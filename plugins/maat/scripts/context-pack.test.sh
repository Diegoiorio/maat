#!/usr/bin/env bash
# context-pack.test.sh — context-pack.sh on a synthetic repository (temporary directory): existing and
# missing files, signatures of a .vue file and of a router, Pydantic models, tests that mention files, data-test and strings,
# DB section with VPN down (simulated: no contact with the host) and up, writes only in <run-dir>,
# regeneration by fingerprint; mutation counterproof run here, on a mutated copy of the script.
#   bash script/fic/context-pack.test.sh
#   CP=/path/variant.sh bash script/fic/context-pack.test.sh   # the suite on a variant
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)   # plugin root
CP=${CP:-$HERE/context-pack.sh}
pass=0 fail=0
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
# the mutants written in $W include the resolver next to themselves ($W/lib) and find the plugin from MAAT_ROOT
mkdir -p "$W/lib" && cp "$HERE/lib/maat-paths.sh" "$W/lib/"; export MAAT_ROOT=$ROOT
ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/    /'; }

# --- synthetic repository ---
R="$W/repo"; A="$R/modules/app/apps/admin"; API="$R/modules/api"
mkdir -p "$A/components/goals" "$A/store" "$API/app/routers" "$API/app/models" "$API/tests" \
         "$R/modules/db/prisma" "$R/.claude/.ai-workflow" "$W/fake"
cat > "$A/components/goals/Section.vue" <<'EOF'
<script setup lang="ts">
const props = defineProps<{
  year: number;
  readonly?: boolean;
  items: { id: string; amount: number }[];
}>();
const emit = defineEmits<{ (e: 'save', v: number): void; (e: 'close'): void }>();
</script>
<template>
  <button data-test="goals-save" @click="emit('save', props.year)">Salva obiettivi</button>
  <span data-test="goals-orfano" />
  <span v-if="false" data-test="goals-orfano" />
</template>
EOF
cat > "$A/components/goals/Section.test.ts" <<'EOF'
import Section from './Section.vue'
it('salva', () => { wrapper.find('[data-test="goals-save"]'); expect(text).toContain('Salva obiettivi') })
EOF
cat > "$A/store/goals.ts" <<'EOF'
export const useGoalsStore = defineStore('goals', () => {})
export async function loadPlan(year: number): Promise<void> {
}
function interna() {}
EOF
cat > "$API/app/routers/goals.py" <<'EOF'
from fastapi import APIRouter
from app.models.goals import GoalPlanView, GoalChangeResult

router = APIRouter(prefix="/goals", tags=["goals"])


@router.get("/plan", response_model=GoalPlanView, summary="Piano")
async def get_plan(year: int):
    return None


@router.patch(
    "/plan/{year}",
    response_model=GoalChangeResult,
)
def patch_plan(year: int, body: GoalPlanView):
    return None
EOF
cat > "$API/app/models/goals.py" <<'EOF'
from pydantic import BaseModel


class _Req(BaseModel):
    model_config = {}


class GoalPlanView(BaseModel):
    year: int
    items: list


class GoalChangeResult(_Req):
    ok: bool
EOF
printf 'from app.routers.goals import router\n' > "$API/tests/test_goals_router.py"
cat > "$R/modules/db/prisma/schema.prisma" <<'EOF'
model goal_plan {
  id String @id
}

model UserGoal {
  id String @id
  @@map("user_goal")
}
EOF
# pk04b-2: the DB schema comes from `contesto` in maat.json: the nuxt-fastapi example (file, tables, command)
cp "$ROOT/examples/nuxt-fastapi.maat.json" "$R/.claude/maat.json"
S="$R/.claude/.ai-workflow/spec-prova.md"
cat > "$S" <<'EOF'
# Prova

