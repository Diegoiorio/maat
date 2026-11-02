#!/usr/bin/env python3
"""lingua-inventario.py -- read-only inventory of the Italian text in the plugin scripts (Maat 1.4.0, block 0).

Usage:
  python tools/lingua-inventario.py [--root <plugin>] [--list <protocol-strings.list>] [--rows] [--json]
  python tools/lingua-inventario.py --consumers [--root <plugin>] [--json]

Default mode: every .sh/.py under the plugin (comments excluded; strings taken with the tokenizer for Python, as
quoted literals and heredoc bodies for bash, embedded Python included) is scanned; a line counts if one of its
literals holds Italian words or accents. Classes (heuristic, the same as the 1.4.0 plan inventory):
  MSG  text printed or returned as a message      READ  the line compares or filters Italian text
  INT  known protocol line                        DOC   docstring of embedded Python
Test files (*.test.sh, test-review-surface.sh) are counted apart and never classified.
RESIDUAL = the MSG/READ/INT lines that still hold Italian once the frozen parts declared in
scripts/lib/protocol-strings.list are taken out (see the header of that file for the format). Entries of the
list that cover no line are reported as unused.

--consumers: the consumer side of the migration. Every reading site (case patterns, quoted or not; grep/sed/awk;
re.*, raw strings, startswith/endswith, ==, in (...)) in scripts/, the tests, skills/ and agents/ is cut into
Italian fragments (two words or more, or a single root that is neither a code identifier nor an English word of
the comments); a fragment found in the Italian text of a different site (script literal or prompt) is a coupling.

Never writes anything. Exit 0 (2 on a usage error).
"""
import collections
import fnmatch
import io
import json
import os
import re
import sys
import tokenize

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.normpath(os.path.join(HERE, "..", "plugins", "maat"))
DEFAULT_LIST = "scripts/lib/protocol-strings.list"

# --- Italian detector (unchanged from the measurement of the plan: same numbers) ---
WORDS = r"""non il lo gli della dello dei degli delle dal dalla dai nella nel nei sul sulla che per con una uno
sono nessun nessuna nessuno manca mancante mancano assente assenti trovato trovata trovati esiste rilancia
rilanciare rinomina vedi decidi oppure anche solo senza dopo prima ancora cambiato cambiati cambiata valido valida
impronta cartella riga righe ciclo fase fasi catena anello anelli approvato eseguito esegui usa scrivi leggi vuoto
vuota uso errore avviso attenzione deviazione deviazioni corsia corsie piano spec-file illeggibile leggibile
mancata letto scritto scritta registrata registrato aperto chiuso chiusura tutti tutte questo questa quello quella
sotto sopra fuori dentro qui ora già più perché cioè ovvero quindi invece niente nulla esito rimedio controprova
controprove rossi rosso verde verdi diverso diversi diverse uguale lanciata lanciato copione installato serve
servono puoi deve devono può nuovo nuova nuovi vecchio vecchia questi stesso stessa altro altra altri cosa come
dove quando ogni""".split()
# added in block D (not in the measurement of the plan): «guardia di sessione / di fase» of guard.py and guard-hook.sh,
# as a phrase, since the bare word is also the maat.json key guardia.* that English text keeps
PHRASES = [r"guardia d(?:i|el|ella)"]
IT = re.compile(r"[àèéìòùÀÈÉÌÒÙ]|\b(?:%s)\b|\b(?:e|piu|gia|perche|puo|c|l|dell|un|nell|all|sull|quest)'(?=\s|$|[a-z])" %
                "|".join([re.escape(w) for w in WORDS] + PHRASES), re.I)
# too ambiguous alone: one of these needs a second hit
WEAK = {"uso", "solo", "come", "dove", "piano", "fase", "spec-file", "verde", "rosso", "esito", "corsia"}

OUT_SH = re.compile(r"\b(echo|printf|die|die_usage|stop|say|warn|warn_line|next|ring_stop|errore|fail|json_stop|"
                    r"review_info|lint_msgs|ev|err|tee|cat\s*<<|read -r)\b|>&2")
OUT_PY = re.compile(r"\b(print|sys\.exit|exit|die|fail|stop|ev|warn|err|log|out|write|raise|_p|say|msg|reason)\b")
INTERNAL = re.compile(r"Recorded:|Catena: |Chiusura: |\b(assente|chiuso|aperto);|rossi: esito|gates: esito|"
                      r"posteriori: esito|UGUALE|CAMBIATO|Impronta piano|: scrive=|^\s*L2 |Base anello|Anelli precedenti|"
                      r"Diff anello|originale=|state=|DEVIAZIONI DIFENSIVE|S2: |Percorso:|Scheletro:")
