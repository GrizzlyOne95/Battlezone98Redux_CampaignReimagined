"""Build CR's two ejected-casing meshes, textures and material.

cr_casing_cannon: a rimmed, straight-tapered tank-gun case after the 105 mm
M68 brass case (M150: 617 mm long, 147 mm rim, ~134 mm base body tapering to
~112 mm at the mouth). Used by stabbers and other large/medium rounds.

cr_casing_bullet: a rimless, bottlenecked rifle/MG case after the .50 BMG
(12.7x99: 99 mm long, 20.4 mm base, shoulder at ~77%, 14.2 mm neck). Used by
miniguns, chainguns and the sniper rifle.

OpenShim contract (Docs/SHELL_CASING_WEAPON_PRESENTATION.md): one rigid case,
unit length along local +Z, base at Z=-0.5, mouth at Z=+0.5; casingType
scales the whole mesh uniformly. Each mesh is a revolved closed profile
(axis -> base -> outer wall -> lip -> inner wall -> inner floor -> axis), so
it is watertight with a hollow mouth and an inset primer.

Meshes are written through the Battlezone98_Modding_Toolbox serializer.
"""
from pathlib import Path
import argparse
import math
import os
import struct
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
TOOLBOX = Path(os.environ.get('BZ_TOOLBOX_DIR') or os.environ.get('BZ_TOOLBOX')
               or Path.home()/'Documents/GIT/Battlezone98_Modding_Toolbox')
sys.path.insert(0, str(TOOLBOX))
from battlezone.meshes.ogre import (  # noqa: E402
    Geometry, OgreMesh, SubMesh, VertexBuffer, VertexElement, read_mesh, write_mesh)

SIDES = 16
# Texture atlas V bands (u wraps the circumference).
V_BODY = (0.02, 0.48)   # base end -> mouth end
V_RIM = (0.54, 0.68)
V_INNER = (0.72, 0.74)
V_HEAD = (0.78, 0.86)   # base face (headstamp ring)
V_PRIMER = (0.90, 0.99)  # primer disc, centre -> edge

# Profiles: (r, z, v). z runs -0.5 (base) .. +0.5 (mouth); r is the radius
# for unit length. Consecutive points form one revolved band.
CANNON = [
    (0.000, -0.496, V_PRIMER[0]), (0.030, -0.496, V_PRIMER[1]),   # primer, inset
    (0.034, -0.500, V_HEAD[0]), (0.119, -0.500, V_HEAD[1]),       # base face
    (0.121, -0.497, V_RIM[0]), (0.121, -0.478, V_RIM[0]+0.04),    # rim
    (0.113, -0.474, V_RIM[0]+0.07), (0.109, -0.462, V_RIM[1]),    # rim fillet
    (0.109, -0.460, V_BODY[0]), (0.092, 0.488, V_BODY[1]),        # tapered body
    (0.090, 0.500, V_BODY[1]),                                    # mouth chamfer
    (0.082, 0.500, V_INNER[0]),                                   # lip
    (0.084, 0.440, V_INNER[1]), (0.098, -0.420, V_INNER[1]),      # inner wall
    (0.000, -0.430, V_INNER[1]),                                  # inner floor
]
BULLET = [
    (0.000, -0.496, V_PRIMER[0]), (0.040, -0.496, V_PRIMER[1]),
    (0.045, -0.500, V_HEAD[0]), (0.096, -0.500, V_HEAD[1]),
    (0.103, -0.493, V_RIM[0]), (0.103, -0.462, V_RIM[0]+0.03),    # rimless head
    (0.083, -0.447, V_RIM[0]+0.07), (0.083, -0.420, V_RIM[0]+0.10),  # extractor groove
    (0.101, -0.400, V_RIM[1]),                                    # groove bevel
    (0.101, -0.398, V_BODY[0]), (0.094, 0.270, 0.37),             # body
    (0.072, 0.335, 0.41),                                         # shoulder
    (0.071, 0.500, V_BODY[1]),                                    # neck
    (0.058, 0.500, V_INNER[0]),
    (0.058, 0.300, V_INNER[1]), (0.086, 0.240, V_INNER[1]), (0.086, -0.360, V_INNER[1]),
    (0.000, -0.370, V_INNER[1]),
]
CASES = {
    'cannon': dict(profile=CANNON, material='CR_Casing_Cannon_Brass',
                   brass=(0.70, 0.52, 0.27), shine=0.55, soot=0.55),
    'bullet': dict(profile=BULLET, material='CR_Casing_Bullet_Brass',
                   brass=(0.82, 0.63, 0.32), shine=0.75, soot=0.35),
}


