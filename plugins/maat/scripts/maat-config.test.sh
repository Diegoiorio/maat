#!/usr/bin/env bash
# maat-config.test.sh — schema, single reader (maat-config.py), bash interface (lib/maat-conf.sh) and profiles (pk03).
#   bash plugins/maat/scripts/maat-config.test.sh          (Git Bash or WSL)
#   MC=/path/variant.py bash .../maat-config.test.sh   # the suite against another reader
# The mutation counterproofs run inside the suite: the reader is copied to a temporary folder, a sed mutates it,
# and the case the mutation must break is rerun on the copy: it must turn red.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(dirname "$HERE")
MC=${MC:-$HERE/maat-config.py}
. "$HERE/python.sh" || true
[ -n "${FIC_PY:-}" ] || { echo "maat-config.test.sh: nessun Python utilizzabile" >&2; exit 2; }
export PYTHONIOENCODING=utf-8 PYTHONDONTWRITEBYTECODE=1
unset MAAT_CONFIG FIC_GATES_VENV_PY PROJECT_ROOT MAAT_ROOT
pass=0 fail=0
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
T=$(cd "$T" && { pwd -W 2>/dev/null || pwd; })   # C:/… form on Windows: understood by both bash and Python
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; sed 's/^/    /' "$T/out" 2>/dev/null; fi; }
mc() { "$FIC_PY" "$MC" "$@"; }
SS=$PLUGIN/examples/nuxt-fastapi.maat.json
DO=$PLUGIN/examples/bash-node.maat.json

# --- 0. the validator covers every construct used by the schema -------------------------------------------------
"$FIC_PY" -c '
import json, sys
NOTI = {"$schema", "$id", "title", "description", "default", "type", "required", "enum", "properties", "items",
        "additionalProperties", "pattern"}
def giro(s, k):
    extra = set(s) - NOTI
    if extra: print("costrutto non supportato in %s: %s" % (k or "(radice)", sorted(extra))); sys.exit(1)
    for n, x in s.get("properties", {}).items(): giro(x, k + "." + n)
    if isinstance(s.get("items"), dict): giro(s["items"], k + "[]")
    if s.get("additionalProperties", False) is not False:
        print("additionalProperties diverso da false in %s: il validatore conosce solo false" % (k or "(radice)")); sys.exit(1)
giro(json.load(open(sys.argv[1], encoding="utf-8")), "")
' "$PLUGIN/schemas/maat-config.schema.json" > "$T/out" 2>&1
check "schema: solo costrutti che il validatore interno conosce" '[ $? = 0 ]'

# --- 1. valid examples ---------------------------------------------------------------------------------------------
mc valida "$SS" > "$T/out" 2>&1; check "esempio nuxt-fastapi valido" '[ $? = 0 ]'
mc valida "$DO" > "$T/out" 2>&1; check "esempio bash-node valido" '[ $? = 0 ]'

# --- 2. minimal maat.json (R2: "5 lines") and defaults ---------------------------------------------------------------
mkdir -p "$T/min/.claude"
cat > "$T/min/.claude/maat.json" <<'EOF'
{"versione_schema": 1,
 "moduli": [{"nome": "app", "radice": ".",
             "comandi": {"test": "npm test -- {test}"}}]}
EOF
MIN=$T/min/.claude/maat.json
mc valida "$MIN" > "$T/out" 2>&1; check "maat.json minimo valido" '[ $? = 0 ]'
leggi() { MAAT_CONFIG=$MIN mc leggi "$1" 2>"$T/out"; }
check "default moduli.0.regola_test = accanto" '[ "$(leggi moduli.0.regola_test)" = accanto ]'
check "default moduli.0.ambiente = nativo" '[ "$(leggi moduli.0.ambiente)" = nativo ]'
check "default moduli.0.radice_pacchetti = radice (.)" '[ "$(leggi moduli.0.radice_pacchetti)" = . ]'
# alignment note from pk04b: the checks run at every level
check "default gate.full = test controlli lint build" '[ "$(leggi gate.full)" = "test controlli lint build" ]'
check "default gate.min = test controlli" '[ "$(leggi gate.min)" = "test controlli" ]'
check "default cartelle.lavoro" '[ "$(leggi cartelle.lavoro)" = .claude/.ai-workflow ]'
check "default piattaforma.copia_wsl = auto" '[ "$(leggi piattaforma.copia_wsl)" = auto ]'
check "default lingua = en" '[ "$(leggi lingua)" = en ]'
check "default moduli.0.report = nessuno" '[ "$(leggi moduli.0.report)" = nessuno ]'
MAAT_CONFIG=$MIN mc leggi guardia.produzione > "$T/out" 2>&1; rc=$?
check "leggi: chiave assente -> exit 3" '[ $rc = 3 ] && grep -q "chiave assente" "$T/out"'
check "leggi --default" '[ "$(MAAT_CONFIG=$MIN mc leggi guardia.produzione --default nessuna)" = nessuna ]'
# without MAAT_CONFIG: <PROJECT_ROOT>/.claude/maat.json
check "senza MAAT_CONFIG: <PROJECT_ROOT>/.claude/maat.json" '[ "$(PROJECT_ROOT=$T/min mc leggi moduli.0.nome 2>&1)" = app ]'
MAAT_CONFIG=$MIN mc modulo-di README.md > "$T/out" 2>&1; rc=$?
check "radice \".\": modulo-di README.md -> app radice" '[ $rc = 0 ] && [ "$(cat "$T/out")" = "app radice" ]'
MAAT_CONFIG=$T/nessuno.json mc valida > "$T/out" 2>&1; rc=$?
check "file mancante -> exit 4 e /maat:setup" '[ $rc = 4 ] && grep -q "progetto non configurato: lancia /maat:setup" "$T/out"'

# --- 3. invalid cases: exit 1 and the key in the message --------------------------------------------------------------
M='{"nome":"app","radice":".","comandi":{"test":"npm test -- {test}"}}'
ko() { # <description> <json> <expected key> [expected text]
  printf '%s\n' "$2" > "$T/ko.json"
  mc valida "$T/ko.json" > "$T/out" 2>&1; local rc=$?
  KO_CHIAVE=$3 KO_TESTO=${4:-}
  check "non valido: $1" '[ $rc = 1 ] && grep -qF -- ": $KO_CHIAVE: " "$T/out" && grep -qF -- "$KO_TESTO" "$T/out"'
}
caso_sconosciuta() { printf '%s\n' "{\"versione_schema\":1,\"moduli\":[$M],\"sconosciuta\":1}" > "$T/k1.json"
  "$FIC_PY" "$1" valida "$T/k1.json" > "$T/out" 2>&1; [ $? = 1 ] && grep -qF ": sconosciuta: chiave sconosciuta" "$T/out"; }
