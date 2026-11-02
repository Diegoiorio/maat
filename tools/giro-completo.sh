#!/usr/bin/env bash
# giro-completo.sh — all the plugin suites, one at a time: first Linux (clone ~/maat-linux in WSL, realigned to the
# branch), then Windows (the branch worktree). From Git Bash. Results in <results dir>/<linux|windows>/riepilogo.txt.
# Usage: bash tools/giro-completo.sh <results dir> <Windows worktree, /c/… form> <Linux clone branch>
#   MAAT_LINUX_CLONE: the Linux clone, relative to the WSL home (default maat-linux); it must have origin pointing to the repo.
# Entries of tools/suite.list: resolved by suite_file (tools/lib/guardia-plugin.sh), as tools/suite.sh does.
# Guard of the run (1.5.0), in both loops: the fingerprint of the plugin files (guardia_impronta; on Linux one more
# `wsl` call per suite, on the clone) before the first suite and after each one; a suite after which it differs gets
# «PLUGIN CAMBIATO» in its line of riepilogo.txt and the exit is 1. At the top of both riepilogo.txt an AVVISO line
# if the Linux clone is not at the commit of the worktree, or if the worktree has uncommitted changes under plugins/
# or tools/ (the Linux loop would test another tree).
set -u
OUT=${1:?cartella esiti}
WT=${2:?worktree Windows (forma /c/…)}
RAMO=${3:?ramo del clone Linux}
LX=${MAAT_LINUX_CLONE:-maat-linux}
SP=$(cd "$(dirname "$0")" && pwd)
. "$SP/lib/guardia-plugin.sh" || exit 2
mkdir -p "$OUT/linux" "$OUT/windows"
TUTTE=$(tr -d '\r' < "$SP/suite.list" | grep -v '^[[:space:]]*\(#\|$\)')   # the same list as tools/suite.sh (CI)
esito=0
LXPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 1. Linux: throwaway clone, realigned to the branch (manual copies disappear)
wsl -- bash -lc "cd ~/$LX && git fetch -q origin && git checkout -q -f $RAMO 2>/dev/null || git checkout -q -f -b $RAMO origin/$RAMO; git reset -q --hard origin/$RAMO && git clean -qfd && git log -1 --format='clone: %h %s'" > "$OUT/linux/clone.txt" 2>&1
avvisi=
c_lx=$(wsl -- bash -lc "cd ~/$LX && git rev-parse HEAD" 2>/dev/null | tr -d '\r')
c_wt=$(git -C "$WT" rev-parse HEAD 2>/dev/null)
[ -n "$c_lx" ] && [ "$c_lx" = "$c_wt" ] ||
  avvisi+="AVVISO: clone Linux a ${c_lx:0:12}, worktree a ${c_wt:0:12}: le due parti non provano lo stesso commit"$'\n'
[ -z "$(git -C "$WT" status --porcelain -- plugins tools 2>/dev/null)" ] ||
  avvisi+="AVVISO: il worktree ha modifiche non committate sotto plugins/ o tools/: il clone Linux non le ha"$'\n'
printf '%s' "$avvisi" > "$OUT/linux/riepilogo.txt"
printf '%s' "$avvisi" > "$OUT/windows/riepilogo.txt"

lx_impronta() { wsl -- bash -lc "cd ~/$LX && PATH=$LXPATH bash tools/lib/guardia-plugin.sh plugins/maat" 2>/dev/null | tr -d '\r'; }
prima=$(lx_impronta)
for s in $TUTTE; do
  f=$(suite_file "$s")
  t0=$(date +%s)
  wsl -- bash -lc "cd ~/$LX && PATH=$LXPATH FIC_WT_WSL=0 timeout 5400 bash $f" > "$OUT/linux/$(suite_log "$s").log" 2>&1
  rc=$?
  dopo=$(lx_impronta)
  cambiato=
  if [ "$dopo" != "$prima" ] || ! [[ $dopo =~ ^[0-9a-f]{64}$ ]]; then cambiato='PLUGIN CAMBIATO · '; esito=1; fi
  prima=$dopo
  printf '%-22s rc=%-3s %5ss  %s%s\n' "$s" "$rc" "$(( $(date +%s) - t0 ))" "$cambiato" "$(tail -1 "$OUT/linux/$(suite_log "$s").log" | cut -c1-90)" >> "$OUT/linux/riepilogo.txt"
done
echo FINE >> "$OUT/linux/riepilogo.txt"

# 2. Windows: worktree (comandi-equivalenza only from the Linux clone: the worktree's .git points to C:/)
WSL_SUITE=" test-fast counterproof vitest-classify "
MAAT_DIR=$WT MAAT_W=/mnt/c${WT#/c}
prima=$(guardia_impronta "$WT/plugins/maat")
for s in $TUTTE; do
  [ "$s" = comandi-equivalenza ] && continue
  f=$(suite_file "$s")
  t0=$(date +%s)
  case "$WSL_SUITE" in
    *" $s "*) dove=WSL; wsl -- bash -lc "cd $MAAT_W && timeout 5400 bash $f" > "$OUT/windows/$(suite_log "$s").log" 2>&1 ;;
    *) dove=GitBash; (cd "$WT" && timeout 5400 bash "$f") > "$OUT/windows/$(suite_log "$s").log" 2>&1 ;;
  esac
  rc=$?
  dopo=$(guardia_impronta "$WT/plugins/maat")
  cambiato=
  if [ "$dopo" != "$prima" ] || [ "$dopo" = NON-CALCOLABILE ]; then cambiato='PLUGIN CAMBIATO · '; esito=1; fi
  prima=$dopo
  printf '%-22s %-7s rc=%-3s %5ss  %s%s\n' "$s" "$dove" "$rc" "$(( $(date +%s) - t0 ))" "$cambiato" "$(grep -v 'screen size' "$OUT/windows/$(suite_log "$s").log" | tail -1 | cut -c1-90)" >> "$OUT/windows/riepilogo.txt"
done
echo FINE >> "$OUT/windows/riepilogo.txt"
exit $esito
