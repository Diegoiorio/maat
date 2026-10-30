#!/usr/bin/env python3
r"""guard.py — guardia dei comandi: hook PreToolUse delle sotto-sessioni e (con --universal) della sessione.

Le sotto-sessioni girano in bypassPermissions (le scritture sotto .claude/ passano solo cosi') con un
deny per PREFISSO, che un comando avvolto in `wsl -- bash -lc '...'` aggira (misurato). Questo hook
guarda il comando INTERO, dentro gli involucri, e nega (exit 2, motivo su stderr) un elenco CHIUSO di
azioni irreversibili. Non e' una sandbox: cosa resta scoperto e' scritto in riferimento.md, sezione
"Sub-session permissions".

DUE STRATI DI REGOLE (R3.6, pk05):
  NUCLEO, sempre attivo e generico: git che cambia stato (con le regole sui worktree collegati), GRAVE_GIT,
     `rm -rf` e `Remove-Item -Recurse -Force`, heredoc Python che scrivono, installazioni di pacchetti, accesso
     remoto diretto (ssh/scp/sftp/rsync), docker, psql; le regole delle fasi (scritture solo nella cartella di
     lavoro per le fasi in sola lettura, suite intere vietate in plan/test-red/test-stage).
  PROGETTO, da maat.json -> guardia:
     produzione    regex (senza maiuscole) sull'intero testo del comando: sempre GRAVE, anche con la guardia ridotta;
     rilascio      script di rilascio, confrontati come SOTTOSTRINGA del comando: negati sempre, sempre GRAVI; nel
                   contenuto di uno script contano come comando, come la produzione;
     involucri     script che incapsulano l'accesso remoto o la copia locale: ammessi e non letti; le loro
                   opzioni_negate sono sempre GRAVI (eseguiti direttamente o con `bash …`);
     vietati_extra prefissi di comandi negati nelle sotto-sessioni (gli stessi passano a --disallowedTools);
     suite         script di suite del progetto ({script, selettori: pytest|vitest}), negati senza file o selettori come i runner;
     la suite intera della regola 4: i runner dei comandi `test` dei moduli e guardia.suite, oltre a pytest e vitest.
  Il file: MAAT_CONFIG (le sotto-sessioni lo ricevono da run-phase.sh, percorso assoluto), altrimenti
  <CLAUDE_PROJECT_DIR>/.claude/maat.json (Claude Code fornisce la variabile agli hook; mai dalla cwd del comando).
  Assente, illeggibile o non valido: il nucleo resta, e ogni comando che contiene un host o un dominio fuori da
  localhost e' GRAVE (fail-closed): «maat.json non trovato» / «maat.json non valido».

  1. Progetto, prima di tutto e sull'intero testo del comando: rilascio e produzione.
  2. Strumenti solo in POSIZIONE DI COMANDO (dopo ; && || | & ( e le parole chiave do/then/else/{/!,
     dentro bash -c / -lc (anche con -o pipefail), $( ), ``, xargs, find -exec, cmd /c, powershell -c):
     ssh/scp/sftp/rsync diretti (si passa dagli involucri), git che cambia stato, docker, psql, installazioni di
     pacchetti, rm ricorsivo forzato. Cosi' `git show <Base>:docker-compose.yml > docker-compose.yml` o
     `git status && rm f` passano. Il payload degli involucri NON viene analizzato.
  3. Fasi `plan`/`review`/`probe` (FIC_PHASE): Edit/Write/NotebookEdit dentro il repo solo sotto
     la cartella di lavoro (cartelle.lavoro di maat.json, default `.claude/.ai-workflow/`). Fuori dal repo (scratchpad) e' libero.
  3b. Corsia di implementazione (FIC_WRITE_SCOPE, harness-pt13): Edit/Write dentro il repo solo sui file di
     `scrive:` dei blocchi della corsia e nella run dir (check_scope). Si somma alla regola 5: con FIC_WRITE_SCOPE
     e FIC_SCOPE entrambi impostati una scrittura deve rispettare tutti e due (check_write li applica in fila).
  4. Fase `plan`: niente suite complete — pytest, vitest e i runner dei comandi `test` dei moduli senza file o
     selettori espliciti (-k/-m per pytest, -t per vitest) negati, anche dentro wsl/bash -c (check_suite). Le suite
     del livello le esegue il driver (scripts/gates.sh del plugin) dopo implement/fix.
  5. Fasi `test-red` e `test-stage` (harness-pt11): Edit/Write dentro il repo solo sui path dello SCOPE, il file
     indicato da FIC_SCOPE (uno per riga, relativi al repo; una riga che finisce con / vale come prefisso):
     test-red = i file di test del piano + i file che il piano dichiara nuovi (stub); test-stage = la sola
     <run-dir>/staging/. Scope assente o illeggibile: tutto negato. Niente suite complete, come in `plan`.

COSA RESTA SCOPERTO, per scelta (niente sandbox su Windows nativo; ogni test passa da `wsl bash -lc`,
quindi un'allowlist vera di capability qui non e' applicabile): comandi offuscati (base64, variabili
costruite a runtime, script scritti su file e poi eseguiti, un programma Python che apre una
connessione); file scritti con Bash nelle fasi di sola lettura; il payload degli involucri.
Un hook che FALLISCE (eccezione, interprete assente) lascia passare: e' fail-open. Per questo
run-phase.sh non lancia la sottosessione se l'autotest non ottiene il diniego (exit 5). L'hook del plugin
(scripts/guard-hook.sh) invece tratta un'uscita diversa da 0/2, o Python assente, come "ask" (nega con FIC_PHASE).

MODALITA' --universal (guardia di SESSIONE, hook del plugin hooks/hooks.json -> guard-hook.sh): solo le regole
1-2, niente regole per fase. Differenze: `git commit`/`checkout`/`add` ammessi solo DENTRO un worktree collegato
(`git rev-parse --git-dir` != `--git-common-dir`; la directory e' il `cwd` dell'hook, seguito da `cd <dir>` e da
`git -C <dir>`; ignota → negato), mai nel tree principale; `git worktree add|list` ammessi; push/reset/rebase/stash
e il resto restano negati ovunque.
In piu' `bash|sh <file>` con il file sotto script/ o .claude/ legge le righe ESEGUIBILI del file (senza
commenti ne' corpi di heredoc di testo) e applica solo le regole remote e infrastrutturali: ssh/scp/
sftp/rsync, docker, psql, installazioni, le opzioni negate degli involucri, e la produzione solo come comando
(script di rilascio) o come argomento di un comando di rete (ssh, curl, ...), non in un echo. Git e `rm -rf` no:
gli script lavorano su repo e cartelle temporanee e sono codice revisionato. Non si leggono gli involucri del
progetto ne' gli involucri del plugin (PLUGIN_WRAPPERS sotto MAAT_ROOT/scripts/, confrontati per percorso
assoluto risolto, anche nella forma /mnt/<drive>/ di WSL).
In entrambe le modalita': heredoc Python (`python - <<`, `py -3 - <<`) che apre file in scrittura
(open(..., 'w'|'a'), write_text, write_bytes) negata.

Directory del git in --universal: `--git-dir`/`--work-tree`/`-c core.worktree`, GIT_DIR/GIT_WORK_TREE
nel comando, pushd/popd/Push-Location → ignota (quindi non ammessa). Un `cd` dentro `( … )`, `$( )`,
`bash -c`, `wsl [--cd x] -- bash -lc`, `cmd /c`, `powershell -c` non vale per i comandi che seguono.
Tool analizzati: Bash e PowerShell (in PowerShell `\` e' un separatore; Remove-Item -Recurse -Force).

MOTIVI (R11): ogni risposta ha tre parti, separate da « — »: <cosa e' stato riconosciuto, a partire dal comando> —
<regola del nucleo|del progetto, quale> — <cosa fare se e' voluto>. Tabella unica MSG, in it ed en; la lingua viene
da maat.json -> lingua (assente, non in tabella, maat.json non valido o assente: it).

Uso: stdin = JSON del PreToolUse. Sottosessioni: uscita 0 = ammesso, 2 = negato (motivo su stderr).
`--universal` = guardia di sessione: nella sessione principale (FIC_PHASE vuota) invece di negare CHIEDE
CONFERMA (JSON `hookSpecificOutput.permissionDecision: "ask"` su stdout, uscita 0); con FIC_PHASE
impostata (sotto-sessione) nega come sempre. `--deny-list`: stampa le voci di --disallowedTools per
run-phase.sh (nucleo, rilascio, vietati_extra), una per riga. Test: guard.test.sh.
GUARDIA RIDOTTA: con FIC_SESSION_GUARD=prod (blocco env di .claude/settings.local.json) la sessione principale
chiede conferma SOLO per le azioni GRAVI: produzione, rilascio, opzioni negate degli involucri, maat.json
assente o non valido con un host nel comando, git push/reset/rebase/clean/restore/filter-branch/update-ref,
`checkout` che butta modifiche (`--`, `.`, `-f`), branch/tag con cancellazione o forzatura, input illeggibile. Il
resto (commit, checkout di branch, merge, installazioni, docker, ssh, rm -rf, heredoc) passa. Le sotto-sessioni
(FIC_PHASE impostata) applicano sempre le regole piene.
"""
import importlib.util
import io
import json
import os
import re
import shlex
import subprocess
import sys

