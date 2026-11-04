#!/usr/bin/env bash
# suite.sh — all the plugin suites, one at a time, from the repo root: the CI (Linux, macOS, Windows) or a Linux clone.
# Usage: bash tools/suite.sh [--gruppi <file>] [--gruppo <k>/<n>] [<results dir>]      (default: ./esiti)
#   --gruppi <file> (1.6.0): the groups file, a path from the repo root (default tools/suite-gruppi.list; Windows:
#   tools/suite-gruppi-windows.list). A line is «<g> [VAR=value …] <entry>» (the entry runs in group g, with those
#   variables in its environment, shown as «[VAR=value …]» in its line of riepilogo.txt) or «- <entry> <reason …>» (the entry is left out on that platform: counted as
#   covered, and written in riepilogo.txt as «<entry> ESCLUSA: <reason>»; in a --gruppo run only by group 1).
#   --gruppo <k>/<n> (1.5.1): only the suites of group k of the groups file, in the order of suite.list (one
#   CI job per group; tools/suite-parallelo.sh, one Linux clone per group). The file must have exactly the groups
#   1..n: exit 2 if an entry of suite.list is in no line or in two, an entry of the file is not in suite.list, or a
#   group is outside 1..n or has no suite. The CI passes n = strategy.job-total, the number of jobs of its matrix, so a
#   matrix with fewer or more jobs than the file has groups is red (tools/suite.test.sh checks .github/workflows/ci.yml).
#   --gruppi without --gruppo: every entry of the file that is not left out, with the same checks (n = its groups).
# Writes <results dir>/<name>.log and <results dir>/riepilogo.txt (one line per suite, like the Linux part of
# giro-completo.sh). Exit 0 if every suite exits 0; 1 if one fails or changes the plugin; 2 if tools/suite.list does
# not match the suites on disk (a suite missing from the list, a tools/*.test.sh missing from the list, or an entry
# with no file) or if the plugin fingerprint is not computable before the first suite.
# Entries: tools/lib/guardia-plugin.sh (suite_file). Guard of the run (1.5.0): the fingerprint of the plugin files
# (guardia_impronta) is taken before the first suite and after each one (the one after a suite is the one before the
# next); a suite after which it differs gets «PLUGIN CAMBIATO» in its line of riepilogo.txt and the exit is 1.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GRUPPO= GRUPPI=
uso() { echo "usage: bash tools/suite.sh [--gruppi <file>] [--gruppo <k>/<n>] [<results dir>]   (1 <= k <= n)" >&2; exit 2; }
while :; do
  case "${1:-}" in
    --gruppo) GRUPPO=${2:-}
      [[ $GRUPPO =~ ^[1-9][0-9]*/[1-9][0-9]*$ ]] && [ "${GRUPPO%/*}" -le "${GRUPPO#*/}" ] || uso
      shift 2 ;;
    --gruppi) [ -n "${2:-}" ] || uso; GRUPPI=$2; shift 2 ;;
    *) break ;;
  esac
