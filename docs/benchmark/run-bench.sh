#!/bin/bash
# run-bench.sh — the procedure of the Maat benchmark, as a script. Written before the first run; see README.md.
#
#   bash run-bench.sh check                      versions and tools; prints the «environment» block of the records
#   bash run-bench.sh schedule <seed>            writes schedule.tsv: the 30 runs in random order (seed: see README)
#   bash run-bench.sh prepare <run-id>           builds the clean copy of one run; no Claude session (on the Maat side
#                                                it only runs `claude plugin marketplace add` and `plugin install`)
#   bash run-bench.sh run <run-id>               launches the run's side on its copy, then collects the record
#   bash run-bench.sh hidden <run-id>            the hidden acceptance tests on the run's final tree (after `run`)
#   bash run-bench.sh group <first> <last> [N]   one group of the schedule, orders <first>..<last> (at most 6 runs):
#                                                prepare each in order, then run + hidden, N at a time (default 1)
#
# Environment (all required, fixed for the whole benchmark and written in each record):
#   BENCH_HOME        work folder (copies, mirrors, records), outside any repository
#   CLAUDE_BIN        the Claude Code binary, same for both sides (Maat's phases use it too)
#   CLAUDE_CONFIG_DIR a configuration folder used only for the benchmark: logged in, no CLAUDE.md, no plugins,
#                     no MCP servers, no hooks (the Maat plugin is installed in it, at project scope, by `prepare`)
#   ANTHROPIC_MODEL   the model id, same for both sides
#   MAAT_TAG          the Maat release under test (v1.6.0)
#   HIDDEN_DIR        the folder of the hidden acceptance tests (private until the end: never inside BENCH_HOME/records)
#   GO, NODE_VERSION  optional: go binary (default go); node must be in PATH (Node 20 recommended)
#
# Safety: both sides run with --permission-mode bypassPermissions (Maat's phases always do). Run the benchmark on a
# disposable machine or user account, never where a mistake cannot be undone. Copies have no git remote.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_HOME:?set BENCH_HOME}"
mkdir -p "$BENCH_HOME"/{mirrors,copies,records,nm,hidden}
export DISABLE_AUTOUPDATER=1               # one Claude Code binary for the whole benchmark
MAX_GROUP=6                                # runs per group; the quota is checked before each group (README)
TIME_CAP_S=${TIME_CAP_S:-14400}            # 4 h, the same cap for both sides (pre-registered)
BASE_DATE='2026-01-01T00:00:00 +0000'      # fixed date of the snapshot commit: same commit id for every copy

die() { echo "run-bench: $*" >&2; exit 2; }

# ---- tasks: id | repository | starting commit | spec file -----------------------------------------------------
task_row() {
  case "$1" in
    T1) echo "https://github.com/python-humanize/humanize.git d16e6352c9785c5ab86de0133222bd22e89b0db2 T1-humanize-parse-size/spec-parse-naturalsize.md" ;;
    T2) echo "https://github.com/dustin/go-humanize.git a1b4e66b9a6d890e9e15e7091cf16c8032367d6e T2-go-humanize-bytes-rounding/spec-bytes-rounding-unit.md" ;;
    T3) echo "https://github.com/minimistjs/minimist.git ecfdaea23e7931c0d529c52b743c711c3278a8ce T3-minimist-split-modules/spec-split-parser-modules.md" ;;
    T4) echo "https://github.com/nvie/git-toolbelt.git 354262e7d595a5f42d935fdce5a3930d0b173391 T4-git-toolbelt-stale-branches/spec-stale-branches.md" ;;
    T5) echo "https://github.com/pallets/click.git 6d5bac5c712195cbfa9666ba0ecbf0573cdea356 T5-click-short-help-abbreviation/spec-short-help-abbreviation.md" ;;
    *) die "unknown task $1" ;;
  esac
}

