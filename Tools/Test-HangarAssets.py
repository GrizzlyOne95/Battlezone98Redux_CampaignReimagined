"""Static invariants for the NSDF (abhang) and Black Dog (bbhang) hangar model fixes."""
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / 'Assets' / 'ModelFixes'


def chunks(data, start, end):
    while start < end:
        kind, size = struct.unpack_from('<HI', data, start)
        assert size >= 6 and start + size <= end, 'truncated Ogre chunk'
        yield kind, start + 6, start + size
        start += size
    assert start == end


def skeleton_bones(path):
    data = path.read_bytes()
    head = data.index(b'\n') + 1
    assert data[2:head] == b'[Serializer_v1.80]\n', 'skeleton serializer version'
    bones = {}
    pos = head
    while pos < len(data):
        kind, size = struct.unpack_from('<HI', data, pos)
        s = pos + 6
        if kind == 0x2000:
            # Ogre's skeleton writer leaves the bone name out of the chunk size.
            ne = data.index(b'\n', s)
            name = data[s:ne].decode('ascii')
            handle = struct.unpack_from('<H', data, ne + 1)[0]
            px, py, pz, qx, qy, qz, qw = struct.unpack_from('<7f', data, ne + 3)
            bones[name] = (handle, (px, py, pz), (qw, qx, qy, qz))
            size += ne + 1 - s
        assert size >= 6
        pos += size
    assert pos == len(data)
    assert sorted(h for h, _, _ in bones.values()) == list(range(len(bones))), 'contiguous bone handles'
    return bones


def mesh_info(path):
    data = path.read_bytes()
    head = data.index(b'\n') + 1
    assert data[2:head] == b'[MeshSerializer_v1.100]\n'
    kind, start, end = next(chunks(data, head, len(data)))
    assert kind == 0x3000
    info = {'bones': [], 'skeleton': None, 'material': None, 'vertices': 0}
    for kind, ss, se in chunks(data, start + 1, end):
        if kind == 0x6000:
            info['skeleton'] = data[ss:data.index(b'\n', ss)].decode('ascii')
        if kind != 0x4000:
            continue
        ne = data.index(b'\n', ss)
        info['material'] = data[ss:ne].decode('ascii')
        _, count, wide = struct.unpack_from('<?I?', data, ne + 1)
        pos = ne + 7 + count * (4 if wide else 2)
        for k, gs, ge in chunks(data, pos, se):
            if k == 0x5000:
                info['vertices'] = struct.unpack_from('<I', data, gs)[0]
            if k == 0x4100:
                vertex, bone, weight = struct.unpack_from('<IHf', data, gs)
                assert vertex < info['vertices'] and weight > 0
                info['bones'].append(bone)
    return info


def sdf_anim(path):
    data = path.read_bytes()
    geocount = struct.unpack_from('<4sIi', data, 20 + 78)[2]
    a = 20 + 78 + 12 + 6 * geocount * 120
    hdr = struct.unpack_from('=4si16s5ii6i', data, a)
    assert hdr[0] == b'ANIM'
    n_el, n_or, n_rot, n_t2, n_pos = hdr[3:8]
    assert hdr[1] == 72 + n_el * 148 + n_or * 132 + n_rot * 20 + n_t2 * 16 + n_pos * 16, 'ANIM section length'
    o = a + 72
    elements = [struct.unpack_from('=i32iiiif', data, o + i * 148) for i in range(n_el)]
    o += n_el * 148
    ors = {}
    for i in range(n_or):
        r = struct.unpack_from('=8si12f12f6i', data, o + i * 132)
        ors[r[0].rstrip(b'\0').decode('ascii')] = r
    o += n_or * 132
    rots = [struct.unpack_from('=i4f', data, o + i * 20) for i in range(n_rot)]
    o += n_rot * 20 + n_t2 * 16
    poss = [struct.unpack_from('=i3f', data, o + i * 16) for i in range(n_pos)]
    return elements, ors, rots, poss


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def yaw(q):
    return math.degrees(2 * math.atan2(q[2], q[0]))


