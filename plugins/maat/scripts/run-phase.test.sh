#!/usr/bin/env bash
# run-phase.test.sh — tests of run-phase.sh with a fake `claude`: code-phase locks,
# --lock-status, guard self-test, arguments passed to the subsession, attribution
# (touched.txt) and outcome (.esito).
#   bash plugins/maat/scripts/run-phase.test.sh
#   RP=/path/variant.sh bash .../run-phase.test.sh   # the variant must live in this folder
#   FIC_DRIVER=0 RP=/path/variant.sh bash .../run-phase.test.sh   # (1.5.1) a variant that changes VALIDA_PY (the
#     internal validator): without FIC_DRIVER=0 the Python driver validates and the mutation is not seen
# The real lock (inside .git) is not touched: FIC_LOCK points to a temporary directory; FIC_REPO points
# to a temporary git repo, so the fake claude changes files there and not in the project.
set -uo pipefail
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
HERE=$(cd "$(dirname "$0")" && pwd)
RP=${RP:-$HERE/run-phase.sh}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export FIC_LOCK="$T/lock"
export FIC_REPO="$T/repo"
mkdir -p "$FIC_REPO" && (cd "$FIC_REPO" && git init -q . && git config user.email t@t && git config user.name t   && printf 'uno
' > a.py && printf 'due
' > b.py && git add -A && git commit -qm init)
fail=0 n=0
check() { n=$((n + 1)); if eval "$2"; then :; else fail=$((fail + 1)); echo "FAIL: $1"; fi; }

# fake claude: records arguments and environment, sleeps FAKE_SLEEP seconds, writes a result.
cat > "$T/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_OUT.args"
echo "FIC_PHASE=$FIC_PHASE" > "$FAKE_OUT.env"
echo "MAAT_CONFIG=${MAAT_CONFIG:-}" >> "$FAKE_OUT.env"
nc=$(( $(cat "$FAKE_OUT.calls" 2>/dev/null || echo 0) + 1 )); echo "$nc" > "$FAKE_OUT.calls"
cat > "$FAKE_OUT.stdin"; cp "$FAKE_OUT.stdin" "$FAKE_OUT.stdin.$nc"
if [ -f "$FAKE_OUT.gates-done" ]; then echo si; else echo no; fi > "$FAKE_OUT.gates-at-start.$nc"
[ -n "${FAKE_SPEC:-}" ] && echo "chiamata $nc" >> "$FAKE_SPEC"
[ -n "${FAKE_EARLY:-}" ] && echo "$FAKE_EARLY"
sleep "${FAKE_SLEEP:-0}"
# FAKE_WAIT_GATES: the tree changes only after the gates have computed their key (in the parallel window)
[ -n "${FAKE_WAIT_GATES:-}" ] && for _ in $(seq 1 600); do [ -f "$FAKE_OUT.gates-done" ] && break; sleep 0.1; done
[ -n "${FAKE_TOUCH:-}" ] && echo toccato >> "$FAKE_TOUCH"
echo "FIC_SCOPE=${FIC_SCOPE:-}" >> "$FAKE_OUT.env"
# the sub-session command appears in the log as a Bash tool_use (FAKE_LOGCMD: one extra, only in the log);
# FAKE_ALTRO writes to the tree WITHOUT appearing in the log: another flow in the same working tree (ALTRI FLUSSI)
tu() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"'"$s"'"}}]}}'; }
[ -n "${FAKE_CMD:-}" ] && tu "$FAKE_CMD"
[ -n "${FAKE_LOGCMD:-}" ] && tu "$FAKE_LOGCMD"
[ -n "${FAKE_ALTRO:-}" ] && eval "$FAKE_ALTRO"
[ -n "${FAKE_CMD:-}" ] && eval "$FAKE_CMD"
[ -n "${FAKE_BREAK:-}" ] && mv "$FAKE_BREAK/.git" "$FAKE_BREAK/.git.rotto"
echo '{"type":"user","message":{"content":[{"type":"tool_result","content":"ESITO FASE implement: OK — esempio letto da SKILL.md"}]}}'
if [ -n "${FAKE_RESULT_N:-}" ]; then
  echo '{"type":"result","result":"ESITO FASE x: OK — finto '"$nc"'","structured_output":{"fase":"'"$FIC_PHASE"'","esito":"OK","motivo":"finto '"$nc"'","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[],"copertura":[{"requisito":"R1","test":["tests/test_a.py::test_a"]}]}}'
elif [ -n "${FAKE_RESULT:-}" ]; then echo "$FAKE_RESULT"
else echo '{"type":"result","result":"lavoro fatto\nESITO FASE x: OK — finto","structured_output":{"fase":"'"$FIC_PHASE"'","esito":"OK","motivo":"finto","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}'; fi
EOF
chmod +x "$T/claude"
export CLAUDE_BIN="$T/claude"
# fake gates.sh (the real one has its own suite, script/fic/gates.test.sh): records the arguments, prints the outcome
cat > "$T/gates" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_OUT.gates-args"
sleep "${FAKE_GATES_SLEEP:-0}"
echo x >> "$FAKE_OUT.gates-calls"
if [ -n "${FAKE_GATES_EV:-}" ]; then   # evidence per key (the tree), reused for an identical key, as in gates.sh
  k=$(cd "$FIC_REPO" && bash "$FAKE_RS" tree | sha256sum | cut -c1-16)
  if [ -d "$2/evidence/$k" ]; then echo riuso >> "$FAKE_OUT.gates-esito"; else mkdir -p "$2/evidence/$k"; echo eseguito >> "$FAKE_OUT.gates-esito"; fi
  : > "$FAKE_OUT.gates-done"
  echo "gates: esito=PASS chiave=$k evidence=$2/evidence/$k"; exit 0
fi
: > "$FAKE_OUT.gates-done"
echo "tests-be: PASS (eseguito) — finto"
echo "gates: esito=PASS chiave=k0 evidence=C:/finto/evidence/k0"
EOF
export FIC_GATES="$T/gates" FAKE_RS="$HERE/review-surface.sh"
echo "/full-implementation-cycle --worker=probe x" > "$T/prompt.md"
run() { FAKE_OUT="$T/$2" bash "$RP" "$T/run" "$2" "$T/prompt.md" 2>"$T/$2.err" </dev/null; }

# 1. plan phase: no CODE lock (only the per-spec lock, released at the end), correct arguments
run x 01-plan; rc=$?
check "plan esce 0" '[ $rc -eq 0 ]'
check "plan non prende il lock di codice" '[ ! -d "$FIC_LOCK" ]'
check "  e rilascia il lock per spec" '[ ! -d "$T/run/plan.lock" ]'
check "plan: FIC_PHASE=plan" 'grep -qx "FIC_PHASE=plan" "$T/01-plan.env"'
check "hook passato con --settings" 'grep -qx -- "--settings" "$T/01-plan.args" && grep -q "guard.py" "$T/01-plan.args"'
check "  --settings con guardia E hook Stop (stop-hook.py)" 'grep -F "\"PreToolUse\"" "$T/01-plan.args" | grep -q guard.py && grep -F "\"Stop\"" "$T/01-plan.args" | grep -q "stop-hook.py"'
# pk08 (Linux): the Stop hook path is the real one, not «/stop-hook.py» (pwd -W missing outside Windows)
STOPP=$(grep -F '"Stop"' "$T/01-plan.args" | grep -o '[^"\\ ]*stop-hook\.py' | head -1)
check "  hook Stop: il file nel comando esiste ($STOPP)" '[ -n "$STOPP" ] && [ "$STOPP" != /stop-hook.py ] && [ -f "$STOPP" ]'
check "plan: nessun gate del driver" '[ ! -f "$T/run/log/01-plan.gates" ] && [ ! -f "$T/01-plan.gates-args" ]'
check "deny per prefisso ancora passato" 'grep -qx -- "--disallowedTools" "$T/01-plan.args"'
check "niente MCP: --strict-mcp-config senza --mcp-config" 'grep -qx -- "--strict-mcp-config" "$T/01-plan.args" && ! grep -qx -- "--mcp-config" "$T/01-plan.args"'
check ".exit scritto" '[ "$(cat "$T/run/log/01-plan.exit")" = 0 ]'
# 1a. pk05: the DENY is generated by the guard (core + release + vietati_extra), MAAT_CONFIG reaches the subsession
check "  senza maat.json: DENY del nucleo, niente MAAT_CONFIG esportato" 'grep -qx "Bash(git push:\*)" "$T/01-plan.args" && ! grep -q "rsync-once" "$T/01-plan.args" && grep -qx "MAAT_CONFIG=" "$T/01-plan.env"'
SSX=$(cygpath -m "$HERE/../examples/nuxt-fastapi.maat.json" 2>/dev/null || printf '%s' "$HERE/../examples/nuxt-fastapi.maat.json")
MAAT_CONFIG="$SSX" run x 01a-plan; rc=$?
check "con l'esempio nuxt-fastapi: la sonda di produzione e' negata, la fase gira" '[ $rc -eq 0 ] && [ -f "$T/01a-plan.args" ]'
check "  DENY con rilascio e vietati_extra" 'for v in "Bash(bash script/deploy-production.sh:*)" "Bash(script/deploy-production.sh:*)" "Bash(bash script/rsync-once.sh:*)" "Bash(bash script/rsync.sh:*)" "Bash(script/rsync-once.sh:*)" "Bash(bash script/prod:*)" "Bash(rm -rf:*)"; do grep -qxF -- "$v" "$T/01a-plan.args" || exit 1; done'
check "  MAAT_CONFIG assoluto nell'ambiente della sotto-sessione" 'grep -qxF "MAAT_CONFIG=$SSX" "$T/01a-plan.env"'
# pk08: MAAT_CONFIG relative to the working folder (with a space) arrives absolute even outside Windows (no cygpath -a)
mkdir -p "$T/cfg rel" && cp "$HERE/../examples/nuxt-fastapi.maat.json" "$T/cfg rel/ss.json"
CREL=$(cd "$T/cfg rel" && { pwd -W 2>/dev/null || pwd; })/ss.json
(cd "$T" && MAAT_CONFIG="cfg rel/ss.json" run x 01c-plan); rc=$?
check "  MAAT_CONFIG relativo reso assoluto ($CREL)" '[ $rc -eq 0 ] && grep -qxF "MAAT_CONFIG=$CREL" "$T/01c-plan.env"'
# 1b. plugin in the subsession (pk04a-1, step 7): no --plugin-dir by default (the plugin is enabled in the
#     project, pk01 D1); with MAAT_PLUGIN_DIR=<folder> --plugin-dir <folder>; the phase rules are the
#     skill's child-rules.md. Counterproof on a mutated copy of the plugin: --plugin-dir always ⇒ the first case fails.
check "nessun --plugin-dir per default" '! grep -qx -- "--plugin-dir" "$T/01-plan.args"'
check "  --append-system-prompt con child-rules.md della skill del plugin" 'grep -qF -- "$(head -1 "$HERE/../skills/full-implementation-cycle/child-rules.md")" "$T/01-plan.args"'
MAAT_PLUGIN_DIR="$T/cartella plugin" run x 01b-plan
check "MAAT_PLUGIN_DIR impostata: --plugin-dir <cartella>" '[ "$(grep -A1 -x -- "--plugin-dir" "$T/01b-plan.args" | sed -n 2p)" = "$T/cartella plugin" ]'
PDM="$T/mut plugin-dir/maat"; mkdir -p "$(dirname "$PDM")" && cp -r "$HERE/.." "$PDM" && find "$PDM" -name __pycache__ -type d -prune -exec rm -rf {} +
sed -i 's|^\[ -n "\${MAAT_PLUGIN_DIR:-}" \] && PLUGIN_ARGS=(--plugin-dir "\$MAAT_PLUGIN_DIR")$|PLUGIN_ARGS=(--plugin-dir "${MAAT_PLUGIN_DIR:-$MAAT_ROOT}")   # MUTANTE|' "$PDM/scripts/run-phase.sh"
check "  premessa: mutazione «--plugin-dir sempre» applicata" 'grep -q "# MUTANTE$" "$PDM/scripts/run-phase.sh"'
# its own run dir: the mutated copy is another plugin, with the fingerprint of $T/run it would exit with 6 (pk04a-2)
FAKE_OUT="$T/01c-plan" bash "$PDM/scripts/run-phase.sh" "$T/run-1c" 01c-plan "$T/prompt.md" 2>"$T/01c-plan.err" </dev/null
check "  controprova: col mutante il caso «nessun --plugin-dir per default» cade" 'grep -qx -- "--plugin-dir" "$T/01c-plan.args"'

# 2. two concurrent code phases: the second exits 4, the first releases the lock
check "--lock-status libero → 0" 'out=$(bash "$RP" --lock-status); [ $? -eq 0 ] && [ "$out" = libero ]'
FAKE_SLEEP=6 run x 02-implement & a=$!
for _ in $(seq 1 40); do [ -f "$FIC_LOCK/owner" ] && grep -q '^cpid=' "$FIC_LOCK/owner" && break; sleep 0.25; done
check "il lock contiene i PID" 'grep -q "^pid=" "$FIC_LOCK/owner" && grep -q "^cpid=" "$FIC_LOCK/owner"'
check "--lock-status durante una fase di codice → 1 col proprietario" 'out=$(bash "$RP" --lock-status); [ $? -eq 1 ] && printf "%s" "$out" | grep -q "occupato: run=.*label=02-implement"'
check "--lock-status dentro il ciclo (FIC_PHASE) → 0" 'FIC_PHASE=review bash "$RP" --lock-status | grep -q "dentro il ciclo"'
check "--lock-status da una fase di piano → 1 (il lock non e' suo)" 'FIC_PHASE=plan bash "$RP" --lock-status >/dev/null; [ $? -eq 1 ]'
run x 03-review; rc=$?
check "fase di codice concorrente → 4" '[ $rc -eq 4 ]'
check "  con .exit=4 (il Monitor non resta appeso)" '[ "$(cat "$T/run/log/03-review.exit")" = 4 ]'
check "  e il motivo su stderr" 'grep -q "lock occupato" "$T/run/log/03-review.stderr"'
check "  e la sottosessione non e partita" '[ ! -f "$T/03-review.args" ]'
run x 04-plan; rc=$?
check "un piano gira anche col lock preso" '[ $rc -eq 0 ]'
wait $a; rc=$?
check "la prima fase finisce 0" '[ $rc -eq 0 ]'
check "e rilascia il lock" '[ ! -d "$FIC_LOCK" ]'

# 2b. per-spec lock: two plans on the SAME spec → the second exits 4 with the owner; different specs → parallel
# (20 s: the two phases launched below, with the harness fingerprint, may exceed the previous 6 s on Windows)
FAKE_SLEEP=20 run x 40-plan & a=$!
for _ in $(seq 1 40); do [ -f "$T/run/plan.lock/owner" ] && grep -q '^cpid=' "$T/run/plan.lock/owner" && break; sleep 0.25; done
check "plan.lock con i PID" 'grep -q "^pid=" "$T/run/plan.lock/owner" && grep -q "^cpid=" "$T/run/plan.lock/owner"'
run x 41-plan; rc=$?
check "secondo plan sulla stessa spec → 4" '[ $rc -eq 4 ] && [ "$(cat "$T/run/log/41-plan.exit")" = 4 ]'
check "  col proprietario su stderr" 'grep -q "lock del piano occupato.*label=40-plan" "$T/run/log/41-plan.stderr"'
check "  e la sottosessione non e partita" '[ ! -f "$T/41-plan.args" ]'
FAKE_OUT="$T/42-plan" bash "$RP" "$T/altra.run" 42-plan "$T/prompt.md" 2>/dev/null </dev/null; rc=$?
check "plan di una spec diversa parte in parallelo" '[ $rc -eq 0 ] && [ -f "$T/42-plan.args" ] && [ ! -d "$T/altra.run/plan.lock" ]'
check "  mentre il primo tiene ancora il suo lock" '[ -d "$T/run/plan.lock" ]'
wait $a; rc=$?
check "il primo plan finisce 0 e rilascia plan.lock" '[ $rc -eq 0 ] && [ ! -d "$T/run/plan.lock" ]'
mkdir -p "$T/run/plan.lock"
printf 'run=%s\nlabel=43-plan\nsince=x\npid=999995\ncpid=999996\n' "$T/run" > "$T/run/plan.lock/owner"
run x 44-plan; rc=$?
check "plan.lock con PID morti → ripreso" '[ $rc -eq 0 ] && grep -q "ripreso" "$T/run/log/44-plan.stderr" && [ ! -d "$T/run/plan.lock" ]'

# 2c. same LABEL on the same spec (repeated sequential labels, ux-6): the second exits 4 and does not
#     touch log/.exit/.stderr of the live phase
FAKE_EARLY='{"type":"system","subtype":"primo"}' FAKE_SLEEP=6 run x 50-plan & a=$!
for _ in $(seq 1 40); do [ -f "$T/run/plan.lock/owner" ] && grep -q '^cpid=' "$T/run/plan.lock/owner" && grep -q primo "$T/run/log/50-plan.jsonl" 2>/dev/null && break; sleep 0.25; done
echo "segno del primo" >> "$T/run/log/50-plan.stderr"
run x 50-plan; rc=$?
check "stessa etichetta → 4" '[ $rc -eq 4 ]'
check "  il .jsonl del primo e' intatto" 'grep -q primo "$T/run/log/50-plan.jsonl"'
check "  nessun .exit scritto nella label viva" '[ ! -f "$T/run/log/50-plan.exit" ]'
check "  .stderr del primo intatto" 'grep -q "segno del primo" "$T/run/log/50-plan.stderr"'
wait $a; rc=$?
check "  il primo finisce 0 col suo esito" '[ $rc -eq 0 ] && [ "$(cat "$T/run/log/50-plan.exit")" = 0 ] && grep -q "\"type\":\"result\"" "$T/run/log/50-plan.jsonl"'
# m3: when a label is relaunched, the previous watcher files (.result/.pos/.pending) disappear
for s in result pos pending; do echo vecchio > "$T/run/log/50-plan.jsonl.$s"; done
run x 50-plan
check "rilancio: .jsonl.result/.pos/.pending stantii rimossi" '[ ! -f "$T/run/log/50-plan.jsonl.result" ] && [ ! -f "$T/run/log/50-plan.jsonl.pos" ] && [ ! -f "$T/run/log/50-plan.jsonl.pending" ]'

# 3. orphan lock: dead PIDs, leftover .running → taken over
mkdir -p "$FIC_LOCK" "$T/old/log"
printf 'run=%s\nlabel=05-fix\nsince=x\npid=999991\ncpid=999992\n' "$T/old" > "$FIC_LOCK/owner"
date > "$T/old/log/05-fix.running"
run x 06-fix; rc=$?
check "lock con PID morti → ripreso, fase eseguita" '[ $rc -eq 0 ] && grep -q "ripreso" "$T/run/log/06-fix.stderr"'
check "  e rilasciato alla fine" '[ ! -d "$FIC_LOCK" ]'

