# Format-1 plans (re-opened, no `Plan format: 2` line)

A format-1 plan is never converted. Everything of `SKILL.md` holds, with these differences.

- **Budget: 10 iterations**, not 4 (one fan-out, one delta round or one fresh-eyes run = one iteration).
- **No S2**: after round 1 the rounds are one delta reviewer (below), and the fresh-eyes gate runs once at the end,
  under its triggers. `lint2`, `gen`, `skeleton`, `route` say `non si applica`.

   the legacy plan lacks, and — if a critical surface is declared — its `[pavimento:` or `⚠️`
   line. A plan approved before 2026-09-21 is **not** retrofitted with a
   `### Tracciabilità requisiti` table: its absence is not a finding (rebuilding a whole plan in
   the new format to add one constraint would cost rounds for nothing). The added lines fall in
   the delta, so the delta reviewer checks them — tell it to verify the surface line as L1 would;

- A round whose blocking findings were **all** rejected changes nothing in the plan but the
  changelog, so **do not run `delta`** (its range would be the changelog alone): re-run the
  producer(s) that raised them on the same ranges, with the refutations. It counts as an
  iteration.
- Any rejection during the cycle makes the fresh-eyes gate run before approval (Step 2-ter,
  trigger 3): a rejection is your own judgement, and it gets a second look.

## Step 0: Propose the branch (full vs light)

Before planning, read the spec's risk surfaces and **propose** which branch fits. Touching any
surface of the vocabulary below → full branch. None of them → suggest `/maat:plan-review-cycle-light`.

Two guardrails: the routing **proposes, it does not decide**, and it errs **one way only** —
any doubt goes to the full branch, never to the light one. An explicit `--full` / `--light` in
the invocation always wins over the proposal. State the proposal in one line with its reason,
then continue; do not stop to wait for an answer.

## Step 2-bis (round 2 onwards): ONE reviewer, on the delta only

From round 2 a **single** reviewer runs, not three: on a delta the three lenses have no disjoint
material and would cost triple to re-read the same twenty lines.

**Derive the delta mechanically — never declare it yourself.** You are the same entity that just
introduced the defects; if you omit or mis-state a range, that defect becomes invisible by
construction. And `.gitignore` excludes `.claude/.ai-workflow/spec-*`, so there is no `git diff`
to fall back on. Therefore:

- copy the spec file into the scratchpad **immediately before** dispatching each revision;
- after revising, run `plan-check.sh delta <copy> <spec>` and use the `range:` lines it prints
  (±2 lines of context, nearby hunks merged, CRLF-insensitive);
- **empty diff, or missing baseline, is a HARD ERROR — never `APPROVED`**: rerun that round at
  full scope. Same for a diff that spans the whole file (whitespace reflow): treat it as no
  baseline. This is the likeliest and most silent failure mode of the mechanism — which is why
  the script, not your reading of a diff, decides it (exit 1).

**The minimal impact cone.** A fix can leave an unchanged line saying the old thing, which the
delta cannot see. So `delta` also prints up to 8 `xref:` lines — plan lines outside the delta
citing the same backticked path/symbol (generic tokens filtered, rarest first): pass them as
consistency-only. No dependency analysis beyond that; for code, direct callers only when a
changed line alters a shared symbol.

The delta prompt is `revisori.md`, section «Delta».

## Step 2-ter: the fresh-eyes gate, once, at the end

When the delta reviewer returns `APPROVED`, run **one** `spec-plan-reviewer` at **full scope**
with a single mandate: *"which premise of this plan has never been questioned?"* Pass it the
rejected list too — a rejection is your own judgement, and the gate is where it gets a second look.

`Plan status: APPROVED` is set only if the gate approves too; if it does not, reopen a round and
**re-run the gate afterwards at full scope** — so a cycle costs `1 + n` gate runs, not a fixed one.
Each gate run is an iteration.

**When it fires** — any one of three triggers:

1. **at least one delta round happened** — the gate offsets the delta's narrowing (on
   `spec-company-prefill` four clean delta rounds were followed by a blocker in areas none of
   them had in its perimeter);
2. **round 1 approved outright AND `Superfici a rischio` declares a critical surface** — three
   lenses of one model can share one unexamined premise, and there it is expensive. Rare (2 plans
   out of 61 approved at round 1) and productive (20 first gate runs out of 26 found a major);
3. **a blocker/major was rejected** at any point (see "Verify before applying").

Otherwise the gate does **not** run: round 1 was already full scope, and the gate would be pure
cost (~44% on a one-round cycle).

each time.

