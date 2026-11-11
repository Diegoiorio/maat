# Harness tests

Applies to the `plugins/maat` plugin of this repo: how to run the suites on Windows and on Linux, the genericity
test, the expected outputs of the public examples (the proof of the driver), and the old-against-new oracle.

## The two roots

| variable | what it is | how it is resolved |
|---|---|---|
| `MAAT_ROOT` | the plugin root (`scripts/`, `skills/`, `agents/`, `schemas/`) | `MAAT_ROOT` from the environment, otherwise two levels above `scripts/lib/maat-paths.sh`; it must contain `.claude-plugin/plugin.json`, otherwise exit 4 |
| `PROJECT_ROOT` | the root of the project the cycle works on | `FIC_REPO`, otherwise `git rev-parse --show-toplevel` from the **working directory** (never from the script's location); outside a git repo: clear error, exit 4 |
| `MAAT_SCRIPTS`, `MAAT_SKILLS`, `MAAT_AGENTS`, `MAAT_SCHEMAS` | under `MAAT_ROOT` | — |
| `MAAT_WORK` | the project's working folder | `PROJECT_ROOT/<cartelle.lavoro>` from `.claude/maat.json` (default `.claude/.ai-workflow`) |

There is a single resolver: `scripts/lib/maat-paths.sh` (bash, sourced with `.`) and `scripts/maat_paths.py` (Python,
same rules). Run directly, each prints the variables one per line, in the form `NAME=value`:

```bash
cd <project> && bash <plugin>/scripts/lib/maat-paths.sh
```

The lock of the code phases does **not** use `PROJECT_ROOT`: `run-phase.sh` computes it with
`git rev-parse --absolute-git-dir` from the working directory (in a linked worktree it is the worktree's).
`FIC_LOCK` overrides it.

## Override environment variables

The names are the same as before; only the default changes.

| group | variables | default |
|---|---|---|
| harness root | `FIC_GATES_HARNESS` (gates.sh, finalize.sh), `CONTEXT_PACK_HARNESS`, `HARNESS_MERGE_HARNESS`, `FIC_DRIVER_ROOT` | `MAAT_ROOT` |
| repository to read | `FIC_GATES_ROOT`, `CONTEXT_PACK_ROOT` | `PROJECT_ROOT` |
| plugin in the subsession | `MAAT_PLUGIN_DIR` | unset: no `--plugin-dir` (the plugin is enabled in the project); `replay.sh` always sets it |
| repo and lock | `FIC_REPO`, `FIC_LOCK` | toplevel of the working directory · git dir of the working directory |
| cycle components | `FIC_RUN_PHASE`, `FIC_CONTEXT_PACK`, `FIC_GATES`, `FIC_FINALIZE`, `FIC_DRIVER_PY`, … | the plugin's scripts |
| state of the cycle in `run` (tests) | `FIC_CYCLE_STATE`: `driver.py run` reads `Next`/`State` from that script instead of its own `next` (like `FIC_RUN_PHASE`) | unset: `driver.py next` |
| other | `PLAN_CHECK_ROOT`, `CLAUDE_BIN`, `FIC_PYTHON`, `MAAT_CONFIG` | — |

Under an overridden harness root the plugin structure applies: a mutated copy of the plugin (test counterproofs) is
passed whole, not just one script.

**One engine (1.6.0).** `driver.py` decides `next` and `valida`; `cycle-state.sh` and `run-phase.sh` (for `valida`) are
its wrappers, with the same interface as before. There is no other engine and no engine to choose: the bash table and
the internal validator (`VALIDA_PY`) are gone, and so are `run-phase.sh --valida`, `driver.py equiv` and
`certificato`, `driver.equiv`, `tools/certifica.sh` and `FIC_DRIVER_CERT`. **`FIC_DRIVER`** no longer has any effect:
set and not empty (`0`, `1`, anything) `driver.py run` prints one `AVVISO: FIC_DRIVER=<value> …` per invocation (an
event, also in `driver.log`) and `maat-doctor` a `WARNING`; the wrappers say nothing (`cycle-state.sh` runs dozens of
times per cycle and other scripts read its output); empty, it is the default as in 1.5.1. The bash engine is in Maat
1.5.1: going back is reinstalling it (README, «Going back to 1.5.1»).

First, the Python check: no interpreter (`python.sh` fails) or one older than 3.10 → `Next: STOP — …`
(`cycle-state.sh`), `PHASE RESULT <phase>: STOP — …` (`run-phase.sh`), `Driver result: STOP — …` (`run`), with the
remedy `FIC_PYTHON=<python 3.10 or newer>`; the threshold is in two places, `fic_py_min_ok` of `python.sh` (also used
by `maat-doctor`) and `PY_MIN` of `driver.py`, and `driver.test.sh` checks they agree. A driver that fails is a `STOP`
with the reason, never a fallback.

**The prefix «catena:» (`chain:` in `en`) on an exit 7.** `run-phase.sh` exits 7 («not launched») for a chain STOP
(rows C1-C4), and also when it cannot read the state of the cycle before launching (`cycle-state.sh` gives no `State:`
line: for example no Python, one older than 3.10, or `driver.py next` failed). `driver.py run` does not tell the two
apart: on every exit 7 that is not a `WAIT — catena` it prints `Driver result: STOP — catena: <the last lines of the
phase's stderr, up to three, joined by « | »>`. So the word «catena» does not mean that the cycle is a chain: the
reason is the text after it. For a failed `driver.py next`, since 1.5.1 its whole stderr (the traceback) is in the
phase's `.stderr` before the STOP line, so the line reads `STOP — catena: <end of the traceback> | STOP — driver.py
next non riuscito (exit 1): <last line> — dalla Maat 1.6.0 non c'e' un altro motore … — fase non lanciata`. `driver.test.sh` checks that the `Driver result:`
line holds the reason too, not only the prefix.

**Message language (`MAAT_LINGUA`, 1.4.0).** The messages the scripts print for a person come from the catalog
`scripts/lib/messages.tsv` (`msg` in bash, `lib/maat-msg.sh`; `T` in Python, `maat_msg.py`). The language is
`MAAT_LINGUA` (`it|en`; any other value: `en`; empty: unset), otherwise `lingua` of `.claude/maat.json`, otherwise
`en`; `guard.py` follows the same precedence. Since 1.5.0 `run-phase.sh` adds `MAAT_LINGUA` to `WSLENV` (no
duplicate, the entries and flags already there kept), so a value set by hand also reaches what the phase session and
each lane run in `wsl`, instead of the `lingua` read again there from `.claude/maat.json`. The section below says how
the two languages are tested.

## The two languages (1.4.0)

- **Italian, unchanged.** Every suite starts with `export MAAT_LINGUA=it`: its assertions are on the Italian text,
  the same as in 1.3.0, so a green suite proves that `"lingua": "it"` prints what 1.3.0 printed. The cases that test
  the reading of `lingua` (guard, session-start, maat-config) drop the variable (`env -u MAAT_LINGUA` or a local
  `unset`).
- **English cases.** Next to the Italian ones, the suites of the scripts that print messages have cases with
  `MAAT_LINGUA=en` on their main output: the English text is there and no Italian is left, except the frozen lines. `cycle-state.test.sh` runs every `expect`
  in English too (`CS_EN=0` skips that part, it makes the suite slower). In `plan-check.test.sh`,
  `MAAT_VINCOLO2=1` checks that the stdout of `basis` and `contract` is byte for byte the same with `MAAT_LINGUA=it`,
  with `MAAT_LINGUA=en` and with `plan-check.sh` of `v1.3.0` (off by default).
- **The catalog and the anti-leak test.** `messages.test.sh` tests `scripts/lib/messages.tsv`: bash and Python give
  the same language and the same bytes, the catalog format (unique keys, the same placeholders in both columns, no
  Italian in the `en` column, no key missing or unused), the fallback `‹key›`, and the static **anti-leak** test: no
  Italian literal in a plugin script outside the catalog and `scripts/lib/protocol-strings.list`. Its counterproofs
  run on a mutated copy of the plugin (an Italian `echo` added, a list entry deleted…) and must be red.
- **The inventory.** `python tools/lingua-inventario.py` (read-only) scans every `.sh`/`.py` of the plugin and prints
  the residual: the lines that still hold Italian once the frozen parts of `protocol-strings.list` are taken out
  (`--rows` lists them; an entry of the list that covers nothing is reported as unused).
  `python tools/lingua-inventario.py --consumers` looks at the other side: the places (scripts, tests, skills,
  agents) that read Italian text another script prints. `messages.test.sh` uses the same scanner; outside the repo
  (plugin installed in the cache) those sections are skipped with the reason.
- **The conversion.** The messages were moved by `tools/lingua-converti.py` from the tables of
  `tools/lingua-conversioni/`. `check <table>` compares every Italian entry with its literal in `v1.3.0`;
  `copertura <table>...` checks that every Italian-looking literal of the cited lines is covered by an entry, or
  declared in `non-messaggi.list` or `protocol-strings.list` (a wrong `#n` index passes `check`, not `copertura`).
  Run both, on all the tables, after any change to a table; a one-word literal outside the scanner vocabulary is
  seen by neither, so check those rows by hand.
- **The conversion tables in the suite (1.5.0).** Section 10 of `messages.test.sh` runs `copertura` on all the
  tables and `check` on each one, so nobody has to remember it. Like the anti-leak test it works in the repo only: it
  is SKIPPED, with the reason, from the installed plugin or in a clone without the tag `v1.3.0` (a shallow clone).
  On GitHub Actions a skip is a FAIL (the CI clones with `fetch-depth: 0`, tags included).
- **The decider in both languages (1.6.0).** The expected outputs of the public examples have one file per language
  for `next` (`next-it.txt`, `next-en.txt`) and one per validator and language for `valida`
  (`valida-<minimo|jsonschema>-<it|en>.txt`): the driver is compared in `it` and in `en` at every run of
  `tools/esempi-equiv.test.sh` («The expected outputs»). Until 1.5.1 section 9 of `driver.test.sh` compared the
  driver with the bash table on every case of `cycle-state.test.sh`; it went with the bash table.
- **Frozen lines.** `protocol-strings.list` says, line by line, which Italian text stays in every language and why
  (the lines that scripts pass to each other, the keywords `VIOLAZIONE`, `AVVISO`, `ERRORE DURO`, `Percorso:`,
  `Scheletro:`, `S2:`). A new Italian literal goes either into the catalog or into the list, with its reason.

## How to run the suites from the plugin

Each suite creates its own synthetic repos in a temporary folder and touches neither the plugin repo nor a real
project. From Git Bash:

```bash
bash plugins/maat/scripts/<name>.test.sh
```

- Short: `maat-paths`, `maat-config`, `gates`, `finalize`, `ciclo-worktree`, `context-pack`, `cycle-report`,
  `harness-merge`, `guard`, `stop-hook`, `session-start`, `phase-usage`, `blocks-independent`, `phase-events`,
  `test-review-surface.sh`, `plan-check`,
  `senza-wsl` (pk08: Windows without WSL, PATH without `wsl`/`wsl.exe`; about 5 minutes, two `run-phase.sh` phases),
  `spazi` (pk08: plugin, project, run dir and worktree with spaces and «à»; about 5 minutes on Windows, 1 on Linux;
  also on Linux, from the clone in WSL with `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin FIC_WT_WSL=0`).
- Long (one at a time, in the background): `cycle-state`, `run-phase`, `driver` (since 1.6.0 about 1–1.5 minutes on
  Linux: no more section 9).
- **One engine in the suites too (1.6.0).** `cycle-state.test.sh` and `run-phase.test.sh` test the driver through
  its wrappers. A **mutation counterproof** of a row of the table or of a branch of the validator is a mutated copy of
  `driver.py`, given with `FIC_DRIVER_PY=<copy>` (the variants `CS=` and `RP=` change the wrapper, not the decision).
- In WSL (they need `rsync` and `flock`): `test-fast.test.sh`, `vitest-classify.test.sh`, `counterproof.test.sh`,
  `comandi-equivalenza.test.sh`. Since 1.5.0 `comandi-equivalenza.test.sh` reads no git history, so it also runs in
  WSL on a worktree created from Windows (see «The commands of the gates: frozen reference»).
- Tests of the repo, in `tools/` (they make sense only in the repo, not from the installed plugin):
  `tools/suite.test.sh`, `tools/esempi-equiv.test.sh` (the public examples and their expected outputs),
  `tools/oracolo.test.sh` (the old-against-new oracle). Run them from the repo root: `bash tools/<name>.test.sh`.
- Skipped with a declared reason (specific to the guide project): part 2 of `vitest-classify.test.sh`.
  `guard.test.sh` (pk05) tests the plugin hook (`guard-hook.sh`) and its equivalence with the guide project's guard
  on the fixture `tests/guard-esempio.cases`.
- `maat-paths.test.sh` also contains the **anti-structure search**: no reference to the guide project's structure
  (`.claude/skills/`, `script/fic`, `script/test`, `$HERE/../..`, `/../test`, `/../../../script/`) outside comments and
  tests, with the exclusions declared in the test (project commands of the WSL wrappers until pk04b; the fingerprint
  one was closed by pk04a-2).

## Windows and Linux

**Windows** (Git Bash, from the worktree or from the clone on `C:`): `bash plugins/maat/scripts/<name>.test.sh`, one
suite at a time. The three WSL suites (`test-fast`, `counterproof`, `vitest-classify`) are run from WSL on the same
folder:

```bash
wsl -- bash -lc 'cd /mnt/c/<…>/maat && bash plugins/maat/scripts/test-fast.test.sh'
```

**Linux.** There is no dedicated Linux machine: a **clone inside WSL** is used with a pure Linux PATH, so that no
Windows tool (`cmd.exe`, `wsl.exe`, `py.exe`, the Store Python) gets into the test.

```bash
wsl -- bash -lc 'git clone -b <branch> /mnt/c/<…>/maat ~/maat-linux'      # once; then git fetch and reset on the branch
wsl -- bash -lc 'cd ~/maat-linux && PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin FIC_WT_WSL=0 \
  timeout 5400 bash plugins/maat/scripts/<name>.test.sh'
```

- `FIC_WT_WSL=0` tells the worktree tests not to go through WSL: on Linux they are already at home.
- The clone must be realigned to the branch before every run (files copied by hand disappear): no changes inside the
  clone.
- Git cannot read a worktree created from Windows from inside WSL (its `.git` points to `C:/`): the few cases that
  need the history of this repo (the oracle with git refs) are SKIPPED there and run on the Linux clone.
- `MAAT_ORACOLO_121=1 bash plugins/maat/scripts/plan-check.test.sh` also compares, on every Italian fixture, the
  output of `plan-check.sh` of 1.2.1 (commit `a2c5b99`, read with git) with the current one, byte for byte: the proof
  that 1.3.0 reads the Italian formats as before. Off by default (it doubles the run time).

**The full run** (all suites, Linux first then Windows, one at a time, with a summary per platform):
`bash tools/giro-completo.sh <results folder> <worktree> <branch>`, from Git Bash. `<worktree>` is the Windows folder
of the branch to test, in the form `/c/…`; `<branch>` is the branch the Linux clone is realigned to; the clone is
always `~/maat-linux` (another one with `MAAT_LINUX_CLONE`). For example:
`bash tools/giro-completo.sh /tmp/esiti /c/<…>/maat-lavoro wip/lavoro`. Each suite writes
`<folder>/<linux|windows>/<name>.log` and one line in `riepilogo.txt` (exit code, seconds, last line). Duration: about
40 minutes on Linux, about 10 hours on Windows (1.5.0), because of the long suites. Two options (1.5.1), before the
arguments:

- `--linux-parallelo`: the Linux part with `tools/suite-parallelo.sh` (below), three clones at once, about 15 minutes
  instead of 40. Clones in `MAAT_LINUX_CLONI` (relative to the WSL home, default `maat-linux maat-linux-2
  maat-linux-3`). If the machine is busy the run stops before the Windows part.
- `--windows-breve`: the Windows part runs only the short proof (below), about 50 minutes.

For a release since 1.5.1: `bash tools/giro-completo.sh --windows-breve <folder> <worktree> <branch>` (the Linux part
one suite at a time). `--linux-parallelo` is not for a release yet: its acceptance on the real suites is still to be
done («The parallel run», last point).

- In the Windows part most suites run in Git Bash on the worktree; the suites that need `rsync` and `flock`
  (`test-fast`, `counterproof`, `vitest-classify`, `comandi-equivalenza`) and `tools/oracolo.test.sh` run in WSL on
  the same worktree (`/mnt/c/…`). `tools/esempi-equiv.test.sh` stays in Git Bash on purpose: it is the proof of the
  driver on Windows (see «The expected outputs»).
- **Guard of the run (1.5.0).** Don't touch the plugin while the run is going: the harness fingerprint changes and
  the suites that check it fail for no real reason. `giro-completo.sh` and `tools/suite.sh` take a fingerprint of the
  plugin files (the list of `run-phase.sh --harness-paths`, content without CR) before the first suite and after each
  one; a suite after which it changed gets `PLUGIN CAMBIATO` in its line of `riepilogo.txt`, and the exit is 1. On
  Linux the fingerprint is taken on the clone.
- At the top of both `riepilogo.txt`, an `AVVISO` line when the Linux clone is not at the commit of the worktree, or
  when the worktree has uncommitted changes under `plugins/` or `tools/`: the two parts would not test the same tree.

**Times on Windows and on Linux.** The proof on the public examples is slow in Git Bash: `review-surface.sh` runs
`git add -A` on a temporary index for every check, and process start-up costs much more on Windows.

| what | Git Bash (Windows) | WSL or Linux |
|---|---|---|
| `tools/esempi-equiv.test.sh` (1.6.0: the expected outputs) | the corpus alone (build, 130 `next`, 196 `valida`) about 1 hour, measured on a busy machine; about 18 minutes (1091 s) on the CI runner | about 2 minutes (127 s, both validators) |
| `tools/oracolo.test.sh`, the oracle on the whole corpus | about 70 minutes (1.5.0) | about 6 minutes |
| `plugins/maat/scripts/driver.test.sh` (1.6.0) | about 7 minutes (409 s) on the CI runner | about 1–1.5 minutes (59–85 s) |

The corpus has 65 specs, almost one per row of the table plus the mothers and rings of the chains: it is kept whole,
not trimmed for speed. That is why the full run sends `tools/oracolo.test.sh` to WSL in its Windows part too, and why
the expected outputs are written from Linux.

**The list of suites** is `tools/suite.list`, one name per line, in the order they run; `giro-completo.sh` and
`tools/suite.sh` both read it. A plain name is `plugins/maat/scripts/<name>.test.sh`; an entry with a `/` is a path
from the repo root (`tools/esempi-equiv.test.sh`). Both scripts resolve an entry with the same function (`suite_file`,
`tools/lib/guardia-plugin.sh`). A new suite goes into the list: `tools/suite.sh` refuses (exit 2) a list that misses a
`*.test.sh` of the plugin or a `tools/*.test.sh`, or names a file that does not exist.

**The groups (1.5.1)** are `tools/suite-gruppi.list`, one line `<group> <entry>`: three groups of similar length on
Linux (about 13.5 minutes each on the clone in WSL), used by the CI (one job per group) and by the parallel run (one
clone per group). `bash tools/suite.sh --gruppo <k>/<n> <folder>` runs group k only, in the order of `suite.list`, and
refuses (exit 2) a groups file that does not cover `suite.list` exactly (an entry in no group or in two, an entry not
in the list) or that has not exactly the groups 1..n. A new suite goes into both files; to rebalance, move a line
using the times of the last `riepilogo.txt`. `tools/esempi-equiv.test.sh`, the one that reads `MAAT_ATTESE_RICHIESTE`,
is in group 3. Since 1.6.0 the same three groups run on macOS, and Windows has its own groups file,
`tools/suite-gruppi-windows.list` (five groups balanced on the times of the CI runner, and lines `- <entry> <reason>`
for what is left out there), read with `bash tools/suite.sh --gruppi tools/suite-gruppi-windows.list --gruppo <k>/5
<folder>`; a line `<group> VAR=value <entry>` runs that suite with the variable. Since 1.6.0 the Linux groups are
shorter (block C) and not rebalanced: the longest job is about 12 minutes.

### The parallel run (1.5.1)

`bash tools/suite-parallelo.sh <folder> <ref>`, from Linux or WSL, from any checkout of the repo: group k of
`tools/suite-gruppi.list` runs in clone k (`MAAT_LINUX_CLONI`, one clone per group, relative to `$HOME` or absolute,
default `maat-linux maat-linux-2 maat-linux-3`), all at the same time, each with `tools/suite.sh --gruppo k/n`. Create
the clones once (`git clone <repo> ~/maat-linux-2`, …) with origin pointing to a repo that has `<ref>`; the script
realigns them (fetch, `checkout --detach`, `clean`), so nothing must be changed inside them.

- **It does not start (exit 3)** when the machine is busy: another parallel run (a lock, `MAAT_PARALLELO_LOCK`),
  `tools/esempi-equiv/attese.sh --scrivi` running (the expected outputs are never written together with anything,
  and the parallel run never runs together with that writing), or a Maat cycle running on Windows (a Windows process whose command line has
  `driver.py run`, read from WSL through `powershell.exe`; outside WSL this part is skipped). `MAAT_PARALLELO_FORZA=1`
  skips the check of the processes, not the lock. A cycle on Linux is not seen: don't start the run while one goes.
- **A suite red in parallel is run again alone**, in its clone, after every group has ended. Green alone: its line of
  `riepilogo.txt` says `ROSSA SOLO IN PARALLELO` and it counts as green, but it depends on the others (load, a shared
  path) and goes into a group of its own; red again: `ROSSA ANCHE DA SOLA`, exit 1. A suite after which its clone's
  plugin changed (`PLUGIN CAMBIATO`, the guard of `suite.sh` on each clone) is not run again.
- `<folder>/riepilogo.txt`: one line per suite in the order of `suite.list` (`g<group>`, exit, seconds, last line),
  then `parallelo: gruppi=… · in parallelo …s · con i rilanci …s · rosse=… · rosse-solo-in-parallelo=…` and `FINE`;
  `<folder>/gruppo-<k>/` holds the logs; `<folder>/clone.txt` the commit of each clone (all the same, otherwise exit 2).
- Before 1.5.1 the suites were checked for shared state: they create their files in `mktemp -d` and set a `HOME` of
  their own where it matters (`test-fast`, `counterproof`, the cycle suites); `guard.test.sh` sets a fixed
  `SCRATCH=/tmp/claude/scratch` that nothing uses.
- **Not yet accepted on the real suites: the acceptance is still to be done.** Its own cases are in
  `tools/suite.test.sh` (section 7: fake clones, a suite red only in parallel, a suite always red, the lock, a
  counterproof). The acceptance is the parallel run and the run one at a time on the same commit, on the same machine,
  with the same outcome for every suite. The CI does not replace it: its groups run on separate runners, so they share
  neither the machine, nor the load, nor `/tmp`, which are exactly what the parallel run puts at risk. Until then the
  parallel run is only a quick local check, and a release runs the Linux part one suite at a time (or on the CI).

### The short proof on Windows (1.5.1)

Since 1.5.1 a release does not run the whole Windows part (about 10 hours in Git Bash) but a short proof:
`tools/prova-breve-windows.list`, the quick suites in Git Bash, about 48 minutes (1.5.0 times: `tools/suite.test.sh`,
`stop-hook`, `blocks-independent`, `phase-usage`, `session-start`, `harness-merge`, `phase-events`, `maat-config`,
`context-pack`, `genericita`, `senza-wsl`, `maat-paths`, `messages`, `cycle-report`, `guard`, `bash-node`,
`test-review-surface`, `gates`). It runs with `bash tools/giro-completo.sh --windows-breve …`. A line may start with
`VAR=value` words, which the suite runs with. Since 1.6.0 it stays as an optional local proof: the Windows proof is
the CI, which runs every suite on Windows at every push except the oracle and the four suites that need WSL. `rollback.test.sh`, left out of the list in 1.5.1, went
with the bash engine.

## CI

`.github/workflows/ci.yml` runs at every push and pull request on GitHub, and by hand (`workflow_dispatch`). Since
1.6.0 on three platforms, every job of every platform at the same time: Linux and macOS run the three groups of
`tools/suite-gruppi.list`, Windows the five of `tools/suite-gruppi-windows.list`. The final jobs `linux`, `macos` and
`windows` are green only if all the groups of their platform are, and **`ci`** only if all three are: `ci` is the
check to require on `main`. `concurrency`: on a branch a new push stops the run of the same event and branch still
going; on `main` and on tags every commit has its own run, never cancelled. Limits per job (about 1.5 × the longest
measured job, rounded up to 5 minutes): Linux 25 minutes, Windows 40 (worst job 1546 s), macOS 30 (longest 984 s,
with the Homebrew setup). Since 1.8.0 each job also sets `MAAT_SUITE_TIMEOUT`, the limit of each suite in
`tools/suite.sh`, below the job's: 1200 s on Linux and macOS, 1800 s on Windows (`tools/suite.test.sh` checks that
every job of the groups sets it below `timeout-minutes` × 60). A suite that hangs then ends with `rc=124` and a line
`TIMEOUT <entry> dopo <s> s` followed by the last 20 lines of its log, and the job goes on with the next suite instead
of dying without saying which one. In the log of every job, a line `suite: avvio <entry>` before each suite; after a
red suite, its `^FAIL` lines (at most 10) are printed and written in `riepilogo.txt` under its line, so the case
that failed is read in the job log, without downloading the artifact. **Windows**:
Git Bash of the runner, `FIC_PYTHON` = the Python 3.10 of `setup-python` (otherwise `py -3` would choose the newest),
the `jsonschema` venv in `Scripts/python.exe`, `core.autocrlf false`, `TEMP` rewritten in its long form (the runner
gives `C:\Users\RUNNER~1\…`, which Python expands and bash does not). The whole Windows run goes at every push: the
rule is complete at every push if it fits in at most 8 jobs of at most 45 minutes, and it is 5 jobs of about 16–22
minutes. Left out on Windows, with the reason in its groups file: `test-fast`, `counterproof`, `vitest-classify`,
`comandi-equivalenza` (they need `rsync` and `flock`; on Windows they run in WSL, which the runner does not have: run
them locally from WSL before each release) and `tools/oracolo.test.sh` (it runs on Linux and macOS). **macOS**:
`setup-python` first, then `brew install` of bash and the GNU tools (with a cache of the downloads), their `gnubin`
folders first in `PATH`, `awk` = gawk, `TMPDIR=$RUNNER_TEMP`; the runner usually has 3 CPUs, so the step 2 cases of
`counterproof` (they want at least 4) are `SALTATO` there with the reason. The longest job: Linux about 12 minutes,
macOS about 16, Windows about 22. **On Linux**, since
1.5.1 in **three jobs at the same time**, one per group of `tools/suite-gruppi.list` («The groups»): each one `ubuntu-latest`, Python 3.10 (the lowest
supported version), Node 20, a test git identity, the `jsonschema` venv, then `bash tools/suite.sh --gruppo <k>/<n>
esiti`, one suite at a time with `FIC_WT_WSL=0` like the Linux run. `n` is not written by hand: it is
`strategy.job-total`, the number of jobs of the matrix, and `k` (`matrix.gruppo`) must be the job's position
(`strategy.job-index` + 1), so the matrix is exactly 1..n. A job fails if a suite exits with a code other than 0, if
`k` is not its position, or if the groups file does not match `suite.list` or has not exactly the groups 1..n — so a
matrix with fewer jobs than the file has groups is red, never green without a group. `tools/suite.test.sh` checks
the link on `ci.yml` itself (the matrix is 1..n with n = the groups of the file, the argument is built from
`strategy.job-total`); its logs and
`riepilogo.txt` are kept as the artifact `esiti-<platform>-<k>` (`fail-fast: false`, so a red group does not stop the
others). Locally the
same run is `bash tools/suite.sh <results folder>` from a Linux clone, or the parallel run.

**The two validators (1.5.0).** The outcome validator, `driver.py valida`, uses the `jsonschema` module when the
interpreter has it, a minimal validator otherwise. The CI proves both: the system Python has no `jsonschema` (minimal
validator), and a step creates a venv of its own with `jsonschema==4.23.0` and exports `MAAT_PY_JSONSCHEMA` to its
interpreter. `tools/esempi-equiv.test.sh` compares the expected outputs of each validator.

**Strict checks of the expected outputs (1.6.0).** With `MAAT_ATTESE_RICHIESTE=1`, set by the CI at **every** push and
pull request (stricter than `MAAT_CERT_RICHIESTO` of 1.5.x, which was on only for `main`, tags and pull requests to
`main`), `tools/esempi-equiv.test.sh` is red when a validator is `SALTATO`, and when a file of
`tools/esempi-equiv/attese/` changed since the base (the merge-base with `origin/main`; on `main` and tags the previous
commit) without a new line in `attese/STORIA` (`attese.sh --storia`). So a change of an output is never silent: the
expected outputs are rewritten with `attese.sh --scrivi --motivo …` in the same pull request, and the diff shows
what changes («The expected outputs»). A change of `driver.py` or of the catalog that does not change an output needs
nothing more (in 1.5.x it made the certificate expire).

What CI does not cover: on Windows the four suites that need WSL (run locally before each release) and the oracle
(run on Linux and macOS); on a macOS runner with fewer than 4 CPUs, the parallel step of `counterproof`. What
skips with a declared reason, as in the Linux clone: part 2 of `vitest-classify.test.sh` (specific to the guide
project). Since 1.5.0 `comandi-equivalenza.test.sh` and section 10 of `messages.test.sh` run in CI too.

## The commands of the gates: frozen reference

`comandi-equivalenza.test.sh` compares the commands the gates run (`gates.sh`, `finalize.sh`) on a synthetic
repository with those of the reference harness, the last one with hard-wired commands (a commit of the private
development history). Until 1.4.0 it read that commit with git, so it was SKIPPED everywhere the commit was missing,
which means everywhere outside the private repo.

Since 1.5.0 the output of the reference side is **frozen** in `plugins/maat/tests/comandi-equivalenza/riferimento.txt`
(one section per case and view, already normalized). The test compares the current plugin with that file and reads
no git history, so it runs in WSL and on Linux, in CI included. It needs `rsync` and `flock`.

- The synthetic repository is deterministic: fixed git identity and dates, no git configuration of the machine, a fake
  `node` that prints `v20.0.0`, `TZ=UTC`. The normalizations are declared at the top of the test: `<repo>`, `<copia>`,
  `<report>`, the base commit as `<base>` and, in the view `chiave`, `tree=<40 hex digits>` as `tree=<tree>`.
- A **hygiene** case checks the reference itself: no `node=v` other than the fake's, no `tz_wsl=` other than the fixed
  one, no 40-digit sha.
- **Regenerating it** needs the private history: `MAAT_RIF_REPO=<repo with the reference commit> bash
  plugins/maat/scripts/comandi-equivalenza.test.sh --rigenera` runs the reference side, rewrites
  `riferimento.txt` and then compares. Do it only when a normalization changes; the file changes only together with
  the test.

## Genericity

`genericita.test.sh` (Git Bash or WSL) checks that the plugin does not carry the guide project along with it.

1. **Core** (`scripts/`, `skills/`, `agents/`, `hooks/`, `schemas/`): none of the guide project's names (paths,
   services, `.nuxt`, …), outside the test fixtures and the exceptions declared in the test, each with its reason.
   An exception that no longer covers any line is a FAIL. The runner lines (`junitxml`, `--reporter=json`) live only
   in the profiles and the examples.
