# fic-mirror.sh — shared functions of the WSL copy (harness-pt03): destination, dependency fingerprint,
# seeding of node_modules, deletion of a worktree's copy. It is SOURCED with `.` by test-fast.sh,
# counterproof.sh and (via WSL) corpus/replay.sh: it is not executed, and has no effect until a function is called.
# It writes only under $HOME/fic-mirror-<hash> (never in $HOME/fic-mirror, never in the repository).
#
# PACKAGES DIRECTORY: the CALLER decides it, no default. It is the module's packages root
# (`radice_pacchetti` in maat.json), relative to the repository; the copy keeps it at the same relative path,
# <copy> = $FIC_MIRROR/<dir>. The caller passes it in the two arguments <source> = <root>/<dir> and
# <copy> = $FIC_MIRROR/<dir>; the functions derive <dir> from them (fic__pkg) to find the linked copies
# (the one of the main tree, the one of a lane's root) at the same path. A <copy> outside
# $FIC_MIRROR is a caller error: reason and exit 1, never a guessed directory.
#
# DESTINATION (fic_mirror_init <root>): $HOME/fic-mirror from the main tree, $HOME/fic-mirror-<first 12
# characters of the sha256 of the root> from a linked worktree (git-dir different from git-common-dir).
# Worktree created by Git for Windows: its .git file says "gitdir: C:/…", which the WSL git does not resolve; here
# it is translated to /mnt/c/… and exported as GIT_DIR (with GIT_WORK_TREE = root), so that both the
# destination and the manifest work. FIC_WSL_MNT changes the drives root (default /mnt; used by the tests).
#
# DEPENDENCY FINGERPRINT (fic_deps_fp): all package.json files outside node_modules/.nuxt/.output and the
# package-lock.json files, on the content WITHOUT CR: two checkouts with different line endings give the same fingerprint.
# fic_deps_ok also accepts a .fic-deps written before this rule (fingerprint of the bytes).
#
# SEEDING (fic_seed_node_modules): the copy of a worktree without node_modules takes them from the copy of the main
# tree with hardlinks (rsync --link-dest: no installs, no space), ONLY if that copy is
# valid for the main tree and the worktree dependencies match (normalised fingerprint) those of the
# main tree. The caches (.cache, .vite, .vitest) are not seeded: the run writes them, as new files.
# A stale seeding source (copy of the main tree or of the root) is realigned first, under ITS lock.
#
# AUTOMATIC REALIGNMENT (fic_deps_autorefresh, inside the copy's lock; called by test-fast.sh and
# counterproof.sh when fic_deps_ok is false): never an install, never the network, only local copies.
# - source with node_modules -> fic_deps_refresh, the same operation as --setup (rsync from the source, node_modules
#   included, same exclusions, then the fingerprint);
# - worktree without node_modules -> copy of the main tree realigned if stale (from the main tree, which
#   must have node_modules; under that copy's lock), then seeded again, if the dependencies match;
# - lane copy -> copy of the root realigned as above (under its lock), then seeded again from it;
# - no source with node_modules, or worktree dependencies different from those of the main tree -> reason, and the
#   caller exits BLOCKED. During the rsync .fic-deps holds "interrotto": a failed rsync leaves the copy stale.
# Lock order: from the derived copy (lane, worktree) towards the copy of the root and that of the main tree,
# never the other way round: no cycle.
# Declared limit: a hardlink shares the inode; a process that rewrote IN PLACE a file of
# node_modules of the worktree copy would also change the one of the main copy. vitest/eslint do not
# do it (the caches are excluded above); a --setup of the worktree rewrites the files with rsync, which replaces them.
#
# DELETION (fic_mirror_forget <root of a worktree>): the copy of THAT worktree, never the one of the main
# tree; if a run holds it (any of its <dir>/.fic-lock locks), it stays. replay.sh calls it
# at the end of a replay. The locks are looked up in the copy (fic__locks): deletion does not depend on the directory.
#
# SYNC EXCLUSIONS (FIC_MIRROR_EXCL, the only variable of its own that sourcing defines; MESSAGES below): a single list of the core,
# used by test-fast.sh and counterproof.sh for every module — installed dependencies, generated files and runner caches
# (node_modules, .nuxt, .output, coverage, .turbo, .venv, __pycache__, .pytest_cache) and the copy state
# (/.fic-*). A directory that a module lacks changes nothing; counterproof.sh adds the directories of
# the module's `collega_nel_worktree`.
#
# CLEANUP (fic_mirror_pulisci <copy> <relative root> [<runner> [globs of preparati…]]): removes from the copy the
# directories that contain the module's `preparati` (globs relative to the root; an entry without a directory removes its
# files) and, if the counterproof runner is vitest, the vite/vitest caches (core vitest adapter, like
# FIC_VITE_CACHE_DIR). Module without preparati and without a vitest runner: nothing to clean. When: the
# caller decides (counterproof.sh at every sync, test-fast.sh when dependencies or the generated tsconfig change).
#
# LANES (harness-pt13): fic_lane_init <k> (k = 1..9, after fic_mirror_init) moves FIC_MIRROR to the lane's
# copy, <copy of the root>-<k>, with its <dir>/.fic-lock and its vite/vitest caches; FIC_LANE_BASE stays
# the copy of the root. Seeding of the lane copy takes node_modules as hardlinks from THAT copy (valid
# for the current dependencies), not from ~/fic-mirror. fic_lane_forget <root> <k> deletes only the lane copy
# (~/fic-mirror-<k> or ~/fic-mirror-<12 hex>-<k>), never a copy of the root; if a run holds it, it stays.
#
# COPY WITH FALLBACK (pk08, fic_sync [--delete] [--checksum] [--exclude=<p>…] <source>/ <copy>/): `rsync -a` with the
# same arguments if rsync is available; otherwise (Git Bash on Windows without WSL) fic__sync_ripiego, with the same
# observable result, slower:
# - exclusions as in rsync: a name without / at any depth, /x anchored to the transfer root, a/b at the end
#   of the path; in the copy the excluded paths are not deleted (like rsync without --delete-excluded);
# - --delete: what is in the copy but not in the source (outside the exclusions) is deleted; a directory that
#   contains excluded paths (e.g. node_modules) stays, with them, and loses only the rest, like rsync (pk08 review);
# - known differences from rsync, not corrected (no harness pattern hits them): in a pattern with / the `*` of find
#   -path also crosses /, rsync's does not; the trailing / of a pattern (rsync: directories only) is removed and the
#   pattern also applies to files;
# - a file is rewritten (unlink, then tar) if missing, if its type changes, if the x bit or the sha256 fingerprint differ:
#   always the content comparison, like --checksum; directories and symbolic links like rsync -a.
# Exit: 0 · 23 copy failed (like rsync) · 2 option the fallback does not handle. Used by counterproof.sh;
# test-fast.sh and the functions above (seeding, realignment) stay on rsync: the fast copy wants WSL.
#
# LOCK WITHOUT flock (pk08, fic_lock_dir <dir> [<wait in s>, empty = no limit] · fic_unlock_dir <dir>):
# atomic mkdir of <dir>, with inside the pid of the holder. A lock whose pid is no longer alive (KILL, death of the
# shell) is orphaned: whoever waits takes it over, one at a time (<dir>.rec, also a mkdir) and after rereading
# the pid; it is the equivalent of flock, which frees itself when its holder dies. A lock WITHOUT a pid (death between
# the mkdir and the pid write) is also orphaned, if its directory is older than 10 s (mtime): it is taken over the same way
# (pk08 review). An orphaned .rec is not taken over: the wait expires, and the caller reports the path.
# Whoever did the mkdir writes the pid without overwriting (noclobber) and rereads it: if the file was already there or the
# pid read back is not its own (a process stalled over 10 s between mkdir and write, taken over by another meanwhile), the
# lock is not its own and it retries as when waiting (pk08 review round 2). Declared limits: the 10 s threshold compares
# the local clock (`date +%s`) with the mtime written by the file system, which on drvfs (/mnt/<letter>/) or on a network
# directory may have a different clock: a skew of a few seconds advances or delays the takeover of a lock without
# a pid; and a narrow window remains (the stalled process writes the pid exactly between the check of the taker and its
# rm) that only an operating-system lock would close.
# Release is up to the caller (trap EXIT): fic_unlock_dir removes the directory only if the pid is its own.
#
# MESSAGES (1.4.0): the reasons come from the catalog next to this file (lib/maat-msg.sh, lib/messages.tsv): English by
# default, Italian with "lingua": "it" or MAAT_LINGUA=it. Sourcing defines msg only if the caller has not (test-fast.sh
# and counterproof.sh load it themselves); never maat_msg_carica here: a caller that sources this file in WSL (worktree-lib.sh,
# the probes of maat-doctor.sh) pays the catalog only when a message is printed. Frozen: the «interrotto» value of .fic-deps.

