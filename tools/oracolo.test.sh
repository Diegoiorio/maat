#!/usr/bin/env bash
# oracolo.test.sh — tools/oracolo.sh on the public corpus (Maat 1.5.0, Block E). A test of the repo only.
#   bash tools/oracolo.test.sh          (Git Bash or Linux)
#   MAAT_ORACOLO_TEST=completo|ridotto  case 2 (both sides from a ref) on the whole corpus or on two small mini-repos
#                                       (default: completo on Linux, ridotto elsewhere: on Windows every spec costs a
#                                       few seconds per side and language)
# The corpus is built once (tools/esempi-equiv/costruisci.sh) and shared by every case.
#   0. usage: no argument, a side that is neither a plugin folder nor a ref, a project without .claude/.ai-workflow/
#      → exit 2;
#   1. HEAD against the plugin folder of this repo (in CI the same content), the whole corpus: exit 0, «diverse=0», N
#      = the specs of casi.tsv, the harness.fp fixtures kept (none rewritten), the projects given never written;
#      the records include the row-0 STOPs of the fixtures (with the current fingerprint normalized) and the C4 STOP
#      with the path of review-surface.sh; from the «oracolo: parola …» lines every spec has, on EVERY side and
#      language, the word of casi.tsv (the harness-fixture ones: STOP);
#   2. both sides from a ref (HEAD against HEAD) → identical. When git cannot read this repository (a Windows worktree
#      seen from WSL: its .git points to a C:/ path) the cases from a ref are SALTATO and case 1 is folder against
#      folder.
# Counterproofs (copies of the plugin or of the oracle, never the files of the repo):
#   (i)   new side = the plugin with the it text of cycle-state.impl changed in the catalog → differences in it only on
#         IMPLEMENT specs, en still equal (State and word), exit 1;
#   (ii)  new side = cycle-state.sh with «chiuso;» → «closed;» in chain_state → every mother differs in BOTH languages;
#   (iii) a copy of tools/oracolo.sh that ignores .claude/oracolo-conserva (the CONSERVA line) → the two sides are still
#         equal to each other (exit 0), but the harness-fixture spec CAMBIATO leaves STOP: the word check is red; the
#         same specs with the real oracle stay STOP (the check is not red by itself).
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1 LC_ALL=C
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OR=$ROOT/tools/oracolo.sh
EQ=$ROOT/tools/esempi-equiv
PLUGIN=$ROOT/plugins/maat
pass=0 fail=0
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
check() { # $1 description, $2 condition (eval), [$3 detail on failure]
  if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$1]"; [ -n "${3:-}" ] && printf '%s\n' "$3" | head -30 | sed 's/^/    /'; fi
}
casi() { tr -d '\r' < "$EQ/casi.tsv" | grep -v '^#' | grep .; }
riga() { grep '^oracolo: spec=' "$1" | tail -1; }
MODO=${MAAT_ORACOLO_TEST:-}
[ -n "$MODO" ] || { MODO=ridotto; [ "$(uname -s)" = Linux ] && MODO=completo; }
case $MODO in completo|ridotto) ;; *) echo "MAAT_ORACOLO_TEST: completo or ridotto"; exit 2 ;; esac
REF=HEAD
git -C "$ROOT" rev-parse -q --verify "HEAD^{commit}" >/dev/null 2>&1 || REF=

t0=$(date +%s)
bash "$EQ/costruisci.sh" "$T/c" > "$T/c.out" 2>&1 || { echo "oracolo.test.sh: the corpus does not build"; tail -5 "$T/c.out"; exit 1; }
MINI=(); while IFS= read -r m; do MINI+=("$T/c/$m"); done < <(sed -n 's/^esempi-equiv: \(progetto-[^ ]*\) · spec=.*/\1/p' "$T/c.out")
echo "oracolo.test: corpus ${#MINI[@]} mini-repo in $(( $(date +%s) - t0 ))s · modo $MODO"
NS=$(casi | awk -F'\t' '$1 == "spec"' | grep -c .)