# 3b. run-phase killed (SIGTERM, like TaskStop) while the subsession is alive → the lock stays;
#     once the subsession ends, the next phase takes it over.
FAKE_SLEEP=6 FAKE_OUT="$T/09-review" bash "$RP" "$T/run" 09-review "$T/prompt.md" 2>/dev/null </dev/null & rp=$!
for _ in $(seq 1 40); do [ -f "$FIC_LOCK/owner" ] && grep -q '^cpid=' "$FIC_LOCK/owner" && break; sleep 0.25; done
kill -TERM $rp; wait $rp 2>/dev/null
check "SIGTERM a run-phase con la sottosessione viva: il lock resta" '[ -d "$FIC_LOCK" ]'
run x 10-fix; rc=$?
check "  e un'altra fase di codice trova occupato (4)" '[ $rc -eq 4 ]'
sleep 7
run x 11-fix; rc=$?
check "  finita la sottosessione, il lock si riprende" '[ $rc -eq 0 ] && grep -q "ripreso" "$T/run/log/11-fix.stderr"'
check "  e viene rilasciato" '[ ! -d "$FIC_LOCK" ]'

# 4. guard not active → 5, no subsession
FIC_PYTHON="$T/non-esiste.exe" run x 07-implement; rc=$?
check "interprete assente → 5" '[ $rc -eq 5 ] && [ ! -f "$T/07-implement.args" ]'
check "  senza lasciare il lock" '[ ! -d "$FIC_LOCK" ]'
printf '#!/usr/bin/env bash\n[ "${1:-}" = -c ] && exit 0\ncat >/dev/null; exit 0\n' > "$T/py-finto"; chmod +x "$T/py-finto"
FIC_PYTHON="$T/py-finto" run x 08-review; rc=$?
check "guardia che non nega (fail-open) → 5" '[ $rc -eq 5 ] && [ ! -f "$T/08-review.args" ]'
check "  l'autotest fallisce chiuso anche con l'hook Stop: nessun gate lanciato" '[ ! -f "$T/run/log/08-review.gates" ] && [ ! -f "$T/08-review.gates-args" ]'

# 5. attribution: the implement phase records the paths it changed; the plan phase does not
rm -f "$T/run/touched.txt"
FAKE_TOUCH="$FIC_REPO/a.py" run x 12-plan
check "plan: nessun touched.txt" '[ ! -f "$T/run/touched.txt" ]'
(cd "$FIC_REPO" && git checkout -q -- a.py)
printf 'nuovo\n' > "$FIC_REPO/c.py"                     # someone else's work, already there before the phase
FAKE_TOUCH="$FIC_REPO/a.py" run x 13-implement; rc=$?
check "implement: touched.txt con il file cambiato dalla fase" '[ $rc -eq 0 ] && grep -qx "a.py" "$T/run/touched.txt"'
check "  ma non il file sporco gia' prima" '! grep -qx "c.py" "$T/run/touched.txt"'
check "  .pre-tree e .post-tree scritti" '[ -s "$T/run/log/13-implement.pre-tree" ] && [ -s "$T/run/log/13-implement.post-tree" ]'
# driver gates (harness-pt04): after an OK implement log/<label>.gates exists, with the touched.txt files
check "implement OK: log/13-implement.gates scritto" 'grep -q "^gates: esito=PASS" "$T/run/log/13-implement.gates" && grep -q "^exit=0 livello=legacy" "$T/run/log/13-implement.gates"'
check "  gates.sh con --run-dir, livello e i file di touched.txt" '[ "$(sed -n 1p "$T/13-implement.gates-args")" = --run-dir ] && [ "$(sed -n 3p "$T/13-implement.gates-args")" = legacy ] && grep -qx a.py "$T/13-implement.gates-args"'
# killed phase: .pre-tree without .post-tree → closed by the next code phase (even a review)
(cd "$FIC_REPO" && bash "$HERE/review-surface.sh" tree) > "$T/run/log/14-fix.pre-tree"
printf 'x\n' >> "$FIC_REPO/b.py"
FIC_REVIEW_PARALLEL=0 run x 15-review   # the sequence (below, 8: the parallel one)
check "pre-tree orfano chiuso dalla review: b.py attribuito" 'grep -qx "b.py" "$T/run/touched.txt" && [ -s "$T/run/log/14-fix.post-tree" ]'
check "review: gate PRIMA della sotto-sessione, evidenza in coda al prompt" '[ -s "$T/run/log/15-review.gates" ] && grep -q "^EVIDENZE DEI GATE (driver, run-phase.sh): C:/finto/evidence/k0" "$T/15-review.stdin" && grep -q "^/full-implementation-cycle" "$T/15-review.stdin"'
check "  il prompt originale non e' toccato" '! grep -q EVIDENZE "$T/prompt.md"'
FAKE_RESULT='{"type":"result","result":"ESITO FASE implement: STOP — deviazione"}' run x 19-implement
check "implement finito STOP: nessun gate" '[ ! -f "$T/run/log/19-implement.gates" ] && [ ! -f "$T/19-implement.gates-args" ]'
printf '/full-implementation-cycle --worker=fix x --tests=full\n' > "$T/prompt-full.md"
FAKE_OUT="$T/23-fix" bash "$RP" "$T/run" 23-fix "$T/prompt-full.md" 2>/dev/null </dev/null
check "fix OK con --tests=full nel prompt: gate al livello full" '[ "$(sed -n 3p "$T/23-fix.gates-args")" = full ]'

# 5b. killed phase of ANOTHER feature: its .pre-tree is closed in ITS run dir, before this
#     phase changes the tree (this phase's work must not end up in the other's touched.txt)
mkdir -p "$T/other/log" "$FIC_LOCK"
(cd "$FIC_REPO" && bash "$HERE/review-surface.sh" tree) > "$T/other/log/20-implement.pre-tree"
printf 'altra\n' > "$FIC_REPO/d.py"                    # written by the killed phase of the other feature
printf 'run=%s\nlabel=20-implement\nsince=x\npid=999993\ncpid=999994\n' "$T/other" > "$FIC_LOCK/owner"
FAKE_TOUCH="$FIC_REPO/e.py" run x 21-fix; rc=$?
check "lock orfano di un'altra feature: il suo pre-tree chiuso nella sua run dir" '[ $rc -eq 0 ] && grep -qx "d.py" "$T/other/touched.txt" && [ -s "$T/other/log/20-implement.post-tree" ]'
check "  il lavoro di questa fase va nel SUO touched.txt, non in quello dell'altra" 'grep -qx "e.py" "$T/run/touched.txt" && ! grep -qx "e.py" "$T/other/touched.txt"'
check "  e il lavoro dell'altra non finisce in questa" '! grep -qx "d.py" "$T/run/touched.txt"'

# 5c. attribution failed (final tree not computable) → no .post-tree: that is what stops cycle-state
FAKE_BREAK="$FIC_REPO" run x 22-implement; rc=$?
mv "$FIC_REPO/.git.rotto" "$FIC_REPO/.git"
check "tree finale fallito: .pre-tree si', .post-tree no" '[ -s "$T/run/log/22-implement.pre-tree" ] && [ ! -f "$T/run/log/22-implement.post-tree" ]'
check "  e l'AVVISO rimanda allo STOP" 'grep -q "niente .post-tree" "$T/run/log/22-implement.stderr"'

# 6. outcome: from the result event, never from the texts read; only if the subsession exits 0 without error
check "esito dall'evento result" '[ "$(sed -n 1p "$T/run/log/13-implement.esito")" = "ESITO FASE x: OK — finto" ]'
FAKE_RESULT='{"type":"result","is_error":true,"result":"ESITO FASE implement: OK"}' run x 16-implement
check "result con is_error → nessun .esito" '[ ! -f "$T/run/log/16-implement.esito" ]'
FAKE_RESULT='{"type":"system"}' run x 17-implement
check "nessun evento result → nessun .esito (l'ESITO letto in un tool_result non conta)" '[ ! -f "$T/run/log/17-implement.esito" ]'

# 6b. structured outcome (harness-pt08): --json-schema passed and JSON block revalidated here
check "--json-schema passato con lo schema (contenuto compatto, senza barre: MSYS le convertirebbe)" 's=$(sed -n "/^--json-schema$/{n;p;}" "$T/01-plan.args"); printf "%s" "$s" | grep -q "\"deviazioni\"" && ! printf "%s" "$s" | grep -q /'
check "JSON valido → log/<label>.result.json scritto" 'grep -q "\"fase\": \"implement\"" "$T/run/log/13-implement.result.json"'
FAKE_RESULT='{"type":"result","result":"fatto\nESITO FASE implement: OK — dichiarato"}' run x 24-implement
check "JSON assente → .esito STOP «uscita non valida»" 'sed -n 1p "$T/run/log/24-implement.esito" | grep -q "^PHASE RESULT implement: STOP — uscita non valida: nessun blocco JSON"'
check "  la riga ESITO del testo e' comunque scritta (originale=), con lo state" 'grep -qx "originale=ESITO FASE implement: OK — dichiarato" "$T/run/log/24-implement.esito" && grep -q "^state=" "$T/run/log/24-implement.esito"'
check "  nessun result.json e nessun gate (non e' un OK)" '[ ! -f "$T/run/log/24-implement.result.json" ] && [ ! -f "$T/run/log/24-implement.gates" ]'
FAKE_RESULT='{"type":"result","result":"ESITO FASE implement: OK","structured_output":{"fase":"implement","esito":"FORSE","motivo":"m","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[],"extra":1}}' run x 25-implement
# the two errors, in any order: jsonschema (if available, e.g. Linux python3) lists them in another order and
# without the field name compared with the minimal validator (pk08)
check "JSON fuori schema → STOP «uscita non valida» con gli errori" 'l=$(sed -n 1p "$T/run/log/25-implement.esito"); case "$l" in "PHASE RESULT implement: STOP — uscita non valida: "*FORSE*) ;; *) false ;; esac && case "$l" in *"uscita non valida: "*extra*) ;; *) false ;; esac && [ ! -f "$T/run/log/25-implement.result.json" ]'
FAKE_RESULT='{"type":"result","result":"ESITO FASE implement: OK","structured_output":{"fase":"review","esito":"OK","motivo":"m","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}' run x 26-implement
check "JSON di un'altra fase → STOP «uscita non valida»" 'sed -n 1p "$T/run/log/26-implement.esito" | grep -q "uscita non valida: fase .review. diversa"'
FAKE_RESULT='{"type":"result","result":"fatto\nESITO FASE implement: OK — r\n```json\n{\"fase\":\"implement\",\"esito\":\"OK\",\"motivo\":\"m\",\"deviazioni\":[\"passo 8 adattato\"],\"bloccato_su\":\"nessuno\",\"file\":[\"a.py\"],\"gate_interni\":[{\"comando\":\"pytest\",\"esito\":\"PASS\"}],\"finding\":[{\"severita\":\"major\",\"file\":\"a.py\",\"riga\":null,\"testo\":\"t\"}]}\n```"}' run x 27-implement
check "senza structured_output: vale l'ultimo recinto json del testo" 'grep -q "passo 8 adattato" "$T/run/log/27-implement.result.json"'
check "prosa OK, JSON con deviazioni → .esito STOP (il piu conservativo), prosa sotto originale=" 'sed -n 1p "$T/run/log/27-implement.esito" | grep -q "^PHASE RESULT implement: STOP — JSON: deviazioni dichiarate (1): passo 8 adattato" && grep -qx "originale=ESITO FASE implement: OK — r" "$T/run/log/27-implement.esito"'
check "  e nessun gate (non e' un OK)" '[ ! -f "$T/run/log/27-implement.gates" ]'
FAKE_RESULT='{"type":"result","result":"ESITO FASE implement: STOP — migrazione da applicare","structured_output":{"fase":"implement","esito":"OK","motivo":"m","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}' run x 28-implement
check "prosa STOP, JSON OK → .esito resta STOP" 'sed -n 1p "$T/run/log/28-implement.esito" | grep -q "^ESITO FASE implement: STOP — migrazione" && [ -f "$T/run/log/28-implement.result.json" ] && [ ! -f "$T/run/log/28-implement.gates" ]'
# 1.3.0: the English result line the agents now write, with bloccato_su "none", reads like the Italian one
FAKE_RESULT='{"type":"result","result":"done\nPHASE RESULT implement: OK — done","structured_output":{"fase":"implement","esito":"OK","motivo":"m","deviazioni":[],"bloccato_su":"none","file":[],"gate_interni":[],"finding":[]}}' run x 28b-implement
check "riga «PHASE RESULT implement: OK» e bloccato_su «none» → .esito OK, gate eseguiti" '[ "$(sed -n 1p "$T/run/log/28b-implement.esito")" = "PHASE RESULT implement: OK — done" ] && [ -f "$T/run/log/28b-implement.gates" ]'
FAKE_RESULT='{"type":"result","result":"PHASE RESULT implement: STOP — migration to apply","structured_output":{"fase":"implement","esito":"OK","motivo":"m","deviazioni":[],"bloccato_su":"none","file":[],"gate_interni":[],"finding":[]}}' run x 28c-implement
check "  riga inglese STOP con JSON OK → .esito resta STOP, nessun gate" 'sed -n 1p "$T/run/log/28c-implement.esito" | grep -q "^PHASE RESULT implement: STOP — migration to apply" && [ ! -f "$T/run/log/28c-implement.gates" ]'

# 6b-bis. defensive deviations: ALL with "difensiva: " → no STOP, recorded (file, AVVISO, note in the changelog
# outside the fingerprint); even a single one without the prefix → STOP as before; the review receives the list to judge.
DD="$T/run/log/deviazioni-difensive.txt"
djson() { # $1 JSON list of the deviations → result event with OK prose
  printf '{"type":"result","result":"ESITO FASE implement: OK — fatto","structured_output":{"fase":"implement","esito":"OK","motivo":"m","deviazioni":%s,"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}' "$1"
}
FAKE_RESULT=$(djson '["difensiva: stato.ts:42 — ramo per uno stato senza data (escluso dal CHECK del DB): nessun caso previsto cambia"]') run x 29-implement
check "solo deviazioni difensive → .esito OK (l'esito di senza deviazioni), gate eseguiti" '[ "$(sed -n 1p "$T/run/log/29-implement.esito")" = "ESITO FASE implement: OK — fatto" ] && [ -f "$T/run/log/29-implement.gates" ]'
check "  una riga per deviazione in log/deviazioni-difensive.txt (etichetta, testo)" '[ "$(grep -c . "$DD")" = 1 ] && grep -q "^29-implement	difensiva: stato.ts:42 — ramo per uno stato" "$DD"'
check "  e un AVVISO in .esito, dopo state=" 'grep -q "^AVVISO: 1 deviazioni difensive dichiarate" "$T/run/log/29-implement.esito" && [ "$(sed -n 2p "$T/run/log/29-implement.esito" | cut -c1-6)" = "state=" ]'
FAKE_RESULT=$(djson '["difensiva: a.py:1 — ripiego", "passo 3 adattato"]') run x 30-implement
check "una difensiva e una no → STOP (deviazioni dichiarate, tutte elencate), niente gate" 'sed -n 1p "$T/run/log/30-implement.esito" | grep -q "^PHASE RESULT implement: STOP — JSON: deviazioni dichiarate (2): difensiva: a.py:1 — ripiego; passo 3 adattato" && [ ! -f "$T/run/log/30-implement.gates" ]'
check "  e nessuna riga registrata per la fase ferma" '! grep -q "^30-implement	" "$DD" && ! grep -q "deviazioni difensive" "$T/run/log/30-implement.esito"'
check "nessun prefisso (27-implement) → STOP come prima, nulla registrato" 'sed -n 1p "$T/run/log/27-implement.esito" | grep -q "STOP — JSON: deviazioni dichiarate" && ! grep -q "^27-implement	" "$DD"'
FAKE_RESULT=$(djson '["difensiva:ramo"]') run x 31-implement
check "prefisso storpiato («difensiva:» senza spazio) → non difensiva, STOP" 'sed -n 1p "$T/run/log/31-implement.esito" | grep -q "STOP — JSON: deviazioni dichiarate (1)"'
FAKE_RESULT=$(djson '["difensiva: stato.ts:42 — rilancio"]') run x 29-implement
check "rilancio della stessa etichetta: le sue righe sostituite, non duplicate" '[ "$(grep -c "^29-implement	" "$DD")" = 1 ] && grep -q "rilancio$" "$DD"'
run x 32-review
check "review: DEVIAZIONI DIFENSIVE in coda al prompt, con la consegna e le righe" 'grep -q "^DEVIAZIONI DIFENSIVE (driver, run-phase.sh): .*deviazioni-difensive.txt — .*e. un finding major" "$T/32-review.stdin" && grep -q "^29-implement	difensiva: stato.ts:42 — rilancio" "$T/32-review.stdin"'
# note in the spec's changelog: Approved basis fingerprint and State unchanged (the plan stays FRESH)
W6="$T/w6"; SP6="$W6/spec-d.md"; R6="$W6/spec-d.run"; mkdir -p "$R6"
sp6() { printf '%s\r\n' "# D" "## Requisiti" "1. A." "## Piano di implementazione" "Plan status: APPROVED" "Test level: std" \
  "Superfici a rischio: nessuna" "$@" "### Passi" "1. Modificare \`a.py\`." "### Changelog revisione piano" "- giro 1: ok" "" > "$SP6"; }
