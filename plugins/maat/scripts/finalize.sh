#!/usr/bin/env bash
# finalize.sh — firma lo stato finale di una feature (harness-pt08): la review scrive il verdetto, lo script
# conferma `Feature status: IMPLEMENTED` solo con l'evidenza, altrimenti lo porta a NEEDS_VERIFICATION.
#
#   bash script/fic/finalize.sh [--level min|std|full|legacy] [--copertura <result.json>] <run-dir>
#
# <run-dir> = .claude/.ai-workflow/spec-<name>.run; la spec e' <run-dir senza .run>.md. run-phase.sh lo lancia
# dopo ogni review uscita 0 (esito in log/<label>.finalize), col livello in vigore.
#
# AGISCE solo se la sezione "## Review implementazione" (fuori dai recinti) ha `Review status: APPROVED` e
# `Feature status: IMPLEMENTED`: non promuove mai oltre il verdetto della review (obblighi, e2e e snapshot li
# conosce solo lei). Altrimenti non tocca nulla (uscita 4).
# CONFERMA IMPLEMENTED solo se:
#   1. ogni gate RICHIESTO — la lista di gates.sh, `maat_gate_richiesti <livello> <file di touched.txt>` da
#      .claude/maat.json: tests-<modulo> per ogni modulo con comando di test o con file toccati, controlli-<modulo>
#      per ogni modulo con controlli, lint se il livello lo prevede (build e' facoltativo, come nella review) — ha
#      evidence/<chiave ATTUALE>/<gate>.json con esito PASS e il report accanto, oppure SKIPPED (niente da
#      eseguire, col motivo: soddisfatto come nella review). NOT RUN (dichiarato: modulo senza test, voci saltate)
#      non soddisfa e non e' un errore: la firma e' al massimo NEEDS_VERIFICATION, col motivo «nessun test nel
#      modulo X, controlli verdi» (o «controlli saltati: …»). La cartella e' quella il cui argomenti.txt e'
#      <livello> + i file di touched.txt, e che `gates.sh --verify` dichiara FRESH; il campo "chiave" del JSON
#      deve essere il nome della cartella;
#   2. ogni controprova e' rossa su asserzione: se c'e' <run-dir>/counterproof/mutations.json, ogni suo id ha
#      <id>.json con esito rosso_asserzione (counterproof.sh, harness-pt05) — o rosso_generico (runner comando:
#      rosso senza report), che soddisfa ma e' una prova DEBOLE, dichiarata («prove deboli: …» nel dettaglio e una
#      riga «prova debole: …» su stdout); non_eseguita (modulo senza controprova) e' NOT RUN (dichiarato): come un
#      gate NOT RUN non soddisfa e non e' un errore (al massimo NEEDS_VERIFICATION); altrimenti ogni riga richiesta della
#      tabella delle evidenze della review che nomina una controprova (counterproof) ha Result PASS. Una voce con
#      "assorbita": true (L2, harness-pt11: file nuovo, rosso alla base con stub, verde dopo) vale solo se
#      `plan-check.sh l2` la conferma sul codice attuale (righe in <run-dir>/counterproof/l2.txt: impronta tests
#      FRESH, stub = simboli esportati, ogni simbolo in un test di accettazione) o se e' comunque rossa su asserzione;
#      altrimenti manca evidenza (NEEDS_VERIFICATION, non FAIL).
# VERDETTO = AND (harness-pt09): un gate richiesto FAIL (controlli-<modulo> compreso), o una controprova non rossa (rosso_import, rosso_raccolta,
# rosso_diverso, verde; o una riga di controprova della tabella con Result FAIL), e' FAIL anche con la review
# APPROVED: scrive `Review status: NEEDS_CHANGES`, `Feature status: PLANNED`, `Verification: PARTIAL (finalize.sh:
# <cosa>)` (la riga «APPROVED + any FAIL» della tabella di decisione della review; cycle-state.sh manda a FIX).
# ALTRIMENTI, se manca evidenza (assente, BLOCKED, chiave vecchia, controprova bloccata o senza risultato) scrive
# `Feature status: NEEDS_VERIFICATION` e `Verification: PARTIAL (finalize.sh: <cosa manca>)`. Confermando
# IMPLEMENTED, una `Verification:` provvisoria (review in parallelo con VERIFY) diventa `VERIFIED (finalize.sh: …)`.
# In tutti i casi scrive (o sostituisce) la riga `Finalize: <IMPLEMENTED|NEEDS_VERIFICATION|FAIL> — snapshot <x12> —
# <dettaglio> · <ora UTC>` sotto `Feature status:`, dove <x12> e' l'impronta (sha256, 12 cifre, spazi compressi) del
# `Reviewed snapshot:` verificato: cycle-state.sh (riga 13f) da' DONE solo se coincide con lo snapshot attuale.
# Le fine riga della spec restano quelle che erano (CRLF compreso).
# UNIONE (harness-pt09, --copertura <log/<label>.result.json della review>): il campo "copertura" (requisito -> ID
# di test, scritti dal reviewer senza risultati) si unisce MECCANICAMENTE ai risultati di VERIFY e diventa la
# tabella "Requirement evidence (finalize.sh: …)" sotto la riga Finalize: (sostituita a ogni firma). Risultati per
# FORMATO del report del modulo (campo `report`), mai per nome del gate: junit -> dal JUnit di tests-<modulo> nella
# cartella FRESH (node id pytest -> classname/name); vitest -> dal report del wrapper (test-fast.sh), che non ha un
# esito per test: FAIL dalle righe "FAIL <id>", PASS solo per un ID che e' un file di test con la riga "✓ <file>";
# nessuno -> nessun risultato per test. La radice del modulo davanti a un ID si toglie; il suffisso della tabella
# e' l'etichetta del gate. Controprove da counterproof/<id>.json. Un ID senza risultato -> requisito «non
# coperto»: e' un dato della tabella, non cambia il verdetto (che resta l'AND sopra). Senza --copertura nessuna
# tabella.
#
# Livello: --level, altrimenti la riga Test level: del piano (plan-check.sh contract), altrimenti legacy.
# Uscita: 0 IMPLEMENTED confermato · 1 NEEDS_VERIFICATION scritto · 3 FAIL scritto · 4 niente da firmare (spec
# intatta) · 2 uso.
# Stdout: una riga per ciò che manca, poi "finalize: esito=<IMPLEMENTED|NEEDS_VERIFICATION|FAIL|INVARIATO> — <…>".
# Variabili: FIC_GATES gates.sh da usare per --verify (default: accanto a questo) · FIC_GATES_ROOT e le altre
# di gates.sh passano per l'ambiente (FIC_GATES_ROOT e' anche il progetto di maat.json; MAAT_CONFIG lo sostituisce) ·
# FIC_GATES_HARNESS radice del plugin (default MAAT_ROOT; scripts/plan-check.sh, scripts/python.sh,
# scripts/lib/maat-conf.sh).
# Test: scripts/finalize.test.sh (accanto a questo).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_ROOT (plugin)
HROOT=${FIC_GATES_HARNESS:-$MAAT_ROOT}
GATES=${FIC_GATES:-$HERE/gates.sh}
PC="$HROOT/scripts/plan-check.sh"
usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
win() { maat_cygm "$1" 2>/dev/null || printf '%s' "$1"; }

