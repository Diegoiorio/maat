#!/usr/bin/env bash
# counterproof.sh — le controprove di una review, eseguite SOLO nella copia locale (mirror), mai nel working tree.
#
# Uso:
#   PROJECT_ROOT=<repo> bash <plugin>/scripts/counterproof.sh <run-dir>/counterproof/mutations.json
# Lo lancia run_cp di run-phase.sh: dentro WSL (percorsi /mnt/…, PROJECT_ROOT e MAAT_CONFIG tradotti) solo su Windows
# e con un modulo `ambiente: wsl` fra quelli delle mutazioni; altrimenti diretto.
# Radice del progetto: PROJECT_ROOT, altrimenti FIC_REPO, altrimenti il toplevel git della cartella di lavoro
# (lib/maat-paths.sh, maat_progetto); mai dalla posizione dello script, che sta nel plugin. Non risolta -> exit 64.
# Moduli, runner e comandi: maat.json del progetto (MAAT_CONFIG vince), letto IMPORTANDO maat-config.py (lo stesso
# lettore dei comandi `modulo-di` e `comando`). I risultati vanno nella cartella di mutations.json: un <id>.json
# per ogni mutazione.
#
# FORMATO DI INPUT — mutations.json e' una LISTA di oggetti:
#   {
#     "id":        "CP-3",                                   lettere, cifre, . _ -  (nome del file risultato)
#     "file":      "web/src/utils/goals.ts",                 relativo al repository
#     "simbolo":   "companyAssignStatus",                    dove sta la mutazione (per chi legge)
#     "mutazione": {"cerca": "gap.cents * 20 > goalCents", "sostituisci": "gap.cents * 20 >= goalCents"},
#     "test":      {"percorso": "web/src/tests/goals-utils.test.ts", "nome": "companyAssignStatus soglia"},
#     "rosso_se":  {"test_id": "<nome completo del test nel runner>", "asserzione": "<testo nel messaggio di errore>"},
#     "superficie": "…"                                     facoltativo, riportato tale e quale
#     "assorbita": true, "motivo": "…"                      facoltativi (L2, harness-pt11): la scrive
#                                                           `plan-check.sh gen` dopo la fase test-red
#   }
# - "assorbita": true (L2: file NUOVO, rosso alla base con stub dimostrato, verde dopo) -> la mutazione NON si
#   esegue: <id>.json con esito "assorbita" (controprova ASSORBITA, motivo), niente runner. Non entra nei conteggi
#   (prove=<n>/<tot> conta le sole eseguite); l'ultima riga aggiunge "assorbite=<n>". Solo assorbite -> exit 0 senza
#   mirror ne' lock. Le condizioni di L2 le ricontrolla finalize.sh (plan-check.sh l2), non questo script.
# - "cerca" deve comparire ESATTAMENTE una volta nel file (sostituzione esatta, byte per byte; se il file ha
#   fine riga CRLF e "cerca" contiene \n, si riprova con \r\n). Zero o piu' occorrenze -> bloccata.
# - Il MODULO lo decide maat.json (instradamento di `modulo-di`): file e test nello STESSO modulo, con il test sotto
#   la `radice` del modulo; altrimenti exit 64 (il runner di un modulo non vede la mutazione di un altro: sarebbe
#   un falso «verde»).
# - Il RUNNER e' `controprova.runner` del modulo; la riga di comando e' `controprova.comando`, con i segnaposto
#   {test}, {nome}, {report}, {python}, eseguita nella `radice` del modulo dentro la copia:
#   - vitest, pytest: adattatori del nucleo (tempi, gruppo di processi, lock, classificazione dal report). {test}
#     e' il file di test relativo alla radice (pytest: <file>::<nome>), {nome} il nome del test (vitest: gia'
#     protetto per la regex di -t, da "test.nome", default rosso_se.test_id), {report} il report che il nucleo legge;
#   - comando: rosso = uscita diversa da 0 -> rosso_generico, uscita 0 -> verde. Nessun report: la prova e' DEBOLE
#     (non dice su quale asserzione e' rosso), e la review la conta come tale.
# - Modulo senza `controprova` (o senza `controprova.comando`) -> la mutazione non si esegue: <id>.json con esito
#   "non_eseguita" e controprova "NOT RUN" (dichiarato), mai «verde» ne' «rosso». Non entra nei conteggi; l'ultima
#   riga aggiunge "non_eseguite=<n>". Solo non eseguite (e assorbite) -> "esito=NOT RUN", exit 0, senza mirror.
# - S5, duplicati esatti: stesso file, simbolo, cerca, sostituisci, test e rosso_se => eseguita UNA volta,
#   il risultato vale per tutti gli ID (campo "duplicato_di"). Mutazioni in punti diversi non sono duplicati.
#
# ESITI (campo "esito" di <id>.json) e controprova:
#   rosso_asserzione  il test nominato e' rosso E il messaggio contiene rosso_se.asserzione  -> PASS (prova)
#   rosso_generico    (runner comando) il comando esce diverso da 0                          -> PASS (prova debole)
#   rosso_import      il file di test non si carica / errore d'import: MAI una prova         -> FAIL
#   rosso_raccolta    file o test nominato non raccolto, saltato, o errore di raccolta       -> FAIL
#   rosso_diverso     il test nominato e' rosso ma non sull'asserzione attesa               -> FAIL
#   verde             la mutazione non e' coperta                                            -> FAIL
#   bloccato          mutazione non applicabile, runner assente, nessun report, tetto di tempo -> BLOCKED
#   assorbita         (L2) non eseguita: la coppia rosso-con-stub / verde-dopo vale da controprova -> ASSORBITA
#   non_eseguita      modulo senza controprova dichiarata                                    -> NOT RUN
# Gli adattatori vitest e pytest leggono il report del runner, mai il solo codice d'uscita (JSON di vitest, JUnit
# di pytest: la riga che lo chiede sta in `controprova.comando`, nei profili).
#
# GARANZIE
# - Il working tree NON viene mai scritto: la mutazione si applica alla copia nel mirror, lo stesso di test-fast.sh
#   e con la stessa regola (fic-mirror.sh): <mirror> = $HOME/fic-mirror dal tree principale, $HOME/fic-mirror-<hash>
#   da un worktree (anche creato da Git per Windows). Ogni modulo delle mutazioni sta in <mirror>/<radice_pacchetti>.
#   Il modulo con `copia` (al piu' uno fra quelli delle mutazioni, altrimenti exit 64 «più moduli con copia») e'
#   quello di test-fast.sh: la sua copia di un worktree senza node_modules si semina come li' (hardlink dalla copia
#   del tree principale, solo con le stesse dipendenze). Un modulo senza `copia` si sincronizza e si verifica col
#   manifest, senza semina ne' impronta.
# - Lock: lo stesso file di test-fast.sh, <mirror>/<radice_pacchetti del modulo con copia>/.fic-lock (senza un
#   modulo con copia fra le mutazioni: quello del primo modulo con copia di maat.json, altrimenti del primo modulo
#   delle mutazioni), preso con `flock -w "${FIC_LOCK_WAIT:-900}"`: si ATTENDE, e oltre il tetto -> exit 3. MAI un
#   ripiego su /mnt/c: li' il test girerebbe sull'albero non mutato e darebbe un falso «non rosso».
# - Senza rsync o senza flock (pk08, per esempio Git Bash su Windows senza WSL; CAMBIA IL CONTRATTO di pk04b-2, che dava
#   BLOCKED): le controprove girano lo stesso, con i ripieghi di fic-mirror.sh, piu' lenti e dichiarati in una riga
#   «counterproof: … di ripiego …». Copia: fic_sync (find + impronte sha256 + tar, stesse esclusioni, --delete e
#   confronto del contenuto di rsync; la verifica del manifest qui sotto resta). Lock: mkdir atomico di
#   <lock>.d (fic_lock_dir, stesso tetto FIC_LOCK_WAIT), anche per la coda dei worker del gradino 2; rilasciato dal
#   trap EXIT. La copia di un modulo con `copia` (preparazione, semina, riallineamento) resta di test-fast.sh, che
#   vuole rsync e flock: senza, «mirror assente» o il riallineamento non riuscito, col motivo.
# - Sotto il lock: impronta delle dipendenze del modulo con copia (quella di `test-fast.sh --setup`), poi per ogni
#   modulo sync con cancellazione (esclusioni: l'elenco unico del nucleo FIC_MIRROR_EXCL di fic-mirror.sh piu' le
#   cartelle di `collega_nel_worktree` del modulo), pulizia della copia (fic_mirror_pulisci: le cartelle dei
#   `preparati` e, col runner vitest, le cache di vite/vitest), le cartelle di sola lettura di `copia_anche`
#   (rsync -a --delete --checksum --exclude=node_modules, fuori dal manifest), poi manifest (path + sha256 dei file
#   tracciati e non tracciati non ignorati, piu' i .env*: lo stesso di test-fast.sh, node_modules escluso)
#   confrontato fra origine e mirror. Dipendenze stantie -> la copia si riallinea da sola sotto il lock come in
#   test-fast.sh (fic_deps_autorefresh), riga "counterproof: dipendenze cambiate (impronta <vecchia> -> <nuova>):
#   copia riallineata dall'origine", poi l'impronta di nuovo. Mirror assente, dipendenze stantie non riallineabili,
#   sync fallito o copia non allineata -> exit 3.
# - Per ogni mutazione: copia di sicurezza del SOLO file, sostituzione (unlink + write), run del solo test
#   nominato, ripristino (unlink + copia), poi hash del modulo nel mirror riconfrontato con il manifest iniziale. Se
#   non torna -> exit 5 e ci si ferma (un mirror sporco falserebbe le mutazioni successive). Se lo script muore
#   a meta', il trap EXIT ripristina il file in volo.
# - {python}: $FIC_PYTEST_PY se impostata (override); altrimenti, per un modulo `ambiente: wsl`, la ricerca di
#   gates.sh (moduli[].python, stringa o lista, relativa alla radice; poi piattaforma.python; poi python3: il primo
#   che esiste, qui dentro WSL) e nessuno -> exit 3 «python WSL assente»; per un modulo nativo la precedenza del
#   lettore (risolvi_python) e nessun interprete -> exit 3 «python assente». pytest gira con `-B -p no:cacheprovider`
#   (nel comando del profilo): nessun .pyc che sopravviva alla mutazione.
#
# GRADINO 1 e GRADINO 2
# - Gradino 1, seriale nel mirror sotto il lock: i moduli senza copia, i file del modulo con copia fuori dalla sua
#   radice (i link del workspace in node_modules puntano ai pacchetti DEL MIRROR, una copia privata non li
#   vedrebbe), ogni runner diverso da vitest, e tutto quando N < 2.
# - Gradino 2, parallelo: le mutazioni vitest su file sotto la radice del modulo con copia girano su N copie private
#   del SOLO sorgente ($HOME/fic-cp.XXXXXX/<i>/<radice_pacchetti>, fuori dal mirror), fatte dal mirror verificato. Il
#   lock del mirror resta preso per TUTTO il gradino (snapshot, run, verifica finale dei sorgenti del mirror): le
#   copie leggono ancora node_modules e packages/ del mirror, che un altro scrittore non deve cambiare sotto i run.
#   node_modules radice = symlink a quello del mirror (sola lettura); node_modules annidati copiati senza
#   cache. Per copia: FIC_VITE_CACHE_DIR (cacheDir privata) e FIC_VITE_FS_ALLOW (radice della copia +
#   node_modules e packages del mirror: vite 5 non carica file fuori da server.fs.allow), nell'ambiente del run e
#   lette da vitest.config.ts SOLO se impostate. Niente `cp -al`. Le copie si cancellano alla fine.
#
# SEGNALI
# - TERM, INT (Ctrl-C), HUP: il trap scatta subito (i run girano in background e si attendono con `wait`) e,
#   in ordine, uccide con KILL tutti i discendenti — worker, `timeout`, il comando del runner e i suoi figli — e i
#   process group aperti da `timeout` (registrati per pid: sopravvivono ai worker se un Ctrl-C uccide prima questi),
#   ripristina il file in volo nel mirror, cancella le copie private $HOME/fic-cp.*; altri segnali durante la pulizia
#   si ignorano, perche' non la interrompano a meta'. Esce 143;
#   i <id>.json gia' scritti restano, quelli non ancora scritti mancano: il run non e' completo.
# - KILL (o la morte di WSL) non e' intercettabile: possono restare un file mutato nel mirror (lo riallinea il
#   sync con --checksum del run successivo, di test-fast.sh o di questo script: il working tree non e'
#   toccato), copie $HOME/fic-cp.* (da cancellare a mano) e processi orfani (`pkill -f fic-cp`). Il lock si libera
#   da se' quando muore l'ultimo processo che ne tiene aperto il descrittore: i run lo chiudono. Il lock di ripiego
#   (senza flock) resta come cartella <lock>.d col pid morto: chi attende la riconosce orfana e la riprende.
# - N = min(FIC_CP_PARALLEL [4], MemAvailable / FIC_CP_MEM_MB [1500, misurato], nproc/2, mutazioni del
#   gradino 2). FIC_CP_PARALLEL=1 forza il seriale.
#
# Output: una riga per mutazione, ultima riga
#   "counterproof: esito=<PASS|FAIL|BLOCKED|NOT RUN> prove=<n>/<tot> fail=<n> bloccate=<n> tempo=<s>s luogo=<mirror|copie(N)>".
# Exit: 0 tutte prove valide (o nessuna da eseguire) · 1 almeno una FAIL · 2 almeno una bloccata (nessuna FAIL) ·
#       3 BLOCKED d'ambiente (strumenti assenti senza ripiego — sha256sum, timeout, un Python da python.sh, rsync e tar
#         insieme: «controprove non disponibili: manca <strumento>» —, interprete di {python} assente, lock oltre il
#         tetto, mirror assente,
#         dipendenze stantie non riallineabili, sync fallito, copia non allineata, copia privata non creabile; oppure
#         mirror cambiato durante il gradino 2): i risultati di questo run non valgono, anche se qualche <id>.json e'
#         stato scritto ·
#       5 mirror o copia privata non ripristinati (integrita': ci si ferma) ·
#       64 uso errato: argomenti, radice del progetto non risolta (PROJECT_ROOT), maat.json non leggibile,
#          mutations.json non valido.
set -u

