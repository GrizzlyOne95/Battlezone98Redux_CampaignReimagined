"""CCA cruiser 'svcrus' from CCAfleet3 concept (centre ship, side elevation),
styled after the BZTC CCA rocketship. Run: blender -b -P build_cca.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shipkit as K
from shipkit import octo

K.setup_scene()
s = K.Ship("svcrus", "cca")
A, L, ACC, RED, HAZ, GRB = "auto", ("trim", "lights"), ("trim", "accent"), ("trim", "redlts"), ("trim", "hazard"), ("trim", "greeble")

# --- forked bow: upper jaw, greeble keel slot, lower jaw
s.loft([(-150, octo(3, 12, 9, 1)), (-128, octo(14, 18, 8, 3)), (-96, octo(24, 25, 8.5, 5)),
        (-93, octo(24.6, 25.4, 8.4, 5)), (-62, octo(30, 30, 8, 6)), (-38, octo(34, 31, 8, 6))],
       [A, A, L, A, ACC])
s.box((0, -84, 2.5), (14, 96, 12), A, faces={"+x": GRB, "-x": GRB, "-y": GRB})
s.loft([(-134, octo(3, -5, -8, 1)), (-110, octo(12, -2, -12, 3)), (-78, octo(21, -1, -17, 5)),
        (-75, octo(21.6, -0.8, -17.4, 5)), (-38, octo(30, -1, -22, 6))],
       [A, A, HAZ, A])

# --- mid block with hangar door, roundel, strakes, ventral fins
s.loft([(-40, octo(42, 17, -30, 7)), (-37, octo(42.6, 17.4, -30.4, 7)), (54, octo(42.6, 17.4, -30.4, 7)),
        (57, octo(42, 17, -30, 7))], [L, A, RED])
s.plate((21.3, 11, 2.5), (61, 21), "+x", ("trim", "hangar"), mirror_x=True)
s.plate((21.3, 11, -9.6), (61, 2.2), "+x", HAZ, mirror_x=True)
s.plate((21.3, -28, 3), (11, 11), "+x", ("cell", "roundel"), mirror_x=True)
s.box((21.8, 20, -18), (1.6, 66, 2.6), A, faces={"+x": L})
s.box((-21.8, 20, -18), (1.6, 66, 2.6), A, faces={"-x": L})
for y in (-30, 8, 16, 50):
    s.box((0, y, -34), (2.2, 4, 8), A)
s.plate((0, -10, -30.4), (24, 50), "-z", GRB)

# --- bridge tower (stepped pedestal + masts, from the concept sheet)
s.box((0, 4, 21), (16, 22, 8), A, faces={"-y": ("trim", "vent")})
s.box((0, 6, 28), (11, 14, 6), A, faces={"-y": ("cell", "glass"), "+x": L, "-x": L})
s.box((0, 8, 33), (6, 8, 4), A, faces={"-y": RED})
s.box((2, 9, 42), (0.8, 0.8, 14), A)
s.box((-2, 11, 39), (0.8, 0.8, 8), A)
s.box((0, 70, 37.6), (1.4, 124, 1.4), A)  # dorsal rail to the engines

# --- dorsal engine nacelle
s.loft([(50, octo(16, 32, 21, 4)), (60, octo(24, 36, 17, 6)), (96, octo(24, 36, 17, 6)),
        (99, octo(24.6, 36.3, 16.7, 6)), (103, octo(20, 33, 19, 5)), (140, octo(20, 33, 19, 5)),
        (143, octo(21, 33.5, 18.5, 5))], [A, A, L, A, A, ACC])
s.plate((12, 78, 26.5), (16, 9), "+x", ("cell", "chevron"), mirror_x=True)
s.plate((12, 120, 26), (8, 8), "+x", ("cell", "star"), depth=0.4, mirror_x=True)
for x in (-5, 5):
    s.engine(137, x, 26, 4.6, 16)

# --- ventral engine nacelle (larger)
s.loft([(48, octo(20, 4, -24, 5)), (60, octo(30, 9, -36, 8)), (95, octo(30, 9, -36, 8)),
        (98, octo(30.6, 9.3, -36.3, 8)), (104, octo(24, 2, -24, 6)), (140, octo(24, 2, -24, 6)),
        (143, octo(25, 2.5, -24.5, 6))], [A, A, L, A, A, ACC])
s.plate((15, 76, -14), (18, 18), "+x", ("cell", "star"), mirror_x=True)
s.plate((12, 122, -11), (24, 2.4), "+x", HAZ, mirror_x=True)
for x, z in ((-5.6, -5.6), (5.6, -5.6), (-5.6, -16.6), (5.6, -16.6)):
    s.engine(137, x, z, 4.6, 17)

# --- bow details: hull number, hatch, lights
s.plate((14.2, -72, 19), (14, 8), "+x", ("cell", "number"), depth=0.4, mirror_x=True)
s.plate((11.6, -108, 16.5), (5, 6), "+x", ("cell", "hatch"), depth=0.3, mirror_x=True)

ob = s.finish()
print("FACES", len(ob.data.polygons))
K.export_mesh(ob)
K.write_ogre_material("svcrus", "cca")
import bpy
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(K.OUT, "svcrus.blend"))
if "--norender" not in sys.argv:
    K.render_previews(ob, "svcrus", 560)
