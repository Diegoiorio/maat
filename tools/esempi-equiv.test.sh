#!/usr/bin/env bash
# esempi-equiv.test.sh — the public corpus, tools/esempi-equiv/ (Maat 1.5.0; 1.6.0: the expected outputs in place
# of the equivalence certificate). A test of the repo only.
#   bash tools/esempi-equiv.test.sh          (Git Bash or Linux)
#   MAAT_PY_JSONSCHEMA=<python with jsonschema>   the second validator (D14; the CI sets it, venv of its own)
#   MAAT_PY_MINIMO=<python without jsonschema>    the first one, when the interpreter of python.sh imports jsonschema
#   MAAT_ATTESE_RICHIESTE=1                       the strict checks of §5 (the CI, at every push)
#   MAAT_ESEMPI_DETERMINISMO=completo|ridotto     the second build of case 1 (default: completo on Linux, ridotto
#                                                 elsewhere: on Windows a whole build costs ~15 min, on Linux ~30 s)
# Block A of the 1.5.0 plan (the builder):
#   1. the corpus built twice, in two folders and at two different seconds of the clock → the same fingerprint
#      (driver.py impronta, printed by the builder), exit 0, no placeholder left. «completo»: the whole corpus
#      twice; «ridotto»: the whole corpus once, then one mini-repo (the one whose files carry the sha of the base
#      commit) again, against the fingerprint of the same mini-repo in the first build;
#   2. the manifests: every row of righe.list and every branch of rami-valida.list has a case in casi.tsv, every spec
#      and every jsonl of the built corpus is in casi.tsv and vice versa, no counted jsonl is empty;
#      2b. every branch of rami-valida.list with an expectation (out, result, in) is gone through by at least one of its
#      jsonl, by `driver.py valida` on the built corpus; every fase-<f> label of a jsonl is its phase (_phase_of);
#      2c. the copy of snap_fp in the builder gives the same result as _snap_fp of driver.py;
#   3. a model with a placeholder outside the list, or naming a state that does not exist → exit 2.
# The proof on the corpus (1.6.0, D2; one build, the first one, shared by every case below):
#   4. tools/esempi-equiv/attese.sh on the built corpus, with each validator available (the interpreter of python.sh,
#      by what it imports, or MAAT_PY_MINIMO → «minimo»; MAAT_PY_JSONSCHEMA or ~/maat-venv → «jsonschema»; a missing
#      one: «SALTATO: <v>»): exit 0, next-it and next-en UGUALE (one block per spec of casi.tsv), every valida file of
#      an available validator UGUALE (one block per jsonl), the first word of Next of every spec = casi.tsv in both
#      languages; attese/STORIA starts with the writing from the plugin of v1.5.1 (the anchor of the proof);
#   5. with MAAT_ATTESE_RICHIESTE=1: no validator SALTATO, and the files of attese/ changed since the base (merge-base
#      with origin/main) only with a new line in attese/STORIA (attese.sh --storia).
# Counterproofs: (A) a copy of the builder without the fixed dates (the DATE-FISSE line) → two builds of a mini-repo
# whose files carry the sha of the base commit give two fingerprints (the determinism case would be red);
# (a) a copy of the plugin whose driver.py has the Python twin of IMPLEMENT pointing to another key → attese.sh DIVERSO
# only on IMPLEMENT specs (progetto-storico, next, it);
# (b) DIFENSIVA = ("difensiva: ",) → DIVERSO on a jsonl (valida) and on a spec (next) of progetto-singoli (it);
# (c) the case of row C2-chiusura-assente removed from a copy of casi.tsv → «row without a case», red;
# (d) a counted jsonl of the built corpus emptied → «empty jsonl», red;
# (f) in a copy of rami-valida.list, v-badjson with the expected output of v-nojson → only v-badjson red;
# (g) a copy of attese/ with one line of next-it.txt changed → DIVERSO on that block only (the real attese/ on the same
# mini-repo: UGUALE);
# (h) the normalizations (attese.py normalizza, the forms of attese.sh --forme): every form of the closed list becomes
# its token, at the boundary of a path or of hex digits only (a longer name, a 13th digit: untouched), the longest
# first (<MAAT> under <REPO>), forms of equal length all replaced; one character of the reason changed in each line →
# a different line (a real difference stays red);
# (i) MAAT_PY_JSONSCHEMA pointing to a Python without jsonschema → attese.sh --validatori: «SALTATO: jsonschema», exit
# 1 with MAAT_ATTESE_RICHIESTE=1, exit 0 without;
# (j) on a fake repo: a file of attese/ changed and STORIA unchanged → attese.sh --storia red; one line appended →
# green; STORIA rewritten (not appended) → red.
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
  I1R=$("$FIC_PY" "$DRV" impronta "$T/c1/$CP/.claude/.ai-workflow" 2>/dev/null | tr -d '\r')
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
# the built corpus against casi.tsv: the specs (with their run dir) and the counted jsonl (attese.sh: log/<n>-<label>.jsonl, no
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
# the phase of each jsonl: _phase_of of driver.py on its label, as attese.sh passes it to valida
sed -E 's|^.*/log/([0-9]+-[^/]*)\.jsonl\t.*$|\1|' "$T/jsonl-rami" |
  "$FIC_PY" -B -c 'import sys; sys.path.insert(0, sys.argv[1]); from driver import _phase_of; [print(_phase_of(l.strip())) for l in sys.stdin]' \
  "$(nat "$SCR")" | tr -d '\r' > "$T/jsonl-fasi"
