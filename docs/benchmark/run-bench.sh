#!/bin/bash
# run-bench.sh — the procedure of the Maat benchmark, as a script. Written before the first run; see README.md.
#
#   bash run-bench.sh check                      exact versions of the tools (fails on any difference); prints the
#                                                «environment» block of the records
#   bash run-bench.sh wheelhouse                 the offline wheels of the hidden tests (once, before the first group)
#   bash run-bench.sh seed <freeze commit id>    the seed of the schedule: the public commit and a drand round after it
#   bash run-bench.sh schedule <seed>            writes schedule.tsv: the 30 runs in random order
#   bash run-bench.sh prepare <run-id>           builds the clean copy of one run; no Claude session (on the Maat side
#                                                it only runs `claude plugin marketplace add` and `plugin install`)
#   bash run-bench.sh sandbox-check <run-id>     tries, inside the run's sandbox, to read what it must not see
#   bash run-bench.sh sandbox-exec <run-id> -- <command…>   a command in the run's sandbox (checks before the freeze,
#                                                never during the benchmark)
#   bash run-bench.sh run <run-id>               launches the run's side in its sandbox, then collects the record
#   bash run-bench.sh hidden <run-id>            the hidden acceptance tests on the run's final tree (after `run`)
#   bash run-bench.sh hidden --retry-infra <run-id> "<note>"   the one rerun allowed after an infrastructure error
#   bash run-bench.sh group <first> <last>       one group of the schedule, orders <first>..<last> (at most 6 runs):
#                                                check, then for each run in order: prepare, sandbox-check, run, hidden
#
# Environment (all required, fixed for the whole benchmark and written in each record):
#   BENCH_HOME        work folder (copies, mirrors, records), outside any repository
#   CLAUDE_BIN        the Claude Code binary, same for both sides (Maat's phases use it too)
#   CLAUDE_CONFIG_DIR a configuration folder used only for the benchmark: logged in, no CLAUDE.md, no plugins,
#                     no MCP servers, no hooks (the Maat plugin is installed in it, at project scope, by `prepare`)
#   ANTHROPIC_MODEL   the model id, same for both sides
#   MAAT_TAG          the Maat release under test
#   HIDDEN_DIR        the folder of the hidden acceptance tests (private until the end; never visible to a run)
#   go, gofmt, node (20), npx, dash, shellcheck, bwrap in PATH
#
# Isolation: every Claude session of both sides (and Maat's sub-sessions, children of its driver) runs inside
# bubblewrap: it sees its own copy and the benchmark's configuration folder (read-write), the system and the tools
# (read-only), a private /tmp and an empty $HOME; nothing else of the machine (other copies, mirrors, records, the
# hidden tests, /mnt). The network is shared (the API). Both sides still run with --permission-mode
# bypassPermissions (Maat's phases always do): use a disposable machine or user account. Copies have no git remote.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_HOME:?set BENCH_HOME}"
mkdir -p "$BENCH_HOME"/{mirrors,copies,records,nm,hidden}
export DISABLE_AUTOUPDATER=1               # one Claude Code binary for the whole benchmark
MAX_GROUP=6                                # runs per group, one at a time; the quota is checked before each group
TIME_CAP_S=${TIME_CAP_S:-14400}            # 4 h, the same cap for both sides (pre-registered)
HIDDEN_CAP_S=3600                          # cap of the hidden tests of one run
BASE_DATE='2026-01-01T00:00:00 +0000'      # fixed date of the snapshot commit: same commit id for every copy
# Exact versions (pre-registered): `check` fails on any difference.
WANT_CLAUDE=2.1.318 WANT_MODEL=claude-opus-5-5 WANT_MAAT=v1.6.0 WANT_GO=go1.27 WANT_NODE=v20 WANT_SHELLCHECK=0.10.0
# drand «quicknet» (League of Entropy): the public randomness of the seed
DRAND_URL=https://api.drand.sh DRAND_CHAIN=52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971
DRAND_GENESIS=1692803367 DRAND_PERIOD=3 SEED_DELAY_S=3600
GITHUB_REPO=Diegoiorio/maat                # the freeze commit is read from here: it must be public

die() { echo "run-bench: $*" >&2; exit 2; }

