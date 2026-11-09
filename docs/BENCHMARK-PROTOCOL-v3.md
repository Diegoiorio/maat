# Benchmark protocol, version 3

**Status: draft, not frozen, no run made.** This document is a proposal for the author to read; nothing in it is
pre-registered yet. It becomes the pre-registration only when its freeze commit is public (see «Pre-registration»).
It is meant for Maat **1.7.0** (release tag `v1.7.0`, not released when this draft was written). Its application,
with the candidate tasks and the draw, is [`benchmark-v3/README.md`](benchmark-v3/README.md).

Version 2 ([`BENCHMARK-PROTOCOL.md`](BENCHMARK-PROTOCOL.md), applied in [`benchmark/`](benchmark/README.md)) stays
as it is, with its 8 runs; version 3 does not reuse them.

## What stays from version 2

The two questions (A: does Maat complete a change on its own; B: is the result better than Claude Code alone), the
baseline (one Claude Code session in print mode, same model, same Claude Code binary, same project, a fixed prompt),
the measures and their order (undisclosed defects, hidden acceptance tests, defects found by a blind review, cost and
wall-clock time), the procedure of a run (a clean copy without history, the environment prepared before the run, one
command per side, nobody intervenes, the 4-hour cap), the isolation (bubblewrap, the hidden tests and the mirrors
never visible), the hidden tests run right after each run with their rule for infrastructure errors, the blind
review and the adjudication only after all runs, and the rule that no run is repeated or discarded after looking at
its result. Where this document says nothing, version 2 and its Clarifications apply.

## What changes, and why

### 1. Harder tasks

**Why.** On the five tasks of version 2 the baseline reached the full hidden score in every run it finished (4 of
4), in 3 to 8 minutes. With the score at its ceiling, measure 2 cannot tell the two sides apart. The tasks were meant
for 30 to 90 minutes; in practice they were changes of 1 to 3 files and under 100 lines of source.

**What.** A task enters the hard group only if it meets every requirement below, besides the general ones (§3):

| # | Requirement | Threshold |
|---|---|---|
| D1 | A change across several files | the upstream fix touches ≥ 3 source files, or ≥ 150 changed source lines in one large module. Not source: tests, docs and their examples, changelogs, lock files, version numbers, build thresholds, fuzzers, data files |
| D2 | Requirements with edge cases | ≥ 6 functional requirements, ≥ 3 of them with explicit edge cases |
| D3 | At least one known trap | backward compatibility, security (hostile input), concurrency, error paths, data loss or corruption, exact round trip: named in the spec and covered by ≥ 3 hidden tests |
| D4 | Estimated baseline time ≥ 30–60 minutes | estimated from the signals below, never from a trial run |
| D5 | The spec describes behaviour | see §2 |

D4 is estimated only from signals that can be checked before any run: the size of the upstream fix (source files,
lines added and removed, tests excluded), the regression cases added upstream, the days between opening and merge
and the rounds of review, the edge cases and traps listed in the issue, and the comparison with version 2 (1–3
files, < 100 lines of source). None of them says how long an agent will take; this is a threat to validity.

**A first list of candidates was dropped.** The first list of eight hard candidates was made by counting the whole
size of each upstream pull request, test lines included. Checked against D1, which excludes tests, six of the eight
failed, a seventh failed C6 and the eighth was weak on D4. The list was dropped and a second search was made. **The
thresholds were not lowered**: the same D1 and D4 were applied to the second search, and the exclusions named in D1
were only made more explicit, which can reject a candidate but never admit one. The first list and the reason for
each rejection stay in the README.

### 2. Specs written like an issue

**Why.** In version 2 the specs named the files and the functions to change. That removes the part of the work where
a process can help most (finding where the change goes and what else it touches) and makes the task easier for both
sides.

**What.** A spec describes the **expected behaviour**, the way a good issue does: the problem, the public API and its
documented behaviour, the cases that must work, the compatibility that must be kept, the context a contributor would
be given. It never names an internal file, function or class to change. It may name the public API (a documented
function, a command-line option, an error message the user sees). Before the freeze each spec is checked against
this rule, by the author and, when possible, by one other reader; the check is written in the README. The spec is the
same for both sides, in the format Maat reads, as in version 2.

### 3. Candidate qualification and a public random draw

**Why.** In version 2 the author chose the tasks. Even with good intentions, a choice made by hand can lean towards
tasks where Maat is expected to do well.

**What.**

1. **Criteria first.** The general requirements C1–C10 (in the README) and D1–D5 are fixed before the candidates
   are looked at closely; the candidates are judged only against them. If a criterion turns out to be wrong after the
   candidates have been seen, it is not quietly changed: a new version of the criteria is written, with its reason,
   before the candidates are checked again, and the change is listed among the threats to validity.
