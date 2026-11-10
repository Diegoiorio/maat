# Spec: `pyenv binary install`, install a published package for this system or stop

## Problem

`pyenv install` builds CPython from source on the user's machine, which is slow and needs a compiler and many
development headers. The experimental `pyenv binary` plugin can already package a build on one machine
(`pyenv binary package`, `save`, `generate-installer`), and the project now publishes some of those packages. There is no
command to consume them: a user has to find the right package by hand, check that it suits the system, and install it.

We want an explicit command, `pyenv binary install <version>`, that picks a published package suited to the current
system and installs it. **It never builds from source**: when no package suits the system, it stops and says so. The
user who wants a source build asks for one with `pyenv install`, which must keep working exactly as it does today.

A second, smaller need comes from publishing: a package is built under a long name such as
`3.14.7-ubuntu-24.04-x86_64`, and its metadata does not say which Python version it holds. The metadata must record that.

## The published catalogue

The catalogue of published packages is kept in the repository and ships with the plugin. The command reads it from the
installed copy each time it runs; it does not fetch a catalogue or keep a cache.

- **Location:** the folder `share/pyenv-binary/versions/` of the plugin, that is `plugins/pyenv-binary/share/pyenv-binary/versions/`
  under the root of pyenv. The plugin may be reached through the pyenv installation or through `PYENV_ROOT`; in the tests
  they are the same folder.
- **Files:** one plain text file per Python series, named `<major>.<minor>` (`3.14`, `3.9`), with the rows of that series only.
  A series may have no file.
- **Rows:** fields separated by one tab, in this order. The first line of each file is this header:

  ```
  source_version	entry	os	arch	distro	sha256
  3.14.7	3.14.7-macos-15-arm64	Darwin	arm64	macos 15.7.9	8a8ff86b520c3b5da00b49e04a5345b7a28f2f9e8da5a9ae43b8ac309e8f3e55
  3.14.7	3.14.7-ubuntu-24.04-x86_64	Linux	x86_64	ubuntu 24.04	e63dbcb981ec9ba83a2bc9b4d8b369620cec4aa45394559d719c5606ee9ff718
  ```

| Field | Meaning | Valid form |
|---|---|---|
| `source_version` | the Python version the package holds | numbers separated by dots, two or three of them: `3.14`, `3.14.7` |
| `entry` | the name of the package at the published address | letters, digits, `.`, `_`, `-` only, and not `.` or `..` |
| `os` | as printed by `uname -s` | `Linux`, `Darwin` |
| `arch` | as printed by `uname -m` | `x86_64`, `arm64`, … |
| `distro` | the system the package was built on | Linux: `<ID> <VERSION_ID>`, as in `ubuntu 24.04`. macOS: `macos <version>`, as in `macos 15.7.9` |
| `sha256` | SHA-256 of the file at the published address | 64 hexadecimal digits, either case |

A line that does not fit (the header, an empty line, too few fields, a `source_version` or an `entry` not in the valid form)
is not a package and is ignored. This matters: the catalogue is data read by a program that writes under `versions/` and
requests addresses.

**The published address** of an entry is `https://pyenv.github.io/pythons/binaries/<entry>`, downloaded with `curl`. What is
there is a python-build definition file, of the kind `pyenv binary generate-installer` writes. The result is the same as
installing that definition with pyenv's installer under the name `<source_version>` of the row: `versions/3.14.7`, not
`versions/3.14.7-ubuntu-24.04-x86_64`. The definition does its own fetching and unpacking.

**How the command sees the system.** It decides only from these, each called by name through `PATH`, because that is how the
tests of this project simulate another system:

- `uname -s` and `uname -m` for the operating system and the architecture; the first decides which of the next two applies;
- on Linux, `ID` and `VERSION_ID` of `/etc/os-release`, or `lsb_release -si` and `-sr` if that file does not exist;
- on macOS (`Darwin`), `sw_vers -productVersion` and nothing else: `/etc/os-release` is not consulted, even if it exists.

## Functional requirements

FR1. **The command.** `pyenv binary install <version>` is a subcommand like the others of `pyenv binary`: `pyenv binary` lists
it, and `pyenv binary install --help` shows its usage, a line with `pyenv binary install <version>`, and exits 0. It takes
exactly one argument. Edge cases: with none, or with more than one, it prints the usage on standard error and exits non-zero,
downloading and installing nothing. `pyenv completions binary install` succeeds (exit 0) and does not offer the versions that
can only be built from source (the output of `pyenv install --list`).

FR2. **Names that cannot be versions.** A `<version>` that contains `/` or a control character, or that is `.` or `..`,
exits non-zero with `pyenv-binary: invalid version name` followed by the name, before anything else happens. Edge cases: any
other string that is not a version, such as `3.*`, an empty string or `*`, matches no package and stops under FR5 (or as an
invalid name: either is correct), and never expands to a package by a shell pattern.

FR3. **Which versions match.** `<version>` is a complete version or a prefix of whole components: `3.14.7` matches only
`3.14.7`, `3.14` matches every `3.14.*`, and `3` matches `3.*` across all the catalogue files. Among the rows that suit the
system (FR4), the highest version wins, in numeric order, and the package is installed under its own `source_version`.
Edge cases: `3.14.1` does not match `3.14.10`, and `3.1` does not match `3.14.7`; `3.14.10` is higher than `3.14.9`, and
`3.14.1` higher than `3.9.20`; a newer version published only for another system is passed over in favour of an older one
that suits this system.