level="" cop=""
while [ $# -gt 0 ]; do
  case $1 in
    --level) [ $# -ge 2 ] || usage; level=$2; shift 2 ;;
    --copertura) [ $# -ge 2 ] || usage; cop=$2; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "finalize: opzione sconosciuta: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
[ $# -eq 1 ] || usage
run=${1%/}
[ -d "$run" ] || { echo "finalize: run dir assente: $run" >&2; exit 2; }
SPEC="${run%.run}.md"
[ -f "$SPEC" ] || { echo "finalize: spec assente: $SPEC" >&2; exit 2; }
. "$HROOT/scripts/python.sh" || { echo "finalize: interprete Python non trovato" >&2; exit 2; }
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8 PYTHONDONTWRITEBYTECODE=1
py() { sed '1,/^#__PYTHON__$/d' "$0" | "$FIC_PY" - "$@"; }   # il codice arriva da una pipe: nessun file temporaneo
WSPEC=$(win "$SPEC")

# --- c'e' qualcosa da firmare? ---
st=$(py stato "$WSPEC" | tr -d '\r')
rs=${st%%|*} fs=${st#*|}
case "$rs/$fs" in
  APPROVED*/IMPLEMENTED*) ;;
  *) echo "finalize: esito=INVARIATO — niente da firmare (Review status '${rs}' · Feature status '${fs}')"; exit 4 ;;
esac

# --- livello in vigore e gate richiesti ---
if [ -z "$level" ]; then
  level=$(bash "$PC" contract "$SPEC" 2>/dev/null | tr -d '\r' | sed -n 's/^Test level: \([a-z]*\).*/\1/p' | head -1)
  case $level in min|std|full) ;; *) level=legacy ;; esac
