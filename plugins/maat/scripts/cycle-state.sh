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
# Implemented by driver.py (`driver.py next`, function `_cycle_state`; 1.6.0: this script is only its WRAPPER, below).
# What follows describes the answer of the command that the skills and prompts cite.
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
# TABLE — the first matching row wins. It is the authoritative source: SKILL.md points here (implemented by
# driver.py `_cycle_state`).
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

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/maat-msg.sh"; maat_msg_carica   # messages (1.4.0): the catalog next to this script
[ $# -eq 1 ] && [ -f "$1" ] || { echo "$(msg cycle-state.usage script="$0")" >&2; exit 2; }
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_SCRIPTS (plugin) and PROJECT_ROOT (working folder)
# Language (1.4.0): resolved once and exported, so the driver, plan-check.sh and run-phase.sh read the same one
maat_lingua -v MAAT_LINGUA; export MAAT_LINGUA

# WRAPPER (1.6.0): the table is implemented by driver.py (`driver.py next`, function `_cycle_state`), the only engine:
# the bash table is gone (it was the fallback with FIC_DRIVER=0 in 1.5.1; FIC_DRIVER no longer has any effect here,
# and this wrapper is silent about it: `driver.py run` warns once). No fallback on error: no usable Python, a Python
# older than 3.10, or a driver that fails (exit not 0 or no Next line) give `Next: STOP — <reason>`, exit 0 (a STOP is
# an answer), that single line and NO State: line — the marker the internal readers of run-phase.sh recognise (every
# answer of the driver has State: before Next:). FIC_DRIVER_PY replaces the driver (tests).
DRV=${FIC_DRIVER_PY:-$MAAT_SCRIPTS/driver.py}
FIC_PY=""
if ! . "$HERE/python.sh" 2>/dev/null; then echo "Next: STOP — $(msg cycle-state-engine.no_python)"; exit 0; fi
fic_py_min_ok || { echo "Next: STOP — $(msg cycle-state-engine.python_old v="$FIC_PY_VER" py="$FIC_PY")"; exit 0; }
# stdout of the driver in dout, its stderr in derr, without a temporary file: the inner substitution sends stderr
# to fd 3 (the outer capture); its exit code and stdout follow, after a separator
dres=$( { dout=$("$FIC_PY" "$DRV" next "$1" 2>&3 3>&-); drc=$?; printf '\n\036%s\036%s\036' "$drc" "$dout"; } 3>&1 )
derr=${dres%%$'\n\036'*}; dres=${dres#*$'\n\036'}; drc=${dres%%$'\036'*}; dout=${dres#*$'\036'}; dout=${dout%$'\036'}
if [ "$drc" = 0 ] && grep -q '^Next: ' <<< "$dout"; then printf '%s\n' "$dout"; exit 0; fi
# failed (an exit other than 0, or exit 0 with no Next: line): the whole stderr of the driver (a traceback) goes on to
# our stderr, as run-phase.sh does for valida; the STOP line on stdout keeps only its last line
[ -n "$derr" ] && printf '%s\n' "$derr" >&2
line=$(printf '%s\n' "$derr" | tr -d '\r' | sed '/^[[:space:]]*$/d' | tail -1)
line=${line:0:200}
echo "Next: STOP — $(msg cycle-state-engine.driver_failed rc="$drc" line="${line:--}")"
exit 0
