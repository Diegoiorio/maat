#!/usr/bin/env bash
# replay.sh — replays ONE phase of a real /full-implementation-cycle run in a throwaway git worktree,
# with --no-dev, and measures it with cycle-report.py.
#
#   replay.sh <cycle> <phase> [--harness <plugin>] [--source <dir>] [--worktree <path>] [--out <dir>]
#             [--inject <name>]... [--dry-run]
#   replay.sh --check [--source <dir>]          corpus cycles: are spec, run directory and base present?
#   replay.sh --remove <path> [--dry-run]       removes a worktree left behind by an interrupted replay
#
#   The project is the one of the working directory (PROJECT_ROOT); the corpus is the corpus.json named by
#   cartelle.corpus in its maat.json (relative to the repository; absent: no corpus, run directories by name only).
#   <cycle>   corpus id (for example `ciclo-1`) or the name of ANY run directory, even outside the
#             corpus: `export-csv`, `spec-export-csv` or `spec-export-csv.run`
#             (base from base.txt)
#   <phase>   label (`06-review`) or phase name (plan|implement|review|fix) if it is unique in the cycle
#   --harness the ROOT OF A maat PLUGIN (with .claude-plugin/plugin.json) to launch the phase from: its
#             scripts/run-phase.sh, and the same plugin loaded in the sub-session (MAAT_PLUGIN_DIR, exported
#             ALWAYS: the replay does not depend on the plugin being enabled in the worktree) (default: MAAT_ROOT,
#             the plugin of this script). The harness is NOT copied into the worktree
#   --source  the directory with spec-*.md and spec-*.run/ (default: the work directory, cartelle.lavoro, of the
#             MAIN tree, resolved with `git rev-parse --git-common-dir`: run directories are gitignored and live there)
#   --worktree where to create the worktree (default: next to the main tree, fic-replay-<label>-<time>: short,
#             because of the Windows path length limit);
#             the name must start with fic-replay- and the path must not exist
#   --out     where to save log and report of the replayed phase (default <source>/spec-<name>.replay/<label>-<time>,
#             gitignored by the spec-* rule)
#   --inject  inject/ script (without .sh) to apply to the worktree before the phase; repeatable
#   --non-confrontabile  proceeds even if the dependencies at the phase state differ from those of the
#             main tree (see below); the replay is marked NON CONFRONTABILE in report.txt and in
#             NON-CONFRONTABILE.txt of the output
#   --dry-run prints the commands without running them: no worktree, no file, no session
#
# What it does, in order: `git worktree add --detach` at the cycle base; `fic-replay` marker in the worktree's
# OWN git dir (outside the working tree, hence never review surface); the code at the phase
# state — the label's .pre-tree, otherwise the last earlier .post-tree, otherwise the
# base — applied as UNCOMMITTED changes (as in the real cycle); the spec (in its CURRENT state: the run
# directory does not keep its versions) and the run
# directory up to the phase, excluded (log and prompts of earlier labels, base/do-not-touch/mixed if
# an implement or fix precedes, touched.txt recomputed from the earlier .pre/.post-tree pairs); the
# ORIGINAL prompt of the phase with --no-dev inserted after the name and the skill with the plugin prefix
# (/maat:full-implementation-cycle: the plugin's skill, not whatever the cycle's commit had in .claude/skills);
# the injects; the phase with scripts/run-phase.sh of the --harness plugin, cwd in the worktree, MAAT_PLUGIN_DIR=<plugin>,
# with the lock of the MAIN tree (FIC_LOCK: the vitest-fast mirror and DEV are
# shared, so a replay never runs alongside a real code phase); copy of the logs to --out;
# cycle-report.py on that copy; `git worktree remove --force` ONLY after verifying that the
# path is a worktree created by replay.sh (name fic-replay-*, marker with its path, listed by
# `git worktree list`, outside the main tree and the harness).
# A replay interrupted while the phase is still running leaves the worktree (removing it under a live
# session would be worse): remove it later with --remove.
#
# Dependencies (the phase gates must run as in the original, without installing anything):
# - BEFORE creating the worktree: the dependency files (package.json and package-lock.json of the root
#   and of modules/app, modules/api/requirements*.txt) at the phase state must match those
#   of the main tree (`git diff` between that tree and the main working tree, same logic as git
#   status: CRLF included). Otherwise: exit 2, no worktree; --non-confrontabile to proceed anyway;
# - node_modules (root, modules/app, apps/*, packages/*) and modules/api/.venv of the main tree are
#   LINKED into the worktree (junction on Windows, symlink elsewhere), never copied or installed; from
#   apps/admin/.nuxt tsconfig.json and *.d.ts are copied (lint needs them: vitest-fast.sh);
# - the worktree's .git points to the git dir with a RELATIVE path (`git worktree add` writes "gitdir: C:/…";
#   vitest-fast.sh and counterproof.sh now translate it themselves, via script/test/fic-mirror.sh: the relative
#   path stays as an extra safeguard);
# - WSL copy of the worktree: vitest-fast.sh and counterproof.sh use ~/fic-mirror-<hash> (one per root) and,
#   on first use, SEED its node_modules as hardlinks from the main tree's copy, if the dependencies
#   match (fingerprint on content without CR: line endings of the new checkout no longer matter, no
#   byte copy). Different fingerprint: warning in log and report (the copy is not seeded and the gates exit
#   BLOCKED), without stopping;
# - removal: FIRST the worktree's WSL copies (fic_lane_forget k=1,2 for the lanes, then fic_mirror_forget:
#   never ~/fic-mirror; if a run holds it,
#   it stays with a warning — to delete later with the same command), THEN the links are removed (only the
#   link, never recursive), THEN `git worktree remove --force`; if a link remains, the worktree
#   is NOT removed (following it would delete the main tree's dependencies). No orphan
#   ~/fic-mirror-<hash> copy at the end of the replay.
# Known limit: a prompt that quotes absolute paths of the main tree still quotes them.
#
# Exit: that of the phase · 0 --check/--remove/--dry-run succeeded · 1 --check with missing items ·
#         2 invalid usage or cycle data · 3 path refused (not a replay.sh worktree).

