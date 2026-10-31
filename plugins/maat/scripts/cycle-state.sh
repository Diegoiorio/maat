#!/usr/bin/env bash
# cycle-state.sh — the resume table of /full-implementation-cycle, computed and not interpreted.
#
#   cycle-state.sh <.claude/.ai-workflow/spec-<name>.md>
#
# Prints the lines it read and two final lines:
#   State: <hash12>   fingerprint of the spec's state lines (for the orchestrator's anti-loop guard)
#   Next: PLAN | IMPLEMENT | REVIEW | FIX | DONE | STOP — <reason>   (chains: also WAIT and CHIUSURA, below)
# Exit 0 (also for STOP: it is an answer) · 2 usage.
#
# Reads: the plan with plan-check.sh (contract for Plan status, basis for "Approved basis"); the
# "## Review implementazione" section outside the fences; for IMPLEMENTED the code with review-surface.sh check
# on the "Reviewed snapshot" and on the manifest; the run dir <spec without .md>.run/log/ for the outcome of the last
# phase (<label>.esito, written by run-phase.sh: result line + "state=<hash>" at the end-of-phase state).
#
# Languages (Maat 1.3.0): the result line is "PHASE RESULT <phase>: OK|STOP — …" (written from 1.3.0 on) or
# "ESITO FASE <phase>: OK|STOP — …" (old run dirs): both are read. Likewise "## Implementation review" next to
# "## Review implementazione" (both in one spec: STOP, the same section in two languages), "Children:" next to
# "Figlie:" (the first line wins), "defensive: " next to "difensiva: ", "none" next to "nessuno". The lines that
# enter State are not translated: for identical input State is byte for byte the one of 1.2.x.
#
# STRUCTURED OUTCOME (harness-pt08): if the last implement/fix phase has log/<label>.result.json (written by
# run-phase.sh only if valid against script/fic/schemas/phase-result.schema.json) the outcome is read from there, with the
# rules in code: non-empty deviazioni[] -> STOP regardless of "esito" (unless ALL of them start with
# "difensiva: ": purely defensive deviations do not stop, the review judges them); bloccato_su other than "nessuno" ->
# STOP; otherwise "esito". An unreadable result.json -> STOP. The phase is OK only if BOTH the result.json
# AND the ESITO line of <label>.esito are (the most conservative; .esito is the authority: run-phase.sh already writes it
# as STOP when the JSON is). Without result.json (old run dirs, --inline) the ESITO line alone decides, as before.
# A STOP result.json stops the cycle (row 7s/11s) until the spec changes; to resume after the human
# decision, rename the file to <label>.result.json.visto: the ESITO line decides (STOP -> the phase is relaunched, in
# completion). A deviation is accepted by reopening the plan, not by renaming.
# NEW REGIME (run dir with evidence/ or with at least one *.result.json, even renamed .result.json.visto): DONE
# (row 13) only with a "Finalize: IMPLEMENTED — snapshot <x12> — … · <UTC time>" line in the review section,
# where <x12> is the fingerprint of the CURRENT "Reviewed snapshot:" (the snapshot finalize.sh signed: a manual
# or --inline review that changes the snapshot without relaunching finalize does not pass) and the time is not older
# than the last review launched (log/<n>-*review*.jsonl, if any); otherwise REVIEW (13f). Old run dirs
# give DONE as before.
# FIX BUDGET (row 11b): computed here from "Review rounds: n/3 · post-approval NEEDS_CHANGES: k/1", not
# read by the LLM.
#
# TABLE — the first matching row wins. It is the authoritative source: SKILL.md points here.
#   1b (1.3.0, above every other row, chains included) both "## Review implementazione" and "## Implementation
#      review" in the spec → STOP (the same section in two languages)
#   1  review section without a plan                            → STOP (nothing to plan on top of)
#   2  no plan, or Plan status DRAFT without a review             → PLAN
#   3  plan DRAFT or NEEDS HUMAN DECISION with a review          → STOP (plan reopened after the review)
#   4  Plan status NEEDS HUMAN DECISION                           → STOP (open decision)
#   5  non-standard Plan status                                   → STOP
#   6  Approved basis STALE (spec or plan changed after approval) → STOP: reopen the plan. STALE (tests):
#      an acceptance test file changed after test-red (harness-pt11) → STOP (deviation, human decision)
#   7t (harness-pt11) plan in FORMAT 2, no review, no implement/fix launched, "tests" fingerprint not
#      recorded in the Approved basis → TEST-RED; if the last test-red has an .esito with unchanged state (STOP, or
#      closed without recording the tests) → STOP with that line. Format 1: never. A format-2 cycle that already went
#      through implement without test-red (started before the rule) goes on as before.
#   7s no review, last implement/fix with a STOP result.json (rules above) and unchanged state → STOP
#   7  no review: last implement/fix launched = "implement", outcome OK, unchanged state → REVIEW,
#      otherwise IMPLEMENT (a review launched that never started does not count: it did not change the spec)
#      (full or completion is decided by the implement worker). ATTRIBUTION (also row 11): moving to
#      REVIEW requires the <label>.post-tree of that phase and no open .pre-tree of a lower label;
#      otherwise STOP (attribution not measured: the review would not know which files belong to the feature).
#   8  legacy review section without state lines                 → REVIEW (the review does a full round)
#   9  Review status NEEDS HUMAN DECISION                         → STOP
#   10 Reviewed contract different from the current basis         → REVIEW (full-scope round; holds also
#      with NEEDS_CHANGES: those findings were on the old contract)
#   10b a touched.txt path listed under "Excluded:" in the manifest → STOP (the review excluded code
#      of the feature). Rows 10-13 do not go through attribution again: a review already happened, and
#      run-phase closes the open .pre-tree files at the start of every code phase, review included.
#   11s NEEDS_CHANGES, last implement/fix with a STOP result.json and unchanged state → STOP
#   11 NEEDS_CHANGES: last implement/fix launched = "fix", outcome OK, unchanged state → REVIEW, otherwise
#   11b FIX only if n < 3 and k < 1 (Review rounds); budget exhausted or unreadable line → STOP
#   12 Feature status NEEDS_VERIFICATION                          → REVIEW (one promotion attempt)
#   13f new regime, APPROVED + IMPLEMENTED without a "Finalize: IMPLEMENTED" on the current snapshot that is recent
#       → REVIEW (fail-closed)
#   13 APPROVED + IMPLEMENTED: code FRESH → DONE · STALE/UNKNOWN → REVIEW · no snapshot (legacy) → DONE
#      with a note. EXCLUDED-CHANGED does not change the outcome: the lines are printed for the report.
#   14 anything else                                              → STOP with the lines read
#   0  (applies above every row leading to PLAN/IMPLEMENT/REVIEW/FIX, never on DONE or on another STOP)
#      <run-dir>/harness.fp not EQUAL to the current fingerprint (run-phase.sh --harness-fp-confronta: CAMBIATO,
#      FORMATO-PRECEDENTE, ILLEGGIBILE or NON-CALCOLABILE) → STOP with the reason, the date and the remedy. Without harness.fp
#      (cycle started before the rule) no check.
#
# CHAINS (harness-pt12). A MOTHER has the line "Figlie: spec-<nome>-1-…, -2-…" above the plan; a RING is a
# spec listed by a mother in the same folder. A spec outside a chain sees none of this.
#   C1 mother: first child missing → STOP; the first one not closed (plan-check.sh closed: APPROVED + IMPLEMENTED
#      and a fresh Finalize: IMPLEMENTED on the current Reviewed snapshot, no legacy fallback) → WAIT
#   C2 mother, all rings closed: <mother's run-dir>/chiusura.txt missing → CHIUSURA (code phase of
#      run-phase.sh, label NN-chiusura: full gates on the final tree against the base of the first ring, e2e
#      via /dev-verify if the children have [e2e-locator:); "Chiusura: IMPLEMENTED — base <b> · tree <t> …" and
#      code FRESH (review-surface.sh check on the files of the rings' touched.txt) → DONE, otherwise
#      CHIUSURA; failed closing → STOP with the recovery. Only this way is the mother IMPLEMENTED.
#   C3 ring k>1, towards PLAN: the plan of k-1 is not APPROVED → WAIT (L6: the plan starts once the plan of k-1 is APPROVED)
#   C4 ring k>1, towards IMPLEMENT: k-1 not closed → WAIT; no code phase of k yet (no .pre-tree)
#      and working tree different from the last .post-tree of k-1, or .post-tree missing → STOP (human changes that
#      the ring would claim as its own). Row 6 (Approved basis, which for a ring includes mother, plan of k-1,
#      interface and touched: plan-check.sh basis) and the others apply as for any spec.
#   Prints for a ring k>1: "Anelli precedenti: <files of their touched.txt>" (same chain: neither other flows
#   nor mixed ones, no completion), "Base anello: <.post-tree of k-1>" (never HEAD) and "Diff anello: <path>" (only the
#   paths changed since the ring's base: the surface of its review).
# Left to the orchestrator: a phase still running (.running without .exit), a PHASE RESULT … STOP,
# and «NEEDS_VERIFICATION obtained in THIS invocation → STOP». IMPLEMENTED is signed by script/fic/finalize.sh
# (run-phase.sh, after every review): here we read the line it left.
#
# Test: cycle-state.test.sh.

