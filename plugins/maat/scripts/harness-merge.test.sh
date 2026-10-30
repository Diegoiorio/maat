#!/usr/bin/env bash
# harness-merge.test.sh — tests of harness-merge.sh on a temporary repository with a linked worktree.
#   bash script/fic/harness-merge.test.sh
#   HM=/path/variant.sh bash script/fic/harness-merge.test.sh   # counterproof on a mutation
# The real lock is not touched: FIC_LOCK points to a temporary directory (except the case that tests the
# default lock, which lives in the temporary repository's .git).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
HM=${HM:-$HERE/harness-merge.sh}
HARNESS_MERGE_HARNESS=$(cd "$HERE/.." && pwd); export HARNESS_MERGE_HARNESS   # plugin root
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export FIC_LOCK=$T/lock
unset FIC_PHASE FIC_REPO
n=0 fail=0
check() { n=$((n + 1)); if eval "$2"; then :; else fail=$((fail + 1)); echo "FAIL: $1"; sed 's/^/    /' "$T/out" 2>/dev/null; fi; }
hm() { bash "$HM" "$@" > "$T/out" 2>&1; echo $? > "$T/rc"; }
rc() { cat "$T/rc"; }
gitstate() { for r in "$M" "$WT"; do git -C "$r" rev-parse HEAD; git -C "$r" status --porcelain; git -C "$r" branch --list; done; }

M=$T/main WT=$T/wt
mkdir -p "$M/.claude/.ai-workflow"
(cd "$M" && git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false &&
  echo uno > a.txt && printf 'spec-*\n' > .claude/.ai-workflow/.gitignore && git add -A && git commit -qm init)
(cd "$M" && git worktree add -q -b harness/fic-v2 "$WT") > /dev/null 2>&1
(cd "$WT" && echo due > b.txt && git add -A && git commit -qm harness)
AW=$M/.claude/.ai-workflow

# 1. all clear -> 0 and the command printed, not run
s0=$(gitstate)
hm "$WT"
check "tutto libero -> 0 e comando stampato" '[ "$(rc)" = 0 ] && grep -q "git merge --ff-only harness/fic-v2" "$T/out" && grep -q "Lock delle fasi di codice: libero" "$T/out"'
check "  nessuna scrittura di git (HEAD, status, branch dei due tree)" '[ "$(gitstate)" = "$s0" ]'

# 2. lock held (live PID: this shell) -> 4, no command
mkdir -p "$FIC_LOCK"; printf 'run=x\nlabel=03-review\nsince=x\npid=%s\n' "$$" > "$FIC_LOCK/owner"
hm "$WT"
check "lock occupato -> 4, senza comando" '[ "$(rc)" = 4 ] && grep -q "occupato" "$T/out" && grep -q RIFIUTATO "$T/out" && ! grep -q "git merge" "$T/out"'
rm -rf "$FIC_LOCK"
# the default lock is the main tree's, not the worktree's
mkdir -p "$M/.git/full-implementation-cycle.lock"; printf 'run=x\nlabel=05-fix\nsince=x\npid=%s\n' "$$" > "$M/.git/full-implementation-cycle.lock/owner"
( unset FIC_LOCK; hm "$WT" )
check "  senza FIC_LOCK: lock del tree principale occupato -> 4" '[ "$(rc)" = 4 ] && grep -q "label=05-fix" "$T/out"'
rm -rf "$M/.git/full-implementation-cycle.lock"