mkdir -p "$T/valida"; : > "$T/valida/indice"; k=0
while IFS=$'\t' read -r f et ph; do
  k=$((k + 1)); rm -f "$T/valida/r.json"
  o=$(cd "$T" && MAAT_LINGUA=it "$FIC_PY" "$(nat "$DRV")" valida "$(nat "$T/c1/$f")" "$SCHEMA" "$ph" "$(nat "$T/valida/r.json")" 2>/dev/null); rc=$?
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
check "ogni ramo di rami-valida.list con un'attesa ($nr) e' percorso da almeno un suo jsonl (driver.py valida)" '[ -z "$np" ] && [ "$nr" -gt 0 ]' "$np
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

# --- 2c. snap_fp: the copy in the builder ({{finalize}}) gives the same result as _snap_fp of driver.py ---
sfp() { # $1 file whose «snap_fp() » line is evaluated, $2 value → its snap_fp
  ( eval "$(tr -d '\r' < "$1" | grep -m1 '^snap_fp() ')" && snap_fp "$2" )
}
sfp_drv() { # $1 value → _snap_fp of driver.py
  "$FIC_PY" -B -c 'import sys; sys.path.insert(0, sys.argv[1]); from driver import _snap_fp; sys.stdout.write(_snap_fp(sys.argv[2]))' \
    "$(nat "$SCR")" "$1" 2>/dev/null | tr -d '\r'
}
SFP_IN=("base 0123456789ab · tree 0123456789ab · fingerprint 0123456789ab · 2 paths"
        "  base 0123456789ab  ·	tree 0123456789ab ·  fingerprint 0123456789ab · 2 paths	 " "")
sfp_ko=""
for v in "${SFP_IN[@]}"; do
  a=$(sfp "$B" "$v"); c=$(sfp_drv "$v")
  [[ $a =~ ^[0-9a-f]{12}$ ]] && [ "$a" = "$c" ] || sfp_ko+=" «$v»: costruttore $a, driver.py $c;"
done
check "snap_fp del costruttore = _snap_fp di driver.py (${#SFP_IN[@]} valori, spazi e tab compressi)" '[ -z "$sfp_ko" ]' "$sfp_ko"
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

