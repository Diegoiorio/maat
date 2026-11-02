#!/usr/bin/env bash
# comandi-equivalenza.test.sh — the commands the gates run, before and after pk04b-1, on a synthetic nuxt-fastapi
# repository: the REFERENCE harness (commit $RIF of the private development history: gates.sh and finalize.sh of that
# time, with the vitest-fast.sh engine where it lived in the project, <repo>/script/test/) against the current plugin
# with examples/nuxt-fastapi.maat.json. Same touched files, same level, same fake evidence.
# 1.5.0: the reference side is FROZEN in ../tests/comandi-equivalenza/riferimento.txt (sections «== <case> <view>»,
# already normalized, INV lines included), so the test runs everywhere (WSL or Linux) without the commit $RIF:
#   bash comandi-equivalenza.test.sh                              compare the current plugin with riferimento.txt
#   MAAT_RIF_REPO=<repo with $RIF> bash comandi-equivalenza.test.sh --rigenera
#                                     run the reference harness (git archive of $RIF from that repo, and the two engine
#                                     files in <repo>/script/test/ only while it runs), rewrite riferimento.txt, compare
# Without --rigenera nothing reads git history. The synthetic repository is deterministic (fixed identity and dates,
# no git configuration of the machine), `node` is a fake that prints v20.0.0 and TZ=UTC, so the key's probe
# (node=, tz_wsl=) carries no value of the machine.
# Compared:
#   - the recorded command lines (FAKE npx, npm and venv python, plus the wrapper: vitest-fast.sh of the
#     reference and test-fast.sh of the plugin, which become the same placeholder), with the working directory (pwd)
#     normalized: repo root -> <repo>, copy directory -> <copia>, report -> <report>, and the base commit of the
#     synthetic repository -> <base> (it is in base.txt and in the INV --lint --base line). The directory from which
#     gates.sh launches the wrapper is not compared: the wrapper does not depend on it. Order is compared within each
#     lane (WSL in series; native pytest) but not between the two, which run in parallel in both harnesses;
#   - the gate lines (label, outcome, summary or reason) and the overall outcome;
#   - the key entries other than the commands (cmd.*), as a SET: in the plugin the entries come module by module
#     (pip, of the be module, after tsconfig, of the fe module), in the reference in a fixed order; with
#     tree=<40 hex digits> -> tree=<tree>: gates.sh writes the write-tree of the whole synthetic repository, which in
#     --rigenera holds the two engine files of $RIF and otherwise does not, and holds .claude/maat.json copied from the
#     example, which may change in a release;
#   - the outcome of finalize.sh.
# Reference hygiene: riferimento.txt has no node=v other than the fake's, no tz_wsl= other than the fixed one and no
# 40-digit sha (green only if <base> and <tree> are applied when it is written).
# In addition: the working directory of each gate (tests-be <repo>/modules/api, tests-fe and lint <copia>/apps/admin,
# messages of the extra file <copia>/packages/ui, build <repo>/modules/app); no self-invocation (the wrapper only once
# per gate, inside the copy only vitest, npm run -s lint, eslint); S5 and S6 of `valida`; exit 64 of
# test-fast.sh with two modules with a copy and no MAAT_MODULO.
# Counterproofs (here): signing IMPLEMENTED only with PASS => the «.vue senza test» case diverges; a line changed in a
# copy of riferimento.txt => that case diverges (the test really reads the file); the real base sha written in a copy of
# riferimento.txt => hygiene red; norm without the <base> rule => the «lint-con-base» case diverges.
# To be run in WSL or Linux (the copy needs rsync and flock):
#   wsl -- bash -lc 'bash /mnt/c/<maat>/plugins/maat/scripts/comandi-equivalenza.test.sh'
set -uo pipefail
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
export TZ=UTC           # 1.5.0: tz_wsl= and TZ= of the key are frozen in the reference
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(dirname "$HERE")
RIF=d3e9397   # maat-pk05: the last harness with hard-wired commands
RIFF=$PLUGIN/tests/comandi-equivalenza/riferimento.txt
RIGENERA=""
case ${1:-} in
  "") ;;
  --rigenera) RIGENERA=1 ;;
  *) echo "uso: [MAAT_RIF_REPO=<repo con $RIF>] bash comandi-equivalenza.test.sh [--rigenera]" >&2; exit 2 ;;
