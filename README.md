<p align="center">
  <img src="plugins/maat/assets/maat-logo-orizzontale-chiaro.svg" alt="Maat — Multi-Agent Assurance Toolkit" width="360">
</p>

# Maat — Multi-Agent Assurance Toolkit

[![CI](https://github.com/Diegoiorio/maat/actions/workflows/ci.yml/badge.svg)](https://github.com/Diegoiorio/maat/actions/workflows/ci.yml)

**Verified AI development for Claude Code.**

**Maat is a Claude Code plugin that makes agents work like a good team.** You describe the change you want. Maat
carries it all the way to written and reviewed code, and stops when it needs a decision from you.

## What it does

You give it a **spec**, a text file that describes the change. With a single command Maat runs five stages, in
order:

1. **Plan.** One agent writes the plan, another one critiques it. This repeats until the plan is approved.
2. **Code.** An agent writes the code following the plan and runs the project's tests.
3. **Review.** A different agent compares the code with the plan and the spec.
4. **Fixes.** If the review finds serious problems, the code is fixed and reviewed again.
5. **Sign-off.** The final outcome: everything done, or what is left to verify.

Each stage runs in a separate Claude session: no agent judges its own work.

While it works, Maat:

- **blocks dangerous commands**: production, push and git commands that change state, installations;
- **never commits**: the code stays modified in the folder, and you make the commit after looking at it;
- **resumes where it left off**: if it is interrupted, you run the same command again.

- Author: [Diego Iorio](https://github.com/Diegoiorio). [MIT](LICENSE) license: free to use, modify and
  redistribute.
- Full guide to the flows, with diagrams: [`docs/GUIDA-FLUSSI.html`](docs/GUIDA-FLUSSI.html) (open it in a browser).
- What's new in each version: [`CHANGELOG.md`](CHANGELOG.md). Current version: **1.4.0**.

## When to use Maat

Maat fits when:

- the change can be described in a spec, with requirements you can verify;
- the project has tests, or at least checks that can be run;
- you want a second agent to check the work, and a written record of what was verified and what was not.

Maat is not the right tool for:

- one-line fixes: a single Claude Code session is faster;
- exploratory prototypes, or requirements you are still discovering: there is no spec to verify against yet;
- projects without tests: Maat still works, but the best outcome is `NEEDS_VERIFICATION`, because nothing can be
  run to prove the change.

A cycle starts several Claude Code sessions and takes from minutes to hours. At the end, Maat prints its cost and
duration, phase by phase.

## Before you start

| You need | Version | How to check |
|---|---|---|
| Claude Code | 2.1.285 or newer | `claude --version` |
| git | 2.35 or newer | `git --version` |
| bash (on Windows: Git Bash, included in Git for Windows) | 4 or newer | `bash --version` |
| Python | 3.10 or newer | `python --version` (on Windows: `py -3 --version`) |

On Windows **WSL is not required**: it only speeds up JavaScript tests.

## Installation

Maat is installed **once for each project** you want to use it in.

**1. Install the plugin.** Open a terminal in the **main folder of the project**, that is the root of the git repo,
and run these two commands, copying them exactly as they are:

```bash
claude plugin marketplace add https://github.com/Diegoiorio/maat.git#v1.4.0 --scope project
claude plugin install maat@maat --scope project
```

- The first command tells Claude Code **where to get Maat from**: the GitHub repo, at version `v1.4.0` (the part
  after `#`). This address is the "source".
- The second one installs the `maat` plugin from that source.
- `--scope project` saves the choice in the project's `.claude/settings.json` file. If you commit that file, whoever
  clones the project finds Maat already configured.

You can also give the same commands inside Claude Code: type `/plugin` instead of `claude plugin`.

**2. Restart Claude Code** in the project folder, or type `/reload-plugins`.

**3. Configure the project.** Inside Claude Code type:

```text
/maat:setup
```

The setup:

1. looks at the project **without changing anything** and recognizes languages, tests and lint;
2. shows you, in a table, the modules and commands it will use: you confirm or correct them;
3. asks you only what it cannot guess, that is:
   - the production address;
   - the release script;
   - how you access the servers;
   - the files that must never be touched;
4. writes `.claude/maat.json` **only after you confirm**, tests the guard and runs a final check.

**4. Add to `.gitignore`** Maat's working folder, where specs, plans and cycle logs go:

```text
.claude/.ai-workflow/
```

**Check, whenever you want.** From the project folder:

```bash
bash ~/.claude/plugins/cache/maat/maat/1.4.0/scripts/maat-doctor.sh
```

The check changes nothing and prints one line per verification:

- `OK`: all good;
- `WARNING`: it works, but there is something you should know;
- `MISSING`: needs fixing, and the line says how.

With `"lingua": "it"` (see «Language») the same lines say `OK`, `ATTENZIONE` and `MANCA`.

## Usage

### 1. Write the spec

The spec is a Markdown file in the `.claude/.ai-workflow/` folder, with a name like `spec-<name>.md`, for example
`spec-export-csv.md`. It describes **what** you want, not how to do it:

```markdown
# Spec: export customers to CSV

## Context
Why it is needed and how it works today (useful files and lines, if you know them).

## Functional requirements
FR1. What it must do, point by point, in a way that can be verified.

## Out of scope
What must not be touched.

## Acceptance criteria
AC1. How you can tell it is done, for example which tests must pass.
```

Maat reads two of these headings: `Functional requirements` and `Acceptance criteria`, whose ids (`FR1`, `AC1`…)
the plan must cover. Specs written for earlier versions, with Italian headings (`Requisiti funzionali`, `Criteri di
accettazione`, ids `RF1`, `CA1`), keep working: Maat reads both languages.

Don't know where to start? Ask Claude: "use the `maat:spec-author` agent to write the spec for: …", and describe
the change. The agent reads the code, asks you questions if something is unclear and writes the file.

### 2. Run the cycle

```text
/maat:full-implementation-cycle .claude/.ai-workflow/spec-export-csv.md
```

In the chat you only see the progress lines. Depending on the change, the cycle takes from a few minutes to a few
hours.

### 3. Read the outcome

| Outcome | What it means | What you do |
|---|---|---|
| `IMPLEMENTED` | Code written, reviewed and verified. | Look at the changes and commit. |
| `NEEDS_VERIFICATION` | The review is approved, but a required check was not run, for example because the module has no tests. The message says which one. | Run that check yourself, then commit. |
| `STOP` | Maat stopped because a person is needed. The message says why and what to decide. | Decide, then run the same command again: it resumes from there. |

### Useful options

- `--worktree`: the cycle works in a separate copy of the repo, on its own branch, so you can keep working in the
  main folder. Run it from the main folder of the repo.
- `--tests=min|std|full`: how many tests to run, from a few to all of them.
- `--light`: the plan is reviewed by a single reviewer. Fine for small changes.
- **Large specs:** they are split into smaller specs, which Maat runs in order. `maat:spec-author` prepares them.
- **Without the full cycle:** `/maat:plan-review-cycle <spec>` only makes the plan; then
  `/maat:implementation-review-cycle <name>` reviews the code you wrote yourself.

## Configuration

Everything about your project lives in `.claude/maat.json`, written by `/maat:setup`. Usually you don't need to
edit it by hand. If you want to:

- ready-made profiles for common stacks: `plugins/maat/profiles/`;
- complete examples: `plugins/maat/examples/`;
- all the keys: `plugins/maat/schemas/maat-config.schema.json`.

## Language

English is the default language. It covers what Maat prints for a person: the explanation shown under each
permission request, the guard's reasons, the progress lines of a cycle and, since 1.4.0, the messages of the scripts
(the text after `STOP — `, errors and remedies, the reports of `maat-doctor`, `cycle-report` and `phase-usage`).
For Italian, add `"lingua": "it"` to `.claude/maat.json`: the output is then the same as in 1.3.0. A project with
no `lingua` gets English: since 1.4.0 this changes the output of projects that never set it.

The environment variable `MAAT_LINGUA` (`it` or `en`) wins over `.claude/maat.json`, for one command or one test run:
`MAAT_LINGUA=it bash <MAAT_ROOT>/scripts/maat-doctor.sh`. The order is `MAAT_LINGUA`, then `lingua` of
`.claude/maat.json`, then English.

Some words stay Italian in every language, because scripts, skills and tests read them: `VIOLAZIONE`, `AVVISO`,
`ERRORE DURO`, `Percorso:`, `Scheletro:`, `S2:`, and the lines the scripts pass to each other (the full list is
`plugins/maat/scripts/lib/protocol-strings.list`). The explanation after them follows the language.

The language is part of the harness fingerprint: changing `lingua` (or running with a different `MAAT_LINGUA`)
while a cycle is in progress stops it with «harness changed», as an update does (see «Updating to a new version»).

Since 1.3.0 the formats Maat reads are written in English: spec and plan headings, the outcome line of each phase
(`PHASE RESULT <phase>: OK`), the report lines of the agents. The Italian forms of earlier versions are still read,
so existing specs, approved plans and cycles keep working; don't translate an approved plan, or its approval expires.

## Updating to a new version

Maat never updates itself: it stays at the version written in the source. To move to a new version, for example
`v1.4.0`, from the project folder:

```bash
claude plugin marketplace add https://github.com/Diegoiorio/maat.git#v1.4.0 --scope project
claude plugin update maat@maat --scope project
```

Then restart Claude Code and run the check: the version line must say OK. Don't update while a cycle is running. If
you do, the cycle notices, stops and asks you to confirm.

From 1.3.x to 1.4.0 the messages of the scripts become English; to keep them Italian, add `"lingua": "it"` to
`.claude/maat.json` (see «Language»).

## Uninstalling

From the project folder:

```bash
claude plugin uninstall maat@maat --scope project
claude plugin marketplace remove maat --scope project
```

Two empty keys remain in `.claude/settings.json` (`enabledPlugins` and `extraKnownMarketplaces`): they are harmless.
`.claude/maat.json` and the `.claude/.ai-workflow/` folder also remain: if you no longer need them, delete them
yourself.

## Platforms

| Platform | Status |
|---|---|
| Windows with WSL | verified with all tests |
| Windows without WSL | the fallbacks without WSL verified: tests, checks and diagnostics |
| Linux | verified with all tests, on a Linux with no Windows tools |
| Mac | planned, not yet tried |

Paths with spaces and accented letters work. One limit only: in plans, project file names must not contain
spaces.

## What is proven and what is not

Proven, and where to check it:

- **The automated suites pass** on Linux at every push ([CI](https://github.com/Diegoiorio/maat/actions/workflows/ci.yml));
  they also run on Windows before each release (`docs/TESTING-harness.md`).
- **The guard blocks dangerous commands**: behaviour tests on production, push, state-changing git, installations and
  remote access (`plugins/maat/scripts/guard.test.sh`, `plugins/maat/tests/guard-esempio.cases`).
- **The Python driver behaves like the original bash code** on 15 real, closed cycles of a private project
  (`plugins/maat/scripts/driver.equiv`, line `corpus`; the cycles themselves are not public).

One example, not a measurement: on a second private project, which has no tests, a pilot cycle of an early version
(0.3.0) went from the spec to `NEEDS_VERIFICATION` with no human step during the cycle: plan and review approved at the
first round, 22 minutes, $5.23 API-equivalent cost. A first attempt with `--worktree` had stopped on a defect, fixed
since; the cycle that completed ran without it. It cannot be reproduced from this repo.

Not proven yet:

- that Maat produces better code than Claude Code alone: the benchmark has not been run; its protocol is fixed in
  advance in [`docs/BENCHMARK-PROTOCOL.md`](docs/BENCHMARK-PROTOCOL.md);
- that Maat finds, on its own, defects nobody had described: in the pilot above the defect the cycle fixed was
  already described in the spec;
- how often a cycle completes without help, across different projects;
- Mac, and very large projects.

## Developing Maat

This part is only for people who modify Maat:

- changes are made with **flow H** (`.claude/skills/flusso-h/SKILL.md`), running `claude` from this repo's
  folder;
- firm rule: **the Maat you are modifying is tested, not used for development**. To try it by hand:
  `claude --plugin-dir <repo folder>/plugins/maat`;
- the tests are described in [`docs/TESTING-harness.md`](docs/TESTING-harness.md).

Reports and proposals: open an issue on GitHub.

## Disclaimer

Maat runs artificial intelligence agents that read and modify your project's code and run commands on your
machine. The guard reduces the risks, but does not eliminate them.

- **You use it at your own risk.** Always check the changes before committing, and don't run it on projects or
  machines where a mistake cannot be undone.
- Maat is provided **"as is", without warranties of any kind**. The author is not liable for damages, data loss or
  other consequences of its use: see the [license](LICENSE).
- The cost of the Claude Code sessions that Maat starts is borne by whoever uses it.
- Maat is an independent project, not affiliated with Anthropic. Claude and Claude Code are trademarks of Anthropic.

## License

[MIT](LICENSE) © 2026 Diego Iorio.
