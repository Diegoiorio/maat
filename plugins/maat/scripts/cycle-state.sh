#!/usr/bin/env bash
# cycle-state.sh — la tabella di ripresa di /full-implementation-cycle, calcolata e non interpretata.
#
#   cycle-state.sh <.claude/.ai-workflow/spec-<name>.md>
#
# Stampa le righe che ha letto e due righe finali:
#   State: <hash12>   impronta delle righe di stato della spec (per la guardia anti-loop dell'orchestratore)
#   Next: PLAN | IMPLEMENT | REVIEW | FIX | DONE | STOP — <motivo>   (catene: anche WAIT e CHIUSURA, sotto)
# Uscita 0 (anche per STOP: e' una risposta) · 2 uso.
#
# Legge: il piano con plan-check.sh (contract per Plan status, basis per "Approved basis"); la sezione
# "## Review implementazione" fuori dai recinti; per IMPLEMENTED il codice con review-surface.sh check
# sul "Reviewed snapshot" e sul manifest; la run dir <spec senza .md>.run/log/ per l'esito dell'ultima
# fase (<label>.esito, scritto da run-phase.sh: riga ESITO + "state=<hash>" allo stato di fine fase).
#
# ESITO STRUTTURATO (harness-pt08): se l'ultima fase implement/fix ha log/<label>.result.json (scritto da
# run-phase.sh solo se valido per script/fic/schemas/phase-result.schema.json) l'esito si legge da li', con le
# regole in codice: deviazioni[] non vuoto -> STOP a prescindere da "esito" (salvo che TUTTE comincino con
# "difensiva: ": deviazioni puramente difensive, non fermano, le giudica la review); bloccato_su diverso da "nessuno" ->
# STOP; altrimenti "esito". Un result.json illeggibile -> STOP. La fase e' OK solo se lo sono SIA il result.json
# SIA la riga ESITO di <label>.esito (il piu' conservativo; .esito e' l'autorita': run-phase.sh la scrive gia'
# STOP quando il JSON lo e'). Senza result.json (run dir vecchie, --inline) decide la sola riga ESITO, come prima.
# Un result.json STOP ferma il ciclo (riga 7s/11s) finche' la spec non cambia; per riprendere dopo la decisione
# umana si rinomina il file in <label>.result.json.visto: decide la riga ESITO (STOP -> si rilancia la fase, in
# completion). Una deviazione si accetta riaprendo il piano, non con la rinomina.
# NUOVO REGIME (run dir con evidence/ o con almeno un *.result.json, anche rinominato .result.json.visto): DONE
# (riga 13) solo con una riga "Finalize: IMPLEMENTED — snapshot <x12> — … · <ora UTC>" nella sezione di review,
# dove <x12> e' l'impronta del "Reviewed snapshot:" ATTUALE (lo snapshot che finalize.sh ha firmato: una review
# a mano o --inline che cambia lo snapshot senza rilanciare finalize non passa) e l'ora non e' piu' vecchia
# dell'ultima review lanciata (log/<n>-*review*.jsonl, se c'e'); altrimenti REVIEW (13f). Le run dir vecchie
# danno DONE come prima.
# BUDGET DEI FIX (riga 11b): calcolato qui da "Review rounds: n/3 · post-approval NEEDS_CHANGES: k/1", non
# letto dall'LLM.
#
# TABELLA — la prima riga che combacia vince. E' la fonte autorevole: SKILL.md rimanda qui.
#   1  sezione review senza piano                               → STOP (niente da pianificare sopra)
#   2  nessun piano, o Plan status DRAFT senza review             → PLAN
#   3  piano DRAFT o NEEDS HUMAN DECISION con una review          → STOP (piano riaperto dopo la review)
#   4  Plan status NEEDS HUMAN DECISION                           → STOP (decisione aperta)
#   5  Plan status non standard                                   → STOP
#   6  Approved basis STALE (spec o piano cambiati dopo l'approvazione) → STOP: riaprire il piano. STALE (tests):
#      un file dei test di accettazione cambiato dopo test-red (harness-pt11) → STOP (deviazione, decisione umana)
#   7t (harness-pt11) piano in FORMATO 2, nessuna review, nessuna implement/fix lanciata, impronta "tests" non
#      registrata nella Approved basis → TEST-RED; se l'ultima test-red ha un .esito con lo stato invariato (STOP, o
#      chiusa senza registrare i test) → STOP con quella riga. Formato 1: mai. Un ciclo in formato 2 gia' passato
#      da implement senza test-red (avviato prima della regola) prosegue come prima.
#   7s nessuna review, ultima implement/fix con result.json STOP (regole sopra) e stato invariato → STOP
#   7  nessuna review: ultima implement/fix lanciata = "implement", esito OK, stato invariato → REVIEW,
#      altrimenti IMPLEMENT (una review lanciata e mai partita non conta: non ha cambiato la spec)
#      (full o completion lo decide il worker implement). ATTRIBUZIONE (anche riga 11): il passaggio a
#      REVIEW richiede il <label>.post-tree di quella fase e nessun .pre-tree aperto di un label minore;
#      altrimenti STOP (attribuzione non misurata: la review non saprebbe quali file sono della feature).
#   8  sezione review legacy senza righe di stato                 → REVIEW (la review fa un giro pieno)
#   9  Review status NEEDS HUMAN DECISION                         → STOP
#   10 Reviewed contract diverso dalla basis attuale              → REVIEW (giro a scope pieno; vale anche
#      con NEEDS_CHANGES: quei finding erano sul contratto vecchio)
#   10b un path di touched.txt elencato sotto "Excluded:" del manifest → STOP (la review ha escluso codice
#      della feature). Le righe 10-13 non ripassano dall'attribuzione: una review c'e' gia' stata, e
#      run-phase chiude i .pre-tree aperti all'avvio di ogni fase di codice, review compresa.
#   11s NEEDS_CHANGES, ultima implement/fix con result.json STOP e stato invariato → STOP
#   11 NEEDS_CHANGES: ultima implement/fix lanciata = "fix", esito OK, stato invariato → REVIEW, altrimenti
#   11b FIX solo se n < 3 e k < 1 (Review rounds); budget esaurito o riga illeggibile → STOP
#   12 Feature status NEEDS_VERIFICATION                          → REVIEW (un tentativo di promozione)
#   13f nuovo regime, APPROVED + IMPLEMENTED senza "Finalize: IMPLEMENTED" sullo snapshot attuale e recente
#       → REVIEW (fail-closed)
#   13 APPROVED + IMPLEMENTED: codice FRESH → DONE · STALE/UNKNOWN → REVIEW · senza snapshot (legacy) → DONE
#      con nota. EXCLUDED-CHANGED non cambia l'esito: le righe vengono stampate per il report.
#   14 altro                                                      → STOP con le righe lette
#   0  (vale sopra ogni riga che manda a PLAN/IMPLEMENT/REVIEW/FIX, mai su DONE o su un altro STOP)
#      <run-dir>/harness.fp non UGUALE all'impronta attuale (run-phase.sh --harness-fp-confronta: CAMBIATO,
#      FORMATO-PRECEDENTE, ILLEGGIBILE o NON-CALCOLABILE) → STOP col motivo, la data e il rimedio. Senza harness.fp
#      (ciclo avviato prima della regola) nessun controllo.
#
# CATENE (harness-pt12). Una MADRE ha la riga "Figlie: spec-<nome>-1-…, -2-…" sopra il piano; un ANELLO e' una
# spec che una madre della stessa cartella elenca. Una spec fuori da una catena non vede nulla di questo.
#   C1 madre: la prima figlia assente → STOP; la prima non chiusa (plan-check.sh closed: APPROVED + IMPLEMENTED
#      e Finalize: IMPLEMENTED fresca sul Reviewed snapshot attuale, nessun ripiego legacy) → WAIT
#   C2 madre, anelli tutti chiusi: <run-dir della madre>/chiusura.txt assente → CHIUSURA (fase di codice di
#      run-phase.sh, etichetta NN-chiusura: gate full sull'albero finale contro la base del primo anello, e2e
#      via /dev-verify se le figlie hanno [e2e-locator:); "Chiusura: IMPLEMENTED — base <b> · tree <t> …" e
#      codice FRESH (review-surface.sh check sui file dei touched.txt degli anelli) → DONE, altrimenti
#      CHIUSURA; chiusura non riuscita → STOP col recupero. La madre e' IMPLEMENTED solo cosi'.
#   C3 anello k>1, verso PLAN: il piano di k-1 non e' APPROVED → WAIT (L6: il piano parte a piano di k-1 APPROVED)
#   C4 anello k>1, verso IMPLEMENT: k-1 non chiuso → WAIT; nessuna fase di codice di k ancora (nessun .pre-tree)
#      e working tree diverso dall'ultimo .post-tree di k-1, o .post-tree assente → STOP (modifiche umane che
#      l'anello si attribuirebbe). Le righe 6 (Approved basis, che per un anello include madre, piano di k-1,
#      interfaccia e touched: plan-check.sh basis) e le altre valgono come per ogni spec.
#   Stampa per un anello k>1: "Anelli precedenti: <file dei loro touched.txt>" (stessa catena: ne' altri flussi
#   ne' misti, niente completion), "Base anello: <.post-tree di k-1>" (mai HEAD) e "Diff anello: <path>" (solo i
#   path cambiati dalla base dell'anello: la superficie della sua review).
# Restano all'orchestratore: una fase ancora in corso (.running senza .exit), un ESITO FASE … STOP,
# e «NEEDS_VERIFICATION ottenuto in QUESTA invocazione → STOP». IMPLEMENTED lo firma script/fic/finalize.sh
# (run-phase.sh, dopo ogni review): qui si legge la riga che ha lasciato.
#
# Test: cycle-state.test.sh.

