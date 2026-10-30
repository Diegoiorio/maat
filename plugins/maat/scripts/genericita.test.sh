#!/usr/bin/env bash
# genericita.test.sh — R3.5 (pk04b-2, step 9): no name of the guide project in the plugin core.
#   1. grep -rniE <NOMI> over scripts/, skills/, agents/, hooks/, schemas/. profiles/ and examples/ are out by construction
#      (they are not among the searched paths); excluded are the test fixtures (*.test.sh, fixtures/ directories), which MUST be
#      able to use those names, and BY NAME, until pk07 (note 4 of the targeted review): scripts/vitest-classify.py and
#      scripts/corpus/. Any line found and not covered by a declared exception => FAIL with the list.
#      `.nuxt` is among the names (pk04b-2 decision: the generated-tsconfig requirement is tied to the module's
#      `preparati`).
#   2. grep -niE 'junitxml|--reporter=json' over counterproof.sh, plan-check.sh and gates.sh: the runner lines live
#      only in profiles and examples (step 4). In guard.py it is legitimate code (note 4): not searched there.
#   3. DECLARED EXCEPTIONS (below, with the reason): they cover ONLY the name `.nuxt` on specific lines; another name on the
#      same line is still a FAIL. An exception that no longer covers any line is a FAIL (the list stays honest).
#   4. Mutation counterproofs, here, on a copy of the searched paths: `apps/admin` in a comment of gates.sh =>
#      red; «Progetto Riservato» (with the space) in a comment of gates.sh => red; `--junitxml` in a comment of counterproof.sh => red; a name other than `.nuxt` on a line covered
#      by an exception (fic-mirror.sh) => red.
#   5. (pk09) repo DOCUMENTATION: docs/ (except docs/piani/, which is history), the README.md of the repo and of the plugin do not
#      name the guide project (DOC_NOMI). Declared exception: the real file names of the plugin (DOC_FILE_VERI),
#      removed before the comparison. The proper names of the guide project come from the local file .genericita-nomi (see NOMI).
#   6. (pk09) LINKS of the guide docs/GUIDA-FLUSSI.html: every internal href leads to an id of the page (#anchor) or to a
#      file that exists next to the guide; http(s):, mailto: and data: are not checked. Only grep and test -e.
#   7. (pk09) Counterproofs on a copy of docs/ and of the READMEs: «Progetto Riservato» in the guide => red; an href to a
#      non-existent file => red; a non-existent anchor => red; a reserved name in the README => red; copy
#      restored => green. Outside the repo (plugin installed in the cache, without docs/) 5-7 are SALTATI with a reason.
# The R11 reminder in the main-session skills (pk05) is already checked by guard.test.sh, a plugin suite.
#   bash plugins/maat/scripts/genericita.test.sh          (Git Bash or WSL)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(cd "$HERE/.." && pwd)
pass=0 fail=0
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/    /'; }

# Proper names of the guide project (name, hosts, services): they are NOT in the public repo. They are read, if present, from a
# local untracked file (one regex alternative per line, # for comments): MAAT_NOMI_RISERVATI, otherwise
# <repo>/.genericita-nomi. The fake name FINTO is always there: the counterproofs need it, so they stay meaningful without the local file.
FINTO='progetto[- ]riservato'
NR=${MAAT_NOMI_RISERVATI:-$(cd "$PLUGIN/../.." && pwd)/.genericita-nomi}
RIS=$([ -f "$NR" ] && tr -d '\r' < "$NR" | grep -vE '^[[:space:]]*(#|$)' | paste -sd'|' -)
NOMI="apps/admin|modules/(api|app)|build:admin|prisma|\\.nuxt|$FINTO${RIS:+|$RIS}"
RUNNER='junitxml|--reporter=json'
PERCORSI=(scripts skills agents hooks schemas)
NUCLEO_DIR='\.nuxt.*\.output|\.output.*\.nuxt'   # a list of the core's known directories (dependencies, generated, caches)
# file <TAB> regex of the covered line <TAB> reason
ECC=(
  "scripts/blocks-independent.py	.	adattatore framework nuxt-autoimport (passo 6: attivo solo se dichiarato in maat.json) e l'elenco dei percorsi generati che mettono la fase in serie"
  "schemas/maat-config.schema.json	nuxt-autoimport	descrizione dell'adattatore nuxt-autoimport del campo framework"
  "scripts/fic-mirror.sh	$NUCLEO_DIR	elenco unico delle esclusioni della copia (passo 4 del piano: node_modules, .nuxt, .output, …), impronta e semina"
  "scripts/test-fast.sh	$NUCLEO_DIR	cartelle escluse dal manifest e dalla rilevazione delle scritture: lo stesso elenco del nucleo"
  "scripts/counterproof.sh	$NUCLEO_DIR	cartelle escluse dalla ricerca dei .env*: lo stesso elenco del nucleo"
  "scripts/context-pack.sh	^SKIP = \\{	cartelle che il pacchetto di contesto non visita: lo stesso elenco del nucleo"
  "scripts/plan-check.sh	^SKIP = \\{	cartelle che plan-check.sh non visita: lo stesso elenco del nucleo"
  "scripts/maat-config.py	$NUCLEO_DIR	cartelle che il lettore salta (SALTA_DIR, ESCLUSE_ACCANTO): lo stesso elenco del nucleo"
)

