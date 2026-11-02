# maat-conf.sh — bash interface of the single reader (scripts/maat-config.py). To be sourced with `.`.
#
#   maat_conf <dotted.key> [--default x]       value with the schema defaults; missing key: return 3
#   maat_modulo_di <file relative to the repo>  «<nome> radice» | «<nome> pacchetti» | return 2
#   maat_comando <module> <type> [options]      two lines: execution folder and expanded command
#   maat_gate_richiesti <level> [file…]         the gates of the level: «etichetta<TAB>modulo<TAB>tipo»
#   maat_conf_carica                            reads the file only once (per-process cache)
#
# Cache: maat_conf loads all keys on the first call (`maat-config.py leggi --tutto`) into the variable
# _MAAT_CACHE and then never rereads the file. A call inside $(…) runs in a subshell and its cache is lost:
# a caller that calls several times runs maat_conf_carica once in the main shell, and the subshells inherit it.
# The file: MAAT_CONFIG, otherwise <PROJECT_ROOT>/.claude/maat.json (rules of maat-config.py).
# The interpreter: the one from python.sh (FIC_PY), the same as the rest of the harness.

_MAAT_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_MAAT_PY="$(dirname "$_MAAT_LIB")/maat-config.py"
if [ -z "${FIC_PY:-}" ]; then . "$(dirname "$_MAAT_LIB")/python.sh" || true; fi
# messages (1.4.0): the catalog next to this file; sourced only if the caller has not loaded it (it would empty its cache)
declare -F msg >/dev/null || . "$_MAAT_LIB/maat-msg.sh"
declare -gA _MAAT_CACHE=()
_MAAT_CARICATA=""

maat_conf_carica() {
  local out k v
  [ -n "${FIC_PY:-}" ] || { echo "maat-conf: $(msg maat-conf.no_python)" >&2; return 2; }
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
    echo "maat-conf: $(msg maat-conf.key_missing k="$k")" >&2
    return 3
  fi
}

maat_modulo_di() { "$FIC_PY" "$_MAAT_PY" modulo-di "$@"; }

maat_comando() { "$FIC_PY" "$_MAAT_PY" comando "$@"; }

# The gates of a level, one line «etichetta<TAB>modulo<TAB>tipo» each (maat-config.py gate-richiesti): the same list
# for gates.sh (what to run) and finalize.sh (what to require; build stays optional). The touched files decide
# only the tests-<modulo> gate of a module without a test command (declared NOT RUN).
maat_gate_richiesti() { # <level> [file…]
  local l=${1:-} a=() f
  [ -n "$l" ] || { echo "uso: maat_gate_richiesti <livello> [file…]" >&2; return 64; }
  shift
  for f in "$@"; do a+=(--file "$f"); done
  "$FIC_PY" "$_MAAT_PY" gate-richiesti "$l" ${a[@]+"${a[@]}"}
}
