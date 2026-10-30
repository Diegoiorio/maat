#!/usr/bin/env bash
# run-phase.sh — lancia UNA fase di /full-implementation-cycle in una sottosessione Claude separata
# (contesto vuoto), non interattiva, e ne salva il log stream-json.
#
#   run-phase.sh <run-dir> <etichetta> <file-prompt>
#   run-phase.sh --lock-status      libero / dentro il ciclo → exit 0 · occupato → exit 1 (per le skill a mano)
#   run-phase.sh --harness-fp [<repo>]   stampa harness.fp (tre righe, sotto) · exit 1 se non calcolabile
#   run-phase.sh --harness-fp-confronta <harness.fp> [<repo>]   la decisione dei tre lettori, una riga (sotto)
#   run-phase.sh --harness-paths         stampa i file dell'impronta (relativi a MAAT_ROOT) e .claude/maat.json
#   run-phase.sh --valida <log.jsonl> <schema> <fase> <result.json>   il validatore interno dell'esito, da solo
#                                        (termine di confronto di script/fic/driver.py equiv; sotto, VALIDA_PY)
#
# DRIVER (harness-pt14): le fasi le lancia script/fic/driver.py (`driver.py run`), sempre attraverso questo script.
# Qui il driver entra in un punto solo, la validazione dell'esito (`driver.py valida`), e solo col certificato di
# equivalenza valido (INVOLUCRO, sotto VALIDA_PY). Senza certificato questo script e' autonomo come prima.
#
#   <run-dir>     .claude/.ai-workflow/spec-<name>.run   (gitignorata da "spec-*")
#   <etichetta>   es. 01-plan, 02-implement, 03-review, 04-fix (la fase si legge dall'etichetta)
#   <file-prompt> il prompt della fase, passato su stdin (niente limiti di lunghezza della riga)
#
# Scrive in <run-dir>/log/: <etichetta>.jsonl (log), .stderr, .running (mentre gira), .exit (codice),
# .esito (riga "ESITO FASE …" dell'evento result + "state=<hash>" di cycle-state.sh, solo se la
# sottosessione esce 0: e' cio' che fa passare cycle-state da implement/fix a review).
# Fasi implement/fix: .pre-tree/.post-tree e <run-dir>/touched.txt (sotto, ATTRIBUZIONE).
# GATE (harness-pt04): dopo un implement/fix finito OK e prima di ogni review, script/fic/gates.sh (livello
# in vigore, file di touched.txt) gira QUI, fuori dalla sotto-sessione: esito in .gates, evidenza in
# <run-dir>/evidence/<chiave>/; la review riceve la cartella in coda al prompt (.prompt = prompt effettivo).
# La sotto-sessione ha anche un hook Stop (script/fic/stop-hook.py) accanto alla guardia.
# ESITO STRUTTURATO (harness-pt08): la sotto-sessione riceve --json-schema con script/fic/schemas/
# phase-result.schema.json (il contenuto: il CLI vuole lo schema, non il file) e, IN PIU', qui si rivalida il
# blocco JSON dell'ultimo evento result (structured_output, altrimenti l'ultimo recinto ```json del testo) con lo
# stesso schema: jsonschema se c'e', altrimenti il validatore minimo qui sotto; "fase" deve essere quella
# dell'etichetta. Valido -> log/<label>.result.json (letto da cycle-state.sh). Assente o non valido -> nessun
# result.json e .esito = "ESITO FASE <fase>: STOP — uscita non valida: <errori>", con la riga ESITO del testo
# conservata sotto "originale=". La riga ESITO resta scritta sempre (compatibilita' e revert). Prosa e JSON
# discordi: vale il piu' conservativo (prosa OK ma JSON STOP, deviazioni o bloccato_su -> .esito STOP con
# originale=; prosa STOP -> resta STOP). .esito e' l'autorita'.
# DEVIAZIONI DIFENSIVE: una deviazione che comincia con "difensiva: " (ramo di robustezza, ripiego per un caso che
# piano o schema escludono, helper interno: nessun effetto sui casi previsti) non ferma la fase; se TUTTE lo sono,
# l'esito e' quello che sarebbe senza deviazioni. Un implement/fix finito OK le registra: una riga
# "<label><TAB><testo>" in <run-dir>/log/deviazioni-difensive.txt, un AVVISO in .esito e una nota nel changelog del
# piano (fuori dall'impronta Approved basis: se l'impronta cambiasse la spec torna com'era). La review le riceve in
# coda al prompt (riga "DEVIAZIONI DIFENSIVE (driver, run-phase.sh): …"): una non puramente difensiva e' un major.
# FINALIZE (harness-pt08): dopo una review uscita 0, script/fic/finalize.sh firma lo stato finale (conferma
# IMPLEMENTED solo con l'evidenza alla chiave attuale, altrimenti NEEDS_VERIFICATION): esito in .finalize.
# Fail-closed: finalize assente o uscito con un codice diverso da 0/1/3/4 -> .esito = "ESITO FASE review: STOP —
# finalize non eseguito|fallito"; e cycle-state.sh non da' DONE senza una riga Finalize: IMPLEMENTED recente.
# Finalize gira dopo la scrittura di result.json e riceve --copertura log/<label>.result.json (harness-pt09).
# REVIEW IN PARALLELO CON LA VERIFICA (harness-pt09). Fase review: si calcola la chiave del tree (review-surface.sh
# tree; con le controprove del driver anche lo sha256 di counterproof/mutations.json) e partono INSIEME, in
# background, VERIFY = gates.sh (poi counterproof.sh — dentro WSL solo su Windows e con un modulo delle mutazioni
# `ambiente: wsl`, altrimenti diretto (run_cp) — SOLO se mutations.json e' la lista di
# `plan-check.sh gen` coerente col piano: <run>/gen/procedura.txt con l'"Impronta piano:" attuale e la lista
# identica a una rigenerata qui in log/.gen-verifica.<pid>; niente sidecar *.meta. Altrimenti — formato 1, lista
# scritta dal worker a un giro precedente, piano cambiato — le controprove restano del worker, che riscrive la
# lista a ogni giro, come prima) e la sotto-sessione di review, col
# prompt + la riga "VERIFY IN PARALLELO …" (il reviewer scrive gli ID dei test per requisito nel campo copertura,
# non i risultati; verdetto provvisorio). A fine di entrambe la chiave si ricalcola: diversa (o non calcolabile)
# -> entrambi i risultati scartati (spec rimessa com'era da log/<label>.spec-pre, .gates/.counterproof in
# *.scartato, la cartella evidence/<chiave> indicata in .gates rinominata <chiave>.scartato — non piu' riusabile
# da gates.sh ne' FRESH per finalize.sh —, <id>.json del giro cancellati anche in modo worker, evento
# {"subtype":"fic_scartato"} nel log: l'esito si legge solo
# dopo) e rilancio in SEQUENZA. La sequenza e' quella di prima (gate, poi review con EVIDENZE DEI GATE nel prompt)
# e vale anche con FIC_REVIEW_PARALLEL=0, con una sezione di review registrata APPROVED (promozione e gate-only non
# lanciano il reviewer: non cambiano) e con la chiave non calcolabile. Il modo sta in log/<label>.parallelo.
# Verdetto = AND in finalize.sh: gate FAIL o controprova non rossa -> FAIL; BLOCKED -> NEEDS_VERIFICATION.
# counterproof.sh del driver: esito in log/<label>.counterproof (exit=); uscita fuori da 0/1/2 -> i suoi <id>.json
# si cancellano (non valgono: finalize li conta assenti); exit 5 (mirror non ripristinato) -> .esito STOP.
# Variabili: FIC_REVIEW_PARALLEL (1 default, 0 = sequenza) · FIC_CP_CMD programma che riceve il percorso di
# mutations.json al posto di counterproof.sh (test) · FIC_COUNTERPROOF percorso dello script
# · FIC_PLAN_CHECK percorso di plan-check.sh. VERIFY in background scrive vpid= nell'owner del lock: finche' vive,
# il lock non si libera (lock_alive, release), anche se run-phase viene ucciso.
# CORSIE (harness-pt13, L1). Fase implement: prima di lanciare, `plan-check.sh gen` rigenera la procedura dal piano
# attuale in una cartella a parte e script/fic/blocks-independent.py decide (log/<label>.corsie: esito, corsia k,
# scope k, dipendenze). Esito parallelo -> sotto lo STESSO lock due sotto-sessioni `claude -p` insieme, ciascuna con
# FIC_LANE=k (vitest-fast.sh usa la copia <copia della radice>-<k>; WSLENV la porta in WSL) e FIC_WRITE_SCOPE =
# i file di scrive: dei suoi blocchi (guard.py nega Edit/Write fuori); prompt log/<label>.corsia-<k>.prompt = il
# prompt + la riga "CORSIA k/2 …", log in log/<label>.corsia-<k>.jsonl, PID in cpid= e cpid2= dell'owner. A corsie
# finite il CONTROLLO A POSTERIORI: path cambiati fra .pre-tree e il tree di ora (log/<label>.cambiati) divisi per
# scope con blocks-independent.py --posteriori (log/<label>.posteriori): un file fuori dall'unione, attribuito a
# entrambe le corsie (nel suo scope e dichiarato dall'altra nel "file" del JSON) o condiviso/generato -> STOP. Poi
# in <label>.jsonl un solo evento result UNITO (ESITO, JSON: unione di file/deviazioni/gate, bloccato_su), che la
# validazione di sempre legge. Corsia col solo JSON nel result (uscita strutturata, nessuna riga "ESITO FASE"): la
# riga si ricava dall'oggetto valido ("ESITO FASE implement: <OK|STOP> — <motivo>"), come in serie; riga di testo e
# oggetto discordi -> vince lo STOP. Le liste del preflight delle corsie (do-not-touch.<k>.txt, mixed.<k>.txt) si uniscono
# (sort -u) in do-not-touch.txt e mixed.txt, le sole lette dalle fasi successive. I gate restano quelli del driver
# sull'albero intero, a corsie finite (sotto).
# Serie, come prima, con: FIC_LANES=0, fase diversa da implement, formato 1 o gen non riuscito, tree iniziale non
# calcolato, blocchi dipendenti (una condizione falsa basta).
# Con FIC_CORSIE=<file> (harness-pt14: lanciato da script/fic/driver.py) la decisione e' quella del driver, presa con
# gli stessi comandi (gen in una cartella a parte, blocks-independent.py): il file diventa log/<label>.corsie e
# launch_lanes parte come sempre. FIC_LANES=0 e il tree iniziale restano controllati qui.
# Uscita: quella della sottosessione · 2 = uso · 3 = binario claude non trovato ·
#         4 = un'altra fase di CODICE e' in corso (lock), o un'altra fase di PIANO sulla stessa spec
#             (lock per spec) · 5 = guardia non attiva: non si lancia · 6 = STOP, harness cambiato dal
#             primo lancio del ciclo (sotto, IMPRONTA DEL HARNESS): non si lancia · 7 = STOP della catena
#             (sotto, CATENE): non si lancia.
#
# CATENE (harness-pt12; le regole sono in cycle-state.sh, righe C1-C4).
#   Anello: all'avvio di un implement di un anello k>1 (spec elencata nella riga Figlie: di una madre, nessun
#   .pre-tree ancora nella sua run dir) si chiede a cycle-state.sh: "STOP — catena" (tree diverso dal .post-tree
#   di k-1) o "WAIT — catena" (k-1 non chiuso) → exit 7, la sotto-sessione non parte.
#   Review di un anello k>1: il driver scrive log/<label>.anello.diff = review-surface.sh diff dalla "Base anello"
#   (.post-tree di k-1, mai HEAD) al tree attuale sui file del touched.txt dell'anello, e ne mette file e indice in
#   coda al prompt (riga "DIFF DELL'ANELLO (driver, run-phase.sh): …"). Base assente o diff fallito → exit 7.
#   Chiusura: etichetta NN-chiusura sulla run dir della MADRE. Fase di codice (lock), senza sotto-sessione se non
#   serve: touched.txt = unione dei touched.txt degli anelli, base.txt = quello del primo anello, gate a livello
#   full (script/fic/gates.sh) sull'albero finale. Se le figlie hanno righe [e2e-locator: <spec>] e i gate sono
#   verdi, la sotto-sessione parte col prompt piu' la riga "E2E DELLA CATENA: <spec…>" (worker chiusura:
#   /dev-verify, sotto la stessa guardia) e conta la sua riga "ESITO FASE chiusura: OK" (nessun --json-schema:
#   la fase non e' nello schema dell'esito). Scrive <run-dir>/chiusura.txt: "Chiusura: IMPLEMENTED — base <b> ·
#   tree <t> · gates PASS · e2e <…> · <ora UTC>" oppure "Chiusura: NEEDS_VERIFICATION — <motivo> · <ora UTC>", e
#   log/<label>.esito. La madre e' DONE (cycle-state.sh) solo con la prima, sul codice attuale.
#
# IMPRONTA DEL HARNESS (pt03; incidente ux-1..4: harness modificato da un'altra sessione sotto un ciclo).
# Al primo lancio di un ciclo (run dir senza fasi girate: nessun .running, nessun .exit che non sia
# 2/4/5) si scrive <run-dir>/harness.fp (pk04a-2), tre righe: "impronta=<64 esadecimali>", "versione=<version di
# .claude-plugin/plugin.json>", "radice=<MAAT_ROOT, forma C:/…>". L'impronta e' lo sha256 delle righe
# "<sha256 del contenuto senza CR> <percorso>" di tutti i file sotto MAAT_ROOT (percorso relativo, ordine LC_ALL=C)
# tranne HARNESS_EXCLUDE, piu' in coda <progetto>/.claude/maat.json (assente: riga fissa ".claude/maat.json
# ASSENTE"). Niente git: la cache dei plugin non e' un repository; le skill del progetto non ne fanno parte.
# A ogni fase successiva si confronta con hfp_confronta (--harness-fp-confronta), la funzione UNICA usata anche da
# cycle-state.sh e driver.py: UGUALE → si va avanti; CAMBIATO, FORMATO-PRECEDENTE (una riga sola di 64
# esadecimali: ciclo iniziato col harness interno), ILLEGGIBILE (vuoto, troncato, senza impronta) o NON-CALCOLABILE
# → STOP, exit 6, con la data della registrazione e il rimedio. Versione e radice non entrano nel confronto. Una
# run dir senza harness.fp e con fasi gia' girate (ciclo avviato prima di questa regola) non si controlla.
#
# PERMESSI (decisione dell'utente, 2026-09-21). In modalita' -p le scritture sotto .claude/ — dove vive
# la spec — passano SOLO in bypass: misurato, ne' acceptEdits ne' regole Edit(path) le sbloccano.
# Quindi bypass + due strati:
#   1. DENY per prefisso (sotto): ferma il comando diretto e le catene con &&, NON un comando avvolto
#      in `wsl -- bash -lc '...'` o `bash -c '...'` (misurato);
#   2. guard.py come hook PreToolUse (passato con --settings; misurato 2026-09-22: in -p + bypass l'hook
#      scatta e l'exit 2 blocca anche il comando annidato). Guarda il comando intero: produzione e rilascio del
#      progetto, accesso remoto diretto, git che cambia stato, docker, psql, installazioni, rm -rf; e nelle fasi
#      plan/review le scritture fuori dalla cartella di lavoro. L'hook e' fail-open (se FALLISCE lascia
#      passare): per questo, prima di lanciare, l'autotest gli fa negare la sonda di `maat-config.py
#      sonda-produzione` (o, senza guardia.produzione, `git push --force origin x`) con lo STESSO comando
#      dell'hook, e se non nega non si lancia (exit 5). Cosa resta scoperto: docstring di guard.py.
#   Le guardie in una sotto-sessione sono DUE, ed e' voluto: questa (deny, senza --universal) e l'hook del plugin
#   (hooks/hooks.json → guard-hook.sh → guard.py --universal, che con FIC_PHASE nega con exit 2: legge anche il
#   contenuto di `bash script/x.sh`, i `cd` e le regole git sui worktree). pk01 D2: l'hook del plugin scatta anche
#   nelle sotto-sessioni e si somma a --settings. Tutte e due leggono MAAT_CONFIG, esportato qui sotto.
#   Niente MCP (--strict-mcp-config senza --mcp-config): nessuna fase della catena li usa; misurato
#   2026-09-22, tool all'avvio 79 -> 31 (48 MCP: chrome-devtools, Drive, Docs). Capacita' in meno, non
#   un risparmio di contesto (sono caricati in differita: -2k token).
#   Il test controlla l'argomento; la misura sull'evento system/init si ripete a mano (phase-usage.py:
#   colonna "tool all'avvio (mcp N)") dopo un aggiornamento del CLI.
#
# LOCK (fasi implement/review/fix): working tree, controprove, sync e context e2e del DEV sono
# condivisi, quindi una sola fase di codice alla volta, di qualunque feature. Le fasi plan di spec
# DIVERSE girano in parallelo; due plan sulla STESSA spec no (incidente ux-6: piano approvato
# sovrascritto): ogni plan prende <run-dir>/plan.lock, stessa liveness, e il secondo esce 4 col
# proprietario. Non e' un lock globale sul planning. Il lock e' una directory dentro .git (mai superficie di review) con i PID MSYS di
# questo script e della sottosessione: vivo se almeno uno dei due esiste (`kill -0` vede anche i
# processi di altre finestre Git Bash). NON il PID Windows letto da /proc/<pid>/winpid subito dopo
# `&`: e' quello dello stub del fork, non di claude.exe (misurato 2026-09-22). Le skill lanciate a mano
# (/implementation-review-cycle, /dev-verify --e2e) lo interrogano con --lock-status e si fermano se e'
# occupato; non lo prendono.
#
# ATTRIBUZIONE (fasi implement/fix): tree del working tree prima e dopo la sottosessione; i path che
# cambiano fra i due finiscono in <run-dir>/touched.txt e non possono essere esclusi dalla review. Col
# lock preso nessun'altra fase di codice gira, quindi il delta e' della feature; una modifica umana
# fatta nello stesso intervallo ci finisce dentro (sovra-inclusione: direzione sicura). Una fase
# uccisa lascia .pre-tree senza .post-tree: la chiude la fase di codice successiva della stessa feature,
# oppure — se e' di un'altra feature — quella che ne riprende il lock orfano, prima di cambiare il tree.
# Il .post-tree esiste SOLO se tree iniziale, tree finale e diff sono riusciti: e' la prova che
# cycle-state.sh chiede prima di mandare una fase implement/fix OK in review. Un fallimento qui e' un
# AVVISO, ma il ciclo si ferma li' (fail-closed a valle, non una fase lasciata a meta' col lock).
#
# ALTRI FLUSSI (incidente: PRODUZIONE.md modificato dall'utente in un'altra sessione durante test-red). Il diff dei
# tree non sa CHI ha scritto: per ogni path cambiato nella fase il driver chiede ai log della sotto-sessione
# (NOMI_PY, sotto) se l'ha nominato. test-red: un path fuori scope mai nominato non ferma la fase; va in
# do-not-touch.txt (forma del preflight), esce da touched.txt se ci e' entrato in questa fase, e c'e' un AVVISO
# (.stderr, .esito dopo state=, log/<label>.avvisi, log/<label>.altri-flussi). Nominato, o log inservibili -> STOP
# come prima. implement/fix, conservativo (formatter e generatori scrivono senza nominare): il path mai nominato
# RESTA in touched.txt, annotato in log/<label>.altri-flussi con un AVVISO; nessuno STOP, nessun file tolto.
# test-red: un path gia' in touched.txt prima della fase (lavoro della feature) e cambiato senza essere nominato
# non puo' stare sia in touched.txt sia in do-not-touch -> STOP col motivo, decide l'utente.
# LIMITE: un programma che calcola i path da se' (generatori, script Python/Node che percorrono cartelle, codegen
# senza argomenti) scrive senza nominarli. Se la sotto-sessione di test-red ne lancia uno che scrive fuori scope, la
# scrittura sembra di un altro flusso: niente STOP, il file va in do-not-touch (e l'AVVISO lo dice). Le regole di
# NOMI_PY coprono i comandi che scrivono noti (antenate, glob, punto, --fix/--write/-u), non un programma arbitrario.
#
# FASE TEST-RED (harness-pt11; etichetta *test-red*, solo piani in formato 2, fra piano APPROVED e implement):
# fase di CODICE (lock, .pre-tree/.post-tree, touched.txt). La guardia le da' uno scope suo (FIC_SCOPE =
# log/<label>.scope, da `plan-check.sh accept`): i file di test del piano + i file che il piano dichiara nuovi.
# La sotto-sessione (agente acceptance-test-writer) scrive i test di accettazione e gli stub; poi, QUI, la
# verifica del driver: gates.sh mirato (livello std, file di test del piano + touched.txt; esito in .gates) e
# `plan-check.sh rossi` sull'evidenza (.rossi, <run-dir>/test-red/rossi.json): ogni test rosso sulla sua
# asserzione, nessun import/raccolta, nessun verde, nessuna suite esistente in conflitto; altrimenti .esito =
# "ESITO FASE test-red: STOP — …" (originale= sotto). Chiusura OK: test-red/stubs.json, test-red/tests.txt,
# " · tests <fp>" nell'Approved basis (plan-check.sh basis --write-tests) e gen (controprove assorbite, L2).
# Dopo implement e fix OK: i file dei test di accettazione confrontati con test-red/tests.txt; diversi ->
# .esito STOP «deviazione: test di accettazione modificati» a prescindere dal report (gli stub no), salvo la
# MODIFICA PRESCRITTA (file nello scrive: di un blocco, funzioni dei test di accettazione invariate o non
# verificabili): OK con un AVVISO e l'impronta dei test riregistrata (vedi tests_guard).
# S3 · TEST IN SOSTA (etichetta *test-stage*): nessun lock (non scrive lo spec ne' il tree), scope = la sola
# <run-dir>/staging/, <run-dir>/staging.fp = impronta del piano al lancio. Una test-red trova lo staging con
# l'impronta del piano attuale -> copia nel tree i file dello scope (staging -> staging.copiato), niente
# sotto-sessione, e la verifica; impronta diversa -> staging scartato, la sotto-sessione scrive i test.
#
# Per aggiornare QUESTO file mentre un ciclo gira: scrivere una copia e fare `mv` sopra l'originale.
# Riscriverlo sul posto e' pericoloso: bash rilegge lo script dal disco mentre lo esegue.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_ROOT/MAAT_SCRIPTS (plugin) e PROJECT_ROOT (cartella di lavoro)
RS="$MAAT_SCRIPTS/review-surface.sh"

