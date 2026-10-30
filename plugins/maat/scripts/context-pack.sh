#!/usr/bin/env bash
# context-pack.sh — pacchetto di contesto deterministico di uno spec (harness-pt07). SOLA LETTURA: scrive un
# solo file, <run-dir>/context-pack.md (via <run-dir>/context-pack.md.tmp, rinominato). Contenuto:
#   - file nominati dallo spec, verificati (esiste · trovato come · ambiguo · NON ESISTE) e simboli nominati
#     con la loro definizione;
#   - per ogni file: firme esportate (funzioni, props/emits dei .vue), rotte FastAPI (@router.*), modelli
#     Pydantic coinvolti, test che lo citano;
#   - test che citano le stringhe dello spec e i data-test;
#   - colonne DB delle tabelle nominate (`tabella` fra backtick = un blocco riconosciuto nel file dello schema),
#     da information_schema col comando dello schema; comando che fallisce => sezione «assente» con il motivo;
#   - intestazione con data, commit e impronta dello spec.
# Schema del DB da `contesto` di maat.json (MAAT_CONFIG, altrimenti <radice>/.claude/maat.json, letta importando
# maat-config.py): schema_db_file (il file da cui si riconoscono le tabelle, la sua estensione conta fra i file
# nominati), tabelle {blocco, nome_mappato?} (regex: il blocco con il nome nel gruppo 1 e il corpo nel gruppo 2;
# dentro il blocco il nome reale nel gruppo 1), schema_db_comando (riceve l'SQL come ultimo argomento, lanciato dalla
# radice del repository). Senza schema_db_file e schema_db_comando: «schema DB non dichiarato»; senza tabelle nessuna
# tabella si riconosce e la sezione lo dice. Uscita del comando: 124 => «timeout», altrimenti «comando dello schema
# uscito N: <prima riga non vuota della sua uscita>».
# È orientamento, non autorità: il codice vince sul pacchetto. Tetto ~5k token (troncato oltre).
# Se il pacchetto esiste con la stessa impronta dello spec non viene riscritto ("invariato"): l'orchestratore
# può lanciarlo prima di ogni fase di piano, costa solo quando lo spec è cambiato.
#
#   bash script/fic/context-pack.sh .claude/.ai-workflow/spec-<name>.md            # -> spec-<name>.run/
#   bash script/fic/context-pack.sh <spec> --run-dir <dir> [--force]
# Uscita: 0 scritto o invariato · 1 estrazione fallita · 2 uso (spec assente, opzione sconosciuta, Python).
# Variabili (per i test): CONTEXT_PACK_ROOT repository da leggere (default: PROJECT_ROOT, il progetto della
# cartella di lavoro) · CONTEXT_PACK_SQL
# script al posto di schema_db_comando (chiamato `bash <script> --read "<SQL>"`) · CONTEXT_PACK_SQL_TIMEOUT
# secondi (default 90) · CONTEXT_PACK_HARNESS radice del plugin (default MAAT_ROOT; scripts/python.sh e
# scripts/maat-config.py).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_ROOT (plugin) e PROJECT_ROOT (cartella di lavoro)
HROOT=${CONTEXT_PACK_HARNESS:-$MAAT_ROOT}
ROOT=${CONTEXT_PACK_ROOT:-$PROJECT_ROOT}
usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }

spec="" run_dir="" force=0
while [ $# -gt 0 ]; do
  case $1 in
    --run-dir) [ $# -ge 2 ] || usage; run_dir=$2; shift 2 ;;
    --force) force=1; shift ;;
    -h|--help) usage ;;
    -*) echo "context-pack: opzione sconosciuta: $1" >&2; exit 2 ;;
    *) [ -z "$spec" ] || usage; spec=$1; shift ;;
  esac
done
[ -n "$spec" ] || usage
[ -n "$ROOT" ] || { maat_progetto; exit 4; }
if [ ! -f "$spec" ]; then
  if [ -f "$ROOT/$spec" ]; then spec=$ROOT/$spec; else echo "context-pack: spec non trovato: $spec" >&2; exit 2; fi
