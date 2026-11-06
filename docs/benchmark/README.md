# Maat benchmark — pre-registration

**Status: frozen; stopped by the author after 8 of 30 runs (see Results).** This folder applies [`../BENCHMARK-PROTOCOL.md`](../BENCHMARK-PROTOCOL.md)
(version 2) to five tasks. It is published before the first run. The commit that freezes it changes only this
status line; its full commit id, with a public random value drawn after it, gives the seed of the schedule
(Procedure, step 1), and the first run starts only after that commit is public. After it, nothing here changes except the «Results» section, which is filled in as the runs
go: a flaw found later restarts the benchmark under a new version of the protocol, as the protocol says.

## What is compared

- **Maat side:** Maat **1.6.0** (release tag `v1.6.0`, commit `f079090`), installed in the copy with the two
  commands of the main README (`claude plugin marketplace add https://github.com/Diegoiorio/maat.git#v1.6.0 --scope
  project`, then `claude plugin install maat@maat --scope project`), with the task's frozen `.claude/maat.json` (in
  `tasks/<task>/`, in place of an interactive `/maat:setup`; for T2 and T3 also the task's format adapter, see
  Clarifications). The full cycle is started by its deterministic driver,
  the same command that `/maat:full-implementation-cycle` launches: `driver.py run .claude/.ai-workflow/<spec> --`,
  with no flag (since 1.6.0 the driver is Maat's only engine; `FIC_DRIVER` has no effect and is not set). Nobody
  answers during the run: a `STOP` ends the run, and its cause is recorded.
- **Baseline side:** one Claude Code session in print mode, `claude -p` with the fixed prompt
  [`baseline-prompt.txt`](baseline-prompt.txt), in a copy without Maat.
- **The same on both sides:** Claude Code **2.1.318** (the native Linux binary `~/.local/bin/claude`, one binary
  as `CLAUDE_BIN`, auto-update disabled, logged in with a Claude Max subscription), model **`claude-opus-5-5`**
  (`ANTHROPIC_MODEL`), a configuration folder used only for the benchmark (no `CLAUDE.md`, plugins, hooks or MCP
  servers of the operator), the same machine and OS (Linux: Ubuntu 24.04 on WSL2; Python 3.12, Node 20, Go 1.27,
  git 2.43, `dash`, ShellCheck 0.10.0, bubblewrap, all in `PATH`; `run-bench.sh check` refuses any other version),
  `--permission-mode bypassPermissions`, no web tools (`WebFetch` and `WebSearch` denied in the project settings
  of the copy, which is the only way for the Maat side, whose driver passes no tool list, and also on the baseline's
  command line), the spec at the same path `.claude/.ai-workflow/<spec>`, the same prepared environment
  (dependencies installed before the run; neither side needs to install anything; the baseline prompt says where
  they are, as `maat.json` tells Maat), the same isolation (each run in its own sandbox, Clarifications), one run
  at a time, the same time cap of 4 hours.

## Tasks

| Id | Repository (license) | Starting commit | Language, size | Kind of change | Tests in the project |
|---|---|---|---|---|---|
| T1 | [python-humanize/humanize](https://github.com/python-humanize/humanize) (MIT) | `d16e6352c9785c5ab86de0133222bd22e89b0db2` | Python, 89 files, ~1.7k lines of source | new feature: `parse_naturalsize()`, the inverse of `naturalsize()` | pytest, ~740 tests, ~6 s |
| T2 | [dustin/go-humanize](https://github.com/dustin/go-humanize) (MIT) | `a1b4e66b9a6d890e9e15e7091cf16c8032367d6e` | Go, 39 files, ~2.8k lines | bug fix: sizes that round up to 1000/1024 keep the smaller unit (`1000 kB`) | `go test` |
| T3 | [minimistjs/minimist](https://github.com/minimistjs/minimist) (MIT) | `ecfdaea23e7931c0d529c52b743c711c3278a8ce` | JavaScript (ES5), 33 files, one 270-line module | refactoring: split the parser into `lib/` modules with no change of behaviour | tape, 171 assertions, plus a strict lint |
| T4 | [nvie/git-toolbelt](https://github.com/nvie/git-toolbelt) (BSD-3-Clause) | `354262e7d595a5f42d935fdce5a3930d0b173391` | POSIX shell, 68 files, ~2.2k lines | new feature: a `git stale-branches` command | **none** |
| T5 | [pallets/click](https://github.com/pallets/click) (BSD-3-Clause) | `6d5bac5c712195cbfa9666ba0ecbf0573cdea356` | Python, 178 files, ~12.7k lines of source | bug fix: a command's short help stops at an abbreviation (`vs.`) | pytest, ~2.1k tests, ~5 s |

The starting commits of T2 and T5 are the parents of public upstream fixes, both later than the model's training
data (`claude-opus-5-5`: knowledge up to June 2026), so the model cannot have seen the fixes themselves:

- **T2:** fixed by `2122467` (go-humanize pull request #160, opened 2026-09-20, merged 2026-10-13). The defect
  was public before: issue #127 «Don't output 1000 kB for 1.0 MB», opened 2025-04-17, and pull request #128 with a
  proposed fix, opened 2025-04-18 and never merged. Both are older than the model's training data, so the model
  may know the defect and one way of fixing it.
- **T5:** fixed by `f67c2bb` (click pull request #3865, opened 2026-09-11, merged 2026-09-12). A search of the click
  issues and pull requests (2026-11-05) found no earlier report of an abbreviation cutting the short help; the
  older issues on the rule itself (#1082, 2018: stop at a line break too) are about other cases.

The specs were written from the observed behaviour, not copied from those commits; the copies used in the runs
contain no history (see Procedure), and web tools are denied. What the model may know helps both sides equally.

Each task is meant for a cycle of 30 to 90 minutes: several requirements, edge cases that a hurried
implementation misses, and at least one constraint that is easy to break without noticing (exact arithmetic in
T1, every boundary of five functions in T2, ES5 and an unchanged behaviour in T3, `dash` and exact output in T4,
narrow widths in T5).

### Frozen files

SHA-256 of the files as committed (LF line endings, `.gitattributes` in this folder); the same list is in
[`SHA256SUMS`](SHA256SUMS).

| File | SHA-256 |
|---|---|
| `tasks/T1-humanize-parse-size/spec-parse-naturalsize.md` | `f90c1620bf415dd354a38a3d076a694375ab2237b923eac40cb0c1afda92c1cc` |
| `tasks/T2-go-humanize-bytes-rounding/spec-bytes-rounding-unit.md` | `4591679fe95692413c00832423638ddd8ebca422f34784cb0d8fd81ac222684b` |
| `tasks/T3-minimist-split-modules/spec-split-parser-modules.md` | `960d23d26f10b1c28a057f3e6033eaf6c77b05635d9bddc5e4ba650031fafcd7` |
| `tasks/T4-git-toolbelt-stale-branches/spec-stale-branches.md` | `487a18afd7ce77a00fea1b612caf3399880dcaf935fcbccfeb403eed86fbd91c` |
| `tasks/T5-click-short-help-abbreviation/spec-short-help-abbreviation.md` | `2c0ebc44b4cf96d1c6e7e8e436b8cd7e8b652fb46e80183961592bf75fdb3754` |
| `tasks/T1-humanize-parse-size/maat.json` | `1694cb2c3f45456e825a82b7da7addaf0138024d4d873ccd6a8dcb13464693f3` |
| `tasks/T2-go-humanize-bytes-rounding/maat.json` | `84da359d19bb0166e148a85df128d852667b6133465a6ea110834f8f88394574` |
| `tasks/T3-minimist-split-modules/maat.json` | `2ec85c4d13fee772a58b0c1b6b379ed8a2f502cd17a83eaf5e9c09943d0d857a` |
| `tasks/T4-git-toolbelt-stale-branches/maat.json` | `69c1c71fda0c2d91e686fa5b50f134ee2b24771362cd52b0a4196bab49743408` |
| `tasks/T5-click-short-help-abbreviation/maat.json` | `980db7b0b5d062ca1b4148bb25ac96abacef94ced5d399fbb92e787e9087608b` |
| `tasks/T2-go-humanize-bytes-rounding/adapter/go-junit.py` | `0da2839428f6c0266b165d8e733a49684f85b8227c0f096783aac5ba0d9ec458` |
| `tasks/T3-minimist-split-modules/adapter/tape-junit.py` | `1531816c9afca3fc6f48903447c2d33c59e0b9c7359d784eaefc93f612d96159` |
| `tasks/T3-minimist-split-modules/adapter/tape-objects.js` | `c7ef632cc7634342702be1a118d550664cd6823bc72affad0c79c40e4ed09028` |
| `adapters_test.py` | `09d72227ed26c4c9ba00a875ac4100cdd833ef12d49ff3be664906aa8a4d501a` |
| `baseline-prompt.txt` | `05d4452038f3433689933acf613e311c3e1fdcc8a5846f70f70be0e3f8735f20` |
| `blind-review.md` | `edb9f72e6d7ce3b1151c86f10889faff4e7193ece79ea311acfac1476a5704eb` |
| `run-bench.sh` | `e6ff329983ad7c95d173c5691613a5c15f7ba2745c44351f53ebc75e6ee44edd` |
| `run-record.md` | `0a7fb7b508f667d6c5d12c4b5f43a6e3ee3514ae97ded10e2fe6ca9288cdffcc` |
| `run-record.template.json` | `4c6b30c5a3d5923709ed3d2f39b09800698d63ba2726beb029845c22a9664371` |
| `grafici.py` | `a089b21797facbb1a0be8cb93086d992715a685d70be3e8152794adfc1045a50` |
| `grafici_test.py` | `d32fca569279d81b5eed6c622b78730b8a55f0d006b7161d17e3f6002a8a9121` |
| Hidden acceptance tests: SHA-256 of their `SHA256SUMS` list (all their files; published with the results) | `3304b94f3bbb4bdb484388b39a305383c32799194558a6bbafe30e366e6d763d` |

The `maat.json` files, the format adapters of T2 and T3 and their tests, the baseline prompt, the review
instructions, the run script, the record format and the chart script are in `SHA256SUMS` too. Not in the list, on
purpose: this README (its «Results» section changes as the runs go), `.gitattributes`, the charts in `grafici/`
(made from the records) and `schedule.tsv` (made from the seed). The hidden tests' list covers all their files:
the tests, their runners, their pinned `pytest`, the test → requirement map, their README and the reference
solutions.

## Measures

As in the protocol, in this order of importance, per run and then per task and side (median and range of the 3
runs; no pooled score across tasks):

1. **Undisclosed defects** — defects in the final code that the run's own report does not mention
   ([`blind-review.md`](blind-review.md), «Adjudication»).
2. **Hidden acceptance tests** — share passed on the final code. Written from the specs before any run, never shown
   to either side; their text is published with the results, their unit and totals now:

   | Task | Counted unit | Total (fixed) | Unchanged starting commit | Reference solution |
   |---|---|---|---|---|
   | T1 | pytest case (parametrized cases included) | 120 | 9 | 120 (written for the check) |
   | T2 | hidden test or subtest, plus 3 checks on the agent's tree (`go vet`, `gofmt -l`, the project's tests) | 21 | 6 | 21 (upstream fix `2122467`) |
   | T3 | 5 checks (original tests unchanged, project suite, lint, ES5, `npm pack`) + 16 hidden tests | 21 | 6 | 21 (written for the check) |
   | T4 | check: 9 static, 18 behaviours × (`dash`, `bash`) | 45 | 2 | 45 (written for the check) |
   | T5 | pytest case | 106 | 87 | 106 (upstream fix `f67c2bb`) |

   A test that does not run (collection error, crash, timeout) counts as failed: the total never shrinks. Their
   rules for errors are in Clarifications.
3. **Defects found by a blind review** — a reviewer that sees only the spec and the final diff
   ([`blind-review.md`](blind-review.md)).
4. **Cost and wall-clock time** — API-equivalent cost as reported by Claude Code (Maat: `phase-usage.py --summary`
   of the cycle; baseline: `total_cost_usd` of the session), and wall-clock seconds from launch to exit.

For question A (does Maat complete a change on its own), the Maat runs also report their outcome
(`IMPLEMENTED`, `NEEDS_VERIFICATION`, `STOP` and its cause). T4 has no tests: Maat's best outcome there is
`NEEDS_VERIFICATION`, by design.

## Procedure

[`run-bench.sh`](run-bench.sh) is the procedure; in short:

1. **Schedule.** `run-bench.sh seed <freeze commit id>` then `run-bench.sh schedule <seed>` shuffle the 30 runs
   (5 tasks × 2 sides × 3). The seed is the SHA-256 of `<commit id>:<round>:<randomness>`, where the commit is the
   one that freezes this document and the round is the first round of the drand «quicknet» beacon (League of
   Entropy, chain `52db9ba7…e971`, a public value every 3 s) whose time is at least one hour after the commit's
   committer date. The freeze commit is pushed before that round is drawn (the push time is published with the
   schedule); otherwise a new freeze commit is made. So nobody, the author included, can know the order before the
   commit is fixed. The runs are launched in that order, in groups of at most 6 consecutive runs, **one at a time**
   (`run-bench.sh group <first> <last>`), with the quota check before each group (Clarifications).
2. **Clean copy per run.** The starting commit is exported with `git archive` into a new repository with one commit
   at a fixed date (same commit id for every copy of a task, no upstream history, no remote). The environment is
   prepared before the run: a venv with the project and its `tests` extra (T1) or the project and pytest (T5),
   `go mod download` (T2), a `node_modules` installed once with `--ignore-scripts` and copied (T3), nothing (T4);
   the versions installed are recorded with the run. The spec is copied to `.claude/.ai-workflow/` and its hash
   checked against `SHA256SUMS`; on the Maat side the plugin and the task's `maat.json` (and adapter) are added,
   and the installed version is checked against the tag. The prepared copy must be clean (`git status` empty).
   Before each prepare and each run, `run-bench.sh check` verifies the exact versions; before each run,
   `sandbox-check` verifies from inside the sandbox that the hidden tests, the mirrors, the records and the other
   copies are not visible.
3. **Run.** One command per side (above), inside the sandbox, with the 4-hour cap (`timeout -k`). Nobody
   intervenes during a run.
4. **Collect.** The final diff (`.claude/` excluded), its hash, the report (Maat: the spec with plan, review and
   evidence written by Maat, and the driver's last line; baseline: the session's final message), cost and time,
   the versions, and three checks of what the run left: the audit of paths outside the copy, the model of every
   session (its `init` event), the signs of the usage limit; [`run-record.md`](run-record.md) lists every field
   and maps the driver's results to the outcomes.
5. **No run is repeated or discarded.** A run that fails, stops or hits the cap is recorded as it is. A copy or a
   record folder that already exists makes the script refuse.
6. **Hidden tests right after each run** (`run-bench.sh hidden <run-id>`, part of `group`): they are fixed in
   advance and involve no judgement. They run in a sandbox too, on a copy of the final tree, offline (their pinned
   `pytest` comes from a local wheelhouse), after `sha256sum -c` of their list. The record keeps only the score
   (`hidden: p/t`); their output stays private with the tests until the end. **After all runs:** the blind review, then the adjudication; then the final
   results are added below with all raw records, the hidden tests and their per-run output.

## Clarifications of the protocol

These do not change the protocol; they fix choices it leaves open.

- "Human interventions" (question A): by this procedure there are none during a run. A Maat `STOP` that would need
  a person ends the run; its cause is the measure. A baseline session that stops to ask a question ends the same
  way.
- "Defect" and "undisclosed": defined in [`blind-review.md`](blind-review.md) («Adjudication»). A requirement with
  failing hidden tests counts as one defect.
- The Maat cycle is started through its driver (the command the slash command runs), not through an interactive
  chat: the result, the evidence and the cost are the same; the chat would only add the progress lines and the
  questions before the start, which nobody would answer.
- **Intermediate publication** (a decision of the operator). After each group of runs, the raw record of every
  finished run (outcome, cost, time, final diff and its hash, the agent's report, versions) and the hidden-test
  score of that run are published in `records/<run-id>/`, with the status «partial: N of 30». The blind review and
  the adjudication of undisclosed defects are made only after all 30 runs, all together. The text of the hidden
  tests stays private until the end (only its hash is published, above). The partial tables and charts change
  nothing in the procedure: no run is repeated or discarded, and the order stays the one fixed by the seed.
- **Hidden tests after each run**, not only at the end: they are fixed before the first run and give a number
  without judgement, so running them early cannot depend on what was seen (step 6 of the Procedure). Two rules for
  their errors: an error caused by the agent's tree (it does not build, does not import, hangs past the timeout)
  gives what passed, down to 0/total; an error of the infrastructure (the copy, the venv, the offline install, a
  missing tool: the runner says `infra-error`) allows **one** rerun, `run-bench.sh hidden --retry-infra <run-id>
  "<note>"`, with the note written in the record; a second one is recorded as it is, with no score.
- **Isolation.** Every Claude session of both sides, Maat's sub-sessions included (children of its driver), runs
  inside bubblewrap: read-write only its own copy and the benchmark's configuration folder (whose installed plugins
  are read-only); read-only the system (`/usr`, `/etc`) and the tools (Claude Code, Go, Node, ShellCheck); a private
  `/tmp`, an empty `$HOME`, its own process namespace; the network is shared (the API needs it). The hidden tests,
  the reference solutions, the mirrors with the upstream history, the records, the other copies and the rest of
  the machine are not visible. After each run an **audit** searches the transcript, the run directory and the logs
  for paths outside the copy (other copies, mirrors, records, the hidden tests, `docs/piani`, `/mnt`): a hit is
  recorded and published, and the run is marked contaminated; it is not repeated, as the protocol says.
- **ShellCheck.** T4's spec does not ask for it. The Maat side runs it as a check of `maat.json` on the scripts it
  touches; the baseline has it in the `PATH` and is told so in its prompt.
- **Format adapters for T2 and T3** (Maat side only). Maat 1.6.0 reads the outcome of single tests only from a
  JUnit report in the pytest form or from vitest; without it, the test-red phase of every plan stops `BLOCKED`
  («report none»). Go and tape do not write such a report, so each of the two tasks has a small converter, the
  same thing a user of Maat with a Go or tape project would write: [`go-junit.py`](tasks/T2-go-humanize-bytes-rounding/adapter/go-junit.py)
  runs `go test -json ./...` (a test that does not compile, a panic: the tests that did not run are failed, not
  missing), [`tape-junit.py`](tasks/T3-minimist-split-modules/adapter/tape-junit.py) runs tape one file at a time
  through tape's object stream ([`tape-objects.js`](tasks/T3-minimist-split-modules/adapter/tape-objects.js), so a
  comment is never taken for a test); both write JUnit with one case per test, the test file as class name and the
  `file:line` of each failure, using only Python 3 and the project's own `go` or `node`. Their tests:
  [`adapters_test.py`](adapters_test.py). They are called by the
  `test` command of the task's `maat.json` (`"report": "junit"`) and installed by `prepare` in
  `.claude/bench/` of the Maat copy: outside the project's code, so they never enter the final diff, the review
  copy or the hidden tests, and the baseline copy does not have them. In the same way the lint command of T3 ends
  with the outcome line (`vitest-fast: esito=PASS|FAIL`) that Maat 1.6.0 requires of a lint gate; ESLint itself
  prints nothing when the code is clean, and the gate would otherwise be `BLOCKED`. Checked before the freeze, on a
  prepared copy of each task, with Maat's own `gates.sh` and `plan-check.sh rossi` (the check of the test-red
  phase): a new test red on its assertion is read as red with its `file:line`, the same test green as green, and
  without the adapter the phase is `BLOCKED` as described.
- **Quota.** The runs go in groups of at most 6 runs, one at a time. Before each group the usage of the
  subscription is checked: above 75% of the current window, the group waits for the reset. A run stopped or slowed
  by the usage limit is recognised by «usage limit», «limit reached», `rate_limit_error` or «out of extra usage» in
  its transcript, stderr or logs (`quota.txt`): it is recorded as it is, with the reason «quota», reported apart,
  and not repeated.

## Threats to validity (in addition to the protocol's)

- All five specs, the hidden tests and the `maat.json` files are written by the author of Maat.
- T2's defect, with a proposed fix, was public before the model's training data (see Tasks); the fixes of T2 and
  T5 are later. Both sides can benefit from what the model knows.
- The adjudicator of undisclosed defects is not blind to the side (the two kinds of report look different); the
  rules are literal and every decision is published with its quote.
- Three runs per side and task show the spread, they do not support a statistical test.
- The usage limit of the subscription hits Maat harder: a full cycle makes many sessions and lasts longer, so it
  is more likely to reach the limit in the middle. One run at a time and the check before each group limit this;
  a run that reaches it is recorded, marked «quota» and reported apart (Clarifications), never repeated.
- Isolation is by bubblewrap, not by a separate machine: the network is shared, and the sandbox runs as the
  operator's user. A run cannot read the hidden tests, the mirrors or the other runs; the audit after each run
  looks for any trace of them, and the sandbox check before each run proves they are not visible.
- Partial results are public while the runs go on, and the operator sees them; nothing in the procedure depends
  on them (fixed order, no run repeated or discarded, review and adjudication only at the end).
- T2 and T3 depend on the format adapters (Clarifications): a fault in one of them would hurt only the Maat side.
  They are small, published with the frozen files, and checked on red, green and missing-adapter cases before the
  freeze; their effect is the one a Go or tape user of Maat 1.6.0 would need anyway, which also means the result
  on these two tasks holds for Maat with such an adapter, not for Maat out of the box.
- The prepared environments install the current versions of the packages at preparation time, so two runs of a
  task may get different versions; they are recorded with each run (`env-packages.txt`).

## Results

**Stopped by the author after 8 of 30 runs (2026-11-06). Version 2 of the benchmark ends here, without a result.**
The reason is in the data below and in nothing else: on these five tasks the baseline reached the full hidden score
in every run it finished (4 of 4, in 3 to 8 minutes), so the tasks are too easy for the comparison to tell the two
sides apart on quality, while the Maat side cost 2 to 10 times more where both sides ran the same task. The runs made stay here as they are, with their
records; none is removed or repeated, the blind review and the adjudication are not made, and no conclusion is
drawn from 8 runs. A version 3 of the protocol, with harder tasks chosen by criteria written before the runs, will be
published as a new pre-registration in its own folder; it does not reuse these runs.

The runs went in groups, and this section grew after each one; the blind review and the adjudication of the defects
(measures 1 and 3) were to come only after all 30 runs.

- **Schedule.** Freeze commit `b72ff0755d0d5cc7f2339e2b9bb1e20936152530`, drand quicknet round 33717017: seed and
  draw in [`seed.txt`](seed.txt), the order of the 30 runs in [`schedule.tsv`](schedule.tsv).
- **Records.** One folder per run in [`records/`](records/): `record.json` and the raw files of
  [`run-record.md`](run-record.md). `record.json` is filled in from the raw files by
  [`records/compila_record.py`](records/compila_record.py), written with the first group (it applies the table of
  `run-record.md` and decides nothing else). In the published raw files the home folder of the machine's user is
  written `/home/bench` (the only change; `final.diff` is untouched and matches its `final.diff.sha256`).

### Groups

| Group | Orders | Date (UTC) | Quota before (5 h · week) | Runs |
|---|---|---|---|---|
| 1 | 1–6 | 2026-11-06 10:02–10:51 | 21% · 79% | T4-baseline-2, T2-baseline-3, T2-maat-2, T3-baseline-2, T4-baseline-1, T3-maat-2 |
| 2 (not finished) | 7–8 | 2026-11-06 13:18–14:07 | 68% · 84% | T2-maat-1, T5-maat-2; paused by the author after order 8, before the session of order 9 started (its copy, being prepared and never used by a session, was discarded); then the benchmark was stopped |

| Run | Outcome | Hidden tests | Cost (API-eq.) | Time | Notes |
|---|---|---|---|---|---|
| T4-baseline-2 | COMPLETED | 45/45 | $0.75 | 3.2 min | |
| T2-baseline-3 | COMPLETED | 21/21 | $1.07 | 7.8 min | |
| T2-maat-2 | NEEDS_VERIFICATION | 21/21 | $9.01 | 24.1 min | the cycle ended with the counterproofs of T1 and T4 not run (the module declares no counterproof) |
| T3-baseline-2 | COMPLETED | 21/21 | $0.85 | 5.0 min | |
| T4-baseline-1 | COMPLETED | 45/45 | $0.73 | 3.0 min | |
| T2-maat-1 | NEEDS_VERIFICATION | 21/21 | $11.03 | 29.7 min | as T2-maat-2: counterproofs not run (the module declares none) |
| T5-maat-2 | NEEDS_VERIFICATION | 106/106 | $6.71 | 17.9 min | **contaminated** by the audit rule, the same two hits as T3-maat-2 (see below; plan log line 74) |
| T3-maat-2 | STOP | 6/21 | $1.61 | 5.2 min | stopped in the plan phase: `lint2` refused the rows naming files in a new `lib/` folder, which the cycle cannot create; no code written (6/21 is the starting score). **Contaminated** by the audit rule: see below |

**T3-maat-2, contaminated.** The audit found `/mnt/c/` twice in the log of the plan phase. Both hits are the text of
an example path inside Maat's own file `agents/acceptance-test-writer.md` (line 53), which the phase read from the
benchmark's configuration folder (`run-dir/log/01-plan.jsonl`, line 137); the session did not reach anything outside
its copy. The frozen rule marks the run contaminated all the same, and so it stays, with this note in its
`notes`. Any Maat run that reads that file will have the same two hits.

### Progress

Status: **stopped: 8 of 30**

| Task | Maat | Baseline |
|---|---|---|
| T1 | 0 of 3 | 0 of 3 |
| T2 | 2 of 3 | 1 of 3 |
| T3 | 1 of 3 | 1 of 3 |
| T4 | 0 of 3 | 2 of 3 |
| T5 | 1 of 3 | 0 of 3 |
| **All** | 4 of 15 | 4 of 15 |

The charts and this table are made by [`grafici.py`](grafici.py) from the records in `records/`
(`python3 grafici.py --progress` prints the table; `python3 grafici_test.py` tests the script). Each bar is the
median of the runs available, the whisker their range (min–max), and `n` the number of runs behind the bar; a
measure that is not there yet is shown as «not yet available», never as zero.

### 1. Undisclosed defects

![Undisclosed defects per run, by task and side](grafici/undisclosed-defects.svg)

### 2. Hidden acceptance tests

![Share of hidden acceptance tests passed, by task and side](grafici/hidden-tests.svg)

### 3. Defects found by the blind review

![Defects confirmed from the blind review, by task and side](grafici/blind-review.svg)

### 4. Cost and wall-clock time

![API-equivalent cost and wall-clock time per run, by task and side](grafici/cost-time.svg)
