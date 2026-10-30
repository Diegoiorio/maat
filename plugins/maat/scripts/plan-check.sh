#!/usr/bin/env bash
# plan-check.sh — controlli DETERMINISTICI del ciclo /plan-review-cycle.
#
# Porta in un controllo meccanico cio' che la skill altrimenti affida al giudizio dell'orchestratore
# (che e' lo stesso che ha appena scritto il piano). Non giudica il contenuto del piano: solo
# struttura, confini e differenze.
#
#   plan-check.sh delta        <baseline> <corrente>      range cambiati + xref, per il giro delta
#   plan-check.sh lint         <spec> [--baseline <copia>] struttura della sezione del piano
#   plan-check.sh contract     <spec>                      contratto di verifica, per /implementation-review-cycle
#   plan-check.sh basis        <spec>                      l'approvazione e' ancora quella di questa spec e di questo piano?
#   plan-check.sh lint2        <spec>                      struttura del piano in FORMATO 2 (Plan format: 2)
#   plan-check.sh gen          <spec> [--run-dir <dir>]    procedura generata dal piano in formato 2 (comandi, mutations.json)
#   plan-check.sh route        <spec> [--diff <file>]      L5: superfici rilevate dai file, percorso leggero o pieno
#   plan-check.sh s2           <spec> --delta <f> --gate <f> [--respinti <n>]   S2: delta e occhi freschi puliti?
#   plan-check.sh skeleton     <spec>                      scheletro (passi, file, superfici, righe) sotto o sopra il tetto
#   plan-check.sh split        <madre> [<figlia>…]         partizione dei requisiti fra le figlie di una catena
#   plan-check.sh closed       <spec>                      l'anello e' chiuso? (Finalize: IMPLEMENTED fresca) · uscita 0|1
#   plan-check.sh basis        <spec> --write-tests        (formato 2) registra "tests <fp>" nell'Approved basis
#   plan-check.sh accept|tests|stubs|rossi|l2 <spec> …     fase test-red e L2 (harness-pt11, sotto: cmd_f2x)
#
# Uscita: 0 = ok · 1 = VIOLAZIONE (o, per delta, ERRORE DURO) · 2 = errore d'uso.
# Gli AVVISO sono stampati ma non cambiano l'uscita.
#
# FORMATO 2 — riga "Plan format: 2" sotto "## Piano di implementazione" (definito in SKILL.md, "Plan format 2").
# Senza la riga il piano e' in formato 1: lint, delta, contract e basis si comportano come prima, byte per byte;
# lint2 e gen rispondono "non si applica" con uscita 0. lint2, gen e route leggono le tabelle con Python
# (python.sh del full cycle), sulle righe di annotate: stesso confine del piano, stessi recinti.
#   lint2  VIOLAZIONE: requisito della tracciabilita' senza test · test fuori da un passo · file di un passo fuori
#          da "### File toccati" · blocco senza scrive: · tabella dei test o mutazione malformata · rischio aperto
#          senza test · stringa/data-test tolti ma ancora asseriti da un test che il piano non tocca · riga del
#          piano di test con asserzione "resta verde" (test esistente di non-regressione: va nella nota sotto la
#          tabella, la tracciabilita' scrive "non verificabile a test (invarianza, ...)").
#   gen    scrive <run-dir>/gen/procedura.txt (righe "chiave: valore": Plan format, Impronta piano, Test level,
#          vitest, pytest, altri, cmd vitest|pytest|lint|counterproof, mutazioni, "blocco <id>: scrive=… · dopo=…")
#          e <run-dir>/counterproof/mutations.json nel formato di script/test/counterproof.sh (tolto se nessuna
#          riga ha una mutazione). <run-dir> di default: <spec senza .md>.run. Uscita 1 su riga malformata.
#   route  stampa le superfici rilevate (percorsi + parole chiave distruttive nel piano e nel --diff), quelle
#          dichiarate e "Percorso: leggero|pieno — <motivo>"; uscita 0 (e' una risposta).
#   s2     legge le due risposte (prima riga "Impronta piano: <fp12>", poi il contratto del revisore) e stampa
#          "S2: APPROVA | CORREGGI | RILANCIA | IMPRONTA DIVERSA | STOP — <motivo>"; uscita 0.
#
# SPEZZAMENTO E CATENE (harness-pt12, L6):
#   skeleton  (formato 2; formato 1: "non si applica", uscita 0) conta i passi di "### Passi", i file (File
#          toccati + file dei passi), le superfici dichiarate e le righe del piano; stampa "Scheletro: SOTTO IL
#          TETTO" (uscita 0) o "Scheletro: SOPRA IL TETTO — <cosa>" (uscita 1: proposta di taglio, nessuna deroga).
#          Tetti: <=15 passi, <=40 file (lo scheletro) e <=400 righe (il piano completo, stesso comando).
#          La decisione dell'utente di NON spezzare sta nella spec, sopra il piano: "Taglio: rifiutato — <data>";
#          con quella riga lo scheletro sopra il tetto lo dice e la riporta, ma esce 0 (piano unico, nessuno stop).
#   split     ogni ID (RF<n>, CA<n>, anche puntato: RF5.4) DEFINITO dalla madre nelle sezioni "Requisiti funzionali"
#          e "Criteri di accettazione" (a inizio di un titolo, di una voce di elenco o di una riga di tabella) sta in
#          UNA e una sola figlia; nessuna figlia ha ID che la madre non ha; ogni figlia ha "Dipende da:" e
#          "Interfaccia per:" (sopra il piano, a inizio riga). Figlie: dagli argomenti, in ordine di catena, oppure
#          dalla riga "Figlie:" della madre. Uscita 1 = VIOLAZIONE (STOP).
#   basis di una FIGLIA (una spec della stessa cartella la elenca nella sua riga "Figlie:"): la Basis aggiunge
#          "madre <fp>" (le sezioni della madre sopra il piano), per l'anello k>1 "prec <fp>" (spec e piano
#          dell'anello k-1) e, a k-1 chiuso (plan-check.sh closed), "interfaccia
#          <fp>" (i file in backtick della sua riga "Interfaccia per:" nel suo ultimo .post-tree; chiuso = come
#          `closed`: Finalize: IMPLEMENTED fresca, nessun ripiego legacy). STALE se uno dei
#          campi registrati e' cambiato; STALE (madre|prec) se la Basis attuale ha il campo e la registrata no;
#          a k-1 chiuso e senza "interfaccia" registrata (piano approvato mentre k-1 implementava: L6), STALE
#          (touched: <file>) se QUALUNQUE file citato dal piano (fra backtick, :riga e ::nome tolti) sta nel
#          touched.txt di k-1: si fa il giro delta a k-1 chiuso. Una spec fuori da una catena: Basis invariata.
# Radice del repository: PLAN_CHECK_ROOT, altrimenti git della cartella della spec, altrimenti la cartella corrente.
#
# Invarianti (vedi SKILL.md e la memoria sulle trappole dei gate su markdown):
# - i file spec sono CRLF: ogni lettura toglie i \r, e diff usa --strip-trailing-cr;
# - la sezione del piano va da "## Piano di implementazione" a "## Review implementazione" o a fine
#   file: una H2 dentro il piano NON la chiude (succede, es. spec-restyling-ui-soft);
# - tutto cio' che sta dentro un blocco di codice (``` o ~~~) non conta come struttura.
#
# Test: plan-check.test.sh (ogni controllo ha la sua controprova rossa).

set -uo pipefail
set -f

# Vocabolario unico delle superfici a rischio (definito in SKILL.md, Step 0). CRITICHE = quelle che
# attivano il pavimento di verifica e, se il round 1 approva subito, il gate fresh-eyes.
SURFACES="permessi dati contratto-api import logica-condivisa distruttiva"
CRITICAL="permessi dati distruttiva"
# Token fra backtick troppo generici per fare da riferimento incrociato.
XREF_STOP=" std full min true false none null APPROVED DRAFT legacy TODO nessuna "
XREF_MAX_LINES=8
XREF_MAX_HITS=15   # un token che compare in piu' righe di cosi' e' rumore, non un riferimento

die_usage() { echo "uso: $0 delta <baseline> <corrente> | lint <spec> [--baseline <copia>] | contract <spec> | basis <spec> | lint2 <spec> | gen <spec> [--run-dir <dir>] | route <spec> [--diff <file>] | s2 <spec> --delta <file> --gate <file> [--respinti <n>] | skeleton <spec> | split <madre> [<figlia>…] | closed <spec> | basis <spec> --write-tests | accept|tests|l2 <spec> [--run-dir <dir>] | stubs <spec> [--run-dir <dir>] | rossi <spec> --evidence <dir> [--run-dir <dir>]" >&2; exit 2; }

