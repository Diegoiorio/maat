#!/usr/bin/env python3
"""phase-events.py — trasforma il log stream-json di una sottosessione in righe di avanzamento.

    python3 -u phase-events.py <log.jsonl> <file.exit>

Ogni riga stampata su stdout diventa un aggiornamento nella chat principale (strumento Monitor).
Emette SOLO: le righe "▶ " scritte dalla sottosessione, gli agenti e le skill lanciati, il verdetto
(`Decision:`) di ogni agente, e la fine della fase. Tutto il resto del log (letture, ricerche,
ragionamenti) resta nel file e non entra nel contesto della chat.

La FINE della fase (`■`/`✖`) si emette solo quando esiste <file.exit>, cioe' quando la sottosessione
e' davvero uscita: in `-p` ogni turno intermedio produce un evento `result`, che qui diventa solo una
riga di avanzamento ("· turno concluso"). L'ultimo `result` visto resta in <log>.pending e diventa la
riga di fine quando compare <file.exit>.

Riprende da dove era arrivato (<log>.pos): il Monitor scade dopo 30 minuti e va riarmato, e un
riarmo non deve ripetere gli eventi gia' mostrati. Esce 0 alla fine della fase, 1 se la sottosessione
e' terminata senza un risultato (crash, interruzione) o con .exit diverso da 0 anche dopo un `result`
(riga `✖`): il silenzio non deve sembrare "sta lavorando".
Lo lancia watch-phase.sh con l'interprete di python.sh (FIC_PY), senza WSL.
"""
import json
import os
import sys
import time

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
    pendf = log + ".pending"  # ultima riga di fine candidata: sopravvive al riarmo
    # riarmo dopo la fine della fase: ripete l'esito invece di dire "senza risultato"
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
    agents = {}  # tool_use_id -> descrizione
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
            # un `result` non e' la fine: si ricorda (anche su file, per il riarmo) e si continua
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
            # la sottosessione ha finito (file .exit) e non c'e' piu' niente da leggere: e' la fine vera
            if os.path.exists(exitf) and idle >= 3:
                code = open(exitf).read().strip()
                if last is not None:
                    # un `result` (anche intermedio) seguito da un'uscita non zero e' un fallimento: ✖
                    if code != "0":
                        last = f"✖ sottosessione uscita con exit {code} — ultimo turno: {last.lstrip('■✖ ')}"
                    emit(last)
                    with open(resf, "w", encoding="utf-8") as f:
                        f.write(last)
                    sys.exit(0 if code == "0" else 1)
                emit(f"✖ sottosessione terminata senza risultato (exit {code}) — vedi {os.path.basename(log)} e .stderr")
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
                    desc = f"{inp.get('subagent_type', 'agente')}: {inp.get('description', '')}"
                    agents[b.get("id")] = desc
                    emit(short(f"  · lancia {desc}"))
                elif name == "Skill" and top:
                    emit(short(f"  · skill /{inp.get('skill', '?')} {inp.get('args', '')}"))
    elif t == "user":
        for b in ev.get("message", {}).get("content", []) or []:
            if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("tool_use_id") in agents:
                txt = text_of(b.get("content"))
                dec = next((l.strip() for l in txt.splitlines() if l.strip().startswith("Decision:")), None)
                emit(short(f"    ← {agents.pop(b.get('tool_use_id'))} → {dec or 'finito'}"))
    elif t == "result":
        res = ev.get("result") or ""
        esito = next((l.strip() for l in reversed(res.splitlines()) if l.strip().startswith("ESITO FASE")), None)
        mins = round((ev.get("duration_ms") or 0) / 60000, 1)
        cost = ev.get("total_cost_usd")
        extra = f" · {mins} min · {ev.get('num_turns', '?')} turni" + (f" · ${cost:.2f}" if isinstance(cost, (int, float)) else "")
        mark = "✖" if ev.get("is_error") else "■"
        # riga di avanzamento, non di fine: la fine la decide il file .exit (vedi main)
        emit(short(f"  · turno concluso: {esito or 'nessuna riga ESITO FASE'}{extra}", 400))
        return short(f"{mark} {esito or 'fase finita (nessuna riga ESITO FASE)'}{extra}", 400)
    return None


if __name__ == "__main__":
    main()
