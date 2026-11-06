`git stale-branches` is implemented, and all acceptance checks pass under `dash`, `bash` and `bash --posix`. Nothing is committed. Git Bash on Windows is the one target I couldn't test.

## What changed
- **`git-stale-branches`** (new, executable): the command itself.
- **`README.md`**: added the command to the list at the top, next to `git-recent-branches`, plus a new section with usage and examples.
- **`CHANGELOG.md`**: added an entry at the top of `v1.12.0`.

## What I verified
| Check | Result |
|---|---|
| `sh -n git-stale-branches` (`/bin/sh` is `dash`), plus `dash -n`, `bash -n` and `bash --posix -n` | pass |
| `shellcheck git-stale-branches` | exit 0, no findings |
| `test -x git-stale-branches`, and first line is `#!/bin/sh` | pass |
| Throwaway test script against temporary repositories, run once per shell | 83 checks, 0 failed in each |

The project has no test suite and the spec rules out a test framework, so I added no tests to the repo. The test script was in `/tmp` and I deleted it afterwards.

- **AC1–AC4:**
  - exact output and order for several dates
  - no overlap with `git active-branches`, and together they cover every local branch, across 9 dates
  - the `-m` / `-u` split and the 3-month default
  - every error case, and `-h`
- **Other cases:**
  - time zones near midnight, and a different `TZ` setting
  - branches with identical timestamps, and non-ASCII or slashed names
  - detached `HEAD`, running from a subdirectory, and an empty repository
  - a tip older than its parent
  - unhelpful git config, such as `color.ui=always`

The first test run caught a real bug: `git stale-branches foo` was accepted instead of giving a usage error, because of how the shell groups `||` and `&&`. It's fixed. The other failures in that run were mistakes in my test script.

## Choices the spec left open
- **Tags with the same name as a branch:** the script compares full ref names (`refs/heads/...`) rather than using `git local-branches`. Short names turn into `heads/foo` when a tag `foo` exists, which would break the output and the merge check.
- **Outside a repository:** it calls `git rev-parse --git-dir` directly, because `git is-repo` hides git's error message and FR7 requires it.
- **No main branch found:** without `-m` / `-u` it says nothing on stderr. With them it prints its own one-line error and exits 2.
- **Main branch only on the remote:** if `git main-branch` names a branch with no local copy, `-m` / `-u` compare against `refs/remotes/origin/<main>`. If that doesn't exist either, it counts as "no main branch".
- **Bad options:** `getopts` runs in quiet mode, so stderr shows only the usage text in every shell.

## Not verified or still open
- **Git Bash on Windows:** not available here. The script uses only POSIX shell features and git itself, so I expect it to work.
- **Existing bug in `git active-branches`:** from reading the code, it probably breaks on a branch that shares a name with a tag, because `git local-branches` prints `heads/foo`. I didn't run this or change it, as other commands are out of scope. For such a branch the "active or stale, never both" guarantee can't be checked.
- **Bare repositories:** from reading the code, `git main-branch` fails there because `git root` needs a work tree. `-m` / `-u` would then exit 2, and the main branch wouldn't be excluded from the list. I didn't test this.
- **Possible network call:** if there is an `origin` remote but no local `origin/HEAD` or common main branch name, `git main-branch` asks the remote for its HEAD, so the command can be slow in that case.

<!-- total_cost_usd=0.7329568000000001 duration_ms=175896 num_turns=7 -->
<!-- usage_from_transcript={"claude-opus-5-5": {"cache_creation_input_tokens": 41024, "cache_read_input_tokens": 182384, "calls": 6, "input_tokens": 12, "output_tokens": 66}} -->
