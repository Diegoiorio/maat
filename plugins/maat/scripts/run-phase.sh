#!/usr/bin/env bash
# run-phase.sh — launches ONE phase of /full-implementation-cycle in a separate Claude subsession
# (empty context), non-interactive, and saves its stream-json log.
#
#   run-phase.sh <run-dir> <label> <prompt-file>
#   run-phase.sh --lock-status      free / inside the cycle → exit 0 · busy → exit 1 (for skills run by hand)
#   run-phase.sh --harness-fp [<repo>]   prints harness.fp (three lines, below) · exit 1 if not computable
#   run-phase.sh --harness-fp-confronta <harness.fp> [<repo>]   the decision of the three readers, one line (below)
#   run-phase.sh --harness-paths         prints the fingerprint files (relative to MAAT_ROOT) and .claude/maat.json
#
# DRIVER (harness-pt14): phases are launched by script/fic/driver.py (`driver.py run`), always through this script.
# Here the driver enters at a single point, the outcome validation (`driver.py valida`), and decides it: since 1.6.0
# there is no internal validator (WRAPPER, at valida). The four reads of cycle-state.sh go
# through cycle_state_read, which recognises a STOP of its wrapper (INTERNAL READERS, above cycle_state_read).
#
#   <run-dir>     .claude/.ai-workflow/spec-<name>.run   (gitignored by "spec-*")
#   <label>       e.g. 01-plan, 02-implement, 03-review, 04-fix (the phase is read from the label)
#   <prompt-file> the phase prompt, passed on stdin (no line-length limits)
#
# Writes to <run-dir>/log/: <label>.jsonl (log), .stderr, .running (while running), .exit (code),
# .esito ("PHASE RESULT …" line of the result event + "state=<hash>" from cycle-state.sh, only if the
# subsession exits 0: this is what moves cycle-state from implement/fix to review).
# implement/fix phases: .pre-tree/.post-tree and <run-dir>/touched.txt (below, ATTRIBUTION).
# GATES (harness-pt04): after an implement/fix finished OK and before every review, script/fic/gates.sh (level
# in force, touched.txt files) runs HERE, outside the subsession: outcome in .gates, evidence in
# <run-dir>/evidence/<key>/; the review receives the folder appended to the prompt (.prompt = actual prompt).
# The subsession also has a Stop hook (script/fic/stop-hook.py) next to the guard.
# STRUCTURED OUTCOME (harness-pt08): the subsession receives --json-schema with script/fic/schemas/
# phase-result.schema.json (the content: the CLI wants the schema, not the file) and, IN ADDITION, here the
# JSON block of the last result event (structured_output, otherwise the last ```json fence of the text) is revalidated with the
# same schema: jsonschema if available, otherwise the minimal validator of driver.py; "fase" must be that
# of the label. Valid -> log/<label>.result.json (read by cycle-state.sh). Missing or invalid -> no
# result.json and .esito = "PHASE RESULT <fase>: STOP — uscita non valida: <errori>", with the result line of the text
# kept under "originale=". The ESITO line is always written (compatibility and revert). Prose and JSON
# disagree: the most conservative wins (prose OK but JSON STOP, deviations or bloccato_su -> .esito STOP with
# originale=; prose STOP -> stays STOP). .esito is the authority.
# LANGUAGES (Maat 1.3.0): the result lines this script WRITES are "PHASE RESULT <phase>: OK|STOP — …"; every reader
# accepts "ESITO FASE …" too (old run dirs, prompts of 1.2.x); since 1.4.0 the text after "STOP — " follows the language (catalog).
# Likewise "## Implementation plan|review", "### Plan review changelog", "Children:", "defensive: " and "none" are
# read next to the Italian forms. Lines between scripts, run-dir file names and result.json keys do not change.
# DEFENSIVE DEVIATIONS: a deviation starting with "difensiva: " or "defensive: " (robustness branch, fallback for a case that
# plan or schema exclude, internal helper: no effect on the expected cases) does not stop the phase; if ALL are,
# the outcome is what it would be without deviations. An implement/fix finished OK records them: a
# "<label><TAB><text>" line in <run-dir>/log/deviazioni-difensive.txt, an AVVISO in .esito and a note in the plan's
# changelog (outside the Approved basis fingerprint: if the fingerprint changed, the spec goes back as it was). The review receives them
# appended to the prompt ("DEVIAZIONI DIFENSIVE (driver, run-phase.sh): …" line): one that is not purely defensive is a major.
# FINALIZE (harness-pt08): after a review that exited 0, script/fic/finalize.sh signs the final state (confirms
# IMPLEMENTED only with the evidence at the current key, otherwise NEEDS_VERIFICATION): outcome in .finalize.
# Fail-closed: finalize missing or exited with a code other than 0/1/3/4 -> .esito = "PHASE RESULT review: STOP —
# finalize non eseguito|fallito"; and cycle-state.sh does not give DONE without a recent Finalize: IMPLEMENTED line.
# Finalize runs after result.json is written and receives --copertura log/<label>.result.json (harness-pt09).
# REVIEW IN PARALLEL WITH VERIFICATION (harness-pt09). Review phase: the tree key is computed (review-surface.sh
# tree; with driver counterproofs also the sha256 of counterproof/mutations.json) and they start TOGETHER, in
# background, VERIFY = gates.sh (then counterproof.sh — inside WSL only on Windows and with a mutations module
# `ambiente: wsl`, otherwise direct (run_cp) — ONLY if mutations.json is the
# `plan-check.sh gen` list consistent with the plan: <run>/gen/procedura.txt with the current "Impronta piano:" and the list
# identical to one regenerated here in log/.gen-verifica.<pid>; no *.meta sidecars. Otherwise — format 1, list
# written by the worker in a previous round, plan changed — the counterproofs stay with the worker, which rewrites the
# list every round, as before) and the review subsession, with the
# prompt + the "VERIFY IN PARALLELO …" line (the reviewer writes the test IDs per requirement in the copertura field,
# not the results; provisional verdict). When both finish the key is recomputed: different (or not computable)
# -> both results discarded (spec restored from log/<label>.spec-pre, .gates/.counterproof to
# *.scartato, the evidence/<key> folder named in .gates renamed <key>.scartato — no longer reusable
# by gates.sh nor FRESH for finalize.sh —, the round's <id>.json deleted also in worker mode, event
# {"subtype":"fic_scartato"} in the log: the outcome is read only
# afterwards) and relaunch in SEQUENCE. The sequence is the previous one (gates, then review with EVIDENZE DEI GATE in the prompt)
# and also applies with FIC_REVIEW_PARALLEL=0, with a review section recorded APPROVED (promotion and gate-only do not
# launch the reviewer: they do not change) and with the key not computable. The mode is in log/<label>.parallelo.
# Verdict = AND in finalize.sh: gates FAIL or counterproof not red -> FAIL; BLOCKED -> NEEDS_VERIFICATION.
# driver's counterproof.sh: outcome in log/<label>.counterproof (exit=); exit outside 0/1/2 -> its <id>.json
# are deleted (they do not count: finalize treats them as missing); exit 5 (mirror not restored) -> .esito STOP.
# Variables: FIC_REVIEW_PARALLEL (1 default, 0 = sequence) · FIC_CP_CMD program that receives the path of
# mutations.json instead of counterproof.sh (tests) · FIC_COUNTERPROOF path of the script
# · FIC_PLAN_CHECK path of plan-check.sh. VERIFY in background writes vpid= into the lock owner: while it lives,
# the lock is not released (lock_alive, release), even if run-phase is killed.
# LANES (harness-pt13, L1). implement phase: before launching, `plan-check.sh gen` regenerates the procedure from the current
# plan in a separate folder and script/fic/blocks-independent.py decides (log/<label>.corsie: outcome, lane k,
# scope k, dependencies). Parallel outcome -> under the SAME lock two `claude -p` subsessions together, each with
# FIC_LANE=k (vitest-fast.sh uses the copy <root copy>-<k>; WSLENV carries it into WSL) and FIC_WRITE_SCOPE =
# the scrive: files of its blocks (guard.py denies Edit/Write outside); prompt log/<label>.corsia-<k>.prompt = the
# prompt + the "CORSIA k/2 …" line, log in log/<label>.corsia-<k>.jsonl, PIDs in cpid= and cpid2= of the owner. When the lanes
# are done, the AFTER-THE-FACT CHECK: paths changed between .pre-tree and the current tree (log/<label>.cambiati) split by
# scope with blocks-independent.py --posteriori (log/<label>.posteriori): a file outside the union, attributed to
# both lanes (in its scope and declared by the other in the JSON "file") or shared/generated -> STOP. Then
# in <label>.jsonl a single MERGED result event (ESITO, JSON: union of file/deviazioni/gate, bloccato_su), which the
# usual validation reads. A lane with only JSON in the result (structured exit, no "PHASE RESULT" line): the
# line is derived from the valid object ("PHASE RESULT implement: <OK|STOP> — <motivo>"), as in series; text line and
# object disagree -> STOP wins. The lanes' preflight lists (do-not-touch.<k>.txt, mixed.<k>.txt) are merged
# (sort -u) into do-not-touch.txt and mixed.txt, the only ones read by later phases. The gates stay the driver's
# on the whole tree, once the lanes are done (below).
# Series, as before, with: FIC_LANES=0, phase other than implement, format 1 or gen failed, initial tree not
# computed, dependent blocks (one false condition is enough).
# With FIC_CORSIE=<file> (harness-pt14: launched by script/fic/driver.py) the decision is the driver's, taken with
# the same commands (gen in a separate folder, blocks-independent.py): the file becomes log/<label>.corsie and
# launch_lanes starts as usual. FIC_LANES=0 and the initial tree are still checked here.
# Exit: that of the subsession · 2 = usage · 3 = claude binary not found ·
#         4 = another CODE phase is running (lock), or another PLAN phase on the same spec
#             (per-spec lock) · 5 = guard not active: not launched · 6 = STOP, harness changed since the
#             first launch of the cycle (below, HARNESS FINGERPRINT): not launched · 7 = chain STOP
#             (below, CHAINS): not launched.
#
# CHAINS (harness-pt12; the rules are in cycle-state.sh, rows C1-C4).
#   Ring: at the start of an implement of a ring k>1 (spec listed in the Figlie: line of a mother, no
#   .pre-tree yet in its run dir) cycle-state.sh is asked: "STOP — catena" (tree different from the .post-tree
#   of k-1) or "WAIT — catena" (k-1 not closed) → exit 7, the subsession does not start.
#   Review of a ring k>1: the driver writes log/<label>.anello.diff = review-surface.sh diff from the "Base anello"
#   (.post-tree of k-1, never HEAD) to the current tree on the files of the ring's touched.txt, and appends file and index to
#   the prompt ("DIFF DELL'ANELLO (driver, run-phase.sh): …" line). Base missing or diff failed → exit 7.
#   Closing: label NN-chiusura on the MOTHER's run dir. Code phase (lock), without a subsession unless
#   needed: touched.txt = union of the rings' touched.txt, base.txt = that of the first ring, gates at
#   full level (script/fic/gates.sh) on the final tree. If the children have [e2e-locator: <spec>] lines and the gates are
#   green, the subsession starts with the prompt plus the "E2E DELLA CATENA: <spec…>" line (closing worker:
#   /dev-verify, under the same guard) and its "PHASE RESULT chiusura: OK" line counts (no --json-schema:
#   the phase is not in the outcome schema). Writes <run-dir>/chiusura.txt: "Chiusura: IMPLEMENTED — base <b> ·
#   tree <t> · gates PASS · e2e <…> · <ora UTC>" or "Chiusura: NEEDS_VERIFICATION — <motivo> · <ora UTC>", and
#   log/<label>.esito. The mother is DONE (cycle-state.sh) only with the former, on the current code.
#
# HARNESS FINGERPRINT (pt03; incident ux-1..4: harness modified by another session under a running cycle).
# At the first launch of a cycle (run dir with no phases run: no .running, no .exit other than
# 2/4/5) <run-dir>/harness.fp is written (pk04a-2), three lines: "impronta=<64 hex digits>", "versione=<version from
# .claude-plugin/plugin.json>", "radice=<MAAT_ROOT, C:/… form>". The fingerprint is the sha256 of the lines
# "<sha256 of the content without CR> <path>" of all the files under MAAT_ROOT (relative path, LC_ALL=C order)
# except HARNESS_EXCLUDE, plus <project>/.claude/maat.json at the end (missing: fixed line ".claude/maat.json
# ASSENTE"). No git: the plugin cache is not a repository; the project's skills are not part of it.
# At every later phase it is compared with hfp_confronta (--harness-fp-confronta), the SINGLE function also used by
# cycle-state.sh and driver.py: UGUALE → go on; CAMBIATO, FORMATO-PRECEDENTE (a single line of 64
# hex digits: cycle started with the internal harness), ILLEGGIBILE (empty, truncated, no fingerprint) or NON-CALCOLABILE
# → STOP, exit 6, with the registration date and the remedy. Version and root are not part of the comparison. A
# run dir without harness.fp and with phases already run (cycle started before this rule) is not checked.
#
# PERMISSIONS (user decision, 2026-09-21). In -p mode writes under .claude/ — where the
# spec lives — pass ONLY in bypass: measured, neither acceptEdits nor Edit(path) rules unlock them.
# Hence bypass + two layers:
#   1. DENY by prefix (below): stops the direct command and && chains, NOT a command wrapped
#      in `wsl -- bash -lc '...'` or `bash -c '...'` (measured);
#   2. guard.py as a PreToolUse hook (passed with --settings; measured 2026-09-22: in -p + bypass the hook
#      fires and exit 2 blocks the nested command too). It looks at the whole command: production and release of the
#      project, direct remote access, git that changes state, docker, psql, installs, rm -rf; and in the
#      plan/review phases writes outside the working folder. The hook is fail-open (if it FAILS it lets
#      through): that is why, before launching, the self-test makes it deny the probe of `maat-config.py
#      sonda-produzione` (or, without guardia.produzione, `git push --force origin x`) with the SAME command
#      as the hook, and if it does not deny, nothing is launched (exit 5). What stays uncovered: docstring of guard.py.
#   The guards in a subsession are TWO, on purpose: this one (deny, without --universal) and the plugin hook
#   (hooks/hooks.json → guard-hook.sh → guard.py --universal, which with FIC_PHASE denies with exit 2: it also reads the
#   content of `bash script/x.sh`, the `cd`s and the git rules on worktrees). pk01 D2: the plugin hook fires also
#   in subsessions and adds up with --settings. Both read MAAT_CONFIG, exported below.
#   No MCP (--strict-mcp-config without --mcp-config): no phase of the chain uses them; measured
#   2026-09-22, tools at startup 79 -> 31 (48 MCP: chrome-devtools, Drive, Docs). Less capability, not
#   a context saving (they are loaded deferred: -2k tokens).
#   The test checks the argument; the measurement on the system/init event is repeated by hand (phase-usage.py:
#   column "tool all'avvio (mcp N)") after a CLI update.
#
# LOCK (implement/review/fix phases): working tree, counterproofs, sync and DEV e2e context are
# shared, so only one code phase at a time, of any feature. Plan phases of DIFFERENT
# specs run in parallel; two plans on the SAME spec do not (incident ux-6: approved plan
# overwritten): every plan takes <run-dir>/plan.lock, same liveness, and the second exits 4 with the
# owner. It is not a global lock on planning. The lock is a directory inside .git (never review surface) with the MSYS PIDs of
# this script and of the subsession: alive if at least one of the two exists (`kill -0` also sees the
# processes of other Git Bash windows). NOT the Windows PID read from /proc/<pid>/winpid right after
# `&`: that is the fork stub's, not claude.exe's (measured 2026-09-22). Skills launched by hand
# (/implementation-review-cycle, /dev-verify --e2e) query it with --lock-status and stop if it is
# busy; they do not take it.
#
# ATTRIBUTION (implement/fix phases): tree of the working tree before and after the subsession; the paths that
# change between the two end up in <run-dir>/touched.txt and cannot be excluded by the review. With the
# lock taken no other code phase runs, so the delta belongs to the feature; a human change
# made in the same interval ends up in it (over-inclusion: safe direction). A killed
# phase leaves .pre-tree without .post-tree: it is closed by the next code phase of the same feature,
# or — if it belongs to another feature — by the one that takes over its orphan lock, before changing the tree.
# The .post-tree exists ONLY if initial tree, final tree and diff succeeded: it is the proof that
# cycle-state.sh asks for before sending an OK implement/fix phase to review. A failure here is an
# AVVISO, but the cycle stops there (fail-closed downstream, not a phase left half-done holding the lock).
#
# OTHER FLOWS (incident: PRODUZIONE.md modified by the user in another session during test-red). The tree
# diff does not know WHO wrote: for every path changed in the phase the driver asks the subsession's logs
# (NOMI_PY, below) whether it named it. test-red: an out-of-scope path never named does not stop the phase; it goes into
# do-not-touch.txt (preflight form), leaves touched.txt if it entered it in this phase, and there is an AVVISO
# (.stderr, .esito after state=, log/<label>.avvisi, log/<label>.altri-flussi). Named, or unusable logs -> STOP
# as before. implement/fix, conservative (formatters and generators write without naming): the never-named path
# STAYS in touched.txt, annotated in log/<label>.altri-flussi with an AVVISO; no STOP, no file removed.
# test-red: a path already in touched.txt before the phase (feature work) and changed without being named
# cannot be both in touched.txt and in do-not-touch -> STOP with the reason, the user decides.
# LIMIT: a program that computes paths by itself (generators, Python/Node scripts walking folders, codegen
# without arguments) writes without naming them. If the test-red subsession launches one that writes out of scope, the
# write looks like another flow's: no STOP, the file goes into do-not-touch (and the AVVISO says so). The rules of
# NOMI_PY cover the known writing commands (ancestors, glob, dot, --fix/--write/-u), not an arbitrary program.
#
# TEST-RED PHASE (harness-pt11; label *test-red*, format-2 plans only, between APPROVED plan and implement):
# CODE phase (lock, .pre-tree/.post-tree, touched.txt). The guard gives it its own scope (FIC_SCOPE =
# log/<label>.scope, from `plan-check.sh accept`): the plan's test files + the files the plan declares new.
# The subsession (acceptance-test-writer agent) writes the acceptance tests and the stubs; then, HERE, the
# driver's verification: targeted gates.sh (std level, the plan's test files + touched.txt; outcome in .gates) and
# `plan-check.sh rossi` on the evidence (.rossi, <run-dir>/test-red/rossi.json): every test red on its own
# assertion, no import/collection errors, no green, no existing suite in conflict; otherwise .esito =
# "PHASE RESULT test-red: STOP — …" (originale= below). 1.8.1: a STOP whose only cause are conflicts of an existing
# suite gets ONE second round (secondo_giro): red in one round only = unstable test (AVVISO), red in both = STOP
# «(confirmed on two rounds)». Closing OK: test-red/stubs.json, test-red/tests.txt,
# " · tests <fp>" in the Approved basis (plan-check.sh basis --write-tests) and gen (absorbed counterproofs, L2).
# After implement and fix OK: the acceptance test files compared with test-red/tests.txt; different ->
# .esito STOP «deviazione: test di accettazione modificati» regardless of the report (stubs do not count), except for a
# PRESCRIBED CHANGE (file in a block's scrive:, acceptance test functions unchanged or not
# verifiable): OK with an AVVISO and the test fingerprint re-recorded (see tests_guard).
# S3 · PARKED TESTS (label *test-stage*): no lock (it writes neither the spec nor the tree), scope = only
# <run-dir>/staging/, <run-dir>/staging.fp = plan fingerprint at launch. A test-red that finds the staging with
# the current plan fingerprint -> copies the scope files into the tree (staging -> staging.copiato), no
# subsession, and the verification; different fingerprint -> staging discarded, the subsession writes the tests.
#
# To update THIS file while a cycle is running: write a copy and `mv` it over the original.
# Rewriting it in place is dangerous: bash rereads the script from disk while executing it.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_ROOT/MAAT_SCRIPTS (plugin) and PROJECT_ROOT (working folder)
RS="$MAAT_SCRIPTS/review-surface.sh"
# Messages (1.4.0): the catalog next to this script. The language is resolved once and exported (the sub-session,
# cycle-state.sh and the gates read the same one) and it is part of the harness fingerprint (below). The embedded
# Python (TG_PY, LANE_PY, DIFENSIVE_PY) imports maat_msg.py from MAAT_MSG_PY, in native form (msg_py).
. "$HERE/lib/maat-msg.sh"; maat_msg_carica
maat_lingua -v MAAT_LINGUA; export MAAT_LINGUA
# wsl.exe passes into WSL only the variables named in WSLENV: without this, whatever the sub-sessions (normal and
# lanes) launch in `wsl` would reread maat.json there and lose a MAAT_LINGUA set by hand (1.5.0). Inert outside Windows.
wslenv_add() { # $1 = variable name: appended once; the entries already there and their /p /l /u /w flags are kept
  local e w=()
  IFS=: read -r -a w <<< "${WSLENV:-}"
  for e in ${w[@]+"${w[@]}"}; do [ "${e%%/*}" = "$1" ] && { export WSLENV; return 0; }; done
  WSLENV=${WSLENV:+$WSLENV:}$1
  export WSLENV
}
wslenv_add MAAT_LINGUA
msg_py() {
  [ -n "${MAAT_MSG_PY:-}" ] || MAAT_MSG_PY=$(maat_cygm "$HERE/maat_msg.py" 2>/dev/null || printf '%s' "$HERE/maat_msg.py")
  export MAAT_MSG_PY
}

# --- harness fingerprint (see HARNESS FINGERPRINT) ---
# The SINGLE list of exclusions, used by the computation and by --harness-paths: each entry is a glob matched against EVERY
# component of the path relative to MAAT_ROOT (the first two exclude folders, the others editor and merge temporary
# files wherever they are). No .gitignore: every other file under MAAT_ROOT is included.
HARNESS_EXCLUDE=(__pycache__ assets '*.swp' '*.orig' .DS_Store '*~')
# The computation in ONE process (standard library): on Windows one process per file cost seconds at every comparison.
#   argv: elenco|impronta <MAAT_ROOT> <project> <language> -- <HARNESS_EXCLUDE…> · exit 1 = unreadable file
# elenco: the harness files relative to MAAT_ROOT (regular files, not links), without the excluded components (fnmatch,
# case-sensitive), in UTF-8 byte order (= LC_ALL=C sort). impronta: sha256 of the lines
# "<sha256 of the content without CR> <path>\n" of those files, plus at the end that of <project>/.claude/maat.json
# (or ".claude/maat.json ASSENTE\n") and, since 1.4.0, "lingua <it|en>\n": the RESOLVED language of the messages
# (MAAT_LINGUA, otherwise maat.json), so that a language changed through the variable in the middle of a cycle stops
# it as a changed maat.json does, instead of rewriting the lines of the spec in the other language.
HFP_PY='
import fnmatch, hashlib, os, sys
modo, root, prog, lingua = sys.argv[1:5]
esc = sys.argv[6:]
def escluso(rel):
    return any(fnmatch.fnmatchcase(c, p) for c in rel.split("/") for p in esc)
def h(p):
    with open(p, "rb") as fh:
        return hashlib.sha256(fh.read().replace(b"\r", b"")).hexdigest()
def errore(d):
    raise OSError(d)
try:
    files = []
    for d, dirs, fs in os.walk(root, onerror=errore):
        for n in fs:
            full = os.path.join(d, n)
            if os.path.islink(full) or not os.path.isfile(full):
                continue
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            if not escluso(rel):
                files.append(rel)
    files.sort(key=lambda s: s.encode("utf-8", "surrogateescape"))
    out = sys.stdout.buffer
    if modo == "elenco":
        out.write("".join(f + "\n" for f in files).encode("utf-8", "surrogateescape"))
        sys.exit(0)
    righe = "".join("%s %s\n" % (h(os.path.join(root, f)), f) for f in files)
    mj = os.path.join(prog, ".claude", "maat.json")
    if os.path.exists(mj):
        if not os.path.isfile(mj):
            sys.exit(1)
        righe += "%s .claude/maat.json\n" % h(mj)
    else:
        righe += ".claude/maat.json ASSENTE\n"
    righe += "lingua %s\n" % lingua
    out.write(hashlib.sha256(righe.encode("utf-8", "surrogateescape")).hexdigest().encode())
except OSError:
    sys.exit(1)
