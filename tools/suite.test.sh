#!/usr/bin/env bash
# suite.test.sh — tools/suite.sh (Maat 1.5.0, block 0): the tools/… entries of suite.list and the guard of the run.
# On a copy of the repo in a temporary folder (tools/ and plugins/maat/, the real suites removed), with fake suites:
#   1 a suite that changes a plugin file → its line says PLUGIN CAMBIATO, exit 1; the next suite (no change) does not
#   2 a suite that touches nothing → no PLUGIN CAMBIATO, exit 0 (a plain name, plugins/maat/scripts/<name>.test.sh, too)
#   3 a tools/x.test.sh not in the list → exit 2 · 4 a tools/… entry with no file → exit 2
#   5 counterproof: a guard that takes the fingerprint only once (before = after by construction) → case 1 green, red
#   bash tools/suite.test.sh          (Git Bash or WSL; only in the repo)
set -uo pipefail
export MAAT_LINGUA=it
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; [ -n "${3:-}" ] && printf '%s\n' "$3" | head -20 | sed 's/^/    /'; fi; }

R=$T/repo
mkdir -p "$R/plugins" && cp -r "$ROOT/tools" "$R/" && cp -r "$ROOT/plugins/maat" "$R/plugins/" &&
  find "$R" -name __pycache__ -type d -prune -exec rm -rf {} + || exit 2