# annotate FILE → righe "NR<TAB>zona<TAB>infence<TAB>testo"
# zona: above | plan | changelog | review. infence=1 anche sulle righe-recinto stesse.
annotate() {
  tr -d '\r' < "$1" | awk '
    BEGIN { zone = "above"; infence = 0 }
    {
      line = $0
      isfence = (line ~ /^[ \t]*(```|~~~)/)
      if (!infence && !isfence) {
        if (zone == "above" && line ~ /^## Piano di implementazione/) zone = "plan"
        else if ((zone == "plan" || zone == "changelog") && line ~ /^## Review implementazione/) zone = "review"
        else if (zone == "plan" && line ~ /^###[ \t]+([0-9]+\.[ \t]*)?Changelog revisione piano/) zone = "changelog"
        else if (zone == "changelog" && line ~ /^##?#?[ \t]/) zone = "plan"
      }
      fl = infence
      if (isfence) { infence = !infence; fl = 1 }
      printf "%d\t%s\t%d\t%s\n", NR, zone, fl, line
    }'
}

# above_norm: toglie gli spazi a fine riga e le righe vuote in coda (stdin → stdout).
above_norm() { sed 's/[[:space:]]*$//' | awk 'NF { for (i = 0; i < b; i++) print ""; b = 0; print; next } { b++ }'; }

# test_zone: stampa "NR<TAB>testo" delle righe di "### Piano di test" (fuori recinti), dall'annotate su stdin.
test_zone() {
  awk -F'\t' '
    $2 != "plan" { if (in_t) exit; next }
    $3 == 0 && $4 ~ /^###[ \t]+([0-9]+\.[ \t]*)?Piano di test/ { in_t = 1; next }
    in_t && $3 == 0 && $4 ~ /^##?#?[ \t]/ { exit }
    in_t { print $1 "\t" $4 }'
}
# Una riga di pavimento e' una VOCE DI ELENCO dentro "### Piano di test": una menzione in prosa
# altrove ("coperto dal [pavimento: permessi] sotto") non e' una seconda riga di pavimento.
PAV_RE='^[ \t]*([-*]|[0-9]+\.)[ \t]+\[pavimento:'
# Una riga [e2e-locator: <spec>] e' l'e2e mirato che il piano prescrive A OGNI LIVELLO quando cambia uno
# spec e2e o una stringa/classe/attributo usata dai suoi locator: fuori dai tetti come il pavimento.
E2E_RE='^[ \t]*([-*]|[0-9]+\.)[ \t]+\[e2e-locator:'

# warn_line <token>: "NR<TAB>testo" della prima riga "⚠️ Superficie <token>" del piano, fuori dai
# recinti (annotate su stdin). Il token deve seguire "⚠️ Superficie" (tollerati `, * e _ del markdown):
# una riga ⚠️ su un'ALTRA superficie non copre questa.
warn_line() {
  awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "⚠️ Superficie") { print $1 "\t" $4 }' \
    | grep -E "⚠️ Superficie[[:space:]*_\`]+$1([^[:alnum:]_-]|\$)" | head -1 || true
}
# waiver_of <testo della riga ⚠️>: il motivo della deroga "statica sufficiente: <motivo>", o vuoto.
waiver_of() { printf '%s\n' "$1" | sed -n 's/.*statica sufficiente:[[:space:]]*//p' | sed 's/[[:space:]]*$//'; }
# declared_surfaces: i token validi di "Superfici a rischio:" (annotate su stdin), separati da spazi.
declared_surfaces() {
  local d s out=""
  d=$(awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "Superfici a rischio:") == 1 { sub(/^Superfici a rischio:[ \t]*/, "", $4); print $4; exit }')
  for s in $(printf '%s' "$d" | tr -d '`' | tr ',·;' '   ' | tr -s ' '); do
    case " $SURFACES " in *" $s "*) out="$out $s" ;; esac
  done
  printf '%s\n' "$out"
}
# section_range <nome H3>: "offset=N limit=M" della sottosezione del piano (annotate su stdin).
section_range() {
  awk -F'\t' -v name="$1" '
    $2 != "plan" { if (s) exit; next }
    !s && $3 == 0 && $4 ~ ("^###[ \t]+([0-9]+\\.[ \t]*)?" name) { s = $1; last = $1; next }
    s && $3 == 0 && $4 ~ /^##?#?[ \t]/ { exit }
    s { last = $1 }
    END { if (s) printf "offset=%d limit=%d\n", s, last - s + 1 }'
}
# fmt2_of: 1 se il piano (annotate su stdin) ha la riga "Plan format: 2" fuori dai recinti, altrimenti 0.
fmt2_of() { awk -F'\t' '$2 == "plan" && $3 == 0 && $4 ~ /^Plan format:[ \t]*2[ \t]*$/ { f = 1 } END { print f ? 1 : 0 }'; }

# ─────────────────────────────────────────────────────────────────────────── delta
cmd_delta() {
  [ $# -eq 2 ] || die_usage
  local base="$1" cur="$2"
  if [ ! -s "$base" ]; then echo "ERRORE DURO: baseline assente o vuota ($base) — rifai il giro a scope pieno, mai APPROVED"; return 1; fi
  [ -f "$cur" ] || { echo "file corrente assente: $cur" >&2; return 2; }

  local d; d=$(diff --strip-trailing-cr "$base" "$cur")
  if [ -z "$d" ]; then echo "ERRORE DURO: diff vuoto — nessuna revisione registrata, oppure baseline presa dopo l'Edit. Rifai il giro a scope pieno, mai APPROVED"; return 1; fi

  local ann; ann=$(annotate "$cur")
  local total_new total_old
  total_new=$(printf '%s\n' "$ann" | wc -l)
  total_old=$(tr -d '\r' < "$base" | wc -l)

  # Hunk → range sul file corrente (1-based). Una cancellazione pura diventa la riga dopo cui cadeva.
  printf '%s\n' "$d" | awk -v tn="$total_new" -v to="$total_old" '
    /^[0-9]+(,[0-9]+)?[acd][0-9]+(,[0-9]+)?$/ {
      match($0, /[acd]/); op = substr($0, RSTART, 1)
      split(substr($0, 1, RSTART - 1), o, ","); split(substr($0, RSTART + 1), n, ",")
      os = o[1]; oe = (2 in o) ? o[2] : o[1]
      ns = n[1]; ne = (2 in n) ? n[2] : n[1]
      if (op == "d") { chold += oe - os + 1; s = (ns < 1 ? 1 : ns); e = s + 1 }
      else { if (op == "c") chold += oe - os + 1; chnew += ne - ns + 1; s = ns; e = ne }
      s -= 2; e += 2; if (s < 1) s = 1; if (e > tn) e = tn
      rs[++k] = s; re[k] = e
    }
    END {
      if ((tn > 20 && chnew > 0.9 * tn) || (to > 20 && chold > 0.9 * to)) {
        print "ERRORE DURO: il diff copre oltre il 90% del file (riformattazione o fine riga) — trattalo come baseline mancante: giro a scope pieno"
        exit 1
      }
      # fonde range vicini (distanza <= 3) per non spendere chiamate del revisore
      for (i = 1; i <= k; i++) {
        if (m && rs[i] <= me + 3) { if (re[i] > me) me = re[i]; continue }
        if (m) printf "range: offset=%d limit=%d\n", ms, me - ms + 1
        ms = rs[i]; me = re[i]; m = 1
      }
      if (m) printf "range: offset=%d limit=%d\n", ms, me - ms + 1
    }' > "$TMPD/ranges" || { cat "$TMPD/ranges"; return 1; }
  cat "$TMPD/ranges"

  # xref: token fra backtick delle righe cambiate, cercati nelle ALTRE righe del piano.
  awk '{ split($2, a, "="); split($3, b, "="); for (i = a[2]; i < a[2] + b[2]; i++) print i }' "$TMPD/ranges" | sort -un > "$TMPD/inrange"
  printf '%s\n' "$ann" | awk -F'\t' 'NR==FNR { r[$1] = 1; next } ($1 in r) { print $4 }' "$TMPD/inrange" - \
    | grep -o '`[^`]*`' | tr -d '`' | sort -u > "$TMPD/tokens" || true

  : > "$TMPD/cand"
  local tok hits
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    [ ${#tok} -le 60 ] || continue
    case "$XREF_STOP" in *" $tok "*) continue ;; esac
    if ! printf '%s' "$tok" | grep -q '[/._(:]' && ! printf '%s' "$tok" | grep -q '[a-z][A-Z]' && [ ${#tok} -lt 6 ]; then continue; fi
    printf '%s\n' "$ann" | awk -F'\t' -v t="$tok" 'NR==FNR { r[$1] = 1; next }
      $2 == "plan" && !($1 in r) && index($4, t) { print $1 }' "$TMPD/inrange" - > "$TMPD/hits"
    hits=$(wc -l < "$TMPD/hits")
    [ "$hits" -gt 0 ] && [ "$hits" -le "$XREF_MAX_HITS" ] || continue
    while IFS= read -r ln; do printf '%d\t%d\t%s\n' "$hits" "$ln" "$tok" >> "$TMPD/cand"; done < "$TMPD/hits"
  done < "$TMPD/tokens"
  # piu' raro prima; una riga sola per numero di riga; tetto XREF_MAX_LINES
  sort -t$'\t' -k1,1n -k2,2n "$TMPD/cand" | awk -F'\t' -v max="$XREF_MAX_LINES" '!seen[$2]++ { print "xref: riga " $2 " (" $3 ")"; if (++n >= max) exit }'
  return 0
}

# ─────────────────────────────────────────────────────────────────────────── lint
cmd_lint() {
  local spec="" base=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --baseline) [ $# -ge 2 ] || die_usage; base="$2"; shift 2 ;;
      -*) die_usage ;;
      *) [ -z "$spec" ] || die_usage; spec="$1"; shift ;;
    esac
  done
  [ -n "$spec" ] && [ -f "$spec" ] || die_usage
  local rc=0 ann; ann=$(annotate "$spec")
  viol() { echo "VIOLAZIONE: $*"; rc=1; }
  warn() { echo "AVVISO: $*"; }

  if ! printf '%s\n' "$ann" | awk -F'\t' '$2 != "above" { f = 1 } END { exit !f }'; then
    viol "nessuna sezione '## Piano di implementazione' (fuori dai blocchi di codice)"; return 1
  fi

  # Righe di stato: una sola occorrenza ancorata nel piano (changelog compreso), fuori dai recinti.
  local lit n ln prev=""
  for lit in "Plan status:" "Test level:" "Superfici a rischio:"; do
    n=$(printf '%s\n' "$ann" | awk -F'\t' -v l="$lit" '($2 == "plan" || $2 == "changelog") && $3 == 0 && index($4, l) == 1' | wc -l)
    if [ "$n" -gt 1 ]; then viol "'$lit' compare $n volte a inizio riga nel piano: dev'essere UNA (i grep a valle prendono la prima)"
    elif [ "$n" -eq 0 ]; then warn "'$lit' assente nel piano (spec legacy?) — in riapertura lo Step 1 la aggiunge"
    fi
    ln=$(printf '%s\n' "$ann" | awk -F'\t' -v l="$lit" '$2 == "plan" && $3 == 0 && index($4, l) == 1 { print $1; exit }')
    if [ -n "$prev" ] && [ -n "$ln" ] && [ "$ln" -ne $((prev + 1)) ]; then warn "'$lit' non sta nella riga subito sotto la precedente riga di stato"; fi
    [ -n "$ln" ] && prev="$ln"
    # Nel changelog il letterale non va citato nemmeno in mezzo alla riga: e' li' che nasce il duplicato.
    if printf '%s\n' "$ann" | awk -F'\t' -v l="$lit" '$2 == "changelog" && index($4, l) > 1 { f = 1 } END { exit !f }'; then
      warn "il changelog cita il letterale '$lit' in mezzo a una riga — scrivilo in prosa, e' a un a-capo dal diventare un duplicato"
    fi
  done

  # Approved basis: scritta all'approvazione (la scrive la skill, mai a mano); una sola.
  n=$(printf '%s
' "$ann" | awk -F'	' '($2 == "plan" || $2 == "changelog") && $3 == 0 && index($4, "Approved basis:") == 1' | wc -l)
  if [ "$n" -gt 1 ]; then viol "'Approved basis:' compare $n volte a inizio riga nel piano: dev'essere UNA"
  elif [ "$n" -eq 0 ] && printf '%s
' "$ann" | awk -F'	' '$2 == "plan" && $3 == 0 && $4 ~ /^Plan status:[ 	]*APPROVED/ { f = 1 } END { exit !f }'; then
    warn "piano APPROVED senza riga 'Approved basis:' (piano legacy: non si ritocca a mano, la riga arriva alla prossima approvazione)"
  fi

  # Superfici dichiarate: solo token del vocabolario (i backtick si tollerano, le note no).
  local decl; decl=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "Superfici a rischio:") == 1 { sub(/^Superfici a rischio:[ \t]*/, "", $4); print $4; exit }')
  local declared="" s nnone=0 ntok=0
  if [ -n "$decl" ]; then
    for s in $(printf '%s' "$decl" | tr -d '`' | tr ',·;' '   ' | tr -s ' '); do
      ntok=$((ntok + 1))
      case " $SURFACES " in
        *" $s "*) declared="$declared $s" ;;
        *) if [ "$s" = "nessuna" ]; then nnone=1
           else viol "superficie sconosciuta '$s' in 'Superfici a rischio' — solo token nudi del vocabolario: $SURFACES (oppure: nessuna)"; fi ;;
      esac
    done
    [ "$nnone" -eq 1 ] && [ "$ntok" -gt 1 ] && viol "'Superfici a rischio' dice 'nessuna' insieme ad altre superfici"
  fi

  # Pavimento: voce di elenco in "### Piano di test", su superficie CRITICA e DICHIARATA, una per superficie.
  local tz; tz=$(printf '%s\n' "$ann" | test_zone)
  local pav; pav=$(printf '%s\n' "$tz" | cut -f2- | grep -E "$PAV_RE" | grep -o '\[pavimento:[^]]*\]' | sed 's/^\[pavimento:[[:space:]]*//; s/[[:space:]]*\]$//' || true)
  if [ -n "$pav" ]; then
    while IFS= read -r s; do
      case " $CRITICAL " in *" $s "*) ;; *) viol "[pavimento: $s] — il pavimento vale solo per le superfici critiche: $CRITICAL" ;; esac
      case " $declared " in *" $s "*) ;; *) viol "[pavimento: $s] su una superficie non dichiarata in 'Superfici a rischio'" ;; esac
    done <<< "$pav"
    printf '%s\n' "$pav" | sort | uniq -d | while IFS= read -r s; do echo "VIOLAZIONE: piu' di una riga [pavimento: $s] — il pavimento e' UNA verifica per superficie"; done
    printf '%s\n' "$pav" | sort | uniq -d | grep -q . && rc=1
  fi
  # Superficie critica dichiarata senza pavimento ne' riga ⚠️ che la NOMINI: AVVISO (lo giudica L3).
  # Una riga ⚠️ su un'altra superficie non la copre. Deroga ("statica sufficiente:") senza motivo o
  # spezzata a capo: AVVISO — a valle `contract` la leggerebbe come obbligo.
  local wl wn wt nxt
  for s in $declared; do
    case " $CRITICAL " in *" $s "*) ;; *) continue ;; esac
    printf '%s\n' "$pav" | grep -qx "$s" && continue
    wl=$(printf '%s\n' "$ann" | warn_line "$s")
    if [ -z "$wl" ]; then
      warn "superficie critica '$s' dichiarata senza riga [pavimento: $s] ne' riga '⚠️ Superficie $s … non coperta'"
      continue
    fi
    wn=${wl%%$'\t'*}; wt=${wl#*$'\t'}
    if printf '%s\n' "$wt" | grep -q 'statica sufficiente:' && [ -z "$(waiver_of "$wt")" ]; then
      warn "riga $wn: deroga 'statica sufficiente:' senza motivo sulla stessa riga"
    fi
    nxt=$(printf '%s\n' "$ann" | awk -F'\t' -v n=$((wn + 1)) '$1 == n { print $4; exit }')
    if printf '%s\n' "$nxt" | grep -Eq '^[[:space:]]*(—|-)?[[:space:]]*(statica|sufficiente)'; then
      warn "riga $wn: la deroga continua a capo — 'statica sufficiente: <motivo>' va sulla stessa riga di '⚠️ Superficie $s'"
    fi
  done

  # e2e mirati per locator: al massimo 2 (oltre, una riga ⚠️ e il regression-watch).
  local ne2e; ne2e=$(printf '%s\n' "$tz" | cut -f2- | grep -cE "$E2E_RE" || true)
  [ "${ne2e:-0}" -le 2 ] || warn "$ne2e righe [e2e-locator: — al massimo 2; oltre, una riga ⚠️ e il regression-watch"

  # Lunghezza di "### Piano di test" rispetto al livello (AVVISO: la giudica L3, qui si misura).
  # Non contano le righe vuote, quelle di pavimento, quelle [e2e-locator: e le righe ⚠️: fuori dal tetto.
  local lvl; lvl=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "Test level:") == 1 { sub(/^Test level:[ \t]*/, "", $4); sub(/[ \t].*$/, "", $4); print $4; exit }')
  if printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && $4 ~ /^###[ \t]+([0-9]+\.[ \t]*)?Piano di test/ { f = 1 } END { exit !f }'; then
    # Formato 2: intestazione e separatore della tabella dei test e le righe "⚠️ Rischio aperto" non contano.
    local f2; f2=$(printf '%s\n' "$ann" | fmt2_of)
    local tlen; tlen=$(printf '%s\n' "$tz" | cut -f2- | grep -vE "$PAV_RE" | grep -vE "$E2E_RE" | grep -v '⚠️ Superficie' \
      | { if [ "$f2" = 1 ]; then grep -vE '^[[:space:]]*\|[[:space:]]*(ID[[:space:]]*\||:?-)' | grep -v '⚠️ Rischio aperto'; else cat; fi; } \
      | grep -c '[^[:space:]]' || true)
    case "$lvl" in
      min) [ "$tlen" -le 1 ] || warn "'### Piano di test' ha $tlen righe al livello min (tetto 1; righe [pavimento:, [e2e-locator: e ⚠️ escluse)" ;;
      std) [ "$tlen" -le 15 ] || warn "'### Piano di test' ha $tlen righe al livello std (tetto 15; righe [pavimento:, [e2e-locator: e ⚠️ escluse)" ;;
    esac
  fi

  # Con baseline: la spec sopra il piano e la review di implementazione non si toccano.
  if [ -n "$base" ]; then
    [ -f "$base" ] || { echo "baseline assente: $base" >&2; return 2; }
    local bann; bann=$(annotate "$base")
    local b_above c_above b_rev c_rev
    # Spazi e righe vuote in CODA alla parte sopra il piano non contano: la riga vuota che precede
    # "## Piano di implementazione" la aggiunge chi scrive il piano, non chi ha scritto la spec.
    b_above=$(printf '%s\n' "$bann" | awk -F'\t' '$2 == "above" { print $4 }' | above_norm | sha256sum)
    c_above=$(printf '%s\n' "$ann"  | awk -F'\t' '$2 == "above" { print $4 }' | above_norm | sha256sum)
    [ "$b_above" = "$c_above" ] || viol "le sezioni della SPEC sopra '## Piano di implementazione' sono cambiate rispetto alla baseline — questo ciclo non le puo' toccare"
    b_rev=$(printf '%s\n' "$bann" | awk -F'\t' '$2 == "review" { print $4 }' | sha256sum)
    c_rev=$(printf '%s\n' "$ann"  | awk -F'\t' '$2 == "review" { print $4 }' | sha256sum)
    [ "$b_rev" = "$c_rev" ] || viol "la sezione '## Review implementazione' e' cambiata — appartiene a /implementation-review-cycle"
  fi

  [ $rc -eq 0 ] && echo "lint: OK"
  return $rc
}

# ─────────────────────────────────────────────────────────────────────────── contract
# Il contratto di verifica del piano, come lo consuma /implementation-review-cycle: un solo parser per
# i due lati, cosi' il livello, le superfici e gli obblighi non vengono ri-dedotti a mano a valle.
cmd_contract() {
  [ $# -eq 1 ] && [ -f "$1" ] || die_usage
  local ann; ann=$(annotate "$1")
  if ! printf '%s\n' "$ann" | awk -F'\t' '$2 != "above" { f = 1 } END { exit !f }'; then
    echo "nessuna sezione '## Piano di implementazione' (fuori dai blocchi di codice)"; return 1
  fi
  local st n lvl decl s pl wl wn wt why r
  st=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "Plan status:") == 1 { print $4; exit }')
  echo "${st:-Plan status: (assente)}"
  n=$(printf '%s\n' "$ann" | awk -F'\t' '($2 == "plan" || $2 == "changelog") && $3 == 0 && index($4, "Test level:") == 1' | wc -l)
  lvl=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "Test level:") == 1 { sub(/^Test level:[ \t]*/, "", $4); sub(/[ \t].*$/, "", $4); print $4; exit }')
  # n conta anche il changelog (dove il letterale e' un duplicato), lvl solo il piano: una riga che
  # vive solo nel changelog non e' un livello.
  if [ "$n" -eq 0 ] || { [ "$n" -eq 1 ] && [ -z "$lvl" ]; }; then echo "Test level: legacy (assente)"
  elif [ "$n" -gt 1 ]; then echo "Test level: legacy (duplicata: $n)"
  else echo "Test level: $lvl"; fi
  decl=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "Superfici a rischio:") == 1 { sub(/^Superfici a rischio:[ \t]*/, "", $4); print $4; exit }')
  echo "Superfici a rischio: ${decl:-(assente)}"
  local tz; tz=$(printf '%s\n' "$ann" | test_zone)
  for s in $(printf '%s\n' "$ann" | declared_surfaces); do
    case " $CRITICAL " in *" $s "*) ;; *) continue ;; esac
    # PAV_RE via ENVIRON: `awk -v` interpreterebbe gli escape della regex (`\.` `\[`).
    pl=$(printf '%s\n' "$tz" | PAV="$PAV_RE" awk -F'\t' -v s="$s" '$2 ~ ENVIRON["PAV"] {
      t = $2; gsub(/\[pavimento:[ \t]*/, "[pavimento: ", t); gsub(/[ \t]*\]/, "]", t)
      if (index(t, "[pavimento: " s "]")) { print $1; exit } }')
    if [ -n "$pl" ]; then echo "Pavimento: $s (riga $pl)"; continue; fi
    wl=$(printf '%s\n' "$ann" | warn_line "$s")
    if [ -z "$wl" ]; then echo "Obbligo: $s — né pavimento né ⚠️"; continue; fi
    wn=${wl%%$'\t'*}; wt=${wl#*$'\t'}
    why=$(waiver_of "$wt")
    if [ -n "$why" ]; then echo "Statica sufficiente: $s — $why (riga $wn)"
    else echo "Obbligo: $s — ⚠️ senza deroga (riga $wn)"; fi
  done
  # Formato 2: anche le righe "⚠️ Rischio aperto" (difetto trovato tardi, con un test assegnato) sono focus di rischio.
  local f2; f2=$(printf '%s\n' "$ann" | fmt2_of)
  printf '%s\n' "$ann" | awk -F'\t' -v f2="$f2" '$2 == "plan" && $3 == 0 && (index($4, "⚠️ Superficie") || (f2 == 1 && index($4, "⚠️ Rischio aperto"))) {
    t = $4; sub(/^[ \t]*([-*][ \t]+)?/, "", t); print "Rischio: riga " $1 " — " t }'
  r=$(printf '%s\n' "$ann" | section_range "Piano di test"); echo "Piano di test: ${r:-assente}"
  r=$(printf '%s\n' "$ann" | section_range "Tracciabilità requisiti"); echo "Tracciabilità requisiti: ${r:-assente}"
  [ "$f2" = 1 ] && echo "Plan format: 2"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────── basis
