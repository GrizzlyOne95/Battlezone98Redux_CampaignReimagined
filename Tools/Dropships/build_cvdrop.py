"""CRA 'Wedge rocket-lander' dropship `cvdrop`: the approved blockout geometry (unchanged), UV-mapped and textured
with the `crdv` atlas (texgen_cvstock.py), rigged and exported like build_dropship.py (avdrop).
Flat cropped-delta arrowhead body; the hold (packed cvrecy + 4 cvtnk in one row) sits in the
wide aft body. The single wide bow ramp IS the chin glacis (45 deg closed), under a raised
framed cockpit. Four downward rocket prongs with bell nozzles are the landing legs.
Ground z 0, forward -Y, metres.
Run: python texgen_cvstock.py, then blender -b -P build_cvdrop.py [-- --norender]"""
import json
import math
import os
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dropkit as C                                   # noqa: E402
from dropkit import prof8, box, loft, band, union, cut, recess, solid, prism_yz, VENT, GLASS, NOZZLE, LAMP  # noqa: E402
from shipkit import circle                            # noqa: E402
import paths                                          # noqa: E402
import bpy                                            # noqa: E402
from mathutils import Vector                          # noqa: E402

FAC = "crdv"      # texture prefix (texgen_cvstock.py)
P = "cdr11"
# ---- cargo (measured; see report): cvrecy 13.73 W x 16.26 L x 8.34 H, cvtnk 7.73 x 8.63 x 2.72
RECY = (13.73, 16.26, 8.34)
TANK = (7.73, 8.63, 2.72)
ZF, ZC = 4.5, 15.5                    # hold floor / ceiling (11 m: recycler 8.34 + 0.2 + 2.9 headroom)
HOLD_HW, HOLD_Y1 = 18.0, 15.0         # four tanks abreast need 4 x 7.73 + 5 x ~1 = 36 m
RAMP_L, RAMP_W, RAMP_T = 16.0, 30.2, 1.2
RAMP_CLOSED = 45.0                    # closed ramp leans forward 45 deg and forms the chin glacis
H = Vector((0, -16.0, ZF))            # hinge on the ramp's outer face, at floor level
d = Vector((0, -math.cos(math.radians(RAMP_CLOSED)), math.sin(math.radians(RAMP_CLOSED))))   # hinge -> ramp top
n = Vector((0, -d.z, d.y))            # outward (down-forward) normal of the glacis
T = H + d * RAMP_L
RAMP_OPEN = RAMP_CLOSED + math.degrees(math.asin(ZF / RAMP_L))   # swing until the lip touches the ground
WELL_HW = RAMP_W / 2 + 0.3
yz = lambda v: (v.y, v.z)
Y_FLOOR0 = (H - n * RAMP_T).y + ((H - n * RAMP_T).z - ZF)          # inner face meets the floor (45 deg)
Y_CEIL0 = (H - n * RAMP_T).y - (ZC - (H - n * RAMP_T).z)           # inner face meets the ceiling


def hexp(hw, ws, zt, ze, zb):
    """6-point faceted section: sharp lateral edge at (hw, ze), flat top/bottom of half-width ws."""
    return [(hw, ze), (ws, zt), (-ws, zt), (-hw, ze), (-ws, zb), (ws, zb)]


C.reset()
parts = []
BODY = [(-50, hexp(3, 2, 18.2, 17.6, 17.2)),                 # arrowhead point
        (-40, hexp(13, 10, 19.0, 17.2, 16.2)),
        (T.y, hexp(18.0, 16, 19.5, 17.0, T.z)),              # top of the glacis = ramp top edge
        (H.y + (H.z - 2.91), hexp(23.0, 20, 17.5, 8.0, 2.91)),  # foot of the glacis (on the ramp plane)
        (22, hexp(37, 20, 17.5, 7.0, 3.0)),                  # full span 74 m
        (30, hexp(37, 20, 12.5, 6.0, 3.5))]                  # trailing edge
body = solid(P + "bdy", loft(BODY))
COCK = [(-44, prof8(3.5, 20.0, 17.5, 1.2, 0.3)),
        (-38, prof8(6.5, 25.0, 17.5, 2.5, 0.3)),
        (-27, prof8(7.0, 25.5, 18.0, 2.5, 0.3)),
        (-20, prof8(5.0, 22.0, 16.8, 1.5, 0.3))]