'
hfp_win() { # $1 = variable, $2 = path → the variable in C:/… form on Windows; no process if it already is
  local w=$2
  [[ $w =~ ^[A-Za-z]:/ ]] || w=$(maat_cygm "$2") || w=$2
  printf -v "$1" '%s' "$w"
}
hfp_py1() { # "$@" = interpreter → the HFP_PY output if valid (hfp_modo, hfp_r, hfp_p of the caller), otherwise 1
  local o
  o=$(PYTHONDONTWRITEBYTECODE=1 "$@" -c "$HFP_PY" "$hfp_modo" "$hfp_r" "$hfp_p" "$MAAT_LINGUA" -- "${HARNESS_EXCLUDE[@]}" 2>/dev/null) || return 1
  if [ "$hfp_modo" = impronta ]; then [[ $o =~ ^[0-9a-f]{64}$ ]] || return 1
  else [[ $'\n'$o$'\n' == *$'\n.claude-plugin/plugin.json\n'* ]] || return 1; fi   # the plugin always has plugin.json
  printf '%s\n' "$o"
}
hfp_py() { # $1 = elenco|impronta, $2 = project root (impronta only) → the HFP_PY output
  # The fingerprint does not depend on the guard interpreter: FIC_PYTHON, FIC_PY, the py launcher, python3,
  # python are tried and the first VALID output wins (64 hex digits; a list with .claude-plugin/plugin.json). A broken
  # FIC_PYTHON thus stays a guard problem (exit 5), not a non-computable fingerprint (exit 6), as with the computation
  # in bash. No python.sh: it starts two of them to choose. No valid interpreter: non-zero → NON-CALCOLABILE.
  local hfp_modo=$1 hfp_r hfp_p c
  hfp_win hfp_r "$MAAT_ROOT"; hfp_win hfp_p "${2:-.}"
  [ -n "${FIC_PYTHON:-}" ] && hfp_py1 "$FIC_PYTHON" && return 0
  [ -n "${FIC_PY:-}" ] && hfp_py1 "$FIC_PY" && return 0
  command -v py >/dev/null 2>&1 && hfp_py1 py -3 && return 0
  for c in python3 python; do command -v "$c" >/dev/null 2>&1 && hfp_py1 "$c" && return 0; done
  return 1
}
hfp_elenco() { # prints the harness files, relative to MAAT_ROOT, in LC_ALL=C order · non-zero if they cannot be listed
  hfp_py elenco
}
harness_fp() { # $1 = project root → prints the fingerprint (64 hex digits) · non-zero if not computable
  local fp
  [ -n "$1" ] && [ -d "$1" ] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1 || return 1
  fp=$(hfp_py impronta "$1") || return 1
  [[ $fp =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s\n' "$fp"
}
hfp_stampa() { # $1 = project root → the content of harness.fp, three lines · non-zero if not computable
  local fp v r
  fp=$(harness_fp "$1") || return 1
  v=$(tr -d '\r' < "$MAAT_ROOT/.claude-plugin/plugin.json" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  r=$(maat_cygm "$MAAT_ROOT" 2>/dev/null || printf '%s' "$MAAT_ROOT")
  printf 'impronta=%s\nversione=%s\nradice=%s\n' "$fp" "$v" "$r"
}
hfp_impronta_di() { # $1 = harness.fp → "nuovo <impronta>" | "precedente <impronta>" | nothing (unreadable)
  local c l
  { c=$(< "$1"); } 2>/dev/null || return 0
  c=${c//$'\r'/}
  while IFS= read -r l; do
    [[ $l =~ ^impronta=([0-9a-f]{64})$ ]] && { echo "nuovo ${BASH_REMATCH[1]}"; return 0; }
  done <<< "$c"
  [[ $c =~ ^[0-9a-f]{64}$ ]] && echo "precedente $c"   # previous format: a single line of 64 hex digits
  return 0
}
hfp_confronta() { # $1 = harness.fp, $2 = project root → ONE line, the decision of the three readers (run-phase.sh,
  # cycle-state.sh, driver.py): UGUALE | CAMBIATO <reg:12> <att:12> | FORMATO-PRECEDENTE <reg:12> <att:12> |
  # ILLEGGIBILE <att:12> | NON-CALCOLABILE. Version and root are informative: outside the comparison.
  local now reg
  now=$(harness_fp "$2") || { echo NON-CALCOLABILE; return 0; }
  reg=$(hfp_impronta_di "$1")
  case "$reg" in
    "nuovo $now") echo UGUALE ;;
    nuovo\ *) echo "CAMBIATO ${reg:6:12} ${now:0:12}" ;;
    precedente\ *) echo "FORMATO-PRECEDENTE ${reg:11:12} ${now:0:12}" ;;
    *) echo "ILLEGGIBILE ${now:0:12}" ;;
  esac
}
if [ "${1:-}" = "--harness-paths" ]; then
  hfp_elenco || exit 1
  echo .claude/maat.json; exit 0
fi
if [ "${1:-}" = "--harness-fp" ]; then
  [ $# -le 2 ] || { echo "$(msg run-phase.usage_fp script="$0")" >&2; exit 2; }
  unset MSYS_NO_PATHCONV
  r=${2:-$PROJECT_ROOT}
  hfp_stampa "$r" || { echo "$(msg run-phase.hfp_nc)" >&2; exit 1; }
  exit 0
fi
if [ "${1:-}" = "--harness-fp-confronta" ]; then
  [ $# -ge 2 ] && [ $# -le 3 ] || { echo "$(msg run-phase.usage_fpc script="$0")" >&2; exit 2; }
  unset MSYS_NO_PATHCONV
  hfp_confronta "$2" "${3:-$PROJECT_ROOT}"
  exit 0
fi

# --- structured outcome: `driver.py valida` decides (see STRUCTURED OUTCOME; harness-pt14) ---
# WRAPPER (1.6.0): `driver.py valida`, the only engine (the internal validator VALIDA_PY, the fallback with FIC_DRIVER=0
# in 1.5.1, is gone with `run-phase.sh --valida`; FIC_DRIVER no longer has any effect here, and this wrapper is silent
# about it: `driver.py run` warns once). It prints the ESITO line (or the «uscita non valida» STOP and, below it,
# originale=<line>) and writes result.json if valid. The Python check comes first: FIC_PY_VER older than 3.10 ->
# `PHASE RESULT <phase>: STOP — <reason>`. No fallback on error: a driver that exits not 0 gives `PHASE RESULT <phase>:
# STOP — <reason>` and its result.json, if written, is removed (a valid result.json of a failed run must not decide).
# FIC_DRIVER_PY replaces the driver (tests).
DRV=${FIC_DRIVER_PY:-$MAAT_SCRIPTS/driver.py}
valida() { # <log> <schema> <phase> <result.json>: prints the outcome (see above)
  local o vres vrc verr line
  fic_py_min_ok || { echo "PHASE RESULT $3: STOP — $(msg run-phase-engine.python_old v="${FIC_PY_VER:-}" py="$FIC_PY")"; return 0; }
  # stdout of the driver in o, its stderr in verr (as in cycle-state.sh: fd 3 is the outer capture), then the
  # stderr goes on to the caller's stderr as before
  vres=$( { o=$("$FIC_PY" "$DRV" valida "$@" 2>&3 3>&-); vrc=$?; printf '\n\036%s\036%s\036' "$vrc" "$o"; } 3>&1 )
  verr=${vres%%$'\n\036'*}; vres=${vres#*$'\n\036'}; vrc=${vres%%$'\036'*}; o=${vres#*$'\036'}; o=${o%$'\036'}
  [ -n "$verr" ] && printf '%s\n' "$verr" >&2
  if [ "$vrc" = 0 ]; then [ -n "$o" ] && printf '%s\n' "$o"; return 0; fi
  rm -f "$4"
  line=$(printf '%s\n' "$verr" | tr -d '\r' | sed '/^[[:space:]]*$/d' | tail -1)
  line=${line:0:200}
  echo "PHASE RESULT $3: STOP — $(msg run-phase-engine.valida_failed rc="$vrc" line="${line:--}")"
}

# --- attribution by name (see OTHER FLOWS): did the subsession name these paths? ---
# NOMI_PY <repo root> <file of paths, one per line> <log.jsonl>… prints "nominato<TAB>p" or "mai<TAB>p" for
# every path. The inputs of ALL the tool_use entries of the logs are examined (nested too, sub-agents too): named =
# relative path (also with \), or the basename alone, in any string; or, in a `command` that writes
# (sed -i, rm, mv, cp, find, >, tee, git checkout/restore, --fix, --write, Remove-Item…), an ancestor directory
# (also relative to a `cd` of another call: any sequence of segments of the path's folder), a
# bare dot, a glob without a folder or under an ancestor (same), the root as the target (not as `cd`), or a
# command that writes over the whole project (--fix, --write, npm run format, git checkout/restore/stash/reset…, the
# snapshot updates --update, --snapshot-update, --update-snapshots, -u of vitest/jest/npx/npm). When in doubt,
# nominato. Fail-closed: unreadable logs, no events or no result event -> all "nominato", exit 3.
# `run-phase.sh --nominati <root> <paths-file> <log.jsonl>…` runs it on its own (tests).
NOMI_PY='
import json, re, sys
sys.stdout.reconfigure(encoding="utf-8")
radice, elenco, logs = sys.argv[1], sys.argv[2], sys.argv[3:]
def norma(s):
    return re.sub(r"/+", "/", s.replace("\\", "/")).lower()
def usi(o, out):
    if isinstance(o, dict):
        if o.get("type") == "tool_use" and "input" in o:
            out.append(o["input"])
        for v in o.values():
            usi(v, out)
    elif isinstance(o, list):
        for v in o:
            usi(v, out)
def stringhe(o, k, out):
    if isinstance(o, str):
        out.append((k, o))
    elif isinstance(o, dict):
        for kk, v in o.items():
            stringhe(v, kk, out)
    elif isinstance(o, list):
        for v in o:
            stringhe(v, k, out)
try:
    paths = [l.strip() for l in open(elenco, encoding="utf-8", errors="replace").read().splitlines() if l.strip()]
except OSError:
    paths = []
eventi = risultati = 0
ins = []
try:
    for lg in logs:
        for ln in open(lg, encoding="utf-8", errors="replace"):
            try:
                ev = json.loads(ln)
            except ValueError:
                continue
            if not isinstance(ev, dict):
                continue
            eventi += 1
            risultati += ev.get("type") == "result"
            usi(ev, ins)
except OSError:
    eventi = 0
if not logs or not eventi or not risultati:
    for p in paths:
        print("nominato\t" + p)
    sys.exit(3)
testi, comandi = [], []
for i in ins:
    ss = []
    stringhe(i, "", ss)
    for k, s in ss:
        testi.append(norma(s))
        if k == "command":
            comandi.append(norma(s))
r = norma(radice).rstrip("/")
radici = {r}
for m in (re.match(r"^([a-z]):/(.*)$", r), re.match(r"^/mnt/([a-z])/(.*)$", r), re.match(r"^/([a-z])/(.*)$", r)):
    if m:
        radici |= {"%s:/%s" % m.groups(), "/%s/%s" % m.groups(), "/mnt/%s/%s" % m.groups()}
        break
INNOCUI = re.compile(r"[0-9&]*>>?\s*(/dev/null|nul)\b|[0-9]*>&[0-9-]+")
SCRIVE = re.compile(r"\bsed\b[^|;&]*\s-[a-z]*i|\bperl\b[^|;&]*\s-[a-z]*i|>|\b(rm|rmdir|mv|cp|tee|find|touch|truncate|install|ln|dd|patch|unzip|tar|rsync|del|erase|prettier)\b"
                    r"|\b(remove|move|copy|new|rename)-item\b|\b(set|add|clear)-content\b|\bout-file\b|--fix\b|--write\b|\bnpm\s+run\s+(format|fix)"
                    r"|\bgit\b[^|;&]*\s(checkout|restore|stash|reset|clean|apply|am|pull|merge|rebase|switch|mv|rm)\b")
TUTTO = re.compile(r"--fix\b|--write\b|\bnpm\s+run\s+(format|fix)|\bgit\b[^|;&]*\s(checkout|restore|stash|reset|clean|pull|merge|rebase|switch)\b"
                   r"|--update\b|--snapshot-update\b|--update-snapshots?\b|\b(vitest|jest|npx|npm|yarn|pnpm)\b[^|;&]*\s-u(?=$|[\s\"\x27;&|)])")
PUNTO = re.compile(r"(?:^|[\s\"\x27=])\.{1,2}/?\*?(?=$|[\s\"\x27;&|)])")
TOKEN = re.compile(r"[^\s\"\x27|;&<>()=]+")
def confine(t):
    return re.compile(r"(?<![a-z0-9_.-])" + re.escape(t) + r"(?![a-z0-9_-])")
def relativo(pre):
    for rr in radici:
        if pre == rr or pre.startswith(rr + "/"):
            return pre[len(rr):].lstrip("/")
    return pre
def dentro(pn, d):   # d (root removed, leading ./ and ../ removed) is a contiguous sequence of segments of the folder of pn
    d = re.sub(r"^(\.{1,2}(/|$))+", "", d).strip("/")
    return ("/" + pn).find("/" + d + "/") >= 0 if d else None
def nominato(p):
    pn = norma(p)
    if any(confine(pn).search(t) or confine(pn.split("/")[-1]).search(t) for t in testi):
        return True
    for c in comandi:
        c = INNOCUI.sub(" ", c)
        if not (SCRIVE.search(c) or TUTTO.search(c)):
            continue
        if TUTTO.search(c) or PUNTO.search(c):
            return True
        # every argument, WHOLE: an ancestor folder (dir, dir/) or the prefix of a glob (dir/*.py, *.md).
        # Also RELATIVE to a cwd set by a `cd` of another call (the cwd persists): it is enough for it to be a
        # contiguous sequence of segments of the path folder (cd modulo/b; then rm -r app/servizi)
        for tok in TOKEN.findall(c):
            if "*" in tok:
                pre = tok.split("*", 1)[0]
                if dentro(pn, relativo(pre.rsplit("/", 1)[0] if "/" in pre else "")) is not False:
                    return True   # None = glob without a folder, or under the root: everything
            elif dentro(pn, relativo(tok)):
                return True
        for rr in radici:
            for m in re.finditer(r"(?<![a-z0-9_.-])" + re.escape(rr) + r"(?=/?(?:$|[\s\"\x27;&|)]))", c):
                if not re.search(r"(?:\bcd|\bpushd|\s-c|set-location)\s+[\"\x27]?$", c[:m.start()]):
                    return True
    return False
for p in paths:
    print(("nominato\t" if nominato(p) else "mai\t") + p)
'
if [ "${1:-}" = "--nominati" ]; then
  [ $# -ge 4 ] || { echo "$(msg run-phase.usage_nominati script="$0")" >&2; exit 2; }
  . "$HERE/python.sh" || { echo "$(msg run-phase.no_python)" >&2; exit 5; }
  shift; "$FIC_PY" -c "$NOMI_PY" "$@"; exit $?
fi

# --- code-phase lock (also for --lock-status) ---
# git.exe must receive converted paths: with MSYS_NO_PATHCONV=1 `git -C /c/...` failed and the lock
# appeared "free" (measured 2026-09-22). And if git does not find the repository, no computable lock:
# --lock-status says "unknown" (exit 1, like busy) and no phase starts. Never fail-open.
unset MSYS_NO_PATHCONV
if [ -n "${FIC_LOCK:-}" ]; then
  LOCK=$FIC_LOCK
else
  # from the WORKING FOLDER, not from PROJECT_ROOT (which makes FIC_REPO win, exported to the phases): in a linked
  # worktree it is .git/worktrees/<name>, in the main tree .git (pk04a-1, step 3)
  gd=$(git rev-parse --absolute-git-dir 2>/dev/null) && [ -n "$gd" ] || {
    [ "${1:-}" = "--lock-status" ] && { echo "sconosciuto: $(msg run-phase.lock_unknown)"; exit 1; }
    echo "$(msg run-phase.lock_no_repo)" >&2; exit 2; }
  LOCK=$gd/full-implementation-cycle.lock
fi
alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
lock_alive() { # $1 = lock directory (default: the code-phase one)
  local p c v L=${1:-$LOCK}
  if [ ! -f "$L/owner" ]; then
    # just created by someone else (owner not written yet) → alive; old and without owner → orphan
    [ -z "$(find "$L" -maxdepth 0 -mmin +1 2>/dev/null)" ]
    return
  fi
  p=$(sed -n 's/^pid=//p' "$L/owner"); c=$(sed -n 's/^cpid=//p' "$L/owner")
  v=$(sed -n 's/^vpid=//p' "$L/owner")   # background VERIFY of the parallel review (harness-pt09)
  local c2; c2=$(sed -n 's/^cpid2=//p' "$L/owner")   # second lane of the implement (harness-pt13)
  alive "$p" || alive "$c" || alive "$v" || alive "$c2"
}

if [ "${1:-}" = "--lock-status" ]; then
  [ $# -eq 1 ] || { echo "$(msg run-phase.usage_lock script="$0")" >&2; exit 2; }
  case "${FIC_PHASE:-}" in implement|review|fix|chiusura|test-red) echo "dentro il ciclo (fase $FIC_PHASE): $(msg run-phase.lock_inside)"; exit 0 ;; esac
  if [ -d "$LOCK" ] && lock_alive; then echo "occupato: $([ -f "$LOCK/owner" ] && tr '\n' ' ' < "$LOCK/owner")"; exit 1; fi
  if [ -d "$LOCK" ]; then echo "libero ($(msg run-phase.lock_orphan_free owner="$([ -f "$LOCK/owner" ] && tr '\n' ' ' < "$LOCK/owner")"))"; else echo "libero"; fi
  exit 0
fi

[ $# -eq 3 ] || { echo "$(msg run-phase.usage script="$0")" >&2; exit 2; }
dir=$1 label=$2 prompt=$3
msg_py   # the embedded Python below prints messages of the catalog
[ -f "$prompt" ] || { echo "$(msg run-phase.no_prompt prompt="$prompt")" >&2; exit 2; }

# Binary: CLAUDE_BIN if set; then the most recent version inside the VS Code extension (the
# path changes at every update, so it is searched for); then `claude` in PATH.
CL=${CLAUDE_BIN:-}
if [ -z "$CL" ]; then
  ext=$(ls -d "${USERPROFILE:-$HOME}"/.vscode/extensions/anthropic.claude-code-*-win32-x64 2>/dev/null | sort -V | tail -1)
  [ -n "$ext" ] && [ -f "$ext/resources/native-binary/claude.exe" ] && CL="$ext/resources/native-binary/claude.exe"
fi
[ -n "$CL" ] || CL=$(command -v claude 2>/dev/null || true)
[ -n "$CL" ] || { echo "$(msg run-phase.no_claude)" >&2; exit 3; }

# DENY by prefix (--disallowedTools): generated by the guard (`guard.py --deny-list`, «guardia» section below):
# core + guardia.rilascio + guardia.vietati_extra from maat.json (pk05).
DENY=()

# First launch of the cycle (HARNESS FINGERPRINT): decided BEFORE writing any file of the label.
fresh=1
for f in "$dir"/log/*.running "$dir"/log/*.exit; do
  [ -f "$f" ] || continue
  case "$f" in *.running) fresh=0; break ;; esac
  case "$(tr -d '\r' < "$f" 2>/dev/null)" in 2|4|5) ;; *) fresh=0; break ;; esac
done
mkdir -p "$dir/log"
log="$dir/log/$label.jsonl" err="$dir/log/$label.stderr" ex="$dir/log/$label.exit"
finish() { echo "$1" > "$ex"; exit "$1"; }

# --- phase, from the label (unknown → treated as read-only) ---
case "$label" in
  *chiusura*) phase=chiusura ;;
  *test-red*) phase=test-red ;; *test-stage*) phase=test-stage ;;
  *implement*) phase=implement ;; *review*) phase=review ;; *fix*) phase=fix ;;
  *plan*) phase=plan ;; *) phase=probe ;;
esac
export FIC_PHASE=$phase

# --- attribution (see ATTRIBUTION) ---
tree_now() { (cd "$FIC_REPO" && bash "$RS" tree) 2>>"$err"; }
close_pre() { # $1 = .pre-tree file, $2 = its run dir: paths changed between that tree and now → touched.txt
  local pre post
  pre=$(cat "$1") && post=$(tree_now) && [ -n "$pre" ] && [ -n "$post" ] || { echo "AVVISO: $(msg run-phase.attr_not_computed f="$1")" >> "$err"; return 0; }
  (cd "$FIC_REPO" && git -c core.quotePath=false diff --name-only --no-renames "$pre" "$post") >> "$2/touched.txt" 2>>"$err" \
    || { echo "AVVISO: $(msg run-phase.attr_diff_failed f="$1")" >> "$err"; return 0; }
  sort -u -o "$2/touched.txt" "$2/touched.txt"
  echo "$post" > "${1%.pre-tree}.post-tree"
}
# --- other flows (see OTHER FLOWS): who wrote a path changed during the phase ---
nominati() { # $1 = file of paths; prints "nominato|mai<TAB>path" (NOMI_PY) over the phase logs · != 0 = not verifiable
  local r lg=("$log") f
  r=$(maat_cygm "$FIC_REPO" 2>/dev/null || printf '%s' "$FIC_REPO")
  for f in "$dir/log/$label".corsia-[12].jsonl; do [ -f "$f" ] && lg+=("$f"); done
  "$FIC_PY" -c "$NOMI_PY" "$r" "$1" "${lg[@]}" 2>>"$err" | tr -d '\r'
  return "${PIPESTATUS[0]}"
}
avviso() { # $1 = warning line: into the label's .stderr, into log/<label>.avvisi (then into .esito) and on stderr
  printf '%s\n' "$1" | tee -a "$err" "$dir/log/$label.avvisi" >&2
}
altri_flussi() { # implement/fix, conservative version: the paths changed in the phase and never named STAY in
  # touched.txt (the review sees them), annotated in log/<label>.altri-flussi with a warning. No STOP.
  local t0 t1 nm p c="$dir/log/$label.cambiati-fase" a="$dir/log/$label.altri-flussi"
  t0=$(cat "$pre_file" 2>/dev/null); t1=$(cat "${pre_file%.pre-tree}.post-tree" 2>/dev/null)
  [ -n "$t0" ] && [ -n "$t1" ] || return 0
  (cd "$FIC_REPO" && git -c core.quotePath=false diff --name-only --no-renames "$t0" "$t1") 2>/dev/null | tr -d '\r' | grep -v '^$' > "$c"
  [ -s "$c" ] || return 0
  if ! nm=$(nominati "$c"); then
    echo "AVVISO: $(msg run-phase.names_unverifiable)" >> "$err"
    return 0
  fi
  printf '%s\n' "$nm" | awk -F'\t' '$1 == "mai" { print $2 }' > "$a"
  [ -s "$a" ] || { rm -f "$a"; return 0; }
  while IFS= read -r p; do
    avviso "AVVISO: $(msg run-phase.other_flow_kept p="$p")"
  done < "$a"
}

owned=0 cpid="" cpid2="" vpid="" held=""
# Release: never while the subsession is alive, nor the background VERIFY (parallel review, harness-pt09).
# If run-phase receives SIGTERM (TaskStop) while `claude` keeps writing code, or while gates.sh and
# counterproof.sh are running, the lock stays; it can be taken over when none of them is alive.
release() {
  [ $owned -eq 1 ] || return 0
  alive "$cpid" && return 0
  alive "$cpid2" && return 0
  alive "$vpid" && return 0
  rm -rf "$held"; owned=0
}
# Locks are taken BEFORE touching log/<label>.*: a second launch with the same label as the
# live phase (repeated sequential labels: incident ux-6) must neither truncate its log nor write its .exit.
notes=""   # messages to put into the label's .stderr, once taken
busy() { # $1 = busy lock directory, $2 = first line of the message
  local msg o_run o_label
  msg="$2 — $([ -f "$1/owner" ] && tr '\n' ' ' < "$1/owner")
$(msg run-phase.busy_retry lock="$1")"
  echo "$msg" >&2
  o_run=$(sed -n 's/^run=//p' "$1/owner" 2>/dev/null); o_label=$(sed -n 's/^label=//p' "$1/owner" 2>/dev/null)
  # unreadable owner or same label in the same run dir: the label files belong to the live phase
  if [ -z "$o_label" ] || { [ "$o_run" = "$dir" ] && [ "$o_label" = "$label" ]; }; then
    echo "$(msg run-phase.same_label label="$label")" >&2
    exit 4
  fi
  rm -f "$dir/log/$label.esito" "$dir/log/$label.result.json"; : > "$log"; echo "$msg" > "$err"
  finish 4
}
take_lock() { # $1 = lock directory, $2 = message if busy; sets orphan_run
  local L=$1 tries=0
  until mkdir "$L" 2>/dev/null; do
    if lock_alive "$L" || [ $tries -ge 3 ]; then busy "$L" "$2"; fi
    # Atomic takeover of the orphan: the mv succeeds for ONE contender only; the others retry the mkdir.
    if mv "$L" "$L.orfano.$$" 2>/dev/null; then
      notes="$notes${notes:+
}$(msg run-phase.lock_taken what="$3"): $([ -f "$L.orfano.$$/owner" ] && tr '\n' ' ' < "$L.orfano.$$/owner")"
      echo "$(msg run-phase.lock_taken what="$3")" >&2
      orphan_run=$(sed -n 's/^run=//p' "$L.orfano.$$/owner" 2>/dev/null)
      rm -rf "$L.orfano.$$"
    fi
    tries=$((tries + 1))
  done
  owned=1 held=$L
  trap release EXIT
  printf 'run=%s\nlabel=%s\nsince=%s\npid=%s\n' "$dir" "$label" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" > "$L/owner"
}
code_phase=0
case "$phase" in implement|review|fix|chiusura|test-red) code_phase=1 ;; esac
orphan_run=""
if [ "$phase" = plan ]; then   # per-spec lock (see LOCK): <run-dir>/plan.lock
  take_lock "$dir/plan.lock" "$(msg run-phase.lock_plan_busy)" "$(msg run-phase.lock_plan_orphan)"
  orphan_run=""   # a plan does not change the tree: no attribution to close
elif [ $code_phase -eq 1 ]; then
  take_lock "$LOCK" "$(msg run-phase.lock_busy)" "$(msg run-phase.lock_orphan)"
fi

# --- from here on the label files are ours: they are reset (also those of a previous launch's watcher) ---
rm -f "$ex" "$dir/log/$label.esito" "$log.result" "$log.pos" "$log.pending" "$dir/log/$label.gates" "$dir/log/$label.prompt" \
  "$dir/log/$label.result.json" "$dir/log/$label.finalize" "$dir/log/$label.parallelo" "$dir/log/$label.counterproof" \
  "$dir/log/$label.spec-pre" "$dir/log/$label.gates.scartato" "$dir/log/$label.counterproof.scartato" \
  "$dir/log/$label.corsie" "$dir/log/$label.cambiati" "$dir/log/$label.posteriori" "$dir/log/$label".corsia-* \
  "$dir/log/$label.cambiati-fase" "$dir/log/$label.altri-flussi" "$dir/log/$label.avvisi" "$dir/log/$label.touched-pre"
: > "$log"
printf '%s' "${notes:+$notes
}" > "$err"

# FIC_REPO already set wins (needed by the tests, with a temporary repo).
FIC_REPO=$PROJECT_ROOT   # = FIC_REPO if set, otherwise the git toplevel of the working folder
[ -n "$FIC_REPO" ] || { echo "$(msg run-phase.not_a_repo)" >> "$err"; finish 2; }
export FIC_REPO
PC="$MAAT_SCRIPTS/plan-check.sh"
SPEC_F="${dir%.run}.md"
TR="$dir/test-red"
if [ "$phase" = test-red ] || [ "$phase" = test-stage ]; then   # harness-pt11: format 2 only
  { [ -f "$SPEC_F" ] && bash "$PC" contract "$SPEC_F" 2>/dev/null | tr -d '\r' | grep -qx 'Plan format: 2'; } ||
    { echo "$(msg run-phase.format2_only phase="$phase" spec="$SPEC_F")" | tee -a "$err" >&2; finish 2; }
fi

# --- harness fingerprint: recorded at the first launch, checked at every later phase ---
hfp_file="$dir/harness.fp"
if [ -f "$hfp_file" ]; then
  hfp_c=$(hfp_confronta "$hfp_file" "$FIC_REPO")
  if [ "$hfp_c" != UGUALE ]; then
    read -r hfp_esito hfp_a hfp_b <<< "$hfp_c"
    hfp_since=$(date -u -r "$hfp_file" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    hfp_root=$(maat_cygm "$MAAT_ROOT" 2>/dev/null || printf '%s' "$MAAT_ROOT")
    hfp_rimedio="bash \"$(maat_cygm "$MAAT_SCRIPTS/run-phase.sh" 2>/dev/null || printf '%s' "$MAAT_SCRIPTS/run-phase.sh")\" --harness-fp > \"$hfp_file\""
    # 1.6.0 (block Z): on Windows the command mixes C:/… and /tmp/… paths, so it runs in Git Bash, not in PowerShell;
    # the note is printed on every platform (the same message everywhere, like `next` of driver.py), as a shell
    # comment: the printed command still runs as is when pasted (spazi.test.sh runs it)
    hfp_rimedio="$hfp_rimedio # $(msg run-phase-z.rim_git_bash)"
    case "$hfp_esito" in
      CAMBIATO) hfp_msg="STOP: $(msg run-phase.hfp_changed since="$hfp_since" a="$hfp_a" b="$hfp_b" root="$hfp_root" rim="$hfp_rimedio")" ;;
      FORMATO-PRECEDENTE) hfp_msg="STOP: $(msg run-phase.hfp_old a="$hfp_a" since="$hfp_since" b="$hfp_b" rim="$hfp_rimedio")" ;;
      ILLEGGIBILE) hfp_msg="STOP: $(msg run-phase.hfp_unreadable since="$hfp_since" a="$hfp_a" rim="$hfp_rimedio")" ;;
      *) hfp_msg="STOP: $(msg run-phase.hfp_nc_stop root="$hfp_root" repo="$FIC_REPO" since="$hfp_since")" ;;
    esac
    echo "$hfp_msg" | tee -a "$err" >&2
    finish 6
  fi
elif [ $fresh -eq 1 ]; then
  if hfp_now=$(hfp_stampa "$FIC_REPO"); then printf '%s\n' "$hfp_now" > "$hfp_file"
  else echo "AVVISO: $(msg run-phase.hfp_not_recorded)" >> "$err"; fi
fi

# The killed phase belonged to ANOTHER feature: its .pre-tree is closed now, before this phase
# changes the tree, otherwise this phase's work would end up in that one's touched.txt.
if [ -n "$orphan_run" ] && [ "$orphan_run" != "$dir" ] && [ -d "$orphan_run/log" ]; then
  for f in "$orphan_run"/log/*.pre-tree; do
    [ -f "$f" ] && [ ! -f "${f%.pre-tree}.post-tree" ] && close_pre "$f" "$orphan_run"
  done
fi

# --- guard: a single command, for the self-test and for the hook ---
. "$HERE/python.sh" || { echo "$(msg run-phase.guard_no_python)" | tee -a "$err" >&2; finish 5; }
GUARD="$MAAT_SCRIPTS/guard.py"
HOOK_CMD="\"$FIC_PY\" \"$GUARD\""
# the project's maat.json for the two guards (this one and the plugin's) and for the self-test: MAAT_CONFIG as an absolute
# path. Without the file it is not exported: the guard falls back anyway to «maat.json non trovato».
if [ -z "${MAAT_CONFIG:-}" ] && [ -n "${PROJECT_ROOT:-}" ] && [ -f "$PROJECT_ROOT/.claude/maat.json" ]; then
  MAAT_CONFIG=$PROJECT_ROOT/.claude/maat.json
fi
if [ -n "${MAAT_CONFIG:-}" ]; then
  # Relative made absolute in bash, like plan-check.sh: outside Windows maat_cygm -a is missing and the relative path stayed relative.
  case $MAAT_CONFIG in
    /*|[A-Za-z]:[/\\]*) ;;
    *) # Windows form even without cygpath (pwd -W); unreachable folder -> relative to the current folder
       if _d=$(cd "$(dirname "$MAAT_CONFIG")" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); then
         MAAT_CONFIG=$_d/$(basename "$MAAT_CONFIG")
       else MAAT_CONFIG=$PWD/$MAAT_CONFIG; fi; unset _d ;;
  esac
  MAAT_CONFIG=$(maat_cygm "$MAAT_CONFIG" 2>/dev/null || printf '%s' "$MAAT_CONFIG")
  export MAAT_CONFIG
fi
# probe: the output of `maat-config.py sonda-produzione` (also with exit 3, the core fallback); without a readable
# maat.json, the core command. It must exit 2, otherwise exit 5.
probe_cmd=$(PROJECT_ROOT=${PROJECT_ROOT:-} "$FIC_PY" "$MAAT_SCRIPTS/maat-config.py" sonda-produzione 2>/dev/null | tr -d '\r' | head -1)
[ -n "$probe_cmd" ] || probe_cmd="git push --force origin x"
probe_esc=${probe_cmd//\\/\\\\}; probe_esc=${probe_esc//\"/\\\"}
probe='{"tool_name":"Bash","tool_input":{"command":"'"$probe_esc"'"}}'
printf '%s' "$probe" | eval "$HOOK_CMD" >/dev/null 2>&1
if [ $? -ne 2 ]; then
  echo "$(msg run-phase.guard_probe probe="$probe_cmd" hook="$HOOK_CMD")" | tee -a "$err" >&2
  finish 5
fi
mapfile -t DENY < <("$FIC_PY" "$GUARD" --deny-list 2>/dev/null | tr -d '\r')
if [ ${#DENY[@]} -eq 0 ]; then
  echo "$(msg run-phase.guard_deny_empty hook="$HOOK_CMD")" | tee -a "$err" >&2
  finish 5
fi
# Stop hook (harness-pt04, 1g): denies the end of turn without `PHASE RESULT` or with background jobs not
# collected; stop_hook_active against the loop. Fails open (lets it close): that is the safe direction.
STOP_PY="$MAAT_SCRIPTS/stop-hook.py"
STOP_CMD=""
if [ -f "$STOP_PY" ]; then STOP_CMD="\"$FIC_PY\" \"$(cd "$(dirname "$STOP_PY")" && { pwd -W 2>/dev/null || pwd; })/stop-hook.py\""
else echo "AVVISO: $(msg run-phase.stop_hook_missing stop="$STOP_PY")" >> "$err"; fi
SETTINGS=$("$FIC_PY" -c 'import json, sys
h = {"PreToolUse": [{"matcher": "Bash|Edit|Write|NotebookEdit|MultiEdit|Agent|Task", "hooks": [{"type": "command", "command": sys.argv[1]}]}]}
if sys.argv[2]:
    h["Stop"] = [{"hooks": [{"type": "command", "command": sys.argv[2]}]}]
print(json.dumps({"hooks": h}))' "$HOOK_CMD" "$STOP_CMD")

# --- gates run by the driver (harness-pt04, 1d): outside the subsession, evidence in evidence/ ---
# After every implement/fix finished OK and before every review: script/fic/gates.sh with the level in force and the
# touched.txt files; the outcome in log/<label>.gates. The review receives the evidence folder in the prompt.
GATES=${FIC_GATES:-$MAAT_SCRIPTS/gates.sh}
gates_level() { # --tests=<l> in the prompt, then the plan's Test level: line (plan-check.sh contract), then legacy
  local l
  [ "$phase" = chiusura ] && { echo full; return; }   # closing of a chain: always full
  l=$(tr -d '\r' < "$prompt" | grep -o -- '--tests=[a-z]*' | head -1 | cut -d= -f2)
  [ -z "$l" ] && [ -f "${dir%.run}.md" ] &&
    l=$(bash "$MAAT_SCRIPTS/plan-check.sh" contract "${dir%.run}.md" 2>/dev/null | tr -d '\r' | sed -n 's/^Test level: \([a-z]*\).*/\1/p' | head -1)
  case $l in min|std|full) echo "$l" ;; *) echo legacy ;; esac
}
run_gates() { # prints the evidence folder (nothing if the gates did not start)
  local g="$dir/log/$label.gates" lvl rc files=()
  if [ ! -f "$dir/touched.txt" ]; then echo "gates: $(msg run-phase.gates_no_touched)" > "$g"; return 0; fi
  if [ ! -f "$GATES" ]; then echo "gates: $(msg run-phase.gates_missing gates="$GATES")" > "$g"; return 0; fi
  lvl=$(gates_level)
  mapfile -t files < <(tr -d '\r' < "$dir/touched.txt" | grep -v '^$')
  FIC_GATES_ROOT="$FIC_REPO" bash "$GATES" --run-dir "$dir" "$lvl" ${files[@]+"${files[@]}"} > "$g" 2>&1; rc=$?
  echo "exit=$rc livello=$lvl" >> "$g"
  sed -n 's/^gates: esito=.* evidence=\(.\{2,\}\)$/\1/p' "$g" | tail -1
}

# --- review ∥ VERIFY (harness-pt09): see REVIEW IN PARALLEL WITH VERIFICATION at the top ---
MUT="$dir/counterproof/mutations.json"
CP_SH=${FIC_COUNTERPROOF:-$MAAT_SCRIPTS/counterproof.sh}
cp_driver=0
wslp() { local w; w=$(maat_cygm "$1" 2>/dev/null || printf '%s' "$1")
  case $w in [A-Za-z]:/*) printf '/mnt/%s%s' "$(printf '%s' "${w:0:1}" | tr 'A-Z' 'a-z')" "${w:2}" ;; *) printf '%s' "$w" ;; esac; }
sq() { local s=${1//\'/\'\\\'\'}; printf "'%s'" "$s"; }
review_status() { # Review status: recorded in the spec's review section (empty if missing)
  [ -f "${dir%.run}.md" ] || return 0
  tr -d '\r' < "${dir%.run}.md" | sed -nE '/^## (Review implementazione|Implementation review)/,$ s/^Review status: *//p' | head -1
}
verify_key() { # tree key: review-surface.sh tree + (driver counterproofs) sha256 of mutations.json
  local t; t=$(tree_now) && [ -n "$t" ] || return 1
  if [ $cp_driver -eq 1 ]; then printf '%s mutations=%s\n' "$t" "$([ -f "$MUT" ] && sha256sum < "$MUT" | cut -c1-64)"
  else printf '%s\n' "$t"; fi
}
cp_ids() { "$FIC_PY" -c 'import json, sys
try:
    l = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    l = []
for e in l if isinstance(l, list) else []:
    i = e.get("id") if isinstance(e, dict) else None
    if isinstance(i, str) and i.strip() and "/" not in i and "\\" not in i and not i.startswith("."):
        print(i)' "$MUT" 2>/dev/null | tr -d '\r'; }
cp_clear() { local i; while IFS= read -r i; do [ -n "$i" ] && rm -f "$dir/counterproof/$i.json"; done < <(cp_ids); }
PC_SH=${FIC_PLAN_CHECK:-$MAAT_SCRIPTS/plan-check.sh}
cp_from_gen() { # 0 = mutations.json is what `plan-check.sh gen` (pt10) generates NOW from the approved plan:
  # <run>/gen/procedura.txt with the current "Impronta piano:" and the list identical to one regenerated here, in a
  # separate folder (gen does not write a marker). Format 1, list written by a worker, plan changed: 1.
  local spec="${dir%.run}.md" t="$dir/log/.gen-verifica.$$" fr fn rc=1
  [ -s "$MUT" ] && [ -f "$dir/gen/procedura.txt" ] && [ -f "$spec" ] && [ -f "$PC_SH" ] || return 1
  rm -rf "$t"; mkdir -p "$t" || return 1
  if bash "$PC_SH" gen "$spec" --run-dir "$t" >/dev/null 2>&1 && [ -f "$t/gen/procedura.txt" ] && [ -f "$t/counterproof/mutations.json" ]; then
    fr=$(tr -d '\r' < "$dir/gen/procedura.txt" | sed -n 's/^Impronta piano: *//p' | head -1)
    fn=$(tr -d '\r' < "$t/gen/procedura.txt" | sed -n 's/^Impronta piano: *//p' | head -1)
    [ -n "$fn" ] && [ "$fr" = "$fn" ] && cmp -s <(tr -d '\r' < "$MUT") <(tr -d '\r' < "$t/counterproof/mutations.json") && rc=0
  fi
  rm -rf "$t"; return $rc
}
# Counterproofs run inside WSL ONLY on Windows (uname/OSTYPE, never the presence of wsl.exe) and with a mutations
# module `ambiente: wsl` in maat.json (the module of files and tests, as routed by the imported reader); otherwise
# counterproof.sh runs directly: on Linux, or on Windows without wsl modules, wsl.exe is not needed (and may be missing).
CP_WSL_PY='
import importlib.util, json, os, sys
import sys; sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
spec = importlib.util.spec_from_file_location("maat_config", os.environ["MAAT_CONFIG_PY"])
mc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mc)
try:
    cfg, _p = mc.carica()
except mc.Uscita:
    sys.exit(0)
r = mc.risolto(cfg)
amb = {m["nome"]: m.get("ambiente", "nativo") for m in r["moduli"]}
for e in json.load(open(sys.argv[1], encoding="utf-8")):
    if not isinstance(e, dict):
        continue
    for p in (e.get("file"), (e.get("test") or {}).get("percorso")):
        d = mc.instrada(r, p) if isinstance(p, str) and p else None
        if d is not None and amb.get(d[0]) == "wsl":
            print("wsl")
            sys.exit(0)
'
cp_in_wsl() { # 0 = counterproof.sh must be launched inside WSL
  case "${OSTYPE:-}:$(uname -s 2>/dev/null)" in *msys*|*cygwin*|*:MINGW*|*:MSYS*|*:CYGWIN*) ;; *) return 1 ;; esac
  PROJECT_ROOT=$FIC_REPO MAAT_CONFIG_PY="$MAAT_SCRIPTS/maat-config.py" "$FIC_PY" -c "$CP_WSL_PY" "$MUT" 2>/dev/null |
    tr -d '\r' | grep -qx wsl
}
run_cp() { # driver counterproofs: counterproof.sh (pt05) on mutations.json; outcome in log/<label>.counterproof
  local c="$dir/log/$label.counterproof" rc env_w
  cp_clear   # no result of a previous round survives this one
  if [ -n "${FIC_CP_CMD:-}" ]; then "$FIC_CP_CMD" "$MUT" > "$c" 2>&1; rc=$?
  elif [ ! -f "$CP_SH" ]; then echo "$(msg run-phase.cp_missing cp="$CP_SH")" > "$c"; rc=127
  elif cp_in_wsl; then
    # project root and maat.json translated for WSL: counterproof.sh does not derive them from its own location
    env_w="PROJECT_ROOT=$(sq "$(wslp "$FIC_REPO")")"
    [ -n "${MAAT_CONFIG:-}" ] && env_w+=" MAAT_CONFIG=$(sq "$(wslp "$MAAT_CONFIG")")"
    [ -n "${MAAT_LINGUA:-}" ] && env_w+=" MAAT_LINGUA=$(sq "$MAAT_LINGUA")"
    MSYS_NO_PATHCONV=1 wsl -- bash -lc "$env_w bash $(sq "$(wslp "$CP_SH")") $(sq "$(wslp "$MUT")")" > "$c" 2>&1; rc=$?
  else PROJECT_ROOT=$FIC_REPO bash "$CP_SH" "$MUT" > "$c" 2>&1; rc=$?; fi
  echo "exit=$rc" >> "$c"
  # 3 = environment BLOCKED: the results of that run do not count even if they exist (and so does every exit outside 0/1/2)
  case $rc in 0|1|2) ;; *) cp_clear ;; esac
}
launch() { # $1 = stdin file, $2 = ">" or ">>" on the log; sets code
  if [ "$2" = ">>" ]; then
    CLAUDE_PLUGIN_ROOT=$MAAT_ROOT "$CL" -p --permission-mode bypassPermissions --disallowedTools "${DENY[@]}" --settings "$SETTINGS" --strict-mcp-config \
      ${SCHEMA_ARGS[@]+"${SCHEMA_ARGS[@]}"} ${PLUGIN_ARGS[@]+"${PLUGIN_ARGS[@]}"} --append-system-prompt "$CHILD_RULES_TXT" \
      --output-format stream-json --verbose < "$1" >> "$log" 2>> "$err" &
  else
    CLAUDE_PLUGIN_ROOT=$MAAT_ROOT "$CL" -p --permission-mode bypassPermissions --disallowedTools "${DENY[@]}" --settings "$SETTINGS" --strict-mcp-config \
      ${SCHEMA_ARGS[@]+"${SCHEMA_ARGS[@]}"} ${PLUGIN_ARGS[@]+"${PLUGIN_ARGS[@]}"} --append-system-prompt "$CHILD_RULES_TXT" \
      --output-format stream-json --verbose < "$1" > "$log" 2>> "$err" &
  fi
  cpid=$!
  if [ $owned -eq 1 ]; then sed -i '/^cpid=/d' "$held/owner" 2>/dev/null; echo "cpid=$cpid" >> "$held/owner"; fi
  wait $cpid
  code=$?
}

