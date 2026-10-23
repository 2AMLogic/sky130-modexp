"""Fail-closed writer for the fleet artifact store (`klt artifact put`).

New run evidence keeps its raw bytes out of git: this module stores them via
`klt artifact put` and leaves only a manifest (name, size, sha256, `artifact:`
URI per object) to commit. See `verification/README.md` ("Artifact store").

Fail closed: if `$KLT_ARTIFACT_BROKER` is unset, `klt` lacks `artifact put`,
or the broker refuses / is unreachable, `store_files()` raises
`ArtifactStoreError` and the manifest on disk is left exactly as it was. There
is no fallback to committing bytes. The broker URL is read from the
environment by `klt` itself and is never written anywhere by this module.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

BROKER_ENV = "KLT_ARTIFACT_BROKER"
PUT_TIMEOUT_S = 600


class ArtifactStoreError(RuntimeError):
    """Storing evidence failed; nothing may be committed in its place."""


def _run(cmd: list[str], env: dict) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            cmd, capture_output=True, text=True, env=env, timeout=PUT_TIMEOUT_S
        )
    except FileNotFoundError:
        raise ArtifactStoreError(f"`{cmd[0]}` is not on $PATH") from None
    except subprocess.TimeoutExpired:
        raise ArtifactStoreError(f"`{' '.join(cmd[:3])}` timed out") from None


def store_files(
    files: list[tuple[Path, str]],
    manifest_path: Path,
    *,
    klt: str = "klt",
    env: dict | None = None,
) -> list[dict]:
    """Store each `(path, name)` and merge its entry into `manifest_path`.

    Returns the manifest entries for exactly these files. The manifest is
    replaced only after every file stored; on any error it is untouched.
    """
    env = dict(os.environ if env is None else env)
    if not env.get(BROKER_ENV):
        raise ArtifactStoreError(
            f"${BROKER_ENV} is not set -- evidence bytes are not committed "
            "to git as a fallback; run on a fleet worker"
        )
    if _run([klt, "artifact", "put", "--help"], env).returncode != 0:
        raise ArtifactStoreError(
            f"`{klt} artifact put` is unavailable (klt too old?); evidence "
            "bytes are not committed to git as a fallback"
        )

    with tempfile.TemporaryDirectory(prefix="artifact-manifest-") as tmp:
        work = Path(tmp) / "manifest.json"
        if manifest_path.exists():
            shutil.copyfile(manifest_path, work)
        for path, name in files:
            proc = _run(
                [klt, "artifact", "put", "--manifest", str(work), "--name", name, str(path)],
                env,
            )
            if proc.returncode != 0:
                detail = (proc.stderr or proc.stdout).strip().splitlines()[-1:] or ["no output"]
                raise ArtifactStoreError(
                    f"`klt artifact put` failed for {name} (exit {proc.returncode}): {detail[0]}"
                )
        manifest = json.loads(work.read_text(encoding="utf-8"))
        wanted = {name for _, name in files}
        entries = [e for e in manifest["entries"] if e.get("name") in wanted]
        if len(entries) < len(wanted):
            raise ArtifactStoreError("manifest is missing entries for stored files")
        bad = [e["name"] for e in entries if not str(e.get("uri", "")).startswith("artifact:")]
        if bad:
            raise ArtifactStoreError(f"non-`artifact:` uri for {bad}")
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(work, manifest_path)
    return entries
