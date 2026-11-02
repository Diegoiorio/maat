#!/usr/bin/env bash
# esempi-equiv.test.sh — the public equivalence corpus, tools/esempi-equiv/ (Maat 1.5.0). A test of the repo only.
#   bash tools/esempi-equiv.test.sh          (Git Bash or Linux)
#   MAAT_PY_JSONSCHEMA=<python with jsonschema>   the second validator (D14; the CI sets it, venv of its own)
#   MAAT_PY_MINIMO=<python without jsonschema>    the first one, when the interpreter of python.sh imports jsonschema
#   MAAT_CERT_RICHIESTO=1                         the strict check of the certificate (CI: main, tags, PRs to main)
#   MAAT_ESEMPI_DETERMINISMO=completo|ridotto     the second build of case 1 (default: completo on Linux, ridotto
#                                                 elsewhere: on Windows a whole build costs ~15 min, on Linux ~30 s)
# Block A of the 1.5.0 plan (the builder):
#   1. the corpus built twice, in two folders and at two different seconds of the clock → the same fingerprint
#      (driver.py equiv --impronta, printed by the builder), exit 0, no placeholder left. «completo»: the whole corpus
#      twice; «ridotto»: the whole corpus once, then one mini-repo (the one whose files carry the sha of the base
#      commit) again, against the fingerprint of the same mini-repo in the first build;
#   2. the manifests: every row of righe.list and every branch of rami-valida.list has a case in casi.tsv, every spec
#      and every jsonl of the built corpus is in casi.tsv and vice versa, no counted jsonl is empty;
#      2b. every branch of rami-valida.list with an expectation (out, result, in) is gone through by at least one of its
#      jsonl, by `run-phase.sh --valida` on the built corpus; every fase-<f> label of a jsonl is its phase (_phase_of);
#      2c. the copy of snap_fp in the builder gives the same result as the one of cycle-state.sh;
#   3. a model with a placeholder outside the list, or naming a state that does not exist → exit 2.
# Block D (the proof on the corpus; one build, the first one, shared by every case below):
#   4. `driver.py equiv` on the built corpus with each validator available (D14: the interpreter of python.sh, by what
#      it imports, or MAAT_PY_MINIMO → «minimo»; MAAT_PY_JSONSCHEMA → «jsonschema»; a missing one: «SALTATO: <v>»):
#      every spec UGUALE, «diverse=0 · diversi=0» in it and in en, the counts = casi.tsv, the first word of Next of
#      every spec = casi.tsv in both languages;
#   5. with MAAT_CERT_RICHIESTO=1: plugins/maat/scripts/driver.equiv VALIDO, the fingerprint of its corpus line = that
#      of the corpus built, its «spec=<n> jsonl=<m>» = the counts of casi.tsv, «validatori minimo,jsonschema», and no
#      validator SALTATO.
# Counterproofs: (A) a copy of the builder without the fixed dates (the DATE-FISSE line) → two builds of a mini-repo
# whose files carry the sha of the base commit give two fingerprints (the determinism case would be red);
# (a) a copy of driver.py whose Python twin of IMPLEMENT points to another key → DIVERSO on the IMPLEMENT specs;
# (b) DIFENSIVA = ("difensiva: ",) → DIVERSO on a jsonl (valida) and on a spec (next) of the «defensive:» branch;
# (c) the case of row C2-chiusura-assente removed from a copy of casi.tsv → «row without a case», red;
# (d) a counted jsonl of the built corpus emptied → «empty jsonl», red;
# (e) a certificate VALIDO for the hashes but with another fingerprint → the strict check is red; (e') the same with the
# fingerprint of the corpus but the counts of one spec → red;
# (f) in a copy of rami-valida.list, v-badjson with the expected output of v-nojson → only v-badjson red.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1   # no __pycache__ in the plugin (driver.py imports maat_msg, maat_paths)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
EQ=$ROOT/tools/esempi-equiv
B=$EQ/costruisci.sh
DRV=$ROOT/plugins/maat/scripts/driver.py
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
FIC_PY=""; . "$ROOT/plugins/maat/scripts/python.sh" >/dev/null 2>&1
[ -n "$FIC_PY" ] || { echo "esempi-equiv.test.sh: no Python (python.sh)"; exit 2; }
CP=progetto-catena-codice-cambiato   # its chiusura.txt and snapshot carry the sha of the base commit
DET=${MAAT_ESEMPI_DETERMINISMO:-}
[ -n "$DET" ] || { DET=ridotto; [ "$(uname -s)" = Linux ] && DET=completo; }
case $DET in completo|ridotto) ;; *) echo "MAAT_ESEMPI_DETERMINISMO: completo or ridotto"; exit 2 ;; esac

