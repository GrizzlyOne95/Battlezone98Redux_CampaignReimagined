#!/usr/bin/env python3
"""Stock Redux vertex layout for skinned Ogre meshes.

    python Tools/ogrelayout.py --check               # exit 1 if a skinned mesh mixes streams
    python Tools/ogrelayout.py --fix PATH ...        # rewrite those meshes in place

Stock craft meshes keep source 0 = POSITION NORMAL and source 1 = DIFFUSE
TEXCOORD0 [TANGENT]. A skinned submesh that keeps its UVs (or tangents) in the
POSITION/NORMAL buffer draws one flat colour in game: measured live 2026-10-26,
when every CR-built cockpit drew flat grey until this split alone fixed it.
The likely cause is Ogre software skinning, which blends into an uninitialised
copy of the POSITION/NORMAL buffer and rewrites only those two elements.

Every CR tool that writes a skinned mesh goes through this module, and the
binary converter below produces the same bytes the serializer writes for the
same vertices, so a rebuilt asset matches a converted one.
"""
from pathlib import Path
import struct, sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]

VET_FLOAT2, VET_FLOAT3, VET_COLOUR_ARGB = 1, 2, 10
VES_POSITION, VES_NORMAL, VES_DIFFUSE, VES_TEXCOORD, VES_TANGENT = 1, 4, 5, 7, 9
VET_SIZE = {0: 4, 1: 8, 2: 12, 3: 16, 4: 4, 5: 2, 6: 4, 7: 6, 8: 8, 9: 4, 10: 4, 11: 4}
WHITE = 0xFFFFFFFF

M_MESH, M_SUBMESH, M_SUBMESH_BONE_ASSIGNMENT = 0x3000, 0x4000, 0x4100
M_GEOMETRY, M_DECLARATION, M_ELEMENT = 0x5000, 0x5100, 0x5110
M_BUFFER, M_BUFFER_DATA = 0x5200, 0x5210
M_SKELETON_LINK, M_MESH_BONE_ASSIGNMENT = 0x6000, 0x7000


def stock_layout(rows):
    """Split float rows [position3 normal3 uv2 (tangent3)] into the stock two-stream layout.
    Returns (elements, buffers): elements are (source, type, semantic, offset) in
    declaration order, buffers are (bind, stride, bytes) in bind order."""
    rows = np.asarray(rows, dtype="<f4")
    if rows.ndim != 2 or rows.shape[1] not in (8, 11):
        raise ValueError("expected position, normal, uv and optional tangent columns")
    elements = [(0, VET_FLOAT3, VES_POSITION, 0), (0, VET_FLOAT3, VES_NORMAL, 12),
                (1, VET_COLOUR_ARGB, VES_DIFFUSE, 0), (1, VET_FLOAT2, VES_TEXCOORD, 4)]
    if rows.shape[1] == 11:
        elements.append((1, VET_FLOAT3, VES_TANGENT, 12))
    s0 = np.ascontiguousarray(rows[:, :6])
    s1 = np.empty((len(rows), rows.shape[1] - 5), dtype="<u4")
    s1[:, 0] = WHITE
    s1[:, 1:] = rows[:, 6:].view("<u4")
    return elements, [(0, 24, s0.tobytes()), (1, s1.shape[1] * 4, s1.tobytes())]


def fill_vertex_data(vertex_data, rows):
    """Declare and fill a bzmodellibs VertexData in the stock layout."""
    elements, buffers = stock_layout(rows)
    for source, vtype, semantic, offset in elements:
        vertex_data.vertex_declaration.create_vertex_element(source, vtype, semantic, offset, 0)
    for bind, stride, data in buffers:
        vertex_data.create_vertex_buffer(data, bind, stride)


def chunk(cid, body):
    return struct.pack("<HI", cid, len(body) + 6) + body


