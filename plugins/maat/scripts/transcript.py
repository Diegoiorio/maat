#!/usr/bin/env python3
"""transcript.py — what a phase did, read from its session transcript (Maat 1.8.0, §Tassonomia, D2, D3, A1).

    transcript.py bash <comando> <estratto>                       < <jsonl>
        a Bash call of the MAIN session whose input.command is exactly <comando> and one of whose results
        contains <estratto> (an Executed proof: line of a plan, D3)
    transcript.py agente <subagent_type> <testo d'input>… <testo di risultato>    < <jsonl>
        an Agent/Task call of the MAIN session with exactly that subagent_type, whose input.prompt contains every
        <testo d'input> and whose result contains <testo di risultato> (the deviation judge of test-red, A1)
    transcript.py conta <subagent_type> <jsonl>…
        the number of results of the Agent/Task calls with exactly that subagent_type, on the MAIN sessions of all the
        files (the budget of the plan, D3)

The jsonl is the log of a phase (`claude -p --output-format stream-json`, run-phase.sh: log/<label>.jsonl) or a
Claude session transcript: both have the assistant/user events with message.content blocks (tool_use, tool_result).
MAIN SESSION: an event with `isSidechain: true` (session transcript) or a non-null `parent_tool_use_id` (stream-json:
the messages of a sub-agent) is not the main session and never counts, neither as a call nor as a result.
Texts: CRs dropped from the haystack and from the texts searched (<comando> is compared as it is, byte for byte). An
empty <estratto>, input text or result text is a usage error: an empty string is contained in everything.
A RESULT is a tool_result of the main session with the tool_use_id of the call. For an agent it is never the launch
receipt of an asynchronous agent ("Async agent launched", tool_use_result.status async_launched: no verdict in it); for
`conta` an is_error result does not count either (the reviewer did not answer).

Exits: bash, agente: 0 found (stdout: one line with the lines of the call and of the result), 1 not found, 2 usage or
transcript unreadable. conta: 0 and the number on stdout; 2 usage or a file unreadable (no number: a count that misses
a file is no proof).

Imported (driver.py classifica, 1.8.0 B8; the checks of B10/B13), the same rules: righe(path), bash_trovato(righe, …),
agente_trovato(righe, …), conta_risultati(paths, tipo), aperti_alla_chiusura(righe) — the agents and background jobs
of the main session still open at a CLOSING of the session: a `system/init` after the first (the session woken up
again: the previous turn had closed), a `result` event, the end of the file. Opened by: a Bash result "running in
background with ID: <id>", an Agent/Task result "Async agent launched … agentId: <id>"; closed by: a
`<task-notification>` with that <task-id> and a final <status>, a `system` task_notification/task_updated event
with that task_id and a final status, a BashOutput/TaskOutput showing a final status, TaskStop/KillShell on the id.
This file uses no syntax newer than Python 3.7 (as driver.py, which imports it). Test: transcript.test.sh.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AGENT_TOOLS = ("Agent", "Task")
BG_RE = re.compile(r"in background with ID: ([A-Za-z0-9_-]+)")
AGENT_BG_RE = re.compile(r"Async agent launched")
AGENT_ID_RE = re.compile(r"agentId: ([A-Za-z0-9_-]+)")
NOTIF_RE = re.compile(r"<task-id>([A-Za-z0-9_-]+)</task-id>(.*?)</task-notification>", re.S)
FINALI = ("completed", "failed", "killed", "stopped", "exited", "error", "cancelled")
DONE_RE = re.compile(r"<status>(%s)</status>" % "|".join(FINALI))
OUTPUT_TOOLS = ("BashOutput", "TaskOutput")
KILL_TOOLS = ("TaskStop", "KillShell", "KillBash")
ID_KEYS = ("task_id", "bash_id", "shell_id", "id")


def righe(path):
    """the lines of a jsonl file (OSError if unreadable)"""
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read().split("\n")


def _eventi(rr):
    """(line number, event) of every JSON object line"""
    for n, l in enumerate(rr, 1):
        try:
            ev = json.loads(l)
        except ValueError:
            continue
        if isinstance(ev, dict):
            yield n, ev


def principale(ev):
    """the event belongs to the main session: not a sidechain, not the message of a sub-agent"""
    return ev.get("isSidechain") is not True and ev.get("parent_tool_use_id") in (None, "")  # SESSIONE-PRINCIPALE


def testo(content):
    """the text of a content (a string or a list of blocks), CRs dropped"""
    if isinstance(content, str):
        return content.replace("\r", "")
    if isinstance(content, list):
        return "\n".join(testo(c.get("text") if isinstance(c, dict) and c.get("type") == "text"
                               else c.get("content") if isinstance(c, dict) else c) for c in content)
    return ""


def _blocchi(ev):
    msg = ev.get("message") if isinstance(ev.get("message"), dict) else {}
    c = msg.get("content")
    return [b for b in c if isinstance(b, dict)] if isinstance(c, list) else []


def chiamate(rr):
    """the tool calls of the main session, in order: [{id, name, input, line, results: [(line, text, error,
    async)]}]"""
    per_id, ordine = {}, []
    for n, ev in _eventi(rr):
        if not principale(ev):
            continue
        tipo = ev.get("type")
        for b in _blocchi(ev):
            if tipo == "assistant" and b.get("type") == "tool_use":
                inp = b.get("input") if isinstance(b.get("input"), dict) else {}
                c = {"id": b.get("id"), "name": b.get("name") or "", "input": inp, "line": n, "results": []}
                if c["id"] and c["id"] not in per_id:
                    per_id[c["id"]] = c
                    ordine.append(c)
            elif tipo == "user" and b.get("type") == "tool_result" and b.get("tool_use_id") in per_id:
                t = testo(b.get("content"))
                tur = ev.get("tool_use_result")
                asin = bool(AGENT_BG_RE.search(t[:300])) or (isinstance(tur, dict) and (
                    tur.get("status") == "async_launched" or tur.get("isAsync") is True))
                per_id[b["tool_use_id"]]["results"].append((n, t, b.get("is_error") is True, asin))
    return ordine


def bash_trovato(rr, comando, estratto):
    """(line of the call, line of the result) of the first Bash call with exactly that command and a result that
    contains the excerpt; None"""
    e = estratto.replace("\r", "")
    for c in chiamate(rr):
        if c["name"] != "Bash" or c["input"].get("command") != comando:  # COMANDO-ESATTO
            continue
        for n, t, _err, _asin in c["results"]:
            if e in t:  # ESTRATTO-NEL-RISULTATO
                return c["line"], n
    return None


def agente_trovato(rr, tipo, ingressi, risultato):
    """(line of the call, line of the result) of the first Agent/Task call with exactly that subagent_type, whose
    prompt contains every input text, with a result (not an asynchronous launch) that contains `risultato`; None"""
    ii = [x.replace("\r", "") for x in ingressi]
    r = risultato.replace("\r", "")
    for c in chiamate(rr):
        if c["name"] not in AGENT_TOOLS or c["input"].get("subagent_type") != tipo:
            continue
        p = testo(c["input"].get("prompt"))
        if not all(x in p for x in ii):  # INGRESSI-NEL-PROMPT
            continue
        for n, t, _err, asin in c["results"]:
            if not asin and r in t:
                return c["line"], n
    return None


def conta_risultati(paths, tipo):
    """the results of the Agent/Task calls with exactly that subagent_type on the main sessions of the files: one per
    call that has a result that is not an error and not an asynchronous launch (OSError if a file is unreadable)"""
    k = 0
    for p in paths:
        for c in chiamate(righe(p)):
            if c["name"] in AGENT_TOOLS and c["input"].get("subagent_type") == tipo and any(
                    not err and not asin for _n, _t, err, asin in c["results"]):  # RISULTATO-CONTATO
                k += 1
    return k


def aperti_alla_chiusura(rr):
    """the ids (agents and background jobs of the main session) open at a closing of the session, in launch order"""
    usi, aperti, chiusi, visti = {}, [], set(), []
    init = 0

    def chiusura():
        for j in aperti:
            if j not in chiusi and j not in visti:
                visti.append(j)

    for _n, ev in _eventi(rr):
        tipo, sub = ev.get("type"), ev.get("subtype")
        if tipo == "system" and sub == "init":
            init += 1
            if init > 1:   # the session woken up again: its previous turn had closed
                chiusura()
            continue
        if tipo == "result":
            chiusura()
            continue
        for s in _stringhe(ev):
            if "<task-notification>" in s:
                for tid, body in NOTIF_RE.findall(s):
                    if DONE_RE.search(body):
                        chiusi.add(tid)
        if tipo == "system" and sub in ("task_notification", "task_updated") and ev.get("task_id"):
            st = ev.get("status")
            patch = ev.get("patch")
            if isinstance(patch, dict):
                st = patch.get("status", st)
            if st in FINALI:
                chiusi.add(str(ev["task_id"]))
            continue
        if not principale(ev):
            continue
        for b in _blocchi(ev):
            if tipo == "assistant" and b.get("type") == "tool_use":
                nome, inp = b.get("name") or "", b.get("input") if isinstance(b.get("input"), dict) else {}
                usi[b.get("id")] = (nome, inp)
                if nome in KILL_TOOLS:
                    chiusi.update(str(inp[k]) for k in ID_KEYS if inp.get(k))
            elif tipo == "user" and b.get("type") == "tool_result":
                nome, inp = usi.get(b.get("tool_use_id"), ("", {}))
                t = testo(b.get("content"))
                tur = ev.get("tool_use_result") if isinstance(ev.get("tool_use_result"), dict) else {}
                if nome == "Bash":
                    m = BG_RE.search(t[:300])
                    if m and m.group(1) not in aperti:
                        aperti.append(m.group(1))
                elif nome in AGENT_TOOLS and (AGENT_BG_RE.search(t[:300]) or tur.get("status") == "async_launched"):
                    m = AGENT_ID_RE.search(t[:1000])
                    j = m.group(1) if m else str(tur.get("agentId") or "")
                    if j and j not in aperti:
                        aperti.append(j)
                elif nome in OUTPUT_TOOLS and DONE_RE.search(t):
                    chiusi.update(str(inp[k]) for k in ID_KEYS if inp.get(k))
    chiusura()   # the end of the file
    return visti


def _stringhe(obj):
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for v in obj.values():
            for s in _stringhe(v):
                yield s
    elif isinstance(obj, list):
        for v in obj:
            for s in _stringhe(v):
                yield s


def T(k, **kw):
    sys.dont_write_bytecode = True
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    from maat_msg import T
    return T(k, **kw)


def _uso():
    print(T("transcript-180.usage"), file=sys.stderr)
    return 2


def _stdin():
    data = sys.stdin.buffer.read()
    return data.decode("utf-8", errors="replace").split("\n")


def main(argv):
    try:
        sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    except (AttributeError, ValueError):
        pass
    if not argv:
        return _uso()
    cmd, rest = argv[0], argv[1:]
    if cmd == "bash":
        if len(rest) != 2 or not rest[0] or not rest[1].replace("\r", ""):
            return _uso()
        trov = bash_trovato(_stdin(), rest[0], rest[1])
    elif cmd == "agente":
        if len(rest) < 3 or not rest[0] or not all(x.replace("\r", "") for x in rest[1:]):
            return _uso()
        trov = agente_trovato(_stdin(), rest[0], rest[1:-1], rest[-1])
    elif cmd == "conta":
        if len(rest) < 2 or not rest[0]:
            return _uso()
        try:
            k = conta_risultati(rest[1:], rest[0])
        except OSError as e:
            print(T("transcript-180.unreadable", f=getattr(e, "filename", "") or "", e=e.strerror or e),
                  file=sys.stderr)
            return 2
        print(k)
        return 0
    else:
        return _uso()
    if trov is None:
        print(T("transcript-180.not_found"))
        return 1
    print(T("transcript-180.found", call=trov[0], res=trov[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