# L'approvazione del piano legata a cio' che ha approvato. Due impronte (sha256, 12 caratteri):
#   spec = le sezioni sopra "## Piano di implementazione" (come nel lint --baseline: spazi e righe vuote
#          in coda non contano);
#   plan = il CORPO del piano: senza il changelog (note e riga di metrica si scrivono dopo l'approvazione)
#          e senza la riga "Approved basis:" stessa. I blocchi di codice contano.
# CR tolti, spazi a fine riga tolti. La review di implementazione non conta: e' scritta dopo, da un altro.
# La skill scrive all'approvazione "Approved basis: spec <fp> · plan <fp>"; /implementation-review-cycle
# registra le stesse due impronte come "Reviewed contract:". Riga assente → LEGACY (nessun controllo).
# Limiti dichiarati: una riga "Approved basis:" indentata o cancellata rende il piano LEGACY (il lint avvisa
# su APPROVED senza riga); il testo sotto un titolo #### dopo il changelog conta come changelog; le note
# del changelog (optional) non sono nell impronta.
full_line() { sed 's/^[^\t]*\t[^\t]*\t[^\t]*\t//'; }   # la riga intera: $4 si fermerebbe al primo TAB
basis_of() {
  local s p
  s=$(printf '%s\n' "$1" | awk -F'\t' '$2 == "above"' | full_line | above_norm | sha256sum | cut -c1-12)
  p=$(printf '%s\n' "$1" | awk -F'\t' '$2 == "plan" && !($3 == 0 && index($4, "Approved basis:") == 1)' | full_line | above_norm | sha256sum | cut -c1-12)
  printf 'spec %s · plan %s\n' "$s" "$p"
}
# ─────────────────────────────────────────────────────────────────────────── catene (harness-pt12)
# head_val <file> <letterale>: il valore della prima riga "<letterale> …" sopra il piano, fuori dai recinti.
head_val() { annotate "$1" | awk -F'\t' -v l="$2" '$2 != "above" { exit } $3 == 0 && index($4, l) == 1 { v = substr($4, length(l) + 1); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }'; }
# figlie_of <madre>: i nomi (senza .md) della riga "Figlie:", in ordine di catena, uno per riga.
figlie_of() { head_val "$1" "Figlie:" | grep -o 'spec-[A-Za-z0-9._-]*' | sed 's/\.md$//; s/\.$//' || true; }
# req_ids <file>: gli ID (RF<n>, CA<n>, anche puntati) DEFINITI in "Requisiti funzionali" e "Criteri di
# accettazione" sopra il piano, fuori dai recinti: a inizio di un titolo, di una voce di elenco o di una riga di
# tabella (il primo della riga). Unici, nell'ordine.
req_ids() {
  annotate "$1" | awk -F'\t' '
    $2 != "above" { exit }
    $3 == 1 { next }
    $4 ~ /^##[ \t]/ { s = $4; sub(/^##[ \t]+([0-9]+\.[ \t]*)?/, "", s); s = tolower(s)
      on = (index(s, "requisiti funzionali") == 1 || index(s, "criteri di accettazione") == 1); next }
    on && match($4, /^(###+[ \t]+|[ \t]*([-*]|[0-9]+\.)[ \t]+|[ \t]*\|[ \t]*)?[*_`]*(RF|CA)[0-9]+(\.[0-9]+)*/) {
      x = substr($4, RSTART, RLENGTH); match(x, /(RF|CA)[0-9]+(\.[0-9]+)*$/); id = substr(x, RSTART)
      if (!(id in seen)) { seen[id] = 1; print id } }'
}
# madre_of <spec>: "<madre><TAB><k><TAB><n><TAB><precedente|->" se una spec della stessa cartella elenca questa
# nella sua riga "Figlie:" (la prima, in ordine di nome); altrimenti niente.
madre_of() {
  local d b m k
  d=$(dirname "$1"); b=$(basename "$1" .md)
  while IFS= read -r m; do
    [ -n "$m" ] && [ "$(basename "$m" .md)" != "$b" ] || continue
    figlie_of "$m" > "$TMPD/figlie"
    k=$(grep -nxF -- "$b" "$TMPD/figlie" | head -1 | cut -d: -f1)
    [ -n "$k" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$m" "$k" "$(grep -c . "$TMPD/figlie")" \
      "$(if [ "$k" -gt 1 ]; then printf '%s/%s.md' "$d" "$(sed -n "$((k - 1))p" "$TMPD/figlie")"; else printf -- -; fi)"
    return 0
  done < <(find "$d" -maxdepth 1 -type f -name 'spec-*.md' -exec grep -l '^Figlie:' {} + 2>/dev/null | LC_ALL=C sort)
}
# closed_why <spec>: stampa perche' l'anello NON e' chiuso (niente = chiuso). Un solo criterio, usato anche da
# cycle-state.sh (plan-check.sh closed): Review status APPROVED, Feature status IMPLEMENTED e una riga
# "Finalize: IMPLEMENTED — snapshot <x12> — … · <ora UTC>" FRESCA, con le regole di finalize_gap di cycle-state.sh:
# <x12> = impronta del "Reviewed snapshot:" attuale e ora non piu' vecchia dell'ultima review lanciata
# (<run-dir>/log/<n>-*review*.jsonl). Nessun ripiego legacy: senza Finalize l'anello e' aperto.
closed_why() {
  local sec rs fs fz snap fs12 now ts rl rt run="${1%.md}.run"
  sec=$(tr -d '\r' < "$1" | awk '{ isf = ($0 ~ /^[ \t]*(```|~~~)/) } isf { inf = !inf; next } inf { next }
    !r && /^## Review implementazione/ { r = 1; next } r { print }')
  rs=$(printf '%s\n' "$sec" | sed -n 's/^Review status:[[:space:]]*//p' | head -1)
  fs=$(printf '%s\n' "$sec" | sed -n 's/^Feature status:[[:space:]]*//p' | head -1)
  fz=$(printf '%s\n' "$sec" | sed -n 's/^Finalize:[[:space:]]*//p' | head -1)
  snap=$(printf '%s\n' "$sec" | sed -n 's/^Reviewed snapshot:[[:space:]]*//p' | head -1)
  case "$rs" in APPROVED*) ;; *) echo "Review status ${rs:-(assente)}"; return ;; esac
  case "$fs" in IMPLEMENTED*) ;; *) echo "Feature status ${fs:-(assente)}"; return ;; esac
  case "$fz" in IMPLEMENTED*) ;; "") echo "nessuna riga Finalize: IMPLEMENTED"; return ;; *) echo "Finalize: $fz"; return ;; esac
  fs12=$(printf '%s\n' "$fz" | sed -n 's/.*snapshot \([0-9a-f]\{12\}\).*/\1/p' | head -1)
  now=$(printf '%s' "$snap" | tr -s ' \t' '  ' | sed 's/^ //; s/ $//' | tr -d '\n' | sha256sum | cut -c1-12)
  [ -n "$fs12" ] && [ "$fs12" = "$now" ] || { echo "Finalize su un altro snapshot (${fs12:-nessuna impronta}), non sul Reviewed snapshot attuale"; return; }
  ts=$(printf '%s\n' "$fz" | grep -o '[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z' | tail -1)
  ts=$( [ -n "$ts" ] && date -u -d "$ts" +%s 2>/dev/null )
  [ -n "$ts" ] || { echo "Finalize senza un'ora leggibile"; return; }
  rl=$(ls "$run/log" 2>/dev/null | sed -n 's/^\([0-9][0-9]*-[^.]*review[^.]*\)\.jsonl$/\1/p' | sort -t- -k1,1n | tail -1)
  [ -n "$rl" ] || return 0
  rt=$(date -r "$run/log/$rl.jsonl" +%s 2>/dev/null)
  [ -n "$rt" ] && [ "$ts" -ge "$rt" ] || echo "Finalize piu' vecchia dell'ultima review lanciata ($rl)"
}
closed_of() { [ -z "$(closed_why "$1")" ]; }
cmd_closed() {
  [ $# -eq 1 ] && [ -f "$1" ] || die_usage
  local w; w=$(closed_why "$1")
  if [ -z "$w" ]; then echo "Anello: CHIUSO"; return 0; fi
  echo "Anello: APERTO — $w"; return 1
}
# last_post_tree <run-dir>: il tree dell'ultimo .post-tree (etichetta di numero piu' alto), o niente.
last_post_tree() {
  local l; l=$(ls "$1/log" 2>/dev/null | sed -n 's/^\([0-9][0-9]*-[^.]*\)\.post-tree$/\1/p' | sort -t- -k1,1n | tail -1)
  [ -n "$l" ] && tr -d '\r\n ' < "$1/log/$l.post-tree"
}
# code_paths: i percorsi fra backtick delle righe su stdin (con una /), senza ::nome e :riga.
code_paths() { grep -o '`[^`]*`' | tr -d '`' | grep '/' | sed -E 's/::.*//; s/:[0-9]+(-[0-9]+)?$//; s/[[:space:]].*$//' | grep . | LC_ALL=C sort -u || true; }
# iface_fp <spec precedente> <tree> <radice>: impronta dei file della sua riga "Interfaccia per:" in quel tree
# (path + blob, oppure ABSENT); niente se la riga non nomina file.
iface_fp() {
  local l p out=""
  l=$(head_val "$1" "Interfaccia per:" | code_paths)
  [ -n "$l" ] || return 0
  while IFS= read -r p; do
    out="$out$p $(git -C "$3" rev-parse -q --verify "$2:$p" 2>/dev/null || echo ABSENT)
"
  done <<< "$l"
  printf '%s' "$out" | sha256sum | cut -c1-12
}

# TESTS (harness-pt11, solo formato 2): la fase test-red, chiusa OK, aggiunge in coda alla riga " · tests <fp>"
# (basis --write-tests): <fp> = sha256 (12) delle righe "<sha256 senza CR>  <path>" dei file dei test di
# accettazione (tabella del piano di test; `tests` le stampa). Si confronta SOLO quando c'e': diversa ->
# "Status: STALE (tests)" (un test di accettazione cambiato dopo test-red e' una deviazione). In formato 2 in piu'
# "Tests: <fp attuale>" e "Tests status: FRESH | STALE | ASSENTE". Formato 1: output invariato, byte per byte.
cmd_basis() {
  local spec="" wt=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --write-tests) wt=1; shift ;;
      -*) die_usage ;;
      *) [ -z "$spec" ] || die_usage; spec="$1"; shift ;;
    esac
  done
  [ -n "$spec" ] && [ -f "$spec" ] || die_usage
  set -- "$spec"
  local ann cur rec rs rp cs cp what="" f2 tl tcur="" trec="" tst="" nr
  ann=$(annotate "$1")
  if ! printf '%s\n' "$ann" | awk -F'\t' '$2 != "above" { f = 1 } END { exit !f }'; then
    echo "nessuna sezione '## Piano di implementazione' (fuori dai blocchi di codice)"; return 1
  fi
  cur=$(basis_of "$ann")
  # Catena (harness-pt12): i campi madre / prec / interfaccia, solo per una figlia.
  local ch madre="" k="" nk="" prev="" pclosed=0 ptree="" f
  ch=$(madre_of "$1")
  if [ -n "$ch" ]; then
    IFS=$'\t' read -r madre k nk prev <<< "$ch"
    cur="$cur · madre $(annotate "$madre" | awk -F'\t' '$2 == "above"' | full_line | above_norm | sha256sum | cut -c1-12)"
    if [ "$prev" != - ] && [ -f "$prev" ]; then
      cur="$cur · prec $(basis_of "$(annotate "$prev")" | sha256sum | cut -c1-12)"
      if closed_of "$prev"; then
        pclosed=1
        ptree=$(last_post_tree "${prev%.md}.run")
        if [ -n "$ptree" ]; then f=$(iface_fp "$prev" "$ptree" "$(repo_root "$1")"); [ -n "$f" ] && cur="$cur · interfaccia $f"; fi
      fi
    fi
    echo "Catena: anello $k/$nk di $(basename "$madre" .md)$([ "$prev" != - ] && printf ' · precedente %s (%s)' "$(basename "$prev" .md)" "$([ $pclosed -eq 1 ] && echo chiuso || echo aperto)")"
  fi
  rec=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "Approved basis:") == 1 { sub(/^Approved basis:[ \t]*/, "", $4); sub(/[ \t]+$/, "", $4); print $4; exit }')
  f2=$(printf '%s\n' "$ann" | fmt2_of)
  if [ "$f2" = 1 ]; then
    need_py || return 2
    tl=$(printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" tests "$(repo_root "$1")") || return 2
    tcur=$(printf '%s\n' "$tl" | sha256sum | cut -c1-12)
    trec=$(printf '%s\n' "$rec" | sed -n 's/.*tests[[:space:]]\{1,\}\([0-9a-f]\{12\}\).*/\1/p')
    if [ -z "$trec" ]; then tst=ASSENTE; elif [ "$trec" = "$tcur" ]; then tst=FRESH; else tst=STALE; fi
  fi
  rs=$(printf '%s\n' "$rec" | sed -n 's/.*spec[[:space:]]\{1,\}\([0-9a-f]\{12\}\).*/\1/p')
  rp=$(printf '%s\n' "$rec" | sed -n 's/.*plan[[:space:]]\{1,\}\([0-9a-f]\{12\}\).*/\1/p')
  cs=$(printf '%s\n' "$cur" | sed -n 's/.*spec \([0-9a-f]*\).*/\1/p')
  cp=$(printf '%s\n' "$cur" | sed -n 's/.*plan \([0-9a-f]*\).*/\1/p')
  if [ $wt -eq 1 ]; then   # chiusura OK di test-red: registra l'impronta dei test nella riga
    [ "$f2" = 1 ] || { echo "basis --write-tests: solo per i piani in formato 2"; return 1; }
    [ -n "$rec" ] || { echo "basis --write-tests: nessuna riga Approved basis (piano non approvato)"; return 1; }
    [ "$rs" = "$cs" ] && [ "$rp" = "$cp" ] || { echo "basis --write-tests: approvazione STALE (spec o piano cambiati): non si registra"; return 1; }
    nr=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "Approved basis:") == 1 { print $1; exit }')
    "$FIC_PY" "$TMPD/plan_check_f2.py" wbasis "$1" "$nr" "$tcur" || { echo "basis --write-tests: riga Approved basis non scritta"; return 1; }
    echo "Tests: $tcur registrata in Approved basis"
    return 0
  fi
  echo "Basis: $cur"
  echo "Recorded: ${rec:-assente}"
  if [ -z "$rec" ]; then
    echo "Status: LEGACY"
    [ "$f2" = 1 ] && { echo "Tests: $tcur"; echo "Tests status: $tst"; }
    return 0
  fi
  [ "$rs" = "$cs" ] || what="spec"
  [ "$rp" = "$cp" ] || what="${what:+$what, }plan"
  local fld r c hit cited
  for fld in madre prec interfaccia; do
    r=$(printf '%s\n' "$rec" | sed -n "s/.*$fld[[:space:]]\{1,\}\([0-9a-f]\{12\}\).*/\1/p")
    c=$(printf '%s\n' "$cur" | sed -n "s/.*$fld \([0-9a-f]*\).*/\1/p")
    if [ -n "$r" ]; then [ "$r" = "$c" ] || what="${what:+$what, }$fld"
    elif [ -n "$c" ] && [ "$fld" != interfaccia ]; then what="${what:+$what, }$fld"; fi
  done
  # L6: piano approvato mentre l'anello precedente implementava (nessuna "interfaccia" registrata), ora chiuso:
  # QUALUNQUE file citato dal piano e toccato dall'anello precedente → STALE, giro delta a k-1 chiuso.
  if [ $pclosed -eq 1 ] && [ -z "$(printf '%s\n' "$rec" | sed -n 's/.*interfaccia[[:space:]]\{1,\}\([0-9a-f]\{12\}\).*/\1/p')" ]; then
    cited=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan"' | full_line | code_paths)
    hit=""
    [ -n "$cited" ] && hit=$([ -f "${prev%.md}.run/touched.txt" ] && tr -d '\r' < "${prev%.md}.run/touched.txt" | grep -xF -f <(printf '%s\n' "$cited") | head -1)   # CONTROLLO-L6-TOUCHED
    [ -n "$hit" ] && what="${what:+$what, }touched: $hit"
  fi
  [ "$tst" = STALE ] && what="${what:+$what, }tests"   # CONFRONTO-TESTS
  if [ -z "$what" ]; then echo "Status: FRESH"; else echo "Status: STALE ($what)"; fi
  [ "$f2" = 1 ] && { echo "Tests: $tcur"; echo "Tests status: $tst"; }
  return 0
}

# ─────────────────────────────────────────────────────────────────────────── formato 2
# Parser delle tabelle del formato 2, in Python (stdin = righe di annotate). Nessun apice singolo qui dentro,
# e solo ASCII (i caratteri non ASCII come escape \u). need_py la scrive in un file di $TMPD (troppo lunga per `-c`).
PY2='
import json, os, re, sys

sys.stdin.reconfigure(encoding="utf-8", errors="replace")
sys.stdout.reconfigure(encoding="utf-8", newline="\n")

SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
H3 = re.compile(r"^###[ \t]+(?:[0-9]+\.[ \t]*)?(.*?)[ \t]*$")
HEAD = re.compile(r"^#{1,3}[ \t]")
BLOCK = re.compile(r"^####[ \t]+Blocco[ \t]+([A-Za-z0-9._-]+)")
KV = re.compile(r"^[ \t]*(?:[-*][ \t]+)?(scrive|dopo):[ \t]*(.*)$")
SEP = re.compile(r"^:?-+:?$")
LIST = re.compile(r"[,;\u00b7]")
PAV = re.compile(r"^[ \t]*(?:[-*]|[0-9]+\.)[ \t]+\[pavimento:[ \t]*([^\]]*?)[ \t]*\]")
E2E = re.compile(r"^[ \t]*(?:[-*]|[0-9]+\.)[ \t]+\[e2e-locator:[ \t]*([^\]]*?)[ \t]*\]")
RISK = re.compile(r"\u26a0\ufe0f?[ \t]*Rischio aperto")
# asserzione di un test esistente di non-regressione (harness-pt15, D): "resta verde", "rimane verde",
# "restano verdi", "continua a passare"... in testa alla cella (dopo eventuali * _ \u00ab " di formattazione)
INVARIANZA = re.compile(r"^[\s*_\u00ab\"]*(?:rest(?:a|ano)\s+verd[ei]|riman(?:e|gono)\s+verd[ei]|continu(?:a|ano)\s+a\s+passare)\b", re.I)
DESTR = re.compile(r"\bDELETE\b|\.delete\(|\bDROP\b|\bTRUNCATE\b|(?<![A-Za-z0-9_])rm ")
TEST_HDR = ["id", "requisito", "file", "asserzione", "mutazione"]
STEP_HDR = ["id", "file", "modifica", "test"]
STR_HDR = ["azione", "tipo", "valore"]
NONE = ("", "-", "\u2014", "nessuna", "nessuno")
SEC = {"decisioni": "Decisioni", "file toccati": "File toccati", "passi": "Passi",
       "tracciabilit\u00e0 requisiti": "Tracciabilit\u00e0 requisiti", "piano di test": "Piano di test",
       "stringhe e data-test": "Stringhe e data-test"}