READ_ALTS = [r"\bgrep\b", r"\bsed -n\b", r"\bsed '", r"\bcase\b.*\bin\b", r"\*\)", r"\bawk\b",
             r"\bre\.(?:compile|match|search|sub|findall|fullmatch)\b", r"startswith", r"endswith", r"==\s*[\"']",
             r"[\"']\s*==", r"\bin \(", r"\bin \[", r"=~", r"index\(\$", r"/\^", r"\\\|", r"\(\?:", r"\bnot in\b"]
READ = re.compile("|".join(READ_ALTS))
SQ = re.compile(r'"(?:[^"\\]|\\.)*"|\'[^\']*\'')


def italian(s):
    hits = [m.group(0).lower() for m in IT.finditer(s)]
    if not hits:
        return False
    strong = [h for h in hits if h.strip("'") not in WEAK]
    return bool(strong) or len(set(hits)) >= 2


def is_test(rel):
    return rel.endswith(".test.sh") or rel.endswith("test-review-surface.sh")


# --- scanners: rows = (line number, line, kind, [Italian segments]) ---
def scan_sh(text):
    rows = []
    heredoc = kind = None
    for n, line in enumerate(text.splitlines(), 1):
        st = line.strip()
        if heredoc:
            if st == heredoc:
                heredoc = None
                continue
            if st.startswith("#"):
                continue
            segs = SQ.findall(line) or ([line] if kind == "text" else [])
            its = [s for s in segs if italian(s)]
            if its:
                rows.append((n, line, "heredoc-" + kind, its))
            continue
        m = re.search(r"<<-?\s*['\"]?([A-Za-z_]+)['\"]?", line)
        if st.startswith("#"):
            continue
        code = re.sub(r"\s#\s.*$", "", line) if not re.search(r"['\"][^'\"]*\s#", line) else line
        its = [s for s in SQ.findall(code) if italian(s)]
        if its:
            rows.append((n, line, "out" if OUT_SH.search(code) else "assign/other", its))
        if m and "<<<" not in line:
            heredoc = m.group(1)
            kind = "py" if re.search(r"python|FIC_PY|PY\b|py -3", line) or heredoc == "PY" else "text"
    return rows


def py_strings(text):
    """(line, token string, is_docstring) for every string token; None if the file does not tokenize."""
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, SyntaxError, IndentationError):
        return None
    out, prev = [], None
    fsm = getattr(tokenize, "FSTRING_MIDDLE", None)
    for i, t in enumerate(toks):
        if t.type == tokenize.STRING or (fsm is not None and t.type == fsm):
            is_doc = prev in (None, tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT, tokenize.NL) and \
                i + 1 < len(toks) and toks[i + 1].type in (tokenize.NEWLINE, tokenize.ENDMARKER)
            out.append((t.start[0], t.string, is_doc))
        if t.type not in (tokenize.COMMENT, tokenize.NL):
            prev = t.type
    return out


def scan_py(text):
    lines = text.splitlines()
    strs = py_strings(text)
    if strs is None:
        return [(0, "TOKENIZE ERROR", "err", [])]
    rows = collections.OrderedDict()
    for n, s, is_doc in strs:
        if is_doc or not italian(s):
            continue
        ln = lines[n - 1]
        if n not in rows:
            rows[n] = (n, ln, "out" if OUT_PY.search(ln) else "assign/other", [])
        rows[n][3].append(s)
    return list(rows.values())


def classify(line):
    body = line.strip()[:220]   # the measurement of the plan looked at the first 220 characters
    if INTERNAL.search(line):
        return "INT"
    if '"""' in body:
        return "DOC"
    if READ.search(body):
        return "READ"
    return "MSG"


def walk(root, exts):
    for dp, dn, fn in os.walk(root):
        dn[:] = sorted(d for d in dn if d != "__pycache__" and not d.startswith("."))
        for f in sorted(fn):
            if f.endswith(exts):
                p = os.path.join(dp, f)
                yield os.path.relpath(p, root).replace("\\", "/"), p


def read(p):
    with open(p, encoding="utf-8", errors="replace", newline="") as fh:
        return fh.read().replace("\r\n", "\n")