# --- impronta del harness (vedi IMPRONTA DEL HARNESS) ---
# L'elenco UNICO delle esclusioni, usato dal calcolo e da --harness-paths: ogni voce e' un glob confrontato con OGNI
# componente del percorso relativo a MAAT_ROOT (le prime due escludono cartelle, le altre i file temporanei d'editor
# e di merge ovunque si trovino). Niente .gitignore: sotto MAAT_ROOT entra ogni altro file.
HARNESS_EXCLUDE=(__pycache__ assets '*.swp' '*.orig' .DS_Store '*~')
# Il calcolo in UN processo (libreria standard): su Windows un processo per file costava secondi a ogni confronto.
#   argv: elenco|impronta <MAAT_ROOT> <progetto> -- <HARNESS_EXCLUDE…> · uscita 1 = file non leggibile
# elenco: i file del harness relativi a MAAT_ROOT (file regolari, non link), senza le componenti escluse (fnmatch,
# maiuscole distinte), in ordine di byte UTF-8 (= LC_ALL=C sort). impronta: sha256 delle righe
# "<sha256 del contenuto senza CR> <percorso>\n" di quei file, piu' in coda quella di <progetto>/.claude/maat.json
# (o ".claude/maat.json ASSENTE\n").
HFP_PY='
import fnmatch, hashlib, os, sys
modo, root, prog = sys.argv[1:4]
esc = sys.argv[5:]
def escluso(rel):
    return any(fnmatch.fnmatchcase(c, p) for c in rel.split("/") for p in esc)
def h(p):
    with open(p, "rb") as fh:
        return hashlib.sha256(fh.read().replace(b"\r", b"")).hexdigest()
def errore(d):
    raise OSError(d)
try:
    files = []
    for d, dirs, fs in os.walk(root, onerror=errore):
        for n in fs:
            full = os.path.join(d, n)
            if os.path.islink(full) or not os.path.isfile(full):
                continue
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            if not escluso(rel):
                files.append(rel)
    files.sort(key=lambda s: s.encode("utf-8", "surrogateescape"))
    out = sys.stdout.buffer
    if modo == "elenco":
        out.write("".join(f + "\n" for f in files).encode("utf-8", "surrogateescape"))
        sys.exit(0)
    righe = "".join("%s %s\n" % (h(os.path.join(root, f)), f) for f in files)
    mj = os.path.join(prog, ".claude", "maat.json")
    if os.path.exists(mj):
        if not os.path.isfile(mj):
            sys.exit(1)
        righe += "%s .claude/maat.json\n" % h(mj)
    else:
        righe += ".claude/maat.json ASSENTE\n"
    out.write(hashlib.sha256(righe.encode("utf-8", "surrogateescape")).hexdigest().encode())
except OSError:
    sys.exit(1)
'
hfp_win() { # $1 = variabile, $2 = percorso → la variabile in forma C:/… su Windows; nessun processo se lo e' gia'
  local w=$2
  [[ $w =~ ^[A-Za-z]:/ ]] || w=$(maat_cygm "$2") || w=$2
  printf -v "$1" '%s' "$w"
}
hfp_py1() { # "$@" = interprete → l'uscita di HFP_PY se valida (hfp_modo, hfp_r, hfp_p del chiamante), altrimenti 1
  local o
  o=$(PYTHONDONTWRITEBYTECODE=1 "$@" -c "$HFP_PY" "$hfp_modo" "$hfp_r" "$hfp_p" -- "${HARNESS_EXCLUDE[@]}" 2>/dev/null) || return 1
  if [ "$hfp_modo" = impronta ]; then [[ $o =~ ^[0-9a-f]{64}$ ]] || return 1
  else [[ $'\n'$o$'\n' == *$'\n.claude-plugin/plugin.json\n'* ]] || return 1; fi   # il plugin ha sempre plugin.json
  printf '%s\n' "$o"
}
hfp_py() { # $1 = elenco|impronta, $2 = radice del progetto (solo impronta) → l'uscita di HFP_PY
  # L'impronta non dipende dall'interprete della guardia: si provano FIC_PYTHON, FIC_PY, il launcher py, python3,
  # python e vale la prima uscita VALIDA (64 esadecimali; un elenco con .claude-plugin/plugin.json). Un FIC_PYTHON
  # rotto resta cosi' un problema della guardia (exit 5), non un'impronta non calcolabile (exit 6), come col calcolo
  # in bash. Niente python.sh: ne avvia due per scegliere. Nessun interprete valido: non-zero → NON-CALCOLABILE.
  local hfp_modo=$1 hfp_r hfp_p c
  hfp_win hfp_r "$MAAT_ROOT"; hfp_win hfp_p "${2:-.}"
  [ -n "${FIC_PYTHON:-}" ] && hfp_py1 "$FIC_PYTHON" && return 0
  [ -n "${FIC_PY:-}" ] && hfp_py1 "$FIC_PY" && return 0
  command -v py >/dev/null 2>&1 && hfp_py1 py -3 && return 0
  for c in python3 python; do command -v "$c" >/dev/null 2>&1 && hfp_py1 "$c" && return 0; done
  return 1
}
hfp_elenco() { # stampa i file del harness, relativi a MAAT_ROOT, in ordine LC_ALL=C · non-zero se non elencabili
  hfp_py elenco
}
harness_fp() { # $1 = radice del progetto → stampa l'impronta (64 esadecimali) · non-zero se non calcolabile
  local fp
  [ -n "$1" ] && [ -d "$1" ] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1 || return 1
  fp=$(hfp_py impronta "$1") || return 1
  [[ $fp =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s\n' "$fp"
}
hfp_stampa() { # $1 = radice del progetto → il contenuto di harness.fp, tre righe · non-zero se non calcolabile
  local fp v r
  fp=$(harness_fp "$1") || return 1
  v=$(tr -d '\r' < "$MAAT_ROOT/.claude-plugin/plugin.json" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  r=$(maat_cygm "$MAAT_ROOT" 2>/dev/null || printf '%s' "$MAAT_ROOT")
  printf 'impronta=%s\nversione=%s\nradice=%s\n' "$fp" "$v" "$r"
}
hfp_impronta_di() { # $1 = harness.fp → "nuovo <impronta>" | "precedente <impronta>" | niente (illeggibile)
  local c l
  { c=$(< "$1"); } 2>/dev/null || return 0
  c=${c//$'\r'/}
  while IFS= read -r l; do
    [[ $l =~ ^impronta=([0-9a-f]{64})$ ]] && { echo "nuovo ${BASH_REMATCH[1]}"; return 0; }
  done <<< "$c"
  [[ $c =~ ^[0-9a-f]{64}$ ]] && echo "precedente $c"   # formato precedente: una sola riga di 64 esadecimali
  return 0
}
hfp_confronta() { # $1 = harness.fp, $2 = radice del progetto → UNA riga, la decisione dei tre lettori (run-phase.sh,
  # cycle-state.sh, driver.py): UGUALE | CAMBIATO <reg:12> <att:12> | FORMATO-PRECEDENTE <reg:12> <att:12> |
  # ILLEGGIBILE <att:12> | NON-CALCOLABILE. Versione e radice sono informative: fuori dal confronto.
  local now reg
  now=$(harness_fp "$2") || { echo NON-CALCOLABILE; return 0; }
  reg=$(hfp_impronta_di "$1")
  case "$reg" in
    "nuovo $now") echo UGUALE ;;
    nuovo\ *) echo "CAMBIATO ${reg:6:12} ${now:0:12}" ;;
    precedente\ *) echo "FORMATO-PRECEDENTE ${reg:11:12} ${now:0:12}" ;;
    *) echo "ILLEGGIBILE ${now:0:12}" ;;
  esac
}
if [ "${1:-}" = "--harness-paths" ]; then
  hfp_elenco || exit 1
  echo .claude/maat.json; exit 0
