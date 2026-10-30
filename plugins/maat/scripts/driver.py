#!/usr/bin/env python3
"""driver.py — orchestratore deterministico di /full-implementation-cycle (harness-pt14, blocco 1).

    driver.py next <spec.md>                   la tabella di ripresa: stesso output di cycle-state.sh (State/Next)
    driver.py run <spec.md> [--max-fasi N] [--dry-run] [-- <flag inoltrati alle fasi>…]
                                               la macchina a stati: next -> fase -> next … fino a DONE/STOP/WAIT
    driver.py valida <log.jsonl> <schema> <fase> <result.json>
                                               l'esito strutturato di una fase (lo stesso di run-phase.sh)
    driver.py equiv [--certifica] <cartella|spec.md>…
                                               prova di equivalenza con cycle-state.sh e con il validatore di
                                               run-phase.sh; con --certifica, se passa, scrive driver.equiv
    driver.py certificato                      stato del certificato: VALIDO (exit 0) · ASSENTE/SCADUTO (exit 1)
    driver.py righe [<tetto>]                  righe di istruzioni caricate per fase; exit 1 se il carico BASE di una
                                               supera il tetto (default 300); a parte, senza tetto, i file condizionali,
                                               il carico con la scrittura del piano (autore.md) e quello dei sotto-agenti

CATENE in `run`: un WAIT che nomina un anello fa proseguire il driver su quella spec; il DONE di un anello lo
riporta alla madre (che nomina il prossimo anello o la chiusura). Stesso budget, stesso anti-loop; un passaggio
gia' fatto senza lanci in mezzo non si ripete. Senza certificato valido (driver.equiv) `run` prende Next/State da
cycle-state.sh autonomo (FIC_CYCLE_STATE lo sostituisce nei test) e lo scrive nel log.

LOTTI E CORSIE (passo 5). Prima di un implement in formato 2 il driver rigenera la procedura dal piano, raggruppa
i blocchi in LOTTI con il contesto stimato dell'implementer sotto FIC_LOTTO_MAX (riga "LOTTI (driver): …" nel
prompt, log/<label>.lotti) e decide le corsie con blocks-independent.py (log/<label>.corsie-driver, passato a
run-phase.sh in FIC_CORSIE; run-phase.sh lancia le corsie con il suo launch_lanes). Formato 1: niente, come prima.

PROMOZIONE L2 (harness-pt15). Prima di ogni review il driver ricontrolla le controprove "assorbita" di
counterproof/mutations.json con `plan-check.sh l2` (lo stesso controllo di finalize.sh, sul codice finale): quelle
che finalize rifiuterebbe perdono "assorbita" e si eseguono davvero (promuovi_l2).

RIUSO, NON REIMPLEMENTAZIONE. Il driver sta SOPRA run-phase.sh: ogni fase parte con
`run-phase.sh <run-dir> <label> <prompt>`, che resta il solo a gestire lock (codice e per spec), guardia, hook Stop,
impronta del harness, attribuzione, gates.sh, review ∥ VERIFY, counterproof.sh, finalize.sh, catene, test-red e
corsie. Il driver aggiunge cio' che era prosa dell'orchestratore LLM (SKILL.md, «Orchestrator mode» e «Resumption»):
context-pack.sh prima di ogni fase, numerazione delle etichette, prompt della fase, lettura dell'esito, le uscite
di run-phase come STOP, NEEDS_VERIFICATION nella stessa invocazione -> STOP, anti-loop, budget di fasi.
Due parti sono portate in Python, con la prova di equivalenza (`equiv`) come condizione per usarle:
  - `next`   = la tabella di cycle-state.sh (righe 0-14, 7t/7s/11s/11b/13f, catene C1-C4), che chiama gli stessi
               script (plan-check.sh contract/basis/closed, review-surface.sh tree/check, run-phase.sh --harness-fp-confronta);
  - `valida` = il validatore dell'esito di run-phase.sh (schema phase-result, prosa e JSON: il piu' conservativo).

INVOLUCRI. cycle-state.sh e run-phase.sh restano script completi. Chiamano il driver (cycle-state.sh: `next`;
run-phase.sh: `valida`) solo se il certificato driver.equiv porta l'hash attuale di driver.py e il loro, cioe'
se l'equivalenza e' passata su QUESTI file; altrimenti restano autonomi. FIC_DRIVER=0 li forza autonomi,
FIC_DRIVER=1 li forza sul driver (test). Un driver che fallisce -> ripiego sul codice autonomo, con un AVVISO.

USCITE di `run`: 0 DONE · 1 STOP · 2 uso · 3 WAIT (catena) · 4 fase in corso o lock occupato.
Eventi: righe "driver: …" su stdout e in <run-dir>/driver.log.

Variabili: FIC_BASH (bash da usare) · FIC_RUN_PHASE (run-phase.sh al posto del vero, test) · FIC_CONTEXT_PACK
(context-pack.sh; "-" = saltato) · FIC_MAX_FASI (budget di default, 12) · FIC_DRIVER_CERT (certificato, test) ·
FIC_DRIVER_ROOT (radice del harness al posto di MAAT_ROOT: una copia mutata del plugin, controprove dei test).
Test: driver.test.sh.
"""
import datetime
import difflib
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
sys.dont_write_bytecode = True   # nessun __pycache__ sotto MAAT_ROOT (pk04a-1)
sys.path.insert(0, HERE)
import maat_paths  # noqa: E402

# ROOT = radice del HARNESS (MAAT_ROOT; FIC_DRIVER_ROOT la sostituisce: una copia mutata del plugin, controprove dei
# test). Il PROGETTO non passa da qui: e' il toplevel git della cartella della spec (run, `entra`).
try:
    ROOT = os.environ.get("FIC_DRIVER_ROOT") or maat_paths.maat_root()
except maat_paths.ErroreMaat as _e:
    sys.stderr.write("driver: %s\n" % _e)
    sys.exit(2)
HERE = os.path.join(ROOT, "scripts")   # una copia mutata (controprove dei test) usa i propri script
FC = os.path.join(ROOT, "skills", "full-implementation-cycle")   # testi della skill: child-rules.md, SKILL.md, workers/
PC = os.path.join(HERE, "plan-check.sh")
RS = os.path.join(HERE, "review-surface.sh")
CS = os.path.join(HERE, "cycle-state.sh")
RP = os.path.join(HERE, "run-phase.sh")
CPK = os.path.join(HERE, "context-pack.sh")
SCHEMA = os.path.join(ROOT, "schemas", "phase-result.schema.json")
# Deviazione PURAMENTE DIFENSIVA (nessun effetto sui casi previsti dal piano): la sua stringa in "deviazioni" comincia
# cosi'. Se tutte lo fanno la fase non si ferma per deviazione (run-phase.sh le registra, la review le giudica).
DIFENSIVA = "difensiva: "


def _cert_path():
    return os.environ.get("FIC_DRIVER_CERT") or os.path.join(HERE, "driver.equiv")


