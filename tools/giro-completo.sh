#!/usr/bin/env bash
# giro-completo.sh — all the plugin suites, one at a time: first Linux (clone ~/maat-linux in WSL, realigned to the
# branch), then Windows (the branch worktree). From Git Bash. Results in <results dir>/<linux|windows>/riepilogo.txt.
# Usage: bash tools/giro-completo.sh <results dir> <Windows worktree, /c/… form> <Linux clone branch>
#   MAAT_LINUX_CLONE: the Linux clone, relative to the WSL home (default maat-linux); it must have origin pointing to the repo.
set -u
OUT=${1:?cartella esiti}
WT=${2:?worktree Windows (forma /c/…)}
RAMO=${3:?ramo del clone Linux}
LX=${MAAT_LINUX_CLONE:-maat-linux}
SP=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT/linux" "$OUT/windows"
TUTTE="maat-paths maat-config gates finalize ciclo-worktree context-pack cycle-report harness-merge guard stop-hook
  blocks-independent phase-events test-review-surface plan-check bash-node genericita maat-doctor senza-wsl spazi
  session-start test-fast counterproof comandi-equivalenza vitest-classify cycle-state run-phase driver"

# 1. Linux: throwaway clone, realigned to the branch (manual copies disappear)
wsl -- bash -lc "cd ~/$LX && git fetch -q origin && git checkout -q -f $RAMO 2>/dev/null || git checkout -q -f -b $RAMO origin/$RAMO; git reset -q --hard origin/$RAMO && git clean -qfd && git log -1 --format='clone: %h %s'" > "$OUT/linux/clone.txt" 2>&1
for s in $TUTTE; do
  f=plugins/maat/scripts/$s.test.sh; [ "$s" = test-review-surface ] && f=plugins/maat/scripts/test-review-surface.sh
  t0=$(date +%s)
  wsl -- bash -lc "cd ~/$LX && PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin FIC_WT_WSL=0 timeout 5400 bash $f" > "$OUT/linux/$s.log" 2>&1
  rc=$?
  printf '%-22s rc=%-3s %5ss  %s\n' "$s" "$rc" "$(( $(date +%s) - t0 ))" "$(tail -1 "$OUT/linux/$s.log" | cut -c1-90)" >> "$OUT/linux/riepilogo.txt"
done
echo FINE >> "$OUT/linux/riepilogo.txt"

# 2. Windows: worktree (comandi-equivalenza only from the Linux clone: the worktree's .git points to C:/)
WSL_SUITE=" test-fast counterproof vitest-classify "
MAAT_DIR=$WT MAAT_W=/mnt/c${WT#/c}
for s in $TUTTE; do
  [ "$s" = comandi-equivalenza ] && continue
  f=plugins/maat/scripts/$s.test.sh; [ "$s" = test-review-surface ] && f=plugins/maat/scripts/test-review-surface.sh
  t0=$(date +%s)
  case "$WSL_SUITE" in
    *" $s "*) dove=WSL; wsl -- bash -lc "cd $MAAT_W && timeout 5400 bash $f" > "$OUT/windows/$s.log" 2>&1 ;;
    *) dove=GitBash; (cd "$WT" && timeout 5400 bash "$f") > "$OUT/windows/$s.log" 2>&1 ;;
  esac
  rc=$?
  printf '%-22s %-7s rc=%-3s %5ss  %s\n' "$s" "$dove" "$rc" "$(( $(date +%s) - t0 ))" "$(grep -v 'screen size' "$OUT/windows/$s.log" | tail -1 | cut -c1-90)" >> "$OUT/windows/riepilogo.txt"
done
echo FINE >> "$OUT/windows/riepilogo.txt"
