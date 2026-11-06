#!/usr/bin/env bash
# ciclo-worktree.test.sh — tests of script/fic/ciclo-worktree.sh in a FAKE git repository in a temporary
# folder, with a fake HOME and without WSL (FIC_WT_WSL=0): no worktree, branch or link in the real repository.
#   bash script/fic/ciclo-worktree.test.sh
#   CW=/path/variant.sh bash script/fic/ciclo-worktree.test.sh   # the variant sits next to worktree-lib.sh
# Cases: crea (worktree, spec and run dir copied, links, no physical copy of node_modules, .nuxt), resume
# (also with an untracked dependency file), someone else's worktree, different dependencies, riporta (run dir
# sync, STOP if the main tree's spec or run dir changed), rimuovi with changes / with spec or run dir not
# synced back / with lock, live plan.lock or running phase / with an UNREGISTERED link (sentinel intact) /
# clean (the source's node_modules INTACT: entries and content), per-worktree lock (run-phase.sh --lock-status),
# --forza --branch, WSL copies of the worktree and of the lanes really deleted (forget_mirror, fake HOME).
# Counterproofs by mutation, ONLY in the fake repos: (1) rimuovi without scollega_e_verifica ⇒ the source's
# node_modules is emptied (git worktree remove follows junctions), the «intact» check turns red; (2) links_left() { return 0; }
# ⇒ an unregistered link no longer stops the removal and the sentinel is emptied.
# ⚠️ Designed for WINDOWS (Git Bash): links = junctions (mklink /J), as in the real repository; the counterproofs
# measure that `git worktree remove` follows junctions. Elsewhere (Linux, pk08) links are symlinks, which git
# does not follow: counterproof 1 declares itself SALTATO, 2 measures that the removal no longer stops. Declared limit: a symlink TRACKED by the repository would be
# a leftover link for `rimuovi` (false positive, STOP: the safe direction); the repository has none today.
set -uo pipefail
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)   # plugin root
CW=${CW:-$HERE/ciclo-worktree.sh}
RPS=$ROOT/scripts/run-phase.sh
# ciclo-worktree.sh calls the plugin's run-phase.sh and cycle-state.sh (MAAT_SCRIPTS), not the worktree's (pk04a-1,
# schema H): the fake repo has no copies of them. The mutants in $T find the plugin via MAAT_ROOT
export MAAT_ROOT=$ROOT
T=$(mktemp -d)
# pk08: outside Windows (Linux) links are symlinks, as in worktree-lib.sh: no cmd.exe or cygpath
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) TWIN=1 ;; *) TWIN=0 ;; esac
unlink_all() { # the links left under $T, removed WITHOUT following them (before rm -rf)
  local l
  find "$T" -type l 2>/dev/null | while IFS= read -r l; do
    [ $TWIN -eq 1 ] && MSYS2_ARG_CONV_EXCL='*' cmd.exe /c rmdir "$(cygpath -w "$l")" >/dev/null 2>&1; [ -L "$l" ] && rm -f "$l"; done
}
trap 'unlink_all; rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export FIC_WT_WSL=0
unset FIC_LOCK FIC_PHASE FIC_REPO MSYS_NO_PATHCONV
fail=0 n=0
check() { n=$((n + 1)); if eval "$2"; then :; else fail=$((fail + 1)); echo "FAIL: $1"; fi; }
canon() { (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); }

mkrepo() { # $1 folder, $2 maat.json (default: the nuxt-fastapi example): fake repository with fake installed
  # dependencies and a spec; its maat.json declares the links, dependency files and preparati
  local M=$1 C=${2:-$ROOT/examples/nuxt-fastapi.maat.json}
  mkdir -p "$M" && cd "$M" || return 1
  git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false
  printf 'node_modules\n.venv\n.venv312\n.nuxt\n.claude/.ai-workflow/spec-*\n' > .gitignore
  mkdir -p modules/app/apps/admin modules/app/packages/ui modules/api .claude/.ai-workflow
  printf '{"name":"root"}\n' > package.json; printf '{"lock":0}\n' > package-lock.json
  printf '{"name":"app"}\n' > modules/app/package.json; printf '{"lock":1}\n' > modules/app/package-lock.json
  printf '{"name":"admin"}\n' > modules/app/apps/admin/package.json
  printf '{"name":"ui"}\n' > modules/app/packages/ui/package.json
  printf 'fastapi\n' > modules/api/requirements.txt
  printf '<template/>\n' > modules/app/apps/admin/a.vue
  printf 'codice\n' > a.txt; printf '# note\n' > .claude/.ai-workflow/README.md
  cp "$C" .claude/maat.json || return 1
  git add -A && git commit -qm init || return 1
  # installed dependencies (gitignored): the ones the worktree must LINK
  mkdir -p node_modules/r1 modules/app/node_modules/p1/lib modules/app/node_modules/p2 modules/app/node_modules/p3 \
           modules/app/apps/admin/node_modules/q1 modules/api/.venv/Scripts modules/app/apps/admin/.nuxt
  echo r > node_modules/r1/index.js; echo p > modules/app/node_modules/p1/lib/index.js; echo p2 > modules/app/node_modules/p2/x.js
  echo q > modules/app/apps/admin/node_modules/q1/index.js; echo py > modules/api/.venv/Scripts/python.txt
  printf '{"extends":"x"}\n' > modules/app/apps/admin/.nuxt/tsconfig.json
  echo 'd' > modules/app/apps/admin/.nuxt/imports.d.ts; echo 'd' > modules/app/apps/admin/.nuxt/components.d.ts
  echo 'no' > modules/app/apps/admin/.nuxt/altro.mjs
  printf '# spec uno\n## Requisiti\n' > .claude/.ai-workflow/spec-uno.md
  mkdir -p .claude/.ai-workflow/spec-uno.run/log && echo 0 > .claude/.ai-workflow/spec-uno.run/log/01-plan.exit
  for s in due tre quattro cinque sei sette otto; do printf '# spec %s\n' "$s" > ".claude/.ai-workflow/spec-$s.md"; done
}
mkjunction() { # junction on Windows, symlink elsewhere (the variant of link_dep in worktree-lib.sh)
  if [ $TWIN -eq 1 ]; then MSYS2_ARG_CONV_EXCL='*' cmd.exe /c mklink /J "$(cygpath -w "$2")" "$(cygpath -w "$1")" >/dev/null
  else ln -s "$1" "$2"; fi
}
rmjunction() { if [ $TWIN -eq 1 ]; then MSYS2_ARG_CONV_EXCL='*' cmd.exe /c rmdir "$(cygpath -w "$1")" >/dev/null 2>&1; else rm -f "$1"; fi; }
nm_count() { find "$1/modules/app/node_modules" "$1/node_modules" "$1/modules/app/apps/admin/node_modules" "$1/modules/api/.venv" | wc -l; }
nm_sum() { find "$1/modules/app/node_modules" "$1/node_modules" "$1/modules/app/apps/admin/node_modules" "$1/modules/api/.venv" -type f -exec cksum {} + | sort; }
cw() { (cd "$M" && bash "$CW" "$@"); }   # from the fake main tree

