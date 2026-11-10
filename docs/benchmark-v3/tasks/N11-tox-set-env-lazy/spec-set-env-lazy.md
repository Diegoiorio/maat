# Spec: `set_env` values must see the keys of the environment they end up in

## Problem

`set_env` values may refer to each other: `DATA = {env:BASE}/data` reads the `BASE` key of the same `set_env`, and falls
back to the host variable only when no key has that name. This works for lines written directly in an environment. It
does not work when the lines come from somewhere else:

```ini
[base]
set_env =
    BASE = /opt/app
    DATA = {env:BASE}/data

[testenv:integration]
set_env =
    {[base]set_env}
    EXTRA = 1
```

```toml
[env_run_base]
set_env = { BASE = "/opt/app", DATA = { replace = "env", name = "BASE" } }
```

In both, with `BASE=/host` on the host, `DATA` is computed from the host variable (or from nothing) instead of from the
`BASE` key that the environment sets. The same section gives different values depending on who includes it.

Related defects of the same area, to be fixed by this change:

- Precedence between included sections depends on nesting: a section included by another section can override the section
  that included it.
- `tox config` may not show keys that `tox run` sets, when they come from nested includes.
- Cycles fail badly: a section that includes itself, or values that refer to each other inside an included section, end with
  a traceback, with "could not find python interpreter", or silently with host values.

## Goal

A line included from another section, or a `{ replace = "env" }` table, behaves as if the line had been written directly
in the `set_env` of the environment that uses it. In INI an include is `{[section]set_env}`; in TOML it is
`{ replace = "ref", of = [...] }`. The rules below hold for both formats, for `tox run` and for `tox config`, and for
everything that reads the variable (`commands = echo {env:DATA}` included).

## Functional requirements

Below, "the keys of the environment" means every key its `set_env` ends up with, wherever it comes from: a line written in
place, an included section at any depth, an entry of an environment file (`file|name` in INI, `file = "name"` in TOML), a
TOML list entry.

FR1. **`{env:KEY}` in an included value.** It reads the keys of the environment, then the host variable, then the default,
then the empty string. Edge cases that must work:
- `KEY` is written after the line that refers to it, or in another included section, earlier or later;
- `KEY` is written in the including section, and then that value is the one used by the included line (with `BASE = /own`
  and `{[base]set_env}` in one environment, `BASE` is `/own` and `DATA` is `/own/data`);
- `KEY` comes from a section nested deeper, or from the section that includes the one holding the reference;
- a line of an environment file included through a section refers to a key of the block, and a line of the block refers to
  a key of an environment file;
- the reference sits in the default of another substitution: `V = {env:MISSING:{env:BASE}/d}`, `V = {posargs:{env:BASE}}`;
- chains: `C = {env:B}/c`, `B = {env:A}/b`, `A = /a` give `C = /a/b/c` whatever the host holds.

FR2. **TOML `{ replace = "env", name = "NAME", default = "..." }` inside `set_env`.** It resolves with the lookup order of
FR1 and the self-reference rule of FR3. Its `default` is literal text, apart from the substitutions it holds:
`default = "http://x:80/a"` gives `http://x:80/a`, `default = "a}b{c"` gives `a}b{c`. Edge cases that must work:
- `NAME` is a key next to the table, before or after it, and also when the table reaches the environment through a
  `{ replace = "ref" }`;
- the `default` holds a substitution (`default = "{env:BASE}/d"`);
- no `default` and no value anywhere gives the empty string;
- a `marker` on the table still decides whether the key exists.

Outside `set_env` the table keeps its current behaviour.

FR3. **A value that refers to its own key reads the host.** `TOOLS = {env:TOOLS}:/extra` with `TOOLS=/usr/x` on the host
gives `/usr/x:/extra`, written in place or included. Edge cases that must work:
- an included line with its default: `SEED = {env:SEED:0}` gives the host value, or `0` with no host value. This holds for
  keys tox sets on its own too: an included `PYTHONHASHSEED = {env:PYTHONHASHSEED:0}` gives `0` with no host value, not the
  value tox would have chosen;
- another key reads the result, not the host: with `TOOLS = {env:TOOLS}:/extra` and `OTHER = {env:TOOLS}`, `OTHER` is
  `/usr/x:/extra`;
- a TOML table that names its own key: `FOO = { replace = "env", name = "FOO", default = "d" }` gives the host value or `d`.

