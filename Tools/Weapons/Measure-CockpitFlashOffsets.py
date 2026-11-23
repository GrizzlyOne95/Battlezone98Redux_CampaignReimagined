"""Measure `[CraftClass] cockpitFlashOffset<N>` for every CR craft with a *_cockpit.mesh.

In cockpit view the local player's muzzle flash must start at the end of the
cockpit model's barrel, not at the hull hardpoint plus flashOffset<N> (which is
buried in the cockpit gun mesh). OpenShim applies `cockpitFlashOffset<N>` instead
of `flashOffset<N>` for the player's own shots in cockpit view: "right up
forward" metres (each -20..20), relative to the HULL weapon hardpoint, in the
hardpoint's frame (the frame of its barrel node, as Build-WeaponFlashes.py).

Value = centre of the cockpit barrel's muzzle face (centroid of the vertices
within FACE m of the barrel's furthest-forward plane) minus the hull hardpoint,
plus MARGIN m forward. A barrel is a connected piece of a cockpit gun/barrel
submesh (material name containing "gun" or "barrel"). Slots with no such barrel
near the hardpoint line, and mortar/mine/special hardpoints (GM*, GS*), are
skipped and listed with the reason.

Meshes and skeletons are read only through the toolkit serializers
(bzmodellibs). Usage:

    python Tools/Weapons/Measure-CockpitFlashOffsets.py            # table + ODF lines
    python Tools/Weapons/Measure-CockpitFlashOffsets.py --write    # also (re)write the ODF blocks
    python Tools/Weapons/Measure-CockpitFlashOffsets.py bvtank     # selected crafts
"""
import sys as _sys; from pathlib import Path as _Path
_sys.path.insert(0, str(_Path(__file__).resolve().parent.parent))  # Tools/ root: shared libs (bzmodellibs)
from pathlib import Path
import argparse
import io
import os
import re
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree
from bzmodellibs import ogremesh as om, ogremesh_serializer as oms, ogreskeleton_serializer as oss

