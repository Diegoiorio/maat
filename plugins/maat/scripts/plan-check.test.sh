#!/usr/bin/env bash
# Tests of plan-check.sh. Every check has its GREEN case and its RED COUNTERPROOF: a check
# that cannot turn red looks like coverage and is not.
#   bash plugins/maat/scripts/plan-check.test.sh
set -uo pipefail
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
set -f

HERE=$(cd "$(dirname "$0")" && pwd)
PC=${PC:-$HERE/plan-check.sh}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0

# expect <expected-code> <expected-pattern-in-output|-> <description> -- command...
expect() {
  local want="$1" pat="$2" desc="$3"; shift 4
  local out code; out=$("$@" 2>&1); code=$?
  if [ "$code" -ne "$want" ]; then echo "FAIL [$desc] uscita $code, attesa $want"; printf '%s\n' "$out" | sed 's/^/    /'; fail=$((fail+1)); return; fi
  if [ "$pat" != "-" ] && ! printf '%s\n' "$out" | grep -qE -- "$pat"; then echo "FAIL [$desc] manca /$pat/"; printf '%s\n' "$out" | sed 's/^/    /'; fail=$((fail+1)); return; fi
  pass=$((pass+1))
}
# refute <pattern> <description> -- command...   (the output must NOT contain the pattern)
refute() {
  local pat="$1" desc="$2"; shift 3
  local out; out=$("$@" 2>&1)
  if printf '%s\n' "$out" | grep -qE -- "$pat"; then echo "FAIL [$desc] presente /$pat/"; printf '%s\n' "$out" | sed 's/^/    /'; fail=$((fail+1)); return; fi
  pass=$((pass+1))
}

# Reference spec: it deliberately contains the real traps — an H2 inside the plan, a
# "Plan status:" inside a code block, a changelog, an implementation review.
spec() {
cat <<'EOF'
# Titolo
## Contesto
Contesto della feature.
## Requisiti funzionali
1. Il filtro `status` va applicato.
## Piano di implementazione
Plan status: DRAFT
Test level: std
Superfici a rischio: permessi, logica-condivisa
### Passi
1. Modificare `modules/api/app/services/foo.py` in `apply_filter()`.
2. Riusare `modules/api/app/services/foo.py` nel router.
3. Nessun effetto su `std` o `true`.
```text
Plan status: APPROVED
esempio documentato dentro un recinto
```
## ⚠️ Nota interna al piano
La H2 qui sopra NON chiude la sezione del piano.
### Piano di test
- caso 1: `test_foo.py::test_filter` rosso se: il filtro e' ignorato
- [pavimento: permessi] `test_perm.py::test_forbidden` rosso se: il 403 sparisce
### Changelog revisione piano
- Giro 1: corretto il path di `apply_filter()`; rimosso `solo_nel_changelog`.
## Review implementazione
Review status: APPROVED
EOF
}
spec > "$T/base.md"

# ── delta ──────────────────────────────────────────────────────────────────────────────────────
expect 1 "baseline assente" "delta: baseline mancante = errore duro" -- bash "$PC" delta "$T/nope.md" "$T/base.md"
expect 1 "diff vuoto" "delta: file identico = errore duro" -- bash "$PC" delta "$T/base.md" "$T/base.md"
sed 's/$/\r/' "$T/base.md" > "$T/crlf.md"
expect 1 "diff vuoto" "delta: sola conversione CRLF = nessun cambiamento" -- bash "$PC" delta "$T/base.md" "$T/crlf.md"
# counterproof: a real changed line produces a range that contains it (line 12)
sed 's/nel router\./nel router e nel job./' "$T/base.md" > "$T/one.md"
expect 0 "range: offset=10 limit=5" "delta: una riga cambiata -> range corretto (+-2)" -- bash "$PC" delta "$T/base.md" "$T/one.md"
# xref: the path of the changed line also appears on line 11 (outside the range? no: inside the +-2). I use a change on line 22.
sed 's/rosso se: il filtro e. ignorato/rosso se: `apply_filter()` ignora il filtro/' "$T/base.md" > "$T/x.md"
expect 0 "xref: riga 11 \(apply_filter\(\)\)" "delta: xref trova l'altro uso del simbolo fuori range" -- bash "$PC" delta "$T/base.md" "$T/x.md"
# xref must discard the generic stop-list tokens (std, true) but keep the paths
# (the change is on line 22, far from lines 11-12 that cite the path: inside the +-2 they would not
#  be xref, but part of the range)
sed 's/rosso se: il filtro e. ignorato/rosso se: `std`, `true` o `modules\/api\/app\/services\/foo.py` lo ignorano/' "$T/base.md" > "$T/x2.md"
refute "\((std|true)\)" "delta: xref scarta std/true" -- bash "$PC" delta "$T/base.md" "$T/x2.md"
expect 0 "xref: riga 11 \(modules/api/app/services/foo.py\)" "delta: xref tiene il path" -- bash "$PC" delta "$T/base.md" "$T/x2.md"
# reformatting of the whole file (>90%)
awk '{ print $0 " " }' "$T/base.md" | awk 'BEGIN{for(i=0;i<5;i++) print "riga extra " i} {print}' > "$T/reflow.md"
expect 1 "90%" "delta: diff su quasi tutto il file = errore duro" -- bash "$PC" delta "$T/base.md" "$T/reflow.md"

# ── lint ───────────────────────────────────────────────────────────────────────────────────────
expect 0 "lint: OK" "lint: spec di riferimento pulita (recinto e H2 interna non contano)" -- bash "$PC" lint "$T/base.md"
expect 0 "lint: OK" "lint: identica alla baseline" -- bash "$PC" lint "$T/base.md" --baseline "$T/base.md"
expect 0 "lint: OK" "lint: CRLF indifferente" -- bash "$PC" lint "$T/crlf.md" --baseline "$T/base.md"
sed 's/^Test level: std$/Test level: std\nPlan status: APPROVED/' "$T/base.md" > "$T/dup.md"
expect 1 "'Plan status:' compare 2 volte" "lint: riga di stato duplicata = VIOLAZIONE" -- bash "$PC" lint "$T/dup.md"
grep -v '^Superfici a rischio:' "$T/base.md" | sed 's/\[pavimento: permessi\] //' > "$T/legacy.md"
expect 0 "AVVISO: 'Superfici a rischio:' assente" "lint: riga mancante (legacy) = solo AVVISO, uscita 0" -- bash "$PC" lint "$T/legacy.md"
sed 's/- Giro 1: corretto/Test level: full\n- Giro 1: corretto/' "$T/base.md" > "$T/clog.md"
expect 1 "'Test level:' compare 2 volte" "lint: letterale a inizio riga nel changelog = VIOLAZIONE" -- bash "$PC" lint "$T/clog.md"
sed 's/^Contesto della feature\./Contesto della feature, cambiato./' "$T/base.md" > "$T/above.md"
expect 1 "sezioni della SPEC" "lint: spec sopra il piano modificata = VIOLAZIONE" -- bash "$PC" lint "$T/above.md" --baseline "$T/base.md"
sed 's/^Review status: APPROVED/Review status: NEEDS_CHANGES/' "$T/base.md" > "$T/rev.md"
expect 1 "Review implementazione" "lint: review di implementazione toccata = VIOLAZIONE" -- bash "$PC" lint "$T/rev.md" --baseline "$T/base.md"
sed 's/^Superfici a rischio: permessi, logica-condivisa/Superfici a rischio: permessi, auth/' "$T/base.md" > "$T/voc.md"
expect 1 "superficie sconosciuta 'auth'" "lint: superficie fuori vocabolario = VIOLAZIONE" -- bash "$PC" lint "$T/voc.md"
sed 's/^Superfici a rischio: permessi, logica-condivisa/Superfici a rischio: logica-condivisa/' "$T/base.md" > "$T/pav.md"
expect 1 "non dichiarata" "lint: pavimento su superficie non dichiarata = VIOLAZIONE" -- bash "$PC" lint "$T/pav.md"
sed 's/^Superfici a rischio: permessi, logica-condivisa/Superfici a rischio: permessi, logica-condivisa, dati/; s/\[pavimento: permessi\]/[pavimento: logica-condivisa]/' "$T/base.md" > "$T/pav2.md"
expect 1 "solo per le superfici critiche" "lint: pavimento su superficie non critica = VIOLAZIONE" -- bash "$PC" lint "$T/pav2.md"
sed 's/^- \[pavimento: permessi\].*/&\n- [pavimento: permessi] `test_perm.py::test_other` rosso se: x/' "$T/base.md" > "$T/pav3.md"
expect 1 "piu' di una riga \[pavimento: permessi\]" "lint: due pavimenti sulla stessa superficie = VIOLAZIONE" -- bash "$PC" lint "$T/pav3.md"
# Test plan: at level min 1 line; the [pavimento: line does not count
sed 's/^Test level: std$/Test level: min/' "$T/base.md" > "$T/min.md"
expect 0 "lint: OK" "lint: a min, 1 caso + 1 pavimento = entro il tetto" -- bash "$PC" lint "$T/min.md"
sed 's/^- caso 1:.*/&\n- caso 2: `test_foo.py::test_b` rosso se: y/' "$T/min.md" > "$T/min2.md"
expect 0 "AVVISO: '### Piano di test' ha 2 righe al livello min" "lint: a min, 2 casi = AVVISO (uscita 0)" -- bash "$PC" lint "$T/min2.md"
# [e2e-locator: outside the cap like the floor; at most 2 lines
sed 's/^- caso 1:.*/&\n- [e2e-locator: e2e-6-customer.spec.ts] riga cambiata usata da un locator — rosso se: il testo non combacia/' "$T/min.md" > "$T/mine2e.md"
expect 0 "lint: OK" "lint: a min, 1 caso + 1 pavimento + 1 [e2e-locator: = entro il tetto" -- bash "$PC" lint "$T/mine2e.md"
sed 's/^- caso 1:.*/&\n- e2e-6-customer.spec.ts riga cambiata usata da un locator — rosso se: x/' "$T/min.md" > "$T/mine2e-nomark.md"
expect 0 "righe al livello min" "lint: la stessa riga SENZA marcatore conta nel tetto (controprova)" -- bash "$PC" lint "$T/mine2e-nomark.md"
sed 's/^- caso 1:.*/&\n- [e2e-locator: a.spec.ts] x rosso se: x\n- [e2e-locator: b.spec.ts] y rosso se: y\n- [e2e-locator: c.spec.ts] z rosso se: z/' "$T/base.md" > "$T/e2e3.md"
expect 0 "AVVISO: 3 righe \[e2e-locator: — al massimo 2" "lint: 3 righe [e2e-locator: = AVVISO" -- bash "$PC" lint "$T/e2e3.md"
# without a plan section
head -5 "$T/base.md" > "$T/noplan.md"
expect 1 "nessuna sezione" "lint: spec senza piano = VIOLAZIONE" -- bash "$PC" lint "$T/noplan.md"
# first run: baseline without plan, plan added after ONE BLANK LINE → the spec has not changed
{ head -5 "$T/base.md"; echo; sed -n '6,$p' "$T/base.md" | grep -v '^## Review implementazione' | grep -v '^Review status:'; } > "$T/blank.md"
expect 0 "lint: OK" "lint: riga vuota prima del piano non e' una modifica della spec" -- bash "$PC" lint "$T/blank.md" --baseline "$T/noplan.md"
# counterproof: one word changed in the spec, same scenario → VIOLAZIONE
sed 's/^Contesto della feature\./Contesto cambiato./' "$T/blank.md" > "$T/blank2.md"
expect 1 "sezioni della SPEC" "lint: stessa situazione ma spec toccata = VIOLAZIONE" -- bash "$PC" lint "$T/blank2.md" --baseline "$T/noplan.md"
# backticked surfaces: tolerated
sed 's/^Superfici a rischio: permessi, logica-condivisa/Superfici a rischio: `permessi`, `logica-condivisa`/' "$T/base.md" > "$T/bt.md"
expect 0 "lint: OK" "lint: superfici fra backtick = accettate" -- bash "$PC" lint "$T/bt.md"
sed 's/^Superfici a rischio: permessi, logica-condivisa/Superfici a rischio: nessuna, permessi/' "$T/base.md" > "$T/none.md"
expect 1 "'nessuna' insieme" "lint: 'nessuna' con altre superfici = VIOLAZIONE" -- bash "$PC" lint "$T/none.md"
# a mention of the floor in prose, outside the list of the Piano di test, is not a second floor
sed 's/^La H2 qui sopra NON chiude la sezione del piano\./& Coperto dal [pavimento: permessi] sotto./' "$T/base.md" > "$T/prosa.md"
expect 0 "lint: OK" "lint: [pavimento: citato in prosa non conta" -- bash "$PC" lint "$T/prosa.md"
# declared critical surface without a floor or ⚠️ → AVVISO
sed 's/\[pavimento: permessi\] //' "$T/base.md" > "$T/nopav.md"
expect 0 "AVVISO: superficie critica 'permessi'" "lint: critica senza pavimento ne' ⚠️ = AVVISO" -- bash "$PC" lint "$T/nopav.md"
sed 's/^- caso 1:.*/&\n- ⚠️ Superficie permessi non coperta dai gate al livello std/' "$T/nopav.md" > "$T/warnln.md"
refute "superficie critica 'permessi'" "lint: la riga ⚠️ soddisfa la superficie critica" -- bash "$PC" lint "$T/warnln.md"
# at min, the ⚠️ line does not count in the 1-line cap
grep -v 'test_perm.py::test_forbidden' "$T/warnln.md" | sed 's/^Test level: std$/Test level: min/' > "$T/minwarn.md"
refute "righe al livello min" "lint: a min, 1 caso + riga ⚠️ = entro il tetto" -- bash "$PC" lint "$T/minwarn.md"
# the ⚠️ line applies to the surface it NAMES: a ⚠️ on another surface does not cover 'permessi'
sed 's/^- caso 1:.*/&\n- ⚠️ Superficie contratto-api non coperta dai gate al livello std/' "$T/nopav.md" > "$T/warnother.md"
expect 0 "AVVISO: superficie critica 'permessi'" "lint: ⚠️ su un'altra superficie NON copre la critica" -- bash "$PC" lint "$T/warnother.md"
# waiver: without a reason, or broken across lines → AVVISO (downstream it would look like an obligation)
sed 's/^- ⚠️ Superficie permessi .*/& — statica sufficiente:/' "$T/warnln.md" > "$T/wvoid.md"
expect 0 "AVVISO: riga 22: deroga 'statica sufficiente:' senza motivo" "lint: deroga senza motivo = AVVISO" -- bash "$PC" lint "$T/wvoid.md"
sed 's/^- ⚠️ Superficie permessi .*/& —\n  statica sufficiente: rinomina/' "$T/warnln.md" > "$T/wsplit.md"
expect 0 "AVVISO: riga 22: la deroga continua a capo" "lint: deroga spezzata a capo = AVVISO" -- bash "$PC" lint "$T/wsplit.md"
sed 's/^- ⚠️ Superficie permessi .*/& — statica sufficiente: rinomina di una costante/' "$T/warnln.md" > "$T/waiver.md"
refute "deroga" "lint: controprova, deroga con motivo sulla stessa riga = nessun avviso" -- bash "$PC" lint "$T/waiver.md"

# ── contract ───────────────────────────────────────────────────────────────────────────────────
expect 0 "^Plan status: DRAFT$" "contract: Plan status fuori dal recinto" -- bash "$PC" contract "$T/base.md"
expect 0 "^Test level: std$" "contract: livello" -- bash "$PC" contract "$T/base.md"
expect 0 "^Superfici a rischio: permessi, logica-condivisa$" "contract: superfici" -- bash "$PC" contract "$T/base.md"
expect 0 "^Pavimento: permessi \(riga 22\)$" "contract: pavimento" -- bash "$PC" contract "$T/base.md"
refute "^Obbligo" "contract: con pavimento nessun obbligo" -- bash "$PC" contract "$T/base.md"
expect 0 "^Piano di test: offset=20 limit=3$" "contract: range del Piano di test" -- bash "$PC" contract "$T/base.md"
expect 0 "^Tracciabilità requisiti: assente$" "contract: tracciabilità assente" -- bash "$PC" contract "$T/base.md"
expect 0 "^Obbligo: permessi — né pavimento né ⚠️$" "contract: critica scoperta = obbligo" -- bash "$PC" contract "$T/nopav.md"
expect 0 "^Obbligo: permessi — ⚠️ senza deroga \(riga 22\)$" "contract: ⚠️ senza deroga = obbligo" -- bash "$PC" contract "$T/warnln.md"
expect 0 "^Rischio: riga 22 — ⚠️ Superficie permessi non coperta" "contract: la riga ⚠️ e' anche focus di rischio" -- bash "$PC" contract "$T/warnln.md"
expect 0 "^Obbligo: permessi — né pavimento né ⚠️$" "contract: ⚠️ su un'altra superficie non toglie l'obbligo" -- bash "$PC" contract "$T/warnother.md"
expect 0 "^Statica sufficiente: permessi — rinomina di una costante \(riga 22\)$" "contract: deroga con motivo" -- bash "$PC" contract "$T/waiver.md"
refute "^Obbligo" "contract: controprova, la deroga toglie l'obbligo" -- bash "$PC" contract "$T/waiver.md"
expect 0 "^Obbligo: permessi — ⚠️ senza deroga" "contract: deroga spezzata a capo = ancora obbligo" -- bash "$PC" contract "$T/wsplit.md"
grep -v '^Test level:' "$T/legacy.md" | sed 's/^- caso 1:.*/&\n⚠️ Superficie **schema DB** non coperta dai gate: la migrazione e'"'"' manuale./' > "$T/legacy2.md"
expect 0 "^Test level: legacy \(assente\)$" "contract: livello assente = legacy" -- bash "$PC" contract "$T/legacy2.md"
expect 0 "^Rischio: riga [0-9]+ — ⚠️ Superficie \*\*schema DB\*\*" "contract: riga ⚠️ legacy in prosa riportata" -- bash "$PC" contract "$T/legacy2.md"
refute "^Obbligo" "contract: spec legacy (senza superfici) = nessun obbligo" -- bash "$PC" contract "$T/legacy2.md"
expect 0 "^Test level: legacy \(duplicata: 2\)$" "contract: livello duplicato = legacy" -- bash "$PC" contract "$T/clog.md"
sed 's/^esempio documentato dentro un recinto$/Test level: full/' "$T/base.md" > "$T/fencelvl.md"
expect 0 "^Test level: std$" "contract: un livello dentro un recinto non conta" -- bash "$PC" contract "$T/fencelvl.md"
grep -v '^Test level:' "$T/base.md" | sed 's/^- Giro 1: corretto.*/Test level: full/' > "$T/clogonly_lvl.md"
expect 0 "^Test level: legacy \(assente\)$" "contract: livello solo nel changelog = legacy" -- bash "$PC" contract "$T/clogonly_lvl.md"
sed 's/^3\. Nessun effetto.*/&\n### Tracciabilità requisiti\n| Req | Passi | Verifica |\n| RF1 | 1 | caso 1 |/' "$T/base.md" > "$T/trac.md"
expect 0 "^Tracciabilità requisiti: offset=14 limit=7$" "contract: range della tracciabilità (fino alla H2 successiva)" -- bash "$PC" contract "$T/trac.md"
expect 1 "nessuna sezione" "contract: spec senza piano = uscita 1" -- bash "$PC" contract "$T/noplan.md"

# ── basis: the approval bound to spec and plan ──────────────────────────────────────────────────
expect 0 "^Status: LEGACY$" "basis: nessuna riga Approved basis = LEGACY" -- bash "$PC" basis "$T/base.md"
cur=$(bash "$PC" basis "$T/base.md" | sed -n 's/^Basis: //p')
sed "s/^Superfici a rischio: .*/&\nApproved basis: $cur/" "$T/base.md" > "$T/ab.md"
expect 0 "^Status: FRESH$" "basis: riga scritta con l'impronta attuale = FRESH" -- bash "$PC" basis "$T/ab.md"
sed 's/$/\r/' "$T/ab.md" > "$T/ab-crlf.md"
expect 0 "^Status: FRESH$" "basis: CRLF indifferente" -- bash "$PC" basis "$T/ab-crlf.md"
sed 's/^- Giro 1: corretto.*/&\nMetrica ciclo: giri=1 · esito=approvato/' "$T/ab.md" > "$T/ab-clog.md"
expect 0 "^Status: FRESH$" "basis: solo changelog cambiato = FRESH" -- bash "$PC" basis "$T/ab-clog.md"
sed 's/^Review status: APPROVED/Review status: NEEDS_CHANGES/' "$T/ab.md" > "$T/ab-rev.md"
expect 0 "^Status: FRESH$" "basis: solo review di implementazione cambiata = FRESH" -- bash "$PC" basis "$T/ab-rev.md"
sed 's/^Contesto della feature\./Contesto cambiato./' "$T/ab.md" > "$T/ab-spec.md"
expect 0 "^Status: STALE \(spec\)$" "basis: spec sopra il piano cambiata = STALE (spec)" -- bash "$PC" basis "$T/ab-spec.md"
sed 's/nel router\./nel router e nel job./' "$T/ab.md" > "$T/ab-plan.md"
expect 0 "^Status: STALE \(plan\)$" "basis: corpo del piano cambiato = STALE (plan)" -- bash "$PC" basis "$T/ab-plan.md"
sed 's/^esempio documentato dentro un recinto/esempio cambiato dentro un recinto/' "$T/ab.md" > "$T/ab-fence.md"
expect 0 "^Status: STALE \(plan\)$" "basis: blocco di codice del piano cambiato = STALE (plan)" -- bash "$PC" basis "$T/ab-fence.md"
sed 's/^Contesto della feature\./Contesto cambiato./; s/nel router\./nel job./' "$T/ab.md" > "$T/ab-both.md"
expect 0 "^Status: STALE \(spec, plan\)$" "basis: entrambe cambiate" -- bash "$PC" basis "$T/ab-both.md"
sed 's/^Plan status: DRAFT/Plan status: APPROVED/' "$T/ab.md" > "$T/ab-st.md"
expect 0 "^Status: STALE \(plan\)$" "basis: Plan status fa parte del corpo" -- bash "$PC" basis "$T/ab-st.md"
# a line with a TAB: the change AFTER the TAB must count (awk $4 would stop at the TAB)
printf '%s\n' "# T" "## Piano di implementazione" "Plan status: APPROVED" "- a	b" > "$T/tab.md"
curt=$(bash "$PC" basis "$T/tab.md" | sed -n 's/^Basis: //p')
printf '%s\n' "# T" "## Piano di implementazione" "Plan status: APPROVED" "Approved basis: $curt" "- a	c" > "$T/tab2.md"
expect 0 "^Status: STALE \(plan\)$" "basis: cambio dopo un TAB = STALE" -- bash "$PC" basis "$T/tab2.md"
expect 1 "nessuna sezione" "basis: spec senza piano = uscita 1" -- bash "$PC" basis "$T/noplan.md"
# lint of the line
sed "s/^Approved basis: .*/&\nApproved basis: $cur/" "$T/ab.md" > "$T/ab-dup.md"
expect 1 "'Approved basis:' compare 2 volte" "lint: Approved basis duplicata = VIOLAZIONE" -- bash "$PC" lint "$T/ab-dup.md"
sed 's/^Plan status: DRAFT/Plan status: APPROVED/' "$T/base.md" > "$T/appr-nobasis.md"
expect 0 "AVVISO: piano APPROVED senza riga 'Approved basis:'" "lint: APPROVED senza basis = AVVISO" -- bash "$PC" lint "$T/appr-nobasis.md"
refute "Approved basis" "lint: DRAFT senza basis = nessun avviso" -- bash "$PC" lint "$T/base.md"

