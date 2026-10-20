"""Validate the NSDF Eagle's Nest rocket: static mesh, material, textures, ODF, layout and BZN placement."""
from pathlib import Path
import hashlib
import io
import json
import math
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from bzmodellibs import bwd2_serializer, geo_serializer, ogremesh_serializer

NAME = 'cr03rok'
build = json.loads((ROOT / 'References/Misn03Rocket/build.json').read_text())

# --- Committed outputs are exactly what the deterministic build recorded.
for relative, digest in build['sha256'].items():
    assert hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == digest, relative + ' differs from build.json'

# --- Static Ogre mesh.
mesh = ogremesh_serializer.MeshSerializer(io.BytesIO((ROOT / f'Assets/ModelFixes/{NAME}.mesh').read_bytes())).read()
assert mesh.skeleton_name is None, 'static Ogre mesh: no skeleton link'
assert len(mesh.submesh_list) == 1, 'only the rocket submesh; the pad is dropped'
sub = mesh.submesh_list[0]
assert sub.material_name == 'cr03rok00', 'namespaced material, clear of the Resurgence abtrans_BZBase_abtrans'
assert not sub.use_shared_vertices and sub.index_count == 2750 * 3
indices = sub.get_index_array().tolist()
buffer = sub.vertex_data.get_vertex_buffer(0)
assert buffer.bind_index == 0 and buffer.vertex_size == 32
assert buffer.buffer.nbytes == sub.vertex_data.vertex_count * 32
vertices = list(struct.iter_unpack('<8f', bytes(buffer.buffer)))
assert max(indices) < len(vertices) and all(math.isfinite(x) for v in vertices for x in v)
assert all(abs(sum(x * x for x in v[3:6]) - 1) < .005 for v in vertices), 'unit normals'
xs, ys, zs = [[v[i] for v in vertices] for i in range(3)]
half_height = (max(ys) - min(ys)) / 2
assert abs(max(ys) + min(ys)) < 1e-3, 'cr06rok origin convention: Y is the mid-height'
assert abs(half_height - 46.0047) < .001, 'rocket height is the source rocket, unscaled'
assert abs(min(xs) + max(xs)) < .01 and abs(min(zs) + max(zs)) < .01, 'X/Z are centred on the rocket axis'
assert 14.3 < max(xs) < 14.7 and 17.0 < max(zs) < 18.5, 'flared skirt about 14.5 m wide, 17.7 m across the dorsal housing'
aligned = degenerate = 0
for i in range(0, len(indices), 3):
    a, b, c = [vertices[indices[i + j]] for j in range(3)]
    u = [b[j] - a[j] for j in range(3)]
    v = [c[j] - a[j] for j in range(3)]
    n = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
    if sum(x * x for x in n) < 1e-12:
        degenerate += 1
        continue
    mean = [a[3 + j] + b[3 + j] + c[3 + j] for j in range(3)]
    aligned += sum(x * y for x, y in zip(n, mean)) > 0
assert aligned >= .995 * (len(indices) / 3 - degenerate), 'normals agree with triangle winding'

# --- Native fallback geometry and SDF.
geo = geo_serializer.GeoSerializer(io.BytesIO((ROOT / f'Assets/ModelFixes/{NAME}.geo').read_bytes())).read()
assert geo.name == NAME and geo.vert_count < 4096 and len(geo.face_list) == 2750
sdf = bwd2_serializer.SDFSerializer(io.BytesIO((ROOT / f'Assets/ModelFixes/{NAME}.sdf').read_bytes())).read()
obj = sdf.get_object(0, 0, 0)
assert obj.name == NAME and obj.parent == 'WORLD'
assert abs(obj.half_size.y - half_height) < .01 and 14.3 < obj.half_size.x < 14.7 and 17.0 < obj.half_size.z < 18.5

# --- Textures: 1024 squared, uncompressed RGBA8 (BC3 failed in the native DX11 colour path).
for suffix in 'dnse':
    dds = (ROOT / f'Assets/Textures/{NAME}_{suffix}.dds').read_bytes()
    assert dds[:4] == b'DDS ' and struct.unpack_from('<II', dds, 12) == (1024, 1024)
    assert struct.unpack_from('<I', dds, 80)[0] == 0x41 and struct.unpack_from('<I', dds, 88)[0] == 32, 'RGBA8 texture'
    assert struct.unpack_from('<3I', dds, 92) == (0xff0000, 0xff00, 0xff), 'BGRA8 masks'
    assert len(dds) == 128 + 4 * 1024 * 1024

# --- Material and ODF.
material = (ROOT / f'Materials/{NAME}.material').read_text()
assert re.search(r'^material cr03rok00 : BZBase$', material, re.M)
for slot, suffix in (('DiffuseMap', 'd'), ('NormalMap', 'n'), ('SpecularMap', 's'), ('EmissiveMap', 'e')):
    assert f'set_texture_alias {slot} {NAME}_{suffix}.dds' in material
assert 'abtrans' not in material
odf = (ROOT / f'ODF/{NAME}.odf').read_text()
assert 'classLabel = "i76building"' in odf and 'maxHealth = 0' in odf and 'baseName = "cr03rok"' in odf

