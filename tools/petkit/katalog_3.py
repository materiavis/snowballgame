"""Ei 8 bis 10 und Goldener Yeti."""
from kit import *
AUR = ['#7CF5C8', '#4FC4E8', '#7A7DFF', '#D07BFF']

def kristall_drache():
    P = dragon('Kristall-Drache', {'fur': '#8FD6F2', 'belly': '#E9FBFF', 'horn': ('#3E8FE0', '#D9F8FF'), 'wing': ('#6E9BE8', '#CFE9FF'), 'nose': ('#2F5A8E', '#2F5A8E'), 'gem': ('#7A3FC4', '#D9B8FF')})
    # Legendär: Rückenzacken aus Kristall, grosser Stirnkristall, Kristalle auf den Flügeln
    for y, z, h, r in [(1.82, -.56, .50, .15), (1.46, -.76, .46, .14), (1.06, -.80, .42, .13), (.72, -.74, .34, .11)]:
        P.hard(crystal((0, y, z), (0, y + h * .5, z - h), r, 6, .5), 'horn')
    P.hard(crystal((0, 1.70, .62), (0, 2.34, .78), .15, 6, .55), 'gem', True)
    for x, y, h in [(1.54, 2.10, .46), (1.02, 1.86, .36)]:
        P.hard(sym(crystal((x, y, -.72), (x + .08, y + h, -.76), .10, 6, .5)), 'horn')
    return P

def spiegel_katze():
    P = sitter('Spiegel-Katze', {'fur': '#D6DFEC', 'mirror': '#55657F', 'nose': ('#C9798C', '#F0A3B3'), 'inner': '#A9B6CA'}, muzzle='cat', ears='point', tail='long')
    # Gewöhnlich, Merkmal ist das Spiegelbild: linke und rechte Hälfte sind umgekehrt
    P.paint(lambda p: p[:, 0] < 0, 'mirror')
    P.base = 'fur'
    return P

def eis_golem():
    ice = {'stops': ['#2F6FE0', '#6FD0F4', '#D9F8FF'], 't': lambda p: np.clip((p[:, 1] - .2) / 2.8, 0, 1)}
    P = Pet('Eis-Golem', {'fur': ice, 'glow': ('#2BB5D9', '#A9F4FF'), 'nose': ('#1E3A6A', '#1E3A6A'), 'crystal': ('#3E8FE0', '#E6FBFF')}, True, 1.0)
    hc = (0, 2.12, .10); hr = (.62, .56, .52); P.head = (hc, hr)
    P.add(B(hc, (.62, .54, .52), .17), .03)
    P.add(B((0, 1.16, 0), (.86, .60, .62), .22), .05)
    P.add(sym(B((.34, .28, .04), (.30, .28, .36), .13)), .03)
    P.add(sym(B((1.22, 1.46, 0), (.34, .30, .36), .13)), .03)
    P.add(sym(B((1.32, .72, .06), (.40, .46, .42), .15)), .03)
    P.line([(-.54, 2.60, .63), (-.42, 2.46, .63), (-.48, 2.34, .63), (-.40, 2.22, .63)], .035, 'nose')
    P.line([(-.5, 1.42, .63), (-.20, 1.18, .63), (-.36, .94, .63), (-.12, .72, .63)], .04, 'nose')
    P.eyes(hc, (.66, .58, .54), .30, 2.16, .92, mat='eye', ring='glow')
    P.smile(1.88, .63, w=.20, d=.05, back=.01)
    for x, y, h, r in [(1.22, 1.72, .56, .16), (1.44, 1.70, .36, .11), (.98, 1.72, .36, .10)]:
        P.hard(sym(crystal((x, y, 0), (x + .10, y + h, -.02), r, 6, .45)), 'crystal')
    P.hard(crystal((.2, 2.56, 0), (.26, 3.0, -.02), .13, 6, .45), 'crystal')
    P.hard(crystal((-.22, 2.56, .06), (-.28, 2.88, .04), .10, 6, .45), 'crystal')
    return P

