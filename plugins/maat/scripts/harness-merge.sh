#!/usr/bin/env bash
# harness-merge.sh — a harness developed in a worktree enters the main tree ONLY when no cycle is
# running (harness-pt03; incident ux-1..4: harness modified under a running cycle). It does NOT merge: it checks and
# prints the command for the user to run. No git writes (only rev-parse, symbolic-ref,
# merge-base --is-ancestor, rev-list, log).
#
#   bash script/fic/harness-merge.sh <worktree>
#
# The main tree is the worktree's own (the folder of git-common-dir). In this order:
#   1. VERDICT — refuses (exit 4, with the list) if `run-phase.sh --lock-status` does not say `libero` (a code
#      phase is running, or the lock cannot be computed) or if a <cartelle.lavoro>/spec-*.run/log/*.running exists
#      without its .exit (phase running or killed: a recovery command for each). Clear to go: prints
#      `git merge --ff-only <worktree branch>`, or the cherry-pick of the commits if the main tree is not an
#      ancestor of the worktree;
#   2. LIST of the unclosed cycles, informational (does not block: between two phases, the next launch of a cycle
#      with harness.fp stops by itself with the fingerprint STOP). Read from the spec's STATUS LINES, without
#      checking the code: closed = "Review status: APPROVED" + "Feature status: IMPLEMENTED" in the review
#      section. Measured: a full cycle-state.sh over 18 run dirs took 24 minutes (review-surface.sh on the code).
#      FIC_MERGE_NO_LIST=1 skips it; FIC_MERGE_LIST_MAX (seconds, default 20) truncates it, declared.
# Exit: 0 clear to go, command printed · 4 refused · 2 usage (worktree missing or not linked).
# Variables (for tests): HARNESS_MERGE_HARNESS root of the plugin providing scripts/run-phase.sh (default:
# MAAT_ROOT) · FIC_LOCK is passed to run-phase.sh.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_ROOT (plugin)
HROOT=${HARNESS_MERGE_HARNESS:-$MAAT_ROOT}
FIC=$HROOT/scripts
unset MSYS_NO_PATHCONV

[ $# -eq 1 ] && [ -d "$1" ] || { echo "uso: $0 <worktree>" >&2; exit 2; }
WT=$(cd "$1" && pwd)
gd=$(git -C "$WT" rev-parse --path-format=absolute --git-dir 2>/dev/null) &&
  gcd=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) &&
  [ -n "$gd" ] && [ -n "$gcd" ] || { echo "harness-merge: $WT non e' un repository git" >&2; exit 2; }
[ "$gd" != "$gcd" ] || { echo "harness-merge: $WT e' il tree principale, non un worktree collegato" >&2; exit 2; }
MAIN=$(cd "$gcd/.." && pwd)
branch=$(git -C "$WT" symbolic-ref --short -q HEAD) || branch=""
head=$(git -C "$WT" rev-parse HEAD) || { echo "harness-merge: HEAD del worktree illeggibile" >&2; exit 2; }
echo "harness-merge: tree principale $MAIN · worktree $WT (${branch:-HEAD staccato} @ ${head:0:12})"
# the main tree's work folder (cartelle.lavoro of its maat.json): the resolver launched from there
mp=$( (cd "$MAIN" && env -u FIC_REPO bash "$HERE/lib/maat-paths.sh") 2>/dev/null | tr -d '\r')
mw=$(printf '%s\n' "$mp" | sed -n 's/^MAAT_WORK=//p') mr=$(printf '%s\n' "$mp" | sed -n 's/^PROJECT_ROOT=//p')
lav=.claude/.ai-workflow; [ -n "$mw" ] && [ -n "$mr" ] && lav=${mw#"$mr"/}
AIW=$MAIN/$lav

# --- 1. verdict ---
refuse=0
# lock of the code phases: the main tree's one (inside git-common-dir)
lock=$(env -u FIC_PHASE FIC_LOCK="${FIC_LOCK:-$gcd/full-implementation-cycle.lock}" bash "$FIC/run-phase.sh" --lock-status 2>&1); lrc=$?
echo "Lock delle fasi di codice: $lock"
case "$lock" in libero*) [ $lrc -eq 0 ] || refuse=1 ;; *) refuse=1 ;; esac