# ---- tasks: id | repository | starting commit | spec file | fixed total of the hidden tests ----------------------
task_row() {
  case "$1" in
    T1) echo "https://github.com/python-humanize/humanize.git d16e6352c9785c5ab86de0133222bd22e89b0db2 T1-humanize-parse-size/spec-parse-naturalsize.md 120" ;;
    T2) echo "https://github.com/dustin/go-humanize.git a1b4e66b9a6d890e9e15e7091cf16c8032367d6e T2-go-humanize-bytes-rounding/spec-bytes-rounding-unit.md 21" ;;
    T3) echo "https://github.com/minimistjs/minimist.git ecfdaea23e7931c0d529c52b743c711c3278a8ce T3-minimist-split-modules/spec-split-parser-modules.md 21" ;;
    T4) echo "https://github.com/nvie/git-toolbelt.git 354262e7d595a5f42d935fdce5a3930d0b173391 T4-git-toolbelt-stale-branches/spec-stale-branches.md 45" ;;
    T5) echo "https://github.com/pallets/click.git 6d5bac5c712195cbfa9666ba0ecbf0573cdea356 T5-click-short-help-abbreviation/spec-short-help-abbreviation.md 106" ;;
    *) die "unknown task $1" ;;
  esac
}
side_of() { local s; s=$(echo "$1" | cut -d- -f2); case $s in maat|baseline) echo "$s" ;; *) die "bad run id $1" ;; esac; }

# Environment of a copy, prepared before the run (the agents do not install anything).
setup_env() { # setup_env <task> <copy>
  case "$1" in
    T1)    python3 -m venv "$2/.venv"   # the project's `tests` extra: tests/test_benchmarks.py needs pytest-codspeed
           "$2/.venv/bin/python" -m pip install -q --disable-pip-version-check -e "$2[tests]" >/dev/null ;;
    T5)    python3 -m venv "$2/.venv"
           "$2/.venv/bin/python" -m pip install -q --disable-pip-version-check -e "$2" pytest >/dev/null ;;
    T2)    (cd "$2" && go mod download && go build ./...) ;;
    T3)    if [ ! -d "$BENCH_HOME/nm/T3/node_modules" ]; then
             mkdir -p "$BENCH_HOME/nm/T3" && cp "$2/package.json" "$BENCH_HOME/nm/T3/"
             (cd "$BENCH_HOME/nm/T3" && npm install --ignore-scripts --no-audit --no-fund --loglevel=error >/dev/null)
           fi
           cp -r "$BENCH_HOME/nm/T3/node_modules" "$2/node_modules" ;;
    T4)    : ;;
  esac
}
env_packages() { # the versions installed in a copy
  if [ -x "$1/.venv/bin/python" ]; then "$1/.venv/bin/python" -m pip freeze --exclude-editable 2>&1
  elif [ -d "$1/node_modules" ]; then (cd "$1" && npm ls --all --parseable 2>/dev/null | sed "s|^$1/||")
  else echo "(nothing installed)"; fi
}

cmd_check() {
  local cv gv nv sv
  cv=$("$CLAUDE_BIN" --version | cut -d' ' -f1); gv=$(go version | cut -d' ' -f3); nv=$(node --version)
  sv=$(shellcheck --version 2>/dev/null | sed -n 's/^version: //p')
  echo "date_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "os: $(uname -srm)"
  echo "claude_code: $cv"; echo "model: ${ANTHROPIC_MODEL:-}"; echo "maat_tag: ${MAAT_TAG:-}"
  echo "git: $(git --version)"; echo "python: $(python3 --version)"; echo "node: $nv"; echo "go: $gv"
  echo "dash: $(command -v dash || true)"; echo "shellcheck: $sv"; echo "bwrap: $(bwrap --version 2>/dev/null || true)"
  [ "$cv" = "$WANT_CLAUDE" ] || die "check: Claude Code $cv, expected $WANT_CLAUDE"
  [ "${ANTHROPIC_MODEL:-}" = "$WANT_MODEL" ] || die "check: ANTHROPIC_MODEL ${ANTHROPIC_MODEL:-unset}, expected $WANT_MODEL"
  [ "${MAAT_TAG:-}" = "$WANT_MAAT" ] || die "check: MAAT_TAG ${MAAT_TAG:-unset}, expected $WANT_MAAT"
  case $gv in "$WANT_GO"|"$WANT_GO".*) ;; *) die "check: go $gv, expected $WANT_GO" ;; esac
  case $nv in "$WANT_NODE".*) ;; *) die "check: node $nv, expected $WANT_NODE" ;; esac
  [ "$sv" = "$WANT_SHELLCHECK" ] || die "check: shellcheck ${sv:-missing}, expected $WANT_SHELLCHECK"
  command -v dash >/dev/null || die "check: dash missing"
  command -v bwrap >/dev/null || die "check: bwrap (bubblewrap) missing"
  [ -d "${CLAUDE_CONFIG_DIR:-}" ] || die "check: CLAUDE_CONFIG_DIR missing"
  [ ! -e "$CLAUDE_CONFIG_DIR/CLAUDE.md" ] || die "check: the benchmark config dir must not have a CLAUDE.md"
}

