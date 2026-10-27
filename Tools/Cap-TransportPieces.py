"""Close the open faces of the Fury transport's destruction pieces (Mission 18).

When a thruster (hbtrn200) or the transport hull (hbtran00) dies, OpenShim's native chunk
meshes fling the whole model as one piece (each mesh has a single bone). Both stock meshes
were modelled as shells that sit against something, so the flying piece shows its hollow
inside:

* hbtrn200: the pod's inner face, the trapezoid that faced the hull, was never modelled.
* hbtran00: the underside has an octagonal opening (radius 7.6 m) that sat on the ground.

This copies each stock mesh and adds cap triangles to the existing submesh, in the same
material, vertex layout and bone, so nothing else about the model changes. Only real holes
are capped: the remaining boundary cycles are zero-area T-junction slivers along seams.
Cap winding is the reverse of the boundary walk (outward, matching the neighbouring faces),
the cap normal is flat, and the cap UVs are a planar projection at the mesh's own texel
density, placed on the plain plated-metal panels of hbtran_d.dds (u 0.50-0.67, v 0.11-0.27,
the hull's own plating). Edge lists are dropped (Ogre rebuilds them on demand).

Usage: python Tools/Cap-TransportPieces.py [--models-dir <Redux BZ_ASSETS/common/models>]
Writes Assets/ModelFixes/hbtrn200.mesh and Assets/ModelFixes/hbtran00.mesh.
"""
from pathlib import Path
import argparse
import io
import struct
import sys
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh, ogremesh_serializer

VET_FLOAT2, VET_FLOAT3 = ogremesh.VET.FLOAT2, ogremesh.VET.FLOAT3
VES_POSITION, VES_NORMAL, VES_TEXCOORD = ogremesh.VES.POSITION, ogremesh.VES.NORMAL, ogremesh.VES.TEXTURE_COORDINATES

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MODELS = Path(r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\BZ_ASSETS\common\models")
# Plated-metal panel region of hbtran_d.dds and the UV centre a cap is placed on.
METAL_BOX = (0.50, 0.11, 0.67, 0.27)
METAL_CENTRE = (0.585, 0.19)
MIN_HOLE_AREA = 0.5  # m^2; T-junction slivers are ~0
TARGETS = {"hbtrn200": 1, "hbtran00": 1}  # mesh -> expected number of real holes


def boundary_cycles(pos, tris):
    """Simple cycles of directed boundary edges over position-welded vertices.
    Returns (cycles as lists of welded ids, welded positions, welded id -> first raw index)."""
    keys, weld, first = {}, [], {}
    for i, p in enumerate(pos):
        w = keys.setdefault(tuple(np.round(p, 3)), len(keys))
        weld.append(w)
        first.setdefault(w, i)
    weld = np.array(weld)
    wpos = np.array([pos[first[w]] for w in range(len(keys))])
    count = {}
    for t in weld[tris]:
        for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            count[(min(a, b), max(a, b))] = count.get((min(a, b), max(a, b)), 0) + 1
    out = {}
    for t in weld[tris]:
        for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            if count[(min(a, b), max(a, b))] == 1:
                out.setdefault(int(a), []).append(int(b))
    if any(n > 2 for n in count.values()):
        raise ValueError("non-manifold edge; refusing to cap")
    cycles, used = [], set()

    def walk(path):
        for nxt in out.get(path[-1], []):
            if (path[-1], nxt) in used:
                continue
            if nxt == path[0] and len(path) >= 3:
                return path
            if nxt in path:
                continue
            found = walk(path + [nxt])
            if found:
                return found
        return None

    # Shortest cycles first: slivers (3 edges) consume their edges before the real holes are walked.
    for length_limit in range(3, len(wpos) + 1):
        for a in sorted(out):
            for b in out[a]:
                if (a, b) in used:
                    continue
                c = walk([a, b])
                if c and len(c) <= length_limit:
                    cycles.append(c)
                    used.update(zip(c, c[1:] + c[:1]))
    if sum(len(v) for v in out.values()) != len(used):
        raise ValueError("boundary edges left uncovered by cycles")
    return cycles, wpos, first


def newell(points):
    n = np.zeros(3)
    for p, q in zip(points, np.roll(points, -1, axis=0)):
        n += np.cross(p, q)
    return n


def texel_density(pos, uv, tris):
    a3 = np.linalg.norm(np.cross(pos[tris[:, 1]] - pos[tris[:, 0]], pos[tris[:, 2]] - pos[tris[:, 0]]), axis=1).sum()
    d1, d2 = uv[tris[:, 1]] - uv[tris[:, 0]], uv[tris[:, 2]] - uv[tris[:, 0]]
    a2 = np.abs(d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0]).sum()
    return np.sqrt(a2 / a3)  # UV units per metre


