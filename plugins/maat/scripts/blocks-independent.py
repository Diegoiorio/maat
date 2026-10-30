#!/usr/bin/env python3
"""blocks-independent.py — i blocchi di implementazione possono girare in due CORSIE parallele? (harness-pt13, L1)

  blocks-independent.py [--root <repo>] <procedura.txt>
      Legge le righe "blocco <id>: scrive=a,b · dopo=B1" che `plan-check.sh gen` scrive in gen/procedura.txt
      (formato 2, pt10) e decide. Stampa:
        blocks-independent: esito=parallelo corsie=2        (exit 0)
        corsia 1: B1                 corsia 2: B2,B3        (blocchi, nell'ordine del piano)
        scope 1: <file,...>          scope 2: <file,...>    (l'unione dei loro scrive:, per FIC_WRITE_SCOPE)
      oppure
        blocks-independent: esito=serie motivo=<perche'>    (exit 1)
      e, in entrambi i casi, una riga "dipendenza: <A>~<B> — <motivo>" per ogni coppia dipendente.
      Exit 2 = uso errato o procedura illeggibile (per chi chiama: serie).

  blocks-independent.py --posteriori <corsie.txt> <cambiati.txt> [<dichiarati-1.txt> <dichiarati-2.txt>]
      CONTROLLO A POSTERIORI: <corsie.txt> e' l'output del modo sopra (righe scope k:), <cambiati.txt> i path
      cambiati fra il tree di prima e quello di dopo le corsie (git diff --name-only), <dichiarati-k.txt> i file
      che la corsia k dichiara nel suo esito ("file" del JSON). Divide il diff per scope e stampa
        posteriori: esito=OK corsia 1: <file,...> · corsia 2: <file,...>     (exit 0)
      oppure "posteriori: esito=STOP — <motivo>" (exit 1) se un file cambiato e' fuori dall'unione degli scope,
      e' attribuito a ENTRAMBE le corsie (nel suo scope e dichiarato dall'altra), o e' un file condiviso o
      generato (anche se l'ha scritto un tool lanciato via Bash); anche se un file d'ingresso non si legge.
      Eccezione: un file dei `generati` di .claude/maat.json (rigenerato col suo comando) fuori dagli scope e'
      della corsia che lo dichiara; dichiarato da nessuna o da entrambe => STOP.
      Un blocco senza scrive: (scope di corsia vuoto) => serie.

I MODULI vengono da .claude/maat.json del repository (MAAT_CONFIG vince), letti IMPORTANDO maat-config.py
(MAAT_CONFIG_PY, default accanto a questo file): le stesse funzioni del comando modulo-di. Progetto non configurato:
nessun modulo e nessun adattatore. Configurazione non valida: exit 2 (per chi chiama: serie).

DUE BLOCCHI SONO INDIPENDENTI solo se valgono tutte e tre (una falsa => dipendenti):
  1. scrive: disgiunti (un path uguale, o uno dentro una cartella dell'altro);
  2. nessuna dipendenza nel GRAFO REALE, in nessuna delle due direzioni, e nessun dopo: fra i due:
     - import espliciti dei file che ESISTONO (JS/TS/Vue: from/import()/require relativi, @repo/<pkg> su
       <radice_pacchetti del modulo>/packages/<pkg>; Python: import/from, assoluti sulla radice del modulo del file,
       relativi sul pacchetto) risolti su un file dell'altro blocco;
     - con l'adattatore `nuxt-autoimport` (campo `framework` di maat.json, solo se dichiarato), per i moduli con
       `preparati` sotto .nuxt/: gli alias ~/ @/ ~~/ @@/ risolti sulla radice del modulo, e i componenti e
       composable AUTO-IMPORTATI usati senza import: i nomi e i file che li definiscono si leggono da
       <radice>/.nuxt/components.d.ts e .nuxt/imports.d.ts; un identificatore del file (tag PascalCase o
       kebab-case compresi) che nomina un file dell'altro blocco;
     - in piu' (stesso adattatore), per OGNI file (nuovo o esistente: un .nuxt vecchio non ha i nomi di oggi) i
       nomi auto-importati si ricavano dal percorso: components/goals/Foo.vue -> GoalsFoo (e LazyGoalsFoo),
       composables|utils/useX.ts -> useX;
     - FAIL-CLOSED: se un blocco scrive sotto la radice di un modulo dell'adattatore e i suoi .nuxt/components.d.ts
       o imports.d.ts non si leggono, il grafo non e' conoscibile => serie ("motivo=.nuxt/*.d.ts assenti");
     - senza adattatori valgono solo gli import espliciti;
  3. nessuno dei due tocca file CONDIVISI o GENERATI (CONDIVISI sotto): barrel (__init__.py, index.ts/js),
     package*.json e lockfile, i18n, __snapshots__, .nuxt/, migrazioni. Uno solo basta: tutta la fase in serie.
Le corsie sono al piu' 2: le componenti connesse del grafo delle dipendenze, ripartite in due gruppi (la piu'
grande per prima nella corsia meno carica). Una sola componente => serie, come prima.

Limite dichiarato: la dipendenza di un file NUOVO verso l'altro blocco (cio' che il file importera') non e'
conoscibile prima di scriverlo. La copre il driver: gate sull'albero intero a corsie finite (gates.sh).
Test: scripts/blocks-independent.test.sh del plugin.
"""
import os
import re
import subprocess
import sys

