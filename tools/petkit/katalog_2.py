"""Ei 5 bis 7."""
from kit import *

def yak():
    P = stander('Yak', {'fur': '#4B3A32', 'cream': '#D9C4A5', 'horn': ('#A69C86', '#F2EBD8'), 'nose': ('#1E1A20', '#37303A'), 'hoof': '#2B2320'}, body=(.74, .68, .92), leg=.22, scale=1.02)
    for z, l in ((.26, .46), (-.14, .38), (-.54, .44), (-.94, .40)):
        P.add(sym(C([(.60, .98, z), (.72, l, z + .06)], [.28, .13])), .10)
    P.add(C([(0, 2.30, .56), (0, 2.14, 1.0)], [.26, .08]), .08)                  # Stirnzotteln
    P.add(sym(C([(.26, 2.26, .62), (.38, 2.06, .98)], [.20, .07])), .08)
    P.paint(inside(E((0, 1.46, 1.02), (.33, .20, .33))), 'cream')
    P.paint(lambda p: (P.legs(p) < .03) & (p[:, 1] < .26), 'hoof')
    P.hard(sym(C([(.60, 2.10, .46), (1.04, 2.14, .40), (1.26, 2.46, .36), (1.22, 2.78, .34)], [.15, .12, .08, .03])), 'horn')
    return P

def rotpanda():
    P = sitter('Rotpanda', {'fur': '#C95A28', 'white': '#FCF4E6', 'dark': '#3A2420', 'nose': ('#1E1A20', '#37303A'), 'inner': '#3A2420'}, muzzle='cat', ears='round', tail='thick')
    P.paint(lambda p: (P.muz(p) < .06), 'white')
    P.paint(inside(sym(E((.36, 1.66, .60), (.17, .11, .16)))), 'white')
    P.paint(inside(sym(C([(.64, 1.20, .50), (.82, 1.00, .22)], [.12, .08]))), 'white')
    P.paint(lambda p: (P.ear(p) < .03) & (np.abs(p[:, 0]) > .78), 'white')
    P.paint(lambda p: (P.front(p) < .03), 'dark')
    P.paint(lambda p: (p[:, 1] < .22) & (p[:, 2] > .05), 'dark')
    P.paint(inside(E((0, .60, .52), (.36, .50, .22))), 'dark')
    for c in [(.52, .22, -.98), (1.00, .20, -.72), (1.12, .22, -.20)]:
        P.paint(inside(S(c, .155)), 'dark')
    return P

def schneeleopard():
    P = sitter('Schneeleopard', {'fur': '#E7E5DE', 'white': '#FBFAF6', 'spot': '#4E5260', 'nose': ('#C9798C', '#F0A3B3'), 'inner': '#BDB6A9', 'collar': '#2F5FD0', 'gem': ('#3E8FE0', '#BDEBFF')},
               muzzle='cat', ears='round', tail='thick', cheeks=True)
    P.paint(lambda p: (P.muz(p) < .06), 'white')
    P.paint(inside(E((0, .64, .54), (.38, .50, .26))), 'white')
    for c in [(.42, 1.86, .36), (-.42, 1.86, .36), (0, 1.96, .34), (.74, 1.48, .26), (-.74, 1.48, .26), (.56, .84, -.30), (-.56, .84, -.30), (.30, 1.0, -.56), (-.30, 1.0, -.56),
              (.66, .42, -.32), (-.66, .42, -.32), (.72, .36, .10), (-.72, .36, .10), (.0, .66, -.68), (.52, .22, -.98), (1.0, .2, -.72), (.4, .24, -1.0)]:
        cc = np.array(c)
        P.paint(lambda p, cc=cc: np.abs(length(p - cc) - .085) < .034, 'spot')
    P.paint(inside(S((1.12, .22, -.20), .19)), 'spot')
    P.hard(torus((0, .90, .10), .55, .06, (0, .9, .25)), 'collar')
    P.hard(crystal((0, .86, .62), (0, .86, .82), .13, 6, .6), 'gem', True)
    return P

