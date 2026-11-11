"""CRA 'Wedge rocket-lander' dropship `cvdrop`, round 3: a heavy angular armoured slab instead of the swept delta.
Chamfered octagonal-section body (about 45 deg chamfers, 4-6 % of the part size), a short sloped armour-wedge nose with a
raised lip, a squarer rear, separate swept bevelled wing slabs with engine pods and winglet blocks unioned in with their
roots buried, recessed roof panel insets, bezelled thrusters. The hold (packed cvrecy + 4 cvtnk in one row), the bow ramp
(which closes as the 45 deg chin glacis), the bones and the four landing prongs keep their places and sizes; each prong
now has a 16-sided bevelled rim lip and a recessed bezel ring with the emissive disc set into it.
Ground z 0, forward -Y, metres.
Run: blender -b -P build_cvdrop.py -- --norender, python texgen_cvstock.py, blender -b -P build_cvdrop.py"""
import json
import math
import os
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dropkit as C                                   # noqa: E402
from dropkit import prof8, box, loft, band, union, cut, recess, solid, prism_yz, inset_poly  # noqa: E402
from dropkit import VENT, GLASS, NOZZLE, LAMP         # noqa: E402
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
FOOT_Y = H.y + (H.z - 2.91)                                        # foot of the glacis on the body

C.reset()
parts = []
# ------------------------------------------------------------------ body: octagonal armour slab
BODY = [(-34.0, prof8(12.0, 17.2, 15.4, 1.0, 0.5)),       # nose face (short blunt wedge)
        (-33.0, prof8(14.0, 18.6, 15.4, 1.4, 0.6)),       # raised lip shoulder
        (-31.0, prof8(16.5, 19.0, 15.5, 1.8, 0.8)),
        (T.y, prof8(19.0, 19.5, T.z, 2.4, 0.8)),          # top of the glacis = ramp top edge
        (FOOT_Y, prof8(21.5, 19.5, 2.91, 3.6, 3.0)),      # foot of the glacis (on the ramp plane)
        (10.0, prof8(21.5, 19.5, 3.0, 3.6, 3.0)),
        (28.5, prof8(21.5, 19.0, 3.0, 3.4, 3.0)),
        (30.0, prof8(20.0, 18.0, 3.5, 2.0, 1.8))]         # squarer rear with a trailing chamfer
body = solid(P + "bdy", loft(BODY))
COCK = [(-31.0, prof8(4.2, 21.2, 17.5, 1.4, 0.3)),
        (-27.0, prof8(7.2, 25.0, 17.5, 2.6, 0.3)),
        (-17.0, prof8(8.0, 25.5, 18.0, 2.6, 0.3)),
        (-10.0, prof8(6.0, 22.0, 17.0, 1.6, 0.3))]
union(body, loft(COCK), "cockpit")


def wing_plan(sx):
    return [(17.0 * sx, -16.0), (36.5 * sx, 7.0), (36.5 * sx, 29.0), (17.0 * sx, 29.0)]


for sx in (1, -1):
    plan = wing_plan(sx)
    # swept bevelled wing slab: 45 deg bevel top and bottom, root buried in the body
    union(body, loft([(3.5, inset_poly(plan, 1.0)), (4.5, plan), (8.5, plan), (9.5, inset_poly(plan, 1.0))], axis="z"),
          f"wing{sx:+d}")
    cx = 29.0 * sx
    union(body, loft([(9.0, prof8(2.2, 15.2, 8.6, 1.0, 0.6, cx)), (12.0, prof8(3.2, 16.4, 8.6, 1.4, 0.8, cx)),
                      (28.0, prof8(3.2, 16.4, 8.6, 1.4, 0.8, cx)), (29.6, prof8(2.8, 15.8, 8.8, 1.1, 0.7, cx))]),
          f"pod{sx:+d}")
    wx = 35.8 * sx
    union(body, loft([(10.0, prof8(0.7, 14.0, 8.8, 0.3, 0.3, wx)), (13.0, prof8(0.8, 18.0, 8.8, 0.5, 0.3, wx)),
                      (26.0, prof8(0.8, 18.0, 8.8, 0.5, 0.3, wx)), (28.5, prof8(0.7, 15.0, 8.8, 0.3, 0.3, wx))]),
          f"winglet{sx:+d}")
# hold: aft box (full width) + wedge under the glacis + the ramp well (ramp width)
cut(body, box((0, (Y_FLOOR0 + HOLD_Y1) / 2, (ZF + ZC) / 2), (2 * HOLD_HW, HOLD_Y1 - Y_FLOOR0, ZC - ZF)), "hold")
cut(body, prism_yz([(Y_FLOOR0 + 0.5, ZF), (Y_FLOOR0 + 0.5, ZC), (Y_CEIL0, ZC), (Y_FLOOR0, ZF)], -WELL_HW, WELL_HW),
    "hold_glacis_wedge")
well = [H + n * 1.0 - d * 0.3, T + n * 1.0 + d * 0.3, T - n * 1.3 + d * 0.3, H - n * 1.3 - d * 0.3]
cut(body, prism_yz([yz(v) for v in well], -WELL_HW, WELL_HW), "ramp_well")
# main thrusters in the rear slab: one clean recessed frame each, the emissive throat is its floor
for x in (-11, 0, 11):
    cut(body, box((x, 30.5, 8.0), (7.6, 5.0, 5.2)), f"aftnozzle{x}", NOZZLE)
