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

echo "suite.test.sh: $pass passati, $fail falliti"
[ $fail -eq 0 ]