done
[ -n "$GRUPPO$GRUPPI" ] && GRUPPI=${GRUPPI:-tools/suite-gruppi.list}
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
declare -A VARS=()   # entry → its «VAR=value …» from the groups file
ESCLUSE=""           # «<entry> ESCLUSA: <reason>» lines, in the order of the file
if [ -n "$GRUPPI" ]; then
  gf=$(basename "$GRUPPI")
  G=$(tr -d '\r' < "$GRUPPI" 2>/dev/null | grep -v '^[[:space:]]*\(#\|$\)') ||
    { echo "$gf: missing or empty" >&2; exit 2; }
  n=$(printf '%s\n' "$G" | awk '$1 != "-" { print $1 }' | sort -u | grep -c .)
  [ -n "$GRUPPO" ] && n=${GRUPPO#*/}
  k=${GRUPPO%/*}
  E=""   # «<g> <entry>», g = - for an entry left out
  while read -r g r; do
    p=(); read -ra p <<< "$r"
    if [ "$g" = - ]; then
      e=${p[0]:-}
      if [ ${#p[@]} -lt 2 ]; then echo "$gf: bad line: - $r (- <entry> <reason>)" >&2; bad=1; continue; fi
      ESCLUSE+="$e ESCLUSA: ${p[*]:1}"$'\n'
    else
      ok=1 e= v=()
      if [ ${#p[@]} -ge 1 ]; then e=${p[${#p[@]}-1]} v=("${p[@]:0:${#p[@]}-1}"); fi
      for x in ${v[@]+"${v[@]}"}; do [[ $x =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*$ ]] || ok=0; done
      if ! [[ $g =~ ^[0-9]+$ ]] || [ -z "$e" ] || [ $ok = 0 ] || [[ $e == *=* ]]; then
        echo "$gf: bad line: $g $r" >&2; bad=1; continue
      fi
      [ "$g" -ge 1 ] && [ "$g" -le "$n" ] || { echo "$gf: $e is in group $g, outside 1..$n" >&2; bad=1; }
      [ ${#v[@]} -eq 0 ] || VARS[$e]="${v[*]}"
    fi
    printf '%s\n' $LIST | grep -qxF -- "$e" || { echo "$gf: $e is not in suite.list" >&2; bad=1; }
    E+="$g $e"$'\n'
  done <<< "$G"
  for s in $LIST; do
    c=$(printf '%s' "$E" | awk -v e="$s" '$2 == e' | wc -l)
    [ "$c" -eq 1 ] || { echo "$gf: $s is in $c lines (exactly one is required: a group, or - for left out)" >&2; bad=1; }
  done
  for g in $(seq 1 "$n"); do
    printf '%s' "$E" | awk -v g="$g" '$1 == g' | grep -q . || { echo "$gf: group $g has no suite" >&2; bad=1; }
  done
  [ $bad -eq 0 ] || exit 2
  if [ -n "$GRUPPO" ]; then
    LIST=$(printf '%s' "$E" | awk -v g="$k" '$1 == g { print $2 }' | grep -xF -f - <(printf '%s\n' $LIST))   # order of suite.list
    [ "$k" = 1 ] || ESCLUSE=""
  else
    LIST=$(printf '%s' "$E" | awk '$1 != "-" { print $2 }' | grep -xF -f - <(printf '%s\n' $LIST))
  fi
fi
prima=$(guardia_impronta plugins/maat) || { echo "suite.sh: plugin fingerprint not computable (tools/lib/guardia-plugin.sh)" >&2; exit 2; }
# like the Linux run of giro-completo.sh: no WSL (ciclo-worktree.sh would otherwise try to use it)
export FIC_WT_WSL=0
: > "$OUT/riepilogo.txt"
[ -z "$ESCLUSE" ] || printf '%s' "$ESCLUSE" | tee -a "$OUT/riepilogo.txt"
failed=0
for s in $LIST; do
  t0=$(date +%s)
  read -ra va <<< "${VARS[$s]:-}"
  env ${va[@]+"${va[@]}"} timeout 5400 bash "$(suite_file "$s")" > "$OUT/$(suite_log "$s").log" 2>&1
  rc=$?
  [ $rc -eq 0 ] || failed=1
  dopo=$(guardia_impronta plugins/maat)   # GUARDIA-DOPO
  cambiato=
  if [ "$dopo" != "$prima" ] || [ "$dopo" = NON-CALCOLABILE ]; then cambiato='PLUGIN CAMBIATO · '; failed=1; fi
  prima=$dopo
  printf '%-22s rc=%-3s %5ss  %s%s%s\n' "$s" "$rc" "$(( $(date +%s) - t0 ))" "$cambiato" "${VARS[$s]:+[${VARS[$s]}] }" "$(tail -1 "$OUT/$(suite_log "$s").log" | cut -c1-90)" | tee -a "$OUT/riepilogo.txt"
done
echo FINE >> "$OUT/riepilogo.txt"
exit $failed
