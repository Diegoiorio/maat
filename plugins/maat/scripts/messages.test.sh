#!/usr/bin/env bash
# messages.test.sh — the message catalog (Maat 1.4.0, block A): lib/maat-msg.sh (bash) and maat_msg.py (Python), the
# catalog lib/messages.tsv and the static anti-leak test over lib/protocol-strings.list. Every counterproof runs on a
# MUTATED copy of the plugin, never on the real one.
#
#   bash plugins/maat/scripts/messages.test.sh          (Git Bash or WSL)
#
# Sections: 1 language resolution, bash and Python equal on the same cases (MAAT_LINGUA > maat.json > en) · 2 a
# language that changes between two calls of the same process, maat.json cached per path · 3 substitution, the same
# bytes in bash and Python (hard values, missing value) · 4 catalog in CRLF: the same bytes · 5 fallback ‹key› (key or
# catalog missing): one warning per call, exit code unchanged · 6 msg -v · 7 catalog checks (format, unique keys,
# same placeholders, no Italian in the en column, keys used in the code present, no unused key) · 8 static anti-leak:
# no Italian literal outside the catalog and protocol-strings.list, except the TEMPORARY exemptions per file (below)
# · 9 counterproofs on a copy: Italian echo in a script, a placeholder taken from the en column, a list entry deleted,
# maat_lingua that ignores the environment — each red, then green again on the restored copy · 10 (1.5.0) the
# conversion tables: tools/lingua-converti.py copertura on all of them and check on each, with two counterproofs.
# Sections 7 (Italian detector) and 8-9 (scanner) need tools/lingua-inventario.py of the repo, section 10
# tools/lingua-converti.py and the tag v1.3.0: outside the repo (plugin installed in the cache) they are SKIPPED with
# the reason.
set -uo pipefail
export MAAT_LINGUA=it
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(cd "$HERE/.." && pwd)
SCANNER=$(cd "$PLUGIN/../.." && pwd)/tools/lingua-inventario.py
unset MAAT_CONFIG PROJECT_ROOT FIC_REPO MAAT_ROOT MAAT_MSG_PY
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
. "$HERE/python.sh" || { echo "interprete Python non trovato" >&2; exit 2; }
export PYTHONDONTWRITEBYTECODE=1
fail=0 n=0 skip=0
check() { n=$((n + 1)); if eval "$2"; then :; else fail=$((fail + 1)); echo "FAIL: $1"; [ -n "${3:-}" ] && printf '%s\n' "$3" | head -20 | sed 's/^/    /'; fi; }
nat() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
copia() { mkdir -p "$(dirname "$2")" && cp -r "$1" "$2" && find "$2" -name __pycache__ -type d -prune -exec rm -rf {} +; }
muta() { # $1 file, $2 exact line to replace, $3 new line → 0 if applied (a single occurrence)
  local f=$1; [ "$(grep -cxF -- "$2" "$f")" = 1 ] || return 1
  "$FIC_PY" -c 'import sys
p, a, b = sys.argv[1:4]
t = open(p, encoding="utf-8", newline="").read()
open(p, "w", encoding="utf-8", newline="").write(t.replace(a + "\n", b + "\n", 1))' "$f" "$2" "$3"
}

# TEMPORARY exemptions of the anti-leak test: the files not migrated yet, with the number of rows the scanner still
# finds there (residual). The number must be EXACT: a new Italian literal (or a list entry deleted) raises it, a
# migration lowers it, and both are red until the line here is updated. Each block removes its files; at the end of
# 1.4.0 the list is empty (exit criterion of the plan).
cat > "$T/esenzioni" <<'EOF'
EOF

# The Python side, as a program: <maat_msg.py> <command> … (stdout as UTF-8 bytes, no CRLF on Windows)
cat > "$T/drv.py" <<'EOF'
import importlib.util, os, sys
sys.dont_write_bytecode = True
s = importlib.util.spec_from_file_location("maat_msg", sys.argv[1]); m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
cmd, args = sys.argv[2], sys.argv[3:]
w = lambda x: sys.stdout.buffer.write(x.encode("utf-8"))
if cmd == "lingua":
    w(m.lingua() + "\n")
elif cmd == "T":
    w(m.T(args[0], **dict(a.split("=", 1) for a in args[1:])))
