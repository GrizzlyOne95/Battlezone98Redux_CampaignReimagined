"""Bake per-vertex wind sway weights into foliage meshes.

The wind vertex programs (Shaders/cr17_wind.program, Shaders/CR_grasswind.program)
read TEXCOORD1 as (bend, flutter) weights in 0..1. They cannot derive them from
object-space height because ground cover is drawn through Ogre StaticGeometry,
whose vertices are baked into region space, so a vertex's height above its own
root is lost by the time the shader sees it.

Each selected submesh gains one extra vertex stream (a new bind index holding a
float2 TEXCOORD1), so the existing buffers are not repacked, and is renamed to
the wind material. A wind material on a mesh without the stream would fail the
D3D11 vertex declaration on every draw, which is why the stock non-wind
materials (CR17/Leaves, CR/GrassPrototype) are left alone for other meshes.

Modes:
  plant  bend = h^1.5, flutter = h, with h the height above the mesh's lowest
         vertex normalised to its tallest.
  tree   the trunk does not bend (bark keeps a BZBase material), so the canopy
         only shifts a little: bend = h^2, flutter = h * radial distance from
         the bark's axis normalised to the widest leaf.

Rerunning on an already baked mesh replaces the stream rather than adding a
second one.

Usage:
  python -I Tools/Bake-FoliageSway.py <toolbox root> <mode> <from material> <to material> <mesh>...
"""
import math
import struct
import sys
from pathlib import Path

VET_FLOAT2 = 1
VES_TEXTURE_COORDINATES = 7


def bake(mesh_path, mode, source_material, target_material, ogre):
    mesh = ogre.read_mesh(Path(mesh_path))
    subs = [s for s in mesh.submeshes if s.material in (source_material, target_material)]
    if not subs:
        raise SystemExit(f"{mesh_path}: no submesh uses {source_material} or {target_material}")

    axis = (0.0, 0.0)
    bark = [s for s in mesh.submeshes if s not in subs and s.geometry is not None]
    if mode == "tree" and bark:
        points = [p for s in bark for p in (s.geometry.attribute(1) or [])]
        low = sorted(points, key=lambda p: p[1])[:max(1, len(points) // 4)]
        axis = (sum(p[0] for p in low) / len(low), sum(p[2] for p in low) / len(low))

    for sub in subs:
        geometry = sub.geometry
        if geometry is None:
            raise SystemExit(f"{mesh_path}: {sub.material} uses shared vertices, which this tool does not handle")
        positions = geometry.attribute(1)
        ys = [p[1] for p in positions]
        y0, y1 = min(ys), max(ys)
        span = max(y1 - y0, 1e-4)
        radii = [math.hypot(p[0] - axis[0], p[2] - axis[1]) for p in positions]
        widest = max(max(radii), 1e-4)

        weights = []
        for p, r in zip(positions, radii):
            if mode == "tree":
                h = min(1.0, max(0.0, p[1] / max(y1, 1e-4)))
                weights.append((h * h, h * min(1.0, r / widest)))
            else:
                h = (p[1] - y0) / span
                weights.append((h ** 1.5, h))

        # Drop a previous bake's stream, then append ours on a fresh bind index.
        old = [e for e in geometry.elements if e.semantic == VES_TEXTURE_COORDINATES and e.index == 1]
        for element in old:
            geometry.elements.remove(element)
            if not any(e.source == element.source for e in geometry.elements):
                geometry.buffers.pop(element.source, None)
        bind = max(geometry.buffers, default=-1) + 1
        data = b"".join(struct.pack("<2f", *w) for w in weights)
        geometry.elements.append(ogre.VertexElement(bind, VET_FLOAT2, VES_TEXTURE_COORDINATES, 0, 1))
        geometry.buffers[bind] = ogre.VertexBuffer(bind, 8, data, 0)
        sub.material = target_material

    ogre.write_mesh(mesh, Path(mesh_path))
    print(f"{Path(mesh_path).name}: {len(subs)} submesh(es) -> {target_material} ({mode})")


def main(argv):
    if len(argv) < 6 or argv[2] not in ("plant", "tree"):
        raise SystemExit(__doc__)
    sys.path.insert(0, str(Path(argv[1]).resolve()))
    from battlezone.meshes import ogre
    for mesh_path in argv[5:]:
        bake(mesh_path, argv[2], argv[3], argv[4], ogre)


if __name__ == "__main__":
    main(sys.argv)