# Environment of a copy, prepared before the run (the agents do not install anything).
setup_env() { # setup_env <task> <copy>
  case "$1" in
    T1)    python3 -m venv "$2/.venv"   # the project's `tests` extra: tests/test_benchmarks.py needs pytest-codspeed
           "$2/.venv/bin/python" -m pip install -q --disable-pip-version-check -e "$2[tests]" >/dev/null ;;
    T5)    python3 -m venv "$2/.venv"
           "$2/.venv/bin/python" -m pip install -q --disable-pip-version-check -e "$2" pytest >/dev/null ;;
    T2)    (cd "$2" && "${GO:-go}" mod download && "${GO:-go}" build ./...) ;;
    T3)    if [ ! -d "$BENCH_HOME/nm/T3/node_modules" ]; then
             mkdir -p "$BENCH_HOME/nm/T3" && cp "$2/package.json" "$BENCH_HOME/nm/T3/"
             (cd "$BENCH_HOME/nm/T3" && npm install --ignore-scripts --no-audit --no-fund --loglevel=error >/dev/null)
           fi
           cp -r "$BENCH_HOME/nm/T3/node_modules" "$2/node_modules" ;;
    T4)    : ;;
  esac
}

cmd_check() {
  echo "date_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "os: $(uname -srm)"
  echo "claude_code: $("$CLAUDE_BIN" --version)"
  echo "model: ${ANTHROPIC_MODEL:?}"
  echo "maat_tag: ${MAAT_TAG:?}"
  echo "git: $(git --version)"; echo "python: $(python3 --version)"; echo "node: $(node --version)"
  echo "go: $("${GO:-go}" version)"; echo "dash: $(command -v dash)"
  [ -d "${CLAUDE_CONFIG_DIR:?}" ] || die "CLAUDE_CONFIG_DIR missing"
  [ ! -e "$CLAUDE_CONFIG_DIR/CLAUDE.md" ] || die "the benchmark config dir must not have a CLAUDE.md"
}

cmd_schedule() { # 5 tasks x 3 runs x 2 sides, shuffled with a published seed
  local seed=${1:?seed}
  python3 - "$seed" > "$HERE/schedule.tsv" <<'PY'
import random, sys
rows = [(t, side, k) for t in ("T1", "T2", "T3", "T4", "T5") for side in ("maat", "baseline") for k in (1, 2, 3)]
random.Random(sys.argv[1]).shuffle(rows)
print("order\trun_id\ttask\tside")
for i, (t, side, k) in enumerate(rows, 1):
    print(f"{i}\t{t}-{side}-{k}\t{t}\t{side}")
PY
  echo "schedule.tsv written (seed $seed)"
}

mirror() { # mirror <url>: local bare mirror, fetched once
  local m="$BENCH_HOME/mirrors/$(basename "$1")"
  [ -d "$m" ] || git clone -q --mirror "$1" "$m"
  echo "$m"
}

cmd_prepare() {
  local id=${1:?run-id}; local task=${id%%-*}; local side; side=$(echo "$id" | cut -d- -f2)
  read -r url sha spec <<<"$(task_row "$task")"
  local c="$BENCH_HOME/copies/$id"; [ ! -e "$c" ] || die "$c exists: a run is never repeated"
  local m; m=$(mirror "$url")
  git -C "$m" cat-file -e "$sha^{commit}" || die "commit $sha not found in $url"
  # Snapshot without history: no future commit (with the upstream fix) is reachable from the copy.
  mkdir -p "$c"; git -C "$m" archive --format=tar "$sha" | tar -x -C "$c"
  ( cd "$c" && git init -q -b main && git config core.autocrlf false && git config user.name bench \
      && git config user.email bench@example.invalid && git add -A \
      && GIT_AUTHOR_DATE=$BASE_DATE GIT_COMMITTER_DATE=$BASE_DATE git commit -q -m "benchmark base $task $sha" )
  printf '%s\n' .claude/ .venv/ node_modules/ >> "$c/.git/info/exclude"
  setup_env "$task" "$c"
  local name; name=$(basename "$spec")
  mkdir -p "$c/.claude/.ai-workflow"
  cp "$HERE/tasks/$spec" "$c/.claude/.ai-workflow/$name"
  # Same project settings on both sides: no web tools (the upstream fixes of T2 and T5 are public).
  printf '%s\n' '{ "permissions": { "deny": ["WebFetch", "WebSearch"] } }' > "$c/.claude/settings.json"
  if [ "$side" = maat ]; then
    : "${CLAUDE_CONFIG_DIR:?set CLAUDE_CONFIG_DIR}" "${MAAT_TAG:?set MAAT_TAG}"; export CLAUDE_CONFIG_DIR
    ( cd "$c" && "$CLAUDE_BIN" plugin marketplace add "https://github.com/Diegoiorio/maat.git#$MAAT_TAG" --scope project >/dev/null \
        && "$CLAUDE_BIN" plugin install maat@maat --scope project >/dev/null )
    cp "$HERE/tasks/$(dirname "$spec")/maat.json" "$c/.claude/maat.json"
    local root v; root=$(plugin_root)
    v=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$root/.claude-plugin/plugin.json")
    [ "v$v" = "$MAAT_TAG" ] || die "installed Maat $v, expected $MAAT_TAG"
  fi
  ( cd "$c" && git rev-parse HEAD ) > "$c/.git/bench-base"
  echo "$c"
}