M="$T/proj"; mkrepo "$M" >/dev/null 2>&1 || { echo "FAIL: repo finto non creato"; exit 1; }
MC=$(canon "$M"); PAR=$(dirname "$MC"); W1="$PAR/proj-fic-uno"
cnt0=$(nm_count "$M") sum0=$(nm_sum "$M") ls0=$(ls "$M/modules/app/node_modules" | wc -l)

# 1. crea: worktree on branch fic/uno, spec and run dir copied, links, no physical copy
out=$(cw crea .claude/.ai-workflow/spec-uno.md 2>&1); rc=$?
check "crea esce 0" '[ $rc -eq 0 ]' || printf '%s\n' "$out"
check "  ultima riga = percorso del worktree" '[ "$(printf "%s\n" "$out" | tail -1)" = "$W1" ]'
check "  worktree sul branch fic/uno" '[ "$(git -C "$W1" symbolic-ref --short HEAD 2>/dev/null)" = fic/uno ]'
check "  spec copiata" 'cmp -s "$M/.claude/.ai-workflow/spec-uno.md" "$W1/.claude/.ai-workflow/spec-uno.md"'
check "  run dir copiata" '[ -f "$W1/.claude/.ai-workflow/spec-uno.run/log/01-plan.exit" ]'
check "  marcatore nel worktree" '[ "$(head -1 "$W1/.claude/.ai-workflow/spec-uno.worktree")" = fic-ciclo-worktree ]'
for p in node_modules modules/app/node_modules modules/app/apps/admin/node_modules modules/api/.venv; do
  check "  $p collegato (collegamento, non cartella)" '[ -L "$W1/$p" ] && [ -f "$W1/$p/$(ls "$M/$p" | head -1)" -o -d "$W1/$p/$(ls "$M/$p" | head -1)" ]'
done
check "  nessuna copia fisica di node_modules (find non segue i collegamenti)" '[ -z "$(find "$W1" -path "*node_modules/*" -print -quit)" ] && [ -z "$(find "$W1" -path "*/.venv/*" -print -quit)" ]'
check "  .venv312 assente nella fonte: nessun collegamento" '[ ! -e "$W1/modules/api/.venv312" ]'
check "  .nuxt: tsconfig e dichiarazioni copiati, il resto no" '[ -f "$W1/modules/app/apps/admin/.nuxt/tsconfig.json" ] && [ -f "$W1/modules/app/apps/admin/.nuxt/components.d.ts" ] && [ ! -e "$W1/modules/app/apps/admin/.nuxt/altro.mjs" ]'
check "  worktree pulito per git (marcatore, spec, collegamenti gitignorati)" '[ -z "$(git -C "$W1" status --porcelain --untracked-files=all)" ]'
check "  tree principale intatto" '[ -z "$(git -C "$M" status --porcelain)" ] && [ "$(nm_count "$M")" = "$cnt0" ]'

# 2. crea again: resume, the worktree's spec wins
echo "## Piano (dal ciclo)" >> "$W1/.claude/.ai-workflow/spec-uno.md"
out=$(cw crea .claude/.ai-workflow/spec-uno.md 2>&1); rc=$?
check "crea due volte → ripresa (0)" '[ $rc -eq 0 ] && printf "%s" "$out" | grep -q "ripresa"' || printf '%s\n' "$out"
check "  la spec del worktree non e' sovrascritta" 'grep -q "Piano (dal ciclo)" "$W1/.claude/.ai-workflow/spec-uno.md"'
check "  collegamenti ancora collegamenti" '[ -L "$W1/modules/app/node_modules" ]'
printf '{"name":"nuovo"}\n' > "$W1/modules/app/packages/ui/package-lock.json"   # dependency added, untracked
out=$(cw crea .claude/.ai-workflow/spec-uno.md 2>&1); rc=$?
check "ripresa con un file di dipendenze non tracciato nel worktree → STOP (3)" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "packages/ui/package-lock.json"' || printf '%s\n' "$out"
rm "$W1/modules/app/packages/ui/package-lock.json"

# 2b. pk09 (pilot on a second project): launched from INSIDE a linked worktree (git dir ≠ git common dir) ⇒ refusal (3) for
# every subcommand, with the message, nothing created. Before pk09 it climbed to the main tree (--git-common-dir) and
# took its base, maat.json and spec: here crea resumed the worktree (0) and stato answered (0). Counterproof: from the
# main tree the same commands pass (the cases around here and the last check below).
nwt0=$(git -C "$M" worktree list | wc -l)
# .claude/.ai-workflow is gitignored: git status does not see it, so its listing is compared before and after
aiw() { (cd "$W1" && find .claude/.ai-workflow 2>/dev/null | LC_ALL=C sort); }
aiw0=$(aiw)
out=$( (cd "$W1" && bash "$CW" crea .claude/.ai-workflow/spec-uno.md) 2>&1); rc=$?
check "crea da un worktree collegato → rifiuto (3) col messaggio" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "o senza --worktree: questa cartella e. gia. un worktree"' || printf '%s\n' "$out"
check "  nessun worktree nuovo, nessun file nuovo nel worktree (.claude/.ai-workflow compresa)" '[ "$(git -C "$M" worktree list | wc -l)" = "$nwt0" ] && [ -z "$(git -C "$W1" status --porcelain --untracked-files=all)" ] && [ "$(aiw)" = "$aiw0" ] && [ ! -e "$W1-fic-uno" ]'
out=$( (cd "$W1" && bash "$CW" stato uno) 2>&1); rc=$?
check "stato da un worktree collegato → rifiuto (3) col messaggio" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "o senza --worktree: questa cartella e. gia. un worktree"' || printf '%s\n' "$out"
check "  stato: .claude/.ai-workflow del worktree invariata" '[ "$(aiw)" = "$aiw0" ]'
out=$(cw stato uno 2>&1); rc=$?
check "  controprova: stato dal tree principale → 0" '[ $rc -eq 0 ] && printf "%s" "$out" | grep -qx "percorso: $W1"' || printf '%s\n' "$out"
# 2en. 1.4.0, English (MAAT_LINGUA=en): crea (resume) and stato, the main output; the last line of crea is still the
# path, the sub-commands and the marker as they are, no Italian of the catalog
out=$(MAAT_LINGUA=en cw crea .claude/.ai-workflow/spec-uno.md 2>&1); rc=$?
check "en: crea due volte → ripresa (0), testo inglese, ultima riga = percorso" '[ $rc -eq 0 ] && printf "%s\n" "$out" | grep -qx "ciclo-worktree: resuming the existing worktree: $W1" && printf "%s\n" "$out" | grep -q "^ciclo-worktree: dependencies linked from the main tree: " && [ "$(printf "%s\n" "$out" | tail -1)" = "$W1" ]' || printf '%s\n' "$out"
check "  en: niente italiano nell'uscita di crea" '! printf "%s" "$out" | grep -Eq "ripresa|collegat|dipendenze|gia.|sovrascriv|saltata|copiat|nessun|AVVISO"' || printf '%s\n' "$out"
out=$(MAAT_LINGUA=en cw stato uno 2>&1); rc=$?
check "en: stato → 0, righe inglesi" '[ $rc -eq 0 ] && printf "%s\n" "$out" | grep -qx "path: $W1" && printf "%s\n" "$out" | grep -q "^owner: ciclo-worktree.sh (" && printf "%s\n" "$out" | grep -q "^files changed: 0$"' || printf '%s\n' "$out"
check "  en: niente italiano nell'uscita di stato (il valore si/no a parte)" '! printf "%s" "$out" | grep -Eq "percorso|proprietario|riportata|modificati|assente|staccato"' || printf '%s\n' "$out"
out=$( (cd "$W1" && MAAT_LINGUA=en bash "$CW" stato uno) 2>&1); rc=$?
check "en: stato da un worktree collegato → rifiuto (3), STOP col motivo inglese" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "^ciclo-worktree: STOP — launch the cycle from the main tree (.*), or without --worktree: this folder is already a worktree"' || printf '%s\n' "$out"

