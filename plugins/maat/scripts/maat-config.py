#!/usr/bin/env python3
"""maat-config.py — the single reader of .claude/maat.json (standard library only).

Usage:
  maat-config.py valida [file]
  maat-config.py leggi <dotted.key> [--default x]          with the schema defaults
  maat-config.py leggi --tutto                              every key: «chiave<TAB>valore» (cache of maat-conf.sh)
  maat-config.py modulo-di <file relative to the repo>      «<nome> radice» | «<nome> pacchetti» | exit 2
  maat-config.py comando <modulo> <test|lint|build|controlli|controprova>
                 [--file f]… [--test t]… [--base b] [--cache c] [--report r] [--nome n]
      prints two lines: working directory (relative to the repo) and expanded command; for controlli one pair per
      entry and per file it concerns (one file per invocation). The --file and --test paths are relative to the repo: they become relative to the
      command's directory.
  maat-config.py copia-modulo
      the module of the WSL copy (test-fast.sh): MAAT_MODULO if set, otherwise the only module with `copia`.
      Prints five lines: name, radice, radice_pacchetti, lint_base (true|false), preparazione. Several modules with copia and no
      MAAT_MODULO: exit 64 «several modules with copia: set MAAT_MODULO»; no module with copia: exit 2.
  maat-config.py comando-copia <modulo> <test|lint|lint_messaggi> --copia <dir>
                 [--pacchetto p] [--file f]… [--test t]… [--cache c]
      the command that test-fast.sh runs INSIDE the copy (field `copia`, never `comandi`). Two lines: absolute
      working directory (<dir> plus the command's directory: radice = the radice relative to radice_pacchetti,
      radice_pacchetti = <dir>; --pacchetto replaces it, for lint_messaggi) and expanded command. --file and --test
      are relative to <dir> (the copy of radice_pacchetti) and become relative to the directory. copia.lint as a
      list: the first alternative without se_esiste, or whose se_esiste (relative to its directory) exists, wins.
  maat-config.py gate-richiesti <min|std|full|legacy> [--file f]…
      the gates of the level, «etichetta<TAB>modulo<TAB>tipo»: tests-<modulo> (modules with comandi.test or with files
      touched under the radice), controlli-<modulo>, lint and build (with -<modulo> if several modules declare them).
  maat-config.py test-di <modulo> [--file f]…     the tests that regola_test selects for the files (relative to the repo)
  maat-config.py python <modulo>                  the {python} interpreter of the module (exit 2: it does not use it)
  maat-config.py chiave <modulo>                  the key entries: «etichetta<TAB>file|comando|assente<TAB>cartella<TAB>valore»
  maat-config.py elenco-moduli
  maat-config.py generati [--verifica]
      the regenerable generated files of implement/fix: one line per entry, «percorso | cartella | comando | test |
      ambiente» (ambiente = that of the module containing the cartella, nativo outside every module); no entries
      = no lines. --verifica checks the entries against the project (PROJECT_ROOT): the generated file, the cartella,
      the test and the command's script exist, the test names the generated file; «ERROR: generati.<i>: …» and exit 1, otherwise
      «generati: <n> entries verified» (ERRORE, voci verificate in Italian).
  maat-config.py sonda-produzione
  maat-config.py componi <profilo>… --radice <modulo>=<percorso> [--radice …] [--nativo]
      --nativo (pk06, /maat:setup without WSL or outside Windows): every module has ambiente nativo and no copia;
      comandi.test and comandi.lint that called test-fast.sh become the copy's command run in the repo
      (copia.test; for lint the first alternative without se_esiste or whose se_esiste exists in the project,
      relative to its directory, without {cache?…}); lint_base stays only if the
      lint still has {base?…}; piattaforma.copia_wsl: no.

Importable (importlib, from the path in MAAT_CONFIG_PY): carica(), risolto(cfg), modulo_di(risolto, percorso) and
comando(cfg, modulo, tipo, file=…, test=…, …) are the functions behind the modulo-di and comando commands, without printing:
plan-check.sh, counterproof.sh, blocks-independent.py, context-pack.sh and worktree-lib.sh use them this way, with a single
implementation for bash and Python.

Where it finds the file: MAAT_CONFIG, otherwise <PROJECT_ROOT>/.claude/maat.json (PROJECT_ROOT from the environment,
otherwise `git rev-parse --show-toplevel` from the current directory). {maat} = MAAT_ROOT, otherwise the root of the
plugin that contains this file.

Exit codes: 0 ok · 1 invalid configuration · 2 no module / command not declared · 3 key missing (leggi),
command skipped and NOT RUN (declared) (comando), core fallback (sonda-produzione) · 4 project not
configured · 64 wrong usage.

Messages (1.4.0): from the catalog lib/messages.tsv (T below), English by default, Italian with "lingua": "it".
Read by gates.sh in both languages: «python not found» (and its Italian form) and the «NOT RUN (dichiarato): » /
«NOT RUN (declared): » prefix; frozen: «SALTATA: » of the skipped checks and the «assente» type of `chiave`.
"""
import copy
import json
import os
import posixpath
import re
import shutil
import subprocess
import sys

PLUGIN = posixpath.dirname(posixpath.dirname(os.path.abspath(__file__).replace("\\", "/")))
SCHEMA = posixpath.join(PLUGIN, "schemas", "maat-config.schema.json")
PROFILI = posixpath.join(PLUGIN, "profiles")

VERSIONE_CORRENTE = 1
VERSIONE_PRECEDENTE = None   # accepted with a warning (R9); None while only version 1 exists
CARTELLE = ("radice", "radice_pacchetti", "repo")
SALTA_DIR = {"node_modules", ".git", ".venv", ".nuxt", ".output", "__pycache__"}


class Uscita(Exception):
    def __init__(self, codice, messaggio=""):
        super().__init__(messaggio)
        self.codice, self.messaggio = codice, messaggio


def err(msg):
    sys.stderr.write("maat-config: %s\n" % msg)