Modifica `modules/app/apps/admin/components/goals/Section.vue` e `store/goals.ts`; il router
`modules/api/app/routers/goals.py:12` resta; il servizio `modules/api/app/services/inesistente_service.py` va creato.
Vedi https://example.com/guida/esterna.md e `useGoalsStore`, `nonEsisteSimbolo()`, `GoalsSection`.
Di nuovo `components/goals/Section.vue`, citato in un altro modo.
Il bottone data-test="goals-save" mostra «Salva obiettivi»; «Testo che nessuno cita».
Tabelle: `goal_plan` e `user_goal.amount`.
EOF
cat > "$W/fake/sql-down.sh" <<'EOF'
echo "$@" > "${0%.sh}.args"
echo "ERRORE: tunnel VPN non 'Connected' dentro WSL — l'host DEV non è raggiungibile." >&2
exit 3
EOF
cat > "$W/fake/sql-up.sh" <<'EOF'
echo "$@" > "${0%.sh}.args"
printf '        ?column?\n------------------------\n @@goal_plan|id text, year int4, note varchar?\n(1 row)\n'
EOF

RUN="$R/.claude/.ai-workflow/spec-prova.run"; PACK="$RUN/context-pack.md"
tree_sum() { find "$R" -type f ! -path "$RUN/*" -exec cksum {} + | sort; }
gen() { # $1 script, $2 fake sql, other arguments -> $out, $rc
  local s=$1 f=$2; shift 2
  out=$(CONTEXT_PACK_ROOT="$R" CONTEXT_PACK_HARNESS="$ROOT" CONTEXT_PACK_SQL="$W/fake/$f.sh" bash "$s" "$S" "$@" 2>&1); rc=$?
}
has() { grep -qF -- "$1" "$PACK" && ok || ko "pacchetto: manca «$1»" "$(cat "$PACK" 2>/dev/null)"; }
hasx() { grep -qx -- "$1" "$PACK" && ok || ko "pacchetto: manca la riga «$1»" "$(cat "$PACK" 2>/dev/null)"; }

# --- VPN down (simulated): exit 0, DB section «assente», the rest goes on ---
real_before=$(git -C "$ROOT" status --porcelain)
before=$(tree_sum)
gen "$CP" sql-down
[ $rc -eq 0 ] && ok || ko "uscita con VPN giu': $rc" "$out"
[ -f "$PACK" ] && ok || ko "pacchetto non scritto" "$out"
DOWN="ERRORE: tunnel VPN non 'Connected' dentro WSL — l'host DEV non è raggiungibile."
printf '%s\n' "$out" | grep -qF "file nominati 4 (1 inesistenti)" && printf '%s\n' "$out" | grep -q "^context-pack: .*DB: assente (comando dello schema uscito 3: $DOWN)$" &&
  ok || ko "riga di sintesi" "$out"
# the reason is the first line of the command output, not a table of codes in the harness (pk04b-2)
has "- **assente** — comando dello schema uscito 3: $DOWN. Tabelle nominate: goal_plan, user_goal"
[ "$(cat "$W/fake/sql-down.args" 2>/dev/null | cut -d' ' -f1)" = "--read" ] && ok || ko "dev-sql chiamato senza --read"

# existing / missing files
hasx "- esiste: modules/app/apps/admin/components/goals/Section.vue"
hasx "- esiste: modules/app/apps/admin/store/goals.ts (citato come \`store/goals.ts\`)"
hasx "- esiste: modules/api/app/routers/goals.py"
hasx "- NON ESISTE: modules/api/app/services/inesistente_service.py"
grep -q 'example\.com\|esterna\.md' "$PACK" && ko "un URL trattato come file" || ok
grep -q 'spec-prova\.md (' "$PACK" && ko "lo spec elenca se stesso" || ok
n=$(sed -n '/^## File nominati/,/^## /p' "$PACK" | grep -c 'goals/Section\.vue')
[ "$n" = 1 ] && ok || ko "stesso file citato in due modi: $n righe (attesa 1)" "$(cat "$PACK")"

