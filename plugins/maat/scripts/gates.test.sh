#!/usr/bin/env bash
# gates.test.sh — gates.sh su un repository sintetico (cartella temporanea) configurato con l'esempio nuxt-fastapi
# (.claude/maat.json), con WSL, test-fast.sh, node, npm e
# il python del venv FINTI (nessun contatto con la copia WSL reale, HOME temporanea): derivazione dei comandi,
# evidenza JSON, riuso a chiave identica, rilancio quando cambia un byte (anche di un file non tracciato), TZ
# o la versione di node, gate senza report -> BLOCKED e mai PASS, BLOCKED mai riusato, --verify, albero
# cambiato durante i gate; controprova per mutazione eseguita qui, su una copia mutata dello script.
#   bash script/fic/gates.test.sh
#   GT=/percorso/variante.sh bash script/fic/gates.test.sh   # la suite su una variante
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)   # radice del plugin
GT=${GT:-$HERE/gates.sh}
pass=0 fail=0
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
# i mutanti scritti in $W includono il risolutore accanto a se' ($W/lib) e trovano il plugin da MAAT_ROOT
mkdir -p "$W/lib" && cp "$HERE/lib/maat-paths.sh" "$W/lib/"; export MAAT_ROOT=$ROOT
export HOME="$W/home"; mkdir -p "$HOME"
ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/    /'; }
chk() { if eval "$2"; then ok; else ko "$1" "${3:-}"; fi; }

# --- repository sintetico ---
R="$W/repo"; A="$R/modules/app/apps/admin"; API="$R/modules/api"; FB="$W/bin"
# test-fast.sh e' del harness (pk04b-1): il finto sta in una COPIA del plugin, data come FIC_GATES_HARNESS
HP="$W/plugin"; cp -r "$ROOT" "$HP" && find "$HP" -name __pycache__ -type d -prune -exec rm -rf {} +
mkdir -p "$A/utils" "$A/components/goals" "$R/modules/app/packages/ui" "$API/app/services" "$API/tests" \
         "$FB" "$R/.claude"
cp "$ROOT/examples/nuxt-fastapi.maat.json" "$R/.claude/maat.json"
printf 'export const somma = (a: number) => a\n' > "$A/utils/goals.ts"
printf "import { somma } from './goals'\nit('x', () => expect(somma(1)).toBe(1))\n" > "$A/utils/goals.test.ts"
printf '<template><div/></template>\n' > "$A/components/goals/Riga.vue"
printf '<template><button/></template>\n' > "$R/modules/app/packages/ui/Button.vue"
printf '{"name":"app"}\n' > "$R/modules/app/package.json"
printf 'def f():\n    return 1\n' > "$API/app/services/goals.py"
printf 'def g():\n    return 2\n' > "$API/app/services/senza_test.py"
printf 'def test_f():\n    assert True\n' > "$API/tests/test_goals.py"
# test-fast.sh finto: registra la chiamata (e MAAT_MODULO); FAKE_VF=pass|fail|noreport|mute; FAKE_VF_TOUCH=file da cambiare
cat > "$HP/scripts/test-fast.sh" <<'EOF'
#!/usr/bin/env bash
echo "VF $*" >> "$GLOG"
echo "MOD ${MAAT_MODULO:-}" >> "$GLOG"
echo "CONF ${MAAT_CONFIG:-}" >> "$GLOG"
[ -n "${FAKE_VF_TOUCH:-}" ] && echo cambiato >> "$FAKE_VF_TOUCH"
[ -n "${FAKE_VF_STDERR:-}" ] && echo "$FAKE_VF_STDERR" >&2
lint=0; [ "${1:-}" = --lint ] && lint=1
case ${FAKE_VF:-pass} in
  pass) [ $lint = 1 ] || echo " Tests  2 passed (2)"; echo "vitest-fast: esito=PASS luogo=copia"; exit 0 ;;
  fail) [ $lint = 1 ] || echo " Tests  1 failed | 1 passed (2)"; echo "vitest-fast: esito=FAIL luogo=copia"; exit 1 ;;
  noreport) echo "vitest-fast: esito=PASS luogo=copia"; exit 0 ;;
  mute) exit 0 ;;
