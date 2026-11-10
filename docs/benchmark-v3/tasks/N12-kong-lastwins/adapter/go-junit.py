#!/usr/bin/env python3
"""go-junit.py — format adapter of the benchmark: runs `go test -json` and writes a JUnit report that Maat 1.7.0 reads
(report "junit"). Not part of the project: on the Maat side it is installed in .claude/bench/ (excluded from the final
diff); the baseline side does not use it. The same file serves every Go task of the benchmark.

    python3 .claude/bench/go-junit.py <report.xml> [ignored…]      (from the module root; GO = go binary, default go)

Runs every package (`go test -count=1 -json ./...`), like the project's own `go test ./...`; packages with no tests give
no case. If a file `go-junit.skip` lies next to this script, its lines (blank lines and `#` comments left out) are the
tests the task's spec declares as not counted: they are joined with `|` and passed as `go test -skip`, and they are
never reported as «did not run». Each test, subtest, example and fuzz test is one <testcase>: classname = the path of
the `_test.go` file that declares its top-level function, relative to the module root, with "/" written as "." (the
form Maat matches with the plan's `file::name`); name = the name Go prints (`TestX/sub`). A failure keeps the test's
output, with every `xxx_test.go:NN` position (also `./xxx_test.go:NN:CC` of the compiler) written as its path from the
module root, so Maat finds the line of the red. A package that does not build (or fails outside any test) gives one
case with no classname, named after each test file its output names (or the package folder): Maat reads it as the
whole file being red. When a package fails (a panic, a crash, a timeout), every test declared in its files that has
no result is a failed case «did not run», never a missing one; an example with no output comment is not counted,
because `go test` only compiles it, and neither is a test in a file that `go test` leaves out on this system (a
`_windows_test.go` file, a build constraint). Characters that XML 1.0 cannot hold are replaced by U+FFFD.
Exit status: the one of `go test`.
"""

import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

GO = os.environ.get("GO", "go")
FUNC = re.compile(r"^func\s+((?:Test|Example|Fuzz)\w*)\s*\(", re.M)
POS = re.compile(r"(?<![\w/.-])(?:\./)?((?:[\w.-]+/)*[\w.-]+_test\.go):([0-9]+)")
OUTPUT = re.compile(r"//\s*(?:unordered )?output:", re.I)
NOT_XML = re.compile("[^\t\n\r\x20-퟿-�\U00010000-\U0010ffff]")


def skip_pattern():
    """the `go test -skip` pattern of go-junit.skip, next to this script; "" = none"""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "go-junit.skip")
    try:
        with open(path, encoding="utf-8") as fh:
            lines = [l.strip() for l in fh]
    except OSError:
        return ""
    return "|".join(l for l in lines if l and not l.startswith("#"))


SKIP = skip_pattern()
SKIP_RE = re.compile(SKIP) if SKIP else None


def skipped(name):
    return SKIP_RE is not None and SKIP_RE.search(name) is not None


def xml_text(s):
    return NOT_XML.sub("�", s)


COMPILED = {}   # {folder: the test files go compiles there}; none known for a folder = no filter


def rel(path):
    return os.path.relpath(path, os.getcwd()).replace(os.sep, "/")


def packages():
    """{import path: folder relative to the module root}"""
    fmt = '{{.ImportPath}}\t{{.Dir}}\t{{join .TestGoFiles ","}},{{join .XTestGoFiles ","}}'
    p = subprocess.run([GO, "list", "-e", "-f", fmt, "./..."], capture_output=True, text=True)
    out = {}
    for line in p.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) == 3:
            out[parts[0]] = rel(parts[1])
            COMPILED[rel(parts[1])] = {f for f in parts[2].split(",") if f}
    return out


def in_folder(folder, name):
    return name if folder in ("", ".") else folder + "/" + name


def test_files(folder):
    """{TestX: path of the _test.go file that declares it}, in the order of the files and of the declarations"""
    decl = {}
    try:
        names = sorted(os.listdir(folder or "."))
    except OSError:
        return decl
    for f in names:
        if not f.endswith("_test.go") or (COMPILED.get(folder) and f not in COMPILED[folder]):
            continue
        path = in_folder(folder, f)
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                src = fh.read()
        except OSError:
            continue
        for m in FUNC.finditer(src):
            if m.group(1).startswith("Example") and not OUTPUT.search(src, m.end(), body_end(src, m.end())):
                continue   # go test compiles an example with no output comment and never runs it
            decl.setdefault(m.group(1), path)
    return decl


