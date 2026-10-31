# Reviewer mandates — read by the spec-plan-reviewer agent

The orchestrator's prompt names your section (`Round 1` with a lens, `Delta`, or `Fresh eyes`) and gives the
parameters: the spec file, the ranges to read, the context pack, the test level and `Risk surfaces` in force,
and for later rounds the resolved, rejected and removed lists and your tool-call budget. Follow your section; the
placeholders in angle brackets are those parameters.

## Round 1

```text
Use the maat:spec-plan-reviewer agent.

Review the specification and the proposed implementation plan against the local codebase.
Both live in the same file; the plan is the "## Implementation plan" section ("## Piano di implementazione" in
an older spec). Headings and keywords come in English or, in older specs, in Italian ("### Test plan" /
"### Piano di test", "red if:" / "rosso se:", "[floor:" / "[pavimento:"…): both are valid, never a finding;
the same section present in BOTH languages is (one of the two would be ignored downstream).

Spec + plan file: .claude/.ai-workflow/spec-<name>.md
Read these ranges only (never the whole file): spec <offset/limit>, plan <offset/limit>.
<if the pack exists> Context pack: .claude/.ai-workflow/spec-<name>.run/context-pack.md — read it
FIRST: named files verified, signatures, tests that cite them, DB columns. Orientation only: the
code wins over the pack; verify in the code whatever you anchor a finding on.

YOUR LENS IS <L1 | L2 | L3>. Cover it; ignore the other two and say which lens you had.

  L1 · Contract & data — missing requirements and conformance to the spec; roles and
       permissions; API/payload/persistence; validation; migrations; backward compatibility.
       Plus: verify EVERY "no implication" ("nessuna implicazione") the plan declares — do not take
       one on trust — and, the same way, the "Risk surfaces" line (a touched surface left undeclared is
       a finding) and the "Requirement traceability" table (a requirement with no step, a
       significant step serving no requirement, a verification that cannot verify it).
  L2 · Fidelity to the code — every path:line cited exists and is the right one; which file an
       auto-imported UiXxx really resolves to (app wrapper vs packages/ui primitive); blast
       radius of the shared files touched; minimality of scope; and RE-COUNT every number the
       plan declares, never trust a count.
  L3 · Gates & tests — the test set must be minimal AND sufficient. Under-testing and
       OVER-testing are findings of the SAME severity. Over-testing = a case duplicating an
       existing test's coverage · a case on code the plan does not change · an e2e where a unit
       test suffices · a whole-suite gate when the level is not `full` · a `/browser-qa`
       prescribed at all. Required change: remove it. Check that the declared level matches
       what the plan actually prescribes: exceeding it is a blocking finding (the length of
       "### Test plan" alone is not: it is a lint signal).
       Still yours: non-vacuity of the gates proposed — every new case must state "red if:",
       and you check that condition is real and reachable; a vacuous test is pure cost — ·
       every string the plan proposes to change, searched in e2e/specs/ and tests/ — a hit in
       e2e/specs/ needs its "[e2e-locator: <spec>]" line, at any level ·
       acceptance criteria actually satisfiable · UI/loading/error/locked states. A line
       marked "[floor: <surface>]" is exempt from the caps and from over-testing: check
       only that it is pertinent and can go red; the same for an "[e2e-locator: <spec>]" line (it
       must name a spec whose locator the plan really changes). A counterproof must name its
       file(s) — reverted to base, or a named mutation when the test imports what the feature adds
       (a revert would fail on the import). A "⚠️ Surface <critical token>" line means
       a human STOP downstream: is a floor really unreachable? A "static sufficient:" waiver
       holds only if the change leaves that surface's runtime behaviour untouched.

Tool-call budget: ~25, as a SOFT threshold. At the budget, if you hold an unverified lead on a
possible blocker, say so and continue up to +50%; otherwise stop and write what you have.
Batch independent Read/Grep/Glob calls in one message; after every message with tool calls, emit
one line of text. The budget counts calls, not messages. If you cannot continue, deliver a partial
with "Blocked on: <reason>" and your coverage. Open with a coverage statement. Say "lens N:
nothing" explicitly if your lens is clean.

minor and nit do NOT block and must not be promoted. Every blocker/major carries an
"Anchor (<kind>):" — code path:line · spec/plan line that contradicts or omits something
checkable · absence (pattern + scope + 0 results) · measure. No anchor → optional. Do not
fabricate findings to justify another round; if the plan holds, APPROVED is the correct answer.
Do not request scope outside the specification.

Do not implement anything. Do not modify files. Return your canonical contract.
```

⚠️ **The L3 text above is the round-1 restatement, not the authority.** This prompt is sent only at
round 1; from round 2 the delta prompt assigns no lens. The bidirectional anti-over-testing rule
lives in `spec-plan-reviewer.md` (the paragraph under the lens table), which reaches rounds 2+ and
the fresh-eyes gate through "cover all items in the table and the rules below it". Keep the two in
sync: changing only this block would make the reduction valid at round 1 alone.

## Delta

```text
Use the maat:spec-plan-reviewer agent.

Incremental review. The previous rounds already covered the rest of this plan — verify the
fixes and, above all, THE REGRESSIONS THE FIXES INTRODUCE. On this project it is measured that
applying findings introduces new ones: nine specs record it in their own words.

Spec + plan file: .claude/.ai-workflow/spec-<name>.md
Read ONLY these ranges (the lines rewritten since the last round): <offset/limit list>.
Plus the pertinent spec requirement at <offset/limit>.
Consistency-only lines (unchanged, but citing what the rewrite touched — check only that they
still agree with it): <xref line list, or "none">.
If a rewritten line changes the behaviour or signature of a shared symbol, check its direct
callers (one hop, no further).

Test level in force: <lvl>. Risk surfaces in force: <tokens>. State both here EVERY
round: those lines are written once at Step 1 and never rewritten, so they never fall inside a
delta range — without them the level-dependent caps (≤5 cases, whole-suite legality)
and the [floor: exemption are unenforceable from round 2.

Already resolved — do NOT re-raise: <finding key + anchored symbol/path + one line each>.
Exception: if a resolved finding's claim holds AGAIN on lines rewritten to resolve it, raise it
and call it "reintrodotto".
Rejected — anchor found literally false: <key + refutation, one line each>. Re-raise only with
NEW evidence.
Test cases removed as over-testing — do NOT re-add without NEW evidence: <one line each>.

Tool-call budget: ~<20 → 15 → 12, decreasing per round>, as a SOFT threshold — same rule as
before: an unverified lead on a possible blocker justifies +50%.
[the budget, anti-stall and anti-inflation paragraphs of «Round 1» apply unchanged]
```

## Fresh eyes

Full scope, one mandate: *which premise of this plan has never been questioned?* The rejected list is
re-examined too — a rejection is the orchestrator's own judgement, and this is where it gets a second look. No lens:
cover all the items of your checklist and the rules below it. Budget ~25, same anti-stall and anti-inflation
paragraphs as «Round 1».
