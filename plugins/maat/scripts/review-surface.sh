#!/usr/bin/env bash
# review-surface.sh — DETERMINISTIC review surface for /implementation-review-cycle.
#
# Why it exists: `git diff` alone is NOT the implementation. It leaves out staged changes, untracked
# (new) files, and after a commit it is empty. And an approval not bound to a snapshot stays
# "valid" even if the code changes afterwards. This script answers three questions without an LLM:
#   1. what has really changed relative to the base?            → snapshot
#   2. is what was approved still what is there?                → check
#   3. have the changed tests been weakened?                    → test-signals
#
# Read-only on the working tree and on the real index. It only writes unreferenced git objects
# (blobs/trees) through a TEMPORARY index: no visible effect, `git gc` will prune them after ~2
# weeks (that is why `check` has a fallback on the fingerprint).
#
# Subcommands:
#   snapshot [--base <ref>]
#       Base:  <sha>   (default HEAD; with --base <ref> → merge-base <ref> HEAD)
#       Tree:  <sha>   tree of the COMPLETE working tree (tracked + staged + non-ignored untracked)
#       Changes:       name-status base..tree (A/M/D/R/T), renames included
#       Origin:        git status --porcelain (which are staged, which unstaged, which untracked)
#   fingerprint --tree <tree> --paths-file <f>
#       sha256 (12 chars) of the content of the listed paths in the tree: path + blob, or ABSENT.
#   check --base <sha> --tree <old-tree> --paths-file <f> [--fingerprint <fp>] [--exclude-file <f>]
#       --paths-file = approved SCOPE; --exclude-file = paths excluded from the scope (another flow).
#       Recomputes the snapshot on the RECORDED base (never HEAD: a commit after the approval is not
#       a change) and reports FRESH | STALE | UNKNOWN, the delta, and whether the delta is "tests only,
#       without test infrastructure and without weakening signals; in already existing tests only
#       pure additions, with no shared setup and no control flow" (Gate-only eligible: yes, or
#       no — <reason>).
#       An excluded file that changes does NOT make it stale, but is reported as EXCLUDED-CHANGED:
#       the orchestrator must look at it (a mixed file can carry feature code).
#   test-signals --from <tree-ish> --to <tree-ish> [--paths-file <f>]
#       Weakened-test signals between two tree-ishes, optionally limited to the paths in the file.
#   tree
#       Only the sha of the complete working tree's tree (like snapshot's "Tree"). run-phase.sh uses it
#       before and after the implement/fix phases to know which paths the phase changed (touched.txt).
#   diff --from <tree-ish> --to <tree-ish> --paths-file <f> --out <file>
#       Writes to <file> the diff of the listed paths (untracked new files included, because --to is a
#       tree) and prints the index "<path><TAB>offset=N limit=M" to read it in chunks with Read. It is how
#       the implementation-reviewer sees the surface without having Bash. A rename shows up as such
#       only if both paths are in the list; otherwise as A + D.
#
# Paths are printed WITHOUT git quoting (core.quotePath=false): a non-ASCII name in octal
# quotes would no longer match itself across manifest, pathspecs and comparisons.
#
# Exit: 0 ok · 2 wrong usage · 3 check UNKNOWN (tree pruned and no fingerprint for the fallback).

