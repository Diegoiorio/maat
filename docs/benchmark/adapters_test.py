#!/usr/bin/env python3
"""Tests of the format adapters of T2 and T3 (tasks/*/adapter/), on small synthetic projects:

    NM=<a node_modules with tape> python3 adapters_test.py        (go and node in PATH)

go-junit.py: a red with its `file:line`, a test file that does not compile (`./m_test.go:6:5`), a panic (the tests
after it are failed «did not run», not missing), an Example, a subpackage. tape-junit.py: a comment that looks like
a test name (one case, not two), a summary-like comment, a red with its `file:line`, a file that does not load.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
GO_JUNIT = os.path.join(HERE, "tasks", "T2-go-humanize-bytes-rounding", "adapter", "go-junit.py")
TAPE_DIR = os.path.join(HERE, "tasks", "T3-minimist-split-modules", "adapter")


def write(root, files):
    for name, text in files.items():
        p = os.path.join(root, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)


def cases(report):
    out = {}
    for c in ET.parse(report).getroot().iter("testcase"):
        bad = [e for e in c if e.tag in ("failure", "error")]
        out[(c.get("classname"), c.get("name"))] = "\n".join((e.get("message") or "") + "\n" + (e.text or "") for e in bad) or "ok"
    return out


GO_MOD = "module example.com/m\n\ngo 1.21\n"
LIB = "package m\n\nfunc Two() int { return 2 }\n"


class GoJunit(unittest.TestCase):
    def run_go(self, files):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d)
        write(d, dict({"go.mod": GO_MOD, "m.go": LIB}, **files))
        env = dict(os.environ, GOFLAGS="-mod=mod", GOTOOLCHAIN="local", GOPROXY="off")
        p = subprocess.run([sys.executable, "-B", GO_JUNIT, os.path.join(d, "r.xml")], cwd=d, env=env,
                           capture_output=True, text=True)
        return p.returncode, cases(os.path.join(d, "r.xml"))

    def test_red_with_position(self):
        rc, c = self.run_go({"m_test.go": 'package m\n\nimport "testing"\n\nfunc TestOk(t *testing.T) {}\n\n'
                             'func TestRed(t *testing.T) {\n\tif Two() != 3 {\n\t\tt.Errorf("Two() = %d, want 3", Two())\n\t}\n}\n'})
        self.assertNotEqual(rc, 0)
        self.assertEqual(c[("m_test.go", "TestOk")], "ok")
        self.assertIn("m_test.go:9: Two() = 2, want 3", c[("m_test.go", "TestRed")])

    def test_build_failure_with_dot_slash(self):
        rc, c = self.run_go({"m_test.go": 'package m\n\nimport "testing"\n\nfunc TestX(t *testing.T) {\n\t_ = Three()\n}\n'})
        self.assertNotEqual(rc, 0)
        self.assertIn(("", "m_test.go"), c)                      # the whole file is red
        self.assertIn("m_test.go:6", c[("", "m_test.go")])
        self.assertNotIn(("", "./m_test.go"), c)

    def test_panic_keeps_the_tests_that_did_not_run(self):
        rc, c = self.run_go({"m_test.go": 'package m\n\nimport "testing"\n\nfunc TestA(t *testing.T) {}\n\n'
                             'func TestB(t *testing.T) { panic("boom") }\n\nfunc TestC(t *testing.T) {}\n'})
        self.assertNotEqual(rc, 0)
        self.assertEqual(c[("m_test.go", "TestA")], "ok")
        self.assertIn("boom", c[("m_test.go", "TestB")])
        self.assertIn("did not run: TestC", c[("m_test.go", "TestC")])

    def test_example_and_subpackage(self):
        rc, c = self.run_go({"m_test.go": 'package m\n\nimport "fmt"\n\nfunc ExampleTwo() {\n\tfmt.Println(Two())\n\t// Output: 3\n}\n',
                             "sub/s.go": "package sub\n", "sub/s_test.go": 'package sub\n\nimport "testing"\n\nfunc TestS(t *testing.T) {\n\tt.Fatal("no")\n}\n'})
        self.assertNotEqual(rc, 0)
        self.assertIn("ExampleTwo", "".join(n for _, n in c))
        self.assertIn(("m_test.go", "ExampleTwo"), c)
        self.assertIn("sub/s_test.go:6", c[("sub.s_test.go", "TestS")])


class TapeJunit(unittest.TestCase):
    def run_tape(self, files):
        nm = os.environ.get("NM")
        if not nm:
            self.skipTest("NM not set")
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d)
        write(d, files)
        os.symlink(nm, os.path.join(d, "node_modules"))
        bench = os.path.join(d, ".claude", "bench")
        os.makedirs(bench)
        for f in ("tape-junit.py", "tape-objects.js"):
            shutil.copy(os.path.join(TAPE_DIR, f), bench)
        p = subprocess.run([sys.executable, "-B", os.path.join(bench, "tape-junit.py"), os.path.join(d, "r.xml")],
                           cwd=d, capture_output=True, text=True)
        return p.returncode, cases(os.path.join(d, "r.xml"))

    def test_comment_is_not_a_test(self):
        rc, c = self.run_tape({"test/a.js": "'use strict';\nvar test = require('tape');\n\n"
                               "test('first', function (t) {\n\tt.comment('second');\n\tt.comment('tests 3');\n"
                               "\tt.equal(1, 2, 'one is two');\n\tt.end();\n});\n"})
        self.assertEqual(rc, 1)
        self.assertEqual(sorted(c), [("test.a.js", "first")])
        self.assertIn("one is two", c[("test.a.js", "first")])
        self.assertIn("test/a.js:7", c[("test.a.js", "first")])

    def test_green_and_summary_lines(self):
        rc, c = self.run_tape({"test/b.js": "'use strict';\nvar test = require('tape');\n\n"
                               "test('ok', function (t) {\n\tt.comment('ok');\n\tt.ok(true);\n\tt.end();\n});\n"})
        self.assertEqual(rc, 0)
        self.assertEqual(c, {("test.b.js", "ok"): "ok"})

    def test_file_that_does_not_load(self):
        rc, c = self.run_tape({"test/c.js": "'use strict';\nvar x = require('./missing');\n"})
        self.assertEqual(rc, 1)
        self.assertIn(("", "test/c.js"), c)
        self.assertIn("missing", c[("", "test/c.js")])


if __name__ == "__main__":
    unittest.main()
