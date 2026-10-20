"""Minimal Ogre 1.10 binary .mesh / .skeleton reader and submesh appender.

Used by Tools/cockpitglass.py. Reads what the cockpit-glass tool needs (submesh
materials, positions, triangles, bone assignments; bones and their bind pose)
and rewrites a mesh with one extra submesh appended, copying every other chunk
byte for byte. Only [MeshSerializer_v1.100] meshes (every stock BZR and ISDFC mesh; the odd v1.8 file is refused) and
[Serializer_v1.80] / [Serializer_v1.10] skeletons are handled.

Chunk layout (OgreMeshSerializerImpl.cpp, Ogre 1.10): u16 id, u32 length
(including the 6-byte header); strings end in '\n'.
"""
# TODO(toolkit gap): remaining hand-rolled .mesh/.skeleton parsing, kept only because Tools/cockpitglass.py
# (owned by branch agent/cockpit-fixes) still imports ogrebin.Mesh/Skeleton. The serializer limits that blocked
# a port (bone assignments re-sorted, LOD levels/poses/animations dropped) are fixed upstream in BZ98RBlenderToolKit
# PR #19 (preserve_bone_assignment_order, raw_chunks); replace this module with ogremesh/ogreskeleton when
# cockpitglass is migrated.
import struct
import numpy as np

M_HEADER = 0x1000
M_MESH = 0x3000
M_SUBMESH = 0x4000
M_SUBMESH_OPERATION = 0x4010
M_SUBMESH_BONE_ASSIGNMENT = 0x4100
M_SUBMESH_TEXTURE_ALIAS = 0x4200
M_GEOMETRY = 0x5000
M_GEOMETRY_VERTEX_DECLARATION = 0x5100
M_GEOMETRY_VERTEX_ELEMENT = 0x5110
M_GEOMETRY_VERTEX_BUFFER = 0x5200
M_GEOMETRY_VERTEX_BUFFER_DATA = 0x5210
M_MESH_SKELETON_LINK = 0x6000
M_MESH_BONE_ASSIGNMENT = 0x7000
M_MESH_LOD_LEVEL = 0x8000
M_MESH_BOUNDS = 0x9000
M_SUBMESH_NAME_TABLE = 0xA000
M_SUBMESH_NAME_TABLE_ELEMENT = 0xA100
M_EDGE_LISTS = 0xB000

VET_FLOAT2, VET_FLOAT3 = 1, 2
VES_POSITION, VES_NORMAL, VES_TEXCOORD = 1, 4, 7
VET_SIZE = {0: 4, 1: 8, 2: 12, 3: 16, 4: 4, 5: 2, 6: 4, 7: 6, 8: 8, 9: 4, 10: 4, 11: 4}

MESH_VERSION = b"[MeshSerializer_v1.100]"


class Reader:
    def __init__(self, data, pos=0, end=None):
        self.d, self.p = data, pos
        self.end = len(data) if end is None else end

    def u16(self):
        v = struct.unpack_from("<H", self.d, self.p)[0]; self.p += 2; return v

    def u32(self):
        v = struct.unpack_from("<I", self.d, self.p)[0]; self.p += 4; return v

    def b(self):
        v = self.d[self.p] != 0; self.p += 1; return v

    def f(self, n):
        v = struct.unpack_from("<%df" % n, self.d, self.p); self.p += 4 * n; return v

    def s(self):
        i = self.d.index(b"\n", self.p)
        v = self.d[self.p:i].decode("latin-1"); self.p = i + 1; return v

    def chunk(self):
        """(id, start, end) of the chunk at the cursor; the cursor moves past the header."""
        start = self.p
        cid = self.u16(); ln = self.u32()
        return cid, start, start + ln

    def more(self):
        return self.p + 6 <= self.end


def chunks(data, start, end):
    """Every chunk header in [start, end): (id, start, end)."""
    out, p = [], start
    while p + 6 <= end:
        cid, ln = struct.unpack_from("<HI", data, p)
        if ln < 6 or p + ln > end:
            break
        out.append((cid, p, p + ln))
        p += ln
    return out


def _read_geometry(data, start, end):
    """M_GEOMETRY chunk body -> dict(count, elements, buffers{bind: (size, bytes)})."""
    r = Reader(data, start + 6, end)
    count = r.u32()
    elements, buffers = [], {}
    for cid, cs, ce in chunks(data, r.p, end):
        if cid == M_GEOMETRY_VERTEX_DECLARATION:
            for eid, es, ee in chunks(data, cs + 6, ce):
                if eid == M_GEOMETRY_VERTEX_ELEMENT:
                    elements.append(struct.unpack_from("<5H", data, es + 6))
        elif cid == M_GEOMETRY_VERTEX_BUFFER:
            bind, size = struct.unpack_from("<2H", data, cs + 6)
            for did, ds, de in chunks(data, cs + 10, ce):
                if did == M_GEOMETRY_VERTEX_BUFFER_DATA:
                    buffers[bind] = (size, data[ds + 6:de])
    return {"count": count, "elements": elements, "buffers": buffers}


