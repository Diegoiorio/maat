#!/usr/bin/env bash
# ui-transitiva.sh <worktree>
# Difetto: una modifica TRANSITIVA in modules/app/packages/ui — il pacchetto `ui` che apps/admin importa
# (`import { Action } from "ui"`, decine di componenti). Si cambia la dimensione di default del bottone
# `Action` (packages/ui/src/button/action.vue: prop `size`, "small" → "x-small"; unica a tutte le basi
# del corpus): nessun file di apps/admin cambia, ma cambia cio' che rende. Attribuita alla feature
# (touched.txt) se una fase di codice precede quella rigiocata.
# Chi lo prende: il riuso dell'evidenza (pt04), che deve invalidare i gate di apps/admin quando cambia
# una dipendenza, e la review che deve vedere il file fuori da apps/admin.
. "$(dirname "$0")/_lib.sh"
[ $# -eq 0 ] || die "nessuna opzione prevista"
F=modules/app/packages/ui/src/button/action.vue
replace_once "$F" 'default: "small",' 'default: "x-small",'
mark_touched "$F"
inj_done "$F: size di default small → x-small"
