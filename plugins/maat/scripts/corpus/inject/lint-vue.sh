#!/usr/bin/env bash
# lint-vue.sh <worktree> [--file <.vue file>]
# Defect: a lint error in a `.vue` — a comparison with `==`, which `eqeqeq` (error level in
# apps/admin/.eslintrc.cjs, hence visible even with --quiet) reports. Target: the first `.vue` of
# apps/admin in touched.txt, otherwise components/goals/SummaryCard.vue (with <script setup> at all the
# corpus bases). Line inserted right after the opening of <script setup>.
# Who catches it: the lint gate (full level) on the feature perimeter.
. "$(dirname "$0")/_lib.sh"
F=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file) F=${2:-}; shift 2 ;;
    *) die "$(msg inject.unknown_opt opt="$1")" ;;
  esac
done
[ -n "$F" ] || F=$(pick '^modules/app/apps/admin/.*\.vue$' modules/app/apps/admin/components/goals/SummaryCard.vue) || exit
case "$F" in *.vue) ;; *) die "$(msg inject.need_vue f="$F")" ;; esac
[ -f "$WT/$F" ] || die "$(msg inject.no_file f="$F")"
insert_line "$WT/$F" '^<script setup' after 'const sameGoalValue = (a: unknown, b: unknown): boolean => a == b'
mark_touched "$F"
inj_done "$F: $(msg inject.eqeqeq)"