REMOTE = {"ssh", "scp", "sftp", "rsync"}
GIT_DENY = {"commit", "push", "reset", "checkout", "switch", "restore", "clean", "stash",
            "rebase", "merge", "rm", "mv", "add", "cherry-pick", "revert", "am", "apply",
            "update-ref", "worktree"}
# sottocomandi innocui in lettura, distruttivi con certe opzioni
GIT_DENY_WITH = {"branch": {"-d", "-D", "--delete", "-m", "-M", "--move", "-f", "--force"},
                 "tag": {"-d", "--delete", "-f", "--force"}}
KEYWORDS = {"do", "then", "else", "elif", "if", "while", "until", "{", "}", "!", "[[", "]]"}
GIT_OPT_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
SHELLS = {"bash", "sh", "zsh", "dash", "fish"}
WRAPPERS = {"env", "exec", "sudo", "nohup", "time", "command", "builtin", "nice"}
OPERATORS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;"}
WRITE_TOOLS = {"Edit", "Write", "NotebookEdit", "MultiEdit"}
READONLY_PHASES = {"plan", "review", "probe"}
# fasi con uno scope di scrittura loro (FIC_SCOPE, regola 5) e senza suite complete (regola 4)
SCOPED_PHASES = {"test-red", "test-stage"}
SUITE_PHASES = {"plan"} | SCOPED_PHASES
# --universal: sottocomandi git ammessi solo DENTRO un worktree collegato (git-dir != git-common-dir),
# mai nel tree principale; `worktree add`/`worktree list` ammessi ovunque. push/reset/rebase/stash e
# il resto di GIT_DENY restano negati ovunque.
GIT_WORKTREE_OK = {"commit", "checkout", "add"}
GIT_WORKTREE_SUB_OK = {"add", "list"}
# `python - <<` / `py -3 - <<` (anche .exe con percorso): heredoc Python
PY_HEREDOC_RE = re.compile(r"(?:^|[\s;&|(/\\])(?:python[0-9.]*|py)(?:\.exe)?(?:\s+-[-\w.]+)*\s+-?\s*<<")
# open(..., 'w') sulla stessa riga, senza dipendere dalle parentesi: open(os.path.join(d, "f"), "w")
PY_WRITE_RE = re.compile(r"""open\s*\(.*?,\s*(mode\s*=\s*)?['"][wax][bt+]*['"]|write_text|write_bytes""")
MODE = {"universal": False, "cwd": None, "script": False, "gitenv": False}
# variabili che spostano repository o working tree: con queste la directory del git e' ignota
GIT_ENV_RE = re.compile(r"GIT_(DIR|WORK_TREE|COMMON_DIR|INDEX_FILE)\b", re.IGNORECASE)
CD_LIKE = {"cd", "chdir", "set-location", "sl"}
CD_UNKNOWN = {"pushd", "popd", "push-location", "pop-location"}
SHELL_TOOLS = {"Bash", "PowerShell"}
# comandi di rete: nel contenuto di uno script la produzione conta solo come loro argomento (o come comando)
NET_TOOLS = {"ssh", "scp", "sftp", "rsync", "curl", "wget", "http", "https", "nc", "ncat", "telnet", "ping"}
# heredoc: `<<EOF`, `<<-'EOF'`, `<< "EOF"` (non `<<<`)
HEREDOC_RE = re.compile(r"(?<!<)<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
HEREDOC_EXEC_RE = re.compile(r"(^|[\s;&|(/\\])(bash|sh|zsh|dash|ssh|python[0-9.]*|py)(\.exe)?(\s|$)")
# Involucri del PLUGIN (passo 3-bis): ammessi per percorso assoluto risolto sotto MAAT_ROOT/scripts/, anche dentro
# `wsl -- bash -lc '…'`. fic-mirror.sh no: e' una libreria inclusa dagli involucri, non si lancia da sola.
PLUGIN_WRAPPERS = ("test-fast.sh", "counterproof.sh", "vitest-fast.sh")
# Suite complete (regola 4), nucleo: runner noti. Quelli del progetto vengono dai comandi `test` dei moduli e da
# guardia.suite (script di suite del progetto, con le regole di selezione di pytest o vitest).
SUITE_NUCLEO = {"pytest": "pytest", "py.test": "pytest", "vitest": "vitest"}
# Fail-closed senza maat.json valido: un host (nome con un punto) o un IPv4 nel comando. localhost non ha punti.
HOST_RE = re.compile(r"(?<![\w.-])(?:\d{1,3}(?:\.\d{1,3}){3}|(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z][a-z0-9-]*)"
                     r"(?![\w-])", re.IGNORECASE)
# --deny-list: prefissi del nucleo per --disallowedTools (il deny per prefisso delle sotto-sessioni)
DENY_NUCLEO = ("ssh", "scp", "sftp", "rsync", "git commit", "git push", "git reset", "git checkout", "git switch",
               "git clean", "git stash", "git rebase", "git merge", "git restore", "docker", "psql", "pip install",
               "npm install", "rm -rf")


# Guardia di sessione RIDOTTA (FIC_SESSION_GUARD=prod, nel blocco env di .claude/settings.local.json): nella
# sola sessione principale (--universal senza FIC_PHASE) chiede conferma solo per le azioni GRAVI (vedi docstring).
# Le sottosessioni (FIC_PHASE impostata) non la vedono mai.
GRAVE_GIT = {"push", "reset", "rebase", "clean", "update-ref", "filter-branch", "restore"}
# `git checkout` che butta modifiche non committate (irreversibile): `-- <path>`, `.`, `-f/--force`
GRAVE_CHECKOUT = {"--", ".", "-f", "--force"}

# ------------------------------------------------------------------------------------------- motivi (R11)
# Una voce per regola: (cosa e' stato riconosciuto, regola, cosa fare). Le parti variabili ({...}) stanno SOLO
# nella prima parte, che inizia con il comando riconosciuto; « — » separa le tre parti e non compare nei valori.
SEP = " — "
MSG = {
    "input": {
        "it": ("`input dell'hook`: JSON non leggibile",
               "regola del nucleo (input illeggibile: si nega per prudenza)",
               "riprova il comando; se si ripete, controlla la versione di Claude Code"),
        "en": ("`hook input`: unreadable JSON",
               "core rule (unreadable input: denied as a precaution)",
               "retry the command; if it happens again, check the Claude Code version")},
    "config_assente": {
        "it": ("`{what}`: host o dominio nel comando, senza regole di produzione del progetto",
               "regola del nucleo (maat.json non trovato: guardia di progetto assente)",
               "crea .claude/maat.json con /maat:setup; conferma solo se l'host non è di produzione"),
        "en": ("`{what}`: host or domain in the command, with no project production rules",
               "core rule (maat.json not found: project guard missing)",
               "create .claude/maat.json with /maat:setup; confirm only if the host is not production")},
    "config_non_valido": {
        "it": ("`{what}`: host o dominio nel comando, senza regole di produzione del progetto",
               "regola del nucleo (maat.json non valido: guardia di progetto assente)",
               "correggi .claude/maat.json (maat-config.py valida dice cosa); conferma solo se l'host non è di produzione"),
        "en": ("`{what}`: host or domain in the command, with no project production rules",
               "core rule (invalid maat.json: project guard missing)",
               "fix .claude/maat.json (maat-config.py valida tells what); confirm only if the host is not production")},
    "produzione": {
        "it": ("`{what}`: il comando nomina la produzione",
               "regola del progetto (guardia.produzione: host, domini e percorsi di produzione)",
               "conferma solo se vuoi davvero agire sulla produzione: nel ciclo di sviluppo non si tocca"),
        "en": ("`{what}`: the command names production",
               "project rule (guardia.produzione: production hosts, domains and paths)",
               "confirm only if you really mean to act on production: the development cycle never touches it")},
    "produzione_script": {
        "it": ("`{what}`: lo script esegue un comando verso la produzione",
               "regola del progetto (guardia.produzione e guardia.rilascio, nel contenuto degli script)",
               "conferma solo se vuoi davvero agire sulla produzione: nel ciclo di sviluppo non si tocca"),
        "en": ("`{what}`: the script runs a command against production",
               "project rule (guardia.produzione and guardia.rilascio, inside scripts)",
               "confirm only if you really mean to act on production: the development cycle never touches it")},
    "rilascio": {
        "it": ("`{what}`: script di rilascio",
               "regola del progetto (guardia.rilascio: script di rilascio)",
               "conferma solo se vuoi davvero rilasciare; mai da una sotto-sessione"),
        "en": ("`{what}`: release script",
               "project rule (guardia.rilascio: release scripts)",
               "confirm only if you really mean to release; never from a sub-session")},
    "involucro_opzione": {
        "it": ("`{what}`: opzione negata di un involucro",
               "regola del progetto (guardia.involucri: opzioni negate)",
               "conferma solo se è davvero voluto: in un ciclo è uno STOP per l'utente"),
        "en": ("`{what}`: denied option of a wrapper",
               "project rule (guardia.involucri: denied options)",
               "confirm only if it is really intended: inside a cycle it is a STOP for the user")},
    "vietato_extra": {
        "it": ("`{what}`: comando vietato dal progetto nelle sotto-sessioni",
               "regola del progetto (guardia.vietati_extra)",
               "lascialo all'utente, fuori dalla sotto-sessione"),
        "en": ("`{what}`: command forbidden by the project in sub-sessions",
               "project rule (guardia.vietati_extra)",
               "leave it to the user, outside the sub-session")},
    "heredoc_py": {
        "it": ("`python - <<`: heredoc Python che scrive file",
               "regola del nucleo (heredoc Python che scrivono)",
               "scrivi il file con Write o Edit: un'heredoc ha già scritto byte invisibili"),
        "en": ("`python - <<`: Python heredoc writing files",
               "core rule (Python heredocs that write)",
               "write the file with Write or Edit: a heredoc already wrote invisible bytes")},
    "find_delete": {
        "it": ("`find -delete`: cancellazione in blocco",
               "regola del nucleo (cancellazioni ricorsive)",
               "togli i file uno per uno, o conferma solo se è voluto"),
        "en": ("`find -delete`: bulk deletion",
               "core rule (recursive deletions)",
               "remove the files one by one, or confirm only if intended")},
    "git_worktree": {
        "it": ("`git {sub}`: cambia lo stato del repository fuori da un worktree collegato (directory {gdir})",
               "regola del nucleo (git che cambia stato: ammesso solo in un worktree collegato)",
               "lavora in un worktree collegato, o conferma solo se vuoi davvero cambiare il tree principale"),
        "en": ("`git {sub}`: changes the repository outside a linked worktree (directory {gdir})",
               "core rule (git that changes state: allowed only in a linked worktree)",
               "work in a linked worktree, or confirm only if you really mean to change the main tree")},
    "git_push": {
        "it": ("`git {sub}`: pubblica verso un repository remoto",
               "regola del nucleo (git che pubblica)",
               "conferma solo se vuoi davvero pubblicare i commit"),
        "en": ("`git {sub}`: publishes to a remote repository",
               "core rule (git that publishes)",
               "confirm only if you really mean to publish the commits")},
    "git_stato": {
        "it": ("`git {sub}`: cambia lo stato del repository",
               "regola del nucleo (git che cambia stato, anche dentro wsl o bash -c)",
               "conferma solo se vuoi davvero cambiare il repository"),
        "en": ("`git {sub}`: changes the repository state",
               "core rule (git that changes state, also inside wsl or bash -c)",
               "confirm only if you really mean to change the repository")},
    "git_forza": {
        "it": ("`git {sub}`: cancellazione o forzatura",
               "regola del nucleo (git che cambia stato: rami e tag)",
               "conferma solo se vuoi davvero cancellare o forzare"),
        "en": ("`git {sub}`: deletion or force",
               "core rule (git that changes state: branches and tags)",
               "confirm only if you really mean to delete or force")},
    "git_storia": {
        "it": ("`git {sub}`: riscrive la storia del repository",
               "regola del nucleo (git che riscrive la storia)",
               "conferma solo se vuoi davvero riscrivere la storia, dopo un backup del ramo"),
        "en": ("`git {sub}`: rewrites the repository history",
               "core rule (git that rewrites history)",
               "confirm only if you really mean to rewrite history, after backing up the branch")},
    "remoto": {
        "it": ("`{what}`: accesso remoto diretto",
               "regola del nucleo (accesso remoto diretto: ssh, scp, sftp, rsync)",
               "usa l'involucro del progetto che incapsula l'accesso (guardia.involucri), o conferma solo se è voluto"),
        "en": ("`{what}`: direct remote access",
               "core rule (direct remote access: ssh, scp, sftp, rsync)",
               "use the project wrapper for remote access (guardia.involucri), or confirm only if intended")},
    "docker": {
        "it": ("`{what}`: comando sui container",
               "regola del nucleo (docker)",
               "conferma solo se vuoi davvero toccare i container"),
        "en": ("`{what}`: container command",
               "core rule (docker)",
               "confirm only if you really mean to touch the containers")},
    "db": {
        "it": ("`{what}`: comando diretto sul database",
               "regola del nucleo (psql e strumenti del database)",
               "per le letture usa l'involucro del progetto, o conferma solo se è voluto"),
        "en": ("`{what}`: direct database command",
               "core rule (psql and database tools)",
               "for reads use the project wrapper, or confirm only if intended")},
    "install": {
        "it": ("`{what}`: installazione di pacchetti",
               "regola del nucleo (installazioni)",
               "conferma solo se vuoi davvero installare: cambia l'ambiente"),
        "en": ("`{what}`: package installation",
               "core rule (installations)",
               "confirm only if you really mean to install: it changes the environment")},
    "rm_rf": {
        "it": ("`{what}`: cancellazione ricorsiva forzata",
               "regola del nucleo (rm -rf e Remove-Item -Recurse -Force)",
               "togli i file uno per uno, o conferma solo se è voluto"),
        "en": ("`{what}`: forced recursive deletion",
               "core rule (rm -rf and Remove-Item -Recurse -Force)",
               "remove the files one by one, or confirm only if intended")},
    "suite": {
        "it": ("`{what}`: suite completa senza file né selettori nella fase {fase}",
               "regola del nucleo (fasi plan, test-red e test-stage: niente suite complete)",
               "indica un file o un selettore (-k, -t): le suite del livello le esegue il driver dopo implement e fix"),
        "en": ("`{what}`: whole suite with no files or selectors in phase {fase}",
               "core rule (plan, test-red and test-stage phases: no whole suites)",
               "name a file or a selector (-k, -t): the driver runs the level's suites after implement and fix")},
    "corsia": {
        "it": ("`{what}`: file fuori dai blocchi della corsia {lane} (FIC_WRITE_SCOPE)",
               "regola del nucleo (corsia di implementazione)",
               "un file di un altro blocco è dell'altra corsia: se serve, è una deviazione dal piano"),
        "en": ("`{what}`: file outside the blocks of lane {lane} (FIC_WRITE_SCOPE)",
               "core rule (implementation lane)",
               "a file of another block belongs to the other lane: if needed, it is a plan deviation")},
    "scope_fase": {
        "it": ("`{what}`: file fuori dallo scope della fase {fase} (FIC_SCOPE)",
               "regola del nucleo (fasi test-red e test-stage: scope di scrittura)",
               "scrivi solo i test del piano e i file nuovi dichiarati (test-stage: la sola staging/)"),
        "en": ("`{what}`: file outside the scope of phase {fase} (FIC_SCOPE)",
               "core rule (test-red and test-stage phases: write scope)",
               "write only the plan's tests and the declared new files (test-stage: staging/ only)")},
    "lavoro_fase": {
        "it": ("`{what}`: scrittura fuori da {lav} nella fase {fase}",
               "regola del nucleo (fasi in sola lettura: si scrive solo nella cartella di lavoro)",
               "revert e ripristino delle controprove si fanno con Bash (git show … >, cp)"),
        "en": ("`{what}`: write outside {lav} in phase {fase}",
               "core rule (read-only phases: writes only in the work folder)",
               "counterproof revert and restore are done with Bash (git show … >, cp)")},
}

# Regole del progetto (load_config). stato: None = maat.json valido, "assente", "non_valido".
CONF = {"stato": "assente", "lingua": "it", "prod": None, "rilascio": [], "involucri": [], "vietati": [],
        "suite": dict(SUITE_NUCLEO)}


def reason(key, **kw):
    """Il motivo in tre parti, nella lingua di maat.json (it se assente, non in tabella o con maat.json non valido)."""
    voci = MSG[key]
    t = voci.get(CONF["lingua"]) or voci["it"]
    vals = {k: str(v).replace("—", "-") for k, v in kw.items()}   # « — » solo come separatore
    return SEP.join((t[0].format(**vals), t[1], t[2]))


def reduced():
    return (MODE["universal"] and not os.environ.get("FIC_PHASE")
            and os.environ.get("FIC_SESSION_GUARD", "").strip().lower() == "prod")


def deny(key, grave=False, **kw):
    """Sottosessioni (anche con --universal, se FIC_PHASE e' impostata): diniego, exit 2.
    Sessione principale (--universal senza FIC_PHASE): chiede conferma all'utente (permissionDecision
    "ask" nel JSON su stdout, exit 0). Con la guardia ridotta (reduced()) un diniego non grave non chiede
    niente: ritorna e i controlli proseguono (un'azione grave piu' avanti nello stesso comando chiede)."""
    if reduced() and not grave:
        return
    msg = reason(key, **kw)
    if MODE["universal"] and not os.environ.get("FIC_PHASE"):
        sys.stdout.write(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "ask",
            "permissionDecisionReason": msg}}) + "\n")
        sys.exit(0)
    who = "guardia di sessione" if MODE["universal"] else "guardia di fase"
    sys.stderr.write(who + ": " + msg + "\n")
    sys.exit(2)


