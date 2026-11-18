"""Ei 1, Ungewöhnlich: Bergdohle (Alpine Chough).
Merkmale: dunkles Gefieder, kurzer gelber Schnabel, rote Beine. Die Vögel, die bei jeder
Alphütte um Znüni-Reste betteln. Ungewöhnlich = kein Zubehör, aber hellere Federspitzen.
Dunkles Pet: Augen bekommen einen hellen Ring, sonst gehen sie im Gefieder unter.
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import numpy as np
from petkit import *

FUR, TIPS, RING, EYE, SHINE, BEAK, LEG, BLUSH, BEAKLO = range(9)
RAMPS = [
    ('#141A2C', '#404C6B'),  # Gefieder, Blauschwarz statt Schwarz, damit die Form sichtbar bleibt
    ('#2B3A5C', '#6F85B0'),  # helle Federspitzen
    ('#8F9CB8', '#DCE3F0'),  # Augenring
    ('#10131F', '#1E2336'),  # Auge
    ('#FFFFFF', '#FFFFFF'),  # Glanzpunkt
    ('#D99A12', '#FFD23F'),  # Schnabel
    ('#B8352F', '#F0564A'),  # Beine
    ('#C96F86', '#EE9AAE'),  # Wangen
    ('#B9780C', '#E9A820'),  # Unterschnabel
]

HEAD_C, HEAD_R = (0, 1.62, 0.10), (0.80, 0.74, 0.76)
EYE_R = (0.18, 0.215, 0.115)
RING_R = (0.225, 0.262, 0.07)
EYES = []
for s in (-1, 1):
    p, n = on_ellipsoid(HEAD_C, HEAD_R, s * 0.40, 1.68)
    EYES.append((p - n * 0.03, n, align(n)))

WTIPS = [(0.72, 0.47, 0.10), (0.76, 0.41, -0.20), (0.71, 0.49, -0.50)]
def wing(p, s):
    """Angelegter Flügel: liegt am Körper an, drei kurze Federn am Rand."""
    d = ellipsoid(p, (s * 0.64, 0.90, -0.18), (0.52, 0.44, 0.15), align((s * 1, 0.12, 0.06)))
    for tip in WTIPS:
        e = round_cone(p, (s * 0.64, 0.84, -0.20 + tip[2] * 0.35), (s * tip[0], tip[1], tip[2]), 0.13, 0.075)
        d = smin(d, e, 0.05)
    return d

def tail(p):
    d = None
    for tx, tz, ty in [(0.0, -1.16, 0.42), (-0.25, -1.08, 0.46), (0.25, -1.08, 0.46)]:
        e = round_cone(p, (0, 0.82, -0.56), (tx, ty, tz), 0.19, 0.09)
        d = e if d is None else smin(d, e, 0.04)
    return d

def tuft(p):
    d = None
    for a, b, r1, r2 in [((0, 2.24, 0.02), (0.0, 2.54, -0.16), 0.15, 0.06),
                         ((0.12, 2.22, 0.02), (0.20, 2.44, -0.18), 0.12, 0.05),
                         ((-0.12, 2.22, 0.02), (-0.20, 2.44, -0.18), 0.12, 0.05)]:
        e = round_cone(p, a, b, r1, r2)
        d = e if d is None else smin(d, e, 0.05)
    return d

def fur(p):
    d = ellipsoid(p, HEAD_C, HEAD_R)
    d = smin(d, ellipsoid(p, (0, 0.84, -0.06), (0.70, 0.64, 0.70)), 0.18)        # Körper
    d = smin(d, ellipsoid(p, (0, 0.80, 0.38), (0.44, 0.36, 0.26)), 0.14)         # Brust
    for s in (-1, 1):
        d = smin(d, wing(p, s), 0.06)
    d = smin(d, tail(p), 0.09)
    d = smin(d, tuft(p), 0.09)
    return d

def beak(p):
    return smin(beak_up(p), beak_lo(p), 0.012)

def beak_up(p):
    return chain(p, [(0, 1.60, 0.74), (0, 1.52, 1.03), (0, 1.39, 1.17)], [0.20, 0.125, 0.04])

def beak_lo(p):
    return chain(p, [(0, 1.42, 0.78), (0, 1.385, 0.98), (0, 1.335, 1.07)], [0.135, 0.085, 0.035])

def legs(p):
    d = None
    for s in (-1, 1):
        x = s * 0.27
        e = round_cone(p, (x, 0.42, 0.02), (x, 0.11, 0.06), 0.105, 0.09)
        for dx, z in [(-0.20, 0.44), (0.0, 0.52), (0.20, 0.44)]:
            e = smin(e, round_cone(p, (x, 0.09, 0.08), (x + dx, 0.08, z), 0.095, 0.075), 0.03)
        e = smin(e, round_cone(p, (x, 0.09, 0.04), (x, 0.075, -0.26), 0.085, 0.06), 0.03)
        d = e if d is None else np.minimum(d, e)
    return np.maximum(d, -p[:, 1])

def ring(p):
    return np.minimum(ellipsoid(p, EYES[0][0], RING_R, EYES[0][2]), ellipsoid(p, EYES[1][0], RING_R, EYES[1][2]))

def eye(p):
    return np.minimum(ellipsoid(p, EYES[0][0] + EYES[0][1] * 0.02, EYE_R, EYES[0][2]),
                      ellipsoid(p, EYES[1][0] + EYES[1][1] * 0.02, EYE_R, EYES[1][2]))

def shine(p):
    d = None
    for (c, n, R) in EYES:
        x, y, z = R[:, 0], R[:, 1], R[:, 2]
        big = c - x * 0.055 + y * 0.085 + z * 0.118
        small = c + x * 0.045 - y * 0.075 + z * 0.125
        e = np.minimum(ellipsoid(p, big, (0.062, 0.072, 0.03), R), ellipsoid(p, small, (0.03, 0.033, 0.022), R))
        d = e if d is None else np.minimum(d, e)
    return d

def everything(p):
    d = np.minimum(fur(p), ring(p))
    d = np.minimum(d, eye(p)); d = np.minimum(d, shine(p))
    d = np.minimum(d, beak(p))
    return np.minimum(d, legs(p))

def labels(p):
    L = np.full(len(p), FUR)
    f = fur(p)
    tipmask = np.ones(len(p), bool)
    for s in (-1, 1):
        w = wing(p, s)
        # Federspitzen: runde Kappen an den Flügelenden
        for tip in WTIPS:
            L[(w < 0.03) & (length(p - np.array((s * tip[0], tip[1], tip[2]))) < 0.17)] = TIPS
    for c in [(0.0, 0.42, -1.16), (0.25, 0.46, -1.08), (-0.25, 0.46, -1.08)]:
        L[(length(p - np.array(c)) < 0.17) & (tail(p) < 0.03)] = TIPS
    for s in (-1, 1):
        L[(length(p - np.array((s * 0.56, 1.33, 0.60))) < 0.115) & (p[:, 2] > 0.3)] = BLUSH
    r, e, h, b, l = ring(p), eye(p), shine(p), beak(p), legs(p)
    L[(r < f) & (r < b)] = RING
    L[(e < r) & (e < f) & (e < b)] = EYE
    L[(h < e + 0.002) & (h < f) & (h < r)] = SHINE
    L[(b < f) & (b < r) & (b < e)] = BEAK
    L[(b < f) & (b < r) & (b < e) & (beak_lo(p) < beak_up(p))] = BEAKLO
    L[(l < f)] = LEG
    return L

def normal_field(lab):
    return {RING: ring, EYE: eye, SHINE: shine, BEAK: beak, BEAKLO: beak, LEG: legs}.get(lab, fur)

def importance(p):
    w = np.ones(len(p))
    w[(p[:, 2] > 0.25) & (p[:, 1] > 1.1) & (p[:, 1] < 2.1) & (np.abs(p[:, 0]) < 0.8)] = 3.0
    w[np.abs(np.minimum(ring(p), eye(p))) < 0.05] = 8.0
    w[np.abs(shine(p)) < 0.03] = 8.0
    return w

def build(out, voxel=0.022, target=2950):
    return bake(None, everything, labels, normal_field, (-1.2, -0.05, -1.45), (1.2, 2.72, 1.32), voxel, target,
                RAMPS, importance=importance, name='Bergdohle', out=out, scale=1.08)

if __name__ == '__main__':
    print(build(sys.argv[1] if len(sys.argv) > 1 else 'build/bergdohle.glb',
                float(sys.argv[2]) if len(sys.argv) > 2 else 0.022))
