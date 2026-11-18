"""python3 bauen2.py slug: baut Version 2 nach build2/slug.glb"""
import sys, time, json, traceback
import pathlib as _pl; ROOT = _pl.Path(__file__).resolve().parent; sys.path.insert(0, str(ROOT))
from wow import build_pet
(ROOT / 'build2').mkdir(exist_ok=True)
name = sys.argv[1]; t = time.time()
try:
    info = build_pet(name).build(str(ROOT / 'build2' / f'{name}.glb'), .022)
    print(json.dumps({'pet': name, **info, 's': round(time.time() - t)}))
except Exception as e:
    print(json.dumps({'pet': name, 'error': repr(e)[:300]})); traceback.print_exc()