# --- 1. determinism ---
t0=$(date +%s)
bash "$B" "$T/c1" > "$T/c1.out" 2>&1; rc1=$?
t1=$(date +%s); nuovo_secondo "$t1"
if [ $DET = completo ]; then
  bash "$B" "$T/c2" > "$T/c2.out" 2>&1; rc2=$?
  echo "esempi-equiv: costruzione $(( ($(date +%s) - t0) / 2 ))s (media di due)"
else
  bash "$B" "$T/c2" $CP > "$T/c2.out" 2>&1; rc2=$?
  echo "esempi-equiv: costruzione $((t1 - t0))s; determinismo ridotto a $CP ($(( $(date +%s) - t1 ))s)"
fi
check "il corpus si costruisce (exit 0, due volte)" '[ $rc1 -eq 0 ] && [ $rc2 -eq 0 ]' "$(tail -5 "$T/c1.out"; tail -5 "$T/c2.out")"
I1=$(impronta "$T/c1.out"); I2=$(impronta "$T/c2.out")
if [ $DET = completo ]; then
  check "due costruzioni, in cartelle e secondi diversi → la stessa impronta" '[[ $I1 =~ ^[0-9a-f]{64}$ ]] && [ "$I1" = "$I2" ]' "$I1 / $I2"
else
  I1R=$("$FIC_PY" "$DRV" equiv --impronta "$T/c1/$CP/.claude/.ai-workflow" 2>/dev/null | tr -d '\r')
  check "due costruzioni, in cartelle e secondi diversi → la stessa impronta (ridotto: $CP)" '[[ $I1 =~ ^[0-9a-f]{64}$ ]] && [[ $I1R =~ ^[0-9a-f]{64}$ ]] && [ "$I1R" = "$I2" ]' "$I1R / $I2"
fi
check "  nessun segnaposto rimasto nel corpus costruito" '[ -z "$(grep -rlF "{{" "$T/c1"/*/.claude 2>/dev/null)" ]'
grep '^esempi-equiv: ' "$T/c1.out" | tail -1

