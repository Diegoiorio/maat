# _lib.sh — sourced (with `.`) by the inject/ scripts: worktree checks and utilities.
# Each inject:  bash inject/<name>.sh <corpus worktree> [options]
# A corpus worktree is one created by replay.sh: a LINKED git worktree (never the main tree), with
# the `fic-replay` marker in its git dir recording its path. Any other path is
# refused (exit 3) before touching a file. Exit 2 = invalid usage or target not applicable.
set -uo pipefail
unset MSYS_NO_PATHCONV
INJ_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "${INJ_HERE%/corpus/inject}/lib/maat-paths.sh" || exit 4   # scripts/lib: MAAT_ROOT and MAAT_SCRIPTS (plugin)
INJ_NAME=$(basename "$0" .sh)
die() { echo "inject $INJ_NAME: $*" >&2; exit 2; }
refuse() { echo "inject $INJ_NAME: RIFIUTO — $*" >&2; exit 3; }

# canonical form (C:/…) of an existing path: under MSYS the same place has several names. Empty → empty.
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
LAVORO=.claude/.ai-workflow   # the work directory (cartelle.lavoro), relative to the root: as in replay.sh
[ -n "${MAAT_WORK:-}" ] && LAVORO=${MAAT_WORK#"$PROJECT_ROOT"/}
AIW="$WT/$LAVORO"
RUN=$(ls -d "$AIW"/spec-*.run 2>/dev/null)
[ -n "$RUN" ] && [ "$(printf '%s\n' "$RUN" | wc -l)" -eq 1 ] || die "attesa una sola run directory in $AIW"
SPEC="${RUN%.run}.md"
winp() { maat_cygm "$1" 2>/dev/null || printf '%s' "$1"; }

# replace_once <relative path> <from> <to>: literal replacement; exactly ONE occurrence, otherwise error
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

# insert_line <path> <regex> <before|after> <text>: inserts the text before/after the FIRST line that
# matches the regex (from line <from> on, default 1)
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

# append_text <relative path> <text>: appends at the end, with a newline before
append_text() {
  [ -f "$WT/$1" ] || die "file assente nel worktree: $1"
  printf '\n%s\n' "$2" >> "$WT/$1"
}

# mark_touched <relative path>: attributed to the feature ONLY if the run directory already has a touched.txt
# (a code phase precedes the replayed one); before an implement the defect is pre-existing.
mark_touched() {
  [ -f "$RUN/touched.txt" ] || return 0
  printf '%s\n' "$1" >> "$RUN/touched.txt"
  sort -u -o "$RUN/touched.txt" "$RUN/touched.txt"
}

# pick <regex> <fallback>: the first touched.txt path that matches and exists, otherwise the fallback
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

# last_prompt: the prompt of the phase that will be replayed (the highest label in prompts/)
last_prompt() {
  local p
  p=$(ls "$RUN"/prompts/*.md 2>/dev/null | sort | tail -1)
  [ -n "$p" ] || die "nessun prompt in $RUN/prompts"
  printf '%s' "$p"
}

inj_done() { echo "inject $INJ_NAME: applicato a $WT — $*"; }
