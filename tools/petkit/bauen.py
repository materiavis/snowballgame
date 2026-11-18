"""python3 bauen.py name [voxel]: baut ein Pet nach build/name.glb"""
import sys, time, importlib, json, glob, os, traceback
import pathlib as _pl; ROOT = _pl.Path(__file__).resolve().parent; sys.path.insert(0, str(ROOT))
name = sys.argv[1]; vox = float(sys.argv[2]) if len(sys.argv) > 2 else .022
PETS = {}
for f in sorted(glob.glob(str(ROOT / 'katalog_*.py'))):
    PETS.update(importlib.import_module(os.path.basename(f)[:-3]).PETS)
(ROOT / 'build').mkdir(exist_ok=True)
t = time.time()
try:
    info = PETS[name]().build(str(ROOT / 'build' / f'{name}.glb'), vox)
    print(json.dumps({'pet': name, **info, 's': round(time.time() - t)}))
except Exception as e:
    print(json.dumps({'pet': name, 'error': repr(e)[:200]})); traceback.print_exc()