sp6; b6=$(bash "$HERE/plan-check.sh" basis "$SP6" | tr -d '\r' | sed -n 's/^Basis: //p')
sp6 "Approved basis: $b6"   # the Approved basis line is outside the fingerprint (no sed -i: in Git Bash it strips the CRs)
bb() { bash "$HERE/plan-check.sh" basis "$SP6" | tr -d '\r'; }
b6a=$(bb); s6a=$(bash "$HERE/cycle-state.sh" "$SP6" | sed -n 's/^State: //p')
FAKE_OUT="$T/33-implement" FAKE_RESULT=$(djson '["difensiva: a.py:9 — default col codice grezzo"]') bash "$RP" "$R6" 33-implement "$T/prompt.md" 2>/dev/null </dev/null
check "nota «- nota (deviazione difensiva, <etichetta>): …» subito dopo l'ultima riga del changelog, CRLF conservato" 'tr -d "\r" < "$SP6" | grep -A1 "^- giro 1: ok$" | tail -1 | grep -qx -- "- nota (deviazione difensiva, 33-implement): difensiva: a.py:9 — default col codice grezzo" && [ "$(tr -cd "\r" < "$SP6" | wc -c)" = "$(wc -l < "$SP6")" ]'
check "  impronta Approved basis e State invariati (Status: FRESH), .esito OK" '[ "$(bb)" = "$b6a" ] && bb | grep -qx "Status: FRESH" && [ "$(bash "$HERE/cycle-state.sh" "$SP6" | sed -n "s/^State: //p")" = "$s6a" ] && sed -n 1p "$R6/log/33-implement.esito" | grep -q "^ESITO FASE implement: OK"'
# 1.3.0: English plan headings («## Implementation plan», «### Plan review changelog»): the note goes into the
# English changelog (zones as in plan-check.sh annotate), English "defensive: " prefix, fingerprint unchanged
W7="$T/w7"; SP7="$W7/spec-e.md"; R7="$W7/spec-e.run"; mkdir -p "$R7"
sp7() { printf '%s\n' "# E" "## Requirements" "1. A." "## Implementation plan" "Plan status: APPROVED" "Test level: std" \
  "Risk surfaces: none" "$@" "### Steps" "1. Change \`a.py\`." "### Plan review changelog" "- round 1: ok" "" > "$SP7"; }
sp7; b7=$(bash "$HERE/plan-check.sh" basis "$SP7" | tr -d '\r' | sed -n 's/^Basis: //p'); sp7 "Approved basis: $b7"
b7a=$(bash "$HERE/plan-check.sh" basis "$SP7" | tr -d '\r')
FAKE_OUT="$T/34-implement" FAKE_RESULT='{"type":"result","result":"PHASE RESULT implement: OK — done","structured_output":{"fase":"implement","esito":"OK","motivo":"m","deviazioni":["defensive: a.py:9 — raw code default"],"bloccato_su":"none","file":[],"gate_interni":[],"finding":[]}}' bash "$RP" "$R7" 34-implement "$T/prompt.md" 2>/dev/null </dev/null
check "piano inglese: nota della deviazione «defensive: » dopo l'ultima riga di «### Plan review changelog», impronta invariata, .esito OK" 'grep -A1 "^- round 1: ok$" "$SP7" | tail -1 | grep -qx -- "- nota (deviazione difensiva, 34-implement): defensive: a.py:9 — raw code default" && [ "$(bash "$HERE/plan-check.sh" basis "$SP7" | tr -d "\r")" = "$b7a" ] && sed -n 1p "$R7/log/34-implement.esito" | grep -q "^PHASE RESULT implement: OK"'

# 6c. finalize fail-closed (harness-pt08): missing or exit outside 0/1/4 → STOP, and cycle-state never DONE
mkdir -p "$T/w2"; RSP="$T/w2/spec-r.md"; CS="$(dirname "$RP")/cycle-state.sh"
printf '%s\n' "# X" "## Piano di implementazione" "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" \
  "### Passi" "1. Fare A." "## Review implementazione" "Review status: APPROVED" "Feature status: IMPLEMENTED" \
  "Verification: VERIFIED" "Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1" > "$RSP"
rrev() { FAKE_OUT="$T/$1" FIC_FINALIZE="$2" bash "$RP" "$T/w2/spec-r.run" "$1" "$T/prompt.md" 2>/dev/null </dev/null; }
rrev 60-review "$T/non-esiste.sh"
check "finalize assente → .esito STOP «finalize non eseguito»" 'sed -n 1p "$T/w2/spec-r.run/log/60-review.esito" | grep -q "^PHASE RESULT review: STOP — finalize non eseguito"'
check "  e cycle-state non da' DONE" 'o=$(bash "$CS" "$RSP"); printf "%s\n" "$o" | grep -q "^Next: REVIEW — IMPLEMENTED non firmato"'
printf '#!/usr/bin/env bash\nexit 2\n' > "$T/fin-2"
rrev 61-review "$T/fin-2"
check "finalize exit 2 → .esito STOP «finalize fallito», la riga della review sotto originale=" 'sed -n 1p "$T/w2/spec-r.run/log/61-review.esito" | grep -q "^PHASE RESULT review: STOP — finalize fallito (exit 2" && grep -qx "originale=ESITO FASE x: OK — finto" "$T/w2/spec-r.run/log/61-review.esito"'
check "  e cycle-state non da' DONE" 'o=$(bash "$CS" "$RSP"); printf "%s\n" "$o" | grep -q "^Next: REVIEW — IMPLEMENTED non firmato"'
cat > "$T/fin-ok" <<'EOF'
#!/usr/bin/env bash
for a; do d=$a; done
# spec-r has no Reviewed snapshot: the fingerprint is the one of the empty value, as finalize.sh writes it
printf 'Finalize: IMPLEMENTED — snapshot %s — finto · %s\n' "$(printf '' | sha256sum | cut -c1-12)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${d%.run}.md"
printf '%s\n' "$@" > "$d.fin-args"
EOF
rrev 62-review "$T/fin-ok"
check "controprova: finalize che firma (exit 0) → .esito OK, --level dal piano, cycle-state DONE" '[ "$(sed -n 1p "$T/w2/spec-r.run/log/62-review.esito")" = "ESITO FASE x: OK — finto" ] && grep -qx std "$T/w2/spec-r.run.fin-args" && bash "$CS" "$RSP" | grep -q "^Next: DONE"'
mkdir -p "$T/w"; printf '%s\n' "# X" "## Piano di implementazione" "Plan status: APPROVED" > "$T/w/spec-y.md"
FAKE_OUT="$T/18" bash "$RP" "$T/w/spec-y.run" 18-plan "$T/prompt.md" 2>/dev/null </dev/null
check "con la spec accanto, .esito porta lo stato di cycle-state" 'grep -Eq "^state=[0-9a-f]{12}$" "$T/w/spec-y.run/log/18-plan.esito"'

# lock not computable: never "free" (fail-closed). Working folder outside any git repo, without FIC_LOCK (pk04a-1:
# the lock is computed from the working folder, not from the script's location).
mkdir -p "$T/nogit"; NOGIT_CEIL=$(cd "$T" && { pwd -W 2>/dev/null || pwd; })
check "--lock-status senza repository → sconosciuto, exit 1" 'out=$(cd "$T/nogit" && env -u FIC_LOCK GIT_CEILING_DIRECTORIES="$NOGIT_CEIL" bash "$RP" --lock-status 2>&1); [ $? -eq 1 ] && [ "${out%%:*}" = sconosciuto ]'
check "  e una fase non parte (exit 2, niente sottosessione)" '(cd "$T/nogit" && env -u FIC_LOCK GIT_CEILING_DIRECTORIES="$NOGIT_CEIL" FAKE_OUT="$T/30-plan" bash "$RP" "$T/run" 30-plan "$T/prompt.md" >/dev/null 2>&1 </dev/null); [ $? -eq 2 ] && [ ! -f "$T/30-plan.args" ]'
check "MSYS_NO_PATHCONV=1 non cambia la risposta sul lock vero" '[ "$(env -u FIC_LOCK bash "$RP" --lock-status 2>&1 | cut -d: -f1)" = "$(env -u FIC_LOCK MSYS_NO_PATHCONV=1 bash "$RP" --lock-status 2>&1 | cut -d: -f1)" ]'

# 7. harness fingerprint (pt03; pk04a-2: the plugin files and .claude/maat.json, three-line harness.fp, single
#    decision --harness-fp-confronta). Mutations are made on a COPY of the plugin, with MAAT_ROOT pointing there.
#    Counterproofs here, on a SECOND copy with a mutated run-phase.sh (the measured plugin stays the first): HARNESS_EXCLUDE
#    without assets, without the temporary files. Orchestrator counterproofs: removing the comparison, or always printing
#    UGUALE from hfp_confronta → the "harness changed" cases turn red; UGUALE also for an unreadable file → the
#    "empty" and "0000" cases turn red.
HP="$T/hplug/maat"; mkdir -p "$T/hplug" && cp -r "$HERE/.." "$HP" && find "$HP" -name __pycache__ -type d -prune -exec rm -rf {} +
sed -i 's/"version": *"[^"]*"/"version": "9.9.9-copia"/' "$HP/.claude-plugin/plugin.json"
HP_M=$(cygpath -m "$HP" 2>/dev/null || printf '%s' "$HP")
export MAAT_ROOT="$HP"
hrun() { FAKE_OUT="$T/h$2" bash "${HRP:-$RP}" "$1" "$2" "$T/prompt.md" 2>"$T/h$2.err" </dev/null; }
hfpc() { bash "$RP" --harness-fp-confronta "$1" "$FIC_REPO"; }
rimedio() { # $1 = the label's .stderr: runs the printed remedy as is, from the project
  local r; r=$(grep -o 'bash "[^"]*/run-phase.sh" --harness-fp > "[^"]*"' "$1" | head -1)
  [ -n "$r" ] && (cd "$FIC_REPO" && eval "$r")
}
hrun "$T/h.run" 01-plan; rc=$?
check "primo lancio: harness.fp e' l'uscita di --harness-fp, tre righe" '[ $rc -eq 0 ] && [ "$(cat "$T/h.run/harness.fp")" = "$(bash "$RP" --harness-fp "$FIC_REPO")" ] && [ "$(wc -l < "$T/h.run/harness.fp")" -eq 3 ]'
check "  impronta=<64 esadecimali>, versione= della copia, radice= la copia" 'sed -n 1p "$T/h.run/harness.fp" | grep -Eqx "impronta=[0-9a-f]{64}" && [ "$(sed -n 2p "$T/h.run/harness.fp")" = "versione=9.9.9-copia" ] && [ "$(sed -n 3p "$T/h.run/harness.fp")" = "radice=$HP_M" ]'
hrun "$T/h.run" 02-implement; rc=$?
check "harness invariato fra due fasi → la fase gira" '[ $rc -eq 0 ] && [ -f "$T/h02-implement.args" ]'
# 1.4.0: the RESOLVED language of the messages is part of the fingerprint. A change of MAAT_LINGUA in the middle of a
# cycle stops it like a changed maat.json (the message cites the language in English; the Italian one is that of
# 1.3.0, asserted below); back to the language of the cycle, the phase runs.
MAAT_LINGUA=en hrun "$T/h.run" 02b-probe; rc=$?
check "1.4.0: un cambio di lingua (MAAT_LINGUA it → en) a meta' ciclo ferma il ciclo: exit 6, la sotto-sessione non parte" '[ $rc -eq 6 ] && [ ! -f "$T/h02b-probe.args" ] && grep -q "^STOP: harness changed since [0-9T:-]*Z: .*and the language of the messages" "$T/h02b-probe.err"'
hrun "$T/h.run" 02c-probe; rc=$?
check "  di nuovo con la lingua del ciclo (it): la fase gira" '[ $rc -eq 0 ] && [ -f "$T/h02c-probe.args" ]'
LR="$T/lrepo"; mkdir -p "$LR/.claude" && (cd "$LR" && git init -q .)
printf '{"versione_schema": 1, "moduli": [{"nome": "tutto", "radice": ".", "regola_test": "nessuna"}], "lingua": "it"}\n' > "$LR/.claude/maat.json"
lfp() { (cd "$LR" && env -u MAAT_CONFIG FIC_REPO="$LR" "$@" bash "$RP" --harness-fp "$LR" | sed -n 's/^impronta=//p'); }
f_none=$(lfp env -u MAAT_LINGUA); f_it=$(lfp env MAAT_LINGUA=it); f_en=$(lfp env MAAT_LINGUA=en)
check "1.4.0: impronta senza MAAT_LINGUA = impronta con MAAT_LINGUA uguale alla lingua di maat.json (la lingua risolta)" '[ -n "$f_none" ] && [ "$f_none" = "$f_it" ] && [ "$f_en" != "$f_it" ]'
mkdir -p "$HP/scripts/__pycache__"; echo pyc > "$HP/scripts/__pycache__/m.pyc"
hrun "$T/h.run" 03-review; rc=$?
check "  un file in scripts/__pycache__/ del plugin non cambia l'impronta" '[ $rc -eq 0 ]'
echo cambiato >> "$HP/assets/maat-icona.svg"
hrun "$T/h.run" 03b-probe; rc=$?
check "  un file in assets/ cambiato non cambia l'impronta" '[ $rc -eq 0 ] && [ "$(hfpc "$T/h.run/harness.fp")" = UGUALE ]'
TMPF=(.run-phase.sh.swp driver.py.orig .DS_Store cycle-state.sh~)
for f in "${TMPF[@]}"; do echo tmp > "$HP/scripts/$f"; done
hrun "$T/h.run" 03c-probe; rc=$?
check "  file temporanei d'editor (.swp .orig .DS_Store ~) → UGUALE, la fase gira" '[ $rc -eq 0 ] && [ -f "$T/h03c-probe.args" ] && [ "$(hfpc "$T/h.run/harness.fp")" = UGUALE ]'
check "  e --harness-paths non li elenca" '! bash "$RP" --harness-paths | grep -E "\.swp$|\.orig$|\.DS_Store$|~$"'
# counterproofs on the exclusions: run-phase.sh mutated in a second copy, MAAT_ROOT stays the first
hmut() { # $1 name, $2 sed expression on the HARNESS_EXCLUDE line → prints the path of the mutated script
  local d="$T/hmut-$1/maat"; mkdir -p "$T/hmut-$1" && cp -r "$HERE/.." "$d" && sed -i "$2" "$d/scripts/run-phase.sh"
  printf '%s' "$d/scripts/run-phase.sh"
}
M_AS=$(hmut assets 's/^HARNESS_EXCLUDE=(__pycache__ assets /HARNESS_EXCLUDE=(__pycache__ /')
check "  premessa: mutazione «assets non escluso» applicata" 'grep -q "^HARNESS_EXCLUDE=(__pycache__ .\*\.swp" "$M_AS"'
HRP=$M_AS hrun "$T/hca.run" 01-plan
echo ancora >> "$HP/assets/maat-icona.svg"
HRP=$M_AS hrun "$T/hca.run" 02-probe; rc=$?
check "  controprova: assets tolto da HARNESS_EXCLUDE → la stessa modifica in assets/ da' exit 6" '[ $rc -eq 6 ]'
M_TMP=$(hmut temp 's/^HARNESS_EXCLUDE=(__pycache__ assets .*)$/HARNESS_EXCLUDE=(__pycache__ assets)/')
check "  premessa: mutazione «file temporanei non esclusi» applicata" 'grep -qx "HARNESS_EXCLUDE=(__pycache__ assets)" "$M_TMP"'
for f in "${TMPF[@]}"; do rm -f "$HP/scripts/$f"; done
HRP=$M_TMP hrun "$T/hct.run" 01-plan
for f in "${TMPF[@]}"; do echo tmp > "$HP/scripts/$f"; done
HRP=$M_TMP hrun "$T/hct.run" 02-probe; rc=$?
check "  controprova: i quattro pattern tolti da HARNESS_EXCLUDE → gli stessi file temporanei danno exit 6" '[ $rc -eq 6 ]'
for f in "${TMPF[@]}"; do rm -f "$HP/scripts/$f"; done
printf '#' >> "$HP/scripts/context-pack.sh"
hrun "$T/h.run" 04-fix; rc=$?
check "un byte di uno script del plugin → STOP, exit 6, la sottosessione non parte" '[ $rc -eq 6 ] && [ ! -f "$T/h04-fix.args" ] && [ "$(cat "$T/h.run/log/04-fix.exit")" = 6 ]'
check "  il motivo con la data, su stderr; il rimedio a percorso assoluto nello .stderr della label" 'grep -q "STOP: harness cambiato dal [0-9T:-]*Z: ricomincia la fase o conferma (impronta registrata [0-9a-f]\{12\}, attuale [0-9a-f]\{12\}; file del plugin in $HP_M e .claude/maat.json)" "$T/h04-fix.err" && grep -qF "bash \"$HP_M/scripts/run-phase.sh\" --harness-fp > \"$T/h.run/harness.fp\"" "$T/h.run/log/04-fix.stderr"'
check "  e il lock di codice e' rilasciato" '[ ! -d "$FIC_LOCK" ]'
rimedio "$T/h.run/log/04-fix.stderr"
check "  il rimedio eseguito cosi' com'e' scrive harness.fp di tre righe" '[ "$(wc -l < "$T/h.run/harness.fp")" -eq 3 ] && [ "$(hfpc "$T/h.run/harness.fp")" = UGUALE ]'
hrun "$T/h.run" 05-fix; rc=$?
check "  confermata l'impronta attuale → la fase gira" '[ $rc -eq 0 ] && [ -f "$T/h05-fix.args" ]'
printf 'nuovo\n' > "$HP/scripts/nuovo.sh"
hrun "$T/h.run" 06-review; rc=$?
check "file nuovo in scripts/ del plugin → STOP" '[ $rc -eq 6 ]'
rm -f "$HP/scripts/nuovo.sh"
printf 'nota\n' > "$HP/scripts/note.bak"
hrun "$T/h.run" 06b-probe; rc=$?
check "file estraneo non escluso (scripts/note.bak: niente .gitignore) → STOP" '[ $rc -eq 6 ]'
rm -f "$HP/scripts/note.bak"
# the project's .claude/maat.json: missing at registration and then created, changed, deleted → exit 6 every time
mkdir -p "$FIC_REPO/.claude"
printf '{"versione_schema": 1, "moduli": [{"nome": "app", "radice": "."}]}\n' > "$FIC_REPO/.claude/maat.json"
hrun "$T/h.run" 07-probe; rc=$?
check "maat.json assente alla registrazione e poi creato → exit 6" '[ $rc -eq 6 ]'
rimedio "$T/h.run/log/07-probe.stderr"; hrun "$T/h.run" 07b-probe; rc=$?
check "  confermato → la fase gira" '[ $rc -eq 0 ]'
printf '{"versione_schema": 1, "moduli": [{"nome": "api", "radice": "."}]}\n' > "$FIC_REPO/.claude/maat.json"
hrun "$T/h.run" 07c-probe; rc=$?
check "maat.json cambiato → exit 6" '[ $rc -eq 6 ]'
rimedio "$T/h.run/log/07c-probe.stderr"
rm -rf "$FIC_REPO/.claude"
hrun "$T/h.run" 07d-probe; rc=$?
check "maat.json presente e poi cancellato → exit 6" '[ $rc -eq 6 ]'
rimedio "$T/h.run/log/07d-probe.stderr"
# unreadable harness.fp: empty (the remedy outside a repository exits 1 and empties the file) or "0000"
bash "$RP" --harness-fp "$T/nogit" > "$T/h.run/harness.fp"; rc=$?
check "il rimedio fuori da un repository esce 1 e lascia harness.fp vuoto" '[ $rc -eq 1 ] && [ ! -s "$T/h.run/harness.fp" ]'
check "  --harness-fp-confronta sul file vuoto → ILLEGGIBILE <12 esadecimali>, exit 0" 'o=$(hfpc "$T/h.run/harness.fp"); [ $? -eq 0 ] && printf "%s" "$o" | grep -Eqx "ILLEGGIBILE [0-9a-f]{12}"'
hrun "$T/h.run" 08-probe; rc=$?
check "  harness.fp vuoto → «harness.fp illeggibile», exit 6" '[ $rc -eq 6 ] && grep -q "STOP: harness.fp illeggibile (vuoto o senza impronta" "$T/h08-probe.err"'
echo 0000 > "$T/h.run/harness.fp"
check "  --harness-fp-confronta su 0000 → ILLEGGIBILE <12 esadecimali>, exit 0" 'o=$(hfpc "$T/h.run/harness.fp"); [ $? -eq 0 ] && printf "%s" "$o" | grep -Eqx "ILLEGGIBILE [0-9a-f]{12}"'
hrun "$T/h.run" 08b-probe; rc=$?
check "  harness.fp con 0000 → «harness.fp illeggibile», exit 6" '[ $rc -eq 6 ] && grep -q "STOP: harness.fp illeggibile" "$T/h08b-probe.err"'
bash "$RP" --harness-fp "$FIC_REPO" > "$T/h.run/harness.fp"
# the plugin copy moved, identical content: the different root does not count
mv "$HP" "$T/hplug/maat-spostato"; export MAAT_ROOT="$T/hplug/maat-spostato"
hrun "$T/h.run" 09-probe; rc=$?
check "plugin spostato in un'altra cartella, contenuto identico → UGUALE, la fase gira" '[ $rc -eq 0 ] && [ -f "$T/h09-probe.args" ] && grep -qx "radice=$HP_M" "$T/h.run/harness.fp"'
mv "$T/hplug/maat-spostato" "$HP"; export MAAT_ROOT="$HP"
# previous format: one line of 64 hex digits (cycle started with the internal harness)
echo x | sha256sum | cut -c1-64 > "$T/h.run/harness.fp"
check "  --harness-fp-confronta sul formato precedente → FORMATO-PRECEDENTE" 'hfpc "$T/h.run/harness.fp" | grep -Eqx "FORMATO-PRECEDENTE [0-9a-f]{12} [0-9a-f]{12}"'
hrun "$T/h.run" 10-probe; rc=$?
check "harness.fp di formato precedente → «formato precedente», exit 6" '[ $rc -eq 6 ] && grep -q "STOP: impronta di formato precedente: ciclo iniziato col harness interno" "$T/h10-probe.err"'
# run dir of a cycle started before the rule: phases already run, no harness.fp → no check
mkdir -p "$T/vecchio.run/log"; echo 0 > "$T/vecchio.run/log/01-plan.exit"
printf '#' >> "$HP/scripts/context-pack.sh"; rm -f "$T/h02-implement.args"
hrun "$T/vecchio.run" 02-implement; rc=$?
check "run dir senza harness.fp e con fasi girate → nessun controllo, nessun harness.fp scritto" '[ $rc -eq 0 ] && [ -f "$T/h02-implement.args" ] && [ ! -f "$T/vecchio.run/harness.fp" ]'
# a first launch rejected by the lock (exit 4) does not make the run dir an "old" cycle
mkdir -p "$T/nuovo.run/log"; echo 4 > "$T/nuovo.run/log/01-plan.exit"
hrun "$T/nuovo.run" 02-plan; rc=$?
check "  una .exit 4 non e' una fase girata: harness.fp scritto" '[ $rc -eq 0 ] && [ -s "$T/nuovo.run/harness.fp" ]'
check "--harness-paths: scripts/run-phase.sh e .claude/maat.json, nulla sotto assets/ o __pycache__/" 'hp=$(bash "$RP" --harness-paths) && grep -qx "scripts/run-phase.sh" <<< "$hp" && grep -qx ".claude/maat.json" <<< "$hp" && ! grep -Eq "(^|/)(assets|__pycache__)/" <<< "$hp"'
check "--harness-fp fuori da un repository → exit 1" 'bash "$RP" --harness-fp "$T/nogit" >/dev/null 2>&1; [ $? -eq 1 ]'
unset MAAT_ROOT

