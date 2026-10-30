#!/usr/bin/env bash
# watch-phase.sh — follows a phase launched by run-phase.sh and prints its progress, one line per
# event. It is the command to give to the Monitor tool of the main chat.
#
#   watch-phase.sh <run-dir> <label>
#
# The reader is phase-events.py, run with the python.sh interpreter (FIC_PY, like the other scripts) and with paths in
# the form Windows programs expect (C:/…, `pwd -W`) or, where `pwd -W` is missing (Linux), in the form of `pwd`: no WSL, which
# may be missing on Windows (D5). Only when no Python at all is found here does it fall back to python3 inside WSL, if WSL exists
# (MSYS_NO_PATHCONV=1: without it, Git Bash rewrites the /mnt/c/... paths passed to wsl.exe).
set -uo pipefail
[ $# -eq 2 ] || { echo "uso: $0 <run-dir> <etichetta>" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
nat() { local d; d=$(cd "$(dirname "$1")" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }) || d=$(dirname "$1"); printf '%s/%s' "$d" "$(basename "$1")"; }
log="$1/log/$2.jsonl"; ex="$1/log/$2.exit"
export PYTHONIOENCODING=utf-8   # ■/✖ on a pipe: Windows Python would write them in cp1252
. "$HERE/python.sh" 2>/dev/null || FIC_PY=""
if [ -n "${FIC_PY:-}" ]; then exec "$FIC_PY" -u "$(nat "$HERE/phase-events.py")" "$(nat "$log")" "$(nat "$ex")"; fi
if command -v wsl >/dev/null 2>&1; then
  to_wsl() { local w; w=$(nat "$1")
    case $w in [A-Za-z]:/*) printf '/mnt/%s%s' "$(printf '%s' "${w:0:1}" | tr 'A-Z' 'a-z')" "${w:2}" ;; *) printf '%s' "$w" ;; esac; }
  MSYS_NO_PATHCONV=1 exec wsl -- python3 -u "$(to_wsl "$HERE/phase-events.py")" "$(to_wsl "$log")" "$(to_wsl "$ex")"
fi
echo "watch-phase: nessun Python (python.sh: imposta FIC_PYTHON) e nessun WSL" >&2
exit 2