# engine-pod thrusters
for sx in (1, -1):
    cx = 29.0 * sx
    cut(body, box((cx, 30.4, 12.8), (3.8, 3.6, 2.8)), f"podnozzle{sx:+d}", NOZZLE)
    cut(body, box((cx, 18.0, 16.4), (2.4, 12.0, 0.5)), f"podpanel{sx:+d}")            # pod top inset panel
    cut(body, box((26.0 * sx, 1.0, 9.5), (6.0, 8.0, 0.4)), f"wingpanel{sx:+d}")          # wing top inset panel
# roof: panel insets cut as recesses, deck grooves, slot grilles, round hatch, lamps
for sx in (1, -1):
    cut(body, box((9.0 * sx, 7.0, 19.5), (8.0, 11.0, 0.4)), f"roofinset{sx:+d}")
    cut(body, box((8.0 * sx, 21.0, 19.2), (8.0, 7.0, 0.5)), f"roofinsetaft{sx:+d}")
for sx in (1, -1):
    for k in range(5):
        cut(body, box((15.6 * sx, 9.0 + 1.6 * k, 19.5), (3.2, 0.6, 0.8)), f"grille{sx:+d}{k}", VENT)
    cut(body, box((17.0 * sx, 30, 6), (1.2, 0.6, 1.2)), f"lamp{sx:+d}", LAMP)
cut(body, loft([(19.0, circle(2.2, 14.0, 24, 0)), (20.2, circle(2.2, 14.0, 24, 0))], axis="z"), "hatch")
# cockpit glazing: recessed panes; the uncut band round each facet is the bezel lip
for i, j in ((0, 1), (0, 2), (0, 3), (1, 1), (1, 3)):
    recess(body, band(COCK, i, j), (0, -24, 21), f"cockpitglass{i}{j}", GLASS, inset=0.45)
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
# 16 sides, a chamfered rim lip at the foot, a recessed bezel ring and the emissive throat set into it
LEGS = [(1, 22.5, -6, 9.0, "lg1"), (1, 30, 24, 8.5, "lg2"), (-1, 22.5, -6, 9.0, "lg3"), (-1, 30, 24, 8.5, "lg4")]
for sx, x, y, top, nm in LEGS:
    x *= sx
    prof = [(0.0, 2.7), (0.3, 3.3), (0.9, 3.3), (1.3, 2.9), (2.5, 2.0), (2.9, 1.7), (3.5, 2.4), (top, 2.4)]
    leg = solid(P + nm, loft([(z, circle(r, y, 16, x)) for z, r in prof], axis="z"))
    cut(leg, loft([(-0.5, circle(2.3, y, 16, x)), (0.3, circle(2.3, y, 16, x))], axis="z"), f"bezel_{nm}")
    cut(leg, loft([(-0.5, circle(1.8, y, 16, x)), (1.7, circle(0.9, y, 16, x))], axis="z"), f"bell_{nm}", NOZZLE)
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


def classify(c, n, bone):
    """Face groups the painter colours by (texgen_island.py): maroon roof, ochre flanks and wings, olive body, armour nose,
    the rear slab, legs, ramp. Insignia go only on 'flank' and 'rear' islands."""
    if bone.startswith(P + "lg"):
        return "leg"
    if bone == P + "rmp":
        return "ramp"
    if n.z < -0.35:
        return "under"
    if n.z > 0.9:
        if c.z > 18.4:
            return "roof"
        if c.z > 10:
            return "pod"
        return "wing" if abs(c.x) > 22 else "base"
    if abs(n.x) > 0.9 and abs(c.x) < 22.5 and c.z > 5:
        return "flank"
    if n.y > 0.9 and c.y > 28:
        return "rear"
    if c.y < -27:
        return "armor"
    if abs(c.x) > 22 and c.z < 10.5:
        return "wing"
    return "base"


def logo_cams():
    """Close-up cameras aimed at the insignia the painter placed (it writes cvdrop_logos.json); fixed guesses before that."""
    p = os.path.join(paths.TEX, "cvdrop_logos.json")
    if not os.path.exists(p):
        return [("flank_port", (52, 9, 14), (21.5, 9, 12.7), 50), ("flank_stbd", (-52, 9, 14), (-21.5, 9, 12.7), 50),
                ("rear_logo", (0, 70, 16), (0, 30, 12), 35)]
    with open(p) as fh:
        logos = json.load(fh)
    out, seen = [], set()
    for e in logos:
        nm = "rear_logo" if e["tag"] == "rear" else ("flank_port" if e["side"] > 0 else "flank_stbd")
        if nm in seen:
            continue
        seen.add(nm)
        pos, nn = Vector(e["pos"]), Vector(e["n"])
        out.append((nm, tuple(pos + nn * (36 if e["tag"] == "rear" else 22)), tuple(pos), 40))
    return out


cfg = dict(hold=(-HOLD_HW - 0.05, HOLD_HW + 0.05, Y_FLOOR0 - 0.05, HOLD_Y1 + 0.05, ZF - 0.05, ZC + 0.05),
           classify=classify, atlas=4096, bay_close=((6, -64, 8), (0, -8, 9), 40),
           ctr=tuple(ctr), dist=210, ramp_view=((0, -18, 7), (-0.55, -1.3, 0.42), 135), bay_light=(0, 0, 14),
           nose=((-18, -62, 30), (0, -30, 19), 60), small=((31, -14, -7), (22.5, -6, 2.0), 60),
           extra=logo_cams() + [("thrusters", (8, 50, 6), (0, 30, 8), 55), ("wingtip", (60, 30, 22), (36, 18, 12), 50)],
           stock=(os.path.join(paths.STOCK, "TRO", "cvrecy.mesh"), os.path.join(paths.STOCK_TEX, "TRO", "DIFF", "cvrecy_d.dds"),
                  (-46.0, -28.0)),
           compare_dist=170)
C.package(ship, ao, FAC, cfg, cargo, OPEN, report)