# ── delta: the xrefs do not fish in the changelog (it is history, it would use up the 8 slots) ─────────────
sed 's/^- Giro 1: corretto il path di `apply_filter()`; rimosso `solo_nel_changelog`\./&\n- Giro 2: `rosso_unico_token` sistemato./' "$T/base.md" > "$T/cl1.md"
sed 's/^Contesto della feature\./Contesto della feature./; s/^3\. Nessun effetto su `std` o `true`\./3. Nessun effetto su `rosso_unico_token`./' "$T/cl1.md" > "$T/cl2.md"
refute "xref: riga 2[0-9] \(rosso_unico_token\)" "delta: xref non punta al changelog" -- bash "$PC" delta "$T/cl1.md" "$T/cl2.md"

# ── format 2: lint2, gen, route, s2 ─────────────────────────────────────────────────────────────
# A fake repository: the plan paths must exist (first folder) and lint2 searches the real tests.
R="$T/repo"
mkdir -p "$R/modules/api/app/routers" "$R/modules/api/tests" "$R/modules/app/apps/admin/components" \
  "$R/modules/app/apps/admin/tests" "$R/modules/app/apps/admin/e2e/specs" "$R/modules/app/packages/ui" "$R/script"
printf '%s\n' 'def update_goal(user):' '    if not can_edit:' '        raise Forbidden()' > "$R/modules/api/app/routers/goals.py"
printf '%s\n' 'def test_update_denied():' '    assert status == 403' > "$R/modules/api/tests/test_goals.py"
printf '%s\n' '<div data-test="goals-company-bar">Barra</div>' > "$R/modules/app/apps/admin/components/Bar.vue"
printf '%s\n' 'it("bar", () => { expect(w.find("[data-test=goals-company-bar]").exists()).toBe(true) })' > "$R/modules/app/apps/admin/tests/bar.test.ts"
printf '%s\n' 'it("old", () => { expect(w.find("[data-test=goals-old-section]").exists()).toBe(true) })' > "$R/modules/app/apps/admin/tests/old.test.ts"
printf '%s\n' 'test("e2e", async () => { await page.getByText("Vecchio titolo").click() })' > "$R/modules/app/apps/admin/e2e/specs/e2e-6-goals.spec.ts"
export PLAN_CHECK_ROOT="$R"
. "$HERE/python.sh"; export FIC_PY   # a single interpreter for all calls
# pk04b-2: modules, surfaces and migrations come from maat.json (the nuxt-fastapi example); the prep of
# counterproof.sh reads it by importing the reader, with the root of the fake project
mkdir -p "$R/.claude"; cp "$HERE/../examples/nuxt-fastapi.maat.json" "$R/.claude/maat.json"
export MAAT_CONFIG_PY="$HERE/maat-config.py" PROJECT_ROOT="$R"
# the be interpreter (python of the example: .venv312/bin/python, then .venv/bin/python): the second one exists
mkdir -p "$R/modules/api/.venv/bin"; : > "$R/modules/api/.venv/bin/python"
PLUGIN_DIR=$(cd "$HERE/.." && pwd)
mutpc() { # <name> <sed expression> → mutant of plan-check.sh next to lib/maat-paths.sh and the catalog (the plugin from MAAT_ROOT)
  mkdir -p "$T/pcm-$1/lib"; cp "$HERE/lib/maat-paths.sh" "$HERE/lib/maat-msg.sh" "$HERE/lib/messages.tsv" "$T/pcm-$1/lib/"
  cp "$HERE/maat_msg.py" "$T/pcm-$1/"   # 1.4.0: the message catalog and its two readers, next to the mutant
  sed "$2" "$PC" > "$T/pcm-$1/plan-check.sh"; ! cmp -s "$PC" "$T/pcm-$1/plan-check.sh"
}
spec2() {
cat <<'EOF'
# Titolo
## Requisiti funzionali
1. RF1 — un venditore non modifica l'obiettivo.
2. RF2 — la barra compare.
3. RF3 — il testo della barra.
## Piano di implementazione
Plan format: 2
Plan status: DRAFT
Test level: std
Superfici a rischio: permessi, contratto-api
### Decisioni
Il 403 vale per chi non può modificare.
| input | output |
|---|---|
| venditore | 403 |
### File toccati
- `modules/api/app/routers/goals.py`
- `modules/api/tests/test_goals.py`
- `modules/app/apps/admin/components/Bar.vue`
- `modules/app/apps/admin/tests/bar.test.ts`
### Passi
#### Blocco B1 — backend
scrive: `modules/api/app/routers/goals.py`, `modules/api/tests/test_goals.py`
dopo: nessuno

| id | file | modifica | test |
|---|---|---|---|
| P1 | `modules/api/app/routers/goals.py` | `update_goal()`: 403 a chi non può | T1 |
| P2 | `modules/api/tests/test_goals.py` | caso nuovo | T1 |

#### Blocco B2 — frontend
scrive: `modules/app/apps/admin/components/Bar.vue`, `modules/app/apps/admin/tests/bar.test.ts`
dopo: B1

| id | file | modifica | test |
|---|---|---|---|
| P3 | `modules/app/apps/admin/components/Bar.vue` | la barra | T2 |
### Tracciabilità requisiti
| Req | Passi del piano | Verifica |
|---|---|---|
| RF1 | P1, P2 | T1 |
| RF2 | P3 | T2 |
| RF3 | P3 | non verificabile a test: solo testo |
### Stringhe e data-test
| azione | tipo | valore |
|---|---|---|
| aggiunge | data-test | `goals-company-bar` |
### Piano di test
| ID | requisito | file | asserzione | mutazione |
|---|---|---|---|---|
| T1 | RF1 | `modules/api/tests/test_goals.py::test_update_denied` (nuovo) | rosso se: il venditore aggiorna | `modules/api/app/routers/goals.py` · `update_goal` · `if not can_edit:` → `if False:` · rosso se: `assert 200 == 403` |
| T2 | RF2 | `modules/app/apps/admin/tests/bar.test.ts::bar` (nuovo) | rosso se: la barra manca, `expected false to be true` | — |
- [pavimento: permessi] T1
### Changelog revisione piano
- Giro 1: piano iniziale.
EOF
}
spec2 > "$T/f2.md"
# lint2 and the usual lint on the reference format 2 plan
expect 0 "^lint2: OK$" "lint2: piano in formato 2 di riferimento pulito" -- bash "$PC" lint2 "$T/f2.md"
expect 0 "AVVISO: .*goals-company-bar aggiunto dal piano ma gia presente in modules/app/apps/admin/tests/bar.test.ts:1" "lint2: stringa aggiunta gia presente in un test = AVVISO" -- bash "$PC" lint2 "$T/f2.md"
expect 0 "lint: OK" "lint: il formato 2 passa anche il lint di sempre" -- bash "$PC" lint "$T/f2.md"
refute "righe al livello" "lint: in formato 2 intestazione e separatore della tabella non contano nel tetto" -- bash "$PC" lint "$T/f2.md"
# format 1 plan: lint2 and gen do not apply
expect 0 "^lint2: non si applica" "lint2: piano in formato 1 = non si applica (uscita 0)" -- bash "$PC" lint2 "$T/base.md"
refute "VIOLAZIONE" "lint2: formato 1, nessuna violazione" -- bash "$PC" lint2 "$T/base.md"
# requirement without a test (counterproof by mutation: removing the check makes this case green)
sed 's/^| T2 | RF2 |/| T2 | RF1 |/' "$T/f2.md" > "$T/f2-noreq.md"
expect 1 "VIOLAZIONE: riga [0-9]+: requisito RF2 senza test" "lint2: requisito senza test = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-noreq.md"
refute "requisito RF3" "lint2: 'non verificabile a test' esenta il requisito" -- bash "$PC" lint2 "$T/f2-noreq.md"
# file in the steps but not in the list
grep -v '^- `modules/app/apps/admin/components/Bar.vue`$' "$T/f2.md" > "$T/f2-nofile.md"
expect 1 "VIOLAZIONE: riga [0-9]+: passo P3: modules/app/apps/admin/components/Bar.vue non e nella lista ### File toccati" "lint2: file di un passo fuori lista = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-nofile.md"
# test outside a step
sed 's/^| P3 | \(.*\) | T2 |$/| P3 | \1 | — |/' "$T/f2.md" > "$T/f2-nostep.md"
expect 1 "VIOLAZIONE: riga [0-9]+: test T2 non compare in nessun passo" "lint2: test fuori da un passo = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-nostep.md"
# harness-pt15 (D): an EXISTING non-regression test in the table ("resta verde") stops the cycle at test-red:
# a VIOLAZIONE that explains where it goes. Variants: "rimane verde", "continua a passare", uppercase.
sed 's/^| T2 | RF2 | \(`[^`]*`\) (nuovo) | rosso se: /| T2 | RF2 | \1 | resta verde: /' "$T/f2.md" > "$T/f2-verde.md"
expect 1 "VIOLAZIONE: riga [0-9]+: test T2: asserzione \"resta verde\": un test esistente di non-regressione non e una riga del Piano di test" "lint2: riga 'resta verde' nel piano di test = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-verde.md"
expect 1 "nota sotto di essa .*non verificabile a test \(invarianza, non dimostrabile rossa\)" "lint2: il messaggio dice dove va il test di non-regressione" -- bash "$PC" lint2 "$T/f2-verde.md"
sed 's/^| T2 | RF2 | \(`[^`]*`\) (nuovo) | rosso se: /| T2 | RF2 | \1 | **Rimane verde** con: /' "$T/f2.md" > "$T/f2-verde2.md"
expect 1 "VIOLAZIONE: riga [0-9]+: test T2: asserzione \"resta verde\"" "lint2: 'Rimane verde' in grassetto = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-verde2.md"
sed 's/^| T2 | RF2 | \(`[^`]*`\) (nuovo) | rosso se: /| T2 | RF2 | \1 | continua a passare: /' "$T/f2.md" > "$T/f2-verde3.md"
expect 1 "VIOLAZIONE: riga [0-9]+: test T2: asserzione \"resta verde\"" "lint2: 'continua a passare' = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-verde3.md"
# right form: T2 outside the table, note below, RF2 "non verificabile a test (invarianza, ...)" = clean
grep -v '^| T2 |' "$T/f2.md" | sed -e 's/^| P3 | \(.*\) | T2 |$/| P3 | \1 | — |/' \
  -e 's/^| RF2 | P3 | T2 |$/| RF2 | P3 | non verificabile a test (invarianza, non dimostrabile rossa): la copre il test esistente `bar.test.ts`, nel gate |/' \
  -e 's/^- \[pavimento: permessi\] T1$/Test ESISTENTI di non-regressione (non sono righe del Piano di test): `modules\/app\/apps\/admin\/tests\/bar.test.ts` resta verde (RF2).\n- [pavimento: permessi] T1/' \
  > "$T/f2-verde-ok.md"
expect 0 "^lint2: OK$" "lint2: test di non-regressione nella nota, tracciabilita 'non verificabile a test (invarianza...)' = pulito" -- bash "$PC" lint2 "$T/f2-verde-ok.md"
# "resta verde" INSIDE a red assertion (not at the start) is not a non-regression test
sed 's/^| T2 | RF2 | \(`[^`]*`\) (nuovo) | rosso se: /| T2 | RF2 | \1 (nuovo) | rosso se: il caso vecchio resta verde ma /' "$T/f2.md" > "$T/f2-verde-mid.md"
expect 0 "^lint2: OK$" "lint2: 'resta verde' a meta asserzione = pulito" -- bash "$PC" lint2 "$T/f2-verde-mid.md"
# block without scrive:
awk '!(/^scrive:/ && ++n == 2)' "$T/f2.md" > "$T/f2-noscrive.md"
expect 1 "VIOLAZIONE: riga [0-9]+: blocco B2 senza scrive:" "lint2: blocco senza scrive: = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-noscrive.md"
# step outside a block
sed 's/^#### Blocco B1 — backend$/Blocco B1 — backend/' "$T/f2.md" > "$T/f2-noblock.md"
expect 1 "VIOLAZIONE: riga [0-9]+: passo P1 fuori da un blocco" "lint2: passo fuori da un blocco = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-noblock.md"
# removed string still asserted by an existing test that the plan does not touch
sed 's/^| aggiunge | data-test | `goals-company-bar` |$/&\n| toglie | data-test | `goals-old-section` |/' "$T/f2.md" > "$T/f2-rm.md"
expect 1 "VIOLAZIONE: riga [0-9]+: data-test goals-old-section tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/old.test.ts:1" "lint2: data-test tolto ancora asserito = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-rm.md"
# counterproof: if the plan touches that test, the case is clean again
sed 's/^- `modules\/app\/apps\/admin\/tests\/bar.test.ts`$/&\n- `modules\/app\/apps\/admin\/tests\/old.test.ts`/' "$T/f2-rm.md" > "$T/f2-rm-ok.md"
expect 0 "^lint2: OK$" "lint2: data-test tolto ma il piano tocca il test che lo asserisce = pulito" -- bash "$PC" lint2 "$T/f2-rm-ok.md"
# a removed string asserted by an e2e: the [e2e-locator:] line is needed
sed 's/^| aggiunge | data-test | `goals-company-bar` |$/&\n| toglie | stringa | `Vecchio titolo` |/' "$T/f2.md" > "$T/f2-e2e.md"
expect 1 "stringa Vecchio titolo tolto dal piano ma ancora asserito da modules/app/apps/admin/e2e/specs/e2e-6-goals.spec.ts:1" "lint2: stringa tolta asserita da un e2e = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-e2e.md"
sed 's/^- \[pavimento: permessi\] T1$/&\n- [e2e-locator: e2e-6-goals.spec.ts] il titolo cambia rosso se: il locator non trova il testo/' "$T/f2-e2e.md" > "$T/f2-e2e-ok.md"
expect 0 "^lint2: OK$" "lint2: con la riga [e2e-locator:] dello spec = pulito" -- bash "$PC" lint2 "$T/f2-e2e-ok.md"
# removed strings: only in literals, whole value; absence = AVVISO; waiver with the verificato column
printf '%s\n' "it(\"neg\", () => { expect(text).not.toContain('Attivo'); expect(w.text()).toContain(\"Attivonuovo\") })" > "$R/modules/app/apps/admin/tests/neg.test.ts"
printf '%s\n' "it(\"pos\", () => { expect(w.text()).toContain('Scaduto') })" > "$R/modules/app/apps/admin/tests/pos.test.ts"
strrow() { sed "s/^| aggiunge | data-test | \`goals-company-bar\` |\$/&\n$1/" "$T/f2.md"; }
strrow '| toglie | stringa | `Attivo` |' > "$T/f2-neg.md"
expect 0 "^lint2: OK$" "lint2: stringa tolta solo in un'asserzione di assenza di un file non toccato = pulito" -- bash "$PC" lint2 "$T/f2-neg.md"
expect 0 "AVVISO: riga [0-9]+: stringa Attivo tolto dal piano: modules/app/apps/admin/tests/neg.test.ts:1 lo cita solo in un asserzione di assenza" "lint2: l'asserzione di assenza e' un AVVISO" -- bash "$PC" lint2 "$T/f2-neg.md"
strrow '| toglie | stringa | `Scad` |' > "$T/f2-sub.md"
expect 0 "^lint2: OK$" "lint2: sottostringa di una parola piu' lunga = nessun match (controprova: senza il criterio del letterale va rossa)" -- bash "$PC" lint2 "$T/f2-sub.md"
refute "Scad" "lint2: sottostringa, nemmeno un AVVISO" -- bash "$PC" lint2 "$T/f2-sub.md"
printf '%s\n' '// colonna "Chiuso" della tabella' "it('mostra lo stato Chiuso', () => { expect(1).toBe(1) })" > "$R/modules/app/apps/admin/tests/title.test.ts"
strrow '| toglie | stringa | `Chiuso` |' > "$T/f2-title.md"
refute "Chiuso" "lint2: titolo di un test e commento non sono asserzioni = nessun match" -- bash "$PC" lint2 "$T/f2-title.md"
# real absence versus presence (2nd review): .not.toBeNull() and data-test selectors require the element to exist
printf '%s\n' "it(\"p\", () => { expect(w.find('[data-test=\"goals-contrib-total\"]').element.closest('.x')).not.toBeNull() })" > "$R/modules/app/apps/admin/tests/presence.test.ts"
strrow '| toglie | data-test | `goals-contrib-total` |' > "$T/f2-nn.md"
expect 1 "VIOLAZIONE: riga [0-9]+: data-test goals-contrib-total tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/presence.test.ts:1" "lint2: .not.toBeNull() afferma la presenza = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-nn.md"
printf '%s\n' "it(\"s\", () => { expect(w.find('[data-test=\"goals-sel-x\"]').text()).not.toContain('y') })" > "$R/modules/app/apps/admin/tests/selector.test.ts"
strrow '| toglie | data-test | `goals-sel-x` |' > "$T/f2-sel.md"
expect 1 "VIOLAZIONE: riga [0-9]+: data-test goals-sel-x tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/selector.test.ts:1" "lint2: data-test nel selettore di un .not.toContain = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-sel.md"
printf '%s\n' "it(\"e\", () => { expect(w.find('[data-test=\"goals-gone\"]').exists()).toBe(false) })" > "$R/modules/app/apps/admin/tests/gone.test.ts"
strrow '| toglie | data-test | `goals-gone` |' > "$T/f2-gone.md"
expect 0 "AVVISO: riga [0-9]+: data-test goals-gone tolto dal piano: modules/app/apps/admin/tests/gone.test.ts:1 lo cita solo in un asserzione di assenza" "lint2: exists()).toBe(false) = assenza, AVVISO" -- bash "$PC" lint2 "$T/f2-gone.md"
expect 0 "^lint2: OK$" "lint2: exists()).toBe(false) non blocca" -- bash "$PC" lint2 "$T/f2-gone.md"
# position per literal, and ALL literals of the value (3rd review): a single positive position is enough
printf '%s\n' '    assert "Sospeso" in body and "x" not in body' > "$R/modules/api/tests/test_pos_and_not_in.py"
strrow '| toglie | stringa | `Sospeso` |' > "$T/f2-py1.md"
expect 1 "VIOLAZIONE: riga [0-9]+: stringa Sospeso tolto dal piano ma ancora asserito da modules/api/tests/test_pos_and_not_in.py:1" "lint2: assert \"X\" in body and \"y\" not in body = VIOLAZIONE su X" -- bash "$PC" lint2 "$T/f2-py1.md"
printf '%s\n' '    assert "x" in body and "Revocato" not in body' > "$R/modules/api/tests/test_neg_not_in.py"
strrow '| toglie | stringa | `Revocato` |' > "$T/f2-py2.md"
expect 0 "AVVISO: riga [0-9]+: stringa Revocato tolto dal piano: modules/api/tests/test_neg_not_in.py:1 lo cita solo in un asserzione di assenza" "lint2: \"X\" not in body = assenza, AVVISO" -- bash "$PC" lint2 "$T/f2-py2.md"
printf '%s\n' "it(\"a\", () => { expect(w.get('[data-test=\"save\"]').attributes('disabled')).toBeFalsy() })" > "$R/modules/app/apps/admin/tests/attr.test.ts"
strrow '| toglie | data-test | `save` |' > "$T/f2-attr.md"
expect 1 "VIOLAZIONE: riga [0-9]+: data-test save tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/attr.test.ts:1" "lint2: toBeFalsy() dopo .attributes( sul get = presenza, VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-attr.md"
printf '%s\n' "it(\"b\", () => { expect(a).toContain('Bozza'); expect(b).not.toContain('Bozza') })" > "$R/modules/app/apps/admin/tests/both.test.ts"
strrow '| toglie | stringa | `Bozza` |' > "$T/f2-both.md"
expect 1 "VIOLAZIONE: riga [0-9]+: stringa Bozza tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/both.test.ts:1" "lint2: toContain e .not.toContain sulla stessa riga = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-both.md"
# the positive cases: all VIOLAZIONE
printf '%s\n' "  screen.getByText('Pos1')" "  expect(w).toHaveText('Pos2')" "  await findByTestId('pos-3')" \
  "  expect(w.find('[data-test=\"pos-4\"]').exists()).toBe(true)" "  expect(w.find('[data-test=\"pos-5\"]')).toBeTruthy()" > "$R/modules/app/apps/admin/tests/positives.test.ts"
