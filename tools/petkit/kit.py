"""kit – Baukasten über petkit: ein Pet wird aus wenigen Zeilen zusammengesteckt.

Pet sammelt weiche Teile (Fell, verschmelzen), harte Teile (Augen, Zubehör), Farbflächen und
Linien. Farben: Name -> Grundfarbe (Schatten wird berechnet) oder (Schatten, Grundfarbe)
oder Verlauf {'stops': [...], 't': fn}. Eine Textur hat Platz für 10 Spalten.
"""
import numpy as np
from petkit import (ellipsoid, sphere, round_cone, chain, round_box, smin, smax, ssub, grad, length,
                    norm, on_ellipsoid, surface, decimate, smooth_boundaries, ribbon, write_glb, srgb)
import struct, zlib

TW, TH, SW, COLS = 256, 128, 12, 21
TEX = TH

def frame(n):
    z = norm(n); up = np.array((0, 1.0, 0)) if abs(z[1]) < .95 else np.array((0, 0, 1.0))
    x = np.cross(up, z); x = x / np.linalg.norm(x); y = np.cross(z, x)
    return np.stack([x, y, z], 1)

# ---------- Feld-Bausteine ----------
def E(c, r, R=None): return lambda p: ellipsoid(p, c, r, R)
def S(c, r): return lambda p: sphere(p, c, r)
def C(pts, rad):
    pts = [np.array(x, float) for x in pts]; rad = list(rad)
    return lambda p: chain(p, pts, rad)
def B(c, b, r, R=None): return lambda p: round_box(p, c, b, r, R)
def U(*fs):
    def g(p):
        d = fs[0](p)
        for f in fs[1:]: d = np.minimum(d, f(p))
        return d
    return g
def SU(k, *fs):
    def g(p):
        d = fs[0](p)
        for f in fs[1:]: d = smin(d, f(p), k)
        return d
    return g
def sym(f):
    def g(p):
        q = p.copy(); q[:, 0] = np.abs(q[:, 0]); return f(q)
    return g
def flat(f, o, n, fac):
    o = np.array(o, float); n = norm(n)
    def g(p): return f(p + ((p - o) @ n)[..., None] * n * (1 / fac - 1)) * fac
    return g
def torus(c, R, r, n=(0, 1, 0), squash=1.0):
    F = frame(n); c = np.array(c, float)
    def f(p):
        q = (p - c) @ F
        return np.sqrt((np.sqrt(q[:, 0]**2 + q[:, 1]**2) - R)**2 + (q[:, 2] / squash)**2) - r
    return f
def cyl(a, b, r, rnd=.03):
    a = np.array(a, float); b = np.array(b, float); ax = b - a; L = np.linalg.norm(ax); F = frame(ax); m = (a + b) / 2
    def f(p):
        q = (p - m) @ F
        dx = np.sqrt(q[:, 0]**2 + q[:, 1]**2) - (r - rnd); dy = np.abs(q[:, 2]) - (L / 2 - rnd)
        return np.minimum(np.maximum(dx, dy), 0) + np.sqrt(np.maximum(dx, 0)**2 + np.maximum(dy, 0)**2) - rnd
    return f
def crystal(a, b, r, sides=6, tip=.4, twist=0.0):
    """Spitzer Kristall von a nach b, Radius r, tip = Anteil der Länge für die Spitze."""
    a = np.array(a, float); b = np.array(b, float); ax = b - a; L = np.linalg.norm(ax); F = frame(ax)
    tl = L * tip; ca = tl / np.hypot(tl, r); sa = r / np.hypot(tl, r)
    ns = [(np.cos(twist + 2 * np.pi * i / sides), np.sin(twist + 2 * np.pi * i / sides)) for i in range(sides)]
    def f(p):
        q = (p - a) @ F; d = -q[:, 2]
        for nx, ny in ns:
            s = q[:, 0] * nx + q[:, 1] * ny
            d = np.maximum(d, s - r)
            d = np.maximum(d, s * ca + (q[:, 2] - (L - tl)) * sa - r * ca)
        return d
    return f
def star(c, n, r, thick=.06, pts=5, inner=.42):
    """Flacher Stern mit runden Spitzen."""
    F = frame(n); c = np.array(c, float); X, Y = F[:, 0], F[:, 1]
    arms = [C([c, c + (np.sin(2 * np.pi * i / pts) * X + np.cos(2 * np.pi * i / pts) * Y) * r], [r * inner, thick * .55]) for i in range(pts)]
    return flat(U(*arms), c, n, .55)
