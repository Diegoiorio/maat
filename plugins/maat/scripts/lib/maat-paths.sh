# maat-paths.sh — single resolver of the two roots (pk04a-1, step 1). To be sourced with `.` at the start of every
# bash script of the harness; run directly (`bash maat-paths.sh`) it prints the variables, one per line
# «NOME=valore» (diagnostics and tests: same format as `maat_paths.py`).
#
#   MAAT_ROOT     plugin root: MAAT_ROOT from the environment if set, otherwise two levels above this file.
#                 It must contain .claude-plugin/plugin.json, otherwise error and exit 4.
#   PROJECT_ROOT  project root: FIC_REPO if set, otherwise `git rev-parse --show-toplevel` run
#                 from the WORKING DIRECTORY (never from the script location). Outside a git repo it stays empty:
#                 whoever needs it calls `maat_progetto`, which prints a clear error and returns 4 (when run
#                 directly, this file exits with 4).
#   MAAT_SCRIPTS  $MAAT_ROOT/scripts · MAAT_SKILLS $MAAT_ROOT/skills · MAAT_AGENTS $MAAT_ROOT/agents ·
#   MAAT_SCHEMAS  $MAAT_ROOT/schemas
#   MAAT_WORK     $PROJECT_ROOT/<cartelle.lavoro> (maat.json, read with maat_conf; default .claude/.ai-workflow).
#                 Empty without a project.
#
# Path form: on Windows (Git Bash) C:/… like `pwd -W` and like git's output; elsewhere that of `pwd`.
# The lock of the code phases does NOT use PROJECT_ROOT: run-phase.sh computes it from the working directory.
# No variable is exported: each script recomputes it from its own location and its own working directory.

_maat_paths_err() { echo "maat: $*" >&2; }
# Messages (1.4.0): these errors can come before the plugin is known (a MAAT_ROOT that is not a plugin), so the catalog
# is the one next to this file (lib/messages.tsv, read by lib/maat-msg.sh, sourced only on these paths); without it, the
# Italian text of 1.3.0 below, frozen in protocol-strings.list (Revisione 1 §9 of the 1.4.0 plan).
_maat_paths_cat() {
  local d=${BASH_SOURCE[0]%/*}
  [ "$d" = "${BASH_SOURCE[0]}" ] && d=.
  [ -f "$d/messages.tsv" ] && [ -f "$d/maat-msg.sh" ] || return 1
  declare -F msg >/dev/null || . "$d/maat-msg.sh"
}

# Path in C:/… form for Windows programs: scripts that pass paths to Python, WSL or pytest call
# this, never cygpath -m directly (only `mostra` of cycle-state.sh remains, twin of driver.py). cygpath -m prepends //?/
# to paths beyond MAX_PATH (260): a run dir with a long name became //?/C:/… and pytest in WSL did not write the JUnit.
# maat_cygm strips the prefix. Arguments as for cygpath -m (also `maat_cygm -a <path>`); non-zero if cygpath
# is missing or fails (the caller keeps its own fallback).
maat_cygm() { local o; o=$(cygpath -m "$@" 2>/dev/null) || return 1; printf '%s' "${o#//\?/}"; }

if [ -n "${MAAT_ROOT:-}" ]; then
  MAAT_ROOT=${MAAT_ROOT%/}
else
  MAAT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && { pwd -W 2>/dev/null || pwd; })
fi
if [ -z "$MAAT_ROOT" ] || [ ! -f "$MAAT_ROOT/.claude-plugin/plugin.json" ]; then
  if _maat_paths_cat; then _maat_paths_err "$(msg maat-paths.no_root root="$MAAT_ROOT")"
  else _maat_paths_err "MAAT_ROOT='$MAAT_ROOT' non e' la radice di un plugin maat (manca .claude-plugin/plugin.json)"; fi
  if [ "${BASH_SOURCE[0]}" = "$0" ]; then exit 4; else return 4; fi
fi
MAAT_SCRIPTS=$MAAT_ROOT/scripts
MAAT_SKILLS=$MAAT_ROOT/skills
MAAT_AGENTS=$MAAT_ROOT/agents
MAAT_SCHEMAS=$MAAT_ROOT/schemas

if [ -n "${FIC_REPO:-}" ]; then
  PROJECT_ROOT=$FIC_REPO
else
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r') || PROJECT_ROOT=""
fi

maat_progetto() { # PROJECT_ROOT required: clear error and 4 if missing
  [ -n "${PROJECT_ROOT:-}" ] && return 0
  if _maat_paths_cat; then
    _maat_paths_err "$(msg maat-paths.no_project cwd="$(pwd)")" "$(msg maat-paths.no_project_fix)"
  else
    local e="la cartella di lavoro $(pwd) non e' in un repository git: PROJECT_ROOT non risolta"
    _maat_paths_err "$e" "(lancia dalla cartella del progetto, o imposta FIC_REPO)"
  fi
  return 4
}

MAAT_WORK=""
if [ -n "$PROJECT_ROOT" ]; then
  _maat_lavoro=.claude/.ai-workflow
  if [ -n "${MAAT_CONFIG:-}" ] || [ -f "$PROJECT_ROOT/.claude/maat.json" ]; then
    # the file exists: cartelle.lavoro from the single reader (the schema default is the same)
    if . "$MAAT_SCRIPTS/lib/maat-conf.sh" && _v=$(PROJECT_ROOT=$PROJECT_ROOT maat_conf cartelle.lavoro --default "$_maat_lavoro"); then
      [ -n "$_v" ] && _maat_lavoro=$_v
    else
      if _maat_paths_cat; then _maat_paths_err "$(msg maat-paths.no_lavoro lavoro="$_maat_lavoro")"
      else _maat_paths_err "cartelle.lavoro non letta da maat.json: uso il default $_maat_lavoro"; fi
    fi
    unset _v
  fi
  MAAT_WORK=$PROJECT_ROOT/${_maat_lavoro%/}
  unset _maat_lavoro
fi

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  maat_progetto || exit 4
  for _k in MAAT_ROOT PROJECT_ROOT MAAT_SCRIPTS MAAT_SKILLS MAAT_AGENTS MAAT_SCHEMAS MAAT_WORK; do
    printf '%s=%s\n' "$_k" "${!_k}"
  done
  exit 0
fi
return 0
