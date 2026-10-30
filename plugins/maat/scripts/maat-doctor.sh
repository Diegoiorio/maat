#!/usr/bin/env bash
# maat-doctor.sh — what Maat is missing in this project, WITHOUT CHANGING ANYTHING (pk06, R5).
#
# Usage (from the project folder):
#   bash <maat>/scripts/maat-doctor.sh                 all checks, read-only
#   bash <maat>/scripts/maat-doctor.sh --prova-test    also runs the test command of each module on ONE test file
#                                                      chosen by the module's rule. WARNING: with this option
#                                                      the doctor is no longer read-only, because the test command
#                                                      can write cache and coverage files (`cache e coverage`) to the project.
#   bash <maat>/scripts/maat-doctor.sh --piattaforma   one line: windows-wsl | windows-senza-wsl | altro (used by
#                                                      /maat:setup to propose the nativo environment); read-only
#
# One line per check: «OK|ATTENZIONE|MANCA <cosa> — <come si risolve>», then «maat-doctor: <n> OK, <n> ATTENZIONE,
# <n> MANCA». Exit: 0 no MANCA · 1 at least one MANCA · 64 wrong usage.
#
# Checks:
#   versions       bash >= 4, Python >= 3.10 (python.sh), git >= 2.35, Claude Code (CLAUDE_BIN, then the VS Code
#                  extension, then PATH: the order of run-phase.sh): below the version tested in pk01 ATTENZIONE; not
#                  found ATTENZIONE «versione non verificata»
#   configuration  maat.json present and valid (maat-config.py valida), plugin version compatible with `harness`
#   WSL            Windows only (uname/OSTYPE, like run_cp of run-phase.sh: never the presence of wsl.exe). WSL missing
#                  = wsl.exe not on PATH, or `wsl -- true` failed or took longer than MAAT_DOCTOR_WSL_TIMEOUT seconds (30).
#                  copia_wsl auto without wsl modules -> OK «WSL assente»; copia_wsl sì -> MANCA; every module with
#                  `ambiente: wsl` -> MANCA. With WSL: bash and Node in WSL, the copy of the wsl modules with `copia`
#                  (node_modules and .fic-deps, like test-fast.sh; a worktree without its own copy but with the main
#                  tree's copy ready -> ATTENZIONE «si seminerà al primo uso»; otherwise MANCA: test-fast.sh --setup)
#   modules        first executable of comandi, controlli (with se_presente: ATTENZIONE «controllo saltato») and
#                  controprova (runner comando): after env assignments and options, and after a builtin command
#                  (`cd x && ./run.sh`) the one following && or ;, relative to the folder of the cds; looked up where the module
#                  runs (nativo: here; wsl: inside WSL, also an absolute path outside /mnt/ with [ -x ]); folder
#                  of the commands; {python} like gates.sh (nativo: the precedence of maat-config.py; wsl: the candidates
#                  inside WSL; missing: MANCA and the command using it gets no OK line); preparati (guide file), copia_anche (MANCA), collega_nel_worktree and file_dipendenze
#                  (ATTENZIONE); where the counterproofs run sha256sum, timeout, rsync or tar (ATTENZIONE: BLOCKED),
#                  rsync/flock missing -> OK «di ripiego, più lenti» (pk08); first executable of
#                  contesto.schema_db_comando and verifica_remota (MANCA), guardia.suite scripts (ATTENZIONE)
#   guard          only after a successful `valida`: `git push --force origin prova` and the production probe
#                  (maat-config.py sonda-produzione) denied in a phase (exit 2) and asked in the session (ask); every probe
#                  covered by a guardia.produzione regex (MANCA), every regex exercised by a probe (ATTENZIONE);
#                  guard hooked up (plugin enabled in enabledPlugins, or project PreToolUse hook with guard.py),
#                  duplicate hook and marketplace from a folder (ATTENZIONE)
#   work folder    cartelle.lavoro exists and is writable; whether it is ignored by git
#
# Read-only: no temporary files, PYTHONDONTWRITEBYTECODE=1 (the imports of maat-config.py do not write
# __pycache__ into the plugin). The Python code is at the end of this file and reaches the interpreter through a pipe.
# Variables: MAAT_CONFIG (the maat.json, like maat-config.py) · FIC_REPO (project root) · FIC_PYTHON (python.sh)
# · CLAUDE_BIN · MAAT_DOCTOR_WSL_TIMEOUT. Test: maat-doctor.test.sh.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1 PYTHONIOENCODING=utf-8 PYTHONUTF8=1
SELF=${BASH_SOURCE[0]}
HERE=$(cd "$(dirname "$SELF")" && pwd)
CLAUDE_MIN=2.1.285   # the version tested in pk01
usage() { sed -n '2,/^set -uo/p' "$SELF" | sed '$d; s/^# \{0,1\}//'; }

prova=0 piattaforma=0
for a in "$@"; do
  case $a in
    --prova-test) prova=1 ;;
    --piattaforma) piattaforma=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "maat-doctor: opzione sconosciuta: $a (--prova-test | --piattaforma | --help)" >&2; exit 64 ;;
  esac
done