# --- chain (harness-pt12, see CHAINS): at the start of a ring, before measuring its .pre-tree ---
is_ring() { # is the spec of this run dir listed in the Figlie: (Children:) line of a mother in the same folder?
  [ -f "${dir%.run}.md" ] && grep -lsE '^(Figlie|Children):' "$(dirname "$dir")"/spec-*.md 2>/dev/null | xargs -r grep -lF -- "$(basename "${dir%.run}")" >/dev/null 2>&1
}
# INTERNAL READERS (1.5.1): every answer of the table and of the driver has a State: line before Next:
# (cycle-state.sh, top); only a STOP of its wrapper (no usable Python, Python older than 3.10, driver failed) has none.
# The absence of State: is therefore the marker: it does not depend on the language nor on the catalog texts, and it
# covers any future STOP of the wrapper. The four reads below all go through here: a STOP of the wrapper is a phase not
# launched (start of a ring, review of a ring) or a STOP outcome (end of a phase), never an OK outcome with state= empty.
cycle_state_read() { # <spec>: the output in cso; 1 = no State: line, the reason in cs_why (text after "Next: STOP — ")
  local rc
  cso=$(bash "$HERE/cycle-state.sh" "$1" 2>>"$err"); rc=$?
  cso=${cso//$'\r'/}; cs_why=""
  grep -q '^State: ' <<< "$cso" && return 0
  cs_why=$(printf '%s\n' "$cso" | sed -n 's/^Next: //p' | head -1); cs_why=${cs_why#STOP — }
  [ -n "$cs_why" ] || cs_why=$(msg run-phase-engine.cs_no_state rc="$rc")
  return 1
}
if [ "$phase" = implement ] && ! ls "$dir/log" 2>/dev/null | grep -q '\.pre-tree$' && is_ring; then
  cycle_state_read "${dir%.run}.md" || { echo "STOP — $cs_why — $(msg run-phase.not_launched)" | tee -a "$err" >&2; finish 7; }
  cn=$(printf '%s\n' "$cso" | sed -n 's/^Next: //p')
  case "$cn" in "STOP — catena"*|"WAIT — catena"*) echo "$cn — $(msg run-phase.not_launched)" | tee -a "$err" >&2; finish 7 ;; esac
fi
# closing of a chain: prepares the MOTHER's run dir (touched.txt, base.txt) and finds the children's e2e
chz_fail="" chz_e2e=""
chiusura_prep() {
  local m="${dir%.run}.md" d c first="" b kids
  d=$(dirname "$m")
  [ -f "$m" ] || { chz_fail="$(msg run-phase.mother_missing m="$m")"; return; }
  kids=$(tr -d '\r' < "$m" | awk '{ isf = ($0 ~ /^[ \t]*(```|~~~)/) } isf { inf = !inf; next } inf { next }
    /^## (Piano di implementazione|Review implementazione|Implementation plan|Implementation review)/ { exit } /^(Figlie|Children):/ { print; exit }' | grep -o 'spec-[A-Za-z0-9._-]*' | sed 's/\.md$//; s/\.$//')
  [ -n "$kids" ] || { chz_fail="$(msg run-phase.mother_no_children)"; return; }
  : > "$dir/touched.txt.chiusura"
  for c in $kids; do
    [ -n "$first" ] || first=$c
    [ -f "$d/$c.run/touched.txt" ] || chz_fail="${chz_fail:+$chz_fail; }$(msg run-phase.ring_no_touched c="$c")"
    [ -f "$d/$c.run/touched.txt" ] && tr -d '\r' < "$d/$c.run/touched.txt" >> "$dir/touched.txt.chiusura"
    chz_e2e="$chz_e2e $([ -f "$d/$c.md" ] && tr -d '\r' < "$d/$c.md" | sed -n 's/^[[:space:]]*\([-*]\|[0-9][0-9]*\.\)[[:space:]]\{1,\}\[e2e-locator:[[:space:]]*\([^]]*\)\].*/\2/p' | sed 's/[[:space:]]*$//' | tr '\n' ' ')"
  done
  grep . "$dir/touched.txt.chiusura" | sort -u > "$dir/touched.txt"; rm -f "$dir/touched.txt.chiusura"
  [ -s "$dir/touched.txt" ] || chz_fail="${chz_fail:+$chz_fail; }$(msg run-phase.rings_no_files)"
  b=$([ -f "$d/$first.run/base.txt" ] && tr -d '\r\n ' < "$d/$first.run/base.txt")
  if [ -n "$b" ]; then echo "$b" > "$dir/base.txt"; else chz_fail="${chz_fail:+$chz_fail; }$(msg run-phase.first_no_base first="$first")"; fi
  chz_e2e=$(printf '%s\n' $chz_e2e | grep . | sort -u | tr '\n' ' ' | sed 's/ $//')
}

# 1.8.0 (A1): the test-data deviations of test-red (DEV_PY). «ammesse <result.json> <jsonl> <originale 0|1>»: exit 0
# when the ONLY cause of the
# STOP of `valida` is deviations — esito OK, bloccato_su none, every deviation test-data:/dati-test: or difensiva:/
# defensive:, at least one test-data — printing «motivo\t<motivo>» then one test-data deviation per line; else exit 1.
# «giudice <jsonl> <out> <diff> <run dir> <root> <input file>…»: the first call of the MAIN session (transcript.py) to
# Agent/Task with subagent_type maat:spec-plan-reviewer-light whose prompt holds every input verbatim (CR removed) and
# that has a result that is not an asynchronous launch: its text into <out>, prints «ok»; else «mai» (no call of that
# type), «incompleto <n>» (the input files missing in the prompt, 1-based) or «asincrono» (no result in the foreground).
# 1.8.1 (G2-2, R6-R8): the LAST input (the diff) is also satisfied by the line «diff file: <p> · sha256 <s>» of
# `plan-check.sh diff-test --file`: <s> the sha256 of <diff> (the stdout of diff-test, recomputed here), <p> resolving
# to <run dir>/test-red/diff-test-<s[:16]>.diff (relative paths on <root>), that file still with sha256 <s>, at most
# 2000 lines of at most 2000 characters, and a Read of <p> by the sub-agent of THAT call (transcript.chiamate_figlie)
# without offset, without limit or with limit ≥ its lines, with a result not in error. Anything else: input missing.
# 1.9.1 (C2): a call whose prompt has a «judge file: <p> · sha256 <s>» line (plan-check.sh giudizio) is judged on that file
# only: the prompt holds that line and the fixed sentence and nothing else («extra»); <p> is the path computed here for
# DEV_TN (<run dir>/test-red/giudizio-<Tn>-<s[:16]>.md); the file has sha256 <s>, ONE «deviation: » line, and is byte for
# byte the blocks of DEV_BLOCCHI + that line + the recomputed diff; a whole Read of it by the sub-agent of that call.
# Otherwise «incompleto giudizio:<why>» (frase, percorso, file, sha, contenuto, tn, read). The judged line goes to
# DEV_TESTO_OUT. Without the line: the inline form above, unchanged.
# 1.9.0 (K6a, K0.3) «ammesse-impl <result.json> <jsonl> <originale 0|1>»: the same for implement/fix and the family
# «test-difettoso: » / «defective-test: » (every deviation of the family or defensive, at least one of the family).
# 1.9.0 (K6a, K0.5) «giudice --tutti <jsonl> <out prefix> <run dir> <root> <n> {<k> <diff> <input file>…}×n»: one group of
# input files per deviation (the last one its diff, also satisfied by «diff file:» as above). EVERY call of the main
# session to maat:spec-plan-reviewer-light counts, complete or not: «mai» (none, or a deviation without a complete
# call), «incompleto <n>» (only incomplete calls: the inputs missing in the first, 1-based), «rifiutato» (an incomplete
# call next to a complete one, or a complete call without a foreground result not in error with «Deviation verdict:
# ACCEPT»), «extra» (the prompt of a complete call, its inputs taken out once, holds non-blank characters), else «ok»
# and the result of the last complete call of deviation k in <out prefix><k>.result.
DEV_PY='
import importlib.util, json, os, re, sys
sys.dont_write_bytecode = True
one = lambda s: " ".join(str(s).split())
if sys.argv[1] in ("ammesse", "ammesse-impl"):
    fam = ("test-data: ", "dati-test: ") if sys.argv[1] == "ammesse" else ("test-difettoso: ", "defective-test: ")
    d = json.load(open(sys.argv[2], encoding="utf-8"))
    dev = [one(x) for x in d.get("deviazioni") or [] if str(x).strip()]
    td = [x for x in dev if x.startswith(fam)]
    ok = d.get("esito") == "OK" and one(d.get("bloccato_su") if d.get("bloccato_su") is not None else "-").lower() in ("nessuno", "none") \
        and td and all(x.startswith(fam + ("difensiva: ", "defensive: ")) for x in dev)  # AMMESSE-FAMIGLIA
    if ok and sys.argv[4] == "0":   # no originale=: valida saw no PHASE RESULT line in the text (structured_output only)
        res = None
        for ln in open(sys.argv[3], encoding="utf-8", errors="replace"):
            try:
                ev = json.loads(ln)
            except ValueError:
                continue
            if isinstance(ev, dict) and ev.get("type") == "result":
                res = ev
        txt = (res or {}).get("result") or ""
        ok = res is not None and not any(l.strip().startswith(("PHASE RESULT", "ESITO FASE")) for l in str(txt).splitlines())
    if not ok:
        sys.exit(1)
    sys.stdout.buffer.write(("motivo\t%s\n" % one(d.get("motivo") or "")[:300] + "".join(x + "\n" for x in td)).encode("utf-8"))
    sys.exit(0)
s = importlib.util.spec_from_file_location("transcript_rp", os.path.join(os.environ["MAAT_SCRIPTS_PY"], "transcript.py"))
tr = importlib.util.module_from_spec(s); s.loader.exec_module(tr)
import hashlib, posixpath
tutti = sys.argv[2] == "--tutti"
A = sys.argv[3:] if tutti else sys.argv[2:]
rr = tr.righe(A[0])
leggi = lambda f: open(f, encoding="utf-8", errors="replace").read().replace("\r", "")
if tutti:   # A = jsonl, out prefix, run dir, root, n, then n groups «k diff input…»
    G, a = [], A[5:]
    for _g in range(int(A[4])):
        k = int(a[0])
        G.append((open(a[1], "rb").read(), [leggi(f) for f in a[2:2 + k]]))
        a = a[2 + k:]
    RUND, ROOT = A[2], A[3]
else:
    G = [(open(A[2], "rb").read(), [leggi(f) for f in A[5:]])]
    RUND, ROOT = A[3], A[4]
calls = [c for c in tr.chiamate(rr) if c["name"] in tr.AGENT_TOOLS and c["input"].get("subagent_type") == "maat:spec-plan-reviewer-light"]
if not calls:
    print("mai"); sys.exit(0)
def chiave(x):   # R8: one form for a path — \ → /, C:/… = /c/… = /mnt/c/… (drive letter lower case), relative on the root
    x = str(x).replace("\\", "/")
    if not re.match(r"^(/|[A-Za-z]:/)", x):
        x = ROOT.replace("\\", "/").rstrip("/") + "/" + x
    m = re.match(r"^(?:([A-Za-z]):|/mnt/([a-z])(?=/|$)|/([A-Za-z])(?=/|$))(.*)$", x)
    if m:
        x = "/%s/%s" % ((m.group(1) or m.group(2) or m.group(3)).lower(), m.group(4).lstrip("/"))
    return posixpath.normpath(x)
def per_file(c, p, dd):   # G2-2 (b): the diff as a file the sub-agent of THIS call Read whole; the line, or None
    sha = hashlib.sha256(dd).hexdigest()
    atteso = os.path.join(RUND, "test-red", "diff-test-%s.diff" % sha[:16])
    try:
        txt = dd.decode("utf-8")
    except UnicodeDecodeError:
        return None
    rl = txt.split("\n")
    if rl and rl[-1] == "":
        rl.pop()
    if len(rl) > 2000 or any(len(l) > 2000 for l in rl):   # R7: the limits of Read
        return None
    try:
        if hashlib.sha256(open(atteso, "rb").read()).hexdigest() != sha:
            return None
    except OSError:
        return None
    posti = {chiave(atteso), chiave(os.path.realpath(atteso))}
    for m in re.finditer(r"^diff file: (.+?) \u00b7 sha256 ([0-9a-f]{64})[ \t]*$", p, re.M):
        if m.group(2) != sha or chiave(m.group(1)) not in posti:
            continue
        for f in tr.chiamate_figlie(rr, c["id"]):   # READ-DEL-GIUDICE
            fi = f["input"]
            lim = fi.get("limit")
            if f["name"] == "Read" and isinstance(fi.get("file_path"), str) and chiave(fi["file_path"]) in posti \
                    and "offset" not in fi and ("limit" not in fi or (type(lim) is int and lim >= len(rl))) \
                    and any(not err for _n, _t, err, _a in f["results"]):
                return m.group(0)
    return None
def mancano(c, p, dd, ii):   # (the missing inputs, 1-based, as strings; the «diff file:» line that stands for the diff)
    miss = [str(k + 1) for k, x in enumerate(ii) if x not in p]  # INGRESSI-DEL-GIUDICE
    fl = None
    if miss and miss[-1] == str(len(ii)):   # R8: only the LAST input, the diff
        fl = per_file(c, p, dd)
        if fl is not None:
            miss = miss[:-1]
    return miss, fl
FRASE = "Read that file whole with Read before judging: it holds your instructions, the plan rows, the deviation and the diff."
JF = re.compile(r"^judge file: (.+?) · sha256 ([0-9a-f]{64})[ \t]*$", re.M)
def pulito(p, ms):   # 1.9.1 (C2) PROMPT-PULITO: beside the one «judge file:» line only its fixed sentence and spaces
    if len(ms) > 1:
        return "extra"
    q = p[:ms[0].start()] + p[ms[0].end():]
    if FRASE not in q:
        return "incompleto giudizio:frase"
    if re.sub(r"\s", "", q.replace(FRASE, "", 1)):
        return "extra"
    return None
if tutti:
    ACC = re.compile(r"^[ \t>*_`-]*Deviation verdict:[ \t*_`]*(.*?)[ \t*_`]*$", re.M)
    compl, incompl, esito = [], [], ""
    for c in calls:
        p = tr.testo(c["input"].get("prompt")).replace("\r", "")
        ms = list(JF.finditer(p))
        if ms:   # 1.9.1 (C2): the same PROMPT-PULITO here; a clean judge file is not an input of this branch (fail-closed)
            print(pulito(p, ms) or "incompleto giudizio:ramo"); sys.exit(0)
        best = None
        for g, (dd, ii) in enumerate(G):
            miss, fl = mancano(c, p, dd, ii)
            if not miss:
                q = p
                for x in ii + ([fl] if fl else []):
                    q = q.replace(x, "", 1)
                compl.append((c, g, re.sub(r"\s", "", q) != ""))   # EXTRA-NEL-PROMPT
                best = None
                break
            if best is None or len(miss) < len(best):
                best = miss
        else:
            incompl.append(best)
    res = {}
    if not compl:
        print("incompleto " + ",".join(incompl[0])); sys.exit(0)
    if incompl:   # TUTTE-LE-CHIAMATE: a call of the judge in the phase that is not complete
        print("rifiutato"); sys.exit(0)
    for c, g, extra in compl:
        ok = [t for _n, t, err, asin in c["results"] if not asin and not err]
        v = ACC.findall(ok[-1]) if ok else []
        if not v or not re.match(r"ACCEPT\b(?!\s*\|)", v[-1]):   # OGNI-CHIAMATA-ACCEPT
            print("rifiutato"); sys.exit(0)
        if extra:
            esito = esito or "extra"
        res[g] = ok[-1]
    if esito:
        print(esito); sys.exit(0)
    if len(res) != len(G):   # a deviation without a complete call of its own
        print("mai"); sys.exit(0)
    for g, t in res.items():
        open("%s%d.result" % (A[1], g + 1), "w", encoding="utf-8").write(t)
    print("ok"); sys.exit(0)
def giudizio(c, p, dd):   # 1.9.1 (C2): the judge file of plan-check.sh giudizio; None without a «judge file:» line
    ms = list(JF.finditer(p))
    if not ms:
        return None
    e = pulito(p, ms)
    if e:
        return e, None
    m = ms[0]
    # GIUDIZIO-PERCORSO: the path the driver computes for the Tn of THIS deviation, never the one of the prompt;
    # its 16 hex = the head of the sha256 of the line
    tn, sha = os.environ.get("DEV_TN", ""), m.group(2)
    mm = re.match(r"^giudizio-(.+)-([0-9a-f]{16})\.md$", posixpath.basename(m.group(1).replace("\\", "/")))
    if not tn or not mm or mm.group(1) != tn or mm.group(2) != sha[:16]:
        return "incompleto giudizio:percorso", None
    atteso = os.path.join(RUND, "test-red", "giudizio-%s-%s.md" % (tn, sha[:16]))
    posti = {chiave(atteso), chiave(os.path.realpath(atteso))}
    if chiave(m.group(1)) not in posti:
        return "incompleto giudizio:percorso", None
    try:
        b = open(atteso, "rb").read()
    except OSError:
        return "incompleto giudizio:file", None
    if hashlib.sha256(b).hexdigest() != sha:
        return "incompleto giudizio:sha", None
    try:
        t = b.decode("utf-8")
    except UnicodeDecodeError:
        return "incompleto giudizio:contenuto", None
    dl = [l for l in t.split("\n") if l.startswith("deviation: ")]
    if len(dl) != 1:
        return "incompleto giudizio:contenuto", None
    riga = dl[0][len("deviation: "):]
    # GIUDIZIO-RICOMPOSTO: the whole file again from the blocks computed NOW, the one line and the recomputed diff,
    # byte for byte (never a containment check)
    blocchi = open(os.environ["DEV_BLOCCHI"], "rb").read()
    if blocchi + ("deviation: %s\n" % riga).encode("utf-8") + dd != b:
        return "incompleto giudizio:contenuto", None
    if not re.match(re.escape(tn) + r"[ \t]*—", re.sub(r"^(test-data|dati-test): *", "", riga)):
        return "incompleto giudizio:tn", None
    rl = t.split("\n")
    if rl and rl[-1] == "":
        rl.pop()
    for f in tr.chiamate_figlie(rr, c["id"]):   # READ-DEL-GIUDICE, as per_file
        fi = f["input"]
        lim = fi.get("limit")
        if f["name"] == "Read" and isinstance(fi.get("file_path"), str) and chiave(fi["file_path"]) in posti \
                and "offset" not in fi and ("limit" not in fi or (type(lim) is int and lim >= len(rl))) \
                and any(not err for _n, _t, err, _a in f["results"]):
            return "ok", riga
    return "incompleto giudizio:read", None
dd, ii = G[0]
esito = "asincrono"
for c in calls:
    p = tr.testo(c["input"].get("prompt")).replace("\r", "")
    g = giudizio(c, p, dd)
    if g is not None:
        if g[0] != "ok":
            esito = g[0]
            continue
        for _n, t, err, asin in c["results"]:
            if not asin and not err:
                open(A[1], "w", encoding="utf-8").write(t)
                open(os.environ["DEV_TESTO_OUT"], "w", encoding="utf-8").write(g[1])
                print("ok"); sys.exit(0)
        continue
    miss, _fl = mancano(c, p, dd, ii)
    if miss:
        esito = "incompleto " + ",".join(miss)
        continue
    for _n, t, err, asin in c["results"]:
        if not asin and not err:
            open(A[1], "w", encoding="utf-8").write(t)
            print("ok"); sys.exit(0)
print(esito)
'
# The checks of the test-data deviations after the usual verification (A1, all needed; the first that fails is the
# STOP): every acceptance test «dimostrato» in rossi.json; for each deviation its Tn a row of the plan, the judge in the
# foreground with the row, its traceability rows, the deviation and the diff RECOMPUTED here with `plan-check.sh diff-test`
# (the worker's command) in its prompt, and `plan-check.sh deviazione` ACCETTATA on its result. Writes
# log/<label>.deviazioni-test («<text>\t<verdict>\t<sha256 of the diff>») and the lines of log/deviazioni-accettate.txt.
pc_root() { # the repository root of plan-check.sh (its repo_root): the base of the relative path of «diff file:»
  if [ -n "${PLAN_CHECK_ROOT:-}" ]; then printf '%s' "$PLAN_CHECK_ROOT"; else git -C "$(dirname "$SPEC_F")" rev-parse --show-toplevel 2>/dev/null || pwd; fi
}
deviazioni_test() { # $1 = file with the test-data deviations (one per line); prints the cause of a STOP, nothing if accepted
  local d tn k=0 dl rc st out vd sha gt tmp="$dir/log/$label.deviazioni-test.tmp" pfx="$dir/log/$label.dev"
  "$FIC_PY" -c 'import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8")).get("test") or {}
sys.exit(0 if d and all(isinstance(v, dict) and v.get("esito") == "dimostrato" for v in d.values()) else 1)' "$TR/rossi.json" 2>>"$err" ||
    { msg run-phase-180.dev_not_proven; return 0; }   # DEV-DIMOSTRATI
  : > "$tmp"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    k=$((k + 1))
    tn=$(printf '%s\n' "$d" | sed -n 's/^\(test-data\|dati-test\): *\([A-Za-z0-9._-]*\) *—.*/\2/p')
    [ -n "$tn" ] || { msg run-phase-180.dev_no_tn d="$d"; return 0; }
    out=$(bash "$PC" deviazione - "$SPEC_F" "$tn" 2>>"$err" | tr -d '\r'); rc=$?
    [ $rc -eq 0 ] || { printf '%s\n' "$out" | sed -n 's/^Deviazione: STOP — //p' | head -1; return 0; }
    printf '%s' "$(printf '%s\n' "$out" | sed -n 's/^test row: //p')" > "$pfx$k.row"
    printf '%s\n' "$out" | sed -n 's/^trace row: //p' > "$pfx$k.traces"
    printf '%s\n' "$out" | sed -n 's/^other row: //p' > "$pfx$k.others"   # 1.9.1 (C1): the other tests of the file
    # 1.8.1 (G2-2): the text WITHOUT its family prefix (the regex of tn above): a substring of both forms, so the
    # prompt may hold it with or without the label; .deviazioni-test and deviazioni-accettate.txt keep $d (R9)
    printf '%s' "$(printf '%s\n' "$d" | sed 's/^\(test-data\|dati-test\): *//')" > "$pfx$k.text"   # TESTO-SENZA-PREFISSO
    bash "$PC" diff-test "$SPEC_F" "$(printf '%s\n' "$out" | sed -n 's/^test file: //p')" --run-dir "$dir" > "$pfx$k.diff" 2>>"$err" &&
      [ -s "$pfx$k.diff" ] || { msg run-phase-180.dev_no_diff tn="$tn"; return 0; }
    printf '%s' "$(cat "$pfx$k.diff")" > "$pfx$k.diff-in"   # the diff as the prompt holds it: without the final newline
    printf '%s' "$(printf '%s\n' "$out" | sed -n 's/^judge instructions: //p')" > "$pfx$k.instr"   # the fixed block (review)
    [ -s "$pfx$k.instr" ] || { msg run-phase-180.dev_no_diff tn="$tn"; return 0; }
    local inputs=("$pfx$k.instr" "$pfx$k.row") l j=0
    while IFS= read -r l; do j=$((j + 1)); printf '%s' "$l" > "$pfx$k.trace$j"; inputs+=("$pfx$k.trace$j"); done < "$pfx$k.traces"
    j=0
    while IFS= read -r l; do j=$((j + 1)); printf '%s' "$l" > "$pfx$k.other$j"; inputs+=("$pfx$k.other$j"); done < "$pfx$k.others"
    inputs+=("$pfx$k.text" "$pfx$k.diff-in")
    # 1.9.1 (C2): the blocks of `deviazione -` as plan-check.sh giudizio writes them (the judge file is recomposed from
    # them); the text the judge read comes back in $pfx$k.giudicato
    printf '%s\n' "$out" > "$pfx$k.blocchi"; rm -f "$pfx$k.giudicato"
    st=$(DEV_TN=$tn DEV_BLOCCHI=$(maat_cygm "$pfx$k.blocchi" 2>/dev/null || printf '%s' "$pfx$k.blocchi") \
      DEV_TESTO_OUT=$(maat_cygm "$pfx$k.giudicato" 2>/dev/null || printf '%s' "$pfx$k.giudicato") \
      MAAT_SCRIPTS_PY=$(maat_cygm "$MAAT_SCRIPTS" 2>/dev/null || printf '%s' "$MAAT_SCRIPTS") "$FIC_PY" -c "$DEV_PY" giudice "$log" "$pfx$k.result" \
      "$pfx$k.diff" "$dir" "$(pc_root)" "${inputs[@]}" 2>>"$err" | tr -d '\r')
    case "$st" in
      ok) ;;
      mai) msg run-phase-180.dev_judge_never tn="$tn"; return 0 ;;   # GIUDICE-CHIAMATO
      extra) msg run-phase-191.dev_judge_extra tn="$tn"; return 0 ;;
      "incompleto giudizio:"*) msg run-phase-191.dev_judge_file tn="$tn" why="${st#incompleto giudizio:}"; return 0 ;;
      incompleto*) msg run-phase-180.dev_judge_input tn="$tn" which="${st#incompleto }"; return 0 ;;
      *) msg run-phase-180.dev_judge_async tn="$tn"; return 0 ;;
    esac
    out=$(bash "$PC" deviazione "$pfx$k.result" "$SPEC_F" "$tn" 2>>"$err" | tr -d '\r'); rc=$?
    [ $rc -eq 0 ] || { printf '%s\n' "$out" | sed -n 's/^Deviazione: STOP — //p' | head -1; return 0; }  # DEVIAZIONE-ACCETTATA
    vd=$(tr -d '\r' < "$pfx$k.result" | sed -n 's/^[ \t>*_`-]*Deviation verdict:[ \t*_`]*//p' | tail -1 | sed 's/[ \t*_`]*$//')
    sha=$(sha256sum < "$pfx$k.diff" | cut -c1-64)
    # 1.9.1 (C2, decision 1): judged by file, the text the judge read; a different text in the result is not a STOP, the
    # column 1 stays the declared one (driver.py and cycle-report.py match on it) and a 4th column «giudicato=<text>»
    # keeps the judged one for the review
    gt=""
    if [ -s "$pfx$k.giudicato" ]; then
      gt=$(tr -d '\r\n' < "$pfx$k.giudicato" | sed 's/^\(test-data\|dati-test\): *//')
      [ "$(printf '%s' "$gt" | tr -s ' \t' ' ')" != "$(printf '%s\n' "$d" | sed 's/^\(test-data\|dati-test\): *//' | tr -s ' \t' ' ')" ] || gt=""
    fi
    if [ -n "$gt" ]; then printf '%s\t%s\t%s\tgiudicato=%s\n' "$d" "$vd" "$sha" "$gt" >> "$tmp"
    else printf '%s\t%s\t%s\n' "$d" "$vd" "$sha" >> "$tmp"; fi
  done < "$1"
  mv -f "$tmp" "$dir/log/$label.deviazioni-test"
  { [ -f "$dir/log/deviazioni-accettate.txt" ] && tr -d '\r' < "$dir/log/deviazioni-accettate.txt" | grep -v "^$label	"
    awk -F'\t' -v l="$label" '{ print l "\t" $1 "\t" $2 ($4 != "" ? "\t" $4 : "") }' "$dir/log/$label.deviazioni-test"; } > "$dir/log/deviazioni-accettate.txt.tmp" &&
    mv -f "$dir/log/deviazioni-accettate.txt.tmp" "$dir/log/deviazioni-accettate.txt"
}
# 1.8.1 (G2-1): the second round of verify_red (RED2_PY). «ammesso <rossi.json>»: exit 0 when the STOP of rossi has
# only suite conflicts (len(conflitti) == len(conflitti_suite) > 0: no static conflict, no vitest summary) and every
# acceptance test is dimostrato or sonda_smentita. «confronta <rossi1.json> <rossi2.json> <U>»: exit 1 when round 2 is
# not comparable (unreadable, BLOCKED, a conflict without identity, an outcome of a T different from round 1); else
# prints «P <n>» (the identities red in both rounds) and writes U, those red in one round only, one per line.
RED2_PY='
import json, sys
def load(p):
    try:
        d = json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return d if isinstance(d, dict) else None
