#!/usr/bin/env bash
# attese.sh — the expected outputs of the public corpus (Maat 1.6.0): the proof of the decider, in place of the
# equivalence certificate of 1.5.x. A tool of the repo, not of the plugin.
#   bash tools/esempi-equiv/attese.sh [--corpus <folder>] [--repo <mini-repo>]… [--solo next|valida] [--lingua it|en]
#                                     [--attese <folder>] [--esiti <folder>]
#        compare: the outputs of the plugin under test on the corpus against tools/esempi-equiv/attese/
#   bash tools/esempi-equiv/attese.sh --scrivi --motivo "<text>"
#        rewrite the expected outputs (and one line more in attese/STORIA)
#   bash tools/esempi-equiv/attese.sh --validatori      the validators available (exit 1 if one is SALTATO and
#                                                       MAAT_ATTESE_RICHIESTE=1)
#   bash tools/esempi-equiv/attese.sh --storia [<base>] attese/ changed since <base> → a new line in attese/STORIA
#   bash tools/esempi-equiv/attese.sh --forme <folder>  the forms of a root that the normalization replaces
#
# WHAT IS RECORDED (tools/esempi-equiv/attese/, LF, blocks in the order of casi.tsv):
#   next-<l>.txt                for every spec of casi.tsv, in language <l> (it, en): «== <mini-repo>/<spec>», the stdout
#                               of `cycle-state.sh <spec>` (CR removed), «== exit <n>»;
#   valida-<v>-<l>.txt          for every jsonl of casi.tsv, with validator <v> (minimo, jsonschema) and language <l>:
#                               «== <mini-repo>/<jsonl>», «-- stdout», its lines, «-- stderr», its lines, «-- exit <n> ·
#                               result.json <sha256 without CR | nessuno>» of `driver.py valida <jsonl> <schema>
#                               <phase> <result.json>` (phase = _phase_of of driver.py on the label of the jsonl; the
#                               result.json written in <mini-repo>/.claude/attese-out/, removed afterwards);
#   STORIA                      one line per --scrivi: «<UTC> · base <commit> · plugin <which> · motori <next>/<valida>
#                               · corpus <fingerprint 12> · motivo: <text> · file: <files changed | nessuno>».
#   A line that ends without a newline gets «== (nessun a capo finale)» after it. cwd: a folder outside the mini-repos;
#   MAAT_ROOT = the plugin under test; FIC_REPO, FIC_DRIVER_ROOT, FIC_DRIVER_PY, FIC_CYCLE_STATE, FIC_RUN_PHASE unset.
#   FIC_DRIVER passes through (with the plugin of v1.5.1, FIC_DRIVER=0 = its bash table: the anchor of `next`).
# NORMALIZATIONS — THE CLOSED LIST (D2 of the plan; the same in docs/TESTING-harness.md, «The expected outputs»):
#   <REPO>              the root of the mini-repo of the block, in every form: as given, `pwd -P` (a link: on macOS
#                       /var → /private/var), and where cygpath exists (Windows) `cygpath -m` (C:/…) and
#                       `cygpath -u` of that (/c/… or, under the Temp of Git Bash, /tmp/…) of both;
#   <MAAT>              the root of the plugin under test, in the same forms;
#   <impronta-attuale>  the current harness fingerprint of the plugin under test on that mini-repo in that language
#                       (`run-phase.sh --harness-fp`), 64 digits and its first 12.
#   Paths at the boundary of a path, fingerprints at the boundary of hex digits, the longest form first, forms of
#   equal length all kept, one pass (tools/esempi-equiv/attese.py). RULE: a new normalization enters only written in
#   this list (and in TESTING), with a counterproof in tools/esempi-equiv.test.sh (h): a real difference in the same
#   line (one character of the reason changed) stays red.
# THE PLUGIN UNDER TEST: MAAT_ATTESE_PLUGIN, a plugin folder (with .claude-plugin/plugin.json, or a repo root with
#   plugins/maat/) or a git ref of this repository (git archive); default: plugins/maat of this repo. The corpus is
#   always built with the plugin of the repo (tools/esempi-equiv/costruisci.sh: the placeholders do not depend on the
#   engine), or taken from --corpus (a folder built by costruisci.sh: the sources of the models are checked).
# MAAT_ATTESE_VALIDA=run-phase: `valida` through `run-phase.sh --valida` of the plugin under test (its internal
#   validator, VALIDA_PY: the anchor of `valida` with v1.5.1); a plugin without --valida → exit 2. Default: driver.py.
# THE VALIDATORS: «minimo» = MAAT_PY_MINIMO, or the interpreter of python.sh when it does not import jsonschema;
#   «jsonschema» = MAAT_PY_JSONSCHEMA, or ~/maat-venv/bin/python, or the interpreter of python.sh when it imports it.
#   A missing one: «SALTATO: <v>», its two files not compared; with MAAT_ATTESE_RICHIESTE=1 (the CI) that is red
#   (exit 1). `next` runs with the minimal interpreter (or the other one when it is missing).
# --scrivi refuses (exit 2): without --motivo (one line, no TAB), with --corpus/--repo/--solo/--lingua/--attese,
#   without one of the two validators, with a jsonschema of a version other than the one in .github/workflows/ci.yml.
# --storia: <base> default = `git merge-base HEAD origin/main` (HEAD~1 when that is HEAD itself, as on main); the
#   files of attese/ changed since <base> (committed, in the working tree, or new) other than STORIA → STORIA must keep
#   its text at <base> as it is and add at least one line (not a comment). Exit 0 · 1 red · 2 git cannot say.
# Exit (compare and --scrivi): 0 equal (or written) · 1 a difference, or a validator SALTATO with
#   MAAT_ATTESE_RICHIESTE=1 · 2 usage or environment. Never in parallel with a suite of the plugin (constraint 4).
set -uo pipefail
export LC_ALL=C PYTHONDONTWRITEBYTECODE=1
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
ATTESE_REPO=$HERE/attese
REL=tools/esempi-equiv/attese
CASI=$HERE/casi.tsv
APY=$HERE/attese.py
FILE_NEXT="next-it.txt next-en.txt"
FILE_VALIDA="valida-minimo-it.txt valida-minimo-en.txt valida-jsonschema-it.txt valida-jsonschema-en.txt"

