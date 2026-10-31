---
name: plan-review-cycle-light
description: Lightweight, pragmatic variant of plan-review-cycle. Turns a specification into an approved implementation plan using the local spec-plan-reviewer-light agent, writing the plan as a section INSIDE the spec file. Use for smaller/lower-risk changes where the full review is overkill.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
argument-hint: "<path to spec-<name>.md, or pasted specification text> [--tests=min|std|full]"
---

# Plan Review Cycle (light)

Radice del plugin: `${CLAUDE_PLUGIN_ROOT}`. Nei file di questa skill che leggi con Read, `${CLAUDE_PLUGIN_ROOT}` vale questo percorso: sostituiscilo prima di eseguire un comando.

Prima di ogni comando Bash o PowerShell, scrivi `description` secondo `${CLAUDE_PLUGIN_ROOT}/docs/descrizione-comandi.md`.

This skill follows `plan-review-cycle` in structure and rules **with two declared exceptions**:

1. it uses the **`spec-plan-reviewer-light`** agent (concise, pragmatic; deep architectural
   review only when the change touches permissions, database, API contracts, imports, shared
   business logic, auth, or persistent state);
2. it does **not** take the fan-out, the delta review or the fresh-eyes gate — see
   §"What this branch deliberately does NOT take". **Every round here is full scope.**

⚠️ Consequence for the loop: where `plan-review-cycle` Step 3 says *"return to Step 2-bis"* and
*"repeat Step 2-bis → Step 3"*, **this branch returns to the full-scope review of
§"The reviewer"** instead. Step 2, Step 2-bis and Step 2-ter of the full skill do not apply here.

**Format 2 (every new plan): this branch is decided by the files, not chosen (L5).** After Step 1,
run `plan-check.sh route <spec>`: only `Percorso: leggero` (plan ≤150 lines, no migration, no surface
detected, `Risk surfaces: none`) keeps the plan here; `Percorso: pieno` — any discordance —
continues in `plan-review-cycle` from its Step 2, on the plan already written, and says so in one line.
In format 2 this branch also takes `lint2` before every round, `gen` at approval and the budget of **4**
iterations ("Plan format 2" in `plan-review-cycle`); every round stays full scope, with no S2. A
format-1 plan keeps this file as it is.

The user input is:

$ARGUMENTS

## What is identical to plan-review-cycle

Follow `plan-review-cycle` exactly for all of the following (do not diverge). Since harness-pt14 the author's
rules named below (§"Test effort", "Plan format 2", the risk-surface vocabulary, "Reading", "How to revise") live
in `plan-review-cycle/autore.md`, and the plan-check commands in its `SKILL.md`:

- **Single writable artifact**: `.claude/.ai-workflow/spec-<name>.md`. The plan lives inside
  it as the `## Implementation plan` section with a line-anchored, single-occurrence
  `Plan status: DRAFT | APPROVED | NEEDS HUMAN DECISION`. Never modify the specification
  sections or any `## Implementation review` section.
- **Languages (Maat 1.3.0)**: headings and keywords are written in English (full branch, autore.md
  «Languages»); the Italian ones of older specs (`## Piano di implementazione`, `Superfici a rischio:`,
  `[pavimento:`, `rosso se:`…) are still read. A section that already exists keeps its heading: English only
  for a section created new, never both.
- **Resolving `<name>` and ensuring the container exists**: from an existing `spec-<name>.md`
  path (strip `spec-`), or from pasted text (slug from title, else ask a short `<name>` at
  invocation time) — then create `.claude/.ai-workflow/spec-<name>.md` with minimal spec
  sections before writing the plan section. One spec file = one feature; no `-2/-3`
  disambiguators.
- **Autonomous execution**: run plan → review → revise → review back-to-back, no pauses.
- **Stop conditions**: `APPROVED`; `STOP_HUMAN_DECISION_REQUIRED` / hard stops; or **10
  effective iterations** → `NEEDS HUMAN DECISION`. No special early stop tied to an iteration
  number. The ceiling is the same in both branches: no spec has ever reached it (max 9 across
  21), so lowering it would cut real rounds — the only genuine loss of coverage available.
- **Severity policy**: the verifiable-anchor contract (`code` · `spec/plan` · `absence` ·
  `measure`), **verify before applying** (reject only on a literally false anchor, never on
  reasoning), and **optional findings never applied** — they stay in the changelog as notes for
  the implementation.
- **Approval binds the plan**: at `APPROVED`, the `Approved basis: spec <fp> · plan <fp>` line from
  `plan-check.sh basis`, right under `Risk surfaces:`, and `basis` must then say `FRESH`
  (full branch, Step 3). Without it the plan stays legacy and nothing downstream can tell a later
  edit of the spec or plan.
- **Surgical revision**: each blocking finding applied as one minimal, localized Edit — never a
  rewrite of the section — and every list or count it writes measured by a search first.
- **Recurrence enforced by the orchestrator** (stable `<area>/<claim>` key plus anchored
  symbol/path, never a line number; two consecutive runs of the same producer →
  `STOP_HUMAN_DECISION_REQUIRED`; `reintrodotto` is a label, not a stop), never delegated to the
  stateless reviewer.
- **Risk surfaces**: the single vocabulary of Step 0, the `Risk surfaces:` line, the
  `[floor:` floor for critical surfaces (or the `⚠️ Surface <token>` line, an obligation
  downstream unless waived with `— static sufficient: <reason>`), `red if:` on every new case,
  and `### Requirement traceability`.
- **`plan-check.sh lint --baseline <copy>`** after Step 1 and after every revision — the copy is
  taken in the scratchpad just before writing, exactly as in the full branch; **re-opening** as
  the only way to amend an approved plan (here the re-opened round is a full-scope one, like
  every round).