fi
if [ -z "$run_dir" ]; then
  case $spec in *.md) run_dir=${spec%.md}.run ;; *) run_dir=$spec.run ;; esac
fi
. "$HROOT/scripts/python.sh" || { echo "context-pack: interprete Python non trovato" >&2; exit 2; }
win() { maat_cygm "$1" 2>/dev/null || printf '%s' "$1"; }
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8 PYTHONDONTWRITEBYTECODE=1
export MAAT_CONFIG_PY=${MAAT_CONFIG_PY:-$HROOT/scripts/maat-config.py}   # il Python legge `contesto` col lettore unico
args=("$(win "$ROOT")" "$(win "$spec")" "$(win "$run_dir")" "$force")
py() { sed '1,/^#__PYTHON__$/d' "$0" | "$FIC_PY" - "$@"; }   # il codice arriva da una pipe: nessun file temporaneo

plan=$(py plan "${args[@]}" | tr -d '\r') || { echo "context-pack: estrazione fallita" >&2; exit 1; }
fp=$(printf '%s\n' "$plan" | sed -n 's/^FP //p')
if printf '%s\n' "$plan" | grep -qx 'STATE unchanged'; then
  echo "context-pack: invariato ($fp) — $run_dir/context-pack.md"; exit 0
fi
tables=$(printf '%s\n' "$plan" | sed -n 's/^TABLE //p' | tr '\n' ' ')
dbcmd=$(printf '%s\n' "$plan" | sed -n 's/^DBCMD //p' | head -1)   # contesto.schema_db_comando
db_state=none db_out=""
if [ -n "${tables// /}" ]; then
  list=""; for t in $tables; do list="$list'$t',"; done   # nomi validati dal Python: [a-z_][a-z0-9_]*
  sql="SELECT '@@' || table_name || '|' || string_agg(column_name || ' ' || udt_name || CASE WHEN is_nullable = 'YES' THEN '?' ELSE '' END, ', ' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = 'public' AND table_name IN (${list%,}) GROUP BY table_name ORDER BY table_name;"
  to=(); command -v timeout >/dev/null 2>&1 && to=(timeout "${CONTEXT_PACK_SQL_TIMEOUT:-90}")
  if [ -n "${CONTEXT_PACK_SQL:-}" ]; then   # override (test): `bash <script> --read "<SQL>"`
    db_out=$("${to[@]}" bash "$CONTEXT_PACK_SQL" --read "$sql" 2>&1 </dev/null)
    db_state=rc=$?
  elif [ -n "$dbcmd" ]; then   # il comando dichiarato, dalla radice del repository, con l'SQL come ultimo argomento
    db_out=$(cd "$ROOT" && "${to[@]}" bash -c "$dbcmd"' "$1"' context-pack "$sql" 2>&1 </dev/null)
    db_state=rc=$?
  else
    db_state=nocmd
  fi
fi
CP_DB=$db_state CP_DB_OUT=$db_out CP_TABLES=$tables py write "${args[@]}"
exit $?

#__PYTHON__
import datetime, hashlib, os, posixpath, re, subprocess, sys

MODE, ROOT, SPEC, RUN_DIR, FORCE = sys.argv[1:6]
ROOT = ROOT.rstrip("/\\")
PACK = os.path.join(RUN_DIR, "context-pack.md")
CAP = 20000   # caratteri: ~5k token (stima caratteri/4)
SKIP = {"node_modules", ".git", ".venv", ".nuxt", ".output", "dist", "__pycache__", ".turbo", ".pytest_cache"}


def contesto():
    """`contesto` di maat.json (MAAT_CONFIG, altrimenti <ROOT>/.claude/maat.json), letta importando maat-config.py
    (MAAT_CONFIG_PY): {} se il progetto non e' configurato; configurazione non valida => uscita 1."""
    import importlib.util
    p = os.environ.get("MAAT_CONFIG_PY") or ""
    try:
        sp = importlib.util.spec_from_file_location("maat_config", p)
        mc = importlib.util.module_from_spec(sp)
        sp.loader.exec_module(mc)
    except Exception as e:
        sys.stderr.write("context-pack: lettore della configurazione non caricabile (%s): %s\n" % (p, e))
        sys.exit(1)
    try:
        cfg, _p = mc.carica(os.environ.get("MAAT_CONFIG") or os.path.join(ROOT, ".claude", "maat.json"))
    except mc.Uscita as u:
        if u.codice == 4:
            return {}
        sys.stderr.write("context-pack: maat.json: %s\n" % (u.messaggio or "configurazione non valida (uscita %d)" % u.codice))
        sys.exit(1)
    return cfg.get("contesto") or {}


