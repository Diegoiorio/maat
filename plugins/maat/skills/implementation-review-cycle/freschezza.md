# Freshness — the section already has a `Reviewed snapshot:` line

Read by `SKILL.md` Step 1 only in that case. The script decides what changed; you decide the path.

recorded `Scope:` and `Excluded:` lists to two scratch files and run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-surface.sh" check \
  --base <recorded base> --tree <recorded tree> --paths-file <scope file> \
  --exclude-file <excluded file> --fingerprint <recorded fp>
```

**The contract first.** If the section has a `Reviewed contract:` line and it differs from the
current `Basis:` of `plan-check.sh basis`, the spec or the plan changed after this review: the old
verdict answers a question nobody is asking any more. Run a **full-scope** round (Step 2), whatever
the code check says; if the recorded `Review status` was `APPROVED`, it is a post-approval round
(same budget as below).

**Then the recorded exclusions.** A path under the recorded `Excluded:` that is in the touched list
was reviewed by nobody, whatever `check` says: take it out of the exclude file, add it to the scope
file, and run a round (Step 2) on it — never the promotion or gate-only path for that invocation.
Its diff is the whole change **from the recorded base** (`review-surface.sh diff --from <recorded base>`),
never from the recorded tree: the file may not have moved since, and an empty delta would approve it
unseen. If the recorded `Review status` was `APPROVED`, it is a post-approval round (same budget).
(`/full-implementation-cycle` stops on this state; this is its recovery.)

It always compares against the **recorded** base (a commit after approval is not a change):
- `EXCLUDED-CHANGED <path>` lines (any status): an excluded file changed. Look at its delta; if it
  carries this feature's code, treat the result as `STALE` and move the path into scope.
- `Status: FRESH` and `Review status: APPROVED` → **promotion path**: skip Step 2, run only the
  required gates that are not `PASS` (Step 2.5), then Step 3. Costs no iteration.
- `Status: STALE` with `Gate-only eligible: yes` **and** the recorded `Review status: APPROVED`
  with no required gate `FAIL` and no `obligation:` row short of `PASS` → skip Step 2, re-run the
  gates on the new snapshot, then Step 3. Eligibility is decided by the script, never by you (a `no`
  line prints its reason): every changed path is a test file proper (`test_*.py`, `*_test.py`,
  `*.test|spec.[jt]s`) — a fake, helper, fixture, `conftest` or setup file under `tests/` is
  infrastructure and closes the path —, the delta has `Test signals: none`, and a test file that
  already existed in the approved tree (in the manifest or not) only **gained** lines: none removed or
  changed, no shared setup (`vi.mock`, `beforeEach`, `autouse`) and no control flow (`return`, `if`,
  `try`) added — those change tests a reviewer already saw. New test files keep the cheap path.
  After a `NEEDS_CHANGES` or a failed gate the gate-only path is closed: a fix to a failing test is
  exactly what a reviewer must see. So is a test written to close an obligation.
- `Status: STALE` otherwise → **APPROVAL STALE**: run Step 2 on the delta the script printed
  (`M/A/D` paths + `NEW-SURFACE`), with the delta prompt. If the previous section was `APPROVED`,
  this is a **post-approval delta round**: it has its own budget of one per stale snapshot, does
  not consume the 3 iterations, and a second `NEEDS_CHANGES` on post-approval deltas of the same
  plan → `NEEDS HUMAN DECISION`.
- `Status: STALE` whose delta is **only** `NEW-SURFACE` lines (new files nobody reviewed): each one is
  either this feature's or another flow's. You may exclude it — written reason, as for any exclusion —
  **except** a path in the touched list (see "Scope"), or a path that the plan section names, itself
  or through one of its directories (search it literally in the plan). Then re-run `check` with the
  extended `--exclude-file`: `FRESH` → promotion path, and the section is rewritten with the extended
  `Excluded:` list; otherwise the delta round below. For a new file not in the touched list, the
  rule for new files in "Scope" above applies too (plan search and the two greps in the reason).
- `Status: STALE (via fingerprint …)` or exit 3 `UNKNOWN` (tree pruned by `git gc`) → the delta
  cannot be rebuilt: run a **full-scope** round. Never approve on a delta you could not compute.
