#!/usr/bin/env bash
# suite.test.sh — tools/suite.sh (Maat 1.5.0, block 0): the tools/… entries of suite.list and the guard of the run.
# On a copy of the repo in a temporary folder (tools/ and plugins/maat/, the real suites removed), with fake suites:
#   1 a suite that changes a plugin file → its line says PLUGIN CAMBIATO, exit 1; the next suite (no change) does not
#   2 a suite that touches nothing → no PLUGIN CAMBIATO, exit 0 (a plain name, plugins/maat/scripts/<name>.test.sh, too)
#   3 a tools/x.test.sh not in the list → exit 2 · 4 a tools/… entry with no file → exit 2
#   5 counterproof: a guard that takes the fingerprint only once (before = after by construction) → case 1 green, red
#   6 (1.5.1) --gruppo <k>/<n>, and the link of .github/workflows/ci.yml with tools/suite-gruppi.list (n from the
#   matrix, matrix 1..n), with a counterproof · 7 (1.5.1) tools/suite-parallelo.sh
#   8 (1.6.0) --gruppi <file>: lines «- <entry> <reason>» (left out: counted as covered, ESCLUSA in riepilogo.txt, only
#   in group 1) and «<g> VAR=value <entry>»; the three matrices of ci.yml (linux and macos on tools/suite-gruppi.list,
#   windows on tools/suite-gruppi-windows.list), the Windows file against suite.list, with counterproofs; the five
#   entries left out on Windows, no «VAR=» line in the two groups files of the CI, the needs of the job ci; --gruppi
#   with every entry left out → exit 2
#   9 (1.8.0) MAAT_SUITE_TIMEOUT: a suite over the limit → rc=124, «TIMEOUT <entry> dopo <s> s» and the last lines of
#   its log, the next suite still runs; a «suite: avvio <entry>» line before each suite; after a red suite its «^FAIL»
#   lines (at most 10) on stdout and in riepilogo.txt; a value that is not a positive integer → exit 2; each job of
#   the groups in ci.yml sets MAAT_SUITE_TIMEOUT below its timeout-minutes × 60; counterproofs (the variable ignored,
#   a limit above the job's, a job without it)
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
check "  una suite della lista in nessun gruppo → exit 2, nessuna suite lanciata" '[ $rc -eq 2 ] && grep -q "finta is in 0 lines" "$T/out" && [ ! -f "$T/esiti/riepilogo.txt" ]' "$(cat "$T/out")"
corri_g "$L6" "1 tools/finta-ferma.test.sh;1 finta;2 finta" 2/2
check "  una suite in due gruppi → exit 2" '[ $rc -eq 2 ] && grep -q "finta is in 2 lines" "$T/out"' "$(cat "$T/out")"
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
# the link with the CI (review of 1.5.1; 1.6.0: one matrix job per platform): in the block of job $2 of ci.yml, n is
# strategy.job-total (never written by hand), k must be strategy.job-index + 1, the groups file is $3 (--gruppi, a
# path from the repo root), and the matrix is 1..n with n = the groups of that file (lines «-» are not groups).
# $1 = ci.yml
ci_blocco() { tr -d '\r' < "$1" | awk -v j="  $2:" '$0 == j { s = 1; next } s && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { s = 0 } s'; }
ci_legame() {
  local n m b
  b=$(ci_blocco "$1" "$2")
  n=$(grep -v '^[[:space:]]*\(#\|$\)' "$ROOT/$3" | tr -d '\r' | awk '$1 != "-" {print $1}' | sort -u | wc -l | tr -d ' ')
  m=$(printf '%s\n' "$b" | sed -n 's/^[[:space:]]*gruppo: \[\(.*\)\][[:space:]]*$/\1/p' | tr -d ' ')
  [ "$m" = "$(seq -s, 1 "$n")" ] &&
    [ "$(printf '%s\n' "$b" | grep -c -- "--gruppi $3 --gruppo \${{ matrix.gruppo }}/\${{ strategy.job-total }} ")" = 1 ] &&
    printf '%s\n' "$b" | grep -qF 'test "${{ matrix.gruppo }}" = "$(( ${{ strategy.job-index }} + 1 ))"' &&
    ! printf '%s\n' "$b" | grep -- '--gruppo ' | grep -v '^[[:space:]]*#' | grep -q -- '--gruppo [^$]*/[0-9]'
}
# no other job runs suite.sh --gruppo: the three above are all of them
ci_tre() { [ "$(tr -d '\r' < "$1" | grep -v '^[[:space:]]*#' | grep -c -- 'tools/suite.sh .*--gruppo ')" = 3 ]; }
CIY=$ROOT/.github/workflows/ci.yml
check "  il legame con la CI: per linux e macos (tools/suite-gruppi.list) e windows (tools/suite-gruppi-windows.list) n = strategy.job-total, k = job-index + 1, la matrice e' 1..n con n = i gruppi del file" \
  'ci_legame "$CIY" linux-gruppo tools/suite-gruppi.list && ci_legame "$CIY" macos-gruppo tools/suite-gruppi.list && ci_legame "$CIY" windows-gruppo tools/suite-gruppi-windows.list && ci_tre "$CIY"'
