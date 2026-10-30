# Plan author — how the plan is written and revised

Read by whoever writes the plan section: the `plan-review-cycle` session itself for the initial plan (skeleton
first, then the full plan), and the fresh author sub-agent it launches for each format-2 revision («How to
revise»). The orchestrator keeps the finding table and the recurrence. Structure, boundaries and
differences are checked by `plan-check.sh` (`lint`, `lint2`, `skeleton`): run `lint` and, in format 2, `lint2` after
writing, and fix every `VIOLAZIONE` before you hand back.

## Single writable artifact: the spec file

This workflow writes to **exactly one file**: the specification file
`.claude/.ai-workflow/spec-<name>.md`. The plan lives **inside** it as a dedicated section.
No other files are created or modified (no `plan-<name>.md`, no `spec.md`, no versioned
files, no state file).

The spec file has this shape (spec sections authored by `spec-author` or by you when a spec
file does not yet exist; the plan section is owned by this skill):

```text
# <Titolo>
## Contesto ...
## Requisiti funzionali ...
...spec sections...

## Piano di implementazione        ← OWNED by this skill
Plan format: 2                                    ← new plans only (see "Plan format 2")
Plan status: DRAFT | APPROVED | NEEDS HUMAN DECISION
Test level: min | std | full
Superfici a rischio: <voci del vocabolario («Risk surfaces»), oppure: nessuna>
Approved basis: spec <fp12> · plan <fp12>        ← written at approval only (Step 3); format 2: the
                                                    driver appends " · tests <fp12>" when test-red closes OK
<plan content, incl. ### Tracciabilità requisiti and ### Piano di test>
### Changelog revisione piano
<blocker/major finding → change applied · rejected findings · optional notes · metric line>
```

Hard rules on writing:
- The ONLY file you may write/edit is `.claude/.ai-workflow/spec-<name>.md`.
- You may create/update ONLY the `## Piano di implementazione` section (and its
  `### Changelog revisione piano` sub-section). **Never** modify the specification sections
  above it, and never touch any `## Review implementazione` section (owned by
  `implementation-review-cycle`).
- `Plan status:` must be a **line-anchored, single-occurrence** line (downstream greps
  `^Plan status: APPROVED`). The changelog MUST NOT reproduce the literal `Plan status:`
  prefix.
- `Test level:` follows the SAME rule, and needs it more (see "Test effort"): line-anchored,
  single-occurrence, immediately under `Plan status:`. The changelog and any finding text
  quoted into the plan MUST NOT reproduce the literal `Test level:` prefix — write "livello
  di test" in prose. This matters because lens L3 now raises findings *about the test level*,
  and that text lands in the changelog.
- `Superfici a rischio:` follows the SAME rule again: line-anchored, single-occurrence,
  immediately under `Test level:`; in prose write "superfici a rischio" in lower case.
- **An approved plan is never edited.** After `Plan status: APPROVED` only the changelog is written
  (notes, metric line). Any other change — a new constraint, an amendment, a "small fix" — goes
  through a re-opening (SKILL.md, «re-opening»). Measured: 308 lines added to an approved plan by
  hand, once reviewed, held 1 blocker and 7 majors (`spec-restyling-ui-soft`). It is now also
  **detected**: `Approved basis:` fingerprints the spec and the plan body at approval, and
  `plan-check.sh basis` says `STALE` when either changed; `/implementation-review-cycle` and
  `/full-implementation-cycle` stop on it.

## Risk surfaces

**The risk-surface vocabulary — the single list; every other mention points here:**

| Token | Covers | Critical |
|---|---|---|
| `permessi` | authentication, authorization, roles, visibility by role | **yes** |
| `dati` | DB schema, migrations, persistent state, data written or deleted in bulk | **yes** |
| `distruttiva` | an operation that deletes or overwrites data/state irreversibly | **yes** |
| `contratto-api` | request/response shape, status codes, routes consumed by others | no |
| `import` | the import pipelines | no |
| `logica-condivisa` | shared business logic, shared components/stores/composables | no |

The plan declares the touched ones in `Superfici a rischio:` — bare tokens separated by commas,
or `nessuna`; no notes on that line (`plan-check.sh lint` rejects an unknown token). **Critical** surfaces drive two things and nothing else: the verification floor
(see "Test effort") and the fresh-eyes gate after a round-1 approval (Step 2-ter). No
LOW/MEDIUM/HIGH grading: no behaviour needs it. Lens L1 verifies the declaration like any
`nessuna implicazione` — under-declaring would silently skip both.