# 3. someone else's worktree with the same name ⇒ STOP, nothing touched
W2="$PAR/proj-fic-due"
git -C "$M" worktree add -q -b fic/due "$W2" HEAD 2>/dev/null
out=$(cw crea .claude/.ai-workflow/spec-due.md 2>&1); rc=$?
check "worktree altrui con lo stesso nome → STOP (3)" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "STOP"' || printf '%s\n' "$out"
check "  nessun collegamento ne' spec nel worktree altrui" '[ ! -e "$W2/node_modules" ] && [ ! -e "$W2/.claude/.ai-workflow/spec-due.md" ]'
out=$(cw rimuovi due 2>&1); rc=$?
check "  rimuovi del worktree altrui → STOP, resta" '[ $rc -eq 3 ] && [ -d "$W2" ]'
git -C "$M" worktree remove "$W2" && git -C "$M" branch -q -D fic/due
mkdir -p "$PAR/proj-fic-due"   # any folder with that name
out=$(cw crea .claude/.ai-workflow/spec-due.md 2>&1); rc=$?
check "cartella non-worktree con lo stesso nome → STOP (3)" '[ $rc -eq 3 ]'
rmdir "$PAR/proj-fic-due"

# 4. different dependencies ⇒ STOP, no worktree, no branch
printf '{"lock":2}\n' > "$M/modules/app/package-lock.json"
out=$(cw crea .claude/.ai-workflow/spec-tre.md 2>&1); rc=$?
check "dipendenze diverse → STOP (3)" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "modules/app/package-lock.json"' || printf '%s\n' "$out"
check "  nessun worktree, nessun branch" '[ ! -e "$PAR/proj-fic-tre" ] && ! git -C "$M" show-ref -q --verify refs/heads/fic/tre'
printf '{"lock":1}\n' > "$M/modules/app/package-lock.json"
check "  (ripristino: tree principale di nuovo pulito)" '[ -z "$(git -C "$M" status --porcelain)" ]'

# 5. riporta: spec and run dir into the main tree; never the code
echo "Review status: APPROVED" >> "$W1/.claude/.ai-workflow/spec-uno.md"
echo 0 > "$W1/.claude/.ai-workflow/spec-uno.run/log/02-implement.exit"
echo "modifica del ciclo" >> "$W1/a.txt"
echo "# nota dell'utente" >> "$M/.claude/.ai-workflow/spec-uno.md"   # main tree spec changed after the copy
out=$(cw riporta uno 2>&1); rc=$?
check "riporta con la spec principale cambiata → STOP (3)" '[ $rc -eq 3 ] && grep -q "nota dell" "$M/.claude/.ai-workflow/spec-uno.md"'
out=$(cw riporta uno --forza 2>&1); rc=$?
check "riporta --forza esce 0" '[ $rc -eq 0 ]' || printf '%s\n' "$out"
check "  spec nel tree principale = spec del worktree" 'cmp -s "$M/.claude/.ai-workflow/spec-uno.md" "$W1/.claude/.ai-workflow/spec-uno.md"'
check "  run dir nel tree principale (file nuovo e vecchio)" '[ -f "$M/.claude/.ai-workflow/spec-uno.run/log/02-implement.exit" ] && [ -f "$M/.claude/.ai-workflow/spec-uno.run/log/01-plan.exit" ]'
check "  codice del tree principale non toccato" '[ -z "$(git -C "$M" status --porcelain)" ] && ! grep -q "modifica del ciclo" "$M/a.txt"'
echo "Feature status: IMPLEMENTED" >> "$W1/.claude/.ai-workflow/spec-uno.md"
out=$(cw riporta uno 2>&1); rc=$?
check "riporta di nuovo (principale = ultima riportata) → 0 senza --forza" '[ $rc -eq 0 ] && cmp -s "$M/.claude/.ai-workflow/spec-uno.md" "$W1/.claude/.ai-workflow/spec-uno.md"' || printf '%s\n' "$out"
out=$(cw stato uno 2>&1); rc=$?
check "stato: percorso, branch, file modificati" '[ $rc -eq 0 ] && printf "%s" "$out" | grep -qx "percorso: $W1" && printf "%s" "$out" | grep -q "^branch: fic/uno" && printf "%s" "$out" | grep -qx "file modificati: 1"' || printf '%s\n' "$out"

# 6. rimuovi with changes ⇒ refusal, nothing touched
out=$(cw rimuovi uno 2>&1); rc=$?
check "rimuovi con modifiche → rifiuto (3)" '[ $rc -eq 3 ] && [ -d "$W1" ] && [ -L "$W1/modules/app/node_modules" ]' || printf '%s\n' "$out"
git -C "$W1" checkout -q -- a.txt