# 8. review ∥ VERIFY (harness-pt09): tree key, review and VERIFY together, final recomputation, discard and sequence.
#    Counterproof: removing the final recomputation of the key → the «key changed» case accepts the results.
W3="$T/w3"; SPP="$W3/spec-p.md"; R3="$W3/spec-p.run"; mkdir -p "$R3"; echo a.py > "$R3/touched.txt"
pspec() { printf '%s\n' "# P" "## Piano di implementazione" "Plan status: APPROVED" "Test level: std" "$@" > "$SPP"; }
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$FAKE_OUT.fin-args"\n' > "$T/fin-rec"; chmod +x "$T/fin-rec"
cat > "$T/cp" <<'EOF'
#!/usr/bin/env bash
echo "$1" > "$FAKE_OUT.cp-args"
[ "${FAKE_CP_WRITE:-1}" = 1 ] && printf '{"id":"T1","esito":"rosso_asserzione"}\n' > "$(dirname "$1")/T1.json"
exit "${FAKE_CP_EXIT:-0}"
EOF
chmod +x "$T/cp"
prun() { # $1 = run-phase.sh: a mutant is another plugin (copy $HC), so its fingerprint is confirmed before the
  # launch and the real plugin's one is reconfirmed afterwards, as a person would do (pk04a-2); without it, it would exit with 6
  local rc
  [ "$1" = "$RP" ] || bash "$1" --harness-fp "$FIC_REPO" > "$R3/harness.fp"
  FAKE_OUT="$T/$2" FIC_FINALIZE="$T/fin-rec" FIC_CP_CMD="${PRUN_CP_CMD-$T/cp}" FAKE_RESULT_N=1 FAKE_SPEC="${FS:-$SPP}" bash "$1" "$R3" "$2" "$T/prompt.md" 2>/dev/null </dev/null; rc=$?
  [ "$1" = "$RP" ] || bash "$RP" --harness-fp "$FIC_REPO" > "$R3/harness.fp"
  return $rc
}
L3="$R3/log"
pspec; FAKE_GATES_SLEEP=3 prun "$RP" 70-review; rc=$?
check "parallelo: la review parte mentre VERIFY gira (gate non finiti al suo avvio), una sola review" '[ $rc -eq 0 ] && [ "$(cat "$T/70-review.gates-at-start.1")" = no ] && [ -f "$T/70-review.gates-done" ] && [ "$(cat "$T/70-review.calls")" = 1 ]'
check "  .parallelo: modo=parallelo, controprove del worker (mutations.json non c'e')" 'grep -q "^modo=parallelo controprove=worker chiave=[0-9a-f]\{12\}$" "$L3/70-review.parallelo"'
check "  prompt con VERIFY IN PARALLELO, senza EVIDENZE (nessun risultato da citare)" 'grep -q "^VERIFY IN PARALLELO (driver, run-phase.sh): " "$T/70-review.stdin.1" && ! grep -q EVIDENZE "$T/70-review.stdin.1" && grep -q "controprove restano tue" "$T/70-review.stdin.1"'
check "  finalize dopo result.json, con --copertura (unione requisito→ID)" 'grep -qx -- --copertura "$T/70-review.fin-args" && grep -q "70-review.result.json$" "$T/70-review.fin-args" && grep -q "\"copertura\"" "$L3/70-review.result.json"'
check "  chiave invariata: la scrittura della review resta, esito della review" 'grep -qx "chiamata 1" "$SPP" && [ "$(sed -n 1p "$L3/70-review.esito")" = "ESITO FASE x: OK — finto 1" ]'

pspec; FAKE_SLEEP=1 FAKE_TOUCH="$FIC_REPO/a.py" prun "$RP" 71-review; rc=$?
check "chiave cambiata durante la fase: risultati scartati e rilancio in sequenza" '[ $rc -eq 0 ] && grep -q "^scartato: chiave cambiata durante la fase" "$L3/71-review.parallelo" && grep -q "^modo=sequenza — chiave cambiata" "$L3/71-review.parallelo" && [ "$(cat "$T/71-review.calls")" = 2 ] && [ "$(wc -l < "$T/71-review.gates-calls")" = 2 ]'
check "  il rilancio e' la sequenza di prima (EVIDENZE nel prompt, niente VERIFY IN PARALLELO)" 'grep -q "^EVIDENZE DEI GATE" "$T/71-review.stdin.2" && ! grep -q "VERIFY IN PARALLELO" "$T/71-review.stdin.2"'
check "  la spec scritta dalla review scartata e' rimessa com'era" '! grep -qx "chiamata 1" "$SPP" && grep -qx "chiamata 2" "$SPP"'
check "  l'esito e' quello del rilancio (dopo l'evento fic_scartato), i gate scartati a parte" 'grep -q "\"fic_scartato\"" "$L3/71-review.jsonl" && [ "$(sed -n 1p "$L3/71-review.esito")" = "ESITO FASE x: OK — finto 2" ] && [ -f "$L3/71-review.gates.scartato" ]'
(cd "$FIC_REPO" && git checkout -q -- a.py)

LINE='  k1=$(verify_key) || k1=""   # ricalcolo finale della chiave (harness-pt09)'
check "controprova: riga del ricalcolo finale unica" '[ "$(grep -cxF -- "$LINE" "$RP")" = 1 ]'
HC="$T/hc"; mkdir -p "$HC"   # copy of the plugin: scripts/, schemas/, .claude-plugin/
cp -r "$HERE" "$HC/scripts"; cp -r "$HERE/../schemas" "$HERE/../.claude-plugin" "$HC/"
MRP="$HC/scripts/run-phase.sh"
sed 's/^  k1=\$(verify_key) || k1=""   # ricalcolo finale della chiave/  k1=$k0   # MUTANTE: niente ricalcolo/' "$RP" > "$MRP"
if cmp -s "$RP" "$MRP"; then fail=$((fail + 1)); n=$((n + 1)); echo "FAIL: controprova: la mutazione non si applica"
else
  pspec; FAKE_SLEEP=1 FAKE_TOUCH="$FIC_REPO/a.py" prun "$MRP" 72-review
  check "controprova: senza il ricalcolo finale la chiave cambiata passa (una review, niente scarto: il caso sopra sarebbe rosso)" '[ "$(cat "$T/72-review.calls")" = 1 ] && ! grep -q scartato "$L3/72-review.parallelo" && grep -qx "chiamata 1" "$SPP"'
  (cd "$FIC_REPO" && git checkout -q -- a.py)
fi

pspec; FIC_REVIEW_PARALLEL=0 FAKE_GATES_SLEEP=2 prun "$RP" 73-review
check "FIC_REVIEW_PARALLEL=0: la sequenza di prima (gate finiti prima della review, EVIDENZE nel prompt)" '[ "$(cat "$T/73-review.gates-at-start.1")" = si ] && grep -qx "modo=sequenza — FIC_REVIEW_PARALLEL=0" "$L3/73-review.parallelo" && grep -q "^EVIDENZE DEI GATE" "$T/73-review.stdin.1"'
pspec "## Review implementazione" "Review status: APPROVED" "Feature status: NEEDS_VERIFICATION"
FAKE_GATES_SLEEP=2 prun "$RP" 74-review
check "review registrata APPROVED (promozione, gate-only): sequenza, nessun cambiamento" '[ "$(cat "$T/74-review.gates-at-start.1")" = si ] && grep -q "^modo=sequenza — review registrata APPROVED" "$L3/74-review.parallelo"'

# 8b. who runs the counterproofs: the driver ONLY on a `plan-check.sh gen` list consistent with the plan
# Repository root of plan-check.sh EXPLICIT and synthetic (the fake repo, with modules/api): without it, plan-check
# would fall back to the current folder, i.e. the project the suite is launched from (pk04a-1). Stays until the end.
export PLAN_CHECK_ROOT="$FIC_REPO"; mkdir -p "$FIC_REPO/modules/api/app" "$FIC_REPO/modules/api/tests"
# and its maat.json (pk04b-2): plan-check routes files and tests only with the declared modules, no more modules/api
# hard-coded; outside the fake repo, so the harness fingerprint does not change. Stays until the end.
printf '{"versione_schema": 1, "moduli": [{"nome": "be", "radice": "modules/api", "ambiente": "nativo", "report": "junit"}]}\n' > "$T/cfg-nativo.json"
export MAAT_CONFIG="$T/cfg-nativo.json"
PCK="$HERE/plan-check.sh"
pspec2() { # format-2 plan with one mutation (T1); $1 = extra line in the plan (changes the fingerprint)
  printf '%s\n' "# P" "## Requisiti funzionali" "1. RF1 — A." "## Piano di implementazione" "Plan format: 2" \
    "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" ${1:+"$1"} "### File toccati" '- `a.py`' "### Passi" \
    "#### Blocco B1 — tutto" 'scrive: `a.py`' "dopo: nessuno" "" "| id | file | modifica | test |" "|---|---|---|---|" \
    '| P1 | `a.py` | uno | T1 |' "### Tracciabilità requisiti" "| Req | Passi del piano | Verifica |" "|---|---|---|" \
    "| RF1 | P1 | T1 |" "### Piano di test" "| ID | requisito | file | asserzione | mutazione |" "|---|---|---|---|---|" \
    '| T1 | RF1 | `modules/api/tests/test_a.py::test_a` (nuovo) | rosso se: A | `modules/api/app/a.py` · `f` · `return 1` → `return 2` · rosso se: `assert 2 == 1` |' > "$SPP"
}
FS="$T/scarto.txt"   # from here on the fake subsession does not write into the spec (it would change the plan fingerprint)
mkdir -p "$R3/counterproof"; printf '[{"id":"T1"}]\n' > "$R3/counterproof/mutations.json"   # written by the worker in round 1
pspec; FS=$FS prun "$RP" 75-review
check "secondo giro con un mutations.json del worker: controprove del worker (il driver non le lancia)" 'grep -q "^modo=parallelo controprove=worker" "$L3/75-review.parallelo" && [ ! -f "$T/75-review.cp-args" ] && grep -q "le controprove restano tue" "$T/75-review.stdin.1"'
pspec2; bash "$PCK" gen "$SPP" >/dev/null 2>&1
check "  (fixture: gen ha scritto procedura.txt e mutations.json)" '[ -f "$R3/gen/procedura.txt" ] && grep -q "\"id\": \"T1\"" "$R3/counterproof/mutations.json"'
printf '{"id":"T1","esito":"verde"}\n' > "$R3/counterproof/T1.json"   # result of a previous round
FS=$FS FAKE_CP_WRITE=0 prun "$RP" 76-review
check "lista di gen con impronta coerente: controprove del driver in VERIFY" 'grep -q "^modo=parallelo controprove=driver" "$L3/76-review.parallelo" && grep -q "counterproof/mutations.json$" "$T/76-review.cp-args" && grep -qx "exit=0" "$L3/76-review.counterproof"'
check "  il prompt dice al worker di non riscrivere mutations.json ne' lanciare counterproof.sh" 'grep -q "le esegue il DRIVER ora" "$T/76-review.stdin.1"'
check "  un risultato di un giro precedente non sopravvive al run del driver" '[ ! -f "$R3/counterproof/T1.json" ]'
FS=$FS FAKE_CP_EXIT=3 prun "$RP" 77-review
check "  counterproof.sh exit 3 (ambiente): i suoi risultati non valgono, cancellati" 'grep -qx "exit=3" "$L3/77-review.counterproof" && [ ! -f "$R3/counterproof/T1.json" ]'
FS=$FS FAKE_CP_EXIT=5 prun "$RP" 78-review
check "  counterproof.sh exit 5 (mirror non ripristinato): .esito STOP" 'sed -n 1p "$L3/78-review.esito" | grep -q "^PHASE RESULT review: STOP — counterproof.sh exit 5"'
# run_cp without FIC_CP_CMD (pk04b-2, step 4-bis): counterproof.sh inside WSL only on Windows and with a mutations
# module `ambiente: wsl` (maat.json); otherwise direct, with PROJECT_ROOT, without wsl (fake here: records and exits
# 127, as if it were missing). Counterproof: hard-coded wsl in run_cp -> the native case calls wsl, red.
WB="$T/wslbin"; mkdir -p "$WB"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$FAKE_WSL_LOG"\nexit 127\n' > "$WB/wsl"; chmod +x "$WB/wsl"
cat > "$T/cp-diretto" <<'EOF'
#!/usr/bin/env bash
printf 'args=%s\nPROJECT_ROOT=%s\n' "$*" "${PROJECT_ROOT:-}" > "$FAKE_OUT.cpd"
printf '{"id":"T1","esito":"rosso_asserzione"}\n' > "$(dirname "$1")/T1.json"
exit 0
EOF
chmod +x "$T/cp-diretto"
printf '{"versione_schema": 1, "moduli": [{"nome": "be", "radice": "modules/api", "ambiente": "nativo", "report": "junit"}]}\n' > "$T/cfg-nativo.json"
printf '{"versione_schema": 1, "moduli": [{"nome": "be", "radice": "modules/api", "ambiente": "wsl"}]}\n' > "$T/cfg-wsl.json"
cprun() { # <run-phase.sh> <label> <maat.json>: driver counterproofs without FIC_CP_CMD, fake wsl in PATH
  rm -f "$T/wsl.log"
  FAKE_WSL_LOG="$T/wsl.log" PATH="$WB:$PATH" MAAT_CONFIG="$3" FIC_COUNTERPROOF="$T/cp-diretto" PRUN_CP_CMD= FS=$FS prun "$1" "$2"
}
cprun "$RP" 7a-review "$T/cfg-nativo.json"
check "run_cp senza FIC_CP_CMD, modulo nativo: counterproof.sh diretto con PROJECT_ROOT, mai wsl" 'grep -q "^modo=parallelo controprove=driver" "$L3/7a-review.parallelo" && grep -q "^args=.*counterproof/mutations.json$" "$T/7a-review.cpd" && grep -qxF "PROJECT_ROOT=$FIC_REPO" "$T/7a-review.cpd" && grep -qx "exit=0" "$L3/7a-review.counterproof" && [ ! -f "$T/wsl.log" ]'
cprun "$RP" 7b-review "$T/cfg-wsl.json"
case "${OSTYPE:-}:$(uname -s 2>/dev/null)" in
  *msys*|*cygwin*|*:MINGW*|*:MSYS*|*:CYGWIN*)
    check "  modulo wsl su Windows: dentro WSL, PROJECT_ROOT e MAAT_CONFIG tradotti, MAAT_LINGUA passata" 'grep -q "^-- bash -lc PROJECT_ROOT=./mnt/.* MAAT_CONFIG=./mnt/.*cfg-wsl\.json. MAAT_LINGUA=.it. bash ./mnt/.*cp-diretto. ./mnt/.*counterproof/mutations\.json.$" "$T/wsl.log" && [ ! -f "$T/7b-review.cpd" ] && grep -qx "exit=127" "$L3/7b-review.counterproof"' ;;
  *) check "  modulo wsl fuori da Windows: diretto, mai wsl" '[ ! -f "$T/wsl.log" ] && [ -f "$T/7b-review.cpd" ]' ;;