rm -f "$R"/plugins/maat/scripts/*.test.sh "$R/plugins/maat/scripts/test-review-surface.sh" "$R"/tools/*.test.sh
SUITE_SH=$R/tools/suite.sh
# $1 = the list (entries separated by spaces); the fake suites are created by the caller · rc, $T/out, $T/esiti
corri() {
  printf '%s\n' "# finta" $1 > "$R/tools/suite.list"
  rm -rf "$T/esiti"; (cd "$R" && bash "$SUITE_SH" "$T/esiti") > "$T/out" 2>&1; rc=$?
}
riga() { grep "^$1 " "$T/esiti/riepilogo.txt" 2>/dev/null; }
pulisci() { rm -f "$R"/tools/*.test.sh "$R"/plugins/maat/scripts/*.test.sh; }
tocca() { printf '%s\n' '#!/usr/bin/env bash' 'printf "riga in piu\n" >> plugins/maat/README.md; echo "finta: plugin toccato"' > "$R/tools/finta-tocca.test.sh"; }
ferma() { printf '%s\n' '#!/usr/bin/env bash' 'echo "finta: niente toccato"' > "$R/tools/finta-ferma.test.sh"; }
cp "$R/plugins/maat/README.md" "$T/README.orig"

# --- 1. a suite that changes a plugin file, then one that does not ---
pulisci; tocca; ferma; corri "tools/finta-tocca.test.sh tools/finta-ferma.test.sh"
caso_modifica() { [ $rc -eq 1 ] && riga tools/finta-tocca.test.sh | grep -q "rc=0 .*PLUGIN CAMBIATO" && riga tools/finta-ferma.test.sh | grep -q "rc=0" && ! riga tools/finta-ferma.test.sh | grep -q "PLUGIN CAMBIATO"; }
check "1 suite che modifica un file del plugin → la sua riga dice PLUGIN CAMBIATO (rc della suite 0), exit 1; la suite dopo no" 'caso_modifica' "$(cat "$T/out")"
cp "$T/README.orig" "$R/plugins/maat/README.md"

# --- 2. a suite that touches nothing (a tools/ entry and a plain name) ---
pulisci; ferma; printf '%s\n' '#!/usr/bin/env bash' 'echo "finta del plugin"' > "$R/plugins/maat/scripts/finta.test.sh"
corri "tools/finta-ferma.test.sh finta"
check "2 suite che non toccano niente → nessuna riga PLUGIN CAMBIATO, exit 0; il nome semplice è plugins/maat/scripts/<nome>.test.sh" '[ $rc -eq 0 ] && ! grep -q "PLUGIN CAMBIATO" "$T/esiti/riepilogo.txt" && riga finta | grep -q "finta del plugin" && [ -f "$T/esiti/tools-finta-ferma.test.sh.log" ]' "$(cat "$T/out")"

# --- 3-4. the list against the files ---
pulisci; ferma; printf '%s\n' '#!/usr/bin/env bash' 'echo x' > "$R/tools/x.test.sh"; corri "tools/finta-ferma.test.sh"
check "3 tools/x.test.sh non in lista → exit 2, nessuna suite lanciata" '[ $rc -eq 2 ] && grep -q "tools/x.test.sh is not in the list" "$T/out" && [ ! -f "$T/esiti/riepilogo.txt" ]' "$(cat "$T/out")"
pulisci; ferma; corri "tools/finta-ferma.test.sh tools/assente.test.sh"
check "4 voce tools/… senza file → exit 2" '[ $rc -eq 2 ] && grep -q "tools/assente.test.sh has no file" "$T/out"' "$(cat "$T/out")"
pulisci; ferma; printf '%s\n' '#!/usr/bin/env bash' 'echo y' > "$R/plugins/maat/scripts/y.test.sh"; corri "tools/finta-ferma.test.sh"
check "  e una suite del plugin non in lista → exit 2, come prima" '[ $rc -eq 2 ] && grep -q "plugins/maat/scripts/y.test.sh is not in the list" "$T/out"' "$(cat "$T/out")"

# --- 5. counterproof: the fingerprint taken only once ---
cp "$SUITE_SH" "$T/suite.orig"
sed -i 's/^  dopo=$(guardia_impronta plugins\/maat)   # GUARDIA-DOPO$/  dopo=$prima   # GUARDIA-DOPO tolta/' "$SUITE_SH"
check "controprova: la mutazione è applicata (impronta presa una volta sola)" 'grep -q "GUARDIA-DOPO tolta" "$SUITE_SH"'
pulisci; tocca; ferma; corri "tools/finta-tocca.test.sh tools/finta-ferma.test.sh"
check "controprova: con l'impronta presa una volta sola il caso 1 non regge (nessun PLUGIN CAMBIATO, exit 0)" '! caso_modifica && [ $rc -eq 0 ]' "$(cat "$T/out")"
cp "$T/suite.orig" "$SUITE_SH"; cp "$T/README.orig" "$R/plugins/maat/README.md"
pulisci; tocca; ferma; corri "tools/finta-tocca.test.sh tools/finta-ferma.test.sh"
check "  copia ripristinata → il caso 1 torna verde" 'caso_modifica' "$(cat "$T/out")"

# --- 6. (1.5.1) --gruppo <k>/<n> and tools/suite-gruppi.list ---
# $1 = list, $2 = groups file content (lines "<g> <entry>" separated by ;), $3 = --gruppo argument
corri_g() {
  printf '%s\n' "# finta" $1 > "$R/tools/suite.list"
  printf '%s\n' "# finta" > "$R/tools/suite-gruppi.list"; local IFS=';'; printf '%s\n' $2 >> "$R/tools/suite-gruppi.list"; unset IFS
  rm -rf "$T/esiti"; (cd "$R" && bash "$SUITE_SH" --gruppo "$3" "$T/esiti") > "$T/out" 2>&1; rc=$?
}
pulisci; ferma; printf '%s\n' '#!/usr/bin/env bash' 'echo "finta del plugin"' > "$R/plugins/maat/scripts/finta.test.sh"
L6="tools/finta-ferma.test.sh finta"
corri_g "$L6" "2 tools/finta-ferma.test.sh;1 finta" 2/2
check "6 --gruppo 2/2 → solo le suite del gruppo 2, exit 0" '[ $rc -eq 0 ] && riga tools/finta-ferma.test.sh | grep -q "rc=0" && ! riga finta' "$(cat "$T/out")"
corri_g "$L6" "2 tools/finta-ferma.test.sh;1 finta" 1/2
check "  --gruppo 1/2 → solo finta" '[ $rc -eq 0 ] && riga finta | grep -q "finta del plugin" && ! riga tools/finta-ferma.test.sh' "$(cat "$T/out")"
corri_g "$L6" "1 tools/finta-ferma.test.sh" 1/1
check "  una suite della lista in nessun gruppo → exit 2, nessuna suite lanciata" '[ $rc -eq 2 ] && grep -q "finta is in 0 groups" "$T/out" && [ ! -f "$T/esiti/riepilogo.txt" ]' "$(cat "$T/out")"
corri_g "$L6" "1 tools/finta-ferma.test.sh;1 finta;2 finta" 2/2
check "  una suite in due gruppi → exit 2" '[ $rc -eq 2 ] && grep -q "finta is in 2 groups" "$T/out"' "$(cat "$T/out")"
corri_g "$L6" "1 tools/finta-ferma.test.sh;1 finta;1 assente" 1/1
check "  una voce del file non in suite.list → exit 2" '[ $rc -eq 2 ] && grep -q "assente is not in suite.list" "$T/out"' "$(cat "$T/out")"
corri_g "$L6" "1 tools/finta-ferma.test.sh;1 finta" 1/2
check "  il file ha meno gruppi di n (la matrice della CI non coincide) → exit 2" '[ $rc -eq 2 ] && grep -q "group 2 has no suite" "$T/out"' "$(cat "$T/out")"
corri_g "$L6" "1 tools/finta-ferma.test.sh;3 finta" 1/2
check "  un gruppo fuori da 1..n → exit 2" '[ $rc -eq 2 ] && grep -q "finta is in group 3, outside 1..2" "$T/out"' "$(cat "$T/out")"
corri_g "$L6" "1 tools/finta-ferma.test.sh;1 finta" 3/2
check "  --gruppo 3/2 (k > n) → exit 2, uso" '[ $rc -eq 2 ] && grep -q "^usage:" "$T/out"' "$(cat "$T/out")"
check "  il file vero: tools/suite-gruppi.list copre tools/suite.list (ogni suite in un gruppo solo, gruppi 1..3)" \
  '(cd "$ROOT" && G=$(grep -v "^[[:space:]]*\(#\|$\)" tools/suite-gruppi.list | tr -d "\r"); L=$(grep -v "^[[:space:]]*\(#\|$\)" tools/suite.list | tr -d "\r");
    [ "$(printf "%s\n" "$G" | awk "{print \$2}" | sort)" = "$(printf "%s\n" "$L" | sort)" ] && [ "$(printf "%s\n" "$G" | awk "{print \$1}" | sort -u | tr "\n" " ")" = "1 2 3 " ])'
check "  e tools/prova-breve-windows.list nomina solo voci di suite.list" \
  '(cd "$ROOT" && L=$(grep -v "^[[:space:]]*\(#\|$\)" tools/suite.list | tr -d "\r"); grep -v "^[[:space:]]*\(#\|$\)" tools/prova-breve-windows.list | tr -d "\r" |
    while read -r r; do printf "%s\n" "$L" | grep -qxF -- "${r##* }" || exit 1; done)'

# --- 7. (1.5.1) tools/suite-parallelo.sh on two fake clones (Linux: it needs flock) ---
#   a suite red only in parallel (it fails while the other group's suite holds a marker) is run again alone and passes
#   → «ROSSA SOLO IN PARALLELO», exit 0; a suite always red → «ROSSA ANCHE DA SOLA», exit 1; the lock held → exit 3.
#   Counterproof: the rerun removed (marker RILANCIO) → the first one stays red, no «ROSSA SOLO IN PARALLELO».
if command -v flock >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
  PAR=$ROOT/tools/suite-parallelo.sh
  pulisci; rm -f "$R"/plugins/maat/scripts/*.test.sh
  M=$T/marcatore; export FINTA_MARCATORE=$M
  printf '%s\n' '#!/usr/bin/env bash' 'touch "$FINTA_MARCATORE"; sleep 4; rm -f "$FINTA_MARCATORE"; echo "finta: tiene il marcatore"' > "$R/tools/finta-tiene.test.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'sleep 1; [ ! -e "$FINTA_MARCATORE" ] && echo "finta: libera" || { echo "finta: marcatore presente"; exit 1; }' > "$R/tools/finta-sola.test.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "finta: sempre rossa"; exit 1' > "$R/tools/finta-rossa.test.sh"
  P7=(tools/finta-tiene.test.sh tools/finta-sola.test.sh tools/finta-rossa.test.sh)
  printf '%s\n' "# finta" "${P7[@]}" > "$R/tools/suite.list"
  printf '%s\n' "# finta" "1 tools/finta-tiene.test.sh" "2 tools/finta-sola.test.sh" "2 tools/finta-rossa.test.sh" > "$R/tools/suite-gruppi.list"
  (cd "$R" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm finta &&
    git clone -q "$R" "$T/c1" && git clone -q "$R" "$T/c2") > /dev/null 2>&1
  apar() { rm -rf "$T/pe"; MAAT_LINUX_CLONI="$T/c1 $T/c2" MAAT_PARALLELO_FORZA=1 MAAT_PARALLELO_LOCK=$T/plock bash "${1:-$PAR}" "$T/pe" HEAD > "$T/out" 2>&1; rc=$?; }
  priga() { grep "^g[0-9] $1 " "$T/pe/riepilogo.txt" 2>/dev/null; }
  caso_par() { [ $rc -eq 1 ] && priga tools/finta-sola.test.sh | grep -q "rc=1 .*ROSSA SOLO IN PARALLELO (da sola rc=0" &&
    priga tools/finta-rossa.test.sh | grep -q "ROSSA ANCHE DA SOLA (rc=1" && priga tools/finta-tiene.test.sh | grep -q "^g1 .*rc=0" &&
    grep -q "rosse=1 · rosse-solo-in-parallelo=1" "$T/pe/riepilogo.txt" && grep -qx FINE "$T/pe/riepilogo.txt"; }
  apar
  check "7 parallelo: rossa solo in parallelo → rilanciata da sola e verde; sempre rossa → rossa anche da sola; exit 1" 'caso_par' "$(cat "$T/out")"
  check "  clone.txt: i due cloni allo stesso commit" '[ "$(grep -c "^clone [12]: " "$T/pe/clone.txt")" = 2 ]' "$(cat "$T/pe/clone.txt" 2>&1)"
  printf '%s\n' "# finta" "${P7[0]}" "${P7[1]}" > "$R/tools/suite.list"
  printf '%s\n' "# finta" "1 tools/finta-tiene.test.sh" "2 tools/finta-sola.test.sh" > "$R/tools/suite-gruppi.list"
  rm -f "$R/tools/finta-rossa.test.sh"; (cd "$R" && git add -A && git commit -qm "senza la rossa") > /dev/null 2>&1
  apar
  check "  senza la sempre rossa: exit 0, la rossa solo in parallelo contata verde ma segnalata" '[ $rc -eq 0 ] && priga tools/finta-sola.test.sh | grep -q "ROSSA SOLO IN PARALLELO" && grep -q "rosse=0 · rosse-solo-in-parallelo=1" "$T/pe/riepilogo.txt"' "$(cat "$T/out")"
  MAAT_LINUX_CLONI="$T/c1" MAAT_PARALLELO_FORZA=1 MAAT_PARALLELO_LOCK=$T/plock bash "$PAR" "$T/pe" HEAD > "$T/out" 2>&1; rc=$?
  check "  un clone per due gruppi → exit 2" '[ $rc -eq 2 ] && grep -q "1 clones for 2 groups" "$T/out"' "$(cat "$T/out")"
  ( flock 9; sleep 5 ) 9> "$T/plock" & lp=$!; sleep 1
  apar
  check "  il lock tenuto da un altro giro → exit 3 OCCUPATA, nessun gruppo partito" '[ $rc -eq 3 ] && grep -q OCCUPATA "$T/out" && [ ! -d "$T/pe/gruppo-1" ]' "$(cat "$T/out")"
  wait $lp
  cp "$PAR" "$T/par-mut.sh"; cp -r "$ROOT/tools/lib" "$T/lib"
  sed -i 's/^  elif \[ "\$rc" != 0 \]; then$/  elif false; then   # RILANCIO tolto/' "$T/par-mut.sh"
  check "controprova: la mutazione è applicata (nessun rilancio)" 'grep -q "RILANCIO tolto" "$T/par-mut.sh"'
  apar "$T/par-mut.sh"
  check "controprova: senza rilancio la rossa solo in parallelo non è riconosciuta (nessuna ROSSA SOLO IN PARALLELO)" '! grep -q "ROSSA SOLO IN PARALLELO" "$T/pe/riepilogo.txt" && priga tools/finta-sola.test.sh | grep -q "rc=1"' "$(cat "$T/out")"
  unset FINTA_MARCATORE
else
  echo "SALTATO: sezione 7 (tools/suite-parallelo.sh): flock o git assente (Linux)"
fi

echo "suite.test.sh: $pass passati, $fail falliti"
[ $fail -eq 0 ]
