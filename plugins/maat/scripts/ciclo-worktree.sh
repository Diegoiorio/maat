#!/usr/bin/env bash
# ciclo-worktree.sh — /full-implementation-cycle in a DEDICATED git worktree (flag --worktree), to run the
# cycle while other sessions work in the main tree: their `git add -A` does not commit the half-done files of the
# cycle, and the cycle's review does not see other flows' files in the diff.
#
#   ciclo-worktree.sh crea <spec> [--base <ref>]      creates (or resumes) the cycle's worktree; last line: the path
#   ciclo-worktree.sh stato <nome>                    where it is, branch, cycle phase, modified files
#   ciclo-worktree.sh riporta <nome> [--forza]        worktree spec and run dir → main tree (never the code)
#   ciclo-worktree.sh rimuovi <nome> [--branch] [--forza]
#
# The repository is the current folder's, which must be the MAIN TREE: from a linked worktree
# (git dir ≠ git common dir) every subcommand is refused with STOP (pk09). <nome> = the spec without `spec-` and `.md`.
#
# crea, in order:
#   1. worktree `<parent>/<repo>-fic-<nome>` on branch `fic/<nome>` from --base (default: HEAD of the main tree).
#      If the path exists: resume if it is ours (marker below), otherwise STOP. Branch `fic/<nome>` already
#      existing without its worktree: STOP. Ownership marker INSIDE the worktree:
#      `<cartelle.lavoro>/spec-<nome>.worktree` (default .claude/.ai-workflow; gitignored by the spec-* rule, verified: never review
#      surface), with the path, the branch, the base and the fingerprint of the main tree's spec at copy time;
#   2. BEFORE creating anything: the files that decide the dependencies (the `file_dipendenze` files of the
#      maat.json modules) must match between the base and the main working tree (deps_diff, the same logic as
#      replay.sh). If not: STOP, no worktree — never link the wrong dependencies;
#   3. LINKS, never copies or installs, the `collega_nel_worktree` folders of the modules present in the main
#      tree: junctions on Windows, symlinks elsewhere (worktree-lib.sh, shared with corpus/replay.sh); .git with a
#      relative gitdir (WSL's git can read it);
#   4. copies the spec and, if present, its run dir `spec-<nome>.run/` (gitignored: the checkout does not bring
#      them); on resume the worktree's ones win and are not overwritten;
#   5. copies the module's `preparati` from the main tree (same dependencies, verified at step 2), if the guide
#      file (the first glob without wildcards) is there and missing in the worktree: the copy's lint and tests
#      read them; if it is missing in the main tree, warns to run the module's `preparazione` there. A module
#      without preparati: no copy, no warning;
#   6. checks the worktree's WSL copy (~/fic-mirror-<hash>) for the module with `copia`: the seeding of the
#      dependencies of its radice_pacchetti as hardlinks from ~/fic-mirror (fic_seed_node_modules of fic-mirror.sh,
#      the same as test-fast.sh's first run) and the guide file of its preparati as seen from WSL. FIC_WT_WSL=0
#      skips it (tests);
#   7. prints the worktree path (last line of stdout).
# riporta: SYNCS into the main tree the worktree's spec (plan, review, status lines) and run dir, in the usual
#   place (.claude/.ai-workflow/), for cycle-report.py and for the user: the run dir is copied into a temporary
#   folder next to it and replaces the old one (no merging: a file removed in the worktree disappears there
#   too). Does not touch the code. STOP if the main tree's spec or run dir changed after the copy (fingerprints
#   in the marker: someone worked on them there), unless --forza.
# rimuovi, in order: STOP if a worktree phase is alive — code phase lock (run-phase.sh --lock-status),
#   <run-dir>/plan.lock with a live pid (never forceable) — or if a phase shows as running (log/*.running without
#   .exit: alive, or dead without closing; --forza to proceed); STOP if the worktree has uncommitted changes, or if
#   its spec or run dir are not synced back to the main tree (cmp, diff -rq), unless --forza (which loses them);
#   the worktree's WSL copies deleted (lanes included); links removed (only the link, never recursive);
#   check that NONE is left, even outside the dependency list (`find -type l`, reparse points from
#   Windows with `dir /AL /S`, `find -type l` from WSL; a check command that fails is a STOP): if one is left,
#   STOP; then `git worktree remove`; the branch only with --branch (`git branch -d`: unmerged commits → it stays).
#   ⚠️ Measured: `git worktree remove` (even without --force) FOLLOWS a junction and empties the target
#   folder. Removing without unlinking would empty the main tree's REAL node_modules.
#   Limit: a symlink TRACKED by the repository (none today) would be seen as a leftover link (false
#   positive: STOP, the safe direction).
#
# The cycle in the worktree: driver.py and run-phase.sh of the session's PLUGIN (MAAT_SCRIPTS: same plugin version,
# not the harness of the worktree's commit), cwd in the worktree. The code phase lock is
# in the worktree's git dir (`git rev-parse --absolute-git-dir`: .git/worktrees/<id>/) and the WSL copy is
# ~/fic-mirror-<hash> (one per root): the LOCAL work of two cycles in two worktrees does not block each other. DEV
# instead stays shared (code sync, e2e context): that is why with --worktree the orchestrator forces --no-dev and
# refuses --with-e2e; verification on DEV happens later, from the main tree, once the code is merged. The cycle does
# not commit: the changes stay uncommitted on branch fic/<nome>.
#
# Exit: 0 done · 1 WSL copy check failed (worktree created: running `crea` again resumes) or `stato`
#         of a missing worktree · 2 usage or error · 3 STOP (someone else's, different dependencies, changes, lock,
#         links, launched from a linked worktree).
# Tests: script/fic/ciclo-worktree.test.sh (fake repo, fake HOME, counterproof by mutation).

