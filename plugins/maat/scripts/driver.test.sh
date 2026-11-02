#!/usr/bin/env bash
# driver.test.sh — tests of script/fic/driver.py (harness-pt14), without real claude and without touching the project:
# throwaway git repo, temporary HOME, fake run-phase.sh and context-pack.sh for the state machine.
#   bash script/fic/driver.test.sh
#   DRIVER_TEST_RAPIDO=1 bash script/fic/driver.test.sh   # skips section 9, the port of cycle-state.test.sh (~20 min)
#   DRV=/path/variant.py bash script/fic/driver.test.sh   # counterproof on a mutation (FIC_DRIVER_ROOT
#                                                              # lets the copy find the repository's scripts)
# Sections:
#   1 usage · 2 valida: cases from run-phase.test.sh 6b, compared byte by byte with `run-phase.sh --valida`
#   3 wrappers: cycle-state.sh and run-phase.sh call the driver only with the certificate (or FIC_DRIVER=1)
#   4 run: the state machine (anti-loop, ESITO STOP, run-phase exits 4/6/7, NEEDS_VERIFICATION, invalid
#     result.json, phase running, budget, dry-run, forwarded flags, context-pack, progress up to DONE)
#   5 equiv and certificate · 6 plan counterproofs: anti-loop removed, JSON validation removed
#   7 batches and lanes decided by the driver (step 5) · 8 lines loaded per phase (step 4, cap on the base load)
#   9 port of cycle-state.test.sh: every call compares the whole output of cycle-state.sh (standalone) and of
#     `driver.py next`; the cases must pass AND the two outputs must match
#  10 L2 promotion before the review: assorbita only if it holds finalize's check (plan-check.sh l2)
#  11 (1.4.0) a whole cycle through the real run-phase.sh, in English and in Italian: the same phases, the same end
set -uo pipefail
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)   # plugin root
FC=$ROOT/scripts
DRV=${DRV:-$HERE/driver.py}
. "$FC/python.sh" || { echo "driver.test.sh: nessun interprete Python (FIC_PYTHON)"; exit 2; }
export FIC_DRIVER_ROOT=$ROOT
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
cp "$HERE/maat_paths.py" "$T/"   # the mutated drivers written in $T import maat_paths from next to themselves (pk04a-1)
# 1.4.0: and maat_msg.py, which reads the catalog next to itself (lib/messages.tsv): a copy uses its own catalog
cp "$HERE/maat_msg.py" "$T/"; mkdir -p "$T/lib"; cp "$HERE/lib/messages.tsv" "$HERE/lib/maat-msg.sh" "$T/lib/"
export HOME="$T/home"; mkdir -p "$HOME"
unset FIC_DRIVER FIC_DRIVER_PY FIC_DRIVER_CERT FIC_RUN_PHASE FIC_CONTEXT_PACK FIC_MAX_FASI FIC_REPO FIC_LOCK
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi; }
drv() { "$FIC_PY" "$DRV" "$@"; }

# --- 1. usage ---
drv >/dev/null 2>&1; rc=$?; check "senza comando → 2" '[ $rc -eq 2 ]'
drv next "$T/non-esiste.md" >/dev/null 2>&1; rc=$?; check "next su una spec assente → 2" '[ $rc -eq 2 ]'
drv run >/dev/null 2>&1; rc=$?; check "run senza spec → 2" '[ $rc -eq 2 ]'
drv valida a b >/dev/null 2>&1; rc=$?; check "valida con argomenti sbagliati → 2" '[ $rc -eq 2 ]'

# --- 2. valida: same cases and same bytes as the internal validator of run-phase.sh ---
SCHEMA=$ROOT/schemas/phase-result.schema.json
ok_json() { # $1 phase, $2 esito, $3 deviazioni, $4 bloccato_su
  printf '{"fase":"%s","esito":"%s","motivo":"finto","deviazioni":%s,"bloccato_su":"%s","file":[],"gate_interni":[],"finding":[]}' "$1" "$2" "$3" "$4"
}
V=$T/valida; mkdir -p "$V"
vcase() { # $1 name, $2 phase, $3 log content · prints the driver output to $V/$1.out
  printf '%s\n' "$3" > "$V/$1.jsonl"
  rm -f "$V/$1.a.json" "$V/$1.b.json"
  FIC_DRIVER=0 bash "$FC/run-phase.sh" --valida "$V/$1.jsonl" "$SCHEMA" "$2" "$V/$1.a.json" > "$V/$1.a" 2> "$V/$1.a.err"
  drv valida "$V/$1.jsonl" "$SCHEMA" "$2" "$V/$1.b.json" > "$V/$1.out" 2> "$V/$1.b.err"
  local same=1
  cmp -s <(tr -d '\r' < "$V/$1.a") <(tr -d '\r' < "$V/$1.out") || same=0
  cmp -s <(tr -d '\r' < "$V/$1.a.err") <(tr -d '\r' < "$V/$1.b.err") || same=0
  if [ -f "$V/$1.a.json" ] || [ -f "$V/$1.b.json" ]; then cmp -s "$V/$1.a.json" "$V/$1.b.json" || same=0; fi
  check "valida [$1]: uguale a run-phase.sh --valida (stdout, stderr, result.json)" '[ $same -eq 1 ]'
}
vcase valido implement '{"type":"result","result":"lavoro\nESITO FASE x: OK — finto","structured_output":'"$(ok_json implement OK '[]' nessuno)"'}'
check "  valido: la riga ESITO del testo e result.json scritto" 'grep -qx "ESITO FASE x: OK — finto" "$V/valido.out" && [ -f "$V/valido.b.json" ]'
vcase senza implement '{"type":"result","result":"ESITO FASE implement: OK — fatto"}'
check "  JSON assente → STOP «uscita non valida» (scritta come PHASE RESULT) con originale= (la riga italiana letta)" 'sed -n 1p "$V/senza.out" | grep -q "^PHASE RESULT implement: STOP — uscita non valida: nessun blocco JSON" && grep -qx "originale=ESITO FASE implement: OK — fatto" "$V/senza.out"'
vcase fuori implement '{"type":"result","result":"ESITO FASE implement: OK","structured_output":{"fase":"implement","esito":"FORSE","motivo":"m","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[],"extra":1}}'
# Errors in any order and format: minimal validator ("$.esito … FORSE", "extra") or jsonschema ("'extra' was
# unexpected; 'FORSE' is not one of …"), depending on whether the interpreter has jsonschema.
check "  JSON fuori schema → STOP con gli errori, niente result.json" 'l=$(sed -n 1p "$V/fuori.out"); case "$l" in "PHASE RESULT implement: STOP — uscita non valida: "*) e=${l#"PHASE RESULT implement: STOP — uscita non valida: "}; case "$e" in *FORSE*) ;; *) false ;; esac && case "$e" in *extra*) ;; *) false ;; esac ;; *) false ;; esac && [ ! -f "$V/fuori.b.json" ]'
vcase altra implement '{"type":"result","result":"ESITO FASE implement: OK","structured_output":'"$(ok_json review OK '[]' nessuno)"'}'
check "  JSON di un'altra fase → STOP" 'grep -q "uscita non valida: fase .review. diversa" "$V/altra.out"'
vcase dev implement '{"type":"result","result":"ESITO FASE implement: OK — fatto","structured_output":'"$(ok_json implement OK '["passo 8 adattato"]' nessuno)"'}'
check "  prosa OK ma deviazioni nel JSON → STOP (il piu conservativo)" 'grep -q "^PHASE RESULT implement: STOP — JSON: deviazioni dichiarate (1): passo 8 adattato" "$V/dev.out" && grep -qx "originale=ESITO FASE implement: OK — fatto" "$V/dev.out"'
vcase difensive implement '{"type":"result","result":"ESITO FASE implement: OK — fatto","structured_output":'"$(ok_json implement OK '["difensiva: a.py:3 — ramo per un caso escluso dal CHECK"]' nessuno)"'}'
check "  solo deviazioni «difensiva: » → resta OK (nessuno STOP per deviazione)" '[ "$(tr -d "\r" < "$V/difensive.out")" = "ESITO FASE implement: OK — fatto" ]'
vcase miste implement '{"type":"result","result":"ESITO FASE implement: OK — fatto","structured_output":'"$(ok_json implement OK '["difensiva: a.py:3 — ramo", "passo 8 adattato"]' nessuno)"'}'
check "  una difensiva e una no → STOP, tutte elencate" 'grep -q "^PHASE RESULT implement: STOP — JSON: deviazioni dichiarate (2): difensiva: a.py:3 — ramo; passo 8 adattato" "$V/miste.out"'
vcase scartato review "$(printf '%s\n' '{"type":"result","result":"ESITO FASE review: OK","structured_output":'"$(ok_json review OK '[]' nessuno)"'}' '{"type":"system","subtype":"fic_scartato"}')"
check "  evento fic_scartato dopo il result → nessun esito" '[ ! -s "$V/scartato.out" ]'
vcase errore implement '{"type":"result","is_error":true,"result":"ESITO FASE implement: OK"}'
check "  is_error → nessun esito" '[ ! -s "$V/errore.out" ]'
vcase recinto fix '{"type":"result","result":"testo\n```json\n'"$(ok_json fix OK '[]' nessuno | sed 's/"/\\"/g')"'\n```\nESITO FASE fix: OK — da recinto"}'
check "  JSON nel recinto json del testo → valido" 'grep -qx "ESITO FASE fix: OK — da recinto" "$V/recinto.out" && [ -f "$V/recinto.b.json" ]'
vcase rotto fix '{"type":"result","result":"```json\n{rotto\n```\nESITO FASE fix: OK"}'
check "  recinto illeggibile → STOP" 'grep -q "uscita non valida: blocco JSON illeggibile" "$V/rotto.out"'
vcase noriga plan '{"type":"result","result":"niente riga","structured_output":'"$(ok_json plan STOP '[]' "migrazione da applicare")"'}'
check "  senza riga ESITO: la compone dal JSON (bloccato_su), in inglese" 'grep -qx "PHASE RESULT plan: STOP — bloccato su: migrazione da applicare" "$V/noriga.out"'
# 1.3.0: the English forms written by the agents (PHASE RESULT, "defensive: ", "none"), read by both validators
vcase valido_en implement '{"type":"result","result":"work\nPHASE RESULT implement: OK — done","structured_output":'"$(ok_json implement OK '[]' none)"'}'
check "  riga «PHASE RESULT … OK» e bloccato_su «none» → la riga del testo, result.json scritto" 'grep -qx "PHASE RESULT implement: OK — done" "$V/valido_en.out" && [ -f "$V/valido_en.b.json" ]'
vcase dev_en implement '{"type":"result","result":"PHASE RESULT implement: OK — done","structured_output":'"$(ok_json implement OK '["step 8 adapted"]' none)"'}'
check "  prosa inglese OK ma deviazioni → STOP, prosa sotto originale=" 'grep -q "^PHASE RESULT implement: STOP — JSON: deviazioni dichiarate (1): step 8 adapted" "$V/dev_en.out" && grep -qx "originale=PHASE RESULT implement: OK — done" "$V/dev_en.out"'
vcase difensive_en implement '{"type":"result","result":"PHASE RESULT implement: OK — done","structured_output":'"$(ok_json implement OK '["defensive: a.py:3 — branch", "difensiva: b.py:1 — ramo"]' none)"'}'
check "  deviazioni tutte «defensive: »/«difensiva: » → resta OK" '[ "$(tr -d "\r" < "$V/difensive_en.out")" = "PHASE RESULT implement: OK — done" ]'
vcase bloccato_en implement '{"type":"result","result":"PHASE RESULT implement: OK — done","structured_output":'"$(ok_json implement OK '[]' "migration to apply")"'}'
check "  bloccato_su diverso da «none» → STOP" 'grep -q "^PHASE RESULT implement: STOP — JSON: bloccato su: migration to apply" "$V/bloccato_en.out"'