CONDIVISI = re.compile(
    r"(^|/)__init__\.py$|(^|/)index\.(ts|js|mjs|cjs)$"                          # barrel
    r"|(^|/)package(-lock)?\.json$|(^|/)(yarn\.lock|pnpm-lock\.yaml|poetry\.lock|uv\.lock|Pipfile\.lock)$"
    r"|(^|/)requirements[^/]*\.txt$"                                              # dipendenze e lockfile
    r"|(^|/)(i18n|locales?|lang)/"                                                # traduzioni
    r"|(^|/)__snapshots__/|(^|/)\.nuxt/|(^|/)\.output/"                           # generati
    r"|(^|/)migrations/")                                                         # migrazioni
EXT = (".d.ts", ".tsx", ".ts", ".mjs", ".cjs", ".js", ".vue", ".py")
CODE_EXT = (".ts", ".tsx", ".js", ".mjs", ".cjs", ".vue", ".py")
BLOCCO = re.compile(r"^blocco[ \t]+(\S+):[ \t]*scrive=(.*?)[ \t]*·[ \t]*dopo=(.*)$")
JS_IMPORT = re.compile(r"""(?:\bfrom\s*|\bimport\s*\(\s*|\bimport\s+|\brequire\s*\(\s*)['"]([^'"\n]+)['"]""")
PY_FROM = re.compile(r"^[ \t]*from[ \t]+(\.*[\w.]*)[ \t]+import[ \t]+\(?([^\n#]*)", re.M)
PY_IMPORT = re.compile(r"^[ \t]*import[ \t]+([\w., \t]+)", re.M)
IDENT = re.compile(r"[A-Za-z_$][\w$]*")
KEBAB_TAG = re.compile(r"<([a-z][a-z0-9]*(?:-[a-z0-9]+)+)")
DTS_COMP = re.compile(r"""^\s*'?(\w+)'?\s*:\s*typeof import\(["']([^"']+)["']\)""", re.M)
DTS_CONST = re.compile(r"""^export const (\w+)\s*:\s*typeof import\(["']([^"']+)["']\)""", re.M)
DTS_IMPORT = re.compile(r"""^export \{([^}]*)\} from ['"]([^'"]+)['"]""", re.M)


def posix(p):
    p = p.replace("\\", "/").strip()
    while p.startswith("./"):
        p = p[2:]
    return p


def key(p):
    """Chiave di confronto di un file: senza estensione e senza /index o /__init__ finale."""
    p = posix(p).rstrip("/")
    for e in EXT:
        if p.endswith(e):
            p = p[: -len(e)]
            break
    for tail in ("/index", "/__init__"):
        if p.endswith(tail):
            p = p[: -len(tail)]
    return p


def normpath(p):
    parts = []
    for seg in posix(p).split("/"):
        if seg in ("", "."):
            continue
        if seg == "..":
            if parts:
                parts.pop()
        else:
            parts.append(seg)
    return "/".join(parts)


def overlap(a, b):
    """Stesso path, o uno dentro l'altro (un elemento di scrive: puo' essere una cartella)."""
    a, b = posix(a).rstrip("/"), posix(b).rstrip("/")
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


