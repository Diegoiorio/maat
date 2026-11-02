#!/usr/bin/env bash
# oracolo.sh — the old-against-new oracle of the plugin (Maat 1.5.0, D10): two plugins on the same projects, the
# outputs of the resume table compared. A tool of the repo, not of the plugin.
#   bash tools/oracolo.sh [--esiti <folder>] <old> <new> <project>…
# <old>, <new>: a plugin folder (it has .claude-plugin/plugin.json; a repo root with plugins/maat/ is accepted too) or
#   a git ref of this repository (`git archive <ref> plugins/maat`; MAAT_ORACOLO_REPO: another repository).
# <project>: the root of a project with .claude/.ai-workflow/ (e.g. a mini-repo of the corpus built by
#   tools/esempi-equiv/costruisci.sh). Never written: an intact copy is taken first (cp -a, mtimes kept). Two projects
#   with the same folder name: usage error.
# The two sides run IN TURN IN THE SAME PATHS: for each side the plugin is put in $T/maat and every project is copied
# again from its intact copy into $T/progetti/<name>, so the plugin root, the absolute paths `mostra` prints
# (cycle-state.sh, rows 0 and C4) and the paths of the run dirs are the same by construction. For each side and each
# language (MAAT_LINGUA=it, then en):
#   1. the VALID harness.fp (exactly one line «impronta=<64 hex>») of the run dirs not listed in the project's
#      .claude/oracolo-conserva (the fixtures — CAMBIATO, FORMATO-PRECEDENTE, ILLEGGIBILE, ... — stay as they are)
#      are rewritten with `run-phase.sh --harness-fp` of that side in that language; then their mtime is restored from
#      the intact copy (touch -r: the mtime enters the «since» of row 0). Every rewritten file must then be UGUALE for
#      `run-phase.sh --harness-fp-confronta` of that side: no Next is decided by a rewritten harness.fp. A rewrite that
#      fails leaves the file as it was (an AVVISO line);
#   2. for every spec with its run dir (the specs `driver.py equiv` sees): `cycle-state.sh` (FIC_DRIVER=0: the table
#      in bash, never the driver), `plan-check.sh basis` and `plan-check.sh contract`: stdout (CR removed) and exit code.
# One normalization, declared: the CURRENT harness fingerprint of the side (`run-phase.sh --harness-fp` of that side, in
# that language, on that project: 64 hex and its first 12) becomes <impronta-attuale> in the records. The STOPs of row 0
# print it («attuale <12>»), and two different plugins have two different fingerprints by construction; the recorded
# one (the fixture) is not touched. Not computable (row 0 NON-CALCOLABILE): nothing to replace.
# Comparison: in it the whole record identical; in en «State:», «Last code phase:», the first word of «Next:», basis,
# contract and the exit codes identical (the reasons of Next are translated).
# Output: «oracolo: parola <side> <language> <project>/<spec> <WORD>» per spec, side (vecchio, nuovo) and language: the
# first word of Next seen on THAT side, after the rewrite («-» without a Next line); the anomalies; then
# «oracolo: harness.fp riscritti=R · conservati=C · non-uguali=K» and «oracolo: spec=N · it uguali=I · en uguali=E ·
# diverse=D» (D = the specs different in at least one language), with the diffs below it (at most 40 lines per spec and
# language).
# Exit 0 everything identical · 1 a difference, or a rewritten harness.fp not UGUALE · 2 usage, a side or a project not
# usable.
# --esiti <folder>: keeps the records, <folder>/<side>-<language>/<project>/<spec>.txt (must not exist or be empty).
# Cost: per spec, side and language one cycle-state.sh and two plan-check.sh (review-surface.sh on the whole working
# tree of the project): on Windows minutes for the public corpus, much less in WSL or on Linux.
set -uo pipefail
export LC_ALL=C PYTHONDONTWRITEBYTECODE=1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO=${MAAT_ORACOLO_REPO:-$ROOT}