# --- 4. the expected outputs: attese.sh on the corpus built (D2), with each validator available ---
AT=$EQ/attese.sh
NS=$(casi | awk -F'\t' '$1 == "spec"' | grep -c .); NJ=$(casi | awk -F'\t' '$1 == "jsonl"' | grep -c .)
validatore() { "$1" -c "import jsonschema" >/dev/null 2>&1 && echo jsonschema || echo minimo; }
[ -z "${MAAT_PY_MINIMO:-}" ] || check "MAAT_PY_MINIMO non importa jsonschema" '[ "$(validatore "$MAAT_PY_MINIMO")" = minimo ]' "$MAAT_PY_MINIMO"
[ -z "${MAAT_PY_JSONSCHEMA:-}" ] || check "MAAT_PY_JSONSCHEMA importa jsonschema" '[ "$(validatore "$MAAT_PY_JSONSCHEMA")" = jsonschema ]' "$MAAT_PY_JSONSCHEMA"
attese() { env -u MAAT_ATTESE_RICHIESTE -u MAAT_ATTESE_PLUGIN -u MAAT_ATTESE_VALIDA -u FIC_DRIVER bash "$AT" "$@"; }
t0=$(date +%s)
attese --corpus "$T/c1" --esiti "$T/att" > "$T/att.out" 2>&1; rc=$?
echo "esempi-equiv: attese $(( $(date +%s) - t0 ))s · $(grep '^attese: confronto' "$T/att.out")"
check "attese.sh sul corpus costruito: exit 0, nessun DIVERSO" '[ $rc -eq 0 ] && ! grep -q "^attese: .* DIVERSO" "$T/att.out" && grep -q "^attese: confronto · .*diversi=0" "$T/att.out"' \
  "rc=$rc $(grep -v '^attese: [a-z-]*\.txt UGUALE' "$T/att.out" | head -60)"
# the first word of Next of every spec, from the outputs just computed
parole() { awk '/^== [^ \/]*\/[^ ]*$/ { cur = substr($0, 4); w = "-"; next } /^Next: / { w = $2 } /^== exit / { print cur, w }' "$1" | LC_ALL=C sort; }
casi | awk -F'\t' '$1 == "spec" { print $2 "/" $3, $4 }' | LC_ALL=C sort > "$T/parole-attese"
for l in it en; do
  check "  next-$l.txt UGUALE alle attese ($NS spec)" 'grep -qx "attese: next-$l.txt UGUALE ($NS blocchi)" "$T/att.out"' "$(grep "next-$l" "$T/att.out")"
  dp=$(diff "$T/parole-attese" <(parole "$T/att/next-$l.txt" 2>/dev/null))
  check "  ($l) la prima parola di Next di ogni spec = casi.tsv" '[ -s "$T/att/next-$l.txt" ] && [ -z "$dp" ]' "$dp"
done
saltati=""
for v in minimo jsonschema; do
  if grep -q "^SALTATO: $v " "$T/att.out"; then
    echo "SALTATO: $v (attese.sh: nessun interprete con il validatore $v)"; saltati+=" $v"; continue
  fi
  for l in it en; do
    check "  valida-$v-$l.txt UGUALE alle attese ($NJ jsonl)" 'grep -qx "attese: valida-$v-$l.txt UGUALE ($NJ blocchi)" "$T/att.out"' "$(grep "valida-$v-$l" "$T/att.out")"
  done
done
prima=$(tr -d '\r' < "$EQ/attese/STORIA" 2>/dev/null | grep -v '^\(#\|[[:space:]]*$\)' | head -1)
check "attese/STORIA: la prima riga e' la scrittura dal plugin di v1.5.1 (l'ancora della prova)" \
  '[[ $prima == *" · plugin ref v1.5.1 ("*", versione 1.5.1 · "* ]]' "${prima:-(nessuna riga)}"

