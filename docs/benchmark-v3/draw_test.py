#!/usr/bin/env python3
"""Tests of draw.py (standard library only, no network):  python3 draw_test.py

The arithmetic of the seed is checked on the real values of version 2 (docs/benchmark/seed.txt). The refusals use fake
answers of GitHub and drand. Each clause of the rule has a counterproof, and so does the rejection itself: with the
check switched off, the same seed gives a set that breaks the rule.
"""

from __future__ import annotations

import collections
import contextlib
import hashlib
import io
import itertools
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import draw  # noqa: E402

V2 = {  # docs/benchmark/seed.txt
    "commit": "b72ff0755d0d5cc7f2339e2b9bb1e20936152530",
    "date": 1793950813,
    "round": 33717017,
    "time": "2026-11-06T08:40:15Z",
    "randomness": "af214728e90a98eb44150fc5bb7b6a28823da1378fd1e4c2cb5bd96884b63719",
    "seed": "b6d47025c21427a9bf548bb1accfca1961955d42a71130e82a60d6c40c1c5776",
}
COMMIT = "a" * 40
GOLDEN_SEED = "fixed-seed-of-the-test"
GOLDEN_SHA = "904648233b3c3c8ac5f7fe0d38e88595066f5ad278d0c4614ff2d974a78b1b4f"


def fake_get(date="2026-11-10T10:00:00Z", commit=COMMIT, sums=b"", beacon_error=None):
    def get(url):
        if "api.github.com" in url:
            return json.dumps({"sha": commit, "commit": {"committer": {"date": date}}}).encode()
        if "raw.githubusercontent.com" in url:
            return sums
        if beacon_error:
            raise beacon_error
        return json.dumps({"round": int(url.rsplit("/", 1)[1]), "randomness": "ab" * 32}).encode()
    return get


class Seed(unittest.TestCase):
    def test_round_and_seed_of_version_2(self):
        rnd, at = draw.round_for(V2["date"])
        self.assertEqual(rnd, V2["round"])
        self.assertEqual(draw.utc(at), V2["time"])
        self.assertEqual(draw.seed_of(V2["commit"], rnd, V2["randomness"]), V2["seed"])

    def test_round_is_the_first_at_least_one_hour_later(self):
        for date in (V2["date"], V2["date"] + 1, V2["date"] + 2, V2["date"] + 3):
            rnd, at = draw.round_for(date)
            self.assertGreaterEqual(at, date + 3600)
            self.assertLess(at - draw.DRAND_PERIOD, date + 3600)


