# Maat benchmark, version 3

**Status: qualified: candidates and draw procedure fixed; tasks not drawn yet; not frozen; no run made.**

This folder applies [`../BENCHMARK-PROTOCOL-v3.md`](../BENCHMARK-PROTOCOL-v3.md).
[`QUALIFICATION.md`](QUALIFICATION.md) fixes the criteria, the pools of candidates and the procedure of the draw, and
[`SHA256SUMS`](SHA256SUMS) holds their checksums, so that they cannot change unseen after the qualification commit. No
spec, hidden test or format adapter exists: they are written only for the tasks that will be drawn (protocol, §3, item 5,
and §8). No Claude session has been run on any candidate.

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

1. The qualification commit is pushed; at least one hour later, `python3 draw.py <its id> > draw.txt` draws the tasks.
2. For the drawn tasks only: specs, hidden tests, format adapters, the checks C8–C10, D2, D3 and D5, the lists of failures
   already present at the starting commit (protocol, §4a), and the version of Claude Code.
3. The freeze commit, with its second seed for the order of the runs; the runs end at the latest 3 months after it.

## Results

None: no run made.