union(body, loft(COCK), "cockpit")
# hold: aft box (full width) + wedge under the glacis + the ramp well (ramp width)
cut(body, box((0, (Y_FLOOR0 + HOLD_Y1) / 2, (ZF + ZC) / 2), (2 * HOLD_HW, HOLD_Y1 - Y_FLOOR0, ZC - ZF)), "hold")
cut(body, prism_yz([(Y_FLOOR0 + 0.5, ZF), (Y_FLOOR0 + 0.5, ZC), (Y_CEIL0, ZC), (Y_FLOOR0, ZF)], -WELL_HW, WELL_HW),
    "hold_glacis_wedge")
well = [H + n * 1.0 - d * 0.3, T + n * 1.0 + d * 0.3, T - n * 1.3 + d * 0.3, H - n * 1.3 - d * 0.3]
cut(body, prism_yz([yz(v) for v in well], -WELL_HW, WELL_HW), "ramp_well")
# main engine nozzles in the trailing face, grooves, vents, lamps
for x in (-11, 0, 11):
    cut(body, box((x, 29.0, 8.0), (7, 4, 5)), f"aftnozzle{x}", NOZZLE)
for x in (-10, 10):
    cut(body, box((x, 3, 17.5), (0.3, 34, 0.7)), f"topgroove_x{x}")
cut(body, box((0, 4, 17.5), (38, 0.3, 0.7)), "topgroove_y4")
zt_aft = lambda y: 17.5 - 5.0 * (y - 22) / 8
for x0, x1 in ((4, 9), (-9, -4)):
    pts = [Vector((x, y, zt_aft(y))) for x, y in ((x0, 23.5), (x1, 23.5), (x1, 28.5), (x0, 28.5))]
    cut(body, C.facet_cutter(pts, (0, 26, 8), inset=0.0, depth=0.4), f"aftvent{x0}", VENT)
for sx in (1, -1):
    cut(body, box((17 * sx, 30, 6), (1.2, 0.6, 1.2)), f"lamp{sx:+d}", LAMP)
# CRA unit language (cvrecy/cvmuf/cvtnk): rows of slot grilles and a round hatch, all recessed into the deck
for sx in (1, -1):
    for k in range(5):
        cut(body, box((15.0 * sx, 9.0 + 1.6 * k, 17.5), (6.0, 0.6, 0.8)), f"grille{sx:+d}{k}", VENT)
cut(body, loft([(17.0, circle(2.6, 13.0, 24, 0)), (18.2, circle(2.6, 13.0, 24, 0))], axis="z"), "hatch")
# cockpit glazing: recessed panes; the uncut band round each facet is the (later yellow) frame
for i, j in ((0, 1), (0, 2), (0, 3), (1, 1), (1, 3)):
    recess(body, band(COCK, i, j), (0, -32, 20), f"cockpitglass{i}{j}", GLASS, inset=0.45)
parts.append((P + "bdy", body, (0, 0, 0), None))

# ------------------------------------------------------------------ bow ramp
slab = [H, T, T - n * RAMP_T, H - n * RAMP_T]
ramp = solid(P + "rmp", prism_yz([yz(v) for v in slab], -RAMP_W / 2, RAMP_W / 2))
for s in (5.0, 11.0):
    c0 = H + d * s
    pts = [c0 + Vector((x, 0, 0)) + d * dd for x, dd in ((-13.5, -0.15), (13.5, -0.15), (13.5, 0.15), (-13.5, 0.15))]
    cut(ramp, C.facet_cutter(pts, tuple(H + d * 8 - n * 0.6), inset=0.0, depth=0.3), f"rampgroove{int(s)}")
parts.append((P + "rmp", ramp, tuple(H), P + "bdy"))

# ------------------------------------------------------------------ rocket prongs = landing legs
LEGS = [(1, 22.5, -6, 9.0, "lg1"), (1, 30, 24, 8.5, "lg2"), (-1, 22.5, -6, 9.0, "lg3"), (-1, 30, 24, 8.5, "lg4")]
for sx, x, y, top, nm in LEGS:
    x *= sx
    leg = solid(P + nm, loft([(0.0, circle(3.2, y, 8, x)), (0.5, circle(3.0, y, 8, x)), (2.4, circle(2.0, y, 8, x)),
                              (2.8, circle(1.6, y, 8, x)), (3.4, circle(2.4, y, 8, x)), (top, circle(2.4, y, 8, x))],
                             axis="z"))
    cut(leg, loft([(-0.5, circle(2.6, y, 8, x)), (2.0, circle(1.2, y, 8, x))], axis="z"), f"bell_{nm}", NOZZLE)
    parts.append((P + nm, leg, (x, y, top), P + "bdy"))
