"""Ei 1, Gewöhnlich: Schneehase (Snow Hare).
Merkmale: Winterfell weiss, lange Ohren mit schwarzen Spitzen wie beim echten Alpenschneehasen,
Wangenbüschel, Kugelschwanz, grosse Hinterpfoten. Gewöhnlich = keine Accessoires.
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import numpy as np
from petkit import *

# Materialien (Spalten der Palette): (Schatten, Grundfarbe)
FUR, EARIN, TIP, BLUSH, EYE, SHINE, NOSE, MOUTH = range(8)
RAMPS = [
    ('#9FB6DA', '#FBFCFF'),  # Fell
    ('#D98CA6', '#FFC3D0'),  # Ohr innen
    ('#1F2436', '#3A4058'),  # Ohrspitze
    ('#F7AFC0', '#FFC9D4'),  # Wangen
    ('#141827', '#232A40'),  # Auge
    ('#FFFFFF', '#FFFFFF'),  # Glanzpunkt
    ('#D9718C', '#F48FA8'),  # Nase
    ('#5A4A5E', '#5A4A5E'),  # Mund
]

HEAD_C, HEAD_R = (0, 1.30, 0.10), (0.84, 0.70, 0.74)

def head_normal(x, y):
    """Normale der Kopf-Ellipsoide an Stelle x,y (Vorderseite)."""
    r = np.array(HEAD_R); c = np.array(HEAD_C)
    q = np.array([x - c[0], y - c[1], 0.0]) / r
    z = np.sqrt(max(1 - q @ q, 1e-6))
    p = np.array([x, y, c[2] + z * r[2]])
    return p, norm((p - c) / (r * r))

# Augen sitzen tief und weit aussen, das macht den Kopf kindlich
EYES = []
for s in (-1, 1):
    p, n = head_normal(s * 0.37, 1.35)
    EYES.append((p - n * 0.035, n, align(n)))
EYE_R = (0.185, 0.225, 0.115)

def ear_parts(p, s):
    """Liefert (Ohrform, Delle innen, Abstand zur Spitze) für ein Ohr. s = -1 oder +1."""
    if s > 0:   # dieses Ohr knickt oben ab, das gibt Charakter
        pts = [(0.30, 1.80, -0.06), (0.43, 2.28, -0.10), (0.54, 2.66, -0.06), (0.76, 2.84, 0.10), (0.98, 2.80, 0.22)]
        rad = [0.22, 0.28, 0.245, 0.20, 0.115]
    else:
        pts = [(-0.30, 1.80, -0.06), (-0.43, 2.28, -0.10), (-0.54, 2.72, -0.12), (-0.60, 3.04, -0.12), (-0.62, 3.14, -0.12)]
        rad = [0.22, 0.28, 0.26, 0.19, 0.11]
    pts = np.array(pts); rad = np.array(rad)
    n = norm((s * 0.22, 0.10, 1.0)); f = 0.52
    q = p + ((p - pts[0]) @ n)[..., None] * n * (1 / f - 1)
    d = chain(q, pts, rad) * f
    shift = n[None, :] * (rad * 1.38)[:, None]
    dent = chain(q, pts + shift, rad * 0.80) * f
    return d, dent, length(p - pts[-1])

def fluff(p):
    """Wangen, Brustlatz, Scheitel: breite weiche Bögen statt einzelner Zacken."""
    d = None
    for s in (-1, 1):
        for a, b, r1, r2 in [((0.66, 1.12, 0.16), (0.91, 1.00, 0.12), 0.25, 0.13),
                             ((0.58, 0.92, 0.14), (0.78, 0.76, 0.10), 0.22, 0.115)]:
            e = round_cone(p, (s * a[0], a[1], a[2]), (s * b[0], b[1], b[2]), r1, r2)
            d = e if d is None else smin(d, e, 0.05)
    d = smin(d, ellipsoid(p, (0, 0.76, 0.47), (0.36, 0.25, 0.17)), 0.10)          # Brustlatz
    for c, r in [((-0.17, 0.62, 0.55), 0.10), ((0, 0.58, 0.58), 0.11), ((0.17, 0.62, 0.55), 0.10)]:
        d = smin(d, sphere(p, c, r), 0.10)
    for a, b, r1, r2 in [((0.02, 1.92, 0.12), (0.05, 2.08, 0.24), 0.12, 0.06),
                         ((-0.12, 1.92, 0.12), (-0.17, 2.02, 0.24), 0.10, 0.055)]:
        d = smin(d, round_cone(p, a, b, r1, r2), 0.07)
    return d

def fur(p):
    y0 = -p[:, 1]
    d = ellipsoid(p, HEAD_C, HEAD_R)
    d = smin(d, ellipsoid(p, (0, 1.125, 0.76), (0.29, 0.19, 0.17)), 0.16)        # Schnauze
    b = ellipsoid(p, (0, 0.58, -0.06), (0.60, 0.58, 0.60))                       # Körper
    d = smin(d, b, 0.14)
    for s in (-1, 1):
        d = smin(d, ellipsoid(p, (s * 0.46, 0.35, -0.24), (0.32, 0.35, 0.43)), 0.10)   # Keule
        d = smin(d, ellipsoid(p, (s * 0.44, 0.125, 0.28), (0.215, 0.125, 0.42)), 0.07) # Hinterpfote
        d = smin(d, round_cone(p, (s * 0.20, 0.56, 0.42), (s * 0.17, 0.115, 0.52), 0.115, 0.125), 0.05)  # Vorderbein
        d = smin(d, ear_parts(p, s)[0], 0.10)
    d = smin(d, fluff(p), 0.11)
    t = sphere(p, (0, 0.47, -0.76), 0.29)                                        # Schwanz, runder Bommel
    for c, r in [((0.17, 0.56, -0.86), 0.14), ((-0.18, 0.54, -0.87), 0.14), ((0.04, 0.32, -0.88), 0.14), ((-0.06, 0.68, -0.86), 0.12)]:
        t = smin(t, sphere(p, c, r), 0.13)
    d = smin(d, t, 0.05)
    for s in (-1, 1):
        e = ear_parts(p, s)
        d = ssub(d, e[1], 0.035)
    return smax(d, y0 + 0.0, 0.03)

def eye(p):
    return np.minimum(ellipsoid(p, EYES[0][0], EYE_R, EYES[0][2]), ellipsoid(p, EYES[1][0], EYE_R, EYES[1][2]))

def shine(p):
    d = None
    for (c, n, R) in EYES:
        x, y, z = R[:, 0], R[:, 1], R[:, 2]
        # beide Glanzpunkte auf derselben Seite, wie von einer Lichtquelle
        big = c - x * 0.055 + y * 0.085 + z * 0.098
        small = c + x * 0.045 - y * 0.075 + z * 0.104
        e = np.minimum(ellipsoid(p, big, (0.07, 0.08, 0.03), R), ellipsoid(p, small, (0.034, 0.036, 0.022), R))
        d = e if d is None else np.minimum(d, e)
    return d

def nose(p):
    return ellipsoid(p, (0, 1.205, 0.905), (0.092, 0.062, 0.06), align((0, 0.25, 1)))

def everything(p):
    return np.minimum(np.minimum(np.minimum(fur(p), eye(p)), shine(p)), nose(p))

def labels(p):
    L = np.full(len(p), FUR)
    for s in (-1, 1):
        d, dent, tip = ear_parts(p, s)
        L[(d < 0.06) & (dent < 0.02)] = EARIN
    for s in (-1, 1):
        d, dent, tip = ear_parts(p, s)
        L[(d < 0.05) & (tip < 0.27)] = TIP
    for s in (-1, 1):
        L[(length(p - np.array((s * 0.62, 1.115, 0.64))) < 0.155) & (p[:, 2] > 0.3)] = BLUSH
    f, e, h, n = fur(p), eye(p), shine(p), nose(p)
    L[(e < f) & (e < n)] = EYE
    L[(h < e + 0.002) & (h < f)] = SHINE
    L[(n < f) & (n < e)] = NOSE
    return L

def normal_field(lab):
    return {EYE: eye, SHINE: shine, NOSE: nose}.get(lab, fur)

def importance(p):
    """Gesicht bekommt mehr Dreiecke, Augen und Nase am meisten."""
    w = np.ones(len(p))
    w[(p[:, 2] > 0.25) & (p[:, 1] > 0.85) & (p[:, 1] < 1.75) & (np.abs(p[:, 0]) < 0.8)] = 3.0
    w[np.abs(np.minimum(eye(p), nose(p))) < 0.05] = 8.0
    w[np.abs(shine(p)) < 0.03] = 8.0
    return w

def mouth_lines():
    """Kleines Hasenmaul: Strich unter der Nase und zwei Bögen."""
    z = 0.92
    a = [(0, 1.15 - i * 0.022, z) for i in range(4)]
    out = [(fur, a, 0.024, MOUTH)]
    for s in (-1, 1):
        c = [(s * (0.012 + 0.135 * t), 1.085 - 0.075 * np.sin(t * np.pi) + 0.02 * t, z - 0.06 * t) for t in np.linspace(0, 1, 9)]
        out.append((fur, c, 0.024, MOUTH))
    return out

def build(out, voxel=0.022, target=2950):
    return bake(None, everything, labels, normal_field, (-1.25, -0.08, -1.15), (1.25, 3.40, 1.12), voxel, target,
                RAMPS, importance=importance, ribbons=mouth_lines(), name='Schneehase', out=out)

if __name__ == '__main__':
    print(build(sys.argv[1] if len(sys.argv) > 1 else 'build/schneehase.glb',
                float(sys.argv[2]) if len(sys.argv) > 2 else 0.022))