usage() {
  echo "usage: bash tools/esempi-equiv/attese.sh [--corpus <folder>] [--repo <mini-repo>]… [--solo next|valida] [--lingua it|en] [--attese <folder>] [--esiti <folder>]
       bash tools/esempi-equiv/attese.sh --scrivi --motivo \"<text>\" | --validatori | --storia [<base>] | --forme <folder>" >&2
  exit 2
}
die() { echo "attese.sh: $1" >&2; exit "${2:-2}"; }
nat() { cygpath -m "$1" 2>/dev/null || printf '%s\n' "$1"; }   # a path for the native Python (Windows)

MODO=confronta MOTIVO= MOTIVO_DATO=0 CORPUS= SOLO= LINGUE="it en" ATT=$ATTESE_REPO ESITI= BASE= FORME_DI=
REPOS=() parziale=0
while [ $# -gt 0 ]; do
  case $1 in
    --scrivi) MODO=scrivi; shift ;;
    --motivo) [ $# -ge 2 ] || usage; MOTIVO=$2; MOTIVO_DATO=1; shift 2 ;;
    --corpus) [ $# -ge 2 ] || usage; CORPUS=$2; shift 2 ;;
    --repo) [ $# -ge 2 ] || usage; REPOS+=("$2"); parziale=1; shift 2 ;;
    --solo) [ $# -ge 2 ] || usage; SOLO=$2; parziale=1; shift 2
      case $SOLO in next|valida) ;; *) usage ;; esac ;;
    --lingua) [ $# -ge 2 ] || usage; LINGUE=$2; parziale=1; shift 2
      case $LINGUE in it|en) ;; *) usage ;; esac ;;
    --attese) [ $# -ge 2 ] || usage; ATT=$(cd "$2" 2>/dev/null && pwd) || die "--attese: $2 is not a folder"; shift 2 ;;
    --esiti) [ $# -ge 2 ] || usage; ESITI=$2; shift 2 ;;
    --validatori) MODO=validatori; shift ;;
    --storia) MODO=storia; shift; if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then BASE=$1; shift; fi ;;
    --forme) [ $# -ge 2 ] || usage; MODO=forme; FORME_DI=$2; shift 2 ;;
    *) usage ;;
  esac
