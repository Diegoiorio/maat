#!/usr/bin/env bash
# driver.test.sh — tests of script/fic/driver.py (harness-pt14), without real claude and without touching the project:
# throwaway git repo, temporary HOME, fake run-phase.sh and context-pack.sh for the state machine.
#   bash script/fic/driver.test.sh
#   DRV=/path/variant.py bash script/fic/driver.test.sh   # counterproof on a mutation (FIC_DRIVER_ROOT
#                                                              # lets the copy find the repository's scripts)
# Sections:
#   1 usage · 2 valida: cases from run-phase.test.sh 6b, with their content checks (1.6.0: the byte-for-byte
#     comparison with `run-phase.sh --valida` is gone with it; every branch of the validator is in the expected
#     outputs of the public corpus, tools/esempi-equiv/attese/)
#   3 wrappers (1.6.0): cycle-state.sh and run-phase.sh decide with the driver, the only engine; FIC_DRIVER (0, 1,
#     anything) changes nothing and the wrappers are silent about it; no fallback on error (no Python, Python older
#     than 3.10, driver failed: a STOP); python.sh with and without pipefail; the 3.10 threshold in its two places
#     (python.sh, driver.py; maat-doctor.sh uses fic_py_min_ok since 1.6.0)
#   4 run: the state machine (anti-loop, ESITO STOP, run-phase exits 4/6/7, NEEDS_VERIFICATION, invalid
#     result.json, phase running, budget, dry-run, forwarded flags, context-pack, progress up to DONE); FIC_DRIVER set
#     → one AVVISO per invocation, from run only; FIC_CYCLE_STATE (tests) replaces our own next
#   5 the corpus fingerprint (`driver.py impronta`) · 6 plan counterproofs: anti-loop removed, JSON validation removed
#   7 batches and lanes decided by the driver (step 5) · 8 lines loaded per phase (step 4, cap on the base load)
#   9 (gone in 1.6.0: the port of cycle-state.test.sh compared the driver with the bash table, which is gone; the
#     suite cycle-state.test.sh itself runs on the driver)
#  10 L2 promotion before the review: assorbita only if it holds finalize's check (plan-check.sh l2)
#  11 (1.4.0) a whole cycle through the real run-phase.sh, in English and in Italian: the same phases, the same end
#  12 (1.5.1) the internal readers of cycle-state.sh in the real run-phase.sh: a STOP of its wrapper is a STOP outcome
#     or a phase not launched, never an OK outcome with state= empty (end of a phase, start and review of a ring, closing)
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
unset FIC_DRIVER FIC_DRIVER_PY FIC_RUN_PHASE FIC_CONTEXT_PACK FIC_MAX_FASI FIC_REPO FIC_LOCK
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi; }
drv() { "$FIC_PY" "$DRV" "$@"; }

# --- 1. usage ---
drv >/dev/null 2>&1; rc=$?; check "senza comando → 2" '[ $rc -eq 2 ]'
drv next "$T/non-esiste.md" >/dev/null 2>&1; rc=$?; check "next su una spec assente → 2" '[ $rc -eq 2 ]'
drv run >/dev/null 2>&1; rc=$?; check "run senza spec → 2" '[ $rc -eq 2 ]'
drv valida a b >/dev/null 2>&1; rc=$?; check "valida con argomenti sbagliati → 2" '[ $rc -eq 2 ]'

# --- 2. valida: the cases of the internal validator of run-phase.sh up to 1.5.1, with their content checks (1.6.0: the
# byte-for-byte comparison with `run-phase.sh --valida` is gone with it; every branch is in tools/esempi-equiv/attese/) ---
SCHEMA=$ROOT/schemas/phase-result.schema.json
ok_json() { # $1 phase, $2 esito, $3 deviazioni, $4 bloccato_su
  printf '{"fase":"%s","esito":"%s","motivo":"finto","deviazioni":%s,"bloccato_su":"%s","file":[],"gate_interni":[],"finding":[]}' "$1" "$2" "$3" "$4"
}
V=$T/valida; mkdir -p "$V"
vcase() { # $1 name, $2 phase, $3 log content · prints the driver output to $V/$1.out (result.json: $V/$1.b.json)
  printf '%s\n' "$3" > "$V/$1.jsonl"
  rm -f "$V/$1.b.json"
  drv valida "$V/$1.jsonl" "$SCHEMA" "$2" "$V/$1.b.json" > "$V/$1.out" 2> "$V/$1.b.err"
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

# --- throwaway repo for wrappers, run and impronta ---
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

# --- 3. wrappers (1.6.0): the driver is the only engine; FIC_DRIVER (0, 1, anything) changes nothing and the wrappers
# say nothing about it (the AVVISO is driver.py run's, section 4). No fallback on error: no Python, a Python older than
# 3.10 or a driver that fails give ONE line `Next: STOP — <reason>`, exit 0, no State: (the marker of the internal
# readers of run-phase.sh, section 12). Counterproofs on a copy of the plugin (CX), each mutation in a file of its own
# or put back after.
cat > "$T/finto-drv.py" <<'EOF'
import os, sys
open(os.environ["SPY"], "a").write(" ".join(sys.argv[1:2]) + "\n")
if os.environ.get("FINTO_ESCE"):
    sys.stderr.write("rumore\nerrore finto\n\n")
    sys.exit(int(os.environ["FINTO_ESCE"]))
if os.environ.get("FINTO_SENZA_NEXT"):   # exit 0 with no Next: line (D3)
    sys.stderr.write("avviso finto senza Next\n")
    sys.stdout.buffer.write("Plan status: finto\nState: 000000000000\n".encode("utf-8"))
    sys.exit(0)
sys.stdout.buffer.write("Plan status: finto\nState: 000000000000\nNext: FINTO — dal driver\n".encode("utf-8"))
EOF
export SPY=$T/spy
# fake interpreter: answers $PY_VER to the version question of python.sh only, hands every other call to the real one
cat > "$T/py-ver" <<EOF
#!/usr/bin/env bash
case "\$*" in *version_info*) echo "\$PY_VER"; exit 0 ;; esac
exec "$FIC_PY" "\$@"
EOF
chmod +x "$T/py-ver"
cs() { # [variables]: cycle-state.sh (CSX: a variant) on the spec with the fake driver · stdout in out, stderr in $T/cs.err, exit in csrc
  rm -f "$SPY"
  out=$(env FIC_DRIVER_PY="$T/finto-drv.py" "$@" bash "${CSX:-$FC/cycle-state.sh}" "$SP" 2>"$T/cs.err"); csrc=$?
  out=${out//$'\r'/}
}
dal_driver() { [ "$csrc" -eq 0 ] && printf '%s\n' "$out" | grep -qx "Next: FINTO — dal driver" && grep -qx next "$SPY" 2>/dev/null; }
stop1() { # $1 = the expected start of the text after «Next: STOP — »: exit 0, that single line (no State:, no table)
  [ "$csrc" -eq 0 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && case "$out" in "Next: STOP — $1"*) true ;; *) false ;; esac
}
cs FIC_DRIVER=1
check "cycle-state.sh, FIC_DRIVER=1 → risponde il driver" 'dal_driver'
cs FIC_DRIVER=0
check "cycle-state.sh, FIC_DRIVER=0 (1.6.0: non ha piu' effetto) → risponde il driver, stderr vuoto (l'involucro tace)" 'dal_driver && [ ! -s "$T/cs.err" ]'
cs FIC_DRIVER=
check "  FIC_DRIVER vuota → il driver" 'dal_driver'
cs FIC_DRIVER=si
check "  FIC_DRIVER=si → il driver, nessun AVVISO su stderr (l'AVVISO e' solo di driver.py run, sezione 4)" 'dal_driver && [ ! -s "$T/cs.err" ]'
# with the real driver: FIC_DRIVER unset, 0, 1, si, empty give the same output byte for byte, and nothing on stderr
csv() { env "$@" bash "${CSX:-$FC/cycle-state.sh}" "$SP" 2>"$T/csv.err" | tr -d '\r'; [ ! -s "$T/csv.err" ]; }
csv_uguali() { local a b v; a=$(csv -u FIC_DRIVER) || return 1; [ -n "$a" ] || return 1
  for v in 0 1 si ''; do b=$(csv FIC_DRIVER="$v") || return 1; [ "$a" = "$b" ] || return 1; done; }
