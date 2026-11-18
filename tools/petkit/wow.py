"""Version 2: bunter und auffälliger. Formen kommen aus alt3 und katalog_1..3,
hier stehen pro Pet die neuen Farben, die Irisfarbe und die Extras je Seltenheit."""
import numpy as np
from kit import Pet, RARITY_SIZE, norm
import alt3, katalog_1, katalog_2, katalog_3
from pets_meta import META

BASE = {**alt3.PETS, **katalog_1.PETS, **katalog_2.PETS, **katalog_3.PETS}
SLUGS = [v[0] for v in META.values()]
RARITY = {s: (i % 5 if i < 50 else 5) for i, s in enumerate(SLUGS)}

def HG(stops, a=0.0, b=2.6):
    """Farbverlauf nach Höhe."""
    return {'stops': stops, 't': lambda p: np.clip((p[:, 1] - a) / (b - a), 0, 1)}

GOLD = ('#C98A00', '#FFE14D')
IRIS = {'pink': ['#7A1F5C', '#E0479E', '#FFB3DA'], 'gold': ['#7A3E00', '#FFB800', '#FFF0A0'], 'violet': ['#3B1E5E', '#8A5CF0', '#D8C2FF'],
        'emerald': ['#0B4D2E', '#19C77A', '#B6FFD9'], 'amber': ['#5A2A00', '#E08A1E', '#FFD38A'], 'teal': ['#0E4A5E', '#1FB5D9', '#B8F2FF'],
        'sapphire': ['#0B2E7A', '#2F7BFF', '#BFE0FF'], 'aqua': ['#063E5E', '#12A7E0', '#A8F0FF'], 'ice': ['#0B5E7A', '#1FE0FF', '#D0FFFF'],
        'magenta': ['#5E0B6E', '#E03DFF', '#FFC0FF'], 'jade': ['#0B5E3A', '#1FD98A', '#C8FFE0'], 'lime': ['#3D5E00', '#9CFF1F', '#E8FFB0'],
        'rose': ['#5E0B4E', '#FF3DA8', '#FFC0E8'], 'orange': ['#7A2E00', '#FF7A1F', '#FFD0A0'], 'yellow': ['#7A5E00', '#FFD21F', '#FFF5A0'],
        'fire': ['#C2185B', '#FF7A00', '#FFE14D']}