# --- counterproofs (a), (b): copies of the plugin with a mutated driver.py, against the expected outputs ---
copia_plugin() { mkdir -p "$T/$1" && cp -R "$ROOT/plugins/maat/." "$T/$1/" && find "$T/$1" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null; return 0; }
diversi() { sed -n 's/^  DIVERSO \(.*\)$/\1/p' "$1"; }
copia_plugin drv-a
sed 's/"IMPLEMENT — " + T("cycle-state.impl")/"IMPLEMENT — " + T("cycle-state.plan_draft")/' "$DRV" > "$T/drv-a/scripts/driver.py"
check "controprova (a): la mutazione e' applicata (il gemello Python di IMPLEMENT punta a un'altra chiave)" 'grep -qF "\"IMPLEMENT — \" + T(\"cycle-state.plan_draft\")" "$T/drv-a/scripts/driver.py"'
mutata() { env -u MAAT_ATTESE_RICHIESTE -u MAAT_ATTESE_VALIDA -u FIC_DRIVER MAAT_ATTESE_PLUGIN="$1" bash "$AT" "${@:2}"; }
mutata "$T/drv-a" --corpus "$T/c1" --repo progetto-storico --solo next --lingua it > "$T/att-a.out" 2>&1; rc=$?
d_a=$(diversi "$T/att-a.out")
fuori_a=$(printf '%s\n' "$d_a" | grep . | while IFS= read -r s; do grep -qx "$s IMPLEMENT" "$T/parole-attese" || echo "$s"; done)
check "controprova (a): DIVERSO solo sulle spec IMPLEMENT di progetto-storico (next, it), exit 1" '[ $rc -eq 1 ] && [ -n "$d_a" ] && [ -z "$fuori_a" ]' \
  "rc=$rc $(grep -v '^    ' "$T/att-a.out" | tail -8) · fuori: $fuori_a"
copia_plugin drv-b
sed 's/^DIFENSIVA = ("difensiva: ", "defensive: ")$/DIFENSIVA = ("difensiva: ",)/' "$DRV" > "$T/drv-b/scripts/driver.py"
check "controprova (b): la mutazione e' applicata (DIFENSIVA senza «defensive: »)" 'grep -qx "DIFENSIVA = (\"difensiva: \",)" "$T/drv-b/scripts/driver.py"'
mutata "$T/drv-b" --corpus "$T/c1" --repo progetto-singoli --lingua it > "$T/att-b.out" 2>&1; rc=$?
d_b=$(diversi "$T/att-b.out")
check "controprova (b): DIVERSO su almeno un jsonl (valida) e su almeno una spec (next) di progetto-singoli, exit 1" \
  '[ $rc -eq 1 ] && printf "%s\n" "$d_b" | grep -q "\.jsonl$" && printf "%s\n" "$d_b" | grep -q "/spec-[^/]*$"' "rc=$rc $(grep -v '^    ' "$T/att-b.out" | tail -10)"

# --- counterproof (g): an expected output with one line changed ---
mkdir -p "$T/att-g" && cp "$EQ/attese/"* "$T/att-g/"
awk 'BEGIN { m = 0 } /^== progetto-impronta-nc\// && !m { b = 1 } b && /^Next: / { $0 = $0 " (cambiata)"; b = 0; m = 1 } { print }' "$EQ/attese/next-it.txt" > "$T/att-g/next-it.txt"
check "controprova (g): la mutazione e' applicata (una riga Next: di progetto-impronta-nc in next-it.txt)" \
  '[ "$(diff "$EQ/attese/next-it.txt" "$T/att-g/next-it.txt" | grep -c "^>")" = 1 ]'
attese --attese "$T/att-g" --corpus "$T/c1" --repo progetto-impronta-nc --solo next --lingua it > "$T/att-g.out" 2>&1; rc=$?
d_g=$(diversi "$T/att-g.out")
attese --corpus "$T/c1" --repo progetto-impronta-nc --solo next --lingua it > "$T/att-g0.out" 2>&1; rc0=$?
check "controprova (g): un'attesa con una riga cambiata → DIVERSO su quel blocco solo, exit 1 (le attese vere: exit 0)" \
  '[ $rc -eq 1 ] && [ "$d_g" = "progetto-impronta-nc/spec-esempio-harness-not-computable" ] && [ $rc0 -eq 0 ]' "rc=$rc rc0=$rc0 $d_g · $(tail -3 "$T/att-g0.out")"

# --- counterproof (h): the normalizations, one by one ---
norm() { "$FIC_PY" "$(nat "$EQ/attese.py")" normalizza "$(nat "$1")"; }
H=$T/h; mkdir -p "$H/vera/r/maat"
ln -s vera "$H/link" 2>/dev/null
LINK=0; [ -L "$H/link" ] && [ -d "$H/link/r" ] && LINK=1
if [ $LINK = 1 ]; then R=$H/link/r; else R=$H/vera/r; echo "SALTATO: (h) forma pwd -P (nessun collegamento simbolico qui)"; fi
M=$R/maat
F64=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
{ bash "$AT" --forme "$R" | sed 's/^/path	<REPO>	/'; bash "$AT" --forme "$M" | sed 's/^/path	<MAAT>	/'
  printf 'hex\t<impronta-attuale>\t%s\nhex\t<impronta-attuale>\t%s\n' "$F64" "${F64:0:12}"; } > "$H/forme"