def pura(d):
    c, cs, t = d.get("conflitti"), d.get("conflitti_suite"), d.get("test")
    return (isinstance(c, list) and isinstance(cs, list) and isinstance(t, dict) and bool(t) and len(c) == len(cs)
            and all(isinstance(x, dict) and isinstance(x.get("id"), str) for x in cs)
            and all(isinstance(v, dict) and v.get("esito") in ("dimostrato", "sonda_smentita") for v in t.values()))
if sys.argv[1] == "ammesso":
    d = load(sys.argv[2])
    sys.exit(0 if d is not None and d.get("esito") == "STOP" and pura(d) and d["conflitti"] else 1)
d1, d2 = load(sys.argv[2]), load(sys.argv[3])
if d1 is None or d2 is None or d2.get("esito") not in ("OK", "STOP") or not pura(d1) or not pura(d2):
    sys.exit(1)
if {k: v.get("esito") for k, v in d1["test"].items()} != {k: v.get("esito") for k, v in d2["test"].items()}:  # ESITI-UGUALI
    sys.exit(1)
c1 = [x["id"] for x in d1["conflitti_suite"]]
c2 = [x["id"] for x in d2["conflitti_suite"]]
p = set(c1) & set(c2)
u = [x for x in dict.fromkeys(c1 + c2) if x not in p]
open(sys.argv[4], "w", encoding="utf-8", newline="\n").write("".join(x + "\n" for x in u))
print("P %d" % len(p))
'
# 1.8.1 (G2-1, R1-R5): after a rossi STOP whose only cause are suite conflicts, ONE second round: the evidence of round 1
# renamed <ev>.giro1 (kept; gates.sh does not reuse its key), round 1 kept in log/<label>.gates1, .rossi1, .rossi1.json;
# the same gates.sh -> .gates2, rossi -> .rossi2. P (red in both) empty -> rossi a third time on the evidence of round 2
# with --instabili U, into .rossi and rossi.json, one AVVISO per unstable test; P not empty -> the STOP of round 2,
# «(confirmed on two rounds)». The round that decides also writes .gates and .rossi (classifica compares .rossi with
# rossi.json). Round 2 not usable or not comparable -> the STOP of round 1, restored (fail-closed). Declared limit (R5):
# a real conflict that is also unstable is reported as unstable. Sets rc and conf of verify_red.
giro1_resta() { # $1 = why round 2 is not used
  avviso "AVVISO: $(msg run-phase-181.round2_kept why="$1" label="$label")"
  cp -f "$dir/log/$label.gates1" "$g"; cp -f "$dir/log/$label.rossi1" "$ro"; cp -f "$dir/log/$label.rossi1.json" "$TR/rossi.json"
}
secondo_giro() {
  local g2="$dir/log/$label.gates2" r2="$dir/log/$label.rossi2" u="$dir/log/$label.instabili" ev2 rc2 cmp id
  "$FIC_PY" -c "$RED2_PY" ammesso "$TR/rossi.json" 2>>"$err" || return 0   # SECONDO-GIRO-AMMESSO
  cp -f "$g" "$dir/log/$label.gates1" && cp -f "$ro" "$dir/log/$label.rossi1" && cp -f "$TR/rossi.json" "$dir/log/$label.rossi1.json" || return 0
  rm -rf "$ev.giro1"
  mv "$ev" "$ev.giro1" 2>>"$err" || { giro1_resta "$(msg run-phase-181.r2_no_evidence)"; return 0; }   # EVIDENZA-GIRO1
  FIC_BUILD_CHIUSURA=0 FIC_GATES_ROOT="$FIC_REPO" bash "$GATES" --run-dir "$dir" std ${files[@]+"${files[@]}"} > "$g2" 2>&1; rc2=$?  # NO-BUILD-RED
  echo "exit=$rc2 livello=std ($(msg run-phase.red_level))" >> "$g2"
  ev2=$(sed -n 's/^gates: esito=.* evidence=\(.\{2,\}\)$/\1/p' "$g2" | tail -1)
  if [ -z "$ev2" ] || [ "$ev2" = - ] || grep -q '^gates: esito=BLOCKED' "$g2"; then
    giro1_resta "$(msg run-phase-181.r2_no_evidence)"; return 0
  fi
  bash "$PC" rossi "$SPEC_F" --evidence "$ev2" --run-dir "$dir" > "$r2" 2>&1; rc2=$?
  [ $rc2 -le 1 ] || { giro1_resta "$(msg run-phase-181.r2_no_evidence)"; return 0; }
  cmp=$("$FIC_PY" -c "$RED2_PY" confronta "$dir/log/$label.rossi1.json" "$TR/rossi.json" "$u" 2>>"$err" | tr -d '\r')
  case $cmp in "P "[0-9]*) ;; *) giro1_resta "$(msg run-phase-181.r2_differ)"; return 0 ;; esac
  cp -f "$g2" "$g"
  if [ "$cmp" = "P 0" ]; then
    bash "$PC" rossi "$SPEC_F" --evidence "$ev2" --run-dir "$dir" --instabili "$u" > "$ro" 2>&1; rc=$?
    while IFS= read -r id; do
      [ -n "$id" ] && avviso "AVVISO: $(msg run-phase-181.unstable id="$id")"
    done < "$u"
  else
    cp -f "$r2" "$ro"; rc=$rc2; conf=" $(msg run-phase-181.confirmed)"   # CONFERMATO-DUE-GIRI
  fi
}
# --- driver verification for test-red (harness-pt11, see TEST-RED PHASE): prints the final outcome of the phase ---
verify_red() { # $1 = outcome of the subsession (ESITO line, possibly originale=)
  local e1 g="$dir/log/$label.gates" ro="$dir/log/$label.rossi" ev rc files=() why="" devf="" esci="$1"
  e1=$(printf '%s\n' "$1" | sed -n 1p)
  if ! printf '%s\n' "$e1" | grep -Eq '^(PHASE RESULT|ESITO FASE) [^:]*: OK'; then
    # 1.8.0 (A1): the STOP of `valida` whose only cause is test-data deviations enters the verification (VERIFY-RED-
    # DEVIAZIONI); with originale= the OK line of the session, without (only structured_output) one synthesized
    devf="$dir/log/$label.dev-ammesse"
    local orig; orig=$(printf '%s\n' "$1" | sed -n 's/^originale=//p' | head -1)
    if printf '%s\n' "$e1" | grep -Eq '^PHASE RESULT test-red: STOP — ' && [ -f "$dir/log/$label.result.json" ] &&
       { [ -z "$orig" ] || { printf '%s\n' "$e1" | grep -Eq '^PHASE RESULT test-red: STOP — JSON: ' &&
                              printf '%s\n' "$orig" | grep -Eq '^(PHASE RESULT|ESITO FASE) [^:]*: OK'; }; } &&
       "$FIC_PY" -c "$DEV_PY" ammesse "$dir/log/$label.result.json" "$log" "$([ -n "$orig" ] && echo 1 || echo 0)" > "$devf" 2>>"$err"; then
      tr -d '\r' < "$devf" | sed -n '2,$p' > "$devf.elenco"
      e1=$orig
      [ -n "$e1" ] || e1="PHASE RESULT test-red: OK — $(tr -d '\r' < "$devf" | sed -n '1s/^motivo	//p')"  # RIGA-OK-SINTETIZZATA
      esci=$e1
    else
      rm -f "$devf"; printf '%s\n' "$1"; return 0
    fi
  fi
  # writes of the phase outside its scope (also via Bash, which the guard does not see): tree before and after
  local t0 t1 fuori c="$dir/log/$label.cambiati-fase" a="$dir/log/$label.altri-flussi" nm="" nrc=0 p
  t0=$(cat "$dir/log/$label.pre-tree" 2>/dev/null); t1=$(cat "$dir/log/$label.post-tree" 2>/dev/null)
  if [ -z "$t0" ] || [ -z "$t1" ]; then why="$(msg run-phase.red_no_attr)"
  else
    # (B12-B13 review) the files of the run dir itself (when it lies in the repository and is not gitignored) are the
    # harness's own, never a write of the phase
    local rdp; rdp=$(cd "$dir" 2>/dev/null && pwd); rdp=${rdp#"$(cd "$FIC_REPO" && pwd)"/}
    (cd "$FIC_REPO" && git -c core.quotePath=false diff --name-only --no-renames "$t0" "$t1") 2>/dev/null | tr -d '\r' |
      grep -vxF -f "$dir/log/$label.scope" | grep -v '^$' | { [ -n "$rdp" ] && [ "${rdp#/}" = "$rdp" ] && grep -vF -- "$rdp/" || cat; } > "$c"   # SCOPE-DOPO-LA-FASE
    # OTHER FLOWS: an out-of-scope path that the subsession never named belongs to another flow
    : > "$a"
    if [ -n "$devf" ] && [ -s "$c" ]; then  # DEV-SOLO-SCOPE: before do-not-touch.txt / touched.txt are rewritten
      why="$(msg run-phase-180.dev_outside files="$(head -5 "$c" | paste -sd, -)")"
    elif [ -s "$c" ]; then
      nm=$(nominati "$c"); nrc=$?
      [ $nrc -eq 0 ] && printf '%s\n' "$nm" | awk -F'\t' '$1 == "mai" { print $2 }' > "$a"
    fi
    fuori=""; [ -n "$why" ] || fuori=$(grep -vxF -f "$a" "$c" | head -5 | paste -sd, -)
    if [ -n "$fuori" ]; then
      why="$(msg run-phase.red_outside out="$fuori")"
      [ $nrc -ne 0 ] && why="$why ($(msg run-phase.red_names))"
    fi
    if [ -s "$a" ]; then
      # already in touched.txt before the phase (feature work): it cannot also be in do-not-touch -> STOP,
      # it stays in touched.txt. touched-pre missing: all treated this way (fail-closed)
      local tp="$dir/log/$label.touched-pre" feat nuovi
      if [ -f "$tp" ]; then feat=$(grep -xF -f "$tp" "$a"); nuovi=$(grep -vxF -f "$tp" "$a")
      else feat=$(cat "$a"); nuovi=""; fi
      if [ -n "$feat" ]; then
        why="${why:+$why; }$(msg run-phase.red_feature files="$(printf '%s\n' "$feat" | head -5 | paste -sd, -)")"
      fi
      if [ -n "$nuovi" ]; then   # into do-not-touch.txt (preflight form), out of touched.txt (it entered it now)
        { [ -f "$dir/do-not-touch.txt" ] && tr -d '\r' < "$dir/do-not-touch.txt"; printf '%s\n' "$nuovi"; } | sed '/^[[:space:]]*$/d' | sort -u > "$dir/do-not-touch.txt.nuovo" &&
          mv -f "$dir/do-not-touch.txt.nuovo" "$dir/do-not-touch.txt"
        if [ -f "$dir/touched.txt" ]; then
          tr -d '\r' < "$dir/touched.txt" | grep -vxF -f <(printf '%s\n' "$nuovi") > "$dir/touched.txt.nuovo"
          mv -f "$dir/touched.txt.nuovo" "$dir/touched.txt"
        fi
        while IFS= read -r p; do
          avviso "AVVISO: $(msg run-phase.red_other_flow p="$p")"
        done <<< "$nuovi"
      fi
    else rm -f "$a"; fi
  fi
  # 1.8.0 (D4): the `stub` files of accept (existing production files) changed only by extension, on the diff
  # pre-tree -> post-tree taken with -w --ignore-blank-lines (a realignment of gofmt/rustfmt/prettier removes nothing)
  local stubf=() sd="" arc ao
  if [ -z "$why" ]; then
    mapfile -t stubf < <(bash "$PC" accept "$SPEC_F" 2>/dev/null | tr -d '\r' | sed -n 's/^stub //p')
    if [ ${#stubf[@]} -gt 0 ]; then
      sd="$dir/log/$label.stub-diff"
      # (B12-B13 review) where indentation is syntax (.py, .yml, .yaml) only the end-of-line spaces are ignored: a
      # dedent of `return a` out of an `if` is a removed and an added line, not an invisible change
      local sw=() si=() f_
      for f_ in "${stubf[@]}"; do case "${f_,,}" in *.py|*.yml|*.yaml) si+=("$f_") ;; *) sw+=("$f_") ;; esac; done  # INDENTAZIONE
      if ! { [ ${#sw[@]} -eq 0 ] || (cd "$FIC_REPO" && git -c core.quotePath=false diff -w --ignore-blank-lines --no-renames \
                 --no-color --no-ext-diff "$t0" "$t1" -- "${sw[@]}"); } > "$sd" 2>>"$err" ||
         ! { [ ${#si[@]} -eq 0 ] || (cd "$FIC_REPO" && git -c core.quotePath=false diff --ignore-space-at-eol --ignore-blank-lines \
                 --no-renames --no-color --no-ext-diff "$t0" "$t1" -- "${si[@]}"); } >> "$sd" 2>>"$err"; then
        why="$(msg run-phase-180.stub_diff label="$label")"
      elif [ -s "$sd" ]; then
        ao=$(bash "$PC" additivo "$SPEC_F" --diff "$sd" 2>>"$err"); arc=$?
        case $arc in
          0) ;;
          1) why=$(printf '%s\n' "$ao" | tr -d '\r' | grep . | head -3 | paste -sd';' - | sed 's/;/; /g') ;;  # STUB-ADDITIVO
          *) why="$(msg run-phase-180.stub_diff label="$label")" ;;
        esac
      fi
    fi
  fi
  mapfile -t files < <({ bash "$PC" accept "$SPEC_F" 2>/dev/null | tr -d '\r' | sed -n 's/^test //p'
                         [ -f "$dir/touched.txt" ] && tr -d '\r' < "$dir/touched.txt"; } | grep -v '^$' | LC_ALL=C sort -u)
  if [ -n "$why" ]; then :
  elif [ ! -f "$GATES" ]; then why="$(msg run-phase.red_no_gates gates="$GATES")"
  else
    FIC_BUILD_CHIUSURA=0 FIC_GATES_ROOT="$FIC_REPO" bash "$GATES" --run-dir "$dir" std ${files[@]+"${files[@]}"} > "$g" 2>&1; rc=$?  # NO-BUILD-RED
    echo "exit=$rc livello=std ($(msg run-phase.red_level))" >> "$g"
    ev=$(sed -n 's/^gates: esito=.* evidence=\(.\{2,\}\)$/\1/p' "$g" | tail -1)
    if [ -z "$ev" ] || [ "$ev" = - ]; then why="$(msg run-phase.red_no_evidence rc="$rc" label="$label")"
    else
      bash "$PC" rossi "$SPEC_F" --evidence "$ev" --run-dir "$dir" > "$ro" 2>&1; rc=$?
      # 1.8.0 (B11, D3): the probes of rossi. limite_dimostrato: the STOP says the limit is proven (exit as every
      # STOP: classifica reads the class UMANO from rossi.json); sonda_smentita: not a STOP, an AVVISO (the review sees it)
      local lim sm
      lim=$(tr -d '\r' < "$ro" | sed -n 's/^rosso \([^:]*\): limite_dimostrato.*/\1/p' | paste -sd, - | sed 's/,/, /g')
      sm=$(tr -d '\r' < "$ro" | sed -n 's/^rosso \([^:]*\): sonda_smentita.*/\1/p' | paste -sd, - | sed 's/,/, /g')
      [ -n "$sm" ] && avviso "AVVISO: $(msg run-phase-180.probe_disproved tests="$sm")"
      local conf=""
      [ $rc -eq 1 ] && [ -z "$lim" ] && secondo_giro   # 1.8.1 (G2-1): only suite conflicts -> one second round
      case $rc in
        0) ;;
        1) why=$(tr -d '\r' < "$ro" | sed -n 's/^rossi: esito=STOP — //p' | tail -1)
           if [ -n "$lim" ]; then why="$(msg run-phase-180.red_limit tests="$lim" label="$label")"  # LIMITE-NELLO-STOP
           else why="$(msg run-phase.red_not_proven why="${why:-$(msg run-phase.not_proven)}" label="$label")$conf"; fi ;;
        *) why="$(msg run-phase.red_blocked det="$(tr -d '\r' < "$ro" | sed -n 's/^rossi: esito=[A-Z]* — //p' | tail -1)" label="$label")" ;;
      esac
    fi
  fi
  if [ -z "$why" ] && [ -n "$devf" ]; then   # 1.8.0 (A1): the test-data deviations, judged on verified input
    why=$(deviazioni_test "$devf.elenco")  # CONTROLLI-DEVIAZIONE
  fi
  if [ -z "$why" ]; then   # closing OK: stubs, test fingerprint (also in the basis), absorbed counterproofs (L2)
    mkdir -p "$TR"; rm -f "$TR/tests.red.txt"   # base of the prescribed changes (tests_guard): that of THIS test-red
    { bash "$PC" stubs "$SPEC_F" --run-dir "$dir" ${sd:+--diff "$sd"} && bash "$PC" tests "$SPEC_F" | tr -d '\r' > "$TR/tests.txt" &&
      bash "$PC" basis "$SPEC_F" --write-tests && bash "$PC" gen "$SPEC_F" --run-dir "$dir"; } >> "$ro" 2>&1 ||
      why="$(msg run-phase.red_closing label="$label")"
  fi
  if [ -z "$why" ]; then printf '%s\n' "$esci"
  else printf 'PHASE RESULT test-red: STOP — %s\noriginale=%s\n' "$why" "$e1"; fi
}
# --- 1.8.0 (D4.5, DA7): a STOP of test-red parks the files the phase wrote (its scope only) in <run-dir>/staging/<path>
# (staging.fp = plan fingerprint, staging.origine = stop) and brings them back to the pre-tree (git cat-file of the
# blob of the .pre-tree for an existing file, removal for a new one): the tree handed over never holds half-written
# tests or stubs. The next test-red copies them back (S3) and launches the subsession all the same (ORIGINE-STOP).
parcheggia() { # $1 = outcome of test-red after verify_red; prints it, the STOP line with where the files are
  local e1 t0 t1 p n=0 resto
  e1=$(printf '%s\n' "$1" | sed -n 1p); resto=$(printf '%s\n' "$1" | sed -n '2,$p')
  printf '%s\n' "$e1" | grep -Eq '^(PHASE RESULT|ESITO FASE) [^:]*: STOP' || { printf '%s\n' "$1"; return 0; }
  t0=$(cat "$dir/log/$label.pre-tree" 2>/dev/null); t1=$(cat "$dir/log/$label.post-tree" 2>/dev/null)
  if [ -z "$t0" ] || [ -z "$t1" ] || [ ! -f "$dir/log/$label.scope" ]; then
    avviso "AVVISO: $(msg run-phase-180.park_no_tree label="$label")"; printf '%s\n' "$1"; return 0
  fi
  rm -rf "$dir/staging"
  while IFS= read -r p; do
    [ -n "$p" ] && grep -qxF -- "$p" "$dir/log/$label.scope" || continue   # PARCHEGGIO-SOLO-SCOPE
    if [ -f "$FIC_REPO/$p" ]; then mkdir -p "$dir/staging/$(dirname "$p")" && cp -p "$FIC_REPO/$p" "$dir/staging/$p"; fi
    if (cd "$FIC_REPO" && git cat-file -e "$t0:$p") 2>/dev/null; then
      mkdir -p "$FIC_REPO/$(dirname "$p")" && (cd "$FIC_REPO" && git cat-file blob "$t0:$p") > "$FIC_REPO/$p"
    else rm -f "$FIC_REPO/$p"; fi
    n=$((n + 1))
  done < <(cd "$FIC_REPO" && git -c core.quotePath=false diff --name-only --no-renames "$t0" "$t1" 2>/dev/null | tr -d '\r')  # PARCHEGGIO
  if [ $n -gt 0 ]; then
    echo "$plan_fp" > "$dir/staging.fp"; echo stop > "$dir/staging.origine"
    e1="$e1 · $(msg run-phase-180.parked n="$n" dir="$dir")"
  fi
  printf '%s\n' "$e1"; [ -n "$resto" ] && printf '%s\n' "$resto"
  return 0
}
# --- after implement/fix: the acceptance tests are those of test-red (harness-pt11) ---
# PRESCRIBED CHANGE (typical case: a plan step changes a helper in a file that also contains an acceptance
# test). A changed acceptance test file is tampering ONLY if no
# block of the plan has it in scrive: (procedure regenerated NOW by `plan-check.sh gen` in a separate folder, like
# lanes_decide). If it is prescribed, the acceptance test functions (file+name from test-red/rossi.json, written
# by `plan-check.sh rossi`) must stay identical to test-red: base = the file blob in the .post-tree of a
# test-red phase, accepted only if its sha256 (without CR) is the one recorded at test-red (test-red/tests.red.txt if
# the fingerprint has already been re-recorded, otherwise tests.txt). Comparison: Python, ast.dump of the node (Class::method,
# parameters [..] removed; decorators and docstrings included, comments and formatting not). Function changed or gone
# -> STOP as before. Not verifiable (not Python, no name, base not found or different, rossi.json missing)
# -> no STOP but an AVVISO in .esito, which the review sees. Limit: a helper (fixture, _make_*) that changed
# changes the test behaviour even with an identical function: the AVVISO always names it, the review decides.
# Prescribed change accepted -> the fingerprint is re-recorded with the test-red commands (`plan-check.sh tests` into
# tests.txt, `basis --write-tests`), so cycle-state.sh (STALE (tests)) and finalize.sh (l2: Tests status FRESH)
# see the same fingerprint; not recordable (STALE approval) -> STOP.
TG_PY='import ast, hashlib, importlib.util, json, os, re, subprocess, sys
sys.stdout.reconfigure(encoding="utf-8")
sys.dont_write_bytecode = True
_s = importlib.util.spec_from_file_location("maat_msg", os.environ["MAAT_MSG_PY"])
_m = importlib.util.module_from_spec(_s)
_s.loader.exec_module(_m)
T = _m.T   # the message catalog (msg_py)
root, procedura, base_txt, rossi, cambiati = sys.argv[1:6]
trees = sys.argv[6:]
scrive = {}
for l in open(procedura, encoding="utf-8"):
    m = re.match(r"^blocco ([^:]+): scrive=(.*) · dopo=", l.rstrip("\n"))
    if m:
        for f in m.group(2).split(","):
            scrive.setdefault(f.strip(), []).append(m.group(1))