# --- 2. manifests ---
casi() { tr -d '\r' < "${CASI:-$EQ/casi.tsv}" | grep -v '^#' | grep .; }
lista() { tr -d '\r' < "$1" | grep -v '^#' | grep . | cut -f1 | LC_ALL=C sort -u; }
righe_senza_caso() { comm -23 <(lista "$EQ/righe.list") <(casi | awk -F'\t' '$1 == "spec" { print $5 }' | LC_ALL=C sort -u); }
manca_r=$(righe_senza_caso)
check "ogni riga di righe.list ha almeno un caso" '[ -z "$manca_r" ]' "$manca_r"
fuori_r=$(comm -13 <(lista "$EQ/righe.list") <(casi | awk -F'\t' '$1 == "spec" { print $5 }' | LC_ALL=C sort -u))
check "  e ogni spec di casi.tsv ha un'etichetta di righe.list" '[ -z "$fuori_r" ]' "$fuori_r"
manca_v=$(comm -23 <(lista "$EQ/rami-valida.list") <(casi | awk -F'\t' '$1 == "jsonl" { print $5 }' | tr ',' '\n' | LC_ALL=C sort -u))
check "ogni ramo di rami-valida.list ha almeno un jsonl" '[ -z "$manca_v" ]' "$manca_v"
fuori_v=$(comm -13 <(lista "$EQ/rami-valida.list") <(casi | awk -F'\t' '$1 == "jsonl" { print $5 }' | tr ',' '\n' | LC_ALL=C sort -u))
check "  e ogni etichetta dei jsonl di casi.tsv e' in rami-valida.list" '[ -z "$fuori_v" ]' "$fuori_v"
campi=$(casi | awk -F'\t' 'NF != 6 || $1 !~ /^(spec|jsonl)$/' | head -3)
check "casi.tsv: 6 campi per riga, tipo spec o jsonl" '[ -z "$campi" ]' "$campi"
# rami-valida.list: 5 fields, none empty (IFS=$'\t' read in rami_non_provati merges consecutive tabs)
campi_v=$(tr -d '\r' < "$EQ/rami-valida.list" | grep -v '^#' | grep . | awk -F'\t' '{ v = 0; for (i = 1; i <= NF; i++) if ($i == "") v = 1 } NF != 5 || v' | head -3)
check "rami-valida.list: 5 campi per riga, nessuno vuoto" '[ -z "$campi_v" ]' "$campi_v"
# the built corpus against casi.tsv: the specs (with their run dir) and the counted jsonl (equiv: log/<n>-<label>.jsonl, no
# dot in the label, and not of the phase chiusura: _phase_of of driver.py, «chiusura» anywhere in the file name only)
for d in "$T/c1"/*/; do
  m=$(basename "$d")
  (cd "$d/.claude/.ai-workflow" && ls | sed -n 's/^\(spec-.*\)\.md$/\1/p' | while IFS= read -r s; do [ -d "$s.run" ] && printf 'spec\t%s\t%s\n' "$m" "$s"; done
   find . -path './spec-*.run/log/*' -type f -name '*.jsonl' | sed 's|^\./||' | grep -E '/log/[0-9]+-[^./]*\.jsonl$' |
     grep -vE '/log/[0-9]+-[^./]*chiusura[^./]*\.jsonl$' |
     sed "s|^|jsonl\t$m\t|")
done | LC_ALL=C sort > "$T/costruiti"
casi | cut -f1-3 | LC_ALL=C sort > "$T/dichiarati"
d=$(diff "$T/dichiarati" "$T/costruiti")
check "ogni spec e ogni jsonl del corpus costruito e' in casi.tsv, e viceversa" '[ -z "$d" ]' "$d"
jsonl_vuoti() { awk -F'\t' '$1 == "jsonl" { print $2 "/.claude/.ai-workflow/" $3 }' "$T/costruiti" | while IFS= read -r f; do [ -s "$T/c1/$f" ] || echo "$f"; done; }
vuoti=$(jsonl_vuoti)
check "nessun jsonl contato e' vuoto" '[ -z "$vuoti" ]' "$vuoti"
# counterproof (c): the case of row C2-chiusura-assente removed from a copy of casi.tsv → that row has no case
tr -d '\r' < "$EQ/casi.tsv" | awk -F'\t' '!($1 == "spec" && $5 == "C2-chiusura-assente")' > "$T/casi-senza-c2"
manca_c=$(CASI=$T/casi-senza-c2 righe_senza_caso)
check "controprova (c): tolto il caso C2-chiusura-assente da una copia di casi.tsv → «riga senza caso» rosso" \
  '! cmp -s "$EQ/casi.tsv" "$T/casi-senza-c2" && [ "$manca_c" = C2-chiusura-assente ]' "$manca_c"
# counterproof (d): a counted jsonl emptied (then put back) → the empty-jsonl case is red
J1=$(awk -F'\t' '$1 == "jsonl" { print $2 "/.claude/.ai-workflow/" $3; exit }' "$T/costruiti")
cp -p "$T/c1/$J1" "$T/jsonl-salvato"; : > "$T/c1/$J1"
vuoti_d=$(jsonl_vuoti)
cp -p "$T/jsonl-salvato" "$T/c1/$J1"
check "controprova (d): un jsonl contato svuotato → «jsonl vuoto» rosso" '[ "$vuoti_d" = "$J1" ] && [ -s "$T/c1/$J1" ]' "$vuoti_d"

# --- 2b. the labels of the jsonl: each branch of rami-valida.list is really gone through by at least one of its jsonl ---
SCR=$ROOT/plugins/maat/scripts
nat() { cygpath -m "$1" 2>/dev/null || printf '%s\n' "$1"; }   # a path for the native Python (Windows)
SCHEMA=$(nat "$ROOT/plugins/maat/schemas/phase-result.schema.json")
casi | awk -F'\t' '$1 == "jsonl" { print $2 "/.claude/.ai-workflow/" $3 "\t" $5 }' > "$T/jsonl-rami"
# the phase of each jsonl: _phase_of of driver.py on its label, as equiv passes it to --valida
sed -E 's|^.*/log/([0-9]+-[^/]*)\.jsonl\t.*$|\1|' "$T/jsonl-rami" |
  "$FIC_PY" -B -c 'import sys; sys.path.insert(0, sys.argv[1]); from driver import _phase_of; [print(_phase_of(l.strip())) for l in sys.stdin]' \
  "$(nat "$SCR")" | tr -d '\r' > "$T/jsonl-fasi"
