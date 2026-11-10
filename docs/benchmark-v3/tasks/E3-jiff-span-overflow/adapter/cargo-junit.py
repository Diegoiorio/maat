#!/usr/bin/env python3
"""cargo-junit.py — format adapter of the benchmark (v3): runs `cargo test` and writes a JUnit report that Maat 1.7.0
reads (report "junit"). Not part of the project: on the Maat side it is installed in .claude/bench/ (excluded from the
final diff); the baseline side does not use it.

    python3 .claude/bench/cargo-junit.py <report.xml> [cargo test arguments…]      (from the project root; CARGO = cargo)

Runs `cargo test --no-fail-fast <arguments>` and reads its plain output (libtest has no stable machine format). Each
test and doc test is one <testcase>: classname = the path of the file that declares it, relative to the current folder,
with "/" written as "." (the form Maat matches with the plan's `file::name`); name = the name libtest prints
(`module::test_name`; for a doc test, what follows the path). A failure keeps the test's output, where the panic gives
the position as `path/to/file.rs:LINE:COL`, so Maat finds the line of the red. A build that fails gives one case with no
classname, named after each file its errors point to (or `cargo build`): Maat reads it as the whole file being red. When
a test binary dies (a stack overflow, a signal), every test with no result runs again alone, so that the death costs only
the test that causes it; a test that dies alone is a failed case with the runtime's message and the position of its
declaration (`file.rs:LINE`). If the binary cannot be run again, every test declared in its files is a failed case «did not
run», never a missing one; if none can be listed, one failed case carries the name of the binary. Exit status:
0 when `cargo test` passes, otherwise 1, the status Maat reads as «tests failed» (cargo itself gives 101).
"""

import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor

CARGO = os.environ.get("CARGO", "cargo")
RUNNING = re.compile(r"^\s*Running (?:unittests )?(\S+)(?: \((\S+)\))?\s*$")
DOCTESTS = re.compile(r"^\s*Doc-tests (\S+)\s*$")
RESULT = re.compile(r"^test (.+?)(?: - should panic)? \.\.\. (ok|FAILED|ignored.*)$")
BLOCK = re.compile(r"^---- (.+?) std(?:out|err) ----$")
SUMMARY = re.compile(r"^test result: ")
DOC_NAME = re.compile(r"^(\S+\.rs) - (.+)$")
ERROR_AT = re.compile(r"^\s*--> ([^:\s]+\.rs):[0-9]+:[0-9]+")
# what cannot appear in XML 1.0, and the colours of a terminal
BAD_XML = re.compile("[^\t\n\r\x20-퟿-�\U00010000-\U0010FFFF]")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
MOD_LINE = re.compile(r"^\s*(?:pub(?:\([^)]*\))?\s+)?mod\s+(\w+)\s*(;|\{)")
TEST_ATTR = re.compile(r"^\s*#\[(?:[\w:]+::)?test(?:\(.*\))?\]")
FN_LINE = re.compile(r"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:const\s+)?(?:unsafe\s+)?fn\s+(\w+)")


def rel(path):
    return os.path.relpath(path, os.getcwd()).replace(os.sep, "/")


def clean(text):
    return BAD_XML.sub("?", ANSI.sub("", text))


def packages():
    """[(package folder, [target])] of the workspace; [] if cargo metadata cannot tell."""
    p = subprocess.run([CARGO, "metadata", "--no-deps", "--offline", "--format-version", "1"],
                       capture_output=True, text=True)
    try:
        meta = json.loads(p.stdout)
    except ValueError:
        return []
    return [(os.path.dirname(x["manifest_path"]), x.get("targets") or []) for x in meta.get("packages") or []]


