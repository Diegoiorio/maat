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
# <n> MANCA». Exit: 0 no MANCA · 1 at least one MANCA · 64 wrong usage. The text follows the language (1.4.0): in
# English the levels are OK|WARNING|MISSING; --piattaforma prints the same three values in every language.
#
# Checks:
#   versions       bash >= 4, Python >= 3.10 (fic_py_min_ok of python.sh, the threshold of the wrappers), git >= 2.35,
#                  Claude Code (CLAUDE_BIN, then the VS Code extension, then PATH: the order of run-phase.sh): below
#                  the version tested in pk01 ATTENZIONE; not found ATTENZIONE «versione non verificata»
#   FIC_DRIVER     (1.6.0) set and not empty -> ATTENZIONE: it no longer has any effect (the rule of driver.py run)
#   macOS          (1.6.0) only on Darwin: GNU sed, grep and stat, sha256sum, timeout, flock; missing -> MANCA with
#                  the brew command
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
# · FIC_DRIVER (only to warn that it does nothing)
# · CLAUDE_BIN · MAAT_DOCTOR_WSL_TIMEOUT. Test: maat-doctor.test.sh.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1 PYTHONIOENCODING=utf-8 PYTHONUTF8=1
SELF=${BASH_SOURCE[0]}
HERE=$(cd "$(dirname "$SELF")" && pwd)
CLAUDE_MIN=2.1.285   # the version tested in pk01
# Messages (1.4.0): the catalog next to this script (lib/maat-msg.sh), English by default, Italian with "lingua": "it";
# the language is resolved once and exported, the Python part imports maat_msg.py from MAAT_MSG_PY. The levels travel
# between the two parts as OK|ATTENZIONE|MANCA in every language: only `riga` prints them in the language (D3).
. "$HERE/lib/maat-msg.sh"; maat_msg_carica; maat_lingua -v MAAT_LINGUA; export MAAT_LINGUA
MAAT_MSG_PY=$(cygpath -m "$HERE/maat_msg.py" 2>/dev/null || printf '%s' "$HERE/maat_msg.py"); export MAAT_MSG_PY
usage() { sed -n '2,/^set -uo/p' "$SELF" | sed '$d; s/^# \{0,1\}//'; }

prova=0 piattaforma=0
for a in "$@"; do
  case $a in
    --prova-test) prova=1 ;;
    --piattaforma) piattaforma=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "maat-doctor: $(msg maat-doctor.bad_option a="$a")" >&2; exit 64 ;;
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
  [ -n "$py_ok" ] || { echo "maat-doctor: $(msg maat-doctor.no_python_platform)" >&2; exit 2; }
  py piattaforma
  exit $?
fi

[ "$prova" = 1 ] && echo "--prova-test: $(msg maat-doctor.prova_writes)"
nok=0 natt=0 nman=0
msg -v LIV_ATT maat-doctor.level_warning; msg -v LIV_MAN maat-doctor.level_missing
riga() { # <OK|ATTENZIONE|MANCA> <text>: the level printed in the language (en WARNING|MISSING)
  case $1 in OK) nok=$((nok + 1)) ;; ATTENZIONE) natt=$((natt + 1)) ;; *) nman=$((nman + 1)) ;; esac
  case $1 in OK) printf 'OK %s\n' "$2" ;; ATTENZIONE) printf '%s %s\n' "$LIV_ATT" "$2" ;; *) printf '%s %s\n' "$LIV_MAN" "$2" ;; esac
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
else riga MANCA "$(msg maat-doctor.bash_old v="$BASH_VERSION")"; fi

pyv=""
[ -n "$py_ok" ] && pyv=$("$FIC_PY" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null | tr -d '\r' | head -1)
if [ -z "$py_ok" ] || [ -z "$pyv" ]; then
  riga MANCA "$(msg maat-doctor.no_python)"; py_ok=""
elif ! fic_py_min_ok; then   # 1.6.0 (D9 a): the threshold of python.sh, the one of the wrappers (FIC_PY_VER)
  riga MANCA "$(msg maat-doctor.python_old pyv="$pyv" py="$FIC_PY")"; py_ok=""
else riga OK "Python $pyv ($FIC_PY)"; fi

