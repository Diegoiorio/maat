# Maat benchmark, version 3 — candidates and draw

**Status: draft, not frozen, no run made.** This folder will apply [`../BENCHMARK-PROTOCOL-v3.md`](../BENCHMARK-PROTOCOL-v3.md)
(version 3, also a draft). It lists the two pools of candidate tasks with each criterion checked, the candidates left
out and why, and the procedure that will draw the tasks. Nothing here is pre-registered yet. No spec, hidden test or
format adapter exists, because they are written only for the tasks that will be drawn (protocol, §3, item 5, and §8).
No Claude session has been run on any candidate.

## What is compared

- **Maat side:** Maat `v1.7.0` (not released at the time of this draft), installed and started as in version 2: the
  plugin at project scope, the task's frozen `.claude/maat.json`, the full cycle started by its driver, nobody
  answering.
- **Baseline side:** one Claude Code session in print mode with a fixed prompt, in a copy without Maat (the prompt of
  version 2, with the tools of the new environment named).
- **The same on both sides:** one Claude Code binary, at the version current at the freeze and pinned from then on;
  model **`claude-opus-5-5`**; a configuration folder used only for the benchmark; Linux (Ubuntu 24.04 on WSL2);
  bubblewrap isolation; no web tools; the same prepared environment; one run at a time; the 4-hour cap.
- **Toolchains** (those of the checks below): Python 3.12.3, Go 1.27.3, Node 22.22.2, Rust 1.99.1, GNU `parallel`
  20261022, bats 1.14.0, git 2.43.0, bash 5.2.21; pnpm 11.15.1 only to prepare N2.

## Criteria

General requirements; a candidate missing one is rejected:

| # | Requirement | How it is checked before any run |
|---|---|---|
| C1 | A real open-source repository with a permissive license (MIT, BSD, Apache-2.0, ISC) | the license file at the starting commit |
| C2 | A maintained project | commits and merged pull requests in the 3 months before the **date of the qualification commit** |
| C3 | A test suite that runs (or, for at most one task, no tests, declared) | run on a prepared copy, offline; failures unrelated to the task are declared (protocol, §4a) |
| C4 | A real upstream change: an issue or pull request that describes it and fixes it | link, merge commit |
| C5 | Starting commit = parent of the commit that brings the upstream change | `git rev-parse <merge>^` on the mirror |
| C6 | The fix was not public before the model's training data (`claude-opus-5-5`: June 2026) | dates of the pull request and of the issue; a search of the project's issues and pull requests for earlier reports or patches; what was found is written. A request or a report of the defect may be older; an implementation may not |
| C7 | Runs offline in the bubblewrap sandbox, with pinned toolchains | environment prepared before the run, then the project's suite with the network closed |
| C8 | Hidden tests can be written with a fixed total, with no leak | test → requirement map; nothing in the working copy to copy them from |
| C9 | Stable hidden tests | 20 runs on the reference solution, all full; 20 on the starting commit, always the same score |
| C10 | Maat can work on it with no known tool defect | `gates.sh` and `plan-check.sh rossi` on a prepared copy, new folders creatable |

Hard tasks must also meet D1–D5 (protocol, §1–2). C8–C10, D2, D3 and D5 depend on the spec, the hidden tests and
`v1.7.0`: they are checked after the draw, on the drawn tasks only.

**A first list was dropped; the thresholds were not lowered.** A first list of eight hard candidates (H1–H8, below)
was sized by the whole pull request, test lines included. D1 counts source files and lines only, so six of the eight
failed D1. Those eight were dropped and a new search was made under the same D1 and D4.

## Pool of hard tasks (the draw takes 6 of 10)

Sizes of the upstream fix count source only. For all ten: the merge commit was read on a mirror, it is on the main
line, it has one parent, and that parent is the starting commit; the pull request's dates and merge commit were
checked against GitHub's public API; the license is MIT at the starting commit; the project had merged changes in
the last 3 months. Each suite ran offline on a history-less copy of the starting commit (network closed by bubblewrap).