set -uo pipefail
set -f

[ $# -eq 1 ] && [ -f "$1" ] || { echo "uso: $0 <spec-<name>.md>" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_SCRIPTS (plugin) e PROJECT_ROOT (cartella di lavoro)

# INVOLUCRO (harness-pt14): la stessa tabella e' portata in script/fic/driver.py (`driver.py next`). Lo si usa al
# posto del codice qui sotto solo se il certificato script/fic/driver.equiv porta l'hash attuale di driver.py e di
# QUESTO file (equivalenza provata da `driver.py equiv --certifica` sulle run directory reali); altrimenti questo
# script resta autonomo. FIC_DRIVER=0 forza il codice qui sotto, FIC_DRIVER=1 il driver (test); FIC_DRIVER_PY e
# FIC_DRIVER_CERT sostituiscono driver e certificato (test). Driver fallito o senza riga Next -> codice qui sotto.
DRV=${FIC_DRIVER_PY:-$MAAT_SCRIPTS/driver.py}
CERT=${FIC_DRIVER_CERT:-$MAAT_SCRIPTS/driver.equiv}
fic_hash() { tr -d '\r' < "$1" | sha256sum | cut -c1-64; }
driver_on() {
  case "${FIC_DRIVER:-}" in 0) return 1 ;; 1) [ -f "$DRV" ]; return ;; esac
  [ -f "$DRV" ] && [ -f "$CERT" ] || return 1
  local c; c=$(tr -d '\r' < "$CERT")
  grep -qx "driver $(fic_hash "$DRV")" <<< "$c" && grep -qx "cycle-state $(fic_hash "${BASH_SOURCE[0]}")" <<< "$c"
}
if driver_on; then
  FIC_PY=""; . "$HERE/python.sh" 2>/dev/null
  if [ -n "$FIC_PY" ] && dout=$("$FIC_PY" "$DRV" next "$1" 2>/dev/null) && grep -q '^Next: ' <<< "$dout"; then
    printf '%s\n' "$dout"; exit 0
  fi
  echo "AVVISO: driver.py next non riuscito: cycle-state.sh autonomo" >&2