def _attribute(geom, semantic, index=0):
    """float array (count, n) of a FLOAT2/FLOAT3 attribute, or None."""
    for source, vtype, sem, offset, idx in geom["elements"]:
        if sem == semantic and idx == index and vtype in (VET_FLOAT2, VET_FLOAT3):
            size, raw = geom["buffers"][source]
            n = 2 if vtype == VET_FLOAT2 else 3
            arr = np.frombuffer(raw, dtype=np.uint8).reshape(geom["count"], size)
            return arr[:, offset:offset + 4 * n].copy().view("<f4").reshape(geom["count"], n).astype(np.float64)
    return None


class Mesh:
    """Parsed view of a v1.100 mesh: .submeshes[i] = dict(material, shared, tris, positions,
    bones (count,) dominant bone handle or -1), plus the raw chunk list for rewriting."""

    def __init__(self, path):
        self.path = path
        self.data = data = open(path, "rb").read()
        r = Reader(data)
        if r.u16() != M_HEADER:
            raise ValueError("not an Ogre mesh")
        self.version = r.s()
        if self.version != MESH_VERSION.decode():
            raise ValueError("unsupported mesh version " + self.version)
        self.header_end = r.p
        cid, ms, me = r.chunk()
        if cid != M_MESH:
            raise ValueError("no M_MESH chunk")
        self.mesh_start, self.mesh_end = ms, me
        self.skeletal = r.b()
        self.body_start = r.p
        self.children = chunks(data, r.p, me)
        self.tail = data[me:]
        self.shared = None
        self.shared_ba = []
        self.submeshes = []
        self.skeleton = None
        for cid, cs, ce in self.children:
            if cid == M_GEOMETRY:
                self.shared = _read_geometry(data, cs, ce)
            elif cid == M_MESH_SKELETON_LINK:
                self.skeleton = Reader(data, cs + 6, ce).s()
            elif cid == M_MESH_BONE_ASSIGNMENT:
                self.shared_ba.append(struct.unpack_from("<IHf", data, cs + 6))
        for cid, cs, ce in self.children:
            if cid == M_SUBMESH:
                self.submeshes.append(self._read_submesh(cs, ce))
        self.lod = any(c[0] == M_MESH_LOD_LEVEL for c in self.children)

    def _read_submesh(self, cs, ce):
        data = self.data
        r = Reader(data, cs + 6, ce)
        material = r.s()
        shared = r.b()
        n = r.u32()
        idx32 = r.b()
        if idx32:
            idx = np.frombuffer(data, "<u4", n, r.p).astype(np.int64); r.p += 4 * n
        else:
            idx = np.frombuffer(data, "<u2", n, r.p).astype(np.int64); r.p += 2 * n
        geom, ba, op = None, [], 4
        for cid, s, e in chunks(data, r.p, ce):
            if cid == M_GEOMETRY:
                geom = _read_geometry(data, s, e)
            elif cid == M_SUBMESH_BONE_ASSIGNMENT:
                ba.append(struct.unpack_from("<IHf", data, s + 6))
            elif cid == M_SUBMESH_OPERATION:
                op = struct.unpack_from("<H", data, s + 6)[0]
        g = self.shared if shared else geom
        ba = self.shared_ba if shared else ba
        pos = _attribute(g, VES_POSITION) if g else None
        count = g["count"] if g else 0
        dom = np.full(count, -1, dtype=np.int64)
        best = np.zeros(count)
        for vi, bone, w in ba:
            if vi < count and w > best[vi]:
                best[vi], dom[vi] = w, bone
        tris = idx.reshape(-1, 3) if op == 4 and len(idx) % 3 == 0 else np.zeros((0, 3), np.int64)
        return {"material": material, "shared": shared, "tris": tris, "positions": pos, "bones": dom,
                "chunk": (cs, ce)}

    def write_with_submesh(self, out_path, material, positions, normals, uvs, tris, bone,
                           drop_material=None):
        """Write the mesh with one submesh appended (and any submesh whose material is
        drop_material removed first). Drops edge lists (Ogre rebuilds them on demand) and
        grows the bounds to cover the new vertices. Refuses meshes with LOD levels."""
        if self.lod:
            raise ValueError("mesh has LOD levels; appending a submesh would desync them")
        data = self.data
        sub_index = 0
        dropped = []
        kept = []
        for cid, cs, ce in self.children:
            if cid == M_SUBMESH:
                mat = Reader(data, cs + 6, ce).s()
                if drop_material is not None and mat == drop_material:
                    dropped.append(sub_index)
                    sub_index += 1
                    continue
                sub_index += 1
            kept.append((cid, cs, ce))
        if dropped and dropped != list(range(sub_index - len(dropped), sub_index)):
            raise ValueError("an old glass submesh is not last; refusing to renumber submeshes")
        n_sub = sub_index - len(dropped)
        new_sub = build_submesh(material, positions, normals, uvs, tris, bone)
        body = bytearray()
        inserted = False
        last_sub = max((i for i, c in enumerate(kept) if c[0] == M_SUBMESH), default=-1)
        for i, (cid, cs, ce) in enumerate(kept):
            if cid == M_EDGE_LISTS:
                continue
            if cid == M_MESH_BOUNDS:
                mn = np.array(struct.unpack_from("<3f", data, cs + 6))
                mx = np.array(struct.unpack_from("<3f", data, cs + 18))
                rad = struct.unpack_from("<f", data, cs + 30)[0]
                mn = np.minimum(mn, positions.min(0)); mx = np.maximum(mx, positions.max(0))
                rad = max(rad, float(np.linalg.norm(positions, axis=1).max()))
                body += chunk(M_MESH_BOUNDS, struct.pack("<7f", *mn, *mx, rad))
            elif cid == M_SUBMESH_NAME_TABLE:
                elems = []
                for eid, es, ee in chunks(data, cs + 6, ce):
                    if eid == M_SUBMESH_NAME_TABLE_ELEMENT:
                        r = Reader(data, es + 6, ee)
                        k = r.u16()
                        if k < n_sub:
                            elems.append(data[es:ee])
                body += chunk(M_SUBMESH_NAME_TABLE, b"".join(elems))
            else:
                body += data[cs:ce]
            if i == last_sub:
                body += new_sub
                inserted = True
        if not inserted:
            body = new_sub + body
        mesh_body = bytes([1 if self.skeletal else 0]) + bytes(body)
        out = data[:self.header_end] + chunk(M_MESH, mesh_body) + self.tail
        open(out_path, "wb").write(out)
        return n_sub  # index of the appended submesh


