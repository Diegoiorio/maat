#!/usr/bin/env python3
"""lingua-converti.py -- mechanical migration of Italian messages to the catalog (Maat 1.4.0, block B on).

Usage:
  python tools/lingua-converti.py apply <table>     write the catalog sections, replace the bash literals
  python tools/lingua-converti.py check <table>     every catalog entry of the table against v1.3.0
  python tools/lingua-converti.py copertura [-v] <table>...
                                                    every Italian-looking literal (scanner vocabulary, or a phrase of two
                                                    words or more) of the v1.3.0 lines the tables cite is accounted
                                                    for; a one-word literal outside the vocabulary is not seen

The table (tools/lingua-conversioni/<block>.tsv: UTF-8, LF, # comments) has one row per message site:
  key <TAB> at <TAB> pre <TAB> post <TAB> names <TAB> en
  key    the catalog key, <section>.<name>; the first row of a key is its SOURCE, the next rows with the same key
         are its TWINS (the same message at another site, bash or Python): their Italian must be identical
  at     <file>:<line>[#<n>][!<mode>] in the tree of v1.3.0 (git show v1.3.0:plugins/maat/<file>): the n-th
         string literal (default 1) that STARTS on that line. Modes:
           (none)   a .py file: the logical literal (implicit concatenation of the following string tokens);
                    a .sh file: a double-quoted (or single-quoted) bash string
           !py      the line is Python embedded in a bash file: the line alone is tokenized
           !pytail  the line is in the Python program that ends a bash file after a line #__PYTHON__ (maat-doctor.sh):
                    the program is tokenized as a .py file, so a literal continued on the next lines is whole
           !printf  a bash string that is a printf format: %s are the placeholders, not $…
           !cont    the line continues a double-quoted bash string opened above: from the start of the line
           !d       the word of the n-th ${var:-word} (or ${var:+word}) expansion of the line
           !f       the n-th Python f-string of the line (f"..." or f'...', embedded or not): every {expr} is an
                    interpolation, {{ and }} literal braces; edited by hand like the Python sites
           !sq      the n-th '...' of the line at any depth (inside $(…) too: ' · nota' of $(… && echo ' · nota')),
                    no escapes; edited by hand like the Python sites
           !aftersq the n-th bash string of the line after its first ' (a line that closes a '…' program opened
                    above: ' "$x" || die "…"); edited by hand
           !insq    the n-th bash string inside the first '…' of the line (a trap program: trap '… echo "…"' INT);
                    edited by hand
           !awk     the n-th "..." string of an awk program (inside a single-quoted bash literal): awk escapes
                    backslash-quote and backslash-backslash only, no interpolation; edited by hand like the
                    Python sites
  pre    exact text removed from the start of the literal (- = nothing), in source form (bash: as written,
         interpolations included; Python: the value, %-specifiers included, \t and \n for TAB and newline): the
         frozen part kept in the code
  post   the same at the end (- = nothing)
  names  the placeholder names, one per interpolation of the cut literal in order (bash: $x ${…} $(…) $((…));
         Python and printf: %s %d %r), space-separated (- = none); a name may repeat. name=EXPR: the value the new
         bash code passes is EXPR instead of the v1.3.0 interpolation (one with Italian inside, ${x:-testo})
  en     the English text (the default language), with the same placeholders {name}

The Italian column is never typed: `apply` extracts it from v1.3.0 (bash unescaped, interpolations -> {name},
braces doubled) and writes "key<TAB>en<TAB>it" into the section "# --- <section> (lingua-converti.py)" of
plugins/maat/scripts/lib/messages.tsv (appended if missing, replaced otherwise). In the bash files of the working
tree it replaces, on the line that still holds the v1.3.0 text (exactly once in the file), the cut part of a plain
double-quoted literal with $(msg <key> name="<interpolation>"…). Python sites and the other modes are edited by
hand: their row feeds the catalog and the check.

`check`, the control of the plan (Revisione 1, risk 3): for every row the Italian extracted again from v1.3.0 is
byte for byte the it column of the catalog, the twins give the same Italian and the en column is the table's;
the it text with the placeholders put back as the v1.3.0 interpolations (bash re-escaped, %-specifiers for Python)
and the pre/post put back appears as a literal in the code of v1.3.0; every key of the sections the table writes
comes from the table (no entry typed by hand). Exit 0 = all good, 1 = differences (listed), 2 = usage.

`copertura` (review of 1.4.0): `check` extracts again from the same coordinate, so a wrong #n that falls on another
literal of the line passes it (maat-doctor.sh:850#3 gave «, », blocks-independent.py:356#2 gave «radice»). Over all
the tables given at once (run it on the seven together): for every v1.3.0 line cited, every literal of the mode of
the row (same #n numbering) that holds Italian (italian() of tools/lingua-inventario.py) or is a phrase of two words
or more outside $(…) (the detector misses «installalo o correggi maat.json») is a row with that #n, or is frozen
whole by scripts/lib/protocol-strings.list (the residual rule of the inventory), or is declared with its reason in
tools/lingua-conversioni/non-messaggi.list (at <TAB> reason; a line that is no longer needed is an error). Two rows on
the same literal must cut disjoint parts of it (the pre/post of one holds the other), and the Italian of a row must
hold a letter. -v lists the declared literals with the declaration that covers them. Exit 0, 1 (listed) or 2.
"""
import ast
import contextlib
import io
import os
import re
import subprocess
import sys
import time
import tokenize

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, ".."))
PLUGIN = os.path.join(REPO, "plugins", "maat")
CATALOG = os.path.join(PLUGIN, "scripts", "lib", "messages.tsv")
BASE = "v1.3.0"
_SRC = {}


