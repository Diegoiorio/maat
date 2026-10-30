# `--light` mode — the quick round to run ALWAYS after an implementation

**When to use it.** Right after implementing an approved plan and seeing the gates green.
It does not replace the full review: it is the bare minimum, and it costs a single agent round.

**Why it exists** (measured, 2026-08-05, spec `qa-debug-pt4`). The plan had passed **7 rounds** of
`spec-plan-reviewer`, and the implementation had **3357 backend + 1047 frontend + 162 e2e tests green**.
A single `--light` round still found **a real flaw**: a requirement that hid a section from a role
had a **fourth surface** — an ungated twin route, reachable with one click — that none of the 7
rounds had foreseen and that no test could catch, because the tests checked the three surfaces
*already found*.

The principle: **tests check what you thought of checking.** Review sees what you did not know
you had to look at. They are different nets, and neither is enough on its own.

**How it runs.** A single `implementation-reviewer` round, no iteration, narrow mandate,
on the surface computed by `review-surface.sh snapshot` (Step 1) — in `--light` too a bare
`git diff` is not enough. The agent prompt ALWAYS contains these four elements:

1. **Declare the green gates with their REAL numbers**, and explicitly forbid looking for what those
   gates would already have caught (typos, style, coverage in general). Without this the agent spends
   the round re-verifying what is already verified.
   ⚠️ **Also declare the level in force and the suites NOT run.** At `min`/`std` the suites of the
   untouched modules did not run: saying «the gates are green» about suites nobody executed is
   worse than saying nothing, because it forbids the round from looking exactly where nothing else looks.
   Element 1 of the mandate in `prompt-revisore.md` applies, and it governs **every** `implementation-reviewer` prompt.
2. **Ask ONLY for the classes tests cannot see:**
   - **blast radius** — who else consumes the shared files I touched, and breaks?
   - **forgotten surfaces** — if the change hides or gates something, is there another route to
     it that I did not find?
   - **interactions and loops** — middleware, redirects, guards that combine into a bounce
     or a cycle.
   - **test integrity** — if the snapshot's `Test signals` are not `none`: was the test
     changed to follow the spec or to fit the implementation?
3. **Strict reporting threshold**: only what would lead to changing the code. Something theoretical,
   or needing a condition that does not occur, is not reported. Ask for an explicit
   «class N: nothing» when a class is clean, so the absence of findings is data and
   not an ambiguity.
4. **Anti-stall instruction**: if it cannot complete, it must state the reason and how far it
   got instead of ending silently.

⚠️ **After applying the findings, RE-RUN the tests** — those of the touched modules, not everything.
Applying this review's findings introduces regressions like any other change:
in the reference session, fixing one finding broke 5 tests (a module mock that did not
cover a new export). It is the counterproof of the principle above, in the other direction.

In `--light` the `## Review implementazione` section is not written unless blocking findings
emerge: the quick round lives in the conversation, and **never** leads to `IMPLEMENTED`. If it
writes it, it does **not** write the `Reviewed snapshot:` line: the quick round looked only at the narrow
classes, so it is not a basis on which a later review may limit itself to the delta — the full
round that follows is full-scope. The iteration
budget is **1**, not 3. The response still declares `Verification:` with the same semantics as the
full branch, so a quick round without tests does not read as verified.