usage() { echo "usage: bash tools/oracolo.sh [--esiti <folder>] <old> <new> <project>…   (old, new: plugin folder or git ref)" >&2; exit 2; }
die() { echo "oracolo.sh: $1" >&2; exit 2; }
ESITI=
if [ "${1:-}" = --esiti ]; then [ $# -ge 2 ] || usage; ESITI=$2; shift 2; fi
[ $# -ge 3 ] || usage
VECCHIO=$1 NUOVO=$2; shift 2
if [ -n "$ESITI" ]; then
  if [ -e "$ESITI" ] && [ -n "$(ls -A "$ESITI" 2>/dev/null)" ]; then die "$ESITI exists and is not empty"; fi
  mkdir -p "$ESITI" && ESITI=$(cd "$ESITI" && pwd) || die "cannot create $ESITI"
fi

T=$(mktemp -d) || die "mktemp"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/lati" "$T/intatti" "$T/esiti"

# --- the two sides: $T/lati/<side>, a plugin root ---
prepara_lato() { # $1 argument (folder or ref), $2 destination
  local a=$1 d=$2
  if [ -d "$a" ]; then
    [ -f "$a/.claude-plugin/plugin.json" ] || { [ -f "$a/plugins/maat/.claude-plugin/plugin.json" ] && a=$a/plugins/maat; }
    [ -f "$a/.claude-plugin/plugin.json" ] || die "$1: a folder without .claude-plugin/plugin.json (nor plugins/maat/)"
    mkdir -p "$d" && cp -R "$a/." "$d/" || die "$1: copy failed"
    find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  else
    git -C "$REPO" rev-parse -q --verify "$a^{commit}" >/dev/null 2>&1 || die "$1: neither a plugin folder nor a git ref of $REPO"
    mkdir -p "$d.x" || die "mkdir"
    git -C "$REPO" -c core.autocrlf=false archive "$a" plugins/maat | tar -x -C "$d.x" || die "$1: git archive failed"
    mv "$d.x/plugins/maat" "$d" && rm -rf "$d.x" || die "$1: no plugins/maat in the ref"
    [ -f "$d/.claude-plugin/plugin.json" ] || die "$1: the ref has no plugins/maat/.claude-plugin/plugin.json"
  fi
  for s in cycle-state.sh plan-check.sh run-phase.sh; do [ -f "$d/scripts/$s" ] || die "$1: no scripts/$s"; done
}
prepara_lato "$VECCHIO" "$T/lati/vecchio"
prepara_lato "$NUOVO" "$T/lati/nuovo"

# --- the projects: an intact copy of each (the original is only read) ---
NOMI=()
for p in "$@"; do
  [ -d "$p/.claude/.ai-workflow" ] || die "$p: not a project root with .claude/.ai-workflow/"
  n=$(basename "$(cd "$p" && pwd)")
  [ -e "$T/intatti/$n" ] && die "two projects named $n"
  cp -a "$p" "$T/intatti/$n" || die "$p: copy failed"
  NOMI+=("$n")
done

conservati() { # $1 project copy → the harness.fp kept as they are (paths from the project root)
  [ -f "$1/.claude/oracolo-conserva" ] && tr -d '\r' < "$1/.claude/oracolo-conserva" | grep -v '^[[:space:]]*\(#\|$\)'   # CONSERVA
  return 0
}
valido() { [ "$(tr -d '\r' < "$1" | grep -cE '^impronta=[0-9a-f]{64}$')" = 1 ]; }
estrai_en() { # the fields compared in en
  awk '/^== /{ m = ($2 == "cycle-state"); print; next }
    m && /^(State:|Last code phase:)/ { print; next }
    m && /^Next: / { print $1, $2; next }
    !m { print }' "$1"
}

riscritti=0 conservati_n=0 non_uguali=0
for lato in vecchio nuovo; do
  rm -rf "$T/maat"; cp -R "$T/lati/$lato" "$T/maat" || die "copy of the $lato side"
  S=$T/maat/scripts
  for lingua in it en; do
    for n in "${NOMI[@]}"; do
      P=$T/progetti/$n; E=$T/esiti/$lato-$lingua/$n
      rm -rf "$P"; mkdir -p "$T/progetti" "$E"; cp -a "$T/intatti/$n" "$P" || die "copy of $n"
      (
        cd "$P" || exit 2
        unset FIC_REPO FIC_DRIVER_ROOT FIC_DRIVER_CERT MAAT_MSG_PY
        export MAAT_ROOT=$T/maat FIC_DRIVER=0 MAAT_LINGUA=$lingua
        W=.claude/.ai-workflow
        keep=$(conservati .)
        for fp in "$W"/*.run/harness.fp; do
          [ -f "$fp" ] || continue
          sn=$(basename "${fp%.run/harness.fp}")
          if printf '%s\n' "$keep" | grep -qxF -- "$fp"; then echo "C"; continue; fi
          valido "$fp" || continue
          if bash "$S/run-phase.sh" --harness-fp "$P" > "$fp.oracolo" 2>/dev/null && valido "$fp.oracolo"; then
            mv "$fp.oracolo" "$fp" && touch -r "$T/intatti/$n/$fp" "$fp"
            echo "R"
            v=$(bash "$S/run-phase.sh" --harness-fp-confronta "$fp" "$P" 2>/dev/null | tr -d '\r')
            [ "${v%% *}" = UGUALE ] || { echo "K"; echo "oracolo: harness.fp riscritto non UGUALE $lato $lingua $n/$sn: ${v:-(nessuna uscita)}" >&2; }
          else
            rm -f "$fp.oracolo"
            echo "oracolo: AVVISO — harness.fp non riscritto $lato $lingua $n/$sn (run-phase.sh --harness-fp fallito): resta com'era" >&2
          fi
        done > "$T/conteggi"
        # the current harness fingerprint of this side (rows 0 print it: different between two plugins by construction)
        cur=$(bash "$S/run-phase.sh" --harness-fp "$P" 2>/dev/null | tr -d '\r' | sed -n 's/^impronta=\([0-9a-f]\{64\}\)$/\1/p')
        norm() { if [ -n "$cur" ]; then sed "s/$cur/<impronta-attuale>/g; s/${cur:0:12}/<impronta-attuale>/g"; else cat; fi; }   # IMPRONTA-ATTUALE
        for sp in "$W"/spec-*.md; do
          [ -d "${sp%.md}.run" ] || continue
          sn=$(basename "${sp%.md}")
          {
            echo "== cycle-state"; bash "$S/cycle-state.sh" "$sp" 2>/dev/null | tr -d '\r'; echo "== exit ${PIPESTATUS[0]}"
            echo "== basis"; bash "$S/plan-check.sh" basis "$sp" 2>/dev/null | tr -d '\r'; echo "== exit ${PIPESTATUS[0]}"
            echo "== contract"; bash "$S/plan-check.sh" contract "$sp" 2>/dev/null | tr -d '\r'; echo "== exit ${PIPESTATUS[0]}"
          } | norm > "$E/$sn.txt"
          w=$(sed -n 's/^Next: \([^ ]*\).*/\1/p' "$E/$sn.txt" | tail -1)
          echo "oracolo: parola $lato $lingua $n/$sn ${w:--}"
        done
      ) 2>&1 || die "$n: the $lato side ($lingua) failed"
      riscritti=$((riscritti + $(grep -c '^R$' "$T/conteggi")))
      conservati_n=$((conservati_n + $(grep -c '^C$' "$T/conteggi")))
      non_uguali=$((non_uguali + $(grep -c '^K$' "$T/conteggi")))
    done
  done
done

# --- comparison ---
N=0 IT=0 EN=0 DIV=0
: > "$T/diff"
for n in "${NOMI[@]}"; do
  for f in "$T/esiti/vecchio-it/$n"/*.txt; do
    [ -f "$f" ] || continue
    sn=$(basename "$f" .txt); N=$((N + 1)); d=0
    if diff "$f" "$T/esiti/nuovo-it/$n/$sn.txt" > "$T/d" 2>&1; then IT=$((IT + 1))
    else d=1; { echo "--- $n/$sn it (< vecchio, > nuovo)"; head -40 "$T/d"; } >> "$T/diff"; fi
    if diff <(estrai_en "$T/esiti/vecchio-en/$n/$sn.txt") <(estrai_en "$T/esiti/nuovo-en/$n/$sn.txt") > "$T/d" 2>&1; then EN=$((EN + 1))
    else d=1; { echo "--- $n/$sn en: State, Last code phase, parola di Next, basis, contract (< vecchio, > nuovo)"; head -40 "$T/d"; } >> "$T/diff"; fi
    DIV=$((DIV + d))
  done
done
[ -n "$ESITI" ] && cp -R "$T/esiti/." "$ESITI/"
echo "oracolo: harness.fp riscritti=$riscritti · conservati=$conservati_n · non-uguali=$non_uguali"
echo "oracolo: spec=$N · it uguali=$IT · en uguali=$EN · diverse=$DIV"
cat "$T/diff"
[ "$N" -gt 0 ] || die "no spec with its run dir in the projects"
[ $DIV -eq 0 ] && [ $non_uguali -eq 0 ]
