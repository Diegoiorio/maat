#!/usr/bin/env python3
"""tape-junit.py — format adapter of the benchmark (T3): runs tape one test file at a time and writes a JUnit report
that Maat 1.6.0 reads (report "junit"). Not part of the project: on the Maat side it is installed, with
tape-objects.js, in .claude/bench/ (excluded from the final diff); the baseline side does not use it.

    python3 .claude/bench/tape-junit.py <report.xml> [test files…]     (from the package root; NODE = node binary)

With no file it runs every `test/**/*.js`, as the project's `npx tape 'test/**/*.js'`. Each file runs on its own,
through tape-objects.js, which prints tape's object stream (not TAP text, where a comment looks like a test name):
each `test('name', …)` is one <testcase>, classname = the file path with "/" written as "." (the form Maat matches
with the plan's `file::name`), name = the test name. A test fails when one of its assertions fails; the failure
keeps the assertion's name, operator, expected, actual and `at: … (file:line:col)`, with absolute paths written from
the package root, so Maat finds the line of the red. A file that does not load, or exits non-zero with no failed
assertion, gives one case with no classname named after the file: Maat reads it as the whole file being red.
Exit status: 1 if anything failed, else 0.
"""

import glob
import json
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

NODE = os.environ.get("NODE", "node")
WRAPPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tape-objects.js")


def files_of(argv):
    if argv:
        return [a.replace("\\", "/") for a in argv]
    return sorted(f.replace("\\", "/") for f in glob.glob("test/**/*.js", recursive=True))


def run_file(path):
    p = subprocess.run([NODE, WRAPPER, path], capture_output=True, text=True)
    cwd = os.getcwd().replace("\\", "/").rstrip("/") + "/"
    tests, by_id = [], {}
    for line in p.stdout.splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if row.get("type") == "test":
            t = {"name": row.get("name") or "(no name)", "fail": [], "n": 0}
            tests.append(t)
            by_id[row.get("id")] = t
        elif row.get("type") == "assert":
            t = by_id.get(row.get("test"))
            if t is None:
                t = {"name": "(assertion outside a test)", "fail": [], "n": 0}
                tests.append(t)
                by_id[row.get("test")] = t
            t["n"] += 1
            if not row.get("ok") and not row.get("todo"):
                text = "not ok %s %s\n  operator: %s\n  expected: %s\n  actual:   %s\n  at: %s\n  stack: %s" % (
                    row.get("id"), row.get("name"), row.get("operator"), row.get("expected"), row.get("actual"),
                    row.get("at"), row.get("stack"))
                t["fail"].append(text.replace(cwd, ""))
    return p.returncode, tests, p.stdout.replace(cwd, ""), p.stderr.replace(cwd, "")


def main(argv):
    if not argv:
        print("usage: tape-junit.py <report.xml> [test files…]", file=sys.stderr)
        return 2
    report, files = argv[0], files_of(argv[1:])
    suite = ET.Element("testsuite", name="tape")
    n = f = 0
    for path in files:
        rc, tests, out, err = run_file(path)
        cn = path.replace("/", ".")
        bad_any = False
        for t in tests:
            c = ET.SubElement(suite, "testcase", classname=cn, name=t["name"])
            n += 1
            if t["fail"]:
                bad_any = True
                f += 1
                ET.SubElement(c, "failure", message=t["fail"][0].split("\n", 1)[0]).text = "\n".join(t["fail"])
        if rc != 0 and not bad_any:
            c = ET.SubElement(suite, "testcase", classname="", name=path)
            ET.SubElement(c, "error", message="%s exited %d" % (path, rc)).text = (err + "\n" + out).strip()
            n += 1
            f += 1
    suite.set("tests", str(n))
    suite.set("failures", str(f))
    root = ET.Element("testsuites")
    root.append(suite)
    ET.ElementTree(root).write(report, encoding="utf-8", xml_declaration=True)
    print("tape-junit: %d files, %d cases, %d failed -> %s" % (len(files), n, f, report))
    return 1 if f else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
