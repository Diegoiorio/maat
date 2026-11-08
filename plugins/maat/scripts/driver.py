#!/usr/bin/env python3
"""driver.py — deterministic orchestrator of /full-implementation-cycle (harness-pt14, block 1).

    driver.py next <spec.md>                   the resume table, the answer of cycle-state.sh (State/Next)
    driver.py run <spec.md> [--max-fasi N] [--dry-run] [-- <flags forwarded to the phases>…]
                                               the state machine: next -> phase -> next … until DONE/STOP/WAIT
    driver.py valida <log.jsonl> <schema> <fase> <result.json>
                                               the structured outcome of a phase (run-phase.sh calls it)
    driver.py impronta <folder|spec.md>…       the fingerprint of a corpus (64 hex digits: tools/esempi-equiv/); up to
                                               1.5.1 `equiv --impronta`. `equiv` and `certificato` (the proof against
                                               the bash engine) are gone in 1.6.0: the proof is the expected outputs
                                               of the public corpus, tools/esempi-equiv/attese/
    driver.py righe [<cap>]                    instruction lines loaded per phase; exit 1 if the BASE load of one
                                               exceeds the cap (default 300); separately, with no cap, the conditional files,
                                               the load with plan writing (autore.md) and that of the sub-agents

CHAINS in `run`: a WAIT naming a ring makes the driver go on with that spec; the DONE of a ring brings it
back to the mother (which names the next ring or the closing). Same budget, same anti-loop; a hand-over
already made with no launches in between is not repeated.

BATCHES AND LANES (step 5). Before a format-2 implement the driver regenerates the procedure from the plan, groups
the blocks into BATCHES with the implementer's estimated context below FIC_LOTTO_MAX ("LOTTI (driver): …" line in the
prompt, log/<label>.lotti) and decides the lanes with blocks-independent.py (log/<label>.corsie-driver, passed to
run-phase.sh in FIC_CORSIE; run-phase.sh launches the lanes with its own launch_lanes). Format 1: nothing, as before.

THE SIZE OF THE CYCLE (1.7.0). `run` keeps <run-dir>/taglia.txt (piccola | piena, append-only; «size of the cycle»
below): avvio at the first launch of a new cycle, T2 on the approved plan with `plan-check.sh taglia` (a plan
approved in the light branch whose facts are above the small size: E2, the plan phase again with --full and the
reopening), T3 with `taglia --diff` after every implement/fix (E3: a file outside the plan or a fact above), the
gates and the review after every review (E4, E5). Small size: one lane, no FIX without an escalation (STOP), the
review prompt says so. Absent taglia.txt = the flow of 1.6, identical (FIC_TAGLIA=off to the phases, flags unchanged).
--full and --light together: usage, exit 2. What a phase writes cannot keep the small size: taglia.txt is compared by
sha256 around every phase (E0), a full size needs the full reviewer in a plan log (else E2), only APPROVED passes E5.

L2 PROMOTION (harness-pt15). Before every review the driver re-checks the "assorbita" counterproofs of
counterproof/mutations.json with `plan-check.sh l2` (the same check as finalize.sh, on the final code): those
that finalize would reject lose "assorbita" and are really executed (promuovi_l2).

REUSE, NOT REIMPLEMENTATION. The driver sits ON TOP of run-phase.sh: every phase starts with
`run-phase.sh <run-dir> <label> <prompt>`, which remains the only one handling locks (code and per spec), guard, Stop hook,
harness fingerprint, attribution, gates.sh, review ∥ VERIFY, counterproof.sh, finalize.sh, chains, test-red and
lanes. The driver adds what used to be prose for the LLM orchestrator (SKILL.md, «Orchestrator mode» and «Resumption»):
context-pack.sh before every phase, label numbering, phase prompt, reading the outcome, run-phase exits
as STOP, NEEDS_VERIFICATION in the same invocation -> STOP, anti-loop, phase budget.
Two parts used to be bash and are Python (1.5.0, the only engine since 1.6.0):
  - `next`   = the cycle-state.sh table (rows 0-14, 7t/7s/11s/11b/13f, chains C1-C4), which calls the same
               scripts (plan-check.sh contract/basis/closed, review-surface.sh tree/check, run-phase.sh --harness-fp-confronta);
  - `valida` = the outcome validator of run-phase.sh (phase-result schema, prose and JSON: the most conservative).

WRAPPERS (1.6.0). The driver is the only engine: cycle-state.sh calls `next`, run-phase.sh calls `valida`, `run` uses
its own `next` (FIC_CYCLE_STATE replaces it with a script, in tests). The bash code of 1.5.1 (the table of
cycle-state.sh, the internal validator of run-phase.sh) is gone: FIC_DRIVER no longer has any effect, and `run` says so
with one AVVISO when it is set (the wrappers are silent); for the bash engine, reinstall Maat 1.5.1. No fallback on
error: a driver that fails gives a STOP with the reason.
PYTHON 3.10 OR NEWER: `run` checks sys.version_info against PY_MIN first (Driver result: STOP, exit 1); the wrappers
check it through python.sh (fic_py_min_ok). So that the check is always reached, this file uses NO SYNTAX NEWER THAN
PYTHON 3.7 (no walrus, no match, no `X | Y` types, no str.removeprefix): an older interpreter must reach the STOP, not a
SyntaxError.

EXITS of `run`: 0 DONE · 1 STOP · 2 usage · 3 WAIT (chain) · 4 phase running (RUNNING) or lock occupato (BUSY).
The end line is "Driver result: <DONE|STOP|WAIT|BUSY|RUNNING|DRY-RUN> — …" (1.3.0; up to 1.2.x "Esito driver:", with
OCCUPATO and IN CORSO). The phase result lines are read in both languages (PHASE RESULT / ESITO FASE).
Events: "driver: …" lines on stdout and in <run-dir>/driver.log.

MESSAGES (1.4.0): the text for a person comes from the catalog lib/messages.tsv (maat_msg.T), with the keys that
cycle-state.sh and the validator of run-phase.sh had: English by default, Italian with "lingua": "it" or MAAT_LINGUA=it.
The language is resolved once at the start and exported. The protocol stays as it is in both languages: the first
word of Next, "STOP — catena", "Catena:", "Chiusura:", the harness fingerprint tokens, chain_state and every line
that enters State.

Variables: FIC_BASH (bash to use) · FIC_CYCLE_STATE (a script instead of our own `next` in `run`, tests) ·
FIC_RUN_PHASE (run-phase.sh instead of the real one, tests) · FIC_CONTEXT_PACK (context-pack.sh; "-" = skipped) · FIC_MAX_FASI (default budget, 12) ·
FIC_DRIVER_ROOT (harness root instead of MAAT_ROOT: a mutated copy of the plugin, test counterproofs).
Test: driver.test.sh.
"""
import datetime
import fnmatch
import hashlib
import json
import os
import posixpath
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT (pk04a-1)
sys.path.insert(0, HERE)
import maat_paths  # noqa: E402
import maat_msg  # noqa: E402,F401   (1.4.0: the message catalog next to this file, as lib/maat-msg.sh)
from maat_msg import T  # noqa: E402

# ROOT = root of the HARNESS (MAAT_ROOT; FIC_DRIVER_ROOT replaces it: a mutated copy of the plugin, test
# counterproofs). The PROJECT does not go through here: it is the git toplevel of the spec's folder (run, `entra`).
try:
    ROOT = os.environ.get("FIC_DRIVER_ROOT") or maat_paths.maat_root()
except maat_paths.ErroreMaat as _e:
    sys.stderr.write("driver: %s\n" % _e)
    sys.exit(2)
HERE = os.path.join(ROOT, "scripts")   # a mutated copy (test counterproofs) uses its own scripts
FC = os.path.join(ROOT, "skills", "full-implementation-cycle")   # skill texts: child-rules.md, SKILL.md, workers/
PC = os.path.join(HERE, "plan-check.sh")
RS = os.path.join(HERE, "review-surface.sh")
CS = os.path.join(HERE, "cycle-state.sh")
RP = os.path.join(HERE, "run-phase.sh")
CPK = os.path.join(HERE, "context-pack.sh")
SCHEMA = os.path.join(ROOT, "schemas", "phase-result.schema.json")
# PURELY DEFENSIVE deviation (no effect on the cases the plan foresees): its string in "deviazioni" starts
# like this. If all of them do, the phase does not stop for deviation (run-phase.sh records them, the review judges them).
# Maat 1.3.0: the English prefix "defensive: " is accepted next to the Italian one (a tuple: str.startswith).
DIFENSIVA = ("difensiva: ", "defensive: ")
# "nothing" value of bloccato_su: "nessuno" or, since 1.3.0, "none" (compared lowercase)
NESSUNO = ("nessuno", "none")
# The result line of a phase: "PHASE RESULT <phase>: OK|STOP — …" is written since 1.3.0, "ESITO FASE …" (old run
# dirs, prompts of 1.2.x) is still read. RIGA_OK / RIGA_STOP: the same prefix regexes as run-phase.sh.
ESITO_PREF = ("PHASE RESULT", "ESITO FASE")
RIGA_OK = r"(?:PHASE RESULT|ESITO FASE) [^:]*: OK"
RIGA_STOP = r"(?:PHASE RESULT|ESITO FASE) [^:]*: STOP"
# Review section heading, both languages
REVIEW_H = ("## Review implementazione", "## Implementation review")
# The minimum Python of Maat (1.5.1), checked first by `run`; the same 3.10 as python.sh (fic_py_min_ok, which
# maat-doctor.sh also uses since 1.6.0): driver.test.sh checks that the two agree
PY_MIN = (3, 10)


# ─────────────────────────────────────────────────────────────── utilities
def _dec(b):
    return b.decode("utf-8", "surrogateescape")


def _enc(s):
    return s.encode("utf-8", "surrogateescape")


def _read(p):
    try:
        with open(p, "rb") as fh:
            return _dec(fh.read())
    except OSError:
        return None


def _fw(p):
    return p.replace("\\", "/")


def _bash():
    b = os.environ.get("FIC_BASH")
    if b:
        return b
    if os.name == "nt":   # never WSL's bash.exe (System32) nor the Store stub
        for c in (shutil.which("bash"), os.environ.get("SHELL"), r"C:\Program Files\Git\usr\bin\bash.exe",
                  r"C:\Program Files\Git\bin\bash.exe"):
            if c and os.path.isfile(c) and "system32" not in c.lower() and "windowsapps" not in c.lower():
                return c
    return shutil.which("bash") or "bash"


BASH = _bash()


def _run(args, cwd=None, merge=False, env=None):
    """(code, decoded stdout); stderr discarded (or merged into stdout with merge)."""
    try:
        p = subprocess.run(args, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT if merge else subprocess.DEVNULL, env=env)
    except OSError:
        return 127, ""
    return p.returncode, _dec(p.stdout)


def _subst(s):
    """Like bash $(…): strips only the trailing empty lines."""
    return s.rstrip("\n")


_SHOWN = {}


def shown(p):
    """The path as `cd … && pwd` prints it in Git Bash (cycle-state.sh messages contain it)."""
    if os.name != "nt":
        return p
    if p not in _SHOWN:
        rc, o = _run(["cygpath", "-u", p])
        _SHOWN[p] = _subst(o) if rc == 0 and o.strip() else _fw(p)
    return _SHOWN[p]


_MOSTRATI = {}


def mostra(p):
    """The absolute path of a harness script in messages, like `cygpath -m` in Git Bash: C:/… on Windows
    (cycle-state.sh messages contain it in the same form, pk04a-1)."""
    if os.name != "nt":
        return p
    if p not in _MOSTRATI:
        rc, o = _run(["cygpath", "-m", p])
        _MOSTRATI[p] = _subst(o) if rc == 0 and o.strip() else _fw(p)
    return _MOSTRATI[p]


def _records(t):
    """awk/sed records: lines without the terminator, the last one also without a newline."""
    if not t:
        return []
    r = t.split("\n")
    if t.endswith("\n"):
        r.pop()
    return r


def _names(run_fs):
    """`ls <run>/log`: the non-hidden names."""
    try:
        return [n for n in os.listdir(os.path.join(run_fs, "log")) if not n.startswith(".")]
    except OSError:
        return []


