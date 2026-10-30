#!/usr/bin/env bash
# guard-hook.sh — the plugin's PreToolUse hook (Bash|PowerShell): the session guard of every project that installs
# Maat (hooks/hooks.json). It finds Python (python.sh) and runs `guard.py --universal`, which reads the project rules
# from MAAT_CONFIG or from <CLAUDE_PROJECT_DIR>/.claude/maat.json.
#
# Never fail-open. Without Python, or when guard.py exits with a code other than 0 and 2 (crash):
#   - in the session (FIC_PHASE empty)   → "ask" on EVERY command, with the three-part reason (R11);
#   - in a sub-session (FIC_PHASE)       → exit 2 with the reason on stderr: there "ask" is not a denial.
# The two reasons are fixed texts, in Italian: in these cases neither guard.py's table nor maat.json can be read.
# Reduced guard: FIC_SESSION_GUARD=prod, applied by guard.py.
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(cat)
if . "$HERE/python.sh" >/dev/null 2>&1 && [ -n "${FIC_PY:-}" ]; then
  printf '%s' "$input" | "$FIC_PY" "$HERE/guard.py" --universal
  rc=$?
  if [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; then exit "$rc"; fi
  why="guardia in errore (uscita $rc): nessun controllo eseguito — regola del nucleo (guardia che fallisce: mai lasciar passare) — conferma solo se il comando è sicuro, e segnala l'errore di guard.py"
else
  why="Python non trovato: guardia non disponibile — regola del nucleo (guardia senza interprete: si chiede su ogni comando) — installa Python 3.10 o superiore, o imposta FIC_PYTHON; conferma solo se il comando è sicuro"
fi
if [ -n "${FIC_PHASE:-}" ]; then
  printf 'guardia di sessione: %s\n' "$why" >&2
  exit 2
fi
printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "%s"}}\n' "$why"
exit 0