# --- throwaway repo for wrappers, run and equiv ---
W=$T/repo; mkdir -p "$W"; cd "$W" || exit 2
git init -q .; git config user.email t@t; git config user.name t; git config core.autocrlf false
mkdir -p src .claude/.ai-workflow; printf 'spec-*\n' > .claude/.ai-workflow/.gitignore
printf 'uno\n' > src/a.py; git add -A; git commit -qm init
SP=.claude/.ai-workflow/spec-x.md; RUN=.claude/.ai-workflow/spec-x.run
PC=$ROOT/scripts/plan-check.sh
spec_approved() {
  printf '%s\n' "# X" "## Contesto" "Contesto." "## Requisiti funzionali" "1. Fare A." "## Piano di implementazione" \
    "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" "### Passi" "1. Modificare \`src/a.py\`." \
    "### Changelog revisione piano" "- giro 1: ok" > "$SP"
  local cur; cur=$(bash "$PC" basis "$SP" | sed -n 's/^Basis: //p')
  sed -i "s/^Superfici a rischio: .*/&\nApproved basis: $cur/" "$SP"
}
spec_approved

# --- 3. wrappers ---
cat > "$T/finto-drv.py" <<'EOF'
import os, sys
open(os.environ["SPY"], "a").write(" ".join(sys.argv[1:2]) + "\n")
if os.environ.get("FINTO_ESCE"):
    sys.exit(int(os.environ["FINTO_ESCE"]))
sys.stdout.buffer.write("Plan status: finto\nState: 000000000000\nNext: FINTO — dal driver\n".encode("utf-8"))
EOF
export SPY=$T/spy
out=$(FIC_DRIVER=1 FIC_DRIVER_PY="$T/finto-drv.py" bash "$FC/cycle-state.sh" "$SP" 2>/dev/null)
check "cycle-state.sh, FIC_DRIVER=1 → risponde il driver" 'printf "%s\n" "$out" | grep -qx "Next: FINTO — dal driver"'
rm -f "$SPY"; out=$(FIC_DRIVER=0 FIC_DRIVER_PY="$T/finto-drv.py" bash "$FC/cycle-state.sh" "$SP" 2>/dev/null)
check "cycle-state.sh, FIC_DRIVER=0 → autonomo, il driver non e' chiamato" 'printf "%s\n" "$out" | grep -q "^Next: IMPLEMENT" && [ ! -f "$SPY" ]'
h() { tr -d '\r' < "$1" | sha256sum | cut -c1-64; }
msgh() { printf 'messages %s\nmaat-msg %s\nmaat_msg %s\n' "$(h "$FC/lib/messages.tsv")" "$(h "$FC/lib/maat-msg.sh")" "$(h "$FC/maat_msg.py")"; }
{ printf 'driver %s\ncycle-state %s\nrun-phase %s\n' "$(h "$T/finto-drv.py")" "$(h "$FC/cycle-state.sh")" "$(h "$FC/run-phase.sh")"; msgh; } > "$T/cert-ok"
printf 'driver %s\ncycle-state %s\n' "$(h "$T/finto-drv.py")" 0000 > "$T/cert-ko"
out=$(FIC_DRIVER_CERT="$T/cert-ok" FIC_DRIVER_PY="$T/finto-drv.py" bash "$FC/cycle-state.sh" "$SP" 2>/dev/null)
check "cycle-state.sh col certificato valido → il driver" 'printf "%s\n" "$out" | grep -qx "Next: FINTO — dal driver"'
out=$(FIC_DRIVER_CERT="$T/cert-ko" FIC_DRIVER_PY="$T/finto-drv.py" bash "$FC/cycle-state.sh" "$SP" 2>/dev/null)
check "  certificato con un altro hash di cycle-state.sh → autonomo" 'printf "%s\n" "$out" | grep -q "^Next: IMPLEMENT"'
out=$(FIC_DRIVER_CERT="$T/non-esiste" FIC_DRIVER_PY="$T/finto-drv.py" bash "$FC/cycle-state.sh" "$SP" 2>/dev/null)
check "  nessun certificato → autonomo" 'printf "%s\n" "$out" | grep -q "^Next: IMPLEMENT"'
grep -v '^maat_msg ' "$T/cert-ok" > "$T/cert-nomsg"; echo "maat_msg 0000" >> "$T/cert-nomsg"
out=$(FIC_DRIVER_CERT="$T/cert-nomsg" FIC_DRIVER_PY="$T/finto-drv.py" bash "$FC/cycle-state.sh" "$SP" 2>/dev/null)
check "  1.4.0: certificato con un altro hash di maat_msg.py → autonomo" 'printf "%s\n" "$out" | grep -q "^Next: IMPLEMENT"'
out=$(FINTO_ESCE=1 FIC_DRIVER=1 FIC_DRIVER_PY="$T/finto-drv.py" bash "$FC/cycle-state.sh" "$SP" 2>"$T/cs.err")
check "  driver fallito → autonomo, con AVVISO" 'printf "%s\n" "$out" | grep -q "^Next: IMPLEMENT" && grep -q "AVVISO: driver.py next non riuscito" "$T/cs.err"'
# run-phase.sh: outcome validation goes through the driver only when it delegates (spy on a real phase, fake claude)
cat > "$T/spia-drv.py" <<EOF
import os, runpy, sys
open(os.environ["SPY"], "a").write("valida\n")
sys.argv = [r"$(cygpath -w "$DRV" 2>/dev/null || echo "$DRV")"] + sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
EOF
cat > "$T/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo '{"type":"result","result":"ESITO FASE implement: OK — finto","structured_output":{"fase":"implement","esito":"FORSE","motivo":"m","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}'
EOF
chmod +x "$T/claude"
printf '#!/usr/bin/env bash\necho "gates: esito=PASS chiave=k0 evidence=-"\n' > "$T/gates"; chmod +x "$T/gates"
echo "/maat:full-implementation-cycle --worker=implement x" > "$T/prompt.md"
rp() { # $1 = FIC_DRIVER, $2 = label
  rm -f "$SPY"
  FIC_DRIVER=$1 FIC_DRIVER_PY="$T/spia-drv.py" FIC_LOCK="$T/lock" FIC_REPO="$W" CLAUDE_BIN="$T/claude" FIC_GATES="$T/gates" \
    FIC_FINALIZE="$T/non-esiste" FIC_LANES=0 bash "$FC/run-phase.sh" "$T/rp.run" "$2" "$T/prompt.md" >/dev/null 2>&1 </dev/null
}
rp 1 01-implement
check "run-phase.sh, FIC_DRIVER=1: esito validato dal driver (spia) → STOP «uscita non valida»" 'grep -qx valida "$SPY" && sed -n 1p "$T/rp.run/log/01-implement.esito" | grep -q "^PHASE RESULT implement: STOP — uscita non valida: .*FORSE"'
rp 0 02-implement
check "run-phase.sh, FIC_DRIVER=0: validatore interno (spia muta), stesso esito" '[ ! -f "$SPY" ] && [ "$(sed -n 1p "$T/rp.run/log/01-implement.esito")" = "$(sed -n 1p "$T/rp.run/log/02-implement.esito")" ]'
{ printf 'driver %s\nrun-phase %s\n' "$(h "$T/spia-drv.py")" "$(h "$FC/run-phase.sh")"; msgh; } > "$T/cert-rp-ok"
printf 'driver %s\nrun-phase %s\n' "$(h "$T/spia-drv.py")" 0000 > "$T/cert-rp-ko"
rpc() { # $1 = certificate, $2 = label (FIC_DRIVER not set: the certificate decides)
  rm -f "$SPY"
  FIC_DRIVER_CERT="$1" FIC_DRIVER_PY="$T/spia-drv.py" FIC_LOCK="$T/lock" FIC_REPO="$W" CLAUDE_BIN="$T/claude" FIC_GATES="$T/gates" \
    FIC_FINALIZE="$T/non-esiste" FIC_LANES=0 bash "$FC/run-phase.sh" "$T/rp.run" "$2" "$T/prompt.md" >/dev/null 2>&1 </dev/null
}
rpc "$T/cert-rp-ok" 03-implement
check "run-phase.sh col certificato valido per il suo hash → valida il driver (spia)" 'grep -qx valida "$SPY" && sed -n 1p "$T/rp.run/log/03-implement.esito" | grep -q "uscita non valida"'
rpc "$T/cert-rp-ko" 04-implement
check "  certificato con un altro hash di run-phase.sh → validatore interno (spia muta)" '[ ! -f "$SPY" ] && sed -n 1p "$T/rp.run/log/04-implement.esito" | grep -q "uscita non valida"'
rpc "$T/non-esiste" 05-implement
check "  nessun certificato → validatore interno" '[ ! -f "$SPY" ] && sed -n 1p "$T/rp.run/log/05-implement.esito" | grep -q "uscita non valida"'

