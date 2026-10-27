"""Build the NSDF Eagle's Nest rocket fixture (cr03rok) from GrizzlyOne95's own art.

python Tools/Build-Misn03Rocket.py [SOURCE_DIR]

SOURCE_DIR defaults to the author's ROTBDv2 working folder and is read only. It
must hold abtrans.mesh and the four abtrans_DefaultMaterial_*.dds maps (the NSDF
rocket from ROTBD/Resurgence). The pad submesh is dropped, the skeleton link and
bone assignments are stripped, and the rocket is recentred on its own axis.

Origin convention: the same as cr06rok. X/Z sit on the rocket axis and Y is the
mid-height of the bounds, so the nozzle plane is at -half-height (CR06's is
-48.5) and the generated launch layout is expressed from that plane.

Writes (all committed, regeneration is deterministic):
  Assets/ModelFixes/cr03rok.{mesh,geo,sdf}   Assets/Textures/cr03rok_{d,n,s,e}.dds
  Materials/cr03rok.material  ODF/cr03rok.odf  Scripts/CR03RocketLayout.lua
  References/Misn03Rocket/build.json

Model I/O goes through the shared serializers (bzmodellibs); nothing is hand-rolled.
"""
import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import sys

import numpy as np
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parent))
from bcdds import save_bc

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bzmodellibs import geo, geo_serializer, ogremesh_serializer  # noqa: E402
from bzstaticmodel import mesh_bounds, static_mesh_bytes, static_sdf_bytes  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = Path(r"C:\Users\iestu\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\ROTBDv2")
NAME = "cr03rok"
SUBMESH = "abtrans_BZBase_abtrans"
# Measured rocket axis in the abtrans frame (the six-lobed skirt is centred here).
AXIS_X, AXIS_Z = 24.745, -23.415
RING_RADIUS = 9.0
TEXTURES = {
    "d": "abtrans_DefaultMaterial_BaseMap_sRGB.dds",
    "n": "abtrans_DefaultMaterial_Normal_Raw.dds",
    "s": "abtrans_DefaultMaterial_Specular_sRGB.dds",
    "e": "abtrans_DefaultMaterial_Emissive_sRGB.dds",
}


def read_rocket(source):
    mesh = ogremesh_serializer.MeshSerializer(io.BytesIO((source / "abtrans.mesh").read_bytes())).read()
    subs = [s for s in mesh.submesh_list if s.material_name == SUBMESH]
    assert len(subs) == 1, "expected exactly one rocket submesh"
    sub = subs[0]
    assert not sub.use_shared_vertices
    vd = sub.vertex_data
    positions = normals = uvs = None
    for element in vd.vertex_declaration.vertex_element_list:
        buffer = np.frombuffer(bytes(vd.get_vertex_buffer(element.source).buffer), dtype="u1")
        stride = vd.get_vertex_buffer(element.source).vertex_size
        rows = buffer.reshape(vd.vertex_count, stride)
        def floats(count):
            return np.ascontiguousarray(rows[:, element.offset:element.offset + 4 * count]).view("<f4").reshape(-1, count)
        if element.semantic == 1:
            positions = floats(3)
        elif element.semantic == 4:
            normals = floats(3)
        elif element.semantic == 7:
            uvs = floats(2)
    assert positions is not None and normals is not None and uvs is not None
    indices = sub.get_index_array().astype("<u4").tolist()
    assert len(indices) // 3 == 2750 and max(indices) < len(positions)
    return positions.astype("<f8"), normals, uvs, indices


def build_geometry(source):
    positions, normals, uvs, indices = read_rocket(source)
    lo, hi = positions.min(0), positions.max(0)
    mid_y = round(float((lo[1] + hi[1]) / 2), 6)
    shift = np.array([AXIS_X, mid_y, AXIS_Z])
    local = (positions - shift).astype("<f4")
    rows = np.concatenate([local, normals, uvs], axis=1)
    return rows, indices, mid_y