def attr(geom, sem):
    for source, vtype, s, offset, idx in geom["elements"]:
        if s == sem and idx == 0 and vtype in (VET_FLOAT2, VET_FLOAT3):
            size, raw = geom["buffers"][source]
            n = 2 if vtype == VET_FLOAT2 else 3
            arr = np.frombuffer(raw, np.uint8).reshape(geom["count"], size)
            return arr[:, offset:offset + 4 * n].copy().view("<f4").reshape(-1, n).astype(np.float64)
    raise ValueError("missing vertex element %d" % sem)


def cap_mesh(src, dst, expected):
    mesh = ogremesh_serializer.MeshSerializer(io.BytesIO(src.read_bytes())).read()
    if mesh.shared_vertex_data is not None or len(mesh.submesh_list) != 1:
        raise ValueError("%s: expected one submesh with its own geometry" % src.name)
    sub = mesh.submesh_list[0]
    vdata = sub.vertex_data
    geom = {"count": vdata.vertex_count,
            "elements": [(e.source, e.type, e.semantic, e.offset, e.index)
                         for e in vdata.vertex_declaration.vertex_element_list],
            "buffers": {b: (vb.vertex_size, bytes(vb.buffer)) for b, vb in vdata.vertex_buffer_map.items()}}
    pos, nrm, uv = attr(geom, VES_POSITION), attr(geom, VES_NORMAL), attr(geom, VES_TEXCOORD)
    tris = sub.get_index_array().astype(np.int64).reshape(-1, 3)
    ba = {}
    for vba in sub.bone_assignments():
        ba.setdefault(vba.vertex_index, []).append((vba.bone_index, vba.weight))

    cycles, wpos, first = boundary_cycles(pos, tris)
    holes = [c for c in cycles if np.linalg.norm(newell(wpos[c])) / 2 > MIN_HOLE_AREA]
    if len(holes) != expected:
        raise ValueError("%s: found %d real holes, expected %d" % (src.name, len(holes), expected))
    welded = np.array([next(w for w, i in first.items() if np.allclose(pos[i], q, atol=1e-3)) for q in pos])

    buffers = {b: bytearray(raw) for b, (size, raw) in geom["buffers"].items()}
    sizes = {b: size for b, (size, raw) in geom["buffers"].items()}
    elems = geom["elements"]
    new_tris, nv = [], geom["count"]
    report = []
    for hole in holes:
        loop = wpos[hole[::-1]]  # reverse of the boundary walk = outward winding
        n = newell(loop); area = np.linalg.norm(n) / 2; n /= np.linalg.norm(n)
        planar = np.abs((loop - loop.mean(0)) @ n).max()
        if planar > 0.05:
            raise ValueError("%s: hole is not planar (%.3f m)" % (src.name, planar))
        # Planar UVs: u along the longest edge, v across it, at the texel density of the faces
        # that border the hole (shrunk only if the cap would not fit the metal region).
        ring = set(hole)
        border = tris[np.array([sum(int(welded[v]) in ring for v in t) >= 2 for t in tris])]
        density = texel_density(pos, uv, border)
        edges = np.roll(loop, -1, axis=0) - loop
        ax_u = edges[np.argmax(np.linalg.norm(edges, axis=1))]; ax_u /= np.linalg.norm(ax_u)
        ax_v = np.cross(n, ax_u)
        st = np.stack([(loop - loop.mean(0)) @ ax_u, (loop - loop.mean(0)) @ ax_v], 1) * density
        st -= (st.min(0) + st.max(0)) / 2
        room = np.array([METAL_BOX[2] - METAL_BOX[0], METAL_BOX[3] - METAL_BOX[1]]) * 0.95
        fit = min(1.0, (room / (st.max(0) - st.min(0))).min())
        st *= fit
        cap_uv = st + np.array(METAL_CENTRE)
        if (cap_uv.min(0) < METAL_BOX[:2]).any() or (cap_uv.max(0) > METAL_BOX[2:]).any():
            raise ValueError("%s: cap UVs leave the plated-metal region" % src.name)
        base = nv
        for k, w in enumerate(hole[::-1]):
            raw = first[w]  # copy colour and bone assignment from the matching boundary vertex
            for b, size in sizes.items():
                rec = bytearray(buffers[b][raw * size:(raw + 1) * size])
                for source, vtype, s, offset, idx in elems:
                    if source != b:
                        continue
                    if s == VES_POSITION:
                        rec[offset:offset + 12] = struct.pack("<3f", *loop[k])
                    elif s == VES_NORMAL:
                        rec[offset:offset + 12] = struct.pack("<3f", *n)
                    elif s == VES_TEXCOORD and idx == 0:
                        rec[offset:offset + 8] = struct.pack("<2f", *cap_uv[k])
                buffers[b] += rec
            ba[nv] = list(ba.get(raw, []))
            nv += 1
        new_tris += [(base, base + k, base + k + 1) for k in range(1, len(hole) - 1)]
        report.append("%d-gon %.1f m^2, normal (%.2f, %.2f, %.2f), %.4f UV/m%s" % (
            len(hole), area, *n, density * fit, "" if fit == 1 else " (border %.4f, shrunk to fit)" % density))

    all_tris = np.vstack([tris, np.array(new_tris)])
    # Closed-mesh sanity: with outward (CCW) winding the signed volume is positive.
    P = np.vstack([pos, np.array([struct.unpack_from("<3f", buffers[0], i * sizes[0]) for i in range(geom["count"], nv)])])
    vol = np.einsum("ij,ij->i", P[all_tris[:, 0]], np.cross(P[all_tris[:, 1]], P[all_tris[:, 2]])).sum() / 6
    if vol <= 0:
        raise ValueError("%s: capped mesh has non-positive volume %.2f (winding)" % (src.name, vol))

    # Same material/flags and vertex layout, longer index list and vertex buffers. Edge lists are dropped.
    big = nv > 65535
    idx = all_tris.reshape(-1).astype("<u4" if big else "<u2")
    sub.indices_32_bit, sub.index_count = big, len(idx)
    sub.set_index_buffer(idx.tobytes())
    vdata.set_vertex_count(nv)
    for b, vb in vdata.vertex_buffer_map.items():
        vb.set_buffer(bytes(buffers[b]))
    sub.clear_bone_assignments()
    for vi in sorted(ba):
        for bone, w in ba[vi]:
            sub.create_bone_assignment(vi, bone, w)
    mesh.edge_lists = {}
    out = io.BytesIO()
    ogremesh_serializer.MeshSerializer(out).write(mesh)
    dst.write_bytes(out.getvalue())
    print("%s: %d -> %d tris, %d -> %d verts, volume %.0f m^3; %s" % (
        dst.name, len(tris), len(all_tris), geom["count"], nv, vol, "; ".join(report)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--models-dir", type=Path, default=DEFAULT_MODELS)
    ap.add_argument("--out-dir", type=Path, default=ROOT / "Assets/ModelFixes")
    a = ap.parse_args()
    for name, expected in TARGETS.items():
        cap_mesh(a.models_dir / (name + ".mesh"), a.out_dir / (name + ".mesh"), expected)


if __name__ == "__main__":
    main()