def wolkenkranich():
    P = Pet('Wolkenkranich', {'fur': '#FBFCFF', 'dark': '#2B3247', 'red': ('#C4302B', '#F0564A'), 'beak': ('#8F7A40', '#D9C176'), 'leg': '#2B3247', 'cloud': ('#AFC6E6', '#FFFFFF'), 'gold': ('#B9860F', '#FFD84D')}, True, .96)
    hc = (0, 3.02, .44); hr = (.50, .46, .48); P.head = (hc, hr)
    P.add(E(hc, hr)); P.add(C([(0, 1.86, .24), (0, 2.46, .34), (0, 2.86, .42)], [.34, .20, .20]), .10)
    P.add(E((0, 1.72, -.14), (.66, .58, .84)), .14)
    P.wing = sym(flat(SU(.08, C([(.60, 1.92, .06), (1.0, 2.26, -.20), (1.5, 2.50, -.42)], [.20, .16, .08]),
                         C([(.70, 1.80, -.2), (1.22, 1.72, -.48)], [.17, .08]), C([(.86, 2.02, -.26), (1.42, 2.02, -.50)], [.15, .07])), (1, 2, -.3), (0, .2, 1), .5))
    P.add(P.wing, .07)
    P.paint(lambda p: (P.wing(p) < .03) & (np.abs(p[:, 0]) > 1.02), 'dark')
    tail = U(*[C([(0, 1.62, -.80), (x, 1.32, -1.40)], [.16, .07]) for x in (-.24, 0, .24)]); P.add(tail, .07, 'dark')
    P.paint(inside(E((0, 2.46, .46), (.27, .34, .24))), 'dark')
    P.hard(E((0, 3.42, .42), (.25, .09, .25)), 'red')
    P.eyes(hc, hr, .23, 3.08, .62)
    P.hard(C([(0, 3.0, .86), (0, 2.92, 1.24), (0, 2.86, 1.46)], [.10, .05, .02]), 'beak', True)
    P.legs = sym(C([(.20, 1.24, -.06), (.22, .60, .0)], [.075, .06])); P.hard(P.legs, 'leg')
    for c, r, sd in [((0, .42, 0), .62, 1), ((.72, .36, .1), .40, 2), ((-.72, .36, .1), .40, 3), ((.1, .38, .62), .34, 4), ((-.1, .38, -.62), .36, 5)]:
        P.hard(puff(c, r, 6, sd), 'cloud')
    return P

def yeti_():
    P = yeti('Yeti', {'fur': '#EAF2FC', 'face': '#9CC3E6', 'nose': ('#27314B', '#3C4866'), 'horn': ('#A69C86', '#F7F0DC'), 'crystal': ('#3E8FE0', '#BDEBFF')}, scale=1.0)
    for x, y, h in [(1.10, 1.92, .50), (1.34, 1.78, .38), (.88, 2.08, .36)]:
        P.hard(sym(crystal((x, y - .14, .0), (x + .18, y + h, -.02), .15, 6, .45)), 'crystal')
    return P

def sturmvogel():
    P = birdy('Sturmvogel', {'fur': '#5D6B86', 'white': '#F4F7FC', 'tip': '#2F3A52', 'beak': ('#27314B', '#3C4866'), 'beaklo': ('#1E2436', '#2F3A52'), 'leg': ('#27314B', '#3C4866')}, beak='small', ring=None)
    P.paint(inside(E((0, 1.0, .46), (.52, .68, .44))), 'white')
    P.paint(inside(E((0, 1.44, .62), (.34, .24, .22))), 'white')
    P.paint(inside(U(*[S(t, .17) for t in BTIPS] + [S((-t[0], t[1], t[2]), .17) for t in BTIPS])), 'tip')
    return P

def wolken_schaf():
    P = stander('Wolken-Schaf', {'fur': '#39445E', 'wool': ('#B6CBE8', '#FFFFFF'), 'nose': ('#1E2436', '#1E2436'), 'hoof': '#232B3F', 'pink': '#F0A3B3'}, body=(.66, .62, .86))
    for c, r, sd in [((0, 1.30, -.34), .74, 1), ((.46, 1.06, .02), .50, 2), ((-.46, 1.06, .02), .50, 3), ((.46, 1.06, -.74), .52, 4), ((-.46, 1.06, -.74), .52, 5), ((0, 1.12, -1.12), .44, 6), ((0, 1.20, .28), .46, 7)]:
        P.add(puff(c, r, 5, sd), .06, 'wool')
    P.add(puff((0, 2.28, .46), .42, 5, 9), .05, 'wool')
    P.paint(lambda p: (P.legs(p) < .03) & (p[:, 1] < .24), 'hoof')
    P.paint(inside(sym(E((.56, 1.56, .86), (.11, .08, .08)))), 'pink')
    return P