check "non valido: chiave sconosciuta (additionalProperties)" 'caso_sconosciuta "$MC"'
ko "regola_test fuori elenco (enum)" '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","regola_test":"vicino"}]}' moduli.0.regola_test "fuori elenco"
ko "moduli mancante (required)" '{"versione_schema":1}' moduli "obbligatoria"
ko "moduli oggetto (type)" '{"versione_schema":1,"moduli":{}}' moduli "tipo array"
ko "controlli senza glob (items + required)" '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","controlli":[{"comando":"bash -n {file}"}]}]}' moduli.0.controlli.0.glob "obbligatoria"
ko "cartella fuori elenco (properties + enum)" '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","comandi":{"test":{"comando":"t {test}","cartella":"altrove"}}}]}' moduli.0.comandi.test.cartella "fuori elenco"
ko "harness senza >= (pattern)" "{\"versione_schema\":1,\"harness\":\"1.0\",\"moduli\":[$M]}" harness "non rispetta la forma"
caso_s1() { printf '%s\n' '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","regola_test":"specchio"}]}' > "$T/k8.json"
  "$FIC_PY" "$1" valida "$T/k8.json" > "$T/out" 2>&1; [ $? = 1 ] && grep -qF ": moduli.0.specchio: " "$T/out" && grep -q "(S1)" "$T/out"; }
check "non valido: specchio mancante (S1)" 'caso_s1 "$MC"'
ko "comandi.test senza {test} (S2)" '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","comandi":{"test":"npm test"}}]}' moduli.0.comandi.test "(S2)"
ko "controlli senza {file} (S2)" '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","controlli":[{"glob":"*.sh","comando":"bash -n"}]}]}' moduli.0.controlli.0.comando "(S2)"
ko "versione_schema futura (S3)" "{\"versione_schema\":2,\"moduli\":[$M]}" versione_schema "versione futura: aggiorna il plugin"
ko "comando numero (type lista)" '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","comandi":{"test":5}}]}' moduli.0.comandi.test "tipo string o object"
ko "lingua fuori elenco" "{\"versione_schema\":1,\"lingua\":\"fr\",\"moduli\":[$M]}" lingua "fuori elenco"
ko "lint_base senza {base?} (S4)" '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","lint_base":true,"comandi":{"lint":"eslint {file}"}}]}' moduli.0.comandi.lint "(S4)"
ko "test-fast.sh senza copia (S5)" '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","comandi":{"test":"bash {maat}/scripts/test-fast.sh {test}"}}]}' moduli.0.copia.test "(S5)"
ko "copia che chiama test-fast.sh (S6)" '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","comandi":{"test":"bash {maat}/scripts/test-fast.sh {test}"},"copia":{"test":"bash {maat}/scripts/test-fast.sh {test}"}}]}' moduli.0.copia.test "(S6)"
ko "copia.lint senza {file} (S7)" '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","copia":{"lint":[{"comando":"npx eslint"}]}}]}' moduli.0.copia.lint.0 "(S7)"
caso_s8() { printf '%s\n' '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","regola_test":"nessuna","comandi":{"test":"t {test}"}}]}' > "$T/ks8.json"
  "$FIC_PY" "$1" valida "$T/ks8.json" > "$T/out" 2>&1; [ $? = 1 ] && grep -qF ": moduli.0.comandi.test: regola nessuna ma comando di test dichiarato (S8)" "$T/out"; }
check "non valido: regola nessuna con comandi.test (S8)" 'caso_s8 "$MC"'

# --- 4. modulo-di ----------------------------------------------------------------------------------------------------
caso_pacchetti() { local o; o=$(MAAT_CONFIG=$SS "$FIC_PY" "$1" modulo-di modules/app/packages/ui/y.ts 2>&1) && [ "$o" = "fe pacchetti" ]; }
check "modulo-di admin/x.vue -> fe radice" '[ "$(MAAT_CONFIG=$SS mc modulo-di modules/app/apps/admin/x.vue)" = "fe radice" ]'
check "modulo-di packages/ui/y.ts -> fe pacchetti (APP di gates.sh:107)" 'caso_pacchetti "$MC"'
check "modulo-di api/app/routers/a.py -> be radice" '[ "$(MAAT_CONFIG=$SS mc modulo-di modules/api/app/routers/a.py)" = "be radice" ]'
MAAT_CONFIG=$SS mc modulo-di README.md > "$T/out" 2>&1; rc=$?
check "modulo-di README.md -> stdout vuoto, exit 2" '[ $rc = 2 ] && [ ! -s "$T/out" ]'
printf '%s\n' '{"versione_schema":1,"moduli":[{"nome":"a","radice":"a"},{"nome":"ab","radice":"a/b"}]}' > "$T/annidate.json"
caso_annidate() { [ "$(MAAT_CONFIG=$T/annidate.json "$FIC_PY" "$1" modulo-di a/b/x 2>&1)" = "ab radice" ] &&
                  [ "$(MAAT_CONFIG=$T/annidate.json "$FIC_PY" "$1" modulo-di a/y 2>&1)" = "a radice" ]; }
check "radici annidate: a/b/x -> ab, a/y -> a (vince la più lunga)" 'caso_annidate "$MC"'

# --- 5. comando: the strings of gates.sh 137-146 and 216 ------------------------------------------------------------
# Declared normalizations: repo root -> <repo>; report path -> <report>; the mirror-copy script
# (in gates.sh:58,130 `$(sq "$VF")` = '<repo>/script/test/vitest-fast.sh', quoted; in the plugin {maat} quoted plus
# /scripts/test-fast.sh = '<plugin root>'/scripts/test-fast.sh) -> '<VF>'. The expectations below are the literal
# form gates.sh produces, with the line reference.
R=$T/ss MR=$T/maatroot
cmd() { MAAT_CONFIG=$SS PROJECT_ROOT=$R MAAT_ROOT=$MR "$FIC_PY" "${MCX:-$MC}" comando "$@" 2>&1 |
        sed -e "s#$R/ev/tests-be.junit.xml#<report>#g" -e "s#'$MR'/scripts/test-fast.sh#'<VF>'#g" -e "s#$R#<repo>#g"; }
riga() { printf '%s\n%s' "$1" "$2"; }
# gates.sh:216  (cd "$ROOT/$API" && "$VPY" -m pytest -q --junitxml="$WEV/tests-be.junit.xml" "${BE_SEL[@]}"), VPY from 128
# (From the reference project the example has python [.venv312/bin/python, .venv/bin/python]: neither exists -> the last)
E_BE="<repo>/modules/api/.venv/bin/python -m pytest -q --junitxml=<report> 'tests/test_a.py' 'tests/routers/test_a_b.py'"
check "tests-be = comando eseguito di gates.sh:216, da modules/api" \
  '[ "$(cmd be test --test modules/api/tests/test_a.py --test modules/api/tests/routers/test_a_b.py --report "$R/ev/tests-be.junit.xml")" = "$(riga modules/api "$E_BE")" ]'
# gates.sh:141  CMD[tests-fe]="bash $(sq "$VF")$(join_q "${FE_SEL[@]}")", FE_SEL relative to ADM (110)
E_FE="bash '<VF>' 'components/x.test.ts'"
check "tests-fe = gates.sh:141, dalla radice del modulo" \
  '[ "$(cmd fe test --test modules/app/apps/admin/components/x.test.ts)" = "$(riga modules/app/apps/admin "$E_FE")" ]'
# gates.sh:145  CMD[lint]="bash $(sq "$VF") --lint${base:+ --base $(sq "$base")}$(join_q "${APP[@]}")"
E_LINT_BASE="bash '<VF>' --lint --base 'b' 'modules/app/apps/admin/x.vue' 'modules/app/packages/ui/y.ts'"
E_LINT="bash '<VF>' --lint 'modules/app/apps/admin/x.vue'"
caso_lint_base() { [ "$(MCX=$1 cmd fe lint --base b --file modules/app/apps/admin/x.vue --file modules/app/packages/ui/y.ts)" = \
  "$(riga . "$E_LINT_BASE")" ]; }
