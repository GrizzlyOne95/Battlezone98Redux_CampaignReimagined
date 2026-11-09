"""Thruster housings ("nacelle jets") at the points where a hover craft's jet flames emit.

    python Tools/Build-NacelleJets.py [--units avfigh] [--skip-render] [--ship]

Stock hover VDFs carry no flame-emitter part, so the engine hangs one under every nacelle
part (class 67): at the part origin dropped to the bottom of its bounding box, firing along
the part's -Y (BZ 1.5 decompile; see References/NacelleJets/README.md). This tool derives
those points from the unit's VDF, GEOs and skeleton, builds a housing around each one
(Tools/nacellejet_blender.py), paints it in the unit's faction colours and writes a preview
mesh, textures and material under Local/NacelleJets plus review renders under
References/NacelleJets. It always starts from the unit's pre-rig mesh (the weapon-rig
source revision), so it can be re-run at any time.

--ship installs the result as the unit's pre-rig stage: Assets/ModelFixes/<unit>.mesh, the
four textures and the material block. Commit that, pin the commit in
References/WeaponRigs/models.json stage_revisions, then re-run Tools/Build-WeaponRigs.py for
the unit (References/NacelleJets/README.md has the steps).
"""
from pathlib import Path
import argparse, hashlib, io, json, math, os, re, shutil, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT / 'Tools'))
import ogrelayout
import reddevilcockpit as shared
import weaponrigs as wr
from bcdds import save_bc
from bzmodellibs import legacy, legacy_port

om, oms, VES = shared.om, shared.oms, shared.om.VES
BLENDER = Path(os.environ.get('CR_BLENDER') or r'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe')
PAINT, BELL, LIP, GROOVE, BORE, THROAT, VENT = range(7)
SIZE = 512

# Faction dressing that cannot be sampled from the hull texture.
FACTIONS = {'nsdf': dict(stripe=(214, 214, 204), glow=(40, 140, 255))}
# Shape in metres. z runs along the chord from the emit point (+z is the nose), pod depth
# hangs from the measured wing underside, bell/bore/groove heights are from the emit point.
CONFIG = {
    'avfigh': dict(
        faction='nsdf', stripe=(.14, .21),
        shape=dict(
            sides=20, bury=.06, chamfer=.045, flat=.86, smoothAngle=35,
            sections=[(.47, .09, .015), (.37, .21, .07), (.24, .30, .12), (.21, .30, .12), (.14, .30, .12),
                      (-.20, .30, .12), (-.33, .21, .08), (-.44, .08, .015)],
            bell=dict(top=0., lip=-.15, rTop=.25, rLip=.235),
            bore=dict(roof=.03, rRoof=.15, rMouth=.205),
            groove=dict(y0=-.132, y1=-.120, depth=.008, rOut=.28),
            vent=dict(z=[-.13, -.03, .07], drop=.04, halfWidth=.30, depth=.02, height=.03, length=.085))),
}