VOCAB = ["permessi", "dati", "distruttiva", "contratto-api", "import", "logica-condivisa"]
MUT_FORM = "`file` \u00b7 `simbolo` \u00b7 `cerca` \u2192 `sostituisci` \u00b7 rosso se: `testo`"
SKIP = {"node_modules", ".nuxt", ".output", ".venv", "__pycache__", ".turbo", "coverage", "dist", ".git", ".pytest_cache"}


def load():
    rows = []
    for raw in sys.stdin.read().split("\n"):
        if not raw:
            continue
        p = raw.split("\t", 3)
        while len(p) < 4:
            p.append("")
        rows.append((int(p[0]), p[1], p[2] == "1", p[3]))
    return rows


def toks(s):
    """testo e code span (anche con piu backtick), come li legge il markdown"""
    out, buf, i, n = [], "", 0, len(s)
    while i < n:
        if s[i] == "`":
            j = i
            while j < n and s[j] == "`":
                j += 1
            m = re.compile("(?<!`)" + s[i:j] + "(?!`)").search(s, j)
            if m:
                if buf:
                    out.append(("t", buf))
                    buf = ""
                c = s[j:m.start()]
                if len(c) >= 2 and c[0] == " " and c[-1] == " " and c.strip():
                    c = c[1:-1]
                out.append(("c", c))
                i = m.end()
                continue
            buf += s[i:j]
            i = j
            continue
        buf += s[i]
        i += 1
    if buf:
        out.append(("t", buf))
    return out


def codes(s):
    return [v for k, v in toks(s) if k == "c"]


def cells(t):
    s = t.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|") and not s.endswith("\\|"):
        s = s[:-1]
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", s)]


def is_sep(c):
    return bool(c) and all(SEP.match(x.replace(" ", "")) for x in c)


def hnorm(c):
    return [x.lower().replace("*", "").replace("`", "").strip() for x in c]


def bare(s):
    return s.strip().strip("`*").strip()


def items(s):
    return [bare(x) for x in LIST.split(s) if bare(x).lower() not in NONE]


def tables(lines):
    out, cur = [], None
    for n, t in lines:
        if t.lstrip().startswith("|"):
            c = cells(t)
            if cur is None:
                cur = {"hdr": hnorm(c), "n": n, "rows": []}
                out.append(cur)
            elif not is_sep(c):
                cur["rows"].append((n, c))
        else:
            cur = None
    return out


def rel_ok(p):
    return (isinstance(p, str) and p != "" and not p.startswith("/") and "\\" not in p
            and ".." not in p.split("/") and not re.match(r"^[A-Za-z]:", p) and " " not in p)


def in_repo(root, p):
    return rel_ok(p) and os.path.exists(os.path.join(root, p.split("/")[0]))


_CONF = {}


def conf():
    """maat.json del progetto, risolta, letta IMPORTANDO maat-config.py (MAAT_CONFIG_PY, esportata da need_py): le
    stesse funzioni dei comandi modulo-di e comando, nessuna copia delle regole. Il file: MAAT_CONFIG, altrimenti
    <radice>/.claude/maat.json. Progetto non configurato: nessun modulo, nessuna superficie, nessuna migrazione.
    Configurazione non valida o lettore assente: uscita 2."""
    if "r" in _CONF:
        return _CONF["r"]
    import importlib.util
    p = os.environ.get("MAAT_CONFIG_PY") or ""
    try:
        import sys; sys.dont_write_bytecode = True   # nessun __pycache__ sotto MAAT_ROOT
        sp = importlib.util.spec_from_file_location("maat_config", p)
        mc = importlib.util.module_from_spec(sp)
        sp.loader.exec_module(mc)
    except Exception as e:
        sys.stderr.write("plan-check: lettore della configurazione non caricabile (%s): %s\n" % (p, e))
        sys.exit(2)
    f = os.environ.get("MAAT_CONFIG") or os.path.join(_CONF.get("root", "."), ".claude", "maat.json")
    try:
        cfg, _p = mc.carica(f)
        r = mc.risolto(cfg)
    except mc.Uscita as u:
        if u.codice != 4:
            sys.stderr.write("plan-check: maat.json: %s\n" % (u.messaggio or "configurazione non valida (uscita %d)" % u.codice))
            sys.exit(2)
        cfg, r = {"moduli": []}, {"moduli": []}
    _CONF["cfg"] = cfg
    piano = r.get("piano") or {}
    try:
        _CONF["sup"] = [(x["superficie"], re.compile(x["regex"])) for x in piano.get("superfici_critiche", [])]
        _CONF["mig"] = [re.compile(x) for x in piano.get("migrazioni", [])]
    except re.error as e:
        sys.stderr.write("plan-check: maat.json: regex non valida in piano: %s\n" % e)
        sys.exit(2)
    _CONF.update(mc=mc, r=r)
    return r


def modulo(p):
    """(modulo, "radice" | "pacchetti") del percorso (relativo al repo) secondo maat.json, (None, None) fuori"""
    r = conf()
    d = _CONF["mc"].modulo_di(r, p)
    if d is None:
        return None, None
    return next(m for m in r["moduli"] if m["nome"] == d[0]), d[1]


def radice(m):
    return _CONF["mc"].norm(m["radice"])


def rel_radice(m, p):
    rad = radice(m)
    return p[len(rad) + 1:] if rad else p


def runner(f, tp):
    """il modulo che esegue la controprova del file f osservata dal test tp, o None: la regola di counterproof.sh
    (file e test nello stesso modulo di maat.json, il test sotto la radice del modulo)"""
    mf, _kf = modulo(f)
    mt, kt = modulo(tp)
    if mf is None or mt is None or mf["nome"] != mt["nome"] or kt != "radice":
        return None
    return mf["nome"]


def parse_mut(cell):
    if cell.strip().lower() in NONE:
        return None, None
    parts, cur = [], []
    for k, v in toks(cell):
        if k == "c":
            cur.append((k, v))
            continue
        for i, sg in enumerate(v.split("\u00b7")):
            if i:
                parts.append(cur)
                cur = []
            if sg.strip():
                cur.append(("t", sg.strip()))
    parts.append(cur)
    bad = "mutazione illeggibile, forma attesa: " + MUT_FORM + " (sostituisci puo essere (vuoto))"
    if len(parts) != 4:
        return None, bad
    f, sym, cs, rs = parts
    if [k for k, v in f] != ["c"] or [k for k, v in sym] != ["c"]:
        return None, bad
    kinds = [k for k, v in cs]
    if kinds == ["c", "t", "c"] and re.match(r"^(\u2192|->)$", cs[1][1]):
        sost = cs[2][1]
    elif kinds == ["c", "t"] and re.match(r"^(\u2192|->)[ \t]*\(vuoto\)$", cs[1][1]):
        sost = ""
    else:
        return None, bad
    if [k for k, v in rs] != ["t", "c"] or rs[0][1].lower() != "rosso se:":
        return None, bad
    m = {"file": f[0][1].strip(), "simbolo": sym[0][1].strip(), "cerca": cs[0][1],
         "sostituisci": sost, "asserzione": rs[1][1]}
    if not m["simbolo"] or not m["asserzione"].strip():
        return None, "mutazione: simbolo e testo di rosso se non possono essere vuoti"
    if m["cerca"] == m["sostituisci"]:
        return None, "mutazione vuota: cerca uguale a sostituisci"
    return m, None


def sections(plan):
    sec, dup, cur = {}, [], None
    for n, t in plan:
        m = H3.match(t)
        if m:
            name = m.group(1).lower().replace("*", "")
            cur = None
            for k, v in SEC.items():
                if name == k or name.startswith(k + " ") or name.startswith(k + ":"):
                    cur = v
            if cur in sec:
                dup.append((n, cur))
                cur = None
            elif cur:
                sec[cur] = []
            continue
        if HEAD.match(t):
            cur = None
            continue
        if cur:
            sec[cur].append((n, t))
    return sec, dup


def build(rows, root):
    M = {"E": [], "W": [], "G": []}
    E, W, G = M["E"], M["W"], M["G"]
    plan = [(n, t) for n, z, f, t in rows if z == "plan" and not f]
    M["plan"] = plan
    M["plan_all"] = [(n, t) for n, z, f, t in rows if z == "plan"]
    tg = [t for n, z, f, t in rows if z == "above" and not f and t.startswith("Taglio:")]
    M["taglio"] = tg[0][len("Taglio:"):].strip() if tg else ""
    M["is2"] = any(re.match(r"^Plan format:[ \t]*2[ \t]*$", t) for n, t in plan)
    fmt = [n for n, t in plan if t.startswith("Plan format:")]
    if len(fmt) > 1:
        E.append("riga %d: Plan format: compare %d volte a inizio riga nel piano, deve essere UNA" % (fmt[1], len(fmt)))
    lvl = [t for n, t in plan if t.startswith("Test level:")]
    M["level"] = (lvl[0][len("Test level:"):].split() or ["legacy"])[0] if lvl else "legacy"
    dl = [t for n, t in plan if t.startswith("Superfici a rischio:")]
    M["declared"] = None
    if dl:
        M["declared"] = [x for x in re.split(r"[,;\u00b7\s]+", dl[0][len("Superfici a rischio:"):].replace("`", "")) if x]
    sec, dup = sections(plan)
    M["sec"] = sec
    for n, name in dup:
        E.append("riga %d: sezione ### %s ripetuta: deve essere una" % (n, name))
    for name in ("File toccati", "Passi", "Tracciabilit\u00e0 requisiti", "Piano di test"):
        if name not in sec:
            E.append("manca la sezione ### %s (formato 2)" % name)

    files, newf = [], []
    for n, t in sec.get("File toccati", []):
        tk = toks(t)
        for i, (k, c) in enumerate(tk):
            if k != "c":
                continue
            c = c.strip()
            if ("/" in c or "." in c) and c not in files:
                files.append(c)
            # harness-pt11: `path` (nuovo) = file che il piano crea (scope della fase test-red, stub, L2)
            if ("/" in c or "." in c) and i + 1 < len(tk) and tk[i + 1][0] == "t" \
                    and tk[i + 1][1].strip().lower().startswith("(nuovo)") and c not in newf:
                newf.append(c)
    M["files"], M["new_files"] = files, newf

    tests, order = {}, []
    tbls = [tb for tb in tables(sec.get("Piano di test", [])) if tb["hdr"] == TEST_HDR]
    if "Piano di test" in sec and not tbls:
        G.append("### Piano di test senza la tabella | ID | requisito | file | asserzione | mutazione |")
    for tb in tbls:
        for n, c in tb["rows"]:
            if len(c) != 5:
                G.append("riga %d: la riga del piano di test ha %d colonne, ne servono 5" % (n, len(c)))
                continue
            tid = bare(c[0])
            if not SAFE_ID.match(tid):
                G.append("riga %d: ID di test non valido (%s): lettere, cifre, . _ -" % (n, tid))
                continue
            if tid in tests:
                G.append("riga %d: ID di test %s ripetuto" % (n, tid))
                continue
            cs = codes(c[2])
            ref = cs[0].strip() if cs else ""
            path, name = (ref.split("::", 1) + [""])[:2]
            T = {"id": tid, "n": n, "reqs": items(c[1]), "path": path.strip(), "name": name.strip(), "mut": None,
                 "asserzione": c[3].strip(), "texts": [x for x in codes(c[3]) if x.strip()]}
            if not ref:
                G.append("riga %d: test %s: il file va fra backtick (`percorso` o `percorso::nome`)" % (n, tid))
            elif not in_repo(root, T["path"]):
                G.append("riga %d: test %s: percorso non relativo al repository: %s" % (n, tid, T["path"]))
            if not c[3].strip():
                G.append("riga %d: test %s: asserzione vuota (e il rosso se del caso)" % (n, tid))
            m, why = parse_mut(c[4])
            if why:
                G.append("riga %d: test %s: %s" % (n, tid, why))
            elif m:
                if not in_repo(root, m["file"]):
                    G.append("riga %d: test %s: file della mutazione non relativo al repository: %s" % (n, tid, m["file"]))
                elif not T["name"]:
                    G.append("riga %d: test %s: ha una mutazione ma non nomina il test (`percorso::nome`)" % (n, tid))
                elif not runner(m["file"], T["path"]):
                    G.append("riga %d: test %s: file e test in moduli diversi di maat.json (o fuori da ogni modulo, o test fuori dalla radice del modulo): counterproof.sh la rifiuterebbe" % (n, tid))
                else:
                    T["mut"] = m
            tests[tid] = T
            order.append(tid)
    M["tests"], M["order"] = tests, order

    blocks, steps, bids = [], [], set()
    cur, hdr = None, None
    for n, t in sec.get("Passi", []):
        m = BLOCK.match(t)
        if m:
            cur = {"id": m.group(1), "n": n, "scrive": None, "dopo": None}
            if cur["id"] in bids:
                E.append("riga %d: blocco %s ripetuto" % (n, cur["id"]))
            bids.add(cur["id"])
            blocks.append(cur)
            hdr = None
            continue
        if t.lstrip().startswith("|"):
            c = cells(t)
            if hdr is None:
                hdr = hnorm(c)
                continue
            if is_sep(c) or hdr != STEP_HDR:
                continue
            if len(c) != 4:
                E.append("riga %d: la riga del passo ha %d colonne, ne servono 4 (id | file | modifica | test)" % (n, len(c)))
                continue
            S = {"id": bare(c[0]), "n": n, "files": [x.strip() for x in codes(c[1]) if x.strip()],
                 "tests": items(c[3]), "block": cur["id"] if cur else None}
            if cur is None:
                E.append("riga %d: passo %s fuori da un blocco (#### Blocco <id>)" % (n, S["id"]))
            steps.append(S)
            continue
        hdr = None
        m = KV.match(t)
        if m and cur is not None and cur[m.group(1)] is None:
            cur[m.group(1)] = m.group(2).strip()
    if "Passi" in sec and not steps:
        E.append("### Passi senza la tabella | id | file | modifica | test |")
    if "Passi" in sec and not blocks:
        E.append("### Passi: i passi non sono raggruppati in blocchi (#### Blocco <id> con scrive: e dopo:)")
    for b in blocks:
        s = b["scrive"] or ""
        b["files"] = [x.strip() for x in codes(s) if x.strip()] or items(s)
        b["deps"] = [x for x in re.split(r"[,;\u00b7\s]+", (b["dopo"] or "").replace("`", "")) if x and x.lower() not in NONE]
        if not b["files"]:
            E.append("riga %d: blocco %s senza scrive: (i file che scrive)" % (b["n"], b["id"]))
        if b["dopo"] is None:
            W.append("riga %d: blocco %s senza dopo: (scrivi dopo: nessuno se non dipende da altri blocchi)" % (b["n"], b["id"]))
        for d in b["deps"]:
            if d not in bids:
                W.append("riga %d: blocco %s dopo %s, che non esiste" % (b["n"], b["id"], d))
    M["blocks"], M["steps"] = blocks, steps

    reqs = []
    for tb in tables(sec.get("Tracciabilit\u00e0 requisiti", []))[:1]:
        for n, c in tb["rows"]:
            r = bare(c[0])
            if r:
                reqs.append((n, r, c[2].strip() if len(c) > 2 else ""))
    if "Tracciabilit\u00e0 requisiti" in sec and not reqs:
        E.append("### Tracciabilit\u00e0 requisiti senza righe (| Req | Passi del piano | Verifica |)")
    M["reqs"] = reqs
    return M


def test_files(root):
    for d, subs, fs in os.walk(os.path.join(root, "modules")):
        subs[:] = sorted(s for s in subs if s not in SKIP)
        for f in sorted(fs):
            if ".test." in f or ".spec." in f or (f.startswith("test_") and f.endswith(".py")) or f.endswith("_test.py"):
                yield os.path.join(d, f)