# signatures of the .vue file, the router, the models; exports of the .ts file
hasx "- props: year, readonly, items · emits: save, close"
hasx "- GET /goals/plan → get_plan · response_model GoalPlanView (r. 7)"
hasx "- PATCH /goals/plan/{year} → patch_plan · response_model GoalChangeResult (r. 12)"
has "- modello GoalPlanView (modules/api/app/models/goals.py:8): year, items"
has "- modello GoalChangeResult (modules/api/app/models/goals.py:13): ok"
has "- export async function loadPlan(year: number): Promise<void> (r. 2)"
grep -q 'interna' "$PACK" && ko "una funzione non esportata tra le firme" || ok

# tests that mention files, data-test, strings
hasx "- test: modules/app/apps/admin/components/goals/Section.test.ts"
hasx "- test: modules/api/tests/test_goals_router.py"
hasx "- \`goals-save\` (spec) → modules/app/apps/admin/components/goals/Section.test.ts"
hasx "- nei .vue nominati altri 1 data-test, 0 citati da test; non citati: \`goals-orfano\`"
hasx "- «Salva obiettivi» → modules/app/apps/admin/components/goals/Section.test.ts"
grep -q 'Testo che nessuno cita' "$PACK" && ko "stringa non citata elencata" || ok

# symbols
has "- \`useGoalsStore\` → modules/app/apps/admin/store/goals.ts:1"
hasx "- \`nonEsisteSimbolo\` → non trovato"
hasx "- \`GoalsSection\` → componente modules/app/apps/admin/components/goals/Section.vue"

# header: spec fingerprint, orientation, cap
fp=$(sha256sum "$S" | cut -c1-16)
grep -q "^Data: .* · Commit: n/d · Impronta spec: sha256:$fp · Stima: ~[0-9]* token$" "$PACK" && ok || ko "intestazione" "$(head -8 "$PACK")"
has "il codice vince sul pacchetto"
t=$(sed -n 's/.*Stima: ~\([0-9]*\) token$/\1/p' "$PACK"); [ -n "$t" ] && [ "$t" -le 5000 ] && ok || ko "stima token «$t»"

# writes only in <run-dir>
[ "$before" = "$(tree_sum)" ] && ok || ko "scritto fuori da <run-dir>" "$(diff <(echo "$before") <(tree_sum))"
[ "$(ls -A "$RUN")" = "context-pack.md" ] && ok || ko "<run-dir> contiene altro: $(ls -A "$RUN" | tr '\n' ' ')"
[ "$real_before" = "$(git -C "$ROOT" status --porcelain)" ] && ok || ko "il repository del harness e' cambiato"

# --- same fingerprint: unchanged, the file is not touched; spec changed: regenerated ---
sum1=$(cksum "$PACK")
gen "$CP" sql-down
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q '^context-pack: invariato (sha256:' && [ "$sum1" = "$(cksum "$PACK")" ] &&
  ok || ko "stessa impronta: atteso «invariato» senza riscrittura (rc=$rc)" "$out"
printf '\nUna riga in piu.\n' >> "$S"
before=$(tree_sum)
gen "$CP" sql-down
fp2=$(sha256sum "$S" | cut -c1-16)
[ $rc -eq 0 ] && grep -q "Impronta spec: sha256:$fp2 " "$PACK" && [ "$fp2" != "$fp" ] && ok ||
  ko "spec cambiato: pacchetto non rigenerato (rc=$rc)" "$out"

# --- tunnel up (simulated): columns; table named but missing from the DB ---
gen "$CP" sql-up --force
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q 'DB: presente$' && ok || ko "DB presente: sintesi (rc=$rc)" "$out"
hasx "- \`goal_plan\`: id text, year int4, note varchar?"
hasx "- \`user_goal\`: non trovata in information_schema"
grep -q "IN ('goal_plan','user_goal')" "$W/fake/sql-up.args" && ok || ko "SQL con le tabelle nominate" "$(cat "$W/fake/sql-up.args")"
[ "$before" = "$(tree_sum)" ] && ok || ko "--force: scritto fuori da <run-dir>"