set -uo pipefail
set -f

[ $# -eq 1 ] && [ -f "$1" ] || { echo "uso: $0 <spec-<name>.md>" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_SCRIPTS (plugin) and PROJECT_ROOT (working folder)

# WRAPPER (harness-pt14): the same table is ported to script/fic/driver.py (`driver.py next`). It is used
# instead of the code below only if the certificate script/fic/driver.equiv carries the current hash of driver.py and of
# THIS file (equivalence proved by `driver.py equiv --certifica` on the real run directories); otherwise this
# script stays standalone. FIC_DRIVER=0 forces the code below, FIC_DRIVER=1 the driver (tests); FIC_DRIVER_PY and
# FIC_DRIVER_CERT replace driver and certificate (tests). Driver failed or without a Next line -> code below.
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
# absolute path of a harness script in messages: C:/… on Windows (cygpath -m), like driver.py (mostra)
mostra() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
SPEC="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
RUN="${SPEC%.md}.run"
cd "$(dirname "$SPEC")" || exit 2
TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

# --- plan ---
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
  tests_st=$(printf '%s\n' "$basis_out" | tr -d '\r' | sed -n 's/^Tests status: //p')   # format 2 only
fi
fmt2=0; printf '%s\n' "$contract" | tr -d '\r' | grep -qx 'Plan format: 2' && fmt2=1

# --- review section: lines outside the fences, from "## Review implementazione" down ---
tr -d '\r' < "$SPEC" | awk '
  { isf = ($0 ~ /^[ \t]*(```|~~~)/) }
  isf { inf = !inf; next }
  inf { next }
  !r && /^## (Review implementazione|Implementation review)/ { r = 1 }
  r { print }' > "$TMP/review"
has_review=0; [ -s "$TMP/review" ] && has_review=1
# both headings (1.3.0): the same section in two languages, a reader would take only one of them -> STOP below
review_both=0
grep -q '^## Review implementazione' "$TMP/review" && grep -q '^## Implementation review' "$TMP/review" && review_both=1
line() { sed -n "s/^$1:[[:space:]]*//p" "$TMP/review" | head -1; }
rstatus=$(line "Review status"); fstatus=$(line "Feature status")
snap=$(line "Reviewed snapshot"); rcontract=$(line "Reviewed contract"); rounds=$(line "Review rounds")
# Manifest: the paths under "Scope:" and under "Excluded:", up to an empty line or the end of the block.
list_of() { awk -v h="$1" '
  $0 == h ":" { on = 1; next }
  on && (/^[ \t]*$/ || /^Excluded:/ || /^Scope:/ || /^<\/details>/) { exit }
  on { print }' "$TMP/review"; }
# Excluded lines may carry a note after « — » (e.g. «stessa catena, anello precedente»): only the path is compared.
list_of Scope > "$TMP/scope"; list_of Excluded | sed "s/ — .*//" > "$TMP/excl"

# --- chains (harness-pt12): mother (Figlie: line) or ring (a mother in the same folder lists it) ---
chead() { # <file> <literal> [<English literal>]: the value of the first "<literal> …" line above the plan, outside
  # the fences; with two literals the first line that has either wins (Figlie:/Children:, 1.3.0)
  tr -d '\r' < "$1" | awk -v l="$2" -v l2="${3:-$2}" '{ isf = ($0 ~ /^[ \t]*(```|~~~)/) } isf { inf = !inf; next } inf { next }
    /^## (Piano di implementazione|Review implementazione|Implementation plan|Implementation review)/ { exit }
    index($0, l) == 1 || index($0, l2) == 1 { k = (index($0, l) == 1) ? l : l2; v = substr($0, length(k) + 1); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }'
}
cfiglie() { chead "$1" "Figlie:" "Children:" | grep -o 'spec-[A-Za-z0-9._-]*' | sed 's/\.md$//; s/\.$//' || true; }
cclosed() { # <spec>: closed = plan-check.sh closed (a single criterion: fresh Finalize: IMPLEMENTED, no legacy)
  bash "$PC" closed "$1" >/dev/null 2>&1
}
cpost() { # <run-dir>: the tree of the last .post-tree (highest-numbered label)
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
  done < <(find "$CDIR" -maxdepth 1 -type f -name 'spec-*.md' -exec grep -lE '^(Figlie|Children):' {} + 2>/dev/null | LC_ALL=C sort)
fi
if [ -n "$ring_prev" ]; then
  ring_base=$(cpost "${ring_prev%.md}.run")   # BASE-ANELLO: the recorded .post-tree of k-1, never HEAD
  ring_now=$(bash "$RS" tree 2>/dev/null)
fi
# the mother: state of each ring and of the closing (goes into State; empty outside a chain)
chain_state=""
if [ -n "$figlie" ]; then
  for c in $figlie; do
    if [ ! -f "$CDIR/$c.md" ]; then chain_state="$chain_state$c assente;"
    elif cclosed "$CDIR/$c.md"; then chain_state="$chain_state$c chiuso;"
    else chain_state="$chain_state$c aperto;"; fi
  done
  chain_state="$chain_state$([ -f "$RUN/chiusura.txt" ] && tr -d '\r' < "$RUN/chiusura.txt" | head -1)"
fi

# --- contract recorded by the review ---
hexes() { printf '%s\n' "$1" | grep -o 'spec [0-9a-f]\{12\}\|plan [0-9a-f]\{12\}' | tr '\n' ' '; }
contract_st=n/a
if [ $has_review -eq 1 ]; then
  if [ -z "$rcontract" ]; then contract_st=LEGACY
  elif [ "$(hexes "$rcontract")" = "$(hexes "$basis_cur")" ]; then contract_st=FRESH
  else contract_st=STALE; fi
fi

# --- state fingerprint (everything a phase can change in the spec) ---
STATE=$( { echo "$plan_raw"; printf '%s\n' "$basis_out"; grep -E '^(Review status|Feature status|Verification|Reviewed snapshot|Reviewed contract|Review rounds):' "$TMP/review"; cat "$TMP/scope" "$TMP/excl"; printf '%s' "$chain_state"; } | sha256sum | cut -c1-12)

# --- last CODE phase that writes (implement/fix) in the run dir ---
# Labels come from .jsonl (phases launched by run-phase) and from .esito (also the --inline phases, which
# have no .jsonl).
# Not the very last phase: a review launched and never started (lock occupato, missing guard,
# dead session) leaves its .jsonl but does not change the spec, and must not cause the implement or
# the fix already finished to be repeated. A review that WROTE changes the State, and the comparison with state= excludes it.
last_label="" last_esito="" last_state=""
if [ -d "$RUN/log" ]; then
  last_label=$(ls "$RUN/log" 2>/dev/null | sed -n 's/^\([0-9][0-9]*-[^.]*\)\.\(jsonl\|esito\)$/\1/p' | grep -E 'implement|fix' | sort -u | sort -t- -k1,1n | tail -1)
  if [ -n "$last_label" ] && [ -f "$RUN/log/$last_label.esito" ]; then
    last_esito=$(tr -d '\r' < "$RUN/log/$last_label.esito" | sed -n '1p')
    last_state=$(tr -d '\r' < "$RUN/log/$last_label.esito" | sed -n 's/^state=//p')
  fi
fi
# --- structured outcome (harness-pt08): result.json of the last implement/fix, rules in code ---
json_esito="" json_why=""
if [ -n "$last_label" ] && [ -f "$RUN/log/$last_label.result.json" ]; then
  FIC_PY=""; . "$HERE/python.sh" 2>/dev/null
  jr=$("${FIC_PY:-false}" -c 'import json, sys
sys.stdout.reconfigure(encoding="utf-8")
d = json.load(open(sys.argv[1], encoding="utf-8"))
one = lambda s: " ".join(str(s).split())[:300]
dev = [one(x) for x in (d.get("deviazioni") or []) if str(x).strip()]
bs = one(d.get("bloccato_su") if d.get("bloccato_su") is not None else "(assente)")
if [x for x in dev if not x.startswith(("difensiva: ", "defensive: "))]:
    print("STOP|deviazioni dichiarate (%d): %s" % (len(dev), one("; ".join(dev))))
elif bs.lower() not in ("nessuno", "none"):
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
# last_ok <phase>: the last implement/fix launched is <phase>, it finished OK (ESITO line AND, if present, result.json:
# the most conservative wins), and the spec has not changed since
last_ok() {
  case "$last_label" in *"$1"*) ;; *) return 1 ;; esac
  case "$last_esito" in "PHASE RESULT $1: OK"*|"ESITO FASE $1: OK"*) ;; *) return 1 ;; esac   # both languages (1.3.0)
  [ -z "$json_esito" ] || [ "$json_esito" = OK ] || return 1
  [ "$last_state" = "$STATE" ]
}
# json_stop: rows 7s/11s — STOP result.json and spec unchanged since → STOP with the recovery.
json_stop() {
  [ "$json_esito" = STOP ] && [ -n "$last_state" ] && [ "$last_state" = "$STATE" ] || return 0
  next "STOP — $last_label: $json_why (regola in codice su $RUN/log/$last_label.result.json). Decidi; per riprendere dopo la decisione (es. migrazione applicata) rinomina quel file in $last_label.result.json.visto: decide la riga ESITO di $last_label.esito (STOP -> la fase si rilancia, in completion). Una deviazione si accetta riaprendo il piano (spec cambiata), non con la rinomina"
}
# finalize_gap: row 13f — in the new regime prints why IMPLEMENTED is not signed by finalize.sh.
new_regime=0
[ -d "$RUN/evidence" ] && new_regime=1
ls "$RUN/log" 2>/dev/null | grep -q '\.result\.json\(\.visto\)\{0,1\}$' && new_regime=1
# snap_fp <value of Reviewed snapshot:>: 12-digit fingerprint, the same one finalize.sh writes in "snapshot <x>"
# (spaces and tabs squeezed, ends trimmed, sha256).
snap_fp() { printf '%s' "$1" | tr -s ' \t' '  ' | sed 's/^ //; s/ $//' | tr -d '\n' | sha256sum | cut -c1-12; }
finalize_gap() {
  local f fs ts rl rt
  [ $new_regime -eq 1 ] || return 0
  f=$(line "Finalize")
  case "$f" in IMPLEMENTED*) ;; "") echo "IMPLEMENTED non firmato da finalize.sh (nessuna riga Finalize:)"; return ;;
    *) echo "IMPLEMENTED non firmato da finalize.sh (Finalize: $f)"; return ;; esac
  fs=$(printf '%s\n' "$f" | sed -n 's/.*snapshot \([0-9a-f]\{12\}\).*/\1/p' | head -1)
  [ -n "$fs" ] || { echo "riga Finalize: senza l'impronta dello snapshot firmato"; return; }
  [ "$fs" = "$(snap_fp "$snap")" ] || { echo "Finalize: firmata su un altro snapshot (snapshot $fs), non sul Reviewed snapshot attuale"; return; }   # snapshot comparison
  ts=$(printf '%s\n' "$f" | grep -o '[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z' | tail -1)
  ts=$( [ -n "$ts" ] && date -u -d "$ts" +%s 2>/dev/null )
  [ -n "$ts" ] || { echo "riga Finalize: senza un'ora leggibile"; return; }
  rl=$(ls "$RUN/log" 2>/dev/null | sed -n 's/^\([0-9][0-9]*-[^.]*review[^.]*\)\.jsonl$/\1/p' | sort -t- -k1,1n | tail -1)
  [ -n "$rl" ] || return 0
  rt=$(date -r "$RUN/log/$rl.jsonl" +%s 2>/dev/null)
  [ -n "$rt" ] || { echo "ora dell'ultima review ($rl) non leggibile"; return; }
  [ "$ts" -ge "$rt" ] || echo "Finalize: piu' vecchia dell'ultima review lanciata ($rl)"
}
# budget_fix: row 11b — a fix only if n < 3 and k < 1 (the section does not say what kind of round the last one was).
budget_fix() {
  local n k
  n=$(printf '%s\n' "$rounds" | sed -n 's|^\([0-9][0-9]*\)/3.*|\1|p')
  k=$(printf '%s\n' "$rounds" | sed -n 's|.*post-approval NEEDS_CHANGES:[[:space:]]*\([0-9][0-9]*\)/1.*|\1|p')
  [ -n "$n" ] && [ -n "$k" ] || next "STOP — budget dei fix non calcolabile: riga 'Review rounds: n/3 · post-approval NEEDS_CHANGES: k/1' assente o illeggibile ('${rounds}')"
  [ "$n" -lt 3 ] && [ "$k" -lt 1 ] || next "STOP — budget dei fix esaurito (Review rounds $n/3 · post-approval NEEDS_CHANGES $k/1): un fix che nessuna review vedra' non si scrive; decide una persona"
}
# attribution_gap: prints the reason if the OK phase <last_label> does not have measured attribution.
attribution_gap() {
  local n f l
  [ -f "$RUN/log/$last_label.post-tree" ] || { echo "$last_label senza .post-tree"; return; }
  n=${last_label%%-*}
  for l in $(ls "$RUN/log" 2>/dev/null | sed -n 's/\.pre-tree$//p'); do   # set -f: no globbing
    [ -f "$RUN/log/$l.post-tree" ] && continue
    [ "$((10#${l%%-*}))" -lt "$((10#$n))" ] 2>/dev/null && { echo "$l con .pre-tree ancora aperto"; return; }
  done
}
# to_review <message>: REVIEW only with measured attribution, otherwise STOP with the recovery.
to_review() {
  local gap; gap=$(attribution_gap)
  [ -z "$gap" ] && next "REVIEW — $1"
  next "STOP — attribuzione non misurata ($gap): la review non saprebbe quali file sono della feature. Con il .pre-tree: git -c core.quotePath=false diff --name-only --no-renames \$(cat <pre-tree>) \$(bash $(mostra "$RS") tree) >> $RUN/touched.txt, poi quel tree in <label>.post-tree (e' cio' che fa run-phase). Senza .pre-tree: elenca a mano in touched.txt i file della feature, poi crea il .post-tree — decisione tua"
}
# test_red_gate: row 7t (harness-pt11) — format-2 plan without acceptance tests proven red.
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
# touched_excluded: the first touched.txt path that the review put among the excluded ones.
touched_excluded() {
  [ -s "$RUN/touched.txt" ] && [ -s "$TMP/excl" ] || return 0
  tr -d '\r' < "$RUN/touched.txt" | grep -Fx -f "$TMP/excl" | head -1
}