def write_model(rows, indices):
    model = ROOT / "Assets/ModelFixes"
    rows_list = [tuple(float(v) for v in row) for row in rows]
    (model / (NAME + ".mesh")).write_bytes(static_mesh_bytes(NAME + "00", rows_list, indices))
    lo, hi, radius = mesh_bounds(rows_list)
    center = [(a + b) / 2 for a, b in zip(lo, hi)]
    half = [(b - a) / 2 for a, b in zip(lo, hi)]
    (model / (NAME + ".sdf")).write_bytes(static_sdf_bytes(NAME, center, half, radius))
    # Native fallback geometry: the rocket is only ~2.7k triangles, so use it whole.
    points = rows[:, :3].astype("<f4")
    g = geo.Geo()
    g.name = NAME
    g.vert_count = len(points)
    g.vertex_pos_buffer = points
    g.vertex_normal_buffer = rows[:, 3:6].astype("<f4")
    for i in range(0, len(indices), 3):
        q = [points[j].astype("<f8") for j in indices[i:i + 3]]
        normal = np.cross(q[1] - q[0], q[2] - q[0])
        length = np.linalg.norm(normal)
        normal = normal / length if length > 1e-12 else np.array([0.0, 1.0, 0.0])
        face = g.create_face(i // 3)
        face.color = geo.Color3(255, 255, 255)
        face.plane = geo.SurfacePlane(geo.Vector3(*(-normal)), float(normal.dot(q[0])))
        face.shade_type = face.texture_type = 0
        face.texture_name = NAME + ".map"
        for j in indices[i:i + 3]:
            face.create_face_node(j, j, geo.UV(float(rows[j, 6]), float(rows[j, 7])))
    raw = io.BytesIO()
    geo_serializer.GeoSerializer(raw).write(g)
    (model / (NAME + ".geo")).write_bytes(raw.getvalue())
    return lo, hi, radius


def write_textures(source):
    for suffix, filename in TEXTURES.items():
        image = Image.open(source / filename).convert("RGBA")
        assert image.size == (1024, 1024)
        # BC1 with full offline mips; compressed DDS without mips render black.
        save_bc(image, ROOT / "Assets/Textures" / f"{NAME}_{suffix}.dds")


def write_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def write_layout(nozzle_y):
    nozzles = [(0.0, 0.0)] + [
        (RING_RADIUS * math.cos(math.radians(a)), RING_RADIUS * math.sin(math.radians(a)))
        for a in range(0, 360, 60)
    ]
    lines = ["-- Generated by Build-Misn03Rocket.py: one centre bell and six on a 9 m ring (skirt lobes).",
             "return { nozzleY = %.9f, nozzles = {" % nozzle_y]
    lines += ["    {%.9f, %.9f}," % (x + 0.0, z + 0.0) for x, z in nozzles]
    lines.append("} }")
    write_text(ROOT / "Scripts/CR03RocketLayout.lua", "\n".join(lines) + "\n")
    return nozzles


def build(source):
    rows, indices, mid_y = build_geometry(source)
    lo, hi, radius = write_model(rows, indices)
    write_textures(source)
    write_text(ROOT / "Materials" / (NAME + ".material"),
        'import * from "BZBase.material"\n'
        f"material {NAME}00 : BZBase\n{{\n"
        + "".join(f"    set_texture_alias {m} {NAME}_{s}.dds\n" for m, s in
                  (("DiffuseMap", "d"), ("NormalMap", "n"), ("SpecularMap", "s"), ("EmissiveMap", "e")))
        + '    set $diffuse "1 1 1"\n    set $ambient "1 1 1"\n    set $specular ".7 .7 .7"\n'
          '    set $shininess "127"\n    set $glow "1 1 1"\n}\n')
    write_text(ROOT / "ODF" / (NAME + ".odf"),
        '[GameObjectClass]\nbaseName = "cr03rok"\nclassLabel = "i76building"\nscrapCost = 0\n'
        'scrapValue = 0\nmaxHealth = 0\nmaxAmmo = 0\nunitName = "NSDF Rocket Transport"\n'
        'heatSignature = 0\nimageSignature = 0\nradarSignature = 0\n')
    nozzle_y = float(lo[1])
    nozzles = write_layout(nozzle_y)
    paths = [ROOT / "Assets/ModelFixes" / f"{NAME}.{s}" for s in ("mesh", "geo", "sdf")]
    paths += [ROOT / "Assets/Textures" / f"{NAME}_{s}.dds" for s in TEXTURES]
    info = {
        "source": "GrizzlyOne95 NSDF rocket (ROTBD/Resurgence abtrans.mesh, submesh " + SUBMESH + ")",
        "triangles": len(indices) // 3, "vertices": len(rows),
        "axis_in_abtrans_frame": [AXIS_X, AXIS_Z], "mid_height_in_abtrans_frame": mid_y,
        "bounds_min": [float(v) for v in lo], "bounds_max": [float(v) for v in hi],
        "nozzle_plane": nozzle_y, "nozzle_ring_radius": RING_RADIUS, "nozzles": len(nozzles),
        "sha256": {str(p.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},
    }
    write_text(ROOT / "References/Misn03Rocket/build.json", json.dumps(info, indent=2) + "\n")
    print(f"Built NSDF rocket: {info['triangles']} triangles, mid-height origin, nozzle plane y={nozzle_y:.4f}, "
          f"{len(nozzles)} nozzle anchors.")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", nargs="?", type=Path, default=DEFAULT_SOURCE)
    build(ap.parse_args().source)