bone_names = [p[0] for p in parts]
ship, ao = C.join_parts("cvdrop", parts)

# ------------------------------------------------------------------ cargo proxies + fit checks
recy_y = Y_FLOOR0 + 1.0 + RECY[1] / 2
cargo = [C.cargo_box("cvrecy_packed", RECY[0], RECY[1], RECY[2], 0, recy_y, ZF + 0.2, (0.45, 0.42, 0.25, 1))]
row = Y_FLOOR0 + 1.0 + RECY[1] + 1.5 + TANK[1] / 2
for x in (-13.1, -4.4, 4.4, 13.1):
    cargo.append(C.cargo_box(f"cvtnk_{len(cargo)}", TANK[0], TANK[1], TANK[2], x, row, ZF + 0.2, (0.5, 0.35, 0.2, 1)))
fit = {o.name: C.overlaps(o, ship) for o in cargo}
fit.update({f"{a.name}~{b.name}": C.overlaps(a, b) for i, a in enumerate(cargo) for b in cargo[i + 1:]})
assert not any(fit.values()), f"cargo intersects hull or cargo: {fit}"

allp = C.evaluated_coords(ship)
mn, mx = C.bounds(allp)
ctr = (mn + mx) / 2
rad = max((Vector(p) - Vector(ctr)).length for p in allp)
OPEN = [(P + "rmp", "rot", "X", RAMP_OPEN)]
C.apply_pose(ao, OPEN)
rp = C.evaluated_coords(ship, P + "rmp")
rmn, rmx = C.bounds(rp)
lip = min(rp, key=lambda p: p.z)
slope = math.degrees(math.atan2(ZF - lip.z, H.y - lip.y))
assert -0.05 < rmn[2] < 0.3 and lip.y < H.y, f"ramp lip not on the ground ahead of the hinge: {rmn[2]} {lip}"
C.reset_pose(ao)

report = dict(
    ship="cvdrop", overall=dict(W=round(mx[0] - mn[0], 2), L=round(mx[1] - mn[1], 2), H=round(mx[2] - mn[2], 2),
                                min=[round(v, 2) for v in mn], max=[round(v, 2) for v in mx],
                                bounding_sphere_r=round(rad, 1)),
    hold=dict(W=2 * HOLD_HW, L_floor=round(HOLD_Y1 - Y_FLOOR0, 2), L_ceiling=round(HOLD_Y1 - Y_CEIL0, 2), H=ZC - ZF,
              floor_z=ZF, ceiling_z=ZC, y=(round(Y_FLOOR0, 2), HOLD_Y1), glacis_wedge_hw=WELL_HW),
    ramp=dict(length=RAMP_L, width=RAMP_W, thickness=RAMP_T, hinge=tuple(round(v, 2) for v in H),
              closed_deg_from_horizontal=RAMP_CLOSED, open_rotation_deg=round(RAMP_OPEN, 2),
              lip_z_open=round(rmn[2], 3), slope_deg=round(slope, 2)),
    bones=bone_names, cargo_fit_overlaps=fit,
    cargo=dict(cvrecy=RECY, cvtnk=TANK, recy_center_y=round(recy_y, 2), tank_row_y=round(row, 2)),
    booleans=C.LOG)
print("DIMS", report["overall"], "RAMP", report["ramp"], "HOLD", report["hold"])
os.makedirs(C.OUT, exist_ok=True)
cfg = dict(hold=(-HOLD_HW - 0.05, HOLD_HW + 0.05, Y_FLOOR0 - 0.05, HOLD_Y1 + 0.05, ZF - 0.05, ZC + 0.05),
           ctr=tuple(ctr), dist=210, ramp_view=((0, -18, 7), (-0.55, -1.3, 0.42), 135), bay_light=(0, 0, 14),
           nose=((-16, -64, 30), (0, -36, 21), 60), small=((31, -14, -7), (22.5, -6, 2.0), 60),
           stock=(os.path.join(paths.STOCK, "TRO", "cvrecy.mesh"), os.path.join(paths.STOCK_TEX, "TRO", "DIFF", "cvrecy_d.dds"),
                  (-46.0, -28.0)),
           compare_dist=170)
C.package(ship, ao, FAC, cfg, cargo, OPEN, report)
