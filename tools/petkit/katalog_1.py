"""Ei 1 und 2 (Launch) sowie Ei 3 und 4."""
from kit import *

def rotfuchs():
    P = sitter('Rotfuchs', {'fur': '#E2762F', 'white': '#FBF4E8', 'dark': '#3A2A28', 'nose': ('#1E1A20', '#37303A'), 'inner': '#3A2A28',
                            'hat': '#3E7A52', 'band': '#C8332C', 'feather': '#FBF4E8'}, muzzle='fox', tail='bushy')
    P.paint(lambda p: (p[:, 1] < 1.22) & (P.muz(p) < .05) & (p[:, 2] > .55), 'white')
    P.paint(inside(E((0, .72, .50), (.40, .46, .30))), 'white')
    P.paint(inside(S((.92, .28, .10), .34)), 'white')
    P.paint(lambda p: (P.front(p) < .03) & (p[:, 1] < .42), 'dark')
    P.paint(inside(S((.44, .10, .68), .001)), 'dark')
    P.paint(lambda p: (np.abs(p[:, 0]) > .30) & (p[:, 1] < .22) & (p[:, 2] > .30), 'dark')
    P.paint(lambda p: (P.ear(p) < .03) & (p[:, 1] > 2.24), 'dark')
    # Sennenhut mit Feder
    c = (.10, 1.96, .02); n = norm((.14, 1, .02))
    P.hard(torus(c, .34, .10, n, squash=.5), 'hat')
    P.hard(E((.11, 2.10, .02), (.30, .26, .28)), 'hat')
    P.hard(torus((.105, 2.02, .02), .285, .04, n), 'band')
    P.hard(flat(C([(.34, 2.06, -.05), (.62, 2.46, -.20)], [.09, .025]), (.5, 2.3, -.1), (0, .2, 1), .4), 'feather')
    return P

def schneeeule():
    P = birdy('Schneeeule', {'fur': '#FAFBFF', 'spot': '#7F8AA3', 'beak': '#2D3040', 'leg': '#EEF1F8', 'gold': ('#B9860F', '#FFD84D'), 'face': '#FFFFFF'},
              head=(.88, .78, .78), crest=False, beak=None, ring=None, eye=1.15, legs=True)
    P.hard(C([(0, 1.56, .86), (0, 1.48, .96), (0, 1.36, .96)], [.105, .075, .025]), 'beak', True)
    for c in [(.40, 1.05, .56), (-.40, 1.05, .56), (0, .95, .68), (.24, .70, .66), (-.24, .70, .66), (.48, .62, .46), (-.48, .62, .46),
              (.78, .84, -.20), (-.78, .84, -.20), (.76, 1.10, -.36), (-.76, 1.10, -.36), (0, 2.26, .10), (.34, 2.20, .06), (-.34, 2.20, .06)]:
        P.paint(inside(E(c, (.085, .05, .085))), 'spot')
    P.paint(inside(sym(E((.40, 1.64, .66), (.40, .46, .34)))), 'face')
    # Legendär: goldene Schneeflocke als Stirnschmuck
    P.hard(flake((0, 2.62, .10), (0, .15, 1), .40, .04), 'gold', True)
    return P

def gaemse():
    P = stander('Gämse', {'fur': '#9A6E45', 'cream': '#F2E2C4', 'dark': '#3B2A22', 'horn': ('#15131A', '#2F2C36'), 'nose': ('#1E1A20', '#37303A'), 'hoof': '#3B2A22'})
    P.paint(inside(sym(C([(.20, 1.98, .98), (.26, 1.56, 1.14)], [.13, .10]))), 'dark')
    P.paint(inside(E((0, 1.46, 1.02), (.34, .20, .34))), 'cream')
    P.paint(inside(E((0, 2.12, .84), (.44, .22, .30))), 'cream')
    P.paint(inside(E((0, .58, -.16), (.42, .24, .62))), 'cream')
    P.paint(lambda p: (P.legs(p) < .03) & (p[:, 1] < .30), 'hoof')
    P.hard(sym(C([(.20, 2.24, .36), (.26, 2.70, .30), (.27, 2.98, .18), (.22, 3.02, .02)], [.075, .06, .045, .02])), 'horn')
    return P

