#!/usr/bin/env bash
# file-lasciato-mutato.sh <worktree> [--file <path> --from <testo> --to <testo>]
# Difetto: una controprova morta a meta' che ha lasciato il file mutato. Come fa il worker review
# (SKILL.md, «Counterproofs», passi 2-3): copia del file in <run-dir>/counterproof/<path>, sidecar
# <path>.meta con path, base, hash della copia e hash del file mutato; poi la mutazione nominata nel file.
# Default: la stessa mutazione di confine di mutazione-non-coperta.sh (utils/goals.ts, `<=` → `<`).
# Il file NON e' attribuito alla feature: e' lo scarto di una controprova, non codice.
# Chi lo prende: il worker review (passo 1: ripristino delle copie rimaste, solo se l'hash combacia).
. "$(dirname "$0")/_lib.sh"
F=modules/app/apps/admin/utils/goals.ts
FROM='Math.abs(cents) <= COMPACT_THRESHOLD_CENTS'
TO='Math.abs(cents) < COMPACT_THRESHOLD_CENTS'
while [ $# -gt 0 ]; do
  case "$1" in
    --file) F=${2:-}; shift 2 ;;
    --from) FROM=${2:-}; shift 2 ;;
    --to) TO=${2:-}; shift 2 ;;
    *) die "opzione sconosciuta: $1" ;;
  esac
done
[ -f "$WT/$F" ] || die "file assente nel worktree: $F"
base=$(tr -d '\r\n ' 2>/dev/null < "$RUN/base.txt")
[ -n "$base" ] || base=$(git -C "$WT" rev-parse HEAD)
CP="$RUN/counterproof/$F"
[ -e "$CP" ] && die "copia di controprova gia' presente: $CP"
mkdir -p "$(dirname "$CP")" && cp "$WT/$F" "$CP" || die "copia non riuscita: $CP"
copy_sha=$(sha256sum < "$CP" | cut -c1-64)
replace_once "$F" "$FROM" "$TO"
mut_sha=$(sha256sum < "$WT/$F" | cut -c1-64)
printf 'path: %s\nbase: %s\ncopy_sha256: %s\nreverted_sha256: %s\nmutation: %s -> %s\n' \
  "$F" "$base" "$copy_sha" "$mut_sha" "$FROM" "$TO" > "$CP.meta"
inj_done "$F mutato; copia e sidecar in counterproof/"