usage() { echo "uso: PROJECT_ROOT=<repo> counterproof.sh <mutations.json>" >&2; exit 64; }
[ $# -eq 1 ] || usage
case "$1" in -*) usage ;; esac

HERE=$(cd "$(dirname "$0")" && pwd)
# Radice del progetto: PROJECT_ROOT dell'ambiente vince (run_cp la passa, anche dentro WSL); senza, il risolutore
# unico (FIC_REPO, poi git dalla cartella di lavoro). Mai $HERE/../..: nel plugin sarebbe la cartella dei plugin.
_PR=${PROJECT_ROOT:-}
. "$HERE/lib/maat-paths.sh" || { echo "counterproof: lib/maat-paths.sh non caricabile (plugin incompleto: $HERE)" >&2; exit 64; }
[ -n "$_PR" ] && PROJECT_ROOT=$_PR
maat_progetto || { echo "counterproof: radice del progetto non risolta: imposta PROJECT_ROOT" >&2; exit 64; }
ROOT=$(cd "$PROJECT_ROOT" 2>/dev/null && pwd) || { echo "counterproof: radice del progetto non accessibile: $PROJECT_ROOT" >&2; exit 64; }
export PROJECT_ROOT=$ROOT MAAT_CONFIG_PY="$HERE/maat-config.py"