def frost_einhorn():
    P = stander('Frost-Einhorn', {'fur': '#F6FAFF', 'mane': {'stops': ['#BDF0FF', '#7FB8FF', '#B48CFF'], 't': lambda p: np.clip((2.6 - p[:, 1]) / 2.2, 0, 1)},
                                  'horn': ('#3E8FE0', '#D9F8FF'), 'nose': ('#7E90AE', '#A4B4CC'), 'hoof': '#7FB8FF'})
    P.paint(lambda p: (P.legs(p) < .03) & (p[:, 1] < .30), 'hoof')
    P.paint(inside(E((0, 1.46, 1.02), (.33, .20, .33))), 'fur')
    P.add(C([(0, 2.36, .32), (0, 2.20, -.14), (0, 1.74, -.54), (0, 1.32, -.72)], [.16, .22, .20, .11]), .08, 'mane')
    for x, y, z in [(.30, 2.30, .36), (.38, 1.96, -.08), (.34, 1.56, -.44)]:
        P.add(sym(C([(x * .4, y + .02, z), (x, y - .22, z - .06)], [.17, .06])), .07, 'mane')
    P.add(C([(0, 2.34, .62), (0, 2.14, 1.02)], [.15, .05]), .07, 'mane')
    P.tail = C([(0, 1.26, -1.18), (0, 1.0, -1.58), (0, .50, -1.62), (.0, .22, -1.40)], [.15, .24, .20, .05]); P.add(P.tail, .07, 'mane')
    P.hard(crystal((0, 2.26, .78), (0, 3.26, 1.04), .13, 6, .85), 'horn', False)
    return P

def polarlicht_schlange():
    P = Pet('Polarlicht-Schlange', {'fur': {'stops': AUR, 't': lambda p: np.clip(p[:, 1] / 2.5, 0, 1)}, 'belly': '#F2F8FF', 'nose': ('#27314B', '#3C4866'), 'tongue': ('#C4302B', '#F0564A'), 'star': ('#7CF5C8', '#E8FFF5')}, True, 1.0)
    hc = (0, 2.24, .36); hr = (.74, .58, .66); P.head = (hc, hr)
    P.add(E(hc, hr))
    P.add(torus((0, .30, 0), .86, .32), .08); P.add(torus((0, .78, 0), .64, .29), .08); P.add(torus((0, 1.20, 0), .42, .25), .08)
    P.add(C([(.30, 1.26, .20), (.0, 1.66, .10), (0, 2.0, .24)], [.28, .27, .30]), .12)
    P.add(C([(.92, .28, -.42), (1.40, .24, -.78), (1.74, .20, -.70)], [.28, .16, .04]), .08)
    P.paint(inside(C([(0, 1.30, .46), (0, 1.74, .42), (0, 1.96, .50)], [.20, .20, .20])), 'belly')
    P.add(E((0, 2.06, .94), (.30, .18, .20)), .14)
    P.hard(sym(E((.10, 2.14, 1.13), (.03, .022, .022))), 'nose', True)
    P.smile(1.92, 1.12, w=.26, d=.03, back=.18)
    P.eyes(hc, hr, .38, 2.30, 1.0)
    P.hard(C([(0, 1.96, 1.10), (0, 1.90, 1.32)], [.03, .022]), 'tongue')
    P.hard(sym(C([(0, 1.90, 1.32), (.06, 1.86, 1.42)], [.02, .012])), 'tongue')
    # Episch: Sternenkrone auf dem Kopf
    P.hard(star((0, 2.92, .24), (0, .1, 1), .24, .07), 'star')
    return P