# Un valore conta solo DENTRO un letterale del test (apici, virgolette, backtick) e INTERO: mai come pezzo di
# una parola piu lunga. Una riga che asserisce la sua ASSENZA resta verde quando il valore sparisce: e un
# AVVISO, non una violazione. Si decide PER LETTERALE, per posizione; la riga e di assenza solo se TUTTI i
# letterali del valore lo sono. Un letterale e in posizione di assenza solo se:
#   e seguito subito da "not in" (python: assert ... "X" not in body);
#   sta DENTRO l argomento di .not.toContain( / .not.toHaveText( / .not.toMatch(;
#   e l argomento di un find/get/query... a cui si applica DIRETTAMENTE .exists()).toBe(false), oppure
#   .toBeNull() / .toBeFalsy() senza .not. davanti: un accesso concatenato prima del matcher (.attributes(
#   .text() .classes() .element ...) chiede che l elemento esista, e il letterale resta positivo.
LITERAL = re.compile(r"\x27(?:[^\x27\\]|\\.)*\x27|\x22(?:[^\x22\\]|\\.)*\x22|`(?:[^`\\]|\\.)*`")
NEG_CALL = re.compile(r"\.not\.(?:toContain|toHaveText|toMatch)\(")
NULLISH = re.compile(r"(?<!\.not)\.(?:toBeNull|toBeFalsy)\(\)")  # REGOLA-NULLISH
NOT_EXISTS = re.compile(r"\.exists\(\)\)\.toBe\(false\)")
PY_NOT_IN = re.compile(r"^\s*not\s+in\b")
QUERY = re.compile(r"\b(?:find|findAll|get|querySelector|querySelectorAll|query\w*|findBy\w+|findAllBy\w+|getBy\w+|getAllBy\w+)\(\s*$")
# Non sono asserzioni: le righe di commento e il TITOLO di it/test/describe (il loro primo letterale);
# non /re/.test( ne x.it( : prima del nome non ci devono essere un punto o una lettera.
COMMENT = re.compile(r"^\s*(//|/\*|\*|#)")
TITLE = re.compile(r"(?<![.\w])(?:it|test|describe)(?:\.\w+)*\(\s*(" + LITERAL.pattern + ")")


def close_of(l, i, lits):
    """indice della parentesi che chiude quella aperta in l[i], saltando i letterali; len(l) se manca"""
    d, j = 0, i
    while j < len(l):
        inl = [b for a, b in lits if a <= j < b]
        if inl:
            j = inl[0]
            continue
        if l[j] == "(":
            d += 1
        elif l[j] == ")":
            d -= 1
            if d == 0:
                return j
        j += 1
    return len(l)


def lit_absent(l, m, lits):
    """True se il letterale m sta in una posizione di assenza"""
    if PY_NOT_IN.match(l[m.end():]):  # REGOLA-PY-POSIZIONE
        return True
    for c in NEG_CALL.finditer(l):
        if c.end() <= m.start() and m.end() <= close_of(l, c.end() - 1, lits):
            return True
    if QUERY.search(l[:m.start()]):
        k = close_of(l, l.rfind("(", 0, m.start()), lits)
        for t in NOT_EXISTS.finditer(l, k + 1):
            if not l[k + 1:t.start()].strip():
                return True
        for t in NULLISH.finditer(l, k + 1):
            if re.fullmatch(r"[\s)]*", l[k + 1:t.start()]):  # NULLISH-DIRETTO
                return True
    return False


def absent(l, tp, spans):
    """True se la riga l asserisce l ASSENZA del valore: tutti i suoi letterali (spans) in posizione di assenza"""
    lits = [(x.start(), x.end()) for x in LITERAL.finditer(l)]
    return all(lit_absent(l, m, lits) for m in spans)  # TUTTI-I-LETTERALI


def find_hits(root, vals):
    """valore -> [(file, riga, assenza)]: ogni riga di test che lo cita in un letterale"""
    pats, pats_tp = {}, {}
    for tp, val in vals:
        pats_tp[val] = tp
        if tp == "data-test":
            pats[val] = re.compile(r"(?<![A-Za-z0-9_-])" + re.escape(val) + r"(?![A-Za-z0-9_-])")
        else:
            pats[val] = re.compile(r"(?<!\w)" + re.escape(val) + r"(?!\w)")
    hits = {}
    for p in test_files(root):
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                lines = fh.read().split("\n")
        except OSError:
            continue
        rel = os.path.relpath(p, root).replace(os.sep, "/")
        for val, rx in pats.items():
            for i, l in enumerate(lines):
                if COMMENT.match(l):
                    continue
                l = TITLE.sub("(", l)
                spans = [m for m in LITERAL.finditer(l) if rx.search(m.group(0)[1:-1])]
                if spans:  # CRITERIO-LETTERALE
                    hits.setdefault(val, []).append((rel, i + 1, absent(l, pats_tp[val], spans)))  # CLASSIFICA-ASSENZA
    return hits


def lint2(M, root):
    E, W = M["E"], M["W"]
    tests, steps = M["tests"], M["steps"]
    E.extend(M["G"])
    covered = set(r for T in tests.values() for r in T["reqs"])
    known = set(r for n, r, v in M["reqs"])
    for n, r, ver in M["reqs"]:
        if r not in covered and not ver.lower().startswith("non verificabile"):  # CONTROLLO-REQUISITO-SENZA-TEST
            E.append("riga %d: requisito %s senza test: nessuna riga del piano di test lo nomina (oppure Verifica: non verificabile a test, <motivo>)" % (n, r))
    for tid in M["order"]:
        for r in tests[tid]["reqs"]:
            if known and r not in known:
                W.append("riga %d: test %s cita il requisito %s, che non e nella tracciabilita" % (tests[tid]["n"], tid, r))
    in_steps = set(x for S in steps for x in S["tests"])
    for tid in M["order"]:
        if tid not in in_steps:
            E.append("riga %d: test %s non compare in nessun passo (colonna test)" % (tests[tid]["n"], tid))
        # harness-pt11: la fase test-red verifica il rosso su un testo dell asserzione (ID + posizione)
        if not tests[tid]["texts"] and not tests[tid]["mut"]:  # CONTROLLO-ASSERZIONE-LINT2
            E.append("riga %d: test %s: asserzione senza testo fra backtick e senza mutazione: la fase test-red non puo dimostrare il rosso (scrivi il testo atteso del messaggio d errore fra backtick)" % (tests[tid]["n"], tid))
        # harness-pt15 (D): un test ESISTENTE di non-regressione non si dimostra rosso sulla base con stub; nella
        # tabella ferma il ciclo a test-red. Va in una nota sotto la tabella.
        if INVARIANZA.match(tests[tid]["asserzione"]):  # CONTROLLO-NON-REGRESSIONE-LINT2
            E.append("riga %d: test %s: asserzione \"resta verde\": un test esistente di non-regressione non e una riga del Piano di test (test-red pretende ogni riga rossa sulla base con stub). Toglilo dalla tabella e mettilo nella nota sotto di essa (\"Test ESISTENTI di non-regressione\": file, cosa resta vero, requisito, comando se fuori dal gate); la tracciabilita lo cita come \"non verificabile a test (invarianza, non dimostrabile rossa): <test esistente>\"" % (tests[tid]["n"], tid))
    files = set(M["files"])
    for S in steps:
        for x in S["tests"]:
            if x not in tests:
                W.append("riga %d: passo %s cita il test %s, che non e nella tabella del piano di test" % (S["n"], S["id"], x))
        for f in S["files"]:
            if f not in files:
                E.append("riga %d: passo %s: %s non e nella lista ### File toccati" % (S["n"], S["id"], f))
            if not in_repo(root, f):
                E.append("riga %d: passo %s: percorso non relativo al repository: %s" % (S["n"], S["id"], f))
    for n, t in M["plan"]:
        if RISK.search(t) and not any(re.search(r"(?<![A-Za-z0-9._-])" + re.escape(tid) + r"(?![A-Za-z0-9._-])", t) for tid in tests):
            E.append("riga %d: rischio aperto senza un test assegnato (un ID della tabella del piano di test)" % n)
    rows = []
    for tb in tables(M["sec"].get("Stringhe e data-test", [])):
        if tb["hdr"] not in (STR_HDR, STR_HDR + ["verificato"]):
            E.append("riga %d: ### Stringhe e data-test vuole la tabella | azione | tipo | valore | (piu | verificato | facoltativa)" % tb["n"])
            continue
        for n, c in tb["rows"]:
            ver = None   # deroga: colonna verificato = `file` - motivo (trattino lungo o corto)
            if len(tb["hdr"]) == 4 and len(c) == 4:
                v, c = c[3].strip(), c[:3]
                if v.lower() not in NONE:
                    vs = re.split(r"\s+(?:" + chr(0x2014) + r"|-)\s+", v, maxsplit=1)
                    vc = codes(vs[0])
                    vf = (vc[0] if vc else vs[0]).strip()
                    why = vs[1].strip() if len(vs) > 1 else ""
                    if not rel_ok(vf) or not why:
                        E.append("riga %d: verificato vuole `file` - motivo (file relativo al repository e un motivo)" % n)
                    else:
                        ver = (vf, why)
            az, tp = (c[0].strip().lower(), c[1].strip().lower()) if len(c) == 3 else ("", "")
            cs = codes(c[2]) if len(c) == 3 else []
            val = cs[0] if cs else (c[2].strip().strip("\u00ab\u00bb\"") if len(c) == 3 else "")
            if az not in ("aggiunge", "toglie") or tp not in ("stringa", "data-test") or not val:
                E.append("riga %d: attesi azione aggiunge|toglie, tipo stringa|data-test e un valore" % n)
                continue
            rows.append((n, az, tp, val, ver))
    if rows:
        hits = find_hits(root, [(tp, val) for n, az, tp, val, ver in rows])
        touched = set(M["files"]) | set(f for S in steps for f in S["files"]) | set(T["path"] for T in tests.values())
        e2e = set(x.group(1) for n, t in M["sec"].get("Piano di test", []) for x in [E2E.match(t)] if x)
        for n, az, tp, val, ver in rows:
            byfile = {}
            for rel, ln, neg in hits.get(val, []):
                byfile.setdefault(rel, []).append((ln, neg))
            if ver and ver[0] not in byfile:
                W.append("riga %d: deroga verificato inutilizzata: %s non cita %s %s in un letterale (o non esiste)" % (n, ver[0], tp, val))
            for rel, occ in byfile.items():
                pos = [ln for ln, neg in occ if not neg]
                if az == "aggiunge":
                    W.append("riga %d: %s %s aggiunto dal piano ma gia presente in %s:%d" % (n, tp, val, rel, occ[0][0]))
                elif rel in touched:
                    continue
                elif "/e2e/" in "/" + rel and os.path.basename(rel) in e2e:
                    continue
                elif not pos:
                    W.append("riga %d: %s %s tolto dal piano: %s:%d lo cita solo in un asserzione di assenza, che resta verde" % (n, tp, val, rel, occ[0][0]))
                elif ver and ver[0] == rel:
                    W.append("riga %d: %s %s tolto dal piano, asserito da %s:%d: deroga verificato (%s)" % (n, tp, val, rel, pos[0], ver[1]))
                else:
                    E.append("riga %d: %s %s tolto dal piano ma ancora asserito da %s:%d, che il piano non tocca (aggiungilo ai passi; un e2e vuole la sua riga [e2e-locator:]; oppure la colonna verificato)" % (n, tp, val, rel, pos[0]))
    for w in W:
        print("AVVISO: " + w)
    for e in E:
        print("VIOLAZIONE: " + e)
    if E:
        return 1
    print("lint2: OK")
    return 0


def to_mnt(p):
    p = p.replace("\\", "/")
    if p.startswith("//?/"):   # prefisso dei percorsi lunghi di Windows, tolto come maat_cygm
        p = p[4:]
    m = re.match(r"^([A-Za-z]):/(.*)$", p) or re.match(r"^/([A-Za-z])/(.*)$", p)
    return "/mnt/" + m.group(1).lower() + "/" + m.group(2) if m else p


def su_windows():
    """le righe vanno in WSL solo su Windows (come run_cp di run-phase.sh): altrove si eseguono dirette"""
    return os.name == "nt" or sys.platform.startswith(("cygwin", "msys"))


def maat_dir(wsl):
    p = (os.environ.get("MAAT_ROOT") or _CONF["mc"].PLUGIN).replace("\\", "/").rstrip("/")
    return to_mnt(p) if wsl else p


def py_wsl(m, root):
    """{python} di un modulo wsl, con la ricerca di gates.sh: i candidati del modulo (relativi alla radice), poi
    piattaforma.python (relativo al repo), poi python3; vince il primo che esiste (il file del repo e lo stesso visto
    da WSL), in forma /mnt. Un nome senza / vale com e ma NON e verificato: gates.sh lo cerca nel PATH di WSL (e se
    manca passa al candidato dopo), qui non si chiama WSL; la riga lo dichiara (riga_cmd). Ritorna (interprete,
    verificato); nessuno: (None, True) (python WSL assente)."""
    if os.environ.get("FIC_GATES_VENV_PY"):
        return os.environ["FIC_GATES_VENV_PY"], True
    mc = _CONF["mc"]
    v, base = m.get("python"), mc.norm(m["radice"])
    if not v:
        v, base = (_CONF["cfg"].get("piattaforma") or {}).get("python") or "python3", ""
    for c in (v if isinstance(v, list) else [v]):
        c = c.replace("\\", "/")
        if "/" not in c:
            return c, False
        if c.startswith("/") or re.match(r"^[A-Za-z]:/", c):
            p = c
        else:
            p = "/".join(x for x in (root.replace("\\", "/").rstrip("/"), base, mc.norm(c)) if x)
        if os.path.lexists(p):
            return to_mnt(p), True
    return None, True


def avvolgi(wsl, inner):
    """la riga in WSL (wsl -- bash -lc <riga quotata per bash: gli apici di espandi diventano \x27\\\x27\x27>) o diretta"""
    return "wsl -- bash -lc " + _CONF["mc"].sq(inner) if wsl else inner


def riga_cmd(m, tipo, root, run, file=(), test=()):
    """la riga di shell di comandi.<tipo> del modulo, da comando() di maat-config.py (stessa espansione di gates.sh):
    cd nella cartella del comando, poi il comando. Modulo ambiente wsl su Windows: dentro WSL, con {maat}, {python} e
    {report} in forma /mnt. {report}: <run>/gen/tests-<modulo>.junit.xml (o .report). Dentro WSL anche MAAT_CONFIG,
    se impostata, in forma /mnt (come in_wsl di gates.sh). {python} preso per nome (non verificato in WSL): un
    commento in coda lo dichiara. Comando non risolvibile: NON DISPONIBILE e il motivo."""
    mc = _CONF["mc"]
    wsl = m.get("ambiente") == "wsl" and su_windows()
    root = root.replace("\\", "/").rstrip("/")
    rep = os.path.abspath(os.path.join(run, "gen", "tests-%s.%s" % (
        m["nome"], "junit.xml" if m.get("report") == "junit" else "report"))).replace("\\", "/")
    env = {"MAAT_ROOT": maat_dir(wsl)}
    nota = ""
    if wsl and "{python}" in mc.testo(m.get("comandi", {}).get(tipo)):
        py, verificato = py_wsl(m, root)
        if py is None:
            return "NON DISPONIBILE — python WSL assente per il modulo %s" % m["nome"]
        if not verificato:
            nota = "  # non verificato: %s cercato nel PATH di WSL solo da gates.sh" % py
        env["FIC_GATES_VENV_PY"] = py
    prima = {k: os.environ.get(k) for k in env}
    os.environ.update(env)
    try:
        cart, riga = mc.comando(_CONF["cfg"], m["nome"], tipo, file=list(file), test=list(test),
                                report=to_mnt(rep) if wsl else rep, root=root)[0]
    except mc.Uscita as u:
        return "NON DISPONIBILE — " + (u.messaggio or "comando %s del modulo %s (uscita %d)" % (tipo, m["nome"], u.codice))
    finally:
        for k, v in prima.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    d = to_mnt(root + ("/" + cart if cart else "")) if wsl else cart
    pre = ""
    if wsl and os.environ.get("MAAT_CONFIG"):   # fuori da WSL la riga eredita l ambiente: niente da aggiungere
        pre = "export MAAT_CONFIG=" + mc.sq_se_serve(to_mnt(os.environ["MAAT_CONFIG"].replace("\\", "/"))) + "; "
    return avvolgi(wsl, pre + ("cd " + mc.sq_se_serve(d) + " && " if d else "") + riga) + nota


def riga_cp(muts, root, run):
    """la riga delle controprove: counterproof.sh del plugin su <run>/counterproof/mutations.json, con PROJECT_ROOT
    (e MAAT_CONFIG se impostata); dentro WSL solo su Windows e con un modulo delle mutazioni ambiente wsl (run_cp)"""
    mc = _CONF["mc"]
    wsl = su_windows() and any((modulo(e["file"])[0] or {}).get("ambiente") == "wsl" for e in muts)
    tr = to_mnt if wsl else (lambda x: x)
    mj = os.path.abspath(os.path.join(run, "counterproof", "mutations.json")).replace("\\", "/")
    env = "PROJECT_ROOT=" + mc.sq_se_serve(tr(root.replace("\\", "/").rstrip("/")))
    if os.environ.get("MAAT_CONFIG"):
        env += " MAAT_CONFIG=" + mc.sq_se_serve(tr(os.environ["MAAT_CONFIG"].replace("\\", "/")))
    return avvolgi(wsl, env + " bash " + mc.sq_se_serve(maat_dir(wsl) + "/scripts/counterproof.sh") + " " + mc.sq_se_serve(tr(mj)))


