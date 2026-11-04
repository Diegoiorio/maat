#!/usr/bin/env bash
# giro-completo.sh — all the plugin suites, one at a time: first Linux (clone ~/maat-linux in WSL, realigned to the
# branch), then Windows (the branch worktree). From Git Bash. Results in <results dir>/<linux|windows>/riepilogo.txt.
# Usage: bash tools/giro-completo.sh [--linux-parallelo] [--windows-breve] <results dir> <Windows worktree, /c/… form> <Linux clone branch>
#   MAAT_LINUX_CLONE: the Linux clone, relative to the WSL home (default maat-linux); it must have origin pointing to the repo.
#   --linux-parallelo (1.5.1): the Linux part with tools/suite-parallelo.sh of the worktree, run in WSL: one group of
#     tools/suite-gruppi.list per clone, all at the same time, a suite red only in parallel run again alone. Clones in
#     MAAT_LINUX_CLONI (relative to the WSL home, default "maat-linux maat-linux-2 maat-linux-3"). Its exit 2 (clones)
#     or 3 (machine busy: a cycle on Windows, tools/certifica.sh, another parallel run) stops the run before Windows.
#   --windows-breve (1.5.1): the Windows part runs only the lines of tools/prova-breve-windows.list (about 50 minutes in
#     Git Bash), not every suite. A line: [VAR=value …] <entry of suite.list>.
# Entries of tools/suite.list: resolved by suite_file (tools/lib/guardia-plugin.sh), as tools/suite.sh does.
# Guard of the run (1.5.0), in both loops: the fingerprint of the plugin files (guardia_impronta; on Linux one more
# `wsl` call per suite, on the clone) before the first suite and after each one; a suite after which it differs gets
# «PLUGIN CAMBIATO» in its line of riepilogo.txt and the exit is 1. At the top of both riepilogo.txt an AVVISO line
# if the Linux clone is not at the commit of the worktree, or if the worktree has uncommitted changes under plugins/
# or tools/ (the Linux loop would test another tree).
set -u
PARALLELO=0 BREVE=0
while :; do
  case "${1:-}" in
    --linux-parallelo) PARALLELO=1; shift ;;
    --windows-breve) BREVE=1; shift ;;
    *) break ;;
  esac