esac
sed 's/^  elif cp_in_wsl; then$/  elif true; then   # MUTANTE: wsl fisso/' "$RP" > "$MRP"
if cmp -s "$RP" "$MRP"; then fail=$((fail + 1)); n=$((n + 1)); echo "FAIL: controprova (run_cp): la mutazione non si applica"
else
  cprun "$MRP" 7c-review "$T/cfg-nativo.json"
  check "controprova (run_cp): con wsl fisso il modulo nativo passa da wsl (il caso 7a sarebbe rosso)" '[ -f "$T/wsl.log" ] && [ ! -f "$T/7c-review.cpd" ]'
fi
pspec2 "Nota: piano cambiato dopo gen."
FS=$FS prun "$RP" 79-review
check "impronta del piano cambiata dopo gen: niente controprove del driver (stessa lista, impronta diversa)" 'grep -q "^modo=parallelo controprove=worker" "$L3/79-review.parallelo" && [ ! -f "$T/79-review.cp-args" ]'
cp "$R3/counterproof/mutations.json" "$T/mut-gen.json"; printf '[{"id":"T9"}]\n' > "$R3/counterproof/mutations.json"; pspec2
FS=$FS prun "$RP" 80-review
check "lista riscritta dal worker dopo gen (impronta coerente): controprove del worker" 'grep -q "^modo=parallelo controprove=worker" "$L3/80-review.parallelo" && [ ! -f "$T/80-review.cp-args" ]'
cp "$T/mut-gen.json" "$R3/counterproof/mutations.json"
# counterproofs by mutation of the rule: (a) no gen check => the worker's list goes to the driver;
# (b) without the fingerprint comparison => the changed plan goes to the driver
for mv_ in a b; do
  case $mv_ in
    a) sed 's/^    ! ls "\$dir"\/counterproof\/\*\.meta >\/dev\/null 2>&1 \&\& cp_from_gen \&\& cp_driver=1$/    cp_driver=1   # MUTANTE/' "$RP" > "$MRP" ;;
    b) sed 's/ \[ -n "\$fn" \] \&\& \[ "\$fr" = "\$fn" \] \&\& cmp/ [ -n "$fn" ] \&\& cmp/' "$RP" > "$MRP" ;;
  esac
  if cmp -s "$RP" "$MRP"; then fail=$((fail + 1)); n=$((n + 1)); echo "FAIL: controprova ($mv_): la mutazione non si applica"; continue; fi
  if [ $mv_ = a ]; then printf '[{"id":"T1"}]\n' > "$R3/counterproof/mutations.json"; rm -rf "$R3/gen"; pspec; else pspec2; bash "$PCK" gen "$SPP" >/dev/null 2>&1; pspec2 "Nota: piano cambiato dopo gen."; fi
  FS=$FS prun "$MRP" "8$mv_-review"
  check "controprova ($mv_): sul mutante il caso diventa «controprove del driver» (il test sopra sarebbe rosso)" 'grep -q "^modo=parallelo controprove=driver" "$L3/8$mv_-review.parallelo"'
done
rm -rf "$R3/counterproof" "$R3/gen"

# 8c. discard: the evidence of the parallel window does not stay reusable; in worker mode the round's <id>.json files disappear
mkdir -p "$R3/counterproof"; printf '[{"id":"CP-1"}]\n' > "$R3/counterproof/mutations.json"
printf '{"id":"CP-1","esito":"rosso_asserzione"}\n' > "$R3/counterproof/CP-1.json"
pspec; FS=$FS FAKE_GATES_EV=1 FAKE_WAIT_GATES=1 FAKE_TOUCH="$FIC_REPO/a.py" prun "$RP" 90-review
k0=$(sed -n 's|^gates: esito=.* evidence=.*/evidence/\([0-9a-f]*\)$|\1|p' "$L3/90-review.gates.scartato" 2>/dev/null | tail -1)
check "scarto: evidence/<k0> della finestra parallela diventa <k0>.scartato" '[ -n "$k0" ] && grep -q "^scartato:" "$L3/90-review.parallelo" && [ ! -d "$R3/evidence/$k0" ] && [ -d "$R3/evidence/$k0.scartato" ]'
check "  in modo worker i <id>.json del giro scartato sono cancellati" 'grep -q "controprove=worker" "$L3/90-review.parallelo" && [ ! -f "$R3/counterproof/CP-1.json" ]'
(cd "$FIC_REPO" && git checkout -q -- a.py)   # tree brought back to k0
pspec; FS=$FS FAKE_GATES_EV=1 FIC_REVIEW_PARALLEL=0 prun "$RP" 91-review
check "  tree riportato a k0: i gate si rieseguono (nessun riuso dell'evidenza scartata)" 'grep -q "evidence/$k0$" "$L3/91-review.gates" && grep -qx eseguito "$T/91-review.gates-esito"'
sed 's/^    if \[ -n "\$evd" \] \&\& \[ "\$evd" != - \] \&\& \[ -d "\$evd" \]; then rm -rf "\$evd.scartato"; mv -f "\$evd" "\$evd.scartato"; fi$/    : # MUTANTE/' "$RP" > "$MRP"
if cmp -s "$RP" "$MRP"; then fail=$((fail + 1)); n=$((n + 1)); echo "FAIL: controprova (evidenza): la mutazione non si applica"
else
  rm -rf "$R3/evidence"
  pspec; FS=$FS FAKE_GATES_EV=1 FAKE_WAIT_GATES=1 FAKE_TOUCH="$FIC_REPO/a.py" prun "$MRP" 92-review
  (cd "$FIC_REPO" && git checkout -q -- a.py)
  pspec; FS=$FS FAKE_GATES_EV=1 FIC_REVIEW_PARALLEL=0 prun "$RP" 93-review
  check "controprova (evidenza): senza la rinomina, il tree riportato a k0 riusa l'evidenza scartata (il test sopra sarebbe rosso)" 'grep -qx riuso "$T/93-review.gates-esito"'
fi
rm -rf "$R3/counterproof"

# 8d. run-phase killed while VERIFY is still running (the subsession has already exited): vpid= keeps the lock
pspec; FAKE_GATES_SLEEP=8 FAKE_OUT="$T/94-review" FIC_FINALIZE="$T/fin-rec" FAKE_RESULT_N=1 FAKE_SPEC="$FS" bash "$RP" "$R3" 94-review "$T/prompt.md" 2>/dev/null </dev/null & rp=$!
for _ in $(seq 1 40); do grep -q '^vpid=' "$FIC_LOCK/owner" 2>/dev/null && [ -f "$T/94-review.calls" ] && break; sleep 0.25; done
sleep 1
kill -TERM $rp; wait $rp 2>/dev/null
check "run-phase ucciso con VERIFY vivo: vpid nell'owner e il lock resta occupato" '[ -d "$FIC_LOCK" ] && grep -q "^vpid=" "$FIC_LOCK/owner" && { bash "$RP" --lock-status >/dev/null; [ $? -eq 1 ]; }'
for _ in $(seq 1 60); do [ -f "$T/94-review.gates-done" ] && break; sleep 0.25; done; sleep 1
check "  finito VERIFY, il lock e' orfano e si riprende" 'bash "$RP" --lock-status | grep -q "^libero"'
rm -rf "$FIC_LOCK"

# 9. chains (harness-pt12): start of a ring k>1 and closing of the mother
CD="$FIC_REPO/wf"; mkdir -p "$CD"; printf 'spec-*\n' > "$CD/.gitignore"
printf '%s\n' "# M" "Figlie: spec-m-1-a, spec-m-2-b" "## Requisiti funzionali" "1. RF1 — a" > "$CD/spec-m.md"
printf '%s\n' "# A" "## Piano di implementazione" "Plan status: APPROVED" "Test level: std" "### Passi" "1. \`a.py\`" > "$CD/spec-m-1-a.md"
printf '%s\n' "# B" "## Piano di implementazione" "Plan status: APPROVED" "Test level: std" "### Passi" "1. \`b.py\`" "### Piano di test" "- caso" > "$CD/spec-m-2-b.md"
crun() { FAKE_OUT="$T/c$2" bash "$RP" "$CD/$1.run" "$2" "$T/prompt.md" 2>"$T/c$2.err" </dev/null; }
crun spec-m-2-b 70-implement; rc=$?
check "anello 2 con l'anello 1 aperto: implement non lanciato (exit 7, WAIT)" '[ $rc -eq 7 ] && [ ! -f "$T/c70-implement.args" ] && grep -q "WAIT — catena" "$CD/spec-m-2-b.run/log/70-implement.stderr"'
# 1.4.0, block B (f): the same in English: the prefix «WAIT — catena» written by cycle-state.sh in English is still
# recognised by run-phase.sh (the harness.fp of the ring is recorded in English for this case, then put back)
cp "$CD/spec-m-2-b.run/harness.fp" "$T/hfp-it"; MAAT_LINGUA=en bash "$RP" --harness-fp "$FIC_REPO" > "$CD/spec-m-2-b.run/harness.fp"
MAAT_LINGUA=en crun spec-m-2-b 70b-implement; rc=$?
check "  1.4.0 (f): in inglese, WAIT — catena riconosciuto: exit 7, niente sotto-sessione, messaggio inglese" '[ $rc -eq 7 ] && [ ! -f "$T/c70b-implement.args" ] && grep -q "^WAIT — catena: the implement of ring 2 waits for ring 1 (spec-m-1-a) IMPLEMENTED; the plan can run — phase not launched$" "$CD/spec-m-2-b.run/log/70b-implement.stderr"'
cp "$T/hfp-it" "$CD/spec-m-2-b.run/harness.fp"
mkdir -p "$CD/spec-m-1-a.run/log"; printf 'a.py\n' > "$CD/spec-m-1-a.run/touched.txt"
printf 'anello1\n' >> "$FIC_REPO/a.py"                  # ring 1's hunk on a.py, which ring 2 will also touch
(cd "$FIC_REPO" && bash "$HERE/review-surface.sh" tree) > "$CD/spec-m-1-a.run/log/02-implement.post-tree"
printf '%s\n' "## Review implementazione" "Review status: APPROVED" "Feature status: IMPLEMENTED" \
  "Finalize: IMPLEMENTED — snapshot $(printf '' | sha256sum | cut -c1-12) — firmato · $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CD/spec-m-1-a.md"
printf 'umano\n' > "$FIC_REPO/z.py"
crun spec-m-2-b 71-implement; rc=$?
check "anello 2 col tree diverso dal .post-tree dell'anello 1: exit 7 (STOP), niente sotto-sessione" '[ $rc -eq 7 ] && [ ! -f "$T/c71-implement.args" ] && grep -q "STOP — catena: il working tree" "$CD/spec-m-2-b.run/log/71-implement.stderr"'
cp "$CD/spec-m-2-b.run/harness.fp" "$T/hfp-it"; MAAT_LINGUA=en bash "$RP" --harness-fp "$FIC_REPO" > "$CD/spec-m-2-b.run/harness.fp"
MAAT_LINGUA=en crun spec-m-2-b 71b-implement; rc=$?
check "  1.4.0 (f): STOP — catena in inglese ancora riconosciuto da run-phase.sh: exit 7, niente sotto-sessione" '[ $rc -eq 7 ] && [ ! -f "$T/c71b-implement.args" ] && grep -q "^STOP — catena: the working tree .* — phase not launched$" "$CD/spec-m-2-b.run/log/71b-implement.stderr"'
cp "$T/hfp-it" "$CD/spec-m-2-b.run/harness.fp"
rm -f "$FIC_REPO/z.py"
FAKE_TOUCH="$FIC_REPO/a.py" crun spec-m-2-b 72-implement; rc=$?
check "  controprova: tree uguale al .post-tree dell'anello 1 → l'implement parte" '[ $rc -eq 0 ] && [ -f "$T/c72-implement.args" ]'
# M1: ring 2's review receives ITS diff, built by the driver from the ring's base (never HEAD)
printf '#!/usr/bin/env bash\nexit 4\n' > "$T/fin-4"; chmod +x "$T/fin-4"
FIC_FINALIZE="$T/fin-4" crun spec-m-2-b 78-review; rc=$?
RDIFF="$CD/spec-m-2-b.run/log/78-review.anello.diff"
check "M1: review dell'anello 2 → diff dell'anello scritto dal driver, in coda al prompt" '[ $rc -eq 0 ] && [ -s "$RDIFF" ] && grep -q "^DIFF DELL.ANELLO (driver, run-phase.sh): $RDIFF — base anello $(cat "$CD/spec-m-1-a.run/log/02-implement.post-tree")" "$T/c78-review.stdin"'
check "  a.py toccato da 1 e da 2: il diff ha l'hunk dell'anello 2 e non quello dell'anello 1" 'grep -q "^+toccato" "$RDIFF" && ! grep -Eq "^[-+]anello1" "$RDIFF"'
check "  controprova del test: dal commit (HEAD) lo stesso file mostra anche l'hunk dell'anello 1" '(cd "$FIC_REPO" && git diff HEAD -- a.py) | grep -q "^+anello1"'
mv "$CD/spec-m-1-a.run/log/02-implement.post-tree" "$T/pt.bak"
FIC_FINALIZE="$T/fin-4" crun spec-m-2-b 79-review; rc=$?
check "  senza la base dell'anello: exit 7, la review non parte, nessun .running" '[ $rc -eq 7 ] && [ ! -f "$T/c79-review.args" ] && [ ! -f "$CD/spec-m-2-b.run/log/79-review.running" ]'
mv "$T/pt.bak" "$CD/spec-m-1-a.run/log/02-implement.post-tree"
printf 'b.py\n' > "$CD/spec-m-2-b.run/touched.txt"
(cd "$FIC_REPO" && git rev-parse HEAD) > "$CD/spec-m-1-a.run/base.txt"
crun spec-m 73-chiusura; rc=$?
check "chiusura senza e2e: fase di codice senza sotto-sessione, esce 0" '[ $rc -eq 0 ] && [ ! -f "$T/c73-chiusura.args" ] && [ ! -d "$FIC_LOCK" ]'
check "  touched.txt = unione degli anelli, base.txt = quella del primo anello" '[ "$(tr "\n" " " < "$CD/spec-m.run/touched.txt")" = "a.py b.py " ] && [ "$(cat "$CD/spec-m.run/base.txt")" = "$(cat "$CD/spec-m-1-a.run/base.txt")" ]'
check "  gate a livello full sui file della catena" '[ "$(sed -n 3p "$T/c73-chiusura.gates-args")" = full ] && grep -qx a.py "$T/c73-chiusura.gates-args" && grep -qx b.py "$T/c73-chiusura.gates-args"'
check "  chiusura.txt IMPLEMENTED con base e tree, .esito OK" 'grep -Eq "^Chiusura: IMPLEMENTED — base [0-9a-f]{40} · tree [0-9a-f]{40} · gates PASS .* · e2e non richiesto · " "$CD/spec-m.run/chiusura.txt" && grep -q "^PHASE RESULT chiusura: OK" "$CD/spec-m.run/log/73-chiusura.esito"'
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$FAKE_OUT.gates-args"\necho "gates: esito=FAIL chiave=k1 evidence=C:/finto/evidence/k1"\nexit 1\n' > "$T/gates-fail"; chmod +x "$T/gates-fail"
FIC_GATES="$T/gates-fail" crun spec-m 74-chiusura
check "chiusura coi gate rossi → NEEDS_VERIFICATION, .esito STOP" 'grep -q "^Chiusura: NEEDS_VERIFICATION — gates FAIL" "$CD/spec-m.run/chiusura.txt" && grep -q "^PHASE RESULT chiusura: STOP" "$CD/spec-m.run/log/74-chiusura.esito"'
printf '%s\n' "- [e2e-locator: e2e-6-goals.spec.ts] il titolo" >> "$CD/spec-m-2-b.md"
FAKE_RESULT='{"type":"result","result":"e2e verdi\nESITO FASE chiusura: OK — e2e PASS"}' crun spec-m 75-chiusura
check "figlie con [e2e-locator: → sotto-sessione col prompt E2E DELLA CATENA, senza --json-schema" '[ -f "$T/c75-chiusura.args" ] && grep -qx "E2E DELLA CATENA: e2e-6-goals.spec.ts" "$T/c75-chiusura.stdin" && ! grep -qx -- "--json-schema" "$T/c75-chiusura.args"'
check "  FIC_PHASE=chiusura (il lock e' della fase: /dev-verify lo vede dentro il ciclo)" 'grep -qx "FIC_PHASE=chiusura" "$T/c75-chiusura.env"'
check "  e2e OK → chiusura IMPLEMENTED" 'grep -q "^Chiusura: IMPLEMENTED — .* · e2e OK (e2e-6-goals.spec.ts) · " "$CD/spec-m.run/chiusura.txt"'
FAKE_RESULT='{"type":"result","result":"e2e green\nPHASE RESULT chiusura: OK — e2e PASS"}' crun spec-m 75b-chiusura
check "  riga inglese «PHASE RESULT chiusura: OK» (1.3.0) → chiusura IMPLEMENTED, .esito PHASE RESULT" 'grep -q "^Chiusura: IMPLEMENTED — .* · e2e OK (e2e-6-goals.spec.ts) · " "$CD/spec-m.run/chiusura.txt" && grep -q "^PHASE RESULT chiusura: OK — catena chiusa" "$CD/spec-m.run/log/75b-chiusura.esito"'
FAKE_RESULT='{"type":"result","result":"ESITO FASE chiusura: STOP — e2e rosso"}' crun spec-m 76-chiusura
check "  e2e non riusciti → NEEDS_VERIFICATION" 'grep -q "^Chiusura: NEEDS_VERIFICATION — e2e non riusciti" "$CD/spec-m.run/chiusura.txt"'
rm -f "$CD/spec-m-1-a.run/base.txt"; crun spec-m 77-chiusura
check "base del primo anello assente → NEEDS_VERIFICATION, nessun gate" 'grep -q "^Chiusura: NEEDS_VERIFICATION — base del primo anello assente" "$CD/spec-m.run/chiusura.txt" && [ ! -f "$T/c77-chiusura.gates-args" ]'
# 10. test-red phase (harness-pt11): lock, guard scope, driver verification (targeted gates.sh + plan-check.sh
#    red), closing (stub, test fingerprint in the basis, gen); S3 (test-stage, staging); comparison of the acceptance
#    tests after implement. Counterproof by mutation (run by hand with RP=<variant>): without
#    CONFRONTO-TEST-ACCETTAZIONE the implement that changes an acceptance test closes OK (red here).
export PLAN_CHECK_ROOT="$FIC_REPO"
PCK="$(dirname "$RP")/plan-check.sh"
mkdir -p "$FIC_REPO/modules/api/app" "$FIC_REPO/modules/api/tests" "$T/w3"
printf 'x\n' > "$FIC_REPO/modules/api/app/__init__.py"
cat > "$T/gates-red" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_OUT.gates-args"
ev="$FAKE_EVDIR"; mkdir -p "$ev"
case ${FAKE_RED:-ok} in
  ok) b='<testcase classname="tests.test_calc" name="test_somma"><failure message="assert 0 == 3">E  assert 0 == 3
