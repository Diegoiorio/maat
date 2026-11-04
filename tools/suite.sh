#!/usr/bin/env bash
# suite.sh — all the plugin suites, one at a time, from the repo root, on Linux (the CI, or a Linux clone).
# Usage: bash tools/suite.sh [--gruppo <k>/<n>] [<results dir>]      (default: ./esiti)
#   --gruppo <k>/<n> (1.5.1): only the suites of group k of tools/suite-gruppi.list, in the order of suite.list (one
#   CI job per group; tools/suite-parallelo.sh, one Linux clone per group). The file must have exactly the groups
#   1..n: exit 2 if an entry of suite.list is in no group or in two, an entry of the file is not in suite.list, or a
#   group is outside 1..n or has no suite. The CI passes n = strategy.job-total, the number of jobs of its matrix, so a
#   matrix with fewer or more jobs than the file has groups is red (tools/suite.test.sh checks .github/workflows/ci.yml).
# Writes <results dir>/<name>.log and <results dir>/riepilogo.txt (one line per suite, like the Linux part of
# giro-completo.sh). Exit 0 if every suite exits 0; 1 if one fails or changes the plugin; 2 if tools/suite.list does
# not match the suites on disk (a suite missing from the list, a tools/*.test.sh missing from the list, or an entry
# with no file) or if the plugin fingerprint is not computable before the first suite.
# Entries: tools/lib/guardia-plugin.sh (suite_file). Guard of the run (1.5.0): the fingerprint of the plugin files
# (guardia_impronta) is taken before the first suite and after each one (the one after a suite is the one before the
# next); a suite after which it differs gets «PLUGIN CAMBIATO» in its line of riepilogo.txt and the exit is 1.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GRUPPO=
if [ "${1:-}" = --gruppo ]; then
  GRUPPO=${2:-}
  [[ $GRUPPO =~ ^[1-9][0-9]*/[1-9][0-9]*$ ]] && [ "${GRUPPO%/*}" -le "${GRUPPO#*/}" ] ||
    { echo "usage: bash tools/suite.sh [--gruppo <k>/<n>] [<results dir>]   (1 <= k <= n)" >&2; exit 2; }
  shift 2
fi
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
if [ -n "$GRUPPO" ]; then
  k=${GRUPPO%/*} n=${GRUPPO#*/}
  G=$(tr -d '\r' < tools/suite-gruppi.list 2>/dev/null | grep -v '^[[:space:]]*\(#\|$\)') ||
    { echo "suite-gruppi.list: missing or empty" >&2; exit 2; }
  while read -r g e x; do
    if ! [[ $g =~ ^[0-9]+$ ]] || [ -z "$e" ] || [ -n "$x" ]; then
      echo "suite-gruppi.list: bad line: $g $e $x" >&2; bad=1; continue
    fi
    [ "$g" -ge 1 ] && [ "$g" -le "$n" ] || { echo "suite-gruppi.list: $e is in group $g, outside 1..$n" >&2; bad=1; }
    printf '%s\n' $LIST | grep -qxF -- "$e" || { echo "suite-gruppi.list: $e is not in suite.list" >&2; bad=1; }
  done <<< "$G"
  for s in $LIST; do
    c=$(printf '%s\n' "$G" | awk -v e="$s" '$2 == e' | wc -l)
    [ "$c" -eq 1 ] || { echo "suite-gruppi.list: $s is in $c groups (exactly one is required)" >&2; bad=1; }
  done
  for g in $(seq 1 "$n"); do
    printf '%s\n' "$G" | awk -v g="$g" '$1 == g' | grep -q . || { echo "suite-gruppi.list: group $g has no suite" >&2; bad=1; }
  done
  [ $bad -eq 0 ] || exit 2
  LIST=$(printf '%s\n' "$G" | awk -v g="$k" '$1 == g { print $2 }' | grep -xF -f - <(printf '%s\n' $LIST))   # order of suite.list
fi
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
