#!/usr/bin/env python3
"""Build the L-Power lightning-panel model fixes (Assets/ModelFixes).

For the NSDF (ablpow) and Black Dog (bblpow) lightning plants, which share one mesh layout:

  * Mesh: the faces that carry the baked lightning art (the six panel bones alt11pt1..pt6, plus
    the lightning faces on the fins) are moved into a second submesh, `lightning`, whose
    material is the moving-bolts shader (Materials/cr_lightarc.material). Skeleton link, bone
    assignments, UVs and every vertex attribute are kept, so skinning, shadows and OpenShim's
    per-bone destruction pieces behave as before (the pieces are cut per bone from the face
    streams of every submesh, so the second submesh only changes the material those faces use).
  * SDF (ablpow and bblpow, whose stock SDFs are byte-identical): the stock ANIM chunk gains element 4, the one
    PowerPlant::PowerPlant plays, with the two fins (alt11tpb, alt11tpc) turning once per 8 seconds about the mast.

Stock inputs are read, never written: the stock .mesh/.skeleton from a Redux install and the
stock ablpow.sdf from a BZ1 1.5 install. All file I/O goes through the BZ98R Blender ToolKit
(Tools/bzmodellibs.py finds it): its OgreXMLConverter (MeshSerializer v1.100) and SDFSerializer.

  python Tools/Build-LightningPlants.py --stock-sdf <ablpow.sdf> [--stock-bblpow-sdf <bblpow.sdf>] [--game <Redux dir>]
"""
import argparse
import importlib
import io
import math
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bzmodellibs  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Assets", "ModelFixes")
DEFAULT_GAME = r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux"

# name -> (mesh path under BZ_ASSETS\common\models, arc material)
PLANTS = {
    "ablpow": ("ablpow", "CR_LightArc_NSDF"),
    "bblpow": ("TRO/bblpow", "CR_LightArc_BDog"),
}
PANEL_BONES = {"alt11pt%d" % i for i in range(1, 7)}
# Lightning art on the fins, in atlas UV (u0, v0, u1, v1): the three coffin-shaped bolt
# plates and the four tube strips. Faces on the mast and fin bones whose UV centroid falls
# inside one of these take the bolts too.
FIN_RECTS = [(0.305, 0.175, 0.378, 0.435), (0.405, 0.19, 0.525, 0.42), (0.55, 0.14, 0.72, 0.475)]
FIN_BONES = {"alt11tpb", "alt11tpc", "alt11bdb"}

SPIN_SECONDS = 8.0
FPS = 15.0
FRAMES = int(round(SPIN_SECONDS * FPS))  # 120; element 4 runs frames 0..120 with 120 == 0


def converter():
    exe = os.path.join(str(bzmodellibs.toolkit_root()), "bz98tools", "ogretools", "OgreXMLConverter.exe")
    if not os.path.exists(exe):
        sys.exit("OgreXMLConverter.exe not found at " + exe)
    return exe


def run_converter(exe, src, dst):
    log = os.path.join(tempfile.gettempdir(), "cr_lightning_ogrexml.log")
    r = subprocess.run([exe, "-q", "-log", log, src, dst], capture_output=True, text=True)
    if not os.path.exists(dst) or os.path.getsize(dst) == 0:
        sys.exit("OgreXMLConverter failed on %s: %s%s" % (src, r.stdout, r.stderr))


# --------------------------------------------------------------------------- mesh split

def skeleton_names(path):
    root = ET.parse(path).getroot()
    return {int(b.get("id")): b.get("name") for b in root.iter("bone")}


