#!/usr/bin/env bash
# senza-wsl.sh — the PATH without wsl shared by the suites that test a machine without WSL (Maat 1.8.0):
# maat-doctor.test.sh, senza-wsl.test.sh, phase-events.test.sh.
#   . "$HERE/lib/senza-wsl.sh"; PATH_SENZA_WSL=$(senza_wsl)
# To be sourced, not run; it reads $PATH and $FIC_PY (the Python of the suite, the one the code under test uses).
# A folder of $PATH is left out when any of these finds a wsl in it: bash (`-e` of wsl.exe and wsl, the listing of
# the folder, `command -v` in a new bash with that folder only, as gates.sh looks it up) and that Python (shutil.which
# of wsl and wsl.exe, os.listdir), as the doctor looks it up. Why all of them: an app execution alias of WindowsApps
# is a reparse point that Git Bash does not always stat, while Python's shutil.which finds it — on some CI runners the
# folder stayed, and the doctor (1.6.1, 1.7.0, 1.8.0) or gates.sh (1.8.0) found wsl on the reduced PATH. Call it right
# before each case that uses it, not once at the start.
senza_wsl_cygm() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
senza_wsl() {
  local out="" d i=0 dirs=() py
  IFS=: read -ra dirs <<< "$PATH"
  py=$(for d in ${dirs[@]+"${dirs[@]}"}; do printf '%s\n' "$(senza_wsl_cygm "$d")"; done | "$FIC_PY" -c 'import os, shutil, sys
for d in sys.stdin.read().split("\n")[:-1]:
    try:
        ns = [n.lower() for n in os.listdir(d)]
    except OSError:
        ns = []
    w = d and (shutil.which("wsl", path=d) or shutil.which("wsl.exe", path=d) or "wsl" in ns or "wsl.exe" in ns)
    print(1 if w else 0)' | tr -d '\r')
  for d in ${dirs[@]+"${dirs[@]}"}; do
    i=$((i + 1))
    [ "$(printf '%s\n' "$py" | sed -n "${i}p")" = 0 ] || continue   # SENZA-WSL-PY
    { [ -e "$d/wsl.exe" ] || [ -e "$d/wsl" ] || ls -A "$d" 2>/dev/null | grep -qixE 'wsl(\.exe)?'; } && continue
    [ -z "$(PATH=$d "$BASH" -c 'command -v wsl || command -v wsl.exe' 2>/dev/null)" ] || continue   # SENZA-WSL-BASH
    out+="${out:+:}$d"
  done
  printf '%s' "$out"
}