mkdir -p "$T/valida"; : > "$T/valida/indice"; k=0
while IFS=$'\t' read -r f et ph; do
  k=$((k + 1)); rm -f "$T/valida/r.json"
  o=$(cd "$T" && MAAT_LINGUA=it bash "$SCR/run-phase.sh" --valida "$(nat "$T/c1/$f")" "$SCHEMA" "$ph" "$(nat "$T/valida/r.json")" 2>/dev/null); rc=$?
  printf '%s' "$o" | tr -d '\r' | awk 'NR > 1 { printf " ## " } { printf "%s", $0 } END { print "" }' > "$T/valida/$k.out"
  [ -f "$T/valida/r.json" ] && tr -d '\r' < "$T/valida/r.json" > "$T/valida/$k.res"
  printf '%s\t%s\t%s\t%s\t%s\n' "$k" "$et" "$f" "$ph" "$rc" >> "$T/valida/indice"
done < <(paste "$T/jsonl-rami" "$T/jsonl-fasi")
rami_non_provati() { # $1 a rami-valida.list → the labels with a condition (out, result, in) that none of their jsonl meets
  local et cosa eo er ei k lab f ph rc ok
  while IFS=$'\t' read -r et cosa eo er ei; do
    [ "$eo$er$ei" = "---" ] && continue
    ok=0
    while IFS=$'\t' read -r k lab f ph rc; do
      case ",$lab," in *",$et,"*) ;; *) continue ;; esac
      [ "$rc" = 0 ] || continue
      [ "$eo" = - ] || grep -qE -- "$eo" "$T/valida/$k.out" || continue
      case $er in -) ;; no) [ ! -f "$T/valida/$k.res" ] || continue ;; *) [ -f "$T/valida/$k.res" ] && grep -qE -- "$er" "$T/valida/$k.res" || continue ;; esac
      [ "$ei" = - ] || grep -qE -- "$ei" "$T/c1/$f" || continue
      ok=1; break
    done < "$T/valida/indice"
    [ $ok = 1 ] || echo "$et"
  done < <(tr -d '\r' < "$1" | grep -v '^#' | grep .)
}
np=$(rami_non_provati "$EQ/rami-valida.list")
nr=$(tr -d '\r' < "$EQ/rami-valida.list" | grep -v '^#' | awk -F'\t' 'NF == 5 && $3 $4 $5 != "---"' | grep -c .)
check "ogni ramo di rami-valida.list con un'attesa ($nr) e' percorso da almeno un suo jsonl (run-phase.sh --valida)" '[ -z "$np" ] && [ "$nr" -gt 0 ]' "$np
    (uscite: $(head -c 600 "$T/valida/1.out"))"