# ------------------------------------------------------------------------------------------- maat.json
def config_path():
    """MAAT_CONFIG, altrimenti <CLAUDE_PROJECT_DIR>/.claude/maat.json; mai dalla cwd del comando."""
    p = os.environ.get("MAAT_CONFIG")
    if p:
        return p
    pd = os.environ.get("CLAUDE_PROJECT_DIR")
    return os.path.join(pd, ".claude", "maat.json") if pd else None


def runner_of(txt):
    """Il runner di un comando di test: `{python} -m pytest …` → pytest, `bash {maat}/scripts/x.sh …` → x.sh."""
    try:
        toks = shlex.split(txt)
    except ValueError:
        toks = txt.split()
    i = 0
    while i < len(toks) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", toks[i]):
        i += 1
    if i >= len(toks):
        return None
    b, rest = base(toks[i]), toks[i + 1:]
    if b in SHELLS:
        r = base(rest[0]) if rest else None
    elif "-m" in rest and (b.startswith("python") or b in ("py", "{python}")):
        k = rest.index("-m")
        r = rest[k + 1] if k + 1 < len(rest) else None
    elif b in ("npx", "pnpm", "yarn", "bunx") and rest:
        r = base(rest[0])
    else:
        r = b
    return None if not r or r.startswith("{") else r