sed 's|/\${{ strategy.job-total }} esiti|/3 esiti|' "$CIY" > "$T/ci-3.yml"
sed 's|^\(        gruppo: \)\[1, 2, 3\]$|\1[1, 2]|' "$CIY" > "$T/ci-2.yml"
sed 's|--gruppi tools/suite-gruppi-windows.list|--gruppi tools/suite-gruppi.list|' "$CIY" > "$T/ci-w.yml"
sed 's|^\(        gruppo: \)\[\(1, 2, 3, 4[0-9, ]*\), [0-9]*\]$|\1[\2]|' "$CIY" > "$T/ci-w1.yml"
check "controprova: ci.yml con /3 scritto a mano, o con la matrice [1, 2] → il legame è rosso" \
  'grep -q -- "/3 esiti" "$T/ci-3.yml" && ! ci_legame "$T/ci-3.yml" linux-gruppo tools/suite-gruppi.list && grep -q "gruppo: \[1, 2\]$" "$T/ci-2.yml" && ! ci_legame "$T/ci-2.yml" linux-gruppo tools/suite-gruppi.list'
check "controprova: il job windows con il file di Linux, o con un gruppo in meno nella matrice → il legame è rosso" \
  '! cmp -s "$CIY" "$T/ci-w.yml" && ! ci_legame "$T/ci-w.yml" windows-gruppo tools/suite-gruppi-windows.list && ! cmp -s "$CIY" "$T/ci-w1.yml" && ! ci_legame "$T/ci-w1.yml" windows-gruppo tools/suite-gruppi-windows.list'
# the Windows file: every entry of suite.list in exactly one line (a group or «-»), groups 1..n. $1 = groups file
win_copre() {
  local G L
  G=$(grep -v '^[[:space:]]*\(#\|$\)' "$1" | tr -d '\r'); L=$(grep -v '^[[:space:]]*\(#\|$\)' "$ROOT/tools/suite.list" | tr -d '\r')
  [ "$(printf '%s\n' "$G" | awk '$1 == "-" { print $2; next } { print $NF }' | sort)" = "$(printf '%s\n' "$L" | sort)" ] &&
    [ "$(printf '%s\n' "$G" | awk '$1 != "-" { print $1 }' | sort -un | tr '\n' ' ')" = "$(seq -s ' ' 1 "$(printf '%s\n' "$G" | awk '$1 != "-" { print $1 }' | sort -u | wc -l)") " ]
}
check "  il file Windows copre tools/suite.list (ogni voce in una riga sola, gruppi 1..n)" 'win_copre "$ROOT/tools/suite-gruppi-windows.list"'
awk '!f && /^- / { f = 1; next } 1' "$ROOT/tools/suite-gruppi-windows.list" > "$T/w-senza.list"
awk '$1 == "1" { $1 = "9" } 1' "$ROOT/tools/suite-gruppi-windows.list" > "$T/w-buco.list"
check "controprova: senza la prima riga «-» il file Windows non copre suite.list; il gruppo 1 rinominato 9 → gruppi non 1..n" \
  '! cmp -s "$T/w-senza.list" "$ROOT/tools/suite-gruppi-windows.list" && ! win_copre "$T/w-senza.list" && ! cmp -s "$T/w-buco.list" "$ROOT/tools/suite-gruppi-windows.list" && ! win_copre "$T/w-buco.list"'
