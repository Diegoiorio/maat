#!/usr/bin/env bash
# transcript.test.sh — tests of transcript.py (Maat 1.8.0, §Tassonomia, D2, D3, A1): what a phase did, read from its
# session transcript (log/<label>.jsonl, stream-json, or a session transcript), on the MAIN session only.
#   bash plugins/maat/scripts/transcript.test.sh          (Git Bash or WSL)
#   TRX=/path/variant.py bash .../transcript.test.sh     # the suite against another copy of the module
# Cases (synthetic, generic jsonl): bash — a Bash call and its result -> found; a command one character shorter, an
# excerpt absent, the same command only in a sidechain (isSidechain) or in a sub-agent (parent_tool_use_id) -> not
# found; empty excerpt -> usage. agente — subagent_type, input texts in the prompt and result -> found; an input text
# missing, another subagent_type, the verdict only in an asynchronous launch or only in the final text -> not found.
# conta — the results of a subagent_type over several jsonl, main sessions only (no sidechain, no error, no
# asynchronous launch); a file unreadable -> exit 2. aperti_alla_chiusura — an agent launched in background and still
# open when the session is woken up again -> open; foreground agents, a background job collected before the closing ->
# none; (B8 review) a text that only looks like a receipt opens nothing, a `result` event is a closing, a sub-agent's job
# and notification do not count, BashOutput/TaskOutput/KillShell close; the receipt of a background Bash is not its
# result. Counterproofs at the end: main-session filter removed, command compared by containment, the result not
# required for conta, the Bash receipt accepted, jobs opened by text, no closing on `result`, notifications of every
# session -> their cases red.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TRX=${TRX:-$HERE/transcript.py}
. "$HERE/python.sh" || true
[ -n "${FIC_PY:-}" ] || { echo "transcript.test.sh: nessun Python utilizzabile" >&2; exit 2; }
export PYTHONDONTWRITEBYTECODE=1 PYTHONIOENCODING=utf-8 MAAT_LINGUA=it
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
nat() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; [ -n "${3:-}" ] && printf '%s\n' "$3" | sed 's/^/    /'; fi; }
tr_() { local x=$1; shift; "$FIC_PY" "$(nat "$x")" "$@"; }   # <module> <args…> (stdin passed through)

# --- the fixtures ---
# a phase: init, a Bash run in the foreground and its result, the same command (one character more) only in a
# sidechain and only in a sub-agent, a reviewer in the foreground with its verdict, the final result
cat > "$T/fase.jsonl" <<'EOF'
{"type":"system","subtype":"init","session_id":"s1"}
{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"tu_1","name":"Bash","input":{"command":"python -m pytest tests/test_depth.py -k deep","description":"run"}}]}}
{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"tu_1","content":"F\r\nE   DepthError: nesting limit 64 exceeded\r\n1 failed","is_error":true}]},"tool_use_result":{"stdout":"F"}}
{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"tool_use","id":"tu_2","name":"Bash","input":{"command":"python -m pytest tests/test_depth.py -k deeper"}}]}}
{"type":"user","isSidechain":true,"message":{"content":[{"type":"tool_result","tool_use_id":"tu_2","content":"E   DepthError: nesting limit 64 exceeded"}]}}
{"type":"assistant","parent_tool_use_id":"tu_9","message":{"content":[{"type":"tool_use","id":"tu_3","name":"Bash","input":{"command":"node -e 'run()'"}}]}}
{"type":"user","parent_tool_use_id":"tu_9","message":{"content":[{"type":"tool_result","tool_use_id":"tu_3","content":[{"type":"text","text":"overflow at depth 65"}]}]}}
{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"text","text":"Deviation verdict: ACCEPT (written by the worker, not by a judge)"},{"type":"tool_use","id":"tu_4","name":"Agent","input":{"description":"judge","subagent_type":"maat:spec-plan-reviewer-light","prompt":"Row T4 of the plan:\n| T4 | parses nested input | FR9 |\r\nThe deviation: test-data: T4 — other fixture names — collision\n--- a/t.py\n+++ b/t.py\n@@ -1 +1 @@\n-a\n+b"}}]}}
{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"tu_4","content":[{"type":"text","text":"Deviation verdict: ACCEPT\nRequirements still covered: FR9"}]}]}}
{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"tu_5","name":"Task","input":{"description":"other","subagent_type":"maat:spec-plan-reviewer","prompt":"Row T5 of the plan"}}]}}
{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"tu_5","content":"Async agent launched successfully.\nagentId: a1b2c3 (internal ID)"}]},"tool_use_result":{"isAsync":true,"status":"async_launched","agentId":"a1b2c3"}}
{"type":"result","subtype":"success","result":"PHASE RESULT test-red: OK — done"}
EOF
CMD='python -m pytest tests/test_depth.py -k deep'

