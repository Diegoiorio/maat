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
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/maat-msg.sh"   # messages (1.4.0): only the two errors below; the catalog is read at the first one
[ $# -eq 2 ] || { echo "$(msg watch-phase.usage script="$0")" >&2; exit 2; }
nat() { local d; d=$(cd "$(dirname "$1")" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }) || d=$(dirname "$1"); printf '%s/%s' "$d" "$(basename "$1")"; }
log="$1/log/$2.jsonl"; ex="$1/log/$2.exit"
export PYTHONIOENCODING=utf-8   # ■/✖ on a pipe: Windows Python would write them in cp1252
. "$HERE/python.sh" 2>/dev/null || FIC_PY=""
if [ -n "${FIC_PY:-}" ]; then exec "$FIC_PY" -u "$(nat "$HERE/phase-events.py")" "$(nat "$log")" "$(nat "$ex")"; fi
if command -v wsl >/dev/null 2>&1; then
  to_wsl() { local w; w=$(nat "$1")
    case $w in [A-Za-z]:/*) printf '/mnt/%s%s' "$(printf '%s' "${w:0:1}" | tr 'A-Z' 'a-z')" "${w:2}" ;; *) printf '%s' "$w" ;; esac; }
  # wsl.exe does not pass the environment: a MAAT_LINGUA of the caller goes on the command line, resolved (it|en).
  # Unset, it is not resolved here (without a Python here maat_lingua cannot read maat.json and would say en):
  # phase-events.py reads the `lingua` of maat.json itself, inside WSL
  lg=(); [ -z "${MAAT_LINGUA:-}" ] || lg=(env "MAAT_LINGUA=$(maat_lingua)")
  MSYS_NO_PATHCONV=1 exec wsl -- ${lg[@]+"${lg[@]}"} python3 -u "$(to_wsl "$HERE/phase-events.py")" "$(to_wsl "$log")" "$(to_wsl "$ex")"
fi
echo "watch-phase: $(msg watch-phase.no_python)" >&2
exit 2