def flake(c, n, r, w=.03):
    """Schneeflocke: sechs Arme mit Seitenästen."""
    F = frame(n); c = np.array(c, float); X, Y = F[:, 0], F[:, 1]; parts = []
    for i in range(6):
        a = np.pi * i / 3; d = np.cos(a) * X + np.sin(a) * Y; e = -np.sin(a) * X + np.cos(a) * Y
        parts.append(C([c, c + d * r], [w * 1.2, w * .7]))
        for t, s in ((.6, .3),):
            for sg in (-1, 1):
                parts.append(C([c + d * r * t, c + (d * (t + s * .7) + e * sg * s) * r], [w * .8, w * .5]))
    return U(*parts)
def bolt(pts, w, n=(0, 0, 1)):
    """Blitz: Zickzack, flach gedrückt."""
    return flat(C(pts, [w] * len(pts)), pts[0], n, .5)
def puff(c, r, n=7, seed=0, spread=1.0):
    """Wolkenbausch aus mehreren Kugeln."""
    rng = np.random.default_rng(seed); c = np.array(c, float); fs = [S(c, r)]
    for i in range(n):
        v = rng.normal(size=3) * np.array((1, .55, 1)); v = v / np.linalg.norm(v)
        fs.append(S(c + v * r * .8 * spread, r * rng.uniform(.5, .75)))
    return SU(r * .3, *fs)
def inside(f, eps=0.0): return lambda p: f(p) < eps
def above(y): return lambda p: p[:, 1] > y
def below(y): return lambda p: p[:, 1] < y

def shade(h):
    """Schattenfarbe: dunkler, kühler und satter statt grau, das wirkt bunter."""
    import colorsys
    c = srgb(h) / 255 * np.array((.56, .58, .74))
    hh, ss, vv = colorsys.rgb_to_hsv(*c)
    c = np.array(colorsys.hsv_to_rgb(hh, min(1, ss * 1.25 + .06), vv)) * 255
    return '#%02X%02X%02X' % tuple(int(x) for x in np.clip(np.round(c), 0, 255))
RARITY_SIZE = [2.7, 2.9, 3.1, 3.4, 3.7, 3.9]   # Zielgrösse in Studs, je seltener desto grösser

