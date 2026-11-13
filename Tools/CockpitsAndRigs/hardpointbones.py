"""Skeleton side of the hardpoint receipts (References/Hardpoints/<unit>.json).

The VDF part is the engine's hardpoint; the Ogre skeleton carries a bone of the same name that the
presentation layer reads (Tools/Weapons/Build-WeaponFlashes.py measures muzzle offsets from it). Stock
exports hang that bone from its VDF parent at the mirrored VDF local matrix (Ogre = diag(-1,1,1) of
native), so a receipt part's bone takes the same rule: parent = the receipt owner, position =
mirror(receipt position), rotation = mirror(receipt rotation). A stock bone whose rotation differs
from its exported VDF part (svtank SCZ11GC1 carries a -90 degree X exporter axis fix) keeps that
difference. Both skeleton writers use this: Tools/CockpitsAndRigs/Build-WeaponRigs.py (rigged models' _recoil
skeletons) and Tools/CockpitsAndRigs/Build-UnitAnimSlots.py (stock skeletons the CR meshes reference).
"""
import sys as _sys; from pathlib import Path as _Path
_sys.path.insert(0, str(_Path(__file__).resolve().parent.parent))  # Tools/ root: shared libs (bzmodellibs, bcdds, ...)
import json
import subprocess
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation

from bzmodellibs import legacy

ROOT = Path(__file__).resolve().parents[2]
RECEIPTS = ROOT / "References" / "Hardpoints"
GAME = Path(r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux")
MIRROR = np.diag([-1.0, 1.0, 1.0])


def receipt(unit):
    path = RECEIPTS / (unit + ".json")
    if not path.exists():
        return None
    r = json.loads(path.read_text())
    return r if r.get("parts") else None


def units():
    return sorted(p.stem for p in RECEIPTS.glob("*.json") if receipt(p.stem))


def frame(m12):
    """Column rotation matrix of a 12-float native matrix (r, u, f, p)."""
    return np.asarray(m12[:9], float).reshape(3, 3).T


def base_matrices(r, game=GAME, stock_dir=None):
    """{part: 12-float matrix} of the VDF the receipt was drawn from (its `base`): CR's file at
    that revision, or the stock one (from stock_dir, else the game's StockODFFiles)."""
    model = r["model"]
    if r["base"].startswith("CR@"):
        raw = subprocess.run(["git", "-C", str(ROOT), "show", "--no-textconv",
                              r["base"][3:] + ":Assets/ModelFixes/%s.vdf" % model],
                             capture_output=True, check=True).stdout
    elif r["base"] == "stock":
        raw = (Path(stock_dir or Path(game) / "StockODFFiles") / (model + ".vdf")).read_bytes()
    else:
        raise ValueError("%s: unknown receipt base %r" % (model, r["base"]))
    return {p.name: p.matrix for p in legacy.read_vdf(raw).band(0)}


def poses(r, old_quat, game=GAME, stock_dir=None):
    """[(name, owner, position xyz, quaternion xyzw, new)] for each receipt part.

    old_quat(name) gives the bone's current local orientation (xyzw), or None when there is no
    such bone; an existing receipt part must have a bone and a new one must not."""
    base = base_matrices(r, game, stock_dir)
    out = []
    for p in r["parts"]:
        q0 = old_quat(p["name"])
        if p["existing"] != (q0 is not None):
            raise ValueError("%s: %s is %s in the receipt but %s in the skeleton"
                             % (r["model"], p["name"], "existing" if p["existing"] else "new",
                                "present" if q0 is not None else "absent"))
        rot = MIRROR @ frame(p["matrix"]) @ MIRROR
        if q0 is not None:
            exported = MIRROR @ frame(base[p["name"]]) @ MIRROR
            rot = rot @ exported.T @ Rotation.from_quat(q0).as_matrix()
        pos = MIRROR @ np.asarray(p["matrix"][9:12], float)
        out.append((p["name"], p["owner"], tuple(float(v) for v in pos),
                    tuple(float(v) for v in Rotation.from_matrix(rot).as_quat()), q0 is None))
    return out
