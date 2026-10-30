#!/usr/bin/env bash
# test-review-surface.sh — asserzioni su review-surface.sh, in un repo git usa-e-getta.
#
#   bash .claude/skills/implementation-review-cycle/test-review-surface.sh
#   SCRIPT=/percorso/variante.sh bash .../test-review-surface.sh   # controprova su una mutazione
#
# Ogni caso ha una controprova incorporata (lo stesso controllo, nella condizione opposta, deve
# dare l'esito opposto): un'asserzione che non puo' fallire non conta come copertura.

set -uo pipefail
set -f

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=${SCRIPT:-$HERE/review-surface.sh}
case "$SCRIPT" in /*|[A-Za-z]:*) ;; *) SCRIPT="$PWD/$SCRIPT" ;; esac
[ -f "$SCRIPT" ] || { echo "script non trovato: $SCRIPT"; exit 2; }

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
ko()  { FAIL=$((FAIL+1)); echo "  FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       | /'; }
has() { printf '%s\n' "$1" | grep -Eq "$2"; }
rs()  { bash "$SCRIPT" "$@"; }
field() { printf '%s\n' "$1" | sed -n "s/^$2: //p" | head -1; }

WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 2
git init -q .
git config user.email t@t; git config user.name t
git config core.autocrlf false; git config core.safecrlf false
mkdir -p src tests
printf 'a\n' > src/a.py
printf 'b\n' > src/b.py
printf 'out\n' > src/other.py
printf 'def test_a():\n    assert f() == 1\n    assert g() == 2\n' > tests/test_a.py
printf 'line1\r\nline2\r\n' > src/crlf.txt          # CRLF committato
printf '#!/bin/sh\necho x\n' > run.sh
chmod +x run.sh   # pk08: dove core.filemode vale (Linux) il file sul disco deve avere il modo dell'indice
git add -A; git update-index --chmod=+x run.sh
git commit -qm init
git config core.autocrlf true                      # come sulla macchina Windows del progetto
HEAD_TREE=$(git rev-parse 'HEAD^{tree}')

echo "1. snapshot pulito, autocrlf=true, CRLF committato + 100755"
out=$(rs snapshot)
if [ "$(field "$out" Tree)" = "$HEAD_TREE" ] && has "$out" '^  \(none\)$'; then ok "nessun cambio fittizio"; else ko "cambi fittizi su tree pulito" "$out"; fi

echo "2. unstaged + staged + untracked + deleted + renamed entrano tutti"
printf 'a2\n' > src/a.py                            # unstaged
printf 'b2\n' > src/b.py; git add src/b.py          # staged
printf 'new\n' > src/new.py                         # untracked
git rm -q src/other.py                              # deleted
git mv tests/test_a.py tests/test_renamed.py        # renamed
out=$(rs snapshot)
for pat in $'^  M\tsrc/a.py$' $'^  M\tsrc/b.py$' $'^  A\tsrc/new.py$' $'^  D\tsrc/other.py$' $'^  R[0-9]+\ttests/test_a.py\ttests/test_renamed.py$'; do
  if has "$out" "$pat"; then ok "presente: $pat"; else ko "manca: $pat" "$out"; fi
done
if has "$out" 'crlf.txt|run.sh'; then ko "file non toccati riportati come cambiati" "$out"; else ok "controprova: i file non toccati non compaiono"; fi
# L'indice reale NON deve essere toccato: new.py resta untracked.
if git status --porcelain | grep -q '^?? src/new.py$'; then ok "indice reale intatto"; else ko "l'indice reale e' stato modificato"; fi

BASE=$(field "$out" Base); TREE=$(field "$out" Tree)
PF="$WORK/../paths.$$"; trap 'rm -rf "$WORK" "$PF"' EXIT
git diff --name-only --no-renames "$BASE" "$TREE" > "$PF"
FP=$(rs fingerprint --tree "$TREE" --paths-file "$PF" | sed -n 's/^Fingerprint: //p')

echo "3. check subito dopo = FRESH"
out=$(rs check --base "$BASE" --tree "$TREE" --paths-file "$PF" --fingerprint "$FP")
if has "$out" '^Status: FRESH$'; then ok "fresh"; else ko "atteso FRESH" "$out"; fi

echo "4. commit dopo l'approvazione = ancora FRESH (base registrata, non HEAD)"
git add -A; git commit -qm impl
out=$(rs check --base "$BASE" --tree "$TREE" --paths-file "$PF" --fingerprint "$FP")
if has "$out" '^Status: FRESH$'; then ok "fresh dopo commit"; else ko "un commit non e' una modifica" "$out"; fi

echo "5. file NUOVO comparso dopo l'approvazione (anche fuori dal manifest) = STALE"
printf 'unrelated\n' > src/unrelated_flow.py
git -c core.autocrlf=false add src/unrelated_flow.py
out=$(rs check --base "$BASE" --tree "$TREE" --paths-file "$PF" --fingerprint "$FP")
# Un file NUOVO rispetto alla base e' superficie nuova: deve dare STALE (non sappiamo se e' della feature).
if has "$out" '^Status: STALE$' && has "$out" $'NEW-SURFACE\tsrc/unrelated_flow.py'; then ok "file nuovo dopo l'approvazione = NEW-SURFACE"; else ko "file nuovo non rilevato" "$out"; fi
git rm -q --cached src/unrelated_flow.py; rm -f src/unrelated_flow.py
out=$(rs check --base "$BASE" --tree "$TREE" --paths-file "$PF" --fingerprint "$FP")
if has "$out" '^Status: FRESH$'; then ok "controprova: tolto il file, torna FRESH"; else ko "controprova fallita" "$out"; fi

echo "6. modifica di codice dopo l'approvazione = STALE, non gate-only"
printf 'a3\n' > src/a.py
out=$(rs check --base "$BASE" --tree "$TREE" --paths-file "$PF" --fingerprint "$FP")
if has "$out" '^Status: STALE$' && has "$out" $'M\tsrc/a.py' && has "$out" '^Gate-only eligible: no'; then ok "stale + delta + no gate-only"; else ko "atteso STALE su src/a.py" "$out"; fi
git checkout -q -- src/a.py

echo "7. solo un test AGGIUNTO (nessun indebolimento) = gate-only yes"
printf 'def test_a():\n    assert f() == 1\n    assert g() == 2\n\ndef test_b():\n    assert h() == 3\n' > tests/test_renamed.py
out=$(rs check --base "$BASE" --tree "$TREE" --paths-file "$PF" --fingerprint "$FP")
if has "$out" '^Gate-only eligible: yes$' && has "$out" '^Test signals: none$'; then ok "gate-only"; else ko "atteso gate-only yes" "$out"; fi

echo "8. assert rimosso + skip aggiunto = segnali, gate-only NO"
printf 'import pytest\n\n@pytest.mark.skip\ndef test_a():\n    assert f() == 1\n' > tests/test_renamed.py
out=$(rs check --base "$BASE" --tree "$TREE" --paths-file "$PF" --fingerprint "$FP")
if has "$out" 'REMOVED-ASSERTIONS tests/test_renamed.py: -1' && has "$out" 'ADDED-SKIP tests/test_renamed.py' && has "$out" '^Gate-only eligible: no'; then ok "indebolimento rilevato"; else ko "indebolimento NON rilevato" "$out"; fi
out=$(rs test-signals --from "$BASE" --to HEAD)
if has "$out" '^Test signals: none$'; then ok "controprova: la rinomina senza tagli non da' segnali"; else ko "falso positivo sulla rinomina" "$out"; fi
git checkout -q -- tests/test_renamed.py

echo "9. test cancellato = DELETED-TEST"
git rm -q tests/test_renamed.py
out=$(rs test-signals --from HEAD --to "$(git write-tree)")
if has "$out" '^DELETED-TEST tests/test_renamed.py$'; then ok "cancellazione rilevata"; else ko "cancellazione non rilevata" "$out"; fi
git reset -q HEAD -- tests/test_renamed.py; git checkout -q -- tests/test_renamed.py

echo "10. tree potato: ripiego sull'impronta"
FAKE=0123456789abcdef0123456789abcdef01234567
out=$(rs check --base "$BASE" --tree "$FAKE" --paths-file "$PF" --fingerprint "$FP")
if has "$out" '^Status: FRESH \(via fingerprint\)$'; then ok "fresh via fingerprint"; else ko "ripiego fallito" "$out"; fi
printf 'a4\n' > src/a.py
out=$(rs check --base "$BASE" --tree "$FAKE" --paths-file "$PF" --fingerprint "$FP")
if has "$out" '^Status: STALE \(via fingerprint'; then ok "controprova: stale via fingerprint"; else ko "modifica non vista dall'impronta" "$out"; fi
git checkout -q -- src/a.py
rs check --base "$BASE" --tree "$FAKE" --paths-file "$PF" >/dev/null; rc=$?
if [ "$rc" -eq 3 ]; then ok "senza impronta: UNKNOWN exit 3"; else ko "atteso exit 3, avuto $rc"; fi

echo "11. file di un ALTRO flusso, escluso dallo scope: non rende stale la review"
XFILE="$WORK/../excl.$$"; trap 'rm -rf "$WORK" "$PF" "$XFILE"' EXIT
printf 'altro\n' > src/other_flow.py
printf 'src/other_flow.py\n' > "$XFILE"
out=$(rs check --base "$BASE" --tree "$TREE" --paths-file "$PF" --fingerprint "$FP" --exclude-file "$XFILE")
if has "$out" '^Status: FRESH$'; then ok "escluso: fresh"; else ko "un file escluso ha invalidato la review" "$out"; fi
# ...ma se il file escluso esisteva gia' nel tree approvato e cambia, va SEGNALATO (file misto).
printf 'src/other_flow.py\nsrc/crlf.txt\n' > "$XFILE"
printf 'changed\r\n' > src/crlf.txt
out=$(rs check --base "$BASE" --tree "$TREE" --paths-file "$PF" --fingerprint "$FP" --exclude-file "$XFILE")
if has "$out" '^Status: FRESH$' && has "$out" $'EXCLUDED-CHANGED\tsrc/crlf.txt'; then ok "escluso cambiato: fresh ma segnalato"; else ko "EXCLUDED-CHANGED assente" "$out"; fi
git checkout -q -- src/crlf.txt
printf 'src/other_flow.py\n' > "$XFILE"
out=$(rs check --base "$BASE" --tree "$TREE" --paths-file "$PF" --fingerprint "$FP")
if has "$out" '^Status: STALE$' && has "$out" $'NEW-SURFACE\tsrc/other_flow.py'; then ok "controprova: senza esclusione e' superficie nuova"; else ko "controprova fallita" "$out"; fi
rm -f src/other_flow.py

echo "12. test RINOMINATO e svuotato nello stesso passo: il segnale non si perde"
git mv tests/test_renamed.py tests/test_moved.py
printf 'def test_a():\n    pass\n' > tests/test_moved.py
out=$(rs check --base "$BASE" --tree "$TREE" --paths-file "$PF" --fingerprint "$FP")
# Riscritto molto: git non lo vede come rinomina → DELETED-TEST. Poco: rinomina → REMOVED-ASSERTIONS.
if has "$out" 'REMOVED-ASSERTIONS tests/test_moved.py|DELETED-TEST tests/test_renamed.py' && has "$out" '^Gate-only eligible: no'; then ok "rinomina+svuotamento rilevati"; else ko "indebolimento nascosto dalla rinomina" "$out"; fi
git mv tests/test_moved.py tests/test_renamed.py; git checkout -q -- tests/test_renamed.py
# Variante "rinomina vera" (simile >50%): un'asserzione su tre tolta, riconosciuta come R.
printf 'def test_a():\n    assert f() == 1\n    assert g() == 2\n\ndef test_c():\n    x = 1\n    y = 2\n    return x + y\n' > tests/test_renamed.py
git add tests/test_renamed.py; git commit -qm more
B3=$(git rev-parse HEAD)
git mv tests/test_renamed.py tests/test_moved.py
printf 'def test_a():\n    assert f() == 1\n\ndef test_c():\n    x = 1\n    y = 2\n    return x + y\n' > tests/test_moved.py
git add tests/test_moved.py
out=$(rs test-signals --from "$B3" --to "$(git write-tree)")
if has "$out" 'REMOVED-ASSERTIONS tests/test_moved.py: -1'; then ok "rinomina riconosciuta: asserzione tolta vista"; else ko "rinomina: asserzione tolta persa" "$out"; fi
git reset -q --hard HEAD   # repo usa-e-getta: nessun residuo nell'indice per i casi dopo

echo "13. solo conftest/fixture cambiati: MAI gate-only"
printf 'import pytest\n@pytest.fixture\ndef f():\n    return lambda: 1\n' > tests/conftest.py
out=$(rs check --base "$BASE" --tree "$TREE" --paths-file "$PF" --fingerprint "$FP")
if has "$out" '^Gate-only eligible: no' && has "$out" $'NEW-SURFACE\ttests/conftest.py'; then ok "conftest escluso dal gate-only"; else ko "conftest ammesso al gate-only" "$out"; fi
rm -f tests/conftest.py
printf 'def fake():\n    return True\n' > tests/goals_fakes.py      # helper python, non un test
out=$(rs check --base "$BASE" --tree "$TREE" --paths-file "$PF" --fingerprint "$FP")
if has "$out" '^Gate-only eligible: no'; then ok "helper in tests/ escluso dal gate-only"; else ko "helper in tests/ ammesso al gate-only" "$out"; fi
rm -f tests/goals_fakes.py

echo "14. path NON ASCII: nel manifest senza virgolette, e il delta lo vede"
printf 'x\n' > "src/città.py"
out=$(rs snapshot)
if has "$out" $'^  A\tsrc/città.py$'; then ok "path non ASCII stampato in chiaro"; else ko "path non ASCII quotato" "$out"; fi
B2=$(field "$out" Base); T2=$(field "$out" Tree)
PF2="$WORK/../paths2.$$"; trap 'rm -rf "$WORK" "$PF" "$XFILE" "$PF2"' EXIT
printf 'src/città.py\n' > "$PF2"
printf 'y\n' > "src/città.py"
out=$(rs check --base "$B2" --tree "$T2" --paths-file "$PF2")
if has "$out" '^Status: STALE$' && has "$out" $'M\tsrc/città.py'; then ok "modifica del path non ASCII vista"; else ko "modifica del path non ASCII persa" "$out"; fi
rm -f "src/città.py"

echo "15. gate-only: nei test GIA' esistenti solo aggiunte pure (niente setup condiviso ne' controllo)"
git reset -q --hard HEAD
mkdir -p web
# Valore atteso su una riga di continuazione (come la scrive prettier): nessun token di asserzione.
printf "it('nega', async () => {\n  const r = await call('viewer')\n  expect(r.status).toBe(\n    403,\n  )\n  expect(\n    r.body,\n  ).toStrictEqual(\n    {},\n  )\n})\n" > web/deny.test.ts
printf "it('altro', () => {\n  expect(1).toBe(1)\n})\n" > web/other.test.ts
printf 'def test_ok():\n    r = call()\n    assert r == 1\n    mock.assert_called_once_with(1)\n' > tests/test_ok.py
git -c core.autocrlf=false add -A; git commit -qm gates
out=$(rs snapshot); B4=$(field "$out" Base); T4=$(field "$out" Tree)
PF4="$WORK/../paths4.$$"; trap 'rm -rf "$WORK" "$PF" "$XFILE" "$PF2" "$PF4"' EXIT
printf 'web/deny.test.ts\ntests/test_ok.py\n' > "$PF4"
chk() { rs check --base "$B4" --tree "$T4" --paths-file "$PF4"; }
# checkout senza CRLF: il sed di Linux (a differenza di quello di MSYS) non riconosce ^…$ su una riga che finisce in \r
back() { git -c core.autocrlf=false checkout -q -- web tests; git clean -qfd web tests >/dev/null; }
gate_no() { # $1 descrizione, $2 motivo atteso (regex)
  if has "$out" "^Gate-only eligible: no — ($2)"; then ok "$1"; else ko "$1" "$out"; fi; }
gate_yes() { if has "$out" '^Gate-only eligible: yes$'; then ok "$1"; else ko "$1" "$out"; fi; }

sed -i 's/^    assert r == 1$/    assert r == 2/' tests/test_ok.py                 # 1 -> 2 sulla stessa riga
out=$(chk)
if has "$out" 'REMOVED-ASSERTIONS tests/test_ok.py: -1 \+1'; then ok "asserzione cambiata sulla stessa riga: gia' presa"; else ko "asserzione cambiata non vista" "$out"; fi
gate_no "stessa riga: gate-only chiuso" "segnali"; back

sed -i 's/^    403,$/    200,/' web/deny.test.ts                                # 403 -> 200 a capo
out=$(chk)
if has "$out" '^Test signals: none$'; then ok "controprova: i segnali NON vedono il valore a capo"; else ko "atteso nessun segnale" "$out"; fi
gate_no "valore atteso a capo cambiato: gate-only chiuso" "righe tolte o modificate.*web/deny.test.ts"; back

sed -i '/^  ).toStrictEqual($/d; /^    {},$/d' web/deny.test.ts                        # matcher tolto, expect( resta
out=$(rs test-signals --from "$T4" --to "$(rs snapshot | sed -n 's/^Tree: //p')")
if has "$out" 'REMOVED-ASSERTIONS web/deny.test.ts: -1'; then ok "matcher a capo senza expect( riconosciuto"; else ko "toStrictEqual a capo non visto" "$out"; fi; back
sed -i '/assert_called_once_with/d' tests/test_ok.py
out=$(chk)
if has "$out" 'REMOVED-ASSERTIONS tests/test_ok.py: -1'; then ok "mock.assert_called_once_with riconosciuto"; else ko "assert_called_* non visto" "$out"; fi; back

sed -i 's/^def test_ok():$/def test_ok():\n    return/' tests/test_ok.py          # return in testa
out=$(chk)
if has "$out" '^Test signals: none$'; then ok "controprova: return in testa invisibile ai segnali"; else ko "atteso nessun segnale" "$out"; fi
gate_no "return in testa a un test esistente: gate-only chiuso" "flusso di controllo"; back

sed -i 's/^    assert r == 1$/    if False:\n        assert r == 1/' tests/test_ok.py  # if attorno, re-indent
out=$(chk); gate_no "if attorno a un'asserzione esistente: gate-only chiuso" "segnali|righe tolte|flusso"; back

sed -i '1i vi.mock("../auth")' web/deny.test.ts                                    # setup condiviso, in manifest
out=$(chk); gate_no "vi.mock aggiunto a un test esistente: gate-only chiuso" "setup condiviso.*web/deny.test.ts"; back

printf 'beforeEach(() => {})\n' >> web/other.test.ts                              # FUORI manifest
out=$(chk)
if has "$out" $'NEW-SURFACE\tweb/other.test.ts'; then ok "test esistente fuori manifest = NEW-SURFACE"; else ko "fuori manifest non visto" "$out"; fi
gate_no "beforeEach aggiunto a un test esistente fuori manifest: gate-only chiuso" "setup condiviso.*web/other.test.ts"; back

printf "vi.mock('../auth')\nbeforeEach(() => {})\nit('n', () => {\n  if (x) {\n    return\n  }\n  expect(1).toBe(1)\n})\n" > web/nuovo.test.ts
out=$(chk); gate_yes "controprova: file di test NUOVO con vi.mock/beforeEach/if = gate-only"; back

printf '\ndef test_two():\n    assert call() == 2\n' >> tests/test_ok.py            # funzione nuova pura
out=$(chk); gate_yes "controprova: funzione nuova pura in un test esistente = gate-only"; back

printf "\n\n" >> web/deny.test.ts                                                   # solo righe vuote
out=$(chk); gate_yes "controprova: righe vuote aggiunte = gate-only"; back

git mv web/deny.test.ts web/deny2.test.ts                                           # rinomina pura
out=$(chk); gate_no "rinomina pura: gate-only chiuso (falso positivo accettato)" "righe tolte"
git mv web/deny2.test.ts web/deny.test.ts; back

echo "N. tree e diff (per touched.txt e per il reviewer senza Bash), in un repo a parte"
mkdir "$WORK/d" && cd "$WORK/d" || exit 2
git init -q .; git config user.email t@t; git config user.name t; git config core.autocrlf false
printf 'uno\ndue\n' > a.py; printf 'x\n' > old.py; printf 'fuori\n' > other.py
git add -A; git commit -qm init
D0=$(rs tree)
if [ "$D0" = "$(git rev-parse 'HEAD^{tree}')" ]; then ok "tree su working tree pulito = tree di HEAD"; else ko "tree diverso da HEAD su tree pulito" "$D0"; fi
printf 'uno\nDUE\n' > a.py; printf 'nuovo\n' > new.py; git mv old.py renamed.py; printf 'y\n' > other.py
D1=$(rs tree)
if [ "$D1" = "$(field "$(rs snapshot)" Tree)" ]; then ok "tree = Tree di snapshot"; else ko "tree diverso da snapshot"; fi
if [ "$D1" != "$D0" ]; then ok "controprova: tree cambia col working tree"; else ko "tree non cambia"; fi
printf 'a.py\nnew.py\nold.py\nrenamed.py\n' > "$WORK/dscope"
idx=$(rs diff --from "$D0" --to "$D1" --paths-file "$WORK/dscope" --out "$WORK/d.diff")
for pat in $'^a.py\toffset=1 limit=' $'^new.py\toffset=' $'^old.py → renamed.py\toffset='; do
  if has "$idx" "$pat"; then ok "indice: $pat"; else ko "indice senza: $pat" "$idx"; fi
done
if has "$idx" 'other.py'; then ko "path fuori scope nell'indice" "$idx"; else ok "controprova: path fuori scope assente"; fi
if grep -q '^+nuovo$' "$WORK/d.diff"; then ok "file nuovo NON tracciato presente nel diff"; else ko "file nuovo assente dal diff"; fi
# offset/limit: il pezzo indicato per new.py contiene la sua intestazione e il suo contenuto, e nient'altro
o=$(printf '%s\n' "$idx" | sed -n 's/^new.py\toffset=\([0-9]*\) limit=\([0-9]*\)$/\1 \2/p')
piece=$(sed -n "${o% *},$(( ${o% *} + ${o#* } - 1 ))p" "$WORK/d.diff")
if has "$piece" '^diff --git a/new.py b/new.py$' && has "$piece" '^\+nuovo$' && ! has "$piece" 'a.py|renamed'; then ok "offset/limit delimitano il file"; else ko "offset/limit sbagliati" "$piece"; fi
total=0; while IFS=$'\t' read -r _ ol; do l=${ol#*limit=}; total=$((total + l)); done <<< "$idx"
if [ "$total" -eq "$(wc -l < "$WORK/d.diff")" ]; then ok "i pezzi coprono tutto il file"; else ko "i pezzi non coprono il file ($total righe)"; fi
: > "$WORK/dempty"
if rs diff --from "$D0" --to "$D1" --paths-file "$WORK/dempty" --out "$WORK/x.diff" 2>/dev/null; then ko "scope vuoto accettato"; else ok "scope vuoto = errore"; fi
printf 'other.py\n' > "$WORK/dsame"
if has "$(rs diff --from "$D1" --to "$D1" --paths-file "$WORK/dsame" --out "$WORK/y.diff")" 'nessuna differenza'; then ok "nessuna differenza dichiarata"; else ko "diff vuoto non dichiarato"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