def gen(M, root, run, fp):
    for w in M["W"]:
        print("AVVISO: " + w)
    if M["G"]:
        for e in M["G"]:
            print("VIOLAZIONE: " + e)
        return 1
    tests = M["tests"]
    # liste vitest:/pytest: per RUNNER DICHIARATO del modulo del test (controprova.runner, come runner() e
    # counterproof.sh), percorsi relativi alla radice del modulo; gli altri test (fuori dai moduli, sotto i pacchetti,
    # runner comando o nessuno) in altri:, col percorso del repo. per_mod: i test di ogni modulo, per i comandi.
    vit, pyt, other = [], [], []
    per_mod = {"vitest": [], "pytest": []}   # [(modulo, [percorsi del repo])] nell ordine di prima comparsa
    for tid in M["order"]:
        p = tests[tid]["path"]
        mt, kt = modulo(p)
        rn = (mt.get("controprova") or {}).get("runner") if mt is not None and kt == "radice" else None
        if rn in per_mod:
            x, lst = rel_radice(mt, p), (vit if rn == "vitest" else pyt)
            g = next((v for k, v in per_mod[rn] if k["nome"] == mt["nome"]), None)
            if g is None:
                g = []
                per_mod[rn].append((mt, g))
            if p not in g:
                g.append(p)
        else:
            x, lst = p, other
        if x not in lst:
            lst.append(x)
    pav = [(PAV.match(t).group(1), t) for n, t in M["sec"].get("Piano di test", []) if PAV.match(t)]
    # L2 (harness-pt11): dopo la fase test-red (test-red/rossi.json) le mutazioni dei file NUOVI con il rosso alla
    # base con stub dimostrato si marcano assorbite; counterproof.sh le salta, finalize.sh le ricontrolla (l2).
    # Criterio di finalize (final=True: stub = simboli esportati ORA): alla chiusura di test-red il codice sono gli
    # stub appena registrati, quindi nulla cambia; rigenerata dopo l implementazione (cp_from_gen di run-phase.sh,
    # promozione L2 del driver) non assorbe cio che finalize rifiuterebbe.
    l2 = l2_eval(M, root, run, True) if os.path.isfile(os.path.join(run, "test-red", "rossi.json")) else {}
    muts, absorbed = [], []
    for tid in M["order"]:
        T = tests[tid]
        m = T["mut"]
        if not m:
            continue
        mt, _kt = modulo(T["path"])
        # il runner pytest delle controprove vuole il node id (<file>::<nome>), gli altri il nome del test
        pyid = mt is not None and (mt.get("controprova") or {}).get("runner") == "pytest"
        e = {"id": tid, "file": m["file"], "simbolo": m["simbolo"],
             "mutazione": {"cerca": m["cerca"], "sostituisci": m["sostituisci"]},
             "test": {"percorso": T["path"]},
             "rosso_se": {"test_id": T["path"] + "::" + T["name"] if pyid else T["name"],
                          "asserzione": m["asserzione"]}}
        for s, t in pav:
            if re.search(r"(?<![A-Za-z0-9._-])" + re.escape(tid) + r"(?![A-Za-z0-9._-])", t):
                e["superficie"] = s
                break
        if l2.get(tid) == "":
            e["assorbita"] = True
            e["motivo"] = "L2: file nuovo, rosso alla base con stub sull asserzione di rosso se (test-red), verde dopo"
            absorbed.append(tid)
        muts.append(e)
        fpath = os.path.join(root, m["file"])
        if not os.path.isfile(fpath):
            print("AVVISO: mutazione %s: %s assente nel working tree (atteso se lo crea il piano)" % (tid, m["file"]))
        else:
            with open(fpath, "rb") as fh:
                data = fh.read()
            c = m["cerca"].encode("utf-8")
            k = data.count(c)
            if k == 0 and b"\r\n" in data and b"\n" in c:
                k = data.count(c.replace(b"\n", b"\r\n"))
            if k != 1:
                print("AVVISO: mutazione %s: cerca compare %d volte in %s (dopo l implementazione ne serve esattamente 1)" % (tid, k, m["file"]))
    lines = ["Plan format: 2", "Impronta piano: " + fp, "Test level: " + M["level"],
             "vitest: " + (" ".join(vit) or "(nessuno)"), "pytest: " + (" ".join(pyt) or "(nessuno)"),
             "altri: " + (" ".join(other) or "(nessuno)")]
    # i comandi: comandi.test e comandi.lint del modulo, espansi da comando() di maat-config.py (riga_cmd)
    for rn in ("vitest", "pytest"):
        for mt, g in per_mod[rn]:
            lines.append("cmd %s: %s" % (rn, riga_cmd(mt, "test", root, run, test=g)))
    if M["level"] == "full":   # lint: ogni file del piano del modulo (radice o pacchetti), come gates.sh
        for mt in conf()["moduli"]:
            if "lint" not in mt.get("comandi", {}):
                continue
            fl = [f for f in M["files"] if (modulo(f)[0] or {}).get("nome") == mt["nome"]]
            if fl:
                lines.append("cmd lint: " + riga_cmd(mt, "lint", root, run, file=fl))
    if muts:
        lines.append("cmd counterproof: " + riga_cp(muts, root, run))
    lines.append("mutazioni: %d" % len(muts))
    for b in M["blocks"]:
        lines.append("blocco %s: scrive=%s \u00b7 dopo=%s" % (b["id"], ",".join(b["files"]) or "(nessuno)", ",".join(b["deps"]) or "nessuno"))
    os.makedirs(os.path.join(run, "gen"), exist_ok=True)
    with open(os.path.join(run, "gen", "procedura.txt"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    mj = os.path.join(run, "counterproof", "mutations.json")
    if muts:
        os.makedirs(os.path.dirname(mj), exist_ok=True)
        with open(mj, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(muts, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
    elif os.path.isfile(mj):
        os.unlink(mj)
    for l in lines:
        print(l)
    for tid in absorbed:
        print("gen: mutazione %s assorbita (L2)" % tid)
    print("gen: scritto %s%s" % (os.path.join(run, "gen", "procedura.txt").replace(os.sep, "/"), " e counterproof/mutations.json" if muts else ""))
    return 0


def surf_of(p):
    """superfici del percorso (relativo al repo): ogni regola {superficie, regex} di piano.superfici_critiche di
    maat.json la cui regex si trova nel percorso (re.search); nessuna regola = nessuna superficie"""
    conf()
    return {s for s, rx in _CONF["sup"] if rx.search(p)}


def is_mig(p):
    """il percorso e un file di migrazione: una regex di piano.migrazioni di maat.json si trova nel percorso"""
    conf()
    return any(rx.search(p) for rx in _CONF["mig"])


def route(M, diff):
    paths = []
    def add(p, where):
        p = re.sub(r":[0-9]+(-[0-9]+)?$", "", p.split("::")[0].strip())
        if p and "/" in p and " " not in p and (p, where) not in paths:
            paths.append((p, where))
    if M["is2"]:
        for f in M["files"]:
            add(f, "piano")
        for S in M["steps"]:
            for f in S["files"]:
                add(f, "piano")
        for b in M["blocks"]:
            for f in b["files"]:
                add(f, "piano")
        for T in M["tests"].values():
            add(T["path"], "piano")
    else:
        for n, t in M["plan"]:
            for c in codes(t):
                add(c, "piano")
    text = [("piano riga %d" % n, t) for n, t in M["plan_all"]]
    if diff:
        with open(diff, encoding="utf-8", errors="replace") as fh:
            for i, l in enumerate(fh.read().split("\n")):
                m = re.match(r"^diff --git a/(\S+) b/(\S+)", l)
                if m:
                    add(m.group(1), "diff")
                    add(m.group(2), "diff")
                elif l[:1] in "+-" and not l.startswith("+++") and not l.startswith("---"):
                    text.append(("diff riga %d" % (i + 1), l[1:]))
    ev = {}
    mig = []
    for p, where in paths:
        for s in surf_of(p):
            ev.setdefault(s, []).append(p)
        if is_mig(p) and p not in mig:
            mig.append(p)
    for where, t in text:
        m = DESTR.search(t)
        if m:
            ev.setdefault("distruttiva", []).append("parola chiave %s (%s)" % (m.group(0).strip(), where))
    decl = M["declared"]
    dset = set(x for x in (decl or []) if x in VOCAB)
    if "distruttiva" in dset and "distruttiva" not in ev:
        ev["distruttiva"] = ["dichiarata"]
    det = [s for s in VOCAB if s in ev]
    nl = len(M["plan_all"])
    print("Righe del piano: %d (tetto 150)" % nl)
    print("Migrazione: " + (", ".join(mig) if mig else "no"))
    for s in det:
        print("Superficie %s: %s" % (s, ", ".join(ev[s][:3]) + (" (+%d)" % (len(ev[s]) - 3) if len(ev[s]) > 3 else "")))
    print("Superfici rilevate: " + (", ".join(det) or "nessuna"))
    print("Superfici dichiarate: " + ("(assente)" if decl is None else (", ".join(decl) or "(vuota)")))
    why = []
    if nl > 150:
        why.append("piano di %d righe (oltre 150)" % nl)
    if mig:
        why.append("migrazione")
    if det:
        why.append("superfici rilevate: " + ", ".join(det))
    if decl is None:
        why.append("riga Superfici a rischio assente")
    elif decl != ["nessuna"]:
        why.append("dichiarazione diversa da nessuna: " + (", ".join(decl) or "(vuota)"))
    a = [s for s in det if s not in dset]
    b = [s for s in VOCAB if s in dset and s not in det]
    if a or b:
        d = []
        if a:
            d.append("rilevata e non dichiarata: " + ", ".join(a))
        if b:
            d.append("dichiarata e non rilevata: " + ", ".join(b))
        print("Discordanza: " + " \u00b7 ".join(d))
        why.append("discordanza con la dichiarazione")
    if why:
        print("Percorso: pieno \u2014 " + " \u00b7 ".join(why))
    else:
        print("Percorso: leggero \u2014 piano entro 150 righe, nessuna migrazione, nessuna superficie rilevata, dichiarazione concorde")
    return 0


SKEL_STEPS, SKEL_FILES, PLAN_LINES = 15, 40, 400


def skeleton(M):
    """harness-pt12: scheletro sotto o sopra il tetto (passi, file) e piano completo entro le righe"""
    files = list(M["files"])
    for S in M["steps"]:
        for f in S["files"]:
            if f not in files:
                files.append(f)
    ns, nf, nl = len(M["steps"]), len(files), len(M["plan_all"])
    if not ns:
        print("AVVISO: nessuna riga di passo sotto ### Passi (| id | file | modifica | test |): lo scheletro conta passi e file da li")
    decl = M["declared"]
    print("Passi: %d (tetto %d)" % (ns, SKEL_STEPS))
    print("File: %d (tetto %d)" % (nf, SKEL_FILES))
    print("Superfici: " + ("(assente)" if decl is None else (", ".join(decl) or "(vuota)")))
    print("Righe del piano: %d (tetto %d)" % (nl, PLAN_LINES))
    over = []
    if ns > SKEL_STEPS:  # TETTO-PASSI
        over.append("passi %d > %d" % (ns, SKEL_STEPS))
    if nf > SKEL_FILES:
        over.append("file %d > %d" % (nf, SKEL_FILES))
    if nl > PLAN_LINES:
        over.append("righe del piano %d > %d" % (nl, PLAN_LINES))
    if M["taglio"]:
        print("Taglio: " + M["taglio"])
    if over and M["taglio"].lower().startswith("rifiutato"):  # DECISIONE-TAGLIO
        print("Scheletro: SOPRA IL TETTO — " + " · ".join(over)
              + ": taglio rifiutato dall utente (riga Taglio:), si prosegue col piano unico, nessuno stop")
        return 0
    if over:
        print("Scheletro: SOPRA IL TETTO — " + " · ".join(over)
              + ": proposta di taglio (spec-author, modalita split), nessuna deroga")
        return 1
    print("Scheletro: SOTTO IL TETTO — il piano completo parte da questo scheletro")
    return 0


# ---- harness-pt11: fase test-red (test di accettazione, stub, verifica dei rossi) e L2 ----
IMPORT_JS = re.compile(r"Failed to load url|Failed to resolve import|Cannot find module|Cannot find package|does not provide an export named|is not exported by|Failed to parse source|Transform failed|SyntaxError|ERR_MODULE_NOT_FOUND")
IMPORT_PY = re.compile(r"ImportError|ModuleNotFoundError|SyntaxError|IndentationError|cannot import name")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
TS_EXP = re.compile(r"^[ \t]*export[ \t]+(?:declare[ \t]+)?(?:default[ \t]+)?(?:async[ \t]+)?(?:abstract[ \t]+)?(?:function\*?|const|let|var|class|interface|type|enum)[ \t]+([A-Za-z_$][\w$]*)", re.M)
TS_EXP_LIST = re.compile(r"^[ \t]*export[ \t]*(?:type[ \t]*)?\{([^}]*)\}", re.M)
TS_EXP_ANON = re.compile(r"^[ \t]*export[ \t]+default[ \t]+(?!(?:async[ \t]+)?(?:function|class)[ \t]+[A-Za-z_$])", re.M)
PY_DEF = re.compile(r"^(?:async[ \t]+)?(?:def|class)[ \t]+([A-Za-z]\w*)", re.M)
PY_ASSIGN = re.compile(r"^([A-Za-z]\w*)[ \t]*(?::[^=\n]*)?=(?!=)", re.M)
FAILH = re.compile(r"^\s*FAIL\s+(?:\|[^|]*\|\s+)?(\S+)(.*)$")
RANL = re.compile(r"^\s*(?:\u2713|\u276f|\u00d7|\u2193|FAIL)\s+(?:\|[^|]*\|\s+)?(\S+)")
SEPL = re.compile(r"\u23af{3,}")


def nrm(s):
    return " ".join(ANSI.sub("", s or "").split())


def jload(p):
    try:
        with open(p, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def jsave(p, d):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p + ".tmp", "w", encoding="utf-8", newline="\n") as fh:
        json.dump(d, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    os.replace(p + ".tmp", p)


def acc_paths(M):
    """i file dei test di accettazione (tabella del piano di test), in ordine"""
    out = []
    for tid in M["order"]:
        p = M["tests"][tid]["path"]
        if p and p not in out:
            out.append(p)
    return out


def stub_files(M):
    """i file che il piano dichiara nuovi e che non sono test di accettazione: vi vanno gli stub"""
    tp = set(acc_paths(M))
    return [f for f in M["new_files"] if f not in tp]


def cmd_accept(M):
    """scope della fase test-red: test <path> (i file di test del piano) e nuovo <path> (i file nuovi)"""
    for p in acc_paths(M):
        print("test " + p)
    for p in stub_files(M):
        print("nuovo " + p)
    return 0


def cmd_tests(M, root):
    """le righe dell impronta dei test di accettazione: sha256 del contenuto senza CR, due spazi, path"""
    import hashlib
    for p in sorted(acc_paths(M)):
        fp = os.path.join(root, p)
        if os.path.isfile(fp):
            with open(fp, "rb") as fh:
                h = hashlib.sha256(fh.read().replace(b"\r", b"")).hexdigest()
        else:
            h = "ABSENT"
        print(h + "  " + p)
    return 0


def exports(root, p):
    """simboli esportati di un file (None se assente): TS/JS export, Python def/class/nomi pubblici di modulo,
    .vue il componente (nome del file). Un export default anonimo vale il nome del file."""
    try:
        with open(os.path.join(root, p), encoding="utf-8", errors="replace") as fh:
            s = fh.read()
    except OSError:
        return None
    out = []

    def add(x):
        if x and x not in out:
            out.append(x)
    base_name = os.path.splitext(os.path.basename(p))[0]
    if p.endswith(".py"):
        for m in PY_DEF.finditer(s):
            add(m.group(1))
        for m in PY_ASSIGN.finditer(s):
            add(m.group(1))
    elif p.endswith(".vue"):
        add(base_name)
    else:
        for m in TS_EXP.finditer(s):
            add(m.group(1))
        for m in TS_EXP_LIST.finditer(s):
            for x in m.group(1).split(","):
                w = x.split()
                if w:
                    add(w[-1])
        if TS_EXP_ANON.search(s):
            add(base_name)
    return sorted(out)


def mentioned(root, paths, sym):
    rx = re.compile(r"(?<![\w$])" + re.escape(sym) + r"(?![\w$])")
    for p in paths:
        try:
            with open(os.path.join(root, p), encoding="utf-8", errors="replace") as fh:
                if rx.search(fh.read()):
                    return True
        except OSError:
            continue
    return False


def cmd_stubs(M, root, run):
    """alla chiusura OK di test-red: i simboli degli stub di ogni file nuovo -> <run>/test-red/stubs.json"""
    d = {}
    for f in stub_files(M):
        ex = exports(root, f)
        d[f] = {"simboli": ex}
        print("stub %s: %s" % (f, "assente" if ex is None else (", ".join(ex) or "(nessun simbolo)")))
    jsave(os.path.join(run, "test-red", "stubs.json"), d)
    return 0


def l2_why(T, m, stubs, rossi, root, acc, final):
    """perche la controprova di T NON e assorbita (vuoto = assorbita). final: codice implementato."""
    st = stubs.get(m["file"])
    if not isinstance(st, dict) or not isinstance(st.get("simboli"), list):
        return "stub non registrati alla chiusura di test-red"
    r = rossi.get(T["id"]) if isinstance(rossi, dict) else None
    if not isinstance(r, dict) or r.get("esito") != "dimostrato":
        return "rosso alla base con stub non dimostrato"
    if not r.get("posizione"):
        return "rosso alla base senza posizione"
    if nrm(m["asserzione"]) not in nrm(r.get("messaggio")):
        return "il rosso alla base non colpisce l asserzione di rosso se (%s)" % m["asserzione"]
    sy = st["simboli"]
    if final:
        cur = exports(root, m["file"])
        if cur is None:
            return "file assente"
        if sorted(cur) != sorted(sy):
            return "gli stub non coprono tutti e soli i simboli nuovi: esportati ora %s, stub %s" % (", ".join(cur) or "-", ", ".join(sy) or "-")
        sy = cur
    miss = [s for s in sy if not mentioned(root, acc, s)]  # SIMBOLI-TESTATI
    if miss:
        return "simbolo esportato non testato da nessun test di accettazione: " + ", ".join(miss)
    return ""


def l2_eval(M, root, run, final):
    """tid -> motivo ("" = assorbibile), per le sole mutazioni su file NUOVI (non di test)"""
    stubs = jload(os.path.join(run, "test-red", "stubs.json")) or {}
    rossi = (jload(os.path.join(run, "test-red", "rossi.json")) or {}).get("test") or {}
    acc = acc_paths(M)
    newf = set(stub_files(M))
    res = {}
    for tid in M["order"]:
        T = M["tests"][tid]
        m = T["mut"]
        if m and m["file"] in newf:
            res[tid] = l2_why(T, m, stubs, rossi, root, acc, final)
    return res


def cmd_l2(M, root, run, tests_state):
    """per finalize.sh: una riga per mutazione su un file nuovo, L2 <id>: OK | NO - <motivo>"""
    for tid, why in l2_eval(M, root, run, True).items():
        if tests_state != "FRESH":
            why = "impronta dei test di accettazione cambiata o non registrata (Tests status: %s)" % tests_state
        print("L2 %s: %s" % (tid, "OK" if not why else "NO \u2014 " + why))
    return 0


def junit_cases(p):
    import xml.etree.ElementTree as ET
    try:
        root = ET.parse(p).getroot()
    except Exception:
        return None
    out = []
    for c in root.iter("testcase"):
        kids = list(c)
        out.append({"cn": c.get("classname") or "", "nm": c.get("name") or "",
                    "bad": [(e.get("message") or "") + "\n" + (e.text or "") for e in kids if e.tag in ("failure", "error")],
                    "skip": any(e.tag == "skipped" for e in kids), "own": None})
    return out


def py_claim(T, c, trel):
    """come un caso JUnit riguarda il test T (trel: il suo percorso relativo alla radice del modulo): target | file |
    suite | None"""
    mod = trel[:-3].replace("/", ".") if trel.endswith(".py") else trel.replace("/", ".")
    cn, nm = c["cn"], c["nm"]
    if not cn:
        return "suite" if nm in (mod, trel, T["path"]) or nm.endswith("." + mod) else None
    if cn == mod:
        rest = ""
    elif cn.startswith(mod + "."):
        rest = "::" + cn[len(mod) + 1:].replace(".", "::")
    else:
        return None
    if not T["name"]:
        return "target"
    nid = trel + rest + "::" + nm
    if nid.endswith("::" + T["name"]) or nid.split("[")[0].endswith("::" + T["name"]):
        return "target"
    return "file"


def vitest_blocks(text):
    """blocchi FAIL del reporter di default: file (relativo alla radice del modulo), segmenti del nome o None (suite), testo"""
    lines = ANSI.sub("", text).split("\n")
    blocks, cur, ran = [], None, set()
    for l in lines:
        s = re.match(r"^\s*Tests\s+([0-9]+)\s+failed", l)  # riepilogo del runner: quanti test rossi
        if s:
            ran.add("#failed=" + s.group(1))
        r = RANL.match(l)
        if r:
            ran.add(r.group(1).lstrip("./"))
        m = FAILH.match(l)
        if m:
            rest = m.group(2).strip()
            segs = [x.strip() for x in rest[1:].split(" > ")] if rest.startswith(">") else None
            cur = {"file": m.group(1).lstrip("./"), "segs": segs, "body": [], "own": None}
            blocks.append(cur)
            continue
        if SEPL.search(l):
            cur = None
            continue
        if cur is not None:
            cur["body"].append(l)
    return blocks, ran


def vt_claim(T, b, trel):
    if b["file"] != trel:
        return None
    if b["segs"] is None:
        return "suite"
    if not T["name"]:
        return "target"
    s = b["segs"]
    # il piano puo nominare il test come vitest lo stampa ("describe > it") o col nome pieno di -t ("describe it")
    ids = set([sep.join(s[k:]) for k in range(len(s)) for sep in (" ", " > ")] + [s[-1]])
    return "target" if T["name"] in ids else "file"


def posizione(T, raw, trel):
    m = re.search(re.escape(trel) + r":([0-9]+)", raw.replace("\\", "/"))
    return "%s:%s" % (T["path"], m.group(1)) if m else None


def verdict(T, failed, suite, ran, passed, imp, trel):
    """(esito, motivo, messaggio, posizione) di un test di accettazione sulla base con stub"""
    texts = T["texts"] or ([T["mut"]["asserzione"]] if T["mut"] else [])
    if failed:
        raw = "\n".join(failed)
        msg = nrm(raw)
        pos = posizione(T, raw, trel)
        if imp.search(msg):  # CLASSIFICAZIONE-IMPORT
            return "rosso_import", "rosso per un errore d import, non per l asserzione: non dimostrato", msg, pos
        if not texts:  # CONTROLLO-ASSERZIONE: senza testo dell asserzione nessun rosso e dimostrato
            return "rosso_senza_asserzione", "nessun testo dell asserzione (backtick nella colonna asserzione o rosso se della mutazione): non dimostrato", msg, pos
        if texts and not any(nrm(x) in msg for x in texts):
            return "rosso_diverso", "rosso, ma non sull asserzione dichiarata (%s): non dimostrato" % " | ".join(texts), msg, pos
        if not pos:  # CONTROLLO-POSIZIONE: ID + posizione nel file di test
            return "rosso_senza_asserzione", "rosso senza posizione nel file di test: non dimostrato", msg, pos
        return "dimostrato", "rosso sull asserzione dichiarata", msg, pos
    if suite:
        msg = nrm("\n".join(suite))
        if imp.search(msg):
            return "rosso_import", "il file di test non si carica (errore d import): non dimostrato", msg, None
        return "rosso_raccolta", "il file di test fallisce in raccolta: non dimostrato", msg, None
    if not ran:
        return "rosso_raccolta", "file di test non raccolto dal runner: non dimostrato", "", None
    if passed:
        return "verde", "verde sulla base con stub: il test non prova nulla", "", None
    return "rosso_raccolta", "test nominato non eseguito (assente o saltato): non dimostrato", "", None


def cmd_rossi(M, root, run, ev):
    """Verifica del driver sulla base con stub (evidenza di gates.sh in <ev>): ogni test di accettazione rosso
    sulla sua asserzione, nessuna suite esistente in conflitto. Scrive <run>/test-red/rossi.json.
    Uscita 0 OK (tutti dimostrati) - 1 STOP - 3 BLOCKED (evidenza assente o gate BLOCKED)."""
    tests = M["tests"]
    # un gate tests-<modulo> per modulo di maat.json; il report si legge per il campo report del modulo
    mods = conf()["moduli"]
    gates = {"tests-" + m["nome"]: jload(os.path.join(ev, "tests-" + m["nome"] + ".json")) for m in mods}
    fmt = {"tests-" + m["nome"]: m.get("report", "nessuno") for m in mods}
    rad = {"tests-" + m["nome"]: radice(m) for m in mods}
    rep = {}
    for g, d in gates.items():
        # NOT RUN (con lo spazio, phase-result.schema.json) come SKIPPED: test non eseguiti, mai bloccati;
        # ogni altro esito (BLOCKED, NOT_RUN...) resta fuori da rep, cioe bloccato
        if not isinstance(d, dict) or d.get("esito") not in ("PASS", "FAIL", "SKIPPED", "NOT RUN"):
            continue
        p = os.path.join(ev, d.get("report") or "-")
        if d.get("esito") in ("SKIPPED", "NOT RUN"):
            rep[g] = None
        elif fmt[g] == "junit":
            rep[g] = junit_cases(p)
            if rep[g] is None:
                rep[g] = False
        elif fmt[g] == "vitest":
            try:
                with open(p, encoding="utf-8", errors="replace") as fh:
                    rep[g] = vitest_blocks(fh.read())
            except OSError:
                rep[g] = False
        else:
            rep[g] = False   # report nessuno: gli esiti dei singoli test non si leggono
    out, blocked = {}, []
    if not M["order"]:
        print("AVVISO: la tabella del piano di test non ha righe: nessun test di accettazione da dimostrare rosso")
    for tid in M["order"]:
        T = tests[tid]
        mt, kt = modulo(T["path"])
        g = "tests-" + mt["nome"] if mt is not None and kt == "radice" else None
        if g is None:
            out[tid] = ("non_eseguito", "test fuori dalla radice di ogni modulo di maat.json: il driver non lo esegue", "", None)
            continue
        d = gates[g]
        if not isinstance(d, dict) or g not in rep or rep[g] is False:
            why = "evidenza assente" if not isinstance(d, dict) else (
                "esito %s (%s)" % (d.get("esito"), d.get("motivo") or "") if g not in rep else
                "report illeggibile" if fmt[g] != "nessuno" else "report nessuno: esiti dei test non leggibili")
            if "%s: %s" % (g, why) not in blocked:
                blocked.append("%s: %s" % (g, why))
            continue
        if rep[g] is None:
            out[tid] = ("non_eseguito", "gate %s %s: %s" % (g, d.get("esito"), d.get("motivo") or ""), "", None)
            continue
        trel = rel_radice(mt, T["path"])
        if fmt[g] == "junit":
            failed, suite, ran, passed = [], [], False, False
            for c in rep[g]:
                k = py_claim(T, c, trel)
                if k is None:
                    continue
                if k == "suite":
                    ran = True
                    if c["bad"]:
                        suite += c["bad"]
                        c["own"] = tid
                    continue
                ran = True
                if k == "target":
                    if c["bad"]:
                        failed += c["bad"]
                        c["own"] = tid
                    elif not c["skip"]:
                        passed = True
            out[tid] = verdict(T, failed, suite, ran, passed, IMPORT_PY, trel)
        else:
            blocks, ran_files = rep[g]
            failed, suite = [], []
            for b in blocks:
                k = vt_claim(T, b, trel)
                if k == "target":
                    failed.append("\n".join(b["body"]))
                    b["own"] = tid
                elif k == "suite":
                    suite.append("\n".join(b["body"]))
                    b["own"] = tid
            ran = trel in ran_files or any(b["file"] == trel for b in blocks)
            out[tid] = verdict(T, failed, suite, ran, ran and not failed and not suite, IMPORT_JS, trel)
    # conflitti: una suite ESISTENTE rossa sulla base con stub (un caso che nessun test di accettazione reclama),
    # o un test esistente che asserisce l ASSENZA di un valore che il piano aggiunge (### Stringhe e data-test)
    def related(f):
        ids = [t for t in M["order"] if tests[t]["path"] == f] or M["order"]
        return "; ".join("%s: %s" % (t, tests[t]["asserzione"][:100]) for t in ids)
    confl = []
    def sotto_rad(g, x):
        return (rad[g] + "/" if rad[g] else "") + x
    for g in [x for x in gates if fmt[x] == "junit"]:   # prima i JUnit, poi vitest: l ordine di prima
        for c in (rep.get(g) or []):
            if c["bad"] and c["own"] is None:
                f = sotto_rad(g, c["cn"].replace(".", "/") + ".py") if c["cn"] else c["nm"]
                confl.append("%s::%s \u2014 %s <-> %s" % (c["cn"] or "(raccolta)", c["nm"], nrm("\n".join(c["bad"]))[:200], related(f)))
    for g in [x for x in gates if fmt[x] == "vitest"]:
        fe = rep.get(g)
        if fe:  # il riepilogo di vitest e i blocchi letti devono tornare: altrimenti il parser ha perso dei rossi
            nsum = [int(x.split("=")[1]) for x in fe[1] if x.startswith("#failed=")]
            nblk = len([b for b in fe[0] if b["segs"] is not None])
            if nsum and nsum[-1] != nblk:
                confl.append("riepilogo di vitest: %d test falliti, %d blocchi FAIL letti dall output: evidenza non interpretabile" % (nsum[-1], nblk))
        for b in (fe[0] if fe else []):
            if b["own"] is None:
                confl.append("%s%s \u2014 %s <-> %s" % (b["file"], " > " + " > ".join(b["segs"]) if b["segs"] else " (file)",
                                                       nrm("\n".join(b["body"]))[:200], related(sotto_rad(g, b["file"]))))
    adds = []
    for tb in tables(M["sec"].get("Stringhe e data-test", [])):
        for n, c in tb["rows"]:
            if len(c) >= 3 and c[0].strip().lower() == "aggiunge" and c[1].strip().lower() in ("stringa", "data-test"):
                cs = codes(c[2])
                v = cs[0] if cs else c[2].strip().strip("\u00ab\u00bb\"")
                if v:
                    adds.append((c[1].strip().lower(), v))
    if adds:
        for val, hs in find_hits(root, adds).items():
            for rel, ln, neg in hs:
                if neg:  # CONFLITTO-STATICO
                    near = [t for t in M["order"] if val in tests[t]["asserzione"]] or M["order"]
                    confl.append("%s:%d asserisce l assenza di %s, che il piano aggiunge <-> %s" % (
                        rel, ln, val, "; ".join("%s: %s" % (t, tests[t]["asserzione"][:100]) for t in near)))
    for tid in M["order"]:
        es, why, msg, pos = out.get(tid, ("bloccato", "gate non utilizzabile", "", None))
        print("rosso %s: %s%s \u2014 %s%s" % (tid, es, (" " + pos) if pos else "", why, (" \u2014 " + msg[:200]) if msg else ""))
    for c in confl:
        print("conflitto: " + c)
    bad = [t for t in M["order"] if t in out and out[t][0] != "dimostrato"]
    if blocked:
        esito, riass = "BLOCKED", "evidenza dei gate non utilizzabile: " + "; ".join(blocked)
    elif bad or confl:
        parts = ["non dimostrato: " + ", ".join("%s %s" % (t, out[t][0]) for t in bad)] if bad else []
        if confl:
            parts.append("conflitto con la suite esistente: " + confl[0])
        esito, riass = "STOP", "; ".join(parts)
    else:
        esito, riass = "OK", "%d/%d test di accettazione rossi sulla loro asserzione" % (len(out), len(M["order"]))
    jsave(os.path.join(run, "test-red", "rossi.json"), {
        "esito": esito, "riassunto": riass, "evidence": ev, "conflitti": confl,
        "test": {t: {"esito": v[0], "motivo": v[1], "messaggio": v[2][:4000], "posizione": v[3],
                     "file": tests[t]["path"], "nome": tests[t]["name"]} for t, v in out.items()}})
    print("rossi: esito=%s \u2014 %s" % (esito, riass))
    return {"OK": 0, "STOP": 1}.get(esito, 3)


def cmd_wbasis(spec, nr, fp):
    """scrive (o sostituisce) \u00b7 tests <fp> in coda alla riga Approved basis (riga nr), fine riga conservata"""
    with open(spec, encoding="utf-8", newline="") as fh:
        lines = fh.read().splitlines(keepends=True)
    i = int(nr) - 1
    if i < 0 or i >= len(lines):
        return 1
    body = lines[i].rstrip("\r\n")
    eol = lines[i][len(body):]
    if not body.startswith("Approved basis:"):
        return 1
    body = re.sub(r"[ \t]*\u00b7[ \t]*tests[ \t]+[0-9a-f]+", "", body).rstrip()
    lines[i] = body + " \u00b7 tests " + fp + eol
    with open(spec + ".tests.tmp", "w", encoding="utf-8", newline="") as fh:
        fh.write("".join(lines))
    os.replace(spec + ".tests.tmp", spec)
    return 0


cmd = sys.argv[1]
if cmd == "wbasis":
    sys.exit(cmd_wbasis(*sys.argv[2:5]))
_CONF["root"] = sys.argv[2]   # la radice del repository: maat.json di default, letta alla prima domanda (conf)
M = build(load(), sys.argv[2])
if not M["is2"] and cmd in ("lint2", "gen", "skeleton"):
    print("%s: non si applica (piano in formato 1, senza la riga Plan format: 2)" % cmd)
    sys.exit(0)
if not M["is2"] and cmd in ("accept", "tests", "stubs", "rossi", "l2"):
    print("%s: non si applica (piano in formato 1, senza la riga Plan format: 2)" % cmd)
    sys.exit(2)
if cmd == "accept":
    sys.exit(cmd_accept(M))
elif cmd == "tests":
    sys.exit(cmd_tests(M, sys.argv[2]))
elif cmd == "stubs":
    sys.exit(cmd_stubs(M, sys.argv[2], sys.argv[3]))
elif cmd == "rossi":
    sys.exit(cmd_rossi(M, sys.argv[2], sys.argv[3], sys.argv[4]))
elif cmd == "l2":
    sys.exit(cmd_l2(M, sys.argv[2], sys.argv[3], sys.argv[4]))
if cmd == "lint2":
    sys.exit(lint2(M, sys.argv[2]))
elif cmd == "gen":
    sys.exit(gen(M, sys.argv[2], sys.argv[3], sys.argv[4]))
elif cmd == "route":
    sys.exit(route(M, sys.argv[3] if len(sys.argv) > 3 else ""))
elif cmd == "skeleton":
    sys.exit(skeleton(M))
sys.exit(2)
'

need_py() {
  # Il programma va in un file di $TMPD, mai in `-c`: oltre ~32k caratteri Windows rifiuta la riga di comando.
  printf '%s' "$PY2" > "$TMPD/plan_check_f2.py" || return 2
  export MAAT_CONFIG_PY="${MAAT_CONFIG_PY:-$MAAT_SCRIPTS/maat-config.py}"   # il Python importa il lettore unico (conf)
  [ -n "${FIC_PY:-}" ] && return 0
  . "$MAAT_SCRIPTS/python.sh" && [ -n "${FIC_PY:-}" ] && return 0
  echo "plan-check: interprete Python non trovato (python.sh del full cycle)" >&2; return 2
}
repo_root() {
  if [ -n "${PLAN_CHECK_ROOT:-}" ]; then printf '%s\n' "$PLAN_CHECK_ROOT"; return; fi
  git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null || pwd
}
has_plan_section() { printf '%s\n' "$1" | awk -F'\t' '$2 != "above" { f = 1 } END { exit !f }'; }

cmd_lint2() {
  [ $# -eq 1 ] && [ -f "$1" ] || die_usage
  local ann; ann=$(annotate "$1")
  has_plan_section "$ann" || { echo "VIOLAZIONE: nessuna sezione '## Piano di implementazione' (fuori dai blocchi di codice)"; return 1; }
  need_py || return 2
  printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" lint2 "$(repo_root "$1")"
}

cmd_gen() {
  local spec="" run=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --run-dir) [ $# -ge 2 ] || die_usage; run="$2"; shift 2 ;;
      -*) die_usage ;;
      *) [ -z "$spec" ] || die_usage; spec="$1"; shift ;;
    esac
  done
  [ -n "$spec" ] && [ -f "$spec" ] || die_usage
  [ -n "$run" ] || run="${spec%.md}.run"
  local ann fp; ann=$(annotate "$spec")
  has_plan_section "$ann" || { echo "VIOLAZIONE: nessuna sezione '## Piano di implementazione' (fuori dai blocchi di codice)"; return 1; }
  need_py || return 2
  fp=$(basis_of "$ann" | sed -n 's/.*plan \([0-9a-f]*\).*/\1/p')
  printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" gen "$(repo_root "$spec")" "$run" "$fp"
}

# Fase test-red (harness-pt11), solo formato 2 (formato 1: "non si applica", uscita 2):
#   accept <spec>                          scope della fase: "test <path>" (file di test del piano), "nuovo <path>"
#   tests  <spec>                          righe dell'impronta dei test di accettazione ("<sha256>  <path>")
#   stubs  <spec> [--run-dir <d>]          simboli degli stub dei file nuovi -> <d>/test-red/stubs.json
#   rossi  <spec> --evidence <ev> [--run-dir <d>]   verifica dei rossi sulla base con stub, dall'evidenza di
#          gates.sh (tests-be JUnit, tests-fe output del reporter): ogni test rosso sulla sua asserzione (testi fra
#          backtick della colonna asserzione, altrimenti il rosso se della mutazione), import/raccolta = non
#          dimostrato, verde = STOP, suite esistente rossa o test che asserisce l'assenza di un valore aggiunto dal
#          piano = conflitto. Scrive <d>/test-red/rossi.json. Uscita 0 OK · 1 STOP · 3 BLOCKED.
#   l2     <spec> [--run-dir <d>]          per finalize.sh: "L2 <id>: OK | NO — <motivo>" delle mutazioni su file
#          nuovi, sul codice attuale (stub = simboli esportati, ogni simbolo in un test, impronta tests FRESH)
cmd_f2x() {
  local sub=$1 spec="" run="" ev=""; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --run-dir) [ $# -ge 2 ] || die_usage; run="$2"; shift 2 ;;
      --evidence) [ "$sub" = rossi ] && [ $# -ge 2 ] || die_usage; ev="$2"; shift 2 ;;
      -*) die_usage ;;
      *) [ -z "$spec" ] || die_usage; spec="$1"; shift ;;
    esac
  done
  [ -n "$spec" ] && [ -f "$spec" ] || die_usage
  [ "$sub" != rossi ] || [ -n "$ev" ] || die_usage
  [ -n "$run" ] || run="${spec%.md}.run"
  local ann root ts; ann=$(annotate "$spec")
  has_plan_section "$ann" || { echo "VIOLAZIONE: nessuna sezione '## Piano di implementazione' (fuori dai blocchi di codice)"; return 1; }
  need_py || return 2
  root=$(repo_root "$spec")
  case $sub in
    accept|tests) printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" "$sub" "$root" ;;
    stubs) printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" stubs "$root" "$run" ;;
    rossi) printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" rossi "$root" "$run" "$ev" ;;
    l2)
      ts=$(cmd_basis "$spec" | sed -n 's/^Tests status: //p')
      printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" l2 "$root" "$run" "${ts:-ASSENTE}" ;;
  esac
}

