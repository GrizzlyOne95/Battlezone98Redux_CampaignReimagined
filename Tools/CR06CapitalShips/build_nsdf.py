"""NSDF carrier 'avcarr' from Nsdf_carrier concept (side elevation, bow at -Y, ~0.36 m/px),
painted after the NSDF victory art and built with the same rocketship-style kit as svcrus.
Run: blender -b -P build_nsdf.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shipkit as K
from shipkit import octo, circle
import math
import bmesh
from mathutils import Matrix, Vector

K.setup_scene()
s = K.Ship("avcarr", "nsdf")
A, L, ACC, RED, HAZ, GRB = "auto", ("trim", "lights"), ("trim", "accent"), ("trim", "redlts"), ("trim", "hazard"), ("trim", "greeble")

# --- blunt angled nose + forward hull block
s.loft([(-184, octo(8, 2, -5, 2)), (-160, octo(30, 9, -18, 5)), (-128, octo(52, 20, -31, 7)),
        (-123, octo(56, 23, -34, 7)), (-119, octo(56.6, 23.4, -34.4, 7)), (-34, octo(56.6, 23.4, -34.4, 7)),
        (-30, octo(54, 22, -33, 7))],
       [A, A, A, L, A, ACC])
s.plate((0, -170, 3.4), (3, 26), "+z", L, depth=0.3)          # bright nose strip
s.plate((28.4, -96, 10), (16, 9), "+x", ("cell", "number"), depth=0.4, mirror_x=True)
s.plate((28.4, -60, 12), (12, 12), "+x", ("cell", "star"), depth=0.4, mirror_x=True)
s.plate((28.4, -78, -24), (60, 2.4), "+x", HAZ, mirror_x=True)
s.plate((0, -78, -34.4), (26, 70), "-z", GRB)

# --- neck: sloped dorsal spine climbing to the tower over a lower body with side pods
s.loft([(-32, octo(44, 8, -30, 6)), (22, octo(44, 8, -30, 6))], [A])
s.loft([(-34, octo(30, 23.5, 12, 4)), (-30, octo(30, 24.5, 13, 4)), (22, octo(30, 41, 29, 4))], [ACC, A])
for x in (-27, 27):
    s.loft([(-28, octo(6, -14, -20, 2, x)), (-22, octo(13, -10, -26, 4, x)), (14, octo(13, -10, -26, 4, x)),
            (20, octo(8, -13, -22, 2, x))], [A, L, A])

# --- arch tower: solid base, two pillars, top beam, dish, vent block under the arch
s.box((0, 43, -15), (60, 50, 56), A, faces={"-y": ("trim", "vent")})
s.box((0, 25, 22), (60, 14, 18), A, faces={"+x": L, "-x": L})
s.box((0, 61, 22), (60, 14, 18), A, faces={"+x": L, "-x": L})
s.box((0, 43, 37), (60, 50, 12), A, faces={"-y": ACC, "+y": ACC})
s.box((0, 43, 16), (34, 20, 6), A, faces={"+x": ("trim", "vent"), "-x": ("trim", "vent")})
s.plate((30, 43, -6), (14, 14), "+x", ("cell", "roundel"), depth=0.4, mirror_x=True)
# concept roof: big shallow saucer dish over the front pillar, dark radome hump behind it
ell = lambda rx, ry, n=16: [(rx * math.cos(2 * math.pi * k / n), ry * math.sin(2 * math.pi * k / n)) for k in range(n)]
s.loft([(0, ell(15, 17)), (4, ell(14, 15.5)), (8, ell(11, 12.5)), (10.5, ell(6.5, 7.5)), (11.5, ell(2, 2.5))],
       [A, A, ("trim", "accent"), A], cap0=None, off=(0, 50, 43), axis="z")
s.loft([(0, circle(3, 0, 8)), (4, circle(2.2, 0, 8))], [L], cap0=None, off=(0, 25, 43), axis="z")
DC = Vector((0, 25, 47))
dish = s.loft([(0, circle(2.6, 0, 20)), (1.6, circle(7.5, 0, 20)), (2.8, circle(11.5, 0, 20)),
               (2.8, circle(10.8, 0, 20)), (1.1, circle(4, 0, 20))],
              [A, A, ("trim", "accent"), A], cap0="auto", cap1=("cell", "dish"), off=tuple(DC), axis="z")
bmesh.ops.rotate(s.bm, verts=list({v for f in dish for v in f.verts}), cent=DC,
                 matrix=Matrix.Rotation(math.radians(12), 3, "X"))
s.box((5, 62, 56), (0.8, 0.8, 14), A)

# --- tall rear hull with angled prow, hangar mouths, stars and stripes
s.loft([(66, octo(64, 30, -38, 8)), (74, octo(84, 40, -44, 11)), (78, octo(84.6, 40.4, -44.4, 11)),
        (160, octo(84.6, 40.4, -44.4, 11)), (164, octo(84, 40, -44, 11)), (180, octo(62, 22, -28, 9))],
       [A, L, A, RED, A])
for sx in (1, -1):
    s.loft([(70, octo(8, 22, 8, 2, sx * 42)), (100, octo(14, 30, 2, 4, sx * 45)), (106, octo(14, 30, 2, 4, sx * 45))],
           [A, A], cap1="auto")                                       # angled prow sponsons
s.plate((42.3, 132, -14), (44, 16), "+x", ("trim", "hangar"), mirror_x=True)
s.plate((42.3, 132, -23.6), (44, 2), "+x", HAZ, mirror_x=True)
s.plate((42.3, 128, 24), (18, 18), "+x", ("cell", "star"), depth=0.4, mirror_x=True)
s.plate((42.3, 150, 24), (14, 9), "+x", ("cell", "chevron"), depth=0.4, mirror_x=True)
s.plate((0, 120, 40.4), (30, 60), "+z", GRB)
s.plate((0, 96, 40.4), (14, 14), "+z", ("cell", "star"), depth=0.3)
s.plate((0, 150, 40.4), (8, 8), "+z", ("cell", "hatch"), depth=0.3)

# --- engines: stern cluster plus victory-art side pods with blue glow
for x in (-18, 0, 18):
    for z in (6, -12):
        s.engine(170, x, z, 6, 18)
for x in (-49, 49):
    s.box((x * 0.88, 146, -24), (6, 52, 5), A, faces={"+z": GRB})   # pylon to the hull
    s.engine(110, x, -24, 8.5, 74, bands=L)

ob = s.finish()
print("FACES", len(ob.data.polygons))
K.export_mesh(ob)
K.write_ogre_material("avcarr", "nsdf")
import bpy
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(K.OUT, "avcarr.blend"))
if "--norender" not in sys.argv:
    K.render_previews(ob, "avcarr", 640)