# the entries left out on Windows are exactly these five (review of the CI of 1.6.0). $1 = groups file
WIN_ESCLUSE="comandi-equivalenza counterproof test-fast tools/oracolo.test.sh vitest-classify "
win_escluse() { [ "$(grep -v '^[[:space:]]*\(#\|$\)' "$1" | tr -d '\r' | awk '$1 == "-" { print $2 }' | sort | tr '\n' ' ')" = "$WIN_ESCLUSE" ]; }
check "  il file Windows esclude esattamente le cinque voci attese ($WIN_ESCLUSE)" 'win_escluse "$ROOT/tools/suite-gruppi-windows.list"'
sed 's/^1 run-phase$/- run-phase motivo finto/' "$ROOT/tools/suite-gruppi-windows.list" > "$T/w-piu.list"
check "controprova: un'esclusa in piu' (run-phase), o una in meno (senza la prima riga «-») → rosso" \
  '! cmp -s "$T/w-piu.list" "$ROOT/tools/suite-gruppi-windows.list" && ! win_escluse "$T/w-piu.list" && ! win_escluse "$T/w-senza.list"'
# no «<g> VAR=value <entry>» line in the groups files of the CI: a variable there (MAAT_ATTESE_RICHIESTE, FIC_WT_WSL,
# PATH, BASH_ENV…) would change the environment of a suite in CI without a trace in ci.yml. $1 = groups file
senza_var() { ! grep -v '^[[:space:]]*\(#\|$\)' "$1" | tr -d '\r' | awk '$1 != "-" && (NF != 2 || $2 ~ /=/)' | grep -q .; }
check "  nessuna riga VAR= in tools/suite-gruppi.list e tools/suite-gruppi-windows.list (i file della CI)" \
  'senza_var "$ROOT/tools/suite-gruppi.list" && senza_var "$ROOT/tools/suite-gruppi-windows.list"'
awk '!f && $1 == "1" { $0 = "1 MAAT_ATTESE_RICHIESTE=0 " $2; f = 1 } 1' "$ROOT/tools/suite-gruppi.list" > "$T/g-var.list"
awk '!f && $1 == "2" { $0 = "2 PATH=/x " $2; f = 1 } 1' "$ROOT/tools/suite-gruppi-windows.list" > "$T/w-var.list"
check "controprova: una riga «1 MAAT_ATTESE_RICHIESTE=0 <voce>» nel file di Linux, o «2 PATH=/x <voce>» in quello Windows → rosso" \
  'grep -q "^1 MAAT_ATTESE_RICHIESTE=0 " "$T/g-var.list" && ! senza_var "$T/g-var.list" && grep -q "^2 PATH=/x " "$T/w-var.list" && ! senza_var "$T/w-var.list"'
# the job ci needs the three platforms and wants success from each. $1 = ci.yml
ci_needs() {
  local b p; b=$(ci_blocco "$1" ci)
  printf '%s\n' "$b" | grep -qx '    needs: \[linux, macos, windows\]' || return 1
  for p in linux macos windows; do
    printf '%s\n' "$b" | grep -v '^[[:space:]]*#' | grep -qF "test \"\${{ needs.$p.result }}\" = success" || return 1
  done
}
check "  il job ci: needs: [linux, macos, windows] e success richiesto a tutti e tre" 'ci_needs "$CIY"'
sed 's/^    needs: \[linux, macos, windows\]$/    needs: [linux, windows]/' "$CIY" > "$T/ci-n.yml"
sed 's/ && test "\${{ needs.macos.result }}" = success//' "$CIY" > "$T/ci-s.yml"
check "controprova: ci.yml senza macos nei needs, o senza il success di macos → rosso" \
  '! cmp -s "$CIY" "$T/ci-n.yml" && ! ci_needs "$T/ci-n.yml" && ! cmp -s "$CIY" "$T/ci-s.yml" && ! ci_needs "$T/ci-s.yml"'
check "  e tools/prova-breve-windows.list nomina solo voci di suite.list" \
  '(cd "$ROOT" && L=$(grep -v "^[[:space:]]*\(#\|$\)" tools/suite.list | tr -d "\r"); grep -v "^[[:space:]]*\(#\|$\)" tools/prova-breve-windows.list | tr -d "\r" |
    while read -r r; do printf "%s\n" "$L" | grep -qxF -- "${r##* }" || exit 1; done)'