CTX = contesto()
SCHEMA_FILE = (CTX.get("schema_db_file") or "").replace("\\", "/")
SCHEMA_CMD = CTX.get("schema_db_comando") or ""
TAB = CTX.get("tabelle") or {}
EXT = "vue|tsx|ts|mjs|cjs|js|py|sh|json|scss|css|sql|md|html|yml|yaml|toml|csv"
_SEXT = os.path.splitext(SCHEMA_FILE)[1][1:]
if _SEXT and _SEXT not in EXT.split("|"):   # l estensione del file dello schema conta fra i file nominati
    EXT += "|" + re.escape(_SEXT)
CODE = (".vue", ".ts", ".tsx", ".js", ".mjs", ".cjs", ".py")
MAX_FILES, MAX_SYMS, MAX_SIG, MAX_TESTS = 40, 30, 10, 4


def read(p, limit=1500000):
    p = p if os.path.isabs(p) else os.path.join(ROOT, p)
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read(limit)
    except OSError:
        return ""


with open(SPEC, "rb") as fh:
    SPEC_BYTES = fh.read()
FP = "sha256:" + hashlib.sha256(SPEC_BYTES).hexdigest()[:16]
TEXT = SPEC_BYTES.decode("utf-8", errors="replace")
TICKS = [t.strip() for t in re.findall(r"`([^`\n]{1,120})`", TEXT)]
PATH_RE = re.compile(r"(?<![\w/.@*<>$~-])((?:[\w.@~-]+/)*[\w@-][\w.@-]*\.(?:%s))(?![\w/-])" % EXT)


def schema_tables():
    """tabelle del file dello schema: ogni blocco di contesto.tabelle.blocco (nome nel gruppo 1, corpo nel gruppo 2),
    con il nome reale da nome_mappato dentro il corpo se c'e'. Senza file o senza blocco: nessuna."""
    if not SCHEMA_FILE or not TAB.get("blocco"):
        return set()
    s = read(SCHEMA_FILE)
    out = set()
    for m in re.finditer(TAB["blocco"], s, re.M | re.S):
        corpo = m.group(2) if m.re.groups >= 2 else m.group(0)
        mm = re.search(TAB["nome_mappato"], corpo) if TAB.get("nome_mappato") else None
        out.add(mm.group(1) if mm else m.group(1))
    return out


def named_tables():
    known, out = schema_tables(), []
    for t in TICKS:
        if "/" in t or PATH_RE.fullmatch(t):
            continue
        head = t.split(".")[0]
        if head in known and head not in out and re.fullmatch(r"[a-z_][a-z0-9_]*", head):
            out.append(head)
    return out[:12]


if MODE == "plan":
    same = ("Impronta spec: " + FP) in read(PACK, 4000)
    print("FP", FP)
    print("STATE", "unchanged" if same and FORCE != "1" else "changed")
    if SCHEMA_CMD:
        print("DBCMD", SCHEMA_CMD.replace("\n", " "))
    for t in named_tables():
        print("TABLE", t)
    sys.exit(0)

# ---------------------------------------------------------------- write
TABLES = os.environ.get("CP_TABLES", "").split()


def git(*a):
    if not os.path.exists(os.path.join(ROOT, ".git")):
        return None
    try:
        r = subprocess.run(["git", "-C", ROOT] + list(a), capture_output=True)
    except OSError:
        return None
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