def body_end(src, start):
    end = src.find("\n}", start)
    return len(src) if end < 0 else end


def fix_positions(text, folder):
    """`./bytes_test.go:12:3` or `bytes_test.go:12` -> `<folder>/bytes_test.go:12…` (Go prints base names)."""
    def one(m):
        f = m.group(1)
        if "/" not in f:
            f = in_folder(folder, f)
        return "%s:%s" % (f, m.group(2))
    return POS.sub(one, text)


def main(argv):
    if not argv:
        print("usage: go-junit.py <report.xml>", file=sys.stderr)
        return 2
    report = argv[0]
    pk = packages()
    cmd = [GO, "test", "-count=1"] + (["-skip", SKIP] if SKIP else []) + ["-json", "./..."]
    p = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    tests, order, pkg_out, pkg_fail = {}, [], {}, set()
    loose = []
    for line in p.stdout.splitlines():
        try:
            ev = json.loads(line)
        except ValueError:
            loose.append(line + "\n")
            continue
        ip = (ev.get("Package") or ev.get("ImportPath") or "").split(" ")[0]   # "pkg [pkg.test]" of build events
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
        elif act in ("output", "build-output"):
            pkg_out.setdefault(ip, []).append(ev.get("Output", ""))
        elif act in ("fail", "build-fail"):
            pkg_fail.add(ip)
    extra = "".join(loose) + (p.stderr or "")
    decls = {}

    def decl(folder):
        if folder not in decls:
            decls[folder] = test_files(folder)
        return decls[folder]

    suite = ET.Element("testsuite", name="go test")
    n = f = 0

    def case(cn, name, kind=None, msg="", text=""):
        nonlocal n, f
        c = ET.SubElement(suite, "testcase", classname=cn, name=xml_text(name))
        n += 1
        if kind in ("failure", "error"):
            f += 1
            ET.SubElement(c, kind, message=xml_text(msg)).text = xml_text(text)
        elif kind == "skipped":
            ET.SubElement(c, "skipped")

    ran = {}
    for ip, t in order:
        folder = pk.get(ip, ".")
        top = t.split("/", 1)[0]
        file = decl(folder).get(top, in_folder(folder, "unknown_test.go"))
        r = tests[(ip, t)]
        ran.setdefault(ip, set()).add(top)
        text = fix_positions("".join(r["out"]), folder)
        if r["res"] == "pass":
            case(file.replace("/", "."), t)
        elif r["res"] == "skip":
            case(file.replace("/", "."), t, "skipped")
        elif r["res"] == "fail":
            case(file.replace("/", "."), t, "failure", "FAIL: " + t, text)
        else:
            case(file.replace("/", "."), t, "failure", "no result: " + t, text + "\n(the test started and did not end)")
    for ip in sorted(pkg_fail | ({""} if p.returncode and not tests and extra.strip() else set())):
        folder = pk.get(ip, ".")
        text = fix_positions("".join(pkg_out.get(ip, [])) + (extra if ip in ("", next(iter(sorted(pkg_fail)), "")) else ""), folder)
        if ip in ran:
            # a panic, a crash or a timeout: the tests of the package that never ran are failed, not missing
            for name, file in decl(folder).items():
                if name not in ran[ip] and not skipped(name):
                    case(file.replace("/", "."), name, "failure", "did not run: " + name,
                         "the package failed before this test ran\n" + text)
            continue
        named = sorted({m.group(1) if "/" in m.group(1) else in_folder(folder, m.group(1)) for m in POS.finditer(text)})
        for name in named or [folder]:
            case("", name, "error", "package %s failed" % (ip or "?"), text)
    suite.set("tests", str(n))
    suite.set("failures", str(f))
    root = ET.Element("testsuites")
    root.append(suite)
    ET.ElementTree(root).write(report, encoding="utf-8", xml_declaration=True)
    print("go-junit: %d cases, %d failed, go test exit %d -> %s" % (n, f, p.returncode, report))
    return p.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