# ---------- Pet ----------
class Pet:
    def __init__(s, name, colors, ground=True, scale=1.1):
        s.name, s.ground, s.scale = name, ground, scale
        s.colors = {'eye': ('#141827', '#232A40'), 'shine': ('#FFFFFF', '#FFFFFF')}
        s.colors.update(colors)
        s.colors['iris'] = {'stops': ['#2B2F6E', '#5C7BFF', '#BFD0FF'], 't': lambda p: np.full(len(p), .5)}
        s.colors['blush'] = '#FF8FB1'
        s.soft, s.subs, s.hardp, s.paints, s.rib, s.detail, s.head = [], [], [], [], [], [], None
        s.base = 'fur'; s.target = None; s.eyepos = []; s.hetero = False
        s.layout()
    def layout(s):
        s.names = list(s.colors); s.index = {k: i for i, k in enumerate(s.names)}
        s.col0 = {}; c = 0
        for k in s.names:
            v = s.colors[k]; s.col0[k] = c
            c += len(v['stops']) if isinstance(v, dict) else 1
        assert c <= COLS, f'{s.name}: {c} Spalten'
    def recolor(s, colors):
        for k, v in colors.items():
            if isinstance(v, list) and isinstance(s.colors.get(k), dict): s.colors[k] = dict(s.colors[k], stops=v)
            else: s.colors[k] = v
        s.layout()

    # Bausteine
    def add(s, f, k=.1, mat=None):
        s.soft.append((f, k))
        if mat: s.paints.append((inside(f, .025), mat))
    def sub(s, f, k=.03): s.subs.append((f, k))
    def hard(s, f, mat, detail=False):
        s.hardp.append((f, mat))
        if detail: s.detail.append(f)
    def paint(s, mask, mat): s.paints.append((mask, mat))
    def line(s, pts, w=.024, mat='nose'): s.rib.append((pts, w, mat))

    def fur(s, p):
        d = None
        for f, k in s.soft:
            e = f(p); d = e if d is None else smin(d, e, k)
        for f, k in s.subs: d = ssub(d, f(p), k)
        return smax(d, -p[:, 1], .03) if s.ground else d
    def all(s, p):
        d = s.fur(p)
        for f, _ in s.hardp: d = np.minimum(d, f(p))
        return np.maximum(d, -p[:, 1]) if s.ground else d

    # Gesicht
    def eyes(s, c, r, x, y, size=1.0, ring=None, mat='eye', sink=.03):
        """Augen mit farbiger Iris (Verlauf von oben dunkel nach unten hell), dunkler Pupille und zwei Glanzpunkten."""
        rf, ef, pf, sf = [], [], [], []
        for sg in (-1, 1):
            p_, n = on_ellipsoid(c, r, sg * x, y); F = frame(n); k = p_ - n * sink
            if ring:
                rf.append(E(k, (.225 * size, .262 * size, .07 * size), F)); k = k + n * .02
            X, Y, Z = F[:, 0], F[:, 1], F[:, 2]
            ef.append(E(k, (.175 * size, .21 * size, .112 * size), F))
            pf.append(E(k + (Z * .045 + Y * .012) * size, (.10 * size, .125 * size, .075 * size), F))
            sf.append(E(k + (-X * .055 + Y * .085 + Z * .100) * size, (.066 * size, .076 * size, .03 * size), F))
            sf.append(E(k + (X * .045 - Y * .075 + Z * .106) * size, (.032 * size, .035 * size, .022 * size), F))
            s.eyepos.append((k, F, size))
        y0 = y - .21 * size; h = .42 * size
        def t(p):
            v = np.clip((p[:, 1] - y0) / h, 0, 1)
            return np.where(p[:, 0] < 0, v / 3, 2 / 3 + v / 3) if s.hetero else v
        s.colors['iris'] = dict(s.colors['iris'], t=t)
        if ring: s.hard(U(*rf), ring, True)
        s.hard(U(*ef), 'iris', True); s.hard(U(*pf), mat, True); s.hard(U(*sf), 'shine', True)
    def blush(s, mat='blush', r=.11, down=.27, out=.17):
        """Rosa Wangen unter den Augen, als Farbfläche auf dem Fell."""
        cs = []
        for k, F, size in s.eyepos:
            sg = 1 if k[0] >= 0 else -1
            cs.append(k - F[:, 1] * down * size + F[:, 0] * out * size * sg)
        f = U(*[S(c, r) for c in cs])
        s.paints.append((lambda p: f(p) < 0, mat))
    def sparkles(s, pts, r=.13, mat='spark'):
        """Schwebende Glitzersterne mit vier Spitzen."""
        for c in pts:
            c = np.array(c, float); n = norm((c[0] * .3, .15, 1))
            s.hard(star(c, n, r, .045, 4, .34), mat)
    def halo(s, c, R=.42, w=.06, mat='halo', n=(0, 1, .08)):
        s.hard(torus(c, R, w, n, squash=1.2), mat)
    def omega(s, y, z, w=.135, d=.075, stem=True, mat='nose', lw=.024, back=.06):
        """Kleiner Tiermund: optional Strich von oben, zwei Bögen."""
        if stem: s.line([(0, y + .065 - i * .022, z) for i in range(4)], lw, mat)
        for sg in (-1, 1):
            s.line([(sg * (.012 + w * t), y - d * np.sin(t * np.pi) + .02 * t, z - back * t) for t in np.linspace(0, 1, 9)], lw, mat)

    def smile(s, y, z, w=.24, d=.06, mat='nose', lw=.03, back=.2):
        s.line([(w * t, y - d * (1 - t * t) + .0, z - back * t * t) for t in np.linspace(-1, 1, 15)], lw, mat)

    # Bau
    def bounds(s):
        ax = [np.arange(-3.6, 3.7, .1), np.arange(-.3, 5.0, .1), np.arange(-3.6, 3.7, .1)]
        g = np.stack(np.meshgrid(*ax, indexing='ij'), -1).reshape(-1, 3)
        i = g[s.all(g) < .09]
        return i.min(0) - .12, i.max(0) + .12

    def build(s, out, voxel=.022, target=2950):
        s.layout(); lo, hi = s.bounds()
        layers = [s.fur] + [f for f, _ in s.hardp]
        field = s.all
        V, F = surface(field, lo, hi, voxel)
        cen = (V[F[:, 0]] + V[F[:, 1]] + V[F[:, 2]]) / 3
        def labels(p):
            L = np.full(len(p), s.index[s.base])
            for mask, mat in s.paints: L[mask(p)] = s.index[mat]
            cur = s.fur(p); L = L + 0
            for i, (f, mat) in enumerate(s.hardp):
                e = f(p); m = e < cur; L[m] = s.index[mat] + 16 * (i + 1); cur = np.minimum(cur, e)
            return L
        L = labels(cen)
        V = smooth_boundaries(V, F, L, field, iters=10)
        def importance(p):
            w = np.ones(len(p))
            if s.head: w[ellipsoid(p, s.head[0], np.array(s.head[1]) * 1.03) < 0] = 2.5
            for f in s.detail: w[np.abs(f(p)) < .045] = 8.0
            return w
        target = target - sum(2 * (len(r[0]) - 1) for r in s.rib)   # Linien zählen zum Budget
        V2, F2, L2 = decimate(V, F, L, target, importance, boundary_w=12.0)
        for _ in range(2):
            g = grad(field, V2); g2 = np.maximum((g * g).sum(-1), 1e-9)
            V2 = V2 - (field(V2) / g2)[:, None] * g
        ao_f = (lambda p: np.minimum(field(p), p[:, 1])) if s.ground else field
        P, N, UV, I, XT, base = [], [], [], [], [], 0
        def uv(mat, ao, p):
            v = s.colors[mat]; c0 = s.col0[mat]
            if isinstance(v, dict):
                n = len(v['stops']); t = np.clip(v['t'](p), 0, 1)
                u = (c0 * SW + .5 + t * (n * SW - 1)) / TW
            else:
                u = np.full(len(p), (c0 + .5) * SW / TW)
            return np.stack([u, .01 + .98 * np.clip(ao, 0, 1)], 1)
        for lab in np.unique(L2):
            fs = F2[L2 == lab]; used, inv = np.unique(fs, return_inverse=True); p = V2[used]
            layer = int(lab) // 16; mat = s.names[int(lab) % 16]; f = layers[layer]
            n = grad(f, p); n /= np.maximum(length(n), 1e-9)[:, None]
            occ = np.zeros(len(p))
            for h, w in ((.03, .5), (.07, .3), (.15, .2), (.3, .12), (.5, .06)):
                occ += w * np.clip((h - ao_f(p + n * h)) / h, 0, 1)
            P.append(p); N.append(n); UV.append(uv(mat, 1 - occ, p)); I.append(inv.reshape(-1, 3) + base); base += len(p)
            XT.append(np.full(len(p), mat in ('spark', 'halo')))
        for pts, w, mat in s.rib:
            rv, rn, rf = ribbon(s.fur, pts, w)
            P.append(rv); N.append(rn); UV.append(uv(mat, np.ones(len(rv)), rv)); I.append(rf + base); base += len(rv)
            XT.append(np.zeros(len(rv), bool))
        P = np.concatenate(P); N = np.concatenate(N); UV = np.concatenate(UV); I = np.concatenate(I)
        core = P[~np.concatenate(XT)]          # Glitzer und Heiligenschein zählen nicht zur Grösse
        b0, b1 = core.min(0), core.max(0); b0[1] = P[:, 1].min() if not s.ground else b0[1]
        ext = b1 - b0
        if s.target: s.scale = s.target / max(ext[1], .72 * max(ext[0], ext[2]))
        P = (P - np.array([(b0[0] + b1[0]) / 2, b0[1], (b0[2] + b1[2]) / 2])) * s.scale
        write_glb(out, s.name, P, N, UV, I, s.palette())
        return dict(tris=int(len(I)), size=[round(float(x), 2) for x in (b1 - b0) * s.scale])

    def palette(s):
        img = np.zeros((TH, TW, 3), np.uint8) + 255
        def cell(v):
            return (srgb(v[0]), srgb(v[1])) if isinstance(v, tuple) else (srgb(shade(v)), srgb(v))
        for k in s.names:
            v = s.colors[k]; x0 = s.col0[k] * SW
            for y in range(TH):
                t = y / (TH - 1)
                if isinstance(v, dict):
                    st = [cell(c) for c in v['stops']]; w = len(st) * SW
                    for x in range(w):
                        a = x / (w - 1) * (len(st) - 1); i = min(int(a), len(st) - 2); f = a - i
                        lo = st[i][0] * (1 - f) + st[i + 1][0] * f; hi = st[i][1] * (1 - f) + st[i + 1][1] * f
                        img[y, x0 + x] = np.round(lo * (1 - t) + hi * t)
                else:
                    lo, hi = cell(v); img[y, x0:x0 + SW] = np.round(lo * (1 - t) + hi * t)
        raw = b''.join(b'\0' + img[y].tobytes() for y in range(TH))
        def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
        return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', TW, TH, 8, 2, 0, 0, 0)) +
                chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

