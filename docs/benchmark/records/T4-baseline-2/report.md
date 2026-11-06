`git stale-branches` is in place and meets all the acceptance criteria (AC1–AC6), giving identical results under `dash` and `bash`. Nothing is committed or pushed, and nothing was installed.

## What changed
- **`git-stale-branches`** (new, executable, `#!/bin/sh`): the command itself. It uses the same `git log -1 --since` test as `git-active-branches`.
- **`README.md`**: added an entry after `git-recent-branches` in the top list, and a new section with usage and examples.
- **`CHANGELOG.md`**: added an entry at the top of the `v1.12.0` section.

## What I verified
| Check | Result |
|---|---|
| `sh -n`, `dash -n`, `bash -n` on the script | pass |
| `shellcheck git-stale-branches` | clean |
| `test -x` and the first line of the file | executable, `#!/bin/sh` |
| Throwaway test script against temporary repositories, with `dash` | 48 of 48 pass |
| Same script with `bash` | 48 of 48 pass |
| Same script with `dash` under `LC_ALL=C.UTF-8` | 48 of 48 pass |

The spec rules out a test framework and doesn't ask for tests, so I added none to the repo and deleted the script afterwards. It covered:
- **AC1:** exact output and order for several dates, including no overlap and no gaps with `git active-branches`.
- **AC2–AC4:** the `-m`/`-u` split, the default date (4 and 2 months old), every error case and `-h`.
- **Branch names and sorting:** ties in byte order, and slashes, dots, dashes and non-ASCII characters in names.
- **Dates:** commit time zones and a different local `TZ`.
- **Repository states:** detached `HEAD`, an empty repository, and a tag with the same name as a branch.
- **Main branch only on origin:** `origin/HEAD` set with no local main, and the case where `git main-branch` has to ask the remote, using a local clone.

## Choices I made where the spec was silent
- **Empty date:** `-s ''` is a usage error (status 2). Git would read it as "now" and call every branch stale.
- **Main branch only on origin:** `-m`/`-u` compare against `refs/remotes/origin/<main>`. If that doesn't exist either, the command exits 2.
- **`git main-branch` failing for another reason:** the command stops with that status, rather than risk listing the main branch as stale. This happens if the toolbelt isn't on the `PATH`. It also happens in a bare repository, where the command exits 128 even without `-m`/`-u`, because `git main-branch` relies on `git is-repo`, which needs a work tree.
- **Repository check:** I used `git rev-parse --git-dir` rather than `git is-repo`, because `git is-repo` hides the git error that FR7 requires.

## Still open
- **Invalid dates:** `-s garbage` isn't rejected, because `git log --since` accepts it without error. Every branch then shows as stale and none as active, which keeps the two commands consistent but could mislead someone who mistypes a date.
- **Bug in `git active-branches` (not fixed, out of scope):** it crashes with `fatal: bad revision 'refs/heads/heads/foo'` if a tag has the same name as a local branch. `git stale-branches` handles this case, but the AC1 comparison can't run on such a repository, so I removed that branch before running it.
- **Same day, out of order:** sorting uses the exact commit time, as FR4 asks, so commits in different time zones can look out of order by date. In my test, `2020-07-01 tzplus` correctly comes before `2020-07-01 tzminus`.
- **Git Bash on Windows:** not run. I only tested `dash` and `bash` on Linux; the script avoids bash-only syntax and `sed`, `sort` and `date` altogether.

<!-- total_cost_usd=0.7464253999999999 duration_ms=188636 num_turns=7 -->
<!-- usage_from_transcript={"claude-opus-5-5": {"cache_creation_input_tokens": 40073, "cache_read_input_tokens": 226827, "calls": 7, "input_tokens": 14, "output_tokens": 847}} -->