FR4. **Precedence.** When two lines set the same key:
- a key written directly in a `set_env` wins over the same key from a section it includes, before or after the include line;
- a later include wins over an earlier one, whatever the depth at which each of them holds the key (`{[a]set_env}` then
  `{[b]set_env}`: a key that `b` gets from a nested section still wins over the same key written in `a`);
- the rule applies again inside every included section, so a nested section never overrides the section that includes it;
- the marker of a line goes with its value: only the winning line's marker counts;
- in the TOML list form, the later entry wins, as today.

FR5. **Visibility and environment.** `tox config -e <env> -k set_env` shows every key `tox run` sets, at any depth of nesting,
with the same values. A section included twice, directly or through two paths (a diamond), is not an error. Included values
resolve in the environment that includes them: `{env_name}` gives that environment's name, and two environments including
one section can get different values. The section's own environment and an environment that only includes it get the same
values.

FR6. **Cycles fail the environment.** The following are errors of the configuration:
- a section that includes itself, directly or through other sections;
- a TOML `{ replace = "ref" }` that leads back to itself, directly or through another `ref`;
- values that refer to each other (`A = {env:B}`, `B = {env:A}`), written in place, included, or as TOML strings or tables,
  with two keys or more, are errors, also when the host has variables of those names.

On `tox run` the environment fails with a non-zero exit code before running its commands. The output has no traceback and
does not say "could not find python interpreter". It contains the word `circular`, and it names every element of the cycle:
the keys for values, the section names for includes, the `of` path for a TOML `ref`. The rest of the wording is free.

FR7. **Compatibility: what must not change.** This, with the self-reference of FR3, is the trap of the change: the
substitution rules are shared with every other key and many configurations rely on them:
- lines written in place keep their results, including what FR1 and FR3 say about them;
- other keys keep substituting as before, including a chain of references (`description = {[base]outer}`, where `outer` holds
  `{[base]inner}`, where `inner` holds `{env:HOST_VAR:fallback}`), and a TOML `{ replace = "env" }` outside `set_env`;
- two keys that read the same host variable are not a cycle;
- inside an included value: `{[section]key}` references to other keys, `\#` for a literal `#`, `\{` and `\}` for literal
  braces, `; <marker>`;
- a line whose key is a substitution keeps working, in place or included: `{env:KNAME} = 1` with `KNAME=FOO` sets `FOO`;
- a key with a brace that opens no substitution stays literal: `{unknown} = {env:MISSING:value}` sets a key named
  `{unknown}` to `value`;
- an include of a section that does not exist stays an error that shows the line (`{[missing]set_env}`);
- the project's test suite stays green, except for the failures declared below.

## Acceptance criteria

AC1. With `BASE=/host` on the host, both configurations under «Problem» give `DATA` as `/opt/app/data` and `/opt/app`
respectively, in `tox config` and in the process run by `tox run`.

AC2. Each example of FR1 to FR7 gives the stated result.

AC3. The test suite passes, apart from the declared failures: from the project's root,
`PATH="$PWD/.venv/bin:$PATH" .venv/bin/python -m pytest -n 8 -o timeout=300 tests`.

## Declared failure at the starting commit

One test of the suite fails at the starting commit in the prepared environment, for a reason that has nothing to do with this
change: it is not to be fixed, and it is excluded from every count.

- `tests/tox_env/python/virtual_env/package/test_package_cmd_builder.py::test_run_installpkg_targz`: it installs packages
  from the public package index, and the network is closed.

## Context for a contributor

- The environment is prepared in `.venv`, with the project installed in development mode and the test dependencies pinned;
  the network is closed, so no package can be added. The directory `.venv/bin` must be on the `PATH` when running the suite:
  otherwise seven tests of `tests/session/cmd/test_schema.py` stop with "tombi must be installed", because they look for
  that tool on the `PATH`.
- The tests of the project reject any warning (`filterwarnings = error`). The project's limit of 30 seconds per test is
  tight on a busy machine, which is why the command above raises it.

## Out of scope

- `set_env` given through `-x` or `TOX_OVERRIDE`.
- Host values or substituted text holding line breaks, `;` or `file|`: how they are split into lines stays as it is.
- A line of an included section that as a whole is a substitution expanding to several lines of `set_env` syntax.
- Sections that get `set_env` by inheritance or through generative section names, when included.
- The documentation and the changelog fragment are welcome, not required.

## Constraints

- No new dependency.
- The change comes with tests in the project's suite, as any change to this project does.
- The Python versions supported by the project (`requires-python` in `pyproject.toml`).
