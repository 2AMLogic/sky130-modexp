#!/usr/bin/env bash
#
# Run a globbed set of vendored Loom regression suites, honouring the
# two-manifest skip protocol (#185), and report every suite as run or skipped.
#
# This is the single implementation of the suite-classification algorithm that
# the `guard-hooks` and `merge-pr-suites` jobs in `.github/workflows/ci.yml`
# both use (#338). It used to exist twice, as two ~50-line `run:` heredocs in
# that workflow with 43 byte-identical code lines between them, which meant the
# repo's reading of two external contracts -- upstream's `manifest_names()`
# parsing idiom from `.loom/scripts/tests/check-ci-suite-manifest.sh`, and the
# `#185` consumer-skips supplement in `.github/ci-suites-consumer-skips.txt` --
# had to be re-applied in two places 130 lines apart, with a green build if
# only one was updated (each job consults the manifests only for its own glob,
# so a half-applied change mis-skips silently). The same rule
# `verification/_repo_utils.py` states for Python: one implementation per
# contract.
#
# This script is REPO-OWNED on purpose. It must stay outside `.loom/`, because
# a `chore: resync installed Loom surfaces` commit copies upstream's `.loom/`
# wholesale over this repo's copies with no diff review -- the exact failure
# mode (#107, #126) the two jobs calling this script exist to catch. It is also
# deliberately NOT a wrapper around upstream's `.loom/scripts/tests/run-ci-suites.sh`:
# that runner's `ci-wired.txt` references suite directories absent from this
# consumer repo, so it fails its own precondition check here (the full reason is
# recorded in the `merge-pr-suites` job comment).
#
# Usage:
#   scripts/run-loom-suites.sh --glob PATTERN --label TEXT \
#       --missing-manifest-note TEXT --skip-note TEXT --empty-note TEXT \
#       [--manifest-prefix PREFIX] [--excluded-manifest PATH] \
#       [--consumer-skips PATH] [--dry-run]
#
# Options:
#   --glob PATTERN            Shell glob selecting the suites to consider,
#                             relative to the current directory.
#   --label TEXT              Short name for this suite set, used in the
#                             "no suite was run" error.
#   --missing-manifest-note TEXT
#                             Tail of the `::error::` emitted when the upstream
#                             exclusion manifest is absent -- says what the job
#                             cannot determine without it.
#   --skip-note TEXT          Parenthetical reason printed next to each skipped
#                             suite in the trailing summary list.
#   --empty-note TEXT         Tail of the `::error::` emitted when every globbed
#                             suite landed in a skip list.
#   --manifest-prefix PREFIX  Only exclusion-manifest entries whose first token
#                             starts with PREFIX can name a suite in this glob;
#                             the entry is matched by its basename. Omit (or
#                             pass "") to match the bare first token of every
#                             entry, which is the form upstream uses for suites
#                             living in `.loom/scripts/tests/` itself.
#   --excluded-manifest PATH  Upstream exclusion manifest.
#                             Default: .loom/scripts/tests/ci-excluded.txt
#   --consumer-skips PATH     Repo-owned consumer carve-out supplement (#185).
#                             Default: .github/ci-suites-consumer-skips.txt
#   --dry-run                 Classify and summarise without executing any
#                             suite. Produces byte-identical classification and
#                             summary output to a real run, which is what makes
#                             a local before/after comparison against the old
#                             inline runners possible without paying for the
#                             suites.
#
# Exit status: 0 if every suite that ran passed; 1 if any suite failed, if
# either manifest is missing, if the glob matched nothing, or if every globbed
# suite was skipped.

# Deliberately NOT `set -e`. This script is invoked from a GitHub Actions
# `run:` block, whose default shell is `bash -eo pipefail`; under `-e` a suite
# that exits non-zero would make the `out=$(bash "$f" 2>&1)` assignment abort
# the whole step immediately, before the pass/fail classification below ever
# runs -- silently turning every suite AFTER the first failing one into a false
# "did not run" pass, which is exactly the blind spot the jobs calling this
# script exist to close. `set +e` overrides the inherited runner default so
# every suite runs and each rc is classified explicitly. This rationale is now
# stated once, here, instead of once per copy.
set +e -u -o pipefail

glob=
label=
missing_manifest_note=
skip_note=
empty_note=
manifest_prefix=
excluded_manifest=.loom/scripts/tests/ci-excluded.txt
consumer_skips=.github/ci-suites-consumer-skips.txt
dry_run=0

usage() {
  cat <<'EOF'
Usage: scripts/run-loom-suites.sh --glob PATTERN --label TEXT \
         --missing-manifest-note TEXT --skip-note TEXT --empty-note TEXT \
         [--manifest-prefix PREFIX] [--excluded-manifest PATH] \
         [--consumer-skips PATH] [--dry-run]

Run a globbed set of vendored Loom regression suites, honouring the
two-manifest skip protocol (#185). See the header comment of this file for the
full option reference and for why it is repo-owned.
EOF
}

die() {
  echo "run-loom-suites.sh: $1" >&2
  echo >&2
  usage >&2
  exit 2
}

need_value() {
  # $1 = flag name, $2 = number of remaining args after the flag
  [[ "$2" -ge 1 ]] || die "$1 requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --glob) need_value "$1" "$(($# - 1))"; glob=$2; shift 2 ;;
    --label) need_value "$1" "$(($# - 1))"; label=$2; shift 2 ;;
    --missing-manifest-note) need_value "$1" "$(($# - 1))"; missing_manifest_note=$2; shift 2 ;;
    --skip-note) need_value "$1" "$(($# - 1))"; skip_note=$2; shift 2 ;;
    --empty-note) need_value "$1" "$(($# - 1))"; empty_note=$2; shift 2 ;;
    --manifest-prefix) need_value "$1" "$(($# - 1))"; manifest_prefix=$2; shift 2 ;;
    --excluded-manifest) need_value "$1" "$(($# - 1))"; excluded_manifest=$2; shift 2 ;;
    --consumer-skips) need_value "$1" "$(($# - 1))"; consumer_skips=$2; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$glob" ]] || die "--glob is required"
