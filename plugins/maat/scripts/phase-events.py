#!/usr/bin/env python3
"""phase-events.py — turns the stream-json log of a subsession into progress lines.

    python3 -u phase-events.py <log.jsonl> <file.exit>

Each line printed on stdout becomes an update in the main chat (Monitor tool).
It emits ONLY: the "▶ " lines written by the subsession, the agents and skills launched, the verdict
(`Decision:`) of each agent, and the end of the phase. Everything else in the log (reads, searches,
reasoning) stays in the file and does not enter the chat context.

The END of the phase (`■`/`✖`) is emitted only when <file.exit> exists, i.e. when the subsession
has really exited: in `-p` every intermediate turn produces a `result` event, which here becomes just a
progress line ("· turno concluso"). The last `result` seen stays in <log>.pending and becomes the
end line when <file.exit> appears.

It resumes from where it stopped (<log>.pos): the Monitor expires after 30 minutes and must be re-armed, and a
re-arm must not repeat events already shown. Exits 0 at the end of the phase, 1 if the subsession
ended without a result (crash, interruption) or with a non-zero .exit even after a `result`
(`✖` line): silence must not look like "still working".
Launched by watch-phase.sh with the python.sh interpreter (FIC_PY), without WSL.
The words of the lines come from the message catalog next to this file (maat_msg.py, 1.4.0); the "▶ " lines, the
`Decision:` of the agents and the PHASE RESULT line are quoted as they are.
"""
import json
import os
import sys
import time

sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from maat_msg import T  # noqa: E402

MAX = 240


def short(s, n=MAX):
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[: n - 1] + "…"


def emit(s):
    print(s, flush=True)


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict))
    return ""


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("uso: phase-events.py <log.jsonl> <file.exit>\n")
        sys.exit(2)
    log, exitf = sys.argv[1], sys.argv[2]
    posf = log + ".pos"
    resf = log + ".result"
    pendf = log + ".pending"  # last candidate end line: survives a re-arm
    # re-arm after the end of the phase: repeats the outcome instead of saying "no result"
    if os.path.exists(resf):
        emit(open(resf, encoding="utf-8").read().strip())
        sys.exit(0)
    pos = 0
    try:
        with open(posf) as f:
            pos = int(f.read().strip() or 0)
    except (OSError, ValueError):
        pass
    last = None
    try:
        with open(pendf, encoding="utf-8") as f:
            last = f.read().strip() or None
    except OSError:
        pass
    agents = {}  # tool_use_id -> description
    buf = ""
    idle = 0
    while True:
        chunk = ""
        try:
            with open(log, "r", encoding="utf-8", errors="replace") as f:
                f.seek(pos)
                chunk = f.read()
                pos = f.tell()
        except OSError:
            pass
        buf += chunk
        while "\n" in buf:
            line, buf = buf.split("\n", 1)
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            done = handle(ev, agents)
            # a `result` is not the end: remember it (also on file, for the re-arm) and continue
            if done is not None:
                last = done
                with open(pendf, "w", encoding="utf-8") as f:
                    f.write(done)
            with open(posf, "w") as f:
                f.write(str(pos - len(buf.encode("utf-8"))))
        if chunk:
            idle = 0
        else:
            idle += 1
            # the subsession has finished (.exit file) and there is nothing left to read: this is the real end
            if os.path.exists(exitf) and idle >= 3:
                code = open(exitf).read().strip()
                if last is not None:
                    # a `result` (even an intermediate one) followed by a non-zero exit is a failure: ✖
                    if code != "0":
                        last = "✖ " + T("phase-events.exit_after", code=code, last=last.lstrip("■✖ "))
                    emit(last)
                    with open(resf, "w", encoding="utf-8") as f:
                        f.write(last)
                    sys.exit(0 if code == "0" else 1)
                emit("✖ " + T("phase-events.no_result", code=code, log=os.path.basename(log)))
                sys.exit(1)
        time.sleep(1)


def handle(ev, agents):
    t = ev.get("type")
    top = ev.get("parent_tool_use_id") is None
    if t == "assistant":
        for b in ev.get("message", {}).get("content", []) or []:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "text" and top:
                for ln in b.get("text", "").splitlines():
                    ln = ln.strip()
                    if ln.startswith("▶"):
                        emit(short(ln))
            elif b.get("type") == "tool_use":
                name, inp = b.get("name"), b.get("input") or {}
                if name in ("Agent", "Task"):
                    desc = f"{inp.get('subagent_type', T('phase-events.agent'))}: {inp.get('description', '')}"
                    agents[b.get("id")] = desc
                    emit(short("  · " + T("phase-events.launches", desc=desc)))
                elif name == "Skill" and top:
                    emit(short(f"  · skill /{inp.get('skill', '?')} {inp.get('args', '')}"))
    elif t == "user":
        for b in ev.get("message", {}).get("content", []) or []:
            if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("tool_use_id") in agents:
                txt = text_of(b.get("content"))
                dec = next((l.strip() for l in txt.splitlines() if l.strip().startswith("Decision:")), None)
                emit(short(f"    ← {agents.pop(b.get('tool_use_id'))} → {dec or T('phase-events.done')}"))
    elif t == "result":
        res = ev.get("result") or ""
        esito = next((l.strip() for l in reversed(res.splitlines()) if l.strip().startswith(("PHASE RESULT", "ESITO FASE"))), None)
        mins = round((ev.get("duration_ms") or 0) / 60000, 1)
        cost = ev.get("total_cost_usd")
        extra = f" · {mins} min · {ev.get('num_turns', '?')} " + T("phase-events.turns") + (f" · ${cost:.2f}" if isinstance(cost, (int, float)) else "")
        mark = "✖" if ev.get("is_error") else "■"
        # progress line, not an end line: the end is decided by the .exit file (see main)
        emit(short("  · " + T("phase-events.turn_done") + (esito or T("phase-events.no_line")) + extra, 400))
        return short(f"{mark} {esito or T('phase-events.phase_done')}{extra}", 400)
    return None


if __name__ == "__main__":
    main()