elif cmd == "valori":   # the values of the file (NUL-terminated) in every test entry, in it then en
    vals = open(args[0], "rb").read().decode("utf-8").split("\0")[:-1]
    for lang in ("it", "en"):
        os.environ["MAAT_LINGUA"] = lang
        for v in vals:
            w(m.T("test.value", v=v) + "\x1f" + m.T("test.order", a=v, b="<" + v + ">") + "\x1f" +
              m.T("test.braces", x=v) + "\x1f")
elif cmd == "tutte":    # every test entry, without values and with values, in it then en
    for lang in ("it", "en"):
        os.environ["MAAT_LINGUA"] = lang
        for k in ("test.plain", "test.value", "test.order", "test.braces", "test.accents"):
            w(m.T(k, v="1", a="2", b="3", x="4") + "\x1f")
elif cmd == "cambia":   # args: it.json en.json (native paths)
    seq = []
    os.environ["MAAT_LINGUA"] = "it"; seq.append(m.T("test.plain"))
    os.environ["MAAT_LINGUA"] = "en"; seq.append(m.T("test.plain"))
    del os.environ["MAAT_LINGUA"]
    os.environ["MAAT_CONFIG"] = args[0]; seq.append(m.T("test.plain"))
    os.environ["MAAT_CONFIG"] = args[1]; seq.append(m.T("test.plain"))
    with open(args[0], "w", encoding="utf-8") as f:   # same path, file changed: the cached value stays
        f.write(open(args[1], encoding="utf-8").read())
    os.environ["MAAT_CONFIG"] = args[0]; seq.append(m.T("test.plain"))
    w("|".join(seq))
EOF
# The bash side, the same commands: <lib dir> <command> …
cat > "$T/drv.sh" <<'EOF'
. "$1/maat-msg.sh"
maat_msg_carica
cmd=$2; shift 2
case $cmd in
  lingua) maat_lingua ;;
  T) msg "$@" ;;
  valori)
    mapfile -d '' -t V < "$1"
    for lang in it en; do
      export MAAT_LINGUA=$lang
      for v in ${V[@]+"${V[@]}"}; do
        msg test.value v="$v"; printf '\037'; msg test.order a="$v" b="<$v>"; printf '\037'
        msg test.braces x="$v"; printf '\037'
      done
    done ;;
  tutte)
    for lang in it en; do
      export MAAT_LINGUA=$lang
      for k in test.plain test.value test.order test.braces test.accents; do msg "$k" v=1 a=2 b=3 x=4; printf '\037'; done
    done ;;
  cambia)
    export MAAT_LINGUA=it; msg test.plain; printf '|'
    MAAT_LINGUA=en; msg test.plain; printf '|'
    unset MAAT_LINGUA
    export MAAT_CONFIG=$1; msg test.plain; printf '|'
    MAAT_CONFIG=$2; msg test.plain; printf '|'
    cp "$2" "$1"
    MAAT_CONFIG=$1; msg test.plain ;;
esac
EOF
pyd() { "$FIC_PY" "$T/drv.py" "$@"; }   # $1 = maat_msg.py
shd() { bash "$T/drv.sh" "$@"; }         # $1 = lib dir

CFG="$T/cfg"; mkdir -p "$CFG"
MIN='"versione_schema": 1, "moduli": [{"nome": "tutto", "radice": ".", "regola_test": "nessuna"}]'
printf '{%s, "lingua": "it"}\n' "$MIN" > "$CFG/it.json"
printf '{%s, "lingua": "en"}\n' "$MIN" > "$CFG/en.json"
printf '{%s}\n' "$MIN" > "$CFG/senza.json"
printf '{%s, "lingua": "fr"}\n' "$MIN" > "$CFG/fr.json"
printf '{"versione_schema": 1, \n' > "$CFG/rotto.json"
mkdir -p "$T/proj/.claude"; cp "$CFG/it.json" "$T/proj/.claude/maat.json"