fi
if [ "${1:-}" = "--harness-fp" ]; then
  [ $# -le 2 ] || { echo "uso: $0 --harness-fp [<repo>]" >&2; exit 2; }
  unset MSYS_NO_PATHCONV
  r=${2:-$PROJECT_ROOT}
  hfp_stampa "$r" || { echo "impronta del harness non calcolabile" >&2; exit 1; }
  exit 0
fi
if [ "${1:-}" = "--harness-fp-confronta" ]; then
  [ $# -ge 2 ] && [ $# -le 3 ] || { echo "uso: $0 --harness-fp-confronta <harness.fp> [<repo>]" >&2; exit 2; }
  unset MSYS_NO_PATHCONV
  hfp_confronta "$2" "${3:-$PROJECT_ROOT}"
  exit 0
fi

# --- esito strutturato: il validatore interno (vedi ESITO STRUTTURATO) e l'involucro del driver (harness-pt14) ---
# VALIDA_PY stampa la riga ESITO (o lo STOP «uscita non valida» e, sotto, originale=<riga>) e scrive result.json
# se valido. Argomenti: <log.jsonl> <schema> <fase> <result.json>. `run-phase.sh --valida …` lo esegue da solo
# (sempre questo, mai il driver): e' il termine di confronto di `driver.py equiv`.
VALIDA_PY='
import json, os, re, sys
sys.stdout.reconfigure(encoding="utf-8")
log, schema_path, phase, out = sys.argv[1:5]
res = None
for ln in open(log, encoding="utf-8", errors="replace"):
    try:
        ev = json.loads(ln)
    except ValueError:
        continue
    if isinstance(ev, dict) and ev.get("type") == "result":
        res = ev
    elif isinstance(ev, dict) and ev.get("subtype") == "fic_scartato":
        res = None   # review parallela scartata (harness-pt09): vale solo quello che segue
if res is None or res.get("is_error"):
    sys.exit(0)
text = res.get("result") or ""
lines = [l.strip() for l in text.splitlines()]
riga = next((l for l in reversed(lines) if l.startswith("ESITO FASE")), "")

KEYS = {"type", "enum", "required", "properties", "additionalProperties", "items", "minLength", "minimum"}
ANNOT = {"$schema", "$id", "title", "description"}
TYPES = {"object": lambda x: isinstance(x, dict), "array": lambda x: isinstance(x, list),
         "string": lambda x: isinstance(x, str), "null": lambda x: x is None,
         "boolean": lambda x: isinstance(x, bool),
         "integer": lambda x: isinstance(x, int) and not isinstance(x, bool),
         "number": lambda x: isinstance(x, (int, float)) and not isinstance(x, bool)}

def valida(x, s, p):
    """Validatore minimo: le sole keyword di KEYS; una keyword sconosciuta e un errore (fail-closed)."""
    extra = sorted(set(s) - KEYS - ANNOT)
    if extra:
        return ["%s: keyword non supportata dal validatore minimo: %s" % (p, ", ".join(extra))]
    if "type" in s:
        ts = s["type"] if isinstance(s["type"], list) else [s["type"]]
        if not any(TYPES.get(t, lambda v: False)(x) for t in ts):
            return ["%s: tipo atteso %s" % (p, "|".join(ts))]
    errs = []
    if "enum" in s and x not in s["enum"]:
        errs.append("%s: valore %r fuori da %s" % (p, x, s["enum"]))
    if isinstance(x, dict):
        props = s.get("properties", {})
        errs += ["%s: manca %s" % (p, r) for r in s.get("required", []) if r not in x]
        for k, v in x.items():
            if k in props:
                errs += valida(v, props[k], p + "." + k)
            elif s.get("additionalProperties") is False:
                errs.append("%s: campo non previsto %s" % (p, k))
    if isinstance(x, list) and "items" in s:
        for i, v in enumerate(x):
            errs += valida(v, s["items"], "%s[%d]" % (p, i))
    if isinstance(x, str) and len(x) < s.get("minLength", 0):
        errs.append("%s: stringa piu corta di %d" % (p, s["minLength"]))
    if TYPES["number"](x) and "minimum" in s and x < s["minimum"]:
        errs.append("%s: sotto il minimo %s" % (p, s["minimum"]))
    return errs

def blocco():
    so = res.get("structured_output")
    if isinstance(so, dict):
        return so, ""
    recinti = re.findall(r"```json[ \t]*\r?\n(.*?)\r?\n[ \t]*```", text, re.S)
    if not recinti:
        return None, "nessun blocco JSON (structured_output o recinto json)"
    try:
        return json.loads(recinti[-1]), ""
    except ValueError as e:
        return None, "blocco JSON illeggibile: %s" % e

obj, errs = blocco()
errs = [errs] if errs else []
if obj is not None:
    try:
        schema = json.load(open(schema_path, encoding="utf-8"))
    except (OSError, ValueError) as e:
        schema, errs = None, ["schema illeggibile: %s" % e]
    if schema is not None:
        try:
            import jsonschema
            errs = [e.message for e in jsonschema.validators.validator_for(schema)(schema).iter_errors(obj)]
        except ImportError:
            errs = valida(obj, schema, "$")
        if not errs and obj.get("fase") != phase:
            errs = ["fase %r diversa da quella dell etichetta (%s)" % (obj.get("fase"), phase)]
if errs:
    for e in errs:
        print("uscita non valida: " + e, file=sys.stderr)
    msg = "; ".join(errs[:3]).replace("\n", " ")
    print("ESITO FASE %s: STOP — uscita non valida: %s" % (phase, msg))
    if riga:
        print("originale=" + riga)
    sys.exit(0)
with open(out + ".tmp", "w", encoding="utf-8") as fh:
    json.dump(obj, fh, ensure_ascii=False, indent=1)
    fh.write("\n")
os.replace(out + ".tmp", out)
# Prosa e JSON discordi: vale il piu conservativo (le stesse regole di cycle-state.sh sul JSON).
one = lambda s: " ".join(str(s).split())
dev = [one(x) for x in obj["deviazioni"] if str(x).strip()]
jstop = ""
if [x for x in dev if not x.startswith("difensiva: ")]:   # tutte "difensiva: " -> nessuno STOP per deviazione
    jstop = "deviazioni dichiarate (%d): %s" % (len(dev), "; ".join(dev))
elif one(obj["bloccato_su"]).lower() != "nessuno":
    jstop = "bloccato su: " + one(obj["bloccato_su"])
elif obj["esito"] != "OK":
    jstop = "esito STOP: " + one(obj["motivo"])
jstop = jstop[:300]
if not riga:
    print("ESITO FASE %s: %s" % (obj["fase"], ("STOP — " + jstop) if jstop else ("OK — " + one(obj["motivo"]))))
elif jstop and re.match(r"ESITO FASE [^:]*: OK", riga):
    print("ESITO FASE %s: STOP — JSON: %s (la prosa diceva OK: vale il piu conservativo)" % (obj["fase"], jstop))
    print("originale=" + riga)
else:
    print(riga)
'
# INVOLUCRO (harness-pt14): `driver.py valida` al posto di VALIDA_PY solo se il certificato script/fic/driver.equiv
# porta l'hash attuale di driver.py e di QUESTO file (equivalenza provata da `driver.py equiv --certifica`);
# altrimenti il validatore interno. FIC_DRIVER=0 forza l'interno, FIC_DRIVER=1 il driver (test); FIC_DRIVER_PY e
# FIC_DRIVER_CERT sostituiscono driver e certificato (test). Driver fallito -> validatore interno, con un AVVISO.
DRV=${FIC_DRIVER_PY:-$MAAT_SCRIPTS/driver.py}
CERT=${FIC_DRIVER_CERT:-$MAAT_SCRIPTS/driver.equiv}
fic_hash() { tr -d '\r' < "$1" | sha256sum | cut -c1-64; }
driver_on() { # 0 = delega al driver
  case "${FIC_DRIVER:-}" in 0) return 1 ;; 1) [ -f "$DRV" ]; return ;; esac
  [ -f "$DRV" ] && [ -f "$CERT" ] || return 1
  local c; c=$(tr -d '\r' < "$CERT")
  grep -qx "driver $(fic_hash "$DRV")" <<< "$c" && grep -qx "run-phase $(fic_hash "${BASH_SOURCE[0]}")" <<< "$c"
}
valida() { # <log> <schema> <fase> <result.json>: stampa l'esito (vedi VALIDA_PY)
  local o
  if driver_on; then
    if o=$("$FIC_PY" "$DRV" valida "$@"); then [ -n "$o" ] && printf '%s\n' "$o"; return 0; fi
    echo "AVVISO: driver.py valida fallito: validatore interno di run-phase.sh" >&2
  fi
  "$FIC_PY" -c "$VALIDA_PY" "$@"
}
if [ "${1:-}" = "--valida" ]; then
  [ $# -eq 5 ] || { echo "uso: $0 --valida <log.jsonl> <schema> <fase> <result.json>" >&2; exit 2; }
  . "$HERE/python.sh" || { echo "nessun interprete Python utilizzabile (imposta FIC_PYTHON)" >&2; exit 5; }
  "$FIC_PY" -c "$VALIDA_PY" "$2" "$3" "$4" "$5"; exit $?
fi

# --- attribuzione per nome (vedi ALTRI FLUSSI): la sotto-sessione ha nominato questi path? ---
# NOMI_PY <radice del repo> <file dei path, uno per riga> <log.jsonl>… stampa "nominato<TAB>p" o "mai<TAB>p" per
# ogni path. Si guardano gli input di TUTTI i tool_use dei log (anche annidati, anche dei sotto-agenti): nominato =
# path relativo (anche con \), o la sola basename, in una stringa qualunque; oppure, in un `command` che scrive
# (sed -i, rm, mv, cp, find, >, tee, git checkout/restore, --fix, --write, Remove-Item…), una directory antenata
# (anche relativa a un `cd` di un'altra chiamata: una sequenza qualunque di segmenti della cartella del path), un
# punto nudo, un glob senza cartella o sotto un'antenata (idem), la radice come bersaglio (non come `cd`), o un
# comando che scrive su tutto il progetto (--fix, --write, npm run format, git checkout/restore/stash/reset…, gli
# aggiornamenti di snapshot --update, --snapshot-update, --update-snapshots, -u di vitest/jest/npx/npm). Nel dubbio
# nominato. Fail-closed: log illeggibili, nessun evento o nessun evento result -> tutti "nominato", exit 3.
# `run-phase.sh --nominati <radice> <file-dei-path> <log.jsonl>…` lo esegue da solo (test).
NOMI_PY='
import json, re, sys
sys.stdout.reconfigure(encoding="utf-8")
radice, elenco, logs = sys.argv[1], sys.argv[2], sys.argv[3:]
def norma(s):
    return re.sub(r"/+", "/", s.replace("\\", "/")).lower()
def usi(o, out):
    if isinstance(o, dict):
        if o.get("type") == "tool_use" and "input" in o:
            out.append(o["input"])
        for v in o.values():
            usi(v, out)
    elif isinstance(o, list):
        for v in o:
            usi(v, out)
def stringhe(o, k, out):
    if isinstance(o, str):
        out.append((k, o))
    elif isinstance(o, dict):
        for kk, v in o.items():
            stringhe(v, kk, out)
    elif isinstance(o, list):
        for v in o:
            stringhe(v, k, out)
try:
    paths = [l.strip() for l in open(elenco, encoding="utf-8", errors="replace").read().splitlines() if l.strip()]
except OSError:
    paths = []
eventi = risultati = 0
ins = []
try:
    for lg in logs:
        for ln in open(lg, encoding="utf-8", errors="replace"):
            try:
                ev = json.loads(ln)
            except ValueError:
                continue
            if not isinstance(ev, dict):
                continue
            eventi += 1
            risultati += ev.get("type") == "result"
            usi(ev, ins)
except OSError:
    eventi = 0
if not logs or not eventi or not risultati:
    for p in paths:
        print("nominato\t" + p)
    sys.exit(3)
testi, comandi = [], []
for i in ins:
    ss = []
    stringhe(i, "", ss)
    for k, s in ss:
        testi.append(norma(s))
        if k == "command":
            comandi.append(norma(s))
r = norma(radice).rstrip("/")
radici = {r}
for m in (re.match(r"^([a-z]):/(.*)$", r), re.match(r"^/mnt/([a-z])/(.*)$", r), re.match(r"^/([a-z])/(.*)$", r)):
    if m:
        radici |= {"%s:/%s" % m.groups(), "/%s/%s" % m.groups(), "/mnt/%s/%s" % m.groups()}
        break
INNOCUI = re.compile(r"[0-9&]*>>?\s*(/dev/null|nul)\b|[0-9]*>&[0-9-]+")
SCRIVE = re.compile(r"\bsed\b[^|;&]*\s-[a-z]*i|\bperl\b[^|;&]*\s-[a-z]*i|>|\b(rm|rmdir|mv|cp|tee|find|touch|truncate|install|ln|dd|patch|unzip|tar|rsync|del|erase|prettier)\b"
                    r"|\b(remove|move|copy|new|rename)-item\b|\b(set|add|clear)-content\b|\bout-file\b|--fix\b|--write\b|\bnpm\s+run\s+(format|fix)"
                    r"|\bgit\b[^|;&]*\s(checkout|restore|stash|reset|clean|apply|am|pull|merge|rebase|switch|mv|rm)\b")
TUTTO = re.compile(r"--fix\b|--write\b|\bnpm\s+run\s+(format|fix)|\bgit\b[^|;&]*\s(checkout|restore|stash|reset|clean|pull|merge|rebase|switch)\b"
                   r"|--update\b|--snapshot-update\b|--update-snapshots?\b|\b(vitest|jest|npx|npm|yarn|pnpm)\b[^|;&]*\s-u(?=$|[\s\"\x27;&|)])")
PUNTO = re.compile(r"(?:^|[\s\"\x27=])\.{1,2}/?\*?(?=$|[\s\"\x27;&|)])")
TOKEN = re.compile(r"[^\s\"\x27|;&<>()=]+")
def confine(t):
    return re.compile(r"(?<![a-z0-9_.-])" + re.escape(t) + r"(?![a-z0-9_-])")
def relativo(pre):
    for rr in radici:
        if pre == rr or pre.startswith(rr + "/"):
            return pre[len(rr):].lstrip("/")
    return pre
def dentro(pn, d):   # d (radice tolta, ./ e ../ in testa tolti) e una sequenza contigua di segmenti della cartella di pn
    d = re.sub(r"^(\.{1,2}(/|$))+", "", d).strip("/")
    return ("/" + pn).find("/" + d + "/") >= 0 if d else None
def nominato(p):
    pn = norma(p)
    if any(confine(pn).search(t) or confine(pn.split("/")[-1]).search(t) for t in testi):
        return True
    for c in comandi:
        c = INNOCUI.sub(" ", c)
        if not (SCRIVE.search(c) or TUTTO.search(c)):
            continue
        if TUTTO.search(c) or PUNTO.search(c):
            return True
        # ogni argomento, per INTERO: una cartella antenata (dir, dir/) o il prefisso di un glob (dir/*.py, *.md).
        # Anche RELATIVO a un cwd messo da un `cd` di un altra chiamata (il cwd persiste): basta che sia una
        # sequenza contigua di segmenti della cartella del path (cd modulo/b; poi rm -r app/servizi)
        for tok in TOKEN.findall(c):
            if "*" in tok:
                pre = tok.split("*", 1)[0]
                if dentro(pn, relativo(pre.rsplit("/", 1)[0] if "/" in pre else "")) is not False:
                    return True   # None = glob senza cartella, o sotto la radice: tutto
            elif dentro(pn, relativo(tok)):
                return True
        for rr in radici:
            for m in re.finditer(r"(?<![a-z0-9_.-])" + re.escape(rr) + r"(?=/?(?:$|[\s\"\x27;&|)]))", c):
                if not re.search(r"(?:\bcd|\bpushd|\s-c|set-location)\s+[\"\x27]?$", c[:m.start()]):
                    return True
    return False
for p in paths:
    print(("nominato\t" if nominato(p) else "mai\t") + p)
'
if [ "${1:-}" = "--nominati" ]; then
  [ $# -ge 4 ] || { echo "uso: $0 --nominati <radice> <file-dei-path> <log.jsonl>…" >&2; exit 2; }
  . "$HERE/python.sh" || { echo "nessun interprete Python utilizzabile (imposta FIC_PYTHON)" >&2; exit 5; }
  shift; "$FIC_PY" -c "$NOMI_PY" "$@"; exit $?
fi

# --- lock delle fasi di codice (anche per --lock-status) ---
# git.exe deve ricevere percorsi convertiti: con MSYS_NO_PATHCONV=1 `git -C /c/...` falliva e il lock
# risultava "libero" (misurato 2026-09-22). E se git non trova il repository, niente lock calcolabile:
# --lock-status dice "sconosciuto" (exit 1, come occupato) e nessuna fase parte. Mai fail-open.
unset MSYS_NO_PATHCONV
if [ -n "${FIC_LOCK:-}" ]; then
  LOCK=$FIC_LOCK
else
  # dalla CARTELLA DI LAVORO, non da PROJECT_ROOT (che fa vincere FIC_REPO, esportata alle fasi): in un worktree
  # collegato e' .git/worktrees/<nome>, nel tree principale .git (pk04a-1, passo 3)
  gd=$(git rev-parse --absolute-git-dir 2>/dev/null) && [ -n "$gd" ] || {
    [ "${1:-}" = "--lock-status" ] && { echo "sconosciuto: git non trova il repository del lock"; exit 1; }
    echo "git non trova il repository: lock non calcolabile, fase non lanciata" >&2; exit 2; }
  LOCK=$gd/full-implementation-cycle.lock
fi
alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
lock_alive() { # $1 = directory del lock (default: quello delle fasi di codice)
  local p c v L=${1:-$LOCK}
  if [ ! -f "$L/owner" ]; then
    # appena creato da un altro (owner non ancora scritto) → vivo; vecchio e senza owner → orfano
    [ -z "$(find "$L" -maxdepth 0 -mmin +1 2>/dev/null)" ]
    return
  fi
  p=$(sed -n 's/^pid=//p' "$L/owner"); c=$(sed -n 's/^cpid=//p' "$L/owner")
  v=$(sed -n 's/^vpid=//p' "$L/owner")   # VERIFY in background della review parallela (harness-pt09)
  local c2; c2=$(sed -n 's/^cpid2=//p' "$L/owner")   # seconda corsia dell'implement (harness-pt13)
  alive "$p" || alive "$c" || alive "$v" || alive "$c2"
}

if [ "${1:-}" = "--lock-status" ]; then
  [ $# -eq 1 ] || { echo "uso: $0 --lock-status" >&2; exit 2; }
  case "${FIC_PHASE:-}" in implement|review|fix|chiusura|test-red) echo "dentro il ciclo (fase $FIC_PHASE): il lock e' di questa fase"; exit 0 ;; esac
  if [ -d "$LOCK" ] && lock_alive; then echo "occupato: $([ -f "$LOCK/owner" ] && tr '\n' ' ' < "$LOCK/owner")"; exit 1; fi
  if [ -d "$LOCK" ]; then echo "libero (lock orfano, processi non piu' vivi: $([ -f "$LOCK/owner" ] && tr '\n' ' ' < "$LOCK/owner"))"; else echo "libero"; fi
  exit 0
fi

[ $# -eq 3 ] || { echo "uso: $0 <run-dir> <etichetta> <file-prompt> | --lock-status" >&2; exit 2; }
dir=$1 label=$2 prompt=$3
[ -f "$prompt" ] || { echo "prompt assente: $prompt" >&2; exit 2; }

# Binario: CLAUDE_BIN se impostato; poi la versione piu' recente dentro l'estensione di VS Code (il
# percorso cambia a ogni aggiornamento, quindi si cerca); poi `claude` nel PATH.
CL=${CLAUDE_BIN:-}
if [ -z "$CL" ]; then
  ext=$(ls -d "${USERPROFILE:-$HOME}"/.vscode/extensions/anthropic.claude-code-*-win32-x64 2>/dev/null | sort -V | tail -1)
  [ -n "$ext" ] && [ -f "$ext/resources/native-binary/claude.exe" ] && CL="$ext/resources/native-binary/claude.exe"
fi
[ -n "$CL" ] || CL=$(command -v claude 2>/dev/null || true)
[ -n "$CL" ] || { echo "binario claude non trovato (imposta CLAUDE_BIN)" >&2; exit 3; }

# DENY per prefisso (--disallowedTools): la genera la guardia (`guard.py --deny-list`, sezione «guardia» sotto):
# nucleo + guardia.rilascio + guardia.vietati_extra di maat.json (pk05).
DENY=()

# Primo lancio del ciclo (IMPRONTA DEL HARNESS): deciso PRIMA di scrivere qualunque file della label.
fresh=1
for f in "$dir"/log/*.running "$dir"/log/*.exit; do
  [ -f "$f" ] || continue
  case "$f" in *.running) fresh=0; break ;; esac
  case "$(tr -d '\r' < "$f" 2>/dev/null)" in 2|4|5) ;; *) fresh=0; break ;; esac
done
mkdir -p "$dir/log"
log="$dir/log/$label.jsonl" err="$dir/log/$label.stderr" ex="$dir/log/$label.exit"
finish() { echo "$1" > "$ex"; exit "$1"; }

# --- fase, dall'etichetta (sconosciuta → trattata come sola lettura) ---
case "$label" in
  *chiusura*) phase=chiusura ;;
  *test-red*) phase=test-red ;; *test-stage*) phase=test-stage ;;
  *implement*) phase=implement ;; *review*) phase=review ;; *fix*) phase=fix ;;
  *plan*) phase=plan ;; *) phase=probe ;;
esac
export FIC_PHASE=$phase

# --- attribuzione (vedi ATTRIBUZIONE) ---
tree_now() { (cd "$FIC_REPO" && bash "$RS" tree) 2>>"$err"; }
close_pre() { # $1 = file .pre-tree, $2 = sua run dir: path cambiati fra quel tree e ora → touched.txt
  local pre post
  pre=$(cat "$1") && post=$(tree_now) && [ -n "$pre" ] && [ -n "$post" ] || { echo "AVVISO: attribuzione non calcolata per $1 (niente .post-tree: cycle-state.sh fermera' il ciclo)" >> "$err"; return 0; }
  (cd "$FIC_REPO" && git -c core.quotePath=false diff --name-only --no-renames "$pre" "$post") >> "$2/touched.txt" 2>>"$err" \
    || { echo "AVVISO: git diff fallito per $1 (niente .post-tree: cycle-state.sh fermera' il ciclo)" >> "$err"; return 0; }
  sort -u -o "$2/touched.txt" "$2/touched.txt"
  echo "$post" > "${1%.pre-tree}.post-tree"
}
# --- altri flussi (vedi ALTRI FLUSSI): chi ha scritto un path cambiato durante la fase ---
nominati() { # $1 = file dei path; stampa "nominato|mai<TAB>path" (NOMI_PY) sui log della fase · != 0 = non verificabile
  local r lg=("$log") f
  r=$(maat_cygm "$FIC_REPO" 2>/dev/null || printf '%s' "$FIC_REPO")
  for f in "$dir/log/$label".corsia-[12].jsonl; do [ -f "$f" ] && lg+=("$f"); done
  "$FIC_PY" -c "$NOMI_PY" "$r" "$1" "${lg[@]}" 2>>"$err" | tr -d '\r'
  return "${PIPESTATUS[0]}"
}
avviso() { # $1 = riga di avviso: nello .stderr della label, in log/<label>.avvisi (poi in .esito) e su stderr
  printf '%s\n' "$1" | tee -a "$err" "$dir/log/$label.avvisi" >&2
}
altri_flussi() { # implement/fix, versione conservativa: i path cambiati nella fase e mai nominati RESTANO in
  # touched.txt (la review li vede), annotati in log/<label>.altri-flussi con un avviso. Nessuno STOP.
  local t0 t1 nm p c="$dir/log/$label.cambiati-fase" a="$dir/log/$label.altri-flussi"
  t0=$(cat "$pre_file" 2>/dev/null); t1=$(cat "${pre_file%.pre-tree}.post-tree" 2>/dev/null)
  [ -n "$t0" ] && [ -n "$t1" ] || return 0
  (cd "$FIC_REPO" && git -c core.quotePath=false diff --name-only --no-renames "$t0" "$t1") 2>/dev/null | tr -d '\r' | grep -v '^$' > "$c"
  [ -s "$c" ] || return 0
  if ! nm=$(nominati "$c"); then
    echo "AVVISO: attribuzione per nome non verificabile (log della fase illeggibile, senza eventi o senza result): nessuna annotazione degli altri flussi" >> "$err"
    return 0
  fi
  printf '%s\n' "$nm" | awk -F'\t' '$1 == "mai" { print $2 }' > "$a"
  [ -s "$a" ] || { rm -f "$a"; return 0; }
  while IFS= read -r p; do
    avviso "AVVISO: $p cambiato durante la fase e mai nominato dalla sotto-sessione: resta in touched.txt (la review lo vede), probabilmente di un altro flusso"
  done < "$a"
}

owned=0 cpid="" cpid2="" vpid="" held=""
# Rilascio: mai finche' la sottosessione e' viva, ne' VERIFY in background (review parallela, harness-pt09).
# Se run-phase riceve SIGTERM (TaskStop) mentre `claude` continua a scrivere codice, o mentre gates.sh e
# counterproof.sh girano, il lock resta; si potra' riprendere quando nessuno di loro vive.
release() {
  [ $owned -eq 1 ] || return 0
  alive "$cpid" && return 0
  alive "$cpid2" && return 0
  alive "$vpid" && return 0
  rm -rf "$held"; owned=0
}
# I lock si prendono PRIMA di toccare log/<label>.*: un secondo lancio con la stessa etichetta della
# fase viva (etichette sequenziali ripetute: incidente ux-6) non deve troncarne il log ne' scriverne .exit.
notes=""   # messaggi da mettere nello .stderr della label, una volta presa
busy() { # $1 = directory del lock occupato, $2 = prima riga del messaggio
  local msg o_run o_label
  msg="$2 — $([ -f "$1/owner" ] && tr '\n' ' ' < "$1/owner")
Rilancia quando ha finito. Se sei certo che nessuna fase stia girando: rm -rf \"$1\""
  echo "$msg" >&2
  o_run=$(sed -n 's/^run=//p' "$1/owner" 2>/dev/null); o_label=$(sed -n 's/^label=//p' "$1/owner" 2>/dev/null)
  # proprietario illeggibile o stessa etichetta nella stessa run dir: i file della label sono della fase viva
  if [ -z "$o_label" ] || { [ "$o_run" = "$dir" ] && [ "$o_label" = "$label" ]; }; then
    echo "stessa etichetta (o proprietario non ancora scritto): log/$label.* non toccati" >&2
    exit 4
  fi
  rm -f "$dir/log/$label.esito" "$dir/log/$label.result.json"; : > "$log"; echo "$msg" > "$err"
  finish 4
}
take_lock() { # $1 = directory del lock, $2 = messaggio se occupato; imposta orphan_run
  local L=$1 tries=0
  until mkdir "$L" 2>/dev/null; do
    if lock_alive "$L" || [ $tries -ge 3 ]; then busy "$L" "$2"; fi
    # Presa atomica dell'orfano: il mv riesce a UN solo concorrente; gli altri riprovano il mkdir.
    if mv "$L" "$L.orfano.$$" 2>/dev/null; then
      notes="$notes${notes:+
}$3 ripreso (processi non piu' vivi): $([ -f "$L.orfano.$$/owner" ] && tr '\n' ' ' < "$L.orfano.$$/owner")"
      echo "$3 ripreso (processi non piu' vivi)" >&2
      orphan_run=$(sed -n 's/^run=//p' "$L.orfano.$$/owner" 2>/dev/null)
      rm -rf "$L.orfano.$$"
    fi
    tries=$((tries + 1))
  done
  owned=1 held=$L
  trap release EXIT
  printf 'run=%s\nlabel=%s\nsince=%s\npid=%s\n' "$dir" "$label" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" > "$L/owner"
}
code_phase=0
case "$phase" in implement|review|fix|chiusura|test-red) code_phase=1 ;; esac
orphan_run=""
if [ "$phase" = plan ]; then   # lock per spec (vedi LOCK): <run-dir>/plan.lock
  take_lock "$dir/plan.lock" "lock del piano occupato: un'altra fase di piano sulla STESSA spec e' in corso" "lock del piano orfano"
  orphan_run=""   # un plan non cambia il tree: niente attribuzione da chiudere
elif [ $code_phase -eq 1 ]; then
  take_lock "$LOCK" "lock occupato: un'altra fase di codice e' in corso" "lock orfano"
fi

# --- da qui i file della label sono nostri: si azzerano (anche quelli del watcher di un lancio precedente) ---
rm -f "$ex" "$dir/log/$label.esito" "$log.result" "$log.pos" "$log.pending" "$dir/log/$label.gates" "$dir/log/$label.prompt" \
  "$dir/log/$label.result.json" "$dir/log/$label.finalize" "$dir/log/$label.parallelo" "$dir/log/$label.counterproof" \
  "$dir/log/$label.spec-pre" "$dir/log/$label.gates.scartato" "$dir/log/$label.counterproof.scartato" \
  "$dir/log/$label.corsie" "$dir/log/$label.cambiati" "$dir/log/$label.posteriori" "$dir/log/$label".corsia-* \
  "$dir/log/$label.cambiati-fase" "$dir/log/$label.altri-flussi" "$dir/log/$label.avvisi" "$dir/log/$label.touched-pre"
: > "$log"
printf '%s' "${notes:+$notes
}" > "$err"

# FIC_REPO gia' impostata vince (serve ai test, con un repo temporaneo).
FIC_REPO=$PROJECT_ROOT   # = FIC_REPO se impostata, altrimenti il toplevel git della cartella di lavoro
[ -n "$FIC_REPO" ] || { echo "non e' un repository git" >> "$err"; finish 2; }
export FIC_REPO
PC="$MAAT_SCRIPTS/plan-check.sh"
SPEC_F="${dir%.run}.md"
TR="$dir/test-red"
if [ "$phase" = test-red ] || [ "$phase" = test-stage ]; then   # harness-pt11: solo formato 2
  { [ -f "$SPEC_F" ] && bash "$PC" contract "$SPEC_F" 2>/dev/null | tr -d '\r' | grep -qx 'Plan format: 2'; } ||
    { echo "fase $phase: solo per un piano in formato 2 (Plan format: 2) nella spec accanto alla run dir ($SPEC_F): non lanciata" | tee -a "$err" >&2; finish 2; }
fi

# --- impronta del harness: registrata al primo lancio, controllata a ogni fase successiva ---
hfp_file="$dir/harness.fp"
if [ -f "$hfp_file" ]; then
  hfp_c=$(hfp_confronta "$hfp_file" "$FIC_REPO")
  if [ "$hfp_c" != UGUALE ]; then
    read -r hfp_esito hfp_a hfp_b <<< "$hfp_c"
    hfp_since=$(date -u -r "$hfp_file" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    hfp_root=$(maat_cygm "$MAAT_ROOT" 2>/dev/null || printf '%s' "$MAAT_ROOT")
    hfp_rimedio="bash \"$(maat_cygm "$MAAT_SCRIPTS/run-phase.sh" 2>/dev/null || printf '%s' "$MAAT_SCRIPTS/run-phase.sh")\" --harness-fp > \"$hfp_file\""
    case "$hfp_esito" in
      CAMBIATO) hfp_msg="STOP: harness cambiato dal $hfp_since: ricomincia la fase o conferma (impronta registrata $hfp_a, attuale $hfp_b; file del plugin in $hfp_root e .claude/maat.json). Rimedio: se il cambio e' voluto, registra l'impronta attuale — $hfp_rimedio — e rilancia; altrimenti riporta il harness com'era" ;;
      FORMATO-PRECEDENTE) hfp_msg="STOP: impronta di formato precedente: ciclo iniziato col harness interno (impronta registrata $hfp_a dal $hfp_since, attuale $hfp_b). Rimedio: se il passaggio al plugin e' voluto, registra l'impronta attuale — $hfp_rimedio — e rilancia; altrimenti riprendi il ciclo col harness interno" ;;
      ILLEGGIBILE) hfp_msg="STOP: harness.fp illeggibile (vuoto o senza impronta, registrato dal $hfp_since; attuale $hfp_a). Rimedio: se il harness attuale e' quello voluto, registra l'impronta attuale — $hfp_rimedio — e rilancia" ;;
      *) hfp_msg="STOP: impronta del harness non calcolabile (file del plugin in $hfp_root o .claude/maat.json di $FIC_REPO non leggibili, oppure repository non trovato; registrata dal $hfp_since), fase non lanciata" ;;
    esac
    echo "$hfp_msg" | tee -a "$err" >&2
    finish 6
  fi
elif [ $fresh -eq 1 ]; then
  if hfp_now=$(hfp_stampa "$FIC_REPO"); then printf '%s\n' "$hfp_now" > "$hfp_file"
  else echo "AVVISO: impronta del harness non calcolata: questo ciclo non sara' controllato" >> "$err"; fi
fi

# La fase uccisa era di un'ALTRA feature: il suo .pre-tree si chiude ora, prima che questa fase
# cambi il tree, altrimenti il lavoro di questa finirebbe nel touched.txt di quella.
if [ -n "$orphan_run" ] && [ "$orphan_run" != "$dir" ] && [ -d "$orphan_run/log" ]; then
  for f in "$orphan_run"/log/*.pre-tree; do
    [ -f "$f" ] && [ ! -f "${f%.pre-tree}.post-tree" ] && close_pre "$f" "$orphan_run"
  done
fi

# --- guardia: un solo comando, per l'autotest e per l'hook ---
. "$HERE/python.sh" || { echo "guardia non attiva: nessun interprete Python utilizzabile (imposta FIC_PYTHON)" | tee -a "$err" >&2; finish 5; }
GUARD="$MAAT_SCRIPTS/guard.py"
HOOK_CMD="\"$FIC_PY\" \"$GUARD\""
# maat.json del progetto per le due guardie (questa e quella del plugin) e per l'autotest: MAAT_CONFIG a percorso
# assoluto. Senza file non si esporta: la guardia cade comunque nel ripiego «maat.json non trovato».
if [ -z "${MAAT_CONFIG:-}" ] && [ -n "${PROJECT_ROOT:-}" ] && [ -f "$PROJECT_ROOT/.claude/maat.json" ]; then
  MAAT_CONFIG=$PROJECT_ROOT/.claude/maat.json
fi
if [ -n "${MAAT_CONFIG:-}" ]; then
  # Relativo reso assoluto in bash, come plan-check.sh: fuori da Windows maat_cygm -a non c'e' e il relativo restava tale.
  case $MAAT_CONFIG in
    /*|[A-Za-z]:[/\\]*) ;;
    *) # forma Windows anche senza cygpath (pwd -W); cartella non raggiungibile -> relativo alla cartella corrente
       if _d=$(cd "$(dirname "$MAAT_CONFIG")" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); then
         MAAT_CONFIG=$_d/$(basename "$MAAT_CONFIG")
       else MAAT_CONFIG=$PWD/$MAAT_CONFIG; fi; unset _d ;;
  esac
  MAAT_CONFIG=$(maat_cygm "$MAAT_CONFIG" 2>/dev/null || printf '%s' "$MAAT_CONFIG")
  export MAAT_CONFIG
fi
# sonda: l'uscita di `maat-config.py sonda-produzione` (anche con exit 3, il ripiego del nucleo); senza maat.json
# leggibile il comando del nucleo. Deve uscire 2, altrimenti exit 5.
probe_cmd=$(PROJECT_ROOT=${PROJECT_ROOT:-} "$FIC_PY" "$MAAT_SCRIPTS/maat-config.py" sonda-produzione 2>/dev/null | tr -d '\r' | head -1)
[ -n "$probe_cmd" ] || probe_cmd="git push --force origin x"
probe_esc=${probe_cmd//\\/\\\\}; probe_esc=${probe_esc//\"/\\\"}
probe='{"tool_name":"Bash","tool_input":{"command":"'"$probe_esc"'"}}'
printf '%s' "$probe" | eval "$HOOK_CMD" >/dev/null 2>&1
if [ $? -ne 2 ]; then
  echo "guardia non attiva: l'autotest non ha negato la sonda «$probe_cmd» ($HOOK_CMD)" | tee -a "$err" >&2
  finish 5
fi
mapfile -t DENY < <("$FIC_PY" "$GUARD" --deny-list 2>/dev/null | tr -d '\r')
if [ ${#DENY[@]} -eq 0 ]; then
  echo "guardia non attiva: lista DENY vuota ($HOOK_CMD --deny-list)" | tee -a "$err" >&2
  finish 5
fi
# Hook Stop (harness-pt04, 1g): nega la fine turno senza `ESITO FASE` o con job in background non
# raccolti; stop_hook_active contro il loop. Fallisce aperto (lascia chiudere): e' la direzione sicura.
STOP_PY="$MAAT_SCRIPTS/stop-hook.py"
STOP_CMD=""
if [ -f "$STOP_PY" ]; then STOP_CMD="\"$FIC_PY\" \"$(cd "$(dirname "$STOP_PY")" && { pwd -W 2>/dev/null || pwd; })/stop-hook.py\""
else echo "AVVISO: hook Stop assente ($STOP_PY): la sotto-sessione parte senza" >> "$err"; fi
SETTINGS=$("$FIC_PY" -c 'import json, sys
h = {"PreToolUse": [{"matcher": "Bash|Edit|Write|NotebookEdit|MultiEdit", "hooks": [{"type": "command", "command": sys.argv[1]}]}]}
if sys.argv[2]:
    h["Stop"] = [{"hooks": [{"type": "command", "command": sys.argv[2]}]}]
print(json.dumps({"hooks": h}))' "$HOOK_CMD" "$STOP_CMD")

# --- gate eseguiti dal driver (harness-pt04, 1d): fuori dalla sotto-sessione, evidenza in evidence/ ---
# Dopo ogni implement/fix finita OK e prima di ogni review: script/fic/gates.sh col livello in vigore e i
# file di touched.txt; l'esito in log/<label>.gates. La review riceve nel prompt la cartella dell'evidenza.
GATES=${FIC_GATES:-$MAAT_SCRIPTS/gates.sh}
gates_level() { # --tests=<l> nel prompt, poi la riga Test level: del piano (plan-check.sh contract), poi legacy
  local l
  [ "$phase" = chiusura ] && { echo full; return; }   # chiusura di una catena: sempre full
  l=$(tr -d '\r' < "$prompt" | grep -o -- '--tests=[a-z]*' | head -1 | cut -d= -f2)
  [ -z "$l" ] && [ -f "${dir%.run}.md" ] &&
    l=$(bash "$MAAT_SCRIPTS/plan-check.sh" contract "${dir%.run}.md" 2>/dev/null | tr -d '\r' | sed -n 's/^Test level: \([a-z]*\).*/\1/p' | head -1)
  case $l in min|std|full) echo "$l" ;; *) echo legacy ;; esac
}
run_gates() { # stampa la cartella dell'evidenza (niente se i gate non sono partiti)
  local g="$dir/log/$label.gates" lvl rc files=()
  if [ ! -f "$dir/touched.txt" ]; then echo "gates: non eseguiti (nessun touched.txt): i gate restano alla fase" > "$g"; return 0; fi
  if [ ! -f "$GATES" ]; then echo "gates: non eseguiti (gates.sh assente: $GATES)" > "$g"; return 0; fi
  lvl=$(gates_level)
  mapfile -t files < <(tr -d '\r' < "$dir/touched.txt" | grep -v '^$')
  FIC_GATES_ROOT="$FIC_REPO" bash "$GATES" --run-dir "$dir" "$lvl" ${files[@]+"${files[@]}"} > "$g" 2>&1; rc=$?
  echo "exit=$rc livello=$lvl" >> "$g"
  sed -n 's/^gates: esito=.* evidence=\(.\{2,\}\)$/\1/p' "$g" | tail -1
}