# 3. .running without .exit -> 4 with the list; with .exit it does not refuse
mkdir -p "$AW/spec-a.run/log"; date > "$AW/spec-a.run/log/01-plan.running"; printf '# A\n' > "$AW/spec-a.md"
hm "$WT"
check ".running senza .exit -> 4 con l'elenco" '[ "$(rc)" = 4 ] && grep -q "spec-a.run/log/01-plan.running" "$T/out" && ! grep -q "git merge" "$T/out"'
check "  con il comando di recupero" 'grep -qF "echo 143 > \"$AW/spec-a.run/log/01-plan.exit\"" "$T/out"'
echo 0 > "$AW/spec-a.run/log/01-plan.exit"
# two more cycles: one closed (APPROVED + IMPLEMENTED), one open (NEEDS_CHANGES)
mkdir -p "$AW/spec-b.run" "$AW/spec-c.run"
printf '# B\n## Review implementazione\nReview status: APPROVED\nFeature status: IMPLEMENTED\n' > "$AW/spec-b.md"
printf '# C\n## Review implementazione\n```\nReview status: APPROVED\n```\nReview status: NEEDS_CHANGES\nFeature status: PLANNED\n' > "$AW/spec-c.md"
hm "$WT"
check "  con il suo .exit -> via libera" '[ "$(rc)" = 0 ] && grep -q "git merge --ff-only" "$T/out"'
check "cicli non chiusi dalle righe di stato, senza rifiuto" 'grep -q "spec-a: nessuna review" "$T/out" && grep -q "spec-c: Review status NEEDS_CHANGES · Feature status PLANNED" "$T/out" && ! grep -q "spec-b:" "$T/out"'
check "  verdetto e comando PRIMA dell'elenco" '[ "$(grep -n "git merge --ff-only" "$T/out" | cut -d: -f1)" -lt "$(grep -n "^Cicli non chiusi" "$T/out" | cut -d: -f1)" ]'
FIC_MERGE_NO_LIST=1 hm "$WT"
check "FIC_MERGE_NO_LIST=1 -> elenco saltato, verdetto invariato" '[ "$(rc)" = 0 ] && grep -q "elenco saltato" "$T/out" && ! grep -q "spec-a:" "$T/out" && grep -q "git merge --ff-only" "$T/out"'
FIC_MERGE_LIST_MAX=0 hm "$WT"
check "FIC_MERGE_LIST_MAX=0 -> elenco troncato, dichiarato" '[ "$(rc)" = 0 ] && grep -q "elenco troncato" "$T/out"'
# cost: the list goes through neither cycle-state.sh nor review-surface.sh (24 min measured on the real tree)
H=$T/harness; mkdir -p "$H"; cp -r "$HARNESS_MERGE_HARNESS/scripts" "$HARNESS_MERGE_HARNESS/.claude-plugin" "$H/"
for s in cycle-state.sh review-surface.sh; do
  printf '#!/usr/bin/env bash\necho chiamato >> "%s"\n' "$T/costoso" > "$H/scripts/$s"
done
HARNESS_MERGE_HARNESS=$H hm "$WT"
check "costo: ne' cycle-state.sh ne' review-surface.sh invocati" '[ "$(rc)" = 0 ] && [ ! -e "$T/costoso" ] && grep -q "spec-c:" "$T/out"'
code0=$(grep -vE '^[[:space:]]*(#|echo[[:space:]])' "$HM")
check "  e il testo dello script non li nomina fuori dai commenti" '! printf "%s\n" "$code0" | grep -Eq "cycle-state\.sh|review-surface\.sh"'

# 4. main tree moved ahead -> no fast-forward: cherry-pick of the commit
(cd "$M" && echo tre > c.txt && git add c.txt && git commit -qm main-avanti)
s1=$(gitstate)
hm "$WT"
check "non fast-forward -> cherry-pick del commit del worktree" '[ "$(rc)" = 0 ] && grep -q "git cherry-pick $(git -C "$WT" rev-parse HEAD)" "$T/out" && ! grep -q "merge --ff-only" "$T/out"'
check "  nessuna scrittura di git" '[ "$(gitstate)" = "$s1" ]'

# 5. usage
hm "$M"
check "tree principale al posto del worktree -> 2" '[ "$(rc)" = 2 ]'
hm "$T/non-esiste"
check "worktree assente -> 2" '[ "$(rc)" = 2 ]'

# 6. script text: no git invocation that writes (the printed commands are inside echo)
code=$(grep -vE '^[[:space:]]*(#|echo[[:space:]])' "$HM")
check "nessun git merge/cherry-pick/commit/... eseguito dallo script" '! printf "%s\n" "$code" | grep -Eq "git[^|;&]*[[:space:]](merge|cherry-pick|commit|checkout|switch|reset|rebase|push|pull|fetch|stash|restore|clean|add|rm|mv|update-ref|worktree|branch|tag)([[:space:]]|\$|\")"'
check "  il controllo vede davvero le invocazioni (una riga finta viene trovata)" 'printf "%s\n" "  git -C \"\$MAIN\" merge --ff-only x" | grep -Eq "git[^|;&]*[[:space:]](merge|cherry-pick)([[:space:]]|\$|\")"'

echo "harness-merge.test.sh: $((n - fail))/$n ok"
[ $fail -eq 0 ]
