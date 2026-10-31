# Gates run by the model (the declared remote verification)

Read when the level's suites have no `FRESH` driver evidence (a review by hand, a driver `BLOCKED` to re-run, a
scope path missing from the driver's `argomenti.txt`, `STALE`), and for every plan gate outside the driver's
VERIFY (e2e, DB checks, measurements). The required-gate list and the result vocabulary are in `SKILL.md`.

Unless `--no-dev` was set, run the gates as a SEPARATE step (the reviewer stays static). Pass
the declared remote verification (`verifica_remota` in `.claude/maat.json`) the **paths in scope** from the snapshot — never let it recompute from `git diff`
(it would miss untracked test files) — **and the snapshot's `Base:`**, which `--lint` needs to tell an
error you introduced outside the module's `radice` from one that was already there.

**Gates of different modules start together**, and all are collected before anything is decided:
they use disjoint resources (a module without `copia` reads the working tree; the module with `copia` runs on
its local copy, which holds only its `radice_pacchetti`). The remote verification does this itself — do not serialise it by asking for
one mode at a time.

**Lint outside the `radice`.** The `lint` gate covers what the CI covers, the module's `radice`. For a lintable
file the plan touched in another package, the remote verification reports a classification instead of silence:
`INTRODUCED` (absent from the base) makes the gate **FAIL** like any other lint error — it is a defect
this work added, and the CI not looking at it is not a reason to accept it; `PREEXISTING` is recorded as
a note and blocks nothing; `UNRESOLVED` (not classifiable) is a `BLOCKED` gate, so the verdict is
`NEEDS_VERIFICATION`, never `IMPLEMENTED`. A package with no eslint configuration is `SKIPPED`, which
here is true: there is nothing that could be run.

**OPTIONAL gates** (reported, never block, never promote): direct importers of changed shared
modules (the remote verification selects ≤10 and declares any truncation) · an e2e requested only via
`--with-e2e` and not prescribed by the plan. Below `full` the lint does not run at all.

**A required gate that is `SKIPPED` with its reason and its paths is satisfied**, exactly like `PASS`, in
the decision table below: `SKIPPED` means "there was nothing to run", not "it could not run" (that is
`BLOCKED`). It is the normal outcome of the `full` lint on a backend-only change, of a change with no
lintable extension, and of a package that has **no eslint configuration at all** — there, nothing could
be run even in principle. Absence of applicable work is not absence of evidence; what must never be read
as evidence is a gate that was blocked or never attempted.

⚠️ **One `SKIPPED` is not satisfied: a lintable file outside the `radice` that was never classified.**
Before, "outside the CI's lint perimeter" was listed here as a normal `SKIPPED`; it is not, because the
file *could* have been checked. The remote verification's lint now classifies those files against the snapshot's
`Base:` (`INTRODUCED` → `FAIL`, `PREEXISTING` → a note, `UNRESOLVED` → `BLOCKED`), and the wrapper's line
says how many it classified. If the line reports lintable files outside the `radice` with **no**
classification — because `--base` was not passed, or the run fell back to `/mnt/c` — treat that gate as
**`BLOCKED`**, not as satisfied: the verdict is `NEEDS_VERIFICATION` and the remedy is to re-run the lint
with `--base`. A surface nobody looked at is not a surface with nothing to look at.

**e2e.** Never run the broad suite here. An e2e **prescribed by the plan** (at `full`, one targeted
spec; at any level, an `[e2e-locator: <spec>]` line, at most 2) is a required gate and runs via the remote verification with `--e2e <spec>`. Otherwise e2e runs only
on explicit request (`--with-e2e`), one spec mapped to the touched flow. The e2e runs on the DEV
host, which is not a git checkout: the remote verification's e2e must first bring DEV to the snapshot and
**prove it** (see its "e2e" mode); a run on code that is not the reviewed snapshot is `BLOCKED
(DEV not at snapshot)`, never `PASS`.

**Plan gates the remote verification cannot run** (a counterproof — the named files reverted to base, or a named
mutation applied to them —, a manual measurement) and any
gate re-run by the user outside the session (e.g. the container command of a BLOCKED line). A
gate is `PASS` with one of these kinds of evidence, and the evidence table says which:
- **driver** — only for the level's suites: `evidence/<key>/<gate>.json` written by `gates.sh`, with the
  key `FRESH` (see "Evidence from the driver" above) and the runner's report next to it;
- **observed** — command and output seen in this session, after the last change to the scope;
- **user-reported** — the user pastes the command and its output (`PASS (user-reported)`). The user
  is the authority on their own environment; an **agent's** claim without output is not evidence
  and stays `NOT RUN`.
This skill never runs a counterproof itself (it would modify source files): the implementer runs
it, and its output reaches this skill through one of the two channels above.

A plan gate with `red if: <condition>` (or `rosso se:`) (plans since 2026-09-21) states the world in which it goes
red: when the evidence is a counterproof, check that the red observed is **that** red.

**Result vocabulary per gate** (keep them distinct — absence of evidence is not evidence):
`PASS` ran and passed · `FAIL` ran and failed on the code · `BLOCKED` could not run or not
conclusive (environment: tunnel down, WSL timeout, Node missing) · `SKIPPED` nothing to run (no
test exists for the touched files — declared, never silent) · `NOT RUN` not attempted (`--no-dev`,
or a plan gate without observed evidence).

A timeout or a setup failure of the runner is `BLOCKED`, never `FAIL`: on `/mnt/c` vitest can be
~100× slower than in the container (`vitest.config.ts`), and a test that times out there accuses
code that is fine. The BLOCKED line carries the equivalent container command, so the user can run
it and paste the result (user-reported evidence), or simply re-invoke later.

**Gate artefacts.** Some gates write files (a first vitest run creating `__snapshots__`, coverage
output). This skill does not delete them (it never modifies the working tree): list them in the
evidence table and hand them to the implementer. An auto-written snapshot is precisely a test nobody
reviewed — it makes the Step 3 check stale, which is correct: `IMPLEMENTED` waits until the
implementer has either removed it or accepted it and it has been reviewed.
