#!/usr/bin/env python3
"""maat-config.py — lettore unico di .claude/maat.json (solo libreria standard).

Uso:
  maat-config.py valida [file]
  maat-config.py leggi <chiave.puntata> [--default x]      con i default dello schema
  maat-config.py leggi --tutto                              ogni chiave: «chiave<TAB>valore» (cache di maat-conf.sh)
  maat-config.py modulo-di <file relativo al repo>          «<nome> radice» | «<nome> pacchetti» | exit 2
  maat-config.py comando <modulo> <test|lint|build|controlli|controprova>
                 [--file f]… [--test t]… [--base b] [--cache c] [--report r] [--nome n]
      stampa due righe: cartella d'esecuzione (relativa al repo) e comando espanso; per controlli una coppia per
      ogni voce e ogni file che la riguarda (un file per invocazione). I percorsi di --file e --test sono relativi al repo: diventano relativi alla
      cartella del comando.
  maat-config.py copia-modulo
      il modulo della copia WSL (test-fast.sh): MAAT_MODULO se impostata, altrimenti l'unico modulo con `copia`.
      Stampa cinque righe: nome, radice, radice_pacchetti, lint_base (true|false), preparazione. Più moduli con copia e nessun
      MAAT_MODULO: exit 64 «più moduli con copia: imposta MAAT_MODULO»; nessun modulo con copia: exit 2.
  maat-config.py comando-copia <modulo> <test|lint|lint_messaggi> --copia <dir>
                 [--pacchetto p] [--file f]… [--test t]… [--cache c]
      il comando che test-fast.sh esegue DENTRO la copia (campo `copia`, mai `comandi`). Due righe: cartella
      d'esecuzione assoluta (<dir> più la cartella del comando: radice = la radice relativa a radice_pacchetti,
      radice_pacchetti = <dir>; --pacchetto la sostituisce, per lint_messaggi) e comando espanso. --file e --test
      sono relativi a <dir> (la copia di radice_pacchetti) e diventano relativi alla cartella. copia.lint come
      lista: vale la prima alternativa senza se_esiste o il cui se_esiste (relativo alla sua cartella) esiste.
  maat-config.py gate-richiesti <min|std|full|legacy> [--file f]…
      i gate del livello, «etichetta<TAB>modulo<TAB>tipo»: tests-<modulo> (moduli con comandi.test o con file
      toccati sotto la radice), controlli-<modulo>, lint e build (con -<modulo> se più moduli li dichiarano).
  maat-config.py test-di <modulo> [--file f]…     i test che regola_test seleziona per i file (relativi al repo)
  maat-config.py python <modulo>                  l'interprete di {python} del modulo (exit 2: non lo usa)
  maat-config.py chiave <modulo>                  le voci chiave: «etichetta<TAB>file|comando|assente<TAB>cartella<TAB>valore»
  maat-config.py elenco-moduli
  maat-config.py generati [--verifica]
      i file generati rigenerabili da implement/fix: una riga per voce, «percorso | cartella | comando | test |
      ambiente» (ambiente = quello del modulo che contiene la cartella, nativo fuori da ogni modulo); nessuna voce
      = nessuna riga. --verifica controlla le voci sul progetto (PROJECT_ROOT): generato, cartella, test e script
      del comando esistono, il test nomina il generato; «ERRORE: generati.<i>: …» ed exit 1, altrimenti
      «generati: <n> voci verificate».
  maat-config.py sonda-produzione
  maat-config.py componi <profilo>… --radice <modulo>=<percorso> [--radice …] [--nativo]
      --nativo (pk06, /maat:setup senza WSL o fuori da Windows): ogni modulo ha ambiente nativo e niente copia;
      comandi.test e comandi.lint che chiamavano test-fast.sh diventano il comando della copia eseguito nel repo
      (copia.test; per il lint la prima alternativa senza se_esiste o il cui se_esiste esiste nel progetto,
      relativo alla sua cartella, senza {cache?…}); lint_base resta solo se il
      lint ha ancora {base?…}; piattaforma.copia_wsl: no.

Importabile (importlib, dal percorso in MAAT_CONFIG_PY): carica(), risolto(cfg), modulo_di(risolto, percorso) e
comando(cfg, modulo, tipo, file=…, test=…, …) sono le funzioni dei comandi modulo-di e comando, senza stampa:
plan-check.sh, counterproof.sh, blocks-independent.py, context-pack.sh e worktree-lib.sh le usano così, con una sola
implementazione per bash e Python.

Dove trova il file: MAAT_CONFIG, altrimenti <PROJECT_ROOT>/.claude/maat.json (PROJECT_ROOT dall'ambiente,
altrimenti `git rev-parse --show-toplevel` dalla cartella corrente). {maat} = MAAT_ROOT, altrimenti la radice del
plugin che contiene questo file.

Uscite: 0 ok · 1 configurazione non valida · 2 nessun modulo / comando non dichiarato · 3 chiave assente (leggi),
comando saltato e NOT RUN (dichiarato) (comando), ripiego del nucleo (sonda-produzione) · 4 progetto non
configurato · 64 uso sbagliato.
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
VERSIONE_PRECEDENTE = None   # accettata con un avviso (R9); None finché esiste solo la 1
CARTELLE = ("radice", "radice_pacchetti", "repo")
SALTA_DIR = {"node_modules", ".git", ".venv", ".nuxt", ".output", "__pycache__"}


class Uscita(Exception):
    def __init__(self, codice, messaggio=""):
        super().__init__(messaggio)
        self.codice, self.messaggio = codice, messaggio


def err(msg):
    sys.stderr.write("maat-config: %s\n" % msg)


# --------------------------------------------------------------------------- validazione strutturale
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
    """Validatore minimo: type (anche lista), enum, pattern, required, properties, additionalProperties: false, items."""
    t = sch.get("type")
    if t is not None:
        tipi = t if isinstance(t, list) else [t]
        if not any(TIPI[x](v) for x in tipi):
            errori.append((chiave, "tipo %s atteso, trovato %s" % (" o ".join(tipi), nome_tipo(v))))
            return
    if "enum" in sch and not any(v == e and type(v) is type(e) for e in sch["enum"]):
        errori.append((chiave, "valore %s fuori elenco (ammessi: %s)"
                       % (json.dumps(v, ensure_ascii=False), ", ".join(str(e) for e in sch["enum"]))))
    if "pattern" in sch and isinstance(v, str) and not re.fullmatch(sch["pattern"], v):
        errori.append((chiave, "valore %s non rispetta la forma %s" % (json.dumps(v, ensure_ascii=False), sch["pattern"])))
    if isinstance(v, dict):
        for k in sch.get("required", []):
            if k not in v:
                errori.append((unisci(chiave, k), "chiave obbligatoria mancante"))
        props = sch.get("properties", {})
        ap = sch.get("additionalProperties", True)
        for k, x in v.items():
            if k in props:
                valida_struttura(x, props[k], unisci(chiave, k), errori)
            elif ap is False:
                errori.append((unisci(chiave, k), "chiave sconosciuta"))
    if isinstance(v, list) and "items" in sch:
        for i, x in enumerate(v):
            valida_struttura(x, sch["items"], unisci(chiave, i), errori)


# --------------------------------------------------------------------------- validazione semantica
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
            yield "moduli.%d.specchio" % i, "obbligatoria con regola_test: specchio (S1)"


def s2(cfg):
    for i, m in moduli(cfg):
        c = m.get("comandi", {})
        if "test" in c and "{test}" not in testo(c["test"]):
            yield "moduli.%d.comandi.test" % i, "il comando di test deve contenere {test} (S2)"
        if "lint" in c and "{file}" not in testo(c["lint"]):
            yield "moduli.%d.comandi.lint" % i, "il comando di lint deve contenere {file} (S2)"
        for j, v in enumerate(m.get("controlli", [])):
            if "{file}" not in v.get("comando", ""):
                yield "moduli.%d.controlli.%d.comando" % (i, j), "il comando di un controllo deve contenere {file} (S2)"


def s3(cfg):
    v = cfg.get("versione_schema")
    if v > VERSIONE_CORRENTE:
        yield "versione_schema", "versione futura: aggiorna il plugin (%d, il lettore arriva a %d) (S3)" % (v, VERSIONE_CORRENTE)
    elif v != VERSIONE_CORRENTE and v != VERSIONE_PRECEDENTE:
        yield "versione_schema", "versione %d non più supportata: il lettore accetta %s (S3)" % (
            v, " e ".join(str(x) for x in (VERSIONE_CORRENTE, VERSIONE_PRECEDENTE) if x is not None))


def s4(cfg):
    for i, m in moduli(cfg):
        if m.get("lint_base") is True and "{base?" not in testo(m.get("comandi", {}).get("lint")):
            yield "moduli.%d.comandi.lint" % i, "lint_base: true chiede un comando lint con {base?…} (S4)"


def s5(cfg):
    for i, m in moduli(cfg):
        for k in ("test", "lint"):
            if "test-fast.sh" in testo(m.get("comandi", {}).get(k)) and k not in m.get("copia", {}):
                yield "moduli.%d.copia.%s" % (i, k), "comandi.%s usa test-fast.sh: serve copia.%s, il comando dentro la copia (S5)" % (k, k)


def s6(cfg):
    for i, m in moduli(cfg):
        for k, c in m.get("copia", {}).items():
            alt = alternative(c)
            for j, a in enumerate(alt):
                if "test-fast.sh" in testo(a):
                    chiave = "moduli.%d.copia.%s" % (i, k) + (".%d" % j if isinstance(c, list) else "")
                    yield chiave, "un comando di copia non può chiamare test-fast.sh (autorichiamo) (S6)"


def s7(cfg):
    for i, m in moduli(cfg):
        cp = m.get("copia", {})
        if "test" in cp and "{test}" not in testo(cp["test"]):
            yield "moduli.%d.copia.test" % i, "copia.test deve contenere {test} (S7)"
        for k in ("lint", "lint_messaggi"):
            if k not in cp:
                continue
            for j, a in enumerate(alternative(cp[k])):
                if "{file}" not in testo(a):
                    chiave = "moduli.%d.copia.%s" % (i, k) + (".%d" % j if isinstance(cp[k], list) else "")
                    yield chiave, "copia.%s deve contenere {file} (S7)" % k


def s8(cfg):
    for i, m in moduli(cfg):
        if m.get("regola_test") == "nessuna" and "test" in m.get("comandi", {}):
            yield "moduli.%d.comandi.test" % i, "regola nessuna ma comando di test dichiarato (S8)"


NON_GENERATI = re.compile(r"golden|__snapshots__|lint-baseline", re.I)


def s9(cfg):
    for i, g in enumerate(cfg.get("generati", [])):
        for k in ("percorso", "test"):
            if NON_GENERATI.search(g.get(k, "")):
                yield "generati.%d.%s" % (i, k), "golden, snapshot e base del lint non sono generati da rigenerare (S9)"


def s10(cfg):
    for i, m in moduli(cfg):
        if m.get("preparati") and not m.get("preparazione"):
            yield "moduli.%d.preparati" % i, "preparati chiede preparazione, il comando che li scrive (S10)"


# Controlli semantici: dichiarati qui e nella `description` dello schema.
SEMANTICA = [
    ("S1", "regola_test specchio => specchio presente", s1),
    ("S2", "comandi.test con {test}; comandi.lint e controlli[].comando con {file}", s2),
    ("S3", "versione_schema accettata dal lettore", s3),
    ("S4", "lint_base true => comandi.lint con {base?…}", s4),
    ("S5", "comandi con test-fast.sh => copia con la voce corrispondente", s5),
    ("S6", "nessun comando di copia chiama test-fast.sh", s6),
    ("S7", "copia.test con {test}; copia.lint e copia.lint_messaggi con {file}", s7),
    ("S8", "regola_test nessuna => nessun comandi.test", s8),
    ("S9", "generati[]: nessun golden, snapshot o base del lint", s9),
    ("S10", "moduli[].preparati => preparazione presente", s10),
]


# --------------------------------------------------------------------------- caricamento
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
    """Strutturale, poi semantica. Errori: «<file>: <chiave>: <motivo>» ed exit 1."""
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
        err("%s: versione_schema %d è la precedente: migra alla %d (R9)" % (nome, VERSIONE_PRECEDENTE, VERSIONE_CORRENTE))


def carica(arg=None):
    p = percorso_config(arg)
    if not os.path.isfile(p):
        raise Uscita(4, "progetto non configurato: lancia /maat:setup (manca %s)" % p)
    try:
        with open(p, encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        err("%s: (file): JSON non leggibile: %s" % (p, e))
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


# --------------------------------------------------------------------------- utilità
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
    """{file} e {test}: liste, ogni voce quotata; {x?prefisso}: prefisso + valore quotato + spazio, oppure niente."""
    def sost(mo):
        nome, opz, pref = mo.group(1), mo.group(2), mo.group(3)
        v = valori.get(nome)
        if opz is not None:
            if v is None or v == "" or v == []:
                return ""
            return pref + sq(v) + " "   # un argomento intero: separato da ciò che segue

        if nome in ("file", "test"):
            return " ".join(sq(x) for x in (v or []))
        if nome == "nome":
            return mo.group(0) if v is None else sq(v)
        if nome == "python":
            if v is None:
                raise NonRisolto("python non trovato: {python} non risolvibile")
            return sq_se_serve(v)
        if nome == "maat":
            return sq(v)   # sempre quotata, come lo script in gates.sh (`bash $(sq "$VF")`)
        return mo.group(0) if v is None else sq_se_serve(v)
    return re.sub(r"[ \t]+$", "", SEGNAPOSTO.sub(sost, testo_cmd))


def python_risponde(p):
    """pk09: il ripiego python3 dal PATH sotto …/WindowsApps/ puo' essere lo stub dello Store (senza argomenti apre
    lo Store, con argomenti esce 9009) o il Python Install Manager (vero). Sonda SEMPRE con argomenti e un timeout;
    fuori da WindowsApps nessuna sonda."""
    if "/windowsapps/" not in p.lower():
        return True
    try:
        r = subprocess.run([p, "-c", "import sys"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return False
    return r.returncode == 0


def python_dal_path(v, scartato):
    """pk09: il primo `v` del PATH (`scartato`) non risponde: si cerca negli ALTRI elementi del PATH, in ordine,
    una cartella alla volta; si sondano solo i percorsi sotto WindowsApps (python_risponde)."""
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
        # una lista = alternative in ordine (la prima che esiste; nessuna -> l'ultimo percorso); una stringa = una
        # lista di uno, il suo percorso vale anche se non esiste (come prima). Un nome senza / si cerca nel PATH.
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
                # solo l'ultimo ripiego (python3 dal PATH): moduli[].python e piattaforma.python restano come prima
                if i == 2 and not python_risponde(w):
                    w = python_dal_path(v, w)   # lo stub e' il primo del PATH: gli altri elementi, in ordine
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
            raise Uscita(64, "%s è fuori dalla cartella del comando (%s)" % (f, base))
    return out


def presente(se_presente, radice_abs):
    if any(c in se_presente for c in "*?/"):
        return esistono(radice_abs, se_presente)
    return shutil.which(se_presente) is not None


# --------------------------------------------------------------------------- comandi
def cmd_valida(args):
    if len(args) > 1:
        raise Uscita(64, "uso: valida [file]")
    _cfg, p = carica(args[0] if args else None)
    print("maat-config: %s valido" % p)


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
        raise Uscita(64, "uso: leggi <chiave.puntata> [--default x] | leggi --tutto")
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
            raise Uscita(3, "chiave assente: %s" % args[0])
    print(formatta(v))


def instrada(r, p):
    """(nome, "radice" | "pacchetti") del file p (relativo al repo), None fuori da ogni modulo."""
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
    """Il modulo del file (relativo al repo) nella configurazione RISOLTA r (risolto(cfg)): (nome, "radice" |
    "pacchetti"), None fuori da ogni modulo. La stessa regola del comando modulo-di, importabile (plan-check.sh,
    counterproof.sh, blocks-independent.py)."""
    return instrada(r, percorso)


def cmd_modulo_di(args):
    if len(args) != 1:
        raise Uscita(64, "uso: modulo-di <file relativo al repo>")
    cfg, _p = carica()
    d = modulo_di(risolto(cfg), args[0])
    if d is None:
        raise Uscita(2)
    print("%s %s" % d)


def modulo_di_nome(r, nome):
    m = next((x for x in r["moduli"] if x["nome"] == nome), None)
    if m is None:
        raise Uscita(2, "modulo sconosciuto: %s" % nome)
    return m


def cmd_gate_richiesti(args):
    """I gate di un livello: una riga «etichetta<TAB>modulo<TAB>tipo» (tipo = test | controlli | lint | build).
    tests-<modulo> per ogni modulo con comandi.test o con un file toccato sotto la radice (senza comando di test
    il gate è NOT RUN dichiarato); controlli-<modulo> per ogni modulo con controlli; lint e build per i moduli
    che li dichiarano, senza suffisso se è uno solo. Ordine: tests, controlli, lint, build, ognuno per etichetta.
    legacy = std. La stessa funzione per gates.sh (quali eseguire) e finalize.sh (quali richiedere)."""
    if not args:
        raise Uscita(64, "uso: gate-richiesti <min|std|full|legacy> [--file f]…")
    livello = "std" if args[0] == "legacy" else args[0]
    if livello not in ("min", "std", "full"):
        raise Uscita(64, "livello sconosciuto: %s (min|std|full|legacy)" % args[0])
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
    """regola accanto: un file di test toccato (se esiste); per un sorgente il test con lo stesso nome nella sua
    cartella, altrimenti ovunque sotto la radice (senza node_modules, .nuxt, .output)."""
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
    """Regex del glob g in cui {m} vale sost (già una regex)."""
    return sost.join(glob_re(x).pattern for x in g.split("{m}"))


def test_specchio(rad_abs, rel, sp):
    """regola specchio: un file che corrisponde a `a` (con {m} qualunque) è un test toccato (se esiste); un file
    che corrisponde a `da` dà i file che corrispondono a `a` con lo stesso {m}."""
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
    """I test selezionati dalla regola_test del modulo per i file toccati: uno per riga, relativi al repo,
    ordinati e senza doppioni. regola nessuna: nessuno. I file fuori dalla radice si ignorano."""
    if not args:
        raise Uscita(64, "uso: test-di <modulo> [--file f]…")
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
    """L'interprete del modulo (precedenza di {python}), se un suo comando, controllo o voce di chiave usa
    {python}: exit 2 se nessuno lo usa, 3 se non si risolve."""
    if len(args) != 1:
        raise Uscita(64, "uso: python <modulo>")
    cfg, p = carica()
    m = modulo_di_nome(risolto(cfg), args[0])
    if not any("{python}" in t for t in testi_del_modulo(m)):
        raise Uscita(2)
    py = risolvi_python(cfg, m, radice_progetto(p))
    if py is None:
        raise Uscita(3, "python non trovato per %s" % args[0])
    print(py)


def cmd_chiave(args):
    """Le voci `chiave` del modulo, una riga «etichetta<TAB>tipo<TAB>cartella<TAB>valore»: tipo file (valore = il
    file, relativo alla cartella) o comando (valore = il comando espanso, {python} e {maat} compresi); assente se
    il comando non si risolve. cartella relativa al repo («.» = il repo)."""
    if len(args) != 1:
        raise Uscita(64, "uso: chiave <modulo>")
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
            raise Uscita(64, "opzione sconosciuta o senza valore: %s" % a)
    return val


def comando(cfg, modulo, tipo, file=(), test=(), base=None, cache=None, report=None, nome=None, root=None):
    """Il comando <tipo> del modulo, espanso: lista di coppie (cartella d'esecuzione relativa al repo, "" = il repo;
    comando). Una coppia, salvo controlli (una per voce e per file). cfg = la configurazione di carica(); file e
    test relativi al repo; root = la radice del progetto (default: radice_progetto()). Le uscite come il comando
    `comando` (Uscita 2 non dichiarato, 3 saltato e NOT RUN dichiarato, 64 percorso fuori dalla cartella), di cui e'
    l'implementazione: lo usano anche plan-check.sh e counterproof.sh importando questo file."""
    if tipo not in ("test", "lint", "build", "controlli", "controprova"):
        raise Uscita(64, "tipo sconosciuto: %s" % tipo)
    r = risolto(cfg)
    root = (root or radice_progetto()).replace("\\", "/").rstrip("/")
    m = next((x for x in r["moduli"] if x["nome"] == modulo), None)
    if m is None:
        raise Uscita(2, "modulo sconosciuto: %s" % modulo)
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
                err("SALTATA: %s — NOT RUN (dichiarato): %s assente" % (v["comando"], v["se_presente"]))
                saltate += 1
                continue
            try:
                # una riga per file: `bash -n a b` e `node --check a b` controllano solo a,
                # `python -m json.tool a b` scriverebbe su b
                out.extend([espansa(norm(m["radice"]), v["comando"], "file", [f]) for f in files])
                eseguite += 1
            except NonRisolto as e:
                err("SALTATA: %s — NOT RUN (dichiarato): %s" % (v["comando"], e))
                saltate += 1
        if eseguite:
            return out
        if saltate:
            raise Uscita(3)
        raise Uscita(2, "nessun controllo per questi file nel modulo %s" % modulo)

    if tipo == "controprova":
        c = m.get("controprova", {}).get("comando")
        if not c:
            raise Uscita(2, "controprova.comando non dichiarato per %s" % modulo)
        c = {"comando": c}
    else:
        c = m.get("comandi", {}).get(tipo)
        if c is None:
            raise Uscita(2, "comando %s non dichiarato per %s" % (tipo, modulo))
        if isinstance(c, str):
            c = {"comando": c}
    if c.get("se_presente") and not presente(c["se_presente"], radice_abs):
        raise Uscita(3, "NOT RUN (dichiarato): %s assente per %s.%s" % (c["se_presente"], modulo, tipo))
    cart = cartella_di(m, c.get("cartella", "radice"))
    files = rebase(file, cart)
    tests = rebase(test, cart)
    valori["file"] = files
    try:
        out.append(espansa(cart, c["comando"], "test", tests))
    except NonRisolto as e:
        raise Uscita(3, "NOT RUN (dichiarato): %s" % e)
    return out


