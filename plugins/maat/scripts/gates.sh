#!/usr/bin/env bash
# gates.sh — the gates of the test level, run by the DRIVER (run-phase.sh) outside the sub-sessions,
# with evidence on file and reuse on an identical key (harness-pt04, 1d-1e). Modules and commands come from
# .claude/maat.json (single reader scripts/maat-config.py, interface scripts/lib/maat-conf.sh), never from here (R3.3).
#
#   bash gates.sh --run-dir <run-dir> <level> <touched files…>
#   bash gates.sh --verify <run-dir>/evidence/<key>
#
# <level>: min | std | full | legacy (legacy = std). Files are relative to the repository (touched.txt).
#
# ROUTING: each file goes to the module of `maat_modulo_di` — «radice» (counts for the module's tests, checks, lint
# and build) or «pacchetti» (under radice_pacchetti but outside the radice: lint and build only). A file outside every
# module is covered by no gate: the line «non coperto: …» says so.
#
# GATES — those of `maat_gate_richiesti <level>` (section `gate` of maat.json), one JSON file each:
#   tests-<module>      comandi.test on the tests that regola_test (accanto, specchio, nessuna) selects for the files of the
#                       radice. No test selected -> SKIPPED «nessun test esistente per: …»; no file under the
#                       radice -> SKIPPED «nessun file sotto <radice>» (never the whole suite); module WITHOUT a test
#                       command (or with regola nessuna) and with touched files -> NOT RUN «dichiarato: nessun test», never PASS;
#   controlli-<module>  each entry {glob, comando, se_presente?} on the touched files of the radice that match the
#                       glob, one invocation per file. FAIL if an executed entry exits != 0; PASS if at least one was
#                       executed; SKIPPED if no file matches; NOT RUN if all the relevant entries were
#                       skipped (se_presente missing from PATH: entry SALTATA in the `voci` field of the JSON and in the reason);
#   lint, build         comandi.lint (with {base?…} = <run-dir>/base.txt, if it exists) and comandi.build on the files of the
#                       radice and of the module's packages; `lint-<module>`/`build-<module>` if several modules declare them.
#   Each command runs from its `cartella` (radice | radice_pacchetti | repo), with MAAT_MODULO=<module> in the environment
#   (not in the command line); ambiente wsl -> inside WSL, nativo -> here. The gates of native modules run IN PARALLEL with the
#   wsl lane; within the wsl lane they run serially (the test-fast.sh copy has a single lock).
#
# EVIDENCE: <run-dir>/evidence/<key>/<gate>.json with the fields gate, esito (PASS|FAIL|BLOCKED|SKIPPED|NOT RUN),
# comando, exit, durata_s, report (file in the same directory; null if the gate was not run), riepilogo,
# motivo, file (selectors or paths), chiave, eseguito_il, and `voci` for the checks. Next to it: chiave.txt (the key
# components in clear) and argomenti.txt (level and files, for --verify). The report format is set by the
# `report` field of the MODULE, never by the gate name:
#   junit    report <gate>.junit.xml ({report} of the command): PASS only with a readable JUnit and at least one test;
#   vitest   report <gate>.log: PASS only with the wrapper's "esito=" line and the "Tests … passed" summary;
#   nessuno  report <gate>.log: PASS with exit 0 and a non-empty log, like build.
# lint is judged by the wrapper's "esito=" line (test-fast.sh). NEVER A PASS WITHOUT A REPORT: -> BLOCKED.
#
# KEY: sha256 of: tree of the WHOLE working tree (review-surface.sh tree: tracked, staged and untracked not
# ignored), level and commands (plugin root -> <maat>, project root -> <repo>: the key does not depend on
# where the plugin is installed; a version change is caught by the harness fingerprint), node and TZ in WSL (only
# if a module has ambiente wsl), python= (the {python} interpreter of the modules that use it, precedence of
# maat-config.py; the version for a wsl module is the one in WSL), the `chiave` entries of the modules ({etichetta, file} ->
# fingerprint of the file or «assente»; {etichetta, comando} -> its output, INSIDE WSL for a wsl module that uses {python}:
# the interpreter exists only there), TZ and CI (here).
#
# {python} OF A WSL MODULE (from a real case): without FIC_GATES_VENV_PY the interpreter is looked up INSIDE WSL among the
# candidates of moduli[].python (string or list, relative to the radice; the first that exists wins), otherwise
# piattaforma.python (relative to the repo), otherwise python3; a name without / is looked up in the WSL PATH. None exists
# -> the module's gates that use {python} are BLOCKED «python WSL assente», never PASS. The lookup command has no
# shell variables: `wsl -- bash -lc` passes it through a first shell that would expand them to empty. For the same
# reason a `chiave` entry run in WSL must not use shell variables. No per-module granularity: one byte changed anywhere -> new
# key, everything runs again. Reuse ONLY on an identical key and only of PASS/FAIL/SKIPPED/NOT RUN with the report present: a
# BLOCKED gate runs again. If the tree changes while the gates run, those executed become BLOCKED (the evidence would
# belong to no tree).
#
# Exit: 0 all PASS/SKIPPED/NOT RUN · 1 at least one FAIL · 3 at least one BLOCKED, no FAIL (also maat.json
#   missing or invalid) · 2 usage.
#   --verify: 0 FRESH (the directory key is the current one) · 1 STALE · 3 not verifiable (BLOCKED: maat.json
#   missing or invalid, tree not computable) · 2 usage.
# Stdout: one line per gate "<gate>: <ESITO> (eseguito|riuso) — <summary or reason>", the line "non coperto: …" if
#   some file is outside the modules, then the last one "gates: esito=<ESITO>[ (NOT RUN dichiarato: <gate…>)]
#   chiave=<key> evidence=<directory>".
# LANGUAGE (1.4.0): reasons and summaries come from the catalog (English by default, Italian with "lingua": "it"); the
#   quoted texts above are the Italian ones. Frozen in every language: the prefix "gates: esito=", the outcome words,
#   the tokens eseguito|riuso, and the key components that are not reasons («assente», «node=wsl non raggiungibile»,
#   «<non impostata>»). The key line of a gate that is not run carries its reason, so a key is per language: the
#   language is in the harness fingerprint (run-phase.sh), a cycle never mixes two.
# Variables (for tests): FIC_GATES_ROOT repository (default: PROJECT_ROOT, the project of the working directory) ·
# FIC_GATES_HARNESS plugin root (default MAAT_ROOT; scripts/review-surface.sh, scripts/python.sh,
# scripts/lib/maat-conf.sh and the {maat} of the commands) · FIC_GATES_WSL program that receives ONE bash command to run
# in WSL (default: wsl -- bash -lc) · FIC_GATES_VENV_PY interpreter of {python} (wins over maat.json and over the lookup in
# WSL; for a wsl module it is a WSL path, used as is) · MAAT_CONFIG.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_ROOT (plugin) and PROJECT_ROOT (working directory)
# Messages (1.4.0): the catalog next to this script. The language is resolved once and exported (finalize.sh and
# the commands of the gates read the same one); the embedded Python imports maat_msg.py from MAAT_MSG_PY.
. "$HERE/lib/maat-msg.sh"; maat_msg_carica
maat_lingua -v MAAT_LINGUA; export MAAT_LINGUA
MAAT_MSG_PY=$(maat_cygm "$HERE/maat_msg.py" 2>/dev/null || printf '%s' "$HERE/maat_msg.py"); export MAAT_MSG_PY
HROOT=${FIC_GATES_HARNESS:-$MAAT_ROOT}
ROOT=${FIC_GATES_ROOT:-$PROJECT_ROOT}
RS="$HROOT/scripts/review-surface.sh"
usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
win() { maat_cygm "$1" 2>/dev/null || printf '%s' "$1"; }
wslp() { # C:/x/y -> /mnt/c/x/y
  local w; w=$(win "$1")
  case $w in [A-Za-z]:/*) printf '/mnt/%s%s' "$(printf '%s' "${w:0:1}" | tr 'A-Z' 'a-z')" "${w:2}" ;; *) printf '%s' "$w" ;; esac
}
sq() { local s=${1//\'/\'\\\'\'}; printf "'%s'" "$s"; }
in_wsl() { # $1 = bash command to run inside WSL
  if [ -n "${FIC_GATES_WSL:-}" ]; then "$FIC_GATES_WSL" "$1"; else MSYS_NO_PATHCONV=1 wsl -- bash -lc "$1"; fi
}
sha() { sha256sum | cut -c1-64; }
tree_now() { (cd "$ROOT" && bash "$RS" tree) 2>/dev/null; }

run_dir="" verify=""
while [ $# -gt 0 ]; do
  case $1 in
    --run-dir) [ $# -ge 2 ] || usage; run_dir=$2; shift 2 ;;
    --verify) [ $# -ge 2 ] || usage; verify=$2; shift 2 ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) echo "gates: $(msg gates.unknown_option opt="$1")" >&2; exit 2 ;;
    *) break ;;
  esac
done
if [ -n "$verify" ]; then
  [ $# -eq 0 ] && [ -f "$verify/argomenti.txt" ] || { echo "gates: $(msg gates.verify_usage)" >&2; exit 2; }
  run_dir=$(cd "$verify/../.." && pwd) || exit 2
  mapfile -t args < <(tr -d '\r' < "$verify/argomenti.txt")
  set -- ${args[@]+"${args[@]}"}
fi
[ -n "$run_dir" ] && [ $# -ge 1 ] || usage
# Absolute: the test commands run in the module directory, and a relative {report} would end up there (new file
# not ignored => «albero cambiato durante i gate», report never found). run-phase.sh passes a relative run dir.
case $run_dir in /*|[A-Za-z]:[/\\]*) ;; *) run_dir="$PWD/$run_dir" ;; esac
level=$1; shift
case $level in min|std|full|legacy) ;; *) echo "gates: $(msg gates.unknown_level level="$level")" >&2; exit 2 ;; esac
[ -n "$ROOT" ] || { maat_progetto; exit 4; }
. "$HROOT/scripts/python.sh" || { echo "gates: $(msg gates.no_python)" >&2; exit 2; }
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8 PYTHONDONTWRITEBYTECODE=1
py() { sed '1,/^#__PYTHON__$/d' "$0" | "$FIC_PY" - "$@"; }   # the code comes from a pipe: no temporary file

blocca() { echo "gates: esito=BLOCKED ($1) chiave=- evidence=-"; exit 3; }
TMPD=$(mktemp -d) || blocca "$(msg gates.no_tmp)"
trap 'rm -rf "$TMPD"' EXIT
reader_err() { tr -d '\r' < "$TMPD/err" | sed 's/^maat-config: //' | grep -v '^$' | head -3 | tr '\n' ' ' | sed 's/ *$//'; }

# --- configuration: the single reader, loaded once in the main shell ---
export PROJECT_ROOT=$ROOT   # the reader finds <repo>/.claude/maat.json (MAAT_CONFIG wins)
. "$HROOT/scripts/lib/maat-conf.sh" 2>"$TMPD/err" || blocca "$(msg gates.conf_lib err="$(reader_err)")"
maat_conf_carica 2>"$TMPD/err" || blocca "maat.json: $(reader_err)"
lettore() { "$FIC_PY" "$_MAAT_PY" "$@"; }
normp() { local p=${1//\\//}; while [ "${p#./}" != "$p" ]; do p=${p#./}; done; p=${p%/}; [ "$p" = . ] && p=""; printf '%s' "$p"; }

MODS=()
declare -A M_IDX M_RAD M_RADS M_PAC M_PACS M_AMB M_REP
i=0
while n=$(maat_conf "moduli.$i.nome" 2>/dev/null); do
  MODS+=("$n"); M_IDX[$n]=$i
  M_RADS[$n]=$(maat_conf "moduli.$i.radice"); M_RAD[$n]=$(normp "${M_RADS[$n]}")
  M_PACS[$n]=$(maat_conf "moduli.$i.radice_pacchetti"); M_PAC[$n]=$(normp "${M_PACS[$n]}")
  M_AMB[$n]=$(maat_conf "moduli.$i.ambiente" --default nativo)
  M_REP[$n]=$(maat_conf "moduli.$i.report" --default nessuno)
  i=$((i + 1))
done
dichiara() { maat_conf "moduli.${M_IDX[$1]}.$2" >/dev/null 2>&1; }   # <module> <dotted.key>

mapfile -t FILES < <(printf '%s\n' "$@" | tr -d '\r' | sed 's|^\./||' | grep -v '^$' | LC_ALL=C sort -u)

# --- routing: radice (tests, checks, lint, build) or pacchetti (lint and build only) ---
declare -A RADF ALLF
UNCOV=()
for f in ${FILES[@]+"${FILES[@]}"}; do
  out=$(maat_modulo_di "$f" 2>"$TMPD/err" | tr -d '\r'); rc=$?   # pipefail: the reader's exit code
  case $rc in
    0) n=${out%% *}; dove=${out#* }
       [ "$dove" = radice ] && RADF[$n]+="$f"$'\n'
       ALLF[$n]+="$f"$'\n' ;;
    2) UNCOV+=("$f") ;;
    *) blocca "$(msg gates.modulo_di f="$f" rc="$rc" err="$(reader_err)")" ;;
  esac
done
righe() { printf '%s' "${1:-}" | grep -v '^$'; }

# --- the gates of the level and their commands ---
gl=$(maat_gate_richiesti "$level" ${FILES[@]+"${FILES[@]}"} 2>"$TMPD/err" | tr -d '\r') || blocca "gate-richiesti: $(reader_err)"
WROOT=$(wslp "$ROOT")
base=""; [ -f "$run_dir/base.txt" ] && base=$(tr -d '\r\n ' < "$run_dir/base.txt")
radice_di() { if [ "${M_AMB[$1]}" = wsl ]; then printf '%s' "$WROOT"; else printf '%s' "$ROOT"; fi; }
maat_di() { if [ "${M_AMB[$1]}" = wsl ]; then wslp "$HROOT"; else printf '%s' "$HROOT"; fi; }
# {maat} ends up in a bash command line: Git Bash must not rewrite MAAT_ROOT (/mnt/c/… -> C:/Program Files/Git/mnt/c/…)
NOCONV="MAAT_ROOT${MSYS2_ENV_CONV_EXCL:+;$MSYS2_ENV_CONV_EXCL}"
dir_of() { if [ "$2" = . ]; then radice_di "$1"; else printf '%s/%s' "$(radice_di "$1")" "$2"; fi; }   # <module> <rel>

# {python} of wsl modules, looked up INSIDE WSL (see the header). From a real case: the derived Windows venv
# (other FastAPI versions) answered differently from production and a test had passed green.
declare -A PYW PYWMISS
PYW_ASSENTE=/python-wsl-assente   # placeholder: a command that contains it is BLOCKED, never run
if [ -z "${FIC_GATES_VENV_PY:-}" ]; then
  for m in ${MODS[@]+"${MODS[@]}"}; do
    [ "${M_AMB[$m]}" = wsl ] || continue
    FIC_GATES_VENV_PY=$PYW_ASSENTE lettore python "$m" >/dev/null 2>&1 || continue   # the module does not use {python}
    i=${M_IDX[$m]} cand=() wp=() base=${M_RAD[$m]} probe_py=""
    if maat_conf "moduli.$i.python.0" >/dev/null 2>&1; then
      j=0; while c=$(maat_conf "moduli.$i.python.$j" 2>/dev/null); do cand+=("$c"); j=$((j + 1)); done
    elif c=$(maat_conf "moduli.$i.python" 2>/dev/null); then cand=("$c")
    elif c=$(maat_conf piattaforma.python 2>/dev/null); then cand=("$c") base=""
    else cand=(python3) base=""; fi
    for k in "${!cand[@]}"; do
      c=${cand[$k]//\\//}
      case $c in
        */*) case $c in /*) p=$c ;; [A-Za-z]:/*) p=$(wslp "$c") ;; *) p="$WROOT${base:+/$base}/${c#./}" ;; esac
             t="[ -x $(sq "$p") ]" ;;
        *) p=$c t="command -v $(sq "$c") >/dev/null 2>&1" ;;
      esac
      wp[$k]=$p probe_py+="${probe_py:+el}if $t; then echo $k; "
    done
    k=$(in_wsl "${probe_py}fi" 2>/dev/null </dev/null | tr -d '\r' | tail -1)
    if [[ $k =~ ^[0-9]+$ ]] && [ -n "${wp[$k]:-}" ]; then PYW[$m]=${wp[$k]}
    else PYWMISS[$m]="$(msg gates.pyw_missing cands="${wp[*]}")"; fi
  done
fi
con_py() { # <module> <command…>: the command with the module's {python} interpreter (FIC_GATES_VENV_PY)
  local m=$1 vpy=${FIC_GATES_VENV_PY:-} excl=${MSYS2_ENV_CONV_EXCL:-}; shift
  if [ -n "${PYW[$m]:-}" ]; then vpy=${PYW[$m]}; elif [ -n "${PYWMISS[$m]:-}" ]; then vpy=$PYW_ASSENTE; fi
  # a WSL path: Git Bash must not rewrite it for the Windows Python (/mnt/c/… -> C:/Program Files/Git/…)
  [ "${M_AMB[$m]}" = wsl ] && excl="FIC_GATES_VENV_PY${excl:+;$excl}"
  FIC_GATES_VENV_PY=$vpy MSYS2_ENV_CONV_EXCL=$excl "$@"
}
comando() { # <module> <type> [options] -> C_REL (relative directory), C_CMD (command), C_ERR; returns the reader's exit code
  local m=$1 out rc; shift
  out=$(MSYS2_ENV_CONV_EXCL=$NOCONV MAAT_ROOT=$(maat_di "$m") con_py "$m" maat_comando "$m" "$@" 2>"$TMPD/err" | tr -d '\r'); rc=$?
  C_ERR=$(reader_err); C_REL=$(printf '%s\n' "$out" | sed -n 1p); C_CMD=$(printf '%s\n' "$out" | sed -n '2,$p')
  # C_NR: the reason without the «NOT RUN (dichiarato): » prefix of the reader, in both languages (maat-config.py
  # follows MAAT_LINGUA from block D on)
  C_NR=${C_ERR#NOT RUN (dichiarato): }; C_NR=${C_NR#NOT RUN (declared): }
  if [ "$rc" -eq 0 ] && [ -n "${PYWMISS[$m]:-}" ] && printf '%s' "$C_CMD" | grep -qF "$PYW_ASSENTE"; then
    C_ERR=${PYWMISS[$m]}; return 5
  fi
  return "$rc"
}
# Reader exit 3 for an unresolvable {python} («python non trovato», «python not found» in English): an environment
# fault, BLOCKED — never NOT RUN «dichiarato», which is only for what maat.json declares (se_presente missing, no test
# command). maat-config.py writes the text in the language of the messages: both forms are read (1.4.0).
senza_python() { case $C_ERR in *"python non trovato"*|*"python not found"*) return 0 ;; esac; return 1; }
GATES=()
declare -A GMOD GTIPO CMD EXEC GDIR SKIPWHY NRWHY BLKWHY GFILES CTL SALT
while IFS=$'\t' read -r g m tipo; do
  [ -n "$g" ] || continue
  GATES+=("$g"); GMOD[$g]=$m GTIPO[$g]=$tipo
  mapfile -t rf < <(righe "${RADF[$m]:-}")
  mapfile -t af < <(righe "${ALLF[$m]:-}")
  case $tipo in
    test)
      if ! dichiara "$m" comandi.test; then
        NRWHY[$g]="$(msg gates.declared_no_test)"; GFILES[$g]=$(printf '%s\n' ${rf[@]+"${rf[@]}"})
      elif [ ${#rf[@]} -eq 0 ]; then SKIPWHY[$g]="$(msg gates.no_file_under root="${M_RADS[$m]}")"
      else
        a=(); for f in "${rf[@]}"; do a+=(--file "$f"); done
        sel=$(lettore test-di "$m" "${a[@]}" 2>"$TMPD/err" | tr -d '\r') || { BLKWHY[$g]="test-di $m: $(reader_err)"; continue; }
        mapfile -t S < <(righe "$sel")
        if [ ${#S[@]} -eq 0 ]; then SKIPWHY[$g]="$(msg gates.no_test_for files="${rf[*]}")"; continue; fi
        a=(); for t in "${S[@]}"; do a+=(--test "$t"); done
        comando "$m" test "${a[@]}" --report '<report>'; rc=$?
        case $rc in
          0) GDIR[$g]=$(dir_of "$m" "$C_REL"); EXEC[$g]=$C_CMD; CMD[$g]="cd $(sq "${GDIR[$g]}") && $C_CMD"
             if [ "$C_REL" = . ]; then GFILES[$g]=$(printf '%s\n' "${S[@]}"); else GFILES[$g]=$(printf '%s\n' "${S[@]}" | sed "s|^$C_REL/||"); fi ;;
          3) if senza_python; then BLKWHY[$g]="$(msg gates.test_cmd m="$m" err="$C_NR")"
             else NRWHY[$g]="$(msg gates.declared_why why="$C_NR")"; fi ;;
          *) BLKWHY[$g]="$(msg gates.test_unresolved m="$m" rc="$rc" err="$C_ERR")" ;;
        esac
      fi ;;
    controlli)
      GFILES[$g]=$(printf '%s\n' ${rf[@]+"${rf[@]}"})
      if [ ${#rf[@]} -eq 0 ]; then SKIPWHY[$g]="$(msg gates.no_file_under root="${M_RADS[$m]}")"; continue; fi
      a=(); for f in "${rf[@]}"; do a+=(--file "$f"); done
      comando "$m" controlli "${a[@]}"; rc=$?
      SALT[$g]=$(tr -d '\r' < "$TMPD/err" | sed -n 's/^maat-config: \(SALTATA: .*\)/\1/p')
      case $rc in
        0) c="" ; CTL[$g]=""
           while IFS= read -r d && IFS= read -r x; do
             CTL[$g]+="$(dir_of "$m" "$d")"$'\t'"$x"$'\n'
             c="${c:+$c ; }cd $(sq "$(dir_of "$m" "$d")") && $x"
           done <<< "$C_REL"$'\n'"$C_CMD"
           CMD[$g]=$c ;;
        3) NRWHY[$g]="$(msg gates.checks_skipped list="$(printf '%s\n' "${SALT[$g]}" | sed 's/^SALTATA: //' | paste -sd ';' - | sed 's/;/; /g')")" ;;
        2) SKIPWHY[$g]="$(msg gates.checks_none m="$m")" ;;
        *) BLKWHY[$g]="$(msg gates.checks_unresolved m="$m" rc="$rc" err="$C_ERR")" ;;
      esac ;;
    lint|build)
      GFILES[$g]=$(printf '%s\n' ${af[@]+"${af[@]}"})
      if [ ${#af[@]} -eq 0 ]; then SKIPWHY[$g]="$(msg gates.no_file_under root="${M_PACS[$m]}")"; continue; fi
      a=()
      if [ "$tipo" = lint ]; then for f in "${af[@]}"; do a+=(--file "$f"); done; [ -n "$base" ] && a+=(--base "$base"); fi
      comando "$m" "$tipo" ${a[@]+"${a[@]}"}; rc=$?
      case $rc in
        0) GDIR[$g]=$(dir_of "$m" "$C_REL"); EXEC[$g]=$C_CMD; CMD[$g]="cd $(sq "${GDIR[$g]}") && $C_CMD" ;;
        3) if senza_python; then BLKWHY[$g]="$(msg gates.type_cmd tipo="$tipo" m="$m" err="$C_NR")"
           else NRWHY[$g]="$(msg gates.declared_why why="$C_NR")"; fi ;;
        *) BLKWHY[$g]="$(msg gates.type_unresolved tipo="$tipo" m="$m" rc="$rc" err="$C_ERR")" ;;
      esac ;;
  esac
done <<< "$gl"
# Module with `ambiente: wsl` but no WSL (wsl and wsl.exe not in PATH; pk08, D5): its gates to run are BLOCKED with the
# reason, never run — if launched they would give «comando non trovato», i.e. a FAIL for the checks and a BLOCKED without
# reason for a report (the doctor's promise: «i suoi gate saranno BLOCKED»). With FIC_GATES_WSL, that program decides.
if [ -z "${FIC_GATES_WSL:-}" ] && ! command -v wsl >/dev/null 2>&1 && ! command -v wsl.exe >/dev/null 2>&1; then
  for g in ${GATES[@]+"${GATES[@]}"}; do
    [ "${M_AMB[${GMOD[$g]}]}" = wsl ] && { [ -n "${CMD[$g]:-}" ] || [ -n "${BLKWHY[$g]:-}" ]; } &&
      BLKWHY[$g]="$(msg gates.no_wsl m="${GMOD[$g]}")"
  done
fi

# --- key ---
file_sha() { if [ -f "$1" ]; then sha < "$1"; else echo assente; fi; }
# plugin and project roots in the key: <maat> and <repo>, in all forms (the longest first)
NK=$( { for x in "$HROOT" "$(win "$HROOT")" "$(wslp "$HROOT")"; do printf '%s\t%s\t<maat>\n' "${#x}" "$x"; done
        for x in "$ROOT" "$(win "$ROOT")" "$WROOT"; do printf '%s\t%s\t<repo>\n' "${#x}" "$x"; done; } | LC_ALL=C sort -t $'\t' -k1,1nr | awk -F '\t' '!v[$2]++')
normk() { local s=$1 l x t; while IFS=$'\t' read -r l x t; do [ -n "$x" ] && s=${s//"$x"/$t}; done <<< "$NK"; printf '%s' "$s"; }
TREE=$(tree_now)
[ -n "$TREE" ] || blocca "$(msg gates.no_tree)"
wsl_mod=""; for m in ${MODS[@]+"${MODS[@]}"}; do [ "${M_AMB[$m]}" = wsl ] && wsl_mod=1; done
probe=""
if [ -n "$wsl_mod" ]; then
  probe=$(in_wsl 'printf "node=%s\n" "$(node --version 2>&1 | head -1)"; printf "tz_wsl=%s|%s\n" "${TZ-}" "$(date +%Z%z)"' 2>/dev/null | tr -d '\r')
  [ -n "$probe" ] || probe="node=wsl non raggiungibile"
fi
pyl=()
declare -A KWSL   # wsl modules that use {python}: version and command entries of the key in WSL
for m in ${MODS[@]+"${MODS[@]}"}; do
  p=$(con_py "$m" lettore python "$m" 2>/dev/null | tr -d '\r'); rc=$?
  [ $rc -eq 2 ] && continue
  v=assente
  if [ "${M_AMB[$m]}" = wsl ]; then
    KWSL[$m]=1
    if [ $rc -eq 0 ] && [ "$p" != "$PYW_ASSENTE" ]; then
      v=$(in_wsl "$(sq "$p") --version 2>&1 || echo assente" 2>/dev/null </dev/null | tr -d '\r' | tail -1)
    fi
  elif [ $rc -eq 0 ] && { [ -f "$p" ] || command -v "$p" >/dev/null 2>&1; }; then v=$("$p" --version 2>&1 | tr -d '\r'); fi
  pyl+=("$m"$'\t'"$v")
done
comp=$(
  echo "schema=gates-1"
  echo "tree=$TREE"
  echo "livello=$level"
  for g in ${GATES[@]+"${GATES[@]}"}; do
    if [ -n "${BLKWHY[$g]:-}" ]; then echo "cmd.$g=BLOCKED $(normk "${BLKWHY[$g]}")"
    elif [ -n "${NRWHY[$g]:-}" ]; then echo "cmd.$g=NOT RUN $(normk "${NRWHY[$g]}")"
    elif [ -n "${CMD[$g]:-}" ]; then echo "cmd.$g=$(normk "${CMD[$g]}")"
    else echo "cmd.$g=SKIPPED ${SKIPWHY[$g]}"; fi
  done
  [ -n "$probe" ] && echo "$probe"
  for x in ${pyl[@]+"${pyl[@]}"}; do
    if [ ${#pyl[@]} -eq 1 ]; then echo "python=${x#*$'\t'}"; else echo "python.${x%%$'\t'*}=${x#*$'\t'}"; fi
  done
  for m in ${MODS[@]+"${MODS[@]}"}; do
    while IFS=$'\t' read -r et tipo cart val; do
      [ -n "$et" ] || continue
      d=$ROOT; [ "$cart" = . ] || d="$ROOT/$cart"
      wd=$WROOT; [ "$cart" = . ] || wd="$WROOT/$cart"
      case $tipo in
        file) echo "$et=$(file_sha "$d/$val")" ;;
        comando)
          if [ -n "${KWSL[$m]:-}" ]; then   # stdin closed: wsl.exe would consume the lines of this loop
            echo "$et=$(in_wsl "if cd $(sq "$wd") 2>/dev/null; then bash -c $(sq "$val") 2>/dev/null </dev/null; else echo assente; fi" 2>/dev/null </dev/null | tr -d '\r' | paste -sd ' ' -)"
          elif [ -d "$d" ]; then echo "$et=$(cd "$d" && bash -c "$val" 2>/dev/null </dev/null | tr -d '\r' | paste -sd ' ' -)"; else echo "$et=assente"; fi ;;
        *) echo "$et=assente" ;;
      esac
    done < <(if [ -n "${KWSL[$m]:-}" ]; then mr=$(wslp "$HROOT"); else mr=$HROOT; fi
             MSYS2_ENV_CONV_EXCL=$NOCONV MAAT_ROOT=$mr con_py "$m" lettore chiave "$m" 2>/dev/null | tr -d '\r')
  done
  echo "TZ=${TZ-<non impostata>}"
  echo "CI=${CI-<non impostata>}"
)
KEY=$(printf '%s\n' "$comp" | sha)

if [ -n "$verify" ]; then
  if [ "$KEY" = "$(basename "$verify")" ]; then echo FRESH; exit 0; fi
  echo "STALE ($(msg gates.stale key="$KEY"))"; exit 1
fi

EV="$run_dir/evidence/$KEY"
mkdir -p "$EV" || { echo "gates: esito=BLOCKED ($(msg gates.ev_dir ev="$EV")) chiave=$KEY evidence=-"; exit 3; }
printf '%s\n' "$comp" > "$EV/chiave.txt"
printf '%s\n' "$level" ${FILES[@]+"${FILES[@]}"} > "$EV/argomenti.txt"
WEV=$(win "$EV")

# --- execution ---
now_ms() { date +%s%3N; }
esegui() { # <module> <absolute directory> <command>: MAAT_MODULO in the environment, not in the command line
  # stderr merged INSIDE WSL: merged outside, wsl.exe delivers two streams that overwrite each other in the log (a vitest
  # FAIL block lost under the summary => «Tn verde», «N falliti, N-1 blocchi»). From a real case.
  # MAAT_CONFIG (if set) also reaches WSL, translated: test-fast.sh reads the same configuration from it; MAAT_LINGUA
  # (resolved above) too: wsl.exe does not pass the environment, and the messages of test-fast.sh follow it
  if [ "${M_AMB[$1]}" = wsl ]; then in_wsl "{ export MAAT_MODULO=$(sq "$1")${MAAT_CONFIG:+; export MAAT_CONFIG=$(sq "$(wslp "$MAAT_CONFIG")")}; export MAAT_LINGUA=$(sq "$MAAT_LINGUA"); cd $(sq "$2") && $3; } 2>&1"
  else (cd "$2" && MAAT_MODULO=$1 bash -c "$3"); fi
}
run_gate() { # $1 = gate. Reuse on an identical key, otherwise execution and JSON.
  local g=$1 rc=0 r t0 kind why="" m=${GMOD[$1]} cmd="" x rp d c files=()
  if [ -n "$(py stato "$WEV" "$g")" ]; then echo riuso > "$EV/.$g.stato"; return 0; fi
  rm -f "$EV/$g.json" "$EV/$g.log" "$EV/$g.junit.xml" "$EV/.$g.voci"
  echo eseguito > "$EV/.$g.stato"
  mapfile -t files < <(righe "${GFILES[$g]:-}")
  t0=$(now_ms)
  if [ -n "${BLKWHY[$g]:-}" ]; then kind=blocked why=${BLKWHY[$g]}
  elif [ -n "${NRWHY[$g]:-}" ]; then kind=notrun why=${NRWHY[$g]}
  elif [ -z "${CMD[$g]:-}" ]; then kind=skip why=${SKIPWHY[$g]:-}
  elif [ "${GTIPO[$g]}" = controlli ]; then
    kind=controlli cmd=${CMD[$g]}
    : > "$EV/$g.log"
    while IFS=$'\t' read -r d c; do
      [ -n "$c" ] || continue
      printf '== %s\n' "$c" >> "$EV/$g.log"
      esegui "$m" "$d" "$c" >> "$EV/$g.log" 2>&1 </dev/null; r=$?
      printf '== %s\n' "$(msg gates.log_exit rc="$r")" >> "$EV/$g.log"
      if [ $r -eq 0 ]; then printf 'PASS\t%s\t%s\n' "$r" "$c"; else printf 'FAIL\t%s\t%s\n' "$r" "$c"; rc=1; fi >> "$EV/.$g.voci"
    done <<< "${CTL[$g]}"
    while IFS= read -r x; do [ -n "$x" ] && printf 'SALTATA\t\t%s\n' "${x#SALTATA: }" >> "$EV/.$g.voci"; done <<< "${SALT[$g]:-}"
  else
    case ${GTIPO[$g]} in test) kind=${M_REP[$m]} ;; *) kind=${GTIPO[$g]} ;; esac
    cmd=${CMD[$g]}
    if [ "${M_AMB[$m]}" = wsl ]; then rp=$(wslp "$EV/$g.junit.xml"); else rp=$(win "$EV/$g.junit.xml"); fi
    x=${EXEC[$g]//"'<report>'"/$(sq "$rp")}
    esegui "$m" "${GDIR[$g]}" "$x" > "$EV/$g.log" 2>&1; rc=$?
  fi
  py scrivi "$WEV" "$g" "$kind" "$cmd" "$rc" "$(( $(now_ms) - t0 ))" "$why" "$KEY" ${files[@]+"${files[@]}"} >/dev/null
  rm -f "$EV/.$g.voci"
}
NAT=() WL=()
for g in ${GATES[@]+"${GATES[@]}"}; do if [ "${M_AMB[${GMOD[$g]}]}" = wsl ]; then WL+=("$g"); else NAT+=("$g"); fi; done
( for g in ${NAT[@]+"${NAT[@]}"}; do run_gate "$g"; done ) & natpid=$!
for g in ${WL[@]+"${WL[@]}"}; do run_gate "$g"; done
wait $natpid

# The tree changed while the gates were running: what was executed is evidence of no tree.
after=$(tree_now)
if [ "$after" != "$TREE" ]; then
  for g in ${GATES[@]+"${GATES[@]}"}; do
    [ "$(cat "$EV/.$g.stato" 2>/dev/null)" = eseguito ] &&
      py invalida "$WEV" "$g" "$(msg gates.tree_changed tree="$TREE" after="${after:-$(msg gates.not_computable)}")" >/dev/null
  done
fi
for g in ${GATES[@]+"${GATES[@]}"}; do py riga "$WEV" "$g" "$(cat "$EV/.$g.stato" 2>/dev/null)"; rm -f "$EV/.$g.stato"; done
[ ${#UNCOV[@]} -eq 0 ] || echo "$(msg gates.uncovered files="${UNCOV[*]}")"
tot=$(py totale "$WEV" ${GATES[@]+"${GATES[@]}"})
echo "gates: esito=$tot chiave=$KEY evidence=$WEV"
case ${tot%% *} in PASS|SKIPPED) exit 0 ;; FAIL) exit 1 ;; *) exit 3 ;; esac

#__PYTHON__
import datetime
import importlib.util
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

_s = importlib.util.spec_from_file_location("maat_msg", os.environ["MAAT_MSG_PY"])
_m = importlib.util.module_from_spec(_s)
_s.loader.exec_module(_m)
T = _m.T   # the message catalog (1.4.0), next to gates.sh

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
RIUSABILI = ("PASS", "FAIL", "SKIPPED", "NOT RUN")


def read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return ANSI.sub("", f.read())
    except OSError:
        return None


def load(ev, g):
    try:
        with open(os.path.join(ev, g + ".json"), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save(ev, g, d):
    tmp = os.path.join(ev, g + ".json.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.replace(tmp, os.path.join(ev, g + ".json"))


def junit(p):
    """(tests, failures, errors, skipped) of a JUnit report, None if missing or unreadable."""
    try:
        root = ET.parse(p).getroot()
    except (OSError, ET.ParseError):
        return None
    suites = [root] if root.tag == "testsuite" else root.findall("testsuite")
    if not suites:
        return None
    tot = [0, 0, 0, 0]
    for s in suites:
        for i, k in enumerate(("tests", "failures", "errors", "skipped")):
            try:
                tot[i] += int(s.get(k, "0"))
            except ValueError:
                return None
    return tuple(tot)


def wrapper_line(text):
    """Last 'vitest-fast: esito=…' line of the wrapper (test-fast.sh): (outcome, line) or (None, None)."""
    for ln in reversed(text.splitlines()):
        m = re.search(r"vitest-fast: esito=(\w+)", ln)
        if m:
            return m.group(1), ln.strip()
    return None, None


def judge(ev, g, kind, rc):
    """(outcome, report, summary, reason) from the FORMAT (kind: junit | vitest | nessuno | lint | build | controlli),
    never from the gate name. Never PASS without a report."""
    if kind == "junit":
        rep = g + ".junit.xml"
        j = junit(os.path.join(ev, rep))
        if j is None:
            return "BLOCKED", None, "", T("gates.no_junit", rc=rc, g=g)
        n, fl, er, sk = j
        riep = T("gates.junit_summary", n=n, fl=fl, er=er, sk=sk)
        if rc == 0 and fl + er == 0 and n > 0:
            return "PASS", rep, riep, ""
        if rc == 1 and fl + er > 0:
            return "FAIL", rep, riep, ""
        return "BLOCKED", rep, riep, T("gates.junit_incoherent", rc=rc)
    rep = g + ".log"
    text = read(os.path.join(ev, rep))
    if not text or not text.strip():
        return "BLOCKED", None, "", T("gates.no_output", rc=rc)
    if kind == "controlli":
        voci = leggi_voci(ev, g)
        ese = [v for v in voci if v["esito"] != "SALTATA"]
        ko = [v for v in ese if v["esito"] == "FAIL"]
        riep = T("gates.checks_summary", n=len(ese), ko=len(ko), sk=len(voci) - len(ese))
        if rc == 0 and ese and not ko:
            return "PASS", rep, riep, ""
        if ko:
            return "FAIL", rep, riep, ""
        return "BLOCKED", rep, riep, T("gates.checks_incoherent", rc=rc)
    if kind in ("build", "nessuno"):
        last = text.strip().splitlines()[-1].strip()
        if rc == 0:
            return "PASS", rep, last, ""
        if rc in (126, 127, 255) or rc < 0:
            return "BLOCKED", rep, last, T("gates.not_runnable", rc=rc)
        return "FAIL", rep, last, ""
    esito, line = wrapper_line(text)
    if esito is None:
        return "BLOCKED", rep, "", T("gates.no_wrapper_line", rc=rc)
    if kind == "vitest":
        summ = [l.strip() for l in text.splitlines() if re.match(r"\s*Tests\s+\d", l)]
        riep = summ[-1] if summ else line
        if rc == 0 and esito == "PASS":
            if not summ or "passed" not in summ[-1]:
                return "BLOCKED", rep, line, T("gates.no_vitest_summary")
            return "PASS", rep, riep, ""
        if rc == 1 and esito == "FAIL":
            return "FAIL", rep, riep, ""
        return "BLOCKED", rep, riep, line
    # lint
    if rc == 0 and esito == "PASS":
        return "PASS", rep, line, ""
    if rc == 0 and esito == "SKIPPED":
        return "SKIPPED", rep, line, line
    if rc == 1 and esito == "FAIL":
        return "FAIL", rep, line, ""
    return "BLOCKED", rep, line, line


def leggi_voci(ev, g):
    """The entries of the checks written by gates.sh (.<gate>.voci): outcome<TAB>exit<TAB>command or reason."""
    out = []
    t = read(os.path.join(ev, "." + g + ".voci")) or ""
    for ln in t.splitlines():
        p = ln.split("\t", 2)
        if len(p) < 3:
            continue
        if p[0] == "SALTATA":
            c, _sep, mot = p[2].partition(" — ")
            out.append({"comando": c, "esito": "SALTATA", "exit": None, "motivo": mot})
        else:
            out.append({"comando": p[2], "esito": p[0], "exit": int(p[1]) if p[1].lstrip("-").isdigit() else None,
                        "motivo": ""})
    return out


def cmd_scrivi(ev, g, kind, cmd, rc, dur, why, key, *files):
    rc = int(rc)
    voci = leggi_voci(ev, g)
    if kind == "skip":
        esito, rep, riep, mot, cmd, rc = "SKIPPED", None, "", why, None, None
    elif kind == "notrun":
        esito, rep, riep, mot, cmd, rc = "NOT RUN", None, "", why, None, None
    elif kind == "blocked":
        esito, rep, riep, mot, rc = "BLOCKED", None, "", why, None
    else:
        esito, rep, riep, mot = judge(ev, g, kind, rc)
    d = {"gate": g, "esito": esito, "comando": cmd or None, "exit": rc,
         "durata_s": round(int(dur) / 1000.0, 1), "report": rep, "riepilogo": riep,
         "motivo": mot, "file": list(files), "chiave": key,
         "eseguito_il": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    if voci:
        d["voci"] = voci
    save(ev, g, d)
    print(esito)


def cmd_stato(ev, g):
    """Prints the outcome if the gate can be reused (PASS/FAIL/SKIPPED/NOT RUN, report present), nothing otherwise."""
    d = load(ev, g)
    if not d or d.get("esito") not in RIUSABILI:
        return
    rep = d.get("report")
    if rep and not os.path.isfile(os.path.join(ev, rep)):
        return
    if d["esito"] in ("PASS", "FAIL") and not rep:
        return
    print(d["esito"])


def cmd_invalida(ev, g, why):
    d = load(ev, g)
    if d:
        d["esito"], d["motivo"] = "BLOCKED", why
        save(ev, g, d)


def cmd_riga(ev, g, stato):
    d = load(ev, g) or {"esito": "BLOCKED", "motivo": T("gates.ev_not_written")}
    detail = d.get("riepilogo") if d.get("esito") in ("PASS", "FAIL") else d.get("motivo")
    print(f"{g}: {d['esito']} ({stato or 'eseguito'}) — {detail or ''}".rstrip(" —"))


def cmd_totale(ev, *gates):
    es = [(g, (load(ev, g) or {}).get("esito", "BLOCKED")) for g in gates]
    nr = [g for g, e in es if e == "NOT RUN"]
    tutti = [e for _g, e in es]
    if "FAIL" in tutti:
        tot = "FAIL"
    elif any(e not in ("PASS", "SKIPPED", "NOT RUN") for e in tutti):
        tot = "BLOCKED"
    elif all(e in ("SKIPPED", "NOT RUN") for e in tutti):
        tot = "SKIPPED"
    else:
        tot = "PASS"
    print(tot + (" (%s)" % T("gates.nr_declared", gates=" ".join(nr)) if nr else ""))


sys.stdout.reconfigure(encoding="utf-8")
{"scrivi": cmd_scrivi, "stato": cmd_stato, "invalida": cmd_invalida, "riga": cmd_riga,
 "totale": cmd_totale}[sys.argv[1]](*sys.argv[2:])