# --- Launch layout: centre bell plus six on a 9 m ring on the skirt lobes, from the nozzle plane.
layout = (ROOT / 'Scripts/CR03RocketLayout.lua').read_text()
nozzle_y = float(re.search(r'nozzleY = (-?[\d.]+)', layout)[1])
assert abs(nozzle_y + half_height) < .001, 'nozzles at the mesh nozzle plane'
jets = [tuple(map(float, m)) for m in re.findall(r'\{(-?[\d.]+),\s*(-?[\d.]+)\}', layout)]
assert len(jets) == 7 and len(set(jets)) == 7 and jets[0] == (0.0, 0.0)
assert all(abs(math.hypot(x, z) - 9) < 1e-6 for x, z in jets[1:])
assert sorted(round(math.degrees(math.atan2(z, x)) % 360) % 360 for x, z in jets[1:]) == [0, 60, 120, 180, 240, 300]

# --- Particles are Mission 06's shipped templates; nothing new for the Moon.
template = (ROOT / 'Materials/cr06_launch.particle.payload').read_text()
for kind in ('Core', 'Plume', 'Dust'):
    assert f'particle_system CR/M06/{kind}' in template
assert not list((ROOT / 'Materials').glob('cr03*payload'))

# --- BZN fixture, placed from the launch_pad basis.
raw = (ROOT / 'Missions/misn03.bzn').read_bytes()
assert b'\r\n' in raw
text = raw.decode('latin1').replace('\r\n', '\n')
blocks = text.split('[GameObject]\n')


def find(label):
    found = [b for b in blocks[1:] if f'label = {label}\n' in b]
    assert len(found) == 1, label
    return found[0]


def num(block, key):
    return float(re.search(r'^\s*' + key + r' \[1\] =\n([^\n]+)', block, re.M)[1])


def field(block, key):
    return re.search(r'^' + key + r' \[1\] =\n([^\n]+)', block, re.M)[1]


pad, rocket = find('launch_pad'), find('cr03_rocket')
assert field(pad, 'PrjID') == 'ablpad' and field(rocket, 'PrjID') == NAME
assert field(rocket, 'team') == '0' and field(rocket, 'perceivedTeam') == '0'
assert field(rocket, 'maxHealth') == '0' and field(rocket, 'curHealth') == '0'
assert field(pad, 'team') == '1' and field(pad, 'maxHealth') == '7000', 'the real pad is untouched'
addresses = re.findall(r'^obj_addr = (\w+)', text, re.M)
seqnos = re.findall(r'^seqno \[1\] =\n(\d+)', text, re.M)
assert len(addresses) == len(set(addresses)) == len(seqnos) == len(set(seqnos)) == len(blocks) - 1
assert int(re.search(r'^size \[1\] =\n(\d+)', blocks[0], re.M)[1]) == len(blocks) - 1
assert int(re.search(r'^seq_count \[1\] =\n(\d+)', blocks[0], re.M)[1]) > max(map(int, seqnos))
# The pad basis carries the rocket axis: 24.745 along right and 23.415 along front in native local
# terms (the Ogre mesh X is mirrored, so the stock-frame -24.745 becomes +24.745), at the rocket's
# mid-height. The heading is the pad's turned 180 degrees about up (right and front negated).
axes = {k: [num(pad, f'{k}_{a}') for a in 'xyz'] for k in ('right', 'up', 'front')}
origin = [num(pad, f'posit_{a}') for a in 'xyz']
offset = {'right': 24.745, 'up': build['mid_height_in_abtrans_frame'], 'front': 23.415}
expected = [origin[i] + sum(axes[k][i] * offset[k] for k in offset) for i in range(3)]
posit = [num(rocket, f'posit_{a}') for a in 'xyz']
assert all(abs(p - e) < .01 for p, e in zip(posit, expected)), (posit, expected)
vectors = re.findall(r'^pos \[1\] =\n  x \[1\] =\n([^\n]+)\n  y \[1\] =\n([^\n]+)\n  z \[1\] =\n([^\n]+)', rocket, re.M)
assert len(vectors) == 2 and all(all(abs(float(v) - p) < .01 for v, p in zip(vec, posit)) for vec in vectors)
for k, sign in (('right', -1), ('up', 1), ('front', -1)):
    for i, a in enumerate('xyz'):
        assert abs(num(rocket, f'{k}_{a}') - sign * axes[k][i]) < 1e-5, 'heading is the pad turned 180 degrees'
assert abs((posit[1] + nozzle_y) - (origin[1] + 20.2515)) < .01, 'nozzle plane 20.25 above the pad origin'
for key in ('v', 'omega', 'Accel'):
    assert re.search(r'^ ' + key + r' \[1\] =\n  x \[1\] =\n0\n  y \[1\] =\n0\n  z \[1\] =\n0\n', rocket, re.M)

print('Misn03 NSDF rocket: static mesh, RGBA8 textures, 7-bell layout and pad-relative BZN fixture passed')