# --- bash ---
tr_ "$TRX" bash "$CMD" "DepthError: nesting limit 64" < "$T/fase.jsonl" > "$T/o" 2>&1; rc=$?
check "bash: la chiamata Bash della sessione principale e il suo risultato (con CR) → trovato, exit 0" '[ $rc -eq 0 ] && grep -q "riga 2, risultato alla riga 3" "$T/o"' "$(cat "$T/o")"
tr_ "$TRX" bash "${CMD%p}" "DepthError: nesting limit 64" < "$T/fase.jsonl" > "$T/o" 2>&1; rc=$?
check "bash: comando diverso di un carattere (uno in meno) → non trovato, exit 1" '[ $rc -eq 1 ] && grep -q "non trovato" "$T/o"' "$(cat "$T/o")"
tr_ "$TRX" bash "$CMD" "nesting limit 65" < "$T/fase.jsonl" > "$T/o" 2>&1; rc=$?
check "bash: estratto assente dal risultato → non trovato, exit 1" '[ $rc -eq 1 ]' "$(cat "$T/o")"
tr_ "$TRX" bash "${CMD}er" "DepthError: nesting limit 64" < "$T/fase.jsonl" > "$T/o" 2>&1; rc=$?
check "bash: lo stesso comando solo in un sidechain (isSidechain) → non trovato" '[ $rc -eq 1 ]' "$(cat "$T/o")"
tr_ "$TRX" bash "node -e 'run()'" "overflow at depth 65" < "$T/fase.jsonl" > "$T/o" 2>&1; rc=$?
check "bash: lo stesso comando solo in un sotto-agente (parent_tool_use_id) → non trovato" '[ $rc -eq 1 ]' "$(cat "$T/o")"
tr_ "$TRX" bash "$CMD" "" < "$T/fase.jsonl" > "$T/o" 2>&1; rc=$?
check "bash: estratto vuoto → uso, exit 2" '[ $rc -eq 2 ] && grep -q "^uso: transcript.py" "$T/o"' "$(cat "$T/o")"
tr_ "$TRX" > "$T/o" 2>&1; rc=$?
check "senza sottocomando → uso, exit 2" '[ $rc -eq 2 ]'