def steinbock():
    P = stander('Steinbock', {'fur': '#A98A62', 'cream': '#E9D9BC', 'dark': '#5A4632', 'horn': ('#6F5A40', '#C9B48F'), 'nose': ('#1E1A20', '#37303A'), 'hoof': '#3B2E26'})
    P.paint(inside(E((0, .60, -.16), (.42, .24, .62))), 'cream')
    P.paint(inside(E((0, 1.42, 1.02), (.33, .19, .33))), 'cream')
    P.paint(lambda p: (P.legs(p) < .03) & (p[:, 1] < .30), 'hoof')
    P.paint(inside(E((0, 1.72, -.60), (.20, .42, .64))), 'dark')
    h = [(.20, 2.20, .34), (.32, 2.68, .14), (.40, 3.04, -.22), (.42, 3.16, -.66), (.42, 2.98, -1.00)]
    P.hard(sym(horn(h, .155, .035)), 'horn')
    ks = []
    for a, b in zip(h[:-1], h[1:]):
        for t in (.25, .75):
            ks.append(S(np.array(a) * (1 - t) + np.array(b) * t + np.array((0, .03, .10)), .145 - .03 * (a[2] < -.2) - .03 * (a[2] < -.6)))
    P.hard(sym(U(*ks)), 'horn')
    return P

def bernhardiner():
    P = sitter('Bernhardiner', {'fur': '#FBF6EC', 'patch': '#B4622A', 'mask': '#5C3320', 'nose': ('#1E1A20', '#37303A'), 'inner': '#B4622A',
                                'wood': '#A8713E', 'band': '#5D5A68', 'collar': '#C8332C'}, muzzle='dog', ears='flop', tail='thick', cheeks=False, head=(.90, .76, .78), scale=1.3)
    P.base = 'fur'
    P.paint(inside(P.ear), 'patch')
    P.paint(inside(sym(E((.62, 1.46, .34), (.44, .46, .50)))), 'patch')
    P.paint(inside(E((0, .92, -.60), (.66, .50, .46))), 'patch')
    P.paint(inside(sym(E((.46, .40, -.40), (.34, .28, .34)))), 'patch')
    P.paint(inside(sym(E((.28, 1.42, .86), (.17, .19, .16)))), 'mask')
    P.paint(inside(S(P.tailtip, .001)), 'patch')
    P.paint(inside(P.tail), 'patch')
    P.paint(inside(S((1.12, .22, -.20), .24)), 'fur')
    # Selten: Halsband mit Fässchen
    P.hard(torus((0, .90, .10), .56, .055, (0, .9, .25)), 'collar')
    P.hard(cyl((-.21, .60, .72), (.21, .60, .72), .155), 'wood')
    P.hard(U(torus((-.13, .60, .72), .158, .022, (1, 0, 0)), torus((.13, .60, .72), .158, .022, (1, 0, 0))), 'band')
    return P

def steinadler():
    P = birdy('Steinadler', {'fur': '#6D4A30', 'light': '#D9A85C', 'tip': '#2E2422', 'beak': ('#B8860F', '#F6C744'), 'beaklo': ('#8E6A10', '#D9A62E'), 'leg': ('#C9901A', '#F6C744')},
              beak='hook', crest=False, wings='open')
    P.paint(inside(E((0, 2.06, -.34), (.84, .62, .64))), 'light')
    P.paint(lambda p: (P.wing(p) < .03) & (np.abs(p[:, 0]) > 1.05) & (p[:, 1] < 1.25), 'tip')
    P.paint(inside(U(*[S(c, .22) for c in [(0, .44, -1.16), (.25, .46, -1.08), (-.25, .46, -1.08)]])), 'light')
    return P

def goldener_steinbock():
    P = stander('Goldener Steinbock', {'fur': '#F2C14A', 'cream': '#FFF1BF', 'horn': ('#B8860F', '#FFE27A'), 'nose': ('#6A4A12', '#8A6420'), 'hoof': '#B8860F',
                                       'sun': ('#E89A1E', '#FFD24D'), 'gem': ('#A81E3C', '#F2436A')})
    P.paint(inside(E((0, .60, -.16), (.42, .24, .62))), 'cream')
    P.paint(inside(E((0, 1.42, 1.02), (.33, .19, .33))), 'cream')
    P.paint(lambda p: (P.legs(p) < .03) & (p[:, 1] < .30), 'hoof')
    P.add(C([(0, 1.30, 1.00), (0, 1.02, 1.04), (0, .78, 1.02)], [.16, .13, .04]), .07, 'cream')  # Bart
    # eigenes Merkmal gegenüber der Gold-Variante: Spiralhörner, Sonnenscheibe, Stirnjuwel
    pts = [(.20, 2.20, .34), (.44, 2.66, .14), (.72, 2.96, -.20), (.96, 2.90, -.56), (1.02, 2.56, -.62), (.88, 2.36, -.36)]
    P.hard(sym(horn(pts, .17, .04)), 'horn')
    P.hard(torus((0, 2.44, -.74), .74, .085, (0, .05, 1)), 'sun')
    for i in range(10):
        a = 2 * np.pi * i / 10 + .314; d = np.array((np.cos(a), np.sin(a), 0))
        if d[1] > -.35:
            c0 = np.array((0, 2.44, -.74)); P.hard(C([c0 + d * .80, c0 + d * 1.04], [.09, .025]), 'sun')
    P.hard(crystal((0, 2.14, .92), (0, 2.14, 1.12), .10, 6, .6), 'gem', True)
    return P