def cmd_comando(args):
    if len(args) < 2:
        raise Uscita(64, "uso: comando <modulo> <test|lint|build|controlli|controprova> [opzioni]")
    nome, tipo = args[0], args[1]
    if tipo not in ("test", "lint", "build", "controlli", "controprova"):
        raise Uscita(64, "tipo sconosciuto: %s" % tipo)
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
            raise Uscita(2, "modulo sconosciuto: %s (MAAT_MODULO)" % nome)
        if not m.get("copia"):
            raise Uscita(2, "il modulo %s non dichiara copia (MAAT_MODULO)" % nome)
        return m
    con = [x for x in r["moduli"] if x.get("copia")]
    if len(con) == 1:
        return con[0]
    if not con:
        raise Uscita(2, "nessun modulo dichiara copia")
    raise Uscita(64, "più moduli con copia: imposta MAAT_MODULO")


def relativa(radice, pacchetti):
    """La radice relativa a radice_pacchetti ("" se coincidono)."""
    if radice == pacchetti:
        return ""
    if pacchetti == "" or radice.startswith(pacchetti + "/"):
        return radice[len(pacchetti) + 1:] if pacchetti else radice
    raise Uscita(1, "radice %s fuori da radice_pacchetti %s" % (radice, pacchetti))


def cmd_copia_modulo(args):
    if args:
        raise Uscita(64, "uso: copia-modulo")
    cfg, _p = carica()
    m = modulo_della_copia(risolto(cfg))
    print("\n".join([m["nome"], norm(m["radice"]), norm(m["radice_pacchetti"]),
                     "true" if m.get("lint_base") else "false", m.get("preparazione", "")]))