## Test effort: `--tests=min|std|full`

Parse `$ARGUMENTS` for `--tests=min|std|full`. Italian aliases count as the flag: "test minimi" /
"solo i gate" → `min`; "test completi" / "tutti i test" → `full`. **Default: `std`.**

Write the resolved level into the plan as `Test level: <lvl>`, immediately under `Plan status:`
(single occurrence, line-anchored — see the hard rules above). This line is how
`/implementation-review-cycle` learns the level; it is the only channel.

| | `min` | `std` (default) | `full` |
|---|---|---|---|
| Suite | existing gates of the **touched modules only** | same | modules' suites + lint (the CI's gates; build only if the plan prescribes it) |
| New test cases in the plan | **0**, unless a bug regression (1 case) | **≤5**, only on the behavior the plan changes | no cap |
| `[pavimento:` line per declared critical surface | 1, outside the caps | 1, outside the caps | 1, outside the caps |
| Counterproof (the file(s) it names reverted to base, or a named mutation; expected red) | none | on the **central gate** only (1, max 2) | every new case |
| e2e prescribed in the plan | only `[e2e-locator:` (below) | only `[e2e-locator:` (below) | at most 1 targeted spec, plus `[e2e-locator:` |
| `/browser-qa` | never | never | **never** — explicit request only |
| Length of `### Piano di test` (a signal, never a finding by itself) | ~1 line | ~15 lines | free |

**A whole-suite gate is permitted but never required at `full`; it is forbidden at `min` and
`std`.** This is the criterion L3 uses to decide whether a gate is over-testing, so it must be
unambiguous.

**Section name.** The canonical heading is `### Piano di test` (numbering optional, e.g.
`### 9. Piano di test`). Existing specs use both forms; the length rule targets this heading.

**The length is measured, not enforced.** `plan-check.sh lint` prints an `AVVISO` above it; a
reviewer never raises a blocker/major on the line count alone — what blocks is what the lines
prescribe (a case over the level's cap, a duplicate, a whole suite below `full`). Measured: a major
"over the 15-line cap" cost a round and was resolved by merging lines, not by removing a test.

**Risk surfaces do NOT raise the level — but a critical one gets a floor.** The level is the
verification *budget*; it never turns `min` into `full`. Yet at `min` a permission change could
otherwise reach approval with no verification of the permission at all. So, for **each critical
surface declared** (`permessi`, `dati`, `distruttiva` — vocabulary in «Risk surfaces»), `### Piano di test`
names **exactly one** pertinent verification, as a list item of its own, marked:

```text
- [pavimento: permessi] <an existing test cited by path, OR 1 new case, OR a read-only DB check of the declared remote verification> rosso se: <condition>
```

- for `permessi`, the pertinent verification is the **negative** one (the denied role is denied);
- a `[pavimento:` line is **exempt** from the level's caps (new cases, `### Piano di test` length),
  from the L3 over-testing rule and from the "do NOT re-add" list — at most one per critical
  surface, which `plan-check.sh lint` enforces;
- if no pertinent verification is reachable, the plan writes the old **one line** instead —
  `⚠️ Superficie <token> non coperta dai gate al livello <lvl>`, with the vocabulary token right
  after `Superficie` (a `⚠️` line about another surface does not cover this one) — and continues.
  One line, not a paragraph, and outside the caps too. **Downstream it is an obligation**: the
  feature cannot reach `IMPLEMENTED` until the user reports a verification of that surface — i.e.
  in `/full-implementation-cycle` a `⚠️` on a critical surface **is a human STOP**. That is the
  honest reading of "no gate can cover it"; before, it came out `VERIFIED` with nothing having
  touched the surface at runtime. So look hard for a floor first;
- **the waiver**: when the change does not alter the surface's runtime behaviour at all (a rename,
  a message, a refactor that leaves the check itself untouched), append on the **same physical
  line** `— statica sufficiente: <motivo>`. Then no obligation arises downstream; the surface stays
  a risk focus. L3 judges the motive: a waiver on a change that does alter the behaviour is
  under-testing. After approval the line is frozen (`Approved basis:`);
