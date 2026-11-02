#!/usr/bin/env bash
# mutazione-non-coperta.sh <worktree> [--file <path> --from <text> --to <text>]
# Defect: a behaviour mutation that no test sees (surviving mutant). Default: the
# boundary of the compact form of amounts in utils/goals.ts, `<=` → `<` (present, identical and unique
# at all the corpus bases): only the value exactly at the threshold changes. Attributed to the feature
# (touched.txt) if a code phase precedes the replayed one.
# Who catches it: the review (a change without a test covering it) and the mutation counterproofs.
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
[ -n "$F" ] && [ -n "$FROM" ] && [ "$FROM" != "$TO" ] || die "$(msg inject.bad_mutation)"
replace_once "$F" "$FROM" "$TO"
mark_touched "$F"
inj_done "$F: «$FROM» → «$TO»"