# Messages (1.4.0): the catalog lib/messages.tsv through maat_msg.py next to this file, imported only when a message
# is built (leggi --tutto, the hot path of maat-conf.sh, prints none). maat_msg resolves `lingua` with carica() of
# this file: a message built INSIDE that resolution (maat.json missing or invalid) must not resolve it again, so
# the nested call gets the bare key (maat_msg swallows it and falls back to en). The flag lives on the maat_msg
# module, the only object shared with the copy of this file that maat_msg loads.
_MSG = []


def T(chiave, **valori):
    if not _MSG:
        dwb = sys.dont_write_bytecode
        sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        try:
            import maat_msg
        finally:
            sys.dont_write_bytecode = dwb
        _MSG.append(maat_msg)
    m = _MSG[0]
    if getattr(m, "_maat_config_in_lingua", False):
        return chiave
    m._maat_config_in_lingua = True
    try:
        m.lingua()
    finally:
        m._maat_config_in_lingua = False
    return m.T(chiave, **valori)


# --------------------------------------------------------------------------- structural validation
TIPI = {
    "string": lambda v: isinstance(v, str),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "boolean": lambda v: isinstance(v, bool),
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "null": lambda v: v is None,
}


def nome_tipo(v):
    for n in ("boolean", "integer", "number", "string", "object", "array", "null"):
        if TIPI[n](v):
            return n
    return type(v).__name__


def unisci(chiave, k):
    return "%s.%s" % (chiave, k) if chiave else str(k)


def valida_struttura(v, sch, chiave, errori):
    """Minimal validator: type (also a list), enum, pattern, required, properties, additionalProperties: false, items."""
    t = sch.get("type")
    if t is not None:
        tipi = t if isinstance(t, list) else [t]
        if not any(TIPI[x](v) for x in tipi):
            errori.append((chiave, T("maat-config.type_expected", types=(" %s " % T("maat-config.or")).join(tipi), got=nome_tipo(v))))
            return
    if "enum" in sch and not any(v == e and type(v) is type(e) for e in sch["enum"]):
        errori.append((chiave, T("maat-config.not_in_enum", v=json.dumps(v, ensure_ascii=False),
                         allowed=", ".join(str(e) for e in sch["enum"]))))
    if "pattern" in sch and isinstance(v, str) and not re.fullmatch(sch["pattern"], v):
        errori.append((chiave, T("maat-config.bad_pattern", v=json.dumps(v, ensure_ascii=False), pattern=sch["pattern"])))
    if isinstance(v, dict):
        for k in sch.get("required", []):
            if k not in v:
                errori.append((unisci(chiave, k), T("maat-config.required_missing")))
        props = sch.get("properties", {})
        ap = sch.get("additionalProperties", True)
        for k, x in v.items():
            if k in props:
                valida_struttura(x, props[k], unisci(chiave, k), errori)
            elif ap is False:
                errori.append((unisci(chiave, k), T("maat-config.unknown_key")))
    if isinstance(v, list) and "items" in sch:
        for i, x in enumerate(v):
            valida_struttura(x, sch["items"], unisci(chiave, i), errori)


# --------------------------------------------------------------------------- semantic validation
def testo(c):
    if isinstance(c, str):
        return c
    if isinstance(c, dict):
        return c.get("comando", "")
    return ""


def moduli(cfg):
    return list(enumerate(cfg.get("moduli", [])))


def alternative(c):
    return c if isinstance(c, list) else [c]


def s1(cfg):
    for i, m in moduli(cfg):
        if m.get("regola_test") == "specchio" and "specchio" not in m:
            yield "moduli.%d.specchio" % i, T("maat-config.s1")


def s2(cfg):
    for i, m in moduli(cfg):
        c = m.get("comandi", {})
        if "test" in c and "{test}" not in testo(c["test"]):
            yield "moduli.%d.comandi.test" % i, T("maat-config.s2_test")
        if "lint" in c and "{file}" not in testo(c["lint"]):
            yield "moduli.%d.comandi.lint" % i, T("maat-config.s2_lint")
        for j, v in enumerate(m.get("controlli", [])):
            if "{file}" not in v.get("comando", ""):
                yield "moduli.%d.controlli.%d.comando" % (i, j), T("maat-config.s2_check")


def s3(cfg):
    v = cfg.get("versione_schema")
    if v > VERSIONE_CORRENTE:
        yield "versione_schema", T("maat-config.s3_future", v=v, cur=VERSIONE_CORRENTE)
    elif v != VERSIONE_CORRENTE and v != VERSIONE_PRECEDENTE:
        yield "versione_schema", T("maat-config.s3_old", v=v, accepted=(" %s " % T("maat-config.and")).join(
            str(x) for x in (VERSIONE_CORRENTE, VERSIONE_PRECEDENTE) if x is not None))


def s4(cfg):
    for i, m in moduli(cfg):
        if m.get("lint_base") is True and "{base?" not in testo(m.get("comandi", {}).get("lint")):
            yield "moduli.%d.comandi.lint" % i, T("maat-config.s4")


def s5(cfg):
    for i, m in moduli(cfg):
        for k in ("test", "lint"):
            if "test-fast.sh" in testo(m.get("comandi", {}).get(k)) and k not in m.get("copia", {}):
                yield "moduli.%d.copia.%s" % (i, k), T("maat-config.s5", k=k)


def s6(cfg):
    for i, m in moduli(cfg):
        for k, c in m.get("copia", {}).items():
            alt = alternative(c)
            for j, a in enumerate(alt):
                if "test-fast.sh" in testo(a):
                    chiave = "moduli.%d.copia.%s" % (i, k) + (".%d" % j if isinstance(c, list) else "")
                    yield chiave, T("maat-config.s6")


def s7(cfg):
    for i, m in moduli(cfg):
        cp = m.get("copia", {})
        if "test" in cp and "{test}" not in testo(cp["test"]):
            yield "moduli.%d.copia.test" % i, T("maat-config.s7_test")
        for k in ("lint", "lint_messaggi"):
            if k not in cp:
                continue
            for j, a in enumerate(alternative(cp[k])):
                if "{file}" not in testo(a):
                    chiave = "moduli.%d.copia.%s" % (i, k) + (".%d" % j if isinstance(cp[k], list) else "")
                    yield chiave, T("maat-config.s7_file", k=k)


def s8(cfg):
    for i, m in moduli(cfg):
        if m.get("regola_test") == "nessuna" and "test" in m.get("comandi", {}):
            yield "moduli.%d.comandi.test" % i, T("maat-config.s8")