def robbe():
    P = Pet('Robbe', {'fur': '#F4F6FB', 'spot': '#BBC4D6', 'nose': ('#1E1A20', '#37303A')}, True, 1.15)
    hc = (0, 1.26, .42); hr = (.74, .64, .64); P.head = (hc, hr)
    P.add(E(hc, hr))
    P.add(C([(0, .66, .24), (0, .52, -.60), (0, .32, -1.30)], [.64, .52, .22]), .22)
    P.add(sym(flat(C([(.56, .54, .42), (.92, .22, .58), (1.04, .12, .62)], [.20, .17, .10]), (.9, .25, .55), (.2, 1, .1), .5)), .06)
    P.add(sym(flat(C([(.10, .30, -1.40), (.34, .16, -1.86)], [.17, .11]), (.25, .2, -1.6), (0, 1, 0), .45)), .06)
    P.add(E((0, 1.08, .98), (.28, .18, .20)), .15)
    P.add(sym(E((.20, 1.10, .92), (.20, .16, .17))), .08)
    P.hard(E((0, 1.20, 1.15), (.085, .062, .055)), 'nose', True)
    P.omega(1.055, 1.17, w=.15, d=.04, back=.14)
    P.eyes(hc, hr, .36, 1.34, 1.2)
    for c in [(.30, .95, -.40), (-.34, .90, -.70), (.12, .70, -1.05), (-.05, 1.06, -.05)]:
        P.paint(inside(S(c, .13)), 'spot')
    return P

def pinguin():
    P = penguin('Pinguin', {'fur': '#27314B', 'belly': '#FAFBFF', 'beak': ('#C97A12', '#FFA928'), 'leg': ('#C97A12', '#FFA928'), 'cheek': '#FFC93C'}, scale=1.15)
    P.paint(inside(sym(E((.46, 1.74, .50), (.20, .17, .24)))), 'cheek')
    P.paint(inside(sym(E((.34, 1.98, .62), (.30, .34, .22)))), 'belly')
    return P

def walross():
    P = Pet('Walross', {'fur': '#A9754F', 'pad': '#DDB48D', 'tusk': ('#BDB39A', '#FFF8E4'), 'nose': ('#3A2620', '#5A3D32'), 'hat': '#C8332C', 'brim': '#FBF4E8'}, True, 1.1)
    hc = (0, 1.42, .34); hr = (.76, .66, .66); P.head = (hc, hr)
    P.add(E(hc, hr)); P.add(C([(0, .80, .10), (0, .62, -.70), (0, .34, -1.34)], [.84, .66, .24]), .24)
    P.add(sym(flat(C([(.72, .66, .36), (1.10, .24, .56), (1.26, .12, .62)], [.24, .20, .11]), (1.0, .3, .5), (.2, 1, .1), .5)), .06)
    P.add(sym(flat(C([(.10, .30, -1.44), (.40, .14, -1.88)], [.19, .12]), (.25, .2, -1.6), (0, 1, 0), .45)), .06)
    pad = sym(E((.26, 1.22, .92), (.30, .25, .22))); P.add(pad, .06, 'pad')
    P.hard(E((0, 1.38, 1.06), (.11, .07, .06)), 'nose', True)
    P.hard(sym(C([(.20, 1.02, .98), (.23, .66, 1.08), (.26, .40, 1.10)], [.085, .07, .025])), 'tusk', True)
    for x, y in [(.16, 1.30), (.30, 1.32), (.42, 1.26), (.16, 1.16), (.30, 1.14), (.42, 1.14)]:
        P.paint(lambda p, x=x, y=y: (np.abs(np.abs(p[:, 0]) - x) < .028) & (np.abs(p[:, 1] - y) < .028) & (p[:, 2] > .8), 'nose')
    P.eyes(hc, hr, .36, 1.54, .85)
    # Selten: rote Wollmütze
    P.hard(E((0, 2.0, .30), (.42, .30, .42)), 'hat')
    P.hard(torus((0, 1.90, .31), .44, .08, (0, 1, .08), squash=1.3), 'brim')
    P.hard(puff((0, 2.36, .30), .12, 5), 'brim')
    return P