# ---------- Ohren ----------
def ear(P, base, tip, r1, r2, n=(.25, .1, 1), f=.5, inner='inner', mid=None):
    """Spitzes oder langes Ohr mit Delle innen, gespiegelt."""
    pts = [np.array(base, float)] + ([np.array(mid, float)] if mid else []) + [np.array(tip, float)]
    rad = np.array([r1] + ([(r1 + r2) * .62] if mid else []) + [r2]); N = norm(n)
    outer = sym(flat(C(pts, rad), pts[0], N, f))
    dent = sym(flat(C([q + N * r * 1.38 for q, r in zip(pts, rad)], rad * .8), pts[0], N, f))
    P.add(outer, .09); P.sub(dent, .035)
    if inner: P.paint(lambda p: (outer(p) < .06) & (dent(p) < .02), inner)
    return outer

def ear_round(P, c, n, r=.24, inner='inner'):
    F = frame(n); c = np.array(c, float); N = norm(n)
    o = sym(E(c, (r, r, r * .55), F)); d = sym(E(c + N * r * .6, (r * .62, r * .62, r * .45), F))
    P.add(o, .08); P.sub(d, .03)
    if inner: P.paint(lambda p: (d(p) < .02) & (o(p) < .05), inner)
    return o

# ---------- Vorlage: sitzender Vierbeiner ----------
HC = (0, 1.30, .10)
def sitter(name, colors, muzzle='cat', ears='point', tail='long', head=(.84, .72, .76), cheeks=True, eye=1.0, ring=None,
           ground=True, scale=1.1, mouth=True, tailmat=None):
    P = Pet(name, colors, ground, scale); P.head = (HC, head)
    P.add(E(HC, head))
    P.add(E((0, .58, -.06), (.60, .58, .60)), .14)
    P.add(sym(E((.46, .35, -.24), (.32, .35, .43))), .10)
    P.add(sym(E((.44, .125, .28), (.215, .125, .42))), .07)
    P.front = sym(C([(.20, .56, .42), (.17, .115, .52)], [.115, .125]))
    P.add(P.front, .05)
    if cheeks:
        P.add(sym(C([(.66, 1.12, .16), (.91, 1.00, .12)], [.25, .13])), .11)
    if muzzle == 'cat':
        P.muz = E((0, 1.125, .78), (.29, .19, .17)); P.add(P.muz, .16)
        P.nose = (0, 1.205, .925); nr = (.085, .058, .055)
        if mouth: P.omega(1.085, .94)
    elif muzzle == 'fox':
        P.muz = C([(0, 1.18, .66), (0, 1.09, 1.00), (0, 1.05, 1.20)], [.30, .17, .10]); P.add(P.muz, .14)
        P.nose = (0, 1.10, 1.285); nr = (.095, .075, .075)
        if mouth: P.omega(.985, 1.16, w=.10, d=.03, stem=False, back=.1)
    elif muzzle == 'dog':
        P.muz = E((0, 1.10, .84), (.37, .26, .31)); P.add(P.muz, .12)
        P.nose = (0, 1.23, 1.10); nr = (.13, .09, .085)
        if mouth: P.omega(1.03, 1.14, w=.17, d=.06, back=.1)
    else:  # bear
        P.muz = E((0, 1.12, .80), (.35, .25, .25)); P.add(P.muz, .13)
        P.nose = (0, 1.235, 1.02); nr = (.125, .085, .08)
        if mouth: P.omega(1.07, 1.05, w=.14, d=.06)
    P.hard(E(P.nose, nr), 'nose', True)
    if muzzle == 'dog': P.eyes(HC, head, .42, 1.50, eye, ring)
    else: P.eyes(HC, head, .39, 1.37, eye, ring)
    if ears == 'point':
        P.ear = ear(P, (.46, 1.80, .02), (.72, 2.50, -.08), .31, .055)
    elif ears == 'round':
        P.ear = ear_round(P, (.66, 1.92, -.02), (.55, .35, .75))
    elif ears == 'flop':
        P.ear = sym(flat(C([(.66, 1.70, .10), (.96, 1.52, .12), (1.02, 1.04, .16)], [.18, .26, .20]), (.9, 1.4, .1), (1, 0, .12), .55))
        P.add(P.ear, .07)
    elif ears == 'long':
        P.ear = ear(P, (.30, 1.80, -.06), (.60, 3.02, -.12), .22, .11, mid=(.45, 2.40, -.10), f=.52)
    if tail == 'bushy':
        P.tail = C([(.16, .30, -.60), (.62, .36, -.86), (.96, .36, -.44), (.92, .28, .10)], [.16, .31, .30, .10]); P.add(P.tail, .08)
        P.tailtip = (.92, .28, .10)
    elif tail == 'long':
        P.tail = C([(0, .40, -.60), (.08, .52, -.98), (.20, .98, -1.10), (.16, 1.46, -.96)], [.12, .12, .115, .10]); P.add(P.tail, .06)
        P.tailtip = (.16, 1.46, -.96)
    elif tail == 'thick':
        P.tail = C([(.10, .30, -.62), (.52, .22, -.98), (1.00, .20, -.72), (1.12, .22, -.20)], [.14, .20, .21, .17]); P.add(P.tail, .07)
        P.tailtip = (1.12, .22, -.20)
    elif tail == 'stub':
        P.tail = S((0, .42, -.74), .20); P.add(P.tail, .06); P.tailtip = (0, .42, -.9)
    return P