cmd_wheelhouse() { # offline wheels of the hidden tests, from their pinned list (hashes checked)
  : "${HIDDEN_DIR:?set HIDDEN_DIR}"
  mkdir -p "$BENCH_HOME/wheelhouse"
  python3 -m pip download -q --disable-pip-version-check --only-binary :all: --no-deps --require-hashes \
    -r "$HIDDEN_DIR/requirements-hidden.txt" -d "$BENCH_HOME/wheelhouse"
  ls "$BENCH_HOME/wheelhouse"
}

cmd_seed() { # seed <freeze commit id>: sha256 of «<commit>:<round>:<randomness>», drand round SEED_DELAY_S after it
  local commit=${1:?freeze commit id}
  [ ${#commit} -eq 40 ] || die "the full commit id (40 hex digits)"
  python3 - "$commit" "$GITHUB_REPO" "$DRAND_URL" "$DRAND_CHAIN" "$DRAND_GENESIS" "$DRAND_PERIOD" "$SEED_DELAY_S" <<'PY'
import calendar, hashlib, json, sys, time, urllib.request
commit, repo, url, chain, genesis, period, delay = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]), int(sys.argv[6]), int(sys.argv[7])
# the committer date as GitHub has it: the commit must be public
with urllib.request.urlopen("https://api.github.com/repos/%s/commits/%s" % (repo, commit), timeout=30) as r:
    c = json.load(r)
assert c["sha"] == commit
ct = calendar.timegm(time.strptime(c["commit"]["committer"]["date"], "%Y-%m-%dT%H:%M:%SZ"))
target = ct + delay
rnd = max(1, -(-(target - genesis) // period) + 1)   # first round whose time >= committer date + delay
at = genesis + (rnd - 1) * period
if time.time() < at:
    sys.exit("run-bench: round %d is at %s UTC: not public yet" % (rnd, time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(at))))
with urllib.request.urlopen("%s/%s/public/%d" % (url, chain, rnd), timeout=30) as r:
    d = json.load(r)
assert d["round"] == rnd
seed = hashlib.sha256(("%s:%d:%s" % (commit, rnd, d["randomness"])).encode()).hexdigest()
print("commit: %s\ncommitter_date_unix: %d\ndrand_chain: %s\ndrand_round: %d\ndrand_round_time_utc: %s\n"
      "drand_randomness: %s\nseed: %s" % (commit, ct, chain, rnd, time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(at)),
                                          d["randomness"], seed))
PY
}