def die(msg):
    sys.stderr.write("lingua-converti: %s\n" % msg)
    sys.exit(2)


def base_text(rel):
    if rel not in _SRC:
        r = subprocess.run(["git", "-C", REPO, "show", "%s:plugins/maat/%s" % (BASE, rel)], capture_output=True)
        if r.returncode != 0:
            die("git show %s:plugins/maat/%s failed" % (BASE, rel))
        _SRC[rel] = r.stdout.decode("utf-8").replace("\r\n", "\n")
    return _SRC[rel]


# ---------------------------------------------------------------- bash
def _skip_sub(s, i, close):
    """Index just after the `close` matching a $( or ${ opened before i (quotes and nesting honoured)."""
    depth = 1
    while i < len(s):
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == "'" and close == ")":
            j = s.find("'", i + 1)
            i = (j if j >= 0 else len(s) - 1) + 1
            continue
        if c == '"':
            i = _dq_end(s, i + 1)
            continue
        if s.startswith("$(", i) or s.startswith("${", i):
            i = _skip_sub(s, i + 2, ")" if s[i + 1] == "(" else "}")
            continue
        if c == ("(" if close == ")" else "{"):
            depth += 1
        elif c == close:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    die("unbalanced %s in: %s" % (close, s))


def _dq_end(s, i):
    """Index just after the closing quote of a double-quoted string whose content starts at i."""
    while i < len(s):
        c = s[i]
        if c == "\\":
            i += 2
        elif c == '"':
            return i + 1
        elif s.startswith("$(", i) or s.startswith("${", i):
            i = _skip_sub(s, i + 2, ")" if s[i + 1] == "(" else "}")
        else:
            i += 1
    die("unterminated string: %s" % s)


def bash_literals(line):
    """[(kind, start, end)] of the quoted literals of a bash line: kind dq/sq, start/end = the content span."""
    out, i = [], 0
    while i < len(line):
        c = line[i]
        if c == "\\":
            i += 2
        elif c == "#" and (i == 0 or line[i - 1] in " \t;"):
            break
        elif c == "'":
            j = line.find("'", i + 1)
            if j < 0:
                die("unterminated '…' in: %s" % line)
            out.append(("sq", i + 1, j))
            i = j + 1
        elif c == '"':
            j = _dq_end(line, i + 1)
            out.append(("dq", i + 1, j - 1))
            i = j
        elif line.startswith("$(", i) or line.startswith("${", i):
            i = _skip_sub(line, i + 2, ")" if line[i + 1] == "(" else "}")
        else:
            i += 1
    return out


