#!/usr/bin/env bash
# comandi-equivalenza.test.sh — i comandi che i gate eseguono, prima e dopo pk04b-1, su un repository sintetico
# nuxt-fastapi: il harness DI RIFERIMENTO (commit $RIF di questo repo: gates.sh e finalize.sh di allora, con il
# motore vitest-fast.sh dove stava nel progetto, <repo>/script/test/) contro il plugin attuale con
# examples/nuxt-fastapi.maat.json. Stessi file toccati, stesso livello, stessa evidenza finta; a confronto:
#   - le righe di comando registrate (npx, npm e il python del venv FINTI, piu' l'involucro: vitest-fast.sh del
#     riferimento e test-fast.sh del plugin, che diventano lo stesso segnaposto), con la cartella di lavoro (pwd)
#     normalizzata: radice del repo -> <repo>, cartella della copia -> <copia>, report -> <report>. La cartella da cui
#     gates.sh lancia l'involucro non si confronta: l'involucro non dipende da li'. L'ordine si confronta dentro ogni
#     corsia (WSL in serie; pytest nativo) ma non fra le due, che girano in parallelo in entrambi i harness;
#   - le righe dei gate (etichetta, esito, riepilogo o motivo) e l'esito complessivo;
#   - le voci della chiave diverse dai comandi (cmd.*), come INSIEME: nel plugin le voci arrivano modulo per modulo
#     (pip, del modulo be, dopo tsconfig, del modulo fe), nel riferimento in un ordine fisso;
#   - l'esito di finalize.sh.
# In piu': la cartella di lavoro di ogni gate (tests-be <repo>/modules/api, tests-fe e lint <copia>/apps/admin,
# messaggi del file extra <copia>/packages/ui, build <repo>/modules/app); niente autorichiamo (l'involucro una sola
# volta per gate, dentro la copia solo vitest, npm run -s lint, eslint); S5 e S6 di `valida`; exit 64 di
# test-fast.sh con due moduli con copia e nessun MAAT_MODULO.
# Controprova per mutazione (qui): firmare IMPLEMENTED solo con PASS => il caso «.vue senza test» diverge.
# Da eseguire in WSL (la copia vuole rsync e flock):
#   wsl -- bash -lc 'bash /mnt/c/<maat>/plugins/maat/scripts/comandi-equivalenza.test.sh'
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(dirname "$HERE")
RIF=d3e9397   # maat-pk05: l'ultimo harness con i comandi cablati
command -v rsync >/dev/null && command -v flock >/dev/null || { echo "comandi-equivalenza.test.sh: servono rsync e flock (WSL)" >&2; exit 2; }
unset MAAT_CONFIG MAAT_MODULO MAAT_ROOT PROJECT_ROOT FIC_REPO FIC_LANE FIC_ALLOW_MNT_C FIC_GATES FIC_GATES_ROOT \
      FIC_GATES_HARNESS FIC_GATES_WSL FIC_GATES_VENV_PY CI
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '%s\n' "$2" | head -40 | sed 's/^/    /'; }
chk() { if eval "$2"; then ok; else ko "$1" "${3:-}"; fi; }

# --- i due harness: riferimento (dal commit $RIF) e plugin attuale, ognuno con un registratore dell'involucro ---
TOP=$(git -c safe.directory='*' -C "$PLUGIN" rev-parse --show-toplevel)
# Il riferimento viene dalla storia: in un repo senza $RIF (il repo pubblico parte da un commit solo) il confronto si
# SALTA con motivo, non e' un FAIL; l'equivalenza e' stata verificata dove il commit c'era.
if ! git -c safe.directory='*' -C "$TOP" cat-file -e "$RIF:plugins/maat/scripts/gates.sh" 2>/dev/null; then
  echo "SKIP [equivalenza col harness di $RIF — la storia di questo repo non ha quel commit]"
  echo "comandi-equivalenza.test.sh: 0 ok, 0 falliti (SALTATO: manca $RIF)"; exit 0
fi
git -c safe.directory='*' -C "$TOP" archive "$RIF" plugins/maat | tar -x -C "$T" && mv "$T/plugins/maat" "$T/vecchio" ||
  { echo "comandi-equivalenza.test.sh: harness $RIF non estraibile da git" >&2; exit 2; }