def list_files():
    out = git("ls-files", "-co", "--exclude-standard", "-z")
    if out is not None:
        return [p for p in out.split("\0") if p and not (set(p.split("/")) & SKIP)]
    files = []
    for d, dirs, names in os.walk(ROOT):
        dirs[:] = sorted(x for x in dirs if x not in SKIP and not x.endswith(".run"))
        rel = os.path.relpath(d, ROOT).replace("\\", "/")
        files += [n if rel == "." else rel + "/" + n for n in sorted(names)]
    return files


FILES = list_files()
FILESET = set(FILES)
TEST_RE = re.compile(r"(^|/)(tests?|__tests__|e2e)/|\.(test|spec)\.[cm]?[jt]sx?$|(^|/)test_[^/]*\.py$|\.test\.sh$")
TESTS = [f for f in FILES if TEST_RE.search(f) and f.rsplit(".", 1)[-1] in ("ts", "tsx", "js", "mjs", "py", "sh")]
SOURCES = [f for f in FILES if f.endswith(CODE) and not TEST_RE.search(f)]
_cache = {}


def content(f):
    if f not in _cache:
        _cache[f] = read(f)
    return _cache[f]


def lineno(s, i):
    return s.count("\n", 0, i) + 1


try:
    SPEC_REL = os.path.relpath(SPEC, ROOT).replace("\\", "/")
except ValueError:
    SPEC_REL = SPEC
if SPEC_REL.startswith("../"):
    SPEC_REL = SPEC.replace("\\", "/")

# --- file nominati ---
def nome_progetto():
    """La cartella del tree principale (da un worktree collegato: quella che contiene git-common-dir), altrimenti
    quella di ROOT. I percorsi assoluti del progetto e dei suoi worktree (<nome>-…) si tolgono dal testo."""
    gcd = (git("rev-parse", "--path-format=absolute", "--git-common-dir") or "").strip().rstrip("/\\")
    return os.path.basename(os.path.dirname(gcd)) if gcd else os.path.basename(ROOT)


NOME = nome_progetto()
ABS = re.compile(r"(?:[A-Za-z]:|/mnt/[a-z])/[^\s`'\"()<>|]*?/" + re.escape(NOME) + r"[\w-]*/") if NOME else None
BRACE = re.compile(r"([\w./@~-]*)\{([\w.,/@~-]+)\}([\w./@~-]*)")


def expand(t):
    for _ in range(4):
        n = BRACE.sub(lambda m: " ".join(m.group(1) + x + m.group(3) for x in m.group(2).split(",")), t)
        if n == t:
            break
        t = n
    return t


def named_paths():
    t = TEXT.replace("\\", "/")
    t = expand(ABS.sub("", t) if ABS else t)
    out = []
    for m in PATH_RE.finditer(t):
        tok = re.split(r"[\s`(\"'<>«]", t[max(0, m.start() - 200):m.start()])[-1]
        if "//" in tok:
            continue   # URL
        q = re.sub(r"^(?:\./|~/|@/)+", "", m.group(1))
        q = posixpath.normpath(q)
        while q.startswith("../"):
            q = q[3:]
        if q in (SPEC_REL, posixpath.basename(SPEC_REL)) or q in out:
            continue
        out.append(q)
    return out


def resolve(q):
    exists = q in FILESET
    if exists:
        return "esiste", [q]
    c = sorted(f for f in FILES if f.endswith("/" + q))
    if 1 <= len(c) <= 3:
        return "trovato", c
    return ("ambiguo" if c else "assente"), c


# --- firme ---
def match_block(s, i):
    d = 0
    for j in range(i, len(s)):
        if s[j] in "{[(":
            d += 1
        elif s[j] in "}])":
            d -= 1
            if d == 0:
                return j
    return len(s)


def top_keys(body):
    flat, d = [], 0
    for c in body:
        if c in "{[(<":
            d += 1
        elif c in "}])>":
            d = max(0, d - 1)
        elif d == 0:
            flat.append(c)
    return re.findall(r"(?:^|[,;\n])\s*['\"]?([A-Za-z_$][\w$-]*)['\"]?\s*\??\s*:", "".join(flat))


def body_after(s, m):
    i = m.end() - 1
    return s[i + 1:match_block(s, i)]


