# _lib.sh — incluso (con `.`) dagli script di inject/: controlli sul worktree e utilita'.
# Ogni inject:  bash inject/<nome>.sh <worktree del corpus> [opzioni]
# Un worktree del corpus e' uno creato da replay.sh: worktree git COLLEGATO (mai il tree principale), con
# il marcatore `fic-replay` nella sua git dir che ne riporta il percorso. Qualunque altro percorso e'
# rifiutato (uscita 3) prima di toccare un file. Uscita 2 = uso o bersaglio non applicabile.
set -uo pipefail
unset MSYS_NO_PATHCONV
INJ_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "${INJ_HERE%/corpus/inject}/lib/maat-paths.sh" || exit 4   # scripts/lib: MAAT_ROOT e MAAT_SCRIPTS (plugin)
INJ_NAME=$(basename "$0" .sh)
die() { echo "inject $INJ_NAME: $*" >&2; exit 2; }
refuse() { echo "inject $INJ_NAME: RIFIUTO — $*" >&2; exit 3; }

# forma canonica (C:/…) di un percorso esistente: con MSYS lo stesso posto ha piu' nomi. Vuoto → vuoto.
canon() { [ -n "${1:-}" ] && (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); }

[ $# -ge 1 ] || die "uso: $0 <worktree del corpus> [opzioni]"
WT=$(canon "$1") && [ -n "$WT" ] || refuse "percorso inesistente: $1"
shift
top=$(git -C "$WT" rev-parse --show-toplevel 2>/dev/null) || refuse "non e' un repository git: $WT"
[ "$(canon "$top")" = "$WT" ] || refuse "non e' la radice di un worktree: $WT"
common=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || refuse "git dir comune non risolta: $WT"
MAIN=$(canon "$(dirname "$common")")
[ "$WT" != "$MAIN" ] && [ "$WT" != "$(canon "$MAAT_ROOT")" ] || refuse "e' il tree principale o il harness, non un worktree del corpus: $WT"
gd=$(git -C "$WT" rev-parse --absolute-git-dir)
[ -f "$gd/fic-replay" ] || refuse "manca il marcatore di replay.sh: $WT non e' un worktree del corpus"
[ "$(canon "$(sed -n 's/^path=//p' "$gd/fic-replay")")" = "$WT" ] || refuse "il marcatore di replay.sh indica un altro percorso: $WT"

. "$MAAT_SCRIPTS/python.sh" || die "interprete Python non trovato (imposta FIC_PYTHON)"
LAVORO=.claude/.ai-workflow   # la cartella di lavoro (cartelle.lavoro), relativa alla radice: come replay.sh
[ -n "${MAAT_WORK:-}" ] && LAVORO=${MAAT_WORK#"$PROJECT_ROOT"/}
AIW="$WT/$LAVORO"
RUN=$(ls -d "$AIW"/spec-*.run 2>/dev/null)
[ -n "$RUN" ] && [ "$(printf '%s\n' "$RUN" | wc -l)" -eq 1 ] || die "attesa una sola run directory in $AIW"
SPEC="${RUN%.run}.md"
winp() { maat_cygm "$1" 2>/dev/null || printf '%s' "$1"; }

# replace_once <path relativo> <da> <a>: sostituzione letterale; esattamente UNA occorrenza, altrimenti errore
replace_once() {
  [ -f "$WT/$1" ] || die "file assente nel worktree: $1"
  "$FIC_PY" -c '
import sys
p, a, b = sys.argv[1], sys.argv[2].encode("utf-8"), sys.argv[3].encode("utf-8")
s = open(p, "rb").read()
n = s.count(a)
if n != 1:
    sys.exit("occorrenze di %r: %d (attesa 1)" % (sys.argv[2], n))
open(p, "wb").write(s.replace(a, b))
' "$(winp "$WT/$1")" "$2" "$3" || die "sostituzione non applicabile in $1"
}

# insert_line <path> <regex> <before|after> <testo>: inserisce il testo prima/dopo la PRIMA riga che
# corrisponde alla regex (dalla riga <from> in poi, default 1)
insert_line() {
  "$FIC_PY" -c '
import re, sys
p, rx, where, text = sys.argv[1], re.compile(sys.argv[2]), sys.argv[3], sys.argv[4]
start = int(sys.argv[5]) if len(sys.argv) > 5 else 1
raw = open(p, "rb").read().decode("utf-8")
nl = "\r\n" if "\r\n" in raw else "\n"
lines = raw.split(nl)
for i in range(start - 1, len(lines)):
    if rx.search(lines[i]):
        add = text.split("\n")
        lines[i:i] = add if where == "before" else []
        if where == "after":
            lines[i + 1:i + 1] = add
        open(p, "wb").write(nl.join(lines).encode("utf-8"))
        sys.exit(0)
sys.exit("nessuna riga corrisponde a %r" % sys.argv[2])
' "$(winp "$1")" "$2" "$3" "$4" "${5:-1}" || die "inserimento non applicabile in $1"
}

# append_text <path relativo> <testo>: aggiunge in coda, con a capo prima
append_text() {
  [ -f "$WT/$1" ] || die "file assente nel worktree: $1"
  printf '\n%s\n' "$2" >> "$WT/$1"
}

# mark_touched <path relativo>: attribuito alla feature SOLO se la run directory ha gia' un touched.txt
# (una fase di codice precede quella rigiocata); prima di una implement il difetto e' preesistente.
mark_touched() {
  [ -f "$RUN/touched.txt" ] || return 0
  printf '%s\n' "$1" >> "$RUN/touched.txt"
  sort -u -o "$RUN/touched.txt" "$RUN/touched.txt"
}

# pick <regex> <ripiego>: il primo path di touched.txt che corrisponde e che esiste, altrimenti il ripiego
pick() {
  local p
  if [ -f "$RUN/touched.txt" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] && printf '%s' "$p" | grep -qE "$1" && [ -f "$WT/$p" ] && { printf '%s' "$p"; return 0; }
    done < "$RUN/touched.txt"
  fi
  [ -f "$WT/$2" ] || die "nessun bersaglio: niente in touched.txt per /$1/ e ripiego assente ($2); indicalo con --file/--test"
  printf '%s' "$2"
}

# last_prompt: il prompt della fase che sara' rigiocata (l'etichetta piu' alta in prompts/)
last_prompt() {
  local p
  p=$(ls "$RUN"/prompts/*.md 2>/dev/null | sort | tail -1)
  [ -n "$p" ] || die "nessun prompt in $RUN/prompts"
  printf '%s' "$p"
}

inj_done() { echo "inject $INJ_NAME: applicato a $WT — $*"; }