def cmd_comando_copia(args):
    if len(args) < 2:
        raise Uscita(64, "uso: comando-copia <modulo> <test|lint|lint_messaggi> --copia <dir> [opzioni]")
    nome, tipo = args[0], args[1]
    if tipo not in ("test", "lint", "lint_messaggi"):
        raise Uscita(64, "tipo sconosciuto: %s" % tipo)
    o = opzioni(args[2:], ("file", "test"), ("copia", "pacchetto", "cache"))
    if not o["copia"]:
        raise Uscita(64, "comando-copia: --copia <dir> obbligatoria")
    copia_dir = o["copia"].replace("\\", "/").rstrip("/")
    cfg, p = carica()
    r = risolto(cfg)
    m = next((x for x in r["moduli"] if x["nome"] == nome), None)
    if m is None:
        raise Uscita(2, "modulo sconosciuto: %s" % nome)
    c = m.get("copia", {}).get(tipo)
    if c is None:
        raise Uscita(2, "copia.%s non dichiarato per %s" % (tipo, nome))
    gruppo = relativa(norm(m["radice"]), norm(m["radice_pacchetti"]))

    def cart_rel(a):
        if o["pacchetto"] is not None:
            return norm(o["pacchetto"])
        quale = a.get("cartella", "radice")
        if quale == "repo":
            raise Uscita(1, "copia.%s di %s: la cartella repo non esiste nella copia" % (tipo, nome))
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
        raise Uscita(2, "copia.%s di %s: nessuna alternativa applicabile (se_esiste)" % (tipo, nome))
    cart = cart_rel(scelta)
    valori = {"maat": (os.environ.get("MAAT_ROOT") or PLUGIN).replace("\\", "/"), "cache": o["cache"],
              "file": rebase(o["file"], cart), "test": rebase(o["test"], cart)}
    if "{python}" in scelta["comando"]:
        valori["python"] = risolvi_python(cfg, m, radice_progetto(p))
    try:
        riga = espandi(scelta["comando"], valori)
    except NonRisolto as e:
        raise Uscita(3, "NOT RUN (dichiarato): %s" % e)
    print(assoluta(cart))
    print(riga)