def donnerziege():
    P = stander('Donnerziege', {'fur': '#6C7890', 'dark': '#3A4560', 'bolt': ('#E8A91F', '#FFE04D'), 'nose': ('#1E2436', '#2F3A52'), 'hoof': '#232B3F', 'light': '#C3CCDD'})
    P.paint(lambda p: (P.legs(p) < .03) & (p[:, 1] < .30), 'hoof')
    P.paint(inside(E((0, 1.46, 1.02), (.33, .20, .33))), 'light')
    P.add(C([(0, 1.30, 1.02), (0, 1.02, 1.06), (0, .82, 1.04)], [.15, .12, .03]), .07, 'dark')
    P.add(C([(0, 2.34, .34), (0, 2.02, -.26), (0, 1.56, -.70)], [.13, .15, .12]), .10, 'dark')
    # Selten: Hörner aus Blitzen
    P.hard(sym(bolt([(.24, 2.20, .36), (.50, 2.62, .30), (.34, 2.72, .28), (.66, 3.26, .20)], .085, (0, .1, 1))), 'bolt', True)
    P.hard(bolt([(.72, 1.22, -.44), (.70, .98, -.34), (.72, .96, -.54), (.70, .70, -.40)], .05, (1, 0, 0)), 'bolt')
    P.hard(bolt([(-.72, 1.22, -.44), (-.70, .98, -.34), (-.72, .96, -.54), (-.70, .70, -.40)], .05, (1, 0, 0)), 'bolt')
    return P

def himmelsdrache():
    P = dragon('Himmelsdrache', {'fur': '#7CC6F0', 'belly': '#FDF6E3', 'horn': ('#D99A12', '#FFD84D'), 'wing': ('#8FC4EE', '#E6F6FF'), 'nose': ('#3C5E7E', '#54789A'), 'cloud': ('#AFC6E6', '#FFFFFF')})
    P.hard(P.spines, 'horn')
    P.paint(inside(E((0, 1.04, 1.02), (.26, .13, .26))), 'belly')
    for c, r, sd in [((1.26, .34, -.56), .30, 1), ((-1.0, .30, -.30), .34, 2)]:
        P.hard(puff(c, r, 6, sd), 'cloud')
    return P

def berggeist():
    P = Pet('Berggeist', {'fur': '#808A9E', 'snow': ('#AFC6E6', '#FFFFFF'), 'moss': '#6FA34F', 'glow': ('#2BB5D9', '#A9F4FF'), 'nose': ('#3C4866', '#3C4866'), 'dark': '#59627A'}, True, 1.0)
    hc = (0, 1.30, .12); hr = (1.02, .92, .86); P.head = (hc, hr)
    P.add(E(hc, hr)); P.add(C([(0, 1.5, .0), (.08, 2.42, -.06), (.10, 3.26, -.08)], [.84, .50, .05]), .22)
    P.add(C([(.72, 1.1, .0), (1.10, 1.92, -.08), (1.16, 2.34, -.10)], [.54, .28, .04]), .18)
    P.add(C([(-.72, 1.1, .0), (-1.06, 1.76, -.06), (-1.12, 2.12, -.08)], [.54, .28, .04]), .18)
    P.add(E((0, .46, .0), (1.32, .46, 1.14)), .18)
    P.add(sym(C([(1.20, .92, .30), (1.56, .62, .52)], [.24, .17])), .08)
    P.paint(lambda p: p[:, 1] + .10 * np.sin(p[:, 0] * 9) + .08 * np.sin(p[:, 2] * 7 + 1) > 2.28, 'snow')
    P.paint(lambda p: (np.abs(p[:, 0]) > .72) & (p[:, 1] + .08 * np.sin(p[:, 2] * 9) > 1.74), 'snow')
    P.paint(lambda p: p[:, 1] + .06 * np.sin(p[:, 0] * 8) + .05 * np.sin(p[:, 2] * 6) < .34, 'moss')
    P.eyes(hc, hr, .38, 1.36, 1.05, ring='glow', mat='eye')
    P.smile(.92, .90, w=.22, d=.06, back=.12)
    # Legendär: schwebende Felsen und Glühkugeln
    for a, y, r in [(.4, 2.02, .13), (2.4, 2.26, .11), (4.2, 1.98, .12)]:
        P.hard(S((1.72 * np.cos(a), y, 1.0 * np.sin(a)), r), 'glow')
    for a, y, r in [(.05, 1.42, .20), (3.1, 1.56, .17), (4.7, 1.30, .18)]:
        P.hard(crystal((1.9 * np.cos(a), y - r, 1.1 * np.sin(a)), (1.9 * np.cos(a), y + r * 1.2, 1.1 * np.sin(a)), r, 5, .6), 'dark')
    return P