def split_lightning(mesh_xml, skeleton_xml, arc_material):
    tree = ET.parse(mesh_xml)
    root = tree.getroot()
    names = skeleton_names(skeleton_xml)
    submeshes = root.find("submeshes")
    sm = submeshes.findall("submesh")
    if len(sm) != 1:
        sys.exit("expected one submesh, found %d" % len(sm))
    sm = sm[0]
    geom = sm.find("geometry")
    buffers = geom.findall("vertexbuffer")
    count = int(geom.get("vertexcount"))
    verts = [[vb.findall("vertex")[i] for vb in buffers] for i in range(count)]
    uv = [(float(t.get("u")), float(t.get("v"))) for t in buffers[1].iter("texcoord")]
    assign = defaultdict(list)
    for a in sm.find("boneassignments"):
        assign[int(a.get("vertexindex"))].append((int(a.get("boneindex")), float(a.get("weight"))))
    bone_of = {i: names[max(l, key=lambda x: x[1])[0]] for i, l in assign.items()}

    faces = [tuple(int(f.get(k)) for k in ("v1", "v2", "v3")) for f in sm.find("faces")]
    arc = set()
    stats = defaultdict(int)
    for n, f in enumerate(faces):
        bones = [bone_of[i] for i in f]
        b = max(set(bones), key=bones.count)
        if b in PANEL_BONES:
            arc.add(n)
            stats[b] += 1
        elif b in FIN_BONES:
            cu = sum(uv[i][0] for i in f) / 3.0
            cv = sum(uv[i][1] for i in f) / 3.0
            if any(r[0] <= cu <= r[2] and r[1] <= cv <= r[3] for r in FIN_RECTS):
                arc.add(n)
                stats[b + "(art)"] += 1
    if not arc:
        sys.exit("no lightning faces found")

    def build(face_ids, material):
        remap, order = {}, []
        for n in face_ids:
            for i in faces[n]:
                if i not in remap:
                    remap[i] = len(order)
                    order.append(i)
        out = ET.Element("submesh", dict(sm.attrib, material=material))
        faces_el = ET.SubElement(out, "faces", count=str(len(face_ids)))
        for n in face_ids:
            a, b, c = (remap[i] for i in faces[n])
            ET.SubElement(faces_el, "face", v1=str(a), v2=str(b), v3=str(c))
        g = ET.SubElement(out, "geometry", vertexcount=str(len(order)))
        for bi, vb in enumerate(buffers):
            vbo = ET.SubElement(g, "vertexbuffer", vb.attrib)
            for i in order:
                vbo.append(verts[i][bi])
        ba = ET.SubElement(out, "boneassignments")
        for i in order:
            for bone, w in assign[i]:
                ET.SubElement(ba, "vertexboneassignment", vertexindex=str(remap[i]), boneindex=str(bone),
                              weight=repr(w))
        return out

    keep = [n for n in range(len(faces)) if n not in arc]
    base = build(keep, sm.get("material"))
    lightning = build(sorted(arc), arc_material)
    names_el = root.find("submeshnames")
    submeshes.remove(sm)
    submeshes.append(base)
    submeshes.append(lightning)
    if names_el is not None:
        root.remove(names_el)
    names_el = ET.Element("submeshnames")
    ET.SubElement(names_el, "submeshname", name="base", index="0")
    ET.SubElement(names_el, "submeshname", name="lightning", index="1")
    # submeshnames sits after submeshes/skeletonlink in the Ogre XML schema.
    root.insert(list(root).index(submeshes) + 1 + (1 if root.find("skeletonlink") is not None else 0), names_el)
    ET.indent(tree, space="    ")
    tree.write(mesh_xml, encoding="utf-8", xml_declaration=True)
    return len(faces), len(arc), dict(stats)


# --------------------------------------------------------------------------- SDF ANIM

def qmul(a, b):
    aw, ax, ay, az = a
    bw, bx, by, bz = b
    return (aw * bw - ax * bx - ay * by - az * bz, aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx, aw * bz + ax * by - ay * bx + az * bw)


def spin_key(frame, bind_hamilton):
    """Stored key quaternion (w, x, y, z): the conjugate of the Hamilton quaternion of the
    part's parent-space column matrix, here R_y(theta) * R_bind."""
    theta = 2.0 * math.pi * frame / FRAMES
    spin = (math.cos(theta / 2), 0.0, math.sin(theta / 2), 0.0)
    w, x, y, z = qmul(spin, bind_hamilton)
    return (w, -x, -y, -z)


