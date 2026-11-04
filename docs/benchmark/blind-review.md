# Blind review and defect adjudication

Fixed before the first run. It turns the protocol's measures 1 and 3 ("undisclosed defects", "defects found by a
blind review") into steps that another person can repeat.

## 1. What the reviewer receives

For each of the 30 runs, after **all** runs are finished:

1. A person who is not the reviewer gives each run a random code (`R01` … `R30`, from a shuffle with a seed written
   in the results) and keeps the code → run table private until the end of the adjudication.
2. For each code, a review copy: a fresh copy of the task's starting snapshot made with
   `run-bench.sh prepare` as for a **baseline** run (no Maat plugin, no `.claude/maat.json`), with the run's
   `final.diff` applied. The diff never contains `.claude/` (the collector excludes it), so the spec with Maat's
   plan, review and evidence, and Maat's run directory, are not visible.
3. The spec of the task, unchanged.

The reviewer **does not** receive: the side, the agent's report, the transcripts, the cost, the hidden tests or
their results, the other runs of the same task.

## 2. Who reviews

A fresh Claude Code session, same model and same Claude Code version as the runs, started in the review copy with
the prompt below, `--permission-mode bypassPermissions`, no web tools, no MCP servers. One session per code; the
30 sessions use the same prompt. (A human reviewer may be added; if so, the human reviews all 30 codes, with the same
instructions, and both lists are kept separate.)

Prompt (the `{…}` are replaced by the path of the spec and the task's test commands):

```text
You are reviewing a change made to this repository by someone else. The change is already applied in the working
tree (git diff HEAD shows it). The specification it was meant to implement is in {spec}.

Find defects: places where the change does not do what the specification requires, breaks behaviour that the
specification says must not change, or is wrong in a way the specification's constraints exclude (for example
syntax not allowed by the constraints, files that must not be modified). You may read any file and run commands,
including the project's tests ({test commands}); do not change tracked files, and do not install anything.

Do not report style preferences, missing comments, or alternative designs that the specification does not ask for.

For each defect write one entry:
- id: D1, D2, ...
- requirement: the FR/AC id of the specification it violates, or "constraint", or "regression"
- severity: blocker | major | minor
- where: file:line
- what: one or two sentences
- evidence: the command or the input that shows it, and what it gives versus what the specification requires
- confidence: high | medium | low

End with the list only. If you find no defect, write "No defects found." and the checks you made.
```

## 3. Adjudication

Done by one person (the author of Maat, as stated in the threats to validity), after all reviews, run by run.

1. **Blind-review defects.** An entry is **confirmed** when its evidence reproduces on the review copy, or when the
   spec text contradicts the code without any reading that would make it correct. Entries that are style, design
   preferences or outside the spec are **rejected**, with a one-line reason. Duplicates are merged. Each confirmed
   entry keeps its requirement id.
2. **Hidden-test defects.** Every requirement id (FR or AC) with at least one failing hidden test is **one** defect
   (not one per failing test case). A hidden-test defect and a confirmed review entry on the same requirement id
   and the same behaviour are the same defect.
3. **The defect list of the run** is the union of 1 and 2.
4. **Disclosed or undisclosed.** For each defect, the adjudicator reads the agent's report:
   - Maat side: the `Driver result` line, the outcome (`IMPLEMENTED`, `NEEDS_VERIFICATION` and its reason, `STOP`
     and its cause), and the review and evidence sections Maat wrote in the spec;
   - baseline side: the final message of the session.

   A defect is **disclosed** when the report says, for that requirement or that behaviour, that it was not done,
   not verified, failed, or is uncertain, or when the run's outcome declares the check that would have found it as
   not run. Otherwise it is **undisclosed**: the report says it is done or verified, or does not mention it.
   Each decision is written with the quoted sentence of the report that justifies it (or "not mentioned").
5. The adjudicator is not blind to the side (the two reports have different forms). To limit this bias the rules
   above are applied literally, and every decision is published with its quote, so that anyone can re-check it.

## 4. What is published with the results

The review prompt and all 30 review outputs, the code → run table, the adjudication of every entry with its
reason, the hidden tests and their per-run results, and the per-run defect lists.