def vue_props(s):
    m = re.search(r"defineProps\s*<\s*\{", s)
    if m:
        return top_keys(body_after(s, m))
    m = re.search(r"defineProps\s*<\s*(\w+)\s*>", s)
    if m:
        t = re.search(r"(?:interface\s+%s\b[^{]*|type\s+%s\s*=\s*)\{" % (m.group(1), m.group(1)), s)
        return top_keys(body_after(s, t)) if t else ["<%s>" % m.group(1)]
    m = re.search(r"defineProps\s*\(\s*\[([^\]]*)\]", s)
    if m:
        return re.findall(r"['\"]([^'\"]+)['\"]", m.group(1))
    m = re.search(r"defineProps\s*\(\s*\{", s) or re.search(r"^\s*props\s*:\s*\{", s, re.M)
    return top_keys(body_after(s, m)) if m else []


def vue_emits(s):
    m = re.search(r"defineEmits\s*\(\s*\[([^\]]*)\]", s) or re.search(r"^\s*emits\s*:\s*\[([^\]]*)\]", s, re.M)
    if m:
        return re.findall(r"['\"]([^'\"]+)['\"]", m.group(1))
    m = re.search(r"defineEmits\s*<\s*\{", s)
    if m:
        b = body_after(s, m)
        return re.findall(r"\(\s*\w+\s*:\s*['\"]([^'\"]+)['\"]", b) or top_keys(b)
    return []


def short(line, n=110):
    line = re.sub(r"\s+", " ", line.strip()).rstrip("{").rstrip()
    return line if len(line) <= n else line[:n - 1] + "…"


PYD = None


def pydantic_index():
    classes = {}
    for f in SOURCES:
        if not (f.endswith(".py") and "/api/" in "/" + f):
            continue
        s = content(f)
        for m in re.finditer(r"^class\s+(\w+)\s*\(([^)]*)\)\s*:", s, re.M):
            nxt = re.search(r"^\S", s[m.end():], re.M)
            body = s[m.end(): m.end() + nxt.start()] if nxt else s[m.end():]
            fields = re.findall(r"^    (\w+)\s*:", body, re.M)
            bases = set(re.findall(r"\w+", m.group(2)))
            classes.setdefault(m.group(1), (f, lineno(s, m.start()), bases, fields))
    pyd, grew = {"BaseModel"}, True
    while grew:
        grew = False
        for n, (_, _, b, _) in classes.items():
            if n not in pyd and b & pyd:
                pyd.add(n)
                grew = True
    return {n: classes[n] for n in pyd if n in classes}


def py_sigs(f, s):
    global PYD
    out = []
    pre = re.search(r"APIRouter\([^)]*prefix\s*=\s*['\"]([^'\"]*)", s)
    pre = pre.group(1) if pre else ""
    for m in re.finditer(r"^@router\.(get|post|put|patch|delete)\(\s*['\"]([^'\"]*)['\"](.*?)^(?:async\s+)?def\s+(\w+)",
                         s, re.M | re.S):
        rm = re.search(r"response_model\s*=\s*([\w\[\], ]+?)\s*[,)\n]", m.group(3))
        out.append("%s %s%s → %s%s (r. %d)" % (m.group(1).upper(), pre, m.group(2), m.group(4),
                   " · response_model " + rm.group(1) if rm else "", lineno(s, m.start())))
    if not out:
        for m in re.finditer(r"^(?:async\s+)?def\s+[A-Za-z]\w*\s*\([^\n]*|^class\s+\w+[^\n]*", s, re.M):
            out.append("%s (r. %d)" % (short(m.group(0)).rstrip(":"), lineno(s, m.start())))
    if PYD is None:
        PYD = pydantic_index()
    models = []
    for n in re.findall(r"\b([A-Z]\w+)\b", s):
        if n in PYD and n not in models and PYD[n][0] != f:
            models.append(n)
    extra = ["modello %s (%s:%d): %s" % (n, PYD[n][0], PYD[n][1], ", ".join(PYD[n][3][:8]) or "—") for n in models[:8]]
    return out, extra