# --- agente ---
J=maat:spec-plan-reviewer-light
ROW='| T4 | parses nested input | FR9 |'; DEV='test-data: T4 — other fixture names — collision'
DIFF=$(printf -- '--- a/t.py\n+++ b/t.py\n@@ -1 +1 @@\n-a\n+b')
tr_ "$TRX" agente "$J" "$ROW" "$DEV" "$DIFF" "Deviation verdict: ACCEPT" < "$T/fase.jsonl" > "$T/o" 2>&1; rc=$?
check "agente: subagent_type esatto, riga, deviazione e diff nel prompt, verdetto nel risultato → trovato, exit 0" '[ $rc -eq 0 ] && grep -q "riga 8, risultato alla riga 9" "$T/o"' "$(cat "$T/o")"
tr_ "$TRX" agente "$J" "$ROW" "$DEV" "$DIFF
+c" "Deviation verdict: ACCEPT" < "$T/fase.jsonl" > "$T/o" 2>&1; rc=$?
check "agente: un testo d'input che il prompt non contiene (un hunk in più) → non trovato" '[ $rc -eq 1 ]' "$(cat "$T/o")"
tr_ "$TRX" agente maat:spec-plan-reviewer "$ROW" "Deviation verdict: ACCEPT" < "$T/fase.jsonl" > "$T/o" 2>&1; rc=$?
check "agente: un altro subagent_type → non trovato" '[ $rc -eq 1 ]' "$(cat "$T/o")"
tr_ "$TRX" agente maat:spec-plan-reviewer "Row T5" "Async agent launched" < "$T/fase.jsonl" > "$T/o" 2>&1; rc=$?
check "agente: la ricevuta di un lancio asincrono non e' un risultato → non trovato" '[ $rc -eq 1 ]' "$(cat "$T/o")"
grep -v '"tu_4"' "$T/fase.jsonl" > "$T/senza-giudice.jsonl"
tr_ "$TRX" agente "$J" "$ROW" "Deviation verdict: ACCEPT" < "$T/senza-giudice.jsonl" > "$T/o" 2>&1; rc=$?
check "agente: giudice mai chiamato (il verdetto solo nel testo) → non trovato" '[ $rc -eq 1 ]' "$(cat "$T/o")"
tr_ "$TRX" agente "$J" "Deviation verdict: ACCEPT" < "$T/fase.jsonl" > "$T/o" 2>&1; rc=$?
check "agente: senza testi d'input → uso, exit 2" '[ $rc -eq 2 ]'

# --- conta ---
R=maat:spec-plan-reviewer
riv() { # <id> <subagent_type> [sidechain|sub|async|error]
  local sc="" pt=null res='"content":"Decision: NEEDS_CHANGES"' tur=""
  case "${3:-}" in
    sidechain) sc='"isSidechain":true,' ;;
    sub) pt='"tu_x"' ;;
    async) res='"content":"Async agent launched successfully.\nagentId: z'"$1"'"'; tur=',"tool_use_result":{"status":"async_launched"}' ;;
    error) res='"content":"agent failed","is_error":true' ;;
  esac
  printf '{"type":"assistant",%s"parent_tool_use_id":%s,"message":{"content":[{"type":"tool_use","id":"%s","name":"Agent","input":{"subagent_type":"%s","prompt":"review"}}]}}\n' "$sc" "$pt" "$1" "$2"
  printf '{"type":"user",%s"parent_tool_use_id":%s,"message":{"content":[{"type":"tool_result","tool_use_id":"%s",%s}]}%s}\n' "$sc" "$pt" "$1" "$res" "$tur"
}
{ riv a1 "$R"; riv a2 "$R"; riv a3 "$R" sidechain; riv a4 "$R-light"; riv a5 "$R" sub; } > "$T/p1.jsonl"
{ riv b1 "$R"; riv b2 "$R" async; riv b3 "$R" error; riv b4 spec-plan-reviewer; } > "$T/p2.jsonl"
o=$(tr_ "$TRX" conta "$R" "$(nat "$T/p1.jsonl")" "$(nat "$T/p2.jsonl")" 2>&1); rc=$?
check "conta: 3 risultati di $R su due jsonl (non il sidechain, non il sotto-agente, non -light, non il lancio asincrono, non l'errore, non il nome senza prefisso)" '[ $rc -eq 0 ] && [ "$(printf "%s" "$o" | tr -d "\r")" = 3 ]' "rc=$rc $o"
o=$(tr_ "$TRX" conta "$R-light" "$(nat "$T/p1.jsonl")" 2>&1); rc=$?
check "conta: 1 risultato di $R-light" '[ $rc -eq 0 ] && [ "$(printf "%s" "$o" | tr -d "\r")" = 1 ]' "rc=$rc $o"
o=$(tr_ "$TRX" conta "$R" "$(nat "$T/p1.jsonl")" "$(nat "$T/manca.jsonl")" 2>&1); rc=$?
check "conta: un jsonl illeggibile → exit 2, nessun numero" '[ $rc -eq 2 ] && ! printf "%s\n" "$o" | grep -qx "[0-9]*"' "rc=$rc $o"