def bash_defaults(line):
    """[(start, end)] of the `word` of the ${var:-word} and ${var:+word} expansions of a line, in order."""
    out = []
    for m in re.finditer(r"\$\{[A-Za-z_][A-Za-z0-9_]*:[-+]", line):
        end = _skip_sub(line, m.start() + 2, "}")
        out.append((m.end(), end - 1))
    return out


def awk_strings(line):
    """[(start, end)] of the content of the "..." strings of a line of an awk program, in order."""
    out, i = [], 0
    while i < len(line):
        if line[i] == '"':
            j = i + 1
            while j < len(line) and line[j] != '"':
                j += 2 if line[j] == "\\" else 1
            out.append((i + 1, j))
            i = j + 1
        else:
            i += 1
    return out


PYTAIL = "#__PYTHON__"   # the marker line of a bash file that ends with a whole Python program (maat-doctor.sh)


FSTR = re.compile(r"""(?<![A-Za-z0-9_])[fF](["'])((?:\\.|(?!\1).)*)\1""")


def f_parts(s):
    """The content of an f-string as [('t', text) | ('v', '{expr}')]: {{ and }} are literal braces."""
    parts, buf, i = [], [], 0
    while i < len(s):
        if s.startswith("{{", i) or s.startswith("}}", i):
            buf.append(s[i])
            i += 2
        elif s[i] == "{":
            j = s.index("}", i)
            if buf:
                parts.append(("t", "".join(buf)))
                buf = []
            parts.append(("v", s[i:j + 1]))
            i = j + 1
        else:
            buf.append(s[i])
            i += 1
    if buf:
        parts.append(("t", "".join(buf)))
    return parts


def bash_parts(s, kind):
    """The content of a literal as [('t', text) | ('v', interpolation source)], unescaped."""
    if kind == "sq":
        return [("t", s)] if s else []
    parts, buf, i = [], [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s) and s[i + 1] in '$`"\\':
            buf.append(s[i + 1])
            i += 2
        elif c == "$" and i + 1 < len(s) and (s[i + 1] in "({" or s[i + 1].isalnum() or s[i + 1] in "_*@#?$!"):
            if buf:
                parts.append(("t", "".join(buf)))
                buf = []
            if s[i + 1] in "({":
                j = _skip_sub(s, i + 2, ")" if s[i + 1] == "(" else "}")
            elif s[i + 1].isdigit() or s[i + 1] in "*@#?$!":
                j = i + 2
            else:
                j = i + 1
                while j < len(s) and (s[j].isalnum() or s[j] == "_"):
                    j += 1
            parts.append(("v", s[i:j]))
            i = j
        elif c == "`":
            die("backticks not supported: %s" % s)
        else:
            buf.append(c)
            i += 1
    if buf:
        parts.append(("t", "".join(buf)))
    return parts


def bash_escape(t):
    """Literal text in a double-quoted bash string (the inverse of bash_parts on text)."""
    return re.sub(r'([$`"])', r"\\\1", t.replace("\\", "\\\\"))


# ---------------------------------------------------------------- python
def _tokens(text):
    out = []
    try:
        for t in tokenize.generate_tokens(io.StringIO(text).readline):
            out.append(t)
    except (tokenize.TokenError, IndentationError, SyntaxError):
        pass   # an embedded line with brackets closed further down: the tokens read so far are enough
    return out


def _prev_str(toks, i):
    j = i - 1
    while j >= 0 and toks[j].type in (tokenize.NL, tokenize.COMMENT):
        j -= 1
    return j >= 0 and toks[j].type == tokenize.STRING


def py_literals(text, line):
    """The values of the logical string literals starting on `line`, in order."""
    toks = _tokens(text)
    starts = [i for i, t in enumerate(toks)
              if t.type == tokenize.STRING and t.start[0] == line and not _prev_str(toks, i)]
    out = []
    for i in starts:
        group = [toks[i]]
        j = i + 1
        while j < len(toks) and toks[j].type in (tokenize.STRING, tokenize.NL, tokenize.COMMENT):
            if toks[j].type == tokenize.STRING:
                group.append(toks[j])
            j += 1
        out.append("".join(ast.literal_eval(t.string) for t in group))
    return out