def refers(target, files, prefix=False):
    """`target` (chiave di un modulo; con prefix=True una cartella di pacchetto @repo/…) nomina uno dei file?"""
    return next((f for f in files if key(f) == target or (prefix and key(f).startswith(target + "/"))), None)


def pascal(s):
    return "".join(w[:1].upper() + w[1:] for w in re.split(r"[-_.\s]+", s) if w)


def configurazione(root):
    """(lettore, moduli risolti, adattatori) da maat.json: MAAT_CONFIG, altrimenti <root>/.claude/maat.json, letta
    con maat-config.py importato (MAAT_CONFIG_PY, default accanto a questo file). Progetto non configurato: nessun
    modulo e nessun adattatore; configurazione non valida o lettore assente: SystemExit (exit 2)."""
    import importlib.util
    p = os.environ.get("MAAT_CONFIG_PY") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "maat-config.py")
    try:
        import sys; sys.dont_write_bytecode = True   # nessun __pycache__ sotto MAAT_ROOT
        sp = importlib.util.spec_from_file_location("maat_config", p)
        mc = importlib.util.module_from_spec(sp)
        sp.loader.exec_module(mc)
    except Exception as e:
        raise SystemExit("blocks-independent: lettore della configurazione non caricabile (%s): %s" % (p, e))
    try:
        cfg, _p = mc.carica(os.environ.get("MAAT_CONFIG") or os.path.join(root, ".claude", "maat.json"))
    except mc.Uscita as u:
        if u.codice == 4:
            return mc, [], []
        raise SystemExit("blocks-independent: maat.json: %s" % (u.messaggio or "configurazione non valida (uscita %d)" % u.codice))
    r = mc.risolto(cfg)
    return mc, r["moduli"], r.get("framework", [])


def derived_names(f, nuxt):
    """Nomi auto-importati di un file NUOVO, dal percorso (regola di Nuxt, prefisso di cartella non ripetuto):
    solo sotto la radice `nuxt` di un modulo dell'adattatore nuxt-autoimport (None: nessun nome)."""
    f = posix(f)
    if nuxt is None or not (nuxt == "" or f.startswith(nuxt + "/")):
        return set()
    rel = f[len(nuxt) + 1:] if nuxt else f
    stem = re.sub(r"\.(vue|tsx|ts|js|mjs)$", "", rel)
    if rel.startswith("components/") and rel.endswith((".vue", ".tsx", ".ts", ".js")):
        parts = stem.split("/")[1:]
        if parts and parts[-1] == "index":
            parts = parts[:-1]
        dirs, leaf = pascal(" ".join(parts[:-1])), pascal(parts[-1]) if parts else ""
        name = leaf if dirs and leaf.lower().startswith(dirs.lower()) else dirs + leaf
        return {name, "Lazy" + name} if name else set()
    if rel.startswith(("composables/", "utils/")):
        parts = stem.split("/")
        leaf = parts[-2] if parts[-1] == "index" and len(parts) > 2 else parts[-1]
        return {leaf} if leaf and leaf != "index" else set()
    return set()