fi
PC="$MAAT_SCRIPTS/plan-check.sh"
RS="$MAAT_SCRIPTS/review-surface.sh"
# percorso assoluto di uno script del harness nei messaggi: C:/… su Windows (cygpath -m), come driver.py (mostra)
mostra() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
SPEC="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
RUN="${SPEC%.md}.run"
cd "$(dirname "$SPEC")" || exit 2
TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

# --- piano ---
has_plan=1
contract=$(bash "$PC" contract "$SPEC" 2>/dev/null) || has_plan=0
plan_raw=$(printf '%s\n' "$contract" | sed -n '1s/^Plan status:[[:space:]]*//p')
case "$plan_raw" in
  APPROVED*) plan=APPROVED ;; DRAFT*) plan=DRAFT ;; "NEEDS HUMAN DECISION"*) plan=NHD ;; *) plan=other ;;
esac
basis_out=""; basis=n/a; basis_cur=""; tests_st=""
if [ $has_plan -eq 1 ]; then
  basis_out=$(bash "$PC" basis "$SPEC" 2>/dev/null)
  basis=$(printf '%s\n' "$basis_out" | sed -n 's/^Status: //p')
  basis_cur=$(printf '%s\n' "$basis_out" | sed -n 's/^Basis: //p')
  tests_st=$(printf '%s\n' "$basis_out" | tr -d '\r' | sed -n 's/^Tests status: //p')   # solo formato 2
fi
fmt2=0; printf '%s\n' "$contract" | tr -d '\r' | grep -qx 'Plan format: 2' && fmt2=1

# --- sezione review: righe fuori dai recinti, da "## Review implementazione" in giu' ---
tr -d '\r' < "$SPEC" | awk '
  { isf = ($0 ~ /^[ \t]*(```|~~~)/) }
  isf { inf = !inf; next }
  inf { next }
  !r && /^## Review implementazione/ { r = 1 }
  r { print }' > "$TMP/review"
has_review=0; [ -s "$TMP/review" ] && has_review=1
line() { sed -n "s/^$1:[[:space:]]*//p" "$TMP/review" | head -1; }
rstatus=$(line "Review status"); fstatus=$(line "Feature status")
snap=$(line "Reviewed snapshot"); rcontract=$(line "Reviewed contract"); rounds=$(line "Review rounds")
# Manifest: i path sotto "Scope:" e sotto "Excluded:", fino a una riga vuota o alla fine del blocco.
list_of() { awk -v h="$1" '
  $0 == h ":" { on = 1; next }
  on && (/^[ \t]*$/ || /^Excluded:/ || /^Scope:/ || /^<\/details>/) { exit }
  on { print }' "$TMP/review"; }
list_of Scope > "$TMP/scope"; list_of Excluded > "$TMP/excl"

# --- catene (harness-pt12): madre (riga Figlie:) o anello (una madre della stessa cartella lo elenca) ---
chead() { # <file> <letterale>: il valore della prima riga "<letterale> …" sopra il piano, fuori dai recinti
  tr -d '\r' < "$1" | awk -v l="$2" '{ isf = ($0 ~ /^[ \t]*(```|~~~)/) } isf { inf = !inf; next } inf { next }
    /^## (Piano di implementazione|Review implementazione)/ { exit }
    index($0, l) == 1 { v = substr($0, length(l) + 1); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }'
}
cfiglie() { chead "$1" "Figlie:" | grep -o 'spec-[A-Za-z0-9._-]*' | sed 's/\.md$//; s/\.$//' || true; }
cclosed() { # <spec>: chiusa = plan-check.sh closed (un solo criterio: Finalize: IMPLEMENTED fresca, niente legacy)
  bash "$PC" closed "$1" >/dev/null 2>&1
}
cpost() { # <run-dir>: il tree dell'ultimo .post-tree (etichetta di numero piu' alto)
  local l; l=$(ls "$1/log" 2>/dev/null | sed -n 's/^\([0-9][0-9]*-[^.]*\)\.post-tree$/\1/p' | sort -t- -k1,1n | tail -1)
  [ -n "$l" ] && tr -d '\r\n ' < "$1/log/$l.post-tree"
}
CDIR=$(dirname "$SPEC"); CNAME=$(basename "$SPEC" .md)
figlie=$(cfiglie "$SPEC")
ring_k="" ring_n="" ring_madre="" ring_prev="" ring_before="" ring_base="" ring_now=""
if [ -z "$figlie" ]; then
  while IFS= read -r m; do
    [ "$(basename "$m" .md)" != "$CNAME" ] || continue
    l=$(cfiglie "$m"); k=$(printf '%s\n' "$l" | grep -nxF -- "$CNAME" | head -1 | cut -d: -f1)
    [ -n "$k" ] || continue
    ring_madre=$m ring_k=$k ring_n=$(printf '%s\n' "$l" | grep -c .)
    ring_before=$(printf '%s\n' "$l" | head -n $((k - 1)))
    [ "$k" -gt 1 ] && ring_prev="$CDIR/$(printf '%s\n' "$l" | sed -n "$((k - 1))p").md"
    break
  done < <(find "$CDIR" -maxdepth 1 -type f -name 'spec-*.md' -exec grep -l '^Figlie:' {} + 2>/dev/null | LC_ALL=C sort)
