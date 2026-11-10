"""Checks the shipped hardpoint mounts (Tools/Build-HardpointMounts.py) against their receipts.

    python Tools/Test-HardpointMounts.py

For each References/HardpointMounts/<unit>.json, through the toolkit serializers only (no Blender):
  - the shipped mesh and VDF load (submeshes > 0, VDF parts > 0, the hardpoint part present),
  - the <unit>_hpmount submesh: triangles == the receipt, within the kit cap, closed and manifold
    (welded positions, every edge used by exactly two triangles), every vertex on the owner bone,
  - in the VDF pose the buried saddle lies under the hull skin (rays along +normal hit the hull),
  - the mount's lowest point is not below the hull's (it never touches the ground first),
  - the hardpoint part: parent == owner, at the receipt point, just inside the muzzle,
  - nothing of the hull or glass lies in front of the muzzle,
  - bm.part_clearance: the mount touches no other VDF part at rest and its owner only with its
    buried saddle, stays out of the other guns' lines of fire, and keeps clear of every gimbal
    part (66/67/68) swept through +-23 deg, which also stays out of the mount's line of fire
    (unless the receipt's fireThrough names it),
  - the four <unit>_hpmount textures and the material block exist.
"""
from pathlib import Path
import importlib.util, json, sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT / 'Tools'))
_spec = importlib.util.spec_from_file_location('hardpointmounts', ROOT / 'Tools/Build-HardpointMounts.py')
bm = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(bm)
nj, wr, shared, legacy, VES, S = bm.nj, bm.wr, bm.shared, bm.legacy, bm.VES, bm.S


def skeleton_for(mesh):
    folders = (ROOT / 'Assets/ModelFixes', ROOT / 'Assets/Models', wr.GAME / 'BZ_ASSETS/common/models')
    sk = next((f / mesh.skeleton_name for f in folders if (f / mesh.skeleton_name).is_file()), None)
    sk = sk or next(p for p in folders[2].rglob('*.skeleton') if p.name.lower() == mesh.skeleton_name.lower())
    return wr.read_skeleton(sk)