fasi_ko=$(while IFS=$'\t' read -r k lab f ph rc; do
  for e in $(printf '%s\n' "$lab" | tr ',' '\n' | sed -n 's/^fase-//p'); do [ "$e" = "$ph" ] || echo "$f: fase-$e, _phase_of $ph"; done
done < "$T/valida/indice")
check "  ogni etichetta fase-<f> di un jsonl e' la sua fase (_phase_of di driver.py)" '[ -z "$fasi_ko" ] && [ -s "$T/valida/indice" ]' "$fasi_ko"
# counterproof (f): in a copy of rami-valida.list the branch v-badjson expects the output of v-nojson → v-badjson red
tr -d '\r' < "$EQ/rami-valida.list" | awk -F'\t' -v OFS='\t' '$1 == "v-nojson" { e = $3 } $1 == "v-badjson" { $3 = e } { print }' > "$T/rami-scambiati"
np_f=$(rami_non_provati "$T/rami-scambiati")
check "controprova (f): v-badjson con l'attesa di v-nojson in una copia di rami-valida.list → solo v-badjson rosso" \
  '! cmp -s <(tr -d "\r" < "$EQ/rami-valida.list") "$T/rami-scambiati" && [ "$np_f" = v-badjson ]' "$np_f"

# --- 2c. snap_fp: the copy in the builder ({{finalize}}) gives the same result as the formula of cycle-state.sh ---
sfp() { # $1 file whose «snap_fp() » line is evaluated, $2 value → its snap_fp
  ( eval "$(tr -d '\r' < "$1" | grep -m1 '^snap_fp() ')" && snap_fp "$2" )
}
SFP_IN=("base 0123456789ab · tree 0123456789ab · fingerprint 0123456789ab · 2 paths"
        "  base 0123456789ab  ·	tree 0123456789ab ·  fingerprint 0123456789ab · 2 paths	 " "")
sfp_ko=""
for v in "${SFP_IN[@]}"; do
  a=$(sfp "$B" "$v"); c=$(sfp "$SCR/cycle-state.sh" "$v")
  [[ $a =~ ^[0-9a-f]{12}$ ]] && [ "$a" = "$c" ] || sfp_ko+=" «$v»: costruttore $a, cycle-state.sh $c;"
done
check "snap_fp del costruttore = snap_fp di cycle-state.sh (${#SFP_IN[@]} valori, spazi e tab compressi)" '[ -z "$sfp_ko" ]' "$sfp_ko"
# the inputs discriminate: the first two differ only in spaces and tabs, so a formula that did not squeeze them would differ
check "  i valori distinguono: i primi due danno la stessa impronta, una formula senza la compressione degli spazi no" \
  '[ "$(sfp "$B" "${SFP_IN[0]}")" = "$(sfp "$B" "${SFP_IN[1]}")" ] && [ "$(printf "%s" "${SFP_IN[0]}" | sha256sum | cut -c1-12)" != "$(printf "%s" "${SFP_IN[1]}" | sha256sum | cut -c1-12)" ]'

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

# --- counterproof (A): no fixed dates → two fingerprints ---
grep -v '# DATE-FISSE$' "$B" > "$Q/costruisci.sh"
check "controprova: la mutazione e' applicata (niente date fisse del commit)" '! grep -q "GIT_COMMITTER_DATE=" "$Q/costruisci.sh" && grep -q "GIT_COMMITTER_DATE=" "$B"'
MAAT_ESEMPI_PLUGIN=$ROOT/plugins/maat bash "$Q/costruisci.sh" "$T/k1" $CP > "$T/k1.out" 2>&1
s=$(date +%s); nuovo_secondo "$s"
MAAT_ESEMPI_PLUGIN=$ROOT/plugins/maat bash "$Q/costruisci.sh" "$T/k2" $CP > "$T/k2.out" 2>&1
K1=$(impronta "$T/k1.out"); K2=$(impronta "$T/k2.out")
check "controprova: senza date fisse due costruzioni danno impronte diverse (il caso del determinismo sarebbe rosso)" \
  '[[ $K1 =~ ^[0-9a-f]{64}$ ]] && [[ $K2 =~ ^[0-9a-f]{64}$ ]] && [ "$K1" != "$K2" ]' "$K1 / $K2"
