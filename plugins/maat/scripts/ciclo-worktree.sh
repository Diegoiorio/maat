#!/usr/bin/env bash
# ciclo-worktree.sh — /full-implementation-cycle in un git worktree DEDICATO (flag --worktree), per far girare il
# ciclo mentre altre sessioni lavorano nel tree principale: un loro `git add -A` non committa i file del ciclo a
# meta', e la review del ciclo non vede nel diff i file di altri flussi.
#
#   ciclo-worktree.sh crea <spec> [--base <ref>]      crea (o riprende) il worktree del ciclo; ultima riga: il percorso
#   ciclo-worktree.sh stato <nome>                    dove sta, branch, fase del ciclo, file modificati
#   ciclo-worktree.sh riporta <nome> [--forza]        spec e run dir del worktree → tree principale (mai il codice)
#   ciclo-worktree.sh rimuovi <nome> [--branch] [--forza]
#
# Il repository e' quello della cartella corrente, che deve essere il TREE PRINCIPALE: da un worktree collegato
# (git dir ≠ git common dir) ogni sottocomando e' rifiutato con STOP (pk09). <nome> = la spec senza `spec-` e `.md`.
#
# crea, in ordine:
#   1. worktree `<padre>/<repo>-fic-<nome>` sul branch `fic/<nome>` da --base (default HEAD del tree principale).
#      Se il percorso esiste: ripresa se e' suo (marcatore sotto), altrimenti STOP. Branch `fic/<nome>` gia'
#      esistente senza il suo worktree: STOP. Marcatore di proprieta' DENTRO il worktree:
#      `<cartelle.lavoro>/spec-<nome>.worktree` (default .claude/.ai-workflow; gitignorato dalla regola spec-*, verificato: mai superficie di
#      review), con il percorso, il branch, la base e l'impronta della spec del tree principale alla copia;
#   2. PRIMA di creare qualunque cosa: i file che decidono le dipendenze (i file di `file_dipendenze` dei moduli di
#      maat.json) devono coincidere fra la base e il working tree principale (deps_diff, la stessa logica di
#      replay.sh). Se no: STOP, niente worktree — mai collegare dipendenze sbagliate;
#   3. COLLEGA, mai copia ne' installa, le cartelle di `collega_nel_worktree` dei moduli presenti nel tree
#      principale: junction su Windows, symlink altrove (worktree-lib.sh, condivisa con corpus/replay.sh); .git con
#      gitdir relativo (il git di WSL lo legge);
#   4. copia la spec e, se c'e', la sua run dir `spec-<nome>.run/` (gitignorate: il checkout non le porta); in
#      ripresa quelle del worktree vincono e non si sovrascrivono;
#   5. copia dal tree principale i `preparati` del modulo (dipendenze uguali, verificato al passo 2), se il file
#      guida (il primo glob senza caratteri jolly) c'e' li' e manca nel worktree: il lint e i test della copia li
#      leggono; se manca nel tree principale avvisa di lanciarvi la `preparazione` del modulo. Un modulo senza
#      preparati: nessuna copia, nessun avviso;
#   6. verifica la copia WSL del worktree (~/fic-mirror-<hash>) per il modulo con `copia`: la semina delle
#      dipendenze della sua radice_pacchetti in hardlink da ~/fic-mirror (fic_seed_node_modules di fic-mirror.sh,
#      la stessa del primo run di test-fast.sh) e il file guida dei suoi preparati visto da WSL. FIC_WT_WSL=0 la
#      salta (test);
#   7. stampa il percorso del worktree (ultima riga di stdout).
# riporta: ALLINEA nel tree principale la spec (piano, review, righe di stato) e la run dir del worktree, al solito
#   posto (.claude/.ai-workflow/), per cycle-report.py e per l'utente: la run dir si copia in una cartella
#   temporanea accanto e prende il posto della vecchia (niente fusione: un file tolto nel worktree sparisce anche
#   li'). Non tocca il codice. STOP se la spec o la run dir del tree principale sono cambiate dopo la copia (impronte
#   nel marcatore: qualcuno ci ha lavorato li'), salvo --forza.
# rimuovi, in ordine: STOP se una fase del worktree e' viva — lock delle fasi di codice (run-phase.sh --lock-status),
#   <run-dir>/plan.lock con un pid vivo (mai forzabile) — o se una fase risulta in corso (log/*.running senza .exit:
#   viva, o morta senza chiudere; --forza per procedere); STOP se il worktree ha modifiche non committate, o se la
#   sua spec o la sua run dir non sono riportate nel tree principale (cmp, diff -rq), salvo --forza (che le perde);
#   copie WSL del worktree cancellate (corsie comprese); collegamenti tolti (solo il collegamento, mai ricorsivo);
#   verifica che non ne resti NESSUNO, anche fuori dall'elenco delle dipendenze (`find -type l`, reparse point da
#   Windows con `dir /AL /S`, `find -type l` da WSL; un comando di verifica che fallisce e' STOP): se ne resta uno,
#   STOP; poi `git worktree remove`; il branch solo con --branch (`git branch -d`: commit non integrati → resta).
#   ⚠️ Misurato: `git worktree remove` (anche senza --force) SEGUE una junction e svuota la cartella di
#   destinazione. Rimuovere senza scollegare svuoterebbe il node_modules VERO del tree principale.
#   Limite: un symlink TRACCIATO dal repository (oggi nessuno) sarebbe visto come collegamento rimasto (falso
#   positivo: STOP, direzione sicura).
#
# Il ciclo nel worktree: driver.py e run-phase.sh del PLUGIN della sessione (MAAT_SCRIPTS: stessa versione del plugin,
# non il harness del commit del worktree), cwd nel worktree. Il lock delle fasi di codice e'
# nella git dir del worktree (`git rev-parse --absolute-git-dir`: .git/worktrees/<id>/) e la copia WSL e'
# ~/fic-mirror-<hash> (una per radice): il lavoro LOCALE di due cicli in due worktree non si blocca a vicenda. Il DEV
# invece resta condiviso (sync del codice, context e2e): per questo con --worktree l'orchestratore forza --no-dev e
# rifiuta --with-e2e; la verifica su DEV si fa dopo, dal tree principale, a codice integrato. Il ciclo non committa:
# le modifiche restano non committate sul branch fic/<nome>.
#
# Uscita: 0 fatto · 1 verifica della copia WSL non riuscita (worktree creato: `crea` di nuovo riprende) o `stato`
#         di un worktree assente · 2 uso o errore · 3 STOP (altrui, dipendenze diverse, modifiche, lock, collegamenti,
#         lanciato da un worktree collegato).
# Test: script/fic/ciclo-worktree.test.sh (repo finto, HOME finta, controprova per mutazione).