def cmd_elenco(args):
    if args:
        raise Uscita(64, "uso: elenco-moduli")
    cfg, _p = carica()
    for m in cfg["moduli"]:
        print(m["nome"])


def cmd_generati(args):
    if args not in ([], ["--verifica"]):
        raise Uscita(64, "uso: generati [--verifica]")
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
            errori.append("%s: generato assente: %s" % (k, pg))
        if not os.path.isdir(posixpath.join(root, cart or ".")):
            errori.append("%s: cartella assente: %s" % (k, cart or "."))
        if not os.path.isfile(posixpath.join(root, tst)):
            errori.append("%s: test assente: %s" % (k, tst))
        script = next((w for w in g["comando"].split() if re.search(r"\.(py|mjs|js|sh)$", w)), None)
        if script is None:
            errori.append("%s: il comando non nomina uno script (.py .mjs .js .sh)" % k)
        elif not os.path.isfile(posixpath.join(root, cart or ".", script)):
            errori.append("%s: script del comando assente: %s" % (k, posixpath.join(cart, script) if cart else script))
        if os.path.isfile(posixpath.join(root, tst)):
            with open(posixpath.join(root, tst), encoding="utf-8", errors="replace") as fh:
                if posixpath.basename(pg) not in fh.read():
                    errori.append("%s: %s non nomina %s: non e' il test che lo confronta" % (k, tst, posixpath.basename(pg)))
    for e in errori:
        print("ERRORE: %s" % e)
    if errori:
        raise Uscita(1)
    print("generati: %d voci verificate" % len(voci))


