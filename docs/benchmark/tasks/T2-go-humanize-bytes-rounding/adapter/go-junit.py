#!/usr/bin/env python3
"""go-junit.py — format adapter of the benchmark (T2): runs `go test -json` and writes a JUnit report that Maat
1.6.0 reads (report "junit"). Not part of the project: on the Maat side it is installed in .claude/bench/ (excluded
from the final diff); the baseline side does not use it.

    python3 .claude/bench/go-junit.py <report.xml> [ignored…]      (from the module root; GO = go binary, default go)

Runs every package (`go test -count=1 -json ./...`), like the project's own `go test ./...`. Each test and subtest
is one <testcase>: classname = the path of the `_test.go` file that declares its top-level `func TestX`, relative
to the module root, with "/" written as "." (the form Maat matches with the plan's `file::name`); name = the test
name as Go prints it (`TestX/sub`). A failure keeps the test's output, with every `xxx_test.go:NN:` position
written as its path from the module root, so Maat finds the line of the red. A package that does not build (or
fails outside any test) gives one case with no classname, named after each test file its output names (or the
package folder): Maat reads it as the whole file being red. Exit status: the one of `go test`.
"""

import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

GO = os.environ.get("GO", "go")
FUNC = re.compile(r"^func\s+(Test\w*)\s*\(", re.M)
POS = re.compile(r"(?<![\w./-])([\w.-]+_test\.go):([0-9]+)")


def rel(path):
    r = os.path.relpath(path, os.getcwd()).replace(os.sep, "/")
    return r


def packages():
    """{import path: folder relative to the module root}"""
    p = subprocess.run([GO, "list", "-f", "{{.ImportPath}}\t{{.Dir}}", "./..."], capture_output=True, text=True)
    out = {}
    for line in p.stdout.splitlines():
        if "\t" in line:
            ip, d = line.split("\t", 1)
            out[ip] = rel(d)
    return out


def test_files(folder):
    """{TestX: relative path of the _test.go file that declares it}, [test files of the folder]"""
    decl, files = {}, []
    for f in sorted(os.listdir(folder or ".")):
        if not f.endswith("_test.go"):
            continue
        path = f if folder in ("", ".") else folder + "/" + f
        files.append(path)
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                for name in FUNC.findall(fh.read()):
                    decl.setdefault(name, path)
        except OSError:
            pass
    return decl, files


def fix_positions(text, folder):
    """`bytes_test.go:12` -> `<folder>/bytes_test.go:12` (Go prints the base name only)."""
    if folder in ("", "."):
        return text
    return POS.sub(lambda m: "%s/%s:%s" % (folder, m.group(1), m.group(2))
                   if "/" not in m.group(1) else m.group(0), text)


def main(argv):
    if not argv:
        print("usage: go-junit.py <report.xml>", file=sys.stderr)
        return 2
    report = argv[0]
    pk = packages()
    p = subprocess.run([GO, "test", "-count=1", "-json", "./..."], capture_output=True, text=True)
    tests, order, pkg_out, pkg_fail = {}, [], {}, {}
    for line in p.stdout.splitlines():
        try:
            ev = json.loads(line)
        except ValueError:
            pkg_out.setdefault("", []).append(line + "\n")
            continue
        ip = ev.get("Package") or ev.get("ImportPath") or ""
        ip = ip.split(" ")[0]          # "pkg [pkg.test]" of build events
        act, t = ev.get("Action"), ev.get("Test")
        if t:
            k = (ip, t)
            if k not in tests:
                tests[k] = {"out": [], "res": None}
                order.append(k)
            if act == "output":
                tests[k]["out"].append(ev.get("Output", ""))
            elif act in ("pass", "fail", "skip"):
                tests[k]["res"] = act
        else:
            if act in ("output", "build-output"):
                pkg_out.setdefault(ip, []).append(ev.get("Output", ""))
            elif act in ("fail", "build-fail"):
                pkg_fail[ip] = True
    if p.stderr:
        pkg_out.setdefault("", []).append(p.stderr)
    suite = ET.Element("testsuite", name="go test")
    n = f = 0
    decls = {}
    for ip, t in order:
        folder = pk.get(ip, ".")
        if folder not in decls:
            decls[folder] = test_files(folder)
        top = t.split("/", 1)[0]
        file = decls[folder][0].get(top, (folder + "/" if folder not in ("", ".") else "") + "unknown_test.go")
        r = tests[(ip, t)]
        c = ET.SubElement(suite, "testcase", classname=file.replace("/", "."), name=t)
        n += 1
        if r["res"] == "fail" or r["res"] is None:
            f += 1
            text = fix_positions("".join(r["out"]), folder)
            ET.SubElement(c, "failure", message="FAIL: " + t if r["res"] else "no result: " + t).text = text
        elif r["res"] == "skip":
            ET.SubElement(c, "skipped")
    failed_tests = {ip for (ip, t), r in tests.items() if r["res"] != "pass" and r["res"] != "skip"}
    for ip in sorted(set(pkg_fail) | ({""} if "" in pkg_out and p.returncode and not failed_tests else set())):
        if ip in failed_tests:
            continue
        folder = pk.get(ip, ".")
        text = "".join(pkg_out.get(ip, []) + (pkg_out.get("", []) if ip != "" else []))
        if folder not in decls:
            decls[folder] = test_files(folder)
        text = fix_positions(text, folder)
        named = sorted({m.group(1) if "/" in m.group(1) or folder in ("", ".") else folder + "/" + m.group(1)
                        for m in POS.finditer(text)})
        for name in named or [folder]:
            c = ET.SubElement(suite, "testcase", classname="", name=name)
            ET.SubElement(c, "error", message="package %s failed" % (ip or "?")).text = text
            n += 1
            f += 1
    suite.set("tests", str(n))
    suite.set("failures", str(f))
    root = ET.Element("testsuites")
    root.append(suite)
    ET.ElementTree(root).write(report, encoding="utf-8", xml_declaration=True)
    sys.stdout.write(p.stdout if os.environ.get("GO_JUNIT_VERBOSE") else "")
    print("go-junit: %d cases, %d failed, go test exit %d -> %s" % (n, f, p.returncode, report))
    return p.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
