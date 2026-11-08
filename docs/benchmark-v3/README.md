# Maat benchmark, version 3 — candidates and draw

**Status: draft, not frozen, no run made.** This folder will apply [`../BENCHMARK-PROTOCOL-v3.md`](../BENCHMARK-PROTOCOL-v3.md)
(version 3, also a draft). It lists the candidate tasks with each criterion checked, and the procedure that will draw
the tasks. Nothing here is pre-registered yet; no spec and no hidden test exists, because they are written only for
the tasks that will be drawn (protocol, §3, item 5). No Claude session has been run on any candidate.

## What is compared

- **Maat side:** Maat **1.7.0** (release tag `v1.7.0`, not released at the time of this draft), installed and
  started as in version 2: the plugin at project scope, the task's frozen `.claude/maat.json`, the full cycle started
  by its driver, nobody answering.
- **Baseline side:** one Claude Code session in print mode with a fixed prompt, in a copy without Maat (the prompt of
  version 2, with the new tools of the environment named).
- **The same on both sides:** one Claude Code binary (version to be fixed at the freeze; version 2 used 2.1.318),
  model **`claude-opus-5-5`**, a configuration folder used only for the benchmark, Linux (Ubuntu 24.04 on WSL2),
  bubblewrap isolation, no web tools, the same prepared environment, one run at a time, the 4-hour cap.
- **Toolchains** (from the feasibility check below): Python 3.12.3, Go 1.27.3, Node 20.20.2 and Node 22.22.2, Rust
  1.99.1 (or 1.98 if a clap task were drawn: its UI tests run only on 1.98), GNU `parallel` 20261022, bats 1.14.0,
  git 2.43.0, bash 5.2.21.

## Criteria

General requirements; a candidate missing one is rejected:

| # | Requirement | How it is checked before any run |
|---|---|---|
| C1 | A real open-source repository with a permissive license (MIT, BSD, Apache-2.0, ISC) | the license file at the starting commit |
| C2 | A maintained project | commits and merged pull requests in the last 3 months |
| C3 | A test suite that runs (or, for at most one task, no tests, declared) | run on a prepared copy, offline |
| C4 | A real upstream change: an issue or pull request that describes it and fixes it | link, merge commit |
| C5 | Starting commit = parent of the commit that brings the upstream change | `git rev-parse <merge>^` on the mirror |
| C6 | The fix was not public before the model's training data (`claude-opus-5-5`: June 2026) | dates of the pull request and of the issue; a search of the project's issues and pull requests for earlier reports or patches; what was found is written |
| C7 | Runs offline in the bubblewrap sandbox, with pinned toolchains | environment prepared before the run, then the project's suite with the network closed |
| C8 | Hidden tests can be written with a fixed total, with no leak | test → requirement map; nothing in the working copy to copy them from |
| C9 | Stable hidden tests | 20 runs on the reference solution, all full; 20 on the starting commit, always the same score |
| C10 | Maat can work on it with no known tool defect | `gates.sh` and `plan-check.sh rossi` on a prepared copy, new folders creatable |

Hard tasks must also meet D1–D5 (protocol, §1–2). C8–C10, D2, D3 and D5 depend on the spec, the hidden tests and
Maat 1.7.0: they are checked after the draw, on the drawn tasks only. D1 counts source files only: tests, docs,
changelogs, lock files, version numbers and build thresholds are excluded.

## Candidates

Checked on 2026-11-08: the repositories cloned, the merge commits and their parents read on the clones, the dates
from GitHub's public API, and each suite run offline on a history-less copy of the starting commit (network closed
by bubblewrap). «Upstream fix» counts source lines only.

