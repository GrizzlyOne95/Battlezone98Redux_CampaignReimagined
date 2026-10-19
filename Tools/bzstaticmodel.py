"""Author the static-building SDF and Ogre mesh records CR's build tools emit.

A thin layer over the shared libraries (see ``bzmodellibs``): every byte is
written by BZ98RBlenderToolKit's serializers, none by hand. The record layout
matches the files the tools used to assemble themselves (a one-part SDFC/SGEO
"WORLD"-parented static object with five unused NULL LOD/rep slots and two
trailing EXIT chunks), so rebuilt output stays byte-identical.
"""

from __future__ import annotations

import io
import math

from bzmodellibs import bwd2, bwd2_serializer

_CR_REVISION = 8
_STATIC_CLASS_ID = 60
_NULL_ARGS = dict(class_id=0)


def static_sdf_bytes(
    name: str, center, half, radius: float, *, null_parent: str = "", template: bytes | None = None
) -> bytes:
    """One-part static SDF named `name` with the given bounds.

    ``null_parent`` is stored in the five unused slots; the NSDF/CCA scripts
    leave it empty, the Misn17 crystals store "NULL". ``template`` is a stock
    SDF (Misn17 uses ``obdata.sdf``): its header (BWD2, REV, SDFC, any EXITs
    before SGEO) is kept and only the parts are replaced. Without one the
    header is CR's own (revision 8, "xbldx1.xdf" death animation).
    """
    if template is not None:
        sdf = bwd2_serializer.SDFSerializer(io.BytesIO(template)).read()
        sdf.object_list = [[[] for _ in reps] for reps in sdf.object_list]
        sdf.objcount = 0
        sdf.obj_namemap = {}
        sdf.anim_obj = None
        sdf.sgeo_trailing_bytes = b""
    else:
        sdf = bwd2.SDF()
        sdf.revision = _CR_REVISION
        sdf.name = name
        sdf.struct_class = 1
        sdf.lod_dist_list[:] = [2000.0, 1e20, 1e20, 1e20, 1e20]
        sdf.ddr = 0
        sdf.death_animation_width = 14
        sdf.death_animation = "xbldx1.xdf"
        sdf.death_audio = "null"
        sdf.exit_count_after_sdfc = 0
    sdf.exit_count = 2
    part = sdf.append_object(name, parent="WORLD")
    part.transform = bwd2.Transform()
    part.center_pos = bwd2.Vector3(*center)
    part.half_size = bwd2.Vector3(*half)
    part.radius = float(radius)
    part.class_id = _STATIC_CLASS_ID
    for slot in sdf.all_geo_objects(raw=True):
        if slot is not part:
            slot.make_null(**_NULL_ARGS)
            slot.parent = null_parent
    out = io.BytesIO()
    bwd2_serializer.SDFSerializer(out).write(sdf)
    return out.getvalue()


def mesh_bounds(rows):
    """(lo, hi, radius) of the positions (the first three columns) in `rows`."""
    points = [row[:3] for row in rows]
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    radius = max(math.sqrt(sum(x * x for x in p)) for p in points)
    return lo, hi, radius


def static_mesh_bytes(material: str, rows, indices, *, tangents: bool = False) -> bytes:
    """One-submesh, unskinned Ogre ``.mesh`` (serializer v1.100) as the Redux assets use it.

    `rows` are (x, y, z, nx, ny, nz, u, v[, tx, ty, tz]) per vertex, with
    ``tangents`` set when the last three columns are present. The mesh carries
    no SUBMESH_NAME_TABLE and its bounds come from the positions.
    """
    import numpy as np

    from bzmodellibs import ogremesh as om, ogremesh_serializer as oms

    width = 11 if tangents else 8
    data = np.array(rows, dtype="<f4").reshape(-1, width)
    lo, hi, radius = mesh_bounds(rows)
    mesh = om.Mesh()
    mesh.skeleton_name = None
    sub = mesh.create_submesh()
    sub.material_name = material
    sub.index_count = len(indices)
    sub.indices_32_bit = len(data) >= 65536
    sub.set_index_buffer(np.array(indices, dtype="<u4" if sub.indices_32_bit else "<u2").tobytes())
    vd = sub.create_vertex_data(len(data))
    layout = [(om.VET.FLOAT3, om.VES.POSITION, 0), (om.VET.FLOAT3, om.VES.NORMAL, 12),
              (om.VET.FLOAT2, om.VES.TEXTURE_COORDINATES, 24)]
    if tangents:
        layout.append((om.VET.FLOAT3, om.VES.TANGENT, 32))
    for kind, semantic, offset in layout:
        vd.vertex_declaration.create_vertex_element(0, kind, semantic, offset, 0)
    vd.create_vertex_buffer(data.tobytes(), 0, width * 4)
    mesh.aabb = om.AxisAlignedBoundingBox(*lo, *hi)
    mesh.bound_radius = radius
    out = io.BytesIO()
    oms.MeshSerializer(out).write(mesh)
    return out.getvalue()