OH=$T/vecchio
NH=$T/nuovo; cp -r "$PLUGIN" "$NH"; find "$NH" -name __pycache__ -type d -prune -exec rm -rf {} +
[ -n "${GT:-}" ] && cp "$GT" "$NH/scripts/gates.sh"
[ -n "${FZ:-}" ] && cp "$FZ" "$NH/scripts/finalize.sh"
mv "$NH/scripts/test-fast.sh" "$NH/scripts/test-fast.real.sh"
printf '#!/usr/bin/env bash\nprintf "INV %%s\\n" "$*" >> "$REC"\nexec bash "$(dirname "$0")/test-fast.real.sh" "$@"\n' > "$NH/scripts/test-fast.sh"

# --- repository sintetico ---
R=$T/repo; A=$R/modules/app; ADM=$A/apps/admin; API=$R/modules/api
mkdir -p "$R/.claude" "$R/script/test" "$ADM/components/goals" "$ADM/components/x" "$ADM/utils" "$ADM/.nuxt" \
         "$A/packages/ui" "$A/node_modules/dep" "$API/app/routers" "$API/tests/routers"
cp "$PLUGIN/examples/nuxt-fastapi.maat.json" "$R/.claude/maat.json"
# il motore del riferimento stava nel progetto: <repo>/script/test/vitest-fast.sh (con fic-mirror.sh accanto)
git -c safe.directory='*' -C "$PLUGIN" show "$RIF:plugins/maat/scripts/vitest-fast.sh" > "$R/script/test/vitest-fast.sh"
git -c safe.directory='*' -C "$PLUGIN" show "$RIF:plugins/maat/scripts/fic-mirror.sh" > "$R/script/test/fic-mirror.sh"
printf '#!/usr/bin/env bash\nprintf "INV %%s\\n" "$*" >> "$REC"\nexec bash "%s/script/test/vitest-fast.sh" "$@"\n' "$R" > "$OH/scripts/vitest-fast.sh"
echo '{"name":"app"}' > "$A/package.json"; echo '{"lock":1}' > "$A/package-lock.json"; echo dep > "$A/node_modules/dep/index.js"
echo '{"name":"admin"}' > "$ADM/package.json"; echo 'export default {}' > "$ADM/lint-baseline.mjs"
echo '{"compilerOptions":{}}' > "$ADM/.nuxt/tsconfig.json"
printf '<template><div/></template>\n' > "$ADM/components/goals/Riga.vue"
printf "it('riga', () => {})\n" > "$ADM/components/goals/Riga.test.ts"
printf '<template><span/></template>\n' > "$ADM/components/x/Solo.vue"
printf 'export const somma = (a: number) => a\n' > "$ADM/utils/goals.ts"
printf "it('somma', () => {})\n" > "$ADM/utils/goals.test.ts"
echo '{"name":"ui"}' > "$A/packages/ui/package.json"; echo 'export default []' > "$A/packages/ui/eslint.config.js"
printf 'export const b = 1\n' > "$A/packages/ui/Button.ts"
printf 'def f():\n    return 1\n' > "$API/app/routers/goals.py"
printf 'def test_f():\n    assert True\n' > "$API/tests/routers/test_goals.py"
printf 'def test_d():\n    assert True\n' > "$API/tests/test_diretto.py"
echo '# repo' > "$R/README.md"
printf 'node_modules\n.nuxt\n' > "$R/.gitignore"
(cd "$R" && git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false &&
  git add -A && git commit -qm init)
BASE_SHA=$(git -C "$R" rev-parse HEAD)