def unit_vectors(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def emitters(unit, skeleton):
    """Engine flame emit points in Ogre mesh space, one per nacelle part."""
    source = legacy_port.AssetSource(folders=[ROOT / 'Assets/ModelFixes', ROOT / 'Assets/Models'],
                                     archives=[wr.GAME / 'bzone.zfs', wr.GAME / 'tro_cam.zfs'])
    parts = legacy.read_vdf(source(unit + '.vdf')).parts
    assert not any(p.klass == 75 for p in parts), 'unit authors its own flame emitters; house those instead'
    out = []
    for part in parts:
        if part.klass != 67:
            continue
        bone = next(b for b in skeleton.bones if b.name.lower() == part.name.lower())
        pivot, q = wr.flash.bone_world(skeleton, bone.handle)
        assert max(abs(c) for c in q[:3]) < 1e-5, 'a rotated nacelle bind pose is not handled yet'
        drop = float(np.asarray(legacy.read_geo(source(part.name + '.geo')).positions, float)[:, 1].min())
        out.append(dict(part=part.name, bone=bone.handle, pivot=[float(c) for c in pivot],
                        emit=[float(pivot[0]), float(pivot[1]) + drop, float(pivot[2])]))
    assert len(out) == 2 and np.allclose(np.array(out[0]['emit']) * (-1, 1, 1), out[1]['emit'], atol=1e-4), 'expected a mirrored nacelle pair'
    return sorted(out, key=lambda e: -e['emit'][0])  # +X first: the solid is built there


def hull(mesh, bone=None):
    """Triangles (positions, uvs) of the hull submesh: all of it, or those owned by one bone."""
    sub = mesh.submesh_list[0]
    p = shared.values(sub.vertex_data, VES.POSITION).astype(float); uv = shared.values(sub.vertex_data, VES.TEXTURE_COORDINATES).astype(float)
    index = np.array(sub.index_array).reshape(-1, 3); owner = np.full(len(p), -1)
    for a in sub.bone_assignments():
        owner[a.vertex_index] = a.bone_index
    if bone is not None:
        index = index[(owner[index] == bone).all(1)]
    return p[index], uv[index]


def underside(tri, emit, shape):
    """Least-squares height of the wing underside along the chord, over the pod footprint."""
    a, b, c = tri[:, 0], tri[:, 1], tri[:, 2]
    d = (b[:, 2] - c[:, 2]) * (a[:, 0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (a[:, 2] - c[:, 2])
    ok = np.abs(d) > 1e-12; d = np.where(ok, d, 1)
    half = max(s[1] for s in shape['sections']); zs = [s[0] for s in shape['sections']]; rows = []
    for x in np.arange(emit[0] - half, emit[0] + half + 1e-6, .05):
        for z in np.arange(emit[2] + min(zs), emit[2] + max(zs) + 1e-6, .05):
            u = ((b[:, 2] - c[:, 2]) * (x - c[:, 0]) + (c[:, 0] - b[:, 0]) * (z - c[:, 2])) / d
            v = ((c[:, 2] - a[:, 2]) * (x - c[:, 0]) + (a[:, 0] - c[:, 0]) * (z - c[:, 2])) / d
            hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1)
            if hit.any():
                rows.append((z - emit[2], (u * a[:, 1] + v * b[:, 1] + (1 - u - v) * c[:, 1])[hit].min()))
    rows = np.array(rows); A = np.c_[np.ones(len(rows)), rows[:, 0]]
    fit, *_ = np.linalg.lstsq(A, rows[:, 1], rcond=None); error = float(np.abs(rows[:, 1] - A @ fit).max())
    assert error < shape['bury'] * .5, ('wing underside is not flat enough to bury the pod roof', error)
    return [float(fit[0]), float(fit[1])], error


def solid_config(shape, emit, fit):
    """Absolute dimensions for the Blender step and for the face tagging."""
    out = dict(shape, emit=emit, underside=fit)
    for part, keys in (('bell', ('top', 'lip')), ('bore', ('roof',)), ('groove', ('y0', 'y1'))):
        out[part] = dict(shape[part], **{k: emit[1] + shape[part][k] for k in keys})
    bell, groove = out['bell'], out['groove']
    out['groove']['rIn'] = bell_radius(out, (groove['y0'] + groove['y1']) / 2) - groove['depth']
    return out


def bell_radius(cfg, y):
    b = cfg['bell']
    return b['rLip'] + (b['rTop'] - b['rLip']) * (y - b['lip']) / (b['top'] - b['lip'])


def bore_radius(cfg, y):
    return cfg['bore']['rMouth'] + (cfg['bore']['rRoof'] - cfg['bore']['rMouth']) * (y - cfg['bell']['lip']) / (cfg['bore']['roof'] - cfg['bell']['lip'])


def lathe_radius(cfg, p):
    """Circumradius of the N-gon lathe ring a point lies on (plain radius would dip mid-facet)."""
    step = 2 * math.pi / cfg['sides']
    angle = np.arctan2(p[..., 2] - cfg['emit'][2], p[..., 0] - cfg['emit'][0]) % step
    return np.hypot(p[..., 0] - cfg['emit'][0], p[..., 2] - cfg['emit'][2]) * np.cos(angle - step / 2) / math.cos(step / 2)


def tag_faces(tri, cfg):
    """Material zone of every triangle, from where it sits on the construction solids."""
    eps = 2e-3; y = tri[..., 1]; rho = lathe_radius(cfg, tri); centre = tri.mean(1)
    bell, bore, groove, vent = cfg['bell'], cfg['bore'], cfg['groove'], cfg['vent']
    tag = np.full(len(tri), PAINT)
    tag[(np.abs(rho - bell_radius(cfg, y)) < eps).all(1) & (y < bell['top'] + eps).all(1)] = BELL
    tag[(y > groove['y0'] - eps).all(1) & (y < groove['y1'] + eps).all(1) & (rho < bell_radius(cfg, y) + eps).all(1) & (rho > groove['rIn'] - eps).all(1)] = GROOVE
    tag[(np.abs(y - bell['lip']) < eps).all(1)] = LIP
    tag[(rho < bore_radius(cfg, y) + eps).all(1) & (y > bell['lip'] + eps).any(1) & (y < bore['roof'] + eps).all(1)] = BORE
    tag[(np.abs(y - bore['roof']) < eps).all(1) & (rho < bore['rRoof'] + eps).all(1)] = THROAT
    for z in vent['z']:
        zc = cfg['emit'][2] + z; yc = cfg['underside'][0] + cfg['underside'][1] * z - vent['drop']; side = np.abs(centre[:, 0] - cfg['emit'][0])
        tag[(np.abs(centre[:, 2] - zc) < vent['length'] / 2 + eps) & (np.abs(centre[:, 1] - yc) < vent['height'] / 2 + eps)
            & (side < vent['halfWidth'] - eps / 2) & (side > vent['halfWidth'] - vent['depth'] - eps)] = VENT
    for name, value in (('bell', BELL), ('lip', LIP), ('groove', GROOVE), ('bore', BORE), ('throat', THROAT), ('vent', VENT)):
        assert (tag == value).any(), name + ' zone is missing from the solid'
    return tag


def raster(uv):
    """Per texel: the covering triangle (-1 where empty) and its barycentric weights."""
    face = np.full((SIZE, SIZE), -1); weight = np.zeros((SIZE, SIZE, 3))
    for f, t in enumerate(uv * SIZE):
        x0, y0 = np.floor(t.min(0)).astype(int).clip(0); x1, y1 = np.ceil(t.max(0)).astype(int).clip(None, SIZE)
        d = (t[1, 1] - t[2, 1]) * (t[0, 0] - t[2, 0]) + (t[2, 0] - t[1, 0]) * (t[0, 1] - t[2, 1])
        if abs(d) < 1e-12 or x0 >= x1 or y0 >= y1:
            continue
        X, Y = np.meshgrid(np.arange(x0, x1) + .5, np.arange(y0, y1) + .5)
        a = ((t[1, 1] - t[2, 1]) * (X - t[2, 0]) + (t[2, 0] - t[1, 0]) * (Y - t[2, 1])) / d
        b = ((t[2, 1] - t[0, 1]) * (X - t[2, 0]) + (t[0, 0] - t[2, 0]) * (Y - t[2, 1])) / d
        inside = (a >= 0) & (b >= 0) & (a + b <= 1)
        face[y0:y1, x0:x1][inside] = f; weight[y0:y1, x0:x1][inside] = np.dstack([a, b, 1 - a - b])[inside]
    return face, weight


def mesh_edges(tri, tag, crease):
    """Creases and zone borders of the solid itself: (face, corner, convex, border) per side."""
    ids = {}; vid = np.array([[ids.setdefault(tuple(p), len(ids)) for p in t] for t in np.round(tri, 5)])
    normal = unit_vectors(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])); centre = tri.mean(1); users = {}
    for f, v in enumerate(vid):
        for i in range(3):
            users.setdefault((min(v[i], v[(i + 1) % 3]), max(v[i], v[(i + 1) % 3])), []).append((f, i))
    out = []
    for pair in users.values():
        if len(pair) != 2:
            continue
        (f, i), (g, j) = pair; border = tag[f] != tag[g]
        if border or normal[f] @ normal[g] < math.cos(math.radians(crease)):
            convex = normal[f] @ (centre[g] - centre[f]) < 0
            out += [(f, i, convex, border), (g, j, convex, border)]
    return out