# --- review ∥ VERIFY (harness-pt09): vedi REVIEW IN PARALLELO CON LA VERIFICA in testa ---
MUT="$dir/counterproof/mutations.json"
CP_SH=${FIC_COUNTERPROOF:-$MAAT_SCRIPTS/counterproof.sh}
cp_driver=0
wslp() { local w; w=$(maat_cygm "$1" 2>/dev/null || printf '%s' "$1")
  case $w in [A-Za-z]:/*) printf '/mnt/%s%s' "$(printf '%s' "${w:0:1}" | tr 'A-Z' 'a-z')" "${w:2}" ;; *) printf '%s' "$w" ;; esac; }
sq() { local s=${1//\'/\'\\\'\'}; printf "'%s'" "$s"; }
review_status() { # Review status: registrato nella sezione di review della spec (vuoto se non c'e')
  [ -f "${dir%.run}.md" ] || return 0
  tr -d '\r' < "${dir%.run}.md" | sed -n '/^## Review implementazione/,$ s/^Review status: *//p' | head -1
}
verify_key() { # chiave del tree: review-surface.sh tree + (controprove del driver) sha256 di mutations.json
  local t; t=$(tree_now) && [ -n "$t" ] || return 1
  if [ $cp_driver -eq 1 ]; then printf '%s mutations=%s\n' "$t" "$([ -f "$MUT" ] && sha256sum < "$MUT" | cut -c1-64)"
  else printf '%s\n' "$t"; fi
}
cp_ids() { "$FIC_PY" -c 'import json, sys
try:
    l = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    l = []
for e in l if isinstance(l, list) else []:
    i = e.get("id") if isinstance(e, dict) else None
    if isinstance(i, str) and i.strip() and "/" not in i and "\\" not in i and not i.startswith("."):
        print(i)' "$MUT" 2>/dev/null | tr -d '\r'; }
cp_clear() { local i; while IFS= read -r i; do [ -n "$i" ] && rm -f "$dir/counterproof/$i.json"; done < <(cp_ids); }
PC_SH=${FIC_PLAN_CHECK:-$MAAT_SCRIPTS/plan-check.sh}
cp_from_gen() { # 0 = mutations.json e' quello che `plan-check.sh gen` (pt10) genera ORA dal piano approvato:
  # <run>/gen/procedura.txt con l'"Impronta piano:" attuale e la lista identica a una rigenerata qui, in una
  # cartella a parte (gen non scrive un marcatore). Formato 1, lista scritta da un worker, piano cambiato: 1.
  local spec="${dir%.run}.md" t="$dir/log/.gen-verifica.$$" fr fn rc=1
  [ -s "$MUT" ] && [ -f "$dir/gen/procedura.txt" ] && [ -f "$spec" ] && [ -f "$PC_SH" ] || return 1
  rm -rf "$t"; mkdir -p "$t" || return 1
  if bash "$PC_SH" gen "$spec" --run-dir "$t" >/dev/null 2>&1 && [ -f "$t/gen/procedura.txt" ] && [ -f "$t/counterproof/mutations.json" ]; then
    fr=$(tr -d '\r' < "$dir/gen/procedura.txt" | sed -n 's/^Impronta piano: *//p' | head -1)
    fn=$(tr -d '\r' < "$t/gen/procedura.txt" | sed -n 's/^Impronta piano: *//p' | head -1)
    [ -n "$fn" ] && [ "$fr" = "$fn" ] && cmp -s <(tr -d '\r' < "$MUT") <(tr -d '\r' < "$t/counterproof/mutations.json") && rc=0
  fi
  rm -rf "$t"; return $rc
}
# Le controprove girano dentro WSL SOLO su Windows (uname/OSTYPE, mai la presenza di wsl.exe) e con un modulo delle
# mutazioni `ambiente: wsl` in maat.json (il modulo di file e test, come lo instrada il lettore importato); altrimenti
# counterproof.sh gira diretto: su Linux, o su Windows senza moduli wsl, wsl.exe non serve (e puo' mancare).
CP_WSL_PY='
import importlib.util, json, os, sys
import sys; sys.dont_write_bytecode = True   # nessun __pycache__ sotto MAAT_ROOT
spec = importlib.util.spec_from_file_location("maat_config", os.environ["MAAT_CONFIG_PY"])
mc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mc)
try:
    cfg, _p = mc.carica()