def frostkoenig():
    P = Pet('Frostkönig', {'fur': '#BFE3F7', 'white': ('#AFC6E6', '#FFFFFF'), 'cape': '#2F4FB8', 'gold': ('#B9860F', '#FFD84D'), 'crystal': ('#3E8FE0', '#D9F8FF'), 'nose': ('#7E9BC8', '#A4BFE8'), 'gem': ('#A81E3C', '#F2436A')}, True, 1.0)
    hc = (0, 1.92, .10); hr = (.76, .66, .68); P.head = (hc, hr)
    P.add(E(hc, hr))
    P.body = C([(0, 1.30, 0), (0, .36, -.02)], [.52, .98]); P.add(P.body, .12, 'cape')
    P.add(sym(C([(.62, 1.30, .08), (.96, .96, .26)], [.20, .17])), .06, 'cape')
    P.add(sym(S((1.00, .90, .30), .15)), .03, 'fur')
    P.add(torus((0, 1.36, .02), .60, .14, (0, 1, .06)), .04, 'white')
    P.add(C([(0, 1.62, .72), (0, 1.12, .92), (0, .70, .90)], [.36, .30, .05]), .10, 'white')
    P.add(sym(C([(.06, 1.68, .80), (.42, 1.62, .66)], [.13, .07])), .06, 'white')
    P.hard(E((0, 1.80, .82), (.10, .08, .07)), 'nose', True)
    P.eyes(hc, hr, .36, 2.00, .92)
    P.add(sym(C([(.12, 2.30, .68), (.50, 2.28, .52)], [.06, .05])), .03, 'white')
    # Legendär: Eiskrone und Zepter
    for a in np.linspace(0, 2 * np.pi, 7)[:-1]:
        d = np.array((np.cos(a + .26), 0, np.sin(a + .26)))
        P.hard(crystal(np.array((0, 2.40, .08)) + d * .44, np.array((0, 2.40 + .50 + .26 * (np.sin(a + .26) > .3), .08)) + d * .54, .13, 6, .5), 'crystal')
    P.hard(torus((0, 2.42, .08), .46, .07, (0, 1, 0), squash=1.3), 'gold')
    P.hard(crystal((0, 2.38, .50), (0, 2.38, .72), .09, 6, .6), 'gem', True)
    P.hard(cyl((1.16, .04, .34), (1.16, 2.36, .34), .055), 'gold')
    P.hard(crystal((1.16, 2.30, .34), (1.16, 3.0, .34), .19, 6, .4), 'crystal')
    return P

def astronauten_hund():
    P = sitter('Astronauten-Hund', {'fur': '#D9A566', 'suit': ('#B4BFD3', '#F7F9FD'), 'nose': ('#1E1A20', '#37303A'), 'inner': '#A9713E', 'metal': '#6E7C96', 'red': ('#B22A2A', '#EF5350'), 'blue': ('#1E5BC0', '#59A0FF'), 'dark': '#2F3A52'},
               muzzle='dog', ears='flop', tail='stub', cheeks=False, head=(.88, .74, .78), scale=1.25)
    P.paint(lambda p: p[:, 1] < .93, 'suit')
    P.paint(inside(P.ear), 'inner')
    P.paint(lambda p: (P.muz(p) < .05) & (p[:, 1] < 1.12), 'suit')
    P.hard(torus((0, .98, .08), .54, .10, (0, .9, .2), squash=.9), 'metal')
    P.hard(B((0, .60, -.78), (.40, .46, .18), .08), 'metal')
    P.hard(B((0, .62, .62), (.24, .18, .05), .03), 'dark')
    P.hard(sym(S((.10, .66, .66), .045)), 'red', True); P.hard(S((0, .54, .67), .045), 'blue', True)
    P.paint(lambda p: (P.front(p) < .03) & (p[:, 1] < .22), 'metal')
    P.paint(lambda p: (np.abs(p[:, 0]) > .24) & (p[:, 1] < .17) & (p[:, 2] > .2), 'metal')
    P.hard(C([(.34, .98, -.70), (.36, 1.62, -.76)], [.03, .02]), 'metal'); P.hard(S((.36, 1.68, -.76), .075), 'red', True)
    return P

def mond_hase():
    P = sitter('Mond-Hase', {'fur': '#D5D8E4', 'crater': '#A7ACBF', 'nose': ('#7E8AAE', '#A4B0D0'), 'inner': '#B8BDD0', 'moon': ('#D99A12', '#FFE27A')},
               muzzle='cat', ears='long', tail='stub', cheeks=False)
    for c, r in [((.52, 1.72, .42), .17), ((-.60, 1.54, .46), .13), ((.06, 1.96, .30), .13), ((.42, .70, .44), .15), ((-.40, .46, .30), .17), ((.66, .54, -.20), .19), ((-.62, 1.04, -.14), .15), ((0, 1.22, -.62), .20), ((-.30, 1.78, -.40), .16), ((.40, 1.30, -.54), .14)]:
        P.sub(S(np.array(c) * 1.10, r * .92), .035)
        P.paint(inside(S(np.array(c) * 1.10, r * 1.02)), 'crater')
    a = np.linspace(-1.2, 1.2, 7)
    P.hard(C([(-.17 * np.cos(t) + .04, 1.80 + .17 * np.sin(t), .70) for t in a], [.02, .05, .075, .085, .075, .05, .02]), 'moon', True)
    return P