base = {}
for l in open(base_txt, encoding="utf-8"):
    p = l.rstrip("\r\n").split("  ", 1)
    if len(p) == 2:
        base[p[1]] = p[0]
nomi = None
try:
    d = json.load(open(rossi, encoding="utf-8"))
    nomi = {}
    for t in (d.get("test") or {}).values():
        if isinstance(t, dict) and t.get("file"):
            nomi.setdefault(t["file"], []).append(t.get("nome") or "")
except (OSError, ValueError, AttributeError):
    pass
def blob(tree, p):
    r = subprocess.run(["git", "-C", root, "cat-file", "blob", "%s:%s" % (tree, p)], capture_output=True)
    return r.stdout.replace(b"\r", b"") if r.returncode == 0 else None
def nodo(albero, nome):
    corpo = albero.body
    trovato = None
    for seg in re.sub(r"\[.*\]$", "", nome).split("::"):
        trovato = None
        for n in corpo:
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and n.name == seg:
                trovato = n   # as in Python: the last definition wins
        if trovato is None:
            return None
        corpo = getattr(trovato, "body", [])
    return trovato
for p in [x.strip() for x in open(cambiati, encoding="utf-8") if x.strip()]:
    if p not in scrive:
        print("fuori\t" + p); continue
    bl = ",".join(scrive[p])
    def nv(why):
        print("nonverificabile\t%s\t%s\t%s" % (p, bl, why))
    if not p.endswith(".py"):
        nv(T("run-phase.tg_python_only")); continue
    if nomi is None:
        nv(T("run-phase.tg_no_rossi")); continue
    ns = nomi.get(p, [])
    if not ns or not all(ns):
        nv(T("run-phase.tg_no_names")); continue
    vecchio = next((b for b in (blob(t, p) for t in trees) if b is not None and hashlib.sha256(b).hexdigest() == base.get(p)), None)
    if vecchio is None:
        nv(T("run-phase.tg_no_base")); continue
    try:
        av = ast.parse(vecchio.decode("utf-8"))
    except (SyntaxError, UnicodeDecodeError, ValueError):
        nv(T("run-phase.tg_unparsable")); continue
    try:
        with open(os.path.join(root, p), "rb") as fh:
            an = ast.parse(fh.read().replace(b"\r", b"").decode("utf-8"))
    except (OSError, SyntaxError, UnicodeDecodeError, ValueError):
        print("cambiato\t%s\t%s" % (p, T("run-phase.tg_current"))); continue
    diversi, nonvisti = [], []
    for n in ns:
        o, c = nodo(av, n), nodo(an, n)
        if o is None:
            nonvisti.append(n)
        elif c is None or ast.dump(o) != ast.dump(c):
            diversi.append(n)
    if diversi:
        print("cambiato\t%s\t%s" % (p, ", ".join(diversi)))
    elif nonvisti:
        nv(T("run-phase.tg_not_found") + ", ".join(nonvisti))
    else:
        print("ok\t%s\t%s\t%s" % (p, bl, ", ".join(ns)))'
tests_guard() { # $1 = outcome; prints the outcome, STOP if an acceptance test file changed (PRESCRIBED CHANGE above)
  local e1 now ch t="$dir/log/.gen-tests.$$" out fuori camb trees=() f bt
  [ -f "$TR/tests.txt" ] && [ -f "$SPEC_F" ] || { printf '%s\n' "$1"; return 0; }
  now=$(bash "$PC" tests "$SPEC_F" 2>/dev/null | tr -d '\r')
  [ "$now" = "$(tr -d '\r' < "$TR/tests.txt")" ] && { printf '%s\n' "$1"; return 0; }   # CONFRONTO-TEST-ACCETTAZIONE
  e1=$(printf '%s\n' "$1" | sed -n 1p)
  ch=$(diff <(tr -d '\r' < "$TR/tests.txt") <(printf '%s\n' "$now") | sed -n 's/^[<>] [0-9A-Za-z]*  //p' | LC_ALL=C sort -u)
  # only for an OK outcome: a STOP stays such, and no fingerprint is re-recorded
  if printf '%s\n' "$e1" | grep -Eq '^(PHASE RESULT|ESITO FASE) [^:]*: OK' && [ -n "$ch" ]; then
    bt="$TR/tests.red.txt"; [ -f "$bt" ] || bt="$TR/tests.txt"
    while IFS= read -r f; do [ -n "$f" ] && trees+=("$(tr -d '\r' < "$f")"); done < <(ls "$dir"/log/*test-red.post-tree 2>/dev/null | LC_ALL=C sort -r)
    rm -rf "$t"; mkdir -p "$t" && printf '%s\n' "$ch" > "$t/cambiati"
    if bash "$PC" gen "$SPEC_F" --run-dir "$t" >/dev/null 2>&1 && [ -f "$t/gen/procedura.txt" ]; then
      out=$("$FIC_PY" -c "$TG_PY" "$FIC_REPO" "$t/gen/procedura.txt" "$bt" "$TR/rossi.json" "$t/cambiati" ${trees[@]+"${trees[@]}"} 2>>"$err" | tr -d '\r') || out=""
    else out=""; fi
    rm -rf "$t"
    fuori=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "fuori" { print $2 }' | paste -sd, -)
    camb=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "cambiato" { print $2 " (" $3 ")" }' | paste -sd, -)
    # every changed file has an ok/nonverificabile line (no fuori, no cambiato, no mancante)
    if [ -n "$out" ] && [ -z "$fuori" ] && [ -z "$camb" ] &&
       [ "$(printf '%s\n' "$out" | awk -F'\t' '$1 == "ok" || $1 == "nonverificabile" { print $2 }' | LC_ALL=C sort -u)" = "$ch" ]; then
      [ -f "$TR/tests.red.txt" ] || cp "$TR/tests.txt" "$TR/tests.red.txt"   # the test-red base stays that one
      if bash "$PC" tests "$SPEC_F" 2>>"$err" | tr -d '\r' > "$TR/tests.txt.nuovo" && mv -f "$TR/tests.txt.nuovo" "$TR/tests.txt" &&
         bash "$PC" basis "$SPEC_F" --write-tests >> "$err" 2>&1; then
        printf '%s\n' "$out" | while IFS=$'\t' read -r k p b x; do
          case $k in
            ok) avviso "AVVISO: $(msg run-phase.tg_ok p="$p" b="$b" x="$x")" ;;
            nonverificabile) avviso "AVVISO: $(msg run-phase.tg_unverified p="$p" b="$b" x="$x")" ;;
          esac
        done
        printf '%s\n' "$1"; return 0
      fi
      printf 'PHASE RESULT %s: STOP — %s\noriginale=%s\n' "$phase" "$(msg run-phase.tg_not_recorded files="$(printf '%s\n' "$ch" | paste -sd, -)" label="$label")" "$e1"
      return 0
    fi
    if [ -n "$camb" ]; then
      printf 'PHASE RESULT %s: STOP — %s\noriginale=%s\n' "$phase" "$(msg run-phase.tg_deviation files="$camb")" "$e1"
      return 0
    fi
  fi
  printf 'PHASE RESULT %s: STOP — %s\noriginale=%s\n' "$phase" "$(msg run-phase.tg_deviation files="$(printf '%s\n' "$ch" | paste -sd, - | sed 's/^$/?/')")" "$e1"
}

# --- 1.9.0 (K6a, S2): DEFECTIVE ACCEPTANCE TEST, a deviation of implement/fix accepted with a proof ---
# The STOP of `valida` («STOP — JSON: …» with originale= the OK line, or the structured output alone) whose only cause
# is deviations «test-difettoso: »/«defective-test: » (and defensive ones) enters the verification (DEV_PY ammesse-impl),
# unless the family is switched off (maat-config.py opzione correzione_test = 0: the STOP of 1.8, byte for byte). Then,
# under the same lock: the gates of the phase (K0.4; no evidence or BLOCKED -> STOP run-phase-190.gates), the script
# proofs D1-D8 and the judge (s2_prove, K6b), and on acceptance the register (registro_impl, K0.6) and the AVVISO; any
# failed check -> «PHASE RESULT <phase>: STOP — <why>» with originale= the line of the session.
difetto() { # $1 = outcome after valida; prints it, or the outcome decided by the verification
  local e1 orig devf="$dir/log/$label.dev-impl" on ev why
  e1=$(printf '%s\n' "$1" | sed -n 1p); orig=$(printf '%s\n' "$1" | sed -n 's/^originale=//p' | head -1)
  printf '%s\n' "$e1" | grep -Eq "^PHASE RESULT $phase: STOP — " && [ -f "$dir/log/$label.result.json" ] &&
    { [ -z "$orig" ] || { printf '%s\n' "$e1" | grep -Eq "^PHASE RESULT $phase: STOP — JSON: " &&
                           printf '%s\n' "$orig" | grep -Eq '^(PHASE RESULT|ESITO FASE) [^:]*: OK'; }; } &&
    "$FIC_PY" -c "$DEV_PY" ammesse-impl "$dir/log/$label.result.json" "$log" "$([ -n "$orig" ] && echo 1 || echo 0)" > "$devf" 2>>"$err" ||
    { rm -f "$devf"; printf '%s\n' "$1"; return 0; }   # AMMISSIONE-IMPL
  on=$(PROJECT_ROOT=$FIC_REPO "$FIC_PY" "$MAAT_SCRIPTS/maat-config.py" opzione correzione_test 2>>"$err" | tr -d '\r')
  if [ "$on" != 1 ]; then   # FAMIGLIA-SPENTA: the STOP of 1.8 unchanged (the notice only in the stderr of the phase)
    echo "AVVISO: $(msg run-phase-190.off fam=test-difettoso k=ciclo.correzione_test)" >> "$err"
    rm -f "$devf"; printf '%s\n' "$1"; return 0
  fi
  tr -d '\r' < "$devf" | sed -n '2,$p' > "$devf.elenco"
  [ -n "$orig" ] || orig="PHASE RESULT $phase: OK — $(tr -d '\r' < "$devf" | sed -n '1s/^motivo	//p')"
  ev=$(run_gates)   # GATE-PRIMA: the following review reuses this evidence (same key)
  if [ -z "$ev" ] || [ "$ev" = - ] || grep -q '^gates: esito=BLOCKED' "$dir/log/$label.gates" 2>/dev/null; then
    why="$(msg run-phase-190.gates label="$label")"
  else
    why=$(s2_prove "$devf.elenco" "$ev")
  fi
  if [ -n "$why" ]; then
    : > "$dir/log/$label.dev-impl.stop"   # the guard after it must not replace the cause (VERIFICA-DECIDE)
    printf 'PHASE RESULT %s: STOP — %s\noriginale=%s\n' "$phase" "$why" "$orig"; return 0
  fi
  printf '%s\n' "$orig"
}
# K0.6: the register of the accepted deviations: log/<label>.deviazioni-impl («text\tverdict\tsha256 of the proofs»,
# from <tmp>), its lines in log/deviazioni-accettate.txt (as 1.8.0, the review receives them), the note in the changelog
# of the plan (DIFENSIVE_PY nota with run-phase-190.note_corrected, outside the fingerprint: restored if the basis moves)
registro_impl() { # $1 = file of the lines «text\tverdict\tsha»
  local sp="${dir%.run}.md" b0 b1 rc
  mv -f "$1" "$dir/log/$label.deviazioni-impl" || return 1
  { [ -f "$dir/log/deviazioni-accettate.txt" ] && tr -d '\r' < "$dir/log/deviazioni-accettate.txt" | grep -v "^$label	"
    awk -F'\t' -v l="$label" '{ print l "\t" $1 "\t" $2 }' "$dir/log/$label.deviazioni-impl"; } > "$dir/log/deviazioni-accettate.txt.tmp" &&
    mv -f "$dir/log/deviazioni-accettate.txt.tmp" "$dir/log/deviazioni-accettate.txt"
  [ -f "$sp" ] || return 0
  cut -f1 "$dir/log/$label.deviazioni-impl" > "$dir/log/$label.note-impl"
  b0=$(bash "$PC_SH" basis "$sp" 2>/dev/null | tr -d '\r' | grep '^Basis: ')
  cp "$sp" "$dir/log/$label.note-impl.spec-pre"
  "$FIC_PY" -c "$DIFENSIVE_PY" nota "$sp" "$label" "$dir/log/$label.note-impl" corretto 2>>"$err"; rc=$?
  b1=$(bash "$PC_SH" basis "$sp" 2>/dev/null | tr -d '\r' | grep '^Basis: ')
  if [ $rc -ne 0 ] || [ -z "$b0" ] || [ "$b0" != "$b1" ]; then cp "$dir/log/$label.note-impl.spec-pre" "$sp"; fi
  rm -f "$dir/log/$label.note-impl.spec-pre" "$dir/log/$label.note-impl"
  return 0
}
# K0.3/K0.6: the corrections of <Tn> already accepted in this cycle: the lines «Deviazione accettata: <label> · <family> ·
# <Tn> · sha=…» of driver.log (written by the driver, K4) and those of deviazioni-accettate.txt whose text is of the
# family for <Tn> (deleting the file does not lower the count). Prints the label of the first one, nothing if none.
gia_corretto() { # $1 = Tn
  { tr -d '\r' < "$dir/driver.log" 2>/dev/null | sed -n 's/.*Deviazione accettata: \([^ ]*\) · \(test-difettoso\|defective-test\) · '"$1"' · .*/\1/p'
    tr -d '\r' < "$dir/log/deviazioni-accettate.txt" 2>/dev/null |
      awk -F'\t' -v t="$1" '{ d = $2; sub(/^(test-difettoso|defective-test): (corsia [0-9]+: |lane [0-9]+: )?/, "", d) }
        $2 ~ /^(test-difettoso|defective-test): / && index(d, t " ") == 1 { print $1 }'; } | head -1
}
# 1.9.0 (K6b, S2 D1-D8): the helper of the proofs (S2_PY, the run dir files as input, prints one answer):
#   forma <deviation>                → «<Tn>\t<class>» (prefix, «corsia k: » / «lane k: » removed); exit 1 not in its form or
#                                      <why> over 200 characters
#   info <rossi.json> <Tn>           → «<file>\t<name>» of rossi.json (test-red), exit 1 missing
#   runner <file>                    → the controprova runner of its module in maat.json (pytest, vitest, …; «-» none)
#   attesi <test row>                → the expected texts of the row, one per line (the backticks of its assertion cell,
#                                      otherwise the «rosso se:» of its mutation), as plan-check testi_attesi
#   esito <esiti.json> <Tn>          → «<esito>\t<riga_errore>» of esiti; exit 1 unreadable
#   candidati <es1> <es2> <file> <id> → the cases of <file> red in BOTH rounds, other than <id>, in the order of the
#                                      first report: «<test_id>» per line (at most 4: the 4th only to say there are more)
#   caso <json> <file> <test_id>     → «<esito>\t<complete 0|1>\t<riga_errore>» of the case: an esiti.json (casi,
#                                      file_completi) or an <id>.json of counterproof in whole-file mode (casi,
#                                      casi_completo, and the file itself verde or rosso); a case absent → «absent»
#                                      (never green)
#   cp <id.json>                     → the esito of a counterproof result, «-» unreadable
#   piano <spec>                     → the paths of «### File toccati» (backticks), one per line
S2_PY='
import json, os, re, sys
sys.dont_write_bytecode = True
a = sys.argv[1:]
def jl(p):
    try:
        return json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError):
        return None