def ts_sigs(s):
    return ["%s (r. %d)" % (short(m.group(0)), lineno(s, m.start())) for m in re.finditer(
        r"^export\s+(?:default\s+)?(?:async\s+)?(?:function\*?|const|let|class|interface|type|enum)\s+[\w$]+[^\n]*"
        r"|^export\s+default\b[^\n]*", s, re.M)]


def data_tests(s):
    return re.findall(r"\bdata-test(?:id)?=[\"']([\w-]+)[\"']", s)


def citing_tests(f):
    stem, ext = os.path.splitext(f)
    parts = stem.split("/")
    if ext == ".py":
        terms = [".".join(parts[parts.index("app"):])] if "app" in parts else [parts[-1]]
    elif ext in CODE and len(parts) >= 2:
        terms = ["/".join(parts[-2:])]
    else:
        terms = [posixpath.basename(f)]
    rxs = [re.compile(r"(?<![\w-])" + re.escape(t) + r"(?![\w-])") for t in terms]
    sib = re.compile(r"['\"]\./%s(?:\.\w+)?['\"]" % re.escape(parts[-1]))
    d = posixpath.dirname(f)
    return [t for t in TESTS if t != f and (any(r.search(content(t)) for r in rxs)
            or (posixpath.dirname(t) == d and sib.search(content(t))))]


def fmt_tests(ts):
    if not ts:
        return "nessuno"
    return ", ".join(ts[:MAX_TESTS]) + (" … +%d" % (len(ts) - MAX_TESTS) if len(ts) > MAX_TESTS else "")


# --- simboli ---
def named_symbols():
    out = []
    for tok in TICKS:
        s = re.sub(r"\(.*\)$", "", tok)
        called = s != tok
        if "/" in s or not re.fullmatch(r"[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?", s):
            continue
        last = s.split(".")[-1]
        if s.split(".")[0] in TABLES or len(last) < 4 or last in out:
            continue
        if "_" in last.strip("_") or re.search(r"[a-z][A-Z]", last) or re.match(r"[A-Z][a-z]+[A-Z]", last):
            out.append(last)
    return out[:MAX_SYMS]


def nuxt_name(f):
    # nome di auto-import Nuxt di components/**.vue: segmenti in PascalCase, prefisso ripetuto tolto
    segs = f[:-4].split("/components/", 1)[-1].split("/")
    name = ""
    for s in segs:
        p = "".join(w[:1].upper() + w[1:] for w in re.split(r"[-_]", s) if w)
        name = p if name and p.startswith(name) else name + p
    return name


def find_defs(sym, first):
    stems = [f for f in FILES if f.endswith(".vue") and (posixpath.basename(f)[:-4] == sym
             or ("/components/" in "/" + f and nuxt_name("/" + f) == sym))]
    if stems:
        return ["componente " + x for x in stems[:3]]
    e = re.escape(sym)
    rx = re.compile(r"^[ \t]*(?:export\s+)?(?:default\s+)?(?:async\s+)?(?:def|class|function\*?|interface|type|enum|const|let|var)"
                    r"\s+%s\b|^[ \t]*(?:async\s+)?%s\s*\([^)\n]*\)\s*(?::[^{\n=]*)?\{\s*$" % (e, e), re.M)
    for pool in (first, SOURCES):
        hits = []
        for f in pool:
            s = content(f)
            if sym in s:
                hits += ["%s:%d" % (f, lineno(s, m.start())) for m in rx.finditer(s)]
        if hits:
            return hits[:3] + (["… +%d" % (len(hits) - 3)] if len(hits) > 3 else [])
    return []


# --- assemblaggio ---
paths = named_paths()
L = []
sel, n_missing, n_listed = [], 0, 0
L.append("## File nominati dallo spec")
for q in paths:
    kind, c = resolve(q)
    if kind in ("esiste", "trovato") and all(x in sel for x in c):
        continue   # stesso file citato in un altro modo
    n_listed += 1
    if kind == "esiste":
        L.append("- esiste: " + q)
    elif kind == "trovato":
        L.append("- esiste: %s (citato come `%s`)" % (", ".join(c), q))
    elif kind == "ambiguo":
        L.append("- ambiguo: `%s` → %d file (%s)" % (q, len(c), fmt_tests(c)))
    else:
        L.append("- NON ESISTE: " + q)
        n_missing += 1
    if kind in ("esiste", "trovato"):
        sel += [x for x in c if x not in sel]