def load_config():
    path = config_path()
    if not path or not os.path.isfile(path):
        CONF["stato"] = "assente"
        return
    sys.dont_write_bytecode = True   # nessun __pycache__ sotto MAAT_ROOT
    try:
        spec = importlib.util.spec_from_file_location(
            "maat_config", os.path.join(os.path.dirname(os.path.abspath(__file__)), "maat-config.py"))
        mc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mc)
    except Exception:   # lettore assente o rotto: nessuna regola del progetto, fail-closed
        CONF["stato"] = "non_valido"
        return
    saved, sys.stderr = sys.stderr, io.StringIO()   # gli errori del lettore non vanno nel canale dell'hook
    try:
        cfg, _p = mc.carica(path)
        g = cfg.get("guardia", {}) or {}
        prod = [r for r in g.get("produzione", []) if r]
        CONF["prod"] = re.compile("|".join("(?:%s)" % r for r in prod), re.IGNORECASE) if prod else None
    except mc.Uscita as u:
        CONF["stato"] = "assente" if u.codice == 4 else "non_valido"
        return
    except Exception:   # regex non valida, file illeggibile
        CONF["stato"] = "non_valido"
        return
    finally:
        sys.stderr = saved
    CONF["stato"] = None
    CONF["lingua"] = cfg.get("lingua") if cfg.get("lingua") in ("it", "en") else "it"
    CONF["rilascio"] = [r for r in g.get("rilascio", []) if r]
    inv = []
    for x in g.get("involucri", []):
        s = x if isinstance(x, str) else x.get("script", "")
        if s:
            s = pfold(s.replace("\\", "/"))
            inv.append((s, base(s), [] if isinstance(x, str) else list(x.get("opzioni_negate", []))))
    CONF["involucri"] = inv
    CONF["vietati"] = [v for v in g.get("vietati_extra", []) if v]
    for x in g.get("suite", []):
        if x.get("script") and x.get("selettori") in ("pytest", "vitest"):
            CONF["suite"][base(x["script"].replace("\\", "/"))] = x["selettori"]
    for m in cfg.get("moduli", []):
        r = runner_of(mc.testo((m.get("comandi") or {}).get("test")))
        if r and r not in CONF["suite"]:
            CONF["suite"][r] = "pytest" if r in ("pytest", "py.test") else "file"