# --- 8. (1.6.0) --gruppi <file>: entries left out («- <entry> <reason>») and «<g> VAR=value <entry>» ---
# $1 = list, $2 = groups file content (lines separated by ;), $3… = the arguments of suite.sh before the results dir
corri_f() {
  local l=$1 c=$2; shift 2
  printf '%s\n' "# finta" $l > "$R/tools/suite.list"
  printf '%s\n' "# finta" > "$T/gruppi-f.list"; local IFS=';'; printf '%s\n' $c >> "$T/gruppi-f.list"; unset IFS
  rm -rf "$T/esiti"; (cd "$R" && bash "$SUITE_SH" "$@" "$T/esiti") > "$T/out" 2>&1; rc=$?
}
pulisci; ferma; printf '%s\n' '#!/usr/bin/env bash' 'echo "finta: V=${FINTA_V:-nessuna}"' > "$R/plugins/maat/scripts/finta.test.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo "esclusa partita"; exit 1' > "$R/tools/finta-esclusa.test.sh"
L8="tools/finta-ferma.test.sh finta tools/finta-esclusa.test.sh"
F8="- tools/finta-esclusa.test.sh manca uno strumento;1 FINTA_V=ciao finta;2 tools/finta-ferma.test.sh"
corri_f "$L8" "$F8" --gruppi "$T/gruppi-f.list" --gruppo 1/2
check "8 --gruppi: la voce esclusa conta come coperta e non parte; il gruppo 1 la scrive ESCLUSA con il motivo; VAR=valore arriva alla suite" \
  '[ $rc -eq 0 ] && grep -qx "tools/finta-esclusa.test.sh ESCLUSA: manca uno strumento" "$T/esiti/riepilogo.txt" && ! grep -q "esclusa partita" "$T/esiti/"*.log && riga finta | grep -q "\[FINTA_V=ciao\] finta: V=ciao" && ! riga tools/finta-ferma.test.sh' "$(cat "$T/out")"
corri_f "$L8" "$F8" --gruppi "$T/gruppi-f.list" --gruppo 2/2
check "  il gruppo 2 non ripete le escluse, e senza VAR=valore la suite non la vede" \
  '[ $rc -eq 0 ] && ! grep -q ESCLUSA "$T/esiti/riepilogo.txt" && riga tools/finta-ferma.test.sh | grep -q "rc=0" && ! riga finta' "$(cat "$T/out")"
corri_f "$L8" "$F8" --gruppi "$T/gruppi-f.list"
check "  --gruppi senza --gruppo: tutte le voci non escluse, l'esclusa scritta" \
  '[ $rc -eq 0 ] && riga finta | grep -q "V=ciao" && riga tools/finta-ferma.test.sh | grep -q "rc=0" && grep -q "ESCLUSA" "$T/esiti/riepilogo.txt" && ! grep -q "esclusa partita" "$T/esiti/"*.log' "$(cat "$T/out")"
corri_f "$L8" "- tools/assente.test.sh motivo;$F8" --gruppi "$T/gruppi-f.list" --gruppo 1/2
check "  un'esclusa che non è in suite.list → exit 2, nessuna suite lanciata" \
  '[ $rc -eq 2 ] && grep -q "tools/assente.test.sh is not in suite.list" "$T/out" && [ ! -f "$T/esiti/riepilogo.txt" ]' "$(cat "$T/out")"
corri_f "$L8" "- finta;2 tools/finta-ferma.test.sh;1 tools/finta-esclusa.test.sh" --gruppi "$T/gruppi-f.list" --gruppo 1/2
check "  un'esclusa senza motivo → exit 2" '[ $rc -eq 2 ] && grep -q "bad line: - finta" "$T/out"' "$(cat "$T/out")"
corri_f "$L8" "$F8;1 tools/finta-esclusa.test.sh" --gruppi "$T/gruppi-f.list" --gruppo 1/2
check "  esclusa e anche in un gruppo → exit 2 (due righe)" '[ $rc -eq 2 ] && grep -q "tools/finta-esclusa.test.sh is in 2 lines" "$T/out"' "$(cat "$T/out")"
corri_f "$L8" "- tools/finta-esclusa.test.sh motivo;1 1V=x finta;2 tools/finta-ferma.test.sh" --gruppi "$T/gruppi-f.list" --gruppo 1/2
check "  una variabile che non è un nome → exit 2" '[ $rc -eq 2 ] && grep -q "bad line: 1 1V=x finta" "$T/out"' "$(cat "$T/out")"
corri_f "$L8" "$F8" --gruppi "$T/assente.list" --gruppo 1/2
check "  un file dei gruppi che non c'è → exit 2" '[ $rc -eq 2 ] && grep -q "assente.list: missing or empty" "$T/out"' "$(cat "$T/out")"
corri_f "$L8" "- tools/finta-esclusa.test.sh m;- finta m;- tools/finta-ferma.test.sh m" --gruppi "$T/gruppi-f.list"
check "  --gruppi senza --gruppo con tutte le voci escluse → exit 2, nessuna suite lanciata" \
  '[ $rc -eq 2 ] && grep -q "every entry is left out" "$T/out" && [ ! -f "$T/esiti/riepilogo.txt" ]' "$(cat "$T/out")"