rm -rf "$T/c2" "$T/k1" "$T/k2" "$T/q1" "$T/q2" "$T/q3" "$T/copia"

# --- 4. equiv on the corpus, with each validator available (D14) ---
# the targets in the fixed order of the builder (its «esempi-equiv: <mini-repo> · spec=» lines)
TARGETS=(); while IFS= read -r m; do TARGETS+=("$T/c1/$m/.claude/.ai-workflow"); done < <(sed -n 's/^esempi-equiv: \(progetto-[^ ]*\) · spec=.*/\1/p' "$T/c1.out")
NS=$(casi | awk -F'\t' '$1 == "spec"' | grep -c .); NJ=$(casi | awk -F'\t' '$1 == "jsonl"' | grep -c .)
casi | awk -F'\t' '$1 == "spec" { print $3 " " $4 }' | LC_ALL=C sort > "$T/parole-attese"
validatore() { "$1" -c "import jsonschema" >/dev/null 2>&1 && echo jsonschema || echo minimo; }
blocco() { tr -d '\r' < "$1" | sed -n "/^equiv: lingua $2\$/,/^equiv: lingua [a-z]*\$/p" | sed '/^equiv: lingua /d'; }
declare -A PYV=()
PYV[$(validatore "$FIC_PY")]=$FIC_PY
if [ -n "${MAAT_PY_MINIMO:-}" ]; then
  check "MAAT_PY_MINIMO non importa jsonschema" '[ "$(validatore "$MAAT_PY_MINIMO")" = minimo ]' "$MAAT_PY_MINIMO"
  [ "$(validatore "$MAAT_PY_MINIMO")" = minimo ] && PYV[minimo]=$MAAT_PY_MINIMO
fi
if [ -n "${MAAT_PY_JSONSCHEMA:-}" ]; then
  check "MAAT_PY_JSONSCHEMA importa jsonschema" '[ "$(validatore "$MAAT_PY_JSONSCHEMA")" = jsonschema ]' "$MAAT_PY_JSONSCHEMA"
  [ "$(validatore "$MAAT_PY_JSONSCHEMA")" = jsonschema ] && PYV[jsonschema]=$MAAT_PY_JSONSCHEMA
fi
saltati=""
for v in minimo jsonschema; do
  py=${PYV[$v]:-}
  if [ -z "$py" ]; then echo "SALTATO: $v (nessun interprete con il validatore $v)"; saltati+=" $v"; continue; fi
  t0=$(date +%s)
  FIC_PY=$py "$py" "$DRV" equiv "${TARGETS[@]}" > "$T/eq-$v.out" 2>&1; rc=$?
  echo "esempi-equiv: equiv $v $(( $(date +%s) - t0 ))s · $(grep '^equiv: spec=' "$T/eq-$v.out" | tr -d '\r' | tr '\n' ' ')"
  check "equiv ($v): exit 0 e nessun DIVERSO" '[ $rc -eq 0 ] && ! grep -q "^DIVERSO" "$T/eq-$v.out"' "$(grep -A8 "^DIVERSO" "$T/eq-$v.out" | head -40)"
  for l in it en; do
    blocco "$T/eq-$v.out" $l > "$T/eq-$v-$l"
    check "  ($v, $l) «equiv: spec=$NS diverse=0 · jsonl=$NJ diversi=0» e $NS righe UGUALE" \
      'grep -qx "equiv: spec=$NS diverse=0 · jsonl=$NJ diversi=0" "$T/eq-$v-$l" && [ "$(grep -c "^UGUALE " "$T/eq-$v-$l")" = "$NS" ]' \
      "$(grep "^equiv: spec=" "$T/eq-$v-$l")"
    sed -n 's/^UGUALE \(spec-[^ ]*\) · Next: \([^ ]*\).*/\1 \2/p' "$T/eq-$v-$l" | LC_ALL=C sort > "$T/parole-$v-$l"
    dp=$(diff "$T/parole-attese" "$T/parole-$v-$l")
    check "  ($v, $l) la prima parola di Next di ogni spec = casi.tsv" '[ -z "$dp" ]' "$dp"
  done
