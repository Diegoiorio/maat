---
name: flusso-h
description: Flow H — implements ONE of Maat's already approved plans (docs/piani/maat-pkNN-*.md of this repo) on a working branch of the maat repo, with the maat:plan-implementer and maat:implementation-reviewer agents of a fixed version (plugin installed from a tag), the plugin tests, the releasability acceptance check, a commit on the branch and the revision of the following plans. It does NOT use /maat:full-implementation-cycle (its subsessions would load the plugin being modified). Accepts one or more plans in sequence; the first STOP halts the chain.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, BashOutput, Agent, Monitor, TaskStop
argument-hint: "pkNN [pkMM …]"
---

# Flow H — implementing Maat's plans

Input: `$ARGUMENTS` — one or more plan identifiers (`pk10`, `maat-pk10`, or the file path). Several plans run **in
sequence, in the given order**; the first STOP halts all the following ones.

**Where to run it.** From inside the maat repo folder: `cd <maat repo>`, then `claude`, then `/flusso-h pkNN`. The
skill belongs to this repo (`.claude/skills/flusso-h/`), not to the plugin: it does not exist anywhere else. Do
**not** launch it with `claude --plugin-dir <maat repo>/plugins/maat`: `--plugin-dir` is for trying things by hand,
not for running the cycles (see step 1).

**It is a tool for those who develop Maat**, not for those who use it. Plans are the maintainer's working notes and
**are not published**: they are written in `docs/piani/` of your own copy of the repo (`maat-pkNN-<title>.md`; the
first plan creates the folder). They are **already approved**: no planning phase, no rewriting of the plan. The
«Note da piani precedenti» (notes from previous plans) section, if present, **overrides** the steps it corrects. A
deviation from the plan is a STOP for the user.

**Guide project** (or test bench): a real project that uses Maat, with already closed cycles, on which every change
is acceptance-tested. Always work on a copy of it, never on the real project.

## Why not `/maat:full-implementation-cycle`

Its subsessions load the plugin enabled in the project. If that plugin is the very code being modified (a folder
marketplace or `--plugin-dir` on the branch), the cycle would change under its own feet: that is the incident of the
harness changed under a cycle (measurements of four cycles skewed). In flow H the harness being modified is
**tested**, never **used** to implement itself: the agents come from a **fixed** version (the plugin installed from
a tag), never from the branch folder. Step 1 checks this.

## Firm rules

- Work **only on a working branch** of the maat repo (for example `wip/pkNN`, preferably in a worktree
  `../maat-pkNN`), never on `main`. A linked worktree and the main tree are not mixed: each does its own things.
- Commit **only** on the working branch, one per closed plan. **Never** push, **never** merge into `main`, **never**
  published tags, **never** `git reset --hard`/`rebase`/`stash`: push, tags and integration are done by the user only.
- The **test bench** is the guide project: replays and acceptance checks run on a **copy** of it (a clone in a
  temporary folder, with the run dirs of the closed cycles), never on its tree, which stays read-only. No access to
  production, no sync to remote environments, no DB writes, no installations, except those the plan explicitly
  authorizes or the user confirms (the plugin in step 1).
- **Never fast mode** (`fastMode`) and no lever that requires spending: the user's decision.
- Acceptance replays run with `--no-dev`.
- Write files with Write/Edit, never with Python heredocs (invisible bytes). LF line endings.

## The 9 steps (for each plan)

