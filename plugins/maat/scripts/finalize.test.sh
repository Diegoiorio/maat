#!/usr/bin/env bash
# finalize.test.sh — finalize.sh on a synthetic repository (configured with the nuxt-fastapi example) with the REAL
# evidence of gates.sh (WSL, test-fast.sh,
# node, npm and the venv python FAKE as in gates.test.sh; temporary HOME, no contact with the WSL copy):
# all gates PASS at the current key -> IMPLEMENTED; old key -> NEEDS_VERIFICATION; review that declares
# PASS without evidence files -> never IMPLEMENTED; gate FAIL, full level without lint, counterproofs (JSON of
# counterproof.sh and review table), nothing to sign, CRLF preserved. Mutation counterproof run
# here: without the key comparison the «chiave vecchia» case becomes IMPLEMENTED. harness-pt09: verdict = AND
# (review APPROVED + gate FAIL or counterproof not red -> FAIL; + gate BLOCKED -> NEEDS_VERIFICATION) and merge
# requirement -> test ID -> results (--copertura): an ID without result -> requirement «non coperto».
#   bash script/fic/finalize.test.sh
#   FZ=/path/variant.sh bash script/fic/finalize.test.sh   # the suite on a variant
set -uo pipefail
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)   # plugin root
FZ=${FZ:-$HERE/finalize.sh}
pass=0 fail=0
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
# the mutants written in $W include the resolver next to themselves ($W/lib) and find the plugin from MAAT_ROOT;
# 1.4.0: also the message catalog and its two readers (lib/messages.tsv, lib/maat-msg.sh, maat_msg.py)
mkdir -p "$W/lib" && cp "$HERE/lib/maat-paths.sh" "$HERE/lib/maat-msg.sh" "$HERE/lib/messages.tsv" "$W/lib/" &&
  cp "$HERE/maat_msg.py" "$W/"; export MAAT_ROOT=$ROOT
export HOME="$W/home"; mkdir -p "$HOME"
ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/    /'; }
chk() { if eval "$2"; then ok; else ko "$1" "${3:-}"; fi; }

# --- synthetic repository (as in gates.test.sh) ---
R="$W/repo"; A="$R/modules/app/apps/admin"; API="$R/modules/api"; FB="$W/bin"
# test-fast.sh belongs to the harness (pk04b-1): the fake lives in a COPY of the plugin, given as FIC_GATES_HARNESS
HP="$W/plugin"; cp -r "$ROOT" "$HP" && find "$HP" -name __pycache__ -type d -prune -exec rm -rf {} +
mkdir -p "$A/utils" "$API/app/services" "$API/tests" "$FB" "$R/.claude"
cp "$ROOT/examples/nuxt-fastapi.maat.json" "$R/.claude/maat.json"
printf 'export const somma = (a: number) => a\n' > "$A/utils/goals.ts"
printf "import { somma } from './goals'\nit('x', () => expect(somma(1)).toBe(1))\n" > "$A/utils/goals.test.ts"
printf '{"name":"app"}\n' > "$R/modules/app/package.json"
printf 'def f():\n    return 1\n' > "$API/app/services/goals.py"
printf 'def test_f():\n    assert True\n' > "$API/tests/test_goals.py"
cat > "$HP/scripts/test-fast.sh" <<'EOF'
#!/usr/bin/env bash
case ${FAKE_VF:-pass} in
  pass) echo " ✓ utils/goals.test.ts (2 tests) 3ms"; echo " Tests  2 passed (2)"; echo "vitest-fast: esito=PASS luogo=copia"; exit 0 ;;
  fail) echo " FAIL  utils/goals.test.ts > somma > x"; echo " Tests  1 failed | 1 passed (2)"; echo "vitest-fast: esito=FAIL luogo=copia"; exit 1 ;;
esac
EOF
(cd "$R" && git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false &&
  git add -A && git commit -qm init)