done

# --- the forms of a root (the closed list above: as given, pwd -P, cygpath -m and -u of both) ---
forme() {
  local r=$1 p x m
  {
    printf '%s\n' "$r"
    p=$(cd "$r" 2>/dev/null && pwd -P) && printf '%s\n' "$p"
    if command -v cygpath >/dev/null 2>&1; then
      for x in "$r" "${p:-}"; do
        [ -n "$x" ] || continue
        m=$(cygpath -m "$x" 2>/dev/null) || continue
        printf '%s\n%s\n' "$m" "$(cygpath -u "$m" 2>/dev/null)"
      done
    fi
  } | tr -d '\r' | awk 'length($0) && !seen[$0]++'
}
if [ $MODO = forme ]; then
  [ -d "$FORME_DI" ] || die "--forme: $FORME_DI is not a folder"
  forme "$FORME_DI"; exit 0
fi

# --- --storia: the files of attese/ changed since the base need a new line in STORIA ---
if [ $MODO = storia ]; then
  git -C "$ROOT" rev-parse -q --verify 'HEAD^{commit}' >/dev/null 2>&1 || die "--storia: git cannot read $ROOT"
  if [ -z "$BASE" ]; then
    BASE=$(git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null) || die "--storia: no merge-base with origin/main (git fetch origin main)"
    [ "$BASE" = "$(git -C "$ROOT" rev-parse HEAD)" ] && { BASE=$(git -C "$ROOT" rev-parse -q --verify 'HEAD~1^{commit}') || die "--storia: HEAD has no parent"; }
  fi
  git -C "$ROOT" rev-parse -q --verify "$BASE^{commit}" >/dev/null 2>&1 || die "--storia: $BASE is not a commit"
  b12=$(git -C "$ROOT" rev-parse --short=12 "$BASE")
  cambiati=$( { git -C "$ROOT" diff --name-only "$BASE" -- "$REL"; git -C "$ROOT" ls-files --others --exclude-standard -- "$REL"; } |
    grep -vx "$REL/STORIA" | LC_ALL=C sort -u)
  if [ -z "$cambiati" ]; then echo "attese: STORIA non richiesta (nessun file di attese/ cambiato da $b12)"; exit 0; fi
  S=$(mktemp -d) || die "mktemp"
  trap 'rm -rf "$S"' EXIT
  git -C "$ROOT" show "$BASE:$REL/STORIA" > "$S/prima" 2>/dev/null || : > "$S/prima"
  tr -d '\r' < "$S/prima" > "$S/p"; tr -d '\r' < "$ROOT/$REL/STORIA" > "$S/d" 2>/dev/null || : > "$S/d"
  np=$(grep -cv '^\(#\|[[:space:]]*$\)' "$S/p"); nd=$(grep -cv '^\(#\|[[:space:]]*$\)' "$S/d")
  if cmp -s -n "$(wc -c < "$S/p")" "$S/p" "$S/d" && [ "$nd" -gt "$np" ]; then
    echo "attese: STORIA ok ($((nd - np)) righe nuove da $b12 per: $(printf '%s ' $cambiati))"; exit 0
  fi
  echo "attese: ROSSO — file di attese/ cambiati da $b12 senza una riga nuova in fondo a attese/STORIA: $(printf '%s ' $cambiati)"
  echo "    (un cambio voluto: bash tools/esempi-equiv/attese.sh --scrivi --motivo \"<perche'>\"; STORIA si allunga, non si riscrive)"
  exit 1
