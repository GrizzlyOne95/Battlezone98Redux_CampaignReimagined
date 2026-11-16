"""Give skinned-mesh vertices that have no bone assignment their neighbours' weights.

Ogre skins a vertex with no assignment to the entity origin (it logs "includes
vertices without bone assignments"), so a triangle that uses one stretches down
to the model's base. Several stock meshes ship such vertices and CR's
re-exports inherited them (BZ98RBlenderToolKit fix_mesh_normals.py copies
weights but does not invent them), so rerun this after regenerating meshes.

Each unweighted vertex used by a triangle copies the assignments of its
closest weighted triangle neighbour, repeated until nothing changes; a vertex
with no weighted neighbour copies the nearest weighted vertex. Meshes are read
and written only through the toolkit serializer (Tools/bzmodellibs.py).

    python Tools/fix_unweighted_vertices.py Assets/ModelFixes/cblpad.mesh ...
    python Tools/fix_unweighted_vertices.py --check Assets   # exit 1 if any
"""
from __future__ import annotations

import argparse
import io
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bzmodellibs  # noqa: E402

ser = bzmodellibs.ogremesh_serializer


def _positions(vertex_data):
    element = vertex_data.vertex_declaration.get_position_vertex_element()
    buffer = vertex_data.get_vertex_buffer(element.source)
    raw = bytes(buffer.get_buffer())
    return [struct.unpack_from("<3f", raw, i * buffer.vertex_size + element.offset)
            for i in range(vertex_data.vertex_count)]


def _dist2(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b))


def _fix_group(owner, amap, vertex_data, submeshes, apply):
    """owner: Mesh (shared vertices) or SubMesh; returns the vertices fixed."""
    neighbours = {}
    used = set()
    for sm in submeshes:
        if sm.operation_type != 4:  # OT_TRIANGLE_LIST; strips/fans would misread neighbours
            raise SystemExit(f"submesh {sm.submesh_index}: operation type {sm.operation_type} not supported")
        idx = [int(x) for x in sm.get_index_array()]
        for t in range(0, len(idx) - 2, 3):
            tri = idx[t:t + 3]
            used.update(tri)
            for v in tri:
                neighbours.setdefault(v, set()).update(u for u in tri if u != v)
    missing = sorted(v for v in used if not amap.get(v))
    if not missing:
        return []
    pos = _positions(vertex_data)
    weights = {v: [(a.bone_index, a.weight) for a in amap[v]] for v in amap if amap[v]}
    pending = set(missing)
    while pending:
        progressed = False
        for v in sorted(pending):
            donors = [u for u in neighbours.get(v, ()) if u in weights]
            if donors:
                weights[v] = weights[min(donors, key=lambda u: _dist2(pos[v], pos[u]))]
                pending.discard(v)
                progressed = True
        if not progressed:
            donors = [u for u in weights if u not in pending]
            if not donors:
                print("warning: no weighted vertex to copy from; group left as is", file=sys.stderr)
                return []
            for v in sorted(pending):
                weights[v] = weights[min(donors, key=lambda u: _dist2(pos[v], pos[u]))]
            pending.clear()
    if apply:
        for v in missing:
            for bone, weight in weights[v]:
                owner.create_bone_assignment(v, bone, weight)
    return missing


def process(path: Path, apply: bool):
    raw = path.read_bytes()
    reader = ser.MeshSerializer(io.BytesIO(raw))
    mesh = reader.read()
    if not mesh.skeleton_name:
        return []
    found = []
    shared = [sm for sm in mesh.submesh_list if sm.use_shared_vertices]
    if shared and mesh.shared_vertex_data and mesh.bone_assignment_map:
        fixed = _fix_group(mesh, mesh.bone_assignment_map, mesh.shared_vertex_data, shared, apply)
        if fixed:
            found.append(("shared", fixed))
    for sm in mesh.submesh_list:
        # A submesh with no assignments at all is left alone: nothing to copy from.
        if sm.use_shared_vertices or not sm.vertex_data or not sm.bone_assignment_map:
            continue
        fixed = _fix_group(sm, sm.bone_assignment_map, sm.vertex_data, [sm], apply)
        if fixed:
            found.append((f"sub{sm.submesh_index} {sm.material_name}", fixed))
    if apply and found:
        out = io.BytesIO()
        ser.MeshSerializer(out).write(mesh, version=reader.version)
        path.write_bytes(out.getvalue())
    return found


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", type=Path, help=".mesh files or folders to search")
    ap.add_argument("--check", action="store_true", help="report only; exit 1 if any vertex needs fixing")
    args = ap.parse_args()
    files = []
    for p in args.paths:
        files.extend(sorted(p.rglob("*.mesh")) if p.is_dir() else [p])
    total = 0
    for f in files:
        for group, verts in process(f, apply=not args.check):
            total += len(verts)
            print(f"{f}: {group}: {len(verts)} unweighted vertices {'found' if args.check else 'fixed'}")
    print(f"{len(files)} meshes, {total} vertices {'need fixing' if args.check else 'fixed'}")
    return 1 if args.check and total else 0


if __name__ == "__main__":
    raise SystemExit(main())