cat > "$FB/wsl" <<EOF
#!/usr/bin/env bash
c=\${1//\/mnt\//\/}
PATH="$FB:\$PATH" bash -c "\$c"
EOF
printf '#!/usr/bin/env bash\necho v18.19.0\n' > "$FB/node"
printf '#!/usr/bin/env bash\necho "build ok"\n' > "$FB/npm"
cat > "$FB/venv-python" <<'EOF'
#!/usr/bin/env bash
[ "$1" = --version ] && { echo "Python 3.12.1"; exit 0; }
[ "$1 $2" = "-m pip" ] && { echo "fastapi==0.110.0"; exit 0; }
if [ "$1 $2" = "-m pytest" ]; then
  for a in "$@"; do case $a in --junitxml=*) j=${a#--junitxml=} ;; esac; done
  printf '<?xml version="1.0"?><testsuites><testsuite name="pytest" tests="1" failures="0" errors="0" skipped="0"><testcase classname="tests.test_goals" name="test_f"/></testsuite></testsuites>\n' > "$j"
  echo "1 passed"; exit 0
fi
exit 9
EOF
chmod +x "$FB"/* "$HP/scripts/test-fast.sh"
export FIC_GATES_ROOT="$R" FIC_GATES_HARNESS="$HP" FIC_GATES_WSL="$FB/wsl" FIC_GATES_VENV_PY="$FB/venv-python"
export FIC_GATES="$ROOT/scripts/gates.sh"
F_STD=(modules/api/app/services/goals.py modules/app/apps/admin/utils/goals.ts)

# --- spec and run dir ---
WF="$W/wf"; SP="$WF/spec-x.md"; RUN="$WF/spec-x.run"
mkdir -p "$RUN"; printf '%s\n' "${F_STD[@]}" > "$RUN/touched.txt"
spec() { # $1 Review status, $2 Feature status, $3 outcome of the counterproof row in the table
  printf '%s\n' "# X" "## Contesto" "Contesto." "## Requisiti funzionali" "1. Fare A." \
    "## Piano di implementazione" "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" \
    "### Passi" "1. Modificare \`utils/goals.ts\`." \
    "## Review implementazione" "Review status: $1" "Feature status: $2" "Verification: VERIFIED" \
    "Reviewed snapshot:  base aaaaaaaaaaaa ·  tree bbbbbbbbbbbb · fingerprint cccccccccccc · 2 paths " \
    "Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1" "" \
    "| Gate | Req. | Command / check | Result | Evidence |" \
    "| backend tests (touched) | yes | pytest tests/test_goals.py | PASS | 1/1 |" \
    "| plan: counterproof on goals.ts | yes | mutazione di somma | ${3:-PASS} | observed this session |" > "$SP"
}
out="" rc=0
fin() { out=$(bash "$FZ" "$@" "$RUN" 2>&1); rc=$?; }
fstat() { tr -d '\r' < "$SP" | sed -n 's/^Feature status: //p'; }
gates() { bash "$FIC_GATES" --run-dir "$RUN" std "${F_STD[@]}" >/dev/null 2>&1; }

# --- 1. all gates PASS at the current key => IMPLEMENTED confirmed ---
gates; spec APPROVED IMPLEMENTED
fin --level std
chk "gate PASS alla chiave attuale: uscita 0" '[ $rc -eq 0 ]' "$out"
chk "  Feature status resta IMPLEMENTED, firmato" '[ "$(fstat)" = IMPLEMENTED ] && grep -q "^Finalize: IMPLEMENTED — " "$SP"' "$(cat "$SP")"
chk "  riga finale" 'printf "%s\n" "$out" | tail -1 | grep -q "^finalize: esito=IMPLEMENTED"'
SFP=$(printf '%s' "base aaaaaaaaaaaa · tree bbbbbbbbbbbb · fingerprint cccccccccccc · 2 paths" | sha256sum | cut -c1-12)
chk "  la riga Finalize porta l'impronta del Reviewed snapshot (spazi compressi, come snap_fp di cycle-state)" 'grep -q "^Finalize: IMPLEMENTED — snapshot $SFP — " "$SP"' "$(grep "^Finalize" "$SP")"
fin
chk "livello letto dal piano (Test level: std) senza --level" '[ $rc -eq 0 ] && [ "$(grep -c "^Finalize:" "$SP")" = 1 ]' "$out"

# --- 2. old key (a new file in the tree after the gates) => NEEDS_VERIFICATION ---
spec APPROVED IMPLEMENTED
printf 'nuovo\n' > "$R/nota.md"
fin --level std
chk "chiave vecchia: uscita 1, NEEDS_VERIFICATION" '[ $rc -eq 1 ] && [ "$(fstat)" = NEEDS_VERIFICATION ]' "$out"
chk "  Verification PARTIAL col gate mancante" 'grep -q "^Verification: PARTIAL (finalize.sh: nessuna evidenza del driver alla chiave attuale.*chiavi vecchie" "$SP"' "$(cat "$SP")"
rm -f "$R/nota.md"

# --- 3. the review declares PASS but there is no evidence file => never IMPLEMENTED ---
RUN0=$RUN; RUN="$WF/spec-y.run"; SP="$WF/spec-y.md"; mkdir -p "$RUN"; cp "$RUN0/touched.txt" "$RUN/"
spec APPROVED IMPLEMENTED
fin --level std
chk "report senza file di evidenza: NEEDS_VERIFICATION" '[ $rc -eq 1 ] && [ "$(fstat)" = NEEDS_VERIFICATION ]' "$out"
RUN=$RUN0; SP="$WF/spec-x.md"

# --- 4. gate FAIL at the current key ---
printf 'x\n' > "$R/altro.md"
FAKE_VF=fail gates; spec APPROVED IMPLEMENTED
fin --level std
# harness-pt09, verdict = AND: review APPROVED + gate FAIL => FAIL (the «APPROVED + any FAIL» row of the review)
chk "review APPROVED + tests-fe FAIL alla chiave attuale: FAIL (uscita 3)" '[ $rc -eq 3 ] && grep -q "^Finalize: FAIL — " "$SP" && printf "%s\n" "$out" | tail -1 | grep -q "^finalize: esito=FAIL"' "$out"
chk "  Review NEEDS_CHANGES, Feature PLANNED, Verification PARTIAL col gate" 'grep -qx "Review status: NEEDS_CHANGES" "$SP" && [ "$(fstat)" = PLANNED ] && grep -q "^Verification: PARTIAL (finalize.sh: tests-fe: FAIL" "$SP"' "$(cat "$SP")"
chk "  cycle-state manda a FIX (budget 1/3)" 'bash "$ROOT/scripts/cycle-state.sh" "$SP" 2>/dev/null | grep -q "^Next: FIX"' "$(bash "$ROOT/scripts/cycle-state.sh" "$SP" 2>&1)"
fin --level std
chk "  una seconda firma non tocca nulla (niente APPROVED da firmare): uscita 4" '[ $rc -eq 4 ]' "$out"
rm -f "$R/altro.md"

# --- 4b. review APPROVED + gate BLOCKED (venv missing) => NEEDS_VERIFICATION, not FAIL ---
printf 'y\n' > "$R/altro.md"
FIC_GATES_VENV_PY="$W/venv-assente.exe" gates; spec APPROVED IMPLEMENTED
out=$(FIC_GATES_VENV_PY="$W/venv-assente.exe" bash "$FZ" --level std "$RUN" 2>&1); rc=$?
chk "review APPROVED + tests-be BLOCKED: NEEDS_VERIFICATION (uscita 1)" '[ $rc -eq 1 ] && [ "$(fstat)" = NEEDS_VERIFICATION ] && grep -qx "Review status: APPROVED" "$SP" && grep -q "^Verification: PARTIAL (finalize.sh: tests-be: BLOCKED" "$SP"' "$out"
rm -f "$R/altro.md"

# --- 5. full level: lint required, std evidence only => NEEDS_VERIFICATION ---
spec APPROVED IMPLEMENTED
fin --level full
chk "full senza evidenza al livello full: NEEDS_VERIFICATION" '[ $rc -eq 1 ] && grep -q "livello full" "$SP"' "$out"

# --- 6. counterproofs: counterproof.sh JSON (green, absent, red on assertion) ---
mkdir -p "$RUN/counterproof"; printf '[{"id":"CP-1"}]\n' > "$RUN/counterproof/mutations.json"
spec APPROVED IMPLEMENTED; fin --level std
chk "controprova senza risultato: NEEDS_VERIFICATION" '[ $rc -eq 1 ] && grep -q "controprova CP-1: risultato assente" "$SP"' "$out"
printf '{"id":"CP-1","esito":"verde","motivo":"la mutazione non e coperta"}\n' > "$RUN/counterproof/CP-1.json"
spec APPROVED IMPLEMENTED; fin --level std
chk "controprova verde (non rossa): FAIL anche con la review APPROVED" '[ $rc -eq 3 ] && [ "$(fstat)" = PLANNED ] && grep -q "controprova CP-1: verde" "$SP"' "$out"
printf '{"id":"CP-1","esito":"bloccato","motivo":"mirror"}\n' > "$RUN/counterproof/CP-1.json"
spec APPROVED IMPLEMENTED; fin --level std
chk "controprova bloccata: NEEDS_VERIFICATION, non FAIL" '[ $rc -eq 1 ] && [ "$(fstat)" = NEEDS_VERIFICATION ] && grep -q "controprova CP-1: bloccato" "$SP"' "$out"
printf '{"id":"CP-1","esito":"rosso_asserzione","controprova":"PASS"}\n' > "$RUN/counterproof/CP-1.json"
spec APPROVED IMPLEMENTED NOT\ RUN; fin --level std
chk "controprova rossa su asserzione: IMPLEMENTED (il JSON vince sulla tabella)" '[ $rc -eq 0 ] && [ "$(fstat)" = IMPLEMENTED ]' "$out"

# --- 6b. merge requirement -> test ID -> results (harness-pt09) ---
printf '%s\n' '{"fase":"review","esito":"OK","motivo":"m","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[],' \
  '"copertura":[{"requisito":"R1 somma","test":["modules/api/tests/test_goals.py::test_f"]},' \
  '{"requisito":"R2 vista","test":["utils/goals.test.ts"]},' \
  '{"requisito":"R3 mancante","test":["tests/test_goals.py::test_f","tests/test_goals.py::test_inesistente"]},' \
  '{"requisito":"R4 mutazione","test":["CP-1"]},' \
  '{"requisito":"R5 per nome","test":["utils/goals.test.ts > somma > x"]},' \
  '{"requisito":"R6 nessuno","test":[]}]}' > "$W/review.result.json"
spec APPROVED IMPLEMENTED; sed -i 's/^Verification: VERIFIED$/Verification: VERIFIED (provvisorio: VERIFY del driver in parallelo)/' "$SP"
fin --level std --copertura "$W/review.result.json"
row() { tr -d '\r' < "$SP" | grep -F "| $1 |"; }
chk "unione: verdetto invariato dai requisiti non coperti (IMPLEMENTED, uscita 0)" '[ $rc -eq 0 ] && [ "$(fstat)" = IMPLEMENTED ]' "$out"
chk "  Verification provvisoria confermata da finalize" 'grep -q "^Verification: VERIFIED (finalize.sh: gate" "$SP"' "$(grep ^Verification "$SP")"
chk "  tabella sotto la riga Finalize" 'tr -d "\r" < "$SP" | grep -A1 "^Finalize: IMPLEMENTED" | tail -1 | grep -q "^Requirement evidence (finalize.sh: "' "$(cat "$SP")"
chk "  node id pytest con risultato nel JUnit -> PASS (tests-be)" 'row "R1 somma" | grep -q "test_f → PASS (tests-be) |$"' "$(row "R1 somma")"
chk "  file di test con la riga ✓ del wrapper -> PASS (tests-fe)" 'row "R2 vista" | grep -q "goals.test.ts → PASS (tests-fe) |$"' "$(row "R2 vista")"
chk "  un ID senza risultato -> requisito non coperto, anche se l altro ID ce l ha" 'row "R3 mancante" | grep -q "| non coperto (senza risultato: tests/test_goals.py::test_inesistente) |$"' "$(row "R3 mancante")"
chk "  id di controprova -> esito di counterproof/<id>.json" 'row "R4 mutazione" | grep -q "CP-1 → PASS (controprova rosso_asserzione) |$"' "$(row "R4 mutazione")"
chk "  test frontend per nome: il report non ha l esito per test -> non coperto" 'row "R5 per nome" | grep -q "| non coperto (senza risultato: utils/goals.test.ts > somma > x) |$"' "$(row "R5 per nome")"
chk "  requisito senza ID -> non coperto" 'row "R6 nessuno" | grep -q "non coperto (nessun ID di test)"' "$(row "R6 nessuno")"
chk "  riepilogo su stdout" 'printf "%s\n" "$out" | grep -q "Evidence composta — 6 requisiti, 3 non coperti"' "$out"
sed -i 's/^Review status: .*/Review status: APPROVED/; s/^Feature status: .*/Feature status: IMPLEMENTED/' "$SP"
fin --level std --copertura "$W/review.result.json"
chk "  una seconda firma sostituisce la tabella (una sola)" '[ "$(grep -c "^Requirement evidence (finalize.sh" "$SP")" = 1 ] && [ "$(grep -c "^| R1 somma |" "$SP")" = 1 ]' "$(cat "$SP")"
# 1.3.0: the English review heading and the English provisional marker that the review skill now writes
spec APPROVED IMPLEMENTED; sed -i 's/^## Review implementazione$/## Implementation review/; s/^Verification: VERIFIED$/Verification: VERIFIED (provisional: driver VERIFY in parallel)/' "$SP"
fin --level std --copertura "$W/review.result.json"
chk "«## Implementation review» con «(provisional: …)»: firmata IMPLEMENTED, Verification confermata da finalize" '[ $rc -eq 0 ] && [ "$(fstat)" = IMPLEMENTED ] && grep -q "^Finalize: IMPLEMENTED — " "$SP" && grep -q "^Verification: VERIFIED (finalize.sh: gate" "$SP"' "$(cat "$SP")"
# L2 (harness-pt11): an "assorbita" entry counts only if plan-check.sh l2 confirms it on the current code; this spec
# is in format 1, so l2 confirms nothing -> the entry is not enough (fail-closed); red on assertion, yes.
printf '[{"id":"CP-1","assorbita":true,"motivo":"L2"}]\n' > "$RUN/counterproof/mutations.json"
printf '{"id":"CP-1","esito":"assorbita","controprova":"ASSORBITA"}\n' > "$RUN/counterproof/CP-1.json"
spec APPROVED IMPLEMENTED; fin --level std
chk "controprova assorbita non confermata da l2: NEEDS_VERIFICATION" '[ $rc -eq 1 ] && grep -q "controprova CP-1: assorbita (L2) non valida" "$SP" && [ -f "$RUN/counterproof/l2.txt" ]' "$out"
printf '{"id":"CP-1","esito":"rosso_asserzione","controprova":"PASS"}\n' > "$RUN/counterproof/CP-1.json"
spec APPROVED IMPLEMENTED; fin --level std
chk "  assorbita ma comunque rossa su asserzione: IMPLEMENTED" '[ $rc -eq 0 ] && [ "$(fstat)" = IMPLEMENTED ]' "$out"
# new counterproof.sh outcomes (pk04b-2): rosso_generico (command runner) = PASS but WEAK proof, declared;
# non_eseguita (module without counterproof) = NOT RUN (declared): NEEDS_VERIFICATION, never FAIL
printf '[{"id":"CP-1"}]\n' > "$RUN/counterproof/mutations.json"
cp_generico() { printf '{"id":"CP-1","esito":"rosso_generico","controprova":"PASS","motivo":"il comando della controprova esce 1"}\n' > "$RUN/counterproof/CP-1.json"; }
cp_non_eseguita() { printf '{"id":"CP-1","esito":"non_eseguita","controprova":"NOT RUN","motivo":"NOT RUN (dichiarato): modulo be senza controprova"}\n' > "$RUN/counterproof/CP-1.json"; }
caso_generico() { # $1 script: IMPLEMENTED, weak proof in the Finalize line and on stdout, weak PASS in the table
  cp_generico; spec APPROVED IMPLEMENTED; out=$(bash "$1" --level std --copertura "$W/review.result.json" "$RUN" 2>&1); rc=$?
  [ $rc -eq 0 ] && [ "$(fstat)" = IMPLEMENTED ] && grep -q "^Finalize: IMPLEMENTED — .*prove deboli: controprova CP-1: rosso_generico, prova debole" "$SP" &&
    printf '%s\n' "$out" | grep -q "^prova debole: controprova CP-1: rosso_generico" &&
    row "R4 mutazione" | grep -q "CP-1 → PASS (controprova rosso_generico, prova debole) |$"
}
caso_non_eseguita() { # $1 script: NEEDS_VERIFICATION with the reason NOT RUN (dichiarato), never FAIL
  cp_non_eseguita; spec APPROVED IMPLEMENTED; out=$(bash "$1" --level std "$RUN" 2>&1); rc=$?
  [ $rc -eq 1 ] && [ "$(fstat)" = NEEDS_VERIFICATION ] && grep -q "^Verification: PARTIAL (finalize.sh: controprova CP-1: NOT RUN (dichiarato): modulo be senza controprova" "$SP"
}
chk "controprova rosso_generico: IMPLEMENTED, dichiarata prova debole (dettaglio, stdout, tabella)" 'caso_generico "$FZ"' "$out $(grep "^Finalize" "$SP") $(row "R4 mutazione")"
chk "controprova non_eseguita: NOT RUN (dichiarato) -> NEEDS_VERIFICATION, non FAIL" 'caso_non_eseguita "$FZ"' "$out $(grep "^Verification" "$SP")"
# mutation counterproofs: rosso_generico counted as FAIL; non_eseguita counted as FAIL
for mu in 'rosso_generico|s/^CP_DEBOLE = "rosso_generico"$/CP_DEBOLE = "nessuno"/; s/^CP_FAIL = (\(.*\)"verde")$/CP_FAIL = (\1"verde", "rosso_generico")/' \
          'non_eseguita|s/^CP_NON_ESEGUITA = "non_eseguita"$/CP_NON_ESEGUITA = "nessuno"/; s/^CP_FAIL = (\(.*\)"verde")$/CP_FAIL = (\1"verde", "non_eseguita")/'; do
  M="$W/mut-${mu%%|*}.sh"; sed "${mu#*|}" "$FZ" > "$M"
  if cmp -s "$FZ" "$M"; then ko "controprova (${mu%%|*} come FAIL): la mutazione non si applica"; continue; fi
  if [ "${mu%%|*}" = rosso_generico ]; then caso_generico "$M"; else caso_non_eseguita "$M"; fi; r=$?
  if [ $r -ne 0 ]; then ok   # expected red
  else ko "controprova: con ${mu%%|*} contato come FAIL il caso resta verde (il test non discrimina)" "$out"; fi
done
rm -rf "$RUN/counterproof"
spec APPROVED IMPLEMENTED; fin --level std --copertura "$W/review.result.json"
chk "  controprova senza risultato (niente counterproof/) -> non coperto" 'row "R4 mutazione" | grep -q "non coperto (senza risultato: CP-1)"' "$(row "R4 mutazione")"
spec APPROVED IMPLEMENTED "NOT RUN"; fin --level std
chk "senza JSON: riga di controprova della tabella non PASS => NEEDS_VERIFICATION" '[ $rc -eq 1 ] && grep -q "controprova (tabella della review) plan: counterproof on goals.ts: NOT RUN" "$SP"' "$out"
spec APPROVED IMPLEMENTED "FAIL"; fin --level std
chk "senza JSON: riga di controprova della tabella FAIL => FAIL" '[ $rc -eq 3 ] && [ "$(fstat)" = PLANNED ]' "$out"

# --- 6c. report by FORMAT, not by gate name (pk04b-1): the pytest module is called «api», junit report ---
RUNX=$RUN SPX=$SP
RUN="$WF/spec-api.run"; SP="$WF/spec-api.md"; mkdir -p "$RUN"; cp "$RUNX/touched.txt" "$RUN/"
sed 's/"nome": "be"/"nome": "api"/' "$R/.claude/maat.json" > "$W/api.maat.json"
export MAAT_CONFIG="$W/api.maat.json"
gates; spec APPROVED IMPLEMENTED; fin --level std --copertura "$W/review.result.json"
chk "report per formato: modulo «api» (junit) -> la tabella dal JUnit di tests-api.json" 'ls "$RUN"/evidence/*/tests-api.json >/dev/null 2>&1 && [ $rc -eq 0 ] && row "R1 somma" | grep -q "test_f → PASS (tests-api) |$"' "$out $(row "R1 somma")"
M="$W/mut-nome.sh"
sed 's/ for n, rep, rad in mods if rep == "junit"\]/ for n, rep, rad in mods if "tests-" + n == "tests-be"]/' "$FZ" > "$M"
if cmp -s "$FZ" "$M"; then ko "controprova (formato dal nome del gate): la mutazione non si applica"; else
  spec APPROVED IMPLEMENTED; out=$(bash "$M" --level std --copertura "$W/review.result.json" "$RUN" 2>&1)
  if row "R1 somma" | grep -q "| non coperto (senza risultato: modules/api/tests/test_goals.py::test_f) |$"; then ok   # expected red
  else ko "controprova: col formato scelto dal nome del gate la tabella ha ancora il risultato (il test non discrimina)" "$(row "R1 somma")"; fi
fi
unset MAAT_CONFIG; RUN=$RUNX SP=$SPX

# --- 6d. 1.4.0, English (MAAT_LINGUA=en): the detail of the Verification:/Finalize: lines and the Evidence table
#     follow the language, prefixes and separators do not; «not covered» is counted like «non coperto»; the English
#     Finalize: line is read back by plan-check.sh closed (the criterion of the chain in basis) and by cycle-state.sh.
#     Counterproof: the reader of «non coperto» only in Italian -> the English count is 0 (red). ---
RUNX=$RUN SPX=$SP
RUN="$WF/spec-en.run"; SP="$WF/spec-en.md"; mkdir -p "$RUN"; cp "$RUNX/touched.txt" "$RUN/"
MAAT_LINGUA=en gates
fin_en() { # $1 script: en signature with the merge, provisional Verification confirmed
  spec APPROVED IMPLEMENTED; sed -i 's/^Verification: VERIFIED$/Verification: VERIFIED (provisional: VERIFY of the driver in parallel)/' "$SP"
  out=$(MAAT_LINGUA=en bash "$1" --level std --copertura "$W/review.result.json" "$RUN" 2>&1); rc=$?
}
fin_en "$FZ"
chk "en: IMPLEMENTED, Verification e Finalize col dettaglio inglese e i prefissi di sempre" '[ $rc -eq 0 ] && [ "$(fstat)" = IMPLEMENTED ] && grep -q "^Verification: VERIFIED (finalize.sh: gates tests-.* at the current key (evidence/" "$SP" && grep -q "^Finalize: IMPLEMENTED — snapshot $SFP — gates .*counterproofs red on assertion · [0-9T:Z-]*$" "$SP" && printf "%s\n" "$out" | tail -1 | grep -q "^finalize: esito=IMPLEMENTED — confirmed: gates "' "$out $(grep -E "^(Verification|Finalize)" "$SP")"
chk "en: tabella Evidence in inglese, «not covered» contato" 'row "R6 nessuno" | grep -q "| not covered (no test ID) |$" && row "R3 mancante" | grep -q "| not covered (no result: tests/test_goals.py::test_inesistente) |$" && grep -q "^Requirement evidence (finalize.sh: requirement → test ID → result of VERIFY, evidence/" "$SP" && printf "%s\n" "$out" | grep -q "^finalize: Evidence composed — 6 requirements, 4 not covered$"' "$out $(grep -A8 "^Requirement evidence" "$SP")"
chk "en: niente italiano del catalogo nella spec" '! grep -qE "non coperto|alla chiave attuale|controprove rosse|requisito → ID|Evidence composta" "$SP"' "$(grep -A8 "^Finalize" "$SP")"
chk "en: plan-check.sh closed rilegge la riga Finalize inglese (anello chiuso), in en e in it" 'MAAT_LINGUA=en bash "$ROOT/scripts/plan-check.sh" closed "$SP" >/dev/null 2>&1 && MAAT_LINGUA=it bash "$ROOT/scripts/plan-check.sh" closed "$SP" >/dev/null 2>&1' "$(MAAT_LINGUA=en bash "$ROOT/scripts/plan-check.sh" closed "$SP" 2>&1)"
nx() { MAAT_LINGUA=$1 FIC_DRIVER=0 bash "$ROOT/scripts/cycle-state.sh" "$SP" 2>/dev/null | tr -d '\r' | sed -n 's/^Next: \([A-Z-]*\).*/\1/p'; }
chk "en: cycle-state.sh legge la riga Finalize inglese: stessa parola di Next in it e in en" '[ -n "$(nx it)" ] && [ "$(nx it)" = "$(nx en)" ]' "it=$(nx it) en=$(nx en)"
M="$W/mut-uncov.sh"
sed 's/^UNCOVERED = ("non coperto", "not covered")$/UNCOVERED = ("non coperto",)/' "$FZ" > "$M"
if cmp -s "$FZ" "$M"; then ko "controprova (lettore di «non coperto» solo italiano): la mutazione non si applica"; else
  fin_en "$M"
  if printf '%s\n' "$out" | grep -q "Evidence composed — 6 requirements, 4 not covered"; then
    ko "controprova: col lettore solo italiano il conteggio inglese resta 4 (il test non discrimina)" "$out"
  else ok; fi   # expected red: «not covered» no longer counted
fi
gates; spec APPROVED IMPLEMENTED; sed -i 's/^Verification: VERIFIED$/Verification: VERIFIED (provvisorio: VERIFY del driver in parallelo)/' "$SP"
fin --level std --copertura "$W/review.result.json"
chk "it, stesso run dir: il testo di sempre («non coperto», 4 non coperti, CP-1 senza risultato qui)" '[ $rc -eq 0 ] && printf "%s\n" "$out" | grep -q "Evidence composta — 6 requisiti, 4 non coperti" && row "R6 nessuno" | grep -q "non coperto (nessun ID di test)"' "$out"
RUN=$RUNX SP=$SPX

# --- 7. nothing to sign: spec untouched ---
spec NEEDS_CHANGES PLANNED; cp "$SP" "$W/prima"
fin --level std
chk "Review NEEDS_CHANGES: uscita 4, spec intatta" '[ $rc -eq 4 ] && cmp -s "$SP" "$W/prima"' "$out"
spec APPROVED NEEDS_VERIFICATION; cp "$SP" "$W/prima"; fin --level std
chk "NEEDS_VERIFICATION non viene promosso" '[ $rc -eq 4 ] && cmp -s "$SP" "$W/prima"' "$out"

# --- 8. CRLF preserved ---
spec APPROVED IMPLEMENTED; sed -i 's/$/\r/' "$SP"; printf 'nuovo\n' > "$R/nota.md"
fin --level std
chk "spec CRLF: ogni riga resta CRLF dopo la scrittura" '[ $rc -eq 1 ] && [ "$(grep -c $'"'"'\r$'"'"' "$SP")" = "$(wc -l < "$SP")" ]' "$(od -c "$SP" | tail -5)"
rm -f "$R/nota.md"

# --- 9. usage ---
spec APPROVED IMPLEMENTED; bash "$FZ" --level boh "$RUN" >/dev/null 2>&1; r=$?; chk "livello sconosciuto: uscita 2" '[ $r -eq 2 ]'
bash "$FZ" "$W/non-esiste.run" >/dev/null 2>&1; r=$?; chk "run dir assente: uscita 2" '[ $r -eq 2 ]'

# --- counterproof: without the key comparison, the «chiave vecchia» case becomes IMPLEMENTED ---
LINE='  if bash "$GATES" --verify "$d" >/dev/null 2>&1; then ev=$d; break; fi   # confronto della chiave'
chk "controprova: riga del confronto unica" '[ "$(grep -cxF -- "$LINE" "$FZ")" = 1 ]'
M="$W/mut-chiave.sh"
sed 's|^  if bash "\$GATES" --verify "\$d" >/dev/null 2>&1; then|  if true; then|' "$FZ" > "$M"
if cmp -s "$FZ" "$M"; then ko "controprova: la mutazione non si applica"; else
  # new run dir with only PASS evidence, then the tree changes: the same state as case 2
  RUN="$WF/spec-z.run"; SP="$WF/spec-z.md"; mkdir -p "$RUN"; cp "$RUN0/touched.txt" "$RUN/"; gates
  printf 'nuovo\n' > "$R/nota.md"
  spec APPROVED IMPLEMENTED; out=$(bash "$FZ" --level std "$RUN" 2>&1); r=$?
  chk "controprova: sull'originale lo stesso stato e' NEEDS_VERIFICATION" '[ $r -eq 1 ] && [ "$(fstat)" = NEEDS_VERIFICATION ]' "$out"
  spec APPROVED IMPLEMENTED; out=$(bash "$M" --level std "$RUN" 2>&1); r=$?
  if [ $r -eq 0 ] && [ "$(fstat)" = IMPLEMENTED ]; then ok   # expected red: the «chiave vecchia» test would fail
  else ko "controprova: sul mutante la chiave vecchia non diventa IMPLEMENTED (il test non discrimina)" "$out"; fi
  rm -f "$R/nota.md"
fi

echo "finalize.test.sh: $pass ok, $fail falliti"
[ $fail -eq 0 ]
