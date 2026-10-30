#!/usr/bin/env bash
# driver.test.sh — test di script/fic/driver.py (harness-pt14), senza claude vero e senza toccare il progetto:
# repo git usa-e-getta, HOME temporanea, run-phase.sh e context-pack.sh finti per la macchina a stati.
#   bash script/fic/driver.test.sh
#   DRIVER_TEST_RAPIDO=1 bash script/fic/driver.test.sh   # salta la sezione 9, il porting di cycle-state.test.sh (~20 min)
#   DRV=/percorso/variante.py bash script/fic/driver.test.sh   # controprova su una mutazione (FIC_DRIVER_ROOT
#                                                              # fa trovare alla copia gli script del repository)
# Sezioni:
#   1 uso · 2 valida: casi di run-phase.test.sh 6b, confrontati byte per byte con `run-phase.sh --valida`
#   3 involucri: cycle-state.sh e run-phase.sh chiamano il driver solo col certificato (o FIC_DRIVER=1)
#   4 run: la macchina a stati (anti-loop, ESITO STOP, uscite 4/6/7 di run-phase, NEEDS_VERIFICATION, result.json
#     non valido, fase in corso, budget, dry-run, flag inoltrati, context-pack, avanzamento fino a DONE)
#   5 equiv e certificato · 6 controprove del piano: anti-loop tolto, validazione dei JSON tolta
#   7 lotti e corsie decisi dal driver (passo 5) · 8 righe caricate per fase (passo 4, tetto sul carico base)
#   9 porting di cycle-state.test.sh: ogni chiamata confronta l'output intero di cycle-state.sh (autonomo) e di
#     `driver.py next`; i casi devono passare E le due uscite coincidere
#  10 promozione L2 prima della review: assorbita solo se regge il controllo di finalize (plan-check.sh l2)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)   # radice del plugin
FC=$ROOT/scripts
DRV=${DRV:-$HERE/driver.py}
. "$FC/python.sh" || { echo "driver.test.sh: nessun interprete Python (FIC_PYTHON)"; exit 2; }
export FIC_DRIVER_ROOT=$ROOT
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
cp "$HERE/maat_paths.py" "$T/"   # i driver mutati scritti in $T importano maat_paths accanto a se' (pk04a-1)
export HOME="$T/home"; mkdir -p "$HOME"
unset FIC_DRIVER FIC_DRIVER_PY FIC_DRIVER_CERT FIC_RUN_PHASE FIC_CONTEXT_PACK FIC_MAX_FASI FIC_REPO FIC_LOCK
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi; }
drv() { "$FIC_PY" "$DRV" "$@"; }

# --- 1. uso ---
drv >/dev/null 2>&1; rc=$?; check "senza comando → 2" '[ $rc -eq 2 ]'
drv next "$T/non-esiste.md" >/dev/null 2>&1; rc=$?; check "next su una spec assente → 2" '[ $rc -eq 2 ]'
drv run >/dev/null 2>&1; rc=$?; check "run senza spec → 2" '[ $rc -eq 2 ]'
drv valida a b >/dev/null 2>&1; rc=$?; check "valida con argomenti sbagliati → 2" '[ $rc -eq 2 ]'