def kristall_kaefer():
    P = Pet('Kristall-Käfer', {'fur': '#27405A', 'shell': '#2FB8B0', 'crystal': ('#2E9FD9', '#C9F6FF'), 'nose': ('#1E2436', '#1E2436'), 'leg': '#1E2F44', 'ball': '#7CF5C8'}, True, 1.2)
    hc = (0, .94, .74); hr = (.62, .54, .48); P.head = (hc, hr)
    P.add(E(hc, hr)); P.shell = E((0, .92, -.26), (.92, .76, 1.08)); P.add(P.shell, .05, 'shell')
    P.line([(0, 1.66, z) for z in np.linspace(.24, -1.2, 12)], .05, 'nose')
    P.eyes(hc, hr, .27, 1.0, .88)
    P.omega(.74, 1.17, w=.11, d=.035, stem=False, back=.06)
    P.hard(sym(C([(.20, 1.40, .78), (.34, 1.84, .86), (.52, 2.0, .86)], [.05, .04, .03])), 'leg')
    P.hard(sym(S((.56, 2.02, .86), .10)), 'ball')
    for z in (.30, -.26, -.82):
        P.hard(sym(C([(.72, .44, z), (1.08, .30, z + .06), (1.18, .10, z + .12)], [.10, .085, .07])), 'leg')
    for a, b, r in [((0, 1.46, -.28), (.0, 2.34, -.34), .20), ((.30, 1.42, -.46), (.52, 2.02, -.56), .15), ((-.30, 1.42, -.46), (-.52, 2.02, -.56), .15), ((.28, 1.46, .04), (.44, 1.92, .10), .12), ((-.28, 1.46, .04), (-.44, 1.92, .10), .12)]:
        P.hard(crystal(a, b, r, 6, .42), 'crystal')
    return P

def frost_fledermaus():
    P = Pet('Frost-Fledermaus', {'fur': '#BFE0F7', 'wing': ('#3E6BB0', '#6E9BDF'), 'inner': '#7FA6E0', 'nose': ('#3C4866', '#3C4866'), 'fang': ('#C9D6E6', '#FFFFFF'), 'belly': '#EAF7FF', 'leg': '#3E6BB0'}, False, 1.1)
    hc = (0, 1.44, .08); hr = (.84, .78, .74); P.head = (hc, hr)
    P.add(E(hc, hr)); P.add(E((0, .86, -.02), (.54, .54, .50)), .16)
    P.paint(inside(E((0, .84, .42), (.34, .40, .22))), 'belly')
    ear(P, (.46, 1.96, .02), (.80, 3.02, -.08), .34, .07, mid=(.68, 2.50, -.04), f=.5)
    for x, y, z in [(.74, 1.86, .10), (.0, 2.24, .12)]:
        P.add(sym(C([(x * .8, y - .1, z), (x * 1.04, y + .10, z + .12)], [.14, .05])), .08)
    P.eyes(hc, hr, .38, 1.52, 1.05)
    P.hard(E((0, 1.33, .84), (.075, .05, .05)), 'nose', True)
    P.omega(1.22, .84, w=.12, d=.03, stem=False, back=.05)
    P.hard(sym(C([(.11, 1.20, .78), (.115, 1.08, .79)], [.042, .012])), 'fang', True)
    sh = (.66, 1.44, -.10); ms = []
    for tip in [(2.02, 2.22, -.28), (2.16, 1.46, -.28), (1.74, .86, -.26), (1.18, .66, -.22)]:
        m = ((sh[0] + tip[0]) * .55, (sh[1] + tip[1]) * .5, -.2); ms.append(C([sh, m, tip], [.10, .24, .03]))
    P.hard(sym(flat(SU(.16, *ms), (1.3, 1.4, -.22), (0, 0, 1), .26)), 'wing')
    P.hard(sym(C([(.20, .44, .08), (.22, .28, .16)], [.08, .05])), 'leg')
    return P