fi
if [ -n "$ring_prev" ]; then
  ring_base=$(cpost "${ring_prev%.md}.run")   # BASE-ANELLO: il .post-tree registrato di k-1, mai HEAD
  ring_now=$(bash "$RS" tree 2>/dev/null)
fi
# la madre: stato di ogni anello e della chiusura (entra nello State; vuoto fuori da una catena)
chain_state=""
if [ -n "$figlie" ]; then
  for c in $figlie; do
    if [ ! -f "$CDIR/$c.md" ]; then chain_state="$chain_state$c assente;"
    elif cclosed "$CDIR/$c.md"; then chain_state="$chain_state$c chiuso;"
    else chain_state="$chain_state$c aperto;"; fi
  done
  chain_state="$chain_state$([ -f "$RUN/chiusura.txt" ] && tr -d '\r' < "$RUN/chiusura.txt" | head -1)"
fi

# --- contratto registrato dalla review ---
hexes() { printf '%s\n' "$1" | grep -o 'spec [0-9a-f]\{12\}\|plan [0-9a-f]\{12\}' | tr '\n' ' '; }
contract_st=n/a
if [ $has_review -eq 1 ]; then
  if [ -z "$rcontract" ]; then contract_st=LEGACY
  elif [ "$(hexes "$rcontract")" = "$(hexes "$basis_cur")" ]; then contract_st=FRESH
  else contract_st=STALE; fi
fi

# --- impronta dello stato (tutto cio' che una fase puo' cambiare nella spec) ---
STATE=$( { echo "$plan_raw"; printf '%s\n' "$basis_out"; grep -E '^(Review status|Feature status|Verification|Reviewed snapshot|Reviewed contract|Review rounds):' "$TMP/review"; cat "$TMP/scope" "$TMP/excl"; printf '%s' "$chain_state"; } | sha256sum | cut -c1-12)

# --- ultima fase di CODICE che scrive (implement/fix) della run dir ---
# I label vengono da .jsonl (fasi lanciate da run-phase) e da .esito (anche le fasi --inline, che non
# hanno .jsonl).
# Non l'ultima fase in assoluto: una review lanciata e mai partita (lock occupato, guardia assente,
# sessione morta) lascia il suo .jsonl ma non cambia la spec, e non deve far ripetere l'implement o
# il fix gia' finiti. Una review che ha SCRITTO cambia lo State, e il confronto con state= la esclude.
last_label="" last_esito="" last_state=""
if [ -d "$RUN/log" ]; then
  last_label=$(ls "$RUN/log" 2>/dev/null | sed -n 's/^\([0-9][0-9]*-[^.]*\)\.\(jsonl\|esito\)$/\1/p' | grep -E 'implement|fix' | sort -u | sort -t- -k1,1n | tail -1)
  if [ -n "$last_label" ] && [ -f "$RUN/log/$last_label.esito" ]; then
    last_esito=$(tr -d '\r' < "$RUN/log/$last_label.esito" | sed -n '1p')
    last_state=$(tr -d '\r' < "$RUN/log/$last_label.esito" | sed -n 's/^state=//p')
  fi
fi
# --- esito strutturato (harness-pt08): result.json dell'ultima implement/fix, regole in codice ---
json_esito="" json_why=""
if [ -n "$last_label" ] && [ -f "$RUN/log/$last_label.result.json" ]; then
  FIC_PY=""; . "$HERE/python.sh" 2>/dev/null
  jr=$("${FIC_PY:-false}" -c 'import json, sys
sys.stdout.reconfigure(encoding="utf-8")
d = json.load(open(sys.argv[1], encoding="utf-8"))
one = lambda s: " ".join(str(s).split())[:300]
dev = [one(x) for x in (d.get("deviazioni") or []) if str(x).strip()]
bs = one(d.get("bloccato_su") if d.get("bloccato_su") is not None else "(assente)")
if [x for x in dev if not x.startswith("difensiva: ")]:
    print("STOP|deviazioni dichiarate (%d): %s" % (len(dev), one("; ".join(dev))))
elif bs.lower() != "nessuno":
    print("STOP|bloccato su: " + bs)
elif d.get("esito") != "OK":
    print("STOP|esito %s: %s" % (d.get("esito"), one(d.get("motivo") or "")))
else:
    print("OK|" + one(d.get("motivo") or ""))' "$RUN/log/$last_label.result.json" 2>/dev/null | tr -d '\r')
  case "$jr" in
    OK\|*|STOP\|*) json_esito=${jr%%|*} json_why=${jr#*|} ;;
    *) json_esito=STOP json_why="result.json illeggibile" ;;
  esac