set -uo pipefail
set -f
# Messages (1.4.0): the catalog next to this script, loaded by the first message (msg does it), not here: `tree` runs
# before and after every phase and gate, and a message is printed only for an error or a verdict. The prefixes of the
# lines read by the review skill («Status: …», «Gate-only eligible: no — ») stay in the code.
case ${BASH_SOURCE[0]} in */*) . "${BASH_SOURCE[0]%/*}/lib/maat-msg.sh" ;; *) . lib/maat-msg.sh ;; esac

die() { echo "review-surface: $*" >&2; exit 2; }
g() { git -c core.quotePath=false "$@"; }

g rev-parse --git-dir >/dev/null 2>&1 || die "$(msg review-surface.not_git)"
TOP=$(g rev-parse --show-toplevel)
cd "$TOP" || die "$(msg review-surface.cd_failed top="$TOP")"

# Test files: the perimeter of "test-signals" and of the gate-only path. `script/` excluded on
# purpose: script/e2e/ is stack infrastructure, not a test.
TEST_RE='(^|/)(tests?|__tests__|e2e)/|\.(test|spec)\.[cm]?[jt]sx?$|(^|/)test_[^/]*\.py$|_test\.py$|(^|/)conftest\.py$|__snapshots__/|\.snap$'
NOT_TEST_RE='^script/'
# Test infrastructure: changing it can make everything pass without touching a single assertion.
# Allowed in the diff, never on the gate-only path (it always requires a review round).
TEST_INFRA_RE='(^|/)conftest\.py$|(^|/)(fixtures?|mocks?|__mocks__|fakes?|helpers?|support|utils?)/|(^|/)(setup|global-setup|vitest\.setup)[^/]*\.[cm]?[jt]s$|\.(fixture|mock|fake)s?\.[cm]?[jt]sx?$'
# The gate-only path admits ONLY actual test files. Everything else under tests/,
# __tests__/, e2e/ (a fake, a helper, a factory: tests/goals_fakes.py) is infrastructure.
TEST_FILE_RE='\.(test|spec)\.[cm]?[jt]sx?$|(^|/)test_[^/]*\.py$|_test\.py$'
# Assertions: `expect(` and the matchers even when prettier wraps them with no `expect(` on the
# line (`).toStrictEqual(`), `expect.soft(`, unittest (`self.assertEqual(`), mock (`.assert_called_with(`).
ASSERT_RE='expect\(|expect\.[A-Za-z_]+\(|\bassert\b|pytest\.raises|\.to(Be|Equal|StrictEqual|Have|Contain|Match|Throw|Satisfy)[A-Za-z_]*\(|\.(resolves|rejects)\b|\.assert(_[A-Za-z_]+|[A-Z][A-Za-z_]*)\('
SKIP_RE='\b(it|test|describe)\.(skip|only|todo|fixme|skipIf|runIf)\b|\bx(it|describe|test)\(|pytest\.mark\.(skip|skipif|xfail)|pytest\.skip\(|@unittest\.skip|test\.fail\('
SNAP_RE='__snapshots__/|\.snap$|(^|/)(golden|snapshots?)/'
# Gate-only path, test files ALREADY existing in the approved tree: pure additions only. A line
# removed or changed (the expected value on a continuation line, an input, the role used) changes the
# strength of a test a reviewer has already seen; and some additions change existing tests without
# a single `-` line: shared setup (vi.mock is hoisted over the whole file, a beforeEach, an autouse)
# and control flow (a `return` at the top, an `if`/`try` around existing assertions).
# It does not apply to NEW files: they have no pre-existing tests to alter.
SHARED_SETUP_RE='\b(vi|jest)\.(mock|doMock|stubGlobal|stubEnv)\(|\b(before|after)(Each|All)\(|autouse[[:space:]]*=[[:space:]]*True'
CONTROL_RE='^\+[[:space:]]*(return[[:space:]]*;?[[:space:]]*$|if\b|for\b|while\b|with\b|try\b|except\b|catch\b|continue\b|break\b|else\b|pass[[:space:]]*$)'

is_test() { printf '%s\n' "$1" | grep -Ev "$NOT_TEST_RE" | grep -Eq "$TEST_RE"; }

# Tree of the complete working tree. The temporary index is SEEDED with a copy of the real one:
# with core.autocrlf=true an empty index would re-hash every file and produce hundreds of
# spurious changes (measured: 392 on this repo, plus the loss of the executable bit).
# `cp -p` keeps the index mtime: with a new mtime git would lose detection of "racy" files
# (modified in the same second as the last add) and would miss a real change.
snapshot_tree() {
  local tmp idx tree
  idx=$(g rev-parse --git-path index)
  tmp=$(mktemp) || die "$(msg review-surface.mktemp_failed)"
  if [ -f "$idx" ]; then cp -p "$idx" "$tmp"; else rm -f "$tmp"; fi
  GIT_INDEX_FILE="$tmp" g add -A >/dev/null 2>&1 || { rm -f "$tmp"; die "$(msg review-surface.add_failed)"; }
  tree=$(GIT_INDEX_FILE="$tmp" g write-tree) || { rm -f "$tmp"; die "$(msg review-surface.write_tree_failed)"; }
  rm -f "$tmp"
  echo "$tree"
}

resolve_base() {
  local ref=${1:-}
  if [ -z "$ref" ]; then g rev-parse HEAD; return; fi
  g rev-parse --verify -q "$ref^{commit}" >/dev/null || die "$(msg review-surface.base_unresolvable ref="$ref")"
  g merge-base "$ref" HEAD 2>/dev/null || g rev-parse "$ref^{commit}"
}

read_paths() { # prints the paths in the file, without blank lines, sorted and unique
  [ -f "$1" ] || die "$(msg review-surface.paths_missing f="$1")"
  # a line may carry a note after « — » (Excluded: «<path> — stessa catena, anello precedente (…)»): the path is what counts
  tr -d '\r' < "$1" | sed 's/ — .*//' | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u
}

