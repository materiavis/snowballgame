"""Gold, Regenbogen und Frostig als fertige Texturen: gleiche Anordnung wie die Originaltextur,
Miggi tauscht in Roblox nur die Textur. Aufruf: python3 varianten.py <glb-ordner> <ziel-ordner>"""
import sys, json, struct, io, pathlib, colorsys
import numpy as np
from PIL import Image

def palette_from_glb(path):
    b = pathlib.Path(path).read_bytes()
    jl = struct.unpack('<I', b[12:16])[0]; j = json.loads(b[20:20 + jl]); st = 28 + jl
    v = j['bufferViews'][j['images'][0]['bufferView']]
    return Image.open(io.BytesIO(b[st + v['byteOffset']: st + v['byteOffset'] + v['byteLength']])).convert('RGB')

def ramp(L, stops):
    stops = np.array(stops, float); x = np.linspace(0, 1, len(stops))
    return np.stack([np.interp(L, x, stops[:, i]) for i in range(3)], -1)

def hexs(*h): return [[int(c[i:i + 2], 16) for i in (1, 3, 5)] for c in h]

def variants(img):
    a = np.asarray(img).astype(float); L = (a @ np.array((.299, .587, .114))) / 255
    gold = ramp(np.clip(L * 1.15, 0, 1), hexs('#3A1E00', '#9A5A00', '#F2A400', '#FFD84D', '#FFF8D0'))
    ice = ramp(np.clip(L * 1.1 + .05, 0, 1), hexs('#1E2A7A', '#3D7BFF', '#8FDFFF', '#E8FBFF', '#FFFFFF'))
    frost = a * .35 + ice * .65
    h, w, _ = a.shape
    # Regenbogen: Farbton läuft quer über die Textur. Weil das Fell ein Höhenverlauf ist,
    # liegt der Regenbogen als Band über dem Körper.
    hue = (np.arange(w) / 52.0) % 1
    rb = np.zeros_like(a)
    for x in range(w):
        vv = .45 + .55 * np.clip(L[:, x] * 1.1, 0, 1)
        rb[:, x] = np.array([colorsys.hsv_to_rgb(hue[x], .62, q) for q in vv]) * 255
    # Augen (dunkel) und Glanz (weiss) bleiben gleich, damit das Gesicht lesbar bleibt
    keep = np.zeros(L.shape, bool); keep[:, :24] = True    # Spalten 0 und 1: Pupille und Glanzpunkt
    out = {}
    for n, arr in (('gold', gold), ('regenbogen', rb), ('frostig', frost)):
        arr = np.where(keep[..., None], a, arr)
        out[n] = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    return out

if __name__ == '__main__':
    src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]); dst.mkdir(parents=True, exist_ok=True)
    for g in sorted(src.glob('*.glb')):
        img = palette_from_glb(g); img.save(dst / f'{g.stem}_textur.png', optimize=True)
        for n, im in variants(img).items(): im.save(dst / f'{g.stem}_{n}.png', optimize=True)
    print(len(list(dst.glob('*.png'))))