2. **No trial runs.** No Claude session, of either side, is run on a candidate before the benchmark. A trial of the
   baseline only, used to drop the tasks it solves easily, would keep exactly the tasks where the baseline fails: a
   gift to Maat. Difficulty is estimated only from the signals of §1. Tool problems (adapters, runners, the
   sandbox) are fixed and tested on prepared copies, without an agent working on the task.
3. **Qualification in public.** For every candidate the README publishes the result of each criterion and its
   evidence (repository, license, upstream issue and pull request, dates, the merge commit, the starting commit =
   its parent, the size), rejected candidates included.
4. **Draw.** **6 hard** tasks are drawn from a pool of 10 and **2 easy** tasks from a pool of 3, with a public seed,
   under a rule of variety (at least 4 languages over the 8 tasks, at most 2 hard tasks per language, at most one task
   per repository, at least one bug fix and one new feature; the clause on compatibility changes is an open point, see
   the README, «Variety rule»). The procedure is in the README («Draw»). If a later check leaves fewer than 6 hard
   candidates, all of them are taken, with a minimum of 5; with fewer than 5, more candidates are looked for, with
   the same criteria, before the freeze.
5. **Specs and hidden tests come after the draw.** They are written only for the drawn tasks, so that no effort is
   spent on tasks that will not be drawn. The criteria that depend on them (C8, C9, C10, D2, D3, D5) are checked on
   the drawn tasks before the freeze. A drawn task that fails one of them is replaced by the next candidate in the
   draw's order that keeps the variety rule; the replacement and its reason are published. This happens before the
   freeze and before any run, so it cannot depend on a result.
6. **A task that turns out easy stays.** A task where both sides reach the ceiling stays in the results, marked «not
   discriminating»; it is not removed or replaced once the runs have started.

### 4. Easy tasks, reported apart

**Why.** Maat 1.7.0 chooses automatically a lighter flow for small changes. Whether that flow lowers the cost of
simple work is a different question from the quality question of the hard tasks.

**What.** The 2 easy tasks are declared easy in the pre-registration, before any run. For them C1–C10 apply, not
D1–D5; both sides are expected to reach the full hidden score. They are reported **apart**: they never enter the
tables or the charts of the hard tasks, and nothing is added up across the two groups. Their main measure is the
cost and the wall-clock time of Maat against the baseline; the hidden score is the check that the light flow does
not lose quality. The flow Maat chose in each run is recorded (from the driver's output).

### 4a. Failures already present at the starting commit

A test of the project that fails at the starting commit for a reason unrelated to the task is **declared**: named in
the task's folder before the freeze, said in the same words to both sides, and excluded from every count (the hidden
total, a check on the project's suite, Maat's test gate). It is never fixed in the copy.

Declared now, for E2 (git-extras): six tests, `works with linux and github`, `… gitlab` and `… bitbucket` in both
`tests/git-browse.bats` and `tests/git-browse-ci.bats`. They fail with or without the network, because in WSL the
script does not use `xdg-open`; they have nothing to do with the changelog. The same rule applies to the other tasks
with such failures (README, «Offline suites»); their lists are fixed if those tasks are drawn.

### 5. A stop rule written in advance

**Why.** Version 2 was stopped after 8 of 30 runs by a decision taken while the runs were going, after the partial
results were seen. The reason was honest and is published, but a stop that depends on results is exactly what a
pre-registration should exclude.

**What.** Once the first run has started, version 3 stops before its last run **only** for one of these reasons:

1. **Calendar.** The runs are not finished **3 months after the date of the freeze commit**, whatever the reason
   (quota, availability of the operator).
2. **Instrument defect.** A defect of the benchmark's own tooling (run script, sandbox, adapter, hidden-test runner,
   record collection) that makes the runs not comparable, shown on the tooling itself and independent of which side
   ran. The benchmark then restarts from the beginning under a new version of this protocol, as version 2 says.
3. **External change.** The pinned Claude Code binary or the model can no longer be used (the binary stops working,
   the model is withdrawn), so the remaining runs could not keep the same conditions.

Results, partial scores, costs, outcomes, a ceiling reached by both sides, or the author's view of the benchmark are
**not** reasons to stop. A stop is published at once, with its reason under one of the three headings, and everything
made so far is published as a partial result, as version 2 did. Nothing is added after a stop: no run is made to
complete a task once the benchmark has stopped.

### 6. The audit: Maat's own files are not contamination

**Why.** In version 2 the audit marked two Maat runs contaminated (T3-maat-2 and T5-maat-2) because of the text
`/mnt/c/` in the log of the plan phase. Both hits were an example path inside Maat's own agent file
(`agents/acceptance-test-writer.md`, line 53), which the phase read from the plugin installed in the benchmark's
configuration folder; the session reached nothing outside its copy. The same text is in other files of the plugin
(`agents/plan-implementer.md`, several scripts), so every Maat run that reads them would be marked contaminated: a
false positive that hits only the Maat side.

