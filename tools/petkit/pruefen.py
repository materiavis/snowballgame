"""Prüft gebaute Pets vor dem Import in Roblox Studio.
Aufruf: python3 pruefen.py build2/schneehase.glb [weitere.glb ...] [--bilder ordner]

Geprüft wird pro Datei:
- genau 1 Mesh, 1 Primitive, 1 Textur (PNG eingebettet), unter 3'000 Dreiecken
- Nullpunkt unten in der Mitte (min Y = 0, X und Z zentriert)
- Höhe gegen die Zielgrösse nach Seltenheit (wow.RARITY, kit.RARITY_SIZE)
- Vorderseite nach +Z: die Augen (Texturspalten 0 und 1) liegen vorne
- UVs innerhalb der Textur
Mit --bilder wird pro Pet eine Ansicht von vorne (+Z) und von der Seite gespeichert.
"""
import sys, json, struct, io, pathlib
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))


def read_glb(path):
    b = pathlib.Path(path).read_bytes()
    magic, ver, total = struct.unpack('<III', b[:12])
    assert magic == 0x46546C67 and ver == 2, 'keine glTF-2.0-GLB'
    jl = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    st = 20 + jl + 8
    def view(i):
        v = j['bufferViews'][i]; return b[st + v['byteOffset']: st + v['byteOffset'] + v['byteLength']]
    def acc(i, dt, n):
        a = j['accessors'][i]; return np.frombuffer(view(a['bufferView']), dt).reshape(-1, n)[:a['count']]
    prim = j['meshes'][0]['primitives'][0]; at = prim['attributes']
    pos = acc(at['POSITION'], '<f4', 3); uv = acc(at['TEXCOORD_0'], '<f4', 2)
    idx = acc(prim['indices'], '<u2', 1).reshape(-1, 3)
    png = view(j['images'][0]['bufferView'])
    return j, pos, uv, idx, png


def check(path):
    from wow import RARITY
    from kit import RARITY_SIZE, TW, SW
    j, pos, uv, idx, png = read_glb(path)
    slug = pathlib.Path(path).stem
    res = {'pet': slug}; ok = True
    def chk(name, cond, info):
        nonlocal ok
        res[name] = ('OK ' if cond else 'FEHLER ') + info; ok &= bool(cond)
    chk('aufbau', len(j['meshes']) == 1 and len(j['meshes'][0]['primitives']) == 1 and len(j['images']) == 1,
        f"{len(j['meshes'])} Mesh, {len(j['meshes'][0]['primitives'])} Primitive, {len(j['images'])} Textur")
    chk('dreiecke', len(idx) < 3000, f'{len(idx)}')
    lo, hi = pos.min(0), pos.max(0); ext = hi - lo
    chk('nullpunkt', abs(lo[1]) < 1e-3 and abs(lo[0] + hi[0]) < .5 and abs(lo[2] + hi[2]) < .5,
        '(Mitte = Körper ohne Glitzer, ganze Box darf leicht daneben liegen) ' + f'min Y {lo[1]:.3f}, Mitte X {(lo[0] + hi[0]) / 2:.3f}, Mitte Z {(lo[2] + hi[2]) / 2:.3f}')
    if slug in RARITY:
        target = RARITY_SIZE[RARITY[slug]]
        # Höhe inklusive Glitzer kann über dem Ziel liegen, der Körper ist auf das Ziel skaliert
        chk('groesse', ext[1] >= target - .05, f'Box {ext[0]:.2f} x {ext[1]:.2f} x {ext[2]:.2f} Studs, Ziel Körper {target}')
    eyes = uv[:, 0] < 2 * SW / TW
    ez = pos[eyes, 2].mean() if eyes.any() else float('nan')
    chk('vorne_plus_z', eyes.any() and ez > .3 * hi[2], f'Augen bei Z {ez:.2f} (vorderster Punkt {hi[2]:.2f})')
    chk('uv', (uv >= 0).all() and (uv <= 1).all(), f'U {uv[:, 0].min():.2f}..{uv[:, 0].max():.2f}, V {uv[:, 1].min():.2f}..{uv[:, 1].max():.2f}')
    from PIL import Image
    im = Image.open(io.BytesIO(png)); chk('textur', im.format == 'PNG', f'{im.format} {im.size[0]}x{im.size[1]}')
    res['gesamt'] = 'OK' if ok else 'FEHLER'
    return res, (pos, uv, idx, im)


def bilder(path, data, out):
    import matplotlib; matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection
    pos, uv, idx, im = data
    tex = np.asarray(im.convert('RGB')) / 255.0
    h, w, _ = tex.shape
    c_uv = uv[idx].mean(1)
    col = tex[np.clip((c_uv[:, 1] * h).astype(int), 0, h - 1), np.clip((c_uv[:, 0] * w).astype(int), 0, w - 1)]
    fig = plt.figure(figsize=(8, 4.2))
    for k, (elev, azim, title) in enumerate([(0, -90, 'vorne (+Z)'), (0, 0, 'Seite (+X)')]):
        ax = fig.add_subplot(1, 2, k + 1, projection='3d')
        # Roblox: Y oben. Matplotlib: Z oben, darum (x, -z, y) zeigen, Blick von +Z
        P = np.stack([pos[:, 0], -pos[:, 2], pos[:, 1]], 1)
        ax.add_collection3d(Poly3DCollection(P[idx], facecolors=col, edgecolors='none'))
        m = np.abs(P).max(); ax.set_xlim(-m, m); ax.set_ylim(-m, m); ax.set_zlim(0, 2 * m)
        ax.view_init(elev=elev, azim=azim); ax.set_axis_off(); ax.set_title(title)
        ax.set_proj_type('ortho'); ax.set_box_aspect((1, 1, 1))
    fig.suptitle(pathlib.Path(path).stem); fig.tight_layout()
    out = pathlib.Path(out); out.mkdir(parents=True, exist_ok=True)
    fig.savefig(out / f'{pathlib.Path(path).stem}_ansicht.png', dpi=110); plt.close(fig)


if __name__ == '__main__':
    args = sys.argv[1:]; out = None
    if '--bilder' in args:
        i = args.index('--bilder'); out = args[i + 1]; del args[i:i + 2]
    alle_ok = True
    for p in args:
        r, data = check(p); alle_ok &= r['gesamt'] == 'OK'
        print(json.dumps(r, ensure_ascii=False, indent=1))
        if out: bilder(p, data, out)
    sys.exit(0 if alle_ok else 1)
