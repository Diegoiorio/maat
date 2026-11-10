#!/bin/bash
# run-bench.sh — the procedure of version 3 of the Maat benchmark, as a script. Written before the first run; it
# keeps the structure, the guarantees and the record format of version 2 (../benchmark/run-bench.sh).
#
#   bash run-bench.sh check                      exact versions of the tools (fails on any difference); prints the
#                                                «environment» block of the records
#   bash run-bench.sh seed <freeze commit id>    the seed of the schedule: the public commit and a drand round after it
#   bash run-bench.sh schedule <seed>            writes schedule.tsv: the 48 runs in random order
#   bash run-bench.sh prepare <run-id>           builds the clean copy of one run and its task's dependencies; no Claude
#                                                session (on the Maat side it only runs `claude plugin marketplace add`
#                                                and `plugin install`)
#   bash run-bench.sh sandbox-check <run-id>     tries, inside the run's sandbox, to read what it must not see
#   bash run-bench.sh sandbox-exec <run-id> -- <command…>   a command in the run's sandbox (checks before the freeze,
#                                                never during the benchmark)
#   bash run-bench.sh run <run-id>               launches the run's side in its sandbox, then collects the record
#   bash run-bench.sh hidden <run-id>            the hidden acceptance tests on the run's final tree (after `run`)
#   bash run-bench.sh hidden --retry-infra <run-id> "<note>"   the one rerun allowed after an infrastructure error
#   bash run-bench.sh group <first> <last>       one group of the schedule, orders <first>..<last> (at most 4 runs):
#                                                the usage check before each run, then check, prepare, sandbox-check,
#                                                run, hidden
#   BENCH_DRY=1 bash run-bench.sh dry-collect <run-id>   proof of the tooling only: collects a record from a prepared
#                                                copy that nobody ran (no Claude session); `run` and `group` refuse
#                                                BENCH_DRY, and refuse a copy prepared with it
#
# Environment (all required, fixed for the whole benchmark and written in each record):
#   BENCH_HOME        work folder (copies, mirrors, dependencies, records), outside any repository
#   CLAUDE_BIN        the Claude Code binary, same for both sides (Maat's phases use it too)
#   CLAUDE_CONFIG_DIR a configuration folder used only for the benchmark: logged in, no CLAUDE.md, no plugins,
#                     no MCP servers, no hooks (the Maat plugin is installed in it, at project scope, by `prepare`)
#   ANTHROPIC_MODEL   the model id, same for both sides
#   MAAT_TAG          the Maat release under test
#   HIDDEN_DIR        the folder of the hidden acceptance tests (private until the end; never visible to a run)
#   QUOTA_CMD         optional: a command that prints the usage of the subscription as JSON (`group` reads the
#                     five-hour and the weekly window from it); without it `group` asks the operator before each run
#   go, gofmt, node (22), npx, cargo, rustc, bats, parallel, shellcheck, bwrap in PATH; python3, git, dash in /usr/bin
#
# Isolation: every Claude session of both sides (and Maat's sub-sessions, children of its driver) runs inside
# bubblewrap: it sees its own copy and the benchmark's configuration folder (read-write; the folders where Claude Code
# keeps sessions and transcripts are the run's own), its task's dependency folder, the system and the tools
# (read-only), a private /tmp and an empty $HOME; nothing else of the machine (other copies, other tasks'
# dependencies, mirrors, records, the hidden tests, /mnt). The network is shared (the API). The hidden tests run in a
# sandbox of the same kind with the network closed. Both sides still run with --permission-mode bypassPermissions
# (Maat's phases always do): use a disposable machine or user account. Copies have no git remote.
# shellcheck disable=SC2015,SC2016   # «a && b || die» is meant; single-quoted code runs inside the sandbox
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_HOME:?set BENCH_HOME}"
mkdir -p "$BENCH_HOME"/{mirrors,copies,records,hidden,deps,cfgstate,quota}
export DISABLE_AUTOUPDATER=1               # one Claude Code binary for the whole benchmark
MAX_GROUP=4                                # runs per group, one at a time (protocol v3, §7)
QUOTA_MAX=75                               # percent: above it the next run (five-hour) or the group (weekly) waits
TIME_CAP_S=${TIME_CAP_S:-14400}            # 4 h, the same cap for both sides (pre-registered)
HIDDEN_CAP_S=3600                          # cap of the hidden tests of one run
BASE_DATE='2026-01-01T00:00:00 +0000'      # fixed date of the snapshot commit: same commit id for every copy
# Exact versions (pre-registered): `check` fails on any difference.
WANT_CLAUDE=2.1.318 WANT_MODEL=claude-opus-5-5 WANT_MAAT=v1.7.0
WANT_MAAT_COMMIT=752ff923ac4fdf524f6611faaf16ea4575112912
WANT_GO=go1.27.3 WANT_NODE=v22.22.2 WANT_PYTHON=3.12.3 WANT_RUST=1.99.1 WANT_BATS=1.14.0 WANT_PARALLEL=20261022
WANT_PNPM=11.15.1 WANT_GIT=2.43.0 WANT_BASH=5.2.21 WANT_SHELLCHECK=0.10.0
TASKS="N3 N11 N2 N12 N9 N7 E1 E3"          # the drawn tasks, in the order of draw.txt
# sha256 of the SHA256SUMS of the hidden tests, fixed in the freeze commit (the tests stay private until the end)
HIDDEN_SUMS_SHA256=8e3674c1262e81d49d9d79fa2f6d901c4d3f0374265bb0ebc5915d0d3b953e81
# folders of the configuration where Claude Code keeps sessions, transcripts and file backups: one set per run
CFG_PRIVATE_DIRS="projects sessions session-env shell-snapshots file-history todos plans"
# drand «quicknet» (League of Entropy): the public randomness of the seed
DRAND_URL=https://api.drand.sh DRAND_CHAIN=52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971
DRAND_GENESIS=1692803367 DRAND_PERIOD=3 SEED_DELAY_S=3600
GITHUB_REPO=Diegoiorio/maat                # the freeze commit and the plugin are read from here: it must be public
DRY=${BENCH_DRY:-}                         # proof of the tooling only (see dry-collect)

die() { echo "run-bench: $*" >&2; exit 2; }
case $DRY in ''|1) ;; *) die "BENCH_DRY is 1 or unset" ;; esac