set -uo pipefail
unset MSYS_NO_PATHCONV
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_ROOT e MAAT_SCRIPTS (plugin), MAAT_WORK (progetto)
TAG=ciclo-worktree

say() { echo "$TAG: $*"; }
die() { echo "$TAG: $*" >&2; exit 2; }
stop() { echo "$TAG: STOP — $*" >&2; exit 3; }
q() { printf '%q' "$1"; }

WT_TAG=$TAG
. "$HERE/worktree-lib.sh" || die "$HERE/worktree-lib.sh o $HERE/fic-mirror.sh non trovati"

sha() { if [ -f "$1" ]; then sha256sum < "$1" | cut -c1-64; else echo assente; fi; }
dir_fp() { # $1 cartella → impronta di percorsi e contenuti dei suoi file; «assente» se non c'e'
  if [ -d "$1" ]; then (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum) | sha256sum | cut -c1-64
  else echo assente; fi
}
AIW=.claude/.ai-workflow   # la cartella di lavoro (cartelle.lavoro di maat.json), relativa alla radice del repository
[ -n "$MAAT_WORK" ] && AIW=${MAAT_WORK#"$PROJECT_ROOT"/}

# --- argomenti ---
CMD=${1:-}; [ $# -gt 0 ] && shift
ARG="" BASE_REF="" FORCE=0 DELBRANCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE_REF=${2:-}; [ -n "$BASE_REF" ] || die "--base vuole un ref"; shift 2 ;;
    --base=*) BASE_REF=${1#--base=}; [ -n "$BASE_REF" ] || die "--base vuole un ref"; shift ;;
    --forza) FORCE=1; shift ;;
    --branch) DELBRANCH=1; shift ;;
    -*) die "opzione sconosciuta: $1" ;;
    *) [ -z "$ARG" ] || die "un solo argomento posizionale: $ARG, $1"; ARG=$1; shift ;;
  esac
done
USO="uso: ciclo-worktree.sh crea <spec> [--base <ref>] | stato <nome> | riporta <nome> [--forza] | rimuovi <nome> [--branch] [--forza]"
[ -n "$ARG" ] || die "$USO"
case "$CMD" in
  crea) [ $DELBRANCH -eq 0 ] && [ $FORCE -eq 0 ] || die "crea accetta solo --base" ;;
  stato) [ -z "$BASE_REF" ] && [ $DELBRANCH -eq 0 ] && [ $FORCE -eq 0 ] || die "stato non vuole opzioni" ;;
  riporta) [ -z "$BASE_REF" ] && [ $DELBRANCH -eq 0 ] || die "riporta accetta solo --forza" ;;
  rimuovi) [ -z "$BASE_REF" ] || die "rimuovi non accetta --base" ;;
  *) die "$USO" ;;