plugin_root() { ls -d "$CLAUDE_CONFIG_DIR"/plugins/cache/maat/maat/"${MAAT_TAG#v}" 2>/dev/null || die "Maat ${MAAT_TAG} not in the plugin cache"; }

cmd_run() {
  local id=${1:?run-id}; local task=${id%%-*}; local side; side=$(echo "$id" | cut -d- -f2)
  read -r url sha spec <<<"$(task_row "$task")"
  local c="$BENCH_HOME/copies/$id" r="$BENCH_HOME/records/$id"
  [ -d "$c" ] || die "prepare $id first"; [ ! -e "$r" ] || die "$r exists: a run is never repeated"
  mkdir -p "$r"; local name; name=$(basename "$spec")
  cmd_check > "$r/environment.txt"
  local t0 t1 rc=0
  t0=$(date +%s); date -u +%Y-%m-%dT%H:%M:%SZ > "$r/started_utc"
  if [ "$side" = maat ]; then
    local root; root=$(plugin_root)
    ( cd "$c" && export CLAUDE_PLUGIN_ROOT="$root" && . "$root/scripts/python.sh" \
        && timeout "$TIME_CAP_S" "$FIC_PY" "$root/scripts/driver.py" run ".claude/.ai-workflow/$name" -- ) \
        > "$r/driver-stdout.txt" 2>&1 || rc=$?
  else
    ( cd "$c" && timeout "$TIME_CAP_S" "$CLAUDE_BIN" -p "$(sed "s|{spec}|.claude/.ai-workflow/$name|" "$HERE/baseline-prompt.txt")" \
        --permission-mode bypassPermissions --disallowedTools WebFetch WebSearch --strict-mcp-config \
        --output-format stream-json --verbose < /dev/null ) > "$r/transcript.jsonl" 2> "$r/stderr.txt" || rc=$?
  fi
  t1=$(date +%s); date -u +%Y-%m-%dT%H:%M:%SZ > "$r/ended_utc"
  echo "$rc" > "$r/exit_code"; echo $((t1 - t0)) > "$r/wall_clock_s"
  collect "$id" "$side" "$c" "$r" "$name" "$sha"
}

