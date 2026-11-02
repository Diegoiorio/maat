#!/usr/bin/env bash
# certifica.sh — the equivalence certificate of the driver on the public corpus, in one command (Maat 1.5.0).
#   bash tools/certifica.sh            verify: builds the corpus, proves it, writes the certificate to a temporary file
#   bash tools/certifica.sh --scrivi   the same, then copies it to plugins/maat/scripts/driver.equiv (Linux only, D13)
# Steps: tools/esempi-equiv/costruisci.sh in a temporary folder; `driver.py equiv --certifica` with a temporary
# FIC_DRIVER_CERT on the folders of the mini-repos in the fixed order of the builder, once per validator (D14: first
# «minimo», MAAT_PY_MINIMO or the interpreter of python.sh, which must not import jsonschema; then «jsonschema»,
# MAAT_PY_JSONSCHEMA, ~/maat-venv/bin/python or the interpreter of python.sh when it imports jsonschema, with
# --validatori-precedenti minimo); then `driver.py certificato` on that file and the check
# that its corpus line carries the fingerprint printed by the builder. With --scrivi the file is copied into the plugin
# (the only write into plugins/maat/) and `certificato` is run again on it. Prints the duration.
# --scrivi refuses (exit 2): outside Linux (on Windows: run it in WSL on the /mnt/c/… path of the worktree), without
# one of the two validators, or with a jsonschema of a version other than the one fixed in .github/workflows/ci.yml.
# Never in parallel with anything else (suites, giro-completo, the other proof): constraint 4 of the plan.
# Exit 0 · 1 the build, the proof or the certificate failed · 2 usage or environment (the reason on stderr).
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1   # no __pycache__ in the plugin
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCR=$ROOT/plugins/maat/scripts
DRV=$SCR/driver.py
CERT=$SCR/driver.equiv
die() { echo "certifica.sh: $1" >&2; exit "${2:-1}"; }
SCRIVI=0
case "${1:-}" in "") ;; --scrivi) SCRIVI=1 ;; *) echo "usage: bash tools/certifica.sh [--scrivi]" >&2; exit 2 ;; esac
[ $# -le 1 ] || { echo "usage: bash tools/certifica.sh [--scrivi]" >&2; exit 2; }
t0=$(date +%s)
JV=$(tr -d '\r' < "$ROOT/.github/workflows/ci.yml" 2>/dev/null | grep -o 'jsonschema==[0-9][0-9.]*' | head -1)
JV=${JV#jsonschema==}
if [ $SCRIVI = 1 ] && [ "$(uname -s)" != Linux ]; then
  die "--scrivi only from Linux (D13: the environment of the CI that checks it). On Windows, in WSL:
  wsl -- bash -lc 'cd /mnt/c/<worktree path> && bash tools/certifica.sh --scrivi'" 2
fi

# --- the two validators ---
FIC_PY=""; . "$SCR/python.sh" >/dev/null 2>&1
[ -n "$FIC_PY" ] || die "no Python (python.sh)" 2
validatore() { "$1" -c "import jsonschema" >/dev/null 2>&1 && echo jsonschema || echo minimo; }
PY_MIN=${MAAT_PY_MINIMO:-} PY_JS=${MAAT_PY_JSONSCHEMA:-}
if [ -n "$PY_MIN" ] && [ "$(validatore "$PY_MIN")" != minimo ]; then die "MAAT_PY_MINIMO=$PY_MIN imports jsonschema" 2; fi
[ -n "$PY_JS" ] || { [ -x "$HOME/maat-venv/bin/python" ] && PY_JS=$HOME/maat-venv/bin/python; }
# the interpreter of python.sh: the minimal validator, or (when it imports jsonschema and nothing else gives it) jsonschema
if [ "$(validatore "$FIC_PY")" = minimo ]; then [ -n "$PY_MIN" ] || PY_MIN=$FIC_PY; elif [ -z "$PY_JS" ]; then PY_JS=$FIC_PY; fi
if [ -n "$PY_JS" ] && [ "$(validatore "$PY_JS")" != jsonschema ]; then
  [ $SCRIVI = 1 ] && die "$PY_JS does not import jsonschema" 2
  echo "certifica.sh: $PY_JS does not import jsonschema: validator jsonschema skipped" >&2; PY_JS=""
fi
VENV_CMD="python3 -m venv ~/maat-venv && ~/maat-venv/bin/pip install jsonschema==${JV:-<version of ci.yml>}"
if [ $SCRIVI = 1 ]; then
  [ -n "$PY_MIN" ] || die "validator minimo missing: $FIC_PY imports jsonschema. Point MAAT_PY_MINIMO to an interpreter
without it, e.g. a venv with no packages (created once, an installation): python3 -m venv ~/maat-venv-minimo, then
MAAT_PY_MINIMO=~/maat-venv-minimo/bin/python" 2
  [ -n "$PY_JS" ] || die "validator jsonschema missing: no MAAT_PY_JSONSCHEMA and no ~/maat-venv. Create it once (an installation):
  $VENV_CMD
or point MAAT_PY_JSONSCHEMA to an interpreter with jsonschema==${JV:-?}" 2
  [ -n "$JV" ] || die "no jsonschema==<version> in .github/workflows/ci.yml" 2
  v=$("$PY_JS" -c 'import importlib.metadata as m; print(m.version("jsonschema"))' 2>/dev/null | tr -d '\r')
  [ "$v" = "$JV" ] || die "jsonschema $v in $PY_JS, the CI fixes $JV: $VENV_CMD" 2
fi
[ -n "$PY_MIN" ] || echo "SALTATO: minimo ($FIC_PY imports jsonschema; MAAT_PY_MINIMO: an interpreter without it)"
[ -n "$PY_JS" ] || echo "SALTATO: jsonschema (no MAAT_PY_JSONSCHEMA, no ~/maat-venv: $VENV_CMD)"
[ -n "$PY_MIN$PY_JS" ] || die "no validator available" 2

# --- the corpus ---
T=$(mktemp -d) || die "mktemp" 2
trap 'rm -rf "$T"' EXIT
bash "$ROOT/tools/esempi-equiv/costruisci.sh" "$T/corpus" > "$T/costruisci.out" 2>&1 || { tail -20 "$T/costruisci.out" >&2; die "the build of the corpus failed"; }
IMP=$(sed -n 's/^impronta //p' "$T/costruisci.out" | tr -d '\r')
[[ $IMP =~ ^[0-9a-f]{64}$ ]] || die "the builder printed no fingerprint"
TARGETS=(); while IFS= read -r m; do TARGETS+=("$T/corpus/$m/.claude/.ai-workflow"); done < <(sed -n 's/^esempi-equiv: \(progetto-[^ ]*\) · spec=.*/\1/p' "$T/costruisci.out")
[ ${#TARGETS[@]} -gt 0 ] || die "the builder listed no mini-repo"
grep '^esempi-equiv: [0-9]' "$T/costruisci.out"
echo "impronta ${IMP:0:12} · costruzione $(( $(date +%s) - t0 ))s"

# --- the proof, once per validator; the second pass joins the first one's validator ---
prec=""
for v in minimo jsonschema; do
  if [ $v = minimo ]; then py=$PY_MIN; else py=$PY_JS; fi
  [ -n "$py" ] || continue
  t1=$(date +%s)
  FIC_DRIVER_CERT="$T/driver.equiv" FIC_PY=$py "$py" "$DRV" equiv --certifica ${prec:+--validatori-precedenti "$prec"} "${TARGETS[@]}" > "$T/equiv-$v.out" 2>&1
  rc=$?
  grep -E '^(equiv: (lingua|spec=)|DIVERSO)' "$T/equiv-$v.out" | tr -d '\r' | sed "s/^/[$v] /"
  echo "[$v] $(( $(date +%s) - t1 ))s, exit $rc"
  [ $rc -eq 0 ] || die "equiv with the validator $v: exit $rc (output above; the DIVERSO lines say where)"
  prec=${prec:+$prec,}$v
done
o=$(FIC_DRIVER_CERT="$T/driver.equiv" "$FIC_PY" "$DRV" certificato 2>&1 | tr -d '\r'); echo "$o"
case $o in "certificato: VALIDO"*) ;; *) die "the certificate just written is not VALIDO" ;; esac
c=$(tr -d '\r' < "$T/driver.equiv" | grep '^corpus ')
[[ $c == *" · impronta ${IMP:0:12} · "* ]] || die "the corpus line does not carry the fingerprint of the builder (${IMP:0:12}): $c"

if [ $SCRIVI = 1 ]; then
  [[ $c == *" · validatori minimo,jsonschema" ]] || die "the corpus line does not say «validatori minimo,jsonschema»: $c"
  cp "$T/driver.equiv" "$CERT" || die "cannot write $CERT"
  o=$("$FIC_PY" "$DRV" certificato 2>&1 | tr -d '\r'); echo "$o"
  case $o in "certificato: VALIDO"*) ;; *) die "$CERT written but not VALIDO" ;; esac
  echo "certifica.sh: scritto $CERT ($(( $(date +%s) - t0 ))s)"
else
  echo "certifica.sh: verifica riuscita, certificato non scritto (--scrivi da Linux per scriverlo) ($(( $(date +%s) - t0 ))s)"
fi
exit 0