check "  col driver vero: FIC_DRIVER non impostata, 0, 1, si, vuota → la stessa uscita byte per byte, stderr vuoto" 'csv_uguali'
cs FINTO_ESCE=1
check "  driver fallito (exit 1) → «Next: STOP — driver.py next non riuscito (exit 1): <ultima riga del suo stderr> …», e l'uscita e' quella sola riga" 'stop1 "driver.py next non riuscito (exit 1): errore finto — dalla Maat 1.6.0 non c" && [ "$out" = "Next: STOP — driver.py next non riuscito (exit 1): errore finto — dalla Maat 1.6.0 non c'"'"'e'"'"' un altro motore (la tabella bash e'"'"' nella Maat 1.5.1)" ]'
check "  e lo stderr intero del driver (non solo l'ultima riga) passa sullo stderr di cycle-state.sh (come valida, B.4)" 'grep -qx rumore "$T/cs.err" && grep -qx "errore finto" "$T/cs.err"'
cs FINTO_SENZA_NEXT=1
check "  driver con exit 0 ma senza riga Next: (D3) → «Next: STOP — driver.py next non riuscito (exit 0): <ultima riga del suo stderr> …», una riga sola" 'stop1 "driver.py next non riuscito (exit 0): avviso finto senza Next — dalla Maat 1.6.0" && grep -qx "avviso finto senza Next" "$T/cs.err"'
NOPY="nessun Python utilizzabile (FIC_PYTHON, py -3, python3, python): imposta FIC_PYTHON=<python 3.10 o successivo>"
cs FIC_PYTHON="$T/non-esiste.exe"
check "  Python assente (FIC_PYTHON verso un file inesistente: vince su PATH) → «Next: STOP — nessun Python utilizzabile …», il driver mai chiamato" '[ "$out" = "Next: STOP — $NOPY" ] && stop1 "nessun" && [ ! -f "$SPY" ]'
cs FIC_DRIVER=0 FIC_PYTHON="$T/non-esiste.exe"
check "  lo stesso con FIC_DRIVER=0: nessuna via salta il controllo di Python" '[ "$out" = "Next: STOP — $NOPY" ] && stop1 "nessun"'
cs FIC_PYTHON="$T/py-ver" PY_VER=3.9
check "  Python 3.9 (finto) → «Next: STOP — Python 3.9 (<percorso>) e' precedente a 3.10 …», il driver mai chiamato" 'stop1 "Python 3.9 ($T/py-ver) e" && grep -q "precedente a 3.10, il minimo di Maat: imposta FIC_PYTHON=<python 3.10 o successivo>$" <<< "$out" && [ ! -f "$SPY" ]'
cs FIC_DRIVER=0 FIC_PYTHON="$T/py-ver" PY_VER=3.9
check "  lo stesso con FIC_DRIVER=0: una riga, nessuno State:, nessuna riga della tabella" 'stop1 "Python 3.9 ($T/py-ver) e" && [ ! -f "$SPY" ]'
cs FIC_PYTHON="$T/py-ver" PY_VER=3.10
check "  il confine: Python 3.10 (finto) passa il controllo → il driver" 'dal_driver'
check "  il testo di no_python e dei tre python_old non nomina FIC_DRIVER (il rimedio e' FIC_PYTHON)" '[ "$(awk -F"\t" "\$1 ~ /^(cycle-state-engine\\.no_python|cycle-state-engine\\.python_old|run-phase-engine\\.python_old|driver-engine\\.python_old)\$/" "$FC/lib/messages.tsv" | grep -c .)" = 4 ] && ! awk -F"\t" "\$1 ~ /^(cycle-state-engine\\.no_python|cycle-state-engine\\.python_old|run-phase-engine\\.python_old|driver-engine\\.python_old)\$/" "$FC/lib/messages.tsv" | grep -q FIC_DRIVER'
# python.sh from an includer with and without pipefail (no pipe in the verdict, Blocco A): the same rc in both modes;
# a broken interpreter leaves FIC_PY_VER empty, also when FIC_PY_VER=3.12 comes from the environment
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/py-rotto"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/py-muto"; chmod +x "$T/py-rotto" "$T/py-muto"
mkdir -p "$T/vuoto"
pysh() { # $1 = python.sh to include, then env arguments → «rc=<n> ver=<FIC_PY_VER>» once without and once with pipefail
  local p=$1 m; shift
  for m in "set -u" "set -uo pipefail"; do
    env "$@" "$BASH" -c "$m"'; . "$1"; echo "rc=$? ver=${FIC_PY_VER-}"' _ "$p" | tr -d '\r'
  done | tr '\n' ' '
}
py_casi() { # $1 = python.sh: 0 if the five cases hold
  local r
  r=$(pysh "$1")
  [[ $r =~ ^rc=0\ ver=([0-9]+\.[0-9]+)\ rc=0\ ver=([0-9]+\.[0-9]+)\ $ ]] && [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ] || return 1
  [ "$(pysh "$1" FIC_PY_VER=3.12 FIC_PYTHON="$T/non-esiste.exe")" = "rc=1 ver= rc=1 ver= " ] || return 1
  [ "$(pysh "$1" FIC_PY_VER=3.12 FIC_PYTHON="$T/py-rotto")" = "rc=1 ver= rc=1 ver= " ] || return 1
  [ "$(pysh "$1" -u FIC_PYTHON FIC_PY_VER=3.12 PATH="$T/vuoto")" = "rc=1 ver= rc=1 ver= " ] || return 1
  [ "$(pysh "$1" FIC_PY_VER=3.12 FIC_PYTHON="$T/py-muto")" = "rc=0 ver= rc=0 ver= " ]
}
check "python.sh senza e con pipefail: interprete buono rc=0 e la versione; inesistente, import fallito, nessun interprete rc=1 e FIC_PY_VER vuota (anche se 3.12 ereditata); exit 0 muto rc=0 senza versione" 'py_casi "$FC/python.sh"'
mins() { "$BASH" -c '. "$1"; for v in 3.9 3.10 3.11 4.0 3.1 x; do FIC_PY_VER=$v; fic_py_min_ok && printf "%s:si " $v || printf "%s:no " $v; done' _ "$1"; }
check "soglie coincidenti (D12): 3.10 in python.sh (fic_py_min_ok) e in driver.py (PY_MIN); maat-doctor.sh usa fic_py_min_ok (1.6.0), nessuna soglia sua" '[ "$(mins "$FC/python.sh")" = "3.9:no 3.10:si 3.11:si 4.0:si 3.1:no x:no " ] && grep -qx "PY_MIN = (3, 10)" "$DRV" && grep -q "^elif ! fic_py_min_ok; then" "$FC/maat-doctor.sh" && ! grep -q "ver_ge \"\$pyv\"" "$FC/maat-doctor.sh"'
# the texts of the catalog too (review): every <major>.<minor> in a message about Python (cycle-state-engine,
# run-phase-engine, maat-doctor, guard-hook, in it and en) is PY_MIN; driver-engine.python_old takes it as {min}
pymin=$(sed -n 's/^PY_MIN = (\([0-9]*\), \([0-9]*\))$/\1.\2/p' "$DRV")
pyver_cat=$(grep -i python "$FC/lib/messages.tsv" | grep -oE '(^|[^0-9.])[0-9]+\.[0-9]+([^0-9.]|$)' | grep -oE '[0-9]+\.[0-9]+' | sort -u)
check "  e i testi del catalogo: ogni versione nei messaggi su Python e' PY_MIN ($pymin), nelle righe di cycle-state-engine, run-phase-engine e maat-doctor; driver-engine.python_old usa {min}" '[ -n "$pymin" ] && [ "$pyver_cat" = "$pymin" ] && (for k in cycle-state-engine.no_python cycle-state-engine.python_old run-phase-engine.python_old maat-doctor.python_old; do [ "$(awk -F"\t" -v k=$k "\$1 == k { print \$2 \"\n\" \$3 }" "$FC/lib/messages.tsv" | grep -cF "$pymin")" = 2 ] || exit 1; done) && awk -F"\t" "\$1 == \"driver-engine.python_old\"" "$FC/lib/messages.tsv" | grep -q "older than {min}.*precedente a {min}"' "$pyver_cat"
# counterproofs on a copy of the plugin: mut <pair> <source> <dest> replaces exactly one line (line 1 of the pair file,
# CR ignored) with the other lines of the pair file
mut() {
  awk 'FNR == NR { if (FNR == 1) a = $0; else b = b (b == "" ? "" : "\n") $0; next }
       { l = $0; sub(/\r$/, "", l) } l == a { print b; n++; next } { print } END { exit n != 1 }' "$1" "$2" > "$3"
}
CX="$T/plug-cx/maat"; CXS=$CX/scripts; mkdir -p "$T/plug-cx" && cp -r "$ROOT" "$CX" && find "$CX" -name __pycache__ -type d -prune -exec rm -rf {} +
# (1) another engine put back with FIC_DRIVER=0 (the 1.5.1 switch, here a fixed answer) · (2) the wrapper that warns
# about FIC_DRIVER on its stderr (1.5.1 did it for an unknown value)
cat > "$T/m1" <<'EOF'
fic_py_min_ok || { echo "Next: STOP — $(msg cycle-state-engine.python_old v="$FIC_PY_VER" py="$FIC_PY")"; exit 0; }
fic_py_min_ok || { echo "Next: STOP — $(msg cycle-state-engine.python_old v="$FIC_PY_VER" py="$FIC_PY")"; exit 0; }
[ "${FIC_DRIVER:-}" = 0 ] && { printf 'State: 000000000001\nNext: IMPLEMENT — un altro motore\n'; exit 0; }  # MOTORE-RIMESSO
EOF
cat > "$T/m2" <<'EOF'
fic_py_min_ok || { echo "Next: STOP — $(msg cycle-state-engine.python_old v="$FIC_PY_VER" py="$FIC_PY")"; exit 0; }
fic_py_min_ok || { echo "Next: STOP — $(msg cycle-state-engine.python_old v="$FIC_PY_VER" py="$FIC_PY")"; exit 0; }
[ -n "${FIC_DRIVER:-}" ] && echo "AVVISO: FIC_DRIVER=$FIC_DRIVER" >&2  # AVVISO-INVOLUCRO
EOF
# (2b) the stderr of the failed driver dropped again (only its last line, in the STOP) · (2c) exit 0 enough, no Next: asked
cat > "$T/m2b" <<'EOF'
[ -n "$derr" ] && printf '%s\n' "$derr" >&2
:  # STDERR-SCARTATO
EOF
cat > "$T/m2c" <<'EOF'
if [ "$drc" = 0 ] && grep -q '^Next: ' <<< "$dout"; then printf '%s\n' "$dout"; exit 0; fi
if [ "$drc" = 0 ]; then printf '%s\n' "$dout"; exit 0; fi  # NEXT-NON-CHIESTO
EOF
check "controprove degli involucri: le mutazioni sono applicate" 'mut "$T/m1" "$CXS/cycle-state.sh" "$CXS/cs-motore.sh" && mut "$T/m2" "$CXS/cycle-state.sh" "$CXS/cs-avviso.sh" && mut "$T/m2b" "$CXS/cycle-state.sh" "$CXS/cs-scarta.sh" && mut "$T/m2c" "$CXS/cycle-state.sh" "$CXS/cs-senzanext.sh" && grep -q MOTORE-RIMESSO "$CXS/cs-motore.sh" && grep -q AVVISO-INVOLUCRO "$CXS/cs-avviso.sh" && grep -q STDERR-SCARTATO "$CXS/cs-scarta.sh" && grep -q NEXT-NON-CHIESTO "$CXS/cs-senzanext.sh"'
CSX="$CXS/cs-motore.sh" cs FIC_DRIVER=0
check "controprova: cycle-state.sh con un altro motore per FIC_DRIVER=0 → non risponde il driver (il caso «FIC_DRIVER=0 → il driver» e' rosso)" '! dal_driver && printf "%s\n" "$out" | grep -qx "Next: IMPLEMENT — un altro motore"'
check "  e col driver vero l'uscita con FIC_DRIVER=0 cambia (il caso «la stessa uscita byte per byte» e' rosso)" '! CSX="$CXS/cs-motore.sh" csv_uguali'
CSX="$CXS/cs-avviso.sh" cs FIC_DRIVER=si
check "controprova: cycle-state.sh che avvisa di FIC_DRIVER su stderr → il caso «FIC_DRIVER=si, nessun AVVISO» e' rosso (risponde sempre il driver)" 'dal_driver && grep -qx "AVVISO: FIC_DRIVER=si" "$T/cs.err"'
CSX="$CXS/cs-scarta.sh" cs FINTO_ESCE=1
check "controprova: cycle-state.sh che scarta lo stderr del driver → «rumore» non c'e' su stderr (il caso dello stderr intero e' rosso), lo STOP resta" 'stop1 "driver.py next non riuscito (exit 1): errore finto" && ! grep -qx rumore "$T/cs.err"'
CSX="$CXS/cs-senzanext.sh" cs FINTO_SENZA_NEXT=1
check "controprova: cycle-state.sh senza il grep di Next: → passa l'uscita del driver senza Next: (il caso D3 e' rosso)" '! stop1 "driver.py next non riuscito (exit 0)" && printf "%s\n" "$out" | grep -qx "State: 000000000000" && ! printf "%s\n" "$out" | grep -q "^Next: "'
# (3) python.sh with «> 3.10» and (4) without capturing the version: mutated in the copy and put back
cp "$CXS/python.sh" "$T/python.sh.orig"
sed 's/\[ "\$mi" -ge 10 \]/[ "$mi" -gt 10 ]/' "$T/python.sh.orig" > "$CXS/python.sh"   # in mid-line: no marker comment
CSX="$CXS/cycle-state.sh" cs FIC_PYTHON="$T/py-ver" PY_VER=3.10
check "controprova: python.sh con «> 3.10» → il confine 3.10 da' STOP python_old (il caso del confine e' rosso)" 'grep -qF "[ \"\$mi\" -gt 10 ]" "$CXS/python.sh" && ! dal_driver && stop1 "Python 3.10"'
sed 's/FIC_PY_VER=\$("\$FIC_PY" -c .import json, shlex, sys; print("%d.%d" % sys.version_info\[:2\]). 2>\/dev\/null)$/"$FIC_PY" -c "import json, shlex" 2>\/dev\/null  # VERSIONE-NON-CATTURATA/' "$T/python.sh.orig" > "$CXS/python.sh"
# Expected: with FIC_PY_VER never set, the `then` branch of python.sh reads it and the `set -u` of cycle-state.sh stops
# the wrapper there, with no output and an exit other than 0 (the error goes to the 2>/dev/null of the `.`). That is
# what makes the two cases red, and it is asserted as such: no «Python 3.9» STOP, no answer of the driver, nothing.
CSX="$CXS/cycle-state.sh" cs FIC_PYTHON="$T/py-ver" PY_VER=3.9; vecchio=$out vecchio_rc=$csrc
CSX="$CXS/cycle-state.sh" cs FIC_PYTHON="$T/py-ver" PY_VER=3.10
check "controprova: python.sh che non imposta FIC_PY_VER → cycle-state.sh si ferma per set -u, uscita vuota ed exit diverso da 0, sia per 3.9 sia per il confine 3.10 (i due casi rossi)" 'grep -q VERSIONE-NON-CATTURATA "$CXS/python.sh" && [ -z "$vecchio" ] && [ "$vecchio_rc" -ne 0 ] && [ -z "$out" ] && [ "$csrc" -ne 0 ] && [ ! -f "$SPY" ]'
# (5) python.sh that does not empty FIC_PY_VER in the else branch → the inherited 3.12 survives with no interpreter
sed 's/^else FIC_PY_VER=""; false; fi$/else false; fi  # NON-AZZERA/' "$T/python.sh.orig" > "$CXS/python.sh"
check "controprova: python.sh che non azzera FIC_PY_VER nel ramo else → il caso «3.12 ereditata» e' rosso" 'grep -q NON-AZZERA "$CXS/python.sh" && ! py_casi "$CXS/python.sh" && [ "$(pysh "$CXS/python.sh" -u FIC_PYTHON FIC_PY_VER=3.12 PATH="$T/vuoto")" = "rc=1 ver=3.12 rc=1 ver=3.12 " ]'
cp "$T/python.sh.orig" "$CXS/python.sh"
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
rp() { # $1 = FIC_DRIVER, $2 = label · stderr of run-phase.sh in $T/rp.err
  rm -f "$SPY"
  FIC_DRIVER=$1 FIC_DRIVER_PY="$T/spia-drv.py" FIC_LOCK="$T/lock" FIC_REPO="$W" CLAUDE_BIN="$T/claude" FIC_GATES="$T/gates" \
    FIC_FINALIZE="$T/non-esiste" FIC_LANES=0 bash "$FC/run-phase.sh" "$T/rp.run" "$2" "$T/prompt.md" >/dev/null 2>"$T/rp.err" </dev/null
}
rp 1 01-implement
check "run-phase.sh, FIC_DRIVER=1: esito validato dal driver (spia) → STOP «uscita non valida»" 'grep -qx valida "$SPY" && sed -n 1p "$T/rp.run/log/01-implement.esito" | grep -q "^PHASE RESULT implement: STOP — uscita non valida: .*FORSE"'
rp 0 02-implement
check "run-phase.sh, FIC_DRIVER=0 (1.6.0: non ha piu' effetto): valida il driver (spia), stesso esito, nessun AVVISO su FIC_DRIVER (l'involucro tace)" 'grep -qx valida "$SPY" && [ "$(sed -n 1p "$T/rp.run/log/01-implement.esito")" = "$(sed -n 1p "$T/rp.run/log/02-implement.esito")" ] && ! grep -q "FIC_DRIVER" "$T/rp.err"'
# 1.5.1: a spy by mode (SPIA_MODO): next1 = exit 1 on `next` only, valida1 = writes result.json then exit 1 on `valida`
# only; every other call goes to the real driver (also used by section 12)
cat > "$T/spia-modi.py" <<EOF
import os, runpy, sys
m = os.environ.get("SPIA_MODO", "")
open(os.environ["SPY"], "a").write(sys.argv[1] + "\n")
if m == "next1" and sys.argv[1] == "next":
    sys.stderr.write("rumore\nTraceback finto: next rotto\n\n")
    sys.exit(1)