check "lint con base = gates.sh:145, dal repo" 'caso_lint_base "$MC"'
caso_lint_senza() { local o; o=$(MCX=$1 cmd fe lint --file modules/app/apps/admin/x.vue)
  [ "$o" = "$(riga . "$E_LINT")" ] && ! printf '%s' "$o" | grep -q -- --base; }
check "lint senza base: nessun --base (gates.sh:145)" 'caso_lint_senza "$MC"'
# gates.sh:146  CMD[build]="cd $(sq "$WROOT/modules/app") && npm run build:admin"
check "build = gates.sh:146, da radice_pacchetti" '[ "$(cmd fe build)" = "$(riga modules/app "npm run build:admin")" ]'
E_SPAZIO="bash '<VF>' 'a b.test.ts' 'c.test.ts'"
check "{test} con uno spazio: argomenti separati e quotati" \
  '[ "$(cmd fe test --test "modules/app/apps/admin/a b.test.ts" --test modules/app/apps/admin/c.test.ts)" = "$(riga modules/app/apps/admin "$E_SPAZIO")" ]'
MSP="$T/con spazio"
check "{maat} con uno spazio resta un solo argomento quotato" \
  '[ "$(MAAT_CONFIG=$SS PROJECT_ROOT=$R MAAT_ROOT=$MSP mc comando fe test --test modules/app/apps/admin/x.test.ts | tail -1)" = "bash '"'"'$MSP'"'"'/scripts/test-fast.sh '"'"'x.test.ts'"'"'" ]'
cmd fe test --test modules/api/tests/test_a.py > "$T/out"; rc=${PIPESTATUS[0]}
check "file fuori dalla cartella del comando -> exit 64" '[ $rc = 64 ]'
MAAT_CONFIG=$SS PROJECT_ROOT=$R mc comando be lint > "$T/out" 2>&1; rc=$?
check "comando non dichiarato -> exit 2" '[ $rc = 2 ] && grep -q "non dichiarato" "$T/out"'
check "FIC_GATES_VENV_PY vince su moduli[].python" \
  '[ "$(FIC_GATES_VENV_PY=$T/py.exe cmd be test --test modules/api/tests/test_a.py --report "$R/ev/tests-be.junit.xml" | tail -1)" = "$T/py.exe -m pytest -q --junitxml=<report> '"'"'tests/test_a.py'"'"'" ]'
check "controprova vitest: {test} relativo alla radice, {nome} quotato" \
  '[ "$(cmd fe controprova --test modules/app/apps/admin/a.test.ts --nome "il caso" --report r.json | tail -1)" = "CI=true npx vitest run '"'"'a.test.ts'"'"' -t '"'"'il caso'"'"' --reporter=default --reporter=json --outputFile.json=r.json" ]'
check "elenco-moduli" '[ "$(MAAT_CONFIG=$SS mc elenco-moduli | tr "\n" " ")" = "fe be " ]'

# --- 6. nuxt-fastapi example: guardia equal to guard.py and run-phase.sh (lines copied over) -------------------------
"$FIC_PY" -c '
import json, re, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))["guardia"]
# PROD_RE of guard.py before the split (5f0d933:80-86), deploy-production included: it stays in rilascio too (review pk05)
attesi = [r"prod\.example\.internal", r"(?<![0-9.])10\.20\.30\.40(?![0-9])",
          r"(?<![-a-z0-9])(app|api|auth)\.example\.com",
          r"(?<![-a-z0-9.@])((www|api|app|auth)\.)?example\.org(?![-a-z0-9])",
          "script/prod/", "deploy-production", r"docker-compose\.prod", "run-and-clean-prod"]
assert c["produzione"] == attesi, c["produzione"]
assert c["rilascio"] == ["script/deploy-production.sh"]
# guard.py:129-130 (WRAPPER_SCRIPTS) and 310-311 (dev-sql.sh --apply denied)
inv = [x if isinstance(x, str) else x["script"] for x in c["involucri"]]
assert inv == ["script/dev/dev-exec.sh", "script/dev/dev-sql.sh", "script/rsync-once.sh",
               "script/test/vitest-fast.sh", "script/test/counterproof.sh"], inv
assert c["involucri"][1]["opzioni_negate"] == ["--apply"]
# run-phase.sh:537-538: the rsyncs, which are not release scripts, and `bash script/prod` (pk05: the current DENY, nothing lost)
assert c["vietati_extra"] == ["bash script/rsync-once.sh", "bash script/rsync.sh", "script/rsync-once.sh", "bash script/prod"]
# every probe matches at least one produzione regex
for s in c["sonde"]:
    assert any(re.search(r, "curl -s https://%s/" % s, re.I) for r in c["produzione"]), s
' "$SS" > "$T/out" 2>&1
check "guardia dell'esempio = guard.py:81-86,129-130 e run-phase.sh:537-538; sonde coperte" '[ $? = 0 ]'
o=$(MAAT_CONFIG=$SS mc sonda-produzione); rc=$?
check "sonda-produzione con sonde -> curl sulla prima, exit 0" '[ $rc = 0 ] && [ "$o" = "curl -s https://prod.example.internal/" ]'
o=$(MAAT_CONFIG=$MIN mc sonda-produzione); rc=$?
check "sonda-produzione senza guardia -> ripiego del nucleo, exit 3" '[ $rc = 3 ] && [ "$o" = "git push --force origin x" ]'
printf '%s\n' "{\"versione_schema\":1,\"guardia\":{\"produzione\":[],\"sonde\":[\"x.y\"]},\"moduli\":[$M]}" > "$T/vuota.json"
o=$(MAAT_CONFIG=$T/vuota.json mc sonda-produzione); rc=$?
check "sonda-produzione con produzione vuota -> ripiego, exit 3" '[ $rc = 3 ] && [ "$o" = "git push --force origin x" ]'

# --- 7. profiles: componi --------------------------------------------------------------------------------------------
mc componi nuxt-vitest fastapi-pytest --radice fe=modules/app/apps/admin --radice be=modules/api > "$T/comp.json" 2>"$T/out"
check "componi nuxt-vitest + fastapi-pytest esce 0" '[ $? = 0 ]'
mc valida "$T/comp.json" > "$T/out" 2>&1; check "  e il risultato è valido" '[ $? = 0 ]'
"$FIC_PY" -c '
import json, sys
def pulisci(c):
    # only the project-specific parts: project sections, language, build, python, radice_pacchetti
    for k in ("guardia", "lingua", "verifica_remota", "contesto", "piano", "da_non_toccare", "generati"):
        c.pop(k, None)
    for m in c["moduli"]:
        # where the interpreter runs (python and its ambiente) is a project choice: in the reference project the
        # example be module runs in WSL, the fastapi-pytest profile stays nativo
        if "{python}" in json.dumps(m):
            m.pop("ambiente", None)
        m.pop("python", None); m.pop("radice_pacchetti", None); m.get("comandi", {}).pop("build", None)
        # pk04b-2: the read-only counterproof folders (copia_anche) belong to the project, not the profile
        m.pop("copia_anche", None)
    return c