- non-critical surfaces (`contratto-api`, `logica-condivisa`, `import`) get no floor and no
  obligation: their risk is blast radius, which is L1/L2's job, not a test's. A `⚠️` line on them
  is only a risk focus.

**Every new test case states `rosso se: <condition>`** — the world in which it goes red. One
clause per case, no new cap: it makes L3's non-vacuity check checkable instead of inferred.

**A counterproof names the file(s) it touches** — either reverted to the base, or a **named
mutation** (file · symbol · what is removed, e.g. "remove the `!= ROLE_MANAGER` condition in
`resolve_membership()`") — then the expected red. Use the mutation when the test imports something
the feature adds: a file back at base then fails on the import, not on the assertion (measured,
`spec-golas-obiettivo-aziendale`: an ImportError, a FAIL, a round and a human decision). Never
"revert the whole feature" nor a `git stash`: `/full-implementation-cycle` touches only the files a
gate names and records a gate that names none as `NOT RUN` — a STOP.

**An e2e bound to a locator, at any level.** When the plan changes a file in `e2e/specs/`, or a
string, class or attribute that an e2e spec uses as a locator (L3 searches every changed string
there), `### Piano di test` carries one list item per affected spec:

```text
- [e2e-locator: e2e-6-customer.spec.ts] <the locator or string that changes> rosso se: <condition>
```

At most 2 such lines; beyond that, one `⚠️` line and the regression watch. They are outside the
level's caps like a `[pavimento:` line (`plan-check.sh lint` does not count them, the
`Approved basis:`
fingerprint freezes them), and downstream each is a required gate: the declared remote verification (`verifica_remota` in `.claude/maat.json`) with `--e2e <spec>` on DEV, so with
`--no-dev` the feature stops at `NEEDS_VERIFICATION` — on purpose. Measured: unit tests green while the real DOM broke a locator (`spec-partita-iva-unica-context`), and a selector changed at `std` whose e2e never ran (`spec-opzioni-offerta-salvataggio`).

**`/browser-qa` is never prescribed in a plan**, at any level: it is a separate flow, invoked by
hand when needed (and it stays a mandatory gate only at the porting cutover).

**Downstream contract — these lines are consumed, not just read.** `/implementation-review-cycle`
parses the approved plan with `plan-check.sh contract` and does NOT re-derive what the plan already
decided:
- every gate written in `### Piano di test` becomes a **required gate** of the implementation
  review (a feature cannot reach `IMPLEMENTED` until it has passed on the reviewed code). So write
  each gate as something that can be executed and observed — a test file, a command, a counterproof
  with its expected red — never as a wish ("verify that it works");
- every `⚠️ Superficie <token> non coperta…` line becomes a **risk focus** the implementation reviewer
  must look at first: keep it to the surfaces that are really uncovered;
- the surfaces of `Superfici a rischio:` are a risk focus too, a `[pavimento:` or `[e2e-locator:`
  line is a required gate like any other, a critical surface with neither a floor nor a waiver is an
  **obligation** closed only by the user's evidence, and `### Tracciabilità requisiti` is the
  requirement list the implementation reviewer reports coverage against.
Over-prescribing here therefore costs twice: once in the plan, once as a gate that must pass.

## Plan format 2

A plan whose section opens with the line `Plan format: 2` — right under `## Piano di implementazione`,
above `Plan status:`, line-anchored, single occurrence — is in **format 2**. **Every plan this skill
writes from scratch is in format 2.** A plan without the line is **format 1** and follows the rest of
this file exactly as before — a format-1 plan re-opened later included: it is never converted.
Everything above (status lines, level, surfaces, floors, `rosso se:`, `Approved basis:`) holds in both.

**Structure.** H3 sections (numbering optional); the table headers are fixed — `plan-check.sh` reads
them:

