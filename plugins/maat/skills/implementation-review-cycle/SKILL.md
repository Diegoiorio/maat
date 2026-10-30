---
name: implementation-review-cycle
description: Runs a bounded implementation review of the current working-tree changes (staged, unstaged and untracked) using the local implementation-reviewer agent, plus the required test gates, and binds the verdict to a snapshot fingerprint. Accepts the plan by NAME (reads the approved plan from spec-<name>.md) or as pasted plain text. Use after implementing an approved plan.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, BashOutput, Task
argument-hint: "<plan name> | <pasted plan text> [--tests=min|std|full] [--no-dev] [--light] [--with-e2e] [--base=<ref>] [optional extra context]"
---

# Implementation Review Cycle

Radice del plugin: `${CLAUDE_PLUGIN_ROOT}`. Nei file di questa skill che leggi con Read, `${CLAUDE_PLUGIN_ROOT}` vale questo percorso: sostituiscilo prima di eseguire un comando.

Prima di ogni comando Bash o PowerShell, scrivi `description` secondo `${CLAUDE_PLUGIN_ROOT}/docs/descrizione-comandi.md`.

You orchestrate a bounded implementation review: the **review surface** of `review-surface.sh` (never a bare
`git diff`) against an approved plan, by the local `implementation-reviewer` agent, plus the gates the plan
requires. `Feature status: IMPLEMENTED` means both: the static review approved the surface **and** every required
gate passed on that same surface — absence of evidence is never written as evidence. This skill never modifies
source files and never applies findings: it writes only the spec's `## Review implementazione` (mode a).
Read only when this file sends you there: `freschezza.md` (a section with a `Reviewed snapshot:`),
`gate-manuali.md` (gates run by the model), `light.md` (`--light`, by hand); the reviewer reads its own mandate
in `prompt-revisore.md`. What moved into code, with its test: `${CLAUDE_PLUGIN_ROOT}/skills/full-implementation-cycle/
riferimento.md`, «Regole in codice».

User input:

$ARGUMENTS

## Inputs

- **Mode (a), by name**: `.claude/.ai-workflow/spec-<name>.md` with `^Plan status: APPROVED` in its plan
  section, else stop (complete `/maat:plan-review-cycle` first). Specification = the sections above
  `## Piano di implementazione`; approved plan = that section; output = the review section of the same file.
- **Mode (b), pasted plan**: no status preflight; the reviewer runs plan-only; output in the conversation only,
  never a file; declare `Review basis: PLAN_ONLY — requirement completeness NOT verified` and «no persistent
  snapshot: freshness and promotion are not available». Level `legacy` (or `--tests`); the pasted gates are the
  plan gates, its `⚠️` lines risk focus, never an obligation.
- **Flags**: `--no-dev` (no execution gates: at most `NEEDS_VERIFICATION`) · `--with-e2e` (one targeted e2e, an
  optional gate) · `--base=<ref>` (surface against `merge-base <ref> HEAD`) · `--tests=…` wins over the plan's
  level for this invocation (never rewritten) · `--light` → `light.md`.

## The section (mode a)

```text
## Review implementazione          ← OWNED by this skill
Review status: APPROVED | NEEDS_CHANGES | NEEDS HUMAN DECISION
Feature status: PLANNED | NEEDS_VERIFICATION | IMPLEMENTED
Verification: VERIFIED | PARTIAL (<required gates not passed>) | NOT RUN (<reason>)
Review basis: SPEC+PLAN
Reviewed snapshot: base <sha> · tree <sha> · fingerprint <fp12> · <n> paths
Reviewed contract: spec <fp12> · plan <fp12>
Review rounds: <n>/3 · post-approval NEEDS_CHANGES: <k>/1
<evidence table, finding table, findings, manifest>
```

- Status lines line-anchored, single occurrence; quoted prose never reproduces their prefixes. Never touch the
  spec sections nor the plan section.
- The **finding table** (`key · severity · state OPEN|RESOLVED|REINTRODUCED`, one row each, no prose) and
  `Review rounds:` are the counters across sessions: read them at Step 1 (a legacy section starts at round 1).