fi

# --- the Python of the repo (attese.py, _phase_of) and the validators ---
FIC_PY=""; . "$ROOT/plugins/maat/scripts/python.sh" >/dev/null 2>&1
[ -n "$FIC_PY" ] || die "no Python (python.sh)"
PY0=$FIC_PY
validatore() { "$1" -c "import jsonschema" >/dev/null 2>&1 && echo jsonschema || echo minimo; }
JV=$(tr -d '\r' < "$ROOT/.github/workflows/ci.yml" 2>/dev/null | grep -o 'jsonschema==[0-9][0-9.]*' | head -1); JV=${JV#jsonschema==}
VENV_CMD="python3 -m venv ~/maat-venv && ~/maat-venv/bin/pip install jsonschema==${JV:-<version of ci.yml>}"
PY_MIN=${MAAT_PY_MINIMO:-} PY_JS=${MAAT_PY_JSONSCHEMA:-} SALTATI=""
if [ -n "$PY_MIN" ] && [ "$(validatore "$PY_MIN")" != minimo ]; then die "MAAT_PY_MINIMO=$PY_MIN imports jsonschema"; fi
[ -n "$PY_JS" ] || { [ -x "$HOME/maat-venv/bin/python" ] && PY_JS=$HOME/maat-venv/bin/python; }
if [ "$(validatore "$PY0")" = minimo ]; then [ -n "$PY_MIN" ] || PY_MIN=$PY0; elif [ -z "$PY_JS" ]; then PY_JS=$PY0; fi
if [ -n "$PY_JS" ] && [ "$(validatore "$PY_JS")" != jsonschema ]; then
  echo "attese: $PY_JS non importa jsonschema: validatore jsonschema saltato" >&2; PY_JS=""
fi
[ -n "$PY_MIN" ] || { echo "SALTATO: minimo ($PY0 importa jsonschema; MAAT_PY_MINIMO: un interprete senza)"; SALTATI+=" minimo"; }
[ -n "$PY_JS" ] || { echo "SALTATO: jsonschema (niente MAAT_PY_JSONSCHEMA ne' ~/maat-venv: $VENV_CMD)"; SALTATI+=" jsonschema"; }
JSV=""
[ -z "$PY_JS" ] || JSV=$("$PY_JS" -c 'import importlib.metadata as m; print(m.version("jsonschema"))' 2>/dev/null | tr -d '\r')
richiesti_ko() { [ "${MAAT_ATTESE_RICHIESTE:-0}" = 1 ] && [ -n "$SALTATI" ]; }
if [ $MODO = validatori ]; then
  [ -z "$PY_MIN" ] || echo "validatore minimo: $PY_MIN"
  [ -z "$PY_JS" ] || echo "validatore jsonschema: $PY_JS (jsonschema ${JSV:-?}, la CI fissa ${JV:-?})"
  if richiesti_ko; then echo "attese: ROSSO — MAAT_ATTESE_RICHIESTE=1 e validatore SALTATO:$SALTATI"; exit 1; fi
  exit 0
fi
[ -n "$PY_MIN$PY_JS" ] || die "no validator available"
PYN=${PY_MIN:-$PY_JS}   # the interpreter of next (it does not use jsonschema)

if [ $MODO = scrivi ]; then
  [ $MOTIVO_DATO = 1 ] && [ -n "$MOTIVO" ] || die "--scrivi without --motivo \"<text>\""
  case $MOTIVO in *$'\n'*|*$'\t'*) die "--motivo: one line, no TAB" ;; esac
  [ $parziale = 0 ] && [ -z "$CORPUS" ] && [ "$ATT" = "$ATTESE_REPO" ] || die "--scrivi: the whole corpus, built here (no --corpus, --repo, --solo, --lingua, --attese)"
  [ -n "$PY_MIN" ] || die "--scrivi: validator minimo missing (MAAT_PY_MINIMO: an interpreter without jsonschema, e.g. python3 -m venv ~/maat-venv-minimo)"
  [ -n "$PY_JS" ] || die "--scrivi: validator jsonschema missing: $VENV_CMD (or MAAT_PY_JSONSCHEMA)"
  [ -n "$JV" ] || die "--scrivi: no jsonschema==<version> in .github/workflows/ci.yml"
  [ "$JSV" = "$JV" ] || die "--scrivi: jsonschema $JSV in $PY_JS, the CI fixes $JV: $VENV_CMD"
