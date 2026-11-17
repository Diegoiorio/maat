"""nomi_test.py — the names of the tests (Maat 1.8.0, D1-bis): one rule shared by plan-check.sh (rossi: py_claim,
vt_claim) and counterproof.sh (classify_pytest, classify_vitest), IMPORTED with importlib like maat-config.py, never
copied.

relazione(nome_piano, nome_caso, separatori, segmenti=None) -> "uguale" | "discendente" | "antenato" | "altro": how a
case of the report (a JUnit testcase, a vitest test) stands to the test the plan names.
- The names are split into LEVELS by the separators of the language of the test file (separatori()): `.go` -> `/`
  (a space of the plan is written `_`, as `go test` does), `.py` -> `[` (parameters), `.rs` -> nothing more; every
  other file (`.bats`, Java...) -> only `[`, so a bats name like "parses a/b" is not the parent of "parses a/b c". `::`
  is always a level: it is how the callers join the file, the classes and the name of a JUnit case
  (`<file>::<Class>::<name>`). A module may declare its own (`moduli[].separatori_test` of maat.json) for an adapter
  that does not follow its language.
- With `segmenti` (vitest: ancestorTitles + title, or the segments of a FAIL block) the case is that structured
  chain, never a string split on spaces: "parse" is not the parent of "parse empty". The plan name is split on " > "
  (the separators passed); the full -t name ("describe it", joined by a space) is still `uguale`.
- `uguale`: the levels of the plan are the last levels of the case (the plan may omit the file and the classes);
  `discendente`: they are a run of levels of the case, not at its end (the case is a subtest, a parameter, a method of
  the class the plan names); `antenato`: the case ends with the first levels of the plan, not all of them (an adapter
  that folds the subtests into the parent); otherwise `altro`.

How the callers use it (spec D1-bis): `uguale` and `discendente` are the test (their texts joined in the order of the
report: one red descendant is enough, as in `go test`); `antenato` is claimed, never a conflict, and its text counts
only if there is no `uguale`/`discendente` case and it holds the leaf of the plan name (foglia()).

SIMBOLO_MANCANTE: the messages of a missing symbol per language (a compilation or import error that a stub would
cure): Go, Rust, TypeScript/JavaScript, Python, Java. simbolo_mancante(testo, extra) -> the first match or None.
"""
import os
import re

SEP_LINGUA = {".go": ["/"], ".py": ["["], ".rs": []}
SEP_ALTRI = ["["]
UNIONE = "::"   # the join of file, classes and name in a JUnit id: always a level
SEP_VITEST = [" > "]
SEP_AMMESSI = ("/", "::", "[")   # moduli[].separatori_test: the enum of maat-config.schema.json


def separatori(percorso, dichiarati=None):
    """the separators of the levels for the test file `percorso` (its extension), or the declared ones of the module
    (only among SEP_AMMESSI, as the schema of maat.json says: anything else is a ValueError, fail-closed)"""
    if dichiarati:
        fuori = [x for x in dichiarati if not isinstance(x, str) or x not in SEP_AMMESSI]
        if fuori:
            raise ValueError("separatori_test: %r not among %s" % (fuori, " ".join(SEP_AMMESSI)))
        s = list(dichiarati)
    else:
        s = list(SEP_LINGUA.get(os.path.splitext(percorso or "")[1].lower(), SEP_ALTRI))
    if UNIONE not in s:
        s.append(UNIONE)
    return s


def dividi(nome, separatori):
    """the levels of a name: split on every separator (the longest first), empty levels dropped"""
    seps = sorted(set(separatori), key=len, reverse=True)
    if not seps:
        return [nome.strip()] if nome.strip() else []
    parti = re.split("|".join(re.escape(x) for x in seps), nome or "")
    return [x.strip() for x in parti if x.strip()]


def _forma(separatori):
    go = "/" in separatori   # go test writes the space of a subtest name as _
    return (lambda x: x.replace(" ", "_")) if go else (lambda x: x)


def relazione(nome_piano, nome_caso, separatori, segmenti=None):
    f = _forma(separatori)
    P = [f(x) for x in dividi(nome_piano or "", separatori)]
    C = [f(x.strip()) for x in segmenti if x.strip()] if segmenti is not None else [f(x) for x in dividi(nome_caso or "", separatori)]
    if not P or not C:
        return "altro"
    n, m = len(P), len(C)
    if n <= m and C[m - n:] == P:   # RELAZIONE-UGUALE
        return "uguale"
    if segmenti is not None and (nome_piano or "").strip() in {" ".join(C[k:]) for k in range(m)}:
        return "uguale"   # the full -t name of vitest, joined by a space: equality only
    for k in range(0, m - n):   # RELAZIONE-DISCENDENTE
        if C[k:k + n] == P:
            return "discendente"
    for j in range(min(n - 1, m), 0, -1):   # RELAZIONE-ANTENATO
        if C[m - j:] == P[:j]:
            return "antenato"
    return "altro"