# --- finti: npx, npm, python del venv (registrano pwd e argomenti), wsl (siamo gia' in WSL) ---
FB=$T/bin; mkdir -p "$FB"
cat > "$FB/npx" <<'EOF'
#!/usr/bin/env bash
printf 'NPX %s|%s\n' "$PWD" "$*" >> "$REC"
if [ "${1:-}" = vitest ]; then shift 2; for f in "$@"; do echo " ✓ $f (1 test) 1ms"; done; echo " Tests  $# passed ($#)"; fi
exit 0
EOF
cat > "$FB/npm" <<'EOF'
#!/usr/bin/env bash
printf 'NPM %s|%s\n' "$PWD" "$*" >> "$REC"
[ "$1 ${2:-}" = "run build:admin" ] && echo "build ok"
exit 0
EOF
cat > "$FB/venv-python" <<'EOF'
#!/usr/bin/env bash
[ "$1" = --version ] && { echo "Python 3.12.1"; exit 0; }
[ "$1 $2" = "-m pip" ] && { echo "fastapi==0.110.0"; exit 0; }
if [ "$1 $2" = "-m pytest" ]; then
  printf 'PYTEST %s|%s\n' "$PWD" "$*" >> "$REC"
  for a in "$@"; do case $a in --junitxml=*) j=${a#--junitxml=} ;; esac; done
  printf '<?xml version="1.0"?><testsuites><testsuite name="pytest" tests="1" failures="0" errors="0" skipped="0"><testcase classname="t" name="t"/></testsuite></testsuites>\n' > "$j"
  echo "1 passed"; exit 0
fi
exit 9
EOF
printf '#!/usr/bin/env bash\nexec bash -c "$1"\n' > "$FB/wsl"
chmod +x "$FB"/* "$NH/scripts/test-fast.sh" "$OH/scripts/vitest-fast.sh"
export PATH="$FB:$PATH" REC=$T/rec FIC_GATES_ROOT=$R FIC_GATES_WSL=$FB/wsl FIC_GATES_VENV_PY=$FB/venv-python

# --- le due copie (una HOME per harness), preparate una volta come fa --setup a mano ---
HO=$T/home-vecchio HN=$T/home-nuovo; mkdir -p "$HO" "$HN"
(cd "$R" && HOME=$HO bash "$R/script/test/vitest-fast.sh" --setup) > "$T/setup.out" 2>&1 &&
  (cd "$R" && HOME=$HN bash "$NH/scripts/test-fast.real.sh" --setup) >> "$T/setup.out" 2>&1 ||
  { echo "comandi-equivalenza.test.sh: --setup delle copie fallito" >&2; cat "$T/setup.out" >&2; exit 2; }

norm() { sed -e "s#$HO/fic-mirror/modules/app#<copia>#g" -e "s#$HN/fic-mirror/modules/app#<copia>#g" -e "s#$R#<repo>#g" \
             -e "s#--junitxml=[^ ]*#--junitxml=<report>#g"; }
spec() { # $1 = file della spec: review APPROVED + IMPLEMENTED, controprova della tabella PASS
  printf '%s\n' "# X" "## Contesto" "Contesto." "## Requisiti funzionali" "1. Fare A." \
    "## Piano di implementazione" "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" \
    "### Passi" "1. Modificare \`utils/goals.ts\`." \
    "## Review implementazione" "Review status: APPROVED" "Feature status: IMPLEMENTED" "Verification: VERIFIED" \
    "Reviewed snapshot: base aaaaaaaaaaaa · tree bbbbbbbbbbbb · fingerprint cccccccccccc · 2 paths" \
    "Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1" "" \
    "| Gate | Req. | Command / check | Result | Evidence |" \
    "| plan: counterproof on goals.ts | yes | mutazione | PASS | observed |" > "$1"
}
# un harness su un caso: $1 vecchio|nuovo, $2 nome, $3 livello, $4 si|no (base.txt), file…; risultati in $T/<h>.*
gira() {
  local h=$1 n=$2 l=$3 b=$4 hr hm out ev; shift 4
  if [ "$h" = vecchio ]; then hr=$OH hm=$HO; else hr=$NH hm=$HN; fi
  local run="$T/wf-$h/spec-$n.run"; mkdir -p "$run"; printf '%s\n' "$@" > "$run/touched.txt"
  [ "$b" = si ] && echo "$BASE_SHA" > "$run/base.txt"
  : > "$REC"
  out=$(cd "$R" && HOME=$hm FIC_GATES_HARNESS=$hr bash "$hr/scripts/gates.sh" --run-dir "$run" "$l" "$@" 2>&1)
  printf '%s\n' "$out" > "$T/$h.gates"
  # due corsie in parallelo (pytest nativo, il resto in WSL): l'ordine conta dentro ogni corsia, non fra le due
  { norm < "$REC" | grep -v '^PYTEST '; norm < "$REC" | grep '^PYTEST '; } > "$T/$h.rec"
  printf '%s\n' "$out" | grep -E '^[a-z0-9-]+: [A-Z]' > "$T/$h.righe"
  printf '%s\n' "$out" | sed -n 's/^gates: esito=\([A-Z]*\).*/\1/p' > "$T/$h.esito"
  ev=$(printf '%s\n' "$out" | sed -n 's/^gates: .* evidence=\(.*\)$/\1/p' | tail -1)
  { [ -n "$ev" ] && grep -v '^cmd\.' "$ev/chiave.txt" | norm | LC_ALL=C sort; } > "$T/$h.chiave"
  spec "${run%.run}.md"
  (cd "$R" && HOME=$hm FIC_GATES_HARNESS=$hr FIC_GATES="$hr/scripts/gates.sh" bash "${FZH:-$hr/scripts/finalize.sh}" --level "$l" "$run" 2>&1) |
    sed -n 's/^finalize: esito=\([A-Z_]*\).*/\1/p' > "$T/$h.firma"
}
uguali() { # $1 nome del caso: i quattro confronti
  local x
  for x in rec righe esito chiave firma; do
    chk "$1: $x identico" 'cmp -s "$T/vecchio.$x" "$T/nuovo.$x"' "$(diff "$T/vecchio.$x" "$T/nuovo.$x")"
  done
}
caso() { gira vecchio "$@"; gira nuovo "$@"; uguali "$1"; }
cnt() { grep -c "$1" "$T/nuovo.rec"; }