tests/test_calc.py:4: AssertionError</failure></testcase>'; e=FAIL ;;
  imp) b='<testcase classname="tests.test_calc" name="test_somma"><failure message="ImportError">ImportError: cannot import name somma</failure></testcase>'; e=FAIL ;;
  verde) b='<testcase classname="tests.test_calc" name="test_somma"/>'; e=PASS ;;
esac
printf '<?xml version="1.0"?><testsuites><testsuite name="pytest">%s</testsuite></testsuites>\n' "$b" > "$ev/tests-be.junit.xml"
printf '{"gate":"tests-be","esito":"%s","report":"tests-be.junit.xml","motivo":""}\n' "$e" > "$ev/tests-be.json"
printf '{"gate":"tests-fe","esito":"SKIPPED","report":null,"motivo":"nessun file"}\n' > "$ev/tests-fe.json"
echo "gates: esito=$e chiave=k1 evidence=$ev"
[ "$e" = FAIL ] && exit 1 || exit 0
EOF
chmod +x "$T/gates-red"
TSP="$T/w3/spec-t.md" TRUN="$T/w3/spec-t.run"
mkspec() { # approved format-2 plan (current Approved basis), run dir and feature files reset
  rm -rf "$TRUN" "$FIC_REPO/modules/api/app/calc.py" "$FIC_REPO/modules/api/tests/test_calc.py"
  printf '%s\n' "# T" "## Requisiti funzionali" "1. RF1 — somma." "## Piano di implementazione" "Plan format: 2" "Plan status: APPROVED" \
    "Test level: std" "Superfici a rischio: nessuna" "### File toccati" "- \`modules/api/app/calc.py\` (nuovo)" \
    "- \`modules/api/tests/test_calc.py\` (nuovo)" "### Passi" "#### Blocco B1 — x" \
    "scrive: \`modules/api/app/calc.py\`, \`modules/api/tests/test_calc.py\`" "dopo: nessuno" "" "| id | file | modifica | test |" \
    "|---|---|---|---|" "| P1 | \`modules/api/app/calc.py\` | somma | T1 |" "### Tracciabilità requisiti" "| Req | Passi del piano | Verifica |" \
    "|---|---|---|" "| RF1 | P1 | T1 |" "### Piano di test" "| ID | requisito | file | asserzione | mutazione |" "|---|---|---|---|---|" \
    "| T1 | RF1 | \`modules/api/tests/test_calc.py::test_somma\` (nuovo) | rosso se: \`assert 0 == 3\` | \`modules/api/app/calc.py\` · \`somma\` · \`return a + b\` → \`return 0\` · rosso se: \`assert 0 == 3\` |" > "$TSP"
  local b; b=$(bash "$PCK" basis "$TSP" | sed -n 's/^Basis: //p')
  sed -i "s/^Superfici a rischio: .*/&\nApproved basis: $b/" "$TSP"
}
WRITE_RED='printf "def somma(a, b):\n    return 0\n" > "$FIC_REPO/modules/api/app/calc.py"; printf "from app.calc import somma\n\ndef test_somma():\n    assert somma(1, 2) == 3\n" > "$FIC_REPO/modules/api/tests/test_calc.py"'
trun() { FAKE_OUT="$T/$1" FIC_GATES="$T/gates-red" FAKE_EVDIR="$T/ev-$1" bash "$RP" "$TRUN" "$1" "$T/prompt.md" 2>"$T/$1.err" </dev/null; }
printf '%s\n' "# F" "## Piano di implementazione" "Plan status: APPROVED" > "$T/w3/spec-f1.md"
FAKE_OUT="$T/70-test-red" bash "$RP" "$T/w3/spec-f1.run" 70-test-red "$T/prompt.md" 2>/dev/null </dev/null; rc=$?
check "test-red su un piano in formato 1 → exit 2, nessuna sotto-sessione" '[ $rc -eq 2 ] && [ ! -f "$T/70-test-red.args" ]'
mkspec
FAKE_CMD="$WRITE_RED" trun 71-test-red; rc=$?
check "test-red: rossi dimostrati → .esito OK" '[ $rc -eq 0 ] && [ "$(sed -n 1p "$TRUN/log/71-test-red.esito")" = "ESITO FASE x: OK — finto" ]'
check "  FIC_PHASE=test-red e FIC_SCOPE = log/<label>.scope (test del piano + file nuovi)" 'grep -qx "FIC_PHASE=test-red" "$T/71-test-red.env" && grep -q "^FIC_SCOPE=.*71-test-red.scope$" "$T/71-test-red.env" && [ "$(cat "$TRUN/log/71-test-red.scope")" = "$(printf "modules/api/tests/test_calc.py\nmodules/api/app/calc.py")" ]'
check "  fase di codice: attribuzione in touched.txt, lock rilasciato" 'grep -qx modules/api/tests/test_calc.py "$TRUN/touched.txt" && grep -qx modules/api/app/calc.py "$TRUN/touched.txt" && [ -s "$TRUN/log/71-test-red.post-tree" ] && [ ! -d "$FIC_LOCK" ]'
check "  gates.sh mirato (std, test del piano) con l'esito atteso FAIL" '[ "$(sed -n 3p "$T/71-test-red.gates-args")" = std ] && grep -qx modules/api/tests/test_calc.py "$T/71-test-red.gates-args" && grep -q "^exit=1 livello=std" "$TRUN/log/71-test-red.gates"'
check "  chiusura: stub, tests.txt, tests <fp> nella basis, mutazione assorbita (L2)" 'grep -q "\"somma\"" "$TRUN/test-red/stubs.json" && [ -s "$TRUN/test-red/tests.txt" ] && grep -q "^Approved basis: .* · tests [0-9a-f]\{12\}$" "$TSP" && grep -q "\"assorbita\": true" "$TRUN/counterproof/mutations.json"'
check "  cycle-state: dopo test-red OK → IMPLEMENT" 'bash "$(dirname "$RP")/cycle-state.sh" "$TSP" | grep -q "^Next: IMPLEMENT"'
# pk09 (pilot on a second project): the run dir starts without touched.txt (mkspec resets it); test-red's «touched-pre» copy
# had the input redirect before 2>/dev/null, and the error came out anyway. Red if it shows up again in stderr.
# We look for «touched.txt: » (path followed by the error message), not the message text: it works in any language.
# Counterproof by mutation at the end of section 10 (redirect without the [ -f ] check => red).
touched_err() { grep -qsE 'touched\.txt: ' "$T/$1.err" "$TRUN/log/$1.stderr"; }
check "  test-red senza touched.txt prima della fase: nessun errore «touched.txt: …» nello stderr" '[ -f "$TRUN/log/71-test-red.touched-pre" ] && ! touched_err 71-test-red'
cp "$TSP" "$T/w3/spec-t.dopo-red"
FAKE_CMD='printf "def somma(a, b):\n    return a + b\n" > "$FIC_REPO/modules/api/app/calc.py"' FAKE_OUT="$T/72-implement" bash "$RP" "$TRUN" 72-implement "$T/prompt.md" 2>/dev/null </dev/null
check "implement che riempie lo stub → OK (lo stub non e' un test)" '[ "$(sed -n 1p "$TRUN/log/72-implement.esito")" = "ESITO FASE x: OK — finto" ]'
# PRESCRIBED CHANGE (a plan step changes a helper in a file that also contains an acceptance test):
# the acceptance test file is in B1's scrive: and test_somma stays identical -> OK with AVVISO and fingerprint
# re-recorded (before the fix: STOP «test di accettazione modificati»). The acceptance function changed -> STOP.
FAKE_CMD='printf "\ndef test_altro():\n    assert True\n" >> "$FIC_REPO/modules/api/tests/test_calc.py"' FAKE_OUT="$T/73-fix" bash "$RP" "$TRUN" 73-fix "$T/prompt.md" 2>/dev/null </dev/null
check "fix che cambia un file di test PRESCRITTO (scrive: di B1), test_somma invariata → OK, AVVISO in .esito" '[ "$(sed -n 1p "$TRUN/log/73-fix.esito")" = "ESITO FASE x: OK — finto" ] && grep -q "^AVVISO: test di accettazione: modules/api/tests/test_calc.py cambiato, modifica prescritta dal piano (scrive: di B1); funzioni dei test di accettazione invariate da test-red (test_somma)" "$TRUN/log/73-fix.esito"'
check "  impronta riregistrata: tests.txt = plan-check tests, base in tests.red.txt, basis Tests FRESH, cycle-state non STALE (tests)" '[ "$(cat "$TRUN/test-red/tests.txt")" = "$(bash "$PCK" tests "$TSP" | tr -d "\r")" ] && ! cmp -s "$TRUN/test-red/tests.txt" "$TRUN/test-red/tests.red.txt" && bash "$PCK" basis "$TSP" | grep -qx "Tests status: FRESH" && ! bash "$(dirname "$RP")/cycle-state.sh" "$TSP" | grep -q "STALE (tests)\|test di accettazione cambiati"'
check "  e i gate del driver (e' un OK)" '[ -f "$TRUN/log/73-fix.gates" ]'
FAKE_CMD='sed -i "s/somma(1, 2) == 3/somma(2, 2) == 4/" "$FIC_REPO/modules/api/tests/test_calc.py"' FAKE_OUT="$T/73b-fix" bash "$RP" "$TRUN" 73b-fix "$T/prompt.md" 2>/dev/null </dev/null
check "fix che cambia la FUNZIONE del test di accettazione (file prescritto) → .esito STOP deviazione, a prescindere dal report" 'sed -n 1p "$TRUN/log/73b-fix.esito" | grep -q "^PHASE RESULT fix: STOP — deviazione: test di accettazione modificati dopo test-red (modules/api/tests/test_calc.py (test_somma))" && grep -qx "originale=ESITO FASE x: OK — finto" "$TRUN/log/73b-fix.esito"'
check "  e nessun gate (non e' un OK), impronta NON riregistrata" '[ ! -f "$TRUN/log/73b-fix.gates" ] && [ "$(cat "$TRUN/test-red/tests.txt")" != "$(bash "$PCK" tests "$TSP" | tr -d "\r")" ]'
sed -i "s/somma(2, 2) == 4/somma(1, 2) == 3/" "$FIC_REPO/modules/api/tests/test_calc.py"
FAKE_CMD='printf "\ndef test_terzo():\n    assert True\n" >> "$FIC_REPO/modules/api/tests/test_calc.py"' FAKE_OUT="$T/73c-fix" bash "$RP" "$TRUN" 73c-fix "$T/prompt.md" 2>/dev/null </dev/null
check "  di nuovo un aiutante dopo la riregistrazione: la base resta test-red (tests.red.txt) → OK" '[ "$(sed -n 1p "$TRUN/log/73c-fix.esito")" = "ESITO FASE x: OK — finto" ] && grep -q "funzioni dei test di accettazione invariate da test-red (test_somma)" "$TRUN/log/73c-fix.esito"'
cp "$TSP" "$T/w3/spec-t.prima-fuori"
sed -i 's/^scrive: `modules\/api\/app\/calc.py`, `modules\/api\/tests\/test_calc.py`$/scrive: `modules\/api\/app\/calc.py`/' "$TSP"
FAKE_CMD='printf "\ndef test_quarto():\n    assert True\n" >> "$FIC_REPO/modules/api/tests/test_calc.py"' FAKE_OUT="$T/73d-fix" bash "$RP" "$TRUN" 73d-fix "$T/prompt.md" 2>/dev/null </dev/null
check "file di test di accettazione in nessuno scrive: → STOP deviazione (manomissione), nessun gate" 'sed -n 1p "$TRUN/log/73d-fix.esito" | grep -q "^PHASE RESULT fix: STOP — deviazione: test di accettazione modificati dopo test-red (modules/api/tests/test_calc.py);" && [ ! -f "$TRUN/log/73d-fix.gates" ]'
cp "$T/w3/spec-t.prima-fuori" "$TSP"
mkspec
FAKE_RED=imp FAKE_CMD="$WRITE_RED" trun 74-test-red
check "test-red con rosso da import → STOP «non dimostrato», originale= sotto" 'sed -n 1p "$TRUN/log/74-test-red.esito" | grep -q "^PHASE RESULT test-red: STOP — test di accettazione non dimostrato: T1 rosso_import" && grep -qx "originale=ESITO FASE x: OK — finto" "$TRUN/log/74-test-red.esito"'
check "  nessuna impronta dei test registrata, cycle-state STOP" '! grep -q "· tests " "$TSP" && bash "$(dirname "$RP")/cycle-state.sh" "$TSP" | grep -q "^Next: STOP — 74-test-red: test di accettazione non registrati"'
mkspec
FAKE_RED=verde FAKE_CMD="$WRITE_RED" trun 75-test-red
check "test-red con un test verde → STOP" 'sed -n 1p "$TRUN/log/75-test-red.esito" | grep -q "^PHASE RESULT test-red: STOP — .*T1 verde"'
mkspec
FAKE_CMD="$WRITE_RED; echo fuori >> \"\$FIC_REPO/a.py\"" trun 75b-test-red
check "test-red che scrive fuori dallo scope (via Bash) → STOP, nessun gate" 'sed -n 1p "$TRUN/log/75b-test-red.esito" | grep -q "^PHASE RESULT test-red: STOP — scritture fuori dallo scope di test-red .*: a.py$" && [ ! -f "$T/75b-test-red.gates-args" ]'
(cd "$FIC_REPO" && git checkout -q -- a.py)
# OTHER FLOWS: an out-of-scope path changed during test-red and NEVER named by the subsession (no tool_use
# cites it) belongs to another flow: do-not-touch, out of touched.txt, warning, gates as for an OK. Named (75b above:
# (b), path in a Bash command; 75e: the basename alone) or log without result -> STOP. implement: stays in touched.txt,
# annotated in .altri-flussi. Counterproof by mutation (by hand: RP=<mutated copy with the same name in another
# folder>, compared with a NON-mutated copy placed the same way): with nominato() always false 75b turns red.
(cd "$FIC_REPO" && mkdir -p docs && printf 'nota\n' > docs/NOTE.md && git add docs/NOTE.md && git commit -qm nota)
ALTRO='echo altro flusso >> "$FIC_REPO/docs/NOTE.md"'
mkspec
FAKE_ALTRO="$ALTRO" FAKE_CMD="$WRITE_RED" trun 75c-test-red
check "(a) test-red: path fuori scope MAI nominato → nessuno STOP, gate eseguiti come per un OK" '[ "$(sed -n 1p "$TRUN/log/75c-test-red.esito")" = "ESITO FASE x: OK — finto" ] && grep -qx modules/api/tests/test_calc.py "$T/75c-test-red.gates-args" && ! grep -qx docs/NOTE.md "$T/75c-test-red.gates-args" && grep -q "· tests " "$TSP"'
check "  in do-not-touch.txt, fuori da touched.txt, in log/<label>.altri-flussi" 'grep -qx docs/NOTE.md "$TRUN/do-not-touch.txt" && ! grep -qx docs/NOTE.md "$TRUN/touched.txt" && grep -qx modules/api/app/calc.py "$TRUN/touched.txt" && [ "$(cat "$TRUN/log/75c-test-red.altri-flussi")" = docs/NOTE.md ]'
check "  avviso nello .stderr, su stderr e in .esito (dopo state=)" 'l="AVVISO: docs/NOTE.md cambiato durante la fase da un altro flusso (mai nominato dalla sotto-sessione): non attribuito, in do-not-touch"; grep -qxF "$l" "$TRUN/log/75c-test-red.stderr" && grep -qxF "$l" "$T/75c-test-red.err" && tail -1 "$TRUN/log/75c-test-red.esito" | grep -qxF "$l" && sed -n 2p "$TRUN/log/75c-test-red.esito" | grep -q "^state="'
FAKE_ALTRO="$ALTRO" FAKE_CMD='printf "def somma(a, b):\n    return a + b\n" > "$FIC_REPO/modules/api/app/calc.py"' FAKE_OUT="$T/75d-implement" bash "$RP" "$TRUN" 75d-implement "$T/prompt.md" 2>"$T/75d-implement.err" </dev/null
check "(e) implement con un file mai nominato → esito OK, resta in touched.txt, annotato in .altri-flussi con avviso" '[ "$(sed -n 1p "$TRUN/log/75d-implement.esito")" = "ESITO FASE x: OK — finto" ] && grep -qx docs/NOTE.md "$TRUN/touched.txt" && [ "$(cat "$TRUN/log/75d-implement.altri-flussi")" = docs/NOTE.md ] && grep -q "^AVVISO: docs/NOTE.md cambiato durante la fase e mai nominato dalla sotto-sessione: resta in touched.txt" "$TRUN/log/75d-implement.stderr" && grep -qx docs/NOTE.md "$T/75d-implement.gates-args"'
(cd "$FIC_REPO" && git checkout -q -- docs/NOTE.md)
mkspec
FAKE_ALTRO="$ALTRO" FAKE_LOGCMD='sed -n 1p NOTE.md' FAKE_CMD="$WRITE_RED" trun 75e-test-red
check "(c) test-red: fuori scope con la sola basename nominata → STOP, nessun gate, niente do-not-touch" 'sed -n 1p "$TRUN/log/75e-test-red.esito" | grep -q "^PHASE RESULT test-red: STOP — scritture fuori dallo scope di test-red .*: docs/NOTE.md$" && [ ! -f "$T/75e-test-red.gates-args" ] && [ ! -f "$TRUN/do-not-touch.txt" ]'
(cd "$FIC_REPO" && git checkout -q -- docs/NOTE.md)
mkspec
FAKE_RESULT='{"type":"system","subtype":"senza-result"}' FAKE_ALTRO="$ALTRO" FAKE_CMD="$WRITE_RED" trun 75f-test-red
check "(d) test-red finito senza evento result → nessun OK, nessun gate, niente do-not-touch" '! grep -Eq "^(PHASE RESULT|ESITO FASE) [^:]*: OK" "$TRUN/log/75f-test-red.esito" 2>/dev/null && [ ! -f "$T/75f-test-red.gates-args" ] && [ ! -f "$TRUN/do-not-touch.txt" ]'
printf 'docs/NOTE.md\n' > "$T/np"; : > "$T/vuoto.jsonl"
{ grep -v '"type":"result"' "$TRUN/log/75f-test-red.jsonl"; echo '{"type":"result","result":"x"}'; } > "$T/con-result.jsonl"
bash "$RP" --nominati "$FIC_REPO" "$T/np" "$TRUN/log/75f-test-red.jsonl" > "$T/np1" 2>/dev/null; r1=$?
bash "$RP" --nominati "$FIC_REPO" "$T/np" "$T/vuoto.jsonl" > "$T/np2" 2>/dev/null; r2=$?
bash "$RP" --nominati "$FIC_REPO" "$T/np" "$T/con-result.jsonl" > "$T/np3" 2>/dev/null; r3=$?
check "  --nominati fail-closed: log senza result o vuoto → exit 3, tutti nominati; lo stesso log con result → mai" '[ $r1 -eq 3 ] && [ "$(tr -d "\r" < "$T/np1")" = "$(printf "nominato\tdocs/NOTE.md")" ] && [ $r2 -eq 3 ] && [ "$(tr -d "\r" < "$T/np2")" = "$(printf "nominato\tdocs/NOTE.md")" ] && [ $r3 -eq 0 ] && [ "$(tr -d "\r" < "$T/np3")" = "$(printf "mai\tdocs/NOTE.md")" ]'
(cd "$FIC_REPO" && git checkout -q -- docs/NOTE.md)
# test-red: a FEATURE path (already in touched.txt before the phase) changed by another flow: it cannot be both in
# touched.txt and in do-not-touch -> STOP with the reason, it stays in touched.txt
mkspec; mkdir -p "$TRUN"; echo docs/NOTE.md > "$TRUN/touched.txt"
FAKE_ALTRO="$ALTRO" FAKE_CMD="$WRITE_RED" trun 75g-test-red
check "test-red: path gia' in touched.txt cambiato da un altro flusso → STOP col motivo, resta in touched.txt, niente do-not-touch, nessun gate" 'sed -n 1p "$TRUN/log/75g-test-red.esito" | grep -q "^PHASE RESULT test-red: STOP — file della feature (gia. in touched.txt prima di test-red) cambiato durante la fase da un altro flusso (mai nominato dalla sotto-sessione): docs/NOTE.md — resta in touched.txt" && grep -qx docs/NOTE.md "$TRUN/touched.txt" && [ ! -f "$TRUN/do-not-touch.txt" ] && [ ! -f "$T/75g-test-red.gates-args" ]'
(cd "$FIC_REPO" && git checkout -q -- docs/NOTE.md)
# «attribuzione non verificabile» branch of verify_red, end-to-end: a Python that fails ONLY on NOMI_PY
REALPY=$(. "$(dirname "$RP")/python.sh" && printf '%s' "$FIC_PY")
printf '#!/usr/bin/env bash\nfor a in "$@"; do case "$a" in *"def nominato("*) exit 9 ;; esac; done\nexec "%s" "$@"\n' "$REALPY" > "$T/py-rotto"; chmod +x "$T/py-rotto"
mkspec
FIC_PYTHON="$T/py-rotto" FAKE_ALTRO="$ALTRO" FAKE_CMD="$WRITE_RED" trun 75h-test-red
check "test-red con la ricerca per nome che fallisce → STOP fuori scope «non verificabile», niente do-not-touch, nessun gate" 'sed -n 1p "$TRUN/log/75h-test-red.esito" | grep -q "^PHASE RESULT test-red: STOP — scritture fuori dallo scope di test-red .*: docs/NOTE.md (attribuzione per nome non verificabile" && [ ! -f "$TRUN/do-not-touch.txt" ] && [ ! -f "$T/75h-test-red.gates-args" ]'
(cd "$FIC_REPO" && git checkout -q -- docs/NOTE.md)
# Table of the NOMI_PY branches (--nominati, hand-written jsonl, root C:/repo): for each branch a named one and a never.
# Counterproof by mutation (by hand, as above): without the loop over the writing commands (ancestors, GLOB, PUNTO,
# TUTTO, root) the «nominato» cases of those branches turn red.
nomi() { # $1 expected (nominato|mai) · $2 path · $3 tool (Bash: command · Edit: file_path) · $4 string
  local s=${4//\\/\\\\} k=command; s=${s//\"/\\\"}; [ "$3" = Edit ] && k=file_path
  printf '%s\n' "$2" > "$T/nt.p"
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"'"$3"'","input":{"'"$k"'":"'"$s"'"}}]}}' '{"type":"result","result":"x"}' > "$T/nt.jsonl"
  NT_OUT=$(bash "$RP" --nominati C:/repo "$T/nt.p" "$T/nt.jsonl" 2>/dev/null | tr -d '\r')
  NT_EXP=$(printf '%s\t%s' "$1" "$2")
  check "--nominati: $1 $2 ← $3 $4" '[ "$NT_OUT" = "$NT_EXP" ]'
}
nomi nominato docs/NOTE.md Edit 'C:\repo\docs\NOTE.md'                  # path with \
nomi mai      docs/NOTE.md Edit 'C:\repo\docs\ALTRO.md'
nomi nominato modules/api/app/x.py Bash 'rm -r modules/api'           # ancestor in a command that writes
nomi mai      modules/app/y.ts     Bash 'rm -r modules/api'
nomi mai      modules/api/app/x.py Bash 'ls modules/api'                # ancestor, but the command does not write
nomi nominato modules/api/app/x.py Bash 'sed -i s/a/b/ modules/api/app/*.py'   # GLOB
nomi mai      modules/app/y.ts     Bash 'sed -i s/a/b/ modules/api/app/*.py'
nomi nominato PRODUZIONE.md Bash 'cp -r /tmp/x .'                       # PUNTO
nomi mai      PRODUZIONE.md Bash 'cp /tmp/x ./sub/y'
nomi nominato PRODUZIONE.md Bash 'npx prettier --write modules/app/x.vue'   # TUTTO
nomi nominato PRODUZIONE.md Bash 'npx vitest run -u modules/app/x.test.ts'
nomi mai      PRODUZIONE.md Bash 'npx prettier --check modules/app/x.vue'
nomi mai      PRODUZIONE.md Bash 'ls | sort -u > /tmp/o'
nomi nominato PRODUZIONE.md Bash 'find /c/repo -name x -delete'         # root as the target
nomi mai      PRODUZIONE.md Bash 'cd C:/repo && cat x > /tmp/o'        # ... not as cd
nomi nominato PRODUZIONE.md Bash 'ls . > /tmp/o'                        # INNOCUI: without harmless redirections it writes
nomi mai      PRODUZIONE.md Bash 'ls . 2>/dev/null'
nomi mai      PRODUZIONE.md Bash 'ls . 2>&1 | tail'
nomi nominato modules/api/app/services/s.py Bash 'sed -i s/a/b/ app/services/*.py'   # relative to a previous cd
nomi nominato modules/api/app/services/s.py Bash 'rm -r app/services'
nomi mai      modules/api/app/other/s.py    Bash 'sed -i s/a/b/ app/services/*.py'
nomi mai      modules/api/app/other/s.py    Bash 'rm -r app/services'
# S3: tests parked. test-stage without lock, scope = staging/ alone, staging.fp = plan fingerprint
mkspec
PFP=$(bash "$PCK" basis "$TSP" | sed -n 's/^Basis: .*plan \([0-9a-f]*\).*/\1/p')
STAGE_WRITE='mkdir -p "$TRUN/staging/modules/api/tests" "$TRUN/staging/modules/api/app"; printf "def somma(a, b):\n    return 0\n" > "$TRUN/staging/modules/api/app/calc.py"; printf "from app.calc import somma\n\ndef test_somma():\n    assert somma(1, 2) == 3\n" > "$TRUN/staging/modules/api/tests/test_calc.py"'
mkdir -p "$FIC_LOCK"; printf 'run=altro\nlabel=99-implement\nsince=x\npid=%s\n' "$$" > "$FIC_LOCK/owner"   # a live code phase
TRUN="$TRUN" FAKE_CMD="$STAGE_WRITE" FAKE_OUT="$T/76-test-stage" bash "$RP" "$TRUN" 76-test-stage "$T/prompt.md" 2>/dev/null </dev/null; rc=$?
rm -rf "$FIC_LOCK"
check "test-stage gira anche col lock di codice preso (non tocca il tree)" '[ $rc -eq 0 ] && grep -qx "FIC_PHASE=test-stage" "$T/76-test-stage.env"'
check "  scope = la sola staging/, staging.fp = impronta del piano" 'grep -q "spec-t.run/staging/$" "$TRUN/log/76-test-stage.scope" && [ "$(cat "$TRUN/staging.fp")" = "$PFP" ]'
FAKE_OUT="$T/77-test-red" FIC_GATES="$T/gates-red" FAKE_EVDIR="$T/ev-77" bash "$RP" "$TRUN" 77-test-red "$T/prompt.md" 2>"$T/77.err" </dev/null
check "S3: stessa impronta → test copiati nel tree, nessuna sotto-sessione, verifica eseguita → OK" '[ ! -f "$T/77-test-red.args" ] && [ -f "$FIC_REPO/modules/api/tests/test_calc.py" ] && sed -n 1p "$TRUN/log/77-test-red.esito" | grep -q "^PHASE RESULT test-red: OK — test in sosta (S3)" && grep -q "· tests " "$TSP"'
check "  staging consumato (staging.copiato)" '[ ! -d "$TRUN/staging" ] && [ -d "$TRUN/staging.copiato" ] && grep -q "S3: 2 file in sosta copiati" "$TRUN/log/77-test-red.stderr"'
mkspec
TRUN="$TRUN" FAKE_CMD="$STAGE_WRITE" FAKE_OUT="$T/78-test-stage" bash "$RP" "$TRUN" 78-test-stage "$T/prompt.md" 2>/dev/null </dev/null
echo 000000000000 > "$TRUN/staging.fp"   # the plan changed after parking
FAKE_CMD="$WRITE_RED" trun 79-test-red
check "S3: impronta diversa → staging scartato, la sotto-sessione scrive i test" '[ -f "$T/79-test-red.args" ] && [ ! -d "$TRUN/staging" ] && [ ! -f "$TRUN/staging.fp" ] && grep -q "S3: staging scartato" "$TRUN/log/79-test-red.stderr"'
check "--lock-status dentro test-red → 0" 'FIC_PHASE=test-red bash "$RP" --lock-status | grep -q "dentro il ciclo"'
# counterproof (pk09, 0.2) on a copy of the plugin ($HC, section 8): the «touched-pre» copy without the
# [ -f ] check (the old redirect) => the «touched.txt: …» error shows up again in stderr, case 71 would be red
sed 's/^  \[ "\$phase" = test-red \] && { \[ -f "\$dir\/touched.txt" \] && tr -d/  [ "$phase" = test-red ] \&\& { tr -d/' "$RP" > "$MRP"
if cmp -s "$RP" "$MRP"; then fail=$((fail + 1)); n=$((n + 1)); echo "FAIL: controprova (touched-pre): la mutazione non si applica"
else
  mkspec
  FAKE_CMD="$WRITE_RED" FAKE_OUT="$T/7m-test-red" FIC_GATES="$T/gates-red" FAKE_EVDIR="$T/ev-7m" bash "$MRP" "$TRUN" 7m-test-red "$T/prompt.md" 2>"$T/7m-test-red.err" </dev/null
  check "controprova (touched-pre): col redirect senza [ -f ] l'errore «touched.txt: …» torna nello stderr (il caso 71 sarebbe rosso)" 'touched_err 7m-test-red'