if a[0] == "forma":
    d = " ".join(a[1].split())
    m = re.match(r"^(?:test-difettoso|defective-test): (?:(?:corsia|lane) [0-9]+: )?([A-Za-z0-9._-]+) — (\S+) — (.+)$", d)
    if not m or len(m.group(3)) > 200:   # FORMA-PERCHE
        sys.exit(1)
    print("%s\t%s" % (m.group(1), m.group(2)))
elif a[0] == "info":
    t = ((jl(a[1]) or {}).get("test") or {}).get(a[2])
    if not isinstance(t, dict) or not t.get("file") or not t.get("nome"):
        sys.exit(1)
    print("%s\t%s" % (t["file"], t["nome"]))
elif a[0] == "runner":
    import importlib.util
    s = importlib.util.spec_from_file_location("maat_config", os.environ["MAAT_CONFIG_PY"])
    mc = importlib.util.module_from_spec(s); s.loader.exec_module(mc)
    try:
        cfg, _p = mc.carica()
        r = mc.risolto(cfg)
    except mc.Uscita:
        print("-"); sys.exit(0)
    k = mc.instrada(r, a[1])
    m = next((x for x in r["moduli"] if k and x["nome"] == k[0] and k[1] == "radice"), None)
    print(((m or {}).get("controprova") or {}).get("runner") or "-")
elif a[0] == "attesi":
    c = [x.strip() for x in a[1].strip().strip("|").split("|")]
    t = re.findall(r"`([^`]+)`", c[3]) if len(c) > 3 else []
    if not t and len(c) > 4:
        t = re.findall(r"rosso se:\s*`([^`]+)`|red if:\s*`([^`]+)`", c[4])
        t = [x or y for x, y in t]
    print("\n".join(" ".join(x.split()) for x in t if x.strip()))
elif a[0] == "esito":
    t = ((jl(a[1]) or {}).get("test") or {}).get(a[2])
    if not isinstance(t, dict):
        sys.exit(1)
    print("%s\t%s" % (t.get("esito"), " ".join(str(t.get("riga_errore") or "").split())))
elif a[0] == "candidati":
    c1 = ((jl(a[1]) or {}).get("casi") or {}).get(a[3]) or []
    c2 = {c.get("test_id"): c.get("esito") for c in (((jl(a[2]) or {}).get("casi") or {}).get(a[3]) or [])}
    out = [c["test_id"] for c in c1 if c.get("esito") == "rosso" and c.get("test_id") != a[4] and c2.get(c.get("test_id")) == "rosso"]
    print("\n".join(out[:4]))
elif a[0] == "caso":
    d = jl(a[1]) or {}
    if "casi_completo" in d:   # counterproof, whole-file mode: complete only if the file itself ran (FILE-INTERO-ESEGUITO:
        # verde or rosso; rosso_raccolta = an error of the file, afterAll or a hook, bloccato, … never count).
        # Declared limit: a file with an error of the file (afterAll) AND a red case is «rosso», not «rosso_raccolta»
        # (counterproof.sh): the error of the hook does not stop V there.
        casi, comp = d.get("casi") or [], d.get("casi_completo") is True and d.get("esito") in ("verde", "rosso")
    else:
        casi, comp = (d.get("casi") or {}).get(a[2]) or [], a[2] in (d.get("file_completi") or [])
    c = next((x for x in casi if x.get("test_id") == a[3]), None)
    if c is None:
        print("absent\t%d\t" % comp)
    else:
        print("%s\t%d\t%s" % (c.get("esito"), comp, " ".join(str(c.get("riga_errore") or c.get("messaggio") or "").split())[:300]))
elif a[0] == "cp":
    print((jl(a[1]) or {}).get("esito") or "-")
elif a[0] == "piano":
    zona = False
    for l in open(a[1], encoding="utf-8", errors="replace"):
        l = l.rstrip("\r\n")
        if re.match(r"^###[ \t]+(File toccati|Touched files)\b", l):
            zona = True; continue
        if zona and re.match(r"^#{1,3}[ \t]", l):
            zona = False
        if zona:
            for p in re.findall(r"`([^`]+)`", l):
                print(re.sub(r"::.*$", "", p))
'
s2py() { MAAT_CONFIG_PY="$MAAT_SCRIPTS/maat-config.py" PROJECT_ROOT=$FIC_REPO "$FIC_PY" -c "$S2_PY" "$@" 2>>"$err" | tr -d '\r'; }
# the proof worktrees of this phase, one per line in log/<label>.prova-wt (the subshells add to it): removed at the end,
# on a STOP and on a signal (trap in s2_prove)
s2_pulisci() { local w
  [ -f "$dir/log/$label.prova-wt" ] || return 0
  while IFS= read -r w; do [ -n "$w" ] && MAIN=$FIC_REPO WT_TAG=run-phase wt_prova_rimuovi "$w" >>"$err" 2>&1; done < "$dir/log/$label.prova-wt"
  rm -f "$dir/log/$label.prova-wt"; }
