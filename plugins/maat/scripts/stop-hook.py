#!/usr/bin/env python3
"""stop-hook.py — hook `Stop` delle sotto-sessioni di /full-implementation-cycle (harness-pt04, 1g).

run-phase.sh lo passa con --settings accanto a guard.py. Una sotto-sessione `-p` che chiude il turno
senza la riga `ESITO FASE`, o mentre un suo job in background non e' ancora stato raccolto, finisce li'
(«attesa passiva»: nessuno la risveglia). L'hook NEGA la fine del turno in due casi:
  1. l'ultimo messaggio dell'assistente (il testo dopo l'ultima chiamata di tool) non contiene una riga
     `ESITO FASE <fase>: OK|STOP` (il formato JSON arrivera' con pt08);
  2. il transcript mostra job lanciati in background (Bash, «running in background with ID: <id>») non
     raccolti: nessuna notifica `<task-notification>` di quel <task-id> con <status> finale, nessun
     BashOutput/TaskOutput che ne mostri lo stato finale, nessun TaskStop/KillShell su quell'id.

Contro il loop: con `stop_hook_active` (la sessione sta gia' continuando per un diniego di questo hook)
lascia sempre chiudere. Un hook che fallisce non deve bloccare una sessione: input illeggibile,
transcript assente o qualunque eccezione -> lascia chiudere (uscita 0 senza output).

Uso: stdin = JSON dell'evento Stop (transcript_path, stop_hook_active). Diniego = JSON
{"decision": "block", "reason": ...} su stdout, uscita 0. Test: scripts/stop-hook.test.sh del plugin.
"""
import json
import re
import sys

ESITO_RE = re.compile(r"(?m)^\s*ESITO FASE \S+: (OK|STOP)\b")
BG_RE = re.compile(r"in background with ID: ([A-Za-z0-9_-]+)")
NOTIF_RE = re.compile(r"<task-id>([A-Za-z0-9_-]+)</task-id>(.*?)</task-notification>", re.S)
DONE_RE = re.compile(r"<status>(completed|failed|killed|stopped|exited|error|cancelled)</status>")
OUTPUT_TOOLS = {"BashOutput", "TaskOutput"}
KILL_TOOLS = {"TaskStop", "KillShell", "KillBash"}
ID_KEYS = ("task_id", "bash_id", "shell_id", "id")


def text_of(content):
    """Testo di un content (stringa o lista di blocchi)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(text_of(c.get("text") if isinstance(c, dict) and c.get("type") == "text"
                                 else c.get("content") if isinstance(c, dict) else c) for c in content)
    return ""


def strings(obj):
    """Tutte le stringhe dentro un oggetto JSON (per le notifiche, ovunque stiano)."""
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from strings(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from strings(v)


def analyze(lines):
    """(testo finale dell'assistente, id dei job in background ancora aperti)."""
    uses = {}          # tool_use_id -> (nome, input)
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
            tail = []   # un risultato di tool o un nuovo messaggio: il testo finale viene dopo
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
    except Exception:   # un hook rotto non deve mai trattenere una sessione
        return
    reasons = []
    if open_jobs:
        reasons.append("job in background non raccolti: " + ", ".join(open_jobs)
                       + " — raccoglili (BashOutput/TaskOutput, finche' non sono finiti) o fermali (TaskStop)"
                       " prima di chiudere: in -p nessuno ti risveglia")
    if not ESITO_RE.search(final):
        reasons.append("l'ultimo messaggio non ha la riga `ESITO FASE <fase>: OK — …` o `ESITO FASE <fase>: STOP — …`:"
                       " completa la fase (o fermala con STOP e il motivo) e chiudi con quella riga")
    if reasons:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stdout.write(json.dumps({"decision": "block", "reason": "hook Stop: " + " · ".join(reasons)},
                                    ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
    sys.exit(0)