# 6b. spec or run dir not synced back ⇒ STOP (unless --forza); riporta SYNCS the run dir; live phases ⇒ STOP
RD1="$W1/.claude/.ai-workflow/spec-uno.run" RDM="$M/.claude/.ai-workflow/spec-uno.run"
echo "## Review (dopo il riporta)" >> "$W1/.claude/.ai-workflow/spec-uno.md"
out=$(cw rimuovi uno 2>&1); rc=$?
check "rimuovi con la spec non riportata → STOP (3), worktree e collegamenti intatti" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "la spec" && [ -d "$W1" ] && [ -L "$W1/modules/app/node_modules" ]' || printf '%s\n' "$out"
cw riporta uno >/dev/null 2>&1
echo 0 > "$RD1/log/03-review.exit"
out=$(cw rimuovi uno 2>&1); rc=$?
check "rimuovi con la run dir non riportata → STOP (3)" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "la run dir" && [ -d "$W1" ]' || printf '%s\n' "$out"
rm "$RD1/log/02-implement.exit"
out=$(cw riporta uno 2>&1); rc=$?
check "riporta allinea la run dir: file nuovo arrivato, file tolto sparito" '[ $rc -eq 0 ] && [ -f "$RDM/log/03-review.exit" ] && [ ! -e "$RDM/log/02-implement.exit" ] && diff -rq "$RD1" "$RDM" >/dev/null' || printf '%s\n' "$out"
check "  nessuna cartella temporanea lasciata" '[ -z "$(ls -d "$RDM".* 2>/dev/null)" ]'
echo altro > "$RDM/log/99-altro.txt"; echo 0 > "$RD1/log/04-fix.exit"   # main run dir changed after riporta
out=$(cw riporta uno 2>&1); rc=$?
check "riporta con la run dir principale cambiata → STOP (3), nulla toccato" '[ $rc -eq 3 ] && [ -f "$RDM/log/99-altro.txt" ] && [ ! -e "$RDM/log/04-fix.exit" ]' || printf '%s\n' "$out"
rm "$RDM/log/99-altro.txt"
out=$(cw riporta uno 2>&1); rc=$?
check "  tolto il file estraneo, riporta esce 0" '[ $rc -eq 0 ] && [ -f "$RDM/log/04-fix.exit" ]' || printf '%s\n' "$out"
mkdir "$RD1/plan.lock" && printf 'pid=%s\nrun=x\nlabel=01-plan\n' "$$" > "$RD1/plan.lock/owner"
out=$(cw rimuovi uno --forza 2>&1); rc=$?
check "rimuovi con plan.lock vivo → STOP (3) anche con --forza" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "plan.lock" && [ -L "$W1/modules/app/node_modules" ]' || printf '%s\n' "$out"
rm -rf "$RD1/plan.lock"
date > "$RD1/log/05-review.running"
out=$(cw rimuovi uno 2>&1); rc=$?
check "rimuovi con una fase in corso (.running senza .exit) → STOP (3)" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "05-review" && [ -d "$W1" ]' || printf '%s\n' "$out"
rm "$RD1/log/05-review.running"
# failed run dir swap and failed restore (fake mv that fails only on *.nuova.* and *.vecchia.*):
# the message names the old one, the new one is deleted, nothing is lost
FMV="$T/fakemv"; mkdir -p "$FMV"
MV_VERO=$(command -v mv)   # 1.6.0: the mv of the PATH, not /usr/bin/mv (on macOS mv is /bin/mv); the same file on Linux
printf '#!/bin/bash\ncase "$1" in *.nuova.*|*.vecchia.*) echo "mv finto: fallisce $1" >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$MV_VERO" > "$FMV/mv"; chmod +x "$FMV/mv"
echo 0 > "$RD1/log/06-review.exit"
out=$( (cd "$M" && PATH="$FMV:$PATH" bash "$CW" riporta uno) 2>&1); rc=$?
vec=$(ls -d "$RDM".vecchia.* 2>/dev/null | head -1)
check "riporta con scambio e ripristino falliti → errore (2) che nomina la run dir precedente" '[ $rc -eq 2 ] && [ -n "$vec" ] && printf "%s" "$out" | grep -q "NON ripristinata" && printf "%s" "$out" | grep -qF "precedente e'"'"' in " && printf "%s" "$out" | grep -qF "$(basename "$vec")"'
check "  copia nuova cancellata, precedente conservata" '[ -z "$(ls -d "$RDM".nuova.* 2>/dev/null)" ] && [ -f "$vec/log/04-fix.exit" ]'
[ -n "$vec" ] && "$MV_VERO" "$vec" "$RDM"
out=$(cw riporta uno 2>&1); rc=$?
check "  rimessa a mano la precedente, riporta esce 0" '[ $rc -eq 0 ] && [ -f "$RDM/log/06-review.exit" ] && diff -rq "$RD1" "$RDM" >/dev/null' || printf '%s\n' "$out"

# 7. lock: each worktree has its own (the worktree's git dir); two cycles do not block each other
W4="$PAR/proj-fic-quattro"
out=$(cw crea .claude/.ai-workflow/spec-quattro.md 2>&1); rc=$?
check "crea di un secondo worktree esce 0" '[ $rc -eq 0 ] && [ -d "$W4" ]' || printf '%s\n' "$out"
L1="$(git -C "$W1" rev-parse --absolute-git-dir)/full-implementation-cycle.lock"
mkdir -p "$L1" && printf 'pid=%s\ncpid=\nrun=x\nlabel=02-implement\n' "$$" > "$L1/owner"   # live code phase in worktree 1
ls1=$( (cd "$W1" && bash "$RPS" --lock-status) ); r1=$?
ls4=$( (cd "$W4" && bash "$RPS" --lock-status) ); r4=$?
lsm=$( (cd "$M" && bash "$RPS" --lock-status) ); rm_=$?
check "lock: worktree 1 occupato (1)" '[ $r1 -eq 1 ] && printf "%s" "$ls1" | grep -q "^occupato"'
check "  worktree 2 libero (0): il lock e' per worktree" '[ $r4 -eq 0 ] && [ "$ls4" = libero ]'
check "  tree principale libero (0)" '[ $rm_ -eq 0 ] && [ "$lsm" = libero ]'
check "  i due lock sono in git dir diverse" '[ "$(git -C "$W1" rev-parse --absolute-git-dir)" != "$(git -C "$W4" rev-parse --absolute-git-dir)" ]'
out=$(cw rimuovi uno 2>&1); rc=$?
check "rimuovi con il lock del worktree occupato → rifiuto (3)" '[ $rc -eq 3 ] && [ -L "$W1/modules/app/node_modules" ]' || printf '%s\n' "$out"
rm -rf "$L1"

# 8. clean rimuovi: links removed, the source's node_modules INTACT, worktree gone, branch kept
out=$(cw rimuovi uno 2>&1); rc=$?
check "rimuovi esce 0" '[ $rc -eq 0 ]' || printf '%s\n' "$out"
check "  worktree sparito (cartella e git worktree list)" '[ ! -e "$W1" ] && ! git -C "$M" worktree list | grep -q "proj-fic-uno"'
check "  node_modules della fonte INTATTO: stesso numero di voci" '[ "$(nm_count "$M")" = "$cnt0" ] && [ "$(ls "$M/modules/app/node_modules" | wc -l)" = "$ls0" ]'
check "  e stesso contenuto" '[ "$(nm_sum "$M")" = "$sum0" ]'
check "  branch fic/uno lasciato (senza --branch)" 'git -C "$M" show-ref -q --verify refs/heads/fic/uno'
out=$(cw rimuovi quattro --branch 2>&1); rc=$?
check "rimuovi --branch: worktree e branch spariti" '[ $rc -eq 0 ] && [ ! -e "$W4" ] && ! git -C "$M" show-ref -q --verify refs/heads/fic/quattro' || printf '%s\n' "$out"