# --- 2. valida: stessi casi e stessi byte del validatore interno di run-phase.sh ---
SCHEMA=$ROOT/schemas/phase-result.schema.json
ok_json() { # $1 fase, $2 esito, $3 deviazioni, $4 bloccato_su
  printf '{"fase":"%s","esito":"%s","motivo":"finto","deviazioni":%s,"bloccato_su":"%s","file":[],"gate_interni":[],"finding":[]}' "$1" "$2" "$3" "$4"
}
V=$T/valida; mkdir -p "$V"
vcase() { # $1 nome, $2 fase, $3 contenuto del log · stampa l'output del driver in $V/$1.out
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
check "  JSON assente → STOP «uscita non valida» con originale=" 'sed -n 1p "$V/senza.out" | grep -q "^ESITO FASE implement: STOP — uscita non valida: nessun blocco JSON" && grep -qx "originale=ESITO FASE implement: OK — fatto" "$V/senza.out"'
vcase fuori implement '{"type":"result","result":"ESITO FASE implement: OK","structured_output":{"fase":"implement","esito":"FORSE","motivo":"m","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[],"extra":1}}'
# Errori in qualunque ordine e formato: validatore minimo ("$.esito … FORSE", "extra") o jsonschema ("'extra' was
# unexpected; 'FORSE' is not one of …"), a seconda che l'interprete abbia jsonschema.
check "  JSON fuori schema → STOP con gli errori, niente result.json" 'l=$(sed -n 1p "$V/fuori.out"); case "$l" in "ESITO FASE implement: STOP — uscita non valida: "*) e=${l#"ESITO FASE implement: STOP — uscita non valida: "}; case "$e" in *FORSE*) ;; *) false ;; esac && case "$e" in *extra*) ;; *) false ;; esac ;; *) false ;; esac && [ ! -f "$V/fuori.b.json" ]'
vcase altra implement '{"type":"result","result":"ESITO FASE implement: OK","structured_output":'"$(ok_json review OK '[]' nessuno)"'}'
check "  JSON di un'altra fase → STOP" 'grep -q "uscita non valida: fase .review. diversa" "$V/altra.out"'
vcase dev implement '{"type":"result","result":"ESITO FASE implement: OK — fatto","structured_output":'"$(ok_json implement OK '["passo 8 adattato"]' nessuno)"'}'
check "  prosa OK ma deviazioni nel JSON → STOP (il piu conservativo)" 'grep -q "^ESITO FASE implement: STOP — JSON: deviazioni dichiarate (1): passo 8 adattato" "$V/dev.out" && grep -qx "originale=ESITO FASE implement: OK — fatto" "$V/dev.out"'
vcase difensive implement '{"type":"result","result":"ESITO FASE implement: OK — fatto","structured_output":'"$(ok_json implement OK '["difensiva: a.py:3 — ramo per un caso escluso dal CHECK"]' nessuno)"'}'
check "  solo deviazioni «difensiva: » → resta OK (nessuno STOP per deviazione)" '[ "$(tr -d "\r" < "$V/difensive.out")" = "ESITO FASE implement: OK — fatto" ]'
vcase miste implement '{"type":"result","result":"ESITO FASE implement: OK — fatto","structured_output":'"$(ok_json implement OK '["difensiva: a.py:3 — ramo", "passo 8 adattato"]' nessuno)"'}'
check "  una difensiva e una no → STOP, tutte elencate" 'grep -q "^ESITO FASE implement: STOP — JSON: deviazioni dichiarate (2): difensiva: a.py:3 — ramo; passo 8 adattato" "$V/miste.out"'
vcase scartato review "$(printf '%s\n' '{"type":"result","result":"ESITO FASE review: OK","structured_output":'"$(ok_json review OK '[]' nessuno)"'}' '{"type":"system","subtype":"fic_scartato"}')"
check "  evento fic_scartato dopo il result → nessun esito" '[ ! -s "$V/scartato.out" ]'
vcase errore implement '{"type":"result","is_error":true,"result":"ESITO FASE implement: OK"}'
check "  is_error → nessun esito" '[ ! -s "$V/errore.out" ]'
vcase recinto fix '{"type":"result","result":"testo\n```json\n'"$(ok_json fix OK '[]' nessuno | sed 's/"/\\"/g')"'\n```\nESITO FASE fix: OK — da recinto"}'
check "  JSON nel recinto json del testo → valido" 'grep -qx "ESITO FASE fix: OK — da recinto" "$V/recinto.out" && [ -f "$V/recinto.b.json" ]'
vcase rotto fix '{"type":"result","result":"```json\n{rotto\n```\nESITO FASE fix: OK"}'
check "  recinto illeggibile → STOP" 'grep -q "uscita non valida: blocco JSON illeggibile" "$V/rotto.out"'
vcase noriga plan '{"type":"result","result":"niente riga","structured_output":'"$(ok_json plan STOP '[]' "migrazione da applicare")"'}'
check "  senza riga ESITO: la compone dal JSON (bloccato_su)" 'grep -qx "ESITO FASE plan: STOP — bloccato su: migrazione da applicare" "$V/noriga.out"'

# --- repo usa-e-getta per involucri, run ed equiv ---
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

# --- 3. involucri ---
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
printf 'driver %s\ncycle-state %s\nrun-phase %s\n' "$(h "$T/finto-drv.py")" "$(h "$FC/cycle-state.sh")" "$(h "$FC/run-phase.sh")" > "$T/cert-ok"
printf 'driver %s\ncycle-state %s\n' "$(h "$T/finto-drv.py")" 0000 > "$T/cert-ko"
out=$(FIC_DRIVER_CERT="$T/cert-ok" FIC_DRIVER_PY="$T/finto-drv.py" bash "$FC/cycle-state.sh" "$SP" 2>/dev/null)
check "cycle-state.sh col certificato valido → il driver" 'printf "%s\n" "$out" | grep -qx "Next: FINTO — dal driver"'
out=$(FIC_DRIVER_CERT="$T/cert-ko" FIC_DRIVER_PY="$T/finto-drv.py" bash "$FC/cycle-state.sh" "$SP" 2>/dev/null)
check "  certificato con un altro hash di cycle-state.sh → autonomo" 'printf "%s\n" "$out" | grep -q "^Next: IMPLEMENT"'
out=$(FIC_DRIVER_CERT="$T/non-esiste" FIC_DRIVER_PY="$T/finto-drv.py" bash "$FC/cycle-state.sh" "$SP" 2>/dev/null)
check "  nessun certificato → autonomo" 'printf "%s\n" "$out" | grep -q "^Next: IMPLEMENT"'
out=$(FINTO_ESCE=1 FIC_DRIVER=1 FIC_DRIVER_PY="$T/finto-drv.py" bash "$FC/cycle-state.sh" "$SP" 2>"$T/cs.err")
check "  driver fallito → autonomo, con AVVISO" 'printf "%s\n" "$out" | grep -q "^Next: IMPLEMENT" && grep -q "AVVISO: driver.py next non riuscito" "$T/cs.err"'
# run-phase.sh: la validazione dell'esito passa dal driver solo quando delega (spia su una fase vera, claude finto)
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
rp() { # $1 = FIC_DRIVER, $2 = etichetta
  rm -f "$SPY"
  FIC_DRIVER=$1 FIC_DRIVER_PY="$T/spia-drv.py" FIC_LOCK="$T/lock" FIC_REPO="$W" CLAUDE_BIN="$T/claude" FIC_GATES="$T/gates" \
    FIC_FINALIZE="$T/non-esiste" FIC_LANES=0 bash "$FC/run-phase.sh" "$T/rp.run" "$2" "$T/prompt.md" >/dev/null 2>&1 </dev/null
}
rp 1 01-implement
check "run-phase.sh, FIC_DRIVER=1: esito validato dal driver (spia) → STOP «uscita non valida»" 'grep -qx valida "$SPY" && sed -n 1p "$T/rp.run/log/01-implement.esito" | grep -q "^ESITO FASE implement: STOP — uscita non valida: .*FORSE"'
rp 0 02-implement
check "run-phase.sh, FIC_DRIVER=0: validatore interno (spia muta), stesso esito" '[ ! -f "$SPY" ] && [ "$(sed -n 1p "$T/rp.run/log/01-implement.esito")" = "$(sed -n 1p "$T/rp.run/log/02-implement.esito")" ]'
printf 'driver %s\nrun-phase %s\n' "$(h "$T/spia-drv.py")" "$(h "$FC/run-phase.sh")" > "$T/cert-rp-ok"
printf 'driver %s\nrun-phase %s\n' "$(h "$T/spia-drv.py")" 0000 > "$T/cert-rp-ko"
rpc() { # $1 = certificato, $2 = etichetta (FIC_DRIVER non impostata: decide il certificato)
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

# --- 4. run: la macchina a stati, con run-phase.sh e context-pack.sh finti ---
cat > "$T/rp-finto" <<'EOF'
#!/usr/bin/env bash
# run-phase.sh finto: <run-dir> <label> <prompt>; FAKE_MODE sceglie cosa fa la "fase"
d=$1 l=$2; mkdir -p "$d/log"; echo "$l" >> "$FAKE_CALLS"; spec="${d%.run}.md"
st() { FIC_DRIVER=0 bash "$FC/cycle-state.sh" "$spec" 2>/dev/null | sed -n 's/^State: //p'; }
case "$FAKE_MODE" in
  nulla) exit 0 ;;
  esito-stop) printf 'ESITO FASE implement: STOP — migrazione da applicare\nstate=x\n' > "$d/log/$l.esito"; exit 0 ;;
  exit4) echo "lock occupato: un'altra fase di codice e' in corso — run=altro" > "$d/log/$l.stderr"; exit 4 ;;
  exit6) echo "STOP: harness cambiato dal 2026-09-30T00:00:00Z" > "$d/log/$l.stderr"; exit 6 ;;
  exit7) echo "WAIT — catena: l'implement dell'anello 2 aspetta l'anello 1 — fase non lanciata" > "$d/log/$l.stderr"; exit 7 ;;
  json-rotto) : > "$d/log/$l.jsonl"; echo x > "$d/log/$l.pre-tree"; echo y > "$d/log/$l.post-tree"
    printf '{"fase":"implement","esito":"FORSE"}\n' > "$d/log/$l.result.json"
    printf 'ESITO FASE implement: OK — fatto\nstate=%s\n' "$(st)" > "$d/log/$l.esito"; exit 0 ;;
  avanza|nv|nv-ver|nv-vuoto)
    case "$l" in
      *implement*) : > "$d/log/$l.jsonl"; echo x > "$d/log/$l.pre-tree"; echo y > "$d/log/$l.post-tree"
        printf 'ESITO FASE implement: OK — fatto\nstate=%s\n' "$(st)" > "$d/log/$l.esito" ;;
      *review*) : > "$d/log/$l.jsonl"
        fs=IMPLEMENTED; case "$FAKE_MODE" in nv*) fs=NEEDS_VERIFICATION ;; esac
        printf '%s\n' "## Review implementazione" "Review status: APPROVED" "Feature status: $fs" >> "$spec"
        [ "$FAKE_MODE" = nv ] && printf '%s\n' "Finalize: NEEDS_VERIFICATION — snapshot 0123456789ab — tests-x: NOT RUN (dichiarato: nessun test) — nessun test nel modulo x, controlli verdi · 2026-10-29T10:00:00Z" \
          "Verification: PARTIAL (finalize.sh: tests-x: NOT RUN (dichiarato: nessun test) — nessun test nel modulo x, controlli verdi)" >> "$spec"
        # pk09: la sola riga Verification: PARTIAL (nessuna Finalize:), oppure nessuna delle due
        [ "$FAKE_MODE" = nv-ver ] && printf '%s\n' "Verification: PARTIAL (finalize.sh: tests-y: NOT RUN (solo la riga Verification))" >> "$spec"
        printf 'ESITO FASE review: OK — finta\nstate=%s\n' "$(st)" > "$d/log/$l.esito" ;;
    esac; exit 0 ;;