esac
command -v rsync >/dev/null && command -v flock >/dev/null || { echo "comandi-equivalenza.test.sh: servono rsync e flock (WSL)" >&2; exit 2; }
unset MAAT_CONFIG MAAT_MODULO MAAT_ROOT PROJECT_ROOT FIC_REPO FIC_LANE FIC_ALLOW_MNT_C FIC_GATES FIC_GATES_ROOT \
      FIC_GATES_HARNESS FIC_GATES_WSL FIC_GATES_VENV_PY CI
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '%s\n' "$2" | head -40 | sed 's/^/    /'; }
chk() { if eval "$2"; then ok; else ko "$1" "${3:-}"; fi; }

# --- the two harnesses: reference (only with --rigenera, from commit $RIF) and current plugin, each with a recorder ---
if [ -n "$RIGENERA" ]; then
  [ -n "${MAAT_RIF_REPO:-}" ] || { echo "comandi-equivalenza.test.sh: --rigenera vuole MAAT_RIF_REPO=<repo con $RIF>" >&2; exit 2; }
  git -c safe.directory='*' -C "$MAAT_RIF_REPO" cat-file -e "$RIF:plugins/maat/scripts/gates.sh" 2>/dev/null ||
    { echo "comandi-equivalenza.test.sh: $RIF non e' nella storia di $MAAT_RIF_REPO" >&2; exit 2; }
  git -c safe.directory='*' -C "$MAAT_RIF_REPO" archive "$RIF" plugins/maat | tar -x -C "$T" && mv "$T/plugins/maat" "$T/vecchio" ||
    { echo "comandi-equivalenza.test.sh: harness $RIF non estraibile da git" >&2; exit 2; }
  OH=$T/vecchio
else
  [ -f "$RIFF" ] || { echo "comandi-equivalenza.test.sh: manca il riferimento $RIFF" >&2; exit 2; }
fi
NH=$T/nuovo; cp -r "$PLUGIN" "$NH"; find "$NH" -name __pycache__ -type d -prune -exec rm -rf {} +
[ -n "${GT:-}" ] && cp "$GT" "$NH/scripts/gates.sh"
[ -n "${FZ:-}" ] && cp "$FZ" "$NH/scripts/finalize.sh"
mv "$NH/scripts/test-fast.sh" "$NH/scripts/test-fast.real.sh"
printf '#!/usr/bin/env bash\nprintf "INV %%s\\n" "$*" >> "$REC"\nexec bash "$(dirname "$0")/test-fast.real.sh" "$@"\n' > "$NH/scripts/test-fast.sh"

# --- synthetic repository ---
R=$T/repo; A=$R/modules/app; ADM=$A/apps/admin; API=$R/modules/api
mkdir -p "$R/.claude" "$ADM/components/goals" "$ADM/components/x" "$ADM/utils" "$ADM/.nuxt" \
         "$A/packages/ui" "$A/node_modules/dep" "$API/app/routers" "$API/tests/routers"
cp "$PLUGIN/examples/nuxt-fastapi.maat.json" "$R/.claude/maat.json"
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
# deterministic base commit: fixed identity and dates, no git configuration of the machine (as tools/esempi-equiv)
(cd "$R" && export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z &&
  git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false &&
  git config core.filemode false && git add -A && git commit -qm init)
BASE_SHA=$(git -C "$R" rev-parse HEAD)

