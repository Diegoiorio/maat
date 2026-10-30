#!/usr/bin/env bash
# contraddizione-piano.sh <worktree>
# Defect: a contradiction in the plan, in the form of goals-ux-1 (03-implement: «T1 vuole 999,4 ⇒
# «999,4%», mentre RF8, D3, il passo 4 … vogliono il moltiplicatore oltre 999»): a case of the test
# plan that contradicts a decision. In the spec copied into the worktree, inside the plan, we add:
# a decision (the threshold of the compact form is INCLUSIVE, as utils/goals.ts does today) right before
# the test plan heading, and a T-FIC case that wants the opposite right after the heading.
# Who catches it: the implementer (it must stop with a deviation, not «fix» the plan in the code)
# or the plan review.
. "$(dirname "$0")/_lib.sh"
[ $# -eq 0 ] || die "nessuna opzione prevista"
[ -f "$SPEC" ] || die "spec assente nel worktree: $SPEC"
start=$(grep -n '^## Piano di implementazione' "$SPEC" | head -1 | cut -d: -f1)
[ -n "$start" ] || die "la spec non ha '## Piano di implementazione'"
grep -n '^###* .*Piano di test' "$SPEC" | awk -F: -v s="$start" '$1 > s' | grep -q . ||
  die "nessun titolo 'Piano di test' dentro il piano della spec"
insert_line "$SPEC" '^###* .*Piano di test' before "
**D-FIC · soglia della forma compatta (decisione del PO).** Un importo con valore assoluto **pari** a
\`COMPACT_THRESHOLD_CENTS\` resta in forma piena (\`formatCentsWithSymbol\`): la soglia e' inclusa, come fa oggi
\`utils/goals.ts\` (\`Math.abs(cents) <= COMPACT_THRESHOLD_CENTS\`). Nessun passo del piano la cambia.
" "$start"
insert_line "$SPEC" '^###* .*Piano di test' after "
- **T-FIC** (\`tests/goals-utils.test.ts\`) — un importo pari a \`COMPACT_THRESHOLD_CENTS\` e' reso in forma
  **compatta**. Rosso se: il valore alla soglia esatta esce in forma piena." "$start"
inj_done "$(basename "$SPEC"): decisione D-FIC e caso T-FIC in contraddizione"