def polarfuchs():
    P = sitter('Polarfuchs', {'fur': '#F6F9FF', 'blue': '#BFD2EE', 'nose': ('#1E1A20', '#37303A'), 'inner': '#E9C3D2', 'scarf': '#3D7BD9', 'scarf2': '#BFE0FF'},
               muzzle='fox', tail='bushy', ears='round')
    P.paint(inside(S((.92, .28, .10), .34)), 'blue')
    P.paint(lambda p: (P.front(p) < .03) & (p[:, 1] < .34), 'blue')
    # Episch: dicker Schal mit Fransen
    P.hard(torus((0, .92, .08), .56, .14, (0, .9, .22), squash=.8), 'scarf')
    P.hard(flat(C([(.28, .92, .62), (.40, .56, .74), (.42, .28, .74)], [.14, .15, .13]), (.4, .6, .72), (0, .1, 1), .4), 'scarf')
    P.hard(flat(cyl((.42, .40, .74), (.42, .30, .74), .14), (.4, .3, .72), (0, 0, 1), .4), 'scarf2')
    P.hard(flat(cyl((.40, .66, .74), (.41, .58, .74), .155), (.4, .6, .72), (0, 0, 1), .4), 'scarf2')
    return P

def eisbaer():
    P = sitter('Eisbär', {'fur': '#FBFCFF', 'nose': ('#1E1A20', '#37303A'), 'inner': '#CBD9EE', 'crystal': ('#3E8FE0', '#BDEBFF'), 'gold': ('#B9860F', '#FFD84D')},
               muzzle='bear', ears='round', tail='stub', head=(.92, .78, .80), cheeks=False, scale=1.15)
    P.add(sym(E((.34, .60, .30), (.34, .46, .34))), .12)
    # Legendär: Eiskrone
    for x, h, r in [(0, .78, .17), (.30, .56, .13), (.56, .40, .11)]:
        for sg in ((1, -1) if x else (1,)):
            P.hard(crystal((sg * x, 1.92 - x * .28, .06), (sg * x * 1.15, 1.92 - x * .28 + h, .06), r, 6, .45), 'crystal', False)
    P.hard(torus((0, 1.92, .08), .60, .055, (0, 1, .1), squash=1.3), 'gold')
    return P

def schneehuhn():
    P = birdy('Schneehuhn', {'fur': '#FBFCFF', 'tip': '#D9E1EE', 'beak': '#2D3040', 'leg': '#EEF1F8', 'comb': ('#C4302B', '#F0564A')}, beak='small', crest=False, eye=1.05)
    P.hard(sym(E((.36, 2.02, .68), (.15, .05, .06), frame((.3, .6, .7)))), 'comb', True)
    P.paint(inside(U(*[S(c, .17) for c in [(0, .42, -1.16), (.25, .46, -1.08), (-.25, .46, -1.08)]])), 'beak')
    return P

def narwal():
    P = whale('Narwal', {'fur': '#7D93B5', 'belly': '#EEF3FB', 'spot': '#4F6484', 'horn': ('#B5AD97', '#FFF6DE'), 'nose': ('#2D3040', '#2D3040')}, eye=1.1, scale=1.15)
    P.paint(inside(P.belly), 'belly')
    for c in [(.5, 1.5, -.3), (-.4, 1.62, -.5), (.1, 1.75, .1), (.62, 1.3, -.9), (-.55, 1.22, -1.0), (.2, 1.42, -1.3), (-.1, 1.9, .6), (.66, 1.2, .3), (-.68, 1.3, .2)]:
        P.paint(inside(S(c, .12)), 'spot')
    P.smile(.72, 1.27)
    a = np.array((0, 1.26, 1.24)); b = np.array((0, 1.62, 2.34))
    pts = [a + (b - a) * t for t in np.linspace(0, 1, 7)]
    P.hard(C(pts, list(np.linspace(.13, .03, 7))), 'horn', False)
    sp = []
    for t in np.linspace(.04, .9, 8):
        q = a + (b - a) * t; sp.append(torus(q, .13 * (1 - t) + .03 * t, .022, b - a))
    P.hard(U(*sp), 'horn', False)
    return P