# MAIN=$FIC_REPO (a declared choice, interface (a) of K0): the proof worktrees are worktrees of the tree of the phase and
# take its dependencies (dep_links, preparati, deps_diff compared with ITS working tree): the same dependencies as the
# main tree the gates of the phase ran on, never those of another checkout.
s2_albero() { # $1 = suffix of the worktree, $2 = tree to apply, $3 = file of Tn, $4 = its content → prints the worktree
  local w rc
  w=$(MAIN=$FIC_REPO WT_TAG=run-phase wt_prova_crea "$label-$1" "$(git -C "$FIC_REPO" rev-parse HEAD 2>>"$err")" 2>>"$err"); rc=$?
  [ -n "$w" ] && printf '%s\n' "$w" >> "$dir/log/$label.prova-wt"
  [ $rc -eq 0 ] && [ -n "$w" ] || return 1
  MAIN=$FIC_REPO WT_TAG=run-phase wt_prova_albero "$w" "$2" >>"$err" 2>&1 || return 1
  mkdir -p "$(dirname "$w/$3")" && cp "$4" "$w/$3" || return 1
  printf '%s\n' "$w"
}
s2_gate() { # $1 = suffix (.prova-a, .prova-a2, .prova-b, .verde2), $2 = root, $3 = file of Tn, $4 = prefix of the files of
  # the deviation (log/<label>.dif-<Tn>) → esiti in <prefix>$1.esiti.json: one per deviation (its sha in the register)
  local r="$dir/log/$label$1" e
  rm -rf "$r"; rm -f "$4$1.esiti.json"; mkdir -p "$r"
  FIC_BUILD_CHIUSURA=0 FIC_GATES_ROOT="$2" bash "$GATES" --run-dir "$r" std "$3" > "$r.gates" 2>&1  # NO-BUILD-PROVA
  e=$(sed -n 's/^gates: esito=.* evidence=\(.\{2,\}\)$/\1/p' "$r.gates" | tail -1)
  { [ -n "$e" ] && [ "$e" != - ] && ! grep -q '^gates: esito=BLOCKED' "$r.gates"; } || return 1
  bash "$PC" esiti "$SPEC_F" --evidence "$e" --out "$4$1.esiti.json" --run-dir "$dir" > "$r.esiti" 2>>"$err"
}
s2_cp() { # $1 = name, $2 = PROJECT_ROOT, $3 = file, $4 = test_id ("" = the whole file), $5 = runner → prints the <id>.json
  local c="$dir/log/$label.$1" nm
  rm -rf "$c"; mkdir -p "$c"
  if [ -n "$4" ]; then
    nm=$4; [ "$5" = pytest ] && nm=${4#"$3::"}
    "$FIC_PY" -c 'import json, sys; json.dump([{"id": sys.argv[1], "file": sys.argv[2], "simbolo": sys.argv[3], "test": {"percorso": sys.argv[2], "nome": sys.argv[3]}, "rosso_se": {"test_id": sys.argv[4]}}], open(sys.argv[5], "w", encoding="utf-8"))' \
      "$1" "$3" "$nm" "$4" "$c/mutations.json" 2>>"$err"
  else
    "$FIC_PY" -c 'import json, sys; json.dump([{"id": sys.argv[1], "file": sys.argv[2], "intero": True, "test": {"percorso": sys.argv[2]}}], open(sys.argv[3], "w", encoding="utf-8"))' \
      "$1" "$3" "$c/mutations.json" 2>>"$err"
  fi
  PROJECT_ROOT=$2 bash "$CP_SH" --senza-mutazione "$c/mutations.json" > "$c.out" 2>&1
  case $? in 0|2) printf '%s\n' "$c/$1.json" ;; *) return 1 ;; esac   # 3 environment, 5 copy not restored, 64 usage
}
s2_una() { # $1 = Tn, $2 = class, $3 = deviation, $4 = evidence of the phase, $5 = file of the judge inputs (one path per line)
  local tn=$1 cl=$2 d=$3 ev=$4 inl=$5 path nome rn oldf pt cur out rc k tr why w x e1 e2 r1 a1 a2 tnid v vs vcp p1 p2
  local pd="$dir/log/$label.dif-$tn" attesi
  IFS=$'\t' read -r path nome < <(s2py info "$TR/rossi.json" "$tn") || true
  [ -n "${path:-}" ] && [ -n "${nome:-}" ] || { msg run-phase-190.d_proof c="$cl" tn="$tn" why="rossi.json"; return; }
  rn=$(s2py runner "$path")
  case "$cl:$rn:$path" in   # CLASSE-LINGUAGGIO: pytest for .py, vitest for JS/TS
    *:pytest:*.py|*:vitest:*.js|*:vitest:*.jsx|*:vitest:*.mjs|*:vitest:*.cjs|*:vitest:*.ts|*:vitest:*.tsx|*:vitest:*.mts|*:vitest:*.cts) ;;
    *) msg run-phase-190.d_class c="$cl ($rn, $path)"; return ;;
  esac
  # the judge inputs plan-check computes: fixed instructions, test row, trace rows, defect line
  out=$(bash "$PC" deviazione - "$SPEC_F" "$tn" --famiglia test-difettoso --classe "$cl" 2>>"$err" | tr -d '\r'); rc=$?
  if [ $rc -ne 0 ]; then
    printf '%s\n' "$out" | grep -qx 'controllo: d_class' && { msg run-phase-190.d_class c="$cl"; return; }
    x=$(printf '%s\n' "$out" | sed -n 's/^Deviazione: STOP — //p' | head -1)
    [ -n "$x" ] || x=$(msg run-phase-190.d_proof c="$cl" tn="$tn" why="plan-check deviazione exit $rc")   # DEVIAZIONE-EXIT
    printf '%s\n' "$x"; return
  fi
  attesi=$(s2py attesi "$(printf '%s\n' "$out" | sed -n 's/^test row: //p')")
  # D1: the acceptance files changed are files of the declared T only; no other file beyond the plan; never a shared one
  local tf pf ch fuori
  tf=$(cat "$dir/log/$label.dif-files" 2>/dev/null)
  pf=$(s2py piano "$SPEC_F")
  fuori=$(printf '%s\n' "$(cat "$dir/log/$label.dif-changed")" | grep -v '^$' | while IFS= read -r x; do
      case "${x##*/}" in conftest.py|setup*|vitest.setup*|*fixture*) echo "$x"; continue ;; esac
      case "/$x/" in */fixtures/*|*/__fixtures__/*) echo "$x"; continue ;; esac
      if printf '%s\n' "$(cat "$dir/log/$label.dif-acc")" | grep -qxF -- "$x"; then
        printf '%s\n' "$tf" | grep -qxF -- "$x" || echo "$x"
      else printf '%s\n' "$pf" | grep -qxF -- "$x" || echo "$x"; fi
    done | head -5 | paste -sd, -)
  [ -z "$fuori" ] || { msg run-phase-190.d_files files="$fuori"; return; }   # FILE-DELLA-FASE
  # D1, D2, D8: plan-check.sh corretto between the version of test-red (its .post-tree) and the current file
  pt=$(ls "$dir"/log/*-test-red.post-tree 2>/dev/null | LC_ALL=C sort | tail -1); pt=$([ -n "$pt" ] && tr -d '\r\n' < "$pt")
  oldf="$pd.old"
  [ -n "$pt" ] && git -C "$FIC_REPO" cat-file blob "$pt:$path" > "$oldf" 2>>"$err" && [ -f "$FIC_REPO/$path" ] ||
    { msg run-phase-190.d_transform tn="$tn" why="test-red post-tree"; return; }
  bash "$PC" corretto "$SPEC_F" "$tn" --classe "$cl" --vecchio "$oldf" --nuovo "$FIC_REPO/$path" --run-dir "$dir" > "$pd.corretto" 2>&1; rc=$?
  case $rc in
    0) tr=$(tr -d '\r' < "$pd.corretto" | grep '^trasformazione: ' | head -1) ;;
    1) k=$(tr -d '\r' < "$pd.corretto" | sed -n 's/^violazione \([a-z_]*\): \(.*\)$/\1\t\2/p' | head -1)
       x=${k#*	}; k=${k%%	*}
       case $k in   # VIOLAZIONE-DI-CORRETTO: the key of the first violation
         d_outside) msg run-phase-190.d_outside f="$path" tn="$tn" ;;
         d_skip) msg run-phase-190.d_skip m="$x" ;;
         d_assert) msg run-phase-190.d_assert tn="$tn" t="$x" ;;
         *) msg run-phase-190.d_transform tn="$tn" why="$x" ;;
       esac; return ;;
    *) msg run-phase-190.d_transform tn="$tn" why="plan-check.sh corretto exit $rc"; return ;;
  esac
  [ -n "$tr" ] || { msg run-phase-190.d_transform tn="$tn" why="-"; return; }
  # D3: tree A = the current tree with the file of Tn at the version of test-red; two rounds of gates on its file
  cur=$(tree_now) && [ -n "$cur" ] || { msg run-phase-190.d_tree why="tree"; return; }
  w=$(s2_albero a "$cur" "$path" "$oldf") || { msg run-phase-190.d_tree why="$(msg run-phase-190.why_wt n=A)"; return; }
  s2_gate .prova-a "$w" "$path" "$pd" && s2_gate .prova-a2 "$w" "$path" "$pd" || { msg run-phase-190.d_tree why="$(msg run-phase-190.why_gates n=A)"; return; }
  a1=$(s2py esito "$pd.prova-a.esiti.json" "$tn"); a2=$(s2py esito "$pd.prova-a2.esiti.json" "$tn")
  e1=${a1%%	*} e2=${a2%%	*}
  if [ "$e1" != verde ] || [ "$e2" != verde ]; then   # D3-A: the old Tn green in its file in both rounds
    for x in "$a1" "$a2"; do
      case ${x%%	*} in rosso_import|rosso_raccolta|rosso_simbolo) msg run-phase-190.d_old_load tn="$tn"; return ;; esac
    done
    for x in "$a1" "$a2"; do
      r1=${x#*	}
      case ${x%%	*} in verde) continue ;; esac
      if [ -n "$r1" ] && printf '%s\n' "$r1" | grep -qF -f <(printf '%s\n' "$attesi" | grep -v '^$'); then
        msg run-phase-190.d_on_text tn="$tn"; return   # D3-TESTO: the code is at fault
      fi
    done
    msg run-phase-190.d_proof c="$cl" tn="$tn" why="A: $e1, $e2"; return
  fi
  # D5: the new Tn green in its file on the gates of the phase (K0.4) and on a second round in the tree of the phase
  rm -f "$pd.fase.esiti.json"
  bash "$PC" esiti "$SPEC_F" --evidence "$ev" --out "$pd.fase.esiti.json" --run-dir "$dir" > "$pd.fase.esiti" 2>>"$err" ||
    { msg run-phase-190.not_green tn="$tn" e="plan-check esiti exit $?"; return; }   # ESITI-FASE
  s2_gate .verde2 "$FIC_REPO" "$path" "$pd" || { msg run-phase-190.not_green tn="$tn" e="$(msg run-phase-190.why_gates n=verde2)"; return; }
  p1=$(s2py esito "$pd.fase.esiti.json" "$tn"); p2=$(s2py esito "$pd.verde2.esiti.json" "$tn")
  [ "${p1%%	*}" = verde ] && [ "${p2%%	*}" = verde ] || { msg run-phase-190.not_green tn="$tn" e="${p1%%	*}, ${p2%%	*}"; return; }   # VERDE-DUE-GIRI
  # D3 (b): the victim V, a case of the file of Tn red in both rounds on A, at most 3 candidates
  tnid=$nome; [ "$rn" = pytest ] && tnid="$path::$nome"
  mapfile -t vs < <(s2py candidati "$pd.prova-a.esiti.json" "$pd.prova-a2.esiti.json" "$path" "$tnid" | grep -v '^$')
  local vic="" vwhy="" vnew1 vnew2 valone j=0 n4="" tnsolo
  [ ${#vs[@]} -gt 3 ] && n4=" ($(msg run-phase-190.why_more))"
  for v in "${vs[@]:0:3}"; do
    j=$((j + 1))
    vcp=$(s2_cp "v$j" "$w" "$path" "$v" "$rn") || { msg run-phase-190.d_tree why="$(msg run-phase-190.why_cp v="$v")"; return; }
    valone=$(s2py cp "$vcp")
    [ "$valone" = verde ] || { vwhy="$v: $valone"; continue; }   # V-DA-SOLO: red alone too = a defect of the code
    if [ "$rn" = vitest ]; then   # the text log does not list an all-green file: two runs of the whole file
      x=$(s2_cp "f1-$j" "$FIC_REPO" "$path" "" "$rn") && vnew1=$(s2py caso "$x" "$path" "$v") || vnew1="absent	0	"
      x=$(s2_cp "f2-$j" "$FIC_REPO" "$path" "" "$rn") && vnew2=$(s2py caso "$x" "$path" "$v") || vnew2="absent	0	"
    else
      vnew1=$(s2py caso "$pd.fase.esiti.json" "$path" "$v"); vnew2=$(s2py caso "$pd.verde2.esiti.json" "$path" "$v")
    fi
    case "$vnew1|$vnew2" in   # V-NEL-FILE-NUOVO: present, verde, its file complete, in both rounds (absence is never green)
      "verde	1	"*"|verde	1	"*) vic=$v; break ;;
    esac
    vwhy="$v: ${vnew1%%	*}, ${vnew2%%	*}"
  done
  [ -n "$vic" ] || { msg run-phase-190.d_victim tn="$tn" why="${vwhy:-$(msg run-phase-190.why_none)}$n4"; return; }
  # D3 (b) 3: the new Tn green alone (the tree of the phase, mirror copy) — and in its file, above (D5)
  x=$(s2_cp tn "$FIC_REPO" "$path" "$tnid" "$rn") || { msg run-phase-190.d_tree why="$(msg run-phase-190.why_cp v="$tn")"; return; }
  tnsolo=$(s2py cp "$x")
  [ "$tnsolo" = verde ] || { msg run-phase-190.not_green tn="$tn" e="$tnsolo"; return; }   # TN-DA-SOLO
  # D4: tree B = the post-tree of the last test-red with the file of Tn in the new version: Tn red on its assertion
  w=$(s2_albero b "$pt" "$path" "$FIC_REPO/$path") || { msg run-phase-190.d_tree why="$(msg run-phase-190.why_wt n=B)"; return; }
  s2_gate .prova-b "$w" "$path" "$pd" || { msg run-phase-190.d_tree why="$(msg run-phase-190.why_gates n=B)"; return; }
  x=$(s2py esito "$pd.prova-b.esiti.json" "$tn")
  [ "${x%%	*}" = dimostrato ] || { msg run-phase-190.d_stub tn="$tn" e="${x%%	*}"; return; }   # ROSSO-SULLO-STUB
  # D7: the inputs of the judge, recomputed here as the phase had them (one file each; the diff last, with its canonical
  # bytes): the blocks of plan-check deviazione, the trasformazione: line of corretto, the diff from the post-tree
  local q="$pd.in" i=0
  w_in() { i=$((i + 1)); printf '%s' "$1" > "$q$i"; echo "$q$i" >> "$inl"; }
  : > "$inl"
  w_in "$(printf '%s\n' "$out" | sed -n 's/^judge instructions: //p')"
  w_in "$(printf '%s\n' "$out" | sed -n 's/^test row: //p')"
  while IFS= read -r x; do w_in "$x"; done < <(printf '%s\n' "$out" | sed -n 's/^trace row: //p')
  while IFS= read -r x; do w_in "$x"; done < <(printf '%s\n' "$out" | sed -n 's/^other row: //p')   # 1.9.1 (C1)
  w_in "$(printf '%s\n' "$out" | grep '^defect: ' | head -1)"
  # (D7, amendment of 23/11) the victim and the outcomes of D3 are computed here AFTER the phase: script proofs, never
  # inputs of the judge (the phase could not paste them); they go into correzioni.json for the review
  w_in "$tr"
  bash "$PC" diff-test "$SPEC_F" "$path" --run-dir "$dir" --dal-post > "$pd.diff" 2>>"$err" && [ -s "$pd.diff" ] ||
    { msg run-phase-190.d_transform tn="$tn" why="diff-test --dal-post"; return; }
  printf '%s' "$(cat "$pd.diff")" > "$pd.diff-in"; echo "$pd.diff-in" >> "$inl"
  # what correzioni.json records for this T (written on acceptance): the outcomes as measured above, never constants
  local va1 va2
  va1=$(s2py caso "$pd.prova-a.esiti.json" "$path" "$vic"); va2=$(s2py caso "$pd.prova-a2.esiti.json" "$path" "$vic")
  "$FIC_PY" -c 'import hashlib, json, sys
h = lambda p: hashlib.sha256(open(p, "rb").read().replace(b"\r", b"")).hexdigest()
jl = lambda p: json.load(open(p, encoding="utf-8"))
t = lambda p, k: (jl(p).get("test") or {}).get(k) or {}
a = sys.argv
e = lambda x: x.split("\t")[0]
json.dump({"test": a[1], "file": a[2], "classe": a[3], "sha256_vecchio": h(a[4]), "sha256_nuovo": h(a[5]),
           "A": [{k: t(p, a[1]).get(k) for k in ("esito", "messaggio", "posizione")} for p in (a[6], a[7])],
           "B": {k: t(a[8], a[1]).get(k) for k in ("esito", "messaggio", "posizione")},
           "vittima": {"test_id": a[9], "nel_file_con_tn_vecchio": [e(a[12]), e(a[13])], "da_sola": a[14],
                       "nel_file_con_tn_nuovo": [e(a[15]), e(a[16])]},
           "tn_nuovo": {"da_solo": a[17], "nel_file": [e(a[18]), e(a[19])]},
           "trasformazione": a[10]}, open(a[11], "w", encoding="utf-8"), ensure_ascii=False, indent=1)' \
    "$tn" "$path" "$cl" "$oldf" "$FIC_REPO/$path" "$pd.prova-a.esiti.json" "$pd.prova-a2.esiti.json" \
    "$pd.prova-b.esiti.json" "$vic" "$tr" "$pd.correzione.json" "$va1" "$va2" "$valone" "$vnew1" "$vnew2" \
    "$tnsolo" "$p1" "$p2" 2>>"$err"
}
s2_prove() { # $1 = file of the deviations of the family (one per line), $2 = evidence of the gates of the phase
  local f=$1 ev=$2 d tn cl x why g=0 tmp="$dir/log/$label.deviazioni-impl.tmp" args=() visti=" " vd sha st
  local inl l2 t0
  trap 's2_pulisci' EXIT
  trap 's2_pulisci; exit 143' TERM INT
  declare -F wt_prova_crea >/dev/null || { MAIN=$FIC_REPO WT_TAG=run-phase . "$MAAT_SCRIPTS/worktree-lib.sh" >>"$err" 2>&1 ||
    { msg run-phase-190.d_tree why="worktree-lib.sh"; return; }; }
  # the files of the phase (pre-tree -> now) and the acceptance files changed after test-red (the ch of tests_guard)
  t0=$(tr -d '\r\n' < "$dir/log/$label.pre-tree" 2>/dev/null)
  x=$(tree_now)
  local rdp; rdp=$(cd "$dir" 2>/dev/null && pwd); rdp=${rdp#"$(cd "$FIC_REPO" && pwd)"/}   # the run dir: the harness's own files
  [ -n "$t0" ] && [ -n "$x" ] && (cd "$FIC_REPO" && git -c core.quotePath=false diff --name-only --no-renames "$t0" "$x") 2>>"$err" | tr -d '\r' |
    { [ -n "$rdp" ] && [ "${rdp#/}" = "$rdp" ] && grep -vF -- "$rdp/" || cat; } > "$dir/log/$label.dif-changed" ||
    { msg run-phase-190.d_tree why="pre-tree"; return; }
  diff <(tr -d '\r' < "$TR/tests.txt") <(bash "$PC" tests "$SPEC_F" 2>/dev/null | tr -d '\r') | sed -n 's/^[<>] [0-9A-Za-z]*  //p' | LC_ALL=C sort -u > "$dir/log/$label.dif-acc"
  : > "$dir/log/$label.dif-files"; : > "$tmp"
  local devs=(); mapfile -t devs < <(grep -v '^$' "$f")   # read once: the proofs below must not consume it
  for d in ${devs[@]+"${devs[@]}"}; do   # FORMA, CLASSE, UNA-VOLTA: before any proof
    x=$(s2py forma "$d") || { msg run-phase-190.form fam=test-difettoso d="$d"; return; }
    tn=${x%%	*}; cl=${x#*	}
    case " stato-condiviso shared-state patch-non-ripristinata unrestored-patch " in *" $cl "*) ;; *) msg run-phase-190.d_class c="$cl"; return ;; esac
    case "$visti" in *" $tn "*) msg run-phase-190.d_once tn="$tn" label="$label"; return ;; esac
    visti="$visti$tn "
    x=$(gia_corretto "$tn"); [ -z "$x" ] || { msg run-phase-190.d_once tn="$tn" label="$x"; return; }   # D6
    IFS=$'\t' read -r x _ < <(s2py info "$TR/rossi.json" "$tn") && echo "$x" >> "$dir/log/$label.dif-files"
  done
  local pd rc cj=()
  for d in "${devs[@]}"; do
    x=$(s2py forma "$d"); tn=${x%%	*}; cl=${x#*	}; g=$((g + 1))
    pd="$dir/log/$label.dif-$tn"; inl="$pd.ingressi"
    rm -f "$inl" "$pd".*   # nothing of a previous round (or written by the session) stands for a proof of this one
    why=$(s2_una "$tn" "$cl" "$d" "$ev" "$inl"); rc=$?
    [ -z "$why" ] || { s2_pulisci; printf '%s\n' "$why"; return; }
    # CONFERMA-POSITIVA: accepted only when s2_una ran to its end: exit 0 and the correzione.json it has just written
    [ $rc -eq 0 ] && [ -s "$pd.correzione.json" ] && [ -s "$inl" ] ||
      { s2_pulisci; msg run-phase-190.d_proof c="$cl" tn="$tn" why="correzione.json"; return; }
    cj+=("$pd.correzione.json")
    args+=("$(grep -c . "$inl")" "$pd.diff")
    while IFS= read -r l2; do args+=("$l2"); done < "$inl"
  done
  s2_pulisci
  # D7: the judge, every call of the phase (giudice --tutti), then plan-check deviazione on the result of each.
  # Declared limit (two lanes): only $log is read; with lanes it holds the merged result, not the calls of the lane
  # sessions (log/<label>.corsia-<k>.jsonl), so the judge is never found there → STOP «giudice mai» (fail-closed).
  st=$(MAAT_SCRIPTS_PY=$(maat_cygm "$MAAT_SCRIPTS" 2>/dev/null || printf '%s' "$MAAT_SCRIPTS") "$FIC_PY" -c "$DEV_PY" giudice --tutti "$log" \
       "$dir/log/$label.dif" "$dir" "$(pc_root)" "$g" "${args[@]}" 2>>"$err" | tr -d '\r')
  g=0
  for d in "${devs[@]}"; do
    x=$(s2py forma "$d"); tn=${x%%	*}; cl=${x#*	}; g=$((g + 1))
    case $st in
      ok) ;;
      extra) msg run-phase-190.judge_extra; return ;;
      incompleto*) msg run-phase-190.judge fam=test-difettoso tn="$tn" st="$st" which="${st#incompleto }"; return ;;
      *) msg run-phase-190.judge fam=test-difettoso tn="$tn" st="$st" which="-"; return ;;
    esac
    x=$(bash "$PC" deviazione "$dir/log/$label.dif$g.result" "$SPEC_F" "$tn" --famiglia test-difettoso --classe "$cl" 2>>"$err" | tr -d '\r'); rc=$?
    if [ $rc -ne 0 ] || ! printf '%s\n' "$x" | grep -qx 'Deviazione: ACCETTATA'; then   # GIUDICE-ACCETTA
      printf '%s\n' "$x" | grep -qx 'controllo: d_class' && { msg run-phase-190.d_class c="$cl"; return; }
      why=$(printf '%s\n' "$x" | sed -n 's/^Deviazione: STOP — //p' | head -1)
      [ -n "$why" ] || why=$(msg run-phase-190.d_proof c="$cl" tn="$tn" why="plan-check deviazione exit $rc")
      printf '%s\n' "$why"; return
    fi
    vd=$(tr -d '\r' < "$dir/log/$label.dif$g.result" | sed -n 's/^[ \t>*_`-]*Deviation verdict:[ \t*_`]*//p' | tail -1 | sed 's/[ \t*_`]*$//')
    pd="$dir/log/$label.dif-$tn"   # the sha of the proofs of THIS deviation (its files, s2_gate)
    sha=$(cat "$pd.corretto" "$pd.diff" "$pd.prova-a.esiti.json" "$pd.prova-a2.esiti.json" "$pd.prova-b.esiti.json" \
          "$pd.verde2.esiti.json" 2>>"$err" | sha256sum | cut -c1-64)
    printf '%s\t%s\t%s\n' "$d" "$vd" "$sha" >> "$tmp"
  done
  # K6b point 5: the fingerprint re-recorded by the script (the commands of test-red); then tests_guard sees it equal
  mkdir -p "$TR"
  { [ -f "$TR/tests.red.txt" ] || cp "$TR/tests.txt" "$TR/tests.red.txt"; } &&
    bash "$PC" tests "$SPEC_F" 2>>"$err" | tr -d '\r' > "$TR/tests.txt.nuovo" && mv -f "$TR/tests.txt.nuovo" "$TR/tests.txt" &&
    bash "$PC" basis "$SPEC_F" --write-tests >> "$err" 2>&1 && bash "$PC" gen "$SPEC_F" --run-dir "$dir" >> "$err" 2>&1 ||
    { msg run-phase-190.not_recorded; return; }   # RIREGISTRA
  "$FIC_PY" -c 'import json, sys
c = {}
try:
    c = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    pass
for p in sys.argv[2:]:
    d = json.load(open(p, encoding="utf-8"))
    c[d["test"]] = d
open(sys.argv[1] + ".tmp", "w", encoding="utf-8").write(json.dumps(c, ensure_ascii=False, indent=1) + "\n")' \
    "$TR/correzioni.json" "${cj[@]}" 2>>"$err" && mv -f "$TR/correzioni.json.tmp" "$TR/correzioni.json"
  registro_impl "$tmp"
  while IFS=$'\t' read -r d vd sha; do
    x=$(s2py forma "$d"); avviso "AVVISO: $(msg run-phase-190.ok_corrected tn="${x%%	*}" d="$d")"
  done < "$dir/log/$label.deviazioni-impl"
}

# --- lanes (harness-pt13): see LANES at the top ---
BI=${FIC_BLOCKS_INDEPENDENT:-$MAAT_SCRIPTS/blocks-independent.py}
lanes_decide() { # writes log/<label>.corsie · 0 = two lanes, otherwise series (with the reason in the file)
  local spec="${dir%.run}.md" t="$dir/log/.gen-corsie.$$" c="$dir/log/$label.corsie" rc=1
  if [ "${FIC_LANES:-1}" = 0 ]; then echo "blocks-independent: esito=serie motivo=FIC_LANES=0" > "$c"; return 1; fi
  if [ -z "$pre_file" ]; then echo "blocks-independent: esito=serie motivo=$(msg run-phase.bi_no_tree)" > "$c"; return 1; fi
  if [ -n "${FIC_CORSIE:-}" ] && [ -f "$FIC_CORSIE" ]; then   # harness-pt14: decided by the driver (same commands)
    tr -d '\r' < "$FIC_CORSIE" > "$c"
    grep -qx 'blocks-independent: esito=parallelo corsie=2' "$c"; return
  fi
  if [ ! -f "$spec" ] || [ ! -f "$PC_SH" ] || [ ! -f "$BI" ]; then echo "blocks-independent: esito=serie motivo=$(msg run-phase.bi_missing)" > "$c"; return 1; fi
  rm -rf "$t"; mkdir -p "$t" || return 1
  if bash "$PC_SH" gen "$spec" --run-dir "$t" >/dev/null 2>&1 && [ -f "$t/gen/procedura.txt" ]; then
    PROJECT_ROOT=$FIC_REPO "$FIC_PY" "$BI" --root "$FIC_REPO" "$t/gen/procedura.txt" 2>>"$err" | tr -d '\r' > "$c"; rc=${PIPESTATUS[0]}
    [ $rc -le 1 ] || echo "blocks-independent: esito=serie motivo=$(msg run-phase.bi_failed rc="$rc")" > "$c"
  else
    echo "blocks-independent: esito=serie motivo=$(msg run-phase.bi_no_gen)" > "$c"
  fi
  rm -rf "$t"
  [ $rc -eq 0 ] && grep -qx 'blocks-independent: esito=parallelo corsie=2' "$c"
}
# Lane outcome: `estrai <log> <out>` writes the declared files (JSON "file" field) of the lane;
# `unisci <log1> <log2> <posteriori> <exit1> <exit2>` (an exit != 0 is STOP «corsia k: uscita N») prints ONE result event with the ESITO and the JSON merged (validation against the
# schema stays the usual one, on the last result event of <label>.jsonl). The most conservative wins.
LANE_PY='import importlib.util, json, os, re, sys
sys.stdout.reconfigure(encoding="utf-8")
sys.dont_write_bytecode = True
_s = importlib.util.spec_from_file_location("maat_msg", os.environ["MAAT_MSG_PY"])
_m = importlib.util.module_from_spec(_s)
_s.loader.exec_module(_m)
T = _m.T   # the message catalog (msg_py)
def ultimo(log):
    res = None
    try:
        for ln in open(log, encoding="utf-8", errors="replace"):
            try:
                ev = json.loads(ln)
            except ValueError:
                continue
            if isinstance(ev, dict) and ev.get("type") == "result":
                res = ev
    except OSError:
        pass
    return None if res is None or res.get("is_error") else res
def blocco(res):
    so = res.get("structured_output")
    if isinstance(so, dict):
        return so
    rec = re.findall(r"```json[ \t]*\r?\n(.*?)\r?\n[ \t]*```", res.get("result") or "", re.S)
    try:
        return json.loads(rec[-1]) if rec else None
    except ValueError:
        return None
LISTE = ("deviazioni", "file", "gate_interni", "finding")
def forma(o):
    return (isinstance(o, dict) and all(isinstance(o.get(f), list) for f in LISTE)
            and all(isinstance(o.get(f), str) for f in ("esito", "motivo", "bloccato_su")))
def riga(res, o):
    # With --json-schema the result field often carries ONLY the JSON, without the text line: then the line is derived
    # from the structured object (already shape-checked), like `driver.py valida` in series. Text line present: it wins,
    # and if it contradicts the object STOP wins (text STOP below; object STOP via m["esito"] and `driver.py valida`).
    l = next((l.strip() for l in reversed((res.get("result") or "").splitlines()) if l.strip().startswith(("PHASE RESULT", "ESITO FASE"))), "")
    if l or not forma(o):
        return l
    return "PHASE RESULT implement: %s — %s" % ("OK" if o["esito"] == "OK" else "STOP", " ".join(o["motivo"].split()) or "-")
if sys.argv[1] == "estrai":
    r = ultimo(sys.argv[2]); o = blocco(r) if r else None
    with open(sys.argv[3], "w", encoding="utf-8", newline="\n") as fh:
        for f in (o.get("file") if forma(o) else []):
            fh.write(str(f).replace("\\", "/") + "\n")
    sys.exit(0)
logs, post = sys.argv[2:4], open(sys.argv[4], encoding="utf-8", errors="replace").read().strip()
codici = sys.argv[5:7]
stop = "" if post.startswith("posteriori: esito=OK") else T("run-phase.lane_post") + (post.split("— ", 1)[-1] if post else T("run-phase.lane_post_not_run"))
prob, objs, righe = [], [], []
for k, log in enumerate(logs, 1):
    r = ultimo(log)
    o = blocco(r) if r else None
    if len(codici) >= k and codici[k - 1] != "0":
        prob.append(T("run-phase.lane_exit", k=k, rc=codici[k - 1]))
    elif r is None:
        prob.append(T("run-phase.lane_no_result", k=k))
    elif not forma(o):
        prob.append(T("run-phase.lane_no_json", k=k))
    else:
        objs.append((k, o)); righe.append((k, riga(r, o)))
if prob:
    print(json.dumps({"type": "result", "result": "PHASE RESULT implement: STOP — " + "; ".join(prob + ([stop] if stop else []))}))
    sys.exit(0)
def dev_corsia(k, d):   # the defensive prefix stays at the start (DEFENSIVE DEVIATIONS): "difensiva: corsia k: …"
    s = " ".join(str(d).split())
    # the prefix as written (1.3.0: the English one too); 1.9.0 (K6a, K0.2): also that of a defective test
    for pre in ("difensiva: ", "defensive: ", "test-difettoso: ", "defective-test: "):  # PREFISSO-IN-TESTA
        if s.startswith(pre):
            return T("run-phase.lane_dev_pre", pre=pre, k=k, d=s[len(pre):])
    return T("run-phase.lane_item", k=k, d=d)
m = {"fase": "implement", "esito": "OK", "motivo": " · ".join(T("run-phase.lane_item", k=k, d=o["motivo"]) for k, o in objs),
     "deviazioni": [dev_corsia(k, d) for k, o in objs for d in o["deviazioni"]], "bloccato_su": "nessuno",
     "file": [], "gate_interni": [g for k, o in objs for g in o["gate_interni"]], "finding": [f for k, o in objs for f in o["finding"]]}
for k, o in objs:
    m["file"] += [f for f in o["file"] if f not in m["file"]]
    if o["esito"] != "OK":
        m["esito"] = "STOP"
    if " ".join(o["bloccato_su"].split()).lower() not in ("nessuno", "none") and m["bloccato_su"] == "nessuno":
        m["bloccato_su"] = T("run-phase.lane_item", k=k, d=o["bloccato_su"])
    if isinstance(o.get("fase"), str) and o["fase"] != "implement":
        m["fase"] = o["fase"]   # the usual validation rejects it: phase different from the one of the label
    if isinstance(o.get("copertura"), list):
        m.setdefault("copertura", []).extend(o["copertura"])
if stop:
    m["esito"] = "STOP"
    m["bloccato_su"] = stop if m["bloccato_su"] == "nessuno" else m["bloccato_su"] + "; " + stop
ko = [(k, l) for k, l in righe if not re.match(r"(?:PHASE RESULT|ESITO FASE) implement: OK", l)]
if stop:
    testo = "PHASE RESULT implement: STOP — " + stop
elif ko:
    testo = "PHASE RESULT implement: STOP — " + T("run-phase.lane_item", k=ko[0][0], d=re.sub(r"^(?:PHASE RESULT|ESITO FASE) [^:]*:\s*(STOP\s*—\s*)?", "", ko[0][1]) or T("run-phase.lane_no_esito"))
else:
    testo = "PHASE RESULT implement: OK — " + T("run-phase.lane_ok") + m["motivo"]
print(json.dumps({"type": "result", "subtype": "fic_corsie", "result": testo, "structured_output": m}, ensure_ascii=False))'
launch_lanes() { # two subsessions together (one per lane), then after-the-fact check and merged result event
  local k b s o p c="$dir/log/$label.corsie" c1 c2 pids=() pre post lf=()
  echo '{"type":"system","subtype":"fic_corsie"}' > "$log"
  rm -f "$dir"/{do-not-touch,mixed}.[12].txt   # a lane dead before the preflight does not merge the lists of a previous round
  for k in 1 2; do
    b=$(sed -n "s/^corsia $k: //p" "$c"); s=$(sed -n "s/^scope $k: //p" "$c"); o=$(sed -n "s/^corsia $((3 - k)): //p" "$c")
    p="$dir/log/$label.corsia-$k.prompt"; lf+=("$dir/log/$label.corsia-$k.jsonl")
    { cat "$prompt"; printf '\n%s\n' "CORSIA $k/2 (driver, run-phase.sh): $(msg run-phase.lane_prompt b="$b" s="$s" o="$o" k="$k" k="$k")"; } > "$p"
    FIC_LANE=$k FIC_WRITE_SCOPE=$s WSLENV="FIC_LANE${WSLENV:+:$WSLENV}" \
      CLAUDE_PLUGIN_ROOT=$MAAT_ROOT "$CL" -p --permission-mode bypassPermissions --disallowedTools "${DENY[@]}" --settings "$SETTINGS" --strict-mcp-config \
      ${SCHEMA_ARGS[@]+"${SCHEMA_ARGS[@]}"} ${PLUGIN_ARGS[@]+"${PLUGIN_ARGS[@]}"} --append-system-prompt "$CHILD_RULES_TXT" \
      --output-format stream-json --verbose < "$p" > "${lf[$((k - 1))]}" 2>> "$err" &
    pids+=($!)
  done
  cpid=${pids[0]} cpid2=${pids[1]}
  if [ $owned -eq 1 ]; then sed -i '/^cpid2\{0,1\}=/d' "$held/owner" 2>/dev/null; printf 'cpid=%s\ncpid2=%s\n' "$cpid" "$cpid2" >> "$held/owner"; fi
  wait "$cpid"; c1=$?
  wait "$cpid2"; c2=$?
  code=$c1; [ "$code" -eq 0 ] && code=$c2
  # preflight lists of the lanes (do-not-touch.<k>.txt, mixed.<k>.txt) -> the lists read by later phases
  for k in do-not-touch mixed; do
    if [ -f "$dir/$k.1.txt" ] || [ -f "$dir/$k.2.txt" ]; then
      cat "$dir/$k.1.txt" "$dir/$k.2.txt" 2>/dev/null | tr -d '\r' | sed '/^[[:space:]]*$/d' | sort -u > "$dir/$k.txt"
    fi
  done
  # after-the-fact check: the tree diff during the lanes, split by scope
  pre=$(cat "$pre_file" 2>/dev/null); post=$(tree_now)
  if [ -n "$pre" ] && [ -n "$post" ] && (cd "$FIC_REPO" && git -c core.quotePath=false diff --name-only --no-renames "$pre" "$post") > "$dir/log/$label.cambiati" 2>>"$err"; then
    for k in 1 2; do "$FIC_PY" -c "$LANE_PY" estrai "${lf[$((k - 1))]}" "$dir/log/$label.corsia-$k.file" 2>>"$err"; done
    "$FIC_PY" "$BI" --posteriori "$c" "$dir/log/$label.cambiati" "$dir/log/$label.corsia-1.file" "$dir/log/$label.corsia-2.file" 2>>"$err" | tr -d '\r' > "$dir/log/$label.posteriori"
  else
    echo "posteriori: esito=STOP — $(msg run-phase.post_no_diff)" > "$dir/log/$label.posteriori"
  fi
  "$FIC_PY" -c "$LANE_PY" unisci "${lf[0]}" "${lf[1]}" "$dir/log/$label.posteriori" "$c1" "$c2" 2>>"$err" | tr -d '\r' >> "$log"
}

# --- attribution: paths changed by implement/fix phases, closing of killed phases ---
if [ $code_phase -eq 1 ]; then
  for f in "$dir"/log/*.pre-tree; do
    [ -f "$f" ] && [ ! -f "${f%.pre-tree}.post-tree" ] && close_pre "$f" "$dir"
  done
fi
pre_file=""
if [ "$phase" = implement ] || [ "$phase" = fix ] || [ "$phase" = test-red ]; then
  pre_file="$dir/log/$label.pre-tree"
  rm -f "$pre_file" "$dir/log/$label.post-tree"
  t=$(tree_now) && [ -n "$t" ] && echo "$t" > "$pre_file" || { echo "AVVISO: $(msg run-phase.tree_not_computed label="$label")" >> "$err"; pre_file=""; }
fi

# --- test-red / test-stage phases (harness-pt11): guard write scope, parked tests (S3) ---
staged=0
if [ "$phase" = test-red ] || [ "$phase" = test-stage ]; then
  scope="$dir/log/$label.scope"
  plan_fp=$(bash "$PC" basis "$SPEC_F" 2>/dev/null | tr -d '\r' | sed -n 's/^Basis: .*plan \([0-9a-f]*\).*/\1/p')
  if [ "$phase" = test-red ]; then
    bash "$PC" accept "$SPEC_F" 2>>"$err" | tr -d '\r' | sed -n 's/^\(test\|nuovo\|stub\) //p' > "$scope"
  else   # test-stage: only <run-dir>/staging/, tied to the fingerprint of the candidate plan
    mkdir -p "$dir/staging"
    sa=$(cd "$dir" && pwd); sa=$(maat_cygm "$sa" 2>/dev/null || printf '%s' "$sa")
    sr=$(maat_cygm "$FIC_REPO" 2>/dev/null || printf '%s' "$FIC_REPO")
    printf '%s/staging/\n' "${sa#"$sr"/}" > "$scope"
    echo "$plan_fp" > "$dir/staging.fp"; rm -f "$dir/staging.origine"   # 1.8.0: parked by test-stage, not by a STOP
  fi
  # 1.9.1 (C4): absolute, so the guard does not open it against the session's current folder (a `cd` into evidence/
  # made an in-scope Edit denied)
  sab="$(cd "$(dirname "$scope")" && pwd)/$(basename "$scope")"
  FIC_SCOPE=$(maat_cygm "$sab" 2>/dev/null || printf '%s' "$sab"); export FIC_SCOPE
  if [ "$phase" = test-red ] && { [ -d "$dir/staging" ] || [ -f "$dir/staging.fp" ]; }; then
    sfp=$([ -f "$dir/staging.fp" ] && tr -d '\r\n' < "$dir/staging.fp")
    if [ -n "$sfp" ] && [ "$sfp" = "$plan_fp" ] && [ -d "$dir/staging" ]; then   # CONFRONTO-IMPRONTA-STAGING
      nst=0
      while IFS= read -r f; do
        r=${f#"$dir/staging/"}
        if grep -qxF -- "$r" "$scope"; then
          mkdir -p "$FIC_REPO/$(dirname "$r")" && cp "$f" "$FIC_REPO/$r" && nst=$((nst + 1))
        else echo "AVVISO: S3: $(msg run-phase.s3_outside r="$r")" >> "$err"; fi
      done < <(find "$dir/staging" -type f | LC_ALL=C sort)
      rm -rf "$dir/staging.copiato"; mv "$dir/staging" "$dir/staging.copiato"; rm -f "$dir/staging.fp"
      # 1.8.0 (D4.5, DA7): files parked by a STOP of test-red (staging.origine=stop): copied back, and the subsession is
      # launched all the same (they are not the proof of a finished phase, only the work to resume)
      if [ "$(tr -d '\r\n' < "$dir/staging.origine" 2>/dev/null)" = stop ]; then  # ORIGINE-STOP
        echo "S3: $(msg run-phase-180.s3_stop n="$nst")" >> "$err"
      else
        [ $nst -gt 0 ] && staged=1
      fi
      rm -f "$dir/staging.origine"
      echo "S3: $(msg run-phase.s3_copied n="$nst" fp="$sfp")" >> "$err"
    else
      if [ "$(tr -d '\r\n' < "$dir/staging.origine" 2>/dev/null)" = stop ] && [ -d "$dir/staging" ]; then  # SCARTATO-CONSERVATO
        # (B12-B13 review) files parked by a STOP are work, not a cache: kept in staging.scartato (the last one)
        rm -rf "$dir/staging.scartato"; mv "$dir/staging" "$dir/staging.scartato"
        echo "AVVISO: S3: $(msg run-phase-180.s3_kept fp="${sfp:-$(msg run-phase.missing)}")" >> "$err"
      fi
      rm -rf "$dir/staging" "$dir/staging.fp" "$dir/staging.origine"
      echo "S3: $(msg run-phase.s3_discarded fp="${sfp:-$(msg run-phase.missing)}" plan="${plan_fp:-$(msg cycle-state.not_computable)}")" >> "$err"
    fi
  fi
fi

date -u +%Y-%m-%dT%H:%M:%SZ > "$dir/log/$label.running"

stdin_file=$prompt
# Review of a ring k>1 (harness-pt12, M1): the surface is built by the driver, not by the reviewer. Diff from the
# "Base anello" (.post-tree of k-1, from cycle-state.sh) to the current tree, on the files of THIS ring's touched.txt
# only: a file also touched by k-1 shows only k's hunks. File and index appended to the prompt (which becomes
# log/<label>.prompt-anello: review ∥ VERIFY and sequence use it as the starting prompt). Base missing or diff
# failed → exit 7, the review does not start (never a ring review on the diff from HEAD). Rebuilt before a
# relaunch in sequence after a discard (harness-pt09), so the diff is always that of the reviewed tree.
# DEFENSIVE DEVIATIONS: the review receives the list to judge appended to the starting prompt (the ring's too).
if [ "$phase" = review ] && [ -s "$dir/log/deviazioni-difensive.txt" ]; then
  { cat "$prompt"; printf '\n%s\n' "DEVIAZIONI DIFENSIVE (driver, run-phase.sh): $dir/log/deviazioni-difensive.txt — $(msg run-phase.defensive_prompt)"; tr -d '\r' < "$dir/log/deviazioni-difensive.txt"; } > "$dir/log/$label.prompt-difensive"
  prompt="$dir/log/$label.prompt-difensive" stdin_file="$dir/log/$label.prompt-difensive"
fi
# 1.8.0 (A1): the test-data deviations accepted in test-red, the same way (the review writes them in its section
# «Deviazioni di test accettate»: the instruction is the text of the line, outside the base load of the review)
if [ "$phase" = review ] && [ -s "$dir/log/deviazioni-accettate.txt" ]; then
  # 1.9.0 (K6a): the text of the two families when a defective-test deviation is in the list, that of 1.8.0 otherwise
  acp=$(msg run-phase-180.accepted_prompt); grep -Eq '	(test-difettoso|defective-test): ' "$dir/log/deviazioni-accettate.txt" && acp=$(msg run-phase-190.accepted_prompt)
  { cat "$prompt"; printf '\n%s\n' "DEVIAZIONI DI TEST ACCETTATE (driver, run-phase.sh): $dir/log/deviazioni-accettate.txt — $acp"; tr -d '\r' < "$dir/log/deviazioni-accettate.txt"; } > "$dir/log/$label.prompt-deviazioni"  # PROMPT-DEVIAZIONI
  prompt="$dir/log/$label.prompt-deviazioni" stdin_file="$dir/log/$label.prompt-deviazioni"
fi
ring_stop() { echo "$1" | tee -a "$err" >&2; rm -f "$dir/log/$label.running"; finish 7; }
ring=0 prompt0=$prompt
ring_prompt() {
  local rd="$dir/log/$label.anello.diff" rt ridx
  { [ -f "$dir/touched.txt" ] && tr -d '\r' < "$dir/touched.txt"; } | grep . > "$dir/log/$label.anello.paths"
  if [ -s "$dir/log/$label.anello.paths" ] && rt=$(tree_now) && [ -n "$rt" ] \
     && ridx=$(cd "$FIC_REPO" && bash "$RS" diff --from "$rb" --to "$rt" --paths-file "$dir/log/$label.anello.paths" --out "$rd" 2>>"$err"); then
    { cat "$prompt0"; printf '\n%s\n%s\n' "DIFF DELL'ANELLO (driver, run-phase.sh): $rd — $(msg run-phase.ring_prompt rb="$rb" rt="$rt")" "$ridx"; } > "$dir/log/$label.prompt-anello"
    prompt="$dir/log/$label.prompt-anello" stdin_file="$dir/log/$label.prompt-anello"
  else
    ring_stop "STOP — catena: $(msg run-phase.ring_no_diff rb="$rb" dir="${dir}")"
  fi
}
if [ "$phase" = review ] && is_ring; then
  cycle_state_read "${dir%.run}.md" || ring_stop "STOP — $cs_why — $(msg run-phase.not_launched)"
  rk=$(printf '%s\n' "$cso" | sed -n 's/^Catena: anello \([0-9][0-9]*\)\/.*/\1/p' | head -1)
  rb=$(printf '%s\n' "$cso" | sed -n 's/^Base anello: \([0-9a-f]\{40\}\)$/\1/p')
  if [ "${rk:-1}" -le 1 ]; then :   # ring 1: its base is the usual one
  elif [ -n "$rb" ]; then ring=1; ring_prompt
  else
    ring_stop "STOP — catena: $(msg run-phase.ring_no_base rk="$rk")"
  fi
fi
code=0 skip_cl=0 chz_ev="" esito=""
if [ "$phase" = chiusura ]; then   # full gates on the final tree; the subsession only for the children's e2e
  chiusura_prep
  [ -z "$chz_fail" ] && chz_ev=$(run_gates)
  if [ -z "$chz_fail" ] && [ -n "$chz_e2e" ] && grep -q '^exit=0 ' "$dir/log/$label.gates" 2>/dev/null; then
    stdin_file="$dir/log/$label.prompt"
    { cat "$prompt"; printf '\n%s\n' "E2E DELLA CATENA: $chz_e2e"; } > "$stdin_file"
  else
    skip_cl=1
  fi
fi

# --- structured outcome (harness-pt08): the schema is passed by content, compact ---
SCHEMA=${FIC_SCHEMA:-$MAAT_SCHEMAS/phase-result.schema.json}
SCHEMA_ARGS=()
if [ "$phase" = chiusura ]; then :   # closing is not in the outcome schema: its ESITO line counts
elif [ -f "$SCHEMA" ] && sc=$("$FIC_PY" -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1], encoding="utf-8")), separators=(",", ":")))' "$SCHEMA" 2>>"$err" | tr -d '\r') && [ -n "$sc" ]; then
  SCHEMA_ARGS=(--json-schema "$sc")
else
  echo "AVVISO: $(msg run-phase.no_schema schema="$SCHEMA")" >> "$err"
fi
# --plugin-dir only as an explicit override (MAAT_PLUGIN_DIR; the replay always sets it): normally the subsession
# finds the plugin because it is enabled in the project (pk01 D1; D8: with the plugin also enabled nothing is duplicated)
PLUGIN_ARGS=()
[ -n "${MAAT_PLUGIN_DIR:-}" ] && PLUGIN_ARGS=(--plugin-dir "$MAAT_PLUGIN_DIR")
CHILD_RULES="$MAAT_SKILLS/full-implementation-cycle/child-rules.md"
# Claude Code replaces ${CLAUDE_PLUGIN_ROOT} only in the texts of SKILL.md and of the agents: in the text passed with
# --append-system-prompt the replacement is done here, deterministically, with MAAT_ROOT (and the subsession receives
# CLAUDE_PLUGIN_ROOT=$MAAT_ROOT in the environment, see launch)
CHILD_RULES_TXT=$(cat "$CHILD_RULES" 2>>"$err")
CHILD_RULES_TXT=${CHILD_RULES_TXT//'${CLAUDE_PLUGIN_ROOT}'/$MAAT_ROOT}

lanes=0   # lanes (harness-pt13): implement only, only with computed independent blocks
[ "$phase" = implement ] && lanes_decide && lanes=1
mode="" why="" par="$dir/log/$label.parallelo"
if [ "$phase" = review ]; then
  mode=sequenza
  rs_now=$(review_status)
  if [ "${FIC_REVIEW_PARALLEL:-1}" = 0 ]; then why="FIC_REVIEW_PARALLEL=0"
  elif [ "${rs_now%% *}" = APPROVED ]; then why="$(msg run-phase.seq_approved)"
  else
    # driver counterproofs ONLY on a plan-check.sh gen list consistent with the plan (orchestrator decision):
    # a list written by the worker in a previous round stays the worker's, which rewrites it every round
    ! ls "$dir"/counterproof/*.meta >/dev/null 2>&1 && cp_from_gen && cp_driver=1
    if k0=$(verify_key) && [ -n "$k0" ]; then mode=parallelo; else why="$(msg run-phase.seq_no_key)"; cp_driver=0; fi
  fi
fi
if [ "$mode" = parallelo ]; then
  # VERIFY (gates.sh, then counterproof.sh only if the list is the plan-check.sh gen one, consistent with the plan:
  # cp_from_gen) and the review start TOGETHER, on the same key.
  cpw=worker; [ $cp_driver -eq 1 ] && cpw=driver
  printf 'modo=parallelo controprove=%s chiave=%s\n' "$cpw" "$(printf '%s' "$k0" | sha256sum | cut -c1-12)" > "$par"
  [ -f "${dir%.run}.md" ] && cp "${dir%.run}.md" "$dir/log/$label.spec-pre"
  stdin_file="$dir/log/$label.prompt"
  if [ $cp_driver -eq 1 ]; then cpn="$(msg run-phase.cp_driver)"
  else cpn="$(msg run-phase.cp_worker)"; fi
  { cat "$prompt"; printf '\n%s\n' "VERIFY IN PARALLELO (driver, run-phase.sh): $(msg run-phase.verify_prompt cpn="$cpn")"; } > "$stdin_file"
  ( run_gates >/dev/null; [ $cp_driver -eq 1 ] && run_cp ) & vpid=$!
  [ $owned -eq 1 ] && echo "vpid=$vpid" >> "$held/owner"   # lock_alive: a live VERIFY holds the lock
  launch "$stdin_file" ">"
  wait $vpid
  k1=$(verify_key) || k1=""   # ricalcolo finale della chiave (harness-pt09)
  if [ "$k1" != "$k0" ]; then
    # tree (or mutations.json) changed while review and VERIFY were running: neither result belongs to a single tree
    msg="scartato: $(msg run-phase.discarded k0="$(printf '%s' "$k0" | sha256sum | cut -c1-12)" k1="$(printf '%s' "$k1" | sha256sum | cut -c1-12)")"
    echo "$msg" >> "$par"; echo "AVVISO: $msg" >> "$err"
    [ -f "$dir/log/$label.spec-pre" ] && cp "$dir/log/$label.spec-pre" "${dir%.run}.md"
    # the evidence of the parallel window must not stay reusable (gates.sh with an identical key) nor FRESH for
    # finalize.sh: its folder becomes <key>.scartato (--verify sees it STALE, gates.sh does not find it)
    evd=$(sed -n 's/^gates: esito=.* evidence=\(.\{2,\}\)$/\1/p' "$dir/log/$label.gates" 2>/dev/null | tail -1)
    if [ -n "$evd" ] && [ "$evd" != - ] && [ -d "$evd" ]; then rm -rf "$evd.scartato"; mv -f "$evd" "$evd.scartato"; fi
    [ -f "$dir/log/$label.gates" ] && mv -f "$dir/log/$label.gates" "$dir/log/$label.gates.scartato"
    [ -f "$dir/log/$label.counterproof" ] && mv -f "$dir/log/$label.counterproof" "$dir/log/$label.counterproof.scartato"
    cp_clear   # in worker mode too: the <id>.json of the discarded round do not count
    [ $owned -eq 1 ] && sed -i '/^vpid=/d' "$held/owner" 2>/dev/null
    # the log stays one (the Monitor follows it): an event marks the discard, the outcome is read only after it
    echo '{"type":"system","subtype":"fic_scartato"}' >> "$log"
    mode=sequenza why="$(msg run-phase.seq_key_changed)" relaunch=1
  fi
fi
if [ "$mode" = sequenza ]; then   # the previous sequence: gates, then the review with the evidence in the prompt
  echo "modo=sequenza — ${why:-sequenza}" >> "$par"
  [ "${relaunch:-0}" = 1 ] && [ $ring -eq 1 ] && ring_prompt   # ring diff on the relaunch tree
  stdin_file=$prompt
  ev=$(run_gates)   # with an identical key it is a reuse, not a relaunch
  if [ -n "$ev" ] && [ "$ev" != - ]; then
    stdin_file="$dir/log/$label.prompt"
    { cat "$prompt"; printf '\n%s\n' "EVIDENZE DEI GATE (driver, run-phase.sh): $ev — $(grep '^gates: esito=' "$dir/log/$label.gates" | tail -1 | sed 's/ chiave=.*//'). $(msg run-phase.gates_prompt)"; } > "$stdin_file"
  fi
  launch "$stdin_file" "$([ "${relaunch:-0}" = 1 ] && echo '>>' || echo '>')"
elif [ $staged -eq 1 ]; then   # S3 (harness-pt11): the parked tests are in the tree, no subsession; the verification is below
  msg -v s3m run-phase.s3_result   # the text has no quote nor backslash: it goes into the JSON as it is
  printf '{"type":"result","result":"PHASE RESULT test-red: OK — %s","structured_output":{"fase":"test-red","esito":"OK","motivo":"%s","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}\n' "$s3m" "$s3m" > "$log"
  code=0
elif [ $lanes -eq 1 ]; then   # lanes (harness-pt13): implement only, after S3 and before the single launch
  launch_lanes
elif [ "$phase" != review ] && [ $skip_cl -eq 0 ]; then   # closing without e2e (or with red gates) does not launch the subsession
  launch "$stdin_file" ">"
fi

if [ -n "$pre_file" ]; then
  # test-red (OTHER FLOWS): touched.txt before this phase, to remove only what enters it now
  # (pk09: touched.txt missing at the first code phase — checked beforehand: the input redirect `<` is evaluated
  # before `2>/dev/null`, and the «No such file» error still came out in the phase stderr)
  [ "$phase" = test-red ] && { [ -f "$dir/touched.txt" ] && tr -d '\r' < "$dir/touched.txt"; true; } > "$dir/log/$label.touched-pre"
  close_pre "$pre_file" "$dir"
  case "$phase" in implement|fix) altri_flussi ;; esac
fi
# DEFENSIVE DEVIATIONS (see the top). DIFENSIVE_PY estrai <result.json>: the deviations, one per line, only if
# ALL start with "difensiva: " (otherwise nothing: the phase is already STOP). DIFENSIVE_PY nota <spec> <label>
# <file>: "- nota (deviazione difensiva, <label>): <testo>" after the last line of the "### Changelog revisione piano"
# (same zones as plan-check.sh annotate, outside fences; lines already present skipped, line ending kept); exit 3
# if the plan has no changelog.
DIFENSIVE_PY='
import importlib.util, json, os, re, sys
sys.stdout.reconfigure(encoding="utf-8")
sys.dont_write_bytecode = True
_s = importlib.util.spec_from_file_location("maat_msg", os.environ["MAAT_MSG_PY"])
_m = importlib.util.module_from_spec(_s)
_s.loader.exec_module(_m)
T = _m.T   # the message catalog (msg_py)
one = lambda s: " ".join(str(s).split())
if sys.argv[1] == "estrai":
    dev = [one(x) for x in json.load(open(sys.argv[2], encoding="utf-8")).get("deviazioni") or [] if str(x).strip()]
    # 1.9.0 (K6a): next to defective-test deviations (accepted: this runs only on an OK outcome) the defensive ones
    if dev and all(x.startswith(("difensiva: ", "defensive: ", "test-difettoso: ", "defective-test: ")) for x in dev):
        dif = [x for x in dev if x.startswith(("difensiva: ", "defensive: "))]
        if dif:
            print("\n".join(dif))
    sys.exit(0)
spec, label, elenco = sys.argv[2:5]
corretto = len(sys.argv) > 5 and sys.argv[5] == "corretto"   # 1.9.0 (K6a): the note of an accepted defective test
raw = open(spec, "rb").read().decode("utf-8")
nl = "\r\n" if "\r\n" in raw else "\n"
righe = raw.replace("\r\n", "\n").split("\n")
zona, fence, ultima = "above", False, -1
for i, l in enumerate(righe):
    isf = re.match(r"^[ \t]*(```|~~~)", l) is not None
    if not fence and not isf:
        if zona == "above" and re.match(r"^## (Piano di implementazione|Implementation plan)", l): zona = "plan"
        elif zona in ("plan", "changelog") and re.match(r"^## (Review implementazione|Implementation review)", l): zona = "review"
        elif zona == "plan" and re.match(r"^###[ \t]+([0-9]+\.[ \t]*)?(Changelog revisione piano|Plan review changelog)", l): zona = "changelog"
        elif zona == "changelog" and re.match(r"^##?#?[ \t]", l): zona = "plan"
    if isf:
        fence = not fence
    if zona == "changelog" and l.strip():
        ultima = i
