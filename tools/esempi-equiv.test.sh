#!/usr/bin/env bash
# esempi-equiv.test.sh — the public equivalence corpus, tools/esempi-equiv/ (Maat 1.5.0). A test of the repo only.
#   bash tools/esempi-equiv.test.sh          (Git Bash or Linux)
# Block A of the 1.5.0 plan (the builder):
#   1. the whole corpus built twice, in two folders and at two different seconds of the clock → the same fingerprint
#      (driver.py equiv --impronta, printed by the builder), exit 0, no placeholder left;
#   2. the manifests: every row of righe.list and every branch of rami-valida.list has a case in casi.tsv, every spec
#      and every jsonl of the built corpus is in casi.tsv and vice versa, no counted jsonl is empty;
#   3. a model with a placeholder outside the list, or naming a state that does not exist → exit 2.
# Counterproof: a copy of the builder without the fixed dates (the DATE-FISSE line) → two builds of a mini-repo whose
# files carry the sha of the base commit give two fingerprints (the determinism case would be red).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
EQ=$ROOT/tools/esempi-equiv
B=$EQ/costruisci.sh
pass=0 fail=0
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
check() { # $1 description, $2 condition (eval), [$3 detail on failure]
  if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$1]"; [ -n "${3:-}" ] && printf '%s\n' "$3" | sed 's/^/    /'; fi
}
impronta() { sed -n 's/^impronta //p' "$1"; }
nuovo_secondo() { # waits until date +%s is past $1 (two commits in the same second would give the same sha anyway)
  while [ "$(date +%s)" -le "$1" ]; do sleep 1; done
}

# --- 1. determinism ---
t0=$(date +%s)
bash "$B" "$T/c1" > "$T/c1.out" 2>&1; rc1=$?
s1=$(date +%s); nuovo_secondo "$s1"
bash "$B" "$T/c2" > "$T/c2.out" 2>&1; rc2=$?
echo "esempi-equiv: costruzione $(( ($(date +%s) - t0) / 2 ))s (media di due)"
check "il corpus si costruisce (exit 0, due volte)" '[ $rc1 -eq 0 ] && [ $rc2 -eq 0 ]' "$(tail -5 "$T/c1.out"; tail -5 "$T/c2.out")"
I1=$(impronta "$T/c1.out"); I2=$(impronta "$T/c2.out")
check "due costruzioni, in cartelle e secondi diversi → la stessa impronta" '[[ $I1 =~ ^[0-9a-f]{64}$ ]] && [ "$I1" = "$I2" ]' "$I1 / $I2"
check "  nessun segnaposto rimasto nel corpus costruito" '[ -z "$(grep -rlF "{{" "$T/c1"/*/.claude 2>/dev/null)" ]'
grep '^esempi-equiv: ' "$T/c1.out" | tail -1