# Strumenti (pk08): rsync e flock hanno un ripiego (fic_sync con tar, fic_lock_dir con mkdir: fic-mirror.sh), piu'
# lento e dichiarato; senza ripiego -> BLOCKED: sha256sum, timeout, un Python da python.sh, e tar quando manca rsync.
. "$HERE/python.sh" 2>/dev/null || FIC_PY=""
manca=""
for t in sha256sum timeout; do command -v "$t" >/dev/null 2>&1 || manca+="${manca:+, }$t"; done
command -v rsync >/dev/null 2>&1 || command -v tar >/dev/null 2>&1 || manca+="${manca:+, }rsync e tar"
[ -n "${FIC_PY:-}" ] || manca+="${manca:+, }python"
if [ -n "$manca" ]; then echo "counterproof: esito=BLOCKED (controprove non disponibili: manca $manca) luogo=-"; exit 3; fi
FLOCK=1; command -v flock >/dev/null 2>&1 || FLOCK=""
RIPIEGO=""
command -v rsync >/dev/null 2>&1 || RIPIEGO="rsync assente: copia di ripiego (find, impronte sha256, tar)"
[ -n "$FLOCK" ] || RIPIEGO+="${RIPIEGO:+; }flock assente: lock di ripiego (mkdir atomico)"

# Destinazione con la STESSA regola di test-fast.sh (fic-mirror.sh): ~/fic-mirror dal tree principale,
# ~/fic-mirror-<hash> da un worktree. Da un worktree non si sincronizza mai il suo codice nella copia del tree
# principale. Radice non determinabile -> BLOCKED (piu' sotto).
. "$HERE/fic-mirror.sh" || { echo "counterproof: fic-mirror.sh non trovato accanto a counterproof.sh" >&2; exit 64; }
if fic_mirror_init "$ROOT"; then MIR=$FIC_MIRROR; else MIR=""; fi
WAIT=${FIC_LOCK_WAIT:-900}
RUN_TIMEOUT=${FIC_CP_TIMEOUT:-1800}

MJ=$1
[ -f "$MJ" ] || { [ -f "$ROOT/$MJ" ] && MJ="$ROOT/$MJ"; }
[ -f "$MJ" ] || { echo "counterproof: mutations.json non trovato: $1" >&2; exit 64; }
OUT=$(cd "$(dirname "$MJ")" && pwd)

# Logica su JSON e report, in Python (niente jq in WSL). Nessun apice singolo qui dentro.
PY='
import importlib.util, json, os, posixpath, re, shutil, sys
import xml.etree.ElementTree as ET

def die(msg):
    print("counterproof: " + msg, file=sys.stderr)
    sys.exit(64)

SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
IMPORT_JS = re.compile(r"Failed to load url|Failed to resolve import|Cannot find module|Cannot find package|does not provide an export named|is not exported by|Failed to parse source|Transform failed|SyntaxError|ERR_MODULE_NOT_FOUND")
IMPORT_PY = re.compile(r"ImportError|ModuleNotFoundError|SyntaxError|IndentationError|cannot import name")

def lettore():
    # maat-config.py importato (MAAT_CONFIG_PY): le stesse funzioni dei comandi modulo-di e comando
    p = os.environ.get("MAAT_CONFIG_PY") or ""
    try:
        import sys; sys.dont_write_bytecode = True   # nessun __pycache__ sotto MAAT_ROOT
        spec = importlib.util.spec_from_file_location("maat_config", p)
        mc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mc)
    except Exception as e:
        die("lettore della configurazione non caricabile (%s): %s" % (p, e))
    return mc

def rel_ok(p):
    if not isinstance(p, str) or not p or p.startswith("/") or "\\" in p or re.match(r"^[A-Za-z]:", p):
        return False
    return ".." not in p.split("/")

def norm(s):
    return " ".join(ANSI.sub("", s or "").split())

def wtxt(path, s):
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(s)