- **The metric line** at the end of the changelog.
- **Plan sized to the change**: a section with nothing to say gets one line,
  `no implication`, not filler prose.
- **Reading** (full branch, Step 1, "Reading, in this step and in every revision"): targeted first,
  no stale re-reads or quotes by the scoped staleness rule, batch only independent calls.
- **§"Test effort" in full**: the `--tests=min|std|full` parsing with its Italian aliases, the
  default `std`, the per-level caps, the `Test level:` line written under `Plan status:` with its
  anti-collision clause, and the three constraints on the test plan (suite selection follows the
  diff · no whole-suite gate below `full` · never prescribe `/browser-qa`).
- **Reviewer output contract**: consume the reviewer's `Decision:` line directly.

## What this branch deliberately does NOT take

The light branch keeps **every round at full scope, exactly as today**:

- **no three-lens fan-out** — the fan is a device for large plans; here it would spend three
  reviewers on a small one;
- **no delta review** from round 2 — rounds stay full scope;
- **and therefore no fresh-eyes gate**, which exists solely to offset the narrowing that the
  delta review introduces. With no narrowing it is pure cost: on a one-round cycle it would add
  ~44% in tokens. The full branch's second trigger (round 1 approved outright on a critical
  surface) does not apply either: a critical surface is a reason to take the full branch in the
  first place (Step 0), not a reason to graft the gate onto this one;
- **no `xref` lines** — they complement a delta range, and here there is none.

Consequence to be aware of: on small changes the structural saving is **zero**. What this branch
gains is the free part — anti-stall (no more rounds lost to the 600 s watchdog), surgical
revision, optionals left as notes, enforced recurrence. The one real saving is a round avoided.

## ⚠️ A partial review is NOT an approval — and here it matters MORE, not less

This branch instructs the reviewer to deliver `Blocked on: <reason>` with a coverage statement
rather than dying silently. So a reviewer that runs out of budget having found nothing will
return `APPROVED` while declaring it covered only part of its mandate. **Read the coverage
statement, not just the `Decision:` line.**

- `Decision: APPROVED` accompanied by `Blocked on:` or by a coverage statement declaring
  uncovered ranges **does not set `Plan status: APPROVED`**;
- re-run the reviewer to **complete the interrupted round** on the uncovered ranges — this is
  coverage completion, **not** a delta round, so it does not contradict "every round here is
  full scope";
- **one** free re-run only; a second partial on the same range counts as a full iteration, a
  third stops with `STOP_HUMAN_DECISION_REQUIRED`.

In the full branch a partial round can still be caught downstream by the fresh-eyes gate. **Here
there is no gate, ever** — so this rule is the only thing standing between a partial round and an
approved plan.

## The reviewer

Every review round of this branch — the first and every later one — invokes the
**`maat:spec-plan-reviewer-light`** agent at full scope, with this instruction:

```text
Use the maat:spec-plan-reviewer-light agent.

Review the specification and the proposed implementation plan against the local codebase
and existing project patterns. Both live in the same file; the plan is the
"## Implementation plan" section ("## Piano di implementazione" in an older spec: English and Italian headings
and keywords are both valid, the same section in both languages is a finding). Keep the review concise and pragmatic; do not suggest
large refactors unless strictly necessary. Do not implement anything. Do not modify files.

Spec + plan file:
.claude/.ai-workflow/spec-<name>.md

Read these ranges only (never the whole file): spec <offset/limit>, plan <offset/limit>.
From round 2, add: "Already resolved — do NOT re-raise: <finding key + anchored symbol/path +
one line each>. Rejected — anchor found literally false, re-raise only with NEW evidence:
<key + refutation each>."

Tool-call budget: ~20, as a SOFT threshold. At the budget, if you hold an unverified lead on a
possible blocker, say so and continue up to +50%; otherwise stop and write what you have.
Batch independent Read/Grep/Glob calls in one message; after every message with tool calls, emit
one line of text. The budget counts calls, not messages. If you cannot continue, deliver a partial
with "Blocked on: <reason>" and your coverage. Open with a coverage statement, and say "class N:
nothing" explicitly when a class is clean.

The plan declares `Test level: <lvl>`. Over-testing is a finding of the same severity as
under-testing: a case duplicating existing coverage, a case on code the plan does not change, an
e2e where a unit test suffices, a whole-suite gate below `full`, or a `/browser-qa` prescribed at
all. If the plan prescribes more than its declared level allows, say so.

A line marked "[floor: <surface>]" ("[pavimento:") is the one verification owed to a critical surface: it is
exempt from the caps — check only that it is pertinent and can go red. A "⚠️ Surface <critical
token>" line instead of a floor is a human STOP downstream; its "static sufficient:" waiver holds
only if the change leaves that surface's runtime behaviour untouched. Every new case states
"red if:" ("rosso se:"); check that the condition is real. Search every string, class or attribute the plan
changes in e2e/specs/ and tests/: a hit in e2e/specs/ needs an "[e2e-locator: <spec>]" line (any
level, outside the caps, at most 2), and a counterproof must name the file(s) it touches — reverted
to base, or a named mutation when the test imports what the feature adds. The length of
"### Test plan" alone is never a finding.

minor and nit do NOT block and must not be promoted to major. Every blocker/major carries an
"Anchor (<kind>):" — code path:line · spec/plan line that contradicts or omits something
checkable · absence (pattern + scope + 0 results) · measure. No anchor → optional. Do not
fabricate findings to justify another round: if the plan holds, APPROVED is the correct answer.

Return your canonical contract (Decision / Coverage statement / Blocking findings / Optional
findings with Severity). Only blocker and major findings block approval.
```

## Final response

Same structure as `plan-review-cycle`. If approved, recommend:

```text
/maat:implementation-review-cycle <name>
```