winp() { local o; o=$(cygpath -m "$1" 2>/dev/null) && [ -n "$o" ] && { printf '%s' "${o#//\?/}"; return; }; printf '%s' "$1"; }
is_windows() { case "${OSTYPE:-}:$(uname -s 2>/dev/null)" in *msys*|*cygwin*|*:MINGW*|*:MSYS*|*:CYGWIN*) return 0 ;; esac; return 1; }
ver_ge() { # <version> <minimum>: 0 if version >= minimum (numeric components, up to three)
  local IFS=. i x y
  local -a a b
  read -ra a <<< "$1"; read -ra b <<< "$2"
  for i in 0 1 2; do
    x=${a[i]:-0} y=${b[i]:-0}; x=${x//[!0-9]/} y=${y//[!0-9]/}
    ((10#${x:-0} > 10#${y:-0})) && return 0
    ((10#${x:-0} < 10#${y:-0})) && return 1
  done
  return 0
}

MAAT_ROOT=$(winp "$(cd "$HERE/.." && pwd)")
export MAAT_ROOT MAAT_CONFIG_PY="$MAAT_ROOT/scripts/maat-config.py"
DR_WIN=0; is_windows && DR_WIN=1
DR_BASH=$(winp "$BASH")
export DR_WIN DR_BASH DR_PROVA=$prova
py_ok=""
if . "$HERE/python.sh" >/dev/null 2>&1 && [ -n "${FIC_PY:-}" ]; then py_ok=1; fi
# -I: the current folder (the project) does not enter sys.path, so a json.py or glob.py of its own cannot replace the
# standard library; -I also ignores the PYTHON* environment variables, so -B and -X utf8 restore them.
py() { sed '1,/^#__PYTHON__$/d' "$SELF" | "$FIC_PY" -I -B -X utf8 - "$@"; }

if [ "$piattaforma" = 1 ]; then
  [ -n "$py_ok" ] || { echo "maat-doctor: Python non trovato: piattaforma non determinabile" >&2; exit 2; }
  py piattaforma
  exit $?
fi

[ "$prova" = 1 ] && echo "--prova-test: il comando di test può scrivere cache e coverage (questa esecuzione non è in sola lettura)"
nok=0 natt=0 nman=0
riga() { # <OK|ATTENZIONE|MANCA> <text>
  case $1 in OK) nok=$((nok + 1)) ;; ATTENZIONE) natt=$((natt + 1)) ;; *) nman=$((nman + 1)) ;; esac
  printf '%s %s\n' "$1" "$2"
}
LAVORO=.claude/.ai-workflow VALIDA=""
emetti() { # lines from the Python part: «OK|ATTENZIONE|MANCA …» or meta «#chiave<TAB>valore»
  local l
  while IFS= read -r l; do
    l=${l%$'\r'}
    case $l in
      "#lavoro"$'\t'*) LAVORO=${l#*$'\t'} ;;
      "#valida"$'\t'*) VALIDA=${l#*$'\t'} ;;
      OK\ *|ATTENZIONE\ *|MANCA\ *) riga "${l%% *}" "${l#* }" ;;
      "") ;;
      *) printf '%s\n' "$l" ;;
    esac
  done
}

# --- versions ---------------------------------------------------------------------------------------------------------
if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then riga OK "bash $BASH_VERSION"
else riga MANCA "bash $BASH_VERSION sotto la 4 — installa bash 4 o superiore (Git Bash recente su Windows)"; fi

pyv=""
[ -n "$py_ok" ] && pyv=$("$FIC_PY" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null | tr -d '\r' | head -1)
if [ -z "$py_ok" ] || [ -z "$pyv" ]; then
  riga MANCA "Python non trovato — installa Python 3.10 o superiore, o imposta FIC_PYTHON"; py_ok=""
elif ! ver_ge "$pyv" 3.10; then
  riga MANCA "Python $pyv sotto la 3.10 ($FIC_PY) — installa Python 3.10 o superiore, o imposta FIC_PYTHON"; py_ok=""
else riga OK "Python $pyv ($FIC_PY)"; fi

