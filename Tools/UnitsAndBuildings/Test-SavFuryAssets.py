"""Guard the infected Fury-blue SAV (savfury): namespaced native copy, unchanged geometry, textures, ODF, shipping."""
from pathlib import Path
from hashlib import sha256
import io, json, re, sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bzmodellibs import bwd2_serializer, geo_serializer, ogremesh_serializer, ogreskeleton_serializer
from bcdds import bc_dds_problem

ROOT = Path(__file__).resolve().parents[2]
ORIGINAL = ROOT / 'References/SavFury/original'
ASSETS = ROOT / 'Assets/ModelFixes'
checks = 0


def check(ok, why):
    global checks
    assert ok, why
    checks += 1


def namespaced(data):
    return re.sub(b'ssv11', b'csf11', data, flags=re.I)


def read_mesh(data):
    return ogremesh_serializer.MeshSerializer(io.BytesIO(data)).read()


manifest = json.loads((ROOT / 'References/SavFury/provenance.json').read_text())
for name, digest in manifest['original_sha256'].items():
    check(sha256((ORIGINAL / name).read_bytes()).hexdigest() == digest, 'source asset provenance ' + name)
check((ORIGINAL / 'svsav.mesh').read_bytes() == (ASSETS / 'svsav.mesh').read_bytes(), 'built from the mesh CR ships as svsav')

# --- native model: toolkit load, objects > 0, hardpoint GEOs present, unchanged except the part prefix
raw = (ASSETS / 'savfury.vdf').read_bytes()
check(raw == namespaced((ORIGINAL / 'svsav.vdf').read_bytes()), 'VDF is the stock one with only the part prefix renamed')
vdf = bwd2_serializer.VDFSerializer(io.BytesIO(raw)).read()
old = bwd2_serializer.VDFSerializer(io.BytesIO((ORIGINAL / 'svsav.vdf').read_bytes())).read()
parts = [o.name for o in vdf.primary_objects()]
check(vdf.objcount > 0 and len(parts) == 7 and vdf.objcount == old.objcount, 'VDF loads with all seven parts')
for hardpoint in ('GC1', 'GM1', 'GR1', 'GS1', 'LGT', 'POV'):
    check('csf11' + hardpoint in parts, 'hardpoint part survives: csf11' + hardpoint)
check(not any(p.lower().startswith('ssv11') for p in parts), 'no stock part name is claimed')
for part in parts:
    geo = ASSETS / (part.lower() + '.geo')
    check(geo.is_file(), 'GEO companion ships: ' + geo.name)
    model = geo_serializer.GeoSerializer(io.BytesIO(geo.read_bytes())).read()
    check(model.vert_count >= 0 and model.name.lower().startswith('csf11'), 'GEO loads through the toolkit: ' + geo.name)
    stock = ORIGINAL / ('ss' + 'v11' + geo.name[5:])
    check(namespaced(stock.read_bytes()) == geo.read_bytes(), 'GEO geometry unchanged: ' + geo.name)
sk_raw = (ASSETS / 'savfury.skeleton').read_bytes()
check(sk_raw == namespaced((ORIGINAL / 'svsav.skeleton').read_bytes()), 'skeleton unchanged except the part prefix')
skeleton = ogreskeleton_serializer.SkeletonSerializer(io.BytesIO(sk_raw)).read()
check(len(list(skeleton.bones())) > 0, 'skeleton loads')

# --- mesh: only the material and skeleton resource links differ
before = read_mesh((ORIGINAL / 'svsav.mesh').read_bytes())
after = read_mesh((ASSETS / 'savfury.mesh').read_bytes())
check(after.skeleton_name == 'savfury.skeleton' and len(before.submesh_list) == len(after.submesh_list) >= 1, 'own skeleton, same submeshes')
for a, b in zip(before.submesh_list, after.submesh_list):
    check(b.material_name == 'savfury' and a.material_name == 'svsav', 'own material link')
    check(a.index_count == b.index_count and bytes(a.get_index_buffer()) == bytes(b.get_index_buffer()), 'indices preserved')
    check(a.vertex_data.vertex_count == b.vertex_data.vertex_count > 0, 'vertex count preserved')
    check([vars(e) for e in a.vertex_data.vertex_declaration.vertex_element_list] == [vars(e) for e in b.vertex_data.vertex_declaration.vertex_element_list], 'vertex layout preserved')
    check(all(bytes(vb.buffer) == bytes(b.vertex_data.get_vertex_buffer(i).buffer) for i, vb in a.vertex_data.vertex_buffer_map.items()), 'positions, normals, UVs preserved')
    weights = lambda s: [(v.vertex_index, v.bone_index, v.weight) for v in s.bone_assignments()]
    check(weights(a) == weights(b), 'skin weights preserved')
