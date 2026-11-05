# Benchmark protocol

**Status: not yet run.** This document fixes, before any run, what the Maat benchmark will measure and how. It is
planned after Maat 1.6.0 (the 1.5.3 of the old roadmap: the multi-platform CI). Until it is run, the README claims
nothing about Maat being better than Claude Code alone.

## The two questions

**A. Does Maat complete a change on its own?**
Given a written spec, how often does a full cycle reach a usable outcome without a person stepping in?

- Outcome of each cycle: `IMPLEMENTED`, `NEEDS_VERIFICATION`, or `STOP` with its cause.
- Human interventions: every time a person had to answer, fix or relaunch something, with the reason.
- Cost (API-equivalent, from the cycle summary) and wall-clock time per cycle.

**B. Is the result better than Claude Code alone?**
The same specs are given to Maat and to a baseline, under the same conditions.

- **Baseline:** a single Claude Code session, same model, same Claude Code version, same project, given the spec and
  the instruction to implement it, test it and report what was done and what was verified.
- **Measures**, in order of importance:
  1. **Undisclosed defects:** defects present in the final code that the agent's own report does not mention. Maat
     promises evidence, not only code: a defect it declares (for example a check it could not run) is not counted
     here; a defect it reports as done or verified is.
  2. **Hidden acceptance tests:** tests written before the runs, from the spec, and never shown to either side.
     The share that passes on the final code.
  3. **Defects found by a blind review:** a reviewer who does not know which side produced the code.
  4. Cost and wall-clock time.

## Tasks

- Public repositories only, so that anyone can repeat the runs.
- Different languages, sizes and kinds of change (new feature, bug fix, refactoring), including at least one
  project without tests.
- Each spec is written and frozen before any run; its hash is recorded.
- Specs are written in the format Maat reads, and given unchanged to the baseline.

## Runs

- At least 3 runs for each task and each side, in random order.
- Each run starts from the same commit, in a clean copy of the repository.
- Every run is recorded, including failed or interrupted ones: spec hash, commit, versions, outcome, cost, time,
  the final diff, the agent's report.
- No run is repeated or discarded after looking at its result.

## Pre-registration

This protocol, the task list and the measures are published before the first run, and do not change after that.
If a flaw is found once the runs have started, the runs are not adjusted: the benchmark starts again from the
beginning, under a new version of this protocol, published before its first run.

## Threats to validity

- The specs are written by the author of Maat; when possible, some come from other people.
- Model output varies between runs: hence at least 3 runs per side, and results reported with their spread.
- Cost on a subscription is not billed per call: the API-equivalent cost is reported as given by Claude Code.
- Hidden tests and blind review reflect the reviewers' judgment; their instructions are published with the results.

## Results

Not available yet. They will be added here, with the raw records, when the benchmark is run.
