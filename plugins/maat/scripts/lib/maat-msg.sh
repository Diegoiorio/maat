# maat-msg.sh — the message catalog of Maat in bash (1.4.0), twin of scripts/maat_msg.py. To be sourced with `.`.
#
#   maat_lingua [-v var]               it|en (printed with a newline, or assigned to var)
#   maat_msg_carica                    reads the catalog once, and the language of maat.json if MAAT_LINGUA is unset
#   msg [-v var] <key> [name=value…]   the text of the key in the current language, placeholders replaced; printed
#                                      WITHOUT a newline, or assigned to var (like printf -v: no subshell)
#
# Language: MAAT_LINGUA if set and not empty (it|en; any other value: en), otherwise `lingua` of .claude/maat.json read
# by the single reader (maat-config.py leggi; maat.json missing or invalid: en), otherwise en. Only the variable is
# read at every call; the value of maat.json is cached per path (MAAT_CONFIG, PROJECT_ROOT and working directory).
# The entry scripts resolve once and export MAAT_LINGUA (block B): children never reread maat.json.
# Catalog: messages.tsv next to this file, never from a variable of the caller (a copy of the plugin uses its own).
# CRs are dropped on reading. Format and rules: the header of messages.tsv.
# Substitution (same rules as maat_msg.py, same bytes): left to right, {{ → {, }} → }, {name} → the value as it is
# (never rescanned), any other brace stays. A value missing → {name} stays and one warning on stderr. Never printf with
# catalog text as the format, values always quoted.
# Missing key or catalog: the key between ‹ › as the text, one warning on stderr (at most one per call); the return
# code is 0, so the caller's exit code does not change. Usage errors (bad var name, argument without =): 64.
# Cache: maat_msg_carica (or the first msg) fills _MAAT_MSG (key → whole line); a call inside $(…) runs in a subshell
# and its cache is lost: every script that uses msg runs maat_msg_carica in its main shell, and the subshells inherit it.
# Cost (block A, Git Bash on Windows): the file is read with $(<…) and split by IFS, never with mapfile or read (one
# system call per byte there: 200 ms for 1000 entries); the line is split into en and it only for the key printed.