gv=$(git --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
if [ -z "$gv" ]; then riga MANCA "git non trovato — installa git 2.35 o superiore"
elif ver_ge "$gv" 2.35; then riga OK "git $gv"
else riga MANCA "git $gv sotto la 2.35 — aggiorna git"; fi

# The same order as run-phase.sh (`Binario:`), so the binary checked is the one the cycle will use: CLAUDE_BIN, then the
# most recent version inside the VS Code extension (the path changes at every update), then claude on PATH.
CL=${CLAUDE_BIN:-}
if [ -z "$CL" ]; then
  ext=$(ls -d "${USERPROFILE:-$HOME}"/.vscode/extensions/anthropic.claude-code-*-win32-x64 2>/dev/null | sort -V | tail -1)
  [ -n "$ext" ] && [ -f "$ext/resources/native-binary/claude.exe" ] && CL="$ext/resources/native-binary/claude.exe"
fi
[ -n "$CL" ] || CL=$(command -v claude 2>/dev/null || true)
if [ -z "$CL" ]; then
  riga ATTENZIONE "Claude Code non trovato: versione non verificata — imposta CLAUDE_BIN o metti claude nel PATH"
else
  if command -v timeout >/dev/null 2>&1; then cv=$(timeout 30 "$CL" --version 2>/dev/null </dev/null | head -1)
  else cv=$("$CL" --version 2>/dev/null </dev/null | head -1); fi
  cv=$(printf '%s' "$cv" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ -z "$cv" ]; then riga ATTENZIONE "Claude Code ($CL) non dice la sua versione: versione non verificata"
  elif ver_ge "$cv" "$CLAUDE_MIN"; then riga OK "Claude Code $cv"
  else riga ATTENZIONE "Claude Code $cv sotto la $CLAUDE_MIN provata — aggiorna Claude Code"; fi
fi

# --- project, configuration, WSL, modules -----------------------------------------------------------------------------
ROOT=${FIC_REPO:-}
[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
if [ -z "$ROOT" ]; then
  riga MANCA "repository git non trovato da $(pwd) — lancia il doctor dalla cartella del progetto (o imposta FIC_REPO)"
  echo "maat-doctor: $nok OK, $natt ATTENZIONE, $nman MANCA"
  exit 1
fi
ROOT=$(winp "$ROOT")
export DR_ROOT=$ROOT PROJECT_ROOT=$ROOT
CFG=${MAAT_CONFIG:-$ROOT/.claude/maat.json}
CFG=$(winp "$CFG")
case $CFG in /*|[A-Za-z]:/*) ;; *) CFG=$(winp "$PWD/$CFG") ;; esac
export MAAT_CONFIG=$CFG

if [ -z "$py_ok" ]; then
  riga MANCA "configurazione, moduli e guardia non verificati: serve Python 3.10 o superiore — installa Python o imposta FIC_PYTHON"
else
  emetti < <(py config)
fi

# --- guard -------------------------------------------------------------------------------------------------------------
gjson() { "$FIC_PY" -I -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}, "cwd": sys.argv[2]}))' "$1" "$ROOT"; }
GMOT=""
prova_guardia() { # <command>: 0 if denied in a phase (exit 2) and asked in the session (ask); otherwise the reason in GMOT
  local j rc out
  j=$(gjson "$1")
  printf '%s' "$j" | FIC_PHASE=implement FIC_REPO=$ROOT MAAT_CONFIG=$CFG "$FIC_PY" "$HERE/guard.py" >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] || { GMOT="in fase non negato (uscita $rc, attesa 2)"; return 1; }
  out=$(printf '%s' "$j" | env -u FIC_PHASE CLAUDE_PROJECT_DIR="$ROOT" MAAT_CONFIG="$CFG" "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | tr -d '\r')
  printf '%s' "$out" | grep -qE '"permissionDecision": *"ask"' || { GMOT="in sessione non chiesto (atteso ask)"; return 1; }
}
if [ -n "$py_ok" ]; then
  if [ "$VALIDA" != 0 ]; then
    riga MANCA "guardia non provata: configurazione non valida — correggi maat.json, poi rilancia il doctor"
  else
    for c in "git push --force origin prova"; do
      if prova_guardia "$c"; then riga OK "guardia: «$c» negato in fase e chiesto in sessione"
      else riga MANCA "guardia: «$c» $GMOT — la guardia non protegge: controlla guard.py e la sezione guardia di maat.json"; fi
    done
    sonda=$("$FIC_PY" "$HERE/maat-config.py" sonda-produzione 2>/dev/null | tr -d '\r' | head -1); src=$?
    if [ "$src" = 3 ]; then riga OK "nessuna sonda di produzione: provato solo il nucleo"
    elif [ "$src" != 0 ] || [ -z "$sonda" ]; then riga MANCA "sonda di produzione non calcolabile (maat-config.py sonda-produzione uscito $src) — controlla guardia.sonde"
    elif prova_guardia "$sonda"; then riga OK "guardia: sonda di produzione «$sonda» negata in fase e chiesta in sessione"
    else riga MANCA "guardia: sonda di produzione «$sonda» $GMOT — controlla guardia.produzione e guardia.sonde"; fi
  fi
  emetti < <(py aggancio)
fi

# --- working folder ---------------------------------------------------------------------------------------------------
LAVORO=${LAVORO%/}
W="$ROOT/$LAVORO"
if [ ! -d "$W" ]; then riga MANCA "cartella di lavoro $LAVORO assente — creala (mkdir -p $LAVORO) o correggi cartelle.lavoro"
elif [ ! -w "$W" ]; then riga MANCA "cartella di lavoro $LAVORO non scrivibile — dai i permessi di scrittura"
elif git -C "$ROOT" check-ignore -q -- "$LAVORO" 2>/dev/null || git -C "$ROOT" check-ignore -q -- "$LAVORO/" 2>/dev/null; then
  riga OK "cartella di lavoro $LAVORO scrivibile, ignorata da git"
else riga OK "cartella di lavoro $LAVORO scrivibile, NON ignorata da git: spec e run dir compaiono in git status (aggiungila a .gitignore se non vuoi versionarle)"; fi

echo "maat-doctor: $nok OK, $natt ATTENZIONE, $nman MANCA"
[ "$nman" = 0 ]
exit $?

#__PYTHON__
import contextlib
import glob
import importlib.util
import io
import json
import os
import posixpath
import re
import shlex
import shutil
import subprocess
import sys

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", newline="\n")
    except (AttributeError, ValueError):
        pass

ROOT = os.environ.get("DR_ROOT", "").replace("\\", "/").rstrip("/")
PLUGIN = os.environ["MAAT_ROOT"].replace("\\", "/").rstrip("/")
WIN = os.environ.get("DR_WIN") == "1"
BASH = os.environ.get("DR_BASH") or "bash"
PROVA = os.environ.get("DR_PROVA") == "1"
TIMEOUT_WSL = int(os.environ.get("MAAT_DOCTOR_WSL_TIMEOUT") or 30)


def riga(livello, cosa, rimedio=""):
    print("%s %s%s" % (livello, cosa, (" — " + rimedio) if rimedio else ""), flush=True)


def meta(k, v):
    print("#%s\t%s" % (k, v), flush=True)


def wslp(p):
    p = p.replace("\\", "/")
    m = re.match(r"^([A-Za-z]):/(.*)$", p)
    return "/mnt/%s/%s" % (m.group(1).lower(), m.group(2)) if m else p


def sq(s):
    return "'" + str(s).replace("'", "'\\''") + "'"


def wsl_stato():
    """(present, reason, executable). Missing = wsl.exe not on PATH, or `wsl -- true` failed or exceeded the limit."""
    w = shutil.which("wsl") or shutil.which("wsl.exe")
    if not w:
        return False, "wsl.exe fuori dal PATH", None
    try:
        r = subprocess.run([w, "--", "true"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=TIMEOUT_WSL)
    except subprocess.TimeoutExpired:
        return False, "`wsl -- true` oltre %d s" % TIMEOUT_WSL, None
    except OSError as e:
        return False, "`wsl -- true` non eseguibile: %s" % e, None
    if r.returncode != 0:
        return False, "`wsl -- true` uscito %d" % r.returncode, None
    return True, "", w


class Sonde:
    """Shell probes run in a single process (bash here, or bash inside WSL), on the first read of a result."""
    def __init__(self, argv):
        self.argv, self.prove, self.esito = argv, [], None

    def prova(self, test):
        self.prove.append(test)
        return len(self.prove) - 1

    def __getitem__(self, i):
        if self.esito is None:
            self.esegui()
        return self.esito[i]

    def esegui(self):
        self.esito = [False] * len(self.prove)
        if not self.prove or not self.argv:
            return
        s = "".join("if %s; then echo '@@ok %d'; fi\n" % (t, i) for i, t in enumerate(self.prove))
        try:
            r = subprocess.run(self.argv, input=s.encode("utf-8"), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               timeout=180)
        except (OSError, subprocess.TimeoutExpired):
            return
        for l in r.stdout.decode("utf-8", "replace").replace("\r", "").splitlines():
            if l.startswith("@@ok ") and l[5:].strip().isdigit() and int(l[5:]) < len(self.esito):
                self.esito[int(l[5:])] = True


def esiste_cmd(sonde, exe):
    return sonde.prova("command -v %s >/dev/null 2>&1" % sq(exe))


def prove_copia(fm, root, pac):
    """The two shell probes (inside WSL) of the copy of <pac>, with the rules of test-fast.sh: (copy ready =
    node_modules and .fic-deps in the copy of this root; will be seeded = a worktree's copy missing but the main
    tree's copy ready, from which fic_seed_node_modules seeds it on first use)."""
    p = pac.replace('"', '\\"')

    def pronta(d):
        prove = ['[ -d "%s/node_modules" ]' % d, '[ -f "%s/.fic-deps" ]' % d]
        return " && ".join(prove)
    init = ". %s && fic_mirror_init %s" % (sq(fm), sq(root))
    questa, principale = pronta("$FIC_MIRROR/" + p), pronta("$HOME/fic-mirror/" + p)
    ok = "( %s && %s )" % (init, questa)
    semina = '( %s && [ "$FIC_MIRROR" != "$HOME/fic-mirror" ] && ! { %s; } && %s )' % (init, questa, principale)
    return ok, semina


def carica_lettore():
    s = importlib.util.spec_from_file_location("maat_config", os.environ["MAAT_CONFIG_PY"])
    mc = importlib.util.module_from_spec(s)
    s.loader.exec_module(mc)
    return mc


def versione_plugin():
    try:
        with open(posixpath.join(PLUGIN, ".claude-plugin", "plugin.json"), encoding="utf-8") as f:
            return json.load(f).get("version", "")
    except (OSError, ValueError):
        return ""


def tupla(v):
    return tuple(int(x) for x in re.findall(r"\d+", v)[:3])


# --------------------------------------------------------------------------- platform
def cmd_piattaforma():
    if not WIN:
        print("altro")
        return 0
    print("windows-wsl" if wsl_stato()[0] else "windows-senza-wsl")
    return 0


# --------------------------------------------------------------------------- first executable of a command
ASSEGNA = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
BUILTIN = {"cd", "export", "if", "[", "[[", "test", "true", "false", ":", "set", "source", ".", "eval", "exec",
           "for", "while", "until", "case", "{", "(", "!", "echo", "printf", "unset", "local"}


SEPARA = {"&&", ";"}                      # after a builtin command the chain is followed up to the first real executable
ENV_CON_ARG = {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}


def senza_parentesi(tok):
    """The segment without the subshell parentheses at its edges: «(» at the start (alone or attached to the first token) and «)»
    at the end (alone or attached to the last token, if it does not close a $(…) of the same token)."""
    tok = list(tok)
    while tok and tok[0] == "(":
        tok.pop(0)
    if tok and tok[0].startswith("(") and not tok[0].startswith("(("):
        tok[0] = tok[0][1:]
    while tok and tok[-1] == ")":
        tok.pop()
    if tok and tok[-1].endswith(")") and tok[-1].count("(") < tok[-1].count(")"):
        tok[-1] = tok[-1][:-1]
    return [x for x in tok if x]


def primo(mc, txt, maat):
    """(executable, script, folder) of the command: the first real executable ("{python}" for the module's interpreter;
    None if there are only shell builtins), looked up after the assignments and the env options and, after a
    builtin command (`cd x && ./run.sh`), in the command following && or ;. script: what bash/sh/{python}
    launch (.sh or .py). folder: where the skipped `cd`s lead ("" = no cd), for relative paths."""
    t = txt.replace("{maat}", maat).replace("{python}", "\x00PY\x00")
    t = mc.SEGNAPOSTO.sub("", t).replace("\x00PY\x00", "{python}")
    try:
        # ( and ) are not punctuation: FOO=$(pwd) stays a single token; the parentheses of a subshell are removed
        # at the edges of the segment (senza_parentesi), so `( cd x && ./run.sh )` follows the cd as without parentheses
        lx = shlex.shlex(t, posix=True, punctuation_chars=";&|<>")
        lx.whitespace_split = True
        tutti = list(lx)
    except ValueError:
        tutti = t.split()
    segmenti, cur = [], []
    for x in tutti:
        if x in SEPARA:
            segmenti.append(cur)
            cur = []
        else:
            cur.append(x)
    segmenti.append(cur)
    cart = ""
    for tok in segmenti:
        tok = senza_parentesi(tok)
        while tok:
            if ASSEGNA.match(tok[0]):
                tok.pop(0)
            elif tok[0] == "env":
                tok.pop(0)
                while tok and tok[0].startswith("-"):
                    o = tok.pop(0)
                    if o == "--":
                        break
                    if o in ENV_CON_ARG and tok:
                        tok.pop(0)
            else:
                break
        if not tok:
            continue
        exe = tok[0]
        if exe in BUILTIN:
            if exe == "cd" and len(tok) > 1 and not tok[1].startswith("-"):
                cart = posixpath.normpath(posixpath.join(cart, tok[1].replace("\\", "/")))
            continue
        script = None
        resto = [x for x in tok[1:] if not x.startswith("-")]
        if posixpath.basename(exe) in ("bash", "sh", "{python}") and resto and resto[0].endswith((".sh", ".py")):
            script = resto[0]
        return exe, script, cart
    return None, None, cart


def assoluto(p, base):
    p = p.replace("\\", "/")
    return p if p.startswith("/") or re.match(r"^[A-Za-z]:/", p) else posixpath.normpath(posixpath.join(base, p))


# --------------------------------------------------------------------------- config
def cmd_config():
    mc = carica_lettore()
    buf = io.StringIO()
    with contextlib.redirect_stderr(buf):
        try:
            cfg, p = mc.carica()
            rc = 0
        except mc.Uscita as u:
            rc, msg = u.codice, u.messaggio
    if rc == 4:
        meta("valida", 4)
        riga("MANCA", "maat.json assente (%s)" % mc.percorso_config(), "lancia /maat:setup")
        return
    if rc != 0:
        meta("valida", rc)
        dett = [l.replace("maat-config: ", "") for l in buf.getvalue().splitlines() if l.strip()][:3]
        riga("MANCA", "maat.json non valido: %s" % ("; ".join(dett) or msg),
             "correggi il file (python maat-config.py valida) o rilancia /maat:setup")
        return
    meta("valida", 0)
    r = mc.risolto(cfg)
    meta("lavoro", r.get("cartelle", {}).get("lavoro", ".claude/.ai-workflow"))
    riga("OK", "maat.json valido (%s)" % p)
    vp = versione_plugin()
    h = cfg.get("harness")
    if h:
        if vp and tupla(vp)[:2] >= tupla(h)[:2]:
            riga("OK", "versione del plugin %s compatibile con harness %s" % (vp, h))
        else:
            riga("MANCA", "versione del plugin %s non compatibile con harness %s" % (vp or "ignota", h),
                 "aggiorna il plugin o correggi harness in maat.json")
    else:
        riga("OK", "versione del plugin %s (harness non dichiarato)" % (vp or "ignota"))

    piano = []          # functions that print, called after all probes have been registered
    locale = Sonde([BASH, "-s"])
    mods = r.get("moduli", [])
    wsl_mod = [m["nome"] for m in mods if m.get("ambiente") == "wsl"]

    # --- WSL
    wsl, wsl_motivo, wexe = False, "", None
    if WIN:
        copia_wsl = r.get("piattaforma", {}).get("copia_wsl", "auto")
        if copia_wsl in ("auto", "sì") or wsl_mod:
            wsl, wsl_motivo, wexe = wsl_stato()
            if not wsl:
                if copia_wsl == "sì":
                    riga("MANCA", "WSL assente (%s) ma piattaforma.copia_wsl: sì" % wsl_motivo,
                         "installa WSL, o metti piattaforma.copia_wsl: auto")
                elif not wsl_mod:
                    riga("OK", "WSL assente: copia veloce dei test non disponibile (%s)" % wsl_motivo)
                else:
                    riga("ATTENZIONE", "WSL assente (%s)" % wsl_motivo, "i moduli wsl sono elencati sotto")
        else:
            riga("OK", "WSL non richiesto (piattaforma.copia_wsl: no, nessun modulo wsl)")
    else:
        riga("OK", "piattaforma non Windows: WSL non serve")
    inwsl = Sonde([wexe, "--", "bash", "-l", "-s"] if wsl else None)
    if wsl:
        node = r.get("piattaforma", {}).get("node_wsl")
        ib = esiste_cmd(inwsl, "bash")
        inode = inwsl.prova("[ -x %s ]" % sq(node)) if node and "/" in node else esiste_cmd(inwsl, node or "node")

        def wsl_righe(ib=ib, inode=inode, node=node):
            riga("OK", "WSL raggiungibile")
            if not inwsl[ib]:
                riga("MANCA", "bash non trovato in WSL", "installa bash nella distribuzione predefinita di WSL")
            if inwsl[inode]:
                riga("OK", "Node in WSL (%s)" % (node or "node"))
            else:
                riga("MANCA" if wsl_mod else "ATTENZIONE", "Node non trovato in WSL (%s)" % (node or "node"),
                     "installa Node in WSL, o imposta piattaforma.node_wsl")
        piano.append(wsl_righe)

    copie = [m for m in mods if m.get("copia")]
    for m in mods:
        piano.extend(controlli_modulo(mc, cfg, r, m, wsl, locale, inwsl, len(copie)))
    piano.extend(controlli_progetto(mc, cfg, r, locale))
    for f in piano:
        f()


def controlli_modulo(mc, cfg, r, m, wsl, locale, inwsl, n_copie):
    out = []
    nome = m["nome"]
    amb = m.get("ambiente", "nativo")
    rad = mc.norm(m["radice"])
    rad_abs = posixpath.join(ROOT, rad) if rad else ROOT
    usabile = amb != "wsl" or wsl          # the module's commands can be looked up where they run
    sonde = inwsl if amb == "wsl" else locale
    maat = PLUGIN   # the {maat} scripts are looked up here: they are the same files even as seen from WSL (/mnt/…)
    if amb == "wsl" and not WIN:
        out.append(lambda: riga("MANCA", "modulo %s ambiente: wsl fuori da Windows: i suoi gate saranno BLOCKED" % nome,
                                "metti ambiente: nativo"))
    elif amb == "wsl" and not wsl:
        out.append(lambda: riga("MANCA", "modulo %s ambiente: wsl ma WSL assente: i suoi gate saranno BLOCKED" % nome,
                                "metti `ambiente: nativo` o installa WSL"))
    if not os.path.isdir(rad_abs):
        out.append(lambda: riga("MANCA", "radice del modulo %s assente: %s" % (nome, rad or "."), "correggi moduli[].radice"))
        return out

    # --- {python}
    usa_py = any("{python}" in t for t in mc.testi_del_modulo(m)) or "{python}" in m.get("controprova", {}).get("comando", "")
    py = {"ok": True}
    if usa_py and usabile:
        if amb == "wsl":
            env = os.environ.get("FIC_GATES_VENV_PY")
            if env:
                cand, base = [env], ""
            elif m.get("python"):
                cand, base = (m["python"] if isinstance(m["python"], list) else [m["python"]]), rad
            elif r.get("piattaforma", {}).get("python"):
                cand, base = [r["piattaforma"]["python"]], ""
            else:
                cand, base = ["python3"], ""
            idx = []
            for c in cand:
                c = c.replace("\\", "/")
                if "/" in c:
                    p = c if c.startswith("/") else wslp(c) if re.match(r"^[A-Za-z]:/", c) else \
                        posixpath.normpath(posixpath.join(wslp(ROOT), base, c))
                    idx.append((p, inwsl.prova("[ -x %s ]" % sq(p))))
                else:
                    idx.append((c, esiste_cmd(inwsl, c)))

            def py_righe(idx=idx):
                trovati = [p for p, i in idx if inwsl[i]]
                if trovati:
                    riga("OK", "python del modulo %s in WSL: %s" % (nome, trovati[0]))
                    py["wsl"] = trovati[0]
                else:
                    py["ok"] = False
                    riga("MANCA", "python assente per il modulo %s in WSL (cercati: %s)" % (nome, ", ".join(p for p, _ in idx)),
                         "crea il venv del modulo dentro WSL o correggi moduli[].python")
            out.append(py_righe)
        else:
            p = mc.risolvi_python(cfg, m, ROOT)
            ok = p is not None and (os.path.isfile(p) or os.path.isfile(p + ".exe") or shutil.which(p) is not None)
            if ok:   # un interprete che c'e' ma non parte (es. lo stub dello Store senza Python) vale come assente
                try:
                    ok = subprocess.run([p, "-c", "import sys"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL, timeout=20).returncode == 0
                except (OSError, subprocess.TimeoutExpired):
                    ok = False

            def py_righe(p=p, ok=ok):
                if ok:
                    riga("OK", "python del modulo %s: %s" % (nome, p))
                else:
                    py["ok"] = False
                    riga("MANCA", "python assente per il modulo %s (%s)" % (nome, p or "nessun candidato"),
                         "crea il venv del modulo o correggi moduli[].python / piattaforma.python")
            out.append(py_righe)

    def eseguibile(etichetta, txt, cart_abs, se_presente=None, livello="MANCA", rimedio=""):
        """Registra la prova del primo eseguibile di txt; ritorna la funzione che stampa la riga."""
        exe, script, cd = primo(mc, txt, maat)
        base = assoluto(cd, cart_abs) if cd else cart_abs
        i = None
        if exe and exe != "{python}" and "/" not in exe and usabile:
            i = esiste_cmd(sonde, exe)
        # wsl module: an absolute path outside /mnt/ exists only inside WSL -> [ -x ] (script: [ -f ]) in the
        # same WSL shell as the other probes (with its timeout); /mnt/<u>/… is checked here as <U>:/…
        dentro = {}
        if amb == "wsl" and usabile:
            for p, t in ((exe, "-x"), (script, "-f")):
                if p and p != "{python}" and "/" in p:
                    a = assoluto(p, base)
                    if a.startswith("/") and not a.startswith("/mnt/"):
                        dentro[p] = sonde.prova("[ %s %s ]" % (t, sq(a)))

        def qui(p):
            m_ = re.match(r"^/mnt/([a-z])/(.*)$", p) if amb == "wsl" and WIN else None
            return "%s:/%s" % (m_.group(1).upper(), m_.group(2)) if m_ else p

        def stampa():
            if not usabile:
                return
            mancanti = []
            if exe == "{python}":
                pass
            elif exe in dentro:
                if not sonde[dentro[exe]]:
                    mancanti.append(exe)
            elif exe and "/" in exe:
                if not os.path.exists(qui(assoluto(exe, base))):
                    mancanti.append(exe)
            elif exe and i is not None and not sonde[i]:
                mancanti.append(exe)
            if script:
                ok = sonde[dentro[script]] if script in dentro else os.path.isfile(qui(assoluto(script, base)))
                if not ok:
                    mancanti.append(script)
            if exe == "{python}" and not py["ok"] and not mancanti:
                return   # the missing interpreter already has its MANCA line: the command cannot be checked, no OK
            if not mancanti:
                riga("OK", "%s: %s" % (etichetta, exe or "comando della shell"))
            elif se_presente:
                riga("ATTENZIONE", "%s: controllo saltato, %s assente" % (etichetta, ", ".join(mancanti)),
                     "installa %s se vuoi il controllo" % ", ".join(mancanti))
            else:
                riga(livello, "%s: %s non trovato" % (etichetta, ", ".join(mancanti)),
                     rimedio or "installalo o correggi il comando in maat.json")
        return stampa

    # --- comandi (commands)
    for tipo, c in m.get("comandi", {}).items():
        c = {"comando": c} if isinstance(c, str) else c
        quale = c.get("cartella", "radice")
        cart = mc.cartella_di(m, quale)
        cart_abs = posixpath.join(ROOT, cart) if cart else ROOT
        et = "comando %s del modulo %s" % (tipo, nome)
        if not os.path.isdir(cart_abs):
            out.append(lambda et=et, cart=cart, quale=quale: riga(
                "MANCA", "%s: cartella %s (%s) assente" % (et, cart or ".", quale), "correggi radice o radice_pacchetti"))
            continue
        if c.get("se_presente") and not mc.presente(c["se_presente"], rad_abs):
            out.append(lambda et=et, sp=c["se_presente"]: riga("OK", "%s: NOT RUN (dichiarato), %s assente" % (et, sp)))
            continue
        out.append(eseguibile(et, c["comando"], cart_abs))

    # --- controlli (checks)
    for j, v in enumerate(m.get("controlli", [])):
        out.append(eseguibile("controllo %s del modulo %s (%s)" % (j, nome, v["glob"]), v["comando"], rad_abs,
                              se_presente=v.get("se_presente")))

    # --- controprova (counterproof)
    cp = m.get("controprova")
    if not cp or not cp.get("comando"):
        out.append(lambda: riga("OK", "controprove del modulo %s: NOT RUN (dichiarato)" % nome))
    else:
        if cp.get("runner") == "comando":
            out.append(eseguibile("controprova del modulo %s" % nome, cp["comando"], rad_abs))
        elif "{python}" in cp["comando"]:
            out.append(eseguibile("controprova del modulo %s" % nome, "{python}", rad_abs))
        if usabile:
            # the tools of counterproof.sh (pk08): rsync and flock have a fallback (tar, mkdir), the others do not
            st = [(s, esiste_cmd(sonde, s)) for s in ("rsync", "flock", "tar", "sha256sum", "timeout")]

            def strumenti(st=st):
                ha = {s: sonde[i] for s, i in st}
                manca = [s for s in ("sha256sum", "timeout") if not ha[s]]
                if not ha["rsync"] and not ha["tar"]:
                    manca.append("rsync e tar")
                assenti = [s for s in ("rsync", "flock") if not ha[s]]
                if manca:
                    riga("ATTENZIONE", "controprove del modulo %s non disponibili (BLOCKED): manca %s"
                         % (nome, ", ".join(manca)), "installa %s %s" % (", ".join(manca), "in WSL" if amb == "wsl" else "qui"))
                elif assenti:
                    cosa = {("rsync",): "rsync assente: copia di ripiego, più lenta",
                            ("flock",): "flock assente: lock di ripiego, più lento",
                            ("rsync", "flock"): "rsync/flock assenti: copia e lock di ripiego, più lenti"}
                    riga("OK", "controprove del modulo %s: %s" % (nome, cosa[tuple(assenti)]))
                else:
                    riga("OK", "controprove del modulo %s: rsync e flock %s" % (nome, "in WSL" if amb == "wsl" else "presenti"))
            out.append(strumenti)

    # --- WSL copy of the module
    if amb == "wsl" and wsl and m.get("copia"):
        pac = mc.norm(m["radice_pacchetti"])
        fm = wslp(posixpath.join(PLUGIN, "scripts", "fic-mirror.sh"))
        t_ok, t_semina = prove_copia(fm, wslp(ROOT), pac)
        i, i_semina = inwsl.prova(t_ok), inwsl.prova(t_semina)
        env = "MAAT_MODULO=%s " % sq(nome) if n_copie > 1 else ""
        setup = "wsl -- bash -lc 'cd %s && %sbash %s/scripts/test-fast.sh --setup'" % (wslp(ROOT), env, wslp(PLUGIN))

        def copia(i=i, i_semina=i_semina, setup=setup):
            if inwsl[i]:
                riga("OK", "copia WSL del modulo %s presente" % nome)
            elif inwsl[i_semina]:
                riga("ATTENZIONE", "copia WSL del modulo %s assente in questo worktree: si seminerà al primo uso dalla "
                     "copia del tree principale (node_modules in hardlink), se le dipendenze coincidono" % nome,
                     "niente da fare; se le dipendenze sono diverse: %s" % setup)
            else:
                riga("MANCA", "copia WSL del modulo %s assente" % nome, "creala una volta: %s" % setup)
        out.append(copia)

    # --- preparati: the guide file (the first glob without wildcards)
    guida = next((g for g in m.get("preparati", []) if not any(ch in g for ch in "*?[")), None)
    if guida:
        ok = os.path.exists(posixpath.join(rad_abs, guida))
        out.append(lambda ok=ok, guida=guida: riga(
            "OK", "preparato del modulo %s presente (%s)" % (nome, guida)) if ok else riga(
            "ATTENZIONE", "preparato assente nel modulo %s (%s)" % (nome, guida),
            "lancia `%s` nella radice del modulo" % m.get("preparazione", "la preparazione")))

    # --- copia_anche: repo folders that the counterproofs copy
    for d in m.get("copia_anche", []):
        ok = os.path.isdir(posixpath.join(ROOT, mc.norm(d)))
        out.append(lambda ok=ok, d=d: riga("OK", "copia_anche del modulo %s: %s" % (nome, d)) if ok else riga(
            "MANCA", "copia_anche del modulo %s: %s non esiste (le controprove del modulo fallirebbero)" % (nome, d),
            "correggi moduli[].copia_anche"))

    # --- collega_nel_worktree: the folders present in the main tree
    for v in m.get("collega_nel_worktree", []):
        v = {"percorso": v} if isinstance(v, str) else v
        cart = mc.cartella_di(m, v.get("cartella", "radice"))
        pat = posixpath.join(ROOT, cart, v["percorso"]) if cart else posixpath.join(ROOT, v["percorso"])
        ok = any(os.path.isdir(x) for x in glob.glob(pat))
        dov = posixpath.join(cart, v["percorso"]) if cart else v["percorso"]
        out.append(lambda ok=ok, dov=dov: riga("OK", "collega_nel_worktree del modulo %s: %s presente" % (nome, dov))
                   if ok else riga("ATTENZIONE", "dipendenze non installate: i worktree del modulo %s non avranno %s"
                                   % (nome, dov), "installa le dipendenze nel tree principale"))

    # --- file_dipendenze: every glob finds at least one tracked file
    for v in m.get("file_dipendenze", []):
        v = {"glob": v} if isinstance(v, str) else v
        cart = mc.cartella_di(m, v.get("cartella", "radice"))
        spec = ":(glob)" + (cart + "/" + v["glob"] if cart else v["glob"])
        try:
            g = subprocess.run(["git", "-C", ROOT, "ls-files", "--", spec], stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, timeout=60)
            ok = bool(g.stdout.strip())
        except (OSError, subprocess.TimeoutExpired):
            ok = False
        out.append(lambda ok=ok, spec=spec: riga("OK", "file_dipendenze del modulo %s: %s" % (nome, spec[7:])) if ok
                   else riga("ATTENZIONE", "file_dipendenze del modulo %s: glob senza file tracciati: %s" % (nome, spec[7:]),
                             "correggi il glob in maat.json"))

    # --- --prova-test
    if PROVA and "test" in m.get("comandi", {}) and usabile:
        out.append(lambda: prova_test(mc, cfg, m, py))
    return out


def scegli_test(mc, m):
    rad = mc.norm(m["radice"])
    rad_abs = posixpath.join(ROOT, rad) if rad else ROOT
    regola = m.get("regola_test", "accanto")
    if regola == "nessuna":
        return None
    rx = re.compile(mc.glob_pezzi(m["specchio"]["a"], "[^/]*")) if regola == "specchio" else None
    for d, sub, files in os.walk(rad_abs):
        sub[:] = sorted(s for s in sub if s not in mc.SALTA_DIR)
        rel = os.path.relpath(d, rad_abs).replace("\\", "/")
        for f in sorted(files):
            p = f if rel == "." else rel + "/" + f
            if (rx is not None and rx.fullmatch(p)) or (rx is None and mc.TEST_ACCANTO.fullmatch(f)):
                return posixpath.join(rad, p) if rad else p
    return None


def prova_test(mc, cfg, m, py):
    nome = m["nome"]
    t = scegli_test(mc, m)
    if t is None:
        riga("ATTENZIONE", "prova test del modulo %s: nessun file di test trovato dalla regola %s"
             % (nome, m.get("regola_test", "accanto")), "aggiungi un test o correggi regola_test")
        return
    wsl = m.get("ambiente") == "wsl"
    salva = {k: os.environ.get(k) for k in ("MAAT_ROOT", "FIC_GATES_VENV_PY")}
    try:
        if wsl:
            os.environ["MAAT_ROOT"] = wslp(PLUGIN)
            if py.get("wsl"):
                os.environ["FIC_GATES_VENV_PY"] = py["wsl"]
        cart, line = mc.comando(cfg, nome, "test", test=[t], root=ROOT)[0]
    except mc.Uscita as u:
        riga("MANCA", "prova test del modulo %s: comando non risolto (%s)" % (nome, u.messaggio or u.codice),
             "correggi comandi.test")
        return
    finally:
        for k, v in salva.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    cart_abs = posixpath.join(ROOT, cart) if cart else ROOT
    try:
        if wsl:
            s = "export MAAT_MODULO=%s MAAT_CONFIG=%s\ncd %s && %s\n" % (
                sq(nome), sq(wslp(os.environ.get("MAAT_CONFIG", ""))), sq(wslp(cart_abs)), line)
            w = shutil.which("wsl") or shutil.which("wsl.exe")
            res = subprocess.run([w, "--", "bash", "-l", "-s"], input=s.encode("utf-8"), stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, timeout=900)
        else:
            env = dict(os.environ, MAAT_MODULO=nome)
            res = subprocess.run([BASH, "-c", "cd %s && %s" % (sq(cart_abs), line)], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900, env=env)
    except subprocess.TimeoutExpired:
        riga("MANCA", "prova test del modulo %s: %s oltre 900 s" % (nome, t), "lancia il comando a mano e guarda dove si ferma")
        return
    ultima = ([l for l in res.stdout.decode("utf-8", "replace").replace("\r", "").splitlines() if l.strip()] or [""])[-1]
    if res.returncode == 0:
        riga("OK", "prova test del modulo %s: %s, uscita 0" % (nome, t))
    else:
        riga("MANCA", "prova test del modulo %s: %s, uscita %d (%s)" % (nome, t, res.returncode, ultima[:160]),
             "correggi comandi.test o l'ambiente del modulo")


def controlli_progetto(mc, cfg, r, locale):
    out = []

    def comando_progetto(etichetta, txt):
        if re.fullmatch(r"/[A-Za-z0-9:_-]+", txt.strip()):
            out.append(lambda: riga("OK", "%s: comando di sessione %s (si lancia in Claude Code, non verificabile qui)"
                                    % (etichetta, txt.strip())))
            return
        exe, script, cd = primo(mc, txt, PLUGIN)
        base = assoluto(cd, ROOT) if cd else ROOT
        i = esiste_cmd(locale, exe) if exe and "/" not in exe and exe != "{python}" else None

        def stampa():
            manca = []
            if exe and "/" in exe and not os.path.exists(assoluto(exe, base)):
                manca.append(exe)
            if i is not None and not locale[i]:
                manca.append(exe)
            if script and not os.path.isfile(assoluto(script, base)):
                manca.append(script)
            if manca:
                riga("MANCA", "%s: %s non trovato" % (etichetta, ", ".join(manca)), "installalo o correggi maat.json")
            else:
                riga("OK", "%s: %s" % (etichetta, exe or "comando della shell"))
        out.append(stampa)

    c = r.get("contesto", {}).get("schema_db_comando")
    if c:
        comando_progetto("contesto.schema_db_comando", c)
    v = r.get("verifica_remota", {}).get("comando")
    if v:
        comando_progetto("verifica_remota", v)
    g = r.get("guardia", {})
    if g.get("suite"):
        try:
            tracciati = subprocess.run(["git", "-C", ROOT, "ls-files"], stdout=subprocess.PIPE,
                                       stderr=subprocess.DEVNULL, timeout=60).stdout.decode("utf-8", "replace").splitlines()
        except (OSError, subprocess.TimeoutExpired):
            tracciati = []
        for s in g["suite"]:
            nome = s["script"].replace("\\", "/").strip()
            ok = any(t == nome or t.endswith("/" + nome) for t in tracciati) or os.path.isfile(assoluto(nome, ROOT))
            out.append(lambda ok=ok, nome=nome: riga("OK", "guardia.suite: %s" % nome) if ok else riga(
                "ATTENZIONE", "guardia.suite: script %s non trovato nel repo" % nome, "correggi guardia.suite"))

    # production probes and regexes
    prod, sonde = g.get("produzione", []), g.get("sonde", [])
    rx = []
    for p in prod:
        try:
            rx.append((p, re.compile(p, re.I)))
        except re.error as e:
            out.append(lambda p=p, e=e: riga("MANCA", "guardia.produzione: regex non valida %s (%s)" % (p, e),
                                             "correggi la regex"))
    for s in sonde:
        cmd = "curl -s https://%s/" % s
        ok = any(x.search(cmd) for _p, x in rx)
        out.append(lambda ok=ok, s=s: riga("OK", "sonda %s coperta da guardia.produzione" % s) if ok else riga(
            "MANCA", "sonda non coperta dalla guardia: %s" % s, "aggiungi a guardia.produzione una regex che la copra"))
    if sonde:
        for p, x in rx:
            if not any(x.search("curl -s https://%s/" % s) for s in sonde):
                out.append(lambda p=p: riga("ATTENZIONE", "regola di produzione non provata: %s" % p,
                                            "aggiungi a guardia.sonde un host che le corrisponda"))
    return out


# --------------------------------------------------------------------------- guard hookup
def leggi_json(p):
    try:
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def cmd_aggancio():
    home = (os.environ.get("HOME") or os.environ.get("USERPROFILE") or "").replace("\\", "/")
    progetto = posixpath.join(ROOT, ".claude", "settings.json")
    locale = posixpath.join(ROOT, ".claude", "settings.local.json")
    utente = posixpath.join(home, ".claude", "settings.json")
    abilitato, mk, dove = None, "", ""
    for f in (locale, progetto, utente):          # precedence: local > project > user
        ep = leggi_json(f).get("enabledPlugins", {})
        if not isinstance(ep, dict):
            continue
        voci = [(k, v) for k, v in ep.items() if k.split("@", 1)[0] == "maat"]
        if voci:
            abilitato = voci[0][1] is True
            mk, dove = voci[0][0].partition("@")[2], f
            break
    hook = False
    for h in leggi_json(progetto).get("hooks", {}).get("PreToolUse", []) or []:
        for x in (h.get("hooks", []) if isinstance(h, dict) else []):
            c = x.get("command", "") if isinstance(x, dict) else ""
            if "guard.py" in c or "guard-hook.sh" in c:
                hook = True
    rel = lambda f: f[len(ROOT) + 1:] if f.startswith(ROOT + "/") else f
    if abilitato and hook:
        riga("ATTENZIONE", "hook di guardia doppio: plugin maat abilitato (%s) e hook PreToolUse di progetto in .claude/settings.json"
             % rel(dove), "togli l'hook di progetto: la guardia del plugin basta")
    elif abilitato:
        riga("OK", "guardia agganciata: plugin maat%s abilitato (%s)" % ("@" + mk if mk else "", rel(dove)))
    elif hook:
        riga("OK", "guardia agganciata: hook PreToolUse di progetto in .claude/settings.json")
    else:
        riga("MANCA", "guardia non agganciata: né plugin maat abilitato né hook di progetto", "abilita il plugin (/plugin)")
    if abilitato and mk:
        km = leggi_json(posixpath.join(home, ".claude", "plugins", "known_marketplaces.json")).get(mk, {})
        ex = leggi_json(progetto).get("extraKnownMarketplaces", {})
        ex = ex.get(mk, {}) if isinstance(ex, dict) else {}
        fonti = [x.get("source") for x in (km, ex) if isinstance(x, dict)]
        if any((s.get("source") if isinstance(s, dict) else s) == "directory" for s in fonti):
            riga("ATTENZIONE", "plugin installato da un marketplace da cartella (%s): il codice gira dalla cartella sorgente, "
                 "ogni modifica arriva subito" % mk, "installa da git con un ref")


MODI = {"piattaforma": cmd_piattaforma, "config": cmd_config, "aggancio": cmd_aggancio}
if __name__ == "__main__":   # otherwise loaded by the tests (maat-doctor.test.sh, «unità» section), without running anything
    if len(sys.argv) < 2 or sys.argv[1] not in MODI:
        sys.stderr.write("maat-doctor (python): modo sconosciuto\n")
        sys.exit(64)
    sys.exit(MODI[sys.argv[1]]() or 0)