printf '%s\n' '    assert "Pos6" in body' > "$R/modules/api/tests/test_positives.py"
sed 's/^| aggiunge | data-test | `goals-company-bar` |$/&\n| toglie | stringa | `Pos1` |\n| toglie | stringa | `Pos2` |\n| toglie | data-test | `pos-3` |\n| toglie | data-test | `pos-4` |\n| toglie | data-test | `pos-5` |\n| toglie | stringa | `Pos6` |/' "$T/f2.md" > "$T/f2-positives.md"
expect 1 "stringa Pos1 tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/positives.test.ts:1" "lint2: getByText('X') = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-positives.md"
expect 1 "stringa Pos2 tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/positives.test.ts:2" "lint2: toHaveText('X') = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-positives.md"
expect 1 "data-test pos-3 tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/positives.test.ts:3" "lint2: findByTestId('x') = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-positives.md"
expect 1 "data-test pos-4 tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/positives.test.ts:4" "lint2: exists()).toBe(true) = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-positives.md"
expect 1 "data-test pos-5 tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/positives.test.ts:5" "lint2: toBeTruthy() su un find = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-positives.md"
expect 1 "stringa Pos6 tolto dal piano ma ancora asserito da modules/api/tests/test_positives.py:1" "lint2: assert \"X\" in body = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-positives.md"
printf '%s\n' "  expect(/^x/.test('Riservato')).toBe(true)" > "$R/modules/app/apps/admin/tests/regex.test.ts"
strrow '| toglie | stringa | `Riservato` |' > "$T/f2-re.md"
expect 1 "stringa Riservato tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/regex.test.ts:1" "lint2: /re/.test('X') non e' un titolo di test" -- bash "$PC" lint2 "$T/f2-re.md"
strrow '| toglie | stringa | `Scaduto` |' > "$T/f2-pos.md"
expect 1 "VIOLAZIONE: riga [0-9]+: stringa Scaduto tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/pos.test.ts:1" "lint2: stringa tolta asserita in positivo = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-pos.md"
sed 's/^| azione | tipo | valore |$/| azione | tipo | valore | verificato |/; s/^| toglie | stringa | `Scaduto` |$/| toglie | stringa | `Scaduto` | `modules\/app\/apps\/admin\/tests\/pos.test.ts` — riscritto dal flusso X |/' "$T/f2-pos.md" > "$T/f2-ver.md"
expect 0 "^lint2: OK$" "lint2: la deroga verificato sul file = pulito" -- bash "$PC" lint2 "$T/f2-ver.md"
expect 0 "AVVISO: .*stringa Scaduto tolto dal piano, asserito da modules/app/apps/admin/tests/pos.test.ts:1: deroga verificato \(riscritto dal flusso X\)" "lint2: la deroga resta un AVVISO col motivo" -- bash "$PC" lint2 "$T/f2-ver.md"
sed 's/ — riscritto dal flusso X |$/ |/' "$T/f2-ver.md" > "$T/f2-ver-nowhy.md"
expect 1 "VIOLAZIONE: riga [0-9]+: verificato vuole" "lint2: deroga senza motivo = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-ver-nowhy.md"
sed 's/`modules\/app\/apps\/admin\/tests\/pos.test.ts` — riscritto/`modules\/app\/apps\/admin\/tests\/altro.test.ts` — riscritto/' "$T/f2-ver.md" > "$T/f2-ver-other.md"
expect 1 "VIOLAZIONE: riga [0-9]+: stringa Scaduto tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/pos.test.ts:1" "lint2: una deroga su un altro file non copre questo" -- bash "$PC" lint2 "$T/f2-ver-other.md"
sed 's/`modules\/app\/apps\/admin\/tests\/pos.test.ts` — riscritto/`modules\/app\/apps\/admin\/tests\/nessuno.test.ts` — riscritto/' "$T/f2-ver.md" > "$T/f2-ver-unused.md"
expect 1 "AVVISO: riga [0-9]+: deroga verificato inutilizzata: modules/app/apps/admin/tests/nessuno.test.ts" "lint2: deroga su un file senza match = AVVISO deroga inutilizzata" -- bash "$PC" lint2 "$T/f2-ver-unused.md"
refute "deroga verificato inutilizzata" "lint2: controprova, la deroga usata non e' inutilizzata" -- bash "$PC" lint2 "$T/f2-ver.md"
# malformed mutation, and across different modules
sed 's/ · rosso se: `assert 200 == 403` |$/ |/' "$T/f2.md" > "$T/f2-badmut.md"
expect 1 "VIOLAZIONE: riga [0-9]+: test T1: mutazione illeggibile" "lint2: mutazione senza rosso se = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-badmut.md"
sed 's/^| T2 | RF2 | \(.*\) | — |$/| T2 | RF2 | \1 | `modules\/api\/app\/routers\/goals.py` · `update_goal` · `raise Forbidden()` → (vuoto) · rosso se: `expected` |/' "$T/f2.md" > "$T/f2-cross.md"
expect 1 "VIOLAZIONE: riga [0-9]+: test T2: file e test in moduli diversi" "lint2: mutazione backend osservata da un test frontend = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-cross.md"
# pk04b-2: the Python of plan-check.sh REALLY uses the reader (MAAT_CONFIG_PY), not a copy of the rules: with a
# maat-config.py whose modulo_di puts every file in fe, the backend mutation observed by the frontend test is no longer
# across different modules. Counterproof: runner() again with hard-wired ADMIN/API => the violation stays, the case is red.
mkdir -p "$T/mcx/scripts"; cp -r "$HERE/../schemas" "$HERE/../profiles" "$T/mcx/"
sed 's/^    return instrada(r, percorso)$/    return ("fe", "radice")/' "$HERE/maat-config.py" > "$T/mcx/scripts/maat-config.py"
lettore_ok() { local o   # the exit code first, then grep: with pipefail the exit 1 of lint2 would invert the result
  ! cmp -s "$HERE/maat-config.py" "$T/mcx/scripts/maat-config.py" || return 1
  o=$(MAAT_CONFIG_PY="$T/mcx/scripts/maat-config.py" "$@" lint2 "$T/f2-cross.md" 2>&1)
  ! printf '%s\n' "$o" | grep -q "moduli diversi"; }
lettore_ok bash "$PC" && pass=$((pass+1)) || { echo "FAIL [lint2: il Python legge i moduli dal lettore importato (MAAT_CONFIG_PY)]"; fail=$((fail+1)); }
mutpc cablato '/^def runner(f, tp):$/a\    return "x" if (f.startswith("modules/app/") and tp.startswith("modules/app/apps/admin/")) or (f.startswith("modules/api/") and tp.startswith("modules/api/")) else None' &&
  ! lettore_ok env MAAT_ROOT="$PLUGIN_DIR" bash "$T/pcm-cablato/plan-check.sh" && pass=$((pass+1)) ||
  { echo "FAIL [controprova: con ADMIN/API cablati in runner() il lettore alterato non cambia nulla, il caso deve essere rosso]"; fail=$((fail+1)); }
# open risk: it must name a test of the table
sed 's/^- \[pavimento: permessi\] T1$/&\n- ⚠️ Rischio aperto: la barra lampeggia/' "$T/f2.md" > "$T/f2-risk.md"
expect 1 "VIOLAZIONE: riga [0-9]+: rischio aperto senza un test assegnato" "lint2: rischio aperto senza test = VIOLAZIONE" -- bash "$PC" lint2 "$T/f2-risk.md"
sed 's/^- ⚠️ Rischio aperto: la barra lampeggia$/& — T2/' "$T/f2-risk.md" > "$T/f2-risk-ok.md"
expect 0 "^lint2: OK$" "lint2: rischio aperto con il suo test = pulito" -- bash "$PC" lint2 "$T/f2-risk-ok.md"
# contract: the format and the open risk lines; format 1 unchanged
expect 0 "^Plan format: 2$" "contract: formato 2 dichiarato in coda" -- bash "$PC" contract "$T/f2.md"
expect 0 "^Rischio: riga [0-9]+ — ⚠️ Rischio aperto: la barra lampeggia — T2$" "contract: il rischio aperto e' un focus di rischio" -- bash "$PC" contract "$T/f2-risk-ok.md"
refute "Plan format" "contract: formato 1, nessuna riga nuova" -- bash "$PC" contract "$T/base.md"

# gen: procedure and mutations.json in the run directory, never in the plan
expect 0 "^mutazioni: 1$" "gen: una mutazione dalla tabella" -- bash "$PC" gen "$T/f2.md"
P2="$T/f2.run/gen/procedura.txt"; MJ="$T/f2.run/counterproof/mutations.json"
expect 0 "^Test level: std$" "gen: livello" -- cat "$P2"
expect 0 "^vitest: tests/bar.test.ts$" "gen: percorsi di vitest-fast.sh relativi ad apps/admin" -- cat "$P2"
expect 0 "^pytest: tests/test_goals.py$" "gen: selettori pytest relativi a modules/api" -- cat "$P2"
# pk04b-2: the commands from the module comandi.test (comando() of maat-config.py), in the command folder, inside WSL
# for the ambiente wsl modules (on Windows), quoted for bash. pk08: outside Windows (Linux) the same lines without WSL,
# in the native form (cd relative to the root, no export of MAAT_CONFIG: the line inherits the environment)
PCWIN=0; case "${OSTYPE:-}:$(uname -s 2>/dev/null)" in *msys*|*cygwin*|*:MINGW*|*:MSYS*|*:CYGWIN*) PCWIN=1 ;; esac
if [ $PCWIN -eq 1 ]; then
expect 0 "^cmd vitest: wsl -- bash -lc 'cd [^ ]*/modules/app/apps/admin && bash '\\\\''[^']*'\\\\''/scripts/test-fast.sh '\\\\''tests/bar.test.ts'\\\\'''$" "gen: comando di test di fe (test-fast.sh del plugin, dalla radice)" -- cat "$P2"
expect 0 "^cmd pytest: wsl -- bash -lc 'cd [^ ]*/modules/api && [^ ]*/modules/api/.venv/bin/python -m pytest -q --junitxml=.*tests-be.junit.xml.* '\\\\''tests/test_goals.py'\\\\'''$" "gen: comando di test di be (python del modulo trovato, --junitxml dichiarato)" -- cat "$P2"
expect 0 "^cmd counterproof: wsl -- bash -lc 'PROJECT_ROOT=[^ ]* bash [^ ]*/scripts/counterproof.sh [^ ]*/f2.run/counterproof/mutations.json'$" "gen: comando della controprova (counterproof.sh del plugin, PROJECT_ROOT)" -- cat "$P2"
else
expect 0 "^cmd vitest: cd modules/app/apps/admin && bash '[^']*'/scripts/test-fast.sh 'tests/bar.test.ts'$" "gen: comando di test di fe, nativo (test-fast.sh del plugin, dalla radice)" -- cat "$P2"
expect 0 "^cmd pytest: cd modules/api && /[^ ]*/modules/api/.venv/bin/python -m pytest -q --junitxml=.*tests-be.junit.xml 'tests/test_goals.py'$" "gen: comando di test di be, nativo (python del modulo trovato, --junitxml dichiarato)" -- cat "$P2"
expect 0 "^cmd counterproof: PROJECT_ROOT=[^ ]* bash /[^ ]*/scripts/counterproof.sh /[^ ]*/f2.run/counterproof/mutations.json$" "gen: comando della controprova, nativo (counterproof.sh del plugin, PROJECT_ROOT)" -- cat "$P2"
refute "^cmd .*wsl" "gen: fuori da Windows nessuna riga passa da WSL" -- cat "$P2"
fi
# review pk04b-2, minor 1: a set MAAT_CONFIG reaches INSIDE WSL also in the test cmd lines (like in_wsl of
# gates.sh and like riga_cp), in WSL form (a path starting with /, not C:/). Counterproof: without the addition
# (mutant) the line starts from the cd, without export
MCR="export MAAT_CONFIG=/[^ ;]*/\\.claude/maat\\.json; cd "
refute "^cmd (vitest|pytest): .*MAAT_CONFIG" "gen: senza MAAT_CONFIG nessun export nelle righe di test" -- cat "$P2"
if [ $PCWIN -eq 0 ]; then
  echo "SALTATO [MAAT_CONFIG dentro WSL nelle righe di test, e la sua controprova]: fuori da Windows nessuna riga passa da WSL"
  refute "^cmd (vitest|pytest): .*MAAT_CONFIG" "gen: fuori da Windows nessun export di MAAT_CONFIG (la riga lo eredita)" -- env MAAT_CONFIG="$R/.claude/maat.json" bash "$PC" gen "$T/f2.md" --run-dir "$T/mc.run"
else
expect 0 "^cmd vitest: wsl -- bash -lc '$MCR" "gen: MAAT_CONFIG dentro WSL nella riga vitest" -- env MAAT_CONFIG="$R/.claude/maat.json" bash "$PC" gen "$T/f2.md" --run-dir "$T/mc.run"
expect 0 "^cmd pytest: wsl -- bash -lc '$MCR" "gen: MAAT_CONFIG dentro WSL nella riga pytest" -- cat "$T/mc.run/gen/procedura.txt"
if mutpc mcfg 's/^    if wsl and os.environ.get("MAAT_CONFIG"):   # outside/    if False:   # MUTANTE outside/'; then
  expect 0 "^cmd vitest: wsl -- bash -lc 'cd " "controprova: senza l'aggiunta di MAAT_CONFIG (mutante) la riga vitest non la porta in WSL" -- env MAAT_ROOT="$PLUGIN_DIR" MAAT_CONFIG="$R/.claude/maat.json" bash "$T/pcm-mcfg/plan-check.sh" gen "$T/f2.md" --run-dir "$T/mc-mut.run"
  refute "^cmd vitest: .*MAAT_CONFIG" "controprova: la riga vitest del mutante non ha MAAT_CONFIG" -- cat "$T/mc-mut.run/gen/procedura.txt"
else echo "FAIL [controprova MAAT_CONFIG: la mutazione non si applica]"; fail=$((fail+1)); fi
fi
# pk08, block A: MAAT_CONFIG relative to the working directory (and with spaces) becomes absolute on entry, in bash, never
# with os.path.abspath of Windows Python: the cp line (and on Windows the cmd line, inside WSL) carries the absolute path,
# not the relative one, which after the cd or inside WSL would no longer be the file. Counterproof: without the normalization
# (mutant) the cp line carries the relative path
mkdir -p "$T/conf con spazi"; cp "$R/.claude/maat.json" "$T/conf con spazi/maat.json"
gen_rel() { # <plan-check.sh> <run dir> [MAAT_ROOT]: gen from the $T folder, with a relative MAAT_CONFIG
  (cd "$T" && export MAAT_CONFIG="conf con spazi/maat.json" && { [ -z "${3:-}" ] || export MAAT_ROOT=$3; } &&
    bash "$1" gen "$T/f2.md" --run-dir "$2" >/dev/null 2>&1); cat "$2/gen/procedura.txt"; }
MCA="MAAT_CONFIG=('\\\\''|')?/[^;']*/conf con spazi/maat\\.json"
expect 0 "^cmd counterproof: .*PROJECT_ROOT=[^ ]* $MCA" "gen: MAAT_CONFIG relativo e con spazi -> assoluto nella riga cp" -- gen_rel "$PC" "$T/rel.run"
case "${OSTYPE:-}:$(uname -s 2>/dev/null)" in
  *msys*|*cygwin*|*:MINGW*|*:MSYS*|*:CYGWIN*)
    expect 0 "^cmd pytest: wsl -- bash -lc 'export $MCA('\\\\''|')?; cd " "gen: MAAT_CONFIG relativo e con spazi -> assoluto (forma WSL) nella riga cmd" -- cat "$T/rel.run/gen/procedura.txt" ;;
  *) echo "SALTATO [MAAT_CONFIG relativo nella riga cmd]: fuori da Windows la riga non esporta MAAT_CONFIG (la eredita)" ;;
esac
if mutpc mcrel 's/^    \/\*|\[A-Za-z\]:\[\/\\\\\]\*) ;;$/    *) ;;   # MUTANTE: nessuna normalizzazione/'; then
  expect 0 "^cmd counterproof: .*MAAT_CONFIG=('\\\\''|')?conf con spazi/maat\\.json" "controprova: senza la normalizzazione (mutante) la riga cp porta il percorso relativo" -- gen_rel "$T/pcm-mcrel/plan-check.sh" "$T/rel-mut.run" "$PLUGIN_DIR"
else echo "FAIL [controprova MAAT_CONFIG relativo: la mutazione non si applica]"; fail=$((fail+1)); fi
# review pk04b-2, minor 7: a {python} by name (python3, first candidate without /) cannot be verified in WSL from here
# (gates.sh looks for it in the WSL PATH): the line declares it in a trailing comment. Counterproof: with the name taken as
# verified (mutant) the comment disappears and the line ends with the quote
"$FIC_PY" -c 'import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
for m in c["moduli"]:
    if m["nome"] == "be":
        m["python"] = ["python3", ".venv/bin/python"]
json.dump(c, open(sys.argv[2], "w", encoding="utf-8"), indent=1)' "$R/.claude/maat.json" "$T/conf-py3.json"
NV="'  # non verificato: python3 cercato nel PATH di WSL solo da gates\\.sh$"
refute "non verificato" "gen: python trovato come file (.venv/bin/python): nessuna dichiarazione" -- cat "$P2"
if [ $PCWIN -eq 0 ]; then   # pk08: without WSL the name is searched in the local PATH, so it is verified (absolute path)
  echo "SALTATO [python per nome «non verificato», e la sua controprova]: fuori da Windows il nome si verifica nel PATH locale"
  expect 0 "^cmd pytest: cd modules/api && /[^ ]*python3 -m pytest .*'$" "gen: python per nome, nativo: risolto a percorso assoluto" -- env MAAT_CONFIG="$T/conf-py3.json" bash "$PC" gen "$T/f2.md" --run-dir "$T/py3.run"
  refute "non verificato" "gen: python per nome, nativo: nessuna dichiarazione" -- cat "$T/py3.run/gen/procedura.txt"
else
expect 0 "^cmd pytest: wsl -- bash -lc '.* python3 -m pytest .*$NV" "gen: python per nome dichiarato non verificato" -- env MAAT_CONFIG="$T/conf-py3.json" bash "$PC" gen "$T/f2.md" --run-dir "$T/py3.run"
if mutpc py3 's/^            return c, False$/            return c, True   # MUTANTE/'; then
  expect 0 "^cmd pytest: wsl -- bash -lc '.* python3 -m pytest .*'$" "controprova: col nome dato per verificato (mutante) la riga non dichiara nulla" -- env MAAT_ROOT="$PLUGIN_DIR" MAAT_CONFIG="$T/conf-py3.json" bash "$T/pcm-py3/plan-check.sh" gen "$T/f2.md" --run-dir "$T/py3-mut.run"
  refute "non verificato" "controprova: nessun «non verificato» nel mutante" -- cat "$T/py3-mut.run/gen/procedura.txt"
