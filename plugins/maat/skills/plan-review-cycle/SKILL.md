---
name: plan-review-cycle
description: Runs a bounded specification-to-plan adversarial review cycle using the local spec-plan-reviewer agent. The approved plan is written as a section INSIDE the spec file. Use when the user wants to turn a specification into an approved implementation plan without manually passing the plan back and forth.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
argument-hint: "<path to spec-<name>.md, or pasted specification text> [--tests=min|std|full] [--no-dev] [--full|--light]"
---

# Plan Review Cycle

Radice del plugin: `${CLAUDE_PLUGIN_ROOT}`. Nei file di questa skill che leggi con Read, `${CLAUDE_PLUGIN_ROOT}` vale questo percorso: sostituiscilo prima di eseguire un comando.

Prima di ogni comando Bash o PowerShell, scrivi `description` secondo `${CLAUDE_PLUGIN_ROOT}/docs/descrizione-comandi.md`.

You orchestrate a bounded planning and adversarial review workflow: a plan inside the spec file, reviewed by
the local `spec-plan-reviewer` agent until approved, a stop condition, or the budget. Do not implement code.
Where the rest lives — read a file only when this one sends you there:
- `autore.md` — how the plan is written and revised (plan shape, format 2, test level, floors): read by you at
  Step 1, and by the fresh author sub-agent of each format-2 revision;
- `revisori.md` — the reviewers' mandates: read by the reviewer agent itself;
- `formato-1.md` — a re-opened plan with no `Plan format: 2` line: read it only then;
- `plan-check.sh` — the code: structure, boundaries, differences, decisions (below). What moved out of this file
  into code, with its test: `${CLAUDE_PLUGIN_ROOT}/skills/full-implementation-cycle/riferimento.md`, «Rules in code».

$ARGUMENTS

## Single writable artifact

- You write only `.claude/.ai-workflow/spec-<name>.md`, and in it only `## Implementation plan` with its
  `### Plan review changelog`: never the spec sections above, never `## Implementation review`.
- The status lines (`Plan format: 2`, `Plan status:`, `Test level:`, `Risk surfaces:`, `Approved basis:`)
  are line-anchored and single-occurrence; prose and the changelog never reproduce those prefixes.
- **Languages (Maat 1.3.0)**: write the English headings and keywords (autore.md, «Languages»); every reader also
  accepts the Italian ones of older specs (`## Piano di implementazione`, `### Changelog revisione piano`,
  `Superfici a rischio:`…). A section that already exists keeps its heading: English only for a section created
  new, never both (`lint` VIOLAZIONE). An approved plan is never translated.
- **An approved plan is never edited**: only its changelog (notes, metric line). Any other change is a
  re-opening (below); `Approved basis:` makes a hand edit visible (`basis` → `STALE`, and the cycle stops).

## plan-check.sh — the code

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/plan-check.sh" <cmd> …` — exit 0 ok · 1 `VIOLAZIONE` · 2 usage; an
`AVVISO` never changes the exit. A `VIOLAZIONE` is fixed before a reviewer sees the plan.
The keywords (`VIOLAZIONE`, `AVVISO`, `ERRORE DURO`, `Percorso:`, `Scheletro:`, `S2:`) are the same in every language;
the explanation after them follows `lingua` of `.claude/maat.json` (Maat 1.4.0).

| command | what it decides |
|---|---|
| `lint <spec> [--baseline <copy>]` | status lines, sections above untouched, surfaces and floors — before every round |
| `lint2 <spec>` | format 2: requirements ↔ tests ↔ steps ↔ files, blocks, test table and mutations, removed strings still asserted, Python test ids (`::`), reds that need a stub in an existing file; AVVISO for a module without `report` |
| `skeleton <spec>` | the size gate (skeleton and full plan); `Split: rejected` (or `Taglio: rifiutato`) in the spec → exit 0 |
| `split <mother> <child…>` | a cut: every requirement in exactly one child, `Depends on:` / `Interface for:` (or `Dipende da:` / `Interfaccia per:`) present |
| `route <spec>` | format 2 branch: `Percorso: leggero \| pieno — <motivo>` |
| `taglia <spec> [--override full\|light]` | the size of the cycle (1.7.0): facts F1–F14, last line `Taglia: piccola \| piena — <motivi>` |
| `e1 <reply>` | the one round of the small size: `E1: piccola \| piena \| STOP — <motivo>` |
| `delta <copy> <spec>` | the `range:` lines rewritten since the copy, plus `xref:` lines; empty or whole-file → exit 1: that round runs at full scope |
| `s2 <spec> --delta <f> --gate <f> [--respinti <n>]` | `S2: APPROVA \| CORREGGI \| RILANCIA \| IMPRONTA DIVERSA \| STOP` |
| `basis <spec>` · `gen <spec>` | the fingerprint to record at approval · the downstream procedure (format 2) |

## `<name>`, container, re-opening

