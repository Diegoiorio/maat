#!/usr/bin/env bash
# ciclo-worktree.test.sh — test di script/fic/ciclo-worktree.sh in un repository git FINTO in una cartella
# temporanea, con HOME finta e senza WSL (FIC_WT_WSL=0): nessun worktree, branch o collegamento nel repository vero.
#   bash script/fic/ciclo-worktree.test.sh
#   CW=/percorso/variante.sh bash script/fic/ciclo-worktree.test.sh   # la variante sta accanto a worktree-lib.sh
# Casi: crea (worktree, spec e run dir copiate, collegamenti, nessuna copia fisica di node_modules, .nuxt), ripresa
# (anche con un file di dipendenze non tracciato), worktree altrui, dipendenze diverse, riporta (allineamento della
# run dir, STOP se spec o run dir del tree principale sono cambiate), rimuovi con modifiche / con spec o run dir non
# riportate / con lock, plan.lock vivo o fase in corso / con un collegamento NON registrato (sentinella intatta) /
# pulito (node_modules della fonte INTATTO: voci e contenuto), lock per worktree (run-phase.sh --lock-status),
# --forza --branch, copie WSL del worktree e delle corsie cancellate davvero (forget_mirror, HOME finta).
# Controprove per mutazione, SOLO nei repo finti: (1) rimuovi senza scollega_e_verifica ⇒ il node_modules della fonte
# si svuota (git worktree remove segue le junction), il controllo «intatto» va rosso; (2) links_left() { return 0; }
# ⇒ un collegamento non registrato non ferma piu' la rimozione e la sentinella si svuota.
# ⚠️ Pensato per WINDOWS (Git Bash): collegamenti = junction (mklink /J), come nel repository vero; le controprove
# misurano che `git worktree remove` segue le junction. Altrove (Linux, pk08) i collegamenti sono symlink, che git
# non segue: la controprova 1 si dichiara SALTATO, la 2 misura che la rimozione non si ferma piu'. Limite dichiarato: un symlink TRACCIATO dal repository sarebbe
# un collegamento rimasto per `rimuovi` (falso positivo, STOP: direzione sicura); il repository oggi non ne ha.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)   # radice del plugin
CW=${CW:-$HERE/ciclo-worktree.sh}
RPS=$ROOT/scripts/run-phase.sh
# ciclo-worktree.sh chiama run-phase.sh e cycle-state.sh del plugin (MAAT_SCRIPTS), non del worktree (pk04a-1,
# schema H): il repo finto non ne ha copie. I mutanti in $T trovano il plugin da MAAT_ROOT
export MAAT_ROOT=$ROOT
T=$(mktemp -d)
# pk08: fuori da Windows (Linux) i collegamenti sono symlink, come in worktree-lib.sh: niente cmd.exe ne' cygpath
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) TWIN=1 ;; *) TWIN=0 ;; esac
unlink_all() { # i collegamenti rimasti sotto $T, tolti SENZA seguirli (prima di rm -rf)
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

mkrepo() { # $1 cartella, $2 maat.json (default l'esempio nuxt-fastapi): repository finto con dipendenze
  # installate finte e una spec; collegamenti, file delle dipendenze e preparati li dichiara la sua maat.json
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
  # dipendenze installate (gitignorate): quelle che il worktree deve COLLEGARE
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
mkjunction() { # junction su Windows, symlink altrove (la variante di link_dep in worktree-lib.sh)
  if [ $TWIN -eq 1 ]; then MSYS2_ARG_CONV_EXCL='*' cmd.exe /c mklink /J "$(cygpath -w "$2")" "$(cygpath -w "$1")" >/dev/null
  else ln -s "$1" "$2"; fi
}
rmjunction() { if [ $TWIN -eq 1 ]; then MSYS2_ARG_CONV_EXCL='*' cmd.exe /c rmdir "$(cygpath -w "$1")" >/dev/null 2>&1; else rm -f "$1"; fi; }
nm_count() { find "$1/modules/app/node_modules" "$1/node_modules" "$1/modules/app/apps/admin/node_modules" "$1/modules/api/.venv" | wc -l; }
nm_sum() { find "$1/modules/app/node_modules" "$1/node_modules" "$1/modules/app/apps/admin/node_modules" "$1/modules/api/.venv" -type f -exec cksum {} + | sort; }
cw() { (cd "$M" && bash "$CW" "$@"); }   # dal tree principale finto

M="$T/proj"; mkrepo "$M" >/dev/null 2>&1 || { echo "FAIL: repo finto non creato"; exit 1; }
MC=$(canon "$M"); PAR=$(dirname "$MC"); W1="$PAR/proj-fic-uno"
cnt0=$(nm_count "$M") sum0=$(nm_sum "$M") ls0=$(ls "$M/modules/app/node_modules" | wc -l)

# 1. crea: worktree sul branch fic/uno, spec e run dir copiate, collegamenti, nessuna copia fisica
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

# 2. crea di nuovo: ripresa, la spec del worktree vince
echo "## Piano (dal ciclo)" >> "$W1/.claude/.ai-workflow/spec-uno.md"
out=$(cw crea .claude/.ai-workflow/spec-uno.md 2>&1); rc=$?
check "crea due volte → ripresa (0)" '[ $rc -eq 0 ] && printf "%s" "$out" | grep -q "ripresa"' || printf '%s\n' "$out"
check "  la spec del worktree non e' sovrascritta" 'grep -q "Piano (dal ciclo)" "$W1/.claude/.ai-workflow/spec-uno.md"'
check "  collegamenti ancora collegamenti" '[ -L "$W1/modules/app/node_modules" ]'
printf '{"name":"nuovo"}\n' > "$W1/modules/app/packages/ui/package-lock.json"   # dipendenza aggiunta, non tracciata
out=$(cw crea .claude/.ai-workflow/spec-uno.md 2>&1); rc=$?
check "ripresa con un file di dipendenze non tracciato nel worktree → STOP (3)" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "packages/ui/package-lock.json"' || printf '%s\n' "$out"
rm "$W1/modules/app/packages/ui/package-lock.json"

# 2b. pk09 (pilota su un secondo progetto): lanciato da DENTRO un worktree collegato (git dir ≠ git common dir) ⇒ rifiuto (3) per
# ogni sottocomando, col messaggio, nulla creato. Prima di pk09 risaliva al tree principale (--git-common-dir) e ne
# prendeva base, maat.json e spec: qui crea riprendeva il worktree (0) e stato rispondeva (0). Controprova: dal tree
# principale gli stessi comandi passano (i casi qui intorno e l'ultimo check sotto).
nwt0=$(git -C "$M" worktree list | wc -l)
# .claude/.ai-workflow e' gitignorata: git status non la vede, quindi se ne confronta l'elenco prima e dopo
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

# 3. worktree altrui con lo stesso nome ⇒ STOP, nulla toccato
W2="$PAR/proj-fic-due"
git -C "$M" worktree add -q -b fic/due "$W2" HEAD 2>/dev/null
out=$(cw crea .claude/.ai-workflow/spec-due.md 2>&1); rc=$?
check "worktree altrui con lo stesso nome → STOP (3)" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "STOP"' || printf '%s\n' "$out"
check "  nessun collegamento ne' spec nel worktree altrui" '[ ! -e "$W2/node_modules" ] && [ ! -e "$W2/.claude/.ai-workflow/spec-due.md" ]'
out=$(cw rimuovi due 2>&1); rc=$?
check "  rimuovi del worktree altrui → STOP, resta" '[ $rc -eq 3 ] && [ -d "$W2" ]'
git -C "$M" worktree remove "$W2" && git -C "$M" branch -q -D fic/due
mkdir -p "$PAR/proj-fic-due"   # una cartella qualunque con quel nome
out=$(cw crea .claude/.ai-workflow/spec-due.md 2>&1); rc=$?
check "cartella non-worktree con lo stesso nome → STOP (3)" '[ $rc -eq 3 ]'
rmdir "$PAR/proj-fic-due"

# 4. dipendenze diverse ⇒ STOP, nessun worktree, nessun branch
printf '{"lock":2}\n' > "$M/modules/app/package-lock.json"
out=$(cw crea .claude/.ai-workflow/spec-tre.md 2>&1); rc=$?
check "dipendenze diverse → STOP (3)" '[ $rc -eq 3 ] && printf "%s" "$out" | grep -q "modules/app/package-lock.json"' || printf '%s\n' "$out"
check "  nessun worktree, nessun branch" '[ ! -e "$PAR/proj-fic-tre" ] && ! git -C "$M" show-ref -q --verify refs/heads/fic/tre'
printf '{"lock":1}\n' > "$M/modules/app/package-lock.json"
check "  (ripristino: tree principale di nuovo pulito)" '[ -z "$(git -C "$M" status --porcelain)" ]'

# 5. riporta: spec e run dir nel tree principale; mai il codice
echo "Review status: APPROVED" >> "$W1/.claude/.ai-workflow/spec-uno.md"
echo 0 > "$W1/.claude/.ai-workflow/spec-uno.run/log/02-implement.exit"
echo "modifica del ciclo" >> "$W1/a.txt"
echo "# nota dell'utente" >> "$M/.claude/.ai-workflow/spec-uno.md"   # spec del tree principale cambiata dopo la copia
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

# 6. rimuovi con modifiche ⇒ rifiuto, niente toccato
out=$(cw rimuovi uno 2>&1); rc=$?
check "rimuovi con modifiche → rifiuto (3)" '[ $rc -eq 3 ] && [ -d "$W1" ] && [ -L "$W1/modules/app/node_modules" ]' || printf '%s\n' "$out"
git -C "$W1" checkout -q -- a.txt

# 6b. spec o run dir non riportate ⇒ STOP (salvo --forza); riporta ALLINEA la run dir; fasi vive ⇒ STOP
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
echo altro > "$RDM/log/99-altro.txt"; echo 0 > "$RD1/log/04-fix.exit"   # run dir principale cambiata dopo il riporta
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
# scambio della run dir fallito e ripristino fallito (mv finto che fallisce solo su *.nuova.* e *.vecchia.*):
# il messaggio nomina la vecchia, la nuova e' cancellata, nulla va perso
FMV="$T/fakemv"; mkdir -p "$FMV"
printf '#!/bin/bash\ncase "$1" in *.nuova.*|*.vecchia.*) echo "mv finto: fallisce $1" >&2; exit 1 ;; esac\nexec /usr/bin/mv "$@"\n' > "$FMV/mv"; chmod +x "$FMV/mv"
echo 0 > "$RD1/log/06-review.exit"
out=$( (cd "$M" && PATH="$FMV:$PATH" bash "$CW" riporta uno) 2>&1); rc=$?
vec=$(ls -d "$RDM".vecchia.* 2>/dev/null | head -1)
check "riporta con scambio e ripristino falliti → errore (2) che nomina la run dir precedente" '[ $rc -eq 2 ] && [ -n "$vec" ] && printf "%s" "$out" | grep -q "NON ripristinata" && printf "%s" "$out" | grep -qF "precedente e'"'"' in " && printf "%s" "$out" | grep -qF "$(basename "$vec")"'
check "  copia nuova cancellata, precedente conservata" '[ -z "$(ls -d "$RDM".nuova.* 2>/dev/null)" ] && [ -f "$vec/log/04-fix.exit" ]'
[ -n "$vec" ] && /usr/bin/mv "$vec" "$RDM"
out=$(cw riporta uno 2>&1); rc=$?
check "  rimessa a mano la precedente, riporta esce 0" '[ $rc -eq 0 ] && [ -f "$RDM/log/06-review.exit" ] && diff -rq "$RD1" "$RDM" >/dev/null' || printf '%s\n' "$out"

# 7. lock: ogni worktree ha il suo (git dir del worktree); due cicli non si bloccano a vicenda
W4="$PAR/proj-fic-quattro"
out=$(cw crea .claude/.ai-workflow/spec-quattro.md 2>&1); rc=$?
check "crea di un secondo worktree esce 0" '[ $rc -eq 0 ] && [ -d "$W4" ]' || printf '%s\n' "$out"
L1="$(git -C "$W1" rev-parse --absolute-git-dir)/full-implementation-cycle.lock"
mkdir -p "$L1" && printf 'pid=%s\ncpid=\nrun=x\nlabel=02-implement\n' "$$" > "$L1/owner"   # fase di codice viva nel worktree 1
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

# 8. rimuovi pulito: collegamenti tolti, node_modules della fonte INTATTO, worktree sparito, branch lasciato
out=$(cw rimuovi uno 2>&1); rc=$?
check "rimuovi esce 0" '[ $rc -eq 0 ]' || printf '%s\n' "$out"
check "  worktree sparito (cartella e git worktree list)" '[ ! -e "$W1" ] && ! git -C "$M" worktree list | grep -q "proj-fic-uno"'
check "  node_modules della fonte INTATTO: stesso numero di voci" '[ "$(nm_count "$M")" = "$cnt0" ] && [ "$(ls "$M/modules/app/node_modules" | wc -l)" = "$ls0" ]'
check "  e stesso contenuto" '[ "$(nm_sum "$M")" = "$sum0" ]'
check "  branch fic/uno lasciato (senza --branch)" 'git -C "$M" show-ref -q --verify refs/heads/fic/uno'
out=$(cw rimuovi quattro --branch 2>&1); rc=$?
check "rimuovi --branch: worktree e branch spariti" '[ $rc -eq 0 ] && [ ! -e "$W4" ] && ! git -C "$M" show-ref -q --verify refs/heads/fic/quattro' || printf '%s\n' "$out"

# 9. --forza: modifiche scartate, fonte intatta
W5="$PAR/proj-fic-cinque"
cw crea .claude/.ai-workflow/spec-cinque.md >/dev/null 2>&1
echo sporco >> "$W5/a.txt"; echo nuovo > "$W5/nuovo.txt"
mkdir -p "$W5/.claude/.ai-workflow/spec-cinque.run/log" && date > "$W5/.claude/.ai-workflow/spec-cinque.run/log/07-fix.running"
out=$(cw rimuovi cinque --forza --branch 2>&1); rc=$?
check "rimuovi --forza con modifiche esce 0" '[ $rc -eq 0 ] && [ ! -e "$W5" ]' || printf '%s\n' "$out"
check "  e avvisa della fase in corso ignorata, con l'etichetta" 'printf "%s" "$out" | grep -q "AVVISO.*07-fix"'
check "  fonte ancora intatta" '[ "$(nm_count "$M")" = "$cnt0" ] && [ "$(nm_sum "$M")" = "$sum0" ]'

# 9b. collegamento residuo NON registrato (fuori da dep_links) ⇒ STOP, worktree resta, sentinella intatta
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

# 9c. copie WSL del worktree cancellate DAVVERO, corsie comprese (forget_mirror della lib, script su stdin; qui bash
# locale con la HOME finta), mai ~/fic-mirror. Prima del 2026-09-30 le corsie restavano ($k espanso a vuoto).
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
cw rimuovi sette --branch >/dev/null 2>&1
check "tree principale pulito alla fine" '[ -z "$(git -C "$M" status --porcelain)" ]'

# 10. CONTROPROVA per mutazione (solo nel repo finto): rimuovi senza scollega_e_verifica ⇒ fonte svuotata
MU="$T/mut"; mkdir -p "$MU/scripts/lib"
cp "$HERE/worktree-lib.sh" "$ROOT/scripts/fic-mirror.sh" "$ROOT/scripts/python.sh" "$MU/scripts/"
cp "$ROOT/scripts/lib/maat-paths.sh" "$MU/scripts/lib/"
sed 's/^scollega_e_verifica "\$WT" || stop .*$/: MUTANTE — nessuno scollegamento/' "$CW" > "$MU/scripts/ciclo-worktree.sh"
check "premessa: mutazione applicata" '! cmp -s "$CW" "$MU/scripts/ciclo-worktree.sh" && grep -q "^: MUTANTE" "$MU/scripts/ciclo-worktree.sh"'
MM="$T/cp/proj"; mkrepo "$MM" >/dev/null 2>&1
c0=$(nm_count "$MM")
(cd "$MM" && bash "$MU/scripts/ciclo-worktree.sh" crea .claude/.ai-workflow/spec-uno.md >/dev/null 2>&1)
(cd "$MM" && bash "$MU/scripts/ciclo-worktree.sh" rimuovi uno >/dev/null 2>&1)
c1=$(nm_count "$MM" 2>/dev/null)
if [ $TWIN -eq 1 ]; then
  check "controprova: senza lo scollegamento il node_modules della fonte NON e' intatto ($c0 → $c1 voci)" '[ "$c1" != "$c0" ]'
else   # pk08: git worktree remove toglie un symlink senza seguirlo, la fonte resta intatta anche col mutante
  echo "SALTATO [controprova 1]: con i symlink (non Windows) git worktree remove non segue il collegamento ($c0 → $c1 voci): nessun effetto da misurare"
fi

# 11. CONTROPROVA per mutazione (solo nel repo finto): links_left() { return 0; } ⇒ il collegamento non registrato non
# ferma piu' la rimozione e git worktree remove svuota la sentinella
sed '/^scollega_e_verifica() {/i links_left() { return 0; }  # MUTANTE' "$CW" > "$MU/scripts/ciclo-worktree.sh"
check "premessa: mutazione 2 applicata" 'grep -q "^links_left() { return 0; }  # MUTANTE" "$MU/scripts/ciclo-worktree.sh"'
MM2="$T/cp2/proj"; mkrepo "$MM2" >/dev/null 2>&1
SEN2="$T/sentinella2"; mkdir -p "$SEN2/a" && echo s > "$SEN2/a/f.txt" && echo t > "$SEN2/g.txt"
s0=$(sen_s "$SEN2")
(cd "$MM2" && bash "$MU/scripts/ciclo-worktree.sh" crea .claude/.ai-workflow/spec-uno.md >/dev/null 2>&1)
W2M="$(dirname "$(canon "$MM2")")/proj-fic-uno"
mkdir -p "$W2M/modules/x" && mkjunction "$SEN2" "$W2M/modules/x/node_modules"
(cd "$MM2" && bash "$MU/scripts/ciclo-worktree.sh" rimuovi uno >/dev/null 2>&1)
if [ $TWIN -eq 1 ]; then
  check "controprova 2: senza links_left la sentinella NON e' intatta" '[ "$(sen_s "$SEN2")" != "$s0" ]'
else   # pk08: col symlink la sentinella resta; l'effetto del mutante e' che la rimozione non si ferma piu' (caso 9b)
  check "controprova 2 (symlink): senza links_left il collegamento non registrato non ferma la rimozione" '[ ! -e "$W2M" ]'
fi

# 12. pk04b-2: collegamenti e preparati da maat.json, non da elenchi cablati. Una maat.json senza collega_nel_worktree
# e senza preparati: nessun collegamento e nessun file di .nuxt copiato, anche se il tree principale ha
# modules/api/.venv e modules/app/apps/admin/.nuxt/tsconfig.json; nessun avviso di preparazione.
. "$HERE/python.sh"
"$FIC_PY" -c 'import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
for m in c["moduli"]:
    m.pop("collega_nel_worktree", None); m.pop("preparati", None)
json.dump(c, open(sys.argv[2], "w", encoding="utf-8"), indent=1)' "$ROOT/examples/nuxt-fastapi.maat.json" "$T/conf-vuota.json"
caso_vuota() { # $1 script ciclo-worktree, $2 cartella del repo → 0 se nessun collegamento, nessuna copia, nessun avviso
  local MV=$2 out rc W
  mkrepo "$MV" "$T/conf-vuota.json" >/dev/null 2>&1 || { echo "repo finto non creato"; return 2; }
  out=$( (cd "$MV" && bash "$1" crea .claude/.ai-workflow/spec-uno.md) 2>&1); rc=$?
  W="$(dirname "$(canon "$MV")")/proj-fic-uno"
  [ $rc -eq 0 ] || { printf '%s\n' "$out"; return 2; }
  [ -z "$(find "$W" -type l -print -quit)" ] && [ ! -e "$W/modules/api/.venv" ] && [ ! -e "$W/node_modules" ] &&
    [ ! -e "$W/modules/app/apps/admin/.nuxt/tsconfig.json" ] && ! printf '%s' "$out" | grep -q "AVVISO.*preparazione\|nuxi"
}
check "maat.json senza collega_nel_worktree e preparati: nessun collegamento, nessun preparato copiato, nessun avviso" 'caso_vuota "$CW" "$T/v1/proj"'
# l'esempio: i preparati del tree principale mancano => l'avviso nomina la preparazione dichiarata
MP="$T/v2/proj"; mkrepo "$MP" >/dev/null 2>&1; rm -f "$MP/modules/app/apps/admin/.nuxt/tsconfig.json"
out=$( (cd "$MP" && bash "$CW" crea .claude/.ai-workflow/spec-uno.md) 2>&1); rc=$?
check "preparati assenti nel tree principale: avviso con la preparazione del modulo, nessuna copia" \
  '[ $rc -eq 0 ] && printf "%s" "$out" | grep -qF "AVVISO — il tree principale non ha modules/app/apps/admin/.nuxt/tsconfig.json: lancia '"'"'npx nuxi prepare'"'"' in modules/app/apps/admin del tree principale, poi crea di nuovo" && [ ! -e "$(dirname "$(canon "$MP")")/proj-fic-uno/modules/app/apps/admin/.nuxt/components.d.ts" ]' || printf '%s\n' "$out"
# controprove per mutazione: (3) dep_links con modules/api/.venv cablato => nel caso «vuota» compare un collegamento;
# (4) la copia di .nuxt cablata di prima => compare il tsconfig nel worktree. Entrambe: il caso «vuota» rosso
cp "$HERE/worktree-lib.sh" "$MU/scripts/worktree-lib.sh"; cp "$CW" "$MU/scripts/ciclo-worktree.sh"
sed -i '/^  local r=\$1 k g p$/a\  { [ -e "$r/modules/api/.venv" ] || [ -L "$r/modules/api/.venv" ]; } \&\& printf "%s\\n" modules/api/.venv   # MUTANTE' "$MU/scripts/worktree-lib.sh"
check "premessa: mutazione 3 applicata" 'grep -q "# MUTANTE" "$MU/scripts/worktree-lib.sh"'
check "controprova 3: con modules/api/.venv cablato in dep_links il caso «vuota» e' rosso" '! caso_vuota "$MU/scripts/ciclo-worktree.sh" "$T/v3/proj"'
cp "$HERE/worktree-lib.sh" "$MU/scripts/worktree-lib.sh"
sed -i '/^  deps_fp_check "\$MAINC" "\$WT"/i\  NUXT=modules/app/apps/admin/.nuxt; [ -f "$MAINC/$NUXT/tsconfig.json" ] \&\& mkdir -p "$WT/$NUXT" \&\& cp "$MAINC/$NUXT/tsconfig.json" "$WT/$NUXT/"   # MUTANTE' "$MU/scripts/ciclo-worktree.sh"
check "premessa: mutazione 4 applicata" 'grep -q "# MUTANTE" "$MU/scripts/ciclo-worktree.sh"'
check "controprova 4: con la copia di .nuxt cablata il caso «vuota» e' rosso" '! caso_vuota "$MU/scripts/ciclo-worktree.sh" "$T/v4/proj"'

# 13. review pk04b-2, minor 3: preparati TUTTI con jolly => file guida vuoto. Il campo vuoto viaggia come «-» (con
# IFS=$'\t' due tab di fila sono un solo separatore): il modulo si salta, nessun avviso e nessun preparato copiato.
# Senza segnaposto la preparazione diventerebbe il file guida («il tree principale non ha …/npx nuxi prepare»).
"$FIC_PY" -c 'import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
for m in c["moduli"]:
    if m.get("preparati"):
        m["preparati"] = [".nuxt/*.d.ts"]
json.dump(c, open(sys.argv[2], "w", encoding="utf-8"), indent=1)' "$ROOT/examples/nuxt-fastapi.maat.json" "$T/conf-jolly.json"
caso_jolly() { # $1 script ciclo-worktree, $2 cartella del repo → 0 se nessun avviso di preparazione e nessuna copia
  local MV=$2 out rc W
  mkrepo "$MV" "$T/conf-jolly.json" >/dev/null 2>&1 || { echo "repo finto non creato"; return 2; }
  out=$( (cd "$MV" && bash "$1" crea .claude/.ai-workflow/spec-uno.md) 2>&1); rc=$?
  W="$(dirname "$(canon "$MV")")/proj-fic-uno"
  [ $rc -eq 0 ] && [ -d "$W" ] || { printf '%s\n' "$out"; return 2; }
  ! printf '%s' "$out" | grep -q "il tree principale non ha" && [ ! -e "$W/modules/app/apps/admin/.nuxt/components.d.ts" ]
}
check "preparati tutti con jolly: file guida vuoto, modulo saltato senza avvisi ne' copie" 'caso_jolly "$CW" "$T/v5/proj"'
# controprova 5: senza segnaposto (v(x) restituisce il campo com'e') i campi slittano e il caso e' rosso
cp "$CW" "$MU/scripts/ciclo-worktree.sh"
sed 's/^    return x or "-"$/    return x   # MUTANTE/' "$HERE/worktree-lib.sh" > "$MU/scripts/worktree-lib.sh"
check "premessa: mutazione 5 applicata" 'grep -q "# MUTANTE" "$MU/scripts/worktree-lib.sh"'
check "controprova 5: senza il segnaposto dei campi vuoti il caso «jolly» e' rosso" 'caso_jolly "$MU/scripts/ciclo-worktree.sh" "$T/v6/proj"; [ $? -eq 1 ]'
cp "$HERE/worktree-lib.sh" "$MU/scripts/worktree-lib.sh"

echo "ciclo-worktree.test.sh: $((n - fail))/$n ok"
[ $fail -eq 0 ]