# --- 1. .vue con il test accanto ---
caso vue-con-test std no modules/app/apps/admin/components/goals/Riga.vue
chk "  tests-fe: vitest in <copia>/apps/admin, test relativo alla radice" 'grep -qx "NPX <copia>/apps/admin|vitest run components/goals/Riga.test.ts" "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
chk "  niente autorichiamo: l'involucro una volta, dentro la copia solo vitest" '[ "$(cnt "^INV ")" = 1 ] && [ "$(grep -v "^INV " "$T/nuovo.rec" | grep -vc "^NPX <copia>/apps/admin|vitest run ")" = 0 ]' "$(cat "$T/nuovo.rec")"
# --- 2. .vue senza test: tests-fe SKIPPED e firma IMPLEMENTED, come prima ---
caso vue-senza-test std no modules/app/apps/admin/components/x/Solo.vue
chk "  tests-fe SKIPPED e firma IMPLEMENTED" 'grep -q "^tests-fe: SKIPPED" "$T/nuovo.righe" && [ "$(cat "$T/nuovo.firma")" = IMPLEMENTED ]' "$(cat "$T/nuovo.righe" "$T/nuovo.firma")"
# --- 3. .ts in packages/ui ---
caso ts-packages-ui std no modules/app/packages/ui/Button.ts
# --- 4. router Python con test a specchio ---
caso router-specchio std no modules/api/app/routers/goals.py
chk "  tests-be: pytest in <repo>/modules/api, -q, --junitxml, selezione relativa al modulo" 'grep -qx "PYTEST <repo>/modules/api|-m pytest -q --junitxml=<report> tests/routers/test_goals.py" "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
# --- 5. test Python diretto ---
caso test-python-diretto std no modules/api/tests/test_diretto.py
# --- 6-8. i tre livelli ---
F_MIX=(modules/app/apps/admin/utils/goals.ts modules/api/app/routers/goals.py)
caso livello-min min no "${F_MIX[@]}"
caso livello-std std no "${F_MIX[@]}"
caso livello-full full no "${F_MIX[@]}" modules/app/packages/ui/Button.ts
chk "  build: npm run build:admin in <repo>/modules/app" 'grep -qx "NPM <repo>/modules/app|run build:admin" "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
# --- 9. lint con --base (il file extra di packages/ui classificato) ---
caso lint-con-base full si modules/app/apps/admin/components/goals/Riga.vue modules/app/packages/ui/Button.ts
chk "  lint: npm run -s lint in <copia>/apps/admin, file relativo alla radice" 'grep -qx "NPM <copia>/apps/admin|run -s lint -- components/goals/Riga.vue" "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
chk "  messaggi del file extra: eslint in <copia>/packages/ui" 'grep -q "^NPX <copia>/packages/ui|eslint --format compact --quiet " "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
chk "  --base nella riga dell'involucro" 'grep -qx "INV --lint --base $BASE_SHA modules/app/apps/admin/components/goals/Riga.vue modules/app/packages/ui/Button.ts" "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
chk "  niente autorichiamo: involucro una volta per gate (tests-fe, lint), nella copia solo vitest/npm/eslint" '[ "$(cnt "^INV ")" = 2 ] && [ "$(grep -Ev "^(INV |NPX <copia>/[a-z/]*\|(vitest run|eslint) |NPM <copia>/apps/admin\|run -s lint |NPM <repo>/modules/app\|run build:admin$|PYTEST )" "$T/nuovo.rec" | wc -l)" = 0 ]' "$(cat "$T/nuovo.rec")"
# --- 10. lint senza base.txt: nessun --base ---
caso lint-senza-base full no modules/app/apps/admin/components/goals/Riga.vue
chk "  nessun --base" 'grep -q "^INV --lint " "$T/nuovo.rec" && ! grep -q -- "--base" "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
# --- 11. file fuori da ogni modulo ---
caso fuori-modulo std no README.md modules/app/apps/admin/utils/goals.ts
chk "  il plugin lo dichiara non coperto" 'grep -q "^non coperto: README.md" "$T/nuovo.gates"' "$(cat "$T/nuovo.gates")"
# --- 12. file eliminato ---
caso file-eliminato full no modules/app/apps/admin/utils/vecchio.ts

