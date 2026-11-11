#!/usr/bin/env bash
# counterproof.sh — the counterproofs of a review, run ONLY in the local copy (mirror), never in the working tree.
#
# Usage:
#   PROJECT_ROOT=<repo> bash <plugin>/scripts/counterproof.sh <run-dir>/counterproof/mutations.json
# Launched by run_cp in run-phase.sh: inside WSL (/mnt/… paths, PROJECT_ROOT and MAAT_CONFIG translated) only on Windows
# and with an `ambiente: wsl` module among those of the mutations; otherwise directly.
# Project root: PROJECT_ROOT, otherwise FIC_REPO, otherwise the git toplevel of the working directory
# (lib/maat-paths.sh, maat_progetto); never from the script location, which is inside the plugin. Unresolved -> exit 64.
# Modules, runners and commands: the project's maat.json (MAAT_CONFIG wins), read by IMPORTING maat-config.py (the same
# reader as the `modulo-di` and `comando` commands). Results go into the folder of mutations.json: one <id>.json
# per mutation.
#
# INPUT FORMAT — mutations.json is a LIST of objects:
#   {
#     "id":        "CP-3",                                   letters, digits, . _ -  (name of the result file)
#     "file":      "web/src/utils/goals.ts",                 relative to the repository
#     "simbolo":   "companyAssignStatus",                    where the mutation is (for the reader)
#     "mutazione": {"cerca": "gap.cents * 20 > goalCents", "sostituisci": "gap.cents * 20 >= goalCents"},
#     "test":      {"percorso": "web/src/tests/goals-utils.test.ts", "nome": "companyAssignStatus soglia"},
#     "rosso_se":  {"test_id": "<full name of the test in the runner>", "asserzione": "<text in the error message>"},
#     "superficie": "…"                                     optional, reported as is
#     "assorbita": true, "motivo": "…"                      optional (L2, harness-pt11): written by
#                                                           `plan-check.sh gen` after the test-red phase
#   }
# - "assorbita": true (L2: NEW file, red at the base with a proven stub, green afterwards) -> the mutation is NOT
#   run: <id>.json with outcome "assorbita" (counterproof ASSORBITA, reason), no runner. It does not enter the counts
#   (prove=<n>/<tot> counts only those run); the last line adds "assorbite=<n>". Absorbed only -> exit 0 without
#   mirror or lock. The L2 conditions are rechecked by finalize.sh (plan-check.sh l2), not by this script.
# - "cerca" must appear EXACTLY once in the file (exact replacement, byte for byte; if the file has
#   CRLF line endings and "cerca" contains \n, it is retried with \r\n). Zero or several occurrences -> blocked.
# - The MODULE is decided by maat.json (`modulo-di` routing): file and test in the SAME module, with the test under
#   the module's `radice`; otherwise exit 64 (one module's runner does not see another module's mutation: it would be
#   a false «green»).
# - The RUNNER is the module's `controprova.runner`; the command line is `controprova.comando`, with the placeholders
#   {test}, {nome}, {report}, {python}, run in the module's `radice` inside the copy:
#   - vitest, pytest: core adapters (timing, process group, lock, classification from the report). {test}
#     is the test file relative to the root (pytest: <file>::<nome>), {nome} the test name (vitest: already
#     escaped for the -t regex, from "test.nome", default rosso_se.test_id), {report} the report the core reads;
#   - comando: red = exit code other than 0 -> rosso_generico, exit 0 -> green. No report: the proof is WEAK
#     (it does not say on which assertion it is red), and the review counts it as such.
# - Module without `controprova` (or without `controprova.comando`) -> the mutation is not run: <id>.json with outcome
#   "non_eseguita" and counterproof "NOT RUN" (declared), never «green» nor «red». It does not enter the counts; the last
#   line adds "non_eseguite=<n>". Only not-run (and absorbed) -> "esito=NOT RUN", exit 0, without mirror.
# - S5, exact duplicates: same file, simbolo, cerca, sostituisci, test and rosso_se => run ONCE,
#   the result applies to all IDs (field "duplicato_di"). Mutations at different points are not duplicates.
#
# OUTCOMES ("esito" field of <id>.json) and counterproof:
#   rosso_asserzione  the named test is red AND the message contains rosso_se.asserzione   -> PASS (proof)
#   rosso_generico    (comando runner) the command exits with non-zero                       -> PASS (weak proof)
#   rosso_import      the test file does not load / import error: NEVER a proof              -> FAIL
#   rosso_raccolta    named file or test not collected, skipped, or collection error         -> FAIL
#   rosso_diverso     the named test is red but not on the expected assertion                -> FAIL
#   verde             the mutation is not covered                                            -> FAIL
#   bloccato          mutation not applicable, runner missing, no report, time cap           -> BLOCKED
#   assorbita         (L2) not run: the red-with-stub / green-after pair counts as counterproof -> ASSORBITA
#   non_eseguita      module without a declared counterproof                                 -> NOT RUN
# The vitest and pytest adapters read the runner's report, never the exit code alone (vitest JSON, pytest
# JUnit: the option that asks for it is in `controprova.comando`, in the profiles).
#
# GUARANTEES
# - The working tree is NEVER written: the mutation is applied to the copy in the mirror, the same as test-fast.sh
#   and with the same rule (fic-mirror.sh): <mirror> = $HOME/fic-mirror from the main tree, $HOME/fic-mirror-<hash>
#   from a worktree (also one created by Git for Windows). Every module of the mutations lives in <mirror>/<radice_pacchetti>.
#   The module with `copia` (at most one among those of the mutations, otherwise exit 64 «più moduli con copia») is
#   the test-fast.sh one: its copy for a worktree without node_modules is seeded as there (hardlinks from the copy
#   of the main tree, only with the same dependencies). A module without `copia` is synced and verified with the
#   manifest, without seeding or fingerprint.
# - Lock: the same file as test-fast.sh, <mirror>/<radice_pacchetti of the module with copia>/.fic-lock (without a
#   module with copia among the mutations: that of the first module with copia in maat.json, otherwise of the first
#   module of the mutations), taken with `flock -w "${FIC_LOCK_WAIT:-900}"`: it WAITS, and beyond the cap -> exit 3. NEVER a
#   fallback to /mnt/c: there the test would run on the unmutated tree and give a false «not red».
# - 1.8.0 (A4) a module at the ROOT of the repository (radice_pacchetti "" or "."), only WITHOUT `copia` (with `copia`
#   -> exit 64: not in 1.8.0, maat-doctor and `maat-config.py valida` say it before the cycle). It is the whole mirror,
#   shared by every module, so:
#   - its sync excludes, besides the core list, the copy state and the locks of EVERY folder (`.fic-*` not
#     anchored: a tracked file of the project named .fic-* is not copied either, and the manifest check gives
#     BLOCKED, said in a line), `/.git` (from a worktree a file that points to the real repository), the cycles
#     folder (`cartelle.lavoro`, anchored; also out of the manifest: OUT writes there during the run) and the
#     `collega_nel_worktree` folders of every module, each anchored to its folder;
#   - it takes <mirror>/.fic-lock AND <mirror>/<radice_pacchetti>/.fic-lock of EVERY module of maat.json (with or
#     without copia: a counterproof on a module B holds the lock of B's folder, test-fast.sh that of its own), in the
#     order of maat.json, without duplicates, under ONE total deadline FIC_LOCK_WAIT for all the waits; one not taken
#     -> exit 3 «mirror occupato … (lock <path>)», nothing synced, the locks already taken released. Every run
#     closes all the lock descriptors (an orphaned run keeps none).
# - Without rsync or without flock (pk08, for example Git Bash on Windows without WSL; CHANGES THE CONTRACT of pk04b-2, which gave
#   BLOCKED): counterproofs run anyway, with the fic-mirror.sh fallbacks, slower and declared in one line
#   «counterproof: … di ripiego …». Copy: fic_sync (find + sha256 fingerprints + tar, same exclusions, --delete and
#   rsync's content comparison; the manifest check below stays). Lock: atomic mkdir of
#   <lock>.d (fic_lock_dir, same FIC_LOCK_WAIT cap), also for the worker queue of step 2; released by the
#   EXIT trap. The copy of a module with `copia` (preparation, seeding, realignment) stays with test-fast.sh, which
#   needs rsync and flock: without them, «mirror assente» or the failed realignment, with the reason.
# - Under the lock: fingerprint of the dependencies of the module with copia (the one of `test-fast.sh --setup`), then for each
#   module a sync with deletion (exclusions: the core's single list FIC_MIRROR_EXCL of fic-mirror.sh plus the
#   module's `collega_nel_worktree` folders), cleanup of the copy (fic_mirror_pulisci: the folders of the
#   `preparati` and, with the vitest runner, the vite/vitest caches), the read-only folders of `copia_anche`
#   (rsync -a --delete --checksum --exclude=node_modules, outside the manifest), then the manifest (path + sha256 of the
#   tracked and non-ignored untracked files, plus the .env*: the same as test-fast.sh, node_modules excluded)
#   compared between origin and mirror. Stale dependencies -> the copy realigns itself under the lock as in
#   test-fast.sh (fic_deps_autorefresh), line "counterproof: dipendenze cambiate (impronta <vecchia> -> <nuova>):
#   copia riallineata dall'origine", then the fingerprint again. Mirror missing, stale dependencies that cannot be realigned,
#   failed sync or copy not aligned -> exit 3.
# - For each mutation: backup copy of that file ONLY, replacement (unlink + write), run of the named test
#   only, restore (unlink + copy), then the hash of the module in the mirror compared again with the initial manifest. If
#   it does not match -> exit 5 and it stops (a dirty mirror would falsify the following mutations). If the script dies
#   halfway, the EXIT trap restores the in-flight file.
#   1.8.0 (A5): the file is the REAL path, resolved once (a symbolic link inside the module copy is followed; one that
#   leads outside it -> bloccato «collegamento fuori dal modulo», nothing mutated): backup, in-flight record, mutation,
#   restore and the restore of the EXIT trap all work on it, so a link stays a link. The mutation keeps the mode (and,
#   when allowed, the owner) of the file; after the restore the mode of the file and the type of the path (a link to
#   the same target, if it was one) are compared with those of before: different -> exit 5, like the manifest.
# - {python}: $FIC_PYTEST_PY if set (override); otherwise, for an `ambiente: wsl` module, the gates.sh
#   search (moduli[].python, string or list, relative to the root; then piattaforma.python; then python3: the first
#   that exists, here inside WSL) and none -> exit 3 «python WSL assente»; for a native module the reader's
#   precedence (risolvi_python) and no interpreter -> exit 3 «python assente». pytest runs with `-B -p no:cacheprovider`
#   (in the profile command): no .pyc survives the mutation.
#
# STEP 1 and STEP 2
# - Step 1, serial in the mirror under the lock: the modules without copia, the files of the module with copia outside its
#   root (the workspace links in node_modules point to the packages OF THE MIRROR, a private copy would not
#   see them), every runner other than vitest, and everything when N < 2.
# - Step 2, parallel: the vitest mutations on files under the root of the module with copia run on N private copies
#   of the source ONLY ($HOME/fic-cp.XXXXXX/<i>/<radice_pacchetti>, outside the mirror), made from the verified mirror. The
#   mirror lock stays held for the WHOLE step (snapshot, runs, final check of the mirror sources): the
#   copies still read node_modules and packages/ of the mirror, which another writer must not change under the runs.
#   root node_modules = symlink to the mirror's one (read-only); nested node_modules copied without
#   caches. Per copy: FIC_VITE_CACHE_DIR (private cacheDir) and FIC_VITE_FS_ALLOW (root of the copy +
#   node_modules and packages of the mirror: vite 5 does not load files outside server.fs.allow), in the run environment and
#   read by vitest.config.ts ONLY if set. No `cp -al`. The copies are deleted at the end.
#
# SIGNALS
# - TERM, INT (Ctrl-C), HUP: the trap fires at once (runs go in the background and are awaited with `wait`) and,
#   in order, KILLs all descendants — workers, `timeout`, the runner command and its children — and the
#   process groups opened by `timeout` (recorded by pid: they outlive the workers if a Ctrl-C kills those first;
#   1.8.0: each run records its group itself, before it exists, so no run escapes the record), waits at most 5 s
#   for the recorded groups to be empty, restores the in-flight file in the mirror, deletes the private copies
#   $HOME/fic-cp.*; other signals during cleanup
#   are ignored, so that they do not interrupt it halfway. It exits 143;
#   the <id>.json already written stay, those not yet written are missing: the run is not complete.
# - KILL (or the death of WSL) cannot be trapped: what may remain is a mutated file in the mirror (realigned by the
#   sync with --checksum of the next run, of test-fast.sh or of this script: the working tree is not
#   touched), copies $HOME/fic-cp.* (to delete by hand) and orphaned processes (`pkill -f fic-cp`). The lock is released
#   by itself when the last process holding its descriptor open dies: the runs close it. The fallback lock
#   (without flock) stays as a folder <lock>.d with the dead pid: whoever waits recognizes it as orphaned and takes it over.
# - N = min(FIC_CP_PARALLEL [4], MemAvailable / FIC_CP_MEM_MB [1500, measured], nproc/2, mutations of
#   step 2). FIC_CP_PARALLEL=1 forces serial.
#
# Output: one line per mutation, last line
#   "counterproof: esito=<PASS|FAIL|BLOCKED|NOT RUN> prove=<n>/<tot> fail=<n> bloccate=<n> tempo=<s>s luogo=<mirror|copie(N)>".
# Exit: 0 all valid proofs (or none to run) · 1 at least one FAIL · 2 at least one blocked (no FAIL) ·
#       3 environment BLOCKED (tools missing with no fallback — sha256sum, timeout, a Python from python.sh, rsync and tar
#         together: «controprove non disponibili: manca <strumento>» —, {python} interpreter missing, lock beyond the
#         cap, mirror missing,
#         stale dependencies that cannot be realigned, failed sync, copy not aligned, private copy that cannot be created; or
#         mirror changed during step 2): the results of this run are not valid, even if some <id>.json has
#         been written ·
#       5 mirror or private copy not restored (integrity: it stops) ·
#       64 wrong usage: arguments, project root not resolved (PROJECT_ROOT), maat.json not readable,
#          invalid mutations.json.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
# Messages (1.4.0): the catalog next to this script (lib/maat-msg.sh), loaded below once the project is known (the
# language may come from its maat.json); a message before that loads it by itself. The embedded Python (PY) imports
# maat_msg.py from MAAT_MSG_PY. The last line «counterproof: esito=… prove=… luogo=…», the values of <id>.json and the
# JSON keys of mutations.json stay as they are in every language (protocol-strings.list).
. "$HERE/lib/maat-msg.sh"
usage() { echo "$(msg counterproof.usage)" >&2; exit 64; }
[ $# -eq 1 ] || usage
case "$1" in -*) usage ;; esac