# ---------------------------------------------------------------- 1. language resolution
# case: MAAT_LINGUA (- = unset) · MAAT_CONFIG (- = unset) · PROJECT_ROOT (- = unset) · expected
CASI='it|absent.json|-|it
en|it.json|-|en
xx|it.json|-|en
IT|it.json|-|en
|it.json|-|it
-|it.json|-|it
-|en.json|-|en
-|senza.json|-|en
-|rotto.json|-|en
-|fr.json|-|en
-|absent.json|-|en
-|-|proj|it'
risoluzione() { # $1 lib dir, $2 maat_msg.py → the mismatches, one per line (empty = all equal and as expected)
  local l c p e envs ob op
  while IFS='|' read -r l c p e; do
    envs=(env -u MAAT_LINGUA -u MAAT_CONFIG -u PROJECT_ROOT)
    [ "$l" = - ] || envs+=("MAAT_LINGUA=$l")
    [ "$c" = - ] || envs+=("MAAT_CONFIG=$(nat "$CFG/$c")")
    [ "$p" = - ] || envs+=("PROJECT_ROOT=$(nat "$T/$p")")
    ob=$(cd "$T" && "${envs[@]}" bash "$T/drv.sh" "$1" lingua 2>&1)
    op=$(cd "$T" && "${envs[@]}" "$FIC_PY" "$T/drv.py" "$2" lingua 2>&1 | tr -d '\r')
    [ "$ob" = "$e" ] && [ "$op" = "$e" ] || echo "MAAT_LINGUA=$l MAAT_CONFIG=$c PROJECT_ROOT=$p: atteso $e, bash $ob, python $op"
  done <<< "$CASI"
}
r=$(risoluzione "$HERE/lib" "$HERE/maat_msg.py")
check "risoluzione: bash e Python uguali e come attesi su $(printf '%s\n' "$CASI" | grep -c .) casi (env > maat.json > en, valore non valido = en)" '[ -z "$r" ]' "$r"
o=$(env -u MAAT_LINGUA MAAT_CONFIG="$(nat "$CFG/it.json")" bash -c '. "$1"; maat_lingua -v L; printf "%s" "$L"' _ "$HERE/lib/maat-msg.sh")
check "maat_lingua -v: assegna senza stampare" '[ "$o" = it ]' "$o"

# ---------------------------------------------------------------- 2. language changing inside one process
cp "$CFG/it.json" "$T/c1.json"; ob=$(shd "$HERE/lib" cambia "$(nat "$T/c1.json")" "$(nat "$CFG/en.json")" 2>&1)
cp "$CFG/it.json" "$T/c1.json"; op=$(pyd "$HERE/maat_msg.py" cambia "$(nat "$T/c1.json")" "$(nat "$CFG/en.json")" 2>&1)
atteso="Un messaggio semplice|A plain message|Un messaggio semplice|A plain message|Un messaggio semplice"
check "lingua che cambia fra due chiamate dello stesso processo (it, en, maat.json it, maat.json en), Python" '[ "$op" = "$atteso" ]' "$op"
check "  lo stesso in bash, nella stessa shell" '[ "$ob" = "$atteso" ]' "$ob"
check "  maat.json in cache per percorso: file cambiato, stesso percorso → valore di prima (ultimo campo)" '[ "${op##*|}" = "Un messaggio semplice" ] && [ "${ob##*|}" = "Un messaggio semplice" ]'

# ---------------------------------------------------------------- 3. substitution: the same bytes
"$FIC_PY" -c 'import sys
v = ["50% %s %d %% %n", "back\\slash \\n \\\\", "{", "}", "}}", "{{", "{v}", "{x}}", "&", "\\&", "&&", "a&b\\&c&&",
     "— · àèéìòù É", "cr\rmid\r", "riga\naltra\n", "", "\t tab $HOME `x` $(y)"]
open(sys.argv[1], "wb").write(b"".join(x.encode("utf-8") + b"\0" for x in v))' "$T/valori"
shd "$HERE/lib" valori "$T/valori" > "$T/v.sh" 2> "$T/v.sh.err"
pyd "$HERE/maat_msg.py" valori "$T/valori" > "$T/v.py" 2> "$T/v.py.err"
check "sostituzione: stessi byte in bash e Python (17 valori × 3 voci × 2 lingue: % \\ { }} & \\& && — · accenti CR a capo vuoto)" \
  'cmp -s "$T/v.sh" "$T/v.py" && [ -s "$T/v.sh" ] && [ ! -s "$T/v.sh.err" ] && [ ! -s "$T/v.py.err" ]' "$(cmp "$T/v.sh" "$T/v.py" 2>&1; cat "$T/v.sh.err" "$T/v.py.err")"
"$FIC_PY" -c 'import sys
v = open(sys.argv[1], "rb").read().decode("utf-8").split("\0")[:-1]
o = ""
for lang, (fv, fo, fb) in (("it", ("valore: <%s>", "prima %s, poi %s", "graffe {letterali} attorno a %s")),
                           ("en", ("value: <%s>", "%s first, then %s", "literal {braces} around %s"))):
    for x in v:
        o += fv % x + "\x1f" + (fo % ("<" + x + ">", x) if lang == "it" else fo % (x, "<" + x + ">")) + "\x1f" + fb % x + "\x1f"