check(vars(before.aabb) == vars(after.aabb) and before.bound_radius == after.bound_radius, 'bounds preserved')

# --- textures and material
material = (ROOT / 'Materials/savfury.material').read_text()
check('material savfury : CR_BZBase' in material, 'own material')
for suffix in ('d', 'e'):
    name = f'savfury_{suffix}.dds'
    check(bc_dds_problem((ROOT / 'Assets/Textures' / name).read_bytes(), 1024) is None, name + ' is BC1 1024 with full mips')
    check(name in material, name + ' is selected by the material')
check('set_texture_alias EmissiveMap savfury_e.dds' in material and 'set_texture_alias DiffuseMap savfury_d.dds' in material, 'diffuse and emissive are the new ones')
check('crteam_' not in material, 'no team-skin material is bound to the infected hull')

# --- ODF: stock savs8 stats under the new model
def odf(name):
    text = (ROOT / 'ODF' / f'{name}.odf').read_text()
    return {m[1].lower(): m[2].strip().strip('"') for m in re.finditer(r'(?m)^(\w+)\s*=\s*([^/\n]*)', text)}


fury = odf('savfury')
stock = {'classlabel': 'sav', 'scrapvalue': '2', 'scrapcost': '8', 'maxhealth': '4000', 'maxammo': '2000', 'ainame': 'SAVEnemy',
         'ainame2': 'SAVEnemy', 'heatsignature': '0.5', 'imagesignature': '0.8', 'radarsignature': '1.0', 'weaponhard1': 'GC1',
         'weaponname1': 'gbolt', 'weaponhard2': 'GR1', 'weaponname2': 'gwasp', 'rangescan': '400.0f', 'periodscan': '2.0f',
         'velocjam': '5.0f', 'diedmsg': 'sbetty3.wav', 'setaltitude': '5.0', 'velocforward': '200.0',
         'velocreverse': '20.0', 'velocstrafe': '20.0', 'accelthrust': '200.0', 'accelbrake': '25.0', 'omegaspin': '2.0',
         'omegaturn': '1.0', 'acceldragstop': '3.5', 'alphasteer': '5.0', 'acceljump': '400.0', 'sounddeploy': 'avsave5.wav',
         'soundundeploy': 'avsave6.wav', 'soundthrust': 'avsave0.wav'}
for key, value in stock.items():
    check(fury.get(key) == value, f'savfury keeps the stock savs8 {key}')
check(fury['basename'] == 'savfury' and fury['unitname'] == 'Infected Fury', 'own model and display name')
check(not (ROOT / 'ODF/savs8.odf').exists(), 'the stock savs8 name is never overridden')

# --- the betrayal swap builds it; it ships
lua = (ROOT / 'Scripts/misns8cr.lua').read_text(encoding='utf-8')
check('odf == "savs8" then odf = "savfury"' in lua, 'misns8cr maps the swap build to savfury')
lock = json.loads((ROOT / 'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'))
members = {x['source'].replace('\\', '/'): x['runtime'] for x in lock['files']}
shipped = [p for p in ASSETS.iterdir() if p.name.startswith(('savfury.', 'csf11'))]
shipped += [ROOT / 'Assets/Textures/savfury_d.dds', ROOT / 'Assets/Textures/savfury_e.dds',
            ROOT / 'Materials/savfury.material', ROOT / 'ODF/savfury.odf']
check(len(shipped) == 14, 'every savfury file is accounted for')
for p in shipped:
    check(members.get(p.relative_to(ROOT).as_posix()) == p.name, 'shipping admission: ' + p.name)
print(f'savfury assets: {checks} checks passed')