[[ -n "$label" ]] || die "--label is required"
[[ -n "$missing_manifest_note" ]] || die "--missing-manifest-note is required"
[[ -n "$skip_note" ]] || die "--skip-note is required"
[[ -n "$empty_note" ]] || die "--empty-note is required"

if [[ ! -f "$excluded_manifest" ]]; then
  # Fail loudly rather than fall back to "run everything": without the
  # manifest there's no record of which suites need a binary.
  echo "::error::missing $excluded_manifest -- $missing_manifest_note"
  exit 1
fi
if [[ ! -f "$consumer_skips" ]]; then
  echo "::error::missing $consumer_skips -- cannot tell which suites are carved out for this repo"
  exit 1
fi

# Same parse as check-ci-suite-manifest.sh's manifest_names(): strip `#`
# comments, first whitespace-delimited token is the suite name. With a
# --manifest-prefix, only entries under that prefix can name a suite in this
# job's glob, so match those by basename.
if [[ -n "$manifest_prefix" ]]; then
  excluded_names=$(sed -E 's/#.*$//' "$excluded_manifest" \
    | awk -v p="$manifest_prefix" 'index($1, p) == 1 { n = $1; sub(/.*\//, "", n); print n }')
else
  excluded_names=$(sed -E 's/#.*$//' "$excluded_manifest" | awk 'NF { print $1 }')
fi
consumer_names=$(sed -E 's/#.*$//' "$consumer_skips" | awk 'NF { print $1 }')

# Expand the glob ourselves, with nullglob so an unmatched pattern becomes an
# explicit error below instead of being handed to `bash` as a literal filename.
shopt -s nullglob
# shellcheck disable=SC2206  # word-splitting + globbing is the point here
suites=( $glob )
shopt -u nullglob
if [[ "${#suites[@]}" -eq 0 ]]; then
  echo "::error::no file matched $glob -- the suite directory moved or a resync emptied it"
  exit 1
fi

overall_fail=0
ran=()
skipped=()
for f in "${suites[@]}"; do
  name=${f##*/}
  if grep -qxF -- "$name" <<<"$excluded_names"; then
    # Print the reason verbatim from the manifest, with the suite name
    # removed (reasons may contain `#NNNN`, so take the raw line, not the
    # comment-stripped one).
    reason=$(awk -v n="${manifest_prefix}${name}" '$1 == n { $1 = ""; sub(/^ +/, ""); print; exit }' "$excluded_manifest")
    echo "SKIPPED (listed in $excluded_manifest): $name -- ${reason:-<no reason given>}"
    skipped+=("$name")
    continue
  elif grep -qxF -- "$name" <<<"$consumer_names"; then
    reason=$(awk -v n="$name" '$1 == n { $1 = ""; sub(/^ +/, ""); print; exit }' "$consumer_skips")
    echo "SKIPPED (listed in $consumer_skips): $name -- ${reason:-<no reason given>}"
    skipped+=("$name")
    continue
  fi

  ran+=("$name")
  if [[ "$dry_run" -eq 1 ]]; then
    continue
  fi
  echo "::group::$f"
  out=$(bash "$f" 2>&1)
  rc=$?
  printf '%s\n' "$out"
  echo "::endgroup::"

  # NOTE: the resolve-var suite used to be carved out here, with its cases
  # (i)/(j) tolerated as a known pre-existing failure (#96). That carve-out is
  # gone: #96 established that the ALLOW verdict comes from
  # wt_write_mktemp_same_command_safe(), a deliberate safety feature that
  # reached the vendored hook AFTER those assertions were written, so the
  # suite's own assertions were updated to match and it now passes outright.
  # Every suite is judged on its exit status alone again -- the only sanctioned
  # skip is a whole-suite one, backed by a tracked issue via the two manifests
  # above (#185); do not reintroduce a per-suite rc tolerance, since a
  # carve-out also suppresses that suite's rc entirely.
  if [[ "$rc" -ne 0 ]]; then
    echo "FAILED: $f (exit $rc)"
    overall_fail=1
  fi
done

echo
echo "Summary: ran ${#ran[@]} suite(s), skipped ${#skipped[@]} suite(s) listed in $excluded_manifest or $consumer_skips"
for s in ${skipped[@]+"${skipped[@]}"}; do
  echo "  not run ($skip_note): $s"
done
# Don't let the job go green having run nothing (e.g. a resync that moves every
# suite in this glob into a skip list).
if [[ "${#ran[@]}" -eq 0 ]]; then
  echo "::error::no $label suite was run -- $empty_note"
  exit 1
fi
exit "$overall_fail"