class Grafo:
    def __init__(self, root, conf=None):
        self.root = root
        self.mc, self.mods, adattatori = conf if conf is not None else configurazione(root)
        self.r = {"moduli": self.mods}
        # adattatore nuxt-autoimport: solo se dichiarato, per i moduli con preparati sotto .nuxt/
        self.nuxt = [self.mc.norm(m["radice"]) for m in self.mods
                     if "nuxt-autoimport" in adattatori and any(posix(g).startswith(".nuxt/") for g in m.get("preparati", []))]
        self.auto = {}   # nome auto-importato -> chiave del file che lo definisce
        self.dts_ko = []   # radici dell adattatore senza .nuxt/*.d.ts leggibili: grafo non conoscibile (fail-closed)
        for n in self.nuxt:
            dts = os.path.join(root, n, ".nuxt")
            ok_c = self._dts(os.path.join(dts, "components.d.ts"), n, DTS_COMP, DTS_CONST)
            ok_i = self._dts(os.path.join(dts, "imports.d.ts"), n, DTS_IMPORT)
            if not (ok_c and ok_i):
                self.dts_ko.append(n)

    def modulo(self, f):
        """il modulo di maat.json del file (radice o pacchetti), o None"""
        d = self.mc.modulo_di(self.r, posix(f))
        return next(m for m in self.mods if m["nome"] == d[0]) if d else None

    def nuxt_di(self, f):
        """la radice del modulo dell adattatore nuxt-autoimport che contiene f (radice o pacchetti; con un solo modulo
        dell adattatore, quello), o None"""
        m = self.modulo(f)
        if m is not None and self.mc.norm(m["radice"]) in self.nuxt:
            return self.mc.norm(m["radice"])
        return self.nuxt[0] if len(self.nuxt) == 1 else None

    def sotto_nuxt(self, f):
        """la radice dell adattatore sotto cui sta f, o None"""
        f = posix(f)
        return next((n for n in self.nuxt if n == "" or f.startswith(n + "/")), None)

    def _dts(self, path, nuxt, *regexps):
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            return False
        base = (nuxt + "/" if nuxt else "") + ".nuxt"
        for rx in regexps:
            for m in rx.finditer(text):
                names, target = m.group(1), m.group(2)
                if not target.startswith("."):
                    continue   # #app/…, pacchetti: non sono file del repository
                k = key(normpath(base + "/" + target))
                for n in re.split(r"[,\s]+", names):
                    n = n.split(" as ")[-1].strip()
                    if n and n != "type":
                        self.auto.setdefault(n, set()).add(k)
        return True

    def exists(self, f):
        return os.path.isfile(os.path.join(self.root, posix(f)))

    def read(self, f):
        try:
            return open(os.path.join(self.root, posix(f)), encoding="utf-8", errors="replace").read()
        except OSError:
            return ""

    def js_target(self, f, spec):
        d = posix(f).rsplit("/", 1)[0] if "/" in posix(f) else ""
        if spec.startswith("."):
            return key(normpath(d + "/" + spec))
        n = self.nuxt_di(f)
        for alias in ("~~/", "@@/", "~/", "@/"):
            if spec.startswith(alias):   # alias di Nuxt: solo con l adattatore
                return key(normpath((n + "/" if n else "") + spec[len(alias):])) if n is not None else None
        m = self.modulo(f)
        if spec.startswith("@repo/") and m is not None:   # pacchetto del workspace del modulo
            rp = self.mc.norm(m["radice_pacchetti"])
            return key(normpath((rp + "/" if rp else "") + "packages/" + spec[len("@repo/"):]))
        return None

    def py_targets(self, f, text):
        f = posix(f)
        m = self.modulo(f)
        base = self.mc.norm(m["radice"]) if m is not None else ""   # import assoluti: dalla radice del modulo
        pkg = f.rsplit("/", 1)[0] if "/" in f else ""
        out = set()

        def mod(m):
            if m.startswith("."):
                lvl = len(m) - len(m.lstrip("."))
                parts = pkg.split("/") if pkg else []
                parts = parts[: len(parts) - (lvl - 1)] if lvl > 1 else parts
                rest = m.lstrip(".").replace(".", "/")
                return normpath("/".join(parts) + ("/" + rest if rest else ""))
            return normpath((base + "/" if base else "") + m.replace(".", "/"))

        for m in PY_FROM.finditer(text):
            b = mod(m.group(1))
            out.add(key(b))
            for n in re.split(r"[,\s()]+", m.group(2)):
                n = n.split(" as ")[0].strip()
                if n and n != "*" and n.isidentifier():
                    out.add(key(b + "/" + n))
        for m in PY_IMPORT.finditer(text):
            for n in m.group(1).split(","):
                n = n.strip().split(" ")[0]
                if n:
                    out.add(key(mod(n)))
        return out

    def uses(self, f, other, other_new_names):
        """Motivo per cui il file f (di un blocco) dipende dai file `other` dell'altro blocco, o None."""
        if not self.exists(f) or not posix(f).endswith(CODE_EXT):
            return None
        text = self.read(f)
        if posix(f).endswith(".py"):
            for t in sorted(self.py_targets(f, text)):
                g = refers(t, other)
                if g:
                    return "%s importa %s" % (f, g)
            return None
        for m in JS_IMPORT.finditer(text):
            t = self.js_target(f, m.group(1))
            g = refers(t, other, m.group(1).startswith("@repo/")) if t else None
            if g:
                return "%s importa %s" % (f, g)
        idents = set(IDENT.findall(text)) | {pascal(t) for t in KEBAB_TAG.findall(text)}
        for n in sorted(idents):
            for k in sorted(self.auto.get(n, ())):
                g = refers(k, other)
                if g:
                    return "%s usa %s (auto-importato da .nuxt, definito in %s)" % (f, n, g)
            if n in other_new_names:
                return "%s usa %s (auto-importato, nome derivato dal percorso di %s)" % (f, n, other_new_names[n])
        return None