if ultima < 0:
    sys.exit(3)
note = [(T("run-phase-190.note_corrected", label=label, text=one(t)) if corretto else T("run-phase.def_note", label=label, text=one(t))) for t in open(elenco, encoding="utf-8").read().splitlines() if t.strip()]
note = [n for n in note if n not in righe]
if note:
    righe[ultima + 1:ultima + 1] = note
    with open(spec + ".tmp", "wb") as fh:
        fh.write(nl.join(righe).encode("utf-8"))
    import os; os.replace(spec + ".tmp", spec)
'
difensive() { # implement/fix finished OK: records the "difensiva: " deviations (file, AVVISO, note in the changelog)
  local rj="$dir/log/$label.result.json" f="$dir/log/deviazioni-difensive.txt" dl="$dir/log/$label.difensive"
  local sp="${dir%.run}.md" b0 b1 rc
  rm -f "$dl"
  [ -f "$rj" ] && "$FIC_PY" -c "$DIFENSIVE_PY" estrai "$rj" 2>>"$err" | tr -d '\r' > "$dl" && [ -s "$dl" ] || { rm -f "$dl"; return 0; }
  # one line per deviation, "<label><TAB><text>"; a relaunch of the same label replaces its own
  { [ -f "$f" ] && tr -d '\r' < "$f" | grep -v "^$label	"; awk -v l="$label" '{ print l "\t" $0 }' "$dl"; } > "$f.tmp" && mv -f "$f.tmp" "$f"
  avviso "AVVISO: $(msg run-phase.def_count n="$(grep -c . "$dl")")"
  [ -f "$sp" ] || return 0
  b0=$(bash "$PC_SH" basis "$sp" 2>/dev/null | tr -d '\r' | grep '^Basis: ')
  cp "$sp" "$dl.spec-pre"
  "$FIC_PY" -c "$DIFENSIVE_PY" nota "$sp" "$label" "$dl" 2>>"$err"; rc=$?
  b1=$(bash "$PC_SH" basis "$sp" 2>/dev/null | tr -d '\r' | grep '^Basis: ')
  if [ $rc -eq 3 ]; then avviso "AVVISO: $(msg run-phase.def_no_changelog)"
  elif [ $rc -ne 0 ] || [ -z "$b0" ] || [ "$b0" != "$b1" ]; then   # never a STALE spec for a note
    cp "$dl.spec-pre" "$sp"
    avviso "AVVISO: $(msg run-phase.def_not_written rc="$rc" b0="${b0:-$(msg run-phase.not_computed)}" b1="${b1:-$(msg run-phase.not_computed)}")"
  fi
  rm -f "$dl.spec-pre"
}
# Outcome: only from the "result" event (the log also contains the texts read by the phase, with ESITO examples).
# Prints the ESITO line (or the «uscita non valida» STOP and, below it, originale=<line>) and writes result.json if valid.
if [ $code -eq 0 ] && [ "$phase" != chiusura ]; then
  esito=$(valida "$log" "$SCHEMA" "$phase" "$dir/log/$label.result.json" 2>>"$err" | tr -d '\r')
fi
# Finalize (harness-pt08): after a finished review, the final state is signed by the script, before .esito
# records the end-of-phase State; AFTER result.json, because it merges its coverage (harness-pt09).
# Fail-closed: finalize missing, or exited with a code other than 0/1/3/4 -> .esito = STOP (below).
FINALIZE=${FIC_FINALIZE:-$MAAT_SCRIPTS/finalize.sh}
fin_fail=""
if [ "$phase" = review ] && [ $code -eq 0 ] && [ -f "${dir%.run}.md" ]; then
  if [ ! -f "$FINALIZE" ]; then
    fin_fail="finalize non eseguito ($(msg run-phase.fin_missing fin="$FINALIZE"))"; echo "$fin_fail" > "$dir/log/$label.finalize"
  else
    cop_args=(); [ -f "$dir/log/$label.result.json" ] && cop_args=(--copertura "$dir/log/$label.result.json")
    FIC_GATES="$GATES" FIC_GATES_ROOT="$FIC_REPO" bash "$FINALIZE" --level "$(gates_level)" ${cop_args[@]+"${cop_args[@]}"} "$dir" > "$dir/log/$label.finalize" 2>&1
    frc=$?
    echo "exit=$frc" >> "$dir/log/$label.finalize"
    case $frc in 0|1|3|4) ;; *) fin_fail="finalize fallito ($(msg run-phase.fin_failed rc="$frc" label="$label"))" ;; esac
  fi
fi
# driver counterproofs with the mirror not restored (counterproof.sh exit 5): we stop, as in the worker
if [ "$phase" = review ] && [ "$(sed -n 's/^exit=//p' "$dir/log/$label.counterproof" 2>/dev/null | tail -1)" = 5 ]; then
  fin_fail="counterproof.sh exit 5: $(msg run-phase.cp_mirror label="$label")${fin_fail:+; $fin_fail}"
fi
# (B12-B13 review, DA7) a test-red that ends technically (subsession exit != 0, killed, no outcome) is parked as well:
# the .post-tree is already written (close_pre above); its line is an AVVISO in the phase stderr
if [ "$phase" = test-red ] && { [ $code -ne 0 ] || [ -z "${esito:-}" ]; }; then  # PARCHEGGIO-TECNICO
  pk=$(parcheggia "PHASE RESULT test-red: STOP — $(msg run-phase-180.park_technical code="$code")" | sed -n 1p)
  case "$pk" in *" · "*) echo "AVVISO: ${pk##* · }" >> "$err" ;; esac
fi
if [ $code -eq 0 ]; then
  if [ -n "$fin_fail" ]; then
    orig=$(printf '%s\n' "$esito" | sed -n '1p')
    esito="PHASE RESULT review: STOP — $fin_fail${orig:+
originale=$orig}"
  fi
  if [ -n "$esito" ]; then   # harness-pt11: red-test verification (test-red), acceptance tests unchanged (implement/fix)
    case "$phase" in
      test-red) esito=$(verify_red "$esito"); esito=$(parcheggia "$esito") ;;
      implement|fix) rm -f "$dir/log/$label.dev-impl.stop"; esito=$(difetto "$esito")   # 1.9.0 (K6a): S2 before the guard
        [ -f "$dir/log/$label.dev-impl.stop" ] || esito=$(tests_guard "$esito") ;;   # a STOP of the verification keeps its cause
    esac
  fi
  # INTERNAL READER (1.5.1): the state of the spec is read BEFORE the defensive deviations are recorded, to decide the
  # outcome: a STOP of the wrapper of cycle-state.sh makes it `PHASE RESULT <phase>: STOP — <reason>` (state= empty,
  # no deviation recorded). Read again only if recording the deviations changed the spec (the State it prints).
  # Without the spec, state= stays empty as before (run dirs without a spec exist only in the tests).
  cs_ok=1 st="" sp_md="${dir%.run}.md"
  # originale= is the subsession's line: an outcome already STOP with its own originale= (the «uscita non valida» of
  # valida, the checks of the tests) keeps that one, otherwise it is line 1
  cs_stop() { orig=$(printf '%s\n' "$esito" | sed -n 's/^originale=//p' | head -1); [ -n "$orig" ] ||
    orig=$(printf '%s\n' "$esito" | sed -n '1p'); cs_ok=0; esito="PHASE RESULT $phase: STOP — $cs_why${orig:+
originale=$orig}"; }
  if [ -n "$esito" ] && [ -f "$sp_md" ]; then
    # (final review 1.8.0, R4/DA7) a test-red OK turned into a STOP here was not parked above (parcheggia parks only a
    # STOP line, and only once: a second call would copy the restored tree over the parked files): park it now
    cs_gia=$(printf '%s\n' "$esito" | sed -n 1p | grep -Ec '^(PHASE RESULT|ESITO FASE) [^:]*: STOP')
    cycle_state_read "$sp_md" || {
      cs_stop
      if [ "$phase" = test-red ] && [ "$cs_gia" = 0 ]; then esito=$(parcheggia "$esito"); fi  # PARCHEGGIO-CS-STOP
    }
  fi
  case "$phase" in implement|fix)   # DEFENSIVE DEVIATIONS: recorded only on an OK outcome (before the state)
    if [ $cs_ok -eq 1 ] && printf '%s\n' "$esito" | sed -n 1p | grep -Eq '^(PHASE RESULT|ESITO FASE) [^:]*: OK'; then
      sp_sum=$(cksum < "$sp_md" 2>/dev/null)
      difensive
      if [ -f "$sp_md" ] && [ "$(cksum < "$sp_md" 2>/dev/null)" != "$sp_sum" ]; then cycle_state_read "$sp_md" || cs_stop; fi
    fi ;;
  esac
  if [ -n "$esito" ]; then
    [ $cs_ok -eq 1 ] && [ -f "$sp_md" ] && st=$(printf '%s\n' "$cso" | sed -n 's/^State: //p')
    printf '%s\nstate=%s\n' "$esito" "$st" > "$dir/log/$label.esito"
    cat "$dir/log/$label.avvisi" >> "$dir/log/$label.esito" 2>/dev/null   # OTHER FLOWS: after state=, line 1 stays the outcome
  fi
fi
# closing of a chain (see CHAINS): IMPLEMENTED only with green full gates and, if required, OK e2e
if [ "$phase" = chiusura ]; then
  chz_why="$chz_fail"
  if [ -z "$chz_why" ]; then
    grep -q '^exit=0 ' "$dir/log/$label.gates" 2>/dev/null \
      || chz_why="$(msg run-phase.chz_gates g="$(sed -n 's/^gates: esito=\([A-Z]*\).*/\1/p' "$dir/log/$label.gates" 2>/dev/null | tail -1)" label="$label")"
  fi
  chz_e2e_st="$(msg run-phase.chz_e2e_none)"
  if [ -z "$chz_why" ] && [ -n "$chz_e2e" ]; then
    chz_res=$(grep '"type":"result"' "$log" 2>/dev/null | tail -1)
    if [ $code -eq 0 ] && printf '%s' "$chz_res" | grep -Eq '(PHASE RESULT|ESITO FASE) chiusura: OK' && ! printf '%s' "$chz_res" | grep -q '"is_error":true'; then
      chz_e2e_st="OK ($chz_e2e)"
    else chz_why="$(msg run-phase.chz_e2e_failed e2e="$chz_e2e" rc="$code" label="$label")"; fi
  fi
  chz_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  chz_tree=""; [ -z "$chz_why" ] && { chz_tree=$(tree_now) || chz_tree=""; [ -n "$chz_tree" ] || chz_why="$(msg run-phase.chz_no_tree)"; }
  if [ -z "$chz_why" ]; then
    printf 'Chiusura: IMPLEMENTED — base %s · tree %s · gates PASS (%s) · e2e %s · %s\n' "$(cat "$dir/base.txt")" "$chz_tree" "${chz_ev:--}" "$chz_e2e_st" "$chz_now" > "$dir/chiusura.txt"
    chz_esito="PHASE RESULT chiusura: OK — $(msg run-phase.chz_ok e2e="$chz_e2e_st")"
  else
    printf 'Chiusura: NEEDS_VERIFICATION — %s · %s\n' "$chz_why" "$chz_now" > "$dir/chiusura.txt"
    chz_esito="PHASE RESULT chiusura: STOP — $chz_why"
  fi
  # INTERNAL READER (1.5.1): a STOP of the wrapper of cycle-state.sh -> state= empty and, if the closing was OK, the
  # outcome becomes that STOP (a closing already STOP keeps its own reason); chiusura.txt, the verdict of the gates
  # written above, is not touched: the resume decides from it
  st=""
  if cycle_state_read "${dir%.run}.md"; then st=$(printf '%s\n' "$cso" | sed -n 's/^State: //p')
  elif [ -z "$chz_why" ]; then chz_esito="PHASE RESULT chiusura: STOP — $cs_why"; fi
  printf '%s\nstate=%s\n' "$chz_esito" "$st" > "$dir/log/$label.esito"
fi
# gates after an implement/fix finished OK, still under the lock (the following review reuses them with an identical key)
case "$phase" in implement|fix)
  [ $code -eq 0 ] && grep -Eq '^(PHASE RESULT|ESITO FASE) [^:]*: OK' "$dir/log/$label.esito" 2>/dev/null && run_gates >/dev/null ;;
esac

release   # before .exit: whoever sees the phase finished finds the lock already free
echo "$code" > "$ex"
rm -f "$dir/log/$label.running"
exit $code
