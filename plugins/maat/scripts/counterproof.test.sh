#!/usr/bin/env bash
# Deterministic tests of counterproof.sh, in a fake repo with a temporary HOME (never the real mirror,
# no real vitest or pytest, no /mnt/c). The script is launched FROM ITS LOCATION IN THE PLUGIN, with
# PROJECT_ROOT on the fake repo (never copied into the repo: the root must not come from the script location).
# The fake repo's configuration is examples/nuxt-fastapi.maat.json (modules fe and be, vitest and pytest runners
# declared); the cases on N modules and on the `comando` runner use their own configuration (MAAT_CONFIG).
# To be run in WSL:
#   wsl -- bash -lc 'bash /mnt/c/<maat>/plugins/maat/scripts/counterproof.test.sh'
# Variant to test (counterproofs by mutating the script): CP=<plugin copy>/scripts/counterproof.sh — the
# variant lives in a copy of the plugin (scripts/ with lib/, fic-mirror.sh, maat-config.py, python.sh; schemas/;
# .claude-plugin/), because it sources the files next to itself.
set -u
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(dirname "$HERE")
CP=${CP:-$HERE/counterproof.sh}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; fail=0
check() { n=$((n + 1)); if eval "$2"; then :; else fail=$((fail + 1)); echo "FAIL: $1"; fi; }
# 1.6.0: the cases of step 2 in parallel want N >= 2, and counterproof.sh caps N at nproc/2: on a machine with fewer
# than 4 CPUs (the macOS runner of the CI: 3) step 2 is rightly serial, and those cases are SALTATO, declared
NPROC=$(nproc 2>/dev/null || echo 0)
check_par() { if [ $((NPROC / 2)) -ge 2 ]; then check "$@"; else echo "SALTATO [$1]: il gradino 2 vuole almeno 4 CPU (nproc $NPROC)"; fi; }
unset MAAT_CONFIG MAAT_ROOT FIC_REPO PROJECT_ROOT FIC_GATES_VENV_PY MAAT_MODULO

# fake repo: .claude/maat.json (the example) + modules/app + modules/api
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
# 1.6.0: the real rsync found in the PATH, not /usr/bin/rsync (on macOS that is openrsync; GNU rsync from Homebrew is in
# the PATH). The same file on Linux.
export FAKE_RSYNC_VERO=$(command -v rsync)
# fake vitest (npx): reads the sources in the cwd (the mirror's apps/admin) and writes the JSON report like vitest 1.6.
#   IMPORTROTTO in a source -> the test file does not load · ROSSO in src.ts/other.ts -> "somma vale uno"
#   red on "expected 2 to be 1" · DIVERSO -> red with another message · "altro resta verde" always green.
#   -t filters by regex on fullName (the other tests come out skipped). FAKE_KILL: kills counterproof halfway.
cat > "$BIN/npx" <<'EOF'
#!/usr/bin/env bash
exec 9>&- 2>/dev/null
echo "cwd=$PWD args=$*" >> "$FAKE_LOG.all"
echo "cache=${FIC_VITE_CACHE_DIR:-}" >> "$FAKE_LOG.all"
echo "allow=${FIC_VITE_FS_ALLOW:-}" >> "$FAKE_LOG.all"
if flock -n "$FAKE_LOCKFILE" true; then echo "lock=libero" >> "$FAKE_LOG.all"; else echo "lock=occupato" >> "$FAKE_LOG.all"; fi
# FAKE_LOCKDIR: is the fallback lock (mkdir, without flock) present during the run?
[ -z "${FAKE_LOCKDIR:-}" ] || { if [ -d "$FAKE_LOCKDIR" ]; then echo lockdir=presente; else echo lockdir=assente; fi; } >> "$FAKE_LOG.all"
echo "seen=$(cat src.ts other.ts uncovered.ts 2>/dev/null | tr '\n' ' ')" >> "$FAKE_LOG.all"
# FAKE_SECOND: only once, a second counterproof.sh (lock wait cap 1 s) tries to take the mirror
if [ -n "${FAKE_SECOND:-}" ] && mkdir "$FAKE_SECOND.once" 2>/dev/null; then
  FIC_LOCK_WAIT=1 bash "$FAKE_SECOND_SCRIPT" "$FAKE_SECOND" > "$FAKE_SECOND.out" 2>&1; echo "second=$?" >> "$FAKE_LOG.all"
