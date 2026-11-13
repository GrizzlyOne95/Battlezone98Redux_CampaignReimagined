"""Checks the crord* ordnance kit: tris, material, length vs stock, closed parts, sunk fins, ODF links."""
from pathlib import Path
import io, json, re, sys
import numpy as np
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Tools'))
from bzmodellibs import require_or_skip
from bcdds import bc_dds_problem

STOCK = {k: v for k, v in json.loads((ROOT / 'Tools/Weapons/OrdnanceStockDims.json').read_text()).items() if not k.startswith('_')}


def load(path):
    from bzmodellibs import ogremesh_serializer as oms
    mesh = oms.MeshSerializer(io.BytesIO(path.read_bytes())).read()
    assert len(mesh.submesh_list) == 1, (path.name, 'one submesh')
    sub = mesh.submesh_list[0]
    vd = sub.vertex_data
    raw = np.frombuffer(vd.get_vertex_buffer(0).get_buffer(), dtype='<f4').reshape(vd.vertex_count, -1)
    idx = np.frombuffer(sub.get_index_buffer(), dtype='<u4' if sub.indices_32_bit else '<u2').reshape(-1, 3)
    return sub.material_name, raw, idx


def components(pos, idx):
    """Position-welded triangle table and the triangle groups connected through shared vertices."""
    key = {}
    weld = np.array([key.setdefault(tuple(np.round(p, 5)), len(key)) for p in pos])
    tri = weld[idx]
    parent = list(range(len(key)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for t in tri:
        parent[find(t[1])] = find(t[0])
        parent[find(t[2])] = find(t[0])
    groups = {}
    for i, t in enumerate(tri):
        groups.setdefault(find(t[0]), []).append(i)
    return tri, [np.array(g) for g in groups.values()]


def closed_problem(tri):
    """Every directed edge used exactly once and its reverse present: closed and consistently wound."""
    edges = {}
    for t in tri:
        for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            edges[(a, b)] = edges.get((a, b), 0) + 1
    for (a, b), n in edges.items():
        if n != 1 or edges.get((b, a)) != 1:
            return f'edge {a}->{b} used {n}x, reverse {edges.get((b, a))}'
    return None


def volume(t):
    return float(np.einsum('ij,ij->i', t[:, 0], np.cross(t[:, 1], t[:, 2])).sum() / 6)


def inside(point, tris):
    """Ray-parity point-in-closed-mesh along an off-axis direction."""
    d = np.array([0.5773, 0.3711, 0.7311])
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    e1, e2 = b - a, c - a
    h = np.cross(d, e2)
    det = np.einsum('ij,ij->i', e1, h)
    ok = np.abs(det) > 1e-12
    f = np.where(ok, 1 / np.where(ok, det, 1), 0)
    s = point - a
    u = f * np.einsum('ij,ij->i', s, h)
    q = np.cross(s, e1)
    v = f * (q @ d)
    t = f * np.einsum('ij,ij->i', e2, q)
    return int(np.sum(ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-9))) % 2 == 1


def tri_distance(point, tris):
    """Distance from point to the nearest triangle (Ericson closest-point, per triangle)."""
    best = 1e9
    for a, b, c in tris:
        ab, ac, ap = b - a, c - a, point - a
        d1, d2 = ab @ ap, ac @ ap
        bp = point - b
        d3, d4 = ab @ bp, ac @ bp
        cp = point - c
        d5, d6 = ab @ cp, ac @ cp
        if d1 <= 0 and d2 <= 0:
            q = a
        elif d3 >= 0 and d4 <= d3:
            q = b
        elif d6 >= 0 and d5 <= d6:
            q = c
        else:
            vc = d1 * d4 - d3 * d2
            vb = d5 * d2 - d1 * d6
            va = d3 * d6 - d5 * d4
            if vc <= 0 and d1 >= 0 and d3 <= 0:
                q = a + ab * (d1 / (d1 - d3))
            elif vb <= 0 and d2 >= 0 and d6 <= 0:
                q = a + ac * (d2 / (d2 - d6))
            elif va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0:
                q = b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
            else:
                denom = 1 / (va + vb + vc)
                q = a + ab * (vb * denom) + ac * (vc * denom)
        best = min(best, float(np.linalg.norm(point - q)))
    return best


def check_mesh(name, info):
    material, raw, idx = load(ROOT / 'Assets/ModelFixes' / (name + '.mesh'))
    pos = raw[:, :3].astype(float)
    n = len(idx)
    assert 0 < n <= 400, (name, 'triangles', n)
    assert material == 'crord', (name, material)
    ext = pos.max(0) - pos.min(0)
    length, stock = ext[2], info['stockLength']
    assert 0.75 * stock <= length <= 1.25 * stock, (name, 'length', length, 'stock', stock)
    if not info.get('flat'):  # a flat puck (stock gtagg00) is wider than it is long
        assert ext[2] >= ext[0] and ext[2] >= ext[1], (name, 'long axis must be Z')
    assert abs(pos[:, 2].max() + pos[:, 2].min()) < 1e-3, (name, 'centred on the origin like stock')
    uv = raw[:, 6:8]
    assert uv.min() >= 0 and uv.max() <= 1, (name, 'uv inside the atlas')
    tri, groups = components(pos, idx)
    problem = closed_problem(tri)
    assert problem is None, (name, problem)
    for g in groups:
        assert volume(pos[idx[g]]) > 0, (name, 'inside-out part')
    hull = max(groups, key=len)
    hull_tris = pos[idx[hull]]
    fins = 0
    for g in groups:
        if g is hull:
            continue
        verts = np.unique(np.round(pos[idx[g]].reshape(-1, 3), 6), axis=0)
        centred = verts - verts.mean(0)
        proj = centred @ np.linalg.svd(centred)[2].T
        thickness = float((proj.max(0) - proj.min(0)).min())
        buried = [v for v in verts if inside(v, hull_tris)]
        assert 4 <= len(buried) < len(verts), (name, 'fin root not sunk', len(buried), len(verts))
        depth = min(tri_distance(v, hull_tris) for v in buried)
        assert depth >= 0.2 * thickness, (name, 'fin sunk', depth, 'thickness', thickness)
        fins += 1
    return n, length, fins


def main():
    if not require_or_skip('Test-OrdnanceModels'):
        return
    assert len(STOCK) == 12
    from bzmodellibs import geo_serializer
    for name in sorted(STOCK):
        n, length, fins = check_mesh(name, STOCK[name])
        # ODFs name the .mesh directly (a .geo name resolves to the stock round); the .geo twin stays for log hygiene.
        g = geo_serializer.GeoSerializer(io.BytesIO((ROOT / 'Assets/ModelFixes' / (name + '.geo')).read_bytes())).read()
        assert g.vert_count > 0 and len(g.face_list) == n, (name, 'geo twin', g.vert_count, len(g.face_list))
        print(f"{name}: {n} tris, length {length:.3f} vs stock {STOCK[name]['stockLength']:.3f}, {fins} fins sunk, closed")
    for name, info in STOCK.items():
        for odf in info['odfs']:
            path = ROOT / 'ODF' / (odf + '.odf')
            assert path.is_file(), (odf, 'mapped ODF missing')
            m = re.search(r'^shotGeometry\s*=\s*"([^"]+)"', path.read_text(errors='replace'), re.M)
            assert m and m.group(1) == name + '.mesh', (odf, 'shotGeometry', m and m.group(1))
    for tex in ('crord_d.dds', 'crord_e.dds'):
        assert bc_dds_problem((ROOT / 'Assets/Textures' / tex).read_bytes(), 512, 512) is None, tex
    mat = (ROOT / 'Materials/CR_Ordnance.material').read_text()
    assert re.search(r'^material crord : CR_BZBase', mat, re.M) and 'crord_d.dds' in mat and 'crord_e.dds' in mat
    print('Ordnance models: all checks passed.')


if __name__ == '__main__':
    main()