def prod_hit(s):
    """Il testo di produzione o di rilascio trovato in s (barre gia' in avanti), oppure None."""
    low = s.lower()
    for r in CONF["rilascio"]:
        if r.replace("\\", "/").lower() in low:
            return r
    m = CONF["prod"].search(s) if CONF["prod"] else None
    return m.group(0) if m else None


def base(tok):
    t = tok.replace("\\", "/").rsplit("/", 1)[-1].lower()
    return t[:-4] if t.endswith(".exe") else t


def split_simple(cmd, marks=False):
    """Comandi semplici (liste di token) di una riga di shell; ripiego grezzo se shlex fallisce.
    Con marks=True le parentesi compaiono come stringhe "(" / ")": delimitano le subshell."""
    out = []
    for line in cmd.splitlines() or [cmd]:
        try:
            lex = shlex.shlex(line, posix=True, punctuation_chars=";&|()")
            lex.whitespace_split = True
            lex.commenters = ""
            toks = list(lex)
        except ValueError:  # virgolette sbilanciate: si spezza tutto, e' conservativo
            toks = re.split(r"[\s'\"]+", line)
        cur = []
        for t in toks:
            if t in OPERATORS or set(t) <= set(";&|()") and t:
                if cur:
                    out.append(cur)
                cur = []
                if marks:
                    out.extend(c for c in t if c in "()")
            elif t:
                cur.append(t)
        if cur:
            out.append(cur)
    return out


def substitutions(cmd):
    """Contenuto di $( ... ) e `...`: vengono eseguiti, quindi si analizzano come comandi."""
    return re.findall(r"\$\(([^()]*)\)", cmd) + re.findall(r"`([^`]*)`", cmd)


def check_command(cmd, depth=0):
    if depth > 6:
        return
    for inner in substitutions(cmd):   # $( ) e ``: subshell, un `cd` dentro non esce
        saved = MODE["cwd"]
        check_command(inner, depth + 1)
        MODE["cwd"] = saved
    stack = []
    for item in split_simple(cmd, marks=True):
        if item == "(":
            stack.append(MODE["cwd"])
        elif item == ")":
            if stack:
                MODE["cwd"] = stack.pop()   # `( cd x; … )`: la directory torna quella di prima
        else:
            check_simple(item, depth)


def check_simple(toks, depth):
    """Un comando semplice. Solo `cd` (e simili) ed `eval` cambiano la directory per i comandi che
    seguono: `bash -c 'cd x'`, `wsl --cd x …`, `cmd /c`, `powershell -c` girano in un altro processo."""
    saved = MODE["cwd"]
    if not _check_simple(toks, depth):
        MODE["cwd"] = saved


def involucro_negato(name, args):
    """Un involucro del progetto eseguito con un'opzione negata (guardia.involucri): sempre grave."""
    for _path, b, opts in CONF["involucri"]:
        if name == b:
            hit = [o for o in opts if o in args]
            if hit:
                deny("involucro_opzione", grave=True, what=f"{b} {hit[0]}")