# ---- tasks: id | repository | starting commit | spec file | fixed total of the hidden tests ----------------------
task_row() {
  case "$1" in
    N3)  echo "https://github.com/labstack/echo.git bc4028f1d7cc373823de8b6eb057cd4a9d5fc85c N3-echo-body-limit/spec-body-limit.md 104" ;;
    N11) echo "https://github.com/tox-dev/tox.git b3e69e413bf5662dfdf54fa5049f0650b53d35e3 N11-tox-set-env-lazy/spec-set-env-lazy.md 99" ;;
    N2)  echo "https://github.com/h3js/h3.git 82bee3bfcd7b2dbad6d2b11657fd872c953d15d6 N2-h3-pathname-decoding/spec-pathname-encoding.md 234" ;;
    N12) echo "https://github.com/alecthomas/kong.git b778e12c066ce62e03f3eb1439fd003d6a4bbb25 N12-kong-lastwins/spec-lastwins-flag-groups.md 83" ;;
    N9)  echo "https://github.com/pyenv/pyenv.git 3d1dda120be789de6af219ad945c36b2a95e5d4a N9-pyenv-binary-install/spec-binary-install.md 62" ;;
    N7)  echo "https://github.com/tafia/quick-xml.git b0611e33234e7c118c85561c7bdcdd21676fe766 N7-quick-xml-depth-limit/spec-depth-limit.md 63" ;;
    E1)  echo "https://github.com/BurntSushi/toml.git eb8b9987e23e6f5aff69fb1a1d0b113840c0964e E1-toml-max-depth/spec-max-depth.md 92" ;;
    E3)  echo "https://github.com/BurntSushi/jiff.git bc41185bf7e5dbdc9f877fa21c7f3fd7318d7a48 E3-jiff-span-overflow/spec-span-overflow.md 29" ;;
    *) die "unknown task $1" ;;
  esac
}
side_of() { local s; s=$(echo "$1" | cut -d- -f2); case $s in maat|baseline) echo "$s" ;; *) die "bad run id $1" ;; esac; }
task_dir() { local spec; read -r _ _ spec _ <<<"$(task_row "$1")"; dirname "$spec"; }
task_total() { local t; read -r _ _ _ t <<<"$(task_row "$1")"; echo "$t"; }
deps_of() { echo "$BENCH_HOME/deps/$1"; }    # the task's dependency folder: written by setup-env.sh, read-only to runs

# The checksums the copies are checked against. BENCH_DRY_SUMS stands in for them only in a dry proof made before the
# freeze, when SHA256SUMS does not list the task files yet.
sums_file() { if [ -n "$DRY" ] && [ -n "${BENCH_DRY_SUMS:-}" ]; then echo "$BENCH_DRY_SUMS"; else echo "$HERE/SHA256SUMS"; fi; }

# ---- the tools ---------------------------------------------------------------------------------------------------
# tools: the toolchains in PATH, by their real folders (bound read-only into every sandbox)
tools() {
  [ -z "${TOOL_PATH:-}" ] || return 0
  : "${CLAUDE_BIN:?set CLAUDE_BIN}"
  local p
  p=$(command -v node) || die "node not in PATH"; NODE_ROOT=$(dirname "$(dirname "$(readlink -f "$p")")")
  command -v go >/dev/null || die "go not in PATH"; GO_ROOT=$(go env GOROOT)
  command -v rustc >/dev/null || die "rustc not in PATH"; RUST_ROOT=$(rustc --print sysroot)
  p=$(command -v bats) || die "bats not in PATH"; BATS_ROOT=$(dirname "$(dirname "$(readlink -f "$p")")")
  p=$(command -v parallel) || die "parallel not in PATH"; PARALLEL_DIR=$(dirname "$(readlink -f "$p")")
  p=$(command -v shellcheck) || die "shellcheck not in PATH"; SC_DIR=$(dirname "$p")
  CLAUDE_DIR=$(dirname "$CLAUDE_BIN")
  TOOL_PATH="$NODE_ROOT/bin:$GO_ROOT/bin:$RUST_ROOT/bin:$BATS_ROOT/bin:$PARALLEL_DIR:$CLAUDE_DIR:$SC_DIR:/usr/local/bin:/usr/bin:/bin"
}

cmd_check() {
  tools
  local cv gv nv pv rv cav bv parv gitv bashv sv pnv pn
  cv=$("$CLAUDE_BIN" --version | cut -d' ' -f1); gv=$("$GO_ROOT/bin/go" version | cut -d' ' -f3)
  nv=$("$NODE_ROOT/bin/node" --version); pv=$(/usr/bin/python3 --version | cut -d' ' -f2)
  rv=$("$RUST_ROOT/bin/rustc" --version | cut -d' ' -f2); cav=$("$RUST_ROOT/bin/cargo" --version | cut -d' ' -f2)
  bv=$("$BATS_ROOT/bin/bats" --version | cut -d' ' -f2)
  parv=$("$PARALLEL_DIR/parallel" --will-cite --version | sed -n '1s/^GNU parallel //p')
  gitv=$(/usr/bin/git --version | cut -d' ' -f3)
  bashv=$(/usr/bin/bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]}"')
  sv=$("$SC_DIR/shellcheck" --version 2>/dev/null | sed -n 's/^version: //p')
  pn="$(deps_of N2)/pnpm/bin/pnpm"; pnv="(not prepared yet: deps of N2)"
  if [ -x "$pn" ]; then pnv=$(PATH="$NODE_ROOT/bin:$PATH" "$pn" --version); fi
  echo "date_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "os: $(uname -srm)"
  echo "claude_code: $cv"; echo "model: ${ANTHROPIC_MODEL:-}"; echo "maat_tag: ${MAAT_TAG:-}"
  echo "git: $gitv"; echo "bash: $bashv"; echo "python: $pv"; echo "node: $nv"; echo "go: $gv"
  echo "rustc: $rv"; echo "cargo: $cav"; echo "bats: $bv"; echo "parallel: $parv"; echo "pnpm: $pnv"
  echo "dash: $(command -v dash || true)"; echo "shellcheck: $sv"; echo "bwrap: $(bwrap --version 2>/dev/null || true)"
  [ "$cv" = "$WANT_CLAUDE" ] || die "check: Claude Code $cv, expected $WANT_CLAUDE"
  [ "${ANTHROPIC_MODEL:-}" = "$WANT_MODEL" ] || die "check: ANTHROPIC_MODEL ${ANTHROPIC_MODEL:-unset}, expected $WANT_MODEL"
  [ "${MAAT_TAG:-}" = "$WANT_MAAT" ] || die "check: MAAT_TAG ${MAAT_TAG:-unset}, expected $WANT_MAAT"
  [ "$gv" = "$WANT_GO" ] || die "check: go $gv, expected $WANT_GO"
  [ "$nv" = "$WANT_NODE" ] || die "check: node $nv, expected $WANT_NODE"
  [ "$pv" = "$WANT_PYTHON" ] || die "check: python $pv, expected $WANT_PYTHON"
  [ "$rv" = "$WANT_RUST" ] && [ "$cav" = "$WANT_RUST" ] || die "check: rustc $rv / cargo $cav, expected $WANT_RUST"
  [ "$bv" = "$WANT_BATS" ] || die "check: bats $bv, expected $WANT_BATS"
  [ "$parv" = "$WANT_PARALLEL" ] || die "check: parallel ${parv:-missing}, expected $WANT_PARALLEL"
  [ "$gitv" = "$WANT_GIT" ] || die "check: git $gitv, expected $WANT_GIT"
  [ "$bashv" = "$WANT_BASH" ] || die "check: bash $bashv, expected $WANT_BASH"
  [ ! -x "$pn" ] || [ "$pnv" = "$WANT_PNPM" ] || die "check: pnpm $pnv, expected $WANT_PNPM"
  [ "$sv" = "$WANT_SHELLCHECK" ] || die "check: shellcheck ${sv:-missing}, expected $WANT_SHELLCHECK"
  command -v dash >/dev/null || die "check: dash missing"
  command -v bwrap >/dev/null || die "check: bwrap (bubblewrap) missing"
  [ -d "${CLAUDE_CONFIG_DIR:-}" ] || die "check: CLAUDE_CONFIG_DIR missing"
  [ ! -e "$CLAUDE_CONFIG_DIR/CLAUDE.md" ] || die "check: the benchmark config dir must not have a CLAUDE.md"
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