else echo "FAIL [controprova python per nome: la mutazione non si applica]"; fail=$((fail+1)); fi
fi
expect 0 "^blocco B2: scrive=modules/app/apps/admin/components/Bar.vue,modules/app/apps/admin/tests/bar.test.ts · dopo=B1$" "gen: blocchi con scrive e dopo" -- cat "$P2"
fpcur=$(bash "$PC" basis "$T/f2.md" | sed -n 's/.*plan \([0-9a-f]*\).*/\1/p')
expect 0 "^Impronta piano: $fpcur$" "gen: impronta del piano" -- cat "$P2"
refute "cmd lint" "gen: lint solo a full" -- cat "$P2"
# mutations.json valid for counterproof.sh: validated by its own prep function (pt05)
CPS="$HERE/counterproof.sh"
awk "/^PY='\$/{f=1;next} f&&/^'\$/{exit} f" "$CPS" > "$T/cp.py"
# 1.4.0: that Python imports the message catalog from MAAT_MSG_PY, as counterproof.sh exports it (native form)
MAAT_MSG_PY=$(cygpath -m "$HERE/maat_msg.py" 2>/dev/null || printf '%s' "$HERE/maat_msg.py"); export MAAT_MSG_PY
mkdir -p "$T/cptmp" "$T/cpout"
# prep summary (pk04b-2, block A): groups, runnable entries, absorbed, NOT RUN; the modules in <tmp>/mods
expect 0 "^1 1 0 0$" "gen: mutations.json accettato da counterproof.sh (prep: 1 gruppo, 0 assorbite)" -- "$FIC_PY" "$T/cp.py" prep "$MJ" "$R" "$T/cptmp" "$T/cpout"
expect 0 "^be$" "gen: la mutazione e' del modulo be (pytest)" -- cat "$T/cptmp/mods"
expect 0 '"test_id": "modules/api/tests/test_goals.py::test_update_denied"' "gen: test_id pytest = node id" -- cat "$MJ"
expect 0 '"superficie": "permessi"' "gen: la riga [pavimento:] che nomina il test da' la superficie" -- cat "$MJ"
# counterproof of the validator: a list without rosso_se is rejected (exit 64)
printf '%s\n' '[{"id": "T1", "file": "modules/api/app/routers/goals.py", "simbolo": "x", "mutazione": {"cerca": "a", "sostituisci": "b"}, "test": {"percorso": "modules/api/tests/test_goals.py"}}]' > "$T/cpout/bad.json"
expect 64 "rosso_se" "gen: controprova, prep rifiuta una lista malformata" -- "$FIC_PY" "$T/cp.py" prep "$T/cpout/bad.json" "$R" "$T/cptmp2" "$T/cpout"
# a frontend mutation: test_id = vitest name, vitest runner
sed 's/^| T2 | RF2 | \(.*\) | — |$/| T2 | RF2 | \1 | `modules\/app\/apps\/admin\/components\/Bar.vue` · `Bar` · `goals-company-bar` → `x` · rosso se: `expected false to be true` |/' "$T/f2.md" > "$T/f2-fe.md"
expect 0 "^mutazioni: 2$" "gen: due mutazioni" -- bash "$PC" gen "$T/f2-fe.md"
expect 0 "^2 2 0 0$" "gen: mutations.json con vitest e pytest accettato da prep" -- "$FIC_PY" "$T/cp.py" prep "$T/f2-fe.run/counterproof/mutations.json" "$R" "$T/cptmp3" "$T/cpout"
expect 0 "^fe be $" "gen: le due mutazioni sono dei moduli fe e be" -- bash -c 'tr "\n" " " < "$1"; echo' _ "$T/cptmp3/mods"
expect 0 '"test_id": "bar"' "gen: test_id vitest = nome del test" -- cat "$T/f2-fe.run/counterproof/mutations.json"
# no mutation: the mutations.json generated earlier disappears
sed 's/^\(| T1 | RF1 | .* | rosso se: il venditore aggiorna | \).*$/\1— |/' "$T/f2.md" > "$T/f2-nomut.md"
mkdir -p "$T/f2-nomut.run/counterproof"; cp "$MJ" "$T/f2-nomut.run/counterproof/mutations.json"
expect 0 "^mutazioni: 0$" "gen: nessuna mutazione" -- bash "$PC" gen "$T/f2-nomut.md"
expect 1 - "gen: il mutations.json vecchio e' tolto" -- test -e "$T/f2-nomut.run/counterproof/mutations.json"
expect 1 "VIOLAZIONE: riga [0-9]+: test T1: asserzione senza testo fra backtick e senza mutazione" "lint2: asserzione senza backtick e senza mutazione = VIOLAZIONE (test-red non potrebbe dimostrarla)" -- bash "$PC" lint2 "$T/f2-nomut.md"
expect 1 "VIOLAZIONE: riga [0-9]+: test T1: mutazione illeggibile" "gen: riga malformata = uscita 1" -- bash "$PC" gen "$T/f2-badmut.md" --run-dir "$T/badrun"
expect 1 - "gen: con una riga malformata non scrive nulla" -- test -e "$T/badrun/gen/procedura.txt"
expect 0 "^gen: non si applica" "gen: piano in formato 1 = non si applica" -- bash "$PC" gen "$T/base.md" --run-dir "$T/f1run"
expect 1 - "gen: formato 1, nessun file" -- test -e "$T/f1run/gen/procedura.txt"
sed 's/^Test level: std$/Test level: full/' "$T/f2.md" > "$T/f2-full.md"
if [ $PCWIN -eq 1 ]; then
expect 0 "^cmd lint: wsl -- bash -lc 'cd [^ ]*/repo && bash .*/scripts/test-fast.sh --lint '\\\\''modules/app/apps/admin/components/Bar.vue'\\\\'' '\\\\''modules/app/apps/admin/tests/bar.test.ts'\\\\'''$" "gen: a full anche il lint dei file toccati del modulo (comandi.lint di fe)" -- bash "$PC" gen "$T/f2-full.md"
else
expect 0 "^cmd lint: bash '[^']*'/scripts/test-fast.sh --lint 'modules/app/apps/admin/components/Bar.vue' 'modules/app/apps/admin/tests/bar.test.ts'$" "gen: a full anche il lint dei file toccati del modulo, nativo (comandi.lint di fe)" -- bash "$PC" gen "$T/f2-full.md"
fi
# pk04b-2 (maintainer decision, option a): EQUIVALENCE with the previous harness (plan-check.sh at 0eed7b6, hard-wired
# ADMIN/API): same vitest:/pytest:/altri: lists, same mutations.json and, for each cmd line, same type, same
# working directory (hence the same module) and same files in the same order. Allowed differences: the interpreter,
# --junitxml, the quoting style (and the explicit cd: before, vitest-fast.sh started from apps/admin by itself).
OLDPC="$T/pc-old/plan-check.sh"; mkdir -p "$T/pc-old/lib"; cp "$HERE/lib/maat-paths.sh" "$T/pc-old/lib/"
# a copy without .git, or with a history lacking 0eed7b6, has no reference: motivated SKIP, not FAIL (review
# pk04b-2, minor 6). With the commit present, an empty extraction is still a FAIL (below)
EQ_SKIP=0
if ! git -c safe.directory='*' -C "$HERE" rev-parse --git-dir >/dev/null 2>&1; then
  EQ_SKIP=1; echo "SKIP [gen: equivalenza col harness di prima — $HERE non e' in un repository git: nessun riferimento 0eed7b6]"
elif ! git -c safe.directory='*' -C "$HERE" cat-file -e 0eed7b6:plugins/maat/scripts/plan-check.sh 2>/dev/null; then
  EQ_SKIP=1; echo "SKIP [gen: equivalenza col harness di prima — il repository non ha 0eed7b6:plugins/maat/scripts/plan-check.sh]"
else
  git -c safe.directory='*' -C "$HERE" show 0eed7b6:plugins/maat/scripts/plan-check.sh > "$OLDPC" 2>/dev/null
fi
cat > "$T/normcmd.py" <<'EOF'
import re, shlex, sys
proc, root = sys.argv[1], sys.argv[2].replace("\\", "/").rstrip("/")
m = re.match(r"^([A-Za-z]):/(.*)$", root)
radici = [root] + (["/mnt/%s/%s" % (m.group(1).lower(), m.group(2))] if m else [])
PRIMA = {"vitest": "modules/app/apps/admin", "lint": "", "counterproof": ""}   # implicit directory of vitest-fast.sh
def rel(d):
    for r in radici:
        if d == r or d.startswith(r + "/"):
            return d[len(r) + 1:]
    return d
for l in open(proc, encoding="utf-8").read().splitlines():
    if not l.startswith("cmd "):
        if re.match(r"^(vitest|pytest|altri|mutazioni):", l):
            print(l)
        continue
    k, c = l[4:].split(": ", 1)
    t = shlex.split(c)
    if t[:4] == ["wsl", "--", "bash", "-lc"]:
        t = shlex.split(t[4])
    wd = PRIMA.get(k)
    if t[:1] == ["cd"]:
        wd, t = rel(t[1]), t[3:]
    # only the .py/.ts/.vue/.json tokens are kept: the test selectors, the files of the test plans (f2, f2-fe, f2-full
    # touch only .py, .ts and .vue) and mutations.json; interpreter, options and plugin scripts are left out. The lint
    # list is NOT compared by extension and its difference is intended: before it held only the lintable files of
    # modules/app/ (.ts/.tsx/.js/.mjs/.cjs/.vue), now every file of the plan of the module with comandi.lint (as gates.sh does),
    # and test-fast.sh --lint declares the non-lintable extensions SKIPPED. On the test plans the two lists coincide
    f = [x[x.rfind("counterproof/"):] if x.endswith("mutations.json") else x for x in t
         if re.search(r"\.(py|ts|vue|json)$", x) and "/scripts/" not in x and "/script/" not in x]
    print("%s | %s | %s" % (k, wd, " ".join(f)))
EOF
equiv() { # <new plan-check.sh> <spec>: lines that differ from the previous harness (empty = equivalent)
  local s=$2 n a b; n=$(basename "$2" .md)
  env MAAT_ROOT="$PLUGIN_DIR" bash "$OLDPC" gen "$s" --run-dir "$T/eq-old-$n.run" >/dev/null 2>&1 || { echo "harness di prima: gen fallito"; return; }
  env MAAT_ROOT="$PLUGIN_DIR" bash "$1" gen "$s" --run-dir "$T/eq-new-$n.run" >/dev/null 2>&1 || { echo "gen fallito"; return; }
  a=$("$FIC_PY" "$T/normcmd.py" "$T/eq-old-$n.run/gen/procedura.txt" "$R" | tr -d '\r')
  b=$("$FIC_PY" "$T/normcmd.py" "$T/eq-new-$n.run/gen/procedura.txt" "$R" | tr -d '\r')
  diff <(printf '%s\n' "$a") <(printf '%s\n' "$b")
  cmp -s "$T/eq-old-$n.run/counterproof/mutations.json" "$T/eq-new-$n.run/counterproof/mutations.json" || echo "mutations.json diverso"
}
if [ "$EQ_SKIP" = 1 ]; then
  :   # SKIP declared above
elif [ -s "$OLDPC" ]; then
  for s in f2 f2-fe f2-full; do
    d=$(equiv "$PC" "$T/$s.md")
    [ -z "$d" ] && pass=$((pass+1)) || { echo "FAIL [gen: equivalenza col harness di prima su $s.md]"; printf '%s\n' "$d" | sed 's/^/    /'; fail=$((fail+1)); }
  done
  # counterproof: a wrong module for the tests (all in the fe module, as with ADMIN hard-wired for every path) =>
  # the pytest test ends up in a vitest cmd line from apps/admin, the equivalence fails
  if mutpc modsbagliato 's/^        mt, kt = modulo(p)$/        mt, kt = modulo("modules\/app\/apps\/admin\/x.ts")/'; then
    d=$(equiv "$T/pcm-modsbagliato/plan-check.sh" "$T/f2.md")
    [ -n "$d" ] && pass=$((pass+1)) || { echo "FAIL [controprova: col modulo sbagliato l'equivalenza deve fallire]"; fail=$((fail+1)); }
  else echo "FAIL [controprova equivalenza: la mutazione non si applica]"; fail=$((fail+1)); fi
else echo "FAIL [gen: harness di prima (0eed7b6) non estraibile da git]"; fail=$((fail+1)); fi
# quoting: a run dir with spaces stays ONE argument inside wsl -- bash -lc '…' (quotes of espandi re-quoted). The
# line is analysed with bash -n and executed with fake wsl, bash and cd that print the final arguments.
bash "$PC" gen "$T/f2.md" --run-dir "$T/run con spazi" >/dev/null 2>&1
riga_di() { sed -n "s/^cmd $1: //p" "$T/run con spazi/gen/procedura.txt"; }
prova() { ( wsl() { [ "$1" = -- ] && shift; "$@"; }; bash() { if [ "$1" = -lc ]; then eval "$2"; else printf '[%s]\n' "$@"; fi; }
            cd() { printf 'CD[%s]\n' "$1"; }; eval "$1" ) 2>&1; }
o=$(prova "$(riga_di counterproof)")
command bash -n -c "$(riga_di counterproof)" && printf '%s\n' "$o" | grep -qx "\[.*/run con spazi/counterproof/mutations.json\]" && pass=$((pass+1)) ||
  { echo "FAIL [gen: riga counterproof con una run dir con spazi: un solo argomento]"; printf '%s\n' "$o" | sed 's/^/    /'; fail=$((fail+1)); }
o=$(prova "$(riga_di vitest)")
command bash -n -c "$(riga_di vitest)" && printf '%s\n' "$o" | grep -qxE "CD\[(.*/)?modules/app/apps/admin\]" && printf '%s\n' "$o" | grep -qx "\[tests/bar.test.ts\]" && pass=$((pass+1)) ||
  { echo "FAIL [gen: riga vitest: cd e argomenti integri dopo la ri-quotatura]"; printf '%s\n' "$o" | sed 's/^/    /'; fail=$((fail+1)); }

# route (L5): surfaces from the paths, disagreement = full path
expect 0 "^Superfici rilevate: permessi, contratto-api$" "route: un file sotto routers/ = permessi e contratto-api" -- bash "$PC" route "$T/f2.md"
expect 0 "^Percorso: pieno — .*superfici rilevate: permessi, contratto-api" "route: superfici rilevate = percorso pieno" -- bash "$PC" route "$T/f2.md"
refute "^Discordanza" "route: dichiarazione concorde, nessuna discordanza" -- bash "$PC" route "$T/f2.md"
sed 's/^Superfici a rischio: permessi, contratto-api$/Superfici a rischio: nessuna/' "$T/f2.md" > "$T/f2-decl.md"
expect 0 "^Discordanza: rilevata e non dichiarata: permessi, contratto-api$" "route: discordanza con la dichiarazione" -- bash "$PC" route "$T/f2-decl.md"
expect 0 "^Percorso: pieno — .*discordanza con la dichiarazione" "route: discordanza = percorso pieno" -- bash "$PC" route "$T/f2-decl.md"
printf '%s\n' "# T" "## Piano di implementazione" "Plan status: DRAFT" "Test level: min" "Superfici a rischio: nessuna" \
  "1. In \`modules/app/apps/admin/components/Bar.vue\` cambia il testo." > "$T/light.md"
expect 0 "^Percorso: leggero" "route: piano piccolo, nessuna superficie, dichiarazione nessuna = leggero" -- bash "$PC" route "$T/light.md"
# 1.4.0 English twin: the keyword stays (D2), the explanation follows the language
expect 0 "^Percorso: leggero — plan within 150 lines, no migration, no surface detected, declaration consistent$" "en (MAAT_LINGUA=en) route: Percorso: leggero e la spiegazione in inglese" -- env MAAT_LINGUA=en bash "$PC" route "$T/light.md"
expect 0 "^Percorso: pieno — .*mismatch with the declaration" "en (MAAT_LINGUA=en) route: Percorso: pieno e il motivo in inglese" -- env MAAT_LINGUA=en bash "$PC" route "$T/f2-decl.md"
refute "nessuna migrazione|discordanza con|Righe del piano" "en (MAAT_LINGUA=en) route: nessuna spiegazione italiana" -- env MAAT_LINGUA=en bash "$PC" route "$T/f2-decl.md"
sed 's/^1\. In `modules\/app\/apps\/admin\/components\/Bar.vue`/1. In `modules\/app\/packages\/ui\/Bar.vue`/' "$T/light.md" > "$T/light-pkg.md"
expect 0 "^Superfici rilevate: logica-condivisa$" "route: modules/app/packages/ = logica-condivisa" -- bash "$PC" route "$T/light-pkg.md"
sed 's/^1\. In `modules\/app\/apps\/admin\/components\/Bar.vue`/1. In `modules\/app\/apps\/admin\/utils\/adminRouteRoles.ts`/' "$T/light.md" > "$T/light-role.md"
expect 0 "^Superfici rilevate: permessi$" "route: la mappa dei ruoli usata dal middleware = permessi" -- bash "$PC" route "$T/light-role.md"
printf '%s\n' "2. Esegue DELETE FROM goals." >> "$T/light.md"
expect 0 "^Superficie distruttiva: parola chiave DELETE \(piano riga 7\)$" "route: DELETE nel piano = distruttiva" -- bash "$PC" route "$T/light.md"
expect 0 "^Percorso: pieno" "route: distruttiva = percorso pieno" -- bash "$PC" route "$T/light.md"
printf '%s\n' "# T" "## Piano di implementazione" "Plan status: DRAFT" "Superfici a rischio: nessuna" "- \`modules/db/prisma/migrations/20260929_x/migration.sql\`" > "$T/mig.md"
expect 0 "^Migrazione: modules/db/prisma/migrations/20260929_x/migration.sql$" "route: migrazione rilevata" -- bash "$PC" route "$T/mig.md"
printf '%s\n' "diff --git a/modules/api/app/models/goal.py b/modules/api/app/models/goal.py" "+    x.delete()" > "$T/d.diff"
head -6 "$T/light.md" > "$T/light2.md"
expect 0 "^Superfici rilevate: distruttiva, contratto-api$" "route: --diff aggiunge percorsi e parole chiave" -- bash "$PC" route "$T/light2.md" --diff "$T/d.diff"
{ head -5 "$T/light2.md"; for i in $(seq 1 150); do echo "riga $i"; done; } > "$T/long.md"
expect 0 "^Percorso: pieno — piano di 1[0-9][0-9] righe \(oltre 150\)" "route: piano oltre 150 righe = pieno" -- bash "$PC" route "$T/long.md"
# pk04b-2: surfaces and migrations from piano.superfici_critiche and piano.migrazioni of maat.json. Equivalence with the
# previous hard-wired rules (surf_of and is_mig of the harness, copied here as reference): for every path of the corpus
# (one per rule, the exceptions, a neutral path) the same surfaces and the same migration.
"$FIC_PY" -c '
import re, sys
API = "modules/api/"
def surf_of(p):
    q_ = "/" + p
    s = set()
    if "/routers/" in q_:
        s |= {"permessi", "contratto-api"}
    if q_.endswith("/core/security.py") or q_.endswith("/core/context_guard.py"):
        s.add("permessi")
    if not p.startswith(API) and ("/middleware/" in q_ or "/composables/useRole/" in q_
                                  or re.search(r"/utils/(adminRouteRoles|contextlessAdmin|rankingRowAccess)\.ts$", q_)):
        s.add("permessi")
    if q_.endswith("/schema.prisma") or "/prisma/migrations/" in q_ or "/script/migrations/" in q_ or q_.endswith("/services/database.py"):
        s.add("dati")
    if "/models/" in q_ and not p.startswith("modules/app/"):
        s.add("contratto-api")
    if p.startswith("modules/app/packages/") or p.startswith("packages/"):
        s.add("logica-condivisa")
    return s
def is_mig(p):
    q_ = "/" + p
    return q_.endswith("/schema.prisma") or "/prisma/migrations/" in q_ or "/script/migrations/" in q_
VOCAB = ["permessi", "dati", "distruttiva", "contratto-api", "import", "logica-condivisa"]
for p in sys.argv[1:]:
    print("%s|%s|%s" % (p, ", ".join(s for s in VOCAB if s in surf_of(p)) or "nessuna", p if is_mig(p) else "no"))
' modules/api/app/routers/goals.py routers/x.py modules/api/app/core/security.py modules/api/app/core/context_guard.py \
  modules/app/apps/admin/middleware/auth.ts modules/app/apps/admin/composables/useRole/x.ts \
  modules/app/apps/admin/utils/adminRouteRoles.ts modules/app/apps/admin/utils/contextlessAdmin.ts \
  modules/app/apps/admin/utils/rankingRowAccess.ts modules/api/app/middleware/x.py modules/api/app/utils/adminRouteRoles.ts \
  modules/db/prisma/schema.prisma modules/db/prisma/migrations/2026_x/migration.sql script/migrations/x.md \
  modules/api/app/services/database.py modules/api/app/models/goal.py modules/app/apps/admin/models/x.ts \
  modules/app/packages/ui/Bar.vue packages/x/y.ts docs/guida/nota.md | tr -d '\r' > "$T/sup-rif.txt"
sup_eq() { # [MAAT_CONFIG=…] → the corpus lines on which plan-check.sh route differs from the reference
  local p s m e
  while IFS='|' read -r p s m; do
    printf '%s\n' "# T" "## Piano di implementazione" "Plan status: DRAFT" "Superfici a rischio: nessuna" "- \`$p\`" > "$T/sup1.md"
    e=$(bash "$PC" route "$T/sup1.md" 2>&1)
    printf '%s\n' "$e" | grep -qxF "Superfici rilevate: $s" && printf '%s\n' "$e" | grep -qxF "Migrazione: $m" || echo "$p: atteso «$s» e migrazione «$m»"
  done < "$T/sup-rif.txt"
}
[ "$(wc -l < "$T/sup-rif.txt")" -eq 20 ] && d=$(sup_eq) && [ -z "$d" ] && pass=$((pass+1)) ||
  { echo "FAIL [route: superfici e migrazioni di maat.json = le regole di prima, percorso per percorso]"; printf '%s\n' "$d" | sed 's/^/    /'; fail=$((fail+1)); }
# counterproof: without the useRole rule in the example the case composables/useRole/x.ts loses permessi
sed 's#|composables/useRole/|#|#' "$R/.claude/maat.json" > "$T/senza-userole.json"
d=$(MAAT_CONFIG="$T/senza-userole.json" sup_eq)
if ! cmp -s "$R/.claude/maat.json" "$T/senza-userole.json" && [ "$d" = "modules/app/apps/admin/composables/useRole/x.ts: atteso «permessi» e migrazione «no»" ]; then pass=$((pass+1))
else echo "FAIL [controprova: senza la regola useRole l'equivalenza delle superfici deve fallire su composables/useRole/x.ts]"; printf '%s\n' "$d" | sed 's/^/    /'; fail=$((fail+1)); fi
# project without maat.json: no surface from the paths (empty default)
printf '%s\n' "# T" "## Piano di implementazione" "Plan status: DRAFT" "Superfici a rischio: nessuna" "- \`modules/api/app/routers/goals.py\`" > "$T/sup1.md"
expect 0 "^Superfici rilevate: nessuna$" "route: progetto senza maat.json = nessuna superficie dai percorsi" -- env PLAN_CHECK_ROOT="$T/nessun-progetto" bash "$PC" route "$T/sup1.md"