def geometry_chunk(rows):
    """M_GEOMETRY chunk in the stock layout, as the bzmodellibs serializer writes it."""
    elements, buffers = stock_layout(rows)
    return _geometry_chunk(len(rows), [e + (0,) for e in elements], buffers)


def _geometry_chunk(count, elements, buffers):
    decl = b"".join(chunk(M_ELEMENT, struct.pack("<5H", *e)) for e in elements)
    body = struct.pack("<I", count) + chunk(M_DECLARATION, decl)
    for bind, stride, data in buffers:
        body += chunk(M_BUFFER, struct.pack("<2H", bind, stride) + chunk(M_BUFFER_DATA, data))
    return chunk(M_GEOMETRY, body)


def _chunks(data, start, end):
    p = start
    while p < end:
        cid, length = struct.unpack_from("<HI", data, p)
        if length < 6 or p + length > end:
            raise ValueError("bad chunk 0x%04x at %d" % (cid, p))
        yield cid, p + 6, p + length
        p += length


def _geometry(data, start, end):
    count = struct.unpack_from("<I", data, start)[0]
    elements, buffers = [], {}
    for cid, cs, ce in _chunks(data, start + 4, end):
        if cid == M_DECLARATION:
            elements = [struct.unpack_from("<5H", data, es) for eid, es, ee in _chunks(data, cs, ce) if eid == M_ELEMENT]
        elif cid == M_BUFFER:
            bind, stride = struct.unpack_from("<2H", data, cs)
            (_, ds, de), = [c for c in _chunks(data, cs + 4, ce) if c[0] == M_BUFFER_DATA]
            buffers[bind] = (stride, data[ds:de])
    return count, elements, buffers


def _mixed(elements):
    """True when the POSITION/NORMAL source also carries another element."""
    sources = {e[0] for e in elements if e[2] in (VES_POSITION, VES_NORMAL)}
    return any(e[0] in sources and e[2] not in (VES_POSITION, VES_NORMAL) for e in elements)


def _restream(count, elements, buffers):
    """Single-source geometry -> stock layout chunk: POSITION NORMAL stay in source 0; source 1
    starts with the vertex colour (white ARGB when there is none) and keeps every other element
    in declaration order. For [position normal uv tangent] this is exactly stock_layout."""
    if len({e[0] for e in elements}) != 1:
        raise ValueError("unsupported mixed layout %r" % (elements,))
    stride, raw = buffers[elements[0][0]]
    flat = np.frombuffer(raw, dtype="u1").reshape(count, stride)
    first = [e for e in elements if e[2] in (VES_POSITION, VES_NORMAL)]
    colour = [e for e in elements if e[2] == VES_DIFFUSE and e[4] == 0][:1]
    second = colour + [e for e in elements if e not in first and e not in colour]
    out_elements, out_buffers = [], []
    for source, group in ((0, first), (1, second)):
        columns, offset = [], 0
        if source == 1 and not colour:
            columns.append(np.full((count, 4), 0xFF, dtype="u1"))
            out_elements.append((1, VET_COLOUR_ARGB, VES_DIFFUSE, 0, 0))
            offset = 4
        for e in group:
            columns.append(flat[:, e[3]:e[3] + VET_SIZE[e[1]]])
            out_elements.append((source, e[1], e[2], offset, e[4]))
            offset += VET_SIZE[e[1]]
        out_buffers.append((source, offset, np.ascontiguousarray(np.hstack(columns)).tobytes()))
    return _geometry_chunk(count, out_elements, out_buffers)