fi
# last_ok <fase>: l'ultima implement/fix lanciata e' <fase>, e' finita OK (riga ESITO E, se c'e', result.json:
# vale il piu' conservativo), e da allora la spec non e' cambiata
last_ok() {
  case "$last_label" in *"$1"*) ;; *) return 1 ;; esac
  case "$last_esito" in "ESITO FASE $1: OK"*) ;; *) return 1 ;; esac
  [ -z "$json_esito" ] || [ "$json_esito" = OK ] || return 1
  [ "$last_state" = "$STATE" ]
}
# json_stop: righe 7s/11s — result.json STOP e spec invariata da allora → STOP con il recupero.
json_stop() {
  [ "$json_esito" = STOP ] && [ -n "$last_state" ] && [ "$last_state" = "$STATE" ] || return 0
  next "STOP — $last_label: $json_why (regola in codice su $RUN/log/$last_label.result.json). Decidi; per riprendere dopo la decisione (es. migrazione applicata) rinomina quel file in $last_label.result.json.visto: decide la riga ESITO di $last_label.esito (STOP -> la fase si rilancia, in completion). Una deviazione si accetta riaprendo il piano (spec cambiata), non con la rinomina"
}
# finalize_gap: riga 13f — nel nuovo regime stampa perche' IMPLEMENTED non e' firmato da finalize.sh.
new_regime=0
[ -d "$RUN/evidence" ] && new_regime=1
ls "$RUN/log" 2>/dev/null | grep -q '\.result\.json\(\.visto\)\{0,1\}$' && new_regime=1
# snap_fp <valore di Reviewed snapshot:>: impronta a 12 cifre, la stessa che finalize.sh scrive in "snapshot <x>"
# (spazi e tab compressi, estremi tolti, sha256).
snap_fp() { printf '%s' "$1" | tr -s ' \t' '  ' | sed 's/^ //; s/ $//' | tr -d '\n' | sha256sum | cut -c1-12; }
finalize_gap() {
  local f fs ts rl rt
  [ $new_regime -eq 1 ] || return 0
  f=$(line "Finalize")
  case "$f" in IMPLEMENTED*) ;; "") echo "IMPLEMENTED non firmato da finalize.sh (nessuna riga Finalize:)"; return ;;
    *) echo "IMPLEMENTED non firmato da finalize.sh (Finalize: $f)"; return ;; esac
  fs=$(printf '%s\n' "$f" | sed -n 's/.*snapshot \([0-9a-f]\{12\}\).*/\1/p' | head -1)
  [ -n "$fs" ] || { echo "riga Finalize: senza l'impronta dello snapshot firmato"; return; }
  [ "$fs" = "$(snap_fp "$snap")" ] || { echo "Finalize: firmata su un altro snapshot (snapshot $fs), non sul Reviewed snapshot attuale"; return; }   # confronto dello snapshot
  ts=$(printf '%s\n' "$f" | grep -o '[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z' | tail -1)
  ts=$( [ -n "$ts" ] && date -u -d "$ts" +%s 2>/dev/null )
  [ -n "$ts" ] || { echo "riga Finalize: senza un'ora leggibile"; return; }
  rl=$(ls "$RUN/log" 2>/dev/null | sed -n 's/^\([0-9][0-9]*-[^.]*review[^.]*\)\.jsonl$/\1/p' | sort -t- -k1,1n | tail -1)
  [ -n "$rl" ] || return 0
  rt=$(date -r "$RUN/log/$rl.jsonl" +%s 2>/dev/null)
  [ -n "$rt" ] || { echo "ora dell'ultima review ($rl) non leggibile"; return; }
  [ "$ts" -ge "$rt" ] || echo "Finalize: piu' vecchia dell'ultima review lanciata ($rl)"
}
# budget_fix: riga 11b — un fix solo se n < 3 e k < 1 (la sezione non dice che tipo di giro fu l'ultimo).
budget_fix() {
  local n k
  n=$(printf '%s\n' "$rounds" | sed -n 's|^\([0-9][0-9]*\)/3.*|\1|p')
  k=$(printf '%s\n' "$rounds" | sed -n 's|.*post-approval NEEDS_CHANGES:[[:space:]]*\([0-9][0-9]*\)/1.*|\1|p')
  [ -n "$n" ] && [ -n "$k" ] || next "STOP — budget dei fix non calcolabile: riga 'Review rounds: n/3 · post-approval NEEDS_CHANGES: k/1' assente o illeggibile ('${rounds}')"
  [ "$n" -lt 3 ] && [ "$k" -lt 1 ] || next "STOP — budget dei fix esaurito (Review rounds $n/3 · post-approval NEEDS_CHANGES $k/1): un fix che nessuna review vedra' non si scrive; decide una persona"
}
# attribution_gap: stampa il motivo se la fase OK <last_label> non ha l'attribuzione misurata.
attribution_gap() {
  local n f l
  [ -f "$RUN/log/$last_label.post-tree" ] || { echo "$last_label senza .post-tree"; return; }
  n=${last_label%%-*}
  for l in $(ls "$RUN/log" 2>/dev/null | sed -n 's/\.pre-tree$//p'); do   # set -f: niente glob
    [ -f "$RUN/log/$l.post-tree" ] && continue
    [ "$((10#${l%%-*}))" -lt "$((10#$n))" ] 2>/dev/null && { echo "$l con .pre-tree ancora aperto"; return; }
  done
}
# to_review <messaggio>: REVIEW solo con l'attribuzione misurata, altrimenti STOP con il recupero.
to_review() {
  local gap; gap=$(attribution_gap)
  [ -z "$gap" ] && next "REVIEW — $1"
  next "STOP — attribuzione non misurata ($gap): la review non saprebbe quali file sono della feature. Con il .pre-tree: git -c core.quotePath=false diff --name-only --no-renames \$(cat <pre-tree>) \$(bash $(mostra "$RS") tree) >> $RUN/touched.txt, poi quel tree in <label>.post-tree (e' cio' che fa run-phase). Senza .pre-tree: elenca a mano in touched.txt i file della feature, poi crea il .post-tree — decisione tua"
}
# test_red_gate: riga 7t (harness-pt11) — piano in formato 2 senza i test di accettazione dimostrati rossi.
tr_label=""
[ -d "$RUN/log" ] && tr_label=$(ls "$RUN/log" 2>/dev/null | sed -n 's/^\([0-9][0-9]*-[^.]*\)\.\(jsonl\|esito\)$/\1/p' | grep 'test-red' | sort -u | sort -t- -k1,1n | tail -1)
test_red_gate() {
  local l s
  [ "$fmt2" = 1 ] && [ -z "$last_label" ] && [ "$tests_st" != FRESH ] || return 0
  if [ -n "$tr_label" ] && [ -f "$RUN/log/$tr_label.esito" ]; then
    l=$(tr -d '\r' < "$RUN/log/$tr_label.esito" | sed -n 1p)
    s=$(tr -d '\r' < "$RUN/log/$tr_label.esito" | sed -n 's/^state=//p')
    [ -n "$s" ] && [ "$s" = "$STATE" ] && next "STOP — $tr_label: test di accettazione non registrati ($l). Decidi (piano da correggere e riapprovare, o test da rivedere): correggere i test di accettazione e' una decisione umana. Per rilanciare la fase: rinomina $RUN/log/$tr_label.esito in $tr_label.esito.visto"
  fi
  next "TEST-RED — piano in formato 2 approvato: test di accettazione e stub da scrivere e dimostrare rossi prima dell'implementazione"
}
# touched_excluded: il primo path di touched.txt che la review ha messo fra gli esclusi.
touched_excluded() {
  [ -s "$RUN/touched.txt" ] && [ -s "$TMP/excl" ] || return 0
  tr -d '\r' < "$RUN/touched.txt" | grep -Fx -f "$TMP/excl" | head -1
}