# --- code (only for IMPLEMENTED) ---
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
# Chains (harness-pt12): extra lines only for a mother or a ring.
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
# Format 2 (harness-pt10): the format and the procedure generated by `plan-check.sh gen`, compared with the plan's
# fingerprint. Extra lines only, only for format-2 plans: they do not enter State and do not change Next.
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

# Row 0: harness fingerprint recorded at the first launch (run-phase.sh, HARNESS FINGERPRINT).
harness_gap() { # prints the reason for the STOP if the harness changed since the first launch of the cycle
  # The decision belongs to run-phase.sh --harness-fp-confronta (the single function of the three readers, pk04a-2): here we
  # do not read the file's content, we decide on the first word.
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
    TEST-RED*) [ -n "$ring_prev" ] && ring_gate IMPLEMENT ;; esac   # test-red writes the tree: like implement (C4)
  echo "Next: $*"; exit 0
}
# ring_gate PLAN|IMPLEMENT (rows C3, C4): chain pipeline (L6) and tree at the start of ring k>1.
ring_gate() {
  local pn pst
  pn=$(basename "$ring_prev" .md)
  if [ "$1" = PLAN ]; then
    pst=$(bash "$PC" contract "$ring_prev" 2>/dev/null | tr -d '\r' | sed -n '1s/^Plan status:[[:space:]]*//p')
    case "$pst" in APPROVED*) return 0 ;; esac
    echo "Next: WAIT — catena: il piano dell'anello $ring_k parte quando il piano dell'anello $((ring_k - 1)) ($pn) e' APPROVED (ora: ${pst:-nessun piano})"; exit 0
  fi
  cclosed "$ring_prev" || { echo "Next: WAIT — catena: l'implement dell'anello $ring_k aspetta l'anello $((ring_k - 1)) ($pn) IMPLEMENTED; il piano puo' girare"; exit 0; }
  ls "$RUN/log" 2>/dev/null | grep -q '\.pre-tree$' && return 0   # the ring has already started
  [ -n "$ring_base" ] || { echo "Next: STOP — catena: l'anello $((ring_k - 1)) ($pn) non ha un .post-tree: la base dell'anello $ring_k non e' misurata. Decisione tua"; exit 0; }
  [ "$ring_now" = "$ring_base" ] && return 0   # CONTROLLO-TREE-ANELLO
  echo "Next: STOP — catena: il working tree (${ring_now:-non calcolabile}) non e' il .post-tree dell'anello $((ring_k - 1)) ($ring_base): modifiche fatte dopo la sua chiusura, che l'anello $ring_k si attribuirebbe. Decisione tua: riportale fuori dal tree e riprendi; per tenerle nella catena aggiungile al touched.txt di $pn e registra il tree attuale come suo .post-tree (bash $(mostra "$RS") tree)"; exit 0
}
# --- mother of a chain (rows C1, C2): no phase of its own until the rings are closed ---
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
[ $review_both -eq 1 ] && next "STOP — la spec ha sia '## Review implementazione' sia '## Implementation review': la stessa sezione in due lingue. Tieni il titolo che c'era, porta le righe di stato in quella sezione e togli l'altra, poi riprendi"
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