if m == "valida1" and sys.argv[1] == "valida":
    open(sys.argv[5], "w").write("{}")
    sys.stderr.write("valida rotta\n")
    sys.exit(1)
sys.argv = [r"$(cygpath -w "$DRV" 2>/dev/null || echo "$DRV")"] + sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
EOF
rpe() { # $1 label, then variables: run-phase.sh (RPX: a variant) on $T/rp.run (RPD: another run dir), spy by mode
  local l=$1; shift; rm -f "$SPY"
  env FIC_DRIVER_PY="$T/spia-modi.py" FIC_LOCK="$T/lock" FIC_REPO="$W" CLAUDE_BIN="$T/claude" FIC_GATES="$T/gates" \
    FIC_FINALIZE="$T/non-esiste" FIC_LANES=0 "$@" bash "${RPX:-$FC/run-phase.sh}" "${RPD:-$T/rp.run}" "$l" "$T/prompt.md" >/dev/null 2>&1 </dev/null
}
valida_ko() { # $1 run dir, $2 label: the outcome of a driver whose valida failed, and no result.json
  sed -n 1p "$1/log/$2.esito" | grep -qx "PHASE RESULT implement: STOP — driver.py valida non riuscito (exit 1): valida rotta — dalla Maat 1.6.0 non c.e. un altro motore (il validatore interno e. nella Maat 1.5.1)" && [ ! -f "$1/log/$2.result.json" ]
}
rpe 06-implement SPIA_MODO=valida1
check "run-phase.sh, driver valida fallito (exit 1, result.json scritto a meta') → .esito «PHASE RESULT implement: STOP — driver.py valida non riuscito …» e nessun result.json" 'grep -qx valida "$SPY" && valida_ko "$T/rp.run" 06-implement'
rpe 07-implement FIC_DRIVER=0 FIC_PYTHON="$T/py-ver" PY_VER=3.9
check "  FIC_DRIVER=0 e Python 3.9 (finto) → .esito «PHASE RESULT implement: STOP — Python 3.9 … precedente a 3.10 …», driver mai chiamato" 'sed -n 1p "$T/rp.run/log/07-implement.esito" | grep -q "^PHASE RESULT implement: STOP — Python 3.9 (.*) e. precedente a 3.10, il minimo di Maat" && [ ! -f "$SPY" ] && [ ! -f "$T/rp.run/log/07-implement.result.json" ]'
rm -f "$SPY" "$T/vv.json"
FIC_DRIVER_PY="$T/spia-modi.py" bash "$FC/run-phase.sh" --valida "$V/valido.jsonl" "$SCHEMA" implement "$T/vv.json" > "$T/vv.out" 2>&1; rc=$?
check "  1.6.0: run-phase.sh --valida non c'e' piu' (il validatore interno e' tolto) → uso, exit 2, nessuna validazione (spia muta, nessun result.json)" '[ $rc -eq 2 ] && [ ! -f "$SPY" ] && [ ! -f "$T/vv.json" ] && ! grep -q "ESITO FASE" "$T/vv.out"'
# counterproof: run-phase.sh without the rm -f of the result.json (copy CX, its own run dir: another fingerprint)
cat > "$T/m3" <<'EOF'
  rm -f "$4"
  :  # RM-TOLTO