# --- codice (solo per IMPLEMENTED) ---
code=n/a code_out=""
case "$fstatus" in IMPLEMENTED*)
  if [ -z "$snap" ]; then code=LEGACY
  else
    b=$(printf '%s\n' "$snap" | sed -n 's/.*base \([0-9a-f]\{7,\}\).*/\1/p')
    t=$(printf '%s\n' "$snap" | sed -n 's/.*tree \([0-9a-f]\{7,\}\).*/\1/p')
    f=$(printf '%s\n' "$snap" | sed -n 's/.*fingerprint \([0-9a-f]\{7,\}\).*/\1/p')
    if [ -z "$b" ] || [ -z "$t" ] || [ ! -s "$TMP/scope" ]; then code=UNKNOWN; code_out="  snapshot o manifest illeggibili"
    else
      code_out=$(bash "$RS" check --base "$b" --tree "$t" --paths-file "$TMP/scope" --exclude-file "$TMP/excl" ${f:+--fingerprint "$f"} 2>&1)
      case "$(printf '%s\n' "$code_out" | sed -n 's/^Status: //p' | head -1)" in
        FRESH*) code=FRESH ;; STALE*) code=STALE ;; *) code=UNKNOWN ;;
      esac
      code_out=$(printf '%s\n' "$code_out" | grep -v '^Current tree:' | sed 's/^/  /')
    fi
  fi ;;
esac

echo "Plan status: ${plan_raw:-(assente)}"
echo "Plan basis: $basis"
# Catene (harness-pt12): righe in piu' solo per una madre o un anello.
if [ -n "$figlie" ]; then
  echo "Catena: madre di $(printf '%s\n' "$figlie" | grep -c .) anelli · $(printf '%s' "$chain_state" | sed 's/;\(.\)/; \1/g')"