- A spec path → basename without `spec-`, normalised to `[a-z0-9._-]`. Pasted text → a kebab-case slug of its
  first heading (none → ask now) and the container, the text as `## Context` and `## Functional requirements`. No
  timestamps, no suffixes: an existing file is refined in place.
- **Re-opening an approved plan** (the only legal amendment): copy the spec to the scratchpad first (the delta
  baseline); new requirements are written above by the user or `spec-author`, never by you; `Plan status:
  DRAFT`, plus any missing status line (and a floor or `⚠️` line for a declared critical surface); the amendment
  as surgical edits, recorded in the changelog; then straight to the delta round, fresh budget. Format 1 →
  `formato-1.md`.

Run the whole cycle in one uninterrupted turn: no pause and no confirmation between steps, rounds, revisions.

## Budget and stops

**4 iterations** (format 2; format 1: `formato-1.md`): one fan-out, one S2 pair, one fresh-eyes run = one
iteration. At the budget without approval → `Plan status: NEEDS HUMAN DECISION`. Other stops, also →
`NEEDS HUMAN DECISION`: a `STOP_HUMAN_DECISION_REQUIRED` from any reviewer · a recurrence · a rejected finding
re-raised by the same producer with no new evidence (disagreement on a verifiable fact) · scope not in the spec
· an ambiguity the codebase cannot resolve · `skeleton` exit 1 (the cut proposal, Step 1).

## Findings

- Only `blocker`/`major` block, and only with a **verifiable anchor**: `code` (`path:line` that says it) ·
  `spec/plan` (a line contradicting or omitting something checkable) · `absence` (pattern + scope + 0 results) ·
  `measure` (a result of the declared remote verification you supplied). No anchor → optional.
- **Verify before applying**: 1 Read or 1 Grep on the anchor (real data: a read-only query of the remote verification, not under
  `--no-dev`). Reject **only if the anchor is literally false**, never on reasoning — you own the plan. A
  rejection: one changelog line `rifiutato: <key> — <refutation>`, the «Rejected» list of every later prompt and
  of the final response; it does not count toward recurrence.
- `minor`/`nit` are **never applied**, not even after approval: one changelog line each, notes for the
  implementer. A finding needed for correctness is a `major`.
- **One round, several reviewers**: a `STOP_HUMAN_DECISION_REQUIRED` dominates; one `NEEDS_CHANGES` makes the
  round `NEEDS_CHANGES`; `APPROVED` only if all approve.
- **A partial review is not an approval**: an `APPROVED` with `Blocked on:` or uncovered ranges → re-run that
  producer on those ranges, free once per producer and range; a second partial there costs an iteration, a
  third is `STOP_HUMAN_DECISION_REQUIRED`.
- **Recurrence is yours** (the reviewers are stateless): a table `key → state`, never the full reviews; key
  `<area>/<claim in 5 words>` plus its anchored symbol or path, never a line number; states `aperto · risolto ·
  rifiutato · reintrodotto`. The same blocker/major in two consecutive runs of the same producer →
  `STOP_HUMAN_DECISION_REQUIRED`; `reintrodotto` (a `risolto` key back after a later edit) is a label, not a stop.

## Step 1: the plan

