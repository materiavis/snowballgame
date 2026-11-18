"""Ei 1, Selten: Murmeltier (Marmot).
Merkmale: aufrechte Männchen-Pose mit Pfoten vor der Brust, Pausbacken, runde kleine Ohren,
zwei orange Nagezähne wie beim echten Tier, dunkler Scheitel, heller Bauch.
Selten = erstes kleines Zubehör: ein Edelweiss am Kopf.
Bewusst keine Schoggi: Murmeltier plus Schokolade erinnert an eine bekannte Werbung.
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import numpy as np
from petkit import *

FUR, DARK, CREAM, EYE, SHINE, NOSE, TOOTH, PETAL, CENTER = range(9)
RAMPS = [
    ('#7A5136', '#BE8A5C'),  # Fell
    ('#3F2A20', '#7A5240'),  # Scheitel, Pfoten, Schwanzspitze, Ohr innen
    ('#C9A47A', '#F4E2C2'),  # Bauch und Schnauze
    ('#141827', '#232A40'),  # Auge
    ('#FFFFFF', '#FFFFFF'),  # Glanzpunkt
    ('#2A1E1E', '#4A3430'),  # Nase und Mund
    ('#D98E36', '#FFCF85'),  # Nagezähne, leicht orange wie beim echten Tier
    ('#B9C6DA', '#FFFFFF'),  # Edelweiss
    ('#D9A520', '#FFDD55'),  # Edelweiss Mitte
]

HEAD_C, HEAD_R = (0, 1.98, 0.08), (0.86, 0.68, 0.74)
EYE_R = (0.165, 0.195, 0.105)
EYES = []
for s in (-1, 1):
    p, n = on_ellipsoid(HEAD_C, HEAD_R, s * 0.37, 2.06)
    EYES.append((p - n * 0.03, n, align(n)))

# Ohren sitzen tief und seitlich
EARS = []
for s in (-1, 1):
    n = norm((s * 0.75, 0.35, 0.55))
    EARS.append((np.array((s * 0.70, 2.46, 0.00)), n, align(n)))

FL_C, FL_N = on_ellipsoid(HEAD_C, HEAD_R, 0.50, 2.42)
FL_N = norm(FL_N + np.array((0.0, 0.0, 0.35)))     # etwas nach vorne gedreht, damit man es sieht
FL_C = FL_C + FL_N * 0.05
FL_R = align(FL_N)

def ear_outer(p):
    return np.minimum(*[ellipsoid(p, c, (0.20, 0.20, 0.11), R) for c, n, R in EARS])

def ear_dent(p):
    return np.minimum(*[ellipsoid(p, c + n * 0.13, (0.125, 0.125, 0.09), R) for c, n, R in EARS])

def body(p):
    d = ellipsoid(p, (0, 0.78, -0.02), (0.76, 0.78, 0.70))                       # Birnenform unten
    d = smin(d, ellipsoid(p, (0, 1.36, 0.0), (0.58, 0.56, 0.52)), 0.20)          # Brust
    for s in (-1, 1):
        d = smin(d, ellipsoid(p, (s * 0.60, 0.42, 0.06), (0.30, 0.36, 0.40)), 0.12)    # Oberschenkel
    return d

def arm(p):
    d = None
    for s in (-1, 1):
        e = chain(p, [(s * 0.52, 1.40, 0.20), (s * 0.42, 1.22, 0.54), (s * 0.15, 1.20, 0.74)], [0.15, 0.125, 0.115])
        d = e if d is None else np.minimum(d, e)
    return d

def fur(p):
    d = body(p)
    d = smin(d, ellipsoid(p, HEAD_C, HEAD_R), 0.16)
    d = smin(d, ellipsoid(p, (0, 1.76, 0.66), (0.37, 0.25, 0.23)), 0.14)         # Schnauze
    for s in (-1, 1):
        d = smin(d, ellipsoid(p, (s * 0.50, 1.74, 0.44), (0.32, 0.26, 0.28)), 0.22)    # Pausbacken
        d = smin(d, ellipsoid(p, (s * 0.42, 0.125, 0.40), (0.235, 0.125, 0.38)), 0.07) # Füsse
    d = smin(d, arm(p), 0.07)                                                    # Arme und Pfoten
    t = chain(p, [(0, 0.50, -0.62), (0, 0.34, -0.98), (0, 0.30, -1.20)], [0.24, 0.25, 0.17])  # Schwanz
    d = smin(d, t, 0.10)
    d = smin(d, ear_outer(p), 0.08)
    d = ssub(d, ear_dent(p), 0.03)
    return smax(d, -p[:, 1], 0.03)

def eye(p):
    return np.minimum(*[ellipsoid(p, c, EYE_R, R) for c, n, R in EYES])

def shine(p):
    d = None
    for (c, n, R) in EYES:
        x, y, z = R[:, 0], R[:, 1], R[:, 2]
        big = c - x * 0.05 + y * 0.08 + z * 0.09
        small = c + x * 0.04 - y * 0.07 + z * 0.095
        e = np.minimum(ellipsoid(p, big, (0.062, 0.072, 0.03), R), ellipsoid(p, small, (0.03, 0.033, 0.022), R))
        d = e if d is None else np.minimum(d, e)
    return d

def nose(p):
    return ellipsoid(p, (0, 1.875, 0.885), (0.115, 0.075, 0.07), align((0, 0.3, 1)))

def tooth(p):
    R = align((0, -0.25, 1))
    a = round_box(p, (-0.056, 1.632, 0.852), (0.049, 0.078, 0.03), 0.02, R)
    b = round_box(p, (0.056, 1.632, 0.852), (0.049, 0.078, 0.03), 0.02, R)
    return np.minimum(a, b)

def flower(p):
    x, y, z = FL_R[:, 0], FL_R[:, 1], FL_R[:, 2]
    d = None
    for i, l in enumerate((0.27, 0.24, 0.28, 0.23, 0.27, 0.25, 0.26, 0.23)):
        a = i * 2 * np.pi / 8 + 0.2
        u = np.cos(a) * x + np.sin(a) * y
        e = round_cone(p, FL_C + u * 0.06, FL_C + u * l + z * 0.02, 0.078, 0.022)
        d = e if d is None else np.minimum(d, e)
    return d

def center(p):
    x, y, z = FL_R[:, 0], FL_R[:, 1], FL_R[:, 2]
    d = sphere(p, FL_C + z * 0.08, 0.06)
    for i in range(5):
        a = i * 2 * np.pi / 5
        d = np.minimum(d, sphere(p, FL_C + (np.cos(a) * x + np.sin(a) * y) * 0.075 + z * 0.065, 0.05))
    return d

def everything(p):
    d = fur(p)
    for f in (eye, shine, nose, tooth, flower, center):
        d = np.minimum(d, f(p))
    return d

def labels(p):
    L = np.full(len(p), FUR)
    f = fur(p)
    # heller Bauch und Schnauze
    L[(ellipsoid(p, (0, 0.92, 0.46), (0.56, 0.74, 0.52)) < 0) & (p[:, 2] > 0.05)] = CREAM
    L[(ellipsoid(p, (0, 1.72, 0.78), (0.48, 0.33, 0.36)) < 0)] = CREAM
    L[arm(p) < 0.025] = FUR
    # dunkler Scheitel, Pfoten, Füsse, Schwanzspitze, Ohr innen
    L[(ellipsoid(p, (0, 2.66, 0.22), (0.56, 0.46, 0.66)) < 0)] = DARK
    L[(ear_dent(p) < 0.02) & (ear_outer(p) < 0.05)] = DARK
    for s in (-1, 1):
        L[(sphere(p, (s * 0.15, 1.20, 0.80), 0.17) < 0)] = DARK
        L[(sphere(p, (s * 0.42, 0.10, 0.72), 0.22) < 0)] = DARK
    L[(sphere(p, (0, 0.30, -1.26), 0.27) < 0)] = DARK
    e, h, n, t, fl, c = eye(p), shine(p), nose(p), tooth(p), flower(p), center(p)
    L[(e < f)] = EYE
    L[(h < e + 0.002) & (h < f)] = SHINE
    L[(n < f)] = NOSE
    L[(t < f)] = TOOTH
    L[(fl < f)] = PETAL
    L[(c < f) & (c < fl)] = CENTER
    return L

def normal_field(lab):
    return {EYE: eye, SHINE: shine, NOSE: nose, TOOTH: tooth, PETAL: flower, CENTER: center}.get(lab, fur)

def importance(p):
    w = np.ones(len(p))
    w[(p[:, 2] > 0.25) & (p[:, 1] > 1.5) & (p[:, 1] < 2.4) & (np.abs(p[:, 0]) < 0.8)] = 3.0
    w[np.abs(np.minimum(eye(p), nose(p))) < 0.05] = 8.0
    w[np.abs(tooth(p)) < 0.04] = 14.0
    w[np.abs(shine(p)) < 0.03] = 8.0
    w[np.abs(np.minimum(flower(p), center(p))) < 0.05] = 5.0
    return w

def mouth_lines():
    z = 0.95
    out = [(fur, [(0, 1.83 - i * 0.022, z) for i in range(5)], 0.024, NOSE)]
    for s in (-1, 1):
        c = [(s * (0.012 + 0.17 * t), 1.735 - 0.07 * np.sin(t * np.pi) + 0.03 * t, z - 0.08 * t) for t in np.linspace(0, 1, 9)]
        out.append((fur, c, 0.024, NOSE))
    return out

def build(out, voxel=0.022, target=2950):
    return bake(None, everything, labels, normal_field, (-1.25, -0.05, -1.5), (1.25, 2.85, 1.10), voxel, target,
                RAMPS, importance=importance, ribbons=mouth_lines(), name='Murmeltier', out=out, scale=1.1)

if __name__ == '__main__':
    print(build(sys.argv[1] if len(sys.argv) > 1 else 'build/murmeltier.glb',
                float(sys.argv[2]) if len(sys.argv) > 2 else 0.022))
