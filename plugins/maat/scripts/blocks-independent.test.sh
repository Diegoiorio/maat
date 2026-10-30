#!/usr/bin/env bash
# blocks-independent.test.sh — tests of blocks-independent.py (harness-pt13): block independence computed
# on a fake repository (synthetic files, .nuxt/components.d.ts and imports.d.ts) and the after-the-fact check.
#   bash script/fic/blocks-independent.test.sh
# Counterproof by mutation: ignoring .nuxt/components.d.ts => the auto-import case becomes «parallelo» (red).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/python.sh" || { echo "interprete Python non trovato" >&2; exit 2; }
BI="$HERE/blocks-independent.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0 n=0
check() { n=$((n + 1)); if eval "$2"; then :; else fail=$((fail + 1)); echo "FAIL: $1"; fi; }

R="$T/repo"; A=modules/app/apps/admin
mkdir -p "$R/$A/.nuxt" "$R/$A/components/goals" "$R/$A/pages" "$R/$A/composables" "$R/modules/api/app/services" "$R/modules/api/app/routers"
# existing component, used WITHOUT import by the page (as in UserPanel.vue:131-134)
printf '<template><div>card</div></template>\n' > "$R/$A/components/goals/Card.vue"
printf '<template>\n  <GoalsCard />\n</template>\n<script setup lang="ts">\nconst x = 1\n</script>\n' > "$R/$A/pages/goals.vue"
printf '<template>\n  <goals-new-thing />\n</template>\n' > "$R/$A/pages/nuovo.vue"
printf '<script setup lang="ts">\nconst s = useGoalsSum()\n</script>\n' > "$R/$A/pages/somma.vue"
printf 'export const useGoalsSum = () => 1\n' > "$R/$A/composables/useGoalsSum.ts"
printf '<template><div/></template>\n' > "$R/$A/pages/altro.vue"
printf 'from app.services.goals import somma\n' > "$R/modules/api/app/routers/goals.py"
printf 'def somma():\n    return 1\n' > "$R/modules/api/app/services/goals.py"
printf 'def x():\n    return 2\n' > "$R/modules/api/app/services/altro.py"
# name registered WITHOUT folder prefix (pathPrefix: false): only components.d.ts knows it
printf '<template><div>scheda</div></template>\n' > "$R/$A/components/goals/Scheda.vue"
printf '<template>\n  <Scheda />\n</template>\n' > "$R/$A/pages/scheda.vue"
# existing component but missing from an old .nuxt: the name derived from the path finds it
printf '<template><div>v</div></template>\n' > "$R/$A/components/goals/Vecchio.vue"
printf '<template>\n  <GoalsVecchio />\n</template>\n' > "$R/$A/pages/vecchio.vue"
cat > "$R/$A/.nuxt/components.d.ts" <<'EOF'
interface _GlobalComponents {
    'Scheda': typeof import("../components/goals/Scheda.vue")['default']
    'GoalsCard': typeof import("../components/goals/Card.vue")['default']
    'LazyGoalsCard': typeof import("../components/goals/Card.vue")['default']
}
export const GoalsCard: typeof import("../components/goals/Card.vue")['default']
EOF
printf "export { useGoalsSum } from '../composables/useGoalsSum';\nexport { useState } from '#app/composables/state';\n" > "$R/$A/.nuxt/imports.d.ts"
# pk04b-2: modules and adapters from maat.json (the nuxt-fastapi example: nuxt-autoimport, fe with preparati in .nuxt/),
# read with the imported reader; the mutants in $T find it via MAAT_CONFIG_PY
mkdir -p "$R/.claude"; cp "$HERE/../examples/nuxt-fastapi.maat.json" "$R/.claude/maat.json"
export MAAT_CONFIG_PY="$HERE/maat-config.py"

proc() { # $1 file, then "blocco …" lines
  local f=$1; shift
  { echo "Plan format: 2"; printf '%s\n' "$@"; } > "$f"
}
bi() { "$FIC_PY" "${BIX:-$BI}" --root "$R" "$@"; }
og() { # $1 reason searched for, then the command: exit 1 (serie, STOP) must not count under pipefail
  local p=$1 o; shift; o=$("$@" 2>/dev/null); printf '%s\n' "$o" | grep -q -- "$p"; }