def foglia(nome_piano, separatori):
    """the last level of the plan name, in the form of the report (Go: spaces as _)"""
    P = dividi(nome_piano or "", separatori)
    return _forma(separatori)(P[-1]) if P else ""


# The messages of a missing symbol (D4): a red at the base that a stub would cure, never a proof. One table, extensible
# from maat.json (the caller passes the module's own regexes as `extra`).
SIMBOLO_MANCANTE = {
    "go": [r"undefined: (\w+)", r"has no field or method (\w+)"],
    "rust": [r"error\[E0425\]", r"error\[E0599\]", r"error\[E0432\]", r"error\[E0433\]"],
    "ts": [r"TS2305", r"TS2339", r"TS2304", r"does not provide an export named"],
    "python": [r"cannot import name", r"has no attribute"],
    "java": [r"cannot find symbol"],
}


def simbolo_mancante(testo, extra=()):
    """(language, regex, matched text) of the first message of a missing symbol in `testo`, or None. A regex of
    maat.json that does not compile is skipped (maat-config valida says it)"""
    for lingua, regs in list(SIMBOLO_MANCANTE.items()) + [("maat.json", list(extra or ()))]:
        for r in regs:
            try:
                m = re.search(r, testo or "")
            except (re.error, TypeError):
                continue
            if m:
                return lingua, r, m.group(0)
    return None


# The red a plan declares «on the base» is an assertion, never a compilation or import error (D4.4): lint2 refuses a
# `red if` that matches SIMBOLO_MANCANTE or the way a plan writes it («MaxDepth undefined», «Decoder.MaxDepth
# undefined»: an identifier that starts with a capital letter or has a dot, then «undefined»; not «got undefined»).
# (B12-B13 review) in compiler-message shape only: «<identifier> undefined» as the whole red (after `rosso se:`, a
# backtick, a colon, at the end of it), «'<name>' is not defined»; «Expected undefined to be 3» is an assertion
ROSSO_COMPILAZIONE = [r"(?:^|[`:]|rosso se|red if)\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*[ \t]+undefined)[ \t]*(?:[`.;,)]|$)",
                      r"['\"][A-Za-z_]\w*['\"] is not defined\b",
                      r"\b(?:does not|doesn't|won't|will not|fails to) compile\b", r"\bnon compila\b",
                      r"\bcompil(?:e|ation) error\b", r"\berrore di compilazione\b"]


def rosso_di_compilazione(testo, extra=()):
    """the matched text when a declared red is a compilation / import error (SIMBOLO_MANCANTE, ROSSO_COMPILAZIONE), or
    None"""
    m = simbolo_mancante(testo, extra)
    if m:
        return m[2]
    for r in ROSSO_COMPILAZIONE:
        mm = re.search(r, testo or "")
        if mm:
            return mm.group(1) if mm.groups() else mm.group(0)
    return None


# Additive stubs in EXISTING files (D4.1). On the diff `git diff -w --ignore-blank-lines` of a `stub` file, every removed
# line must be a LIST INSTRUCTION that grows: it matches the table of its language and, in the same hunk, an added
# line equals it except tokens inserted inside its LAST pair of brackets ((), [], {}), the inserted tokens only
# identifiers, «,» and quoted names. Everything else (a signature, a condition, a return, a call) is not additive.
# (B12-B13 review) every alternative ends on a word boundary; JS/TS only the list forms (`export {…}`, `export type {…}`,
# `import {…} from …`, `import x, {…} from …`), never `export function`/`export const` (a declaration)
_ELENCO_JS = r"^\s*(?:export\s*(?:type\s*)?\{|import\s*(?:type\s+)?(?:[A-Za-z_$][\w$]*\s*,\s*)?\{[^}]*\}\s*from\b)"
ISTRUZIONE_ELENCO = {
    ".ts": _ELENCO_JS, ".tsx": _ELENCO_JS, ".js": _ELENCO_JS, ".jsx": _ELENCO_JS, ".mjs": _ELENCO_JS, ".cjs": _ELENCO_JS,
    ".mts": _ELENCO_JS, ".cts": _ELENCO_JS,
    ".py": r"^\s*(?:from\s+[\w.]+\s+import\b|import\b|__all__\s*=)",
    ".rs": r"^\s*(?:pub\s+)?use\b",
    ".go": r"^\s*import\b",
}
ISTRUZIONE_ALTRI = (r"^\s*(?:export\s*(?:type\s*)?\{|import\s*\{[^}]*\}\s*from\b|from\s+[\w.]+\s+import\b|(?:pub\s+)?use\b"
                    r"|__all__\s*=)")   # another language: all the list forms, each on a word boundary