# --- 4. run: the state machine, with fake run-phase.sh and context-pack.sh ---
cat > "$T/rp-finto" <<'EOF'
#!/usr/bin/env bash
# fake run-phase.sh: <run-dir> <label> <prompt>; FAKE_MODE chooses what the "phase" does
d=$1 l=$2; mkdir -p "$d/log"; echo "$l" >> "$FAKE_CALLS"; spec="${d%.run}.md"
st() { FIC_DRIVER=0 bash "$FC/cycle-state.sh" "$spec" 2>/dev/null | sed -n 's/^State: //p'; }
case "$FAKE_MODE" in
  nulla) exit 0 ;;
  esito-stop) printf 'ESITO FASE implement: STOP — migrazione da applicare\nstate=x\n' > "$d/log/$l.esito"; exit 0 ;;
  esito-stop-en) printf 'PHASE RESULT implement: STOP — migration to apply\nstate=x\n' > "$d/log/$l.esito"; exit 0 ;;
  exit4) echo "lock occupato: un'altra fase di codice e' in corso — run=altro" > "$d/log/$l.stderr"; exit 4 ;;
  exit6) echo "STOP: harness cambiato dal 2026-09-30T00:00:00Z" > "$d/log/$l.stderr"; exit 6 ;;
  exit7) echo "WAIT — catena: l'implement dell'anello 2 aspetta l'anello 1 — fase non lanciata" > "$d/log/$l.stderr"; exit 7 ;;
  json-rotto) : > "$d/log/$l.jsonl"; echo x > "$d/log/$l.pre-tree"; echo y > "$d/log/$l.post-tree"
    printf '{"fase":"implement","esito":"FORSE"}\n' > "$d/log/$l.result.json"
    printf 'ESITO FASE implement: OK — fatto\nstate=%s\n' "$(st)" > "$d/log/$l.esito"; exit 0 ;;
  avanza|nv|nv-ver|nv-vuoto|nv-en)
    case "$l" in
      *implement*) : > "$d/log/$l.jsonl"; echo x > "$d/log/$l.pre-tree"; echo y > "$d/log/$l.post-tree"
        printf 'ESITO FASE implement: OK — fatto\nstate=%s\n' "$(st)" > "$d/log/$l.esito" ;;
      *review*) : > "$d/log/$l.jsonl"
        fs=IMPLEMENTED; case "$FAKE_MODE" in nv*) fs=NEEDS_VERIFICATION ;; esac
        printf '%s\n' "## Review implementazione" "Review status: APPROVED" "Feature status: $fs" >> "$spec"
        [ "$FAKE_MODE" = nv ] && printf '%s\n' "Finalize: NEEDS_VERIFICATION — snapshot 0123456789ab — tests-x: NOT RUN (dichiarato: nessun test) — nessun test nel modulo x, controlli verdi · 2026-10-29T10:00:00Z" \
          "Verification: PARTIAL (finalize.sh: tests-x: NOT RUN (dichiarato: nessun test) — nessun test nel modulo x, controlli verdi)" >> "$spec"
        # pk09: only the Verification: PARTIAL line (no Finalize:), or neither of the two
        [ "$FAKE_MODE" = nv-ver ] && printf '%s\n' "Verification: PARTIAL (finalize.sh: tests-y: NOT RUN (solo la riga Verification))" >> "$spec"
        # 1.4.0: the lines as finalize.sh writes them in English (the detail follows the language, the prefixes not)
        [ "$FAKE_MODE" = nv-en ] && printf '%s\n' "Finalize: NEEDS_VERIFICATION — snapshot 0123456789ab — tests-x: NOT RUN (declared: no test) — no test in module x, checks green · 2026-10-29T10:00:00Z" \
          "Verification: PARTIAL (finalize.sh: tests-x: NOT RUN (declared: no test) — no test in module x, checks green)" >> "$spec"
        printf 'ESITO FASE review: OK — finta\nstate=%s\n' "$(st)" > "$d/log/$l.esito" ;;
    esac; exit 0 ;;