# 9. --forza: changes discarded, source intact
W5="$PAR/proj-fic-cinque"
cw crea .claude/.ai-workflow/spec-cinque.md >/dev/null 2>&1
echo sporco >> "$W5/a.txt"; echo nuovo > "$W5/nuovo.txt"
mkdir -p "$W5/.claude/.ai-workflow/spec-cinque.run/log" && date > "$W5/.claude/.ai-workflow/spec-cinque.run/log/07-fix.running"
out=$(cw rimuovi cinque --forza --branch 2>&1); rc=$?
check "rimuovi --forza con modifiche esce 0" '[ $rc -eq 0 ] && [ ! -e "$W5" ]' || printf '%s\n' "$out"
check "  e avvisa della fase in corso ignorata, con l'etichetta" 'printf "%s" "$out" | grep -q "AVVISO.*07-fix"'
check "  fonte ancora intatta" '[ "$(nm_count "$M")" = "$cnt0" ] && [ "$(nm_sum "$M")" = "$sum0" ]'

# 9b. leftover UNREGISTERED link (outside dep_links) ⇒ STOP, worktree stays, sentinel intact
W6="$PAR/proj-fic-sei" SEN="$T/sentinella"
mkdir -p "$SEN/a/b" && echo s1 > "$SEN/a/b/f.txt" && echo s2 > "$SEN/g.txt"
sen_n() { find "$1" | wc -l; }; sen_s() { find "$1" -type f -exec cksum {} + | sort; }
sn0=$(sen_n "$SEN") ss0=$(sen_s "$SEN")
cw crea .claude/.ai-workflow/spec-sei.md >/dev/null 2>&1
mkdir -p "$W6/modules/x" && mkjunction "$SEN" "$W6/modules/x/node_modules"
check "premessa: junction estranea presente, ignorata da git" '[ -L "$W6/modules/x/node_modules" ] && [ -f "$W6/modules/x/node_modules/g.txt" ] && [ -z "$(git -C "$W6" status --porcelain --untracked-files=all)" ]'
out=$(cw rimuovi sei 2>&1); rc=$?
check "rimuovi con un collegamento non registrato → STOP (3) che lo nomina" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "modules/x/node_modules"' || printf '%s\n' "$out"
check "  il worktree resta" '[ -d "$W6" ] && git -C "$M" worktree list | grep -q "proj-fic-sei"'
check "  sentinella intatta (voci e cksum)" '[ "$(sen_n "$SEN")" = "$sn0" ] && [ "$(sen_s "$SEN")" = "$ss0" ]'
check "  fonte intatta" '[ "$(nm_count "$M")" = "$cnt0" ] && [ "$(nm_sum "$M")" = "$sum0" ]'
rmjunction "$W6/modules/x/node_modules"; rmdir "$W6/modules/x"
out=$(cw rimuovi sei --branch 2>&1); rc=$?
check "  tolta la junction estranea, rimuovi esce 0 e la sentinella resta intatta" '[ $rc -eq 0 ] && [ ! -e "$W6" ] && [ "$(sen_s "$SEN")" = "$ss0" ]' || printf '%s\n' "$out"

# 9c. the worktree's WSL copies REALLY deleted, lanes included (the lib's forget_mirror, script on stdin; here local
# bash with the fake HOME), never ~/fic-mirror. Before 2026-09-30 the lanes stayed ($k expanded to empty).
W7="$PAR/proj-fic-sette"
cw crea .claude/.ai-workflow/spec-sette.md >/dev/null 2>&1
fm=$( ( WT_TAG=test DEP_LINKS_EXTRA=(); . "$HERE/worktree-lib.sh" || { echo "worktree-lib.sh non caricata"; exit 0; }
  WIN=0
  fic_mirror_init "$W7" || { echo "fic_mirror_init fallita"; exit 0; }
  c=$FIC_MIRROR
  case "$c" in "$HOME"/fic-mirror-????????????) ;; *) echo "copia inattesa: $c"; exit 0 ;; esac
  mkdir -p "$c/x" "$c-1/x" "$c-2/x" "$HOME/fic-mirror/x"
  forget_mirror "$W7" > "$T/fm.out" 2>&1
  for d in "$c" "$c-1" "$c-2"; do [ -e "$d" ] && echo "resta $d"; done
  [ -d "$HOME/fic-mirror/x" ] || echo "cancellata ~/fic-mirror"
  grep -q "corsia cancellata: $c-1" "$T/fm.out" && grep -q "corsia cancellata: $c-2" "$T/fm.out" || echo "corsie non annunciate: $(cat "$T/fm.out")"
) 2>&1)
check "forget_mirror: copia e corsie 1 e 2 del worktree cancellate, ~/fic-mirror no" '[ -z "$fm" ]' || printf '%s\n' "$fm"
# 9d. 1.4.0: on Windows the program for `wsl.exe -- bash -s` exports MAAT_LINGUA, resolved (wsl.exe does not pass the
# environment: the reasons of fic-mirror.sh in WSL). A fake wsl.exe (a function) captures the program, runs nothing.
# Counterproof: a copy of the lib without the export => no MAAT_LINGUA in the program.
fm_prog() { # <worktree-lib.sh> <MAAT_LINGUA>: the program given to wsl.exe
  ( WT_TAG=test DEP_LINKS_EXTRA=(); . "$1" >/dev/null 2>&1 || exit 0
    WIN=1; wsl.exe() { cat > "$T/fm.prog"; }
    rm -f "$T/fm.prog"; MAAT_LINGUA=$2 forget_mirror "$W7" >/dev/null 2>&1; cat "$T/fm.prog" 2>/dev/null )
}
check "forget_mirror su Windows: il programma per wsl.exe esporta MAAT_LINGUA (it e en)" \
  'fm_prog "$HERE/worktree-lib.sh" it | grep -qx "export MAAT_LINGUA=it" && fm_prog "$HERE/worktree-lib.sh" en | grep -qx "export MAAT_LINGUA=en"'
ML="$T/mut-lingua/scripts"; mkdir -p "$ML"; cp -r "$HERE/lib" "$ML/"
cp "$HERE/fic-mirror.sh" "$HERE/python.sh" "$HERE/maat-config.py" "$HERE/maat_paths.py" "$ML/"
grep -v "^          printf 'export MAAT_LINGUA=%q" "$HERE/worktree-lib.sh" > "$ML/worktree-lib.sh"
check "controprova: lib senza l'export -> nessuna MAAT_LINGUA nel programma" \
  '! cmp -s "$HERE/worktree-lib.sh" "$ML/worktree-lib.sh" && p=$(fm_prog "$ML/worktree-lib.sh" it) && [ -n "$p" ] && ! grep -q MAAT_LINGUA <<< "$p"'