fi
# FAKE_KILL: signal to the running counterproof.sh; the run (and one of its children) stay alive FAKE_KILL_SLEEP seconds
if [ -n "${FAKE_KILL:-}" ]; then
  echo $$ >> "$FAKE_LOG.pids"
  # 1.6.0: the pkill of macOS (BSD) leaves out its own ancestors, and counterproof.sh is one of them (exit 1, no
  # signal; in step 2 it finds only the other worker); so the targets are what pgrep -f finds plus the ancestors whose
  # command line holds FAKE_KILL, all signalled with one kill: on Linux (procps) the same set as pkill. Collected
  # first, because a subshell signalled alone dies and breaks the chain up to counterproof.sh
  p=$$ tgt=""
  while p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') && [ -n "$p" ] && [ "$p" -gt 1 ]; do
    case "$(ps -o command= -p "$p" 2>/dev/null)" in *"$FAKE_KILL"*) tgt+=" $p" ;; esac
  done
  tgt=$(printf '%s\n' $tgt $(pgrep -f "$FAKE_KILL" 2>/dev/null) | sort -un)
  [ -z "$tgt" ] || kill -TERM $tgt 2>/dev/null
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
# fake pytest (FIC_PYTEST_PY): junit like pytest; ROSSO in app/core.py -> failure, IMPORTROTTO -> collection error
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
# fake rsync: FAKE_RSYNC_LOG records the arguments (sources, destinations, exclusions), then the real one
cat > "$BIN/rsync" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_RSYNC_LOG:-}" ] && printf '%s\n' "$*" >> "$FAKE_RSYNC_LOG"
[ -n "${FAKE_RSYNC_FAIL:-}" ] && exit 23
[ -n "${FAKE_RSYNC_NOOP:-}" ] && exit 0
exec "$FAKE_RSYNC_VERO" "$@"
EOF
chmod +x "$BIN/npx" "$BIN/fakepy" "$BIN/rsync"
export PATH="$BIN:$PATH" HOME=$T/home FAKE_LOG=$T/npx FIC_PYTEST_PY=$BIN/fakepy
mkdir -p "$HOME"
M=$HOME/fic-mirror/modules/app; MA=$HOME/fic-mirror/modules/api
export FAKE_LOCKFILE=$M/.fic-lock
OUT=$R/run/counterproof
# the copy as `test-fast.sh --setup` prepares it (origin with node_modules: fic_deps_refresh of fic-mirror.sh)
( . "$HERE/fic-mirror.sh" && fic_mirror_init "$R" && fic_deps_refresh "$A" "$FIC_MIRROR/modules/app" ) > /dev/null 2>&1

# CPX: a script other than $CP (a copy of the plugin with one changed file), for a single case
cpr() { rm -f "$FAKE_LOG.all"; PROJECT_ROOT=${CPR_ROOT:-$R} bash "${CPX:-$CP}" "$1" > "$T/out" 2>&1; echo $? > "$T/rc"; }
rc() { cat "$T/rc"; }
field() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print("" if v is None else v)' "$OUT/$1.json" "$2" 2>/dev/null; }
wt_hash() { (cd "$R" && find . -path ./.git -prune -o -path ./run -prune -o -type f -print | LC_ALL=C sort | xargs sha256sum) | sha256sum; }
mir_hash() { (cd "$HOME/fic-mirror" && find . -name node_modules -prune -o -type f ! -name '.fic-*' -print | LC_ALL=C sort | xargs sha256sum) | sha256sum; }
mj() { printf '%s\n' "$2" > "$OUT/$1"; echo "$OUT/$1"; }
mkplug() { # <dir>: copy of the plugin (scripts, lib, schemas, .claude-plugin) with $CP as counterproof.sh
  mkdir -p "$1/scripts"; cp -r "$PLUGIN/.claude-plugin" "$PLUGIN/schemas" "$1/"
  cp "$HERE"/*.sh "$HERE"/*.py "$1/scripts/"; cp -r "$HERE/lib" "$1/scripts/"; cp "$CP" "$1/scripts/counterproof.sh"
}

# entry: id file search replace [test] [test_id] [assertion]
V=modules/app/apps/admin
entry() {
  python3 -c 'import json,sys
i,f,c,s,t,tid,a=sys.argv[1:8]
print(json.dumps({"id":i,"file":f,"simbolo":"sym","mutazione":{"cerca":c,"sostituisci":s},"test":{"percorso":t,"nome":tid},"rosso_se":{"test_id":tid,"asserzione":a},"superficie":"S"}))' \
    "$1" "$2" "$3" "$4" "${5:-$V/tests/a.test.ts}" "${6:-somma vale uno}" "${7:-expected 2 to be 1}"
}

# 1. the full list: valid proof, exact duplicate, same assert from another file, import, not covered, pytest
LIST=$(mj mutations.json "[
$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),
$(entry A1-DUP $V/src.ts 'x = 1' 'x = 2 // ROSSO'),
$(entry B1 $V/other.ts 'y = 1' 'y = 2 // ROSSO'),
$(entry IMP $V/src.ts 'export const x = 1' 'import { z } from "./nope" // IMPORTROTTO
export const x = 1'),
$(entry VERDE $V/uncovered.ts 'w = 1' 'w = 2'),
$(entry PY modules/api/app/core.py 'UNO = 1' 'UNO = 1  # ROSSO' modules/api/tests/test_core.py 'tests/test_core.py::test_uno' 'assert 2 == 1')
]")
mkdir -p "$MA" && "$FAKE_RSYNC_VERO" -a --exclude=__pycache__ "$API/" "$MA/"   # initial state of the api mirror
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

# 1b. same list, step 2: private copies in parallel, same results
FIC_CP_PARALLEL=2 cpr "$LIST"
check_par "gradino 2: stessi esiti del seriale" '[ "$(rc)" = 1 ] && tail -1 "$T/out" | grep -q "esito=FAIL prove=4/6 fail=2 bloccate=0 .*luogo=copie(2)" && [ "$(field A1 esito)" = rosso_asserzione ] && [ "$(field B1 esito)" = rosso_asserzione ] && [ "$(field IMP esito)" = rosso_import ] && [ "$(field VERDE esito)" = verde ] && [ "$(field A1-DUP duplicato_di)" = A1 ] && [ "$(field PY esito)" = rosso_asserzione ]'
check_par "  i run vitest girano nelle copie private, fuori dal mirror" '[ "$(grep "args=vitest" "$FAKE_LOG.all" | grep -c "^cwd=$HOME/fic-cp\.")" = 4 ]'
check "  il backend resta seriale nel mirror" 'grep -q "^cwd=$MA args=-B -m pytest" "$FAKE_LOG.all"'
check_par "  cacheDir di vite privata per copia (2 distinte)" '[ "$(grep "^cache=$HOME/fic-cp\..*/.fic-vite-cache$" "$FAKE_LOG.all" | sort -u | wc -l)" = 2 ]'
check_par "  fs.allow = radice della copia + node_modules e packages del mirror" '[ "$(grep -c "^allow=$HOME/fic-cp\.[^/]*/[12]/modules/app:$M/node_modules:$M/packages$" "$FAKE_LOG.all")" = 4 ]'
check "  lock del mirror tenuto durante i run nelle copie" '[ "$(grep -c "^lock=occupato" "$FAKE_LOG.all")" = 4 ] && ! grep -q "^lock=libero" "$FAKE_LOG.all"'
check "  copie private cancellate alla fine" '! ls -d "$HOME"/fic-cp.* >/dev/null 2>&1'
check "  hash del working tree e del mirror invariati" '[ "$(wt_hash)" = "$WT0" ] && [ "$(mir_hash)" = "$MIR0" ]'
# 1c. goals-ux-12: test named "describe > it", as vitest prints it in FAILs. Counterproof: without the
# " > " form in pattern() -t does not match (all skipped -> rosso_raccolta); without vitest_ids the red is not its own.
FIC_CP_PARALLEL=1 cpr "$(mj gt.json "[$(entry GT $V/src.ts 'x = 1' 'x = 2 // ROSSO' "$V/tests/a.test.ts" 'somma > vale uno')]")"
check "nome «describe > it»: -t col fullName, rosso sull asserzione" '[ "$(rc)" = 0 ] && [ "$(field GT esito)" = rosso_asserzione ] && grep -q -- "-t somma vale uno" "$FAKE_LOG.all"'
cpr "$(mj pk.json "[$(entry PK1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),$(entry PK2 $V/other.ts 'y = 1' 'y = 2 // ROSSO')]")"
check_par "default: parallelo senza variabili" '[ "$(rc)" = 0 ] && grep -q "gradino 2" "$T/out"'
FIC_CP_MEM_MB=99999999 cpr "$(mj pk.json "[$(entry PK1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),$(entry PK2 $V/other.ts 'y = 1' 'y = 2 // ROSSO')]")"
check "memoria insufficiente per 2 run -> seriale nel mirror" '[ "$(rc)" = 0 ] && ! grep -q "gradino 2" "$T/out" && tail -1 "$T/out" | grep -q "luogo=mirror"'
check "  nel seriale nessuna variabile di vite (config identica)" '[ "$(grep -c "^cache=$" "$FAKE_LOG.all")" = 2 ] && [ "$(grep -c "^allow=$" "$FAKE_LOG.all")" = 2 ]'

