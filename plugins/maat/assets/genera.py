"""Maat (Multi-Agent Assurance Toolkit): marchio in stile app. Geometria su griglia 64, un solo colore con i vuoti
ritagliati da una maschera, così funziona a colori, in monocromo e su qualunque sfondo."""
import math
import os

OUT = os.path.dirname(os.path.abspath(__file__))

ORO = "#F2B53A"
LAPIS_1 = "#0F2A5C"
LAPIS_2 = "#1C4E9A"
INCHIOSTRO = "#0F1B33"
BIANCO = "#FFFFFF"

DY = 3
TESTA = (21.5, 30 + DY, 21, 16.5, 5.2)        # x, y, w, h, rx
VISORE = (24.8, 34.6 + DY, 14.4, 7.2, 3.6)
OCCHI = [(29.0, 38.0 + DY, -1), (35.0, 38.0 + DY, 1)]
PIUMA_X, PIUMA_W, PIUMA_BASE, PIUMA_TOP = 29.4, 5.2, 30 + DY, 5.5 + DY
# ala egizia: banda delle copritrici in alto e una fila di remiganti lunghe che scendono a ventaglio
ALA_U = ((24, 31.5 + DY), (14, 24 + DY), (2.5, 21.5 + DY))
ALA_B = ((24, 36.8 + DY), (14.5, 29.8 + DY), (4.6, 26.8 + DY))
N_REMIGANTI = 6


def bz(p0, c, p2, t):
    u = 1 - t
    return (u * u * p0[0] + 2 * u * t * c[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * c[1] + t * t * p2[1])


def ala_sinistra(n=N_REMIGANTI):
    pts_u = [bz(*ALA_U, i / 24) for i in range(25)]
    pts_b = [bz(*ALA_B, i / 24) for i in range(25)]
    polys = [pts_u + pts_b[::-1]]
    g = 0.022
    for i in range(n):
        a = 0.04 + 0.94 * i / n + g
        b = 0.04 + 0.94 * (i + 1) / n - g
        k = i / (n - 1)
        ang = math.radians(98 + 26 * k)            # da quasi verticale (vicino al corpo) a obliqua (verso la punta)
        d = (math.cos(ang), math.sin(ang))
        lun = 13.5 - 4.5 * k
        b1, b2 = bz(*ALA_B, a), bz(*ALA_B, b)
        e1 = (b1[0] + d[0] * lun, b1[1] + d[1] * lun)
        e2 = (b2[0] + d[0] * lun, b2[1] + d[1] * lun)
        polys.append([(b1[0], b1[1] - 0.6), (b2[0], b2[1] - 0.6), e2, e1])
    return polys


def poligono(pts):
    return '<polygon points="' + " ".join(f"{x:.2f},{y:.2f}" for x, y in pts) + '" stroke-linejoin="round"/>'


def piuma_path():
    """Piuma di Maat (geroglifico H6): fusto dritto, cima che si ripiega in avanti e ricade a uncino."""
    x0, w, b, t = PIUMA_X, PIUMA_W, PIUMA_BASE, PIUMA_TOP
    return (f"M{x0} {b} V{t + 1.1*w:.2f} "
            f"C{x0} {t - 0.1*w:.2f} {x0 + 1.1*w:.2f} {t - 0.35*w:.2f} {x0 + 1.65*w:.2f} {t + 0.45*w:.2f} "
            f"C{x0 + 1.9*w:.2f} {t + 0.85*w:.2f} {x0 + 1.8*w:.2f} {t + 1.45*w:.2f} {x0 + 1.55*w:.2f} {t + 1.8*w:.2f} "
            f"C{x0 + 1.5*w:.2f} {t + 1.45*w:.2f} {x0 + 1.3*w:.2f} {t + 1.15*w:.2f} {x0 + w:.2f} {t + 1.25*w:.2f} "
            f"V{b} Z")


def marchio(col, mid, remiganti=N_REMIGANTI, bande=3, passo_bande=3.6, alto_banda="1.3"):
    """Il marchio. I parametri servono alla variante piccola (16-24 px); i default danno il marchio grande."""
    x, y, w, h, rx = TESTA
    vx, vy, vw, vh, vr = VISORE
    m = [f'<mask id="{mid}" maskUnits="userSpaceOnUse" x="0" y="0" width="64" height="64">',
         '<rect width="64" height="64" fill="#fff"/>',
         f'<rect x="{vx}" y="{vy}" width="{vw}" height="{vh}" rx="{vr}" fill="#000"/>',
         # stacco fra ali e testa, così la testa si stacca dalle ali
         f'<rect x="{x - 1.4}" y="{y - 1.4}" width="{w + 2.8}" height="{h + 2.8}" rx="{rx + 1.4}" fill="#000"/>',
         f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="#fff"/>',
         f'<rect x="{vx}" y="{vy}" width="{vw}" height="{vh}" rx="{vr}" fill="#000"/>']
    for k in range(bande):
        by = PIUMA_TOP + PIUMA_W * 2.25 + k * passo_bande
        m.append(f'<rect x="{PIUMA_X - 1}" y="{by:.2f}" width="{PIUMA_W + 2}" height="{alto_banda}" fill="#000"/>')
    m.append(f'<rect x="{PIUMA_X - 1}" y="{y - 1.6:.2f}" width="{PIUMA_W + 2}" height="1.6" fill="#000"/>')
    m.append('</mask>')
    s = [f'<g mask="url(#{mid})" fill="{col}">']
    for poly in ala_sinistra(remiganti):
        s.append(poligono(poly))
        s.append(poligono([(64 - x, y) for x, y in poly]))
    s.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}"/>')
    s.append(f'<path d="{piuma_path()}"/>')
    s.append('</g>')
    for (ex, ey, side) in OCCHI:
        s.append(f'<circle cx="{ex}" cy="{ey}" r="1.7" fill="{col}"/>')
        s.append(f'<path d="M{ex + side*1.4:.2f} {ey + 0.2:.2f} L{ex + side*3.6:.2f} {ey - 0.3:.2f}" stroke="{col}" stroke-width="1.1" stroke-linecap="round"/>')
    return "\n".join(m + s)