cw rimuovi sette --branch >/dev/null 2>&1
check "tree principale pulito alla fine" '[ -z "$(git -C "$M" status --porcelain)" ]'

# 10. COUNTERPROOF by mutation (only in the fake repo): rimuovi without scollega_e_verifica ⇒ source emptied
MU="$T/mut"; mkdir -p "$MU/scripts/lib"
cp "$HERE/worktree-lib.sh" "$ROOT/scripts/fic-mirror.sh" "$ROOT/scripts/python.sh" "$MU/scripts/"
cp "$ROOT/scripts/lib/maat-paths.sh" "$MU/scripts/lib/"
# 1.4.0: the message catalog and its two readers, next to the scripts as in the plugin
cp "$ROOT/scripts/lib/maat-msg.sh" "$ROOT/scripts/lib/messages.tsv" "$MU/scripts/lib/"; cp "$ROOT/scripts/maat_msg.py" "$MU/scripts/"
sed 's/^scollega_e_verifica "\$WT" || stop .*$/: MUTANTE — nessuno scollegamento/' "$CW" > "$MU/scripts/ciclo-worktree.sh"
check "premessa: mutazione applicata" '! cmp -s "$CW" "$MU/scripts/ciclo-worktree.sh" && grep -q "^: MUTANTE" "$MU/scripts/ciclo-worktree.sh"'
MM="$T/cp/proj"; mkrepo "$MM" >/dev/null 2>&1
c0=$(nm_count "$MM")
(cd "$MM" && bash "$MU/scripts/ciclo-worktree.sh" crea .claude/.ai-workflow/spec-uno.md >/dev/null 2>&1)
(cd "$MM" && bash "$MU/scripts/ciclo-worktree.sh" rimuovi uno >/dev/null 2>&1)
c1=$(nm_count "$MM" 2>/dev/null)
# 1.6.0: does THIS git follow a junction in git worktree remove? (the Git for Windows of the CI runner, 2.56, does not:
# the source stays intact even with the mutant, as with the symlinks). Probe on a repo of its own; where it does not
# follow, the counterproofs take the branch of the symlinks. A failed preparation of the probe (git init, commit,
# worktree add, the junction not there before the remove) is a red check of its own, never a SALTATO blamed on git.
# SONDA: segue | non-segue | guasta (Windows only) · SONDA_RIMOSSO: 1 if git removed the probe worktree
SEGUE=0 SONDA= SONDA_RIMOSSO=0
if [ $TWIN -eq 1 ]; then
  PG="$T/sonda-giunzione"; sonda_prep=ok
  { mkdir -p "$PG/fonte" && echo s > "$PG/fonte/f.txt" &&
    (cd "$PG" && git init -q r && cd r && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m s &&
      git worktree add -q ../w 2>/dev/null) && mkjunction "$PG/fonte" "$PG/w/nm" && [ -e "$PG/w/nm" ] &&
    [ -f "$PG/w/nm/f.txt" ]; } > "$T/sonda.out" 2>&1 || sonda_prep=guasta
  if [ $sonda_prep = ok ]; then
    (cd "$PG/r" && git worktree remove --force ../w) >> "$T/sonda.out" 2>&1
    if [ -f "$PG/fonte/f.txt" ]; then SONDA=non-segue; else SONDA=segue SEGUE=1; fi
    [ -e "$PG/w" ] || SONDA_RIMOSSO=1
  else
    SONDA=guasta
  fi
  [ -e "$PG/w/nm" ] && rmjunction "$PG/w/nm"
  check "sonda della giunzione: preparata (repo, worktree e giunzione presenti prima del remove)" '[ $sonda_prep = ok ]'
  [ $sonda_prep = ok ] || sed 's/^/    /' "$T/sonda.out"
  echo "sonda della giunzione ($(git --version)): $SONDA$([ "$SONDA" = guasta ] || { [ $SONDA_RIMOSSO = 1 ] && echo ", worktree rimosso" || echo ", worktree NON rimosso"; })"
fi
if [ $SEGUE -eq 1 ]; then
  check "controprova: senza lo scollegamento il node_modules della fonte NON e' intatto ($c0 → $c1 voci)" '[ "$c1" != "$c0" ]'
elif [ "$SONDA" = guasta ]; then
  echo "NON ESEGUITA [controprova 1]: la sonda della giunzione non si e' preparata (check rosso sopra)"
else   # pk08: git worktree remove removes a symlink without following it, the source stays intact even with the mutant
  echo "SALTATO [controprova 1]: ${SONDA:+sonda $SONDA: }git worktree remove non segue il collegamento ($([ $TWIN -eq 1 ] && echo giunzione || echo symlink); $c0 → $c1 voci): nessun effetto da misurare"
fi

# 11. COUNTERPROOF by mutation (only in the fake repo): links_left() { return 0; } ⇒ the unregistered link no longer
# stops the removal and git worktree remove empties the sentinel
sed '/^scollega_e_verifica() {/i links_left() { return 0; }  # MUTANTE' "$CW" > "$MU/scripts/ciclo-worktree.sh"
check "premessa: mutazione 2 applicata" 'grep -q "^links_left() { return 0; }  # MUTANTE" "$MU/scripts/ciclo-worktree.sh"'
MM2="$T/cp2/proj"; mkrepo "$MM2" >/dev/null 2>&1
SEN2="$T/sentinella2"; mkdir -p "$SEN2/a" && echo s > "$SEN2/a/f.txt" && echo t > "$SEN2/g.txt"
s0=$(sen_s "$SEN2")
(cd "$MM2" && bash "$MU/scripts/ciclo-worktree.sh" crea .claude/.ai-workflow/spec-uno.md >/dev/null 2>&1)
W2M="$(dirname "$(canon "$MM2")")/proj-fic-uno"
mkdir -p "$W2M/modules/x" && mkjunction "$SEN2" "$W2M/modules/x/node_modules"
(cd "$MM2" && bash "$MU/scripts/ciclo-worktree.sh" rimuovi uno >/dev/null 2>&1)
if [ $SEGUE -eq 1 ]; then
  check "controprova 2: senza links_left la sentinella NON e' intatta" '[ "$(sen_s "$SEN2")" != "$s0" ]'
elif [ "$SONDA" = guasta ]; then
  echo "NON ESEGUITA [controprova 2]: la sonda della giunzione non si e' preparata (check rosso sopra)"
elif [ $TWIN -eq 1 ] && [ $SONDA_RIMOSSO = 0 ]; then   # 1.6.0: a junction that git does not follow nor remove
  echo "SALTATO [controprova 2]: sonda $SONDA, worktree NON rimosso: questo git non rimuove il worktree che contiene la giunzione, nessun effetto da misurare (sentinella intatta: $([ "$(sen_s "$SEN2")" = "$s0" ] && echo si || echo no))"
else   # pk08: with a symlink (or a junction that git removes without following) the sentinel stays; the mutant's
  # effect is that the removal no longer stops (case 9b)
  check "controprova 2 ($([ $TWIN -eq 1 ] && echo "giunzione non seguita" || echo symlink)): senza links_left il collegamento non registrato non ferma la rimozione" '[ ! -e "$W2M" ]'