def dipendenze(a, b):
    # pk04b-2: the links and dependency files of the profile are a subset of those of the example (the project
    # adds the monorepo folders, the repo node_modules and .venv312); then they are removed
    for ma, mb in zip(a["moduli"], b["moduli"]):
        for k in ("collega_nel_worktree", "file_dipendenze"):
            pa, pb = ma.pop(k, []), mb.pop(k, [])
            if not pa or any(x not in pb for x in pa):
                print("%s del modulo %s: il profilo %s non sta nell esempio %s" % (k, ma["nome"], pa, pb)); sys.exit(1)
def pulisci_chiave(c):
    for m in c["moduli"]:
        # pk04b-1: the chiave entries from the former gates.sh lines (vitest, eslint, deps, node_modules, pip) belong
        # to the example; the nuxt-vitest profile brings only tsconfig
        k = [v for v in m.get("chiave", []) if v.get("etichetta") == "tsconfig"]
        if k:
            m["chiave"] = k
        else:
            m.pop("chiave", None)
    return c
a = json.load(open(sys.argv[1], encoding="utf-8")); b = json.load(open(sys.argv[2], encoding="utf-8"))
assert a["lingua"] == "en", a.get("lingua")   # componi (used by /maat:setup) writes the default language
assert a["moduli"][0]["comandi"]["build"]["comando"] == "npm run build"
assert b["moduli"][0]["comandi"]["build"]["comando"] == "npm run build:admin"
assert a["moduli"][0]["radice_pacchetti"] == "modules/app/apps/admin" and b["moduli"][0]["radice_pacchetti"] == "modules/app"
a, b = pulisci(a), pulisci(b)
dipendenze(a, b)
a, b = pulisci_chiave(a), pulisci_chiave(b)
if a != b:
    print(json.dumps(a, indent=1, sort_keys=True)); print("---"); print(json.dumps(b, indent=1, sort_keys=True)); sys.exit(1)
' "$T/comp.json" "$SS" > "$T/out" 2>&1
check "componi equivale a examples/nuxt-fastapi.maat.json, tolte solo le parti del progetto" '[ $? = 0 ]'
for p in nuxt-vitest fastapi-pytest node-semplice generico-senza-test; do
  mc componi "$p" --radice m=. > "$T/p.json" 2>"$T/out" && mc valida "$T/p.json" > "$T/out" 2>&1
  check "profilo $p: componi da solo dà un maat.json valido" '[ $? = 0 ]'
done
mc componi nuxt-vitest > "$T/out" 2>&1; check "componi senza --radice -> exit 64" '[ $? = 64 ]'

# pk06, note C: without WSL (or outside Windows) /maat:setup proposes ambiente nativo: componi --nativo
mkdir -p "$T/nat-vuoto" "$T/nat-lb/web"; : > "$T/nat-lb/web/lint-baseline.mjs"
caso_nativo() { # [reader]: nuxt-vitest + fastapi-pytest --nativo -> valid, nativo, no mirror copy, copia_wsl no, no test-fast.sh
  PROJECT_ROOT=$T/nat-vuoto "$FIC_PY" "${1:-$MC}" componi nuxt-vitest fastapi-pytest --radice fe=web --radice be=api --nativo > "$T/nat.json" 2>"$T/out" &&
    "$FIC_PY" "${1:-$MC}" valida "$T/nat.json" >> "$T/out" 2>&1 &&
    "$FIC_PY" -c 'import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
assert c["piattaforma"]["copia_wsl"] == "no", c.get("piattaforma")
for m in c["moduli"]:
    assert m.get("ambiente", "nativo") == "nativo", m["nome"]
    assert "copia" not in m, m["nome"]
    assert "test-fast.sh" not in json.dumps(m.get("comandi", {})), m["comandi"]
fe = c["moduli"][0]
assert fe["comandi"]["test"] == {"comando": "CI=true npx vitest run {test}", "cartella": "radice"}, fe["comandi"]["test"]
assert fe["comandi"]["lint"] == {"comando": "CI=true npx eslint --quiet {file}", "cartella": "radice"}, fe["comandi"]["lint"]
assert fe["lint_base"] is False
' "$T/nat.json" >> "$T/out" 2>&1
}
check "componi --nativo: ambiente nativo, niente copia, copia_wsl no, comandi della copia eseguiti nel repo" 'caso_nativo'
caso_nativo_lb() { # [reader]: with web/lint-baseline.mjs in the project --nativo picks the alternative of its se_esiste
  PROJECT_ROOT=$T/nat-lb "$FIC_PY" "${1:-$MC}" componi nuxt-vitest --radice fe=web --nativo > "$T/nat-lb.json" 2>"$T/out" &&
    "$FIC_PY" "${1:-$MC}" valida "$T/nat-lb.json" >> "$T/out" 2>&1 &&
    "$FIC_PY" -c 'import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))["moduli"][0]
assert m["comandi"]["lint"] == {"comando": "CI=true npm run -s lint -- {file}", "cartella": "radice"}, m["comandi"]["lint"]
' "$T/nat-lb.json" >> "$T/out" 2>&1
}
check "componi --nativo con lint-baseline.mjs nella radice del modulo -> lint = l'alternativa del suo se_esiste" 'caso_nativo_lb'
mc componi nuxt-vitest --radice fe=web > "$T/wsl.json" 2>"$T/out"
check "componi senza --nativo: nuxt-vitest resta ambiente wsl con copia" \
  '"$FIC_PY" -c "import json,sys; m=json.load(open(sys.argv[1]))[\"moduli\"][0]; sys.exit(0 if m[\"ambiente\"] == \"wsl\" and \"copia\" in m else 1)" "$T/wsl.json"'

# node-semplice: tests only if there are *.test.js files (se_presente)
mkdir -p "$T/ns/.claude" "$T/ns/pkg"
mc componi node-semplice --radice n=pkg > "$T/ns/.claude/maat.json"
MAAT_CONFIG=$T/ns/.claude/maat.json PROJECT_ROOT=$T/ns mc comando n test --test pkg/a.test.js > "$T/out" 2>&1; rc=$?
check "node-semplice senza *.test.js: test NOT RUN (dichiarato), exit 3" '[ $rc = 3 ] && grep -q "NOT RUN (dichiarato)" "$T/out"'
mkdir -p "$T/ns/pkg/lib"; : > "$T/ns/pkg/lib/a.test.js"
o=$(MAAT_CONFIG=$T/ns/.claude/maat.json PROJECT_ROOT=$T/ns mc comando n test --test pkg/lib/a.test.js 2>&1); rc=$?
check "node-semplice con *.test.js: node --test" '[ $rc = 0 ] && [ "$o" = "$(riga pkg "node --test '"'"'lib/a.test.js'"'"'")" ]'
o=$(MAAT_CONFIG=$T/ns/.claude/maat.json PROJECT_ROOT=$T/ns mc comando n controlli --file pkg/x.js --file README.md 2>&1); rc=$?
check "node-semplice: controlli node --check sul solo .js del modulo" '[ $rc = 0 ] && [ "$o" = "$(riga pkg "node --check '"'"'x.js'"'"'")" ]'