def py_literal(text, line, n):
    """The value of the n-th logical string literal starting on `line`."""
    vals = py_literals(text, line)
    if len(vals) < n:
        die("line %d: %d string literal(s), #%d asked" % (line, len(vals), n))
    return vals[n - 1]


# %s %d %r, with a width and a precision (%-24s, %4d, %.2f, %.1f: block D); flags other than - are never specifiers
# here, so that a literal text «90% done» stays text
PCT = re.compile(r"%(%|-?[0-9]*(?:\.[0-9]+)?[sdrf])")


def pct_parts(s):
    parts, last = [], 0
    for m in PCT.finditer(s):
        if m.group(1) == "%":
            parts.append(("t", s[last:m.start()] + "%"))
        else:
            if m.start() > last:
                parts.append(("t", s[last:m.start()]))
            parts.append(("v", m.group(0)))
        last = m.end()
    if last < len(s):
        parts.append(("t", s[last:]))
    out = []
    for p in parts:   # adjacent text parts merged
        if out and p[0] == "t" and out[-1][0] == "t":
            out[-1] = ("t", out[-1][1] + p[1])
        else:
            out.append(p)
    return out


# ---------------------------------------------------------------- rows
def split_names(s):
    """The names cell split on the spaces outside $(…) and ${…} (an EXPR may hold spaces)."""
    out, cur, depth = [], [], 0
    for c in s:
        if c in "({":
            depth += 1
        elif c in ")}":
            depth -= 1
        if c == " " and depth == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
    out.append("".join(cur))
    return [x for x in out if x]


class Row:
    def __init__(self, n, cells):
        self.n = n
        self.key, at, pre, post, names, self.en = cells
        m = re.match(r"^(scripts/[^:#!]+):([0-9]+)(?:#([0-9]+))?(?:!(py|pytail|printf|cont|d|awk|f|sq|aftersq|insq))?$", at)
        if not m:
            die("row %d: bad at %r" % (n, at))
        self.file, self.line = m.group(1), int(m.group(2))
        self.idx = int(m.group(3) or 1)
        self.mode = m.group(4) or ("pyfile" if self.file.endswith(".py") else "")
        self.pre = "" if pre == "-" else pre
        self.post = "" if post == "-" else post
        self.names = [] if names == "-" else split_names(names)
        if self.mode in ("pyfile", "py", "pytail"):   # a Python value: \t and \n of the table are the characters
            self.pre = self.pre.replace("\\t", "\t").replace("\\n", "\n")
            self.post = self.post.replace("\\t", "\t").replace("\\n", "\n")

    def source_line(self):
        return base_text(self.file).split("\n")[self.line - 1]

    def literals(self):
        """[(kind, literal of v1.3.0 in source form)]: every literal of the line that the mode of the row counts,
        in the order of its #n (the coverage control walks them all)."""
        l = self.source_line()
        if self.mode == "pyfile":
            return [("py", v) for v in py_literals(base_text(self.file), self.line)]
        if self.mode == "py":
            return [("py", v) for v in py_literals(l.strip(), 1)]
        if self.mode == "pytail":   # the whole program after the marker, tokenized as a .py file
            lines = base_text(self.file).split("\n")
            k = lines.index(PYTAIL) + 1
            if self.line <= k:
                die("row %d: %s:%d is above %s" % (self.n, self.file, self.line, PYTAIL))
            return [("py", v) for v in py_literals("\n".join(lines[k:]), self.line - k)]
        if self.mode == "d":
            return [("dq", l[a:b]) for a, b in bash_defaults(l)]
        if self.mode == "cont":
            return [("dq", l[:_dq_end(l, 0) - 1])]
        if self.mode == "f":
            return [("f", l[a:b]) for a, b in (m.span(2) for m in FSTR.finditer(l))]
        if self.mode == "sq":
            return [("sq", l[a:b]) for a, b in (m.span(1) for m in re.finditer(r"'([^']*)'", l))]
        if self.mode == "awk":
            return [("awk", l[a:b]) for a, b in awk_strings(l)]
        k = l.index("'") + 1 if self.mode in ("aftersq", "insq") else 0   # the line closes a '…' opened above
        e = l.index("'", k) if self.mode == "insq" else len(l)   # insq: only inside the first '…' (a trap program)
        return [("printf" if self.mode == "printf" else kind, l[k + a:k + b]) for kind, a, b in bash_literals(l[k:e])]

    def family(self):
        """The literals that share the #n numbering of the row: a bash string and a printf format are counted
        together (bash_literals), every other mode by itself."""
        return (self.file, self.line, "" if self.mode == "printf" else self.mode)

    def literal(self):
        """(kind, whole literal of v1.3.0 in source form): kind dq, sq, printf, awk, f or py."""
        lits = self.literals()
        if len(lits) < self.idx:
            die("row %d: %d literal(s) of mode %r on %s:%d, #%d asked" % (self.n, len(lits), self.mode, self.file,
                                                                         self.line, self.idx))
        return lits[self.idx - 1]

    def cut(self):
        """(kind, cut literal in source form, parts)."""
        kind, s = self.literal()
        if not s.startswith(self.pre):
            die("row %d (%s): the literal does not start with %r: %r" % (self.n, self.key, self.pre, s[:80]))
        s = s[len(self.pre):]
        if self.post:
            if not s.endswith(self.post):
                die("row %d (%s): the literal does not end with %r: %r" % (self.n, self.key, self.post, s[-80:]))
            s = s[:-len(self.post)]
        if kind == "awk":
            if re.search(r'\\[^"]', s.replace("\\\\", "")):
                die("row %d: an awk escape other than backslash-quote and backslash-backslash: %r" % (self.n, s))
            return kind, s, ([("t", s.replace('\\"', '"').replace("\\\\", "\\"))] if s else [])
        if kind == "f":
            if "\\" in s:
                die("row %d: an f-string with a backslash escape: %r" % (self.n, s))
            return kind, s, f_parts(s)
        if kind in ("py", "printf"):
            if kind == "printf" and "$" in s:
                die("row %d: a printf format with $ interpolations" % self.n)
            text = s if kind == "py" else "".join(p[1] for p in bash_parts(s, "dq"))
            parts = pct_parts(text)
        else:
            parts = bash_parts(s, kind)
        return kind, s, parts

    def italian(self):
        _k, _s, parts = self.cut()
        vs = [p[1] for p in parts if p[0] == "v"]
        if len(vs) != len(self.names):
            die("row %d (%s): %d interpolation(s) %s, %d name(s)" % (self.n, self.key, len(vs), vs, len(self.names)))
        out, k = [], 0
        for p in parts:
            if p[0] == "t":
                out.append(p[1].replace("{", "{{").replace("}", "}}"))
            else:
                out.append("{%s}" % self.names[k].split("=", 1)[0])
                k += 1
        return "".join(out)


