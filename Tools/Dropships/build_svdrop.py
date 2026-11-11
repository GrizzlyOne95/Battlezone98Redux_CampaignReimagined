"""CCA 'Hind heavy-lifter' dropship `svdrop`: the approved blockout geometry (unchanged), UV-mapped and textured
with the `cdrv` atlas (texgen_svstock.py), rigged and exported like build_dropship.py (avdrop).
The fuselage is the hold, sized for a packed svrecy + 4 svtank (two rows of two behind it).
CCA unit language (svrecy/svmuf/svtank): arrowhead dorsal deck plate overhanging the hull, beaked
stepped tandem glazed nose (gunner low, pilot high), forward 'fang' sponsons, tall swept blade nacelles
on stub wings. No fans or rotors: lift comes from downward hover-jet nozzles recessed into the bottoms
of the fang sponsons and the blade-nacelle pods. Stern ramp behind clamshell doors, four landing legs.
Ground z 0, forward -Y, metres.
Run: python texgen_svstock.py, then blender -b -P build_svdrop.py [-- --norender]"""
import json
import math
import os
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dropkit as C                                   # noqa: E402
from dropkit import prof8, box, loft, band, union, cut, recess, solid, VENT, GLASS, NOZZLE, LAMP  # noqa: E402
from shipkit import circle                            # noqa: E402
import paths                                          # noqa: E402
import bpy                                            # noqa: E402
from mathutils import Vector                          # noqa: E402

FAC = "cdrv"      # texture prefix (texgen_svstock.py)
P = "sdr11"
# ---- cargo (packed pose; see report): svrecy 28.95 W x 54.46 L x 14.64 H (classic VDF band-0 rest pose =
# frame-0 keys: the two exhaust nacelles lie flat pointing aft and stand up on deploy), svtank 8.56 x 8.39 x 3.79
RECY = (28.95, 54.46, 14.64)
TANK = (8.56, 8.39, 3.79)
ROW_GAP = 1.0
# ---- hold: recycler forward (1 m to the bulkhead, 1.5 m a side), 1.5 m gap, two rows of two tanks, ~1.2 m to the ramp
HOLD_HW, HOLD_Y0, HOLD_Y1, ZF, ZC = 16.0, -38.0, 39.0, 4.5, 20.5
HW, ZT, ZB, CT, CB = 18.0, 23.0, 3.0, 5.0, 3.0        # outer hull section (2 m walls, 2.5 m roof, 1.5 m floor)
RAMP_L = ZC - ZF                                          # 16 m, closes the whole stern opening
RAMP_OPEN = math.degrees(math.asin(ZF / RAMP_L)) + 90     # 106.3 deg: lip on the ground at 16.3 deg
RAMP_Y = HOLD_Y1 + 0.1                                    # ramp outer face / hinge line
CLAM_OPEN = 100.0
BLADE_X = 25.5                                            # blade-nacelle centre line
JET_R = 1.6                                               # hover-jet nozzle radius

C.reset()
parts = []      # (bone, object, head, parent)

# ------------------------------------------------------------------ body
BODY = [(-55, prof8(1.6, 10.2, 8.2, 0.6, 0.6)),         # beaked gunner nose tip (lower deck)
        (-51, prof8(7.5, 12.5, 6, 3, 1.5)),
        (-46, prof8(13, 17, 4.5, 4.5, 2.5)),
        (-40, prof8(HW, ZT, ZB, CT, CB)),
        (HOLD_Y1, prof8(HW, ZT, ZB, CT, CB))]
body = solid(P + "bdy", loft(BODY))
CANOPY = [(-47.5, prof8(4.5, 17.2, 13.5, 1.5, 0.5)),     # pilot deck, stepped up behind the gunner
          (-43.5, prof8(6.5, 25.0, 14.5, 2.5, 0.5)),
          (-33, prof8(7.0, 25.5, 19.5, 2.5, 0.5)),
          (-26, prof8(5.5, 24.0, 21.0, 1.5, 0.5))]
union(body, loft(CANOPY), "canopy")
# arrowhead dorsal deck plate (svrecy/svmuf lid): sharp chamfered edges overhanging the hull sides
DECK = [(-31, prof8(5.0, 24.6, 22.4, 1.0, 0.8)),
        (-19, prof8(20.5, 24.6, 22.4, 1.1, 0.9)),
        (HOLD_Y1 - 8, prof8(20.5, 24.6, 22.4, 1.1, 0.9)),
        (HOLD_Y1 - 1.5, prof8(14.0, 24.6, 22.4, 1.0, 0.8))]