def hamilton_from_columns(right, up, front):
    """Hamilton quaternion of the matrix whose columns are right, up, front."""
    m = [[right[0], up[0], front[0]], [right[1], up[1], front[1]], [right[2], up[2], front[2]]]
    t = m[0][0] + m[1][1] + m[2][2]
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        q = (0.25 * s, (m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s)
    elif m[0][0] > m[1][1] and m[0][0] > m[2][2]:
        s = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
        q = ((m[2][1] - m[1][2]) / s, 0.25 * s, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s)
    elif m[1][1] > m[2][2]:
        s = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
        q = ((m[0][2] - m[2][0]) / s, (m[0][1] + m[1][0]) / s, 0.25 * s, (m[1][2] + m[2][1]) / s)
    else:
        s = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
        q = ((m[1][0] - m[0][1]) / s, (m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, 0.25 * s)
    return q


def add_spin(sdf_bytes):
    """Return the SDF with ANIM element 4 added, through the toolkit's SDFSerializer (read and
    write both; an untouched stock SDF round-trips byte for byte)."""
    bw = bzmodellibs.bwd2
    # bzmodellibs has no `spacial` alias; its import above already put bz98tools on sys.path.
    sp = importlib.import_module("bzrmodelporter.spacial")
    SDFSerializer = bzmodellibs.bwd2_serializer.SDFSerializer
    sdf = SDFSerializer(io.BytesIO(sdf_bytes)).read()
    anim = sdf.anim_obj
    if anim is None or sorted(anim.animation_map) != [0, 1] or anim.scale_keyframe_list:
        sys.exit("unexpected stock ANIM layout")

    # Element 4 is the one PowerPlant::PowerPlant plays; array order is element index, so
    # elements 2 and 3 exist as inert copies (zero part flags, as Resurgence hbnest).
    # loop 0 = loop forever; frames 0..FRAMES, with the last pose equal to the first.
    for index in (2, 3, 4):
        a = anim.create_animation(index)
        a.start, a.length, a.loop, a.speed = 0, FRAMES + 1, 0, FPS

    # Rebuild the key tables part by part. Existing parts keep their keys (elements 0 and 1
    # stay constant); the fins get a rotation key on every frame, and tpb, which stock leaves
    # out of the ANIM chunk, gets a record of its own.
    geo = {o.name: o for o in sdf.primary_objects()}
    old = list(anim.mesh_map.values())
    keys = {m.name: (anim.slice_mesh_orientation_keyframes(m), anim.slice_mesh_position_keyframes(m)) for m in old}
    fin_bind = {}
    for fin in ("alt11tpb", "alt11tpc"):
        t = geo[fin].transform
        fin_bind[fin] = hamilton_from_columns((t.rx, t.ry, t.rz), (t.ux, t.uy, t.uz), (t.fx, t.fy, t.fz))
    for fin, q in fin_bind.items():  # the toolkit's own conversion must give the bind pose back
        back = sp.Quaternion(*spin_key(0, q)).to_transform()
        t = geo[fin].transform
        if max(abs(a - b) for a, b in zip(back.to_rufp_xyz(), t.to_rufp_xyz())) > 1e-4:
            sys.exit(fin + ": key 0 does not reproduce the bind pose")
    order = []
    for m in old:
        order.append(m)
        if m.name == "alt11tpc":
            tpb = bw.AnimationMesh(anim, "alt11tpb")
            tpb.flags = m.flags
            tpb.inverse_transform = m.inverse_transform
            tpb.frame_transform = geo["alt11tpb"].transform
            order.append(tpb)
            keys["alt11tpb"] = ([], [])
    anim.mesh_map = {}
    anim.orientation_keyframe_list, anim.position_keyframe_list = [], []
    for m in order:
        rot, pos = keys[m.name]
        if m.name in fin_bind:
            rot = [bw.OrientationKeyframe(fr, sp.Quaternion(*spin_key(fr, fin_bind[m.name]))) for fr in range(FRAMES + 1)]
            if not pos:  # every stock moving part carries position keys
                t = geo[m.name].transform
                pos = [bw.PositionKeyframe(fr, sp.Vector3(t.px, t.py, t.pz)) for fr in (0, FRAMES)]
        m.orientation_start, m.orientation_length = len(anim.orientation_keyframe_list), len(rot)
        m.position_start, m.position_length = len(anim.position_keyframe_list), len(pos)
        m.scale_start = m.scale_length = 0
        anim.orientation_keyframe_list += rot
        anim.position_keyframe_list += pos
        anim.mesh_map[m.name] = m
    out = io.BytesIO()
    SDFSerializer(out).write(sdf)
    return out.getvalue()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", default=DEFAULT_GAME, help="Redux install to read stock meshes from")
    ap.add_argument("--stock-sdf", required=True, help="stock ablpow.sdf (BZ1 1.5 install)")
    ap.add_argument("--stock-bblpow-sdf", help="stock bblpow.sdf (default: same bytes as ablpow.sdf; they are identical)")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()
    exe = converter()
    models = os.path.join(args.game, "BZ_ASSETS", "common", "models")
    os.makedirs(args.out, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for name, (rel, material) in PLANTS.items():
            for ext in ("mesh", "skeleton"):
                shutil.copy(os.path.join(models, rel.replace("/", os.sep) + "." + ext), os.path.join(tmp, name + "." + ext))
            run_converter(exe, os.path.join(tmp, name + ".mesh"), os.path.join(tmp, name + ".mesh.xml"))
            run_converter(exe, os.path.join(tmp, name + ".skeleton"), os.path.join(tmp, name + ".skeleton.xml"))
            total, arc, stats = split_lightning(os.path.join(tmp, name + ".mesh.xml"),
                                                os.path.join(tmp, name + ".skeleton.xml"), material)
            out_mesh = os.path.join(args.out, name + ".mesh")
            run_converter(exe, os.path.join(tmp, name + ".mesh.xml"), out_mesh)
            print("%s: %d of %d faces -> lightning submesh (%s) -> %s" % (name, arc, total, stats, out_mesh))
    for name, src in (("ablpow", args.stock_sdf), ("bblpow", args.stock_bblpow_sdf or args.stock_sdf)):
        sdf = add_spin(open(src, "rb").read())
        path = os.path.join(args.out, name + ".sdf")
        open(path, "wb").write(sdf)
        print("%s.sdf: element 4 = fin spin, %d frames at %g fps -> %s" % (name, FRAMES + 1, FPS, path))


if __name__ == "__main__":
    main()