# --- niente autorichiamo nella configurazione: S5, S6; due moduli con copia senza MAAT_MODULO -> 64 ---
. "$HERE/python.sh" || true
printf '%s\n' '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","comandi":{"test":"bash {maat}/scripts/test-fast.sh {test}"},"copia":{"test":"bash {maat}/scripts/test-fast.sh {test}"}}]}' > "$T/s6.json"
o=$("$FIC_PY" "$NH/scripts/maat-config.py" valida "$T/s6.json" 2>&1); r=$?
chk "copia.test che chiama test-fast.sh: valida esce 1 con S6" '[ $r -eq 1 ] && printf "%s" "$o" | grep -q "(S6)"' "$o"
printf '%s\n' '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","comandi":{"test":"bash {maat}/scripts/test-fast.sh {test}"}}]}' > "$T/s5.json"
o=$("$FIC_PY" "$NH/scripts/maat-config.py" valida "$T/s5.json" 2>&1); r=$?
chk "comandi.test con test-fast.sh senza copia: valida esce 1 con S5" '[ $r -eq 1 ] && printf "%s" "$o" | grep -q "(S5)"' "$o"
R2=$T/due; mkdir -p "$R2/.claude" "$R2/a" "$R2/b"; git -C "$R2" init -q .
printf '%s\n' '{"versione_schema":1,"moduli":[{"nome":"a","radice":"a","copia":{"test":"npx vitest run {test}"}},{"nome":"b","radice":"b","copia":{"test":"npx vitest run {test}"}}]}' > "$R2/.claude/maat.json"
o=$(cd "$R2/a" && HOME=$HN bash "$NH/scripts/test-fast.real.sh" x.test.ts 2>&1); r=$?
chk "due moduli con copia, nessun MAAT_MODULO: test-fast.sh esce 64" '[ $r -eq 64 ] && printf "%s" "$o" | grep -q "imposta MAAT_MODULO"' "rc=$r $o"

# --- controprova: firmare IMPLEMENTED solo con PASS => il caso «.vue senza test» diverge ---
MF=$NH/scripts/finalize.mut.sh
sed 's/^        elif es != "SKIPPED":$/        else:/' "$NH/scripts/finalize.sh" > "$MF"
if cmp -s "$NH/scripts/finalize.sh" "$MF"; then ko "controprova: la mutazione (SKIPPED non soddisfa) non si applica"; else
  gira vecchio vue-senza-test-mut std no modules/app/apps/admin/components/x/Solo.vue
  FZH=$MF gira nuovo vue-senza-test-mut std no modules/app/apps/admin/components/x/Solo.vue
  if [ "$(cat "$T/nuovo.firma")" = NEEDS_VERIFICATION ] && ! cmp -s "$T/vecchio.firma" "$T/nuovo.firma"; then ok   # rosso atteso
  else ko "controprova: col mutante la firma del caso «.vue senza test» coincide ancora (il test non discrimina)" "$(cat "$T/vecchio.firma" "$T/nuovo.firma")"; fi
fi

echo "comandi-equivalenza.test.sh: $pass ok, $fail falliti"
[ $fail -eq 0 ]