except mc.Uscita:
    sys.exit(0)
r = mc.risolto(cfg)
amb = {m["nome"]: m.get("ambiente", "nativo") for m in r["moduli"]}
for e in json.load(open(sys.argv[1], encoding="utf-8")):
    if not isinstance(e, dict):
        continue
    for p in (e.get("file"), (e.get("test") or {}).get("percorso")):
        d = mc.instrada(r, p) if isinstance(p, str) and p else None
        if d is not None and amb.get(d[0]) == "wsl":
            print("wsl")
            sys.exit(0)
'
cp_in_wsl() { # 0 = counterproof.sh va lanciato dentro WSL
  case "${OSTYPE:-}:$(uname -s 2>/dev/null)" in *msys*|*cygwin*|*:MINGW*|*:MSYS*|*:CYGWIN*) ;; *) return 1 ;; esac
  PROJECT_ROOT=$FIC_REPO MAAT_CONFIG_PY="$MAAT_SCRIPTS/maat-config.py" "$FIC_PY" -c "$CP_WSL_PY" "$MUT" 2>/dev/null |
    tr -d '\r' | grep -qx wsl
}
run_cp() { # controprove del driver: counterproof.sh (pt05) su mutations.json; esito in log/<label>.counterproof
  local c="$dir/log/$label.counterproof" rc env_w
  cp_clear   # nessun risultato di un giro precedente sopravvive a questo
  if [ -n "${FIC_CP_CMD:-}" ]; then "$FIC_CP_CMD" "$MUT" > "$c" 2>&1; rc=$?
  elif [ ! -f "$CP_SH" ]; then echo "counterproof.sh assente: $CP_SH" > "$c"; rc=127
  elif cp_in_wsl; then
    # radice del progetto e maat.json tradotti per WSL: counterproof.sh non li ricava dalla propria posizione
    env_w="PROJECT_ROOT=$(sq "$(wslp "$FIC_REPO")")"
    [ -n "${MAAT_CONFIG:-}" ] && env_w+=" MAAT_CONFIG=$(sq "$(wslp "$MAAT_CONFIG")")"
    MSYS_NO_PATHCONV=1 wsl -- bash -lc "$env_w bash $(sq "$(wslp "$CP_SH")") $(sq "$(wslp "$MUT")")" > "$c" 2>&1; rc=$?
  else PROJECT_ROOT=$FIC_REPO bash "$CP_SH" "$MUT" > "$c" 2>&1; rc=$?; fi
  echo "exit=$rc" >> "$c"
  # 3 = BLOCKED d'ambiente: i risultati di quel run non valgono anche se esistono (e cosi' ogni uscita fuori da 0/1/2)
  case $rc in 0|1|2) ;; *) cp_clear ;; esac
}
launch() { # $1 = file di stdin, $2 = ">" o ">>" sul log; imposta code
  if [ "$2" = ">>" ]; then
    CLAUDE_PLUGIN_ROOT=$MAAT_ROOT "$CL" -p --permission-mode bypassPermissions --disallowedTools "${DENY[@]}" --settings "$SETTINGS" --strict-mcp-config \
      ${SCHEMA_ARGS[@]+"${SCHEMA_ARGS[@]}"} ${PLUGIN_ARGS[@]+"${PLUGIN_ARGS[@]}"} --append-system-prompt "$CHILD_RULES_TXT" \
      --output-format stream-json --verbose < "$1" >> "$log" 2>> "$err" &
  else
    CLAUDE_PLUGIN_ROOT=$MAAT_ROOT "$CL" -p --permission-mode bypassPermissions --disallowedTools "${DENY[@]}" --settings "$SETTINGS" --strict-mcp-config \
      ${SCHEMA_ARGS[@]+"${SCHEMA_ARGS[@]}"} ${PLUGIN_ARGS[@]+"${PLUGIN_ARGS[@]}"} --append-system-prompt "$CHILD_RULES_TXT" \
      --output-format stream-json --verbose < "$1" > "$log" 2>> "$err" &
  fi
  cpid=$!
  if [ $owned -eq 1 ]; then sed -i '/^cpid=/d' "$held/owner" 2>/dev/null; echo "cpid=$cpid" >> "$held/owner"; fi
  wait $cpid
  code=$?
}

# --- catena (harness-pt12, vedi CATENE): all'avvio di un anello, prima di misurare il suo .pre-tree ---
is_ring() { # la spec di questa run dir e' elencata nella riga Figlie: di una madre della stessa cartella?
  [ -f "${dir%.run}.md" ] && grep -ls '^Figlie:' "$(dirname "$dir")"/spec-*.md 2>/dev/null | xargs -r grep -lF -- "$(basename "${dir%.run}")" >/dev/null 2>&1
}
if [ "$phase" = implement ] && ! ls "$dir/log" 2>/dev/null | grep -q '\.pre-tree$' && is_ring; then
  cn=$(bash "$HERE/cycle-state.sh" "${dir%.run}.md" 2>>"$err" | tr -d '\r' | sed -n 's/^Next: //p')
  case "$cn" in "STOP — catena"*|"WAIT — catena"*) echo "$cn — fase non lanciata" | tee -a "$err" >&2; finish 7 ;; esac
fi
# chiusura di una catena: prepara la run dir della MADRE (touched.txt, base.txt) e trova gli e2e delle figlie
chz_fail="" chz_e2e=""
chiusura_prep() {
  local m="${dir%.run}.md" d c first="" b kids
  d=$(dirname "$m")
  [ -f "$m" ] || { chz_fail="spec madre assente: $m"; return; }
  kids=$(tr -d '\r' < "$m" | awk '{ isf = ($0 ~ /^[ \t]*(```|~~~)/) } isf { inf = !inf; next } inf { next }
    /^## (Piano di implementazione|Review implementazione)/ { exit } /^Figlie:/ { print; exit }' | grep -o 'spec-[A-Za-z0-9._-]*' | sed 's/\.md$//; s/\.$//')
  [ -n "$kids" ] || { chz_fail="la madre non ha la riga Figlie:"; return; }
  : > "$dir/touched.txt.chiusura"
  for c in $kids; do
    [ -n "$first" ] || first=$c
    [ -f "$d/$c.run/touched.txt" ] || chz_fail="${chz_fail:+$chz_fail; }$c senza touched.txt"
    [ -f "$d/$c.run/touched.txt" ] && tr -d '\r' < "$d/$c.run/touched.txt" >> "$dir/touched.txt.chiusura"
    chz_e2e="$chz_e2e $([ -f "$d/$c.md" ] && tr -d '\r' < "$d/$c.md" | sed -n 's/^[[:space:]]*\([-*]\|[0-9][0-9]*\.\)[[:space:]]\{1,\}\[e2e-locator:[[:space:]]*\([^]]*\)\].*/\2/p' | sed 's/[[:space:]]*$//' | tr '\n' ' ')"
  done
  grep . "$dir/touched.txt.chiusura" | sort -u > "$dir/touched.txt"; rm -f "$dir/touched.txt.chiusura"
  [ -s "$dir/touched.txt" ] || chz_fail="${chz_fail:+$chz_fail; }nessun file nei touched.txt degli anelli"
  b=$([ -f "$d/$first.run/base.txt" ] && tr -d '\r\n ' < "$d/$first.run/base.txt")
  if [ -n "$b" ]; then echo "$b" > "$dir/base.txt"; else chz_fail="${chz_fail:+$chz_fail; }base del primo anello assente ($first.run/base.txt)"; fi
  chz_e2e=$(printf '%s\n' $chz_e2e | grep . | sort -u | tr '\n' ' ' | sed 's/ $//')
}

# --- verifica del driver per test-red (harness-pt11, vedi FASE TEST-RED): stampa l'esito finale della fase ---
verify_red() { # $1 = esito della sotto-sessione (riga ESITO, ev. originale=)
  local e1 g="$dir/log/$label.gates" ro="$dir/log/$label.rossi" ev rc files=() why=""
  e1=$(printf '%s\n' "$1" | sed -n 1p)
  printf '%s\n' "$e1" | grep -q '^ESITO FASE [^:]*: OK' || { printf '%s\n' "$1"; return 0; }
  # scritture della fase fuori dal suo scope (anche via Bash, che la guardia non vede): tree prima e dopo
  local t0 t1 fuori c="$dir/log/$label.cambiati-fase" a="$dir/log/$label.altri-flussi" nm="" nrc=0 p
  t0=$(cat "$dir/log/$label.pre-tree" 2>/dev/null); t1=$(cat "$dir/log/$label.post-tree" 2>/dev/null)
  if [ -z "$t0" ] || [ -z "$t1" ]; then why="attribuzione non misurata (.pre-tree/.post-tree): scope della fase non verificabile"
  else
    (cd "$FIC_REPO" && git -c core.quotePath=false diff --name-only --no-renames "$t0" "$t1") 2>/dev/null | tr -d '\r' |
      grep -vxF -f "$dir/log/$label.scope" | grep -v '^$' > "$c"   # SCOPE-DOPO-LA-FASE
    # ALTRI FLUSSI: un path fuori scope che la sotto-sessione non ha mai nominato e' di un altro flusso
    : > "$a"
    if [ -s "$c" ]; then
      nm=$(nominati "$c"); nrc=$?
      [ $nrc -eq 0 ] && printf '%s\n' "$nm" | awk -F'\t' '$1 == "mai" { print $2 }' > "$a"
    fi
    fuori=$(grep -vxF -f "$a" "$c" | head -5 | paste -sd, -)
    if [ -n "$fuori" ]; then
      why="scritture fuori dallo scope di test-red (test del piano e file nuovi): $fuori"
      [ $nrc -ne 0 ] && why="$why (attribuzione per nome non verificabile: log della fase illeggibile, senza eventi o senza result)"
    fi
    if [ -s "$a" ]; then
      # gia' in touched.txt prima della fase (lavoro della feature): non puo' stare anche in do-not-touch -> STOP,
      # resta in touched.txt. touched-pre assente: tutti trattati cosi' (fail-closed)
      local tp="$dir/log/$label.touched-pre" feat nuovi
      if [ -f "$tp" ]; then feat=$(grep -xF -f "$tp" "$a"); nuovi=$(grep -vxF -f "$tp" "$a")
      else feat=$(cat "$a"); nuovi=""; fi
      if [ -n "$feat" ]; then
        why="${why:+$why; }file della feature (gia' in touched.txt prima di test-red) cambiato durante la fase da un altro flusso (mai nominato dalla sotto-sessione): $(printf '%s\n' "$feat" | head -5 | paste -sd, -) — resta in touched.txt, non va in do-not-touch: decidi tu (lavoro tuo da tenere o da riportare com'era)"
      fi
      if [ -n "$nuovi" ]; then   # in do-not-touch.txt (forma del preflight), fuori da touched.txt (ci e' entrato ora)
        { [ -f "$dir/do-not-touch.txt" ] && tr -d '\r' < "$dir/do-not-touch.txt"; printf '%s\n' "$nuovi"; } | sed '/^[[:space:]]*$/d' | sort -u > "$dir/do-not-touch.txt.nuovo" &&
          mv -f "$dir/do-not-touch.txt.nuovo" "$dir/do-not-touch.txt"
        if [ -f "$dir/touched.txt" ]; then
          tr -d '\r' < "$dir/touched.txt" | grep -vxF -f <(printf '%s\n' "$nuovi") > "$dir/touched.txt.nuovo"
          mv -f "$dir/touched.txt.nuovo" "$dir/touched.txt"
        fi
        while IFS= read -r p; do
          avviso "AVVISO: $p cambiato durante la fase da un altro flusso (mai nominato dalla sotto-sessione): non attribuito, in do-not-touch"
        done <<< "$nuovi"
      fi
    else rm -f "$a"; fi
  fi
  mapfile -t files < <({ bash "$PC" accept "$SPEC_F" 2>/dev/null | tr -d '\r' | sed -n 's/^test //p'
                         [ -f "$dir/touched.txt" ] && tr -d '\r' < "$dir/touched.txt"; } | grep -v '^$' | LC_ALL=C sort -u)
  if [ -n "$why" ]; then :
  elif [ ! -f "$GATES" ]; then why="verifica dei rossi non eseguita (gates.sh assente: $GATES)"
  else
    FIC_GATES_ROOT="$FIC_REPO" bash "$GATES" --run-dir "$dir" std ${files[@]+"${files[@]}"} > "$g" 2>&1; rc=$?
    echo "exit=$rc livello=std (test-red: i test di accettazione devono essere rossi)" >> "$g"
    ev=$(sed -n 's/^gates: esito=.* evidence=\(.\{2,\}\)$/\1/p' "$g" | tail -1)
    if [ -z "$ev" ] || [ "$ev" = - ]; then why="verifica dei rossi non eseguita (gates.sh exit $rc senza evidenza: log/$label.gates)"
    else
      bash "$PC" rossi "$SPEC_F" --evidence "$ev" --run-dir "$dir" > "$ro" 2>&1; rc=$?
      case $rc in
        0) ;;
        1) why=$(tr -d '\r' < "$ro" | sed -n 's/^rossi: esito=STOP — //p' | tail -1)
           why="test di accettazione ${why:-non dimostrati} (log/$label.rossi)" ;;
        *) why="verifica dei rossi BLOCKED: $(tr -d '\r' < "$ro" | sed -n 's/^rossi: esito=[A-Z]* — //p' | tail -1) (log/$label.rossi)" ;;
      esac
    fi
  fi
  if [ -z "$why" ]; then   # chiusura OK: stub, impronta dei test (anche nella basis), controprove assorbite (L2)
    mkdir -p "$TR"; rm -f "$TR/tests.red.txt"   # base delle modifiche prescritte (tests_guard): quella di QUESTA test-red
    { bash "$PC" stubs "$SPEC_F" --run-dir "$dir" && bash "$PC" tests "$SPEC_F" | tr -d '\r' > "$TR/tests.txt" &&
      bash "$PC" basis "$SPEC_F" --write-tests && bash "$PC" gen "$SPEC_F" --run-dir "$dir"; } >> "$ro" 2>&1 ||
      why="chiusura di test-red non registrata (stub, impronta dei test o gen: log/$label.rossi)"
  fi
  if [ -z "$why" ]; then printf '%s\n' "$1"
  else printf 'ESITO FASE test-red: STOP — %s\noriginale=%s\n' "$why" "$e1"; fi
}
# --- dopo implement/fix: i test di accettazione sono quelli di test-red (harness-pt11) ---
# MODIFICA PRESCRITTA (caso tipico: un passo del piano cambia un aiutante in un file che contiene anche un test di
# accettazione). Un file dei test di accettazione cambiato e' una manomissione SOLO se nessun
# blocco del piano lo ha in scrive: (procedura rigenerata ORA da `plan-check.sh gen` in una cartella a parte, come
# lanes_decide). Se e' prescritto, le funzioni dei test di accettazione (file+nome di test-red/rossi.json, scritto
# da `plan-check.sh rossi`) devono restare identiche a test-red: base = il blob del file nel .post-tree di una fase
# test-red, accettato solo se il suo sha256 (senza CR) e' quello registrato a test-red (test-red/tests.red.txt se
# l'impronta e' gia' stata riregistrata, altrimenti tests.txt). Confronto: Python, ast.dump del nodo (Classe::metodo,
# parametri [..] tolti; decoratori e docstring compresi, commenti e formattazione no). Funzione cambiata o sparita
# -> STOP come prima. Non verificabile (non Python, nessun nome, base non trovata o diversa, rossi.json assente)
# -> nessuno STOP ma un AVVISO in .esito, che la review vede. Limite: un aiutante (fixture, _make_*) cambiato
# cambia il comportamento del test anche a funzione identica: l'AVVISO lo nomina sempre, decide la review.
# Modifica prescritta accettata -> l'impronta si riregistra coi comandi di test-red (`plan-check.sh tests` in
# tests.txt, `basis --write-tests`), cosi' cycle-state.sh (STALE (tests)) e finalize.sh (l2: Tests status FRESH)
# vedono la stessa impronta; non registrabile (approvazione STALE) -> STOP.
TG_PY='import ast, hashlib, json, os, re, subprocess, sys
sys.stdout.reconfigure(encoding="utf-8")
root, procedura, base_txt, rossi, cambiati = sys.argv[1:6]
trees = sys.argv[6:]
scrive = {}
for l in open(procedura, encoding="utf-8"):
    m = re.match(r"^blocco ([^:]+): scrive=(.*) · dopo=", l.rstrip("\n"))
    if m:
        for f in m.group(2).split(","):
            scrive.setdefault(f.strip(), []).append(m.group(1))
