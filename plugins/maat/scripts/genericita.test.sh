#!/usr/bin/env bash
# genericita.test.sh — R3.5 (pk04b-2, passo 9): nel nucleo del plugin nessun nome del progetto guida.
#   1. grep -rniE <NOMI> su scripts/, skills/, agents/, hooks/, schemas/. Fuori per costruzione profiles/ ed examples/
#      (non sono fra i percorsi cercati); esclusi le fixture dei test (*.test.sh, cartelle fixtures/), che DEVONO poter
#      usare quei nomi, e PER NOME, fino a pk07 (nota 4 della revisione mirata): scripts/vitest-classify.py e
#      scripts/corpus/. Qualunque riga trovata e non coperta da un'eccezione dichiarata => FAIL con l'elenco.
#      `.nuxt` e' fra i nomi (decisione di pk04b-2: il requisito del tsconfig generato e' legato ai `preparati`
#      del modulo).
#   2. grep -niE 'junitxml|--reporter=json' su counterproof.sh, plan-check.sh e gates.sh: le righe dei runner stanno
#      solo nei profili e negli esempi (passo 4). In guard.py e' codice legittimo (nota 4): non si cerca li'.
#   3. ECCEZIONI DICHIARATE (sotto, con il motivo): coprono SOLO il nome `.nuxt` su righe precise; un altro nome sulla
#      stessa riga resta un FAIL. Un'eccezione che non copre piu' nessuna riga e' un FAIL (l'elenco resta onesto).
#   4. Controprove per mutazione, qui, su una copia dei percorsi cercati: `apps/admin` in un commento di gates.sh =>
#      rosso; «Progetto Riservato» (con lo spazio) in un commento di gates.sh => rosso; `--junitxml` in un commento di counterproof.sh => rosso; un nome diverso da `.nuxt` su una riga coperta
#      da un'eccezione (fic-mirror.sh) => rosso.
#   5. (pk09) DOCUMENTAZIONE del repo: docs/ (tranne docs/piani/, che e' storia), README.md del repo e del plugin non
#      nominano il progetto guida (DOC_NOMI). Eccezione dichiarata: i nomi di file veri del plugin (DOC_FILE_VERI),
#      tolti prima del confronto. I nomi propri del progetto guida vengono dal file locale .genericita-nomi (vedi NOMI).
#   6. (pk09) LINK della guida docs/GUIDA-FLUSSI.html: ogni href interno porta a un id della pagina (#ancora) o a un
#      file che esiste accanto alla guida; http(s):, mailto: e data: non si controllano. Solo grep e test -e.
#   7. (pk09) Controprove su una copia di docs/ e dei README: «Progetto Riservato» nella guida => rosso; un href verso un
#      file inesistente => rosso; un'ancora inesistente => rosso; un nome riservato nel README => rosso; copia
#      ripristinata => verde. Fuori dal repo (plugin installato in cache, senza docs/) 5-7 sono SALTATI con motivo.
# Il richiamo R11 nelle skill della sessione principale (pk05) lo verifica gia' guard.test.sh, suite del plugin.
#   bash plugins/maat/scripts/genericita.test.sh          (Git Bash o WSL)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(cd "$HERE/.." && pwd)
pass=0 fail=0
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/    /'; }

# Nomi propri del progetto guida (nome, host, servizi): NON stanno nel repo pubblico. Si leggono, se c'e', da un file
# locale non tracciato (una alternativa regex per riga, # per i commenti): MAAT_NOMI_RISERVATI, altrimenti
# <repo>/.genericita-nomi. Il nome finto FINTO c'e' sempre: serve alle controprove, che senza il file locale restano vere.
FINTO='progetto[- ]riservato'
NR=${MAAT_NOMI_RISERVATI:-$(cd "$PLUGIN/../.." && pwd)/.genericita-nomi}
RIS=$([ -f "$NR" ] && tr -d '\r' < "$NR" | grep -vE '^[[:space:]]*(#|$)' | paste -sd'|' -)
NOMI="apps/admin|modules/(api|app)|build:admin|prisma|\\.nuxt|$FINTO${RIS:+|$RIS}"
RUNNER='junitxml|--reporter=json'
PERCORSI=(scripts skills agents hooks schemas)
NUCLEO_DIR='\.nuxt.*\.output|\.output.*\.nuxt'   # un elenco del nucleo delle cartelle note (dipendenze, generati, cache)
# file <TAB> regex della riga coperta <TAB> motivo
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

cerca() { # $1 radice del plugin -> "file:riga:testo", file relativi alla radice
  (cd "$1" && grep -rniE "$NOMI" "${PERCORSI[@]}" --exclude='*.test.sh' --exclude-dir=fixtures \
     --exclude-dir=__pycache__ --exclude-dir=corpus --exclude=vitest-classify.py 2>/dev/null)
}
cerca_runner() { (cd "$1" && grep -HniE "$RUNNER" scripts/counterproof.sh scripts/plan-check.sh scripts/gates.sh 2>/dev/null); }
# $1 radice -> stdout: le righe NON coperte; in "$W/usate" l'indice di ogni eccezione che ha coperto una riga
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

# --- 1-3. il plugin com'e' ---
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

# --- 4. controprove per mutazione su una copia dei percorsi cercati ---
C="$W/copia"; mkdir -p "$C"
for d in "${PERCORSI[@]}"; do cp -r "$PLUGIN/$d" "$C/$d"; done
muta() { # $1 file relativo, $2 riga aggiunta in fondo; poi ripristina dall'originale
  cp "$PLUGIN/$1" "$C/$1"; printf '%s\n' "$2" >> "$C/$1"
}
muta scripts/gates.sh '# nota di prova: apps/admin'
[ -n "$(residui "$C")" ] && ok || ko "controprova: apps/admin in un commento di gates.sh non fa rosso"
cp "$PLUGIN/scripts/gates.sh" "$C/scripts/gates.sh"
# il nome col solo spazio (nit della review pk04b-2): «progetto[- ]riservato», grep -i
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

# --- 5-7. documentazione del repo e link della guida (pk09) ---
REPO=$(cd "$PLUGIN/../.." && pwd)
DOC_NOMI="apps/admin|modules/(api|app)|prisma|$FINTO${RIS:+|$RIS}"
DOC_FILE_VERI='guard-esempio\.cases|nuxt-fastapi\.maat\.json'
GUIDA=docs/GUIDA-FLUSSI.html
doc_file() { # $1 radice del repo -> i file di documentazione, relativi
  (cd "$1" && { find docs -path docs/piani -prune -o -type f \( -name '*.md' -o -name '*.html' \) -print; \
     ls README.md plugins/maat/README.md 2>/dev/null; } | LC_ALL=C sort)
}
doc_residui() { # $1 radice del repo -> le righe che nominano il progetto guida fuori dalle eccezioni
  local f h testo
  while IFS= read -r f; do
    while IFS= read -r h; do
      testo=$(printf '%s\n' "${h#*:}" | sed -E "s/$DOC_FILE_VERI//g")
      printf '%s\n' "$testo" | grep -qiE -- "$DOC_NOMI" || continue
      printf '%s:%s\n' "$f" "$h"
    done < <(grep -niE -- "$DOC_NOMI" "$1/$f")
  done < <(doc_file "$1")
}
href_rotti() { # $1 radice del repo -> gli href interni della guida che non portano a niente
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
  # controprove su una copia
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