1. **Preparation**
   - If the worktree does not exist: `git worktree add ../maat-pkNN -b wip/pkNN main` from the root of the maat repo;
     if it exists, enter it and check that `git branch --show-current` is the plan's branch.
   - No live cycle on the test bench copy: `cd <copy> && bash <maat repo>/plugins/maat/scripts/run-phase.sh
     --lock-status` must say `libero` (free), and no `.claude/.ai-workflow/spec-*.run/log/*.running` without its
     `.exit`. Otherwise: if the plan modifies files that cycle uses, wait (Monitor) or STOP with the reason.
   - **This session's plugin comes from a fixed version** (rule "the harness being modified is tested, not used").
     Checks, all read-only:
     - `~/.claude/plugins/installed_plugins.json` (source verified in pk01, D6): the `maat` entry valid for this
       folder (scope `user`, or `project`/`local` with `projectPath` equal to the folder), with `version`,
       `installPath` and `gitCommitSha`. `claude plugin list --json` may give the same, but its format **is not yet
       verified**: when in doubt the file wins. The `maat:*` agents come from `installPath`, **except** with a folder
       marketplace: there the code runs from the source folder (D6 f), which must therefore be checked as in the
       next point.
     - The source of the `maat` marketplace (`~/.claude/plugins/known_marketplaces.json` and `extraKnownMarketplaces`
       in the project settings): git or URL with the `ref` of a **tag** ⇒ fine. **Folder** ⇒ fine only if it is a
       folder locked to the tag (`git -C <folder> describe --exact-match --tags HEAD` succeeds and `git -C <folder>
       status --porcelain` is empty, like a `maat-vX.Y.Z` folder) and is neither this worktree nor the main tree of
       the maat repo. `maat-doctor.sh` flags it with the ATTENZIONE line «plugin installato da un marketplace da
       cartella» (plugin installed from a folder marketplace): that line asks precisely for this check.
     - The command line of this session's `claude` process (read-only: `ps -o args=` on Linux and Mac,
       `Get-CimInstance Win32_Process` on Windows) does not contain `--plugin-dir` pointing to the maat repo or one of
       its worktrees. If it cannot be read, ask the user.

     **STOP** if the plugin comes from the branch being modified (folder marketplace pointing to the repo or one of
     its worktrees, `--plugin-dir` on the branch, a `ref` that is a branch and not a tag) or if it is not installed.
     In the message: the command to install it from a tag and the **scope**. Recommended form, **tried** on
     2026-10-30 (installation and switch to a new tag): the GitHub source with the tag, `claude plugin marketplace add
     https://github.com/Diegoiorio/maat.git#vX.Y.Z --scope local` and `claude plugin install maat@maat --scope local`.
     Alternatively, without network: a folder locked to the tag (`git -C <maat repo> worktree add --detach
     ../maat-vX.Y.Z vX.Y.Z`, then `marketplace add <that folder>`). The recommended scope is `local`, run from the
     maat repo folder: it writes to `.claude/settings.local.json` of this folder and to `~/.claude/plugins/` (cache,
     `installed_plugins.json`, `known_marketplaces.json`). `--scope user` would instead write to
     `~/.claude/settings.json` and apply to all projects; `--scope project` to the repo's `.claude/settings.json`,
     which is tracked. Installing **is done only with the user's confirmation**, and the installation is declared in
     the report (the acceptance check needs it, point c).
   - **Session guard.** If the installed plugin is enabled in this session, its guard is hooked in (`maat-doctor.sh`:
     «guardia agganciata», guard hooked). If it is not, say so in the report and behave as if it were anyway: no
     command among those of the firm rules.
   - **Record the starting state**, for the acceptance check (step 6, points b and c): `git status --porcelain` and
     `git stash list` of the guide project's tree; the sha256 of `~/.claude/settings.json` and of
     `~/.claude/plugins/installed_plugins.json`, and the entries of `~/.claude/plugins/known_marketplaces.json`
     **without** the last-update date fields. Not all of `~/.claude/plugins/`: Claude Code writes there on its own
     during the session (cache, marketplace updates), and those writes are not a change made by the flow.
2. **Prerequisites**
   - The plan must have the line `**Plan status: APPROVED**`. If it is missing (or says something else) ⇒ STOP: "the
     plan is not approved". Flow H does not approve plans.
   - Read the plan's `Prerequisiti:` (prerequisites) line and run `git log --oneline --grep "pkXX"` on the branch for
     each one. One missing ⇒ STOP: "run pkXX first".
   - Read the whole «Note da piani precedenti» section.
3. **Implementation in blocks** — split the «Passi di implementazione» (implementation steps) into 1–3 coherent
   blocks (if the plan already states the blocks, use those) and launch one `maat:plan-implementer` agent per block,
   in order. Pass each one:
   - the plan path, specifying: "the plan is the `## Passi di implementazione` section; the requirement is everything
     before it, “Note da piani precedenti” included, which override; ignore the references to `spec-<name>.md` in
     your instructions";
   - mode `full` (or `completion` if the branch already has changes of this plan from an interrupted attempt);
   - "Block k/N — only steps x–y are yours";
   - "the gates are the plugin tests: the suites of the files you touch and the plan's new ones (section `## Test`),
     run as `docs/TESTING-harness.md` says; not a project's suites, unless the plan names them";
   - the previous block's report as orientation (the code wins over the report).

   Deviation from the plan, `Bloccato su` (blocked on) other than `nessuno` (none), or a second `PARZIALE` (partial)
   ⇒ STOP.
