"""Give Achilles (misn17) a cold temperate forest: pack trees, rocks and shore ice.

Run after Build-Misn17Jungle.py. It edits that tool's output in place and is
idempotent: the jungle's tree sites, ground-cover layers and water mask stay
where they are, and only what stands on them changes.

* Trees: the "Low Poly Forest Tree Pack" by 99.Miles (CC-BY-4.0, see
  Docs/FOLIAGE_ART_CREDITS.md). Its four branch + trunk pairs become the solid
  plants c17frst1-4, scaled to the Mire trees they replace. Collision is a
  trunk prism; the canopy has none, as before.
* Rocks: the pack's nine rocks become render-only StaticGeometry layers beside
  the existing ground cover, on forest and rock tiles.
* Ice: ISDF Chronicles' baneice/darkice bergs (BZ2-derived, shipped in ISDFC),
  stretched into long thin render-only shelves cr17_islab1-6 (4-12 m long,
  2-5 m wide) and chained, overlapping, along stretches of pool shore, stream
  bank and river: water freezing at its edge, with open bank between stretches.
  Like the rocks they have no collision, so craft drive over them.
* Explosion: ISDFC's cosmetic xplnxpl (the trees' explosionName) is copied with
  its smokeb.tga sprite; amb_wind.wav is stock.

Never writes to ISDFC or the pack. Every SDF, GEO, Ogre mesh and skeleton byte
comes from the shared libraries (Tools/bzmodellibs.py, Tools/bzstaticmodel.py).
"""
from pathlib import Path
import argparse
import copy
import hashlib
import io
import json
import math
import re
import struct
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
ROOT = Path(__file__).resolve().parents[1]
SEED = 17117
# Rock layers tile coarser than the ground cover's 384 m: CRJungle17 builds one
# StaticGeometry per layer per update, and each still culls by 192 m region.
ROCK_TILE = 1152

# Pack trees: (branches node, trunk node, CR name, target height in metres).
# The Mire trees stood 55-60 m (c17tree1/2 bounds); the pack's trees range
# 9-23 m, so each is scaled to its own height in that band.
TREES = [
    ('Tree_Branches_01', 'Tree_Trunk_01.001', 'c17frst1', 58.0),
    ('Tree_Branches_01.001', 'Tree_Trunk_01', 'c17frst2', 46.0),
    ('Tree_Branches_01.002', 'Tree_Trunk_01.002', 'c17frst3', 52.0),
    ('Tree_Branches_02', 'Tree_Trunk_02', 'c17frst4', 40.0),
]
# Share of the existing tree sites each model takes.
TREE_WEIGHTS = [.3, .3, .25, .15]
ROCKS = ['Rocks'] + ['Rocks.%03d' % i for i in range(1, 9)]

# ISDFC bergs whose plan outline makes a plausible floe; each becomes a slab
# cr17_islabN. Tall props from the previous pass (c17bice*/c17dice*) are removed.
SLABS = ['baneice2', 'baneice4', 'baneice5', 'darkice1', 'darkice3', 'darkice4']
OLD_ICE = ['c17bice%d' % i for i in range(1, 6)] + ['c17dice%d' % i for i in range(1, 5)]
# Plan aspect (width / length) of each slab mesh: the long axis is local x.
SLAB_ASPECT = [.3, .35, .4, .45, .55, .65]
# Thickness as a share of the half-length: a 12 m shelf is 0.27 m thick, a 4 m one 9 cm.
SLAB_THICK = .045
# Sprite for xplnxpl: ISDFC's smokeb.tga, alpha-blended like CR's smokeb2
# because the ODF draws it with srcalpha/invsrcalpha.
SMOKEB = '''import * from "sprites.material"

// ISDF Chronicles' xplnxpl puff (Tools/Build-Misn17Forest.py). Alpha-blended to
// match the ODF's srcalpha/invsrcalpha blend, as smokeb2.material is.
material smokeb.tga : BZSprite/AlphaBlend
{
	set_texture_alias DiffuseMap smoke.dds
}
'''


# --------------------------------------------------------------------------- glTF
def load_glb(path):
    data = Path(path).read_bytes()
    magic, _, _ = struct.unpack_from('<4sII', data, 0)
    assert magic == b'glTF', 'not a GLB'
    jl, _ = struct.unpack_from('<II', data, 12)
    g = json.loads(data[20:20 + jl])
    bl, _ = struct.unpack_from('<II', data, 20 + jl)
    return g, data[28 + jl:28 + jl + bl]


def accessor(g, blob, i):
    a = g['accessors'][i]
    bv = g['bufferViews'][a['bufferView']]
    comps = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    dt = {5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}[a['componentType']]
    size = np.dtype(dt).itemsize * comps
    stride = bv.get('byteStride', size)
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    raw = np.frombuffer(blob, np.uint8, count=stride * (a['count'] - 1) + size, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, (a['count'], size), (stride, 1))
    return np.ascontiguousarray(rows).view(dt).reshape(a['count'], comps)