# generico-senza-test: {python} falls back to python3 from PATH; without it, the JSON check is NOT RUN (declared)
mkdir -p "$T/gen/.claude" "$T/vuoto"
mc componi generico-senza-test --radice g=. > "$T/gen/.claude/maat.json"
gen() { (cd "$T/vuoto" && PATH=$T/vuoto MAAT_CONFIG=$T/gen/.claude/maat.json PROJECT_ROOT=$T/gen "$FIC_PY" "$MC" comando g controlli "$@"); }
gen --file a.sh --file b.sh --file d/c.json > "$T/o1" 2> "$T/e1"; rc=$?
cp "$T/e1" "$T/out"
check "generico senza python3 né shellcheck: bash -n per file, JSON e shellcheck dichiarati" \
  '[ $rc = 0 ] && [ "$(cat "$T/o1")" = "$(printf ".\nbash -n '"'"'a.sh'"'"'\n.\nbash -n '"'"'b.sh'"'"'")" ] && grep -q "{python} -m json.tool {file} — NOT RUN (dichiarato)" "$T/e1" && grep -q "shellcheck {file} — NOT RUN (dichiarato): shellcheck assente" "$T/e1"'
gen --file d/c.json > "$T/out" 2>&1; rc=$?
check "generico: solo un JSON e niente python -> exit 3 (tutto saltato)" '[ $rc = 3 ]'
o=$(FIC_GATES_VENV_PY=$T/py.exe gen --file d/c.json 2>/dev/null)
check "generico: con un interprete, json.tool su un file per invocazione" '[ "$o" = "$(riga . "$T/py.exe -m json.tool '"'"'d/c.json'"'"'")" ]'
# pk09 (pilot on a second project): the python3-from-PATH fallback does not yield the Store stub. Under …/WindowsApps/ it is probed with
# arguments and a timeout: exits 9009 (the stub) -> discarded; answers -c "import sys" (Python Install Manager) -> kept.
WA="$T/wa/Microsoft/WindowsApps"; mkdir -p "$WA"; WAU=$(cd "$WA" && pwd)   # /… form for the bash PATH
stub_wa() { # $1 exit code of the stub when called with arguments
  rm -f "$WA"/python3*
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) printf '@exit /b %s\r\n' "$1" > "$WA/python3.bat" ;;
    *) printf '#!/bin/sh\nexit %s\n' "$1" > "$WA/python3"; chmod +x "$WA/python3" ;;
  esac
}
pyg() { (cd "$T/vuoto" && PATH=${PYG_PATH:-$WAU} MAAT_CONFIG=$T/gen/.claude/maat.json PROJECT_ROOT=$T/gen "$FIC_PY" "${MCX:-$MC}" python g); }
caso_stub() { stub_wa 9009; pyg > "$T/out" 2>&1; [ $? = 3 ] && ! grep -q WindowsApps "$T/out"; }
check "python dal PATH: stub sotto WindowsApps che esce 9009 -> scartato (exit 3)" 'caso_stub'
stub_wa 0; o=$(pyg 2> "$T/out"); rc=$?
check "python dal PATH: sotto WindowsApps ma risponde a -c \"import sys\" -> tenuto" '[ $rc = 0 ] && case "$o" in */WindowsApps/python3*) true ;; *) false ;; esac'
# the stub is the FIRST python3 on PATH, a real python3 comes after (outside WindowsApps: no probe) -> the second
AL="$T/wa/altro"; mkdir -p "$AL"; ALU=$(cd "$AL" && pwd)
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) printf '@exit /b 0\r\n' > "$AL/python3.bat" ;;
  *) printf '#!/bin/sh\nexit 0\n' > "$AL/python3"; chmod +x "$AL/python3" ;;
esac
caso_dopo() { local o rc; stub_wa 9009; o=$(PYG_PATH="$WAU:$ALU" pyg 2> "$T/out"); rc=$?
  [ $rc = 0 ] && case "$o" in */wa/altro/python3*) true ;; *) false ;; esac; }
check "python dal PATH: stub sotto WindowsApps per primo, python3 vero dopo -> preso il secondo" 'caso_dopo'

# --- 8. bash interface: lib/maat-conf.sh ------------------------------------------------------------------------------
cp "$MIN" "$T/conf.json"
(
  export MAAT_CONFIG=$T/conf.json
  . "$HERE/lib/maat-conf.sh"
  maat_conf_carica || exit 11
  mv "$T/conf.json" "$T/conf.via"                     # after loading, the file is not reread
  [ "$(maat_conf moduli.0.regola_test)" = accanto ] || exit 12
  [ "$(maat_conf gate.full)" = "test controlli lint build" ] || exit 13
  maat_conf guardia.sonde 2>/dev/null; [ $? = 3 ] || exit 14
  [ "$(maat_conf guardia.sonde --default x)" = x ] || exit 15
  mv "$T/conf.via" "$T/conf.json"
  [ "$(maat_modulo_di README.md)" = "app radice" ] || exit 16
  [ "$(PROJECT_ROOT=$T maat_comando app test --test x.test.ts)" = "$(printf '.\nnpm test -- %s' "'x.test.ts'")" ] || exit 17
) > "$T/out" 2>&1
check "maat-conf.sh: maat_conf con cache per processo, maat_modulo_di, maat_comando" '[ $? = 0 ]'

# --- 8b. copia (pk04b-1): the command test-fast.sh runs INSIDE the mirror copy -----------------------------------------
# Expected: vitest-fast.sh:219-234 and 293 from before pk04b-1 (cwd <copy>/apps/admin, CI=true, cache at the root of the
# copy, lint-baseline.mjs -> npm run -s lint; messages from the root of the file's package).
CP="$T/copia"; mkdir -p "$CP/apps/admin" "$CP/packages/ui"
cc() { MAAT_CONFIG=$SS "$FIC_PY" "${MCX:-$MC}" comando-copia fe "$@" --copia "$CP" 2>&1; }
check "copia-modulo: l'unico modulo con copia, una riga per campo" \
  '[ "$(MAAT_CONFIG=$SS mc copia-modulo | tr "\n" "|")" = "fe|modules/app/apps/admin|modules/app|true|npx nuxi prepare|" ]'
check "copia.test: dalla radice nella copia, {test} relativo alla radice" \
  '[ "$(cc test --test apps/admin/tests/a.test.ts)" = "$(riga "$CP/apps/admin" "CI=true npx vitest run '"'"'tests/a.test.ts'"'"'")" ]'
caso_alt() { [ "$(MCX=$1 cc lint --file apps/admin/u/x.ts)" = "$(riga "$CP/apps/admin" "CI=true npx eslint --quiet 'u/x.ts'")" ]; }
check "copia.lint senza lint-baseline.mjs: seconda alternativa (npx eslint --quiet)" 'caso_alt "$MC"'
check "copia.lint con --cache: {cache?--cache --cache-location } valorizzato" \
  '[ "$(cc lint --file apps/admin/u/x.ts --cache "$CP/.fic-eslintcache-apps-admin" | tail -1)" = "CI=true npx eslint --cache --cache-location '"'"'$CP/.fic-eslintcache-apps-admin'"'"' --quiet '"'"'u/x.ts'"'"'" ]'
: > "$CP/apps/admin/lint-baseline.mjs"
check "copia.lint con lint-baseline.mjs nella copia: prima alternativa (npm run -s lint)" \
  '[ "$(cc lint --file apps/admin/u/x.ts)" = "$(riga "$CP/apps/admin" "CI=true npm run -s lint -- '"'"'u/x.ts'"'"'")" ]'
