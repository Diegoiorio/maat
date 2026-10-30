#!/usr/bin/env bash
# harness-merge.sh — il harness sviluppato in un worktree entra nel tree principale SOLO quando nessun ciclo
# gira (harness-pt03; incidente ux-1..4: harness modificato sotto un ciclo). NON fa il merge: controlla e
# stampa il comando che l'utente esegue. Nessuna scrittura di git (solo rev-parse, symbolic-ref,
# merge-base --is-ancestor, rev-list, log).
#
#   bash script/fic/harness-merge.sh <worktree>
#
# Il tree principale e' quello del worktree (la cartella di git-common-dir). In quest'ordine:
#   1. VERDETTO — rifiuta (exit 4, con l'elenco) se `run-phase.sh --lock-status` non dice `libero` (una fase di
#      codice gira, o il lock non si calcola) o se esiste un <cartelle.lavoro>/spec-*.run/log/*.running senza
#      il suo .exit (fase in corso o uccisa: per ognuna il comando di recupero). Via libera: stampa
#      `git merge --ff-only <branch del worktree>`, o il cherry-pick dei commit se il tree principale non e' un
#      antenato del worktree;
#   2. ELENCO dei cicli non chiusi, informativo (non blocca: fra due fasi, il lancio successivo di un ciclo con
#      harness.fp si ferma da se' con lo STOP per impronta). Si legge dalle RIGHE DI STATO della spec, senza
#      controllare il codice: chiuso = "Review status: APPROVED" + "Feature status: IMPLEMENTED" nella sezione
#      di review. Misurato: cycle-state.sh completo su 18 run dir costava 24 minuti (review-surface.sh sul codice).
#      FIC_MERGE_NO_LIST=1 lo salta; FIC_MERGE_LIST_MAX (secondi, default 20) lo tronca, dichiarato.
# Uscita: 0 via libera, comando stampato · 4 rifiutato · 2 uso (worktree assente o non collegato).
# Variabili (per i test): HARNESS_MERGE_HARNESS radice del plugin che fornisce scripts/run-phase.sh (default:
# MAAT_ROOT) · FIC_LOCK passa a run-phase.sh.
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
# la cartella di lavoro del tree principale (cartelle.lavoro della sua maat.json): il risolutore lanciato da li'
mp=$( (cd "$MAIN" && env -u FIC_REPO bash "$HERE/lib/maat-paths.sh") 2>/dev/null | tr -d '\r')
mw=$(printf '%s\n' "$mp" | sed -n 's/^MAAT_WORK=//p') mr=$(printf '%s\n' "$mp" | sed -n 's/^PROJECT_ROOT=//p')
lav=.claude/.ai-workflow; [ -n "$mw" ] && [ -n "$mr" ] && lav=${mw#"$mr"/}
AIW=$MAIN/$lav

# --- 1. verdetto ---
refuse=0
# lock delle fasi di codice: quello del tree principale (dentro git-common-dir)
lock=$(env -u FIC_PHASE FIC_LOCK="${FIC_LOCK:-$gcd/full-implementation-cycle.lock}" bash "$FIC/run-phase.sh" --lock-status 2>&1); lrc=$?
echo "Lock delle fasi di codice: $lock"
case "$lock" in libero*) [ $lrc -eq 0 ] || refuse=1 ;; *) refuse=1 ;; esac

# fasi con .running senza .exit (in corso, o uccise: in entrambi i casi un ciclo e' a meta')
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
  # il comando, stampato e non eseguito
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
      # shellcheck disable=SC2086  # un argomento per commit
      git -C "$MAIN" log --no-walk=unsorted --format='    %h %s' $commits 2>/dev/null
    fi
  fi
fi

# --- 2. elenco dei cicli non chiusi (informativo), dalle righe di stato della spec ---
spec_state() { # <spec> → "<Review status>\t<Feature status>" della sezione di review, fuori dai recinti
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
