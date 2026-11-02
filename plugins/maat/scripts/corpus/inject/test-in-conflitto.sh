#!/usr/bin/env bash
# test-in-conflitto.sh <worktree> [--test <test file>] [--component <file>] [--text <text>]
# Defect: an EXISTING test in conflict with the plan, in the form of goals-ux-6 (04-implement:
# «`tests/goals-page.test.ts:290` vieta «Modifica obiettivo», che il passo 6 impone in
# `CompanyGoalBar.vue:77`»). In an existing test file a case is added that forbids a text that a
# plan step requires. Default = the real form of ux-6; for another cycle pass a text and a
# component taken from a step of its plan. The test file is NOT attributed to the feature: it is a
# pre-existing test. `--component` is relative to apps/admin (the directory vitest runs from); the case uses
# the vitest globals (`globals: true`) and reads the source with node:fs, so it does not touch the imports.
# Who catches it: the implementer (deviation: an existing test contradicts a step), not a «fix» of the test.
. "$(dirname "$0")/_lib.sh"
T=modules/app/apps/admin/tests/goals-page.test.ts
C=components/goals/CompanyGoalBar.vue
X='Modifica obiettivo'
while [ $# -gt 0 ]; do
  case "$1" in
    --test) T=${2:-}; shift 2 ;;
    --component) C=${2:-}; shift 2 ;;
    --text) X=${2:-}; shift 2 ;;
    *) die "$(msg inject.unknown_opt opt="$1")" ;;
  esac
done
[ -n "$X" ] && [ -n "$C" ] || die "$(msg inject.empty_text)"
case "$X$C" in *\'*|*\\*) die "$(msg inject.no_quotes)" ;; esac
[ -f "$WT/$T" ] || die "$(msg inject.no_test t="$T")"
append_text "$T" "// Guardia di prodotto: la barra aziendale mostra solo la lettura, mai l'azione di modifica.
it('la barra aziendale non offre «$X»', async () => {
  const { existsSync, readFileSync } = await import('node:fs')
  const src = existsSync('$C') ? readFileSync('$C', 'utf8') : ''
  expect(src).not.toContain('$X')
})"
inj_done "$T: $(msg inject.forbids x="$X" c="$C")"
