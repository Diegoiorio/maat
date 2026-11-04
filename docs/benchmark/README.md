# Maat benchmark — pre-registration

**Status: prepared, not frozen, no run made.** This folder applies [`../BENCHMARK-PROTOCOL.md`](../BENCHMARK-PROTOCOL.md)
to five tasks. It is published before the first run. The fields marked **TBD** (versions of Maat, Claude Code and
the model) are filled in by the commit that freezes this document; the first run starts only after
that commit is public. After it, nothing here changes: a flaw found later restarts the benchmark under a new
version of the protocol, as the protocol says.

## What is compared

- **Maat side:** Maat **TBD** (release tag `v…`), installed in the copy with the two commands of the main README
  (`--scope project`), with the task's frozen `.claude/maat.json` (in `tasks/<task>/`, in place of an interactive
  `/maat:setup`). The full cycle is started by its deterministic driver, the same command that
  `/maat:full-implementation-cycle` launches: `driver.py run .claude/.ai-workflow/<spec> --`, with no flag. Nobody
  answers during the run: a `STOP` ends the run, and its cause is recorded.
- **Baseline side:** one Claude Code session in print mode, `claude -p` with the fixed prompt
  [`baseline-prompt.txt`](baseline-prompt.txt), in a copy without Maat.
- **The same on both sides:** Claude Code **TBD** (one binary, `CLAUDE_BIN`, auto-update disabled), model **TBD**
  (`ANTHROPIC_MODEL`), a configuration folder used only for the benchmark (no `CLAUDE.md`, plugins, hooks or MCP
  servers of the operator), the same machine and OS (Linux), `--permission-mode bypassPermissions`, no web tools
  (`WebFetch` and `WebSearch` denied in the project settings and on the command line), the spec at the same path
  `.claude/.ai-workflow/<spec>`, the same prepared environment (dependencies installed before the run; neither side
  needs to install anything), the same time cap of 4 hours.

## Tasks

| Id | Repository (license) | Starting commit | Language, size | Kind of change | Tests in the project |
|---|---|---|---|---|---|
| T1 | [python-humanize/humanize](https://github.com/python-humanize/humanize) (MIT) | `d16e6352c9785c5ab86de0133222bd22e89b0db2` | Python, 89 files, ~1.7k lines of source | new feature: `parse_naturalsize()`, the inverse of `naturalsize()` | pytest, ~730 tests, ~10 s |
| T2 | [dustin/go-humanize](https://github.com/dustin/go-humanize) (MIT) | `a1b4e66b9a6d890e9e15e7091cf16c8032367d6e` | Go, 39 files, ~2.8k lines | bug fix: sizes that round up to 1000/1024 keep the smaller unit (`1000 kB`) | `go test` |
| T3 | [minimistjs/minimist](https://github.com/minimistjs/minimist) (MIT) | `ecfdaea23e7931c0d529c52b743c711c3278a8ce` | JavaScript (ES5), 33 files, one 270-line module | refactoring: split the parser into `lib/` modules with no change of behaviour | tape, 171 assertions, plus a strict lint |
| T4 | [nvie/git-toolbelt](https://github.com/nvie/git-toolbelt) (BSD-3-Clause) | `354262e7d595a5f42d935fdce5a3930d0b173391` | POSIX shell, 68 files, ~2.2k lines | new feature: a `git stale-branches` command | **none** |
| T5 | [pallets/click](https://github.com/pallets/click) (BSD-3-Clause) | `6d5bac5c712195cbfa9666ba0ecbf0573cdea356` | Python, 178 files, ~12.7k lines of source | bug fix: a command's short help stops at an abbreviation (`vs.`) | pytest, ~2k tests, ~10 s |

The starting commits of T2 and T5 are the parents of public upstream fixes (`2122467` and `f67c2bb`, both
September 2026). The specs were written from the observed behaviour, not copied from those commits; the copies used
in the runs contain no history (see Procedure), and web tools are denied, but a model that has seen the fix in
training could still be helped: this applies to both sides equally.

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
| Hidden acceptance tests: SHA-256 of their `SHA256SUMS` list (published with the results) | `c134b3397d4744a8260e14bdd44091a5c1a54885231587ae74b0db3df5b037dd` |

The `maat.json` files, the baseline prompt and the review instructions are in `SHA256SUMS` too.

## Measures

As in the protocol, in this order of importance, per run and then per task and side (median and range of the 3
runs; no pooled score across tasks):

1. **Undisclosed defects** — defects in the final code that the run's own report does not mention
   ([`blind-review.md`](blind-review.md), «Adjudication»).
2. **Hidden acceptance tests** — share passed on the final code. Written from the specs before any run, never shown
   to either side; their counting unit and their result on the unchanged starting commit and on a reference
   solution are fixed in their README, published with the results.
3. **Defects found by a blind review** — a reviewer that sees only the spec and the final diff
   ([`blind-review.md`](blind-review.md)).
4. **Cost and wall-clock time** — API-equivalent cost as reported by Claude Code (Maat: `phase-usage.py --summary`
   of the cycle; baseline: `total_cost_usd` of the session), and wall-clock seconds from launch to exit.

For question A (does Maat complete a change on its own), the Maat runs also report their outcome
(`IMPLEMENTED`, `NEEDS_VERIFICATION`, `STOP` and its cause). T4 has no tests: Maat's best outcome there is
`NEEDS_VERIFICATION`, by design.

## Procedure

[`run-bench.sh`](run-bench.sh) is the procedure; in short:

1. **Schedule.** `run-bench.sh schedule <seed>` shuffles the 30 runs (5 tasks × 2 sides × 3). The seed is the
   full id of the commit that freezes this document, so it is fixed before anyone can see a run. The runs are
   launched in that order, N at a time (`run-bench.sh all <N>`).
2. **Clean copy per run.** The starting commit is exported with `git archive` into a new repository with one commit
   at a fixed date (same commit id for every copy of a task, no upstream history, no remote). The environment is
   prepared before the run: a venv with the project installed (T1, T5), `go mod download` (T2), a `node_modules`
   installed once with `--ignore-scripts` and copied (T3), nothing (T4). The spec is copied to
   `.claude/.ai-workflow/`; on the Maat side the plugin and the task's `maat.json` are added.
3. **Run.** One command per side (above), with the 4-hour cap. Nobody intervenes during a run.
4. **Collect.** The final diff (`.claude/` excluded), its hash, the report (Maat: the spec with plan, review and
   evidence written by Maat, and the driver's last line; baseline: the session's final message), cost and time,
   the versions; [`run-record.md`](run-record.md) lists every field.
5. **No run is repeated or discarded.** A run that fails, stops or hits the cap is recorded as it is. A copy or a
   record folder that already exists makes the script refuse.
6. **After all runs:** the hidden tests on every final tree, then the blind review, then the adjudication; then
   the results are added below with all raw records.

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

## Threats to validity (in addition to the protocol's)

- All five specs, the hidden tests and the `maat.json` files are written by the author of Maat.
- T2 and T5 have public upstream fixes after their starting commits (see Tasks).
- The adjudicator of undisclosed defects is not blind to the side (the two kinds of report look different); the
  rules are literal and every decision is published with its quote.
- Three runs per side and task show the spread, they do not support a statistical test.
- On a subscription, parallel runs share the usage quota: a run slowed by the quota is still recorded.

## Results

Not available yet.