```text
## Piano di implementazione
Plan format: 2
Plan status: DRAFT
Test level: std
Superfici a rischio: permessi, contratto-api

### Decisioni
<one short paragraph per decision, then its examples>
| input | output |
|---|---|
| obiettivo 1.000.000 €, assegnato 950.000 € | `near` (confine: residuo = soglia) |

### File toccati
- `backend/app/routers/goals.py`
- `backend/tests/test_goals.py`

### Passi
#### Blocco B1 — backend
scrive: `backend/app/routers/goals.py`, `backend/tests/test_goals.py`
dopo: nessuno

| id | file | modifica | test |
|---|---|---|---|
| P1 | `backend/app/routers/goals.py` | `update_goal()`: 403 a chi non può modificare | T1 |

#### Blocco B2 — frontend
scrive: `frontend/components/goals/PlanTable.vue`
dopo: B1

### Tracciabilità requisiti
| Req | Passi del piano | Verifica |
|---|---|---|
| RF1 | P1 | T1 |
| RF2 | P2 | non verificabile a test: <motivo> |

### Stringhe e data-test
| azione | tipo | valore |
|---|---|---|
| toglie | data-test | `goals-company-section` |
| aggiunge | stringa | `Modifica obiettivo aziendale` |

### Piano di test
| ID | requisito | file | asserzione | mutazione |
|---|---|---|---|---|
| T1 | RF1 | `backend/tests/test_goals.py::test_update_denied` (nuovo) | rosso se: un venditore aggiorna l'obiettivo | `backend/app/routers/goals.py` · `update_goal` · `if not can_edit:` → `if False:` · rosso se: `assert 200 == 403` |
- [pavimento: permessi] T1
```

- **Paths** are relative to the repository, everywhere (their first segment exists at the root).
- **New files**: in `### File toccati`, `(nuovo)` right after the path's code span (`` - `path` (nuovo) ``)
  marks a file the plan creates. Downstream (harness-pt11) it is the `test-red` phase's write scope with the
  test files, where the stubs of the new symbols go, and the only kind of file whose counterproof can be
  absorbed (L2).