if not paths:
    L.append("- nessuno")
sel_code = [f for f in sel if f.endswith(CODE)]

db_state, db_out = os.environ.get("CP_DB", "none"), os.environ.get("CP_DB_OUT", "")
if not SCHEMA_FILE and not SCHEMA_CMD:   # sezione omessa: il progetto non dichiara uno schema
    db_summary = "schema DB non dichiarato"
    L += ["", "Colonne DB: schema DB non dichiarato (contesto.schema_db_file e schema_db_comando in maat.json)."]
elif db_state == "none" or not TABLES:
    L += ["", "## Colonne DB (information_schema, sola lettura)"]
    db_summary = "nessuna tabella"
    if not SCHEMA_FILE or not TAB.get("blocco"):
        L.append("- nessuna tabella riconoscibile: %s non dichiarato in maat.json" % (
            "contesto.schema_db_file" if not SCHEMA_FILE else "contesto.tabelle"))
    else:
        L.append("- nessuna tabella nominata (una `tabella` fra backtick che coincide con un blocco di %s)" % SCHEMA_FILE)
else:
    L += ["", "## Colonne DB (information_schema, sola lettura)"]
    rc = int(db_state.split("=", 1)[1]) if db_state.startswith("rc=") else None
    if rc == 0:
        rows = dict((k, v.strip()) for k, v in re.findall(r"@@(\w+)\|([^\n]*)", db_out))
        db_summary = "presente"
        L.append("(`?` = nullable)")
        for t in TABLES:
            L.append("- `%s`: %s" % (t, rows.get(t, "non trovata in information_schema")))
    else:
        if rc is None:   # tabelle nominate ma nessun comando per interrogarle
            why = "comando dello schema non dichiarato (contesto.schema_db_comando)"
        elif rc == 124:
            why = "timeout"
        else:   # il motivo lo spiega il comando stesso: la prima riga non vuota della sua uscita
            first = next((x.strip() for x in db_out.replace("\r", "").split("\n") if x.strip()), "")
            why = "comando dello schema uscito %d%s" % (rc, (": " + first[:200]) if first else "")
        db_summary = "assente (%s)" % why
        L.append("- **assente** — %s. Tabelle nominate: %s" % (why, ", ".join(TABLES)))

syms = named_symbols()
L += ["", "## Simboli nominati (definizione: prima nei file nominati, poi nel repository)"]
for s in syms:
    d = find_defs(s, sel_code)
    L.append("- `%s` → %s" % (s, ", ".join(d) if d else "non trovato"))
if not syms:
    L.append("- nessuno")

dt_vue = []
L += ["", "## Per file: firme e test che lo citano"]
for f in sel[:MAX_FILES]:
    s, ext = content(f), os.path.splitext(f)[1]
    L.append("### %s (%d righe)" % (f, s.count("\n") + (1 if s and not s.endswith("\n") else 0)))
    sig, extra = [], []
    if ext == ".vue":
        p, e = vue_props(s), vue_emits(s)
        sig.append("props: %s · emits: %s" % (", ".join(p) or "—", ", ".join(e) or "—"))
        for x in data_tests(s):
            if x not in dt_vue:
                dt_vue.append(x)
    elif ext in (".ts", ".tsx", ".js", ".mjs", ".cjs"):
        sig = ts_sigs(s)
    elif ext == ".py":
        sig, extra = py_sigs(f, s)
    for x in sig[:MAX_SIG]:
        L.append("- " + x)
    if len(sig) > MAX_SIG:
        L.append("- … +%d firme" % (len(sig) - MAX_SIG))
    L += ["- " + x for x in extra]
    if TEST_RE.search(f):
        L.append("- (è un test)")
    else:
        L.append("- test: " + fmt_tests(citing_tests(f)))