def _scan(data):
    """Yield (material, skinned, geometry start, geometry end) for every submesh geometry."""
    if data[:2] != b"\x00\x10":
        raise ValueError("not a binary Ogre mesh")
    header_end = data.index(b"\n", 2) + 1
    for cid, cs, ce in _chunks(data, header_end, len(data)):
        if cid != M_MESH:
            continue
        children = list(_chunks(data, cs + 1, ce))
        skinned = any(c[0] in (M_SKELETON_LINK, M_MESH_BONE_ASSIGNMENT) for c in children)
        for sid, ss, se in children:
            if sid == M_GEOMETRY:
                yield "<shared>", skinned, ss, se
            if sid != M_SUBMESH:
                continue
            name_end = data.index(b"\n", ss)
            material = data[ss:name_end].decode("latin-1")
            count, wide = struct.unpack_from("<I?", data, name_end + 2)
            indices_end = name_end + 7 + count * (4 if wide else 2)
            subs = list(_chunks(data, indices_end, se))
            bones = skinned or any(c[0] == M_SUBMESH_BONE_ASSIGNMENT for c in subs)
            for gid, gs, ge in subs:
                if gid == M_GEOMETRY:
                    yield material, bones, gs, ge


def mixed_skinned_submeshes(data):
    """Materials of skinned submeshes that keep other elements in the POSITION/NORMAL source."""
    return [m for m, skinned, gs, ge in _scan(data) if skinned and _mixed(_geometry(data, gs, ge)[1])]


def convert(data):
    """Rewrite every mixed skinned submesh geometry in the stock layout, rebuilding the
    enclosing chunks so their lengths stay right; other bytes are kept.
    Returns (new bytes, number of geometries rewritten)."""
    if data[:2] != b"\x00\x10":
        raise ValueError("not a binary Ogre mesh")
    header_end = data.index(b"\n", 2) + 1
    out = bytearray(data[:header_end])
    changed = 0
    for cid, cs, ce in _chunks(data, header_end, len(data)):
        if cid != M_MESH:
            out += data[cs - 6:ce]
            continue
        children = list(_chunks(data, cs + 1, ce))
        skinned = any(c[0] in (M_SKELETON_LINK, M_MESH_BONE_ASSIGNMENT) for c in children)
        body = bytearray(data[cs:cs + 1])
        for sid, ss, se in children:
            if sid == M_GEOMETRY and skinned and _mixed(_geometry(data, ss, se)[1]):
                raise ValueError("shared geometry with a mixed layout is not handled")
            if sid != M_SUBMESH:
                body += data[ss - 6:se]
                continue
            name_end = data.index(b"\n", ss)
            count, wide = struct.unpack_from("<I?", data, name_end + 2)
            indices_end = name_end + 7 + count * (4 if wide else 2)
            subs = list(_chunks(data, indices_end, se))
            bones = skinned or any(c[0] == M_SUBMESH_BONE_ASSIGNMENT for c in subs)
            sub = bytearray(data[ss:indices_end])
            for gid, gs, ge in subs:
                geometry = _geometry(data, gs, ge) if gid == M_GEOMETRY else None
                if geometry and bones and _mixed(geometry[1]):
                    sub += _restream(*geometry)
                    changed += 1
                else:
                    sub += data[gs - 6:ge]
            body += chunk(M_SUBMESH, bytes(sub))
        out += chunk(M_MESH, bytes(body))
    return bytes(out), changed


def mesh_paths():
    for folder in ("Assets", "References"):
        yield from sorted((ROOT / folder).rglob("*.mesh"))


def main(argv):
    if argv[:1] == ["--fix"]:
        for name in argv[1:]:
            path = Path(name)
            data, changed = convert(path.read_bytes())
            if changed:
                path.write_bytes(data)
            print("%s: %d geometries rewritten" % (path, changed))
        return 0
    if argv != ["--check"]:
        print(__doc__.strip().splitlines()[2])
        print(__doc__.strip().splitlines()[3])
        return 2
    bad = 0
    for path in mesh_paths():
        try:
            mixed = mixed_skinned_submeshes(path.read_bytes())
        except ValueError:
            continue  # XML or non-mesh payloads are not in scope
        if mixed:
            bad += 1
            print("mixed skinned layout: %s (%s)" % (path.relative_to(ROOT).as_posix(), ", ".join(mixed)))
    print("SKINNED_VERTEX_LAYOUT_%s %d" % ("FAIL" if bad else "PASS", bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