Level: `--tests=min|std|full` (aliases «test minimi», «solo i gate» → `min`; «test completi», «tutti i test» →
`full`), default `std`. You write the plan yourself: read `${CLAUDE_PLUGIN_ROOT}/skills/plan-review-cycle/autore.md` now and
follow it. Copy the spec to the scratchpad (the `lint` baseline), write the **skeleton** only, then `skeleton`:
- `SOTTO IL TETTO` → write the full plan from the skeleton; then `lint --baseline`,
  `lint2`, `skeleton` again (the full-plan ceiling), `route`, and refresh the context pack
  (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/context-pack.sh" <spec>`: the plan changed the spec's fingerprint);
- `SOPRA IL TETTO` → **cut proposal**: `maat:spec-author` in mode `split` (Task) with the spec path and the `skeleton`
  output; `split <spec> <children…>`; a `VIOLAZIONE` goes back to `maat:spec-author` once, again → report it. Then
  `Plan status: NEEDS HUMAN DECISION`, changelog note «scheletro sopra il tetto: proposta di taglio in N
  anelli», and stop with the proposal: the rings in order, their requirements, what users see between rings.
  The user decides once; a rejection is recorded above the plan by `spec-author` (`Split: rejected —
  <date>`; `Taglio: rifiutato` in an older spec), and from then on `skeleton` lets the single plan go on.

**Size, then branch (1.7.0).** Right after `route`, `taglia <spec>` (`--override full` with `--full`, `--override
light` with `--light`); its last line is `Taglia: piccola | piena — <motivi>`, decided by the script, never by you
(you may only ask for more: a `Size request: full — <reason>` line in the plan). Say it in one line.
- `piena` → the branch as before: `--full` always wins; otherwise `route`: `Percorso: leggero` → the rounds of
  `plan-review-cycle-light`; `pieno` → Step 2 (`--light` is honoured only with `leggero`).
- `piccola` → **one** round of `maat:spec-plan-reviewer-light` at full scope, with the prompt of
  `plan-review-cycle-light` («The reviewer»). Save its reply to the scratchpad and run `e1 <reply>`: `E1: STOP` →
  `NEEDS HUMAN DECISION`; `E1: piena` (a blocker, more than 2 major, a partial reply) → one line `Escalation: piccola
  → piena — <cause>`, then Step 2 on the same plan (the full branch from here); `E1: piccola` → verify each major
  (Findings), apply the verified ones with a fresh author sub-agent («How to revise» of `autore.md`), `lint
  --baseline`, `lint2`, then Step 3 with **no second round**, after the changelog note `taglia piccola: corrected
  without a second round: <keys>` (the code review takes it as focus).

## Step 2: round 1 — three lenses in one message

Three `maat:spec-plan-reviewer` agents in a single message, **in the foreground** (never `run_in_background`: the
parallel comes from the calls being in the same message, and a sub-session of the cycle denies it), each: «Use the maat:spec-plan-reviewer agent. Read
`${CLAUDE_PLUGIN_ROOT}/skills/plan-review-cycle/revisori.md`, section «Round 1», and follow it. Lens: <L1|L2|L3>. Spec + plan
file: <path>. Ranges: spec <offset/limit>, plan <offset/limit>. Context pack: <path | none>. Test level: <lvl>.
Risk surfaces: <tokens>.» Aggregate. `APPROVED` outright → Step 3, but first one fresh-eyes reviewer
alone when a critical surface (`permissions`, `data`, `destructive` — `permessi`, `dati`, `distruttiva`) is declared.

## S2: revise, then delta ∥ fresh eyes (every later round)

1. Verify each blocker/major. Copy the spec to the scratchpad, then — **the author is fresh at every round**, you
   keep the finding table and the recurrence — an author sub-agent (Task): the spec path, the
   findings to apply with their verified anchors, «read `autore.md`, section «How to revise», apply only these».
   Then `lint --baseline`, `lint2`, `delta <copy> <spec>`. All findings rejected → no author, no delta: step 2.
2. One message, two `maat:spec-plan-reviewer` agents on the same plan, in the foreground (never `run_in_background`:
   same message = already in parallel; the author sub-agent of point 1 too) — «read `revisori.md`, section «Delta»» and
   «… section «Fresh eyes»» — with: the `range:` and `xref:` lines, the pertinent requirement ranges, level and
   surfaces (every round), resolved findings (key + symbol + one line), rejected ones (key + refutation), test
   cases removed as over-testing, budget ~20 → 15 → 12. Save each reply to the scratchpad with, as first line,
   `Impronta piano: <plan value of basis at launch>`.
3. `s2 <spec> --delta <f> --gate <f> --respinti <n>` (`n` = the blocker/major of **these two** replies you
   rejected): `APPROVA` → Step 3 · `CORREGGI` → next round · `RILANCIA` → both again, together, with the
   rejected list · `IMPRONTA DIVERSA` → relaunch on the current plan · `STOP` → `NEEDS HUMAN DECISION`.

## Step 3: decide

- **Approved** → `Plan status: APPROVED`; `basis <spec>` and its whole `Basis:` value as `Approved basis: <value>`
  right under `Risk surfaces:` (or `Superfici a rischio:`) (replacing an older one; a ring's `madre`/`prec`/`interfaccia` included);
  `basis` again must say `FRESH`; format 2: `gen <spec>` must exit 0. Never write ` · tests <fp>`: the test-red
  phase does. Then, in the changelog only, the optional findings as notes and the metric line.
- **Not approved** (budget, stop) → `Plan status: NEEDS HUMAN DECISION`, the open decision, the metric line.

The **metric line**, last line of the changelog (no backticks, never the status prefixes; one per run of the
cycle): `Metrica ciclo: giri=5 · R1=2/3 · delta=1/2 · gate=0/1 · rifiutati=1 · ricorrenze=0 · reintrodotti=1 ·
esito=approvato · livello=std · superfici=permessi,dati · formato=2 · taglia=piena` (`R1`/`delta`/`gate` =
blocker/major found in that phase over its runs; `giri` = iterations; `taglia=piccola` only for a plan approved on the
small path, otherwise `taglia=piena`: the driver reads it, 1.7.0).

## Final response

`Decision:` · the spec file · `Plan status:` · summary · unresolved blocker/major · rejected findings (key +
refutation) · optional findings, not applied · `Test level: <lvl> (<default std | esplicito | alias>)` ·
`Risk surfaces:` with the floor of each critical surface (or its `⚠️`) · next command: approved →
`/maat:implementation-review-cycle <name>`, saying plainly that **plan approval does not replace the code review**
(the quick `--light` round after implementing is always worth it); not approved → the human decision needed. A
`/browser-qa` suggestion only when the plan changes a multi-step UI journey or wires UI state to persistence with
no component test — for the human, never in the plan.