pathspecs() { # $1 paths-file → global array SPECS of literal pathspecs
  SPECS=()
  [ -n "${1:-}" ] || return 0
  mapfile -t SPECS < <(read_paths "$1" | sed 's/^/:(literal)/')
}

fingerprint_of() { # $1 tree, $2 paths-file
  local tree=$1 pf=$2 p line
  {
    while IFS= read -r p; do
      line=$(g ls-tree "$tree" -- ":(literal)$p" 2>/dev/null)
      if [ -n "$line" ]; then printf '%s\n' "$line"; else printf 'ABSENT\t%s\n' "$p"; fi
    done < <(read_paths "$pf")
  } | sha256sum | cut -c1-12
}

signals() { # $1 from, $2 to, [$3 paths-file]
  local from=$1 to=$2 pf=${3:-} out="" f st old keep
  keep=""
  [ -n "$pf" ] && keep=$(read_paths "$pf")
  # Renames: the OLD content is compared with the NEW one (`from:old` vs `to:new`). With only the
  # new path, a test renamed and emptied in the same step would give no signal; with
  # --no-renames a pure rename would give a false DELETED-TEST.
  while IFS=$'\t' read -r st old f; do
    [ -z "${f:-}" ] && f=$old
    if [ -n "$pf" ]; then
      printf '%s\n' "$keep" | grep -qxF -- "$f" || printf '%s\n' "$keep" | grep -qxF -- "$old" || continue
    fi
    is_test "$f" || is_test "$old" || continue
    case "$st" in D*) out+="DELETED-TEST ${f}"$'\n'; continue ;; esac
    if printf '%s\n' "$f" | grep -Eq "$SNAP_RE"; then out+="SNAPSHOT-CHANGED ${f}"$'\n'; fi
    local diff rem add skips
    case "$st" in
      R*) diff=$(g diff --no-color --no-ext-diff -U0 "$from:$old" "$to:$f" | grep -E '^[-+]' | grep -Ev '^(\+\+\+|---) ') ;;
      *)  diff=$(g diff --no-color --no-ext-diff -U0 "$from" "$to" -- ":(literal)$f" | grep -E '^[-+]' | grep -Ev '^(\+\+\+|---) ') ;;
    esac
    rem=$(printf '%s\n' "$diff" | grep -E '^-' | grep -cE "$ASSERT_RE")
    add=$(printf '%s\n' "$diff" | grep -E '^\+' | grep -cE "$ASSERT_RE")
    [ "${rem:-0}" -gt 0 ] && out+="REMOVED-ASSERTIONS ${f}: -${rem} +${add:-0}"$'\n'
    skips=$(printf '%s\n' "$diff" | grep -E '^\+' | grep -E "$SKIP_RE" | head -3 | sed 's/^+[[:space:]]*/    /')
    [ -n "$skips" ] && out+="ADDED-SKIP ${f}"$'\n'"${skips}"$'\n'
  done < <(g diff --no-color --name-status -M "$from" "$to")
  if [ -z "$out" ]; then echo "Test signals: none"; else printf 'Test signals:\n%s' "$out"; fi
}