# ---------- Vorlage: stehender Vierbeiner ----------
SHC = (0, 1.74, .50)
def stander(name, colors, head=(.72, .62, .66), body=(.60, .58, .84), snout=True, ears=True, tail=True, leg=.19, scale=1.0, nose=True, ground=True):
    P = Pet(name, colors, ground, scale); P.head = (SHC, head)
    P.add(E(SHC, head))
    P.add(E((0, .98, -.34), body), .16)
    P.add(E((0, 1.04, .14), (.54, .56, .50)), .16)
    P.legs = U(sym(C([(.34, .74, .24), (.32, .14, .28)], [leg + .01, leg - .02])),
               sym(C([(.34, .74, -.86), (.32, .14, -.88)], [leg + .01, leg - .02])))
    P.add(P.legs, .06)
    if snout:
        P.snout = E((0, 1.50, 1.04), (.31, .25, .27)); P.add(P.snout, .13)
        if nose:
            P.hard(sym(E((.09, 1.56, 1.29), (.042, .032, .03))), 'nose', True)
            P.omega(1.40, 1.26, w=.13, d=.05, stem=True, back=.08)
    P.eyes(SHC, head, .38, 1.80, 1.0)
    if ears:
        P.ear = sym(flat(C([(.56, 2.02, .40), (.96, 2.10, .32), (1.10, 2.06, .28)], [.13, .15, .06]), (.8, 2.06, .35), (.1, 1, .25), .6))
        P.add(P.ear, .05)
    if tail:
        P.tail = S((0, 1.26, -1.18), .15); P.add(P.tail, .06)
    return P