done
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
MAAT_W=/mnt/c${WT#/c}

# the lines of the Windows part: every suite, or (--windows-breve) the short list, each entry in suite.list
WIN=$TUTTE
if [ $BREVE -eq 1 ]; then
  WIN=$(tr -d '\r' < "$SP/prova-breve-windows.list" 2>/dev/null | grep -v '^[[:space:]]*\(#\|$\)') ||
    { echo "giro-completo: tools/prova-breve-windows.list missing or empty" >&2; exit 2; }
  while read -r r; do
    printf '%s\n' $TUTTE | grep -qxF -- "${r##* }" ||
      { echo "giro-completo: prova-breve-windows.list: ${r##* } is not in suite.list" >&2; exit 2; }
  done <<< "$WIN"
fi

c_wt=$(git -C "$WT" rev-parse HEAD 2>/dev/null)
avvisi_wt=
[ -z "$(git -C "$WT" status --porcelain -- plugins tools 2>/dev/null)" ] ||
  avvisi_wt="AVVISO: il worktree ha modifiche non committate sotto plugins/ o tools/: il clone Linux non le ha"$'\n'

if [ $PARALLELO -eq 1 ]; then
  # 1'. Linux in parallel: tools/suite-parallelo.sh of the worktree, in WSL; its results on the Windows side
  OUTW=$(cd "$OUT/linux" && { pwd -W 2>/dev/null || pwd; })
  case $OUTW in [A-Za-z]:/*) d=${OUTW:0:1}; OUTW=/mnt/${d,,}${OUTW:2} ;; esac
  wsl -- bash -lc "cd '$MAAT_W' && MAAT_LINUX_CLONI='${MAAT_LINUX_CLONI:-maat-linux maat-linux-2 maat-linux-3}' bash tools/suite-parallelo.sh '$OUTW' '$RAMO'" > "$OUT/linux/parallelo.out" 2>&1
  rp=$?
  c_lx=$(sed -n '1s/^clone 1: [^ ]* \([0-9a-f]*\) .*/\1/p' "$OUT/linux/clone.txt" 2>/dev/null)
  c_lx=$(git -C "$WT" rev-parse --verify -q "${c_lx:-x}^{commit}" 2>/dev/null)
  avvisi=
  [ -n "$c_lx" ] && [ "$c_lx" = "$c_wt" ] ||
    avvisi="AVVISO: cloni Linux a ${c_lx:0:12}, worktree a ${c_wt:0:12}: le due parti non provano lo stesso commit"$'\n'
  avvisi+=$avvisi_wt
  { printf '%s' "$avvisi"; cat "$OUT/linux/riepilogo.txt" 2>/dev/null; } > "$OUT/linux/riepilogo.tmp" &&
    mv "$OUT/linux/riepilogo.tmp" "$OUT/linux/riepilogo.txt"
  printf '%s' "$avvisi" > "$OUT/windows/riepilogo.txt"
  [ $rp -eq 0 ] || esito=1
  if [ $rp -eq 2 ] || [ $rp -eq 3 ]; then
    echo "giro-completo: parte Linux non partita (suite-parallelo.sh exit $rp): $(tail -1 "$OUT/linux/parallelo.out")" |
      tee -a "$OUT/linux/riepilogo.txt" >&2
    exit $rp
  fi
else
  # 1. Linux: throwaway clone, realigned to the branch (manual copies disappear)
  wsl -- bash -lc "cd ~/$LX && git fetch -q origin && git checkout -q -f $RAMO 2>/dev/null || git checkout -q -f -b $RAMO origin/$RAMO; git reset -q --hard origin/$RAMO && git clean -qfd && git log -1 --format='clone: %h %s'" > "$OUT/linux/clone.txt" 2>&1
  avvisi=
  c_lx=$(wsl -- bash -lc "cd ~/$LX && git rev-parse HEAD" 2>/dev/null | tr -d '\r')
  [ -n "$c_lx" ] && [ "$c_lx" = "$c_wt" ] ||
    avvisi+="AVVISO: clone Linux a ${c_lx:0:12}, worktree a ${c_wt:0:12}: le due parti non provano lo stesso commit"$'\n'
  avvisi+=$avvisi_wt
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
fi

# 2. Windows: worktree. In WSL on the worktree (/mnt/c/…): the suites that need rsync and flock (test-fast,
# counterproof, vitest-classify, comandi-equivalenza: since 1.5.0 it reads no git history, only its frozen reference,
# so the .git of the worktree pointing to C:/ no longer matters) and tools/oracolo.test.sh (~70 min on the corpus in
# Git Bash; its ref cases are SKIPPED there, the .git of the worktree points to C:/, and run in the Linux loop).
# Limit per suite: 5400 s on Linux and in WSL, 18000 s in Git Bash (1.5.0: driver.test.sh ~4 h and
# tools/esempi-equiv.test.sh ~1 h 45 min there; at 5400 s both were cut).
# A line of the short list may start with VAR=value words: the suite runs with them (env), and its line says so.
WSL_SUITE=" test-fast counterproof vitest-classify comandi-equivalenza tools/oracolo.test.sh "
[ $BREVE -eq 1 ] && echo "prova breve: tools/prova-breve-windows.list" >> "$OUT/windows/riepilogo.txt"
prima=$(guardia_impronta "$WT/plugins/maat")
while read -r r; do
  [ -n "$r" ] || continue
  s=${r##* } envs=
  [ "$s" = "$r" ] || envs=${r% *}
  f=$(suite_file "$s")
  t0=$(date +%s)
  case "$WSL_SUITE" in
    *" $s "*) dove=WSL; wsl -- bash -lc "cd $MAAT_W && $envs timeout 5400 bash $f" > "$OUT/windows/$(suite_log "$s").log" 2>&1 ;;
    *) dove=GitBash; (cd "$WT" && env $envs timeout 18000 bash "$f") > "$OUT/windows/$(suite_log "$s").log" 2>&1 ;;
  esac
  rc=$?
  dopo=$(guardia_impronta "$WT/plugins/maat")
  cambiato=
  if [ "$dopo" != "$prima" ] || [ "$dopo" = NON-CALCOLABILE ]; then cambiato='PLUGIN CAMBIATO · '; esito=1; fi
  prima=$dopo
  printf '%-22s %-7s rc=%-3s %5ss  %s%s%s\n' "$s" "$dove" "$rc" "$(( $(date +%s) - t0 ))" "$cambiato" "${envs:+$envs · }" "$(grep -v 'screen size' "$OUT/windows/$(suite_log "$s").log" | tail -1 | cut -c1-90)" >> "$OUT/windows/riepilogo.txt"
done <<< "$WIN"
echo FINE >> "$OUT/windows/riepilogo.txt"
exit $esito