rm "$CP/apps/admin/lint-baseline.mjs"
check "copia.lint_messaggi: dalla radice del pacchetto (--pacchetto), file relativi a quella" \
  '[ "$(cc lint_messaggi --pacchetto packages/ui --file packages/ui/i.ts)" = "$(riga "$CP/packages/ui" "CI=true npx eslint --format compact --quiet '"'"'i.ts'"'"'")" ]'
cc test --test packages/ui/x.test.ts > "$T/out"; rc=$?
check "copia: file fuori dalla cartella del comando -> exit 64" '[ $rc = 64 ]'
MAAT_CONFIG=$SS MAAT_MODULO=be mc copia-modulo > "$T/out" 2>&1; rc=$?
check "copia-modulo: MAAT_MODULO di un modulo senza copia -> exit 2" '[ $rc = 2 ] && grep -q "non dichiara copia" "$T/out"'
"$FIC_PY" -c 'import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8")); m = dict(c["moduli"][0]); m["nome"] = "fe2"; m["radice"] = "modules/app/packages/ui"
c["moduli"].append(m); json.dump(c, open(sys.argv[2], "w", encoding="utf-8"))' "$SS" "$T/due.json"
MAAT_CONFIG=$T/due.json mc copia-modulo > "$T/out" 2>&1; rc=$?
check "copia-modulo: due moduli con copia senza MAAT_MODULO -> exit 64" '[ $rc = 64 ] && grep -q "moduli con copia: imposta MAAT_MODULO" "$T/out"'
check "  con MAAT_MODULO=fe2 -> fe2" '[ "$(MAAT_CONFIG=$T/due.json MAAT_MODULO=fe2 mc copia-modulo | head -2 | tr "\n" "|")" = "fe2|modules/app/packages/ui|" ]'

# --- 8c. required gates, selected tests, chiave entries, python (pk04b-1: gates.sh and finalize.sh) -------------------
gr() { MAAT_CONFIG=${GRC:-$SS} "$FIC_PY" "${MCX:-$MC}" gate-richiesti "$@" 2>&1 | tr '\t' ' ' | paste -sd '|' -; }
caso_ordine() { [ "$(MCX=$1 gr std)" = "tests-be be test|tests-fe fe test" ]; }
check "gate-richiesti std (nuxt-fastapi): tests-be, tests-fe, per etichetta" 'caso_ordine "$MC"'
check "gate-richiesti full: + lint e build senza suffisso (un solo modulo li dichiara)" '[ "$(gr full)" = "tests-be be test|tests-fe fe test|lint fe lint|build fe build" ]'
check "gate-richiesti legacy = std" '[ "$(gr legacy)" = "$(gr std)" ]'
check "gate-richiesti con due moduli che dichiarano lint e build: lint-<modulo>, build-<modulo>" \
  '[ "$(GRC=$T/due.json gr full | tr "|" "\n" | grep -E "^(lint|build)" | paste -sd "|" -)" = "lint-fe fe lint|lint-fe2 fe2 lint|build-fe fe build|build-fe2 fe2 build" ]'
check "gate-richiesti bash-node min: controlli a ogni livello, tests solo dei moduli con comando di test" \
  '[ "$(GRC=$DO gr min)" = "tests-agenti agenti test|tests-claude claude test|tests-console console test|controlli-agenti agenti controlli|controlli-claude claude controlli|controlli-console console controlli|controlli-script script controlli" ]'
check "  un file sotto la radice di un modulo senza comando di test aggiunge tests-<modulo> (NOT RUN in gates.sh)" \
  'GRC=$DO gr min --file deploy.sh | tr "|" "\n" | grep -qx "tests-script script test"'
MAAT_CONFIG=$SS mc gate-richiesti boh > "$T/out" 2>&1; rc=$?
check "gate-richiesti: livello sconosciuto -> exit 64" '[ $rc = 64 ]'
TD=$T/td; ADMT=$TD/modules/app/apps/admin; APIT=$TD/modules/api
mkdir -p "$ADMT/utils" "$ADMT/components/x" "$ADMT/altrove/deep" "$ADMT/node_modules/p" "$APIT/app/routers" "$APIT/tests/routers"
: > "$ADMT/utils/g.ts"; : > "$ADMT/utils/g.test.ts"; : > "$ADMT/components/x/Solo.vue"; : > "$ADMT/components/x/Riga.vue"
: > "$ADMT/altrove/deep/Riga.test.ts"; : > "$ADMT/node_modules/p/Riga.test.ts"
: > "$APIT/app/routers/goals.py"; : > "$APIT/tests/routers/test_goals.py"; : > "$APIT/tests/test_goals_extra.py"; : > "$APIT/tests/test_d.py"
td() { MAAT_CONFIG=$SS PROJECT_ROOT=$TD mc test-di "$@" 2>&1 | paste -sd '|' -; }
check "test-di accanto: il test con lo stesso nome nella cartella del sorgente" '[ "$(td fe --file modules/app/apps/admin/utils/g.ts)" = modules/app/apps/admin/utils/g.test.ts ]'
check "test-di accanto: altrimenti ovunque sotto la radice, node_modules escluso" '[ "$(td fe --file modules/app/apps/admin/components/x/Riga.vue)" = modules/app/apps/admin/altrove/deep/Riga.test.ts ]'
check "test-di accanto: un .vue senza test -> nessuno" '[ -z "$(td fe --file modules/app/apps/admin/components/x/Solo.vue)" ]'
check "test-di specchio: app/**/{m}.py -> tests/**/test_{m}*.py, ordinati" '[ "$(td be --file modules/api/app/routers/goals.py)" = "modules/api/tests/routers/test_goals.py|modules/api/tests/test_goals_extra.py" ]'
check "test-di specchio: un test toccato e' selezionato se esiste" '[ "$(td be --file modules/api/tests/test_d.py --file modules/api/tests/test_sparito.py)" = modules/api/tests/test_d.py ]'
check "chiave: le voci dell'esempio (etichetta, tipo, cartella)" \
  '[ "$(MAAT_CONFIG=$SS PROJECT_ROOT=$TD mc chiave fe | cut -f1-3 | tr "\t" " " | paste -sd "|" -)" = "vitest comando modules/app|eslint comando modules/app|deps comando modules/app|node_modules file modules/app|tsconfig file modules/app/apps/admin" ]'
check "chiave: {python} espanso con la precedenza (FIC_GATES_VENV_PY)" \
  'MAAT_CONFIG=$SS PROJECT_ROOT=$TD FIC_GATES_VENV_PY=$T/py.exe mc chiave be | cut -f4 | grep -qF "$T/py.exe -m pip freeze"'
check "python: l'interprete del modulo che usa {python}" '[ "$(MAAT_CONFIG=$SS PROJECT_ROOT=$TD FIC_GATES_VENV_PY=$T/py.exe mc python be)" = "$T/py.exe" ]'
MAAT_CONFIG=$SS PROJECT_ROOT=$TD mc python fe > "$T/out" 2>&1; rc=$?
check "python: un modulo che non usa {python} -> exit 2" '[ $rc = 2 ]'
check "python lista: nessuna alternativa esiste -> l'ultimo percorso" '[ "$(MAAT_CONFIG=$SS PROJECT_ROOT=$TD mc python be)" = "$TD/modules/api/.venv/bin/python" ]'
mkdir -p "$APIT/.venv312/bin" "$APIT/.venv/bin"; : > "$APIT/.venv312/bin/python"; : > "$APIT/.venv/bin/python"
check "python lista: vince la prima alternativa che esiste" '[ "$(MAAT_CONFIG=$SS PROJECT_ROOT=$TD mc python be)" = "$TD/modules/api/.venv312/bin/python" ]'
rm -rf "$APIT/.venv312"
check "python lista: poi la successiva" '[ "$(MAAT_CONFIG=$SS PROJECT_ROOT=$TD mc python be)" = "$TD/modules/api/.venv/bin/python" ]'
rm -rf "$APIT/.venv"

