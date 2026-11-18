"""petkit – baut Snow-Rush-Pets als echte Meshes aus Formfeldern (SDF).

Ablauf: Formfeld -> feines Mesh (Marching Cubes) -> Reduktion auf Dreiecks-Budget
(Farbgrenzen bleiben erhalten) -> Baked-Schatten -> .glb mit kleiner Paletten-Textur.
Nur numpy, scipy und scikit-image noetig. 1 Einheit = 1 Stud, Vorderseite = +Z, Y oben.
"""
import heapq, json, struct, zlib
import numpy as np
from skimage import measure

# ---------- Formen ----------
def length(v): return np.sqrt((v * v).sum(-1))
def norm(v):
    v = np.asarray(v, float); return v / np.linalg.norm(v)

def align(n, up=(0, 1, 0)):
    """Drehmatrix, deren dritte Spalte (lokal z) nach n zeigt."""
    z = norm(n); x = np.cross(up, z); x = x / np.linalg.norm(x); y = np.cross(z, x)
    return np.stack([x, y, z], 1)

def ellipsoid(p, c, r, R=None):
    q = p - np.asarray(c, float)
    if R is not None: q = q @ R
    r = np.asarray(r, float)
    k0 = length(q / r); k1 = length(q / (r * r))
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)

def on_ellipsoid(c, r, x, y):
    """Punkt und Normale vorne auf einer Ellipsoide an Stelle x,y (fuer Augen)."""
    r = np.array(r, float); c = np.array(c, float)
    q = np.array([x - c[0], y - c[1], 0.0]) / r
    z = np.sqrt(max(1 - q @ q, 1e-6))
    p = np.array([x, y, c[2] + z * r[2]])
    return p, norm((p - c) / (r * r))

def round_box(p, c, b, r, R=None):
    q = p - np.asarray(c, float)
    if R is not None: q = q @ R
    q = np.abs(q) - (np.asarray(b, float) - r)
    return length(np.maximum(q, 0)) + np.minimum(q.max(-1), 0) - r

def sphere(p, c, r): return length(p - np.asarray(c, float)) - r

def round_cone(p, a, b, r1, r2):
    a = np.asarray(a, float); b = np.asarray(b, float)
    ba = b - a; l2 = ba @ ba; rr = r1 - r2; a2 = l2 - rr * rr; il2 = 1.0 / l2
    pa = p - a; y = pa @ ba; z = y - l2
    t = pa * l2 - y[..., None] * ba
    x2 = (t * t).sum(-1); y2 = y * y * l2; z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    out = (np.sqrt(np.maximum(x2 * a2 * il2, 0)) + y * rr) * il2 - r1
    c1 = np.sign(y) * a2 * y2 < k; out = np.where(c1, np.sqrt(x2 + y2) * il2 - r1, out)
    c2 = np.sign(z) * a2 * z2 > k; out = np.where(c2, np.sqrt(x2 + z2) * il2 - r2, out)
    return out

def chain(p, pts, rad):
    d = None
    for i in range(len(pts) - 1):
        e = round_cone(p, pts[i], pts[i + 1], rad[i], rad[i + 1])
        d = e if d is None else np.minimum(d, e)
    return d

def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)
def smax(a, b, k): return -smin(-a, -b, k)
def ssub(a, b, k): return smax(a, -b, k)   # a minus b

def grad(f, p, e=1e-3):
    g = np.zeros_like(p)
    for i in range(3):
        d = np.zeros(3); d[i] = e
        g[:, i] = f(p + d) - f(p - d)
    return g / (2 * e)

