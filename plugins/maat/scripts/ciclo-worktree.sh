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
#      them); on resume the worktree's ones win and are not overwritten. A mother spec (a `Figlie:`/`Children:`
#      line, read as driver.py reads it) brings its rings too, `spec-<figlia>.md` and `spec-<figlia>.run/` from the
#      mother's folder, with the same rules (1.6.1); a ring missing there is a STOP before anything is created;
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
#   in the marker: someone worked on them there), unless --forza. A chain's rings come back with the mother, each
#   checked on its own, all checks before any copy (1.6.1); rimuovi and stato look at the rings too.
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
# Tests: script/fic/worktree-cycle.test.sh (fake repo, fake HOME, counterproof by mutation).

set -uo pipefail
unset MSYS_NO_PATHCONV
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_ROOT and MAAT_SCRIPTS (plugin), MAAT_WORK (project)
# Messages (1.4.0): the catalog next to this script (English by default, Italian with "lingua": "it"); the sub-commands,
# --forza and the marker lines stay as they are
. "$HERE/lib/maat-msg.sh"; maat_msg_carica
TAG=ciclo-worktree

say() { echo "$TAG: $*"; }
die() { echo "$TAG: $*" >&2; exit 2; }
stop() { echo "$TAG: STOP — $*" >&2; exit 3; }
q() { printf '%q' "$1"; }

WT_TAG=$TAG
. "$HERE/worktree-lib.sh" || die "$(msg worktree-cycle.no_lib here="$HERE" here="$HERE")"

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
    --base) BASE_REF=${2:-}; [ -n "$BASE_REF" ] || die "$(msg worktree-cycle.base_ref)"; shift 2 ;;
    --base=*) BASE_REF=${1#--base=}; [ -n "$BASE_REF" ] || die "$(msg worktree-cycle.base_ref)"; shift ;;
    --forza) FORCE=1; shift ;;
    --branch) DELBRANCH=1; shift ;;
    -*) die "$(msg worktree-cycle.unknown_opt opt="$1")" ;;
    *) [ -z "$ARG" ] || die "$(msg worktree-cycle.one_arg a="$ARG" b="$1")"; ARG=$1; shift ;;
  esac
done
USO="$(msg worktree-cycle.usage)"
[ -n "$ARG" ] || die "$USO"
case "$CMD" in
  crea) [ $DELBRANCH -eq 0 ] && [ $FORCE -eq 0 ] || die "$(msg worktree-cycle.crea_opts)" ;;
  stato) [ -z "$BASE_REF" ] && [ $DELBRANCH -eq 0 ] && [ $FORCE -eq 0 ] || die "$(msg worktree-cycle.stato_opts)" ;;
  riporta) [ -z "$BASE_REF" ] && [ $DELBRANCH -eq 0 ] || die "$(msg worktree-cycle.riporta_opts)" ;;
  rimuovi) [ -z "$BASE_REF" ] || die "$(msg worktree-cycle.rimuovi_opts)" ;;
  *) die "$USO" ;;
esac

# --- repository: the current folder's ---
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "$(msg worktree-cycle.not_git)"
MAIN=$(cd "$(dirname "$common")" 2>/dev/null && pwd) || die "$(msg worktree-cycle.main_unresolved common="$common")"
# pk09 (pilot on a second project): from a LINKED worktree (git dir ≠ git common dir) we would climb to the main tree and
# take its base, maat.json and spec. Refused for every subcommand, before reading or creating anything
gdir=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || die "$(msg worktree-cycle.gitdir_unresolved)"
[ "$gdir" = "$common" ] || stop "$(msg worktree-cycle.from_linked main="$MAIN" top="$(git rev-parse --show-toplevel 2>/dev/null)")"
MAINC=$(canon "$MAIN")
[ "$(canon "$(git -C "$MAIN" rev-parse --show-toplevel 2>/dev/null)")" = "$MAINC" ] || die "$(msg worktree-cycle.main_invalid main="$MAINC")"
# links, dependency files, preparati and copia: the main tree's maat.json, read once
wt_conf_carica || die "$(msg worktree-cycle.conf_unreadable)"

if [ "$CMD" = crea ]; then
  SPEC=$ARG
  [ -f "$SPEC" ] || die "$(msg worktree-cycle.spec_missing spec="$SPEC")"
  NAME=$(basename "$SPEC"); NAME=${NAME%.md}; NAME=${NAME#spec-}
  case "$(basename "$SPEC")" in spec-*.md) ;; *) die "$(msg worktree-cycle.spec_name spec="$SPEC")" ;; esac
  SPEC=$(cd "$(dirname "$SPEC")" && pwd)/$(basename "$SPEC")
  RUN_SRC=${SPEC%.md}.run