base = {}
for l in open(base_txt, encoding="utf-8"):
    p = l.rstrip("\r\n").split("  ", 1)
    if len(p) == 2:
        base[p[1]] = p[0]
nomi = None
try:
    d = json.load(open(rossi, encoding="utf-8"))
    nomi = {}
    for t in (d.get("test") or {}).values():
        if isinstance(t, dict) and t.get("file"):
            nomi.setdefault(t["file"], []).append(t.get("nome") or "")
except (OSError, ValueError, AttributeError):
    pass
def blob(tree, p):
    r = subprocess.run(["git", "-C", root, "cat-file", "blob", "%s:%s" % (tree, p)], capture_output=True)
    return r.stdout.replace(b"\r", b"") if r.returncode == 0 else None
def nodo(albero, nome):
    corpo = albero.body
    trovato = None
    for seg in re.sub(r"\[.*\]$", "", nome).split("::"):
        trovato = None
        for n in corpo:
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and n.name == seg:
                trovato = n   # come Python: l ultima definizione vince
        if trovato is None:
            return None
        corpo = getattr(trovato, "body", [])
    return trovato
for p in [x.strip() for x in open(cambiati, encoding="utf-8") if x.strip()]:
    if p not in scrive:
        print("fuori\t" + p); continue
    bl = ",".join(scrive[p])
    def nv(why):
        print("nonverificabile\t%s\t%s\t%s" % (p, bl, why))
    if not p.endswith(".py"):
        nv("solo Python (ast)"); continue
    if nomi is None:
        nv("test-red/rossi.json assente o illeggibile"); continue
    ns = nomi.get(p, [])
    if not ns or not all(ns):
        nv("nessun nome di test di accettazione per il file in rossi.json"); continue
    vecchio = next((b for b in (blob(t, p) for t in trees) if b is not None and hashlib.sha256(b).hexdigest() == base.get(p)), None)
    if vecchio is None:
        nv("contenuto di test-red non ritrovato (nessun .post-tree di test-red col suo sha256)"); continue
    try:
        av = ast.parse(vecchio.decode("utf-8"))
    except (SyntaxError, UnicodeDecodeError, ValueError):
        nv("file di test-red non analizzabile"); continue
    try:
        with open(os.path.join(root, p), "rb") as fh:
            an = ast.parse(fh.read().replace(b"\r", b"").decode("utf-8"))
    except (OSError, SyntaxError, UnicodeDecodeError, ValueError):
        print("cambiato\t%s\t(file attuale assente o non analizzabile)" % p); continue
    diversi, nonvisti = [], []
    for n in ns:
        o, c = nodo(av, n), nodo(an, n)
        if o is None:
            nonvisti.append(n)
        elif c is None or ast.dump(o) != ast.dump(c):
            diversi.append(n)
    if diversi:
        print("cambiato\t%s\t%s" % (p, ", ".join(diversi)))
    elif nonvisti:
        nv("funzioni non trovate nel file di test-red: " + ", ".join(nonvisti))
    else:
        print("ok\t%s\t%s\t%s" % (p, bl, ", ".join(ns)))'