# s2: delta and fresh eyes on the same fingerprint, clean; a rejected finding is not clean
rv() { printf '%s\n' "Impronta piano: $1" "Decision: $2" "Coverage statement: tutto" "Blocking findings:"; [ "$3" = 0 ] || printf '%s\n' "1. Severity: major" "   Claim: x"; printf '%s\n' "Optional findings:" "1. Severity: minor"; }
rv "$fpcur" APPROVED 0 > "$T/d-ok"; rv "$fpcur" APPROVED 0 > "$T/g-ok"; rv "$fpcur" NEEDS_CHANGES 1 > "$T/d-one"
expect 0 "^S2: APPROVA" "s2: delta e gate puliti sulla stessa impronta = APPROVA" -- bash "$PC" s2 "$T/f2.md" --delta "$T/d-ok" --gate "$T/g-ok"
expect 0 "^S2: APPROVA — delta and fresh eyes clean on fingerprint [0-9a-f]{12}$" "en (MAAT_LINGUA=en) s2: APPROVA e la spiegazione in inglese" -- env MAAT_LINGUA=en bash "$PC" s2 "$T/f2.md" --delta "$T/d-ok" --gate "$T/g-ok"
expect 0 "^S2: RILANCIA — 1 findings rejected: clean means no finding" "en (MAAT_LINGUA=en) s2: RILANCIA e il motivo in inglese" -- env MAAT_LINGUA=en bash "$PC" s2 "$T/f2.md" --delta "$T/d-one" --gate "$T/g-ok" --respinti 1
refute "puliti sull|pulito vuol dire" "en (MAAT_LINGUA=en) s2: nessuna spiegazione italiana" -- env MAAT_LINGUA=en bash "$PC" s2 "$T/f2.md" --delta "$T/d-one" --gate "$T/g-ok" --respinti 1
expect 0 "^S2: RILANCIA — 1 finding respinti" "s2: un delta con un respinto NON approva (regola dei respinti)" -- bash "$PC" s2 "$T/f2.md" --delta "$T/d-one" --gate "$T/g-ok" --respinti 1
expect 0 "^S2: CORREGGI — 1 blocker/major" "s2: finding non respinto = CORREGGI" -- bash "$PC" s2 "$T/f2.md" --delta "$T/d-one" --gate "$T/g-ok"
rv 000000000000 APPROVED 0 > "$T/g-old"
expect 0 "^S2: IMPRONTA DIVERSA" "s2: gate su un'altra impronta = non approva" -- bash "$PC" s2 "$T/f2.md" --delta "$T/d-ok" --gate "$T/g-old"
expect 0 "^S2: IMPRONTA DIVERSA" "s2: piano cambiato dopo il lancio = non approva" -- bash "$PC" s2 "$T/f2-full.md" --delta "$T/d-ok" --gate "$T/g-ok"
{ cat "$T/g-ok"; echo "Blocked on: budget"; } > "$T/g-part"
expect 0 "^S2: RILANCIA — risposta parziale" "s2: risposta parziale = non approva" -- bash "$PC" s2 "$T/f2.md" --delta "$T/d-ok" --gate "$T/g-part"
{ cat "$T/g-ok"; echo "Blocked on: none"; } > "$T/g-none"
expect 0 "^S2: APPROVA" "s2: 'Blocked on: none' non e' una risposta parziale" -- bash "$PC" s2 "$T/f2.md" --delta "$T/d-ok" --gate "$T/g-none"
rv "$fpcur" STOP_HUMAN_DECISION_REQUIRED 0 > "$T/g-stop"
expect 0 "^S2: STOP" "s2: decisione umana = STOP" -- bash "$PC" s2 "$T/f2.md" --delta "$T/d-ok" --gate "$T/g-stop"
expect 2 "respinti" "s2: piu' respinti che finding = errore d'uso" -- bash "$PC" s2 "$T/f2.md" --delta "$T/d-ok" --gate "$T/g-ok" --respinti 1

# ── skeleton (harness-pt12): skeleton below or above the cap, and the full plan within 400 lines ──────────────
expect 0 "^Scheletro: SOTTO IL TETTO" "skeleton: 3 passi, 4 file = sotto il tetto (uscita 0)" -- bash "$PC" skeleton "$T/f2.md"
expect 0 "^Scheletro: SOTTO IL TETTO — the full plan starts from this skeleton$" "en (MAAT_LINGUA=en) skeleton: SOTTO IL TETTO e la spiegazione in inglese" -- env MAAT_LINGUA=en bash "$PC" skeleton "$T/f2.md"
expect 0 "^Steps: 3 \(cap 15\)$" "en (MAAT_LINGUA=en) skeleton: i conteggi in inglese" -- env MAAT_LINGUA=en bash "$PC" skeleton "$T/f2.md"
refute "il piano completo parte|tetto 15" "en (MAAT_LINGUA=en) skeleton: nessuna spiegazione italiana" -- env MAAT_LINGUA=en bash "$PC" skeleton "$T/f2.md"
expect 0 "^Passi: 3 \(tetto 15\)$" "skeleton: conta i passi" -- bash "$PC" skeleton "$T/f2.md"
expect 0 "^File: 4 \(tetto 40\)$" "skeleton: conta i file (File toccati + passi)" -- bash "$PC" skeleton "$T/f2.md"
expect 0 "^Superfici: permessi, contratto-api$" "skeleton: le superfici dichiarate" -- bash "$PC" skeleton "$T/f2.md"
awk '{ print } /^\| P3 \|/ { for (i = 4; i <= 16; i++) printf "| P%d | `modules/app/apps/admin/components/Bar.vue` | x | T2 |\n", i }' "$T/f2.md" > "$T/sk-passi.md"
expect 1 "^Scheletro: SOPRA IL TETTO — passi 16 > 15: proposta di taglio" "skeleton: 16 passi = sopra il tetto (uscita 1)" -- bash "$PC" skeleton "$T/sk-passi.md"
awk '{ print } /^### File toccati$/ { for (i = 1; i <= 37; i++) printf "- `modules/app/apps/admin/components/F%d.vue`\n", i }' "$T/f2.md" > "$T/sk-file.md"
expect 1 "^Scheletro: SOPRA IL TETTO — file 41 > 40" "skeleton: 41 file = sopra il tetto" -- bash "$PC" skeleton "$T/sk-file.md"
awk '{ print } /^### File toccati$/ { for (i = 1; i <= 36; i++) printf "- `modules/app/apps/admin/components/F%d.vue`\n", i }' "$T/f2.md" > "$T/sk-file40.md"
expect 0 "^File: 40 \(tetto 40\)$" "skeleton: controprova, 40 file = ancora sotto" -- bash "$PC" skeleton "$T/sk-file40.md"
awk '{ print } /^Il 403 vale/ { for (i = 1; i <= 400; i++) print "Decisione " i "." }' "$T/f2.md" > "$T/sk-righe.md"
expect 1 "^Scheletro: SOPRA IL TETTO — righe del piano 4[0-9][0-9] > 400" "skeleton: piano completo oltre 400 righe = di nuovo sopra (nessuna deroga)" -- bash "$PC" skeleton "$T/sk-righe.md"
expect 0 "^skeleton: non si applica" "skeleton: piano in formato 1 = non si applica" -- bash "$PC" skeleton "$T/base.md"
sed 's/^# Titolo$/&\nTaglio: rifiutato — 2026-09-29, piano unico/' "$T/sk-passi.md" > "$T/sk-rifiutato.md"
expect 0 "^Scheletro: SOPRA IL TETTO — passi 16 > 15: taglio rifiutato dall utente" "skeleton: taglio rifiutato (riga Taglio:) = sopra il tetto ma nessuno stop (uscita 0)" -- bash "$PC" skeleton "$T/sk-rifiutato.md"
expect 0 "^Taglio: rifiutato — 2026-09-29, piano unico$" "skeleton: la decisione e' riportata" -- bash "$PC" skeleton "$T/sk-rifiutato.md"
sed 's/^# Titolo$/&\n```text\nTaglio: rifiutato — esempio\n```/' "$T/sk-passi.md" > "$T/sk-rif-fence.md"
expect 1 "SOPRA IL TETTO — passi 16 > 15: proposta di taglio" "skeleton: controprova, la riga dentro un recinto non vale" -- bash "$PC" skeleton "$T/sk-rif-fence.md"

# ── split (harness-pt12): every RF and CA of the parent in one and only one child ──────────────────────────────────────
C="$T/catena"; mkdir -p "$C"
printf '%s\n' "# Madre" "## Contesto" "Grande." "## 2. Requisiti funzionali" "### RF1 — uno" "Testo." "### RF2 — due" "- **RF2.1** dettaglio" \
  "### RF3 — tre" "## Criteri di accettazione" "- CA1 — si vede" "- CA2 — si salva" "## Fuori scope" "- RF9 non e' un requisito qui" > "$C/spec-m.md"
kid() { # $1 file, $2 Dipende da, $3 Interfaccia per, then the IDs (RF… or CA…)
  local f=$1 dep=$2 itf=$3 i; shift 3
  { printf '%s\n' "# Figlia" "Dipende da: $dep" "Interfaccia per: $itf" "## Requisiti funzionali"
    for i in "$@"; do case $i in RF*) printf '1. %s — testo\n' "$i" ;; esac; done
    printf '%s\n' "## Criteri di accettazione"
    for i in "$@"; do case $i in CA*) printf -- '- %s — testo\n' "$i" ;; esac; done; } > "$f"
}
kid "$C/spec-m-1-a.md" nessuno '`src/x.py` — api' RF1 RF2 RF2.1 CA1
kid "$C/spec-m-2-b.md" spec-m-1-a nessuna RF3 CA2
expect 0 "^split: OK — 6 ID della madre in 2 figlie" "split: partizione esatta (titoli, voci puntate, CA)" -- bash "$PC" split "$C/spec-m.md" "$C/spec-m-1-a.md" "$C/spec-m-2-b.md"
kid "$C/spec-m-2-b.md" spec-m-1-a nessuna CA2
expect 1 "VIOLAZIONE: RF3 della madre non sta in nessuna figlia \(perso\)" "split: un RF perso = STOP (uscita 1)" -- bash "$PC" split "$C/spec-m.md" "$C/spec-m-1-a.md" "$C/spec-m-2-b.md"
kid "$C/spec-m-2-b.md" spec-m-1-a nessuna RF3 RF1 CA2
expect 1 "VIOLAZIONE: RF1 sta in 2 figlie: spec-m-1-a spec-m-2-b \(duplicato\)" "split: un RF duplicato = STOP" -- bash "$PC" split "$C/spec-m.md" "$C/spec-m-1-a.md" "$C/spec-m-2-b.md"
kid "$C/spec-m-2-b.md" spec-m-1-a nessuna RF3 RF4 CA2
expect 1 "VIOLAZIONE: spec-m-2-b: RF4 non e' un ID della madre" "split: una figlia che aggiunge un requisito = STOP" -- bash "$PC" split "$C/spec-m.md" "$C/spec-m-1-a.md" "$C/spec-m-2-b.md"
kid "$C/spec-m-2-b.md" spec-m-1-a nessuna RF3 CA2; sed -i '/^Dipende da:/d' "$C/spec-m-2-b.md"
expect 1 "VIOLAZIONE: spec-m-2-b: manca la riga 'Dipende da:'" "split: figlia senza Dipende da: = STOP" -- bash "$PC" split "$C/spec-m.md" "$C/spec-m-1-a.md" "$C/spec-m-2-b.md"
kid "$C/spec-m-2-b.md" spec-m-1-a nessuna RF3 CA2
expect 1 "VIOLAZIONE: figlia ripetuta nella catena: spec-m-1-a" "split: la stessa figlia passata due volte = STOP" -- bash "$PC" split "$C/spec-m.md" "$C/spec-m-1-a.md" "$C/spec-m-1-a.md" "$C/spec-m-2-b.md"
expect 1 "almeno due figlie" "split: madre senza riga Figlie: e senza argomenti = STOP" -- bash "$PC" split "$C/spec-m.md"
sed -i 's/^# Madre$/&\nFiglie: spec-m-1-a, spec-m-2-b/' "$C/spec-m.md"
expect 0 "^split: OK" "split: le figlie dalla riga Figlie: della madre" -- bash "$PC" split "$C/spec-m.md"

# ── basis of a child (harness-pt12, L6): parent, previous ring, interface, touched ───────────────────────
G="$T/catrepo"; mkdir -p "$G/src" "$G/wf"
(cd "$G" && git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false \
  && printf 'x1\n' > src/x.py && printf 'y1\n' > src/y.py && git add -A && git commit -qm init)
export PLAN_CHECK_ROOT="$G"
cp "$C/spec-m.md" "$G/wf/spec-m.md"
{ cat "$C/spec-m-1-a.md"; printf '%s\n' "## Piano di implementazione" "Plan status: APPROVED" "1. Cambia \`src/x.py\`."; } > "$G/wf/spec-m-1-a.md"
{ cat "$C/spec-m-2-b.md"; printf '%s\n' "## Piano di implementazione" "Plan status: APPROVED" "Superfici a rischio: nessuna" "1. Usa \`src/x.py:1\` e \`src/z.py::f\`."; } > "$G/wf/spec-m-2-b.md"
B2="$G/wf/spec-m-2-b.md"
expect 0 "^Catena: anello 2/2 di spec-m · precedente spec-m-1-a \(aperto\)$" "basis: la figlia sa di essere l'anello 2 di 2" -- bash "$PC" basis "$B2"
expect 0 "^Basis: spec [0-9a-f]{12} · plan [0-9a-f]{12} · madre [0-9a-f]{12} · prec [0-9a-f]{12}$" "basis: include madre e piano dell'anello precedente" -- bash "$PC" basis "$B2"
refute "^Catena:" "basis: una spec fuori da una catena non cambia" -- bash "$PC" basis "$T/f2.md"
approve() { local c; c=$(bash "$PC" basis "$1" | sed -n 's/^Basis: //p'); sed -i "/^Approved basis:/d; s/^Superfici a rischio: .*/&\nApproved basis: $c/" "$1"; }
approve "$B2"
expect 0 "^Status: FRESH$" "basis: figlia approvata = FRESH" -- bash "$PC" basis "$B2"
sed -i 's/^### RF1 — uno$/### RF1 — uno, cambiato/' "$G/wf/spec-m.md"
expect 0 "^Status: STALE \(madre\)$" "basis: la madre cambia = tutte le figlie STALE" -- bash "$PC" basis "$B2"
sed -i 's/^### RF1 — uno, cambiato$/### RF1 — uno/' "$G/wf/spec-m.md"
sed -i 's/^1\. Cambia `src\/x.py`\.$/1. Cambia `src\/x.py` e `src\/y.py`./' "$G/wf/spec-m-1-a.md"
expect 0 "^Status: STALE \(prec\)$" "basis: il piano dell'anello precedente riaperto = STALE" -- bash "$PC" basis "$B2"
sed -i 's/^1\. Cambia `src\/x.py` e `src\/y.py`\.$/1. Cambia `src\/x.py`./' "$G/wf/spec-m-1-a.md"
expect 0 "^Status: FRESH$" "basis: controprova, piano precedente ripristinato = FRESH" -- bash "$PC" basis "$B2"
# ring 1 closed: review APPROVED + IMPLEMENTED, touched.txt and .post-tree measured
R1="$G/wf/spec-m-1-a.run"; mkdir -p "$R1/log"
printf '%s\n' "## Review implementazione" "Review status: APPROVED" "Feature status: IMPLEMENTED" >> "$G/wf/spec-m-1-a.md"
expect 1 "^Anello: APERTO — nessuna riga Finalize: IMPLEMENTED$" "closed: APPROVED+IMPLEMENTED senza Finalize = aperto (nessun ripiego legacy)" -- bash "$PC" closed "$G/wf/spec-m-1-a.md"
printf '%s\n' "Reviewed snapshot: base aaa · tree bbb" "Finalize: IMPLEMENTED — snapshot 000000000000 — altro · $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$G/wf/spec-m-1-a.md"
expect 1 "^Anello: APERTO — Finalize su un altro snapshot" "closed: Finalize su un altro snapshot = aperto" -- bash "$PC" closed "$G/wf/spec-m-1-a.md"
SFP1=$(printf '%s' "base aaa · tree bbb" | sha256sum | cut -c1-12)
sed -i "s/snapshot 000000000000 — altro · .*/snapshot $SFP1 — firmato · 2001-01-01T00:00:00Z/" "$G/wf/spec-m-1-a.md"
mkdir -p "$R1/log"; : > "$R1/log/07-review.jsonl"
expect 1 "^Anello: APERTO — Finalize piu' vecchia dell'ultima review lanciata \(07-review\)" "closed: Finalize piu' vecchia dell'ultima review = aperto" -- bash "$PC" closed "$G/wf/spec-m-1-a.md"
sed -i "s/firmato · 2001-01-01T00:00:00Z/firmato · $(date -u +%Y-%m-%dT%H:%M:%SZ)/" "$G/wf/spec-m-1-a.md"; touch -d '2000-01-01' "$R1/log/07-review.jsonl"
expect 0 "^Anello: CHIUSO$" "closed: Finalize IMPLEMENTED fresca sullo snapshot attuale = chiuso" -- bash "$PC" closed "$G/wf/spec-m-1-a.md"
printf 'x2\n' > "$G/src/x.py"; (cd "$G" && git add -A && git write-tree) > "$R1/log/02-implement.post-tree"
printf 'src/y.py\n' > "$R1/touched.txt"
expect 0 "^Status: FRESH$" "L6: anello precedente chiuso, nessun file citato nel suo touched.txt = FRESH" -- bash "$PC" basis "$B2"
printf 'src/x.py\nsrc/y.py\n' > "$R1/touched.txt"
expect 0 "^Status: STALE \(touched: src/x.py\)$" "L6: file citato da k+1 (con :riga) nel touched.txt di k = STALE, giro delta" -- bash "$PC" basis "$B2"
expect 0 "^Basis: .* · interfaccia [0-9a-f]{12}$" "L6: a k chiuso la Basis include l'interfaccia reale" -- bash "$PC" basis "$B2"
approve "$B2"
expect 0 "^Status: FRESH$" "L6: riapprovata dopo il giro delta (interfaccia registrata) = FRESH" -- bash "$PC" basis "$B2"
printf 'x3\n' > "$G/src/x.py"; (cd "$G" && git add -A && git write-tree) > "$R1/log/05-fix.post-tree"
expect 0 "^Status: STALE \(interfaccia\)$" "L6: interfaccia reale diversa da quella registrata = STALE" -- bash "$PC" basis "$B2"
# the same chain with "Interface for:" in place of "Interfaccia per:" gives the same interface fingerprint
IF1=$(bash "$PC" basis "$B2" 2>/dev/null | grep -o 'interfaccia [0-9a-f]\{12\}')
IFF=$(grep -rl '^Interfaccia per:' "$G/wf"); sed -i 's/^Interfaccia per:/Interface for:/' $IFF
IF2=$(bash "$PC" basis "$B2" 2>/dev/null | grep -o 'interfaccia [0-9a-f]\{12\}')
sed -i 's/^Interface for:/Interfaccia per:/' $IFF
[ -n "$IFF" ] && [ -n "$IF1" ] && [ "$IF1" = "$IF2" ] && pass=$((pass+1)) || { echo "FAIL [L6: Interface for: = stessa impronta di Interfaccia per: ('$(printf '%s' "$IF1" | paste -sd'|' -)' / '$(printf '%s' "$IF2" | paste -sd'|' -)', file: $(printf '%s' "$IFF" | paste -sd' ' -))]"; fail=$((fail+1)); }
export PLAN_CHECK_ROOT="$R"
# ── test-red phase (harness-pt11): scope, test fingerprint in the basis, verification of the reds, stubs and L2 ──────────
# Counterproofs by mutation (run by hand with PC=<variant>): without CLASSIFICAZIONE-IMPORT the import case becomes
# «dimostrato» (red here); without CONFRONTO-TESTS the basis stays FRESH with a changed test; without SIMBOLI-TESTATI
# an exported symbol that is not tested is absorbed.
mkdir -p "$R/modules/api/app/services" "$R/modules/app/apps/admin/utils"
printf 'def somma(a, b):\n    return 0\n' > "$R/modules/api/app/services/calc.py"
printf 'from app.services.calc import somma\n\ndef test_somma():\n    assert somma(1, 2) == 3\n' > "$R/modules/api/tests/test_calc.py"
printf "export function fmt(x: number): string {\n  return ''\n}\n" > "$R/modules/app/apps/admin/utils/fmt.ts"
crlf_ok() { [ "$(tr -cd '\r' < "$1" | wc -c)" -eq "$(tr -cd '\n' < "$1" | wc -c)" ] && echo ok; }
printf "import { fmt } from '../utils/fmt'\nit('fmt formatta', () => { expect(fmt(1)).toBe('1,00') })\n" > "$R/modules/app/apps/admin/tests/fmt.test.ts"
spect() {
cat <<'EOF'
# Titolo
## Requisiti funzionali
1. RF1 — la somma.
## Piano di implementazione
Plan format: 2
Plan status: APPROVED
Test level: std
Superfici a rischio: nessuna
### File toccati
- `modules/api/app/services/calc.py` (nuovo)
- `modules/api/tests/test_calc.py` (nuovo)
- `modules/app/apps/admin/utils/fmt.ts` (nuovo)
- `modules/app/apps/admin/tests/fmt.test.ts`
### Passi
#### Blocco B1 — tutto
scrive: `modules/api/app/services/calc.py`, `modules/app/apps/admin/utils/fmt.ts`
dopo: nessuno

| id | file | modifica | test |
|---|---|---|---|
| P1 | `modules/api/app/services/calc.py` | somma | T1, T2 |
### Tracciabilità requisiti
| Req | Passi del piano | Verifica |
|---|---|---|
| RF1 | P1 | T1, T2 |
### Stringhe e data-test
| azione | tipo | valore |
|---|---|---|
| aggiunge | stringa | `Titolo Tred` |
### Piano di test
| ID | requisito | file | asserzione | mutazione |
|---|---|---|---|---|
| T1 | RF1 | `modules/api/tests/test_calc.py::test_somma` (nuovo) | rosso se: la somma e' sbagliata | `modules/api/app/services/calc.py` · `somma` · `return a + b` → `return 0` · rosso se: `assert 0 == 3` |
| T2 | RF1 | `modules/app/apps/admin/tests/fmt.test.ts::fmt formatta` (nuovo) | rosso se: `expected '' to be '1,00'` | — |
EOF
}
spect > "$T/f2t.md"
expect 0 "^test modules/api/tests/test_calc.py$" "accept: i file di test del piano" -- bash "$PC" accept "$T/f2t.md"
expect 0 "^nuovo modules/app/apps/admin/utils/fmt.ts$" "accept: i file nuovi che non sono test (stub)" -- bash "$PC" accept "$T/f2t.md"
refute "^nuovo modules/app/apps/admin/tests/fmt.test.ts" "accept: un test non e' uno stub" -- bash "$PC" accept "$T/f2t.md"
expect 2 "non si applica" "accept: formato 1 = non si applica, uscita 2" -- bash "$PC" accept "$T/base.md"
expect 0 "^Tests status: ASSENTE$" "basis: formato 2 senza tests registrati = ASSENTE" -- bash "$PC" basis "$T/f2t.md"
refute "^Tests" "basis: formato 1 invariato (nessuna riga Tests)" -- bash "$PC" basis "$T/ab.md"
expect 1 "nessuna riga Approved basis" "basis --write-tests: piano senza Approved basis = uscita 1" -- bash "$PC" basis "$T/f2t.md" --write-tests
curt2=$(bash "$PC" basis "$T/f2t.md" | sed -n 's/^Basis: //p')
sed "s/^Superfici a rischio: .*/&\nApproved basis: $curt2/" "$T/f2t.md" | sed 's/$/\r/' > "$T/f2t-crlf.md"
cp "$T/f2t-crlf.md" "$T/f2t.md"
expect 0 "^Tests: [0-9a-f]{12} registrata in Approved basis$" "basis --write-tests: impronta registrata" -- bash "$PC" basis "$T/f2t.md" --write-tests
expect 0 "^Approved basis: spec [0-9a-f]{12} · plan [0-9a-f]{12} · tests [0-9a-f]{12}" "basis --write-tests: in coda alla riga (CRLF: sotto, crlf_ok)" -- cat "$T/f2t.md"
expect 0 "^Status: FRESH$" "basis: con tests registrati e invariati = FRESH" -- bash "$PC" basis "$T/f2t.md"
expect 0 "^Tests status: FRESH$" "basis: Tests status FRESH" -- bash "$PC" basis "$T/f2t.md"
expect 0 "^ok$" "basis --write-tests: nessuna riga senza CR" -- crlf_ok "$T/f2t.md"
printf '\n# commento\n' >> "$R/modules/api/tests/test_calc.py"
expect 0 "^Status: STALE \(tests\)$" "basis: un test di accettazione cambiato = STALE (tests)" -- bash "$PC" basis "$T/f2t.md"
printf 'from app.services.calc import somma\n\ndef test_somma():\n    assert somma(1, 2) == 3\n' > "$R/modules/api/tests/test_calc.py"
# verification of the reds: synthetic evidence as gates.sh writes it (JUnit for tests-be, reporter output for tests-fe)
mkev() { # $1 folder, $2 JUnit testcase, $3 be outcome, $4 vitest log, $5 fe outcome
  mkdir -p "$1"
  printf '<?xml version="1.0"?><testsuites><testsuite name="pytest">%s</testsuite></testsuites>\n' "$2" > "$1/tests-be.junit.xml"
  printf '{"gate":"tests-be","esito":"%s","report":"tests-be.junit.xml","motivo":""}\n' "$3" > "$1/tests-be.json"
  printf '%s\n' "$4" > "$1/tests-fe.log"
  printf '{"gate":"tests-fe","esito":"%s","report":"tests-fe.log","motivo":""}\n' "$5" > "$1/tests-fe.json"
}
JU_RED='<testcase classname="tests.test_calc" name="test_somma"><failure message="assert 0 == 3">E  assert 0 == 3
tests/test_calc.py:4: AssertionError</failure></testcase>'
JU_GREEN='<testcase classname="tests.test_calc" name="test_somma"/>'
JU_IMP='<testcase classname="tests.test_calc" name="test_somma"><failure message="ImportError">ImportError: cannot import name somma
tests/test_calc.py:1: ImportError</failure></testcase>'
FE_RED=" ❯ tests/fmt.test.ts  (1 test | 1 failed) 5ms
⎯⎯⎯⎯⎯⎯⎯ Failed Tests 1 ⎯⎯⎯⎯⎯⎯⎯
 FAIL  tests/fmt.test.ts > fmt formatta
