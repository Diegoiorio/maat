#!/usr/bin/env bash
# Test deterministici di counterproof.sh, in un repo finto con HOME temporaneo (mai il mirror reale,
# nessun vitest o pytest vero, nessun /mnt/c). Lo script si lancia DALLA SUA POSIZIONE NEL PLUGIN, con
# PROJECT_ROOT sul repo finto (mai copiato nel repo: la radice non deve venire dalla posizione dello script).
# La configurazione del repo finto e' examples/nuxt-fastapi.maat.json (moduli fe e be, runner vitest e pytest
# dichiarati); i casi su N moduli e sul runner `comando` usano una configurazione propria (MAAT_CONFIG).
# Da eseguire in WSL:
#   wsl -- bash -lc 'bash /mnt/c/<maat>/plugins/maat/scripts/counterproof.test.sh'
# Variante da provare (controprove per mutazione dello script): CP=<copia del plugin>/scripts/counterproof.sh — la
# variante sta in una copia del plugin (scripts/ con lib/, fic-mirror.sh, maat-config.py, python.sh; schemas/;
# .claude-plugin/), perche' include i file accanto a se'.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(dirname "$HERE")
CP=${CP:-$HERE/counterproof.sh}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; fail=0
check() { n=$((n + 1)); if eval "$2"; then :; else fail=$((fail + 1)); echo "FAIL: $1"; fi; }
unset MAAT_CONFIG MAAT_ROOT FIC_REPO PROJECT_ROOT FIC_GATES_VENV_PY MAAT_MODULO

# finto repo: .claude/maat.json (l'esempio) + modules/app + modules/api
R=$T/repo; A=$R/modules/app; AD=$A/apps/admin; API=$R/modules/api
mkdir -p "$R/.claude" "$AD/tests" "$A/node_modules/dep" "$API/app" "$API/tests" "$R/run/counterproof"
cp "$PLUGIN/examples/nuxt-fastapi.maat.json" "$R/.claude/maat.json"
echo '{"name":"root"}' > "$A/package.json"; echo '{"lock":1}' > "$A/package-lock.json"
echo '{"name":"admin"}' > "$AD/package.json"
echo 'export const x = 1' > "$AD/src.ts"
echo 'export const y = 1' > "$AD/other.ts"
echo 'export const w = 1' > "$AD/uncovered.ts"
echo 'import { x } from "../src"' > "$AD/tests/a.test.ts"
echo 'dep' > "$A/node_modules/dep/index.js"
echo 'UNO = 1' > "$API/app/core.py"
echo 'from app.core import UNO' > "$API/tests/test_core.py"
printf 'node_modules\n.nuxt\n.venv\n__pycache__\nrun/\n' > "$R/.gitignore"
(cd "$R" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm init)

BIN=$T/bin; mkdir -p "$BIN"
# vitest finto (npx): legge i sorgenti della cwd (apps/admin del mirror) e scrive il report JSON come vitest 1.6.
#   IMPORTROTTO in un sorgente -> il file di test non si carica · ROSSO in src.ts/other.ts -> "somma vale uno"
#   rosso su "expected 2 to be 1" · DIVERSO -> rosso con un altro messaggio · "altro resta verde" sempre verde.
#   -t filtra per regex sul fullName (gli altri test risultano skipped). FAKE_KILL: uccide counterproof a meta'.
cat > "$BIN/npx" <<'EOF'
#!/usr/bin/env bash
exec 9>&- 2>/dev/null
echo "cwd=$PWD args=$*" >> "$FAKE_LOG.all"
echo "cache=${FIC_VITE_CACHE_DIR:-}" >> "$FAKE_LOG.all"
echo "allow=${FIC_VITE_FS_ALLOW:-}" >> "$FAKE_LOG.all"
if flock -n "$FAKE_LOCKFILE" true; then echo "lock=libero" >> "$FAKE_LOG.all"; else echo "lock=occupato" >> "$FAKE_LOG.all"; fi
# FAKE_LOCKDIR: il lock di ripiego (mkdir, senza flock) c'e' durante il run?
[ -z "${FAKE_LOCKDIR:-}" ] || { if [ -d "$FAKE_LOCKDIR" ]; then echo lockdir=presente; else echo lockdir=assente; fi; } >> "$FAKE_LOG.all"
echo "seen=$(cat src.ts other.ts uncovered.ts 2>/dev/null | tr '\n' ' ')" >> "$FAKE_LOG.all"
# FAKE_SECOND: una volta sola, un secondo counterproof.sh (tetto di lock 1 s) prova a prendere il mirror
if [ -n "${FAKE_SECOND:-}" ] && mkdir "$FAKE_SECOND.once" 2>/dev/null; then
  FIC_LOCK_WAIT=1 bash "$FAKE_SECOND_SCRIPT" "$FAKE_SECOND" > "$FAKE_SECOND.out" 2>&1; echo "second=$?" >> "$FAKE_LOG.all"
fi
# FAKE_KILL: segnale al counterproof.sh in corso; il run (e un suo figlio) restano vivi FAKE_KILL_SLEEP secondi
if [ -n "${FAKE_KILL:-}" ]; then
  echo $$ >> "$FAKE_LOG.pids"; pkill -TERM -f "$FAKE_KILL"
  sleep "${FAKE_KILL_SLEEP:-3}" & echo $! >> "$FAKE_LOG.pids"; wait; exit 1
