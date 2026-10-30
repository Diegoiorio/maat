#!/usr/bin/env bash
# session-start.test.sh — the SessionStart hook (scripts/session-start.sh, R11.1): it loads the command-description
# rule into the session, in the language of `lingua` in .claude/maat.json (default en).
#   1. hooks.json declares the hook (SessionStart, no matcher: every source) next to the guard;
#   2. output: valid JSON, hookEventName SessionStart, the whole rule (docs/descrizione-comandi.md) in additionalContext;
#   3. language: it -> Italian; en, a language not in the table, an invalid or a missing maat.json -> English;
#      MAAT_CONFIG wins over the project's file;
#   4. without a Python interpreter: the rule as plain stdout, exit 0; rule file missing: no output, exit 0;
#   5. counterproof by mutation: the language fixed to English => the «it» case is red.
#   bash plugins/maat/scripts/session-start.test.sh          (Git Bash or Linux)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(cd "$HERE/.." && pwd)
. "$HERE/python.sh" || { echo "Python interpreter not found" >&2; exit 2; }
pass=0 fail=0
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '%s\n' "$2" | head -20 | sed 's/^/    /'; }
nat() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
# ctx <script> <project> [env…]: the additionalContext of the JSON output (empty if the output is not that JSON)
ctx() {
  local s=$1 p=$2; shift 2
  (cd "$T" && env -u MAAT_CONFIG CLAUDE_PROJECT_DIR="$p" "$@" bash "$s" </dev/null) | "$FIC_PY" -c '
import json, sys
try:
    d = json.load(sys.stdin)["hookSpecificOutput"]
    assert d["hookEventName"] == "SessionStart"
    print(d["additionalContext"])
except Exception:
    pass'
}
proj() { # $1 folder, $2 lingua (or "-" for none, "rotto" for an invalid file)
  mkdir -p "$1/.claude"
  case $2 in
    -) printf '{"versione_schema":1,"moduli":[{"nome":"a","radice":"."}]}' > "$1/.claude/maat.json" ;;
    rotto) printf '{ non e json' > "$1/.claude/maat.json" ;;
    *) printf '{"versione_schema":1,"lingua":"%s","moduli":[{"nome":"a","radice":"."}]}' "$2" > "$1/.claude/maat.json" ;;
  esac
}
SS="$HERE/session-start.sh"
RULE1=$(head -1 "$PLUGIN/docs/descrizione-comandi.md")

# --- 1. hooks.json ---
"$FIC_PY" -c '
import json, sys
h = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]
s = h["SessionStart"]
assert len(s) == 1 and "matcher" not in s[0], s
assert s[0]["hooks"][0]["command"] == "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh\"", s
assert "PreToolUse" in h
' "$(nat "$PLUGIN/hooks/hooks.json")" && ok || ko "hooks.json: SessionStart without matcher, command session-start.sh, guard still there"

# --- 2-3. output and language ---
proj "$T/it" it; proj "$T/en" en; proj "$T/xx" xx; proj "$T/none" -; proj "$T/broken" rotto; mkdir -p "$T/missing"
c=$(ctx "$SS" "$(nat "$T/it")")
case $c in *"tool call in Italian, following this rule."*) ok ;; *) ko "lingua it -> Italian" "$c" ;; esac
printf '%s\n' "$c" | grep -qxF -- "$RULE1" && printf '%s\n' "$c" | grep -qF "At most about 5 lines" && ok || ko "the whole rule is in additionalContext" "$c"
for p in en xx none broken missing; do
  c=$(ctx "$SS" "$(nat "$T/$p")")
  case $c in *"tool call in English, following this rule."*) ok ;; *) ko "$p -> English" "$c" ;; esac
done
c=$(ctx "$SS" "$(nat "$T/en")" MAAT_CONFIG="$(nat "$T/it/.claude/maat.json")")
case $c in *"in Italian,"*) ok ;; *) ko "MAAT_CONFIG wins over the project's maat.json" "$c" ;; esac

# --- 4. no Python; no rule file ---
out=$(cd "$T" && env -u MAAT_CONFIG CLAUDE_PROJECT_DIR="$(nat "$T/it")" FIC_PYTHON="$T/no-python" bash "$SS" </dev/null); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -qxF -- "$RULE1" && ! printf '%s\n' "$out" | grep -q hookSpecificOutput && ok \
  || ko "without Python: the rule as plain stdout, exit 0" "rc=$rc $out"
C="$T/copy"; mkdir -p "$C"; cp -r "$PLUGIN/scripts" "$C/scripts"
out=$(cd "$T" && CLAUDE_PROJECT_DIR="$(nat "$T/it")" bash "$C/scripts/session-start.sh" </dev/null); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && ok || ko "rule file missing: no output, exit 0" "rc=$rc $out"

# --- 5. counterproof: language fixed to English ---
mkdir -p "$C/docs"; cp "$PLUGIN/docs/descrizione-comandi.md" "$C/docs/"
sed -i 's/^name = names.get(lang, "English")$/name = "English"/' "$C/scripts/session-start.sh"
if grep -q '^name = "English"$' "$C/scripts/session-start.sh"; then
  c=$(ctx "$C/scripts/session-start.sh" "$(nat "$T/it")")
  case $c in *"in Italian,"*) ko "counterproof: with the language fixed to English the «it» case is still green" ;; *) ok ;; esac
else ko "counterproof: mutation not applied"; fi

echo "session-start.test.sh: $pass ok, $fail falliti"
[ $fail -eq 0 ]