# slug: (Farben, Iris, Wangen, Anzahl Glitzer, Glitzerfarbe, Heiligenschein)
STYLE = {
 'schneehase': ({'fur': HG(['#C9D2FF', '#FFFFFF'], 0, 2.0), 'inner': '#FF7FAE', 'tip': '#3A2D6E', 'nose': '#FF6F9C', 'mouth': ('#7A3E5E', '#7A3E5E')}, 'pink', '#FF9EC2', 0, None, None),
 'bergdohle': ({'fur': HG(['#2A1B78', '#2B4FC0', '#1FB0B8'], .2, 2.5), 'tips': '#45E0D0', 'ring': ('#B8C8F0', '#F0F4FF'), 'beak': ('#E09A00', '#FFD23F'), 'beaklo': ('#C27A00', '#F2A81D'), 'leg': ('#C2201F', '#FF4D4D')}, 'gold', '#FF7FA8', 0, None, None),
 'murmeltier': ({'fur': HG(['#B8561F', '#F0A05A'], 0, 2.6), 'cream': '#FFEBCB', 'dark': '#7A3E22', 'tooth': ('#E07A10', '#FFC060'), 'petal': ('#C8D8F0', '#FFFFFF'), 'center': ('#E0A000', '#FFE14D'), 'nose': ('#4A1E2A', '#6A2E3A')}, 'violet', '#FF8C8C', 2, '#FFE14D', None),
 'rotfuchs': ({'fur': HG(['#F0301F', '#FF8A1F'], 0, 2.4), 'white': '#FFF6E8', 'dark': '#2B1B3D', 'inner': '#2B1B3D', 'hat': '#1FAE6B', 'band': '#FF2E63', 'feather': '#FFFFFF', 'nose': ('#1E1230', '#3A2650')}, 'emerald', '#FF6F91', 4, '#FFD84D', None),
 'schneeeule': ({'fur': HG(['#BFD2FF', '#FFFFFF'], 0, 2.2), 'spot': '#6C7BFF', 'beak': '#3A2D6E', 'leg': '#E8F0FF', 'gold': GOLD, 'face': '#FFFFFF'}, 'gold', '#FFA8C8', 6, '#FFE14D', None),
 'gaemse': ({'fur': HG(['#8A3F14', '#E0943D'], 0, 2.4), 'cream': '#FFF0D6', 'dark': '#2B1A12', 'horn': ('#1E1630', '#3A2E5A'), 'hoof': '#3A2A40', 'nose': ('#1E1230', '#3A2650')}, 'amber', '#FF8FA0', 0, None, None),
 'steinbock': ({'fur': HG(['#93602E', '#E8BC80'], 0, 2.4), 'cream': '#FFF3DC', 'dark': '#6B4423', 'horn': ('#B98A3E', '#FFF1C9'), 'hoof': '#3B2E26', 'nose': ('#1E1230', '#3A2650')}, 'teal', '#FF9C8C', 0, None, None),
 'bernhardiner': ({'fur': '#FFFFFF', 'patch': '#E8701A', 'mask': '#7A3010', 'inner': '#E8701A', 'wood': '#C98A3E', 'band': GOLD, 'collar': '#FF2E63', 'nose': ('#1E1230', '#3A2650')}, 'amber', '#FF8FA0', 2, '#FFE14D', None),
 'steinadler': ({'fur': HG(['#5A2410', '#E08A2E'], .2, 2.4), 'light': '#FFD36B', 'tip': '#3A1E5E', 'beak': ('#E09A00', '#FFD23F'), 'beaklo': ('#C27A00', '#F2A81D'), 'leg': ('#E09A00', '#FFC21F')}, 'gold', '#FF8F7A', 4, '#FFE14D', None),
 'goldener-steinbock': ({'fur': HG(['#FF8A1C', '#FFE066'], 0, 2.4), 'cream': '#FFFBEA', 'horn': ('#C98A00', '#FFF4B0'), 'nose': ('#8A4B00', '#A8601A'), 'hoof': '#C98A00', 'sun': ('#FF6A00', '#FFE14D'), 'gem': ('#C2185B', '#FF4F9A')}, 'sapphire', '#FF8F7A', 6, '#FFE14D', None),
 'robbe': ({'fur': HG(['#9FD0FF', '#FFFFFF'], 0, 1.6), 'spot': '#A8A0FF', 'nose': ('#2B2240', '#4A3E6E')}, 'aqua', '#FF9EC2', 0, None, None),
 'pinguin': ({'fur': HG(['#1A1F7A', '#2E5BFF'], .2, 2.6), 'belly': '#FFFFFF', 'beak': ('#E05A00', '#FFB020'), 'leg': ('#E05A00', '#FFB020'), 'cheek': '#FFE14D'}, 'aqua', '#FF8FB1', 0, None, None),
 'walross': ({'fur': HG(['#93421F', '#E39A62'], 0, 2.2), 'pad': '#FFD9B0', 'tusk': ('#CFC3A3', '#FFFFFF'), 'nose': ('#7A2E3E', '#A8455A'), 'hat': '#FF2E63', 'brim': '#FFFFFF'}, 'teal', '#FF8FA0', 2, '#BDF0FF', None),
 'polarfuchs': ({'fur': HG(['#B8DCFF', '#FFFFFF'], 0, 2.0), 'blue': '#6FBFFF', 'inner': '#FF9EC2', 'scarf': '#2F6BFF', 'scarf2': '#7FE8FF', 'nose': ('#2B2240', '#4A3E6E')}, 'sapphire', '#FF9EC2', 4, '#BDF0FF', None),
 'eisbaer': ({'fur': HG(['#B8DCFF', '#FFFFFF'], 0, 2.0), 'inner': '#9FD0FF', 'crystal': ('#2F7BFF', '#C8F8FF'), 'gold': GOLD, 'nose': ('#2B2240', '#4A3E6E')}, 'sapphire', '#FF9EC2', 6, '#BDF0FF', None),
 'schneehuhn': ({'fur': HG(['#FFD2B8', '#FFFFFF'], 0, 2.0), 'tip': '#FFA87A', 'beak': '#3A2D6E', 'leg': '#FFF0E6', 'comb': ('#D0102E', '#FF4F5E')}, 'orange', '#FF8FA0', 0, None, None),
 'narwal': ({'fur': HG(['#2FD1C8', '#3B6BFF'], .4, 1.9), 'belly': '#F0FBFF', 'spot': '#1E3A9E', 'horn': ('#E0B33C', '#FFF6C8'), 'nose': ('#0E1E4E', '#0E1E4E')}, 'aqua', '#FF9EC2', 0, None, None),
 'orca': ({'fur': HG(['#101438', '#2B3AA8'], .3, 2.2), 'belly': '#FFFFFF', 'ring': ('#9FB4FF', '#F0F4FF'), 'hat': '#FFFFFF', 'band': '#FF2E63', 'nose': ('#0E1436', '#0E1436')}, 'aqua', '#FF8FB1', 2, '#BDF0FF', None),
 'schneewolf': ({'fur': HG(['#6F7FFF', '#E8EEFF'], 0, 2.2), 'white': '#FFFFFF', 'dark': '#3B3FA8', 'inner': '#3B3FA8', 'crystal': ('#2F7BFF', '#C8F8FF'), 'collar': '#FF2E63', 'nose': ('#1E1230', '#3A2650')}, 'ice', '#FF9EC2', 4, '#BDF0FF', None),
 'polarlicht-fuchs': ({'fur': HG(['#DCCBFF', '#FFFFFF'], 0, 2.0), 'inner': '#B678FF', 'aurora': ['#3DFFB0', '#3DC8FF', '#7A6BFF', '#FF6BE0'], 'star': ('#3DFFB0', '#E8FFF5'), 'nose': ('#3A1E5E', '#5A3A8E')}, 'magenta', '#FF9EC2', 6, '#B8FFF0', ('#C98A00', '#FFE14D')),
 'yak': ({'fur': HG(['#4A2216', '#A0603C'], 0, 2.6), 'cream': '#FFE3C2', 'horn': ('#C9B88A', '#FFFBEA'), 'hoof': '#2B1A12', 'nose': ('#2B1A12', '#4A2E22')}, 'amber', '#FF8FA0', 0, None, None),
 'rotpanda': ({'fur': HG(['#D8301F', '#FF8A2E'], 0, 2.2), 'white': '#FFF8EE', 'dark': '#3D1A2E', 'inner': '#3D1A2E', 'nose': ('#1E1230', '#3A2650')}, 'amber', '#FF8FA0', 0, None, None),
 'schneeleopard': ({'fur': HG(['#CFC4FF', '#FFF8F0'], 0, 2.0), 'white': '#FFFFFF', 'spot': '#5A3FA8', 'nose': ('#E0607E', '#FF9EB8'), 'inner': '#C8B8FF', 'collar': '#1FBF8F', 'gem': ('#0B8A6E', '#7FFFE0')}, 'jade', '#FF9EC2', 2, '#7FFFE0', None),
 'wolkenkranich': ({'fur': HG(['#FFE0F0', '#FFFFFF'], 1.0, 3.2), 'dark': '#1E2A6E', 'red': ('#D0102E', '#FF4F5E'), 'beak': ('#E09A00', '#FFC21F'), 'leg': '#1E2A6E', 'cloud': ('#FFA8D0', '#FFFFFF'), 'gold': GOLD}, 'gold', '#FF9EC2', 4, '#FFE14D', None),
 'yeti': ({'fur': HG(['#6FAEFF', '#F0F8FF'], 0, 2.8), 'face': '#4FA0FF', 'nose': ('#1E2A6E', '#2E3E9E'), 'horn': ('#C9B88A', '#FFFBEA'), 'crystal': ('#2F7BFF', '#C8F8FF')}, 'ice', '#FF9EC2', 6, '#BDF0FF', ('#C98A00', '#FFE14D')),
 'sturmvogel': ({'fur': HG(['#3B2A8F', '#6B8BFF'], .2, 2.5), 'white': '#FFFFFF', 'tip': '#1E1A5E', 'beak': ('#E09A00', '#FFC21F'), 'beaklo': ('#C27A00', '#F2A81D'), 'leg': ('#E06A00', '#FF8A1F')}, 'yellow', '#FF8FB1', 0, None, None),
 'wolken-schaf': ({'fur': '#2B2A5E', 'wool': {'stops': ['#FFC8E8', '#FFFFFF', '#BFE4FF'], 't': lambda p: np.clip((p[:, 0] + 1.0) / 2.0, 0, 1)}, 'hoof': '#1E1A40', 'pink': '#FF8FB1', 'nose': ('#1E1A40', '#1E1A40')}, 'magenta', '#FF8FB1', 0, None, None),
 'donnerziege': ({'fur': HG(['#3B2A8F', '#8A7BFF'], 0, 2.4), 'dark': '#1E1A5E', 'bolt': ('#FFA000', '#FFF04D'), 'hoof': '#1E1A40', 'light': '#E0E0FF', 'nose': ('#1E1A40', '#2E2A60')}, 'yellow', '#FF8FB1', 2, '#FFF04D', None),
 'himmelsdrache': ({'fur': HG(['#1F8FFF', '#7FF0FF'], 0, 2.4), 'belly': '#FFF6D0', 'horn': ('#FFA000', '#FFE84D'), 'wing': ('#5FC0FF', '#E8FBFF'), 'cloud': ('#FFA8D0', '#FFFFFF'), 'nose': ('#1E4A8E', '#2E6AB8')}, 'gold', '#FF9EC2', 4, '#FFE14D', None),
 'berggeist': ({'fur': HG(['#4A5AA8', '#A8B4E8'], 0, 2.4), 'snow': ('#BFD7FF', '#FFFFFF'), 'moss': '#3DDC84', 'glow': ('#00C8FF', '#B8FFFF'), 'dark': ('#7A3FFF', '#D0A8FF'), 'nose': ('#1E2A6E', '#1E2A6E')}, 'ice', '#FF9EC2', 4, '#B8FFFF', None),
 'kristall-kaefer': ({'fur': HG(['#2B1A6E', '#4A3FD9'], 0, 1.6), 'shell': {'stops': ['#1FD9C8', '#3B6BFF', '#B65BFF'], 't': lambda p: np.clip((p[:, 1] - .3) / 1.4, 0, 1)}, 'crystal': ('#E03DB0', '#FFD0F5'), 'leg': '#1E1A5E', 'ball': ('#E0A000', '#FFE14D'), 'nose': ('#1E1A5E', '#1E1A5E')}, 'lime', '#FF9EC2', 0, None, None),
 'frost-fledermaus': ({'fur': HG(['#6FB0FF', '#E0F4FF'], .4, 2.4), 'wing': ('#4A2FC0', '#B47BFF'), 'inner': '#FF9EC2', 'belly': '#FFFFFF', 'fang': ('#D0D8F0', '#FFFFFF'), 'leg': '#5A3FD9', 'nose': ('#2B2A5E', '#2B2A5E')}, 'rose', '#FF9EC2', 0, None, None),
 'glitzer-hirsch': ({'fur': HG(['#A060FF', '#FFB0E0'], 0, 2.4), 'white': '#FFFFFF', 'crystal': ('#7A3FFF', '#E8DCFF'), 'nose': ('#3D1A5E', '#5A2E8E'), 'hoof': '#5A2A9E', 'star': ('#FFA000', '#FFF3B0')}, 'gold', '#FF8FD0', 2, '#FFE14D', None),
 'eis-phoenix': ({'fur': ['#5B2FFF', '#2FA8FF', '#7FF0FF', '#FFFFFF'], 'beak': ('#E09A00', '#FFC21F'), 'beaklo': ('#C27A00', '#F2A81D'), 'leg': ('#E09A00', '#FFC21F'), 'crystal': ('#E03DB0', '#FFE0F5')}, 'gold', '#FF9EC2', 4, '#BDF0FF', None),
 'kristall-drache': ({'fur': HG(['#2FB8FF', '#B678FF'], 0, 2.4), 'belly': '#F0FBFF', 'horn': ('#2F7BFF', '#D0F8FF'), 'wing': ('#9A5BFF', '#F0E0FF'), 'gem': ('#E0107A', '#FFC0E0'), 'nose': ('#1E2A6E', '#2E3E9E')}, 'magenta', '#FF9EC2', 6, '#E0C8FF', None),
 'spiegel-katze': ({'fur': '#FFE8F4', 'mirror': '#2B2A9E', 'inner': '#FF9EC2', 'nose': ('#E0607E', '#FF9EB8')}, ['#7A3E00', '#FFC21F', '#0B2E7A', '#3FA9FF'], '#FF9EC2', 0, None, None),
 'eis-golem': ({'fur': ['#2F4BFF', '#3DC8FF', '#C8FAFF'], 'glow': ('#00D0FF', '#C8FFFF'), 'crystal': ('#E03DB0', '#FFE0F5'), 'nose': ('#0E2A6E', '#0E2A6E')}, 'ice', '#FF9EC2', 0, None, None),
 'frost-einhorn': ({'fur': HG(['#E0D4FF', '#FFFFFF'], 0, 2.4), 'mane': ['#6FF0FF', '#B678FF', '#FF8FD0'], 'horn': ('#9A5BFF', '#F0E8FF'), 'hoof': '#B678FF', 'nose': ('#9A80D0', '#B8A0E8')}, 'magenta', '#FF9EC2', 2, '#FFE0F5', None),
 'polarlicht-schlange': ({'fur': ['#3DFFB0', '#3DC8FF', '#7A6BFF', '#FF6BE0'], 'belly': '#FFFFFF', 'star': ('#FFA000', '#FFF3B0'), 'tongue': ('#D0102E', '#FF4F5E'), 'nose': ('#1E1A5E', '#2E2A80')}, 'gold', '#FF9EC2', 4, '#B8FFF0', None),
 'frostkoenig': ({'fur': HG(['#6FC0FF', '#D8F2FF'], .8, 2.6), 'white': ('#BFD7FF', '#FFFFFF'), 'cape': HG(['#4A1FBF', '#2F6BFF'], .3, 1.4), 'gold': GOLD, 'crystal': ('#3DC8FF', '#E0FBFF'), 'gem': ('#C2185B', '#FF4F9A'), 'nose': ('#6F90E0', '#9AB8FF')}, 'sapphire', '#FF9EC2', 6, '#FFE14D', None),
 'astronauten-hund': ({'fur': HG(['#D0661F', '#FFB870'], .8, 2.4), 'suit': ('#B8C8FF', '#FFFFFF'), 'inner': '#B8551F', 'metal': '#5B6BFF', 'red': ('#D0102E', '#FF4F5E'), 'blue': ('#1FA0FF', '#8AE0FF'), 'dark': '#1E1A40', 'nose': ('#2B1A12', '#4A2E22')}, 'amber', '#FF8FA0', 0, None, None),
 'mond-hase': ({'fur': HG(['#A898FF', '#F0EEFF'], 0, 2.4), 'crater': '#8A78E8', 'inner': '#FF9EC2', 'moon': ('#FFA000', '#FFE84D'), 'nose': ('#7A5BD9', '#9A80F0')}, 'gold', '#FF9EC2', 0, None, None),
 'kometen-fuchs': ({'fur': HG(['#2B1FBF', '#3D8AFF'], 0, 2.2), 'white': '#F0FBFF', 'inner': '#1E1A6E', 'comet': ['#3D8AFF', '#7FF0FF', '#FFF8C8'], 'star': ('#FFA000', '#FFE84D'), 'nose': ('#0E0E2E', '#1E1E4E')}, 'ice', '#FF9EC2', 2, '#FFE14D', None),
 'sternen-wal': ({'fur': HG(['#1E1A6E', '#5A2FD0'], .3, 2.0), 'belly': '#7FA8FF', 'spot': ('#FFB000', '#FFF3A0'), 'star': ('#FFA000', '#FFE84D'), 'ring': ('#7FA8FF', '#E0EBFF'), 'nose': ('#0E0E2E', '#0E0E2E')}, 'gold', '#FF8FD0', 4, '#FFE14D', None),
 'galaxie-drache': ({'fur': ['#1E1450', '#4A2AB8', '#C04FFF', '#FF6BC8'], 'belly': '#FFD0F5', 'horn': ('#FFA000', '#FFE84D'), 'wing': ('#2B1A8F', '#7A4FFF'), 'nose': ('#1E1450', '#1E1450')}, 'rose', '#FF8FD0', 6, '#FFE14D', None),
 'alien-pinguin': ({'fur': HG(['#00A86B', '#7FFF5B'], .2, 2.8), 'belly': '#E8FFE0', 'beak': ('#8A2FFF', '#D9A8FF'), 'leg': ('#8A2FFF', '#D9A8FF'), 'ball': ('#E0107A', '#FFA8D9'), 'dark': '#007A4A'}, 'magenta', '#FF8FD0', 0, None, None),
 'saturn-schildkroete': ({'fur': HG(['#1FA85B', '#8AFF7A'], 0, 1.4), 'shell': ['#FF7A2E', '#FFE08A', '#FF4F5E'], 'ring': ['#B678FF', '#4FD0FF'], 'nose': ('#0E4A2A', '#0E4A2A')}, 'gold', '#FF8FA0', 0, None, None),
 'nebel-qualle': ({'fur': ['#7A3DFF', '#C04FFF', '#FF6BC8', '#FFD0EA'], 'ten': ['#7A3DFF', '#3DE0FF'], 'spot': '#FFFFFF', 'nose': ('#3D1A5E', '#3D1A5E')}, 'ice', '#FF8FD0', 2, '#FFE0F5', None),
 'schwarzes-loch-katze': ({'fur': HG(['#0E0A2E', '#2E1F7A'], 0, 2.2), 'dark': '#5B2FBF', 'inner': ('#9A5BFF', '#E0C8FF'), 'disk': ['#FF2E2E', '#FF9A1F', '#FFF2A0'], 'nose': ('#9A5BFF', '#D0A8FF')}, 'orange', '#C04FFF', 4, '#FFC21F', None),
 'kosmischer-yeti': ({'fur': ['#1E1450', '#3D2AA8', '#7A4FE0', '#3DE0FF'], 'face': '#C8D8FF', 'horn': ('#FFA000', '#FFE84D'), 'star': ('#FFA000', '#FFE84D'), 'nose': ('#1E1450', '#1E1450')}, 'rose', '#FF8FD0', 4, '#E0C8FF', None),
 'goldener-yeti': ({'fur': HG(['#FF8A1C', '#FFE066'], 0, 2.8), 'face': '#FFFBEA', 'horn': ('#E0D8C0', '#FFFFFF'), 'nose': ('#8A4B00', '#A8601A')}, 'fire', '#FF8F7A', 8,
                   {'stops': ['#FF5A5A', '#FFD84D', '#59D98E', '#59A0FF'], 't': lambda p: (np.arctan2(p[:, 0], p[:, 2]) + np.pi) / (2 * np.pi)}, None),
}