# --- 8b. generati (from the reference project): generated files that implement/fix may regenerate -------------
GR='modules/api/docs/operation-log.md | modules/api | PYTHONPATH=. .venv/bin/python tests/test_operation_log_docs.py | modules/api/tests/test_operation_log_docs.py'
check "generati: la voce dell'esempio, con l'ambiente del modulo della cartella" '[ "$(MAAT_CONFIG=$SS mc generati 2>"$T/out")" = "$GR | wsl" ]'
TG=$T/gen; mkdir -p "$TG/modules/api/docs" "$TG/modules/api/tests"
: > "$TG/modules/api/docs/operation-log.md"
printf '%s\n' 'DOC = "docs/operation-log.md"' > "$TG/modules/api/tests/test_operation_log_docs.py"
check "generati --verifica: la voce dell'esempio e' eseguibile sul progetto" \
  'MAAT_CONFIG=$SS PROJECT_ROOT=$TG mc generati --verifica > "$T/out" 2>&1 && grep -qx "generati: 1 voci verificate" "$T/out"'
MAAT_CONFIG=$MIN mc generati > "$T/out" 2>&1; rc=$?
check "generati: nessuna voce -> nessuna riga, exit 0" '[ $rc = 0 ] && [ ! -s "$T/out" ]'
check "generati: cartella fuori da ogni modulo -> ambiente nativo" \
  '[ "$(MAAT_CONFIG=$SS mc generati | cut -d"|" -f5)" = " wsl" ] && printf "%s\n" "{\"versione_schema\":1,\"moduli\":[{\"nome\":\"a\",\"radice\":\"src\",\"ambiente\":\"wsl\"}],\"generati\":[{\"percorso\":\"d/x.md\",\"cartella\":\"d\",\"comando\":\"gen.sh\",\"test\":\"t/x.test\"}]}" > "$T/gn.json" && [ "$(MAAT_CONFIG=$T/gn.json mc generati)" = "d/x.md | d | gen.sh | t/x.test | nativo" ]'
# counterproofs on a broken entry: every --verifica check turns red
GJ='{"percorso":"modules/api/docs/operation-log.md","cartella":"modules/api","comando":"PYTHONPATH=. .venv/bin/python tests/test_operation_log_docs.py","test":"modules/api/tests/test_operation_log_docs.py"}'
gv() { # <description> <json entry> <expected text>
  printf '%s\n' "{\"versione_schema\":1,\"moduli\":[{\"nome\":\"be\",\"radice\":\"modules/api\",\"ambiente\":\"wsl\"}],\"generati\":[$2]}" > "$T/gv.json"
  MAAT_CONFIG=$T/gv.json PROJECT_ROOT=$TG mc generati --verifica > "$T/out" 2>&1; local rc=$?
  GV_TESTO=$3; check "generati --verifica: $1" '[ $rc = 1 ] && grep -qF -- "$GV_TESTO" "$T/out"'
}
gv "generato assente" "${GJ/operation-log.md\"/operation-log-NO.md\"}" "ERRORE: generati.0: generato assente: modules/api/docs/operation-log-NO.md"
gv "cartella assente" "${GJ/\"cartella\":\"modules\/api\"/\"cartella\":\"modules/apiNO\"}" "ERRORE: generati.0: cartella assente: modules/apiNO"
gv "script del comando assente" "${GJ/tests\/test_operation_log_docs.py\",\"test\"/tests/test_NO.py\",\"test\"}" "ERRORE: generati.0: script del comando assente: modules/api/tests/test_NO.py"
gv "test assente" "${GJ/\"test\":\"modules\/api\/tests\/test_operation_log_docs.py\"/\"test\":\"modules/api/tests/test_NO.py\"}" "ERRORE: generati.0: test assente: modules/api/tests/test_NO.py"
: > "$TG/modules/api/tests/conftest.py"
gv "il test non nomina il generato" "${GJ/\"test\":\"modules\/api\/tests\/test_operation_log_docs.py\"/\"test\":\"modules/api/tests/conftest.py\"}" "non nomina operation-log.md"
gv "comando senza script" "${GJ/PYTHONPATH=. .venv\/bin\/python tests\/test_operation_log_docs.py/make docs}" "il comando non nomina uno script"
ko "generati: voce a tre campi (required)" "{\"versione_schema\":1,\"moduli\":[$M],\"generati\":[{\"percorso\":\"a.md\",\"cartella\":\".\",\"comando\":\"g.sh\"}]}" generati.0.test "obbligatoria"
ko "generati: | in un campo (pattern)" "{\"versione_schema\":1,\"moduli\":[$M],\"generati\":[{\"percorso\":\"a|b.md\",\"cartella\":\".\",\"comando\":\"g.sh\",\"test\":\"t.py\"}]}" generati.0.percorso "non rispetta la forma"
caso_s9() { printf '%s\n' "{\"versione_schema\":1,\"moduli\":[$M],\"generati\":[{\"percorso\":\"tests/x_golden.json\",\"cartella\":\".\",\"comando\":\"g.sh\",\"test\":\"tests/test_x_golden.py\"}]}" > "$T/ks9.json"
  "$FIC_PY" "$1" valida "$T/ks9.json" > "$T/out" 2>&1; [ $? = 1 ] && grep -qF ": generati.0.percorso: golden, snapshot e base del lint non sono generati da rigenerare (S9)" "$T/out"; }
check "non valido: un golden fra i generati (S9)" 'caso_s9 "$MC"'
ko "uno snapshot fra i generati (S9)" "{\"versione_schema\":1,\"moduli\":[$M],\"generati\":[{\"percorso\":\"a.md\",\"cartella\":\".\",\"comando\":\"g.sh\",\"test\":\"__snapshots__/a.snap\"}]}" generati.0.test "(S9)"
ko "la base del lint fra i generati (S9)" "{\"versione_schema\":1,\"moduli\":[$M],\"generati\":[{\"percorso\":\"web/eslint-baseline.tsv\",\"cartella\":\"web\",\"comando\":\"lint-baseline.mjs\",\"test\":\"t.py\"}]}" generati.0.percorso "(S9)"
# the workers that launch plan-implementer (implement, fix) pass it the list: without it, the fix stops on
# `file non nominato dal piano`
for w in implement fix; do
  check "workers/$w.md passa maat-config.py generati all'implementer" 'grep -q "maat-config.py\" generati" "$PLUGIN/skills/full-implementation-cycle/workers/$w.md"'
done

# --- 8d. pk04b-2: preparati => preparazione (S10); importable functions equal to the commands ---------------------------
caso_s10() { printf '%s\n' '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","preparati":[".nuxt/tsconfig.json"]}]}' > "$T/ks10.json"
  "$FIC_PY" "$1" valida "$T/ks10.json" > "$T/out" 2>&1; [ $? = 1 ] && grep -qF ": moduli.0.preparati: preparati chiede preparazione, il comando che li scrive (S10)" "$T/out"; }
