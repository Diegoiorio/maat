# Spec: a command's short help must not stop at an abbreviation

## Context

When a command has no explicit `short_help`, Click derives one from its help text, for the list of commands shown
by a group's `--help` (`Command.get_short_help_str()` in `src/click/core.py`, which calls
`_make_default_short_help(help, max_length)` in `src/click/utils.py`). The rule today: take the first paragraph,
collapse whitespace, stop at the first word that ends with a period (the end of the first sentence), and truncate
with `...` if the result is longer than `max_length` (45 by default in that call path).

Any word ending with a period is taken as the end of the sentence, so an abbreviation cuts the short help:

```python
@cli.command()
def weigh():
    """Weigh apples vs. pears."""
```

is listed as `weigh  Weigh apples vs.` instead of `weigh  Weigh apples vs. pears.`; the same happens with `e.g.`,
`i.e.`, `etc.` followed by more words.

The tests of the function are in `tests/test_utils/test_make_default_short_help.py`.

## Goal

The first sentence ends at a period only when that period really ends a sentence, and the short help keeps the
rest of its current rules.

## Functional requirements

FR1. In the first paragraph, after whitespace is collapsed, a word that ends with `.` ends the first sentence only
if it is the last word of the paragraph, or the next word does not start with a lowercase character (as defined by
Python's `str.islower()` on that first character). Otherwise the period belongs to an abbreviation and the sentence
goes on. So `"Weigh apples vs. pears."` is one sentence; `"Pick a fruit. 3 remain."` ends after `fruit.`;
`"Read e.g. the docs. Then go."` ends after `docs.`.

FR2. The short help is the first sentence (or the whole first paragraph if no word ends a sentence). If it is not
longer than `max_length`, it is returned as it is.

FR3. Otherwise it is truncated: as many whole leading words as fit, joined by single spaces, immediately followed
by `...`, so that the total length is at most `max_length`. A word is never split, hyphenated words included. If not
even the first word fits with the `...`, the result is `...`.

FR4. Narrow widths: if `max_length` is smaller than 3 (zero and negative values included) and the text does not
fit, the result is `...` (the only case where the result may be longer than `max_length`). A text that fits is
still returned as it is (`"ab"` with `max_length` 2 gives `"ab"`).

FR5. Unchanged: only the first paragraph is considered (text up to the first blank line); a leading `\b` no-rewrap
marker is ignored; empty help gives `""`; a period inside a word (`~/.netrc`) is not a sentence end.

FR6. The existing test case that relies on the old rule (`"123 567 9. aaaa bbb"` with width 10, which today gives
`"123 567 9."`) is updated to the new rule (`"123 567..."`, since `aaaa` is lowercase), and new cases cover FR1 to
FR5. An end-to-end test checks the command list of a group's `--help`.

FR7. `CHANGES.md` gains an entry in the unreleased section at the top describing the change.

## Codebase areas involved (indicative)

- `src/click/utils.py`: `_make_default_short_help`.
- `src/click/core.py`: `Command.get_short_help_str` (caller, unchanged).
- `tests/test_utils/test_make_default_short_help.py`.
- `CHANGES.md`.

## Acceptance criteria

AC1. `_make_default_short_help("Weigh apples vs. pears.", 30) == "Weigh apples vs. pears."` and
`_make_default_short_help("Weigh apples vs. pears and plums.", 20) == "Weigh apples vs...."`.

AC2. Every example of FR1 to FR5 gives the stated result, with and without a leading `\b` marker paragraph.

AC3. The result is never longer than `max(max_length, 3)`.

AC4. A group whose subcommand has the help `"Weigh apples vs. pears."` lists it in `--help` as
`Weigh apples vs. pears.`.

AC5. The whole test suite passes (`python -m pytest`).

## Assumptions

- An abbreviation followed by a capitalised word (`U.S. Army`) is taken as a sentence end: this limit is accepted.

## Out of scope

- The explicit `short_help` argument, the help of options and arguments, the formatting of the help page.
- New dependencies.

## Constraints

- The Python versions supported by the project (`requires-python` in `pyproject.toml`).
- The function stays private (`_make_default_short_help`), with the same signature.