# --- no table named: dev-sql not called ---
S2="$R/.claude/.ai-workflow/spec-senza-db.md"; printf '# X\n\n`store/goals.ts`\n' > "$S2"
rm -f "$W/fake/sql-down.args"
o=$(CONTEXT_PACK_ROOT="$R" CONTEXT_PACK_HARNESS="$ROOT" CONTEXT_PACK_SQL="$W/fake/sql-down.sh" bash "$CP" "$S2" 2>&1); r=$?
[ $r -eq 0 ] && [ ! -e "$W/fake/sql-down.args" ] && grep -q '^- nessuna tabella nominata' "$R/.claude/.ai-workflow/spec-senza-db.run/context-pack.md" &&
  ok || ko "senza tabelle: dev-sql chiamato o sezione sbagliata (rc=$r)" "$o"

# --- cap: a spec naming many large files is truncated, and the estimate stays within ~5k tokens ---
mkdir -p "$A/utils/big"; S3="$R/.claude/.ai-workflow/spec-grande.md"; printf '# Grande\n\n' > "$S3"
for i in $(seq 1 45); do
  for j in $(seq 1 12); do printf 'export const valoreMoltoLungoNumero%02dDelFile%02d = (argomentoUno: number, argomentoDue: string): string => ""\n' "$j" "$i"; done \
    > "$A/utils/big/modulo-con-un-nome-lungo-$i.ts"
  printf -- '- `modules/app/apps/admin/utils/big/modulo-con-un-nome-lungo-%s.ts`\n' "$i" >> "$S3"
done
o=$(CONTEXT_PACK_ROOT="$R" CONTEXT_PACK_SQL="$W/fake/sql-down.sh" bash "$CP" "$S3" 2>&1); r=$?
P3="$R/.claude/.ai-workflow/spec-grande.run/context-pack.md"
t=$(sed -n 's/.*Stima: ~\([0-9]*\) token$/\1/p' "$P3" 2>/dev/null)
[ $r -eq 0 ] && grep -q '^… TRONCATO al tetto' "$P3" && [ -n "$t" ] && [ "$t" -le 5000 ] && [ "$(wc -c < "$P3")" -le 20500 ] &&
  ok || ko "tetto: atteso troncato entro ~5k token (rc=$r, stima «$t», $(wc -c < "$P3" 2>/dev/null) byte)" "$o"

# --- usage ---
bash "$CP" "$W/non-esiste.md" >/dev/null 2>&1; r=$?; [ $r -eq 2 ] && ok || ko "spec inesistente: uscita attesa 2, ottenuta $r"
bash "$CP" "$S" --boh >/dev/null 2>&1; r=$?; [ $r -eq 2 ] && ok || ko "opzione sconosciuta: uscita attesa 2, ottenuta $r"
O="$W/altra-run"; o=$(CONTEXT_PACK_ROOT="$R" CONTEXT_PACK_SQL="$W/fake/sql-down.sh" bash "$CP" "$S" --run-dir "$O" 2>&1)
[ -f "$O/context-pack.md" ] && ok || ko "--run-dir ignorato" "$o"

# --- pk04b-2: contesto from maat.json ---
# without contesto: the section is omitted with «schema DB non dichiarato», no command run
printf '%s\n' '{"versione_schema":1,"moduli":[{"nome":"tutto","radice":"."}]}' > "$W/senza-contesto.json"
rm -f "$W/fake/sql-down.args"
o=$(MAAT_CONFIG="$W/senza-contesto.json" CONTEXT_PACK_ROOT="$R" CONTEXT_PACK_SQL="$W/fake/sql-down.sh" bash "$CP" "$S" --force 2>&1); r=$?
[ $r -eq 0 ] && printf '%s\n' "$o" | grep -q 'DB: schema DB non dichiarato$' && grep -q 'schema DB non dichiarato' "$PACK" &&
  ! grep -q '^## Colonne DB' "$PACK" && [ ! -e "$W/fake/sql-down.args" ] && ok || ko "senza contesto: «schema DB non dichiarato» (rc=$r)" "$o"