def glitzer_hirsch():
    P = stander('Glitzer-Hirsch', {'fur': '#C9A9E8', 'white': '#FBF6FF', 'crystal': ('#7A5BD9', '#E7DBFF'), 'nose': ('#3C2E5E', '#55447E'), 'hoof': '#5B4A8A', 'star': ('#FFC94D', '#FFF3B8')})
    P.paint(lambda p: (P.legs(p) < .03) & (p[:, 1] < .26), 'hoof')
    P.paint(inside(E((0, 1.44, 1.02), (.33, .20, .33))), 'white')
    P.paint(inside(E((0, .62, -.16), (.42, .26, .64))), 'white')
    for c in [(.44, 1.40, -.30), (-.44, 1.40, -.30), (.16, 1.54, -.70), (-.16, 1.54, -.70), (.54, 1.22, -.82), (-.54, 1.22, -.82), (.58, 1.14, .02), (-.58, 1.14, .02)]:
        P.paint(inside(S(c, .085)), 'white')
    # Selten: Geweih aus Kristallen, Sterne
    for s in (-1, 1):
        P.hard(crystal((s * .24, 2.16, .36), (s * .54, 3.14, .22), .10, 5, .3), 'crystal')
        P.hard(crystal((s * .40, 2.56, .30), (s * .86, 3.00, .26), .08, 5, .4), 'crystal')
        P.hard(crystal((s * .30, 2.34, .34), (s * .12, 2.86, .40), .075, 5, .4), 'crystal')
        P.hard(crystal((s * .49, 2.86, .25), (s * .32, 3.24, .28), .06, 5, .4), 'crystal')
    P.hard(star((.74, 1.0, -.46), (1, 0, 0), .15, .05), 'star'); P.hard(star((-.74, 1.0, -.46), (-1, 0, 0), .15, .05), 'star')
    return P

def eis_phoenix():
    ice = {'stops': ['#2F6FE0', '#4FC4F0', '#BDF0FF', '#FFFFFF'], 't': lambda p: np.clip((p[:, 1] + .35 * np.abs(p[:, 0]) - .3) / 2.5, 0, 1)}
    P = birdy('Eis-Phönix', {'fur': ice, 'beak': ('#D99A12', '#FFD84D'), 'beaklo': ('#B9860F', '#E8B830'), 'leg': ('#D99A12', '#FFD84D'), 'crystal': ('#3E8FE0', '#D9F8FF')}, beak='small', crest=False, wings='open', tail=False)
    P.add(sym(C([(.0, 2.26, .02), (.32, 2.80, -.20), (.52, 3.08, -.34)], [.15, .08, .03])), .08)
    P.add(C([(0, 2.30, .02), (0, 2.96, -.26), (0, 3.34, -.42)], [.16, .09, .03]), .08)
    for x, y, z in [(0, .56, -1.86), (.48, .62, -1.72), (-.48, .62, -1.72)]:
        P.add(C([(0, .82, -.56), ((x * .55), .54, (z - .4) * .62), (x, y, z)], [.20, .17, .05]), .09)
        P.hard(crystal((x * 1.0, y, z - .02), (x * 1.16, y + .02, z - .46), .13, 6, .6), 'crystal')
    return P

PETS = {'yak': yak, 'rotpanda': rotpanda, 'schneeleopard': schneeleopard, 'wolkenkranich': wolkenkranich, 'yeti': yeti_, 'sturmvogel': sturmvogel, 'wolken-schaf': wolken_schaf,
        'donnerziege': donnerziege, 'himmelsdrache': himmelsdrache, 'berggeist': berggeist, 'kristall-kaefer': kristall_kaefer, 'frost-fledermaus': frost_fledermaus,
        'glitzer-hirsch': glitzer_hirsch, 'eis-phoenix': eis_phoenix}