fi
out=""; pat=""; prev=""
for a in "$@"; do
  case "$a" in --outputFile.json=*) out=${a#--outputFile.json=} ;; esac
  [ "$prev" = -t ] && pat=$a
  prev=$a
done
imp=0; red=0; div=0
grep -q IMPORTROTTO src.ts other.ts uncovered.ts 2>/dev/null && imp=1
grep -q ROSSO src.ts other.ts 2>/dev/null && red=1
grep -q DIVERSO src.ts 2>/dev/null && div=1
python3 - "$out" "$pat" "$imp" "$red" "$div" "$PWD/tests/a.test.ts" <<'PYEOF'
import json, re, sys
out, pat, imp, red, div, name = sys.argv[1:7]
tests = []
for anc, title in (("somma", "vale uno"), ("altro", "resta verde")):
    full = anc + " " + title
    st, msgs = "passed", []
    if pat and not re.search(pat, full):
        st = "skipped"
    elif full == "somma vale uno" and red == "1":
        st, msgs = "failed", ["AssertionError: expected 2 to be 1 // Object.is equality\n    at tests/a.test.ts:3:5"]
    elif full == "somma vale uno" and div == "1":
        st, msgs = "failed", ["TypeError: boom is not a function"]
    tests.append({"ancestorTitles": [anc], "fullName": full, "title": title, "status": st, "failureMessages": msgs})
if imp == "1":
    fr = {"name": name, "status": "failed", "message": "Failed to resolve import \"./nope\" from \"src.ts\". Does the file exist?", "assertionResults": []}
else:
    fr = {"name": name, "status": "failed" if any(t["status"] == "failed" for t in tests) else "passed", "message": "", "assertionResults": tests}
with open(out, "w") as fh:
    json.dump({"testResults": [fr]}, fh)
sys.exit(1 if fr["status"] == "failed" else 0)
PYEOF
EOF
# pytest finto (FIC_PYTEST_PY): junit come pytest; ROSSO in app/core.py -> failure, IMPORTROTTO -> errore di raccolta
cat > "$BIN/fakepy" <<'EOF'
#!/usr/bin/env bash
echo "cwd=$PWD args=$*" >> "$FAKE_LOG.all"
jx=""; for a in "$@"; do case "$a" in --junitxml=*) jx=${a#--junitxml=} ;; esac; done
if grep -q IMPORTROTTO app/core.py; then
  printf '<testsuites><testsuite><testcase classname="" name="tests.test_core"><error message="collection failure">ImportError: cannot import name UNO</error></testcase></testsuite></testsuites>' > "$jx"; exit 2
elif grep -q ROSSO app/core.py; then
  printf '<testsuites><testsuite><testcase classname="tests.test_core" name="test_uno"><failure message="AssertionError: assert 2 == 1">tests/test_core.py:3: AssertionError</failure></testcase></testsuite></testsuites>' > "$jx"; exit 1
fi
printf '<testsuites><testsuite><testcase classname="tests.test_core" name="test_uno"/></testsuite></testsuites>' > "$jx"; exit 0
EOF
# rsync finto: FAKE_RSYNC_LOG registra gli argomenti (sorgenti, destinazioni, esclusioni), poi il vero
cat > "$BIN/rsync" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_RSYNC_LOG:-}" ] && printf '%s\n' "$*" >> "$FAKE_RSYNC_LOG"
[ -n "${FAKE_RSYNC_FAIL:-}" ] && exit 23
[ -n "${FAKE_RSYNC_NOOP:-}" ] && exit 0
exec /usr/bin/rsync "$@"
EOF
chmod +x "$BIN/npx" "$BIN/fakepy" "$BIN/rsync"
export PATH="$BIN:$PATH" HOME=$T/home FAKE_LOG=$T/npx FIC_PYTEST_PY=$BIN/fakepy
mkdir -p "$HOME"
M=$HOME/fic-mirror/modules/app; MA=$HOME/fic-mirror/modules/api
export FAKE_LOCKFILE=$M/.fic-lock
OUT=$R/run/counterproof
# la copia come la prepara `test-fast.sh --setup` (origine con node_modules: fic_deps_refresh di fic-mirror.sh)
( . "$HERE/fic-mirror.sh" && fic_mirror_init "$R" && fic_deps_refresh "$A" "$FIC_MIRROR/modules/app" ) > /dev/null 2>&1

