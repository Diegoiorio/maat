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


def separatori(percorso, dichiarati=None):
    """the separators of the levels for the test file `percorso` (its extension), or the declared ones of the module"""
    if dichiarati:
        s = [x for x in dichiarati if isinstance(x, str) and x]
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
    """(language, regex, matched text) of the first message of a missing symbol in `testo`, or None"""
    for lingua, regs in list(SIMBOLO_MANCANTE.items()) + [("maat.json", list(extra or ()))]:
        for r in regs:
            m = re.search(r, testo or "")
            if m:
                return lingua, r, m.group(0)
    return None
