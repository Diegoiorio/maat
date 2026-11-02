#!/usr/bin/env bash
# file-lasciato-mutato.sh <worktree> [--file <path> --from <text> --to <text>]
# Defect: a counterproof that died halfway and left the file mutated. As the review worker does
# (SKILL.md, «Counterproofs», steps 2-3): copy of the file in <run-dir>/counterproof/<path>, sidecar
# <path>.meta with path, base, hash of the copy and hash of the mutated file; then the named mutation in the file.
# Default: the same boundary mutation as mutazione-non-coperta.sh (utils/goals.ts, `<=` → `<`).
# The file is NOT attributed to the feature: it is the leftover of a counterproof, not code.
# Who catches it: the review worker (step 1: restore of the leftover copies, only if the hash matches).
. "$(dirname "$0")/_lib.sh"
F=modules/app/apps/admin/utils/goals.ts
FROM='Math.abs(cents) <= COMPACT_THRESHOLD_CENTS'
TO='Math.abs(cents) < COMPACT_THRESHOLD_CENTS'
while [ $# -gt 0 ]; do
  case "$1" in
    --file) F=${2:-}; shift 2 ;;
    --from) FROM=${2:-}; shift 2 ;;
    --to) TO=${2:-}; shift 2 ;;
    *) die "$(msg inject.unknown_opt opt="$1")" ;;
  esac
done
[ -f "$WT/$F" ] || die "$(msg inject.no_file f="$F")"
base=$(tr -d '\r\n ' 2>/dev/null < "$RUN/base.txt")
[ -n "$base" ] || base=$(git -C "$WT" rev-parse HEAD)
CP="$RUN/counterproof/$F"
[ -e "$CP" ] && die "$(msg inject.cp_exists cp="$CP")"
mkdir -p "$(dirname "$CP")" && cp "$WT/$F" "$CP" || die "$(msg inject.copy_failed cp="$CP")"
copy_sha=$(sha256sum < "$CP" | cut -c1-64)
replace_once "$F" "$FROM" "$TO"
mut_sha=$(sha256sum < "$WT/$F" | cut -c1-64)
printf 'path: %s\nbase: %s\ncopy_sha256: %s\nreverted_sha256: %s\nmutation: %s -> %s\n' \
  "$F" "$base" "$copy_sha" "$mut_sha" "$FROM" "$TO" > "$CP.meta"
inj_done "$F $(msg inject.mutated)"
