#!/usr/bin/env python3
"""Build the L-Power lightning-panel model fixes (Assets/ModelFixes).

For the NSDF (ablpow) and Black Dog (bblpow) lightning plants, which share one mesh layout:

  * Mesh: the faces that carry the baked lightning art (the six panel bones alt11pt1..pt6, plus
    the lightning faces on the fins) are moved into a second submesh, `lightning`, whose
    material is the moving-bolts shader (Materials/cr_lightarc.material). Skeleton link, bone
    assignments, UVs and every vertex attribute are kept, so skinning, shadows and OpenShim's
    per-bone destruction pieces behave as before (the pieces are cut per bone from the face
    streams of every submesh, so the second submesh only changes the material those faces use).
  * SDF (ablpow only): the stock ANIM chunk gains element 4, the one PowerPlant::PowerPlant
    plays, with the two fins (alt11tpb, alt11tpc) turning once per 8 seconds about the mast.

Stock inputs are read, never written: the stock .mesh/.skeleton from a Redux install and the
stock ablpow.sdf from a BZ1 1.5 install. Needs the bz98tools OgreXMLConverter (MeshSerializer
v1.100), found under %APPDATA%\\Blender Foundation\\Blender\\*\\scripts\\addons\\bz98tools or via
the BZ98TOOLS environment variable.

  python Tools/Build-LightningPlants.py --stock-sdf <ablpow.sdf> [--game <Redux dir>] [--check]
"""
import argparse
import glob
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from collections import defaultdict

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
    d = os.environ.get("BZ98TOOLS")
    if not d:
        hits = sorted(glob.glob(os.path.join(os.environ.get("APPDATA", ""), "Blender Foundation", "Blender", "*",
                                             "scripts", "addons", "bz98tools")))
        if not hits:
            sys.exit("bz98tools add-on not found; set BZ98TOOLS")
        d = hits[-1]
    exe = os.path.join(d, "ogretools", "OgreXMLConverter.exe")
    if not os.path.exists(exe):
        sys.exit("OgreXMLConverter.exe not found under " + d)
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

ANIM_HEAD = 64
SEQ = struct.Struct("<i128xiiif")
PART = struct.Struct("<8si96x6i")


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


def read_sdf_parts(data):
    """(name -> (right, up, front, pos)) from the SGEO part records of band 0."""
    pos = data.find(b"SGEO")
    count = struct.unpack_from("<i", data, pos + 8)[0]
    rec = struct.Struct("<8s12f8s7fiii4f")
    out = {}
    base = pos + 12
    for i in range(count):
        f = rec.unpack_from(data, base + i * rec.size)
        name = f[0].split(b"\0")[0].decode()
        if name:
            m = f[1:13]
            out[name] = (m[0:3], m[3:6], m[6:9], m[9:12])
    return out


