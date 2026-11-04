#!/usr/bin/env bash
# suite-parallelo.sh — Maat 1.5.1: all the plugin suites on Linux in parallel, one group of tools/suite-gruppi.list per
# clone (the same groups as the CI jobs), each group with tools/suite.sh --gruppo <k>/<n> in its own clone. From Linux
# or WSL, from any checkout of the repo (the clones are realigned while this runs: the script is read whole first).
# Usage: bash tools/suite-parallelo.sh <results dir> <ref>
#   <ref>: what the clones fetch from their origin (a branch, a tag, a commit sha that origin has).
#   MAAT_LINUX_CLONI="<clone 1> … <clone n>": one clone per group, a path relative to $HOME or absolute (default
#     "maat-linux maat-linux-2 maat-linux-3"). Each one is a git clone whose origin has <ref>; it is realigned
#     (fetch, checkout --detach, clean): no changes inside the clones. Create them once with git clone.
#   MAAT_PARALLELO_FORZA=1: skips the check of what runs on the machine (step 1). MAAT_PARALLELO_LOCK: the lock file
#     (default ${TMPDIR:-/tmp}/maat-suite-parallelo.lock).
# Steps:
#   1 machine busy → exit 3, nothing started: another parallel run (the lock), tools/certifica.sh running (the
#     certificate never runs together with anything), a Maat cycle running on Windows (`driver.py run` in a Windows
#     process, seen from WSL through powershell.exe; outside WSL this part is skipped).
#   2 every clone realigned to <ref>; all at the same commit, otherwise exit 2. <results dir>/clone.txt says which.
#   3 group k in clone k, all at the same time: <results dir>/gruppo-<k>/ (logs and riepilogo.txt of suite.sh, with
#     its guard PLUGIN CAMBIATO on its own clone). In WSL the PATH of the suites is the pure Linux one, as giro-completo.sh.
#   4 RERUN: once every group has ended, each red suite (exit ≠ 0, plugin not changed) runs again alone, one at a time,
#     in its clone (log <name>.rilancio.log, guard before and after). Green alone → «ROSSA SOLO IN PARALLELO» in its
#     line: counted green, but it must go in a group of its own (docs/TESTING-harness.md, «The parallel run»).
#   5 <results dir>/riepilogo.txt: one line per suite in the order of suite.list (group, exit, seconds, last line),
#     then «parallelo: …» and FINE.
# Exit 0 every suite green (also after a rerun); 1 a suite red also alone, a plugin changed, a group that did not end;
# 2 usage or clones; 3 machine busy.
main() {
set -u
local OUT=${1:-} REF=${2:-}
[ -n "$OUT" ] && [ -n "$REF" ] && [ $# -eq 2 ] || { echo "usage: bash tools/suite-parallelo.sh <results dir> <ref>" >&2; return 2; }
local SP; SP=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SP/lib/guardia-plugin.sh" || return 2
command -v flock >/dev/null || { echo "suite-parallelo: flock missing (Linux only)" >&2; return 2; }
mkdir -p "$OUT" && OUT=$(cd "$OUT" && pwd) || return 2
local -a CL=()
local c
for c in ${MAAT_LINUX_CLONI:-maat-linux maat-linux-2 maat-linux-3}; do
  case $c in /*) ;; *) c=$HOME/$c ;; esac
  CL+=("$c")
done
local n=${#CL[@]}

# 1. machine busy
local LOCK=${MAAT_PARALLELO_LOCK:-${TMPDIR:-/tmp}/maat-suite-parallelo.lock}
exec 9> "$LOCK" || return 2
flock -n 9 || { echo "suite-parallelo: OCCUPATA — another parallel run holds $LOCK" >&2; return 3; }
if [ "${MAAT_PARALLELO_FORZA:-0}" != 1 ]; then
  if pgrep -f 'tools/certifica\.sh' >/dev/null 2>&1; then
    echo "suite-parallelo: OCCUPATA — tools/certifica.sh is running (never together with anything)" >&2; return 3
  fi
  local PS=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe w
  if [ -x "$PS" ]; then
    # Windows processes whose command line runs `driver.py run` (a cycle of any project); EncodedCommand: no quoting
    w=$(cat <<'PS1'
@(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'driver\.py"?\s+run(\s|$)' }).Count
PS1
)
    w=$(printf '%s' "$w" | iconv -f utf-8 -t utf-16le | base64 -w0)
    w=$("$PS" -NoProfile -NonInteractive -EncodedCommand "$w" 2>/dev/null | tr -d '\r ')
    [[ $w =~ ^[0-9]+$ ]] || { echo "suite-parallelo: OCCUPATA? — cannot read the Windows processes (MAAT_PARALLELO_FORZA=1 to skip)" >&2; return 3; }
    [ "$w" -eq 0 ] || { echo "suite-parallelo: OCCUPATA — $w Maat cycle(s) running on Windows (driver.py run)" >&2; return 3; }
  fi
fi

# 2. clones realigned, same commit
: > "$OUT/clone.txt"
local i h h0=
for i in "${!CL[@]}"; do
  c=${CL[$i]}
  [ -d "$c/.git" ] || { echo "suite-parallelo: ${c} is not a git clone (git clone <repo> $c)" >&2; return 2; }
  (cd "$c" && git fetch -q origin "$REF" && git checkout -q -f --detach FETCH_HEAD && git clean -qfd) ||
    { echo "suite-parallelo: $c not realigned to $REF" >&2; return 2; }
  h=$(git -C "$c" rev-parse HEAD)
  printf 'clone %s: %s %s\n' "$((i + 1))" "$c" "$(git -C "$c" log -1 --format='%h %s')" >> "$OUT/clone.txt"
  [ -z "$h0" ] && h0=$h
  [ "$h" = "$h0" ] || { echo "suite-parallelo: the clones are not at the same commit (clone.txt)" >&2; return 2; }
done
local ng
ng=$(tr -d '\r' < "${CL[0]}/tools/suite-gruppi.list" | grep -v '^[[:space:]]*\(#\|$\)' | awk '{ print $1 }' | sort -un | tail -1)
[ "$ng" = "$n" ] || { echo "suite-parallelo: $n clones for ${ng:-0} groups of tools/suite-gruppi.list (one clone per group)" >&2; return 2; }

# 3. the groups, at the same time
local LXPATH=$PATH
grep -qi microsoft /proc/version 2>/dev/null && LXPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
local t0=$SECONDS k
local -a PID=()
for i in "${!CL[@]}"; do
  k=$((i + 1))
  rm -rf "$OUT/gruppo-$k"; mkdir -p "$OUT/gruppo-$k"
  (cd "${CL[$i]}" && PATH=$LXPATH bash tools/suite.sh --gruppo "$k/$n" "$OUT/gruppo-$k") > "$OUT/gruppo-$k/suite.out" 2>&1 &
  PID+=($!)
done
for i in "${!PID[@]}"; do wait "${PID[$i]}"; echo $? > "$OUT/gruppo-$((i + 1))/suite.rc"; done
local tpar=$((SECONDS - t0))

# 4-5. reruns and summary
local LIST esito=0 rosse=0 solo=0 s riga g rc f r2 t1 prima dopo nota testa coda
LIST=$(tr -d '\r' < "${CL[0]}/tools/suite.list" | grep -v '^[[:space:]]*\(#\|$\)')
: > "$OUT/riepilogo.txt"
for i in "${!CL[@]}"; do
  k=$((i + 1))
  grep -qx FINE "$OUT/gruppo-$k/riepilogo.txt" 2>/dev/null ||
    { printf 'AVVISO: gruppo %s non concluso (exit %s): %s\n' "$k" "$(cat "$OUT/gruppo-$k/suite.rc")" "$(tail -1 "$OUT/gruppo-$k/suite.out" | cut -c1-120)" >> "$OUT/riepilogo.txt"; esito=1; }
done
for s in $LIST; do
  riga= g=
  for i in "${!CL[@]}"; do
    riga=$(awk -v e="$s" '$1 == e' "$OUT/gruppo-$((i + 1))/riepilogo.txt" 2>/dev/null)
    [ -n "$riga" ] && { g=$((i + 1)); break; }
  done
  [ -n "$riga" ] || { printf '%-28s ASSENTE (in nessun gruppo concluso)\n' "$s" >> "$OUT/riepilogo.txt"; esito=1; continue; }
  [[ $riga =~ ^([^ ]+ +rc=([0-9]+) +[0-9]+s  )(.*)$ ]] ||
    { printf 'g%s %s · RIGA NON LETTA\n' "$g" "$riga" >> "$OUT/riepilogo.txt"; esito=1; continue; }
  rc=${BASH_REMATCH[2]} testa=${BASH_REMATCH[1]} coda=${BASH_REMATCH[3]}
  nota=
  if [[ $coda == *"PLUGIN CAMBIATO"* ]]; then
    esito=1; rosse=$((rosse + 1))
  elif [ "$rc" != 0 ]; then
    # RILANCIO: the red suite alone, in its clone, after every group has ended
    f=$(suite_file "$s"); t1=$SECONDS
    prima=$(guardia_impronta "${CL[$((g - 1))]}/plugins/maat")
    (cd "${CL[$((g - 1))]}" && PATH=$LXPATH FIC_WT_WSL=0 timeout 5400 bash "$f") > "$OUT/gruppo-$g/$(suite_log "$s").rilancio.log" 2>&1
    r2=$?
    dopo=$(guardia_impronta "${CL[$((g - 1))]}/plugins/maat")
    if [ "$dopo" != "$prima" ] || [ "$dopo" = NON-CALCOLABILE ]; then
      nota="ROSSA ANCHE DA SOLA (rc=$r2, $((SECONDS - t1))s, PLUGIN CAMBIATO) · "; esito=1; rosse=$((rosse + 1))
    elif [ $r2 -eq 0 ]; then
      nota="ROSSA SOLO IN PARALLELO (da sola rc=0, $((SECONDS - t1))s) · "; solo=$((solo + 1))
    else
      nota="ROSSA ANCHE DA SOLA (rc=$r2, $((SECONDS - t1))s) · "; esito=1; rosse=$((rosse + 1))
    fi
  fi
  printf 'g%s %s%s%s\n' "$g" "$testa" "$nota" "$coda" >> "$OUT/riepilogo.txt"
done
printf 'parallelo: gruppi=%s · in parallelo %ss · con i rilanci %ss · rosse=%s · rosse-solo-in-parallelo=%s\n' \
  "$n" "$tpar" "$((SECONDS - t0))" "$rosse" "$solo" >> "$OUT/riepilogo.txt"
echo FINE >> "$OUT/riepilogo.txt"
cat "$OUT/riepilogo.txt"
return $esito
}
main "$@"; exit $?
