#!/usr/bin/env python3
"""compila_record.py — fills `record.json` of one published run from its raw files, field by field as the table of
`../run-record.md` says (written after the freeze, with the first group; it decides nothing the table does not).

    python3 compila_record.py <records/<run-id>> <base snapshot commit>

Reads, next to it: `../schedule.tsv` (run_id, task, side, order), `../SHA256SUMS` (the frozen spec) and the task
table of `../run-bench.sh` (upstream repository and commit). The base snapshot commit is `.git/bench-base` of the
run's copy, which is not published: it is given on the command line. The blind review and the adjudication fields
stay null until all 30 runs are done. Standard library only; the same files give the same bytes.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = os.path.dirname(HERE)


def read(d, name):
    p = os.path.join(d, name)
    if not os.path.isfile(p):
        return None
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()


def first(s):
    return s.split()[0] if s and s.split() else ""


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    d, base = sys.argv[1].rstrip("/"), sys.argv[2]
    rid = os.path.basename(d)
    sched = {}
    for line in open(os.path.join(BENCH, "schedule.tsv"), encoding="utf-8").read().splitlines()[1:]:
        o, r, t, s = line.split("\t")
        sched[r] = (int(o), t, s)
    order, task, side = sched[rid]
    rb = open(os.path.join(BENCH, "run-bench.sh"), encoding="utf-8").read()
    m = re.search(r"^\s*%s\) echo \"(\S+) (\S+) (\S+) (\d+)\"" % task, rb, re.M)
    repo, commit, spec_rel, total = m.group(1), m.group(2), m.group(3), int(m.group(4))
    sums = {}
    for line in open(os.path.join(BENCH, "SHA256SUMS"), encoding="utf-8").read().splitlines():
        if line.strip():
            h, p = line.split(None, 1)
            sums[p.strip().lstrip("*")] = h
    env = {}
    for line in (read(d, "environment.txt") or "").splitlines():
        if ": " in line:
            k, v = line.split(": ", 1)
            env[k] = v.strip()
    exit_code = int((read(d, "exit_code") or "").strip() or -1)
    notes = [l for l in (read(d, "notes.txt") or "").splitlines() if l.strip()]
    rec = {
        "run_id": rid, "task": task, "side": side, "order": order,
        "spec_sha256": sums.get("tasks/" + spec_rel, ""),
        "spec_sha256_in_copy": first(read(d, "spec-in-copy.sha256")),
        "upstream_repo": repo, "upstream_commit": commit, "base_snapshot_commit": base,
        "maat_tag": env.get("maat_tag", ""), "claude_code_version": env.get("claude_code", ""),
        "model": env.get("model", ""), "model_check": (read(d, "model-check.txt") or "").strip() or None,
        "os": env.get("os", ""),
        "started_utc": (read(d, "started_utc") or "").strip(), "ended_utc": (read(d, "ended_utc") or "").strip(),
        "wall_clock_s": int((read(d, "wall_clock_s") or "").strip() or 0) or None,
        "exit_code": exit_code, "timed_out": exit_code in (124, 137),
        "outcome": "", "outcome_detail": "",
        "quota": not (read(d, "quota.txt") or "").startswith("quota: none"),
        "contaminated": not (read(d, "audit.txt") or "").startswith("audit: clean"),
        "human_interventions": [],
        "cost_usd_api_equivalent": None, "cost_breakdown": {},
        "final_diff": "records/%s/final.diff" % rid, "final_diff_sha256": first(read(d, "final.diff.sha256")),
        "report": "", "hidden_tests": None,
        "blind_review_code": None, "blind_review_entries": None, "confirmed_defects": None,
        "undisclosed_defects": None, "notes": notes,
    }
    # outcome (run-record.md, «Outcome»)
    if rec["timed_out"]:
        rec["outcome"] = "TIMEOUT"
    elif side == "maat":
        out = read(d, "outcome.txt") or read(d, "driver-stdout.txt") or ""
        m = re.search(r"Driver result: (.*)", out)
        spec = read(d, "spec-with-plan-and-review.md") or ""
        if not m:
            rec["outcome"] = "ERROR"
            rec["outcome_detail"] = "\n".join((read(d, "driver-stdout.txt") or "").splitlines()[-5:])
        else:
            line = m.group(1).strip()
            if line.startswith("DONE"):
                rec["outcome"] = "IMPLEMENTED"
            elif line.startswith("STOP") and re.search(r"Feature status:\s*NEEDS_VERIFICATION", spec):
                rec["outcome"] = "NEEDS_VERIFICATION"
            else:
                rec["outcome"] = "STOP"
            rec["outcome_detail"] = line
        rec["report"] = "records/%s/spec-with-plan-and-review.md + records/%s/outcome.txt" % (rid, rid)
    else:
        result = None
        for line in (read(d, "transcript.jsonl") or "").splitlines():
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if isinstance(e, dict) and e.get("type") == "result":
                result = e
        if result is None:
            rec["outcome"] = "ERROR"
            rec["outcome_detail"] = "\n".join((read(d, "stderr.txt") or "").splitlines()[-5:])
        elif result.get("is_error") or not (result.get("result") or "").strip():
            rec["outcome"] = "NO_REPORT"
            rec["outcome_detail"] = result.get("subtype", "")
        else:
            rec["outcome"] = "COMPLETED"
        rec["report"] = "records/%s/report.md" % rid
        if result is not None and result.get("total_cost_usd") is not None:
            rec["cost_usd_api_equivalent"] = round(float(result["total_cost_usd"]), 4)
        m = re.search(r"<!-- usage_from_transcript=(\{.*?\}) -->", read(d, "report.md") or "")
        if m:
            rec["cost_breakdown"] = json.loads(m.group(1))
    if side == "maat":
        cs = read(d, "cost-summary.txt") or ""
        m = re.search(r"^Cost: \$([0-9.]+)", cs, re.M)
        if m:
            rec["cost_usd_api_equivalent"] = float(m.group(1))
        for pm in re.finditer(r"^\s+(\d\d-\S+)\s+\$([0-9.]+)\s+([0-9.]+) min", cs, re.M):
            rec["cost_breakdown"][pm.group(1)] = {"cost_usd": float(pm.group(2)), "minutes": float(pm.group(3))}
    m = re.search(r"hidden: (\d+)/(\d+)", read(d, "hidden_tests.txt") or "")
    if m:
        p, t = int(m.group(1)), int(m.group(2))
        if t != total:
            sys.exit("%s: hidden total %d, the task's fixed total is %d" % (rid, t, total))
        rec["hidden_tests"] = {"passed": p, "total": t}
    with open(os.path.join(d, "record.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(rec, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("%s: %s, hidden %s, cost %s, %s s%s" % (rid, rec["outcome"], m and "%d/%d" % (p, t), rec["cost_usd_api_equivalent"],
                                                  rec["wall_clock_s"], ", CONTAMINATED" if rec["contaminated"] else ""))


if __name__ == "__main__":
    main()
