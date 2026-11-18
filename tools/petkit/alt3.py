"""Die ersten drei Pets (Schneehase, Bergdohle, Murmeltier), auf den Baukasten umgestellt.
Die Formen kommen unverändert aus modelle/*.py, Farben und Augen aus dem Baukasten."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / 'modelle'))
import numpy as np
from kit import Pet, length, S, U
import schneehase as H, bergdohle as BD, murmeltier as M

def schneehase():
    P = Pet('Schneehase', {'fur': '#FFFFFF', 'inner': '#FFB8CC', 'tip': '#33384F', 'nose': '#F48FA8', 'mouth': ('#5A4A5E', '#5A4A5E')}, True, 1.1)
    P.add(H.fur, .1); P.head = (H.HEAD_C, H.HEAD_R)
    for s in (-1, 1):
        P.paint(lambda p, s=s: (H.ear_parts(p, s)[0] < .06) & (H.ear_parts(p, s)[1] < .02), 'inner')
        P.paint(lambda p, s=s: (H.ear_parts(p, s)[0] < .05) & (H.ear_parts(p, s)[2] < .27), 'tip')
    P.hard(H.nose, 'nose', True)
    P.eyes(H.HEAD_C, H.HEAD_R, .37, 1.35, 1.06, sink=.035)
    for fld, pts, w, mat in H.mouth_lines(): P.line(pts, w, 'mouth')
    return P

def bergdohle():
    P = Pet('Bergdohle', {'fur': '#404C6B', 'tips': '#6F85B0', 'ring': ('#8F9CB8', '#DCE3F0'), 'beak': ('#D99A12', '#FFD23F'),
                          'beaklo': ('#B9780C', '#E9A820'), 'leg': ('#B8352F', '#F0564A')}, True, 1.08)
    P.add(BD.fur, .1); P.head = (BD.HEAD_C, BD.HEAD_R)
    for s in (-1, 1):
        for tip in BD.WTIPS:
            c = np.array((s * tip[0], tip[1], tip[2]))
            P.paint(lambda p, s=s, c=c: (BD.wing(p, s) < .03) & (length(p - c) < .17), 'tips')
    for c in [(0.0, 0.42, -1.16), (0.25, 0.46, -1.08), (-0.25, 0.46, -1.08)]:
        c = np.array(c); P.paint(lambda p, c=c: (length(p - c) < .17) & (BD.tail(p) < .03), 'tips')
    P.hard(BD.beak_up, 'beak', True); P.hard(BD.beak_lo, 'beaklo'); P.hard(BD.legs, 'leg')
    P.eyes(BD.HEAD_C, BD.HEAD_R, .40, 1.68, 1.02, ring='ring')
    return P

def murmeltier():
    P = Pet('Murmeltier', {'fur': '#BE8A5C', 'dark': '#7A5240', 'cream': '#F4E2C2', 'nose': ('#2A1E1E', '#4A3430'), 'tooth': ('#D98E36', '#FFCF85'),
                           'petal': ('#B9C6DA', '#FFFFFF'), 'center': ('#D9A520', '#FFDD55')}, True, 1.1)
    P.add(M.fur, .1); P.head = (M.HEAD_C, M.HEAD_R)
    P.paint(lambda p: (M.ellipsoid(p, (0, 0.92, 0.46), (0.56, 0.74, 0.52)) < 0) & (p[:, 2] > 0.05), 'cream')
    P.paint(lambda p: M.ellipsoid(p, (0, 1.72, 0.78), (0.48, 0.33, 0.36)) < 0, 'cream')
    P.paint(lambda p: M.arm(p) < .025, 'fur')
    P.paint(lambda p: M.ellipsoid(p, (0, 2.66, 0.22), (0.56, 0.46, 0.66)) < 0, 'dark')
    P.paint(lambda p: (M.ear_dent(p) < .02) & (M.ear_outer(p) < .05), 'dark')
    for s in (-1, 1):
        P.paint(lambda p, s=s: M.sphere(p, (s * .15, 1.20, .80), .17) < 0, 'dark')
        P.paint(lambda p, s=s: M.sphere(p, (s * .42, .10, .72), .22) < 0, 'dark')
    P.paint(lambda p: M.sphere(p, (0, .30, -1.26), .27) < 0, 'dark')
    P.hard(M.nose, 'nose', True); P.hard(M.tooth, 'tooth', True)
    P.hard(M.flower, 'petal', True); P.hard(M.center, 'center')
    P.eyes(M.HEAD_C, M.HEAD_R, .37, 2.06, .94)
    for fld, pts, w, mat in M.mouth_lines(): P.line(pts, w, 'nose')
    return P

PETS = {'schneehase': schneehase, 'bergdohle': bergdohle, 'murmeltier': murmeltier}