cmd_route() {
  local spec="" diff=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --diff) [ $# -ge 2 ] && [ -f "$2" ] || die_usage; diff="$2"; shift 2 ;;
      -*) die_usage ;;
      *) [ -z "$spec" ] || die_usage; spec="$1"; shift ;;
    esac
  done
  [ -n "$spec" ] && [ -f "$spec" ] || die_usage
  local ann; ann=$(annotate "$spec")
  has_plan_section "$ann" || { echo "nessuna sezione '## Piano di implementazione' (fuori dai blocchi di codice)"; return 1; }
  need_py || return 2
  if [ -n "$diff" ]; then printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" route "$(repo_root "$spec")" "$diff"
  else printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" route "$(repo_root "$spec")"; fi
}

# S2 · delta ∥ occhi freschi. Ogni risposta e' un file: prima riga "Impronta piano: <fp12>" (il valore "plan"
# di `basis` al lancio, scritto dall'orchestratore), poi il contratto del revisore (Decision:, Severity: …).
# APPROVA solo se entrambe sono sull'impronta attuale e pulite: nessun blocker/major, NEMMENO respinto.
review_info() {   # <file> → "<impronta|-> <decisione|-> <n. blocker/major> <parziale 0|1>"
  local t fp d nb p=0
  t=$(tr -d '\r' < "$1")
  fp=$(printf '%s\n' "$t" | sed -n 's/^Impronta piano:[[:space:]]*\([0-9a-f]\{12\}\).*/\1/p' | head -1)
  d=$(printf '%s\n' "$t" | sed -n 's/^Decision:[[:space:]]*\([A-Z_]*\).*/\1/p' | head -1)
  nb=$(printf '%s\n' "$t" | grep -cE '^[[:space:]]*([0-9]+\.[[:space:]]*)?Severity:[[:space:]]*(blocker|major)' || true)
  # parziale solo se la riga "Blocked on:" dice un motivo: "none" / "nessuno" non e' un blocco
  printf '%s\n' "$t" | grep -E 'Blocked on:' | grep -qviE 'Blocked on:[[:space:]]*(none|nessuno)[[:space:].]*$' && p=1
  echo "${fp:--} ${d:--} ${nb:-0} $p"
}
cmd_s2() {
  local spec="" fd="" fg="" nr=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --delta) [ $# -ge 2 ] || die_usage; fd="$2"; shift 2 ;;
      --gate) [ $# -ge 2 ] || die_usage; fg="$2"; shift 2 ;;
      --respinti) [ $# -ge 2 ] || die_usage; nr="$2"; shift 2 ;;
      -*) die_usage ;;
      *) [ -z "$spec" ] || die_usage; spec="$1"; shift ;;
    esac
  done
  [ -n "$spec" ] && [ -f "$spec" ] && [ -f "$fd" ] && [ -f "$fg" ] || die_usage
  case "$nr" in ''|*[!0-9]*) die_usage ;; esac
  local ann cur; ann=$(annotate "$spec")
  has_plan_section "$ann" || { echo "nessuna sezione '## Piano di implementazione' (fuori dai blocchi di codice)"; return 1; }
  cur=$(basis_of "$ann" | sed -n 's/.*plan \([0-9a-f]*\).*/\1/p')
  local dfp dd dnb dp gfp gd gnb gp
  read -r dfp dd dnb dp <<< "$(review_info "$fd")"
  read -r gfp gd gnb gp <<< "$(review_info "$fg")"
  local tot=$((dnb + gnb))
  [ "$nr" -le "$tot" ] || { echo "respinti ($nr) piu' dei blocker/major delle due risposte ($tot)" >&2; return 2; }
  case "$dd $gd" in *STOP_HUMAN*) echo "S2: STOP — un revisore chiede una decisione umana (delta $dd · gate $gd)"; return 0 ;; esac
  if [ "$dfp" != "$cur" ] || [ "$gfp" != "$cur" ]; then
    echo "S2: IMPRONTA DIVERSA — delta $dfp · gate $gfp · piano attuale $cur: rilancia entrambi sull'impronta attuale"; return 0
  fi
  if [ "$dp" = 1 ] || [ "$gp" = 1 ]; then echo "S2: RILANCIA — risposta parziale (Blocked on): non e' un'approvazione"; return 0; fi
  if [ $((tot - nr)) -gt 0 ]; then echo "S2: CORREGGI — $((tot - nr)) blocker/major da applicare (delta $dnb · gate $gnb · respinti $nr)"; return 0; fi
  [ "$nr" -gt 0 ] && { echo "S2: RILANCIA — $nr finding respinti: pulito vuol dire nessun finding, nemmeno respinto; si rilanciano delta e gate insieme, con la lista dei respinti"; return 0; }  # REGOLA-RESPINTI
  if { [ "$dnb" -eq 0 ] && [ "$dd" != APPROVED ]; } || { [ "$gnb" -eq 0 ] && [ "$gd" != APPROVED ]; }; then
    echo "S2: RILANCIA — Decision senza blocker/major ma non APPROVED (delta $dd · gate $gd)"; return 0
  fi
  echo "S2: APPROVA — delta e occhi freschi puliti sull'impronta $cur"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────── skeleton, split (harness-pt12)