fi
# PLAN_CHECK_ROOT stays the fake repo for the lanes too (before, it went back to the current folder: see 8b)

# 11. lanes (harness-pt13): two independent blocks -> two subsessions TOGETHER under a single lock, with FIC_LANE
#    and FIC_WRITE_SCOPE; after-the-fact check of the diff; driver gates once, when the lanes are done.
cat > "$T/claude-corsie" <<'EOF'
#!/usr/bin/env bash
k=${FIC_LANE:-0}; O="$FAKE_OUT.corsia-$k"
printf '%s\n' "$@" > "$O.args"
printf 'FIC_PHASE=%s\nFIC_LANE=%s\nFIC_WRITE_SCOPE=%s\nWSLENV=%s\n' "$FIC_PHASE" "${FIC_LANE:-}" "${FIC_WRITE_SCOPE:-}" "${WSLENV:-}" > "$O.env"
cat > "$O.stdin"
date +%s%N > "$O.start"
eval "s=\${FAKE_SLEEP_$k:-${FAKE_SLEEP:-0}}"; sleep "$s"
eval "t=\${FAKE_TOUCH_$k:-}"; [ -n "$t" ] && echo "corsia $k" >> "$FIC_REPO/$t"
eval "d=\${FAKE_FILE_$k:-}"
# lane preflight (SKILL.md: do-not-touch.<k>.txt and mixed.<k>.txt in the run dir)
[ -n "${FAKE_RUNDIR:-}" ] && printf 'altro%s.py\ncomune.py\n' "$k" > "$FAKE_RUNDIR/do-not-touch.$k.txt" && printf 'misto%s.py\n' "$k" > "$FAKE_RUNDIR/mixed.$k.txt"
date +%s%N > "$O.end"
eval "nr=\${FAKE_NORESULT_$k:-}"; eval "st=\${FAKE_STOP_$k:-}"; eval "ex=\${FAKE_EXIT_$k:-0}"
# FAKE_JSONONLY_k=OK|STOP: structured output like the real lanes, result = the JSON ONLY (no ESITO line);
# FAKE_TXTSTOP_k: STOP text line and OK object (in disagreement)
eval "jo=\${FAKE_JSONONLY_$k:-}"; eval "ts=\${FAKE_TXTSTOP_$k:-}"
# FAKE_DEV_k: the lane's deviations (JSON strings), with the English result line and "none" (1.3.0)
eval "dv=\${FAKE_DEV_$k:-}"
j='{"fase":"'"$FIC_PHASE"'","esito":"'"${jo:-OK}"'","motivo":"corsia '"$k"' solo json","deviazioni":[],"bloccato_su":"nessuno","file":['"${d:+\"$d\"}"'],"gate_interni":[],"finding":[]}'
if [ -n "$nr" ]; then :
elif [ -n "$jo" ]; then echo '{"type":"result","result":"'"${j//\"/\\\"}"'","structured_output":'"$j"'}'
elif [ -n "$ts" ]; then echo '{"type":"result","result":"ESITO FASE implement: STOP — testo discorde '"$k"'","structured_output":'"$j"'}'
elif [ -n "$dv" ]; then echo '{"type":"result","result":"PHASE RESULT implement: OK — corsia '"$k"'","structured_output":{"fase":"'"$FIC_PHASE"'","esito":"OK","motivo":"corsia '"$k"'","deviazioni":['"$dv"'],"bloccato_su":"none","file":['"${d:+\"$d\"}"'],"gate_interni":[],"finding":[]}}'
elif [ -n "$st" ]; then echo '{"type":"result","result":"ESITO FASE implement: STOP — corsia '"$k"' ferma","structured_output":{"fase":"implement","esito":"STOP","motivo":"corsia '"$k"' ferma","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}'
else echo '{"type":"result","result":"ESITO FASE implement: OK — corsia '"$k"'","structured_output":{"fase":"'"$FIC_PHASE"'","esito":"OK","motivo":"corsia '"$k"'","deviazioni":[],"bloccato_su":"nessuno","file":['"${d:+\"$d\"}"'],"gate_interni":[],"finding":[]}}'; fi
exit "$ex"
EOF
chmod +x "$T/claude-corsie"
W4="$T/w4"; mkdir -p "$W4"; SPL="$W4/spec-l.md"; R4="$W4/spec-l.run"; L4="$R4/log"
printf '%s\n' "# P" "## Requisiti funzionali" "1. RF1 — A." "2. RF2 — B." "## Piano di implementazione" "Plan format: 2" \
  "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" "### File toccati" '- `a.py`' '- `b.py`' "### Passi" \
  "#### Blocco B1 — uno" 'scrive: `a.py`' "dopo: nessuno" "" "| id | file | modifica | test |" "|---|---|---|---|" '| P1 | `a.py` | uno | T1 |' "" \
  "#### Blocco B2 — due" 'scrive: `b.py`' "dopo: nessuno" "" "| id | file | modifica | test |" "|---|---|---|---|" '| P2 | `b.py` | due | T2 |' \
  "### Tracciabilità requisiti" "| Req | Passi del piano | Verifica |" "|---|---|---|" "| RF1 | P1 | T1 |" "| RF2 | P2 | T2 |" \
  "### Piano di test" "| ID | requisito | file | asserzione | mutazione |" "|---|---|---|---|---|" \
  '| T1 | RF1 | `modules/api/tests/test_a.py::test_a` (nuovo) | rosso se: A | — |' '| T2 | RF2 | `modules/api/tests/test_b.py::test_b` (nuovo) | rosso se: B | — |' > "$SPL"
