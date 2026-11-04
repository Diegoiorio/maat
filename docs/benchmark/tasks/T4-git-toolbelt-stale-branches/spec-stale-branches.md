# Spec: a `git stale-branches` command that lists old local branches

## Context

The toolbelt is a collection of POSIX shell scripts, one per command, at the root of the repository
(`git-<command>`); git runs `git-<command>` found on the `PATH` as `git <command>`. Several commands deal with
branches: `git-active-branches` lists the local and remote branches with a commit since a date (default
`3.weeks.ago`), `git-recent-branches` lists local branches by date, `git-merged` / `git-unmerged` list branches
merged (or not) into the main branch, `git-main-branch` prints the name of the main branch, `git-current-branch`
the current one. The commands are documented in `README.md` (a list at the top and one section per command) and
the changes in `CHANGELOG.md`.

There is no command to find the local branches that nobody has touched for a long time, which is the first step of
a branch clean-up. The project has **no automated tests**.

## Goal

A new command, `git stale-branches`, lists the local branches whose last commit is older than a date, oldest
first, optionally only the merged or only the unmerged ones.

## Functional requirements

FR1. A new executable script `git-stale-branches` at the root of the repository, a POSIX shell script
(`#!/bin/sh`, `set -eu`, like the other commands), runnable as `git stale-branches` when the repository root is on
the `PATH`.

FR2. Usage: `git stale-branches [-s <date>] [-m | -u] [-h]`.
- `-s <date>`: the cut-off date, in any format accepted by `git log --since` (`3.months.ago`, `2025-01-31`, …).
  Default: `3.months.ago`.
- `-m`: list only the stale branches that are merged into the main branch.
- `-u`: list only the stale branches that are not merged into the main branch.
- `-h`: print the usage text on standard output and exit 0.

FR3. A local branch is **stale** when its tip commit is not selected by `git log -1 --since=<date>` (the same
test that `git-active-branches` uses, so that for the same date a local branch is either active or stale, never
both, never neither).

FR4. Output: one line per stale branch, `<date><TAB><branch>`, where `<date>` is the committer date of the tip
commit in `YYYY-MM-DD` form (in the time zone recorded in the commit) and `<branch>` the short branch name
(`feature/login`, not `refs/heads/feature/login`). Lines are sorted by the tip's committer date, oldest first;
branches with the same date and time are sorted by name, in byte order. No header and no other output on standard
output. No stale branch: no output, exit 0.

FR5. Never listed: the current branch (when `HEAD` is on a branch) and the main branch as printed by
`git main-branch`. If `git main-branch` cannot find a main branch, only the current branch is excluded, unless `-m`
or `-u` is given: in that case the command prints an error on standard error and exits with status 2, with no
output on standard output.

FR6. Merged means: the branch tip is an ancestor of the main branch tip (the meaning `git merged` uses).

FR7. Errors: an unknown option, `-s` without a value, `-m` together with `-u`, or any positional argument prints
the usage text on standard error and exits with status 2. Outside a git repository the command exits with a
non-zero status, prints git's error on standard error and nothing on standard output.

FR8. Branch names with slashes, dots, dashes or non-ASCII characters are printed as they are.

FR9. The script works with `/bin/sh` being `dash` (Debian, Ubuntu), `bash`, or the shell of Git for Windows (Git
Bash): no bashisms, no GNU-only options of `sed`, `sort` or `date`.

FR10. `README.md` lists the new command in the list at the top (with the branch commands) and gains a section
for it in the style of the others (usage and an example); `CHANGELOG.md` gains an entry for it in its topmost
section (the release being prepared, `v1.12.0` at the starting commit).

## Codebase areas involved (indicative)

- New file `git-stale-branches`.
- `git-active-branches`, `git-merged`, `git-main-branch`, `git-local-branches` (read: conventions and helpers).
- `README.md`, `CHANGELOG.md`.

## Acceptance criteria

AC1. In a test repository whose branches have known committer dates, `git stale-branches -s <date>` prints exactly
the expected lines, in the expected order, for several dates; for the same date, its branches and the local
branches of `git active-branches -s <date>` are disjoint and together form all local branches except the
current and the main one.

AC2. `-m` and `-u` split the stale branches into merged and unmerged ones as in FR6.

AC3. The default date is `3.months.ago`: a branch whose last commit is 4 months old is listed, one whose last
commit is 2 months old is not.

AC4. Every error case of FR5 and FR7 gives the stated exit status and output; `-h` prints the usage on standard
output and exits 0.

AC5. `sh -n git-stale-branches` passes, and the behaviour of AC1–AC4 is the same with `dash` and with `bash`.

AC6. The file is executable (`test -x git-stale-branches`) and starts with `#!/bin/sh`.

## Assumptions

- Remote branches are out of the command's scope (`git-active-branches` covers them).
- Running other toolbelt commands (`git main-branch`) from the script is fine: they are installed together.

## Out of scope

- Deleting branches, or any change to other commands.
- A test framework for the project.

## Constraints

- POSIX shell only, no new dependencies; style of the existing scripts (`usage()` heredoc, `getopts`).