_fic_dir=${BASH_SOURCE[0]%/*}; [ "$_fic_dir" = "${BASH_SOURCE[0]}" ] && _fic_dir=.
declare -F msg >/dev/null 2>&1 || . "$_fic_dir/lib/maat-msg.sh" ||
  { echo "fic-mirror: lib/maat-msg.sh not found next to fic-mirror.sh" >&2; unset _fic_dir; return 1; }
unset _fic_dir

FIC_MIRROR_EXCL=(--exclude=node_modules --exclude=.nuxt --exclude=.output --exclude=coverage --exclude=.turbo
  --exclude=.venv --exclude=__pycache__ --exclude=.pytest_cache --exclude='/.fic-*')

fic_mirror_pulisci() { # <copy> <relative root ("" = the copy itself)> [<runner> [globs of preparati…]] → 0 · 1 rm failed
  local dst=$1 base=$1${2:+/$2} run=${3:-} g v IFS=   # pk08: empty IFS, an entry with spaces is not split in the rm
  shift 2; [ $# -gt 0 ] && shift
  for g in "$@"; do
    case "$g" in */*) v=${g%/*} ;; *) v=$g ;; esac
    case "/$v/" in *"/../"*|//*) continue ;; esac   # never outside the root
    [ -n "$v" ] && [ "$v" != . ] || continue
    rm -rf -- "$base"/$v || return 1   # $v unquoted: a directory with * expands in the copy
  done
  if [ "$run" = vitest ]; then
    rm -rf -- "$base/node_modules/.vite" "$dst/node_modules/.vite" "$dst/node_modules/.vitest" || return 1
  fi
}

fic_sync() { # [--delete] [--checksum] [--exclude=<p>…] <source>/ <copy>/ → rsync -a, or the fallback without rsync
  if command -v rsync >/dev/null 2>&1; then rsync -a "$@"; else fic__sync_ripiego "$@"; fi
}

fic__escludi() { # <pattern…> → FIC__FX: the exclusions as a find expression, with rsync semantics
  local p
  FIC__FX=()
  for p in "$@"; do
    p=${p%/}
    [ -n "$p" ] || continue
    case "$p" in
      /*) FIC__FX+=(-o -path "./${p#/}") ;;
      */*) FIC__FX+=(-o -path "./$p" -o -path "*/$p") ;;
      *) FIC__FX+=(-o -name "$p") ;;
    esac
  done
  if [ ${#FIC__FX[@]} -gt 0 ]; then FIC__FX=("${FIC__FX[@]:1}"); else FIC__FX=(-false); fi
}

fic__sync_ripiego() { # the arguments of fic_sync, without rsync: find + sha256sum + tar
  local del=0 src dst p s d i ts td
  local -a ex=() nuovi=() comuni=() cartelle=() hs=() hd=()
  while [ $# -gt 2 ]; do
    case "$1" in
      --delete) del=1 ;;
      --checksum) ;;   # the fallback always compares the content
      --exclude=*) ex+=("${1#--exclude=}") ;;
      *) echo "fic_sync: $(msg fic-mirror.sync_bad_option opt="$1")" >&2; return 2 ;;
    esac
    shift
  done
  [ $# -eq 2 ] || { echo "fic_sync: $(msg fic-mirror.sync_usage)" >&2; return 2; }
  src=${1%/} dst=${2%/}
  [ -d "$src" ] && mkdir -p "$dst" || return 23
  fic__escludi ${ex[@]+"${ex[@]}"}
  if [ "$del" = 1 ]; then   # in the copy, outside the exclusions, what is not in the source
    while IFS= read -r -d '' p; do
      [ -e "$dst/$p" ] || [ -L "$dst/$p" ] || continue   # already removed with the directory that contained it
      [ -e "$src/$p" ] || [ -L "$src/$p" ] && continue
      if [ -d "$dst/$p" ] && [ ! -L "$dst/$p" ] &&   # with excluded entries inside: it stays, this round removes the rest
         [ -n "$(cd "$dst" && find "$p" -mindepth 1 \( "${FIC__FX[@]}" \) -print -quit)" ]; then continue; fi
      rm -rf -- "${dst:?}/$p" || return 23
    done < <(cd "$dst" && find . -mindepth 1 \( "${FIC__FX[@]}" \) -prune -o -print0)
  fi
  while IFS= read -r -d '' p; do   # from the source, directories before their content
    s=$src/$p d=$dst/$p
    if [ -L "$s" ]; then
      [ -L "$d" ] && [ "$(readlink "$s")" = "$(readlink "$d")" ] && continue
      rm -rf -- "$d" || return 23
      nuovi+=("$p")
    elif [ -d "$s" ]; then
      if [ -L "$d" ] || { [ -e "$d" ] && [ ! -d "$d" ]; }; then rm -f -- "$d" || return 23; fi
      [ -d "$d" ] || cartelle+=("$p")
    else
      if [ -L "$d" ] || [ -d "$d" ]; then rm -rf -- "$d" || return 23; fi
      if [ -e "$d" ] && { [ -x "$s" ] && [ -x "$d" ] || { [ ! -x "$s" ] && [ ! -x "$d" ]; }; }; then comuni+=("$p")
      else nuovi+=("$p"); fi
    fi
  done < <(cd "$src" && find . -mindepth 1 \( "${FIC__FX[@]}" \) -prune -o -print0)
  if [ ${#comuni[@]} -gt 0 ]; then   # fingerprints of the common files, in bulk: one line per file, in the same order
    ts=$(mktemp) && td=$(mktemp) || return 23
    if (cd "$src" && printf '%s\0' "${comuni[@]}" | xargs -0 sha256sum) > "$ts" &&
       (cd "$dst" && printf '%s\0' "${comuni[@]}" | xargs -0 sha256sum) > "$td"; then
      mapfile -t hs < "$ts"; mapfile -t hd < "$td"
    fi
    rm -f "$ts" "$td"
    [ ${#hs[@]} -eq ${#comuni[@]} ] && [ ${#hd[@]} -eq ${#comuni[@]} ] || return 23
    for i in "${!comuni[@]}"; do [ "${hs[i]}" = "${hd[i]}" ] || nuovi+=("${comuni[i]}"); done
  fi
  if [ ${#cartelle[@]} -gt 0 ]; then
    (cd "$dst" && printf '%s\0' "${cartelle[@]}" | xargs -0 mkdir -p --) || return 23
  fi
  if [ ${#nuovi[@]} -gt 0 ]; then   # unlink + new write, like rsync (never in place: a hardlink stays intact)
    (cd "$dst" && printf '%s\0' "${nuovi[@]}" | xargs -0 rm -f --) || return 23
    (cd "$src" && printf '%s\0' "${nuovi[@]}" | tar --null --no-recursion -T - -cf -) | (cd "$dst" && tar -xpf -)
    [ "${PIPESTATUS[0]}${PIPESTATUS[1]}" = 00 ] || return 23
  fi
}

fic_lock_dir() { # <lock dir> [<wait in s>, empty = no limit] → 0 taken · 1 past the wait
  local d=$1 wait=${2:-} me=${BASHPID:-$$} t0=$SECONDS p
  while :; do
    until mkdir "$d" 2>/dev/null; do
      p=$(cat "$d/pid" 2>/dev/null)
      if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null && mkdir "$d.rec" 2>/dev/null; then
        p=$(cat "$d/pid" 2>/dev/null)   # reread under .rec: meanwhile another process may have taken it over and acquired it
        if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then rm -rf -- "$d"; fi
        rmdir "$d.rec" 2>/dev/null
        continue
      fi
      if [ -z "$p" ] && fic__lock_vecchio "$d" && mkdir "$d.rec" 2>/dev/null; then   # without pid for over 10 s: orphaned
        [ -z "$(cat "$d/pid" 2>/dev/null)" ] && fic__lock_vecchio "$d" && rm -rf -- "$d"   # reread under .rec
        rmdir "$d.rec" 2>/dev/null
        continue
      fi
      [ -z "$wait" ] || [ $((SECONDS - t0)) -lt "$wait" ] || return 1
      sleep 0.2
    done
    if ! (set -C; echo "$me" > "$d/pid") 2>/dev/null; then   # noclobber: a pid already written belongs to another process
      p=$(cat "$d/pid" 2>/dev/null)
      if [ -d "$d" ] && [ -z "$p" ]; then rm -rf -- "$d"; return 1; fi   # our directory, pid not writable
    fi
    [ "$(cat "$d/pid" 2>/dev/null)" = "$me" ] && return 0   # reread: only our own pid means the lock is taken
    [ -z "$wait" ] || [ $((SECONDS - t0)) -lt "$wait" ] || return 1   # taken over by another: it is not ours, retry
    sleep 0.2
  done
}

fic__lock_vecchio() { # <dir>: 0 if it exists and its mtime is older than 10 s (GNU stat, then BSD); unknown -> 1
  local m
  m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null) || return 1
  case $m in ''|*[!0-9]*) return 1 ;; esac
  [ $(( $(date +%s) - m )) -ge 10 ]
}

fic_unlock_dir() { # <lock dir> [<pid>, default our own]: removes it only if the lock belongs to <pid>
  local d=$1 me=${2:-${BASHPID:-$$}}
  [ "$(cat "$d/pid" 2>/dev/null)" = "$me" ] && rm -rf -- "$d"
}

fic_git_env() { # $1 root: .git FILE with "gitdir: X:/…" → GIT_DIR translated to <FIC_WSL_MNT>/x/… and GIT_WORK_TREE
  local g d
  [ -f "$1/.git" ] || return 0
  g=$(sed -n '1s/^gitdir:[[:space:]]*//p' "$1/.git" | tr -d '\r')
  g=${g//\\//}
  case "$g" in [A-Za-z]:/*) ;; *) return 0 ;; esac
  d=$(printf '%s' "${g:0:1}" | tr '[:upper:]' '[:lower:]')
  GIT_DIR="${FIC_WSL_MNT:-/mnt}/$d/${g:3}"; GIT_WORK_TREE=$1
  export GIT_DIR GIT_WORK_TREE
}

fic_mirror_init() { # $1 root → FIC_TOP, FIC_MAIN (main tree), FIC_MIRROR; 1 if git does not determine them
  local gd gcd g
  FIC_TOP="" FIC_MAIN="" FIC_MIRROR="" FIC_LANE_BASE=""
  fic_git_env "$1"
  g=(git -c safe.directory='*' -C "$1" rev-parse)
  FIC_TOP=$("${g[@]}" --show-toplevel 2>/dev/null) && [ -n "$FIC_TOP" ] || return 1
  gd=$("${g[@]}" --path-format=absolute --git-dir 2>/dev/null) && [ -n "$gd" ] || return 1
  gcd=$("${g[@]}" --path-format=absolute --git-common-dir 2>/dev/null) && [ -n "$gcd" ] || return 1
  FIC_MAIN=$(cd "$gcd/.." 2>/dev/null && pwd) || return 1
  if [ "$gd" = "$gcd" ]; then FIC_MIRROR=$HOME/fic-mirror
  else FIC_MIRROR=$HOME/fic-mirror-$(printf '%s' "$FIC_TOP" | sha256sum | cut -c1-12); fi
}

fic__pkg() { # <copy> → <dir> (stdout), if <copy> = $FIC_MIRROR/<dir>; otherwise reason and 1
  case "$1" in
    "$FIC_MIRROR"/?*) printf '%s\n' "${1#"$FIC_MIRROR"/}" ;;
    *) echo "$(msg fic-mirror.outside_copy mirror="${FIC_MIRROR:-$(msg fic-mirror.copy_uninit)}" path="$1")"; return 1 ;;
  esac
}

fic__locks() { # <copy of the root> → its .fic-lock files (one per packages directory), node_modules excluded
  find "$1" -name node_modules -prune -o -name .fic-lock -type f -print 2>/dev/null
}

fic_deps_fp() { # <source: packages directory> [raw] → fingerprint; `raw` = the bytes (the old rule)
  local raw=${2:-} f h
  (cd "$1" && find . \( -name node_modules -o -name .nuxt -o -name .output \) -prune -o \
      \( -name package.json -o -name package-lock.json \) -type f -print | LC_ALL=C sort |
    while IFS= read -r f; do
      if [ "$raw" = raw ]; then h=$(sha256sum < "$f" | cut -c1-64); else h=$(tr -d '\r' < "$f" | sha256sum | cut -c1-64); fi
      printf '%s  %s\n' "$h" "$f"
    done) | sha256sum | cut -c1-64
}

fic_deps_ok() { # <source> <copy>: the dependencies are those recorded by --setup
  local rec; rec=$(cat "$2/.fic-deps" 2>/dev/null) && [ -n "$rec" ] || return 1
  [ "$(fic_deps_fp "$1")" = "$rec" ] || [ "$(fic_deps_fp "$1" raw)" = "$rec" ]
}

fic_deps_refresh() { # <source with node_modules> <copy> → 0 done · 1 no, reason on stdout
  # The --setup operation: rsync from the source, node_modules included, then the fingerprint. The lock belongs to the caller.
  # During the rsync .fic-deps holds "interrotto": a failed rsync leaves the copy stale (the next run retries),
  # never with the old fingerprint on half-copied node_modules.
  local src=$1 dst=$2 rc
  [ -d "$src/node_modules" ] || { echo "$(msg fic-mirror.no_node_modules src="$src")"; return 1; }
  mkdir -p "$dst" && echo interrotto > "$dst/.fic-deps" || { echo "$(msg fic-mirror.copy_unwritable dst="$dst")"; return 1; }
  rsync -a --delete --exclude=.nuxt --exclude=.output --exclude=coverage --exclude=.turbo --exclude='/.fic-*' "$src/" "$dst/"
  rc=$?; [ "$rc" -eq 0 ] || { echo "$(msg fic-mirror.rsync_failed rc="$rc")"; return 1; }
  fic_deps_fp "$src" > "$dst/.fic-deps" || { echo "$(msg fic-mirror.fp_unwritable dst="$dst")"; return 1; }
}

fic__seed_copy() { # <seed source> <source> <copy>: node_modules as hardlinks, then the fingerprint
  # No lock (the caller holds it). On an already seeded copy: .fic-deps "interrotto" during seeding, and the
  # node_modules directories of the copy that are no longer in the seed source (package removed) are deleted: they are
  # hardlinks, the seed source is not touched.
  local mm=$1 src=$2 dst=$3 nms
  if [ -f "$dst/.fic-deps" ]; then echo interrotto > "$dst/.fic-deps" || { echo "$(msg fic-mirror.fp_unwritable dst="$dst")"; return 1; }; fi
  nms=$(cd "$mm" && find . -name node_modules -type d -prune -print | sed 's|^\./||') || { echo "$(msg fic-mirror.seed_unreadable mm="$mm")"; return 1; }
  printf '%s\n' "$nms" | while IFS= read -r nm; do
    [ -n "$nm" ] || continue
    mkdir -p "$dst/$nm" &&
      rsync -a --delete --link-dest="$mm/$nm/" --exclude=.cache --exclude=.vite --exclude=.vitest "$mm/$nm/" "$dst/$nm/" || exit 1
  done || { echo "$(msg fic-mirror.seed_failed)"; return 1; }
  (cd "$dst" && find . -name node_modules -type d -prune -print | sed 's|^\./||') | while IFS= read -r nm; do
    printf '%s\n' "$nms" | grep -qxF -- "$nm" || rm -rf "${dst:?}/$nm" || exit 1
  done || { echo "$(msg fic-mirror.orphans)"; return 1; }
  fic_deps_fp "$src" > "$dst/.fic-deps" || { echo "$(msg fic-mirror.fp_unwritable dst="$dst")"; return 1; }
}

fic__source_fresh() { # <origin of the seed source> <seed source> <name> <dir>: the seed source is valid for its origin
  # If it is stale it realigns it, under ITS lock (fd 8), like the copy of a root (fic__refresh_root).
  # 0 valid · 1 no, reason on stdout. One line on stderr when it realigns.
  local o=$1 mm=$2 nome=$3 pkg=$4 out
  [ -d "$mm/node_modules" ] && [ -f "$mm/.fic-deps" ] || { echo "$(msg fic-mirror.missing nome="$nome" mm="$mm")"; return 1; }
  fic_deps_ok "$o" "$mm" && return 0
  out=$(
    exec 8>"$mm/.fic-lock" || { echo "$(msg fic-mirror.lock_unopenable nome="$nome")"; exit 1; }
    flock -w "${FIC_LOCK_WAIT:-900}" 8 || { echo "$(msg fic-mirror.busy nome="$nome" wait="${FIC_LOCK_WAIT:-900}")"; exit 1; }
    fic_deps_ok "$o" "$mm" && exit 0   # realigned meanwhile by another run
    fic__refresh_root "$o" "$mm" "$pkg" || exit 1
    fic_deps_ok "$o" "$mm" || { echo "$(msg fic-mirror.still_stale nome="$nome")"; exit 1; }
  ) || { echo "$(msg fic-mirror.stale_failed nome="$nome" out="${out//$'\n'/; }")"; return 1; }
  [ -z "$out" ] || echo "fic-mirror: $(msg fic-mirror.stale_realigned nome="$nome" mm="$mm" out="${out//$'\n'/; }")" >&2
}

fic__refresh_root() { # <source> <copy of the root> <dir>, lock of the copy already taken
  # Source with node_modules: fic_deps_refresh. Without (worktree): seed again from the copy of the main tree,
  # realigned first if stale. Stdout: what it did, or the reason (exit 1).
  local src=$1 dst=$2 pkg=$3 mm main
  mm=$HOME/fic-mirror/$pkg
  if [ -d "$src/node_modules" ]; then fic_deps_refresh "$src" "$dst" && echo "$(msg fic-mirror.realigned)"; return; fi
  [ "$dst" != "$mm" ] || { echo "$(msg fic-mirror.no_nm_main src="$src")"; return 1; }
  main=$FIC_MAIN/$pkg
  [ -d "$mm/node_modules" ] && [ -f "$mm/.fic-deps" ] || { echo "$(msg fic-mirror.no_nm_no_main mm="$mm")"; return 1; }
  [ -d "$main" ] && [ "$(fic_deps_fp "$src")" = "$(fic_deps_fp "$main")" ] ||
    { echo "$(msg fic-mirror.no_nm_deps_differ)"; return 1; }
  fic__source_fresh "$main" "$mm" "$(msg fic-mirror.name_main)" "$pkg" || return 1
  fic__seed_copy "$mm" "$src" "$dst" && echo "$(msg fic-mirror.reseeded)"
}

fic_deps_autorefresh() { # <source> <copy = $FIC_MIRROR/<dir>>: realigns a copy with stale dependencies
  # The caller holds the copy's lock and rechecks fic_deps_ok afterwards. Never an install: only local copies.
  # Lane copy: the copy of the root realigned (under its lock), then seeded again from it.
  # 0 done, one line on stdout · 1 no, reason on stdout.
  local src=$1 dst=$2 old new out pkg
  pkg=$(fic__pkg "$dst") || { echo "$pkg"; return 1; }
  old=$(cut -c1-12 "$dst/.fic-deps" 2>/dev/null); new=$(fic_deps_fp "$src" | cut -c1-12)
  if [ -n "${FIC_LANE_BASE:-}" ]; then
    out=$(fic__source_fresh "$src" "$FIC_LANE_BASE/$pkg" "$(msg fic-mirror.name_root)" "$pkg") &&
      out=$(fic__seed_copy "$FIC_LANE_BASE/$pkg" "$src" "$dst") &&
      out="$(msg fic-mirror.lane_reseeded base="$FIC_LANE_BASE")"
  else
    out=$(fic__refresh_root "$src" "$dst" "$pkg")
  fi || { echo "${out//$'\n'/; }"; return 1; }
  echo "$(msg fic-mirror.deps_changed old="${old:-$(msg fic-mirror.fp_absent)}" new="$new" out="$out")"
}

fic_seed_node_modules() { # <source> <copy = $FIC_MIRROR/<dir>> → 0 seeded · 1 no, reason on stdout
  # Requires fic_mirror_init already called on the root of the source. A stale seed source is realigned (fic__source_fresh).
  local src=$1 dst=$2 mm pkg
  [ -n "$FIC_MIRROR" ] && [ "$FIC_MIRROR" != "$HOME/fic-mirror" ] || { echo "$(msg fic-mirror.not_worktree)"; return 1; }
  pkg=$(fic__pkg "$dst") || { echo "$pkg"; return 1; }
  mm=$HOME/fic-mirror/$pkg
  if [ -n "${FIC_LANE_BASE:-}" ]; then   # lane copy: from the copy of ITS root (fic_lane_init)
    mm=$FIC_LANE_BASE/$pkg
    [ -d "$mm/node_modules" ] && [ -f "$mm/.fic-deps" ] || { echo "$(msg fic-mirror.no_root_copy mm="$mm")"; return 1; }
    fic__source_fresh "$src" "$mm" "$(msg fic-mirror.name_root)" "$pkg" || return 1
  else
  [ -d "$mm/node_modules" ] && [ -f "$mm/.fic-deps" ] || { echo "$(msg fic-mirror.no_main_copy mm="$mm")"; return 1; }
  [ -d "$FIC_MAIN/$pkg" ] && [ "$(fic_deps_fp "$src")" = "$(fic_deps_fp "$FIC_MAIN/$pkg")" ] ||
    { echo "$(msg fic-mirror.deps_differ)"; return 1; }
  fic__source_fresh "$FIC_MAIN/$pkg" "$mm" "$(msg fic-mirror.name_main)" "$pkg" || return 1
  fi
  mkdir -p "$dst" || { echo "$(msg fic-mirror.copy_mkdir dst="$dst")"; return 1; }
  (
    flock -w "${FIC_LOCK_WAIT:-900}" 9 || { echo "$(msg fic-mirror.wt_busy)"; exit 1; }
    [ -d "$dst/node_modules" ] && [ -f "$dst/.fic-deps" ] && exit 0   # seeded meanwhile by another run
    fic__seed_copy "$mm" "$src" "$dst" || exit 1
  ) 9>"$dst/.fic-lock"
}

fic_mirror_forget() { # <root of a worktree>: deletes ITS copy · 0 done or nothing to do · 1 refused or in use
  local lk
  fic_mirror_init "$1" || { echo "fic-mirror: $(msg fic-mirror.no_root root="$1")"; return 1; }
  case "$FIC_MIRROR" in "$HOME"/fic-mirror-????????????) ;; *) echo "fic-mirror: $(msg fic-mirror.refuse_wt mirror="$FIC_MIRROR")"; return 1 ;; esac
  [ -d "$FIC_MIRROR" ] || { echo "fic-mirror: $(msg fic-mirror.no_copy root="$1")"; return 0; }
  fic__forget_dir "$FIC_MIRROR" || return 1
  echo "fic-mirror: $(msg fic-mirror.deleted mirror="$FIC_MIRROR")"
}

fic__forget_dir() { # <copy of the root>: deleted if none of its locks is held · 1 in use, left
  # All locks taken (flock -n) before deleting and held until the end, in the same subshell.
  ( local lk fd
    while IFS= read -r lk; do
      [ -n "$lk" ] || continue
      exec {fd}>"$lk" && flock -n "$fd" || { echo "fic-mirror: $(msg fic-mirror.in_use dir="$1")"; exit 1; }
    done < <(fic__locks "$1")
    rm -rf "$1" )
}

fic_lane_init() { # <k>: after fic_mirror_init, FIC_MIRROR = copy of lane k · 1 if k is not 1..9 or the root is missing
  case "${1:-}" in [1-9]) ;; *) return 1 ;; esac
  [ -n "$FIC_MIRROR" ] || return 1
  FIC_LANE_BASE=$FIC_MIRROR FIC_MIRROR=$FIC_MIRROR-$1
}

fic_lane_forget() { # <root> <k>: deletes the copy of lane k · 0 done or nothing to do · 1 refused or in use
  fic_mirror_init "$1" && fic_lane_init "${2:-}" || { echo "fic-mirror: $(msg fic-mirror.no_lane root="$1" lane="${2:-}")"; return 1; }
  case "$FIC_MIRROR" in "$HOME"/fic-mirror-[1-9]|"$HOME"/fic-mirror-????????????-[1-9]) ;;
    *) echo "fic-mirror: $(msg fic-mirror.refuse_lane mirror="$FIC_MIRROR")"; return 1 ;; esac
  [ -d "$FIC_MIRROR" ] || { echo "fic-mirror: $(msg fic-mirror.no_lane_copy lane="$2" root="$1")"; return 0; }
  fic__forget_dir "$FIC_MIRROR" || return 1
  echo "fic-mirror: $(msg fic-mirror.lane_deleted mirror="$FIC_MIRROR")"
}