lrun() { CLAUDE_BIN="$T/claude-corsie" FAKE_OUT="$T/$1" bash "$RP" "$R4" "$1" "$T/prompt.md" 2>/dev/null </dev/null; }
(cd "$FIC_REPO" && git checkout -q -- .)
FAKE_RUNDIR="$R4" FAKE_SLEEP=3 FAKE_TOUCH_1=a.py FAKE_TOUCH_2=b.py FAKE_FILE_1=a.py FAKE_FILE_2=b.py lrun 01-implement & a=$!
for _ in $(seq 1 60); do [ -f "$FIC_LOCK/owner" ] && grep -q '^cpid2=' "$FIC_LOCK/owner" && break; sleep 0.25; done
check "corsie: owner con cpid= e cpid2= (un solo lock, due sotto-sessioni)" 'grep -q "^cpid=" "$FIC_LOCK/owner" && grep -q "^cpid2=" "$FIC_LOCK/owner"'
wait $a; rc=$?
check "corsie: la fase finisce 0 e rilascia il lock" '[ $rc -eq 0 ] && [ ! -d "$FIC_LOCK" ]'
check "  log/<label>.corsie: parallelo, corsia 1: B1, corsia 2: B2, scope" 'grep -qx "blocks-independent: esito=parallelo corsie=2" "$L4/01-implement.corsie" && grep -qx "corsia 1: B1" "$L4/01-implement.corsie" && grep -qx "scope 2: b.py" "$L4/01-implement.corsie"'
check "  due sotto-sessioni INSIEME (la seconda parte prima che la prima finisca)" '[ "$(cat "$T/01-implement.corsia-2.start")" -lt "$(cat "$T/01-implement.corsia-1.end")" ] && [ "$(cat "$T/01-implement.corsia-1.start")" -lt "$(cat "$T/01-implement.corsia-2.end")" ]'
check "  FIC_LANE, FIC_WRITE_SCOPE e WSLENV per corsia" 'grep -qx "FIC_LANE=1" "$T/01-implement.corsia-1.env" && grep -qx "FIC_WRITE_SCOPE=a.py" "$T/01-implement.corsia-1.env" && grep -qx "FIC_LANE=2" "$T/01-implement.corsia-2.env" && grep -qx "FIC_WRITE_SCOPE=b.py" "$T/01-implement.corsia-2.env" && grep -q "^WSLENV=FIC_LANE" "$T/01-implement.corsia-2.env"'
check "  prompt della corsia: il prompt + la riga CORSIA k/2 coi suoi blocchi" 'grep -q "^/full-implementation-cycle" "$T/01-implement.corsia-1.stdin" && grep -q "^CORSIA 1/2 (driver, run-phase.sh): sono tuoi SOLO i blocchi B1 " "$T/01-implement.corsia-1.stdin" && grep -q "^CORSIA 2/2 .*blocchi B2 " "$T/01-implement.corsia-2.stdin"'
check "  a posteriori: diff diviso per scope" 'grep -qx "posteriori: esito=OK corsia 1: a.py · corsia 2: b.py" "$L4/01-implement.posteriori"'
check "  esito unito OK e result.json con i file delle due corsie" 'sed -n 1p "$L4/01-implement.esito" | grep -q "^PHASE RESULT implement: OK — corsie parallele: corsia 1: corsia 1 · corsia 2: corsia 2" && grep -q "\"a.py\"" "$L4/01-implement.result.json" && grep -q "\"b.py\"" "$L4/01-implement.result.json"'
check "  touched.txt con i file delle due corsie; gate del driver UNA volta, a corsie finite, su entrambi" 'grep -qx a.py "$R4/touched.txt" && grep -qx b.py "$R4/touched.txt" && [ "$(wc -l < "$T/01-implement.gates-calls")" = 1 ] && grep -qx a.py "$T/01-implement.gates-args" && grep -qx b.py "$T/01-implement.gates-args"'
check "  preflight delle corsie unito (sort -u) in do-not-touch.txt e mixed.txt, lette dalle fasi successive" '[ "$(tr "\n" " " < "$R4/do-not-touch.txt")" = "altro1.py altro2.py comune.py " ] && [ "$(tr "\n" " " < "$R4/mixed.txt")" = "misto1.py misto2.py " ]'
(cd "$FIC_REPO" && git checkout -q -- .)
FAKE_TOUCH_1=a.py FAKE_TOUCH_2=a.py FAKE_FILE_2=a.py lrun 02-implement; rc=$?
check "diff a posteriori: file scritto da entrambe le corsie => STOP, nessun gate" '[ $rc -eq 0 ] && grep -q "scritto da entrambe le corsie" "$L4/02-implement.posteriori" && sed -n 1p "$L4/02-implement.esito" | grep -q "^PHASE RESULT implement: STOP — controllo a posteriori delle corsie: a.py scritto da entrambe le corsie" && [ ! -f "$L4/02-implement.gates" ]'
(cd "$FIC_REPO" && git checkout -q -- .)
FAKE_TOUCH_2=c.py lrun 03-implement
check "diff a posteriori: file fuori dall'unione degli scrive: => STOP" 'grep -q "c.py cambiato fuori" "$L4/03-implement.posteriori" && sed -n 1p "$L4/03-implement.esito" | grep -q "STOP — controllo a posteriori"'
rm -f "$FIC_REPO/c.py"
# failing lanes: JSON STOP, no result event, exit != 0 => never an OK, no gates
printf 'vecchio.py\n' > "$R4/do-not-touch.1.txt"; printf 'vecchio-misto.py\n' > "$R4/mixed.2.txt"   # previous round
FAKE_STOP_2=1 FAKE_TOUCH_1=a.py lrun 05-implement; rc=$?
check "liste per corsia di un giro precedente cancellate all'avvio: le corsie senza preflight non le uniscono" '[ ! -f "$R4/do-not-touch.1.txt" ] && [ ! -f "$R4/mixed.2.txt" ] && ! grep -qx vecchio.py "$R4/do-not-touch.txt" && ! grep -qx vecchio-misto.py "$R4/mixed.txt"'
check "corsia 2 con JSON STOP => .esito STOP, nessun gate" '[ $rc -eq 0 ] && sed -n 1p "$L4/05-implement.esito" | grep -q "^PHASE RESULT implement: STOP — corsia 2: corsia 2 ferma" && [ ! -f "$L4/05-implement.gates" ]'
(cd "$FIC_REPO" && git checkout -q -- .)
FAKE_NORESULT_2=1 lrun 06-implement; rc=$?
check "corsia senza evento result => .esito STOP, nessun result.json, nessun gate" '[ $rc -eq 0 ] && sed -n 1p "$L4/06-implement.esito" | grep -q "^PHASE RESULT implement: STOP" && grep -q "corsia 2: nessun evento result" "$L4/06-implement.esito" && [ ! -f "$L4/06-implement.result.json" ] && [ ! -f "$L4/06-implement.gates" ]'
FAKE_EXIT_2=3 lrun 07-implement; rc=$?
check "exit != 0 di una corsia => la fase esce con quel codice (.exit), nessun ESITO OK, nessun gate" '[ $rc -eq 3 ] && [ "$(cat "$L4/07-implement.exit")" = 3 ] && ! grep -Eq "^(PHASE RESULT|ESITO FASE) implement: OK" "$L4/07-implement.esito" 2>/dev/null && [ ! -f "$L4/07-implement.gates" ]'
check "  e l'evento result unito e' STOP «corsia 2: uscita 3», non OK" 'tail -1 "$L4/07-implement.jsonl" | grep -q "\"result\": \"PHASE RESULT implement: STOP [^\"]*corsia 2: uscita 3\"" && ! tail -1 "$L4/07-implement.jsonl" | grep -Eq "(PHASE RESULT|ESITO FASE) implement: OK"'
FIC_LANES=0 FAKE_TOUCH_0=a.py lrun 04-implement; rc=$?
check "FIC_LANES=0: in serie come prima (una sotto-sessione, senza FIC_LANE)" '[ $rc -eq 0 ] && grep -qx "blocks-independent: esito=serie motivo=FIC_LANES=0" "$L4/04-implement.corsie" && [ -f "$T/04-implement.corsia-0.args" ] && [ ! -f "$T/04-implement.corsia-1.args" ] && grep -qx "FIC_WRITE_SCOPE=" "$T/04-implement.corsia-0.env"'
(cd "$FIC_REPO" && git checkout -q -- .)
# structured exit: the result of each lane is the ONLY JSON (real case: log/<label>.corsia-1.jsonl of a cycle).
# Before the fix: «STOP — corsia 1: nessuna riga ESITO» even with valid JSON and OK outcome.
FAKE_JSONONLY_1=OK FAKE_JSONONLY_2=OK FAKE_TOUCH_1=a.py FAKE_TOUCH_2=b.py FAKE_FILE_1=a.py FAKE_FILE_2=b.py lrun 09-implement; rc=$?
check "corsie col solo JSON nel result, esito OK → .esito OK (riga ricavata dall'oggetto), gate eseguiti" '[ $rc -eq 0 ] && sed -n 1p "$L4/09-implement.esito" | grep -q "^PHASE RESULT implement: OK — corsie parallele: corsia 1: corsia 1 solo json · corsia 2: corsia 2 solo json" && [ -f "$L4/09-implement.result.json" ] && [ -f "$L4/09-implement.gates" ]'
(cd "$FIC_REPO" && git checkout -q -- .)
FAKE_JSONONLY_1=OK FAKE_JSONONLY_2=STOP FAKE_TOUCH_1=a.py FAKE_FILE_1=a.py lrun 10-implement
check "  solo JSON con esito STOP in una corsia → .esito STOP «corsia 2: <motivo>», nessun gate" 'sed -n 1p "$L4/10-implement.esito" | grep -q "^PHASE RESULT implement: STOP — corsia 2: corsia 2 solo json" && [ ! -f "$L4/10-implement.gates" ]'
(cd "$FIC_REPO" && git checkout -q -- .)
FAKE_TXTSTOP_1=1 FAKE_JSONONLY_2=OK FAKE_TOUCH_1=a.py FAKE_FILE_1=a.py lrun 11-implement
check "  riga di testo STOP e oggetto OK (discordi) → vince lo STOP del testo, nessun gate" 'sed -n 1p "$L4/11-implement.esito" | grep -q "^PHASE RESULT implement: STOP — corsia 1: testo discorde 1" && [ ! -f "$L4/11-implement.gates" ]'
(cd "$FIC_REPO" && git checkout -q -- .)
FIC_LANES=0 FAKE_JSONONLY_0=OK FAKE_TOUCH_0=a.py lrun 12-implement; rc=$?
check "  in serie lo stesso result col solo JSON → OK (VALIDA_PY ricava la riga dall'oggetto)" '[ $rc -eq 0 ] && sed -n 1p "$L4/12-implement.esito" | grep -q "^PHASE RESULT implement: OK — corsia 0 solo json" && [ -f "$L4/12-implement.gates" ]'
(cd "$FIC_REPO" && git checkout -q -- .)
# 1.3.0: lanes with the English result line, "none" and defensive deviations in both languages: the prefix stays
# at the start of the merged deviation, as written
FAKE_DEV_1='"defensive: a.py:1 — branch"' FAKE_DEV_2='"difensiva: b.py:1 — ramo"' FAKE_TOUCH_1=a.py FAKE_TOUCH_2=b.py FAKE_FILE_1=a.py FAKE_FILE_2=b.py lrun 13-implement; rc=$?
check "corsie inglesi con deviazioni «defensive: »/«difensiva: » → .esito OK, prefisso conservato nella deviazione unita, registrate" '[ $rc -eq 0 ] && sed -n 1p "$L4/13-implement.esito" | grep -q "^PHASE RESULT implement: OK — corsie parallele: corsia 1: corsia 1 · corsia 2: corsia 2" && grep -q "\"defensive: corsia 1: a.py:1 — branch\"" "$L4/13-implement.result.json" && grep -q "\"difensiva: corsia 2: b.py:1 — ramo\"" "$L4/13-implement.result.json" && grep -q "^13-implement	defensive: corsia 1: a.py:1 — branch" "$L4/deviazioni-difensive.txt"'
(cd "$FIC_REPO" && git checkout -q -- .)
# lock lifetime held by cpid2: lane 1 fast, lane 2 slow, run-phase killed => busy as long as lane 2 lives
CLAUDE_BIN="$T/claude-corsie" FAKE_OUT="$T/08-implement" FAKE_SLEEP_1=0 FAKE_SLEEP_2=8 bash "$RP" "$R4" 08-implement "$T/prompt.md" 2>/dev/null </dev/null & rp=$!
for _ in $(seq 1 80); do [ -f "$T/08-implement.corsia-1.end" ] && grep -q '^cpid2=' "$FIC_LOCK/owner" 2>/dev/null && break; sleep 0.25; done
lc1=$(sed -n 's/^cpid=//p' "$FIC_LOCK/owner" 2>/dev/null); lc2=$(sed -n 's/^cpid2=//p' "$FIC_LOCK/owner" 2>/dev/null)
sleep 1
kill -TERM $rp; wait $rp 2>/dev/null
check "corsia 1 finita, corsia 2 viva, run-phase ucciso: --lock-status occupato (solo cpid2 vivo)" '[ -n "$lc2" ] && ! kill -0 "$rp" 2>/dev/null && ! kill -0 "$lc1" 2>/dev/null && kill -0 "$lc2" 2>/dev/null && [ -d "$FIC_LOCK" ] && { bash "$RP" --lock-status >/dev/null; [ $? -eq 1 ]; }'
for _ in $(seq 1 60); do kill -0 "$lc2" 2>/dev/null || break; sleep 0.25; done; sleep 1
check "  finita la corsia 2, il lock e' orfano e si riprende" 'bash "$RP" --lock-status | grep -q "^libero"'
rm -rf "$FIC_LOCK"; (cd "$FIC_REPO" && git checkout -q -- .)

# 12. 1.5.0: MAAT_LINGUA in WSLENV. maat.json says "it", MAAT_LINGUA=en set by hand: whatever the sub-session (normal
#     and each lane) launches in `wsl` must still see "en". The fake wsl passes ONLY the variables named in WSLENV
#     (name[/flags]), like wsl.exe; the fake claude calls it, records what it saw inside, then runs the usual fake.
cat > "$T/wsl" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = -- ] && shift
[ "${1:-}" = bash ] && [ "${2:-}" = -lc ] && set -- bash -c "$3"
a=(); w=(); IFS=: read -r -a w <<< "${WSLENV:-}"
for e in ${w[@]+"${w[@]}"}; do v=${e%%/*}; [[ $v =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [ -n "${!v+x}" ] && a+=("$v=${!v}"); done
exec env -i PATH="$PATH" ${a[@]+"${a[@]}"} "$@"
EOF
cat > "$T/claude-wsl" <<'EOF'
#!/usr/bin/env bash
k=${FIC_LANE:-0}
"$FAKE_WSL" -- bash -lc 'printf "MAAT_LINGUA=%s\nFIC_LANE=%s\nWSL_FOO=%s\n" "${MAAT_LINGUA:-}" "${FIC_LANE:-}" "${WSL_FOO:-}"' > "$FAKE_OUT.wsl-$k" 2>&1
printf 'WSLENV=%s\n' "${WSLENV:-}" > "$FAKE_OUT.wslenv-$k"
exec "$FAKE_CLAUDE" "$@"
EOF
chmod +x "$T/wsl" "$T/claude-wsl"
WL="$T/wl"; mkdir -p "$WL/.claude"
printf '{"versione_schema": 1, "moduli": [{"nome": "tutto", "radice": "."}], "lingua": "it"}\n' > "$WL/.claude/maat.json"
WLC=$(cygpath -m "$WL/.claude/maat.json" 2>/dev/null || printf '%s' "$WL/.claude/maat.json")
# $1 = run-phase.sh, $2 = run dir, $3 = label, $4 = fake claude behind the wrapper; WSLENV as given by the caller
wlrun() { env -u WSLENV ${WLENV:+WSLENV="$WLENV"} MAAT_CONFIG="$WLC" MAAT_LINGUA=en CLAUDE_BIN="$T/claude-wsl" FAKE_WSL="$T/wsl" \
  FAKE_CLAUDE="$4" FAKE_OUT="$T/$3" WSL_FOO=foo bash "$1" "$2" "$3" "$T/prompt.md" 2>"$T/$3.err" </dev/null; }
WLENV="" wlrun "$RP" "$WL/a/run" w1-plan "$T/claude"; rc=$?
check "WSLENV: lingua it in maat.json, MAAT_LINGUA=en a mano → il wsl della sotto-sessione normale vede en" '[ $rc -eq 0 ] && grep -qx "MAAT_LINGUA=en" "$T/w1-plan.wsl-0" && grep -qx "WSLENV=MAAT_LINGUA" "$T/w1-plan.wslenv-0"'
WLENV="WSL_FOO/u:MAAT_LINGUA/p" wlrun "$RP" "$WL/b/run" w2-plan "$T/claude"
check "  WSLENV con MAAT_LINGUA gia' presente: nessun doppione, voci e flag conservati" 'grep -qx "WSLENV=WSL_FOO/u:MAAT_LINGUA/p" "$T/w2-plan.wslenv-0" && grep -qx "MAAT_LINGUA=en" "$T/w2-plan.wsl-0" && grep -qx "WSL_FOO=foo" "$T/w2-plan.wsl-0"'
WLENV="WSL_FOO/u" wlrun "$RP" "$WL/c/run" w3-plan "$T/claude"
check "  WSLENV con altre voci: MAAT_LINGUA in coda, le altre restano" 'grep -qx "WSLENV=WSL_FOO/u:MAAT_LINGUA" "$T/w3-plan.wslenv-0" && grep -qx "WSL_FOO=foo" "$T/w3-plan.wsl-0" && grep -qx "MAAT_LINGUA=en" "$T/w3-plan.wsl-0"'
# lanes: a fresh copy of the lanes spec (the run dir of section 11 has an Italian harness.fp)
W5="$T/w5"; mkdir -p "$W5"; cp "$SPL" "$W5/spec-l.md"
(cd "$FIC_REPO" && git checkout -q -- .)
FAKE_TOUCH_1=a.py FAKE_TOUCH_2=b.py FAKE_FILE_1=a.py FAKE_FILE_2=b.py WLENV="" wlrun "$RP" "$W5/spec-l.run" w4-implement "$T/claude-corsie"; rc=$?
check "  corsie: il wsl di ciascuna corsia vede en e FIC_LANE; WSLENV comincia ancora con FIC_LANE" '[ $rc -eq 0 ] && grep -qx "blocks-independent: esito=parallelo corsie=2" "$W5/spec-l.run/log/w4-implement.corsie" && ( for k in 1 2; do grep -qx "MAAT_LINGUA=en" "$T/w4-implement.wsl-$k" && grep -qx "FIC_LANE=$k" "$T/w4-implement.wsl-$k" && grep -qx "WSLENV=FIC_LANE:MAAT_LINGUA" "$T/w4-implement.wslenv-$k" || exit 1; done )'
rm -rf "$FIC_LOCK"; (cd "$FIC_REPO" && git checkout -q -- .)
# counterproof: copy of run-phase.sh without the wslenv_add call → inside the fake wsl the language is empty
sed 's/^wslenv_add MAAT_LINGUA$/: # MUTANTE: niente wslenv_add/' "$RP" > "$MRP"
if cmp -s "$RP" "$MRP"; then fail=$((fail + 1)); n=$((n + 1)); echo "FAIL: controprova (WSLENV): la mutazione non si applica"
else
  WLENV="" wlrun "$MRP" "$WL/d/run" w5-plan "$T/claude"
  check "controprova (WSLENV): senza wslenv_add il wsl finto vede la lingua vuota (il caso w1 sarebbe rosso)" 'grep -qx "MAAT_LINGUA=" "$T/w5-plan.wsl-0"'
fi

echo "run-phase.test.sh: $((n - fail))/$n ok"
[ $fail -eq 0 ]
