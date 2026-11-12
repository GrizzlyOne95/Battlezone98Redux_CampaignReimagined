"""Rewrite GEO face planes the way stock GEOs store them.

bz98tools' default ("CURRENT") face-plane export writes each face's centre with d = 1, and its
RECOMPUTE mode writes d with the wrong sign. Stock GEOs store the unit Newell normal of the face
in file vertex order (inward-facing on closed parts) and d = -N.p, so a point p is on the plane
when N.p + d = 0. Building collision reads these planes: with the default export, a part has no
usable collision.

Run: python geo_planes.py <file.geo>...   (rewrites in place; --check only reports)
"""
import math
import struct
import sys


def _faces(b):
    nv, nf = struct.unpack_from("=4si16siii", b, 0)[3:5]
    verts = [struct.unpack_from("=fff", b, 36 + 12 * k) for k in range(nv)]
    i = 36 + 24 * nv                                      # vertices, then vertex normals
    for _ in range(nf):
        count = struct.unpack_from("=i", b, i + 4)[0]
        ids = [struct.unpack_from("=i", b, i + 55 + 16 * k)[0] for k in range(count)]
        yield i, [verts[k] for k in ids]
        i += 55 + 16 * count


def _plane(pts):
    n = [0.0, 0.0, 0.0]
    for a, c in zip(pts, pts[1:] + pts[:1]):
        n[0] += (a[1] - c[1]) * (a[2] + c[2])
        n[1] += (a[2] - c[2]) * (a[0] + c[0])
        n[2] += (a[0] - c[0]) * (a[1] + c[1])
    length = math.sqrt(sum(x * x for x in n)) or 1.0
    n = [x / length for x in n]
    return n + [-sum(n[j] * pts[0][j] for j in range(3))]


def fix(path, check=False):
    b = bytearray(open(path, "rb").read())
    worst = 0.0
    for off, pts in _faces(b):
        plane = _plane(pts)
        old = struct.unpack_from("=ffff", b, off + 11)    # after index, vertex count and rgb bytes
        worst = max(worst, max(abs(p - o) for p, o in zip(plane, old)))
        struct.pack_into("=ffff", b, off + 11, *plane)
    if not check:
        open(path, "wb").write(b)
    return worst


if __name__ == "__main__":
    check = "--check" in sys.argv
    for p in (a for a in sys.argv[1:] if a != "--check"):
        print(f"{p}: max plane change {fix(p, check):.3f}")