ROOT = Path(__file__).resolve().parents[2]
GAME = Path(os.environ.get("BZR_GAME_DIR", r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux"))
BEGIN, END = "// CR COCKPIT FLASH OFFSET BEGIN", "// CR COCKPIT FLASH OFFSET END"
# Generated blocks that sit at the top of [CraftClass]; Build-CombatPresentation.py inserts its
# recoil block straight after the flash block, so ours goes after whichever of them comes last.
GENERATED_ENDS = ("// CR CRAFT FLASH OFFSET END", "// CR CRAFT RECOIL END")
TIP_SLAB = 0.25     # m: front slice of the barrel that centres the flash on right/up
FACE = 0.05          # m: vertices this close to the furthest-forward plane form the muzzle face
MARGIN = 0.05        # m: flash starts just outside the barrel
MAX_LATERAL = 0.6    # m: barrel face centre must be this close to the hardpoint line (the X-mirror bug read 0.62-0.82 here)
MIN_BARREL_VERTS = 24
MAX_BEHIND = 0.3     # m: a muzzle further behind the hull hardpoint than this is not that slot's barrel
MAX_BARREL_WIDTH = 0.7  # m: a piece wider than this is a gun pod, not a barrel
GAP = 0.12           # m: vertices closer than this (right/up) belong to one barrel
MIN_DIFF = 0.1       # m: only write a key that moves the flash by more than this on some axis
GUN_MATERIAL = re.compile(r"gun|barrel", re.I)
MAX_FORWARD = 2.0       # m: a farther muzzle means the hull node is not on this barrel
SKIP_HARDPOINT = {"GM": "mortar/mine launcher: no barrel", "GS": "special/mine launcher: no barrel"}


def find_model(name):
    for d in ("Assets/ModelFixes", "Assets/Models"):
        if (ROOT / d / name).exists():
            return ROOT / d / name, "CR"
    for pattern in ("BZ_ASSETS*", ):
        for hit in GAME.glob(f"{pattern}/**/{name}"):
            return hit, "stock"
    return None, None


def read_odf(name):
    path = ROOT / "ODF" / (name + ".odf")
    if not path.exists():
        path = next(GAME.glob(f"BZ_ASSETS*/**/{name}.odf"), None)
    data, section = {}, ""
    if path is None:
        return data
    for line in path.read_text(errors="replace").splitlines():
        line = line.split("//")[0].strip()
        if line.startswith("["):
            section = line.strip("[] ").lower()
            continue
        m = re.match(r"(\w+)\s*=\s*(.*)", line)
        if m:
            data[(section, m.group(1).lower())] = m.group(2).strip().strip('"')
    return data


def skeleton(path):
    """(skeleton, {bone handle: (world position, world rotation 3x3)}) in bind pose."""
    sk = oss.SkeletonSerializer(io.BytesIO(path.read_bytes())).read()
    world = {}

    def transform(b):
        if b.handle in world:
            return world[b.handle]
        q = b.orientation
        w, x, y, z = q.w, q.x, q.y, q.z
        r = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                      [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                      [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
        pos = np.array([b.position.x, b.position.y, b.position.z])
        if b.parent is not None:
            pp, pr = transform(b.parent)
            pos, r = pp + pr @ pos, pr @ r
        world[b.handle] = (pos, r)
        return world[b.handle]

    for b in sk.bones():
        transform(b)
    return sk, world


def gun_vertices(path):
    """Positions (bone frame) of every vertex of the cockpit gun/barrel submeshes (material name has gun or barrel)."""
    mesh = oms.MeshSerializer(io.BytesIO(path.read_bytes())).read()
    out = []
    for sm in mesh.submesh_list:
        if not GUN_MATERIAL.search(sm.material_name or "") or sm.use_shared_vertices:
            continue
        vd = sm.vertex_data
        e = vd.vertex_declaration.find_by_semantic(om.VES.POSITION)
        b = vd.get_vertex_buffer(e.source)
        out.append(np.ndarray((vd.vertex_count, 3), "<f4", buffer=b.buffer, offset=e.offset,
                              strides=(b.vertex_size, 4)).astype(float))
    pts = np.vstack(out) if out else np.zeros((0, 3))
    # Ogre mesh vertices are X-mirrored against skeleton bones (the toolbox's read_mesh
    # un-mirrors them for Build-WeaponFlashes.py; the raw serializer used here does not).
    # Hardpoint bones and "right" are in the bone frame, so mirror X before measuring.
    pts[:, 0] *= -1
    return pts


def clusters(xy, eps=GAP):
    """Group 2D points that chain together within eps: [index array, ...]."""
    pairs = cKDTree(xy).query_pairs(eps, output_type="ndarray")
    n = len(xy)
    graph = coo_matrix((np.ones(len(pairs)), (pairs[:, 0], pairs[:, 1])), shape=(n, n))
    count, label = connected_components(graph, directed=False)
    return [np.flatnonzero(label == k) for k in range(count)]


def barrels(points, hp, frame):
    """Barrel candidates in the hardpoint frame: [(muzzle centre right/up/forward, vertex count)].

    Barrels are parallel to the hardpoint's forward axis, so vertices chain into one
    barrel by their right/up position. Forward is the centroid of the vertices within
    FACE m of the barrel's furthest-forward plane. Right/up is the middle of the front
    TIP_SLAB m (Build-WeaponFlashes.py's rule): a bevelled muzzle puts its furthest
    vertices on one lip, which would leave the flash on the edge instead of the centre.
    """
    local = (points - hp) @ frame
    out = []
    for idx in clusters(local[:, :2]):
        if len(idx) < MIN_BARREL_VERTS:
            continue
        pts = local[idx]
        top = pts[:, 2].max()
        slab = pts[pts[:, 2] >= top - TIP_SLAB]
        if (pts[:, :2].max(0) - pts[:, :2].min(0)).max() > MAX_BARREL_WIDTH:
            continue
        centre = (slab[:, :2].min(0) + slab[:, :2].max(0)) / 2
        muzzle = np.array([centre[0], centre[1], pts[pts[:, 2] >= top - FACE][:, 2].mean()])
        if muzzle[2] >= -MAX_BEHIND:
            out.append((muzzle, len(pts)))
    return out


def measure(name):
    """-> (rows, note). A row is a dict per weapon slot."""
    odf = read_odf(name)
    cockpit_mesh = ROOT / "Assets/Models" / f"{name}_cockpit.mesh"
    hull_skel, _ = find_model(f"{name}.skeleton")
    if not hull_skel or not cockpit_mesh.exists():
        return [], "hull skeleton or cockpit mesh missing"
    sk, world = skeleton(hull_skel)
    points = gun_vertices(cockpit_mesh)
    rows, claims = [], []
    for n in range(1, 6):
        hard = odf.get(("gameobjectclass", f"weaponhard{n}"))
        weapon = odf.get(("gameobjectclass", f"weaponname{n}"))
        if not hard or not weapon:
            continue
        row = {"slot": n, "hard": hard, "weapon": weapon}
        rows.append(row)
        if hard[:2].upper() in SKIP_HARDPOINT:
            row["skip"] = SKIP_HARDPOINT[hard[:2].upper()]
            continue
        bone = next((b for b in sk.bones() if b.name[-3:].upper() == hard.upper()), None)
        if bone is None:
            row["skip"] = "hull skeleton has no such hardpoint bone"
            continue
        if not len(points):
            row["skip"] = "cockpit mesh has no gun/barrel submesh"
            continue
        hp = world[bone.handle][0]
        frame = world[(bone.parent or bone).handle][1]   # barrel node frame (hardpoint bones may carry an exporter axis fix)
        if not (np.allclose(frame, np.eye(3), atol=0.02) and np.allclose(world[bone.handle][1], np.eye(3), atol=0.02)):
            # The frame OpenShim applies flashOffset<N> in for a rotated node is not
            # verified in game (svtank); an offset in the wrong frame would point away.
            row["skip"] = "rotated barrel node: in-game offset frame unverified"
            continue
        found = barrels(points, hp, frame)
        for face, count in found:
            claims.append((float(np.linalg.norm(face[:2])), n, tuple(np.round(hp + frame @ face, 1)), face, count))
    # Each cockpit barrel serves one slot. Lower slots choose first (slot 1 is the main gun),
    # each taking its nearest barrel that is still free.
    owner = {}
    for row in rows:
        if "skip" in row:
            continue
        mine = sorted((c for c in claims if c[1] == row["slot"]), key=lambda c: c[0])
        if not mine:
            row["skip"] = "no barrel-sized muzzle in the cockpit gun mesh (merged gun pod)"
            continue
        lateral, n, where, face, count = mine[0]
        if lateral > MAX_LATERAL:
            row["skip"] = f"nearest cockpit barrel is {lateral:.2f} m off the hardpoint line"
        elif abs(face[2]) > MAX_FORWARD:
            # Several metres between the hardpoint and the cockpit muzzle means the
            # hull node is not on this barrel (svtank); needs a live look first.
            row["skip"] = f"cockpit muzzle {face[2]:.2f} m from the hardpoint along the barrel: verify live"
        elif where in owner:
            row["skip"] = f"its nearest cockpit barrel already serves slot {owner[where]}"
        else:
            owner[where] = n
            row.update(offset=tuple(float(x) for x in face + np.array([0, 0, MARGIN])), verts=count, lateral=lateral)
            current = odf.get(("craftclass", f"flashoffset{n}"))
            if current is None:
                current = read_odf(row["weapon"]).get(("weaponclass", "flashoffset"), "0 0 0")
            row["current"] = tuple(float(x) for x in current.split()[:3])
            row["diff"] = float(np.abs(np.array(row["offset"]) - row["current"]).max())
    return rows, None


def fmt(v):
    return " ".join(f"{x:.2f}" for x in v)


def write_block(name, rows):
    path = ROOT / "ODF" / (name + ".odf")
    text = path.read_text()
    if BEGIN in text:
        a = text.index(BEGIN)
        b = text.index(END, a) + len(END)
        if text[b:b+1] == "\n":
            b += 1
        text = text[:a] + text[b:]
    keys = [r for r in rows if "offset" in r and r["diff"] > MIN_DIFF]
    if keys:
        block = [BEGIN, "// Player muzzle flash in cockpit view: cockpit barrel tip, relative to the hull hardpoint",
                 "// (right up forward, metres); replaces flashOffset<N> there. Regenerate:",
                 "// Tools/Weapons/Measure-CockpitFlashOffsets.py --write"]
        block += [f'cockpitFlashOffset{r["slot"]} = "{fmt(r["offset"])}"' for r in keys]
        block.append(END)
        ends = [text.index(e) + len(e) for e in GENERATED_ENDS if e in text]
        if ends:
            at = max(ends)
            at += 1 if text[at:at+1] == "\n" else 0
        else:
            section = re.search(r"(?im)^[ \t]*\[CraftClass\][^\n]*\n", text)
            if not section:
                return False
            at = section.end()
        text = text[:at] + "\n".join(block) + "\n" + text[at:]
    path.write_text(text)
    return bool(keys)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("crafts", nargs="*")
    ap.add_argument("--write", action="store_true", help="write the ODF blocks")
    args = ap.parse_args()
    names = args.crafts or sorted(p.name[:-len("_cockpit.mesh")] for p in (ROOT / "Assets/Models").glob("*_cockpit.mesh"))
    print(f"{'craft':8} {'slot':4} {'hard':4} {'weapon':9} {'cockpitFlashOffset':20} {'flashOffset(now)':18} {'diff':>5}  barrel")
    lines, skipped = [], []
    for name in names:
        rows, note = measure(name)
        if not rows:
            skipped.append((name, "-", note or "no weapon slots"))
        for r in rows:
            if "offset" not in r:
                skipped.append((name, f'slot {r["slot"]} {r["hard"]} {r["weapon"]}', r["skip"]))
                continue
            keep = r["diff"] > MIN_DIFF
            print(f"{name:8} {r['slot']:<4} {r['hard']:4} {r['weapon']:9} {fmt(r['offset']):20} {fmt(r['current']):18} {r['diff']:5.2f}  "
                  f"barrel {r['verts']} v, {r['lateral']:.2f} m off line{'' if keep else '  [within 0.1 m: no key]'}")
            if keep:
                lines.append((name, f'cockpitFlashOffset{r["slot"]} = "{fmt(r["offset"])}"'))
        if args.write:
            write_block(name, rows)
    print("\nODF lines:")
    for name, line in lines:
        print(f"  ODF/{name}.odf: {line}")
    print("\nSkipped:")
    for name, what, why in skipped:
        print(f"  {name} {what}: {why}")


if __name__ == "__main__":
    main()