NON_GENERATI = re.compile(r"golden|__snapshots__|lint-baseline", re.I)


def s9(cfg):
    for i, g in enumerate(cfg.get("generati", [])):
        for k in ("percorso", "test"):
            if NON_GENERATI.search(g.get(k, "")):
                yield "generati.%d.%s" % (i, k), T("maat-config.s9")


def s10(cfg):
    for i, m in moduli(cfg):
        if m.get("preparati") and not m.get("preparazione"):
            yield "moduli.%d.preparati" % i, T("maat-config.s10")


def s11(cfg):
    """1.7.0: piano.taglia (the size of the cycle) exists from 1.7: a file that uses it declares "harness": ">=1.7"
    or newer, so that an older Maat refuses it with a clear error instead of reading it without the key."""
    if "taglia" not in (cfg.get("piano") or {}):
        return
    m = re.match(r"^>=([0-9]+)\.([0-9]+)$", str(cfg.get("harness") or ""))
    if not m or (int(m.group(1)), int(m.group(2))) < (1, 7):  # HARNESS-PER-TAGLIA
        yield "harness", T("maat-config-170.s11")


# Semantic checks: declared here and in the schema `description` (documentation only: the messages are the
# maat-config.s* keys of the catalog).
SEMANTICA = [
    ("S1", "regola_test specchio => specchio present", s1),
    ("S2", "comandi.test with {test}; comandi.lint and controlli[].comando with {file}", s2),
    ("S3", "versione_schema accepted by the reader", s3),
    ("S4", "lint_base true => comandi.lint with {base?…}", s4),
    ("S5", "commands with test-fast.sh => copia with the matching entry", s5),
    ("S6", "no command of copia calls test-fast.sh", s6),
    ("S7", "copia.test with {test}; copia.lint and copia.lint_messaggi with {file}", s7),
    ("S8", "regola_test=nessuna => no comandi.test", s8),
    ("S9", "generati[]: no golden, snapshot or lint baseline", s9),
    ("S10", "moduli[].preparati => preparazione present", s10),
    ("S11", "piano.taglia => harness >=1.7 or newer", s11),
]


# --------------------------------------------------------------------------- loading
def carica_schema():
    with open(SCHEMA, encoding="utf-8") as f:
        return json.load(f)


def radice_progetto(percorso_cfg=None):
    env = os.environ.get("PROJECT_ROOT")
    if env:
        return env.replace("\\", "/").rstrip("/")
    if percorso_cfg:
        p = os.path.abspath(percorso_cfg).replace("\\", "/")
        if p.endswith("/.claude/maat.json"):
            return p[: -len("/.claude/maat.json")]
    try:
        r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip().replace("\\", "/")
    except OSError:
        pass
    return os.getcwd().replace("\\", "/")


def percorso_config(arg=None):
    if arg:
        return arg
    if os.environ.get("MAAT_CONFIG"):
        return os.environ["MAAT_CONFIG"]
    return posixpath.join(radice_progetto(), ".claude", "maat.json")


def controlla(cfg, nome):
    """Structural, then semantic. Errors: «<file>: <chiave>: <motivo>» and exit 1."""
    errori = []
    valida_struttura(cfg, carica_schema(), "", errori)
    if not errori:
        for _sid, _desc, f in SEMANTICA:
            errori.extend(f(cfg))
    if errori:
        for k, motivo in errori:
            err("%s: %s: %s" % (nome, k or "(radice)", motivo))
        raise Uscita(1)
    if VERSIONE_PRECEDENTE is not None and cfg.get("versione_schema") == VERSIONE_PRECEDENTE:
        err(T("maat-config.r9", name=nome, prev=VERSIONE_PRECEDENTE, cur=VERSIONE_CORRENTE))