# Project root: PROJECT_ROOT from the environment wins (run_cp passes it, also inside WSL); without it, the single
# resolver (FIC_REPO, then git from the working directory). Never $HERE/../..: in the plugin it would be the plugins folder.
_PR=${PROJECT_ROOT:-}
. "$HERE/lib/maat-paths.sh" || { echo "counterproof: $(msg counterproof.paths_failed here="$HERE")" >&2; exit 64; }
[ -n "$_PR" ] && PROJECT_ROOT=$_PR
maat_progetto || { echo "counterproof: $(msg counterproof.no_root)" >&2; exit 64; }
ROOT=$(cd "$PROJECT_ROOT" 2>/dev/null && pwd) || { echo "counterproof: $(msg counterproof.root_access root="$PROJECT_ROOT")" >&2; exit 64; }
export PROJECT_ROOT=$ROOT MAAT_CONFIG_PY="$HERE/maat-config.py"

# Tools (pk08): rsync and flock have a fallback (fic_sync with tar, fic_lock_dir with mkdir: fic-mirror.sh), slower
# and declared; without a fallback -> BLOCKED: sha256sum, timeout, a Python from python.sh, and tar when rsync is missing.
. "$HERE/python.sh" 2>/dev/null || FIC_PY=""
# language resolved once and exported (the embedded Python reads the same one); maat_msg.py in the form the
# interpreter reads (C:/… for a Windows Python, the path as it is inside WSL)
maat_msg_carica; maat_lingua -v MAAT_LINGUA; export MAAT_LINGUA
MAAT_MSG_PY=$(maat_cygm "$HERE/maat_msg.py" 2>/dev/null || printf '%s' "$HERE/maat_msg.py"); export MAAT_MSG_PY
# 1.8.0 (D1-bis): the relation of the test names, the same module as plan-check.sh rossi (NOMI_TEST_PY wins: tests)
[ -n "${NOMI_TEST_PY:-}" ] || NOMI_TEST_PY=$(maat_cygm "$HERE/nomi_test.py" 2>/dev/null || printf '%s' "$HERE/nomi_test.py")
export NOMI_TEST_PY
missing=""
for t in sha256sum timeout; do command -v "$t" >/dev/null 2>&1 || missing+="${missing:+, }$t"; done
command -v rsync >/dev/null 2>&1 || command -v tar >/dev/null 2>&1 || missing+="${missing:+, }$(msg counterproof.rsync_tar)"
[ -n "${FIC_PY:-}" ] || missing+="${missing:+, }python"
if [ -n "$missing" ]; then echo "counterproof: esito=BLOCKED ($(msg counterproof.tools_missing missing="$missing")) luogo=-"; exit 3; fi
FLOCK=1; command -v flock >/dev/null 2>&1 || FLOCK=""
FALLBACK=""
command -v rsync >/dev/null 2>&1 || FALLBACK="$(msg counterproof.fallback_copy)"
[ -n "$FLOCK" ] || FALLBACK+="${FALLBACK:+; }$(msg counterproof.fallback_lock)"

# Destination with the SAME rule as test-fast.sh (fic-mirror.sh): ~/fic-mirror from the main tree,
# ~/fic-mirror-<hash> from a worktree. From a worktree its code is never synced into the copy of the main
# tree. Root that cannot be determined -> BLOCKED (further below).
. "$HERE/fic-mirror.sh" || { echo "counterproof: $(msg counterproof.fic_mirror_missing)" >&2; exit 64; }
if fic_mirror_init "$ROOT"; then MIR=$FIC_MIRROR; else MIR=""; fi
WAIT=${FIC_LOCK_WAIT:-900}
RUN_TIMEOUT=${FIC_CP_TIMEOUT:-1800}