def lathe(profile):
    """Vertices (pos, normal, uv) and CCW-outward triangles for a revolved profile."""
    verts, tris = [], []
    for (r0, z0, v0), (r1, z1, v1) in zip(profile, profile[1:]):
        dr, dz = r1-r0, z1-z0
        length = math.hypot(dr, dz)
        nr, nz = dz/length, -dr/length          # outward for this traversal order
        base = len(verts)
        for j in range(SIDES+1):
            a = 2*math.pi*j/SIDES
            c, s = math.cos(a), math.sin(a)
            for r, z, v in ((r0, z0, v0), (r1, z1, v1)):
                verts.append(((r*c, r*s, z), (nr*c, nr*s, nz), (j/SIDES, v)))
        for j in range(SIDES):
            p00, p01 = base+2*j, base+2*j+1
            p10, p11 = base+2*(j+1), base+2*(j+1)+1
            for tri in ((p00, p10, p11), (p00, p11, p01)):
                a, b, c = (np.array(verts[k][0]) for k in tri)
                n = np.cross(b-a, c-a)
                if np.linalg.norm(n) < 1e-9:
                    continue                    # pole of a disc band
                want = np.array(verts[tri[0]][1]) + np.array(verts[tri[2]][1])
                tris.append(tri if np.dot(n, want) > 0 else (tri[0], tri[2], tri[1]))
    return verts, tris


def check_closed(verts, tris):
    """Watertight and consistently oriented, welding seam/hard-edge duplicates."""
    key = {}
    weld = [key.setdefault(tuple(round(x, 6) for x in v[0]), len(key)) for v in verts]
    edges = {}
    for a, b, c in tris:
        for e in ((a, b), (b, c), (c, a)):
            u, w = weld[e[0]], weld[e[1]]
            if u != w:
                edges[(u, w)] = edges.get((u, w), 0)+1
    bad = [e for e, n in edges.items() if n != 1 or edges.get((e[1], e[0])) != 1]
    assert not bad, f'not a closed oriented surface: {len(bad)} bad edges'


def build_mesh(name, case):
    verts, tris = lathe(case['profile'])
    check_closed(verts, tris)
    data = b''.join(struct.pack('<8f', *p, *n, *uv) for p, n, uv in verts)
    geometry = Geometry(len(verts), [VertexElement(0, 2, 1, 0, 0), VertexElement(0, 2, 4, 12, 0),
                                      VertexElement(0, 1, 7, 24, 0)], {0: VertexBuffer(0, 32, data, 0)})
    sub = SubMesh(case['material'], False, [i for t in tris for i in t], False, 4, geometry)
    mesh = OgreMesh('[MeshSerializer_v1.8]', '<', submeshes=[sub])
    path = ROOT/'Assets/Models'/f'cr_casing_{name}.mesh'
    data = write_mesh(mesh)
    back = read_mesh(data)
    assert len(back.submeshes) == 1 and back.submeshes[0].geometry.vertex_count == len(verts)
    lo, hi = back.bounds[2], back.bounds[5]
    assert abs(lo+0.5) < 1e-4 and abs(hi-0.5) < 1e-4, back.bounds
    return path, data, len(tris)