cmd_schedule() { # 5 tasks x 3 runs x 2 sides, shuffled with the published seed
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

mirror() { # mirror <url>: local bare mirror, fetched once; never visible inside a sandbox
  local m; m="$BENCH_HOME/mirrors/$(basename "$1")"
  [ -d "$m" ] || git clone -q --mirror "$1" "$m"
  echo "$m"
}

cmd_prepare() {
  local id=${1:?run-id}; local task=${id%%-*}; local side; side=$(side_of "$id")
  read -r url sha spec _ <<<"$(task_row "$task")"
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
  env_packages "$c" > "$c/.git/bench-env-packages.txt"
  local name; name=$(basename "$spec")
  mkdir -p "$c/.claude/.ai-workflow"
  cp "$HERE/tasks/$spec" "$c/.claude/.ai-workflow/$name"
  # Same project settings on both sides: no web tools (the upstream fixes of T2 and T5 are public). The Maat side
  # gets this deny through these settings only (its driver has no --disallowedTools); the baseline also on its
  # command line.
  printf '%s\n' '{ "permissions": { "deny": ["WebFetch", "WebSearch"] } }' > "$c/.claude/settings.json"
  if [ "$side" = maat ]; then
    : "${CLAUDE_CONFIG_DIR:?set CLAUDE_CONFIG_DIR}" "${MAAT_TAG:?set MAAT_TAG}"; export CLAUDE_CONFIG_DIR
    ( cd "$c" && "$CLAUDE_BIN" plugin marketplace add "https://github.com/Diegoiorio/maat.git#$MAAT_TAG" --scope project >/dev/null \
        && "$CLAUDE_BIN" plugin install maat@maat --scope project >/dev/null )
    cp "$HERE/tasks/$(dirname "$spec")/maat.json" "$c/.claude/maat.json"
    # the task's format adapter (T2, T3: test output -> JUnit that Maat reads), outside the project's code
    if [ -d "$HERE/tasks/$(dirname "$spec")/adapter" ]; then
      mkdir -p "$c/.claude/bench" && cp "$HERE/tasks/$(dirname "$spec")/adapter/"* "$c/.claude/bench/"
    fi
    local root v; root=$(plugin_root)
    v=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$root/.claude-plugin/plugin.json")
    [ "v$v" = "$MAAT_TAG" ] || die "installed Maat $v, expected $MAAT_TAG"
  fi
  # the frozen spec, as copied: same hash as SHA256SUMS
  local want got; want=$(awk -v f="tasks/$spec" '$2 == f { print $1 }' "$HERE/SHA256SUMS")
  got=$(sha256sum "$c/.claude/.ai-workflow/$name" | cut -d' ' -f1)
  [ -n "$want" ] && [ "$got" = "$want" ] || die "the spec in the copy ($got) is not the frozen one ($want)"
  echo "$got" > "$c/.git/bench-spec.sha256"
  # the prepared copy is clean: the environment and .claude/ are excluded, nothing else changed
  [ -z "$(git -C "$c" status --porcelain)" ] || die "the prepared copy is not clean: $(git -C "$c" status --porcelain | head -3)"
  ( cd "$c" && git rev-parse HEAD ) > "$c/.git/bench-base"
  echo "$c"
}

plugin_root() { ls -d "$CLAUDE_CONFIG_DIR"/plugins/cache/maat/maat/"${MAAT_TAG#v}" 2>/dev/null || die "Maat ${MAAT_TAG} not in the plugin cache"; }

# ---- the sandbox -----------------------------------------------------------------------------------------------
# sbx <rw-dir…> -- <ro-dir…> --: fills SBX with the bwrap arguments. Visible: the system (/usr, /etc, read-only),
# the tools (Claude Code, go, node, shellcheck: read-only), the given folders; a private /tmp, an empty $HOME, a
# new /proc and /dev. The current working directory is the first rw folder (or the first ro one).
sbx() {
  local rw=() ro=() d mode=rw
  for d in "$@"; do
    if [ "$d" = -- ]; then mode=ro; continue; fi
    if [ "$mode" = rw ]; then rw+=("$d"); else ro+=("$d"); fi
  done
  local claude_real node_root go_root rc
  claude_real=$(readlink -f "$CLAUDE_BIN"); node_root=$(dirname "$(dirname "$(readlink -f "$(command -v node)")")")
  go_root=$(go env GOROOT)
  SBX=(--die-with-parent --new-session --unshare-pid --unshare-ipc --unshare-uts --unshare-cgroup-try
       --ro-bind /usr /usr --ro-bind /etc /etc --ro-bind-try /sys /sys
       --symlink usr/bin /bin --symlink usr/sbin /sbin --symlink usr/lib /lib --symlink usr/lib64 /lib64
       --proc /proc --dev /dev --tmpfs /tmp --tmpfs "$HOME"
       --ro-bind "$claude_real" "$claude_real" --ro-bind "$(dirname "$CLAUDE_BIN")" "$(dirname "$CLAUDE_BIN")"
       --ro-bind "$node_root" "$node_root" --ro-bind "$go_root" "$go_root"
       --ro-bind "$(dirname "$(command -v shellcheck)")" "$(dirname "$(command -v shellcheck)")")
  rc=$(readlink -f /etc/resolv.conf); case $rc in /etc/*) ;; *) SBX+=(--ro-bind-try "$rc" "$rc") ;; esac
  for d in ${rw[@]+"${rw[@]}"}; do SBX+=(--bind "$d" "$d"); done
  for d in ${ro[@]+"${ro[@]}"}; do SBX+=(--ro-bind "$d" "$d"); done
  [ ! -d "${CLAUDE_CONFIG_DIR:-/nonexistent}/plugins" ] || SBX+=(--ro-bind "$CLAUDE_CONFIG_DIR/plugins" "$CLAUDE_CONFIG_DIR/plugins")
  SBX+=(--chdir "${rw[0]:-${ro[0]}}" --clearenv
        --setenv HOME "$HOME" --setenv USER "$(id -un)" --setenv LANG C.UTF-8 --setenv TMPDIR /tmp
        --setenv PATH "$node_root/bin:$go_root/bin:$(dirname "$CLAUDE_BIN"):$(dirname "$(command -v shellcheck)"):/usr/local/bin:/usr/bin:/bin"
        --setenv CLAUDE_BIN "$CLAUDE_BIN" --setenv CLAUDE_CONFIG_DIR "${CLAUDE_CONFIG_DIR:-}"
        --setenv ANTHROPIC_MODEL "${ANTHROPIC_MODEL:-}" --setenv DISABLE_AUTOUPDATER 1
        --setenv GOTOOLCHAIN local --setenv GOCACHE /tmp/go-cache --setenv GOPATH /tmp/go --setenv GOPROXY off
        --setenv GOFLAGS -mod=mod --setenv npm_config_cache /tmp/npm-cache --setenv npm_config_offline true)
}

cmd_sandbox_check() { # sandbox-check <run-id>: what the run must not see, tried from inside its sandbox
  local id=${1:?run-id}; local c="$BENCH_HOME/copies/$id"
  [ -d "$c" ] || die "prepare $id first"
  sbx "$c" "$CLAUDE_CONFIG_DIR" --
  local probe=("$BENCH_HOME/mirrors" "$BENCH_HOME/records" "$BENCH_HOME/hidden" "$BENCH_HOME/nm" "${HIDDEN_DIR:-/nonexistent}"
               "$HERE" /mnt/c "$HOME/.ssh" "$HOME/.claude")   # /mnt/c: the Windows drive of WSL
  local other
  for other in "$BENCH_HOME"/copies/*; do
    if [ -d "$other" ] && [ "$other" != "$c" ]; then probe+=("$other"); break; fi
  done
  local p bad=0
  for p in "${probe[@]}"; do
    if bwrap "${SBX[@]}" -- sh -c 'ls -A "$1" 2>/dev/null | head -1 | grep -q .' _ "$p"; then
      echo "sandbox-check: VISIBLE $p"; bad=1
    fi
  done
  bwrap "${SBX[@]}" -- sh -c 'test -w . && git status --porcelain >/dev/null' || { echo "sandbox-check: the copy is not usable"; bad=1; }
  [ "$bad" -eq 0 ] || die "sandbox-check failed for $id"
  echo "sandbox-check: ok ($id: ${#probe[@]} paths not visible, copy usable)"
}

cmd_sandbox_exec() {
  local id=${1:?run-id}; shift; [ "${1:-}" = -- ] && shift
  local c="$BENCH_HOME/copies/$id"; [ -d "$c" ] || die "prepare $id first"
  sbx "$c" "$CLAUDE_CONFIG_DIR" --
  local root=""; [ "$(side_of "$id")" != maat ] || root=$(plugin_root)
  bwrap "${SBX[@]}" --setenv CLAUDE_PLUGIN_ROOT "$root" -- "$@"
}

cmd_run() {
  local id=${1:?run-id}; local task=${id%%-*}; local side; side=$(side_of "$id")
  read -r url sha spec _ <<<"$(task_row "$task")"
  local c="$BENCH_HOME/copies/$id" r="$BENCH_HOME/records/$id" env
  [ -d "$c" ] || die "prepare $id first"; [ ! -e "$r" ] || die "$r exists: a run is never repeated"
  env=$(cmd_check) || exit 2                    # exact versions, before the record exists
  mkdir -p "$r"; local name; name=$(basename "$spec")
  echo "$env" > "$r/environment.txt"
  local t0 t1 rc=0
  sbx "$c" "$CLAUDE_CONFIG_DIR" --
  t0=$(date +%s); date -u +%Y-%m-%dT%H:%M:%SZ > "$r/started_utc"
  if [ "$side" = maat ]; then
    local root; root=$(plugin_root)
    timeout -k 60 "$TIME_CAP_S" bwrap "${SBX[@]}" --setenv CLAUDE_PLUGIN_ROOT "$root" -- bash -c \
      '. "$CLAUDE_PLUGIN_ROOT/scripts/python.sh" && exec "$FIC_PY" "$CLAUDE_PLUGIN_ROOT/scripts/driver.py" run "$1" --' \
      _ ".claude/.ai-workflow/$name" > "$r/driver-stdout.txt" 2>&1 || rc=$?
  else
    timeout -k 60 "$TIME_CAP_S" bwrap "${SBX[@]}" -- "$CLAUDE_BIN" -p \
      "$(sed "s|{spec}|.claude/.ai-workflow/$name|" "$HERE/baseline-prompt.txt")" \
      --permission-mode bypassPermissions --disallowedTools WebFetch WebSearch --strict-mcp-config \
      --output-format stream-json --verbose < /dev/null > "$r/transcript.jsonl" 2> "$r/stderr.txt" || rc=$?
  fi
  t1=$(date +%s); date -u +%Y-%m-%dT%H:%M:%SZ > "$r/ended_utc"
  echo "$rc" > "$r/exit_code"; echo $((t1 - t0)) > "$r/wall_clock_s"
  collect "$id" "$side" "$c" "$r" "$name"
}

collect() { # the raw material of the record; the record itself is filled in with run-record.md
  local id=$1 side=$2 c=$3 r=$4 name=$5 base
  base=$(cat "$c/.git/bench-base")
  ( cd "$c" && git add -A -N . && git diff --binary "$base" -- . ':(exclude).claude' ) > "$r/final.diff"
  sha256sum "$r/final.diff" | cut -d' ' -f1 > "$r/final.diff.sha256"
  cp "$c/.git/bench-spec.sha256" "$r/spec-in-copy.sha256"
  sha256sum "$c/.claude/.ai-workflow/$name" | cut -d' ' -f1 > "$r/spec-after-run.sha256"
  cp "$c/.git/bench-env-packages.txt" "$r/env-packages.txt"
  local logs=()
  if [ "$side" = maat ]; then
    local root; root=$(plugin_root)
    cp "$c/.claude/.ai-workflow/$name" "$r/spec-with-plan-and-review.md"   # Maat writes plan, review, evidence here
    cp -r "$c/.claude/.ai-workflow/${name%.md}.run" "$r/run-dir" 2>/dev/null || true
    ( cd "$c" && . "$root/scripts/python.sh" && "$FIC_PY" "$root/scripts/phase-usage.py" --summary ".claude/.ai-workflow/${name%.md}.run" ) \
      > "$r/cost-summary.txt" 2>&1 || true
    grep -a 'Driver result: ' "$r/driver-stdout.txt" | tail -1 > "$r/outcome.txt" || true
    logs=("$r/driver-stdout.txt" "$r/run-dir")
  else
    python3 - "$r/transcript.jsonl" > "$r/report.md" <<'PY'
import json, sys
last, usage = None, {}
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try:
        ev = json.loads(line)
    except ValueError:
        continue
    if ev.get("type") == "result":
        last = ev
    elif ev.get("type") == "assistant":       # tokens of each model call (the last event of a message wins)
        m = ev.get("message") or {}
        if m.get("id") and isinstance(m.get("usage"), dict):
            usage[m["id"]] = (m.get("model"), m["usage"])
if last:
    print(last.get("result", ""))
    print(f"\n<!-- total_cost_usd={last.get('total_cost_usd')} duration_ms={last.get('duration_ms')} num_turns={last.get('num_turns')} -->")
tot = {}
for model, u in usage.values():
    t = tot.setdefault(model, {"calls": 0})
    t["calls"] += 1
    for k in ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"):
        t[k] = t.get(k, 0) + int(u.get(k) or 0)
print("<!-- usage_from_transcript=%s -->" % json.dumps(tot, sort_keys=True))
PY
    logs=("$r/transcript.jsonl" "$r/stderr.txt")
  fi
  audit "$id" "$c" "$r" "${logs[@]}"
  model_check "$side" "$r"
  quota_check "$r" "${logs[@]}"
  echo "collected: $r"
}

# AUDIT: any trace of a path outside the run's copy (another copy, the mirrors, the records, the hidden tests,
# /mnt) in what the run left. A hit is recorded and published; the run is marked contaminated (never repeated).
audit() { # audit <id> <copy> <record> <files or folders…>
  local id=$1 c=$2 r=$3; shift 3
  python3 - "$BENCH_HOME" "$c" "${HIDDEN_DIR:-/nonexistent}" "$HERE" "$@" > "$r/audit.txt" <<'PY'
import os, re, sys
bench, copy, hidden, here = sys.argv[1:5]
pats = [re.escape(bench) + r"/(?:mirrors|records|hidden|nm|copies/(?!%s(?:/|\b)))" % re.escape(os.path.basename(copy)),
        re.escape(hidden), r"benchmark-nascosti", r"docs/piani", r"riferimenti/", re.escape(here), r"(?<![\w.])/mnt/[a-z]/"]
rx = re.compile("|".join("(?:%s)" % p for p in pats))
hits = []
def scan(f):
    try:
        with open(f, encoding="utf-8", errors="replace") as fh:
            for n, line in enumerate(fh, 1):
                for m in rx.finditer(line):
                    hits.append("%s:%d: %s" % (os.path.relpath(f, os.path.dirname(copy)), n, m.group(0).replace(bench, "$BENCH_HOME")))
    except OSError:
        pass
for p in sys.argv[5:]:
    if os.path.isdir(p):
        for d, _, fs in os.walk(p):
            for f in sorted(fs):
                scan(os.path.join(d, f))
    elif os.path.isfile(p):
        scan(p)
print("audit: clean" if not hits else "audit: CONTAMINATED (%d hits)" % len(hits))
for h in hits[:200]:
    print(h)
PY
}

model_check() { # the model of every session, from its init event, against ANTHROPIC_MODEL
  local side=$1 r=$2 files=()
  if [ "$side" = maat ]; then mapfile -t files < <(find "$r/run-dir" -name '*.jsonl' 2>/dev/null | sort); else files=("$r/transcript.jsonl"); fi
  python3 - "$ANTHROPIC_MODEL" ${files[@]+"${files[@]}"} > "$r/model-check.txt" <<'PY'
import json, sys
want, seen, bad = sys.argv[1], 0, []
for f in sys.argv[2:]:
    for line in open(f, encoding="utf-8", errors="replace"):
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if ev.get("type") == "system" and ev.get("subtype") == "init":
            seen += 1
            if ev.get("model") != want:
                bad.append("%s: %s" % (f.rsplit("/", 1)[-1], ev.get("model")))
print("model: %s (%d sessions)" % ("ok " + want if not bad and seen else "MISMATCH" if bad else "no init event", seen))
for b in bad:
    print(b)
PY
}

quota_check() { # quota_check <record> <files or folders…>: a run closed or slowed by the usage limit
  local r=$1; shift
  if grep -a -r -i -E -h -m 3 'usage limit|limit reached|rate_limit_error|out of extra usage' "$@" > "$r/quota.txt" 2>/dev/null; then
    sed -i '1i quota: suspected (recorded as it is, reason «quota», reported apart)' "$r/quota.txt"
  else echo "quota: none" > "$r/quota.txt"; fi
}

task_dir() { local spec; read -r _ _ spec _ <<<"$(task_row "$1")"; dirname "$spec"; }
task_total() { local t; read -r _ _ _ t <<<"$(task_row "$1")"; echo "$t"; }

cmd_hidden() { # the hidden tests, right after the run: fixed in advance, no judgement. Detail stays private.
  local retry="" note=""
  if [ "${1:-}" = --retry-infra ]; then retry=1; shift; note=${2:-}; [ -n "$note" ] || die "--retry-infra needs a note"; fi
  local id=${1:?run-id}; local task=${id%%-*}; local total; total=$(task_total "$task")
  local c="$BENCH_HOME/copies/$id" r="$BENCH_HOME/records/$id" h="$BENCH_HOME/hidden/$id"
  : "${HIDDEN_DIR:?set HIDDEN_DIR}"
  [ -f "$r/final.diff" ] || die "run $id first"
  ( cd "$HIDDEN_DIR" && sha256sum -c --quiet SHA256SUMS ) || die "the hidden tests differ from their SHA256SUMS"
  [ -d "$BENCH_HOME/wheelhouse" ] || die "run-bench.sh wheelhouse first"
  if [ -n "$retry" ]; then
    grep -q '^hidden: infra-error' "$r/hidden_tests.txt" 2>/dev/null || die "a retry only follows an infrastructure error"
    [ ! -e "$r/hidden_tests.infra-1.txt" ] || die "the one retry was already used"
    mv "$r/hidden_tests.txt" "$r/hidden_tests.infra-1.txt"; mv "$h" "$h.infra-1"
    printf 'hidden tests rerun once after an infrastructure error: %s\n' "$note" >> "$r/notes.txt"
  fi
  [ ! -e "$h" ] || die "$h exists: hidden tests run once per run"
  [ ! -e "$r/hidden_tests.txt" ] || die "$r/hidden_tests.txt exists"
  mkdir -p "$h"
  sbx "$h" -- "$c" "$HIDDEN_DIR" "$BENCH_HOME/wheelhouse" "$BENCH_HOME/nm" --
  local line rc=0
  line=$(timeout -k 30 "$HIDDEN_CAP_S" bwrap "${SBX[@]}" --setenv WHEELHOUSE "$BENCH_HOME/wheelhouse" \
           --setenv NM "$BENCH_HOME/nm/T3/node_modules" -- \
           bash "$HIDDEN_DIR/$(task_dir "$task")/run.sh" "$c" "$h/out" 2>"$h/stderr.txt" | tail -1) || rc=$?
  case "$line" in
    "hidden: infra-error"*) ;;
    hidden:\ [0-9]*/"$total"*) ;;
    *) if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then line="hidden: 0/$total (timeout)"
       else line="hidden: 0/$total (no score)"; fi ;;
  esac
  echo "$line" > "$r/hidden_tests.txt"    # published: the score only, never the tests or their output
  echo "$id $line"
  case "$line" in "hidden: infra-error"*)
    [ -n "$retry" ] && { echo "second infrastructure error: recorded as it is (no score)" >> "$r/notes.txt"; return 0; }
    echo "run-bench: infrastructure error; fix it, then once: run-bench.sh hidden --retry-infra $id \"<note>\"" >&2; return 3 ;;
  esac
}