# 1.6.0 (D9 b): FIC_DRIVER no longer chooses an engine. Set = not empty, the rule of driver.py run (FIC_DRIVER= empty
# was already the default in 1.5.1 and stays silent).
if [ -n "${FIC_DRIVER:-}" ]; then riga ATTENZIONE "$(msg maat-doctor-f.fic_driver v="$FIC_DRIVER")"; fi

gv=$(git --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
if [ -z "$gv" ]; then riga MANCA "$(msg maat-doctor.no_git)"
elif ver_ge "$gv" 2.35; then riga OK "git $gv"
else riga MANCA "$(msg maat-doctor.git_old gv="$gv")"; fi

# The same order as run-phase.sh (`Binario:`), so the binary checked is the one the cycle will use: CLAUDE_BIN, then the
# most recent version inside the VS Code extension (the path changes at every update), then claude on PATH.
CL=${CLAUDE_BIN:-}
if [ -z "$CL" ]; then
  ext=$(ls -d "${USERPROFILE:-$HOME}"/.vscode/extensions/anthropic.claude-code-*-win32-x64 2>/dev/null | sort -V | tail -1)
  [ -n "$ext" ] && [ -f "$ext/resources/native-binary/claude.exe" ] && CL="$ext/resources/native-binary/claude.exe"
fi
[ -n "$CL" ] || CL=$(command -v claude 2>/dev/null || true)
if [ -z "$CL" ]; then
  riga ATTENZIONE "$(msg maat-doctor.no_claude)"
else
  if command -v timeout >/dev/null 2>&1; then cv=$(timeout 30 "$CL" --version 2>/dev/null </dev/null | head -1)
  else cv=$("$CL" --version 2>/dev/null </dev/null | head -1); fi
  cv=$(printf '%s' "$cv" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ -z "$cv" ]; then riga ATTENZIONE "$(msg maat-doctor.claude_no_version cl="$CL")"
  elif ver_ge "$cv" "$CLAUDE_MIN"; then riga OK "Claude Code $cv"
  else riga ATTENZIONE "$(msg maat-doctor.claude_old cv="$cv" min="$CLAUDE_MIN")"; fi
fi

# 1.6.0 (D9 c): on macOS Maat uses the GNU tools from Homebrew (README, Requirements). Only on Darwin (uname -s): on
# Linux and Windows no line. <tool>:<Homebrew formula>:<gnu|-> — gnu: the first line of --version must say «(GNU »
# (BSD grep says «BSD grep, GNU compatible»), and the formula puts the tool in libexec/gnubin; -: present on PATH.
if [ "$(uname -s 2>/dev/null | tr -d '\r')" = Darwin ]; then
  mac_ok=""
  for mst in sed:gnu-sed:gnu grep:grep:gnu stat:coreutils:gnu sha256sum:coreutils:- timeout:coreutils:- flock:flock:-; do
    mt=${mst%%:*} mf=${mst#*:}; mg=${mf#*:} mf=${mf%%:*} mok=0
    if [ "$mg" = gnu ]; then "$mt" --version 2>/dev/null </dev/null | head -1 | grep -qF '(GNU ' && mok=1
    else command -v "$mt" >/dev/null 2>&1 && mok=1; fi
    if [ "$mok" = 1 ]; then mac_ok+="${mac_ok:+, }$mt"
    elif [ "$mf" = flock ]; then riga MANCA "$(msg maat-doctor-f.mac_missing t="$mt" f="$mf")"
    else riga MANCA "$(msg maat-doctor-f.mac_missing_gnubin t="$mt" f="$mf")"; fi
  done
  [ -z "$mac_ok" ] || riga OK "$(msg maat-doctor-f.mac_ok t="$mac_ok")"
fi

# --- project, configuration, WSL, modules -----------------------------------------------------------------------------
ROOT=${FIC_REPO:-}
[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
if [ -z "$ROOT" ]; then
  riga MANCA "$(msg maat-doctor.no_repo dir="$(pwd)")"
  echo "maat-doctor: $(msg maat-doctor.summary nok="$nok" natt="$natt" nman="$nman")"
  exit 1
fi
ROOT=$(winp "$ROOT")
export DR_ROOT=$ROOT PROJECT_ROOT=$ROOT
CFG=${MAAT_CONFIG:-$ROOT/.claude/maat.json}
CFG=$(winp "$CFG")
case $CFG in /*|[A-Za-z]:/*) ;; *) CFG=$(winp "$PWD/$CFG") ;; esac
export MAAT_CONFIG=$CFG

if [ -z "$py_ok" ]; then
  riga MANCA "$(msg maat-doctor.no_python_config)"
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
  [ "$rc" = 2 ] || { GMOT="$(msg maat-doctor.guard_phase_not_denied rc="$rc")"; return 1; }
  out=$(printf '%s' "$j" | env -u FIC_PHASE CLAUDE_PROJECT_DIR="$ROOT" MAAT_CONFIG="$CFG" "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | tr -d '\r')
  printf '%s' "$out" | grep -qE '"permissionDecision": *"ask"' || { GMOT="$(msg maat-doctor.guard_session_not_asked)"; return 1; }
}
if [ -n "$py_ok" ]; then
  if [ "$VALIDA" != 0 ]; then
    riga MANCA "$(msg maat-doctor.guard_not_tested)"
  else
    for c in "git push --force origin prova"; do
      if prova_guardia "$c"; then riga OK "$(msg maat-doctor.guard_ok c="$c")"
      else riga MANCA "$(msg maat-doctor.guard_ko c="$c" why="$GMOT")"; fi
    done
    sonda=$("$FIC_PY" "$HERE/maat-config.py" sonda-produzione 2>/dev/null | tr -d '\r' | head -1); src=$?
    if [ "$src" = 3 ]; then riga OK "$(msg maat-doctor.no_probe)"
    elif [ "$src" != 0 ] || [ -z "$sonda" ]; then riga MANCA "$(msg maat-doctor.probe_failed src="$src")"
    elif prova_guardia "$sonda"; then riga OK "$(msg maat-doctor.probe_ok sonda="$sonda")"
    else riga MANCA "$(msg maat-doctor.probe_ko sonda="$sonda" why="$GMOT")"; fi
  fi
  emetti < <(py aggancio)
fi

# --- working folder ---------------------------------------------------------------------------------------------------
LAVORO=${LAVORO%/}
W="$ROOT/$LAVORO"
if [ ! -d "$W" ]; then riga MANCA "$(msg maat-doctor.work_missing lav="$LAVORO" lav="$LAVORO")"
elif [ ! -w "$W" ]; then riga MANCA "$(msg maat-doctor.work_readonly lav="$LAVORO")"
elif git -C "$ROOT" check-ignore -q -- "$LAVORO" 2>/dev/null || git -C "$ROOT" check-ignore -q -- "$LAVORO/" 2>/dev/null; then
  riga OK "$(msg maat-doctor.work_ignored lav="$LAVORO")"
else riga OK "$(msg maat-doctor.work_tracked lav="$LAVORO")"; fi

echo "maat-doctor: $(msg maat-doctor.summary nok="$nok" natt="$natt" nman="$nman")"
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
# the message catalog (1.4.0), next to this doctor; the tests load this part with MAAT_ROOT only, hence the fallback
_s = importlib.util.spec_from_file_location(
    "maat_msg", os.environ.get("MAAT_MSG_PY") or posixpath.join(PLUGIN, "scripts", "maat_msg.py"))
_m = importlib.util.module_from_spec(_s)
_s.loader.exec_module(_m)
T = _m.T
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
        return False, T("maat-doctor.wsl_not_on_path"), None
    try:
        r = subprocess.run([w, "--", "true"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=TIMEOUT_WSL)
    except subprocess.TimeoutExpired:
        return False, T("maat-doctor.wsl_timeout", n=TIMEOUT_WSL), None
    except OSError as e:
        return False, T("maat-doctor.wsl_cannot_run", e=e), None
    if r.returncode != 0:
        return False, T("maat-doctor.wsl_exit", rc=r.returncode), None
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
        riga("MANCA", T("maat-doctor.config_missing", p=mc.percorso_config()), T("maat-doctor.run_setup"))
        return
    if rc != 0:
        meta("valida", rc)
        dett = [l.replace("maat-config: ", "") for l in buf.getvalue().splitlines() if l.strip()][:3]
        riga("MANCA", T("maat-doctor.config_invalid", d="; ".join(dett) or msg), T("maat-doctor.config_invalid_fix"))
        return
    meta("valida", 0)
    r = mc.risolto(cfg)
    meta("lavoro", r.get("cartelle", {}).get("lavoro", ".claude/.ai-workflow"))
    riga("OK", T("maat-doctor.config_valid", p=p))
    vp = versione_plugin()
    h = cfg.get("harness")
    if h:
        if vp and tupla(vp)[:2] >= tupla(h)[:2]:
            riga("OK", T("maat-doctor.version_ok", vp=vp, h=h))
        else:
            riga("MANCA", T("maat-doctor.version_ko", vp=vp or T("maat-doctor.version_unknown"), h=h),
                 T("maat-doctor.version_fix"))
    else:
        riga("OK", T("maat-doctor.version_no_harness", vp=vp or T("maat-doctor.version_unknown")))

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
                    riga("MANCA", T("maat-doctor.wsl_required", why=wsl_motivo), T("maat-doctor.wsl_required_fix"))
                elif not wsl_mod:
                    riga("OK", T("maat-doctor.wsl_missing_ok", why=wsl_motivo))
                else:
                    riga("ATTENZIONE", T("maat-doctor.wsl_missing", why=wsl_motivo), T("maat-doctor.wsl_missing_below"))
        else:
            riga("OK", T("maat-doctor.wsl_not_required"))
    else:
        riga("OK", T("maat-doctor.not_windows"))
    inwsl = Sonde([wexe, "--", "bash", "-l", "-s"] if wsl else None)
    if wsl:
        node = r.get("piattaforma", {}).get("node_wsl")
        ib = esiste_cmd(inwsl, "bash")
        inode = inwsl.prova("[ -x %s ]" % sq(node)) if node and "/" in node else esiste_cmd(inwsl, node or "node")

        def wsl_righe(ib=ib, inode=inode, node=node):
            riga("OK", T("maat-doctor.wsl_reachable"))
            if not inwsl[ib]:
                riga("MANCA", T("maat-doctor.wsl_no_bash"), T("maat-doctor.wsl_no_bash_fix"))
            if inwsl[inode]:
                riga("OK", "Node in WSL (%s)" % (node or "node"))
            else:
                riga("MANCA" if wsl_mod else "ATTENZIONE", T("maat-doctor.wsl_no_node", node=node or "node"),
                     T("maat-doctor.wsl_no_node_fix"))
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
        out.append(lambda: riga("MANCA", T("maat-doctor.mod_wsl_not_windows", nome=nome),
                                T("maat-doctor.mod_wsl_not_windows_fix")))
    elif amb == "wsl" and not wsl:
        out.append(lambda: riga("MANCA", T("maat-doctor.mod_wsl_missing", nome=nome), T("maat-doctor.mod_wsl_missing_fix")))
    if not os.path.isdir(rad_abs):
        out.append(lambda: riga("MANCA", T("maat-doctor.mod_root_missing", nome=nome, rad=rad or "."),
                                T("maat-doctor.mod_root_fix")))
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
                    riga("OK", T("maat-doctor.py_wsl_ok", nome=nome, p=trovati[0]))
                    py["wsl"] = trovati[0]
                else:
                    py["ok"] = False
                    riga("MANCA", T("maat-doctor.py_wsl_missing", nome=nome, cand=", ".join(p for p, _ in idx)),
                         T("maat-doctor.py_wsl_fix"))
            out.append(py_righe)
        else:
            p = mc.risolvi_python(cfg, m, ROOT)
            ok = p is not None and (os.path.isfile(p) or os.path.isfile(p + ".exe") or shutil.which(p) is not None)
            if ok:   # an interpreter that is there but does not start (e.g. the Store stub without Python) counts as missing
                try:
                    ok = subprocess.run([p, "-c", "import sys"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL, timeout=20).returncode == 0
                except (OSError, subprocess.TimeoutExpired):
                    ok = False

            def py_righe(p=p, ok=ok):
                if ok:
                    riga("OK", T("maat-doctor.py_ok", nome=nome, p=p))
                else:
                    py["ok"] = False
                    riga("MANCA", T("maat-doctor.py_missing", nome=nome, p=p or T("maat-doctor.py_no_candidate")),
                         T("maat-doctor.py_fix"))
            out.append(py_righe)

    def eseguibile(etichetta, txt, cart_abs, se_presente=None, livello="MANCA", rimedio=""):
        """Registers the probe of the first executable of txt; returns the function that prints the line."""
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
                riga("OK", "%s: %s" % (etichetta, exe or T("maat-doctor.shell_command")))
            elif se_presente:
                riga("ATTENZIONE", T("maat-doctor.check_skipped", et=etichetta, miss=", ".join(mancanti)),
                     T("maat-doctor.check_skipped_fix", miss=", ".join(mancanti)))
            else:
                riga(livello, T("maat-doctor.not_found", et=etichetta, miss=", ".join(mancanti)),
                     rimedio or T("maat-doctor.not_found_fix"))
        return stampa

    # --- comandi (commands)
    for tipo, c in m.get("comandi", {}).items():
        c = {"comando": c} if isinstance(c, str) else c
        quale = c.get("cartella", "radice")
        cart = mc.cartella_di(m, quale)
        cart_abs = posixpath.join(ROOT, cart) if cart else ROOT
        et = T("maat-doctor.command_of", tipo=tipo, nome=nome)
        if not os.path.isdir(cart_abs):
            out.append(lambda et=et, cart=cart, quale=quale: riga(
                "MANCA", T("maat-doctor.folder_missing", et=et, cart=cart or ".", quale=quale), T("maat-doctor.folder_fix")))
            continue
        if c.get("se_presente") and not mc.presente(c["se_presente"], rad_abs):
            out.append(lambda et=et, sp=c["se_presente"]: riga("OK", T("maat-doctor.not_run_present", et=et, sp=sp)))
            continue
        out.append(eseguibile(et, c["comando"], cart_abs))
        if tipo == "test" and (m.get("report") or "nessuno") == "nessuno":
            # D-B (1.6.0): every new plan is format 2, and its test-red phase reads the outcome of each test from the
            # report: without one the full cycle stops BLOCKED at test-red. ATTENZIONE, not MANCA: plan and review
            # cycles work without it, and a project that only uses them keeps its exit code.
            out.append(lambda: riga("ATTENZIONE", T("maat-doctor-z.report_none", nome=nome), T("maat-doctor-z.report_none_fix")))

    # --- controlli (checks)
    for j, v in enumerate(m.get("controlli", [])):
        out.append(eseguibile(T("maat-doctor.check_of", j=j, nome=nome, glob=v["glob"]), v["comando"], rad_abs,
                              se_presente=v.get("se_presente")))

    # --- controprova (counterproof)
    cp = m.get("controprova")
    if not cp or not cp.get("comando"):
        out.append(lambda: riga("OK", T("maat-doctor.cp_not_run", nome=nome)))
    else:
        if cp.get("runner") == "comando":
            out.append(eseguibile(T("maat-doctor.cp_of", nome=nome), cp["comando"], rad_abs))
        elif "{python}" in cp["comando"]:
            out.append(eseguibile(T("maat-doctor.cp_of", nome=nome), "{python}", rad_abs))
        if usabile:
            # the tools of counterproof.sh (pk08): rsync and flock have a fallback (tar, mkdir), the others do not
            st = [(s, esiste_cmd(sonde, s)) for s in ("rsync", "flock", "tar", "sha256sum", "timeout")]

            def strumenti(st=st):
                ha = {s: sonde[i] for s, i in st}
                manca = [s for s in ("sha256sum", "timeout") if not ha[s]]
                if not ha["rsync"] and not ha["tar"]:
                    manca.append(T("maat-doctor.rsync_and_tar"))
                assenti = [s for s in ("rsync", "flock") if not ha[s]]
                if manca:
                    riga("ATTENZIONE", T("maat-doctor.cp_blocked", nome=nome, miss=", ".join(manca)),
                         T("maat-doctor.cp_blocked_fix", miss=", ".join(manca),
                           where="in WSL" if amb == "wsl" else T("maat-doctor.here")))
                elif assenti:
                    cosa = {("rsync",): T("maat-doctor.no_rsync"), ("flock",): T("maat-doctor.no_flock"),
                            ("rsync", "flock"): T("maat-doctor.no_rsync_flock")}
                    riga("OK", T("maat-doctor.cp_tools", nome=nome, what=cosa[tuple(assenti)]))
                else:
                    riga("OK", T("maat-doctor.cp_tools_ok", nome=nome,
                                 where="in WSL" if amb == "wsl" else T("maat-doctor.present")))
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
                riga("OK", T("maat-doctor.copy_ok", nome=nome))
            elif inwsl[i_semina]:
                riga("ATTENZIONE", T("maat-doctor.copy_seed", nome=nome), T("maat-doctor.copy_seed_fix", setup=setup))
            else:
                riga("MANCA", T("maat-doctor.copy_missing", nome=nome), T("maat-doctor.copy_missing_fix", setup=setup))
        out.append(copia)

    # --- preparati: the guide file (the first glob without wildcards)
    guida = next((g for g in m.get("preparati", []) if not any(ch in g for ch in "*?[")), None)
    if guida:
        ok = os.path.exists(posixpath.join(rad_abs, guida))
        out.append(lambda ok=ok, guida=guida: riga(
            "OK", T("maat-doctor.prep_ok", nome=nome, guida=guida)) if ok else riga(
            "ATTENZIONE", T("maat-doctor.prep_missing", nome=nome, guida=guida),
            T("maat-doctor.prep_fix", prep=m.get("preparazione", T("maat-doctor.prep_default")))))

    # --- copia_anche: repo folders that the counterproofs copy
    for d in m.get("copia_anche", []):
        ok = os.path.isdir(posixpath.join(ROOT, mc.norm(d)))
        out.append(lambda ok=ok, d=d: riga("OK", T("maat-doctor.also_ok", nome=nome, d=d)) if ok else riga(
            "MANCA", T("maat-doctor.also_missing", nome=nome, d=d), T("maat-doctor.also_fix")))

    # --- collega_nel_worktree: the folders present in the main tree
    for v in m.get("collega_nel_worktree", []):
        v = {"percorso": v} if isinstance(v, str) else v
        cart = mc.cartella_di(m, v.get("cartella", "radice"))
        pat = posixpath.join(ROOT, cart, v["percorso"]) if cart else posixpath.join(ROOT, v["percorso"])
        ok = any(os.path.isdir(x) for x in glob.glob(pat))
        dov = posixpath.join(cart, v["percorso"]) if cart else v["percorso"]
        out.append(lambda ok=ok, dov=dov: riga("OK", T("maat-doctor.link_ok", nome=nome, dov=dov))
                   if ok else riga("ATTENZIONE", T("maat-doctor.link_missing", nome=nome, dov=dov),
                                   T("maat-doctor.link_fix")))

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
        out.append(lambda ok=ok, spec=spec: riga("OK", T("maat-doctor.deps_ok", nome=nome, g=spec[7:])) if ok
                   else riga("ATTENZIONE", T("maat-doctor.deps_untracked", nome=nome, g=spec[7:]),
                             T("maat-doctor.deps_fix")))

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
        riga("ATTENZIONE", T("maat-doctor.trial_no_test", nome=nome, rule=m.get("regola_test", "accanto")),
             T("maat-doctor.trial_no_test_fix"))
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
        riga("MANCA", T("maat-doctor.trial_unresolved", nome=nome, why=u.messaggio or u.codice), T("maat-doctor.trial_fix"))
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
            # MAAT_LINGUA too (resolved at the top): wsl.exe does not pass the environment, and the last line of the
            # trial (a message of test-fast.sh) goes into maat-doctor.trial_ko
            s = "export MAAT_MODULO=%s MAAT_CONFIG=%s MAAT_LINGUA=%s\ncd %s && %s\n" % (
                sq(nome), sq(wslp(os.environ.get("MAAT_CONFIG", ""))), sq(_m.lingua()), sq(wslp(cart_abs)), line)
            w = shutil.which("wsl") or shutil.which("wsl.exe")
            res = subprocess.run([w, "--", "bash", "-l", "-s"], input=s.encode("utf-8"), stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, timeout=900)
        else:
            env = dict(os.environ, MAAT_MODULO=nome)
            res = subprocess.run([BASH, "-c", "cd %s && %s" % (sq(cart_abs), line)], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900, env=env)
    except subprocess.TimeoutExpired:
        riga("MANCA", T("maat-doctor.trial_timeout", nome=nome, t=t), T("maat-doctor.trial_timeout_fix"))
        return
    ultima = ([l for l in res.stdout.decode("utf-8", "replace").replace("\r", "").splitlines() if l.strip()] or [""])[-1]
    if res.returncode == 0:
        riga("OK", T("maat-doctor.trial_ok", nome=nome, t=t))
    else:
        riga("MANCA", T("maat-doctor.trial_ko", nome=nome, t=t, rc=res.returncode, last=ultima[:160]),
             T("maat-doctor.trial_ko_fix"))


def controlli_progetto(mc, cfg, r, locale):
    out = []

    def comando_progetto(etichetta, txt):
        if re.fullmatch(r"/[A-Za-z0-9:_-]+", txt.strip()):
            out.append(lambda: riga("OK", T("maat-doctor.session_command", et=etichetta, cmd=txt.strip())))
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
                riga("MANCA", T("maat-doctor.not_found", et=etichetta, miss=", ".join(manca)),
                     T("maat-doctor.not_found_fix_project"))
            else:
                riga("OK", "%s: %s" % (etichetta, exe or T("maat-doctor.shell_command")))
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
                "ATTENZIONE", T("maat-doctor.suite_missing", nome=nome), T("maat-doctor.suite_fix")))

    # production probes and regexes
    prod, sonde = g.get("produzione", []), g.get("sonde", [])
    rx = []
    for p in prod:
        try:
            rx.append((p, re.compile(p, re.I)))
        except re.error as e:
            out.append(lambda p=p, e=e: riga("MANCA", T("maat-doctor.regex_invalid", p=p, e=e), T("maat-doctor.regex_fix")))
    for s in sonde:
        cmd = "curl -s https://%s/" % s
        ok = any(x.search(cmd) for _p, x in rx)
        out.append(lambda ok=ok, s=s: riga("OK", T("maat-doctor.probe_covered", s=s)) if ok else riga(
            "MANCA", T("maat-doctor.probe_uncovered", s=s), T("maat-doctor.probe_uncovered_fix")))
    if sonde:
        for p, x in rx:
            if not any(x.search("curl -s https://%s/" % s) for s in sonde):
                out.append(lambda p=p: riga("ATTENZIONE", T("maat-doctor.rule_untested", p=p),
                                            T("maat-doctor.rule_untested_fix")))
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
    # the user's configuration folder: CLAUDE_CONFIG_DIR when set, as Claude Code reads it (1.6.1), otherwise ~/.claude
    cfg = (os.environ.get("CLAUDE_CONFIG_DIR") or "").replace("\\", "/").rstrip("/") or posixpath.join(home, ".claude")
    utente = posixpath.join(cfg, "settings.json")
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
        riga("ATTENZIONE", T("maat-doctor.hook_double", dove=rel(dove)), T("maat-doctor.hook_double_fix"))
    elif abilitato:
        riga("OK", T("maat-doctor.hook_plugin", mk="@" + mk if mk else "", dove=rel(dove)))
    elif hook:
        riga("OK", T("maat-doctor.hook_project"))
    else:
        riga("MANCA", T("maat-doctor.hook_none"), T("maat-doctor.hook_none_fix"))
    if abilitato and mk:
        km = leggi_json(posixpath.join(cfg, "plugins", "known_marketplaces.json")).get(mk, {})
        ex = leggi_json(progetto).get("extraKnownMarketplaces", {})
        ex = ex.get(mk, {}) if isinstance(ex, dict) else {}
        fonti = [x.get("source") for x in (km, ex) if isinstance(x, dict)]
        if any((s.get("source") if isinstance(s, dict) else s) == "directory" for s in fonti):
            riga("ATTENZIONE", T("maat-doctor.marketplace_dir", mk=mk), T("maat-doctor.marketplace_dir_fix"))


MODI = {"piattaforma": cmd_piattaforma, "config": cmd_config, "aggancio": cmd_aggancio}
if __name__ == "__main__":   # otherwise loaded by the tests (maat-doctor.test.sh, «unità» section), without running anything
    if len(sys.argv) < 2 or sys.argv[1] not in MODI:
        sys.stderr.write("maat-doctor (python): %s\n" % T("maat-doctor.bad_mode"))
        sys.exit(64)
    sys.exit(MODI[sys.argv[1]]() or 0)