FR4. **Which rows suit the system.** A row suits when its `os` and `arch` equal those of the system, and:

- **Linux:** its `distro` equals the system's `<ID> <VERSION_ID>`, ignoring case. Another release of the same distribution does
  not suit: `ubuntu 22.04` is not `ubuntu 24.04`.
- **macOS:** its `distro` is `macos <version>`, and the system's version is the same or newer, comparing the components as numbers,
  with a missing component counting as 0. Edge cases: a package from `macos 15.7.9` suits 15.7.9, 15.8 and 26.6.2; it does
  not suit 15.7.8 or 14.8.1; a package from `macos 9.9` suits 15.1. A macOS row whose `distro` has another form does not suit.
- **Any other operating system:** nothing suits, whatever the catalogue says.

FR5. **No package: stop.** When no row matches and suits, the command exits non-zero with exactly
`pyenv-binary: no binary available for <version> on <os>/<arch>`, where `<version>` is the argument as given and `<os>` and `<arch>`
are the system's. It downloads nothing and installs nothing. In particular it **never falls back to a source build**: nothing
calls a compiler or `make`, and nothing asks python.org for a source archive, although a definition for that version
exists in python-build.

FR6. **Verify before installing.** Edge cases, each with exit non-zero and nothing installed, and nothing from the failed
download executed:

- the chosen row's `sha256` is not 64 hexadecimal digits: `pyenv-binary: invalid checksum for <entry>`, before any download;
- the file downloaded does not have that checksum, compared without regard to case: `pyenv-binary: checksum mismatch for <entry>`;
- the download fails: the command stops there (the message is free), with no retry through any other route;
- the definition itself fails while installing: the exit status is non-zero.

A checksum is verified with whatever the system provides (`sha256sum`, `shasum -a 256` or `openssl dgst -sha256`).

FR7. **A version already installed is left alone.** If `versions/<source_version>` already holds an installation, the outcome
is what `pyenv install` gives for an existing version when nobody confirms: with no terminal to ask (standard input empty),
the command exits non-zero, and the installed files stay as they were. Temporary files of the command are removed on
every way out (installed, stopped, failed verification), and they go under `TMPDIR`.

FR8. **The first catalogue.** The repository ships the file `3.14` of the catalogue with the header and the two rows shown
above, exactly.

FR9. **`pyenv binary save` records the source version.** It gains `--source-version <version>`, in any position among its arguments, and
its `.meta` file gets one line `source_version=<version>`. Without the option the line holds the version being saved.
`version=` still holds the installed name, and the other lines stay. The usage message becomes
`Usage: pyenv binary save <version> [<output-dir>] [--name <name>] [--source-version <version>]`, and shell completion offers the
option next to `--name`. Edge cases, all with exit non-zero and no file written:

- the option with no value, an empty one, or a value starting with `-`: `pyenv-binary: --source-version needs a value`;
- a value that contains `/` or a control character, or that is `.` or `..`: `pyenv-binary: invalid source version` followed by the value;
- with no option, an installed version whose name contains a control character is refused in the same way (its name would otherwise
  add lines to the `.meta` file); the words of the message may be `invalid source version` or `invalid version name`.

FR10. **`pyenv binary package` records what it built.** The `.meta` it writes has as `source_version` the version actually
built, not the entry name. Edge cases: `pyenv binary package 3.99:company` where `3.99.2` is the latest definition of that series
records `3.99.2` (the same resolution `pyenv install 3.99` makes); with a generated entry name, `3.99.1` records `3.99.1`; a definition given as a file,
`pyenv binary package /path/to/custom-python:custom-build`, records the file's name, `custom-python`.

FR11. **Documentation.** The plugin's README describes `pyenv binary install` and the catalogue, and the new option of
`save`. The existing test of the usage message of `save` is updated, and the plugin's tests cover the new behaviour.

## Compatibility to keep

This is the other half of the task, along with the error paths of FR5 to FR7.

- `pyenv install` does not change in any way. `pyenv install 3.14.7` builds from source and does not ask for a published package, even
  when the catalogue has a row for it and this system; `pyenv install --list` does not show catalogue entries; `pyenv install
  <file>:<alias>`, `pyenv install <definition>` and prefixes such as `pyenv install 3.99` behave as they do today.
- `pyenv binary save` without the new option keeps its file names and its other metadata lines; `pyenv binary generate-installer` still
  accepts a `.meta` file, with the new line in it. `pyenv binary package` still writes `<entry>.tar.xz`, `<entry>.meta` and the
  definition `<entry>` and leaves the build under `versions/<entry>`.
- The project's own test suite passes.

## Context

- pyenv's scripts are bash, and the project still supports bash 3.2 (the default on macOS).
- The suite is bats: from the repository root, `bats -j 8 test plugins/*/test` (bats and GNU `parallel` are installed). The network is closed while you work: nothing can really be downloaded, so tests simulate the external commands by
  putting small scripts first on `PATH`, as the existing tests of the plugin do.
- No failure of the suite is known at the starting commit.

## Out of scope

- Publishing packages or a tool that adds rows to the catalogue; changing the published address; other interpreters than numbered CPython
  versions, such as free-threaded `3.14.7t` builds, which are not in the valid form above.
- Any change to what a generated definition does (its own checks, relocation), and to `pyenv install`.
- New dependencies.
