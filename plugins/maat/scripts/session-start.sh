#!/usr/bin/env bash
# session-start.sh — SessionStart hook of the plugin (hooks/hooks.json): loads the rule for describing commands in
# permission requests (docs/descrizione-comandi.md, R11.1) into every session of the project, in the language set by
# `lingua` in .claude/maat.json (default en).
#   Project: CLAUDE_PROJECT_DIR (set by Claude Code), otherwise the current folder. Configuration: MAAT_CONFIG,
#   otherwise <project>/.claude/maat.json. Missing or unreadable configuration, or a language not in the table: en.
#   Output: one JSON line {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "…"}};
#   without a Python interpreter, the same text as plain stdout (Claude Code adds both to the context).
#   Always exits 0: a failure here must never block the session.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RULE="$HERE/../docs/descrizione-comandi.md"
[ -f "$RULE" ] || exit 0
PROJ=${CLAUDE_PROJECT_DIR:-$PWD}
CONF=${MAAT_CONFIG:-$PROJ/.claude/maat.json}
. "$HERE/python.sh" 2>/dev/null || FIC_PY=""
nat() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }   # Windows Python does not read /c/… paths
if [ -n "${FIC_PY:-}" ]; then
  "$FIC_PY" - "$(nat "$RULE")" "$(nat "$CONF")" <<'PY' 2>/dev/null && exit 0
import json, sys
rule = open(sys.argv[1], encoding="utf-8").read().strip()
try:
    lang = json.load(open(sys.argv[2], encoding="utf-8")).get("lingua")
except Exception:
    lang = None
names = {"en": "English", "it": "Italian"}
name = names.get(lang, "English")
ctx = ("Maat (plugin): write the `description` of every Bash and PowerShell tool call in %s, following this rule.\n\n%s"
       % (name, rule))
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}))
PY
fi
# fallback without Python (or if it failed): plain stdout, language not read
printf 'Maat (plugin): write the `description` of every Bash and PowerShell tool call following this rule.\n\n'
cat "$RULE"
exit 0
