# Maat benchmark, version 3

**Status: tasks drawn; specs and hidden tests being prepared; not frozen; no run made.**

This folder applies [`../BENCHMARK-PROTOCOL-v3.md`](../BENCHMARK-PROTOCOL-v3.md).
[`QUALIFICATION.md`](QUALIFICATION.md) fixes the criteria, the pools of candidates and the procedure of the draw, and
[`SHA256SUMS`](SHA256SUMS) holds their checksums, so that they cannot change unseen after the qualification commit. No
spec, hidden test or format adapter was written before the draw: they are written only for the drawn tasks (protocol,
§3, item 5, and §8). No Claude session has been run on any candidate.

## The draw

The whole output, with every step, is [`draw.txt`](draw.txt); `python3 draw.py <commit>` gives the same bytes.

- **Qualification commit:** `890c1479f447ba25fe71b1bb389741a9d1bcf500`, public on `main` since **2026-11-09T11:13:37Z**
  (the merge of [pull request #11](https://github.com/Diegoiorio/maat/pull/11), which is also the committer date), about
  one hour before the round below.
- **Seed:** drand «quicknet» round `33807685`, of 2026-11-09T12:13:39Z. The first attempt (`k=0`) met the variety rule.

| Group | Task | Repository | Language, kind |
|---|---|---|---|
| Hard | N3 | labstack/echo | Go, bug fix |
| Hard | N11 | tox-dev/tox | Python, bug fix |
| Hard | N2 | h3js/h3 | TypeScript, compatibility |
| Hard | N12 | alecthomas/kong | Go, new feature |
| Hard | N9 | pyenv/pyenv | shell, new feature |
| Hard | N7 | tafia/quick-xml | Rust, bug fix |
| Easy | E1 | BurntSushi/toml | Go, bug fix |
| Easy | E3 | BurntSushi/jiff | Rust, bug fix |

Four of the six hard tasks (N3, N7, N11, N12) are among those the qualification file marks close to the line: if they
turn out easy they stay, marked «not discriminating». Replacement order, used only if a task fails a check made before
the freeze (C8–C10, D2, D3, D5): hard N5, N1, N6, N4; easy E2.

## What is compared

- **Maat side:** Maat `v1.7.0` (commit `752ff92`), installed and started as in version 2: the
  plugin at project scope, the task's frozen `.claude/maat.json`, the full cycle started by its driver, nobody
  answering.
- **Baseline side:** one Claude Code session in print mode with a fixed prompt, in a copy without Maat (the prompt of
  version 2, with the tools of the new environment named).
- **The same on both sides:** one Claude Code binary, at the version current at the freeze and pinned from then on;
  model **`claude-opus-5-5`**; a configuration folder used only for the benchmark; Linux (Ubuntu 24.04 on WSL2);
  bubblewrap isolation; no web tools; the same prepared environment; one run at a time; the 4-hour cap.
- **Toolchains** (those of the checks below): Python 3.12.3, Go 1.27.3, Node 22.22.2, Rust 1.99.1, GNU `parallel`
  20261022, bats 1.14.0, git 2.43.0, bash 5.2.21; pnpm 11.15.1 only to prepare N2.

## Next

1. For the drawn tasks only: specs, hidden tests, format adapters, the checks C8–C10, D2, D3 and D5, the lists of failures
   already present at the starting commit (protocol, §4a), and the version of Claude Code. A replacement, if any, is
   published here with the check it failed.
2. The freeze commit, with its second seed for the order of the runs; the runs end at the latest 3 months after it.

## Results

None: no run made.