esac
exit 0
EOF
chmod +x "$T/rp-finto"
printf '#!/usr/bin/env bash\necho "$@" >> "$FAKE_CALLS.cp"\necho "context-pack: invariato"\n' > "$T/cp-finto"; chmod +x "$T/cp-finto"
export FC FAKE_CALLS=$T/calls
drun() { # $1 FAKE_MODE, poi gli argomenti di run · uscita in rc, output in $T/run.out
  rm -rf "$RUN" "$FAKE_CALLS" "$FAKE_CALLS.cp"; spec_approved
  FAKE_MODE=$1 FIC_RUN_PHASE="$T/rp-finto" FIC_CONTEXT_PACK="$T/cp-finto" "$FIC_PY" "${DRUN_DRV:-$DRV}" run "${@:2}" > "$T/run.out" 2>&1
  rc=$?
}
calls() { local c; c=$(grep -c . "$FAKE_CALLS" 2>/dev/null); echo "${c:-0}"; }
drun nulla "$SP"
check "run: fase che non cambia lo stato → STOP anti-loop (exit 1) dopo UN lancio" '[ $rc -eq 1 ] && grep -q "Esito driver: STOP — anti-loop" "$T/run.out" && [ "$(calls)" = 1 ]'
check "  etichetta 01-implement e prompt della fase" '[ "$(cat "$FAKE_CALLS")" = 01-implement ] && [ "$(cat "$RUN/prompts/01-implement.md")" = "/maat:full-implementation-cycle --worker=implement x" ]'
check "  context-pack.sh lanciato prima della fase, sulla spec" 'grep -q "spec-x.md" "$FAKE_CALLS.cp"'
check "  eventi anche in <run-dir>/driver.log" 'grep -q "▶ 01-implement avviata" "$RUN/driver.log" && grep -q "Esito driver: STOP" "$RUN/driver.log"'
drun esito-stop "$SP"
check "run: ESITO FASE … STOP → STOP con quella riga" '[ $rc -eq 1 ] && grep -q "Esito driver: STOP — ESITO FASE implement: STOP — migrazione da applicare" "$T/run.out"'
drun exit4 "$SP"
check "run: run-phase exit 4 (lock) → OCCUPATO, exit 4" '[ $rc -eq 4 ] && grep -q "Esito driver: OCCUPATO — .*lock occupato" "$T/run.out"'
drun exit6 "$SP"
check "run: run-phase exit 6 (harness) → STOP" '[ $rc -eq 1 ] && grep -q "run-phase exit 6 (harness cambiato" "$T/run.out"'
drun exit7 "$SP"
check "run: run-phase exit 7 con WAIT — catena → WAIT, exit 3" '[ $rc -eq 3 ] && grep -q "Esito driver: WAIT — .*WAIT — catena" "$T/run.out"'
drun json-rotto "$SP"
check "run: result.json non valido dopo la fase → STOP (fail-closed)" '[ $rc -eq 1 ] && grep -q "result.json di 01-implement non valido" "$T/run.out"'
drun avanza "$SP"
check "run: implement OK → review → DONE (exit 0), etichette in ordine" '[ $rc -eq 0 ] && grep -q "Esito driver: DONE" "$T/run.out" && [ "$(tr "\n" " " < "$FAKE_CALLS")" = "01-implement 02-review " ]'
check "  prompt della review" '[ "$(cat "$RUN/prompts/02-review.md")" = "/maat:full-implementation-cycle --worker=review x" ]'
caso_nv() { # pk09: il motivo dice ciclo finito e cosa verificare (dalla riga Finalize:, senza l'ora finale « · …Z»)
  drun nv "$SP"
  [ $rc -eq 1 ] && grep -qF "Esito driver: STOP — ciclo finito: firma NEEDS_VERIFICATION — da verificare: tests-x: NOT RUN (dichiarato: nessun test) — nessun test nel modulo x, controlli verdi; la promozione" "$T/run.out" && [ "$(calls)" = 2 ]
}
check "run: review che da' NEEDS_VERIFICATION in questa invocazione → STOP (exit 1), il motivo dice ciclo finito e cosa verificare" 'caso_nv'
check "  l'ora finale della riga Finalize: (« · 2026-10-29T10:00:00Z») non entra nel motivo" '! grep -q "2026-10-29T10:00:00Z" "$T/run.out"'
drun nv-ver "$SP"
check "  solo la riga Verification: PARTIAL (nessuna Finalize:) → il dettaglio viene da lì" '[ $rc -eq 1 ] && grep -qF "Esito driver: STOP — ciclo finito: firma NEEDS_VERIFICATION — da verificare: tests-y: NOT RUN (solo la riga Verification); la promozione" "$T/run.out"'
drun nv-vuoto "$SP"
check "  nessuna delle due righe → «dettaglio non trovato», sempre STOP (exit 1)" '[ $rc -eq 1 ] && grep -qF "Esito driver: STOP — ciclo finito: firma NEEDS_VERIFICATION — da verificare: dettaglio non trovato nella spec (righe Finalize:/Verification:)" "$T/run.out"'
# controprova (pk09, su una copia): il vecchio motivo «riprovare ora troverebbe…» fa rosso il caso sopra
sed 's/"ciclo finito: firma NEEDS_VERIFICATION — da verificare: %s; /"la review di questa invocazione ha dato NEEDS_VERIFICATION: riprovare ora troverebbe lo stesso ambiente bloccato (%s); /' "$DRV" > "$T/drv-nv-vecchio.py"
check "controprova NEEDS_VERIFICATION: la mutazione e' applicata" 'grep -q "riprovare ora troverebbe" "$T/drv-nv-vecchio.py"'
check "controprova NEEDS_VERIFICATION: col vecchio motivo «riprovare ora» il caso diventa rosso" '! DRUN_DRV="$T/drv-nv-vecchio.py" caso_nv && grep -q "riprovare ora troverebbe" "$T/run.out"'
drun nulla "$SP" --max-fasi 0
check "run: budget di fasi esaurito → STOP senza lanci" '[ $rc -eq 1 ] && grep -q "budget del driver esaurito" "$T/run.out" && [ "$(calls)" = 0 ]'
drun nulla "$SP" --dry-run
check "run --dry-run: dice cosa lancerebbe, non lancia" '[ $rc -eq 0 ] && grep -q "DRY-RUN — lancerei 01-implement" "$T/run.out" && [ "$(calls)" = 0 ]'
drun esito-stop "$SP" -- --tests=std
check "run: i flag dopo -- arrivano nel prompt" '[ "$(cat "$RUN/prompts/01-implement.md")" = "/maat:full-implementation-cycle --worker=implement x --tests=std" ]'
rm -rf "$RUN"; spec_approved; mkdir -p "$RUN/log"; date > "$RUN/log/01-plan.running"; : > "$FAKE_CALLS"
FAKE_MODE=nulla FIC_RUN_PHASE="$T/rp-finto" FIC_CONTEXT_PACK="$T/cp-finto" "$FIC_PY" "$DRV" run "$SP" > "$T/run.out" 2>&1; rc=$?
check "run: fase in corso (.running senza .exit) → exit 4, niente lanci" '[ $rc -eq 4 ] && grep -q "IN CORSO" "$T/run.out" && [ "$(calls)" = 0 ]'
rm -rf "$RUN"; spec_approved; printf '%s\n' "## Review implementazione" "Review status: APPROVED" "Feature status: IMPLEMENTED" >> "$SP"; : > "$FAKE_CALLS"
FAKE_MODE=nulla FIC_RUN_PHASE="$T/rp-finto" FIC_CONTEXT_PACK="$T/cp-finto" "$FIC_PY" "$DRV" run "$SP" > "$T/run.out" 2>&1; rc=$?
check "run: spec gia' DONE → exit 0 senza lanci" '[ $rc -eq 0 ] && grep -q "Esito driver: DONE" "$T/run.out" && [ "$(calls)" = 0 ]'
# M1: senza certificato valido Next/State vengono da cycle-state.sh autonomo (qui un finto che risponde diverso)
printf '#!/usr/bin/env bash\necho "Plan status: finto"; echo "State: 000000000000"; echo "Next: STOP — finto da cycle-state"\n' > "$T/cs-finto"; chmod +x "$T/cs-finto"
rm -rf "$RUN"; spec_approved; : > "$FAKE_CALLS"
FIC_DRIVER_CERT="$T/cert-ko" FIC_CYCLE_STATE="$T/cs-finto" FAKE_MODE=nulla FIC_RUN_PHASE="$T/rp-finto" FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$SP" > "$T/run.out" 2>&1; rc=$?
check "run: certificato scaduto → segue cycle-state.sh (il finto dice STOP), evento nel log" '[ $rc -eq 1 ] && grep -q "Esito driver: STOP — STOP — finto da cycle-state" "$T/run.out" && grep -q "certificato scaduto: next da cycle-state.sh" "$RUN/driver.log" && [ "$(calls)" = 0 ]'
rm -rf "$RUN"; spec_approved; : > "$FAKE_CALLS"
FIC_DRIVER=1 FIC_CYCLE_STATE="$T/cs-finto" FAKE_MODE=nulla FIC_RUN_PHASE="$T/rp-finto" FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$SP" > "$T/run.out" 2>&1; rc=$?
check "  controprova: col driver in vigore (FIC_DRIVER=1) il finto non e' consultato" 'grep -q "Next: IMPLEMENT" "$T/run.out" && ! grep -q "finto da cycle-state\|certificato scaduto" "$T/run.out"'
# M2: la catena — WAIT sulla madre → l'anello nominato; DONE di un anello → la madre → l'anello successivo
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
check "catena: la madre in WAIT sull'anello 1 → il driver lavora sull'anello 1 (01-implement nella sua run dir)" '[ "$(cat "$FAKE_CALLS")" = 01-implement ] && [ "$(cat $CW/spec-m-1-a.run/prompts/01-implement.md)" = "/maat:full-implementation-cycle --worker=implement m-1-a" ] && grep -q "catena: WAIT — passo a spec-m-1-a" $CW/spec-m.run/driver.log && grep -q "Esito driver: STOP — anti-loop" "$T/run.out"'
mk_catena
EFP=$(printf '' | sha256sum | cut -c1-12)
printf '%s\n' "## Review implementazione" "Review status: APPROVED" "Feature status: IMPLEMENTED" \
  "Finalize: IMPLEMENTED — snapshot $EFP — firmato · $(date -u +%Y-%m-%dT%H:%M:%SZ)" "Verification: VERIFIED" \
  "Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1" >> $CW/spec-m-1-a.md