# --- 0. usage ---
bash "$OR" > /dev/null 2>&1; rc=$?
check "senza argomenti → exit 2" '[ $rc -eq 2 ]'
bash "$OR" "$T/nessuno" "$PLUGIN" "${MINI[0]}" > "$T/u.out" 2>&1; rc=$?
check "un lato che non e' ne' una cartella del plugin ne' un ref → exit 2" '[ $rc -eq 2 ] && grep -q "neither a plugin folder nor a git ref" "$T/u.out"' "rc=$rc $(cat "$T/u.out")"
mkdir -p "$T/vuoto"
bash "$OR" "$PLUGIN" "$PLUGIN" "$T/vuoto" > "$T/u.out" 2>&1; rc=$?
check "un progetto senza .claude/.ai-workflow → exit 2" '[ $rc -eq 2 ] && grep -q "not a project root" "$T/u.out"' "rc=$rc $(cat "$T/u.out")"

# --- 1. HEAD against the plugin folder, the whole corpus ---
stato() { find "$T/c" -type f -printf '%P %T@ %s\n' | sort | sha256sum | cut -c1-64; }   # path, mtime, size
s0=$(stato)
V1=${REF:-$PLUGIN}
[ -n "$REF" ] || echo "SALTATO: i lati da un ref (git non legge $ROOT da qui): il caso 1 e' cartella contro cartella"
t0=$(date +%s)
bash "$OR" --esiti "$T/e1" "$V1" "$PLUGIN" "${MINI[@]}" > "$T/o1.out" 2>&1; rc=$?
echo "oracolo.test: caso 1 $(( $(date +%s) - t0 ))s · $(riga "$T/o1.out")"
check "caso 1: ${V1##*/} contro la cartella del plugin → exit 0, spec=$NS, diverse=0" \
  '[ $rc -eq 0 ] && [ "$(riga "$T/o1.out")" = "oracolo: spec=$NS · it uguali=$NS · en uguali=$NS · diverse=0" ]' "rc=$rc $(grep -v '^oracolo: parola' "$T/o1.out")"
check "  le fixture conservate (4 harness.fp × 2 lati × 2 lingue), nessuna riscritta, nessuna non UGUALE" \
  'grep -qx "oracolo: harness.fp riscritti=0 · conservati=16 · non-uguali=0" "$T/o1.out"' "$(grep '^oracolo: harness' "$T/o1.out")"
check "  i progetti dati non sono stati scritti (percorsi, mtime e dimensioni uguali)" '[ "$(stato)" = "$s0" ]'
F=$T/e1/nuovo-it/progetto-singoli/spec-esempio-harness-changed.txt
check "  i record comprendono lo STOP di riga 0 sulla fixture CAMBIATO, impronta attuale normalizzata" \
  'grep -q "^Next: STOP — harness cambiato .*impronta registrata 000000000000, attuale <impronta-attuale>" "$F"' "$(grep '^Next' "$F" 2>&1)"