# --- 2. manifests ---
casi() { tr -d '\r' < "$EQ/casi.tsv" | grep -v '^#' | grep .; }
lista() { tr -d '\r' < "$1" | grep -v '^#' | grep . | cut -f1 | LC_ALL=C sort -u; }
manca_r=$(comm -23 <(lista "$EQ/righe.list") <(casi | awk -F'\t' '$1 == "spec" { print $5 }' | LC_ALL=C sort -u))
check "ogni riga di righe.list ha almeno un caso" '[ -z "$manca_r" ]' "$manca_r"
fuori_r=$(comm -13 <(lista "$EQ/righe.list") <(casi | awk -F'\t' '$1 == "spec" { print $5 }' | LC_ALL=C sort -u))
check "  e ogni spec di casi.tsv ha un'etichetta di righe.list" '[ -z "$fuori_r" ]' "$fuori_r"
manca_v=$(comm -23 <(lista "$EQ/rami-valida.list") <(casi | awk -F'\t' '$1 == "jsonl" { print $5 }' | tr ',' '\n' | LC_ALL=C sort -u))
check "ogni ramo di rami-valida.list ha almeno un jsonl" '[ -z "$manca_v" ]' "$manca_v"
fuori_v=$(comm -13 <(lista "$EQ/rami-valida.list") <(casi | awk -F'\t' '$1 == "jsonl" { print $5 }' | tr ',' '\n' | LC_ALL=C sort -u))
check "  e ogni etichetta dei jsonl di casi.tsv e' in rami-valida.list" '[ -z "$fuori_v" ]' "$fuori_v"
campi=$(casi | awk -F'\t' 'NF != 6 || $1 !~ /^(spec|jsonl)$/' | head -3)
check "casi.tsv: 6 campi per riga, tipo spec o jsonl" '[ -z "$campi" ]' "$campi"
# the built corpus against casi.tsv: the specs (with their run dir) and the counted jsonl (equiv: log/<n>-<label>.jsonl, no
# dot in the label, not chiusura)
for d in "$T/c1"/*/; do
  m=$(basename "$d")
  (cd "$d/.claude/.ai-workflow" && ls | sed -n 's/^\(spec-.*\)\.md$/\1/p' | while IFS= read -r s; do [ -d "$s.run" ] && printf 'spec\t%s\t%s\n' "$m" "$s"; done
   find . -path './spec-*.run/log/*' -type f -name '*.jsonl' | sed 's|^\./||' | grep -E '/log/[0-9]+-[^./]*\.jsonl$' | grep -v chiusura |
     sed "s|^|jsonl\t$m\t|")
done | LC_ALL=C sort > "$T/costruiti"
casi | cut -f1-3 | LC_ALL=C sort > "$T/dichiarati"
d=$(diff "$T/dichiarati" "$T/costruiti")
check "ogni spec e ogni jsonl del corpus costruito e' in casi.tsv, e viceversa" '[ -z "$d" ]' "$d"
vuoti=$(awk -F'\t' '$1 == "jsonl" { print $2 "/.claude/.ai-workflow/" $3 }' "$T/costruiti" | while IFS= read -r f; do [ -s "$T/c1/$f" ] || echo "$f"; done)
check "nessun jsonl contato e' vuoto" '[ -z "$vuoti" ]' "$vuoti"

# --- 3. placeholders outside the list ---
Q=$T/copia/esempi-equiv; mkdir -p "$T/copia"; cp -r "$EQ" "$Q"
MQ=$Q/progetto-impronta-nc/modelli/.ai-workflow/spec-esempio-harness-not-computable.md
cp "$MQ" "$T/modello"
printf '%s\n' 'Note: {{sconosciuto}}' >> "$MQ"
MAAT_ESEMPI_PLUGIN=$ROOT/plugins/maat bash "$Q/costruisci.sh" "$T/q1" progetto-impronta-nc > "$T/q1.out" 2>&1; rc=$?
check "un modello con un segnaposto fuori elenco → exit 2" '[ $rc -eq 2 ] && grep -q "placeholder outside the list: {{sconosciuto}}" "$T/q1.out"' "rc=$rc $(cat "$T/q1.out")"
cp "$T/modello" "$MQ"; printf '%s\n' 'Reviewed snapshot: {{snapshot:7}}' >> "$MQ"
MAAT_ESEMPI_PLUGIN=$ROOT/plugins/maat bash "$Q/costruisci.sh" "$T/q2" progetto-impronta-nc > "$T/q2.out" 2>&1; rc=$?
check "  un segnaposto che nomina uno stato inesistente → exit 2" '[ $rc -eq 2 ] && grep -q "stati/7" "$T/q2.out"' "rc=$rc $(cat "$T/q2.out")"
cp "$T/modello" "$MQ"
MAAT_ESEMPI_PLUGIN=$ROOT/plugins/maat bash "$Q/costruisci.sh" "$T/q3" progetto-impronta-nc > "$T/q3.out" 2>&1; rc=$?
check "  copia ripristinata → exit 0" '[ $rc -eq 0 ]' "$(cat "$T/q3.out")"
bash "$Q/costruisci.sh" "$T/q4" progetto-nessuno > /dev/null 2>&1; rc=$?
check "  un mini-repo sconosciuto → exit 2" '[ $rc -eq 2 ]'

# --- counterproof: no fixed dates → two fingerprints ---
grep -v '# DATE-FISSE$' "$B" > "$Q/costruisci.sh"
check "controprova: la mutazione e' applicata (niente date fisse del commit)" '! grep -q "GIT_COMMITTER_DATE=" "$Q/costruisci.sh" && grep -q "GIT_COMMITTER_DATE=" "$B"'
CP=progetto-catena-codice-cambiato   # its chiusura.txt and snapshot carry the sha of the base commit
MAAT_ESEMPI_PLUGIN=$ROOT/plugins/maat bash "$Q/costruisci.sh" "$T/k1" $CP > "$T/k1.out" 2>&1
s=$(date +%s); nuovo_secondo "$s"
MAAT_ESEMPI_PLUGIN=$ROOT/plugins/maat bash "$Q/costruisci.sh" "$T/k2" $CP > "$T/k2.out" 2>&1
K1=$(impronta "$T/k1.out"); K2=$(impronta "$T/k2.out")
check "controprova: senza date fisse due costruzioni danno impronte diverse (il caso del determinismo sarebbe rosso)" \
  '[[ $K1 =~ ^[0-9a-f]{64}$ ]] && [[ $K2 =~ ^[0-9a-f]{64}$ ]] && [ "$K1" != "$K2" ]' "$K1 / $K2"

echo "esempi-equiv.test.sh: $pass passati, $fail falliti"
[ $fail -eq 0 ]