# --- aperti_alla_chiusura (imported, as driver.py classifica does) ---
cat > "$T/ap.py" <<'EOF'
import importlib.util, sys
sys.dont_write_bytecode = True
s = importlib.util.spec_from_file_location("transcript", sys.argv[1]); m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
for p in sys.argv[2:]:
    print("%s\t%s" % (p.rsplit("/", 1)[-1], ",".join(m.aperti_alla_chiusura(m.righe(p))) or "-"))
EOF
# the plan that launches three reviewers in background and closes its turn: woken up by the first notification,
# two of them are still open (the closing is the second init); in the end all three are notified
{ printf '%s\n' '{"type":"system","subtype":"init"}'
  for i in 1 2 3; do
    printf '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"l%s","name":"Agent","input":{"subagent_type":"maat:spec-plan-reviewer","prompt":"lens","run_in_background":true}}]}}\n' "$i"
    printf '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"l%s","content":"Async agent launched successfully.\\nagentId: ag%s (internal ID)"}]},"tool_use_result":{"isAsync":true,"status":"async_launched","agentId":"ag%s"}}\n' "$i" "$i" "$i"
  done
  printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"text","text":"waiting for the reviewers"}]}}'
  printf '%s\n' '{"type":"system","subtype":"task_notification","task_id":"ag3","status":"completed"}'
  printf '%s\n' '{"type":"system","subtype":"init"}'
  printf '%s\n' '{"type":"system","subtype":"task_updated","task_id":"ag1","patch":{"status":"completed"}}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":null,"message":{"content":"<task-notification><task-id>ag2</task-id><status>completed</status></task-notification>"}}'
  printf '%s\n' '{"type":"result","subtype":"success","result":"PHASE RESULT plan: STOP — round 1 not collected"}'
} > "$T/sfondo.jsonl"
# the same reviewers in the foreground (one message, three calls) and a background Bash job collected before the end
{ printf '%s\n' '{"type":"system","subtype":"init"}'
  for i in 1 2 3; do riv f$i maat:spec-plan-reviewer; done
  printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"make long","run_in_background":true}}]}}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"b1","content":"Command running in background with ID: bx1"}]}}'
  printf '%s\n' '{"type":"system","subtype":"task_notification","task_id":"bx1","status":"completed"}'
  printf '%s\n' '{"type":"result","subtype":"success","result":"PHASE RESULT plan: OK"}'
} > "$T/primo-piano.jsonl"
# a background Bash job never collected, in a session transcript (no init, no result: the closing is the end)
{ printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b2","name":"Bash","input":{"command":"sleep 600","run_in_background":true}}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b2","content":"Command running in background with ID: bx2"}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}'
} > "$T/job.jsonl"
# (B8 review) jobs opened only by the call: a foreground Bash that prints the receipt text and a foreground agent whose
# reply begins with «Async agent launched» open nothing
{ printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"f1","name":"Bash","input":{"command":"cat old.log"}}]}}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"f1","content":"Command running in background with ID: fk1"}]}}'
  printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"f2","name":"Agent","input":{"subagent_type":"maat:spec-plan-reviewer","prompt":"lens"}}]}}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"f2","content":"Async agent launched successfully.\nagentId: fk2 (quoted by the reviewer)"}]}}'
} > "$T/finti.jsonl"
# a `result` event is a closing: the agent notified only after it was open at that closing
{ printf '%s\n' '{"type":"system","subtype":"init"}'
  printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"r1","name":"Agent","input":{"subagent_type":"maat:spec-plan-reviewer","prompt":"lens","run_in_background":true}}]}}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"r1","content":"Async agent launched successfully.\nagentId: ag7 (internal ID)"}]}}'
  printf '%s\n' '{"type":"result","subtype":"success","result":"PHASE RESULT plan: STOP"}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":null,"message":{"content":"<task-notification><task-id>ag7</task-id><status>completed</status></task-notification>"}}'
} > "$T/result.jsonl"
# the main-session filter: a sub-agent's own background job never collected does not count, and a notification in a
# sub-agent's message does not close the main session's job
{ printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"m1","name":"Bash","input":{"command":"make long","run_in_background":true}}]}}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"m1","content":"Command running in background with ID: bx5"}]}}'
  printf '%s\n' '{"type":"assistant","parent_tool_use_id":"tu_s","message":{"content":[{"type":"tool_use","id":"s1","name":"Bash","input":{"command":"sleep 9","run_in_background":true}}]}}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":"tu_s","message":{"content":[{"type":"tool_result","tool_use_id":"s1","content":"Command running in background with ID: sub1"}]}}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":"tu_s","message":{"content":"<task-notification><task-id>bx5</task-id><status>completed</status></task-notification>"}}'
} > "$T/sotto.jsonl"
# closed through BashOutput (final status), TaskOutput (final status) and KillShell
{ for k in k1 k2 k3; do
    printf '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"c%s","name":"Bash","input":{"command":"job %s","run_in_background":true}}]}}\n' "$k" "$k"
    printf '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"c%s","content":"Command running in background with ID: %s"}]}}\n' "$k" "$k"
  done
  printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"o1","name":"BashOutput","input":{"bash_id":"k1"}}]}}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"o1","content":"<status>completed</status><exit_code>0</exit_code>"}]}}'
  printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"o2","name":"TaskOutput","input":{"task_id":"k2"}}]}}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"o2","content":"<status>failed</status>"}]}}'
  printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"o3","name":"KillShell","input":{"shell_id":"k3"}}]}}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"o3","content":"killed"}]}}'
} > "$T/raccolti.jsonl"
apri() { "$FIC_PY" "$(nat "$T/ap.py")" "$(nat "$1")" "$(nat "$T/sfondo.jsonl")" "$(nat "$T/primo-piano.jsonl")" "$(nat "$T/job.jsonl")" \
  "$(nat "$T/finti.jsonl")" "$(nat "$T/result.jsonl")" "$(nat "$T/sotto.jsonl")" "$(nat "$T/raccolti.jsonl")" 2>&1 | tr -d '\r'; }