def horn(pts, r0=.13, r1=.03):
    n = len(pts); return C(pts, list(np.linspace(r0, r1, n)))

# ---------- Vorlage: runder Vogel ----------
BHC = (0, 1.62, .10)
BTIPS = [(.72, .47, .10), (.76, .41, -.20), (.71, .49, -.50)]
def wing_fold(P):
    w = E((.64, .90, -.18), (.52, .44, .15), frame((1, .12, .06)))
    for t in BTIPS:
        w = SU(.05, w, C([(.64, .84, -.20 + t[2] * .35), t], [.13, .075]))
    return sym(w)
def wing_open(y=1.30, span=1.75, lift=.5):
    """Halb geöffneter Flügel mit Federfingern."""
    base = C([(.58, y, -.10), (1.06, y + lift * .6, -.18), (span, y + lift * .4, -.24)], [.24, .20, .11])
    fs = [base]
    for t in (.14, .34, .54, .74, .92):
        x = .58 + (span - .58) * t; yy = y + lift * .55 * np.sin(t * 2.6); l = .40 + .24 * np.sin(t * 3.0)
        fs.append(C([(x, yy, -.18), (x + .14 * t, yy - l, -.22)], [.165, .08]))
    return sym(flat(SU(.06, *fs), (1.1, y, -.2), (0, .1, 1), .5))
def legs_bird(th=.105, toe=.095, y=.42):
    es = []
    x = .27
    e = round_cone_f((x, y, .02), (x, .11, .06), th, th - .015)
    for dx, z in [(-.20, .44), (0, .52), (.20, .44)]:
        e = SU(.03, e, C([(x, .09, .08), (x + dx, .08, z)], [toe, toe - .02]))
    e = SU(.03, e, C([(x, .09, .04), (x, .075, -.26)], [toe - .01, toe - .035]))
    return sym(e)
def round_cone_f(a, b, r1, r2): return lambda p: round_cone(p, a, b, r1, r2)
def birdy(name, colors, head=(.80, .74, .76), eye=1.0, ring=None, beak='short', crest=True, wings='fold', legs=True, scale=1.08, tail=True):
    P = Pet(name, colors, True, scale); P.head = (BHC, head)
    P.add(E(BHC, head))
    P.add(E((0, .84, -.06), (.70, .64, .70)), .18)
    P.add(E((0, .80, .38), (.44, .36, .26)), .14)
    if wings == 'fold':
        P.wing = wing_fold(P); P.add(P.wing, .06)
    elif wings == 'open':
        P.wing = wing_open(); P.add(P.wing, .08)
    if tail:
        P.tail = U(*[C([(0, .82, -.56), (x, .44, z)], [.19, .09]) for x, z in ((0, -1.16), (-.25, -1.08), (.25, -1.08))]); P.add(P.tail, .09)
    if crest:
        P.add(SU(.05, C([(0, 2.24, .02), (0, 2.54, -.16)], [.15, .06]), C([(.12, 2.22, .02), (.20, 2.44, -.18)], [.12, .05]),
                 C([(-.12, 2.22, .02), (-.20, 2.44, -.18)], [.12, .05])), .09)
    P.eyes(BHC, head, .40, 1.68, eye, ring)
    if beak == 'short':
        up = C([(0, 1.60, .74), (0, 1.52, 1.03), (0, 1.39, 1.17)], [.20, .125, .04])
        lo = C([(0, 1.42, .78), (0, 1.385, .98), (0, 1.335, 1.07)], [.135, .085, .035])
    elif beak == 'hook':
        up = C([(0, 1.62, .76), (0, 1.56, 1.06), (0, 1.42, 1.20), (0, 1.26, 1.16)], [.21, .15, .08, .03])
        lo = C([(0, 1.42, .80), (0, 1.40, 1.00)], [.12, .06])
    elif beak == 'small':
        up = C([(0, 1.58, .80), (0, 1.51, .98), (0, 1.42, 1.05)], [.13, .085, .03])
        lo = C([(0, 1.44, .82), (0, 1.42, .96)], [.09, .05])
    elif beak == 'long':
        up = C([(0, 1.60, .74), (0, 1.52, 1.30), (0, 1.46, 1.72)], [.17, .085, .03])
        lo = C([(0, 1.47, .78), (0, 1.45, 1.26), (0, 1.43, 1.60)], [.10, .06, .025])
    if beak:
        P.hard(up, 'beak', True); P.hard(lo, 'beaklo' if 'beaklo' in P.colors else 'beak')
    if legs:
        P.legs = legs_bird(); P.hard(P.legs, 'leg')
    return P

