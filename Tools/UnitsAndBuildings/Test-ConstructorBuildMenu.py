#!/usr/bin/env python3
"""Check the Constructor build-menu trees (OpenShim PRODMENU) without a game.

Each CR Constructor keeps its stock flat buildItem1..7 list (the AI and peers
without OpenShim read it) and adds buildMenuRoot, a [Builder] tree whose root
page shows the first six buildings plus "More" (the seventh and a shield tower).
Run from the repository root: python Tools/UnitsAndBuildings/Test-ConstructorBuildMenu.py
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ODF = ROOT / "ODF"
FACTIONS = {"av": "a", "sv": "s", "bv": "b", "cv": "c"}
checks = 0


def check(value, message):
    global checks
    if not value:
        raise SystemExit("FAIL: " + message)
    checks += 1


def keys(path):
    return dict(re.findall(r'^\s*(\w+)\s*=\s*"?([^"\r\n]*?)"?\s*$', path.read_text(), re.M))


def sections(path):
    return re.findall(r"^\[(\w+)\]", path.read_text(), re.M)


lock = json.loads((ROOT / "Shipping" / "shipping.lock.json").read_text())
shipped = {e["runtime"].lower() for e in lock["files"]}

for veh, p in FACTIONS.items():
    cnst = ODF / f"{veh}cnst.odf"
    k = keys(cnst)
    flat = [k[f"buildItem{i}"] for i in range(1, 8)]
    check("buildItem8" not in k, f"{cnst.name}: the stock rig shows only 7 slots")
    rt, more, shield = f"b_cn{veh}rt", f"b_cn{veh}mr", f"{p}bshtw"
    check(k.get("buildMenuRoot") == rt, f"{cnst.name}: buildMenuRoot should be {rt}")
    rk, mk = keys(ODF / f"{rt}.odf"), keys(ODF / f"{more}.odf")
    for name, bk in ((rt, rk), (more, mk)):
        check(len(name) <= 8, f"{name}: Builder tokens are 8 characters")
        check(sections(ODF / f"{name}.odf") == ["Builder"], f"{name}: must be a [Builder] ODF")
        check(f"{name}.odf" in shipped, f"{name}.odf is not in the shipping lock")
    root_items = [rk.get(f"buildItem{i}") for i in range(1, 8)]
    check(root_items == flat[:6] + [more], f"{rt}: root page should be the first six buildings plus {more}")
    check("buildItem8" not in rk, f"{rt}: the root page holds 7 entries")
    more_items = [mk.get(f"buildItem{i}") for i in range(1, 3)]
    check(more_items == [flat[6], shield], f"{more}: should hold {flat[6]} and {shield}")
    # A submenu page holds capacity-1 entries plus Back: at most 6.
    check(not any(f"buildItem{i}" in mk for i in range(7, 11)), f"{more}: a submenu shows at most 6 entries")
    sk = keys(ODF / f"{shield}.odf")
    check(sk.get("classLabel") == "shieldtower", f"{shield}: classLabel shieldtower")
    check(sk.get("baseName") == f"{p}bshld", f"{shield}: uses the faction shield model")
    check(sk.get("teamFilter") == "enemies" and sk.get("affectAllies") == "false", f"{shield}: enemies only")
    check(int(sk.get("scrapCost", "0")) > 0, f"{shield}: has a scrap cost")
    check(f"{shield}.odf" in shipped, f"{shield}.odf is not in the shipping lock")
    for item in flat:
        check((ODF / f"{item}.odf").is_file(), f"{item}.odf missing")

print(f"Constructor build menus: {checks} checks passed")