# ─────────────────────────────────────────────────────────────── utilita'
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
    if os.name == "nt":   # mai il bash.exe di WSL (System32) ne' lo stub dello Store
        for c in (shutil.which("bash"), os.environ.get("SHELL"), r"C:\Program Files\Git\usr\bin\bash.exe",
                  r"C:\Program Files\Git\bin\bash.exe"):
            if c and os.path.isfile(c) and "system32" not in c.lower() and "windowsapps" not in c.lower():
                return c
    return shutil.which("bash") or "bash"


BASH = _bash()


def _run(args, cwd=None, merge=False, env=None):
    """(codice, stdout decodificato); stderr scartato (o unito a stdout con merge)."""
    try:
        p = subprocess.run(args, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT if merge else subprocess.DEVNULL, env=env)
    except OSError:
        return 127, ""
    return p.returncode, _dec(p.stdout)


def _subst(s):
    """Come $(…) di bash: toglie le sole righe vuote in coda."""
    return s.rstrip("\n")


_SHOWN = {}


def shown(p):
    """Il percorso come lo stampa `cd … && pwd` in Git Bash (i messaggi di cycle-state.sh lo contengono)."""
    if os.name != "nt":
        return p
    if p not in _SHOWN:
        rc, o = _run(["cygpath", "-u", p])
        _SHOWN[p] = _subst(o) if rc == 0 and o.strip() else _fw(p)
    return _SHOWN[p]


_MOSTRATI = {}


def mostra(p):
    """Il percorso assoluto di uno script del harness nei messaggi, come `cygpath -m` in Git Bash: C:/… su Windows
    (i messaggi di cycle-state.sh lo contengono nella stessa forma, pk04a-1)."""
    if os.name != "nt":
        return p
    if p not in _MOSTRATI:
        rc, o = _run(["cygpath", "-m", p])
        _MOSTRATI[p] = _subst(o) if rc == 0 and o.strip() else _fw(p)
    return _MOSTRATI[p]


def _records(t):
    """I record di awk/sed: righe senza il terminatore, l'ultima anche senza a capo."""
    if not t:
        return []
    r = t.split("\n")
    if t.endswith("\n"):
        r.pop()
    return r


def _names(run_fs):
    """`ls <run>/log`: i nomi non nascosti."""
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
    """Le righe della sezione "## Review implementazione" in giu', fuori dai recinti (CR tolti)."""
    res, inf, r = [], False, False
    for l in _records(txt.replace("\r", "")):
        if FENCE.match(l):
            inf = not inf
            continue
        if inf:
            continue
        if not r and l.startswith("## Review implementazione"):
            r = True
        if r:
            res.append(l)
    return res


def _chead(path, lit):
    """Il valore della prima riga "<lit> …" sopra il piano, fuori dai recinti."""
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
        if re.match(r"## (Piano di implementazione|Review implementazione)", l):
            return ""
        if l.startswith(lit):
            return l[len(lit):].strip(" \t")
    return ""


def _cfiglie(path):
    res = []
    for s in re.findall(r"spec-[A-Za-z0-9._-]*", _chead(path, "Figlie:")):
        s = re.sub(r"\.md$", "", s)
        res.append(re.sub(r"\.$", "", s))
    return res


def _cpost(rd):
    """Il tree dell'ultimo .post-tree (etichetta di numero piu' alto) della run dir."""
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
    """La regola in codice di cycle-state.sh sul result.json: "OK|…" o "STOP|…"; "" se illeggibile."""
    try:
        d = json.load(open(p, encoding="utf-8"))
        one = lambda s: " ".join(str(s).split())[:300]
        dev = [one(x) for x in (d.get("deviazioni") or []) if str(x).strip()]
        bs = one(d.get("bloccato_su") if d.get("bloccato_su") is not None else "(assente)")
        if [x for x in dev if not x.startswith(DIFENSIVA)]:
            s = "STOP|deviazioni dichiarate (%d): %s" % (len(dev), one("; ".join(dev)))
        elif bs.lower() != "nessuno":
            s = "STOP|bloccato su: " + bs
        elif d.get("esito") != "OK":
            s = "STOP|esito %s: %s" % (d.get("esito"), one(d.get("motivo") or ""))
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


