#!/usr/bin/env python3
"""maat_msg.py -- the message catalog of Maat in Python (1.4.0), twin of scripts/lib/maat-msg.sh.

  lingua()                 "it" or "en"
  T(chiave, **valori)      the text of the key in the current language, placeholders replaced
  leggi_catalogo(path)     ([(line, key, en, it)], [lines without exactly two TABs]): the parser of both loaders

Language: MAAT_LINGUA if set and not empty (it|en; any other value: en), otherwise `lingua` of .claude/maat.json read
by the single reader (maat-config.py carica; maat.json missing or invalid: en), otherwise en. Only the variable is read
at every call (a language that changes between two calls of the same process is followed); the value of maat.json
is cached per path (MAAT_CONFIG, PROJECT_ROOT and working directory).
Catalog: lib/messages.tsv in the folder of this module, never from a variable of the caller (a copy of the plugin
uses its own); read once per process, CRs dropped. Format and rules: the header of messages.tsv.
Substitution (same rules as msg in bash, same bytes): left to right, {{ -> {, }} -> }, {name} -> str(value) as it is
(never rescanned), any other brace stays. A value missing -> {name} stays and one warning on stderr.
Missing key or catalog: the key between ‹ › as the text and one warning on stderr (at most one per call); nothing is
raised, so the caller's exit code does not change.
Embedded Python (heredocs of the bash scripts) imports this file from the path in MAAT_MSG_PY with
spec_from_file_location (block B); this module finds its catalog by itself.
"""
import importlib.util
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOGO = os.path.join(HERE, "lib", "messages.tsv")
LINGUE = ("en", "it")
NOME = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}")   # explicit ranges: ASCII only, as in bash
CHIAVE = re.compile(r"[A-Za-z0-9._-]+\Z")

_CONF = {}      # (MAAT_CONFIG, PROJECT_ROOT, cwd) -> language of maat.json
_CAT = None     # key -> (en, it), or {} with the catalog missing
_CAT_OK = False


def _da_config():
    """`lingua` of maat.json through the single reader; en if missing, invalid or not in the table."""
    dwb = sys.dont_write_bytecode
    sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
    saved, sys.stderr = sys.stderr, io.StringIO()   # the reader's errors are not ours
    try:
        spec = importlib.util.spec_from_file_location("maat_config_msg", os.path.join(HERE, "maat-config.py"))
        mc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mc)
        cfg, _p = mc.carica()
        v = cfg.get("lingua")
    except (Exception, SystemExit):
        v = None
    finally:
        sys.stderr = saved
        sys.dont_write_bytecode = dwb
    return v if v in LINGUE else "en"


def lingua():
    v = os.environ.get("MAAT_LINGUA", "")
    if v:
        return v if v in LINGUE else "en"
    k = (os.environ.get("MAAT_CONFIG", ""), os.environ.get("PROJECT_ROOT", ""), os.getcwd())
    if k not in _CONF:
        _CONF[k] = _da_config()
    return _CONF[k]


def leggi_catalogo(path):
    with open(path, encoding="utf-8", newline="") as f:
        righe = f.read().replace("\r", "").split("\n")
    voci, rotte = [], []
    for n, l in enumerate(righe, 1):
        if not l or l.startswith("#"):
            continue
        p = l.split("\t")
        if len(p) != 3:
            rotte.append(n)
            continue
        voci.append((n, p[0], p[1], p[2]))
    return voci, rotte


def _catalogo():
    global _CAT, _CAT_OK
    if _CAT is None:
        try:
            voci, _rotte = leggi_catalogo(CATALOGO)
            _CAT, _CAT_OK = {k: (en, it) for _n, k, en, it in voci}, True
        except OSError:
            _CAT, _CAT_OK = {}, False
    return _CAT


def sostituisci(t, valori):
    """(text, names without a value): the placeholders of t replaced with valori (strings)."""
    out, miss, i, n = [], [], 0, len(t)
    while i < n:
        if t.startswith("{{", i):
            out.append("{")
            i += 2
        elif t.startswith("}}", i):
            out.append("}")
            i += 2
        elif t[i] == "{":
            m = NOME.match(t, i)
            if m:
                nm = m.group(1)
                if nm in valori:
                    out.append(valori[nm])
                else:
                    out.append(m.group(0))
                    if nm not in miss:
                        miss.append(nm)
                i = m.end()
            else:
                out.append("{")
                i += 1
        elif t[i] == "}":
            out.append("}")
            i += 1
        else:
            j = min([x for x in (t.find("{", i), t.find("}", i)) if x >= 0] or [n])
            out.append(t[i:j])
            i = j
    return "".join(out), miss


def T(chiave, **valori):
    cat = _catalogo()
    voce = cat.get(chiave) if CHIAVE.match(chiave) else None   # as in bash: other characters, never in the catalog
    t = voce[LINGUE.index(lingua())] if voce else ""
    if not t:
        if _CAT_OK:
            sys.stderr.write("maat-msg: message key not in the catalog: %s\n" % chiave)
        else:
            sys.stderr.write("maat-msg: message catalog not found: %s\n" % CATALOGO)
        return "‹%s›" % chiave
    s, miss = sostituisci(t, {k: str(v) for k, v in valori.items()})
    if miss:
        sys.stderr.write("maat-msg: %s: no value for %s\n" % (chiave, ", ".join("{%s}" % x for x in miss)))
    return s