F=$T/e1/vecchio-it/progetto-impronta-nc/spec-esempio-harness-not-computable.txt
check "  e lo STOP NON-CALCOLABILE, sui due lati" 'grep -q "^Next: STOP" "$F" && diff -q "$F" "${F/vecchio-it/nuovo-it}" >/dev/null' "$(grep '^Next' "$F" 2>&1)"
c4=$(grep -l '^Next: STOP — catena: .*review-surface.sh tree' "$T/e1/nuovo-it"/*/*.txt 2>/dev/null | head -1)
check "  e lo STOP C4 «albero cambiato» col percorso di review-surface.sh" '[ -n "$c4" ] && grep -q "/maat/scripts/review-surface.sh tree" "$c4"' "${c4:-nessun record}"
# the words: every spec, side and language = casi.tsv
casi | awk -F'\t' '$1 == "spec" { for (l = 1; l <= 4; l++) print $2 "/" $3, $4 }' | LC_ALL=C sort > "$T/attese"
parole() { sed -n 's/^oracolo: parola [a-z]* [a-z]* \([^ ]*\) \([^ ]*\)$/\1 \2/p' "$1" | LC_ALL=C sort; }
dp=$(diff "$T/attese" <(parole "$T/o1.out"))
check "  la parola di Next di ogni spec, in ogni lato e lingua = casi.tsv ($NS × 4)" '[ -z "$dp" ]' "$dp"
casi | awk -F'\t' '$1 == "spec" && ("," $6 ",") ~ /,harness-fixture,/ { print $2 "/" $3 }' > "$T/fixture"
fx=$(while IFS= read -r s; do n=$(grep -c "^oracolo: parola [a-z]* [a-z]* $s STOP$" "$T/o1.out"); [ "$n" = 4 ] || echo "$s: $n su 4"; done < "$T/fixture")
check "  le spec harness-fixture ($(grep -c . "$T/fixture")) sono STOP in ogni lato e lingua" '[ -s "$T/fixture" ] && [ -z "$fx" ]' "$fx"

# --- 2. both sides from a ref ---
if [ -n "$REF" ]; then
  if [ $MODO = completo ]; then M2=("${MINI[@]}"); else M2=("$T/c/progetto-catena-aperta" "$T/c/progetto-impronta-nc"); fi
  n2=$(casi | awk -F'\t' -v l=" ${M2[*]##*/} " '$1 == "spec" && index(l, " " $2 " ")' | grep -c .)
  t0=$(date +%s)
  bash "$OR" HEAD HEAD "${M2[@]}" > "$T/o2.out" 2>&1; rc=$?
  echo "oracolo.test: caso 2 $(( $(date +%s) - t0 ))s · ${#M2[@]} mini-repo"
  check "caso 2: HEAD contro HEAD (i due lati da git archive) → identico, spec=$n2" \
    '[ $rc -eq 0 ] && [ "$(riga "$T/o2.out")" = "oracolo: spec=$n2 · it uguali=$n2 · en uguali=$n2 · diverse=0" ]' "rc=$rc $(grep -v '^oracolo: parola' "$T/o2.out")"
else
  echo "SALTATO: caso 2, HEAD contro HEAD (git non legge $ROOT da qui)"
fi

# --- counterproofs ---
copia_plugin() { mkdir -p "$T/$1" && cp -R "$PLUGIN/." "$T/$1/" && find "$T/$1" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null; return 0; }
intestazioni() { sed -n 's/^--- \([^ ]*\) \(it\|en\)[ :].*/\1 \2/p' "$1" | LC_ALL=C sort; }

# (i) the it text of cycle-state.impl changed
copia_plugin pi
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "cycle-state.impl" { $3 = $3 " (mutata)" } { print }' "$PLUGIN/scripts/lib/messages.tsv" > "$T/pi/scripts/lib/messages.tsv"
check "controprova (i): la mutazione e' applicata (voce it di cycle-state.impl)" 'grep -q "^cycle-state.impl	.*	.* (mutata)$" "$T/pi/scripts/lib/messages.tsv"'
bash "$OR" "$PLUGIN" "$T/pi" "$T/c/progetto-storico" > "$T/oi.out" 2>&1; rc=$?
h_i=$(intestazioni "$T/oi.out")
fuori_i=$(printf '%s\n' "$h_i" | grep . | while read -r s l; do
  [ "$l" = it ] || { echo "$s $l"; continue; }
  w=$(casi | awk -F'\t' -v s="$s" '$1 == "spec" && $2 "/" $3 == s { print $4 }'); [ "$w" = IMPLEMENT ] || echo "$s ($w)"; done)
ns_i=$(casi | awk -F'\t' '$1 == "spec" && $2 == "progetto-storico"' | grep -c .)
check "controprova (i): diff in it solo sulle spec IMPLEMENT, en uguale, exit 1" \
  '[ $rc -eq 1 ] && [ -n "$h_i" ] && [ -z "$fuori_i" ] && riga "$T/oi.out" | grep -q " · en uguali=$ns_i · "' "rc=$rc $(riga "$T/oi.out") · $fuori_i"