if len(sel) > MAX_FILES:
    L.append("- … altri %d file non espansi (tetto %d)" % (len(sel) - MAX_FILES, MAX_FILES))

L += ["", "## Test che citano i data-test"]
dt_spec = []
for x in re.findall(r"data-test(?:id)?\s*=\s*\\?[\"'`]?([\w-]+)", TEXT):
    if x not in dt_spec:
        dt_spec.append(x)
def dt_tests(x):
    rx = re.compile(r"(?:data-test(?:id)?=\\?[\"']?|[\"'`])%s(?![\w-])" % re.escape(x))
    return [t for t in TESTS if rx.search(content(t))]


for x in dt_spec[:25]:
    L.append("- `%s` (spec) → %s" % (x, fmt_tests(dt_tests(x))))
if len(dt_spec) > 25:
    L.append("- … altri %d data-test dello spec" % (len(dt_spec) - 25))
extra_dt = [x for x in dt_vue if x not in dt_spec]
if extra_dt:   # quelli dei .vue nominati: solo il conto e i non citati (i citati sono la norma)
    orphans = [x for x in extra_dt if not dt_tests(x)]
    L.append("- nei .vue nominati altri %d data-test, %d citati da test; non citati: %s" % (
        len(extra_dt), len(extra_dt) - len(orphans),
        ", ".join("`%s`" % x for x in orphans[:15]) + (" … +%d" % (len(orphans) - 15) if len(orphans) > 15 else "")
        if orphans else "nessuno"))
if not dt_spec and not extra_dt:
    L.append("- nessun data-test nello spec né nei .vue nominati")

L += ["", "## Test che citano le stringhe dello spec («…» e \"…\")"]
strs = []
for a, b in re.findall(r"«([^»\n]{5,60})»|\"([^\"\n]{5,60})\"", TEXT):
    x = (a or b).strip()
    # un identificatore o un percorso è già coperto da simboli, file e data-test
    if len(x) >= 5 and x not in strs and not re.fullmatch(r"[\w$.-]+", x):
        strs.append(x)
strs = strs[:80]
cited = [(x, [t for t in TESTS if x in content(t)]) for x in strs]
generic = [x for x, t in cited if len(t) > 12]
cited = [(x, t) for x, t in cited if t and len(t) <= 12]
for x, t in cited[:20]:
    L.append("- «%s» → %s" % (x, fmt_tests(t)))
L.append("- stringhe cercate: %d · citate da test: %d%s · generiche (in più di 12 test, non elencate): %d" % (
    len(strs), len(cited), " (mostrate 20)" if len(cited) > 20 else "", len(generic)))

rev = (git("rev-parse", "--short", "HEAD") or "n/d").strip()
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
head = ["# Pacchetto di contesto — %s" % SPEC_REL, "",
        "> Orientamento, non autorità: il codice vince sul pacchetto. Generato da `scripts/context-pack.sh` del plugin maat",
        "> (sola lettura); si rigenera quando cambia l'impronta dello spec.", "",
        "Data: %s · Commit: %s · Impronta spec: %s" % (now, rev, FP), ""]
head = "\n".join(head) + "\n"
body = "\n".join(L) + "\n"
room = CAP - len(head) - 100   # il tetto vale per il file intero, intestazione e stima comprese
if len(body) > room:
    body = body[:body.rfind("\n", 0, room) + 1] + "\n… TRONCATO al tetto di ~5k token: il resto va letto dal codice.\n"
doc = head + body
tok = (len(doc) + 3) // 4
doc = doc.replace("Impronta spec: %s\n" % FP, "Impronta spec: %s · Stima: ~%d token\n" % (FP, tok), 1)
os.makedirs(RUN_DIR, exist_ok=True)
with open(PACK + ".tmp", "w", encoding="utf-8", newline="\n") as fh:
    fh.write(doc)
os.replace(PACK + ".tmp", PACK)
print("context-pack: %s — file nominati %d (%d inesistenti), ~%d token, DB: %s" % (
    PACK.replace("\\", "/"), n_listed, n_missing, tok, db_summary))