AssertionError: expected '' to be '1,00' // Object.is equality
 ❯ tests/fmt.test.ts:2:43
⎯⎯⎯⎯⎯⎯⎯[1/1]⎯
vitest-fast: esito=FAIL luogo=copia"
mkev "$T/ev-ok" "$JU_RED" FAIL "$FE_RED" FAIL
expect 0 "^rossi: esito=OK" "rossi: tutti rossi sulla loro asserzione = OK" -- bash "$PC" rossi "$T/f2t.md" --evidence "$T/ev-ok"
expect 0 "^rosso T1: dimostrato modules/api/tests/test_calc.py:4" "rossi: ID e posizione del rosso (pytest)" -- bash "$PC" rossi "$T/f2t.md" --evidence "$T/ev-ok"
expect 0 "^rosso T2: dimostrato modules/app/apps/admin/tests/fmt.test.ts:2" "rossi: ID e posizione del rosso (vitest)" -- bash "$PC" rossi "$T/f2t.md" --evidence "$T/ev-ok"
expect 0 '"esito": "OK"' "rossi: test-red/rossi.json scritto nella run dir" -- cat "$T/f2t.run/test-red/rossi.json"
# goals-ux-12: the plan names the test "describe > it", as vitest prints it. Counterproof: with the segments joined
# only by " " the red of T2 goes back to «verde» and its FAIL block to a «conflitto» with the existing suite.
sed 's/fmt\.test\.ts::fmt formatta`/fmt.test.ts::fmt > formatta`/' "$T/f2t.md" > "$T/f2t-desc.md"
mkev "$T/ev-desc" "$JU_RED" FAIL "${FE_RED/ FAIL  tests\/fmt.test.ts > fmt formatta/ FAIL  tests/fmt.test.ts > fmt > formatta}" FAIL
expect 0 "^rosso T2: dimostrato modules/app/apps/admin/tests/fmt.test.ts:2" "rossi: nome «describe > it» nel piano abbinato al blocco FAIL di vitest" -- bash "$PC" rossi "$T/f2t-desc.md" --evidence "$T/ev-desc" --run-dir "$T/rr.run"
refute "^conflitto:" "rossi: il rosso di un test «describe > it» non e' un conflitto" -- bash "$PC" rossi "$T/f2t-desc.md" --evidence "$T/ev-desc" --run-dir "$T/rr.run"
mkev "$T/ev-green" "$JU_GREEN" PASS "$FE_RED" FAIL
expect 1 "^rosso T1: verde " "rossi: verde = STOP (il test non prova nulla)" -- bash "$PC" rossi "$T/f2t.md" --evidence "$T/ev-green" --run-dir "$T/rr.run"
sed 's/^\(| T1 | RF1 | .* | rosso se: la somma e. sbagliata | \).*$/\1— |/' "$T/f2t.md" > "$T/f2t-imp.md"
mkev "$T/ev-imp" "$JU_IMP" FAIL "$FE_RED" FAIL
expect 1 "^rosso T1: rosso_import" "rossi: rosso da import = STOP «non dimostrato» (controprova: senza la classificazione diventa dimostrato)" -- bash "$PC" rossi "$T/f2t-imp.md" --evidence "$T/ev-imp" --run-dir "$T/rr.run"
expect 1 "^rossi: esito=STOP — non dimostrato: T1 rosso_import" "rossi: il riassunto nomina il caso" -- bash "$PC" rossi "$T/f2t-imp.md" --evidence "$T/ev-imp" --run-dir "$T/rr.run"
# MAJOR 1 (review round 1): without an assertion text (no backticks, no mutation) any red
# (NotImplementedError of the stub) is not proven. Counterproof: without CONTROLLO-ASSERZIONE it goes back to «dimostrato».
JU_NIE='<testcase classname="tests.test_calc" name="test_somma"><failure message="NotImplementedError">E  NotImplementedError
tests/test_calc.py:4: NotImplementedError</failure></testcase>'
mkev "$T/ev-nie" "$JU_NIE" FAIL "$FE_RED" FAIL
expect 1 "^rosso T1: rosso_senza_asserzione" "rossi: rosso senza testo dell'asserzione (NotImplementedError) = non dimostrato, uscita 1" -- bash "$PC" rossi "$T/f2t-imp.md" --evidence "$T/ev-nie" --run-dir "$T/rr.run"
JU_NOPOS='<testcase classname="tests.test_calc" name="test_somma"><failure message="assert 0 == 3">E  assert 0 == 3</failure></testcase>'
mkev "$T/ev-nopos" "$JU_NOPOS" FAIL "$FE_RED" FAIL
expect 1 "^rosso T1: rosso_senza_asserzione .*senza posizione" "rossi: rosso sull'asserzione ma senza posizione = non dimostrato" -- bash "$PC" rossi "$T/f2t.md" --evidence "$T/ev-nopos" --run-dir "$T/rr.run"
mkev "$T/ev-sum" "$JU_RED" FAIL "$FE_RED
      Tests  2 failed (2)" FAIL
expect 1 "^conflitto: riepilogo di vitest: 2 test falliti, 1 blocchi FAIL" "rossi: riepilogo di vitest diverso dai blocchi letti = STOP" -- bash "$PC" rossi "$T/f2t.md" --evidence "$T/ev-sum" --run-dir "$T/rr.run"
grep -v '^| T[12] | RF1 |' "$T/f2t.md" > "$T/f2t-empty.md"
mkev "$T/ev-none" "$JU_GREEN" PASS " ✓ tests/fmt.test.ts  (1 test) 3ms
vitest-fast: esito=PASS luogo=copia" PASS
expect 0 "^AVVISO: la tabella del piano di test non ha righe" "rossi: tabella senza righe = AVVISO visibile" -- bash "$PC" rossi "$T/f2t-empty.md" --evidence "$T/ev-none" --run-dir "$T/rr.run"
JU_DIV='<testcase classname="tests.test_calc" name="test_somma"><failure message="assert 1 == 3">E  assert 1 == 3</failure></testcase>'
mkev "$T/ev-div" "$JU_DIV" FAIL "$FE_RED" FAIL
expect 1 "^rosso T1: rosso_diverso" "rossi: rosso su un'altra asserzione = STOP" -- bash "$PC" rossi "$T/f2t.md" --evidence "$T/ev-div" --run-dir "$T/rr.run"
mkev "$T/ev-suite" "$JU_RED" FAIL " FAIL  tests/fmt.test.ts [ tests/fmt.test.ts ]
Error: Failed to resolve import \"../utils/fmt\" from \"tests/fmt.test.ts\". Does the file exist?
vitest-fast: esito=FAIL luogo=copia" FAIL
expect 1 "^rosso T2: rosso_import" "rossi: file di test che non si carica (vitest) = rosso_import" -- bash "$PC" rossi "$T/f2t.md" --evidence "$T/ev-suite" --run-dir "$T/rr.run"
mkev "$T/ev-confl" "$JU_RED" FAIL "$FE_RED
 FAIL  tests/old.test.ts > vecchio caso
AssertionError: expected true to be false" FAIL
expect 1 "^conflitto: tests/old.test.ts > vecchio caso — AssertionError: expected true to be false <-> T1" "rossi: suite esistente rossa sulla base con stub = conflitto, con le due asserzioni" -- bash "$PC" rossi "$T/f2t.md" --evidence "$T/ev-confl" --run-dir "$T/rr.run"
printf '%s\n' "it('g', () => { expect(src).not.toContain('Titolo Tred') })" > "$R/modules/app/apps/admin/tests/tred-guard.test.ts"
expect 1 "^conflitto: modules/app/apps/admin/tests/tred-guard.test.ts:1 asserisce l assenza di Titolo Tred, che il piano aggiunge" "rossi: test esistente che vieta un valore aggiunto dal piano (forma ux-6) = conflitto" -- bash "$PC" rossi "$T/f2t.md" --evidence "$T/ev-ok" --run-dir "$T/rr.run"
rm -f "$R/modules/app/apps/admin/tests/tred-guard.test.ts"
mkdir -p "$T/ev-blk"; printf '{"gate":"tests-be","esito":"BLOCKED","motivo":"venv assente"}\n' > "$T/ev-blk/tests-be.json"; cp "$T/ev-ok/tests-fe.json" "$T/ev-ok/tests-fe.log" "$T/ev-blk/"
expect 3 "^rossi: esito=BLOCKED — .*tests-be: esito BLOCKED \(venv assente\)" "rossi: gate BLOCKED = BLOCKED (mai OK)" -- bash "$PC" rossi "$T/f2t.md" --evidence "$T/ev-blk" --run-dir "$T/rr.run"
# pk04b-2: NOT RUN (with the space, phase-result.schema.json) as SKIPPED: the module tests are non_eseguito with
# the gate reason, never blocked (exit other than 3). NOT_RUN with the underscore stays unknown: blocked.
mkdir -p "$T/ev-nr"; printf '{"gate":"tests-be","esito":"NOT RUN","motivo":"nessun comando di test dichiarato"}\n' > "$T/ev-nr/tests-be.json"; cp "$T/ev-ok/tests-fe.json" "$T/ev-ok/tests-fe.log" "$T/ev-nr/"
expect 1 "^rosso T1: non_eseguito — gate tests-be NOT RUN: nessun comando di test dichiarato$" "rossi: gate NOT RUN = test non_eseguito con il motivo del gate, uscita 1 (non 3)" -- bash "$PC" rossi "$T/f2t.md" --evidence "$T/ev-nr" --run-dir "$T/rr.run"
sed 's/"NOT RUN"/"NOT_RUN"/' "$T/ev-nr/tests-be.json" > "$T/ev-nr/x" && mkdir -p "$T/ev-nr2" && mv "$T/ev-nr/x" "$T/ev-nr2/tests-be.json" && cp "$T/ev-ok/tests-fe.json" "$T/ev-ok/tests-fe.log" "$T/ev-nr2/"
expect 3 "^rossi: esito=BLOCKED — .*tests-be: esito NOT_RUN" "rossi: gate NOT_RUN (trattino basso) = sconosciuto, BLOCKED" -- bash "$PC" rossi "$T/f2t.md" --evidence "$T/ev-nr2" --run-dir "$T/rr.run"
# counterproof: without NOT RUN in the list of the outcomes read, the gate ends up among the blocked ones (exit 3)
if mutpc nr 's/("PASS", "FAIL", "SKIPPED", "NOT RUN")/("PASS", "FAIL", "SKIPPED")/'; then
  expect 3 "^rossi: esito=BLOCKED — .*tests-be: esito NOT RUN" "controprova: senza NOT RUN fra gli esiti letti il gate e' bloccato" -- env MAAT_ROOT="$PLUGIN_DIR" bash "$T/pcm-nr/plan-check.sh" rossi "$T/f2t.md" --evidence "$T/ev-nr" --run-dir "$T/rr.run"
else echo "FAIL [controprova NOT RUN: la mutazione non si applica]"; fail=$((fail+1)); fi
# stubs, absorbed counterproofs (L2) and recheck for finalize
expect 0 "^stub modules/app/apps/admin/utils/fmt.ts: fmt$" "stubs: simboli degli stub registrati" -- bash "$PC" stubs "$T/f2t.md"
expect 0 "^gen: mutazione T1 assorbita \(L2\)$" "gen: file nuovo con rosso dimostrato e simboli testati = assorbita" -- bash "$PC" gen "$T/f2t.md"
expect 0 '"assorbita": true' "gen: mutations.json con assorbita" -- cat "$T/f2t.run/counterproof/mutations.json"
mkdir -p "$T/cptmp4" "$T/cpout4"
expect 0 "^0 0 1 0$" "prep di counterproof.sh: l'assorbita non si esegue" -- "$FIC_PY" "$T/cp.py" prep "$T/f2t.run/counterproof/mutations.json" "$R" "$T/cptmp4" "$T/cpout4"
expect 0 '"esito": "assorbita"' "prep: <id>.json con esito assorbita" -- cat "$T/cpout4/T1.json"
expect 0 "^L2 T1: OK$" "l2: condizioni valide sul codice attuale" -- bash "$PC" l2 "$T/f2t.md"
cp -r "$T/f2t.run" "$T/f2t-b.run"
printf 'def somma(a, b):\n    return 0\n\ndef aiuto():\n    return 1\n' > "$R/modules/api/app/services/calc.py"
bash "$PC" stubs "$T/f2t.md" --run-dir "$T/f2t-b.run" >/dev/null
expect 0 "^mutazioni: 1$" "L2: simbolo esportato non testato, gen" -- bash "$PC" gen "$T/f2t.md" --run-dir "$T/f2t-b.run"
refute "assorbita" "L2: file nuovo con un simbolo esportato non testato = controprova non assorbita" -- cat "$T/f2t-b.run/counterproof/mutations.json"
expect 0 "^L2 T1: NO — simbolo esportato non testato .*aiuto" "l2: il motivo" -- bash "$PC" l2 "$T/f2t.md" --run-dir "$T/f2t-b.run"
expect 0 "^L2 T1: NO — exported symbol tested by no acceptance test: .*aiuto" "en (MAAT_LINGUA=en) l2: il prefisso L2 <id>: NO — resta, il motivo in inglese" -- env MAAT_LINGUA=en bash "$PC" l2 "$T/f2t.md" --run-dir "$T/f2t-b.run"
refute "simbolo esportato" "en (MAAT_LINGUA=en) l2: nessun motivo italiano" -- env MAAT_LINGUA=en bash "$PC" l2 "$T/f2t.md" --run-dir "$T/f2t-b.run"
expect 0 "^L2 T1: NO — gli stub non coprono tutti e soli i simboli nuovi" "l2: un export aggiunto dopo test-red = non piu' assorbita" -- bash "$PC" l2 "$T/f2t.md"
# harness-pt15: gen decides L2 with the finalize criterion (stub = symbols exported NOW). Counterproof: with
# l2_eval(..., False) in gen (as it was) here T1 goes back to absorbed, and finalize then rejects it (l2 NO above).
cp -r "$T/f2t.run" "$T/f2t-c.run"
expect 0 "^mutazioni: 1$" "L2 in gen dopo l'implementazione: gen" -- bash "$PC" gen "$T/f2t.md" --run-dir "$T/f2t-c.run"
refute "assorbita" "gen: stub che non coprono un export aggiunto dopo test-red = non assorbita (come l2 per finalize)" -- cat "$T/f2t-c.run/counterproof/mutations.json"
printf 'def somma(a, b):\n    return 0\n' > "$R/modules/api/app/services/calc.py"
printf '\n# cambiato\n' >> "$R/modules/api/tests/test_calc.py"
expect 0 "^L2 T1: NO — impronta dei test di accettazione cambiata" "l2: test di accettazione cambiato = non assorbita" -- bash "$PC" l2 "$T/f2t.md"
printf 'from app.services.calc import somma\n\ndef test_somma():\n    assert somma(1, 2) == 3\n' > "$R/modules/api/tests/test_calc.py"