union(body, loft(DECK), "deckplate")
for sx in (1, -1):
    cx = 8.0 * sx
    NAC = [(-12, prof8(2.2, 28.0, 23.5, 1.0, 0.4, cx)),
           (-7, prof8(3.2, 30.0, 23.5, 1.6, 0.5, cx)),
           (HOLD_Y1 - 5, prof8(3.2, 30.0, 23.5, 1.6, 0.5, cx)),
           (HOLD_Y1 - 1, prof8(2.8, 29.6, 23.6, 1.4, 0.5, cx))]
    union(body, loft(NAC), f"nacelle{sx:+d}")
for sx in (1, -1):
    # forward fang sponsons flanking the gunner nose (svtank/svrecy claws); hover jets in their bottoms
    fx = 18.5 * sx
    FANG = [(-53, prof8(0.7, 6.8, 5.2, 0.3, 0.3, fx)),
            (-45, prof8(2.6, 10.0, 3.0, 1.4, 0.6, fx)),
            (-34, prof8(2.6, 10.0, 3.0, 1.4, 0.6, fx)),
            (-30.5, prof8(1.8, 9.0, 4.0, 0.8, 0.5, fx))]
    union(body, loft(FANG), f"fang{sx:+d}")
    # anhedral stub wing into a tall swept blade nacelle with a hover-jet pod at its foot
    bx = BLADE_X * sx
    wing = [(16.5 * sx, 12.0), (bx, 10.5), (bx, 12.6), (16.5 * sx, 16.6)]
    union(body, loft([(-8, wing), (6, wing)]), f"stubwing{sx:+d}")
    BLADE = [(-12, prof8(1.2, 9.0, 3.0, 0.5, 0.5, bx)),
             (-3, prof8(1.7, 27.0, 3.0, 0.8, 0.5, bx)),
             (8, prof8(1.7, 27.0, 3.0, 0.8, 0.5, bx)),
             (12, prof8(1.2, 27.0, 15.0, 0.5, 0.5, bx))]
    union(body, loft(BLADE), f"blade{sx:+d}")
    POD = [(-11, prof8(1.8, 7.0, 3.5, 0.8, 0.6, bx)),
           (-7, prof8(2.9, 8.5, 2.2, 1.2, 0.9, bx)),
           (7, prof8(2.9, 8.5, 2.2, 1.2, 0.9, bx)),
           (11, prof8(2.0, 7.5, 3.2, 0.8, 0.6, bx))]
    union(body, loft(POD), f"jetpod{sx:+d}")

# hold: open at the stern (the ramp closes it)
cut(body, box((0, (HOLD_Y0 + HOLD_Y1 + 1.5) / 2, (ZF + ZC) / 2), (2 * HOLD_HW, HOLD_Y1 + 1.5 - HOLD_Y0, ZC - ZF)), "hold")
# hover-jet nozzles: round recesses into the flat bottoms (fangs z 3.0, pods z 2.2)
for sx in (1, -1):
    for y in (-41.5, -36.5):
        cut(body, loft([(2.4, circle(JET_R, y, 16, 18.5 * sx)), (3.6, circle(JET_R, y, 16, 18.5 * sx))], axis="z"),
            f"fangjet{sx:+d}{y}", NOZZLE)
    for y in (-3.5, 3.5):
        cut(body, loft([(1.6, circle(JET_R, y, 16, BLADE_X * sx)), (2.8, circle(JET_R, y, 16, BLADE_X * sx))], axis="z"),
            f"podjet{sx:+d}{y}", NOZZLE)
# panel lines (recessed grooves on the broad plates), vents, lamps, nozzles
for sx in (1, -1):
    for y in (-22, 14, 28):
        cut(body, box((HW * sx, y, 12), (0.7, 0.3, 11)), f"sidegroove{sx:+d}{y}")
    for z in (18, 22):
        cut(body, box(((BLADE_X + 1.7) * sx, 2, z), (0.6, 14, 0.3)), f"bladegroove{sx:+d}{z}")