elif [ -n "$JSV" ] && [ -n "$JV" ] && [ "$JSV" != "$JV" ]; then
  echo "attese: AVVISO — jsonschema $JSV in $PY_JS, la CI fissa $JV: le uscite di valida-jsonschema possono differire"
fi

T=$(mktemp -d) || die "mktemp"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/cwd" "$T/out"
t0=$(date +%s)

# --- the plugin under test ---
SRC=${MAAT_ATTESE_PLUGIN:-$ROOT/plugins/maat}
if [ -d "$SRC" ]; then
  [ -f "$SRC/.claude-plugin/plugin.json" ] || { [ -f "$SRC/plugins/maat/.claude-plugin/plugin.json" ] && SRC=$SRC/plugins/maat; }
  [ -f "$SRC/.claude-plugin/plugin.json" ] || die "MAAT_ATTESE_PLUGIN: $SRC has no .claude-plugin/plugin.json (nor plugins/maat/)"
  PLUGIN=$(cd "$SRC" && pwd)
  if [ "$PLUGIN" = "$(cd "$ROOT/plugins/maat" && pwd)" ]; then QUALE="repo"; else QUALE="cartella $(basename "$(dirname "$PLUGIN")")/$(basename "$PLUGIN")"; fi
else
  sha=$(git -C "$ROOT" rev-parse -q --verify "$SRC^{commit}" 2>/dev/null) || die "MAAT_ATTESE_PLUGIN: $SRC is neither a plugin folder nor a git ref"
  mkdir -p "$T/ref" && git -C "$ROOT" -c core.autocrlf=false archive "$SRC" plugins/maat | tar -x -C "$T/ref" || die "git archive $SRC"
  PLUGIN=$T/ref/plugins/maat
  [ -f "$PLUGIN/.claude-plugin/plugin.json" ] || die "$SRC: no plugins/maat/.claude-plugin/plugin.json"
  QUALE="ref $SRC (${sha:0:12})"
fi
VER=$(tr -d '\r' < "$PLUGIN/.claude-plugin/plugin.json" | sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' | head -1)
QUALE="$QUALE, versione ${VER:-?}"
VALIDA=${MAAT_ATTESE_VALIDA:-driver}
case $VALIDA in
  driver) ;;
  run-phase) grep -q '"--valida"' "$PLUGIN/scripts/run-phase.sh" || die "MAAT_ATTESE_VALIDA=run-phase: run-phase.sh of the plugin under test has no --valida (gone in 1.6.0)" ;;
  *) die "MAAT_ATTESE_VALIDA: driver or run-phase" ;;
esac
MOTORI="next ${FIC_DRIVER:+FIC_DRIVER=$FIC_DRIVER}"; [ -n "${FIC_DRIVER:-}" ] || MOTORI="next predefinito"; MOTORI+=" · valida $VALIDA"
echo "attese: plugin $QUALE · $MOTORI"