open(sys.argv[2], "wb").write(o.encode("utf-8"))' "$T/valori" "$T/v.atteso"
check "  e sono i byte attesi (valori mai riletti, {{ }} letterali, ordine dei segnaposto per lingua)" 'cmp -s "$T/v.sh" "$T/v.atteso"' "$(cmp "$T/v.sh" "$T/v.atteso" 2>&1)"
for L in it en; do
  ob=$(MAAT_LINGUA=$L shd "$HERE/lib" T test.order a=x 2> "$T/m.sh.err"); rb=$?
  op=$(MAAT_LINGUA=$L pyd "$HERE/maat_msg.py" T test.order a=x 2> "$T/m.py.err"); rp=$?
  es=$(tr -d '\r' < "$T/m.sh.err"); ep=$(tr -d '\r' < "$T/m.py.err")
  check "segnaposto mancante ($L): stesso testo ({b} resta), stesso errore su stderr, nessuna uscita diversa da 0" \
    '[ "$ob" = "$op" ] && [ "$es" = "$ep" ] && [ "$es" = "maat-msg: test.order: no value for {b}" ] && [ $rb -eq 0 ] && [ $rp -eq 0 ] && case "$ob" in *"{b}"*) true ;; *) false ;; esac' "bash: $ob / $es · python: $op / $ep"
done
o=$(msg_out=$(bash -c '. "$1"; msg test.plain' _ "$HERE/lib/maat-msg.sh" | od -An -c | tr -d ' \n'); printf '%s' "$msg_out")
check "msg stampa senza a capo" '[ "$o" = "Unmessaggiosemplice" ]' "$o"

# ---------------------------------------------------------------- 4. catalog in CRLF
CP="$T/plugin/maat"; copia "$PLUGIN" "$CP"
shd "$HERE/lib" tutte > "$T/lf.sh"; pyd "$HERE/maat_msg.py" tutte > "$T/lf.py"
sed 's/$/\r/' "$HERE/lib/messages.tsv" > "$CP/scripts/lib/messages.tsv"
# and the lines both loaders skip: comment, blank, one TAB, three TABs (same key as a good entry), empty key
printf '# c\r\n\r\nbad.line\tone\r\ntest.plain\tX\tY\tZ\r\n\tno\tkey\r\n' >> "$CP/scripts/lib/messages.tsv"
shd "$CP/scripts/lib" tutte > "$T/crlf.sh" 2>&1; pyd "$CP/scripts/maat_msg.py" tutte > "$T/crlf.py" 2>&1
check "catalogo in CRLF, con righe da saltare: stessi byte che in LF, in bash e in Python" \
  '[ "$(tr -cd "\r" < "$CP/scripts/lib/messages.tsv" | wc -c)" -gt 5 ] && cmp -s "$T/lf.sh" "$T/lf.py" && cmp -s "$T/crlf.sh" "$T/lf.sh" && cmp -s "$T/crlf.py" "$T/lf.sh"' "$(cmp "$T/crlf.sh" "$T/lf.sh"; cmp "$T/crlf.py" "$T/lf.sh")"
cp "$HERE/lib/messages.tsv" "$CP/scripts/lib/messages.tsv"

# ---------------------------------------------------------------- 5. fallback ‹key›
ob=$(bash -c '. "$1"; msg nope.key; msg nope.altra; exit 7' _ "$HERE/lib/maat-msg.sh" 2> "$T/f.err"); rb=$?
check "chiave mancante (bash): ‹chiave› come testo, un avviso per chiamata, exit code del chiamante invariato" \
  '[ "$ob" = "‹nope.key›‹nope.altra›" ] && [ $rb -eq 7 ] && [ "$(grep -c . "$T/f.err")" = 2 ] && grep -q "message key not in the catalog: nope.key" "$T/f.err"' "rc=$rb $ob $(cat "$T/f.err")"
ob=$(bash -ec '. "$1"; msg nope.key; echo " dopo"' _ "$HERE/lib/maat-msg.sh" 2>/dev/null); rb=$?
check "  con set -e lo script prosegue" '[ "$ob" = "‹nope.key› dopo" ] && [ $rb -eq 0 ]' "rc=$rb $ob"
op=$(pyd "$HERE/maat_msg.py" T nope.key 2> "$T/f.err"); rp=$?
check "chiave mancante (Python): ‹chiave›, un avviso, nessuna eccezione" \
  '[ "$op" = "‹nope.key›" ] && [ $rp -eq 0 ] && [ "$(grep -c . "$T/f.err")" = 1 ] && grep -q "message key not in the catalog: nope.key" "$T/f.err"' "rc=$rp $op $(cat "$T/f.err")"