set -uo pipefail
unset MSYS_NO_PATHCONV
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
. "$HERE/../lib/maat-paths.sh" || exit 4   # MAAT_SCRIPTS (plugin) and PROJECT_ROOT (working directory)
maat_progetto || exit 4
ROOT=$PROJECT_ROOT
CR="$MAAT_SCRIPTS/cycle-report.py"

die() { echo "replay: $*" >&2; exit 2; }
refuse() { echo "replay: RIFIUTO — $*" >&2; exit 3; }
q() { printf '%q' "$1"; }
# winpath, canon, linking and unlinking of dependencies, relative .git, fingerprint, WSL copy: the
# library shared with script/fic/ciclo-worktree.sh (messages with the «replay:» prefix, as before)
WT_TAG=replay DEP_LINKS_EXTRA=()
. "$MAAT_SCRIPTS/worktree-lib.sh" || die "$MAAT_SCRIPTS/worktree-lib.sh o $MAAT_SCRIPTS/fic-mirror.sh non trovati"
LAVORO=.claude/.ai-workflow   # the work directory (cartelle.lavoro), relative to the repository root
[ -n "$MAAT_WORK" ] && LAVORO=${MAAT_WORK#"$PROJECT_ROOT"/}

common=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "git non trova il repository di $ROOT"
MAIN=$(cd "$(dirname "$common")" && pwd) || die "tree principale non risolto da $common"
MAINGIT=$(git -C "$MAIN" rev-parse --absolute-git-dir 2>/dev/null) || die "git dir del tree principale non risolta"
MAINC=$(canon "$MAIN") ROOTC=$(canon "$ROOT") MAATC=$(canon "$MAAT_ROOT")

# --- check: is the path a worktree created by replay.sh? (0 = yes; otherwise the reason on stderr) ---
ours() {
  local p c gd mk w found=0
  p=$1
  [ -d "$p" ] || { echo "non esiste: $p" >&2; return 1; }
  c=$(canon "$p")
  case "$c" in "$MAINC"|"$MAINC"/*) echo "e' il tree principale o sta dentro: $c" >&2; return 1 ;; esac
  case "$c" in "$ROOTC"|"$ROOTC"/*) echo "e' il tree del progetto o sta dentro: $c" >&2; return 1 ;; esac
  case "$c" in "$MAATC"|"$MAATC"/*) echo "e' il plugin (harness) o sta dentro: $c" >&2; return 1 ;; esac
  case "$(basename "$c")" in fic-replay-*) ;; *) echo "il nome non comincia per fic-replay-: $c" >&2; return 1 ;; esac
  [ "$(canon "$(git -C "$c" rev-parse --show-toplevel 2>/dev/null)")" = "$c" ] ||
    { echo "non e' la radice di un worktree git: $c" >&2; return 1; }
  gd=$(git -C "$c" rev-parse --absolute-git-dir 2>/dev/null)
  mk="$gd/fic-replay"
  [ -f "$mk" ] || { echo "manca il marcatore di replay.sh ($mk)" >&2; return 1; }
  [ "$(canon "$(sed -n 's/^path=//p' "$mk")")" = "$c" ] || { echo "il marcatore indica un altro percorso: $(sed -n 's/^path=//p' "$mk")" >&2; return 1; }
  while IFS= read -r w; do [ "$(canon "$w")" = "$c" ] && found=1; done < <(git -C "$MAIN" worktree list --porcelain | sed -n 's/^worktree //p')
  [ $found -eq 1 ] || { echo "non e' fra i worktree del repository principale: $c" >&2; return 1; }
  return 0
}

# FIC_REPLAY_LIB=1: functions only (for the tests, which exercise them on synthetic directories)
[ "${FIC_REPLAY_LIB:-0}" = 1 ] && return 0

# --- arguments ---
DRY=0 MODE=replay HARNESS=$MAAT_ROOT SRC="" WT="" OUT="" INJECT=() POS=() RM_PATH="" ALLOW_DEPS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --non-confrontabile) ALLOW_DEPS=1; shift ;;
    --check) MODE=check; shift ;;
    --remove) MODE=remove; RM_PATH=${2:-}; [ -n "$RM_PATH" ] || die "--remove vuole un percorso"; shift 2 ;;
    --harness) HARNESS=${2:-}; [ -n "$HARNESS" ] || die "--harness vuole la radice di un plugin"; shift 2 ;;
    --source) SRC=${2:-}; [ -n "$SRC" ] || die "--source vuole una cartella"; shift 2 ;;
    --worktree) WT=${2:-}; [ -n "$WT" ] || die "--worktree vuole un percorso"; shift 2 ;;
    --out) OUT=${2:-}; [ -n "$OUT" ] || die "--out vuole una cartella"; shift 2 ;;
    --inject) [ -n "${2:-}" ] || die "--inject vuole un nome"; INJECT+=("$2"); shift 2 ;;
    -*) die "opzione sconosciuta: $1" ;;
    *) POS+=("$1"); shift ;;
  esac
done
SRC=${SRC:-$MAIN/$LAVORO}
[ -d "$SRC" ] || die "cartella delle spec assente: $SRC"
SRC=$(cd "$SRC" && pwd)

# --- --remove ---
if [ "$MODE" = remove ]; then
  [ ${#POS[@]} -eq 0 ] || die "--remove non vuole altri argomenti"
  ours "$RM_PATH" || refuse "$RM_PATH non e' un worktree creato da replay.sh: non lo rimuovo"
  c=$(canon "$RM_PATH")
  echo "+ forget_mirror $(q "$c")"
  echo "+ unlink_deps $(q "$c")"
  echo "+ git -C $(q "$MAIN") worktree remove --force $(q "$c")"
  [ $DRY -eq 1 ] && exit 0
  forget_mirror "$c"
  unlink_deps "$c" || refuse "collegamenti ancora presenti in $c: non lo rimuovo (seguirebbe le dipendenze del tree principale)"
  git -C "$MAIN" worktree remove --force "$c"
  exit $?
fi

. "$MAAT_SCRIPTS/python.sh" || die "interprete Python non trovato (imposta FIC_PYTHON)"
# the PROJECT corpus (cartelle.corpus of maat.json, relative to the repository), never a plugin one
CORPUS_W=""
if [ -n "${MAAT_CONFIG:-}" ] || [ -f "$ROOT/.claude/maat.json" ]; then
  . "$MAAT_SCRIPTS/lib/maat-conf.sh" || die "lettore della configurazione non trovato: $MAAT_SCRIPTS/lib/maat-conf.sh"
  cc=$(PROJECT_ROOT=$ROOT maat_conf cartelle.corpus 2>/dev/null | tr -d '\r') || cc=""
  if [ -n "$cc" ]; then
    [ -f "$ROOT/$cc" ] || die "corpus di cartelle.corpus assente: $ROOT/$cc"
    CORPUS_W=$(winpath "$ROOT/$cc")
  fi
fi
corpus() { # $1 = id → "<run>\t<spec>\t<base>" ; no argument → all rows "<id>\t<run>\t<spec>\t<base>"
  [ -n "$CORPUS_W" ] || return 0   # no corpus: run directories by name only
  "$FIC_PY" -c '
import json, sys
cs = json.load(open(sys.argv[1], encoding="utf-8"))["cicli"]
for c in cs:
    if len(sys.argv) < 3:
        print("\t".join([c["id"], c["run"], c["spec"], c["base"]]))
    elif c["id"] == sys.argv[2]:
        print("\t".join([c["run"], c["spec"], c["base"]]))
' "$CORPUS_W" "$@" | tr -d '\r'
}

# --- --check ---
if [ "$MODE" = check ]; then
  [ ${#POS[@]} -eq 0 ] || die "--check non vuole altri argomenti"
  [ -n "$CORPUS_W" ] || die "nessun corpus: cartelle.corpus non impostata nella maat.json del progetto ($ROOT)"
  miss=0
  while IFS=$'\t' read -r id run spec base; do
    s="ok"
    [ -f "$SRC/$spec" ] || { s="SPEC MANCANTE ($spec)"; miss=1; }
    [ -d "$SRC/$run" ] || { s="$s · RUN DIRECTORY MANCANTE ($run)"; miss=1; }
    b=$(tr -d '\r\n ' 2>/dev/null < "$SRC/$run/base.txt")
    [ "$b" = "$base" ] || { s="$s · base.txt ($b) diversa da corpus.json ($base)"; miss=1; }
    git -C "$MAIN" cat-file -e "$base^{commit}" 2>/dev/null || { s="$s · commit di base assente"; miss=1; }
    echo "$id: $s"
  done < <(corpus)
  exit $miss
fi

# --- cycle and phase ---
[ ${#POS[@]} -eq 2 ] || die "uso: replay.sh <ciclo> <fase> [--harness <tree>] [--source <dir>] [--worktree <path>] [--out <dir>] [--inject <nome>]... [--dry-run] | --check | --remove <path>"
CYC=${POS[0]} FASE=${POS[1]}
row=$(corpus "$CYC")
if [ -n "$row" ]; then
  IFS=$'\t' read -r run spec cbase <<< "$row"
  NAME=${run#spec-}; NAME=${NAME%.run}
else
  NAME=${CYC#spec-}; NAME=${NAME%.run}; NAME=${NAME%.md}; cbase=""
fi
RUN_SRC="$SRC/spec-$NAME.run" SPEC_SRC="$SRC/spec-$NAME.md"
[ -f "$SPEC_SRC" ] || die "spec mancante: $SPEC_SRC"
[ -d "$RUN_SRC/log" ] || die "run directory mancante o senza log: $RUN_SRC"
BASE=$(tr -d '\r\n ' 2>/dev/null < "$RUN_SRC/base.txt")
[ -n "$cbase" ] && [ -n "$BASE" ] && [ "$cbase" != "$BASE" ] && die "base di corpus.json ($cbase) diversa da base.txt ($BASE)"
BASE=${BASE:-$cbase}
[ -n "$BASE" ] || die "base del ciclo sconosciuta: manca $RUN_SRC/base.txt"
git -C "$MAIN" cat-file -e "$BASE^{commit}" 2>/dev/null || die "commit di base assente dal repository: $BASE"

LABELS=$(for f in "$RUN_SRC"/prompts/*.md "$RUN_SRC"/log/*.jsonl; do
  [ -e "$f" ] || continue; b=$(basename "$f"); b=${b%.md}; b=${b%.jsonl}; echo "$b"
done | grep -E '^[0-9]+-[a-z]+$' | sort -u)
if printf '%s' "$FASE" | grep -qE '^[0-9]+-[a-z]+$'; then
  printf '%s\n' "$LABELS" | grep -qxF "$FASE" || die "etichetta $FASE assente in $RUN_SRC (etichette: $(echo $LABELS))"
  LABEL=$FASE
else
  case "$FASE" in plan|implement|review|fix) ;; *) die "fase sconosciuta: $FASE (plan|implement|review|fix o un'etichetta NN-fase)" ;; esac
  cand=$(printf '%s\n' "$LABELS" | grep -E "^[0-9]+-$FASE\$")
  [ -n "$cand" ] || die "nessuna fase $FASE in $RUN_SRC (etichette: $(echo $LABELS))"
  [ "$(printf '%s\n' "$cand" | wc -l)" -eq 1 ] || die "fase $FASE ambigua: indica l'etichetta ($(echo $cand))"
  LABEL=$cand
fi
PHASE=${LABEL#*-} NUM=$((10#${LABEL%%-*}))
PROMPT_SRC="$RUN_SRC/prompts/$LABEL.md"
[ -f "$PROMPT_SRC" ] || die "prompt originale assente: $PROMPT_SRC"
head -1 "$PROMPT_SRC" | grep -qE "^/(maat:)?full-implementation-cycle --worker=$PHASE [^ ]+" ||
  die "la prima riga del prompt non e' /full-implementation-cycle (o /maat:full-implementation-cycle) --worker=$PHASE <nome>: $PROMPT_SRC"

EARLIER=$(printf '%s\n' "$LABELS" | while read -r l; do [ -n "$l" ] && [ $((10#${l%%-*})) -lt $NUM ] && echo "$l"; done)
code_before=0
for l in $EARLIER; do case "$l" in *-implement|*-fix) code_before=1 ;; esac; done

# code state at the start of the phase
STATE="" STATE_FROM="base $BASE"
if [ -f "$RUN_SRC/log/$LABEL.pre-tree" ]; then
  STATE=$(tr -d '\r\n ' < "$RUN_SRC/log/$LABEL.pre-tree"); STATE_FROM="log/$LABEL.pre-tree"
else
  for l in $EARLIER; do
    [ -f "$RUN_SRC/log/$l.post-tree" ] && { STATE=$(tr -d '\r\n ' < "$RUN_SRC/log/$l.post-tree"); STATE_FROM="log/$l.post-tree"; }
  done
fi
if [ -n "$STATE" ]; then
  [ "$(git -C "$MAIN" cat-file -t "$STATE" 2>/dev/null)" = tree ] ||
    die "il tree $STATE ($STATE_FROM) non e' piu' nel repository (potato da git gc): stato della fase non ricostruibile"
fi
[ "$code_before" -eq 1 ] && [ -z "$STATE" ] && [ "$PHASE" != implement ] &&
  die "una fase di codice precede $LABEL ma nessun .post-tree la registra: stato del codice non ricostruibile"

# dependencies: do the main tree ones fit the phase code? (before creating anything)
DEPS_DIFF=$(deps_diff "${STATE:-$BASE}") NONCONF=""
if [ -n "$DEPS_DIFF" ]; then
  [ $ALLOW_DEPS -eq 1 ] || die "dipendenze diverse fra lo stato della fase ($STATE_FROM) e il tree principale: $(echo $DEPS_DIFF). node_modules e venv collegati dal tree principale non sarebbero quelli di questo codice e i gate non girerebbero come nell'originale. Niente worktree creato. Per rigiocare comunque (rigioco NON CONFRONTABILE): --non-confrontabile"
  NONCONF="dipendenze diverse dal tree principale ($STATE_FROM): $(echo $DEPS_DIFF)"
  echo "replay: NON CONFRONTABILE — $NONCONF"
fi

# harness and injects
HARNESS=$(cd "$HARNESS" 2>/dev/null && pwd) || die "harness inesistente"
[ -f "$HARNESS/.claude-plugin/plugin.json" ] || die "--harness non e' la radice di un plugin (manca .claude-plugin/plugin.json): $HARNESS"
[ -f "$HARNESS/scripts/run-phase.sh" ] || die "il plugin non ha scripts/run-phase.sh: $HARNESS"
for n in ${INJECT[@]+"${INJECT[@]}"}; do
  case "$n" in _*|*/*) die "inject non valido: $n" ;; esac
  [ -f "$HERE/inject/$n.sh" ] || die "inject sconosciuto: $n (in $HERE/inject: $(ls "$HERE/inject" | sed -n 's/\.sh$//p' | grep -v '^_' | tr '\n' ' '))"
done

# worktree and output
STAMP=$(date +%Y%m%d-%H%M%S)-$$
[ -n "$WT" ] || WT="$(dirname "$MAIN")/fic-replay-$LABEL-$STAMP"
case "$(basename "$WT")" in fic-replay-*) ;; *) refuse "il worktree deve chiamarsi fic-replay-*: $WT" ;; esac
[ -e "$WT" ] && refuse "$WT esiste gia': non l'ho creato io, non lo uso"
pd=$(canon "$(dirname "$WT")") && [ -n "$pd" ] || refuse "la cartella madre di $WT non esiste"
WT="$pd/$(basename "$WT")"   # canonical form: it is also the one written in the marker
HARNESSC=$(canon "$HARNESS")
case "$WT" in "$MAINC"/*|"$ROOTC"/*|"$HARNESSC"/*) refuse "il worktree non puo' stare dentro il tree principale o il harness: $WT" ;; esac
OUT=${OUT:-$SRC/spec-$NAME.replay/$LABEL-$STAMP}

AIW="$WT/$LAVORO" RUN_DST="$WT/$LAVORO/spec-$NAME.run"
REL_RUN="$LAVORO/spec-$NAME.run"
LOCK="$MAINGIT/full-implementation-cycle.lock"

# act: prints and runs (in --dry-run only prints); a failed preparation step stops everything (the
# trap removes the worktree). act_rc: prints, runs and returns the exit code (the phase, the measurement).
act() { printf '+ %s\n' "$1"; [ $DRY -eq 1 ] && return 0; eval "$1" || die "passo fallito: $1"; }
act_rc() { printf '+ %s\n' "$1"; [ $DRY -eq 1 ] && return 0; eval "$1"; }

echo "replay: ciclo spec-$NAME · fase $LABEL · base $BASE · codice da $STATE_FROM · harness $HARNESS"
echo "replay: worktree $WT · uscita $OUT$([ $DRY -eq 1 ] && echo ' · DRY-RUN: nulla viene eseguito')"

CREATED="" DONE_CLEAN=0
cleanup() {
  [ -n "$CREATED" ] && [ $DONE_CLEAN -eq 0 ] || return 0
  DONE_CLEAN=1
  if [ -f "$RUN_DST/log/$LABEL.running" ] && [ ! -f "$RUN_DST/log/$LABEL.exit" ]; then
    echo "replay: la fase risulta ancora in corso: worktree lasciato. Quando e' finita: bash $(q "$HERE/replay.sh") --remove $(q "$CREATED")" >&2
    return 0
  fi
  mkdir -p "$OUT" && cp "$RUN_DST"/log/"$LABEL".* "$OUT"/ 2>/dev/null
  if ! ours "$CREATED"; then
    echo "replay: $CREATED non supera la verifica: NON rimosso" >&2
  elif forget_mirror "$CREATED" && ! unlink_deps "$CREATED"; then   # links first: the removal must never follow them
    echo "replay: collegamenti ancora presenti in $CREATED: worktree NON rimosso (seguirebbe le dipendenze del tree principale)" >&2
  else
    git -C "$MAIN" worktree remove --force "$CREATED" || echo "replay: rimozione del worktree fallita: $CREATED" >&2
  fi
}
trap cleanup EXIT

# 1. worktree at the base, marker in its git dir
[ $DRY -eq 1 ] || CREATED=$WT   # the trap removes it only if it passes the check
act "git -C $(q "$MAIN") worktree add --detach $(q "$WT") $BASE"
act "printf 'fic-replay\npath=%s\ncreated=%s\n' $(q "$WT") $STAMP > \"\$(git -C $(q "$WT") rev-parse --absolute-git-dir)/fic-replay\""
# 1b. gates runnable as in the original: relative .git (WSL git), linked dependencies, nuxi tsconfig
act "fic_relgit $(q "$WT")"
while IFS= read -r p; do
  [ -n "$p" ] && act "link_dep $(q "$MAIN/$p") $(q "$WT/$p")"
done < <(dep_links "$MAIN")
NUXT=modules/app/apps/admin/.nuxt
[ -f "$MAIN/$NUXT/tsconfig.json" ] &&
  act "mkdir -p $(q "$WT/$NUXT") && cp $(q "$MAIN/$NUXT/tsconfig.json") $(q "$WT/$NUXT/") && { cp $(q "$MAIN/$NUXT")/*.d.ts $(q "$WT/$NUXT/") 2>/dev/null; true; }"
# 2. code at the phase state, as uncommitted changes
[ -n "$STATE" ] && act "git -C $(q "$WT") read-tree -u --reset $STATE && git -C $(q "$WT") read-tree HEAD"
# 2b. dependencies equal for git (checked above): the normalized fingerprint matches that of the main
# tree, i.e. the worktree's WSL copy will be seeded (fic-mirror.sh). Not with --non-confrontabile.
[ -z "$NONCONF" ] && act "deps_fp_check $(q "$MAIN") $(q "$WT")"
# 3. harness: NOT copied into the worktree (pk04a-1): the phase runs with scripts/run-phase.sh of the --harness plugin (step 6)
# 4. spec and run directory up to the phase, excluded
act "mkdir -p $(q "$RUN_DST/log") $(q "$RUN_DST/prompts") && cp $(q "$SPEC_SRC") $(q "$AIW/")"
for l in $EARLIER; do
  act "cp $(q "$RUN_SRC/log")/$l.* $(q "$RUN_DST/log/")"
  [ -f "$RUN_SRC/prompts/$l.md" ] && act "cp $(q "$RUN_SRC/prompts/$l.md") $(q "$RUN_DST/prompts/")"
done
[ -f "$RUN_SRC/input.md" ] && act "cp $(q "$RUN_SRC/input.md") $(q "$RUN_DST/")"
if [ $code_before -eq 1 ]; then
  for f in base.txt do-not-touch.txt mixed.txt; do
    [ -f "$RUN_SRC/$f" ] && act "cp $(q "$RUN_SRC/$f") $(q "$RUN_DST/")"
  done
  act ": > $(q "$RUN_DST/touched.txt")"
  for l in $EARLIER; do
    [ -f "$RUN_SRC/log/$l.pre-tree" ] && [ -f "$RUN_SRC/log/$l.post-tree" ] &&
      act "git -C $(q "$MAIN") -c core.quotePath=false diff --name-only --no-renames $(tr -d '\r\n ' < "$RUN_SRC/log/$l.pre-tree") $(tr -d '\r\n ' < "$RUN_SRC/log/$l.post-tree") >> $(q "$RUN_DST/touched.txt")"
  done
  act "sort -u -o $(q "$RUN_DST/touched.txt") $(q "$RUN_DST/touched.txt")"
fi
# the plugin's skill (maat: prefix), not a .claude/skills/full-implementation-cycle of the cycle's commit
if head -1 "$PROMPT_SRC" | grep -q -- '--no-dev'; then
  act "sed '1s|^/\\(maat:\\)\\{0,1\\}full-implementation-cycle |/maat:full-implementation-cycle |' $(q "$PROMPT_SRC") > $(q "$RUN_DST/prompts/$LABEL.md")"
else
  act "sed '1s|^/\\(maat:\\)\\{0,1\\}full-implementation-cycle \\(--worker=[a-z]* [^ ]*\\)|/maat:full-implementation-cycle \\2 --no-dev|' $(q "$PROMPT_SRC") > $(q "$RUN_DST/prompts/$LABEL.md")"
fi
# 5. inject
for n in ${INJECT[@]+"${INJECT[@]}"}; do act "bash $(q "$HERE/inject/$n.sh") $(q "$WT")"; done
# 6. the phase: run-phase.sh of the --harness plugin, cwd in the worktree, the plugin ALWAYS loaded in the sub-session
# (MAAT_PLUGIN_DIR → --plugin-dir: whether the worktree enables it does not matter), with the main tree's lock
act_rc "(cd $(q "$WT") && MAAT_PLUGIN_DIR=$(q "$HARNESS") FIC_LOCK=$(q "$LOCK") bash $(q "$HARNESS/scripts/run-phase.sh") $REL_RUN $LABEL $REL_RUN/prompts/$LABEL.md)"
code=$?
# 7. logs to --out, measurement
act_rc "mkdir -p $(q "$OUT") && cp $(q "$RUN_DST/log")/$LABEL.* $(q "$OUT/") && { cp $(q "$RUN_DST/touched.txt") $(q "$OUT/") 2>/dev/null; cp $(q "$AIW/spec-$NAME.md") $(q "$OUT/spec-dopo.md"); true; }"
OUT_JSONL=$(winpath "$OUT/$LABEL.jsonl")
MARK=""
[ -n "$NONCONF" ] && MARK="printf 'NON CONFRONTABILE — %s\n' $(q "$NONCONF") | tee $(q "$OUT/NON-CONFRONTABILE.txt"); "
[ -n "$FPWARN" ] && MARK="${MARK}printf 'AVVISO — %s\n' $(q "$FPWARN"); "
act_rc "{ $MARK$(q "$FIC_PY") $(q "$(winpath "$CR")") $(q "$OUT_JSONL"); } | tee $(q "$OUT/report.txt"); $(q "$FIC_PY") $(q "$(winpath "$CR")") --json $(q "$OUT_JSONL") > $(q "$OUT/report.json")"
# 8. removal, only if the path passes the check and after removing the links
if [ $DRY -eq 1 ]; then
  echo "+ forget_mirror $(q "$WT")"
  echo "+ unlink_deps $(q "$WT")"
  echo "+ (verifica: nome fic-replay-*, marcatore con il suo percorso, elencato da git worktree list; nessun collegamento rimasto) git -C $(q "$MAIN") worktree remove --force $(q "$WT")"
  exit 0
fi
cleanup
echo "replay: fase $LABEL finita con uscita $code · log e report in $OUT$([ -n "$NONCONF" ] && echo ' · NON CONFRONTABILE')$([ -n "$FPWARN" ] && echo " · AVVISO: $FPWARN")"
exit $code