MJ=$1
[ -f "$MJ" ] || { [ -f "$ROOT/$MJ" ] && MJ="$ROOT/$MJ"; }
[ -f "$MJ" ] || { echo "counterproof: $(msg counterproof.mj_missing arg="$1")" >&2; exit 64; }
OUT=$(cd "$(dirname "$MJ")" && pwd)

# Logic on JSON and reports, in Python (no jq in WSL). No single quote in here.
PY='
import importlib.util, json, os, posixpath, re, shutil, stat, sys
import xml.etree.ElementTree as ET
sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
_s = importlib.util.spec_from_file_location("maat_msg", os.environ["MAAT_MSG_PY"])
_m = importlib.util.module_from_spec(_s)
_s.loader.exec_module(_m)
T = _m.T   # the catalog (lib/messages.tsv), the same as the bash side
_s = importlib.util.spec_from_file_location("nomi_test", os.environ["NOMI_TEST_PY"])
NT = importlib.util.module_from_spec(_s)
_s.loader.exec_module(NT)   # 1.8.0 (D1-bis): relazione() of the test names, shared with plan-check.sh rossi

def die(msg):
    print("counterproof: " + msg, file=sys.stderr)
    sys.exit(64)

SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
IMPORT_JS = re.compile(r"Failed to load url|Failed to resolve import|Cannot find module|Cannot find package|does not provide an export named|is not exported by|Failed to parse source|Transform failed|SyntaxError|ERR_MODULE_NOT_FOUND")
IMPORT_PY = re.compile(r"ImportError|ModuleNotFoundError|SyntaxError|IndentationError|cannot import name")

def lettore():
    # maat-config.py imported (MAAT_CONFIG_PY): the same functions as the modulo-di and comando commands
    p = os.environ.get("MAAT_CONFIG_PY") or ""
    try:
        import sys; sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
        spec = importlib.util.spec_from_file_location("maat_config", p)
        mc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mc)
    except Exception as e:
        die(T("counterproof.cfg_loader", p=p, e=e))
    return mc

def rel_ok(p):
    if not isinstance(p, str) or not p or p.startswith("/") or "\\" in p or re.match(r"^[A-Za-z]:", p):
        return False
    return ".." not in p.split("/")

def norm(s):
    return " ".join(ANSI.sub("", s or "").split())

def wtxt(path, s):
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(s)