abh = skeleton_bones(FIX / 'abhang.skeleton')
bbh = skeleton_bones(FIX / 'bbhang.skeleton')
DOORS = ['dra', 'drb', 'drc', 'drd']
assert set(abh) == {'abh11bbb'} | {'abh11' + d for d in DOORS}
assert set(bbh) == {'bbh11bbb'} | {'bbh11' + d for d in DOORS}

elements, ors, rots, poss = sdf_anim(FIX / 'abhang.sdf')
assert elements[0][33:36] == (0, 121, 1) or elements[0][33] == 0
frames = 121
for d in DOORS:
    name = 'abh11' + d
    r = ors[name]
    keys = rots[r[26]:r[26] + r[27]]
    assert [k[0] for k in keys] == list(range(frames)), name + ': a rotation key on every frame'
    qs = [k[1:] for k in keys]
    assert all(abs(dot(q, q) - 1) < 1e-4 for q in qs), name + ': unit quaternions'
    assert all(dot(a, b) > 0.99 for a, b in zip(qs, qs[1:])), name + ': shortest-path, no sign flips'
    total = abs(math.degrees(2 * math.acos(max(-1, min(1, abs(dot(qs[0], qs[-1])))))))
    assert 100 < total < 180, name + ': swing %.1f deg is the short way round' % total
    # frame 0 is the closed bind pose: skeleton bone orientation (mirror-free about Y) and position.
    handle, bpos, bq = abh[name]
    assert abs(abs(dot(qs[0], bq)) - 1) < 1e-4, name + ': frame 0 rotation = bind'
    pk = poss[r[30]:r[30] + r[31]]
    assert pk, name + ': position key'
    for k in pk:
        assert abs(-k[1] - bpos[0]) < 1e-3 and abs(k[2] - bpos[1]) < 1e-3 and abs(k[3] - bpos[2]) < 1e-3, \
            name + ': SDF position key agrees with the skeleton bind (hinge)'
    # eased: speed at both ends is below the middle's
    steps = [abs(yaw(qs[i + 1]) - yaw(qs[i])) for i in range(frames - 1)]
    assert steps[0] < steps[60] and steps[-1] < steps[60], name + ': ease in/out'

for skel, mesh, material, link in [(abh, 'abhang.mesh', 'abhang00', 'abhang.skeleton'),
                                   (bbh, 'bbhang.mesh', 'bbhang', 'bbhang.skeleton')]:
    info = mesh_info(FIX / mesh)
    assert info['skeleton'] == link and info['material'] == material, mesh
    assert info['bones'] and max(info['bones']) < len(skel), mesh + ': bone indices in range of its skeleton'
    assert set(range(1, 5)) <= set(info['bones']), mesh + ': all four door bones carry vertices'
a_info, b_info = mesh_info(FIX / 'abhang.mesh'), mesh_info(FIX / 'bbhang.mesh')
assert a_info['vertices'] == b_info['vertices'] and a_info['bones'] == b_info['bones'], 'same closed geometry and weights'

# Black Dog doors stay closed: no SDF override, and no bbhang bone is named like a stock SDF GEO.
assert not (FIX / 'bbhang.sdf').exists(), 'stock bbhang.sdf (abh11* GEOs) is used'
assert not set(bbh) & set(ors), 'no bbhang bone matches an animated GEO name'

lock = json.loads((ROOT / 'Shipping' / 'shipping.lock.json').read_text())
shipped = {e['runtime'] for e in lock['files']} if isinstance(lock, dict) and 'files' in lock else set()
for f in ('abhang.mesh', 'abhang.sdf', 'abhang.skeleton', 'bbhang.mesh', 'bbhang.skeleton'):
    assert f in shipped, f + ' is in the shipping lock'
for f in ('bbhang.sdf', 'avwalk.mesh', 'avwalk.skeleton'):
    assert f not in shipped, f + ' is not shipped'
print('hangar assets: per-frame shortest-path door keys, bind = closed, hinge agreement, '
      'bbhang mesh/skeleton bone indices and closed-door contract passed')
