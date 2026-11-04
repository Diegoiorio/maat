#!/usr/bin/env bash
# suite.sh — all the plugin suites, one at a time, from the repo root, on Linux (the CI, or a Linux clone).
# Usage: bash tools/suite.sh [<results dir>]      (default: ./esiti)
# Writes <results dir>/<name>.log and <results dir>/riepilogo.txt (one line per suite, like the Linux part of
# giro-completo.sh). Exit 0 if every suite exits 0; 1 if one fails or changes the plugin; 2 if tools/suite.list does
# not match the suites on disk (a suite missing from the list, a tools/*.test.sh missing from the list, or an entry
# with no file) or if the plugin fingerprint is not computable before the first suite.
# Entries: tools/lib/guardia-plugin.sh (suite_file). Guard of the run (1.5.0): the fingerprint of the plugin files
# (guardia_impronta) is taken before the first suite and after each one (the one after a suite is the one before the
# next); a suite after which it differs gets «PLUGIN CAMBIATO» in its line of riepilogo.txt and the exit is 1.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-esiti}
mkdir -p "$OUT" && OUT=$(cd "$OUT" && pwd)
cd "$ROOT" || exit 2
. tools/lib/guardia-plugin.sh || exit 2
LIST=$(tr -d '\r' < tools/suite.list | grep -v '^[[:space:]]*\(#\|$\)')
bad=0
for s in $LIST; do [ -f "$(suite_file "$s")" ] || { echo "suite.list: $s has no file $(suite_file "$s")" >&2; bad=1; }; done
for f in plugins/maat/scripts/*.test.sh plugins/maat/scripts/test-review-surface.sh; do
  [ -e "$f" ] || continue
  n=$(basename "$f"); n=${n%.sh}; n=${n%.test}
  printf '%s\n' $LIST | grep -qxF -- "$n" || { echo "suite.list: $f is not in the list" >&2; bad=1; }
done
for f in tools/*.test.sh; do
  [ -e "$f" ] || continue
  printf '%s\n' $LIST | grep -qxF -- "$f" || { echo "suite.list: $f is not in the list" >&2; bad=1; }
done
[ $bad -eq 0 ] || exit 2
prima=$(guardia_impronta plugins/maat) || { echo "suite.sh: plugin fingerprint not computable (tools/lib/guardia-plugin.sh)" >&2; exit 2; }
# like the Linux run of giro-completo.sh: no WSL (ciclo-worktree.sh would otherwise try to use it)
export FIC_WT_WSL=0
: > "$OUT/riepilogo.txt"
failed=0
for s in $LIST; do
  t0=$(date +%s)
  timeout 5400 bash "$(suite_file "$s")" > "$OUT/$(suite_log "$s").log" 2>&1
  rc=$?
  [ $rc -eq 0 ] || failed=1
  dopo=$(guardia_impronta plugins/maat)   # GUARDIA-DOPO
  cambiato=
  if [ "$dopo" != "$prima" ] || [ "$dopo" = NON-CALCOLABILE ]; then cambiato='PLUGIN CAMBIATO · '; failed=1; fi
  prima=$dopo
  printf '%-22s rc=%-3s %5ss  %s%s\n' "$s" "$rc" "$(( $(date +%s) - t0 ))" "$cambiato" "$(tail -1 "$OUT/$(suite_log "$s").log" | cut -c1-90)" | tee -a "$OUT/riepilogo.txt"
done
echo FINE >> "$OUT/riepilogo.txt"
exit $failed