# ── Maat 1.3.0: the English forms (written from 1.3.0 on) next to the Italian ones (still accepted) ──────────
# For every rule group an English fixture with the same outcome as the Italian one; a mixed spec accepted section
# by section; the same section in both languages = VIOLAZIONE. The English fixtures live in $E, so the oracle at
# the end (old script against the new one) runs on the Italian fixtures only.
E="$T/en"; mkdir -p "$E"
spec_en() {
cat <<'EOF'
# Title
## Context
Context of the feature.
## Functional requirements
1. The `status` filter applies.
## Implementation plan
Plan status: DRAFT
Test level: std
Risk surfaces: permissions, shared-logic
### Steps
1. Change `modules/api/app/services/foo.py` in `apply_filter()`.
2. Reuse `modules/api/app/services/foo.py` in the router.
3. No effect on `std` or `true`.
```text
Plan status: APPROVED
example inside a fence
```
## ⚠️ Note inside the plan
The H2 above does NOT close the plan section.
### Test plan
- case 1: `test_foo.py::test_filter` red if: the filter is ignored
- [floor: permissions] `test_perm.py::test_forbidden` red if: the 403 disappears
### Plan review changelog
- Round 1: fixed the path of `apply_filter()`; removed `only_in_changelog`.
## Implementation review
Review status: APPROVED
EOF
}
spec_en > "$E/base.md"
# lint and contract: the same outcomes as the Italian reference spec (same line numbers)
expect 0 "lint: OK" "en lint: spec di riferimento inglese pulita" -- bash "$PC" lint "$E/base.md"
expect 0 "lint: OK" "en lint: identica alla baseline" -- bash "$PC" lint "$E/base.md" --baseline "$E/base.md"
expect 0 "^Superfici a rischio: permissions, shared-logic$" "en contract: la dichiarazione come scritta" -- bash "$PC" contract "$E/base.md"
expect 0 "^Pavimento: permessi \(riga 22\)$" "en contract: [floor: permissions] = pavimento sulla critica permessi" -- bash "$PC" contract "$E/base.md"
refute "^Obbligo" "en contract: con [floor:] nessun obbligo" -- bash "$PC" contract "$E/base.md"
expect 0 "^Piano di test: offset=20 limit=3$" "en contract: range di ### Test plan" -- bash "$PC" contract "$E/base.md"
sed 's/^Context of the feature\./Context changed./' "$E/base.md" > "$E/above.md"
expect 1 "sezioni della SPEC" "en lint: spec sopra ## Implementation plan modificata = VIOLAZIONE" -- bash "$PC" lint "$E/above.md" --baseline "$E/base.md"
sed 's/^Review status: APPROVED/Review status: NEEDS_CHANGES/' "$E/base.md" > "$E/rev.md"
expect 1 "Review implementazione" "en lint: ## Implementation review toccata = VIOLAZIONE" -- bash "$PC" lint "$E/rev.md" --baseline "$E/base.md"
sed 's/^- Round 1: fixed/Test level: full\n- Round 1: fixed/' "$E/base.md" > "$E/clog.md"
expect 1 "'Test level:' compare 2 volte" "en lint: letterale nel ### Plan review changelog = VIOLAZIONE" -- bash "$PC" lint "$E/clog.md"
sed 's/^Risk surfaces: .*/&\nRisk surfaces: permissions/' "$E/base.md" > "$E/dupdecl.md"
expect 1 "'Superfici a rischio:' compare 2 volte" "en lint: Risk surfaces: due volte = VIOLAZIONE" -- bash "$PC" lint "$E/dupdecl.md"
sed 's/^Risk surfaces: .*/&\nSuperfici a rischio: permessi/' "$E/base.md" > "$E/dupdecl2.md"
expect 1 "'Superfici a rischio:' compare 2 volte" "en lint: Risk surfaces: e Superfici a rischio: insieme = VIOLAZIONE" -- bash "$PC" lint "$E/dupdecl2.md"
sed 's/^Risk surfaces: permissions, shared-logic/Risk surfaces: permissions, auth/' "$E/base.md" > "$E/voc.md"
expect 1 "superficie sconosciuta 'auth'" "en lint: token fuori vocabolario = VIOLAZIONE" -- bash "$PC" lint "$E/voc.md"
sed 's/^Risk surfaces: permissions, shared-logic/Risk surfaces: shared-logic/' "$E/base.md" > "$E/pav.md"
expect 1 "non dichiarata" "en lint: [floor:] su superficie non dichiarata = VIOLAZIONE" -- bash "$PC" lint "$E/pav.md"
sed 's/^Risk surfaces: permissions, shared-logic/Risk surfaces: permissions, shared-logic, data/; s/\[floor: permissions\]/[floor: shared-logic]/' "$E/base.md" > "$E/pav2.md"
expect 1 "solo per le superfici critiche" "en lint: [floor:] su superficie non critica = VIOLAZIONE" -- bash "$PC" lint "$E/pav2.md"
sed 's/^- \[floor: permissions\].*/&\n- [pavimento: permessi] `test_perm.py::test_other` rosso se: x/' "$E/base.md" > "$E/pav3.md"
expect 1 "piu' di una riga \[pavimento: permessi\]" "en lint: [floor: permissions] e [pavimento: permessi] = due pavimenti = VIOLAZIONE" -- bash "$PC" lint "$E/pav3.md"
sed 's/^Risk surfaces: permissions, shared-logic/Risk surfaces: none, permissions/' "$E/base.md" > "$E/none.md"
expect 1 "'nessuna' insieme" "en lint: 'none' con altre superfici = VIOLAZIONE" -- bash "$PC" lint "$E/none.md"
sed 's/^Risk surfaces: permissions, shared-logic/Risk surfaces: `permissions`, `shared-logic`/' "$E/base.md" > "$E/bt.md"
expect 0 "lint: OK" "en lint: token fra backtick = accettati" -- bash "$PC" lint "$E/bt.md"
# ⚠️ Surface <token> and the "static sufficient:" waiver
sed 's/\[floor: permissions\] //' "$E/base.md" > "$E/nopav.md"
expect 0 "AVVISO: superficie critica 'permessi'" "en lint: critica senza [floor:] ne' ⚠️ = AVVISO" -- bash "$PC" lint "$E/nopav.md"
expect 0 "^Obbligo: permessi — né pavimento né ⚠️$" "en contract: critica scoperta = obbligo" -- bash "$PC" contract "$E/nopav.md"
sed 's/^- case 1:.*/&\n- ⚠️ Surface permissions not covered by the gates at level std/' "$E/nopav.md" > "$E/warnln.md"
refute "superficie critica 'permessi'" "en lint: la riga ⚠️ Surface permissions soddisfa la critica" -- bash "$PC" lint "$E/warnln.md"
expect 0 "^Obbligo: permessi — ⚠️ senza deroga \(riga 22\)$" "en contract: ⚠️ Surface senza deroga = obbligo" -- bash "$PC" contract "$E/warnln.md"
expect 0 "^Rischio: riga 22 — ⚠️ Surface permissions not covered" "en contract: la riga ⚠️ Surface e' un focus di rischio" -- bash "$PC" contract "$E/warnln.md"
sed 's/^- case 1:.*/&\n- ⚠️ Surface api-contract not covered by the gates at level std/' "$E/nopav.md" > "$E/warnother.md"
expect 0 "AVVISO: superficie critica 'permessi'" "en lint: ⚠️ Surface su un'altra superficie non copre la critica" -- bash "$PC" lint "$E/warnother.md"
sed 's/^- ⚠️ Surface permissions .*/& — static sufficient: rename of a constant/' "$E/warnln.md" > "$E/waiver.md"
expect 0 "^Statica sufficiente: permessi — rename of a constant \(riga 22\)$" "en contract: deroga static sufficient con motivo" -- bash "$PC" contract "$E/waiver.md"
refute "deroga" "en lint: deroga con motivo sulla stessa riga = nessun avviso" -- bash "$PC" lint "$E/waiver.md"
sed 's/^- ⚠️ Surface permissions .*/& — static sufficient:/' "$E/warnln.md" > "$E/wvoid.md"
expect 0 "AVVISO: riga 22: deroga 'statica sufficiente:' senza motivo" "en lint: static sufficient senza motivo = AVVISO" -- bash "$PC" lint "$E/wvoid.md"
sed 's/^- ⚠️ Surface permissions .*/& —\n  static sufficient: rename/' "$E/warnln.md" > "$E/wsplit.md"
expect 0 "AVVISO: riga 22: la deroga continua a capo" "en lint: deroga spezzata a capo = AVVISO" -- bash "$PC" lint "$E/wsplit.md"
grep -v 'test_perm.py::test_forbidden' "$E/warnln.md" | sed 's/^Test level: std$/Test level: min/' > "$E/minwarn.md"
refute "righe al livello min" "en lint: a min, 1 caso + riga ⚠️ Surface = entro il tetto" -- bash "$PC" lint "$E/minwarn.md"
# basis: the English changelog stays out of the plan fingerprint, like the Italian one
expect 0 "^Status: LEGACY$" "en basis: nessuna Approved basis = LEGACY" -- bash "$PC" basis "$E/base.md"
cure=$(bash "$PC" basis "$E/base.md" | sed -n 's/^Basis: //p')
sed "s/^Risk surfaces: .*/&\nApproved basis: $cure/" "$E/base.md" > "$E/ab.md"
expect 0 "^Status: FRESH$" "en basis: approvata = FRESH" -- bash "$PC" basis "$E/ab.md"
sed 's/^- Round 1: fixed.*/&\nCycle metric: rounds=1/' "$E/ab.md" > "$E/ab-clog.md"
expect 0 "^Status: FRESH$" "en basis: solo ### Plan review changelog cambiato = FRESH (fuori dall'impronta)" -- bash "$PC" basis "$E/ab-clog.md"
sed 's/^Review status: APPROVED/Review status: NEEDS_CHANGES/' "$E/ab.md" > "$E/ab-rev.md"
expect 0 "^Status: FRESH$" "en basis: solo ## Implementation review cambiata = FRESH" -- bash "$PC" basis "$E/ab-rev.md"
sed 's/in the router\./in the router and in the job./' "$E/ab.md" > "$E/ab-plan.md"
expect 0 "^Status: STALE \(plan\)$" "en basis: controprova, corpo del piano cambiato = STALE (plan)" -- bash "$PC" basis "$E/ab-plan.md"
# the English changelog heading is excluded like the Italian one: same fingerprint whatever its language
sed 's/^### Changelog revisione piano$/### Plan review changelog/' "$T/base.md" > "$E/it-clog-en.md"
bit=$(bash "$PC" basis "$T/base.md" | sed -n 's/^Basis: //p'); ben=$(bash "$PC" basis "$E/it-clog-en.md" | sed -n 's/^Basis: //p')
[ -n "$bit" ] && [ "$bit" = "$ben" ] && pass=$((pass+1)) || { echo "FAIL [en basis: changelog italiano o inglese = stessa impronta ($bit / $ben)]"; fail=$((fail+1)); }
# mixed spec, accepted section by section: Italian H2 and status lines, English H3, floor and changelog →
# the contract is the one of the Italian reference spec, line by line
sed 's/^### Piano di test$/### Test plan/; s/\[pavimento: permessi\]/[floor: permissions]/; s/^### Changelog revisione piano$/### Plan review changelog/' "$T/base.md" > "$E/mix.md"
expect 0 "lint: OK" "mista lint: titoli italiani e inglesi insieme = pulita" -- bash "$PC" lint "$E/mix.md"
d=$(diff <(bash "$PC" contract "$T/base.md") <(bash "$PC" contract "$E/mix.md"))
[ -z "$d" ] && pass=$((pass+1)) || { echo "FAIL [mista contract: uguale a quello della spec italiana]"; printf '%s\n' "$d" | sed 's/^/    /'; fail=$((fail+1)); }
sed 's/^## Piano di implementazione$/## Implementation plan/; s/^Superfici a rischio: permessi, logica-condivisa$/Risk surfaces: permissions, logica-condivisa/' "$T/base.md" > "$E/mix2.md"
expect 0 "lint: OK" "mista lint: H2 inglese, H3 italiani, token misti = pulita" -- bash "$PC" lint "$E/mix2.md"
expect 0 "^Pavimento: permessi \(riga 22\)$" "mista contract: [pavimento: permessi] sotto ## Implementation plan" -- bash "$PC" contract "$E/mix2.md"
# the same section in both languages = VIOLAZIONE (H2 zone and H3)
sed 's/^- caso 1:.*/&\n### Test plan\n- case 2/' "$T/base.md" > "$E/dup-h3.md"
expect 1 "VIOLAZIONE: '### Piano di test' e '### Test plan' insieme nel piano" "doppione: ### Piano di test e ### Test plan = VIOLAZIONE" -- bash "$PC" lint "$E/dup-h3.md"
sed 's/^- Giro 1: corretto.*/&\n### Plan review changelog\n- Round 2./' "$T/base.md" > "$E/dup-clog.md"
expect 1 "VIOLAZIONE: '### Changelog revisione piano' e '### Plan review changelog' insieme" "doppione: changelog nelle due lingue = VIOLAZIONE" -- bash "$PC" lint "$E/dup-clog.md"
sed 's/^Review status: APPROVED/&\n## Implementation review\nReview status: APPROVED/' "$T/base.md" > "$E/dup-rev.md"
expect 1 "VIOLAZIONE: '## Review implementazione' e '## Implementation review' insieme" "doppione: ## Review implementazione e ## Implementation review = VIOLAZIONE" -- bash "$PC" lint "$E/dup-rev.md"
sed 's/^Plan status: DRAFT/## Implementation plan\n&/' "$T/base.md" > "$E/dup-h2.md"
expect 1 "VIOLAZIONE: '## Piano di implementazione' e '## Implementation plan' insieme" "doppione: ## Piano di implementazione e ## Implementation plan = VIOLAZIONE" -- bash "$PC" lint "$E/dup-h2.md"
sed 's/^# Titolo$/&\nFiglie: spec-a, spec-b\nChildren: spec-a, spec-b/' "$T/base.md" > "$E/dup-figlie.md"
expect 1 "VIOLAZIONE: 'Figlie:' e 'Children:' insieme sopra il piano" "doppione: Figlie: e Children: = VIOLAZIONE" -- bash "$PC" lint "$E/dup-figlie.md"
refute "due lingue" "doppione: controprova, la spec di riferimento italiana non ha doppioni" -- bash "$PC" lint "$T/base.md"

# format 2 in English: the same outcomes as spec2, and the SAME generated mutations.json (Italian tokens)
spec2_en() {
cat <<'EOF'
# Title
## Functional requirements
1. FR1 — a salesperson does not change the goal.
2. FR2 — the bar appears.
3. FR3 — the text of the bar.
## Implementation plan
Plan format: 2
Plan status: DRAFT
Test level: std
Risk surfaces: permissions, api-contract
### Decisions
The 403 applies to whoever cannot edit.
| input | output |
|---|---|
| salesperson | 403 |
### Touched files
- `modules/api/app/routers/goals.py`
- `modules/api/tests/test_goals.py`
- `modules/app/apps/admin/components/Bar.vue`
- `modules/app/apps/admin/tests/bar.test.ts`
### Steps
#### Block B1 — backend
writes: `modules/api/app/routers/goals.py`, `modules/api/tests/test_goals.py`
after: none

| id | file | change | test |
|---|---|---|---|
| P1 | `modules/api/app/routers/goals.py` | `update_goal()`: 403 to whoever cannot | T1 |
| P2 | `modules/api/tests/test_goals.py` | new case | T1 |

#### Block B2 — frontend
writes: `modules/app/apps/admin/components/Bar.vue`, `modules/app/apps/admin/tests/bar.test.ts`
after: B1

| id | file | change | test |
|---|---|---|---|
| P3 | `modules/app/apps/admin/components/Bar.vue` | the bar | T2 |
### Requirement traceability
| Req | Plan steps | Verification |
|---|---|---|
| FR1 | P1, P2 | T1 |
| FR2 | P3 | T2 |
| FR3 | P3 | not verifiable by a test: text only |
### Strings and data-test
| action | type | value |
|---|---|---|
| adds | data-test | `goals-company-bar` |
### Test plan
| ID | requirement | file | assertion | mutation |
|---|---|---|---|---|
| T1 | FR1 | `modules/api/tests/test_goals.py::test_update_denied` (new) | red if: the salesperson updates | `modules/api/app/routers/goals.py` · `update_goal` · `if not can_edit:` → `if False:` · red if: `assert 200 == 403` |
| T2 | FR2 | `modules/app/apps/admin/tests/bar.test.ts::bar` (new) | red if: the bar is missing, `expected false to be true` | — |
- [floor: permissions] T1
### Plan review changelog
- Round 1: first plan.
EOF
}
spec2_en > "$E/f2.md"
expect 0 "^lint2: OK$" "en lint2: piano formato 2 inglese pulito (spec FR/AC: tracciabilita OK)" -- bash "$PC" lint2 "$E/f2.md"
expect 0 "AVVISO: .*goals-company-bar aggiunto dal piano ma gia presente" "en lint2: adds | data-test gia presente = AVVISO" -- bash "$PC" lint2 "$E/f2.md"
expect 0 "lint: OK" "en lint: il formato 2 inglese passa il lint" -- bash "$PC" lint "$E/f2.md"
refute "righe al livello" "en lint: intestazione della tabella inglese fuori dal tetto" -- bash "$PC" lint "$E/f2.md"
sed 's/^| T2 | FR2 |/| T2 | FR1 |/' "$E/f2.md" > "$E/f2-noreq.md"
expect 1 "VIOLAZIONE: riga [0-9]+: requisito FR2 senza test" "en lint2: requisito senza test = VIOLAZIONE" -- bash "$PC" lint2 "$E/f2-noreq.md"
refute "requisito FR3" "en lint2: 'not verifiable' esenta il requisito" -- bash "$PC" lint2 "$E/f2-noreq.md"
grep -v '^- `modules/app/apps/admin/components/Bar.vue`$' "$E/f2.md" > "$E/f2-nofile.md"
expect 1 "VIOLAZIONE: riga [0-9]+: passo P3: modules/app/apps/admin/components/Bar.vue non e nella lista ### File toccati" "en lint2: file di un passo fuori da ### Touched files = VIOLAZIONE" -- bash "$PC" lint2 "$E/f2-nofile.md"
sed 's/^| P3 | \(.*\) | T2 |$/| P3 | \1 | — |/' "$E/f2.md" > "$E/f2-nostep.md"
expect 1 "VIOLAZIONE: riga [0-9]+: test T2 non compare in nessun passo" "en lint2: test fuori da un passo = VIOLAZIONE" -- bash "$PC" lint2 "$E/f2-nostep.md"
# invariance in English, singular and plural forms
inv=0
for w in "stays green:" "**Remain green** with:" "keep passing:" "remains green:" "stay green:" "keeps passing:"; do
  inv=$((inv + 1))
  sed "s/^| T2 | FR2 | \(\`[^\`]*\`\) (new) | red if: /| T2 | FR2 | \1 | $w /" "$E/f2.md" > "$E/f2-inv$inv.md"
  expect 1 "VIOLAZIONE: riga [0-9]+: test T2: asserzione \"resta verde\"" "en lint2: '$w' nel Test plan = VIOLAZIONE" -- bash "$PC" lint2 "$E/f2-inv$inv.md"
done
sed 's/^| T2 | FR2 | \(`[^`]*`\) (new) | red if: /| T2 | FR2 | \1 (new) | red if: the old case stays green but /' "$E/f2.md" > "$E/f2-inv-mid.md"
expect 0 "^lint2: OK$" "en lint2: 'stays green' a meta asserzione = pulito" -- bash "$PC" lint2 "$E/f2-inv-mid.md"
awk '!(/^writes:/ && ++n == 2)' "$E/f2.md" > "$E/f2-nowrites.md"
expect 1 "VIOLAZIONE: riga [0-9]+: blocco B2 senza scrive:" "en lint2: blocco senza writes: = VIOLAZIONE" -- bash "$PC" lint2 "$E/f2-nowrites.md"
sed 's/^#### Block B1 — backend$/Block B1 — backend/' "$E/f2.md" > "$E/f2-noblock.md"
expect 1 "VIOLAZIONE: riga [0-9]+: passo P1 fuori da un blocco" "en lint2: passo fuori da un #### Block = VIOLAZIONE" -- bash "$PC" lint2 "$E/f2-noblock.md"
sed 's/^| adds | data-test | `goals-company-bar` |$/&\n| removes | data-test | `goals-old-section` |/' "$E/f2.md" > "$E/f2-rm.md"
expect 1 "VIOLAZIONE: riga [0-9]+: data-test goals-old-section tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/old.test.ts:1" "en lint2: removes | data-test ancora asserito = VIOLAZIONE" -- bash "$PC" lint2 "$E/f2-rm.md"
sed 's/^| adds | data-test | `goals-company-bar` |$/&\n| removes | string | `Scaduto` |/' "$E/f2.md" > "$E/f2-pos.md"
expect 1 "VIOLAZIONE: riga [0-9]+: stringa Scaduto tolto dal piano ma ancora asserito da modules/app/apps/admin/tests/pos.test.ts:1" "en lint2: removes | string asserita = VIOLAZIONE" -- bash "$PC" lint2 "$E/f2-pos.md"
sed 's/^| action | type | value |$/| action | type | value | verified |/; s/^| removes | string | `Scaduto` |$/| removes | string | `Scaduto` | `modules\/app\/apps\/admin\/tests\/pos.test.ts` — rewritten by flow X |/' "$E/f2-pos.md" > "$E/f2-ver.md"
expect 0 "^lint2: OK$" "en lint2: colonna verified sul file = pulito" -- bash "$PC" lint2 "$E/f2-ver.md"
expect 0 "AVVISO: .*stringa Scaduto tolto dal piano, asserito da modules/app/apps/admin/tests/pos.test.ts:1: deroga verificato \(rewritten by flow X\)" "en lint2: la deroga verified resta un AVVISO col motivo" -- bash "$PC" lint2 "$E/f2-ver.md"
sed 's/ · red if: `assert 200 == 403` |$/ |/' "$E/f2.md" > "$E/f2-badmut.md"
expect 1 "VIOLAZIONE: riga [0-9]+: test T1: mutazione illeggibile" "en lint2: mutazione senza red if = VIOLAZIONE" -- bash "$PC" lint2 "$E/f2-badmut.md"
sed 's/^| T2 | FR2 | \(.*\) | — |$/| T2 | FR2 | \1 | `modules\/api\/app\/routers\/goals.py` · `update_goal` · `raise Forbidden()` → (empty) · red if: `expected` |/' "$E/f2.md" > "$E/f2-cross.md"
expect 1 "VIOLAZIONE: riga [0-9]+: test T2: file e test in moduli diversi" "en lint2: mutazione con (empty) e red if letta (moduli diversi = VIOLAZIONE)" -- bash "$PC" lint2 "$E/f2-cross.md"
sed 's/^- \[floor: permissions\] T1$/&\n- ⚠️ Open risk: the bar blinks/' "$E/f2.md" > "$E/f2-risk.md"
expect 1 "VIOLAZIONE: riga [0-9]+: rischio aperto senza un test assegnato" "en lint2: ⚠️ Open risk senza test = VIOLAZIONE" -- bash "$PC" lint2 "$E/f2-risk.md"
sed 's/^- ⚠️ Open risk: the bar blinks$/& — T2/' "$E/f2-risk.md" > "$E/f2-risk-ok.md"
expect 0 "^lint2: OK$" "en lint2: ⚠️ Open risk con il suo test = pulito" -- bash "$PC" lint2 "$E/f2-risk-ok.md"
expect 0 "^Rischio: riga [0-9]+ — ⚠️ Open risk: the bar blinks — T2$" "en contract: ⚠️ Open risk e' un focus di rischio" -- bash "$PC" contract "$E/f2-risk-ok.md"
sed 's/^### Decisions$/### Decisioni\nx\n### Decisions/' "$E/f2.md" > "$E/f2-dup.md"
expect 1 "VIOLAZIONE: riga [0-9]+: sezione ### Decisioni ripetuta" "en lint2: ### Decisioni e ### Decisions = sezione ripetuta" -- bash "$PC" lint2 "$E/f2-dup.md"
expect 1 "VIOLAZIONE: '### Decisioni' e '### Decisions' insieme nel piano" "en lint: ### Decisioni e ### Decisions = VIOLAZIONE" -- bash "$PC" lint "$E/f2-dup.md"
# gen: the same procedure and the same mutations.json as the Italian plan (canonical tokens, superficie permessi)
expect 0 "^mutazioni: 1$" "en gen: una mutazione dalla tabella inglese" -- bash "$PC" gen "$E/f2.md"
expect 0 '"superficie": "permessi"' "en gen: [floor: permissions] = superficie permessi (token canonico) in mutations.json" -- cat "$E/f2.run/counterproof/mutations.json"
bash "$PC" gen "$T/f2.md" --run-dir "$E/it-f2.run" >/dev/null 2>&1
cmp -s "$E/it-f2.run/counterproof/mutations.json" "$E/f2.run/counterproof/mutations.json" && pass=$((pass+1)) ||
  { echo "FAIL [en gen: mutations.json identico a quello del piano italiano]"; diff "$E/it-f2.run/counterproof/mutations.json" "$E/f2.run/counterproof/mutations.json" | sed 's/^/    /'; fail=$((fail+1)); }