rm -f "$R/tools/finta-esclusa.test.sh"

# --- 9. (1.8.0) MAAT_SUITE_TIMEOUT, the start line, the FAIL lines (C4 + C2) ---
dorme() { printf '%s\n' '#!/usr/bin/env bash' 'echo "finta: riga uno"; echo "finta: dormo"; sleep 8; echo "finta: sveglia"' > "$R/tools/finta-dorme.test.sh"; }
# $1 = how many «FAIL [n] …» lines the fake red suite prints
rossa() { printf '%s\n' '#!/usr/bin/env bash' "for i in \$(seq 1 $1); do echo \"FAIL [\$i] caso \$i\"; echo \"  dettaglio \$i\"; done; echo \"finta: $1 falliti\"; exit 1" > "$R/tools/finta-rossa.test.sh"; }
# rc, $T/out, $T/esiti. The cut is proven by the log (no «finta: sveglia»), not by a time: Git Bash is slow
corri_lim() { printf '%s\n' "# finta" $1 > "$R/tools/suite.list"
  rm -rf "$T/esiti"; (cd "$R" && MAAT_SUITE_TIMEOUT=2 bash "$SUITE_SH" "$T/esiti") > "$T/out" 2>&1; rc=$?; }
nriga() { grep -nx -- "$1" "$T/out" | head -1 | cut -d: -f1; }
caso_limite() {
  [ $rc -eq 1 ] && riga tools/finta-dorme.test.sh | grep -q "rc=124" && grep -q "finta: dormo" "$T/esiti/tools-finta-dorme.test.sh.log" &&
    ! grep -q "finta: sveglia" "$T/esiti/tools-finta-dorme.test.sh.log" &&
    grep -qx "TIMEOUT tools/finta-dorme.test.sh dopo 2 s" "$T/out" && grep -qx "TIMEOUT tools/finta-dorme.test.sh dopo 2 s" "$T/esiti/riepilogo.txt" &&
    grep -q "^ *| finta: riga uno$" "$T/out" && riga tools/finta-ferma.test.sh | grep -q "rc=0"
}
pulisci; ferma; dorme; corri_lim "tools/finta-dorme.test.sh tools/finta-ferma.test.sh"
check "9 MAAT_SUITE_TIMEOUT=2, una suite che dorme 8 s → rc=124, riga TIMEOUT (stdout e riepilogo) con le ultime righe del log; la suite dopo parte; exit 1" 'caso_limite' "$(cat "$T/out")"
check "  una riga «suite: avvio <voce>» su stdout prima di ogni suite, nell'ordine" \
  'a=$(nriga "suite: avvio tools/finta-dorme.test.sh"); b=$(nriga "suite: avvio tools/finta-ferma.test.sh"); f=$(grep -n "^tools/finta-dorme.test.sh .*rc=124" "$T/out" | head -1 | cut -d: -f1);
   [ -n "$a" ] && [ -n "$b" ] && [ -n "$f" ] && [ "$a" -lt "$f" ] && [ "$f" -lt "$b" ] && ! grep -q "suite: avvio" "$T/esiti/riepilogo.txt"' "$(cat "$T/out")"