cmd=${1:-}; shift || true
BASE="" TREE="" FROM="" TO="" PF="" FP="" XF="" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE=${2:-}; shift 2 ;;
    --tree) TREE=${2:-}; shift 2 ;;
    --from) FROM=${2:-}; shift 2 ;;
    --to) TO=${2:-}; shift 2 ;;
    --paths-file) PF=${2:-}; shift 2 ;;
    --fingerprint) FP=${2:-}; shift 2 ;;
    --exclude-file) XF=${2:-}; shift 2 ;;
    --out) OUT=${2:-}; shift 2 ;;
    *) die "$(msg review-surface.unknown_arg arg="$1")" ;;
  esac
done

case "$cmd" in
  snapshot)
    base=$(resolve_base "$BASE") || exit 2
    tree=$(snapshot_tree) || exit 2
    echo "Base: $base"
    echo "Tree: $tree"
    echo "Changes (base..tree):"
    changes=$(g diff --no-color --name-status -M "$base" "$tree")
    if [ -z "$changes" ]; then echo "  (none)"; else printf '%s\n' "$changes" | sed 's/^/  /'; fi
    echo "Origin (git status --porcelain):"
    st=$(g status --porcelain=v1 -uall)
    if [ -z "$st" ]; then echo "  (clean)"; else printf '%s\n' "$st" | sed 's/^/  /'; fi
    ;;
  fingerprint)
    [ -n "$TREE" ] && [ -n "$PF" ] || die "$(msg review-surface.usage_fp)"
    g cat-file -e "$TREE^{tree}" 2>/dev/null || die "$(msg review-surface.tree_absent tree="$TREE")"
    echo "Fingerprint: $(fingerprint_of "$TREE" "$PF")"
    ;;
  check)
    [ -n "$BASE" ] && [ -n "$TREE" ] && [ -n "$PF" ] || die "$(msg review-surface.usage_check)"
    g rev-parse --verify -q "$BASE^{commit}" >/dev/null || die "$(msg review-surface.base_absent base="$BASE")"
    new=$(snapshot_tree) || exit 2
    echo "Current tree: $new"
    # New paths relative to the RECORDED base that were not in the approved manifest.
    known=$( { read_paths "$PF"; [ -n "$XF" ] && read_paths "$XF"; } | LC_ALL=C sort -u)
    added=$(comm -13 <(printf '%s\n' "$known") <(g diff --name-only --no-renames "$BASE" "$new" | LC_ALL=C sort -u) | grep -v '^$')
    if g cat-file -e "$TREE^{tree}" 2>/dev/null; then
      pathspecs "$PF"
      delta=""
      [ ${#SPECS[@]} -gt 0 ] && delta=$(g diff --no-color --name-status --no-renames "$TREE" "$new" -- "${SPECS[@]}")
      excl=""
      if [ -n "$XF" ]; then
        pathspecs "$XF"
        [ ${#SPECS[@]} -gt 0 ] && excl=$(g diff --no-color --name-only --no-renames "$TREE" "$new" -- "${SPECS[@]}")
      fi
      if [ -z "$delta" ] && [ -z "$added" ]; then
        echo "Status: FRESH"
        [ -n "$excl" ] && printf '%s\n' "$excl" | sed 's/^/  EXCLUDED-CHANGED\t/'
        exit 0
      fi
      echo "Status: STALE"
      echo "Delta (approved tree → current, manifest paths):"
      [ -n "$delta" ] && printf '%s\n' "$delta" | sed 's/^/  /'
      [ -n "$added" ] && printf '%s\n' "$added" | sed 's/^/  NEW-SURFACE\t/'
      [ -n "$excl" ] && printf '%s\n' "$excl" | sed 's/^/  EXCLUDED-CHANGED\t/'
      # Gate-only path: ALL paths of the delta are tests (not test infrastructure), and the
      # tests of the delta show no weakening signals.
      all=$( { printf '%s\n' "$delta" | cut -f2-; printf '%s\n' "$added"; } | grep -v '^$')
      dfile=$(mktemp) || die "$(msg review-surface.mktemp_failed)"
      printf '%s\n' "$all" > "$dfile"
      sig=$(signals "$TREE" "$new" "$dfile")
      rm -f "$dfile"
      printf '%s\n' "$sig"
      # The A/M status of each path is decided against the APPROVED tree, not from `$delta`: NEW-SURFACE
      # paths (outside the manifest) have no status, and a pre-existing test outside the manifest that gets
      # a vi.mock added is a MODIFIED file. Without `-w`: in Python indentation is semantic.
      eligible=yes why=""
      while IFS= read -r p; do
        [ -z "$p" ] && continue
        if ! is_test "$p" || ! printf '%s\n' "$p" | grep -Eq "$TEST_FILE_RE"; then eligible=no; why="$(msg review-surface.not_test p="$p")"; break; fi
        if printf '%s\n' "$p" | grep -Eq "$TEST_INFRA_RE"; then eligible=no; why="$(msg review-surface.test_infra p="$p")"; break; fi
        g cat-file -e "$TREE:$p" 2>/dev/null || continue   # new file: no pre-existing test
        d=$(g diff --no-color --no-ext-diff -U0 --ignore-blank-lines --ignore-space-at-eol "$TREE" "$new" -- ":(literal)$p" | grep -Ev '^(\+\+\+|---) ')
        if printf '%s\n' "$d" | grep -Eq '^-.*[^[:space:]]'; then eligible=no; why="$(msg review-surface.lines_removed p="$p")"; break; fi
        if printf '%s\n' "$d" | grep -E '^\+' | grep -Eq "$SHARED_SETUP_RE"; then eligible=no; why="$(msg review-surface.shared_setup p="$p")"; break; fi
        if printf '%s\n' "$d" | grep -Eq "$CONTROL_RE"; then eligible=no; why="$(msg review-surface.control_flow p="$p")"; break; fi
      done <<< "$all"
      if [ "$sig" != "Test signals: none" ]; then eligible=no; why="$(msg review-surface.weakening)"; fi
      if [ "$eligible" = yes ]; then echo "Gate-only eligible: yes"; else echo "Gate-only eligible: no — $why"; fi
    else
      [ -n "$FP" ] || { echo "Status: UNKNOWN ($(msg review-surface.unknown_pruned tree="$TREE"))"; exit 3; }
      cur=$(fingerprint_of "$new" "$PF")
      if [ "$cur" = "$FP" ] && [ -z "$added" ]; then echo "Status: FRESH (via fingerprint)"; exit 0; fi
      echo "Status: STALE (via fingerprint; $(msg review-surface.stale_fp))"
      [ -n "$added" ] && printf '%s\n' "$added" | sed 's/^/  NEW-SURFACE\t/'
      echo "Gate-only eligible: no — $(msg review-surface.no_delta)"
    fi
    ;;
  test-signals)
    [ -n "$FROM" ] && [ -n "$TO" ] || die "$(msg review-surface.usage_signals)"
    signals "$FROM" "$TO" "$PF"
    ;;
  tree)
    snapshot_tree
    ;;
  diff)
    [ -n "$FROM" ] && [ -n "$TO" ] && [ -n "$PF" ] && [ -n "$OUT" ] || die "$(msg review-surface.usage_diff)"
    pathspecs "$PF"
    [ ${#SPECS[@]} -gt 0 ] || die "$(msg review-surface.no_paths)"
    g diff --no-color --no-ext-diff -M "$FROM" "$TO" -- "${SPECS[@]}" > "$OUT" || die "$(msg review-surface.diff_failed)"
    [ -s "$OUT" ] || { echo "($(msg review-surface.no_diff))"; exit 0; }
    # "diff --git a/P b/P": P = half of what follows "a/", minus " b/"; renames state it explicitly.
    awk '
      function emit(e) { if (s) printf "%s\toffset=%d limit=%d\n", name, s, e - s + 1 }
      /^diff --git a\// { emit(NR - 1); s = NR; r = substr($0, 12); name = substr(r, 3, (length(r) - 5) / 2); old = ""; next }
      s && /^rename from / { old = substr($0, 13); next }
      s && /^rename to / { name = old " → " substr($0, 11); next }
      END { emit(NR) }' "$OUT"
    ;;
  *) die "$(msg review-surface.subcommand)" ;;
esac