# ─────────────────────────────────────────────────────────────── next (tabella di cycle-state.sh)
def cycle_state(spec_arg):
    """Le righe che stampa cycle-state.sh <spec>, l'ultima e' "Next: …". Stessa tabella, stessi script."""
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

    # --- piano ---
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

    # --- sezione review ---
    review = _review_lines(_read(spec_fs) or "")
    has_review = bool(review)

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

    scope, excl = list_of("Scope"), list_of("Excluded")
    scope_f, excl_f = os.path.join(tmp, "scope"), os.path.join(tmp, "excl")
    for f, ls in ((scope_f, scope), (excl_f, excl)):
        with open(f, "wb") as fh:
            fh.write(_enc("".join(l + "\n" for l in ls)))

    # --- catene ---
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
                    if not re.search(rb"(?:^|\n)Figlie:", fh.read()):
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

    # --- contratto registrato dalla review ---
    hx = re.compile(r"spec [0-9a-f]{12}|plan [0-9a-f]{12}")
    contract_st = "n/a"
    if has_review:
        if not rcontract:
            contract_st = "LEGACY"
        elif hx.findall(rcontract) == hx.findall(basis_cur):
            contract_st = "FRESH"
        else:
            contract_st = "STALE"

    # --- impronta dello stato ---
    st = plan_raw + "\n" + basis_out + "\n"
    st += "".join(l + "\n" for l in review if re.match(
        r"(Review status|Feature status|Verification|Reviewed snapshot|Reviewed contract|Review rounds):", l))
    st += "".join(l + "\n" for l in scope) + "".join(l + "\n" for l in excl) + chain_state
    STATE = hashlib.sha256(_enc(st)).hexdigest()[:12]

    # --- ultima fase di codice che scrive (implement/fix) ---
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
            json_esito, json_why = "STOP", "result.json illeggibile"

    names = _names(run_fs)
    new_regime = os.path.isdir(os.path.join(run_fs, "evidence")) or any(
        re.search(r"\.result\.json(\.visto)?$", n) for n in names)
    tr_label = ""
    if has_log:
        tl = _labels(run_fs, "test-red")
        tr_label = tl[-1] if tl else ""

    # --- codice (solo per IMPLEMENTED) ---
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
                code, code_out = "UNKNOWN", "  snapshot o manifest illeggibili"
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
            out.append("Anelli precedenti: %s — stessa catena, anello precedente: ne' altri flussi ne' misti, "
                       "niente completion" % (prevf or "(nessun file)"))
            out.append("Base anello: " + ring_base if ring_base else
                       "Base anello: (assente: l'anello precedente non ha un .post-tree)")
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

    # --- decisione ---
    def harness_gap(nxt):
        # la decisione e' di run-phase.sh --harness-fp-confronta (la funzione unica dei tre lettori, pk04a-2): qui
        # non si legge il contenuto del file, si decide sulla prima parola, come cycle-state.sh
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
        rim = "bash \"%s\" --harness-fp > \"%s/harness.fp\"" % (mostra(RP), RUN)
        if w[0] == "CAMBIATO":
            return ("harness cambiato dal %s (impronta registrata %s, attuale %s): ricomincia la fase o conferma. "
                    "Rimedio: se il cambio e' voluto, %s e riprendi (prossima fase: %s); altrimenti riporta il harness "
                    "com'era" % (since, w[1], w[2], rim, nxt))
        if w[0] == "FORMATO-PRECEDENTE":
            return ("impronta di formato precedente: ciclo iniziato col harness interno (impronta registrata %s dal "
                    "%s, attuale %s). Rimedio: se il passaggio al plugin e' voluto, %s e riprendi (prossima fase: %s); "
                    "altrimenti riprendi il ciclo col harness interno" % (w[1], since, w[2], rim, nxt))
        if w[0] == "ILLEGGIBILE":
            return ("harness.fp illeggibile (vuoto o senza impronta, registrato dal %s; attuale %s). Rimedio: se il "
                    "harness attuale e' quello voluto, %s e riprendi (prossima fase: %s)" % (since, w[1], rim, nxt))
        return ("impronta del harness non calcolabile (file del plugin in %s o .claude/maat.json di %s non leggibili, "
                "oppure repository non trovato; registrata dal %s): verifica il plugin e il repository, poi riprendi"
                % (mostra(ROOT), repo or "(nessuno)", since))

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
            raise _Next("WAIT — catena: il piano dell'anello %d parte quando il piano dell'anello %d (%s) e' "
                        "APPROVED (ora: %s)" % (ring_k, ring_k - 1, pn, pst or "nessun piano"))
        if not cclosed(ring_prev):
            raise _Next("WAIT — catena: l'implement dell'anello %d aspetta l'anello %d (%s) IMPLEMENTED; il piano "
                        "puo' girare" % (ring_k, ring_k - 1, pn))
        if any(n.endswith(".pre-tree") for n in names):
            return
        if not ring_base:
            raise _Next("STOP — catena: l'anello %d (%s) non ha un .post-tree: la base dell'anello %d non e' "
                        "misurata. Decisione tua" % (ring_k - 1, pn, ring_k))
        if ring_now == ring_base:   # CONTROLLO-TREE-ANELLO
            return
        raise _Next("STOP — catena: il working tree (%s) non e' il .post-tree dell'anello %d (%s): modifiche fatte "
                    "dopo la sua chiusura, che l'anello %d si attribuirebbe. Decisione tua: riportale fuori dal tree "
                    "e riprendi; per tenerle nella catena aggiungile al touched.txt di %s e registra il tree attuale "
                    "come suo .post-tree (bash %s tree)"
                    % (ring_now or "non calcolabile", ring_k - 1, ring_base, ring_k, pn, mostra(RS)))

    def mother_next():
        n = len(figlie)
        for i, c in enumerate(figlie, 1):
            if not os.path.isfile(os.path.join(CDIR_fs, c + ".md")):
                nxt("STOP — catena: la figlia %s (anello %d/%d) non esiste: la riga Figlie: e i file devono "
                    "coincidere" % (c, i, n))
            if not cclosed(CDIR + "/" + c + ".md"):
                nxt("WAIT — catena: anello %d/%d (%s) non chiuso: il ciclo gira su quell'anello; la madre chiude "
                    "dopo l'ultimo" % (i, n, c))
        cz = _first_line(os.path.join(run_fs, "chiusura.txt"))
        if cz == "":
            nxt("CHIUSURA — %d anelli chiusi: gate full sull'albero finale contro la base della madre (base.txt del "
                "primo anello), e2e via /dev-verify se le figlie hanno [e2e-locator:" % n)
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
                nxt("DONE — catena chiusa: %d anelli IMPLEMENTED e chiusura IMPLEMENTED sul codice attuale" % n)
            nxt("CHIUSURA — codice della catena cambiato dopo la chiusura (%s): si rifa'" % (s or "illeggibile"))
        nxt("STOP — chiusura della catena non riuscita (%s): vedi %s/log/*-chiusura.*; corretto il motivo, per "
            "rilanciarla rinomina %s/chiusura.txt in chiusura.txt.visto" % (cz[len("Chiusura: "):]
                                                                          if cz.startswith("Chiusura: ") else cz,
                                                                          RUN, RUN))

    def last_ok(ph):
        if ph not in last_label or not last_esito.startswith("ESITO FASE %s: OK" % ph):
            return False
        if json_esito and json_esito != "OK":
            return False
        return last_state == STATE

    def json_stop():
        if json_esito == "STOP" and last_state and last_state == STATE:
            nxt("STOP — %s: %s (regola in codice su %s/log/%s.result.json). Decidi; per riprendere dopo la decisione "
                "(es. migrazione applicata) rinomina quel file in %s.result.json.visto: decide la riga ESITO di "
                "%s.esito (STOP -> la fase si rilancia, in completion). Una deviazione si accetta riaprendo il piano "
                "(spec cambiata), non con la rinomina" % (last_label, json_why, RUN, last_label, last_label,
                                                          last_label))

    def finalize_gap():
        if not new_regime:
            return ""
        f = line("Finalize")
        if f == "":
            return "IMPLEMENTED non firmato da finalize.sh (nessuna riga Finalize:)"
        if not f.startswith("IMPLEMENTED"):
            return "IMPLEMENTED non firmato da finalize.sh (Finalize: %s)" % f
        mm = re.match(r".*snapshot ([0-9a-f]{12})", f)
        if not mm:
            return "riga Finalize: senza l'impronta dello snapshot firmato"
        if mm.group(1) != _snap_fp(snap):
            return ("Finalize: firmata su un altro snapshot (snapshot %s), non sul Reviewed snapshot attuale"
                    % mm.group(1))
        tss = re.findall(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", f)
        ts = _epoch(tss[-1]) if tss else None
        if ts is None:
            return "riga Finalize: senza un'ora leggibile"
        rl = sorted([mm2.group(1) for n in names for mm2 in [re.match(r"^([0-9]+-[^.]*review[^.]*)\.jsonl$", n)]
                     if mm2], key=_numkey)
        if not rl:
            return ""
        rt = _mtime(log(rl[-1] + ".jsonl"))
        if rt is None:
            return "ora dell'ultima review (%s) non leggibile" % rl[-1]
        return "" if ts >= rt else "Finalize: piu' vecchia dell'ultima review lanciata (%s)" % rl[-1]

    def budget_fix():
        mn = re.match(r"([0-9]+)/3", rounds)
        mk = re.match(r".*post-approval NEEDS_CHANGES:[ \t\n\r\f\v]*([0-9]+)/1", rounds)
        if not mn or not mk:
            nxt("STOP — budget dei fix non calcolabile: riga 'Review rounds: n/3 · post-approval NEEDS_CHANGES: "
                "k/1' assente o illeggibile ('%s')" % rounds)
        n, k = int(mn.group(1)), int(mk.group(1))
        if not (n < 3 and k < 1):
            nxt("STOP — budget dei fix esaurito (Review rounds %s/3 · post-approval NEEDS_CHANGES %s/1): un fix che "
                "nessuna review vedra' non si scrive; decide una persona" % (mn.group(1), mk.group(1)))

    def attribution_gap():
        if not os.path.isfile(log(last_label + ".post-tree")):
            return last_label + " senza .post-tree"
        n = _numkey(last_label)[0]
        for nm in sorted(names):
            if not nm.endswith(".pre-tree"):
                continue
            l = nm[:-9]
            if os.path.isfile(log(l + ".post-tree")):
                continue
            head = l.split("-", 1)[0]
            if head.isdigit() and int(head) < n:
                return l + " con .pre-tree ancora aperto"
        return ""

    def to_review(msg):
        gap = attribution_gap()
        if not gap:
            nxt("REVIEW — " + msg)
        nxt("STOP — attribuzione non misurata (%s): la review non saprebbe quali file sono della feature. Con il "
            ".pre-tree: git -c core.quotePath=false diff --name-only --no-renames $(cat <pre-tree>) $(bash "
            "%s tree) >> %s/touched.txt, poi quel tree in "
            "<label>.post-tree (e' cio' che fa run-phase). Senza .pre-tree: elenca a mano in touched.txt i file "
            "della feature, poi crea il .post-tree — decisione tua" % (gap, mostra(RS), RUN))

    def test_red_gate():
        if not (fmt2 and not last_label and tests_st != "FRESH"):
            return
        if tr_label and os.path.isfile(log(tr_label + ".esito")):
            t = (_read(log(tr_label + ".esito")) or "").replace("\r", "")
            l1 = _subst(t.split("\n")[0])
            s = _subst("\n".join(r[6:] for r in _records(t) if r.startswith("state=")))
            if s and s == STATE:
                nxt("STOP — %s: test di accettazione non registrati (%s). Decidi (piano da correggere e "
                    "riapprovare, o test da rivedere): correggere i test di accettazione e' una decisione umana. Per "
                    "rilanciare la fase: rinomina %s/log/%s.esito in %s.esito.visto" % (tr_label, l1, RUN, tr_label,
                                                                                      tr_label))
        nxt("TEST-RED — piano in formato 2 approvato: test di accettazione e stub da scrivere e dimostrare rossi "
            "prima dell'implementazione")

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
        if figlie:
            mother_next()
        if has_review and not has_plan:
            nxt("STOP — sezione di review senza piano: niente da pianificare sopra un'implementazione")
        if not has_plan:
            nxt("PLAN — nessun piano")
        if plan in ("DRAFT", "NHD"):
            if has_review:
                nxt("STOP — piano riaperto (%s) dopo la review: la review esistente vale ancora? decisione tua"
                    % plan_raw)
            if plan == "DRAFT":
                nxt("PLAN — piano in DRAFT")
            nxt("STOP — decisione aperta sul piano (Plan status: NEEDS HUMAN DECISION)")
        if plan != "APPROVED":
            nxt("STOP — Plan status non riconosciuto: '%s'" % plan_raw)
        if basis == "STALE (tests)":
            nxt("STOP — test di accettazione cambiati dopo la fase test-red (Approved basis: tests): una modifica ai "
                "test di accettazione e' una deviazione, decide una persona. Se voluta: bash "
                "%s basis %s --write-tests registra l'impronta attuale; "
                "altrimenti riporta i test com'erano (%s/test-red/tests.txt)" % (mostra(PC), SPEC, RUN))
        if basis.startswith("STALE"):
            nxt("STOP — spec o piano cambiati dopo l'approvazione (%s): riapri il piano con /plan-review-cycle"
                % basis)
        if not has_review:
            test_red_gate()
            json_stop()
            if last_ok("implement"):
                to_review("implementazione finita (%s)" % last_label)
            nxt("IMPLEMENT — piano approvato, nessuna review")
        if not (rstatus + fstatus):
            nxt("REVIEW — sezione di review legacy senza righe di stato: la review fa un giro pieno")
        if rstatus.startswith("NEEDS HUMAN DECISION"):
            nxt("STOP — Review status: NEEDS HUMAN DECISION")
        if contract_st == "STALE":
            nxt("REVIEW — spec o piano cambiati dopo la review (Reviewed contract diverso): giro a scope pieno")
        tx = touched_excluded()
        if tx:
            nxt("STOP — la review ha escluso un file toccato dalla feature: %s. Rilancia /implementation-review-cycle "
                "<name>: legge touched.txt e rivede quel file (mai la promozione); oppure, se il file non e' della "
                "feature, toglilo da %s/touched.txt" % (tx, RUN))
        if rstatus.startswith("NEEDS_CHANGES"):
            json_stop()
            if last_ok("fix"):
                to_review("correzione finita (%s)" % last_label)
            budget_fix()
            nxt("FIX — Review status: NEEDS_CHANGES")
        if fstatus.startswith("NEEDS_VERIFICATION"):
            nxt("REVIEW — NEEDS_VERIFICATION: un tentativo di promozione")
        if rstatus.startswith("APPROVED") and fstatus.startswith("IMPLEMENTED"):
            if code in ("FRESH", "LEGACY"):
                fg = finalize_gap()
                if fg:
                    nxt("REVIEW — %s: nel nuovo regime lo stato finale lo firma %s (fail-closed; "
                        "vedi log/<label>.finalize)" % (fg, mostra(os.path.join(HERE, "finalize.sh"))))
            if code == "FRESH":
                nxt("DONE — codice uguale allo snapshot approvato")
            if code == "LEGACY":
                nxt("DONE — sezione senza snapshot (legacy): freschezza del codice non verificabile")
            nxt("REVIEW — codice cambiato dopo l'approvazione (%s)" % code)
        nxt("STOP — combinazione non riconosciuta: Review status '%s' · Feature status '%s'" % (rstatus, fstatus))
    except _Next as e:
        out.append("Next: " + e.msg)
    return out


# ─────────────────────────────────────────────────────────────── valida (esito strutturato di run-phase.sh)
KEYS = {"type", "enum", "required", "properties", "additionalProperties", "items", "minLength", "minimum"}
ANNOT = {"$schema", "$id", "title", "description"}
TYPES = {"object": lambda x: isinstance(x, dict), "array": lambda x: isinstance(x, list),
         "string": lambda x: isinstance(x, str), "null": lambda x: x is None,
         "boolean": lambda x: isinstance(x, bool),
         "integer": lambda x: isinstance(x, int) and not isinstance(x, bool),
         "number": lambda x: isinstance(x, (int, float)) and not isinstance(x, bool)}


def _valida_min(x, s, p):
    """Validatore minimo: le sole keyword di KEYS; una keyword sconosciuta e un errore (fail-closed)."""
    extra = sorted(set(s) - KEYS - ANNOT)
    if extra:
        return ["%s: keyword non supportata dal validatore minimo: %s" % (p, ", ".join(extra))]
    if "type" in s:
        ts = s["type"] if isinstance(s["type"], list) else [s["type"]]
        if not any(TYPES.get(t, lambda v: False)(x) for t in ts):
            return ["%s: tipo atteso %s" % (p, "|".join(ts))]
    errs = []
    if "enum" in s and x not in s["enum"]:
        errs.append("%s: valore %r fuori da %s" % (p, x, s["enum"]))
    if isinstance(x, dict):
        props = s.get("properties", {})
        errs += ["%s: manca %s" % (p, r) for r in s.get("required", []) if r not in x]
        for k, v in x.items():
            if k in props:
                errs += _valida_min(v, props[k], p + "." + k)
            elif s.get("additionalProperties") is False:
                errs.append("%s: campo non previsto %s" % (p, k))
    if isinstance(x, list) and "items" in s:
        for i, v in enumerate(x):
            errs += _valida_min(v, s["items"], "%s[%d]" % (p, i))
    if isinstance(x, str) and len(x) < s.get("minLength", 0):
        errs.append("%s: stringa piu corta di %d" % (p, s["minLength"]))
    if TYPES["number"](x) and "minimum" in s and x < s["minimum"]:
        errs.append("%s: sotto il minimo %s" % (p, s["minimum"]))
    return errs


def schema_errors(obj, schema):
    """Gli errori di obj rispetto allo schema: jsonschema se c'e', altrimenti il validatore minimo."""
    try:
        import jsonschema
    except ImportError:
        return _valida_min(obj, schema, "$")   # VALIDAZIONE-JSON
    return [e.message for e in jsonschema.validators.validator_for(schema)(schema).iter_errors(obj)]


def cmd_valida(log, schema_path, phase, out):
    """Stampa la riga ESITO (o lo STOP «uscita non valida» e, sotto, originale=<riga>) e scrive result.json se
    valido. Stesse regole, stessi byte, del validatore interno di run-phase.sh (run-phase.sh --valida)."""
    res = None
    for ln in open(log, encoding="utf-8", errors="replace"):
        try:
            ev = json.loads(ln)
        except ValueError:
            continue
        if isinstance(ev, dict) and ev.get("type") == "result":
            res = ev
        elif isinstance(ev, dict) and ev.get("subtype") == "fic_scartato":
            res = None   # review parallela scartata (harness-pt09): vale solo quello che segue
    if res is None or res.get("is_error"):
        return 0
    text = res.get("result") or ""
    lines = [l.strip() for l in text.splitlines()]
    riga = next((l for l in reversed(lines) if l.startswith("ESITO FASE")), "")

    def blocco():
        so = res.get("structured_output")
        if isinstance(so, dict):
            return so, ""
        recinti = re.findall(r"```json[ \t]*\r?\n(.*?)\r?\n[ \t]*```", text, re.S)
        if not recinti:
            return None, "nessun blocco JSON (structured_output o recinto json)"
        try:
            return json.loads(recinti[-1]), ""
        except ValueError as e:
            return None, "blocco JSON illeggibile: %s" % e

    obj, errs = blocco()
    errs = [errs] if errs else []
    if obj is not None:
        try:
            schema = json.load(open(schema_path, encoding="utf-8"))
        except (OSError, ValueError) as e:
            schema, errs = None, ["schema illeggibile: %s" % e]
        if schema is not None:
            errs = schema_errors(obj, schema)
            if not errs and obj.get("fase") != phase:
                errs = ["fase %r diversa da quella dell etichetta (%s)" % (obj.get("fase"), phase)]
    if errs:
        for e in errs:
            print("uscita non valida: " + e, file=sys.stderr)
        msg = "; ".join(errs[:3]).replace("\n", " ")
        print("ESITO FASE %s: STOP — uscita non valida: %s" % (phase, msg))
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
    if [x for x in dev if not x.startswith(DIFENSIVA)]:   # tutte "difensiva: " -> nessuno STOP per deviazione
        jstop = "deviazioni dichiarate (%d): %s" % (len(dev), "; ".join(dev))
    elif one(obj["bloccato_su"]).lower() != "nessuno":
        jstop = "bloccato su: " + one(obj["bloccato_su"])
    elif obj["esito"] != "OK":
        jstop = "esito STOP: " + one(obj["motivo"])
    jstop = jstop[:300]
    if not riga:
        print("ESITO FASE %s: %s" % (obj["fase"], ("STOP — " + jstop) if jstop else ("OK — " + one(obj["motivo"]))))
    elif jstop and re.match(r"ESITO FASE [^:]*: OK", riga):
        print("ESITO FASE %s: STOP — JSON: %s (la prosa diceva OK: vale il piu conservativo)" % (obj["fase"], jstop))
        print("originale=" + riga)
    else:
        print(riga)
    return 0


def result_errors(path, fase):
    """Il result.json di una fase conclusa, rivalidato dal driver prima di proseguire (fail-closed)."""
    try:
        obj = json.load(open(path, encoding="utf-8"))
        schema = json.load(open(SCHEMA, encoding="utf-8"))
    except (OSError, ValueError) as e:
        return ["illeggibile: %s" % e]
    errs = schema_errors(obj, schema)
    if not errs and isinstance(obj, dict) and obj.get("fase") != fase:
        errs = ["fase %r diversa da %s" % (obj.get("fase"), fase)]
    return errs


# ─────────────────────────────────────────────────────────────── lotti e corsie dell'implement (passo 5)
# STIMA del contesto di un plan-implementer (token): BASE (prompt, agente, regole, report) + TOKEN_RIGA × (righe
# del piano + LETTURE × righe dei file che il lotto scrive; un file che non esiste ancora vale NUOVO_RIGHE). Una
# stima dichiarata, non una misura: serve a non dare a un solo agente un lotto che lo porta oltre il tetto
# (FIC_LOTTO_MAX, default 150000; misurato: implementer a 597k di contesto su un piano non diviso).
TOKEN_RIGA, BASE_TOKEN, LETTURE, NUOVO_RIGHE = 12, 30000, 2, 100
BLOCCO_RX = re.compile(r"^blocco[ \t]+(\S+):[ \t]*scrive=(.*?)[ \t]*·[ \t]*dopo=(.*)$")


def _blocchi(procedura):
    """[(id, [file], [dipendenze])] dalle righe "blocco <id>: scrive=… · dopo=…" di gen/procedura.txt."""
    res = []
    for l in (_read(procedura) or "").replace("\r", "").split("\n"):
        m = BLOCCO_RX.match(l)
        if m:
            fs = [f for f in m.group(2).split(",") if f and f != "(nessuno)"]
            ds = [d for d in m.group(3).split(",") if d and d != "nessuno"]
            res.append((m.group(1), fs, ds))
    return res


def _ordine(blocchi):
    """I blocchi in un ordine che rispetta dopo: (a parita', quello del piano); un ciclo lascia l'ordine del piano."""
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
    """[(ids, stima)]: i blocchi, in ordine di dopo:, raggruppati finche' la stima resta sotto il tetto. Un blocco
    che da solo lo supera resta un lotto a se' (la stima lo dice: il piano va tagliato, non l'agente affamato)."""
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
        if l.startswith("## Piano di implementazione"):
            on = True
        elif on and l.startswith("## Review implementazione"):
            break
        n += on
    return n


def prepara_implement(spec_fs, run_fs, label, root, ev):
    """Prima di un implement in formato 2: procedura rigenerata dal piano attuale (in una cartella a parte), lotti
    dimensionati (log/<label>.lotti, riga LOTTI nel prompt) e decisione delle corsie (log/<label>.corsie-driver,
    che run-phase.sh riceve in FIC_CORSIE e usa al posto della propria: launch_lanes resta suo). Ritorna
    (riga da aggiungere al prompt | "", file delle corsie | "")."""
    tmp = tempfile.mkdtemp(prefix="fic-lotti-")
    try:
        rc, _ = _run([BASH, _fw(PC), "gen", shown(spec_fs), "--run-dir", _fw(tmp)], cwd=os.path.dirname(spec_fs))
        proc = os.path.join(tmp, "gen", "procedura.txt")
        if rc != 0 or not os.path.isfile(proc):
            ev("lotti e corsie: piano non in formato 2 (o gen non riuscito): li decide il worker, serie")
            return "", ""
        repo = os.environ.get("FIC_REPO") or root
        tetto = int(os.environ.get("FIC_LOTTO_MAX") or 150000)
        lt = lotti(proc, repo, _righe_piano(spec_fs), tetto)
        os.makedirs(os.path.join(run_fs, "log"), exist_ok=True)
        desc = " · ".join("lotto %d/%d: %s (~%dk token%s)" % (i, len(lt), ",".join(ids), st // 1000,
                                                             ", sopra il tetto" if st > tetto else "")
                          for i, (ids, st) in enumerate(lt, 1))
        with open(os.path.join(run_fs, "log", label + ".lotti"), "wb") as fh:
            fh.write(_enc("tetto=%d\n%s\n" % (tetto, desc.replace(" · ", "\n"))))
        ev("lotti: " + desc)
        riga = ("LOTTI (driver): %s. Un plan-implementer per lotto, in quest'ordine: il lotto e' il blocco di lavoro "
                "dell'agente (stima del suo contesto sotto il tetto di %dk)." % (desc, tetto // 1000))
        cf = ""
        if os.environ.get("FIC_LANES", "1") != "0":
            bi = os.environ.get("FIC_BLOCKS_INDEPENDENT") or os.path.join(HERE, "blocks-independent.py")
            p = subprocess.run([sys.executable, bi, "--root", repo, proc], stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            txt = _dec(p.stdout).replace("\r", "")
            if p.returncode > 1 or not txt.strip():
                txt = "blocks-independent: esito=serie motivo=blocks-independent.py fallito (exit %d)\n" % p.returncode
            cf = os.path.join(run_fs, "log", label + ".corsie-driver")
            with open(cf, "wb") as fh:
                fh.write(_enc(txt if txt.endswith("\n") else txt + "\n"))
            ev("corsie: " + txt.split("\n")[0])
        return riga, cf
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


L2_RIGA = re.compile(r"^L2 (\S+): (OK|NO)(?: — (.*))?$")   # la stessa regex di finalize.sh (cmd_controprove)


def promuovi_l2(spec_fs, run_fs, ev):
    """Prima di una review (harness-pt15): le controprove marcate "assorbita" (L2) in counterproof/mutations.json
    si ricontrollano con LO STESSO controllo di finalize.sh — `plan-check.sh l2` sul codice attuale — e quelle che
    non reggono (NO, o nessuna riga: finalize le rifiuterebbe) si PROMUOVONO: tolti "assorbita"/"motivo", si
    eseguono davvero. Copia di prima in mutations.json.pre-promozione, il vecchio <id>.json con esito assorbita in
    <id>.json.assorbita. Una voce gia' eseguita non torna mai assorbita. Ritorna gli id promossi."""
    mj = os.path.join(run_fs, "counterproof", "mutations.json")
    t = _read(mj)
    if not t or not re.search(r'"assorbita": *true', t):   # la stessa condizione di finalize.sh
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
        ev("L2: controprova %s non piu' assorbita, si esegue: %s" % (
            mid, s[1] if s else "condizioni non verificate (plan-check.sh l2, exit %d)" % rc))
    if not promosse:
        return []
    shutil.copyfile(mj, mj + ".pre-promozione")
    for mid in promosse:
        r = os.path.join(run_fs, "counterproof", mid + ".json")
        if re.match(r"^[\w.-]+$", mid) and os.path.isfile(r):
            os.replace(r, r + ".assorbita")
    with open(mj + ".tmp", "w", encoding="utf-8", newline="\n") as fh:   # lo stesso formato di plan-check.sh gen
        json.dump(lst, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(mj + ".tmp", mj)
    return promosse


# ─────────────────────────────────────────────────────────────── righe caricate per fase (passo 4)
# I file di istruzioni che ogni fase carica per costruzione (child-rules in --append-system-prompt, la SKILL del
# ciclo, il file del worker, la SKILL invocata): la misura del beneficio di pt14 (obiettivo <=300 righe per fase).
# I file condizionali (formato 1, ramo leggero, freschezza, gate eseguiti dal modello, controprove del worker)
# sono elencati a parte: si caricano solo su quel percorso. Gli agenti hanno il loro contesto e sono a parte.
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
# Letture fuori dal carico base, riportate a parte (non entrano nel tetto): la fase di piano legge autore.md
# quando scrive o rivede il piano (in una fase di piano nuova: sempre); i sotto-agenti hanno un contesto loro
# (il loro file di mandato + la definizione dell'agente).
LETTURE_A_PARTE = {
    "plan": [("con la scrittura del piano", ["+base", "plan-review-cycle/autore.md"]),
             ("revisore del piano", ["plan-review-cycle/revisori.md", "agents/spec-plan-reviewer.md"])],
    "test-red": [("agente", ["agents/acceptance-test-writer.md"])],
    "implement": [("implementer", ["agents/plan-implementer.md"])],
    "fix": [("implementer", ["agents/plan-implementer.md"])],
    "review": [("revisore", ["implementation-review-cycle/prompt-revisore.md", "agents/implementation-reviewer.md"])],
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
                                    "ASSENTE" if n is None else n))
            tot += n or 0
        cond = ["+%s=%s" % (c, _conta(_file_carico(c))) for c in CONDIZIONALI.get(fase, [])]
        lett = []
        for etichetta, fs in LETTURE_A_PARTE.get(fase, []):
            n = sum(_conta(_file_carico(f)) or 0 for f in fs if f != "+base") + (tot if "+base" in fs else 0)
            lett.append("%s: %d (%s)" % (etichetta, n, " ".join(("base" if f == "+base" else
                                                              "%s=%s" % (f, _conta(_file_carico(f)))) for f in fs)))
        sopra += tot > tetto
        print("righe %s: %d%s · %s%s%s" % (fase, tot, " SOPRA %d" % tetto if tot > tetto else "", " ".join(parti),
                                           (" · condizionali " + " ".join(cond)) if cond else "",
                                           "".join(" · " + x for x in lett)))
    return 1 if sopra else 0


# ─────────────────────────────────────────────────────────────── run (la macchina a stati)
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
    except ValueError:   # unita' diverse (Windows)
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
    rp = os.environ.get("FIC_RUN_PHASE") or RP
    cpk = os.environ.get("FIC_CONTEXT_PACK") or CPK
    # M1: la tabella in Python solo se l'equivalenza e' certificata per QUESTI file (come gli involucri);
    # altrimenti Next/State vengono da cycle-state.sh autonomo. FIC_DRIVER=0/1 forza, come negli involucri.
    fd = os.environ.get("FIC_DRIVER", "")
    usa_driver = fd == "1" or (fd != "0" and _cert_valido())
    spec_fs, entrati, avviso = None, set(), not usa_driver
    visti = set()   # (spec, State) da cui si e' gia' passati a un'altra spec della catena senza lanciare nulla
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
        ev("Esito driver: %s — %s" % (kind, msg))
        return code

    while True:
        if spec_fs not in entrati:
            entrati.add(spec_fs)
            if avviso:
                ev("certificato scaduto: next da cycle-state.sh (%s)" % ("FIC_DRIVER=0" if fd == "0" else
                                                                         "driver.equiv non valido per questi file"))
                avviso = False
            running = sorted(n[:-8] for n in _names(run_fs) if n.endswith(".running")
                             and not os.path.isfile(os.path.join(run_fs, "log", n[:-8] + ".exit")))
            if running:
                return fine("IN CORSO", "log/%s.running senza .exit: una fase gira ancora (o e' morta senza "
                            "chiudere); segui il suo log, oppure verifica che nessun processo viva e rimuovi il "
                            ".running" % running[-1], 4)
        out = cycle_state(spec_fs) if usa_driver else _next_da_cycle_state(spec_fs)
        state = next((l[7:] for l in out if l.startswith("State: ")), "")
        nx = out[-1][6:] if out and out[-1].startswith("Next: ") else ""
        word = nx.split(" ", 1)[0]
        ev("Next: " + nx)
        if prev is not None and word == prev[0] and state == prev[1]:  # ANTI-LOOP
            return fine("STOP", "anti-loop: la fase %s non ha cambiato lo stato (State %s prima e dopo): Next %s"
                        % (prev[2], state, nx), 1)
        # M2: la catena. WAIT che nomina un anello -> quell'anello; DONE di un anello -> la madre, che dice il
        # prossimo anello o la chiusura. Stesso budget, stesso anti-loop; un passaggio gia' fatto senza lanci
        # in mezzo non si ripete (niente giro a vuoto fra madre e anelli).
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
            ev("catena: %s — passo a %s" % (word, os.path.basename(dest)[:-3]))
            entra(dest)
            ev("catena: arrivo da %s" % nx)
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
            return fine("STOP", "Next non riconosciuto: '%s'" % nx, 1)
        if launched >= max_fasi:
            return fine("STOP", "budget del driver esaurito: %d fasi lanciate in questa invocazione (--max-fasi); "
                        "prossima: %s" % (launched, nx), 1)
        label = _next_label(run_fs, fase)
        if dry:
            return fine("DRY-RUN", "lancerei %s (%s)" % (label, nx), 0)
        if cpk != "-" and os.path.isfile(cpk):
            crc, co = _run([BASH, _fw(cpk), _rel(spec_fs, root)], cwd=root, merge=True)
            last = [l for l in co.replace("\r", "").split("\n") if l.strip()]
            ev("context-pack: exit %d%s" % (crc, " · " + last[-1] if last else ""))
        riga_lotti, corsie = prepara_implement(spec_fs, run_fs, label, root, ev) if fase == "implement" else ("", "")
        if fase == "review":   # L2 col criterio di finalize: mai una controprova assorbita che finalize rifiuta
            promuovi_l2(spec_fs, run_fs, ev)
        os.makedirs(os.path.join(run_fs, "prompts"), exist_ok=True)
        pf = os.path.join(run_fs, "prompts", label + ".md")
        with open(pf, "wb") as fh:
            fh.write(_enc(" ".join(["/maat:full-implementation-cycle", "--worker=" + fase, name] + flags) + "\n"
                          + (riga_lotti + "\n" if riga_lotti else "")))
        env = dict(os.environ)
        if corsie:
            env["FIC_CORSIE"] = _fw(corsie)
        ev("▶ %s avviata" % label)
        try:
            prc = subprocess.run([BASH, _fw(rp), _rel(run_fs, root), label, _rel(pf, root)], cwd=root,
                                 stdin=subprocess.DEVNULL, env=env).returncode
        except OSError as e:
            return fine("STOP", "run-phase.sh non lanciato: %s" % e, 1)
        launched += 1
        visti.clear()   # una fase e' partita: la catena puo' essere andata avanti
        esito = _first_line(os.path.join(run_fs, "log", label + ".esito"))
        ev("■ %s finita: exit %d · %s" % (label, prc, esito or "(nessuna riga ESITO)"))
        err = os.path.join(run_fs, "log", label + ".stderr")
        if prc == 4:
            return fine("OCCUPATO", "run-phase exit 4 (lock di codice, o lock del piano della stessa spec): %s"
                        % _tail(err), 4)
        if prc == 7:
            t = _tail(err)
            return fine("WAIT", t, 3) if "WAIT — catena" in t else fine("STOP", "catena: " + t, 1)
        if prc != 0:
            why = {2: "uso", 3: "binario claude non trovato", 5: "guardia non attiva: mai rilanciare senza",
                   6: "harness cambiato dal primo lancio del ciclo"}.get(prc, "sotto-sessione uscita %d" % prc)
            return fine("STOP", "run-phase exit %d (%s): %s" % (prc, why, _tail(err)), 1)
        if re.match(r"ESITO FASE [^:]*: STOP", esito):
            return fine("STOP", esito, 1)
        rj = os.path.join(run_fs, "log", label + ".result.json")
        if os.path.isfile(rj):
            errs = result_errors(rj, fase)
            if errs:
                return fine("STOP", "result.json di %s non valido: %s" % (label, "; ".join(errs[:3])), 1)
        if fase == "review":
            fs = ""
            rlines = _review_lines(_read(spec_fs) or "")
            for l in rlines:
                if l.startswith("Feature status:"):
                    fs = l[len("Feature status:"):].strip()
                    break
            if fs.startswith("NEEDS_VERIFICATION"):
                # pk09: l'esito normale di un ciclo finito senza tutta l'evidenza; exit 1 invariato (orchestratore).
                # Cosa resta da verificare: il dettaglio della firma (Finalize:, altrimenti Verification: PARTIAL)
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
                return fine("STOP", "ciclo finito: firma NEEDS_VERIFICATION — da verificare: %s; la promozione a "
                            "IMPLEMENTED e' di un'invocazione successiva, dopo la verifica"
                            % (da or "dettaglio non trovato nella spec (righe Finalize:/Verification:)"), 1)
        prev = (word, state, label)


# ─────────────────────────────────────────────────────────────── equivalenza e certificato
def _hash(p):
    d = open(p, "rb").read().replace(b"\r", b"")
    return hashlib.sha256(d).hexdigest()


def _want():
    return [("driver", _hash(os.path.abspath(__file__))), ("cycle-state", _hash(CS)), ("run-phase", _hash(RP))]


def _cert_valido():
    t = _read(_cert_path())
    if t is None:
        return False
    have = set(l.strip() for l in t.replace("\r", "").split("\n"))
    try:
        return all("%s %s" % (k, v) in have for k, v in _want())
    except OSError:
        return False


def _next_da_cycle_state(spec_fs):
    """Le righe di cycle-state.sh AUTONOMO (FIC_DRIVER=0): la fonte di Next/State senza certificato."""
    cs = os.environ.get("FIC_CYCLE_STATE") or CS
    _, o = _run([BASH, _fw(cs), shown(spec_fs)], env=dict(os.environ, FIC_DRIVER="0"))
    return _subst(o.replace("\r", "")).split("\n")


def _phase_of(label):
    for key, ph in (("chiusura", "chiusura"), ("test-red", "test-red"), ("test-stage", "test-stage"),
                    ("implement", "implement"), ("review", "review"), ("fix", "fix"), ("plan", "plan")):
        if key in label:
            return ph
    return "probe"


def cmd_equiv(argv):
    certifica = "--certifica" in argv
    targets = [a for a in argv if a != "--certifica"]
    if not targets or any(a.startswith("-") for a in targets):
        return _uso()
    specs = []
    for t in targets:
        if os.path.isdir(t):
            for n in sorted(os.listdir(t)):
                p = os.path.join(t, n)
                if fnmatch.fnmatchcase(n, "spec-*.md") and os.path.isfile(p) and os.path.isdir(p[:-3] + ".run"):
                    specs.append(os.path.abspath(p))
        elif os.path.isfile(t):
            specs.append(os.path.abspath(t))
        else:
            print("equiv: non trovato: %s" % t, file=sys.stderr)
            return 2
    py = os.environ.get("FIC_PY") or sys.executable   # lo stesso interprete per il driver e per --valida
    env0 = dict(os.environ, FIC_DRIVER="0", FIC_PYTHON=py)
    ds = dj = nj = 0
    for s in specs:
        _, a = _run([BASH, _fw(CS), shown(s)], env=env0)
        b = "\n".join(cycle_state(s)) + "\n"
        nm = os.path.basename(s)[:-3]
        if a == b:
            print("UGUALE %s · %s" % (nm, next((l for l in reversed(a.split("\n")) if l.startswith("Next: ")), "")))
        else:
            ds += 1
            print("DIVERSO %s" % nm)
            for l in difflib.unified_diff(a.split("\n"), b.split("\n"), "cycle-state.sh", "driver.py next", lineterm="", n=0):
                print("    " + l)
    tmp = tempfile.mkdtemp(prefix="fic-equiv-")
    try:
        for s in specs:
            run_fs = s[:-3] + ".run"
            for n in sorted(_names(run_fs)):
                m = re.match(r"^([0-9]+-[^.]*)\.jsonl$", n)
                if not m or _phase_of(m.group(1)) == "chiusura":
                    continue
                nj += 1
                jl, ph = os.path.join(run_fs, "log", n), _phase_of(m.group(1))
                o1, o2 = os.path.join(tmp, "a.json"), os.path.join(tmp, "b.json")
                for o in (o1, o2):
                    if os.path.exists(o):
                        os.remove(o)
                r1 = subprocess.run([BASH, _fw(RP), "--valida", _fw(jl), _fw(SCHEMA), ph, _fw(o1)],
                                    stdin=subprocess.DEVNULL, capture_output=True, env=env0)
                r2 = subprocess.run([py, os.path.abspath(__file__), "valida", jl, SCHEMA, ph, o2],
                                    stdin=subprocess.DEVNULL, capture_output=True)
                f1 = open(o1, "rb").read() if os.path.exists(o1) else None
                f2 = open(o2, "rb").read() if os.path.exists(o2) else None
                same = (r1.returncode == r2.returncode and r1.stdout.replace(b"\r", b"") == r2.stdout.replace(b"\r", b"")
                        and r1.stderr.replace(b"\r", b"") == r2.stderr.replace(b"\r", b"") and f1 == f2)
                if not same:
                    dj += 1
                    print("DIVERSO valida %s/log/%s: exit %d/%d · stdout %r / %r · result.json %s" % (
                        os.path.basename(run_fs), n, r1.returncode, r2.returncode, _dec(r1.stdout)[:200],
                        _dec(r2.stdout)[:200], "uguale" if f1 == f2 else "diverso"))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("equiv: spec=%d diverse=%d · jsonl=%d diversi=%d" % (len(specs), ds, nj, dj))
    if ds or dj:
        return 1
    if certifica:
        if not specs:
            print("equiv: nessuna run directory: niente da certificare", file=sys.stderr)
            return 1
        with open(_cert_path(), "wb") as fh:
            fh.write(_enc("# driver.equiv — certificato di equivalenza (harness-pt14), scritto da `driver.py equiv "
                          "--certifica`.\n# Gli involucri cycle-state.sh e run-phase.sh chiamano il driver solo se "
                          "driver.py e loro stessi hanno ancora questi hash (CR tolti).\n"))
            for k, v in _want():
                fh.write(_enc("%s %s\n" % (k, v)))
            fh.write(_enc("corpus spec=%d jsonl=%d · %s\n" % (len(specs), nj, _utc(int(
                datetime.datetime.now(datetime.timezone.utc).timestamp())))))
        print("equiv: certificato scritto: %s" % _cert_path())
    return 0


def cmd_certificato():
    t = _read(_cert_path())
    if t is None:
        print("certificato: ASSENTE (%s)" % _cert_path())
        return 1
    have = set(l.strip() for l in t.replace("\r", "").split("\n"))
    bad = [k for k, v in _want() if "%s %s" % (k, v) not in have]
    if bad:
        print("certificato: SCADUTO — hash diversi: %s (rilancia driver.py equiv --certifica)" % ", ".join(bad))
        return 1
    print("certificato: VALIDO — %s" % next((l for l in have if l.startswith("corpus ")), "corpus ?"))
    return 0


def _uso():
    print("uso: driver.py next <spec.md> | run <spec.md> [--max-fasi N] [--dry-run] [-- <flag>…] | "
          "valida <log.jsonl> <schema> <fase> <result.json> | equiv [--certifica] <cartella|spec.md>… | certificato | "
          "righe [<tetto>]",
          file=sys.stderr)
    return 2


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8", errors="surrogateescape", newline="\n")
    if not argv:
        return _uso()
    cmd, rest = argv[0], argv[1:]
    if cmd == "next":
        if len(rest) != 1 or not os.path.isfile(rest[0]):
            print("uso: driver.py next <spec-<name>.md>", file=sys.stderr)
            return 2
        sys.stdout.write("\n".join(cycle_state(rest[0])) + "\n")
        return 0
    if cmd == "run":
        return cmd_run(rest)
    if cmd == "valida":
        if len(rest) != 4:
            return _uso()
        return cmd_valida(*rest)
    if cmd == "equiv":
        return cmd_equiv(rest)
    if cmd == "certificato" and not rest:
        return cmd_certificato()
    if cmd == "righe":
        return cmd_righe(rest)
    return _uso()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