crun $CW/spec-m-1-a.md
check "catena: anello 1 DONE → la madre → WAIT sull'anello 2 → il suo piano (01-plan nella sua run dir)" '[ "$(cat "$FAKE_CALLS")" = 01-plan ] && [ "$(cat $CW/spec-m-2-b.run/prompts/01-plan.md)" = "/maat:full-implementation-cycle --worker=plan m-2-b" ] && grep -q "catena: DONE — passo a spec-m" $CW/spec-m-1-a.run/driver.log && grep -q "catena: WAIT — passo a spec-m-2-b" $CW/spec-m.run/driver.log'
rm -rf $CW/spec-m*.run $CW/spec-m.md $CW/spec-m-1-a.md $CW/spec-m-2-b.md

# --- 5. equiv e certificato ---
rm -rf "$RUN"; spec_approved; mkdir -p "$RUN/log"
printf '%s\n' '{"type":"result","result":"ESITO FASE implement: OK","structured_output":{"fase":"implement","esito":"OK","motivo":"m","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}' > "$RUN/log/01-implement.jsonl"
printf '%s\n' '{"type":"result","result":"ESITO FASE review: OK"}' > "$RUN/log/02-review.jsonl"
cp "$SP" .claude/.ai-workflow/spec-y.md; mkdir -p .claude/.ai-workflow/spec-y.run
drv equiv .claude/.ai-workflow > "$T/eq.out" 2>&1; rc=$?
check "equiv: due run dir, next e valida uguali → exit 0" '[ $rc -eq 0 ] && grep -q "^equiv: spec=2 diverse=0 · jsonl=2 diversi=0$" "$T/eq.out"'
FIC_DRIVER_CERT="$T/cert" drv equiv --certifica .claude/.ai-workflow > "$T/eq.out" 2>&1; rc=$?
check "equiv --certifica: scrive il certificato con gli hash attuali" '[ $rc -eq 0 ] && grep -qx "driver $(h "$DRV")" "$T/cert" && grep -qx "cycle-state $(h "$FC/cycle-state.sh")" "$T/cert" && grep -qx "run-phase $(h "$FC/run-phase.sh")" "$T/cert"'
FIC_DRIVER_CERT="$T/cert" drv certificato > "$T/c.out"; rc=$?
check "certificato: VALIDO (exit 0)" '[ $rc -eq 0 ] && grep -q "^certificato: VALIDO" "$T/c.out"'
sed -i 's/^driver .*/driver 0000/' "$T/cert"; FIC_DRIVER_CERT="$T/cert" drv certificato > "$T/c.out"; rc=$?
check "  hash del driver diverso → SCADUTO (exit 1)" '[ $rc -eq 1 ] && grep -q "SCADUTO — hash diversi: driver" "$T/c.out"'
sed 's/"IMPLEMENT — piano approvato, nessuna review"/"IMPLEMENT — diverso"/' "$DRV" > "$T/drv-diverso.py"
"$FIC_PY" "$T/drv-diverso.py" equiv .claude/.ai-workflow > "$T/eq.out" 2>&1; rc=$?
check "equiv: un driver che risponde diverso → DIVERSO, exit 1, niente certificato" '[ $rc -eq 1 ] && grep -q "^DIVERSO spec-x" "$T/eq.out" && grep -q "diverse=2" "$T/eq.out"'
rm -rf .claude/.ai-workflow/spec-y.md .claude/.ai-workflow/spec-y.run

