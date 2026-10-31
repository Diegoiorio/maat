#!/usr/bin/env python3
"""stop-hook.py — `Stop` hook of the /full-implementation-cycle sub-sessions (harness-pt04, 1g).

run-phase.sh passes it with --settings next to guard.py. A `-p` sub-session that ends its turn
without the `PHASE RESULT` line, or while one of its background jobs has not been collected yet, ends there
("passive wait": nobody wakes it up). The hook DENIES the end of the turn in two cases:
  1. the assistant's last message (the text after the last tool call) does not contain a
     `PHASE RESULT <phase>: OK|STOP` line (Maat 1.3.0; the Italian `ESITO FASE <fase>: OK|STOP` of 1.2.x is
     accepted too, the denial quotes the English form);
  2. the transcript shows jobs launched in background (Bash, "running in background with ID: <id>") not
     collected: no `<task-notification>` for that <task-id> with a final <status>, no
     BashOutput/TaskOutput showing its final status, no TaskStop/KillShell on that id.

Against loops: with `stop_hook_active` (the session is already continuing because of a denial from this hook)
it always lets the session close. A failing hook must not block a session: unreadable input,
missing transcript or any exception -> it lets the session close (exit 0 with no output).

Usage: stdin = JSON of the Stop event (transcript_path, stop_hook_active). Denial = JSON
{"decision": "block", "reason": ...} on stdout, exit 0. Tests: the plugin's scripts/stop-hook.test.sh.
"""
import json
import re
import sys

ESITO_RE = re.compile(r"(?m)^\s*(?:PHASE RESULT|ESITO FASE) \S+: (OK|STOP)\b")   # both languages (1.3.0)
BG_RE = re.compile(r"in background with ID: ([A-Za-z0-9_-]+)")
NOTIF_RE = re.compile(r"<task-id>([A-Za-z0-9_-]+)</task-id>(.*?)</task-notification>", re.S)
DONE_RE = re.compile(r"<status>(completed|failed|killed|stopped|exited|error|cancelled)</status>")
OUTPUT_TOOLS = {"BashOutput", "TaskOutput"}
KILL_TOOLS = {"TaskStop", "KillShell", "KillBash"}
ID_KEYS = ("task_id", "bash_id", "shell_id", "id")


def text_of(content):
    """Text of a content (string or list of blocks)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(text_of(c.get("text") if isinstance(c, dict) and c.get("type") == "text"
                                 else c.get("content") if isinstance(c, dict) else c) for c in content)
    return ""


def strings(obj):
    """All the strings inside a JSON object (for notifications, wherever they are)."""
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from strings(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from strings(v)


def analyze(lines):
    """(final assistant text, ids of the background jobs still open)."""
    uses = {}          # tool_use_id -> (name, input)
    launched, closed = [], set()
    tail = []
    for ln in lines:
        try:
            ev = json.loads(ln)
        except ValueError:
            continue
        if not isinstance(ev, dict) or ev.get("isSidechain"):
            continue
        for s in strings(ev):
            if "<task-notification>" in s:
                for tid, body in NOTIF_RE.findall(s):
                    if DONE_RE.search(body):
                        closed.add(tid)
        msg = ev.get("message") if isinstance(ev.get("message"), dict) else {}
        content = msg.get("content")
        if ev.get("type") == "assistant" and isinstance(content, list):
            for c in content:
                if not isinstance(c, dict):
                    continue
                if c.get("type") == "tool_use":
                    tail = []
                    name, inp = c.get("name", ""), c.get("input") or {}
                    uses[c.get("id")] = (name, inp)
                    if name in KILL_TOOLS:
                        closed.update(str(inp[k]) for k in ID_KEYS if inp.get(k))
                elif c.get("type") == "text" and c.get("text"):
                    tail.append(c["text"])
        elif ev.get("type") == "user":
            tail = []   # a tool result or a new message: the final text comes after it
            for c in content if isinstance(content, list) else []:
                if not isinstance(c, dict) or c.get("type") != "tool_result":
                    continue
                name, inp = uses.get(c.get("tool_use_id"), ("", {}))
                res = text_of(c.get("content"))
                if name == "Bash":
                    m = BG_RE.search(res[:300])
                    if m:
                        launched.append(m.group(1))
                elif name in OUTPUT_TOOLS and DONE_RE.search(res):
                    closed.update(str(inp[k]) for k in ID_KEYS if inp.get(k))
    open_jobs = [j for j in dict.fromkeys(launched) if j not in closed]
    return "\n".join(tail), open_jobs


def main():
    try:
        data = json.load(sys.stdin)
        if data.get("stop_hook_active"):
            return
        with open(data["transcript_path"], encoding="utf-8", errors="replace") as f:
            final, open_jobs = analyze(f)
    except Exception:   # a broken hook must never hold a session back
        return
    reasons = []
    if open_jobs:
        reasons.append("job in background non raccolti: " + ", ".join(open_jobs)
                       + " — raccoglili (BashOutput/TaskOutput, finche' non sono finiti) o fermali (TaskStop)"
                       " prima di chiudere: in -p nessuno ti risveglia")
    if not ESITO_RE.search(final):
        reasons.append("l'ultimo messaggio non ha la riga `PHASE RESULT <phase>: OK — …` o `PHASE RESULT <phase>: STOP — …`:"
                       " completa la fase (o fermala con STOP e il motivo) e chiudi con quella riga")
    if reasons:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stdout.write(json.dumps({"decision": "block", "reason": "hook Stop: " + " · ".join(reasons)},
                                    ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
    sys.exit(0)