**What.** The audit keeps the patterns of version 2 and adds one class of hits, recorded and published but not
counted as contamination: **plugin text**. A hit is plugin text only when the matched text, with the characters
around it on the same line (up to 40 on each side, after decoding the JSON string that holds it), occurs verbatim in
a file of the installed Maat plugin, that is, the read-only copy of `v1.7.0` in the benchmark's configuration folder,
whose files are checked against the tag before each run. Every other hit contaminates the run, as in version 2.
The baseline has no plugin, so for it every hit counts, as before.

This rule only removes a hit whose text the session could have read from Maat's own files; it does not hide a real
path, because a path outside the copy that the session saw would not sit inside a line of a plugin file. Before the
freeze the new audit is checked on the published records of T3-maat-2 and T5-maat-2 (expected: plugin text only, not
contaminated) and on a test log with a real outside path that is not in the plugin (expected: contaminated).

Not chosen: changing the example in Maat's agent file so that it no longer matches. That would change the product
under test to suit the benchmark, and any other example could hit the same rule later.

### 7. Quota

**Why.** On a subscription the cost is not billed per call, but the runs use the five-hour window and the weekly
window. In version 2 a group of 6 easy runs started at 21% of the five-hour window and the next at 68%; hard runs
are expected to last 5 to 10 times longer, and a full Maat cycle makes many sessions.

**What.**

- Runs go in schedule order, one at a time, in **groups of at most 4**. The usage of the subscription is checked
  **before each run**, not only before each group: above **75% of the five-hour window**, the next run waits for the
  reset. In addition, **no group starts with the weekly window above 75%**; it waits for the weekly reset.
- **A group may be split between two runs, never in the middle of a run.** When a group is split, the group table
  gets a note: after which order, when, the usage seen, and when it resumed. The order of the runs never changes.
- A run is never stopped on purpose. A run stopped or slowed by the usage limit is recognised as in version 2
  («usage limit», «limit reached», `rate_limit_error`, «out of extra usage»), recorded as it is, marked «quota»,
  reported apart, and not repeated.

### 8. Runs and tooling

- **3 runs per task and per side** (6 hard + 2 easy tasks: 48 runs), in an order shuffled with a second public seed,
  drawn after the freeze commit, as in version 2. With 3 runs per side the results show a spread; they do not support
  a statistical test.
- **Claude Code** is the version current at the freeze. It is written in the freeze commit and then pinned: one
  binary, auto-update disabled, as in version 2.
- New toolchains are pinned and checked by `run-bench.sh check` (for the current pools: Node 22, Rust, GNU `parallel`,
  bats, and pnpm for N2 if it is drawn).
- **Format adapters are written after the draw, only for the tasks drawn**, and proven before the freeze as in
  version 2: red, green and missing-adapter cases, with `gates.sh` and `plan-check.sh rossi`, on a prepared copy and
  with no agent working on the task. Maat 1.6 reads the outcome of single tests only from a JUnit report in the pytest
  form or from vitest; other runners (Go, the Node test runner, bats, cargo) get an adapter on the Maat side only,
  outside the diff. If `v1.7.0` reads a format natively, no adapter is used for it, and the README says so.

## Pre-registration

Two public commits, each followed by a drand round at least one hour after it:

1. **Qualification commit:** this protocol (status «qualification, no run made») and the README with every
   candidate's qualification. Its round gives the seed of the **draw** of the tasks. Its date is the reference date
   of C2 for every candidate: E1 stays in the pool only if this commit is dated before 2026-11-16.
2. **Freeze commit:** the drawn tasks with their specs, `maat.json`, adapters, the hash of the hidden tests, the
   versions and the end date of the calendar. Its round gives the seed of the **schedule**.
   After it, nothing changes except the «Results» section of the README; a flaw found once the runs have started
   restarts the benchmark under a new version of this protocol.

## Threats to validity (specific to version 3)

- Difficulty is estimated from indirect signals; a task can still turn out easy. It then stays, marked «not
  discriminating».
- The specs written from behaviour are still written by the author of Maat; when possible, one or two are read by
  someone else before the freeze.
- Some defects were public before the model's training data while their fixes were not (the README says which, per
  task); this helps both sides equally.
- New or changed toolchains, and the format adapters, touch the Maat side only where an adapter is used; a fault in
  one would hurt Maat only. They are small, published, and tested before the freeze.
- The plugin-text rule of the audit is a change in favour of the Maat side compared with version 2. It is narrow
  (verbatim text of the plugin's own files) and tested on both a known false positive and a real hit.
- The draw is random only among the candidates that the author found and qualified. The second search measured D1 by
  script on the merged commits of about 390 public repositories, but the final reading, and the choice of the pool
  from what qualified, were made by hand. The pool's D4 is an estimate, and some candidates are close to the line (the
  README says which).
- The rule of at most 2 hard tasks per language makes each of the three Go candidates less likely to be drawn than
  the others (about 52% against 64%). It follows from the rule, not from a judgement on those tasks.
- The pool contains no deprecation task, so version 3 says nothing about how either side handles one.