def load(table):
    rows = []
    with open(table, encoding="utf-8", newline="") as f:
        for n, l in enumerate(f.read().replace("\r", "").split("\n"), 1):
            if not l.strip() or l.startswith("#"):
                continue
            cells = l.split("\t")
            if len(cells) != 6:
                die("%s:%d: 6 cells expected, %d" % (table, n, len(cells)))
            rows.append(Row(n, cells))
    return rows


def entries(rows):
    """{key: (en, it, [rows])} in table order, and the twin disagreements."""
    res, errs = {}, []
    for r in rows:
        it = r.italian()
        if r.key not in res:
            res[r.key] = (r.en, it, [r])
            continue
        en0, it0, rs = res[r.key]
        rs.append(r)
        if it != it0:
            errs.append("%s: twin %s:%d says %r, source %s:%d says %r" % (r.key, r.file, r.line, it, rs[0].file,
                                                                          rs[0].line, it0))
        if r.en != en0:
            errs.append("%s: twin %s:%d with another en text" % (r.key, r.file, r.line))
    return res, errs


# ---------------------------------------------------------------- catalog
def read_catalog():
    with open(CATALOG, encoding="utf-8", newline="") as f:
        return f.read().replace("\r", "").split("\n")


def section_name(key):
    return key.split(".", 1)[0]


def header(sec):
    return "# --- %s (lingua-converti.py)" % sec