class Source:
    """The modules and the #[test] functions reachable from a crate's root file, read as text. Tests made by macros
    are not listed; their module still gives their file."""

    def __init__(self, root):
        self.modules = {"": root}
        self.tests = {}
        self.lines = {}
        self.seen = set()
        self.read(root, [], os.path.dirname(root))

    def read(self, path, prefix, folder):
        if path in self.seen:
            return
        self.seen.add(path)
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                lines = fh.read().splitlines()
        except OSError:
            return
        stack = []     # (depth at which the inline module closes, name)
        depth = 0
        pending = False
        for number, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            m = MOD_LINE.match(code)
            names = prefix + [s[1] for s in stack]
            if m and m.group(2) == ";":
                sub = names + [m.group(1)]
                inner = os.path.join(folder, *[s[1] for s in stack])
                for cand, next_folder in ((os.path.join(inner, m.group(1) + ".rs"), os.path.join(inner, m.group(1))),
                                          (os.path.join(inner, m.group(1), "mod.rs"), os.path.join(inner, m.group(1)))):
                    if os.path.isfile(cand):
                        self.modules["::".join(sub)] = cand
                        self.read(cand, sub, next_folder)
                        break
            if TEST_ATTR.match(code):
                pending = True
            else:
                f = FN_LINE.match(code)
                if f and pending:
                    self.tests["::".join(names + [f.group(1)])] = path
                    self.lines["::".join(names + [f.group(1)])] = number
                    pending = False
            opens, closes = code.count("{"), code.count("}")
            if m and m.group(2) == "{":
                stack.append((depth + 1, m.group(1)))
                self.modules["::".join(names + [m.group(1)])] = path
            depth += opens - closes
            while stack and depth < stack[-1][0]:
                stack.pop()

    def file_of(self, name):
        if name in self.tests:
            return self.tests[name]
        parts = name.split("::")[:-1]
        while parts:
            f = self.modules.get("::".join(parts))
            if f:
                return f
            parts.pop()
        return self.modules[""]


def find_source(pkgs, shown, binary, cache):
    """the crate of a `Running <file> (<binary>)` line: its root file and folder"""
    stem = os.path.basename(binary or "").rsplit("-", 1)[0]
    same_file = [t for _, targets in pkgs for t in targets
                 if (t.get("src_path") or "").endswith("/" + shown.lstrip("./"))]
    same_name = [t for t in same_file if t.get("name", "").replace("-", "_") == stem]
    hit = (same_name or same_file or [{}])[0].get("src_path")
    if hit is None and os.path.isfile(shown):
        hit = os.path.abspath(shown)
    if hit is None:
        return None
    if hit not in cache:
        cache[hit] = Source(hit)
    return cache[hit]


