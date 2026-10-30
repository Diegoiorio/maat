#!/usr/bin/env bash
# watch-phase.sh — segue una fase lanciata da run-phase.sh e ne stampa l'avanzamento, una riga per
# evento. E' il comando da dare allo strumento Monitor della chat principale.
#
#   watch-phase.sh <run-dir> <etichetta>
#
# Il lettore e' phase-events.py, con l'interprete di python.sh (FIC_PY, come gli altri script) e i percorsi nella
# forma dei programmi Windows (C:/…, `pwd -W`) o, dove `pwd -W` non c'e' (Linux), in quella di `pwd`: niente WSL, che su
# Windows puo' mancare (D5). Solo senza alcun Python qui si ripiega su python3 dentro WSL, se WSL c'e'
# (MSYS_NO_PATHCONV=1: senza, Git Bash riscrive i percorsi /mnt/c/... passati a wsl.exe).
set -uo pipefail
[ $# -eq 2 ] || { echo "uso: $0 <run-dir> <etichetta>" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
nat() { local d; d=$(cd "$(dirname "$1")" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }) || d=$(dirname "$1"); printf '%s/%s' "$d" "$(basename "$1")"; }
log="$1/log/$2.jsonl"; ex="$1/log/$2.exit"
export PYTHONIOENCODING=utf-8   # ■/✖ su una pipe: il Python di Windows scriverebbe in cp1252
. "$HERE/python.sh" 2>/dev/null || FIC_PY=""
if [ -n "${FIC_PY:-}" ]; then exec "$FIC_PY" -u "$(nat "$HERE/phase-events.py")" "$(nat "$log")" "$(nat "$ex")"; fi
if command -v wsl >/dev/null 2>&1; then
  to_wsl() { local w; w=$(nat "$1")
    case $w in [A-Za-z]:/*) printf '/mnt/%s%s' "$(printf '%s' "${w:0:1}" | tr 'A-Z' 'a-z')" "${w:2}" ;; *) printf '%s' "$w" ;; esac; }
  MSYS_NO_PATHCONV=1 exec wsl -- python3 -u "$(to_wsl "$HERE/phase-events.py")" "$(to_wsl "$log")" "$(to_wsl "$ex")"
fi
echo "watch-phase: nessun Python (python.sh: imposta FIC_PYTHON) e nessun WSL" >&2
exit 2