# (ii) «chiuso;» → «closed;» in chain_state
copia_plugin pii
sed 's/chain_state="\$chain_state\$c chiuso;"/chain_state="$chain_state$c closed;"/' "$PLUGIN/scripts/cycle-state.sh" > "$T/pii/scripts/cycle-state.sh"
check "controprova (ii): la mutazione e' applicata (chiuso; → closed; in chain_state)" 'grep -qF "\$c closed;\"" "$T/pii/scripts/cycle-state.sh"'
bash "$OR" "$PLUGIN" "$T/pii" "$T/c/progetto-catene-chiuse" > "$T/oii.out" 2>&1; rc=$?
madri=$(cd "$T/c/progetto-catene-chiuse/.claude/.ai-workflow" && grep -lE '^(Figlie|Children):' spec-*.md | sed 's/\.md$//')
h_ii=$(intestazioni "$T/oii.out")
manca_ii=$(for s in $madri; do for l in it en; do printf '%s\n' "$h_ii" | grep -qx "progetto-catene-chiuse/$s $l" || echo "$s $l"; done; done)
check "controprova (ii): ogni madre ($(echo $madri | wc -w)) diversa in it e in en, exit 1" \
  '[ $rc -eq 1 ] && [ -n "$madri" ] && [ -z "$manca_ii" ]' "rc=$rc $(riga "$T/oii.out") · mancano: $manca_ii"

# (iii) an oracle that ignores .claude/oracolo-conserva, on the mini-repos with the harness-fixture specs reduced to them
mkdir -p "$T/r"
for m in $(cut -d/ -f1 "$T/fixture" | sort -u); do
  cp -a "$T/c/$m" "$T/r/$m"
  (cd "$T/r/$m/.claude/.ai-workflow" && for s in spec-*.md; do
    grep -qx "$m/${s%.md}" "$T/fixture" || rm -rf "$s" "${s%.md}.run"; done)
done
mkdir -p "$T/oc/tools"; grep -v '# CONSERVA$' "$OR" > "$T/oc/tools/oracolo.sh"
check "controprova (iii): la mutazione e' applicata (la riga CONSERVA tolta)" 'grep -q "# CONSERVA$" "$OR" && ! grep -q "oracolo-conserva\" ] &&" "$T/oc/tools/oracolo.sh"'
parole_fixture() { # $1 oracle output → the specs harness-fixture not STOP on some side or language
  while IFS= read -r s; do n=$(grep -c "^oracolo: parola [a-z]* [a-z]* $s STOP$" "$1"); [ "$n" = 4 ] || echo "$s: STOP $n su 4"; done < "$T/fixture"
}
bash "$OR" "$PLUGIN" "$PLUGIN" "$T/r"/*/ > "$T/oiii-ok.out" 2>&1; rc_ok=$?
bash "$T/oc/tools/oracolo.sh" "$PLUGIN" "$PLUGIN" "$T/r"/*/ > "$T/oiii.out" 2>&1; rc=$?
pf_ok=$(parole_fixture "$T/oiii-ok.out"); pf=$(parole_fixture "$T/oiii.out")
check "controprova (iii): con l'oracolo vero le fixture restano STOP (exit 0)" '[ $rc_ok -eq 0 ] && [ -z "$pf_ok" ]' "rc=$rc_ok $pf_ok"
check "controprova (iii): l'oracolo che ignora oracolo-conserva → lati uguali (exit 0) ma la fixture CAMBIATO non e' piu' STOP: rosso" \
  '[ $rc -eq 0 ] && printf "%s\n" "$pf" | grep -q "spec-esempio-harness-changed: STOP 0 su 4"' "rc=$rc $(grep -v '^oracolo: parola' "$T/oiii.out") · $pf"

find "$PLUGIN" -name __pycache__ -type d | grep -q . && { echo "FAIL [__pycache__ nel plugin]"; fail=$((fail + 1)); }
echo "oracolo.test.sh: $pass passati, $fail falliti"
[ $fail -eq 0 ]