def carica(arg=None):
    p = percorso_config(arg)
    if not os.path.isfile(p):
        raise Uscita(4, T("maat-config.not_configured", p=p))
    try:
        with open(p, encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        err(T("maat-config.json_unreadable", p=p, e=e))
        raise Uscita(1)
    controlla(cfg, p)
    return cfg, p


def ha_default(sch):
    return any("default" in ps or (ps.get("type") == "object" and ha_default(ps))
               for ps in sch.get("properties", {}).values())


def con_default(v, sch):
    if isinstance(v, dict):
        for k, ps in sch.get("properties", {}).items():
            if k not in v:
                if "default" in ps:
                    v[k] = copy.deepcopy(ps["default"])
                elif ps.get("type") == "object" and ha_default(ps):
                    v[k] = {}
            if k in v:
                con_default(v[k], ps)
    elif isinstance(v, list) and "items" in sch:
        for x in v:
            con_default(x, sch["items"])


def risolto(cfg):
    r = copy.deepcopy(cfg)
    con_default(r, carica_schema())
    for m in r.get("moduli", []):
        m.setdefault("radice_pacchetti", m["radice"])
    return r


# --------------------------------------------------------------------------- utilities
def norm(p):
    p = p.replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    p = p.rstrip("/")
    return "" if p == "." else p


def sotto(p, r):
    return r == "" or p == r or p.startswith(r + "/")


def formatta(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "null"
    if isinstance(v, (str, int, float)):
        return str(v)
    if isinstance(v, list) and all(isinstance(x, (str, int, float)) and not isinstance(x, bool) for x in v):
        return " ".join(str(x) for x in v)
    return json.dumps(v, ensure_ascii=False, separators=(",", ":"))


def glob_re(g):
    out, i = "", 0
    while i < len(g):
        if g.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif g.startswith("**", i):
            out += ".*"
            i += 2
        elif g[i] == "*":
            out += "[^/]*"
            i += 1
        elif g[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(g[i])
            i += 1
    return re.compile(out)


def esistono(radice_abs, g):
    rx = glob_re(g)
    for d, sub, files in os.walk(radice_abs):
        sub[:] = [s for s in sub if s not in SALTA_DIR]
        rel = os.path.relpath(d, radice_abs).replace("\\", "/")
        for f in files:
            if rx.fullmatch(f if rel == "." else rel + "/" + f):
                return True
    return False


def sq(s):
    return "'" + ("" if s is None else str(s)).replace("'", "'\\''") + "'"


def sq_se_serve(s):
    return s if re.fullmatch(r"[A-Za-z0-9_@%+=:,./-]+", s) else sq(s)


SEGNAPOSTO = re.compile(r"(?<!\$)\{(file|test|base|cache|maat|python|report|nome)(\?([^}]*))?\}")


class NonRisolto(Exception):
    pass


def espandi(testo_cmd, valori):
    """{file} and {test}: lists, each item quoted; {x?prefix}: prefix + quoted value + space, or nothing."""
    def sost(mo):
        nome, opz, pref = mo.group(1), mo.group(2), mo.group(3)
        v = valori.get(nome)
        if opz is not None:
            if v is None or v == "" or v == []:
                return ""
            return pref + sq(v) + " "   # a single whole argument: separated from what follows

        if nome in ("file", "test"):
            return " ".join(sq(x) for x in (v or []))
        if nome == "nome":
            return mo.group(0) if v is None else sq(v)
        if nome == "python":
            if v is None:
                raise NonRisolto(T("maat-config.python_unresolved"))
            return sq_se_serve(v)
        if nome == "maat":
            return sq(v)   # always quoted, like the script in gates.sh (`bash $(sq "$VF")`)
        return mo.group(0) if v is None else sq_se_serve(v)
    return re.sub(r"[ \t]+$", "", SEGNAPOSTO.sub(sost, testo_cmd))


def python_risponde(p):
    """pk09: the python3 fallback from PATH under …/WindowsApps/ may be the Store stub (without arguments it opens
    the Store, with arguments it exits 9009) or the Python Install Manager (a real one). ALWAYS probes with
    arguments and a timeout; outside WindowsApps, no probe."""
    if "/windowsapps/" not in p.lower():
        return True
    try:
        r = subprocess.run([p, "-c", "import sys"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return False
    return r.returncode == 0


def python_dal_path(v, scartato):
    """pk09: the first `v` on PATH (`scartato`) does not respond: search the OTHER PATH entries, in order, one
    directory at a time; only paths under WindowsApps are probed (python_risponde)."""
    for d in os.environ.get("PATH", "").split(os.pathsep):
        if not d:
            continue
        w = shutil.which(v, path=d)
        if not w:
            continue
        w = w.replace("\\", "/")
        if os.path.normcase(w) == os.path.normcase(scartato):
            continue
        if python_risponde(w):
            return w
    return None


def risolvi_python(cfg, m, root):
    env = os.environ.get("FIC_GATES_VENV_PY")
    if env:
        return env.replace("\\", "/")
    for i, (valore, base) in enumerate(((m.get("python"), norm(m["radice"])),
                                        (cfg.get("piattaforma", {}).get("python"), ""),
                                        ("python3", ""))):
        # a list = alternatives in order (the first that exists; none -> the last path); a string = a list of one,
        # whose path is used even if it does not exist (as before). A name without / is looked up on PATH.
        valori = valore if isinstance(valore, list) else [valore]
        ultimo = None
        for v in valori:
            if not v:
                continue
            v = v.replace("\\", "/")
            if "/" in v:
                p = v if posixpath.isabs(v) or re.match(r"^[A-Za-z]:/", v) else posixpath.normpath(
                    posixpath.join(root, base, v))
                if len(valori) == 1 or os.path.exists(p):
                    return p
                ultimo = p
                continue
            w = shutil.which(v)
            if w:
                w = w.replace("\\", "/")
                # only the last fallback (python3 from PATH): moduli[].python and piattaforma.python stay as before
                if i == 2 and not python_risponde(w):
                    w = python_dal_path(v, w)   # the stub is first on PATH: try the other entries, in order
                    if not w:
                        continue
                return w
        if ultimo:
            return ultimo
    return None


def cartella_di(m, quale):
    if quale == "repo":
        return ""
    return norm(m["radice_pacchetti"] if quale == "radice_pacchetti" else m["radice"])


def rebase(percorsi, base):
    out = []
    for f in percorsi:
        p = norm(f)
        if base == "":
            out.append(p)
        elif p.startswith(base + "/"):
            out.append(p[len(base) + 1:])
        else:
            raise Uscita(64, T("maat-config.outside_dir", f=f, base=base))
    return out


def presente(se_presente, radice_abs):
    if any(c in se_presente for c in "*?/"):
        return esistono(radice_abs, se_presente)
    return shutil.which(se_presente) is not None


# --------------------------------------------------------------------------- commands
def cmd_valida(args):
    if len(args) > 1:
        raise Uscita(64, T("maat-config.usage_valida"))
    _cfg, p = carica(args[0] if args else None)
    print("maat-config: " + T("maat-config.valid", p=p))


def cmd_leggi(args):
    if args == ["--tutto"]:
        cfg, _p = carica()
        def giro(v, k):
            if k:
                print("%s\t%s" % (k, formatta(v).replace("\n", " ").replace("\t", " ")))
            if isinstance(v, dict):
                for kk, x in v.items():
                    giro(x, unisci(k, kk))
            elif isinstance(v, list):
                for i, x in enumerate(v):
                    giro(x, unisci(k, i))
        giro(risolto(cfg), "")
        return
    default = None
    if len(args) == 3 and args[1] == "--default":
        default = args[2]
    elif len(args) != 1:
        raise Uscita(64, T("maat-config.usage_leggi"))
    cfg, _p = carica()
    v = risolto(cfg)
    for seg in args[0].split("."):
        if isinstance(v, dict) and seg in v:
            v = v[seg]
        elif isinstance(v, list) and seg.isdigit() and int(seg) < len(v):
            v = v[int(seg)]
        else:
            if default is not None:
                print(default)
                return
            raise Uscita(3, T("maat-config.key_missing", k=args[0]))
    print(formatta(v))


def instrada(r, p):
    """(nome, "radice" | "pacchetti") of file p (relative to the repo), None outside every module."""
    p = norm(p)
    cand = [(len(norm(m["radice"])), m["nome"]) for m in r["moduli"] if sotto(p, norm(m["radice"]))]
    if cand:
        return sorted(cand, key=lambda c: -c[0])[0][1], "radice"
    pacchetti = [(len(norm(m["radice_pacchetti"])), m["nome"]) for m in r["moduli"]
                 if sotto(p, norm(m["radice_pacchetti"]))]
    if pacchetti:
        return sorted(pacchetti, key=lambda c: -c[0])[0][1], "pacchetti"
    return None


def modulo_di(r, percorso):
    """The module of the file (relative to the repo) in the RESOLVED configuration r (risolto(cfg)): (nome, "radice" |
    "pacchetti"), None outside every module. The same rule as the modulo-di command, importable (plan-check.sh,
    counterproof.sh, blocks-independent.py)."""
    return instrada(r, percorso)


def cmd_modulo_di(args):
    if len(args) != 1:
        raise Uscita(64, T("maat-config.usage_modulo_di"))
    cfg, _p = carica()
    d = modulo_di(risolto(cfg), args[0])
    if d is None:
        raise Uscita(2)
    print("%s %s" % d)


def modulo_di_nome(r, nome):
    m = next((x for x in r["moduli"] if x["nome"] == nome), None)
    if m is None:
        raise Uscita(2, T("maat-config.unknown_module", m=nome))
    return m


def cmd_gate_richiesti(args):
    """The gates of a level: one line «etichetta<TAB>modulo<TAB>tipo» (tipo = test | controlli | lint | build).
    tests-<modulo> for each module with comandi.test or with a touched file under its root (without a test command
    the gate is a declared NOT RUN); controlli-<modulo> for each module with controlli; lint and build for the
    modules that declare them, without a suffix if there is only one. Order: tests, controlli, lint, build, each by label.
    legacy = std. The same function serves gates.sh (which to run) and finalize.sh (which to require)."""
    if not args:
        raise Uscita(64, T("maat-config.usage_gate"))
    livello = "std" if args[0] == "legacy" else args[0]
    if livello not in ("min", "std", "full"):
        raise Uscita(64, T("maat-config.unknown_level", l=args[0]))
    o = opzioni(args[1:], ("file",), ())
    cfg, _p = carica()
    r = risolto(cfg)
    tipi = r["gate"][livello]
    toccati = set()
    for f in o["file"]:
        d = instrada(r, f)
        if d is not None and d[1] == "radice":
            toccati.add(d[0])
    gruppi = []
    if "test" in tipi:
        gruppi.append([("tests-" + m["nome"], m["nome"], "test") for m in r["moduli"]
                       if "test" in m.get("comandi", {}) or m["nome"] in toccati])
    if "controlli" in tipi:
        gruppi.append([("controlli-" + m["nome"], m["nome"], "controlli") for m in r["moduli"] if m.get("controlli")])
    for tipo in ("lint", "build"):
        if tipo in tipi:
            con = [m for m in r["moduli"] if tipo in m.get("comandi", {})]
            gruppi.append([(tipo if len(con) == 1 else tipo + "-" + m["nome"], m["nome"], tipo) for m in con])
    for g in gruppi:
        for riga in sorted(g):
            print("\t".join(riga))


ESCLUSE_ACCANTO = ("node_modules", ".nuxt", ".output")
TEST_ACCANTO = re.compile(r".*\.(test|spec)\.(ts|tsx|js)")
SORGENTI_ACCANTO = (".ts", ".tsx", ".vue", ".js")
CANDIDATI_ACCANTO = ("test.ts", "test.tsx", "spec.ts", "spec.tsx")


def test_accanto(rad_abs, rel):
    """`accanto` rule: a touched test file (if it exists); for a source file, the test with the same name in its
    directory, otherwise anywhere under the root (excluding node_modules, .nuxt, .output)."""
    if rel.split("/")[0] in ESCLUSE_ACCANTO:
        return set()
    nome = posixpath.basename(rel)
    if TEST_ACCANTO.fullmatch(nome):
        return {rel} if os.path.isfile(posixpath.join(rad_abs, rel)) else set()
    if not nome.endswith(SORGENTI_ACCANTO):
        return set()
    n = nome.rsplit(".", 1)[0]
    d = posixpath.dirname(rel)
    cand = [n + "." + e for e in CANDIDATI_ACCANTO]
    vicini = {posixpath.join(d, c) if d else c for c in cand if os.path.isfile(posixpath.join(rad_abs, d, c))}
    if vicini:
        return vicini
    trovati = set()
    for dd, sub, files in os.walk(rad_abs):
        sub[:] = [s for s in sub if s not in ESCLUSE_ACCANTO]
        r = os.path.relpath(dd, rad_abs).replace("\\", "/")
        trovati.update((c if r == "." else r + "/" + c) for c in files if c in cand)
    return trovati


def glob_pezzi(g, sost):
    """Regex of glob g where {m} stands for sost (already a regex)."""
    return sost.join(glob_re(x).pattern for x in g.split("{m}"))


def test_specchio(rad_abs, rel, sp):
    """`specchio` (mirror) rule: a file matching `a` (with any {m}) is a touched test (if it exists); a file
    matching `da` yields the files matching `a` with the same {m}."""
    if re.fullmatch(glob_pezzi(sp["a"], "[^/]*"), rel):
        return {rel} if os.path.isfile(posixpath.join(rad_abs, rel)) else set()
    mo = re.fullmatch(glob_pezzi(sp["da"], "([^/]+)"), rel)
    if not mo:
        return set()
    rx = re.compile(glob_pezzi(sp["a"], re.escape(mo.group(1))))
    out = set()
    for dd, sub, files in os.walk(rad_abs):
        sub[:] = [s for s in sub if s not in SALTA_DIR]
        r = os.path.relpath(dd, rad_abs).replace("\\", "/")
        out.update(x for x in ((f if r == "." else r + "/" + f) for f in files) if rx.fullmatch(x))
    return out


def cmd_test_di(args):
    """The tests selected by the module's regola_test for the touched files: one per line, relative to the repo,
    sorted and without duplicates. Rule `nessuna`: none. Files outside the root are ignored."""
    if not args:
        raise Uscita(64, T("maat-config.usage_test_di"))
    o = opzioni(args[1:], ("file",), ())
    cfg, p = carica()
    m = modulo_di_nome(risolto(cfg), args[0])
    root = radice_progetto(p)
    rad = norm(m["radice"])
    rad_abs = posixpath.join(root, rad) if rad else root
    sel = set()
    for f in (norm(x) for x in o["file"]):
        if not sotto(f, rad):
            continue
        rel = f[len(rad) + 1:] if rad else f
        if m["regola_test"] == "accanto":
            sel |= test_accanto(rad_abs, rel)
        elif m["regola_test"] == "specchio":
            sel |= test_specchio(rad_abs, rel, m["specchio"])
    for t in sorted(sel):
        print(posixpath.join(rad, t) if rad else t)


def testi_del_modulo(m):
    out = [testo(c) for c in m.get("comandi", {}).values()]
    out += [v.get("comando", "") for v in m.get("controlli", [])]
    out += [v.get("comando", "") for v in m.get("chiave", [])]
    return out


def cmd_python(args):
    """The module's interpreter ({python} precedence), if one of its commands, controlli or chiave entries uses
    {python}: exit 2 if none uses it, 3 if it does not resolve."""
    if len(args) != 1:
        raise Uscita(64, T("maat-config.usage_python"))
    cfg, p = carica()
    m = modulo_di_nome(risolto(cfg), args[0])
    if not any("{python}" in t for t in testi_del_modulo(m)):
        raise Uscita(2)
    py = risolvi_python(cfg, m, radice_progetto(p))
    if py is None:
        raise Uscita(3, T("maat-config.python_not_found_for", m=args[0]))
    print(py)


def cmd_chiave(args):
    """The module's `chiave` entries, one line «etichetta<TAB>tipo<TAB>cartella<TAB>valore»: tipo file (valore = the
    file, relative to cartella) or comando (valore = the expanded command, {python} and {maat} included); assente if
    the command does not resolve. cartella is relative to the repo («.» = the repo)."""
    if len(args) != 1:
        raise Uscita(64, T("maat-config.usage_chiave"))
    cfg, p = carica()
    m = modulo_di_nome(risolto(cfg), args[0])
    root = radice_progetto(p)
    for v in m.get("chiave", []):
        cart = cartella_di(m, v.get("cartella", "radice")) or "."
        if "file" in v:
            print("\t".join((v["etichetta"], "file", cart, v["file"])))
            continue
        c = v.get("comando", "")
        valori = {"maat": (os.environ.get("MAAT_ROOT") or PLUGIN).replace("\\", "/")}
        try:
            if "{python}" in c:
                valori["python"] = risolvi_python(cfg, m, root)
            riga = espandi(c, valori)
        except NonRisolto:
            print("\t".join((v["etichetta"], "assente", cart, "")))
            continue
        print("\t".join((v["etichetta"], "comando", cart, riga)))


def opzioni(args, ripetibili, singole):
    val = {k: [] for k in ripetibili}
    val.update({k: None for k in singole})
    i = 0
    while i < len(args):
        a = args[i]
        if a.startswith("--") and a[2:] in val and i + 1 < len(args):
            if a[2:] in ripetibili:
                val[a[2:]].append(args[i + 1])
            else:
                val[a[2:]] = args[i + 1]
            i += 2
        else:
            raise Uscita(64, T("maat-config.unknown_option", a=a))
    return val


def comando(cfg, modulo, tipo, file=(), test=(), base=None, cache=None, report=None, nome=None, root=None):
    """The module's <tipo> command, expanded: list of pairs (working directory relative to the repo, "" = the repo;
    command). One pair, except for controlli (one per entry and per file). cfg = the configuration from carica(); file
    and test relative to the repo; root = the project root (default: radice_progetto()). Exit codes as for the
    `comando` command (Uscita 2 not declared, 3 skipped and declared NOT RUN, 64 path outside the directory), which
    this implements: plan-check.sh and counterproof.sh also use it by importing this file."""
    if tipo not in ("test", "lint", "build", "controlli", "controprova"):
        raise Uscita(64, T("maat-config.unknown_type", t=tipo))
    r = risolto(cfg)
    root = (root or radice_progetto()).replace("\\", "/").rstrip("/")
    m = next((x for x in r["moduli"] if x["nome"] == modulo), None)
    if m is None:
        raise Uscita(2, T("maat-config.unknown_module", m=modulo))
    radice_abs = posixpath.join(root, norm(m["radice"])) if norm(m["radice"]) else root
    valori = {"maat": (os.environ.get("MAAT_ROOT") or PLUGIN).replace("\\", "/"),
              "base": base, "cache": cache, "report": report, "nome": nome}
    out = []

    def espansa(cart, txt, files_key, files):
        if "{python}" in txt:
            valori["python"] = risolvi_python(cfg, m, root)
        v = dict(valori)
        v[files_key] = files
        return (cart, espandi(txt, v))

    if tipo == "controlli":
        voci = m.get("controlli", [])
        rel = [f for f in (norm(x) for x in file) if sotto(f, norm(m["radice"]))]
        rel = [f[len(norm(m["radice"])) + 1:] if norm(m["radice"]) else f for f in rel]
        eseguite = saltate = 0
        for v in voci:
            rx = glob_re(v["glob"])
            files = [f for f in rel if rx.fullmatch(f)]
            if not files:
                continue
            if v.get("se_presente") and not presente(v["se_presente"], radice_abs):
                err("SALTATA: " + T("maat-config.skipped_missing", cmd=v["comando"], x=v["se_presente"]))
                saltate += 1
                continue
            try:
                # one line per file: `bash -n a b` and `node --check a b` check only a,
                # `python -m json.tool a b` would write to b
                out.extend([espansa(norm(m["radice"]), v["comando"], "file", [f]) for f in files])
                eseguite += 1
            except NonRisolto as e:
                err("SALTATA: " + T("maat-config.skipped_unresolved", cmd=v["comando"], why=e))
                saltate += 1
        if eseguite:
            return out
        if saltate:
            raise Uscita(3)
        raise Uscita(2, T("maat-config.no_checks", m=modulo))

    if tipo == "controprova":
        c = m.get("controprova", {}).get("comando")
        if not c:
            raise Uscita(2, T("maat-config.no_counterproof", m=modulo))
        c = {"comando": c}
    else:
        c = m.get("comandi", {}).get(tipo)
        if c is None:
            raise Uscita(2, T("maat-config.cmd_not_declared", t=tipo, m=modulo))
        if isinstance(c, str):
            c = {"comando": c}
    if c.get("se_presente") and not presente(c["se_presente"], radice_abs):
        raise Uscita(3, T("maat-config.not_run_missing", x=c["se_presente"], m=modulo, t=tipo))
    cart = cartella_di(m, c.get("cartella", "radice"))
    files = rebase(file, cart)
    tests = rebase(test, cart)
    valori["file"] = files
    try:
        out.append(espansa(cart, c["comando"], "test", tests))
    except NonRisolto as e:
        raise Uscita(3, T("maat-config.not_run", why=e))
    return out


def cmd_comando(args):
    if len(args) < 2:
        raise Uscita(64, T("maat-config.usage_comando"))
    nome, tipo = args[0], args[1]
    if tipo not in ("test", "lint", "build", "controlli", "controprova"):
        raise Uscita(64, T("maat-config.unknown_type", t=tipo))
    o = opzioni(args[2:], ("file", "test"), ("base", "cache", "report", "nome"))
    cfg, p = carica()
    for cart, riga in comando(cfg, nome, tipo, file=o["file"], test=o["test"], base=o["base"], cache=o["cache"],
                              report=o["report"], nome=o["nome"], root=radice_progetto(p)):
        print(cart or ".")
        print(riga)


def modulo_della_copia(r):
    nome = os.environ.get("MAAT_MODULO")
    if nome:
        m = next((x for x in r["moduli"] if x["nome"] == nome), None)
        if m is None:
            raise Uscita(2, T("maat-config.unknown_module", m=nome) + " (MAAT_MODULO)")
        if not m.get("copia"):
            raise Uscita(2, T("maat-config.no_copy_module", m=nome))
        return m
    con = [x for x in r["moduli"] if x.get("copia")]
    if len(con) == 1:
        return con[0]
    if not con:
        raise Uscita(2, T("maat-config.no_copy"))
    raise Uscita(64, T("maat-config.several_copies"))


def relativa(radice, pacchetti):
    """The root relative to radice_pacchetti ("" if they coincide)."""
    if radice == pacchetti:
        return ""
    if pacchetti == "" or radice.startswith(pacchetti + "/"):
        return radice[len(pacchetti) + 1:] if pacchetti else radice
    raise Uscita(1, T("maat-config.outside_packages", r=radice, p=pacchetti))


def cmd_copia_modulo(args):
    if args:
        raise Uscita(64, T("maat-config.usage_copia_modulo"))
    cfg, _p = carica()
    m = modulo_della_copia(risolto(cfg))
    print("\n".join([m["nome"], norm(m["radice"]), norm(m["radice_pacchetti"]),
                     "true" if m.get("lint_base") else "false", m.get("preparazione", "")]))


def cmd_comando_copia(args):
    if len(args) < 2:
        raise Uscita(64, T("maat-config.usage_comando_copia"))
    nome, tipo = args[0], args[1]
    if tipo not in ("test", "lint", "lint_messaggi"):
        raise Uscita(64, T("maat-config.unknown_type", t=tipo))
    o = opzioni(args[2:], ("file", "test"), ("copia", "pacchetto", "cache"))
    if not o["copia"]:
        raise Uscita(64, T("maat-config.copia_required"))
    copia_dir = o["copia"].replace("\\", "/").rstrip("/")
    cfg, p = carica()
    r = risolto(cfg)
    m = next((x for x in r["moduli"] if x["nome"] == nome), None)
    if m is None:
        raise Uscita(2, T("maat-config.unknown_module", m=nome))
    c = m.get("copia", {}).get(tipo)
    if c is None:
        raise Uscita(2, T("maat-config.copy_not_declared", t=tipo, m=nome))
    gruppo = relativa(norm(m["radice"]), norm(m["radice_pacchetti"]))

    def cart_rel(a):
        if o["pacchetto"] is not None:
            return norm(o["pacchetto"])
        quale = a.get("cartella", "radice")
        if quale == "repo":
            raise Uscita(1, T("maat-config.copy_no_repo", t=tipo, m=nome))
        return gruppo if quale == "radice" else ""

    def assoluta(rel):
        return copia_dir + ("/" + rel if rel else "")

    scelta = None
    for a in alternative(c):
        a = {"comando": a} if isinstance(a, str) else a
        if a.get("se_esiste") and not os.path.exists(posixpath.join(assoluta(cart_rel(a)), a["se_esiste"])):
            continue
        scelta = a
        break
    if scelta is None:
        raise Uscita(2, T("maat-config.copy_no_alt", t=tipo, m=nome))
    cart = cart_rel(scelta)
    valori = {"maat": (os.environ.get("MAAT_ROOT") or PLUGIN).replace("\\", "/"), "cache": o["cache"],
              "file": rebase(o["file"], cart), "test": rebase(o["test"], cart)}
    if "{python}" in scelta["comando"]:
        valori["python"] = risolvi_python(cfg, m, radice_progetto(p))
    try:
        riga = espandi(scelta["comando"], valori)
    except NonRisolto as e:
        raise Uscita(3, T("maat-config.not_run", why=e))
    print(assoluta(cart))
    print(riga)


def cmd_elenco(args):
    if args:
        raise Uscita(64, T("maat-config.usage_elenco"))
    cfg, _p = carica()
    for m in cfg["moduli"]:
        print(m["nome"])


def cmd_generati(args):
    if args not in ([], ["--verifica"]):
        raise Uscita(64, T("maat-config.usage_generati"))
    cfg, p = carica()
    r = risolto(cfg)
    voci = r.get("generati", [])
    if not args:
        for g in voci:
            d = instrada(r, g["cartella"])
            amb = modulo_di_nome(r, d[0]).get("ambiente", "nativo") if d else "nativo"
            print(" | ".join([norm(g["percorso"]), norm(g["cartella"]), g["comando"].strip(), norm(g["test"]), amb]))
        return
    root = radice_progetto(p)
    errori = []
    for i, g in enumerate(voci):
        k = "generati.%d" % i
        pg, cart, tst = norm(g["percorso"]), norm(g["cartella"]), norm(g["test"])
        if not os.path.isfile(posixpath.join(root, pg)):
            errori.append(T("maat-config.gen_missing", k=k, p=pg))
        if not os.path.isdir(posixpath.join(root, cart or ".")):
            errori.append(T("maat-config.gen_dir_missing", k=k, d=cart or "."))
        if not os.path.isfile(posixpath.join(root, tst)):
            errori.append(T("maat-config.gen_test_missing", k=k, t=tst))
        script = next((w for w in g["comando"].split() if re.search(r"\.(py|mjs|js|sh)$", w)), None)
        if script is None:
            errori.append(T("maat-config.gen_no_script", k=k))
        elif not os.path.isfile(posixpath.join(root, cart or ".", script)):
            errori.append(T("maat-config.gen_script_missing", k=k, s=posixpath.join(cart, script) if cart else script))
        if os.path.isfile(posixpath.join(root, tst)):
            with open(posixpath.join(root, tst), encoding="utf-8", errors="replace") as fh:
                if posixpath.basename(pg) not in fh.read():
                    errori.append(T("maat-config.gen_unrelated", k=k, t=tst, g=posixpath.basename(pg)))
    for e in errori:
        print(T("maat-config.error_line", e=e))
    if errori:
        raise Uscita(1)
    print("generati: " + T("maat-config.gen_verified", n=len(voci)))


def cmd_sonda(args):
    if args:
        raise Uscita(64, T("maat-config.usage_sonda"))
    cfg, _p = carica()
    g = cfg.get("guardia", {})
    if g.get("produzione") and g.get("sonde"):
        print("curl -s https://%s/" % g["sonde"][0])
        return
    print("git push --force origin x")
    raise Uscita(3)


def nativo(out):
    """componi --nativo: no WSL. The copy is removed; a command that went through test-fast.sh becomes the command
    that test-fast.sh ran inside the copy (S5: without a copy, test-fast.sh cannot be called)."""
    out.setdefault("piattaforma", {})["copia_wsl"] = "no"
    root = radice_progetto()

    def applicabile(a, m):
        # as in comando-copia: the first alternative without se_esiste, or whose se_esiste exists, wins, here in the
        # project (relative to the alternative's directory: the module's radice or radice_pacchetti)
        if not a.get("se_esiste"):
            return True
        quale = a.get("cartella", "radice")
        cart = norm(m.get("radice_pacchetti", m["radice"])) if quale == "radice_pacchetti" else \
            "" if quale == "repo" else norm(m["radice"])
        return os.path.exists(posixpath.join(root, cart, a["se_esiste"]) if cart else posixpath.join(root, a["se_esiste"]))

    for m in out["moduli"]:
        cp = m.pop("copia", {})
        if m.get("ambiente") == "wsl":
            m["ambiente"] = "nativo"
        cmd = m.get("comandi", {})
        for k in ("test", "lint"):
            if k not in cmd or "test-fast.sh" not in testo(cmd[k]):
                continue
            alt = [a if isinstance(a, dict) else {"comando": a} for a in alternative(cp.get(k)) if a is not None]
            scelta = next((a for a in alt if applicabile(a, m)), None)
            if scelta is None:
                del cmd[k]
                continue
            cmd[k] = {"comando": re.sub(r"\{cache\?[^}]*\}", "", scelta["comando"]),
                      "cartella": scelta.get("cartella", "radice")}
        if m.get("lint_base") and "{base?" not in testo(cmd.get("lint")):
            m["lint_base"] = False
    return out


def cmd_componi(args):
    nomi, radici, i = [], [], 0
    senza_wsl = False
    while i < len(args):
        if args[i] == "--nativo":
            senza_wsl = True
            i += 1
        elif args[i] == "--radice" and i + 1 < len(args) and "=" in args[i + 1]:
            n, _sep, p = args[i + 1].partition("=")
            radici.append((n, p))
            i += 2
        elif args[i].startswith("--"):
            raise Uscita(64, T("maat-config.unknown_option_only", a=args[i]))
        else:
            nomi.append(args[i])
            i += 1
    if not nomi or len(nomi) != len(radici):
        raise Uscita(64, T("maat-config.usage_componi"))
    out = {"versione_schema": VERSIONE_CORRENTE, "lingua": "en"}
    mods = []
    for nome, (mod, rad) in zip(nomi, radici):
        f = posixpath.join(PROFILI, nome + ".json")
        if not os.path.isfile(f):
            raise Uscita(64, T("maat-config.unknown_profile", n=nome, d=PROFILI))
        with open(f, encoding="utf-8") as fh:
            prof = json.load(fh)
        for k, v in prof.get("sezioni", {}).items():
            if isinstance(v, list):
                out.setdefault(k, [])
                out[k].extend(x for x in v if x not in out[k])
            elif isinstance(v, dict):
                out.setdefault(k, {})
                for kk, vv in v.items():
                    out[k].setdefault(kk, copy.deepcopy(vv))
            else:
                out.setdefault(k, v)
        m = {"nome": mod, "radice": rad, "radice_pacchetti": rad}
        m.update(copy.deepcopy(prof.get("modulo", {})))
        mods.append(m)
    out["moduli"] = mods
    if senza_wsl:
        nativo(out)
    controlla(out, "componi")
    print(json.dumps(out, ensure_ascii=False, indent=2))


COMANDI = {"valida": cmd_valida, "leggi": cmd_leggi, "modulo-di": cmd_modulo_di, "comando": cmd_comando,
           "gate-richiesti": cmd_gate_richiesti, "test-di": cmd_test_di, "python": cmd_python,
           "chiave": cmd_chiave,
           "copia-modulo": cmd_copia_modulo, "comando-copia": cmd_comando_copia,
           "elenco-moduli": cmd_elenco, "generati": cmd_generati, "sonda-produzione": cmd_sonda, "componi": cmd_componi}


def main(argv):
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", newline="\n")
        except (AttributeError, ValueError):
            pass
    if not argv or argv[0] not in COMANDI:
        sys.stderr.write(__doc__)
        return 64
    try:
        COMANDI[argv[0]](argv[1:])
    except Uscita as u:
        if u.messaggio:
            err(u.messaggio)
        return u.codice
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