- **Acceptance tests (test-red)**: every row of `### Piano di test` is written and proven red on the base with
  stubs before the implementation. The red must hit the row's assertion, at a position in the test file: put
  the expected failure text between backticks in `asserzione` (else the mutation's `rosso se:` is used) — a row
  with neither is a `lint2` VIOLATION, and a red with no text or no position is not proven; every string or `data-test` the plan
  adds must be listed as `aggiunge` in `### Stringhe e data-test` — an existing test asserting its absence is
  a conflict that stops the phase.
- **Decisioni** stay prose; the input → output examples are what the implementer and the tests read.
- **Passi**: every step is a row `id | file | modifica | test` inside a `#### Blocco <id>`; each block
  declares `scrive:` (the files it writes) and `dopo:` (the blocks it depends on, or `nessuno`).
- **Piano di test**: one row per case. `file` = the test, as the first code span: `path` or
  `path::name` (pytest node id, or vitest full name — required when the row has a mutation); `(nuovo)`
  after the span marks a new case, the one the level's caps count. `asserzione` = the case's
  `rosso se:`. `requisito` = the IDs of `### Tracciabilità requisiti` it verifies.
- **Existing non-regression tests are NOT rows of `### Piano di test`.** A test that already exists and must
  only stay green («resta verde», «rimane verde», «continua a passare») cannot be proven red on the base with
  stubs, so as a row it stops the cycle at test-red — `lint2` gives a VIOLATION for a row whose `asserzione`
  starts that way. Put them in a note right under the table, one item each: «Test ESISTENTI di
  non-regressione (non sono righe del Piano di test: non si possono dimostrare rossi sulla base con stub):» —
  `path` (or `path::name`), what stays true, the requirement IDs, and the explicit command when the test is
  outside the gate of the touched modules. A requirement covered only by such a test is written in
  `### Tracciabilità requisiti` as ``non verificabile a test (invarianza, non dimostrabile rossa): la copre il
  test esistente `<path>` `` (the `non verificabile` prefix is what `lint2` accepts); the step's `test` column
  then names no ID for it (`—`). A test the plan **updates** is not «resta verde»: it is a row with its `rosso se:`.
- **mutazione** = the counterproof, in `counterproof.sh`'s form, or `—`:
  `` `file` · `simbolo` · `cerca` → `sostituisci` · rosso se: `testo del messaggio d'errore` ``.
  `(vuoto)` in place of the replacement removes `cerca`; `cerca` must occur **once** in the file
  *after* the implementation; a `|` is written `\|`, a backtick needs a double-backtick span. File and
  test in the same module of `.claude/maat.json` (a test under the `radice` of the file's module). Which rows
  carry one follows the level (none at `min`, the central gate at `std`, every new case at `full`).
- `[pavimento:`, `[e2e-locator:` and `⚠️` lines stay list items under the table, as in format 1; a
  floor that is a row of the table names its ID.
- **Stringhe e data-test**: every string or `data-test` the plan removes (`toglie`) or adds (`aggiunge`).
  `lint2` searches the existing tests for them and decides, by the literal's position, whether a match asserts
  presence (a `VIOLAZIONE` unless the file is one the plan touches — an e2e spec: its `[e2e-locator:` line) or
  absence (an `AVVISO`). An optional fourth column `verificato` — `` `<file>` — <motivo> `` — waives that row's
  match in that file: `| toglie | stringa | `Attivo` | `frontend/tests/x.test.ts` — riscritto dal flusso X |`.
- **A product defect found late** (round 3 or 4) does not reopen the design: it becomes one test row, with its
  step, and one list item `⚠️ Rischio aperto: <claim> — <test ID>` under the table.

**Generated, never written.** The plan carries **no** command line, no `test-fast.sh` path list, no
pytest selector, no counterproof recipe: `plan-check.sh gen <spec>` derives them from the test table and
writes them to the run directory — `<spec>.run/gen/procedura.txt` (level, commands, paths, blocks) and
`<spec>.run/counterproof/mutations.json` (the list `counterproof.sh` reads; removed when no row has a
mutation). A procedure written by hand cannot be wrong, because there is none.

## Skeleton first (format 2)

A plan too large does not converge (the reviewers sample it instead of exhausting it). Asked for the skeleton:
1. **Skeleton first.** Write only the skeleton into the plan section: `Plan format: 2` and the status lines
   (`Plan status: DRAFT`), `### File toccati`, and `### Passi` with its `#### Blocco` blocks and one row per
   step (`| id | file | modifica | test |` — a few words in `modifica`, `test` may be `—`). No decisions, no
   traceability, no test plan yet. Then `plan-check.sh skeleton <spec>`:
   - `Scheletro: SOTTO IL TETTO` (≤15 steps, ≤40 files) → write the full plan **starting from the skeleton**
     (it is its backbone: nothing is thrown away);
   - `Scheletro: SOPRA IL TETTO` (exit 1) → **cut proposal** (below).
   The orchestrator runs `plan-check.sh skeleton` (ceilings in its constants: ≤15 steps, ≤40 files, a full plan
   ≤400 lines) and, under them, asks for the full plan **starting from the skeleton** (nothing is thrown away).

## Writing the plan

Analyze the local codebase and write the `## Piano di implementazione` section into
`.claude/.ai-workflow/spec-<name>.md` with `Plan status: DRAFT`, `Test level: <lvl>` and
`Superfici a rischio: <tokens | nessuna>`. Copy the spec to the scratchpad **before** writing
(the `lint` baseline), and after writing run `plan-check.sh lint <spec> --baseline <copy>`.

**`### Tracciabilità requisiti`** — one row per requirement, with the ID as the spec writes it
(`RF1`, `D3`, `Requisito A`…) or `RF<n>` by position when the spec has none:

```text
| Req | Passi del piano | Verifica |
| RF1 | 2, 3 | test_x.py::test_y · oppure: non verificabile a test, motivo |
```

One row each, no prose: a small feature gets a three-row table. L1 checks it (not a script: real
specs number requirements in too many ways for a count to be reliable).

The plan must cover: objective; relevant files/components/stores/services/routes/tests/
APIs; current behavior; proposed behavior; implementation steps; data-flow implications;
UI implications; backend implications; validation rules; permission rules; migration/
persistence implications; risks; requirement traceability (below); test plan **at the declared
level** (see "Test effort"); rollback considerations; explicit out-of-scope.

**Size the plan to the change — these sections are conditional, not mandatory prose.**
A section with nothing to say gets **one line, `nessuna implicazione`** — never a paragraph of
filler. Measured: plans average ~700 lines and reach 1314, and that volume is the surface every
round rewrites, which is where self-inflicted defects come from. An explicit `nessuna
implicazione` is a verifiable claim; filler prose is indistinguishable from real content, to a
human reader and to a reviewer alike.

Lens **L1** is required to check every one of those declarations, so writing one without
looking will be caught.

**Three constraints on the test plan**, on top of the level's caps:

- **suite selection follows the diff**: FE-only change → no `pytest`; BE-only → no `vitest`. Derive
  the selectors the way the module's `regola_test` in `.claude/maat.json` maps sources to tests
  (`maat-config.py test-di`); do not reinvent it;
- **no whole-suite gate** at `min`/`std`: the gate is the touched modules' suite;
- **never prescribe `/browser-qa`** — separate flow, invoked by hand.

Do not write code. Do not modify source files. Do not touch the spec sections above.

**Context pack first.** If `.claude/.ai-workflow/spec-<name>.run/context-pack.md` exists (the full cycle
generates it; by hand: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/context-pack.sh" .claude/.ai-workflow/spec-<name>.md`), read it
**before** exploring the code: the files the spec names (verified: they exist or not), their signatures,
the tests that cite them, the DB columns. It is orientation, not authority — **the code wins over the
pack**: code reads stay allowed, and whatever the plan cites (`path:line`, a name, a count) is still
checked in the code. After writing the plan, and before launching the lenses, re-run the same command:
the plan changed the spec's fingerprint, so the pack is regenerated with the plan's files too (unchanged
spec → it writes nothing). A missing pack or a failed run changes nothing: explore as before.

**Reading, in this step and in every revision.**
- *Targeted first.* Start from a search (Grep/Glob) and read the ranges it points to; widen a range,
  or read a file whole, only when those ranges do not settle the question (a short file may be read
  whole). This narrows how you read, not what you check: every file, consumer and surface the plan
  needs is still read.
- *No stale re-reads, no stale quotes.* Do not re-read a range already in your context and unchanged
  since; do not `cat`/`sed -n` a file you are about to Read. A range becomes stale — re-read it —
  after: an Edit/Write of yours, or a `cp`/`mv`/redirection, on that file (that file only; so is
  `review-surface.sh diff --out <file>`); a sub-agent that can write, a test, build, formatter,
  generator or any other Bash command (everything — and everything stays stale while such a task runs
  in background); a compaction or a change of phase (everything). Read/Grep/Glob, a sub-agent whose
  `tools:` are only Read/Grep/Glob (the reviewers — by the frontmatter, not by the name), read-only
  commands (`grep`, `ls`, `wc`, `git status|log|diff|show` without redirections), `plan-check.sh`
  and `review-surface.sh snapshot|check|test-signals` stale nothing. When in doubt, everything is
  stale. Whatever you quote — an Edit `old_string`, a gate, a finding, a `path:line` — comes from a
  read still valid under these rules, never from memory.
- *Batch only what is independent*: calls that do not depend on each other's results go in one
  message; never two Edits on the same file, nor a write with what must see it. Batching changes only
  how the same necessary operations travel: never fewer searches, reads or checks to save turns.
- The reviewers still read everything they need from scratch: this rule is about your own repeated
  reads, not theirs.

**Optional dynamic check of DB assumptions (remote verification).** First, parse `$ARGUMENTS`: if it contains
`--no-dev` (or "review veloce" / "senza DEV"), skip this check entirely. Otherwise, when the plan
asserts facts about real data/schema (a column is nullable, an enum's values, a row's
existence/cardinality), verify them with a read-only query of the declared remote verification (`verifica_remota` in `.claude/maat.json`) instead of
deducing them statically, and feed the result into the plan/review. This runs ONLY when the plan makes
such a DB assertion (no assertion → nothing to run, no DEV roundtrip). `spec-plan-reviewer` stays a
static `Read/Grep/Glob` agent — it does NOT get Bash; the verification is this separate step.

### How to revise: surgically, never by rewriting

Apply each blocking finding as **one minimal, localized Edit**. Do not rewrite the section, do
not reorganize "while you are in there", and **do not touch a code block inside the plan unless
the finding is about that block**. This is the single rule that attacks the round multiplier
head-on: nine specs record that their late-round blockers were introduced by the previous
round's own revision. If a finding genuinely requires restructuring, do it — and flag that block
so the next round reviews it in full.

**Measure every list you write.** Any list or count of `file:riga`, occurrences or consumers that a
revision writes comes from a search run **just before** writing it — never from memory or from
the finding's text. Measured on `spec-restyling-ui-soft`: 3 of the 4 blockers raised against
revisions were lists of points written by inference, and "the total still adds up" hid the error
each time.