2. **Documentation** (the repo's `docs/`, except `docs/piani/`; the `README.md` of the repo and of the plugin): no
   name of the guide project. Exception: the real file names of the plugin (`guard-esempio.cases`,
   `nuxt-fastapi.maat.json`). The proper names of your guide project (name, host, services) are not in the repo: put
   them, one per line as regex alternatives, in the local file `.genericita-nomi` at the repo root (ignored by git),
   or point to another file with `MAAT_NOMI_RISERVATI`. Without the file the test checks only the generic names and a
   fake name, used by the counterproofs.
3. **Guide links:** every internal `href` of `docs/GUIDA-FLUSSI.html` leads to an anchor (`id`) that exists in the
   page or to a file that exists next to the guide. `http(s):`, `mailto:` and `data:` are not checked. Only grep and
   existence tests: no link checker to install.
4. **Mutation counterproofs**, on copies: a guide project name in a comment of `gates.sh` ⇒ red; a name in a copy of
   the guide ⇒ red; an `href` to a nonexistent file or a nonexistent anchor ⇒ red; the restored copy turns green
   again.

## The `MAAT_ROOT` snapshot

The plugin must never receive project files. `maat-paths.test.sh` (section 8) works on a **copy** of the plugin and
takes a snapshot of it before and after (every file with its sha256, including new and deleted files): any
difference makes the suite fail. The snapshot is used instead of `chmod -R a-w`, which on Windows/MSYS does not
prevent creating files. The Python sources set `sys.dont_write_bytecode = True` before importing `maat_paths`, so
no `__pycache__` appears under the plugin.

```bash
snap() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum); }
```

## The harness fingerprint (pk04a-2)

On a cycle's first launch `run-phase.sh` writes `<run-dir>/harness.fp`, three lines:

```text
impronta=<64 hex digits>
versione=<version from .claude-plugin/plugin.json>
radice=<MAAT_ROOT, in the form C:/…>
```

(`impronta` = fingerprint, `versione` = version, `radice` = root.)

- **What goes in:** every file under `MAAT_ROOT` (relative path, `LC_ALL=C` order, sha256 of the content without CR)
  except the single `HARNESS_EXCLUDE` list of `run-phase.sh` — `__pycache__`, `assets`, `*.swp`, `*.orig`,
  `.DS_Store`, `*~`, matched against every path component — plus `<project>/.claude/maat.json` (absent: a fixed
  line, so creating or deleting it changes the fingerprint), and since 1.4.0 a line `lingua <it|en>` with the
  **resolved** language of the messages (`MAAT_LINGUA`, otherwise `lingua` of `maat.json`, otherwise `en`): changing
  the language in the middle of a cycle stops it like any other change of the harness. No git and no `.gitignore`: a stray file left in the
  plugin folder (for example a `.bak`) stops the cycles. The **project's** skills (for example `dev-verify`) are not
  part of it: changing one does not stop a cycle.
- **Who decides:** a single function, `run-phase.sh --harness-fp-confronta <harness.fp> [<repo>]`, used by
  `run-phase.sh` (exit 6), `cycle-state.sh` and `driver.py next` (`Next: STOP — …`). It prints one line: `UGUALE`
  (equal), `CAMBIATO <reg> <att>` (changed), `FORMATO-PRECEDENTE <reg> <att>` (previous format: a single line of 64
  hex digits, cycle started with the internal harness), `ILLEGGIBILE <att>` (unreadable: empty, truncated, no
  fingerprint) or `NON-CALCOLABILE` (cannot be computed). Only `UGUALE` lets the cycle go on; `versione=` and
  `radice=` do not count (the same plugin from another folder gives `UGUALE`).
- **Diagnostics:** `run-phase.sh --harness-paths` lists the files that go into the fingerprint.

**Confirming an intended change.** The STOP message prints the remedy with an absolute path; run from the project
folder, it rewrites the file in the new format:

```bash
bash "<MAAT_ROOT>/scripts/run-phase.sh" --harness-fp > "<run-dir>/harness.fp"
```

Outside a repository the command exits with 1 and leaves the file **empty**: the cycle stays stopped (`ILLEGGIBILE`).

## The expected outputs (`tools/esempi-equiv/attese/`)

Since 1.6.0 the proof of the driver is a set of **expected outputs** on the public examples, in place of the
equivalence certificate of 1.5.x (`driver.equiv`, `driver.py equiv` and `certificato`, `tools/certifica.sh`: gone).
For every spec of `casi.tsv` the whole output of `cycle-state.sh` (stdout and exit), and for every counted jsonl the
whole output of `driver.py valida` (stdout, stderr, exit and the sha256 of the `result.json` it writes, or
`nessuno`), in six files:

| file | what |
|---|---|
| `next-it.txt`, `next-en.txt` | `cycle-state.sh <spec>` in `it` and `en`: blocks `== <mini-repo>/<spec>`, the stdout without CR, `== exit <n>` |
| `valida-minimo-it.txt`, `valida-minimo-en.txt`, `valida-jsonschema-it.txt`, `valida-jsonschema-en.txt` | `driver.py valida` with each validator and language: blocks `== <mini-repo>/<jsonl>`, `-- stdout`, `-- stderr`, `-- exit <n> · result.json <sha256 or nessuno>` |
| `STORIA` | one line per writing: date, base commit, plugin used, engines, fingerprint of the corpus, reason, files changed |

**The tool**, from the repo root:

```bash
bash tools/esempi-equiv/attese.sh                                # build the corpus, compute, compare (exit 1 with the diff)
bash tools/esempi-equiv/attese.sh --scrivi --motivo "<reason>"   # rewrite them, one line more in attese/STORIA
bash tools/esempi-equiv/attese.sh --validatori                   # which validators are available
bash tools/esempi-equiv/attese.sh --storia [<base>]              # attese/ changed since <base> only with a new STORIA line
```

The comparison also takes restrictions, for the counterproofs and for slow platforms: `--corpus <folder>` (a corpus
already built), `--repo <mini-repo>`, `--solo next|valida`, `--lingua it|en`, `--attese <folder>`, `--esiti <folder>`.
The corpus is always built with the plugin of the repo (the placeholders do not depend on the engine); the outputs are
computed with the plugin of `MAAT_ATTESE_PLUGIN` (a folder or a git ref of this repo; default: the plugin of the repo).
About 1.5 minutes on Linux. Never run it together with a suite of the plugin.

**Normalizations — the closed list** (the same in the header of `attese.sh`):

- `<REPO>` = the root of the mini-repo of the block, in every form: as given, `pwd -P` (a symbolic link: on macOS
  `/var` → `/private/var`), and where `cygpath` exists (Windows) `cygpath -m` (`C:/…`) and `cygpath -u` of that
  (`/c/…`, or `/tmp/…` under the Temp folder of Git Bash), of both;
- `<MAAT>` = the root of the plugin under test, in the same forms;
- `<impronta-attuale>` = the current harness fingerprint of the plugin under test on that mini-repo in that language,
  its 64 digits and its first 12.

Paths are replaced only at the boundary of a path and fingerprints only at the boundary of hex digits, the longest
form first, forms of equal length all kept, in one pass (`tools/esempi-equiv/attese.py`). A path of another mini-repo
is not normalized (so it stays red). **Rule:** a new normalization enters only written in this list and in the header
of `attese.sh`, with a counterproof in `tools/esempi-equiv.test.sh` (h): a real difference in the same line (one
character of the reason changed) stays red.

**The chain of the proof (why nothing is lost from 1.5.1).** (i) The certificate of 1.5.1 was VALIDO: on these
examples, in both languages and with both validators, the driver of 1.5.1 gave the same bytes as the bash table and
the internal validator. (ii) The expected outputs were written **once with the plugin of `v1.5.1`**
(`MAAT_ATTESE_PLUGIN=v1.5.1 … --scrivi`, the first line of `STORIA`) and checked **directly** against its bash engine:
`next` with `FIC_DRIVER=0` (the bash table) and `valida` with `MAAT_ATTESE_VALIDA=run-phase` (`run-phase.sh --valida`
of 1.5.1, the internal validator), both validators, `it` and `en`: no difference. The driver of 1.6.0 gives them with
no difference too. (iii) At every push the CI compares the driver with them, on every row of `righe.list` and every
branch of `rami-valida.list` (on Linux, macOS and Windows). **The lines rewritten since do not come from the
bash table any more**: `STORIA` lists them, with the reason.

**When and how to rewrite them.** Only when an output changes on purpose (a new row of the table, a new message, a
new case of the examples): `bash tools/esempi-equiv/attese.sh --scrivi --motivo "<what changes and why>"` from Linux,
then commit the six files and `STORIA` in the same pull request as the change; the review reads the diff of the
expected outputs. `--scrivi` refuses (exit 2): without `--motivo`, with a restriction, without both validators, or
with a `jsonschema` of a version other than the one of `.github/workflows/ci.yml` (today `4.23.0`). The validators:

- `jsonschema`: `MAAT_PY_JSONSCHEMA=<python with jsonschema==4.23.0>`, otherwise `~/maat-venv/bin/python`, otherwise
  the interpreter of `python.sh` if it imports `jsonschema`;
- minimal: an interpreter **without** `jsonschema`, `MAAT_PY_MINIMO=<python>`, otherwise the Python that
  `scripts/python.sh` finds, if it does not import `jsonschema`. In WSL the system `python3` may well have it (an
  older version, from the distribution's packages): then it cannot be the minimal one, nor the CI's `jsonschema`;
- preparing them is an installation, done once and by hand (Maat never installs anything by itself):

  ```bash
  python3 -m venv ~/maat-venv && ~/maat-venv/bin/pip install jsonschema==4.23.0   # validator jsonschema
  python3 -m venv ~/maat-venv-minimo                                              # validator minimo: no packages
  MAAT_PY_MINIMO=~/maat-venv-minimo/bin/python bash tools/esempi-equiv/attese.sh --scrivi --motivo "…"
  ```

A change of `driver.py`, of the catalog or of the wrappers that does not change an output needs no rewrite.

**On Windows** the expected outputs are the same as on Linux once normalized (measured while preparing 1.6.0, on
two mini-repos in Git Bash, forms `-m` and `-u`, minimal validator: no difference). The Windows CI compares the
whole corpus with them at every push, both validators, in about 18 minutes (`tools/esempi-equiv.test.sh`, group 2 of
`tools/suite-gruppi-windows.list`).

**Going back to the bash engine** is no longer a switch: it is reinstalling Maat 1.5.1 (README, «Going back to
1.5.1»). `rollback.test.sh`, which proved the switch in the middle of a cycle in 1.5.1, went with it.

### The public examples (`tools/esempi-equiv/`)

Seven small git repositories, built from models, with 65 specs and 49 counted jsonl: Italian (1.2.x) and English
(1.3+) formats, single cycles and chains (closed, open, with code or tree changed after the closing).

- **What they cover**, as two closed lists: `righe.list`, every row of the resume table of `cycle-state.sh` (and of
  the chains and of the `result.json` rules), one label per distinct outcome; `rami-valida.list`, every branch of the
  outcome validator and every phase. The manifest `casi.tsv` gives each spec the expected first word of `Next` and the
  row that decides it, and each jsonl the branches it goes through.
- **The builder**, `bash tools/esempi-equiv/costruisci.sh <empty folder>`, creates the repositories, copies the
  models and fills a closed list of computed placeholders (commit and tree sha, Approved basis, snapshots,
  `Finalize`, `state=`) with the same plugin scripts that compute them in a real cycle. It is deterministic: no git
  configuration of the machine, fixed identity, dates, permissions and line endings. Two builds give the same
  fingerprint, on Windows and on Linux. Last it prints `impronta <64 hex>`.
- **The test**, `bash tools/esempi-equiv.test.sh`: two builds with the same fingerprint; every label of the two lists
  has a case, every spec and jsonl built is in `casi.tsv` and vice versa, no counted jsonl is empty; every branch of
  `rami-valida.list` gone through by its jsonl (`driver.py valida`); then `attese.sh` on the built corpus with each
  validator available: every file `UGUALE`, and the word of `Next` of every spec equal to `casi.tsv` in both
  languages; `STORIA` starts with the writing from `v1.5.1`. With `MAAT_ATTESE_RICHIESTE=1` the strict checks of «CI».
  Counterproofs: mutated copies of `driver.py` (red against the expected outputs), an expected output changed (red on
  that block only), every normalization against a real difference in the same line, a validator `SALTATO`, `attese/`
  changed without `STORIA`.
- **Adding a case:** the spec and its run dir go under `tools/esempi-equiv/<mini-repo>/modelli/.ai-workflow/` (code
  states under `stati/<n>/`), one line in `casi.tsv` for the spec and one for each jsonl; a new row of the table also
  gets a label in `righe.list`, a new validator branch one in `rami-valida.list`. Use only generic names (the
  genericity test checks the folder). A new case changes the outputs: rewrite the expected outputs
  (`attese.sh --scrivi --motivo "new case …"`), or the comparison is red.

### Variables of the tests of the repo

| variable or option | where | what it does |
|---|---|---|
| `MAAT_PY_JSONSCHEMA` | `esempi-equiv.test.sh`, `attese.sh` | the interpreter with `jsonschema` (second validator); without it: `SALTATO: jsonschema` (`attese.sh` also looks for `~/maat-venv`) |
| `MAAT_PY_MINIMO` | `esempi-equiv.test.sh`, `attese.sh` | an interpreter without `jsonschema` (first validator), when the one of `python.sh` has it |
| `MAAT_ATTESE_RICHIESTE=1` | `esempi-equiv.test.sh`, `attese.sh` | the strict checks of the expected outputs: no validator `SALTATO`, `attese/` changed only with a new line in `STORIA` (see «CI») |
| `MAAT_ATTESE_PLUGIN` | `attese.sh` | the plugin whose outputs are computed: a folder or a git ref (default: the plugin of the repo) |
| `MAAT_ATTESE_VALIDA=run-phase` | `attese.sh` | `valida` through `run-phase.sh --valida` of the plugin under test (its internal validator: only up to 1.5.1, the anchor of the proof; with a plugin of 1.6.0 exit 2) |
| `MAAT_ESEMPI_DETERMINISMO=completo\|ridotto` | `esempi-equiv.test.sh` | the second build of the determinism case: the whole corpus (`completo`, default on Linux) or one mini-repo (`ridotto`, default elsewhere: a whole build costs about 15 minutes on Windows) |
| `MAAT_ORACOLO_TEST=completo\|ridotto` | `oracolo.test.sh` | the case with both sides from a git ref, on the whole corpus or on two small mini-repos (same defaults) |
| `MAAT_ORACOLO_REPO` | `oracolo.sh` | the repository the git refs are read from (default: this one) |
| `oracolo.sh --esiti <folder>` | `oracolo.sh` | keeps the records of each side and language (`<folder>/<side>-<language>/<project>/<spec>.txt`) |
| `oracolo.sh --motore bash\|predefinito` | `oracolo.sh` | the engine of `cycle-state.sh` of the OLD side: `FIC_DRIVER=0` (default) or unset; the new side always decides with its default engine |
| `--rigenera` with `MAAT_RIF_REPO` | `comandi-equivalenza.test.sh` | rewrites the frozen reference from the private history (see «The commands of the gates») |
| `suite.sh --gruppo <k>/<n>` | `tools/suite.sh` | group k of `tools/suite-gruppi.list` only (CI, parallel run) |
| `MAAT_SUITE_TIMEOUT` | `tools/suite.sh` | the limit of each suite in seconds (default 5400; the CI: 1200 on Linux and macOS, 1800 on Windows); over it `rc=124` and a `TIMEOUT` line; not a positive integer → exit 2 |
| `MAAT_LINUX_CLONI`, `MAAT_PARALLELO_FORZA=1`, `MAAT_PARALLELO_LOCK` | `suite-parallelo.sh`, `giro-completo.sh --linux-parallelo` | the clones, one per group; skip the check of the processes; the lock file |
| `--linux-parallelo`, `--windows-breve` | `giro-completo.sh` | the Linux part in parallel; the short proof on Windows (`tools/prova-breve-windows.list`) |

### The old-against-new oracle (`tools/oracolo.sh`)

A check of each release, separate from the expected outputs: two versions of the plugin on the same projects, the
output of the resume table compared.

```bash
bash tools/oracolo.sh [--esiti <folder>] [--motore bash|predefinito] <old> <new> <project>…
```

- `<old>`, `<new>`: a plugin folder or a git ref of this repository (for example `v1.4.0` and `HEAD`).
  `<project>`: a project root with `.claude/.ai-workflow/`, for example a mini-repo of the examples built.
- The projects are never written: each side works on a fresh copy, and the two sides run in turn **in the same
  paths**, so the plugin root and the paths that appear in the output are the same by construction. For each side and
  language the valid `harness.fp` files are rewritten for that side (except the fixtures listed in
  `.claude/oracolo-conserva`), keeping their mtime.
- Compared, for every spec: in `it` the whole output of `cycle-state.sh`, `plan-check.sh basis` and `contract`; in
  `en` the `State`, the last code phase, the first word of `Next`, `basis` and `contract`. Last line `oracolo: spec=N ·
  it uguali=… · en uguali=… · diverse=…`, the diffs below. Exit 0 identical, 1 a difference, 2 usage.
- `--motore` (1.5.1; since 1.6.0 for the **old side** only) chooses the engine of `cycle-state.sh` of the old side.
  `bash` (the default) sets `FIC_DRIVER=0`: the bash table of a side that has one (up to 1.5.1), so `--motore bash
  v1.5.1 HEAD` is the last proof bash table against the driver of 1.6.0. `predefinito` unsets `FIC_DRIVER`: the old
  side decides as its users get it. The new side always decides with its default engine: since 1.6.0 there is no other
  one. At each release both are run against the previous tag. At the top, one line per side, `oracolo: lato <side> ·
  motore <m>`, followed by `· certificato <verdict>` for a side whose `driver.py` still has `certificato` (up to
  1.5.1): informative, it never changes the exit code.
- `tools/oracolo.test.sh` runs it on the examples (same plugin on both sides: identical) with mutations that must be
  red; two of them (1.6.0) take both sides from the tag `v1.5.1`, so that they do not depend on `HEAD`, and check that
  `--motore` changes the engine of the old side and not of the new one (SALTATO when git cannot read the repo, red
  when the tag is missing). About 6 minutes on Linux, about 70 in Git Bash: the full run sends it to WSL.

### Optional: the private corpus

Until 1.4.0 the reference proof was made on the real run dirs of a private project. It is no longer required. It is
still worth doing when a release changes the **logic** of `next`: real data (agent prose, rare jsonl events, real
lengths) can show a difference that nobody thought to model in the examples. Since 1.6.0 it is the oracle against the
previous tag, on a **copy** of the project (the oracle never writes the projects it is given, but a copy keeps the
real one completely out):

1. **The copy:** a clone of the project branch in a temporary folder, with `git -c core.longpaths=true clone …`
   (on Windows the run dir paths exceed 260 characters), plus the specs and run dirs of **closed** cycles
   (`.claude/.ai-workflow/spec-*.md` and `*.run/`), copied from the project.
2. **Before:** snapshot (list and sha256) of the specs and run dirs of the real project.
3. **The proof:** `bash tools/oracolo.sh --motore bash <previous tag> HEAD <copy>` and the same with `--motore
   predefinito`, from the root of this repo. Required outcome `diverse=0`; a difference is a STOP with the diff, it is
   not fixed by hand.
4. **After:** the same snapshot of the real project, identical to the one taken before.

The outcome validator is not compared there (the oracle reads `next`, `basis` and `contract`): its branches are in the
expected outputs of the public examples.