class Refusals(unittest.TestCase):
    def inputs(self, get, now):
        return draw.public_inputs(COMMIT, get, lambda: now)

    def test_round_not_public_is_refused(self):
        date = 1794000000
        text = draw.utc(date)
        _, at = draw.round_for(date)
        with self.assertRaisesRegex(draw.Refused, "not public yet"):
            self.inputs(fake_get(text), at - 1)
        self.assertEqual(self.inputs(fake_get(text), at)[3], "ab" * 32)  # the same inputs, at its time: accepted

    def test_refused_before_asking_drand(self):
        asked = []

        def get(url):
            asked.append(url)
            return fake_get()(url)
        with self.assertRaises(draw.Refused):
            draw.public_inputs(COMMIT, get, lambda: 0)
        self.assertEqual(len(asked), 1)
        self.assertIn("api.github.com", asked[0])

    def test_round_missing_at_drand_is_refused(self):
        error = urllib.error.URLError("404")
        with self.assertRaisesRegex(draw.Refused, "not readable"):
            self.inputs(fake_get(beacon_error=error), 4000000000)

    def test_bad_commit_ids(self):
        for bad in ("abc", "A" * 40, "g" * 40):
            with self.assertRaisesRegex(draw.Refused, "full commit id"):
                draw.public_inputs(bad, fake_get(), lambda: 4000000000)

    def test_github_answers_another_commit(self):
        with self.assertRaisesRegex(draw.Refused, "another commit"):
            self.inputs(fake_get(commit="b" * 40), 4000000000)

    def test_cli_refuses_with_exit_2_and_no_result(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.assertEqual(draw.main(["abc"]), 2)
        self.assertEqual(out.getvalue(), "")
        self.assertIn("REFUSED", err.getvalue())


class Rule(unittest.TestCase):
    VALID = (["N1", "N2", "N3", "N6", "N9", "N11"], ["E1", "E2"])

    def test_a_valid_set(self):
        self.assertEqual(draw.violations(*self.VALID), [])

    def test_three_go_hard_tasks(self):
        self.assertIn("3 hard tasks in Go", draw.violations(["N3", "N4", "N12", "N1", "N2", "N6"], ["E2", "E3"]))

    def test_three_languages(self):
        broken = draw.violations(["N3", "N4", "N6", "N7", "N1", "N11"], ["E1", "E3"])
        self.assertEqual(broken, ["fewer than 4 languages (3)"])

    def test_two_tasks_from_one_repository(self):
        hard = dict(draw.HARD, N3=("tj/git-extras", "Go", "bug fix"))
        broken = draw.violations(["N3", "N2", "N1", "N6", "N9", "N11"], ["E2", "E3"], hard)
        self.assertEqual(broken, ["2 tasks from tj/git-extras"])

    def test_no_bug_fix_and_no_feature(self):
        all_features = {k: (v[0], v[1], "new feature") for k, v in draw.HARD.items()}
        easy = {k: (v[0], v[1], "new feature") for k, v in draw.EASY.items()}
        self.assertIn("no bug fix", draw.violations(*self.VALID, all_features, easy))
        all_fixes = {k: (v[0], v[1], "bug fix") for k, v in draw.HARD.items()}
        easy = {k: (v[0], v[1], "bug fix") for k, v in draw.EASY.items()}
        self.assertIn("no new feature", draw.violations(*self.VALID, all_fixes, easy))

    def test_no_compatibility_trap(self):
        # impossible with 6 hard tasks of this pool (see below): a smaller set shows the clause works
        self.assertIn("no task with backward compatibility as its trap",
                      draw.violations(["N1", "N3", "N5", "N6", "N7"], ["E1", "E2"]))

    def test_the_compatibility_clause_constrains_nothing(self):
        for hard in itertools.combinations(draw.HARD, 6):
            self.assertTrue(set(hard) & set(draw.COMPAT_TRAP))

    def test_counts_published_in_the_qualification(self):
        def valid(easy_ids, take):
            return sum(1 for h in itertools.combinations(draw.HARD, 6) for e in itertools.combinations(easy_ids, take)
                       if not draw.violations(h, e))
        self.assertEqual(valid(draw.EASY, 2), 519)
        self.assertEqual(valid(["E2", "E3"], 2), 175)


class Draw(unittest.TestCase):
    def seed_rejected_first(self):
        for i in range(1000):
            seed = "s%d" % i
            if draw.draw(seed)[1] > 0:
                return seed
        self.fail("no seed with a rejection")

    def test_rejection_is_what_keeps_the_rule(self):
        seed = self.seed_rejected_first()
        log, k, hard, easy, _, _ = draw.draw(seed)
        self.assertIn("REJECTED", log[0])
        self.assertEqual(len(log), k + 1)
        self.assertEqual(draw.violations(hard, easy), [])
        # counterproof: with the check switched off the same seed takes the first set, which breaks the rule
        _, k_off, hard_off, easy_off, _, _ = draw.draw(seed, check=lambda h, e: [])
        self.assertEqual(k_off, 0)
        self.assertNotEqual(draw.violations(hard_off, easy_off), [])

    def test_many_seeds_terminate_and_respect_the_rule(self):
        count = collections.Counter()
        total = 5000
        for i in range(total):
            _, _, hard, easy, rest_h, rest_e = draw.draw("many-%d" % i)
            self.assertEqual(draw.violations(hard, easy), [])
            self.assertEqual(sorted(hard + rest_h), sorted(draw.HARD))
            self.assertEqual(sorted(easy + rest_e), sorted(draw.EASY))
            self.assertEqual((len(hard), len(easy), len(rest_h), len(rest_e)), (6, 2, 4, 1))
            count.update(hard + easy)
        for task in ("N3", "N4", "N12"):
            self.assertAlmostEqual(count[task] / total, 0.52, delta=0.04)
        for task in ("N1", "N2", "N5", "N6", "N7", "N9", "N11"):
            self.assertAlmostEqual(count[task] / total, 0.64, delta=0.04)
        for task in draw.EASY:
            self.assertAlmostEqual(count[task] / total, 2 / 3, delta=0.04)

    def test_without_e1(self):
        text = draw.report(GOLDEN_SEED, without_e1=True)
        self.assertIn("pool easy: E2 E3\n", text)
        self.assertNotIn("E1 ", text)
        self.assertIn("replacement order, easy: (none)", text)

    def test_golden_output(self):
        text = draw.report(GOLDEN_SEED)
        self.assertEqual(hashlib.sha256(text.encode()).hexdigest(), GOLDEN_SHA, text)

    def test_same_bytes_in_new_processes(self):
        outputs = set()
        for hash_seed in ("0", "1", "12345"):
            env = dict(os.environ, PYTHONHASHSEED=hash_seed)
            outputs.add(subprocess.run([sys.executable, os.path.join(HERE, "draw.py"), "--seed", GOLDEN_SEED],
                                       env=env, stdout=subprocess.PIPE, check=True).stdout)
        self.assertEqual(len(outputs), 1)
        self.assertTrue(outputs.pop().startswith(b"MADE-UP SEED: A TEST OF THE PROCEDURE, NOT A DRAW\n"))


class E1Date(unittest.TestCase):
    def run_with(self, date):
        with tempfile.TemporaryDirectory() as folder:
            with open(os.path.join(folder, "a.txt"), "wb") as f:
                f.write(b"a")
            line = "%s  a.txt\n" % hashlib.sha256(b"a").hexdigest()
            with open(os.path.join(folder, "SHA256SUMS"), "w", newline="\n") as f:
                f.write(line)
            return draw.real_draw(COMMIT, folder, fake_get(date, sums=line.encode()), lambda: 4000000000)

    def test_before_and_on_the_limit(self):
        self.assertIn("pool easy: E1 E2 E3\n", self.run_with("2026-11-15T23:59:59Z"))
        out = self.run_with("2026-11-16T00:00:00Z")
        self.assertIn("pool easy: E2 E3\n", out)
        self.assertIn("E1 is out", out)

    def test_real_draw_uses_the_seed_of_its_inputs(self):
        out = self.run_with("2026-11-10T10:00:00Z")
        rnd = int(re.search(r"^drand_round: (\d+)$", out, re.M).group(1))
        self.assertIn("seed: %s\n" % draw.seed_of(COMMIT, rnd, "ab" * 32), out)
        self.assertEqual(out, self.run_with("2026-11-10T10:00:00Z"))


class Sums(unittest.TestCase):
    def folder(self, tmp, content=b"a", listed=None):
        with open(os.path.join(tmp, "a.txt"), "wb") as f:
            f.write(content)
        line = "%s  a.txt\n" % hashlib.sha256(listed or content).hexdigest()
        with open(os.path.join(tmp, "SHA256SUMS"), "w", newline="\n") as f:
            f.write(line)
        return line

    def test_a_changed_file_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            line = self.folder(tmp, b"changed", listed=b"a")
            with self.assertRaisesRegex(draw.Refused, "checksum differs: a.txt"):
                draw.check_sums(COMMIT, tmp, lambda url: line.encode())

    def test_a_list_other_than_the_commit_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.folder(tmp)
            other = "%s  a.txt\n" % ("0" * 64)
            with self.assertRaisesRegex(draw.Refused, "not those of the commit"):
                draw.check_sums(COMMIT, tmp, lambda url: other.encode())

    def test_lines_added_after_the_commit_are_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            line = self.folder(tmp)
            with open(os.path.join(tmp, "b.txt"), "wb") as f:
                f.write(b"b")
            with open(os.path.join(tmp, "SHA256SUMS"), "a", newline="\n") as f:
                f.write("%s  b.txt\n" % hashlib.sha256(b"b").hexdigest())
            self.assertEqual(draw.check_sums(COMMIT, tmp, lambda url: line.encode()),
                             hashlib.sha256(line.encode()).hexdigest())


class Published(unittest.TestCase):
    """What the qualification says and what the script does cannot drift apart."""

    def test_this_folder_matches_its_checksums(self):
        draw.local_sums(HERE)

    def test_tables_match_the_pools(self):
        with open(os.path.join(HERE, "QUALIFICATION.md"), encoding="utf-8") as f:
            text = f.read()
        words = {"JS/TS": ("JavaScript", "TypeScript"), "new feature": ("new feature",), "bug fix": ("bug fix",),
                 "compatibility": ("compatibility (breaking)",)}
        for task, (repo, language, kind) in {**draw.HARD, **draw.EASY}.items():
            row = re.search(r"^\| %s \| \[(\S+?)\].*\|$" % task, text, re.M)
            self.assertIsNotNone(row, task)
            self.assertEqual(row.group(1), repo)
            cell = row.group(0).split("|")[7].strip()
            self.assertTrue(any(cell.startswith(w + ", ") for w in words.get(language, (language,))), cell)
            self.assertTrue(any(cell.endswith(w) for w in words[kind]), cell)
        self.assertIn(" ".join(draw.COMPAT_TRAP[:-1]).replace(" ", ", ") + ", N12", text)


if __name__ == "__main__":
    unittest.main()
