#!/usr/bin/env python3
"""bats-junit.py — format adapter of the benchmark (N9): runs the project's bats suite and writes a JUnit report that Maat
1.7.0 reads (report "junit"). Not part of the project: on the Maat side it is installed in .claude/bench/ (excluded from the
final diff); the baseline side does not use it.

    python3 .claude/bench/bats-junit.py <report.xml> [ignored…]      (from the repository root; BATS_JOBS = parallel jobs, default 8)

Runs every folder of tests: `test` and each `plugins/*/test` holding `.bats` files, each with `bats -F junit`. The formatter of
bats names a file by its base name only, so each folder is a run of its own and the path is put back here. Each @test is one
<testcase>: classname = the path of the `.bats` file from the repository root, with "/" written as "." (the form Maat matches
with the plan's `file::name`); name = the name bats prints. A failure keeps the text of bats, and each «in test file x.bats, line
N» of it is also written as `<path>:N`, so Maat finds the line of the red. A file that gives no result (it does not load, the
run crashed or timed out) is one case with no classname, named after the file: Maat reads it as the whole file being red. Exit
status: 0 when every case passed, 1 when one failed, 2 when bats could not run at all or found no test.
"""

import glob
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

BATS = os.environ.get("BATS", "bats")
JOBS = os.environ.get("BATS_JOBS", "8")
TIMEOUT = int(os.environ.get("BATS_TIMEOUT", "1800"))
POS = re.compile(r"in test file (\S+?), line ([0-9]+)")


def folders():
    out = []
    for d in ["test"] + sorted(glob.glob("plugins/*/test")):
        if glob.glob(d + "/*.bats"):
            out.append(d)
    return out


def positions(text, folder):
    """Appends `<path>:N` to each «in test file x.bats, line N»; bats prints the path it was given, or a base name."""
    def one(m):
        f = m.group(1)
        if "/" not in f:
            f = folder + "/" + f
        return "%s %s:%s" % (m.group(0), f, m.group(2))
    return POS.sub(one, text)


def run(files):
    """(xml text, stderr, exit status, files) of some files; they are named one by one so that the paths stay relative."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("PYENV_")}
    try:
        p = subprocess.run([BATS, "-j", JOBS, "-F", "junit"] + files, capture_output=True, text=True, errors="replace",
                           env=env, timeout=TIMEOUT, stdin=subprocess.DEVNULL)
        return p.stdout, p.stderr, p.returncode, files
    except subprocess.TimeoutExpired as e:
        return (e.stdout or b"").decode("utf-8", "replace"), "bats: timeout after %d s\n" % TIMEOUT, 124, files
    except OSError as e:
        return "", "bats: %s\n" % e, 127, files


def main(argv):
    if not argv:
        print("usage: bats-junit.py <report.xml>", file=sys.stderr)
        return 2
    report = argv[0]
    suite = ET.Element("testsuite", name="bats")
    n = f = sk = 0
    worst = 0

    def case(cn, name, kind=None, msg="", text=""):
        nonlocal n, f, sk
        c = ET.SubElement(suite, "testcase", classname=cn, name=name)
        n += 1
        if kind in ("failure", "error"):
            f += 1
            ET.SubElement(c, kind, message=msg).text = text
        elif kind == "skipped":
            sk += 1
            ET.SubElement(c, "skipped")

    def read(folder, files, last_try):
        """The cases of one run of `files`. Returns the files with no result when that may be the fault of another file."""
        nonlocal worst
        xml, err, rc, files = run(files)
        worst = max(worst, rc)
        try:
            root = ET.fromstring(xml[xml.index("<?xml"):] if "<?xml" in xml else xml)
        except (ET.ParseError, ValueError):
            root = None
        seen = set()
        for s in ([] if root is None else root.iter("testsuite")):
            path = folder + "/" + (s.get("name") or "")
            seen.add(path)
            cn = path.replace("/", ".")
            for c in s.iter("testcase"):
                name = c.get("name") or ""
                bad = [e for e in c if e.tag in ("failure", "error")]
                if bad:
                    text = "\n".join(((e.get("message") or "") + "\n" + (e.text or "")) for e in bad)
                    case(cn, name, "failure", "FAIL: " + name, positions(text, folder))
                elif any(e.tag == "skipped" for e in c):
                    case(cn, name, "skipped")
                else:
                    case(cn, name)
        if err.strip():
            sys.stderr.write(err)
        # no result for a file: empty files are fine, the others did not load or never ran
        missing = [p for p in files if p not in seen and rc != 0 and has_tests(p)]
        if last_try:
            for path in missing:
                case("", path, "error", "no result for " + path, (xml[-2000:] + "\n" + err[-4000:]).strip())
            return []
        return missing

    for folder in folders():
        # one file that does not load stops bats for all the files of the run: those are run again one at a time
        for path in read(folder, sorted(glob.glob(folder + "/*.bats")), False):
            read(folder, [path], True)
    suite.set("tests", str(n))
    suite.set("failures", str(f))
    suite.set("errors", "0")
    suite.set("skipped", str(sk))
    root = ET.Element("testsuites")
    root.append(suite)
    if n:
        ET.ElementTree(root).write(report, encoding="utf-8", xml_declaration=True)
    print("bats-junit: %d cases, %d failed, %d skipped, bats exit %d -> %s" % (n, f, sk, worst, report))
    if not n:
        return 2
    return 1 if f else 0


def has_tests(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return "@test" in fh.read()
    except OSError:
        return False


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