4. **Plugin tests**
   - During implementation and fixes run **only the suites of the touched files** (and those that depend on them),
     one at a time: `bash plugins/maat/scripts/<name>.test.sh`. Always also `genericita.test.sh` and
     `maat-paths.test.sh`.
   - **At the end of the plan, a full run** of all the package's suites (`plugins/maat/scripts/*.test.sh`,
     `plugins/maat/skills/**/*.test.sh` and `test-review-surface.sh`), on Windows and on Linux, as
     `docs/TESTING-harness.md` says («Windows and Linux», «The full run»): the long ones (`cycle-state`, `run-phase`,
     `driver`) in parallel in the background, collected before deciding, or one at a time as the full-run script
     does. The review reads the outcomes of that run and reruns only what it has to verify.
   - Plus the plan's new tests, with their **mutation counterproofs**: the mutation is applied (on a copy), the test
     turns red, the mutation is removed. The command and the outcome go in the report.
   - A red ⇒ fix (one round of `maat:plan-implementer` in `fix`) and repeat; at the second red on the same test ⇒
     STOP.
5. **Independent review** — `maat:implementation-reviewer` agent with: the plan (as spec + plan), the branch diff
   against the previous commit, the outcomes of the tests of step 4. Blocker/major ⇒ `maat:plan-implementer` in `fix`
   with only those findings, then a new review. **At most 3 rounds**; at the third without APPROVED ⇒ STOP with the
   open findings. Minor/nit: noted in the report, not applied.
6. **Releasability acceptance check** — the points of the plan's `## Collaudo` (acceptance check) section, plus
   these **three common points**, always:
   - a. **revert test:** in a throwaway copy (a worktree of the maat repo at the plan's state), the plan's changes are
     removed (`git revert --no-commit` of the plan's commit, or the diff applied in reverse): the suites of the
     previous plans must turn green again; then the copy is deleted;
   - b. **guide project intact:** in its tree `git status --porcelain` and `git stash list` equal to those recorded in
     step 1;
   - c. **user state:** `~/.claude/settings.json`, `installed_plugins.json` and the entries of
     `known_marketplaces.json` (without the dates) equal to those recorded in step 1, except for the installations
     planned by the plan or confirmed in step 1, and declared.

   Those the plan assigns to the user (for example an installation to follow by hand) are listed as "to do with the
   user", not simulated. A failed point ⇒ no commit, the branch goes back to the previous commit (`git checkout
   -- .` in the worktree and removal of only the plan's new files), STOP with report.
7. **Commit** on the working branch: `pkNN: <plan title>` + a body with the review outcome, acceptance check and
   measurement, + the attribution lines required by the session. Never `--no-verify`.
8. **Revision of the following plans** — for each plan listed in «Dopo l'implementazione, rivedi» (after
   implementation, review): reread it and, if this part changed something it uses (interface, file, command, format,
   name), add at the top of the next plan, in `docs/piani/` on the same branch, a `## Note da piani precedenti`
   section with: what changed, in which commit, and how the affected step adapts. Do not rewrite the approved steps:
   annotate. If the adaptation changes the substance of the plan ⇒ flag it in the report as a decision for the user.
9. **Report** — add a section to `docs/piani/maat-report.md`: plan, commit, review outcome (rounds), acceptance check
   (the plan's points and the three common ones), measured benefit, annotated plans, open minor/nit, installations
   made (with the scope), time and quota consumed, proposed lines for `CHANGELOG.md`.

## STOP (halts the plan and the whole chain of requested plans)

Plan not approved · missing prerequisite · session plugin not from a fixed version · live cycle on the test bench
copy · deviation from the plan · plugin test red twice · 3 review rounds without APPROVED · failed acceptance check
· substantial adaptation of a following plan · quota over threshold. Every STOP writes the reason in the report and
tells the user what to decide or run.

## Quota (subscription, no spending)

Read the available quota events (`rate_limit_event` in the replay logs, or the session's indication):
- above ~75% of the 5-hour window ⇒ pause until the reset (Monitor on a wait, not active polling);
- above ~30% of the weekly quota ⇒ STOP with report, to leave quota for the rest of the work.
Acceptance replays are **per phase** and on small cycles of the test bench, one per plan.

## Final answer

```text
Flow H — <requested plans>
Outcome: <per plan: COMMITTED <sha> | STOP (<step>: <reason>) | NOT STARTED (chain halted)>
Review: <rounds, findings closed>   Acceptance: <plan points + 3 common: outcome | to do with the user: …>
Measurement: <observed vs expected benefit>
Annotated plans: <pkXX: what>   Decisions for you: <none | list>
Plugin: <version and source of the plugin used; installations made, with the scope>
Report: docs/piani/maat-report.md
Branch: <wip/pkNN> (no push, no merge, no published tag: integration is your call)
```