# CPX: uno script diverso da $CP (una copia del plugin con un file cambiato), per un solo caso
cpr() { rm -f "$FAKE_LOG.all"; PROJECT_ROOT=${CPR_ROOT:-$R} bash "${CPX:-$CP}" "$1" > "$T/out" 2>&1; echo $? > "$T/rc"; }
rc() { cat "$T/rc"; }
field() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print("" if v is None else v)' "$OUT/$1.json" "$2" 2>/dev/null; }
wt_hash() { (cd "$R" && find . -path ./.git -prune -o -path ./run -prune -o -type f -print | LC_ALL=C sort | xargs sha256sum) | sha256sum; }
mir_hash() { (cd "$HOME/fic-mirror" && find . -name node_modules -prune -o -type f ! -name '.fic-*' -print | LC_ALL=C sort | xargs sha256sum) | sha256sum; }
mj() { printf '%s\n' "$2" > "$OUT/$1"; echo "$OUT/$1"; }
mkplug() { # <dir>: copia del plugin (scripts, lib, schemas, .claude-plugin) con $CP come counterproof.sh
  mkdir -p "$1/scripts"; cp -r "$PLUGIN/.claude-plugin" "$PLUGIN/schemas" "$1/"
  cp "$HERE"/*.sh "$HERE"/*.py "$1/scripts/"; cp -r "$HERE/lib" "$1/scripts/"; cp "$CP" "$1/scripts/counterproof.sh"
}

# voce: id file cerca sostituisci [test] [test_id] [asserzione]
V=modules/app/apps/admin
entry() {
  python3 -c 'import json,sys
i,f,c,s,t,tid,a=sys.argv[1:8]
print(json.dumps({"id":i,"file":f,"simbolo":"sym","mutazione":{"cerca":c,"sostituisci":s},"test":{"percorso":t,"nome":tid},"rosso_se":{"test_id":tid,"asserzione":a},"superficie":"S"}))' \
    "$1" "$2" "$3" "$4" "${5:-$V/tests/a.test.ts}" "${6:-somma vale uno}" "${7:-expected 2 to be 1}"
}

# 1. la lista completa: prova valida, duplicato esatto, stesso assert da un altro file, import, non coperta, pytest
LIST=$(mj mutations.json "[
$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),
$(entry A1-DUP $V/src.ts 'x = 1' 'x = 2 // ROSSO'),
$(entry B1 $V/other.ts 'y = 1' 'y = 2 // ROSSO'),
$(entry IMP $V/src.ts 'export const x = 1' 'import { z } from "./nope" // IMPORTROTTO
export const x = 1'),
$(entry VERDE $V/uncovered.ts 'w = 1' 'w = 2'),
$(entry PY modules/api/app/core.py 'UNO = 1' 'UNO = 1  # ROSSO' modules/api/tests/test_core.py 'tests/test_core.py::test_uno' 'assert 2 == 1')
]")
mkdir -p "$MA" && /usr/bin/rsync -a --exclude=__pycache__ "$API/" "$MA/"   # stato iniziale del mirror api
WT0=$(wt_hash); MIR0=$(mir_hash)
FIC_CP_PARALLEL=1 cpr "$LIST"
check "lista con FAIL -> exit 1, ultima riga esito=FAIL" '[ "$(rc)" = 1 ] && tail -1 "$T/out" | grep -q "esito=FAIL prove=4/6 fail=2 bloccate=0"'
check "  gradino 1: seriale nel mirror, sotto il lock" 'tail -1 "$T/out" | grep -q "luogo=mirror" && ! grep -q "lock=libero" "$FAKE_LOG.all"'
check "rosso sull asserzione -> rosso_asserzione, PASS" '[ "$(field A1 esito)" = rosso_asserzione ] && [ "$(field A1 controprova)" = PASS ]'
check "  la mutazione l ha vista il runner nel mirror" 'grep -q "seen=export const x = 2 // ROSSO" "$FAKE_LOG.all"'
check "  solo il test nominato (-t) e report JSON" 'grep -q -- "-t somma vale uno" "$FAKE_LOG.all" && grep -q -- "--reporter=json" "$FAKE_LOG.all"'
check "  riga e cartella di vitest uguali a oggi (dal comando dichiarato)" 'grep -Eq "^cwd=$M/apps/admin args=vitest run tests/a\.test\.ts -t somma vale uno --reporter=default --reporter=json --outputFile\.json=/[^ ]*/report$" "$FAKE_LOG.all"'
check "import rotto -> rosso_import, mai una prova" '[ "$(field IMP esito)" = rosso_import ] && [ "$(field IMP controprova)" = FAIL ]'
check "mutazione non coperta -> verde, FAIL" '[ "$(field VERDE esito)" = verde ] && [ "$(field VERDE controprova)" = FAIL ]'
check "duplicato esatto: stesso esito, duplicato_di A1" '[ "$(field A1-DUP esito)" = rosso_asserzione ] && [ "$(field A1-DUP duplicato_di)" = A1 ]'
check "  eseguito una volta sola (4 run vitest per 5 voci frontend)" '[ "$(grep -c "args=vitest" "$FAKE_LOG.all")" = 4 ]'
check "stesso assert da un file diverso: eseguita anche B1" '[ "$(field B1 esito)" = rosso_asserzione ] && [ -z "$(field B1 duplicato_di)" ] && grep -q "seen=.*y = 2 // ROSSO" "$FAKE_LOG.all"'
check "backend: pytest nel mirror api, rosso sull asserzione" '[ "$(field PY esito)" = rosso_asserzione ] && grep -q "cwd=$MA args=-B -m pytest tests/test_core.py::test_uno -p no:cacheprovider" "$FAKE_LOG.all"'
check "  riga e cartella di pytest uguali a oggi (dal comando dichiarato)" 'grep -Eq "^cwd=$MA args=-B -m pytest tests/test_core\.py::test_uno -p no:cacheprovider --junitxml=/[^ ]*/report$" "$FAKE_LOG.all"'
check "nessun run nel working tree (/mnt/c): tutte le cwd nel mirror" '! grep "^cwd=" "$FAKE_LOG.all" | grep -v "^cwd=$HOME/fic-mirror/" | grep -q .'
check "  sotto il lock del mirror" '[ "$(grep -c "^lock=occupato" "$FAKE_LOG.all")" = 4 ]'
check "hash del working tree invariato" '[ "$(wt_hash)" = "$WT0" ]'
check "hash del mirror invariato" '[ "$(mir_hash)" = "$MIR0" ]'
check "i campi dell input restano nel risultato" '[ "$(field A1 superficie)" = S ] && [ "$(field A1 simbolo)" = sym ] && [ "$(field A1 luogo)" = mirror ]'

# 1b. stessa lista, gradino 2: copie private in parallelo, stessi esiti
FIC_CP_PARALLEL=2 cpr "$LIST"
check "gradino 2: stessi esiti del seriale" '[ "$(rc)" = 1 ] && tail -1 "$T/out" | grep -q "esito=FAIL prove=4/6 fail=2 bloccate=0 .*luogo=copie(2)" && [ "$(field A1 esito)" = rosso_asserzione ] && [ "$(field B1 esito)" = rosso_asserzione ] && [ "$(field IMP esito)" = rosso_import ] && [ "$(field VERDE esito)" = verde ] && [ "$(field A1-DUP duplicato_di)" = A1 ] && [ "$(field PY esito)" = rosso_asserzione ]'
check "  i run vitest girano nelle copie private, fuori dal mirror" '[ "$(grep "args=vitest" "$FAKE_LOG.all" | grep -c "^cwd=$HOME/fic-cp\.")" = 4 ]'
check "  il backend resta seriale nel mirror" 'grep -q "^cwd=$MA args=-B -m pytest" "$FAKE_LOG.all"'
check "  cacheDir di vite privata per copia (2 distinte)" '[ "$(grep "^cache=$HOME/fic-cp\..*/.fic-vite-cache$" "$FAKE_LOG.all" | sort -u | wc -l)" = 2 ]'
check "  fs.allow = radice della copia + node_modules e packages del mirror" '[ "$(grep -c "^allow=$HOME/fic-cp\.[^/]*/[12]/modules/app:$M/node_modules:$M/packages$" "$FAKE_LOG.all")" = 4 ]'
check "  lock del mirror tenuto durante i run nelle copie" '[ "$(grep -c "^lock=occupato" "$FAKE_LOG.all")" = 4 ] && ! grep -q "^lock=libero" "$FAKE_LOG.all"'
check "  copie private cancellate alla fine" '! ls -d "$HOME"/fic-cp.* >/dev/null 2>&1'
check "  hash del working tree e del mirror invariati" '[ "$(wt_hash)" = "$WT0" ] && [ "$(mir_hash)" = "$MIR0" ]'
# 1c. goals-ux-12: test nominato "describe > it", come vitest lo stampa nei FAIL. Controprova: senza la forma
# " > " in pattern() -t non combacia (tutti skipped -> rosso_raccolta); senza vitest_ids il rosso non e' suo.
FIC_CP_PARALLEL=1 cpr "$(mj gt.json "[$(entry GT $V/src.ts 'x = 1' 'x = 2 // ROSSO' "$V/tests/a.test.ts" 'somma > vale uno')]")"
check "nome «describe > it»: -t col fullName, rosso sull asserzione" '[ "$(rc)" = 0 ] && [ "$(field GT esito)" = rosso_asserzione ] && grep -q -- "-t somma vale uno" "$FAKE_LOG.all"'
cpr "$(mj pk.json "[$(entry PK1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),$(entry PK2 $V/other.ts 'y = 1' 'y = 2 // ROSSO')]")"
check "default: parallelo senza variabili" '[ "$(rc)" = 0 ] && grep -q "gradino 2" "$T/out"'
FIC_CP_MEM_MB=99999999 cpr "$(mj pk.json "[$(entry PK1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),$(entry PK2 $V/other.ts 'y = 1' 'y = 2 // ROSSO')]")"
check "memoria insufficiente per 2 run -> seriale nel mirror" '[ "$(rc)" = 0 ] && ! grep -q "gradino 2" "$T/out" && tail -1 "$T/out" | grep -q "luogo=mirror"'
check "  nel seriale nessuna variabile di vite (config identica)" '[ "$(grep -c "^cache=$" "$FAKE_LOG.all")" = 2 ] && [ "$(grep -c "^allow=$" "$FAKE_LOG.all")" = 2 ]'

# 1c. un secondo scrittore durante il gradino 2: non prende il mirror (tetto 1 s -> BLOCKED 3), non lo cambia
mkdir -p "$T/second"
printf '[%s]\n' "$(entry S1 $V/other.ts 'y = 1' 'y = 2 // ROSSO')" > "$T/second/mutations.json"
MIRS=$(mir_hash)
FAKE_SECOND="$T/second/mutations.json" FAKE_SECOND_SCRIPT="$CP" FIC_CP_PARALLEL=2 \
  cpr "$(mj pk.json "[$(entry PK1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),$(entry PK2 $V/other.ts 'y = 1' 'y = 2 // ROSSO')]")"
check "secondo scrittore durante il gradino 2 -> attende e resta fuori (exit 3), il primo finisce" '[ "$(rc)" = 0 ] && grep -qx "second=3" "$FAKE_LOG.all" && grep -q "mirror occupato" "$T/second/mutations.json.out"'
check "  il secondo non ha eseguito nulla e non ha cambiato il mirror" '[ ! -e "$T/second/S1.json" ] && [ "$(mir_hash)" = "$MIRS" ]'

# 2. lock occupato oltre il tetto -> exit 3, niente eseguito, nessun ripiego
( flock 9; sleep 5 ) 9>"$M/.fic-lock" & holder=$!
sleep 1
FIC_LOCK_WAIT=1 cpr "$LIST"
check "lock occupato oltre il tetto -> exit 3, BLOCKED" '[ "$(rc)" = 3 ] && grep -q "esito=BLOCKED (mirror occupato" "$T/out"'
check "  nessun runner lanciato (ne mirror ne /mnt/c)" '[ ! -f "$FAKE_LOG.all" ]'
wait $holder

# 3. lock occupato ma liberato entro il tetto -> si attende e si esegue
( flock 9; sleep 2 ) 9>"$M/.fic-lock" & holder=$!
sleep 1
FIC_LOCK_WAIT=20 cpr "$(mj one.json "[$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')]")"
check "lock liberato entro il tetto -> attende ed esegue" '[ "$(rc)" = 0 ] && tail -1 "$T/out" | grep -q "esito=PASS prove=1/1"'
wait $holder

# 4. sync che non allinea -> exit 3, niente eseguito
echo 'export const x = 1 // divergente' > "$AD/src.ts"
FAKE_RSYNC_NOOP=1 cpr "$(mj one.json "[$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')]")"
check "copia non allineata -> exit 3, nessun runner" '[ "$(rc)" = 3 ] && grep -q "copia non allineata" "$T/out" && [ ! -f "$FAKE_LOG.all" ]'
echo 'export const x = 1' > "$AD/src.ts"

# 5. dipendenze stantie -> la copia si riallinea da sola dall'origine (che ha node_modules), sotto il lock, e la
#    prova gira nel mirror; rsync fallito o nessuna fonte -> exit 3 col motivo
fp() { ( . "$HERE/fic-mirror.sh"; fic_deps_fp "$1" ); }
old12=$(cut -c1-12 "$M/.fic-deps")
echo '{"lock":2}' > "$A/package-lock.json"; echo 'nuovo' > "$A/node_modules/dep/nuovo.js"
new12=$(fp "$A" | cut -c1-12)
cpr "$(mj one.json "[$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')]")"
check "dipendenze stantie -> riallineamento automatico, riga d avviso, prova eseguita nel mirror" '[ "$(rc)" = 0 ] && grep -qx "counterproof: dipendenze cambiate (impronta $old12 -> $new12): copia riallineata dall'"'"'origine" "$T/out" && grep -q "^cwd=$M/apps/admin" "$FAKE_LOG.all" && [ "$(field A1 esito)" = rosso_asserzione ]'
check "  .fic-deps aggiornato, node_modules copiati" '[ "$(cat "$M/.fic-deps")" = "$(fp "$A")" ] && [ -f "$M/node_modules/dep/nuovo.js" ]'
rm -f "$A/node_modules/dep/nuovo.js"; echo '{"lock":3}' > "$A/package-lock.json"
FAKE_RSYNC_FAIL=1 cpr "$(mj one.json "[$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')]")"
check "  rsync del riallineamento fallito -> exit 3 col motivo, nessun runner" '[ "$(rc)" = 3 ] && grep -q "dipendenze stantie, riallineamento automatico non riuscito: rsync dall'"'"'origine fallito (uscita 23)" "$T/out" && [ ! -f "$FAKE_LOG.all" ]'
mv "$A/node_modules" "$T/nm.via"
cpr "$(mj one.json "[$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')]")"
check "  origine senza node_modules, nessuna fonte -> exit 3 col motivo" '[ "$(rc)" = 3 ] && grep -q "riallineamento automatico non riuscito: l'"'"'origine non ha node_modules" "$T/out" && [ ! -f "$FAKE_LOG.all" ]'
mv "$T/nm.via" "$A/node_modules"
# riallineamento che esce 0 ma registra un'impronta sbagliata (fic_deps_fp finto al momento della scrittura) -> exit 3;
# la variante di fic-mirror.sh sta in una copia del plugin (lo script include i file accanto a se')
PCF=$T/plug-fm; mkplug "$PCF"
sed '0,/^  fic_deps_fp "\$src" > "\$dst\/.fic-deps"/s//  echo sbagliata > "$dst\/.fic-deps"/' "$HERE/fic-mirror.sh" > "$PCF/scripts/fic-mirror.sh"
check "  premessa: impronta finta nel riallineamento" 'grep -q "^  echo sbagliata" "$PCF/scripts/fic-mirror.sh"'
CPX="$PCF/scripts/counterproof.sh" cpr "$(mj one.json "[$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')]")"
check "  riallineamento con impronta sbagliata -> exit 3 dal secondo controllo, nessun runner" '[ "$(rc)" = 3 ] && grep -q "dipendenze stantie anche dopo il riallineamento automatico" "$T/out" && [ ! -f "$FAKE_LOG.all" ]'
echo '{"lock":1}' > "$A/package-lock.json"

# 6. mutazione non applicabile (0 occorrenze, poi 2) -> bloccata, exit 2, file intatto
echo 'export const x = 1; export const x2 = 1' > "$AD/dup.ts"
(cd "$R" && git add -A && git commit -qm dup)
cpr "$(mj nomatch.json "[$(entry NM $V/src.ts 'non esiste' 'boh'),$(entry TWO $V/dup.ts '= 1' '= 2')]")"
check "cerca assente o ambiguo -> bloccato, exit 2" '[ "$(rc)" = 2 ] && [ "$(field NM esito)" = bloccato ] && [ "$(field TWO controprova)" = BLOCKED ] && grep -q "compare 2 volte" "$OUT/TWO.json"'
check "  nessun runner lanciato" '[ ! -f "$FAKE_LOG.all" ]'

# 7. rosso su un altro messaggio -> rosso_diverso
cpr "$(mj div.json "[$(entry DIV $V/src.ts 'x = 1' 'x = 1 // DIVERSO')]")"
check "rosso non sull asserzione -> rosso_diverso, FAIL" '[ "$(rc)" = 1 ] && [ "$(field DIV esito)" = rosso_diverso ]'

# 8. test nominato inesistente -> rosso_raccolta (mai verde)
cpr "$(mj rac.json "[$(entry RAC $V/src.ts 'x = 1' 'x = 2 // ROSSO' $V/tests/a.test.ts 'non esiste' 'expected')]")"
check "test nominato non eseguito -> rosso_raccolta" '[ "$(field RAC esito)" = rosso_raccolta ] && [ "$(field RAC controprova)" = FAIL ]'

# 9. pytest: errore di raccolta per import -> rosso_import
cpr "$(mj pyi.json "[$(entry PYI modules/api/app/core.py 'UNO = 1' 'UNO = 1  # IMPORTROTTO' modules/api/tests/test_core.py 'tests/test_core.py::test_uno' 'assert 2 == 1')]")"
check "pytest: import rotto in raccolta -> rosso_import" '[ "$(field PYI esito)" = rosso_import ]'

# 10. input non valido -> 64, niente eseguito
cpr "$(mj bad.json "[$(entry X modules/api/app/core.py 'UNO = 1' 'UNO = 2')]")"
check "file backend osservato con un test vitest -> 64" '[ "$(rc)" = 64 ] && [ ! -f "$FAKE_LOG.all" ]'
cpr "$(mj bad2.json '[{"id":"X","file":"modules/app/apps/admin/src.ts"}]')"
check "voce incompleta -> 64" '[ "$(rc)" = 64 ]'
cpr "$(mj bad3.json "[$(entry X $V/src.ts 'x = 1' 'x = 2'),$(entry X $V/other.ts 'y = 1' 'y = 2')]")"
check "id duplicato -> 64" '[ "$(rc)" = 64 ] && grep -q "id duplicato" "$T/out"'

# 10b. L2 (harness-pt11): voce "assorbita" -> non eseguita, <id>.json con esito assorbita; solo assorbite -> exit 0,
#      nessun runner. Controprova (a mano, CP=<variante> senza SALTO-ASSORBITE): l'assorbita verrebbe eseguita.
AB=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["assorbita"]=True; d["motivo"]="L2 prova"; print(json.dumps(d))' "$(entry AB1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')")
cpr "$(mj ab.json "[$AB,$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')]")"
check "assorbita saltata: A1 eseguita, AB1 no" '[ "$(rc)" = 0 ] && [ "$(field AB1 esito)" = assorbita ] && [ "$(field AB1 controprova)" = ASSORBITA ] && [ "$(field AB1 motivo)" = "L2 prova" ] && [ "$(field A1 esito)" = rosso_asserzione ] && [ "$(grep -c "args=vitest" "$FAKE_LOG.all")" = 1 ]'
check "  ultima riga: prove 1/1 e assorbite=1" 'tail -1 "$T/out" | grep -q "esito=PASS prove=1/1 .*assorbite=1"'
cpr "$(mj ab2.json "[$AB]")"
check "solo assorbite -> exit 0, nessun runner" '[ "$(rc)" = 0 ] && [ ! -f "$FAKE_LOG.all" ] && tail -1 "$T/out" | grep -q "esito=PASS prove=0/0 .*assorbite=1" && [ "$(field AB1 esito)" = assorbita ]'
cpr "$(mj ab3.json "[$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["assorbita"]="si"; print(json.dumps(d))' "$(entry AB2 $V/src.ts 'x = 1' 'x = 2')")]")"
check "assorbita non booleana -> 64" '[ "$(rc)" = 64 ]'
check "opzione al posto del path -> 64" 'PROJECT_ROOT=$R bash "$CP" --help >/dev/null 2>&1; [ $? -eq 64 ]'

# 11. morte a meta' run: il trap rimette il file del mirror
MIR1=$(mir_hash)
FAKE_KILL="$CP" cpr "$(mj one.json "[$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')]")"
check "morte durante il run: il trap ripristina il mirror" '[ "$(mir_hash)" = "$MIR1" ] && grep -qx "export const x = 1" "$M/apps/admin/src.ts"'

# 11b. segnale durante il gradino 2: nessun processo superstite (neanche nei gruppi di timeout), nessuna copia
alive() { local p s; for p in $(cat "$FAKE_LOG.pids" 2>/dev/null); do s=$(ps -o stat= -p "$p" 2>/dev/null); [ -n "$s" ] && [ "${s#Z}" = "$s" ] && echo "$p"; done; }
rm -f "$FAKE_LOG.pids"
t0=$(date +%s)
FAKE_KILL="$CP" FAKE_KILL_SLEEP=30 FIC_CP_PARALLEL=2 \
  cpr "$(mj pk.json "[$(entry PK1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),$(entry PK2 $V/other.ts 'y = 1' 'y = 2 // ROSSO')]")"
sleep 1
check "segnale nel gradino 2: il trap non aspetta la fine dei run" '[ $(( $(date +%s) - t0 )) -lt 25 ] && [ "$(rc)" = 143 ]'
check "  nessun processo dei run superstite" '[ -s "$FAKE_LOG.pids" ] && [ -z "$(alive)" ]'
check "  nessuna copia fic-cp.* residua, mirror invariato, lock libero" '! ls -d "$HOME"/fic-cp.* >/dev/null 2>&1 && [ "$(mir_hash)" = "$MIR1" ] && flock -n "$M/.fic-lock" true'
for p in $(alive); do kill -KILL "$p" 2>/dev/null; done

# 12. da un worktree (pt03): stessa regola di test-fast.sh — copia ~/fic-mirror-<hash> (seminata da
#     ~/fic-mirror) e SUO lock; il codice del worktree non entra mai nella copia del tree principale.
#     Controprova: destinazione fissa ~/fic-mirror -> rosso.
(cd "$R" && git add -A && git commit -qm pre-worktree) > /dev/null 2>&1
W=$T/wt
(cd "$R" && git worktree add -q -b wt "$W") > /dev/null 2>&1
echo 'export const x = 1 // del worktree' > "$W/modules/app/apps/admin/src.ts"
WM=$HOME/fic-mirror-$(printf '%s' "$(git -C "$W" rev-parse --show-toplevel)" | sha256sum | cut -c1-12)/modules/app
mkdir -p "$W/run/counterproof"
printf '[%s]\n' "$(entry W1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')" > "$W/run/counterproof/mutations.json"
MIRW=$(mir_hash)
rm -f "$FAKE_LOG.all"
FAKE_LOCKFILE=$WM/.fic-lock PROJECT_ROOT=$W bash "$CP" "$W/run/counterproof/mutations.json" > "$T/out" 2>&1; echo $? > "$T/rc"
check "worktree: gira nella copia ~/fic-mirror-<hash> del worktree, seminata" '[ "$(rc)" = 0 ] && grep -q "^cwd=$WM/apps/admin " "$FAKE_LOG.all" && [ -d "$WM/node_modules/dep" ] && tail -1 "$T/out" | grep -q "esito=PASS prove=1/1"'
check "  la mutazione vista e' sul codice del worktree" 'grep -q "seen=export const x = 2 // ROSSO // del worktree" "$FAKE_LOG.all"'
check "  sotto il lock della copia del worktree" 'grep -q "^lock=occupato" "$FAKE_LOG.all"'
check "  la copia del tree principale non e' stata toccata" '[ "$(mir_hash)" = "$MIRW" ] && grep -qx "export const x = 1" "$M/apps/admin/src.ts"'

# 13. pytest: la copia porta anche le cartelle di `copia_anche` del modulo (nell'esempio modules/db/prisma, lo
#     schema letto dai test di copertura), allineate con --delete. Controprova: senza il ciclo su copia_anche in
#     counterproof.sh -> rosso.
mkdir -p "$R/modules/db/prisma/migrations/m1"
echo 'model a { id Int @id }' > "$R/modules/db/prisma/schema.prisma"
echo 'SELECT 1;' > "$R/modules/db/prisma/migrations/m1/migration.sql"
cpr "$(mj nc.json "[$(entry NC modules/api/app/core.py 'UNO = 1' 'UNO = 1  # ROSSO' modules/api/tests/test_core.py 'tests/test_core.py::test_uno' 'assert 2 == 1')]")"
check "pytest: schema.prisma copiato nella copia" 'cmp -s "$R/modules/db/prisma/schema.prisma" "$HOME/fic-mirror/modules/db/prisma/schema.prisma"'
rm -rf "$R/modules/db/prisma/migrations/m1"
cpr "$(mj nc2.json "[$(entry NC2 modules/api/app/core.py 'UNO = 1' 'UNO = 1  # ROSSO' modules/api/tests/test_core.py 'tests/test_core.py::test_uno' 'assert 2 == 1')]")"
check "  allineata: una migrazione tolta sparisce dalla copia" '[ ! -e "$HOME/fic-mirror/modules/db/prisma/migrations/m1" ] && [ -f "$HOME/fic-mirror/modules/db/prisma/schema.prisma" ]'

# 14. sync per modulo sull'esempio: mutazioni su entrambi i moduli -> sorgenti, destinazioni ed esclusioni efficaci
#     di prima (EXCL_APP per modules/app, EXCL_API per modules/api, ora dall'elenco unico del nucleo) e pulizia di
#     .nuxt e delle cache di vite/vitest sotto <copia>/modules/app, a ogni sync.
for d in "$M/apps/admin/.nuxt" "$M/apps/admin/node_modules/.vite" "$M/node_modules/.vite" "$M/node_modules/.vitest"; do
  mkdir -p "$d" && echo x > "$d/marker"
done
RL=$T/rsync.log; rm -f "$RL"
FAKE_RSYNC_LOG=$RL FIC_CP_PARALLEL=1 cpr "$(mj both.json "[$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),$(entry PY modules/api/app/core.py 'UNO = 1' 'UNO = 1  # ROSSO' modules/api/tests/test_core.py 'tests/test_core.py::test_uno' 'assert 2 == 1')]")"
rline() { grep -- "--delete --checksum --exclude=" "$RL" | grep -- " $1/ $2/\$"; }
has_ex() { local l=$1 e; shift; for e in "$@"; do case " $l " in *" --exclude=$e "*) ;; *) return 1 ;; esac; done; }
check "sync per modulo: prove su entrambi i moduli" '[ "$(rc)" = 0 ] && tail -1 "$T/out" | grep -q "esito=PASS prove=2/2"'
check "  modules/app: <repo>/modules/app -> <copia>/modules/app, esclusioni di prima" 'l=$(rline "$A" "$M") && [ "$(printf "%s\n" "$l" | wc -l)" = 1 ] && has_ex "$l" node_modules .nuxt .output coverage .turbo "/.fic-*"'
check "  modules/api: <repo>/modules/api -> <copia>/modules/api, esclusioni di prima" 'l=$(rline "$API" "$MA") && [ "$(printf "%s\n" "$l" | wc -l)" = 1 ] && has_ex "$l" .venv __pycache__ .pytest_cache "/.fic-*"'
check "  copia_anche: <repo>/modules/db/prisma con --delete, senza node_modules" 'grep -qx -- "-a --delete --checksum --exclude=node_modules $R/modules/db/prisma/ $HOME/fic-mirror/modules/db/prisma/" "$RL"'
check "  pulizia: .nuxt e cache di vite/vitest tolte sotto <copia>/modules/app" '! ls "$M/apps/admin/.nuxt/marker" "$M/apps/admin/node_modules/.vite/marker" "$M/node_modules/.vite/marker" "$M/node_modules/.vitest/marker" >/dev/null 2>&1'

# 15. N moduli dichiarati (configurazione propria): uno con copia, due senza, radici qualunque, uno senza controprova.
#     Si sincronizzano solo i moduli delle mutazioni, ognuno nella sua <copia>/<radice_pacchetti>; il modulo con copia
#     fuori dalle mutazioni non si semina ne' si verifica. Runner `comando`: rosso = uscita != 0 -> rosso_generico
#     (prova debole), uscita 0 -> verde. Modulo senza controprova -> NOT RUN (dichiarato).
#     Controprove: ciclo sui moduli cablato (MODS=(app api)) -> il terzo modulo non si sincronizza e il caso e' rosso;
#     rosso_generico classificato rosso_asserzione -> rosso.
for d in x/web/app y/svc z/lib w/doc; do
  mkdir -p "$R/$d"; echo 'UNO=1' > "$R/$d/core.txt"
  printf 'grep -q ROSSO core.txt && { echo "rosso: ROSSO in core.txt"; exit 1; }\nexit 0\n' > "$R/$d/t.sh"
done
(cd "$R" && git add -A && git commit -qm tre-moduli) > /dev/null 2>&1
CMDC='"controprova": {"runner": "comando", "comando": "bash {test}"}'
cat > "$T/tre.json" <<EOF
{"versione_schema": 1, "moduli": [
  {"nome": "web", "radice": "x/web/app", "radice_pacchetti": "x/web", "copia": {"test": "true {test}"}, $CMDC},
  {"nome": "svc", "radice": "y/svc", $CMDC},
  {"nome": "lib", "radice": "z/lib", $CMDC},
  {"nome": "doc", "radice": "w/doc"}
]}
EOF
te() { entry "$1" "$2/core.txt" 'UNO=1' "${3:-UNO=1 ROSSO}" "$2/t.sh" "$2/t.sh" 'rosso'; }
MAAT_CONFIG=$T/tre.json cpr "$(mj tre.json "[$(te S1 y/svc),$(te L1 z/lib),$(te D1 w/doc)]")"
check "N moduli: svc e lib eseguiti, doc NOT RUN, exit 0" '[ "$(rc)" = 0 ] && tail -1 "$T/out" | grep -q "esito=PASS prove=2/2 .*non_eseguite=1"'
check "  runner comando: rosso = uscita != 0 -> rosso_generico, PASS (prova debole)" '[ "$(field S1 esito)" = rosso_generico ] && [ "$(field S1 controprova)" = PASS ] && [ "$(field L1 esito)" = rosso_generico ] && [ "$(field S1 runner)" = comando ]'
check "  ognuno nella sua <copia>/<radice_pacchetti>, ripristinato" 'grep -qx "UNO=1" "$HOME/fic-mirror/y/svc/core.txt" && grep -qx "UNO=1" "$HOME/fic-mirror/z/lib/core.txt"'
check "  solo i moduli delle mutazioni: web e doc non sincronizzati" '[ ! -e "$HOME/fic-mirror/x/web/app" ] && [ ! -e "$HOME/fic-mirror/w" ]'
check "  modulo senza controprova -> non_eseguita, NOT RUN (dichiarato), mai verde ne rosso" '[ "$(field D1 esito)" = non_eseguita ] && [ "$(field D1 controprova)" = "NOT RUN" ] && field D1 motivo | grep -q "^NOT RUN (dichiarato): il modulo doc non dichiara controprova"'
MAAT_CONFIG=$T/tre.json cpr "$(mj tre-v.json "[$(te V1 z/lib 'UNO=2')]")"
check "  runner comando: uscita 0 -> verde, FAIL" '[ "$(rc)" = 1 ] && [ "$(field V1 esito)" = verde ] && [ "$(field V1 controprova)" = FAIL ]'
MAAT_CONFIG=$T/tre.json cpr "$(mj tre-d.json "[$(te D2 w/doc)]")"
check "  solo moduli senza controprova -> esito=NOT RUN, exit 0, niente mirror" '[ "$(rc)" = 0 ] && tail -1 "$T/out" | grep -q "esito=NOT RUN prove=0/0 .*non_eseguite=1" && [ ! -e "$HOME/fic-mirror/w" ]'
MAAT_CONFIG=$T/tre.json cpr "$(mj tre-w.json "[$(te W1 x/web/app)]")"
check "  il modulo con copia nelle mutazioni vuole la copia preparata (--setup): exit 3" '[ "$(rc)" = 3 ] && grep -q "mirror assente: eseguire test-fast.sh --setup" "$T/out"'
sed 's/"nome": "svc", "radice": "y\/svc", /"nome": "svc", "radice": "y\/svc", "copia": {"test": "true {test}"}, /' "$T/tre.json" > "$T/tre2.json"
MAAT_CONFIG=$T/tre2.json cpr "$(mj tre-2c.json "[$(te S1 y/svc),$(te W1 x/web/app)]")"
check "due moduli con copia nelle mutazioni -> exit 64 «più moduli con copia»" '[ "$(rc)" = 64 ] && grep -q "più moduli con copia" "$T/out"'

# 16. pk08, CAMBIA IL CONTRATTO (prima: PATH senza rsync -> BLOCKED). PATH senza rsync e senza flock (Git Bash su
#     Windows senza WSL) -> le controprove girano con la copia di ripiego (fic_sync: find, impronte sha256, tar) e il lock
#     con mkdir (fic_lock_dir), dichiarati in una riga, con gli esiti veri e la STESSA copia della via rsync (da una copia
#     derivata: file stantio, estranei, cartella al posto di un file, esclusi da tenere, anche dentro una cartella estranea
#     che quindi resta, come con rsync). Lock tenuto durante i run,
#     rilasciato alla fine e sul segnale; un lock vivo blocca (exit 3), uno orfano si riprende; gradino 2 (coda dei
#     worker col lock mkdir) con gli stessi esiti. Senza sha256sum, timeout, o rsync e tar -> BLOCKED col motivo.
#     Limite noto (pk04b-2): radice_pacchetti = radice del repository -> 64, uguale nelle due vie.
#     Controprove, eseguite qui: ripiego disattivato in fic_sync -> «sync fallito», rosso; --delete ignorato dal ripiego
#     -> copia diversa, rosso; lock mkdir mai rilasciato -> la cartella resta, rosso; strumenti non controllati -> rosso.
path_senza() { # <cartella> <nome…>: il PATH con le cartelle che contengono uno dei <nome> sostituite da <cartella>, che
               # ne collega ogni file tranne quelli; le cartelle /mnt/… (Windows, dentro WSL) restano fuori
  local dst=$1 d f b x hit out="" messa=0 skip; shift; skip=" $* "
  mkdir -p "$dst"
  local IFS=:
  for d in $PATH; do
    case "$d" in /mnt/*|"") continue ;; esac
    hit=0; for x in "$@"; do [ -e "$d/$x" ] && hit=1; done
    if [ "$hit" = 0 ]; then out+="${out:+:}$d"; continue; fi
    for f in "$d"/*; do
      b=${f##*/}
      case "$skip" in *" $b "*) continue ;; esac
      [ -e "$dst/$b" ] || [ -L "$dst/$b" ] || ln -s "$f" "$dst/$b"
    done
    [ "$messa" = 1 ] || { out+="${out:+:}$dst"; messa=1; }
  done
  printf '%s' "$out"
}
cpb() { # <PATH> <lista> [script]: come cpr, con il PATH dato
  rm -f "$FAKE_LOG.all"; PATH=$1 PROJECT_ROOT=$R "$BASH" "${3:-$CP}" "$2" > "$T/out" 2>&1; echo $? > "$T/rc"
}
diverge() { # la stessa deriva della copia prima di ogni giro
  echo 'export const x = 0 // stantio' > "$M/apps/admin/src.ts"
  echo estraneo > "$M/apps/admin/estraneo.ts"; mkdir -p "$M/apps/admin/vuota-estranea/sotto"
  mkdir -p "$M/apps/admin/vuota-estranea/node_modules" && echo x > "$M/apps/admin/vuota-estranea/node_modules/x"   # resta, come rsync
  rm -rf "$M/apps/admin/other.ts"; mkdir -p "$M/apps/admin/other.ts" && echo d > "$M/apps/admin/other.ts/dentro"
  mkdir -p "$M/apps/admin/node_modules/tieni" && echo t > "$M/apps/admin/node_modules/tieni/x"
  echo 'STANTIO = 1' > "$MA/app/estraneo.py"; mkdir -p "$MA/__pycache__" && echo c > "$MA/__pycache__/c.pyc"
  mkdir -p "$HOME/fic-mirror/modules/db/prisma" && echo 'model z {}' > "$HOME/fic-mirror/modules/db/prisma/estraneo.prisma"
}
albero_copia() { # tipo, percorso e contenuto di tutta la copia, lock esclusi
  (cd "$HOME/fic-mirror" && find . -name '.fic-lock*' -prune -o -printf '%y %p\n' | LC_ALL=C sort
   find . -name '.fic-lock*' -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) | sha256sum | cut -c1-64
}
L16=$(mj l16.json "[$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),$(entry VERDE $V/uncovered.ts 'w = 1' 'w = 2'),$(entry PY modules/api/app/core.py 'UNO = 1' 'UNO = 1  # ROSSO' modules/api/tests/test_core.py 'tests/test_core.py::test_uno' 'assert 2 == 1')]")
esiti16() { printf '%s %s %s' "$(field A1 esito)" "$(field VERDE esito)" "$(field PY esito)"; }
diverge; rm -f "$OUT/A1.json" "$OUT/VERDE.json" "$OUT/PY.json"
FIC_CP_PARALLEL=1 cpr "$L16"
RC_RS=$(rc); ES_RS=$(esiti16); AL_RS=$(albero_copia)
check "via rsync, copia derivata -> FAIL vero (A1 e PY rossi, VERDE verde), copia riallineata" '[ "$RC_RS" = 1 ] && [ "$ES_RS" = "rosso_asserzione verde rosso_asserzione" ] && [ ! -e "$M/apps/admin/estraneo.ts" ] && [ -f "$M/apps/admin/node_modules/tieni/x" ] && [ -f "$M/apps/admin/vuota-estranea/node_modules/x" ] && [ ! -e "$M/apps/admin/vuota-estranea/sotto" ]'
PX=$(path_senza "$T/bin-rf" rsync flock)
check "  premessa: PATH senza rsync e flock, con tar e sha256sum" '! PATH=$PX command -v rsync >/dev/null && ! PATH=$PX command -v flock >/dev/null && PATH=$PX command -v tar >/dev/null && PATH=$PX command -v sha256sum >/dev/null'
caso_ripiego() { # [script]: copia derivata, PATH senza rsync e flock -> stessi esiti e stessa copia della via rsync, lock
                 # di ripiego tenuto durante i due run vitest e rilasciato alla fine
  diverge; rm -f "$OUT/A1.json" "$OUT/VERDE.json" "$OUT/PY.json"
  FIC_CP_PARALLEL=1 FAKE_LOCKDIR=$M/.fic-lock.d cpb "$PX" "$L16" "${1:-$CP}"
  [ "$(rc)" = "$RC_RS" ] && [ "$(esiti16)" = "$ES_RS" ] && tail -1 "$T/out" | grep -q "esito=FAIL prove=2/3 fail=1 bloccate=0" &&
    [ "$(albero_copia)" = "$AL_RS" ] && [ "$(grep -c '^lockdir=presente' "$FAKE_LOG.all")" = 2 ] && [ ! -e "$M/.fic-lock.d" ]
}
check "PATH senza rsync e flock -> controprove eseguite: stessi esiti, stessa copia della via rsync, lock rilasciato" 'caso_ripiego'
check "  ripieghi dichiarati in una riga" 'grep -qx "counterproof: rsync assente: copia di ripiego (find, impronte sha256, tar); flock assente: lock di ripiego (mkdir atomico); piu'"'"' lenti, stessi esiti" "$T/out"'
check "  la mutazione l ha vista il runner nel mirror" 'grep -q "seen=export const x = 2 // ROSSO" "$FAKE_LOG.all" && ! grep "^cwd=" "$FAKE_LOG.all" | grep -v "^cwd=$HOME/fic-mirror/" | grep -q .'
# lock di ripiego tenuto da un processo vivo -> si attende, oltre il tetto exit 3; poi orfano (pid morto) -> ripreso
sleep 30 & vivo=$!
mkdir "$M/.fic-lock.d" && echo "$vivo" > "$M/.fic-lock.d/pid"
FIC_LOCK_WAIT=1 cpb "$PX" "$OUT/one.json"
check "  lock di ripiego di un processo vivo -> exit 3 «mirror occupato», niente eseguito, lock intatto" '[ "$(rc)" = 3 ] && grep -qF "esito=BLOCKED (mirror occupato oltre 1s (lock $M/.fic-lock.d)" "$T/out" && [ ! -f "$FAKE_LOG.all" ] && [ "$(cat "$M/.fic-lock.d/pid")" = "$vivo" ]'
kill "$vivo"; wait "$vivo" 2>/dev/null
FIC_LOCK_WAIT=5 cpb "$PX" "$OUT/one.json"
check "  lock orfano (pid morto) -> ripreso, prova eseguita, lock rilasciato" '[ "$(rc)" = 0 ] && tail -1 "$T/out" | grep -q "esito=PASS prove=1/1" && [ ! -e "$M/.fic-lock.d" ] && [ ! -e "$M/.fic-lock.d.rec" ]'
# gradino 2: copie private col ripiego, coda dei worker col lock mkdir
FIC_CP_PARALLEL=2 cpb "$PX" "$(mj pk.json "[$(entry PK1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),$(entry PK2 $V/other.ts 'y = 1' 'y = 2 // ROSSO')]")"
check "  gradino 2 senza rsync e flock: stessi esiti, ogni mutazione una volta, copie cancellate, lock rilasciato" '[ "$(rc)" = 0 ] && tail -1 "$T/out" | grep -q "esito=PASS prove=2/2 .*luogo=copie(2)" && [ "$(field PK1 esito)" = rosso_asserzione ] && [ "$(field PK2 esito)" = rosso_asserzione ] && [ "$(grep -c "args=vitest" "$FAKE_LOG.all")" = 2 ] && ! ls -d "$HOME"/fic-cp.* >/dev/null 2>&1 && [ ! -e "$M/.fic-lock.d" ]'
# segnale a meta' run: il trap ripristina il mirror e rilascia il lock di ripiego
FAKE_KILL="$CP" cpb "$PX" "$OUT/one.json"
check "  segnale durante il run -> exit 143, mirror ripristinato, lock di ripiego rilasciato" '[ "$(rc)" = 143 ] && grep -qx "export const x = 1" "$M/apps/admin/src.ts" && [ ! -e "$M/.fic-lock.d" ]'
# strumenti senza ripiego
for v in "sha256sum|rsync flock sha256sum" "timeout|timeout" "rsync e tar|rsync tar flock"; do
  cpb "$(path_senza "$T/bin-${v#*|}" ${v#*|})" "$OUT/one.json"
  check "senza ${v%%|*} -> exit 3, «controprove non disponibili: manca ${v%%|*}», niente eseguito" '[ "$(rc)" = 3 ] && grep -q "esito=BLOCKED (controprove non disponibili: manca ${v%%|*})" "$T/out" && [ ! -f "$FAKE_LOG.all" ]'
done
# limite noto: radice_pacchetti = radice del repository -> 64 col motivo, con rsync e senza
echo "{\"versione_schema\": 1, \"moduli\": [{\"nome\": \"tutto\", \"radice\": \".\", $CMDC}]}" > "$T/radice.json"
RADL=$(mj rad.json "[$(entry R1 y/svc/core.txt 'UNO=1' 'UNO=1 ROSSO' y/svc/t.sh y/svc/t.sh 'rosso')]")
MAAT_CONFIG=$T/radice.json cpr "$RADL"; RAD1="$(rc) $(grep -c "la copia vuole una cartella" "$T/out")"
MAAT_CONFIG=$T/radice.json cpb "$PX" "$RADL"; RAD2="$(rc) $(grep -c "la copia vuole una cartella" "$T/out")"
check "radice_pacchetti = radice del repository -> 64 «la copia vuole una cartella», uguale con rsync e senza" '[ "$RAD1" = "64 1" ] && [ "$RAD2" = "64 1" ]'
# controprove per mutazione (copie del plugin con fic-mirror.sh o counterproof.sh mutati)
mut16() { # <nome> <file> <sed>: copia del plugin con <file> mutato -> il suo counterproof.sh; vuoto se la sed non cambia nulla
  local d=$T/mut16-$1; mkplug "$d"; sed "$3" "$HERE/$2" > "$d/scripts/$2"
  cmp -s "$HERE/$2" "$d/scripts/$2" || printf '%s' "$d/scripts/counterproof.sh"
}
m=$(mut16 senza-ripiego fic-mirror.sh 's/^  if command -v rsync >\/dev\/null 2>&1; then rsync -a "\$@"; else fic__sync_ripiego "\$@"; fi$/  rsync -a "$@"/')
check "controprova: ripiego disattivato (fic_sync solo rsync) -> «sync fallito», rosso" '[ -n "$m" ] && ! caso_ripiego "$m" && grep -q "esito=BLOCKED (sync fallito" "$T/out"'
m=$(mut16 senza-delete fic-mirror.sh 's/^      --delete) del=1 ;;$/      --delete) ;;/')
check "controprova: --delete ignorato dal ripiego -> copia diversa da quella di rsync, rosso" '[ -n "$m" ] && ! caso_ripiego "$m"'
m=$(mut16 senza-rilascio fic-mirror.sh 's/^  \[ "\$(cat "\$d\/pid" 2>\/dev\/null)" = "\$me" \] && rm -rf -- "\$d"$/  :/')
check "controprova: lock mkdir mai rilasciato -> la cartella resta, rosso" '[ -n "$m" ] && ! caso_ripiego "$m" && [ -d "$M/.fic-lock.d" ]'
rm -rf "$M/.fic-lock.d"
m=$(mut16 senza-strumenti counterproof.sh 's/^for t in sha256sum timeout; do/for t in ; do/')
cpb "$(path_senza "$T/bin-sha256sum-m" rsync flock sha256sum)" "$OUT/one.json" "$m"
check "controprova: strumenti non controllati -> niente «manca sha256sum», rosso" '[ -n "$m" ] && ! grep -q "manca sha256sum" "$T/out"'
caso_ripiego >/dev/null   # copia riallineata dopo i mutanti
rm -rf "$M/apps/admin/node_modules/tieni" "$M/apps/admin/vuota-estranea" "$MA/__pycache__"

# 17. radice del progetto: da PROJECT_ROOT, mai dalla posizione dello script; senza (fuori da un repo) -> exit 64.
#     Controprova: ROOT di nuovo da $HERE/../.. -> i casi sopra sono rossi.
mkdir -p "$T/nogit"
(cd "$T/nogit" && env -u PROJECT_ROOT -u FIC_REPO bash "$CP" "$OUT/one.json" > "$T/out" 2>&1; echo $? > "$T/rc")
check "PROJECT_ROOT non risolvibile -> exit 64" '[ "$(rc)" = 64 ] && grep -q "radice del progetto non risolta" "$T/out"'

# 18. {python} del modulo be (ambiente wsl): senza FIC_PYTEST_PY la ricerca di gates.sh fra i candidati del modulo
#     (.venv312/bin/python, .venv/bin/python): nessuno -> exit 3 «python WSL assente»; il primo che esiste vince.
FIC_PYTEST_PY= cpr "$(mj pyw.json "[$(entry PW modules/api/app/core.py 'UNO = 1' 'UNO = 1  # ROSSO' modules/api/tests/test_core.py 'tests/test_core.py::test_uno' 'assert 2 == 1')]")"
check "python WSL assente fra i candidati del modulo -> exit 3, niente eseguito" '[ "$(rc)" = 3 ] && grep -q "esito=BLOCKED (python WSL assente: $API/.venv312/bin/python $API/.venv/bin/python)" "$T/out" && [ ! -f "$FAKE_LOG.all" ]'
mkdir -p "$API/.venv/bin" && cp "$BIN/fakepy" "$API/.venv/bin/python" && chmod +x "$API/.venv/bin/python"
FIC_PYTEST_PY= cpr "$OUT/pyw.json"
check "  il primo candidato che esiste (.venv/bin/python) esegue il test" '[ "$(rc)" = 0 ] && [ "$(field PW esito)" = rosso_asserzione ] && field PW comando | grep -q "$API/.venv/bin/python -B -m pytest"'
rm -rf "$API/.venv"

echo "counterproof.test.sh: $((n - fail))/$n ok"
[ $fail -eq 0 ]