def _numkey(l):
    m = re.match(r"[0-9]+", l)
    return (int(m.group()) if m else 0, l)


def _first_line(p):
    t = _read(p)
    return "" if t is None else t.replace("\r", "").split("\n")[0]


def _epoch(ts):
    try:
        return int(datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=datetime.timezone.utc).timestamp())
    except ValueError:
        return None


def _mtime(p):
    try:
        return int(os.stat(p).st_mtime)
    except OSError:
        return None


def _utc(sec):
    return datetime.datetime.fromtimestamp(sec, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


FENCE = re.compile(r"^[ \t]*(```|~~~)")


def _review_lines(txt):
    """The lines of the "## Review implementazione" (or "## Implementation review") section downwards, outside the
    fences (CRs removed)."""
    res, inf, r = [], False, False
    for l in _records(txt.replace("\r", "")):
        if FENCE.match(l):
            inf = not inf
            continue
        if inf:
            continue
        if not r and l.startswith(REVIEW_H):
            r = True
        if r:
            res.append(l)
    return res


def _chead(path, *lits):
    """The value of the first "<lit> …" line above the plan, outside the fences; with several literals the first
    line that has any of them wins (Figlie:/Children:, 1.3.0)."""
    t = _read(path)
    if t is None:
        return ""
    inf = False
    for l in _records(t.replace("\r", "")):
        if FENCE.match(l):
            inf = not inf
            continue
        if inf:
            continue
        if re.match(r"## (Piano di implementazione|Review implementazione|Implementation plan|Implementation review)", l):
            return ""
        for lit in lits:
            if l.startswith(lit):
                return l[len(lit):].strip(" \t")
    return ""


def _cfiglie(path):
    res = []
    for s in re.findall(r"spec-[A-Za-z0-9._-]*", _chead(path, "Figlie:", "Children:")):
        s = re.sub(r"\.md$", "", s)
        res.append(re.sub(r"\.$", "", s))
    return res


def _cpost(rd):
    """The tree of the last .post-tree (highest-numbered label) of the run dir."""
    labs = [m.group(1) for n in _names(rd) for m in [re.match(r"^([0-9]+-[^.]*)\.post-tree$", n)] if m]
    if not labs:
        return ""
    t = _read(os.path.join(rd, "log", sorted(labs, key=_numkey)[-1] + ".post-tree"))
    return re.sub(r"[\r\n ]", "", t or "")


def _labels(run_fs, sub):
    rx = re.compile(r"^([0-9]+-[^.]*)\.(jsonl|esito)$")
    return sorted({m.group(1) for n in _names(run_fs) for m in [rx.match(n)] if m and re.search(sub, m.group(1))},
                  key=_numkey)


def _snap_fp(v):
    s = re.sub(r"[ \t]+", " ", v)
    if s.startswith(" "):
        s = s[1:]
    if s.endswith(" "):
        s = s[:-1]
    return hashlib.sha256(_enc(s.replace("\n", ""))).hexdigest()[:12]


def _json_rule(p):
    """The cycle-state.sh rule in code on result.json: "OK|…" or "STOP|…"; "" if unreadable."""
    try:
        d = json.load(open(p, encoding="utf-8"))
        one = lambda s: " ".join(str(s).split())[:300]
        dev = [one(x) for x in (d.get("deviazioni") or []) if str(x).strip()]
        bs = one(d.get("bloccato_su") if d.get("bloccato_su") is not None else "(assente)")
        if [x for x in dev if not x.startswith(DIFENSIVA)]:
            s = "STOP|" + T("cycle-state.json_dev", n=len(dev), devs=one("; ".join(dev)))
        elif bs.lower() not in NESSUNO:
            s = "STOP|" + T("cycle-state.json_blocked") + bs
        elif d.get("esito") != "OK":
            s = "STOP|" + T("cycle-state.json_esito", esito=d.get("esito"), motivo=one(d.get("motivo") or ""))
        else:
            s = "OK|" + one(d.get("motivo") or "")
        s.encode("utf-8")
    except Exception:
        return ""
    return _subst(s.replace("\r", ""))


class _Next(Exception):
    def __init__(self, msg):
        Exception.__init__(self, msg)
        self.msg = msg


# ─────────────────────────────────────────────────────────────── next (cycle-state.sh table)
def cycle_state(spec_arg):
    """The lines cycle-state.sh <spec> prints, the last one is "Next: …". Same table, same scripts."""
    spec_fs = os.path.abspath(spec_arg)
    tmp = tempfile.mkdtemp(prefix="fic-driver-")
    try:
        return _cycle_state(spec_fs, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _cycle_state(spec_fs, tmp):
    SPEC = shown(spec_fs)
    RUN = (SPEC[:-3] if SPEC.endswith(".md") else SPEC) + ".run"
    run_fs = (spec_fs[:-3] if spec_fs.endswith(".md") else spec_fs) + ".run"
    cwd = os.path.dirname(spec_fs)
    log = lambda n: os.path.join(run_fs, "log", n)

    # --- plan ---
    rc, contract = _run([BASH, _fw(PC), "contract", SPEC], cwd=cwd)
    has_plan = rc == 0
    contract = _subst(contract)
    m = re.match(r"Plan status:[ \t\r\f\v]*", contract.split("\n")[0])
    plan_raw = contract.split("\n")[0][m.end():] if m else ""
    if plan_raw.startswith("APPROVED"):
        plan = "APPROVED"
    elif plan_raw.startswith("DRAFT"):
        plan = "DRAFT"
    elif plan_raw.startswith("NEEDS HUMAN DECISION"):
        plan = "NHD"
    else:
        plan = "other"
    basis_out, basis, basis_cur, tests_st = "", "n/a", "", ""
    if has_plan:
        basis_out = _subst(_run([BASH, _fw(PC), "basis", SPEC], cwd=cwd)[1])
        bl = basis_out.split("\n")
        basis = _subst("\n".join(l[8:] for l in bl if l.startswith("Status: ")))
        basis_cur = _subst("\n".join(l[7:] for l in bl if l.startswith("Basis: ")))
        tests_st = _subst("\n".join(l[14:] for l in basis_out.replace("\r", "").split("\n")
                                    if l.startswith("Tests status: ")))
    fmt2 = "Plan format: 2" in contract.replace("\r", "").split("\n")

    # --- review section ---
    review = _review_lines(_read(spec_fs) or "")
    has_review = bool(review)
    # both headings (1.3.0): the same section in two languages -> STOP (row 1b of cycle-state.sh)
    review_both = all(any(l.startswith(h) for l in review) for h in REVIEW_H)

    def line(key):
        rx = re.compile("^" + key + r":[ \t\n\r\f\v]*")
        for l in review:
            mm = rx.match(l)
            if mm:
                return l[mm.end():]
        return ""

    rstatus, fstatus = line("Review status"), line("Feature status")
    snap, rcontract, rounds = line("Reviewed snapshot"), line("Reviewed contract"), line("Review rounds")

    def list_of(h):
        res, on = [], False
        for l in review:
            if l == h + ":":
                on = True
                continue
            if on and (re.match(r"^[ \t]*$", l) or l.startswith("Excluded:") or l.startswith("Scope:")
                       or l.startswith("</details>")):
                break
            if on:
                res.append(l)
        return res

    # Excluded lines may carry a note after « — » (e.g. «stessa catena, anello precedente»): only the path counts,
    # as in cycle-state.sh
    scope, excl = list_of("Scope"), [re.sub(r" — .*", "", l) for l in list_of("Excluded")]
    scope_f, excl_f = os.path.join(tmp, "scope"), os.path.join(tmp, "excl")
    for f, ls in ((scope_f, scope), (excl_f, excl)):
        with open(f, "wb") as fh:
            fh.write(_enc("".join(l + "\n" for l in ls)))

    # --- chains ---
    def cclosed(p):
        return _run([BASH, _fw(PC), "closed", p], cwd=cwd)[0] == 0

    CDIR_fs, CDIR = os.path.dirname(spec_fs), posixpath.dirname(SPEC)
    CNAME = posixpath.basename(SPEC)
    CNAME = CNAME[:-3] if CNAME.endswith(".md") and CNAME != ".md" else CNAME
    figlie = _cfiglie(spec_fs)
    ring_k = ring_n = 0
    ring_madre = ring_prev = ring_prev_fs = ring_base = ring_now = ""
    ring_before = []
    if not figlie:
        try:
            cand = sorted(os.listdir(CDIR_fs))
        except OSError:
            cand = []
        for n in cand:
            p = os.path.join(CDIR_fs, n)
            if not fnmatch.fnmatchcase(n, "spec-*.md") or not os.path.isfile(p):
                continue
            try:
                with open(p, "rb") as fh:
                    if not re.search(rb"(?:^|\n)(?:Figlie|Children):", fh.read()):
                        continue
            except OSError:
                continue
            if n[:-3] == CNAME:
                continue
            l = _cfiglie(p)
            if CNAME not in l:
                continue
            k = l.index(CNAME) + 1
            ring_madre, ring_k, ring_n, ring_before = CDIR + "/" + n, k, len(l), l[:k - 1]
            if k > 1:
                ring_prev, ring_prev_fs = CDIR + "/" + l[k - 2] + ".md", os.path.join(CDIR_fs, l[k - 2] + ".md")
            break
    if ring_prev:
        ring_base = _cpost(ring_prev_fs[:-3] + ".run")
        ring_now = _subst(_run([BASH, _fw(RS), "tree"], cwd=cwd)[1])
    chain_state = ""
    if figlie:
        for c in figlie:
            if not os.path.isfile(os.path.join(CDIR_fs, c + ".md")):
                chain_state += c + " assente;"
            elif cclosed(CDIR + "/" + c + ".md"):
                chain_state += c + " chiuso;"
            else:
                chain_state += c + " aperto;"
        chain_state += _first_line(os.path.join(run_fs, "chiusura.txt"))

    # --- contract recorded by the review ---
    hx = re.compile(r"spec [0-9a-f]{12}|plan [0-9a-f]{12}")
    contract_st = "n/a"
    if has_review:
        if not rcontract:
            contract_st = "LEGACY"
        elif hx.findall(rcontract) == hx.findall(basis_cur):
            contract_st = "FRESH"
        else:
            contract_st = "STALE"

    # --- state fingerprint ---
    st = plan_raw + "\n" + basis_out + "\n"
    st += "".join(l + "\n" for l in review if re.match(
        r"(Review status|Feature status|Verification|Reviewed snapshot|Reviewed contract|Review rounds):", l))
    st += "".join(l + "\n" for l in scope) + "".join(l + "\n" for l in excl) + chain_state
    STATE = hashlib.sha256(_enc(st)).hexdigest()[:12]

    # --- last code phase that writes (implement/fix) ---
    last_label = last_esito = last_state = ""
    has_log = os.path.isdir(os.path.join(run_fs, "log"))
    if has_log:
        labs = _labels(run_fs, "implement|fix")
        last_label = labs[-1] if labs else ""
        if last_label and os.path.isfile(log(last_label + ".esito")):
            t = (_read(log(last_label + ".esito")) or "").replace("\r", "")
            last_esito = _subst(t.split("\n")[0])
            last_state = _subst("\n".join(r[6:] for r in _records(t) if r.startswith("state=")))
    json_esito = json_why = ""
    if last_label and os.path.isfile(log(last_label + ".result.json")):
        jr = _json_rule(log(last_label + ".result.json"))
        if jr.startswith("OK|") or jr.startswith("STOP|"):
            json_esito, _, json_why = jr.partition("|")
        else:
            json_esito, json_why = "STOP", T("cycle-state.json_unreadable")

    names = _names(run_fs)
    new_regime = os.path.isdir(os.path.join(run_fs, "evidence")) or any(
        re.search(r"\.result\.json(\.visto)?$", n) for n in names)
    tr_label = ""
    if has_log:
        tl = _labels(run_fs, "test-red")
        tr_label = tl[-1] if tl else ""

    # --- code (only for IMPLEMENTED) ---
    code, code_out = "n/a", ""
    if fstatus.startswith("IMPLEMENTED"):
        if not snap:
            code = "LEGACY"
        else:
            mb = re.match(r".*base ([0-9a-f]{7,})", snap)
            mt = re.match(r".*tree ([0-9a-f]{7,})", snap)
            mf = re.match(r".*fingerprint ([0-9a-f]{7,})", snap)
            b, t, f = (mb.group(1) if mb else ""), (mt.group(1) if mt else ""), (mf.group(1) if mf else "")
            if not b or not t or not scope:
                code, code_out = "UNKNOWN", "  " + T("cycle-state.code_unreadable")
            else:
                args = [BASH, _fw(RS), "check", "--base", b, "--tree", t, "--paths-file", _fw(scope_f),
                        "--exclude-file", _fw(excl_f)] + (["--fingerprint", f] if f else [])
                co = _subst(_run(args, cwd=cwd, merge=True)[1])
                sts = [l[8:] for l in co.split("\n") if l.startswith("Status: ")]
                s0 = sts[0] if sts else ""
                code = "FRESH" if s0.startswith("FRESH") else "STALE" if s0.startswith("STALE") else "UNKNOWN"
                code_out = _subst("\n".join("  " + l for l in co.split("\n") if not l.startswith("Current tree:")))

    out = ["Plan status: " + (plan_raw or "(assente)"), "Plan basis: " + basis]
    if figlie:
        out.append("Catena: madre di %d anelli · %s" % (len(figlie), re.sub(r";(.)", r"; \1", chain_state)))
    elif ring_k:
        mn = posixpath.basename(ring_madre)
        out.append("Catena: anello %d/%d di %s" % (ring_k, ring_n, mn[:-3] if mn.endswith(".md") else mn))
        if ring_prev:
            cat = ""
            for c in ring_before:
                cat += (_read(os.path.join(CDIR_fs, c + ".run", "touched.txt")) or "").replace("\r", "")
            prevf = " ".join(sorted({l for l in _records(cat) if l}))
            out.append("Anelli precedenti: " + T("cycle-state.ring_prev", files=prevf or "(nessun file)"))
            out.append("Base anello: " + ring_base if ring_base else
                       "Base anello: (%s)" % T("cycle-state.ring_base_missing"))
            if ring_base and ring_now:
                o = _run(["git", "-c", "core.quotePath=false", "diff", "--name-only", "--no-renames",
                          ring_base, ring_now], cwd=cwd)[1].replace("\n", " ")
                o = o[:-1] if o.endswith(" ") else o
                out.append("Diff anello: " + (o or "(vuoto)"))
    if "Plan format: 2" in contract.split("\n"):
        out.append("Plan format: 2")
        gp = os.path.join(run_fs, "gen", "procedura.txt")
        if not os.path.isfile(gp):
            out.append("Generated: assente")
        else:
            gl = [l[16:] for l in (_read(gp) or "").replace("\r", "").split("\n") if l.startswith("Impronta piano: ")]
            gfp = gl[0] if gl else ""
            cur = _subst("\n".join(mm.group(1) for l in basis_cur.split("\n")
                                   for mm in [re.match(r".*plan ([0-9a-f]*)", l)] if mm))
            out.append("Generated: FRESH" if gfp and gfp == cur else "Generated: STALE")
    out.append("Review section: " + ("present" if has_review else "absent"))
    if has_review:
        out += ["Review status: " + (rstatus or "(assente)"), "Feature status: " + (fstatus or "(assente)")]
    out += ["Reviewed contract: " + contract_st, "Code: " + code]
    if code_out and (code != "FRESH" or "EXCLUDED-CHANGED" in code_out):
        out.append(code_out)
    out.append("Last code phase: " + (last_label or "(nessuna)") + (" · " + last_esito if last_esito else "")
               + (" · result.json: %s — %s" % (json_esito, json_why) if json_esito else ""))
    out.append("State: " + STATE)

    # --- decision ---
    def harness_gap(nxt):
        # the decision belongs to run-phase.sh --harness-fp-confronta (the single function of the three readers, pk04a-2): here
        # the file's content is not read, we decide on the first word, like cycle-state.sh
        hf = os.path.join(run_fs, "harness.fp")
        if not os.path.isfile(hf):
            return ""
        repo = os.environ.get("FIC_REPO") or _subst(_run(["git", "rev-parse", "--show-toplevel"], cwd=cwd)[1])
        out = _subst(_run([BASH, _fw(RP), "--harness-fp-confronta", _fw(hf), repo], cwd=cwd)[1]) if repo else ""
        w = (out.split() + ["", "", ""])[:3]
        if w[0] == "UGUALE":
            return ""
        mt_ = _mtime(hf)
        since = _utc(mt_) if mt_ is not None else ""
        # 1.6.0 (block Z): on Windows the command mixes C:/… and /tmp/… paths, so it runs in Git Bash; the note is
        # printed on every platform (one output of `next` everywhere: the expected outputs do not depend on the OS)
        rim = "bash \"%s\" --harness-fp > \"%s/harness.fp\" %s" % (mostra(RP), RUN, T("cycle-state-z.rim_git_bash"))
        if w[0] == "CAMBIATO":
            return T("cycle-state.harness_changed", since=since, a=w[1], b=w[2], rim=rim, next=nxt)
        if w[0] == "FORMATO-PRECEDENTE":
            return T("cycle-state.harness_old", a=w[1], since=since, b=w[2], rim=rim, next=nxt)
        if w[0] == "ILLEGGIBILE":
            return T("cycle-state.harness_unreadable", since=since, a=w[1], rim=rim, next=nxt)
        return T("cycle-state.harness_nc", root=mostra(ROOT), repo=repo or "(nessuno)", since=since)

    def nxt(msg):
        word = msg.split(" ", 1)[0]
        if re.match(r"(PLAN|IMPLEMENT|REVIEW|FIX|CHIUSURA|TEST-RED)", msg):
            gap = harness_gap(word)
            if gap:
                raise _Next("STOP — " + gap)
        if re.match(r"(PLAN|IMPLEMENT)", msg):
            if ring_prev:
                ring_gate(word)
        elif msg.startswith("TEST-RED"):
            if ring_prev:
                ring_gate("IMPLEMENT")
        raise _Next(msg)

    def ring_gate(what):
        pn = posixpath.basename(ring_prev)[:-3]
        if what == "PLAN":
            pc = _subst(_run([BASH, _fw(PC), "contract", ring_prev], cwd=cwd)[1]).replace("\r", "")
            mm = re.match(r"Plan status:[ \t\n\r\f\v]*", pc.split("\n")[0])
            pst = pc.split("\n")[0][mm.end():] if mm else ""
            if pst.startswith("APPROVED"):
                return
            raise _Next("WAIT — catena: " + T("cycle-state.ring_plan_wait", k=ring_k, prev=ring_k - 1, pn=pn,
                                                  pst=pst or T("cycle-state.no_plan")))
        if not cclosed(ring_prev):
            raise _Next("WAIT — catena: " + T("cycle-state.ring_impl_wait", k=ring_k, prev=ring_k - 1, pn=pn))
        if any(n.endswith(".pre-tree") for n in names):
            return
        if not ring_base:
            raise _Next("STOP — catena: " + T("cycle-state.ring_no_base", prev=ring_k - 1, pn=pn, k=ring_k))
        if ring_now == ring_base:   # CONTROLLO-TREE-ANELLO
            return
        raise _Next("STOP — catena: " + T("cycle-state.ring_tree", now=ring_now or T("cycle-state.not_computable"),
                                          prev=ring_k - 1, base=ring_base, k=ring_k, pn=pn, rs=mostra(RS)))

    def mother_next():
        n = len(figlie)
        for i, c in enumerate(figlie, 1):
            if not os.path.isfile(os.path.join(CDIR_fs, c + ".md")):
                nxt("STOP — catena: " + T("cycle-state.child_missing", c=c, i=i, n=n))
            if not cclosed(CDIR + "/" + c + ".md"):
                nxt("WAIT — catena: " + T("cycle-state.ring_open", i=i, n=n, c=c))
        cz = _first_line(os.path.join(run_fs, "chiusura.txt"))
        if cz == "":
            nxt("CHIUSURA — " + T("cycle-state.chain_closing", n=n))
        if cz.startswith("Chiusura: IMPLEMENTED"):
            mb = re.match(r".*base ([0-9a-f]{7,})", cz)
            mt = re.match(r".*tree ([0-9a-f]{7,})", cz)
            cp = [l for l in _records((_read(os.path.join(run_fs, "touched.txt")) or "").replace("\r", "")) if l]
            s = ""
            if mb and mt and cp:
                pf = os.path.join(tmp, "chain-paths")
                with open(pf, "wb") as fh:
                    fh.write(_enc("".join(l + "\n" for l in cp)))
                o = _subst(_run([BASH, _fw(RS), "check", "--base", mb.group(1), "--tree", mt.group(1),
                                 "--paths-file", _fw(pf)], cwd=cwd)[1])
                sts = [l[8:] for l in o.split("\n") if l.startswith("Status: ")]
                s = sts[0] if sts else ""
            if s.startswith("FRESH"):
                nxt("DONE — " + T("cycle-state.chain_done", n=n))
            nxt("CHIUSURA — " + T("cycle-state.chain_redo", st=s or T("cycle-state.unreadable")))
        nxt("STOP — " + T("cycle-state.chain_failed", why=cz[len("Chiusura: "):] if cz.startswith("Chiusura: ") else cz,
                          run=RUN))

    def last_ok(ph):
        if ph not in last_label or not last_esito.startswith(tuple("%s %s: OK" % (p, ph) for p in ESITO_PREF)):
            return False
        if json_esito and json_esito != "OK":
            return False
        return last_state == STATE

    def json_stop():
        if json_esito == "STOP" and last_state and last_state == STATE:
            nxt("STOP — " + T("cycle-state.json_stop", label=last_label, why=json_why, run=RUN))

    def finalize_gap():
        if not new_regime:
            return ""
        f = line("Finalize")
        if f == "":
            return T("cycle-state.fin_unsigned_none")
        if not f.startswith("IMPLEMENTED"):
            return T("cycle-state.fin_unsigned", f=f)
        mm = re.match(r".*snapshot ([0-9a-f]{12})", f)
        if not mm:
            return T("cycle-state.fin_no_fp")
        if mm.group(1) != _snap_fp(snap):
            return T("cycle-state.fin_other_snap", fs=mm.group(1))
        tss = re.findall(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", f)
        ts = _epoch(tss[-1]) if tss else None
        if ts is None:
            return T("cycle-state.fin_no_time")
        rl = sorted([mm2.group(1) for n in names for mm2 in [re.match(r"^([0-9]+-[^.]*review[^.]*)\.jsonl$", n)]
                     if mm2], key=_numkey)
        if not rl:
            return ""
        rt = _mtime(log(rl[-1] + ".jsonl"))
        if rt is None:
            return T("cycle-state.fin_review_time", rl=rl[-1])
        return "" if ts >= rt else T("cycle-state.fin_older", rl=rl[-1])

    def budget_fix():
        mn = re.match(r"([0-9]+)/3", rounds)
        mk = re.match(r".*post-approval NEEDS_CHANGES:[ \t\n\r\f\v]*([0-9]+)/1", rounds)
        if not mn or not mk:
            nxt("STOP — " + T("cycle-state.budget_unknown", rounds=rounds))
        n, k = int(mn.group(1)), int(mk.group(1))
        if not (n < 3 and k < 1):
            nxt("STOP — " + T("cycle-state.budget_spent", n=mn.group(1), k=mk.group(1)))

    def attribution_gap():
        if not os.path.isfile(log(last_label + ".post-tree")):
            return T("cycle-state.attr_no_post", label=last_label)
        n = _numkey(last_label)[0]
        for nm in sorted(names):
            if not nm.endswith(".pre-tree"):
                continue
            l = nm[:-9]
            if os.path.isfile(log(l + ".post-tree")):
                continue
            head = l.split("-", 1)[0]
            if head.isdigit() and int(head) < n:
                return T("cycle-state.attr_pre_open", l=l)
        return ""

    def to_review(msg):
        gap = attribution_gap()
        if not gap:
            nxt("REVIEW — " + msg)
        nxt("STOP — " + T("cycle-state.attr_gap", gap=gap, rs=mostra(RS), run=RUN))

    def test_red_gate():
        if not (fmt2 and not last_label and tests_st != "FRESH"):
            return
        if tr_label and os.path.isfile(log(tr_label + ".esito")):
            t = (_read(log(tr_label + ".esito")) or "").replace("\r", "")
            l1 = _subst(t.split("\n")[0])
            s = _subst("\n".join(r[6:] for r in _records(t) if r.startswith("state=")))
            if s and s == STATE:
                nxt("STOP — " + T("cycle-state.testred_stop", label=tr_label, l=l1, run=RUN))
        nxt("TEST-RED — " + T("cycle-state.testred"))

    def touched_excluded():
        tp = os.path.join(run_fs, "touched.txt")
        if not (os.path.isfile(tp) and os.path.getsize(tp) > 0 and excl):
            return ""
        ex = set(excl)
        for l in _records((_read(tp) or "").replace("\r", "")):
            if l in ex:
                return l
        return ""

    try:
        if review_both:
            nxt("STOP — " + T("cycle-state.review_both"))
        if figlie:
            mother_next()
        if has_review and not has_plan:
            nxt("STOP — " + T("cycle-state.review_no_plan"))
        if not has_plan:
            nxt("PLAN — " + T("cycle-state.no_plan"))
        if plan in ("DRAFT", "NHD"):
            if has_review:
                nxt("STOP — " + T("cycle-state.plan_reopened", plan=plan_raw))
            if plan == "DRAFT":
                nxt("PLAN — " + T("cycle-state.plan_draft"))
            nxt("STOP — " + T("cycle-state.plan_nhd"))
        if plan != "APPROVED":
            nxt("STOP — " + T("cycle-state.plan_unknown", plan=plan_raw))
        if basis == "STALE (tests)":
            nxt("STOP — " + T("cycle-state.tests_stale", pc=mostra(PC), spec=SPEC, run=RUN))
        if basis.startswith("STALE"):
            nxt("STOP — " + T("cycle-state.basis_stale", basis=basis))
        if not has_review:
            test_red_gate()
            json_stop()
            if last_ok("implement"):
                to_review(T("cycle-state.impl_done", label=last_label))
            nxt("IMPLEMENT — " + T("cycle-state.impl"))
        if not (rstatus + fstatus):
            nxt("REVIEW — " + T("cycle-state.review_legacy"))
        if rstatus.startswith("NEEDS HUMAN DECISION"):
            nxt("STOP — Review status: NEEDS HUMAN DECISION")
        if contract_st == "STALE":
            nxt("REVIEW — " + T("cycle-state.contract_stale"))
        tx = touched_excluded()
        if tx:
            nxt("STOP — " + T("cycle-state.excluded", tx=tx, run=RUN))
        if rstatus.startswith("NEEDS_CHANGES"):
            json_stop()
            if last_ok("fix"):
                to_review(T("cycle-state.fix_done", label=last_label))
            budget_fix()
            nxt("FIX — Review status: NEEDS_CHANGES")
        if fstatus.startswith("NEEDS_VERIFICATION"):
            nxt("REVIEW — NEEDS_VERIFICATION: " + T("cycle-state.nv_attempt"))
        if rstatus.startswith("APPROVED") and fstatus.startswith("IMPLEMENTED"):
            if code in ("FRESH", "LEGACY"):
                fg = finalize_gap()
                if fg:
                    nxt("REVIEW — " + T("cycle-state.fin_gap", fg=fg, fin=mostra(os.path.join(HERE, "finalize.sh"))))
            if code == "FRESH":
                nxt("DONE — " + T("cycle-state.done_fresh"))
            if code == "LEGACY":
                nxt("DONE — " + T("cycle-state.done_legacy"))
            nxt("REVIEW — " + T("cycle-state.code_changed", code=code))
        nxt("STOP — " + T("cycle-state.unknown", rs=rstatus, fs=fstatus))
    except _Next as e:
        out.append("Next: " + e.msg)
    return out


# ─────────────────────────────────────────────────────────────── valida (structured outcome of run-phase.sh)
KEYS = {"type", "enum", "required", "properties", "additionalProperties", "items", "minLength", "minimum"}
ANNOT = {"$schema", "$id", "title", "description"}
TYPES = {"object": lambda x: isinstance(x, dict), "array": lambda x: isinstance(x, list),
         "string": lambda x: isinstance(x, str), "null": lambda x: x is None,
         "boolean": lambda x: isinstance(x, bool),
         "integer": lambda x: isinstance(x, int) and not isinstance(x, bool),
         "number": lambda x: isinstance(x, (int, float)) and not isinstance(x, bool)}


def _valida_min(x, s, p):
    """Minimal validator: only the keywords in KEYS; an unknown keyword is an error (fail-closed)."""
    extra = sorted(set(s) - KEYS - ANNOT)
    if extra:
        return [T("run-phase.v_keyword", p=p, kw=", ".join(extra))]
    if "type" in s:
        ts = s["type"] if isinstance(s["type"], list) else [s["type"]]
        if not any(TYPES.get(t, lambda v: False)(x) for t in ts):
            return [T("run-phase.v_type", p=p, types="|".join(ts))]
    errs = []
    if "enum" in s and x not in s["enum"]:
        errs.append(T("run-phase.v_enum", p=p, x=repr(x), enum=s["enum"]))
    if isinstance(x, dict):
        props = s.get("properties", {})
        errs += [T("run-phase.v_required", p=p, r=r) for r in s.get("required", []) if r not in x]
        for k, v in x.items():
            if k in props:
                errs += _valida_min(v, props[k], p + "." + k)
            elif s.get("additionalProperties") is False:
                errs.append(T("run-phase.v_extra", p=p, k=k))
    if isinstance(x, list) and "items" in s:
        for i, v in enumerate(x):
            errs += _valida_min(v, s["items"], "%s[%d]" % (p, i))
    if isinstance(x, str) and len(x) < s.get("minLength", 0):
        errs.append(T("run-phase.v_short", p=p, n=s["minLength"]))
    if TYPES["number"](x) and "minimum" in s and x < s["minimum"]:
        errs.append(T("run-phase.v_min", p=p, min=s["minimum"]))
    return errs


def schema_errors(obj, schema):
    """The errors of obj against the schema: jsonschema if available, otherwise the minimal validator."""
    try:
        import jsonschema
    except ImportError:
        return _valida_min(obj, schema, "$")   # VALIDAZIONE-JSON
    return [e.message for e in jsonschema.validators.validator_for(schema)(schema).iter_errors(obj)]


def cmd_valida(log, schema_path, phase, out):
    """Prints the ESITO line (or the «uscita non valida» STOP and, below it, originale=<line>) and writes result.json if
    valid. Same rules, same bytes, as the internal validator of run-phase.sh up to 1.5.1 (gone in 1.6.0)."""
    res = None
    for ln in open(log, encoding="utf-8", errors="replace"):
        try:
            ev = json.loads(ln)
        except ValueError:
            continue
        if isinstance(ev, dict) and ev.get("type") == "result":
            res = ev
        elif isinstance(ev, dict) and ev.get("subtype") == "fic_scartato":
            res = None   # parallel review discarded (harness-pt09): only what follows counts
    if res is None or res.get("is_error"):
        return 0
    text = res.get("result") or ""
    lines = [l.strip() for l in text.splitlines()]
    riga = next((l for l in reversed(lines) if l.startswith(ESITO_PREF)), "")

    def blocco():
        so = res.get("structured_output")
        if isinstance(so, dict):
            return so, ""
        recinti = re.findall(r"```json[ \t]*\r?\n(.*?)\r?\n[ \t]*```", text, re.S)
        if not recinti:
            return None, T("run-phase.v_nojson")
        try:
            return json.loads(recinti[-1]), ""
        except ValueError as e:
            return None, T("run-phase.v_badjson", e=e)

    obj, errs = blocco()
    errs = [errs] if errs else []
    if obj is not None:
        try:
            schema = json.load(open(schema_path, encoding="utf-8"))
        except (OSError, ValueError) as e:
            schema, errs = None, [T("run-phase.v_schema", e=e)]
        if schema is not None:
            errs = schema_errors(obj, schema)
            if not errs and obj.get("fase") != phase:
                errs = [T("run-phase.v_phase", fase=repr(obj.get("fase")), phase=phase)]
    if errs:
        for e in errs:
            print(T("run-phase.v_invalid", msg=e), file=sys.stderr)
        msg = "; ".join(errs[:3]).replace("\n", " ")
        print("PHASE RESULT %s: STOP — %s" % (phase, T("run-phase.v_invalid", msg=msg)))
        if riga:
            print("originale=" + riga)
        return 0
    with open(out + ".tmp", "w", encoding="utf-8") as fh:
        json.dump(obj, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    os.replace(out + ".tmp", out)
    one = lambda s: " ".join(str(s).split())
    dev = [one(x) for x in obj["deviazioni"] if str(x).strip()]
    jstop = ""
    if [x for x in dev if not x.startswith(DIFENSIVA)]:   # all "difensiva: " -> no STOP for deviation
        jstop = T("run-phase.v_dev", n=len(dev), devs="; ".join(dev))
    elif one(obj["bloccato_su"]).lower() not in NESSUNO:
        jstop = T("run-phase.v_blocked") + one(obj["bloccato_su"])
    elif obj["esito"] != "OK":
        jstop = T("run-phase.v_esito") + one(obj["motivo"])
    jstop = jstop[:300]
    if not riga:
        print("PHASE RESULT %s: %s" % (obj["fase"], ("STOP — " + jstop) if jstop else ("OK — " + one(obj["motivo"]))))
    elif jstop and re.match(RIGA_OK, riga):
        print("PHASE RESULT %s: STOP — JSON: %s" % (obj["fase"], T("run-phase.v_json_stop", stop=jstop)))
        print("originale=" + riga)
    else:
        print(riga)
    return 0


def result_errors(path, fase):
    """The result.json of a finished phase, revalidated by the driver before going on (fail-closed)."""
    try:
        obj = json.load(open(path, encoding="utf-8"))
        schema = json.load(open(SCHEMA, encoding="utf-8"))
    except (OSError, ValueError) as e:
        return [T("driver.result_unreadable", e=e)]
    errs = schema_errors(obj, schema)
    if not errs and isinstance(obj, dict) and obj.get("fase") != fase:
        errs = [T("driver.result_phase", fase=repr(obj.get("fase")), phase=fase)]
    return errs


# ─────────────────────────────────────────────────────────────── implement batches and lanes (step 5)
# ESTIMATE of a plan-implementer's context (tokens): BASE (prompt, agent, rules, report) + TOKEN_RIGA × (lines
# of the plan + LETTURE × lines of the files the batch writes; a file that does not exist yet counts NUOVO_RIGHE). A
# declared estimate, not a measurement: it serves to avoid giving a single agent a batch that takes it beyond the cap
# (FIC_LOTTO_MAX, default 150000; measured: implementer at 597k of context on an undivided plan).
TOKEN_RIGA, BASE_TOKEN, LETTURE, NUOVO_RIGHE = 12, 30000, 2, 100
BLOCCO_RX = re.compile(r"^blocco[ \t]+(\S+):[ \t]*scrive=(.*?)[ \t]*·[ \t]*dopo=(.*)$")


def _blocchi(procedura):
    """[(id, [files], [dependencies])] from the "blocco <id>: scrive=… · dopo=…" lines of gen/procedura.txt."""
    res = []
    for l in (_read(procedura) or "").replace("\r", "").split("\n"):
        m = BLOCCO_RX.match(l)
        if m:
            fs = [f for f in m.group(2).split(",") if f and f != "(nessuno)"]
            ds = [d for d in m.group(3).split(",") if d and d != "nessuno"]
            res.append((m.group(1), fs, ds))
    return res


def _ordine(blocchi):
    """The blocks in an order that respects dopo: (on a tie, the plan's order); a cycle keeps the plan's order."""
    ids = [b[0] for b in blocchi]
    fatti, res = set(), []
    while len(res) < len(blocchi):
        pronti = [b for b in blocchi if b[0] not in fatti and all(d in fatti or d not in ids for d in b[2])]
        if not pronti:
            return blocchi
        res.append(pronti[0])
        fatti.add(pronti[0][0])
    return res


def _righe_file(root, f):
    p = os.path.join(root, f)
    if os.path.isfile(p):
        try:
            with open(p, "rb") as fh:
                return fh.read().count(b"\n") + 1
        except OSError:
            return NUOVO_RIGHE
    return 0 if os.path.isdir(p) else NUOVO_RIGHE


def lotti(procedura, root, righe_piano, tetto):
    """[(ids, estimate)]: the blocks, in dopo: order, grouped as long as the estimate stays below the cap. A block
    that exceeds it alone stays a batch of its own (the estimate says so: the plan must be cut, not the agent starved)."""
    res, cur, tot = [], [], 0
    fisso = BASE_TOKEN + TOKEN_RIGA * righe_piano
    for bid, fs, _ in _ordine(_blocchi(procedura)):
        costo = TOKEN_RIGA * LETTURE * sum(_righe_file(root, f) for f in fs)
        if cur and fisso + tot + costo > tetto:
            res.append((cur, fisso + tot))
            cur, tot = [], 0
        cur.append(bid)
        tot += costo
    if cur:
        res.append((cur, fisso + tot))
    return res


def _righe_piano(spec_fs):
    n, on = 0, False
    for l in _records((_read(spec_fs) or "").replace("\r", "")):
        if l.startswith(("## Piano di implementazione", "## Implementation plan")):
            on = True
        elif on and l.startswith(REVIEW_H):
            break
        n += on
    return n


def prepara_implement(spec_fs, run_fs, label, root, ev, una_corsia=False):
    """Before a format-2 implement: procedure regenerated from the current plan (in a separate folder), batches
    sized (log/<label>.lotti, LOTTI line in the prompt) and lane decision (log/<label>.corsie-driver,
    which run-phase.sh receives in FIC_CORSIE and uses instead of its own: launch_lanes stays its own). Returns
    (line to add to the prompt | "", lanes file | "")."""
    tmp = tempfile.mkdtemp(prefix="fic-lotti-")
    try:
        rc, _ = _run([BASH, _fw(PC), "gen", shown(spec_fs), "--run-dir", _fw(tmp)], cwd=os.path.dirname(spec_fs))
        proc = os.path.join(tmp, "gen", "procedura.txt")
        if rc != 0 or not os.path.isfile(proc):
            ev(T("driver.lots_no_f2"))
            return "", ""
        repo = os.environ.get("FIC_REPO") or root
        tetto = int(os.environ.get("FIC_LOTTO_MAX") or 150000)
        lt = lotti(proc, repo, _righe_piano(spec_fs), tetto)
        os.makedirs(os.path.join(run_fs, "log"), exist_ok=True)
        desc = " · ".join("lotto %d/%d: %s (~%dk token%s)" % (i, len(lt), ",".join(ids), st // 1000,
                                                             T("driver.lot_over") if st > tetto else "")
                          for i, (ids, st) in enumerate(lt, 1))
        with open(os.path.join(run_fs, "log", label + ".lotti"), "wb") as fh:
            fh.write(_enc("tetto=%d\n%s\n" % (tetto, desc.replace(" · ", "\n"))))
        ev(T("driver.ev_lots") + desc)
        riga = "LOTTI (driver): " + T("driver.lots_line", desc=desc, cap=tetto // 1000)
        cf = ""
        if una_corsia:   # 1.7.0: the small size, one lane (run-phase.sh receives FIC_LANES=0)
            ev(T("driver-170.lanes_small"))
        elif os.environ.get("FIC_LANES", "1") != "0":
            bi = os.environ.get("FIC_BLOCKS_INDEPENDENT") or os.path.join(HERE, "blocks-independent.py")
            p = subprocess.run([sys.executable, bi, "--root", repo, proc], stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            txt = _dec(p.stdout).replace("\r", "")
            if p.returncode > 1 or not txt.strip():
                txt = "blocks-independent: esito=serie motivo=%s\n" % T("run-phase.bi_failed", rc=p.returncode)
            cf = os.path.join(run_fs, "log", label + ".corsie-driver")
            with open(cf, "wb") as fh:
                fh.write(_enc(txt if txt.endswith("\n") else txt + "\n"))
            ev(T("driver.ev_lanes") + txt.split("\n")[0])
        return riga, cf
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


L2_RIGA = re.compile(r"^L2 (\S+): (OK|NO)(?: — (.*))?$")   # the same regex as finalize.sh (cmd_controprove)


def promuovi_l2(spec_fs, run_fs, ev):
    """Before a review (harness-pt15): the counterproofs marked "assorbita" (L2) in counterproof/mutations.json
    are re-checked with THE SAME check as finalize.sh — `plan-check.sh l2` on the current code — and those that
    do not hold (NO, or no line: finalize would reject them) are PROMOTED: "assorbita"/"motivo" removed, they
    are really executed. Previous copy in mutations.json.pre-promozione, the old <id>.json with outcome assorbita in
    <id>.json.assorbita. An entry already executed never goes back to assorbita. Returns the promoted ids."""
    mj = os.path.join(run_fs, "counterproof", "mutations.json")
    t = _read(mj)
    if not t or not re.search(r'"assorbita": *true', t):   # the same condition as finalize.sh
        return []
    try:
        lst = json.loads(t)
    except ValueError:
        return []
    if not isinstance(lst, list):
        return []
    rc, out = _run([BASH, _fw(PC), "l2", shown(spec_fs), "--run-dir", _fw(run_fs)], cwd=os.path.dirname(spec_fs),
                   merge=True)
    st = {}
    for ln in out.replace("\r", "").split("\n"):
        m = L2_RIGA.match(ln.strip())
        if m:
            st[m.group(1)] = (m.group(2), m.group(3) or "")
    promosse = []
    for e in lst:
        if not isinstance(e, dict) or e.get("assorbita") is not True:
            continue
        mid = str(e.get("id"))
        s = st.get(mid)
        if s and s[0] == "OK":
            continue
        e.pop("assorbita", None)
        e.pop("motivo", None)
        promosse.append(mid)
        ev("L2: " + T("driver.l2_promoted", id=mid, why=s[1] if s else T("driver.l2_unverified", rc=rc)))
    if not promosse:
        return []
    shutil.copyfile(mj, mj + ".pre-promozione")
    for mid in promosse:
        r = os.path.join(run_fs, "counterproof", mid + ".json")
        if re.match(r"^[\w.-]+$", mid) and os.path.isfile(r):
            os.replace(r, r + ".assorbita")
    with open(mj + ".tmp", "w", encoding="utf-8", newline="\n") as fh:   # the same format as plan-check.sh gen
        json.dump(lst, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(mj + ".tmp", mj)
    return promosse


# ─────────────────────────────────────────────────────────────── lines loaded per phase (step 4)
# The instruction files every phase loads by construction (child-rules in --append-system-prompt, the cycle's
# SKILL, the worker's file, the invoked SKILL): the measure of pt14's benefit (target <=300 lines per phase).
# The conditional files (format 1, light branch, freshness, gates run by the model, worker counterproofs)
# are listed separately: they are loaded only on that path. Agents have their own context and are separate.
CARICO = {
    "orchestratore": ["SKILL", "full-implementation-cycle/orchestratore.md"],
    "plan": ["child", "SKILL", "w:plan", "prc"],
    "test-red": ["child", "SKILL", "w:test-red"],
    "implement": ["child", "SKILL", "w:implement"],
    "review": ["child", "SKILL", "w:review", "irc"],
    "fix": ["child", "SKILL", "w:fix"],
    "chiusura": ["child", "SKILL", "w:chiusura"],
}
CONDIZIONALI = {
    "plan": ["plan-review-cycle/formato-1.md"],
    "review": ["full-implementation-cycle/workers/controprove.md", "implementation-review-cycle/freschezza.md",
               "implementation-review-cycle/gate-manuali.md"],
}
# Reads outside the base load, reported separately (they do not count toward the cap): the plan phase reads autore.md
# when it writes or revises the plan (in a new plan phase: always); the sub-agents have a context of their own
# (their mandate file + the agent definition). The label is a function: the catalog text, read when printed.
LETTURE_A_PARTE = {
    "plan": [(lambda: T("driver.reads_plan_writing"), ["+base", "plan-review-cycle/autore.md"]),
             (lambda: T("driver.reads_plan_reviewer"), ["plan-review-cycle/revisori.md", "agents/spec-plan-reviewer.md"])],
    "test-red": [(lambda: T("driver.reads_agent"), ["agents/acceptance-test-writer.md"])],
    "implement": [(lambda: "implementer", ["agents/plan-implementer.md"])],
    "fix": [(lambda: "implementer", ["agents/plan-implementer.md"])],
    "review": [(lambda: T("driver.reads_reviewer"),
                ["implementation-review-cycle/prompt-revisore.md", "agents/implementation-reviewer.md"])],
}


def _file_carico(k):
    sk = os.path.join(ROOT, "skills")
    if k.startswith("agents/"):
        return os.path.join(ROOT, k)
    return {"child": os.path.join(FC, "child-rules.md"), "SKILL": os.path.join(FC, "SKILL.md"),
            "prc": os.path.join(sk, "plan-review-cycle", "SKILL.md"),
            "irc": os.path.join(sk, "implementation-review-cycle", "SKILL.md")}.get(
        k, os.path.join(FC, "workers", k[2:] + ".md") if k.startswith("w:") else os.path.join(sk, k))


def _conta(p):
    t = _read(p)
    return None if t is None else len(_records(t.replace("\r", "")))


def cmd_righe(argv):
    tetto = int(argv[0]) if argv and argv[0].isdigit() else 300
    sopra = 0
    for fase, ks in CARICO.items():
        parti, tot = [], 0
        for k in ks:
            n = _conta(_file_carico(k))
            parti.append("%s=%s" % (os.path.relpath(_file_carico(k), os.path.join(ROOT, "skills")).replace("\\", "/"),
                                    T("driver.missing") if n is None else n))
            tot += n or 0
        cond = ["+%s=%s" % (c, _conta(_file_carico(c))) for c in CONDIZIONALI.get(fase, [])]
        lett = []
        for etichetta, fs in LETTURE_A_PARTE.get(fase, []):
            n = sum(_conta(_file_carico(f)) or 0 for f in fs if f != "+base") + (tot if "+base" in fs else 0)
            lett.append("%s: %d (%s)" % (etichetta(), n, " ".join(("base" if f == "+base" else
                                                              "%s=%s" % (f, _conta(_file_carico(f)))) for f in fs)))
        sopra += tot > tetto
        print("righe %s: %d%s · %s%s%s" % (fase, tot, " " + T("driver.above_cap", cap=tetto) if tot > tetto else "",
                                           " ".join(parti),
                                           (" · %s " % T("driver.conditional") + " ".join(cond)) if cond else "",
                                           "".join(" · " + x for x in lett)))
    return 1 if sopra else 0


# ─────────────────────────────────────────────────────────────── size of the cycle (1.7.0)
# <run-dir>/taglia.txt, APPEND-ONLY, one line per decision: "<utc> · <moment> · Taglia: piccola|piena — <why>[ · fatti
# F1=… …]" or "<utc> · <moment> · Escalation: piccola → piena — <cause>". Moments: avvio (first launch of a cycle
# started with 1.7: the size is still to be decided), T2 (the approved plan), E2 (reopening in the full branch), T2r
# (the reopened plan approved), T3 <label> and E3 <label> (after an implement/fix), R <label>, E4 <label> and
# E5 <label> (after a review). No file = piena: a cycle started before 1.7 goes on in the full flow. A line that is
# neither piccola nor avvio = piena, and from there never piccola again (taglia_stato). The facts come from
# `plan-check.sh taglia`, never from the model.
TAGLIA_TXT = "taglia.txt"


def _taglia_righe(run_fs):
    t = _read(os.path.join(run_fs, TAGLIA_TXT))
    return None if t is None else [l for l in _records(t.replace("\r", "")) if l.strip()]


def _momento(l):
    p = l.split(" · ", 2)
    return p[1] if len(p) == 3 else ""


def taglia_stato(run_fs):
    """None (no taglia.txt: piena, a cycle older than 1.7) · "auto" (only avvio) · "piccola" · "piena"."""
    rr = _taglia_righe(run_fs)
    if rr is None:
        return None  # ASSENTE-PIENA
    st = "auto" if rr else "piena"
    for l in rr:
        p = l.split(" · ", 2)
        if len(p) == 3 and p[2].startswith("Taglia: piccola"):
            st = "piccola"
        elif len(p) == 3 and p[1] == "avvio":
            continue
        elif len(p) == 3 and p[1].startswith("P ") and p[2].startswith("prova="):   # the proof of a plan phase
            continue
        else:   # Taglia: piena, Escalation:, or a line not understood: piena (fail-closed), for good
            return "piena"  # SENSO-UNICO
    return st


TAGLIA_SHA = "taglia.sha"   # the sha256 the driver expects taglia.txt to have, rewritten after each of its writes
# The expected sha256 of each run dir's taglia.txt IN THE DRIVER'S MEMORY (third review): set after each of its writes
# and after each check, compared before and after every phase. A phase can rewrite taglia.sha with Bash; it cannot
# reach this. taglia.sha is used only at the first check of an invocation (the weaker check, between invocations).
ATTESO = {}
# a line the driver writes in driver.log when a cycle gets its size: a run dir with it is never a cycle of 1.6
MARCA_170 = "Taglia: avvio"


def _taglia_scrivi(run_fs, momento, testo):
    os.makedirs(run_fs, exist_ok=True)
    with open(os.path.join(run_fs, TAGLIA_TXT), "ab") as fh:   # append-only: never rewritten  # TAGLIA-APPEND
        fh.write(_enc("%s · %s · %s\n" % (_utc(int(datetime.datetime.now(datetime.timezone.utc).timestamp())),
                                          momento, testo)))
    ATTESO[run_fs] = _taglia_sha(run_fs)
    with open(os.path.join(run_fs, TAGLIA_SHA), "w", encoding="ascii", newline="\n") as fh:
        fh.write((ATTESO[run_fs] or "") + "\n")


def _marcato_170(run_fs):
    """driver.log holds the line the 1.7 driver writes at avvio: the cycle has (had) a size, it is not one of 1.6."""
    return (" " + MARCA_170 + " — ") in (_read(os.path.join(run_fs, "driver.log")) or "")  # MARCA-170


def _sha_atteso(run_fs):
    t = _read(os.path.join(run_fs, TAGLIA_SHA))
    return None if t is None else (t.strip() or None)


def verifica_taglia(run_fs, ev, label=""):
    """taglia.txt is the one the driver last wrote (taglia.sha), checked before every launch and after every phase:
    a change made by a phase, between two phases or between two invocations of the driver (a process left running)
    is an Escalation E0. Neither file (a cycle older than 1.7): nothing to check."""
    reale = _taglia_sha(run_fs)
    if run_fs in ATTESO:   # this invocation's own record: what a phase rewrites on disk does not count  # SHA-IN-MEMORIA
        atteso = ATTESO[run_fs]
    else:                  # first check of this invocation: taglia.sha of the previous one (weaker)
        atteso = _sha_atteso(run_fs)
        if reale is None and atteso is None:
            if not _marcato_170(run_fs):
                return     # a cycle older than 1.7 (or a new one): nothing to check
            atteso = "-"   # a 1.7 cycle whose two files are gone: never the 1.6 path
    if reale != atteso:  # TAGLIA-INTATTA
        if label:   # during the phase just finished
            _scala(run_fs, ev, "E0 " + label, T("driver-170.tampered", label=label, a=(atteso or "-")[:12],
                                                 b=(reale or "-")[:12]), label)
        else:       # between two phases or two invocations
            _scala(run_fs, ev, "E0 *", T("driver-170.tampered_between", a=(atteso or "-")[:12], b=(reale or "-")[:12]),
                   "*")
    else:
        ATTESO[run_fs] = reale


def _avviato(run_fs):
    """A phase was already launched in this run dir (log/ or prompts/ with a numbered file)."""
    for d in ("log", "prompts"):
        try:
            if any(re.match(r"[0-9]+-", n) for n in os.listdir(os.path.join(run_fs, d))):
                return True
        except OSError:
            pass
    return False


def _override(flags):
    return "full" if "--full" in flags else "light" if "--light" in flags else ""


def _taglia_sha(run_fs):
    """sha256 of taglia.txt (None if absent): taken before and after every phase (1.7.0 review: only the driver
    writes it; a sub-session that touches it gets the full size)."""
    try:
        with open(os.path.join(run_fs, TAGLIA_TXT), "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return None


# The proof that the FULL plan branch ran, read from the stream of THAT plan phase only (log/<label>.jsonl, written by
# run-phase.sh): at least REVISORI_MIN tool_use blocks named Task or Agent whose input.subagent_type is exactly
# spec-plan-reviewer (maat: prefix or not, never -light): the three lenses of round 1. A text that only contains the
# name does not count; a missing or unreadable log is prova=no. Recorded in taglia.txt as "P <label> · prova=sì|no".
REVISORI_PIENI = ("spec-plan-reviewer", "maat:spec-plan-reviewer")
REVISORI_MIN = 3


REVISORI_LEGGERI = ("spec-plan-reviewer-light", "maat:spec-plan-reviewer-light")
LEGGERI_MIN = 1   # the light branch (plan-review-cycle-light) calls spec-plan-reviewer-light once per round, >= 1 round


def _chiamate_revisore(path, nomi=REVISORI_PIENI):
    n = 0
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return 0
    with fh:
        for riga in fh:
            try:
                ev_ = json.loads(riga)
            except ValueError:
                continue
            msg = ev_.get("message") if isinstance(ev_, dict) else None
            cont = msg.get("content") if isinstance(msg, dict) else None
            for b in cont if isinstance(cont, list) else []:
                inp = b.get("input") if isinstance(b, dict) else None
                if (isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") in ("Task", "Agent")
                        and isinstance(inp, dict) and inp.get("subagent_type") in nomi):  # PROVA-RAMO-PIENO
                    n += 1
    return n


def registra_prova(run_fs, label, ev):
    """After a plan phase: "P <label> · prova=sì|no (<n> spec-plan-reviewer) · leggeri=<m>" in taglia.txt (prova =
    the full branch; leggeri = the calls of the light branch, which count only when route says leggero)."""
    lg = os.path.join(run_fs, "log", label + ".jsonl")
    n, m = _chiamate_revisore(lg), _chiamate_revisore(lg, REVISORI_LEGGERI)
    _taglia_scrivi(run_fs, "P " + label, "prova=%s (%d spec-plan-reviewer) · leggeri=%d"
                   % ("sì" if n >= REVISORI_MIN else "no", n, m))


def _prove(rr, dopo=-1, leggero=False):
    """The P lines after line index `dopo`: [True|False] (with leggero, a light round counts too), in order."""
    res = []
    for l in rr[dopo + 1:]:
        if not _momento(l).startswith("P "):
            continue
        body = l.split(" · ", 2)[2]
        ml = re.search(r" · leggeri=([0-9]+)", body)
        res.append(body.startswith("prova=sì") or (leggero and bool(ml) and int(ml.group(1)) >= LEGGERI_MIN))  # PROVA-LEGGERA
    return res


def _da_ultimo_t2(rr):
    """The index of the last T2, T2r or E2 line (-1 if none): a proof counts from there on (third review)."""
    ix = [i for i, l in enumerate(rr) if _momento(l) in ("T2", "T2r", "E2")]
    return ix[-1] if ix else -1


def _route_leggero(spec_fs):
    """plan-check.sh route says Percorso: leggero (the light rounds of 1.6 are the full size's own flow)."""
    rc, o = _run([BASH, _fw(PC), "route", shown(spec_fs)], cwd=os.path.dirname(spec_fs))
    return any(l.startswith("Percorso: leggero") for l in o.replace("\r", "").split("\n"))


def _taglia_cmd(spec_fs, ovr, diff="", touched=""):
    """(piccola|piena, the Taglia: line, the facts after Fatti:) of plan-check.sh taglia; no Taglia: line = piena."""
    args = [BASH, _fw(PC), "taglia", shown(spec_fs)] + (["--diff", _fw(diff)] if diff else []) \
        + (["--touched", _fw(touched)] if touched else []) + (["--override", ovr] if ovr else [])
    rc, o = _run(args, cwd=os.path.dirname(spec_fs))
    ls = o.replace("\r", "").split("\n")
    t = next((l for l in reversed(ls) if l.startswith("Taglia: ")), "")
    f = next((l[7:] for l in ls if l.startswith("Fatti: ")), "")
    if not (t.startswith("Taglia: piccola — ") or t.startswith("Taglia: piena — ")):
        return "piena", "Taglia: piena — " + T("driver-170.taglia_failed", rc=rc), ""
    return ("piccola" if t.startswith("Taglia: piccola") else "piena"), t, f


def _metrica(spec_fs):
    """(how many "Metrica ciclo:" lines the spec has, the taglia= of the last one or "")."""
    n, last = 0, ""
    for l in _records((_read(spec_fs) or "").replace("\r", "")):
        if "Metrica ciclo:" in l:
            n, last = n + 1, l
    m = re.search(r"\btaglia=(piccola|piena)\b", last)
    return n, (m.group(1) if m else "")


def _diff_toccati(run_fs, root):
    """(diff file of the touched.txt paths from base.txt to the current tree, "") or ("", why)."""
    base = _first_line(os.path.join(run_fs, "base.txt")).strip()
    tp = os.path.join(run_fs, "touched.txt")
    if not base:
        return "", T("driver-170.no_base")
    if not os.path.isfile(tp):
        return "", T("driver-170.no_touched")
    rc, tree = _run([BASH, _fw(RS), "tree"], cwd=root)
    tree = tree.strip()
    if rc != 0 or not tree:
        return "", "review-surface.sh tree: exit %d" % rc
    fd, out = tempfile.mkstemp(prefix="fic-taglia-", suffix=".diff")
    os.close(fd)
    rc, _ = _run([BASH, _fw(RS), "diff", "--from", base, "--to", tree, "--paths-file", _fw(tp), "--out", _fw(out)],
                 cwd=root)
    if rc != 0:
        os.remove(out)
        return "", "review-surface.sh diff: exit %d" % rc
    return out, ""


def _scala(run_fs, ev, momento, causa, dopo):
    """Escalation piccola → piena: one line in taglia.txt and one in the driver's events."""
    _taglia_scrivi(run_fs, momento, "Escalation: piccola → piena — " + causa)
    ev("Escalation: piccola → piena — %s (%s)" % (causa, T("driver-170.after", label=dopo)))


def _perche(t):
    return t.split(" — ", 1)[1] if " — " in t else t


def taglia_passo(spec_fs, run_fs, root, flags, ev, plan_ok):
    """The decisions of the size before a launch, all read again from the files (a restart resumes them):
    ("", "") go on · ("riapri", <cause>) E2, the plan phase reopens the plan with --full · ("stop", <reason>)."""
    rr = _taglia_righe(run_fs) or []
    st = taglia_stato(run_fs)
    if st is None:
        return "", ""
    ovr = _override(flags)
    nmet, mt = _metrica(spec_fs)
    e2 = [i for i, l in enumerate(rr) if _momento(l) == "E2"]
    if e2 and not any(_momento(l) == "T2r" for l in rr[e2[-1]:]):   # E2 pending: the reopening
        if not plan_ok:
            return "", ""
        mm = re.search(r" · metriche=([0-9]+)", rr[e2[-1]])
        if nmet <= (int(mm.group(1)) if mm else nmet):
            return "riapri", _perche(rr[e2[-1]].split("Escalation: ", 1)[-1].split(" · metriche=", 1)[0])
        # the reopened plan: a new metric line taglia=piena AND a full reviewer in a plan phase after the E2
        pr = _prove(rr, e2[-1])
        if mt != "piena" or not any(pr):  # PROVA-DOPO-E2
            return "stop", T("driver-170.reopen_not_full", m=mt or "-")
        t = "Taglia: piena — " + T("driver-170.reopen_done")
        _taglia_scrivi(run_fs, "T2r", t + " · metriche=%d" % nmet)
        ev(t)
        return "", ""
    # T2 on the approved plan; again whenever the plan has a new metric line (a plan reopened and approved again)
    t2 = [l for l in rr if _momento(l) in ("T2", "T2r")]
    mt2 = re.search(r" · metriche=([0-9]+)", t2[-1]) if t2 else None
    if plan_ok and (st == "auto" or (st == "piccola" and nmet > (int(mt2.group(1)) if mt2 else -1))):  # CONTROLLO-T2
        k, t, f = _taglia_cmd(spec_fs, ovr)
        fatti = (" · fatti " + f) if f else ""
        # E2: a plan approved small whose facts are above the small size, or a full size with no proof that the full
        # branch ran in a plan phase of this run dir (the metric line is the model's word, the log is not)
        # no P line at all: a plan approved outside the cycle (the only exemption); otherwise the last plan phase
        tutte = _prove(rr)
        pr = _prove(rr, _da_ultimo_t2(rr), leggero=k == "piena" and bool(tutte) and _route_leggero(spec_fs))
        senza_prova = k == "piena" and mt != "piccola" and bool(tutte) and not any(pr)  # PROVA-T2
        if (mt == "piccola" and k == "piena") or senza_prova:
            _taglia_scrivi(run_fs, "T2", t + fatti + " · piano: taglia=%s · metriche=%d" % (mt or "-", nmet))
            ev(t)
            causa = T("driver-170.no_full_proof") if senza_prova else T("driver-170.e2_cause", why=_perche(t))
            _taglia_scrivi(run_fs, "E2", "Escalation: piccola → piena — %s · metriche=%d" % (causa, nmet))
            ev("Escalation: piccola → piena — %s (%s)" % (causa, T("driver-170.after", label="plan")))
            return "riapri", causa
        if mt != "piccola" and k == "piccola":   # reviewed in the full branch: piena, never down
            t = "Taglia: piena — " + T("driver-170.plan_full_branch", m=mt or "-")
        _taglia_scrivi(run_fs, "T2", t + fatti + " · piano: taglia=%s · metriche=%d" % (mt or "-", nmet))
        ev(t)
        return "", ""
    if st != "piccola":
        return "", ""
    log = lambda n: os.path.join(run_fs, "log", n)
    code = _labels(run_fs, "implement|fix")
    if code and re.match(RIGA_OK, _first_line(log(code[-1] + ".esito"))):
        lab = code[-1]
        if not any(_momento(l) in ("T3 " + lab, "E3 " + lab) for l in rr):   # CONTROLLO-T3: the code written
            diff, why = _diff_toccati(run_fs, root)
            if diff:
                try:
                    k, t, f = _taglia_cmd(spec_fs, ovr, diff, os.path.join(run_fs, "touched.txt"))
                finally:
                    os.remove(diff)
            else:
                k, t, f = "piena", "Taglia: piena — " + T("driver-170.diff_failed", why=why), ""
            ev(t)
            if k == "piena":  # ESCALATION-E3: the escalation line is the record (the facts are in its cause)
                _scala(run_fs, ev, "E3 " + lab, _perche(t), lab)
                return "", ""
            _taglia_scrivi(run_fs, "T3 " + lab, t + ((" · fatti " + f) if f else ""))
    revs = [l for l in _labels(run_fs, "review") if os.path.isfile(log(l + ".esito"))]
    if revs and not any(_momento(l) in ("R " + revs[-1], "E4 " + revs[-1], "E5 " + revs[-1]) for l in rr):
        lab = revs[-1]
        g = [l for l in (_read(log(lab + ".gates")) or "").replace("\r", "").split("\n") if l.startswith("gates: esito=")]
        if not g:
            _scala(run_fs, ev, "E4 " + lab, T("driver-170.gates_missing", label=lab), lab)
            return "", ""
        if not re.match(r"gates: esito=(PASS|SKIPPED) ", g[-1]) or "NOT RUN" in g[-1]:  # ESCALATION-E4
            _scala(run_fs, ev, "E4 " + lab, T("driver-170.gates_bad", label=lab,
                                              esito=g[-1][len("gates: esito="):].split(" chiave=")[0]), lab)
            return "", ""
        rs = next((l[len("Review status:"):].strip() for l in _review_lines(_read(spec_fs) or "")
                   if l.startswith("Review status:")), "")
        if rs.startswith("NEEDS_CHANGES"):  # ESCALATION-E5
            try:
                fd = json.load(open(log(lab + ".result.json"), encoding="utf-8")).get("finding") or []
                sev = [str(x.get("severita", "")).lower() for x in fd if isinstance(x, dict)]
                causa = T("driver-170.review_nc", label=lab, nb=sev.count("blocker"), nm=sev.count("major"))
            except (OSError, ValueError, AttributeError):
                causa = T("driver-170.review_nc_unknown", label=lab)
            _scala(run_fs, ev, "E5 " + lab, causa, lab)
            return "", ""
        if not rs.startswith("APPROVED"):  # REVIEW-SOLO-APPROVED: any other status (or none) is not «review ok»
            _scala(run_fs, ev, "E5 " + lab, T("driver-170.review_not_approved", label=lab, rs=rs or "(assente)"), lab)
            return "", ""
        _taglia_scrivi(run_fs, "R " + lab, "Taglia: piccola — " + T("driver-170.review_ok", label=lab))
    return "", ""


# ─────────────────────────────────────────────────────────────── run (the state machine)
FASI = {"PLAN": "plan", "TEST-RED": "test-red", "IMPLEMENT": "implement", "REVIEW": "review", "FIX": "fix",
        "CHIUSURA": "chiusura"}


class _Eventi:
    def __init__(self, run_fs):
        self.f = os.path.join(run_fs, "driver.log")

    def __call__(self, msg):
        print("driver: " + msg, flush=True)
        try:
            os.makedirs(os.path.dirname(self.f), exist_ok=True)
            with open(self.f, "ab") as fh:
                fh.write(_enc("%s %s\n" % (_utc(int(datetime.datetime.now(datetime.timezone.utc).timestamp())), msg)))
        except OSError:
            pass


def _next_label(run_fs, fase):
    n = 0
    for d in ("log", "prompts"):
        try:
            for nm in os.listdir(os.path.join(run_fs, d)):
                m = re.match(r"([0-9]+)-", nm)
                if m:
                    n = max(n, int(m.group(1)))
        except OSError:
            pass
    return "%02d-%s" % (n + 1, fase)


def _rel(p, root):
    try:
        r = os.path.relpath(p, root) if root else ".."
    except ValueError:   # different drives (Windows)
        r = ".."
    return shown(p) if r.startswith("..") else _fw(r)


def _tail(p, n=3):
    t = _read(p) or ""
    return " | ".join([l for l in t.replace("\r", "").split("\n") if l.strip()][-n:])


def cmd_run(argv):
    max_fasi, dry, flags, spec = int(os.environ.get("FIC_MAX_FASI") or 12), False, [], None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--":
            flags = argv[i + 1:]
            break
        if a == "--max-fasi" and i + 1 < len(argv) and argv[i + 1].isdigit():
            max_fasi = int(argv[i + 1])
            i += 2
            continue
        if a == "--dry-run":
            dry = True
        elif spec is None and not a.startswith("-"):
            spec = a
        else:
            return _uso()
        i += 1
    if not spec or not os.path.isfile(spec):
        return _uso()
    if "--full" in flags and "--light" in flags:   # 1.7.0: the two overrides of the size together  # FULL-LIGHT
        print(T("driver-170.usage_full_light"), file=sys.stderr)
        return 2
    rp = os.environ.get("FIC_RUN_PHASE") or RP
    cpk = os.environ.get("FIC_CONTEXT_PACK") or CPK
    spec_fs, entrati = None, set()
    visti = set()   # (spec, State) from which we already moved to another spec of the chain without launching anything
    prev, launched = None, 0

    def entra(p):
        nonlocal spec_fs, name, run_fs, root, ev
        spec_fs = os.path.abspath(p)
        base = os.path.basename(spec_fs)
        name = base[5:-3] if base.startswith("spec-") and base.endswith(".md") else base.rsplit(".", 1)[0]
        run_fs = spec_fs[:-3] + ".run" if spec_fs.endswith(".md") else spec_fs + ".run"
        rc, top = _run(["git", "rev-parse", "--show-toplevel"], cwd=os.path.dirname(spec_fs))
        root = os.path.normpath(_subst(top)) if rc == 0 and top.strip() else os.path.dirname(spec_fs)
        ev = _Eventi(run_fs)

    name = run_fs = root = ev = None
    entra(spec)

    def fine(kind, msg, code):
        ev("Driver result: %s — %s" % (kind, msg))
        return code

    # 1.5.1 (D2): Python 3.10 or newer, checked first (there is no other engine to fall back on)
    if tuple(sys.version_info[:2]) < PY_MIN:
        return fine("STOP", T("driver-engine.python_old", v="%d.%d" % tuple(sys.version_info[:2]), py=sys.executable,
                              min="%d.%d" % PY_MIN), 1)
    # 1.6.0 (D1): the driver is the only engine. FIC_DRIVER set to any non-empty value (0, the bash engine of 1.5.1,
    # included) no longer has any effect: one AVVISO per invocation, here only (the wrappers are silent).
    # FIC_CYCLE_STATE (tests) replaces our own `next` with that script, as FIC_RUN_PHASE replaces run-phase.sh.
    fd = os.environ.get("FIC_DRIVER", "")
    if fd:
        ev("AVVISO: " + T("driver-engine.fic_driver_tolta", v=fd))
    cs_test = os.environ.get("FIC_CYCLE_STATE", "")

    while True:
        if spec_fs not in entrati:
            entrati.add(spec_fs)
            running = sorted(n[:-8] for n in _names(run_fs) if n.endswith(".running")
                             and not os.path.isfile(os.path.join(run_fs, "log", n[:-8] + ".exit")))
            if running:
                return fine("RUNNING", T("driver.running", label=running[-1]), 4)
        out = _next_da_script(cs_test, spec_fs) if cs_test else cycle_state(spec_fs)
        state = next((l[7:] for l in out if l.startswith("State: ")), "")
        nx = out[-1][6:] if out and out[-1].startswith("Next: ") else ""
        word = nx.split(" ", 1)[0]
        ev("Next: " + nx)
        if prev is not None and word == prev[0] and state == prev[1]:  # ANTI-LOOP
            return fine("STOP", T("driver.antiloop", label=prev[2], state=state, next=nx), 1)
        # M2: the chain. WAIT naming a ring -> that ring; DONE of a ring -> the mother, which names the
        # next ring or the closing. Same budget, same anti-loop; a hand-over already made with no launches
        # in between is not repeated (no idle loop between mother and rings).
        dest = ""
        if word == "WAIT":
            m = re.search(r"\((spec-[A-Za-z0-9._-]+)\)", nx)
            dest = os.path.join(os.path.dirname(spec_fs), m.group(1) + ".md") if m else ""
        elif word == "DONE":
            m = next((re.match(r"Catena: anello [0-9]+/[0-9]+ di (spec-[A-Za-z0-9._-]+)$", l) for l in out
                      if l.startswith("Catena: anello ")), None)
            dest = os.path.join(os.path.dirname(spec_fs), m.group(1) + ".md") if m else ""
        if dest and os.path.isfile(dest) and (spec_fs, state) not in visti:
            visti.add((spec_fs, state))
            ev(T("driver.chain_to", word=word, dest=os.path.basename(dest)[:-3]))
            entra(dest)
            ev(T("driver.chain_from", next=nx))
            prev = None
            continue
        if word == "DONE":
            return fine("DONE", nx, 0)
        if word == "WAIT":
            return fine("WAIT", nx, 3)
        if word == "STOP":
            return fine("STOP", nx, 1)
        fase = FASI.get(word)
        if not fase:
            return fine("STOP", T("driver.next_unknown", next=nx), 1)
        if launched >= max_fasi:
            return fine("STOP", T("driver.budget", n=launched, next=nx), 1)
        # 1.7.0: the size of the cycle (taglia.txt). avvio at the first launch of a new cycle; then T2, T3 and the
        # escalations E2-E5, from the files (taglia_passo). Not on a dry run: it writes.
        riapertura, pflags = "", list(flags)
        if not dry:
            verifica_taglia(run_fs, ev)   # a change since the driver's last write, before any decision
            if fase in ("plan", "test-red", "implement") and taglia_stato(run_fs) is None and not _avviato(run_fs):
                _taglia_scrivi(run_fs, "avvio", T("driver-170.avvio"))
                ev(MARCA_170 + " — " + T("driver-170.avvio"))   # driver.log: this run dir is a 1.7 cycle
            azione, perche = taglia_passo(spec_fs, run_fs, root, flags, ev,
                                          bool(out) and out[0].startswith("Plan status: APPROVED"))
            if azione == "stop":
                return fine("STOP", perche, 1)
            if azione == "riapri":   # E2: the plan phase again, with --full, before anything else
                if prev is not None and prev[0] == "PLAN" and prev[1] == state:
                    return fine("STOP", T("driver.antiloop", label=prev[2], state=state, next=nx), 1)
                word, fase, riapertura = "PLAN", "plan", perche
                ev("Next: PLAN — " + T("driver-170.e2_reopen"))
            stt = taglia_stato(run_fs)
            if fase == "fix" and stt == "piccola":   # the small size has one review round  # BUDGET-PICCOLA
                return fine("STOP", T("driver-170.fix_small"), 1)
            if fase == "plan" and (riapertura or stt == "piena"):
                pflags = [x for x in flags if x not in ("--full", "--light")] + ["--full"]
        label = _next_label(run_fs, fase)
        if dry:
            return fine("DRY-RUN", T("driver.dry", label=label, next=nx), 0)
        if cpk != "-" and os.path.isfile(cpk):
            crc, co = _run([BASH, _fw(cpk), _rel(spec_fs, root)], cwd=root, merge=True)
            last = [l for l in co.replace("\r", "").split("\n") if l.strip()]
            ev("context-pack: exit %d%s" % (crc, " · " + last[-1] if last else ""))
        piccola = not dry and taglia_stato(run_fs) == "piccola"
        riga_lotti, corsie = prepara_implement(spec_fs, run_fs, label, root, ev, una_corsia=piccola) \
            if fase == "implement" else ("", "")
        if fase == "review":   # L2 with finalize's criterion: never an absorbed counterproof that finalize rejects
            promuovi_l2(spec_fs, run_fs, ev)
        extra = ""
        if riapertura:   # 1.7.0 E2: the plan worker reopens the approved plan, in the full branch
            extra = "RIAPERTURA (driver): %s — %s\n" % (riapertura, T("driver-170.e2_reopen"))
        elif fase == "review" and piccola:
            extra = "TAGLIA (driver): piccola — %s\n" % T("driver-170.review_line")
        os.makedirs(os.path.join(run_fs, "prompts"), exist_ok=True)
        pf = os.path.join(run_fs, "prompts", label + ".md")
        with open(pf, "wb") as fh:
            fh.write(_enc(" ".join(["/maat:full-implementation-cycle", "--worker=" + fase, name] + pflags) + "\n"
                          + (riga_lotti + "\n" if riga_lotti else "") + extra))
        env = dict(os.environ)
        if corsie:
            env["FIC_CORSIE"] = _fw(corsie)
        if fase == "implement" and piccola:   # 1.7.0: the small size has a single lane
            env["FIC_LANES"] = "0"
        if not dry and taglia_stato(run_fs) is None:   # a cycle started before 1.7: no size, the flow of 1.6
            env["FIC_TAGLIA"] = "off"  # TAGLIA-OFF
        ev("▶ " + T("driver.started", label=label))
        try:
            prc = subprocess.run([BASH, _fw(rp), _rel(run_fs, root), label, _rel(pf, root)], cwd=root,
                                 stdin=subprocess.DEVNULL, env=env).returncode
        except OSError as e:
            return fine("STOP", T("driver.rp_not_launched", e=e), 1)
        verifica_taglia(run_fs, ev, label)   # the phase wrote taglia.txt, which is the driver's alone
        if fase == "plan" and taglia_stato(run_fs) is not None:   # the proof of the full branch, from this log only
            registra_prova(run_fs, label, ev)
        # T3 and the review assessment right after the phase too: a STOP that follows (anti-loop, budget) must not
        # leave an escalation unrecorded (plan_ok False: no T2 here)
        taglia_passo(spec_fs, run_fs, root, flags, ev, False)
        launched += 1
        visti.clear()   # a phase has started: the chain may have moved on
        esito = _first_line(os.path.join(run_fs, "log", label + ".esito"))
        ev("■ " + T("driver.finished", label=label, rc=prc, esito=esito or T("driver.no_esito")))
        err = os.path.join(run_fs, "log", label + ".stderr")
        if prc == 4:
            return fine("BUSY", T("driver.busy", tail=_tail(err)), 4)
        if prc == 7:
            t = _tail(err)
            return fine("WAIT", t, 3) if "WAIT — catena" in t else fine("STOP", T("driver.chain_prefix") + t, 1)
        if prc != 0:
            why = {2: T("driver.rp2"), 3: T("driver.rp3"), 5: T("driver.rp5"),
                   6: T("driver.rp6")}.get(prc) or T("driver.rp_other", rc=prc)
            return fine("STOP", "run-phase exit %d (%s): %s" % (prc, why, _tail(err)), 1)
        if re.match(RIGA_STOP, esito):
            return fine("STOP", esito, 1)
        rj = os.path.join(run_fs, "log", label + ".result.json")
        if os.path.isfile(rj):
            errs = result_errors(rj, fase)
            if errs:
                return fine("STOP", T("driver.result_invalid", label=label, errs="; ".join(errs[:3])), 1)
        if fase == "review":
            fs = ""
            rlines = _review_lines(_read(spec_fs) or "")
            for l in rlines:
                if l.startswith("Feature status:"):
                    fs = l[len("Feature status:"):].strip()
                    break
            if fs.startswith("NEEDS_VERIFICATION"):
                # pk09: the normal outcome of a cycle finished without all the evidence; exit 1 unchanged (orchestrator).
                # What remains to verify: the detail of the signature (Finalize:, otherwise Verification: PARTIAL)
                da = ""
                for l in rlines:
                    mo = re.match(r"^Finalize: NEEDS_VERIFICATION — snapshot \S+ — (.*?)(?: · \S+)?\s*$", l)
                    if mo:
                        da = mo.group(1)
                        break
                if not da:
                    for l in rlines:
                        mo = re.match(r"^Verification: PARTIAL \(finalize\.sh: (.*)\)\s*$", l)
                        if mo:
                            da = mo.group(1)
                            break
                return fine("STOP", T("driver.nv_done", what=da or T("driver.nv_no_detail")), 1)
        prev = (word, state, label)


# ─────────────────────────────────────────────────────────────── corpus fingerprint and helpers of the tests
def _hash(p):
    d = open(p, "rb").read().replace(b"\r", b"")
    return hashlib.sha256(d).hexdigest()


def _next_da_script(cs, spec_fs):
    """The lines of the script cs (FIC_CYCLE_STATE, tests only): the source of Next/State instead of our own `next`."""
    _, o = _run([BASH, _fw(cs), shown(spec_fs)])
    return _subst(o.replace("\r", "")).split("\n")


def _phase_of(label):
    """The phase of a log label (also the phase of a jsonl of the public corpus, tools/esempi-equiv/attese.sh)."""
    for key, ph in (("chiusura", "chiusura"), ("test-red", "test-red"), ("test-stage", "test-stage"),
                    ("implement", "implement"), ("review", "review"), ("fix", "fix"), ("plan", "plan")):
        if key in label:
            return ph
    return "probe"


def _git_neutro():
    """The environment of the git calls of _impronta_corpus: no configuration of the machine. --exclude-standard also
    reads the global core.excludesFile and, without it, $XDG_CONFIG_HOME/git/ignore (or ~/.config/git/ignore): both
    change from machine to machine. GIT_CONFIG_GLOBAL=/dev/null and GIT_CONFIG_NOSYSTEM=1 drop the global and system
    configuration, XDG_CONFIG_HOME on an empty folder the default ignore file; GIT_DIR and the like of the caller do
    not move the repository. Returns (env, folder to remove)."""
    vuota = tempfile.mkdtemp(prefix="fic-fingerprint-")
    env = {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE",
                                                              "GIT_CONFIG", "GIT_CONFIG_PARAMETERS")}
    env.update(GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1", XDG_CONFIG_HOME=vuota)
    return env, vuota


def _impronta_corpus(targets):
    """The fingerprint of a corpus (1.5.0): for every target (folder, or spec file: its folder) the root of its git
    repository (no repository: the folder itself, every file but .git). Of each root: the files tracked and not
    ignored (`git ls-files -co --exclude-standard`, the machine's git configuration off) plus all of .claude/ (specs,
    run dirs, maat.json: ignored by git, they are the corpus); .git excluded. One line per file,
    "<sha256 of the content without CR> <root name>/<path relative to the root>" (a tracked file missing from the
    tree: ASSENTE instead of the sha), in UTF-8 byte order of the path; the result is the sha256 of the lines (64 hex
    digits). The absolute path does not enter: the same folder elsewhere gives the same fingerprint."""
    env, vuota = _git_neutro()
    try:
        roots = []
        for t in targets:
            d = os.path.abspath(t if os.path.isdir(t) else os.path.dirname(os.path.abspath(t)))
            rc, o = _run(["git", "rev-parse", "--show-toplevel"], cwd=d, env=env)
            r = (os.path.normpath(_subst(o)), True) if rc == 0 and o.strip() else (d, False)
            if r not in roots:
                roots.append(r)
        righe = {}
        for r, git in roots:
            rels = set()
            if git:
                rc, o = _run(["git", "ls-files", "-z", "-co", "--exclude-standard"], cwd=r, env=env)
                rels.update(n for n in o.split("\0") if n)
                tops = [os.path.join(r, ".claude")]
            else:
                tops = [r]
            for top in tops:
                for d, dirs, fs in os.walk(top):
                    dirs[:] = [x for x in dirs if x != ".git"]
                    for n in fs:
                        rels.add(os.path.relpath(os.path.join(d, n), r).replace(os.sep, "/"))
            nome = os.path.basename(r.rstrip("/\\"))
            for rel in rels:
                if rel == ".git" or rel.startswith(".git/"):
                    continue
                p = os.path.join(r, rel)
                if os.path.isdir(p):   # a submodule (gitlink): not a file of the corpus
                    continue
                righe[nome + "/" + rel] = _hash(p) if os.path.isfile(p) else "ASSENTE"
    finally:
        shutil.rmtree(vuota, ignore_errors=True)
    testo = "".join("%s %s\n" % (righe[k], k) for k in sorted(righe, key=lambda s: _enc(s)))
    return hashlib.sha256(_enc(testo)).hexdigest()


def cmd_impronta(argv):
    """driver.py impronta <folder|spec.md>…: the fingerprint of a corpus (_impronta_corpus), 64 hex digits (1.5.0 as
    `equiv --impronta`; 1.6.0: a command of its own, the equivalence proof is gone)."""
    if not argv or any(a.startswith("-") for a in argv):
        return _uso()
    for t in argv:
        if not os.path.exists(t):
            print(T("driver-cmd.not_found", t=t), file=sys.stderr)
            return 2
    print(_impronta_corpus(argv))
    return 0


def _uso():
    print(T("driver-cmd.usage"), file=sys.stderr)
    return 2


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8", errors="surrogateescape", newline="\n")
    # Language (1.4.0): resolved once and exported, so plan-check.sh, cycle-state.sh, run-phase.sh and the phases
    # read the same one and never reread maat.json
    os.environ["MAAT_LINGUA"] = maat_msg.lingua()
    if not argv:
        return _uso()
    cmd, rest = argv[0], argv[1:]
    if cmd == "next":
        if len(rest) != 1 or not os.path.isfile(rest[0]):
            print(T("driver.usage_next"), file=sys.stderr)
            return 2
        sys.stdout.write("\n".join(cycle_state(rest[0])) + "\n")
        return 0
    if cmd == "run":
        return cmd_run(rest)
    if cmd == "valida":
        if len(rest) != 4:
            return _uso()
        return cmd_valida(*rest)
    if cmd == "impronta":
        return cmd_impronta(rest)
    if cmd == "righe":
        return cmd_righe(rest)
    return _uso()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