pulisci; ferma; rossa 2; corri_lim "tools/finta-rossa.test.sh tools/finta-ferma.test.sh"
caso_fail() {
  [ $rc -eq 1 ] && [ "$(grep -c '^ *FAIL \[[12]\] caso [12]$' "$T/esiti/riepilogo.txt")" = 2 ] && [ "$(grep -c '^ *FAIL \[[12]\] caso [12]$' "$T/out")" = 2 ] &&
    ! grep -q dettaglio "$T/esiti/riepilogo.txt" && [ "$(grep -c FAIL "$T/esiti/riepilogo.txt")" = 2 ] &&
    [ "$(grep -n "^tools/finta-rossa.test.sh " "$T/esiti/riepilogo.txt" | cut -d: -f1)" -lt "$(grep -n 'FAIL \[1\]' "$T/esiti/riepilogo.txt" | cut -d: -f1)" ]
}
check "  una suite rossa che stampa due «FAIL [x]» → le due righe nel riepilogo, sotto la sua riga, e su stdout; la suite verde nessuna" 'caso_fail' "$(cat "$T/esiti/riepilogo.txt" 2>&1)"
pulisci; rossa 12; corri_lim "tools/finta-rossa.test.sh"
check "  dodici righe FAIL → al più 10 nel riepilogo" '[ $rc -eq 1 ] && [ "$(grep -c "FAIL \[" "$T/esiti/riepilogo.txt")" = 10 ]' "$(cat "$T/esiti/riepilogo.txt" 2>&1)"
pulisci; ferma; printf '%s\n' "# finta" tools/finta-ferma.test.sh > "$R/tools/suite.list"
for v in abc 0 -5 ""; do
  rm -rf "$T/esiti"; (cd "$R" && MAAT_SUITE_TIMEOUT=$v bash "$SUITE_SH" "$T/esiti") > "$T/out" 2>&1; rc=$?
  check "  MAAT_SUITE_TIMEOUT='$v' → exit 2, nessuna suite lanciata" '[ $rc -eq 2 ] && grep -q "MAAT_SUITE_TIMEOUT" "$T/out" && [ ! -f "$T/esiti/riepilogo.txt" ]' "$(cat "$T/out")"
done
# counterproof: the variable ignored (the fixed limit of 1.7) → the fake suite outlives the limit
cp "$SUITE_SH" "$T/suite.orig"
sed -i 's/^LIMITE=\${MAAT_SUITE_TIMEOUT-5400}$/LIMITE=5400   # LIMITE ignorato/' "$SUITE_SH"
check "controprova: la mutazione è applicata (MAAT_SUITE_TIMEOUT ignorato)" 'grep -q "LIMITE ignorato" "$SUITE_SH"'
pulisci; ferma; dorme; corri_lim "tools/finta-dorme.test.sh tools/finta-ferma.test.sh"
check "controprova: con il limite di default fisso la suite finta supera MAAT_SUITE_TIMEOUT=2 → il caso 9 è rosso" '! caso_limite && riga tools/finta-dorme.test.sh | grep -q "rc=0"' "$(cat "$T/out")"
cp "$T/suite.orig" "$SUITE_SH"
# the CI: in the block of each job of the groups, one MAAT_SUITE_TIMEOUT below timeout-minutes × 60. $1 = ci.yml, $2 = job
ci_limite() {
  local b m t
  b=$(ci_blocco "$1" "$2")
  m=$(printf '%s\n' "$b" | sed -n 's/^    timeout-minutes: \([0-9][0-9]*\)[[:space:]]*$/\1/p')
  t=$(printf '%s\n' "$b" | grep -v '^[[:space:]]*#' | sed -n 's/^[[:space:]]*MAAT_SUITE_TIMEOUT: "\{0,1\}\([0-9][0-9]*\)"\{0,1\}[[:space:]]*$/\1/p')
  [ "$(printf '%s' "$m" | grep -c .)" = 1 ] && [ "$(printf '%s' "$t" | grep -c .)" = 1 ] &&
    [ "$(printf '%s\n' "$b" | grep -v '^[[:space:]]*#' | grep -c MAAT_SUITE_TIMEOUT)" = 1 ] && [ "$t" -gt 0 ] && [ "$t" -lt $((m * 60)) ]
}
check "  ci.yml: linux, macos e windows (i job dei gruppi) impostano MAAT_SUITE_TIMEOUT minore di timeout-minutes × 60" \
  'ci_limite "$CIY" linux-gruppo && ci_limite "$CIY" macos-gruppo && ci_limite "$CIY" windows-gruppo'
awk '/^  linux-gruppo:$/ { s = 1 } /^  macos-gruppo:$/ { s = 0 } s && /MAAT_SUITE_TIMEOUT:/ { sub(/[0-9]+/, "1500") } 1' "$CIY" > "$T/ci-l.yml"
grep -v 'MAAT_SUITE_TIMEOUT: "1800"' "$CIY" > "$T/ci-wt.yml"
check "controprova: linux con MAAT_SUITE_TIMEOUT 1500 (= 25 × 60), o windows senza la variabile → rosso" \
  '! cmp -s "$CIY" "$T/ci-l.yml" && ! ci_limite "$T/ci-l.yml" linux-gruppo && ! cmp -s "$CIY" "$T/ci-wt.yml" && ! ci_limite "$T/ci-wt.yml" windows-gruppo'
rm -f "$R/tools/finta-dorme.test.sh" "$R/tools/finta-rossa.test.sh"

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
