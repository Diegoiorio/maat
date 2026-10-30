#!/usr/bin/env python3
"""cycle-report.py — measurement of a full-cycle run, from the phases' stream-json logs. READ-ONLY
(except `--append`, which writes only the metrics file).

Usage: python cycle-report.py <spec-<name>.run | .jsonl file> [...] [--json]
      python cycle-report.py --append [--metrics <file.csv>] <spec-<name>.run> [...]
      common options: --projects <dir>  (root of the transcripts; default ~/.claude/projects)

Each argument is a cycle (a run directory: the phases are `log/NN-<phase>.jsonl`; or a single `.jsonl`).
It builds on the plugin's `scripts/phase-usage.py`, which stays as it is. Per cycle:

- **A · work** = sum of the `result.duration_ms` of all phases, plus the seconds of the driver's steps:
  the `durata` field of the JSON files in `<run>/evidence/**` and `<run>/counterproof/**` (number = seconds;
  string with unit `ms`/`s`/`min`); if there are none, 0.
- **B · wait** = from the first to the last event of the phases, from the timestamps of the transcripts
  `<projects>/*/<session_id>.jsonl` (plus `<session_id>/subagents/*.jsonl`), MINUS the pauses between a phase in
  STOP and the next phase. If a phase's transcript is missing: B = «non misurabile», never estimated.
- **buckets** per thread (orchestrator and each sub-agent), from the stream timestamps: each interval between two
  consecutive events of the same thread is «modello» if it ends on an assistant message, tool time
  if it ends on a tool_result (split among the tool_results of the same event), off-turn if it spans a
  `result` or a `system/init` of the orchestrator (end of turn waiting for background tasks). The tool is
  classified: vitest, eslint, pytest, build, controprove, polling, git/harness, file, agenti, bash, altro.
  «agenti» is the orchestrator's wait on a sub-agent: it overlaps the time of the sub-agent's threads
  and does not enter the aggregates. Wall-clock time: where several threads work together the stretch is split
  among them (never counted twice); off-turn time where nobody works is «attesa passiva», off-turn time where
  a background sub-agent works is work («fuori turno», outside A like the phases without `result`).
  A polling call that names the id or the output file of a background task goes to the awaited task.
- **reruns**: a gate command (vitest, eslint, pytest, build) equal to one already launched in the cycle
  (compared ignoring `2>&1` and the filters `| tail/head/grep/sed/cut/tee`) without, in between, an Edit/Write/
  MultiEdit/NotebookEdit or a `sed -i` on sources (outside `.ai-workflow` and the temporary folders).
  Counterproofs do not count as writes (they restore the tree); a STOP resets the state (between a phase
  in STOP and the next one the tree may be changed by hand).
- aggregates: (a) removable = reruns · (b) gates and counterproofs on first run = vitest+eslint+pytest+
  build+controprove+polling minus the reruns · (c) model · rest = file+git/harness+bash+altro.
- `total_cost_usd` (maximum per phase: it is cumulative), tokens from `modelUsage` (maximum per session and model:
  cumulative, includes the sub-agents), 5h quota before/after (`rate_limit_event`), STOPs by cause (lines
  `ESITO FASE <fase>: STOP — <causa>` from `.esito`, otherwise from the `result` text or from `.jsonl.result`).
"""
import argparse
import csv
import datetime
import glob
import json
import os
import re
import sys