cmd_skeleton() {
  [ $# -eq 1 ] && [ -f "$1" ] || die_usage
  local ann; ann=$(annotate "$1")
  has_plan_section "$ann" || { echo "VIOLAZIONE: nessuna sezione '## Piano di implementazione' (fuori dai blocchi di codice)"; return 1; }
  need_py || return 2
  printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" skeleton "$(repo_root "$1")"
}

cmd_split() {
  [ $# -ge 1 ] && [ -f "$1" ] || die_usage
  local madre=$1 d rc=0 id who n f lit; shift
  local kids=("$@")
  d=$(dirname "$madre")
  if [ ${#kids[@]} -eq 0 ]; then
    while IFS= read -r n; do [ -n "$n" ] && kids+=("$d/$n.md"); done < <(figlie_of "$madre")
  fi
  sviol() { echo "VIOLAZIONE: $*"; rc=1; }
  [ ${#kids[@]} -ge 2 ] || { sviol "una catena vuole almeno due figlie (argomenti, oppure la riga Figlie: della madre)"; return 1; }
  for f in "${kids[@]}"; do [ -f "$f" ] || { sviol "figlia assente: $f"; return 1; }; done
  n=$(for f in "${kids[@]}"; do basename "$f" .md; done | LC_ALL=C sort | uniq -d | tr '\n' ' ' | sed 's/ $//')
  [ -z "$n" ] || { sviol "figlia ripetuta nella catena: $n"; return 1; }
  req_ids "$madre" > "$TMPD/split.madre"
  if [ ! -s "$TMPD/split.madre" ]; then
    sviol "la madre non definisce ID (RF<n>, CA<n>) in Requisiti funzionali o Criteri di accettazione: la partizione non si verifica"; return 1
  fi
  : > "$TMPD/split.figlie"
  for f in "${kids[@]}"; do
    req_ids "$f" | awk -v k="$(basename "$f" .md)" '{ print $0 "\t" k }' >> "$TMPD/split.figlie"
  done
  # CONTROLLO-PARTIZIONE: ogni ID della madre in una e una sola figlia (perso o duplicato = STOP)
  while IFS= read -r id; do
    who=$(awk -F'\t' -v i="$id" '$1 == i { print $2 }' "$TMPD/split.figlie" | LC_ALL=C sort -u)
    n=$(printf '%s' "$who" | grep -c . || true)
    if [ "$n" -eq 0 ]; then sviol "$id della madre non sta in nessuna figlia (perso)"
    elif [ "$n" -gt 1 ]; then sviol "$id sta in $n figlie: $(printf '%s' "$who" | tr '\n' ' ' | sed 's/ $//') (duplicato)"; fi
  done < "$TMPD/split.madre"
  # le figlie non aggiungono requisiti: ogni loro ID e' della madre
  while IFS=$'\t' read -r id who; do
    grep -qxF -- "$id" "$TMPD/split.madre" || sviol "$who: $id non e' un ID della madre (le figlie non cambiano i requisiti)"
  done < "$TMPD/split.figlie"
  for f in "${kids[@]}"; do
    for lit in "Dipende da:" "Interfaccia per:"; do
      [ -n "$(head_val "$f" "$lit")" ] || sviol "$(basename "$f" .md): manca la riga '$lit' (sopra il piano, a inizio riga)"
    done
  done
  [ $rc -eq 0 ] && echo "split: OK — $(grep -c . "$TMPD/split.madre") ID della madre in ${#kids[@]} figlie, ciascuno in una sola"
  return $rc
}

PC_HERE=$(cd "$(dirname "$0")" && pwd)
. "$PC_HERE/lib/maat-paths.sh" || exit 4   # MAAT_SCRIPTS (plugin)
# MAAT_CONFIG relativo (alla cartella di lavoro, anche con spazi) reso assoluto QUI, in bash, come run-phase.sh: le righe
# cmd/cp di gen girano dopo un cd o dentro WSL, e os.path.abspath del Python di Windows su un /c/… darebbe C:\c\….
# Forma C:/… dove c'e' cygpath (maat_cygm), altrimenti quella di `pwd`.
if [ -n "${MAAT_CONFIG:-}" ]; then
  case $MAAT_CONFIG in
    /*|[A-Za-z]:[/\\]*) ;;
    *) # forma Windows anche senza cygpath (pwd -W); cartella non raggiungibile -> relativo alla cartella corrente
       if _d=$(cd "$(dirname "$MAAT_CONFIG")" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); then
         MAAT_CONFIG=$_d/$(basename "$MAAT_CONFIG")
       else MAAT_CONFIG=$PWD/$MAAT_CONFIG; fi; unset _d ;;
  esac
  MAAT_CONFIG=$(maat_cygm "$MAAT_CONFIG" 2>/dev/null || printf '%s' "$MAAT_CONFIG"); export MAAT_CONFIG
fi
TMPD=$(mktemp -d) || exit 2
trap 'rm -rf "$TMPD"' EXIT

[ $# -ge 1 ] || die_usage
sub="$1"; shift
case "$sub" in
  delta) cmd_delta "$@" ;;
  lint) cmd_lint "$@" ;;
  contract) cmd_contract "$@" ;;
  basis) cmd_basis "$@" ;;
  lint2) cmd_lint2 "$@" ;;
  gen) cmd_gen "$@" ;;
  route) cmd_route "$@" ;;
  s2) cmd_s2 "$@" ;;
  skeleton) cmd_skeleton "$@" ;;
  split) cmd_split "$@" ;;
  closed) cmd_closed "$@" ;;
  accept|tests|stubs|rossi|l2) cmd_f2x "$sub" "$@" ;;
  *) die_usage ;;
esac
exit $?