# phases with .running and no .exit (running, or killed: either way a cycle is half done)
running=()
for f in "$AIW"/spec-*.run/log/*.running; do
  [ -f "$f" ] && [ ! -f "${f%.running}.exit" ] && running+=("$f")
done
if [ ${#running[@]} -gt 0 ]; then
  refuse=1
  echo "Fasi in corso o interrotte (.running senza .exit):"
  for f in "${running[@]}"; do
    echo "  ${f#"$MAIN"/} (dal $(head -1 "$f" 2>/dev/null | tr -d '\r'))"
    echo "    recupero, SOLO se nessuna sessione la sta eseguendo (processo morto, log fermo): echo 143 > \"${f%.running}.exit\""
  done
else
  echo "Fasi in corso o interrotte (.running senza .exit): nessuna"
fi

if [ $refuse -eq 1 ]; then
  echo "harness-merge: RIFIUTATO — un ciclo e' in corso o interrotto: rilancia quando il lock e' libero e nessuna fase e' a meta'"
else
  # the command, printed and not run
  ref=${branch:-$head}
  echo "harness-merge: via libera. Esegui tu, nel tree principale:"
  if git -C "$MAIN" merge-base --is-ancestor HEAD "$head" 2>/dev/null; then
    echo "  cd \"$MAIN\" && git merge --ff-only $ref"
  else
    commits=$(git -C "$MAIN" rev-list --reverse --no-merges "HEAD..$head" 2>/dev/null)
    if [ -z "$commits" ]; then
      echo "  niente da portare: nessun commit di $ref manca al tree principale"
    else
      echo "  (il tree principale non e' un antenato di $ref: niente fast-forward) — cherry-pick dei commit:"
      echo "  cd \"$MAIN\" && git cherry-pick $(printf '%s\n' "$commits" | tr '\n' ' ')"
      # shellcheck disable=SC2086  # one argument per commit
      git -C "$MAIN" log --no-walk=unsorted --format='    %h %s' $commits 2>/dev/null
    fi
  fi
fi

# --- 2. list of the unclosed cycles (informational), from the spec's status lines ---
spec_state() { # <spec> → "<Review status>\t<Feature status>" of the review section, outside code fences
  tr -d '\r' < "$1" | awk '
    /^[ \t]*(```|~~~)/ { f = !f; next }
    f { next }
    /^## Review implementazione/ { r = 1 }
    r && rs == "" && sub(/^Review status:[ \t]*/, "") { rs = $0 }
    r && fs == "" && sub(/^Feature status:[ \t]*/, "") { fs = $0 }
    END { printf "%s\t%s\n", rs, fs }'
}
if [ "${FIC_MERGE_NO_LIST:-0}" = 1 ]; then
  echo "Cicli non chiusi: elenco saltato (FIC_MERGE_NO_LIST=1)"
else
  max=${FIC_MERGE_LIST_MAX:-20} t0=$SECONDS open=() cut=0
  for d in "$AIW"/spec-*.run; do
    [ -d "$d" ] && [ -f "${d%.run}.md" ] || continue
    [ $((SECONDS - t0)) -ge "$max" ] && { cut=1; break; }
    IFS=$'\t' read -r rs fs < <(spec_state "${d%.run}.md")
    case "$rs/$fs" in APPROVED*/IMPLEMENTED*) continue ;; esac
    if [ -z "$rs$fs" ]; then open+=("$(basename "${d%.run}"): nessuna review")
    else open+=("$(basename "${d%.run}"): Review status ${rs:-(assente)} · Feature status ${fs:-(assente)}"); fi
  done
  if [ ${#open[@]} -gt 0 ]; then
    echo "Cicli non chiusi (righe di stato della spec; ripartiranno col harness nuovo):"; printf '  %s\n' "${open[@]}"
  else
    echo "Cicli non chiusi: nessuno"
  fi
  [ $cut -eq 1 ] && echo "  (elenco troncato dopo ${max}s: FIC_MERGE_LIST_MAX)"
fi

[ $refuse -eq 1 ] && exit 4
exit 0
