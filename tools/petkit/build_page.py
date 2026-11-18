"""Baut die Sammelbuch-Seite aus build2 (Version 2)."""
import json, pathlib, struct, sys, shutil
R = pathlib.Path(__file__).resolve().parent; sys.path.insert(0, str(R))
from pets_meta import META
from PIL import Image
SRC = R / 'build2'; OUT = R / 'page/pets'
if OUT.exists(): shutil.rmtree(OUT)
OUT.mkdir(parents=True)
t = (R/'page/template.html').read_text().replace('/*VIEWER*/', (R/'viewer.js').read_text())
info = {}
for name, (p, notes) in META.items():
    b = (SRC/f'{p}.glb').read_bytes()
    jl = struct.unpack('<I', b[12:16])[0]; j = json.loads(b[20:20+jl])
    acc = j['accessors']; info[p] = {'tris': acc[0]['count'] // 3, 'height': round(acc[1]['max'][1], 1)}
    (OUT/f'{p}.glb').write_bytes(b)
    Image.open(SRC/f'vorschau/{p}.png').convert('RGBA').resize((132, 132), Image.LANCZOS).save(OUT/f'{p}.png', optimize=True)
    for v in ('textur', 'gold', 'regenbogen', 'frostig'):
        shutil.copy(SRC/f'tex/{p}_{v}.png', OUT/f'{p}_{v}.png')
models = {k: {'file': v[0], 'status': 'Version 2', 'notes': v[1]} for k, v in META.items()}
t = t.replace('/*MODELS*/{}', json.dumps(models, ensure_ascii=False)).replace('/*INFO*/', 'const INFO = ' + json.dumps(info) + ';')
(R/'page/snow-rush-pets.html').write_text(t)
print(len(info), 'max tris', max(i['tris'] for i in info.values()), 'html', len(t))
