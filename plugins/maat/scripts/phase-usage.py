#!/usr/bin/env python3
"""phase-usage.py — consumption of a full-cycle phase, read from the stream-json logs. READ ONLY.

Usage:  python phase-usage.py <spec-<name>.run | .jsonl file> [...] [--json]

For each phase log it prints:
- API-equivalent cost (`total_cost_usd`, the maximum: it is cumulative), duration and turns (sum of the
  `result` events: with background tasks the CLI closes and reopens the turn, and re-emits `system/init`),
  5h quota at the start and at the end (`rate_limit_event`: the measure that matters for the subscription),
  tools and MCP tools loaded at startup;
- per thread type (phase orchestrator; each sub-agent type, with its number of instances):
  model calls, initial / average / maximum context, cache reads, cache writes,
  tool calls and how many model calls carry more than one (batching). Output per call
  is not reliable in the stream: the output total is in the phase line;
- redundant re-reads: the same Read (file, offset, limit) repeated by the SAME instance without,
  in between, a write to that file or an action with an uncertain surface (any tool other
  than Read/Grep/Glob). Conservative estimate: it counts only certain waste (a `cat` via Bash is not visible);
- slow tools (>= 60 s, from the `tool_progress` heartbeat): what the phase was waiting for.

It decides nothing and writes nothing: it measures efficiency, kept separate from quality (findings, gates,
outcomes), which is read in the specs and in the `.esito` files.
"""
import glob
import json
import os
import sys

READ_ONLY = {"Read", "Grep", "Glob"}
WRITERS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
MAIN = "orchestratore"