def _check_simple(toks, depth):
    i = 0
    # assegnazioni VAR=... e involucri
    while i < len(toks):
        t, b = toks[i], base(toks[i])
        if t in KEYWORDS:   # `for f in x; do git …`, `if …; then git …`, `{ git …; }`, `! git …`
            i += 1
        elif b in ("for", "case", "select"):   # `for f in a b` non esegue nulla: il corpo e' dopo `do`
            return
        elif b == "xargs":
            i += 1
            while i < len(toks) and toks[i].startswith("-"):
                opt = toks[i]
                i += 1
                if opt in ("-I", "-n", "-P", "-L", "-d", "-a", "-E", "-s"):
                    i += 1
        elif re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1
        elif b == "wsl":
            i += 1
            while i < len(toks) and toks[i].startswith("-"):
                opt = toks[i]
                i += 1
                if opt == "--cd" and MODE["universal"]:   # vale solo per questo comando (check_simple)
                    tgt = toks[i] if i < len(toks) else ""
                    MODE["cwd"] = (norm(tgt, MODE["cwd"]) if MODE["cwd"] and tgt
                                   and not re.search(r"[$`~*?]", tgt) else None)
                if opt in ("-d", "--distribution", "-u", "--user", "--cd"):
                    i += 1
                if opt in ("--", "-e", "--exec"):
                    break
        elif b in WRAPPERS:
            i += 1
            while i < len(toks) and toks[i].startswith("-"):
                i += 1
        elif b == "timeout":
            i += 1
            while i < len(toks) and toks[i].startswith("-"):
                i += 1
            i += 1  # la durata
        else:
            break
    if i >= len(toks):
        return
    b, args = base(toks[i]), toks[i + 1:]

    if b in CD_LIKE and MODE["universal"]:   # `cd <wt> && git commit`: la directory del git che segue
        tgt = next((a for a in args if not a.startswith("-")), "")
        MODE["cwd"] = (norm(tgt, MODE["cwd"]) if MODE["cwd"] and tgt and not re.search(r"[$`~*?]", tgt)
                       else None)
        return True
    if b in CD_UNKNOWN and MODE["universal"]:   # pila di directory: non la si segue, directory ignota
        MODE["cwd"] = None
        return True
    if MODE["script"]:   # contenuto di uno script: la produzione conta come comando o come host di un comando di rete
        cmd0 = toks[i].replace("\\", "/")   # un comando ha forma di percorso: niente spazi ne' parentesi
        hit = prod_hit(cmd0) if re.fullmatch(r"[\w./:~-]+", cmd0) else None
        if not hit and b in NET_TOOLS | SHELLS:
            hit = next((h for h in (prod_hit(a.replace("\\", "/")) for a in args) if h), None)
        if hit:
            deny("produzione_script", grave=True, what=hit)
    involucro_negato(b, args)   # eseguito direttamente; con `bash …` lo vede SHELLS
    if b == "eval":   # gira nella shell corrente: un `cd` dentro vale anche dopo
        check_command(" ".join(args), depth + 1)
        return True
    if b in SHELLS:
        j, has_c = 0, False
        while j < len(args):
            a = args[j]
            if a in ("-o", "+o", "-O", "+O", "--rcfile", "--init-file"):
                j += 2
                continue
            if not a.startswith(("-", "+")):
                break
            if not a.startswith("--"):
                has_c = has_c or "c" in a[1:]
                if a[-1] in "oO":   # `-euo pipefail`: l'ultima lettera prende un argomento
                    j += 1
            j += 1
        if not has_c and j < len(args) and base(args[j]) in CONF["suite"]:   # `bash <runner> …`
            check_suite(base(args[j]), args[j + 1:])
        if has_c and j < len(args):
            check_command(args[j], depth + 1)
        elif j < len(args):
            involucro_negato(base(args[j]), args[j + 1:])
            if MODE["universal"] and b in ("bash", "sh"):
                check_script(args[j], depth)
        return  # sottosessioni: `bash script.sh ...` non si analizza (vedi docstring)
    if b == "cmd":
        for j, a in enumerate(args):
            if a.lower() in ("/c", "/k", "/r"):
                check_command(" ".join(args[j + 1:]), depth + 1)
                return
        return
    if b in ("powershell", "pwsh"):
        for j, a in enumerate(args):
            if a.lower() in ("-c", "-command", "-commandwithargs"):
                check_command(" ".join(args[j + 1:]), depth + 1)
                return
        return
    if b == "find":
        for j, a in enumerate(args):
            if a in ("-exec", "-execdir", "-ok", "-okdir"):
                rest = []
                for x in args[j + 1:]:
                    if x in (";", "+", "\\;"):
                        break
                    rest.append(x)
                check_simple(rest, depth + 1)
            elif a == "-delete" and not MODE["script"]:
                deny("find_delete")
        return
    check_suite(b, args)

    if MODE["script"] and b in ("git", "rm"):   # negli script: repo e cartelle temporanee, codice revisionato
        return
    if b == "git":
        j, gdir = 0, None if MODE["gitenv"] else MODE["cwd"]
        while j < len(args):
            a = args[j]
            if a.startswith(("--git-dir", "--work-tree")) or (
                    a == "-c" and j + 1 < len(args) and args[j + 1].lower().startswith("core.worktree")):
                gdir = None   # repository o working tree spostati: directory ignota
            if a in GIT_OPT_WITH_ARG:
                if a == "-C" and j + 1 < len(args):
                    tgt = args[j + 1]
                    gdir = norm(tgt, gdir) if gdir and not re.search(r"[$`~*?]", tgt) else None
                j += 2
            elif a.startswith("-"):
                j += 1
            else:
                break
        if MODE["universal"] and j < len(args):
            sub, rest = args[j], args[j + 1:]
            if sub == "worktree" and rest and rest[0] in GIT_WORKTREE_SUB_OK:
                return
            if sub in GIT_WORKTREE_OK:
                if linked_worktree(gdir):
                    return
                deny("git_worktree", sub=sub, gdir=gdir or "sconosciuta")
        if j < len(args) and args[j] in GIT_DENY:
            deny("git_push" if args[j] == "push" else "git_stato", sub=args[j],
                 grave=args[j] in GRAVE_GIT or (args[j] == "checkout" and bool(GRAVE_CHECKOUT & set(args[j + 1:]))))
        if j < len(args) and args[j] in GIT_DENY_WITH and GIT_DENY_WITH[args[j]] & set(args[j + 1:]):
            deny("git_forza", grave=True, sub=args[j])
        if j < len(args) and args[j] in GRAVE_GIT and args[j] not in GIT_DENY:   # filter-branch
            deny("git_storia", grave=True, sub=args[j])
        return
    if b in REMOTE:
        deny("remoto", what=b)
    if b in ("docker", "docker-compose", "podman"):
        deny("docker", what=b)
    if b in ("psql", "pg_restore", "dropdb"):
        deny("db", what=b)
    if b in ("pip", "pip3", "npm", "pnpm", "yarn", "uv") and any(a in ("install", "i", "add", "ci") for a in args):
        deny("install", what=b + " " + next(a for a in args if a in ("install", "i", "add", "ci")))
    if b.startswith("python") and "-m" in args and any(a in ("pip", "ensurepip") for a in args) and "install" in args:
        deny("install", what="python -m pip install")
    if b == "rm":
        flags = "".join(a[1:] for a in args if a.startswith("-") and not a.startswith("--"))
        long = {a for a in args if a.startswith("--")}
        rec = "r" in flags.lower() or "--recursive" in long
        force = "f" in flags or "--force" in long
        if rec and force:
            deny("rm_rf", what="rm -rf")
    # PowerShell: Remove-Item (e alias) con -Recurse e -Force, anche abbreviati (-r, -fo)
    if b in ("remove-item", "ri", "rm", "del", "erase", "rd", "rmdir"):
        low = [a.lower() for a in args]
        if any(a.startswith("-r") for a in low) and any(a.startswith("-fo") for a in low):
            deny("rm_rf", what="Remove-Item -Recurse -Force")


def check_suite(b, args):
    """Fase `plan` (harness-pt04, 1f): niente suite complete. I runner del nucleo (pytest, vitest) e quelli dei
    comandi `test` dei moduli senza file o selettori espliciti → negato. Le suite del livello le esegue il driver
    (scripts/gates.sh del plugin) dopo implement/fix; una fase di piano verifica al massimo un file o un selettore."""
    if MODE["universal"] or os.environ.get("FIC_PHASE") not in SUITE_PHASES:
        return
    if b in ("npx", "pnpm", "yarn", "bunx") and args and base(args[0]) == "vitest":   # `npx vitest run`
        b, args = "vitest", args[1:]
    if (b.startswith("python") or b == "py") and "-m" in args:   # `python -m pytest …`
        k = args.index("-m")
        if k + 1 < len(args) and args[k + 1] == "pytest":
            b, args = "pytest", args[k + 2:]
    kind = CONF["suite"].get(b)
    if kind is None:
        return
    selected = pytest_selected(args) if kind == "pytest" else vitest_selected(args)
    if not selected:
        deny("suite", what=b, fase=os.environ.get("FIC_PHASE"))


