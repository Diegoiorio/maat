# Maat benchmark, version 3

**Status: frozen on 2026-11-10; no run made yet.**

This folder applies [`../BENCHMARK-PROTOCOL-v3.md`](../BENCHMARK-PROTOCOL-v3.md).
[`QUALIFICATION.md`](QUALIFICATION.md) fixes the criteria, the pools of candidates and the procedure of the draw.
[`SHA256SUMS`](SHA256SUMS) holds the checksums of everything frozen:
- the protocol, the qualification file and the draw;
- the run script [`run-bench.sh`](run-bench.sh) and the baseline prompt [`baseline-prompt.txt`](baseline-prompt.txt);
- every file of the 8 task folders under [`tasks/`](tasks/).

The specs, hidden tests and format adapters were written after the draw, for the drawn tasks only (protocol, §3, item 5,
and §8). No Claude session has been run on any task.

## The draw

The whole output, with every step, is [`draw.txt`](draw.txt); `python3 draw.py <commit>` gives the same bytes.

- **Qualification commit:** `890c1479f447ba25fe71b1bb389741a9d1bcf500`, public on `main` since **2026-11-09T11:13:37Z**
  (the merge of [pull request #11](https://github.com/Diegoiorio/maat/pull/11), which is also the committer date), about
  one hour before the round below.
- **Seed:** drand «quicknet» round `33807685`, of 2026-11-09T12:13:39Z. The first attempt (`k=0`) met the variety rule.

| Group | Task | Repository | Language, kind | Folder |
|---|---|---|---|---|
| Hard | N3 | labstack/echo | Go, bug fix | [`N3-echo-body-limit`](tasks/N3-echo-body-limit/) |
| Hard | N11 | tox-dev/tox | Python, bug fix | [`N11-tox-set-env-lazy`](tasks/N11-tox-set-env-lazy/) |
| Hard | N2 | h3js/h3 | TypeScript, compatibility | [`N2-h3-pathname-decoding`](tasks/N2-h3-pathname-decoding/) |
| Hard | N12 | alecthomas/kong | Go, new feature | [`N12-kong-lastwins`](tasks/N12-kong-lastwins/) |
| Hard | N9 | pyenv/pyenv | shell, new feature | [`N9-pyenv-binary-install`](tasks/N9-pyenv-binary-install/) |
| Hard | N7 | tafia/quick-xml | Rust, bug fix | [`N7-quick-xml-depth-limit`](tasks/N7-quick-xml-depth-limit/) |
| Easy | E1 | BurntSushi/toml | Go, bug fix | [`E1-toml-max-depth`](tasks/E1-toml-max-depth/) |
| Easy | E3 | BurntSushi/jiff | Rust, bug fix | [`E3-jiff-span-overflow`](tasks/E3-jiff-span-overflow/) |

Four of the six hard tasks (N3, N7, N11, N12) are among those the qualification file marks close to the line: if they
turn out easy they stay, marked «not discriminating». **No task was replaced:** all eight passed the checks made before
the freeze (C8–C10, D2, D3, D5).

## What was checked before the freeze

For each task, on a copy of the starting commit prepared as the runs will prepare it, inside the sandbox, with the
network closed:

- **C3 / C7:** the project's suite runs twice with the same result, and the copy stays clean.
- **C8:** the hidden tests have a fixed total and use only the public API.
- **C9:** 20 runs of the hidden tests on the upstream fix and 20 on the start, with the same score in every run.
- **C10:** with Maat `v1.7.0`, the test gate reads a red test as red on its assertion, the same test green as green, and a
  missing report as blocked; `plan-check.sh taglia` runs.

| Task | Hidden total | Upstream fix | Start | Failures declared at the start (§4a) |
|---|---|---|---|---|
| N3 | 104 | 104 | 51 | gofmt errors already in 2 files |
| N11 | 99 | 99 | 57 | 1 test that needs the network |
| N2 | 234 | 234 | 149 | 5: 1 that needs a real client IP, 4 `stream` tests that fail at times (4 runs in 20 on a quiet machine) |
| N12 | 83 | 83 | 13 | none |
| N9 | 62 | 62 | 9 | none |
| N7 | 63 | 63 | 9 | none |
| E1 | 92 | 92 | 20 | none |
| E3 | 29 | 29 | 9 | none |

The declared failures are named in each task's spec, in the same words for both sides, and excluded from every count.
The score of the start is not 0 by design: many hidden tests pin behaviour that must not change.

The whole procedure of `run-bench.sh` (prepare, sandbox check, hidden tests, audit) was also run on all eight tasks,
without any Claude session, with the upstream fix applied in place of a run. It gave the same scores.

**Specs read by a second reader** (protocol, §2): an independent reader, who had not written them, read all eight specs
against the upstream fixes and the hidden tests. They checked that each spec names no internal design (D5) and that a
different correct solution would pass. They found:
- one hidden check in N9 stricter than its spec; it now accepts both outcomes the spec allows, and an alternative
  implementation was run against it;
- wording to tighten in the specs of N11, N7, N2, E1 and E3.

All of these were fixed before this commit. The **audit** with the plugin-text rule (§6) was checked on the published
records T3-maat-2 and T5-maat-2 (plugin text only, clean) and on a log with a real outside path (contaminated).

## What is compared

- **Maat side:** Maat `v1.7.0` (commit `752ff92`), installed and started as in version 2:
  - the plugin at project scope;
  - the task's frozen `.claude/maat.json` and, where the task has one, its format adapter;
  - the full cycle started by its driver, nobody answering.
- **Baseline side:** one Claude Code session in print mode with the fixed prompt
  [`baseline-prompt.txt`](baseline-prompt.txt), in a copy without Maat. It is the prompt of version 2, with the tools of
  the new environment named.
- **The same on both sides:**
  - **Claude Code `2.1.318`**, the version current at the freeze, pinned from now on, auto-update disabled;
  - model **`claude-opus-5-5`**;
  - a configuration folder used only for the benchmark;
  - Linux (Ubuntu 24.04 on WSL2) and bubblewrap isolation;
  - no web tools, the same prepared environment, one run at a time, the 4-hour cap.
- **Toolchains:** Python 3.12.3, Go 1.27.3, Node 22.22.2, Rust 1.99.1, GNU `parallel` 20261022, bats 1.14.0, git 2.43.0,
  bash 5.2.21; pnpm 11.15.1 only to prepare N2. `run-bench.sh check` refuses any other version.
- **Hidden tests:** private until the end, run with the network closed. Their checksums are frozen: the `SHA256SUMS` of
  the private folder has sha256 `8e3674c1262e81d49d9d79fa2f6d901c4d3f0374265bb0ebc5915d0d3b953e81`, which
  `run-bench.sh` checks before every hidden run. The tests are published with the results.

## Changes from version 2 in how a run is isolated

- **Each run has its own session folders** inside the benchmark's configuration folder (`projects`, `sessions`,
  `file-history` and the like). In version 2 every run could read the transcripts of the earlier runs there, including
  those of the other side on the same task. Nothing shows it happened, but it was possible.
- **Hidden tests run with the network closed**, as in the checks above.
- **The audit's plugin-text rule** (§6) is a change in favour of the Maat side, as the protocol says.

## Known limits

- **The name of N11's folder** contains «lazy», which hints at the approach of the upstream fix. It was already public in
  the draw, so it was kept. The name is the same for both sides, but the Maat side reads it more often than the baseline, in
  its plan and its review.
- **E3:** the jiff repository has an `AI_POLICY.md` that says autonomous agents may not contribute. Both sides read the same
  file.
- **N3:** some of echo's tests are sensitive to timing. They passed in every run on a quiet machine, so they are not
  declared. On a loaded machine they may fail during a run, so runs go one at a time.

## Calendar

- **Order of the runs:** shuffled with a second public seed, the first drand «quicknet» round one hour after this freeze
  commit (`run-bench.sh seed <commit>` then `schedule <seed>`). The order is published before the first run.
- **Groups** of at most 4 runs. The usage is checked before each run. The first group is run on its own, to measure the real cost
  before the rest are scheduled. It is still the first 4 rows of the shuffled order, so no run is chosen by hand.
- **End date:** the runs are not finished after **2027-02-10**, 3 months after this commit, whatever the reason (protocol, §5).
  A task not run by then is reported as not run.

## Results

None: no run made.