esac
exit 0
EOF
chmod +x "$T/rp-finto"
printf '#!/usr/bin/env bash\necho "$@" >> "$FAKE_CALLS.cp"\necho "context-pack: invariato"\n' > "$T/cp-finto"; chmod +x "$T/cp-finto"
export FC FAKE_CALLS=$T/calls
drun() { # $1 FAKE_MODE, then the run arguments · exit code in rc, output in $T/run.out
  rm -rf "$RUN" "$FAKE_CALLS" "$FAKE_CALLS.cp"; spec_approved
  FAKE_MODE=$1 FIC_RUN_PHASE="$T/rp-finto" FIC_CONTEXT_PACK="$T/cp-finto" "$FIC_PY" "${DRUN_DRV:-$DRV}" run "${@:2}" > "$T/run.out" 2>&1
  rc=$?
}
calls() { local c; c=$(grep -c . "$FAKE_CALLS" 2>/dev/null); echo "${c:-0}"; }
drun nulla "$SP"
check "run: fase che non cambia lo stato → STOP anti-loop (exit 1) dopo UN lancio" '[ $rc -eq 1 ] && grep -q "Driver result: STOP — anti-loop" "$T/run.out" && [ "$(calls)" = 1 ]'
check "  etichetta 01-implement e prompt della fase" '[ "$(cat "$FAKE_CALLS")" = 01-implement ] && [ "$(cat "$RUN/prompts/01-implement.md")" = "/maat:full-implementation-cycle --worker=implement x" ]'
check "  context-pack.sh lanciato prima della fase, sulla spec" 'grep -q "spec-x.md" "$FAKE_CALLS.cp"'
check "  eventi anche in <run-dir>/driver.log" 'grep -q "▶ 01-implement avviata" "$RUN/driver.log" && grep -q "Driver result: STOP" "$RUN/driver.log"'
drun esito-stop "$SP"
check "run: ESITO FASE … STOP → STOP con quella riga" '[ $rc -eq 1 ] && grep -q "Driver result: STOP — ESITO FASE implement: STOP — migrazione da applicare" "$T/run.out"'
drun esito-stop-en "$SP"
check "run: «PHASE RESULT … STOP» (1.3.0) → STOP con quella riga" '[ $rc -eq 1 ] && grep -q "Driver result: STOP — PHASE RESULT implement: STOP — migration to apply" "$T/run.out"'
drun exit4 "$SP"
check "run: run-phase exit 4 (lock) → BUSY, exit 4" '[ $rc -eq 4 ] && grep -q "Driver result: BUSY — .*lock occupato" "$T/run.out"'
drun exit6 "$SP"
check "run: run-phase exit 6 (harness) → STOP" '[ $rc -eq 1 ] && grep -q "run-phase exit 6 (harness cambiato" "$T/run.out"'
drun exit7 "$SP"
check "run: run-phase exit 7 con WAIT — catena → WAIT, exit 3" '[ $rc -eq 3 ] && grep -q "Driver result: WAIT — .*WAIT — catena" "$T/run.out"'
drun json-rotto "$SP"
check "run: result.json non valido dopo la fase → STOP (fail-closed)" '[ $rc -eq 1 ] && grep -q "result.json di 01-implement non valido" "$T/run.out"'
drun avanza "$SP"
check "run: implement OK → review → DONE (exit 0), etichette in ordine" '[ $rc -eq 0 ] && grep -q "Driver result: DONE" "$T/run.out" && [ "$(tr "\n" " " < "$FAKE_CALLS")" = "01-implement 02-review " ]'
check "  prompt della review" '[ "$(cat "$RUN/prompts/02-review.md")" = "/maat:full-implementation-cycle --worker=review x" ]'
caso_nv() { # pk09: the reason says cycle finished and what to verify (from the Finalize: line, without the final time « · …Z»)
  drun nv "$SP"
  [ $rc -eq 1 ] && grep -qF "Driver result: STOP — ciclo finito: firma NEEDS_VERIFICATION — da verificare: tests-x: NOT RUN (dichiarato: nessun test) — nessun test nel modulo x, controlli verdi; la promozione" "$T/run.out" && [ "$(calls)" = 2 ]
}
check "run: review che da' NEEDS_VERIFICATION in questa invocazione → STOP (exit 1), il motivo dice ciclo finito e cosa verificare" 'caso_nv'
check "  l'ora finale della riga Finalize: (« · 2026-10-29T10:00:00Z») non entra nel motivo" '! grep -q "2026-10-29T10:00:00Z" "$T/run.out"'
drun nv-ver "$SP"
check "  solo la riga Verification: PARTIAL (nessuna Finalize:) → il dettaglio viene da lì" '[ $rc -eq 1 ] && grep -qF "Driver result: STOP — ciclo finito: firma NEEDS_VERIFICATION — da verificare: tests-y: NOT RUN (solo la riga Verification); la promozione" "$T/run.out"'
drun nv-vuoto "$SP"
check "  nessuna delle due righe → «dettaglio non trovato», sempre STOP (exit 1)" '[ $rc -eq 1 ] && grep -qF "Driver result: STOP — ciclo finito: firma NEEDS_VERIFICATION — da verificare: dettaglio non trovato nella spec (righe Finalize:/Verification:)" "$T/run.out"'
export MAAT_LINGUA=en; drun nv-en "$SP"; export MAAT_LINGUA=it
check "  1.4.0: le righe Finalize:/Verification: scritte in inglese, lette in inglese → lo stesso STOP col dettaglio" '[ $rc -eq 1 ] && grep -qF "Driver result: STOP — cycle finished: signature NEEDS_VERIFICATION — to verify: tests-x: NOT RUN (declared: no test) — no test in module x, checks green; the promotion" "$T/run.out" && [ "$(calls)" = 2 ]'
drun nv-en "$SP"
check "  e lette in italiano: lo stesso dettaglio" '[ $rc -eq 1 ] && grep -qF "Driver result: STOP — ciclo finito: firma NEEDS_VERIFICATION — da verificare: tests-x: NOT RUN (declared: no test) — no test in module x, checks green; la promozione" "$T/run.out"'
# counterproof (pk09, on a copy): the old reason «riprovare ora troverebbe…» turns the case above red. 1.4.0: the
# text is in the catalog, so the mutation is made on the catalog of a copy (driver.py + maat_msg.py + lib/messages.tsv)
NVD="$T/nv-vecchio"; mkdir -p "$NVD/lib"; cp "$DRV" "$NVD/driver.py"; cp "$HERE/maat_paths.py" "$HERE/maat_msg.py" "$NVD/"
sed 's/\tciclo finito: firma NEEDS_VERIFICATION — da verificare: {what}; /\tla review di questa invocazione ha dato NEEDS_VERIFICATION: riprovare ora troverebbe lo stesso ambiente bloccato ({what}); /' "$HERE/lib/messages.tsv" > "$NVD/lib/messages.tsv"
check "controprova NEEDS_VERIFICATION: la mutazione e' applicata" 'grep -q "riprovare ora troverebbe" "$NVD/lib/messages.tsv"'
check "controprova NEEDS_VERIFICATION: col vecchio motivo «riprovare ora» il caso diventa rosso" '! DRUN_DRV="$NVD/driver.py" caso_nv && grep -q "riprovare ora troverebbe" "$T/run.out"'
drun nulla "$SP" --max-fasi 0
check "run: budget di fasi esaurito → STOP senza lanci" '[ $rc -eq 1 ] && grep -q "budget del driver esaurito" "$T/run.out" && [ "$(calls)" = 0 ]'
drun nulla "$SP" --dry-run
check "run --dry-run: dice cosa lancerebbe, non lancia" '[ $rc -eq 0 ] && grep -q "DRY-RUN — lancerei 01-implement" "$T/run.out" && [ "$(calls)" = 0 ]'
drun esito-stop "$SP" -- --tests=std
check "run: i flag dopo -- arrivano nel prompt" '[ "$(cat "$RUN/prompts/01-implement.md")" = "/maat:full-implementation-cycle --worker=implement x --tests=std" ]'
rm -rf "$RUN"; spec_approved; mkdir -p "$RUN/log"; date > "$RUN/log/01-plan.running"; : > "$FAKE_CALLS"
FAKE_MODE=nulla FIC_RUN_PHASE="$T/rp-finto" FIC_CONTEXT_PACK="$T/cp-finto" "$FIC_PY" "$DRV" run "$SP" > "$T/run.out" 2>&1; rc=$?
check "run: fase in corso (.running senza .exit) → exit 4, niente lanci" '[ $rc -eq 4 ] && grep -q "Driver result: RUNNING — " "$T/run.out" && [ "$(calls)" = 0 ]'
rm -rf "$RUN"; spec_approved; printf '%s\n' "## Review implementazione" "Review status: APPROVED" "Feature status: IMPLEMENTED" >> "$SP"; : > "$FAKE_CALLS"
FAKE_MODE=nulla FIC_RUN_PHASE="$T/rp-finto" FIC_CONTEXT_PACK="$T/cp-finto" "$FIC_PY" "$DRV" run "$SP" > "$T/run.out" 2>&1; rc=$?
check "run: spec gia' DONE → exit 0 senza lanci" '[ $rc -eq 0 ] && grep -q "Driver result: DONE" "$T/run.out" && [ "$(calls)" = 0 ]'
# M1: without a valid certificate Next/State come from standalone cycle-state.sh (here a fake one that answers differently)
printf '#!/usr/bin/env bash\necho "Plan status: finto"; echo "State: 000000000000"; echo "Next: STOP — finto da cycle-state"\n' > "$T/cs-finto"; chmod +x "$T/cs-finto"
rm -rf "$RUN"; spec_approved; : > "$FAKE_CALLS"
FIC_DRIVER_CERT="$T/cert-ko" FIC_CYCLE_STATE="$T/cs-finto" FAKE_MODE=nulla FIC_RUN_PHASE="$T/rp-finto" FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$SP" > "$T/run.out" 2>&1; rc=$?
check "run: certificato scaduto → segue cycle-state.sh (il finto dice STOP), evento nel log" '[ $rc -eq 1 ] && grep -q "Driver result: STOP — STOP — finto da cycle-state" "$T/run.out" && grep -q "certificato scaduto: next da cycle-state.sh" "$RUN/driver.log" && [ "$(calls)" = 0 ]'
rm -rf "$RUN"; spec_approved; : > "$FAKE_CALLS"
FIC_DRIVER=1 FIC_CYCLE_STATE="$T/cs-finto" FAKE_MODE=nulla FIC_RUN_PHASE="$T/rp-finto" FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$SP" > "$T/run.out" 2>&1; rc=$?
check "  controprova: col driver in vigore (FIC_DRIVER=1) il finto non e' consultato" 'grep -q "Next: IMPLEMENT" "$T/run.out" && ! grep -q "finto da cycle-state\|certificato scaduto" "$T/run.out"'
# M2: the chain — WAIT on the mother → the named ring; DONE of a ring → the mother → the next ring
CW=.claude/.ai-workflow
mk_catena() {
  rm -rf $CW/spec-m*.run
  printf '%s\n' "# M" "Figlie: spec-m-1-a, spec-m-2-b" "## Requisiti funzionali" "1. RF1 — a" "2. RF2 — b" > $CW/spec-m.md
  printf '%s\n' "# Anello" "Dipende da: x" "Interfaccia per: nessuna" "## Requisiti funzionali" "1. RF1 — a" "## Piano di implementazione" \
    "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" "### Passi" "1. Modificare \`src/a.py\`." > $CW/spec-m-1-a.md
  local cur; cur=$(bash "$PC" basis $CW/spec-m-1-a.md | sed -n 's/^Basis: //p')
  sed -i "s/^Superfici a rischio: .*/&\nApproved basis: $cur/" $CW/spec-m-1-a.md
  printf '%s\n' "# Anello 2" "Dipende da: spec-m-1-a" "Interfaccia per: nessuna" > $CW/spec-m-2-b.md
}
crun() { : > "$FAKE_CALLS"; FAKE_MODE=nulla FIC_DRIVER=1 FIC_RUN_PHASE="$T/rp-finto" FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$1" > "$T/run.out" 2>&1; rc=$?; }
mk_catena; crun $CW/spec-m.md
check "catena: la madre in WAIT sull'anello 1 → il driver lavora sull'anello 1 (01-implement nella sua run dir)" '[ "$(cat "$FAKE_CALLS")" = 01-implement ] && [ "$(cat $CW/spec-m-1-a.run/prompts/01-implement.md)" = "/maat:full-implementation-cycle --worker=implement m-1-a" ] && grep -q "catena: WAIT — passo a spec-m-1-a" $CW/spec-m.run/driver.log && grep -q "Driver result: STOP — anti-loop" "$T/run.out"'
mk_catena; export MAAT_LINGUA=en; crun $CW/spec-m.md; export MAAT_LINGUA=it
check "  1.4.0 (e): in inglese il WAIT conserva (spec-…) e il driver passa all'anello" '[ "$(cat "$FAKE_CALLS")" = 01-implement ] && grep -q "Next: WAIT — catena: ring 1/2 (spec-m-1-a) not closed" "$T/run.out" && grep -q "chain: WAIT — moving to spec-m-1-a" $CW/spec-m.run/driver.log'
mk_catena
EFP=$(printf '' | sha256sum | cut -c1-12)
printf '%s\n' "## Review implementazione" "Review status: APPROVED" "Feature status: IMPLEMENTED" \
  "Finalize: IMPLEMENTED — snapshot $EFP — firmato · $(date -u +%Y-%m-%dT%H:%M:%SZ)" "Verification: VERIFIED" \
  "Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1" >> $CW/spec-m-1-a.md
crun $CW/spec-m-1-a.md
check "catena: anello 1 DONE → la madre → WAIT sull'anello 2 → il suo piano (01-plan nella sua run dir)" '[ "$(cat "$FAKE_CALLS")" = 01-plan ] && [ "$(cat $CW/spec-m-2-b.run/prompts/01-plan.md)" = "/maat:full-implementation-cycle --worker=plan m-2-b" ] && grep -q "catena: DONE — passo a spec-m" $CW/spec-m-1-a.run/driver.log && grep -q "catena: WAIT — passo a spec-m-2-b" $CW/spec-m.run/driver.log'
rm -rf $CW/spec-m*.run $CW/spec-m.md $CW/spec-m-1-a.md $CW/spec-m-2-b.md

# --- 5. equiv and certificate ---
rm -rf "$RUN"; spec_approved; mkdir -p "$RUN/log"
printf '%s\n' '{"type":"result","result":"ESITO FASE implement: OK","structured_output":{"fase":"implement","esito":"OK","motivo":"m","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}' > "$RUN/log/01-implement.jsonl"
printf '%s\n' '{"type":"result","result":"ESITO FASE review: OK"}' > "$RUN/log/02-review.jsonl"
cp "$SP" .claude/.ai-workflow/spec-y.md; mkdir -p .claude/.ai-workflow/spec-y.run
# 1.3.0: a spec with BOTH review headings (the same STOP from cycle-state.sh and driver.py next) and an English
# phase result line in its run dir
{ cat "$SP"; printf '%s\n' "## Review implementazione" "Review status: NEEDS_CHANGES" "Feature status: PLANNED" \
    "## Implementation review" "Review status: APPROVED"; } > .claude/.ai-workflow/spec-z.md
mkdir -p .claude/.ai-workflow/spec-z.run/log
printf '%s\n' '{"type":"result","result":"PHASE RESULT fix: OK — done","structured_output":{"fase":"fix","esito":"OK","motivo":"m","deviazioni":["defensive: a.py:1 — branch"],"bloccato_su":"none","file":[],"gate_interni":[],"finding":[]}}' > .claude/.ai-workflow/spec-z.run/log/03-fix.jsonl
drv equiv .claude/.ai-workflow > "$T/eq.out" 2>&1; rc=$?
check "equiv: tre run dir, next e valida uguali → exit 0" '[ $rc -eq 0 ] && grep -q "^equiv: spec=3 diverse=0 · jsonl=3 diversi=0$" "$T/eq.out"'
check "  1.4.0 (c): equiv in it e poi in en nello stesso processo, uguale in tutte e due" '[ "$(grep -c "^equiv: spec=3 diverse=0 · jsonl=3 diversi=0$" "$T/eq.out")" = 2 ] && [ "$(grep "^equiv: lingua " "$T/eq.out" | tr "\n" " ")" = "equiv: lingua it equiv: lingua en " ]'
check "  e in en lo STOP di spec-z e' quello inglese, uguale nei due lati" 'grep -q "^UGUALE spec-z · Next: STOP — the spec has both .## Review implementazione. and .## Implementation review." "$T/eq.out"'
check "  spec con «## Review implementazione» e «## Implementation review»: lo stesso STOP da cycle-state.sh e driver.py" 'grep -q "^UGUALE spec-z · Next: STOP — la spec ha sia .## Review implementazione. sia .## Implementation review." "$T/eq.out"'
# 1.5.0 (D6): the warnings on the cycles not closed, informative. blocco: the lines of the pass in language $2 of the
# output $1; avvisi_ok: in that pass the frozen summary line, then one AVVISO per spec named in $4 (in the text of the
# language, $3 = «non chiusa» or «not closed»), then the counts $5 as the last line.
blocco() { sed -n "/^equiv: lingua $2\$/,/^equiv: lingua [a-z]*\$/p" "$1" | sed '/^equiv: lingua /d'; }
avvisi_ok() { # $1 output, $2 language, $3 text of the warning, $4 specs, $5 counts line
  local b s nr na
  b=$(blocco "$1" "$2")
  [ "$(printf '%s\n' "$b" | grep -c "^equiv: AVVISO — ")" = "$(printf '%s\n' $4 | grep -c .)" ] || return 1
  for s in $4; do [ "$(printf '%s\n' "$b" | grep -c "^equiv: AVVISO — $s $3")" = 1 ] || return 1; done
  [ "$(printf '%s\n' "$b" | tail -1)" = "$5" ] || return 1
  nr=$(printf '%s\n' "$b" | grep -n "^equiv: spec=" | cut -d: -f1); na=$(printf '%s\n' "$b" | grep -n "^equiv: AVVISO — " | head -1 | cut -d: -f1)
  [ -n "$nr" ] && [ "$nr" -lt "${na:-999999}" ]
}
check "1.5.0 (D6): x, y, z aperte → in it tre avvisi, uno per spec, dopo la riga riassuntiva, poi «aperte=3 · impronta-non-uguale=0»" 'avvisi_ok "$T/eq.out" it "non chiusa (Next: " "spec-x spec-y spec-z" "equiv: aperte=3 · impronta-non-uguale=0"' "$(cat "$T/eq.out")"
check "  e in en gli stessi tre, col testo inglese" 'avvisi_ok "$T/eq.out" en "not closed (Next: " "spec-x spec-y spec-z" "equiv: aperte=3 · impronta-non-uguale=0"'
check "  la parola è quella di Next del lato bash (spec-z: STOP, spec-x: IMPLEMENT), exit sempre 0" '[ $rc -eq 0 ] && grep -q "^equiv: AVVISO — spec-z non chiusa (Next: STOP): la prova su questa spec copre la riga che decide quella parola, non il cammino fino a DONE$" "$T/eq.out" && grep -q "^equiv: AVVISO — spec-x not closed (Next: IMPLEMENT): the proof" "$T/eq.out"'
cp "$T/eq.out" "$T/eq-avvisi.out"
FIC_DRIVER_CERT="$T/cert" drv equiv --certifica .claude/.ai-workflow > "$T/eq.out" 2>&1; rc=$?
check "equiv --certifica: scrive il certificato con gli hash attuali" '[ $rc -eq 0 ] && grep -qx "driver $(h "$DRV")" "$T/cert" && grep -qx "cycle-state $(h "$FC/cycle-state.sh")" "$T/cert" && grep -qx "run-phase $(h "$FC/run-phase.sh")" "$T/cert"'
check "  1.4.0: anche il catalogo e i suoi due lettori (messages, maat-msg, maat_msg), e «lingue it,en» nella riga corpus" 'msgh | while IFS= read -r l; do grep -qxF "$l" "$T/cert" || exit 1; done && grep -q "^corpus spec=3 jsonl=3 · lingue it,en · " "$T/cert"'
# 1.5.0 (D3): the corpus line ends with the fingerprint of the corpus (= equiv --impronta, 12 digits) and the validator
# of the interpreter (jsonschema if it imports it, otherwise minimo); --validatori-precedenti joins those of before
FPC=$(drv equiv --impronta .claude/.ai-workflow 2>&1)
VAL=minimo; "$FIC_PY" -B -c "import jsonschema" >/dev/null 2>&1 && VAL=jsonschema
ALTRO=jsonschema; [ $VAL = jsonschema ] && ALTRO=minimo
check "  1.5.0: riga corpus con «· impronta <12 cifre> · validatori <v>» in coda, l'impronta = equiv --impronta, v = $VAL" '[[ $FPC =~ ^[0-9a-f]{64}$ ]] && grep -qE "^corpus spec=3 jsonl=3 · lingue it,en · [^ ]+ · impronta [0-9a-f]{12} · validatori (minimo|jsonschema)$" "$T/cert" && grep -q " · impronta ${FPC:0:12} · validatori $VAL$" "$T/cert"' "$(grep "^corpus " "$T/cert") · $FPC"
FIC_DRIVER_CERT="$T/cert2" drv equiv --certifica --validatori-precedenti $ALTRO .claude/.ai-workflow > "$T/eq2.out" 2>&1; rc=$?
check "  --validatori-precedenti $ALTRO: uniti a quello di questo passaggio, in ordine fisso → «validatori minimo,jsonschema»" '[ $rc -eq 0 ] && grep -q " · impronta ${FPC:0:12} · validatori minimo,jsonschema$" "$T/cert2"' "$(grep "^corpus " "$T/cert2")"
FIC_DRIVER_CERT="$T/cert3" drv equiv --certifica --validatori-precedenti altro .claude/.ai-workflow > "$T/eq3.out" 2>&1; rc=$?
check "  un validatore sconosciuto → uso (exit 2), nessuna prova, nessun certificato" '[ $rc -eq 2 ] && [ ! -f "$T/cert3" ] && ! grep -q "^equiv: lingua" "$T/eq3.out" && grep -q "equiv --impronta" "$T/eq3.out"'
drv equiv --impronta --certifica .claude/.ai-workflow > "$T/eq3.out" 2>&1; rc1=$?
drv equiv --validatori-precedenti minimo .claude/.ai-workflow > "$T/eq3.out" 2>&1; rc2=$?
drv equiv --impronta "$T/non-esiste" > "$T/eq3.out" 2>&1; rc3=$?
check "  --impronta con --certifica, --validatori-precedenti senza --certifica → uso (2); --impronta su un percorso assente → 2" '[ $rc1 -eq 2 ] && [ $rc2 -eq 2 ] && [ $rc3 -eq 2 ] && [ ! -f "$T/cert3" ]'
FIC_DRIVER_CERT="$T/cert" drv certificato > "$T/c.out"; rc=$?
check "certificato: VALIDO (exit 0)" '[ $rc -eq 0 ] && grep -q "^certificato: VALIDO" "$T/c.out"'
# 1.4.0: a change to maat_msg.py (here in a copy of the plugin, FIC_DRIVER_ROOT) makes the certificate expire
MC="$T/plug-mc/maat"; mkdir -p "$T/plug-mc" && cp -r "$ROOT" "$MC" && find "$MC" -name __pycache__ -type d -prune -exec rm -rf {} +
printf '# changed\n' >> "$MC/scripts/maat_msg.py"
FIC_DRIVER_ROOT="$MC" FIC_DRIVER_CERT="$T/cert" drv certificato > "$T/c.out"; rc=$?
check "  1.4.0: maat_msg.py cambiato → SCADUTO, e il certificato dice maat_msg" '[ $rc -eq 1 ] && grep -q "SCADUTO — hash diversi: maat_msg" "$T/c.out"'
out=$(FIC_DRIVER_CERT="$T/cert" bash "$MC/scripts/cycle-state.sh" "$SP" 2>&1)
check "  e l'involucro cycle-state.sh di quella copia resta autonomo (nessun driver)" 'printf "%s\n" "$out" | grep -q "^Next: IMPLEMENT" && ! printf "%s\n" "$out" | grep -q "AVVISO: driver.py next"'
rm -rf "$T/plug-mc"
sed -i 's/^driver .*/driver 0000/' "$T/cert"; FIC_DRIVER_CERT="$T/cert" drv certificato > "$T/c.out"; rc=$?
check "  hash del driver diverso → SCADUTO (exit 1)" '[ $rc -eq 1 ] && grep -q "SCADUTO — hash diversi: driver" "$T/c.out"'
# 1.4.0: the text is in the catalog, shared by the two sides: the mutation stays on a copy of driver.py and makes
# the Python twin point to another existing key (the same mutation as before: IMPLEMENT with another reason)
sed 's/"IMPLEMENT — " + T("cycle-state.impl")/"IMPLEMENT — " + T("cycle-state.plan_draft")/' "$DRV" > "$T/drv-diverso.py"
check "controprova equiv: la mutazione e' applicata (il gemello Python punta a un'altra chiave)" 'grep -qF "\"IMPLEMENT — \" + T(\"cycle-state.plan_draft\")" "$T/drv-diverso.py"'
"$FIC_PY" "$T/drv-diverso.py" equiv .claude/.ai-workflow > "$T/eq.out" 2>&1; rc=$?
check "equiv: un driver che risponde diverso → DIVERSO, exit 1, niente certificato" '[ $rc -eq 1 ] && grep -q "^DIVERSO spec-x" "$T/eq.out" && grep -q "diverse=2" "$T/eq.out"'
# counterproof: the warnings removed (copy of driver.py) → the case «three warnings» turns red
sed 's/^        print("equiv: AVVISO — " + w)$/        pass  # AVVISI tolti/' "$DRV" > "$T/drv-noavvisi.py"
check "controprova avvisi: la mutazione e' applicata" 'grep -q "AVVISI tolti" "$T/drv-noavvisi.py"'
"$FIC_PY" "$T/drv-noavvisi.py" equiv .claude/.ai-workflow > "$T/eq.out" 2>&1
check "controprova avvisi: senza le righe AVVISO il caso «tre avvisi» (it) e' rosso" '! avvisi_ok "$T/eq.out" it "non chiusa (Next: " "spec-x spec-y spec-z" "equiv: aperte=3 · impronta-non-uguale=0" && grep -q "^equiv: aperte=3 · impronta-non-uguale=0$" "$T/eq.out"'
rm -rf .claude/.ai-workflow/spec-y.md .claude/.ai-workflow/spec-y.run .claude/.ai-workflow/spec-z.md .claude/.ai-workflow/spec-z.run
# 1.5.0 (D6): a closed spec (DONE, legacy) gives no warning; a spec whose harness.fp is not UGUALE (a fake one,
# impronta=0…0 → CAMBIATO) gives the stronger one, «only the fingerprint branch», and counts in impronta-non-uguale
EW=.claude/.ai-workflow/spec-w.md; EH=.claude/.ai-workflow/spec-h.md
{ cat "$SP"; printf '%s\n' "## Review implementazione" "Review status: APPROVED" "Feature status: IMPLEMENTED" \
    "Verification: VERIFIED" "Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1"; } > "$EW"
cp "$SP" "$EH"; mkdir -p "${EH%.md}.run"; printf 'impronta=%064d\n' 0 > "${EH%.md}.run/harness.fp"
check "premessa: spec-w chiusa (DONE), spec-h ferma sull'impronta (STOP)" 'FIC_DRIVER=0 bash "$FC/cycle-state.sh" "$EW" | grep -q "^Next: DONE" && FIC_DRIVER=0 bash "$FC/cycle-state.sh" "$EH" | grep -q "^Next: STOP — harness cambiato"'
drv equiv "$EW" "$EH" > "$T/eq.out" 2>&1; rc=$?
check "  equiv su spec-w e spec-h: in it nessun avviso per spec-w, quello forte per spec-h, «aperte=1 · impronta-non-uguale=1»" '[ $rc -eq 0 ] && avvisi_ok "$T/eq.out" it "con harness.fp CAMBIATO (Next: STOP): la prova su questa spec copre solo il ramo dell.impronta$" spec-h "equiv: aperte=1 · impronta-non-uguale=1"' "$(cat "$T/eq.out")"
check "  e in en lo stesso, col testo inglese" 'avvisi_ok "$T/eq.out" en "with harness.fp CAMBIATO (Next: STOP): the proof on this spec covers only the fingerprint branch$" spec-h "equiv: aperte=1 · impronta-non-uguale=1" && ! grep -q "AVVISO — spec-w" "$T/eq.out"'
rm -rf "$EW" "$EH" "${EH%.md}.run"

# 1.5.0 (D3): the corpus fingerprint, equiv --impronta (no proof). On a copy of the repo with the same name elsewhere.
# imp_*: 0 if the property holds for driver $1
IMP_A=$T/altrove/repo; mkdir -p "$T/altrove"; cp -r "$W" "$IMP_A"
imp() { "$FIC_PY" "$1" equiv --impronta "$2" 2>/dev/null; }
imp_altrove() { local a b; a=$(imp "$1" "$W/.claude/.ai-workflow"); b=$(imp "$1" "$IMP_A/.claude/.ai-workflow"); [[ $a =~ ^[0-9a-f]{64}$ ]] && [ "$a" = "$b" ]; }
imp_byte() { # $2 file relative to the copy (created if missing, removed after if so), $3 content, $4 the same with one byte changed
  local a b f=$IMP_A/$2 c=; [ -e "$f" ] || c=1
  mkdir -p "$(dirname "$f")"; printf '%s' "$3" > "$f"; a=$(imp "$1" "$IMP_A/.claude/.ai-workflow")
  printf '%s' "$4" > "$f"; b=$(imp "$1" "$IMP_A/.claude/.ai-workflow")
  if [ -n "$c" ]; then rm -f "$f"; else printf '%s' "$3" > "$f"; fi
  [[ $a =~ ^[0-9a-f]{64}$ ]] && [[ $b =~ ^[0-9a-f]{64}$ ]] && [ "$a" != "$b" ]
}
check "--impronta: stessa cartella in un altro percorso (stesso nome) → stessa impronta" 'imp_altrove "$DRV"'
check "  un byte cambiato in un .esito della run dir (ignorata da git) → impronta diversa" 'imp_byte "$DRV" "$RUN/log/09-implement.esito" "PHASE RESULT implement: OK — a
state=000000000000
" "PHASE RESULT implement: OK — b
state=000000000000
"'
check "  un byte cambiato in .claude/maat.json → impronta diversa" 'imp_byte "$DRV" .claude/maat.json "{\"lingua\": \"it\"}
" "{\"lingua\": \"en\"}
"'
check "  un byte cambiato in un file di codice (src/a.py) → impronta diversa" 'imp_byte "$DRV" src/a.py "uno
" "uno!
"'
check "  il CR non conta (contenuto senza CR, come il certificato)" 'a=$(imp "$DRV" "$IMP_A/.claude/.ai-workflow"); printf "uno\r\n" > "$IMP_A/src/a.py"; b=$(imp "$DRV" "$IMP_A/.claude/.ai-workflow"); printf "uno\n" > "$IMP_A/src/a.py"; [ "$a" = "$b" ]'
# the machine's git configuration does not enter: a global core.excludesFile, and the default ignore file of
# ~/.config/git, that exclude *.py leave an untracked src/nuovo.py in the fingerprint
H2=$T/home-escludi; mkdir -p "$H2/.config/git"; printf '*.py\n' > "$H2/escludi"; printf '*.py\n' > "$H2/.config/git/ignore"
printf '[core]\n\texcludesFile = %s\n' "$(cygpath -m "$H2/escludi" 2>/dev/null || printf '%s' "$H2/escludi")" > "$H2/.gitconfig"
i0=$(imp "$DRV" "$IMP_A/.claude/.ai-workflow"); printf 'nuovo\n' > "$IMP_A/src/nuovo.py"
i1=$(imp "$DRV" "$IMP_A/.claude/.ai-workflow"); i2=$(HOME=$H2 env -u XDG_CONFIG_HOME "$FIC_PY" "$DRV" equiv --impronta "$IMP_A/.claude/.ai-workflow" 2>/dev/null)
check "premessa: con quella configurazione globale git esclude src/nuovo.py (e senza no)" '[ -z "$(cd "$IMP_A" && HOME=$H2 env -u XDG_CONFIG_HOME git ls-files -o --exclude-standard src)" ] && [ -n "$(cd "$IMP_A" && git ls-files -o --exclude-standard src)" ]'
check "  un file non tracciato e non ignorato entra nell'impronta; un core.excludesFile globale che esclude *.py non la cambia" '[ "$i0" != "$i1" ] && [ "$i1" = "$i2" ]' "$i0 $i1 $i2"
rm -f "$IMP_A/src/nuovo.py"
# counterproofs on copies of driver.py: a fingerprint that ignores the run dirs (.claude/ not walked) → «byte in a
# .esito» red; one with the absolute path of the root instead of its name → «another path» red
sed 's/^                tops = \[os.path.join(r, ".claude")\]$/                tops = []  # RUN-DIR ignorate/' "$DRV" > "$T/drv-norun.py"
sed 's/^            nome = os.path.basename(r.rstrip("\/\\\\"))$/            nome = r  # PERCORSO assoluto/' "$DRV" > "$T/drv-assoluto.py"
check "controprove impronta: le due mutazioni sono applicate" 'grep -q "RUN-DIR ignorate" "$T/drv-norun.py" && grep -q "PERCORSO assoluto" "$T/drv-assoluto.py"'
check "controprova: impronta che ignora le run dir → il caso «byte cambiato in un .esito» e' rosso" '! imp_byte "$T/drv-norun.py" "$RUN/log/09-implement.esito" "a
" "b
"'
check "controprova: impronta col percorso assoluto → il caso «altro percorso» e' rosso" '! imp_altrove "$T/drv-assoluto.py"'
rm -rf "$T/altrove" "$H2"

# --- 6. plan counterproofs (mutations on a copy; the case must turn red) ---
sed 's/^        if prev is not None and word == prev\[0\] and state == prev\[1\]:  # ANTI-LOOP\r\?$/        if False:  # ANTI-LOOP tolto/' "$DRV" > "$T/drv-noloop.py"
check "controprova anti-loop: la mutazione e' applicata" 'grep -q "ANTI-LOOP tolto" "$T/drv-noloop.py"'
DRUN_DRV="$T/drv-noloop.py" drun nulla "$SP" --max-fasi 3
check "controprova anti-loop: senza la guardia la stessa fase si rilancia (3 lanci, nessun anti-loop)" '[ "$(calls)" = 3 ] && ! grep -q "anti-loop" "$T/run.out"'
sed 's/^def schema_errors(obj, schema):\r\?$/&\n    return []  # VALIDAZIONE-JSON tolta/' "$DRV" > "$T/drv-novalida.py"
check "controprova validazione: la mutazione e' applicata" 'grep -q "VALIDAZIONE-JSON tolta" "$T/drv-novalida.py"'
"$FIC_PY" "$T/drv-novalida.py" valida "$V/fuori.jsonl" "$SCHEMA" implement "$T/nv.json" > "$T/nv.out" 2>&1
check "controprova validazione: senza validazione il JSON fuori schema passa (result.json scritto, nessuno STOP)" '[ -f "$T/nv.json" ] && ! grep -q "uscita non valida" "$T/nv.out"'

# --- 7. batches sized and lanes decided by the driver (step 5) ---
printf 'def a():\n    return 1\n' > src/a.py; printf 'def b():\n    return 2\n' > src/b.py; git add -A; git commit -qm ab
spec_f2() { # format-2 plan with two independent blocks, approved, acceptance tests recorded
  printf '%s\n' "# X" "## Contesto" "Contesto." "## Requisiti funzionali" "1. Fare A." "## Piano di implementazione" \
    "Plan format: 2" "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" \
    "### File toccati" "- \`src/a.py\`" "- \`src/b.py\`" "- \`src/test_a.py\` (nuovo)" "- \`src/test_b.py\` (nuovo)" \
    "### Passi" "#### Blocco B1 — a" "scrive: \`src/a.py\`, \`src/test_a.py\`" "dopo: nessuno" "" \
    "| id | file | modifica | test |" "|---|---|---|---|" "| P1 | \`src/a.py\` | x | T1 |" "" \
    "#### Blocco B2 — b" "scrive: \`src/b.py\`, \`src/test_b.py\`" "dopo: nessuno" "" \
    "| id | file | modifica | test |" "|---|---|---|---|" "| P2 | \`src/b.py\` | y | T2 |" \
    "### Tracciabilità requisiti" "| Req | Passi del piano | Verifica |" "|---|---|---|" "| RF1 | P1, P2 | T1, T2 |" \
    "### Piano di test" "| ID | requisito | file | asserzione | mutazione |" "|---|---|---|---|---|" \
    "| T1 | RF1 | \`src/test_a.py::test_a\` (nuovo) | rosso se: \`assert 1 == 2\` | — |" \
    "| T2 | RF1 | \`src/test_b.py::test_b\` (nuovo) | rosso se: \`assert 3 == 4\` | — |" \
    "### Changelog revisione piano" "- giro 1: ok" > "$SP"
  local cur; cur=$(bash "$PC" basis "$SP" | sed -n 's/^Basis: //p')
  sed -i "s/^Superfici a rischio: .*/&\nApproved basis: $cur/" "$SP"
  printf 'def test_a():\n    assert 1 == 2\n' > src/test_a.py; printf 'def test_b():\n    assert 3 == 4\n' > src/test_b.py
  bash "$PC" basis "$SP" --write-tests >/dev/null
}
cat > "$T/rp-env" <<'EOF'
#!/usr/bin/env bash
echo "$2" >> "$FAKE_CALLS"; echo "FIC_CORSIE=${FIC_CORSIE:-}" > "$FAKE_CALLS.env"; cp "$3" "$FAKE_CALLS.prompt"; exit 0
EOF
chmod +x "$T/rp-env"
drun5() { # [variables] — one run round with the run-phase recording environment and prompt
  rm -rf "$RUN" "$FAKE_CALLS"*; spec_f2
  env "$@" FIC_REPO="$W" FIC_RUN_PHASE="$T/rp-env" FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$SP" > "$T/run.out" 2>&1
}
drun5
check "passo 5: formato 2 → IMPLEMENT con i lotti nel prompt (un lotto sotto il tetto: B1,B2)" 'grep -q "^LOTTI (driver): lotto 1/1: B1,B2 (~" "$FAKE_CALLS.prompt" && [ -f "$RUN/log/01-implement.lotti" ]'
check "  corsie decise dal driver (blocks-independent.py): parallelo, in FIC_CORSIE a run-phase" 'grep -qx "blocks-independent: esito=parallelo corsie=2" "$RUN/log/01-implement.corsie-driver" && grep -q "^FIC_CORSIE=.*01-implement.corsie-driver$" "$FAKE_CALLS.env"'
drun5 FIC_LOTTO_MAX=1
check "  tetto basso → un lotto per blocco, dichiarati sopra il tetto" 'grep -q "lotto 1/2: B1 (~[0-9]*k token, sopra il tetto) · lotto 2/2: B2" "$FAKE_CALLS.prompt"'
drun5 FIC_LANES=0
check "  FIC_LANES=0 → nessuna decisione di corsie, FIC_CORSIE vuota" '[ ! -f "$RUN/log/01-implement.corsie-driver" ] && grep -qx "FIC_CORSIE=" "$FAKE_CALLS.env"'
rm -rf "$RUN" "$FAKE_CALLS"*; spec_approved; : > "$FAKE_CALLS"
FIC_RUN_PHASE="$T/rp-env" FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$SP" > "$T/run.out" 2>&1
check "  formato 1 → niente lotti ne' corsie (le decide il worker)" '! grep -q LOTTI "$FAKE_CALLS.prompt" && grep -qx "FIC_CORSIE=" "$FAKE_CALLS.env"'
# run-phase.sh with FIC_CORSIE: the driver's decision becomes log/<label>.corsie and launch_lanes starts (two lanes)
printf '%s\n' "blocks-independent: esito=parallelo corsie=2" "corsia 1: B1" "corsia 2: B2" "scope 1: src/a.py" "scope 2: src/b.py" > "$T/corsie"
rm -rf "$T/rpc.run"
FIC_CORSIE="$T/corsie" FIC_LOCK="$T/lock" FIC_REPO="$W" CLAUDE_BIN="$T/claude" FIC_GATES="$T/gates" FIC_FINALIZE="$T/non-esiste" \
  bash "$FC/run-phase.sh" "$T/rpc.run" 01-implement "$T/prompt.md" >/dev/null 2>&1 </dev/null
check "run-phase.sh con FIC_CORSIE: usa la decisione del driver e lancia le due corsie (launch_lanes)" 'head -1 "$T/rpc.run/log/01-implement.corsie" | grep -qx "blocks-independent: esito=parallelo corsie=2" && [ -f "$T/rpc.run/log/01-implement.corsia-1.prompt" ] && [ -f "$T/rpc.run/log/01-implement.corsia-2.prompt" ]'
rm -rf "$T/rpc.run"
FIC_LANES=0 FIC_CORSIE="$T/corsie" FIC_LOCK="$T/lock" FIC_REPO="$W" CLAUDE_BIN="$T/claude" FIC_GATES="$T/gates" FIC_FINALIZE="$T/non-esiste" \
  bash "$FC/run-phase.sh" "$T/rpc.run" 01-implement "$T/prompt.md" >/dev/null 2>&1 </dev/null
check "  FIC_LANES=0 vince su FIC_CORSIE: serie" 'grep -q "esito=serie motivo=FIC_LANES=0" "$T/rpc.run/log/01-implement.corsie" && [ ! -f "$T/rpc.run/log/01-implement.corsia-1.prompt" ]'
rm -f src/test_a.py src/test_b.py

# --- 8. lines loaded per phase (step 4): the measure of the benefit, cap 300 ---
drv righe > "$T/righe.out"; rc=$?
cat "$T/righe.out" | sed 's/^/    /'
check "righe: il carico BASE di ogni fase e' <=300 righe di istruzioni" '[ $rc -eq 0 ] && [ "$(grep -c "^righe " "$T/righe.out")" = 7 ] && ! grep -q "ASSENTE\|SOPRA" "$T/righe.out"'
check "  e le letture a parte sono riportate (scrittura del piano con autore.md, revisori con il loro agente), senza file mancanti" 'grep "^righe plan:" "$T/righe.out" | grep -q "con la scrittura del piano: [0-9]* (base plan-review-cycle/autore.md=[0-9]*)" && grep "^righe plan:" "$T/righe.out" | grep -q "revisore del piano: [0-9]* (plan-review-cycle/revisori.md=[0-9]* agents/spec-plan-reviewer.md=[0-9]*)" && grep "^righe review:" "$T/righe.out" | grep -q "revisore: [0-9]* (implementation-review-cycle/prompt-revisore.md=[0-9]* agents/implementation-reviewer.md=[0-9]*)" && ! grep -q "=None" "$T/righe.out"'

# --- 9. port of cycle-state.test.sh: same cases, output compared with standalone cycle-state.sh ---
if [ "${DRIVER_TEST_RAPIDO:-0}" = 1 ]; then
  echo "driver.test.sh: sezione 9 saltata (DRIVER_TEST_RAPIDO=1)"
else
  cat > "$T/cs-confronto.sh" <<EOF
#!/usr/bin/env bash
a=\$(FIC_DRIVER=0 bash "$FC/cycle-state.sh" "\$@" 2>/dev/null)
b=\$("$FIC_PY" "$DRV" next "\$@" 2>&1)
[ "\$a" = "\$b" ] || printf '=== %s\n--- cycle-state.sh\n%s\n--- driver.py next\n%s\n' "\$*" "\$a" "\$b" >> "$T/cs-diff"
printf '%s\n' "\$b"
EOF
  CS="$T/cs-confronto.sh" bash "$FC/cycle-state.test.sh" > "$T/cs.out" 2>&1; rc=$?
  tail -1 "$T/cs.out"
  check "cycle-state.test.sh sul driver: tutti i casi passano" '[ $rc -eq 0 ]'
  check "  e a ogni chiamata l'output del driver e' identico a cycle-state.sh" '[ ! -s "$T/cs-diff" ]'
  [ -s "$T/cs-diff" ] && head -40 "$T/cs-diff"
fi

# --- 10. L2 promotion before the review (harness-pt15): absorption with the same criterion as finalize.sh ---
# NEW file calc.py: test-red records the stub (somma), gen marks T1 assorbita; the final code also exports
# LIMITE, which the stub did not have: `plan-check.sh l2` (finalize's check) says NO, so before the review the
# entry must lose "assorbita" and reach counterproof.sh to be really executed. Counterproof: with the old driver
# (DRV=<copy>) the review receives the entry still absorbed, which finalize then rejects; with the old gen
# (l2_eval(..., False)) the regenerated list no longer matches.
spec_l2() {
  printf '%s\n' "# X" "## Contesto" "Contesto." "## Requisiti funzionali" "1. Fare la somma." "## Piano di implementazione" \
    "Plan format: 2" "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" \
    "### File toccati" "- \`modules/api/app/services/calc.py\` (nuovo)" "- \`modules/api/tests/test_calc.py\` (nuovo)" \
    "### Passi" "#### Blocco B1 — somma" "scrive: \`modules/api/app/services/calc.py\`, \`modules/api/tests/test_calc.py\`" "dopo: nessuno" "" \
    "| id | file | modifica | test |" "|---|---|---|---|" "| P1 | \`modules/api/app/services/calc.py\` | somma | T1 |" \
    "### Tracciabilità requisiti" "| Req | Passi del piano | Verifica |" "|---|---|---|" "| RF1 | P1 | T1 |" \
    "### Piano di test" "| ID | requisito | file | asserzione | mutazione |" "|---|---|---|---|---|" \
    "| T1 | RF1 | \`modules/api/tests/test_calc.py::test_somma\` (nuovo) | rosso se: la somma e' sbagliata | \`modules/api/app/services/calc.py\` · \`somma\` · \`return a + b\` → \`return 0\` · rosso se: \`assert 0 == 3\` |" \
    "### Changelog revisione piano" "- giro 1: ok" > "$SP"
  local cur; cur=$(bash "$PC" basis "$SP" | sed -n 's/^Basis: //p')
  sed -i "s/^Superfici a rischio: .*/&\nApproved basis: $cur/" "$SP"
  mkdir -p modules/api/app/services modules/api/tests
  printf 'from app.services.calc import somma\n\ndef test_somma():\n    assert somma(1, 2) == 3\n' > modules/api/tests/test_calc.py
  printf 'def somma(a, b):\n    return 0\n' > modules/api/app/services/calc.py   # the test-red stub
  bash "$PC" basis "$SP" --write-tests >/dev/null
  bash "$PC" stubs "$SP" --run-dir "$RUN" >/dev/null
  printf '{"esito":"OK","test":{"T1":{"esito":"dimostrato","motivo":"","messaggio":"E  assert 0 == 3","posizione":"modules/api/tests/test_calc.py:4"}}}\n' > "$RUN/test-red/rossi.json"
  bash "$PC" gen "$SP" --run-dir "$RUN" >/dev/null
  printf '{"id":"T1","esito":"assorbita","controprova":"ASSORBITA"}\n' > "$RUN/counterproof/T1.json"
}
printf '#!/usr/bin/env bash\necho "Plan status: APPROVED"; echo "State: 000000000000"; echo "Next: REVIEW — finta"\n' > "$T/cs-review"; chmod +x "$T/cs-review"
printf '#!/usr/bin/env bash\necho "$2" >> "$FAKE_CALLS"; cp "$1/counterproof/mutations.json" "$FAKE_CALLS.mut"; exit 0\n' > "$T/rp-mut"; chmod +x "$T/rp-mut"
lrun() { rm -f "$FAKE_CALLS"*; FIC_DRIVER_CERT="$T/cert-ko" FIC_CYCLE_STATE="$T/cs-review" FIC_RUN_PHASE="$T/rp-mut" FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$SP" > "$T/run.out" 2>&1; }
# maat.json of the fake repo (pk04b-2): plan-check routes files and tests only with the declared modules
printf '{"versione_schema": 1, "moduli": [{"nome": "be", "radice": "modules/api", "ambiente": "nativo"}]}\n' > "$T/cfg-be.json"
export MAAT_CONFIG="$T/cfg-be.json"
rm -rf "$RUN"; spec_l2
check "L2: fixture — dopo test-red gen marca T1 assorbita (stub = codice)" 'grep -q "\"assorbita\": true" "$RUN/counterproof/mutations.json"'
printf 'LIMITE = 10\n\n\ndef somma(a, b):\n    return a + b\n' > modules/api/app/services/calc.py   # the final code: one extra symbol
check "  il controllo di finalize (plan-check.sh l2) sul codice finale dice NO" 'bash "$PC" l2 "$SP" --run-dir "$RUN" | grep -q "^L2 T1: NO — gli stub non coprono tutti e soli i simboli nuovi"'
lrun
check "L2: stub che non coprono i simboli nuovi → la review riceve T1 NON assorbita (si esegue davvero)" '[ "$(cat "$FAKE_CALLS")" = 01-review ] && [ -s "$FAKE_CALLS.mut" ] && ! grep -q "assorbita\|\"motivo\"" "$FAKE_CALLS.mut" && grep -q "\"id\": \"T1\"" "$FAKE_CALLS.mut"'
check "  copia di prima in mutations.json.pre-promozione, T1.json assorbito spostato, evento nel driver.log" 'grep -q "\"assorbita\": true" "$RUN/counterproof/mutations.json.pre-promozione" && [ ! -f "$RUN/counterproof/T1.json" ] && [ -f "$RUN/counterproof/T1.json.assorbita" ] && grep -q "L2: controprova T1 non piu. assorbita, si esegue: gli stub non coprono" "$RUN/driver.log"'
mkdir -p "$T/gen-ora"; cp -r "$RUN/test-red" "$T/gen-ora/"; bash "$PC" gen "$SP" --run-dir "$T/gen-ora" >/dev/null
check "  e coincide con la lista che gen genera ORA (cp_from_gen di run-phase.sh: le controprove le esegue il driver)" 'cmp -s "$RUN/counterproof/mutations.json" "$T/gen-ora/counterproof/mutations.json"'
rm -rf "$RUN" "$T/gen-ora"; spec_l2
printf 'def somma(a, b):\n    return a + b\n' > modules/api/app/services/calc.py   # same symbols as the stub
lrun
check "L2: stub che coprono tutti e soli i simboli nuovi → resta assorbita, nessuna promozione" 'grep -q "\"assorbita\": true" "$FAKE_CALLS.mut" && [ ! -f "$RUN/counterproof/mutations.json.pre-promozione" ] && [ -f "$RUN/counterproof/T1.json" ]'
rm -rf "$RUN" "$FAKE_CALLS"* modules

# --- 11. (1.4.0) a whole cycle through the REAL run-phase.sh, MAAT_LINGUA=en and =it: implement -> review -> DONE.
# The readers no static scan sees (dubbio deciso 5: values built at runtime, exit codes) are on this path: the .esito
# lines and their state=, the result.json rule, the review section (here with the English heading), the Finalize:
# line (written in English), the harness fingerprint with the language, the anti-loop. Fake claude by FIC_PHASE,
# fake gates and finalize; the driver forced on (FIC_DRIVER=1), run-phase.sh and cycle-state.sh the real ones.
unset MAAT_CONFIG
cat > "$T/claude-e2e" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
case "$FIC_PHASE" in
  implement) echo "e2e $MAAT_LINGUA" >> "$FIC_REPO/src/a.py"
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/a.py"}}]}}'
    echo '{"type":"result","result":"PHASE RESULT implement: OK — done","structured_output":{"fase":"implement","esito":"OK","motivo":"done","deviazioni":[],"bloccato_su":"none","file":["src/a.py"],"gate_interni":[],"finding":[]}}' ;;
  review) printf '%s\n' "" "## Implementation review" "Review status: APPROVED" "Feature status: IMPLEMENTED" >> "$E2E_SPEC"
    echo '{"type":"result","result":"PHASE RESULT review: OK — approved","structured_output":{"fase":"review","esito":"OK","motivo":"approved","deviazioni":[],"bloccato_su":"none","file":[],"gate_interni":[],"finding":[]}}' ;;
esac
EOF
chmod +x "$T/claude-e2e"
cat > "$T/fin-e2e" <<EOF
#!/usr/bin/env bash
d=\${!#}; printf 'Finalize: IMPLEMENTED — snapshot %s — signed · %s\n' "$EFP" "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "\${d%.run}.md"
echo "finalize: esito=IMPLEMENTED"
EOF
chmod +x "$T/fin-e2e"
e2e() { # $1 language → rc, output in $T/e2e-$1.out, the labels of the .esito in $T/e2e-$1.labels
  rm -rf "$RUN" "$T/lock"; git checkout -q -- src; spec_approved
  MAAT_LINGUA=$1 E2E_SPEC="$W/$SP" FIC_DRIVER=1 FIC_LOCK="$T/lock" FIC_REPO="$W" CLAUDE_BIN="$T/claude-e2e" FIC_GATES="$T/gates" \
    FIC_FINALIZE="$T/fin-e2e" FIC_LANES=0 FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$SP" > "$T/e2e-$1.out" 2>&1 </dev/null
  rc=$?
  ls "$RUN/log" 2>/dev/null | sed -n 's/\.esito$//p' | tr '\n' ' ' > "$T/e2e-$1.labels"
}
e2e en; rc_en=$rc
check "11 (1.4.0): ciclo completo in inglese con run-phase.sh vero → DONE (exit 0), implement e review" '[ $rc_en -eq 0 ] && grep -q "^driver: Driver result: DONE — DONE — section without a snapshot (legacy)" "$T/e2e-en.out" && [ "$(cat "$T/e2e-en.labels")" = "01-implement 02-review " ]'
check "  le righe di esito scritte in inglese (PHASE RESULT), lo State registrato, nessun harness cambiato" 'sed -n 1p "$RUN/log/01-implement.esito" | grep -qx "PHASE RESULT implement: OK — done" && grep -q "^state=[0-9a-f]\{12\}$" "$RUN/log/02-review.esito" && ! grep -qi "harness" "$T/e2e-en.out"'
check "  gli eventi del driver in inglese" 'grep -q "^driver: ▶ 01-implement started$" "$T/e2e-en.out" && ! grep -q "avviata\|finita" "$T/e2e-en.out"'
e2e it; rc_it=$rc
check "  lo stesso ciclo in italiano: stesse fasi, stessa fine" '[ $rc_it -eq 0 ] && [ "$(cat "$T/e2e-it.labels")" = "$(cat "$T/e2e-en.labels")" ] && grep -q "^driver: Driver result: DONE — DONE — sezione senza snapshot (legacy)" "$T/e2e-it.out"'
rm -rf "$RUN" "$T/lock"; git checkout -q -- src

cd /
# informative, not a check: with an SCADUTO certificate the wrappers stay standalone (safe direction)
echo "driver.test.sh: $(unset FIC_DRIVER_CERT; drv certificato)"
echo "driver.test.sh: $pass passati, $fail falliti"
[ $fail -eq 0 ]