keyl() { grep -E '^(Plan format|Test level|vitest|pytest|altri|mutazioni|blocco [^:]*):' "$1"; }
d=$(diff <(keyl "$E/it-f2.run/gen/procedura.txt") <(keyl "$E/f2.run/gen/procedura.txt"))
[ -z "$d" ] && [ -n "$(keyl "$E/f2.run/gen/procedura.txt")" ] && pass=$((pass+1)) || { echo "FAIL [en gen: procedura.txt uguale a quella italiana (livello, liste, blocchi con dopo=nessuno)]"; printf '%s\n' "$d" | sed 's/^/    /'; fail=$((fail+1)); }
# mixed format 2 plan: Italian traceability and decisions, English steps, blocks and test table
sed 's/^### Passi$/### Steps/; s/^#### Blocco /#### Block /; s/^scrive:/writes:/; s/^dopo: nessuno$/after: none/; s/^dopo:/after:/; s/^| id | file | modifica | test |$/| id | file | change | test |/; s/^### Piano di test$/### Test plan/; s/^| ID | requisito | file | asserzione | mutazione |$/| ID | requirement | file | assertion | mutation |/' "$T/f2.md" > "$E/f2-mix.md"
expect 0 "^lint2: OK$" "mista lint2: formato 2 con sezioni italiane e inglesi = pulito" -- bash "$PC" lint2 "$E/f2-mix.md"
bash "$PC" gen "$E/f2-mix.md" >/dev/null 2>&1
cmp -s "$E/it-f2.run/counterproof/mutations.json" "$E/f2-mix.run/counterproof/mutations.json" && pass=$((pass+1)) ||
  { echo "FAIL [mista gen: mutations.json identico a quello del piano italiano]"; fail=$((fail+1)); }
# route: Risk surfaces in English and the Italian maat.json rules on the same paths = no disagreement
expect 0 "^Superfici rilevate: permessi, contratto-api$" "en route: superfici rilevate dai percorsi" -- bash "$PC" route "$E/f2.md"
expect 0 "^Superfici dichiarate: permessi, contratto-api$" "en route: Risk surfaces: permissions, api-contract = dichiarate permessi, contratto-api" -- bash "$PC" route "$E/f2.md"
refute "^Discordanza" "en route: Risk surfaces inglese + regola maat.json italiana sullo stesso percorso = nessuna discordanza" -- bash "$PC" route "$E/f2.md"
sed 's/^Risk surfaces: permissions, api-contract$/Risk surfaces: none/' "$E/f2.md" > "$E/f2-decl.md"
expect 0 "^Discordanza: rilevata e non dichiarata: permessi, contratto-api$" "en route: none con superfici rilevate = discordanza" -- bash "$PC" route "$E/f2-decl.md"
printf '%s\n' "# T" "## Implementation plan" "Plan status: DRAFT" "Test level: min" "Risk surfaces: none" \
  "1. In \`modules/app/apps/admin/components/Bar.vue\` change the text." > "$E/light.md"
expect 0 "^Percorso: leggero" "en route: Risk surfaces: none, piano piccolo = Percorso: leggero" -- bash "$PC" route "$E/light.md"
# maat.json with English superficie values: mapped to the canonical token → an Italian declaration agrees
"$FIC_PY" -c 'import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
m = {"permessi": "permissions", "dati": "data", "contratto-api": "api-contract", "logica-condivisa": "shared-logic"}
for x in c["piano"]["superfici_critiche"]:
    x["superficie"] = m.get(x["superficie"], x["superficie"])
json.dump(c, open(sys.argv[2], "w", encoding="utf-8"), indent=1)' "$R/.claude/maat.json" "$E/maat-en.json"
expect 0 "^Superfici rilevate: permessi, contratto-api$" "en maat.json: superficie inglese mappata al token canonico" -- env MAAT_CONFIG="$E/maat-en.json" bash "$PC" route "$T/f2.md"
refute "^Discordanza" "en maat.json: superficie inglese + dichiarazione italiana = nessuna discordanza" -- env MAAT_CONFIG="$E/maat-en.json" bash "$PC" route "$T/f2.md"
grep -q '"permissions"' "$E/maat-en.json" && pass=$((pass+1)) || { echo "FAIL [en maat.json: la configurazione di prova non ha valori inglesi]"; fail=$((fail+1)); }
# skeleton and the "Split: rejected" decision
expect 0 "^Scheletro: SOTTO IL TETTO" "en skeleton: sotto il tetto" -- bash "$PC" skeleton "$E/f2.md"
expect 0 "^Passi: 3 \(tetto 15\)$" "en skeleton: conta i passi di ### Steps" -- bash "$PC" skeleton "$E/f2.md"
expect 0 "^File: 4 \(tetto 40\)$" "en skeleton: conta i file (Touched files + passi)" -- bash "$PC" skeleton "$E/f2.md"
expect 0 "^Superfici: permessi, contratto-api$" "en skeleton: superfici canoniche" -- bash "$PC" skeleton "$E/f2.md"
awk '{ print } /^\| P3 \|/ { for (i = 4; i <= 16; i++) printf "| P%d | `modules/app/apps/admin/components/Bar.vue` | x | T2 |\n", i }' "$E/f2.md" > "$E/sk-passi.md"
expect 1 "^Scheletro: SOPRA IL TETTO — passi 16 > 15: proposta di taglio" "en skeleton: 16 passi = sopra il tetto" -- bash "$PC" skeleton "$E/sk-passi.md"
sed 's/^# Title$/&\nSplit: rejected — 2026-10-30, single plan/' "$E/sk-passi.md" > "$E/sk-rejected.md"
expect 0 "^Scheletro: SOPRA IL TETTO — passi 16 > 15: taglio rifiutato dall utente" "en skeleton: Split: rejected = nessuno stop (uscita 0)" -- bash "$PC" skeleton "$E/sk-rejected.md"
# chains: Children:, Depends on:, Interface for:, FR/AC ids
CE="$E/catena"; mkdir -p "$CE"
printf '%s\n' "# Mother" "Children: spec-n-1-a, spec-n-2-b" "## Context" "Big." "## 2. Functional requirements" "### FR1 — one" "### FR2 — two" \
  "- **FR2.1** detail" "## Acceptance criteria" "- AC1 — visible" "- AC2 — saved" "## Out of scope" "- FR9 is not a requirement here" > "$CE/spec-n.md"
kid_en() { # $1 file, $2 Depends on, $3 Interface for, then the ids (any family)
  local f=$1 dep=$2 itf=$3 i; shift 3
  { printf '%s\n' "# Child" "Depends on: $dep" "Interface for: $itf" "## Functional requirements"
    for i in "$@"; do case $i in RF*|FR*) printf '1. %s — text\n' "$i" ;; esac; done
    printf '%s\n' "## Acceptance criteria"
    for i in "$@"; do case $i in CA*|AC*) printf -- '- %s — text\n' "$i" ;; esac; done; } > "$f"
}
kid_en "$CE/spec-n-1-a.md" none '`src/x.py` — api' FR1 FR2 FR2.1 AC1
kid_en "$CE/spec-n-2-b.md" spec-n-1-a none AC2
expect 0 "^split: OK — 5 ID della madre in 2 figlie" "en split: madre FR/AC, figlie dalla riga Children:" -- bash "$PC" split "$CE/spec-n.md" "$CE/spec-n-1-a.md" "$CE/spec-n-2-b.md"
expect 0 "^split: OK — 5 ID della madre in 2 figlie" "en split: le figlie dalla riga Children: della madre" -- bash "$PC" split "$CE/spec-n.md"
kid_en "$CE/spec-n-2-b.md" spec-n-1-a none
expect 1 "VIOLAZIONE: AC2 della madre non sta in nessuna figlia \(perso\)" "en split: un AC perso = STOP" -- bash "$PC" split "$CE/spec-n.md"
kid_en "$CE/spec-n-2-b.md" spec-n-1-a none AC2; sed -i '/^Depends on:/d' "$CE/spec-n-2-b.md"
expect 1 "VIOLAZIONE: spec-n-2-b: manca la riga 'Dipende da:'" "en split: figlia senza Depends on: = STOP" -- bash "$PC" split "$CE/spec-n.md"
kid_en "$CE/spec-n-2-b.md" spec-n-1-a none AC2
# Italian mother (RF/CA) and children written in English that reuse the mother's ids: OK; FR in their place: STOP
CI="$E/catena-it"; mkdir -p "$CI"; cp "$C/spec-m.md" "$CI/spec-m.md"
kid_en "$CI/spec-m-1-a.md" nessuno '`src/x.py` — api' RF1 RF2 RF2.1 CA1
kid_en "$CI/spec-m-2-b.md" spec-m-1-a none RF3 CA2
expect 0 "^split: OK — 6 ID della madre in 2 figlie" "split: madre italiana (RF) + figlie inglesi che riusano RF = OK" -- bash "$PC" split "$CI/spec-m.md"
kid_en "$CI/spec-m-2-b.md" spec-m-1-a none FR3 CA2
expect 1 "VIOLAZIONE: spec-m-2-b: FR3 non e' un ID della madre" "split: FR3 al posto di RF3 = id distinto, nessun alias (STOP)" -- bash "$PC" split "$CI/spec-m.md"
kid_en "$CI/spec-m-2-b.md" spec-m-1-a none RF3 CA2
sed 's/^Children: .*/&\nFiglie: spec-n-1-a, spec-n-2-b/' "$CE/spec-n.md" > "$CE/spec-n2.md"
expect 1 "VIOLAZIONE: la madre ha sia 'Figlie:' sia 'Children:'" "en split: Figlie: e Children: nella madre = VIOLAZIONE" -- bash "$PC" split "$CE/spec-n2.md" "$CE/spec-n-1-a.md" "$CE/spec-n-2-b.md"
rm -f "$CE/spec-n2.md"
# basis of a child found through the mother's Children: line
{ cat "$CE/spec-n-1-a.md"; printf '%s\n' "## Implementation plan" "Plan status: APPROVED" "1. Change \`src/x.py\`."; } > "$CE/x" && mv "$CE/x" "$CE/spec-n-1-a.md"
{ cat "$CE/spec-n-2-b.md"; printf '%s\n' "## Implementation plan" "Plan status: APPROVED" "Risk surfaces: none" "1. Use \`src/x.py\`."; } > "$CE/x" && mv "$CE/x" "$CE/spec-n-2-b.md"
expect 0 "^Catena: anello 2/2 di spec-n · precedente spec-n-1-a \(aperto\)$" "en basis: la figlia trovata dalla riga Children: della madre" -- bash "$PC" basis "$CE/spec-n-2-b.md"
expect 0 "^Basis: spec [0-9a-f]{12} · plan [0-9a-f]{12} · madre [0-9a-f]{12} · prec [0-9a-f]{12}$" "en basis: madre e prec anche con Children:" -- bash "$PC" basis "$CE/spec-n-2-b.md"
# closed: the review read under "## Implementation review"
printf '%s\n' "## Implementation review" "Review status: APPROVED" "Feature status: IMPLEMENTED" >> "$CE/spec-n-1-a.md"
expect 1 "^Anello: APERTO — nessuna riga Finalize: IMPLEMENTED$" "en closed: Review status letta sotto ## Implementation review" -- bash "$PC" closed "$CE/spec-n-1-a.md"
# counterproofs by mutation: without the English alternative of a reader, the English fixture goes red
if mutpc noen-zone 's/\^## (Piano di implementazione|Implementation plan)\//^## Piano di implementazione\//'; then
  expect 1 "nessuna sezione" "controprova: senza 'Implementation plan' in annotate la spec inglese non ha piano" -- env MAAT_ROOT="$PLUGIN_DIR" bash "$T/pcm-noen-zone/plan-check.sh" contract "$E/base.md"
else echo "FAIL [controprova annotate: la mutazione non si applica]"; fail=$((fail+1)); fi
if mutpc noen-tz 's/(Piano di test|Test plan)\/ { in_t = 1/Piano di test\/ { in_t = 1/'; then
  expect 0 "^Obbligo: permessi" "controprova: senza 'Test plan' in test_zone il [floor:] inglese non conta (obbligo)" -- env MAAT_ROOT="$PLUGIN_DIR" bash "$T/pcm-noen-tz/plan-check.sh" contract "$E/base.md"
else echo "FAIL [controprova test_zone: la mutazione non si applica]"; fail=$((fail+1)); fi
if mutpc noen-sec 's/ "test plan": "Piano di test",//'; then
  expect 1 "manca la sezione ### Piano di test" "controprova: senza 'test plan' in SEC il piano formato 2 inglese perde la sezione" -- env MAAT_ROOT="$PLUGIN_DIR" bash "$T/pcm-noen-sec/plan-check.sh" lint2 "$E/f2.md"
else echo "FAIL [controprova SEC: la mutazione non si applica]"; fail=$((fail+1)); fi

# ── 1.4.0: English twins of the lint and delta families (the other families sit next to their Italian case: route,
# s2, skeleton, l2). The keyword stays Italian (D2: the skills read it), the explanation follows the language.
printf '%s\n' "# T" "## Piano di implementazione" "Plan status: DRAFT" "Superfici a rischio: boh" > "$T/en-lint.md"
expect 1 "^VIOLAZIONE: unknown surface 'boh' in 'Risk surfaces' — only bare tokens of the vocabulary: " "en (MAAT_LINGUA=en) lint: VIOLAZIONE e la spiegazione in inglese" -- env MAAT_LINGUA=en bash "$PC" lint "$T/en-lint.md"
expect 1 "^AVVISO: 'Test level:' missing from the plan \(legacy spec\?\) — on reopening, Step 1 adds it$" "en (MAAT_LINGUA=en) lint: AVVISO e la spiegazione in inglese" -- env MAAT_LINGUA=en bash "$PC" lint "$T/en-lint.md"
refute "superficie sconosciuta|assente nel piano|in riapertura" "en (MAAT_LINGUA=en) lint: nessuna spiegazione italiana" -- env MAAT_LINGUA=en bash "$PC" lint "$T/en-lint.md"
expect 1 "^VIOLAZIONE: superficie sconosciuta 'boh'" "it lint: la stessa spec in italiano (gemello)" -- bash "$PC" lint "$T/en-lint.md"
expect 1 "^ERRORE DURO: baseline missing or empty \(.*\) — redo the round at full scope, never APPROVED$" "en (MAAT_LINGUA=en) delta: ERRORE DURO e la spiegazione in inglese" -- env MAAT_LINGUA=en bash "$PC" delta "$T/nessuna-baseline" "$T/en-lint.md"
cp "$T/en-lint.md" "$T/en-lint.copy"
expect 1 "^ERRORE DURO: empty diff — no revision recorded" "en (MAAT_LINGUA=en) delta: diff vuoto, ERRORE DURO in inglese" -- env MAAT_LINGUA=en bash "$PC" delta "$T/en-lint.copy" "$T/en-lint.md"
refute "rifai il giro|nessuna revisione" "en (MAAT_LINGUA=en) delta: nessuna spiegazione italiana" -- env MAAT_LINGUA=en bash "$PC" delta "$T/en-lint.copy" "$T/en-lint.md"
expect 1 "^ERRORE DURO: diff vuoto — nessuna revisione registrata" "it delta: lo stesso caso in italiano (gemello)" -- bash "$PC" delta "$T/en-lint.copy" "$T/en-lint.md"
rm -f "$T/en-lint.copy"

# ── oracle (safety constraint 2 of the 1.3.0 plan): on every Italian fixture of this file, plan-check.sh of
# 1.2.1 (a2c5b99) and the current one give the SAME output, byte for byte: basis (plan fingerprint), contract and
# lint everywhere, lint2 and route on the format 2 fixtures. Opt-in (MAAT_ORACOLO_121=1: it doubles the run time and
# is tied to that commit); a copy without git or without a2c5b99: motivated SKIP.
OR="$T/pc-121/plan-check.sh"; mkdir -p "$T/pc-121/lib"; cp "$HERE/lib/maat-paths.sh" "$T/pc-121/lib/"
if [ "${MAAT_ORACOLO_121:-0}" != 1 ]; then
  echo "SKIP [oracolo 1.2.1 sulle fixture italiane — attivalo con MAAT_ORACOLO_121=1]"
elif git -c safe.directory='*' -C "$HERE" cat-file -e a2c5b99:plugins/maat/scripts/plan-check.sh 2>/dev/null; then
  git -c safe.directory='*' -C "$HERE" show a2c5b99:plugins/maat/scripts/plan-check.sh > "$OR"
  ord=""; nor=0
  while IFS= read -r f; do
    nor=$((nor + 1))
    for sc in basis contract lint; do
      a=$(env MAAT_ROOT="$PLUGIN_DIR" bash "$OR" "$sc" "$f" 2>&1; echo "rc=$?"); b=$(bash "$PC" "$sc" "$f" 2>&1; echo "rc=$?")
      [ "$a" = "$b" ] || ord="$ord $(basename "$f"):$sc"
    done
    case $(basename "$f") in f2*.md)
      for sc in lint2 route; do
        a=$(env MAAT_ROOT="$PLUGIN_DIR" bash "$OR" "$sc" "$f" 2>&1; echo "rc=$?"); b=$(bash "$PC" "$sc" "$f" 2>&1; echo "rc=$?")
        [ "$a" = "$b" ] || ord="$ord $(basename "$f"):$sc"
      done ;;
    esac
  done < <(find "$T" "$C" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)   # set -f: no glob here
  [ -z "$ord" ] && [ "$nor" -gt 100 ] && pass=$((pass+1)) || { echo "FAIL [oracolo 1.2.1: output diverso sulle fixture italiane ($nor file):$ord]"; fail=$((fail+1)); }
else
  echo "SKIP [oracolo 1.2.1 sulle fixture italiane — nessun a2c5b99:plugins/maat/scripts/plan-check.sh in $HERE]"
fi
# ── constraint 2 of the 1.4.0 plan: the stdout of basis and contract (basis enters State, the contract keys are
# read by the skills) is byte for byte the same with MAAT_LINGUA=it, with MAAT_LINGUA=en and with plan-check.sh of
# v1.3.0, on every fixture of this file (Italian and English), exit code included. Stdout only, as cycle-state.sh and
# driver.py read it (2>/dev/null). Opt-in like the oracle above (MAAT_VINCOLO2=1, or MAAT_ORACOLO_121=1 runs both):
# three runs per fixture. A copy without git or without the tag v1.3.0: motivated SKIP.
V2="$T/pc-130/plan-check.sh"; mkdir -p "$T/pc-130/lib"
if [ "${MAAT_VINCOLO2:-0}" != 1 ] && [ "${MAAT_ORACOLO_121:-0}" != 1 ]; then
  echo "SKIP [vincolo 2 della 1.4.0: basis e contract uguali in it, en e v1.3.0 — attivalo con MAAT_VINCOLO2=1]"
elif git -c safe.directory='*' -C "$HERE" cat-file -e v1.3.0:plugins/maat/scripts/plan-check.sh 2>/dev/null; then
  git -c safe.directory='*' -C "$HERE" show v1.3.0:plugins/maat/scripts/plan-check.sh > "$V2"
  git -c safe.directory='*' -C "$HERE" show v1.3.0:plugins/maat/scripts/lib/maat-paths.sh > "$T/pc-130/lib/maat-paths.sh"
  v2d=""; nv2=0
  while IFS= read -r f; do
    nv2=$((nv2 + 1))
    for sc in basis contract; do
      a=$(env MAAT_ROOT="$PLUGIN_DIR" bash "$V2" "$sc" "$f" 2>/dev/null; echo "rc=$?")
      bi=$(MAAT_LINGUA=it bash "$PC" "$sc" "$f" 2>/dev/null; echo "rc=$?")
      be=$(MAAT_LINGUA=en bash "$PC" "$sc" "$f" 2>/dev/null; echo "rc=$?")
      [ "$a" = "$bi" ] || v2d="$v2d $(basename "$f"):$sc:it"
      [ "$a" = "$be" ] || v2d="$v2d $(basename "$f"):$sc:en"
    done
  done < <(find "$T" "$C" "$E" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)   # set -f: no glob here
  [ -z "$v2d" ] && [ "$nv2" -gt 100 ] && pass=$((pass+1)) || { echo "FAIL [vincolo 2: basis/contract diversi da v1.3.0 ($nv2 file):$v2d]"; fail=$((fail+1)); }
else
  echo "SKIP [vincolo 2 della 1.4.0 — nessun v1.3.0:plugins/maat/scripts/plan-check.sh in $HERE]"
fi
unset PLAN_CHECK_ROOT FIC_PY

# ── usage ────────────────────────────────────────────────────────────────────────────────────────
expect 2 "uso:" "argomenti sbagliati = uscita 2" -- bash "$PC" boh

echo "plan-check.test.sh: $pass passati, $fail falliti"
[ "$fail" -eq 0 ]
