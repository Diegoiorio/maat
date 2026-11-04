#!/usr/bin/env python3
"""attese.py — the two pure parts of tools/esempi-equiv/attese.sh (Maat 1.6.0): the normalization and the comparison.

    attese.py normalizza <forms file>            stdin -> stdout, every form replaced by its token
    attese.py confronta <expected> <computed> [<mini-repo>…]
                                                 block by block; exit 0 equal, 1 different (listed), 2 usage

FORMS FILE: one form per line, «<kind><TAB><token><TAB><form>» (UTF-8). attese.sh writes it; the closed list of the
normalizations is in its header (and in docs/TESTING-harness.md, «The expected outputs»):
  path  a root (<REPO>, <MAAT>) in one of its forms; replaced only at the boundary of a path: not preceded by a
        character of a path (letter, digit, . _ ~ - /) and not followed by a character that continues the last name
        (letter, digit, _ ~ -, or a «.» followed by one of them: a «.» that ends a sentence is not part of the name);
        a «/» after it is the rest of the path and stays;
  hex   a fingerprint (<impronta-attuale>, 64 digits and its first 12); replaced only when no hex digit is next to it.
All the forms of a file are tried at each position from the longest to the shortest, forms of the same length all kept
(two forms of one root can have the same length: C:/Users/… and /c/Users/…), in one pass: a token is never rewritten.

BLOCKS: a block starts with a line «== <mini-repo>/<spec or jsonl>» (no space after «== » up to the end of the line,
and a «/» in it) and runs to the next one. `confronta` takes from <expected> only the blocks of the mini-repos given
(all if none), and prints one line per difference: «DIVERSO <block>», «MANCA <block>» (expected, not computed),
«IN PIU <block>» (computed, not expected), «ORDINE» (same blocks, another order); then the unified diff of the blocks
that differ (at most 80 lines). The bytes are compared as they are (attese.sh removes the CRs before).
"""
import difflib
import re
import sys

PATH_PRIMA = rb"(?<![A-Za-z0-9._~/-])"
PATH_DOPO = rb"(?![A-Za-z0-9_~-]|\.[A-Za-z0-9_~-])"
HEX_PRIMA = rb"(?<![0-9a-f])"
HEX_DOPO = rb"(?![0-9a-f])"
HEAD = re.compile(rb"^== ([^ /]+)/[^ ]+$")


def leggi_forme(path):
    forme = []
    for n, l in enumerate(open(path, "rb").read().split(b"\n"), 1):
        l = l.rstrip(b"\r")
        if not l:
            continue
        p = l.split(b"\t", 2)
        if len(p) != 3 or p[0] not in (b"path", b"hex") or not p[1] or not p[2]:
            sys.stderr.write("attese.py: forms file, line %d: <path|hex><TAB><token><TAB><form>\n" % n)
            sys.exit(2)
        forme.append(tuple(p))
    return forme


def normalizza(forme, data):
    if not forme:
        return data
    uniche, visti = [], set()
    for kind, tok, f in forme:
        if f not in visti:
            visti.add(f)
            uniche.append((kind, tok, f))
    uniche.sort(key=lambda x: -len(x[2]))   # stable: the same length keeps every form, in the order given
    alt = [(PATH_PRIMA + re.escape(f) + PATH_DOPO) if kind == b"path" else (HEX_PRIMA + re.escape(f) + HEX_DOPO)
           for kind, tok, f in uniche]
    tok = {f: t for _k, t, f in uniche}
    rx = re.compile(b"|".join(b"(?:" + a + b")" for a in alt))
    return rx.sub(lambda m: tok[m.group(0)], data)


def blocchi(data):
    """[(header, text of the block)] in order; the lines before the first header form a block with header b""."""
    out, cur, buf = [], b"", []
    for l in data.split(b"\n"):
        m = HEAD.match(l)
        if m and not l.startswith(b"== exit"):
            if cur or buf:
                out.append((cur, b"\n".join(buf)))
            cur, buf = l[3:], [l]
        else:
            buf.append(l)
    if cur or buf:
        out.append((cur, b"\n".join(buf)))
    return out


def confronta(a_path, b_path, repos):
    try:
        a = open(a_path, "rb").read()
    except OSError:
        a = None
    b = open(b_path, "rb").read()
    if a is None:
        print("MANCA il file delle attese: %s" % a_path)
        return 1
    ba, bb = blocchi(a), blocchi(b)
    if repos:
        sel = lambda h: h.split(b"/", 1)[0].decode("utf-8", "replace") in repos
        ba = [x for x in ba if x[0] and sel(x[0])]
        bb = [x for x in bb if x[0] and sel(x[0])]
    da, db = dict(ba), dict(bb)
    righe, diff = [], []
    for h, t in ba:
        if h not in db:
            righe.append("MANCA " + h.decode("utf-8", "replace"))
        elif db[h] != t:
            righe.append("DIVERSO " + h.decode("utf-8", "replace"))
            diff += difflib.unified_diff(t.decode("utf-8", "replace").split("\n"), db[h].decode("utf-8", "replace").split("\n"),
                                         "attese", "calcolate", lineterm="", n=0)
    for h, _t in bb:
        if h not in da:
            righe.append("IN PIU " + h.decode("utf-8", "replace"))
    if not righe and [h for h, _ in ba] != [h for h, _ in bb]:
        righe.append("ORDINE")
    for r in righe:
        print(r)
    for l in diff[:80]:
        print("    " + l)
    return 1 if righe else 0


def main(argv):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace", newline="\n")
    if len(argv) == 2 and argv[0] == "normalizza":
        sys.stdout.flush()
        sys.stdout.buffer.write(normalizza(leggi_forme(argv[1]), sys.stdin.buffer.read()))
        return 0
    if len(argv) >= 3 and argv[0] == "confronta":
        return confronta(argv[1], argv[2], set(argv[3:]))
    sys.stderr.write("usage: attese.py normalizza <forms file> | confronta <expected> <computed> [<mini-repo>…]\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