tests_guard() { # $1 = esito; stampa l'esito, STOP se un file dei test di accettazione e' cambiato (MODIFICA PRESCRITTA sopra)
  local e1 now ch t="$dir/log/.gen-tests.$$" out fuori camb trees=() f bt
  [ -f "$TR/tests.txt" ] && [ -f "$SPEC_F" ] || { printf '%s\n' "$1"; return 0; }
  now=$(bash "$PC" tests "$SPEC_F" 2>/dev/null | tr -d '\r')
  [ "$now" = "$(tr -d '\r' < "$TR/tests.txt")" ] && { printf '%s\n' "$1"; return 0; }   # CONFRONTO-TEST-ACCETTAZIONE
  e1=$(printf '%s\n' "$1" | sed -n 1p)
  ch=$(diff <(tr -d '\r' < "$TR/tests.txt") <(printf '%s\n' "$now") | sed -n 's/^[<>] [0-9A-Za-z]*  //p' | LC_ALL=C sort -u)
  # solo per un esito OK: uno STOP resta tale, e nessuna impronta si riregistra
  if printf '%s\n' "$e1" | grep -q '^ESITO FASE [^:]*: OK' && [ -n "$ch" ]; then
    bt="$TR/tests.red.txt"; [ -f "$bt" ] || bt="$TR/tests.txt"
    while IFS= read -r f; do [ -n "$f" ] && trees+=("$(tr -d '\r' < "$f")"); done < <(ls "$dir"/log/*test-red.post-tree 2>/dev/null | LC_ALL=C sort -r)
    rm -rf "$t"; mkdir -p "$t" && printf '%s\n' "$ch" > "$t/cambiati"
    if bash "$PC" gen "$SPEC_F" --run-dir "$t" >/dev/null 2>&1 && [ -f "$t/gen/procedura.txt" ]; then
      out=$("$FIC_PY" -c "$TG_PY" "$FIC_REPO" "$t/gen/procedura.txt" "$bt" "$TR/rossi.json" "$t/cambiati" ${trees[@]+"${trees[@]}"} 2>>"$err" | tr -d '\r') || out=""
    else out=""; fi
    rm -rf "$t"
    fuori=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "fuori" { print $2 }' | paste -sd, -)
    camb=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "cambiato" { print $2 " (" $3 ")" }' | paste -sd, -)
    # ogni file cambiato ha una riga ok/nonverificabile (nessun fuori, nessun cambiato, nessuno mancante)
    if [ -n "$out" ] && [ -z "$fuori" ] && [ -z "$camb" ] &&
       [ "$(printf '%s\n' "$out" | awk -F'\t' '$1 == "ok" || $1 == "nonverificabile" { print $2 }' | LC_ALL=C sort -u)" = "$ch" ]; then
      [ -f "$TR/tests.red.txt" ] || cp "$TR/tests.txt" "$TR/tests.red.txt"   # la base di test-red resta quella
      if bash "$PC" tests "$SPEC_F" 2>>"$err" | tr -d '\r' > "$TR/tests.txt.nuovo" && mv -f "$TR/tests.txt.nuovo" "$TR/tests.txt" &&
         bash "$PC" basis "$SPEC_F" --write-tests >> "$err" 2>&1; then
        printf '%s\n' "$out" | while IFS=$'\t' read -r k p b x; do
          case $k in
            ok) avviso "AVVISO: test di accettazione: $p cambiato, modifica prescritta dal piano (scrive: di $b); funzioni dei test di accettazione invariate da test-red ($x) — il resto del file (aiutanti, fixture) e' cambiato: la review lo controlli; impronta dei test riregistrata" ;;
            nonverificabile) avviso "AVVISO: test di accettazione: $p cambiato, modifica prescritta dal piano (scrive: di $b); funzioni dei test di accettazione NON verificate ($x): la review controlli che i test di accettazione siano quelli di test-red; impronta dei test riregistrata" ;;
          esac
        done
        printf '%s\n' "$1"; return 0
      fi
      printf "ESITO FASE %s: STOP — modifica prescritta di test di accettazione (%s), ma impronta dei test non riregistrata (plan-check.sh tests/basis --write-tests: vedi log/%s.stderr)\noriginale=%s\n" "$phase" "$(printf '%s\n' "$ch" | paste -sd, -)" "$label" "$e1"
      return 0
    fi
    if [ -n "$camb" ]; then
      printf "ESITO FASE %s: STOP — deviazione: test di accettazione modificati dopo test-red (%s); correggerli e' una decisione umana\noriginale=%s\n" "$phase" "$camb" "$e1"
      return 0
    fi
  fi
  printf "ESITO FASE %s: STOP — deviazione: test di accettazione modificati dopo test-red (%s); correggerli e' una decisione umana\noriginale=%s\n" "$phase" "$(printf '%s\n' "$ch" | paste -sd, - | sed 's/^$/?/')" "$e1"
}

# --- corsie (harness-pt13): vedi CORSIE in testa ---
BI=${FIC_BLOCKS_INDEPENDENT:-$MAAT_SCRIPTS/blocks-independent.py}
lanes_decide() { # scrive log/<label>.corsie · 0 = due corsie, altrimenti serie (col motivo nel file)
  local spec="${dir%.run}.md" t="$dir/log/.gen-corsie.$$" c="$dir/log/$label.corsie" rc=1
  if [ "${FIC_LANES:-1}" = 0 ]; then echo "blocks-independent: esito=serie motivo=FIC_LANES=0" > "$c"; return 1; fi
  if [ -z "$pre_file" ]; then echo "blocks-independent: esito=serie motivo=tree iniziale non calcolato (niente controllo a posteriori)" > "$c"; return 1; fi
  if [ -n "${FIC_CORSIE:-}" ] && [ -f "$FIC_CORSIE" ]; then   # harness-pt14: decisa dal driver (stessi comandi)
    tr -d '\r' < "$FIC_CORSIE" > "$c"
    grep -qx 'blocks-independent: esito=parallelo corsie=2' "$c"; return
  fi
  if [ ! -f "$spec" ] || [ ! -f "$PC_SH" ] || [ ! -f "$BI" ]; then echo "blocks-independent: esito=serie motivo=spec, plan-check.sh o blocks-independent.py assenti" > "$c"; return 1; fi
  rm -rf "$t"; mkdir -p "$t" || return 1
  if bash "$PC_SH" gen "$spec" --run-dir "$t" >/dev/null 2>&1 && [ -f "$t/gen/procedura.txt" ]; then
    PROJECT_ROOT=$FIC_REPO "$FIC_PY" "$BI" --root "$FIC_REPO" "$t/gen/procedura.txt" 2>>"$err" | tr -d '\r' > "$c"; rc=${PIPESTATUS[0]}
    [ $rc -le 1 ] || echo "blocks-independent: esito=serie motivo=blocks-independent.py fallito (exit $rc)" > "$c"
  else
    echo "blocks-independent: esito=serie motivo=plan-check.sh gen non riuscito (formato 1 o piano malformato)" > "$c"
  fi
  rm -rf "$t"
  [ $rc -eq 0 ] && grep -qx 'blocks-independent: esito=parallelo corsie=2' "$c"
}
# Esito delle corsie: `estrai <log> <out>` scrive i file dichiarati (campo "file" del JSON) della corsia;
# `unisci <log1> <log2> <posteriori> <exit1> <exit2>` (un'uscita != 0 e' STOP «corsia k: uscita N») stampa UN evento result con l'ESITO e il JSON uniti (la validazione con lo
# schema resta quella di sempre, sull'ultimo evento result di <label>.jsonl). Il piu' conservativo vince.
LANE_PY='import json, re, sys
sys.stdout.reconfigure(encoding="utf-8")
def ultimo(log):
    res = None
    try:
        for ln in open(log, encoding="utf-8", errors="replace"):
            try:
                ev = json.loads(ln)
            except ValueError:
                continue
            if isinstance(ev, dict) and ev.get("type") == "result":
                res = ev
    except OSError:
        pass
    return None if res is None or res.get("is_error") else res
def blocco(res):
    so = res.get("structured_output")
    if isinstance(so, dict):
        return so
    rec = re.findall(r"```json[ \t]*\r?\n(.*?)\r?\n[ \t]*```", res.get("result") or "", re.S)
    try:
        return json.loads(rec[-1]) if rec else None
    except ValueError:
        return None
LISTE = ("deviazioni", "file", "gate_interni", "finding")
def forma(o):
    return (isinstance(o, dict) and all(isinstance(o.get(f), list) for f in LISTE)
            and all(isinstance(o.get(f), str) for f in ("esito", "motivo", "bloccato_su")))
def riga(res, o):
    # Con --json-schema il campo result porta spesso il SOLO JSON, senza la riga di testo: allora la riga si ricava
    # dall oggetto strutturato (gia passato da forma), come VALIDA_PY in serie. Riga di testo presente: vale lei,
    # e se contraddice l oggetto vince lo STOP (testo STOP qui sotto; oggetto STOP via m["esito"] e VALIDA_PY).
    l = next((l.strip() for l in reversed((res.get("result") or "").splitlines()) if l.strip().startswith("ESITO FASE")), "")
    if l or not forma(o):
        return l
    return "ESITO FASE implement: %s — %s" % ("OK" if o["esito"] == "OK" else "STOP", " ".join(o["motivo"].split()) or "-")
if sys.argv[1] == "estrai":
    r = ultimo(sys.argv[2]); o = blocco(r) if r else None
    with open(sys.argv[3], "w", encoding="utf-8", newline="\n") as fh:
        for f in (o.get("file") if forma(o) else []):
            fh.write(str(f).replace("\\", "/") + "\n")
    sys.exit(0)
logs, post = sys.argv[2:4], open(sys.argv[4], encoding="utf-8", errors="replace").read().strip()
codici = sys.argv[5:7]
stop = "" if post.startswith("posteriori: esito=OK") else "controllo a posteriori delle corsie: " + (post.split("— ", 1)[-1] if post else "non eseguito")
prob, objs, righe = [], [], []
for k, log in enumerate(logs, 1):
    r = ultimo(log)
    o = blocco(r) if r else None
    if len(codici) >= k and codici[k - 1] != "0":
        prob.append("corsia %d: uscita %s" % (k, codici[k - 1]))
    elif r is None:
        prob.append("corsia %d: nessun evento result" % k)
    elif not forma(o):
        prob.append("corsia %d: esito strutturato assente o non valido" % k)
    else:
        objs.append((k, o)); righe.append((k, riga(r, o)))
if prob:
    print(json.dumps({"type": "result", "result": "ESITO FASE implement: STOP — " + "; ".join(prob + ([stop] if stop else []))}))
    sys.exit(0)
def dev_corsia(k, d):   # "difensiva: " resta in testa (DEVIAZIONI DIFENSIVE): "difensiva: corsia k: …"
    s = " ".join(str(d).split())
    return "difensiva: corsia %d: %s" % (k, s[len("difensiva: "):]) if s.startswith("difensiva: ") else "corsia %d: %s" % (k, d)
m = {"fase": "implement", "esito": "OK", "motivo": " · ".join("corsia %d: %s" % (k, o["motivo"]) for k, o in objs),
     "deviazioni": [dev_corsia(k, d) for k, o in objs for d in o["deviazioni"]], "bloccato_su": "nessuno",
     "file": [], "gate_interni": [g for k, o in objs for g in o["gate_interni"]], "finding": [f for k, o in objs for f in o["finding"]]}
for k, o in objs:
    m["file"] += [f for f in o["file"] if f not in m["file"]]
    if o["esito"] != "OK":
        m["esito"] = "STOP"
    if " ".join(o["bloccato_su"].split()).lower() != "nessuno" and m["bloccato_su"] == "nessuno":
        m["bloccato_su"] = "corsia %d: %s" % (k, o["bloccato_su"])
    if isinstance(o.get("fase"), str) and o["fase"] != "implement":
        m["fase"] = o["fase"]   # la validazione di sempre lo rifiuta: fase diversa da quella dell etichetta
    if isinstance(o.get("copertura"), list):
        m.setdefault("copertura", []).extend(o["copertura"])
if stop:
    m["esito"] = "STOP"
    m["bloccato_su"] = stop if m["bloccato_su"] == "nessuno" else m["bloccato_su"] + "; " + stop
ko = [(k, l) for k, l in righe if not re.match(r"ESITO FASE implement: OK", l)]
if stop:
    testo = "ESITO FASE implement: STOP — " + stop
elif ko:
    testo = "ESITO FASE implement: STOP — corsia %d: %s" % (ko[0][0], re.sub(r"^ESITO FASE [^:]*:\s*(STOP\s*—\s*)?", "", ko[0][1]) or "nessuna riga ESITO")
else:
    testo = "ESITO FASE implement: OK — corsie parallele: " + m["motivo"]
print(json.dumps({"type": "result", "subtype": "fic_corsie", "result": testo, "structured_output": m}, ensure_ascii=False))'
launch_lanes() { # due sotto-sessioni insieme (una per corsia), poi controllo a posteriori ed evento result unito
  local k b s o p c="$dir/log/$label.corsie" c1 c2 pids=() pre post lf=()
  echo '{"type":"system","subtype":"fic_corsie"}' > "$log"
  rm -f "$dir"/{do-not-touch,mixed}.[12].txt   # una corsia morta prima del preflight non unisce le liste di un giro precedente
  for k in 1 2; do
    b=$(sed -n "s/^corsia $k: //p" "$c"); s=$(sed -n "s/^scope $k: //p" "$c"); o=$(sed -n "s/^corsia $((3 - k)): //p" "$c")
    p="$dir/log/$label.corsia-$k.prompt"; lf+=("$dir/log/$label.corsia-$k.jsonl")
    { cat "$prompt"; printf '\n%s\n' "CORSIA $k/2 (driver, run-phase.sh): sono tuoi SOLO i blocchi $b del piano, nel loro ordine di dopo:; i tuoi file sono quelli del loro scrive: ($s). L'altra corsia implementa ORA, in parallelo, i blocchi $o: i suoi file sono do-not-touch, e la guardia nega Edit/Write fuori dai tuoi (FIC_WRITE_SCOPE). base.txt lo scrive solo la corsia 1; le liste del preflight vanno in do-not-touch.$k.txt e mixed.$k.txt. Le suite del livello le esegue il driver sull'albero intero a corsie finite: tieni solo il ciclo interno mirato. Nel JSON, in file, SOLO i file che hai scritto tu."; } > "$p"
    FIC_LANE=$k FIC_WRITE_SCOPE=$s WSLENV="FIC_LANE${WSLENV:+:$WSLENV}" \
      CLAUDE_PLUGIN_ROOT=$MAAT_ROOT "$CL" -p --permission-mode bypassPermissions --disallowedTools "${DENY[@]}" --settings "$SETTINGS" --strict-mcp-config \
      ${SCHEMA_ARGS[@]+"${SCHEMA_ARGS[@]}"} ${PLUGIN_ARGS[@]+"${PLUGIN_ARGS[@]}"} --append-system-prompt "$CHILD_RULES_TXT" \
      --output-format stream-json --verbose < "$p" > "${lf[$((k - 1))]}" 2>> "$err" &
    pids+=($!)
  done
  cpid=${pids[0]} cpid2=${pids[1]}
  if [ $owned -eq 1 ]; then sed -i '/^cpid2\{0,1\}=/d' "$held/owner" 2>/dev/null; printf 'cpid=%s\ncpid2=%s\n' "$cpid" "$cpid2" >> "$held/owner"; fi
  wait "$cpid"; c1=$?
  wait "$cpid2"; c2=$?
  code=$c1; [ "$code" -eq 0 ] && code=$c2
  # liste del preflight delle corsie (do-not-touch.<k>.txt, mixed.<k>.txt) -> le liste lette dalle fasi successive
  for k in do-not-touch mixed; do
    if [ -f "$dir/$k.1.txt" ] || [ -f "$dir/$k.2.txt" ]; then
      cat "$dir/$k.1.txt" "$dir/$k.2.txt" 2>/dev/null | tr -d '\r' | sed '/^[[:space:]]*$/d' | sort -u > "$dir/$k.txt"
    fi
  done
  # controllo a posteriori: il diff del tree durante le corsie, diviso per scope
  pre=$(cat "$pre_file" 2>/dev/null); post=$(tree_now)
  if [ -n "$pre" ] && [ -n "$post" ] && (cd "$FIC_REPO" && git -c core.quotePath=false diff --name-only --no-renames "$pre" "$post") > "$dir/log/$label.cambiati" 2>>"$err"; then
    for k in 1 2; do "$FIC_PY" -c "$LANE_PY" estrai "${lf[$((k - 1))]}" "$dir/log/$label.corsia-$k.file" 2>>"$err"; done
    "$FIC_PY" "$BI" --posteriori "$c" "$dir/log/$label.cambiati" "$dir/log/$label.corsia-1.file" "$dir/log/$label.corsia-2.file" 2>>"$err" | tr -d '\r' > "$dir/log/$label.posteriori"
  else
    echo "posteriori: esito=STOP — diff del tree non calcolabile" > "$dir/log/$label.posteriori"
  fi
  "$FIC_PY" -c "$LANE_PY" unisci "${lf[0]}" "${lf[1]}" "$dir/log/$label.posteriori" "$c1" "$c2" 2>>"$err" | tr -d '\r' >> "$log"
}

# --- attribuzione: path cambiati dalle fasi implement/fix, chiusura delle fasi uccise ---
if [ $code_phase -eq 1 ]; then
  for f in "$dir"/log/*.pre-tree; do
    [ -f "$f" ] && [ ! -f "${f%.pre-tree}.post-tree" ] && close_pre "$f" "$dir"
  done
fi
pre_file=""
if [ "$phase" = implement ] || [ "$phase" = fix ] || [ "$phase" = test-red ]; then
  pre_file="$dir/log/$label.pre-tree"
  rm -f "$pre_file" "$dir/log/$label.post-tree"
  t=$(tree_now) && [ -n "$t" ] && echo "$t" > "$pre_file" || { echo "AVVISO: tree iniziale non calcolato per $label (niente .post-tree: cycle-state.sh fermera' il ciclo)" >> "$err"; pre_file=""; }
fi

# --- fasi test-red / test-stage (harness-pt11): scope di scrittura della guardia, test in sosta (S3) ---
staged=0
if [ "$phase" = test-red ] || [ "$phase" = test-stage ]; then
  scope="$dir/log/$label.scope"
  plan_fp=$(bash "$PC" basis "$SPEC_F" 2>/dev/null | tr -d '\r' | sed -n 's/^Basis: .*plan \([0-9a-f]*\).*/\1/p')
  if [ "$phase" = test-red ]; then
    bash "$PC" accept "$SPEC_F" 2>>"$err" | tr -d '\r' | sed -n 's/^\(test\|nuovo\) //p' > "$scope"
  else   # test-stage: la sola <run-dir>/staging/, legata all'impronta del piano candidato
    mkdir -p "$dir/staging"
    sa=$(cd "$dir" && pwd); sa=$(maat_cygm "$sa" 2>/dev/null || printf '%s' "$sa")
    sr=$(maat_cygm "$FIC_REPO" 2>/dev/null || printf '%s' "$FIC_REPO")
    printf '%s/staging/\n' "${sa#"$sr"/}" > "$scope"
    echo "$plan_fp" > "$dir/staging.fp"
  fi
  FIC_SCOPE=$(maat_cygm "$scope" 2>/dev/null || printf '%s' "$scope"); export FIC_SCOPE
  if [ "$phase" = test-red ] && { [ -d "$dir/staging" ] || [ -f "$dir/staging.fp" ]; }; then
    sfp=$([ -f "$dir/staging.fp" ] && tr -d '\r\n' < "$dir/staging.fp")
    if [ -n "$sfp" ] && [ "$sfp" = "$plan_fp" ] && [ -d "$dir/staging" ]; then   # CONFRONTO-IMPRONTA-STAGING
      nst=0
      while IFS= read -r f; do
        r=${f#"$dir/staging/"}
        if grep -qxF -- "$r" "$scope"; then
          mkdir -p "$FIC_REPO/$(dirname "$r")" && cp "$f" "$FIC_REPO/$r" && nst=$((nst + 1))
        else echo "AVVISO: S3: $r fuori dallo scope di test-red, non copiato" >> "$err"; fi
      done < <(find "$dir/staging" -type f | LC_ALL=C sort)
      rm -rf "$dir/staging.copiato"; mv "$dir/staging" "$dir/staging.copiato"; rm -f "$dir/staging.fp"
      [ $nst -gt 0 ] && staged=1
      echo "S3: $nst file in sosta copiati dallo staging (impronta del piano $sfp)" >> "$err"
    else
      rm -rf "$dir/staging" "$dir/staging.fp"
      echo "S3: staging scartato (impronta ${sfp:-assente}, piano attuale ${plan_fp:-non calcolabile})" >> "$err"
    fi
  fi
fi

date -u +%Y-%m-%dT%H:%M:%SZ > "$dir/log/$label.running"

stdin_file=$prompt
# Review di un anello k>1 (harness-pt12, M1): la superficie la costruisce il driver, non il revisore. Diff dalla
# "Base anello" (.post-tree di k-1, da cycle-state.sh) al tree attuale, sui soli file del touched.txt di QUESTO
# anello: un file toccato anche da k-1 mostra solo gli hunk di k. File e indice in coda al prompt (che diventa
# log/<label>.prompt-anello: review ∥ VERIFY e sequenza lo usano come prompt di partenza). Base assente o diff non
# riuscito → exit 7, la review non parte (mai una review dell'anello sul diff da HEAD). Ricostruito prima di un
# rilancio in sequenza dopo uno scarto (harness-pt09), cosi' il diff e' sempre dell'albero rivisto.
# DEVIAZIONI DIFENSIVE: la review riceve l'elenco da giudicare in coda al prompt di partenza (anche dell'anello).
if [ "$phase" = review ] && [ -s "$dir/log/deviazioni-difensive.txt" ]; then
  { cat "$prompt"; printf '\n%s\n' "DEVIAZIONI DIFENSIVE (driver, run-phase.sh): $dir/log/deviazioni-difensive.txt — deviazioni dal piano dichiarate «difensiva: » da implement/fix, che non hanno fermato il ciclo (etichetta, testo). Passale a implementation-review-cycle da giudicare: se una di queste deviazioni non e' puramente difensiva (cambia un comportamento osservabile, un contratto API, una stringa visibile prevista, i permessi o i dati scritti nei casi previsti dal piano), e' un finding major."; tr -d '\r' < "$dir/log/deviazioni-difensive.txt"; } > "$dir/log/$label.prompt-difensive"
  prompt="$dir/log/$label.prompt-difensive" stdin_file="$dir/log/$label.prompt-difensive"
fi
ring_stop() { echo "$1" | tee -a "$err" >&2; rm -f "$dir/log/$label.running"; finish 7; }
ring=0 prompt0=$prompt
ring_prompt() {
  local rd="$dir/log/$label.anello.diff" rt ridx
  { [ -f "$dir/touched.txt" ] && tr -d '\r' < "$dir/touched.txt"; } | grep . > "$dir/log/$label.anello.paths"
  if [ -s "$dir/log/$label.anello.paths" ] && rt=$(tree_now) && [ -n "$rt" ] \
     && ridx=$(cd "$FIC_REPO" && bash "$RS" diff --from "$rb" --to "$rt" --paths-file "$dir/log/$label.anello.paths" --out "$rd" 2>>"$err"); then
    { cat "$prompt0"; printf '\n%s\n%s\n' "DIFF DELL'ANELLO (driver, run-phase.sh): $rd — base anello $rb (il .post-tree dell'anello precedente, mai HEAD) → tree $rt, solo i file del touched.txt di questo anello. E' la superficie della review: passala a implementation-review-cycle; indice (path, offset, limit):" "$ridx"; } > "$dir/log/$label.prompt-anello"
    prompt="$dir/log/$label.prompt-anello" stdin_file="$dir/log/$label.prompt-anello"
  else
    ring_stop "STOP — catena: diff dell'anello non calcolato (base $rb, touched.txt ${dir}/touched.txt): la review non parte"
  fi
}
if [ "$phase" = review ] && is_ring; then
  cso=$(bash "$HERE/cycle-state.sh" "${dir%.run}.md" 2>>"$err" | tr -d '\r')
  rk=$(printf '%s\n' "$cso" | sed -n 's/^Catena: anello \([0-9][0-9]*\)\/.*/\1/p' | head -1)
  rb=$(printf '%s\n' "$cso" | sed -n 's/^Base anello: \([0-9a-f]\{40\}\)$/\1/p')
  if [ "${rk:-1}" -le 1 ]; then :   # anello 1: la sua base e' quella di sempre
  elif [ -n "$rb" ]; then ring=1; ring_prompt
  else
    ring_stop "STOP — catena: nessuna Base anello da cycle-state.sh (l'anello precedente non ha un .post-tree?): la review dell'anello $rk non parte"
  fi
fi
code=0 skip_cl=0 chz_ev="" esito=""
if [ "$phase" = chiusura ]; then   # gate full sull'albero finale; la sotto-sessione solo per gli e2e delle figlie
  chiusura_prep
  [ -z "$chz_fail" ] && chz_ev=$(run_gates)
  if [ -z "$chz_fail" ] && [ -n "$chz_e2e" ] && grep -q '^exit=0 ' "$dir/log/$label.gates" 2>/dev/null; then
    stdin_file="$dir/log/$label.prompt"
    { cat "$prompt"; printf '\n%s\n' "E2E DELLA CATENA: $chz_e2e"; } > "$stdin_file"
  else
    skip_cl=1
  fi
fi

# --- esito strutturato (harness-pt08): lo schema passa per contenuto, compatto ---
SCHEMA=${FIC_SCHEMA:-$MAAT_SCHEMAS/phase-result.schema.json}
SCHEMA_ARGS=()
if [ "$phase" = chiusura ]; then :   # la chiusura non e' nello schema dell'esito: conta la sua riga ESITO
elif [ -f "$SCHEMA" ] && sc=$("$FIC_PY" -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1], encoding="utf-8")), separators=(",", ":")))' "$SCHEMA" 2>>"$err" | tr -d '\r') && [ -n "$sc" ]; then
  SCHEMA_ARGS=(--json-schema "$sc")
else
  echo "AVVISO: schema dell'esito assente o illeggibile ($SCHEMA): la fase chiudera' con STOP «uscita non valida»" >> "$err"