# --- fakes: npx, npm, venv python (they record pwd and arguments), wsl (we are already in WSL) ---
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
printf '#!/usr/bin/env bash\necho v20.0.0\n' > "$FB/node"   # the key's probe (node=) without the machine's node
chmod +x "$FB"/* "$NH/scripts/test-fast.sh"
export PATH="$FB:$PATH" REC=$T/rec FIC_GATES_ROOT=$R FIC_GATES_WSL=$FB/wsl FIC_GATES_VENV_PY=$FB/venv-python

# --- the copies (one HOME per harness), prepared once as --setup does by hand: the reference one only with --rigenera ---
HN=$T/home-nuovo; mkdir -p "$HN"
NORM=(-e "s#$HN/fic-mirror/modules/app#<copia>#g")
if [ -n "$RIGENERA" ]; then
  # the reference engine lived in the project: <repo>/script/test/vitest-fast.sh (with fic-mirror.sh next to it); it stays
  # there (untracked) only while the reference side runs
  mkdir -p "$R/script/test"
  git -c safe.directory='*' -C "$MAAT_RIF_REPO" show "$RIF:plugins/maat/scripts/vitest-fast.sh" > "$R/script/test/vitest-fast.sh"
  git -c safe.directory='*' -C "$MAAT_RIF_REPO" show "$RIF:plugins/maat/scripts/fic-mirror.sh" > "$R/script/test/fic-mirror.sh"
  printf '#!/usr/bin/env bash\nprintf "INV %%s\\n" "$*" >> "$REC"\nexec bash "%s/script/test/vitest-fast.sh" "$@"\n' "$R" > "$OH/scripts/vitest-fast.sh"
  chmod +x "$OH/scripts/vitest-fast.sh"
  HO=$T/home-vecchio; mkdir -p "$HO"
  (cd "$R" && HOME=$HO bash "$R/script/test/vitest-fast.sh" --setup) > "$T/setup.out" 2>&1 ||
    { echo "comandi-equivalenza.test.sh: --setup della copia del riferimento fallito" >&2; cat "$T/setup.out" >&2; exit 2; }
  NORM+=(-e "s#$HO/fic-mirror/modules/app#<copia>#g")
fi
NORM+=(-e "s#$R#<repo>#g" -e "s#--junitxml=[^ ]*#--junitxml=<report>#g")
NORM_BASE=(-e "s#$BASE_SHA#<base>#g")
norm() { sed "${NORM[@]}" ${NORM_BASE[@]+"${NORM_BASE[@]}"}; }
# the key view: the commands (cmd.*) out, normalized, tree=<tree>, as a set
norm_chiave() { grep -v '^cmd\.' | norm | sed -E 's/^tree=[0-9a-f]{40}$/tree=<tree>/' | LC_ALL=C sort; }
spec() { # $1 = spec file: review APPROVED + IMPLEMENTED, table counterproof PASS
  printf '%s\n' "# X" "## Contesto" "Contesto." "## Requisiti funzionali" "1. Fare A." \
    "## Piano di implementazione" "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" \
    "### Passi" "1. Modificare \`utils/goals.ts\`." \
    "## Review implementazione" "Review status: APPROVED" "Feature status: IMPLEMENTED" "Verification: VERIFIED" \
    "Reviewed snapshot: base aaaaaaaaaaaa · tree bbbbbbbbbbbb · fingerprint cccccccccccc · 2 paths" \
    "Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1" "" \
    "| Gate | Req. | Command / check | Result | Evidence |" \
    "| plan: counterproof on goals.ts | yes | mutazione | PASS | observed |" > "$1"
}
# a harness on a case: $1 vecchio|nuovo, $2 name, $3 level, $4 si|no (base.txt), file…; results in $T/<h>.*
gira() {
  local h=$1 n=$2 l=$3 b=$4 hr hm out ev x; shift 4
  if [ "$h" = vecchio ]; then hr=$OH hm=$HO; else hr=$NH hm=$HN; fi
  local run="$T/wf-$h/spec-$n.run"; mkdir -p "$run"; printf '%s\n' "$@" > "$run/touched.txt"
  [ "$b" = si ] && echo "$BASE_SHA" > "$run/base.txt"
  : > "$REC"
  out=$(cd "$R" && HOME=$hm FIC_GATES_HARNESS=$hr bash "$hr/scripts/gates.sh" --run-dir "$run" "$l" "$@" 2>&1)
  printf '%s\n' "$out" > "$T/$h.gates"
  # two lanes in parallel (native pytest, the rest in WSL): order matters within each lane, not between the two
  { norm < "$REC" | grep -v '^PYTEST '; norm < "$REC" | grep '^PYTEST '; } > "$T/$h.rec"
  printf '%s\n' "$out" | grep -E '^[a-z0-9-]+: [A-Z]' > "$T/$h.righe"
  printf '%s\n' "$out" | sed -n 's/^gates: esito=\([A-Z]*\).*/\1/p' > "$T/$h.esito"
  ev=$(printf '%s\n' "$out" | sed -n 's/^gates: .* evidence=\(.*\)$/\1/p' | tail -1)
  { [ -n "$ev" ] && norm_chiave < "$ev/chiave.txt"; } > "$T/$h.chiave"
  spec "${run%.run}.md"
  (cd "$R" && HOME=$hm FIC_GATES_HARNESS=$hr FIC_GATES="$hr/scripts/gates.sh" bash "${FZH:-$hr/scripts/finalize.sh}" --level "$l" "$run" 2>&1) |
    sed -n 's/^finalize: esito=\([A-Z_]*\).*/\1/p' > "$T/$h.firma"
  mkdir -p "$T/visti-$h"; cp "$REC" "$T/visti-$h/$n.rec.grezzo"
  for x in $VISTE; do cp "$T/$h.$x" "$T/visti-$h/$n.$x"; done
}
VISTE="rec righe esito chiave firma"
# the cases, in order: «name level base.txt(si|no) file…»
CASI=()
add() { CASI+=("$*"); }
F_MIX="modules/app/apps/admin/utils/goals.ts modules/api/app/routers/goals.py"
add vue-con-test std no modules/app/apps/admin/components/goals/Riga.vue
add vue-senza-test std no modules/app/apps/admin/components/x/Solo.vue
add ts-packages-ui std no modules/app/packages/ui/Button.ts
add router-specchio std no modules/api/app/routers/goals.py
add test-python-diretto std no modules/api/tests/test_diretto.py
add livello-min min no $F_MIX
add livello-std std no $F_MIX
add livello-full full no $F_MIX modules/app/packages/ui/Button.ts
add lint-con-base full si modules/app/apps/admin/components/goals/Riga.vue modules/app/packages/ui/Button.ts
add lint-senza-base full no modules/app/apps/admin/components/goals/Riga.vue
add fuori-modulo std no README.md modules/app/apps/admin/utils/goals.ts
add file-eliminato full no modules/app/apps/admin/utils/vecchio.ts
args_di() { local c; for c in "${CASI[@]}"; do [ "${c%% *}" = "$1" ] && { printf '%s\n' "$c"; return 0; }; done; return 1; }
# $1 case, $2 view, $3 reference file -> the lines of the section «== <case> <view>»
vista_rif() { awk -v h="== $1 $2" '$0 == h { on = 1; next } /^== / { on = 0 } on' "$3"; }
# $1 file -> the hygiene violations (empty = clean): a node= or tz_wsl= that is not the fixed one, a 40-digit sha, or the
# fixed probe missing altogether
igiene() {
  grep -n 'node=v' "$1" | grep -vE '^[0-9]+:node=v20\.0\.0$'
  grep -n 'tz_wsl=' "$1" | grep -vE '^[0-9]+:tz_wsl=UTC\|UTC\+0000$'
  grep -nE '(^|[^0-9a-f])[0-9a-f]{40}([^0-9a-f]|$)' "$1"
  grep -qx 'node=v20.0.0' "$1" || echo "manca node=v20.0.0"
  grep -qx 'tz_wsl=UTC|UTC+0000' "$1" || echo "manca tz_wsl=UTC|UTC+0000"
}