# 1c. a second writer during step 2: does not take the mirror (1 s cap -> BLOCKED 3), does not change it
mkdir -p "$T/second"
printf '[%s]\n' "$(entry S1 $V/other.ts 'y = 1' 'y = 2 // ROSSO')" > "$T/second/mutations.json"
MIRS=$(mir_hash)
FAKE_SECOND="$T/second/mutations.json" FAKE_SECOND_SCRIPT="$CP" FIC_CP_PARALLEL=2 \
  cpr "$(mj pk.json "[$(entry PK1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),$(entry PK2 $V/other.ts 'y = 1' 'y = 2 // ROSSO')]")"
check "secondo scrittore durante il gradino 2 -> attende e resta fuori (exit 3), il primo finisce" '[ "$(rc)" = 0 ] && grep -qx "second=3" "$FAKE_LOG.all" && grep -q "mirror occupato" "$T/second/mutations.json.out"'
check "  il secondo non ha eseguito nulla e non ha cambiato il mirror" '[ ! -e "$T/second/S1.json" ] && [ "$(mir_hash)" = "$MIRS" ]'

# 2. lock held beyond the cap -> exit 3, nothing run, no fallback
( flock 9; sleep 5 ) 9>"$M/.fic-lock" & holder=$!
sleep 1
FIC_LOCK_WAIT=1 cpr "$LIST"
check "lock occupato oltre il tetto -> exit 3, BLOCKED" '[ "$(rc)" = 3 ] && grep -q "esito=BLOCKED (mirror occupato" "$T/out"'
check "  nessun runner lanciato (ne mirror ne /mnt/c)" '[ ! -f "$FAKE_LOG.all" ]'
wait $holder