EOF
check "controprova: la mutazione e' applicata (run-phase.sh senza rm -f del result.json)" 'mut "$T/m3" "$CXS/run-phase.sh" "$CXS/rp-norm.sh" && grep -q RM-TOLTO "$CXS/rp-norm.sh"'
RPX="$CXS/rp-norm.sh" RPD="$T/rpx.run" rpe 01-implement SPIA_MODO=valida1
check "controprova: senza rm -f il result.json del driver fallito resta (il caso «nessun result.json» e' rosso)" '! valida_ko "$T/rpx.run" 01-implement && [ -f "$T/rpx.run/log/01-implement.result.json" ]'

# --- 4. run: the state machine, with fake run-phase.sh and context-pack.sh ---
cat > "$T/rp-finto" <<'EOF'
#!/usr/bin/env bash
# fake run-phase.sh: <run-dir> <label> <prompt>; FAKE_MODE chooses what the "phase" does
d=$1 l=$2; mkdir -p "$d/log"; echo "$l" >> "$FAKE_CALLS"; spec="${d%.run}.md"
st() { bash "$FC/cycle-state.sh" "$spec" 2>/dev/null | sed -n 's/^State: //p'; }
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
# M1 (1.6.0): FIC_CYCLE_STATE (tests) replaces our own `next` in run, as FIC_RUN_PHASE replaces run-phase.sh (here a
# fake one that answers differently), whatever FIC_DRIVER says. FIC_DRIVER set (not empty) → one AVVISO per invocation
# of run, on its output and in driver.log; unset or empty → none.
printf '#!/usr/bin/env bash\necho "Plan status: finto"; echo "State: 000000000000"; echo "Next: STOP — finto da cycle-state"\n' > "$T/cs-finto"; chmod +x "$T/cs-finto"
csrun() { # [variables]: run with FIC_CYCLE_STATE = the fake → rc, output in $T/run.out
  rm -rf "$RUN"; spec_approved; : > "$FAKE_CALLS"
  env "$@" FIC_CYCLE_STATE="$T/cs-finto" FAKE_MODE=nulla FIC_RUN_PHASE="$T/rp-finto" FIC_CONTEXT_PACK=- "$FIC_PY" "${DRUN_DRV:-$DRV}" run "$SP" > "$T/run.out" 2>&1; rc=$?
}
AVV="non ha piu. effetto: decide il driver Python (per il motore bash, reinstallare la Maat 1.5.1)"
navv() { grep -c "AVVISO: FIC_DRIVER=$1 $AVV" "$2"; }   # $1 value, $2 file: how many AVVISO lines
csrun
check "run: FIC_CYCLE_STATE → segue il finto (il finto dice STOP), FIC_DRIVER non impostata → nessun AVVISO" '[ $rc -eq 1 ] && grep -q "Driver result: STOP — STOP — finto da cycle-state" "$T/run.out" && ! grep -q "AVVISO" "$T/run.out" "$RUN/driver.log" && [ "$(calls)" = 0 ]'
csrun FIC_DRIVER=
check "  FIC_DRIVER vuota (il predefinito di 1.5.1) → nessun AVVISO" '[ $rc -eq 1 ] && ! grep -q "AVVISO" "$T/run.out" "$RUN/driver.log"'
csrun FIC_DRIVER=0
check "  FIC_DRIVER=0 → il finto lo stesso (nessun motore bash), un AVVISO «FIC_DRIVER=0 non ha piu' effetto …» sull'uscita e nel driver.log" '[ $rc -eq 1 ] && grep -q "Driver result: STOP — STOP — finto da cycle-state" "$T/run.out" && [ "$(navv 0 "$T/run.out")" = 1 ] && [ "$(navv 0 "$RUN/driver.log")" = 1 ]'
csrun FIC_DRIVER=xyz
check "  FIC_DRIVER=xyz → un AVVISO con quel valore" '[ $rc -eq 1 ] && [ "$(navv xyz "$T/run.out")" = 1 ]'
csrun FIC_DRIVER=1 MAAT_LINGUA=en
check "  FIC_DRIVER=1 in inglese → «AVVISO: FIC_DRIVER=1 no longer has any effect: the Python driver decides (for the bash engine, reinstall Maat 1.5.1)»" '[ $rc -eq 1 ] && [ "$(grep -c "AVVISO: FIC_DRIVER=1 no longer has any effect: the Python driver decides (for the bash engine, reinstall Maat 1.5.1)" "$T/run.out")" = 1 ]'
FIC_DRIVER=0 drun avanza "$SP"
check "  FIC_DRIVER=0 su un ciclo intero (implement → review → DONE, tre giri del ciclo) → DONE come senza, un AVVISO solo, sull'uscita e nel driver.log" '[ $rc -eq 0 ] && grep -q "Driver result: DONE" "$T/run.out" && [ "$(tr "\n" " " < "$FAKE_CALLS")" = "01-implement 02-review " ] && [ "$(navv 0 "$T/run.out")" = 1 ] && [ "$(navv 0 "$RUN/driver.log")" = 1 ]'
# counterproofs on copies of driver.py: the AVVISO removed (the case «FIC_DRIVER=0 → un AVVISO» red); the AVVISO at
# every round of the loop too (the case «un AVVISO solo» red)
sed 's/^    if fd:$/    if False:  # AVVISO-TOLTO/' "$DRV" > "$T/drv-noavviso.py"
sed 's/^    while True:$/&\n        if fd: ev("AVVISO: " + T("driver-engine.fic_driver_tolta", v=fd))  # AVVISO-A-OGNI-GIRO/' "$DRV" > "$T/drv-avvisi.py"
check "controprove AVVISO: le due mutazioni sono applicate" 'grep -q "AVVISO-TOLTO" "$T/drv-noavviso.py" && grep -q "AVVISO-A-OGNI-GIRO" "$T/drv-avvisi.py"'
DRUN_DRV="$T/drv-noavviso.py" csrun FIC_DRIVER=0
check "controprova: driver senza l'AVVISO → il caso «FIC_DRIVER=0 → un AVVISO» e' rosso" '[ $rc -eq 1 ] && [ "$(navv 0 "$T/run.out")" = 0 ]'
FIC_DRIVER=0 DRUN_DRV="$T/drv-avvisi.py" drun avanza "$SP"
check "controprova: driver con l'AVVISO a ogni giro → il caso «un AVVISO solo» e' rosso (piu' di uno)" '[ $rc -eq 0 ] && [ "$(navv 0 "$T/run.out")" -gt 1 ]'
# D2: the Python check of run comes first (there is no other engine); a copy of driver.py with the threshold (99, 0)
# stops at once
sed 's/^PY_MIN = (3, 10)$/PY_MIN = (99, 0)  # SOGLIA-99/' "$DRV" > "$T/drv-py99.py"
check "controprova soglia: la mutazione e' applicata (PY_MIN = (99, 0))" 'grep -q "SOGLIA-99" "$T/drv-py99.py"'
DRUN_DRV="$T/drv-py99.py" drun nulla "$SP"
check "run: driver con la soglia (99, 0) → «Driver result: STOP — Python … e' precedente a 99.0 …», exit 1, nessun lancio" '[ $rc -eq 1 ] && grep -q "Driver result: STOP — Python [0-9]*\.[0-9]* (.*) e. precedente a 99\.0, il minimo di Maat: imposta FIC_PYTHON=<python 99\.0 o successivo>" "$T/run.out" && [ "$(calls)" = 0 ]'
export FIC_DRIVER=0; DRUN_DRV="$T/drv-py99.py" drun nulla "$SP"; unset FIC_DRIVER
check "  lo stesso con FIC_DRIVER=0: lo STOP di Python viene prima dell'AVVISO (nessun AVVISO)" '[ $rc -eq 1 ] && grep -q "Driver result: STOP — Python [0-9]*\.[0-9]* (.*) e. precedente a 99\.0" "$T/run.out" && ! grep -q "AVVISO" "$T/run.out" && [ "$(calls)" = 0 ]'
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
crun() { : > "$FAKE_CALLS"; FAKE_MODE=nulla FIC_RUN_PHASE="$T/rp-finto" FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$1" > "$T/run.out" 2>&1; rc=$?; }
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

# --- 5. the corpus fingerprint (1.6.0: `driver.py impronta`, up to 1.5.1 `equiv --impronta`; equiv and the certificate
# are gone, the proof is on the expected outputs of tools/esempi-equiv/attese/). A run dir with logs, so that .claude/ is
# walked ---
rm -rf "$RUN"; spec_approved; mkdir -p "$RUN/log"
printf '%s
' '{"type":"result","result":"ESITO FASE implement: OK","structured_output":{"fase":"implement","esito":"OK","motivo":"m","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}' > "$RUN/log/01-implement.jsonl"
printf '%s
' '{"type":"result","result":"ESITO FASE review: OK"}' > "$RUN/log/02-review.jsonl"
drv impronta > "$T/imp0.out" 2>&1; rc1=$?
drv impronta --altro .claude/.ai-workflow > "$T/imp0.out" 2>&1; rc2=$?
drv impronta "$T/non-esiste" > "$T/imp0.out" 2>&1; rc3=$?
check "impronta: senza argomenti o con un'opzione → uso (exit 2); un percorso assente → exit 2 «driver.py impronta: non trovato: <percorso>»" '[ $rc1 -eq 2 ] && [ $rc2 -eq 2 ] && [ $rc3 -eq 2 ] && grep -qx "driver.py impronta: non trovato: $T/non-esiste" "$T/imp0.out"'
check "  la cartella del repo → 64 cifre esadecimali, exit 0" '[[ $(drv impronta .claude/.ai-workflow 2>/dev/null) =~ ^[0-9a-f]{64}$ ]]'

# 1.5.0 (D3): the corpus fingerprint, no proof. On a copy of the repo with the same name elsewhere.
# imp_*: 0 if the property holds for driver $1
IMP_A=$T/altrove/repo; mkdir -p "$T/altrove"; cp -r "$W" "$IMP_A"
imp() { "$FIC_PY" "$1" impronta "$2" 2>/dev/null; }
imp_altrove() { local a b; a=$(imp "$1" "$W/.claude/.ai-workflow"); b=$(imp "$1" "$IMP_A/.claude/.ai-workflow"); [[ $a =~ ^[0-9a-f]{64}$ ]] && [ "$a" = "$b" ]; }
imp_byte() { # $2 file relative to the copy (created if missing, removed after if so), $3 content, $4 the same with one byte changed
  local a b f=$IMP_A/$2 c=; [ -e "$f" ] || c=1
  mkdir -p "$(dirname "$f")"; printf '%s' "$3" > "$f"; a=$(imp "$1" "$IMP_A/.claude/.ai-workflow")
  printf '%s' "$4" > "$f"; b=$(imp "$1" "$IMP_A/.claude/.ai-workflow")
  if [ -n "$c" ]; then rm -f "$f"; else printf '%s' "$3" > "$f"; fi
  [[ $a =~ ^[0-9a-f]{64}$ ]] && [[ $b =~ ^[0-9a-f]{64}$ ]] && [ "$a" != "$b" ]
}
check "impronta: stessa cartella in un altro percorso (stesso nome) → stessa impronta" 'imp_altrove "$DRV"'
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
check "  il CR non conta (contenuto senza CR)" 'a=$(imp "$DRV" "$IMP_A/.claude/.ai-workflow"); printf "uno\r\n" > "$IMP_A/src/a.py"; b=$(imp "$DRV" "$IMP_A/.claude/.ai-workflow"); printf "uno\n" > "$IMP_A/src/a.py"; [ "$a" = "$b" ]'
# the machine's git configuration does not enter: a global core.excludesFile, and the default ignore file of
# ~/.config/git, that exclude *.py leave an untracked src/nuovo.py in the fingerprint
H2=$T/home-escludi; mkdir -p "$H2/.config/git"; printf '*.py\n' > "$H2/escludi"; printf '*.py\n' > "$H2/.config/git/ignore"
printf '[core]\n\texcludesFile = %s\n' "$(cygpath -m "$H2/escludi" 2>/dev/null || printf '%s' "$H2/escludi")" > "$H2/.gitconfig"
i0=$(imp "$DRV" "$IMP_A/.claude/.ai-workflow"); printf 'nuovo\n' > "$IMP_A/src/nuovo.py"
i1=$(imp "$DRV" "$IMP_A/.claude/.ai-workflow"); i2=$(HOME=$H2 env -u XDG_CONFIG_HOME "$FIC_PY" "$DRV" impronta "$IMP_A/.claude/.ai-workflow" 2>/dev/null)
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

# --- 9. (gone in 1.6.0) the port of cycle-state.test.sh compared the driver with the bash table, which is gone;
# cycle-state.test.sh runs on the driver by itself ---

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
lrun() { rm -f "$FAKE_CALLS"*; FIC_CYCLE_STATE="$T/cs-review" FIC_RUN_PHASE="$T/rp-mut" FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$SP" > "$T/run.out" 2>&1; }
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
# fake gates and finalize; run-phase.sh and cycle-state.sh the real ones.
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
  MAAT_LINGUA=$1 E2E_SPEC="$W/$SP" FIC_LOCK="$T/lock" FIC_REPO="$W" CLAUDE_BIN="$T/claude-e2e" FIC_GATES="$T/gates" \
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

# --- 12. (1.5.1) the internal readers of cycle-state.sh in the REAL run-phase.sh: the driver fails on `next` only (the
# spy of section 3, SPIA_MODO=next1; `valida` goes to the real driver), so cycle-state.sh answers with the one-line STOP
# of its wrapper, without State:. End of a phase (implement, chiusura) → STOP outcome with state= empty; start and
# review of a ring → phase not launched (exit 7, no .esito, no .running). Fake claude and finalize of section 11, the
# chain of section 4 (mk_catena). Counterproof: the old reading of State: at the end of a phase (copy CX).
lph() { # $1 run dir, $2 label, then variables: run-phase.sh (RPX: a variant) with the spy failing on next → lrc
  local d=$1 l=$2; shift 2; rm -f "$SPY"
  env SPIA_MODO=next1 FIC_DRIVER_PY="$T/spia-modi.py" FIC_LOCK="$T/lock" FIC_REPO="$W" CLAUDE_BIN="$T/claude-e2e" \
    FIC_GATES="$T/gates" FIC_FINALIZE="$T/fin-e2e" FIC_LANES=0 E2E_SPEC="$W/$SP" "$@" \
    bash "${RPX:-$FC/run-phase.sh}" "$d" "$l" "$T/prompt.md" > "$T/lph.out" 2> "$T/lph.err" </dev/null
  lrc=$?
}
fine_stop() { # $1 .esito of an implement: STOP of the wrapper on line 1, state= empty, the computed outcome kept below
  sed -n 1p "$1" | grep -qx "PHASE RESULT implement: STOP — driver.py next non riuscito (exit 1): Traceback finto: next rotto — dalla Maat 1.6.0 non c.e. un altro motore (la tabella bash e. nella Maat 1.5.1)" \
    && grep -qx "state=" "$1" && grep -qx "originale=PHASE RESULT implement: OK — done" "$1"
}
rm -rf "$RUN" "$T/lock"; git checkout -q -- src; spec_approved
lph "$W/$RUN" 01-implement
check "12 (1.5.1) fine di una fase: next del driver fallito → .esito «PHASE RESULT implement: STOP — driver.py next non riuscito …», state= vuoto" '[ $lrc -eq 0 ] && fine_stop "$RUN/log/01-implement.esito"'
check "  nessun gate dopo l'implement (l'esito non e' OK), il result.json di valida c'e', nessuna deviazione registrata" '[ ! -f "$RUN/log/01-implement.gates" ] && [ -f "$RUN/log/01-implement.result.json" ] && grep -qx valida "$SPY" && [ ! -f "$RUN/log/deviazioni-difensive.txt" ]'
rm -rf "$RUN" "$T/lock"; git checkout -q -- src; spec_approved
SPIA_MODO=next1 FIC_DRIVER_PY="$T/spia-modi.py" FIC_LOCK="$T/lock" FIC_REPO="$W" CLAUDE_BIN="$T/claude-e2e" FIC_GATES="$T/gates" \
  FIC_FINALIZE="$T/fin-e2e" FIC_LANES=0 FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$SP" > "$T/lrun.out" 2>&1 </dev/null; rc=$?
check "  driver.py run → «Driver result: STOP — PHASE RESULT implement: STOP — driver.py next …», exit 1, nessun lancio dopo l'implement" '[ $rc -eq 1 ] && grep -q "^driver: Driver result: STOP — PHASE RESULT implement: STOP — driver.py next non riuscito (exit 1): Traceback finto: next rotto" "$T/lrun.out" && [ "$(ls "$RUN/log" | grep -c "\.esito$")" = 1 ] && [ -f "$RUN/log/01-implement.esito" ]'
rm -rf "$RUN" "$T/lock"; git checkout -q -- src
mk_catena; R2=$W/$CW/spec-m-2-b.run/log
lph "$W/$CW/spec-m-2-b.run" 01-implement
check "  inizio di un anello (implement dell'anello 2): exit 7, nessun .esito, nessun .running, «STOP — <motivo> — fase non lanciata», claude non lanciato" '[ $lrc -eq 7 ] && [ ! -f "$R2/01-implement.esito" ] && [ ! -f "$R2/01-implement.running" ] && grep -q "^STOP — driver.py next non riuscito (exit 1): Traceback finto: next rotto — .* — fase non lanciata$" "$R2/01-implement.stderr" && git diff --quiet -- src'
lph "$W/$CW/spec-m-2-b.run" 02-review
check "  review di un anello (anello 2): exit 7, la review non parte, nessun .esito, nessun .running" '[ $lrc -eq 7 ] && [ ! -f "$R2/02-review.esito" ] && [ ! -f "$R2/02-review.running" ] && grep -q "^STOP — driver.py next non riuscito (exit 1): .* — fase non lanciata$" "$R2/02-review.stderr"'
mk_catena; rm -rf "$T/lock"
SPIA_MODO=next1 FIC_DRIVER_PY="$T/spia-modi.py" FIC_LOCK="$T/lock" FIC_REPO="$W" CLAUDE_BIN="$T/claude-e2e" FIC_GATES="$T/gates" \
  FIC_FINALIZE="$T/fin-e2e" FIC_LANES=0 FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run $CW/spec-m.md > "$T/lrun.out" 2>&1 </dev/null; rc=$?
check "  driver.py run sulla madre → l'anello 1 non parte: «Driver result: STOP — catena: <stderr del driver> | STOP — driver.py next …», col motivo (Giro 2; lo stderr intero del driver e' nel .stderr della fase da 1.5.1)" '[ $rc -eq 1 ] && grep -q "^driver: Driver result: STOP — catena: rumore | Traceback finto: next rotto | STOP — driver.py next non riuscito (exit 1): Traceback finto: next rotto" "$T/lrun.out" && [ ! -f $CW/spec-m-1-a.run/log/01-implement.esito ]' "$(grep "Driver result" "$T/lrun.out")"
mk_catena; M=$W/$CW/spec-m.run; mkdir -p $CW/spec-m-1-a.run $CW/spec-m-2-b.run
printf 'src/a.py\n' > $CW/spec-m-1-a.run/touched.txt; printf 'src/a.py\n' > $CW/spec-m-2-b.run/touched.txt
git rev-parse HEAD > $CW/spec-m-1-a.run/base.txt
lph "$M" 01-chiusura
check "  chiusura con i gate verdi: chiusura.txt IMPLEMENTED (non toccato), .esito «PHASE RESULT chiusura: STOP — driver.py next …», state= vuoto" '[ $lrc -eq 0 ] && grep -q "^Chiusura: IMPLEMENTED — base " "$M/chiusura.txt" && sed -n 1p "$M/log/01-chiusura.esito" | grep -q "^PHASE RESULT chiusura: STOP — driver.py next non riuscito (exit 1): " && grep -qx "state=" "$M/log/01-chiusura.esito"'
rm -f $CW/spec-m-1-a.run/base.txt; lph "$M" 02-chiusura
check "  chiusura gia' STOP per un suo motivo (base del primo anello assente) → l'.esito tiene quel motivo, state= vuoto (Giro 2)" 'sed -n 1p "$M/log/02-chiusura.esito" | grep -q "^PHASE RESULT chiusura: STOP — .*base del primo anello assente" && ! grep -q "driver.py next" "$M/log/02-chiusura.esito" && grep -qx "state=" "$M/log/02-chiusura.esito"'
rm -rf $CW/spec-m*.run $CW/spec-m.md $CW/spec-m-1-a.md $CW/spec-m-2-b.md "$T/lock"; git checkout -q -- src
# counterproof: run-phase.sh with the reading of State: of 1.5.0 at the end of a phase (no cycle_state_read): the
# STOP of the wrapper passes and the outcome stays OK with state= empty. Own spec: the copy has another fingerprint
cat > "$T/m4" <<'EOF'
  if [ -n "$esito" ] && [ -f "$sp_md" ]; then cycle_state_read "$sp_md" || cs_stop; fi
  if [ -n "$esito" ] && [ -f "$sp_md" ]; then cso=$(bash "$HERE/cycle-state.sh" "$sp_md" 2>>"$err"); fi  # LETTORE-VECCHIO
EOF
check "controprova lettori: la mutazione e' applicata (run-phase.sh col vecchio sed State: a fine fase)" 'mut "$T/m4" "$CXS/run-phase.sh" "$CXS/rp-lettore.sh" && grep -q LETTORE-VECCHIO "$CXS/rp-lettore.sh"'
spec_approved; cp "$SP" $CW/spec-v.md
RPX="$CXS/rp-lettore.sh" lph "$W/$CW/spec-v.run" 01-implement
check "controprova lettori: col vecchio sed l'.esito resta OK con state= vuoto (il caso «fine di una fase» e' rosso)" '! fine_stop $CW/spec-v.run/log/01-implement.esito && sed -n 1p $CW/spec-v.run/log/01-implement.esito | grep -q "^PHASE RESULT implement: OK" && grep -qx "state=" $CW/spec-v.run/log/01-implement.esito'
rm -rf $CW/spec-v.md $CW/spec-v.run "$T/lock"; git checkout -q -- src
# (1.5.1, review) an outcome already STOP with its own originale= (valida: «uscita non valida», the structured output
# has no esito) and then the STOP of the wrapper: originale= stays the subsession's line, not the STOP of valida.
# Counterproof: cs_stop with originale= = line 1 (copy).
cat > "$T/claude-inv" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo '{"type":"result","result":"PHASE RESULT implement: OK — done","structured_output":{"fase":"implement","motivo":"done"}}'
EOF
chmod +x "$T/claude-inv"
orig_tenuto() { # $1 .esito: the STOP of the wrapper on line 1, one originale=, the subsession's line
  sed -n 1p "$1" | grep -q "^PHASE RESULT implement: STOP — driver.py next non riuscito (exit 1): " &&
    [ "$(grep -c "^originale=" "$1")" = 1 ] && grep -qx "originale=PHASE RESULT implement: OK — done" "$1"
}
rm -rf "$RUN" "$T/lock"; git checkout -q -- src; spec_approved; lph "$W/$RUN" 01-implement CLAUDE_BIN="$T/claude-inv"
check "  12 (review) esito gia' STOP con il suo originale= (valida, uscita non valida), poi next fallito → l'originale= resta la riga della sottosessione" 'orig_tenuto "$RUN/log/01-implement.esito"' "$(cat "$RUN/log/01-implement.esito" 2>/dev/null)"
cat > "$T/m5" <<'EOF'
  cs_stop() { orig=$(printf '%s\n' "$esito" | sed -n 's/^originale=//p' | head -1); [ -n "$orig" ] ||
  cs_stop() { orig=$(printf '%s\n' "$esito" | sed -n '1p'); true ||  # ORIGINALE-RIGA-1
EOF
check "controprova originale=: la mutazione e' applicata (cs_stop con la riga 1)" 'mut "$T/m5" "$CXS/run-phase.sh" "$CXS/rp-orig.sh" && grep -q ORIGINALE-RIGA-1 "$CXS/rp-orig.sh"'
rm -rf "$RUN" "$T/lock"; git checkout -q -- src; spec_approved; cp "$SP" $CW/spec-o.md
RPX="$CXS/rp-orig.sh" lph "$W/$CW/spec-o.run" 01-implement CLAUDE_BIN="$T/claude-inv"
check "controprova originale=: con la riga 1 l'originale= e' lo STOP di valida (il caso e' rosso)" '! orig_tenuto $CW/spec-o.run/log/01-implement.esito && grep -q "^originale=PHASE RESULT implement: STOP" $CW/spec-o.run/log/01-implement.esito' "$(cat $CW/spec-o.run/log/01-implement.esito 2>/dev/null)"
rm -rf $CW/spec-o.md $CW/spec-o.run "$RUN" "$T/lock" "$T/plug-cx"; git checkout -q -- src

cd /
echo "driver.test.sh: $pass passati, $fail falliti"
[ $fail -eq 0 ]
