# maat-conf.sh — interfaccia bash del lettore unico (scripts/maat-config.py). Da includere con `.`.
#
#   maat_conf <chiave.puntata> [--default x]   valore con i default dello schema; chiave assente: return 3
#   maat_modulo_di <file relativo al repo>      «<nome> radice» | «<nome> pacchetti» | return 2
#   maat_comando <modulo> <tipo> [opzioni]      due righe: cartella d'esecuzione e comando espanso
#   maat_gate_richiesti <livello> [file…]       i gate del livello: «etichetta<TAB>modulo<TAB>tipo»
#   maat_conf_carica                            legge il file una volta sola (cache per processo)
#
# Cache: maat_conf carica tutte le chiavi alla prima chiamata (`maat-config.py leggi --tutto`) nella variabile
# _MAAT_CACHE e poi non rilegge più il file. Una chiamata dentro $(…) gira in una subshell e la sua cache si perde:
# chi chiama più volte lancia maat_conf_carica una volta nella shell principale, e le subshell la ereditano.
# Il file: MAAT_CONFIG, altrimenti <PROJECT_ROOT>/.claude/maat.json (regole di maat-config.py).
# L'interprete: quello di python.sh (FIC_PY), lo stesso del resto del harness.

_MAAT_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_MAAT_PY="$(dirname "$_MAAT_LIB")/maat-config.py"
if [ -z "${FIC_PY:-}" ]; then . "$(dirname "$_MAAT_LIB")/python.sh" || true; fi
declare -gA _MAAT_CACHE=()
_MAAT_CARICATA=""

maat_conf_carica() {
  local out k v
  [ -n "${FIC_PY:-}" ] || { echo "maat-conf: interprete Python non trovato" >&2; return 2; }
  out=$("$FIC_PY" "$_MAAT_PY" leggi --tutto) || return $?
  _MAAT_CACHE=()
  while IFS=$'\t' read -r k v; do
    [ -n "$k" ] && _MAAT_CACHE[$k]=$v
  done <<< "$out"
  _MAAT_CARICATA=1
}

maat_conf() {
  local k=${1:-}
  [ -n "$k" ] || { echo "uso: maat_conf <chiave.puntata> [--default x]" >&2; return 64; }
  if [ -z "$_MAAT_CARICATA" ]; then maat_conf_carica || return $?; fi
  if [[ -v "_MAAT_CACHE[$k]" ]]; then
    printf '%s\n' "${_MAAT_CACHE[$k]}"
  elif [ "${2:-}" = --default ] && [ $# -ge 3 ]; then
    printf '%s\n' "$3"
  else
    echo "maat-conf: chiave assente: $k" >&2
    return 3
  fi
}

maat_modulo_di() { "$FIC_PY" "$_MAAT_PY" modulo-di "$@"; }

maat_comando() { "$FIC_PY" "$_MAAT_PY" comando "$@"; }

# I gate di un livello, una riga «etichetta<TAB>modulo<TAB>tipo» (maat-config.py gate-richiesti): la stessa lista
# per gates.sh (cosa eseguire) e finalize.sh (cosa richiedere; build resta facoltativo). I file toccati decidono
# solo il gate tests-<modulo> di un modulo senza comando di test (NOT RUN dichiarato).
maat_gate_richiesti() { # <livello> [file…]
  local l=${1:-} a=() f
  [ -n "$l" ] || { echo "uso: maat_gate_richiesti <livello> [file…]" >&2; return 64; }
  shift
  for f in "$@"; do a+=(--file "$f"); done
  "$FIC_PY" "$_MAAT_PY" gate-richiesti "$l" ${a[@]+"${a[@]}"}
}