- `Reviewed contract:` = the `Basis:` of `plan-check.sh basis` at Step 1, re-checked at Step 3.
- **Manifest**, after the snapshot line: `<details><summary>Manifest (<n> paths)</summary>` with `Scope:` (the
  reviewed paths; a rename: both) and `Excluded:` (another flow's), one path per line — data for freshness. The
  fingerprint is `review-surface.sh fingerprint --tree <Tree> --paths-file <scope list>`.

## Hard rules

- At most **3** review iterations per plan; post-approval delta rounds have their own budget (`freschezza.md`);
  promotion runs cost none. Empty surface → stop. Nothing outside the approved plan.
- The reviewer never modifies files nor runs tests. Only `blocker`/`major` block; `minor`/`nit` are reported,
  never applied.
- **Recurrence is yours** (the reviewer is stateless): from round 2 pass the resolved findings (key + one line)
  with «do not re-raise unless present in the current code», and the delta computed by the script. Key
  `<area>/<claim in 5 words>@<symbol>` (`file:line` is only the current evidence). A resolved finding comes back
  only as `REINTRODUCED`, with current `file:line`: an ordinary blocking finding. The same blocker/major, still
  `OPEN`, in two consecutive runs of the same producer → `NEEDS HUMAN DECISION`.

## Step 1: preflight and surface

1. `bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-phase.sh" --lock-status`: exit 1 → stop (a cycle is changing
   the tree: say who, re-invoke later); `dentro il ciclo` → go on.
2. Mode (a): `plan-check.sh basis <spec>`: `STALE` → stop, the plan must be re-opened; `FRESH`/`LEGACY` → keep
   `Basis:`. Then `plan-check.sh contract <spec>` (exit 1 → stop): `Test level:` (`legacy …`: no caps, the plan's
   own gates are the authority; `duplicata` → say so) · `Superfici a rischio:` risk focus · `Pavimento:` a plan
   gate · `Obbligo:` an obligation row · `Statica sufficiente:` no obligation · `Rischio: riga N` a risk focus,
   echoed in the final response · `Piano di test: offset/limit` every gate there is a plan gate ·
   `Tracciabilità requisiti: offset/limit` the requirement list, passed as is.
3. `bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-surface.sh" snapshot [--base <ref>]` → `Base`, `Tree`,
   `Changes`, `Origin`. Empty `Changes` → stop (work already committed: suggest `--base`).
4. **Scope** = `Changes` minus your exclusions, each written `Excluded from scope: <path> — <reason>` in the
   prompt and the final response — never silent. **Never exclude** a path of the touched list (the caller's,
   else `<run-dir>/touched.txt`), a path the plan names, or a mixed file (it stays; the prompt says which hunks
   are another flow's). A **new** file not in the touched list may be excluded only if the plan does not name
   it (nor its directories) **and** two greps find no link (its name in no in-scope file, no in-scope name in
   it) — both greps in the reason.
5. Scope list in the scratchpad (never in the repo); `review-surface.sh test-signals --from <Base> --to <Tree>
   --paths-file <scope>`; `review-surface.sh diff --from <Base> --to <Tree> --paths-file <scope> --out <scratch
   diff>` — its index goes in the prompt.
6. The section already has a `Reviewed snapshot:` line → read `freschezza.md`: full round, delta round,
   gate-only path or promotion path.

## Step 2: the reviewer

«Use the maat:implementation-reviewer agent. Read `${CLAUDE_PLUGIN_ROOT}/skills/implementation-review-cycle/prompt-revisore.md` and
follow it.» plus its parameters: the specification (mode a: its range; mode b: NONE) and plan ranges; the
scope's `Changes`; the exclusions; the diff file and index; the context pack, if it exists; the delta and the
resolved findings (later rounds); the risk focus of the contract (critical surfaces, other surfaces, `Rischio:`
lines, obligations); the requirement list; the test signals; the green gates with their **real** numbers (or
`none run yet — VERIFY in parallel`); the level in force and the suites **not** run; budget ~18 (delta ~12).

## Step 2.5: gates

Skipped with `--no-dev`. **Required** — one not `PASS`/`SKIPPED` prevents `IMPLEMENTED`: the level's suites on
the scope (`min`/`std`/`legacy`: tests of the touched modules; `full`: plus lint) · every **plan gate** of
`### Piano di test` (counterproof, prescribed e2e, DB check, measurement) · one `obligation: <surface>` row per
`Obbligo:`. Optional, never blocking: importers of changed shared modules, an e2e asked only via `--with-e2e`.
- `EVIDENZE DEI GATE (driver, run-phase.sh): <dir>` in the context → `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gates.sh" --verify <dir>`:
  `FRESH` → copy each `<gate>.json` `esito` with its summary into the evidence table, evidence
  `driver (evidence/<key>)`, never re-run; a `BLOCKED` there, a scope path missing from `<dir>/argomenti.txt`,
  `STALE` or an error → `gate-manuali.md`.
- `VERIFY IN PARALLELO (driver, run-phase.sh): …` in the context → do not run nor wait for the level's suites
  (nor the counterproofs the line gives to the driver): their rows say `VERIFY (driver, in parallelo)`; pass the
  reviewer's `Test IDs` per requirement as the phase JSON's `copertura`; `APPROVED` → `IMPLEMENTED` with
  `Verification: VERIFIED (provvisorio: VERIFY del driver in parallelo)`. Other plan gates keep their rules.
- Neither line (a review by hand) → `gate-manuali.md`.
- `DEVIAZIONI DIFENSIVE (driver, run-phase.sh): <file>` in the context → give the reviewer those lines (label,
  text) to judge against the plan: a deviation declared `difensiva: ` that is not purely defensive (it changes
  observable behaviour, an API contract, an expected visible string, permissions or data written in a case the
  plan foresees) is a **major** finding.
- **Obligation rows** close **only on user-reported evidence** (their command and output, or their written
  manual check), never by static reading nor by a check you or the reviewer chose; until then `NOT RUN` →
  `NEEDS_VERIFICATION`.
- Results: `PASS` · `FAIL` (failed on the code) · `BLOCKED` (could not run, not conclusive — a runner timeout is
  `BLOCKED`, never `FAIL`) · `SKIPPED` (nothing to run, declared with its paths: it satisfies a required gate) ·
  `NOT RUN` (not attempted).

## Step 3: decide

- An `APPROVED` with `Blocked on:` or uncovered files is not an approval: re-run the reviewer on the uncovered
  part, free once per range; a second partial costs an iteration, a third → `NEEDS HUMAN DECISION`.
- Before writing: `review-surface.sh check` on the snapshot just reviewed (its base, tree, scope and excluded
  lists) and `plan-check.sh basis` again. Not `FRESH`, or a different `Basis:` → at most `NEEDS_VERIFICATION`,
  approval stale (`Reviewed contract:` keeps the Step 1 values).

| Reviewer | Required gates | Review status | Feature status | Verification |
|---|---|---|---|---|
| APPROVED | all `PASS` | `APPROVED` | `IMPLEMENTED` | `VERIFIED` |
| APPROVED | no plan gate, level's suites all `SKIPPED` | `APPROVED` | `IMPLEMENTED` | `VERIFIED (static only — no applicable tests: <paths>)` |
| APPROVED | any `FAIL` | `NEEDS_CHANGES` | `PLANNED` | `PARTIAL (<failed gate>)` |
| APPROVED | none failed, some `BLOCKED` / `NOT RUN` | `APPROVED` | `NEEDS_VERIFICATION` | `PARTIAL (<gates>)` |
| APPROVED | `--no-dev` | `APPROVED` | `NEEDS_VERIFICATION` | `NOT RUN (--no-dev)` |
| NEEDS_CHANGES | any | `NEEDS_CHANGES` | `PLANNED` | as measured |
| STOP_HUMAN_DECISION_REQUIRED | any | `NEEDS HUMAN DECISION` | `PLANNED` | as measured |

- Under the driver the state is signed after the phase by `${CLAUDE_PLUGIN_ROOT}/scripts/finalize.sh` (code). **By hand** on a run
  directory of the new regime (`spec-<name>.run/` with `evidence/` or a `log/*.result.json[.visto]`): after
  writing, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize.sh" --level <level> .claude/.ai-workflow/spec-<name>.run` and report its
  last line.
- Mode (a): write the section — status lines, snapshot, contract, rounds, manifest, evidence table, finding
  table, blocker/major findings, optional ones as suggestions. Mode (b): the same in the conversation.
- `NEEDS_CHANGES`: do not fix; recommend a separate fix step. `NEEDS_VERIFICATION`: which required gate is
  missing and the command to obtain it (same snapshot → promotion only); an obligation: the check to do and
  «rilancia `/maat:implementation-review-cycle <name>` incollando comando e output (o la descrizione della verifica
  manuale)».

Evidence table — one line per gate, no logs:

```text
| Gate | Req. | Command / check | Result | Evidence |
| backend tests (touched) | yes | pytest tests/test_x.py | PASS | 42/42 |
| lint (touched) | yes | gates.sh lint (driver) | PASS | driver (evidence/3f9c…): esito=PASS luogo=copia |
| plan: counterproof on foo.py | yes | counterproof.sh cp1 | PASS | observed this session |
| obligation: dati | yes | proposed: migration applied, column nullable | NOT RUN | awaiting user |
```

## Final response

`Decision:` · `Feature status:` (mode a) · `Verification:` · `Review basis:` · `Reviewed snapshot: base <sha12> ·
tree <sha12> · <n> paths (<k> excluded)` · the spec file (mode a) · summary · blocking findings · optional
findings (suggestions, not applied) · evidence (gate · req · result · evidence) · the level in force and where it
came from, the suites not run, each `⚠️ Superficie` line of the plan · the next step: `IMPLEMENTED` → prepare the
commit (a later edit makes the approval stale); `NEEDS_VERIFICATION` → obtain the missing gates and re-invoke;
`NEEDS_CHANGES` → fix only blocker/major, then re-run; `NEEDS HUMAN DECISION` → resolve them by hand first.
