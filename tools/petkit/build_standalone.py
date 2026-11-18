"""Eigenständige Datei: alle Modelle, Bilder und Varianten als base64 eingebettet."""
import base64, json, pathlib, sys
import pathlib as _pl; ROOT = _pl.Path(__file__).resolve().parent; sys.path.insert(0, str(ROOT))
from pets_meta import META
R = ROOT / 'page'
PETS = [v[0] for v in META.values()]
t = (R/'snow-rush-pets.html').read_text()
b64 = lambda f: base64.b64encode((R/f).read_bytes()).decode()
data = {p: {'png': 'data:image/png;base64,' + b64(f'pets/{p}.png'), 'glb': b64(f'pets/{p}.glb'),
            **{v: b64(f'pets/{p}_{v}.png') for v in ('textur', 'gold', 'regenbogen', 'frostig')}} for p in PETS}
t = t.replace("const RAR = [", "const INLINE = " + json.dumps(data) + ";\nconst RAR = [", 1)
t = t.replace("'pets/' + m.file + '.png'", "INLINE[m.file].png")
old = "const r = await fetch('pets/' + m.file + '.glb'); if (!r.ok) throw new Error('Modell nicht gefunden'); cache[m.file] = parseGLB(await r.arrayBuffer());"
new = "const s = atob(INLINE[m.file].glb), u = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) u[i] = s.charCodeAt(i); cache[m.file] = parseGLB(u.buffer);"
assert old in t; t = t.replace(old, new)
old2 = "async function texBlob(file, v) { const r = await fetch('pets/' + file + '_' + v + '.png'); if (!r.ok) throw new Error(); return r.blob(); }"
new2 = "async function texBlob(file, v) { const s = atob(INLINE[file][v]), u = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) u[i] = s.charCodeAt(i); return new Blob([u], { type: 'image/png' }); }"
assert old2 in t; t = t.replace(old2, new2)
head = ('<!doctype html><html lang="de"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
        '<style>:root{color-scheme:light}body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style></head><body>')
(R/'snow-rush-pets-datei.html').write_text(head + t + '</body></html>')
print(len(t))