# --- the corpus ---
casi() { tr -d '\r' < "$CASI" | grep -v '^#' | grep .; }
mapfile -t TUTTI < <(casi | cut -f2 | awk '!s[$0]++')
if [ ${#REPOS[@]} -eq 0 ]; then REPOS=("${TUTTI[@]}"); fi
for m in "${REPOS[@]}"; do printf '%s\n' "${TUTTI[@]}" | grep -qxF -- "$m" || die "--repo: $m is not a mini-repo of casi.tsv"; done
sorgente() { # $1 mini-repo → the sources of its models, as costruisci.sh writes them
  (cd "$HERE/$1" && find modelli stati -type f | LC_ALL=C sort | while IFS= read -r f; do
     printf '%s %s/%s\n' "$(tr -d '\r' < "$f" | sha256sum | cut -c1-64)" "$1" "$f"; done)
}
if [ -n "$CORPUS" ]; then
  CORPUS=$(cd "$CORPUS" 2>/dev/null && pwd) || die "--corpus: $CORPUS is not a folder"
  for m in "${REPOS[@]}"; do
    [ -f "$CORPUS/$m/.claude/esempi-equiv.sorgente" ] || die "--corpus: $CORPUS/$m is not a mini-repo built by costruisci.sh"
    cmp -s <(tr -d '\r' < "$CORPUS/$m/.claude/esempi-equiv.sorgente") <(sorgente "$m") ||
      die "--corpus: $CORPUS/$m was built from other models (rebuild it with tools/esempi-equiv/costruisci.sh)"
  done
  TGT=(); for m in "${REPOS[@]}"; do TGT+=("$(nat "$CORPUS/$m/.claude/.ai-workflow")"); done
  IMP=$("$PY0" "$(nat "$ROOT/plugins/maat/scripts/driver.py")" impronta "${TGT[@]}" 2>/dev/null | tr -d '\r')
else
  CORPUS=$T/corpus
  bash "$HERE/costruisci.sh" "$CORPUS" "${REPOS[@]}" > "$T/costruisci.out" 2>&1 || { tail -20 "$T/costruisci.out" >&2; die "the build of the corpus failed" 1; }
  IMP=$(sed -n 's/^impronta //p' "$T/costruisci.out" | tr -d '\r')
fi
echo "attese: corpus ${#REPOS[@]} mini-repo · impronta ${IMP:0:12} · $(( $(date +%s) - t0 ))s"

# --- the environment of the plugin under test ---
unset FIC_REPO FIC_DRIVER_ROOT FIC_DRIVER_PY FIC_DRIVER_CERT FIC_CYCLE_STATE FIC_RUN_PHASE MAAT_MSG_PY FIC_PY FIC_PY_VER
export MAAT_ROOT=$PLUGIN
SCHEMA=$PLUGIN/schemas/phase-result.schema.json
forme_file() { # $1 mini-repo, $2 language → $T/forme-<m>-<l>
  local m=$1 l=$2 f=$T/forme-$1-$2 cur x
  : > "$f"
  while IFS= read -r x; do printf 'path\t<REPO>\t%s\n' "$x"; done < <(forme "$CORPUS/$m") >> "$f"
  while IFS= read -r x; do printf 'path\t<MAAT>\t%s\n' "$x"; done < <(forme "$PLUGIN") >> "$f"
  cur=$(cd "$T/cwd" && MAAT_LINGUA=$l FIC_PYTHON=$PYN bash "$PLUGIN/scripts/run-phase.sh" --harness-fp "$CORPUS/$m" 2>/dev/null | tr -d '\r' |
    sed -n 's/^impronta=\([0-9a-f]\{64\}\)$/\1/p')
  [ -z "$cur" ] || printf 'hex\t<impronta-attuale>\t%s\nhex\t<impronta-attuale>\t%s\n' "$cur" "${cur:0:12}" >> "$f"
}
corpo() { # $1 file: its text without CR, a marker line when it does not end with a newline
  tr -d '\r' < "$1"
  [ -s "$1" ] && [ -n "$(tail -c1 "$1" | tr -d '\n\r')" ] && printf '\n== (nessun a capo finale)\n'
  return 0
}
normalizza() { "$PY0" "$(nat "$APY")" normalizza "$(nat "$1")"; }

# the phases of the jsonl: _phase_of of the driver of the repo, on their labels
casi | awk -F'\t' '$1 == "jsonl" { print $2 "\t" $3 }' > "$T/jsonl"
sed -E 's|^.*/log/([0-9]+-[^/]*)\.jsonl$|\1|' "$T/jsonl" |
  "$PY0" -B -c 'import sys; sys.path.insert(0, sys.argv[1]); from driver import _phase_of; [print(_phase_of(l.strip())) for l in sys.stdin]' \
  "$(nat "$ROOT/plugins/maat/scripts")" | tr -d '\r' > "$T/fasi"
[ "$(wc -l < "$T/fasi")" = "$(wc -l < "$T/jsonl")" ] || die "_phase_of of driver.py failed"
paste "$T/jsonl" "$T/fasi" > "$T/jsonl-fasi"

FILES=()
for l in $LINGUE; do
  [ "$SOLO" = valida ] || FILES+=("next-$l.txt")
  if [ "$SOLO" != next ]; then
    [ -z "$PY_MIN" ] || FILES+=("valida-minimo-$l.txt")
    [ -z "$PY_JS" ] || FILES+=("valida-jsonschema-$l.txt")
  fi
done
for f in "${FILES[@]}"; do : > "$T/out/$f"; done
for m in "${REPOS[@]}"; do
  for l in $LINGUE; do
    forme_file "$m" "$l"
    if [ "$SOLO" != valida ]; then
      : > "$T/grezzo"
      while IFS=$'\t' read -r tipo mr s _resto; do
        [ "$tipo" = spec ] && [ "$mr" = "$m" ] || continue
        sp=$CORPUS/$m/.claude/.ai-workflow/$s.md
        [ -f "$sp" ] || die "corpus: $m/$s.md missing" 1
        (cd "$T/cwd" && MAAT_LINGUA=$l FIC_PYTHON=$PYN bash "$PLUGIN/scripts/cycle-state.sh" "$sp" > "$T/o" 2>/dev/null); rc=$?
        { printf '== %s/%s\n' "$m" "$s"; corpo "$T/o"; printf '== exit %s\n' "$rc"; } >> "$T/grezzo"
      done < <(casi)
      normalizza "$T/forme-$m-$l" < "$T/grezzo" >> "$T/out/next-$l.txt" || die "attese.py normalizza failed" 1
    fi
  done
  if [ "$SOLO" != next ]; then
    OUTD=$CORPUS/$m/.claude/attese-out
    for v in minimo jsonschema; do
      if [ $v = minimo ]; then py=$PY_MIN; else py=$PY_JS; fi
      [ -n "$py" ] || continue
      for l in $LINGUE; do
        : > "$T/grezzo"
        while IFS=$'\t' read -r mr jf ph; do
          [ "$mr" = "$m" ] || continue
          jl=$CORPUS/$m/.claude/.ai-workflow/$jf
          [ -f "$jl" ] || die "corpus: $m/$jf missing" 1
          rm -rf "$OUTD"; mkdir -p "$OUTD"; r=$OUTD/r.json
          if [ "$VALIDA" = driver ]; then
            (cd "$T/cwd" && MAAT_LINGUA=$l "$py" "$(nat "$PLUGIN/scripts/driver.py")" valida "$(nat "$jl")" "$(nat "$SCHEMA")" "$ph" "$(nat "$r")" > "$T/o" 2> "$T/e"); rc=$?
          else
            (cd "$T/cwd" && MAAT_LINGUA=$l FIC_PYTHON=$py bash "$PLUGIN/scripts/run-phase.sh" --valida "$(nat "$jl")" "$(nat "$SCHEMA")" "$ph" "$(nat "$r")" > "$T/o" 2> "$T/e"); rc=$?
          fi
          if [ -f "$r" ]; then h=$(tr -d '\r' < "$r" | sha256sum | cut -c1-64); else h=nessuno; fi
          { printf '== %s/%s\n-- stdout\n' "$m" "$jf"; corpo "$T/o"; printf -- '-- stderr\n'; corpo "$T/e"
            printf -- '-- exit %s · result.json %s\n' "$rc" "$h"; } >> "$T/grezzo"
        done < "$T/jsonl-fasi"
        normalizza "$T/forme-$m-$l" < "$T/grezzo" >> "$T/out/valida-$v-$l.txt" || die "attese.py normalizza failed" 1
      done
    done
    rm -rf "$OUTD"
  fi
done
echo "attese: calcolate in $(( $(date +%s) - t0 ))s"
if [ -n "$ESITI" ]; then mkdir -p "$ESITI" && cp "$T/out/"* "$ESITI/" || die "--esiti: cannot write $ESITI"; fi

# --- compare, or write ---
uguali=0 diversi=0 cambiati=()
for f in "${FILES[@]}"; do
  if [ $parziale = 1 ]; then "$PY0" "$(nat "$APY")" confronta "$(nat "$ATT/$f")" "$(nat "$T/out/$f")" "${REPOS[@]}" > "$T/cf" 2>&1
  else "$PY0" "$(nat "$APY")" confronta "$(nat "$ATT/$f")" "$(nat "$T/out/$f")" > "$T/cf" 2>&1; fi
  rc=$?
  nb=$(grep -c '^== [^ /]*/[^ ]*$' "$T/out/$f")
  if [ $rc = 0 ]; then uguali=$((uguali + 1)); echo "attese: $f UGUALE ($nb blocchi)"
  else
    diversi=$((diversi + 1)); cambiati+=("$f")
    if [ $MODO = scrivi ]; then
      if [ -f "$ATT/$f" ]; then echo "attese: $f cambia ($(grep -vc '^    ' "$T/cf") blocchi)"; else echo "attese: $f nuovo ($nb blocchi)"; fi
      continue
    fi
    echo "attese: $f DIVERSO ($nb blocchi calcolati)"; sed 's/^/  /' "$T/cf" | head -120
  fi
done
for v in $SALTATI; do for l in $LINGUE; do [ "$SOLO" = next ] || echo "attese: valida-$v-$l.txt SALTATO"; done; done

if [ $MODO = scrivi ]; then
  # the base commit, before writing: «+modifiche» when the working tree already differs from it
  base=$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo "?")
  [ -z "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ] || base="$base+modifiche"
  mkdir -p "$ATTESE_REPO" || die "cannot create $ATTESE_REPO"
  for f in "${FILES[@]}"; do cp "$T/out/$f" "$ATTESE_REPO/$f" || die "cannot write $ATTESE_REPO/$f" 1; done
  if [ ! -f "$ATTESE_REPO/STORIA" ]; then
    printf '%s\n' "# STORIA — one line per \`tools/esempi-equiv/attese.sh --scrivi\` (Maat 1.6.0), appended, never rewritten." \
      "# «<UTC> · base <commit> · plugin <which> · motori <next> · <valida> · corpus <fingerprint 12> · motivo: <text> · file: <changed>»." \
      "# The files of attese/ come from the plugin of the first line, except those of the lines after it." > "$ATTESE_REPO/STORIA"
  fi
  fl=${cambiati[*]:-nessuno}
  printf '%s · base %s · plugin %s · motori %s · corpus %s · motivo: %s · file: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$base" "$QUALE" "$MOTORI" \
    "${IMP:0:12}" "$MOTIVO" "$fl" >> "$ATTESE_REPO/STORIA"
  echo "attese: scritte in $REL (cambiati: $fl), una riga in $REL/STORIA · $(( $(date +%s) - t0 ))s"
  exit 0
fi
echo "attese: confronto · uguali=$uguali · diversi=$diversi · saltati=$(echo $SALTATI | wc -w)$([ $parziale = 1 ] && echo " · parziale") · $(( $(date +%s) - t0 ))s"
[ $diversi -eq 0 ] || exit 1
if [ "$SOLO" != next ] && richiesti_ko; then echo "attese: ROSSO — MAAT_ATTESE_RICHIESTE=1 e validatore SALTATO:$SALTATI"; exit 1; fi
exit 0
