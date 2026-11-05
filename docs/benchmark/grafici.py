#!/usr/bin/env python3
"""grafici.py — the four charts of the Maat benchmark, as static SVG files (standard library only).

    python3 grafici.py [--records DIR] [--out DIR] [--progress]

Reads every `<records>/<run-id>/record.json` (the format of run-record.template.json; default: the `records/`
folder next to this file, where the published raw records go) and writes into `<out>` (default: `grafici/` next
to this file):

    undisclosed-defects.svg   measure 1: undisclosed defects per run
    hidden-tests.svg          measure 2: share of hidden acceptance tests passed
    blind-review.svg          measure 3: defects confirmed from the blind review
    cost-time.svg             measure 4: API-equivalent cost and wall-clock time (two panels, one scale each)

Each chart: the five tasks, Maat and baseline side by side, the median of the runs available as a bar and their
range (min–max) as a whisker, and the number of runs behind each bar («n=2 of 3»). A value that is not there yet
(null in the record: the blind review and the adjudication come only after all 30 runs) is drawn as «not yet
available», never as zero. `--progress` also prints the «Progress» table of the README (markdown).

The output depends only on the records: the same records give the same bytes (no date, no random id).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

TASKS = ("T1", "T2", "T3", "T4", "T5")
SIDES = ("maat", "baseline")
PLANNED = 3                      # runs per task and side (protocol)
SIDE_LABEL = {"maat": "Maat", "baseline": "Baseline"}

# Colours: one light surface on every theme (GitHub shows an SVG as an image: an explicit background is the only
# way to read the same in light and dark mode). Categorical slots 1 and 2 of the reference palette; the two sides
# also differ without colour: Maat is solid, the baseline hatched, and every bar is labelled under the axis.
SURFACE, BORDER = "#fcfcfb", "#d9d8d3"
INK, INK2, MUTED, GRID = "#0b0b0b", "#52514e", "#8a8984", "#e6e5e0"
FILL = {"maat": "#2a78d6", "baseline": "#eb6834"}
FONT = "font-family=\"-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif\""

W = 780
LEFT, RIGHT = 74, 20
GROUP_W = (W - LEFT - RIGHT) / len(TASKS)
BAR_W, BAR_GAP = 38, 16


# ---- data ---------------------------------------------------------------------------------------------------------

def _count(v):
    return float(len(v)) if isinstance(v, list) else None


def _confirmed_review(rec):
    entries = rec.get("blind_review_entries")
    if not isinstance(entries, list):
        return None
    return float(sum(1 for e in entries if isinstance(e, dict) and e.get("verdict") == "confirmed"))


def _hidden_share(rec):
    h = rec.get("hidden_tests")
    if not isinstance(h, dict):
        return None
    p, t = h.get("passed"), h.get("total")
    if not isinstance(p, (int, float)) or not isinstance(t, (int, float)) or isinstance(p, bool) or t <= 0:
        return None
    return 100.0 * p / t


def _num(rec, key, scale=1.0):
    v = rec.get(key)
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    return float(v) * scale


MEASURES = {
    "undisclosed": lambda r: _count(r.get("undisclosed_defects")),
    "hidden": _hidden_share,
    "review": _confirmed_review,
    "cost": lambda r: _num(r, "cost_usd_api_equivalent"),
    "time": lambda r: _num(r, "wall_clock_s", 1 / 60.0),
}


def load(records_dir):
    """{run_id: record} from <records_dir>/*/record.json, sorted; a missing folder is no record."""
    out = {}
    if not os.path.isdir(records_dir):
        return out
    for name in sorted(os.listdir(records_dir)):
        f = os.path.join(records_dir, name, "record.json")
        if not os.path.isfile(f):
            continue
        with open(f, encoding="utf-8") as fh:
            rec = json.load(fh)
        rid, task, side = rec.get("run_id"), rec.get("task"), rec.get("side")
        if task not in TASKS or side not in SIDES or not isinstance(rid, str):
            raise SystemExit("grafici: %s: task, side or run_id not valid" % f)
        if rid in out:
            raise SystemExit("grafici: run %s twice" % rid)
        out[rid] = rec
    return out


def values(records, measure):
    """{(task, side): [finite values]} — a value that is null, missing or not finite is not there yet."""
    fn, res = MEASURES[measure], {(t, s): [] for t in TASKS for s in SIDES}
    for rid in sorted(records):
        r = records[rid]
        v = fn(r)
        if v is not None and math.isfinite(v):
            res[(r["task"], r["side"])].append(v)
    return res


def median(xs):
    s, n = sorted(xs), len(xs)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


def nice_max(v):
    """The smallest of 1, 2, 2.5, 5 × 10^k that is >= v (at least 1)."""
    if v <= 1:
        return 1.0
    k = 10 ** math.floor(math.log10(v))
    for m in (1, 2, 2.5, 5, 10):
        if m * k >= v - 1e-9:
            return float(m * k)
    return float(10 * k)


def int_max(v):
    """For counts: the smallest multiple of 4 that is >= v (at least 4), so the four grid steps are integers."""
    return float(max(4, 4 * math.ceil(v / 4.0)))


def fmt(v, digits):
    s = "%.*f" % (digits, v)
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# ---- svg ----------------------------------------------------------------------------------------------------------

def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def text(x, y, s, size=12, color=INK, anchor="start", weight=None, extra=""):
    w = ' font-weight="%s"' % weight if weight else ""
    return '<text x="%s" y="%s" font-size="%d" fill="%s" text-anchor="%s"%s%s>%s</text>' % (
        fmt(x, 1), fmt(y, 1), size, color, anchor, w, extra, esc(s))


def bar_path(x, y0, h, w, r=4):
    """A bar from the baseline y0 up by h, with rounded top corners only."""
    if h < r + 1:
        return "M%s %sh%sv%sh%sz" % (fmt(x, 1), fmt(y0, 1), fmt(w, 1), fmt(-h, 1), fmt(-w, 1))
    top = y0 - h
    return ("M{x} {b}V{t1}Q{x} {t} {xr} {t}H{xl}Q{x2} {t} {x2} {t1}V{b}z".format(
        x=fmt(x, 1), b=fmt(y0, 1), t1=fmt(top + r, 1), t=fmt(top, 1), xr=fmt(x + r, 1),
        xl=fmt(x + w - r, 1), x2=fmt(x + w, 1)))


def defs():
    return ('<defs><pattern id="hatch" patternUnits="userSpaceOnUse" width="6" height="6" '
            'patternTransform="rotate(45)"><rect width="6" height="6" fill="%s"/>'
            '<line x1="0" y1="0" x2="0" y2="6" stroke="%s" stroke-width="2.4"/></pattern></defs>'
            % (FILL["baseline"], SURFACE))


def fill_of(side):
    return FILL["maat"] if side == "maat" else "url(#hatch)"


def legend(y):
    x = W - RIGHT - 300
    out = ['<rect x="%d" y="%d" width="14" height="14" rx="2" fill="%s"/>' % (x, y - 11, FILL["maat"]),
           text(x + 20, y, "Maat (solid)", 12, INK2),
           '<rect x="%d" y="%d" width="14" height="14" rx="2" fill="url(#hatch)" stroke="%s" stroke-width="1"/>'
           % (x + 120, y - 11, FILL["baseline"]),
           text(x + 140, y, "Baseline (hatched)", 12, INK2)]
    return out


def panel(vals, top, height, unit, digits, fixed_max=None, axis_label=""):
    # fixed_max: a number (fixed scale), "int" (counts: integer grid) or None (a round maximum)
    """One bar panel: y from top to top+height. Returns the SVG lines."""
    out = []
    base = top + height
    present = [v for xs in vals.values() for v in xs]
    top_v = max(present) if present else 0.0
    if fixed_max == "int":
        ymax = int_max(top_v)
    else:
        ymax = fixed_max if fixed_max is not None else nice_max(top_v if present else 1.0)
    for i in range(5):                                  # grid and y ticks
        v = ymax * i / 4
        y = base - height * i / 4
        out.append('<line x1="%d" y1="%s" x2="%d" y2="%s" stroke="%s" stroke-width="1"/>'
                   % (LEFT, fmt(y, 1), W - RIGHT, fmt(y, 1), GRID if i else MUTED))
        out.append(text(LEFT - 8, y + 4, fmt(v, 2) + unit, 11, INK2, "end"))
    if axis_label:
        out.append(text(16, top + height / 2, axis_label, 11, INK2, "middle",
                        extra=' transform="rotate(-90 16 %s)"' % fmt(top + height / 2, 1)))
    for gi, task in enumerate(TASKS):
        gx = LEFT + GROUP_W * gi + (GROUP_W - 2 * BAR_W - BAR_GAP) / 2
        for si, side in enumerate(SIDES):
            x = gx + si * (BAR_W + BAR_GAP)
            cx = x + BAR_W / 2
            xs = vals[(task, side)]
            label = "Maat" if side == "maat" else "Base"
            out.append(text(cx, base + 15, label, 11, INK2, "middle"))
            out.append(text(cx, base + 28, "n=%d of %d" % (len(xs), PLANNED), 10, MUTED, "middle"))
            if not xs:
                out.append('<rect x="%s" y="%s" width="%d" height="%s" rx="4" fill="none" stroke="%s" '
                           'stroke-dasharray="3 3"/>' % (fmt(x, 1), fmt(top, 1), BAR_W, fmt(height, 1), BORDER))
                ty = top + height / 2
                out.append(text(cx + 4, ty, "not yet available", 10, MUTED, "middle",
                                extra=' transform="rotate(-90 %s %s)"' % (fmt(cx + 4, 1), fmt(ty, 1))))
                continue
            med, lo, hi = median(xs), min(xs), max(xs)
            h = height * med / ymax
            if h > 0:
                out.append('<path d="%s" fill="%s"/>' % (bar_path(x, base, h, BAR_W), fill_of(side)))
            else:                                       # a median of zero is drawn, not left empty
                out.append('<rect x="%s" y="%s" width="%d" height="2" fill="%s"/>'
                           % (fmt(x, 1), fmt(base - 2, 1), BAR_W, FILL[side]))
            ylo, yhi = base - height * lo / ymax, base - height * hi / ymax
            if hi > lo:
                out.append('<path d="M%s %sV%sM%s %sH%sM%s %sH%s" stroke="%s" stroke-width="1.5" fill="none"/>'
                           % (fmt(cx, 1), fmt(ylo, 1), fmt(yhi, 1), fmt(cx - 6, 1), fmt(ylo, 1), fmt(cx + 6, 1),
                              fmt(cx - 6, 1), fmt(yhi, 1), fmt(cx + 6, 1), INK))
            out.append(text(cx, min(yhi, base - h) - 5, fmt(med, digits) + unit, 10, INK, "middle"))
        out.append(text(LEFT + GROUP_W * gi + GROUP_W / 2, base + 46, task, 13, INK, "middle", "600"))
    return out


def chart(title, subtitle, panels):
    """panels: list of (heading, vals, unit, digits, fixed_max, axis_label)."""
    ph, gap, head = 220, 78, 92
    height = head + len(panels) * (ph + gap) + 6
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" role="img" '
           'aria-labelledby="t d" %s>' % (W, height, W, height, FONT),
           '<title id="t">%s</title><desc id="d">%s</desc>' % (esc(title), esc(subtitle)), defs(),
           '<rect x="0.5" y="0.5" width="%d" height="%d" rx="8" fill="%s" stroke="%s"/>'
           % (W - 1, height - 1, SURFACE, BORDER),
           text(LEFT - 50, 30, title, 17, INK, weight="600"), text(LEFT - 50, 50, subtitle, 12, INK2)]
    out += legend(74)
    y = head
    for heading, vals, unit, digits, fmax, alabel in panels:
        if heading:
            out.append(text(LEFT, y + 4, heading, 13, INK, weight="600"))
            y += 16
        out += panel(vals, y, ph, unit, digits, fmax, alabel)
        y += ph + gap - (16 if heading else 0)
    out.append("</svg>")
    return "\n".join(out) + "\n"


SUB = "Median of the runs available (bar) and their range, min–max (whisker); n = runs behind each bar."


def build(records):
    """{file name: svg text}."""
    def avail_note(vals):
        return "" if any(vals.values()) else " Not yet available: filled in after all 30 runs."
    v_und, v_hid, v_rev = values(records, "undisclosed"), values(records, "hidden"), values(records, "review")
    v_cost, v_time = values(records, "cost"), values(records, "time")
    return {
        "undisclosed-defects.svg": chart(
            "Undisclosed defects per run (lower is better)", SUB + avail_note(v_und),
            [("", v_und, "", 1, "int", "defects")]),
        "hidden-tests.svg": chart(
            "Hidden acceptance tests passed (higher is better)", SUB + avail_note(v_hid),
            [("", v_hid, "%", 0, 100.0, "share passed")]),
        "blind-review.svg": chart(
            "Defects confirmed from the blind review (lower is better)", SUB + avail_note(v_rev),
            [("", v_rev, "", 1, "int", "defects")]),
        "cost-time.svg": chart(
            "Cost and wall-clock time per run", SUB,
            [("API-equivalent cost (USD)", v_cost, "", 2, None, "USD"),
             ("Wall-clock time (minutes)", v_time, "", 0, None, "minutes")]),
    }


def progress(records):
    """The «Progress» table: runs recorded per task and side, out of 3, and the total out of 30."""
    n = {(t, s): 0 for t in TASKS for s in SIDES}
    for r in records.values():
        n[(r["task"], r["side"])] += 1
    lines = ["| Task | Maat | Baseline |", "|---|---|---|"]
    for t in TASKS:
        lines.append("| %s | %d of %d | %d of %d |" % (t, n[(t, "maat")], PLANNED, n[(t, "baseline")], PLANNED))
    lines.append("| **All** | %d of 15 | %d of 15 |" % (sum(n[(t, "maat")] for t in TASKS),
                                                       sum(n[(t, "baseline")] for t in TASKS)))
    status = ("complete" if len(records) == 30 else "not started: 0 of 30" if not records
              else "partial: %d of 30" % len(records))
    return "Status: **%s**\n\n%s\n" % (status, "\n".join(lines))


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="The charts of the Maat benchmark (static SVG).")
    ap.add_argument("--records", default=os.path.join(here, "records"))
    ap.add_argument("--out", default=os.path.join(here, "grafici"))
    ap.add_argument("--progress", action="store_true", help="also print the Progress table (markdown)")
    a = ap.parse_args(argv)
    recs = load(a.records)
    os.makedirs(a.out, exist_ok=True)
    for name, svg in sorted(build(recs).items()):
        with open(os.path.join(a.out, name), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(svg)
    print("grafici: %d records, 4 charts in %s" % (len(recs), a.out))
    if a.progress:
        sys.stdout.write(progress(recs))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