def blurred(mask, radius):
    return np.asarray(Image.fromarray(np.uint8(np.clip(mask, 0, 1) * 255)).filter(ImageFilter.GaussianBlur(radius)), float) / 255


def paint_colour(mesh):
    """Faction hull paint: the median chromatic texel of the unit's hull."""
    tri, uv = hull(mesh); path = texture_path(mesh.submesh_list[0].material_name)
    image = np.asarray(Image.open(path).convert('RGB'), float); h, w = image.shape[:2]
    weights = np.random.default_rng(1).dirichlet((1, 1, 1), (len(uv), 8))
    sample = (weights[..., None] * uv[:, None]).sum(2).reshape(-1, 2) % 1
    texel = image[(sample[:, 1] * h).astype(int).clip(0, h - 1), (sample[:, 0] * w).astype(int).clip(0, w - 1)]
    chroma = texel.max(1) - texel.min(1); texel = texel[(chroma > 15) & (texel.max(1) < 200)]
    assert len(texel) > 200, 'could not find painted texels on the hull'
    return [float(c) for c in np.median(texel, 0)], path


def texture_path(material):
    """Diffuse texture file of a material in this mod, or None."""
    for path in sorted((ROOT / 'Materials').glob('*.material')):
        block = re.search(r'^material\s+' + re.escape(material) + r'\s*:[^{]*\{(.*?)^\}', path.read_text(errors='ignore'), re.S | re.M)
        if block:
            name = re.search(r'set_texture_alias\s+DiffuseMap\s+(\S+)', block.group(1))
            for folder in (ROOT / 'Assets/Textures', wr.GAME / 'BZ_ASSETS/pc/textures/DIFF'):
                if name and (folder / name.group(1)).is_file():
                    return folder / name.group(1)
    return None