# input <TAB> expected; every input carries «motivo A», the counterproof changes it to «motivo B»
{ printf 'STOP — motivo A: %s/.claude/x.md\tSTOP — motivo A: <REPO>/.claude/x.md\n' "$R"
  printf 'motivo A: di %s.\tmotivo A: di <REPO>.\n' "$R"
  printf 'motivo A: %s/scripts/review-surface.sh tree\tmotivo A: <MAAT>/scripts/review-surface.sh tree\n' "$M"
  printf 'motivo A: %s-altro/x e %sx/y e /pre%s/z\tmotivo A: %s-altro/x e %sx/y e /pre%s/z\n' "$R" "$R" "$R" "$R" "$R" "$R"
  printf 'motivo A: attuale %s, registrata %s\tmotivo A: attuale <impronta-attuale>, registrata <impronta-attuale>\n' "${F64:0:12}" "$F64"
  printf 'motivo A: %s e %sa\tmotivo A: %s e %sa\n' "${F64:0:13}" "$F64" "${F64:0:13}" "$F64"
  if [ $LINK = 1 ]; then
    printf 'motivo A: %s/.claude/maat.json e %s/scripts\tmotivo A: <REPO>/.claude/maat.json e <MAAT>/scripts\n' "$H/vera/r" "$H/vera/r/maat"
  fi
  if command -v cygpath >/dev/null 2>&1; then
    printf 'motivo A: %s/x e %s/y\tmotivo A: <REPO>/x e <REPO>/y\n' "$(cygpath -m "$R")" "$(cygpath -u "$(cygpath -m "$R")")"
  fi
} > "$H/casi"
command -v cygpath >/dev/null 2>&1 || echo "SALTATO: (h) forme cygpath -m e -u (niente cygpath: non Windows)"
cut -f1 "$H/casi" > "$H/in"; cut -f2 "$H/casi" > "$H/atteso"
norm "$H/forme" < "$H/in" | tr -d '\r' > "$H/out"
dh=$(diff "$H/atteso" "$H/out")
check "controprova (h): ogni forma dell'elenco chiuso diventa il suo segnaposto, solo al confine ($(grep -c . "$H/in") righe)" '[ -s "$H/in" ] && [ -z "$dh" ]' "$dh"
sed 's/motivo A/motivo B/' "$H/in" | norm "$H/forme" | tr -d '\r' > "$H/out-b"
uguali_b=$(paste -d '\n' "$H/out" "$H/out-b" | awk 'NR % 2 { a = $0; next } a == $0 { print a }')
check "controprova (h): un carattere del motivo cambiato in ogni riga → ogni riga normalizzata diversa (rossa)" '[ -s "$H/out-b" ] && [ -z "$uguali_b" ]' "$uguali_b"
printf 'path\t<REPO>\t/x/aaaa\npath\t<MAAT>\t/x/bbbb\n' > "$H/forme-pari"
o=$(printf 'motivo A: /x/aaaa/1 e /x/bbbb/2\n' | norm "$H/forme-pari" | tr -d '\r')
check "controprova (h): forme di pari lunghezza, tutte e due sostituite" '[ "$o" = "motivo A: <REPO>/1 e <MAAT>/2" ]' "$o"