def leggi_procedura(path):
    blocks = []
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError as e:
        raise SystemExit("blocks-independent: procedura illeggibile: %s" % e)
    for ln in lines:
        m = BLOCCO.match(ln.strip())
        if m:
            files = [posix(x) for x in m.group(2).split(",") if x.strip() and x.strip() != "(nessuno)"]
            deps = [x.strip() for x in m.group(3).split(",") if x.strip() and x.strip() != "nessuno"]
            blocks.append({"id": m.group(1), "files": files, "dopo": deps})
    return blocks


def dipendenza(a, b, g):
    for f in a["files"]:
        for h in b["files"]:
            if overlap(f, h):
                return "scrive: in comune (%s)" % (f if f == h else f + " / " + h)
    if b["id"] in a["dopo"] or a["id"] in b["dopo"]:
        return "dopo: dichiarato"
    for x, y in ((a, b), (b, a)):
        new_names = {}   # nomi derivati dal percorso: file nuovi ed esistenti (un .nuxt vecchio non li ha)
        for h in y["files"]:
            for n in derived_names(h, g.sotto_nuxt(h)):
                new_names[n] = h
        for f in x["files"]:
            why = g.uses(f, y["files"], new_names)
            if why:
                return why
    return None


def decidi(root, procedura):
    blocks = leggi_procedura(procedura)
    out = []
    if len(blocks) < 2:
        return 1, ["blocks-independent: esito=serie motivo=%d blocco/i nella procedura" % len(blocks)]
    cond = [(b["id"], f) for b in blocks for f in b["files"] if CONDIVISI.search(f)]
    if cond:
        return 1, ["blocks-independent: esito=serie motivo=file condiviso o generato in scrive: (%s: %s)" % cond[0]]
    vuoti = [b["id"] for b in blocks if not b["files"]]
    if vuoti:
        return 1, ["blocks-independent: esito=serie motivo=blocco senza scrive: (%s): scope di corsia vuoto" % ",".join(vuoti)]
    g = Grafo(root)
    ko = next((g.sotto_nuxt(f) for b in blocks for f in b["files"] if g.sotto_nuxt(f) in g.dts_ko), None)
    if ko is not None:
        prep = next((m.get("preparazione") for m in g.mods if g.mc.norm(m["radice"]) == ko), None) or "la preparazione del modulo"
        return 1, ["blocks-independent: esito=serie motivo=.nuxt/*.d.ts assenti (%s.nuxt/components.d.ts o imports.d.ts "
                   "illeggibili: grafo degli auto-import non conoscibile; %s)" % (ko + "/" if ko else "", prep)]
    ids = [b["id"] for b in blocks]
    parent = {i: i for i in ids}

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i, a in enumerate(blocks):
        for b in blocks[i + 1:]:
            why = dipendenza(a, b, g)
            if why:
                out.append("dipendenza: %s~%s — %s" % (a["id"], b["id"], why))
                parent[find(a["id"])] = find(b["id"])
    comps = {}
    for i in ids:
        comps.setdefault(find(i), []).append(i)
    groups = sorted(comps.values(), key=lambda c: (-len(c), ids.index(c[0])))
    if len(groups) < 2:
        return 1, ["blocks-independent: esito=serie motivo=blocchi dipendenti (una sola componente)"] + out
    lanes = [[], []]
    for c in groups:
        min(lanes, key=len).extend(c)
    lanes = [sorted(l, key=ids.index) for l in lanes]
    lanes.sort(key=lambda l: ids.index(l[0]))
    byid = {b["id"]: b for b in blocks}
    res = ["blocks-independent: esito=parallelo corsie=2"]
    for k, l in enumerate(lanes, 1):
        res.append("corsia %d: %s" % (k, ",".join(l)))
    for k, l in enumerate(lanes, 1):
        res.append("scope %d: %s" % (k, ",".join(f for i in l for f in byid[i]["files"])))
    return 0, res + out


