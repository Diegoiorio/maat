#!/usr/bin/env bash
# suite.sh — all the plugin suites, one at a time, from the repo root, on Linux (the CI, or a Linux clone).
# Usage: bash tools/suite.sh [<results dir>]      (default: ./esiti)
# Writes <results dir>/<name>.log and <results dir>/riepilogo.txt (one line per suite, like the Linux part of
# giro-completo.sh). Exit 0 if every suite exits 0; 1 if one fails; 2 if tools/suite.list does not match the suites on
# disk (a suite missing from the list, or a name with no file).
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-esiti}
mkdir -p "$OUT" && OUT=$(cd "$OUT" && pwd)
cd "$ROOT" || exit 2
file_of() { [ "$1" = test-review-surface ] && echo plugins/maat/scripts/test-review-surface.sh || echo "plugins/maat/scripts/$1.test.sh"; }
LIST=$(tr -d '\r' < tools/suite.list | grep -v '^[[:space:]]*\(#\|$\)')
bad=0
for s in $LIST; do [ -f "$(file_of "$s")" ] || { echo "suite.list: $s has no file $(file_of "$s")" >&2; bad=1; }; done
for f in plugins/maat/scripts/*.test.sh plugins/maat/scripts/test-review-surface.sh; do
  n=$(basename "$f"); n=${n%.sh}; n=${n%.test}
  printf '%s\n' $LIST | grep -qxF -- "$n" || { echo "suite.list: $f is not in the list" >&2; bad=1; }
done
[ $bad -eq 0 ] || exit 2
# like the Linux run of giro-completo.sh: no WSL (ciclo-worktree.sh would otherwise try to use it)
export FIC_WT_WSL=0
: > "$OUT/riepilogo.txt"
failed=0
for s in $LIST; do
  t0=$(date +%s)
  timeout 5400 bash "$(file_of "$s")" > "$OUT/$s.log" 2>&1
  rc=$?
  [ $rc -eq 0 ] || failed=1
  printf '%-22s rc=%-3s %5ss  %s\n' "$s" "$rc" "$(( $(date +%s) - t0 ))" "$(tail -1 "$OUT/$s.log" | cut -c1-90)" | tee -a "$OUT/riepilogo.txt"
done
echo FINE >> "$OUT/riepilogo.txt"
exit $failed