def add_spin(sdf_bytes):
    data = bytearray(sdf_bytes)
    i = data.find(b"ANIM")
    tag, length = struct.unpack_from("<4si", data, i)
    body = bytes(data[i + 8:i + length])
    name = body[:16]
    n_seq, n_part, n_rot, n_scale, n_pos = struct.unpack_from("<5i", body, 16)
    ptrs = body[36:64]
    p = ANIM_HEAD
    seqs = [body[p + k * SEQ.size:p + (k + 1) * SEQ.size] for k in range(n_seq)]
    p += n_seq * SEQ.size
    parts = [list(PART.unpack_from(body, p + k * PART.size)) for k in range(n_part)]
    p += n_part * PART.size
    rots = [struct.unpack_from("<i4f", body, p + k * 20) for k in range(n_rot)]
    p += n_rot * 20
    scales = [struct.unpack_from("<i3f", body, p + k * 16) for k in range(n_scale)]
    p += n_scale * 16
    poss = [struct.unpack_from("<i3f", body, p + k * 16) for k in range(n_pos)]
    if n_seq != 2 or n_scale:
        sys.exit("unexpected stock ANIM layout")

    # Element 4 is the one PowerPlant::PowerPlant plays; array order is element index, so
    # elements 2 and 3 exist as inert copies of the spin (zero part flags, as Resurgence
    # hbnest). loop 0 = loop forever; frames 0..FRAMES, with the last pose equal to the first.
    new_seqs = seqs + [SEQ.pack(k, 0, FRAMES + 1, 0, FPS) for k in (2, 3, 4)]

    sdf_parts = read_sdf_parts(sdf_bytes)
    keyed = {}
    for fin in ("alt11tpb", "alt11tpc"):
        r, u, f, _ = sdf_parts[fin]
        keyed[fin] = hamilton_from_columns(r, u, f)

    # Rebuild the key tables. Existing parts keep their keys (element 0/1 stay constant);
    # the fins get FRAMES+1 rotation keys on every frame, and tpb, which stock leaves out of
    # the ANIM chunk, gets a record copied from tpc's (identity extras, its own bind).
    new_parts, new_rots, new_poss = [], [], []
    for rec in parts:
        nm = rec[0].split(b"\0")[0].decode()
        _, flags, r0, rn, s0, sn, p0, pn = rec
        old_r = rots[r0:r0 + rn]
        old_p = poss[p0:p0 + pn]
        if nm == "alt11tpc":
            old_r = [(fr, *spin_key(fr, keyed["alt11tpc"])) for fr in range(FRAMES + 1)]
        new_parts.append([rec[0], flags, len(new_rots), len(old_r), 0, 0, len(new_poss), len(old_p)])
        new_rots += old_r
        new_poss += old_p
        if nm == "alt11tpc":
            tpb = list(rec)
            tpb[0] = b"alt11tpb".ljust(8, b"\0")
            tpb_rots = [(fr, *spin_key(fr, keyed["alt11tpb"])) for fr in range(FRAMES + 1)]
            tpb_pos = [(0, *sdf_parts["alt11tpb"][3]), (FRAMES, *sdf_parts["alt11tpb"][3])]
            new_parts.append([tpb[0], tpb[1], len(new_rots), len(tpb_rots), 0, 0, len(new_poss), len(tpb_pos)])
            new_rots += tpb_rots
            new_poss += tpb_pos
    # tpc also gets constant position keys, like every stock moving part
    for k, rec in enumerate(new_parts):
        if rec[0].split(b"\0")[0] == b"alt11tpc" and rec[7] == 0:
            pos = sdf_parts["alt11tpc"][3]
            rec[6] = len(new_poss)
            rec[7] = 2
            new_poss += [(0, *pos), (FRAMES, *pos)]
    # new_parts positions were recorded in order; the pt parts keep their ranges, so re-pack
    # position ranges contiguously by part order to keep the tables consistent.
    packed_p, packed_r, final_parts = [], [], []
    for rec in new_parts:
        _, flags, r0, rn, s0, sn, p0, pn = rec
        final_parts.append((rec[0], flags, len(packed_r), rn, 0, 0, len(packed_p), pn))
        packed_r += new_rots[r0:r0 + rn]
        packed_p += new_poss[p0:p0 + pn]

    # The struct skips 96 bytes of per-part matrices: copy them from the stock record (tpc's
    # for the new tpb record, which then gets its own bind).
    old_raw = {body[ANIM_HEAD + n_seq * SEQ.size + k * PART.size:][:8].split(b"\0")[0]:
               body[ANIM_HEAD + n_seq * SEQ.size + k * PART.size:][:PART.size] for k in range(n_part)}
    parts_raw = bytearray()
    for rec in final_parts:
        nm = rec[0].split(b"\0")[0]
        raw = bytearray(old_raw.get(nm, old_raw[b"alt11tpc"]))
        raw[0:8] = rec[0]
        struct.pack_into("<6i", raw, 108, *rec[2:])
        if nm == b"alt11tpb":
            # matrix2 of the record: its own bind (identity rotation, position 0 here)
            struct.pack_into("<12f", raw, 12 + 48, *(list(sum(sdf_parts["alt11tpb"][0:3], ())) + list(sdf_parts["alt11tpb"][3])))
        raw[8:12] = struct.pack("<i", 0)
        parts_raw += raw

    new_body = bytearray(name)
    new_body += struct.pack("<5i", len(new_seqs), len(final_parts), len(packed_r), 0, len(packed_p))
    new_body += ptrs
    for s in new_seqs:
        new_body += s
    new_body += parts_raw
    for k in packed_r:
        new_body += struct.pack("<i4f", *k)
    for k in packed_p:
        new_body += struct.pack("<i3f", *k)
    chunk = struct.pack("<4si", b"ANIM", len(new_body) + 8) + bytes(new_body)
    return bytes(data[:i]) + chunk + bytes(data[i + length:])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", default=DEFAULT_GAME, help="Redux install to read stock meshes from")
    ap.add_argument("--stock-sdf", required=True, help="stock ablpow.sdf (BZ1 1.5 install)")
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
    sdf = add_spin(open(args.stock_sdf, "rb").read())
    path = os.path.join(args.out, "ablpow.sdf")
    open(path, "wb").write(sdf)
    print("ablpow.sdf: element 4 = fin spin, %d frames at %g fps -> %s" % (FRAMES + 1, FPS, path))


if __name__ == "__main__":
    main()
