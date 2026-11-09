#!/usr/bin/env python3
"""The draw of the tasks of the Maat benchmark, version 3 (QUALIFICATION.md, «Draw»). Standard library only.

    python3 draw.py <qualification commit id>     the real draw, once the commit and its drand round are public
    python3 draw.py --seed <text> [--without-e1]  the procedure on a made-up seed: a test, never a draw

The output contains no clock time and no machine detail: the same inputs give the same bytes. The real draw refuses,
with exit 2 and no result, when the commit is not public, when the round is not public yet, or when the checksums of
the qualification files do not match. The result is saved as draw.txt:  python3 draw.py <commit> > draw.txt
"""

from __future__ import annotations

import calendar
import collections
import hashlib
import json
import os
import random
import sys
import time
import urllib.error
import urllib.request

GITHUB_REPO = "Diegoiorio/maat"  # the qualification commit is read from here: it must be public
DRAND_URL = "https://api.drand.sh"
DRAND_CHAIN = "52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971"  # «quicknet», League of Entropy
DRAND_GENESIS = 1692803367
DRAND_PERIOD = 3
SEED_DELAY_S = 3600
SUMS_PATH = "docs/benchmark-v3/SHA256SUMS"
E1_LAST_DAY_EXCLUSIVE = calendar.timegm((2026, 11, 16, 0, 0, 0))  # C2: E1 stays only if the commit is before this (UTC)
HARD_TAKEN, EASY_TAKEN = 6, 2
MAX_K = 100000  # never reached: 82% of the combinations are valid; a guard, not a rule

# id: (repository, language group, kind of change). Fixed by the qualification commit; sorted as in the tables.
HARD = {
    "N1": ("agronholm/anyio", "Python", "new feature"),
    "N2": ("h3js/h3", "JS/TS", "compatibility"),
    "N3": ("labstack/echo", "Go", "bug fix"),
    "N4": ("mikefarah/yq", "Go", "new feature"),
    "N5": ("nodejs/undici", "JS/TS", "bug fix"),
    "N6": ("hyperium/hyper", "Rust", "new feature"),
    "N7": ("tafia/quick-xml", "Rust", "bug fix"),
    "N9": ("pyenv/pyenv", "shell", "new feature"),
    "N11": ("tox-dev/tox", "Python", "bug fix"),
    "N12": ("alecthomas/kong", "Go", "new feature"),
}
EASY = {
    "E1": ("BurntSushi/toml", "Go", "bug fix"),
    "E2": ("tj/git-extras", "shell", "new feature"),
    "E3": ("BurntSushi/jiff", "Rust", "bug fix"),
}
COMPAT_TRAP = ("N2", "N4", "N9", "N11", "N12")  # backward compatibility is the named D3 trap


class Refused(Exception):
    """The draw cannot be made now: exit 2, no result."""


def violations(hard, easy, pool_hard=HARD, pool_easy=EASY):
    """The clauses of the variety rule that a set breaks; empty means valid."""
    info = {**pool_hard, **pool_easy}
    tasks = list(hard) + list(easy)
    out = []
    languages = {info[t][1] for t in tasks}
    if len(languages) < 4:
        out.append("fewer than 4 languages (%d)" % len(languages))
    per_language = collections.Counter(info[t][1] for t in hard)
    for language in sorted(per_language):
        if per_language[language] > 2:
            out.append("%d hard tasks in %s" % (per_language[language], language))
    per_repo = collections.Counter(info[t][0] for t in tasks)
    for repo in sorted(per_repo):
        if per_repo[repo] > 1:
            out.append("%d tasks from %s" % (per_repo[repo], repo))
    kinds = {info[t][2] for t in tasks}
    for kind in ("bug fix", "new feature"):
        if kind not in kinds:
            out.append("no %s" % kind)
    if not set(tasks) & set(COMPAT_TRAP):
        out.append("no task with backward compatibility as its trap")
    return out


def shuffled(seed, k, hard_ids, easy_ids):
    """One attempt: one generator for the attempt, the hard pool shuffled first, then the easy pool."""
    rng = random.Random("%s:%d" % (seed, k))
    hard, easy = list(hard_ids), list(easy_ids)
    rng.shuffle(hard)
    rng.shuffle(easy)
    return hard, easy


def draw(seed, hard_ids=None, easy_ids=None, check=violations):
    """Attempts k = 0, 1, 2, … until a set is valid. Returns (log lines, k, hard, easy, rest of hard, rest of easy)."""
    hard_ids = list(HARD) if hard_ids is None else list(hard_ids)
    easy_ids = list(EASY) if easy_ids is None else list(easy_ids)
    log = []
    for k in range(MAX_K):
        hard, easy = shuffled(seed, k, hard_ids, easy_ids)
        picked_h, picked_e = hard[:HARD_TAKEN], easy[:EASY_TAKEN]
        broken = check(picked_h, picked_e)
        log.append("k=%d: hard %s | easy %s -> %s"
                   % (k, " ".join(picked_h), " ".join(picked_e), "REJECTED: " + "; ".join(broken) if broken else "valid"))
        if not broken:
            return log, k, picked_h, picked_e, hard[HARD_TAKEN:], easy[EASY_TAKEN:]
    raise Refused("no valid set in %d attempts" % MAX_K)