cmd_schedule() { # 8 tasks x 3 runs x 2 sides, shuffled with the published seed
  local seed=${1:?seed}
  # shellcheck disable=SC2086
  python3 - "$seed" $TASKS > "$HERE/schedule.tsv" <<'PY'
import random, sys
rows = [(t, side, k) for t in sys.argv[2:] for side in ("maat", "baseline") for k in (1, 2, 3)]
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

# ---- the environment of a copy, prepared before the run (the agents do not install anything) ----------------------
# The task's own setup-env.sh <copy> <deps>, with the network open, outside the sandbox and with a clean environment:
# downloads go once into the task's dependency folder (shared by its 6 runs, read-only to them), what is private to a
# copy goes into the copy and is git-excluded (exclude.txt). A Cargo.lock of the task (the project tracks none) goes
# to the root of the copy, as the task's setup-env.sh and run.sh expect.
setup_env() { # setup_env <task> <copy>
  local dir deps t v px=()
  dir="$HERE/tasks/$(task_dir "$1")"; deps=$(deps_of "$1"); mkdir -p "$deps"
  [ ! -f "$dir/Cargo.lock" ] || cp "$dir/Cargo.lock" "$2/Cargo.lock"
  t=$(mktemp -d)
  for v in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do [ -z "${!v:-}" ] || px+=("$v=${!v}"); done
  env -i HOME="$HOME" USER="$(id -un)" LANG=C.UTF-8 TMPDIR="$t" PATH="$TOOL_PATH" ${px[@]+"${px[@]}"} \
    bash "$dir/setup-env.sh" "$2" "$deps" > "$2/.git/bench-setup-env.txt" 2>&1 \
    || { rm -rf "$t"; tail -5 "$2/.git/bench-setup-env.txt" >&2; die "setup-env.sh of $1 failed"; }
  rm -rf "$t"
  [ ! -f "$dir/Cargo.lock" ] || cmp -s "$dir/Cargo.lock" "$2/Cargo.lock" || die "the Cargo.lock of the copy is not the task's"
}
excludes() { # excludes <task> <copy>: the copy's .git/info/exclude, with the task's exclude.txt
  local f p; f="$HERE/tasks/$(task_dir "$1")/exclude.txt"
  printf '%s\n' .claude/ .venv/ node_modules/ target/ >> "$2/.git/info/exclude"
  [ -f "$f" ] || return 0
  while IFS= read -r p || [ -n "$p" ]; do
    p=${p%$'\r'}
    [ -z "$p" ] || grep -qxF -- "$p" "$2/.git/info/exclude" || printf '%s\n' "$p" >> "$2/.git/info/exclude"
  done < "$f"
}
env_packages() { # env_packages <task> <copy>: the versions installed in a copy
  local c=$2 any=""
  if [ -x "$c/.venv/bin/python" ]; then any=1; echo "## .venv"; "$c/.venv/bin/python" -m pip freeze --exclude-editable 2>&1; fi
  if [ -d "$c/node_modules/.pnpm" ]; then any=1; echo "## node_modules (pnpm)"
    local p; for p in "$c"/node_modules/.pnpm/*@*; do [ ! -d "$p" ] || basename "$p"; done
  elif [ -d "$c/node_modules" ]; then any=1; echo "## node_modules"; (cd "$c" && npm ls --all --parseable 2>/dev/null | sed "s|^$c/||"); fi
  if [ -f "$c/Cargo.lock" ]; then any=1; echo "## Cargo.lock"; sha256sum "$c/Cargo.lock" | sed "s|$c/||"; fi
  if [ -f "$c/go.mod" ]; then any=1; echo "## Go modules in the task's cache"
    local dl; dl="$(deps_of "$1")/gomod/cache/download"
    if [ -d "$dl" ]; then (cd "$dl" && find . -name '*.zip' | sed 's|^\./||; s|/@v/| |; s|\.zip$||' | LC_ALL=C sort)
    else echo "(none)"; fi; fi
  [ -n "$any" ] || echo "(nothing installed)"
}
# task_env <task>: the task's sandbox.env as NAME=value lines; $DEPS and $PATH expanded to their values in the sandbox
task_env() {
  local f deps line name val
  f="$HERE/tasks/$(task_dir "$1")/sandbox.env"; deps=$(deps_of "$1")
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case $line in ''|'#'*) continue ;; esac
    name=${line%%=*}; val=${line#*=}
    [[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [ "$name" != "$line" ] || die "sandbox.env of $1: bad line «$line»"
    val=${val//'${DEPS}'/$deps}; val=${val//'$DEPS'/$deps}
    val=${val//'${PATH}'/$TOOL_PATH}; val=${val//'$PATH'/$TOOL_PATH}
    case $val in *'$'*) die "sandbox.env of $1: only \$DEPS and \$PATH are expanded («$line»)" ;; esac
    printf '%s=%s\n' "$name" "$val"
  done < "$f"
}
# task_files_check <task> <out>: every file of the task's folder is the frozen one (SHA256SUMS), listed in <out>
task_files_check() {
  local dir sums f want got
  dir=$(task_dir "$1"); sums=$(sums_file)
  [ -f "$sums" ] || die "no $sums"
  while IFS= read -r f; do
    want=$(awk -v f="$f" '$2 == f { print $1 }' "$sums"); got=$(sha256sum "$HERE/$f" | cut -d' ' -f1)
    [ -n "$want" ] && [ "$got" = "$want" ] || die "$f ($got) is not the frozen one (${want:-not in $(basename "$sums")})"
    echo "$got  $f"
  done < <(cd "$HERE" && find "tasks/$dir" -type f | LC_ALL=C sort) > "$2"
  [ -s "$2" ] || die "no file in tasks/$dir"
}

cmd_prepare() {
  local id=${1:?run-id}; local task=${id%%-*}; local side; side=$(side_of "$id")
  tools
  read -r url sha spec _ <<<"$(task_row "$task")"
  local c="$BENCH_HOME/copies/$id"; [ ! -e "$c" ] || die "$c exists: a run is never repeated"
  local dir; dir=$(dirname "$spec")
  local tf; tf=$(mktemp); task_files_check "$task" "$tf"    # before anything is built
  local m; m=$(mirror "$url")
  git -C "$m" cat-file -e "$sha^{commit}" || die "commit $sha not found in $url"
  # Snapshot without history: no future commit (with the upstream fix) is reachable from the copy.
  mkdir -p "$c"; git -C "$m" archive --format=tar "$sha" | tar -x -C "$c"
  ( cd "$c" && git init -q -b main && git config core.autocrlf false && git config user.name bench \
      && git config user.email bench@example.invalid && git add -A \
      && GIT_AUTHOR_DATE=$BASE_DATE GIT_COMMITTER_DATE=$BASE_DATE git commit -q -m "benchmark base $task $sha" )
  mv "$tf" "$c/.git/bench-task-files.sha256"
  [ -z "$DRY" ] || echo "prepared with BENCH_DRY=1: never runnable" > "$c/.git/bench-dry"
  excludes "$task" "$c"
  setup_env "$task" "$c"
  env_packages "$task" "$c" > "$c/.git/bench-env-packages.txt"
  local name; name=$(basename "$spec")
  mkdir -p "$c/.claude/.ai-workflow"
  cp "$HERE/tasks/$spec" "$c/.claude/.ai-workflow/$name"
  # Same project settings on both sides: no web tools (the upstream fixes are public). The Maat side gets this deny
  # through these settings only (its driver has no --disallowedTools); the baseline also on its command line.
  printf '%s\n' '{ "permissions": { "deny": ["WebFetch", "WebSearch"] } }' > "$c/.claude/settings.json"
  if [ "$side" = maat ]; then
    : "${CLAUDE_CONFIG_DIR:?set CLAUDE_CONFIG_DIR}" "${MAAT_TAG:?set MAAT_TAG}"; export CLAUDE_CONFIG_DIR
    if [ -z "$DRY" ]; then
      ( cd "$c" && "$CLAUDE_BIN" plugin marketplace add "https://github.com/$GITHUB_REPO.git#$MAAT_TAG" --scope project >/dev/null \
          && "$CLAUDE_BIN" plugin install maat@maat --scope project >/dev/null )
    else
      echo "prepare: BENCH_DRY=1, the plugin is not installed (the plugin cache must already hold $MAAT_TAG)"
    fi
    cp "$HERE/tasks/$dir/maat.json" "$c/.claude/maat.json"
    # the task's format adapter, the whole folder (test output -> JUnit that Maat reads), outside the project's code
    if [ -d "$HERE/tasks/$dir/adapter" ]; then
      mkdir -p "$c/.claude/bench" && cp -R "$HERE/tasks/$dir/adapter/." "$c/.claude/bench/"
    fi
    local root v; root=$(plugin_root)
    v=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$root/.claude-plugin/plugin.json")
    [ "v$v" = "$MAAT_TAG" ] || die "installed Maat $v, expected $MAAT_TAG"
    plugin_verify
  fi
  # the frozen spec, as copied: same hash as SHA256SUMS
  local want got; want=$(awk -v f="tasks/$spec" '$2 == f { print $1 }' "$(sums_file)")
  got=$(sha256sum "$c/.claude/.ai-workflow/$name" | cut -d' ' -f1)
  [ -n "$want" ] && [ "$got" = "$want" ] || die "the spec in the copy ($got) is not the frozen one ($want)"
  echo "$got" > "$c/.git/bench-spec.sha256"
  # the prepared copy is clean: the environment and .claude/ are excluded, nothing else changed
  [ -z "$(git -C "$c" status --porcelain)" ] || die "the prepared copy is not clean: $(git -C "$c" status --porcelain | head -3)"
  ( cd "$c" && git rev-parse HEAD ) > "$c/.git/bench-base"
  echo "$c"
}

plugin_root() { ls -d "$CLAUDE_CONFIG_DIR"/plugins/cache/maat/maat/"${MAAT_TAG#v}" 2>/dev/null || die "Maat ${MAAT_TAG} not in the plugin cache"; }

# plugin_verify: the installed plugin holds exactly the files of MAAT_TAG in the public repository (also the source of
# the audit's «plugin text»), and the marketplace clone, readable by the runs, is at the tag
plugin_verify() {
  local root m t mk; root=$(plugin_root); m=$(mirror "https://github.com/$GITHUB_REPO.git")
  [ "$(git -C "$m" rev-parse "$MAAT_TAG^{commit}")" = "$WANT_MAAT_COMMIT" ] || die "$MAAT_TAG is not $WANT_MAAT_COMMIT"
  t=$(mktemp -d); git -C "$m" archive "$MAAT_TAG" plugins/maat | tar -x -C "$t"
  if ! diff -r --no-dereference -x .in_use -x .orphaned_at "$t/plugins/maat" "$root" > "$t/diff" 2>&1; then
    head -5 "$t/diff" >&2; rm -rf "$t"; die "the installed plugin differs from $MAAT_TAG"
  fi
  rm -rf "$t"
  mk="$CLAUDE_CONFIG_DIR/plugins/marketplaces/maat"
  [ ! -e "$mk/.git" ] || [ "$(git -C "$mk" rev-parse HEAD)" = "$WANT_MAAT_COMMIT" ] || die "the marketplace clone is not at $MAAT_TAG"
}

# ---- the sandbox -----------------------------------------------------------------------------------------------
# sbx <run|hidden> <run-id> <rw-dir…> -- <ro-dir…> --: fills SBX with the bwrap arguments and SBX_ENV with the
# variables it sets. Visible: the system (/usr, /etc, read-only), the tools (Node, Go, Rust, bats, parallel; for a run
# also Claude Code and shellcheck), the task's dependency folder (read-only), the given folders; a private /tmp, an
# empty $HOME, a new /proc and /dev. A run also sees the benchmark's configuration folder with its own session folders
# (CFG_PRIVATE_DIRS) and the installed plugins read-only; the hidden tests run with the network closed. Then the task's
# sandbox.env. The current working directory is the first rw folder (or the first ro one).
sbx() {
  local kind=$1 id=$2; shift 2
  local task=${id%%-*}; tools
  local rw=() ro=() d mode=rw
  for d in "$@"; do
    if [ "$d" = -- ]; then mode=ro; continue; fi
    if [ "$mode" = rw ]; then rw+=("$d"); else ro+=("$d"); fi
  done
  local deps rc path=$TOOL_PATH kv envs=() te
  deps=$(deps_of "$task")
  te=$(task_env "$task")
  while IFS= read -r kv; do
    [ -n "$kv" ] || continue
    if [ "${kv%%=*}" = PATH ]; then path=${kv#*=}; else envs+=("$kv"); fi
  done <<<"$te"
  SBX=(--die-with-parent --new-session --unshare-pid --unshare-ipc --unshare-uts --unshare-cgroup-try
       --ro-bind /usr /usr --ro-bind /etc /etc --ro-bind-try /sys /sys
       --symlink usr/bin /bin --symlink usr/sbin /sbin --symlink usr/lib /lib --symlink usr/lib64 /lib64
       --proc /proc --dev /dev --tmpfs /tmp --tmpfs "$HOME"
       --ro-bind "$NODE_ROOT" "$NODE_ROOT" --ro-bind "$GO_ROOT" "$GO_ROOT" --ro-bind "$RUST_ROOT" "$RUST_ROOT"
       --ro-bind "$BATS_ROOT" "$BATS_ROOT" --ro-bind "$PARALLEL_DIR" "$PARALLEL_DIR")
  if [ "$kind" = run ]; then
    local claude_real; claude_real=$(readlink -f "$CLAUDE_BIN")
    SBX+=(--ro-bind "$claude_real" "$claude_real" --ro-bind "$CLAUDE_DIR" "$CLAUDE_DIR")
    [ "$SC_DIR" = "$CLAUDE_DIR" ] || SBX+=(--ro-bind "$SC_DIR" "$SC_DIR")
  else
    SBX+=(--unshare-net)
  fi
  rc=$(readlink -f /etc/resolv.conf); case $rc in /etc/*) ;; *) SBX+=(--ro-bind-try "$rc" "$rc") ;; esac
  for d in ${rw[@]+"${rw[@]}"}; do SBX+=(--bind "$d" "$d"); done
  for d in ${ro[@]+"${ro[@]}"}; do SBX+=(--ro-bind "$d" "$d"); done
  [ ! -d "$deps" ] || SBX+=(--ro-bind "$deps" "$deps")
  SBX_ENV=(HOME="$HOME" USER="$(id -un)" LANG=C.UTF-8 TMPDIR=/tmp PATH="$path" DEPS="$deps"
           GOTOOLCHAIN=local GOCACHE=/tmp/go-cache GOPATH=/tmp/go GOPROXY=off GOFLAGS=-mod=mod
           npm_config_cache=/tmp/npm-cache npm_config_offline=true)
  if [ "$kind" = run ]; then
    : "${CLAUDE_CONFIG_DIR:?set CLAUDE_CONFIG_DIR}"
    [ ! -d "$CLAUDE_CONFIG_DIR/plugins" ] || SBX+=(--ro-bind "$CLAUDE_CONFIG_DIR/plugins" "$CLAUDE_CONFIG_DIR/plugins")
    local st="$BENCH_HOME/cfgstate/$id"
    for d in $CFG_PRIVATE_DIRS; do
      mkdir -p "$st/$d" "$CLAUDE_CONFIG_DIR/$d"; SBX+=(--bind "$st/$d" "$CLAUDE_CONFIG_DIR/$d")
    done
    touch "$st/history.jsonl" "$CLAUDE_CONFIG_DIR/history.jsonl"
    SBX+=(--bind "$st/history.jsonl" "$CLAUDE_CONFIG_DIR/history.jsonl")
    SBX_ENV+=(CLAUDE_BIN="$CLAUDE_BIN" CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-}"
              DISABLE_AUTOUPDATER=1)
  fi
  SBX_ENV+=(${envs[@]+"${envs[@]}"})
  SBX+=(--chdir "${rw[0]:-${ro[0]}}" --clearenv)
  for kv in "${SBX_ENV[@]}"; do SBX+=(--setenv "${kv%%=*}" "${kv#*=}"); done
}

cmd_sandbox_check() { # sandbox-check <run-id>: what the run must not see, tried from inside its sandbox
  local id=${1:?run-id}; local c="$BENCH_HOME/copies/$id" task=${id%%-*}
  [ -d "$c" ] || die "prepare $id first"
  sbx run "$id" "$c" "$CLAUDE_CONFIG_DIR" --
  local probe=("$BENCH_HOME/mirrors" "$BENCH_HOME/records" "$BENCH_HOME/hidden" "$BENCH_HOME/quota" "$BENCH_HOME/cfgstate"
               "${HIDDEN_DIR:-/nonexistent}" "$HERE" /mnt/c "$HOME/.ssh" "$HOME/.claude" "$HOME/bench3-prep" "$HOME/bench3-mirrors")
  local other t
  for other in "$BENCH_HOME"/copies/*; do                 # /mnt/c: the Windows drive of WSL
    if [ -d "$other" ] && [ "$other" != "$c" ]; then probe+=("$other"); break; fi
  done
  for t in $TASKS; do [ "$t" = "$task" ] || [ ! -d "$(deps_of "$t")" ] || probe+=("$(deps_of "$t")"); done
  local p bad=0
  for p in "${probe[@]}"; do
    if bwrap "${SBX[@]}" -- sh -c 'ls -A "$1" 2>/dev/null | head -1 | grep -q .' _ "$p"; then
      echo "sandbox-check: VISIBLE $p"; bad=1
    fi
  done
  # the session folders of the configuration are the run's own: nothing of another run is listed in them
  local inside own
  inside=$(bwrap "${SBX[@]}" -- sh -c 'cd "$CLAUDE_CONFIG_DIR" && ls -A projects sessions session-env file-history todos 2>/dev/null' | sort)
  # shellcheck disable=SC2012
  own=$(cd "$BENCH_HOME/cfgstate/$id" && ls -A projects sessions session-env file-history todos 2>/dev/null | sort)
  [ "$inside" = "$own" ] || { echo "sandbox-check: the configuration shows sessions of another run"; bad=1; }
  bwrap "${SBX[@]}" -- sh -c 'test -w . && git status --porcelain >/dev/null' || { echo "sandbox-check: the copy is not usable"; bad=1; }
  # the dependency folder: visible, never writable
  bwrap "${SBX[@]}" -- sh -c '[ ! -d "$DEPS" ] || { ls "$DEPS" >/dev/null && ! touch "$DEPS/.w" 2>/dev/null; }' \
    || { echo "sandbox-check: the task's dependency folder is writable or not readable"; bad=1; }
  local tv
  tv=$(bwrap "${SBX[@]}" -- sh -c 'printf "%s | %s | %s | %s | %s | %s" "$(go version)" "$(node --version)" "$(cargo --version)" \
         "$(bats --version)" "$(parallel --will-cite --version | sed -n 1p)" "$(python3 --version)"' 2>&1) \
    || { echo "sandbox-check: a tool does not run inside: $tv"; bad=1; }
  [ "$bad" -eq 0 ] || die "sandbox-check failed for $id"
  echo "sandbox-check: ok ($id: ${#probe[@]} paths not visible, own session folders, copy usable, deps read-only; $tv)"
}

cmd_sandbox_exec() {
  local id=${1:?run-id}; shift; [ "${1:-}" = -- ] && shift
  local c="$BENCH_HOME/copies/$id"; [ -d "$c" ] || die "prepare $id first"
  sbx run "$id" "$c" "$CLAUDE_CONFIG_DIR" --
  local root=""; [ "$(side_of "$id")" != maat ] || root=$(plugin_root)
  bwrap "${SBX[@]}" --setenv CLAUDE_PLUGIN_ROOT "$root" -- "$@"
}

cmd_run() {
  local id=${1:?run-id}; local task=${id%%-*}; local side; side=$(side_of "$id")
  [ -z "$DRY" ] || die "run is never made with BENCH_DRY"
  read -r url sha spec _ <<<"$(task_row "$task")"
  local c="$BENCH_HOME/copies/$id" r="$BENCH_HOME/records/$id" env
  [ -d "$c" ] || die "prepare $id first"; [ ! -e "$r" ] || die "$r exists: a run is never repeated"
  [ ! -e "$c/.git/bench-dry" ] || die "$c was prepared with BENCH_DRY: it is never run"
  env=$(cmd_check) || exit 2                    # exact versions, before the record exists
  [ "$side" != maat ] || plugin_verify          # the plugin's files against the tag, before each run
  mkdir -p "$r"; local name; name=$(basename "$spec")
  echo "$env" > "$r/environment.txt"
  [ ! -f "$BENCH_HOME/quota/$id-before.txt" ] || cp "$BENCH_HOME/quota/$id-before.txt" "$r/quota-before.txt"
  local t0 t1 rc=0
  sbx run "$id" "$c" "$CLAUDE_CONFIG_DIR" --
  printf '%s\n' "${SBX_ENV[@]}" > "$r/sandbox-env.txt"
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

cmd_dry_collect() { # dry-collect <run-id>: a record from a copy nobody ran (proof of collect, audit and hidden only)
  local id=${1:?run-id}; local task=${id%%-*}; local side; side=$(side_of "$id")
  [ -n "$DRY" ] || die "dry-collect only with BENCH_DRY=1"
  read -r _ _ spec _ <<<"$(task_row "$task")"
  local c="$BENCH_HOME/copies/$id" r="$BENCH_HOME/records/$id"
  [ -e "$c/.git/bench-dry" ] || die "$c was not prepared with BENCH_DRY"; [ ! -e "$r" ] || die "$r exists"
  mkdir -p "$r"; echo "DRY: no Claude session; the tree is whatever was put in the copy by hand" > "$r/DRY"
  { cmd_check 2>&1 || true; } > "$r/environment.txt"
  sbx run "$id" "$c" "$CLAUDE_CONFIG_DIR" --; printf '%s\n' "${SBX_ENV[@]}" > "$r/sandbox-env.txt"
  date -u +%Y-%m-%dT%H:%M:%SZ | tee "$r/started_utc" > "$r/ended_utc"; echo dry > "$r/exit_code"; echo 0 > "$r/wall_clock_s"
  if [ "$side" = maat ]; then : > "$r/driver-stdout.txt"; else : > "$r/transcript.jsonl"; : > "$r/stderr.txt"; fi
  collect "$id" "$side" "$c" "$r" "$(basename "$spec")"
}

collect() { # the raw material of the record; the record itself is filled in with run-record.md
  local id=$1 side=$2 c=$3 r=$4 name=$5 base root=""
  base=$(cat "$c/.git/bench-base")
  ( cd "$c" && git add -A -N . && git diff --binary "$base" -- . ':(exclude).claude' ) > "$r/final.diff"
  sha256sum "$r/final.diff" | cut -d' ' -f1 > "$r/final.diff.sha256"
  cp "$c/.git/bench-spec.sha256" "$r/spec-in-copy.sha256"
  sha256sum "$c/.claude/.ai-workflow/$name" | cut -d' ' -f1 > "$r/spec-after-run.sha256"
  cp "$c/.git/bench-env-packages.txt" "$r/env-packages.txt"
  cp "$c/.git/bench-task-files.sha256" "$r/task-files.sha256"
  cp "$c/.git/bench-setup-env.txt" "$r/setup-env.txt"
  local logs=()
  if [ "$side" = maat ]; then
    root=$(plugin_root)
    cp "$c/.claude/.ai-workflow/$name" "$r/spec-with-plan-and-review.md"   # Maat writes plan, review, evidence here
    cp -r "$c/.claude/.ai-workflow/${name%.md}.run" "$r/run-dir" 2>/dev/null || true
    # shellcheck source=/dev/null
    ( cd "$c" && . "$root/scripts/python.sh" && "$FIC_PY" "$root/scripts/phase-usage.py" --summary ".claude/.ai-workflow/${name%.md}.run" ) \
      > "$r/cost-summary.txt" 2>&1 || true
    grep -a 'Driver result: ' "$r/driver-stdout.txt" | tail -1 > "$r/outcome.txt" || true
    { cat "$r/run-dir/taglia.txt" 2>/dev/null || echo "(no taglia.txt: size not recorded)"; } > "$r/size.txt"   # the size chosen
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
    print("<!-- usage_from_result=%s -->" % json.dumps(last.get("usage") or {}, sort_keys=True))
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
  audit "$id" "$c" "$r" "$root" "${logs[@]}"
  model_check "$side" "$r"
  quota_check "$r" "${logs[@]}"
  echo "collected: $r"
}

# AUDIT: any trace of a path outside the run's copy (another copy, other tasks' dependencies, the mirrors, the records,
# the hidden tests, the private folders, /mnt) in what the run left. A hit is recorded and published; the run is marked
# contaminated (never repeated). Protocol v3, §6: a hit is «plugin text», recorded but not contamination, when the
# matched text with up to 40 characters on each side on its line (after decoding the JSON string that holds it) occurs
# verbatim in a file of the installed plugin (checked against the tag by plugin_verify). The baseline has no plugin.
audit() { # audit <id> <copy> <record> <plugin root or ""> <files or folders…>
  local id=$1 c=$2 r=$3 root=$4; shift 4
  python3 - "$BENCH_HOME" "$c" "${HIDDEN_DIR:-/nonexistent}" "$HERE" "$root" "$@" > "$r/audit.txt" <<'PY'
import json, os, re, sys
bench, copy, hidden, here, root = sys.argv[1:6]
own = os.path.basename(copy); task = own.split("-")[0]
pats = [re.escape(bench) + r"/(?:mirrors|records|hidden|quota|cfgstate|copies/(?!%s(?:/|\b))|deps/(?!%s(?:/|\b)))"
        % (re.escape(own), re.escape(task)),
        re.escape(hidden), r"benchmark-nascosti", r"docs/piani", r"v3-prep", r"bench3-(?:prep|mirrors|work)",
        r"riferimenti/", re.escape(here), r"(?<![\w.])/mnt/[a-z]/"]
rx = re.compile("|".join("(?:%s)" % p for p in pats))
corpus = []
if root:
    for d, _, fs in os.walk(root):
        for f in fs:
            try:
                with open(os.path.join(d, f), encoding="utf-8", errors="replace") as fh:
                    corpus.append(fh.read())
            except OSError:
                pass
def plugin_text(text, m):
    ctx = text[max(0, m.start() - 40):m.end() + 40]
    return bool(corpus) and any(ctx in t for t in corpus)
def strings(o):
    if isinstance(o, str):
        yield o
    elif isinstance(o, dict):
        for k, v in o.items():
            yield k
            yield from strings(v)
    elif isinstance(o, list):
        for v in o:
            yield from strings(v)
hits = []   # (kind, where, match)
def scan(f):
    rel = os.path.relpath(f, os.path.dirname(copy))
    try:
        fh = open(f, encoding="utf-8", errors="replace")
    except OSError:
        return
    with fh:
        for n, line in enumerate(fh, 1):
            raw = [m.group(0) for m in rx.finditer(line)]
            if not raw:
                continue
            found = []
            try:
                texts = [l for s in strings(json.loads(line)) for l in s.split("\n")]
            except ValueError:
                texts = [line.rstrip("\n")]
            for t in texts:
                for m in rx.finditer(t):
                    found.append(m.group(0))
                    hits.append(("plugin-text" if plugin_text(t, m) else "hit", "%s:%d" % (rel, n), m.group(0)))
            for g in raw:              # a match of the raw line that no decoded string holds counts as it is
                if g in found:
                    found.remove(g)
                else:
                    hits.append(("hit", "%s:%d" % (rel, n), g))
for p in sys.argv[6:]:
    if os.path.isdir(p):
        for d, _, fs in os.walk(p):
            for f in sorted(fs):
                scan(os.path.join(d, f))
    elif os.path.isfile(p):
        scan(p)
bad = [h for h in hits if h[0] == "hit"]
if not hits:
    print("audit: clean")
elif not bad:
    print("audit: clean (%d hits, all plugin text: not contamination)" % len(hits))
else:
    print("audit: CONTAMINATED (%d hits, %d of them plugin text)" % (len(bad), len(hits) - len(bad)))
for kind, where, g in hits[:200]:
    print("%s %s: %s" % (kind, where, g.replace(bench, "$BENCH_HOME")))
PY
}

model_check() { # the model of every session, from its init event, against ANTHROPIC_MODEL
  local side=$1 r=$2 files=()
  if [ "$side" = maat ]; then mapfile -t files < <(find "$r/run-dir" -name '*.jsonl' 2>/dev/null | sort); else files=("$r/transcript.jsonl"); fi
  python3 - "${ANTHROPIC_MODEL:-}" ${files[@]+"${files[@]}"} > "$r/model-check.txt" <<'PY'
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

cmd_hidden() { # the hidden tests, right after the run: fixed in advance, no judgement. Detail stays private.
  local retry="" note=""
  if [ "${1:-}" = --retry-infra ]; then retry=1; shift; note=${2:-}; [ -n "$note" ] || die "--retry-infra needs a note"; fi
  local id=${1:?run-id}; local task=${id%%-*}; local total; total=$(task_total "$task")
  local c="$BENCH_HOME/copies/$id" r="$BENCH_HOME/records/$id" h="$BENCH_HOME/hidden/$id"
  : "${HIDDEN_DIR:?set HIDDEN_DIR}"
  [ -f "$r/final.diff" ] || die "run $id first"
  if [ -f "$HIDDEN_DIR/SHA256SUMS" ]; then
    [ "$(sha256sum "$HIDDEN_DIR/SHA256SUMS" | cut -d' ' -f1)" = "$HIDDEN_SUMS_SHA256" ] \
      || die "the SHA256SUMS of the hidden tests is not the frozen one"
    ( cd "$HIDDEN_DIR" && sha256sum -c --quiet SHA256SUMS ) || die "the hidden tests differ from their SHA256SUMS"
  elif [ -n "$DRY" ] && [ -e "$r/DRY" ]; then
    echo "DRY: the hidden tests have no SHA256SUMS yet: not checked" >> "$r/notes.txt"
  else die "no $HIDDEN_DIR/SHA256SUMS"; fi
  if [ -n "$retry" ]; then
    grep -q '^hidden: infra-error' "$r/hidden_tests.txt" 2>/dev/null || die "a retry only follows an infrastructure error"
    [ ! -e "$r/hidden_tests.infra-1.txt" ] || die "the one retry was already used"
    mv "$r/hidden_tests.txt" "$r/hidden_tests.infra-1.txt"; mv "$h" "$h.infra-1"
    printf 'hidden tests rerun once after an infrastructure error: %s\n' "$note" >> "$r/notes.txt"
  fi
  [ ! -e "$h" ] || die "$h exists: hidden tests run once per run"
  [ ! -e "$r/hidden_tests.txt" ] || die "$r/hidden_tests.txt exists"
  mkdir -p "$h"
  sbx hidden "$id" "$h" -- "$c" "$HIDDEN_DIR" --
  local line rc=0
  line=$(timeout -k 30 "$HIDDEN_CAP_S" bwrap "${SBX[@]}" -- \
           bash "$HIDDEN_DIR/$(task_dir "$task")/run.sh" "$c" "$h/out" 2>"$h/stderr.txt" | tail -1) || rc=$?
  if [[ $line =~ ^hidden:\ infra-error ]]; then :
  elif [[ $line =~ ^hidden:\ [0-9]+/([0-9]+)$ ]]; then
    [ "${BASH_REMATCH[1]}" = "$total" ] || line="hidden: infra-error (the runner's total is ${BASH_REMATCH[1]}, the task's is $total)"
  elif [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then line="hidden: 0/$total (timeout)"
  else line="hidden: 0/$total (no score)"; fi
  echo "$line" > "$r/hidden_tests.txt"    # published: the score only, never the tests or their output
  echo "$id $line"
  case "$line" in "hidden: infra-error"*)
    [ -n "$retry" ] && { echo "second infrastructure error: recorded as it is (no score)" >> "$r/notes.txt"; return 0; }
    echo "run-bench: infrastructure error; fix it, then once: run-bench.sh hidden --retry-infra $id \"<note>\"" >&2; return 3 ;;
  esac
}

# ---- the usage of the subscription (protocol v3, §7) -------------------------------------------------------------
quota_read() { # prints «<five-hour percent> <weekly percent> <source>»
  if [ -n "${QUOTA_CMD:-}" ]; then
    bash -c "$QUOTA_CMD" | python3 -c '
import json, sys
d = json.load(sys.stdin)
def pct(kind, key):
    for l in d.get("limits") or []:
        if l.get("kind") == kind and l.get("percent") is not None:
            return float(l["percent"])
    v = (d.get(key) or {}).get("utilization")
    return None if v is None else float(v)
s, w = pct("session", "five_hour"), pct("weekly_all", "seven_day")
if s is None or w is None:
    sys.exit("run-bench: the usage is not readable from QUOTA_CMD")
print("%g %g QUOTA_CMD" % (s, w))' || die "QUOTA_CMD gave no usage"
  else
    [ -r /dev/tty ] || die "set QUOTA_CMD, or run group from a terminal: the usage is checked before each run"
    local s w
    read -r -p "usage of the five-hour window, percent: " s < /dev/tty
    read -r -p "usage of the weekly window, percent: " w < /dev/tty
    [[ $s =~ ^[0-9]+([.][0-9]+)?$ && $w =~ ^[0-9]+([.][0-9]+)?$ ]] || die "two numbers"
    echo "$s $w operator"
  fi
}
over() { awk -v a="$1" -v m="$QUOTA_MAX" 'BEGIN { exit !(a > m) }'; }
# quota_gate <run-id> <order> <first of the group: 1|0>: 0 = the run may start; 1 = it waits (the group is split)
quota_gate() {
  local q s w src now; q=$(quota_read) || exit 2; read -r s w src <<<"$q"; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  [[ $s =~ ^[0-9]+([.][0-9]+)?$ && $w =~ ^[0-9]+([.][0-9]+)?$ ]] || die "usage not read («$q»)"
  printf '%s order %s %s: five-hour %s%%, weekly %s%% (%s)\n' "$now" "$2" "$1" "$s" "$w" "$src" >> "$BENCH_HOME/quota/gates.log"
  printf 'checked %s before the run: five-hour window %s%%, weekly window %s%% (%s)\n' "$now" "$s" "$w" "$src" > "$BENCH_HOME/quota/$1-before.txt"
  QUOTA_SEEN="five-hour $s%, weekly $w%"
  if [ "$3" = 1 ] && over "$w"; then echo "run-bench: weekly window at $w% (over $QUOTA_MAX%): the group waits for the weekly reset"; return 1; fi
  if over "$s"; then echo "run-bench: five-hour window at $s% (over $QUOTA_MAX%): the next run waits for the reset"; return 1; fi
}

cmd_group() { # one group: at most MAX_GROUP consecutive rows of schedule.tsv, one run at a time
  local first=${1:?first order} last=${2:?last order}
  [ -z "$DRY" ] || die "group is never run with BENCH_DRY"
  [ -f "$HERE/schedule.tsv" ] || die "run schedule first"
  : "${HIDDEN_DIR:?set HIDDEN_DIR}"
  [ "$last" -ge "$first" ] && [ $((last - first + 1)) -le "$MAX_GROUP" ] || die "a group has 1 to $MAX_GROUP runs"
  local rows; rows=$(awk -F'\t' -v a="$first" -v b="$last" 'NR > 1 && $1 >= a && $1 <= b { print $1, $2 }' "$HERE/schedule.tsv")
  [ -n "$rows" ] || die "no row $first..$last in schedule.tsv"
  local log="$BENCH_HOME/records/groups.txt" order id is_first=1
  printf '%s group %s-%s: start\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$first" "$last" >> "$log"
  while read -r order id <&3; do               # fd 3: the runs never read the list of the group
    if ! quota_gate "$id" "$order" "$is_first"; then
      printf '%s group %s-%s: split before order %s (%s); resume after the reset with: run-bench.sh group %s %s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$first" "$last" "$order" "$QUOTA_SEEN" "$order" "$last" | tee -a "$log"
      return 0
    fi
    is_first=0
    cmd_check > /dev/null
    cmd_prepare "$id" > /dev/null
    cmd_sandbox_check "$id"
    cmd_run "$id"
    cmd_hidden "$id" || true      # an infrastructure error stops nothing: its one retry is made by hand
  done 3<<<"$rows"
  printf '%s group %s-%s: end\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$first" "$last" >> "$log"
}

case "${1:-}" in
  check) cmd_check ;;
  seed) shift; cmd_seed "$@" ;;
  schedule) shift; cmd_schedule "$@" ;;
  prepare) shift; cmd_prepare "$@" ;;
  sandbox-check) shift; cmd_sandbox_check "$@" ;;
  sandbox-exec) shift; cmd_sandbox_exec "$@" ;;
  run) shift; cmd_run "$@" ;;
  dry-collect) shift; cmd_dry_collect "$@" ;;
  hidden) shift; cmd_hidden "$@" ;;
  group) shift; cmd_group "$@" ;;
  *) sed -n 2,43p "$0"; exit 2 ;;
esac