def textures(unit, tri, uv, tag, cfg, stripe, paint, faction):
    """Diffuse, normal, specular and emissive images. Every line follows one of the solid's
    own creases or zone borders; colour ramps use the lathe and loft parameters."""
    face, weight = raster(uv); filled = face >= 0; f = np.where(filled, face, 0)
    p = (weight[..., None] * tri[f]).sum(2); zone = np.where(filled, tag[f], -1)
    emit = cfg['emit']; bell, bore = cfg['bell'], cfg['bore']
    relz = p[..., 2] - emit[2]; y = p[..., 1]; drop = cfg['underside'][0] + cfg['underside'][1] * relz - y
    rng = np.random.default_rng(int(hashlib.sha256(unit.encode()).hexdigest()[:8], 16))
    mottle = blurred(rng.random((SIZE, SIZE)), 5); mottle = (mottle - mottle.mean()) / mottle.std()
    blotch = blurred(rng.random((SIZE, SIZE)), 14); blotch = (blotch - blotch.mean()) / blotch.std()
    grain = rng.normal(0, 1, (SIZE, SIZE))

    scale = 4; seam = Image.new('L', (SIZE * scale,) * 2); wear = Image.new('L', (SIZE * scale,) * 2); rivet = Image.new('L', (SIZE * scale,) * 2)
    for fi, corner, convex, border in mesh_edges(tri, tag, cfg['smoothAngle']):
        a, b, c = (uv[fi][(corner + k) % 3] * SIZE * scale for k in range(3))
        if border or not convex:
            ImageDraw.Draw(seam).line([tuple(a), tuple(b)], fill=255, width=int(2.2 * scale))
        if convex and tag[fi] not in (BORE, THROAT, VENT, GROOVE):
            ImageDraw.Draw(wear).line([tuple(a), tuple(b)], fill=255, width=int(2.6 * scale))
        # Rivet row just inside every long crease of a painted panel.
        pa, pb, pc = (tri[fi][(corner + k) % 3] for k in range(3)); length = np.linalg.norm(pb - pa)
        height = np.linalg.norm(np.cross(pb - pa, pc - pa)) / max(length, 1e-9)
        if tag[fi] == PAINT and convex and not border and length > .1 and height > .04:
            inset = .016 / height
            for s in (np.arange(.5, int(length / .05)) + .0) / int(length / .05):
                q = (a * (1 - s) + b * s) * (1 - inset) + c * inset; r = 1.5 * scale
                ImageDraw.Draw(rivet).ellipse([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=255)
    down = lambda image: np.asarray(image.resize((SIZE, SIZE), Image.LANCZOS), float) / 255
    seam, wear, rivet = down(seam), down(wear), down(rivet)
    grime = blurred(seam, 5); chipped = np.clip(blurred(wear, 1.2) * (1.1 + .9 * mottle) - .25, 0, 1)

    paint = np.array(paint); bare = np.array((148., 150, 146)); glow = np.array(faction['glow'], float)
    colour = np.zeros((SIZE, SIZE, 3)); spec = np.zeros((SIZE, SIZE)); emissive = np.zeros((SIZE, SIZE, 3))
    body = paint * (1 + .07 * blotch[..., None] + .04 * mottle[..., None])
    band = (relz >= stripe[0]) & (relz <= stripe[1])
    body = np.where((band & (blotch + mottle < 1.4))[..., None], np.array(faction['stripe'], float) * (1 + .05 * mottle[..., None]), body)
    body *= (.55 + .45 * np.clip(drop / .035, 0, 1))[..., None]  # contact shadow under the wing skin
    t = np.clip((y - bell['lip']) / (bell['top'] - bell['lip']), 0, 1)[..., None]  # 0 at the lip
    heat = np.clip(1 - t / .65, 0, 1) ** 1.5
    metal = (np.array((60., 63, 68)) * (1 - heat) + np.array((104., 78, 58)) * heat) * (1 + .06 * mottle[..., None])
    depth = np.clip((y - bell['lip']) / (bore['roof'] - bell['lip']), 0, 1)[..., None]  # 1 at the bore roof
    core = np.clip(1 - (lathe_radius(cfg, p) / bore['rRoof']) ** 2 * .7, 0, 1)[..., None]
    hot = np.array((255., 150, 60))
    for value, base, shine in ((PAINT, body, 46 + 14 * band), (BELL, metal, 120), (LIP, np.array((118., 114, 106)) * (1 + .08 * mottle[..., None]), 160),
                               (GROOVE, glow * .45, 40), (BORE, np.array((26., 24, 24)) * (1 - depth) + np.array((84., 44, 24)) * depth, 22),
                               (THROAT, np.array((110., 58, 30)) * core, 30), (VENT, np.array((15., 16, 18)) + 0 * body, 10)):
        mask = zone == value; colour[mask] = np.broadcast_to(base, colour.shape)[mask]; spec[mask] = np.broadcast_to(shine, spec.shape)[mask]
    emissive[zone == GROOVE] = glow * .95
    emissive[zone == BORE] = (hot * .45 * depth ** 2.5)[zone == BORE]
    emissive[zone == THROAT] = (hot * (.35 + .65 * core))[zone == THROAT]
    worn = (chipped * np.isin(zone, (PAINT, BELL, LIP)))[..., None]
    colour = colour * (1 - worn) + np.where((zone == PAINT)[..., None], bare, colour * 1.7) * worn
    lit = (zone == GROOVE) | (zone == THROAT)
    colour *= np.where(lit, 1, (1 - .5 * grime) * (1 - .7 * seam))[..., None]
    colour *= (1 - .35 * rivet[..., None]) * (1 + .03 * grain[..., None])
    spec = (spec + 90 * worn[..., 0]) * np.where(lit, 1, 1 - .6 * seam)
    height = blurred(rivet, .8) * .7 - blurred(seam, .9)
    gy, gx = np.gradient(height); n = unit_vectors(np.dstack([-gx * 3.5, -gy * 3.5, np.ones_like(gx)]))  # +v (image down) is the shader's binormal
    images = dict(D=colour, N=(n * .5 + .5) * 255, S=np.repeat(spec[..., None], 3, 2), E=emissive)
    return {k: Image.fromarray(np.uint8(np.clip(padded(v, filled), 0, 255))) for k, v in images.items()}, zone


def padded(image, filled, passes=8):
    """Bleed chart colours into the gutters so lower mips do not pick up black."""
    image = image.copy(); filled = filled.copy()
    for _ in range(passes):
        total = np.zeros_like(image); count = np.zeros(filled.shape)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            total += np.roll(image * filled[..., None], (dy, dx), (0, 1)); count += np.roll(filled, (dy, dx), (0, 1))
        grow = ~filled & (count > 0); image[grow] = total[grow] / count[grow][:, None]; filled |= grow
    return image


def vertex_rows(tri, normal, uv):
    """Welded [position normal uv tangent] rows and triangle indices for one housing."""
    corners = np.column_stack([tri.reshape(-1, 3), normal.reshape(-1, 3), uv.reshape(-1, 2)])
    data, index = np.unique(np.round(corners, 6), axis=0, return_inverse=True); index = index.reshape(-1, 3)
    tangent = np.zeros((len(data), 3))
    for face in index:
        p = data[face, :3]; t = data[face, 6:8]; a, b = t[1] - t[0], t[2] - t[0]; det = a[0] * b[1] - b[0] * a[1]
        if abs(det) > 1e-12:
            tangent[face] += ((p[1] - p[0]) * b[1] - (p[2] - p[0]) * a[1]) / det
    tangent -= data[:, 3:6] * (tangent * data[:, 3:6]).sum(1)[:, None]
    # Boolean slivers can have zero UV area; their corners take any direction in the surface.
    lost = np.linalg.norm(tangent, axis=1) < 1e-9; n = data[lost, 3:6]
    spare = np.cross(n, np.where((np.abs(n[:, 1:2]) < .9), (0., 1, 0), (1., 0, 0)))
    tangent[lost] = spare; assert lost.mean() < .05, ('too many housing vertices without a tangent', int(lost.sum()))
    return np.column_stack([data, unit_vectors(tangent)]), index


def stage_base(unit, work):
    """The unit's mesh and skeleton before the weapon rig and before any housing."""
    key = f'Assets/ModelFixes/{unit}.mesh'
    revision = json.loads((ROOT / 'References/WeaponRigs/models.json').read_text())['source_revision']
    proc = subprocess.run(['git', 'show', f'{revision}:{key}'], cwd=ROOT, capture_output=True)
    assert proc.returncode == 0, (key, 'is not in the weapon-rig source revision', revision)
    (work / 'base.mesh').write_bytes(proc.stdout); mesh = shared.read_mesh(work / 'base.mesh')
    assert not any(s.material_name == unit + '_nacjet' for s in mesh.submesh_list), 'the base stage already carries a housing'
    folders = (ROOT / 'Assets/ModelFixes', ROOT / 'Assets/Models', wr.GAME / 'BZ_ASSETS/common/models')
    skeleton = next(f / mesh.skeleton_name for f in folders if (f / mesh.skeleton_name).is_file())
    return mesh, wr.read_skeleton(skeleton), revision


def material_block(material):
    lines = [f'material {material} : CR_BZBase', '{']
    lines += [f'\tset_texture_alias {alias} {material}_{key}.dds' for alias, key in (('DiffuseMap', 'D'), ('NormalMap', 'N'), ('SpecularMap', 'S'), ('EmissiveMap', 'E'))]
    return lines + ['', '\tset $diffuse "1 1 1"', '\tset $ambient "1 1 1"', '\tset $specular ".7 .7 .7"', '\tset $shininess "127"', '\tset $glow "1 1 1"', '}', '']


def ship(unit, material, work):
    """Install the housing as the unit's pre-rig stage: mesh, textures and material block."""
    raw = (work / (unit + '.mesh')).read_bytes()
    assert not ogrelayout.mixed_skinned_submeshes(raw), 'the stage mesh must keep the stock two-stream layout'
    (ROOT / 'Assets/ModelFixes' / (unit + '.mesh')).write_bytes(raw)
    for key in 'DNSE':
        shutil.copyfile(work / f'{material}_{key}.dds', ROOT / 'Assets/Textures' / f'{material}_{key}.dds')
    path = ROOT / 'Materials' / (unit + '.material'); text = path.read_bytes().decode()
    block = '\r\n'.join(material_block(material))
    old = re.compile(r'^material[ \t]+' + re.escape(material) + r'[ \t]*:.*?^\}\r?\n', re.S | re.M)
    text = old.sub(lambda m: block, text) if old.search(text) else text.rstrip() + '\r\n\r\n\r\n' + block
    path.write_bytes(text.encode())
    return hashlib.sha256(raw).hexdigest()


def preview_mesh(mesh, material, rows, index, bones, dest):
    """Append both housings to the unit mesh as one submesh, each rigid on its nacelle bone."""
    mirror = rows * np.array([-1, 1, 1, -1, 1, 1, 1, 1, -1, 1, 1])
    data = np.concatenate([rows, mirror]).astype('<f4'); faces = np.concatenate([index, index[:, ::-1] + len(rows)])
    owner = np.repeat(bones, len(rows)); assert len(data) < 65536
    before = [(s.material_name, s.vertex_data.vertex_count) for s in mesh.submesh_list]
    sub = mesh.create_submesh(); sub.material_name = material; sub.index_count = faces.size; sub.indices_32_bit = False
    sub.set_index_buffer(faces.astype('<u2').tobytes()); ogrelayout.fill_vertex_data(sub.create_vertex_data(len(data)), data)
    for i, bone in enumerate(owner):
        sub.create_bone_assignment(i, int(bone), 1.)
    out = io.BytesIO(); oms.MeshSerializer(out).write(mesh); dest.write_bytes(out.getvalue())
    check = shared.read_mesh(dest); new = check.submesh_list[-1]
    assert [(s.material_name, s.vertex_data.vertex_count) for s in check.submesh_list] == before + [(material, len(data))]
    assert sorted((a.vertex_index, a.bone_index) for a in new.bone_assignments()) == list(zip(range(len(data)), owner.tolist()))
    assert np.allclose(shared.values(new.vertex_data, VES.POSITION), data[:, :3])
    return data, faces


def blender(script, *args):
    result = subprocess.run([str(BLENDER), '-b', '--factory-startup', '--python-exit-code', '1', '--python', str(ROOT / 'Tools' / script), '--', *map(str, args)],
                            capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(result.stdout[-3000:] + result.stderr[-3000:])
    return result.stdout


def sheet(images, captions, dest, columns):
    """Captioned contact sheet of same-sized images."""
    font = ImageFont.truetype('arial.ttf', 20); w, h = images[0].size; rows = -(-len(images) // columns)
    out = Image.new('RGB', (w * columns, (h + 34) * rows), (24, 26, 28))
    for i, (image, caption) in enumerate(zip(images, captions)):
        x, y = i % columns * w, i // columns * (h + 34)
        out.paste(image.convert('RGB').resize((w, h)), (x, y)); ImageDraw.Draw(out).text((x + 8, y + h + 5), caption, fill=(232, 232, 226), font=font)
    out.save(dest, quality=90)


def build(unit, render, shipped=False):
    cfg = CONFIG[unit]; faction = FACTIONS[cfg['faction']]; material = unit + '_nacjet'
    work = ROOT / 'Local/NacelleJets' / unit; review = ROOT / 'References/NacelleJets/review'
    work.mkdir(parents=True, exist_ok=True); review.mkdir(parents=True, exist_ok=True)
    mesh, skeleton, revision = stage_base(unit, work)
    jets = emitters(unit, skeleton); emit = jets[0]['emit']
    fit, error = underside(hull(mesh, jets[0]['bone'])[0], emit, cfg['shape'])
    solid = solid_config(cfg['shape'], emit, fit); (work / 'solid.json').write_text(json.dumps(solid, indent=1))
    log = blender('nacellejet_blender.py', work / 'solid.json', work / 'solid.npz')
    print(''.join(line + '\n' for line in log.splitlines() if line.startswith(('boolean', 'nacelle'))), end='')
    data = np.load(work / 'solid.npz'); tris = data['tris']
    tri = data['positions'][tris]; normal = data['normals'][tris]; uv = data['uvs'][tris] * (1, -1) + (0, 1)  # Ogre v runs down
    tag = tag_faces(tri, solid); paint, source = paint_colour(mesh)
    images, zone = textures(unit, tri, uv, tag, solid, cfg['stripe'], paint, faction)
    for key, image in images.items():
        save_bc(image, work / f'{material}_{key}.dds'); image.save(work / f'{material}_{key}.png')
    (work / (material + '.material')).write_text('\n'.join(['import * from "CR_BZBase.material"', ''] + material_block(material)), newline='\n')
    rows, index = vertex_rows(tri, normal, uv)
    vertices, faces = preview_mesh(mesh, material, rows, index, [j['bone'] for j in jets], work / (unit + '.mesh'))
    stage = ship(unit, material, work) if shipped else None
    receipt = dict(unit=unit, faction=cfg['faction'], material=material, emitters=jets, flameDirection=[0, -1, 0], baseRevision=revision,
                   wingUnderside=dict(heightAtEmit=fit[0], slopePerMetreOfChord=fit[1], maxError=error), paint=paint,
                   paintSource=str(source.relative_to(ROOT) if source.is_relative_to(ROOT) else source.name),
                   housing=dict(vertices=len(rows), triangles=len(index), zones={n: int((tag == v).sum()) for n, v in
                                (('paint', PAINT), ('bell', BELL), ('lip', LIP), ('groove', GROOVE), ('bore', BORE), ('throat', THROAT), ('vent', VENT))}),
                   shape=cfg['shape'], stripe=cfg['stripe'])
    record = ROOT / 'References/NacelleJets' / unit / 'build.json'
    # sha256 of the pre-rig Assets/ModelFixes mesh as shipped; a preview run keeps the last shipped value.
    stage = stage or (json.loads(record.read_text()).get('stageMesh') if record.exists() else None)
    if stage:
        receipt['stageMesh'] = stage
    (ROOT / 'References/NacelleJets' / unit).mkdir(exist_ok=True)
    (ROOT / 'References/NacelleJets' / unit / 'build.json').write_text(json.dumps(receipt, indent=2) + '\n', newline='\n')
    print(unit, 'housing', len(rows), 'vertices', len(index), 'triangles each; paint', [round(c) for c in paint], 'underside fit error %.3f' % error)
    if not render:
        return
    # Hand the renderer plain arrays: it only draws.
    parts = []
    for i, sub in enumerate(shared.read_mesh(work / (unit + '.mesh')).submesh_list):
        if 'glass' in sub.material_name.lower():
            continue
        vd = sub.vertex_data; name = work / f'part{i}.npz'; own = sub.material_name == material
        np.savez(name, positions=shared.values(vd, VES.POSITION), normals=shared.values(vd, VES.NORMAL),
                 uvs=shared.values(vd, VES.TEXTURE_COORDINATES), tris=np.array(sub.index_array).reshape(-1, 3))
        texture = None if own else texture_path(sub.material_name)
        if texture:
            Image.open(texture).convert('RGB').save(work / f'part{i}_D.png'); texture = work / f'part{i}_D.png'
        parts.append(dict(mesh=str(name), housing=own, diffuse=str(work / f'{material}_D.png') if own else texture and str(texture),
                          emissive=str(work / f'{material}_E.png') if own else None, normal=str(work / f'{material}_N.png') if own else None))
    e = np.array(emit); close = [('below', e + (1., -1.1, -1.2)), ('outboard', e + (1.9, -.36, .45)), ('front', e + (.3, -.65, 1.75))]
    views = [dict(file='emit-below', eye=[0, -8, emit[2]], target=[0, emit[1], emit[2]], ortho=3.4, marker=True, flame=False, housing=True),
             dict(file='flame-before', eye=list(e + (1.9, -.75, -2.3)), target=list(e + (0, -.25, 0)), fov=38, marker=True, flame=True, housing=False),
             dict(file='flame-after', eye=list(e + (1.9, -.75, -2.3)), target=list(e + (0, -.25, 0)), fov=38, marker=True, flame=True, housing=True),
             dict(file='craft', eye=[3.6, -1.1, -5.6], target=[0, .7, -1.2], fov=38, marker=False, flame=True, housing=True)]
    views += [dict(file='clay-' + n, eye=list(eye), target=list(e + (0, -.02, 0)), fov=32, marker=False, flame=False, housing=True, clay=True) for n, eye in close]
    views += [dict(file='paint-' + n, eye=list(eye), target=list(e + (0, -.02, 0)), fov=32, marker=False, flame=False, housing=True) for n, eye in close]
    (work / 'scene.json').write_text(json.dumps(dict(parts=parts, out=str(work), emit=[j['emit'] for j in jets], views=views,
                                                     flame=dict(halfWidth=.2, length=.9), size=[960, 600]), indent=1))
    blender('nacellejet_render.py', work / 'scene.json')
    shot = lambda name: Image.open(work / (name + '.png'))
    where = 'emit (%.3f, %.3f, %.3f) and its mirror' % tuple(emit)
    sheet([shot('emit-below'), shot('flame-before'), shot('flame-after'), shot('craft')],
          ['From below: magenta dot = engine flame emit point, ' + where, 'Stock wing: the jet starts on bare skin (cone = flame at full throttle)',
           'With the housing: the same emit point now sits in the nozzle bore', 'Both housings, flame cones drawn (length illustrative)'], review / f'{unit}-emit.jpg', 2)
    sheet([shot('clay-' + n) for n, _ in close], ['Mesh from below', 'Mesh from outboard', 'Mesh from the nose side'], review / f'{unit}-mesh.jpg', 3)
    sheet([shot('paint-' + n) for n, _ in close], ['Textured, from below', 'Textured, from outboard', 'Textured, from the nose side'], review / f'{unit}-textured.jpg', 3)
    sheet([images[k].resize((480, 480)) for k in 'DNSE'], [f'{material}_D diffuse', f'{material}_N normal', f'{material}_S specular', f'{material}_E emissive'],
          review / f'{unit}-textures.jpg', 4)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--units', nargs='*', default=list(CONFIG)); parser.add_argument('--skip-render', action='store_true')
    parser.add_argument('--ship', action='store_true', help='install the housing as the pre-rig stage (mesh, textures, material)')
    options = parser.parse_args()
    for unit in options.units:
        build(unit, not options.skip_render, options.ship)