# ---------- Mesh aus Feld ----------
def surface(f, lo, hi, voxel):
    lo = np.asarray(lo, float); hi = np.asarray(hi, float)
    n = np.ceil((hi - lo) / voxel).astype(int) + 1
    ax = [lo[i] + np.arange(n[i]) * voxel for i in range(3)]
    vol = np.empty(tuple(n), np.float32)
    Y, Z = np.meshgrid(ax[1], ax[2], indexing='ij')
    for i, x in enumerate(ax[0]):            # Scheibe fuer Scheibe, spart Speicher
        p = np.stack([np.full(Y.size, x), Y.ravel(), Z.ravel()], 1)
        vol[i] = f(p).reshape(Y.shape)
    V, F, _, _ = measure.marching_cubes(vol, 0.0, spacing=(voxel,) * 3)
    V = V + lo
    # skimage liefert je nach Feld andere Wicklung: nach aussen richten
    a, b, c = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    fn = np.cross(b - a, c - a); m = (a + b + c) / 3
    if (fn * grad(f, m)).sum() < 0: F = F[:, ::-1]
    return V.astype(float), F.astype(int)

# ---------- Reduktion (Quadric Error) mit Farbgrenzen ----------
def _plane_q(n, d, w):
    a, b, c = n[..., 0], n[..., 1], n[..., 2]
    return np.stack([a*a, a*b, a*c, a*d, b*b, b*c, b*d, c*c, c*d, d*d], -1) * w[..., None]

def decimate(V, F, L, target, importance=None, boundary_w=40.0, min_cos=0.25):
    V = V.copy(); nv = len(V)
    a, b, c = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    fn = np.cross(b - a, c - a); ar = np.maximum(length(fn), 1e-12); n = fn / ar[:, None]
    w = ar.copy()
    if importance is not None: w = w * importance((a + b + c) / 3)
    fq = _plane_q(n, -(n * a).sum(-1), w)
    Q = np.zeros((nv, 10))
    for i in range(3): np.add.at(Q, F[:, i], fq)
    # Kanten sammeln
    faces = F.tolist(); labels = list(map(int, L)); alive = [True] * len(faces)
    vf = [set() for _ in range(nv)]
    for i, t in enumerate(faces):
        for x in t: vf[x].add(i)
    edge = {}
    for i, t in enumerate(faces):
        for j in range(3):
            u, v = t[j], t[(j + 1) % 3]
            edge.setdefault((min(u, v), max(u, v)), []).append(i)
    # Grenzkanten: senkrechte Ebene als zusaetzliche Quadrik
    bi = None if importance is None else importance((a + b + c) / 3)
    for (u, v), fs in edge.items():
        if len(fs) == 2 and labels[fs[0]] != labels[fs[1]]:
            e = V[v] - V[u]; l = np.linalg.norm(e)
            for f in fs:
                m = np.cross(e, n[f]); ml = np.linalg.norm(m)
                if ml < 1e-12: continue
                m = m / ml
                bw = boundary_w if bi is None else boundary_w * bi[f]
                q = _plane_q(m, np.array(-(m @ V[u])), np.array(bw * l * l))
                Q[u] += q; Q[v] += q
    Q = Q.tolist(); P = V.tolist(); ver = [0] * nv

    def labs(v): return {labels[f] for f in vf[v]}
    def cost(q, x, y, z):
        return (q[0]*x*x + 2*q[1]*x*y + 2*q[2]*x*z + 2*q[3]*x + q[4]*y*y + 2*q[5]*y*z +
                2*q[6]*y + q[7]*z*z + 2*q[8]*z + q[9])
    def plan(u, v):
        lu, lv = labs(u), labs(v); bu, bv = len(lu) > 1, len(lv) > 1
        pu, pv = P[u], P[v]
        q = [s + t for s, t in zip(Q[u], Q[v])]
        shared = vf[u] & vf[v]
        if bu and bv:
            if len({labels[f] for f in shared}) < 2: return None
            if len(lu) > 2 and len(lv) > 2: return None
            if len(lu) > 2: cands = [pu]
            elif len(lv) > 2: cands = [pv]
            else: cands = [pu, pv]
        elif bu: cands = [pu]
        elif bv: cands = [pv]
        else: cands = [pu, pv, [(s + t) / 2 for s, t in zip(pu, pv)]]
        best, pos = None, None
        for c_ in cands:
            k = cost(q, *c_)
            if best is None or k < best: best, pos = k, c_
        return best, pos
    heap = []
    def push(u, v):
        r = plan(u, v)
        if r is None: return
        heapq.heappush(heap, (r[0], u, v, ver[u], ver[v], r[1]))
    for (u, v) in edge: push(u, v)
    count = len(faces)
    def fnorm(p0, p1, p2):
        ux, uy, uz = p1[0]-p0[0], p1[1]-p0[1], p1[2]-p0[2]
        vx, vy, vz = p2[0]-p0[0], p2[1]-p0[1], p2[2]-p0[2]
        return uy*vz-uz*vy, uz*vx-ux*vz, ux*vy-uy*vx
    def ok(u, v, pos):
        for w_, o in ((u, v), (v, u)):
            for f in vf[w_]:
                t = faces[f]
                if o in t: continue
                old = fnorm(P[t[0]], P[t[1]], P[t[2]])
                pts = [pos if x == w_ else P[x] for x in t]
                new = fnorm(*pts)
                lo, ln = sum(x*x for x in old), sum(x*x for x in new)
                if ln < 1e-14: return False
                d = sum(x*y for x, y in zip(old, new))
                if d <= 0 or d * d < min_cos * min_cos * lo * ln: return False
        return True
    while count > target and heap:
        k, u, v, vu, vv, pos = heapq.heappop(heap)
        if ver[u] != vu or ver[v] != vv or not vf[u] or not vf[v]: continue
        shared = vf[u] & vf[v]
        if len(shared) != 2: continue
        nu = {x for f in vf[u] for x in faces[f]} - {u}
        nvv = {x for f in vf[v] for x in faces[f]} - {v}
        if len(nu & nvv) != 2: continue
        r = plan(u, v)
        if r is None: continue
        pos = r[1]
        if not ok(u, v, pos): continue
        for f in shared:
            alive[f] = False
            for x in faces[f]: vf[x].discard(f)
            count -= 1
        for f in list(vf[v]):
            t = faces[f]; t[t.index(v)] = u; vf[u].add(f)
        vf[v] = set(); P[u] = list(pos)
        Q[u] = [s + t for s, t in zip(Q[u], Q[v])]
        ver[u] += 1; ver[v] += 1
        for x in {x for f in vf[u] for x in faces[f]} - {u}:
            ver[x] += 0
            push(min(u, x), max(u, x))
    keep = [i for i, a_ in enumerate(alive) if a_]
    Fo = np.array([faces[i] for i in keep]); Lo = np.array([labels[i] for i in keep])
    used, inv = np.unique(Fo, return_inverse=True)
    return np.array(P)[used], inv.reshape(-1, 3), Lo