esac
EOF
(cd "$R" && git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false &&
  git add -A && git commit -qm init)
# WSL finto: riceve UN comando bash, riporta /mnt/c/ a /c/ (Git Bash) e lo esegue con node/npm finti nel PATH
# Il suo stderr va altrove, come il secondo flusso di wsl.exe che nel log reale si sovrascrive: arriva al log
# solo cio' che il comando unisce a stdout DENTRO WSL.
cat > "$FB/wsl" <<EOF
#!/usr/bin/env bash
c=\${1//\/mnt\//\/}
# come wsl.exe, che passa a WSL solo le variabili di WSLENV: MAAT_CONFIG non arriva se il comando non la esporta
env -u MAAT_CONFIG PATH="$FB:\$PATH" bash -c "\$c" 2>>"$W/wsl-stderr"
EOF
printf '#!/usr/bin/env bash\necho "${FAKE_NODE:-v18.19.0}"\n' > "$FB/node"
printf '#!/usr/bin/env bash\necho "NPM $*" >> "$GLOG"; echo "build ok"\n' > "$FB/npm"
# python del venv finto: --version, pip freeze, pytest (JUnit salvo FAKE_NOJUNIT)
cat > "$FB/venv-python" <<'EOF'
#!/usr/bin/env bash
[ "$1" = --version ] && { echo "Python 3.12.1"; exit 0; }
[ "$1 $2" = "-m pip" ] && { echo "fastapi==0.110.0"; exit 0; }
if [ "$1 $2" = "-m pytest" ]; then
  echo "PYTEST $*" >> "$GLOG"
  for a in "$@"; do case $a in --junitxml=*) j=${a#--junitxml=} ;; esac; done
  [ -n "${FAKE_NOJUNIT:-}" ] || printf '<?xml version="1.0"?><testsuites><testsuite name="pytest" tests="1" failures="0" errors="0" skipped="0"/></testsuites>\n' > "$j"
  echo "1 passed"; exit 0
fi
exit 9
EOF
chmod +x "$FB"/* "$HP/scripts/test-fast.sh"
export GLOG="$W/glog" FIC_GATES_ROOT="$R" FIC_GATES_HARNESS="$HP" FIC_GATES_WSL="$FB/wsl" FIC_GATES_VENV_PY="$FB/venv-python"
: > "$GLOG"
RUN="$W/spec-x.run"; mkdir -p "$RUN"
out="" rc=0
gates() { out=$(bash "$GT" --run-dir "$RUN" "$@" 2>&1); rc=$?; }
calls() { grep -c "^$1" "$GLOG"; }
key() { printf '%s\n' "$out" | sed -n 's/^gates: .* chiave=\([0-9a-f]*\) .*/\1/p'; }
jget() { "$FIC_PY" -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get(sys.argv[2]))' "$1" "$2"; }
. "$ROOT/scripts/python.sh" || { echo "interprete Python non trovato" >&2; exit 2; }
F_STD=(modules/api/app/services/goals.py modules/app/apps/admin/utils/goals.ts)

# --- 1. primo giro: comandi derivati, evidenza, PASS col report ---
gates std "${F_STD[@]}"; K1=$(key); EV="$RUN/evidence/$K1"
chk "primo giro: uscita 0" '[ $rc -eq 0 ] && [ -n "$K1" ]' "$out"
chk "  chiave sha256 (64 esadecimali)" '[ ${#K1} -eq 64 ]'
chk "  pytest sul test mappato dal modulo" 'grep -q "^PYTEST .*tests/test_goals.py" "$GLOG"' "$(cat "$GLOG")"
chk "  vitest sul test con lo stesso nome del sorgente" 'grep -q "^VF utils/goals.test.ts$" "$GLOG"' "$(cat "$GLOG")"
chk "  tests-be.json PASS con report JUnit" '[ "$(jget "$EV/tests-be.json" esito)" = PASS ] && [ "$(jget "$EV/tests-be.json" report)" = tests-be.junit.xml ] && [ -f "$EV/tests-be.junit.xml" ]'
chk "  tests-fe.json PASS con report" '[ "$(jget "$EV/tests-fe.json" esito)" = PASS ] && [ -s "$EV/tests-fe.log" ]'
chk "  campi comando, exit, durata_s" '[ "$(jget "$EV/tests-fe.json" exit)" = 0 ] && jget "$EV/tests-fe.json" comando | grep -q test-fast.sh && [ "$(jget "$EV/tests-fe.json" durata_s)" != None ]'
chk "  MAAT_MODULO nell'ambiente del comando, non nella riga" 'grep -qx "MOD fe" "$GLOG" && ! jget "$EV/tests-fe.json" comando | grep -q MAAT_MODULO' "$(cat "$GLOG")"
chk "  chiave: radici del plugin e del progetto normalizzate (<maat>, <repo>)" 'grep -q "^cmd.tests-fe=cd '"'"'<repo>/modules/app/apps/admin'"'"' && bash '"'"'<maat>'"'"'/scripts/test-fast.sh '"'"'utils/goals.test.ts'"'"'$" "$EV/chiave.txt" && ! grep -qF "$HP" "$EV/chiave.txt"' "$(cat "$EV/chiave.txt")"
chk "  chiave: le voci chiave dei moduli (vitest, eslint, deps, node_modules, tsconfig, pip)" '(for e in vitest eslint deps node_modules tsconfig pip python; do grep -q "^$e=" "$EV/chiave.txt" || exit 1; done)' "$(cat "$EV/chiave.txt")"
chk "  chiave.txt e argomenti.txt accanto" 'grep -q "^tree=" "$EV/chiave.txt" && grep -q "^TZ=" "$EV/chiave.txt" && [ "$(head -1 "$EV/argomenti.txt")" = std ]'
chk "  a livello std niente lint ne build" '[ ! -f "$EV/lint.json" ] && [ ! -f "$EV/build.json" ]'
chk "  riga finale con esito, chiave ed evidence" 'printf "%s\n" "$out" | tail -1 | grep -q "^gates: esito=PASS chiave=$K1 evidence="'

# --- 2. chiave identica => riuso, nessun runner lanciato ---
n_be=$(calls PYTEST) n_fe=$(calls VF)
gates std "${F_STD[@]}"
chk "chiave identica: stessa chiave" '[ "$(key)" = "$K1" ] && [ $rc -eq 0 ]' "$out"
chk "  riuso: pytest e vitest NON rilanciati" '[ "$(calls PYTEST)" = "$n_be" ] && [ "$(calls VF)" = "$n_fe" ]'
chk "  e dichiarato (riuso)" 'printf "%s\n" "$out" | grep -q "^tests-be: PASS (riuso)" && printf "%s\n" "$out" | grep -q "^tests-fe: PASS (riuso)"' "$out"

# --- 3. un byte cambiato in packages/ui (fuori dai file toccati) => rilancio ---
printf ' ' >> "$R/modules/app/packages/ui/Button.vue"
gates std "${F_STD[@]}"; K2=$(key)
chk "byte cambiato in packages/ui: chiave nuova" '[ -n "$K2" ] && [ "$K2" != "$K1" ]'
chk "  e i gate si rilanciano" '[ "$(calls VF)" -gt "$n_fe" ] && [ "$(calls PYTEST)" -gt "$n_be" ]'

# --- 4. file NUOVO non tracciato (non ignorato) => rilancio (il caso della controprova) ---
n_fe=$(calls VF)
printf '<template><i/></template>\n' > "$R/modules/app/packages/ui/Nuovo.vue"
gates std "${F_STD[@]}"; K3=$(key)
chk "file nuovo non tracciato: chiave nuova e rilancio" '[ -n "$K3" ] && [ "$K3" != "$K2" ] && [ "$(calls VF)" -gt "$n_fe" ]' "$out"

# --- 5. TZ e versione di node => rilancio ---
n_fe=$(calls VF)
TZ=Asia/Tokyo gates std "${F_STD[@]}"; K4=$(key)
chk "TZ cambiato: chiave nuova e rilancio" '[ -n "$K4" ] && [ "$K4" != "$K3" ] && [ "$(calls VF)" -gt "$n_fe" ]'
n_fe=$(calls VF)
FAKE_NODE=v20.11.1 gates std "${F_STD[@]}"; K5=$(key)
chk "versione di node cambiata: chiave nuova e rilancio" '[ -n "$K5" ] && [ "$K5" != "$K3" ] && [ "$(calls VF)" -gt "$n_fe" ]'
chk "  la versione e' nella chiave in chiaro" 'grep -qx "node=v20.11.1" "$RUN/evidence/$K5/chiave.txt"'
gates std "${F_STD[@]}"
chk "  tornati come prima: la chiave di prima, riusata" '[ "$(key)" = "$K3" ]'

# --- 6. gate senza report => BLOCKED, mai PASS; un BLOCKED non si riusa ---
printf 'x\n' > "$R/modules/app/packages/ui/altro.md"
FAKE_NOJUNIT=1 gates std "${F_STD[@]}"; K6=$(key)
chk "pytest senza JUnit: tests-be BLOCKED, uscita 3" '[ "$(jget "$RUN/evidence/$K6/tests-be.json" esito)" = BLOCKED ] && [ $rc -eq 3 ]' "$out"
chk "  riga finale BLOCKED" 'printf "%s\n" "$out" | tail -1 | grep -q "^gates: esito=BLOCKED"'
n_be=$(calls PYTEST)
gates std "${F_STD[@]}"
chk "  a chiave identica il BLOCKED si riesegue (e ora passa)" '[ "$(key)" = "$K6" ] && [ "$(calls PYTEST)" -gt "$n_be" ] && [ "$(jget "$RUN/evidence/$K6/tests-be.json" esito)" = PASS ]' "$out"
printf 'y\n' >> "$R/modules/app/packages/ui/altro.md"
FAKE_VF=noreport gates std "${F_STD[@]}"; K7=$(key)
chk "vitest: PASS del wrapper senza riepilogo di vitest => BLOCKED" '[ "$(jget "$RUN/evidence/$K7/tests-fe.json" esito)" = BLOCKED ]' "$out"
printf 'z\n' >> "$R/modules/app/packages/ui/altro.md"
FAKE_VF=mute gates std "${F_STD[@]}"; K8=$(key)
chk "vitest: uscita 0 senza riga d'esito => BLOCKED" '[ "$(jget "$RUN/evidence/$K8/tests-fe.json" esito)" = BLOCKED ] && [ $rc -eq 3 ]'
printf 'w\n' >> "$R/modules/app/packages/ui/altro.md"
FAKE_VF=fail gates std "${F_STD[@]}"; K9=$(key)
chk "vitest FAIL => tests-fe FAIL, uscita 1" '[ "$(jget "$RUN/evidence/$K9/tests-fe.json" esito)" = FAIL ] && [ $rc -eq 1 ]' "$out"
n_fe=$(calls VF)
gates std "${F_STD[@]}"
chk "  un FAIL a chiave identica si riusa (non si rilancia)" '[ "$(calls VF)" = "$n_fe" ] && [ $rc -eq 1 ]'

# --- 7. livello full: lint (anche .vue, --base da base.txt) e build; SKIPPED dichiarati ---
echo abc123 > "$RUN/base.txt"
gates full modules/app/apps/admin/components/goals/Riga.vue modules/api/app/services/senza_test.py; KF=$(key)
chk "full: lint sul .vue con --base" 'grep -q "^VF --lint --base abc123 modules/app/apps/admin/components/goals/Riga.vue$" "$GLOG"' "$(tail -3 "$GLOG")"
chk "  build:admin eseguito" '[ "$(jget "$RUN/evidence/$KF/build.json" esito)" = PASS ] && grep -q "^NPM run build:admin" "$GLOG"'
chk "  sorgente senza test: tests-be SKIPPED con il path" '[ "$(jget "$RUN/evidence/$KF/tests-be.json" esito)" = SKIPPED ] && jget "$RUN/evidence/$KF/tests-be.json" motivo | grep -q senza_test.py'
chk "  .vue senza test omonimo: tests-fe SKIPPED" '[ "$(jget "$RUN/evidence/$KF/tests-fe.json" esito)" = SKIPPED ]'
chk "  esito complessivo PASS, uscita 0" '[ $rc -eq 0 ] && printf "%s\n" "$out" | tail -1 | grep -q "esito=PASS"' "$out"
rm -f "$RUN/base.txt"

# --- 8. --verify ---
bash "$GT" --verify "$RUN/evidence/$K9" >/dev/null 2>&1; r=$?
chk "--verify sulla chiave attuale: FRESH (0)" '[ $r -eq 0 ]'
printf 'v\n' >> "$R/modules/app/packages/ui/altro.md"
o=$(bash "$GT" --verify "$RUN/evidence/$K9" 2>&1); r=$?
chk "--verify dopo un byte cambiato: STALE (1)" '[ $r -eq 1 ] && printf "%s" "$o" | grep -q "^STALE"' "$o"

# --- 9. albero cambiato mentre i gate girano => BLOCKED ---
FAKE_VF_TOUCH="$R/modules/app/packages/ui/altro.md" gates std "${F_STD[@]}"; KT=$(key)
chk "tree cambiato durante i gate: eseguiti => BLOCKED" '[ "$(jget "$RUN/evidence/$KT/tests-fe.json" esito)" = BLOCKED ] && jget "$RUN/evidence/$KT/tests-fe.json" motivo | grep -q "albero cambiato" && [ $rc -eq 3 ]' "$out"

# --- 10. uso ---
bash "$GT" --run-dir "$RUN" boh a.py >/dev/null 2>&1; r=$?; chk "livello sconosciuto: uscita 2" '[ $r -eq 2 ]'
bash "$GT" std a.py >/dev/null 2>&1; r=$?; chk "senza --run-dir: uscita 2" '[ $r -eq 2 ]'

# --- 11. --run-dir relativo (come lo passa run-phase.sh): il JUnit di pytest, lanciato dalla cartella del modulo,
#     va nell'evidenza e non in modules/api/<run-dir>/ (che cambierebbe l'albero durante i gate). Da il progetto guida
#     emerso con la prima feature con test backend. ---
out=$(cd "$W" && bash "$GT" --run-dir spec-rel.run std "${F_STD[@]}" 2>&1); rc=$?; Kr=$(key)
chk "run dir relativa: uscita 0" '[ $rc -eq 0 ] && [ -n "$Kr" ]' "$out"
chk "  JUnit nell'evidenza della run dir" '[ -f "$W/spec-rel.run/evidence/$Kr/tests-be.junit.xml" ] && [ "$(jget "$W/spec-rel.run/evidence/$Kr/tests-be.json" esito)" = PASS ]' "$out"
chk "  niente sotto modules/api" '[ ! -e "$API/spec-rel.run" ]'

# --- 12. lo stderr del runner (i blocchi FAIL di vitest) arriva nel log del gate: unito dentro WSL. Da il progetto guida
#     Unito fuori, wsl.exe consegna due flussi che si sovrascrivono e un blocco FAIL si perde. ---
RUN="$W/spec-stderr.run"; mkdir -p "$RUN"
FAKE_VF_STDERR="FAIL  blocco su stderr" gates std "${F_STD[@]}"; Ks=$(key)
chk "stderr del runner nel log: uscita 0" '[ $rc -eq 0 ] && [ -n "$Ks" ]' "$out"
chk "  blocco FAIL di stderr presente in tests-fe.log" 'grep -q "FAIL  blocco su stderr" "$RUN/evidence/$Ks/tests-fe.log"' "$(cat "$RUN/evidence/$Ks/tests-fe.log" 2>/dev/null)"

# --- 13. senza FIC_GATES_VENV_PY il {python} di un modulo wsl si cerca DENTRO WSL fra i candidati di moduli[].python
#     (nell'esempio .venv312, poi .venv): percorso di WSL nel comando, versione di WSL nella chiave; nessun candidato ->
#     tests-be BLOCKED, mai PASS. Dal progetto guida: il venv Windows derivato era passato verde. ---
wp() { local w; w=$(cygpath -m "$1" 2>/dev/null || printf '%s' "$1")
  case $w in [A-Za-z]:/*) printf '/mnt/%s%s' "$(printf '%s' "${w:0:1}" | tr 'A-Z' 'a-z')" "${w:2}" ;; *) printf '%s' "$w" ;; esac; }
mkdir -p "$API/.venv/bin" && cp "$FB/venv-python" "$API/.venv/bin/python" && chmod +x "$API/.venv/bin/python"
RUN="$W/spec-wslvenv.run"; mkdir -p "$RUN"; n_be=$(calls PYTEST)
out=$(FIC_GATES_VENV_PY= bash "$GT" --run-dir "$RUN" std "${F_STD[@]}" 2>&1); rc=$?; Kw=$(key)
chk "venv WSL: uscita 0" '[ $rc -eq 0 ] && [ -n "$Kw" ]' "$out"
chk "  pytest lanciato e JUnit nell'evidenza" '[ "$(calls PYTEST)" -gt "$n_be" ] && [ "$(jget "$RUN/evidence/$Kw/tests-be.json" esito)" = PASS ] && [ -f "$RUN/evidence/$Kw/tests-be.junit.xml" ]' "$out"
chk "  comando col python di .venv/bin in forma WSL" 'jget "$RUN/evidence/$Kw/tests-be.json" comando | grep -qF "$(wp "$API")/.venv/bin/python -m pytest"' "$(jget "$RUN/evidence/$Kw/tests-be.json" comando)"
chk "  versione del python di WSL e pip freeze nella chiave" 'grep -qx "python=Python 3.12.1" "$RUN/evidence/$Kw/chiave.txt" && grep -q "^pip=[0-9a-f]\{64\}$" "$RUN/evidence/$Kw/chiave.txt"' "$(cat "$RUN/evidence/$Kw/chiave.txt" 2>/dev/null)"
mkdir -p "$API/.venv312/bin" && cp "$FB/venv-python" "$API/.venv312/bin/python" && chmod +x "$API/.venv312/bin/python"
out=$(FIC_GATES_VENV_PY= bash "$GT" --run-dir "$RUN" std "${F_STD[@]}" 2>&1); rc=$?; Kw=$(key)
chk "  .venv312 presente: vince sul .venv (primo candidato)" '[ $rc -eq 0 ] && jget "$RUN/evidence/$Kw/tests-be.json" comando | grep -qF "$(wp "$API")/.venv312/bin/python -m pytest"' "$out"
rm -rf "$API/.venv" "$API/.venv312"
RUN="$W/spec-novenv.run"; mkdir -p "$RUN"
out=$(FIC_GATES_VENV_PY= bash "$GT" --run-dir "$RUN" std "${F_STD[@]}" 2>&1); rc=$?
chk "  senza venv WSL: tests-be BLOCKED, mai PASS" '[ $rc -eq 3 ] && printf "%s\n" "$out" | grep -q "^tests-be: BLOCKED.*python WSL assente"' "$out"

# --- 14. {python} non risolvibile in un modulo NATIVO (uscita 3 del lettore, «python non trovato»): BLOCKED, mai
#     NOT RUN «dichiarato» (decisione di pk04b-2, nota «Da pk04b-1»). Modulo be nativo con un interprete che non c'e'
#     nel PATH, PATH senza python3 (il harness usa FIC_PY, assoluto, via FIC_PYTHON). Controprova: il ramo BLOCKED tolto => NOT RUN. ---
NOPYPATH=$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r d; do
  { [ -e "$d/python3" ] || [ -e "$d/python3.exe" ]; } && continue; printf '%s:' "$d"; done)
"$FIC_PY" - "$R/.claude/maat.json" "$W/nopy.maat.json" <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
for m in c["moduli"]:
    if m["nome"] == "be":
        m["ambiente"] = "nativo"; m["python"] = "python-maat-assente"
json.dump(c, open(sys.argv[2], "w", encoding="utf-8"), indent=2)
PYEOF
nopy() { RUN="$W/spec-nopy-$1.run"; rm -rf "$RUN"; mkdir -p "$RUN"
  out=$(PATH="$NOPYPATH" FIC_PYTHON="$FIC_PY" MAAT_CONFIG="$W/nopy.maat.json" FIC_GATES_VENV_PY= bash "$2" --run-dir "$RUN" std modules/api/app/services/goals.py 2>&1); rc=$?; }
if PATH="$NOPYPATH" command -v git >/dev/null 2>&1 && PATH="$NOPYPATH" command -v sed >/dev/null 2>&1; then
  nopy orig "$GT"
  chk "14 python non trovato (modulo nativo): tests-be BLOCKED, uscita 3, mai NOT RUN" '[ $rc -eq 3 ] && printf "%s
" "$out" | grep -q "^tests-be: BLOCKED.*python non trovato" && ! printf "%s
" "$out" | grep -q "^tests-be: NOT RUN"' "$out"
  M="$W/mut-nopy.sh"; sed 's/^senza_python() { case \$C_ERR in \*"python non trovato"\*) return 0 ;; esac; return 1; }$/senza_python() { return 1; }/' "$GT" > "$M"
  if cmp -s "$GT" "$M"; then ko "14 controprova: la mutazione non si applica"
  else nopy mut "$M"
    if printf '%s
' "$out" | grep -q "^tests-be: NOT RUN"; then ok   # rosso atteso: torna NOT RUN «dichiarato»
    else ko "14 controprova: senza il ramo BLOCKED l'esito non torna NOT RUN (il test non discrimina)" "$out"; fi
  fi
else
  echo "SKIP [14: nessun PATH senza python3 che abbia ancora git e sed]"
fi

# --- 15. MAAT_CONFIG arriva a test-fast.sh dentro WSL (tradotta /mnt/<unita'>/…: nota «Da pk04b-1»). Controprova:
#     senza l'export nel comando WSL test-fast.sh non la vede. ---
cp "$R/.claude/maat.json" "$W/conf15.maat.json"
conf15() { RUN="$W/spec-conf15-$1.run"; rm -rf "$RUN"; mkdir -p "$RUN"; : > "$GLOG"
  out=$(MAAT_CONFIG="$W/conf15.maat.json" bash "$2" --run-dir "$RUN" std modules/app/apps/admin/utils/goals.ts 2>&1); rc=$?
  CONFV=$(sed -n 's/^CONF //p' "$GLOG" | tail -1); }
conf15 orig "$GT"
chk "15 MAAT_CONFIG in WSL: test-fast.sh la riceve, tradotta, ed e' lo stesso file" '[ $rc -eq 0 ] && [ -n "$CONFV" ] && cmp -s "$CONFV" "$W/conf15.maat.json"' "$out CONF=$CONFV"
M="$W/mut-conf.sh"; sed 's/\${MAAT_CONFIG:+; export MAAT_CONFIG=\$(sq "\$(wslp "\$MAAT_CONFIG")")}//' "$GT" > "$M"
if cmp -s "$GT" "$M"; then ko "15 controprova: la mutazione non si applica"
else conf15 mut "$M"
  if [ -z "$CONFV" ]; then ok   # rosso atteso: test-fast.sh non vede MAAT_CONFIG
  else ko "15 controprova: senza l'export test-fast.sh vede ancora MAAT_CONFIG (il test non discrimina)" "CONF=$CONFV"; fi
fi
: > "$GLOG"

# --- controprova: senza i file non tracciati nella chiave, il caso «file nuovo» diventa un riuso sbagliato ---
LINE='tree_now() { (cd "$ROOT" && bash "$RS" tree) 2>/dev/null; }'
chk "controprova: riga del tree unica" '[ "$(grep -cxF -- "$LINE" "$GT")" = 1 ]'
M="$W/mut-tracciati.sh"
# mutante: tree = HEAD + diff dei soli file tracciati (i non tracciati spariscono dalla chiave)
MUT='tree_now() { (cd "$ROOT" \&\& { git rev-parse HEAD; git diff HEAD; } | sha) 2>/dev/null; }'
sed "s#^tree_now() { (cd \"\$ROOT\" && bash \"\$RS\" tree) 2>/dev/null; }\$#$MUT#" "$GT" > "$M"
if cmp -s "$GT" "$M"; then ko "controprova: la mutazione non si applica"; else
  RUN="$W/spec-mut.run"; mkdir -p "$RUN"
  out=$(bash "$M" --run-dir "$RUN" std "${F_STD[@]}" 2>&1); Km=$(key)
  n_fe=$(calls VF)
  printf '<template><b/></template>\n' > "$R/modules/app/packages/ui/NuovoMut.vue"
  out=$(bash "$M" --run-dir "$RUN" std "${F_STD[@]}" 2>&1)
  if [ -z "$Km" ]; then ko "controprova: il mutante non gira" "$out"
  elif [ "$(key)" = "$Km" ] && [ "$(calls VF)" = "$n_fe" ]; then ok   # rosso atteso: riuso sbagliato
  else ko "controprova: sul mutante il file nuovo non tracciato fa ancora rilanciare (il test non discrimina)" "$out"; fi
fi

# --- L: cygpath -m antepone //?/ ai percorsi oltre MAX_PATH (run dir dal nome lungo: l'evidenza dei gate diventava
# //?/C:/... e pytest in WSL non scriveva il JUnit). maat_cygm, definita una volta in lib/maat-paths.sh, toglie il
# prefisso; gli script che convertono percorsi la includono e non chiamano cygpath -m (o -am) direttamente. ---
if command -v cygpath >/dev/null 2>&1; then
  LIB="$HERE/lib/maat-paths.sh"
  LONG="/c/Users/$(printf 'x%.0s' $(seq 1 250))/spec.run/evidence/k"
  def=$(grep -m1 '^maat_cygm()' "$LIB")
  got=$(bash -c "$def"$'\n''maat_cygm "$1"' _ "$LONG" 2>/dev/null)
  chk "L lib/maat-paths.sh: percorso lungo senza //?/" 'case $got in C:/Users/*) true ;; *) false ;; esac' "${got:0:40}"
  got=$(bash -c "$def"$'\n''maat_cygm -a "$1"' _ "$LONG" 2>/dev/null)
  chk "L lib/maat-paths.sh: percorso lungo con -a senza //?/" 'case $got in C:/Users/*) true ;; *) false ;; esac' "${got:0:40}"
  chk "L lib/maat-paths.sh: una sola chiamata a cygpath -m, in maat_cygm" '[ "$(grep -v "^[[:space:]]*#" "$LIB" | grep -c "cygpath -a\{0,1\}m")" = 1 ]' "$(grep -n "cygpath" "$LIB")"
  for f in gates.sh finalize.sh context-pack.sh worktree-lib.sh corpus/inject/_lib.sh run-phase.sh; do
    chk "L $f: include lib/maat-paths.sh" 'grep -q "lib/maat-paths.sh" "$HERE/$f"'
    chk "L $f: nessun cygpath -m diretto" '[ "$(grep -v "^[[:space:]]*#" "$HERE/$f" | grep -c "cygpath -a\{0,1\}m")" = 0 ]' "$(grep -n "cygpath -a\{0,1\}m" "$HERE/$f")"
  done
fi

echo "gates.test.sh: $pass ok, $fail falliti"
[ $fail -eq 0 ]