# --- 6. controprove del piano (mutazioni su una copia; il caso deve diventare rosso) ---
sed 's/^        if prev is not None and word == prev\[0\] and state == prev\[1\]:  # ANTI-LOOP\r\?$/        if False:  # ANTI-LOOP tolto/' "$DRV" > "$T/drv-noloop.py"
check "controprova anti-loop: la mutazione e' applicata" 'grep -q "ANTI-LOOP tolto" "$T/drv-noloop.py"'
DRUN_DRV="$T/drv-noloop.py" drun nulla "$SP" --max-fasi 3
check "controprova anti-loop: senza la guardia la stessa fase si rilancia (3 lanci, nessun anti-loop)" '[ "$(calls)" = 3 ] && ! grep -q "anti-loop" "$T/run.out"'
sed 's/^def schema_errors(obj, schema):\r\?$/&\n    return []  # VALIDAZIONE-JSON tolta/' "$DRV" > "$T/drv-novalida.py"
check "controprova validazione: la mutazione e' applicata" 'grep -q "VALIDAZIONE-JSON tolta" "$T/drv-novalida.py"'
"$FIC_PY" "$T/drv-novalida.py" valida "$V/fuori.jsonl" "$SCHEMA" implement "$T/nv.json" > "$T/nv.out" 2>&1
check "controprova validazione: senza validazione il JSON fuori schema passa (result.json scritto, nessuno STOP)" '[ -f "$T/nv.json" ] && ! grep -q "uscita non valida" "$T/nv.out"'