# 1. shared auto-imported component: B's page uses <GoalsCard> which A writes => dependent
proc "$T/p1" "blocco B1: scrive=$A/components/goals/Card.vue · dopo=nessuno" "blocco B2: scrive=$A/pages/goals.vue · dopo=nessuno"
out=$(bi "$T/p1"); rc=$?
check "componente auto-importato in comune => serie (exit 1)" '[ $rc -eq 1 ] && printf "%s\n" "$out" | grep -q "^blocks-independent: esito=serie"'
check "  con la dipendenza nominata (GoalsCard, da .nuxt)" 'printf "%s\n" "$out" | grep -q "^dipendenza: B1~B2 — .*usa GoalsCard (auto-importato da .nuxt"'
# 1b. auto-imported composable (imports.d.ts)
proc "$T/p1b" "blocco B1: scrive=$A/composables/useGoalsSum.ts · dopo=nessuno" "blocco B2: scrive=$A/pages/somma.vue · dopo=nessuno"
out=$(bi "$T/p1b"); rc=$?
check "composable auto-importato (imports.d.ts) => serie" '[ $rc -eq 1 ] && printf "%s\n" "$out" | grep -q "usa useGoalsSum"'

# 2. NEW file used by the other block via the derived name (components/goals/NewThing.vue -> GoalsNewThing, kebab tag)
proc "$T/p2" "blocco B1: scrive=$A/components/goals/NewThing.vue · dopo=nessuno" "blocco B2: scrive=$A/pages/nuovo.vue · dopo=nessuno"
out=$(bi "$T/p2"); rc=$?
check "file nuovo usato per nome derivato => serie" '[ $rc -eq 1 ] && printf "%s\n" "$out" | grep -q "usa GoalsNewThing (auto-importato, nome derivato dal percorso di $A/components/goals/NewThing.vue"'
# 2b. EXISTING component missing from an old .nuxt: derived name for it too
proc "$T/p2b" "blocco B1: scrive=$A/components/goals/Vecchio.vue · dopo=nessuno" "blocco B2: scrive=$A/pages/vecchio.vue · dopo=nessuno"
check "componente esistente fuori da un .nuxt vecchio: nome derivato => serie" 'og "usa GoalsVecchio (auto-importato, nome derivato" bi "$T/p2b"'
# 2c. name known ONLY from components.d.ts (without folder prefix) => serie (the counterproof's case)
proc "$T/p1c" "blocco B1: scrive=$A/components/goals/Scheda.vue · dopo=nessuno" "blocco B2: scrive=$A/pages/scheda.vue · dopo=nessuno"
check "nome registrato solo in components.d.ts => serie" 'og "usa Scheda (auto-importato da .nuxt" bi "$T/p1c"'
# 2d. repository WITHOUT .nuxt: frontend blocks => serie fail-closed; backend-only blocks => the rest decides
R0="$T/repo-senza-nuxt"; mkdir -p "$R0"; cp -r "$R/modules" "$R/.claude" "$R0/"; rm -rf "$R0/$A/.nuxt"
o=$("$FIC_PY" "$BI" --root "$R0" "$T/p2b"); rc=$?
check "repo senza .nuxt, un blocco sotto apps/admin => serie (.nuxt/*.d.ts assenti)" '[ $rc -eq 1 ] && printf "%s\n" "$o" | grep -q "^blocks-independent: esito=serie motivo=.nuxt/\*.d.ts assenti"'
proc "$T/p2d" "blocco B1: scrive=modules/api/app/services/altro.py · dopo=nessuno" "blocco B2: scrive=modules/api/app/routers/goals.py · dopo=nessuno"
o=$("$FIC_PY" "$BI" --root "$R0" "$T/p2d"); rc=$?
check "  repo senza .nuxt, blocchi solo backend indipendenti => parallelo" '[ $rc -eq 0 ] && printf "%s\n" "$o" | grep -q "esito=parallelo"'
# 2e. block without scrive: (empty lane scope) => serie
proc "$T/p2e" "blocco B1: scrive=(nessuno) · dopo=nessuno" "blocco B2: scrive=$A/pages/altro.vue · dopo=nessuno"
check "blocco senza scrive: => serie (scope vuoto)" 'og "esito=serie motivo=blocco senza scrive: (B1)" bi "$T/p2e"'