check "non valido: preparati senza preparazione (S10)" 'caso_s10 "$MC"'
printf '%s\n' '{"versione_schema":1,"moduli":[{"nome":"a","radice":".","preparati":[".nuxt/tsconfig.json"],"preparazione":"npx nuxi prepare"}]}' > "$T/s10ok.json"
mc valida "$T/s10ok.json" > "$T/out" 2>&1; check "preparati con preparazione: valido" '[ $? = 0 ]'
imp() { # <reader> -> the outputs of the imported functions (MAAT_CONFIG_PY like plan-check.sh), one per line
  MAAT_CONFIG=$SS PROJECT_ROOT=$TD "$FIC_PY" -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("maat_config", sys.argv[1]); mc = importlib.util.module_from_spec(s); s.loader.exec_module(mc)
cfg, _p = mc.carica(); r = mc.risolto(cfg)
for f in ("modules/app/apps/admin/x.ts", "modules/app/packages/ui/b.ts", "modules/api/app/a.py", "README.md"):
    print(mc.modulo_di(r, f))
for c, l in mc.comando(cfg, "fe", "test", test=["modules/app/apps/admin/tests/a.test.ts"], root=sys.argv[2]):
    print(c); print(l)
try:
    mc.comando(cfg, "be", "lint", root=sys.argv[2])
except mc.Uscita as u:
    print("uscita %d" % u.codice)
' "$1" "$TD" 2>&1 | tr -d '\r'; }
IMP=$(printf '%s\n' "('fe', 'radice')" "('fe', 'pacchetti')" "('be', 'radice')" None)
IMP=$IMP$'\n'$(MAAT_CONFIG=$SS PROJECT_ROOT=$TD MAAT_ROOT=$PLUGIN mc comando fe test --test modules/app/apps/admin/tests/a.test.ts)$'\n'"uscita 2"
check "importato: modulo_di e comando danno quello che danno modulo-di e comando (CLI)" '[ "$(MAAT_ROOT=$PLUGIN imp "$MC")" = "$IMP" ]'

# --- 9. mutation counterproofs (the mutation must turn the case red) ----------------------------------------------------
mutante() { # <name> <sed expression> -> path of the mutated reader; empty if the sed changes nothing
  local d="$T/mut/$1"
  mkdir -p "$d/scripts"; cp -r "$PLUGIN/schemas" "$PLUGIN/profiles" "$d/"
  sed -e "$2" "$MC" > "$d/scripts/maat-config.py"
  cmp -s "$MC" "$d/scripts/maat-config.py" || printf '%s' "$d/scripts/maat-config.py"
}
m=$(mutante ap 's/elif ap is False:/elif False:/')
check "controprova: senza additionalProperties false la chiave sconosciuta passa -> rosso" '[ -n "$m" ] && ! caso_sconosciuta "$m"'
m=$(mutante s1 's/if m.get("regola_test") == "specchio" and "specchio" not in m:/if False:/')
check "controprova: S1 disattivato -> rosso" '[ -n "$m" ] && ! caso_s1 "$m"'
m=$(mutante s8 's/if m.get("regola_test") == "nessuna" and "test" in m.get("comandi", {}):/if False:/')
check "controprova: S8 disattivato -> rosso" '[ -n "$m" ] && ! caso_s8 "$m"'
m=$(mutante s9 's/if NON_GENERATI.search(g.get(k, "")):/if False:/')
check "controprova: S9 disattivato -> un golden fra i generati passa, rosso" '[ -n "$m" ] && ! caso_s9 "$m"'
m=$(mutante s10 's/if m.get("preparati") and not m.get("preparazione"):/if False:/')
check "controprova: S10 disattivato -> preparati senza preparazione passa, rosso" '[ -n "$m" ] && ! caso_s10 "$m"'
m=$(mutante moddi 's/^    return instrada(r, percorso)$/    return None/')
check "controprova: modulo_di importato che non instrada -> diverso dalla CLI, rosso" '[ -n "$m" ] && [ "$(MAAT_ROOT=$PLUGIN imp "$m")" != "$IMP" ]'
m=$(mutante corta 's/key=lambda c: -c\[0\]/key=lambda c: c[0]/g')
check "controprova: radice più corta -> a/b/x dà a, rosso" '[ -n "$m" ] && ! caso_annidate "$m"'
m=$(mutante pacchetti 's/if pacchetti:/if False:/')
check "controprova: senza ripiego su radice_pacchetti -> exit 2, rosso" '[ -n "$m" ] && ! caso_pacchetti "$m"'
m=$(mutante base 's/if v is None or v == "" or v == \[\]:/if False:/')
VB="--base ''"
check "controprova: {base?--base } come segnaposto normale -> compare --base vuoto, rosso" \
  '[ -n "$m" ] && ! caso_lint_senza "$m" && MCX=$m cmd fe lint --file modules/app/apps/admin/x.vue | grep -qF -- "$VB"'

m=$(mutante ordine 's/        for riga in sorted(g):/        for riga in g:/')
check "controprova: gate-richiesti nell'ordine dei moduli -> tests-fe prima di tests-be, rosso" '[ -n "$m" ] && ! caso_ordine "$m"'
m=$(mutante alt 's/if a.get("se_esiste") and not os.path.exists(/if a.get("se_esiste") and os.path.exists(/')
check "controprova: se_esiste rovesciato -> senza lint-baseline.mjs vince npm run, rosso" '[ -n "$m" ] && ! caso_alt "$m"'
m=$(mutante nativo 's/^        nativo(out)$/        pass/')
check "controprova: componi --nativo senza la trasformazione -> resta wsl con copia, rosso" '[ -n "$m" ] && ! caso_nativo "$m"'
m=$(mutante nativo-amb 's/            m\["ambiente"\] = "nativo"/            pass/')
check "controprova: --nativo che lascia ambiente wsl -> rosso" '[ -n "$m" ] && ! caso_nativo "$m"'
m=$(mutante nativo-lb 's/scelta = next((a for a in alt if applicabile(a, m)), None)/scelta = next((a for a in alt if not a.get("se_esiste")), None)/')
check "controprova: --nativo che scarta ogni alternativa con se_esiste -> resta eslint, rosso" '[ -n "$m" ] && ! caso_nativo_lb "$m"'
m=$(mutante nativo-lb-sempre 's/        if not a.get("se_esiste"):$/        if True:/')
check "controprova: --nativo che non guarda se_esiste -> senza il file vince npm run, rosso" '[ -n "$m" ] && ! caso_nativo "$m"'
m=$(mutante wa 's/if i == 2 and not python_risponde(w):/if False:/')
check "controprova: senza la sonda sotto WindowsApps lo stub dello Store e' tenuto, rosso" '[ -n "$m" ] && ! MCX=$m caso_stub'
m=$(mutante wa-dopo 's/w = python_dal_path(v, w)   #/w = None   #/')
check "controprova: senza la ricerca negli altri elementi del PATH il python3 vero dopo lo stub non si trova, rosso" '[ -n "$m" ] && ! MCX=$m caso_dopo'

echo "maat-config.test.sh: $pass ok, $fail falliti"
[ "$fail" = 0 ]