# --- --rigenera: the reference side on every case, then riferimento.txt; the engine files leave the repository ---
if [ -n "$RIGENERA" ]; then
  { echo "# comandi-equivalenza.test.sh: output of the reference harness $RIF on the synthetic repository, normalized."
    echo "# Generated, do not edit: MAAT_RIF_REPO=<repo with $RIF> bash plugins/maat/scripts/comandi-equivalenza.test.sh --rigenera"
  } > "$T/riferimento.nuovo"
  for c in "${CASI[@]}"; do
    # shellcheck disable=SC2086
    gira vecchio $c
    for x in $VISTE; do { echo "== ${c%% *} $x"; cat "$T/vecchio.$x"; } >> "$T/riferimento.nuovo"; done
  done
  rm -rf "$R/script"
  mkdir -p "$(dirname "$RIFF")" && cp "$T/riferimento.nuovo" "$RIFF" ||
    { echo "comandi-equivalenza.test.sh: $RIFF non scrivibile" >&2; exit 2; }
  echo "comandi-equivalenza.test.sh: riferimento riscritto ($RIFF, $(grep -c '^== ' "$RIFF") sezioni)"
fi

# --- the current plugin's copy, prepared once as --setup does by hand (after the engine files left, in --rigenera) ---
(cd "$R" && HOME=$HN bash "$NH/scripts/test-fast.real.sh" --setup) > "$T/setup.out" 2>&1 ||
  { echo "comandi-equivalenza.test.sh: --setup della copia fallito" >&2; cat "$T/setup.out" >&2; exit 2; }

