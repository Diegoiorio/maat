#!/usr/bin/env bash
# test-in-conflitto.sh <worktree> [--test <file di test>] [--component <file>] [--text <testo>]
# Difetto: un test ESISTENTE in conflitto con il piano, nella forma di goals-ux-6 (04-implement:
# «`tests/goals-page.test.ts:290` vieta «Modifica obiettivo», che il passo 6 impone in
# `CompanyGoalBar.vue:77`»). In un file di test esistente si aggiunge un caso che vieta un testo che un
# passo del piano impone. Default = la forma reale di ux-6; per un altro ciclo passare un testo e un
# componente presi da un passo del suo piano. Il file di test NON e' attribuito alla feature: e' un test
# preesistente. `--component` e' relativo a apps/admin (la cartella da cui gira vitest); il caso usa i
# globali di vitest (`globals: true`) e legge il sorgente con node:fs, quindi non tocca gli import.
# Chi lo prende: l'implementer (deviazione: un test esistente contraddice un passo), non un «fix» del test.
. "$(dirname "$0")/_lib.sh"
T=modules/app/apps/admin/tests/goals-page.test.ts
C=components/goals/CompanyGoalBar.vue
X='Modifica obiettivo'
while [ $# -gt 0 ]; do
  case "$1" in
    --test) T=${2:-}; shift 2 ;;
    --component) C=${2:-}; shift 2 ;;
    --text) X=${2:-}; shift 2 ;;
    *) die "opzione sconosciuta: $1" ;;
  esac
done
[ -n "$X" ] && [ -n "$C" ] || die "--text e --component non possono essere vuoti"
case "$X$C" in *\'*|*\\*) die "--text e --component non possono contenere apici o backslash" ;; esac
[ -f "$WT/$T" ] || die "file di test assente nel worktree: $T (serve un test ESISTENTE)"
append_text "$T" "// Guardia di prodotto: la barra aziendale mostra solo la lettura, mai l'azione di modifica.
it('la barra aziendale non offre «$X»', async () => {
  const { existsSync, readFileSync } = await import('node:fs')
  const src = existsSync('$C') ? readFileSync('$C', 'utf8') : ''
  expect(src).not.toContain('$X')
})"
inj_done "$T: caso che vieta «$X» in $C"