# 3. lockfile in scrive: => serie
proc "$T/p3" "blocco B1: scrive=modules/api/app/services/altro.py · dopo=nessuno" "blocco B2: scrive=$A/pages/altro.vue,modules/app/package-lock.json · dopo=nessuno"
out=$(bi "$T/p3"); rc=$?
check "lockfile in scrive: => serie" '[ $rc -eq 1 ] && printf "%s\n" "$out" | grep -q "^blocks-independent: esito=serie motivo=file condiviso o generato in scrive: (B2: modules/app/package-lock.json)"'
proc "$T/p3b" "blocco B1: scrive=modules/api/app/routers/__init__.py · dopo=nessuno" "blocco B2: scrive=$A/pages/altro.vue · dopo=nessuno"
check "  anche un barrel (routers/__init__.py)" 'og "esito=serie motivo=file condiviso" bi "$T/p3b"'

# 4. disjoint backend and frontend => parallel, lanes and scopes named
proc "$T/p4" "blocco B1: scrive=modules/api/app/services/altro.py · dopo=nessuno" "blocco B2: scrive=$A/pages/altro.vue · dopo=nessuno"
out=$(bi "$T/p4"); rc=$?
check "backend e frontend disgiunti => parallelo (exit 0)" '[ $rc -eq 0 ] && printf "%s\n" "$out" | grep -qx "blocks-independent: esito=parallelo corsie=2"'
check "  corsie e scope" 'printf "%s\n" "$out" | grep -qx "corsia 1: B1" && printf "%s\n" "$out" | grep -qx "corsia 2: B2" && printf "%s\n" "$out" | grep -qx "scope 1: modules/api/app/services/altro.py" && printf "%s\n" "$out" | grep -qx "scope 2: $A/pages/altro.vue"'
# 4b. three blocks, A backend · B and C dependent on each other => lane 1 A, lane 2 B,C
proc "$T/p4b" "blocco A: scrive=modules/api/app/services/altro.py · dopo=nessuno" "blocco B: scrive=$A/components/goals/Card.vue · dopo=nessuno" "blocco C: scrive=$A/pages/goals.vue · dopo=B"
out=$(bi "$T/p4b"); rc=$?
check "tre blocchi (backend · scheda · drawer dipendenti) => due corsie, B e C insieme" '[ $rc -eq 0 ] && printf "%s\n" "$out" | grep -qx "corsia 1: A" && printf "%s\n" "$out" | grep -qx "corsia 2: B,C"'

# 5. other conditions: explicit Python import, shared scrive:, declared dopo:
proc "$T/p5" "blocco B1: scrive=modules/api/app/routers/goals.py · dopo=nessuno" "blocco B2: scrive=modules/api/app/services/goals.py · dopo=nessuno"
check "import Python esplicito => serie" 'og "^dipendenza: B1~B2 — modules/api/app/routers/goals.py importa modules/api/app/services/goals.py" bi "$T/p5"'
proc "$T/p5b" "blocco B1: scrive=$A/pages/altro.vue · dopo=nessuno" "blocco B2: scrive=$A/pages/altro.vue · dopo=nessuno"
check "scrive: in comune => serie" 'og "scrive: in comune" bi "$T/p5b"'
proc "$T/p5c" "blocco B1: scrive=modules/api/app/services/altro.py · dopo=nessuno" "blocco B2: scrive=$A/pages/altro.vue · dopo=B1"
check "dopo: dichiarato => serie" 'og "dopo: dichiarato" bi "$T/p5c"'
proc "$T/p5d" "blocco B1: scrive=$A/pages/altro.vue · dopo=nessuno"
check "un blocco solo => serie" 'bi "$T/p5d" >/dev/null; [ $? -eq 1 ]'
check "procedura assente => exit 2" 'bi "$T/non-esiste" >/dev/null 2>&1; [ $? -eq 2 ]'

