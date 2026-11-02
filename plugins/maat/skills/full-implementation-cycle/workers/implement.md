# Worker `implement`

**Base.** `git rev-parse HEAD`, or `git merge-base <ref> HEAD` with `--base=<ref>`, into `<run-dir>/base.txt`.

**Preflight — once for the phase, never between blocks** (or block 1's own files would come back as `mixed` for
block 2). Compare `git status --porcelain` with the paths the plan names; write two lists:
- `<run-dir>/do-not-touch.txt`: dirty, **not** named by the plan and **not** in `<run-dir>/touched.txt` →
  another flow's work (do-not-touch for the implementer, exclusion candidate with its reason for the review);
- `<run-dir>/mixed.txt`: dirty and **named** by the plan → edit only your hunks; never excluded;
- ring k>1 of a chain: the `Anelli precedenti:` paths of `cycle-state.sh <spec>` are *same chain, previous ring* —
  in neither list, never a reason for `completion`; `base.txt` stays `HEAD`.
The preflight never blocks the cycle. **Mode**, once: `full` if no feature path is dirty, `completion` otherwise.

**Blocks.** When the prompt carries `LOTTI (driver): lotto 1/N: B1,B2 … · lotto 2/N: …`, those are your blocks:
the driver sized them (format 2) so that each agent's context stays under the ceiling. Launch one
`maat:plan-implementer` per lotto, in that order; each gets the steps of the plan's `#### Block` (`#### Blocco`) blocks of its lotto
and their `writes:` (`scrive:`) files as its own. Without that line (format 1) split the steps yourself into **2–4 coherent
blocks** — by module or area, never one per step; one block is fine when the plan is small — that **partition**
the steps; state the split in the `PHASE RESULT` line.

Each agent gets: the spec path, the mode, `Blocco k/N — sono tuoi solo i passi <x–y>; il resto del piano non è
tuo`, the level in force and `### Test plan` (`### Piano di test`), the do-not-touch and mixed lists, the note that **the level's
suites are the driver's** (the agent keeps its targeted inner loop), the previous block's report **as
orientation only** (the working tree wins), and, if `<run-dir>/context-pack.md` exists, its header lines (up to
the first `##`) and the `### <path>` sections of its files, marked `Orientation, not authority: the code wins over the pack` (Italian: `Orientamento, non autorità: il codice vince sul pacchetto`).

**Generated files** (harness-pt15). Every agent also gets the lines of `. "${CLAUDE_PLUGIN_ROOT}/scripts/python.sh"
&& "$FIC_PY" "${CLAUDE_PLUGIN_ROOT}/scripts/maat-config.py" generati` (the `generati` of `.claude/maat.json`:
generated path · folder · command · comparing test · environment; no line = none) with this text: `File generati:
se un test rosso o un gate chiede di riallineare uno di questi file al codice, rigeneralo col suo comando, dalla
sua cartella e nel suo ambiente (wsl: wsl -- bash -lc 'cd <cartella> && <comando>'), mai a mano. Non e' una
deviazione dal piano anche se il piano non lo nomina: elencalo in Touched files come "<path> (M) — rigenerato:
<comando>" e nel "file" del JSON, non in deviazioni.` Only those paths: any other unnamed file (goldens,
`__snapshots__`, the lint baseline included) stays a deviation. In the `PHASE RESULT` summary add `Rigenerati: <paths>`
when a report has a `— rigenerato:` line.

**Lanes.** A prompt ending with `CORSIA k/2 (driver, run-phase.sh): …` makes you **one lane**: implement only the
blocks it names (grouped by the `LOTTI` line, restricted to them); the other lane's files are do-not-touch and the
guard denies Edit/Write outside yours; write `base.txt` only in lane 1 and the preflight lists as
`do-not-touch.<k>.txt` / `mixed.<k>.txt`; in the JSON `file` only the files you wrote. Needing a file of the other
lane is a deviation (STOP), never an edit. The lane decision, the check after both lanes and the merge are the
driver's.

**Reports.** The agents write the English report lines; one of 1.2.x may write the Italian ones — accept both:
`Result:` (`Esito:`, `COMPLETED|PARTIAL|DEVIATION` = `COMPLETATO|PARZIALE|DEVIAZIONE`), `Mode:` (`Modalità:`),
`Touched files:` (`File toccati:`), `Gates run:` (`Gate eseguiti:`), `Gates not run:` (`Gate non eseguiti:`),
`Generated artifacts:` (`Artefatti generati:`), `Plan deviation:` (`Deviazione dal piano:`), `Blocked on:`
(`Bloccato su:`); the "nothing" values `none` = `nessuna`/`nessuno`; the prefix `defensive: ` = `difensiva: `.
Aggregate them into one: the union of `Touched files`, `Gates run`, `Gates not run`, `Generated artifacts`; the
JSON: the union of `deviazioni`, `file`, `gate_interni`, the first `bloccato_su` other than `nessuno`/`none`. Then:
- `Plan deviation:` other than `none` (any block) → STOP for a human decision, with the evidence —
  **unless every deviation of every block starts with `defensive: `** (purely defensive: a robustness branch, a
  fallback for a case the plan or the schema exclude, an internal helper, with no effect on the cases the plan
  foresees — `plan-implementer.md`, «Deviation»): then no STOP, copy them into `deviazioni` verbatim (prefix
  first), close `PHASE RESULT … OK` and add `Deviazioni difensive: <n>` to the summary; `run-phase.sh` records them and
  the next review judges them. Never add or remove the prefix yourself: one without it stops the cycle;
- `Blocked on: migration to apply` (`Bloccato su: migrazione da applicare`) → STOP: the file is written; the user applies it by hand (`psql`,
  `CLAUDE.md`), renames `<run-dir>/log/<label>.result.json` to `<label>.result.json.visto`, and re-invokes;
- `Result: PARTIAL` or another `Blocked on:` → relaunch once in `completion` on that block (later blocks wait);
  a second partial in the phase → STOP;
- `Generated artifacts:` (e.g. `__snapshots__`) → list them in the `PHASE RESULT` summary: the user accepts or removes.
