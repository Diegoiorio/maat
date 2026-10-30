#!/usr/bin/env bash
# lint-vue.sh <worktree> [--file <file .vue>]
# Difetto: un errore di lint in un `.vue` — un confronto con `==`, che `eqeqeq` (livello error in
# apps/admin/.eslintrc.cjs, quindi visibile anche con --quiet) segnala. Bersaglio: il primo `.vue` di
# apps/admin in touched.txt, altrimenti components/goals/SummaryCard.vue (con <script setup> a tutte le
# basi del corpus). Riga inserita subito dopo l'apertura di <script setup>.
# Chi lo prende: il gate di lint (livello full) sul perimetro della feature.
. "$(dirname "$0")/_lib.sh"
F=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file) F=${2:-}; shift 2 ;;
    *) die "opzione sconosciuta: $1" ;;
  esac
done
[ -n "$F" ] || F=$(pick '^modules/app/apps/admin/.*\.vue$' modules/app/apps/admin/components/goals/SummaryCard.vue) || exit
case "$F" in *.vue) ;; *) die "serve un file .vue: $F" ;; esac
[ -f "$WT/$F" ] || die "file assente nel worktree: $F"
insert_line "$WT/$F" '^<script setup' after 'const sameGoalValue = (a: unknown, b: unknown): boolean => a == b'
mark_touched "$F"
inj_done "$F: confronto con == dopo <script setup> (eqeqeq)"
