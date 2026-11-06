# Spec: parse a human-readable file size back into a number of bytes

## Context

`humanize.naturalsize()` (in `src/humanize/filesize.py`) turns a number of bytes into text such as `1.5 MB`,
`1.5 MiB` (`binary=True`) or `1.5M` (`gnu=True`). The library has no inverse: a program that reads sizes written by
people or by `naturalsize()` itself (configuration files, command-line options, logs) has to parse them by hand.

The project is a Python library with a pytest suite in `tests/`; `tests/test_filesize.py` covers `naturalsize()`.
The public functions are re-exported from `src/humanize/__init__.py` and listed, sorted, in its `__all__`. The
documentation pages in `docs/` are generated from the docstrings.

## Goal

A new public function, `humanize.parse_naturalsize()`, reads the size formats that `naturalsize()` writes, in
decimal, binary and GNU style, and returns the exact number of bytes as an `int`.

## Functional requirements

FR1. A new function `parse_naturalsize(value: str) -> int` is defined in `src/humanize/filesize.py`, importable as
`humanize.parse_naturalsize` and as `humanize.filesize.parse_naturalsize`, and listed in `humanize.__all__` (which
stays sorted).

FR2. Accepted input: optional leading and trailing whitespace; an optional sign (`+` or `-`); a number; optional
whitespace (spaces or tabs); an optional unit. The number is either digits with an optional fractional part
(`12`, `1.5`, `0.25`) or a fractional part alone (`.5`). Anything else is invalid, in particular: thousands
separators (`1,000 kB`), exponents (`1e3`), a trailing point with no digits (`1.`), more than one number, a unit
with no number, and text after the unit.

FR3. Units, matched **case-insensitively**, and the number of bytes one unit is worth:
- `B`, `Byte`, `Bytes`: 1. A number with no unit also means bytes.
- decimal, two letters: `kB` 1000, `MB` 1000², `GB` 1000³, `TB` 1000⁴, `PB` 1000⁵, `EB` 1000⁶, `ZB` 1000⁷,
  `YB` 1000⁸, `RB` 1000⁹, `QB` 1000¹⁰;
- binary: `KiB` 1024, `MiB` 1024², `GiB` 1024³, `TiB` 1024⁴, `PiB` 1024⁵, `EiB` 1024⁶, `ZiB` 1024⁷,
  `YiB` 1024⁸, `RiB` 1024⁹, `QiB` 1024¹⁰;
- GNU, one letter (as written by `naturalsize(gnu=True)`): `K` 1024, `M` 1024², `G` 1024³, `T` 1024⁴, `P` 1024⁵,
  `E` 1024⁶, `Z` 1024⁷, `Y` 1024⁸, `R` 1024⁹, `Q` 1024¹⁰.

  So `1kb`, `1KB` and `1 kB` are all 1000; `1k` and `1K` are both 1024; `1 kib` is 1024.

FR4. The result is the number multiplied by the value of the unit, computed **exactly** (no binary floating-point
error at any size) and rounded to the nearest integer, with halves rounded away from zero. Examples:
`"1.5 kB"` → 1500, `"1.1 QB"` → 1 100 000 000 000 000 000 000 000 000 000, `"0.5 B"` → 1, `"-0.5 B"` → -1,
`"2.5"` → 3, `"0.0004 kB"` → 0, `"-1.5 KiB"` → -1536. A negative zero result is `0`.

FR5. Errors: a `str` that is not valid according to FR2 and FR3 (the empty string and a whitespace-only string
included) raises `ValueError`, with a message that contains the input as written (its `repr()`). A value that is
not a `str` (for example `None`, `10`, `b"1 kB"`) raises `TypeError`.

FR6. Round trip with `naturalsize()`, for every integer `n` with `abs(n) < 10**33`, with each of the default,
`binary=True` and `gnu=True` styles and the default `format`: `parse_naturalsize(naturalsize(n, ...))` differs from
`n` by at most half of the last digit shown, that is at most `0.05 ×` the value of the unit shown (exactly `n`
when the output is in bytes: `"1 Byte"`, `"300 Bytes"`, `"300B"`). Only the English (untranslated) output of
`naturalsize()` is in scope.

FR7. The function has a docstring in the style of `naturalsize()` (summary, a `pycon` block of examples, `Args`,
`Returns`, `Raises`); the examples in it are correct. The README section that shows `naturalsize()` gains one
example of `parse_naturalsize()`.

FR8. Tests for the new function are added to `tests/test_filesize.py` (or a new test file next to it), covering
FR2 to FR6.

## Codebase areas involved (indicative)

- `src/humanize/filesize.py` — `naturalsize()`, the `suffixes` table.
- `src/humanize/__init__.py` — imports and `__all__`.
- `tests/test_filesize.py`.
- `README.md` — the `naturalsize` examples.

## Acceptance criteria

AC1. `humanize.parse_naturalsize("1.5 MB") == 1500000`, `humanize.parse_naturalsize("1.5 MiB") == 1572864`,
`humanize.parse_naturalsize("1.5M") == 1572864`, and `"parse_naturalsize" in humanize.__all__`.

AC2. Every example in FR3 and FR4 gives the stated result; the result is always of type `int`.

AC3. Each invalid form listed in FR2, the empty string and a whitespace-only string raise `ValueError` whose
message contains the input's `repr()`; `None`, `10` and `b"1 kB"` raise `TypeError`.

AC4. The FR6 round trip holds for a large sample of integers across the whole range, in all three styles.

AC5. The whole existing test suite still passes (`python -m pytest`), and `naturalsize()` returns exactly what it
returned before for every input.

## Assumptions

- Sizes are bytes, never bits: `kb` means kilobytes, like `kB`.
- One-letter units always use base 1024, as `naturalsize(gnu=True)` does; two-letter units always use base 1000.

## Out of scope

- Parsing translated output (other locales) or other separators than `.` for decimals.
- Any change to the behaviour of `naturalsize()` or of other functions.
- New dependencies.

## Constraints

- Python versions supported by the project (`requires-python` in `pyproject.toml`); standard library only.
- Follow the project's style (type hints, docstring format, `ruff` configuration in `pyproject.toml`).