else
  NAME=${ARG#spec-}; NAME=${NAME%.md}; NAME=$(basename "$NAME")
fi
printf '%s' "$NAME" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*$' || die "$(msg worktree-cycle.name_invalid name="$NAME")"
BRANCH=fic/$NAME
WT="$(dirname "$MAINC")/$(basename "$MAINC")-fic-$NAME"
MK_REL=$AIW/spec-$NAME.worktree
SPEC_REL=$AIW/spec-$NAME.md RUN_REL=$AIW/spec-$NAME.run

mk_re() { printf '%s' "$1" | sed 's/[.]/\\./g'; }   # a key as a literal regex (children's names may have dots)
mk_get() { sed -n "s/^$(mk_re "$1")=//p" "$WT/$MK_REL" 2>/dev/null | tr -d '\r' | head -1; }
mk_set() { # $1 key, $2 value: rewrites the line in the marker
  local f=$WT/$MK_REL
  { grep -v "^$(mk_re "$1")=" "$f"; printf '%s=%s\n' "$1" "$2"; } > "$f.tmp" && mv "$f.tmp" "$f"
}

# --- the children of a mother spec (1.6.1): its "Figlie:"/"Children:" line, read as driver.py's _cfiglie does
#     (outside the fences, above the plan; the first line with either literal wins; .md and a final dot dropped).
#     The chain's rings live next to the mother: crea copies them with it, riporta brings them back, rimuovi checks them.
figlie_of() { # $1 spec file → the children's names (without spec- and .md), one per line, in order, no repeats
  [ -f "$1" ] || return 0
  awk '{ sub(/\r$/, "") }
       /^[ \t]*(```|~~~)/ { f = !f; next }
       f { next }
       /^## (Piano di implementazione|Review implementazione|Implementation plan|Implementation review)/ { exit }
       /^(Figlie|Children):/ { sub(/^(Figlie|Children):/, ""); print; exit }' "$1" |
    grep -oE 'spec-[A-Za-z0-9._-]*' | sed -e 's/\.md$//' -e 's/\.$//' -e 's/^spec-//' | awk '!seen[$0]++'
}
FIGLIE=()   # filled by each subcommand: from the main tree's mother (crea) or the worktree's (the others)
carica_figlie() { # $1 mother spec file → FIGLIE: the names driver.py accepts ([A-Za-z0-9._-], never a /: always a
  # file spec-<name>.md inside $AIW); the mother itself and an empty name (a bare spec-) are skipped
  local c
  FIGLIE=()
  while IFS= read -r c; do
    [ -n "$c" ] && [ "$c" != "$NAME" ] || continue
    FIGLIE+=("$c")
  done < <(figlie_of "$1")
}

# --- is the path the worktree created by this script for <nome>? (0 = yes; otherwise the reason on stderr) ---
ours() {
  local c w found=0
  [ -d "$WT" ] || { echo "$(msg worktree-cycle.not_exists wt="$WT")" >&2; return 1; }
  c=$(canon "$WT")
  [ "$(canon "$(git -C "$c" rev-parse --show-toplevel 2>/dev/null)")" = "$c" ] || { echo "$(msg worktree-cycle.not_wt_root c="$c")" >&2; return 1; }
  [ "$c" != "$MAINC" ] || { echo "$(msg worktree-cycle.is_main c="$c")" >&2; return 1; }
  [ -f "$c/$MK_REL" ] || { echo "$(msg worktree-cycle.no_marker mk="$MK_REL")" >&2; return 1; }
  [ "$(head -1 "$c/$MK_REL" | tr -d '\r')" = fic-ciclo-worktree ] || { echo "$(msg worktree-cycle.marker_invalid c="$c" mk="$MK_REL")" >&2; return 1; }
  [ "$(canon "$(mk_get path)")" = "$c" ] || { echo "$(msg worktree-cycle.marker_path p="$(mk_get path)")" >&2; return 1; }
  [ "$(mk_get branch)" = "$BRANCH" ] || { echo "$(msg worktree-cycle.marker_branch b="$(mk_get branch)")" >&2; return 1; }
  [ "$(git -C "$c" symbolic-ref --short -q HEAD)" = "$BRANCH" ] || { echo "$(msg worktree-cycle.not_on_branch b="$BRANCH")" >&2; return 1; }
  while IFS= read -r w; do [ "$(canon "$w")" = "$c" ] && found=1; done < <(git -C "$MAIN" worktree list --porcelain | sed -n 's/^worktree //p')
  [ $found -eq 1 ] || { echo "$(msg worktree-cycle.not_listed c="$c")" >&2; return 1; }
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
# The messages of the WSL check of `crea` (1.4.0): the program runs in WSL, where the catalog is not loaded, so they are
# rendered here as variables M_*, with markers @X@ that its m() replaces with the values known only there.
wsl_msgs() {
  printf 'M_LIB=%q\n' "$(msg worktree-cycle.wsl_lib l=@L@)"
  printf 'M_ROOT=%q\n' "$(msg worktree-cycle.wsl_root r=@R@)"
  printf 'M_UNEXPECTED=%q\n' "$(msg worktree-cycle.wsl_unexpected fm=@FM@)"
  printf 'M_SEEDED_ALREADY=%q\n' "$(msg worktree-cycle.wsl_seeded_already fm=@FM@ p=@P@)"
  printf 'M_SEED_FAILED=%q\n' "$(msg worktree-cycle.wsl_seed_failed why=@WHY@)"
  printf 'M_SEEDED=%q\n' "$(msg worktree-cycle.wsl_seeded fm=@FM@ p=@P@)"
  printf 'M_FP=%q\n' "$(msg worktree-cycle.wsl_fp)"
  printf 'M_GUIDE_MISSING=%q\n' "$(msg worktree-cycle.wsl_guide_missing g=@G@ r=@R@ d=@D@)"
  printf 'M_GUIDE_OK=%q\n' "$(msg worktree-cycle.wsl_guide_ok d=@D@ g=@G@)"
}

# --- unlinking and check: no link may be left before removing the folder ---
links_left() { # $1 worktree → the leftover links (one per line), from Git Bash, then from Windows, then from WSL.
  # Exit ≠ 0 if a check failed (find, dir or WSL failed): the caller stops.
  # Each view runs only if the previous one found none: `dir /S` TRAVERSES junctions (measured), and on a leftover
  # one it would walk the main tree's whole node_modules (read-only, but slow).
  local wt=$1 w out rc err
  [ -d "$wt" ] || { echo "$TAG: $(msg worktree-cycle.not_dir wt="$wt")" >&2; return 2; }
  out=$(find "$wt" -type l) || { echo "$TAG: $(msg worktree-cycle.find_failed wt="$wt")" >&2; return 2; }
  if [ -z "$out" ] && [ $WIN -eq 1 ]; then   # reparse points (junctions and symlinks) as seen from Windows
    err=$(mktemp) || return 2
    out=$(MSYS2_ARG_CONV_EXCL='*' cmd.exe /c dir /AL /S /B "$(cygpath -w "$wt")" 2>"$err" | tr -d '\r' | sed '/^$/d'); rc=${PIPESTATUS[0]}
    # dir exits 1 with «File non trovato» (or «File Not Found») when there is no reparse point: that is the good case
    # (the folder exists, checked above); any other outcome is a failed check
    if [ -z "$out" ] && ! { [ "$rc" -eq 1 ] && grep -qiE 'non trovato|not found' "$err"; }; then
      echo "$TAG: $(msg worktree-cycle.dir_failed wt="$wt" rc="$rc" err="$(tr -d '\r' < "$err")")" >&2; rm -f "$err"; return 2
    fi
    rm -f "$err"
  fi
  if [ -z "$out" ] && use_wsl && [ $WIN -eq 1 ]; then
    w=$(wsl_path "$wt")
    out=$(printf 'find %s -type l\n' "$(q "$w")" | wsl_run) || { echo "$TAG: $(msg worktree-cycle.wsl_find_failed w="$w")" >&2; return 2; }
  fi
  [ -z "$out" ] || printf '%s\n' "$out"
  return 0
}
scollega_e_verifica() { # $1 worktree: 0 = no link left; 1 = something left, or check failed (stderr)
  local wt=$1 left
  unlink_deps "$wt" || return 1
  left=$(links_left "$wt") || { echo "$TAG: $(msg worktree-cycle.check_failed)" >&2; return 1; }
  left=$(printf '%s' "$left" | LC_ALL=C sort -u)
  [ -z "$left" ] && return 0
  echo "$TAG: $(msg worktree-cycle.links_left)" >&2; printf '  %s\n' "$left" >&2
  return 1
}

# ============================================================================================ crea
if [ "$CMD" = crea ]; then
  . "$MAAT_SCRIPTS/python.sh" || die "$(msg worktree-cycle.no_python)"
  RESUME=0
  if [ -e "$WT" ] || [ -L "$WT" ]; then
    why=$(ours 2>&1) || stop "$(msg worktree-cycle.not_ours wt="$WT" name="$NAME" why="$why")"
    RESUME=1
    say "$(msg worktree-cycle.resume wt="$WT")"
  elif git -C "$MAIN" show-ref --verify -q "refs/heads/$BRANCH"; then
    stop "$(msg worktree-cycle.branch_exists b="$BRANCH" wt="$WT" b="$BRANCH")"
  fi
  # the chain's rings (1.6.1): from the worktree's mother on resume (it wins), otherwise from the given one; each ring
  # must be next to the mother (in the worktree on resume, or where the mother is): none missing, BEFORE creating anything
  if [ $RESUME -eq 1 ] && [ -f "$WT/$SPEC_REL" ]; then carica_figlie "$WT/$SPEC_REL"; else carica_figlie "$SPEC"; fi
  SDIR=$(dirname "$SPEC")
  for c in ${FIGLIE[@]+"${FIGLIE[@]}"}; do
    [ -f "$WT/$AIW/spec-$c.md" ] || [ -f "$SDIR/spec-$c.md" ] ||
      stop "$(msg worktree-cycle-161.child_missing c="spec-$c.md" d="$SDIR" m="spec-$NAME.md")"
  done
  if [ $RESUME -eq 0 ]; then
    BASE=$(git -C "$MAIN" rev-parse --verify -q "${BASE_REF:-HEAD}^{commit}") || die "$(msg worktree-cycle.base_invalid ref="${BASE_REF:-HEAD}")"
    # dependencies: do the main tree's ones hold for the base? (before creating anything)
    DD=$(deps_diff "$BASE")
    [ -z "$DD" ] || stop "$(msg worktree-cycle.deps_base base="${BASE:0:12}" dd="$(echo $DD)")"
    git -C "$MAIN" worktree add -q -b "$BRANCH" "$WT" "$BASE" || die "$(msg worktree-cycle.wt_add_failed wt="$WT")"
    mkdir -p "$WT/$AIW" && printf 'fic-ciclo-worktree\npath=%s\nbranch=%s\nbase=%s\nprincipale=%s\nprincipale_run=%s\ncreato=%s\n' \
      "$(canon "$WT")" "$BRANCH" "$BASE" "$(sha "$MAINC/$SPEC_REL")" "$(dir_fp "$MAINC/$RUN_REL")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WT/$MK_REL" ||
      die "$(msg worktree-cycle.marker_unwritable wt="$WT" mk="$MK_REL")"
    if ! git -C "$WT" check-ignore -q "$MK_REL"; then   # the marker must never be review surface
      git -C "$MAIN" worktree remove --force "$WT" && git -C "$MAIN" branch -D -q "$BRANCH"
      stop "$(msg worktree-cycle.not_ignored mk="$MK_REL" base="${BASE:0:12}" aiw="$AIW")"
    fi
    fic_relgit "$WT" || say "$(msg worktree-cycle.abs_gitdir)"
    say "$(msg worktree-cycle.created wt="$WT" b="$BRANCH" base="${BASE:0:12}" root="$MAAT_ROOT")"
  else
    BASE=$(mk_get base)
    # on resume: the base's dependencies still equal to the main tree's, and the cycle did not change them in the
    # worktree (neither modified nor added as untracked files)
    mapfile -t DEP_PS < <(dep_ps)   # file_dipendenze of maat.json; none: nothing to compare
    DD=$( { deps_diff "$BASE"; if [ ${#DEP_PS[@]} -gt 0 ]; then git -C "$WT" -c core.quotePath=false diff --name-only HEAD -- "${DEP_PS[@]}"
            git -C "$WT" -c core.quotePath=false ls-files -o --exclude-standard -- "${DEP_PS[@]}"; fi; } | LC_ALL=C sort -u)
    [ -z "$DD" ] || stop "$(msg worktree-cycle.deps_resume dd="$(echo $DD)")"
  fi

  # links: the main tree's dependencies, never copied
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -L "$WT/$p" ]; then continue
    elif [ -e "$WT/$p" ]; then say "$(msg worktree-cycle.real_dir p="$p")"
    else link_dep "$MAINC/$p" "$WT/$p" || stop "$(msg worktree-cycle.link_failed p="$p")"
    fi
  done < <(dep_links "$MAINC")
  n=$(dep_links "$WT" | while IFS= read -r p; do [ -L "$WT/$p" ] && echo "$p"; done | wc -l)
  say "$(msg worktree-cycle.linked n="$n" links="$(dep_links "$WT" | tr '\n' ' ')")"

  # spec and run dir: copied at creation; on resume the worktree's ones win
  if [ -f "$WT/$SPEC_REL" ]; then
    say "$(msg worktree-cycle.spec_kept rel="$SPEC_REL")"
    [ "$(sha "$MAINC/$SPEC_REL")" = "$(mk_get principale)" ] ||
      say "$(msg worktree-cycle.spec_changed)"
  else
    cp "$SPEC" "$WT/$SPEC_REL" || die "$(msg worktree-cycle.spec_copy_failed)"
    say "$(msg worktree-cycle.spec_copied rel="$SPEC_REL")"
  fi
  if [ -d "$RUN_SRC" ] && [ ! -e "$WT/$RUN_REL" ]; then
    cp -R "$RUN_SRC" "$WT/$RUN_REL" || die "$(msg worktree-cycle.run_copy_failed)"
    say "$(msg worktree-cycle.run_copied rel="$RUN_REL")"
  fi
  # the rings, with the same rules (1.6.1); their main-tree fingerprints go in the marker, as the mother's, for riporta
  for c in ${FIGLIE[@]+"${FIGLIE[@]}"}; do
    crel=$AIW/spec-$c.md rrel=$AIW/spec-$c.run
    if [ -f "$WT/$crel" ]; then
      say "$(msg worktree-cycle.spec_kept rel="$crel")"
      k=$(mk_get "figlia.$c")
      [ -z "$k" ] || [ "$(sha "$MAINC/$crel")" = "$k" ] || say "$(msg worktree-cycle.spec_changed)"
    else
      cp "$SDIR/spec-$c.md" "$WT/$crel" || die "$(msg worktree-cycle.spec_copy_failed)"
      say "$(msg worktree-cycle.spec_copied rel="$crel")"
    fi
    if [ -d "$SDIR/spec-$c.run" ] && [ ! -e "$WT/$rrel" ]; then
      cp -R "$SDIR/spec-$c.run" "$WT/$rrel" || die "$(msg worktree-cycle.run_copy_failed)"
      say "$(msg worktree-cycle.run_copied rel="$rrel")"
    fi
    [ -n "$(mk_get "figlia.$c")" ] || mk_set "figlia.$c" "$(sha "$MAINC/$crel")"
    [ -n "$(mk_get "figlia_run.$c")" ] || mk_set "figlia_run.$c" "$(dir_fp "$MAINC/$rrel")"
  done

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
          mkdir -p "$(dirname "$WT/$rel")" && cp "$f" "$WT/$rel" || die "$(msg worktree-cycle.prep_copy_failed rel="$rel")"
          nc=$((nc + 1))
        done
      done
      say "$(msg worktree-cycle.prep_copied rad="$rad" nc="$nc" guida="$guida")"
    elif [ -d "$MAINC/$rad" ]; then
      say "$(msg worktree-cycle.prep_missing pre="$pre" guida="$guida" cmd="$prepcmd" rad="$rad")"
    fi
  done < <(wt_conf)
  deps_fp_check "$MAINC" "$WT" >/dev/null 2>&1
  [ -z "$FPWARN" ] || say "$(msg worktree-cycle.fp_warn w="$FPWARN")"

  # WSL copy of the worktree, for each module with copia: seeded and with the guide file of the preparati
  cw=()
  while IFS=$'\t' read -r k p rad guida; do
    [ "$k" = copia ] || continue
    [ "$guida" = - ] && guida=""   # empty guide (wt_conf placeholder)
    cw+=("$p" "$rad" "$guida")
  done < <(wt_conf)
  if [ ${#cw[@]} -eq 0 ]; then
    say "$(msg worktree-cycle.no_copia)"
  elif use_wsl; then
    lw=$(wsl_path "$WTLIB_TEST/fic-mirror.sh") rw=$(wsl_path "$WT")
    out=$({ printf 'L=%s R=%s\n' "$(q "$lw")" "$(q "$rw")"; printf 'export MAAT_LINGUA=%q\n' "$(maat_lingua)"
            printf 'set --'; printf ' %q' "${cw[@]}"; printf '\n'
            wsl_msgs; cat <<'EOS'
shopt -u patsub_replacement 2>/dev/null || true   # bash 5.2: a & in a path stays a & in the replacement
m() { local t=$1; t=${t//@L@/"$L"}; t=${t//@R@/"$R"}; t=${t//@FM@/"$FIC_MIRROR"}; t=${t//@P@/"$P"}
      t=${t//@D@/"$D"}; t=${t//@G@/"$G"}; t=${t//@WHY@/"$why"}; printf '%s\n' "$t"; }
. "$L" || { m "$M_LIB"; exit 1; }
fic_mirror_init "$R" || { m "$M_ROOT"; exit 1; }
case "$FIC_MIRROR" in "$HOME"/fic-mirror-????????????) ;; *) m "$M_UNEXPECTED"; exit 1 ;; esac
while [ $# -ge 3 ]; do
  P=$1 D=$2 G=$3; shift 3   # radice_pacchetti, radice and guide file of the module with copia
  if [ -d "$FIC_MIRROR/$P/node_modules" ] && [ -f "$FIC_MIRROR/$P/.fic-deps" ]; then
    m "$M_SEEDED_ALREADY"
  else
    why=$(fic_seed_node_modules "$R/$P" "$FIC_MIRROR/$P") || { m "$M_SEED_FAILED"; exit 1; }
    m "$M_SEEDED"
  fi
  fic_deps_ok "$R/$P" "$FIC_MIRROR/$P" || m "$M_FP"
  [ -n "$G" ] || continue
  [ -f "$R/$D/$G" ] || { m "$M_GUIDE_MISSING"; exit 1; }
  m "$M_GUIDE_OK"
done
EOS
    } | wsl_run 2>&1); rc=$?
    printf '%s\n' "$out" | sed "s/^/$TAG: /"
    [ $rc -eq 0 ] || { echo "$TAG: $(msg worktree-cycle.wsl_failed wt="$WT")" >&2; exit 1; }
  else
    say "$(msg worktree-cycle.wsl_skipped)"
  fi
  canon "$WT"
  exit 0
fi

# ============================================================================================ stato
if [ "$CMD" = stato ]; then
  [ -d "$WT" ] || { say "$(msg worktree-cycle.no_wt name="$NAME" wt="$WT")"; exit 1; }
  echo "$(msg worktree-cycle.st_path p="$(canon "$WT")")"
  echo "branch: $(git -C "$WT" symbolic-ref --short -q HEAD || msg worktree-cycle.st_detached) · HEAD $(git -C "$WT" rev-parse --short=12 HEAD 2>/dev/null) · base $(mk_get base | cut -c1-12)"
  if why=$(ours 2>&1); then echo "$(msg worktree-cycle.st_owner mk="$MK_REL")"; else echo "$(msg worktree-cycle.st_not_owner why="$why")"; fi
  if [ -f "$WT/$SPEC_REL" ]; then
    if cmp -s "$WT/$SPEC_REL" "$MAINC/$SPEC_REL"; then r=si; else r=no; fi
    echo "$(msg worktree-cycle.st_spec wt="$(canon "$WT")" rel="$SPEC_REL" r="$r")"
    CS=$MAAT_SCRIPTS/cycle-state.sh   # the session's plugin, not the harness of the worktree's commit
    echo "$(msg worktree-cycle.st_cycle c="$( (cd "$WT" && bash "$CS" "$SPEC_REL" 2>&1) | tr -d '\r' | grep -E '^(State|Next):' | tr '\n' ' ')")"
    carica_figlie "$WT/$SPEC_REL"   # the chain's rings (1.6.1), same line each
    for c in ${FIGLIE[@]+"${FIGLIE[@]}"}; do
      crel=$AIW/spec-$c.md
      if [ -f "$WT/$crel" ]; then
        if cmp -s "$WT/$crel" "$MAINC/$crel"; then r=si; else r=no; fi
        echo "$(msg worktree-cycle.st_spec wt="$(canon "$WT")" rel="$crel" r="$r")"
      else echo "$(msg worktree-cycle.rp_no_spec wt="$(canon "$WT")" rel="$crel")"; fi
    done
  else
    echo "$(msg worktree-cycle.st_no_spec)"
  fi
  RP=$MAAT_SCRIPTS/run-phase.sh
  [ -f "$RP" ] && echo "lock: $( (cd "$WT" && env -u FIC_LOCK -u FIC_PHASE -u FIC_REPO bash "$RP" --lock-status 2>&1) | tr -d '\r')"
  st=$(git -C "$WT" status --porcelain --untracked-files=all)
  echo "$(msg worktree-cycle.st_changed n="$(printf '%s' "$st" | grep -c .)")"
  [ -z "$st" ] || printf '%s\n' "$st"
  exit 0
fi

why=$(ours 2>&1) || stop "$(msg worktree-cycle.not_ours_stop wt="$WT" name="$NAME" why="$why")"

# ============================================================================================ riporta
if [ "$CMD" = riporta ]; then
  [ -f "$WT/$SPEC_REL" ] || stop "$(msg worktree-cycle.rp_no_spec wt="$WT" rel="$SPEC_REL")"
  carica_figlie "$WT/$SPEC_REL"
  # units: the mother, then each ring (1.6.1) — <spec rel> <run rel> <marker key of the spec> <marker key of the run>
  UNITS=("$SPEC_REL" "$RUN_REL" principale principale_run)
  for c in ${FIGLIE[@]+"${FIGLIE[@]}"}; do UNITS+=("$AIW/spec-$c.md" "$AIW/spec-$c.run" "figlia.$c" "figlia_run.$c"); done
  # every check first, file by file: nothing is copied if one of them changed in the main tree after the copy
  for ((i = 0; i < ${#UNITS[@]}; i += 4)); do
    s=${UNITS[i]} r=${UNITS[i+1]} ks=${UNITS[i+2]} kr=${UNITS[i+3]}
    # a ring not in the worktree, or without its fingerprints (a worktree made before 1.6.1): crea again resumes,
    # copies the ring and records them; --forza brings back what is there
    if [ $i -gt 0 ] && { [ ! -f "$WT/$s" ] || [ -z "$(mk_get "$ks")" ]; } && [ $FORCE -eq 0 ]; then
      stop "$(msg worktree-cycle-161.rp_child_resume rel="$s" spec="$SPEC_REL")"
    fi
    [ -f "$WT/$s" ] || { [ $i -gt 0 ] && continue; stop "$(msg worktree-cycle.rp_no_spec wt="$WT" rel="$s")"; }
    cur=$(sha "$MAINC/$s") exp=$(mk_get "$ks") new=$(sha "$WT/$s")
    if [ "$cur" != "$exp" ] && [ "$cur" != "$new" ] && [ $FORCE -eq 0 ]; then
      stop "$(msg worktree-cycle.rp_spec_changed rel="$s")"
    fi
    rcur=$(dir_fp "$MAINC/$r") rexp=$(mk_get "$kr") rnew=$(dir_fp "$WT/$r")
    if [ -d "$WT/$r" ] && [ "$rcur" != "$rexp" ] && [ "$rcur" != "$rnew" ] && [ $FORCE -eq 0 ]; then
      stop "$(msg worktree-cycle.rp_run_changed rel="$r")"
    fi
  done
  sync_run() { # $1 run dir rel: worktree → main tree
    # sync, not merge: full copy next to it (name spec-*: gitignored), then it replaces the old one
    local rel=$1 rnew
    rnew=$(dir_fp "$WT/$rel")
    new_run="$MAINC/$rel.nuova.$$" old_run="$MAINC/$rel.vecchia.$$" RREL=$rel
    # interrupted mid-swap: drop the new copy, and the old one goes back in place if the run dir is missing
    restore_old() { [ -e "$MAINC/$RREL" ] || [ ! -d "$old_run" ] || mv "$old_run" "$MAINC/$RREL"; }
    trap 'rm -rf "$new_run"; restore_old || echo "$TAG: $(msg worktree-cycle.rp_prev_kept old="$old_run")" >&2; exit 130' INT TERM HUP
    cp -R "$WT/$rel" "$new_run" || { rm -rf "$new_run"; die "$(msg worktree-cycle.rp_copy_failed)"; }
    if [ -d "$MAINC/$rel" ]; then mv "$MAINC/$rel" "$old_run" || { rm -rf "$new_run"; die "$(msg worktree-cycle.rp_not_movable)"; }; fi
    if ! mv "$new_run" "$MAINC/$rel"; then
      rm -rf "$new_run"
      [ -d "$old_run" ] || die "$(msg worktree-cycle.rp_none_prev)"
      mv "$old_run" "$MAINC/$rel" && die "$(msg worktree-cycle.rp_restored)"
      die "$(msg worktree-cycle.rp_not_restored old="$old_run" m="$MAINC" rel="$rel")"
    fi
    trap - INT TERM HUP
    rm -rf "$old_run"
    [ "$(dir_fp "$MAINC/$rel")" = "$rnew" ] || die "$(msg worktree-cycle.rp_differs)"
    say "$(msg worktree-cycle.rp_run_done m="$MAINC" rel="$rel")"
  }
  mkdir -p "$MAINC/$AIW" || die "$(msg worktree-cycle.spec_copy_failed)"
  for ((i = 0; i < ${#UNITS[@]}; i += 4)); do
    s=${UNITS[i]} r=${UNITS[i+1]} ks=${UNITS[i+2]} kr=${UNITS[i+3]}
    [ -f "$WT/$s" ] || continue   # a ring missing in the worktree, with --forza: nothing of it to bring back
    cp "$WT/$s" "$MAINC/$s" || die "$(msg worktree-cycle.spec_copy_failed)"
    say "$(msg worktree-cycle.rp_spec_done m="$MAINC" rel="$s")"
    [ ! -d "$WT/$r" ] || sync_run "$r"
    mk_set "$ks" "$(sha "$WT/$s")"
    mk_set "$kr" "$(dir_fp "$MAINC/$r")"
  done
  say "$(msg worktree-cycle.rp_code_left b="$BRANCH" wt="$(canon "$WT")")"
  exit 0
fi

# ============================================================================================ rimuovi
RP=$MAAT_SCRIPTS/run-phase.sh   # the session's plugin; the lock is still the worktree's (cwd)
if [ -f "$RP" ]; then
  ls_out=$( (cd "$WT" && env -u FIC_LOCK -u FIC_PHASE -u FIC_REPO bash "$RP" --lock-status 2>&1) ); ls_rc=$?
  [ $ls_rc -eq 0 ] || stop "$(msg worktree-cycle.rm_lock out="$(printf '%s' "$ls_out" | tr -d '\r')")"
fi
# the mother's run dir and the rings' (1.6.1: the driver runs a ring's phases in the ring's run dir)
carica_figlie "$WT/$SPEC_REL"
RUNS=("$RUN_REL"); SPECS=("$SPEC_REL")
for c in ${FIGLIE[@]+"${FIGLIE[@]}"}; do RUNS+=("$AIW/spec-$c.run"); SPECS+=("$AIW/spec-$c.md"); done
# plan lock (<run-dir>/plan.lock): alive if one of its pids exists, or if just created without owner (as run-phase.sh)
for rr in "${RUNS[@]}"; do
  PL=$WT/$rr/plan.lock
  [ -d "$PL" ] || continue
  if [ -f "$PL/owner" ]; then
    for k in pid cpid; do
      p=$(sed -n "s/^$k=//p" "$PL/owner" | tr -d '\r' | head -1)
      [ -n "$p" ] && kill -0 "$p" 2>/dev/null && stop "$(msg worktree-cycle.rm_plan_alive rel="$rr" k="$k" p="$p")"
    done
  elif [ -z "$(find "$PL" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    stop "$(msg worktree-cycle.rm_plan_new rel="$rr")"
  fi
done
# running phase: log/<label>.running without .exit (the driver reads it as RUNNING): alive, or dead without closing
running=""
for rr in "${RUNS[@]}"; do
  for f in "$WT/$rr"/log/*.running; do
    [ -e "$f" ] && [ ! -e "${f%.running}.exit" ] && running="$running $(basename "${f%.running}")"
  done
done
if [ -n "$running" ] && [ $FORCE -eq 0 ]; then
  stop "$(msg worktree-cycle.rm_running running="$running")"
fi
[ -z "$running" ] || say "$(msg worktree-cycle.rm_running_forced running="$running")"
st=$(git -C "$WT" status --porcelain --untracked-files=all)
if [ -n "$st" ] && [ $FORCE -eq 0 ]; then
  stop "$(msg worktree-cycle.rm_dirty n="$(printf '%s\n' "$st" | grep -c .)" wt="$(q "$(canon "$WT")")")"
fi
# the cycle's spec and run dir: they would go away with the worktree; they must already be in the main tree
nr=""
for ((i = 0; i < ${#SPECS[@]}; i++)); do
  s=${SPECS[i]} r=${RUNS[i]}
  if [ -f "$WT/$s" ] && ! cmp -s "$WT/$s" "$MAINC/$s"; then
    nr="${nr:+$(msg worktree-cycle.rm_nr_and nr="$nr")}$(msg worktree-cycle.rm_nr_spec rel="$s")"
  fi
  if [ -d "$WT/$r" ] && ! diff -rq "$WT/$r" "$MAINC/$r" >/dev/null 2>&1; then
    nr="$(msg worktree-cycle.rm_nr_run joined="${nr:+$(msg worktree-cycle.rm_nr_and nr="$nr")}" rel="$r")"
  fi
done
if [ -n "$nr" ]; then
  [ $FORCE -eq 1 ] || stop "$(msg worktree-cycle.rm_not_back nr="$nr" name="$NAME")"
  say "$(msg worktree-cycle.rm_not_back_forced nr="$nr")"
fi
if use_wsl; then forget_mirror "$WT"; else say "$(msg worktree-cycle.rm_no_wsl)"; fi
scollega_e_verifica "$WT" || stop "$(msg worktree-cycle.rm_links_left wt="$WT")"
say "$(msg worktree-cycle.rm_unlinked)"
if [ $FORCE -eq 1 ]; then git -C "$MAIN" worktree remove --force "$WT"; else git -C "$MAIN" worktree remove "$WT"; fi ||
  die "$(msg worktree-cycle.rm_failed wt="$WT")"
[ ! -e "$WT" ] || die "$(msg worktree-cycle.rm_still wt="$WT")"
say "$(msg worktree-cycle.rm_done wt="$WT")"
if [ $DELBRANCH -eq 1 ]; then
  git -C "$MAIN" branch -d -q "$BRANCH" || die "$(msg worktree-cycle.rm_branch_kept b="$BRANCH" b="$BRANCH")"
  say "$(msg worktree-cycle.rm_branch_done b="$BRANCH")"
else
  say "$(msg worktree-cycle.rm_branch_left b="$BRANCH")"
fi
exit 0