def chunk(cid, body):
    return struct.pack("<HI", cid, len(body) + 6) + body


def build_submesh(material, positions, normals, uvs, tris, bone):
    """M_SUBMESH chunk: own geometry (POSITION, NORMAL, TEXCOORD0 in one buffer), 16-bit
    triangle list, every vertex bound to `bone` with weight 1."""
    nv = len(positions)
    if nv >= 65536:
        raise ValueError("too many glass vertices for 16-bit indices")
    idx = np.asarray(tris, dtype="<u2").reshape(-1)
    head = material.encode("latin-1") + b"\n" + struct.pack("<?I?", False, len(idx), False) + idx.tobytes()
    decl = b"".join(chunk(M_GEOMETRY_VERTEX_ELEMENT, struct.pack("<5H", *e)) for e in (
        (0, VET_FLOAT3, VES_POSITION, 0, 0), (0, VET_FLOAT3, VES_NORMAL, 12, 0), (0, VET_FLOAT2, VES_TEXCOORD, 24, 0)))
    verts = np.hstack([positions, normals, uvs]).astype("<f4")
    vbuf = struct.pack("<2H", 0, 32) + chunk(M_GEOMETRY_VERTEX_BUFFER_DATA, verts.tobytes())
    geom = chunk(M_GEOMETRY, struct.pack("<I", nv) + chunk(M_GEOMETRY_VERTEX_DECLARATION, decl)
                 + chunk(M_GEOMETRY_VERTEX_BUFFER, vbuf))
    op = chunk(M_SUBMESH_OPERATION, struct.pack("<H", 4))
    ba = b"".join(chunk(M_SUBMESH_BONE_ASSIGNMENT, struct.pack("<IHf", i, bone, 1.0)) for i in range(nv))
    return chunk(M_SUBMESH, head + geom + op + ba)


def quat_matrix(x, y, z, w):
    n = np.sqrt(x * x + y * y + z * z + w * w) or 1.0
    x, y, z, w = x / n, y / n, z / n, w / n
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


class Skeleton:
    """Bones by handle: name, parent, local (t, R, s) and bind world (t, R)."""

    def __init__(self, path):
        data = open(path, "rb").read()
        r = Reader(data)
        if r.u16() != M_HEADER:
            raise ValueError("not an Ogre skeleton")
        self.version = r.s()
        self.names, self.parent, self.local = {}, {}, {}
        # SkeletonSerializer's bone chunk length leaves out the name (calcBoneSize*), so a
        # bone spans length + len(name) + 1; the reader tells scale from length > 36.
        p = r.p
        while p + 6 <= len(data):
            cid, ln = struct.unpack_from("<HI", data, p)
            if cid == 0x2000:
                b = Reader(data, p + 6)
                name = b.s(); h = b.u16()
                t = np.array(b.f(3)); q = b.f(4)
                s = np.array(b.f(3)) if ln > 36 else np.ones(3)
                self.names[h] = name
                self.local[h] = (t, quat_matrix(*q), s)
                p = b.p
            elif cid == 0x3000:
                c, par = struct.unpack_from("<2H", data, p + 6)
                self.parent[c] = par
                p += ln
            elif cid == 0x1010 and ln >= 6:
                p += ln
            else:
                break   # animations: not needed
        self.handle = {n: h for h, n in self.names.items()}
        self.world = {}
        for h in self.names:
            self._world(h)

    def _world(self, h):
        if h in self.world:
            return self.world[h]
        t, R, s = self.local[h]
        if h in self.parent:
            pt, pR = self._world(self.parent[h])
            t, R = pt + pR @ t, pR @ R
        self.world[h] = (t, R)
        return self.world[h]