for y in (0, 20):
    cut(body, box((0, y, 24.6), (8.6, 0.3, 0.7)), f"topgroove{y}")
for sx in (1, -1):
    cx = 8.0 * sx
    cut(body, loft([(-13, prof8(1.6, 27.4, 25.4, 0.6, 0.3, cx)), (-9, prof8(1.6, 27.4, 25.4, 0.6, 0.3, cx))]),
        f"intake{sx:+d}", VENT)
    cut(body, loft([(HOLD_Y1 - 3, prof8(2.0, 28.9, 25.5, 0.9, 0.4, cx)),
                    (HOLD_Y1 + 0.5, prof8(2.0, 28.9, 25.5, 0.9, 0.4, cx))]), f"nozzle{sx:+d}", NOZZLE)
    cut(body, box((15.0 * sx, 14, 24.6), (0.8, 8, 2.4)), f"vent{sx:+d}", VENT)
    cut(body, box((HW * sx, -36, 14), (0.6, 1.2, 1.2)), f"lamp{sx:+d}", LAMP)
# glazing: recessed panes, the uncut border of each facet is the frame
for i, j in ((0, 1), (0, 2), (0, 3), (1, 1), (1, 3)):
    recess(body, band(BODY, i, j), (0, -50, 9), f"gunnerglass{i}{j}", GLASS, inset=0.35)
for i, j in ((0, 1), (0, 2), (0, 3), (1, 1), (1, 3)):
    recess(body, band(CANOPY, i, j), (0, -38, 20), f"pilotglass{i}{j}", GLASS, inset=0.5)
parts.append((P + "bdy", body, (0, 0, 0), None))

# ------------------------------------------------------------------ stern ramp + clamshells
ramp = solid(P + "rmp", box((0, RAMP_Y - 0.6, (ZF + ZC) / 2), (2 * HOLD_HW - 0.2, 1.2, RAMP_L - 0.1)))
for z in (9, 16):
    cut(ramp, box((0, RAMP_Y, z), (28, 0.6, 0.3)), f"rampgroove{z}")
parts.append((P + "rmp", ramp, (0, RAMP_Y, ZF), P + "bdy"))


def half(hw, zt, zb, ct, cb, sx):
    pts = [(0.05, zb), (hw - cb, zb), (hw, zb + cb), (hw, zt - ct), (hw - ct, zt), (0.05, zt)]
    return [(x * sx, z) for x, z in pts]


for k, sx in ((1, 1), (2, -1)):
    CL = [(RAMP_Y + 0.05, half(17.95, 22.95, 3.05, 5, 3, sx)),
          (RAMP_Y + 4.9, half(14.5, 21.5, 5.5, 4.5, 2.5, sx)),
          (RAMP_Y + 9.4, half(8.0, 18.0, 8.5, 2.5, 1.5, sx))]
    cl = solid(f"{P}cl{k}", loft(CL))
    parts.append((f"{P}cl{k}", cl, (17.95 * sx, RAMP_Y + 0.05, 13.0), P + "bdy"))

# ------------------------------------------------------------------ landing legs
LEGS = [(1, -26, "lg1"), (1, 24, "lg2"), (-1, -26, "lg3"), (-1, 24, "lg4")]


