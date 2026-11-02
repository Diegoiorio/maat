# _lib.sh — sourced (with `.`) by the inject/ scripts: worktree checks and utilities.
# Each inject:  bash inject/<name>.sh <corpus worktree> [options]
# A corpus worktree is one created by replay.sh: a LINKED git worktree (never the main tree), with
# the `fic-replay` marker in its git dir recording its path. Any other path is
# refused (exit 3) before touching a file. Exit 2 = invalid usage or target not applicable.
set -uo pipefail
unset MSYS_NO_PATHCONV
INJ_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "${INJ_HERE%/corpus/inject}/lib/maat-paths.sh" || exit 4   # scripts/lib: MAAT_ROOT and MAAT_SCRIPTS (plugin)
# messages (1.4.0): the catalog of the plugin, English by default, Italian with "lingua": "it"; the embedded Python
# below imports maat_msg.py from MAAT_MSG_PY. The text the injects write into the worktree (test cases, plan lines,
# the gate claim in the prompt) is fixture of the guide project and stays as it is.
. "$MAAT_SCRIPTS/lib/maat-msg.sh"; maat_msg_carica
MAAT_MSG_PY=$(maat_cygm "$MAAT_SCRIPTS/maat_msg.py" 2>/dev/null || printf '%s' "$MAAT_SCRIPTS/maat_msg.py"); export MAAT_MSG_PY
INJ_NAME=$(basename "$0" .sh)
die() { echo "inject $INJ_NAME: $*" >&2; exit 2; }
refuse() { echo "inject $INJ_NAME: $(msg inject.refused) — $*" >&2; exit 3; }

# canonical form (C:/…) of an existing path: under MSYS the same place has several names. Empty → empty.
canon() { [ -n "${1:-}" ] && (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); }

[ $# -ge 1 ] || die "$(msg inject.usage script="$0")"
WT=$(canon "$1") && [ -n "$WT" ] || refuse "$(msg inject.no_path p="$1")"
shift
top=$(git -C "$WT" rev-parse --show-toplevel 2>/dev/null) || refuse "$(msg inject.not_repo wt="$WT")"
[ "$(canon "$top")" = "$WT" ] || refuse "$(msg inject.not_root wt="$WT")"
common=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || refuse "$(msg inject.no_common wt="$WT")"
MAIN=$(canon "$(dirname "$common")")
[ "$WT" != "$MAIN" ] && [ "$WT" != "$(canon "$MAAT_ROOT")" ] || refuse "$(msg inject.is_main wt="$WT")"
gd=$(git -C "$WT" rev-parse --absolute-git-dir)
[ -f "$gd/fic-replay" ] || refuse "$(msg inject.no_marker wt="$WT")"
[ "$(canon "$(sed -n 's/^path=//p' "$gd/fic-replay")")" = "$WT" ] || refuse "$(msg inject.marker_other wt="$WT")"

. "$MAAT_SCRIPTS/python.sh" || die "$(msg inject.no_python)"
LAVORO=.claude/.ai-workflow   # the work directory (cartelle.lavoro), relative to the root: as in replay.sh
[ -n "${MAAT_WORK:-}" ] && LAVORO=${MAAT_WORK#"$PROJECT_ROOT"/}
AIW="$WT/$LAVORO"
RUN=$(ls -d "$AIW"/spec-*.run 2>/dev/null)
[ -n "$RUN" ] && [ "$(printf '%s\n' "$RUN" | wc -l)" -eq 1 ] || die "$(msg inject.one_run aiw="$AIW")"
SPEC="${RUN%.run}.md"
winp() { maat_cygm "$1" 2>/dev/null || printf '%s' "$1"; }

# replace_once <relative path> <from> <to>: literal replacement; exactly ONE occurrence, otherwise error
replace_once() {
  [ -f "$WT/$1" ] || die "$(msg inject.no_file f="$1")"
  "$FIC_PY" -c '
import importlib.util, os, sys
p, a, b = sys.argv[1], sys.argv[2].encode("utf-8"), sys.argv[3].encode("utf-8")
s = open(p, "rb").read()
n = s.count(a)
if n != 1:
    sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
    _s = importlib.util.spec_from_file_location("maat_msg", os.environ["MAAT_MSG_PY"])
    _m = importlib.util.module_from_spec(_s); _s.loader.exec_module(_m)
    sys.exit(_m.T("inject.occurrences", a=repr(sys.argv[2]), n=n))
open(p, "wb").write(s.replace(a, b))
' "$(winp "$WT/$1")" "$2" "$3" || die "$(msg inject.replace_failed f="$1")"
}

# insert_line <path> <regex> <before|after> <text>: inserts the text before/after the FIRST line that
# matches the regex (from line <from> on, default 1)
insert_line() {
  "$FIC_PY" -c '
import importlib.util, os, re, sys
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
sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
_s = importlib.util.spec_from_file_location("maat_msg", os.environ["MAAT_MSG_PY"])
_m = importlib.util.module_from_spec(_s); _s.loader.exec_module(_m)
sys.exit(_m.T("inject.no_line", rx=repr(sys.argv[2])))
' "$(winp "$1")" "$2" "$3" "$4" "${5:-1}" || die "$(msg inject.insert_failed f="$1")"
}

# append_text <relative path> <text>: appends at the end, with a newline before
append_text() {
  [ -f "$WT/$1" ] || die "$(msg inject.no_file f="$1")"
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
  [ -f "$WT/$2" ] || die "$(msg inject.no_target rx="$1" fb="$2")"
  printf '%s' "$2"
}

# last_prompt: the prompt of the phase that will be replayed (the highest label in prompts/)
last_prompt() {
  local p
  p=$(ls "$RUN"/prompts/*.md 2>/dev/null | sort | tail -1)
  [ -n "$p" ] || die "$(msg inject.no_prompt run="$RUN")"
  printf '%s' "$p"
}

inj_done() { echo "inject $INJ_NAME: $(msg inject.applied wt="$WT") — $*"; }