# with the file but without tabelle: no recognisable table, and the section says so
printf '%s\n' '{"versione_schema":1,"moduli":[{"nome":"tutto","radice":"."}],"contesto":{"schema_db_file":"modules/db/prisma/schema.prisma","schema_db_comando":"false"}}' > "$W/senza-tabelle.json"
o=$(MAAT_CONFIG="$W/senza-tabelle.json" CONTEXT_PACK_ROOT="$R" CONTEXT_PACK_SQL="$W/fake/sql-down.sh" bash "$CP" "$S" --force 2>&1); r=$?
[ $r -eq 0 ] && grep -qx -- '- nessuna tabella riconoscibile: contesto.tabelle non dichiarato in maat.json' "$PACK" && [ ! -e "$W/fake/sql-down.args" ] &&
  ok || ko "senza contesto.tabelle: nessuna tabella riconosciuta (rc=$r)" "$o"
# the declared command (without CONTEXT_PACK_SQL) receives the SQL as last argument, from the repository root
cfgcmd() { # $1 file, $2 schema command
  "$FIC_PY" -c 'import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8")); c["contesto"]["schema_db_comando"] = sys.argv[3]
json.dump(c, open(sys.argv[2], "w", encoding="utf-8"))' "$ROOT/examples/nuxt-fastapi.maat.json" "$1" "$2"; }
. "$HERE/python.sh"
printf '%s\n' 'pwd > "${0%.sh}.pwd"; echo "$@" > "${0%.sh}.args"' 'printf "@@goal_plan|id text\n"' > "$W/fake/cmd-up.sh"
cfgcmd "$W/cmd-up.json" "bash $W/fake/cmd-up.sh --read"
o=$(MAAT_CONFIG="$W/cmd-up.json" CONTEXT_PACK_ROOT="$R" bash "$CP" "$S" --force 2>&1); r=$?
[ $r -eq 0 ] && printf '%s\n' "$o" | grep -q 'DB: presente$' && grep -q "^--read SELECT .*IN ('goal_plan','user_goal')" "$W/fake/cmd-up.args" &&
  [ "$(cd "$(cat "$W/fake/cmd-up.pwd")" && pwd)" = "$(cd "$R" && pwd)" ] && ok || ko "comando dello schema dichiarato: SQL come ultimo argomento, dalla radice (rc=$r)" "$o"
# exit other than 0: «comando dello schema uscito N: <first line>»; 124: «timeout»
printf '%s\n' 'echo' 'echo "ERRORE: x" >&2' 'echo "seconda riga"' 'exit 3' > "$W/fake/cmd-x.sh"
cfgcmd "$W/cmd-x.json" "bash $W/fake/cmd-x.sh --read"
caso_x() { o=$(MAAT_CONFIG="$W/cmd-x.json" CONTEXT_PACK_ROOT="$R" bash "$1" "$S" --force 2>&1) &&
  printf '%s\n' "$o" | grep -q 'DB: assente (comando dello schema uscito 3: ERRORE: x)$' &&
  grep -qF -- "- **assente** — comando dello schema uscito 3: ERRORE: x. Tabelle nominate:" "$PACK"; }
caso_x "$CP" && ok || ko "comando che esce 3: motivo = prima riga non vuota della sua uscita" "$o"
printf '%s\n' 'exit 124' > "$W/fake/cmd-to.sh"
cfgcmd "$W/cmd-to.json" "bash $W/fake/cmd-to.sh --read"
o=$(MAAT_CONFIG="$W/cmd-to.json" CONTEXT_PACK_ROOT="$R" bash "$CP" "$S" --force 2>&1)
printf '%s\n' "$o" | grep -q 'DB: assente (timeout)$' && ok || ko "comando che esce 124: «timeout»" "$o"
grep -q 'VPN\|anti-nesting\|dev-sql' "$CP" && ko "context-pack.sh nomina ancora VPN, anti-nesting o dev-sql" || ok
# the schema file counts among the named files by its declared extension (not written in the code)
printf '# Schema\n\n`modules/db/prisma/schema.prisma`\n' > "$R/.claude/.ai-workflow/spec-schema.md"
o=$(CONTEXT_PACK_ROOT="$R" CONTEXT_PACK_SQL="$W/fake/sql-down.sh" bash "$CP" "$R/.claude/.ai-workflow/spec-schema.md" 2>&1)
grep -qx -- "- esiste: modules/db/prisma/schema.prisma" "$R/.claude/.ai-workflow/spec-schema.run/context-pack.md" &&
  ok || ko "schema_db_file nominato dallo spec: tra i file (estensione dalla configurazione)" "$o"
# counterproof: the old table of codes (3 = VPN tunnel) instead of the first line => the «esce 3» case is red
M2="$W/mut-esiti.sh"
sed 's/^            why = "comando dello schema uscito %d%s" % (rc, (": " + first\[:200\]) if first else "")$/            why = {3: "tunnel VPN non connesso"}.get(rc, "uscito %d" % rc)/' "$CP" > "$M2"
if cmp -s "$CP" "$M2"; then ko "controprova esiti: la mutazione non si applica"; elif caso_x "$M2"; then ko "controprova esiti: il caso «esce 3» resta verde col codice cablato"; else ok; fi
rm -rf "$RUN"

# --- pk04b-2: the project's absolute paths (also of one of its worktrees, <name>-…) are removed using the project
#     directory name, not a name written in the code. Counterproof: a hard-coded name => the path stays absolute. ---
SA="$R/.claude/.ai-workflow/spec-assoluto.md"; PA="$R/.claude/.ai-workflow/spec-assoluto.run/context-pack.md"
printf '# Assoluto\n\nIl router `C:/Utenti/x/progetti/repo-fic-prova/modules/api/app/routers/goals.py` resta.\n' > "$SA"
caso_abs() { o=$(CONTEXT_PACK_ROOT="$R" CONTEXT_PACK_SQL="$W/fake/sql-down.sh" bash "$1" "$SA" --force 2>&1) &&
  grep -qx -- "- esiste: modules/api/app/routers/goals.py" "$PA" && ! grep -q "Utenti/x" "$PA"; }
caso_abs "$CP" && ok || ko "percorso assoluto di un worktree del progetto: tolto, resta il percorso relativo" "$o $(cat "$PA" 2>/dev/null)"
M3="$W/mut-abs.sh"; sed 's/^NOME = nome_progetto()$/NOME = "nome-cablato"/' "$CP" > "$M3"
if cmp -s "$CP" "$M3"; then ko "controprova abs: la mutazione non si applica"; elif caso_abs "$M3"; then ko "controprova abs: col nome cablato il caso resta verde"; else ok; fi

# --- counterproof: without the existence check, the «file inesistente» case goes RED ---
[ "$(grep -c '^    exists = q in FILESET$' "$CP")" = 1 ] && ok || ko "controprova: riga del controllo non unica"
M="$W/mut-esistenza.sh"; sed 's/^    exists = q in FILESET$/    exists = True/' "$CP" > "$M"
if cmp -s "$CP" "$M"; then ko "controprova: la mutazione non si applica"; else
  rm -rf "$RUN"; gen "$M" sql-down
  if [ $rc -ne 0 ]; then ko "controprova: il mutante non gira" "$out"
  elif grep -qx -- "- NON ESISTE: modules/api/app/services/inesistente_service.py" "$PACK"; then
    ko "controprova: il caso «file inesistente» resta verde sul mutante"
  else ok; fi
fi

echo "context-pack.test.sh: $pass ok, $fail falliti"
[ $fail -eq 0 ]