# --- 5. the strict checks: no validator SALTATO, attese/ changed only with STORIA (MAAT_ATTESE_RICHIESTE=1) ---
# counterproof (i): MAAT_PY_JSONSCHEMA pointing to a Python without jsonschema
PYNO=""
for c in "${MAAT_PY_MINIMO:-}" "$FIC_PY"; do [ -n "$c" ] && [ "$(validatore "$c")" = minimo ] && { PYNO=$c; break; }; done
if [ -n "$PYNO" ]; then
  MAAT_ATTESE_RICHIESTE=1 MAAT_PY_JSONSCHEMA=$PYNO bash "$AT" --validatori > "$T/vi1.out" 2>&1; rc1=$?
  env -u MAAT_ATTESE_RICHIESTE MAAT_PY_JSONSCHEMA=$PYNO bash "$AT" --validatori > "$T/vi0.out" 2>&1; rc0=$?
  check "controprova (i): MAAT_PY_JSONSCHEMA senza jsonschema → con MAAT_ATTESE_RICHIESTE=1 SALTATO e rosso (exit 1), senza SALTATO e verde" \
    '[ $rc1 -eq 1 ] && grep -q "^SALTATO: jsonschema" "$T/vi1.out" && grep -q "ROSSO" "$T/vi1.out" && [ $rc0 -eq 0 ] && grep -q "^SALTATO: jsonschema" "$T/vi0.out"' \
    "rc1=$rc1 rc0=$rc0 $(cat "$T/vi1.out")"
else
  echo "SALTATO: controprova (i) (nessun interprete senza jsonschema: MAAT_PY_MINIMO)"
fi
# counterproof (j): a fake repo with attese/ changed and STORIA not
J=$T/j; mkdir -p "$J/tools/esempi-equiv/attese"; cp "$AT" "$EQ/attese.py" "$J/tools/esempi-equiv/"
printf 'a\n' > "$J/tools/esempi-equiv/attese/next-it.txt"; printf '# t\nriga 1\n' > "$J/tools/esempi-equiv/attese/STORIA"
gj() { git -C "$J" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c core.autocrlf=false "$@" >/dev/null 2>&1; }
gj init -q && gj add -A && gj commit -q -m base && JB=$(git -C "$J" rev-parse HEAD)
printf 'b\n' > "$J/tools/esempi-equiv/attese/next-it.txt"; gj commit -q -am cambio
bash "$J/tools/esempi-equiv/attese.sh" --storia "$JB" > "$T/vj1.out" 2>&1; rj1=$?
printf 'riga 2\n' >> "$J/tools/esempi-equiv/attese/STORIA"
bash "$J/tools/esempi-equiv/attese.sh" --storia "$JB" > "$T/vj2.out" 2>&1; rj2=$?
printf '# t\nriga 1 riscritta\nriga 2\n' > "$J/tools/esempi-equiv/attese/STORIA"
bash "$J/tools/esempi-equiv/attese.sh" --storia "$JB" > "$T/vj3.out" 2>&1; rj3=$?
check "controprova (j): attese/ cambiata e STORIA invariata → rosso; una riga in fondo → verde; STORIA riscritta → rosso" \
  '[ -n "${JB:-}" ] && [ $rj1 -eq 1 ] && [ $rj2 -eq 0 ] && [ $rj3 -eq 1 ]' "rj1=$rj1 rj2=$rj2 rj3=$rj3 $(cat "$T/vj1.out" "$T/vj2.out" "$T/vj3.out")"
if [ "${MAAT_ATTESE_RICHIESTE:-0}" = 1 ]; then
  check "MAAT_ATTESE_RICHIESTE=1: nessun validatore SALTATO" '[ -z "$saltati" ]' "SALTATO:$saltati"
  bash "$AT" --storia > "$T/storia.out" 2>&1; rc=$?
  check "MAAT_ATTESE_RICHIESTE=1: attese/ cambiata solo con una riga nuova in attese/STORIA (base: merge-base con origin/main)" '[ $rc -eq 0 ]' "rc=$rc $(cat "$T/storia.out")"
else
  echo "esempi-equiv: controlli rigidi non richiesti (MAAT_ATTESE_RICHIESTE=1 per attivarli) · saltati:${saltati:- nessuno} · $(bash "$AT" --storia 2>&1 | head -1)"
fi

find "$ROOT/plugins/maat" -name __pycache__ -type d | grep -q . && { echo "FAIL [__pycache__ nel plugin]"; fail=$((fail + 1)); }

echo "esempi-equiv.test.sh: $pass passati, $fail falliti"
[ $fail -eq 0 ]