def lista(path):
    """Righe non vuote del file; None se il file non si legge."""
    try:
        return [posix(x) for x in open(path, encoding="utf-8", errors="replace").read().splitlines() if x.strip()]
    except OSError:
        return None


def generati():
    """Percorsi dei file generati rigenerabili (`generati` di .claude/maat.json, letti con maat-config.py generati,
    harness-pt15 E). Progetto non configurato o lettura fallita => nessuno: vale la regola di sempre."""
    mc = os.path.join(os.path.dirname(os.path.abspath(__file__)), "maat-config.py")
    try:
        r = subprocess.run([sys.executable, mc, "generati"], capture_output=True, text=True, encoding="utf-8")
    except OSError:
        return set()
    if r.returncode != 0:
        return set()
    return {posix(ln.split(" | ")[0]) for ln in r.stdout.splitlines() if ln.strip()}


def posteriori(corsie, cambiati, dichiarati):
    illeggibili = [p for p in [corsie, cambiati] + list(dichiarati) if lista(p) is None]
    if illeggibili:
        return 1, "posteriori: esito=STOP — input illeggibili: %s" % ", ".join(illeggibili)
    scope = {}
    for ln in lista(corsie):
        m = re.match(r"^scope ([12]): (.*)$", ln)
        if m:
            scope[int(m.group(1))] = [posix(x) for x in m.group(2).split(",") if x.strip()]
    if set(scope) != {1, 2}:
        return 1, "posteriori: esito=STOP — scope delle corsie illeggibili in %s" % corsie
    dich = {k: set(lista(p)) for k, p in zip((1, 2), dichiarati)}
    per = {1: [], 2: []}
    gen = generati()
    for f in lista(cambiati):
        if CONDIVISI.search(f):
            return 1, "posteriori: esito=STOP — file condiviso o generato cambiato durante le corsie: %s" % f
        dentro = [k for k in (1, 2) if any(overlap(f, s) for s in scope[k])]
        if not dentro and f in gen:
            # Generato della configurazione, rigenerato col suo comando (E): appartiene alla corsia che lo dichiara
            # nel suo «file»; dichiarato da entrambe o da nessuna => non attribuibile, STOP come un file fuori unione.
            chi = [k for k in (1, 2) if f in dich.get(k, ())]
            if len(chi) != 1:
                return 1, "posteriori: esito=STOP — generato %s rigenerato senza una corsia sola che lo dichiari" % f
            per[chi[0]].append(f)
            continue
        if not dentro:
            return 1, "posteriori: esito=STOP — %s cambiato fuori dall'unione degli scrive: delle corsie" % f
        chi = set(dentro) | {k for k in (1, 2) if f in dich.get(k, ())}
        if len(chi) > 1:
            return 1, "posteriori: esito=STOP — %s scritto da entrambe le corsie" % f
        per[dentro[0]].append(f)
    return 0, "posteriori: esito=OK corsia 1: %s · corsia 2: %s" % (
        ",".join(per[1]) or "(nessuno)", ",".join(per[2]) or "(nessuno)")


def main(argv):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if argv[:1] == ["--posteriori"]:
        if len(argv) not in (3, 5):
            print("uso: blocks-independent.py --posteriori <corsie.txt> <cambiati.txt> [<dichiarati-1> <dichiarati-2>]", file=sys.stderr)
            return 2
        rc, line = posteriori(argv[1], argv[2], argv[3:5])
        print(line)
        return rc
    root = "."
    if argv[:1] == ["--root"] and len(argv) >= 2:
        root, argv = argv[1], argv[2:]
    if len(argv) != 1:
        print("uso: blocks-independent.py [--root <repo>] <procedura.txt>", file=sys.stderr)
        return 2
    try:
        rc, lines = decidi(root, argv[0])
    except SystemExit as e:
        print(e, file=sys.stderr)
        return 2
    print("\n".join(lines))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
