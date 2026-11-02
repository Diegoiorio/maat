#!/usr/bin/env bash
# stop-hook.test.sh — tests of stop-hook.py (the sub-sessions' Stop hook) on synthetic transcripts:
# a turn without `PHASE RESULT` (or the Italian `ESITO FASE` of 1.2.x) is denied; with stop_hook_active it does not loop again; a background job not
# collected is denied, collected (notification, final TaskOutput, TaskStop) is allowed; broken hook -> lets it close.
#   bash script/fic/stop-hook.test.sh
set -uo pipefail
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/python.sh" || { echo "interprete Python non trovato" >&2; exit 2; }
SH="$HERE/stop-hook.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0 n=0
TR="$T/transcript.jsonl"
WTR=$(cygpath -m "$TR" 2>/dev/null || printf '%s' "$TR")

# $1 expected (allow|block), $2 description, $3 stop_hook_active (true|false), $4 text expected in the reason
hook() {
  n=$((n + 1))
  local out rc got
  out=$(printf '{"session_id":"s","transcript_path":"%s","stop_hook_active":%s,"hook_event_name":"Stop"}' "$WTR" "${3:-false}" \
        | "$FIC_PY" "$SH" 2>/dev/null); rc=$?
  got=allow
  [ -n "$out" ] && printf '%s' "$out" | "$FIC_PY" -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("decision")=="block" and d.get("reason") else 1)' && got=block
  if [ $rc -ne 0 ] || [ "$got" != "$1" ] || { [ -n "${4:-}" ] && ! printf '%s' "$out" | grep -q -- "$4"; }; then
    fail=$((fail + 1)); echo "FAIL (atteso $1, ottenuto $got, uscita $rc) $2"; [ -n "$out" ] && echo "    $out"
  fi
}
txt()  { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1"; }
use()  { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"%s","name":"%s","input":%s}]}}\n' "$1" "$2" "$3"; }
res()  { printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"%s","content":"%s"}]}}\n' "$1" "$2"; }
notif() { printf '{"type":"attachment","attachment":{"type":"queued_command","prompt":"<task-notification>\\n<task-id>%s</task-id>\\n<status>%s</status>\\n<summary>x</summary>\\n</task-notification>","commandMode":"task-notification"}}\n' "$1" "$2"; }
OK_LINE='lavoro fatto\nESITO FASE implement: OK — finto'
BG_START() { use tu1 Bash '{"command":"sleep 99","run_in_background":true}'; res tu1 'Command running in background with ID: b123. Output is being written to: C:\\x\\b123.output'; }

# --- ESITO FASE ---
{ printf '{"type":"user","message":{"content":"/full-implementation-cycle --worker=implement x"}}\n'; txt "ho finito"; } > "$TR"
hook block "turno senza riga d'esito negato, il motivo cita la forma inglese" false "PHASE RESULT <phase>: OK"
hook allow "  con stop_hook_active non rientra in loop" true
{ txt "inizio"; txt "$OK_LINE"; } > "$TR"
hook allow "ultimo messaggio con ESITO FASE ... OK: ammesso"
txt 'riassunto\nESITO FASE review: STOP — manca una decisione' > "$TR"
hook allow "ESITO FASE ... STOP: ammesso"
# 1.3.0: the English result line
txt 'work done\nPHASE RESULT implement: OK — done' > "$TR"
hook allow "ultimo messaggio con PHASE RESULT ... OK: ammesso"
txt 'summary\nPHASE RESULT review: STOP — a decision is missing' > "$TR"
hook allow "PHASE RESULT ... STOP: ammesso"
txt 'PHASE RESULT implement: FORSE — x' > "$TR"
hook block "  controprova: PHASE RESULT senza OK/STOP → negato" false "PHASE RESULT"
{ use tu9 Read '{"file_path":"SKILL.md"}'; res tu9 'esempio: ESITO FASE implement: OK — letto da SKILL.md'; txt "ho letto"; } > "$TR"
hook block "ESITO solo dentro un tool_result letto: negato" false "PHASE RESULT"
{ txt "$OK_LINE"; use tu8 Bash '{"command":"ls"}'; res tu8 'a b'; } > "$TR"
hook block "ESITO seguito da altro lavoro, nessun testo finale: negato"

# --- background jobs ---
{ BG_START; txt "$OK_LINE"; } > "$TR"
hook block "job in background non raccolto: negato (anche con ESITO)" false "b123"
hook allow "  con stop_hook_active: lascia chiudere" true
{ BG_START; notif b123 completed; txt "$OK_LINE"; } > "$TR"
hook allow "job concluso (task-notification completed): ammesso"
{ BG_START; notif b123 running; txt "$OK_LINE"; } > "$TR"
hook block "notifica senza stato finale: ancora negato" false "b123"
{ BG_START; use tu2 TaskOutput '{"task_id":"b123"}'; res tu2 '<status>running</status>'; txt "$OK_LINE"; } > "$TR"
hook block "TaskOutput con stato running: negato" false "b123"
{ BG_START; use tu2 BashOutput '{"bash_id":"b123"}'; res tu2 '<status>completed</status><exit_code>0</exit_code>'; txt "$OK_LINE"; } > "$TR"
hook allow "BashOutput con stato completed: ammesso"
{ BG_START; use tu3 TaskStop '{"task_id":"b123"}'; res tu3 'stopped'; txt "$OK_LINE"; } > "$TR"
hook allow "TaskStop sul job: ammesso"
{ BG_START; use tu5 Bash '{"command":"sleep 5","run_in_background":true}'; res tu5 'Command running in background with ID: b456. Output is being written to: C:\\x'; notif b123 completed; txt "$OK_LINE"; } > "$TR"
hook block "due job, uno solo concluso: negato per l'altro" false "b456"

# --- 1.4.0, English (MAAT_LINGUA=en, inherited by the sub-session from run-phase.sh): both reasons from the catalog ---
{ BG_START; txt "ho finito"; } > "$TR"
n=$((n + 1))
out=$(printf '{"session_id":"s","transcript_path":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$WTR" |
      MAAT_LINGUA=en "$FIC_PY" "$SH" 2>&1); rc=$?
printf '%s' "$out" | "$FIC_PY" -c 'import json, sys
r = json.loads(sys.stdin.buffer.read().decode("utf-8"))["reason"]
ok = r.startswith("hook Stop: background jobs not collected: b123 — collect them") and "the last message has no `PHASE RESULT <phase>: OK" in r
sys.exit(0 if ok and not any(w in r for w in ("raccolti", "messaggio", "riga", "fase", "chiudere")) else 1)' && [ $rc -eq 0 ] ||
  { fail=$((fail + 1)); echo "FAIL en: due motivi in inglese, nessun italiano (rc=$rc)"; echo "    $out"; }

# --- broken hook: never hold the session back ---
rm -f "$TR"
hook allow "transcript assente: lascia chiudere"
n=$((n + 1))
out=$(printf 'non json' | "$FIC_PY" "$SH" 2>/dev/null); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] || { fail=$((fail + 1)); echo "FAIL input illeggibile: atteso uscita 0 senza output (rc=$rc, «$out»)"; }

echo "stop-hook.test.sh: $((n - fail))/$n ok"
[ $fail -eq 0 ]
