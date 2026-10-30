#!/usr/bin/env python3
r"""guard.py — command guard: PreToolUse hook of the sub-sessions and (with --universal) of the session.

Sub-sessions run in bypassPermissions (the only way writes under .claude/ go through) with a
PREFIX deny, which a command wrapped in `wsl -- bash -lc '...'` bypasses (measured). This hook
looks at the WHOLE command, inside the wrappers, and denies (exit 2, reason on stderr) a CLOSED list of
irreversible actions. It is not a sandbox: what stays uncovered is written in riferimento.md, section
"Sub-session permissions".

TWO LAYERS OF RULES (R3.6, pk05):
  CORE, always active and generic: state-changing git (with the rules on linked worktrees), GRAVE_GIT,
     `rm -rf` and `Remove-Item -Recurse -Force`, Python heredocs that write, package installs, direct remote
     access (ssh/scp/sftp/rsync), docker, psql; the phase rules (writes only in the work folder
     for the read-only phases, whole suites forbidden in plan/test-red/test-stage).
  PROJECT, from maat.json -> guardia:
     produzione    regex (case-insensitive) on the whole command text: always GRAVE, even with the reduced guard;
     rilascio      release scripts, matched as a SUBSTRING of the command: always denied, always GRAVE; in
                   the content of a script they count as a command, like produzione;
     involucri     scripts that wrap remote access or the local copy: allowed and not read; their
                   opzioni_negate are always GRAVE (run directly or with `bash …`);
     vietati_extra command prefixes denied in sub-sessions (the same ones go to --disallowedTools);
     suite         project suite scripts ({script, selettori: pytest|vitest}), denied without files or selectors like the runners;
     the whole suite of rule 4: the runners of the modules' `test` commands and guardia.suite, besides pytest and vitest.
  The file: MAAT_CONFIG (sub-sessions get it from run-phase.sh, absolute path), otherwise
  <CLAUDE_PROJECT_DIR>/.claude/maat.json (Claude Code provides the variable to hooks; never from the command's cwd).
  Missing, unreadable or invalid: the core stays, and every command containing a host or a domain other than
  localhost is GRAVE (fail-closed): «maat.json non trovato» / «maat.json non valido».

  1. Project, first of all and on the whole command text: rilascio and produzione.
  2. Tools only in COMMAND POSITION (after ; && || | & ( and the keywords do/then/else/{/!,
     inside bash -c / -lc (also with -o pipefail), $( ), ``, xargs, find -exec, cmd /c, powershell -c):
     direct ssh/scp/sftp/rsync (go through the wrappers), state-changing git, docker, psql, package
     installs, forced recursive rm. So `git show <Base>:docker-compose.yml > docker-compose.yml` or
     `git status && rm f` pass. The wrappers' payload is NOT analysed.
  3. Phases `plan`/`review`/`probe` (FIC_PHASE): Edit/Write/NotebookEdit inside the repo only under
     the work folder (cartelle.lavoro in maat.json, default `.claude/.ai-workflow/`). Outside the repo (scratchpad) it is free.
  3b. Implementation lane (FIC_WRITE_SCOPE, harness-pt13): Edit/Write inside the repo only on the files in
     `scrive:` of the lane's blocks and in the run dir (check_scope). It adds to rule 5: with FIC_WRITE_SCOPE
     and FIC_SCOPE both set a write must satisfy both (check_write applies them in sequence).
  4. Phase `plan`: no full suites — pytest, vitest and the runners of the modules' `test` commands without explicit
     files or selectors (-k/-m for pytest, -t for vitest) denied, also inside wsl/bash -c (check_suite). The level's
     suites are run by the driver (the plugin's scripts/gates.sh) after implement/fix.
  5. Phases `test-red` and `test-stage` (harness-pt11): Edit/Write inside the repo only on the SCOPE paths, the file
     given by FIC_SCOPE (one per line, relative to the repo; a line ending with / acts as a prefix):
     test-red = the plan's test files + the files the plan declares new (stubs); test-stage = only
     <run-dir>/staging/. Scope missing or unreadable: everything denied. No full suites, as in `plan`.

WHAT STAYS UNCOVERED, by choice (no sandbox on native Windows; every test goes through `wsl bash -lc`,
so a real capability allowlist is not applicable here): obfuscated commands (base64, variables
built at runtime, scripts written to a file and then run, a Python program that opens a
connection); files written with Bash in the read-only phases; the wrappers' payload.
A hook that FAILS (exception, missing interpreter) lets the call through: it is fail-open. That is why
run-phase.sh does not start the sub-session if the self-test does not get the denial (exit 5). The plugin hook
(scripts/guard-hook.sh) instead treats an exit other than 0/2, or missing Python, as "ask" (denies with FIC_PHASE).

--universal MODE (SESSION guard, plugin hook hooks/hooks.json -> guard-hook.sh): only rules
1-2, no per-phase rules. Differences: `git commit`/`checkout`/`add` allowed only INSIDE a linked worktree
(`git rev-parse --git-dir` != `--git-common-dir`; the directory is the hook's `cwd`, followed through `cd <dir>` and
`git -C <dir>`; unknown → denied), never in the main tree; `git worktree add|list` allowed; push/reset/rebase/stash
and the rest stay denied everywhere.
In addition `bash|sh <file>` with the file under script/ or .claude/ reads the EXECUTABLE lines of the file (without
comments or text heredoc bodies) and applies only the remote and infrastructure rules: ssh/scp/
sftp/rsync, docker, psql, installs, the wrappers' denied options, and produzione only as a command
(release script) or as an argument of a network command (ssh, curl, ...), not in an echo. Not git nor `rm -rf`:
scripts work on repos and temporary folders and are reviewed code. Neither the project's wrappers
nor the plugin's wrappers are read (PLUGIN_WRAPPERS under MAAT_ROOT/scripts/, matched by resolved absolute
path, also in the WSL /mnt/<drive>/ form).
In both modes: a Python heredoc (`python - <<`, `py -3 - <<`) that opens a file for writing
(open(..., 'w'|'a'), write_text, write_bytes) is denied.

Git directory in --universal: `--git-dir`/`--work-tree`/`-c core.worktree`, GIT_DIR/GIT_WORK_TREE
in the command, pushd/popd/Push-Location → unknown (so not allowed). A `cd` inside `( … )`, `$( )`,
`bash -c`, `wsl [--cd x] -- bash -lc`, `cmd /c`, `powershell -c` does not apply to the commands that follow.
Tools analysed: Bash and PowerShell (in PowerShell `\` is a separator; Remove-Item -Recurse -Force).

REASONS (R11): every answer has three parts, separated by « — »: <what was recognised, starting from the command> —
<core|project rule, which one> — <what to do if it is intended>. Single MSG table, in it and en; the language comes
from maat.json -> lingua (missing, not in the table, maat.json invalid or missing: en).

Usage: stdin = PreToolUse JSON. Sub-sessions: exit 0 = allowed, 2 = denied (reason on stderr).
`--universal` = session guard: in the main session (empty FIC_PHASE) instead of denying it ASKS FOR
CONFIRMATION (JSON `hookSpecificOutput.permissionDecision: "ask"` on stdout, exit 0); with FIC_PHASE
set (sub-session) it denies as always. `--deny-list`: prints the --disallowedTools entries for
run-phase.sh (core, rilascio, vietati_extra), one per line. Tests: guard.test.sh.
REDUCED GUARD: with FIC_SESSION_GUARD=prod (env block of .claude/settings.local.json) the main session
asks for confirmation ONLY for GRAVE actions: produzione, rilascio, wrappers' denied options, maat.json
missing or invalid with a host in the command, git push/reset/rebase/clean/restore/filter-branch/update-ref,
`checkout` that discards changes (`--`, `.`, `-f`), branch/tag with deletion or force, unreadable input. The
rest (commit, branch checkout, merge, installs, docker, ssh, rm -rf, heredocs) passes. Sub-sessions
(FIC_PHASE set) always apply the full rules.
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
# subcommands harmless when reading, destructive with certain options
GIT_DENY_WITH = {"branch": {"-d", "-D", "--delete", "-m", "-M", "--move", "-f", "--force"},
                 "tag": {"-d", "--delete", "-f", "--force"}}
KEYWORDS = {"do", "then", "else", "elif", "if", "while", "until", "{", "}", "!", "[[", "]]"}
GIT_OPT_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
SHELLS = {"bash", "sh", "zsh", "dash", "fish"}
WRAPPERS = {"env", "exec", "sudo", "nohup", "time", "command", "builtin", "nice"}
OPERATORS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;"}
WRITE_TOOLS = {"Edit", "Write", "NotebookEdit", "MultiEdit"}
READONLY_PHASES = {"plan", "review", "probe"}
# phases with their own write scope (FIC_SCOPE, rule 5) and without full suites (rule 4)
SCOPED_PHASES = {"test-red", "test-stage"}
SUITE_PHASES = {"plan"} | SCOPED_PHASES
# --universal: git subcommands allowed only INSIDE a linked worktree (git-dir != git-common-dir),
# never in the main tree; `worktree add`/`worktree list` allowed everywhere. push/reset/rebase/stash and
# the rest of GIT_DENY stay denied everywhere.
GIT_WORKTREE_OK = {"commit", "checkout", "add"}
GIT_WORKTREE_SUB_OK = {"add", "list"}
# `python - <<` / `py -3 - <<` (also .exe with a path): Python heredoc
PY_HEREDOC_RE = re.compile(r"(?:^|[\s;&|(/\\])(?:python[0-9.]*|py)(?:\.exe)?(?:\s+-[-\w.]+)*\s+-?\s*<<")
# open(..., 'w') on the same line, without relying on parentheses: open(os.path.join(d, "f"), "w")
PY_WRITE_RE = re.compile(r"""open\s*\(.*?,\s*(mode\s*=\s*)?['"][wax][bt+]*['"]|write_text|write_bytes""")
MODE = {"universal": False, "cwd": None, "script": False, "gitenv": False}
# variables that move the repository or working tree: with these the git directory is unknown
GIT_ENV_RE = re.compile(r"GIT_(DIR|WORK_TREE|COMMON_DIR|INDEX_FILE)\b", re.IGNORECASE)
CD_LIKE = {"cd", "chdir", "set-location", "sl"}
CD_UNKNOWN = {"pushd", "popd", "push-location", "pop-location"}
SHELL_TOOLS = {"Bash", "PowerShell"}
# network commands: in the content of a script, produzione counts only as their argument (or as a command)
NET_TOOLS = {"ssh", "scp", "sftp", "rsync", "curl", "wget", "http", "https", "nc", "ncat", "telnet", "ping"}
# heredoc: `<<EOF`, `<<-'EOF'`, `<< "EOF"` (not `<<<`)
HEREDOC_RE = re.compile(r"(?<!<)<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
HEREDOC_EXEC_RE = re.compile(r"(^|[\s;&|(/\\])(bash|sh|zsh|dash|ssh|python[0-9.]*|py)(\.exe)?(\s|$)")
# PLUGIN wrappers (step 3-bis): allowed by resolved absolute path under MAAT_ROOT/scripts/, also inside
# `wsl -- bash -lc '…'`. Not fic-mirror.sh: it is a library sourced by the wrappers, it is not run on its own.
PLUGIN_WRAPPERS = ("test-fast.sh", "counterproof.sh", "vitest-fast.sh")
# Full suites (rule 4), core: known runners. The project's ones come from the modules' `test` commands and from
# guardia.suite (project suite scripts, with the pytest or vitest selection rules).
SUITE_NUCLEO = {"pytest": "pytest", "py.test": "pytest", "vitest": "vitest"}
# Fail-closed without a valid maat.json: a host (name with a dot) or an IPv4 in the command. localhost has no dots.
HOST_RE = re.compile(r"(?<![\w.-])(?:\d{1,3}(?:\.\d{1,3}){3}|(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z][a-z0-9-]*)"
                     r"(?![\w-])", re.IGNORECASE)
# --deny-list: core prefixes for --disallowedTools (the sub-sessions' prefix deny)
DENY_NUCLEO = ("ssh", "scp", "sftp", "rsync", "git commit", "git push", "git reset", "git checkout", "git switch",
               "git clean", "git stash", "git rebase", "git merge", "git restore", "docker", "psql", "pip install",
               "npm install", "rm -rf")


# REDUCED session guard (FIC_SESSION_GUARD=prod, in the env block of .claude/settings.local.json): in the
# main session only (--universal without FIC_PHASE) it asks for confirmation only for GRAVE actions (see docstring).
# Sub-sessions (FIC_PHASE set) never see it.
GRAVE_GIT = {"push", "reset", "rebase", "clean", "update-ref", "filter-branch", "restore"}
# `git checkout` that discards uncommitted changes (irreversible): `-- <path>`, `.`, `-f/--force`
GRAVE_CHECKOUT = {"--", ".", "-f", "--force"}

# ------------------------------------------------------------------------------------------- reasons (R11)
# One entry per rule: (what was recognised, rule, what to do). The variable parts ({...}) are ONLY
# in the first part, which starts with the recognised command; « — » separates the three parts and never appears in values.
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

# Project rules (load_config). stato: None = valid maat.json, "assente", "non_valido".
CONF = {"stato": "assente", "lingua": "en", "prod": None, "rilascio": [], "involucri": [], "vietati": [],
        "suite": dict(SUITE_NUCLEO)}


def reason(key, **kw):
    """The three-part reason, in the maat.json language (it if missing, not in the table or with an invalid maat.json)."""
    voci = MSG[key]
    t = voci.get(CONF["lingua"]) or voci["it"]
    vals = {k: str(v).replace("—", "-") for k, v in kw.items()}   # « — » only as the separator
    return SEP.join((t[0].format(**vals), t[1], t[2]))


def reduced():
    return (MODE["universal"] and not os.environ.get("FIC_PHASE")
            and os.environ.get("FIC_SESSION_GUARD", "").strip().lower() == "prod")


def deny(key, grave=False, **kw):
    """Sub-sessions (also with --universal, if FIC_PHASE is set): denial, exit 2.
    Main session (--universal without FIC_PHASE): asks the user for confirmation (permissionDecision
    "ask" in the JSON on stdout, exit 0). With the reduced guard (reduced()) a non-grave denial asks
    nothing: it returns and the checks go on (a grave action later in the same command asks)."""
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
    """MAAT_CONFIG, otherwise <CLAUDE_PROJECT_DIR>/.claude/maat.json; never from the command's cwd."""
    p = os.environ.get("MAAT_CONFIG")
    if p:
        return p
    pd = os.environ.get("CLAUDE_PROJECT_DIR")
    return os.path.join(pd, ".claude", "maat.json") if pd else None


def runner_of(txt):
    """The runner of a test command: `{python} -m pytest …` → pytest, `bash {maat}/scripts/x.sh …` → x.sh."""
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
    sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
    try:
        spec = importlib.util.spec_from_file_location(
            "maat_config", os.path.join(os.path.dirname(os.path.abspath(__file__)), "maat-config.py"))
        mc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mc)
    except Exception:   # reader missing or broken: no project rules, fail-closed
        CONF["stato"] = "non_valido"
        return
    saved, sys.stderr = sys.stderr, io.StringIO()   # the reader's errors do not go to the hook's channel
    try:
        cfg, _p = mc.carica(path)
        g = cfg.get("guardia", {}) or {}
        prod = [r for r in g.get("produzione", []) if r]
        CONF["prod"] = re.compile("|".join("(?:%s)" % r for r in prod), re.IGNORECASE) if prod else None
    except mc.Uscita as u:
        CONF["stato"] = "assente" if u.codice == 4 else "non_valido"
        return
    except Exception:   # invalid regex, unreadable file
        CONF["stato"] = "non_valido"
        return
    finally:
        sys.stderr = saved
    CONF["stato"] = None
    CONF["lingua"] = cfg.get("lingua") if cfg.get("lingua") in ("it", "en") else "en"
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
    """The produzione or rilascio text found in s (slashes already forward), or None."""
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
    """Simple commands (token lists) of a shell line; crude fallback if shlex fails.
    With marks=True the parentheses appear as "(" / ")" strings: they delimit subshells."""
    out = []
    for line in cmd.splitlines() or [cmd]:
        try:
            lex = shlex.shlex(line, posix=True, punctuation_chars=";&|()")
            lex.whitespace_split = True
            lex.commenters = ""
            toks = list(lex)
        except ValueError:  # unbalanced quotes: split everything, which is conservative
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
    """Content of $( ... ) and `...`: they are executed, so they are analysed as commands."""
    return re.findall(r"\$\(([^()]*)\)", cmd) + re.findall(r"`([^`]*)`", cmd)


def check_command(cmd, depth=0):
    if depth > 6:
        return
    for inner in substitutions(cmd):   # $( ) and ``: subshell, a `cd` inside does not leak out
        saved = MODE["cwd"]
        check_command(inner, depth + 1)
        MODE["cwd"] = saved
    stack = []
    for item in split_simple(cmd, marks=True):
        if item == "(":
            stack.append(MODE["cwd"])
        elif item == ")":
            if stack:
                MODE["cwd"] = stack.pop()   # `( cd x; … )`: the directory goes back to the previous one
        else:
            check_simple(item, depth)


def check_simple(toks, depth):
    """One simple command. Only `cd` (and similar) and `eval` change the directory for the commands that
    follow: `bash -c 'cd x'`, `wsl --cd x …`, `cmd /c`, `powershell -c` run in another process."""
    saved = MODE["cwd"]
    if not _check_simple(toks, depth):
        MODE["cwd"] = saved


def involucro_negato(name, args):
    """A project wrapper run with a denied option (guardia.involucri): always grave."""
    for _path, b, opts in CONF["involucri"]:
        if name == b:
            hit = [o for o in opts if o in args]
            if hit:
                deny("involucro_opzione", grave=True, what=f"{b} {hit[0]}")


def _check_simple(toks, depth):
    i = 0
    # VAR=... assignments and wrappers
    while i < len(toks):
        t, b = toks[i], base(toks[i])
        if t in KEYWORDS:   # `for f in x; do git …`, `if …; then git …`, `{ git …; }`, `! git …`
            i += 1
        elif b in ("for", "case", "select"):   # `for f in a b` runs nothing: the body comes after `do`
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
                if opt == "--cd" and MODE["universal"]:   # applies to this command only (check_simple)
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
            i += 1  # the duration
        else:
            break
    if i >= len(toks):
        return
    b, args = base(toks[i]), toks[i + 1:]

    if b in CD_LIKE and MODE["universal"]:   # `cd <wt> && git commit`: the directory of the git that follows
        tgt = next((a for a in args if not a.startswith("-")), "")
        MODE["cwd"] = (norm(tgt, MODE["cwd"]) if MODE["cwd"] and tgt and not re.search(r"[$`~*?]", tgt)
                       else None)
        return True
    if b in CD_UNKNOWN and MODE["universal"]:   # directory stack: not followed, directory unknown
        MODE["cwd"] = None
        return True
    if MODE["script"]:   # content of a script: produzione counts as a command or as the host of a network command
        cmd0 = toks[i].replace("\\", "/")   # a command has the shape of a path: no spaces or parentheses
        hit = prod_hit(cmd0) if re.fullmatch(r"[\w./:~-]+", cmd0) else None
        if not hit and b in NET_TOOLS | SHELLS:
            hit = next((h for h in (prod_hit(a.replace("\\", "/")) for a in args) if h), None)
        if hit:
            deny("produzione_script", grave=True, what=hit)
    involucro_negato(b, args)   # run directly; with `bash …` SHELLS sees it
    if b == "eval":   # runs in the current shell: a `cd` inside also applies afterwards
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
                if a[-1] in "oO":   # `-euo pipefail`: the last letter takes an argument
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
        return  # sub-sessions: `bash script.sh ...` is not analysed (see docstring)
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

    if MODE["script"] and b in ("git", "rm"):   # in scripts: repos and temporary folders, reviewed code
        return
    if b == "git":
        j, gdir = 0, None if MODE["gitenv"] else MODE["cwd"]
        while j < len(args):
            a = args[j]
            if a.startswith(("--git-dir", "--work-tree")) or (
                    a == "-c" and j + 1 < len(args) and args[j + 1].lower().startswith("core.worktree")):
                gdir = None   # repository or working tree moved: directory unknown
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
    # PowerShell: Remove-Item (and aliases) with -Recurse and -Force, also abbreviated (-r, -fo)
    if b in ("remove-item", "ri", "rm", "del", "erase", "rd", "rmdir"):
        low = [a.lower() for a in args]
        if any(a.startswith("-r") for a in low) and any(a.startswith("-fo") for a in low):
            deny("rm_rf", what="Remove-Item -Recurse -Force")


def check_suite(b, args):
    """Phase `plan` (harness-pt04, 1f): no full suites. The core runners (pytest, vitest) and those of the modules'
    `test` commands without explicit files or selectors → denied. The level's suites are run by the driver
    (the plugin's scripts/gates.sh) after implement/fix; a plan phase checks at most one file or one selector."""
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


# options that take a value (the value is not a selector)
PYTEST_OPT_VAL = {"-p", "-c", "-o", "-W", "-n", "--rootdir", "--tb", "--maxfail", "--junitxml", "--junit-xml",
                  "--basetemp", "--confcutdir", "--durations", "--log-level", "--cov", "--cov-report",
                  "--deselect", "--ignore", "--ignore-glob", "--import-mode", "--capture"}
VITEST_OPT_VAL = {"--reporter", "--config", "-c", "--root", "-r", "--dir", "--project", "--environment",
                  "--pool", "--outputFile", "--mode", "--shard", "--maxWorkers", "--minWorkers",
                  "--testTimeout", "--bail", "--retry", "--silent"}
VITEST_SUBCOMMANDS = {"run", "watch", "dev", "related"}


def pytest_selected(args):
    """A .py file, a node id (::) or -k/-m: explicit selectors. A folder is not one."""
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
    """A positional filter (file or part of a name) or -t/--testNamePattern."""
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


# Windows paths (Windows Python, or MSYS/Cygwin): drive letters and case-insensitive comparison. Elsewhere
# (Linux, pk08) POSIX paths: no drives (/c/… and /mnt/c/… stay folders) and case kept, because the
# file system distinguishes it and the normalised path is also used to open files and for `git -C` (exception: the
# inside/outside-the-repo comparison, piega_repo, for Mac and /mnt/<letter>/).
WIN_PATHS = os.name == "nt" or sys.platform.startswith(("msys", "cygwin"))


def pfold(s):
    """A path in comparison form: lowercase on Windows, as is elsewhere."""
    return s.lower() if WIN_PATHS else s


def piega_repo(r):
    """pk08 review: outside Windows, the «inside/outside the repo» comparison (check_scope, check_write) also folds
    case if the repo's file system may not distinguish it: Mac (APFS) and WSL on /mnt/<letter>/ (drvfs). `r` is the
    repo already normalised with norm. Only the comparison form: norm stays the usage form (open, `git -C`). When in doubt
    it folds, i.e. denies. On Windows norm already folds: False, behaviour unchanged."""
    return not WIN_PATHS and (sys.platform == "darwin" or bool(re.match(r"^/mnt/[a-zA-Z](/|$)", r)))


def rel_repo(p, r):
    """The path of p relative to the repo r (norm forms), or None if p is outside the repo. The folded form (piega_repo)
    decides ONLY inside/outside; rel keeps the case of p (pk08 review, round 2): lane, FIC_SCOPE and work
    folder are compared with the original case, so `A.TXT` does not match `a.txt` and `.Claude/.AI-workflow/` does not count
    as the work folder. The repo prefix is stripped by length (it matches up to case)."""
    if not piega_repo(r):
        return p[len(r) + 1:] if p == r or p.startswith(r + "/") else None
    pl, rl = p.lower(), r.lower()
    if not (pl == rl or pl.startswith(rl + "/")):
        return None
    if p[:len(r)].lower() == rl and (len(p) == len(r) or p[len(r)] == "/"):
        return p[len(r) + 1:]
    return p   # lowercase of different length (Unicode): absolute, matches no relative entry -> denied


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
    """True if `d` is in a LINKED worktree (`git worktree add`): git-dir != git-common-dir.
    The main tree has git-dir == git-common-dir. Unknown directory, missing git or error → False."""
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
    """Step 3-bis: is p (already normalised with norm) a plugin wrapper under MAAT_ROOT/scripts/?"""
    root = os.environ.get("MAAT_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    root = root.replace("\\", "/").rstrip("/")
    return any(p == norm(root + "/scripts/" + n, root) for n in PLUGIN_WRAPPERS)


def check_script(path, depth):
    """--universal: `bash|sh <file>` with the file under script/ or .claude/ → same rules on its content."""
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
    """Executable lines of a script: without comments (leading `#`) or TEXT heredoc bodies.
    The body of a heredoc fed to a shell, to ssh or to Python stays (it is executed)."""
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
        # a quoted `<<` is text, not a heredoc (otherwise the rest of the file would be skipped)
        if m and pre.count("'") % 2 == 0 and pre.count('"') % 2 == 0 and not HEREDOC_EXEC_RE.search(pre):
            end = m.group(2)
    return "\n".join(out)


def check_heredoc(cmd):
    """`python - <<EOF` that opens files for writing: invisible bytes (incident 23/09). Write with Write/Edit."""
    if PY_HEREDOC_RE.search(cmd) and PY_WRITE_RE.search(cmd):
        deny("heredoc_py")


def in_scope(rel):
    """Rule 5: is rel (relative to the repo, in pfold form) in the FIC_SCOPE scope? Unreadable scope -> no."""
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
    """The project's work folder, relative to the repo and with a trailing /: cartelle.lavoro of its maat.json
    (maat_paths.py; default .claude/.ai-workflow), pk04a-1. Per-process cache: maat-config.py once per repo."""
    project = repo.replace("\\", "/").rstrip("/")
    if project in _LAVORO:
        return _LAVORO[project]
    sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import maat_paths
    try:
        v = maat_paths.maat_work(project)[len(project) + 1:].rstrip("/") + "/"
    except maat_paths.ErroreMaat:   # plugin not resolved: the schema default
        v = maat_paths.LAVORO_DEFAULT + "/"
    _LAVORO[project] = v
    return v


def check_scope(path, data):
    """Implementation lane (harness-pt13): FIC_WRITE_SCOPE = the files in `scrive:` of its blocks, separated
    by commas, relative to the repo (an entry ending with / is a folder). Edit/Write inside the repo only on
    those files and in the run dir (`<work folder>/<x>.run/`); outside the repo (scratchpad) free. Alongside the
    per-phase rules, like FIC_PHASE; --universal does not apply it. Writes via Bash are seen by the driver's
    after-the-fact check (blocks-independent.py --posteriori)."""
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
    """--disallowedTools entries for run-phase.sh: core + guardia.rilascio (`bash x` and `x`) + guardia.vietati_extra."""
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
        if CONF["stato"]:   # maat.json missing or invalid: every host or domain other than localhost is grave
            h = next((x.group(0) for x in HOST_RE.finditer(flat) if not x.group(0).startswith("127.")), None)
            if h:
                deny("config_" + CONF["stato"], grave=True, what=h)
        if os.environ.get("FIC_PHASE"):   # sub-session: the prefixes forbidden by the project, as in --disallowedTools
            v = next((p for p in CONF["vietati"] if cmd.lstrip().startswith(p)), None)
            if v:
                deny("vietato_extra", what=v)
        check_heredoc(cmd)
        MODE["cwd"] = norm(data.get("cwd") or os.getcwd(), os.getcwd())
        MODE["gitenv"] = bool(GIT_ENV_RE.search(cmd))
        if tool == "PowerShell":   # in PowerShell `\` is a path separator, not an escape
            cmd = cmd.replace("\\", "/")
        check_command(cmd)
    elif MODE["universal"]:
        pass   # the per-phase rules (FIC_PHASE) apply only in sub-sessions
    elif tool in WRITE_TOOLS:
        check_write(ti.get("file_path") or ti.get("notebook_path") or "", data)
    sys.exit(0)


if __name__ == "__main__":
    main()