def build_pet(slug):
    P = BASE[slug]()
    colors, iris, blush, nspark, sparkc, halo = STYLE[slug]
    if slug == 'spiegel-katze': P.hetero = True
    P.recolor(colors)
    P.recolor({'iris': IRIS[iris] if isinstance(iris, str) else iris, 'blush': blush})
    P.blush()
    if nspark or halo:
        lo, hi = P.bounds()
        if halo:
            c = np.array(P.head[0], float) if P.head else np.array((0, hi[1], 0))
            P.recolor({'halo': halo}); P.halo((c[0], hi[1] + .24, c[2] - .05), .46, .065, n=(0, 1, .55))
        if nspark:
            P.recolor({'spark': sparkc})
            rx = (hi[0] - lo[0]) / 2 + .28; rz = (hi[2] - lo[2]) / 2 + .2; cz = (hi[2] + lo[2]) / 2
            angs = [-1.15, 1.15, -.55, .55, -1.6, 1.6, -.9, .9]; ys = [.82, .74, .95, .62, .5, .88, .4, .7]
            pts = [(rx * np.sin(a), lo[1] + (hi[1] - lo[1]) * y, cz + rz * np.cos(a) * .55) for a, y in zip(angs[:nspark], ys[:nspark])]
            P.sparkles(pts, .13 if RARITY[slug] < 4 else .16)
    P.target = RARITY_SIZE[RARITY[slug]]
    return P