o=$(apri "$TRX")
check "aperti: tre revisori in background, la sessione risvegliata con due ancora aperti → ag1,ag2 (anche se alla fine sono tutti notificati)" 'printf "%s\n" "$o" | grep -qx "sfondo.jsonl	ag1,ag2"' "$o"
check "aperti: revisori in primo piano e un job in background raccolto prima della chiusura → nessuno" 'printf "%s\n" "$o" | grep -qx "primo-piano.jsonl	-"' "$o"
check "aperti: un job Bash in background mai raccolto, transcript di sessione (chiusura = fine del file) → bx2" 'printf "%s\n" "$o" | grep -qx "job.jsonl	bx2"' "$o"
check "aperti: un Bash in primo piano che stampa la ricevuta e un agente in primo piano che risponde «Async agent launched» → nessuno" 'printf "%s\n" "$o" | grep -qx "finti.jsonl	-"' "$o"
check "aperti: l evento result e una chiusura (l agente notificato solo dopo) → ag7" 'printf "%s\n" "$o" | grep -qx "result.jsonl	ag7"' "$o"
check "aperti: il job di un sotto-agente non conta e la sua notifica non chiude il job principale → bx5" 'printf "%s\n" "$o" | grep -qx "sotto.jsonl	bx5"' "$o"
check "aperti: chiusi da BashOutput e TaskOutput con uno stato finale e da KillShell → nessuno" 'printf "%s\n" "$o" | grep -qx "raccolti.jsonl	-"' "$o"
# bash: the receipt of a background run is not its output (the call asked for the background, or the receipt text)
{ printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"g1","name":"Bash","input":{"command":"make probe","run_in_background":true}}]}}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"g1","content":"Command running in background with ID: bp1"}]}}'
} > "$T/ricevuta.jsonl"
tr_ "$TRX" bash "make probe" "running in background" < "$T/ricevuta.jsonl" > "$T/o" 2>&1; rc=$?
check "bash: la ricevuta di un lancio in background non e' il risultato del comando → non trovato" '[ $rc -eq 1 ]' "$(cat "$T/o")"