# 3. lock held but released within the cap -> waits and runs
( flock 9; sleep 2 ) 9>"$M/.fic-lock" & holder=$!
sleep 1
FIC_LOCK_WAIT=20 cpr "$(mj one.json "[$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')]")"
check "lock liberato entro il tetto -> attende ed esegue" '[ "$(rc)" = 0 ] && tail -1 "$T/out" | grep -q "esito=PASS prove=1/1"'
wait $holder

# 4. sync that does not align -> exit 3, nothing run
echo 'export const x = 1 // divergente' > "$AD/src.ts"
FAKE_RSYNC_NOOP=1 cpr "$(mj one.json "[$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')]")"
check "copia non allineata -> exit 3, nessun runner" '[ "$(rc)" = 3 ] && grep -q "copia non allineata" "$T/out" && [ ! -f "$FAKE_LOG.all" ]'
echo 'export const x = 1' > "$AD/src.ts"

# 5. stale dependencies -> the copy realigns itself from the origin (which has node_modules), under the lock, and the
#    proof runs in the mirror; failed rsync or no source -> exit 3 with the reason
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
# realignment that exits 0 but records a wrong fingerprint (fake fic_deps_fp at write time) -> exit 3;
# the fic-mirror.sh variant lives in a copy of the plugin (the script sources the files next to itself)
PCF=$T/plug-fm; mkplug "$PCF"
sed '0,/^  fic_deps_fp "\$src" > "\$dst\/.fic-deps"/s//  echo sbagliata > "$dst\/.fic-deps"/' "$HERE/fic-mirror.sh" > "$PCF/scripts/fic-mirror.sh"
check "  premessa: impronta finta nel riallineamento" 'grep -q "^  echo sbagliata" "$PCF/scripts/fic-mirror.sh"'
CPX="$PCF/scripts/counterproof.sh" cpr "$(mj one.json "[$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')]")"
check "  riallineamento con impronta sbagliata -> exit 3 dal secondo controllo, nessun runner" '[ "$(rc)" = 3 ] && grep -q "dipendenze stantie anche dopo il riallineamento automatico" "$T/out" && [ ! -f "$FAKE_LOG.all" ]'
echo '{"lock":1}' > "$A/package-lock.json"

# 6. mutation not applicable (0 occurrences, then 2) -> blocked, exit 2, file untouched
echo 'export const x = 1; export const x2 = 1' > "$AD/dup.ts"
(cd "$R" && git add -A && git commit -qm dup)
cpr "$(mj nomatch.json "[$(entry NM $V/src.ts 'non esiste' 'boh'),$(entry TWO $V/dup.ts '= 1' '= 2')]")"
check "cerca assente o ambiguo -> bloccato, exit 2" '[ "$(rc)" = 2 ] && [ "$(field NM esito)" = bloccato ] && [ "$(field TWO controprova)" = BLOCKED ] && grep -q "compare 2 volte" "$OUT/TWO.json"'
check "  nessun runner lanciato" '[ ! -f "$FAKE_LOG.all" ]'

# 7. red with another message -> rosso_diverso
cpr "$(mj div.json "[$(entry DIV $V/src.ts 'x = 1' 'x = 1 // DIVERSO')]")"
check "rosso non sull asserzione -> rosso_diverso, FAIL" '[ "$(rc)" = 1 ] && [ "$(field DIV esito)" = rosso_diverso ]'

# 8. named test that does not exist -> rosso_raccolta (never green)
cpr "$(mj rac.json "[$(entry RAC $V/src.ts 'x = 1' 'x = 2 // ROSSO' $V/tests/a.test.ts 'non esiste' 'expected')]")"
check "test nominato non eseguito -> rosso_raccolta" '[ "$(field RAC esito)" = rosso_raccolta ] && [ "$(field RAC controprova)" = FAIL ]'

# 9. pytest: collection error on import -> rosso_import
cpr "$(mj pyi.json "[$(entry PYI modules/api/app/core.py 'UNO = 1' 'UNO = 1  # IMPORTROTTO' modules/api/tests/test_core.py 'tests/test_core.py::test_uno' 'assert 2 == 1')]")"
check "pytest: import rotto in raccolta -> rosso_import" '[ "$(field PYI esito)" = rosso_import ]'

# 10. invalid input -> 64, nothing run
cpr "$(mj bad.json "[$(entry X modules/api/app/core.py 'UNO = 1' 'UNO = 2')]")"
check "file backend osservato con un test vitest -> 64" '[ "$(rc)" = 64 ] && [ ! -f "$FAKE_LOG.all" ]'
cpr "$(mj bad2.json '[{"id":"X","file":"modules/app/apps/admin/src.ts"}]')"
check "voce incompleta -> 64" '[ "$(rc)" = 64 ]'
cpr "$(mj bad3.json "[$(entry X $V/src.ts 'x = 1' 'x = 2'),$(entry X $V/other.ts 'y = 1' 'y = 2')]")"
check "id duplicato -> 64" '[ "$(rc)" = 64 ] && grep -q "id duplicato" "$T/out"'
MAAT_LINGUA=en cpr "$OUT/bad3.json"
check "en: id duplicato -> 64, the reason in English from the embedded Python" '[ "$(rc)" = 64 ] && grep -qx "counterproof: id X: duplicate id" "$T/out"'

# 10b. L2 (harness-pt11): "absorbed" entry -> not run, <id>.json with outcome `assorbita`; absorbed only -> exit 0,
#      no runner. Counterproof (by hand, CP=<variant> without SALTO-ASSORBITE): the absorbed entry would be run.
AB=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["assorbita"]=True; d["motivo"]="L2 prova"; print(json.dumps(d))' "$(entry AB1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')")
cpr "$(mj ab.json "[$AB,$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')]")"
check "assorbita saltata: A1 eseguita, AB1 no" '[ "$(rc)" = 0 ] && [ "$(field AB1 esito)" = assorbita ] && [ "$(field AB1 controprova)" = ASSORBITA ] && [ "$(field AB1 motivo)" = "L2 prova" ] && [ "$(field A1 esito)" = rosso_asserzione ] && [ "$(grep -c "args=vitest" "$FAKE_LOG.all")" = 1 ]'
check "  ultima riga: prove 1/1 e assorbite=1" 'tail -1 "$T/out" | grep -q "esito=PASS prove=1/1 .*assorbite=1"'
cpr "$(mj ab2.json "[$AB]")"
check "solo assorbite -> exit 0, nessun runner" '[ "$(rc)" = 0 ] && [ ! -f "$FAKE_LOG.all" ] && tail -1 "$T/out" | grep -q "esito=PASS prove=0/0 .*assorbite=1" && [ "$(field AB1 esito)" = assorbita ]'
cpr "$(mj ab3.json "[$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["assorbita"]="si"; print(json.dumps(d))' "$(entry AB2 $V/src.ts 'x = 1' 'x = 2')")]")"
check "assorbita non booleana -> 64" '[ "$(rc)" = 64 ]'
check "opzione al posto del path -> 64" 'PROJECT_ROOT=$R bash "$CP" --help >/dev/null 2>&1; [ $? -eq 64 ]'

# 11. death halfway through the run: the trap puts the mirror file back
MIR1=$(mir_hash)
FAKE_KILL="$CP" cpr "$(mj one.json "[$(entry A1 $V/src.ts 'x = 1' 'x = 2 // ROSSO')]")"
check "morte durante il run: il trap ripristina il mirror" '[ "$(mir_hash)" = "$MIR1" ] && grep -qx "export const x = 1" "$M/apps/admin/src.ts"'

# 11b. signal during step 2: no surviving process (not even in the timeout groups), no copy
alive() { local p s; for p in $(cat "$FAKE_LOG.pids" 2>/dev/null); do s=$(ps -o stat= -p "$p" 2>/dev/null); [ -n "$s" ] && [ "${s#Z}" = "$s" ] && echo "$p"; done; }
rm -f "$FAKE_LOG.pids"
t0=$(date +%s)
FAKE_KILL="$CP" FAKE_KILL_SLEEP=30 FIC_CP_PARALLEL=2 \
  cpr "$(mj pk.json "[$(entry PK1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),$(entry PK2 $V/other.ts 'y = 1' 'y = 2 // ROSSO')]")"
sleep 1
check_par "segnale nel gradino 2: il trap non aspetta la fine dei run" '[ $(( $(date +%s) - t0 )) -lt 25 ] && [ "$(rc)" = 143 ]'
check "  nessun processo dei run superstite" '[ -s "$FAKE_LOG.pids" ] && [ -z "$(alive)" ]'
check "  nessuna copia fic-cp.* residua, mirror invariato, lock libero" '! ls -d "$HOME"/fic-cp.* >/dev/null 2>&1 && [ "$(mir_hash)" = "$MIR1" ] && flock -n "$M/.fic-lock" true'
for p in $(alive); do kill -KILL "$p" 2>/dev/null; done

# 12. from a worktree (pt03): same rule as test-fast.sh — copy ~/fic-mirror-<hash> (seeded from
#     ~/fic-mirror) and ITS lock; the worktree code never enters the main tree's copy.
#     Counterproof: fixed destination ~/fic-mirror -> red.
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

# 13. pytest: the copy also carries the module's `copia_anche` folders (in the example modules/db/prisma, the
#     schema read by the coverage tests), aligned with --delete. Counterproof: without the loop on copia_anche in
#     counterproof.sh -> red.
mkdir -p "$R/modules/db/prisma/migrations/m1"
echo 'model a { id Int @id }' > "$R/modules/db/prisma/schema.prisma"
echo 'SELECT 1;' > "$R/modules/db/prisma/migrations/m1/migration.sql"
cpr "$(mj nc.json "[$(entry NC modules/api/app/core.py 'UNO = 1' 'UNO = 1  # ROSSO' modules/api/tests/test_core.py 'tests/test_core.py::test_uno' 'assert 2 == 1')]")"
check "pytest: schema.prisma copiato nella copia" 'cmp -s "$R/modules/db/prisma/schema.prisma" "$HOME/fic-mirror/modules/db/prisma/schema.prisma"'
rm -rf "$R/modules/db/prisma/migrations/m1"
cpr "$(mj nc2.json "[$(entry NC2 modules/api/app/core.py 'UNO = 1' 'UNO = 1  # ROSSO' modules/api/tests/test_core.py 'tests/test_core.py::test_uno' 'assert 2 == 1')]")"
check "  allineata: una migrazione tolta sparisce dalla copia" '[ ! -e "$HOME/fic-mirror/modules/db/prisma/migrations/m1" ] && [ -f "$HOME/fic-mirror/modules/db/prisma/schema.prisma" ]'

# 14. per-module sync on the example: mutations on both modules -> the same effective sources, destinations and
#     exclusions as before (EXCL_APP for modules/app, EXCL_API for modules/api, now from the core's single list) and cleanup of
#     .nuxt and of the vite/vitest caches under <copy>/modules/app, at every sync.
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

# 15. N declared modules (own configuration): one with a copy, two without, arbitrary roots, one without counterproof.
#     Only the modules of the mutations are synced, each into its <copy>/<radice_pacchetti>; the module with a copy
#     outside the mutations is neither seeded nor verified. `comando` runner: red = exit != 0 -> rosso_generico
#     (weak proof), exit 0 -> green. Module without counterproof -> NOT RUN (declared).
#     Counterproofs: hard-wired loop over the modules (MODS=(app api)) -> the third module is not synced and the case is red;
#     rosso_generico classified as rosso_asserzione -> red.
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
# 1.4.0: the same run in English (MAAT_LINGUA=en): the last line, the values of <id>.json and the «NOT RUN» prefix read by
# finalize.sh stay; the reasons and the progress lines follow the language, no Italian of the catalog is left
MAAT_LINGUA=en MAAT_CONFIG=$T/tre.json cpr "$(mj tre-en.json "[$(te S1 y/svc),$(te L1 z/lib),$(te D1 w/doc)]")"
check "en: N moduli -> stessa ultima riga e stessi esiti, motivi e righe d'avanzamento in inglese" '[ "$(rc)" = 0 ] && tail -1 "$T/out" | grep -q "esito=PASS prove=2/2 .*non_eseguite=1" && [ "$(field D1 esito)" = non_eseguita ] && [ "$(field S1 esito)" = rosso_generico ] && field D1 motivo | grep -q "^NOT RUN (declared): module doc declares no counterproof$" && field S1 motivo | grep -q "^the counterproof command exits 1: red without a report" && grep -q "^counterproof: 2 mutations, 2 to run (exact duplicates once only), luogo=mirror$" "$T/out" && grep -q "^counterproof: 1 NOT RUN (declared): modules without a counterproof, <id>.json with esito=non_eseguita$" "$T/out" && ! grep -qE "mutazioni|da eseguire|dichiarato|non dichiara|il comando della controprova|senza report" "$T/out" "$OUT/D1.json" "$OUT/S1.json"'
MAAT_CONFIG=$T/tre.json cpr "$(mj tre-v.json "[$(te V1 z/lib 'UNO=2')]")"
check "  runner comando: uscita 0 -> verde, FAIL" '[ "$(rc)" = 1 ] && [ "$(field V1 esito)" = verde ] && [ "$(field V1 controprova)" = FAIL ]'
MAAT_CONFIG=$T/tre.json cpr "$(mj tre-d.json "[$(te D2 w/doc)]")"
check "  solo moduli senza controprova -> esito=NOT RUN, exit 0, niente mirror" '[ "$(rc)" = 0 ] && tail -1 "$T/out" | grep -q "esito=NOT RUN prove=0/0 .*non_eseguite=1" && [ ! -e "$HOME/fic-mirror/w" ]'
MAAT_CONFIG=$T/tre.json cpr "$(mj tre-w.json "[$(te W1 x/web/app)]")"
check "  il modulo con copia nelle mutazioni vuole la copia preparata (--setup): exit 3" '[ "$(rc)" = 3 ] && grep -q "mirror assente: eseguire test-fast.sh --setup" "$T/out"'
sed 's/"nome": "svc", "radice": "y\/svc", /"nome": "svc", "radice": "y\/svc", "copia": {"test": "true {test}"}, /' "$T/tre.json" > "$T/tre2.json"
MAAT_CONFIG=$T/tre2.json cpr "$(mj tre-2c.json "[$(te S1 y/svc),$(te W1 x/web/app)]")"
check "due moduli con copia nelle mutazioni -> exit 64 «più moduli con copia»" '[ "$(rc)" = 64 ] && grep -q "più moduli con copia" "$T/out"'

# 16. pk08, CHANGES THE CONTRACT (before: PATH without rsync -> BLOCKED). PATH without rsync and without flock (Git Bash on
#     Windows without WSL) -> counterproofs run with the fallback copy (fic_sync: find, sha256 fingerprints, tar) and the lock
#     with mkdir (fic_lock_dir), declared in one line, with the real results and the SAME copy as the rsync path (from a drifted
#     copy: stale file, extraneous files, a folder in place of a file, excluded items to keep, also inside an extraneous folder
#     which therefore stays, as with rsync). Lock held during the runs,
#     released at the end and on signal; a live lock blocks (exit 3), an orphaned one is taken over; step 2 (worker queue
#     with the mkdir lock) with the same results. Without sha256sum, timeout, or rsync and tar -> BLOCKED with the reason.
#     Known limit (pk04b-2): radice_pacchetti = repository root -> 64, the same on both paths.
#     Counterproofs, run here: fallback disabled in fic_sync -> «sync fallito», red; --delete ignored by the fallback
#     -> different copy, red; mkdir lock never released -> the folder stays, red; tools not checked -> red.
path_senza() { # <folder> <name…>: the PATH with the folders containing one of the <name> replaced by <folder>, which
               # links every file in them except those; the /mnt/… folders (Windows, inside WSL) stay out
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
cpb() { # <PATH> <list> [script]: like cpr, with the given PATH
  rm -f "$FAKE_LOG.all"; PATH=$1 PROJECT_ROOT=$R "$BASH" "${3:-$CP}" "$2" > "$T/out" 2>&1; echo $? > "$T/rc"
}
diverge() { # the same drift of the copy before every round
  echo 'export const x = 0 // stantio' > "$M/apps/admin/src.ts"
  echo estraneo > "$M/apps/admin/estraneo.ts"; mkdir -p "$M/apps/admin/vuota-estranea/sotto"
  mkdir -p "$M/apps/admin/vuota-estranea/node_modules" && echo x > "$M/apps/admin/vuota-estranea/node_modules/x"   # stays, as with rsync
  rm -rf "$M/apps/admin/other.ts"; mkdir -p "$M/apps/admin/other.ts" && echo d > "$M/apps/admin/other.ts/dentro"
  mkdir -p "$M/apps/admin/node_modules/tieni" && echo t > "$M/apps/admin/node_modules/tieni/x"
  echo 'STANTIO = 1' > "$MA/app/estraneo.py"; mkdir -p "$MA/__pycache__" && echo c > "$MA/__pycache__/c.pyc"
  mkdir -p "$HOME/fic-mirror/modules/db/prisma" && echo 'model z {}' > "$HOME/fic-mirror/modules/db/prisma/estraneo.prisma"
}
albero_copia() { # type, path and content of the whole copy, locks excluded
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
caso_ripiego() { # [script]: drifted copy, PATH without rsync and flock -> same results and same copy as the rsync path, fallback
                 # lock held during the two vitest runs and released at the end
  diverge; rm -f "$OUT/A1.json" "$OUT/VERDE.json" "$OUT/PY.json"
  FIC_CP_PARALLEL=1 FAKE_LOCKDIR=$M/.fic-lock.d cpb "$PX" "$L16" "${1:-$CP}"
  [ "$(rc)" = "$RC_RS" ] && [ "$(esiti16)" = "$ES_RS" ] && tail -1 "$T/out" | grep -q "esito=FAIL prove=2/3 fail=1 bloccate=0" &&
    [ "$(albero_copia)" = "$AL_RS" ] && [ "$(grep -c '^lockdir=presente' "$FAKE_LOG.all")" = 2 ] && [ ! -e "$M/.fic-lock.d" ]
}
check "PATH senza rsync e flock -> controprove eseguite: stessi esiti, stessa copia della via rsync, lock rilasciato" 'caso_ripiego'
check "  ripieghi dichiarati in una riga" 'grep -qx "counterproof: rsync assente: copia di ripiego (find, impronte sha256, tar); flock assente: lock di ripiego (mkdir atomico); piu'"'"' lenti, stessi esiti" "$T/out"'
check "  la mutazione l ha vista il runner nel mirror" 'grep -q "seen=export const x = 2 // ROSSO" "$FAKE_LOG.all" && ! grep "^cwd=" "$FAKE_LOG.all" | grep -v "^cwd=$HOME/fic-mirror/" | grep -q .'
# fallback lock held by a live process -> waits, beyond the cap exit 3; then orphaned (dead pid) -> taken over
sleep 30 & vivo=$!
mkdir "$M/.fic-lock.d" && echo "$vivo" > "$M/.fic-lock.d/pid"
FIC_LOCK_WAIT=1 cpb "$PX" "$OUT/one.json"
check "  lock di ripiego di un processo vivo -> exit 3 «mirror occupato», niente eseguito, lock intatto" '[ "$(rc)" = 3 ] && grep -qF "esito=BLOCKED (mirror occupato oltre 1s (lock $M/.fic-lock.d)" "$T/out" && [ ! -f "$FAKE_LOG.all" ] && [ "$(cat "$M/.fic-lock.d/pid")" = "$vivo" ]'
kill "$vivo"; wait "$vivo" 2>/dev/null
FIC_LOCK_WAIT=5 cpb "$PX" "$OUT/one.json"
check "  lock orfano (pid morto) -> ripreso, prova eseguita, lock rilasciato" '[ "$(rc)" = 0 ] && tail -1 "$T/out" | grep -q "esito=PASS prove=1/1" && [ ! -e "$M/.fic-lock.d" ] && [ ! -e "$M/.fic-lock.d.rec" ]'
# step 2: private copies with the fallback, worker queue with the mkdir lock
FIC_CP_PARALLEL=2 cpb "$PX" "$(mj pk.json "[$(entry PK1 $V/src.ts 'x = 1' 'x = 2 // ROSSO'),$(entry PK2 $V/other.ts 'y = 1' 'y = 2 // ROSSO')]")"
check_par "  gradino 2 senza rsync e flock: stessi esiti, ogni mutazione una volta, copie cancellate, lock rilasciato" '[ "$(rc)" = 0 ] && tail -1 "$T/out" | grep -q "esito=PASS prove=2/2 .*luogo=copie(2)" && [ "$(field PK1 esito)" = rosso_asserzione ] && [ "$(field PK2 esito)" = rosso_asserzione ] && [ "$(grep -c "args=vitest" "$FAKE_LOG.all")" = 2 ] && ! ls -d "$HOME"/fic-cp.* >/dev/null 2>&1 && [ ! -e "$M/.fic-lock.d" ]'
# signal halfway through the run: the trap restores the mirror and releases the fallback lock
FAKE_KILL="$CP" cpb "$PX" "$OUT/one.json"
check "  segnale durante il run -> exit 143, mirror ripristinato, lock di ripiego rilasciato" '[ "$(rc)" = 143 ] && grep -qx "export const x = 1" "$M/apps/admin/src.ts" && [ ! -e "$M/.fic-lock.d" ]'
[ "$(rc)" = 143 ] && grep -qx "export const x = 1" "$M/apps/admin/src.ts" && [ ! -e "$M/.fic-lock.d" ] ||   # detail of a red
  { echo "    rc=$(rc) src.ts=$(cat "$M/apps/admin/src.ts" 2>&1) lock=$(ls -la "$M/.fic-lock.d" 2>&1 | tr '\n' ' ') pid=$(cat "$M/.fic-lock.d/pid" 2>&1)"
    sed 's/^/    out: /' "$T/out" | tail -15; sed 's/^/    npx: /' "$FAKE_LOG.all" 2>/dev/null | tail -8; }
# tools without fallback
for v in "sha256sum|rsync flock sha256sum" "timeout|timeout" "rsync e tar|rsync tar flock"; do
  cpb "$(path_senza "$T/bin-${v#*|}" ${v#*|})" "$OUT/one.json"
  check "senza ${v%%|*} -> exit 3, «controprove non disponibili: manca ${v%%|*}», niente eseguito" '[ "$(rc)" = 3 ] && grep -q "esito=BLOCKED (controprove non disponibili: manca ${v%%|*})" "$T/out" && [ ! -f "$FAKE_LOG.all" ]'
done
MAAT_LINGUA=en cpb "$(path_senza "$T/bin-sha256sum-en" rsync flock sha256sum)" "$OUT/one.json"
check "en: senza sha256sum -> exit 3, prefisso «esito=BLOCKED (» congelato, motivo in inglese" '[ "$(rc)" = 3 ] && grep -qx "counterproof: esito=BLOCKED (counterproofs not available: missing sha256sum) luogo=-" "$T/out" && [ ! -f "$FAKE_LOG.all" ]'
# known limit: radice_pacchetti = repository root -> 64 with the reason, with and without rsync
echo "{\"versione_schema\": 1, \"moduli\": [{\"nome\": \"tutto\", \"radice\": \".\", $CMDC}]}" > "$T/radice.json"
RADL=$(mj rad.json "[$(entry R1 y/svc/core.txt 'UNO=1' 'UNO=1 ROSSO' y/svc/t.sh y/svc/t.sh 'rosso')]")
MAAT_CONFIG=$T/radice.json cpr "$RADL"; RAD1="$(rc) $(grep -c "la copia vuole una cartella" "$T/out")"
MAAT_CONFIG=$T/radice.json cpb "$PX" "$RADL"; RAD2="$(rc) $(grep -c "la copia vuole una cartella" "$T/out")"
check "radice_pacchetti = radice del repository -> 64 «la copia vuole una cartella», uguale con rsync e senza" '[ "$RAD1" = "64 1" ] && [ "$RAD2" = "64 1" ]'
# counterproofs by mutation (plugin copies with fic-mirror.sh or counterproof.sh mutated)
mut16() { # <name> <file> <sed>: plugin copy with <file> mutated -> its counterproof.sh; empty if the sed changes nothing
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
caso_ripiego >/dev/null   # copy realigned after the mutants
rm -rf "$M/apps/admin/node_modules/tieni" "$M/apps/admin/vuota-estranea" "$MA/__pycache__"

# 17. project root: from PROJECT_ROOT, never from the script location; without it (outside a repo) -> exit 64.
#     Counterproof: ROOT again from $HERE/../.. -> the cases above are red.
mkdir -p "$T/nogit"
(cd "$T/nogit" && env -u PROJECT_ROOT -u FIC_REPO bash "$CP" "$OUT/one.json" > "$T/out" 2>&1; echo $? > "$T/rc")
check "PROJECT_ROOT non risolvibile -> exit 64" '[ "$(rc)" = 64 ] && grep -q "radice del progetto non risolta" "$T/out"'

# 18. {python} of the be module (wsl environment): without FIC_PYTEST_PY, gates.sh's search among the module's candidates
#     (.venv312/bin/python, .venv/bin/python): none -> exit 3 «python WSL assente»; the first one that exists wins.
FIC_PYTEST_PY= cpr "$(mj pyw.json "[$(entry PW modules/api/app/core.py 'UNO = 1' 'UNO = 1  # ROSSO' modules/api/tests/test_core.py 'tests/test_core.py::test_uno' 'assert 2 == 1')]")"
check "python WSL assente fra i candidati del modulo -> exit 3, niente eseguito" '[ "$(rc)" = 3 ] && grep -q "esito=BLOCKED (python WSL assente: $API/.venv312/bin/python $API/.venv/bin/python)" "$T/out" && [ ! -f "$FAKE_LOG.all" ]'
mkdir -p "$API/.venv/bin" && cp "$BIN/fakepy" "$API/.venv/bin/python" && chmod +x "$API/.venv/bin/python"
FIC_PYTEST_PY= cpr "$OUT/pyw.json"
check "  il primo candidato che esiste (.venv/bin/python) esegue il test" '[ "$(rc)" = 0 ] && [ "$(field PW esito)" = rosso_asserzione ] && field PW comando | grep -q "$API/.venv/bin/python -B -m pytest"'
rm -rf "$API/.venv"

echo "counterproof.test.sh: $((n - fail))/$n ok"
[ $fail -eq 0 ]