# opzioni che prendono un valore (il valore non e' un selettore)
PYTEST_OPT_VAL = {"-p", "-c", "-o", "-W", "-n", "--rootdir", "--tb", "--maxfail", "--junitxml", "--junit-xml",
                  "--basetemp", "--confcutdir", "--durations", "--log-level", "--cov", "--cov-report",
                  "--deselect", "--ignore", "--ignore-glob", "--import-mode", "--capture"}
VITEST_OPT_VAL = {"--reporter", "--config", "-c", "--root", "-r", "--dir", "--project", "--environment",
                  "--pool", "--outputFile", "--mode", "--shard", "--maxWorkers", "--minWorkers",
                  "--testTimeout", "--bail", "--retry", "--silent"}
VITEST_SUBCOMMANDS = {"run", "watch", "dev", "related"}


def pytest_selected(args):
    """Un file .py, un node id (::) oppure -k/-m: selettori espliciti. Una cartella non lo e'."""
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-k", "-m") or re.match(r"^-[km]\S", a):
            return True
        if a in PYTEST_OPT_VAL:
            i += 2
            continue
        if not a.startswith("-") and (".py" in a or "::" in a):
            return True
        i += 1
    return False


def vitest_selected(args):
    """Un filtro posizionale (file o parte di nome) oppure -t/--testNamePattern."""
    i = 0
    if args and args[0] in VITEST_SUBCOMMANDS:
        i = 1
    while i < len(args):
        a = args[i]
        if a in ("-t", "--testNamePattern") or a.startswith(("-t=", "--testNamePattern=")):
            return True
        if a in VITEST_OPT_VAL:
            i += 2
            continue
        if not a.startswith("-"):
            return True
        i += 1
    return False


# Percorsi di Windows (Python di Windows, o di MSYS/Cygwin): lettere di unita' e confronto senza maiuscole. Altrove
# (Linux, pk08) percorsi POSIX: nessuna unita' (/c/… e /mnt/c/… restano cartelle) e maiuscole intatte, perche' il
# file system le distingue e il percorso normalizzato si usa anche per aprire file e per `git -C` (eccezione: il
# confronto dentro/fuori dal repo, piega_repo, per Mac e /mnt/<lettera>/).
WIN_PATHS = os.name == "nt" or sys.platform.startswith(("msys", "cygwin"))


def pfold(s):
    """Un percorso nella forma di confronto: minuscolo su Windows, com'e' altrove."""
    return s.lower() if WIN_PATHS else s


def piega_repo(r):
    """Review di pk08: fuori da Windows, il confronto «dentro/fuori dal repo» (check_scope, check_write) piega anche le
    maiuscole se il file system del repo puo' non distinguerle: Mac (APFS) e WSL su /mnt/<lettera>/ (drvfs). `r` e' il
    repo gia' normalizzato con norm. Solo la forma di confronto: norm resta la forma d'uso (open, `git -C`). Nel dubbio
    si piega, cioe' si nega. Su Windows norm piega gia': False, comportamento invariato."""
    return not WIN_PATHS and (sys.platform == "darwin" or bool(re.match(r"^/mnt/[a-zA-Z](/|$)", r)))


def rel_repo(p, r):
    """Il percorso di p relativo al repo r (forme di norm), o None se p e' fuori dal repo. La forma piegata (piega_repo)
    decide SOLO dentro/fuori; rel conserva le maiuscole di p (review giro 2 di pk08): corsia, FIC_SCOPE e cartella di
    lavoro si confrontano con le maiuscole originali, cosi' `A.TXT` non vale `a.txt` e `.Claude/.AI-workflow/` non vale
    come cartella di lavoro. Il prefisso del repo si toglie per lunghezza (coincide a meno delle maiuscole)."""
    if not piega_repo(r):
        return p[len(r) + 1:] if p == r or p.startswith(r + "/") else None
    pl, rl = p.lower(), r.lower()
    if not (pl == rl or pl.startswith(rl + "/")):
        return None
    if p[:len(r)].lower() == rl and (len(p) == len(r) or p[len(r)] == "/"):
        return p[len(r) + 1:]
    return p   # minuscolo di lunghezza diversa (Unicode): assoluto, non vale per nessuna voce relativa -> negato


def norm(p, cwd):
    p = p.replace("\\", "/")
    if WIN_PATHS:
        m = re.match(r"^/mnt/([a-zA-Z])/(.*)$", p) or re.match(r"^/([a-zA-Z])/(.*)$", p)
        if m:
            p = m.group(1) + ":/" + m.group(2)
        if not re.match(r"^[a-zA-Z]:/", p):
            p = cwd.replace("\\", "/").rstrip("/") + "/" + p
        drive, rest = p[:2], p[3:]
    else:
        if not p.startswith("/"):
            p = cwd.replace("\\", "/").rstrip("/") + "/" + p
        drive, rest = "", p[1:]
    parts = []
    for seg in rest.split("/"):
        if seg in ("", "."):
            continue
        if seg == "..":
            if parts:
                parts.pop()
        else:
            parts.append(seg)
    return pfold(drive + "/" + "/".join(parts))