# 6. after-the-fact check: diff split by scope; both lanes, outside the union, shared => STOP
bi "$T/p4" > "$T/corsie.txt"
printf '%s\n' modules/api/app/services/altro.py "$A/pages/altro.vue" > "$T/diff.txt"
: > "$T/d1"; : > "$T/d2"
out=$("$FIC_PY" "$BI" --posteriori "$T/corsie.txt" "$T/diff.txt" "$T/d1" "$T/d2"); rc=$?
check "a posteriori: diff diviso per scope => OK" '[ $rc -eq 0 ] && [ "$out" = "posteriori: esito=OK corsia 1: modules/api/app/services/altro.py · corsia 2: $A/pages/altro.vue" ]'
printf '%s\n' modules/api/app/services/altro.py > "$T/d2"
out=$("$FIC_PY" "$BI" --posteriori "$T/corsie.txt" "$T/diff.txt" "$T/d1" "$T/d2"); rc=$?
check "a posteriori: file scritto da entrambe le corsie => STOP" '[ $rc -eq 1 ] && [ "$out" = "posteriori: esito=STOP — modules/api/app/services/altro.py scritto da entrambe le corsie" ]'
printf '%s\n' "$A/pages/fuori.vue" > "$T/diff2.txt"
check "a posteriori: file fuori dall'unione => STOP" 'og "fuori dall.unione" "$FIC_PY" "$BI" --posteriori "$T/corsie.txt" "$T/diff2.txt"'
printf '%s\n' modules/app/package-lock.json > "$T/diff3.txt"
check "a posteriori: lockfile generato via Bash => STOP" 'og "file condiviso o generato cambiato" "$FIC_PY" "$BI" --posteriori "$T/corsie.txt" "$T/diff3.txt"'
check "a posteriori: diff illeggibile => STOP (mai OK)" 'og "^posteriori: esito=STOP — input illeggibili" "$FIC_PY" "$BI" --posteriori "$T/corsie.txt" "$T/non-esiste.txt" "$T/d1" "$T/d2"'
check "a posteriori: dichiarati illeggibili => STOP" 'og "^posteriori: esito=STOP — input illeggibili" "$FIC_PY" "$BI" --posteriori "$T/corsie.txt" "$T/diff.txt" "$T/d1" "$T/non-esiste.txt"'
# configured generated file (generati of maat.json, E) regenerated by a lane that declares it => that lane's;
# neither or both => STOP
printf '%s\n' '{"versione_schema":1,"moduli":[{"nome":"a","radice":"."}],"generati":[{"percorso":"docs/gen.md","cartella":".","comando":"true gen.sh","test":"tests/test_gen.py"}]}' > "$T/maat-gen.json"
printf '%s\n' modules/api/app/services/altro.py docs/gen.md > "$T/diff4.txt"
printf '%s\n' docs/gen.md > "$T/d1g"; : > "$T/d2g"
out=$(MAAT_CONFIG="$T/maat-gen.json" "$FIC_PY" "$BI" --posteriori "$T/corsie.txt" "$T/diff4.txt" "$T/d1g" "$T/d2g"); rc=$?
check "a posteriori: generato dichiarato da una corsia => OK, suo" '[ $rc -eq 0 ] && [ "$out" = "posteriori: esito=OK corsia 1: modules/api/app/services/altro.py,docs/gen.md · corsia 2: (nessuno)" ]'
check "a posteriori: generato non dichiarato => STOP" 'MAAT_CONFIG="$T/maat-gen.json" og "generato docs/gen.md rigenerato senza una corsia sola" "$FIC_PY" "$BI" --posteriori "$T/corsie.txt" "$T/diff4.txt" "$T/d2g" "$T/d2g"'
check "a posteriori: file fuori elenco e fuori unione => STOP come prima" 'MAAT_CONFIG="$T/maat-gen.json" og "fuori dall.unione" "$FIC_PY" "$BI" --posteriori "$T/corsie.txt" "$T/diff2.txt" "$T/d1g" "$T/d2g"'

