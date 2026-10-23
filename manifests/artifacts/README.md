# Artifact manifests

One `<experiment>-<record-id>.manifest.json` per evidence run (for example
`width-cross-check-20261023-170000-3b6fecd.manifest.json`). Each lists the
objects that `klt artifact put` stored in the fleet artifact store: `sha256`,
`size`, an `artifact:` `uri`, and the object `name`. The bytes themselves are
private and never committed; the manifest is public.

- Written by `verification/cross_check.py --mint-record` or by hand
  (`verification/README.md`, "Artifact store").
- Checked by `verification/check_artifact_manifests.py` in `npm run lint`.
- Check the stored bytes from a fleet worker with `klt artifact verify <manifest>`.
- Never write a bucket name, cloud account ID, `s3://` URI or broker URL here.