# ---------- Vorlage: Pinguin ----------
PHC = (0, 1.92, .06)
def penguin(name, colors, head=(.74, .66, .68), eye=1.0, ring=None, scale=1.0):
    P = Pet(name, colors, True, scale); P.head = (PHC, head)
    P.add(E(PHC, head)); P.add(E((0, 1.0, -.02), (.78, .98, .70)), .22)
    P.flip = sym(flat(C([(.72, 1.34, .02), (1.00, .96, .04), (1.10, .62, .12)], [.17, .19, .09]), (.95, 1.0, .04), (1, .2, .1), .5))
    P.add(P.flip, .05)
    P.tail = C([(0, .42, -.62), (0, .20, -.92)], [.17, .06]); P.add(P.tail, .07)
    P.belly = E((0, 1.02, .34), (.60, .88, .52))
    P.paint(inside(P.belly), 'belly')
    P.eyes(PHC, head, .34, 1.98, eye, ring)
    P.hard(C([(0, 1.86, .70), (0, 1.76, .92), (0, 1.68, 1.04)], [.17, .10, .035]), 'beak', True)
    P.hard(sym(SU(.03, E((.34, .10, .24), (.27, .10, .40)))), 'leg')
    return P

# ---------- Vorlage: Wal ----------
WHC = (0, 1.05, .40)
def whale(name, colors, head=(.92, .88, .90), eye=1.0, ring=None, scale=1.0, ex=.50, ey=1.02):
    P = Pet(name, colors, False, scale); P.head = (WHC, head)
    P.add(E(WHC, head))
    P.body = C([(0, 1.0, .1), (0, 1.0, -.9), (0, 1.14, -1.75)], [.84, .54, .15]); P.add(P.body, .2)
    fl = sym(flat(C([(.04, 1.20, -1.86), (.42, 1.42, -2.02), (.72, 1.56, -2.14)], [.14, .15, .05]), (.4, 1.4, -2), (0, 1, -.2), .45))
    P.fluke = fl; P.add(fl, .06)
    P.fin = sym(flat(C([(.78, .72, .30), (1.14, .46, .14), (1.34, .34, .02)], [.18, .17, .06]), (1.1, .5, .15), (.25, 1, .1), .45))
    P.add(P.fin, .06)
    P.belly = E((0, .34, .42), (.86, .66, 1.05))
    P.eyes(WHC, head, ex, ey, eye, ring)
    return P