def rtxt(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()

def wjson_out(out, rec):
    dst = os.path.join(out, rec["id"] + ".json")
    with open(dst + ".tmp", "w", encoding="utf-8") as fh:
        json.dump(rec, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(dst + ".tmp", dst)

def dove(d):
    return "fuori da ogni modulo" if d is None else "%s (%s)" % d

def cerca_python_wsl(mc, cfg, m, root):
    # la ricerca di gates.sh: candidati del modulo (radice) o piattaforma.python (repo) o python3; il primo che esiste
    v, base = m.get("python"), mc.norm(m["radice"])
    if not v:
        v, base = cfg.get("piattaforma", {}).get("python") or "python3", ""
    provati = []
    for c in (v if isinstance(v, list) else [v]):
        c = c.replace("\\", "/")
        if "/" not in c:
            provati.append(c)
            if shutil.which(c):
                return c, provati
            continue
        if re.match(r"^[A-Za-z]:/", c):
            p = "/mnt/%s/%s" % (c[0].lower(), c[3:])
        elif c.startswith("/"):
            p = c
        else:
            p = posixpath.join(root, base, mc.norm(c)) if base else posixpath.join(root, mc.norm(c))
        provati.append(p)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p, provati
    return None, provati

def interprete(mc, cfg, m, root):
    o = os.environ.get("FIC_PYTEST_PY")
    if o:
        return o, ""
    if m.get("ambiente") == "wsl":
        p, provati = cerca_python_wsl(mc, cfg, m, root)
        return (p, "") if p else (None, "python WSL assente: " + " ".join(provati))
    p = mc.risolvi_python(cfg, m, root)
    if p and ("/" not in p or (os.path.isfile(p) and os.access(p, os.X_OK))):
        return p, ""
    return None, "python assente: " + (p or "nessun candidato")

def pattern(s):
    # -t confronta il fullName, dove vitest unisce antenati e titolo con uno spazio: un nome scritto come vitest
    # lo stampa nei FAIL ("describe > it") va riportato a quella forma, o nessun test combacia (tutti skipped)
    return re.sub(r"([\\^$.*+?()\[\]{}|/])", r"\\\1", s.replace(" > ", " "))

def prep(mj, root, tmp, out):
    mc = lettore()
    try:
        cfg, _p = mc.carica()
        r = mc.risolto(cfg)
    except mc.Uscita as u:
        die("maat.json: " + (u.messaggio or "configurazione non valida (uscita %d)" % u.codice))
    mods = {x["nome"]: x for x in r["moduli"]}
    try:
        with open(mj, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as e:
        die("mutations.json illeggibile: %s" % e)
    if not isinstance(data, list) or not data:
        die("mutations.json deve essere una lista non vuota")
    seen, groups, order, absorbed, notrun = set(), {}, [], [], []
    for i, m in enumerate(data):
        where = "voce %d" % i
        if not isinstance(m, dict):
            die(where + ": non e un oggetto")
        mid = m.get("id")
        if not isinstance(mid, str) or not SAFE_ID.match(mid):
            die(where + ": id mancante o non valido (lettere, cifre, . _ -)")
        where = "id " + mid
        if mid in seen:
            die(where + ": id duplicato")
        seen.add(mid)
        f, sym, mut, t, rs = m.get("file"), m.get("simbolo"), m.get("mutazione"), m.get("test"), m.get("rosso_se")
        if not rel_ok(f):
            die(where + ": file deve essere un path relativo al repository, senza ..")
        if not isinstance(sym, str) or not sym.strip():
            die(where + ": simbolo mancante")
        if not isinstance(mut, dict) or not isinstance(mut.get("cerca"), str) or not mut["cerca"] or not isinstance(mut.get("sostituisci"), str):
            die(where + ": mutazione deve essere {cerca, sostituisci} con cerca non vuoto")
        if mut["cerca"] == mut["sostituisci"]:
            die(where + ": mutazione vuota (cerca uguale a sostituisci)")
        if not isinstance(t, dict) or not rel_ok(t.get("percorso")):
            die(where + ": test.percorso mancante o non relativo al repository")
        nome = t.get("nome") or ""
        if not isinstance(nome, str):
            die(where + ": test.nome deve essere un testo")
        if not isinstance(rs, dict) or not all(isinstance(rs.get(k), str) and rs[k].strip() for k in ("test_id", "asserzione")):
            die(where + ": rosso_se deve avere test_id e asserzione non vuoti")
        tp = t["percorso"]
        df, dt = mc.instrada(r, f), mc.instrada(r, tp)
        if df is None or dt is None or df[0] != dt[0] or dt[1] != "radice":
            die(where + ": file e test nello stesso modulo di maat.json, con il test sotto la radice del modulo (file: %s; test: %s)" % (dove(df), dove(dt)))
        mod = mods[df[0]]
        for p in (f, tp):
            if not os.path.isfile(os.path.join(root, p)):
                die(where + ": file assente nel working tree: " + p)
        ab = m.get("assorbita", False)
        if not isinstance(ab, bool) or not isinstance(m.get("motivo", ""), str):
            die(where + ": assorbita deve essere true/false e motivo un testo")
        if ab:  # L2 (harness-pt11): non si esegue, il risultato si scrive sotto
            absorbed.append(m)
            continue
        cp = mod.get("controprova") or {}
        if not cp.get("comando"):   # NOT RUN (dichiarato): mai verde ne rosso
            why = ("il modulo %s non dichiara controprova" % mod["nome"]) if not cp else ("controprova.comando non dichiarato per il modulo %s" % mod["nome"])
            notrun.append((m, cp.get("runner"), why))
            continue
        key = json.dumps([f, sym, mut["cerca"], mut["sostituisci"], tp, nome, rs["test_id"], rs["asserzione"]])
        if key not in groups:
            groups[key] = {"entries": [], "runner": cp["runner"], "modulo": mod["nome"]}
            order.append(key)
        groups[key]["entries"].append(m)
    for mid in seen:
        try:
            os.unlink(os.path.join(out, mid + ".json"))
        except FileNotFoundError:
            pass
    vuoto = {"luogo": None, "comando": None, "rc_runner": None, "durata_s": 0.0, "duplicato_di": None,
             "messaggio": "", "output_coda": []}
    for m in absorbed:  # SALTO-ASSORBITE
        rec = dict(m)
        rec.update(vuoto)
        rec.update({"esito": "assorbita", "controprova": "ASSORBITA", "motivo": m.get("motivo") or "L2",
                    "runner": None, "eseguita_per": [m["id"]]})
        wjson_out(out, rec)
    for m, runner, why in notrun:  # NOT-RUN-DICHIARATO
        rec = dict(m)
        rec.update(vuoto)
        rec.update({"esito": "non_eseguita", "controprova": "NOT RUN", "motivo": "NOT RUN (dichiarato): " + why,
                    "runner": runner, "eseguita_per": [m["id"]]})
        wjson_out(out, rec)
    usati = [x for x in r["moduli"] if any(groups[k]["modulo"] == x["nome"] for k in order)]
    con_copia = [x["nome"] for x in usati if x.get("copia")]
    if len(con_copia) > 1:
        die("più moduli con copia nelle mutazioni (%s): una lista per ognuno" % ", ".join(con_copia))
    pys = {}
    for x in usati:
        nm = x["nome"]
        if not SAFE_ID.match(nm):
            die("nome di modulo non utilizzabile come cartella: %s" % nm)
        rad, pac = mc.norm(x["radice"]), mc.norm(x["radice_pacchetti"])
        if not pac:
            die("radice_pacchetti del modulo %s e la radice del repository: la copia vuole una cartella" % nm)
        try:
            gruppo = mc.relativa(rad, pac)
        except mc.Uscita as u:
            die(u.messaggio)
        d = os.path.join(tmp, "mod", nm)
        os.makedirs(d)
        cp = x["controprova"]
        wtxt(os.path.join(d, "radice"), rad)
        wtxt(os.path.join(d, "pacchetti"), pac)
        wtxt(os.path.join(d, "gruppo"), gruppo)
        wtxt(os.path.join(d, "copia"), "1" if x.get("copia") else "")
        wtxt(os.path.join(d, "runner"), cp["runner"])
        # esclusioni in piu del modulo: le cartelle di collega_nel_worktree (dipendenze installate), relative alla
        # radice dei pacchetti, ancorate
        esc = []
        for v in x.get("collega_nel_worktree", []):
            v = {"percorso": v} if isinstance(v, str) else v
            b = mc.cartella_di(x, v.get("cartella", "radice"))
            p = mc.norm(posixpath.join(b, v["percorso"]) if b else v["percorso"])
            if p != pac and mc.sotto(p, pac):
                esc.append("/" + p[len(pac) + 1:])
        wtxt(os.path.join(d, "escludi"), "".join(e + "\n" for e in esc))
        wtxt(os.path.join(d, "preparati"), "".join(g + "\n" for g in x.get("preparati", [])))
        anche = [mc.norm(a) for a in x.get("copia_anche", []) if rel_ok(mc.norm(a))]
        wtxt(os.path.join(d, "anche"), "".join(a + "\n" for a in anche))
        miss = ""
        if "{python}" in cp["comando"]:
            pys[nm], miss = interprete(mc, cfg, x, root)
        wtxt(os.path.join(d, "pymiss"), miss)
    for n, key in enumerate(order):
        g = groups[key]
        m = g["entries"][0]
        x = mods[g["modulo"]]
        rad = mc.norm(x["radice"])
        radp = rad + "/" if rad else ""
        d = os.path.join(tmp, "m", "%04d" % n)
        os.makedirs(d)
        with open(os.path.join(d, "entries.json"), "w", encoding="utf-8") as fh:
            json.dump(g["entries"], fh, ensure_ascii=False)
        tp = m["test"]["percorso"]
        trel = tp[len(radp):]
        nome = m["test"].get("nome") or m["rosso_se"]["test_id"]
        runner = g["runner"]
        if runner == "vitest":
            val = {"test": [trel], "nome": pattern(nome)}
        elif runner == "pytest":  # nome relativo al file: via "<radice>/" e "<percorso>::"
            nome = nome[len(radp):] if radp and nome.startswith(radp) else nome
            nome = nome[len(trel) + 2:] if nome.startswith(trel + "::") else nome
            val = {"test": [trel + "::" + nome] if nome else [trel], "nome": nome}
        else:
            val = {"test": [trel], "nome": nome}
        val["python"] = pys.get(g["modulo"])
        val["maat"] = (os.environ.get("MAAT_ROOT") or mc.PLUGIN).replace("\\", "/")
        wtxt(os.path.join(d, "runner"), runner)
        wtxt(os.path.join(d, "modulo"), g["modulo"])
        wtxt(os.path.join(d, "file"), m["file"])
        wtxt(os.path.join(d, "cerca"), m["mutazione"]["cerca"])
        wtxt(os.path.join(d, "sost"), m["mutazione"]["sostituisci"])
        wtxt(os.path.join(d, "tpath"), tp)
        wtxt(os.path.join(d, "trel"), trel)
        wtxt(os.path.join(d, "radp"), radp)
        wtxt(os.path.join(d, "tname"), nome)
        wtxt(os.path.join(d, "python"), val["python"] or "")
        wtxt(os.path.join(d, "tpl"), x["controprova"]["comando"])
        with open(os.path.join(d, "valori.json"), "w", encoding="utf-8") as fh:
            json.dump(val, fh, ensure_ascii=False)
    # lock: quello del modulo con copia delle mutazioni (lo stesso di test-fast.sh); senza, del primo modulo con
    # copia di maat.json (la copia condivisa con test-fast.sh), altrimenti del primo modulo delle mutazioni
    lock = ""
    if con_copia:
        lock = mc.norm(mods[con_copia[0]]["radice_pacchetti"])
    elif usati:
        primo = next((x for x in r["moduli"] if x.get("copia") and mc.norm(x["radice_pacchetti"])), None)
        lock = mc.norm((primo or usati[0])["radice_pacchetti"])
    wtxt(os.path.join(tmp, "mods"), "".join(x["nome"] + "\n" for x in usati))
    wtxt(os.path.join(tmp, "copiamod"), con_copia[0] if con_copia else "")
    wtxt(os.path.join(tmp, "lockpkg"), lock)
    print(len(order), len(data) - len(absorbed) - len(notrun), len(absorbed), len(notrun))

def riga(d, report):
    # la riga del runner: controprova.comando espanso con i valori del prep e il report di questo run
    mc = lettore()
    with open(os.path.join(d, "valori.json"), encoding="utf-8") as fh:
        val = json.load(fh)
    val["report"] = report
    try:
        print(mc.espandi(rtxt(os.path.join(d, "tpl")), val))
    except mc.NonRisolto as e:
        print("comando della controprova non espandibile: %s" % e, file=sys.stderr)
        sys.exit(3)

def apply(path, cf, sf):
    with open(cf, "rb") as fh:
        cerca = fh.read()
    with open(sf, "rb") as fh:
        sost = fh.read()
    with open(path, "rb") as fh:
        data = fh.read()
    n = data.count(cerca)
    if n == 0 and b"\r\n" in data and b"\n" in cerca:
        c2 = cerca.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        n = data.count(c2)
        if n:
            cerca, sost = c2, sost.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
    if n != 1:
        print("mutazione non applicabile: il testo da cercare compare %d volte nel file (ne serve esattamente 1)" % n)
        sys.exit(2)
    new = data.replace(cerca, sost, 1)
    os.unlink(path)
    with open(path, "wb") as fh:
        fh.write(new)

def vitest_ids(a):
    # nomi con cui un test si puo citare: fullName (antenati + titolo, uniti da spazio), il titolo, e ogni
    # suffisso della catena degli antenati, uniti da spazio o da " > " come nei FAIL; confronto esatto, mai
    # per sottostringa
    anc, title = a.get("ancestorTitles") or [], a.get("title") or ""
    ids = {a.get("fullName"), title}
    for k in range(len(anc)):
        for sep in (" ", " > "):
            ids.add(sep.join(anc[k:] + [title]))
    return ids

def classify_vitest(report, trel, tid, asserz):
    try:
        with open(report, encoding="utf-8") as fh:
            rep = json.load(fh)
    except Exception:
        return "bloccato", "il runner non ha prodotto un report JSON leggibile", ""
    files = [r for r in rep.get("testResults", []) if (r.get("name") or "").replace("\\", "/").endswith("/" + trel)]
    if not files:
        return "rosso_raccolta", "file di test non raccolto dal runner", ""
    fr = files[0]
    targets = [a for a in fr.get("assertionResults", []) if tid in vitest_ids(a)]
    failed = [a for a in targets if a.get("status") == "failed"]
    if failed:
        msg = norm("\n".join(x for a in failed for x in (a.get("failureMessages") or [])))
        return red(msg, asserz, IMPORT_JS)
    fmsg = norm(fr.get("message") or "")
    if fr.get("status") == "failed" and fmsg:
        return suite_red(fmsg, IMPORT_JS)
    if targets and all(a.get("status") == "passed" for a in targets):
        return "verde", "il test nominato resta verde: la mutazione non e coperta", ""
    return "rosso_raccolta", "test nominato non eseguito (assente o saltato): nessuna prova", ""

def red(msg, asserz, imp):
    if norm(asserz) in msg:
        return "rosso_asserzione", "rosso sul test nominato e sull asserzione attesa", msg
    if imp.search(msg):
        return "rosso_import", "rosso per un errore d import, non per l asserzione: non e una prova", msg
    return "rosso_diverso", "il test nominato e rosso, ma non sull asserzione attesa", msg

def suite_red(msg, imp):
    if imp.search(msg):  # CLASSIFICAZIONE-IMPORT
        return "rosso_import", "il file di test non si carica (errore d import): non e una prova", msg
    return "rosso_raccolta", "il file di test fallisce in raccolta: nessun test eseguito", msg

def classify_pytest(report, trel, tid, asserz, rc, radp):
    if rc in (4, 5):
        return "rosso_raccolta", "pytest non ha raccolto il test nominato (uscita %d)" % rc, ""
    try:
        root = ET.parse(report).getroot()
    except Exception:
        return "bloccato", "il runner non ha prodotto un report JUnit leggibile", ""
    tid = tid[len(radp):] if radp and tid.startswith(radp) else tid
    mod = trel[:-3].replace("/", ".") if trel.endswith(".py") else trel.replace("/", ".")
    targets, coll = [], []
    for c in root.iter("testcase"):
        cn, nm = c.get("classname") or "", c.get("name") or ""
        bad = [e for e in list(c) if e.tag in ("failure", "error")]
        if not cn:
            coll += bad
            continue
        if cn == mod:
            rest = ""
        elif cn.startswith(mod + "."):
            rest = "::" + cn[len(mod) + 1:].replace(".", "::")
        else:
            continue
        nodeid = trel + rest + "::" + nm
        if nodeid == tid or nodeid.endswith("::" + tid):
            skipped = any(e.tag == "skipped" for e in list(c))
            targets.append((bad, skipped))
    failed = [b for b, s in targets if b]
    if failed:
        msg = norm("\n".join((e.get("message") or "") + "\n" + (e.text or "") for b in failed for e in b))
        return red(msg, asserz, IMPORT_PY)
    if coll:
        return suite_red(norm("\n".join((e.get("message") or "") + "\n" + (e.text or "") for e in coll)), IMPORT_PY)
    if targets and not any(s for b, s in targets):
        return "verde", "il test nominato resta verde: la mutazione non e coperta", ""
    return "rosso_raccolta", "test nominato non eseguito (assente o saltato): nessuna prova", ""

def classify_comando(rc):
    # runner comando: nessun report, conta solo l uscita (prova debole)
    if rc != 0:
        return "rosso_generico", "il comando della controprova esce %d: rosso senza report, prova debole (nessuna asserzione verificata)" % rc, ""
    return "verde", "il comando della controprova esce 0: la mutazione non e coperta", ""

def result(d, out, report, rc, ms, log, cmd, why):
    rc, ms = int(rc), int(ms)
    with open(os.path.join(d, "entries.json"), encoding="utf-8") as fh:
        entries = json.load(fh)
    runner, trel, radp = rtxt(os.path.join(d, "runner")), rtxt(os.path.join(d, "trel")), rtxt(os.path.join(d, "radp"))
    m0 = entries[0]
    tid, asserz = m0["rosso_se"]["test_id"], m0["rosso_se"]["asserzione"]
    if why:
        esito, motivo, msg = "bloccato", why, ""
    elif rc == 124 or rc == 137:
        esito, motivo, msg = "bloccato", "runner oltre il tetto di tempo (FIC_CP_TIMEOUT)", ""
    elif runner == "vitest":
        esito, motivo, msg = classify_vitest(report, trel, tid, asserz)
    elif runner == "pytest":
        esito, motivo, msg = classify_pytest(report, trel, tid, asserz, rc, radp)
    else:
        esito, motivo, msg = classify_comando(rc)
    cp = {"rosso_asserzione": "PASS", "rosso_generico": "PASS", "bloccato": "BLOCKED"}.get(esito, "FAIL")
    try:
        with open(log, encoding="utf-8", errors="replace") as fh:
            tail = [ANSI.sub("", x.rstrip("\n")) for x in fh.readlines()[-60:]]
    except OSError:
        tail = []
    ids = [e["id"] for e in entries]
    for e in entries:
        rec = dict(e)
        rec.update({
            "esito": esito, "controprova": cp, "motivo": motivo, "runner": runner, "luogo": "mirror",
            "comando": cmd, "rc_runner": rc if not why else None, "durata_s": round(ms / 1000.0, 1),
            "duplicato_di": None if e["id"] == ids[0] else ids[0], "eseguita_per": ids,
            "messaggio": msg[:4000], "output_coda": tail,
        })
        wjson_out(out, rec)
    print(cp, esito, len(ids), ",".join(ids), "--", motivo)

cmd = sys.argv[1]
if cmd == "prep":
    prep(*sys.argv[2:6])
elif cmd == "riga":
    riga(*sys.argv[2:4])
elif cmd == "apply":
    apply(*sys.argv[2:5])
elif cmd == "result":
    result(*sys.argv[2:10])
'

TMPD=$(mktemp -d)
CPD=""; LOCKD=""   # LOCKD: il lock di ripiego (mkdir) preso da questo processo, da rilasciare in cleanup
: > "$TMPD/inflight"
# Su segnale (TERM, INT, HUP -> uscita normale -> trap EXIT), in quest'ordine: si uccidono TUTTI i discendenti
# (worker, `timeout`, il comando del runner: `timeout` apre un proprio process group, quindi uccidere i soli job
# non basta), si ripristina il file in volo nel mirror, si cancellano le copie private. SIGKILL non e' gestibile:
# vedi la testata.
descendants() {  # <pid>: tutti i discendenti, in profondita'
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do echo "$c"; descendants "$c"; done
}
kill_tree() {  # piu' passate: un worker fra una raccolta e l'altra puo' aver lanciato il run successivo
  local k pids
  for k in 1 2 3 4 5; do
    pids=$(descendants $$)
    [ -n "$pids" ] || return 0
    kill -KILL $pids 2>/dev/null
    sleep 0.2
  done
}
kill_runs() {  # i gruppi aperti da `timeout`: sopravvivono ai worker se questi muoiono per primi (Ctrl-C)
  local p
  [ -f "$TMPD/runpgids" ] || return 0
  while read -r p; do [ -n "$p" ] && kill -KILL -- "-$p" "$p" 2>/dev/null; done < "$TMPD/runpgids"
}
cleanup() {
  # Un secondo segnale durante la pulizia la interromperebbe a meta' (copie e processi lasciati li'): da qui
  # in poi i segnali si ignorano.
  trap '' TERM INT HUP
  kill_tree; kill_runs; kill_tree; wait 2>/dev/null
  if [ -s "$TMPD/inflight" ] && [ -f "$TMPD/bak" ]; then q=$(cat "$TMPD/inflight"); rm -f "$q"; cp -p "$TMPD/bak" "$q"; fi
  [ -n "$CPD" ] && rm -rf "$CPD"
  rm -rf "$TMPD"
  [ -z "$LOCKD" ] || fic_unlock_dir "$LOCKD" "$$"   # ultimo: il mirror e' gia' ripristinato
}
trap 'exit 143' TERM INT HUP
trap cleanup EXIT

info=$("$FIC_PY" -c "$PY" prep "$MJ" "$ROOT" "$TMPD" "$OUT") || exit 64
read -r NU NT NA NN <<< "${info//$'\r'/}"
echo "counterproof: $NT mutazioni, $NU da eseguire (duplicati esatti una volta sola), luogo=mirror"
ABS=""; [ "${NA:-0}" -gt 0 ] && { ABS=" assorbite=$NA"; echo "counterproof: $NA assorbite (L2): saltate, <id>.json con esito=assorbita"; }
if [ "${NN:-0}" -gt 0 ]; then
  ABS+=" non_eseguite=$NN"
  echo "counterproof: $NN NOT RUN (dichiarato): moduli senza controprova, <id>.json con esito=non_eseguita"
fi
if [ "$NU" -eq 0 ]; then   # niente da eseguire (assorbite o NOT RUN): nessun lock, nessun mirror
  E=PASS; [ "${NN:-0}" -gt 0 ] && E="NOT RUN"
  echo "counterproof: esito=$E prove=0/0 fail=0 bloccate=0 tempo=0s luogo=-$ABS"; exit 0
fi

blocked() { echo "counterproof: esito=BLOCKED ($1) luogo=-"; exit 3; }
[ -n "$MIR" ] || blocked "radice del repository non determinabile (git): nessuna copia associabile"

# I moduli delle mutazioni (ordine di maat.json), dal prep: cartelle, copia, runner, esclusioni, preparati, copia_anche
modv() { cat "$TMPD/mod/$1/$2" 2>/dev/null; }
mapfile -t MODS < "$TMPD/mods"
declare -A M_RAD M_PAC M_GRP M_RUN
for m in "${MODS[@]}"; do
  M_RAD[$m]=$(modv "$m" radice); M_PAC[$m]=$(modv "$m" pacchetti); M_GRP[$m]=$(modv "$m" gruppo); M_RUN[$m]=$(modv "$m" runner)
  miss=$(modv "$m" pymiss); [ -z "$miss" ] || blocked "$miss"
done
excl_of() {  # <modulo> -> EX: l'elenco del nucleo + le cartelle di collega_nel_worktree del modulo
  local x
  EX=("${FIC_MIRROR_EXCL[@]}")
  while IFS= read -r x; do [ -n "$x" ] && EX+=("--exclude=$x"); done < "$TMPD/mod/$1/escludi"
}
CM=$(cat "$TMPD/copiamod")   # il modulo con copia fra quelli delle mutazioni ("" se nessuno)
LOCKPKG=$(cat "$TMPD/lockpkg")
LOCK="$MIR/$LOCKPKG/.fic-lock"
SRCC=""; DSTC=""
[ -n "$CM" ] && { SRCC="$ROOT/${M_PAC[$CM]}"; DSTC="$MIR/${M_PAC[$CM]}"; }

manifest_list() {  # <dir sorgente>: come test-fast.sh — tracciati + non tracciati non ignorati + .env*
  { git -c safe.directory='*' -C "$1" ls-files -co --exclude-standard -z . | tr '\0' '\n'
    (cd "$1" && find . \( -name node_modules -o -name .nuxt -o -name .output -o -name .venv \) -prune -o -name '.env*' -type f -print | sed 's|^\./||')
  } | LC_ALL=C sort -u
}

hashes() {  # <dir> <lista>: "sha  path" per ogni path della lista; ABSENT se manca
  (cd "$1" && while IFS= read -r f; do
     [ -n "$f" ] || continue
     if [ -f "$f" ]; then printf '%s  %s\n' "$(sha256sum < "$f" | cut -c1-64)" "$f"; else printf 'ABSENT  %s\n' "$f"; fi
   done < "$2")
}

if [ -n "$CM" ]; then
  why=""
  # copia di un worktree al primo uso: node_modules seminati dalla copia del tree principale (come test-fast.sh)
  if [ "$MIR" != "$HOME/fic-mirror" ] && ! { [ -d "$DSTC/node_modules" ] && [ -f "$DSTC/.fic-deps" ]; }; then
    why=$(fic_seed_node_modules "$SRCC" "$DSTC") && why="" || why="; semina non possibile: $why"
  fi
  [ -d "$DSTC/node_modules" ] && [ -f "$DSTC/.fic-deps" ] || blocked "mirror assente: eseguire test-fast.sh --setup$why"
fi
mkdir -p "$MIR/$LOCKPKG" || blocked "mirror non creabile: $MIR/$LOCKPKG"
[ -z "$RIPIEGO" ] || echo "counterproof: $RIPIEGO; piu' lenti, stessi esiti"
if [ -n "$FLOCK" ]; then
  exec 9>"$LOCK"
  flock -w "$WAIT" 9 || blocked "mirror occupato oltre ${WAIT}s (lock $LOCK); nessun ripiego su /mnt/c"
else
  fic_lock_dir "$LOCK.d" "$WAIT" || blocked "mirror occupato oltre ${WAIT}s (lock $LOCK.d); nessun ripiego su /mnt/c"
  LOCKD=$LOCK.d
fi

if [ -n "$CM" ] && ! fic_deps_ok "$SRCC" "$DSTC"; then
  # dipendenze stantie: riallineamento automatico sotto il lock (fic-mirror.sh, fic_deps_autorefresh), poi di nuovo
  # l'impronta; preparati e cache si ripuliscono comunque a ogni run nel sync qui sotto
  deps_out=$(fic_deps_autorefresh "$SRCC" "$DSTC") ||
    blocked "dipendenze stantie, riallineamento automatico non riuscito: $deps_out"
  echo "counterproof: $deps_out"
  fic_deps_ok "$SRCC" "$DSTC" || blocked "dipendenze stantie anche dopo il riallineamento automatico"
fi
for m in "${MODS[@]}"; do
  pk=${M_PAC[$m]}; src="$ROOT/$pk"; dst="$MIR/$pk"
  mkdir -p "$dst" || blocked "mirror non creabile: $dst"
  excl_of "$m"
  fic_sync --delete --checksum "${EX[@]}" "$src/" "$dst/" || blocked "sync fallito ($pk)"
  mapfile -t prepg < "$TMPD/mod/$m/preparati"
  fic_mirror_pulisci "$dst" "${M_GRP[$m]}" "${M_RUN[$m]}" ${prepg[@]+"${prepg[@]}"} || blocked "pulizia della copia fallita ($pk)"
  # copia_anche: cartelle di sola lettura che i test del modulo leggono (per esempio uno schema), allineate con
  # --delete, fuori dal manifest. Le mutazioni restano sotto il modulo.
  while IFS= read -r a; do
    [ -n "$a" ] && [ -d "$ROOT/$a" ] || continue
    mkdir -p "$MIR/$a" &&
      fic_sync --delete --checksum --exclude=node_modules "$ROOT/$a/" "$MIR/$a/" || blocked "sync fallito ($a)"
  done < "$TMPD/mod/$m/anche"
  git -c safe.directory='*' -C "$src" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
    manifest_list "$src" > "$TMPD/list.$m" && [ -s "$TMPD/list.$m" ] || blocked "manifest non calcolabile (git) per $pk"
  hashes "$src" "$TMPD/list.$m" > "$TMPD/src0.$m"
  hashes "$dst" "$TMPD/list.$m" > "$TMPD/base.$m"
  if ! cmp -s "$TMPD/src0.$m" "$TMPD/base.$m"; then
    echo "counterproof: differenze fra origine e mirror ($pk):"; diff "$TMPD/src0.$m" "$TMPD/base.$m" | head -5
    blocked "copia non allineata ($pk)"
  fi
done

py_ok() {  # <interprete>: eseguibile (percorso) o nel PATH (nome)
  case "$1" in */*) [ -x "$1" ] ;; *) command -v "$1" >/dev/null 2>&1 ;; esac
}

# Il runner di UNA mutazione: controprova.comando del modulo, espanso (riga del prep), nella radice del modulo dentro
# <radice>. <dir mutazione> <radice> <dir di lavoro> <cacheDir o ""> <riga>. Solo nelle copie private (cache
# impostata) e col runner vitest: cacheDir privata e fs.allow = radice della copia + node_modules del mirror, dove
# si risolve il symlink, + packages del mirror, dove si risolvono i link del workspace di node_modules.
run_cmd() {
  local d=$1 mroot=$2 w=$3 cache=$4 line=$5 mod cwd allow=""
  mod=$(cat "$d/modulo")
  cwd="$mroot${M_RAD[$mod]:+/${M_RAD[$mod]}}"
  if [ -n "$cache" ] && [ "$(cat "$d/runner")" = vitest ]; then allow="$mroot/${M_PAC[$mod]}:$DSTC/node_modules:$DSTC/packages"; fi
  CMD="(cd $cwd && ${allow:+FIC_VITE_CACHE_DIR=$cache FIC_VITE_FS_ALLOW=$allow }$line)"
  # 9>&-: il lock resta del solo processo principale, non dei run. `& wait`: un segnale al principale fa
  # scattare subito il trap, senza aspettare la fine del run. Il pid di `timeout` (env fa exec) e' anche il
  # pgid del gruppo che apre: registrato in runpgids, il trap uccide il gruppo intero.
  (cd "$cwd" || exit 1
   env ${allow:+"FIC_VITE_CACHE_DIR=$cache" "FIC_VITE_FS_ALLOW=$allow"} timeout -k 10 "$RUN_TIMEOUT" bash -c "$line" &
   echo $! >> "$TMPD/runpgids"; wait $!) 9>&- > "$w/log" 2>&1 &
  wait $!
}

restore() { rm -f "$2" && cp -p "$1" "$2"; }   # <copia di sicurezza> <file>: unlink + copia

# UNA mutazione in una radice che rispecchia il repo: il mirror (gradino 1) o una copia privata (gradino 2).
# <dir mutazione> <radice> <dir di lavoro> [cacheDir di vite]. Scrive <id>.json, appende la riga d'esito a
# <dir di lavoro>/results. Torna 5 se dopo il ripristino la radice non e' identica al manifest iniziale.
run_one() {
  local d=$1 mroot=$2 w=$3 cache=${4:-}
  local f mod py rep line mf why rc t0 ms out cp esito ids
  f=$(cat "$d/file"); mod=$(cat "$d/modulo"); py=$(cat "$d/python")
  mf="$mroot/$f"
  rm -f "$w/report" "$w/bak"; : > "$w/log"
  why=""; rc=0; CMD=""; t0=$(date +%s%N)
  # un interprete Windows (.exe, lanciato da WSL) scrive il report con un percorso Windows
  rep="$w/report"
  case "$py" in *.exe) command -v wslpath >/dev/null 2>&1 && rep=$(wslpath -w "$w/report") ;; esac
  if [ -n "$py" ] && ! py_ok "$py"; then
    why="interprete di {python} assente: $py (impostare FIC_PYTEST_PY)"
  elif ! line=$("$FIC_PY" -c "$PY" riga "$d" "$rep" 2>"$w/log"); then
    why="comando della controprova non espandibile: $(head -1 "$w/log")"
  elif line=${line%$'\r'}; [ ! -f "$mf" ]; then
    why="file assente nel mirror: $f"
  elif ! cp -p "$mf" "$w/bak"; then
    why="copia di sicurezza non riuscita: $f"
  else
    printf '%s' "$mf" > "$w/inflight"   # registrato PRIMA di scrivere: il trap sa cosa ripristinare
    if out=$("$FIC_PY" -c "$PY" apply "$mf" "$d/cerca" "$d/sost" 2>&1); then
      run_cmd "$d" "$mroot" "$w" "$cache" "$line"
      rc=$?
    else
      why=${out:-mutazione non applicabile}
    fi
    restore "$w/bak" "$mf"   # RIPRISTINO
    : > "$w/inflight"
    hashes "$mroot/${M_PAC[$mod]}" "$TMPD/list.$mod" > "$w/now.$mod"
    if ! cmp -s "$TMPD/base.$mod" "$w/now.$mod"; then
      echo "counterproof: $mroot NON ripristinato dopo $(basename "$d") ($f):"; diff "$TMPD/base.$mod" "$w/now.$mod" | head -5
      return 5
    fi
  fi
  ms=$(( ($(date +%s%N) - t0) / 1000000 ))
  line=$("$FIC_PY" -c "$PY" result "$d" "$OUT" "$w/report" "$rc" "$ms" "$w/log" "$CMD" "$why") ||
    { echo "counterproof: risultato non scrivibile in $OUT" >&2; return 64; }
  printf '%s\n' "$line" >> "$w/results"
  read -r cp esito _ ids _ <<< "$line"
  echo "counterproof: $ids -> $esito ($cp, $((ms / 1000)) s)${line#*--}"
}

# ── Gradino 2: quali mutazioni vanno in parallelo, e su quante copie ─────────────────────────────────
# Solo vitest su file sotto la radice del modulo con copia: i link del workspace in node_modules puntano ai
# pacchetti DEL MIRROR, quindi una mutazione fuori dalla radice fatta in una copia privata sarebbe invisibile
# (falso «verde»): quelle, gli altri moduli e gli altri runner restano seriali nel mirror. Per la stessa ragione
# (le copie leggono i pacchetti del mirror) il lock del mirror resta preso per tutto il gradino 2.
# N = min(FIC_CP_PARALLEL [4], MemAvailable / FIC_CP_MEM_MB, nproc/2, mutazioni parallelizzabili); N < 2 =>
# tutto seriale. FIC_CP_MEM_MB: memoria di UN run vitest. Misurata il 2026-09-29 su MemAvailable durante i
# run (goals-utils + goals-page): ~1,1 GB di picco per un run da solo, ~3,3 GB per 4 in parallelo. Il default
# 1500 tiene il picco del run singolo con margine: con ~11 GB liberi il tetto resta quello di FIC_CP_PARALLEL.
MEM_MB=${FIC_CP_MEM_MB:-1500}
N=${FIC_CP_PARALLEL:-4}
case "$N$MEM_MB" in *[!0-9]*) echo "counterproof: FIC_CP_PARALLEL e FIC_CP_MEM_MB vogliono un intero" >&2; exit 64 ;; esac
[ "$MEM_MB" -gt 0 ] || MEM_MB=1
SER=(); PAR=()
for d in "$TMPD"/m/*; do
  par=0
  if [ -n "$CM" ] && [ "$(cat "$d/runner")" = vitest ] && [ "$(cat "$d/modulo")" = "$CM" ]; then
    f=$(cat "$d/file"); r=${M_RAD[$CM]}
    [ -z "$r" ] || [ "${f#"$r"/}" != "$f" ] && par=1
  fi
  if [ $par = 1 ]; then PAR+=("$d"); else SER+=("$d"); fi
done
AVAIL=$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo 2>/dev/null)
NMEM=$(( ${AVAIL:-0} / MEM_MB )); NCPU=$(( $(nproc) / 2 ))
[ "$NMEM" -lt "$N" ] && N=$NMEM
[ "$NCPU" -lt "$N" ] && N=$NCPU
[ "${#PAR[@]}" -lt "$N" ] && N=${#PAR[@]}
if [ "$N" -lt 2 ]; then SER+=(${PAR[@]+"${PAR[@]}"}); PAR=(); fi

q_pop() { k=$(cat "$TMPD/q.next"); echo $((k + 1)) > "$TMPD/q.next"; sed -n "$((k + 1))p" "$TMPD/q.all"; }
next_job() {  # coda dinamica condivisa dai worker: la prossima mutazione, o niente. Senza flock: mkdir, senza tetto
  if [ -n "$FLOCK" ]; then
    ( flock 8; q_pop ) 8>"$TMPD/q.lock"
  else
    ( fic_lock_dir "$TMPD/q.lock.d" || exit 1; trap 'fic_unlock_dir "$TMPD/q.lock.d"' EXIT; q_pop )
  fi
}

T_ALL=$(date +%s%N)
: > "$TMPD/results"
# Gradino 1: seriale nel mirror, sotto il lock.
for d in ${SER[@]+"${SER[@]}"}; do
  run_one "$d" "$MIR" "$TMPD"; r=$?
  if [ "$r" -eq 5 ]; then
    echo "counterproof: esito=BLOCKED (integrita': mirror non ripristinato, lista interrotta) luogo=mirror"; exit 5
  fi
  [ "$r" -eq 0 ] || exit "$r"
done

# Gradino 2: N copie private del SOLO sorgente del modulo con copia, fatte dal mirror verificato; i run girano nelle
# copie, fuori dal mirror. Il lock del mirror resta preso per TUTTO il gradino (snapshot, run, verifica finale): le
# copie leggono ancora il mirror — node_modules radice e' un symlink al suo (sola lettura), e i link del workspace
# li' dentro portano ai SUOI pacchetti — quindi un altro test-fast.sh o counterproof.sh che lo sincronizzasse
# cambierebbe il codice sotto i run. I node_modules annidati (piccoli, con le cache di vite/jiti) sono copiati
# senza cache; cacheDir di vite/vitest privata per copia (FIC_VITE_CACHE_DIR, letta da vitest.config.ts).
# Niente `cp -al`: un hard link condividerebbe l'inode, e la mutazione di una copia toccherebbe le altre.
INTEG=0; DEPS_CHANGED=0; LUOGO=mirror
if [ ${#PAR[@]} -gt 0 ]; then
  DEPS0=$(cat "$DSTC/.fic-deps")
  CPD=$(mktemp -d "$HOME/fic-cp.XXXXXX") || blocked "copie private non creabili in $HOME"
  NESTED=$(cd "$DSTC" && find . -path ./node_modules -prune -o -name node_modules -type d -prune -print | sed 's|^\./||')
  excl_of "$CM"
  for i in $(seq 1 "$N"); do
    c="$CPD/$i/${M_PAC[$CM]}"; mkdir -p "$c"
    fic_sync "${EX[@]}" "$DSTC/" "$c/" || blocked "copia privata $i non creata"
    while IFS= read -r nm; do
      [ -n "$nm" ] || continue
      fic_sync --exclude=.cache --exclude=.vite --exclude=.vitest "$DSTC/$nm/" "$c/$nm/" || blocked "copia privata $i: $nm non copiato"
    done <<< "$NESTED"
    ln -s "$DSTC/node_modules" "$c/node_modules" || blocked "copia privata $i: link a node_modules non creato"
    hashes "$c" "$TMPD/list.$CM" > "$TMPD/copy.$i"
    cmp -s "$TMPD/base.$CM" "$TMPD/copy.$i" || blocked "copia privata $i non identica al manifest"
  done
  LUOGO="copie($N)"
  echo "counterproof: gradino 2 — ${#PAR[@]} mutazioni su $N copie private in parallelo (MemAvailable ${AVAIL} MB, ${MEM_MB} MB a run); lock del mirror tenuto fino alla fine"
  printf '%s\n' "${PAR[@]}" > "$TMPD/q.all"; echo 0 > "$TMPD/q.next"
  PIDS=()
  for i in $(seq 1 "$N"); do
    ( w="$TMPD/w$i"; mkdir -p "$w"; : > "$w/results"; : > "$w/inflight"
      while d=$(next_job) && [ -n "$d" ]; do run_one "$d" "$CPD/$i" "$w" "$CPD/$i/.fic-vite-cache" || exit $?; done ) 9>&- &
    PIDS+=($!)
  done
  for p in "${PIDS[@]}"; do wait "$p" || INTEG=1; done
  # Verifica finale, ancora sotto il lock: i sorgenti del mirror (letti dalle copie tramite il workspace) sono quelli
  # dello snapshot. `test-fast.sh --setup` il lock non lo prende: se ha cambiato node_modules, lo si dice.
  hashes "$DSTC" "$TMPD/list.$CM" > "$TMPD/final.$CM"
  cmp -s "$TMPD/base.$CM" "$TMPD/final.$CM" || DEPS_CHANGED=1
  [ "$(cat "$DSTC/.fic-deps" 2>/dev/null)" = "$DEPS0" ] || DEPS_CHANGED=1
fi
TOT_S=$(( ($(date +%s%N) - T_ALL) / 1000000000 ))

NPASS=0; NFAIL=0; NBLOCK=0
while read -r cp _ n _; do
  [ -n "${cp:-}" ] || continue
  case "$cp" in PASS) NPASS=$((NPASS + n)) ;; FAIL) NFAIL=$((NFAIL + n)) ;; *) NBLOCK=$((NBLOCK + n)) ;; esac
done < <(cat "$TMPD/results" "$TMPD"/w*/results 2>/dev/null)

# Il working tree non e' mai stato scritto da qui: se e' cambiato, l'ha cambiato qualcun altro durante le
# controprove, e i risultati valgono per lo stato sincronizzato all'inizio. Dichiarato, non nascosto.
for m in "${MODS[@]}"; do
  hashes "$ROOT/${M_PAC[$m]}" "$TMPD/list.$m" > "$TMPD/src1.$m"
  cmp -s "$TMPD/src0.$m" "$TMPD/src1.$m" ||
    echo "counterproof: ATTENZIONE: ${M_PAC[$m]} e' cambiato nel working tree DURANTE le controprove (non da questo script): i risultati valgono per lo stato iniziale"
done

SUM="prove=$NPASS/$NT fail=$NFAIL bloccate=$NBLOCK tempo=${TOT_S}s luogo=$LUOGO$ABS"
if [ "$INTEG" -ne 0 ]; then
  echo "counterproof: esito=BLOCKED (integrita': copia privata non ripristinata, worker interrotto) $SUM"; exit 5
fi
if [ "$DEPS_CHANGED" -ne 0 ]; then
  echo "counterproof: esito=BLOCKED (mirror cambiato durante il gradino 2, sorgenti o node_modules: risultati non validi, rilanciare) $SUM"; exit 3
fi
if [ "$NFAIL" -gt 0 ]; then E=FAIL; RC=1
elif [ "$NBLOCK" -gt 0 ]; then E=BLOCKED; RC=2
else E=PASS; RC=0
fi
echo "counterproof: esito=$E $SUM"
exit $RC