fi

# 12. pk04b-2: links and preparati from maat.json, not from hardcoded lists. A maat.json without collega_nel_worktree
# and without preparati: no link and no .nuxt file copied, even though the main tree has
# modules/api/.venv and modules/app/apps/admin/.nuxt/tsconfig.json; no preparazione warning.
. "$HERE/python.sh"
"$FIC_PY" -c 'import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
for m in c["moduli"]:
    m.pop("collega_nel_worktree", None); m.pop("preparati", None)
json.dump(c, open(sys.argv[2], "w", encoding="utf-8"), indent=1)' "$ROOT/examples/nuxt-fastapi.maat.json" "$T/conf-vuota.json"
caso_vuota() { # $1 ciclo-worktree script, $2 repo folder → 0 if no link, no copy, no warning
  local MV=$2 out rc W
  mkrepo "$MV" "$T/conf-vuota.json" >/dev/null 2>&1 || { echo "repo finto non creato"; return 2; }
  out=$( (cd "$MV" && bash "$1" crea .claude/.ai-workflow/spec-uno.md) 2>&1); rc=$?
  W="$(dirname "$(canon "$MV")")/proj-fic-uno"
  [ $rc -eq 0 ] || { printf '%s\n' "$out"; return 2; }
  [ -z "$(find "$W" -type l -print -quit)" ] && [ ! -e "$W/modules/api/.venv" ] && [ ! -e "$W/node_modules" ] &&
    [ ! -e "$W/modules/app/apps/admin/.nuxt/tsconfig.json" ] && ! printf '%s' "$out" | grep -q "AVVISO.*preparazione\|nuxi"
}
check "maat.json senza collega_nel_worktree e preparati: nessun collegamento, nessun preparato copiato, nessun avviso" 'caso_vuota "$CW" "$T/v1/proj"'
# the example: the main tree's preparati are missing => the warning names the declared preparazione
MP="$T/v2/proj"; mkrepo "$MP" >/dev/null 2>&1; rm -f "$MP/modules/app/apps/admin/.nuxt/tsconfig.json"
out=$( (cd "$MP" && bash "$CW" crea .claude/.ai-workflow/spec-uno.md) 2>&1); rc=$?
check "preparati assenti nel tree principale: avviso con la preparazione del modulo, nessuna copia" \
  '[ $rc -eq 0 ] && printf "%s" "$out" | grep -qF "AVVISO — il tree principale non ha modules/app/apps/admin/.nuxt/tsconfig.json: lancia '"'"'npx nuxi prepare'"'"' in modules/app/apps/admin del tree principale, poi crea di nuovo" && [ ! -e "$(dirname "$(canon "$MP")")/proj-fic-uno/modules/app/apps/admin/.nuxt/components.d.ts" ]' || printf '%s\n' "$out"
# counterproofs by mutation: (3) dep_links with modules/api/.venv hardcoded => in the «vuota» case a link appears;
# (4) the old hardcoded .nuxt copy => the tsconfig appears in the worktree. Both: the «vuota» case red
cp "$HERE/worktree-lib.sh" "$MU/scripts/worktree-lib.sh"; cp "$CW" "$MU/scripts/ciclo-worktree.sh"
sed -i '/^  local r=\$1 k g p$/a\  { [ -e "$r/modules/api/.venv" ] || [ -L "$r/modules/api/.venv" ]; } \&\& printf "%s\\n" modules/api/.venv   # MUTANTE' "$MU/scripts/worktree-lib.sh"
check "premessa: mutazione 3 applicata" 'grep -q "# MUTANTE" "$MU/scripts/worktree-lib.sh"'
check "controprova 3: con modules/api/.venv cablato in dep_links il caso «vuota» e' rosso" '! caso_vuota "$MU/scripts/ciclo-worktree.sh" "$T/v3/proj"'
cp "$HERE/worktree-lib.sh" "$MU/scripts/worktree-lib.sh"
sed -i '/^  deps_fp_check "\$MAINC" "\$WT"/i\  NUXT=modules/app/apps/admin/.nuxt; [ -f "$MAINC/$NUXT/tsconfig.json" ] \&\& mkdir -p "$WT/$NUXT" \&\& cp "$MAINC/$NUXT/tsconfig.json" "$WT/$NUXT/"   # MUTANTE' "$MU/scripts/ciclo-worktree.sh"
check "premessa: mutazione 4 applicata" 'grep -q "# MUTANTE" "$MU/scripts/ciclo-worktree.sh"'
check "controprova 4: con la copia di .nuxt cablata il caso «vuota» e' rosso" '! caso_vuota "$MU/scripts/ciclo-worktree.sh" "$T/v4/proj"'

# 13. review pk04b-2, minor 3: ALL preparati with wildcards => empty guide file. The empty field travels as «-» (with
# IFS=$'\t' two tabs in a row are a single separator): the module is skipped, no warning and no preparato copied.
# Without the placeholder the preparazione would become the guide file («il tree principale non ha …/npx nuxi prepare»).
"$FIC_PY" -c 'import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
for m in c["moduli"]:
    if m.get("preparati"):
        m["preparati"] = [".nuxt/*.d.ts"]
json.dump(c, open(sys.argv[2], "w", encoding="utf-8"), indent=1)' "$ROOT/examples/nuxt-fastapi.maat.json" "$T/conf-jolly.json"
caso_jolly() { # $1 ciclo-worktree script, $2 repo folder → 0 if no preparazione warning and no copy
  local MV=$2 out rc W
  mkrepo "$MV" "$T/conf-jolly.json" >/dev/null 2>&1 || { echo "repo finto non creato"; return 2; }
  out=$( (cd "$MV" && bash "$1" crea .claude/.ai-workflow/spec-uno.md) 2>&1); rc=$?
  W="$(dirname "$(canon "$MV")")/proj-fic-uno"
  [ $rc -eq 0 ] && [ -d "$W" ] || { printf '%s\n' "$out"; return 2; }
  ! printf '%s' "$out" | grep -q "il tree principale non ha" && [ ! -e "$W/modules/app/apps/admin/.nuxt/components.d.ts" ]
}
check "preparati tutti con jolly: file guida vuoto, modulo saltato senza avvisi ne' copie" 'caso_jolly "$CW" "$T/v5/proj"'
# counterproof 5: without the placeholder (v(x) returns the field as is) the fields shift and the case is red
cp "$CW" "$MU/scripts/ciclo-worktree.sh"
sed 's/^    return x or "-"$/    return x   # MUTANTE/' "$HERE/worktree-lib.sh" > "$MU/scripts/worktree-lib.sh"
check "premessa: mutazione 5 applicata" 'grep -q "# MUTANTE" "$MU/scripts/worktree-lib.sh"'
check "controprova 5: senza il segnaposto dei campi vuoti il caso «jolly» e' rosso" 'caso_jolly "$MU/scripts/ciclo-worktree.sh" "$T/v6/proj"; [ $? -eq 1 ]'
cp "$HERE/worktree-lib.sh" "$MU/scripts/worktree-lib.sh"