rm "$CP/scripts/lib/messages.tsv"
ob=$(bash -c '. "$1"; msg test.plain; msg test.value v=1; msg test.plain; exit 3' _ "$CP/scripts/lib/maat-msg.sh" 2> "$T/f.err"); rb=$?
check "catalogo assente (bash): ‹chiave›, un avviso per chiamata (3 chiamate, 3 righe), exit code invariato" \
  '[ "$ob" = "‹test.plain›‹test.value›‹test.plain›" ] && [ $rb -eq 3 ] && [ "$(grep -c "message catalog not found" "$T/f.err")" = 3 ] && [ "$(grep -c . "$T/f.err")" = 3 ]' "rc=$rb $ob $(cat "$T/f.err")"
op=$(pyd "$CP/scripts/maat_msg.py" T test.plain 2> "$T/f.err"); rp=$?
check "catalogo assente (Python): ‹chiave›, un avviso" \
  '[ "$op" = "‹test.plain›" ] && [ $rp -eq 0 ] && [ "$(grep -c . "$T/f.err")" = 1 ] && grep -q "message catalog not found" "$T/f.err"' "rc=$rp $op $(cat "$T/f.err")"
cp "$HERE/lib/messages.tsv" "$CP/scripts/lib/messages.tsv"

# ---------------------------------------------------------------- 6. msg -v
o=$(bash -c '. "$1"; maat_msg_carica
f() { local r; msg -v r test.value v="a b"; printf "[%s]" "$r"; }
out=$(msg -v X test.order a=1 b=2); printf "%s|%s|" "$out" "${X:-unset}"
msg -v X test.order a=1 b=2; printf "%s|" "$X"; f; printf "|"
msg -v Y nope.key 2>/dev/null; printf "%s|" "$Y"
msg -v 1x test.plain 2>/dev/null; printf "%s|" $?
msg test.value novalue 2>/dev/null; printf "%s" $?' _ "$HERE/lib/maat-msg.sh")
check "msg -v: assegna senza stampare, anche a una locale del chiamante; ‹chiave› se manca; 64 per un nome o un argomento non validi" \
  '[ "$o" = "|unset|prima 2, poi 1|[valore: <a b>]|‹nope.key›|64|64" ]' "$o"

# ---------------------------------------------------------------- 7-8. catalog checks and anti-leak
cat > "$T/chk.py" <<'EOF'
import importlib.util, json, os, re, subprocess, sys
sys.dont_write_bytecode = True
def load(name, path):
    s = importlib.util.spec_from_file_location(name, path); m = importlib.util.module_from_spec(s)
    s.loader.exec_module(m); return m
cmd = sys.argv[1]
if cmd == "catalogo":   # <maat_msg.py> <scripts dir> <scanner or "-">
    m = load("maat_msg", sys.argv[2]); scripts = sys.argv[3]
    italian = load("inv", sys.argv[4]).italian if sys.argv[4] != "-" else None
    voci, rotte = m.leggi_catalogo(m.CATALOGO)
    errs = ["riga %d: attesi chiave<TAB>en<TAB>it" % n for n in rotte]
    KEY = re.compile(r"^[a-z][a-z0-9-]*(\.[a-z0-9_-]+)+$")
    TOK = re.compile(r"\{\{|\}\}|\{[A-Za-z_][A-Za-z0-9_]*\}")
    # identifiers an English text keeps as they are (block B): file names and paths (chiusura.txt, *.rossi,
    # deviazioni-difensive.txt), options (--max-fasi), sub-commands (valida, righe, certificato), the plan keywords
    # (scrive:, dopo:, Figlie:) and the frozen line prefix «Base anello»; the detector looks at what is left. Block D:
    # the sub-command after «usage: » (leggi, comando of maat-config.py) and the maat.json values listed as <a|b|c>
    IDENT = re.compile(r"\S*[./_]\S*|--[\w-]+|\b(?:scrive|dopo|Figlie):|\bBase anello\b|\b(?:valida|righe|certificato|rossi)\b"
                       r"|\busage: \S+|\| leggi\b|<[^<>]*\|[^<>]*>")
    seen = {}
    for n, k, en, it in voci:
        if not KEY.match(k): errs.append("riga %d: chiave non valida: %r" % (n, k))
        if k in seen: errs.append("riga %d: chiave %s ripetuta (riga %d)" % (n, k, seen[k]))
        seen.setdefault(k, n)
        for lang, t in (("en", en), ("it", it)):
            if not t.strip(): errs.append("riga %d: %s: testo %s vuoto" % (n, k, lang))
            if re.search(r"[{}]", TOK.sub("", t)): errs.append("riga %d: %s: graffa sola nel testo %s" % (n, k, lang))
        pe, pi = sorted(set(m.sostituisci(en, {})[1])), sorted(set(m.sostituisci(it, {})[1]))
        if pe != pi: errs.append("riga %d: %s: segnaposto diversi, en %s · it %s" % (n, k, pe, pi))
        if italian and italian(IDENT.sub(" ", en)): errs.append("riga %d: %s: italiano nella colonna en: %s" % (n, k, en))
    # keys used by the code (msg in bash, T in Python), outside the tests and the two loaders
    MSGCALL = re.compile(r"(?:^|[\s;&|({`$])msg\s+(?:-v\s+\w+\s+)?[\"']?([a-z][a-z0-9-]*(?:\.[a-z0-9_-]+)+)")
    TCALL = re.compile(r"\bT\(\s*[\"']([a-z][a-z0-9-]*(?:\.[a-z0-9_-]+)+)[\"']")
    used, guill = {}, []
    for dp, dn, fn in os.walk(scripts):
        dn[:] = [d for d in dn if d != "__pycache__"]
        for f in fn:
            p = os.path.join(dp, f); rel = os.path.relpath(p, scripts).replace("\\", "/")
            if not f.endswith((".sh", ".py")) or f.endswith(".test.sh") or f == "test-review-surface.sh":
                continue
            src = open(p, encoding="utf-8", errors="replace").read()
            if rel in ("lib/maat-msg.sh", "maat_msg.py"):
                continue
            if re.search("‹|›|\\\\u2039|\\\\u203a", src): guill.append(rel)
            for ln in src.split("\n"):
                if ln.lstrip().startswith("#"): continue
                for k in MSGCALL.findall(ln) + TCALL.findall(ln): used.setdefault(k, rel)
    for k, rel in sorted(used.items()):
        if k not in seen: errs.append("%s usa la chiave %s, assente dal catalogo" % (rel, k))
    for k in sorted(seen):
        if k not in used and not k.startswith("test."): errs.append("chiave %s inutilizzata" % k)
    for rel in guill: errs.append("%s: ‹ › fuori da maat_msg.py e lib/maat-msg.sh" % rel)
    print("\n".join(errs)); sys.exit(1 if errs else 0)
if cmd == "antifuga":   # <scanner> <plugin root> <list> <exemptions>
    r = subprocess.run([sys.executable, sys.argv[2], "--root", sys.argv[3], "--list", sys.argv[4], "--json"],
                       capture_output=True)
    d = json.loads(r.stdout.decode("utf-8"))
    ex = {}
    for l in open(sys.argv[5], encoding="utf-8").read().split("\n"):
        if l.strip():
            f, c = l.split("\t"); ex[f] = int(c)
    errs = ["elenco: %s" % e for e in d["list_errors"]]
    errs += ["voce dell'elenco senza righe, riga %d: %s %s" % (e["n"], e["file"], e["regex"]) for e in d["unused_entries"]]
    for f, v in d["files"].items():
        got, want = v["residual"], ex.get(f, 0)
        if got == want: continue
        rows = ["    %d: %s" % (x["line"], x["text"][:150]) for x in d["residual"].get(f, [])][:5]
        if f not in ex:
            errs.append("%s: %d righe con italiano fuori dal catalogo e dall'elenco congelato" % (f, got))
            errs += rows
        else:
            errs.append("%s: residuo %d, l'esenzione dice %d (%s)" % (f, got, want, "nuovo italiano" if got > want
                        else "righe migrate: aggiorna l'esenzione"))
    errs += ["esenzione per un file che non c'e': %s" % f for f in ex if f not in d["files"]]
    print("\n".join(errs)); sys.exit(1 if errs else 0)
EOF
SC=-; [ -f "$SCANNER" ] && SC=$SCANNER
[ "$SC" = - ] && { skip=$((skip + 1)); echo "SALTATO: rilevatore dell'italiano (tools/lingua-inventario.py fuori dal plugin installato)"; }
catalogo() { "$FIC_PY" "$T/chk.py" catalogo "$1/maat_msg.py" "$1" "$SC" 2>&1 | tr -d '\r'; }
antifuga() { "$FIC_PY" "$T/chk.py" antifuga "$SCANNER" "$1" "$1/scripts/lib/protocol-strings.list" "$T/esenzioni" 2>&1 | tr -d '\r'; }
o=$(catalogo "$HERE")
check "catalogo: formato, chiavi uniche, testi non vuoti, stessi segnaposto in en e it, en senza italiano, chiavi del codice presenti, nessuna inutilizzata" '[ -z "$o" ]' "$o"
if [ "$SC" != - ]; then
  o=$(antifuga "$PLUGIN")
  check "anti-fuga: nessun letterale italiano fuori da catalogo ed elenco congelato (esenzioni temporanee: $(grep -c . "$T/esenzioni") file)" '[ -z "$o" ]' "$o"
else
  skip=$((skip + 1)); echo "SALTATO: anti-fuga e controprove 9 (tools/lingua-inventario.py fuori dal plugin installato)"
fi

# ---------------------------------------------------------------- 9. counterproofs on the copy
if [ "$SC" != - ]; then
  o=$(antifuga "$CP"); oc=$(catalogo "$CP/scripts"); orr=$(risoluzione "$CP/scripts/lib" "$CP/scripts/maat_msg.py")
  check "premessa: la copia del plugin e' verde (anti-fuga, catalogo, risoluzione)" '[ -z "$o" ] && [ -z "$oc" ] && [ -z "$orr" ]' "$o $oc $orr"
  cp "$CP/scripts/python.sh" "$T/bak"; printf 'echo "file non trovato"\n' >> "$CP/scripts/python.sh"
  o=$(antifuga "$CP")
  check "controprova: echo \"file non trovato\" in python.sh (non esentato) → anti-fuga rosso" 'printf "%s" "$o" | grep -q "scripts/python.sh: 1 righe con italiano"' "$o"
  cp "$T/bak" "$CP/scripts/python.sh"
  cp "$CP/scripts/maat-doctor.sh" "$T/bak"; printf 'echo "file non trovato"\n' >> "$CP/scripts/maat-doctor.sh"
  o=$(antifuga "$CP")
  check "controprova: lo stesso in maat-doctor.sh (migrato nel Blocco D, nessuna esenzione) → anti-fuga rosso" '[ ! -s "$T/esenzioni" ] && printf "%s" "$o" | grep -q "scripts/maat-doctor.sh: 1 righe con italiano"' "$o"
  cp "$T/bak" "$CP/scripts/maat-doctor.sh"
  cp "$CP/scripts/lib/messages.tsv" "$T/bak"
  muta "$CP/scripts/lib/messages.tsv" "test.value	value: <{v}>	valore: <{v}>" "test.value	value: <>	valore: <{v}>"; mr=$?
  o=$(catalogo "$CP/scripts")
  check "controprova: segnaposto tolto dalla colonna en → catalogo rosso" '[ $mr -eq 0 ] && printf "%s" "$o" | grep -q "test.value: segnaposto diversi"' "rc=$mr $o"
  cp "$T/bak" "$CP/scripts/lib/messages.tsv"
  L="$CP/scripts/lib/protocol-strings.list"; cp "$L" "$T/bak"
  grep -vF "python non trovato	7:" "$T/bak" > "$L"
  o=$(antifuga "$CP")
  check "controprova: voce dell'elenco congelato cancellata (gates.sh «python non trovato») → anti-fuga rosso" \
    '[ "$(grep -c . "$L")" -lt "$(grep -c . "$T/bak")" ] && printf "%s" "$o" | grep -q "scripts/gates.sh: 1 righe con italiano"' "$o"
  cp "$T/bak" "$L"
  cp "$CP/scripts/lib/maat-msg.sh" "$T/bak"
  muta "$CP/scripts/lib/maat-msg.sh" '  if [ -n "${MAAT_LINGUA:-}" ]; then' '  if false; then'; mr=$?
  o=$(risoluzione "$CP/scripts/lib" "$CP/scripts/maat_msg.py")
  check "controprova: maat_lingua che ignora MAAT_LINGUA → risoluzione rossa" '[ $mr -eq 0 ] && [ -n "$o" ]' "rc=$mr"
  cp "$T/bak" "$CP/scripts/lib/maat-msg.sh"
  o=$(antifuga "$CP"); oc=$(catalogo "$CP/scripts"); orr=$(risoluzione "$CP/scripts/lib" "$CP/scripts/maat_msg.py")
  check "copia ripristinata: di nuovo verde" '[ -z "$o" ] && [ -z "$oc" ] && [ -z "$orr" ]' "$o $oc $orr"
fi

# ---------------------------------------------------------------- 10. the conversion tables: copertura and check
# D9 of the 1.5.0 plan: tools/lingua-converti.py `copertura` on all the tables at once, and `check` on each one (it
# guards «MAAT_LINGUA=it = the output of v1.3.0»). Repo only, like the anti-leak test: SKIPPED with the reason outside
# the repo (plugin installed) or when the repo has no tag v1.3.0 (a shallow clone; the CI fetches the tags,
# fetch-depth: 0) — and on GitHub Actions a skip is a FAIL (exit criterion of the plan: not skipped in CI).
# Counterproofs on copies of the tables, the tool untouched: a #n moved to another literal of the same line (row
# maat-doctor.not_found_fix_project, maat-doctor.sh:850#4 → #3, the case of the 1.4.0 review) → copertura red; the
# en column of a row changed → check red.
CONV=$(cd "$PLUGIN/../.." && pwd)/tools/lingua-converti.py
TAB=$(dirname "$CONV")/lingua-conversioni
salta10=
if [ ! -f "$CONV" ] || [ ! -d "$TAB" ]; then salta10="tools/lingua-converti.py fuori dal plugin installato"
elif ! git -C "$(dirname "$CONV")/.." rev-parse -q --verify 'v1.3.0^{commit}' >/dev/null 2>&1; then
  salta10="il repo non ha il tag v1.3.0 (clone poco profondo?)"
fi
if [ -n "$salta10" ]; then
  skip=$((skip + 1)); echo "SALTATO: copertura e check delle tabelle di conversione ($salta10)"
  [ "${GITHUB_ACTIONS:-}" = true ] && check "sezione 10 non saltata in CI" false "$salta10"
else
  conv() { co=$("$FIC_PY" "$CONV" "$@" 2>&1); crc=$?; co=$(printf '%s\n' "$co" | tr -d '\r'); }
  conv copertura "$TAB"/*.tsv
  check "copertura su tutte le tabelle ($(ls "$TAB"/*.tsv | wc -l)) → exit 0, 0 errori" '[ $crc -eq 0 ] && printf "%s\n" "$co" | tail -1 | grep -q " 0 errors$"' "$co"
  for t in "$TAB"/*.tsv; do
    conv check "$t"
    check "check $(basename "$t") → exit 0" '[ $crc -eq 0 ] && printf "%s\n" "$co" | tail -1 | grep -q " 0 errors$"' "$co"
  done
  mkdir -p "$T/tab"; cp "$TAB"/*.tsv "$T/tab/"
  DOC=$T/tab/blocco-d.doctor.tsv
  sed 's/^\(maat-doctor\.not_found_fix_project	scripts\/maat-doctor\.sh:850\)#4!pytail	/\1#3!pytail	/' "$TAB/blocco-d.doctor.tsv" > "$DOC"
  conv copertura "$T/tab"/*.tsv
  check "controprova: #4 → #3 sulla riga maat-doctor.sh:850 (copia della tabella) → copertura rossa" \
    'grep -q "^maat-doctor.not_found_fix_project	scripts/maat-doctor.sh:850#3!pytail	" "$DOC" && [ $crc -eq 1 ] && printf "%s\n" "$co" | grep -q "maat-doctor.sh:850"' "rc=$crc $co"
  cp "$TAB/blocco-d.doctor.tsv" "$DOC"
  B1=$T/tab/blocco-b.tsv
  awk -F'\t' 'BEGIN { OFS = "\t" } !done && !/^#/ && NF == 6 { $6 = $6 " (mutata)"; done = 1 } { print }' "$TAB/blocco-b.tsv" > "$B1"
  conv check "$B1"
  check "controprova: la colonna en di una riga cambiata (copia di blocco-b.tsv) → check rosso" \
    'grep -q " (mutata)$" "$B1" && [ $crc -eq 1 ]' "rc=$crc $co"
  cp "$TAB/blocco-b.tsv" "$B1"; conv copertura "$T/tab"/*.tsv; c1=$crc; conv check "$B1"
  check "copie ripristinate: copertura e check di nuovo verdi" '[ $c1 -eq 0 ] && [ $crc -eq 0 ]' "$co"
fi

echo "messages.test.sh: $((n - fail))/$n PASS · $fail FAIL · $skip SALTATI"
[ $fail -eq 0 ]
