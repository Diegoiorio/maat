#!/usr/bin/env python3
"""tape-junit.py — format adapter of the benchmark (T3): runs tape one test file at a time and writes a JUnit report
that Maat 1.6.0 reads (report "junit"). Not part of the project: on the Maat side it is installed in .claude/bench/
(excluded from the final diff); the baseline side does not use it.

    python3 .claude/bench/tape-junit.py <report.xml> [test files…]     (from the package root; NODE = node binary)

With no file it runs every `test/**/*.js`, as the project's `npx tape 'test/**/*.js'`. Each file runs on its own
(`node node_modules/tape/bin/tape <file>`) and its TAP output is read: each `test('name', …)` is one <testcase>,
classname = the file path with "/" written as "." (the form Maat matches with the plan's `file::name`), name = the
test name. A test fails when one of its assertions is `not ok`; the failure keeps the `not ok` line and its YAML
block (operator, expected, actual, `at: … (file:line:col)`), with absolute paths written from the package root, so
Maat finds the line of the red. A file that does not load, or exits non-zero with no failed assertion, gives one
case with no classname named after the file: Maat reads it as the whole file being red. Exit status: 1 if
anything failed, else 0.
"""

import glob
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

NODE = os.environ.get("NODE", "node")
TAPE = os.path.join("node_modules", "tape", "bin", "tape")
OK = re.compile(r"^(not ok|ok) [0-9]+")


def files_of(argv):
    if argv:
        return [a.replace("\\", "/") for a in argv]
    return sorted(f.replace("\\", "/") for f in glob.glob("test/**/*.js", recursive=True))


def run_file(path):
    p = subprocess.run([NODE, TAPE, path], capture_output=True, text=True)
    cwd = os.getcwd().replace("\\", "/").rstrip("/") + "/"
    out = p.stdout.replace(cwd, "")
    err = p.stderr.replace(cwd, "")
    tests, cur, block = [], None, None
    for line in out.splitlines():
        if line.startswith("# ") and not re.match(r"^# (tests|pass|fail|ok)\b", line):
            cur = {"name": line[2:], "fail": [], "n": 0}
            tests.append(cur)
            block = None
            continue
        m = OK.match(line)
        if m:
            if cur is None:
                cur = {"name": "(no test name)", "fail": [], "n": 0}
                tests.append(cur)
            cur["n"] += 1
            block = [line] if m.group(1) == "not ok" else None
            if block is not None:
                cur["fail"].append(block)
            continue
        if block is not None and line.startswith("  "):
            block.append(line)
    return p.returncode, tests, out, err


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
                text = "\n".join("\n".join(b) for b in t["fail"])
                ET.SubElement(c, "failure", message=t["fail"][0][0]).text = text
        if rc != 0 and not bad_any:
            c = ET.SubElement(suite, "testcase", classname="", name=path)
            ET.SubElement(c, "error", message="%s exited %d" % (path, rc)).text = (out + "\n" + err).strip()
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