# 14. 1.6.1: a mother spec (Figlie:) brings its rings. crea copies every spec-<figlia>.md and its run dir; riporta brings
# them back, each checked on its own and all checks before any copy; rimuovi stops on a ring not brought back; a ring
# missing in the main tree is a STOP before anything is created. A "Figlie:" inside a fence is not the line (as driver.py).
# Counterproof: the 1.6.0 script (origin/main before the fix, or the mutant without the rings) leaves the rings out.
AIWR=.claude/.ai-workflow
mkmadre() { # $1 repo: mother + 2 rings (f1 with a run dir), and a mother with a missing ring
  printf '# madre\n```\nFiglie: spec-finta\n```\nFiglie: spec-f1, spec-f2.\n## Requisiti\n' > "$1/$AIWR/spec-madre.md"
  printf '# f1\n' > "$1/$AIWR/spec-f1.md"; printf '# f2\n' > "$1/$AIWR/spec-f2.md"; printf '# finta\n' > "$1/$AIWR/spec-finta.md"
  mkdir -p "$1/$AIWR/spec-f1.run/log" && echo 0 > "$1/$AIWR/spec-f1.run/log/01-plan.exit"
  printf '# madre2\nChildren: spec-f1 spec-manca\n' > "$1/$AIWR/spec-madre2.md"
}
caso_catena() { # $1 ciclo-worktree script, $2 repo folder → 0 if the rings travel with the mother; the reason on stdout
  local MC=$2 S=$1 out rc W
  mkrepo "$MC" >/dev/null 2>&1 && mkmadre "$MC" || { echo "repo finto non creato"; return 2; }
  out=$( (cd "$MC" && bash "$S" crea "$AIWR/spec-madre.md") 2>&1); rc=$?
  W="$(dirname "$(canon "$MC")")/proj-fic-madre"
  [ $rc -eq 0 ] && [ -d "$W" ] || { echo "crea: rc $rc"; printf '%s\n' "$out"; return 2; }
  [ -f "$W/$AIWR/spec-f1.md" ] && [ -f "$W/$AIWR/spec-f2.md" ] || { echo "crea: anelli non copiati"; return 1; }
  [ -f "$W/$AIWR/spec-f1.run/log/01-plan.exit" ] && [ ! -e "$W/$AIWR/spec-f2.run" ] || { echo "crea: run dir dell'anello"; return 1; }
  [ ! -e "$W/$AIWR/spec-finta.md" ] || { echo "crea: la riga Figlie: dentro il blocco di codice è stata letta"; return 1; }
  # the cycle works on the rings in the worktree; resume keeps them (worktree wins)
  echo '## Piano f1' >> "$W/$AIWR/spec-f1.md"; echo 0 > "$W/$AIWR/spec-f1.run/log/02-impl.exit"
  echo '## Piano f2' >> "$W/$AIWR/spec-f2.md"
  out=$( (cd "$MC" && bash "$S" crea "$AIWR/spec-madre.md") 2>&1) && grep -q 'Piano f1' "$W/$AIWR/spec-f1.md" ||
    { echo "ripresa: l'anello del worktree sovrascritto"; printf '%s\n' "$out"; return 1; }
  out=$( (cd "$MC" && bash "$S" rimuovi madre) 2>&1); rc=$?
  [ $rc -eq 3 ] && printf '%s' "$out" | grep -q "spec-f1" || { echo "rimuovi con gli anelli non riportati: rc $rc"; printf '%s\n' "$out"; return 1; }
  out=$( (cd "$MC" && bash "$S" riporta madre) 2>&1); rc=$?
  [ $rc -eq 0 ] || { echo "riporta: rc $rc"; printf '%s\n' "$out"; return 1; }
  cmp -s "$W/$AIWR/spec-f1.md" "$MC/$AIWR/spec-f1.md" && cmp -s "$W/$AIWR/spec-f2.md" "$MC/$AIWR/spec-f2.md" &&
    [ -f "$MC/$AIWR/spec-f1.run/log/02-impl.exit" ] || { echo "riporta: anelli non tornati"; return 1; }
  # a ring changed in the main tree after the copy: STOP, and nothing copied (not even the mother)
  echo 'nota a mano' >> "$MC/$AIWR/spec-f2.md"; echo '## Review madre' >> "$W/$AIWR/spec-madre.md"
  out=$( (cd "$MC" && bash "$S" riporta madre) 2>&1); rc=$?
  [ $rc -eq 3 ] && printf '%s' "$out" | grep -q "spec-f2.md" && ! grep -q 'Review madre' "$MC/$AIWR/spec-madre.md" ||
    { echo "riporta con un anello cambiato nel principale: rc $rc"; printf '%s\n' "$out"; return 1; }
  # a ring missing in the main tree: STOP before creating anything
  out=$( (cd "$MC" && bash "$S" crea "$AIWR/spec-madre2.md") 2>&1); rc=$?
  [ $rc -eq 3 ] && printf '%s' "$out" | grep -q "spec-manca.md" && [ ! -e "$(dirname "$(canon "$MC")")/proj-fic-madre2" ] &&
    ! git -C "$MC" show-ref -q --verify refs/heads/fic/madre2 || { echo "anello mancante: rc $rc"; printf '%s\n' "$out"; return 1; }
  return 0
}
r=$(caso_catena "$CW" "$T/cat/proj"); rc=$?
check "catena: crea copia gli anelli (e la loro run dir), riporta li riporta, rimuovi e l'anello mancante fanno STOP" '[ $rc -eq 0 ]' || printf '  %s\n' "$r"
# counterproof 6: the mutant without the rings (carica_figlie that loads nothing) is red at the first check
cp "$CW" "$MU/scripts/ciclo-worktree.sh" && cp "$HERE/worktree-lib.sh" "$MU/scripts/worktree-lib.sh"
sed -i 's/^  FIGLIE=()$/  FIGLIE=(); return 0   # MUTANTE/' "$MU/scripts/ciclo-worktree.sh"
check "premessa: mutazione 6 applicata" 'grep -q "# MUTANTE" "$MU/scripts/ciclo-worktree.sh"'
r=$(caso_catena "$MU/scripts/ciclo-worktree.sh" "$T/cat2/proj"); rc=$?
check "controprova 6: senza gli anelli il caso «catena» è rosso (crea non li copia)" '[ $rc -eq 1 ] && printf "%s" "$r" | grep -q "anelli non copiati"' || printf '  %s\n' "$r"
cp "$CW" "$MU/scripts/ciclo-worktree.sh"

echo "ciclo-worktree.test.sh: $((n - fail))/$n ok"
[ $fail -eq 0 ]