elif [ -n "$ring_k" ]; then
  echo "Catena: anello $ring_k/$ring_n di $(basename "$ring_madre" .md)"
  if [ -n "$ring_prev" ]; then
    prevf=$(for c in $ring_before; do [ -f "$CDIR/$c.run/touched.txt" ] && tr -d '\r' < "$CDIR/$c.run/touched.txt"; done | grep . | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')
    echo "Anelli precedenti: ${prevf:-(nessun file)} — stessa catena, anello precedente: ne' altri flussi ne' misti, niente completion"
    if [ -n "$ring_base" ]; then echo "Base anello: $ring_base"; else echo "Base anello: (assente: l'anello precedente non ha un .post-tree)"; fi
    if [ -n "$ring_base" ] && [ -n "$ring_now" ]; then
      rdiff=$(git -c core.quotePath=false diff --name-only --no-renames "$ring_base" "$ring_now" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
      echo "Diff anello: ${rdiff:-(vuoto)}"
    fi
  fi
fi
# Formato 2 (harness-pt10): il formato e la procedura generata da `plan-check.sh gen`, confrontata con l'impronta
# del piano. Solo righe in piu', solo per i piani in formato 2: non entrano in State e non cambiano Next.
if printf '%s\n' "$contract" | grep -qx 'Plan format: 2'; then
  echo "Plan format: 2"
  gp="$RUN/gen/procedura.txt"
  gfp=$( [ -f "$gp" ] && tr -d '\r' < "$gp" | sed -n 's/^Impronta piano: //p' | head -1 )
  if [ ! -f "$gp" ]; then echo "Generated: assente"
  elif [ -n "$gfp" ] && [ "$gfp" = "$(printf '%s\n' "$basis_cur" | sed -n 's/.*plan \([0-9a-f]*\).*/\1/p')" ]; then echo "Generated: FRESH"
  else echo "Generated: STALE"; fi
fi
echo "Review section: $([ $has_review -eq 1 ] && echo present || echo absent)"
[ $has_review -eq 1 ] && { echo "Review status: ${rstatus:-(assente)}"; echo "Feature status: ${fstatus:-(assente)}"; }
echo "Reviewed contract: $contract_st"
echo "Code: $code"
[ -n "$code_out" ] && [ "$code" != FRESH -o -n "$(printf '%s\n' "$code_out" | grep EXCLUDED-CHANGED)" ] && printf '%s\n' "$code_out"
echo "Last code phase: ${last_label:-(nessuna)}${last_esito:+ · $last_esito}${json_esito:+ · result.json: $json_esito — $json_why}"
echo "State: $STATE"

# Riga 0: impronta del harness registrata al primo lancio (run-phase.sh, IMPRONTA DEL HARNESS).
harness_gap() { # stampa il motivo dello STOP se il harness e' cambiato dal primo lancio del ciclo
  # La decisione e' di run-phase.sh --harness-fp-confronta (la funzione unica dei tre lettori, pk04a-2): qui non si
  # legge il contenuto del file, si decide sulla prima parola.
  local out e a b repo since rim
  [ -f "$RUN/harness.fp" ] || return 0
  repo=${FIC_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}
  out=""; [ -n "$repo" ] && out=$(bash "$MAAT_SCRIPTS/run-phase.sh" --harness-fp-confronta "$RUN/harness.fp" "$repo" 2>/dev/null)
  read -r e a b <<< "$out"
  [ "$e" = UGUALE ] && return 0
  since=$(date -u -r "$RUN/harness.fp" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  rim="bash \"$(mostra "$MAAT_SCRIPTS/run-phase.sh")\" --harness-fp > \"$RUN/harness.fp\""
  case "$e" in
    CAMBIATO) echo "harness cambiato dal $since (impronta registrata $a, attuale $b): ricomincia la fase o conferma. Rimedio: se il cambio e' voluto, $rim e riprendi (prossima fase: $1); altrimenti riporta il harness com'era" ;;
    FORMATO-PRECEDENTE) echo "impronta di formato precedente: ciclo iniziato col harness interno (impronta registrata $a dal $since, attuale $b). Rimedio: se il passaggio al plugin e' voluto, $rim e riprendi (prossima fase: $1); altrimenti riprendi il ciclo col harness interno" ;;
    ILLEGGIBILE) echo "harness.fp illeggibile (vuoto o senza impronta, registrato dal $since; attuale $a). Rimedio: se il harness attuale e' quello voluto, $rim e riprendi (prossima fase: $1)" ;;
    *) echo "impronta del harness non calcolabile (file del plugin in $(mostra "$MAAT_ROOT") o .claude/maat.json di ${repo:-(nessuno)} non leggibili, oppure repository non trovato; registrata dal $since): verifica il plugin e il repository, poi riprendi" ;;
  esac
}
next() {
  case "$*" in PLAN*|IMPLEMENT*|REVIEW*|FIX*|CHIUSURA*|TEST-RED*)
    local gap; gap=$(harness_gap "${*%% *}")
    [ -n "$gap" ] && { echo "Next: STOP — $gap"; exit 0; } ;;
  esac
  case "$*" in PLAN*|IMPLEMENT*) [ -n "$ring_prev" ] && ring_gate "${*%% *}" ;;
    TEST-RED*) [ -n "$ring_prev" ] && ring_gate IMPLEMENT ;; esac   # test-red scrive il tree: come implement (C4)
  echo "Next: $*"; exit 0
}
# ring_gate PLAN|IMPLEMENT (righe C3, C4): pipeline della catena (L6) e tree all'avvio dell'anello k>1.
ring_gate() {
  local pn pst
  pn=$(basename "$ring_prev" .md)
  if [ "$1" = PLAN ]; then
    pst=$(bash "$PC" contract "$ring_prev" 2>/dev/null | tr -d '\r' | sed -n '1s/^Plan status:[[:space:]]*//p')
    case "$pst" in APPROVED*) return 0 ;; esac
    echo "Next: WAIT — catena: il piano dell'anello $ring_k parte quando il piano dell'anello $((ring_k - 1)) ($pn) e' APPROVED (ora: ${pst:-nessun piano})"; exit 0
  fi
  cclosed "$ring_prev" || { echo "Next: WAIT — catena: l'implement dell'anello $ring_k aspetta l'anello $((ring_k - 1)) ($pn) IMPLEMENTED; il piano puo' girare"; exit 0; }
  ls "$RUN/log" 2>/dev/null | grep -q '\.pre-tree$' && return 0   # l'anello e' gia' partito
  [ -n "$ring_base" ] || { echo "Next: STOP — catena: l'anello $((ring_k - 1)) ($pn) non ha un .post-tree: la base dell'anello $ring_k non e' misurata. Decisione tua"; exit 0; }
  [ "$ring_now" = "$ring_base" ] && return 0   # CONTROLLO-TREE-ANELLO
  echo "Next: STOP — catena: il working tree (${ring_now:-non calcolabile}) non e' il .post-tree dell'anello $((ring_k - 1)) ($ring_base): modifiche fatte dopo la sua chiusura, che l'anello $ring_k si attribuirebbe. Decisione tua: riportale fuori dal tree e riprendi; per tenerle nella catena aggiungile al touched.txt di $pn e registra il tree attuale come suo .post-tree (bash $(mostra "$RS") tree)"; exit 0
}
# --- madre di una catena (righe C1, C2): nessuna fase propria finche' gli anelli non sono chiusi ---
mother_next() {
  local i=0 n c cz b t st
  n=$(printf '%s\n' "$figlie" | grep -c .)
  for c in $figlie; do
    i=$((i + 1))
    [ -f "$CDIR/$c.md" ] || next "STOP — catena: la figlia $c (anello $i/$n) non esiste: la riga Figlie: e i file devono coincidere"
    cclosed "$CDIR/$c.md" || next "WAIT — catena: anello $i/$n ($c) non chiuso: il ciclo gira su quell'anello; la madre chiude dopo l'ultimo"
  done
  cz=$([ -f "$RUN/chiusura.txt" ] && tr -d '\r' < "$RUN/chiusura.txt" | head -1)
  case "$cz" in
    "") next "CHIUSURA — $n anelli chiusi: gate full sull'albero finale contro la base della madre (base.txt del primo anello), e2e via /dev-verify se le figlie hanno [e2e-locator:" ;;
    "Chiusura: IMPLEMENTED"*)
      b=$(printf '%s\n' "$cz" | sed -n 's/.*base \([0-9a-f]\{7,\}\).*/\1/p'); t=$(printf '%s\n' "$cz" | sed -n 's/.*tree \([0-9a-f]\{7,\}\).*/\1/p')
      { [ -f "$RUN/touched.txt" ] && tr -d '\r' < "$RUN/touched.txt"; } | grep . > "$TMP/chain-paths"
      if [ -n "$b" ] && [ -n "$t" ] && [ -s "$TMP/chain-paths" ]; then
        st=$(bash "$RS" check --base "$b" --tree "$t" --paths-file "$TMP/chain-paths" 2>/dev/null | sed -n 's/^Status: //p' | head -1)
      fi
      case "$st" in FRESH*) next "DONE — catena chiusa: $n anelli IMPLEMENTED e chiusura IMPLEMENTED sul codice attuale" ;; esac
      next "CHIUSURA — codice della catena cambiato dopo la chiusura (${st:-illeggibile}): si rifa'" ;;
    *) next "STOP — chiusura della catena non riuscita (${cz#Chiusura: }): vedi $RUN/log/*-chiusura.*; corretto il motivo, per rilanciarla rinomina $RUN/chiusura.txt in chiusura.txt.visto" ;;
  esac
}
[ -n "$figlie" ] && mother_next
[ $has_review -eq 1 ] && [ $has_plan -eq 0 ] && next "STOP — sezione di review senza piano: niente da pianificare sopra un'implementazione"
[ $has_plan -eq 0 ] && next "PLAN — nessun piano"
if [ "$plan" = DRAFT ] || [ "$plan" = NHD ]; then
  [ $has_review -eq 1 ] && next "STOP — piano riaperto ($plan_raw) dopo la review: la review esistente vale ancora? decisione tua"
  [ "$plan" = DRAFT ] && next "PLAN — piano in DRAFT"
  next "STOP — decisione aperta sul piano (Plan status: NEEDS HUMAN DECISION)"