# --- 7. lotti dimensionati e corsie decise dal driver (passo 5) ---
printf 'def a():\n    return 1\n' > src/a.py; printf 'def b():\n    return 2\n' > src/b.py; git add -A; git commit -qm ab
spec_f2() { # piano in formato 2 con due blocchi indipendenti, approvato, test di accettazione registrati
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
drun5() { # [variabili] — un giro di run con il run-phase che registra ambiente e prompt
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
# run-phase.sh con FIC_CORSIE: la decisione del driver diventa log/<label>.corsie e launch_lanes parte (due corsie)
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

# --- 8. righe caricate per fase (passo 4): la misura del beneficio, tetto 300 ---
drv righe > "$T/righe.out"; rc=$?
cat "$T/righe.out" | sed 's/^/    /'
check "righe: il carico BASE di ogni fase e' <=300 righe di istruzioni" '[ $rc -eq 0 ] && [ "$(grep -c "^righe " "$T/righe.out")" = 7 ] && ! grep -q "ASSENTE\|SOPRA" "$T/righe.out"'
check "  e le letture a parte sono riportate (scrittura del piano con autore.md, revisori con il loro agente), senza file mancanti" 'grep "^righe plan:" "$T/righe.out" | grep -q "con la scrittura del piano: [0-9]* (base plan-review-cycle/autore.md=[0-9]*)" && grep "^righe plan:" "$T/righe.out" | grep -q "revisore del piano: [0-9]* (plan-review-cycle/revisori.md=[0-9]* agents/spec-plan-reviewer.md=[0-9]*)" && grep "^righe review:" "$T/righe.out" | grep -q "revisore: [0-9]* (implementation-review-cycle/prompt-revisore.md=[0-9]* agents/implementation-reviewer.md=[0-9]*)" && ! grep -q "=None" "$T/righe.out"'

# --- 9. porting di cycle-state.test.sh: stessi casi, output confrontato con cycle-state.sh autonomo ---
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

# --- 10. promozione L2 prima della review (harness-pt15): l'assorbimento con lo stesso criterio di finalize.sh ---
# File NUOVO calc.py: test-red registra lo stub (somma), gen marca T1 assorbita; il codice finale esporta anche
# LIMITE, che lo stub non aveva: `plan-check.sh l2` (il controllo di finalize) dice NO, quindi prima della review la
# voce deve perdere "assorbita" e arrivare a counterproof.sh da eseguire davvero. Controprova: con il driver di prima
# (DRV=<copia>) la review riceve la voce ancora assorbita, che finalize poi rifiuta; con gen di prima
# (l2_eval(..., False)) la lista rigenerata non coincide piu'.
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
  printf 'def somma(a, b):\n    return 0\n' > modules/api/app/services/calc.py   # lo stub di test-red
  bash "$PC" basis "$SP" --write-tests >/dev/null
  bash "$PC" stubs "$SP" --run-dir "$RUN" >/dev/null
  printf '{"esito":"OK","test":{"T1":{"esito":"dimostrato","motivo":"","messaggio":"E  assert 0 == 3","posizione":"modules/api/tests/test_calc.py:4"}}}\n' > "$RUN/test-red/rossi.json"
  bash "$PC" gen "$SP" --run-dir "$RUN" >/dev/null
  printf '{"id":"T1","esito":"assorbita","controprova":"ASSORBITA"}\n' > "$RUN/counterproof/T1.json"
}
printf '#!/usr/bin/env bash\necho "Plan status: APPROVED"; echo "State: 000000000000"; echo "Next: REVIEW — finta"\n' > "$T/cs-review"; chmod +x "$T/cs-review"
printf '#!/usr/bin/env bash\necho "$2" >> "$FAKE_CALLS"; cp "$1/counterproof/mutations.json" "$FAKE_CALLS.mut"; exit 0\n' > "$T/rp-mut"; chmod +x "$T/rp-mut"
lrun() { rm -f "$FAKE_CALLS"*; FIC_DRIVER_CERT="$T/cert-ko" FIC_CYCLE_STATE="$T/cs-review" FIC_RUN_PHASE="$T/rp-mut" FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$SP" > "$T/run.out" 2>&1; }
# maat.json del repo finto (pk04b-2): plan-check instrada file e test solo con i moduli dichiarati
printf '{"versione_schema": 1, "moduli": [{"nome": "be", "radice": "modules/api", "ambiente": "nativo"}]}\n' > "$T/cfg-be.json"
export MAAT_CONFIG="$T/cfg-be.json"
rm -rf "$RUN"; spec_l2
check "L2: fixture — dopo test-red gen marca T1 assorbita (stub = codice)" 'grep -q "\"assorbita\": true" "$RUN/counterproof/mutations.json"'
printf 'LIMITE = 10\n\n\ndef somma(a, b):\n    return a + b\n' > modules/api/app/services/calc.py   # il codice finale: un simbolo in piu'
check "  il controllo di finalize (plan-check.sh l2) sul codice finale dice NO" 'bash "$PC" l2 "$SP" --run-dir "$RUN" | grep -q "^L2 T1: NO — gli stub non coprono tutti e soli i simboli nuovi"'
lrun
check "L2: stub che non coprono i simboli nuovi → la review riceve T1 NON assorbita (si esegue davvero)" '[ "$(cat "$FAKE_CALLS")" = 01-review ] && [ -s "$FAKE_CALLS.mut" ] && ! grep -q "assorbita\|\"motivo\"" "$FAKE_CALLS.mut" && grep -q "\"id\": \"T1\"" "$FAKE_CALLS.mut"'
check "  copia di prima in mutations.json.pre-promozione, T1.json assorbito spostato, evento nel driver.log" 'grep -q "\"assorbita\": true" "$RUN/counterproof/mutations.json.pre-promozione" && [ ! -f "$RUN/counterproof/T1.json" ] && [ -f "$RUN/counterproof/T1.json.assorbita" ] && grep -q "L2: controprova T1 non piu. assorbita, si esegue: gli stub non coprono" "$RUN/driver.log"'
mkdir -p "$T/gen-ora"; cp -r "$RUN/test-red" "$T/gen-ora/"; bash "$PC" gen "$SP" --run-dir "$T/gen-ora" >/dev/null
check "  e coincide con la lista che gen genera ORA (cp_from_gen di run-phase.sh: le controprove le esegue il driver)" 'cmp -s "$RUN/counterproof/mutations.json" "$T/gen-ora/counterproof/mutations.json"'
rm -rf "$RUN" "$T/gen-ora"; spec_l2
printf 'def somma(a, b):\n    return a + b\n' > modules/api/app/services/calc.py   # stessi simboli dello stub
lrun
check "L2: stub che coprono tutti e soli i simboli nuovi → resta assorbita, nessuna promozione" 'grep -q "\"assorbita\": true" "$FAKE_CALLS.mut" && [ ! -f "$RUN/counterproof/mutations.json.pre-promozione" ] && [ -f "$RUN/counterproof/T1.json" ]'
rm -rf "$RUN" "$FAKE_CALLS"* modules

cd /
# informativo, non un check: con il certificato SCADUTO gli involucri restano autonomi (direzione sicura)
echo "driver.test.sh: $(unset FIC_DRIVER_CERT; drv certificato)"
echo "driver.test.sh: $pass passati, $fail falliti"
[ $fail -eq 0 ]