def svg(body, defs=""):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-label="Maat">\n<defs>{defs}</defs>\n{body}\n</svg>\n'


GRADIENTE = (f'<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{LAPIS_2}"/>'
             f'<stop offset="1" stop-color="{LAPIS_1}"/></linearGradient>')


def app(mark=None):
    if mark is None:
        mark = marchio(ORO, "m")
    return svg(f'<rect width="64" height="64" rx="14" fill="url(#bg)"/>\n' + mark, GRADIENTE)


def app_piccola():
    """Icona per 16-24 px: tre remiganti per ala invece di sei (a quella misura si fondono), piuma con due bande."""
    return app(marchio(ORO, "m", remiganti=3, bande=2, passo_bande=4.6, alto_banda="1.8"))


# Logo orizzontale: marchio a sinistra, «maat» in Manrope 800 minuscolo, sottotitolo in maiuscoletto spaziato.
# Il testo resta in <text> (non in tracciati): la conversione richiede fontTools e il file di Manrope, assenti.
# textLength fissa la larghezza del sottotitolo, così l'impaginazione regge anche con il carattere di ripiego.
FONT = "Manrope, 'Segoe UI', Arial, sans-serif"
LOGO_W, TESTO_X = 240, 72


def logo_orizzontale(col, sfondo):
    bg = f'<rect width="{LOGO_W}" height="64" rx="14" fill="url(#bg)"/>\n' if sfondo else ""
    testo = (f'<text x="{TESTO_X}" y="37" fill="{col}" font-family="{FONT}" font-weight="800" font-size="34" '
             f'letter-spacing="-0.5">maat</text>\n'
             f'<text x="{TESTO_X + 1}" y="50" fill="{col}" font-family="{FONT}" font-weight="700" font-size="6.2" '
             f'textLength="158" lengthAdjust="spacing">MULTI-AGENT ASSURANCE TOOLKIT</text>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {LOGO_W} 64" role="img" '
            f'aria-label="Maat — Multi-Agent Assurance Toolkit">\n'
            f'<defs>{GRADIENTE if sfondo else ""}</defs>\n{bg}{marchio(col, "m")}\n{testo}\n</svg>\n')


if __name__ == "__main__":
    files = {
        "maat-icona.svg": app(),
        "maat-marchio-oro.svg": svg(marchio(ORO, "m")),
        "maat-marchio-scuro.svg": svg(marchio(INCHIOSTRO, "m")),
        "maat-marchio-bianco.svg": svg(marchio(BIANCO, "m")),
        "maat-icona-piccola.svg": app_piccola(),
        "maat-logo-orizzontale.svg": logo_orizzontale(ORO, sfondo=True),
        "maat-logo-orizzontale-chiaro.svg": logo_orizzontale(INCHIOSTRO, sfondo=False),
    }
    for name, content in files.items():
        # newline="\n": fine riga LF anche su Windows, così la rigenerazione è identica byte per byte
        with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(content)
    print("scritti:", ", ".join(files))