def round_for(committer_date_unix):
    """The first drand round whose time is at least SEED_DELAY_S after the commit, and that time."""
    target = committer_date_unix + SEED_DELAY_S
    rnd = max(1, -(-(target - DRAND_GENESIS) // DRAND_PERIOD) + 1)
    return rnd, DRAND_GENESIS + (rnd - 1) * DRAND_PERIOD


def seed_of(commit, rnd, randomness):
    """As in version 2: the SHA-256 of «<commit>:<round>:<randomness>»."""
    return hashlib.sha256(("%s:%d:%s" % (commit, rnd, randomness)).encode()).hexdigest()


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "maat-benchmark-draw"})
    with urllib.request.urlopen(request, timeout=30) as reply:
        return reply.read()


def utc(unix):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(unix))


def public_inputs(commit, get=fetch, now=time.time):
    """Commit date and drand round, both read from public sources. Refuses what is not public (yet)."""
    if len(commit) != 40 or set(commit) - set("0123456789abcdef"):
        raise Refused("the full commit id is needed (40 lower-case hex digits)")
    try:
        info = json.loads(get("https://api.github.com/repos/%s/commits/%s" % (GITHUB_REPO, commit)))
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise Refused("commit %s not readable from %s: %s" % (commit, GITHUB_REPO, e))
    if info.get("sha") != commit:
        raise Refused("GitHub answers with another commit: %s" % info.get("sha"))
    date = info["commit"]["committer"]["date"]
    committed = calendar.timegm(time.strptime(date, "%Y-%m-%dT%H:%M:%SZ"))
    rnd, at = round_for(committed)
    if now() < at:
        raise Refused("round %d is at %s UTC: not public yet" % (rnd, utc(at)))
    try:
        beacon = json.loads(get("%s/%s/public/%d" % (DRAND_URL, DRAND_CHAIN, rnd)))
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise Refused("round %d not readable: %s" % (rnd, e))
    if beacon.get("round") != rnd or not beacon.get("randomness"):
        raise Refused("drand answers with another round: %s" % beacon.get("round"))
    return committed, rnd, at, beacon["randomness"]


def local_sums(folder):
    """Checks every line of SHA256SUMS against the files of this folder; returns the file's bytes."""
    with open(os.path.join(folder, "SHA256SUMS"), "rb") as f:
        raw = f.read()
    for line in raw.decode().splitlines():
        want, name = line.split("  ", 1)
        with open(os.path.join(folder, name), "rb") as f:
            have = hashlib.sha256(f.read()).hexdigest()
        if have != want:
            raise Refused("checksum differs: %s" % name)
    return raw


def check_sums(commit, folder, get=fetch):
    """The local files match the local list, and the list holds every line of the list in the commit."""
    raw = local_sums(folder)
    try:
        published = get("https://raw.githubusercontent.com/%s/%s/%s" % (GITHUB_REPO, commit, SUMS_PATH))
    except (urllib.error.URLError, OSError) as e:
        raise Refused("SHA256SUMS not readable at the commit: %s" % e)
    missing = set(published.decode().splitlines()) - set(raw.decode().splitlines())
    if missing:
        raise Refused("the local files are not those of the commit: %s" % sorted(missing)[0])
    return hashlib.sha256(published).hexdigest()


def report(seed, without_e1=False):
    """Every step and the result, as text."""
    easy_ids = [t for t in EASY if not (without_e1 and t == "E1")]
    log, k, hard, easy, rest_h, rest_e = draw(seed, easy_ids=easy_ids)
    lines = ["seed: %s" % seed, "pool hard: %s" % " ".join(HARD), "pool easy: %s" % " ".join(easy_ids)]
    lines += ["attempts:"] + ["  " + line for line in log]
    lines += ["accepted at k=%d" % k]
    lines += ["hard tasks (%d):" % len(hard)]
    lines += ["  %s %s (%s, %s)" % (t, HARD[t][0], HARD[t][1], HARD[t][2]) for t in hard]
    lines += ["easy tasks (%d):" % len(easy)]
    lines += ["  %s %s (%s, %s)" % (t, EASY[t][0], EASY[t][1], EASY[t][2]) for t in easy]
    lines += ["replacement order, hard: %s" % (" ".join(rest_h) or "(none)")]
    lines += ["replacement order, easy: %s" % (" ".join(rest_e) or "(none)")]
    return "\n".join(lines) + "\n"


def real_draw(commit, folder, get=fetch, now=time.time):
    committed, rnd, at, randomness = public_inputs(commit, get, now)
    sums = check_sums(commit, folder, get)
    without_e1 = committed >= E1_LAST_DAY_EXCLUSIVE
    head = ["commit: %s" % commit,
            "committer_date_utc: %s" % utc(committed),
            "sha256_of_SHA256SUMS: %s" % sums,
            "c2_for_E1: %s" % ("commit on or after 2026-11-16: E1 is out" if without_e1 else "commit before 2026-11-16: E1 is in"),
            "drand_chain: %s" % DRAND_CHAIN,
            "drand_round: %d" % rnd,
            "drand_round_time_utc: %s" % utc(at),
            "drand_randomness: %s" % randomness]
    return "\n".join(head) + "\n" + report(seed_of(commit, rnd, randomness), without_e1)


def main(argv):
    folder = os.path.dirname(os.path.abspath(__file__))
    try:
        if len(argv) >= 2 and argv[0] == "--seed" and argv[2:] in ([], ["--without-e1"]):
            text = "MADE-UP SEED: A TEST OF THE PROCEDURE, NOT A DRAW\n" + report(argv[1], argv[2:] == ["--without-e1"])
        elif len(argv) == 1 and not argv[0].startswith("-"):
            text = real_draw(argv[0], folder)
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except Refused as e:
        print("draw: REFUSED: %s" % e, file=sys.stderr)
        return 2
    sys.stdout.buffer.write(text.encode())  # bytes: no newline translation on any system
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