def strut(r, f, s=1.1):
    r, f = Vector(r), Vector(f)
    d = (f - r).normalized()
    u = Vector((0, 1, 0))
    v = d.cross(u).normalized()

    def fn(sh):
        bm = sh.bm
        a = [bm.verts.new(r + u * i * s + v * j * s) for i, j in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
        b = [bm.verts.new(f + u * i * s + v * j * s) for i, j in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
        bm.faces.new(a)
        bm.faces.new(b)
        for i in range(4):
            k = (i + 1) % 4
            bm.faces.new([a[i], a[k], b[k], b[i]])
    return fn


for sx, y, nm in LEGS:
    root, foot = (17.2 * sx, y, 9.5), (22.0 * sx, y, 0.6)
    leg = solid(P + nm, loft([(0.0, circle(2.4, y, 8, 22 * sx)), (0.9, circle(2.0, y, 8, 22 * sx))], axis="z"))
    union(leg, strut(root, foot), f"strut_{nm}")
    parts.append((P + nm, leg, root, P + "bdy"))

bone_names = [p[0] for p in parts]
ship, ao = C.join_parts("svdrop", parts)

# ------------------------------------------------------------------ cargo proxies + fit checks
cargo = [C.cargo_box("svrecy_packed", RECY[0], RECY[1], RECY[2], 0, HOLD_Y0 + 1.0 + RECY[1] / 2, ZF + 0.2, (0.62, 0.56, 0.42, 1))]
row1 = HOLD_Y0 + 1.0 + RECY[1] + 1.5 + TANK[1] / 2
for y in (row1, row1 + TANK[1] + ROW_GAP):
    for x in (-5.5, 5.5):
        cargo.append(C.cargo_box(f"svtank_{len(cargo)}", TANK[0], TANK[1], TANK[2], x, y, ZF + 0.2, (0.5, 0.5, 0.4, 1)))
fit = {o.name: C.overlaps(o, ship) for o in cargo}
fit.update({f"{a.name}~{b.name}": C.overlaps(a, b) for i, a in enumerate(cargo) for b in cargo[i + 1:]})
assert not any(fit.values()), f"cargo intersects hull or cargo: {fit}"

mn, mx = C.bounds(C.evaluated_coords(ship))
ctr = (mn + mx) / 2
rad = max((Vector(p) - Vector(ctr)).length for p in C.evaluated_coords(ship))
OPEN = [(P + "rmp", "rot", "X", -RAMP_OPEN), (P + "cl1", "rot", "Z", -CLAM_OPEN), (P + "cl2", "rot", "Z", CLAM_OPEN)]
C.apply_pose(ao, OPEN)
rp = C.evaluated_coords(ship, P + "rmp")
rmn, rmx = C.bounds(rp)
lip = min(rp, key=lambda p: (p.z, -p.y))
slope = math.degrees(math.atan2(ZF - lip.z, lip.y - RAMP_Y))
assert -0.05 < rmn[2] < 0.3, f"ramp lip not on the ground: {rmn[2]}"
fit_open = {o.name: C.overlaps(o, ship) for o in cargo}
C.reset_pose(ao)

report = dict(
    ship="svdrop", overall=dict(W=round(mx[0] - mn[0], 2), L=round(mx[1] - mn[1], 2), H=round(mx[2] - mn[2], 2),
                                min=[round(v, 2) for v in mn], max=[round(v, 2) for v in mx],
                                bounding_sphere_r=round(rad, 1)),
    hold=dict(W=2 * HOLD_HW, L=HOLD_Y1 - HOLD_Y0, L_inside_closed_ramp=round(RAMP_Y - 1.2 - HOLD_Y0, 2), H=ZC - ZF,
              floor_z=ZF, ceiling_z=ZC, y=(HOLD_Y0, HOLD_Y1)),
    ramp=dict(length=RAMP_L, width=2 * HOLD_HW - 0.2, thickness=1.2, hinge=(0, RAMP_Y, ZF), open_deg=round(RAMP_OPEN, 2),
              lip_z_open=round(rmn[2], 3), slope_deg=round(slope, 2)),
    bones=bone_names, cargo_fit_overlaps=fit, cargo_fit_open=fit_open,
    cargo=dict(svrecy=RECY, svtank=TANK, recy_center_y=HOLD_Y0 + 1.0 + RECY[1] / 2, tank_rows_y=(row1, row1 + TANK[1] + ROW_GAP)),
    booleans=C.LOG)
print("DIMS", report["overall"], "RAMP", report["ramp"])
os.makedirs(C.OUT, exist_ok=True)
cfg = dict(hold=(-HOLD_HW - 0.05, HOLD_HW + 0.05, HOLD_Y0 - 0.05, HOLD_Y1 + 0.05, ZF - 0.05, ZC + 0.05),
           dark=dict(under=True, groups=(P + "lg",)), cells=True, ctr=tuple(ctr), dist=290, ramp_view=((0, 30, 8), (0.55, 1.3, 0.42), 190),
           nose=((-22, -78, 20), (0, -50, 13), 60), small=((24, -45, -9), (18.5, -39, 3.0), 60),
           stock=(os.path.join(paths.STOCK, "svrecy.mesh"),
                  os.path.join(paths.STOCK_TEX, "DIFF", "svrecy_D.dds"),
                  (-62.0, -10.0)),
           compare_dist=330)
C.package(ship, ao, FAC, cfg, cargo, OPEN, report)