def cmd_sonda(args):
    if args:
        raise Uscita(64, "uso: sonda-produzione")
    cfg, _p = carica()
    g = cfg.get("guardia", {})
    if g.get("produzione") and g.get("sonde"):
        print("curl -s https://%s/" % g["sonde"][0])
        return
    print("git push --force origin x")
    raise Uscita(3)


def nativo(out):
    """componi --nativo: niente WSL. La copia si toglie; un comando che passava da test-fast.sh diventa il comando
    che test-fast.sh eseguiva dentro la copia (S5: senza copia non si puo' chiamare test-fast.sh)."""
    out.setdefault("piattaforma", {})["copia_wsl"] = "no"
    root = radice_progetto()

    def applicabile(a, m):
        # come comando-copia: vale la prima alternativa senza se_esiste o il cui se_esiste esiste, qui nel progetto
        # (relativo alla cartella dell'alternativa: radice o radice_pacchetti del modulo)
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
            raise Uscita(64, "opzione sconosciuta: %s" % args[i])
        else:
            nomi.append(args[i])
            i += 1
    if not nomi or len(nomi) != len(radici):
        raise Uscita(64, "uso: componi <profilo>… --radice <modulo>=<percorso> (una --radice per profilo)")
    out = {"versione_schema": VERSIONE_CORRENTE, "lingua": "it"}
    mods = []
    for nome, (mod, rad) in zip(nomi, radici):
        f = posixpath.join(PROFILI, nome + ".json")
        if not os.path.isfile(f):
            raise Uscita(64, "profilo sconosciuto: %s (in %s)" % (nome, PROFILI))
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