def kometen_fuchs():
    com = {'stops': ['#4F7BFF', '#9FE8FF', '#FFF8D0'], 't': lambda p: np.clip((np.hypot(p[:, 1] - .3, p[:, 2] + .4) - .3) / 2.0, 0, 1)}
    P = sitter('Kometen-Fuchs', {'fur': '#3F63D0', 'white': '#EAF3FF', 'nose': ('#141827', '#232A40'), 'inner': '#20306E', 'comet': com, 'star': ('#D99A12', '#FFE27A')},
               muzzle='fox', tail=None)
    P.paint(lambda p: (p[:, 1] < 1.22) & (P.muz(p) < .05) & (p[:, 2] > .55), 'white')
    P.paint(inside(E((0, .72, .50), (.40, .46, .30))), 'white')
    P.paint(lambda p: (P.front(p) < .03) & (p[:, 1] < .42), 'inner')
    P.paint(lambda p: (P.ear(p) < .03) & (p[:, 1] > 2.24), 'inner')
    P.add(C([(.04, .34, -.60), (.20, .76, -1.14), (.26, 1.54, -1.40), (.20, 2.46, -1.30), (.12, 3.0, -1.08)], [.16, .36, .44, .28, .04]), .08, 'comet')
    for x, y, z, l, r in [(.46, 1.90, -1.5, 2.86, .20), (-.14, 1.76, -1.56, 2.72, .20), (.56, 1.4, -1.5, 2.2, .14), (-.26, 1.3, -1.52, 2.1, .16)]:
        P.add(C([(x * .5, y - .5, z + .2), (x, y, z), (x * 1.05, l, z + .36)], [.26, .17, .03]), .08, 'comet')
    P.hard(star((.20, 1.92, .78), (.2, .4, 1), .15, .05), 'star', True)
    return P

def sternen_wal():
    P = whale('Sternen-Wal', {'fur': '#1E2A66', 'belly': '#6E8BE8', 'spot': ('#D9A520', '#FFE27A'), 'star': ('#D99A12', '#FFE27A'), 'nose': ('#0E1436', '#0E1436'), 'ring': ('#6E8BE8', '#BFD0FF')}, eye=1.05, ring='ring', scale=1.08)
    P.paint(inside(P.belly), 'belly')
    P.smile(.72, 1.27, mat='nose')
    for c in [(.52, 1.56, -.28), (-.46, 1.68, -.46), (.1, 1.82, .1), (.60, 1.34, -.86), (-.58, 1.26, -1.0), (.2, 1.44, -1.34), (-.1, 1.92, .62), (-.68, 1.42, .30), (.70, 1.40, .32)]:
        P.paint(inside(S(c, .065)), 'spot')
    # Episch: Sternbild auf dem Rücken und Sternenfontäne
    pts = [(.32, 1.82, -.22), (-.30, 1.70, -.72), (.14, 1.46, -1.28)]
    for i, q in enumerate(pts):
        P.hard(star(q, (q[0] * .6, 1, .1), .19, .06), 'star')
    P.hard(C([(0, 1.86, .30), (0, 2.34, .30)], [.07, .05]), 'star')
    P.hard(star((0, 2.56, .30), (0, .1, 1), .24, .07), 'star', True)
    P.hard(star((.40, 2.36, .30), (0, .1, 1), .13, .05), 'star'); P.hard(star((-.40, 2.36, .30), (0, .1, 1), .13, .05), 'star')
    return P

def galaxie_drache():
    gal = {'stops': ['#1E1450', '#4A2AB8', '#B44FD8', '#FF8AC8'], 't': lambda p: np.clip((p[:, 1] - .1) / 2.2, 0, 1)}
    P = dragon('Galaxie-Drache', {'fur': gal, 'belly': '#F2C8FF', 'horn': ('#D99A12', '#FFE27A'), 'wing': ('#1E1450', '#3D2A9E'), 'nose': ('#1E1450', '#1E1450')})
    P.hard(P.spines, 'horn')
    for c in [(.60, 1.90, .28), (-.60, 1.78, .36), (0, 2.02, .14), (.72, .90, -.10), (-.70, .70, -.14), (.50, .36, -.56), (-.40, 1.20, -.56), (.30, 1.60, -.56)]:
        P.paint(inside(S(c, .05)), 'horn')
    # Legendär: Ring aus Sternenstaub um den Körper und Mondsichel
    P.hard(torus((0, 1.04, -.05), 1.34, .055, (.15, 1, .1), squash=.7), 'horn')
    for a in (0.4, 2.2, 4.0, 5.4):
        P.hard(star((1.34 * np.cos(a), 1.04 - .1 * np.cos(a), 1.34 * np.sin(a) - .05), (0, .2, 1), .2, .06), 'horn')
    return P