# --- counterproofs: a mutated copy of the module, its cases go red ---
mutx() { # <name> <marker> <replacement line> → $T/mut-<name>.py (1 if the marker is not on exactly one line)
  "$FIC_PY" - "$(nat "$TRX")" "$(nat "$T/mut-$1.py")" "$2" "$3" <<'EOF'
import sys
src, dst, marca, nuova = sys.argv[1:5]
rr = open(src, encoding="utf-8").read().split("\n")
idx = [i for i, l in enumerate(rr) if marca in l]
if len(idx) != 1:
    sys.exit(1)
ind = rr[idx[0]][:len(rr[idx[0]]) - len(rr[idx[0]].lstrip())]
rr[idx[0]] = ind + nuova
open(dst, "w", encoding="utf-8").write("\n".join(rr))
EOF
}
cp "$HERE/maat_msg.py" "$T/"; mkdir -p "$T/lib"; cp "$HERE/lib/messages.tsv" "$T/lib/"   # the copies find the catalog
if mutx principale "# SESSIONE-PRINCIPALE" "return True"; then
  tr_ "$T/mut-principale.py" bash "${CMD}er" "DepthError: nesting limit 64" < "$T/fase.jsonl" > "$T/o" 2>&1; rc=$?
  check "controprova: senza il filtro della sessione principale il comando del sidechain e' trovato (il caso sidechain e' rosso)" '[ $rc -eq 0 ]' "$(cat "$T/o")"
else check "controprova sessione principale: la mutazione si applica" false; fi
if mutx esatto "# COMANDO-ESATTO" "if c[\"name\"] != \"Bash\" or comando not in (c[\"input\"].get(\"command\") or \"\"):"; then
  tr_ "$T/mut-esatto.py" bash "${CMD%p}" "DepthError: nesting limit 64" < "$T/fase.jsonl" > "$T/o" 2>&1; rc=$?
  check "controprova: comando confrontato per inclusione → quello piu' corto di un carattere e' trovato (rosso)" '[ $rc -eq 0 ]' "$(cat "$T/o")"
else check "controprova comando esatto: la mutazione si applica" false; fi
if mutx contato "# RISULTATO-CONTATO" "True for _x in [0]):"; then
  o=$(tr_ "$T/mut-contato.py" conta "$R" "$(nat "$T/p1.jsonl")" "$(nat "$T/p2.jsonl")" 2>&1)
  check "controprova: conta senza il controllo del risultato → il lancio asincrono e l'errore contano (5, rosso)" '[ "$(printf "%s" "$o" | tr -d "\r")" = 5 ]' "$o"
else check "controprova conta: la mutazione si applica" false; fi

if mutx ricevuta "# RICEVUTA-BASH" "pass"; then
  tr_ "$T/mut-ricevuta.py" bash "make probe" "running in background" < "$T/ricevuta.jsonl" > "$T/o" 2>&1; rc=$?
  check "controprova: la ricevuta del Bash in background accettata come risultato → trovato (rosso)" '[ $rc -eq 0 ]' "$(cat "$T/o")"
else check "controprova ricevuta: la mutazione si applica" false; fi
mutap() { # <name> <marker> <replacement> <file> <expected of the mutant>
  if mutx "$1" "$2" "$3"; then
    o=$(apri "$T/mut-$1.py"); MF=$4 MA=$5
    check "controprova aperti ($1): $4 diventa «$5» (rosso)" 'printf "%s\n" "$o" | grep -qx "$MF	$MA"' "$o"
  else check "controprova aperti ($1): la mutazione si applica" false; fi
}
mutap bashtesto "# BASH-APERTO-DALLA-CHIAMATA" 'if nome == "Bash":' finti.jsonl fk1
mutap agentetesto "# AGENTE-APERTO-DALLA-CHIAMATA" 'or AGENT_BG_RE.search(t[:300]) or tur.get("status") == "async_launched"):' finti.jsonl fk2
mutap result "# CHIUSURA-RESULT" 'if False:' result.jsonl -
mutap notifiche "# NOTIFICHE-PRINCIPALE" 'if False:' sotto.jsonl sub1
echo "transcript.test.sh: $pass ok, $fail falliti"
[ "$fail" = 0 ]