cerca() { # $1 plugin root -> "file:line:text", files relative to the root
  (cd "$1" && grep -rniE "$NOMI" "${PERCORSI[@]}" --exclude='*.test.sh' --exclude-dir=fixtures \
     --exclude-dir=__pycache__ --exclude-dir=corpus --exclude=vitest-classify.py 2>/dev/null)
}
cerca_runner() { (cd "$1" && grep -HniE "$RUNNER" scripts/counterproof.sh scripts/plan-check.sh scripts/gates.sh 2>/dev/null); }
# $1 root -> stdout: the lines NOT covered; in "$W/usate" the index of each exception that covered a line
residui() {
  local h f testo e i ef er scusata
  : > "$W/usate"
  while IFS= read -r h; do
    f=${h%%:*}; testo=${h#*:}; testo=${testo#*:}
    scusata=0 i=0
    for e in "${ECC[@]}"; do
      IFS=$'\t' read -r ef er _ <<< "$e"
      if [ "$f" = "$ef" ] && printf '%s\n' "$testo" | grep -qE -- "$er" &&
         ! printf '%s\n' "$testo" | sed 's/\.[nN][uU][xX][tT]//g' | grep -qiE -- "$NOMI"; then
        scusata=1; echo "$i" >> "$W/usate"; break
      fi
      i=$((i + 1))
    done
    [ $scusata = 1 ] || printf '%s\n' "$h"
  done < <(cerca "$1")
}

# --- 1-3. the plugin as it is ---
res=$(residui "$PLUGIN")
[ -z "$res" ] && ok || ko "nomi del progetto guida nel nucleo, fuori dalle eccezioni dichiarate ($(printf '%s\n' "$res" | grep -c .) righe)" "$res"
coperte=$(grep -c . "$W/usate")
i=0
for e in "${ECC[@]}"; do
  grep -qx "$i" "$W/usate" && ok || ko "eccezione dichiarata che non copre piu' nessuna riga: ${e%%	*}" "$e"
  i=$((i + 1))
done
run=$(cerca_runner "$PLUGIN")
[ -z "$run" ] && ok || ko "righe dei runner (junitxml, --reporter=json) fuori dai profili" "$run"
echo "genericita: ${#ECC[@]} eccezioni dichiarate, $coperte righe coperte (solo il nome .nuxt)"

# --- 4. mutation counterproofs on a copy of the searched paths ---
C="$W/copia"; mkdir -p "$C"
for d in "${PERCORSI[@]}"; do cp -r "$PLUGIN/$d" "$C/$d"; done
muta() { # $1 relative file, $2 line appended at the end; then restores from the original
  cp "$PLUGIN/$1" "$C/$1"; printf '%s\n' "$2" >> "$C/$1"
}
muta scripts/gates.sh '# nota di prova: apps/admin'
[ -n "$(residui "$C")" ] && ok || ko "controprova: apps/admin in un commento di gates.sh non fa rosso"
cp "$PLUGIN/scripts/gates.sh" "$C/scripts/gates.sh"
# the name with just the space (nit of the pk04b-2 review): «progetto[- ]riservato», grep -i
muta scripts/gates.sh '# nota di prova: dal Progetto Riservato 0000000'
[ -n "$(residui "$C")" ] && ok || ko "controprova: «Progetto Riservato» (con lo spazio) in un commento di gates.sh non fa rosso"
cp "$PLUGIN/scripts/gates.sh" "$C/scripts/gates.sh"
muta scripts/counterproof.sh '# nota di prova: --junitxml=x.xml'
[ -n "$(cerca_runner "$C")" ] && ok || ko "controprova: --junitxml in un commento di counterproof.sh non fa rosso"
cp "$PLUGIN/scripts/counterproof.sh" "$C/scripts/counterproof.sh"
muta scripts/fic-mirror.sh '# nota di prova: (node_modules, .nuxt, .output, modules/api)'
r=$(residui "$C")
printf '%s\n' "$r" | grep -q 'fic-mirror.sh:.*modules/api' && ok || ko "controprova: un'eccezione copre anche un nome diverso da .nuxt sulla stessa riga" "$r"
cp "$PLUGIN/scripts/fic-mirror.sh" "$C/scripts/fic-mirror.sh"
[ -z "$(residui "$C")" ] && ok || ko "copia ripristinata: dovrebbe tornare verde" "$(residui "$C")"

# --- 5-7. repo documentation and guide links (pk09) ---
REPO=$(cd "$PLUGIN/../.." && pwd)
DOC_NOMI="apps/admin|modules/(api|app)|prisma|$FINTO${RIS:+|$RIS}"
DOC_FILE_VERI='guard-esempio\.cases|nuxt-fastapi\.maat\.json'
GUIDA=docs/GUIDA-FLUSSI.html
doc_file() { # $1 repo root -> the documentation files, relative
  (cd "$1" && { find docs -path docs/piani -prune -o -type f \( -name '*.md' -o -name '*.html' \) -print; \
     ls README.md plugins/maat/README.md 2>/dev/null; } | LC_ALL=C sort)
}
doc_residui() { # $1 repo root -> the lines that name the guide project outside the exceptions
  local f h testo
  while IFS= read -r f; do
    while IFS= read -r h; do
      testo=$(printf '%s\n' "${h#*:}" | sed -E "s/$DOC_FILE_VERI//g")
      printf '%s\n' "$testo" | grep -qiE -- "$DOC_NOMI" || continue
      printf '%s:%s\n' "$f" "$h"
    done < <(grep -niE -- "$DOC_NOMI" "$1/$f")
  done < <(doc_file "$1")
}
href_rotti() { # $1 repo root -> the internal hrefs of the guide that lead nowhere
  local g="$1/$GUIDA" d h p
  d=$(dirname "$g")
  [ -f "$g" ] || { echo "guida assente: $GUIDA"; return; }
  while IFS= read -r h; do
    case "$h" in
      http:*|https:*|mailto:*|data:*) continue ;;
      '#'*) grep -qF "id=\"${h#\#}\"" "$g" || echo "ancora inesistente: $h" ;;
      *) p=${h%%#*}; p=${p%%\?*}; [ -e "$d/$p" ] || echo "file inesistente: $h" ;;
    esac
  done < <(grep -oE 'href="[^"]*"' "$g" | sed -E 's/^href="//; s/"$//')
}
if [ -d "$REPO/docs" ] && [ -f "$REPO/.claude-plugin/marketplace.json" ]; then
  r=$(doc_residui "$REPO")
  [ -z "$r" ] && ok || ko "documentazione: nomi del progetto guida fuori dalle eccezioni ($(printf '%s\n' "$r" | grep -c .) righe)" "$r"
  r=$(href_rotti "$REPO")
  [ -z "$r" ] && ok || ko "guida: href interni che non portano a niente" "$r"
  n=$(grep -oE 'href="[^"]*"' "$REPO/$GUIDA" | grep -vcE 'href="(https?:|mailto:|data:)')
  echo "genericita: documentazione $(doc_file "$REPO" | grep -c .) file, guida $n href interni"
  # counterproofs on a copy
  D="$W/repo"; mkdir -p "$D/plugins/maat"
  cp -r "$REPO/docs" "$D/docs"; cp "$REPO/README.md" "$D/README.md"; cp "$REPO/plugins/maat/README.md" "$D/plugins/maat/README.md"
  ripristina() { cp "$REPO/$GUIDA" "$D/$GUIDA"; cp "$REPO/README.md" "$D/README.md"; }
  printf '%s\n' '<p>nota di prova: Progetto Riservato</p>' >> "$D/$GUIDA"
  [ -n "$(doc_residui "$D")" ] && ok || ko "controprova: «Progetto Riservato» nella guida non fa rosso"
  ripristina
  printf '%s\n' '<a href="manca-di-prova.html">x</a>' >> "$D/$GUIDA"
  printf '%s\n' "$(href_rotti "$D")" | grep -q 'file inesistente: manca-di-prova.html' && ok \
    || ko "controprova: un href verso un file inesistente non fa rosso" "$(href_rotti "$D")"
  ripristina
  printf '%s\n' '<a href="#ancora-di-prova">x</a>' >> "$D/$GUIDA"
  printf '%s\n' "$(href_rotti "$D")" | grep -q 'ancora inesistente: #ancora-di-prova' && ok \
    || ko "controprova: un'ancora inesistente non fa rosso" "$(href_rotti "$D")"
  ripristina
  printf '%s\n' '- Progetto guida: Progetto Riservato (riga di prova)' >> "$D/README.md"
  [ -n "$(doc_residui "$D")" ] && ok || ko "controprova: un nome riservato nel README non fa rosso"
  ripristina
  [ -z "$(doc_residui "$D")$(href_rotti "$D")" ] && ok || ko "copia della documentazione ripristinata: dovrebbe tornare verde" "$(doc_residui "$D")$(href_rotti "$D")"
else
  echo "SALTATO [documentazione e link]: $REPO non e' il repo maat (manca docs/ o .claude-plugin/marketplace.json)"
fi

echo "genericita.test.sh: $pass ok, $fail falliti"
[ $fail -eq 0 ]