done

# --- counterproofs (a), (b): copies of driver.py (with the modules next to it: they read their own catalog) ---
mutato() { # $1 name, $2 sed expression → $T/<name>/driver.py
  mkdir -p "$T/$1/lib"; cp "$ROOT/plugins/maat/scripts/"{maat_paths.py,maat_msg.py} "$T/$1/"
  cp "$ROOT/plugins/maat/scripts/lib/"{messages.tsv,maat-msg.sh} "$T/$1/lib/"
  sed "$2" "$DRV" > "$T/$1/driver.py"
}
spec_di() { # $1 awk condition on casi.tsv → the spec files of the built corpus
  casi | awk -F'\t' "\$1 == \"spec\" && ($1) { print \$2 \"/.claude/.ai-workflow/\" \$3 \".md\" }" | sed "s|^|$T/c1/|"
}
mutato drv-a 's/"IMPLEMENT — " + T("cycle-state.impl")/"IMPLEMENT — " + T("cycle-state.plan_draft")/'
check "controprova (a): la mutazione e' applicata (il gemello Python di IMPLEMENT punta a un'altra chiave)" 'grep -qF "\"IMPLEMENT — \" + T(\"cycle-state.plan_draft\")" "$T/drv-a/driver.py"'
mapfile -t SA < <(spec_di '$4 == "IMPLEMENT"')
FIC_DRIVER_ROOT=$ROOT/plugins/maat "$FIC_PY" "$T/drv-a/driver.py" equiv "${SA[@]}" > "$T/eq-a.out" 2>&1; rc=$?
fuori_a=$(sed -n 's/^DIVERSO \(spec-[^ ]*\)$/\1/p' "$T/eq-a.out" | while IFS= read -r s; do grep -qx "$s IMPLEMENT" "$T/parole-attese" || echo "$s"; done)
check "controprova (a): DIVERSO sulle spec IMPLEMENT (${#SA[@]}), exit 1" '[ $rc -eq 1 ] && grep -q "^DIVERSO spec-" "$T/eq-a.out" && [ -z "$fuori_a" ]' "rc=$rc $(grep "^equiv: spec=" "$T/eq-a.out")"
mutato drv-b 's/^DIFENSIVA = ("difensiva: ", "defensive: ")$/DIFENSIVA = ("difensiva: ",)/'
check "controprova (b): la mutazione e' applicata (DIFENSIVA senza «defensive: »)" 'grep -qx "DIFENSIVA = (\"difensiva: \",)" "$T/drv-b/driver.py"'
# the specs of the run dirs with a jsonl of the «defensive» branch
mapfile -t SB < <(casi | awk -F'\t' '$1 == "jsonl" && ("," $5 ",") ~ /,defensive,/ { sub(/\.run\/.*/, "", $3); print $2 "\t" $3 }' | LC_ALL=C sort -u |
  while IFS=$'\t' read -r m s; do echo "$T/c1/$m/.claude/.ai-workflow/$s.md"; done)
FIC_DRIVER_ROOT=$ROOT/plugins/maat "$FIC_PY" "$T/drv-b/driver.py" equiv "${SB[@]}" > "$T/eq-b.out" 2>&1; rc=$?
check "controprova (b): DIVERSO su almeno un jsonl (valida) e su almeno una spec (next) del ramo defensive (${#SB[@]} spec)" \
  '[ $rc -eq 1 ] && grep -q "^DIVERSO valida " "$T/eq-b.out" && grep -q "^DIVERSO spec-" "$T/eq-b.out"' "rc=$rc $(grep "^DIVERSO\|^equiv: spec=" "$T/eq-b.out")"