def orca():
    P = whale('Orca', {'fur': '#1F2536', 'belly': '#FAFBFF', 'nose': ('#2D3040', '#2D3040'), 'ring': ('#8F9CB8', '#DCE3F0'), 'hat': '#FBFBFF', 'band': '#2F5FD0'}, eye=1.0, ring='ring')
    P.paint(inside(P.belly), 'belly')
    P.paint(inside(sym(E((.62, 1.42, .90), (.30, .22, .28)))), 'belly')
    P.paint(inside(sym(E((.74, .86, -.92), (.24, .34, .46)))), 'belly')
    P.add(flat(C([(0, 1.72, -.30), (0, 2.46, -.62)], [.30, .05]), (0, 2, -.4), (1, 0, 0), .4), .08)
    P.smile(.72, 1.27)
    # Selten: Matrosenmütze
    P.hard(cyl((0, 1.80, .46), (0, 2.02, .44), .40, .06), 'hat')
    P.hard(torus((0, 1.86, .46), .40, .05, (0, 1, 0)), 'band')
    return P

def schneewolf():
    P = sitter('Schneewolf', {'fur': '#D9E2EE', 'white': '#FBFCFF', 'dark': '#7F8DA6', 'nose': ('#1E1A20', '#37303A'), 'inner': '#7F8DA6', 'crystal': ('#3E8FE0', '#BDEBFF'), 'collar': '#2F5FD0'},
               muzzle='fox', tail='bushy', head=(.88, .74, .78))
    P.paint(lambda p: P.muz(p) < .05, 'white')
    P.paint(inside(E((0, .72, .50), (.42, .50, .34))), 'white')
    P.paint(lambda p: (p[:, 1] > 1.40 + .62 * np.abs(p[:, 0])) & (P.ear(p) > .04), 'dark')
    P.paint(inside(S((.92, .28, .10), .34)), 'white')
    # Episch: Mähne und Eiskragen
    for x, y, z in [(.80, 1.02, .16), (.70, .78, .28), (.48, .62, .50), (.92, 1.28, .10)]:
        P.add(sym(C([(x * .72, y + .10, z - .1), (x * 1.16, y - .16, z)], [.20, .06])), .07)
    P.hard(torus((0, .86, .12), .60, .06, (0, .9, .22)), 'collar')
    for a in np.linspace(-1.1, 1.1, 5):
        d = np.array((np.sin(a), 0, np.cos(a)))
        c0 = np.array((0, .80, .10)) + d * .62
        P.hard(crystal(c0 + np.array((0, .05, 0)), c0 + d * .08 + np.array((0, -.42, 0)), .09, 6, .5), 'crystal')
    return P

def polarlicht_fuchs():
    grad_ = {'stops': ['#7CF5C8', '#4FC4E8', '#7A7DFF', '#D07BFF'], 't': lambda p: np.clip((np.hypot(p[:, 0], p[:, 2] + .2) - .5) / 1.5, 0, 1)}
    P = sitter('Polarlicht-Fuchs', {'fur': '#EAF3FF', 'nose': ('#1E1A20', '#37303A'), 'inner': '#7A7DFF', 'aurora': grad_, 'star': ('#7CF5C8', '#E8FFF5')},
               muzzle='fox', tail=None, ring=None)
    # Legendär: drei Schweife im Polarlicht
    tails = [C([(.14, .30, -.60), (.62, .40, -.92), (1.08, .70, -.74), (1.30, 1.16, -.40)], [.15, .30, .28, .05]),
             C([(0, .40, -.62), (0, .80, -1.10), (0, 1.40, -1.26), (.0, 2.02, -1.02)], [.15, .30, .28, .05]),
             C([(-.14, .30, -.60), (-.62, .40, -.92), (-1.08, .70, -.74), (-1.30, 1.16, -.40)], [.15, .30, .28, .05])]
    for t in tails: P.add(t, .07, 'aurora')
    P.paint(lambda p: (p[:, 1] > 2.14), 'aurora')
    P.hard(star((0, 1.92, .76), (0, .55, 1), .16, .05), 'star', True)
    return P

PETS = {'rotfuchs': rotfuchs, 'schneeeule': schneeeule, 'gaemse': gaemse, 'steinbock': steinbock, 'bernhardiner': bernhardiner, 'steinadler': steinadler,
        'goldener-steinbock': goldener_steinbock, 'robbe': robbe, 'pinguin': pinguin, 'walross': walross, 'polarfuchs': polarfuchs, 'eisbaer': eisbaer,
        'schneehuhn': schneehuhn, 'narwal': narwal, 'orca': orca, 'schneewolf': schneewolf, 'polarlicht-fuchs': polarlicht_fuchs}