set -uo pipefail
unset MSYS_NO_PATHCONV
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_ROOT and MAAT_SCRIPTS (plugin), MAAT_WORK (project)
TAG=ciclo-worktree

say() { echo "$TAG: $*"; }
die() { echo "$TAG: $*" >&2; exit 2; }
stop() { echo "$TAG: STOP — $*" >&2; exit 3; }
q() { printf '%q' "$1"; }

WT_TAG=$TAG
. "$HERE/worktree-lib.sh" || die "$HERE/worktree-lib.sh o $HERE/fic-mirror.sh non trovati"

sha() { if [ -f "$1" ]; then sha256sum < "$1" | cut -c1-64; else echo assente; fi; }
dir_fp() { # $1 folder → fingerprint of the paths and contents of its files; «assente» if missing
  if [ -d "$1" ]; then (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum) | sha256sum | cut -c1-64
  else echo assente; fi
}
AIW=.claude/.ai-workflow   # the work folder (cartelle.lavoro of maat.json), relative to the repository root
[ -n "$MAAT_WORK" ] && AIW=${MAAT_WORK#"$PROJECT_ROOT"/}

# --- arguments ---
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

# --- repository: the current folder's ---
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "la cartella corrente non e' in un repository git"
MAIN=$(cd "$(dirname "$common")" 2>/dev/null && pwd) || die "tree principale non risolto da $common"
# pk09 (pilot on a second project): from a LINKED worktree (git dir ≠ git common dir) we would climb to the main tree and
# take its base, maat.json and spec. Refused for every subcommand, before reading or creating anything
gdir=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || die "git dir non risolta"
[ "$gdir" = "$common" ] || stop "lancia il ciclo dal tree principale ($MAIN), o senza --worktree: questa cartella e' gia' un worktree ($(git rev-parse --show-toplevel 2>/dev/null))"
MAINC=$(canon "$MAIN")
[ "$(canon "$(git -C "$MAIN" rev-parse --show-toplevel 2>/dev/null)")" = "$MAINC" ] || die "tree principale non valido: $MAINC"
# links, dependency files, preparati and copia: the main tree's maat.json, read once
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
mk_set() { # $1 key, $2 value: rewrites the line in the marker
  local f=$WT/$MK_REL
  grep -v "^$1=" "$f" > "$f.tmp" && printf '%s=%s\n' "$1" "$2" >> "$f.tmp" && mv "$f.tmp" "$f"
}

# --- is the path the worktree created by this script for <nome>? (0 = yes; otherwise the reason on stderr) ---
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

# --- WSL: script on stdin (no quoting through wsl.exe); elsewhere plain bash ---
use_wsl() { [ "${FIC_WT_WSL:-1}" != 0 ]; }
wsl_path() { # existing folder or file → path for WSL (canon only works for folders)
  local p
  if [ -d "$1" ]; then p=$(canon "$1"); else p="$(canon "$(dirname "$1")")/$(basename "$1")"; fi
  if [ $WIN -eq 1 ]; then wslp "$p"; else printf '%s' "$p"; fi
}
wsl_run() { # stdin = bash script
  if [ $WIN -eq 1 ]; then MSYS_NO_PATHCONV=1 wsl.exe -- bash -s; else bash -s; fi
}

# --- unlinking and check: no link may be left before removing the folder ---
links_left() { # $1 worktree → the leftover links (one per line), from Git Bash, then from Windows, then from WSL.
  # Exit ≠ 0 if a check failed (find, dir or WSL failed): the caller stops.
  # Each view runs only if the previous one found none: `dir /S` TRAVERSES junctions (measured), and on a leftover
  # one it would walk the main tree's whole node_modules (read-only, but slow).
  local wt=$1 w out rc err
  [ -d "$wt" ] || { echo "$TAG: $wt non e' una cartella: collegamenti non verificabili" >&2; return 2; }
  out=$(find "$wt" -type l) || { echo "$TAG: find -type l fallito su $wt" >&2; return 2; }
  if [ -z "$out" ] && [ $WIN -eq 1 ]; then   # reparse points (junctions and symlinks) as seen from Windows
    err=$(mktemp) || return 2
    out=$(MSYS2_ARG_CONV_EXCL='*' cmd.exe /c dir /AL /S /B "$(cygpath -w "$wt")" 2>"$err" | tr -d '\r' | sed '/^$/d'); rc=${PIPESTATUS[0]}
    # dir exits 1 with «File non trovato» (or «File Not Found») when there is no reparse point: that is the good case
    # (the folder exists, checked above); any other outcome is a failed check
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
scollega_e_verifica() { # $1 worktree: 0 = no link left; 1 = something left, or check failed (stderr)
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
    # dependencies: do the main tree's ones hold for the base? (before creating anything)
    DD=$(deps_diff "$BASE")
    [ -z "$DD" ] || stop "dipendenze diverse fra la base ${BASE:0:12} e il tree principale: $(echo $DD). node_modules e venv collegati dal tree principale non sarebbero quelli di questo codice. Niente worktree creato."
    git -C "$MAIN" worktree add -q -b "$BRANCH" "$WT" "$BASE" || die "git worktree add fallito: $WT"
    mkdir -p "$WT/$AIW" && printf 'fic-ciclo-worktree\npath=%s\nbranch=%s\nbase=%s\nprincipale=%s\nprincipale_run=%s\ncreato=%s\n' \
      "$(canon "$WT")" "$BRANCH" "$BASE" "$(sha "$MAINC/$SPEC_REL")" "$(dir_fp "$MAINC/$RUN_REL")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WT/$MK_REL" ||
      die "marcatore non scrivibile: $WT/$MK_REL"
    if ! git -C "$WT" check-ignore -q "$MK_REL"; then   # the marker must never be review surface
      git -C "$MAIN" worktree remove --force "$WT" && git -C "$MAIN" branch -D -q "$BRANCH"
      stop "$MK_REL non e' gitignorato alla base ${BASE:0:12} (regola $AIW/spec-*): worktree rimosso"
    fi
    fic_relgit "$WT" || say "AVVISO — .git con gitdir assoluto (vitest-fast.sh lo traduce)"
    say "worktree creato: $WT (branch $BRANCH da ${BASE:0:12}); il ciclo usa il plugin della sessione ($MAAT_ROOT), non il harness del commit del worktree"
  else
    BASE=$(mk_get base)
    # on resume: the base's dependencies still equal to the main tree's, and the cycle did not change them in the
    # worktree (neither modified nor added as untracked files)
    mapfile -t DEP_PS < <(dep_ps)   # file_dipendenze of maat.json; none: nothing to compare
    DD=$( { deps_diff "$BASE"; if [ ${#DEP_PS[@]} -gt 0 ]; then git -C "$WT" -c core.quotePath=false diff --name-only HEAD -- "${DEP_PS[@]}"
            git -C "$WT" -c core.quotePath=false ls-files -o --exclude-standard -- "${DEP_PS[@]}"; fi; } | LC_ALL=C sort -u)
    [ -z "$DD" ] || stop "dipendenze diverse fra il worktree e il tree principale: $(echo $DD). I collegamenti non varrebbero per questo codice."
  fi

  # links: the main tree's dependencies, never copied
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -L "$WT/$p" ]; then continue
    elif [ -e "$WT/$p" ]; then say "AVVISO — $p e' una cartella vera del worktree: non la sostituisco"
    else link_dep "$MAINC/$p" "$WT/$p" || stop "collegamento di $p non riuscito"
    fi
  done < <(dep_links "$MAINC")
  n=$(dep_links "$WT" | while IFS= read -r p; do [ -L "$WT/$p" ] && echo "$p"; done | wc -l)
  say "dipendenze collegate dal tree principale: $n ($(dep_links "$WT" | tr '\n' ' '))"

  # spec and run dir: copied at creation; on resume the worktree's ones win
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

  # module preparati (e.g. generated tsconfig and declarations), same dependencies: copied if the guide file is
  # in the main tree and missing in the worktree; if missing in the main tree, the warning names the preparazione
  while IFS=$'\t' read -r k rad guida prepcmd globs; do
    [ "$k" = prep ] || continue
    [ "$guida" = - ] && guida=""; [ "$prepcmd" = - ] && prepcmd=""   # empty fields (wt_conf placeholder)
    [ -n "$guida" ] || continue
    pre=""; [ "$rad" = . ] || pre="$rad/"
    if [ -f "$MAINC/$pre$guida" ]; then
      [ -f "$WT/$pre$guida" ] && continue
      nc=0
      IFS=$'\t' read -ra gl <<< "$globs"
      for g in "${gl[@]}"; do
        oifs=$IFS; IFS=; fs=("$MAINC/$pre"$g); IFS=$oifs   # pk08: empty IFS, an entry with spaces is not split
        for f in "${fs[@]}"; do   # $g unquoted: the glob's * expands
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

  # WSL copy of the worktree, for each module with copia: seeded and with the guide file of the preparati
  cw=()
  while IFS=$'\t' read -r k p rad guida; do
    [ "$k" = copia ] || continue
    [ "$guida" = - ] && guida=""   # empty guide (wt_conf placeholder)
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
  P=$1 D=$2 G=$3; shift 3   # radice_pacchetti, radice and guide file of the module with copia
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
    CS=$MAAT_SCRIPTS/cycle-state.sh   # the session's plugin, not the harness of the worktree's commit
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
    # sync, not merge: full copy next to it (name spec-*: gitignored), then it replaces the old one
    nuova="$MAINC/$RUN_REL.nuova.$$" vecchia="$MAINC/$RUN_REL.vecchia.$$"
    # interrupted mid-swap: drop the new copy, and the old one goes back in place if the run dir is missing
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
RP=$MAAT_SCRIPTS/run-phase.sh   # the session's plugin; the lock is still the worktree's (cwd)
if [ -f "$RP" ]; then
  ls_out=$( (cd "$WT" && env -u FIC_LOCK -u FIC_PHASE -u FIC_REPO bash "$RP" --lock-status 2>&1) ); ls_rc=$?
  [ $ls_rc -eq 0 ] || stop "lock delle fasi di codice del worktree non libero: $(printf '%s' "$ls_out" | tr -d '\r'). Un ciclo gira li': prima fermalo"
fi
# plan lock (<run-dir>/plan.lock): alive if one of its pids exists, or if just created without owner (as run-phase.sh)
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
# running phase: log/<label>.running without .exit (the driver reads it as RUNNING): alive, or dead without closing
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
# the cycle's spec and run dir: they would go away with the worktree; they must already be in the main tree
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