def textures(case, seed):
    """256x128 diffuse/specular atlas; detail runs in the case's own (u, v) frame."""
    w, h = 256, 128
    rng = np.random.default_rng(seed)
    u = (np.arange(w)+0.5)/w
    v = (np.arange(h)+0.5)/h
    V = np.repeat(v[:, None], w, 1)
    brass = np.ones((h, w, 3))*np.array(case['brass'])
    # Longitudinal brushing: streaks that run along the case length.
    streak = np.repeat(rng.normal(0, 1, w)[None, :], h, 0)
    streak = np.convolve(streak[0], np.ones(3)/3, 'same')[None, :].repeat(h, 0)
    light = 1+0.05*streak+0.02*rng.normal(0, 1, (h, w))
    body = (V >= V_BODY[0]-0.02) & (V <= V_BODY[1]+0.02)
    t = np.clip((V-V_BODY[0])/(V_BODY[1]-V_BODY[0]), 0, 1)
    # Annealed neck/mouth: warmer, slightly darker band, then firing soot.
    anneal = np.exp(-((t-0.80)/0.10)**2)*body
    soot = np.clip((t-0.86)/0.14, 0, 1)**1.5*body*case['soot']
    colour = brass*light[..., None]
    colour *= (1-0.18*anneal)[..., None]*np.array([1.0, 0.92, 0.85])**anneal[..., None]
    colour *= (1-0.75*soot)[..., None]
    spec = np.full((h, w), case['shine'])*light*(1-0.8*soot)
    # Rim: machined rings and a darker extractor groove.
    rim = (V >= V_RIM[0]) & (V <= V_RIM[1])
    rings = 0.92+0.08*np.sin(V*h*2.6)
    colour[rim] *= rings[rim][:, None]
    spec[rim] = case['shine']*1.1*rings[rim]
    inner = (V > V_RIM[1]) & (V < V_HEAD[0])
    colour[inner] = np.array([0.12, 0.10, 0.08])
    spec[inner] = 0.05
    # Base face: plain brass with a stamped headstamp ring.
    head = (V >= V_HEAD[0]) & (V <= V_HEAD[1])
    th = np.clip((V-V_HEAD[0])/(V_HEAD[1]-V_HEAD[0]), 0, 1)
    stamp = np.exp(-((th-0.55)/0.08)**2)*(0.5+0.5*(np.sin(np.repeat(u[None, :], h, 0)*2*math.pi*9) > 0.2))
    colour[head] *= (1-0.35*stamp[head])[:, None]
    # Primer: paler cup with a dark struck firing-pin dimple at the centre.
    primer = V >= V_HEAD[1]+0.02
    tp = np.clip((V-V_PRIMER[0])/(V_PRIMER[1]-V_PRIMER[0]), 0, 1)
    pin = np.exp(-(tp/0.25)**2)
    colour[primer] = (np.array([0.80, 0.72, 0.58])*(1-0.65*pin[primer])[:, None])
    spec[primer] = 0.6*(1-0.6*pin[primer])
    d = Image.fromarray((np.clip(colour, 0, 1)*255).astype(np.uint8), 'RGB')
    s = Image.fromarray((np.clip(spec, 0, 1)*255).astype(np.uint8), 'L').convert('RGB')
    return d, s


MATERIAL_HEADER = '// Generated by Tools/Weapons/Build-CasingMeshes.py -- do not edit.\n'


def material_text():
    out = [MATERIAL_HEADER, 'import * from "CR_BZBase.material"\n']
    for name, case in CASES.items():
        out.append(f'''
material {case['material']} : CR_BZBase
{{
\tset_texture_alias DiffuseMap cr_casing_{name}_d.png
\tset_texture_alias SpecularMap cr_casing_{name}_s.png
\tset $diffuse "1 1 1"
\tset $ambient "1 1 1"
\tset $specular "1 1 1"
\tset $shininess "64"
\tset $glow "0 0 0"
}}
''')
    return ''.join(out)


def outputs():
    files = {}
    for i, (name, case) in enumerate(CASES.items()):
        path, data, _ = build_mesh(name, case)
        files[path] = data
        d, s = textures(case, 9100+i)
        for suffix, image in (('d', d), ('s', s)):
            files[ROOT/'Assets/Textures'/f'cr_casing_{name}_{suffix}.png'] = image
    files[ROOT/'Materials/cr_casings.material'] = material_text().encode()
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--check', action='store_true', help='verify committed outputs match')
    args = parser.parse_args()
    for path, data in outputs().items():
        if isinstance(data, Image.Image):
            if args.check:
                # Textures come from seeded float noise; numpy/PIL builds may
                # round differently, so allow a 2-level drift. Meshes stay exact.
                have = np.asarray(Image.open(path).convert('RGB'), dtype=np.int16)
                want = np.asarray(data.convert('RGB'), dtype=np.int16)
                assert have.shape == want.shape and np.abs(have - want).max() <= 2, \
                    f'{path.name} differs; regenerate'
            else:
                data.save(path, optimize=True)
        elif args.check:
            assert path.read_bytes() == data, f'{path.name} differs; regenerate'
        else:
            path.write_bytes(data)
    print(f'Casing meshes: {len(CASES)} cases {"checked" if args.check else "written"}')


if __name__ == '__main__':
    main()
