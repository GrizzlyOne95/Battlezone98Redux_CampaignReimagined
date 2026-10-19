"""Geometry/UV kit for BZ capital ships (run inside Blender).

Conventions (match bz98tools import of stock Redux meshes):
  Blender -Y = ship forward, +Z = up, metres.
Materials per ship: <name>_hull, <name>_hullw (side plating with windows),
<name>_trim (trim sheet; UVs set per face at build time).
Hull faces get box-projected UVs (T_HULL metres per texture tile).
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "tex")
OUT = os.path.join(ROOT, "out")
with open(os.path.join(TEX, "trim_layout.json")) as _f:
    LAY = json.load(_f)
N = LAY["size"]
T_HULL = 48.0
MATS = ("hull", "hullw", "trim")


# ---------------------------------------------------------------- uv helpers
def strip_v(name):
    a, b = LAY["strips"][name]
    return 1 - (b - 3) / N, 1 - (a + 3) / N  # (bottom v, top v)


def strip_px(name):
    a, b = LAY["strips"][name]
    return b - a


def cell_uv(name):
    i = LAY["cells"].index(name)
    a, b = LAY["strips"]["cells"]
    return (i * 256 + 4) / N, ((i + 1) * 256 - 4) / N, 1 - (b - 4) / N, 1 - (a + 4) / N


def octo(w, zt, zb, c, cx=0.0):
    hw = w / 2.0
    c = min(c, hw * 0.9, (zt - zb) * 0.45)
    return [(cx + hw, zb + c), (cx + hw, zt - c), (cx + hw - c, zt), (cx - hw + c, zt),
            (cx - hw, zt - c), (cx - hw, zb + c), (cx - hw + c, zb), (cx + hw - c, zb)]


def circle(r, zc=0.0, n=12, cx=0.0):
    return [(cx + r * math.cos(2 * math.pi * k / n), zc + r * math.sin(2 * math.pi * k / n)) for k in range(n)]


class Ship:
    def __init__(self, name, faction):
        self.name, self.fac = name, faction
        self.bm = bmesh.new()
        self.uvl = self.bm.loops.layers.uv.new("UVMap")
        self.kind = self.bm.faces.layers.int.new("uvkind")  # 0 preset, 1 box hull, 2 box auto

    # ------------------------------------------------------------ low level
    def _face(self, verts, spec, uvs=None):
        f = self.bm.faces.new(verts)
        if spec in ("hull", "hullw", "auto"):
            f.material_index = MATS.index("hull" if spec == "auto" else spec)
            f[self.kind] = 2 if spec == "auto" else 1
        else:
            f.material_index = MATS.index("trim")
            f[self.kind] = 0
            for l, uv in zip(f.loops, uvs):
                l[self.uvl].uv = uv
        return f

    def _quad_uv(self, spec, corners):
        """UVs for a planar quad (bl, br, tr, tl) under a trim spec."""
        bl, br, tr, tl = [Vector(c) for c in corners]
        if spec[0] == "cell":
            u0, u1, v0, v1 = cell_uv(spec[1])
            return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
        # ("trim", strip[, metres per tile])
        L = ((br - bl).length + (tr - tl).length) / 2
        H = ((tl - bl).length + (tr - br).length) / 2
        m = spec[2] if len(spec) > 2 else N * H / strip_px(spec[1])
        reps = max(1, round(L / m))
        vb, vt = strip_v(spec[1])
        return [(0, vb), (reps, vb), (reps, vt), (0, vt)]

    def _fix_winding(self, faces):
        vol = 0.0
        for f in faces:
            vs = [v.co for v in f.verts]
            for k in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[k].cross(vs[k + 1]))
        if vol < 0:
            bmesh.ops.reverse_faces(self.bm, faces=faces)

    # ------------------------------------------------------------ primitives
    def loft(self, sections, segs, cap0="auto", cap1="auto", off=(0, 0, 0), axis="y"):
        """sections: [(t, [(a,b),...]), ...] with equal point counts.
        axis 'y': point (a,b) -> (x=a, y=t, z=b).  axis 'z': (x=a, y=b, z=t).
        segs[i]: hull spec or ("trim", strip[, m]) for the band i..i+1.
        caps: hull spec, None (open), or ("cell", name)."""
        ox, oy, oz = off

        def P(t, a, b):
            return (a + ox, t + oy, b + oz) if axis == "y" else (a + ox, b + oy, t + oz)

        rings = [[self.bm.verts.new(P(t, a, b)) for a, b in pts] for t, pts in sections]
        faces = []
        for i, spec in enumerate(segs):
            A, B = rings[i], rings[i + 1]
            n = len(A)
            if isinstance(spec, str):
                for j in range(n):
                    k = (j + 1) % n
                    faces.append(self._face([A[j], A[k], B[k], B[j]], spec))
                continue
            vb, vt = strip_v(spec[1])
            perA = [(A[(j + 1) % n].co - A[j].co).length for j in range(n)]
            perB = [(B[(j + 1) % n].co - B[j].co).length for j in range(n)]
            H = sum((B[j].co - A[j].co).length for j in range(n)) / n
            m = spec[2] if len(spec) > 2 else N * H / strip_px(spec[1])
            PA, PB = sum(perA), sum(perB)
            repA = max(1, round(PA / m))
            repB = max(1, round(PB / m))
            reps = max(repA, repB)
            sa = sb = 0.0
            for j in range(n):
                k = (j + 1) % n
                ua0, ua1 = sa / PA * reps, (sa + perA[j]) / PA * reps
                ub0, ub1 = sb / PB * reps, (sb + perB[j]) / PB * reps
                sa += perA[j]
                sb += perB[j]
                faces.append(self._face([A[j], A[k], B[k], B[j]], "trim",
                                        [(ua0, vb), (ua1, vb), (ub1, vt), (ub0, vt)]))
        for ring, cap in ((rings[0], cap0), (rings[-1], cap1)):
            if cap is None:
                continue
            if isinstance(cap, str):
                faces.append(self._face(list(ring), cap))
            else:
                u0, u1, v0, v1 = cell_uv(cap[1])
                xs = [v.co.x for v in ring]
                zs = [(v.co.z if axis == "y" else v.co.y) for v in ring]
                x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
                uvs = [(u0 + (u1 - u0) * (v.co.x - x0) / max(1e-6, x1 - x0),
                        v0 + (v1 - v0) * (((v.co.z if axis == "y" else v.co.y)) - z0) / max(1e-6, z1 - z0))
                       for v in ring]
                faces.append(self._face(list(ring), "trim", uvs))
        self._fix_winding(faces)
        return faces

    def box(self, c, s, spec="auto", faces=None):
        """Axis-aligned box. faces: {'+x': spec, ...} overrides per side."""
        cx, cy, cz = c
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        V = {}
        for i in (-1, 1):
            for j in (-1, 1):
                for k in (-1, 1):
                    V[i, j, k] = self.bm.verts.new((cx + i * hx, cy + j * hy, cz + k * hz))
        # corners ordered bl, br, tr, tl as seen from outside, "up" = +Z (or +Y for z faces)
        sides = {
            "+x": [V[1, -1, -1], V[1, 1, -1], V[1, 1, 1], V[1, -1, 1]],
            "-x": [V[-1, 1, -1], V[-1, -1, -1], V[-1, -1, 1], V[-1, 1, 1]],
            "+y": [V[1, 1, -1], V[-1, 1, -1], V[-1, 1, 1], V[1, 1, 1]],
            "-y": [V[-1, -1, -1], V[1, -1, -1], V[1, -1, 1], V[-1, -1, 1]],
            "+z": [V[-1, -1, 1], V[1, -1, 1], V[1, 1, 1], V[-1, 1, 1]],
            "-z": [V[1, -1, -1], V[-1, -1, -1], V[-1, 1, -1], V[1, 1, -1]],
        }
        out = []
        for key, vs in sides.items():
            sp = (faces or {}).get(key, spec)
            if isinstance(sp, str):
                out.append(self._face(vs, sp))
            else:
                out.append(self._face(vs, "trim", self._quad_uv(sp, [v.co for v in vs])))
        self._fix_winding(out)
        return out

    def plate(self, c, size, normal, spec, depth=0.6, mirror_x=False):
        """Raised decal/greeble plate on a surface facing `normal` ('+x','-x','+z','-y',...)."""
        for sx in ((1, -1) if mirror_x else (1,)):
            nrm = normal if sx == 1 else {"+x": "-x", "-x": "+x"}.get(normal, normal)
            cc = (c[0] * sx, c[1], c[2])
            ax = nrm[1]
            sgn = 1 if nrm[0] == "+" else -1
            w, h = size
            if ax == "x":
                dims = (depth, w, h)
                cen = (cc[0] + sgn * depth / 2, cc[1], cc[2])
            elif ax == "y":
                dims = (w, depth, h)
                cen = (cc[0], cc[1] + sgn * depth / 2, cc[2])
            else:
                dims = (w, h, depth)
                cen = (cc[0], cc[1], cc[2] + sgn * depth / 2)
            self.box(cen, dims, "auto", faces={nrm: spec})

    def engine(self, y0, x, z, r, length, nozzle_r=None, segs=12, glow="glow", bands=None):
        """Cylindrical engine pod along +Y (stern) ending in a recessed glowing bell."""
        nr = nozzle_r or r * 0.8
        secs, sp = [], []
        prof = lambda rr: circle(rr, 0, segs)
        ys = [0, length * 0.08, length * 0.45, length * 0.53, length * 0.9, length]
        rs = [r * 0.82, r, r, r * 0.95, r * 0.95, nr * 1.08]
        for yy, rr in zip(ys, rs):
            secs.append((y0 + yy, prof(rr)))
        sp = ["auto", "auto", bands or ("trim", "lights"), "auto", ("trim", "accent")]
        self.loft(secs, sp, cap0="auto", cap1=None, off=(x, 0, z))
        # bell interior (open ring going inward) + glow disc
        yb = y0 + length
        inner = [(yb, prof(nr * 1.08)), (yb - length * 0.12, prof(nr * 0.7))]
        fs = self.loft(inner, [("trim", "nozzle")], cap0=None, cap1=("cell", glow), off=(x, 0, z))
        for f in fs:
            f.normal_update()
            cen = f.calc_center_median()
            if f is fs[-1]:
                bad = f.normal.y < 0  # glow disc faces out the back
            else:
                radial = Vector((cen.x - x, 0, cen.z - z))
                bad = f.normal.dot(radial) > 0  # bell interior faces the axis
            if bad:
                bmesh.ops.reverse_faces(self.bm, faces=[f])

    # ------------------------------------------------------------ finish
    def finish(self):
        bm = self.bm
        bm.normal_update()
        for f in bm.faces:
            k = f[self.kind]
            if k == 0:
                continue
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            if k == 2:
                f.material_index = MATS.index("hullw" if ax == 0 and abs(n.x) > 0.8 else "hull")
            for l in f.loops:
                p = l.vert.co
                if ax == 0:
                    uv = (p.y * (1 if n.x > 0 else -1), p.z)
                elif ax == 1:
                    uv = (p.x * (-1 if n.y > 0 else 1), p.z)
                else:
                    uv = (p.x, p.y)
                l[self.uvl].uv = (uv[0] / T_HULL, uv[1] / T_HULL)
        me = bpy.data.meshes.new(self.name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        for m in MATS:
            me.materials.append(make_material(self.name, self.fac, m))
        for p in me.polygons:
            p.use_smooth = False
        return ob


# ---------------------------------------------------------------- materials
def tex_names(fac, m):
    base = {"hull": "hull", "hullw": "hull", "trim": "trim"}[m]
    d = f"{fac}{'hullw' if m == 'hullw' else base}_D"
    n = f"{fac}{base}_N"
    s = f"{fac}{base}_S"
    e = {"hull": "capblack_E", "hullw": f"{fac}hullw_E", "trim": f"{fac}trim_E"}[m]
    return d, n, s, e


def _img(name, colorspace="sRGB"):
    path = os.path.join(TEX, name + ".png")
    im = bpy.data.images.load(path, check_existing=True)
    im.colorspace_settings.name = colorspace
    return im


def make_material(ship, fac, m):
    name = f"{ship}_{m}"
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    d, n, s, e = tex_names(fac, m)
    td = nt.nodes.new("ShaderNodeTexImage"); td.image = _img(d)
    nt.links.new(td.outputs[0], bsdf.inputs["Base Color"])
    tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = _img(n, "Non-Color")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs[0], nm.inputs["Color"])
    nt.links.new(nm.outputs[0], bsdf.inputs["Normal"])
    ts = nt.nodes.new("ShaderNodeTexImage"); ts.image = _img(s, "Non-Color")
    inv = nt.nodes.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
    nt.links.new(ts.outputs[0], inv.inputs[1])
    nt.links.new(inv.outputs[0], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.25
    if os.path.exists(os.path.join(TEX, e + ".png")):
        te = nt.nodes.new("ShaderNodeTexImage"); te.image = _img(e)
        key = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
        nt.links.new(te.outputs[0], bsdf.inputs[key])
        bsdf.inputs["Emission Strength"].default_value = 2.5
    return mat


# ---------------------------------------------------------------- output
def write_ogre_material(ship, fac):
    lines = ['import * from "BZBase.material"', ""]
    for m in MATS:
        d, n, s, e = tex_names(fac, m)
        lines += [f"material {ship}_{m} : BZBase", "{",
                  f"\tset_texture_alias DiffuseMap {d}.dds",
                  f"\tset_texture_alias NormalMap {n}.dds",
                  f"\tset_texture_alias SpecularMap {s}.dds",
                  f"\tset_texture_alias EmissiveMap {e}.dds",
                  "", '\tset $diffuse "1 1 1"', '\tset $ambient "1 1 1"',
                  '\tset $specular ".6 .6 .6"', '\tset $shininess "64"', "}", ""]
    with open(os.path.join(OUT, ship + ".material"), "w", newline="\n") as f:
        f.write("\n".join(lines))


def export_mesh(ob):
    os.makedirs(OUT, exist_ok=True)
    conv = os.path.join(bpy.utils.user_resource("SCRIPTS"), "addons", "bz98tools", "ogretools", "OgreXMLConverter.exe")
    # ogrefast writes one submesh per selected object, named after its first material,
    # so export a throwaway copy split into one object per material.
    tmp = ob.copy()
    tmp.data = ob.data.copy()
    bpy.context.collection.objects.link(tmp)
    bpy.ops.object.select_all(action="DESELECT")
    tmp.select_set(True)
    bpy.context.view_layer.objects.active = tmp
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    parts = list(bpy.context.selected_objects)
    for p in parts:
        used = {poly.material_index for poly in p.data.polygons}
        keep = p.data.materials[min(used)]
        p.data.materials.clear()
        p.data.materials.append(keep)
    bpy.context.view_layer.objects.active = parts[0]
    res = bpy.ops.export_scene.bz98_bzr_mesh(
        filepath=os.path.join(OUT, ob.name + ".mesh"), xml_converter=conv,
        export_materials=False, export_skeleton=False, export_animation=False,
        export_colour=False, apply_transform=True, apply_modifiers=True)
    print("EXPORT", ob.name, res, sorted(p.data.materials[0].name for p in parts))
    for p in parts:
        bpy.data.objects.remove(p)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import addon_utils
    addon_utils.enable("bz98tools", default_set=True)


def render_previews(ob, tag, dist, views=None, res=(1600, 900)):
    import mathutils
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in
        sc.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    w = bpy.data.worlds.new("space")
    sc.world = w
    w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.012, 0.014, 0.022, 1)
    bg.inputs[1].default_value = 1.0
    for nm, rot, en, colr in (("key", (52, 0, 38), 5.0, (1, 0.96, 0.9)),
                              ("rim", (110, 0, 210), 2.0, (0.6, 0.7, 1.0)),
                              ("fill", (-60, 0, -40), 0.6, (0.8, 0.8, 0.9))):
        L = bpy.data.lights.new(nm, "SUN")
        L.energy, L.color = en, colr
        lo = bpy.data.objects.new(nm, L)
        lo.rotation_euler = [math.radians(a) for a in rot]
        sc.collection.objects.link(lo)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 60
    cam.data.clip_end = 5000
    sc.collection.objects.link(cam)
    sc.camera = cam
    bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    tgt = sum(bb, Vector()) / 8
    views = views or {"q34": (-1, -1.1, 0.5), "side": (-1, 0, 0.05), "rear": (0.9, 1.2, 0.35),
                      "top": (0.05, 0.2, 1), "low": (1, -0.8, -0.35)}
    paths = []
    for vn, d in views.items():
        d = Vector(d).normalized()
        cam.location = tgt + d * dist
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        p = os.path.join(OUT, f"{tag}_{vn}.png")
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        paths.append(p)
    return paths