MAIN = "orchestratore"
WRITERS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
FILE_TOOLS = {"Read", "Grep", "Glob"} | WRITERS
AGENT_TOOLS = {"Agent", "Task"}
POLL_TOOLS = {"BashOutput", "TaskOutput", "Monitor", "ScheduleWakeup"}
HARNESS_TOOLS = {"Skill", "ToolSearch", "TaskStop", "SendMessage", "TodoWrite"}
SHELL_TOOLS = {"Bash", "PowerShell"}
GATES = ("vitest", "eslint", "pytest", "build")
BUCKETS = GATES + ("controprove", "polling", "git/harness", "file", "agenti", "bash", "altro")
BASH_OPT = r"bash\s+(?:-\S+\s+)*\S*"
RUN_ESLINT = r"npx eslint|npm run lint|" + BASH_OPT + r"vitest-fast\.sh\s+--lint"
RUN_VITEST = r"npx vitest(?:\s+run)?|vitest run|" + BASH_OPT + r"vitest-fast\.sh(?!\s+--lint)"
# pytest also from the venv executable (`./.venv/Scripts/pytest.exe -q`): it is the same gate
RUN_PYTEST = r"-m pytest|(?:^|[;&|(]\s*)(?:\S*[/\\])?pytest(?:\.exe)?\b|(?:\./|bash\s+\S*)run_tests\.sh"
CMD_CLASSES = [  # order: the first match wins
    # `ping -n N 127.0.0.1` is the sleep of Windows prompts
    ("polling", r"\bsleep\b|\buntil\b|kill -0|\bping\s+-n\s+\d+\s+127\.0\.0\.1"),
    ("controprove", r"(?<![A-Za-z0-9])_?cp(?:[-_][\w-]*)?\.sh\b|counterproof|controprov|cp-tools|cp-results|\bmutat"),
    ("eslint", RUN_ESLINT),
    ("vitest", RUN_VITEST),
    ("pytest", RUN_PYTEST),
    ("build", r"npm run build|nuxi (?:build|generate)|vue-tsc|tsc --noEmit"),
    # loop with early exit (`for i in $(seq 1 110); do grep -q exit= f && break; ...`): a wait even
    # without sleep; after the gates, so that a gate relaunched in a retry loop stays a gate
    ("polling", r"\b(?:for|while)\b[^;\n]*;\s*do\b[\s\S]*?\bbreak\b"),
    ("git/harness", r"(?:^|[;&|(]\s*)git\b|\.claude/skills/|run-phase|cycle-state|plan-check|review-surface"),
    ("file", r"^\s*(?:cd [^;&|]*(?:&&|;)\s*)?(?:sed -n|cat|head|tail|grep|rg|ls|wc|find|file|diff|cmp|cp|mv|"
             r"mkdir|rm|touch|stat|echo|printf)\b"),
]
STOP_CLASSES = [  # cause of a STOP, from the text of the ESITO line
    ("deviazione", r"deviazion"),
    ("quota", r"quota|rate.?limit"),
    ("timeout", r"timeout|scadut"),
    ("concorrenza", r"contempor|concorren|\block\b"),
    ("gate", r"\bgate\b|\bFAIL\b|ross[oi]\b"),
    ("decisione", r"decid|decision|domand|scelt"),
]
NOT_SOURCE = re.compile(r"\.ai-workflow/|AppData/Local/Temp/|(^|/)tmp/|scratchpad", re.I)
PASSIVE = ("passive", None)  # wall_share destination: the orchestrator waiting off-turn
OFF_TURN = ("off_turn", None)  # work (already in the buckets) done while the orchestrator is off-turn: outside A
# id in the tool_result: command launched in background · command moved to background by the timeout · async sub-agent
BG_ID = re.compile(r"(?:with ID:|\(ID:|agentId:)\s*(\w+)")
OUT_FILE = re.compile(r"(?:>>?|\btee(?:\s+-a)?)\s*[\"']?[^\s\"'|;&<>]*?([\w.-]+\.(?:txt|log|out|output|json))\b")
ESITO = re.compile(r"ESITO FASE ([\w-]+):\s*(OK|STOP)\s*(?:[—–-]+\s*)?(.*)")
CSV_COLS = ["data", "spec", "fasi", "A_min", "B_min", "bucket_a_min", "bucket_b_min", "bucket_c_min",
            "bucket_resto_min", "costo_usd", "token_cache_letti", "token_cache_scritti", "token_output",
            "riesecuzioni", "stop", "stop_cause", "harness"]