def linked_worktree(d):
    """True se `d` sta in un worktree COLLEGATO (`git worktree add`): git-dir != git-common-dir.
    Il tree principale ha git-dir == git-common-dir. Directory ignota, git assente o errore → False."""
    if not d:
        return False
    env = {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR")}
    try:
        r = subprocess.run(["git", "-C", d, "rev-parse", "--path-format=absolute", "--git-dir",
                            "--git-common-dir"], capture_output=True, text=True, timeout=10, env=env)
    except (OSError, subprocess.SubprocessError):
        return False
    lines = [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]
    if r.returncode != 0 or len(lines) != 2:
        return False
    gd, cd = (os.path.normcase(os.path.normpath(x)) for x in lines)
    return gd != cd


def plugin_wrapper(p):
    """Passo 3-bis: p (gia' normalizzato con norm) e' un involucro del plugin sotto MAAT_ROOT/scripts/?"""
    root = os.environ.get("MAAT_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    root = root.replace("\\", "/").rstrip("/")
    return any(p == norm(root + "/scripts/" + n, root) for n in PLUGIN_WRAPPERS)


def check_script(path, depth):
    """--universal: `bash|sh <file>` con il file sotto script/ o .claude/ → stesse regole sul contenuto."""
    if depth > 6 or not MODE["cwd"] or re.search(r"[$`~*?]", path):
        return
    p = norm(path, MODE["cwd"])
    if not re.search(r"(^|/)(script|\.claude)/", p) or p.endswith(tuple(s for s, _b, _o in CONF["involucri"])):
        return
    if plugin_wrapper(p):
        return
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return
    saved = MODE["cwd"], MODE["script"]
    MODE["script"] = True
    try:
        check_command(executable_lines(text), depth + 1)
    finally:
        MODE["cwd"], MODE["script"] = saved


def executable_lines(text):
    """Righe eseguibili di uno script: senza commenti (`#` in testa) ne' corpi di heredoc di TESTO.
    Il corpo di un'heredoc data a una shell, a ssh o a Python resta (viene eseguito)."""
    out, end = [], None
    for line in text.splitlines():
        if end is not None:
            if line.strip() == end:
                end = None
            continue
        if line.lstrip().startswith("#"):
            continue
        out.append(line)
        m = HEREDOC_RE.search(line)
        pre = line[:m.start()] if m else ""
        # un `<<` fra virgolette e' testo, non un'heredoc (altrimenti si salterebbe il resto del file)
        if m and pre.count("'") % 2 == 0 and pre.count('"') % 2 == 0 and not HEREDOC_EXEC_RE.search(pre):
            end = m.group(2)
    return "\n".join(out)


def check_heredoc(cmd):
    """`python - <<EOF` che apre file in scrittura: byte invisibili (incidente 23/09). Si scrive con Write/Edit."""
    if PY_HEREDOC_RE.search(cmd) and PY_WRITE_RE.search(cmd):
        deny("heredoc_py")


def in_scope(rel):
    """Regola 5: rel (relativo al repo, nella forma di pfold) sta nello scope di FIC_SCOPE? Scope illeggibile -> no."""
    try:
        with open(os.environ.get("FIC_SCOPE") or "", encoding="utf-8") as f:
            entries = [pfold(ln.strip().replace("\\", "/")) for ln in f if ln.strip()]
    except OSError:
        return False
    for e in entries:
        e = e[2:] if e.startswith("./") else e
        if rel == e or (e.endswith("/") and rel.startswith(e)):
            return True
    return False


_LAVORO = {}


def lavoro(repo):
    """La cartella di lavoro del progetto, relativa al repo e con / finale: cartelle.lavoro della sua maat.json
    (maat_paths.py; default .claude/.ai-workflow), pk04a-1. Cache per processo: maat-config.py una volta per repo."""
    project = repo.replace("\\", "/").rstrip("/")
    if project in _LAVORO:
        return _LAVORO[project]
    sys.dont_write_bytecode = True   # nessun __pycache__ sotto MAAT_ROOT
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import maat_paths
    try:
        v = maat_paths.maat_work(project)[len(project) + 1:].rstrip("/") + "/"
    except maat_paths.ErroreMaat:   # plugin non risolto: il default dello schema
        v = maat_paths.LAVORO_DEFAULT + "/"
    _LAVORO[project] = v
    return v


def check_scope(path, data):
    """Corsia di implementazione (harness-pt13): FIC_WRITE_SCOPE = i file di `scrive:` dei suoi blocchi, separati
    da virgole, relativi al repo (una voce che finisce con / e' una cartella). Edit/Write dentro il repo solo su
    quei file e nella run dir (`<cartella di lavoro>/<x>.run/`); fuori dal repo (scratchpad) libero. Accanto alle
    regole per fase, come FIC_PHASE; --universal non la applica. Le scritture via Bash le vede il controllo a
    posteriori del driver (blocks-independent.py --posteriori)."""
    scope = [pfold(s.strip().replace("\\", "/")) for s in os.environ.get("FIC_WRITE_SCOPE", "").split(",")]
    scope = [s[2:] if s.startswith("./") else s for s in scope if s]
    if not scope or not path:
        return
    cwd = data.get("cwd") or os.getcwd()
    rel = rel_repo(norm(path, cwd), norm(os.environ.get("FIC_REPO") or cwd, cwd))
    if rel is None:
        return
    lav = lavoro(os.environ.get("FIC_REPO") or cwd)
    if re.match("^" + re.escape(lav) + r"[^/]+\.run/", rel):
        return
    if any(rel == s.rstrip("/") or (s.endswith("/") and rel.startswith(s)) for s in scope):
        return
    deny("corsia", what=rel, lane=os.environ.get("FIC_LANE", "?"))


def check_write(path, data):
    check_scope(path, data)
    phase = os.environ.get("FIC_PHASE", "")
    if (phase not in READONLY_PHASES and phase not in SCOPED_PHASES) or not path:
        return
    cwd = data.get("cwd") or os.getcwd()
    repo = os.environ.get("FIC_REPO") or cwd
    rel = rel_repo(norm(path, cwd), norm(repo, cwd))
    if rel is not None:
        if phase in SCOPED_PHASES:
            if not in_scope(rel):
                deny("scope_fase", what=rel, fase=phase)
            return
        lav = lavoro(repo)
        if not rel.startswith(lav):
            deny("lavoro_fase", what=rel, lav=lav, fase=phase)


def deny_list():
    """Voci di --disallowedTools per run-phase.sh: nucleo + guardia.rilascio (`bash x` e `x`) + guardia.vietati_extra."""
    voci = list(DENY_NUCLEO)
    for r in CONF["rilascio"]:
        voci += ["bash " + r, r]
    voci += CONF["vietati"]
    seen = set()
    for v in voci:
        if v not in seen:
            seen.add(v)
            print("Bash(%s:*)" % v)


def main():
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass
    MODE["universal"] = "--universal" in sys.argv[1:]
    load_config()
    if "--deny-list" in sys.argv[1:]:
        deny_list()
        sys.exit(0)
    try:
        data = json.load(sys.stdin)
    except ValueError:
        deny("input", grave=True)
    tool = data.get("tool_name", "")
    ti = data.get("tool_input") or {}
    if tool in SHELL_TOOLS:
        cmd = ti.get("command", "") or ""
        flat = cmd.replace("\\", "/")
        hit = next((r for r in CONF["rilascio"] if r.replace("\\", "/").lower() in flat.lower()), None)
        if hit:
            deny("rilascio", grave=True, what=hit)
        m = CONF["prod"].search(flat) if CONF["prod"] else None
        if m:
            deny("produzione", grave=True, what=m.group(0))
        if CONF["stato"]:   # maat.json assente o non valido: ogni host o dominio fuori da localhost e' grave
            h = next((x.group(0) for x in HOST_RE.finditer(flat) if not x.group(0).startswith("127.")), None)
            if h:
                deny("config_" + CONF["stato"], grave=True, what=h)
        if os.environ.get("FIC_PHASE"):   # sotto-sessione: i prefissi vietati dal progetto, come --disallowedTools
            v = next((p for p in CONF["vietati"] if cmd.lstrip().startswith(p)), None)
            if v:
                deny("vietato_extra", what=v)
        check_heredoc(cmd)
        MODE["cwd"] = norm(data.get("cwd") or os.getcwd(), os.getcwd())
        MODE["gitenv"] = bool(GIT_ENV_RE.search(cmd))
        if tool == "PowerShell":   # in PowerShell `\` e' un separatore di percorso, non un escape
            cmd = cmd.replace("\\", "/")
        check_command(cmd)
    elif MODE["universal"]:
        pass   # le regole per fase (FIC_PHASE) valgono solo nelle sottosessioni
    elif tool in WRITE_TOOLS:
        check_write(ti.get("file_path") or ti.get("notebook_path") or "", data)
    sys.exit(0)


if __name__ == "__main__":
    main()