| Id | Repository | Upstream change | Starting commit | Fix (source) | Repository (files, source lines) | Language, kind | Suite offline |
|---|---|---|---|---|---|---|---|
| N1 | [agronholm/anyio](https://github.com/agronholm/anyio) | [#1343](https://github.com/agronholm/anyio/pull/1343), issue #1342, 2026-09-23 → 10-31 | `1af29a44a9d9f3d76817668430ff7eb8df00257b` | 4 files, +147/−5 | 282, 16.6k | Python, new feature | pytest; `tests/test_from_thread.py` 222 passed, 2.9 s; full suite 461 failures unrelated, about 2 min |
| N2 | [h3js/h3](https://github.com/h3js/h3) | [#1526](https://github.com/h3js/h3/pull/1526), issue #1432 (07-03), 2026-08-10 (same day) | `82bee3bfcd7b2dbad6d2b11657fd872c953d15d6` | 8 files, +170/−71 | 223, 9.4k | TypeScript, compatibility (breaking) | vitest, 1626 passed, 1 failure unrelated, 8 s |
| N3 | [labstack/echo](https://github.com/labstack/echo) | [#3087](https://github.com/labstack/echo/pull/3087), issue #3071 (08-25), 2026-09-06 → 09-29 | `bc4028f1d7cc373823de8b6eb057cd4a9d5fc85c` | 3 files, +52/−32 | 152, 12.4k | Go, bug fix | `go test`, ok, 3 s |
| N4 | [mikefarah/yq](https://github.com/mikefarah/yq) | [#2871](https://github.com/mikefarah/yq/pull/2871), request #95 (2017), 2026-09-19 → 09-29 | `338eca45467f7d1159dd2ce10f894dd9cceef637` | 6 files, +148/−1 | 549, 18.4k | Go, new feature | `go test`, ok, 13 s |
| N5 | [nodejs/undici](https://github.com/nodejs/undici) | [#5829](https://github.com/nodejs/undici/pull/5829), no issue, 2026-09-15 → 09-16 | `6933139baebca36b470c6db663d4207f29944867` | 3 files, +259/−82 | 817, 39.0k | JavaScript, bug fix | `test:interceptors`, 397 passed, 3 skipped, 44 s |
| N6 | [hyperium/hyper](https://github.com/hyperium/hyper) | [#4183](https://github.com/hyperium/hyper/pull/4183), request #3832 (2025), 2026-09-06 → 10-05 | `714c7cf46fd405c88eb34c2f243ae5b146ba8f07` | 6 files, +162/−3 | 139, 22.0k | Rust, new feature | `cargo test`, 312 passed, build 76 s + 16 s |
| N7 | [tafia/quick-xml](https://github.com/tafia/quick-xml) | [#988](https://github.com/tafia/quick-xml/pull/988), issue #978 (07-19), 2026-07-29 → 07-30 | `b0611e33234e7c118c85561c7bdcdd21676fe766` | 4 files, +88/−8 | 160, 34.9k | Rust, bug fix | `cargo test`, 2313 passed, build 60 s + 74 s |
| N9 | [pyenv/pyenv](https://github.com/pyenv/pyenv) | [#3567](https://github.com/pyenv/pyenv/pull/3567), request #2334 (2022), 2026-09-25 (same day) | `3d1dda120be789de6af219ad945c36b2a95e5d4a` | 3 scripts, +144/−3 | 1757, 6.5k | shell, new feature | bats, 491 of 491, 46 s |
| N11 | [tox-dev/tox](https://github.com/tox-dev/tox) | [#4108](https://github.com/tox-dev/tox/pull/4108), replaces #4105 (09-30), 2026-10-01 (same day) | `b3e69e413bf5662dfdf54fa5049f0650b53d35e3` | 6 files, +132/−48 | 324, 17.3k | Python, bug fix | pytest (`-n 8`), 8286 passed, 18 failures unrelated, about 1 min |
| N12 | [alecthomas/kong](https://github.com/alecthomas/kong) | [#653](https://github.com/alecthomas/kong/pull/653), replaces #650 (08-20), 2026-08-26 → 08-28 | `b778e12c066ce62e03f3eb1439fd003d6a4bbb25` | 4 files, +158/−19 | 82, 7.1k | Go, new feature | `go test`, ok, < 1 s |

### Notes on the hard tasks

Trap (D3) as expected from the upstream change, to be fixed in the spec. C6 lists what the searches found before the
end of the training data. The signals of D4 are the ones of the protocol, §1.

- **N1 anyio** — `BlockingPortal.call_async()`: call a portal running in another event loop's thread, with results,
  exceptions, context and cancellation carried across. Trap: concurrency and cancellation, across asyncio and Trio.
  D4: 26 commits, 16 reviews by 4 people, 5 weeks. C6: nothing earlier. `trio` must be added to the test group.
- **N2 h3** — decode only the needless escapes of `event.url.pathname`, except `%2F` and `%25`, and leave the original
  URL alone. Marked breaking upstream (`fix(event)!`) on a release candidate (`2.0.1-rc.26`). Trap: security (double
  decoding, middleware bypass) and compatibility. D4: 11 commits, 3 reviews, third version of the rule upstream. C6:
  #1354 and #1361–#1363 (March–April 2026) are about the same decoding but other aspects; no earlier implementation of
  this rule.
- **N3 echo** — `BodyLimit` cannot be bypassed by one large read; JSON, XML, form and multipart answer 413. Trap:
  security, error paths. D4: 6 reviews, 3 weeks, 3 alternative pull requests, but **84 source lines**: inside the size
  of the version 2 tasks. C6: all related pull requests are of August–September 2026.
- **N4 yq** — `if … then … elif … else … end`. Trap: parser errors, and paths such as `.if` that must keep working.
  D4: 17 commits, 10 days. C6: only requests (#95, 2017). The pull request declares that an AI assistant helped write
  it, which does not touch C6.
- **N5 undici** — honor backpressure in the decompression interceptor. Trap: streams, retries, lost data. D4: 341
  source lines but 1 day and 1 reviewer. **D1 rests on the count of 3 files, one of them a one-line type declaration**;
  by lines it has 296 changed in a module of 401 lines, which is not a large one. C6: follow-up of a security advisory,
  nothing earlier on backpressure.
- **N6 hyper** — `max_header_size` for HTTP/1, server and client. Trap: security, exact limits, trailers. D4: one month
  of review. C6: request #3832 (2025) and related defects (#4081, #3874), no earlier implementation.
- **N7 quick-xml** — a depth limit in the serde deserializer. Trap: security (stack overflow), error paths. D4: 2
  reviewers, a first attempt closed, 1 day, **96 source lines**: at the edge of the version 2 tasks. C6: #819 (2024) is
  another defect; #982 is later than the training data.
- **N9 pyenv** — `pyenv binary install`: pick a published package for the system or stop, never build from source.
  Trap: error paths, compatibility of the ordinary command. D4: 7 reviews, 12 review comments, same day. C6: the plugin
  was born on 2026-07-01; only the request #2334 before. The package index is external: the tests simulate it and the
  spec must give its format. Needs GNU `parallel` to run the suite in parallel.
- **N11 tox** — `set_env` values resolved when read. Trap: compatibility of the substitution rules, self-reference. D4
  **close to the line**: merged in 49 minutes, though second version of the change, with follow-ups upstream. C6:
  related fixes in February 2026 (#3737, #3739, #3775), already in the starting commit; resolving at read time is new.
- **N12 kong** — `lastwins` flag groups. Trap: compatibility with `xor`, negation, defaults. D4 **close to the line**:
  2 days, 1 reviewer, a heavier first version dropped. C6: only #650, August 2026.

## Pool of easy tasks (the draw takes 2 of 3)

Declared easy before any run; C1–C10 apply, not D1–D5; reported apart.

| Id | Repository (license) | Upstream change | Starting commit | Fix (source) | Repository (files, source lines) | Language, kind | Suite offline |
|---|---|---|---|---|---|---|---|
| E1 | [BurntSushi/toml](https://github.com/BurntSushi/toml) (MIT) | [#514](https://github.com/BurntSushi/toml/pull/514), issue #497 (07-16), merged 2026-08-16 | `eb8b9987e23e6f5aff69fb1a1d0b113840c0964e` | 2 files, +19/−12 | 1097, 5.9k | Go, bug fix | `go test`, ok, 1.4 s |
| E2 | [tj/git-extras](https://github.com/tj/git-extras) (MIT) | [#1275](https://github.com/tj/git-extras/pull/1275), request #1199 (2025), 2026-09-16 → 09-20 | `7e01ed30d0a30a6751af4df9f32fb062671f3dab` | 2 files, +17/−5 (plus man pages) | 365, 5.8k | shell, new feature | bats, 76 tests, 70 pass, 7.3 s; 6 declared failures |
| E3 | [BurntSushi/jiff](https://github.com/BurntSushi/jiff) (MIT or Unlicense) | [#662](https://github.com/BurntSushi/jiff/pull/662), 2026-10-15 → 10-31 | `bc41185bf7e5dbdc9f877fa21c7f3fd7318d7a48` | 3 files, +84/−3 | 334, 90.5k | Rust, bug fix | `cargo test -p jiff`, all passed, build 53 s + 81 s |

- **E1** — the nesting limit also covers arrays, and `MaxTableNesting()` becomes `MaxDepth()`. **E1 stays in the pool
  only if the qualification commit is dated before 2026-11-16**: its last merged pull request is of 2026-08-16 and the
  repository's last commit of 2026-08-18. It counts as a bug fix, not as a compatibility change: the old name was added
  on 2026-04-15, after the last release (v1.6.0, 2025-12-18), so no released API changes.
- **E2** — `git changelog --exclude <pathspec>`. The six failures are declared and excluded from the count (protocol,
  §4a). Needs bats and the `vendor/bats-all` submodule. The upstream tests of the command are new with the fix.
- **E3** — parsing a `Span` with a time unit over its limit loses an hour. No earlier report found.

## Offline suites

Each of these suites was run on the prepared copy with the network closed. Where the record of the search showed
failures, the suite was run twice more to see whether the same tests fail:

| Task | What ran | Result of the two repeated runs | Failures |
|---|---|---|---|
| N1 | full suite | same 461 tests both times | 460 in `tests/test_sockets.py`, 1 in `tests/test_lazyimport.py`; they fail with the network too (address handling of WSL), and the tests of the portal itself are all green. An earlier run counted 459 |
| N2 | full suite | same 1 test both times | `getRequestFingerprint … uses the request ip when no x-forwarded-for header set (node)`: the client address inside the sandbox |
| N5 | `test:interceptors` | 0 failures both times | none in this subset; the wider `test:unit` had 4 failures (timeouts towards unroutable addresses, TLS) in the record, not repeated |
| N11 | full suite | same 18 tests both times | 17 fail with the network too (documentation examples, `argcomplete`, `tombi`, file lock, others; the reason of each one has not been read); `test_run_installpkg_targz` passes with the network and in one earlier offline run |
| E2 | full suite | same 6 tests in every run | declared (protocol, §4a) |

If one of these tasks is drawn, the list of its failures is named before the freeze (protocol, §4a), after checking that
none of them touches the task; this is still to do for N11, whose failures include configuration tests. The suite that
serves as Maat's test gate is fixed for the same tasks (for N1 and N5, a subset). N3, N4, N6, N7, N9, N12, E1 and E3 had
no failures.

## Variety rule

As approved, the rule asks for: at least 4 languages over the 8 tasks; at most 2 hard tasks per language; at most one
task per repository; at least one bug fix, one new feature and one compatibility change (deprecation). The language
and kind of each candidate are those of the tables above, fixed before the draw, one per task.

All 630 combinations of the pools (6 of 10 × 2 of 3) were listed:

| Clause | Result on this pool |
|---|---|
| ≤ 1 task per repository | always met |
| ≤ 2 hard tasks per language | only Go can exceed it (3 candidates); rejects 105 combinations |
| ≥ 4 languages | rejects 6 more (hard tasks all in Go, Rust and one of Python or JS/TS, with E1 and E3) |
| ≥ 1 bug fix, ≥ 1 new feature | always met over the 8 tasks |
| ≥ 1 compatibility change **(deprecation)** | **cannot be met as written**: no candidate in either pool is a deprecation |

**Everything except the last clause holds: 519 of 630 combinations are valid.** The last clause has three readings:

| Reading | Valid combinations | Effect |
|---|---|---|
| A deprecation, as written | 0 | the draw is impossible |
| A change marked breaking | 330 | only N2 qualifies, so N2 is always drawn; if N2 fails a later check (C8–C10, D2, D3, D5) no replacement can keep the clause |
| **Proposed:** a task that names backward compatibility as its D3 trap (N2, N4, N9, N11, N12) | 519 | always met, since any 6 of the 10 include one; **the clause then constrains nothing**, and this should be said plainly |

**Proposed, for the author to confirm; not yet a decision.** The third reading is the smallest honest change: it
keeps the draw entirely random, it adds no candidate that failed D4 only to fill the rule (the only deprecation found,
werkzeug #3337, was merged in 5 minutes with no review), and it depends on the language and kind of a task, not on who
is expected to do well on it. Version 3 then contains no deprecation task, listed among the threats to validity.

Under the proposed rule every valid combination is equally likely: each Go hard candidate is drawn with about 52%
probability, each of the others with about 64%, each easy candidate with about 67%. If E1 leaves the pool, E2 and E3
are both taken and 175 of the 210 hard sets remain valid.

## Draw

Made once, after the qualification commit is public (protocol, «Pre-registration»), by a script published with that
commit (`run-bench.sh draw`, to be written):

1. **Pools.** `H` = N1, N2, N3, N4, N5, N6, N7, N9, N11, N12; `E` = E1, E2, E3 (without E1 if the qualification commit
   is dated 2026-11-16 or later; `E` is then taken whole).
2. **Seed.** As in version 2: the SHA-256 of `<qualification commit id>:<round>:<randomness>`, where the round is
   the first round of the drand «quicknet» beacon (League of Entropy, chain
   `52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971`) whose time is at least one hour after the
   commit's committer date, and the commit is public before that round.
3. **Draw with rejection.** For `k = 0, 1, 2, …`: shuffle copies of `H` and `E` with Python's
   `random.Random("<seed>:<k>")`; take the first 6 of `H` and the first 2 of `E`. The first `k` whose 8 tasks meet the
   variety rule gives the tasks; the rest of its shuffled `H` and `E`, in order, are the replacement lists.
4. **Replacement.** A drawn task that fails a check made after the draw (C8–C10, D2, D3, D5) is replaced by the first
   task of its replacement list that keeps the variety rule; the replacement and the failed check are published before
   the freeze.

The seed, the round, the value of `k` and the drawn tasks are written in `draw.txt` in this folder.

## Left out

**Excluded from the second search's qualified list, for C3 and C9:**

- **N8 nvm #3920** — six tests of the unit suite fail at the starting commit, also with the network; one of them is
  `nvm ls-remote`, the very command the task changes.
- **N10 aiohttp #13930** — the requirements do not install as they are on Python 3.12, the editable install fails, one
  run ended with a crashed test worker, and 3 of the cookie tests are red at the starting commit.

**The first list, dropped:**

| Id | Change | Why |
|---|---|---|
| H1 | [pallets/click](https://github.com/pallets/click) #3866 | D1: 1 source file, +90/−4 |
| H2 | [urfave/cli](https://github.com/urfave/cli) #2503 | D4 weak: 3 files but 61 lines, merged in 3.5 hours with no review |
| H3 | [tj/commander.js](https://github.com/tj/commander.js) #2577 | D1: 1 source file, +9/−2 |
| H4 | [pypa/packaging](https://github.com/pypa/packaging) #1473 | D1: 1 source file, 119 lines |
| H5 | [python-poetry/tomlkit](https://github.com/python-poetry/tomlkit) #663, #699, #677 | D1: 2 source files, 25 lines; C5: 6 unrelated commits between the fixes |
| H6 | [ljharb/qs](https://github.com/ljharb/qs) #636, #638 | D1: 2 source files, about 10 lines |
| H7 | [bats-core/bats-core](https://github.com/bats-core/bats-core) #1259 | D1: 1 source file, +12/−59 |
| H8 | [clap-rs/clap](https://github.com/clap-rs/clap) #6521 | C6: pull request #6256 (opened 2026-02-09) implements the same attribute before the end of the training data |

**Second search, not in the pool.** About 450 public repositories were listed, 387 had commits since 2026-06-01 and
were scanned; 6,010 commits exceeded D1 by script, 748 were bug fixes or features with tests, and about 60 were read
closely.

- Passed D1 and C6 but weak on D4, not in the pool: resty #1188, go-task #3091, toml-rs #1245, cargo-deny #904,
  werkzeug #3337.
- C6, an implementation or the pull request itself before the end of the training data (some doubtful): starlette
  #3431, anyio #1146, black #5175, babel #1161, go-toml #1084, go-task #2898, asdf #2303, pest #1212, zod #6387 and
  #6371, go-json #630, node-csv #485, tealdeer #458, jsonpickle #645, got #2462, fd #2135.
- D1: fastapi #16577 and #16596, undici #5942, watchexec #1154.
- C4, direct commits with no pull request: mvdan/sh, minijinja, nvm `3fda4d55`.
- C7, needs a service or a system tool: kysely #2161, go-redis, multidict #1453, pyenv #3528, uutils #13382.
- C8, hard to test from behaviour: node-semver #918, pyenv #3581.
- D2 or D4: websockets #1744, platformdirs #550, pillarjs/router #215, just #3524.
- Same repository as a pool candidate: h3 #1608, echo #3133. Not examined further: git-cliff #1611.

## Open before the freeze

- The compatibility clause of the variety rule (see «Variety rule»).
- N5's D1, and N3 and N7 against the comparison with version 2 (see «Notes on the hard tasks»).
- The date of the qualification commit (before 2026-11-16 to keep E1).
- `v1.7.0`, which must be released before C10 and the adapters can be proven.

## Results

None: no run made.