def node_matrix(n):
    if 'matrix' in n:
        return np.array(n['matrix'], float).reshape(4, 4).T
    t = np.eye(4)
    if 'scale' in n:
        t = np.diag(list(n['scale']) + [1]) @ t
    if 'rotation' in n:
        x, y, z, w = n['rotation']
        r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                      [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                      [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        m = np.eye(4); m[:3, :3] = r; t = m @ t
    if 'translation' in n:
        m = np.eye(4); m[:3, 3] = n['translation']; t = m @ t
    return t


def pack_parts(g, blob):
    """{node name: (positions, normals, uvs, indices, material index)} in glTF world space (Y up, metres)."""
    out = {}
    def walk(i, parent):
        n = g['nodes'][i]
        m = parent @ node_matrix(n)
        if 'mesh' in n:
            name = g['nodes'][walk.parent_of[i]]['name']
            (pr,) = g['meshes'][n['mesh']]['primitives']
            at = pr['attributes']
            p = accessor(g, blob, at['POSITION']).astype(float)
            nn = accessor(g, blob, at['NORMAL']).astype(float)
            uv = accessor(g, blob, at['TEXCOORD_0']).astype(float)
            idx = accessor(g, blob, pr['indices']).ravel().astype(np.int64)
            p = (np.c_[p, np.ones(len(p))] @ m.T)[:, :3]
            nm = np.linalg.inv(m[:3, :3]).T
            nn = nn @ nm.T
            nn /= np.linalg.norm(nn, axis=1, keepdims=True)
            if np.linalg.det(m[:3, :3]) < 0:
                idx = idx.reshape(-1, 3)[:, ::-1].ravel()
            out[name] = (p, nn, uv, idx, pr['material'])
        for c in n.get('children', []):
            walk.parent_of[c] = i
            walk(c, m)
    walk.parent_of = {}
    for r in g['scenes'][0]['nodes']:
        walk(r, np.eye(4))
    return out


def image(g, blob, tex_index):
    from PIL import Image
    im = g['images'][g['textures'][tex_index]['source']]
    bv = g['bufferViews'][im['bufferView']]
    o = bv.get('byteOffset', 0)
    return Image.open(io.BytesIO(blob[o:o + bv['byteLength']]))


# ------------------------------------------------------------------- Lua sites
def lua_value(v):
    """Build-Misn17Jungle.py's emitter, so a parse/emit round trip is byte-identical."""
    if isinstance(v, dict):
        return '{' + ','.join(k + '=' + lua_value(x) for k, x in v.items()) + '}'
    if isinstance(v, (list, tuple)):
        return '{' + ','.join(lua_value(x) for x in v) + '}'
    return json.dumps(v)


def parse_lua(text):
    """Parse the table literal that lua_value writes."""
    i = 0
    tok = re.compile(r'\s*(?:([A-Za-z_]\w*)=|("(?:[^"\\]|\\.)*")|(-?\d[\d.eE+-]*)|(true|false|nil)|([{},]))')
    def nxt():
        nonlocal i
        m = tok.match(text, i)
        assert m, text[i:i + 40]
        i = m.end()
        return m
    def value(m):
        if m[2] is not None:
            return json.loads(m[2])
        if m[3] is not None:
            return json.loads(m[3])
        if m[4] is not None:
            return {'true': True, 'false': False, 'nil': None}[m[4]]
        assert m[5] == '{'
        items, keys = [], []
        while True:
            m = nxt()
            if m[5] == '}':
                break
            if m[5] == ',':
                continue
            if m[1]:
                keys.append(m[1]); items.append(value(nxt()))
            else:
                keys.append(None); items.append(value(m))
        if keys and all(keys):
            return dict(zip(keys, items))
        assert not any(keys), 'mixed table'
        return items
    return value(nxt())


SITES_HEAD = '-- Generated by Build-Misn17Jungle.py\nreturn '


def read_sites():
    text = (ROOT / 'Scripts/CRJungle17Sites.lua').read_text()
    assert text.startswith(SITES_HEAD)
    data = parse_lua(text[len(SITES_HEAD):])
    assert SITES_HEAD + lua_value(data) + '\n' == text, 'CRJungle17Sites.lua does not round-trip'
    return data


# ------------------------------------------------------------------- textures
def dds(path, img, fmt, size=None):
    """Block-compressed DDS with a full mip chain, via the toolbox encoder."""
    from PIL import Image
    from bztoolbox.modules.textures import bcpack
    img = img.convert('RGBA')
    if size and img.size != size:
        img = img.resize(size, Image.LANCZOS)
    levels, _ = bcpack.build_chain([np.asarray(img)], *img.size)
    bcpack.write_dds(str(path), img.size[0], img.size[1], [bcpack.encode_level(l, fmt) for l in levels], fmt)


def directx_normal(img):
    """glTF normal maps are OpenGL (+Y); the game samples DirectX (-Y), so flip green."""
    from PIL import Image
    a = np.asarray(img.convert('RGB')).copy()
    a[:, :, 1] = 255 - a[:, :, 1]
    return Image.fromarray(a, 'RGB')


def specular_from_roughness(img, gain):
    """Grey specular from a glTF roughness (G) channel: wet where smooth."""
    from PIL import Image
    a = np.asarray(img.convert('RGB'), float)[:, :, 1] / 255
    s = np.clip((1 - a) * gain * 255, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([s, s, s]), 'RGB')


def check_not_blank(path):
    data = Path(path).read_bytes()
    body = data[128:] if data[:4] == b'DDS ' else data
    assert len(body) and any(body), f'{path} is empty or zero-filled'
    return hashlib.sha256(data).hexdigest()


# ------------------------------------------------------------------- models
def prism_geo(name, radius, height, n=8):
    """Collision GEO: a slightly tapered n-gon prism (the trunk)."""
    from bzmodellibs import geo, geo_serializer
    from battlezone.meshes.legacy import read_geo
    v = [(radius * math.cos(a * math.tau / n), 0, radius * math.sin(a * math.tau / n)) for a in range(n)]
    v += [(radius * .6 * math.cos(a * math.tau / n), height, radius * .6 * math.sin(a * math.tau / n)) for a in range(n)]
    faces = [[i for i in range(n - 1, -1, -1)]]
    faces += [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
    faces.append([n + i for i in range(n)])
    p = np.array(v, float)
    g = geo.Geo(); g.name = name; g.vert_count = len(v)
    g.vertex_pos_buffer = p.astype('<f4'); g.vertex_normal_buffer = np.zeros_like(p, dtype='<f4')
    for i, face in enumerate(faces):
        q = p[face]; normal = np.cross(q[1] - q[0], q[2] - q[0]); normal /= np.linalg.norm(normal)
        # Native GEO uses inward plane normals, as the stock port codec expects.
        gf = g.create_face(i); gf.color = geo.Color3(255, 255, 255)
        gf.plane = geo.SurfacePlane(geo.Vector3(*(-normal)), float(normal @ q[0]))
        gf.shade_type = gf.texture_type = 0; gf.texture_name = name + '.map'
        for j in face:
            gf.create_face_node(j, j, geo.UV(float(p[j][0] * .2 + .5), float(p[j][1] * .05)))
    raw = io.BytesIO(); geo_serializer.GeoSerializer(raw).write(g); raw = raw.getvalue()
    read_geo(raw)
    return raw, p


def submesh(material, pos, nrm, uv, idx, bone, alpha=None):
    """One submesh in the stock building layout: (position, normal) + (ABGR colour, uv), skinned to one bone.

    alpha (0..1 per vertex) goes in the colour's alpha byte, white otherwise."""
    from battlezone.meshes import ogre
    n = len(pos)
    a = np.c_[pos, nrm].astype('<f4').tobytes()
    b = np.zeros(n, dtype=[('c', '<u4'), ('uv', '<f4', 2)])
    b['c'] = 0xFFFFFF
    b['c'] |= (np.full(n, 255) if alpha is None else np.round(np.clip(alpha, 0, 1) * 255)).astype('<u4') << 24
    b['uv'] = uv
    geo = ogre.Geometry(vertex_count=n, elements=[ogre.VertexElement(0, 2, 1, 0, 0), ogre.VertexElement(0, 2, 4, 12, 0),
                                                 ogre.VertexElement(1, 11, 5, 0, 0), ogre.VertexElement(1, 1, 7, 4, 0)],
                        buffers={0: ogre.VertexBuffer(0, 24, a, 0), 1: ogre.VertexBuffer(1, 12, b.tobytes(), 0)})
    return ogre.SubMesh(material=material, uses_shared_vertices=False, indices=[int(i) for i in idx],
                        use32bit=n > 65535, operation=4, geometry=geo,
                        bone_assignments=[] if bone is None else [(i, bone, 1.0) for i in range(n)])



# ------------------------------------------------------------------- build
MATERIALS_HEAD = '''// Generated by Tools/Build-Misn17Forest.py. Achilles' cold temperate forest.
// Trees and rocks: "Low Poly Forest Tree Pack" by 99.Miles, CC-BY-4.0
// (Docs/FOLIAGE_ART_CREDITS.md). Ice slabs: flattened ISDF Chronicles baneice/darkice.
// Canopies sway like the Mire trees did: CR17/CutoutWind, baked by
// Tools/Bake-FoliageSway.py, registered with CRFoliageWind in CRJungle17.lua.
import * from "cr17_wind.material"
import * from "BZBase.material"
'''

CASTER = '''material CR17/CutoutCaster/%s
{
	technique
	{
		pass
		{
			scene_blend one one
			scene_blend_op min
			depth_check off
			depth_write off
			cull_hardware none
			cull_software none
			vertex_program_ref CR17_Wind_Caster_vertex
			{
				param_named windShape float4 0.6 0.7 0.18 5.5
			}
			fragment_program_ref CR17_Cutout_Caster_fragment
			{
				param_named cutoutParams float4 0.45 0 0 0
			}
			texture_unit diffuseMap
			{
				texture %s
			}
		}
	}
}
'''

BRANCHES = '''material CR17/%s : CR17/CutoutWind
{
	set_texture_alias DiffuseMap %s
	set_texture_alias NormalMap cr17_flat.dds
	set_texture_alias SpecularMap cr17_black.dds
	set_texture_alias EmissiveMap cr17_black.dds
	set $cutoutParams "0.45 0.5 0.6 512"
	set $diffuse "%s"
	set $specular "0.08 0.08 0.08"
	set $shininess "16"
	set $caster "CR17/CutoutCaster/%s"
	set $windShape "0.6 0.7 0.18 5.5"
}
'''

SOLID = '''material CR17/%s : BZBase
{
	set_texture_alias DiffuseMap %s.dds
	set_texture_alias NormalMap %s_n.dds
	set_texture_alias SpecularMap %s_s.dds
	set_texture_alias EmissiveMap cr17_black.dds
	set $diffuse "%s"
	set $ambient "1 1 1"
	set $specular "%s"
	set $shininess "%s"
}
'''

GROUND_COLD = '''material CR17/GroundWindCold : CR17/CutoutWind
{
	set_texture_alias DiffuseMap cr17_foliage.dds
	set_texture_alias NormalMap cr17_flat.dds
	set_texture_alias SpecularMap cr17_black.dds
	set_texture_alias EmissiveMap cr17_black.dds
	set $cutoutParams "0.45 0.5 0.6 2048"
	set $diffuse "0.70 0.80 0.78"
	set $ambient "0.86 0.92 0.94"
	set $specular "0.14 0.15 0.16"
	set $shininess "20"
	set $caster "CR17/NoShadowCaster"
	set $windShape "0.45 1.6 0.07 8.0"
}
'''

ODF = '''[GameObjectClass]
baseName = "%s"
classLabel = "i76building2"
scrapCost = 0
scrapValue = 0
maxHealth = %d
maxAmmo = 0
unitName = "%s"
collisionRadius = %g
explosionName = "xplnxpl"
[PlantClass]
isPlant = 1
dropScrap = 0
'''


def plan_thickness(xz):
    """0 on the plan outline (convex hull) of the points, 1 at the deepest point inside it."""
    pts = sorted(set(map(tuple, np.round(xz, 6))))
    def half(seq):
        h = []
        for q in seq:
            while len(h) > 1 and (h[-1][0] - h[-2][0]) * (q[1] - h[-2][1]) - (h[-1][1] - h[-2][1]) * (q[0] - h[-2][0]) <= 0:
                h.pop()
            h.append(q)
        return h[:-1]
    hull = np.array(half(pts) + half(pts[::-1]))
    a, b = hull, np.roll(hull, -1, 0)
    ab = b - a
    t = np.clip(((xz[:, None, :] - a) * ab).sum(2) / np.maximum((ab * ab).sum(1), 1e-12), 0, 1)
    d = np.linalg.norm(xz[:, None, :] - (a + t[..., None] * ab), axis=2).min(1)
    return d / max(d.max(), 1e-9)


def build(pack, isdfc):
    import bzmodellibs
    sys.path.insert(0, str(bzmodellibs.toolbox_root()))
    from battlezone.meshes import ogre
    from battlezone.meshes.legacy_port import build_port, PortOptions
    from battlezone.meshes.ogre_skeleton import write_skeleton
    from battlezone.bzn.bz1 import read_bzn, write_bzn
    from battlezone.terrain.hg2 import read_hg2
    from battlezone.terrain.mat import read_mat
    from bzstaticmodel import static_sdf_bytes
    import importlib.util
    spec = importlib.util.spec_from_file_location('sway', ROOT / 'Tools/Bake-FoliageSway.py')
    sway = importlib.util.module_from_spec(spec); spec.loader.exec_module(sway)
    models, textures = ROOT / 'Assets/Models', ROOT / 'Assets/Textures'
    consumed = {}
    def src(path):
        data = Path(path).read_bytes()
        consumed[Path(path).name] = hashlib.sha256(data).hexdigest()
        return data

    g, blob = load_glb(pack)
    consumed[Path(pack).name] = hashlib.sha256(Path(pack).read_bytes()).hexdigest()
    lic = g['asset'].get('extras', {})
    assert 'CC-BY-4.0' in lic.get('license', '') and '99.Miles' in lic.get('author', ''), 'unexpected pack licence'
    parts = pack_parts(g, blob)
    mats = g['materials']
    def tex(mat, key):
        m = mats[mat]
        if key == 'normal':
            return image(g, blob, m['normalTexture']['index'])
        return image(g, blob, m['pbrMetallicRoughness'][key]['index'])

    # Textures: branch cards keep their 512 size, trunks theirs, rock normals halve to 512.
    written = {}
    def put(name, img, fmt, size=None):
        dds(textures / name, img, fmt, size); written[name] = check_not_blank(textures / name)
    COLD_LEAF = '0.86 0.94 0.96'   # a touch of frost on the needles
    mat_text = [MATERIALS_HEAD]
    branch_mats, trunk_mats = {}, {}
    for mi in sorted({parts[b][4] for b, *_ in TREES}):
        k = len(branch_mats) + 1
        name = 'cr17_fbranch%d.dds' % k
        put(name, tex(mi, 'baseColorTexture'), 'DXT5')
        branch_mats[mi] = 'ForestBranch%dWind' % k
        mat_text.append(CASTER % (branch_mats[mi], name))
        mat_text.append(BRANCHES % (branch_mats[mi], name, COLD_LEAF, branch_mats[mi]))
    for mi in sorted({parts[t][4] for _, t, *_ in TREES}):
        k = len(trunk_mats) + 1
        base = 'cr17_ftrunk%d' % k
        put(base + '.dds', tex(mi, 'baseColorTexture'), 'DXT1')
        put(base + '_n.dds', directx_normal(tex(mi, 'normal')), 'DXT1')
        put(base + '_s.dds', specular_from_roughness(tex(mi, 'metallicRoughnessTexture'), .35), 'DXT1')
        trunk_mats[mi] = 'ForestTrunk%d' % k
        mat_text.append(SOLID % (trunk_mats[mi], base, base, base, '0.9 0.93 0.95', '0.25 0.27 0.3', '24'))
    rock_mat = parts['Rocks'][4]
    put('cr17_frock.dds', tex(rock_mat, 'baseColorTexture'), 'DXT1')
    put('cr17_frock_n.dds', directx_normal(tex(rock_mat, 'normal')), 'DXT1', (512, 512))
    put('cr17_frock_s.dds', specular_from_roughness(tex(rock_mat, 'metallicRoughnessTexture'), .5), 'DXT1', (256, 256))
    mat_text.append(SOLID % ('ForestRock', 'cr17_frock', 'cr17_frock', 'cr17_frock', '0.82 0.86 0.9', '0.35 0.38 0.42', '40'))
    # Ice: ISDFC's iceberg set, already block-compressed with mips, copied as is.
    for old, new in [('iceberg.dds', 'cr17_ice.dds'), ('iceberg_n.dds', 'cr17_ice_n.dds'), ('iceberg_s.dds', 'cr17_ice_s.dds')]:
        data = src(isdfc / old); (textures / new).write_bytes(data); written[new] = check_not_blank(textures / new)
    # The slabs' material is Materials/cr17_ice.material (CR17/IceShelf), not generated.
    # Misn17's copy of the Mire ground cover, cooled toward a damp temperate
    # floor. CRJungle17 passes it as the StaticGeometry material override, so
    # misn18's storm keeps CR17/GroundWind untouched.
    mat_text.append(GROUND_COLD)
    (ROOT / 'Materials/cr17_forest.material').write_text('\n'.join(mat_text), newline='\n')

    # Trees: trunk base at the origin, scaled to the Mire trees' heights.
    tree_info = {}
    for bname, tname, name, height in TREES:
        bp, bn, buv, bi, bm = parts[bname]
        tp, tn, tuv, ti, tm = parts[tname]
        base = tp[:, 1].min()
        foot = tp[tp[:, 1] < base + .6]
        cx, cz = foot[:, 0].mean(), foot[:, 2].mean()
        top = max(bp[:, 1].max(), tp[:, 1].max())
        s = height / (top - base)
        off = np.array([cx, base, cz])
        bp, tp = (bp - off) * s, (tp - off) * s
        r = float(np.percentile(np.hypot(foot[:, 0] - cx, foot[:, 2] - cz), 90)) * s
        trunk_h = float(tp[:, 1].max()) * .55
        geo_bytes, gp = prism_geo(name, r, trunk_h)
        (models / (name + '.geo')).write_bytes(geo_bytes)
        lo, hi = gp.min(0), gp.max(0)
        sdf = static_sdf_bytes(name, (lo + hi) / 2, (hi - lo) / 2, float(np.linalg.norm((hi - lo) / 2)), null_parent='NULL')
        (models / (name + '.sdf')).write_bytes(sdf)
        port = build_port(sdf, 'sdf', name, lambda n: (models / n).read_bytes(), PortOptions(normals='flat', texture_format='none'))
        skel = write_skeleton(port.skeleton)
        (models / (name + '.skeleton')).write_bytes(skel)
        mesh = ogre.OgreMesh(version='MeshSerializer_v1.100', endian='little', skeleton=name + '.skeleton',
            submeshes=[submesh('CR17/' + trunk_mats[tm], tp, tn, tuv, ti, 0),
                       submesh('CR17/' + branch_mats[bm], bp, bn, buv, bi, 0)])
        ogre.write_mesh(mesh, models / (name + '.mesh'))
        sway.bake(models / (name + '.mesh'), 'tree', 'CR17/' + branch_mats[bm], 'CR17/' + branch_mats[bm], ogre)
        (ROOT / 'ODF' / (name + '.odf')).write_text(ODF % (name, 2500, 'Fir Tree', max(3, round(r * 1.5, 1))), newline='\n')
        tree_info[name] = {'height': height, 'trunk_radius': round(r, 2), 'scale': round(s, 3),
                           'triangles': (len(bi) + len(ti)) // 3}

    # Rocks: render-only ground cover, base on the ground, unskinned.
    rock_meshes = []
    for k, rname in enumerate(ROCKS, 1):
        p, n, uv, idx, _ = parts[rname]
        c = p.mean(0); p = p - [c[0], p[:, 1].min() + .05 * (p[:, 1].max() - p[:, 1].min()), c[2]]
        mesh = ogre.OgreMesh(version='MeshSerializer_v1.100', endian='little',
                             submeshes=[submesh('CR17/ForestRock', p, n, uv, idx, None)])
        name = 'cr17_frock%d.mesh' % k
        ogre.write_mesh(mesh, models / name)
        rock_meshes.append((name, float(np.hypot(p[:, 0], p[:, 2]).max())))

    # Ice slabs: an ISDFC berg centred, scaled to a unit half-length along x and
    # SLAB_ASPECT of it along z, squashed to SLAB_THICK, y centred on the middle.
    # Normals follow the squash (inverse scale), so the top faces the sky. Vertex
    # colour alpha carries the plan thickness CR17/IceShelf melts and fades by
    # (Shaders/cr17_ice.hlsl): 0 on the outline, 1 in the deepest middle.
    ice_info, slab_meshes = {}, []
    for k, old in enumerate(SLABS, 1):
        m = ogre.read_mesh(src(isdfc / (old + '.mesh')))
        geos = [m.shared_geometry] if m.shared_geometry is not None else []
        geos += [sm.geometry for sm in m.submeshes if not sm.uses_shared_vertices]
        allp = np.concatenate([np.array(gm.attribute(1, 0), float) for gm in geos])
        lo, hi = allp.min(0), allp.max(0)
        cx, cz = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2
        reach = float(np.hypot(allp[:, 0] - cx, allp[:, 2] - cz).max())
        sv = np.array([2 / (hi[0] - lo[0]), SLAB_THICK / (hi[1] - lo[1]), 2 * SLAB_ASPECT[k - 1] / (hi[2] - lo[2])])
        outline = (allp - [cx, 0, cz])[:, ::2] * sv[::2]
        subs, tris = [], 0
        for sm in m.submeshes:
            gm = m.shared_geometry if sm.uses_shared_vertices else sm.geometry
            pos = (np.array(gm.attribute(1, 0), float) - [cx, (lo[1] + hi[1]) / 2, cz]) * sv
            nrm = np.array(gm.attribute(4, 0), float) / sv
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
            uv = np.array(gm.attribute(7, 0), float)
            thick = plan_thickness(np.r_[pos[:, ::2], outline])[:len(pos)]
            subs.append(submesh('CR17/IceShelf', pos, nrm, uv, sm.indices, None, thick)); tris += len(sm.indices) // 3
        name = 'cr17_islab%d.mesh' % k
        ogre.write_mesh(ogre.OgreMesh(version='MeshSerializer_v1.100', endian='little', submeshes=subs), models / name)
        slab_meshes.append(name)
        ice_info[name] = {'source': old, 'source_width': round(2 * reach, 1), 'source_height': round(float(hi[1] - lo[1]), 1),
                          'aspect': SLAB_ASPECT[k - 1], 'triangles': tris}
    for name in OLD_ICE:
        for path in [models / (name + ext) for ext in ('.mesh', '.skeleton', '.sdf')] + [ROOT / 'ODF' / (name + '.odf')]:
            path.unlink(missing_ok=True)

    # xplnxpl: ISDFC's zero-damage green puff, the trees' explosionName.
    (ROOT / 'ODF/xplnxpl.odf').write_bytes(src(isdfc / 'xplnxpl.odf'))
    (textures / 'smoke.dds').write_bytes(src(isdfc / 'smoke.dds')); written['smoke.dds'] = check_not_blank(textures / 'smoke.dds')
    (ROOT / 'Materials/smokeb.material').write_text(SMOKEB, newline='\n')

    # --------------------------------------------------------------- placement
    sites = read_sites()
    _, h = read_hg2(ROOT / 'Missions/misn17.hg2'); ground = h.astype(float) * .1
    tiles = read_mat(ROOT / 'Missions/misn17.mat', 4, 4)
    def height(x, z): return float(ground[round((z - 97280) / 5), round(x / 5)])
    def tile(x, z): return int(tiles[int((z - 97280) / 20), int(x / 20)]) >> 12
    bzn = read_bzn(ROOT / 'Missions/misn17cr.bzn')
    ours = ('cr17_tree', 'cr17_ice')
    guards = np.array([o.fields['transform'].value[9::2] for o in bzn.objects
                       if o.prjid != 'sfield' and not o.label.startswith(ours)])
    route_pts = np.array([pt for p in bzn.paths for pt in p['points'].value], float).reshape(-1, 2)
    river = sites['river']
    def seg_dist(x, z):
        best = math.inf
        for (ax, az), (bx, bz) in zip(river, river[1:]):
            dx, dz = bx - ax, bz - az
            t = max(0, min(1, ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz)))
            best = min(best, math.hypot(x - ax - dx * t, z - az - dz * t))
        return best
    def clear(x, z, r_obj, r_path):
        return (not np.any((guards[:, 0] - x) ** 2 + (guards[:, 1] - z) ** 2 < r_obj * r_obj)
                and not np.any((route_pts[:, 0] - x) ** 2 + (route_pts[:, 1] - z) ** 2 < r_path * r_path))

    # Water grid from the jungle's run-length mask (what the meshes draw) plus the river strip.
    wm = sites['watermask']
    wet = np.zeros(ground.shape, bool)
    for r, runs in enumerate(wm['rows']):
        for a, n in zip(runs[::2], runs[1::2]):
            wet[wm['firstRow'] + r, a:a + n] = True
    river_cells = np.zeros(ground.shape, bool)
    for (ax, az), (bx, bz) in zip(river, river[1:]):
        for t in np.linspace(0, 1, 40):
            x, z = ax + (bx - ax) * t, az + (bz - az) * t
            iz, ix = round((z - 97280) / 5), round(x / 5)
            river_cells[iz - 1:iz + 2, ix - 1:ix + 2] = True
    water = wet | river_cells
    # Shore = a dry cell with water in its 8-neighbourhood: the edge of the drawn water.
    nb = np.zeros_like(water)
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            nb |= np.roll(np.roll(water, dr, 0), dc, 1)
    shore = nb & ~water
    # How much water lies within ~30 m: pools and the river score high, a thin stream low.
    k = 6
    cs = np.pad(water.astype(np.int32), ((k + 1, k), (k + 1, k))).cumsum(0).cumsum(1)
    area = cs[2 * k + 1:, 2 * k + 1:] - cs[:-2 * k - 1, 2 * k + 1:] - cs[2 * k + 1:, :-2 * k - 1] + cs[:-2 * k - 1, :-2 * k - 1]

    # Water surface per 5 m cell: the highest baked water vertex in the cell.
    surf = np.full(ground.shape, -np.inf)
    for key in ('water', 'streams', 'pools'):
        wsite = sites[key]
        wmesh = ogre.read_mesh(models / wsite['mesh'])
        geos = [wmesh.shared_geometry] if wmesh.shared_geometry is not None else []
        geos += [sm.geometry for sm in wmesh.submeshes if not sm.uses_shared_vertices]
        for gm in geos:
            # Build-Misn17Jungle bakes the water vertices with z mirrored about
            # the site position (render space): sim z = position z - vertex z.
            wp = np.array(gm.attribute(1, 0), float)
            wp = np.c_[wp[:, 0] + wsite['position'][0], wp[:, 1] + wsite['position'][1], wsite['position'][2] - wp[:, 2]]
            iz = np.clip(np.round((wp[:, 2] - 97280) / 5).astype(int), 0, ground.shape[0] - 1)
            ix = np.clip(np.round(wp[:, 0] / 5).astype(int), 0, ground.shape[1] - 1)
            np.maximum.at(surf, (iz, ix), wp[:, 1])

    rng = np.random.default_rng(SEED)
    tree_xy = np.array([t['position'][::2] for t in sites['trees'] if t['label'].startswith('cr17_tree')])
    # Ice shelves: render-only chains along the waterline. A stretch starts at a
    # shore cell and walks the shore 15-35 m; overlapping slabs follow it, long
    # axis along the bank, pushed toward the water so they overhang it. Flat
    # (yaw only), base 3 cm above the surface. Its own generator, so tuning the
    # ice never reshuffles the rocks.
    irng = np.random.default_rng(SEED + 1)
    ok = shore.copy()
    ok[:, :int(780 / 5)] = ok[:, int(3640 / 5) + 1:] = False
    ok[:int((98430 - 97280) / 5)] = ok[int((101740 - 97280) / 5) + 1:] = False
    def waterline(r, c):
        near = [(dr, dc) for dr in range(-2, 3) for dc in range(-2, 3)
                if water[r + dr, c + dc] and np.isfinite(surf[r + dr, c + dc])]
        if not near:
            return None
        wy = float(np.mean([surf[r + dr, c + dc] for dr, dc in near]))
        d = np.mean([(dc, dr) for dr, dc in near], 0)
        return wy, d / max(np.linalg.norm(d), 1e-6)
    # Pool and river shores first (the open water a player sees), then streams.
    cells = list(zip(*np.nonzero(ok)))
    irng.shuffle(cells)
    cells.sort(key=lambda rc: area[rc] < 70)
    used = np.zeros_like(ok)
    ice, placed = [], []
    for r0, c0 in cells:
        if len(placed) >= 48:
            break
        x0, z0 = c0 * 5., r0 * 5. + 97280
        if any(math.hypot(x0 - a, z0 - b) < 60 for a, b in placed) or not clear(x0, z0, 30, 20):
            continue
        # Walk the shore: each step the unvisited shore neighbour that best keeps the heading.
        path, heading = [(r0, c0)], None
        target = irng.uniform(15, 35) / 5
        while len(path) < target:
            r, c = path[-1]
            best = None
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    n = (r + dr, c + dc)
                    if (dr or dc) and ok[n] and not used[n] and n not in path:
                        step = np.array([dc, dr], float) / math.hypot(dc, dr)
                        score = 0 if heading is None else float(step @ heading)
                        if best is None or score > best[0]:
                            best = (score, n, step)
            if best is None or best[0] < -.2:
                break
            heading = best[2] if heading is None else (heading + best[2]) / np.linalg.norm(heading + best[2])
            path.append(best[1])
        if len(path) < 3:
            continue
        info = [waterline(r, c) for r, c in path]
        if any(w is None for w in info) or any(ground[r, c] - w[0] > 1.5 for (r, c), w in zip(path, info)):
            continue  # off the drawn water, or a steep cut bank: no shelf to freeze
        for r, c in path:
            used[r - 2:r + 3, c - 2:c + 3] = True
        pts = np.array([(c * 5., r * 5. + 97280) for r, c in path])
        seg = np.r_[0, np.cumsum(np.hypot(*np.diff(pts, axis=0).T))]
        kind = 'pool/river' if max(area[r, c] for r, c in path) >= 70 else 'stream'
        site, s = [], -2.0
        while s < seg[-1] + 2:
            length = float(irng.uniform(4, 12 if kind == 'pool/river' else 8))
            width = float(irng.uniform(2, min(5, .7 * length)))
            k = min(range(len(SLAB_ASPECT)), key=lambda j: abs(SLAB_ASPECT[j] * length - width))
            half = length / 2
            at = min(max(s + half, 0), seg[-1])
            i = min(int(np.searchsorted(seg, at, side='right')) - 1, len(pts) - 2)
            t = (at - seg[i]) / max(seg[i + 1] - seg[i], 1e-6)
            px, pz = pts[i] + (pts[i + 1] - pts[i]) * t
            tan = (pts[i + 1] - pts[i]) / max(seg[i + 1] - seg[i], 1e-6)
            wy, d = info[i if t < .5 else i + 1]
            # Shore cells sit just inside the bank: push out by part of the width.
            out = SLAB_ASPECT[k] * half * irng.uniform(.5, 1.3) + 1.5
            sx, sz = px + d[0] * out, pz + d[1] * out
            s += length * irng.uniform(.6, .85)
            iz, ix = round((sz - 97280) / 5), round(sx / 5)
            if ground[iz, ix] > wy + .35 or not clear(sx, sz, 25, 15):
                continue
            if len(tree_xy) and np.min(np.hypot(tree_xy[:, 0] - sx, tree_xy[:, 1] - sz)) < 3:
                continue
            # Sim yaw: StaticGeometry turns local x to (cos yaw, sin yaw) in sim x/z.
            yaw = math.atan2(tan[1], tan[0]) + irng.uniform(-.25, .25)
            site.append([slab_meshes[k], round(float(sx), 2), round(wy + .03 + .5 * SLAB_THICK * half, 2), round(float(sz), 2),
                         round(yaw % math.tau, 3), round(half, 3), kind])
        if site:
            placed.append((x0, z0))
            ice += site

    # Trees: the existing sites, Mire models swapped for the pack's, weighted.
    names = [t[2] for t in TREES]
    def pick(label):
        u = int(hashlib.sha256(label.encode()).hexdigest()[:8], 16) / 2 ** 32
        acc = 0
        for n, w in zip(names, TREE_WEIGHTS):
            acc += w
            if u < acc:
                return n
        return names[-1]
    trees = [t for t in sites['trees'] if t['label'].startswith('cr17_tree')]
    for t in trees:
        t['odf'] = pick(t['label'])
    sites['trees'] = trees

    # Rocks: render-only layers on forest and rock tiles, off routes, objects and water.
    layers = [l for l in sites['layers'] if not l['mesh'].startswith(('cr17_frock', 'cr17_islab'))]
    rocks = {}
    spacing = 17
    for z0 in np.arange(98430, 101740, spacing):
        for x0 in np.arange(780, 3640, spacing):
            x = float(x0 + rng.uniform(-spacing * .45, spacing * .45)); z = float(z0 + rng.uniform(-spacing * .45, spacing * .45))
            typ = tile(x, z)
            if typ not in (1, 2) or rng.random() < (.55 if typ == 1 else .25):
                continue
            iz, ix = round((z - 97280) / 5), round(x / 5)
            if water[iz, ix] or seg_dist(x, z) < 12:
                continue
            slope = math.hypot(ground[iz, ix + 1] - ground[iz, ix - 1], ground[iz + 1, ix] - ground[iz - 1, ix]) / 10
            if slope > .7 or not clear(x, z, 30, 20):
                continue
            k = int(rng.integers(len(rock_meshes)))
            mesh, reach = rock_meshes[k]
            # 1.2-4.5 m across, mostly about 2 m: read from a cockpit, but render-only,
            # so never a wall a tank visibly drives through.
            scale = float((1.2 + 3.3 * rng.uniform(0, 1) ** 2) / max(reach * 2, .3))
            p = [round(x, 2), round(height(x, z) - .18 * scale, 2), round(z, 2), round(float(rng.uniform(0, math.tau)), 3), round(scale, 3)]
            rocks.setdefault((mesh, math.floor((x - 2048) / ROCK_TILE), math.floor((z - 99328) / ROCK_TILE)), []).append(p)
    # CRJungle17 builds one layer per update: the few ice layers go before the
    # rocks, so the shore ice is up seconds after the ground cover.
    slabs = {}
    for name, *p, _ in ice:
        slabs.setdefault((name, math.floor((p[0] - 2048) / ROCK_TILE), math.floor((p[2] - 99328) / ROCK_TILE)), []).append(p)
    for key in sorted(slabs):
        layers.append({'mesh': key[0], 'instances': slabs[key]})
    for key in sorted(rocks):
        layers.append({'mesh': key[0], 'instances': rocks[key]})
    sites['layers'] = layers
    (ROOT / 'Scripts/CRJungle17Sites.lua').write_text(SITES_HEAD + lua_value(sites) + '\n', newline='\n')

    # BZN: preplaced trees take their site's model; the old preplaced ice goes.
    by_label = {t['label']: t for t in sites['trees']}
    bzn.objects = [o for o in bzn.objects if not o.label.startswith('cr17_ice')]
    for o in bzn.objects:
        if o.label.startswith('cr17_tree'):
            o.fields['PrjID'].value = by_label[o.label]['odf'].encode()
    seq = max(o.fields.get('seqno', o.fields.get('seqNo')).value for o in bzn.objects) + 1
    bzn.header['seq_count'].value = seq; bzn.header['#objects'].value = len(bzn.objects)
    (ROOT / 'Missions/misn17cr.bzn').write_bytes(write_bzn(bzn, 2016, binary=False, preserve_spelling=False))

    # Keep the reviewed authored trunk pass after a full geometry/site rebuild.
    # The original GLB still supplies tree geometry, UVs, foliage and credits.
    import importlib.util
    art_spec = importlib.util.spec_from_file_location('cr_trunk_art', ROOT / 'Tools/Build-TextureRevamp.py')
    art = importlib.util.module_from_spec(art_spec); art_spec.loader.exec_module(art)
    for name in art.build(foliage_only=True):
        written[name] = check_not_blank(textures / name)
    import collections
    report = {'pack': {k: lic.get(k) for k in ('title', 'author', 'license', 'source')}, 'sha256': consumed,
              'textures': written, 'trunk_art': 'TextureRevamp: generated colour/height masters; original tree geometry and attribution retained.',
              'trees': tree_info, 'ice': ice_info,
              'tree_sites': dict(collections.Counter(t['odf'] for t in trees)),
              'preplaced_trees': sum(t['preplaced'] for t in trees),
              'ice_sites': len(placed), 'ice_slabs': len(ice),
              'ice_placed': dict(collections.Counter(n for n, *_ in ice)),
              'ice_by_water': dict(collections.Counter(w for *_, w in ice)),
              'ice_half_length_m': [round(min(s[5] for s in ice), 1), round(max(s[5] for s in ice), 1)] if ice else [],
              'ice_slab_positions': [s[1:4] for s in ice],
              'rock_layers': len(rocks), 'rocks': sum(len(v) for v in rocks.values()),
              'shore_cells': int(shore.sum())}
    out = ROOT / 'References/Misn17Forest'; out.mkdir(parents=True, exist_ok=True)
    (out / 'source-assets.json').write_text(json.dumps(report, indent=2) + '\n', newline='\n')
    print(json.dumps({k: report[k] for k in ('trees', 'tree_sites', 'ice_sites', 'ice_slabs', 'ice_placed', 'ice_by_water', 'ice_half_length_m', 'rocks', 'rock_layers', 'shore_cells')}, indent=1))


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--pack', type=Path, required=True, help='low_poly_forest_tree_pack.glb')
    ap.add_argument('--isdfc', type=Path, required=True, help='ISDF Chronicles canon tree (read only)')
    a = ap.parse_args(); build(a.pack, a.isdfc)