fi
case $level in min|std|full|legacy) ;; *) echo "finalize: livello sconosciuto: $level (min|std|full|legacy)" >&2; exit 2 ;; esac
FILES=()
[ -f "$run/touched.txt" ] && mapfile -t FILES < <(tr -d '\r' < "$run/touched.txt" | sed 's|^\./||' | grep -v '^$' | LC_ALL=C sort -u)

# --- gate richiesti: la lista di gates.sh (maat_gate_richiesti, stessi livello e file), build escluso (facoltativo,
# come nella review). Per ogni gate il modulo; per ogni modulo il formato del report e la radice (unione). ---
export PROJECT_ROOT=${FIC_GATES_ROOT:-$PROJECT_ROOT}   # il progetto di gates.sh: <repo>/.claude/maat.json
REQ=() GM=() MODINFO=() conf_err=""
if . "$HROOT/scripts/lib/maat-conf.sh" 2>/dev/null && maat_conf_carica 2>/dev/null &&
   gl=$(maat_gate_richiesti "$level" ${FILES[@]+"${FILES[@]}"} 2>/dev/null | tr -d '\r'); then
  while IFS=$'\t' read -r g m t; do
    [ -n "$g" ] && [ "$t" != build ] || continue
    REQ+=("$g"); GM+=("$g=$m")
  done <<< "$gl"
  i=0
  while n=$(maat_conf "moduli.$i.nome" 2>/dev/null); do
    MODINFO+=("$n|$(maat_conf "moduli.$i.report" --default nessuno)|$(maat_conf "moduli.$i.radice")"); i=$((i + 1))
  done
else
  conf_err=$( { [ -n "${FIC_PY:-}" ] && "$FIC_PY" "$HROOT/scripts/maat-config.py" valida; } 2>&1 | tr -d '\r' | sed 's/^maat-config: //' | head -2 | tr '\n' ' ')
  conf_err=${conf_err:-lettore non utilizzabile}
fi

# --- evidenza alla chiave attuale: stessi argomenti di gates.sh (livello + touched.txt), poi --verify ---
want=$(printf '%s\n' "$level" ${FILES[@]+"${FILES[@]}"})
ev="" stale=""
while IFS= read -r d; do
  [ -n "$d" ] && [ -f "$d/argomenti.txt" ] || continue
  [ "$(tr -d '\r' < "$d/argomenti.txt")" = "$want" ] || continue
  if bash "$GATES" --verify "$d" >/dev/null 2>&1; then ev=$d; break; fi   # confronto della chiave
  stale="$stale $(basename "$d" | cut -c1-12)"