def alien_pinguin():
    P = penguin('Alien-Pinguin', {'fur': '#49C46E', 'belly': '#DFFFE6', 'beak': ('#7A3FC4', '#B07CF5'), 'leg': ('#7A3FC4', '#B07CF5'), 'ball': ('#D99A12', '#FFE27A'), 'dark': '#2F8E4F'}, scale=1.15)
    P.paint(inside(sym(E((.34, 1.98, .62), (.30, .34, .22)))), 'belly')
    PHC_ = (0, 1.92, .06)
    k, n = on_ellipsoid(PHC_, (.74, .66, .68), 0, 2.32); F = frame(n)
    P.hard(E(k - n * .03, (.11, .13, .08), F), 'eye', True); P.hard(E(k + n * .03 + F[:, 0] * -.03 + F[:, 1] * .05, (.04, .045, .02), F), 'shine', True)
    P.hard(sym(C([(.30, 2.50, .02), (.46, 2.92, -.04), (.42, 3.14, -.06)], [.05, .04, .03])), 'dark')
    P.hard(sym(S((.42, 3.22, -.06), .11)), 'ball', True)
    for c in [(.60, 1.30, -.42), (-.56, 1.04, -.46), (.2, .70, -.64), (-.3, 1.54, -.46)]:
        P.paint(inside(S(c, .13)), 'dark')
    return P

def saturn_schildkroete():
    bands = ['#E8B66A', '#F5DDA0', '#C98A4A', '#F0C884']
    P = Pet('Saturn-Schildkröte', {'fur': '#7BC47F', 'shell': {'stops': ['#E8B66A', '#F7E3AE', '#C98A4A'], 't': lambda p: .5 + .5 * np.sin(p[:, 1] * 7.0)}, 'ring': {'stops': ['#CBB6F5', '#8E6FE0'], 't': lambda p: np.clip((np.hypot(p[:, 0], p[:, 2] + .08) - 1.28) / .55, 0, 1)}, 'nose': ('#2E5A3A', '#2E5A3A')}, True, 1.05)
    hc = (0, .92, 1.02); hr = (.58, .52, .50); P.head = (hc, hr)
    P.add(E(hc, hr)); P.add(C([(0, .70, .30), (0, .80, .84)], [.34, .36]), .14)
    P.shell = S((0, 1.22, -.08), .98)
    P.add(P.shell, .03, 'shell')
    for z in (.48, -.66):
        P.add(sym(E((.74, .20, z), (.27, .20, .30))), .08)
    P.add(C([(0, .42, -.92), (0, .28, -1.26)], [.14, .04]), .06)
    P.eyes(hc, hr, .24, .98, .84)
    P.omega(.74, 1.44, w=.11, d=.035, stem=False, back=.06)
    P.hard(torus((0, 1.34, -.08), 1.56, .28, (.20, 1, -.30), squash=.13), 'ring')
    return P

def nebel_qualle():
    neb = {'stops': ['#7A5BD9', '#B46FE8', '#FF8AC8', '#FFD1E8'], 't': lambda p: np.clip((p[:, 1] - .6) / 2.3, 0, 1)}
    P = Pet('Nebel-Qualle', {'fur': neb, 'nose': ('#3C2E5E', '#3C2E5E'), 'spot': '#FFF0FA', 'ten': {'stops': ['#7A5BD9', '#59C8F0'], 't': lambda p: np.clip(p[:, 1] / 1.4, 0, 1)}}, False, 1.0)
    hc = (0, 2.14, 0); hr = (1.02, .92, 1.0); P.head = (hc, hr)
    P.add(E(hc, hr))
    P.sub(E((0, 1.26, 0), (.86, .36, .86)), .08)
    for i in range(8):
        a = i * np.pi / 4 + .39; d = np.array((np.cos(a), 0, np.sin(a)))
        P.add(S(np.array((0, 1.62, 0)) + d * .92, .24), .08)
        q = [np.array((0, 1.5, 0)) + d * .78 + np.array((.14 * np.sin(t * 6 + a), -t * 1.5, .14 * np.cos(t * 6 + a))) for t in np.linspace(0, 1, 6)]
        P.hard(C(q, [.13, .12, .11, .09, .07, .03]), 'ten')
    P.eyes(hc, hr, .40, 2.00, 1.0)
    P.smile(1.66, .92, w=.16, d=.04, back=.04)
    for c in [(.5, 2.72, .5), (-.5, 2.76, .44), (0, 2.96, .14), (.72, 2.4, -.2), (-.76, 2.34, -.2), (.2, 2.7, -.66), (-.34, 2.5, -.74)]:
        P.paint(inside(S(c, .12)), 'spot')
    return P

