#!/usr/bin/env python3
"""Tests of grafici.py with synthetic records (standard library only):  python3 grafici_test.py

Cases: complete (30 runs, every measure), partial (some runs, review and adjudication not there yet: «pending»),
measures missing from finished runs (null cost, no hidden score: «missing»), a run that ended in STOP, no record at
all; the dashed line of the starting commit on the hidden-tests chart. Every chart must be valid XML,
contain no NaN or infinity, and be byte-for-byte the same when built twice or from records written in another
order.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import grafici  # noqa: E402

BAD_NUMBER = re.compile(r"\b(nan|inf|infinity)\b", re.IGNORECASE)


def rec(task, side, k, **kw):
    r = {
        "run_id": "%s-%s-%d" % (task, side, k), "task": task, "side": side, "order": 0,
        "outcome": "IMPLEMENTED" if side == "maat" else "COMPLETED",
        "wall_clock_s": 600 * k + 60 * int(task[1]),
        "cost_usd_api_equivalent": 1.25 * k + (0.5 if side == "maat" else 0.0),
        "hidden_tests": {"passed": 15 + k, "total": 21},
        "blind_review_entries": [{"id": "D1", "verdict": "confirmed"}, {"id": "D2", "verdict": "rejected"}][:k - 1],
        "confirmed_defects": [], "undisclosed_defects": [{"id": "D1"}] * (k - 1),
    }
    r.update(kw)
    return r


def complete():
    return [rec(t, s, k) for t in grafici.TASKS for s in grafici.SIDES for k in (1, 2, 3)]


def partial():
    # 7 runs done: the hidden score is there, the review and the adjudication are not (null)
    late = {"blind_review_entries": None, "confirmed_defects": None, "undisclosed_defects": None}
    return [rec("T1", "maat", 1, **late), rec("T1", "maat", 2, **late), rec("T1", "baseline", 1, **late),
            rec("T2", "baseline", 1, **late), rec("T3", "maat", 1, **late), rec("T4", "maat", 1, **late),
            rec("T5", "baseline", 3, **late)]


def missing():
    return [rec("T1", "maat", 1, cost_usd_api_equivalent=None, hidden_tests=None),
            rec("T2", "baseline", 1, hidden_tests={"passed": 0, "total": 0}, cost_usd_api_equivalent=float("nan")),
            rec("T3", "maat", 1, wall_clock_s=None, undisclosed_defects=None)]


def with_stop():
    return [rec("T2", "maat", 1, outcome="STOP", outcome_detail="BLOCKED at test-red",
                hidden_tests={"passed": 6, "total": 21}, cost_usd_api_equivalent=0.0, wall_clock_s=95),
            rec("T2", "baseline", 1)]


def write(d, records, reverse=False):
    for r in (reversed(records) if reverse else records):
        os.makedirs(os.path.join(d, r["run_id"]), exist_ok=True)
        with open(os.path.join(d, r["run_id"], "record.json"), "w", encoding="utf-8") as fh:
            json.dump(r, fh)


class Grafici(unittest.TestCase):
    def build(self, records, reverse=False):
        with tempfile.TemporaryDirectory() as d:
            write(d, records, reverse)
            return grafici.build(grafici.load(d))

    def check_valid(self, charts):
        self.assertEqual(sorted(charts), ["blind-review.svg", "cost-time.svg", "hidden-tests.svg",
                                          "undisclosed-defects.svg"])
        for name, svg in charts.items():
            ET.fromstring(svg)
            self.assertIsNone(BAD_NUMBER.search(svg), name)
            self.assertIn('fill="#fcfcfb"', svg, name)          # explicit background
            self.assertIn("url(#hatch)", svg, name)             # the baseline differs without colour

    def check_deterministic(self, records):
        a, b, c = self.build(records), self.build(records), self.build(records, reverse=True)
        self.assertEqual(a, b)
        self.assertEqual(a, c)

    def test_complete(self):
        ch = self.build(complete())
        self.check_valid(ch)
        self.check_deterministic(complete())
        for svg in ch.values():
            self.assertNotIn("not yet available", svg)
            self.assertEqual(svg.count("n=3 of 3"), 10 * (2 if "Wall-clock" in svg else 1))
        self.assertIn(">0%<", ch["hidden-tests.svg"])           # fixed 0-100 % scale
        self.assertEqual(ch["hidden-tests.svg"].count('stroke-dasharray="5 3"'), 5)   # the starting commit, per task
        self.assertIn(">100%<", ch["hidden-tests.svg"])

    def test_partial(self):
        ch = self.build(partial())
        self.check_valid(ch)
        self.check_deterministic(partial())
        self.assertIn("n=2 of 3", ch["hidden-tests.svg"])
        for name in ("undisclosed-defects.svg", "blind-review.svg"):
            self.assertEqual(ch[name].count("not yet available"), 10, name)
            self.assertIn("Not yet available: filled in after all 30 runs.", ch[name])
            self.assertNotIn("n=1 of 3", ch[name])              # a null value is not a zero
        self.assertEqual(ch["hidden-tests.svg"].count("not yet available"), 10 - 7 + 1)  # 4 bars with no run

    def test_missing_measures(self):
        ch = self.build(missing())
        self.check_valid(ch)
        self.check_deterministic(missing())
        hid = ch["hidden-tests.svg"]
        self.assertEqual(hid.count("n=0 of 3"), 9)              # null score and total 0: not available
        self.assertEqual(hid.count(">missing<"), 2)            # a finished run without a score is «missing»…
        self.assertEqual(hid.count(">1 missing<"), 2)
        self.assertNotIn("missing", ch["undisclosed-defects.svg"])   # …the adjudication not done yet is «pending»
        cost = ch["cost-time.svg"]
        self.assertEqual(cost.count("n=1 of 3"), 1 + 2)         # cost: only T3-maat; time: T1-maat, T2-baseline

    def test_stop_run(self):
        ch = self.build(with_stop())
        self.check_valid(ch)
        self.check_deterministic(with_stop())
        self.assertIn(">29%<", ch["hidden-tests.svg"])          # 6/21 counted as it is
        self.assertIn(">0<", ch["cost-time.svg"])               # a cost of 0 is drawn, not hidden

    def test_no_records(self):
        ch = self.build([])
        self.check_valid(ch)
        for svg in ch.values():
            self.assertEqual(svg.count("not yet available"), 10 * (2 if "Wall-clock" in svg else 1))

    def test_cli_writes_same_bytes(self):
        with tempfile.TemporaryDirectory() as d:
            write(os.path.join(d, "rec"), partial())
            outs = []
            for o in ("o1", "o2"):
                subprocess.run([sys.executable, "-B", os.path.join(HERE, "grafici.py"), "--records",
                                os.path.join(d, "rec"), "--out", os.path.join(d, o)], check=True,
                               stdout=subprocess.DEVNULL)
                got = {}
                for n in sorted(os.listdir(os.path.join(d, o))):
                    with open(os.path.join(d, o, n), "rb") as fh:
                        got[n] = fh.read()
                outs.append(got)
            self.assertEqual(outs[0], outs[1])
            self.assertEqual(len(outs[0]), 4)

    def test_progress(self):
        p = grafici.progress({r["run_id"]: r for r in partial()})
        self.assertIn("partial: 7 of 30", p)
        self.assertIn("| T1 | 2 of 3 | 1 of 3 |", p)
        self.assertIn("complete", grafici.progress({r["run_id"]: r for r in complete()}))

    def test_duplicate_run_refused(self):
        with tempfile.TemporaryDirectory() as d:
            r = rec("T1", "maat", 1)
            write(d, [r])
            os.makedirs(os.path.join(d, "copy"))
            with open(os.path.join(d, "copy", "record.json"), "w", encoding="utf-8") as fh:
                json.dump(r, fh)
            with self.assertRaises(SystemExit):
                grafici.load(d)


if __name__ == "__main__":
    unittest.main()