def isolate(binary, root, pkgs, skip):
    """[(name, result, output, died)] of the tests of a dead binary that have no result, each in its own process, from
    the folder cargo runs it in; None if the binary cannot be run."""
    exe = os.path.abspath(binary)
    cwd = max((f for f, _ in pkgs if root.startswith(f + "/")), key=len, default=os.getcwd())
    env = dict(os.environ, RUST_BACKTRACE="0", CARGO_MANIFEST_DIR=cwd)
    run = dict(cwd=cwd, env=env, text=True, errors="replace", stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        listed = subprocess.run([exe, "--list", "--format", "terse"], timeout=120, **run)
    except (OSError, subprocess.SubprocessError):
        return None
    names = [x[:-6] for x in listed.stdout.splitlines() if x.endswith(": test") and x[:-6] not in skip]
    if listed.returncode:
        return None

    def one(name):
        try:
            r = subprocess.run([exe, "--exact", name], timeout=600, **run)
        except subprocess.TimeoutExpired:
            return name, "FAILED", "the test did not end in 600 s", True
        text = clean(r.stdout)
        got = next((m.group(2) for m in map(RESULT.match, text.split("\n")) if m), None)
        if r.returncode == 0:
            return name, got or "ok", "", False
        return name, "FAILED", text.strip(), got is None

    with ThreadPoolExecutor(8) as pool:
        return list(pool.map(one, names))


def main(argv):
    if not argv:
        print("usage: cargo-junit.py <report.xml> [cargo test arguments]", file=sys.stderr)
        return 2
    report = argv[0]
    env = dict(os.environ, CARGO_TERM_COLOR="never", RUST_BACKTRACE="0")
    p = subprocess.run([CARGO, "test", "--no-fail-fast"] + argv[1:], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, errors="replace", env=env)
    lines = clean(p.stdout).split("\n")
    pkgs = packages()
    cache = {}

    runs = []   # one per test binary or per doc-test group
    cur = None
    block = None
    built = False
    errors, in_error = [], False
    for line in lines:
        m = RUNNING.match(line)
        d = DOCTESTS.match(line) if not m else None
        if m or d:
            built = True
            cur = {"shown": m.group(1) if m else None, "binary": m.group(2) if m else None, "doc": bool(d),
                   "results": [], "text": {}, "output": [], "done": False}
            runs.append(cur)
            block = None
            continue
        if not built:
            if line.startswith("error"):
                in_error = True
            elif not line.strip():
                in_error = False
            if in_error or line.startswith("error"):
                errors.append(line)
            continue
        if cur is None:
            continue
        cur["output"].append(line)
        if SUMMARY.match(line):
            cur["done"] = True
            block = None
            continue
        b = BLOCK.match(line)
        if b:
            block = b.group(1)
            cur["text"].setdefault(block, [])
            continue
        if line == "failures:":
            block = None
            continue
        r = RESULT.match(line)
        if r:
            cur["results"].append((r.group(1), r.group(2)))
            continue
        if block is not None:
            cur["text"][block].append(line)

    suite = ET.Element("testsuite", name="cargo test")
    n = f = 0

    def case(cn, name, kind=None, msg="", text=""):
        nonlocal n, f
        c = ET.SubElement(suite, "testcase", classname=cn, name=name)
        n += 1
        if kind in ("failure", "error"):
            f += 1
            ET.SubElement(c, kind, message=msg).text = text
        elif kind == "skipped":
            ET.SubElement(c, "skipped")

    for run in runs:
        src = None if run["doc"] else find_source(pkgs, run["shown"], run["binary"], cache)
        fallback = rel(src.modules[""]) if src else (run["shown"] or "doc-tests")
        named = set()

        def emit(name, res, text):
            named.add(name)
            if run["doc"]:
                dn = DOC_NAME.match(name)
                file, shown = (dn.group(1), dn.group(2)) if dn else (fallback, name)
                if dn and not os.path.isfile(file):
                    for folder, _ in pkgs:
                        if os.path.isfile(os.path.join(folder, file)):
                            file = rel(os.path.join(folder, file))
                            break
            else:
                file = rel(src.file_of(name)) if src else fallback
                shown = name
            cn = file.replace("/", ".")
            if res == "ok":
                case(cn, shown)
            elif res == "FAILED":
                case(cn, shown, "failure", "FAIL: " + name, text)
            else:
                case(cn, shown, "skipped")

        for name, res in run["results"]:
            emit(name, res, "\n".join(run["text"].get(name, [])).strip())
        if run["done"]:
            continue
        # the binary died before its summary: each test with no result runs alone, so that the death costs only the
        # test that causes it
        tail = "\n".join(run["output"][-30:]).strip()
        again = isolate(run["binary"], src.modules[""], pkgs, named) if src and run["binary"] else None
        if again is not None:
            for name, res, text, died in again:
                if died and name in src.tests:
                    text += "\ndeclared at %s:%d" % (rel(src.tests[name]), src.lines[name])
                emit(name, res, "the test binary died, and this test was run again alone\n" + text)
            if again:
                continue
        missing = [t for t in (src.tests if src else {}) if t not in named]
        for t in missing:
            case(rel(src.tests[t]).replace("/", "."), t, "failure", "did not run: " + t,
                 "the test binary ended before this test had a result\n" + tail)
        if not missing:
            case(fallback.replace("/", "."), "(test binary)", "failure", "the test binary died: " + fallback, tail)

    if p.returncode and not runs:
        text = "\n".join(errors or lines[-40:]).strip()
        files = sorted({m.group(1) for m in map(ERROR_AT.match, errors) if m})
        for name in files or ["cargo build"]:
            case("", rel(name) if os.path.exists(name) else name, "error", "the build failed", text)
    elif p.returncode and f == 0:
        case("", "cargo test", "error", "cargo test failed with no failed test", "\n".join(lines[-40:]).strip())

    suite.set("tests", str(n))
    suite.set("failures", str(f))
    root = ET.Element("testsuites")
    root.append(suite)
    ET.ElementTree(root).write(report, encoding="utf-8", xml_declaration=True)
    print("cargo-junit: %d cases, %d failed, cargo test exit %d -> %s" % (n, f, p.returncode, report))
    return 1 if p.returncode else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