# ---------- Vorlage: Yeti ----------
YHC = (0, 1.86, .10)
def yeti(name, colors, head=(.92, .80, .80), scale=1.0, eye=.95, ring=None):
    P = Pet(name, colors, True, scale); P.head = (YHC, head)
    P.add(E(YHC, head)); P.add(E((0, 1.02, -.02), (.98, .98, .80)), .24)
    arm = sym(C([(.86, 1.44, .02), (1.18, 1.02, .08), (1.20, .50, .16)], [.32, .29, .27])); P.arm = arm
    P.add(arm, .10)
    P.add(sym(E((1.20, .34, .18), (.25, .22, .25))), .08)
    P.add(sym(E((.46, .16, .34), (.34, .16, .46))), .08)
    # Zotteln rund um Schultern, Kopf und Bauch
    for c in [(.70, 2.34, .10), (.94, 2.02, .10), (1.04, 1.62, .10), (1.42, .96, .10), (1.48, .62, .14), (.96, .62, .46), (.60, .28, .60)]:
        d = norm((c[0], .4, .15)); c2 = np.array(c)
        P.add(sym(C([c2 - d * .22, c2 + d * .10 + np.array((0, -.1, 0))], [.22, .07])), .09)
    P.face = E((0, 1.84, .56), (.60, .50, .42)); P.paint(inside(P.face), 'face')
    P.tummy = E((0, 1.0, .60), (.58, .62, .36)); P.paint(inside(P.tummy), 'face')
    P.eyes(YHC, head, .34, 1.92, eye, ring)
    P.hard(E((0, 1.72, .885), (.10, .07, .055)), 'nose', True)
    P.omega(1.56, .86, w=.20, d=.05, stem=False, lw=.028)
    P.hard(sym(C([(.14, 1.54, .80), (.145, 1.66, .84)], [.055, .018])), 'horn', True)
    P.horns = sym(C([(.54, 2.46, .06), (.84, 2.70, .04), (.96, 3.02, -.02)], [.15, .11, .03]))
    P.hard(P.horns, 'horn')
    return P

# ---------- Vorlage: Drache ----------
def dragon(name, colors, head=(.84, .72, .76), scale=1.05, eye=1.0, ring=None, wing_y=1.15):
    P = sitter(name, colors, muzzle='fox', ears=None, tail=None, head=head, cheeks=False, eye=eye, ring=ring, mouth=False, scale=scale)
    P.tail = C([(.10, .36, -.62), (.40, .24, -1.02), (.92, .18, -1.04), (1.26, .18, -.66)], [.24, .20, .13, .06]); P.add(P.tail, .08)
    P.spade = sym(flat(C([(1.26, .18, -.66), (1.38, .19, -.44)], [.17, .03]), (1.3, .18, -.5), (0, 1, 0), .4))
    P.hard(lambda p: flat(C([(1.24, .18, -.66), (1.42, .19, -.36)], [.16, .03]), (1.3, .18, -.5), (0, 1, 0), .45)(p), 'horn2' if 'horn2' in P.colors else 'horn')
    P.belly = E((0, .62, .52), (.40, .60, .32)); P.paint(lambda p: (P.belly(p) < 0) & (P.front(p) > .03), 'belly')
    P.horns = sym(C([(.40, 1.92, -.02), (.54, 2.34, -.22), (.56, 2.62, -.42)], [.14, .085, .025])); P.hard(P.horns, 'horn')
    P.ear = sym(flat(C([(.74, 1.58, -.02), (1.12, 1.80, -.14)], [.17, .05]), (.9, 1.7, -.08), (.1, 1, .3), .5)); P.add(P.ear, .07)
    # Rückenzacken
    sp = []
    for y, z, h in [(1.86, -.52, .24), (1.52, -.74, .24), (1.12, -.78, .22), (.76, -.74, .18)]:
        sp.append(C([(0, y, z), (0, y + h * .35, z - h)], [.10, .025]))
    P.spines = U(*sp)
    # Flügel: drei Finger mit Haut
    w = SU(.04, C([(.42, wing_y, -.46), (1.00, wing_y + .78, -.74), (1.54, wing_y + 1.02, -.78)], [.12, .08, .03]))
    ms = []
    for tip in [(1.54, wing_y + 1.02, -.78), (1.58, wing_y + .42, -.74), (1.34, wing_y - .10, -.70), (.92, wing_y - .32, -.66)]:
        ms.append(C([(.46, wing_y + .05, -.48), (.86, wing_y + .34, -.62), tip], [.09, .13, .03]))
    P.memb = sym(flat(SU(.14, *ms), (.9, wing_y + .3, -.65), (.05, 0, 1), .32))
    P.bone = sym(flat(w, (.9, wing_y + .3, -.65), (.05, 0, 1), .5))
    P.hard(P.memb, 'wing'); P.hard(P.bone, 'fur2' if 'fur2' in P.colors else 'fur')
    return P

def hat_cone(c, r, h, n=(0, 1, 0)):
    return C([c, np.array(c) + norm(n) * h], [r, r * .25])

def crown(c, R, h=.34, pts=5, band=.07, tilt=(0, 1, 0), pr=.075):
    """Krone: Reif plus Zacken."""
    c = np.array(c, float); F = frame(tilt); X, Y, Z = F[:, 0], F[:, 1], F[:, 2]
    fs = [torus(c, R, band, tilt, squash=1.6)]
    for i in range(pts):
        a = 2 * np.pi * i / pts + .3; d = np.cos(a) * X + np.sin(a) * Y
        fs.append(C([c + d * R, c + d * R * 1.14 + Z * h], [pr + .02, .03]))
    return U(*fs)