done < <(ls -dt "$run"/evidence/*/ 2>/dev/null | sed 's|/$||')

# Verdetto = AND (harness-pt09): ogni riga mancante e' "F|…" (gate FAIL, controprova non rossa: il codice e'
# sbagliato) o "N|…" (assente, BLOCKED, chiave vecchia: l'evidenza manca). Un F -> FAIL anche con la review APPROVED.
miss=() nfail=0 weak=()
# "W|…" = controprova rosso_generico: soddisfa (PASS) ma e' una prova DEBOLE, dichiarata nel dettaglio e su stdout
add() { [ -n "$1" ] || return 0; case $1 in F\|*) nfail=$((nfail + 1)) ;; W\|*) weak+=("${1#W|}"); return 0 ;; esac; miss+=("${1#[FN]|}"); }
if [ -n "$conf_err" ]; then
  add "N|gate richiesti non determinabili (maat.json: ${conf_err% })"
elif [ -z "$ev" ]; then
  add "N|nessuna evidenza del driver alla chiave attuale (livello $level, file di touched.txt)${stale:+ — chiavi vecchie:$stale}"
else
  while IFS= read -r m; do add "$m"; done < <(py gate "$(win "$ev")" ${GM[@]+"${GM[@]}"} | tr -d '\r')
fi
# L2 (harness-pt11): le mutazioni marcate "assorbita" (file nuovi) valgono solo se plan-check.sh l2 le conferma sul
# codice attuale (impronta tests FRESH, stub = simboli esportati, ogni simbolo in un test di accettazione).
l2f=""
if [ -f "$run/counterproof/mutations.json" ] && grep -q '"assorbita": *true' "$run/counterproof/mutations.json"; then
  l2f="$run/counterproof/l2.txt"
  bash "$PC" l2 "$SPEC" --run-dir "$run" 2>&1 | tr -d '\r' > "$l2f"
fi
while IFS= read -r m; do add "$m"; done < <(py controprove "$(win "$run")" "$WSPEC" "${l2f:+$(win "$l2f")}" | tr -d '\r')

# Unione requisito -> ID di test -> risultati (harness-pt09): la tabella Evidence della sezione, dopo la firma.
unisci() {
  [ -n "$cop" ] || return 0
  if [ ! -f "$cop" ]; then echo "finalize: copertura assente ($cop): nessuna tabella Evidence"; return 0; fi
  py unisci "$WSPEC" "$(win "$cop")" "$([ -n "$ev" ] && win "$ev")" "$(win "$run")" ${MODINFO[@]+"${MODINFO[@]}"} | tr -d '\r'
}

deboli=""
if [ ${#weak[@]} -gt 0 ]; then
  printf 'prova debole: %s\n' "${weak[@]}"
  deboli=$(printf '%s; ' "${weak[@]}"); deboli=" (prove deboli: ${deboli%; })"
fi
if [ ${#miss[@]} -eq 0 ]; then
  det="gate ${REQ[*]} alla chiave attuale (evidence/$(basename "$ev" | cut -c1-12)…), controprove rosse su asserzione$deboli"
  py scrivi "$WSPEC" IMPLEMENTED "$det" || { echo "finalize: spec non scrivibile" >&2; exit 2; }
  unisci
  echo "finalize: esito=IMPLEMENTED — confermato: $det"
  exit 0
fi
printf '%s\n' "${miss[@]}"
det=$(printf '%s; ' "${miss[@]}"); det=${det%; }$deboli
if [ $nfail -gt 0 ]; then
  py scrivi "$WSPEC" FAIL "$det" || { echo "finalize: spec non scrivibile" >&2; exit 2; }
  unisci
  echo "finalize: esito=FAIL — $det"
  exit 3
fi
py scrivi "$WSPEC" NEEDS_VERIFICATION "$det" || { echo "finalize: spec non scrivibile" >&2; exit 2; }
unisci
echo "finalize: esito=NEEDS_VERIFICATION — $det"
exit 1

#__PYTHON__
import datetime
import hashlib
import json
import os
import re
import sys

FENCE = re.compile(r"^[ \t]*(```|~~~)")


def leggi(spec):
    with open(spec, encoding="utf-8", newline="") as f:
        return f.read().splitlines(keepends=True)


def corpo(line):
    return line.rstrip("\r\n")


def review(lines):
    """Indici delle righe della sezione di review fuori dai recinti (come cycle-state.sh)."""
    out, inf, on = [], False, False
    for i, ln in enumerate(lines):
        t = corpo(ln)
        if FENCE.match(t):
            inf = not inf
            continue
        if inf:
            continue
        if not on and t.startswith("## Review implementazione"):
            on = True
        if on:
            out.append(i)
    return out


def primo(lines, idx, pref):
    return next((i for i in idx if corpo(lines[i]).startswith(pref)), None)


def valore(lines, idx, pref):
    i = primo(lines, idx, pref)
    return "" if i is None else corpo(lines[i])[len(pref):].strip()


def cmd_stato(spec):
    lines = leggi(spec)
    idx = review(lines)
    print("%s|%s" % (valore(lines, idx, "Review status:"), valore(lines, idx, "Feature status:")))


def load(p):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def cmd_gate(ev, *coppie):
    """Una riga per ogni gate richiesto (coppie «gate=modulo») che non soddisfa: PASS col report, o SKIPPED;
    chiave = cartella. NOT RUN (dichiarato: modulo senza test, voci saltate) non soddisfa ma non e' un errore:
    al massimo NEEDS_VERIFICATION, col motivo «nessun test nel modulo X, controlli verdi» (o «controlli saltati»).
    FAIL di qualunque gate richiesto, controlli-<modulo> compreso: F."""
    key = os.path.basename(ev.rstrip("/\\"))
    gm = [c.split("=", 1) for c in coppie]
    nomi = {g for g, _m in gm}

    def gate(g):
        d = load(os.path.join(ev, g + ".json"))
        if not isinstance(d, dict):
            return None, "N|%s: evidenza assente o illeggibile (evidence/%s)" % (g, key[:12])
        if d.get("chiave") != key:
            return None, "N|%s: chiave del JSON diversa dalla cartella dell evidenza" % g
        return d, None

    for g, m in gm:
        d, err = gate(g)
        if err:
            print(err)
            continue
        es = d.get("esito")
        if es == "PASS":
            rep = d.get("report")
            if not rep or not os.path.isfile(os.path.join(ev, rep)):
                print("N|%s: PASS senza il report del runner" % g)
        elif es == "NOT RUN":
            ctl = "controlli-" + m
            if g == "tests-" + m:
                c = gate(ctl)[0] if ctl in nomi else None
                ce = c.get("esito") if isinstance(c, dict) else None
                if ce == "PASS":
                    print("N|%s: NOT RUN (%s) — nessun test nel modulo %s, controlli verdi" % (g, d.get("motivo") or "dichiarato", m))
                elif ce == "NOT RUN":
                    print("N|%s: NOT RUN (%s) — nessun test nel modulo %s, controlli saltati: %s" % (
                        g, d.get("motivo") or "dichiarato", m, c.get("motivo") or "senza motivo"))
                else:
                    print("N|%s: NOT RUN (%s) — nessun test nel modulo %s" % (g, d.get("motivo") or "dichiarato", m))
            elif not (g == ctl and ("tests-" + m) in nomi and
                      (gate("tests-" + m)[0] or {}).get("esito") == "NOT RUN"):
                print("N|%s: NOT RUN (%s)" % (g, d.get("motivo") or "senza motivo"))
        elif es != "SKIPPED":
            print("%s|%s: %s (%s)" % ("F" if es == "FAIL" else "N", g, es,
                                      d.get("motivo") or d.get("riepilogo") or "senza motivo"))


# esiti di counterproof.sh (harness-pt05) che dicono "codice sbagliato": FAIL; bloccato e assente: evidenza mancante
CP_FAIL = ("rosso_import", "rosso_raccolta", "rosso_diverso", "verde")
# rosso_generico (runner comando): rosso senza report, PASS ma prova DEBOLE -> soddisfa, e si dichiara (riga W|);
# non_eseguita (modulo senza controprova): NOT RUN dichiarato -> non soddisfa e non e' un errore (riga N|)
CP_DEBOLE = "rosso_generico"
CP_NON_ESEGUITA = "non_eseguita"


def non_eseguita(r):
    m = (r.get("motivo") or "").strip()
    return m if m.startswith("NOT RUN") else "NOT RUN (dichiarato)" + (": " + m if m else "")


def cmd_controprove(run, spec, l2file=""):
    mj = os.path.join(run, "counterproof", "mutations.json")
    if os.path.isfile(mj):
        lst = load(mj)
        if not isinstance(lst, list):
            print("N|controprove: mutations.json illeggibile")
            return
        l2 = {}
        if l2file and os.path.isfile(l2file):
            with open(l2file, encoding="utf-8", errors="replace") as f:
                for ln in f:
                    m = re.match(r"^L2 (\S+): (OK|NO)(?: — (.*))?$", ln.strip())
                    if m:
                        l2[m.group(1)] = (m.group(2), m.group(3) or "")
        for e in lst:
            mid = e.get("id") if isinstance(e, dict) else None
            if not mid:
                print("N|controprove: voce senza id in mutations.json")
                continue
            r = load(os.path.join(run, "counterproof", str(mid) + ".json"))
            if e.get("assorbita") is True:  # L2: vale solo se plan-check.sh l2 la conferma sul codice attuale
                st = l2.get(str(mid))
                if (st and st[0] == "OK") or (isinstance(r, dict) and r.get("esito") == "rosso_asserzione"):
                    continue
                print("N|controprova %s: assorbita (L2) non valida: %s" % (mid, st[1] if st else "condizioni non verificate (plan-check.sh l2)"))
                continue
            if not isinstance(r, dict):
                print("N|controprova %s: risultato assente (counterproof.sh non eseguito o incompleto)" % mid)
            elif r.get("esito") == CP_DEBOLE:
                print("W|controprova %s: rosso_generico, prova debole (%s)" % (mid, r.get("motivo") or "nessuna asserzione verificata"))
            elif r.get("esito") == CP_NON_ESEGUITA:
                print("N|controprova %s: %s" % (mid, non_eseguita(r)))
            elif r.get("esito") != "rosso_asserzione":
                print("%s|controprova %s: %s (%s)" % ("F" if r.get("esito") in CP_FAIL else "N", mid,
                                                      r.get("esito"), r.get("motivo") or ""))
        return
    lines = leggi(spec)
    for i in review(lines):
        t = corpo(lines[i]).strip()
        if not t.startswith("|"):
            continue
        cells = [c.strip() for c in t.strip("|").split("|")]
        if len(cells) < 4 or not re.search(r"counterproof|controprov", cells[0], re.I):
            continue
        if cells[1].lower() == "no":
            continue
        if not cells[3].upper().startswith("PASS"):
            print("%s|controprova (tabella della review) %s: %s" % ("F" if cells[3].upper().startswith("FAIL") else "N",
                                                                    cells[0], cells[3] or "senza esito"))


def cmd_scrivi(spec, stato, det):
    lines = leggi(spec)
    idx = review(lines)
    fsi = primo(lines, idx, "Feature status:")
    if fsi is None:
        sys.exit(1)
    eol = lines[fsi][len(corpo(lines[fsi])):] or "\n"
    ora = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    det = " ".join(det.split())
    ver = None
    if stato in ("NEEDS_VERIFICATION", "FAIL"):
        # FAIL (harness-pt09, verdetto = AND): la riga di decisione "APPROVED + un gate FAIL" della review
        lines[fsi] = "Feature status: %s" % ("PLANNED" if stato == "FAIL" else stato) + eol
        if stato == "FAIL":
            ri = primo(lines, idx, "Review status:")
            if ri is not None:
                lines[ri] = "Review status: NEEDS_CHANGES" + lines[ri][len(corpo(lines[ri])):]
        ver = "Verification: PARTIAL (finalize.sh: %s)" % det
    elif "provvisori" in valore(lines, idx, "Verification:").lower():
        # verdetto provvisorio della review in parallelo con VERIFY (harness-pt09): confermato dall'unione
        ver = "Verification: VERIFIED (finalize.sh: %s)" % det
    if ver is not None:
        vi = primo(lines, idx, "Verification:")
        if vi is None:
            lines.insert(fsi + 1, ver + eol)
            idx = review(lines)
        else:
            lines[vi] = ver + lines[vi][len(corpo(lines[vi])):]
    # impronta del Reviewed snapshot verificato: la stessa di snap_fp in cycle-state.sh (riga 13f)
    snap = re.sub(r"[ \t]+", " ", valore(lines, idx, "Reviewed snapshot:")).strip(" ")
    sfp = hashlib.sha256(snap.encode("utf-8")).hexdigest()[:12]
    fin = "Finalize: %s — snapshot %s — %s · %s" % (stato, sfp, det, ora) + eol
    old = [i for i in idx if corpo(lines[i]).startswith("Finalize:")]
    for i in reversed(old):
        del lines[i]
    fsi = primo(lines, review(lines), "Feature status:")
    lines.insert(fsi + 1, fin)
    salva(spec, lines)


def salva(spec, lines):
    tmp = spec + ".finalize.tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        f.write("".join(lines))
    os.replace(tmp, spec)


# --- unione requisito -> ID di test -> risultati di VERIFY (harness-pt09) ---
EV_HEAD = "Requirement evidence (finalize.sh"
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def risultati_junit(ev, gate):
    """{(classname, name): esito} dal JUnit di un gate (modulo con report junit) all evidenza FRESH; vuoto se non c e."""
    import xml.etree.ElementTree as ET
    out = {}
    d = load(os.path.join(ev, gate + ".json")) if ev else None
    if not isinstance(d, dict) or not d.get("report"):
        return out
    try:
        root = ET.parse(os.path.join(ev, d["report"])).getroot()
    except (OSError, ET.ParseError):
        return out
    for tc in root.iter("testcase"):
        if tc.find("failure") is not None or tc.find("error") is not None:
            es = "FAIL"
        elif tc.find("skipped") is not None:
            es = "SKIPPED"
        else:
            es = "PASS"
        out[(tc.get("classname") or "", tc.get("name") or "")] = es
    return out


def senza_radice(t, radice):
    r = radice.replace("\\", "/").strip("/")
    while r.startswith("./"):
        r = r[2:]
    if r and r != "." and t.startswith(r + "/"):
        return t[len(r) + 1:]
    return t


def chiave_junit(tid, radice):
    """node id pytest (tests/x.py::C::t, anche con la radice del modulo davanti) -> (classname, name) del JUnit."""
    t = senza_radice(tid.strip().replace("\\", "/"), radice)
    parti = t.split("::")
    if len(parti) < 2 or not parti[0].endswith(".py"):
        return None
    return (".".join([parti[0][:-3].replace("/", ".")] + parti[1:-1]), parti[-1])


def log_vitest(ev, gate):
    d = load(os.path.join(ev, gate + ".json")) if ev else None
    if not isinstance(d, dict) or not d.get("report"):
        return []
    try:
        with open(os.path.join(ev, d["report"]), encoding="utf-8", errors="replace") as f:
            return [" ".join(ANSI.sub("", l).split()) for l in f.read().splitlines()]
    except OSError:
        return []


def esito_vitest(righe, tid, radice):
    """Il report del wrapper (test-fast.sh) non ha un esito per test: FAIL dalle righe "FAIL <id>", PASS solo a
    livello di file (riga "✓ <file>"). Nient altro e' un risultato. La radice del modulo davanti all'ID si toglie."""
    t = senza_radice(" ".join(tid.strip().replace("\\", "/").split()), radice)
    fine = r"(\s|$)"
    if any(re.match(r"(FAIL|❯|×)\s+" + re.escape(t) + fine, l) for l in righe):
        return "FAIL"
    if " > " not in t and any(re.match(r"✓\s+" + re.escape(t) + fine, l) for l in righe):
        return "PASS"
    return None


def cmd_unisci(spec, cop, ev, run, *moduli):
    """moduli: «nome|report|radice»; il formato del report (junit, vitest, nessuno) dice come leggere i risultati
    del gate tests-<nome>, mai il nome del gate. Un modulo con report nessuno non da' risultati per test."""
    obj = load(cop)
    cov = obj.get("copertura") if isinstance(obj, dict) else None
    if not isinstance(cov, list):
        print("finalize: nessuna mappa requisito→ID (campo copertura) in %s: nessuna tabella Evidence" % cop)
        return
    mods = [x.split("|", 2) for x in moduli if x.count("|") >= 2]
    ju = [("tests-" + n, rad, risultati_junit(ev, "tests-" + n)) for n, rep, rad in mods if rep == "junit"]
    vi = [("tests-" + n, rad, log_vitest(ev, "tests-" + n)) for n, rep, rad in mods if rep == "vitest"]

    def risultato(tid):
        for g, rad, res in ju:
            k = chiave_junit(tid, rad)
            if k is None:
                continue
            if k in res:
                return res[k] + " (%s)" % g
        if any(chiave_junit(tid, rad) is not None for _g, rad, _r in ju):
            return None
        r = load(os.path.join(run, "counterproof", tid.strip() + ".json")) if re.match(r"^[\w.-]+$", tid.strip()) else None
        if isinstance(r, dict) and r.get("esito"):
            es = r["esito"]
            if es == CP_DEBOLE:
                return "PASS (controprova %s, prova debole)" % es
            if es == CP_NON_ESEGUITA:
                return "NOT RUN (controprova %s)" % es
            return "%s (controprova %s)" % ("PASS" if es == "rosso_asserzione" else "BLOCKED" if es == "bloccato" else "FAIL", es)
        for g, rad, righe in vi:
            es = esito_vitest(righe, tid, rad)
            if es is not None:
                return es + " (%s)" % g
        return None

    cella = lambda s: " ".join(str(s).split()).replace("|", "\\|")
    righe, scoperti = [], 0
    for voce in cov:
        if not isinstance(voce, dict):
            continue
        ids = [str(i) for i in voce.get("test") or [] if str(i).strip()]
        ris = [(i, risultato(i)) for i in ids]
        senza = [i for i, r in ris if r is None]
        if not ids:
            evid = "non coperto (nessun ID di test)"
        elif senza:
            evid = "non coperto (senza risultato: %s)" % "; ".join(senza)
        else:
            evid = " · ".join("%s → %s" % (i, r) for i, r in ris)
        scoperti += evid.startswith("non coperto")
        righe.append("| %s | %s | %s |" % (cella(voce.get("requisito", "")), cella("; ".join(ids) or "—"), cella(evid)))

    lines = leggi(spec)
    idx = review(lines)
    fi = primo(lines, idx, "Finalize:")
    if fi is None:
        return
    eol = lines[fi][len(corpo(lines[fi])):] or "\n"
    old = primo(lines, idx, EV_HEAD)
    if old is not None:   # la tabella di un finalize precedente: intestazione e righe "|" che la seguono
        j = old + 1
        while j < len(lines) and corpo(lines[j]).lstrip().startswith("|"):
            j += 1
        del lines[old:j]
        fi = primo(lines, review(lines), "Finalize:")
    k12 = os.path.basename(ev.rstrip("/\\"))[:12] if ev else "nessuna chiave attuale"
    blocco = ["%s: requisito → ID di test → risultato di VERIFY, evidence/%s)" % (EV_HEAD, k12),
              "| Requirement | Test IDs | Evidence |", "|---|---|---|"] + righe
    lines[fi + 1:fi + 1] = [b + eol for b in blocco]
    salva(spec, lines)
    print("finalize: Evidence composta — %d requisiti, %d non coperti" % (len(righe), scoperti))


sys.stdout.reconfigure(encoding="utf-8")
{"stato": cmd_stato, "gate": cmd_gate, "controprove": cmd_controprove, "scrivi": cmd_scrivi,
 "unisci": cmd_unisci}[sys.argv[1]](*sys.argv[2:])