def events_of(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            try:
                yield json.loads(ln)
            except ValueError:
                continue


def ctx_of(u):
    return (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) + \
        (u.get("cache_creation_input_tokens") or 0)


def new_inst():
    return {"calls": 0, "ctx": [], "cache_read": 0, "cache_write": 0, "tools": 0, "multi": 0,
            "redundant_reads": 0, "redundant_chars": 0, "valid": {}}


def analyse(path):
    kind = {}        # tool_use_id of an Agent/Task -> sub-agent type
    inst = {}        # instance (MAIN or tool_use_id of the launch) -> metrics
    seen_msg, uses_per_msg, tool_input, slow = set(), {}, {}, {}
    rl, results, init_tools = [], [], None

    for ev in events_of(path):
        t = ev.get("type")
        if t == "system" and ev.get("subtype") == "init" and init_tools is None:
            init_tools = ev.get("tools")
        elif t == "rate_limit_event":
            w = ((ev.get("rate_limit_info") or {}).get("unifiedWindows") or {}).get("five_hour") or {}
            if "utilization" in w:
                rl.append(w["utilization"])
        elif t == "result":
            results.append(ev)
        elif t == "tool_progress":
            tid = ev.get("parent_tool_use_id") or ev.get("tool_use_id")
            slow[tid] = max(slow.get(tid, 0), ev.get("elapsed_time_seconds") or 0)
        elif t == "assistant":
            key = ev.get("parent_tool_use_id") or MAIN
            s = inst.setdefault(key, new_inst())
            m = ev.get("message") or {}
            mid = m.get("id")
            if mid and mid not in seen_msg:
                seen_msg.add(mid)
                u = m.get("usage") or {}
                s["calls"] += 1
                s["ctx"].append(ctx_of(u))
                s["cache_read"] += u.get("cache_read_input_tokens") or 0
                s["cache_write"] += u.get("cache_creation_input_tokens") or 0
            uses = [b for b in (m.get("content") or []) if isinstance(b, dict) and b.get("type") == "tool_use"]
            # the blocks of a message arrive in separate events with the same id
            s["tools"] += len(uses)
            before = uses_per_msg.get(mid, 0)
            uses_per_msg[mid] = before + len(uses)
            if before < 2 <= uses_per_msg[mid]:
                s["multi"] += 1
            for b in uses:
                name, inp = b.get("name"), b.get("input") or {}
                tool_input[b.get("id")] = (key, name, inp)
                if name in ("Agent", "Task"):
                    kind[b.get("id")] = inp.get("subagent_type") or "general-purpose"
                if name == "Read":
                    continue  # evaluated on the result (needs the length)
                if name in WRITERS:
                    fp = os.path.normcase(inp.get("file_path") or "")
                    for sig in [sig for sig in s["valid"] if sig[0] == fp]:
                        del s["valid"][sig]
                elif name not in READ_ONLY:
                    s["valid"].clear()  # uncertain write surface: everything stale
        elif t == "user":
            for b in ((ev.get("message") or {}).get("content") or []):
                if not isinstance(b, dict) or b.get("type") != "tool_result":
                    continue
                key, name, inp = tool_input.get(b.get("tool_use_id"), (None, None, None))
                if name != "Read" or b.get("is_error") or key not in inst:
                    continue
                c = b.get("content")
                size = len(c) if isinstance(c, str) else \
                    sum(len(x.get("text", "")) for x in c or [] if isinstance(x, dict))
                sig = (os.path.normcase(inp.get("file_path") or ""), inp.get("offset"), inp.get("limit"))
                s = inst[key]
                if sig in s["valid"]:
                    s["redundant_reads"] += 1
                    s["redundant_chars"] += size
                s["valid"][sig] = True

    threads = {}
    for key, s in inst.items():
        name = MAIN if key == MAIN else kind.get(key, "sub-agente?")
        a = threads.setdefault(name, {"instances": 0, "calls": 0, "ctx": [], "ctx_first": [], "cache_read": 0,
                                      "cache_write": 0, "tools": 0, "multi_tool_msgs": 0,
                                      "redundant_reads": 0, "redundant_chars": 0})
        a["instances"] += 1
        for f in ("calls", "cache_read", "cache_write", "tools", "redundant_reads", "redundant_chars"):
            a[f] += s[f]
        a["multi_tool_msgs"] += s["multi"]
        a["ctx"] += s["ctx"]
        if s["ctx"]:
            a["ctx_first"].append(s["ctx"][0])
    for a in threads.values():
        c, f = a.pop("ctx"), a.pop("ctx_first")
        a["ctx_first"] = int(sum(f) / len(f)) if f else 0
        a["ctx_mean"] = int(sum(c) / len(c)) if c else 0
        a["ctx_max"] = max(c) if c else 0

    slow_list = []
    for tid, secs in sorted(slow.items(), key=lambda x: -x[1]):
        if secs < 60:
            continue
        key, name, inp = tool_input.get(tid, ("?", "?", {}))
        who = MAIN if key == MAIN else kind.get(key, "sub-agente?")
        what = (inp or {}).get("description") or (inp or {}).get("command") or ""
        slow_list.append({"thread": who, "tool": name, "seconds_at_least": secs, "what": str(what)[:90]})

    models = {}
    for r in results:
        for m, v in (r.get("modelUsage") or {}).items():
            models[m] = max(models.get(m, 0), round(v.get("costUSD") or 0, 2))
    return {
        "log": path,
        "cost_usd": round(max([r.get("total_cost_usd") or 0 for r in results] or [0]), 2),
        "duration_min": round(sum(r.get("duration_ms") or 0 for r in results) / 60000, 1),
        "turns": sum(r.get("num_turns") or 0 for r in results),
        "output_tokens": sum((r.get("usage") or {}).get("output_tokens") or 0 for r in results),
        "results": len(results),
        "is_error": any(r.get("is_error") for r in results),
        "quota_5h": [rl[0], rl[-1]] if rl else None,
        "init_tools": len(init_tools) if init_tools is not None else None,
        "init_mcp_tools": sum(1 for x in init_tools or [] if str(x).startswith("mcp__")),
        "models": models,
        "threads": threads,
        "slow_tools": slow_list,
    }


def files_of(arg):
    if os.path.isdir(arg):
        return sorted(glob.glob(os.path.join(arg, "log", "*.jsonl")) or glob.glob(os.path.join(arg, "*.jsonl")))
    return [arg]


def k(n):
    return "%dk" % round(n / 1000) if n < 1_000_000 else "%.1fM" % (n / 1_000_000)


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    if not args:
        print("uso: phase-usage.py <spec-<name>.run | file .jsonl> [...] [--json]", file=sys.stderr)
        return 2
    report = [analyse(f) for a in args for f in files_of(a)]
    if as_json:
        print(json.dumps(report, ensure_ascii=False, indent=1))
        return 0
    for r in report:
        q = r["quota_5h"]
        print("== %s  $%.2f  %.1f min  turni %d  output %s  quota5h %s  tool all'avvio %s (mcp %s)%s" % (
            os.path.basename(r["log"]), r["cost_usd"], r["duration_min"], r["turns"], k(r["output_tokens"]),
            "%.0f%%->%.0f%%" % (q[0] * 100, q[1] * 100) if q else "-", r["init_tools"], r["init_mcp_tools"],
            "  ERRORE" if r["is_error"] else ""))
        print("   %-24s %4s %6s %7s %7s %7s %8s %7s %5s %5s  %s" % (
            "filo", "ist.", "chiam.", "ctx0", "ctxMed", "ctxMax", "cacheR", "cacheW", "tool", "multi",
            "riletture"))
        for name, t in sorted(r["threads"].items(), key=lambda x: -x[1]["cache_read"]):
            print("   %-24s %4d %6d %7s %7s %7s %8s %7s %5d %5d  %d (%s car.)" % (
                name[:24], t["instances"], t["calls"], k(t["ctx_first"]), k(t["ctx_mean"]), k(t["ctx_max"]),
                k(t["cache_read"]), k(t["cache_write"]), t["tools"], t["multi_tool_msgs"],
                t["redundant_reads"], k(t["redundant_chars"])))
        for s in r["slow_tools"][:8]:
            print("   lento: %-14s %-6s >= %4ds  %s" % (s["thread"][:14], s["tool"], s["seconds_at_least"], s["what"]))
    return 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main(sys.argv[1:]))