shopt -u patsub_replacement 2>/dev/null || true   # bash 5.2: & in a ${x//p/r} replacement is literal again
_MAAT_MSG_LIB=${BASH_SOURCE[0]%/*}
[ "$_MAAT_MSG_LIB" = "${BASH_SOURCE[0]}" ] && _MAAT_MSG_LIB=.
case $_MAAT_MSG_LIB in /*|[A-Za-z]:[/\\]*) ;; *) _MAAT_MSG_LIB=$PWD/$_MAAT_MSG_LIB ;; esac   # no fork: no $(cd …)
_MAAT_MSG_TSV=$_MAAT_MSG_LIB/messages.tsv
declare -gA _MAAT_MSG=() _MAAT_MSG_CONF=()
_MAAT_MSG_CARICATO=""

maat_msg_carica() {
  local _mm_s _mm_l _mm_f="" IFS
  local -a _mm_righe=()
  _MAAT_MSG=()
  _MAAT_MSG_CARICATO=1
  if [ -f "$_MAAT_MSG_TSV" ] && [ -r "$_MAAT_MSG_TSV" ]; then
    _mm_s=$(<"$_MAAT_MSG_TSV")
    _mm_s=${_mm_s//$'\r'/}
    case $- in *f*) _mm_f=1 ;; esac
    set -f; IFS=$'\n'
    _mm_righe=($_mm_s)   # blank lines vanish, as maat_msg.py skips them
    IFS=$' \t\n'; [ -n "$_mm_f" ] || set +f
    for _mm_l in ${_mm_righe[@]+"${_mm_righe[@]}"}; do
      # exactly two TABs and a key, as maat_msg.py (split gives three fields); comments out
      case $_mm_l in '#'*|$'\t'*|*$'\t'*$'\t'*$'\t'*) ;; *$'\t'*$'\t'*) _MAAT_MSG[${_mm_l%%$'\t'*}]=$_mm_l ;; esac
    done
  else
    _MAAT_MSG_CARICATO=missing
  fi
  [ -n "${MAAT_LINGUA:-}" ] || _maat_msg_lingua
  return 0
}

# The language in _MAAT_MSG_L (no subshell).
_maat_msg_lingua() {
  local _mm_c _mm_v _mm_rc
  if [ -n "${MAAT_LINGUA:-}" ]; then
    case $MAAT_LINGUA in it|en) _MAAT_MSG_L=$MAAT_LINGUA ;; *) _MAAT_MSG_L=en ;; esac
    return 0
  fi
  _mm_c="${MAAT_CONFIG:-}|${PROJECT_ROOT:-}|$PWD"
  if [[ -v "_MAAT_MSG_CONF[$_mm_c]" ]]; then _MAAT_MSG_L=${_MAAT_MSG_CONF[$_mm_c]}; return 0; fi
  if [ -z "${FIC_PY:-}" ]; then . "${_MAAT_MSG_LIB%/*}/python.sh" >/dev/null 2>&1 || true; fi
  _mm_v=""
  if [ -n "${FIC_PY:-}" ]; then
    _mm_v=$(PROJECT_ROOT=${PROJECT_ROOT:-} "$FIC_PY" "${_MAAT_MSG_LIB%/*}/maat-config.py" leggi lingua --default en 2>/dev/null)
    _mm_rc=$?
    [ "$_mm_rc" -eq 0 ] || _mm_v=""
  fi
  _mm_v=${_mm_v//$'\r'/}
  case $_mm_v in it|en) ;; *) _mm_v=en ;; esac
  _MAAT_MSG_CONF[$_mm_c]=$_mm_v
  _MAAT_MSG_L=$_mm_v
}

maat_lingua() {
  if [ "${1:-}" = -v ]; then
    [[ ${2:-} =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "usage: maat_lingua [-v var]" >&2; return 64; }
    _maat_msg_lingua
    printf -v "$2" '%s' "$_MAAT_MSG_L"
    return 0
  fi
  [ $# -eq 0 ] || { echo "usage: maat_lingua [-v var]" >&2; return 64; }
  _maat_msg_lingua
  printf '%s\n' "$_MAAT_MSG_L"
}

# Placeholders of _mm_t with the values of _mm_v → _mm_o; the names without a value in _mm_miss («{a}, {b}»).
# Called only by msg (it reads and sets msg's locals).
_maat_msg_sost() {
  local _mm_r=$_mm_t _mm_pre _mm_n
  _mm_o="" _mm_miss=""
  while :; do
    _mm_pre=${_mm_r%%[\{\}]*}
    if [ "$_mm_pre" = "$_mm_r" ]; then _mm_o+=$_mm_r; return 0; fi
    _mm_o+=$_mm_pre
    _mm_r=${_mm_r#"$_mm_pre"}
    case $_mm_r in
      '{{'*) _mm_o+='{'; _mm_r=${_mm_r#??} ;;
      '}}'*) _mm_o+='}'; _mm_r=${_mm_r#??} ;;
      '{'*)
        _mm_n=${_mm_r#?}; _mm_n=${_mm_n%%\}*}
        # a name is ASCII letters, digits and _ (explicit sets: a range would follow the locale)
        if [[ $_mm_r == "{$_mm_n}"* && -n $_mm_n && $_mm_n != [0123456789]* &&
              $_mm_n != *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]* ]]; then
          if [[ -v "_mm_v[$_mm_n]" ]]; then
            _mm_o+=${_mm_v[$_mm_n]}
          else
            _mm_o+="{$_mm_n}"
            case ", $_mm_miss, " in *", {$_mm_n}, "*) ;; *) _mm_miss+=${_mm_miss:+, }"{$_mm_n}" ;; esac
          fi
          _mm_r=${_mm_r#"{$_mm_n}"}
        else
          _mm_o+='{'; _mm_r=${_mm_r#?}
        fi ;;
      *) _mm_o+='}'; _mm_r=${_mm_r#?} ;;
    esac
  done
}

msg() {
  local _mm_var="" _mm_k _mm_a _mm_t _mm_o _mm_miss _mm_ok=""
  local -A _mm_v=()
  if [ "${1:-}" = -v ]; then
    _mm_var=${2:-}
    [[ $_mm_var =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "usage: msg [-v var] <key> [name=value…]" >&2; return 64; }
    shift 2
  fi
  _mm_k=${1:-}
  [ -n "$_mm_k" ] || { echo "usage: msg [-v var] <key> [name=value…]" >&2; return 64; }
  shift
  for _mm_a in "$@"; do
    case $_mm_a in
      [A-Za-z_]*=*) _mm_v[${_mm_a%%=*}]=${_mm_a#*=} ;;
      *) echo "msg: $_mm_k: argument without name=: $_mm_a" >&2; return 64 ;;
    esac
  done
  [ -n "$_MAAT_MSG_CARICATO" ] || maat_msg_carica
  _maat_msg_lingua
  # a key with other characters is never in the catalog (and never reaches an array subscript)
  if [[ $_mm_k != *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-]* && -v "_MAAT_MSG[$_mm_k]" ]]; then
    _mm_t=${_MAAT_MSG[$_mm_k]#*$'\t'}
    if [ "$_MAAT_MSG_L" = it ]; then _mm_t=${_mm_t#*$'\t'}; else _mm_t=${_mm_t%%$'\t'*}; fi
    [ -z "$_mm_t" ] || _mm_ok=1
  fi
  if [ -z "$_mm_ok" ]; then
    _mm_o="‹$_mm_k›"
    if [ "$_MAAT_MSG_CARICATO" = missing ]; then
      echo "maat-msg: message catalog not found: $_MAAT_MSG_TSV" >&2
    else
      echo "maat-msg: message key not in the catalog: $_mm_k" >&2
    fi
  else
    _maat_msg_sost
    [ -z "$_mm_miss" ] || echo "maat-msg: $_mm_k: no value for $_mm_miss" >&2
  fi
  if [ -n "$_mm_var" ]; then printf -v "$_mm_var" '%s' "$_mm_o"; else printf '%s' "$_mm_o"; fi
  return 0
}