cmd_group() { # one group: at most MAX_GROUP consecutive rows of schedule.tsv, one run at a time
  local first=${1:?first order} last=${2:?last order}
  [ -f "$HERE/schedule.tsv" ] || die "run schedule first"
  : "${HIDDEN_DIR:?set HIDDEN_DIR}"
  [ "$last" -ge "$first" ] && [ $((last - first + 1)) -le "$MAX_GROUP" ] || die "a group has 1 to $MAX_GROUP runs"
  local ids; ids=$(awk -F'\t' -v a="$first" -v b="$last" 'NR > 1 && $1 >= a && $1 <= b { print $2 }' "$HERE/schedule.tsv")
  [ -n "$ids" ] || die "no row $first..$last in schedule.tsv"
  local id
  for id in $ids; do
    cmd_check > /dev/null
    cmd_prepare "$id" > /dev/null
    cmd_sandbox_check "$id"
    cmd_run "$id"
    cmd_hidden "$id" || true      # an infrastructure error stops nothing: its one retry is made by hand
  done
}

case "${1:-}" in
  check) cmd_check ;;
  wheelhouse) cmd_wheelhouse ;;
  seed) shift; cmd_seed "$@" ;;
  schedule) shift; cmd_schedule "$@" ;;
  prepare) shift; cmd_prepare "$@" ;;
  sandbox-check) shift; cmd_sandbox_check "$@" ;;
  sandbox-exec) shift; cmd_sandbox_exec "$@" ;;
  run) shift; cmd_run "$@" ;;
  hidden) shift; cmd_hidden "$@" ;;
  group) shift; cmd_group "$@" ;;
  *) sed -n 2,34p "$0"; exit 2 ;;
esac
