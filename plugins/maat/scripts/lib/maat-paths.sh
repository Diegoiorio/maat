# maat-paths.sh — risolutore unico delle due radici (pk04a-1, passo 1). Da includere con `.` all'inizio di ogni
# script bash del harness; eseguito direttamente (`bash maat-paths.sh`) stampa le variabili, una per riga
# «NOME=valore» (diagnosi e test: stesso formato di `maat_paths.py`).
#
#   MAAT_ROOT     radice del plugin: MAAT_ROOT dell'ambiente se impostata, altrimenti due livelli sopra questo file.
#                 Deve contenere .claude-plugin/plugin.json, altrimenti errore ed uscita 4.
#   PROJECT_ROOT  radice del progetto: FIC_REPO se impostata, altrimenti `git rev-parse --show-toplevel` lanciato
#                 dalla CARTELLA DI LAVORO (mai dalla posizione dello script). Fuori da un repo git resta vuota:
#                 chi ne ha bisogno chiama `maat_progetto`, che stampa un errore chiaro e ritorna 4 (eseguito
#                 direttamente, questo file esce con 4).
#   MAAT_SCRIPTS  $MAAT_ROOT/scripts · MAAT_SKILLS $MAAT_ROOT/skills · MAAT_AGENTS $MAAT_ROOT/agents ·
#   MAAT_SCHEMAS  $MAAT_ROOT/schemas
#   MAAT_WORK     $PROJECT_ROOT/<cartelle.lavoro> (maat.json, letta con maat_conf; default .claude/.ai-workflow).
#                 Vuota senza progetto.
#
# Forma dei percorsi: su Windows (Git Bash) C:/… come `pwd -W` e come l'uscita di git; altrove quella di `pwd`.
# Il lock delle fasi di codice NON usa PROJECT_ROOT: run-phase.sh lo calcola dalla cartella di lavoro.
# Nessuna variabile e' esportata: ogni script la ricalcola dalla propria posizione e dalla propria cartella.

_maat_paths_err() { echo "maat: $*" >&2; }

# Percorso in forma C:/… per i programmi Windows: gli script che passano percorsi a Python, WSL o pytest chiamano
# questa, mai cygpath -m direttamente (resta solo `mostra` di cycle-state.sh, gemella di driver.py). cygpath -m antepone //?/
# ai percorsi oltre MAX_PATH (260): un run dir dal nome lungo diventava //?/C:/… e pytest in WSL non scriveva il JUnit.
# maat_cygm toglie il prefisso. Argomenti come cygpath -m (anche `maat_cygm -a <percorso>`); non-zero se cygpath
# manca o fallisce (chi la chiama tiene il proprio ripiego).
maat_cygm() { local o; o=$(cygpath -m "$@" 2>/dev/null) || return 1; printf '%s' "${o#//\?/}"; }

if [ -n "${MAAT_ROOT:-}" ]; then
  MAAT_ROOT=${MAAT_ROOT%/}
else
  MAAT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && { pwd -W 2>/dev/null || pwd; })
fi
if [ -z "$MAAT_ROOT" ] || [ ! -f "$MAAT_ROOT/.claude-plugin/plugin.json" ]; then
  _maat_paths_err "MAAT_ROOT='$MAAT_ROOT' non e' la radice di un plugin maat (manca .claude-plugin/plugin.json)"
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

maat_progetto() { # PROJECT_ROOT obbligatoria: errore chiaro e 4 se manca
  [ -n "${PROJECT_ROOT:-}" ] && return 0
  _maat_paths_err "la cartella di lavoro $(pwd) non e' in un repository git: PROJECT_ROOT non risolta" \
    "(lancia dalla cartella del progetto, o imposta FIC_REPO)"
  return 4
}

MAAT_WORK=""
if [ -n "$PROJECT_ROOT" ]; then
  _maat_lavoro=.claude/.ai-workflow
  if [ -n "${MAAT_CONFIG:-}" ] || [ -f "$PROJECT_ROOT/.claude/maat.json" ]; then
    # il file c'e': cartelle.lavoro dal lettore unico (il default dello schema e' lo stesso)
    if . "$MAAT_SCRIPTS/lib/maat-conf.sh" && _v=$(PROJECT_ROOT=$PROJECT_ROOT maat_conf cartelle.lavoro --default "$_maat_lavoro"); then
      [ -n "$_v" ] && _maat_lavoro=$_v
    else
      _maat_paths_err "cartelle.lavoro non letta da maat.json: uso il default $_maat_lavoro"
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