# the extensions whose indentation is syntax: their stub diff is taken without -w (run-phase.sh, verify_red)
INDENTAZIONE = (".py", ".yml", ".yaml")
_TOKEN = re.compile(r"\s*(\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'|`[^`]*`|[A-Za-z_$][\w$]*(?:::[A-Za-z_$][\w$]*)*|,|\S)")
_APRE, _CHIUDE = "([{", ")]}"


def _token(s):
    out, i = [], 0
    while i < len(s):
        m = _TOKEN.match(s, i)
        if not m or not m.group(1):
            break
        out.append(m.group(1))
        i = m.end()
    return out


def _ultima_coppia(riga):
    """(start, end) of the inner part of the last pair of brackets of the line, or None"""
    j = max(riga.rfind(c) for c in _CHIUDE)
    if j < 0:
        return None
    chiusa, apre = riga[j], _APRE[_CHIUDE.index(riga[j])]
    d = 0
    for i in range(j, -1, -1):
        if riga[i] == chiusa:
            d += 1
        elif riga[i] == apre:
            d -= 1
            if d == 0:
                return i + 1, j
    return None


def _ammesso(t):
    return t == "," or t[0] in "\"'`" or re.match(r"^[A-Za-z_$][\w$]*(?:::[A-Za-z_$][\w$]*)*$", t) is not None


def elenco_allungato(tolta, aggiunta):
    """True when `aggiunta` is `tolta` with tokens inserted only inside its last pair of brackets (identifiers, «,»,
    quoted names): `export { a }` -> `export { a, b }`, `__all__ = ["a"]` -> `__all__ = ["a", "b"]`"""
    c = _ultima_coppia(tolta)
    if c is None:
        return False
    i, j = c
    prima = tolta[:i - 1].rstrip()
    # (B12-B13 review) a bracket after a call or a subscript (`f(`, `x[`) or a `{` after `)` (a body) is not a list
    if (tolta[i - 1] in "([" and re.search(r"[\w$)\]]$", prima) and not re.search(r"\bimport$", prima)) \
            or (tolta[i - 1] == "{" and prima.endswith(")")):  # NON-CHIAMATA
        return False
    pre, dentro, post = tolta[:i], tolta[i:j], tolta[j:].rstrip()
    a = aggiunta.rstrip()
    if not a.startswith(pre) or not a.endswith(post) or len(a) < len(pre) + len(post):
        return False
    t_vecchi, t_nuovi = _token(dentro), _token(a[len(pre):len(a) - len(post)])
    k = 0
    for t in t_nuovi:   # the old tokens in order, every other one is inserted and must be admitted
        if k < len(t_vecchi) and t == t_vecchi[k]:
            k += 1
        elif not _ammesso(t):
            return False
    return k == len(t_vecchi) and len(t_nuovi) > len(t_vecchi)


def diff_additivo(diff):
    """the violations of a unified diff of `stub` files (`git diff -w --ignore-blank-lines`): [(path, line of the old
    file, text)] of every removed line that is not a list instruction grown in the same hunk; [] = additive"""
    out, f, ext, rx, old, hunk = [], None, "", None, 0, None

    def chiudi(h):
        if not h:
            return
        for n, t in h["tolte"]:
            if not t.strip():   # a blank line inside a hunk: layout, not code
                continue
            if not (re.match(rx, t) and any(elenco_allungato(t, a) for a in h["aggiunte"])):  # ELENCO-ALLUNGATO
                out.append((h["f"], n, t))
    for l in (diff or "").replace("\r", "").split("\n"):
        if l.startswith("diff --git "):
            chiudi(hunk)
            hunk = None
        elif l.startswith("+++ "):
            p = l[4:].strip()
            f = p[2:] if p.startswith("b/") else (None if p == "/dev/null" else p)
            if f is not None:
                ext = os.path.splitext(f)[1].lower()
                rx = ISTRUZIONE_ELENCO.get(ext, ISTRUZIONE_ALTRI)
        elif l.startswith("--- "):
            p = l[4:].strip()
            if p != "/dev/null":
                f = p[2:] if p.startswith("a/") else p
                ext = os.path.splitext(f)[1].lower()
                rx = ISTRUZIONE_ELENCO.get(ext, ISTRUZIONE_ALTRI)
        elif l.startswith("@@"):
            chiudi(hunk)
            m = re.match(r"@@ -([0-9]+)", l)
            old = int(m.group(1)) if m else 0
            hunk = {"f": f, "tolte": [], "aggiunte": []}
        elif hunk is not None and l.startswith("-"):
            hunk["tolte"].append((old, l[1:]))
            old += 1
        elif hunk is not None and l.startswith("+"):
            hunk["aggiunte"].append(l[1:])
        elif hunk is not None and l.startswith(" "):
            old += 1
    chiudi(hunk)
    return out