# 7. counterproof: ignoring the contents of .nuxt/components.d.ts (read, not parsed) => case 2c becomes
#    «parallelo» (the test above would be red)
LINE='            ok_c = self._dts(os.path.join(dts, "components.d.ts"), n, DTS_COMP, DTS_CONST)'
check "controprova: riga di components.d.ts unica" '[ "$(grep -cxF -- "$LINE" "$BI")" = 1 ]'
BIX="$T/bi-mutante.py"
sed 's/^            ok_c = self\._dts(os\.path\.join(dts, "components\.d\.ts"), n, DTS_COMP, DTS_CONST)$/            ok_c = self._dts(os.path.join(dts, "components.d.ts"), n)   # MUTANTE: components.d.ts ignorato/' "$BI" > "$BIX"
if cmp -s "$BI" "$BIX"; then fail=$((fail + 1)); n=$((n + 1)); echo "FAIL: controprova: la mutazione non si applica"
else
  out=$(bi "$T/p1c"); rc=$?
  check "controprova: senza components.d.ts il componente registrato senza prefisso risulta «parallelo»" '[ $rc -eq 0 ] && printf "%s\n" "$out" | grep -q "esito=parallelo"'
fi
unset BIX

# 8. pk04b-2: the nuxt-autoimport adapter applies only if declared (framework); without it, only explicit imports
"$FIC_PY" -c 'import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8")); c.pop("framework"); json.dump(c, open(sys.argv[2], "w", encoding="utf-8"))
c["moduli"][1]["radice"] = c["moduli"][1]["radice_pacchetti"] = "modules"; json.dump(c, open(sys.argv[3], "w", encoding="utf-8"))' \
  "$R/.claude/maat.json" "$T/senza-fw.json" "$T/be-modules.json"
caso_fw() { out=$(MAAT_CONFIG="$T/senza-fw.json" "$FIC_PY" "${1:-$BI}" --root "$R" "$T/p1c"); rc=$?
  [ $rc -eq 0 ] && printf "%s\n" "$out" | grep -q "esito=parallelo"; }
check "senza framework nuxt-autoimport: il componente auto-importato non e' una dipendenza (parallelo)" 'caso_fw'
o=$(MAAT_CONFIG="$T/senza-fw.json" "$FIC_PY" "$BI" --root "$R0" "$T/p2b"); rc=$?
check "  e niente fail-closed su .nuxt assente (l'adattatore non c'e')" '[ $rc -eq 0 ] && printf "%s\n" "$o" | grep -q "esito=parallelo"'
check "  gli import espliciti contano ancora (Python)" 'MAAT_CONFIG="$T/senza-fw.json" og "importa modules/api/app/services/goals.py" bi "$T/p5"'
# the module prefixes come from maat.json: with the backend root set to modules, app.services.goals is no longer
# modules/api/app/services/goals.py and the import does not tie the two blocks
o=$(MAAT_CONFIG="$T/be-modules.json" "$FIC_PY" "$BI" --root "$R" "$T/p5"); rc=$?
check "radice del modulo da maat.json: import assoluto risolto sulla radice dichiarata" '[ $rc -eq 0 ] && printf "%s\n" "$o" | grep -q "esito=parallelo"'
# counterproof: adapter always on (framework ignored) => the «senza framework» case goes back to serie, red
BIX="$T/bi-fw.py"
sed 's/if "nuxt-autoimport" in adattatori and any(/if any(/' "$BI" > "$BIX"
check "controprova: con l'adattatore attivo senza dichiararlo il caso «senza framework» e' rosso" '! cmp -s "$BI" "$BIX" && ! caso_fw "$BIX"'
unset BIX

echo "blocks-independent.test.sh: $((n - fail))/$n ok"
[ $fail -eq 0 ]