def inventory(root):
    """{rel: [row dict]} for the production files; number of Italian rows in the test files."""
    prod, tests = collections.OrderedDict(), 0
    for rel, p in walk(root, (".sh", ".py")):
        text = read(p)
        rows = scan_sh(text) if rel.endswith(".sh") else scan_py(text)
        if is_test(rel):
            tests += len(rows)
            continue
        prod[rel] = [{"line": n, "text": l, "kind": k, "segments": segs, "class": classify(l)}
                     for n, l, k, segs in rows]
    return prod, tests


# --- protocol-strings.list ---
def load_list(path):
    entries, errors = [], []
    if not os.path.isfile(path):
        return entries, ["list not found: %s" % path]
    for n, raw in enumerate(read(path).split("\n"), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        parts = raw.split("\t")
        if len(parts) != 3 or not all(x.strip() for x in parts):
            errors.append("%d: expected file<TAB>regex<TAB>reason" % n)
            continue
        try:
            rx = re.compile(parts[1])
        except re.error as e:
            errors.append("%d: bad regex (%s)" % (n, e))
            continue
        entries.append({"n": n, "file": parts[0], "regex": parts[1], "rx": rx, "reason": parts[2], "used": 0})
    return entries, errors


def residual(prod, entries):
    res = collections.OrderedDict()
    for rel, rows in prod.items():
        mine = [e for e in entries if fnmatch.fnmatchcase(rel, e["file"])]
        left = []
        for r in rows:
            if r["class"] == "DOC":
                continue
            segs, hit = list(r["segments"]), set()
            for e in mine:
                new = [e["rx"].sub(" ", s) for s in segs]
                if new != segs:
                    hit.add(e["n"])
                segs = new
            if any(italian(s) for s in segs):
                left.append(r)
            for e in mine:
                if e["n"] in hit:
                    e["used"] += 1
        res[rel] = left
    return res


# --- consumer side ---
LETTERS = "A-Za-zÀ-ÖØ-öø-ÿ"
RUN = re.compile(r"[%s][%s' :—]*[%s]|[%s]{4,}" % (LETTERS, LETTERS, LETTERS, LETTERS))
WORD = re.compile(r"[%s]+" % LETTERS)
MD_QUOTED = re.compile(r"`([^`]+)`|«([^»]+)»|\"([^\"\n]{3,})\"")


def code_vocabulary(root):
    """Identifiers outside literals and the words of the comments (English since 1.2.0): a single word in
    one of these sets is not an Italian root."""
    vocab = set(("case esac then else elif done while until select function local return printf echo grep sed awk "
                 "tr cut head tail sort paste find xargs").split())
    for rel, p in walk(root, (".sh", ".py")):
        text = read(p)
        for line in text.split("\n"):
            st = line.strip()
            if st.startswith("#"):
                # the English of the comments, without what they quote (`libero`, «…», "…": Italian tokens)
                st = re.sub(r"`[^`]*`|«[^»]*»|\"[^\"]*\"", " ", st)
                vocab.update(w.lower() for w in WORD.findall(st))
                continue
            # bash identifiers only (variables, assignments, functions): unquoted case patterns are text
            code = SQ.sub(" ", line)
            for m in re.finditer(r"\$\{?#?(\w+)|\b(\w+)\+?=|\b(\w+)\(\)|\blocal\s+([\w ]+)|\bfor\s+(\w+)\s+in\b", code):
                for g in m.groups():
                    if g:
                        vocab.update(w.lower() for w in g.split())
        if rel.endswith(".py"):
            try:
                vocab.update(t.string.lower() for t in tokenize.generate_tokens(io.StringIO(text).readline)
                             if t.type == tokenize.NAME)
            except (tokenize.TokenError, SyntaxError, IndentationError):
                pass
    return vocab


def fragments(text, vocab):
    out = set()
    for run in RUN.findall(text):
        run = " ".join(run.replace("'", "' ").split()).replace("' ", "'")
        ws = run.split()
        if len(ws) >= 2 and italian(run):
            out.add(run)
        for w in ws:
            w0 = w.strip("':—")
            if w0.lower() in vocab:
                continue
            if len(w0) >= 5 if w0.isupper() else len(w0) >= 4:   # a root, or an all-caps keyword (OCCUPATO)
                out.add(w0)
    return out


LIT = re.compile(r"""(?<![\w\\])([rRbBuUfF]{0,2})("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')""")
LIT_BEFORE = re.compile(r"""(?:\b(?:startswith|endswith|compile|match|search|fullmatch|findall|sub|split|index)\(\(?"""
                        r"""|==|!=|\bin\s*[\(\[]?|\bnot in\s*[\(\[]?|=~|\$\d+\s*[!=]=|\bgrep\b[^|;]*|"""
                        r"""\bsed\b[^|;]*|\bawk\b[^|;]*)\s*$""")
LIT_AFTER = re.compile(r"\s*(?:==|!=)")
TRAIL = re.compile(r"""(?:[rRbBuUfF]{0,2}(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'))\s*[,|]\s*$""")
PAT = r"""((?:"[^"]*"|'[^']*'|[^\s()"';|$])+(?:\|(?:"[^"]*"|'[^']*'|[^\s()"';|])+)*)\)(\s|$)"""
CASE_HEAD = re.compile(r"\bcase\b.*?\bin\s+" + PAT)
CASE_ARM = re.compile(r"(?:^\s*\(?|;;\s*)" + PAT)
QUOTED_ONLY = re.compile(r"""^(?:"[^"]*"|'[^']*')$""")
GREP_ARG = re.compile(r"""\bgrep\b(?:\s+-[A-Za-z]+)*\s+(?:-e\s+|--\s+)?([^\s"'|;)]+)""")


def pattern_texts(line, bash=True):
    """The parts of a code line that are read as patterns: case patterns (quoted or not), unquoted grep
    patterns, and the literals used as a regex, a prefix, a comparison or a member of a tuple compared."""
    out = []
    if bash:
        for rx in (CASE_HEAD, CASE_ARM):
            for m in rx.finditer(line):
                p = m.group(1)
                # a quoted string closing a call at the end of a line is Python (embedded), not an arm
                if p in ("*", "-*") or p.startswith("$") or (QUOTED_ONLY.match(p) and not line[m.end():].strip()):
                    continue
                out.append(p)
    out += GREP_ARG.findall(line)
    for m in LIT.finditer(line):
        pre, lit = m.group(1), m.group(2)
        before = line[:m.start()]
        while TRAIL.search(before):
            before = TRAIL.sub("", before)
        if "r" in pre.lower() or LIT_BEFORE.search(before) or LIT_AFTER.match(line[m.end():]):
            out.append(lit[1:-1])
    return out


def reader_sites(root, vocab):
    """(site, fragment, is_test) for the reading sites of scripts, tests, skills and agents."""
    sites = []
    for rel, p in walk(root, (".sh", ".py")):
        test = is_test(rel)
        for n, line in enumerate(read(p).split("\n"), 1):
            st = line.strip()
            if not st or st.startswith("#"):
                continue
            code = re.sub(r"\s#\s.*$", "", line) if not re.search(r"['\"][^'\"]*\s#", line) else line
            frs = set()
            for pt in pattern_texts(code, rel.endswith(".sh")):
                frs |= fragments(pt, vocab)
            for fr in sorted(frs):
                sites.append(("%s:%d" % (rel, n), fr, test))
    for sub in ("skills", "agents"):
        for rel, p in walk(os.path.join(root, sub), (".md",)):
            for n, line in enumerate(read(p).split("\n"), 1):
                for m in MD_QUOTED.finditer(line):
                    q = next(g for g in m.groups() if g)
                    for fr in fragments(q, vocab):
                        if " " in fr or fr.isupper():
                            sites.append(("%s/%s:%d" % (sub, rel, n), fr, False))
    return sites


def producer_texts(root, prod):
    """(site, text): the Italian literals of the scripts and the lines of the prompts."""
    out = []
    for rel, rows in prod.items():
        for r in rows:
            if r["class"] != "DOC":
                out.append(("%s:%d" % (rel, r["line"]), " ".join(r["segments"])))
    for sub in ("skills", "agents"):
        for rel, p in walk(os.path.join(root, sub), (".md",)):
            for n, line in enumerate(read(p).split("\n"), 1):
                if italian(line):
                    out.append(("%s/%s:%d" % (sub, rel, n), line))
    return out


def consumers(root, prod):
    vocab = code_vocabulary(root)
    sites = reader_sites(root, vocab)
    texts = producer_texts(root, prod)
    pats = {}
    found = collections.OrderedDict()
    for site, fr, test in sites:
        # an all-caps keyword is matched as written (RILANCIA is not «rilanciarla»), the rest ignoring case
        rx = pats.get(fr) or pats.setdefault(fr, re.compile(r"(?<![%s])%s" % (LETTERS, re.escape(fr)),
                                                            0 if fr.isupper() else re.I))
        hits = [ps for ps, t in texts if ps != site and rx.search(t)]
        if not hits:
            continue
        key = (site, fr)
        found[key] = {"reader": site, "fragment": fr, "test": test, "producers": hits}
    return list(found.values())


# --- output ---
def main(argv):
    args = list(argv)
    def opt(name, default=None):
        if name in args:
            i = args.index(name)
            if i + 1 >= len(args):
                sys.exit(2)
            v = args[i + 1]
            del args[i:i + 2]
            return v
        return default
    def flag(name):
        if name in args:
            args.remove(name)
            return True
        return False
    if flag("-h") or flag("--help"):
        print(__doc__)
        return 0
    root = os.path.abspath(opt("--root", DEFAULT_ROOT))
    lpath = opt("--list")
    as_json, rows_out, cons = flag("--json"), flag("--rows"), flag("--consumers")
    if args:
        print("unknown arguments: %s" % " ".join(args), file=sys.stderr)
        return 2
    lpath = os.path.abspath(lpath) if lpath else os.path.join(root, DEFAULT_LIST)
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    prod, tests = inventory(root)

    if cons:
        cs = consumers(root, prod)
        if as_json:
            print(json.dumps(cs, ensure_ascii=False, indent=1))
            return 0
        for c in cs:
            if not c["test"]:
                print("%s  «%s»  <- %s" % (c["reader"], c["fragment"], ", ".join(c["producers"][:8]) +
                                           (" (+%d)" % (len(c["producers"]) - 8) if len(c["producers"]) > 8 else "")))
        nt = sum(1 for c in cs if c["test"])
        print("consumers: %d reading sites outside the tests, %d in the tests" % (len(cs) - nt, nt))
        return 0

    entries, lerr = load_list(lpath)
    res = residual(prod, entries)
    tot = collections.Counter()
    per = collections.OrderedDict()
    for rel, rows in prod.items():
        c = collections.Counter(r["class"] for r in rows)
        tot.update(c)
        per[rel] = {k: c[k] for k in ("MSG", "READ", "INT", "DOC")}
        per[rel]["residual"] = len(res[rel])
    rtot = sum(len(v) for v in res.values())
    unused = [e for e in entries if not e["used"]]
    if as_json:
        print(json.dumps({
            "root": root, "list": lpath, "list_errors": lerr,
            "totals": {k: tot[k] for k in ("MSG", "READ", "INT", "DOC")},
            "test_rows": tests, "residual_total": rtot, "files": per,
            "residual": {rel: [{"line": r["line"], "class": r["class"], "text": r["text"].strip()} for r in rows]
                         for rel, rows in res.items() if rows},
            "unused_entries": [{"n": e["n"], "file": e["file"], "regex": e["regex"]} for e in unused],
        }, ensure_ascii=False, indent=1))
        return 0
    print("%-46s %5s %5s %5s %5s %9s" % ("file", "MSG", "READ", "INT", "DOC", "residual"))
    for rel, v in sorted(per.items(), key=lambda kv: (-sum(kv[1][k] for k in ("MSG", "READ", "INT", "DOC")), kv[0])):
        if any(v.values()):
            print("%-46s %5d %5d %5d %5d %9d" % (rel, v["MSG"], v["READ"], v["INT"], v["DOC"], v["residual"]))
    print("%-46s %5d %5d %5d %5d %9d" % ("TOTAL", tot["MSG"], tot["READ"], tot["INT"], tot["DOC"], rtot))
    print("test files: %d rows with Italian (not classified)" % tests)
    print("list: %s · %d entries · %d unused%s" % (os.path.relpath(lpath, root).replace("\\", "/"), len(entries),
                                                  len(unused), " · errors: " + "; ".join(lerr) if lerr else ""))
    for e in unused:
        print("  unused entry, line %d: %s\t%s" % (e["n"], e["file"], e["regex"]))
    if rows_out:
        for rel, rows in res.items():
            for r in rows:
                print("%s:%d:[%s] %s" % (rel, r["line"], r["class"], r["text"].strip()[:200]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