| Id | Repository (license) | Upstream change | Starting commit (parent of merge) | Upstream fix (source) | Suite offline | Qualifies |
|---|---|---|---|---|---|---|
| H1 | [pallets/click](https://github.com/pallets/click) (BSD-3-Clause) | PR [#3866](https://github.com/pallets/click/pull/3866), 2026-09-11 → 09-23, merge `06b2a678` | `3cbaa76b6014be7427d1ab06b4af40f01e7c278e` | 1 file, +90/−4 | pytest, 2099 passed, 6.8 s | **no** (D1) |
| H2 | [urfave/cli](https://github.com/urfave/cli) (MIT) | PR [#2503](https://github.com/urfave/cli/pull/2503), 2026-10-25 (same day), merge `89ad1167` | `7cf94f0e50afd1e987b28e1b0da61a30c299809e` | 3 files, +48/−13 | `go test`, ok, 9.9 s | **doubtful** (D4) |
| H3 | [tj/commander.js](https://github.com/tj/commander.js) (MIT) | PR [#2577](https://github.com/tj/commander.js/pull/2577), 2026-08-05 → 09-28, issue [#2530](https://github.com/tj/commander.js/issues/2530) 2026-06-17, merge `6dee9e46` (branch `release/16.x`) | `b5cbf2b4da411a7725d696d7473ebdea9de876e9` | 1 file, +9/−2 | `node --test`, 1429 tests, 3.5–9.8 s (1 of 7 runs: 3 failures) | **no** (D1) |
| H4 | [pypa/packaging](https://github.com/pypa/packaging) (Apache-2.0 or BSD-2-Clause) | PR [#1473](https://github.com/pypa/packaging/pull/1473), issue [#1472](https://github.com/pypa/packaging/issues/1472), 2026-10-26 → 10-29, merge `78d8673d` | `b635dc5e60d6fb8020416c6bab9421964bfa342a` | 1 file, +111/−8 | pytest, 63,356 passed, 57 s | **no** (D1) |
| H5 | [python-poetry/tomlkit](https://github.com/python-poetry/tomlkit) (MIT) | PRs [#663](https://github.com/python-poetry/tomlkit/pull/663), [#699](https://github.com/python-poetry/tomlkit/pull/699), [#677](https://github.com/python-poetry/tomlkit/pull/677), 2026-10-15 → 11-06 | `85d391e1ba90fcf1fd15f6f14fecc774c1e500eb` | 2 files, 25 lines in all | pytest, 1249 passed, 2.2 s | **no** (D1, C5) |
| H6 | [ljharb/qs](https://github.com/ljharb/qs) (BSD-3-Clause) | [#636](https://github.com/ljharb/qs/pull/636), [#638](https://github.com/ljharb/qs/pull/638) (+ [#639](https://github.com/ljharb/qs/pull/639)), issue [#633](https://github.com/ljharb/qs/issues/633), 2026-10-21 → 10-28 | `05a875552a31829825c3ebf8899f280011aa06be` | 2 files, ~10 lines | tape, 1661 assertions, 1.3 s; eslint clean | **no** (D1) |
| H7 | [bats-core/bats-core](https://github.com/bats-core/bats-core) (MIT) | PR [#1259](https://github.com/bats-core/bats-core/pull/1259), 2026-09-18 → 09-20, merge `790dd0e4` | `4226b7147456be26227bd09ad60505fbada0f7d1` | 1 file, +12/−59 | bats, 490 tests (3 skipped), 120–138 s | **no** (D1) |
| H8 | [clap-rs/clap](https://github.com/clap-rs/clap) (MIT or Apache-2.0) | PR [#6521](https://github.com/clap-rs/clap/pull/6521), 2026-09-10 → 09-14, merge `7b2ad34c` | `4380302f04d201aec21b67d2ca0f4d5cb5c01897` | 5 files, +110/−36 | `cargo test`, all passed, build 34 s + 36 s | **no** (C6) |
| E1 | [BurntSushi/toml](https://github.com/BurntSushi/toml) (MIT) | PR [#514](https://github.com/BurntSushi/toml/pull/514), issue [#497](https://github.com/BurntSushi/toml/issues/497) 2026-07-16, merged 2026-08-16, merge `6a671b23` | `eb8b9987e23e6f5aff69fb1a1d0b113840c0964e` | 2 files, +19/−12 | `go test`, ok, 1.4 s | **yes** (C2 at the limit) |
| E2 | [tj/git-extras](https://github.com/tj/git-extras) (MIT) | PR [#1275](https://github.com/tj/git-extras/pull/1275), 2026-09-16 → 09-20, request [#1199](https://github.com/tj/git-extras/issues/1199) 2025-03-18, merge `55eff9cd` | `7e01ed30d0a30a6751af4df9f32fb062671f3dab` | 2 files, +17/−5 (plus man pages) | bats, 76 tests, 7.3 s, 6 failing in WSL | **yes** (C3 note) |
| E3 (reserve) | [BurntSushi/jiff](https://github.com/BurntSushi/jiff) (MIT or Unlicense) | PR [#662](https://github.com/BurntSushi/jiff/pull/662), 2026-10-15 → 10-31, merge `840b8698` | `bc41185bf7e5dbdc9f877fa21c7f3fd7318d7a48` | 3 files, +84/−3 | `cargo test -p jiff`, all passed, build 53 s + 81 s | **yes** |

All candidates pass C1 (license file at the starting commit), C2 (merged changes in the last 3 months; E1 only
just), C4 and C5 (the merge commit is on the project's main line and its first parent is the starting commit; H3's is
on the `release/16.x` line). C8–C10, D2, D3 and D5 are not checked yet (after the draw).

### Notes per candidate

- **H1 click** — deprecate parameter names that are not Python identifiers, are keywords or break the future rules.
  The fix is one source file (`+90/−4`); the 8 files and +877 of the pull request are tests, docs and the version
  bump, so **D1 fails**. C6: the «#3827» of the first list is an open alternative pull request (2026-09-01), not an
  issue; older related issues exist (#2768, 2024: a non-identifier name gives `None`; #763, 2017: collisions with
  keywords), the deprecation does not. Kind: compatibility change.
- **H2 urfave/cli** — flags read through `AllowExtFlags` are invisible to `IsSet`, `NumFlags`, `LocalFlagNames` and
  `FlagNames`. Three source files, 61 lines: D1 passes on the file count, at its minimum. D4 is doubtful: a small
  diff, opened and merged in 3.5 hours with no review comment (the pull request has 5 separate fixes of Go flags).
  C6: issue #2225 and pull request #2227 (both 2025-11-21, the latter merged 2026-10-24 and already in the starting
  commit) are about the robustness of external flags; neither mentions `IsSet` or the other functions. Go 1.27.3
  meets `go 1.26`. Needs the Go adapter of version 2. Kind: bug fix.
- **H3 commander.js** — keep the `--` delimiter for executable subcommands. The fix is 11 lines in `lib/command.js`;
  the +215 lines are tests. The first list's «≥ 150 lines in one module» counted the tests: **D1 fails**. The defect
  was reported on 2026-06-17 (before the end of the training data), the fix on 2026-08-05. Needs Node ≥ 22.12. One of
  seven offline runs of the suite had 3 failures (not reproduced in six others). The runner is Node's own test runner,
  not jest.
- **H4 packaging** — `VersionRange.relation` and `RangeRelation`. 119 source lines in one module (< 150): **D1
  fails**, close to the threshold. C6: `VersionRange` itself (#1267, merged 2026-06-24) and its subset and
  disjointness checks (#1298, merged 2026-06-27) are older than the end of the training data; `relation()` is not.
  The suite needs the whole `test` dependency group (`tomli_w`, `pip`). Kind: new feature.
- **H5 tomlkit** — three fixes of the out-of-order table proxy. 25 source lines in two files: **D1 fails**. C5:
  six unrelated commits lie between the second and the third fix, so no upstream state is the reference solution.
  The mechanism was worked on in public in June 2026 (#507, #515, #536, #545), and #439 (2025-08) reported lost keys
  in the same proxy. Needs the `tests/toml-test` submodule.
- **H6 qs** — prototype keys in `parse`. About 10 source lines: **D1 fails**. The pattern (`__proto__` in `parse`)
  has been public since 2021 (#428).
- **H7 bats-core** — semaphore slots claimed atomically with `--jobs`. One source file, +12/−59: **D1 fails**. No
  earlier report of the race was found. Needs GNU `parallel`.
- **H8 clap** — `#[command(defer = true)]` for derived subcommands. Five source files: D1 passes. **C6 fails**: pull
  request #6256 (opened 2026-02-09, still open, +404/−38) implements the same attribute before the end of the training
  data. Its UI tests run only on Rust 1.98.
- **E1 BurntSushi/toml** — the nesting limit also covers arrays, and the method is renamed `MaxDepth()`. C2 at the
  limit: the last commit of the repository is of 2026-08-18; three months before a freeze after 2026-11-16 it would
  fail. C6: issue of 2026-07-16, a first patch (#501) of 2026-07-19; nothing earlier found. Kind: bug fix and
  compatibility change (rename).
- **E2 git-extras** — `git changelog --exclude <pathspec>`. The request (#1199) is of 2025, the fix of 2026-09.
  The upstream tests of the command are new with the fix. Six tests of other commands (`git browse`, `git browse-ci`
  «works with linux and …») fail in WSL with or without the network, because the script detects WSL; they have
  nothing to do with the change and must be declared or avoided by hiding WSL from the sandbox. Needs bats and the
  `vendor/bats-all` submodule. Kind: new feature.
- **E3 jiff (reserve)** — parsing a `Span` with a time unit over its limit loses an hour. No earlier report found.
  Needs a `cargo test` adapter for Maat (none exists yet). Kind: bug fix.

### Where this leaves the draw

With the criteria as written, **no hard candidate fully qualifies**: H2 is doubtful on D4, H8 fails C6, the other six
fail D1. The first list of candidates counted the lines of the tests, which D1 excludes. By the protocol (§3, item 4),
fewer than 5 qualified hard candidates means more candidates must be found, with the same criteria, before the
draw. The easy group has 3 qualified candidates (E1, E2 and the reserve E3).

## Draw

Made once, after the qualification commit is public (protocol, «Pre-registration»), by a script published with that
commit (`run-bench.sh draw`, to be written):

1. **Pools.** `H` = the qualified hard candidates, `E` = the qualified easy candidates (whether the reserve E3 is in
   `E` is fixed before the qualification commit), each sorted by id. The language and the kind of change of every
   candidate are fixed in the table above before the draw.
2. **Seed.** As in version 2: the SHA-256 of `<qualification commit id>:<round>:<randomness>`, where the round is
   the first round of the drand «quicknet» beacon (League of Entropy, chain
   `52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971`) whose time is at least one hour after the
   commit's committer date, and the commit is public before that round.
3. **Draw with rejection.** For `k = 0, 1, 2, …`: shuffle copies of `H` and `E` with Python's
   `random.Random("<seed>:<k>")`; take the first 6 of `H` and the first 2 of `E`. The first `k` whose 8 tasks meet the
   variety rule gives the tasks; the rest of its shuffled `H` and `E`, in order, are the replacement lists.
4. **Variety rule.** At least 4 languages over the 8 tasks (Python, Go, JavaScript/TypeScript, shell, Rust); at most
   2 hard tasks per language; at most one task per repository; at least one bug fix, one new feature and one
   compatibility change among the 8.
5. **Feasibility first.** Before the qualification commit, the script lists every combination of the pools and
   checks that at least one meets the rule; if none does, the rule is not relaxed: more candidates are found. With
   exactly 5 qualified hard candidates all 5 are taken (only the easy ones are drawn, under the same rule).
6. **Replacement.** A drawn task that fails a check made after the draw (C8–C10, D2, D3, D5) is replaced by the
   first task of its replacement list that keeps the variety rule; the replacement and the failed check are published
   before the freeze.

The seed, the round, the value of `k` and the drawn tasks are written in `draw.txt` in this folder.

## Open before the freeze

- More hard candidates (see «Where this leaves the draw»).
- The reference date of C2 (the date of the check, or of the qualification commit).
- Whether the reserve E3 enters the easy pool.
- The Claude Code version, the calendar end date and the weekly quota threshold (protocol, §5 and §7).
- The format adapters needed by the drawn tasks, unless Maat 1.7.0 reads those formats natively.

## Results

None: no run made.