def rtxt(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()

def wjson_out(out, rec):
    dst = os.path.join(out, rec["id"] + ".json")
    with open(dst + ".tmp", "w", encoding="utf-8") as fh:
        json.dump(rec, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(dst + ".tmp", dst)

def dove(d):
    return T("counterproof.outside_modules") if d is None else "%s (%s)" % d

def cerca_python_wsl(mc, cfg, m, root):
    # the gates.sh search: candidates of the module (root) or piattaforma.python (repo) or python3; the first that exists
    v, base = m.get("python"), mc.norm(m["radice"])
    if not v:
        v, base = cfg.get("piattaforma", {}).get("python") or "python3", ""
    provati = []
    for c in (v if isinstance(v, list) else [v]):
        c = c.replace("\\", "/")
        if "/" not in c:
            provati.append(c)
            if shutil.which(c):
                return c, provati
            continue
        if re.match(r"^[A-Za-z]:/", c):
            p = "/mnt/%s/%s" % (c[0].lower(), c[3:])
        elif c.startswith("/"):
            p = c
        else:
            p = posixpath.join(root, base, mc.norm(c)) if base else posixpath.join(root, mc.norm(c))
        provati.append(p)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p, provati
    return None, provati

def interprete(mc, cfg, m, root):
    o = os.environ.get("FIC_PYTEST_PY")
    if o:
        return o, ""
    if m.get("ambiente") == "wsl":
        p, provati = cerca_python_wsl(mc, cfg, m, root)
        return (p, "") if p else (None, T("counterproof.py_wsl_missing") + " ".join(provati))
    p = mc.risolvi_python(cfg, m, root)
    if p and ("/" not in p or (os.path.isfile(p) and os.access(p, os.X_OK))):
        return p, ""
    return None, T("counterproof.py_missing") + (p or T("counterproof.no_candidate"))

def pattern(s):
    # -t matches the fullName, where vitest joins ancestors and title with a space: a name written the way vitest
    # prints it in FAILs ("describe > it") must be brought back to that form, or no test matches (all skipped)
    return re.sub(r"([\\^$.*+?()\[\]{}|/])", r"\\\1", s.replace(" > ", " "))

def prep(mj, root, tmp, out):
    mc = lettore()
    try:
        cfg, _p = mc.carica()
        r = mc.risolto(cfg)
    except mc.Uscita as u:
        die("maat.json: " + (u.messaggio or T("counterproof.cfg_invalid", code=u.codice)))
    mods = {x["nome"]: x for x in r["moduli"]}
    try:
        with open(mj, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as e:
        die(T("counterproof.mj_unreadable", e=e))
    if not isinstance(data, list) or not data:
        die(T("counterproof.mj_not_list"))
    seen, groups, order, absorbed, notrun = set(), {}, [], [], []
    for i, m in enumerate(data):
        where = T("counterproof.entry", i=i)
        if not isinstance(m, dict):
            die(where + ": " + T("counterproof.not_object"))
        mid = m.get("id")
        if not isinstance(mid, str) or not SAFE_ID.match(mid):
            die(where + ": " + T("counterproof.bad_id"))
        where = "id " + mid
        if mid in seen:
            die(where + ": " + T("counterproof.dup_id"))
        seen.add(mid)
        f, sym, mut, t, rs = m.get("file"), m.get("simbolo"), m.get("mutazione"), m.get("test"), m.get("rosso_se")
        if not rel_ok(f):
            die(where + ": " + T("counterproof.bad_file"))
        if not isinstance(sym, str) or not sym.strip():
            die(where + ": " + T("counterproof.no_symbol"))
        if not isinstance(mut, dict) or not isinstance(mut.get("cerca"), str) or not mut["cerca"] or not isinstance(mut.get("sostituisci"), str):
            die(where + ": " + T("counterproof.bad_mutation"))
        if mut["cerca"] == mut["sostituisci"]:
            die(where + ": " + T("counterproof.empty_mutation"))
        if not isinstance(t, dict) or not rel_ok(t.get("percorso")):
            die(where + ": " + T("counterproof.bad_test_path"))
        nome = t.get("nome") or ""
        if not isinstance(nome, str):
            die(where + ": " + T("counterproof.bad_test_name"))
        if not isinstance(rs, dict) or not all(isinstance(rs.get(k), str) and rs[k].strip() for k in ("test_id", "asserzione")):
            die(where + ": " + T("counterproof.bad_red_if"))
        tp = t["percorso"]
        df, dt = mc.instrada(r, f), mc.instrada(r, tp)
        if df is None or dt is None or df[0] != dt[0] or dt[1] != "radice":
            die(where + ": " + T("counterproof.same_module", file=dove(df), test=dove(dt)))
        mod = mods[df[0]]
        for p in (f, tp):
            if not os.path.isfile(os.path.join(root, p)):
                die(where + ": " + T("counterproof.file_missing_wt") + p)
        ab = m.get("assorbita", False)
        if not isinstance(ab, bool) or not isinstance(m.get("motivo", ""), str):
            die(where + ": " + T("counterproof.bad_absorbed"))
        if ab:  # L2 (harness-pt11): not run, the result is written below
            absorbed.append(m)
            continue
        cp = mod.get("controprova") or {}
        if not cp.get("comando"):   # NOT RUN (declared): never green nor red
            why = T("counterproof.module_no_cp", mod=mod["nome"]) if not cp else T("counterproof.module_no_cmd", mod=mod["nome"])
            notrun.append((m, cp.get("runner"), why))
            continue
        key = json.dumps([f, sym, mut["cerca"], mut["sostituisci"], tp, nome, rs["test_id"], rs["asserzione"]])
        if key not in groups:
            groups[key] = {"entries": [], "runner": cp["runner"], "modulo": mod["nome"]}
            order.append(key)
        groups[key]["entries"].append(m)
    for mid in seen:
        try:
            os.unlink(os.path.join(out, mid + ".json"))
        except FileNotFoundError:
            pass
    vuoto = {"luogo": None, "comando": None, "rc_runner": None, "durata_s": 0.0, "duplicato_di": None,
             "messaggio": "", "output_coda": []}
    for m in absorbed:  # SALTO-ASSORBITE
        rec = dict(m)
        rec.update(vuoto)
        rec.update({"esito": "assorbita", "controprova": "ASSORBITA", "motivo": m.get("motivo") or "L2",
                    "runner": None, "eseguita_per": [m["id"]]})
        wjson_out(out, rec)
    for m, runner, why in notrun:  # NOT-RUN-DICHIARATO
        rec = dict(m)
        rec.update(vuoto)
        rec.update({"esito": "non_eseguita", "controprova": "NOT RUN", "motivo": T("counterproof.not_run_declared") + why,
                    "runner": runner, "eseguita_per": [m["id"]]})
        wjson_out(out, rec)
    usati = [x for x in r["moduli"] if any(groups[k]["modulo"] == x["nome"] for k in order)]
    con_copia = [x["nome"] for x in usati if x.get("copia")]
    if len(con_copia) > 1:
        die(T("counterproof.several_copies", mods=", ".join(con_copia)))
    pys = {}
    for x in usati:
        nm = x["nome"]
        if not SAFE_ID.match(nm):
            die(T("counterproof.bad_module_name", nm=nm))
        rad, pac = mc.norm(x["radice"]), mc.norm(x["radice_pacchetti"])
        if not pac and x.get("copia"):   # 1.8.0 (A4): the root is allowed, only without `copia` (DA3)
            die(T("counterproof.pkg_is_root", nm=nm) + " — " + T("counterproof-180.root_copy_fix"))
        try:
            gruppo = mc.relativa(rad, pac)
        except mc.Uscita as u:
            die(u.messaggio)
        d = os.path.join(tmp, "mod", nm)
        os.makedirs(d)
        cp = x["controprova"]
        wtxt(os.path.join(d, "radice"), rad)
        wtxt(os.path.join(d, "pacchetti"), pac)
        wtxt(os.path.join(d, "gruppo"), gruppo)
        wtxt(os.path.join(d, "copia"), "1" if x.get("copia") else "")
        wtxt(os.path.join(d, "runner"), cp["runner"])
        # extra exclusions of the module: the collega_nel_worktree folders (installed dependencies), relative to the
        # packages root, anchored. 1.8.0 (A4): a module at the root (pac "") is the whole mirror, shared by the other
        # modules: its sync also excludes the copy state and the locks of every folder (.fic-*, NOT anchored), the
        # .git of the repository (the .git file of a worktree points to the real repository), the cycles folder (OUT
        # writes there during the run) and the collega_nel_worktree folders of EVERY module, each anchored to the
        # repository root. Before, "/" + p[len(pac) + 1:] cut the first character when pac == "".
        esc, lav = [], ""
        if not pac:
            lav = mc.norm((r.get("cartelle") or {}).get("lavoro") or "")
            esc += [".fic-*", "/.git"] + (["/" + lav] if lav else [])   # ESCLUSIONI-RADICE
        for x2 in ([x] if pac else r["moduli"]):
            for v in x2.get("collega_nel_worktree", []):
                v = {"percorso": v} if isinstance(v, str) else v
                b = mc.cartella_di(x2, v.get("cartella", "radice"))
                p = mc.norm(posixpath.join(b, v["percorso"]) if b else v["percorso"])
                if p and p != pac and mc.sotto(p, pac):
                    esc.append("/" + (p[len(pac) + 1:] if pac else p))   # COLLEGA-RADICE
        wtxt(os.path.join(d, "escludi"), "".join(e + "\n" for e in esc))
        wtxt(os.path.join(d, "lavoro"), lav)
        wtxt(os.path.join(d, "preparati"), "".join(g + "\n" for g in x.get("preparati", [])))
        anche = [mc.norm(a) for a in x.get("copia_anche", []) if rel_ok(mc.norm(a))]
        wtxt(os.path.join(d, "anche"), "".join(a + "\n" for a in anche))
        miss = ""
        if "{python}" in cp["comando"]:
            pys[nm], miss = interprete(mc, cfg, x, root)
        wtxt(os.path.join(d, "pymiss"), miss)
    for n, key in enumerate(order):
        g = groups[key]
        m = g["entries"][0]
        x = mods[g["modulo"]]
        rad = mc.norm(x["radice"])
        radp = rad + "/" if rad else ""
        d = os.path.join(tmp, "m", "%04d" % n)
        os.makedirs(d)
        with open(os.path.join(d, "entries.json"), "w", encoding="utf-8") as fh:
            json.dump(g["entries"], fh, ensure_ascii=False)
        tp = m["test"]["percorso"]
        trel = tp[len(radp):]
        nome = m["test"].get("nome") or m["rosso_se"]["test_id"]
        runner = g["runner"]
        if runner == "vitest":
            val = {"test": [trel], "nome": pattern(nome)}
        elif runner == "pytest":  # name relative to the file: strip "<radice>/" and "<percorso>::"
            nome = nome[len(radp):] if radp and nome.startswith(radp) else nome
            nome = nome[len(trel) + 2:] if nome.startswith(trel + "::") else nome
            val = {"test": [trel + "::" + nome] if nome else [trel], "nome": nome}
        else:
            val = {"test": [trel], "nome": nome}
        val["python"] = pys.get(g["modulo"])
        val["maat"] = (os.environ.get("MAAT_ROOT") or mc.PLUGIN).replace("\\", "/")
        wtxt(os.path.join(d, "runner"), runner)
        wtxt(os.path.join(d, "modulo"), g["modulo"])
        wtxt(os.path.join(d, "file"), m["file"])
        wtxt(os.path.join(d, "cerca"), m["mutazione"]["cerca"])
        wtxt(os.path.join(d, "sost"), m["mutazione"]["sostituisci"])
        wtxt(os.path.join(d, "tpath"), tp)
        wtxt(os.path.join(d, "trel"), trel)
        wtxt(os.path.join(d, "radp"), radp)
        wtxt(os.path.join(d, "tname"), nome)
        wtxt(os.path.join(d, "python"), val["python"] or "")
        wtxt(os.path.join(d, "tpl"), x["controprova"]["comando"])
        wtxt(os.path.join(d, "separatori"), json.dumps(NT.separatori(trel, x.get("separatori_test"))))
        with open(os.path.join(d, "valori.json"), "w", encoding="utf-8") as fh:
            json.dump(val, fh, ensure_ascii=False)
    # lock: that of the module with copia among the mutations (the same as test-fast.sh); without one, that of the first module with
    # copia in maat.json (the copy shared with test-fast.sh), otherwise that of the first module of the mutations
    lock = ""
    if con_copia:
        lock = mc.norm(mods[con_copia[0]]["radice_pacchetti"])
    elif usati:
        primo = next((x for x in r["moduli"] if x.get("copia") and mc.norm(x["radice_pacchetti"])), None)
        lock = mc.norm((primo or usati[0])["radice_pacchetti"])
    locks = [lock]
    # 1.8.0 (A4): a module at the root syncs the whole mirror with --delete, so it takes the lock of the mirror root
    # AND that of the radice_pacchetti of EVERY module of maat.json (with or without copia: a counterproof on a
    # module B holds the lock of the folder of B), always in the order of maat.json (two root counterproofs cannot
    # deadlock), without duplicates
    if any(not mc.norm(x["radice_pacchetti"]) for x in usati):
        locks = [""]
        for x in r["moduli"]:   # LOCK-TUTTI
            k = mc.norm(x["radice_pacchetti"])
            if k not in locks:
                locks.append(k)
    wtxt(os.path.join(tmp, "locks"), "".join(k + "\n" for k in locks))
    wtxt(os.path.join(tmp, "mods"), "".join(x["nome"] + "\n" for x in usati))
    wtxt(os.path.join(tmp, "copiamod"), con_copia[0] if con_copia else "")
    wtxt(os.path.join(tmp, "lockpkg"), lock)
    print(len(order), len(data) - len(absorbed) - len(notrun), len(absorbed), len(notrun))

def riga(d, report):
    # the runner line: controprova.comando expanded with the values from prep and the report of this run
    mc = lettore()
    with open(os.path.join(d, "valori.json"), encoding="utf-8") as fh:
        val = json.load(fh)
    val["report"] = report
    try:
        print(mc.espandi(rtxt(os.path.join(d, "tpl")), val))
    except mc.NonRisolto as e:
        print(T("counterproof.cmd_not_expandable", err=e), file=sys.stderr)
        sys.exit(3)

def apply(path, cf, sf):
    with open(cf, "rb") as fh:
        cerca = fh.read()
    with open(sf, "rb") as fh:
        sost = fh.read()
    with open(path, "rb") as fh:
        data = fh.read()
    n = data.count(cerca)
    if n == 0 and b"\r\n" in data and b"\n" in cerca:
        c2 = cerca.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        n = data.count(c2)
        if n:
            cerca, sost = c2, sost.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
    if n != 1:
        print(T("counterproof.search_count", n=n))
        sys.exit(2)
    new = data.replace(cerca, sost, 1)
    # 1.8.0 (A5): `path` is the real path (run_one resolves a link). unlink + write as before (a hardlink is split on
    # purpose: never mutate a shared inode), then the mode and, when allowed, the owner of before: an executable
    # script stays executable during the run
    st = os.stat(path)
    os.unlink(path)
    with open(path, "wb") as fh:
        fh.write(new)
    os.chmod(path, stat.S_IMODE(st.st_mode))
    if hasattr(os, "chown"):
        try:
            os.chown(path, st.st_uid, st.st_gid)
        except PermissionError:
            pass

def vitest_mio(a, tid):
    # 1.8.0 (D1-bis): the test is the named one or one of its descendants (a `describe` named by the plan), by the
    # structured chain ancestorTitles + title (nomi_test.relazione): the title, every suffix of the chain joined by
    # " > " as in FAILs or by a space as in the full -t name; never a prefix with a space ("parse" is not the parent
    # of "parse empty"), never by substring
    segs = (a.get("ancestorTitles") or []) + [a.get("title") or ""]
    return tid == a.get("fullName") or NT.relazione(tid, None, NT.SEP_VITEST, segmenti=segs) in ("uguale", "discendente")

def classify_vitest(report, trel, tid, asserz):
    try:
        with open(report, encoding="utf-8") as fh:
            rep = json.load(fh)
    except Exception:
        return "bloccato", T("counterproof.no_json_report"), ""
    files = [r for r in rep.get("testResults", []) if (r.get("name") or "").replace("\\", "/").endswith("/" + trel)]
    if not files:
        return "rosso_raccolta", T("counterproof.not_collected"), ""
    fr = files[0]
    targets = [a for a in fr.get("assertionResults", []) if vitest_mio(a, tid)]
    failed = [a for a in targets if a.get("status") == "failed"]
    if failed:
        msg = norm("\n".join(x for a in failed for x in (a.get("failureMessages") or [])))
        return red(msg, asserz, IMPORT_JS)
    fmsg = norm(fr.get("message") or "")
    if fr.get("status") == "failed" and fmsg:
        return suite_red(fmsg, IMPORT_JS)
    if targets and all(a.get("status") == "passed" for a in targets):
        return "verde", T("counterproof.stays_green"), ""
    return "rosso_raccolta", T("counterproof.not_run_named"), ""

def red(msg, asserz, imp):
    if norm(asserz) in msg:
        return "rosso_asserzione", T("counterproof.red_assert"), msg
    if imp.search(msg):
        return "rosso_import", T("counterproof.red_import"), msg
    return "rosso_diverso", T("counterproof.red_other"), msg

def suite_red(msg, imp):
    if imp.search(msg):  # CLASSIFICAZIONE-IMPORT
        return "rosso_import", T("counterproof.suite_import"), msg
    return "rosso_raccolta", T("counterproof.suite_collect"), msg

def classify_pytest(report, trel, tid, asserz, rc, radp, seps):
    if rc in (4, 5):
        return "rosso_raccolta", T("counterproof.pytest_collect", rc=rc), ""
    try:
        root = ET.parse(report).getroot()
    except Exception:
        return "bloccato", T("counterproof.no_junit_report"), ""
    tid = tid[len(radp):] if radp and tid.startswith(radp) else tid
    mod = trel[:-3].replace("/", ".") if trel.endswith(".py") else trel.replace("/", ".")
    targets, coll, anc = [], [], []
    for c in root.iter("testcase"):
        cn, nm = c.get("classname") or "", c.get("name") or ""
        bad = [e for e in list(c) if e.tag in ("failure", "error")]
        if not cn:
            coll += bad
            continue
        if cn == mod:
            rest = ""
        elif cn.startswith(mod + "."):
            rest = "::" + cn[len(mod) + 1:].replace(".", "::")
        else:
            continue
        nodeid = trel + rest + "::" + nm
        # 1.8.0 (D1-bis): the named test, its parameters ([a]), the methods of a named class, the subtests -> the
        # test; an ancestor (a folding adapter) only without them, and only with the leaf of the name in its text
        rel = "uguale" if nodeid == tid else NT.relazione(tid, nodeid, seps)
        skipped = any(e.tag == "skipped" for e in list(c))
        if rel in ("uguale", "discendente"):
            targets.append((bad, skipped))
        elif rel == "antenato":
            anc.append((bad, skipped))
    if not targets and anc:
        leaf = NT.foglia(tid, seps)
        targets = [(b, s) for b, s in anc if not b or any(leaf and leaf in (e.get("message") or "") + "\n" + (e.text or "") for e in b)]
    failed = [b for b, s in targets if b]
    if failed:
        msg = norm("\n".join((e.get("message") or "") + "\n" + (e.text or "") for b in failed for e in b))
        return red(msg, asserz, IMPORT_PY)
    if coll:
        return suite_red(norm("\n".join((e.get("message") or "") + "\n" + (e.text or "") for e in coll)), IMPORT_PY)
    if targets and not any(s for b, s in targets):
        return "verde", T("counterproof.stays_green"), ""
    return "rosso_raccolta", T("counterproof.not_run_named"), ""

def classify_comando(rc):
    # comando runner: no report, only the exit code counts (weak proof)
    if rc != 0:
        return "rosso_generico", T("counterproof.cmd_red", rc=rc), ""
    return "verde", T("counterproof.cmd_green"), ""

def result(d, out, report, rc, ms, log, cmd, why):
    rc, ms = int(rc), int(ms)
    with open(os.path.join(d, "entries.json"), encoding="utf-8") as fh:
        entries = json.load(fh)
    runner, trel, radp = rtxt(os.path.join(d, "runner")), rtxt(os.path.join(d, "trel")), rtxt(os.path.join(d, "radp"))
    m0 = entries[0]
    tid, asserz = m0["rosso_se"]["test_id"], m0["rosso_se"]["asserzione"]
    if why:
        esito, motivo, msg = "bloccato", why, ""
    elif rc == 124 or rc == 137:
        esito, motivo, msg = "bloccato", T("counterproof.timeout"), ""
    elif runner == "vitest":
        esito, motivo, msg = classify_vitest(report, trel, tid, asserz)
    elif runner == "pytest":
        try:
            seps = json.loads(rtxt(os.path.join(d, "separatori")))
        except (OSError, ValueError):
            seps = NT.separatori(trel)
        esito, motivo, msg = classify_pytest(report, trel, tid, asserz, rc, radp, seps)
    else:
        esito, motivo, msg = classify_comando(rc)
    cp = {"rosso_asserzione": "PASS", "rosso_generico": "PASS", "bloccato": "BLOCKED"}.get(esito, "FAIL")
    try:
        with open(log, encoding="utf-8", errors="replace") as fh:
            tail = [ANSI.sub("", x.rstrip("\n")) for x in fh.readlines()[-60:]]
    except OSError:
        tail = []
    ids = [e["id"] for e in entries]
    for e in entries:
        rec = dict(e)
        rec.update({
            "esito": esito, "controprova": cp, "motivo": motivo, "runner": runner, "luogo": "mirror",
            "comando": cmd, "rc_runner": rc if not why else None, "durata_s": round(ms / 1000.0, 1),
            "duplicato_di": None if e["id"] == ids[0] else ids[0], "eseguita_per": ids,
            "messaggio": msg[:4000], "output_coda": tail,
        })
        wjson_out(out, rec)
    print(cp, esito, len(ids), ",".join(ids), "--", motivo)

cmd = sys.argv[1]
if cmd == "prep":
    prep(*sys.argv[2:6])
elif cmd == "riga":
    riga(*sys.argv[2:4])
elif cmd == "apply":
    apply(*sys.argv[2:5])
elif cmd == "result":
    result(*sys.argv[2:10])
'

TMPD=$(mktemp -d)
# LOCKDS: the fallback locks (mkdir) taken by this process, to release in cleanup; LOCKFDS: the descriptors of the
# flock locks (1.8.0, A4: one per lock, a root module takes several), closed in every run (run_cmd)
CPD=""; LOCKDS=(); LOCKFDS=()
: > "$TMPD/inflight"
# On a signal (TERM, INT, HUP -> normal exit -> EXIT trap), in this order: ALL descendants are killed
# (workers, `timeout`, the runner command: `timeout` opens its own process group, so killing only the jobs
# is not enough), the in-flight file in the mirror is restored, the private copies are deleted. SIGKILL cannot be handled:
# see the header.
descendants() {  # <pid>: all descendants, depth-first
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do echo "$c"; descendants "$c"; done
}
kill_tree() {  # several passes: between one collection and the next a worker may have launched the next run
  local k pids
  for k in 1 2 3 4 5; do
    pids=$(descendants $$)
    [ -n "$pids" ] || return 0
    kill -KILL $pids 2>/dev/null
    sleep 0.2
  done
}
kill_runs() {  # the groups opened by `timeout`: they outlive the workers if those die first (Ctrl-C)
  local p
  [ -f "$TMPD/runpgids" ] || return 0
  while read -r p; do [ -n "$p" ] && kill -KILL -- "-$p" "$p" 2>/dev/null; done < "$TMPD/runpgids"
}
runs_gone() {  # 1.8.0 (C1): up to 5 s for the recorded groups to be empty (kill -0 on the group), killing again
  local p k vivo
  [ -f "$TMPD/runpgids" ] || return 0
  for k in $(seq 1 25); do
    vivo=0
    while read -r p; do [ -n "$p" ] && kill -0 -- "-$p" 2>/dev/null && { vivo=1; break; }; done < "$TMPD/runpgids"
    [ $vivo = 0 ] && return 0
    kill_runs; sleep 0.2
  done
  return 1
}
cleanup() {
  # A second signal during cleanup would interrupt it halfway (copies and processes left behind): from here
  # on signals are ignored.
  CP_FINE=1; trap '' TERM INT HUP
  : > "$TMPD/fine"   # before any read of runpgids: a run recorded after this does not start (run_cmd)
  kill_tree; kill_runs; kill_tree; wait 2>/dev/null
  runs_gone   # ATTESA: no run still alive inside the copy deleted below
  # inflight holds the real path (run_one, 1.8.0): a link mutated through its target stays a link
  if [ -s "$TMPD/inflight" ] && [ -f "$TMPD/bak" ]; then q=$(cat "$TMPD/inflight"); rm -f "$q"; cp -p "$TMPD/bak" "$q"; fi
  [ -n "$CPD" ] && rm -rf "$CPD"
  rm -rf "$TMPD"
  for q in ${LOCKDS[@]+"${LOCKDS[@]}"}; do fic_unlock_dir "$q" "$$"; done   # last: the mirror is already restored
}
# 1.8.0 (C1): the handler exits only once (CP_FINE). Before, a second TERM (two runs that signal at the same moment,
# case 11b) arriving between `exit 143` and the first line of cleanup ran `exit 143` again inside the EXIT trap:
# cleanup cut short, nothing killed, the copies left (seen on 11b: both groups of `timeout` alive and recorded, the
# copy still there; a burst of TERM cut it short 39 times out of 40). A flag, not `trap ''` in the handler: bash
# warns «run_pending_traps: bad value» on a signal pending while its trap becomes ignored.
CP_FINE=""
trap '[ -n "$CP_FINE" ] || { CP_FINE=1; exit 143; }' TERM INT HUP
trap cleanup EXIT

info=$("$FIC_PY" -c "$PY" prep "$MJ" "$ROOT" "$TMPD" "$OUT") || exit 64
read -r NU NT NA NN <<< "${info//$'\r'/}"
echo "counterproof: $(msg counterproof.count nt="$NT" nu="$NU"), luogo=mirror"
ABS=""; [ "${NA:-0}" -gt 0 ] && { ABS=" assorbite=$NA"; echo "counterproof: $(msg counterproof.absorbed na="$NA")"; }
if [ "${NN:-0}" -gt 0 ]; then
  ABS+=" non_eseguite=$NN"
  echo "counterproof: $(msg counterproof.not_run nn="$NN")"
fi
if [ "$NU" -eq 0 ]; then   # nothing to run (absorbed or NOT RUN): no lock, no mirror
  E=PASS; [ "${NN:-0}" -gt 0 ] && E="NOT RUN"
  echo "counterproof: esito=$E prove=0/0 fail=0 bloccate=0 tempo=0s luogo=-$ABS"; exit 0
fi

blocked() { echo "counterproof: esito=BLOCKED ($1) luogo=-"; exit 3; }
[ -n "$MIR" ] || blocked "$(msg counterproof.no_repo_root)"

# The modules of the mutations (maat.json order), from prep: folders, copia, runner, exclusions, preparati, copia_anche
modv() { cat "$TMPD/mod/$1/$2" 2>/dev/null; }
mapfile -t MODS < "$TMPD/mods"
declare -A M_RAD M_PAC M_GRP M_RUN
for m in "${MODS[@]}"; do
  M_RAD[$m]=$(modv "$m" radice); M_PAC[$m]=$(modv "$m" pacchetti); M_GRP[$m]=$(modv "$m" gruppo); M_RUN[$m]=$(modv "$m" runner)
  miss=$(modv "$m" pymiss); [ -z "$miss" ] || blocked "$miss"
done
excl_of() {  # <module> -> EX: the core list + the module's collega_nel_worktree folders
  local x
  EX=("${FIC_MIRROR_EXCL[@]}")
  while IFS= read -r x; do [ -n "$x" ] && EX+=("--exclude=$x"); done < "$TMPD/mod/$1/escludi"
}
CM=$(cat "$TMPD/copiamod")   # the module with copia among those of the mutations ("" if none)
# the locks to take, in order (prep): one, or (1.8.0, A4) with a module at the root the mirror root and every module
mapfile -t LOCKPKGS < "$TMPD/locks"
SRCC=""; DSTC=""
[ -n "$CM" ] && { SRCC="$ROOT/${M_PAC[$CM]}"; DSTC="$MIR/${M_PAC[$CM]}"; }

manifest_list() {  # <source dir>: like test-fast.sh — tracked + non-ignored untracked + .env*
  { git -c safe.directory='*' -C "$1" ls-files -co --exclude-standard -z . | tr '\0' '\n'
    (cd "$1" && find . \( -name node_modules -o -name .nuxt -o -name .output -o -name .venv \) -prune -o -name '.env*' -type f -print | sed 's|^\./||')
  } | LC_ALL=C sort -u
}

hashes() {  # <dir> <list>: "sha  path" for each path in the list; ABSENT if missing
  (cd "$1" && while IFS= read -r f; do
     [ -n "$f" ] || continue
     if [ -f "$f" ]; then printf '%s  %s\n' "$(sha256sum < "$f" | cut -c1-64)" "$f"; else printf 'ABSENT  %s\n' "$f"; fi
   done < "$2")
}

if [ -n "$CM" ]; then
  why=""
  # a worktree's copy on first use: node_modules seeded from the main tree's copy (like test-fast.sh)
  if [ "$MIR" != "$HOME/fic-mirror" ] && ! { [ -d "$DSTC/node_modules" ] && [ -f "$DSTC/.fic-deps" ]; }; then
    why=$(fic_seed_node_modules "$SRCC" "$DSTC") && why="" || why="; $(msg counterproof.seed_failed why="$why")"
  fi
  [ -d "$DSTC/node_modules" ] && [ -f "$DSTC/.fic-deps" ] || blocked "$(msg counterproof.mirror_missing why="$why")"
fi
[ -z "$FALLBACK" ] || echo "counterproof: $(msg counterproof.fallback_slower fallback="$FALLBACK")"
# 1.8.0 (A4): every lock with ONE total deadline FIC_LOCK_WAIT for all the waits together (not FIC_LOCK_WAIT per
# lock), held until the end; one not taken in time -> BLOCKED «mirror occupato» with its path, exit 3, no sync; the
# ones already taken are released (flock: at the exit; mkdir: by cleanup)
WAIT_MS=$(awk -v w="$WAIT" 'BEGIN { printf "%d", w * 1000 }')
T_LOCK=$(date +%s%N)
for pk in "${LOCKPKGS[@]}"; do
  LOCK="$MIR${pk:+/$pk}/.fic-lock"
  mkdir -p "${LOCK%/.fic-lock}" || blocked "$(msg counterproof.mirror_mkdir mir="$MIR" pkg="$pk")"
  RESTO=$(( WAIT_MS - ($(date +%s%N) - T_LOCK) / 1000000 ))   # SCADENZA-UNICA
  [ "$RESTO" -gt 0 ] || RESTO=0
  if [ -n "$FLOCK" ]; then
    exec {fd}>"$LOCK" || blocked "$(msg counterproof.mirror_mkdir mir="$MIR" pkg="$pk")"
    LOCKFDS+=("$fd")
    flock -w "$((RESTO / 1000)).$(printf '%03d' $((RESTO % 1000)))" "$fd" || blocked "$(msg counterproof.busy wait="${WAIT}" lock="$LOCK")"
  else
    fic_lock_dir "$LOCK.d" "$(( (RESTO + 999) / 1000 ))" || blocked "$(msg counterproof.busy_dir wait="${WAIT}" lock="$LOCK")"
    LOCKDS+=("$LOCK.d")
  fi
done
# the descriptors of the locks belong to this process only: closed in every run and worker (1.8.0, A4: all of them,
# not only the first; a run orphaned by a signal, the C1 case, must not keep the locks of the other modules taken)
chiudi_lock() { local f; for f in ${LOCKFDS[@]+"${LOCKFDS[@]}"}; do exec {f}>&-; done; }   # CHIUDI-LOCK

if [ -n "$CM" ] && ! fic_deps_ok "$SRCC" "$DSTC"; then
  # stale dependencies: automatic realignment under the lock (fic-mirror.sh, fic_deps_autorefresh), then the
  # fingerprint again; preparati and caches are cleaned anyway on every run in the sync below
  deps_out=$(fic_deps_autorefresh "$SRCC" "$DSTC") ||
    blocked "$(msg counterproof.deps_failed out="$deps_out")"
  echo "counterproof: $deps_out"
  fic_deps_ok "$SRCC" "$DSTC" || blocked "$(msg counterproof.deps_still)"
fi
for m in "${MODS[@]}"; do
  pk=${M_PAC[$m]}; src="$ROOT${pk:+/$pk}"; dst="$MIR${pk:+/$pk}"   # pk "" (1.8.0, A4): the module at the root
  mkdir -p "$dst" || blocked "$(msg counterproof.mirror_mkdir_dst dst="$dst")"
  excl_of "$m"
  fic_sync --delete --checksum "${EX[@]}" "$src/" "$dst/" || blocked "$(msg counterproof.sync_failed pk="$pk")"
  mapfile -t prepg < "$TMPD/mod/$m/preparati"
  fic_mirror_pulisci "$dst" "${M_GRP[$m]}" "${M_RUN[$m]}" ${prepg[@]+"${prepg[@]}"} || blocked "$(msg counterproof.clean_failed pk="$pk")"
  # copia_anche: read-only folders that the module's tests read (for example a schema), aligned with
  # --delete, outside the manifest. The mutations stay under the module.
  while IFS= read -r a; do
    [ -n "$a" ] && [ -d "$ROOT/$a" ] || continue
    mkdir -p "$MIR/$a" &&
      fic_sync --delete --checksum --exclude=node_modules "$ROOT/$a/" "$MIR/$a/" || blocked "$(msg counterproof.sync_failed pk="$a")"
  done < "$TMPD/mod/$m/anche"
  # 1.8.0 (A4): at the root the cycles folder is out of the manifest too (OUT writes its <id>.json there)
  lav=$(modv "$m" lavoro)
  git -c safe.directory='*' -C "$src" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
    manifest_list "$src" | awk -v p="$lav" 'p == "" || ($0 != p && index($0, p "/") != 1)' > "$TMPD/list.$m" &&
    [ -s "$TMPD/list.$m" ] || blocked "$(msg counterproof.manifest_nc pk="$pk")"
  hashes "$src" "$TMPD/list.$m" > "$TMPD/src0.$m"
  hashes "$dst" "$TMPD/list.$m" > "$TMPD/base.$m"
  if ! cmp -s "$TMPD/src0.$m" "$TMPD/base.$m"; then
    echo "counterproof: $(msg counterproof.diff_origin pk="$pk")"; diff "$TMPD/src0.$m" "$TMPD/base.$m" | head -5
    # at the root the .fic-* names are never copied (copy state and locks of every folder): fail-closed, said
    [ -n "$pk" ] || ! grep -Eq '(^|/)\.fic-' "$TMPD/list.$m" || echo "counterproof: $(msg counterproof-180.root_fic_name)"
    blocked "$(msg counterproof.copy_misaligned pk="${pk:-.}")"
  fi
done

py_ok() {  # <interpreter>: executable (path) or in PATH (name)
  case "$1" in */*) [ -x "$1" ] ;; *) command -v "$1" >/dev/null 2>&1 ;; esac
}

# The runner of ONE mutation: the module's controprova.comando, expanded (line from prep), in the module root inside
# <root>. <mutation dir> <root> <work dir> <cacheDir or ""> <line>. Only in the private copies (cache
# set) and with the vitest runner: private cacheDir and fs.allow = root of the copy + node_modules of the mirror, where
# the symlink resolves, + packages of the mirror, where the node_modules workspace links resolve.
run_cmd() {
  local d=$1 mroot=$2 w=$3 cache=$4 line=$5 mod cwd allow=""
  mod=$(cat "$d/modulo")
  cwd="$mroot${M_RAD[$mod]:+/${M_RAD[$mod]}}"
  if [ -n "$cache" ] && [ "$(cat "$d/runner")" = vitest ]; then allow="$mroot/${M_PAC[$mod]}:$DSTC/node_modules:$DSTC/packages"; fi
  CMD="(cd $cwd && ${allow:+FIC_VITE_CACHE_DIR=$cache FIC_VITE_FS_ALLOW=$allow }$line)"
  # chiudi_lock: the locks belong to the main process only, not to the runs (1.8.0, A4: every lock descriptor, not
  # only fd 9 as before; with a module at the root they are several). `& wait`: a signal to the main process makes
  # the trap fire at once, without waiting for the run to end. The subshell records ITS OWN pid in runpgids, then
  # execs env, which execs `timeout`: the same pid, and `timeout` opens the group with pgid = pid, so the trap kills
  # the whole group. 1.8.0 (C1): recorded BEFORE the run exists. Before, the parent recorded `$!` after the fork: a
  # run that signalled counterproof.sh at once (the TERM reaches the subshell before its `echo`) left its group
  # unrecorded, orphaned of init and out of reach of kill_tree, alive inside the copy being deleted. Then, after its
  # record, the subshell starts the run only if cleanup has not begun ($TMPD/fine, written by cleanup BEFORE it reads
  # runpgids): a subshell orphaned by the death of its worker, and recorded after cleanup's last read, gives up
  # instead of starting a run that nobody would kill.
  (cd "$cwd" || exit 1
   chiudi_lock
   echo "$BASHPID" >> "$TMPD/runpgids"   # REGISTRA
   [ -d "$TMPD" ] && [ ! -e "$TMPD/fine" ] || exit 143   # FINE
   exec env ${allow:+"FIC_VITE_CACHE_DIR=$cache" "FIC_VITE_FS_ALLOW=$allow"} timeout -k 10 "$RUN_TIMEOUT" bash -c "$line") > "$w/log" 2>&1 &
  wait $!
}

restore() { rm -f "$2" && cp -p "$1" "$2"; }   # <backup copy> <file>: unlink + copy (the real path: a link stays a link)

# 1.8.0 (A5): <path> <module copy root> → the real path of <path> (a symbolic link resolved, also one in a parent
# folder), only if it is inside the module copy; exit 1 otherwise (the mutation would land outside the module)
percorso_reale() {
  local r b
  r=$(realpath -- "$1" 2>/dev/null) && b=$(realpath -- "$2" 2>/dev/null) || return 1
  case "$r" in "$b"/*) printf '%s' "$r" ;; *) return 1 ;; esac
}
# <real path> <path of the mutation> → «<mode> link:<target>» or «<mode> file»: compared before and after the restore
modo_tipo() {
  local t=file
  [ -L "$2" ] && t="link:$(readlink -- "$2")"
  printf '%s %s' "$(stat -c %a -- "$1" 2>/dev/null)" "$t"
}

# ONE mutation in a root that mirrors the repo: the mirror (step 1) or a private copy (step 2).
# <mutation dir> <root> <work dir> [vite cacheDir]. Writes <id>.json, appends the result line to
# <work dir>/results. Returns 5 if after the restore the root is not identical to the initial manifest.
run_one() {
  local d=$1 mroot=$2 w=$3 cache=${4:-}
  local f mod py rep line mf why rc t0 ms out cp esito ids mt0 mt1
  f=$(cat "$d/file"); mod=$(cat "$d/modulo"); py=$(cat "$d/python")
  mf="$mroot/$f"   # 1.8.0 (A5): becomes the real path below, used by backup, inflight, apply and restore
  rm -f "$w/report" "$w/bak"; : > "$w/log"
  why=""; rc=0; CMD=""; t0=$(date +%s%N)
  # a Windows interpreter (.exe, launched from WSL) writes the report with a Windows path
  rep="$w/report"
  case "$py" in *.exe) command -v wslpath >/dev/null 2>&1 && rep=$(wslpath -w "$w/report") ;; esac
  if [ -n "$py" ] && ! py_ok "$py"; then
    why="$(msg counterproof.py_missing_run py="$py")"
  elif ! line=$("$FIC_PY" -c "$PY" riga "$d" "$rep" 2>"$w/log"); then
    why="$(msg counterproof.cmd_not_expandable err="$(head -1 "$w/log")")"
  elif line=${line%$'\r'}; [ ! -f "$mf" ]; then
    why="$(msg counterproof.file_missing_mirror f="$f")"
  elif ! mf=$(percorso_reale "$mroot/$f" "$mroot/${M_PAC[$mod]}"); then
    why="$(msg counterproof-180.link_outside f="$f" real="$(realpath -- "$mroot/$f" 2>/dev/null)" root="${M_PAC[$mod]}")"
  elif mt0=$(modo_tipo "$mf" "$mroot/$f"); ! cp -p "$mf" "$w/bak"; then
    why="$(msg counterproof.backup_failed f="$f")"
  else
    printf '%s' "$mf" > "$w/inflight"   # recorded BEFORE writing: the trap knows what to restore
    if out=$("$FIC_PY" -c "$PY" apply "$mf" "$d/cerca" "$d/sost" 2>&1); then
      run_cmd "$d" "$mroot" "$w" "$cache" "$line"
      rc=$?
    else
      why=${out:-$(msg counterproof.not_applicable)}
    fi
    restore "$w/bak" "$mf"   # RESTORE
    : > "$w/inflight"
    hashes "$mroot/${M_PAC[$mod]}" "$TMPD/list.$mod" > "$w/now.$mod"
    if ! cmp -s "$TMPD/base.$mod" "$w/now.$mod"; then
      echo "counterproof: $(msg counterproof.not_restored mroot="$mroot" mut="$(basename "$d")" f="$f")"; diff "$TMPD/base.$mod" "$w/now.$mod" | head -5
      return 5
    fi
    # 1.8.0 (A5): the manifest sees only the content; the mode of the file and the type of the path (still a link to
    # the same target, if it was one) too, otherwise exit 5 like the integrity
    mt1=$(modo_tipo "$mf" "$mroot/$f")
    if [ "$mt1" != "$mt0" ]; then
      echo "counterproof: $(msg counterproof.not_restored mroot="$mroot" mut="$(basename "$d")" f="$f")"
      echo "  $(msg counterproof-180.mode_changed before="$mt0" after="$mt1")"
      return 5
    fi
  fi
  ms=$(( ($(date +%s%N) - t0) / 1000000 ))
  line=$("$FIC_PY" -c "$PY" result "$d" "$OUT" "$w/report" "$rc" "$ms" "$w/log" "$CMD" "$why") ||
    { echo "counterproof: $(msg counterproof.result_unwritable out="$OUT")" >&2; return 64; }
  printf '%s\n' "$line" >> "$w/results"
  read -r cp esito _ ids _ <<< "$line"
  echo "counterproof: $ids -> $esito ($cp, $((ms / 1000)) s)${line#*--}"
}

# ── Step 2: which mutations go in parallel, and on how many copies ─────────────────────────────────
# Only vitest on files under the root of the module with copia: the workspace links in node_modules point to the
# packages OF THE MIRROR, so a mutation outside the root made in a private copy would be invisible
# (false «green»): those, the other modules and the other runners stay serial in the mirror. For the same reason
# (the copies read the mirror packages) the mirror lock stays held for the whole of step 2.
# N = min(FIC_CP_PARALLEL [4], MemAvailable / FIC_CP_MEM_MB, nproc/2, parallelizable mutations); N < 2 =>
# everything serial. FIC_CP_MEM_MB: memory of ONE vitest run. Measured on 2026-09-29 on MemAvailable during the
# runs (goals-utils + goals-page): ~1.1 GB peak for a run alone, ~3.3 GB for 4 in parallel. The default
# 1500 covers the single-run peak with margin: with ~11 GB free the cap stays that of FIC_CP_PARALLEL.
MEM_MB=${FIC_CP_MEM_MB:-1500}
N=${FIC_CP_PARALLEL:-4}
case "$N$MEM_MB" in *[!0-9]*) echo "counterproof: $(msg counterproof.not_integer)" >&2; exit 64 ;; esac
[ "$MEM_MB" -gt 0 ] || MEM_MB=1
SER=(); PAR=()
for d in "$TMPD"/m/*; do
  par=0
  if [ -n "$CM" ] && [ "$(cat "$d/runner")" = vitest ] && [ "$(cat "$d/modulo")" = "$CM" ]; then
    f=$(cat "$d/file"); r=${M_RAD[$CM]}
    [ -z "$r" ] || [ "${f#"$r"/}" != "$f" ] && par=1
  fi
  if [ $par = 1 ]; then PAR+=("$d"); else SER+=("$d"); fi
done
AVAIL=$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo 2>/dev/null)
# macOS (1.6.0): no /proc/meminfo; the nearest to MemAvailable is free + inactive + speculative pages of vm_stat
if [ -z "$AVAIL" ] && command -v vm_stat >/dev/null 2>&1; then
  AVAIL=$(vm_stat 2>/dev/null | awk '/page size of/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) ps = $i }
    /^Pages (free|inactive|speculative):/ { v = $NF; sub(/\.$/, "", v); n += v }
    END { if (ps > 0) print int(n * ps / 1048576) }')
fi
NMEM=$(( ${AVAIL:-0} / MEM_MB )); NCPU=$(( $(nproc) / 2 ))
[ "$NMEM" -lt "$N" ] && N=$NMEM
[ "$NCPU" -lt "$N" ] && N=$NCPU
[ "${#PAR[@]}" -lt "$N" ] && N=${#PAR[@]}
if [ "$N" -lt 2 ]; then SER+=(${PAR[@]+"${PAR[@]}"}); PAR=(); fi

q_pop() { k=$(cat "$TMPD/q.next"); echo $((k + 1)) > "$TMPD/q.next"; sed -n "$((k + 1))p" "$TMPD/q.all"; }
next_job() {  # dynamic queue shared by the workers: the next mutation, or nothing. Without flock: mkdir, without a cap
  if [ -n "$FLOCK" ]; then
    ( flock 8; q_pop ) 8>"$TMPD/q.lock"
  else
    ( fic_lock_dir "$TMPD/q.lock.d" || exit 1; trap 'fic_unlock_dir "$TMPD/q.lock.d"' EXIT; q_pop )
  fi
}

T_ALL=$(date +%s%N)
: > "$TMPD/results"
# Step 1: serial in the mirror, under the lock.
for d in ${SER[@]+"${SER[@]}"}; do
  run_one "$d" "$MIR" "$TMPD"; r=$?
  if [ "$r" -eq 5 ]; then
    echo "counterproof: esito=BLOCKED ($(msg counterproof.integrity_mirror)) luogo=mirror"; exit 5
  fi
  [ "$r" -eq 0 ] || exit "$r"
done

# Step 2: N private copies of the source ONLY of the module with copia, made from the verified mirror; the runs happen in the
# copies, outside the mirror. The mirror lock stays held for the WHOLE step (snapshot, runs, final check): the
# copies still read the mirror — root node_modules is a symlink to its own (read-only), and the workspace links
# in there lead to ITS packages — so another test-fast.sh or counterproof.sh syncing it
# would change the code under the runs. Nested node_modules (small, with the vite/jiti caches) are copied
# without caches; private vite/vitest cacheDir per copy (FIC_VITE_CACHE_DIR, read by vitest.config.ts).
# No `cp -al`: a hard link would share the inode, and mutating one copy would touch the others.
INTEG=0; DEPS_CHANGED=0; LUOGO=mirror
if [ ${#PAR[@]} -gt 0 ]; then
  DEPS0=$(cat "$DSTC/.fic-deps")
  CPD=$(mktemp -d "$HOME/fic-cp.XXXXXX") || blocked "$(msg counterproof.private_mkdir home="$HOME")"
  excl_of "$CM"
  # The nested node_modules OUTSIDE the copy's exclusions only (1.6.1): one under .output/.nuxt/coverage… (a build
  # left in the mirror) has no parent in the copy and the second sync would fail. Same list as the copy, read with
  # rsync semantics by fic__escludi, so the two cannot drift — minus every entry that IS a node_modules (the core's
  # `node_modules` and the module's collega_nel_worktree ones such as /apps/*/node_modules): those are what this step
  # copies back. Limit: in find a * also matches /, so a wildcard entry may prune one level deeper than rsync would.
  ex_nm=(); for x in "${EX[@]}"; do x=${x#--exclude=}; x=${x%/}; [ "${x##*/}" = node_modules ] || ex_nm+=("$x"); done
  fic__escludi ${ex_nm[@]+"${ex_nm[@]}"}
  NESTED=$(cd "$DSTC" && find . -path ./node_modules -prune -o \( "${FIC__FX[@]}" \) -prune -o -name node_modules -type d -prune -print | sed 's|^\./||')
  for i in $(seq 1 "$N"); do
    c="$CPD/$i/${M_PAC[$CM]}"; mkdir -p "$c"
    fic_sync "${EX[@]}" "$DSTC/" "$c/" || blocked "$(msg counterproof.private_failed i="$i")"
    while IFS= read -r nm; do
      [ -n "$nm" ] || continue
      fic_sync --exclude=.cache --exclude=.vite --exclude=.vitest "$DSTC/$nm/" "$c/$nm/" || blocked "$(msg counterproof.private_nested i="$i" nm="$nm")"
    done <<< "$NESTED"
    ln -s "$DSTC/node_modules" "$c/node_modules" || blocked "$(msg counterproof.private_link i="$i")"
    hashes "$c" "$TMPD/list.$CM" > "$TMPD/copy.$i"
    cmp -s "$TMPD/base.$CM" "$TMPD/copy.$i" || blocked "$(msg counterproof.private_differs i="$i")"
  done
  LUOGO="copie($N)"
  echo "counterproof: $(msg counterproof.step2 par="${#PAR[@]}" n="$N" avail="${AVAIL}" mem="${MEM_MB}")"
  printf '%s\n' "${PAR[@]}" > "$TMPD/q.all"; echo 0 > "$TMPD/q.next"
  PIDS=()
  for i in $(seq 1 "$N"); do
    ( chiudi_lock; w="$TMPD/w$i"; mkdir -p "$w"; : > "$w/results"; : > "$w/inflight"
      while d=$(next_job) && [ -n "$d" ]; do run_one "$d" "$CPD/$i" "$w" "$CPD/$i/.fic-vite-cache" || exit $?; done ) &
    PIDS+=($!)
  done
  for p in "${PIDS[@]}"; do wait "$p" || INTEG=1; done
  # Final check, still under the lock: the mirror sources (read by the copies through the workspace) are those
  # of the snapshot. `test-fast.sh --setup` does not take the lock: if it changed node_modules, this is reported.
  hashes "$DSTC" "$TMPD/list.$CM" > "$TMPD/final.$CM"
  cmp -s "$TMPD/base.$CM" "$TMPD/final.$CM" || DEPS_CHANGED=1
  [ "$(cat "$DSTC/.fic-deps" 2>/dev/null)" = "$DEPS0" ] || DEPS_CHANGED=1
fi
TOT_S=$(( ($(date +%s%N) - T_ALL) / 1000000000 ))

NPASS=0; NFAIL=0; NBLOCK=0
while read -r cp _ n _; do
  [ -n "${cp:-}" ] || continue
  case "$cp" in PASS) NPASS=$((NPASS + n)) ;; FAIL) NFAIL=$((NFAIL + n)) ;; *) NBLOCK=$((NBLOCK + n)) ;; esac
done < <(cat "$TMPD/results" "$TMPD"/w*/results 2>/dev/null)

# The working tree was never written from here: if it changed, someone else changed it during the
# counterproofs, and the results apply to the state synced at the start. Declared, not hidden.
for m in "${MODS[@]}"; do
  hashes "$ROOT/${M_PAC[$m]}" "$TMPD/list.$m" > "$TMPD/src1.$m"
  cmp -s "$TMPD/src0.$m" "$TMPD/src1.$m" ||
    echo "counterproof: $(msg counterproof.wt_changed pkg="${M_PAC[$m]}")"
done

SUM="prove=$NPASS/$NT fail=$NFAIL bloccate=$NBLOCK tempo=${TOT_S}s luogo=$LUOGO$ABS"
if [ "$INTEG" -ne 0 ]; then
  echo "counterproof: esito=BLOCKED ($(msg counterproof.integrity_private)) $SUM"; exit 5
fi
if [ "$DEPS_CHANGED" -ne 0 ]; then
  echo "counterproof: esito=BLOCKED ($(msg counterproof.mirror_changed)) $SUM"; exit 3
fi
if [ "$NFAIL" -gt 0 ]; then E=FAIL; RC=1
elif [ "$NBLOCK" -gt 0 ]; then E=BLOCKED; RC=2
else E=PASS; RC=0
fi
echo "counterproof: esito=$E $SUM"
exit $RC