def events_of(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            try:
                ev = json.loads(ln)
            except ValueError:
                continue
            if isinstance(ev, dict):
                yield ev


def ts_of(ev):
    s = ev.get("timestamp")
    if not isinstance(s, str):
        return None
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def strip_heredoc(cmd):
    """Strips heredoc bodies: they are text written to a file, not a command."""
    return re.sub(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n.*?\n\s*\2\s*(?=\n|$)", "<<HEREDOC", cmd, flags=re.S)


def classify_cmd(cmd):
    cmd = strip_heredoc(cmd)
    for name, rx in CMD_CLASSES:
        if re.search(rx, cmd):
            return name
    return "bash"


def category(name, inp):
    if name in SHELL_TOOLS:
        return classify_cmd(inp.get("command") or "")
    if name in AGENT_TOOLS:
        return "agenti"
    if name in POLL_TOOLS:
        return "polling"
    if name in FILE_TOOLS:
        return "file"
    if name in HARNESS_TOOLS:
        return "git/harness"
    return "altro"


NOISE = {"run", "-q", "-v", "-vv", "--quiet", "--no-header", "2>&1"}


def gate_key(cat, cmd):
    """Key of a gate command: the runner and its arguments, ignoring wrappers (wsl, cd, time,
    redirections, output filters, `echo exit=$?`) and the options that only change the output."""
    cmd = re.sub(r"\s\d*>>?(?:&\d|\s*\S+)", " ", strip_heredoc(cmd))  # redirections: 2>&1, > file, 2>/dev/null
    parts = []
    for name, rx in (("eslint", RUN_ESLINT), ("vitest", RUN_VITEST), ("pytest", RUN_PYTEST)):
        for m in re.finditer("(?:%s)([^|;&>\n]*)" % rx, cmd):
            toks, skip = [], False
            for t in m.group(1).split():
                t = t.strip("'\"")
                if skip:
                    skip = False
                    continue
                if t in ("--base", "-p") and name != "vitest":
                    skip = True  # --base <sha> (lint) and -p no:<plugin> (pytest): they do not change what is checked
                    continue
                if not t or t in NOISE or t.startswith("--tb="):
                    continue
                toks.append(t)
            parts.append((m.start(), name + "(" + " ".join(toks) + ")"))
    if parts:
        return cat + ":" + " ".join(p for _s, p in sorted(parts))
    c = re.sub(r"\s*\d?>&\d", "", cmd)
    c = re.sub(r"\|\s*(?:tail|head|grep|sed|cut|tee)\b[^|;&]*", "", c)
    return cat + ":" + " ".join(c.split())


def writes_source(name, inp, cat):
    if name in WRITERS:
        p = (inp.get("file_path") or inp.get("notebook_path") or "").replace("\\", "/")
        return bool(p) and not NOT_SOURCE.search(p)
    if name in SHELL_TOOLS and cat != "controprove":
        cmd = inp.get("command") or ""
        if re.search(r"\bsed\s+(?:-\S+\s+)*-i", cmd):
            return not (".ai-workflow" in cmd and "modules/" not in cmd)
    return False


def stop_class(text):
    for name, rx in STOP_CLASSES:
        if re.search(rx, text, re.I):
            return name
    return "altro"


def esito_of(path, results):
    base = path[:-len(".jsonl")] if path.endswith(".jsonl") else path
    texts = []
    if os.path.isfile(base + ".esito"):
        texts.append(open(base + ".esito", encoding="utf-8", errors="replace").read())
    texts += [r.get("result") or "" for r in reversed(results)]
    if os.path.isfile(path + ".result"):
        texts.append(open(path + ".result", encoding="utf-8", errors="replace").read())
    for t in texts:
        found = [m for m in (ESITO.search(ln) for ln in str(t).splitlines()) if m]
        if found:
            m = found[-1]
            return m.group(2), m.group(3).strip()
    return None, ""


def wall_share(work):
    """Parallel threads (background or concurrent sub-agent, orchestrator working while a sub-agent
    runs): the same wall-clock second is not counted twice. In each stretch between two consecutive endpoints,
    each active interval gets stretch x weight / max(1, sum of the active weights); without overlaps each
    interval keeps its whole time. So a phase's buckets sum to the worked wall-clock time,
    like A, which is wall-clock time (`duration_ms`). The orchestrator's off-turn waits (PASSIVE, weight 0)
    take only the part of the stretch where nobody else works: a background sub-agent working
    while the orchestrator has closed its turn is work, not passive wait."""
    marks = sorted([(w[0], 1, k) for k, w in enumerate(work)] + [(w[1], 0, k) for k, w in enumerate(work)])
    out, active, last = {}, set(), None
    for x, is_start, k in marks:  # at the same instant, ends before starts
        if active and x > last:
            busy = round(sum(work[j][2] for j in active), 9)
            f = (x - last) / max(1.0, busy)
            for j in active:
                if work[j][3] != PASSIVE:
                    out[work[j][3]] = out.get(work[j][3], 0.0) + f * work[j][2]
            if any(work[j][3] == PASSIVE for j in active):
                out[PASSIVE] = out.get(PASSIVE, 0.0) + (x - last) * max(0.0, 1 - busy)
                out[OFF_TURN] = out.get(OFF_TURN, 0.0) + (x - last) * min(1.0, busy)
        last = x
        if is_start:
            active.add(k)
        else:
            active.discard(k)
    return out


def analyse_phase(path):
    label = os.path.basename(path)[:-len(".jsonl")] if path.endswith(".jsonl") else os.path.basename(path)
    m = re.match(r"^\d+-([a-z]+)", label)
    kind = {}                  # tool_use_id of an Agent/Task -> sub-agent type
    tool_input = {}            # tool_use_id -> (thread, name, input, launch ts)
    seq = {}                   # thread -> [(ts, type, tool_use_ids)] in stream order; type A/U/R
    results, rl, sids, first_ts = [], [], set(), None
    bg_id = {}                 # tool_use_id of a background command -> task id

    for ev in events_of(path):
        t = ev.get("type")
        if ev.get("session_id"):
            sids.add(ev["session_id"])
        if t == "rate_limit_event":
            w = ((ev.get("rate_limit_info") or {}).get("unifiedWindows") or {}).get("five_hour") or {}
            if "utilization" in w:
                rl.append(w["utilization"])
        elif t == "result":
            results.append(ev)
            seq.setdefault(MAIN, []).append((None, "R", ()))
        elif t == "system" and ev.get("subtype") == "init":
            # every turn opens with an `init`: it is the end of the previous turn even when the stream puts all the
            # `result`s at the end (happens with background sub-agents: 01-plan type, 10 results at the end)
            seq.setdefault(MAIN, []).append((None, "R", ()))
        elif t in ("assistant", "user"):
            th = ev.get("parent_tool_use_id") or MAIN
            ts = ts_of(ev)
            if ts is not None and first_ts is None:
                first_ts = ts
            content = (ev.get("message") or {}).get("content")
            blocks = [b for b in content if isinstance(b, dict)] if isinstance(content, list) else []
            if t == "assistant":
                for b in blocks:
                    if b.get("type") == "tool_use":
                        inp = b.get("input") or {}
                        tool_input[b.get("id")] = (th, b.get("name"), inp, ts)
                        if b.get("name") in AGENT_TOOLS:
                            kind[b.get("id")] = inp.get("subagent_type") or "general-purpose"
                if ts is not None:
                    seq.setdefault(th, []).append((ts, "A", ()))
            else:
                for b in blocks:  # id of a background task (command or sub-agent), from its tool_result
                    lau = tool_input.get(b.get("tool_use_id")) if b.get("type") == "tool_result" else None
                    if lau and (lau[1] in SHELL_TOOLS or lau[1] in AGENT_TOOLS):
                        mid = BG_ID.search(json.dumps(b.get("content"), ensure_ascii=False))
                        if mid:
                            bg_id[b.get("tool_use_id")] = mid.group(1)
                if ts is not None:
                    ids = tuple(b.get("tool_use_id") for b in blocks if b.get("type") == "tool_result")
                    seq.setdefault(th, []).append((ts, "U", ids))
                    for i in ids:
                        # the final message of a foreground sub-agent is not in the stream: it arrives as the
                        # Agent's tool_result. If the thread is stopped on a tool_result, the model turn that
                        # produces that message ends here.
                        lau = tool_input.get(i)
                        if lau and lau[1] in AGENT_TOOLS and not lau[2].get("run_in_background") and \
                                seq.get(i) and seq[i][-1][1] == "U":
                            seq[i].append((ts, "A", ()))

    # A background command (launched that way or moved there by the timeout) or an async sub-agent returns
    # immediately: its time is the wait of whoever awaits it. A wait (polling) that names the task id or a file
    # the command writes to (`>`, `>>`, `tee`) goes to the most recent matching task of the same thread: so
    # a gate weighs the same in foreground or background, and the wait on a sub-agent stays «agenti».
    owner, bg = {}, []         # owner: polling tool_use_id -> tool_use_id of the awaited task
    for tid, (th, name, inp, _ts) in tool_input.items():
        if category(name, inp) == "polling":
            blob = json.dumps(inp, ensure_ascii=False)
            for bth, btid, marks in reversed(bg):
                if bth == th and any(mk in blob for mk in marks):
                    owner[tid] = btid
                    break
        if name in SHELL_TOOLS or name in AGENT_TOOLS:
            marks = set(OUT_FILE.findall(strip_heredoc(inp.get("command") or ""))) if inp.get("run_in_background") \
                else set()
            if tid in bg_id:
                marks.add(bg_id[tid])
            if marks:
                bg.append((th, tid, marks))

    tool_s = {}                # tool_use_id -> seconds
    model_by_thread, passive, off_turn = {}, 0.0, 0.0
    work = []                  # (start, end, weight, ("tool", id) | ("model", thread)): wall-clock time to split
    for th, evs in seq.items():
        name = MAIN if th == MAIN else kind.get(th, "sub-agente?")
        prev, crossed = None, False
        for ts, typ, ids in evs:
            if typ == "R":
                crossed = prev is not None
                continue
            if prev is None:
                prev = ts
                continue
            d = max(0.0, ts - prev)
            if crossed:
                if d:
                    work.append((prev, ts, 0.0, PASSIVE))
            elif typ == "U" and ids:
                for i in ids:
                    i = owner.get(i, i)
                    if (tool_input.get(i) or (None, None))[1] in AGENT_TOOLS:
                        tool_s[i] = tool_s.get(i, 0.0) + d / len(ids)  # wait on a sub-agent: outside the split
                    elif d:
                        work.append((prev, ts, 1.0 / len(ids), ("tool", i)))
            elif typ == "U":
                pass  # prompt or system message: the time belongs to the queue, not to the model or a tool
            elif d:
                work.append((prev, ts, 1.0, ("model", name)))
            prev, crossed = ts, False
    for (what, key), s in wall_share(work).items():
        if what == "tool":
            tool_s[key] = tool_s.get(key, 0.0) + s
        elif what == "model":
            model_by_thread[key] = model_by_thread.get(key, 0.0) + s
        elif what == "off_turn":
            off_turn += s
        else:
            passive += s

    buckets = {b: 0.0 for b in BUCKETS}
    actions = []               # (ts, 'gate', key, tool_use_id) | (ts, 'write', None, tool_use_id)
    for tid, (th, name, inp, ts) in tool_input.items():
        cat = category(name, inp)
        buckets[cat] += tool_s.get(tid, 0.0)
        if ts is None:
            continue
        if cat in GATES:
            actions.append((ts, "gate", gate_key(cat, inp.get("command") or ""), tid))
        elif writes_source(name, inp, cat):
            actions.append((ts, "write", None, tid))
    actions.sort(key=lambda a: a[0])

    usage_max = {}
    for r in results:
        for mod, v in (r.get("modelUsage") or {}).items():
            k = (r.get("session_id"), mod)
            cur = usage_max.setdefault(k, [0, 0, 0])
            cur[0] = max(cur[0], v.get("cacheReadInputTokens") or 0)
            cur[1] = max(cur[1], v.get("cacheCreationInputTokens") or 0)
            cur[2] = max(cur[2], v.get("outputTokens") or 0)
    if usage_max:
        tok = [sum(v[i] for v in usage_max.values()) for i in range(3)]
    else:
        us = [r.get("usage") or {} for r in results]
        tok = [sum(u.get(f) or 0 for u in us)
               for f in ("cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens")]
    esito, cause = esito_of(path, results)
    return {
        "label": label,
        "phase": m.group(1) if m else label,
        "log": path,
        "session_ids": sorted(sids),
        "first_ts": first_ts,
        "duration_s": sum(r.get("duration_ms") or 0 for r in results) / 1000.0,
        "results": len(results),
        "cost_usd": max([r.get("total_cost_usd") or 0 for r in results] or [0]),
        "tokens": {"cache_read": tok[0], "cache_write": tok[1], "output": tok[2]},
        "quota_5h": [rl[0], rl[-1]] if rl else None,
        "esito": esito,
        "stop_cause": cause if esito == "STOP" else "",
        "stop_class": stop_class(cause) if esito == "STOP" else "",
        "buckets_s": buckets,
        "model_by_thread_s": model_by_thread,
        "passive_wait_s": passive,
        "off_turn_work_s": off_turn,
        "work_s": sum(v for k, v in buckets.items() if k != "agenti") + sum(model_by_thread.values()),
        "_tool_s": tool_s,
        "_actions": actions,
    }


def transcript_window(sids, projects):
    """(start, end, missing) from the sessions' transcripts; None if one is missing."""
    lo, hi, missing = None, None, []
    for sid in sids:
        mains = glob.glob(os.path.join(glob.escape(projects), "*", glob.escape(sid) + ".jsonl"))
        if not mains:
            missing.append(sid)
            continue
        files = mains + glob.glob(os.path.join(glob.escape(projects), "*", glob.escape(sid), "subagents", "*.jsonl"))
        for f in files:
            for ev in events_of(f):
                ts = ts_of(ev)
                if ts is None:
                    continue
                lo = ts if lo is None else min(lo, ts)
                hi = ts if hi is None else max(hi, ts)
    if not sids:
        missing.append("(nessun session_id nello stream)")
    return lo, hi, missing


def durata_s(v):
    if isinstance(v, bool):
        return 0.0
    if isinstance(v, (int, float)):
        return float(v)
    m = re.fullmatch(r"\s*(\d+(?:[.,]\d+)?)\s*(ms|s|sec|min|m)?\s*", str(v))
    if not m:
        return 0.0
    n = float(m.group(1).replace(",", "."))
    return {"ms": n / 1000, "min": n * 60, "m": n * 60}.get(m.group(2), n)


def driver_seconds(run_dir):
    tot = 0.0
    for sub in ("evidence", "counterproof"):
        for root, _dirs, files in os.walk(os.path.join(run_dir, sub)):
            for f in files:
                if not f.endswith(".json"):
                    continue
                try:
                    with open(os.path.join(root, f), encoding="utf-8") as fh:
                        data = json.load(fh)
                except (OSError, ValueError):
                    continue
                if isinstance(data, dict) and "durata" in data:
                    tot += durata_s(data["durata"])
    return tot


def files_of(arg):
    if os.path.isdir(arg):
        return sorted(glob.glob(os.path.join(glob.escape(arg), "log", "*.jsonl")) or
                      glob.glob(os.path.join(glob.escape(arg), "*.jsonl")))
    return [arg]


def spec_name(arg):
    b = os.path.basename(os.path.normpath(arg))
    return b[:-len(".run")] if b.endswith(".run") else b


def harness_of(arg):
    """The cycle's harness, from <run>/harness.fp (pk04a-2): {"versione", "radice"}; None for a run dir in the
    older format (one fingerprint line, no versione=), without harness.fp or for a single .jsonl: the internal harness."""
    if not os.path.isdir(arg):
        return None
    try:
        with open(os.path.join(arg, "harness.fp"), encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return None
    kv = {}
    for line in text.replace("\r", "").split("\n"):
        k, sep, v = line.partition("=")
        if sep and k in ("versione", "radice") and k not in kv:
            kv[k] = v
    if "versione" not in kv:
        return None
    # empty versione= (plugin.json without version): never «maat » without a number
    return {"versione": kv["versione"].strip() or "versione ignota", "radice": kv.get("radice", "")}


def analyse_cycle(arg, projects):
    phases = [analyse_phase(f) for f in files_of(arg)]
    driver = driver_seconds(arg) if os.path.isdir(arg) else 0.0

    # B: windows from the transcripts
    missing = []
    for p in phases:
        lo, hi, miss = transcript_window(p["session_ids"], projects)
        p["window"] = [lo, hi] if not miss and lo is not None else None
        missing += miss
    b_s, pauses, unexited = None, [], []
    if phases and not missing and all(p["window"] for p in phases):
        order = sorted(phases, key=lambda p: p["window"][0])
        span = max(p["window"][1] for p in order) - order[0]["window"][0]
        for cur, nxt in zip(order, order[1:]):
            gap = {"dopo": cur["label"], "s": max(0.0, nxt["window"][0] - cur["window"][1])}
            if cur["esito"] == "STOP":
                pauses.append(gap)
            elif cur["esito"] is None:
                unexited.append(gap)  # phase without ESITO (interrupted): the pause stays in B, only shown here
        b_s = span - sum(x["s"] for x in pauses)

    # reruns: phase order, within a phase launch order
    reruns, seen, prev_stop = [], set(), False
    for p in phases:
        if prev_stop:
            seen.clear()
        for ts, typ, key, tid in p["_actions"]:
            if typ == "write":
                seen.clear()
                continue
            if key in seen:
                reruns.append({"fase": p["label"], "comando": key, "s": p["_tool_s"].get(tid, 0.0)})
            seen.add(key)
        prev_stop = p["esito"] == "STOP"

    buckets = {b: sum(p["buckets_s"][b] for p in phases) for b in BUCKETS}
    model = sum(sum(p["model_by_thread_s"].values()) for p in phases)
    rerun_s = sum(r["s"] for r in reruns)
    first_q = next((p["quota_5h"][0] for p in phases if p["quota_5h"]), None)
    last_q = next((p["quota_5h"][1] for p in reversed(phases) if p["quota_5h"]), None)
    a_by_phase, model_by = {}, {}
    for p in phases:
        a_by_phase[p["phase"]] = a_by_phase.get(p["phase"], 0.0) + p["duration_s"]
        for th, s in p["model_by_thread_s"].items():
            k = p["phase"] + "/" + th
            model_by[k] = model_by.get(k, 0.0) + s
    stops = [{"fase": p["label"], "causa": p["stop_class"], "testo": p["stop_cause"]}
             for p in phases if p["esito"] == "STOP"]
    by_cause = {}
    for s in stops:
        by_cause[s["causa"]] = by_cause.get(s["causa"], 0) + 1
    first = min([p["first_ts"] for p in phases if p["first_ts"]] or [None], key=lambda x: x or 0)
    for p in phases:
        p.pop("_tool_s")
        p.pop("_actions")
    return {
        "spec": spec_name(arg),
        "path": arg,
        "harness": harness_of(arg),
        "date": datetime.datetime.fromtimestamp(first).date().isoformat() if first else "",
        "phases": phases,
        "A_s": sum(p["duration_s"] for p in phases) + driver,
        "A_by_phase_s": a_by_phase,
        "driver_s": driver,
        "B_s": b_s,
        "B_missing_sessions": missing,
        "stop_pauses": pauses,
        "unexited_pauses": unexited,
        "buckets_s": buckets,
        "model_s": model,
        "model_by_thread_s": model_by,
        "passive_wait_s": sum(p["passive_wait_s"] for p in phases),
        "off_turn_work_s": sum(p["off_turn_work_s"] for p in phases),
        "no_result_work_s": sum(p["work_s"] for p in phases if not p["results"]),
        "reruns": reruns,
        "aggregates_s": {
            "a_eliminabile": rerun_s,
            "b_gate_primo_run": sum(buckets[g] for g in GATES + ("controprove", "polling")) - rerun_s,
            "c_modello": model,
            "resto": buckets["file"] + buckets["git/harness"] + buckets["bash"] + buckets["altro"],
        },
        "cost_usd": round(sum(p["cost_usd"] for p in phases), 2),
        "tokens": {k: sum(p["tokens"][k] for p in phases) for k in ("cache_read", "cache_write", "output")},
        "quota_5h": [first_q, last_q] if first_q is not None else None,
        "stops": stops,
        "stops_by_cause": by_cause,
    }


def mins(s):
    return "%.1f" % (s / 60.0)


def tk(n):
    return "%dk" % round(n / 1000) if n < 1_000_000 else "%.1fM" % (n / 1_000_000)


def print_cycle(c):
    q = c["quota_5h"]
    b = mins(c["B_s"]) + " min" if c["B_s"] is not None else "non misurabile"
    print("== %s  %s  fasi %d  A %s min (%s)  B %s  $%.2f  quota5h %s" % (
        c["spec"], c["date"], len(c["phases"]), mins(c["A_s"]),
        " · ".join("%s %s" % (k, mins(v)) for k, v in c["A_by_phase_s"].items()) +
        (" · driver %s" % mins(c["driver_s"]) if c["driver_s"] else ""), b, c["cost_usd"],
        "%.0f%%->%.0f%%" % (q[0] * 100, q[1] * 100) if q else "-"))
    h = c["harness"]
    print("   Harness: " + ("maat %s — %s" % (h["versione"], h["radice"]) if h else "harness interno"))
    if c["B_s"] is None and c["B_missing_sessions"]:
        print("   B: transcript mancanti: %s" % ", ".join(c["B_missing_sessions"]))
    if c["stop_pauses"]:
        print("   pause dopo STOP (fuori da B): %s" % ", ".join(
            "%s %s min" % (x["dopo"], mins(x["s"])) for x in c["stop_pauses"]))
    if c["unexited_pauses"]:
        print("   pause dopo fasi senza ESITO (dentro B): %s" % ", ".join(
            "%s %s min" % (x["dopo"], mins(x["s"])) for x in c["unexited_pauses"]))
    t = c["tokens"]
    print("   token: cache letti %s · cache scritti %s · output %s" % (
        tk(t["cache_read"]), tk(t["cache_write"]), tk(t["output"])))
    ag = c["aggregates_s"]
    print("   aggregati (min): (a) riesecuzioni %s [%d] · (b) gate+controprove+polling %s · (c) modello %s · "
          "resto %s · attesa passiva %s · agenti (sovrapposto) %s" % (
              mins(ag["a_eliminabile"]), len(c["reruns"]), mins(ag["b_gate_primo_run"]), mins(ag["c_modello"]),
              mins(ag["resto"]), mins(c["passive_wait_s"]), mins(c["buckets_s"]["agenti"])))
    print("   lavoro fuori da A (gia' negli aggregati, min): fuori turno %s · fasi senza result %s" % (
        mins(c["off_turn_work_s"]), mins(c["no_result_work_s"])))
    print("   bucket (min): " + " · ".join("%s %s" % (k, mins(v)) for k, v in c["buckets_s"].items() if v))
    print("   modello per filo (min): " + " · ".join(
        "%s %s" % (k, mins(v)) for k, v in sorted(c["model_by_thread_s"].items(), key=lambda x: -x[1])))
    for s in c["stops"]:
        print("   STOP %s [%s] %s" % (s["fase"], s["causa"], s["testo"][:110]))


def print_total(cycles):
    def tot(f):
        return sum(f(c) for c in cycles)
    by_phase, buckets, agg, model_by = {}, {}, {}, {}
    for c in cycles:
        for src, dst in ((c["A_by_phase_s"], by_phase), (c["buckets_s"], buckets), (c["aggregates_s"], agg),
                         (c["model_by_thread_s"], model_by)):
            for k, v in src.items():
                dst[k] = dst.get(k, 0.0) + v
    bs = [c["B_s"] for c in cycles]
    b = mins(sum(bs)) + " min" if all(x is not None for x in bs) else "non misurabile (%d cicli su %d)" % (
        sum(1 for x in bs if x is None), len(bs))
    print("== TOTALE %d cicli  A %s min (%s)  B %s  $%.2f  cache letti %s  riesecuzioni %d" % (
        len(cycles), mins(tot(lambda c: c["A_s"])), " · ".join("%s %s" % (k, mins(v)) for k, v in by_phase.items()),
        b, tot(lambda c: c["cost_usd"]), tk(tot(lambda c: c["tokens"]["cache_read"])),
        tot(lambda c: len(c["reruns"]))))
    print("   aggregati (min): " + " · ".join("%s %s" % (k, mins(v)) for k, v in agg.items()) +
          " · attesa passiva %s" % mins(tot(lambda c: c["passive_wait_s"])))
    print("   lavoro fuori da A (gia' negli aggregati, min): fuori turno %s · fasi senza result %s" % (
        mins(tot(lambda c: c["off_turn_work_s"])), mins(tot(lambda c: c["no_result_work_s"]))))
    print("   bucket (min): " + " · ".join("%s %s" % (k, mins(v)) for k, v in buckets.items() if v))
    print("   modello per filo (min): " + " · ".join(
        "%s %s" % (k, mins(v)) for k, v in sorted(model_by.items(), key=lambda x: -x[1])))


def csv_row(c):
    ag = c["aggregates_s"]
    return {
        "data": c["date"], "spec": c["spec"], "fasi": " ".join(p["label"] for p in c["phases"]),
        "A_min": mins(c["A_s"]), "B_min": mins(c["B_s"]) if c["B_s"] is not None else "non misurabile",
        "bucket_a_min": mins(ag["a_eliminabile"]), "bucket_b_min": mins(ag["b_gate_primo_run"]),
        "bucket_c_min": mins(ag["c_modello"]), "bucket_resto_min": mins(ag["resto"]),
        "costo_usd": "%.2f" % c["cost_usd"], "token_cache_letti": c["tokens"]["cache_read"],
        "token_cache_scritti": c["tokens"]["cache_write"], "token_output": c["tokens"]["output"],
        "riesecuzioni": len(c["reruns"]), "stop": len(c["stops"]),
        "stop_cause": ";".join("%s=%d" % kv for kv in sorted(c["stops_by_cause"].items())),
        "harness": "maat %s" % c["harness"]["versione"] if c["harness"] else "interno",
    }


def prepara_metriche(path):
    """Before appending to an existing metrics.csv (pk04a-2): None if the file is ready. Header equal to
    CSV_COLS: nothing to do. Header in the older format (CSV_COLS without the last column): the file is
    rewritten with the new header and the old rows with an empty last column, via a temporary file then renamed.
    Otherwise the reason (exit 2, file intact)."""
    with open(path, encoding="utf-8", newline="") as fh:
        rows = list(csv.reader(fh))
    head = rows[0] if rows else []
    if head == CSV_COLS:
        return None
    if head != CSV_COLS[:-1]:
        return "intestazione di %s sconosciuta, file non toccato: %r (attesa %r)" % (path, head, CSV_COLS)
    body = [r for r in rows[1:] if r]
    bad = [i + 2 for i, r in enumerate(rows[1:]) if r and len(r) != len(head)]
    if bad:
        return "%s: righe con un numero di campi diverso dall'intestazione (%s), file non toccato" % (
            path, ", ".join(map(str, bad[:5])))
    tmp = "%s.tmp-%d" % (path, os.getpid())
    try:
        with open(tmp, "w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(CSV_COLS)
            for r in body:
                w.writerow(r + [""])
        os.replace(tmp, path)
    except OSError as e:
        try:
            os.remove(tmp)
        except OSError:
            pass
        return "%s: migrazione dell'intestazione non riuscita (%s)" % (path, e)
    return None


def default_metrics():
    """MAAT_WORK/metrics.csv: the work folder (cartelle.lavoro) of the current folder's PROJECT, not three
    levels above this file (pk04a-1, schema L)."""
    sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import maat_paths
    try:
        return maat_paths.maat_work(maat_paths.project_root()) + "/metrics.csv"
    except maat_paths.ErroreMaat as e:
        sys.exit("cycle-report.py: %s (o indica --metrics)" % e)


def main(argv):
    ap = argparse.ArgumentParser(prog="cycle-report.py", description="Misura di un ciclo del full cycle.")
    ap.add_argument("cycles", nargs="+", help="spec-<name>.run o file .jsonl")
    ap.add_argument("--json", action="store_true", help="uscita JSON")
    ap.add_argument("--append", action="store_true", help="aggiunge una riga per ciclo al file delle metriche")
    ap.add_argument("--metrics", default=None, help="file delle metriche (default <cartella di lavoro del progetto>/metrics.csv, "
                         "cartelle.lavoro: .claude/.ai-workflow)")
    ap.add_argument("--projects", default=os.path.join(os.path.expanduser("~"), ".claude", "projects"),
                    help="radice dei transcript di Claude Code")
    a = ap.parse_args(argv)
    if a.metrics and not a.append:
        ap.error("--metrics vale solo con --append")
    for c in a.cycles:
        if not os.path.exists(c):
            ap.error("non esiste: %s" % c)
    cycles = [analyse_cycle(c, a.projects) for c in a.cycles]
    if a.append:
        path = a.metrics or default_metrics()
        new = not os.path.isfile(path) or os.path.getsize(path) == 0
        if not new:
            why = prepara_metriche(path)
            if why:
                sys.stderr.write("cycle-report.py: %s\n" % why)
                return 2
        with open(path, "a", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=CSV_COLS)
            if new:
                w.writeheader()
            for c in cycles:
                w.writerow(csv_row(c))
        for c in cycles:
            print("metrics: +1 riga %s -> %s" % (c["spec"], path))
        return 0
    if a.json:
        print(json.dumps(cycles, ensure_ascii=False, indent=1))
        return 0
    for c in cycles:
        print_cycle(c)
    if len(cycles) > 1:
        print_total(cycles)
    return 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main(sys.argv[1:]))