def schwarzes_loch_katze():
    disk = {'stops': ['#FF5A1F', '#FFB347', '#FFF2B0'], 't': lambda p: np.clip(1 - (np.hypot(p[:, 0], p[:, 2]) - 1.20) / .62, 0, 1)}
    P = sitter('Schwarzes-Loch-Katze', {'fur': '#1A1830', 'dark': '#3B2F6E', 'nose': ('#7A5BD9', '#B07CF5'), 'inner': ('#7A5BD9', '#C9B6FF'), 'disk': disk, 'void': ('#000000', '#050308')},
               muzzle='cat', ears='point', tail='long', ring='inner')
    P.paint(lambda p: (P.muz(p) < .05), 'dark')
    # Episch: Akkretionsscheibe um die Katze, Loch auf der Brust
    P.hard(torus((0, .98, -.02), 1.46, .36, (.12, 1, .06), squash=.14), 'disk')
    P.hard(E((0, .70, .58), (.20, .24, .05)), 'void')
    P.hard(torus((0, .70, .59), .25, .035, (0, 0, 1)), 'inner')
    return P

def kosmischer_yeti():
    cos = {'stops': ['#1E1450', '#3D2AA8', '#7A4FE0', '#59C8F0'], 't': lambda p: np.clip((p[:, 1] - .2) / 2.8, 0, 1)}
    P = yeti('Kosmischer Yeti', {'fur': cos, 'face': '#BFD0FF', 'nose': ('#1E1450', '#1E1450'), 'horn': ('#D99A12', '#FFE27A'), 'star': ('#D99A12', '#FFE27A')}, scale=1.0)
    for c in [(.74, 2.1, .36), (-.74, 2.0, .40), (.0, 2.60, .12), (1.14, 1.0, .34), (-1.14, 1.2, .3), (.84, .62, .52), (-.76, .50, .56), (.5, 1.5, .62), (-.5, 1.46, .62)]:
        P.paint(inside(S(c, .06)), 'star')
    P.hard(torus((0, 2.72, .04), .62, .05, (.0, 1, .12), squash=.9), 'star')
    P.hard(star((0, 3.10, .04), (0, .1, 1), .30, .08), 'star', True)
    P.hard(sym(star((1.62, 1.84, .10), (0, .1, 1), .20, .06)), 'star')
    return P

def goldener_yeti():
    rb = {'stops': ['#FF5A5A', '#FFD84D', '#59D98E', '#59A0FF'], 't': lambda p: (np.arctan2(p[:, 0], p[:, 2] - .06) + np.pi) / (2 * np.pi)}
    P = yeti('Goldener Yeti', {'fur': '#F4C542', 'face': '#FFF1BF', 'nose': ('#6A4A12', '#8A6420'), 'horn': ('#D9D3C0', '#FFFFFF'), 'crown': rb}, scale=1.0)
    # Geheim: Krone in den Regenbogenfarben der Seltenheit
    P.hard(crown((0, 2.60, .06), .46, .36, 5), 'crown')
    return P

PETS = {'kristall-drache': kristall_drache, 'spiegel-katze': spiegel_katze, 'eis-golem': eis_golem, 'frost-einhorn': frost_einhorn, 'polarlicht-schlange': polarlicht_schlange, 'frostkoenig': frostkoenig,
        'astronauten-hund': astronauten_hund, 'mond-hase': mond_hase, 'kometen-fuchs': kometen_fuchs, 'sternen-wal': sternen_wal, 'galaxie-drache': galaxie_drache,
        'alien-pinguin': alien_pinguin, 'saturn-schildkroete': saturn_schildkroete, 'nebel-qualle': nebel_qualle, 'schwarzes-loch-katze': schwarzes_loch_katze,
        'kosmischer-yeti': kosmischer_yeti, 'goldener-yeti': goldener_yeti}
