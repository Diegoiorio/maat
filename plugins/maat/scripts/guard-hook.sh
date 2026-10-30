#!/usr/bin/env bash
# guard-hook.sh — hook PreToolUse (Bash|PowerShell) del plugin: la guardia di sessione di ogni progetto che installa
# Maat (hooks/hooks.json). Trova Python (python.sh) e lancia `guard.py --universal`, che legge le regole del progetto
# da MAAT_CONFIG o da <CLAUDE_PROJECT_DIR>/.claude/maat.json.
#
# Mai fail-open. Senza Python, o con guard.py uscito con un codice diverso da 0 e da 2 (crash):
#   - in sessione (FIC_PHASE vuota)      → «ask» su OGNI comando, con il motivo in tre parti (R11);
#   - in sotto-sessione (FIC_PHASE)      → exit 2 con il motivo su stderr: li' «ask» non e' un diniego.
# I due motivi sono testi fissi, in it: in questi casi ne' la tabella di guard.py ne' maat.json sono leggibili.
# Guardia ridotta: FIC_SESSION_GUARD=prod, applicata da guard.py.
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