def check(receipt):
    unit = receipt['unit']; material = receipt['material']; errors = []
    assert material == f'{unit}_hpmount', (unit, 'material must be named <unit>_hpmount', material)
    mesh = shared.read_mesh(ROOT / f'Assets/ModelFixes/{unit}.mesh')
    assert len(mesh.submesh_list) > 0, (unit, 'mesh has no submeshes')
    parts = legacy.read_vdf((ROOT / f'Assets/ModelFixes/{unit}.vdf').read_bytes()).band(0)
    assert len(parts) > 0, (unit, 'VDF has no parts')
    W, by = nj.vdf_world(parts); skeleton = skeleton_for(mesh); pose = nj.vdf_pose(skeleton, W)
    part = by.get(receipt['part'].lower()); assert part is not None, (unit, 'hardpoint part missing from the VDF', receipt['part'])

    mounts = [s for s in mesh.submesh_list if s.material_name == material]
    assert len(mounts) == 1, (unit, f'expected one {material} submesh', len(mounts))
    sub = mounts[0]; index = np.array(sub.index_array).reshape(-1, 3)
    if len(index) != receipt['triangles'] or len(index) > bm.TRIANGLE_CAP:
        errors.append(f"{len(index)} triangles (receipt {receipt['triangles']}, cap {bm.TRIANGLE_CAP})")
    owner = next(b for b in skeleton.bones if b.name.lower() == receipt['owner'].lower())
    bones = {a.bone_index for a in sub.bone_assignments()}
    if bones != {owner.handle}:
        errors.append(f'bone assignments {sorted(bones)}, expected only {owner.name} ({owner.handle})')

    posed = [(m, q, tt) for m, q, n, uv, tt in nj.posed_parts(mesh, pose)]  # a material may span several submeshes
    p, t = next((q, tt) for m, q, tt in posed if m == material)
    _, weld = np.unique(np.round(p, 5), axis=0, return_inverse=True); weld = weld.reshape(-1)
    tri = weld[t]; edges = np.sort(np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]]), axis=1)
    _, uses = np.unique(edges, axis=0, return_counts=True)
    if (uses != 2).any():
        errors.append(f'not manifold: {int((uses != 2).sum())} edges not shared by exactly two triangles')

    hull = np.concatenate([q[tt] for m, q, tt in posed if m != material and 'glass' not in m.lower()])
    glass_hull = np.concatenate([q[tt] for m, q, tt in posed if m != material])
    seat = np.array(receipt['frame']['seat']); normal = np.array(receipt['frame']['normal']); bury = receipt['bury']
    floor = np.unique(np.round(p[(p - seat) @ normal < -.9 * bury], 6), axis=0)
    if len(floor) < 4:
        errors.append(f'saddle floor has {len(floor)} vertices below the hull, expected >= 4')
    misses = sum(nj.ahead(hull, v, normal) is None for v in floor)
    if misses:
        errors.append(f'{misses} saddle floor vertices with no hull above them (a floating corner)')

    ground = float(p[t][..., 1].min() - hull[..., 1].min())
    if ground < -1e-4:
        errors.append(f'mount hangs {-ground:.3f} m below the hull: it would touch the ground first')
    if abs(ground - receipt['checks']['groundClearance']) > 1e-3:
        errors.append(f"ground clearance {ground:+.4f}, receipt {receipt['checks']['groundClearance']:+.4f}")

    if (part.parent or '').lower() != receipt['owner'].lower():
        errors.append(f'{part.name} parent {part.parent}, expected the owner {receipt["owner"]}')
    at = W[part.name.lower()][1] * S; muzzle = np.array(receipt['muzzle']); fire = nj.unit_vectors(np.array(receipt['fire']))
    if np.linalg.norm(at - receipt['hardpoint']) > 1e-3:
        errors.append(f'{part.name} at {at.round(4)}, receipt {receipt["hardpoint"]}')
    if np.linalg.norm(at - muzzle) > receipt['inset'] + .01:
        errors.append(f'{part.name} {np.linalg.norm(at - muzzle):.3f} m from the muzzle')
    side = nj.unit_vectors(np.cross(fire, normal)); up = nj.unit_vectors(np.cross(side, fire))
    blocked = [o for o in (0 * side, side * .03, -side * .03, up * .03, -up * .03) if nj.ahead(glass_hull, muzzle + fire * .01 + o, fire) is not None]
    if blocked:
        errors.append(f'{len(blocked)} of 5 line-of-fire rays hit the hull or glass')

    groups = bm.part_triangles(mesh, pose, skeleton, parts, skip=material)
    _, clash = bm.part_clearance(p[t], groups, parts, W, receipt['owner'], seat, normal, receipt['checks']['saddleTop'], muzzle, fire,
                                 receipt['part'], receipt.get('fireThrough', ()))
    errors += clash

    for k in 'DNSE':
        if not (ROOT / f'Assets/Textures/{material}_{k}.dds').is_file():
            errors.append(f'missing Assets/Textures/{material}_{k}.dds')
    mat = (ROOT / f'Materials/{unit}.material').read_text(errors='replace')
    if f'material {material}' not in mat:
        errors.append(f'Materials/{unit}.material has no {material} block')
    return errors


def main():
    receipts = sorted((ROOT / 'References/HardpointMounts').glob('*.json'))
    assert receipts, 'no References/HardpointMounts receipts'
    failed = 0
    for path in receipts:
        receipt = json.loads(path.read_text()); assert receipt['unit'] == path.stem, (path, 'unit does not match the file name')
        errors = check(receipt)
        print(f"{receipt['unit']}: {receipt['piece']} {receipt['triangles']} tris on {receipt['owner']}: " + ('OK' if not errors else 'FAIL'))
        for e in errors:
            print('  ' + e)
        failed += bool(errors)
    print(f'{len(receipts) - failed}/{len(receipts)} hardpoint mounts pass')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