def write_catalog(res):
    lines = read_catalog()
    while lines and lines[-1] == "":
        lines.pop()
    secs = {}
    for k, (en, it, _rs) in res.items():
        secs.setdefault(section_name(k), []).append("%s\t%s\t%s" % (k, en, it))
    for sec, body in secs.items():
        h = header(sec)
        if h in lines:
            a = lines.index(h)
            b = a + 1
            while b < len(lines) and not lines[b].startswith("# --- "):
                b += 1
            while b > a + 1 and lines[b - 1] == "":
                b -= 1
            lines[a:b] = [h] + body
        else:
            lines += ["", h] + body
    with open(CATALOG, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


@contextlib.contextmanager
def catalog_lock():
    """The catalog is rewritten whole: two applies of different tables at once (lanes of a block) take turns."""
    lock = CATALOG + ".lock"
    for _ in range(600):
        try:
            os.mkdir(lock)
            break
        except FileExistsError:
            time.sleep(0.2)
    else:
        die("%s held for 2 minutes (a stale lock? remove it)" % lock)
    try:
        yield
    finally:
        os.rmdir(lock)


def catalog_entries():
    out = {}
    for l in read_catalog():
        if l and not l.startswith("#"):
            p = l.split("\t")
            if len(p) == 3:
                out[p[0]] = (p[1], p[2])
    return out


# ---------------------------------------------------------------- bash code
def apply_bash(rows):
    done, todo = [], {}
    for r in rows:
        if r.mode == "" and r.literal()[0] == "dq":
            todo.setdefault(r.file, []).append(r)
    for f, rs in todo.items():
        p = os.path.join(PLUGIN, f)
        with open(p, encoding="utf-8", newline="") as fh:
            text = fh.read()
        lines = {}
        for r in rs:
            lines.setdefault(r.line, []).append(r)
        for ln, lrs in lines.items():
            l = lrs[0].source_line()
            new = l
            for r in sorted(lrs, key=lambda x: -bash_literals(l)[x.idx - 1][1]):   # right to left: spans stay valid
                _kind, a, b = bash_literals(l)[r.idx - 1]
                _k, _core, parts = r.cut()
                args, k = [], 0
                for pt in parts:
                    if pt[0] == "v":
                        name, _, expr = r.names[k].partition("=")
                        args.append(' %s="%s"' % (name, expr if expr else pt[1]))
                        k += 1
                new = new[:a] + r.pre + "$(msg %s%s)" % (r.key, "".join(args)) + r.post + new[b:]
            same = [x for x in lines if lrs[0].source_line() == l and x in lines
                    and lines[x][0].source_line() == l]   # identical lines of the file, all in the table
            tl = text.split("\n")   # whole lines: «    echo x» is not a line «      echo x» (block D)
            if tl.count(l) in (1, len(same)):
                text = "\n".join(new if x == l else x for x in tl)
                done += ["%s:%d %s" % (f, ln, r.key) for r in lrs]
            elif any("msg %s" % r.key not in text for r in lrs):
                die("%s:%d: the v1.3.0 line is not (once) in the file, and its keys are not there either" % (f, ln))
        with open(p, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)
    return done


# ---------------------------------------------------------------- check
TOK = re.compile(r"(\{\{|\}\}|\{[A-Za-z_][A-Za-z0-9_]*\})")


def render(row, it):
    """The it text back in v1.3.0 source form, pre and post included."""
    kind, _s, parts = row.cut()
    srcs = [p[1] for p in parts if p[0] == "v"]
    names = [n.split("=", 1)[0] for n in row.names]
    seen = {}
    out = []
    for t in TOK.split(it):
        if t in ("{{", "}}"):
            txt = t[0]
        elif TOK.fullmatch(t) and t[1:-1] in names:
            nm = t[1:-1]
            # a repeated name takes the interpolations in order (bash: the same source; Python: the same spec)
            i = [j for j, x in enumerate(names) if x == nm][min(seen.get(nm, 0), names.count(nm) - 1)]
            seen[nm] = seen.get(nm, 0) + 1
            out.append(srcs[i])
            continue
        else:
            txt = t
        if kind == "dq":
            out.append(bash_escape(txt))
        elif kind == "py":
            out.append(txt.replace("%", "%%"))
        elif kind == "awk":
            out.append(txt.replace("\\", "\\\\").replace('"', '\\"'))
        elif kind == "f":
            out.append(txt.replace("{", "{{").replace("}", "}}"))
        elif kind == "printf":
            out.append(bash_escape(txt).replace("%", "%%"))
        else:
            out.append(txt)
    return row.pre + "".join(out) + row.post


def _pct(val):
    """A Python literal with every bare % doubled (as render writes literal text)."""
    return re.sub(r"%(?!-?[0-9]*(?:\.[0-9]+)?[sdrf]|%)", "%%", val)


def cmd_check(rows):
    errs = []
    res, e = entries(rows)
    errs += e
    cat = catalog_entries()
    for k, (en, it, rs) in res.items():
        if k not in cat:
            errs.append("%s: missing from the catalog" % k)
            continue
        if cat[k][1] != it:
            errs.append("%s: it column %r, v1.3.0 gives %r" % (k, cat[k][1], it))
        if cat[k][0] != en:
            errs.append("%s: en column differs from the table" % k)
        for r in rs:
            lit = render(r, cat[k][1])
            kind, whole = r.literal()
            ok = (lit in _pct(whole)) if kind == "py" else (lit in r.source_line())
            if not ok:
                errs.append("%s: %s:%d: the it text rendered back (%r) is not a literal of v1.3.0" % (k, r.file,
                                                                                                    r.line, lit))
    secs = {section_name(k) for k in res}
    for k in cat:
        if section_name(k) in secs and k not in res:
            errs.append("%s: in a section of the table but not in the table (typed by hand?)" % k)
    for e in errs:
        print(e)
    print("lingua-converti check: %d keys, %d rows, %d errors" % (len(res), len(rows), len(errs)))
    return 1 if errs else 0


# ---------------------------------------------------------------- coverage
NON_MESSAGES = os.path.join(HERE, "lingua-conversioni", "non-messaggi.list")
PROTOCOL_LIST = os.path.join(PLUGIN, "scripts", "lib", "protocol-strings.list")
# a phrase: two words or more. italian() of the inventory misses Italian made only of words outside its list
# («installalo o correggi maat.json», «la preparazione del modulo»: the two wrong #n of the 1.4.0 review), so a
# literal that is a phrase counts too, unless it is bash code ($(…))
PHRASE = re.compile(r"[A-Za-zÀ-ÿ]{2,}(?: +[A-Za-zÀ-ÿ'.]+)+")


def _inventory():
    """tools/lingua-inventario.py as a module (its italian() and load_list()), without writing bytecode."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("lingua_inventario", os.path.join(HERE, "lingua-inventario.py"))
    mod = importlib.util.module_from_spec(spec)
    sys.dont_write_bytecode = True
    spec.loader.exec_module(mod)
    return mod


def load_non_messages(path):
    """{(file, line, family, n): (line of the file, reason)} of the declared non-messages: at <TAB> reason, with
    the at of a table row (file:line#n!mode)."""
    out = {}
    if not os.path.isfile(path):
        return out
    with open(path, encoding="utf-8", newline="") as f:
        for n, l in enumerate(f.read().replace("\r", "").split("\n"), 1):
            if not l.strip() or l.startswith("#"):
                continue
            cells = l.split("\t")
            if len(cells) != 2 or not cells[1].strip():
                die("%s:%d: at <TAB> reason expected" % (path, n))
            r = Row(n, ["-", cells[0], "-", "-", "-", "-"])
            at = r.family() + (r.idx,)
            if at in out:
                die("%s:%d: %s declared twice" % (path, n, cells[0]))
            out[at] = (n, cells[1])
    return out


def cmd_coverage(tables, verbose):
    """Every literal with Italian of every v1.3.0 line cited by the tables is covered: by a row with its #n (the
    cut is the message, the pre/post the frozen part kept in the code), by the frozen text of
    scripts/lib/protocol-strings.list (nothing Italian left once its regexes of the file are taken out, as in
    lingua-inventario.py), or by a line of non-messaggi.list with its reason. A literal is never two overlapping
    texts (two rows on the same #n cut disjoint parts of it), and a row is never a text without a word."""
    inv = _inventory()

    def candidate(lit):
        return inv.italian(lit) or ("$(" not in lit and bool(PHRASE.search(lit)))

    plist, lerr = inv.load_list(PROTOCOL_LIST)
    if lerr:
        die("protocol-strings.list: " + "; ".join(lerr))
    rows = [r for t in tables for r in load(t)]
    nonmsg = load_non_messages(NON_MESSAGES)
    errs, declared = [], []
    by_at, fams = {}, {}
    for r in rows:
        by_at.setdefault(r.family() + (r.idx,), []).append(r)
        fams.setdefault(r.family(), r)

    def frozen(file, lit):
        """The entry of protocol-strings.list that freezes the whole Italian of the literal, or None."""
        mine = [e for e in plist if inv.fnmatch.fnmatchcase(file, e["file"])]
        for form in ('"%s"' % lit, "'%s'" % lit):   # the scanner of the inventory takes the quotes too
            left, hit = form, None
            for e in mine:
                new = e["rx"].sub(" ", left)
                if new != left:
                    hit = hit or e
                left = new
            if hit and not candidate(left):
                return hit
        return None

    used = set()
    for fam, r0 in fams.items():
        mode = "!" + fam[2] if fam[2] else ""
        for i, (_kind, lit) in enumerate(r0.literals(), 1):
            at = fam + (i,)
            where = "%s:%d#%d%s" % (fam[0], fam[1], i, mode)
            if at in by_at or not candidate(lit):
                continue
            if at in nonmsg:
                used.add(at)
                declared.append("%s %r: non-messaggi.list:%d (%s)" % (where, lit[:70], nonmsg[at][0], nonmsg[at][1]))
                continue
            e = frozen(fam[0], lit)
            if e:
                declared.append("%s %r: protocol-strings.list:%d (%s)" % (where, lit[:70], e["n"], e["reason"][:90]))
                continue
            errs.append("%s: a literal with Italian covered by no row and declared nowhere: %r" % (where, lit[:100]))
    for at, rs in by_at.items():
        lit = rs[0].literal()[1]
        spans = []
        for r in rs:
            a, b = len(r.pre), len(lit) - len(r.post)
            for (a2, b2, r2) in spans:
                if a < b2 and a2 < b:
                    errs.append("%s:%d#%d: one literal, two overlapping texts: %s (row %d) and %s (row %d)" % (
                        at[0], at[1], at[3], r2.key, r2.n, r.key, r.n))
            spans.append((a, b, r))
    for r in rows:
        if not re.search(r"[A-Za-zÀ-ÿ]", re.sub(r"\{[A-Za-z_][A-Za-z0-9_]*\}", "", r.italian())):
            errs.append("%s (row %d, %s:%d#%d): its Italian %r holds no word: not a message (a wrong #n?)" % (
                r.key, r.n, r.file, r.line, r.idx, r.italian()))
    for at, (n, _reason) in nonmsg.items():
        if at not in used:
            errs.append("non-messaggi.list:%d: %s:%d#%d is not needed (a row or protocol-strings.list covers it, it "
                        "holds no Italian, it does not exist or no table cites its line)" % (n, at[0], at[1], at[3]))
    if verbose:
        for d in declared:
            print("declared: " + d)
    for e in errs:
        print(e)
    print("lingua-converti copertura: %d tables, %d rows, %d lines, %d declared literals (%d in non-messaggi.list), "
          "%d errors" % (len(tables), len(rows), len(fams), len(declared), len(used), len(errs)))
    return 1 if errs else 0


def main(argv):
    if argv[:1] == ["copertura"]:
        v = "-v" in argv[1:]
        tables = [a for a in argv[1:] if a != "-v"]
        if not tables:
            sys.stderr.write(__doc__)
            return 2
        return cmd_coverage(tables, v)
    if len(argv) != 2 or argv[0] not in ("apply", "check"):
        sys.stderr.write(__doc__)
        return 2
    rows = load(argv[1])
    if argv[0] == "check":
        return cmd_check(rows)
    res, errs = entries(rows)
    if errs:
        print("\n".join(errs))
        return 1
    with catalog_lock():
        write_catalog(res)
    for d in apply_bash(rows):
        print("bash: " + d)
    print("lingua-converti apply: %d keys, %d rows" % (len(res), len(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