esac

# --- repository: quello della cartella corrente ---
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "la cartella corrente non e' in un repository git"
MAIN=$(cd "$(dirname "$common")" 2>/dev/null && pwd) || die "tree principale non risolto da $common"
# pk09 (pilota su un secondo progetto): da un worktree COLLEGATO (git dir ≠ git common dir) si risalirebbe al tree principale e se
# ne prenderebbero base, maat.json e spec. Rifiuto per ogni sottocomando, prima di leggere o creare qualunque cosa
gdir=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || die "git dir non risolta"
[ "$gdir" = "$common" ] || stop "lancia il ciclo dal tree principale ($MAIN), o senza --worktree: questa cartella e' gia' un worktree ($(git rev-parse --show-toplevel 2>/dev/null))"
MAINC=$(canon "$MAIN")
[ "$(canon "$(git -C "$MAIN" rev-parse --show-toplevel 2>/dev/null)")" = "$MAINC" ] || die "tree principale non valido: $MAINC"
# collegamenti, file delle dipendenze, preparati e copia: maat.json del tree principale, letta una volta
wt_conf_carica || die "maat.json del tree principale non leggibile: niente da collegare ne' da verificare"

if [ "$CMD" = crea ]; then
  SPEC=$ARG
  [ -f "$SPEC" ] || die "spec assente: $SPEC"
  NAME=$(basename "$SPEC"); NAME=${NAME%.md}; NAME=${NAME#spec-}
  case "$(basename "$SPEC")" in spec-*.md) ;; *) die "la spec deve chiamarsi spec-<nome>.md: $SPEC" ;; esac
  SPEC=$(cd "$(dirname "$SPEC")" && pwd)/$(basename "$SPEC")
  RUN_SRC=${SPEC%.md}.run