collect() { # the raw material of the record; the record itself is filled in with run-record.md
  local id=$1 side=$2 c=$3 r=$4 name=$5 sha=$6 base
  base=$(cat "$c/.git/bench-base")
  ( cd "$c" && git add -A -N . && git diff --binary "$base" -- . ':(exclude).claude' ) > "$r/final.diff"
  sha256sum "$r/final.diff" | cut -d' ' -f1 > "$r/final.diff.sha256"
  sha256sum "$c/.claude/.ai-workflow/$name" | cut -d' ' -f1 > "$r/spec-after-run.sha256"
  # the versions of the prepared environment (installed at prepare time, so they can differ between runs)
  if [ -x "$c/.venv/bin/python" ]; then "$c/.venv/bin/python" -m pip freeze --exclude-editable > "$r/env-packages.txt" 2>&1 || true
  elif [ -d "$c/node_modules" ]; then (cd "$c" && npm ls --all --parseable 2>/dev/null | sed "s|^$c/||") > "$r/env-packages.txt" || true; fi
  if [ "$side" = maat ]; then
    local root; root=$(plugin_root)
    cp "$c/.claude/.ai-workflow/$name" "$r/spec-with-plan-and-review.md"   # Maat writes plan, review, evidence here
    cp -r "$c/.claude/.ai-workflow/${name%.md}.run" "$r/run-dir" 2>/dev/null || true
    ( cd "$c" && . "$root/scripts/python.sh" && "$FIC_PY" "$root/scripts/phase-usage.py" --summary ".claude/.ai-workflow/${name%.md}.run" ) \
      > "$r/cost-summary.txt" 2>&1 || true
    grep -a 'Driver result: ' "$r/driver-stdout.txt" | tail -1 > "$r/outcome.txt" || true
  else
    python3 - "$r/transcript.jsonl" > "$r/report.md" <<'PY'
import json, sys
last = None
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try:
        ev = json.loads(line)
    except ValueError:
        continue
    if ev.get("type") == "result":
        last = ev
if last:
    print(last.get("result", ""))
    print(f"\n<!-- total_cost_usd={last.get('total_cost_usd')} duration_ms={last.get('duration_ms')} num_turns={last.get('num_turns')} -->")
PY
  fi
  echo "collected: $r"
}

task_dir() { local spec; read -r _ _ spec <<<"$(task_row "$1")"; dirname "$spec"; }

cmd_hidden() { # the hidden tests, right after the run: fixed in advance, no judgement. Detail stays private.
  local id=${1:?run-id}; local task=${id%%-*}
  local c="$BENCH_HOME/copies/$id" r="$BENCH_HOME/records/$id" h="$BENCH_HOME/hidden/$id"
  : "${HIDDEN_DIR:?set HIDDEN_DIR}"
  [ -f "$r/final.diff" ] || die "run $id first"; [ ! -e "$h" ] || die "$h exists: hidden tests run once per run"
  [ ! -e "$r/hidden_tests.txt" ] || die "$r/hidden_tests.txt exists"
  local line
  line=$(NM="$BENCH_HOME/nm/T3/node_modules" bash "$HIDDEN_DIR/$(task_dir "$task")/run.sh" "$c" "$h" 2>"$h.stderr" | tail -1) || true
  case "$line" in hidden:\ *) ;; *) line="hidden: error (see $h.stderr)" ;; esac
  echo "$line" > "$r/hidden_tests.txt"    # published: the score only, never the tests or their output
  echo "$id $line"
}

cmd_group() { # one group: at most MAX_GROUP consecutive rows of schedule.tsv
  local first=${1:?first order} last=${2:?last order} n=${3:-1}
  [ -f "$HERE/schedule.tsv" ] || die "run schedule first"
  : "${HIDDEN_DIR:?set HIDDEN_DIR}"
  [ "$last" -ge "$first" ] && [ $((last - first + 1)) -le "$MAX_GROUP" ] || die "a group has 1 to $MAX_GROUP runs"
  local ids; ids=$(awk -F'\t' -v a="$first" -v b="$last" 'NR > 1 && $1 >= a && $1 <= b { print $2 }' "$HERE/schedule.tsv")
  [ -n "$ids" ] || die "no row $first..$last in schedule.tsv"
  local id; for id in $ids; do cmd_prepare "$id" > /dev/null; done    # in order, one at a time (shared caches)
  # every run is followed by its hidden tests, also when the run failed or hit the cap
  printf '%s\n' $ids | xargs -P "$n" -I{} bash -c 'bash "$0" run "$1"; bash "$0" hidden "$1"' "$0" {}
}

case "${1:-}" in
  check) cmd_check ;;
  schedule) shift; cmd_schedule "$@" ;;
  prepare) shift; cmd_prepare "$@" ;;
  run) shift; cmd_run "$@" ;;
  hidden) shift; cmd_hidden "$@" ;;
  group) shift; cmd_group "$@" ;;
  *) sed -n 2,26p "$0"; exit 2 ;;
esac
