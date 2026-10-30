#!/usr/bin/env bash
# mutazione-non-coperta.sh <worktree> [--file <path> --from <testo> --to <testo>]
# Difetto: una mutazione di comportamento che nessun test vede (mutante sopravvissuto). Default: il
# confine della forma compatta degli importi in utils/goals.ts, `<=` → `<` (presente, identico e unico
# a tutte le basi del corpus): cambia solo il valore esattamente alla soglia. Attribuita alla feature
# (touched.txt) se una fase di codice precede quella rigiocata.
# Chi lo prende: la review (una modifica senza test che la copra) e le controprove per mutazione.
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
[ -n "$F" ] && [ -n "$FROM" ] && [ "$FROM" != "$TO" ] || die "--file/--from/--to non validi"
replace_once "$F" "$FROM" "$TO"
mark_touched "$F"
inj_done "$F: «$FROM» → «$TO»"