# ---------- Palette ----------
SW = 12          # Breite je Farbe in Pixeln (10 Farben pro Textur)
TEX = 128        # Texturgroesse

def srgb(h):
    h = h.lstrip('#'); return np.array([int(h[i:i+2], 16) for i in (0, 2, 4)], float)

def palette_png(ramps):
    """ramps: Liste (Schattenfarbe, Grundfarbe). Spalte = Farbe, Zeile = Schatten bis Licht."""
    img = np.zeros((TEX, TEX, 3), np.uint8) + 255
    for i, (lo, hi) in enumerate(ramps):
        lo, hi = srgb(lo), srgb(hi)
        for y in range(TEX):
            t = y / (TEX - 1)
            img[y, i * SW:(i + 1) * SW] = np.round(lo * (1 - t) + hi * t)
    raw = b''.join(b'\0' + img[y].tobytes() for y in range(TEX))
    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', TEX, TEX, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

def uv_for(mat, ao):
    return np.stack([np.full(len(ao), (mat + 0.5) * SW / TEX), 0.01 + 0.98 * np.clip(ao, 0, 1)], 1)

# ---------- GLB ----------
def write_glb(path, name, pos, nrm, uv, idx, png):
    pos = pos.astype('<f4'); nrm = nrm.astype('<f4'); uv = uv.astype('<f4')
    assert len(pos) < 65535
    idx = idx.astype('<u2').ravel()
    blobs = [idx.tobytes(), pos.tobytes(), nrm.tobytes(), uv.tobytes(), png]
    bin_, views, off = b'', [], 0
    targets = [34963, 34962, 34962, 34962, None]
    for b, t in zip(blobs, targets):
        pad = (-len(bin_)) % 4; bin_ += b'\0' * pad
        v = {'buffer': 0, 'byteOffset': len(bin_), 'byteLength': len(b)}
        if t: v['target'] = t
        views.append(v); bin_ += b
    bin_ += b'\0' * ((-len(bin_)) % 4)
    j = {
      'asset': {'version': '2.0', 'generator': 'Materiavis petkit'},
      'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'mesh': 0, 'name': name}],
      'meshes': [{'name': name, 'primitives': [{'attributes': {'POSITION': 1, 'NORMAL': 2, 'TEXCOORD_0': 3},
                                               'indices': 0, 'material': 0, 'mode': 4}]}],
      'materials': [{'name': name + '_Mat', 'doubleSided': False,
                     'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0.0, 'roughnessFactor': 0.75}}],
      'textures': [{'source': 0, 'sampler': 0}],
      'samplers': [{'magFilter': 9729, 'minFilter': 9729, 'wrapS': 33071, 'wrapT': 33071}],
      'images': [{'bufferView': 4, 'mimeType': 'image/png', 'name': name + '_Palette'}],
      'accessors': [
        {'bufferView': 0, 'componentType': 5123, 'count': int(idx.size), 'type': 'SCALAR'},
        {'bufferView': 1, 'componentType': 5126, 'count': len(pos), 'type': 'VEC3',
         'min': [float(x) for x in pos.min(0)], 'max': [float(x) for x in pos.max(0)]},
        {'bufferView': 2, 'componentType': 5126, 'count': len(nrm), 'type': 'VEC3'},
        {'bufferView': 3, 'componentType': 5126, 'count': len(uv), 'type': 'VEC2'},
      ],
      'bufferViews': views, 'buffers': [{'byteLength': len(bin_)}],
    }
    js = json.dumps(j, separators=(',', ':')).encode()
    js += b' ' * ((-len(js)) % 4)
    total = 12 + 8 + len(js) + 8 + len(bin_)
    with open(path, 'wb') as fh:
        fh.write(struct.pack('<III', 0x46546C67, 2, total))
        fh.write(struct.pack('<II', len(js), 0x4E4F534A)); fh.write(js)
        fh.write(struct.pack('<II', len(bin_), 0x004E4942)); fh.write(bin_)

# ---------- Farbgrenzen glätten ----------
def smooth_boundaries(V, F, L, field, iters=14):
    """Macht die Treppen an Farbgrenzen weg: Grenzlinien werden entlang der Linie geglättet,
    die übrigen Punkte entspannt, alles bleibt auf der Oberfläche."""
    from scipy import sparse
    n = len(V)
    e = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    fid = np.tile(np.arange(len(F)), 3)
    lo = e.min(1); hi = e.max(1); key = lo * n + hi
    order = np.argsort(key); key_s = key[order]
    same = key_s[:-1] == key_s[1:]
    i0 = order[:-1][same]; i1 = order[1:][same]
    border = L[fid[i0]] != L[fid[i1]]
    be = e[i0[border]]
    A = sparse.coo_matrix((np.ones(2 * len(be)), (np.r_[be[:, 0], be[:, 1]], np.r_[be[:, 1], be[:, 0]])), shape=(n, n)).tocsr()
    deg = np.asarray(A.sum(1)).ravel()
    line = deg == 2                       # normale Grenzpunkte
    fixed = deg > 2                       # Dreier-Ecken bleiben stehen
    Aall = sparse.coo_matrix((np.ones(2 * len(e)), (np.r_[lo, hi], np.r_[hi, lo])), shape=(n, n)).tocsr()
    Aall.data[:] = 1
    dall = np.asarray(Aall.sum(1)).ravel()
    V = V.copy()
    for _ in range(iters):
        mean_all = (Aall @ V) / dall[:, None]
        mean_line = (A @ V) / np.maximum(deg, 1)[:, None]
        W = V + 0.5 * (mean_all - V)
        W[line] = V[line] + 0.6 * (mean_line[line] - V[line])
        W[fixed] = V[fixed]
        g = grad(field, W); g2 = np.maximum((g * g).sum(-1), 1e-9)
        V = W - (field(W) / g2)[:, None] * g
    return V

# ---------- Pet zusammenbauen ----------
def ribbon(field, pts, width, lift=0.006):
    """Duenner Streifen auf der Oberflaeche (Mund). pts werden auf das Feld projiziert."""
    p = np.asarray(pts, float)
    for _ in range(4):
        g = grad(field, p); p = p - (field(p) / (g * g).sum(-1))[:, None] * g
    n = grad(field, p); n /= length(n)[:, None]
    t = np.gradient(p, axis=0); s = np.cross(n, t); s /= length(s)[:, None]
    wv = (width * np.sin(np.linspace(0.25, 1 - 0.25, len(p)) * np.pi))[:, None]
    q = p + n * lift
    V = np.concatenate([q - s * wv * .5, q + s * wv * .5]); N = np.concatenate([n, n])
    m = len(p); F = []
    for i in range(m - 1):
        F += [[i, i + 1, m + i], [i + 1, m + i + 1, m + i]]
    return V, N, np.array(F)

def bake(fields, sdf_all, label_fn, normal_of, lo, hi, voxel, target, ramps, importance=None,
         ribbons=(), ao_field=None, name='Pet', out=None, ao_strength=1.0, verbose=True, boundary_w=12.0, scale=1.0):
    """fields wird nur fuer Doku gebraucht; sdf_all = Gesamtform; normal_of(label) = Feld fuer Normalen."""
    V, F = surface(sdf_all, lo, hi, voxel)
    a, b, c = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    L = label_fn((a + b + c) / 3)
    if verbose: print('fein:', len(F), 'Dreiecke')
    V = smooth_boundaries(V, F, L, sdf_all)
    V2, F2, L2 = decimate(V, F, L, target, importance, boundary_w=boundary_w)
    if verbose: print('reduziert:', len(F2))
    for _ in range(2):                                     # zurueck auf die echte Form
        g = grad(sdf_all, V2); g2 = np.maximum((g * g).sum(-1), 1e-9)
        V2 = V2 - (sdf_all(V2) / g2)[:, None] * g
    ao_f = ao_field or (lambda p: np.minimum(sdf_all(p), p[:, 1]))
    P, N, U, I = [], [], [], []
    base = 0
    for lab in np.unique(L2):
        fs = F2[L2 == lab]
        used, inv = np.unique(fs, return_inverse=True)
        p = V2[used]; f = normal_of(int(lab))
        n = grad(f, p); n /= np.maximum(length(n), 1e-9)[:, None]
        occ = np.zeros(len(p))
        for h, w in ((.03, .5), (.07, .3), (.15, .2), (.3, .12), (.5, .06)):
            occ += w * np.clip((h - ao_f(p + n * h)) / h, 0, 1)
        ao = np.clip(1 - occ * ao_strength, 0, 1)
        P.append(p); N.append(n); U.append(uv_for(int(lab), ao)); I.append(inv.reshape(-1, 3) + base)
        base += len(p)
    for fld, pts, width, mat in ribbons:
        rv, rn, rf = ribbon(fld, pts, width)
        P.append(rv); N.append(rn); U.append(uv_for(mat, np.ones(len(rv)))); I.append(rf + base)
        base += len(rv)
    P = np.concatenate(P); N = np.concatenate(N); U = np.concatenate(U); I = np.concatenate(I)
    # Mitte auf den Boden stellen
    bb0, bb1 = P.min(0), P.max(0)
    P = P - np.array([(bb0[0] + bb1[0]) / 2, bb0[1], (bb0[2] + bb1[2]) / 2])
    P = P * scale
    png = palette_png(ramps)
    write_glb(out, name, P, N, U, I, png)
    info = dict(tris=int(len(I)), verts=int(len(P)), size=[round(float(x), 2) for x in (bb1 - bb0) * scale])
    if verbose: print(info)
    return info