# --- 5. the certificate: strict check with MAAT_CERT_RICHIESTO=1 ---
cert_ok() { # $1 certificate, $2 fingerprint of the corpus (64) → 0, or the reason on stdout
  local o c
  o=$(FIC_DRIVER_CERT="$1" "$FIC_PY" "$DRV" certificato 2>&1 | tr -d '\r')
  case $o in "certificato: VALIDO"*) ;; *) echo "$o"; return 1 ;; esac
  c=$(tr -d '\r' < "$1" | grep '^corpus ')
  [[ $c == *" · impronta ${2:0:12} · "* ]] || { echo "impronta diversa da ${2:0:12}: $c"; return 1; }
  [[ $c == "corpus spec=$NS jsonl=$NJ · "* ]] || { echo "conteggi diversi da casi.tsv (spec=$NS jsonl=$NJ): $c"; return 1; }
  [[ $c == *" · validatori minimo,jsonschema" ]] || { echo "validatori non minimo,jsonschema: $c"; return 1; }
}
# counterproof (e): a certificate with the hashes of today but the fingerprint of one mini-repo only (equiv --certifica
# on one closed spec) → red; with the fingerprint of the corpus put in but its counts (spec=1) → still red; with the
# fingerprint and the counts of the corpus put in → green (the check is not always red)
SE=$(spec_di '$4 == "DONE"' | head -1)
altro=jsonschema; [ "$(validatore "$FIC_PY")" = jsonschema ] && altro=minimo
FIC_DRIVER_CERT="$T/cert-e" "$FIC_PY" "$DRV" equiv --certifica --validatori-precedenti $altro "$SE" > "$T/eq-e.out" 2>&1
sed "s/ · impronta [0-9a-f]\{12\} · / · impronta ${I1:0:12} · /" "$T/cert-e" > "$T/cert-e-ridotto"
sed "s/^corpus spec=[0-9]* jsonl=[0-9]* · /corpus spec=$NS jsonl=$NJ · /" "$T/cert-e-ridotto" > "$T/cert-e-giusto"
mot_e=$(cert_ok "$T/cert-e" "$I1"); mot_r=$(cert_ok "$T/cert-e-ridotto" "$I1"); ok_e=$(cert_ok "$T/cert-e-giusto" "$I1")
check "controprova (e): certificato VALIDO ma con un'altra impronta → controllo rigido rosso (e con l'impronta del corpus verde)" \
  '[ -f "$T/cert-e" ] && ! grep -q " · impronta ${I1:0:12} · " "$T/cert-e" && [[ $mot_e == "impronta diversa"* ]] && cert_ok "$T/cert-e-giusto" "$I1" >/dev/null' "$mot_e · $ok_e"
check "controprova (e'): l'impronta del corpus ma i conteggi di una spec sola (spec=1) → controllo rigido rosso" \
  '! grep -q "^corpus spec=$NS jsonl=$NJ · " "$T/cert-e-ridotto" && [[ $mot_r == "conteggi diversi"* ]]' "$mot_r"
if [ "${MAAT_CERT_RICHIESTO:-0}" = 1 ]; then
  mot=$(cert_ok "$ROOT/plugins/maat/scripts/driver.equiv" "$I1")
  check "MAAT_CERT_RICHIESTO=1: driver.equiv VALIDO, impronta = corpus costruito (${I1:0:12}), validatori minimo,jsonschema" '[ -z "$mot" ]' "$mot
    rimedio: bash tools/certifica.sh --scrivi (da Linux), poi committare plugins/maat/scripts/driver.equiv"
  check "  MAAT_CERT_RICHIESTO=1: nessun validatore SALTATO" '[ -z "$saltati" ]' "SALTATO:$saltati"
else
  echo "esempi-equiv: controllo rigido del certificato non richiesto (MAAT_CERT_RICHIESTO=1 per attivarlo) · $(FIC_DRIVER_CERT= "$FIC_PY" "$DRV" certificato 2>&1 | tr -d '\r' | head -1 | cut -c1-120)"
fi

echo "esempi-equiv.test.sh: $pass passati, $fail falliti"
[ $fail -eq 0 ]