fi
# --plugin-dir solo come override esplicito (MAAT_PLUGIN_DIR; il rigioco la imposta sempre): di norma la sotto-sessione
# trova il plugin perche' e' abilitato nel progetto (pk01 D1; D8: con il plugin anche abilitato non duplica nulla)
PLUGIN_ARGS=()
[ -n "${MAAT_PLUGIN_DIR:-}" ] && PLUGIN_ARGS=(--plugin-dir "$MAAT_PLUGIN_DIR")
CHILD_RULES="$MAAT_SKILLS/full-implementation-cycle/child-rules.md"
# Claude Code sostituisce ${CLAUDE_PLUGIN_ROOT} solo nei testi di SKILL.md e degli agenti: nel testo passato con
# --append-system-prompt la sostituzione la fa qui, deterministica, con MAAT_ROOT (e la sotto-sessione riceve
# CLAUDE_PLUGIN_ROOT=$MAAT_ROOT nell'ambiente, vedi launch)
CHILD_RULES_TXT=$(cat "$CHILD_RULES" 2>>"$err")
CHILD_RULES_TXT=${CHILD_RULES_TXT//'${CLAUDE_PLUGIN_ROOT}'/$MAAT_ROOT}

lanes=0   # corsie (harness-pt13): solo implement, solo con blocchi indipendenti calcolati
[ "$phase" = implement ] && lanes_decide && lanes=1
mode="" why="" par="$dir/log/$label.parallelo"
if [ "$phase" = review ]; then
  mode=sequenza
  rs_now=$(review_status)
  if [ "${FIC_REVIEW_PARALLEL:-1}" = 0 ]; then why="FIC_REVIEW_PARALLEL=0"
  elif [ "${rs_now%% *}" = APPROVED ]; then why="review registrata APPROVED: promozione o gate-only (il reviewer puo' non partire) o giro post-approvazione"
  else
    # controprove del driver SOLO su una lista di plan-check.sh gen coerente col piano (decisione dell'orchestratore):
    # una lista scritta dal worker a un giro precedente resta del worker, che la riscrive a ogni giro
    ! ls "$dir"/counterproof/*.meta >/dev/null 2>&1 && cp_from_gen && cp_driver=1
    if k0=$(verify_key) && [ -n "$k0" ]; then mode=parallelo; else why="chiave del tree non calcolabile"; cp_driver=0; fi
  fi
fi
if [ "$mode" = parallelo ]; then
  # VERIFY (gates.sh, poi counterproof.sh solo se la lista e' quella di plan-check.sh gen, coerente col piano:
  # cp_from_gen) e la review partono INSIEME, sulla stessa chiave.
  cpw=worker; [ $cp_driver -eq 1 ] && cpw=driver
  printf 'modo=parallelo controprove=%s chiave=%s\n' "$cpw" "$(printf '%s' "$k0" | sha256sum | cut -c1-12)" > "$par"
  [ -f "${dir%.run}.md" ] && cp "${dir%.run}.md" "$dir/log/$label.spec-pre"
  stdin_file="$dir/log/$label.prompt"
  if [ $cp_driver -eq 1 ]; then cpn="le controprove di counterproof/mutations.json (generata da plan-check.sh gen, coerente col piano) le esegue il DRIVER ora (non riscrivere mutations.json, non lanciare counterproof.sh: i risultati saranno counterproof/<id>.json)"
  else cpn="le controprove restano tue, come sempre (Worker review, passo 2: scrivi o rigenera counterproof/mutations.json e lancia counterproof.sh)"; fi
  { cat "$prompt"; printf '\n%s\n' "VERIFY IN PARALLELO (driver, run-phase.sh): gates.sh gira ORA, fuori da questa sessione, sui file di touched.txt; $cpn. Non aspettare e non eseguire le suite del livello, non citarne i risultati: per ogni requisito scrivi nel campo copertura del JSON gli ID dei test che lo coprono. Il verdetto e' provvisorio (Verification: VERIFIED (provvisorio: …)): finalize.sh fa l'AND con i risultati e compone la tabella Evidence."; } > "$stdin_file"
  ( run_gates >/dev/null; [ $cp_driver -eq 1 ] && run_cp ) & vpid=$!
  [ $owned -eq 1 ] && echo "vpid=$vpid" >> "$held/owner"   # lock_alive: VERIFY vivo tiene il lock
  launch "$stdin_file" ">"
  wait $vpid
  k1=$(verify_key) || k1=""   # ricalcolo finale della chiave (harness-pt09)
  if [ "$k1" != "$k0" ]; then
    # tree (o mutations.json) cambiato mentre review e VERIFY giravano: nessuno dei due risultati e' di un albero solo
    msg="scartato: chiave cambiata durante la fase ($(printf '%s' "$k0" | sha256sum | cut -c1-12) -> $(printf '%s' "$k1" | sha256sum | cut -c1-12)): review e VERIFY rilanciate in sequenza"
    echo "$msg" >> "$par"; echo "AVVISO: $msg" >> "$err"
    [ -f "$dir/log/$label.spec-pre" ] && cp "$dir/log/$label.spec-pre" "${dir%.run}.md"
    # l'evidenza della finestra parallela non deve restare riusabile (gates.sh a chiave identica) ne' FRESH per
    # finalize.sh: la sua cartella diventa <chiave>.scartato (--verify la vede STALE, gates.sh non la trova)
    evd=$(sed -n 's/^gates: esito=.* evidence=\(.\{2,\}\)$/\1/p' "$dir/log/$label.gates" 2>/dev/null | tail -1)
    if [ -n "$evd" ] && [ "$evd" != - ] && [ -d "$evd" ]; then rm -rf "$evd.scartato"; mv -f "$evd" "$evd.scartato"; fi
    [ -f "$dir/log/$label.gates" ] && mv -f "$dir/log/$label.gates" "$dir/log/$label.gates.scartato"
    [ -f "$dir/log/$label.counterproof" ] && mv -f "$dir/log/$label.counterproof" "$dir/log/$label.counterproof.scartato"
    cp_clear   # anche in modo worker: i <id>.json del giro scartato non valgono
    [ $owned -eq 1 ] && sed -i '/^vpid=/d' "$held/owner" 2>/dev/null
    # il log resta uno (il Monitor lo segue): un evento marca lo scarto, l'esito si legge solo dopo di esso
    echo '{"type":"system","subtype":"fic_scartato"}' >> "$log"
    mode=sequenza why="chiave cambiata durante la fase parallela" relaunch=1
  fi
fi
if [ "$mode" = sequenza ]; then   # la sequenza di prima: gate, poi la review con l'evidenza nel prompt
  echo "modo=sequenza — ${why:-sequenza}" >> "$par"
  [ "${relaunch:-0}" = 1 ] && [ $ring -eq 1 ] && ring_prompt   # diff dell'anello sull'albero del rilancio
  stdin_file=$prompt
  ev=$(run_gates)   # a chiave identica e' un riuso, non un rilancio
  if [ -n "$ev" ] && [ "$ev" != - ]; then
    stdin_file="$dir/log/$label.prompt"
    { cat "$prompt"; printf '\n%s\n' "EVIDENZE DEI GATE (driver, run-phase.sh): $ev — $(grep '^gates: esito=' "$dir/log/$label.gates" | tail -1 | sed 's/ chiave=.*//'). Passale a implementation-review-cycle come contesto (Step 2.5, evidenza del driver)."; } > "$stdin_file"
  fi
  launch "$stdin_file" "$([ "${relaunch:-0}" = 1 ] && echo '>>' || echo '>')"
elif [ $staged -eq 1 ]; then   # S3 (harness-pt11): i test in sosta sono nel tree, niente sotto-sessione; la verifica e' sotto
  printf '%s\n' '{"type":"result","result":"ESITO FASE test-red: OK — test in sosta (S3) copiati dallo staging","structured_output":{"fase":"test-red","esito":"OK","motivo":"test in sosta (S3) copiati dallo staging","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}' > "$log"
  code=0
elif [ $lanes -eq 1 ]; then   # corsie (harness-pt13): solo implement, dopo S3 e prima del lancio singolo
  launch_lanes
elif [ "$phase" != review ] && [ $skip_cl -eq 0 ]; then   # la chiusura senza e2e (o coi gate rossi) non lancia la sotto-sessione
  launch "$stdin_file" ">"
fi

if [ -n "$pre_file" ]; then
  # test-red (ALTRI FLUSSI): touched.txt prima di questa fase, per togliere solo cio' che ci entra ora
  # (pk09: touched.txt assente alla prima fase di codice — controllato prima: il redirect di input `<` si valuta
  # prima di `2>/dev/null`, e l'errore «No such file» usciva comunque nello stderr della fase)
  [ "$phase" = test-red ] && { [ -f "$dir/touched.txt" ] && tr -d '\r' < "$dir/touched.txt"; true; } > "$dir/log/$label.touched-pre"
  close_pre "$pre_file" "$dir"
  case "$phase" in implement|fix) altri_flussi ;; esac
fi
# DEVIAZIONI DIFENSIVE (vedi in testa). DIFENSIVE_PY estrai <result.json>: le deviazioni, una per riga, solo se
# TUTTE cominciano con "difensiva: " (altrimenti niente: la fase e' gia' STOP). DIFENSIVE_PY nota <spec> <label>
# <file>: "- nota (deviazione difensiva, <label>): <testo>" dopo l'ultima riga del "### Changelog revisione piano"
# (stesse zone di plan-check.sh annotate, fuori recinti; righe gia' presenti saltate, fine riga conservato); exit 3
# se il piano non ha un changelog.
DIFENSIVE_PY='
import json, re, sys
sys.stdout.reconfigure(encoding="utf-8")
one = lambda s: " ".join(str(s).split())
if sys.argv[1] == "estrai":
    dev = [one(x) for x in json.load(open(sys.argv[2], encoding="utf-8")).get("deviazioni") or [] if str(x).strip()]
    if dev and all(x.startswith("difensiva: ") for x in dev):
        print("\n".join(dev))
    sys.exit(0)
spec, label, elenco = sys.argv[2:5]
raw = open(spec, "rb").read().decode("utf-8")
nl = "\r\n" if "\r\n" in raw else "\n"
righe = raw.replace("\r\n", "\n").split("\n")
zona, fence, ultima = "above", False, -1
for i, l in enumerate(righe):
    isf = re.match(r"^[ \t]*(```|~~~)", l) is not None
    if not fence and not isf:
        if zona == "above" and l.startswith("## Piano di implementazione"): zona = "plan"
        elif zona in ("plan", "changelog") and l.startswith("## Review implementazione"): zona = "review"
        elif zona == "plan" and re.match(r"^###[ \t]+([0-9]+\.[ \t]*)?Changelog revisione piano", l): zona = "changelog"
        elif zona == "changelog" and re.match(r"^##?#?[ \t]", l): zona = "plan"
    if isf:
        fence = not fence
    if zona == "changelog" and l.strip():
        ultima = i
if ultima < 0:
    sys.exit(3)
note = ["- nota (deviazione difensiva, %s): %s" % (label, one(t)) for t in open(elenco, encoding="utf-8").read().splitlines() if t.strip()]
note = [n for n in note if n not in righe]
if note:
    righe[ultima + 1:ultima + 1] = note
    with open(spec + ".tmp", "wb") as fh:
        fh.write(nl.join(righe).encode("utf-8"))
    import os; os.replace(spec + ".tmp", spec)
'
difensive() { # implement/fix finito OK: registra le deviazioni "difensiva: " (file, AVVISO, nota nel changelog)
  local rj="$dir/log/$label.result.json" f="$dir/log/deviazioni-difensive.txt" dl="$dir/log/$label.difensive"
  local sp="${dir%.run}.md" b0 b1 rc
  rm -f "$dl"
  [ -f "$rj" ] && "$FIC_PY" -c "$DIFENSIVE_PY" estrai "$rj" 2>>"$err" | tr -d '\r' > "$dl" && [ -s "$dl" ] || { rm -f "$dl"; return 0; }
  # una riga per deviazione, "<label><TAB><testo>"; un rilancio della stessa etichetta sostituisce le sue
  { [ -f "$f" ] && tr -d '\r' < "$f" | grep -v "^$label	"; awk -v l="$label" '{ print l "\t" $0 }' "$dl"; } > "$f.tmp" && mv -f "$f.tmp" "$f"
  avviso "AVVISO: $(grep -c . "$dl") deviazioni difensive dichiarate (non fermano il ciclo, la review le giudica): log/deviazioni-difensive.txt"
  [ -f "$sp" ] || return 0
  b0=$(bash "$PC_SH" basis "$sp" 2>/dev/null | tr -d '\r' | grep '^Basis: ')
  cp "$sp" "$dl.spec-pre"
  "$FIC_PY" -c "$DIFENSIVE_PY" nota "$sp" "$label" "$dl" 2>>"$err"; rc=$?
  b1=$(bash "$PC_SH" basis "$sp" 2>/dev/null | tr -d '\r' | grep '^Basis: ')
  if [ $rc -eq 3 ]; then avviso "AVVISO: deviazioni difensive: il piano non ha un changelog, nessuna nota nella spec"
  elif [ $rc -ne 0 ] || [ -z "$b0" ] || [ "$b0" != "$b1" ]; then   # mai una spec STALE per una nota
    cp "$dl.spec-pre" "$sp"
    avviso "AVVISO: deviazioni difensive: nota nel changelog non scritta (exit $rc, impronta ${b0:-non calcolata} -> ${b1:-non calcolata}): spec rimessa com'era"
  fi
  rm -f "$dl.spec-pre"
}
# Esito: solo dall'evento "result" (il log contiene anche i testi letti dalla fase, con esempi di ESITO).
# Stampa la riga ESITO (o lo STOP «uscita non valida» e, sotto, originale=<riga>) e scrive result.json se valido.
if [ $code -eq 0 ] && [ "$phase" != chiusura ]; then
  esito=$(valida "$log" "$SCHEMA" "$phase" "$dir/log/$label.result.json" 2>>"$err" | tr -d '\r')
fi
# Finalize (harness-pt08): dopo una review finita, lo stato finale lo firma lo script, prima che .esito
# registri lo State di fine fase; DOPO result.json, perche' ne unisce la copertura (harness-pt09).
# Fail-closed: finalize assente, o uscito con un codice diverso da 0/1/3/4 -> .esito = STOP (sotto).
FINALIZE=${FIC_FINALIZE:-$MAAT_SCRIPTS/finalize.sh}
fin_fail=""
if [ "$phase" = review ] && [ $code -eq 0 ] && [ -f "${dir%.run}.md" ]; then
  if [ ! -f "$FINALIZE" ]; then
    fin_fail="finalize non eseguito (assente: $FINALIZE)"; echo "$fin_fail" > "$dir/log/$label.finalize"
  else
    cop_args=(); [ -f "$dir/log/$label.result.json" ] && cop_args=(--copertura "$dir/log/$label.result.json")
    FIC_GATES="$GATES" FIC_GATES_ROOT="$FIC_REPO" bash "$FINALIZE" --level "$(gates_level)" ${cop_args[@]+"${cop_args[@]}"} "$dir" > "$dir/log/$label.finalize" 2>&1
    frc=$?
    echo "exit=$frc" >> "$dir/log/$label.finalize"
    case $frc in 0|1|3|4) ;; *) fin_fail="finalize fallito (exit $frc, vedi log/$label.finalize)" ;; esac
  fi
fi
# controprove del driver con il mirror non ripristinato (counterproof.sh exit 5): ci si ferma, come nel worker
if [ "$phase" = review ] && [ "$(sed -n 's/^exit=//p' "$dir/log/$label.counterproof" 2>/dev/null | tail -1)" = 5 ]; then
  fin_fail="counterproof.sh exit 5: mirror non ripristinato (vedi log/$label.counterproof)${fin_fail:+; $fin_fail}"
fi
if [ $code -eq 0 ]; then
  if [ -n "$fin_fail" ]; then
    orig=$(printf '%s\n' "$esito" | sed -n '1p')
    esito="ESITO FASE review: STOP — $fin_fail${orig:+
originale=$orig}"
  fi
  if [ -n "$esito" ]; then   # harness-pt11: verifica dei rossi (test-red), test di accettazione invariati (implement/fix)
    case "$phase" in
      test-red) esito=$(verify_red "$esito") ;;
      implement|fix) esito=$(tests_guard "$esito") ;;
    esac
  fi
  case "$phase" in implement|fix)   # DEVIAZIONI DIFENSIVE: registrate solo su un esito OK (prima dello state)
    printf '%s\n' "$esito" | sed -n 1p | grep -q '^ESITO FASE [^:]*: OK' && difensive ;;
  esac
  if [ -n "$esito" ]; then
    st=""
    [ -f "${dir%.run}.md" ] && st=$(bash "$HERE/cycle-state.sh" "${dir%.run}.md" 2>>"$err" | sed -n 's/^State: //p')
    printf '%s\nstate=%s\n' "$esito" "$st" > "$dir/log/$label.esito"
    cat "$dir/log/$label.avvisi" >> "$dir/log/$label.esito" 2>/dev/null   # ALTRI FLUSSI: dopo state=, la riga 1 resta l'esito
  fi
fi
# chiusura di una catena (vedi CATENE): IMPLEMENTED solo con i gate full verdi e, se richiesti, gli e2e OK
if [ "$phase" = chiusura ]; then
  chz_why="$chz_fail"
  if [ -z "$chz_why" ]; then
    grep -q '^exit=0 ' "$dir/log/$label.gates" 2>/dev/null \
      || chz_why="gates $(sed -n 's/^gates: esito=\([A-Z]*\).*/\1/p' "$dir/log/$label.gates" 2>/dev/null | tail -1) (vedi log/$label.gates)"
  fi
  chz_e2e_st="non richiesto"
  if [ -z "$chz_why" ] && [ -n "$chz_e2e" ]; then
    chz_res=$(grep '"type":"result"' "$log" 2>/dev/null | tail -1)
    if [ $code -eq 0 ] && printf '%s' "$chz_res" | grep -q 'ESITO FASE chiusura: OK' && ! printf '%s' "$chz_res" | grep -q '"is_error":true'; then
      chz_e2e_st="OK ($chz_e2e)"
    else chz_why="e2e non riusciti ($chz_e2e): exit $code, vedi log/$label.jsonl"; fi
  fi
  chz_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  chz_tree=""; [ -z "$chz_why" ] && { chz_tree=$(tree_now) || chz_tree=""; [ -n "$chz_tree" ] || chz_why="tree finale non calcolato"; }
  if [ -z "$chz_why" ]; then
    printf 'Chiusura: IMPLEMENTED — base %s · tree %s · gates PASS (%s) · e2e %s · %s\n' "$(cat "$dir/base.txt")" "$chz_tree" "${chz_ev:--}" "$chz_e2e_st" "$chz_now" > "$dir/chiusura.txt"
    chz_esito="ESITO FASE chiusura: OK — catena chiusa: gate full PASS, e2e $chz_e2e_st"
  else
    printf 'Chiusura: NEEDS_VERIFICATION — %s · %s\n' "$chz_why" "$chz_now" > "$dir/chiusura.txt"
    chz_esito="ESITO FASE chiusura: STOP — $chz_why"
  fi
  st=$(bash "$HERE/cycle-state.sh" "${dir%.run}.md" 2>>"$err" | sed -n 's/^State: //p')
  printf '%s\nstate=%s\n' "$chz_esito" "$st" > "$dir/log/$label.esito"
fi
# gate dopo un implement/fix finito OK, ancora sotto il lock (la review che segue li riusa a chiave identica)
case "$phase" in implement|fix)
  [ $code -eq 0 ] && grep -q '^ESITO FASE [^:]*: OK' "$dir/log/$label.esito" 2>/dev/null && run_gates >/dev/null ;;
esac

release   # prima di .exit: chi vede la fase finita trova il lock gia' libero
echo "$code" > "$ex"
rm -f "$dir/log/$label.running"
exit $code