else
  NAME=${ARG#spec-}; NAME=${NAME%.md}; NAME=$(basename "$NAME")
fi
printf '%s' "$NAME" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*$' || die "nome non valido: $NAME"
BRANCH=fic/$NAME
WT="$(dirname "$MAINC")/$(basename "$MAINC")-fic-$NAME"
MK_REL=$AIW/spec-$NAME.worktree
SPEC_REL=$AIW/spec-$NAME.md RUN_REL=$AIW/spec-$NAME.run

mk_get() { sed -n "s/^$1=//p" "$WT/$MK_REL" 2>/dev/null | tr -d '\r' | head -1; }
mk_set() { # $1 chiave, $2 valore: riscrive la riga nel marcatore
  local f=$WT/$MK_REL
  grep -v "^$1=" "$f" > "$f.tmp" && printf '%s=%s\n' "$1" "$2" >> "$f.tmp" && mv "$f.tmp" "$f"
}

# --- il percorso e' il worktree creato da questo script per <nome>? (0 = si'; altrimenti il motivo su stderr) ---
ours() {
  local c w found=0
  [ -d "$WT" ] || { echo "non esiste: $WT" >&2; return 1; }
  c=$(canon "$WT")
  [ "$(canon "$(git -C "$c" rev-parse --show-toplevel 2>/dev/null)")" = "$c" ] || { echo "non e' la radice di un worktree git: $c" >&2; return 1; }
  [ "$c" != "$MAINC" ] || { echo "e' il tree principale: $c" >&2; return 1; }
  [ -f "$c/$MK_REL" ] || { echo "manca il marcatore di ciclo-worktree.sh ($MK_REL)" >&2; return 1; }
  [ "$(head -1 "$c/$MK_REL" | tr -d '\r')" = fic-ciclo-worktree ] || { echo "marcatore non valido: $c/$MK_REL" >&2; return 1; }
  [ "$(canon "$(mk_get path)")" = "$c" ] || { echo "il marcatore indica un altro percorso: $(mk_get path)" >&2; return 1; }
  [ "$(mk_get branch)" = "$BRANCH" ] || { echo "il marcatore indica un altro branch: $(mk_get branch)" >&2; return 1; }
  [ "$(git -C "$c" symbolic-ref --short -q HEAD)" = "$BRANCH" ] || { echo "il worktree non e' sul branch $BRANCH" >&2; return 1; }
  while IFS= read -r w; do [ "$(canon "$w")" = "$c" ] && found=1; done < <(git -C "$MAIN" worktree list --porcelain | sed -n 's/^worktree //p')
  [ $found -eq 1 ] || { echo "non e' fra i worktree del repository: $c" >&2; return 1; }
  return 0
}

# --- WSL: script su stdin (niente quoting attraverso wsl.exe); altrove bash diretto ---
use_wsl() { [ "${FIC_WT_WSL:-1}" != 0 ]; }
wsl_path() { # cartella o file esistente → percorso per WSL (canon vale solo per le cartelle)
  local p
  if [ -d "$1" ]; then p=$(canon "$1"); else p="$(canon "$(dirname "$1")")/$(basename "$1")"; fi
  if [ $WIN -eq 1 ]; then wslp "$p"; else printf '%s' "$p"; fi
}
wsl_run() { # stdin = script bash
  if [ $WIN -eq 1 ]; then MSYS_NO_PATHCONV=1 wsl.exe -- bash -s; else bash -s; fi
}

# --- scollegamento e verifica: nessun collegamento deve restare prima di rimuovere la cartella ---
links_left() { # $1 worktree → i collegamenti rimasti (uno per riga), da Git Bash, poi da Windows, poi da WSL.
  # Uscita ≠ 0 se una verifica non e' riuscita (find, dir o WSL falliti): il chiamante si ferma.
  # Ogni vista parte solo se la precedente non ne ha trovati: `dir /S` ATTRAVERSA le junction (misurato), e su una
  # rimasta scorrerebbe tutto il node_modules del tree principale (solo lettura, ma lento).
  local wt=$1 w out rc err
  [ -d "$wt" ] || { echo "$TAG: $wt non e' una cartella: collegamenti non verificabili" >&2; return 2; }
  out=$(find "$wt" -type l) || { echo "$TAG: find -type l fallito su $wt" >&2; return 2; }
  if [ -z "$out" ] && [ $WIN -eq 1 ]; then   # reparse point (junction e symlink) visti da Windows
    err=$(mktemp) || return 2
    out=$(MSYS2_ARG_CONV_EXCL='*' cmd.exe /c dir /AL /S /B "$(cygpath -w "$wt")" 2>"$err" | tr -d '\r' | sed '/^$/d'); rc=${PIPESTATUS[0]}
    # dir esce 1 con «File non trovato» (o «File Not Found») quando non c'e' nessun reparse point: e' il caso buono
    # (la cartella esiste, verificato sopra); qualunque altro esito e' una verifica fallita
    if [ -z "$out" ] && ! { [ "$rc" -eq 1 ] && grep -qiE 'non trovato|not found' "$err"; }; then
      echo "$TAG: dir /AL /S fallito su $wt (uscita $rc: $(tr -d '\r' < "$err"))" >&2; rm -f "$err"; return 2
    fi
    rm -f "$err"
  fi
  if [ -z "$out" ] && use_wsl && [ $WIN -eq 1 ]; then
    w=$(wsl_path "$wt")
    out=$(printf 'find %s -type l\n' "$(q "$w")" | wsl_run) || { echo "$TAG: find -type l da WSL fallito su $w" >&2; return 2; }
  fi
  [ -z "$out" ] || printf '%s\n' "$out"
  return 0
}
scollega_e_verifica() { # $1 worktree: 0 = nessun collegamento resta; 1 = qualcosa resta, o verifica fallita (stderr)
  local wt=$1 left
  unlink_deps "$wt" || return 1
  left=$(links_left "$wt") || { echo "$TAG: verifica dei collegamenti non riuscita" >&2; return 1; }
  left=$(printf '%s' "$left" | LC_ALL=C sort -u)
  [ -z "$left" ] && return 0
  echo "$TAG: collegamenti ancora presenti:" >&2; printf '  %s\n' "$left" >&2
  return 1
}

# ============================================================================================ crea
if [ "$CMD" = crea ]; then
  . "$MAAT_SCRIPTS/python.sh" || die "interprete Python non trovato (imposta FIC_PYTHON)"
  RESUME=0
  if [ -e "$WT" ] || [ -L "$WT" ]; then
    why=$(ours 2>&1) || stop "$WT esiste e non e' un worktree di ciclo-worktree.sh per $NAME ($why): non lo uso"
    RESUME=1
    say "ripresa del worktree esistente: $WT"
  elif git -C "$MAIN" show-ref --verify -q "refs/heads/$BRANCH"; then
    stop "il branch $BRANCH esiste gia' senza il worktree $WT: non e' mio, non lo riuso (se e' un avanzo: git worktree prune, poi git branch -d $BRANCH)"
  fi
  if [ $RESUME -eq 0 ]; then
    BASE=$(git -C "$MAIN" rev-parse --verify -q "${BASE_REF:-HEAD}^{commit}") || die "ref di base non valido: ${BASE_REF:-HEAD}"
    # dipendenze: quelle del tree principale valgono per la base? (prima di creare qualunque cosa)
    DD=$(deps_diff "$BASE")
    [ -z "$DD" ] || stop "dipendenze diverse fra la base ${BASE:0:12} e il tree principale: $(echo $DD). node_modules e venv collegati dal tree principale non sarebbero quelli di questo codice. Niente worktree creato."
    git -C "$MAIN" worktree add -q -b "$BRANCH" "$WT" "$BASE" || die "git worktree add fallito: $WT"
    mkdir -p "$WT/$AIW" && printf 'fic-ciclo-worktree\npath=%s\nbranch=%s\nbase=%s\nprincipale=%s\nprincipale_run=%s\ncreato=%s\n' \
      "$(canon "$WT")" "$BRANCH" "$BASE" "$(sha "$MAINC/$SPEC_REL")" "$(dir_fp "$MAINC/$RUN_REL")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WT/$MK_REL" ||
      die "marcatore non scrivibile: $WT/$MK_REL"
    if ! git -C "$WT" check-ignore -q "$MK_REL"; then   # il marcatore non deve mai essere superficie di review
      git -C "$MAIN" worktree remove --force "$WT" && git -C "$MAIN" branch -D -q "$BRANCH"
      stop "$MK_REL non e' gitignorato alla base ${BASE:0:12} (regola $AIW/spec-*): worktree rimosso"
    fi
    fic_relgit "$WT" || say "AVVISO — .git con gitdir assoluto (vitest-fast.sh lo traduce)"
    say "worktree creato: $WT (branch $BRANCH da ${BASE:0:12}); il ciclo usa il plugin della sessione ($MAAT_ROOT), non il harness del commit del worktree"
  else
    BASE=$(mk_get base)
    # in ripresa: dipendenze della base ancora uguali al tree principale, e il ciclo non le ha cambiate nel worktree
    # (ne' modificate ne' aggiunte come file non tracciati)
    mapfile -t DEP_PS < <(dep_ps)   # file_dipendenze di maat.json; nessuno: niente da confrontare
    DD=$( { deps_diff "$BASE"; if [ ${#DEP_PS[@]} -gt 0 ]; then git -C "$WT" -c core.quotePath=false diff --name-only HEAD -- "${DEP_PS[@]}"
            git -C "$WT" -c core.quotePath=false ls-files -o --exclude-standard -- "${DEP_PS[@]}"; fi; } | LC_ALL=C sort -u)
    [ -z "$DD" ] || stop "dipendenze diverse fra il worktree e il tree principale: $(echo $DD). I collegamenti non varrebbero per questo codice."
  fi

  # collegamenti: dipendenze del tree principale, mai copiate
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -L "$WT/$p" ]; then continue
    elif [ -e "$WT/$p" ]; then say "AVVISO — $p e' una cartella vera del worktree: non la sostituisco"
    else link_dep "$MAINC/$p" "$WT/$p" || stop "collegamento di $p non riuscito"
    fi
  done < <(dep_links "$MAINC")
  n=$(dep_links "$WT" | while IFS= read -r p; do [ -L "$WT/$p" ] && echo "$p"; done | wc -l)
  say "dipendenze collegate dal tree principale: $n ($(dep_links "$WT" | tr '\n' ' '))"

  # spec e run dir: copiate alla creazione; in ripresa vincono quelle del worktree
  if [ -f "$WT/$SPEC_REL" ]; then
    say "spec del worktree gia' presente: non la sovrascrivo ($SPEC_REL)"
    [ "$(sha "$MAINC/$SPEC_REL")" = "$(mk_get principale)" ] ||
      say "AVVISO — la spec del tree principale e' cambiata dalla copia: il ciclo usa quella del worktree"
  else
    cp "$SPEC" "$WT/$SPEC_REL" || die "copia della spec fallita"
    say "spec copiata: $SPEC_REL"
  fi
  if [ -d "$RUN_SRC" ] && [ ! -e "$WT/$RUN_REL" ]; then
    cp -R "$RUN_SRC" "$WT/$RUN_REL" || die "copia della run dir fallita"
    say "run dir copiata: $RUN_REL"
  fi

  # preparati dei moduli (es. tsconfig e dichiarazioni generati), dipendenze uguali: copiati se il file guida c'e'
  # nel tree principale e manca nel worktree; se manca nel tree principale, l'avviso nomina la preparazione
  while IFS=$'\t' read -r k rad guida prepcmd globs; do
    [ "$k" = prep ] || continue
    [ "$guida" = - ] && guida=""; [ "$prepcmd" = - ] && prepcmd=""   # campi vuoti (segnaposto di wt_conf)
    [ -n "$guida" ] || continue
    pre=""; [ "$rad" = . ] || pre="$rad/"
    if [ -f "$MAINC/$pre$guida" ]; then
      [ -f "$WT/$pre$guida" ] && continue
      nc=0
      IFS=$'\t' read -ra gl <<< "$globs"
      for g in "${gl[@]}"; do
        oifs=$IFS; IFS=; fs=("$MAINC/$pre"$g); IFS=$oifs   # pk08: IFS vuoto, una voce con spazi non si divide
        for f in "${fs[@]}"; do   # $g senza virgolette: il * del glob si espande
          [ -f "$f" ] || continue
          rel=${f#"$MAINC/"}
          [ -f "$WT/$rel" ] && continue
          mkdir -p "$(dirname "$WT/$rel")" && cp "$f" "$WT/$rel" || die "copia di $rel fallita"
          nc=$((nc + 1))
        done
      done
      say "preparati copiati in $rad: $nc file ($guida e gli altri di preparati)"
    elif [ -d "$MAINC/$rad" ]; then
      say "AVVISO — il tree principale non ha $pre$guida: lancia '$prepcmd' in $rad del tree principale, poi crea di nuovo"
    fi
  done < <(wt_conf)
  deps_fp_check "$MAINC" "$WT" >/dev/null 2>&1
  [ -z "$FPWARN" ] || say "AVVISO — $FPWARN"

  # copia WSL del worktree, per ogni modulo con copia: seminata e con il file guida dei preparati
  cw=()
  while IFS=$'\t' read -r k p rad guida; do
    [ "$k" = copia ] || continue
    [ "$guida" = - ] && guida=""   # guida vuota (segnaposto di wt_conf)
    cw+=("$p" "$rad" "$guida")
  done < <(wt_conf)
  if [ ${#cw[@]} -eq 0 ]; then
    say "nessun modulo con copia in maat.json: verifica della copia WSL saltata"
  elif use_wsl; then
    lw=$(wsl_path "$WTLIB_TEST/fic-mirror.sh") rw=$(wsl_path "$WT")
    out=$({ printf 'L=%s R=%s\n' "$(q "$lw")" "$(q "$rw")"; printf 'set --'; printf ' %q' "${cw[@]}"; printf '\n'; cat <<'EOS'
. "$L" || { echo "fic-mirror.sh non leggibile da WSL: $L"; exit 1; }
fic_mirror_init "$R" || { echo "git (WSL) non determina la radice del worktree $R"; exit 1; }
case "$FIC_MIRROR" in "$HOME"/fic-mirror-????????????) ;; *) echo "copia inattesa: $FIC_MIRROR (non e' la copia di un worktree)"; exit 1 ;; esac
while [ $# -ge 3 ]; do
  P=$1 D=$2 G=$3; shift 3   # radice_pacchetti, radice e file guida del modulo con copia
  if [ -d "$FIC_MIRROR/$P/node_modules" ] && [ -f "$FIC_MIRROR/$P/.fic-deps" ]; then
    echo "copia WSL gia' seminata: $FIC_MIRROR ($P)"
  else
    why=$(fic_seed_node_modules "$R/$P" "$FIC_MIRROR/$P") || { echo "semina della copia WSL non riuscita: $why"; exit 1; }
    echo "copia WSL seminata: $FIC_MIRROR ($P, dipendenze in hardlink da ~/fic-mirror)"
  fi
  fic_deps_ok "$R/$P" "$FIC_MIRROR/$P" || echo "AVVISO: impronta della copia diversa dalle dipendenze del worktree (test-fast.sh la riallinea)"
  [ -n "$G" ] || continue
  [ -f "$R/$D/$G" ] || { echo "file guida $G dei preparati assente in $R/$D: il lint uscirebbe BLOCKED"; exit 1; }
  echo "file guida dei preparati presente: $D/$G"
done
EOS
    } | wsl_run 2>&1); rc=$?
    printf '%s\n' "$out" | sed "s/^/$TAG: /"
    [ $rc -eq 0 ] || { echo "$TAG: verifica della copia WSL non riuscita: il worktree resta ($WT); risolto il motivo, 'crea' di nuovo riprende" >&2; exit 1; }
  else
    say "verifica della copia WSL saltata (FIC_WT_WSL=0)"
  fi
  canon "$WT"
  exit 0
fi

# ============================================================================================ stato
if [ "$CMD" = stato ]; then
  [ -d "$WT" ] || { say "nessun worktree per $NAME ($WT)"; exit 1; }
  echo "percorso: $(canon "$WT")"
  echo "branch: $(git -C "$WT" symbolic-ref --short -q HEAD || echo '(staccato)') · HEAD $(git -C "$WT" rev-parse --short=12 HEAD 2>/dev/null) · base $(mk_get base | cut -c1-12)"
  if why=$(ours 2>&1); then echo "proprietario: ciclo-worktree.sh ($MK_REL)"; else echo "proprietario: NON di ciclo-worktree.sh — $why"; fi
  if [ -f "$WT/$SPEC_REL" ]; then
    if cmp -s "$WT/$SPEC_REL" "$MAINC/$SPEC_REL"; then r=si; else r=no; fi
    echo "spec: $(canon "$WT")/$SPEC_REL · riportata nel tree principale: $r"
    CS=$MAAT_SCRIPTS/cycle-state.sh   # il plugin della sessione, non il harness del commit del worktree
    echo "ciclo: $( (cd "$WT" && bash "$CS" "$SPEC_REL" 2>&1) | tr -d '\r' | grep -E '^(State|Next):' | tr '\n' ' ')"
  else
    echo "spec: assente nel worktree"
  fi
  RP=$MAAT_SCRIPTS/run-phase.sh
  [ -f "$RP" ] && echo "lock: $( (cd "$WT" && env -u FIC_LOCK -u FIC_PHASE -u FIC_REPO bash "$RP" --lock-status 2>&1) | tr -d '\r')"
  st=$(git -C "$WT" status --porcelain --untracked-files=all)
  echo "file modificati: $(printf '%s' "$st" | grep -c .)"
  [ -z "$st" ] || printf '%s\n' "$st"
  exit 0
fi

why=$(ours 2>&1) || stop "$WT non e' un worktree di ciclo-worktree.sh per $NAME ($why)"

# ============================================================================================ riporta
if [ "$CMD" = riporta ]; then
  [ -f "$WT/$SPEC_REL" ] || stop "spec assente nel worktree: $WT/$SPEC_REL"
  cur=$(sha "$MAINC/$SPEC_REL") exp=$(mk_get principale) new=$(sha "$WT/$SPEC_REL")
  if [ "$cur" != "$exp" ] && [ "$cur" != "$new" ] && [ $FORCE -eq 0 ]; then
    stop "la spec del tree principale ($SPEC_REL) e' cambiata dopo la copia nel worktree: riportarla cancellerebbe quelle modifiche. Confronta i due file; per sovrascriverla comunque: --forza"
  fi
  rcur=$(dir_fp "$MAINC/$RUN_REL") rexp=$(mk_get principale_run) rnew=$(dir_fp "$WT/$RUN_REL")
  if [ -d "$WT/$RUN_REL" ] && [ "$rcur" != "$rexp" ] && [ "$rcur" != "$rnew" ] && [ $FORCE -eq 0 ]; then
    stop "la run dir del tree principale ($RUN_REL) e' cambiata dopo la copia nel worktree: allinearla cancellerebbe quei file. Confronta (diff -rq); per sovrascriverla comunque: --forza"
  fi
  mkdir -p "$MAINC/$AIW" && cp "$WT/$SPEC_REL" "$MAINC/$SPEC_REL" || die "copia della spec fallita"
  say "spec riportata: $MAINC/$SPEC_REL"
  if [ -d "$WT/$RUN_REL" ]; then
    # allineamento, non fusione: copia completa accanto (nome spec-*: gitignorato), poi prende il posto della vecchia
    nuova="$MAINC/$RUN_REL.nuova.$$" vecchia="$MAINC/$RUN_REL.vecchia.$$"
    # interruzione a meta' dello scambio: via la copia nuova, e la vecchia torna al suo posto se la run dir manca
    ripristina() { [ -e "$MAINC/$RUN_REL" ] || [ ! -d "$vecchia" ] || mv "$vecchia" "$MAINC/$RUN_REL"; }
    trap 'rm -rf "$nuova"; ripristina || echo "$TAG: run dir precedente in $vecchia" >&2; exit 130' INT TERM HUP
    cp -R "$WT/$RUN_REL" "$nuova" || { rm -rf "$nuova"; die "copia della run dir fallita (la run dir del tree principale e' intatta)"; }
    if [ -d "$MAINC/$RUN_REL" ]; then mv "$MAINC/$RUN_REL" "$vecchia" || { rm -rf "$nuova"; die "run dir del tree principale non spostabile (in uso?): intatta"; }; fi
    if ! mv "$nuova" "$MAINC/$RUN_REL"; then
      rm -rf "$nuova"
      [ -d "$vecchia" ] || die "run dir non allineata (non ce n'era una precedente nel tree principale)"
      mv "$vecchia" "$MAINC/$RUN_REL" && die "run dir non allineata: ripristinata la precedente"
      die "run dir non allineata e NON ripristinata: la run dir precedente e' in $vecchia (rimettila a mano in $MAINC/$RUN_REL)"
    fi
    trap - INT TERM HUP
    rm -rf "$vecchia"
    [ "$(dir_fp "$MAINC/$RUN_REL")" = "$rnew" ] || die "run dir riportata diversa da quella del worktree"
    say "run dir allineata: $MAINC/$RUN_REL"
  fi
  mk_set principale "$new"
  mk_set principale_run "$(dir_fp "$MAINC/$RUN_REL")"
  say "codice NON riportato: resta sul branch $BRANCH in $(canon "$WT") (non committato)"
  exit 0
fi

# ============================================================================================ rimuovi
RP=$MAAT_SCRIPTS/run-phase.sh   # il plugin della sessione; il lock e' comunque quello del worktree (cwd)
if [ -f "$RP" ]; then
  ls_out=$( (cd "$WT" && env -u FIC_LOCK -u FIC_PHASE -u FIC_REPO bash "$RP" --lock-status 2>&1) ); ls_rc=$?
  [ $ls_rc -eq 0 ] || stop "lock delle fasi di codice del worktree non libero: $(printf '%s' "$ls_out" | tr -d '\r'). Un ciclo gira li': prima fermalo"
fi
# lock del piano (<run-dir>/plan.lock): vivo se un suo pid esiste, o se e' appena creato senza owner (come run-phase.sh)
PL=$WT/$RUN_REL/plan.lock
if [ -d "$PL" ]; then
  if [ -f "$PL/owner" ]; then
    for k in pid cpid; do
      p=$(sed -n "s/^$k=//p" "$PL/owner" | tr -d '\r' | head -1)
      [ -n "$p" ] && kill -0 "$p" 2>/dev/null && stop "una fase di piano del worktree e' viva ($RUN_REL/plan.lock, $k=$p): prima fermala"
    done
  elif [ -z "$(find "$PL" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    stop "lock del piano appena preso ($RUN_REL/plan.lock, owner non ancora scritto): una fase di piano sta partendo"
  fi
fi
# fase in corso: log/<etichetta>.running senza .exit (il driver lo legge come IN CORSO): viva, o morta senza chiudere
running=""
for f in "$WT/$RUN_REL"/log/*.running; do
  [ -e "$f" ] && [ ! -e "${f%.running}.exit" ] && running="$running $(basename "${f%.running}")"
done
if [ -n "$running" ] && [ $FORCE -eq 0 ]; then
  stop "fase in corso nel worktree:$running (log/<etichetta>.running senza .exit): se gira ancora, prima fermala; se e' morta, --forza"
fi
[ -z "$running" ] || say "AVVISO — --forza: fase risultante in corso ignorata:$running (log/<etichetta>.running senza .exit)"
st=$(git -C "$WT" status --porcelain --untracked-files=all)
if [ -n "$st" ] && [ $FORCE -eq 0 ]; then
  stop "il worktree ha modifiche non committate ($(printf '%s\n' "$st" | grep -c .) file): integrale prima (commit e merge, oppure git -C $(q "$(canon "$WT")") diff | git apply), o --forza per scartarle"
fi
# spec e run dir del ciclo: con il worktree se ne andrebbero; devono essere gia' nel tree principale
nr=""
[ -f "$WT/$SPEC_REL" ] && ! cmp -s "$WT/$SPEC_REL" "$MAINC/$SPEC_REL" && nr="la spec ($SPEC_REL)"
if [ -d "$WT/$RUN_REL" ] && ! diff -rq "$WT/$RUN_REL" "$MAINC/$RUN_REL" >/dev/null 2>&1; then nr="${nr:+$nr e }la run dir ($RUN_REL)"; fi
if [ -n "$nr" ]; then
  [ $FORCE -eq 1 ] || stop "$nr del worktree non e' riportata nel tree principale: rimuovendo il worktree andrebbe persa. Prima: ciclo-worktree.sh riporta $NAME (o --forza per perderla)"
  say "AVVISO — --forza: $nr del worktree non riportata, va persa"
fi
if use_wsl; then forget_mirror "$WT"; else say "copia WSL non cancellata (FIC_WT_WSL=0)"; fi
scollega_e_verifica "$WT" || stop "collegamenti ancora presenti in $WT: worktree NON rimosso (la rimozione seguirebbe le dipendenze del tree principale)"
say "collegamenti tolti, nessuno rimasto"
if [ $FORCE -eq 1 ]; then git -C "$MAIN" worktree remove --force "$WT"; else git -C "$MAIN" worktree remove "$WT"; fi ||
  die "git worktree remove fallito: $WT"
[ ! -e "$WT" ] || die "la cartella $WT esiste ancora dopo git worktree remove"
say "worktree rimosso: $WT"
if [ $DELBRANCH -eq 1 ]; then
  git -C "$MAIN" branch -d -q "$BRANCH" || die "branch $BRANCH non cancellato (commit non integrati?): resta; per scartarlo: git branch -D $BRANCH"
  say "branch cancellato: $BRANCH"
else
  say "branch $BRANCH lasciato (per cancellarlo: --branch)"
fi
exit 0