fi
[ "$plan" = APPROVED ] || next "STOP — Plan status non riconosciuto: '$plan_raw'"
case "$basis" in
  "STALE (tests)") next "STOP — test di accettazione cambiati dopo la fase test-red (Approved basis: tests): una modifica ai test di accettazione e' una deviazione, decide una persona. Se voluta: bash $(mostra "$PC") basis $SPEC --write-tests registra l'impronta attuale; altrimenti riporta i test com'erano ($RUN/test-red/tests.txt)" ;;
  STALE*) next "STOP — spec o piano cambiati dopo l'approvazione ($basis): riapri il piano con /plan-review-cycle" ;;
esac
if [ $has_review -eq 0 ]; then
  test_red_gate
  json_stop
  last_ok implement && to_review "implementazione finita ($last_label)"
  next "IMPLEMENT — piano approvato, nessuna review"
fi
[ -z "$rstatus$fstatus" ] && next "REVIEW — sezione di review legacy senza righe di stato: la review fa un giro pieno"
case "$rstatus" in "NEEDS HUMAN DECISION"*) next "STOP — Review status: NEEDS HUMAN DECISION" ;; esac
[ "$contract_st" = STALE ] && next "REVIEW — spec o piano cambiati dopo la review (Reviewed contract diverso): giro a scope pieno"
tx=$(touched_excluded)
[ -n "$tx" ] && next "STOP — la review ha escluso un file toccato dalla feature: $tx. Rilancia /implementation-review-cycle <name>: legge touched.txt e rivede quel file (mai la promozione); oppure, se il file non e' della feature, toglilo da $RUN/touched.txt"
case "$rstatus" in NEEDS_CHANGES*)
  json_stop
  last_ok fix && to_review "correzione finita ($last_label)"
  budget_fix
  next "FIX — Review status: NEEDS_CHANGES" ;;
esac
case "$fstatus" in NEEDS_VERIFICATION*) next "REVIEW — NEEDS_VERIFICATION: un tentativo di promozione" ;; esac
case "$rstatus/$fstatus" in APPROVED*/IMPLEMENTED*)
  case "$code" in FRESH|LEGACY)
    fg=$(finalize_gap)
    [ -n "$fg" ] && next "REVIEW — $fg: nel nuovo regime lo stato finale lo firma $(mostra "$MAAT_SCRIPTS/finalize.sh") (fail-closed; vedi log/<label>.finalize)" ;;
  esac
  case "$code" in
    FRESH) next "DONE — codice uguale allo snapshot approvato" ;;
    LEGACY) next "DONE — sezione senza snapshot (legacy): freschezza del codice non verificabile" ;;
    *) next "REVIEW — codice cambiato dopo l'approvazione ($code)" ;;
  esac ;;
esac
next "STOP — combinazione non riconosciuta: Review status '${rstatus}' · Feature status '${fstatus}'"