# --- the reference: hygiene, one section per case and view ---
r=$(igiene "$RIFF")
chk "riferimento: igiene (node=, tz_wsl= fissi, nessuno sha di 40 cifre)" '[ -z "$r" ]' "$r"
r=$(for c in "${CASI[@]}"; do for x in $VISTE; do grep -qxF "== ${c%% *} $x" "$RIFF" || echo "manca == ${c%% *} $x"; done; done
    [ "$(grep -c '^== ' "$RIFF")" = $(( ${#CASI[@]} * 5 )) ] || echo "sezioni in piu': $(grep -c '^== ' "$RIFF")")
chk "riferimento: una sezione per caso e vista, nessuna in piu'" '[ -z "$r" ]' "$r"
uguali() { # $1 case name: the five comparisons
  local x
  for x in $VISTE; do
    chk "$1: $x identico" 'cmp -s "$T/vecchio.$x" "$T/nuovo.$x"' "$(diff "$T/vecchio.$x" "$T/nuovo.$x")"
  done
}
# the reference side of case $1 (from riferimento.txt, or file $2) -> $T/vecchio.<view>
dal_rif() { local x; for x in $VISTE; do vista_rif "$1" "$x" "${2:-$RIFF}" > "$T/vecchio.$x"; done; }
caso() { # $1 case name: the current plugin against the reference
  local c; c=$(args_di "$1") || { ko "$1: caso sconosciuto"; return; }
  dal_rif "$1"
  # shellcheck disable=SC2086
  gira nuovo $c
  uguali "$1"
}
cnt() { grep -c "$1" "$T/nuovo.rec"; }

# --- 1. .vue with the test next to it ---
caso vue-con-test
chk "  tests-fe: vitest in <copia>/apps/admin, test relativo alla radice" 'grep -qx "NPX <copia>/apps/admin|vitest run components/goals/Riga.test.ts" "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
chk "  niente autorichiamo: l'involucro una volta, dentro la copia solo vitest" '[ "$(cnt "^INV ")" = 1 ] && [ "$(grep -v "^INV " "$T/nuovo.rec" | grep -vc "^NPX <copia>/apps/admin|vitest run ")" = 0 ]' "$(cat "$T/nuovo.rec")"
# --- 2. .vue without test: tests-fe SKIPPED and signature IMPLEMENTED, as before ---
caso vue-senza-test
chk "  tests-fe SKIPPED e firma IMPLEMENTED" 'grep -q "^tests-fe: SKIPPED" "$T/nuovo.righe" && [ "$(cat "$T/nuovo.firma")" = IMPLEMENTED ]' "$(cat "$T/nuovo.righe" "$T/nuovo.firma")"
# --- 3. .ts in packages/ui ---
caso ts-packages-ui
# --- 4. Python router with mirror test ---
caso router-specchio
chk "  tests-be: pytest in <repo>/modules/api, -q, --junitxml, selezione relativa al modulo" 'grep -qx "PYTEST <repo>/modules/api|-m pytest -q --junitxml=<report> tests/routers/test_goals.py" "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
# --- 5. Python test directly ---
caso test-python-diretto
# --- 6-8. the three levels ---
caso livello-min
caso livello-std
caso livello-full
chk "  build: npm run build:admin in <repo>/modules/app" 'grep -qx "NPM <repo>/modules/app|run build:admin" "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
# --- 9. lint with --base (the extra file of packages/ui classified) ---
caso lint-con-base
chk "  lint: npm run -s lint in <copia>/apps/admin, file relativo alla radice" 'grep -qx "NPM <copia>/apps/admin|run -s lint -- components/goals/Riga.vue" "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
chk "  messaggi del file extra: eslint in <copia>/packages/ui" 'grep -q "^NPX <copia>/packages/ui|eslint --format compact --quiet " "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
chk "  --base nella riga dell'involucro" 'grep -qx "INV --lint --base <base> modules/app/apps/admin/components/goals/Riga.vue modules/app/packages/ui/Button.ts" "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
chk "  niente autorichiamo: involucro una volta per gate (tests-fe, lint), nella copia solo vitest/npm/eslint" '[ "$(cnt "^INV ")" = 2 ] && [ "$(grep -Ev "^(INV |NPX <copia>/[a-z/]*\|(vitest run|eslint) |NPM <copia>/apps/admin\|run -s lint |NPM <repo>/modules/app\|run build:admin$|PYTEST )" "$T/nuovo.rec" | wc -l)" = 0 ]' "$(cat "$T/nuovo.rec")"
# --- 10. lint without base.txt: no --base ---
caso lint-senza-base
chk "  nessun --base" 'grep -q "^INV --lint " "$T/nuovo.rec" && ! grep -q -- "--base" "$T/nuovo.rec"' "$(cat "$T/nuovo.rec")"
# --- 11. file outside every module ---
caso fuori-modulo
chk "  il plugin lo dichiara non coperto" 'grep -q "^non coperto: README.md" "$T/nuovo.gates"' "$(cat "$T/nuovo.gates")"
# --- 12. deleted file ---
caso file-eliminato

# --- no self-invocation in the configuration: S5, S6; two modules with a copy without MAAT_MODULO -> 64 ---
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

# --- counterproof: signing IMPLEMENTED only with PASS => the «.vue senza test» case diverges ---
MF=$NH/scripts/finalize.mut.sh
sed 's/^        elif es != "SKIPPED":$/        else:/' "$NH/scripts/finalize.sh" > "$MF"
if cmp -s "$NH/scripts/finalize.sh" "$MF"; then ko "controprova: la mutazione (SKIPPED non soddisfa) non si applica"; else
  dal_rif vue-senza-test   # the reference side of the same case
  FZH=$MF gira nuovo vue-senza-test-mut std no modules/app/apps/admin/components/x/Solo.vue
  if [ "$(cat "$T/nuovo.firma")" = NEEDS_VERIFICATION ] && ! cmp -s "$T/vecchio.firma" "$T/nuovo.firma"; then ok   # expected red
  else ko "controprova: col mutante la firma del caso «.vue senza test» coincide ancora (il test non discrimina)" "$(cat "$T/vecchio.firma" "$T/nuovo.firma")"; fi
fi

# --- counterproofs on the frozen reference (copies of riferimento.txt; the views of the plugin are those already seen) ---
V=$T/visti-nuovo
# a line changed in a copy -> that case diverges: the test really reads the file
Q=$T/rif-cambiato; awk 'BEGIN { c = 0 } /^== vue-con-test righe$/ { c = 1; print; next } c == 1 { print $0 "X"; c = 2; next } { print }' "$RIFF" > "$Q"
dal_rif vue-con-test "$Q"
if cmp -s "$Q" "$RIFF"; then ko "controprova: la riga del riferimento non cambia nella copia"
elif cmp -s "$T/vecchio.righe" "$V/vue-con-test.righe"; then ko "controprova: una riga cambiata nel riferimento non fa divergere vue-con-test (il test non legge il file)"
else ok; fi   # expected red
# the real base sha in a copy -> hygiene red
Q=$T/rif-base; sed "s#<base>#$BASE_SHA#" "$RIFF" > "$Q"
r=$(igiene "$Q")
chk "controprova: il BASE_SHA vero in una copia del riferimento fa rossa l'igiene" '! cmp -s "$Q" "$RIFF" && [ -n "$r" ]' "$r"
# norm without the <base> rule -> «lint-con-base» diverges (the raw record of the plugin, normalized without it)
NORM_BASE=()
{ norm < "$V/lint-con-base.rec.grezzo" | grep -v '^PYTEST '; norm < "$V/lint-con-base.rec.grezzo" | grep '^PYTEST '; } > "$T/senza-base.rec"
NORM_BASE=(-e "s#$BASE_SHA#<base>#g")
vista_rif lint-con-base rec "$RIFF" > "$T/vecchio.rec"
if ! cmp -s "$V/lint-con-base.rec" "$T/vecchio.rec"; then ko "controprova <base>: lint-con-base rec non e' identico col riferimento"
elif cmp -s "$T/senza-base.rec" "$T/vecchio.rec"; then ko "controprova: norm senza la regola <base> non fa divergere lint-con-base"
else ok; fi   # expected red

echo "comandi-equivalenza.test.sh: $pass ok, $fail falliti"
[ $fail -eq 0 ]
