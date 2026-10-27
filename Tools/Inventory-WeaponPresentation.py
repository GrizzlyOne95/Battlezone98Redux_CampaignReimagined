"""Inventory stock BZR + effective CR weapons and combat-unit recoil topology.

Read-only: stock ODF/VDF and CR source. Legacy models use the shared toolbox
reader. Reports contain authored metadata, not redistributed model data.
"""
from pathlib import Path
import argparse
import csv
import json
import re
import sys
from collections import Counter
from bzmodellibs import legacy, toolbox_root

ROOT = Path(__file__).resolve().parents[1]


def parse(text):
    section, out = "", {}
    for line in text.splitlines():
        line = line.split("//", 1)[0].strip()
        if line.startswith("["):
            section = line.strip("[]").lower()
        elif "=" in line:
            key, value = line.split("=", 1)
            out.setdefault(section, {})[key.strip().lower()] = value.strip().split(";", 1)[0].strip().strip('"')
    return out


def documents(folder):
    return {p.stem.lower(): {"source": str(p), "data": parse(p.read_text(errors="replace"))}
            for p in sorted(folder.glob("*.odf"))}


def inventory(stock):
    stock_docs, cr_docs = documents(stock), documents(ROOT / "ODF")
    effective = {**stock_docs, **cr_docs}
    shipping=json.loads((ROOT/'Shipping/shipping.lock.json').read_text())
    assets={Path(e['runtime']).name.lower():ROOT/Path(e['source'].replace('\\','/')) for e in shipping['files']
            if Path(e['runtime']).suffix.lower() in ('.vdf','.sdf','.geo','.skeleton')}
    weapons, units, models = [], [], {}
    for name, doc in effective.items():
        data = doc["data"]
        if "weaponclass" in data:
            w = data["weaponclass"]
            if "classlabel" in w:
                weapons.append({"odf": name, "class": w["classlabel"], "name": w.get("wpnname", ""),
                    "ordnance": w.get("ordname", ""), "parent": w.get("basename", ""),
                    "scope": "CR override" if name in stock_docs and name in cr_docs else "CR" if name in cr_docs else "stock",
                    "category": w.get("wpncategory", ""),
                    "delay": data.get("cannonclass", {}).get("shotdelay", ""),
                    "producer": "cannon factory" if w["classlabel"] in ("cannon", "mortar", "snipergun") else
                                "machinegun factory (companion OpenShim change; live pending)" if w["classlabel"] == "machinegun" else "other producer pending"})
        game = data.get("gameobjectclass", {})
        slots = [{"slot": i, "weapon": game.get("weaponname" + str(i), ""), "hardpoint": game.get("weaponhard" + str(i), "")}
                 for i in range(1, 6) if game.get("weaponname" + str(i), "").lower() not in ("", "null", "none")]
        if not slots:
            continue
        # Include armed structures/pilots too, rather than silently losing their weapons.
        model_name = game.get("basename", name).lower()
        if model_name not in models:
            model_path = next((p for p in (assets.get(model_name+'.vdf'),assets.get(model_name+'.sdf'),
                stock / (model_name + ".vdf"), stock / (model_name + ".sdf")) if p and p.exists()), None)
            if model_path:
                try:
                    model = legacy.read_vdf(model_path) if model_path.suffix == ".vdf" else legacy.read_sdf(model_path)
                    parts = {p.name.lower(): p for p in model.band(0)}
                    models[model_name] = (model, parts, "read")
                except ValueError as exc:
                    models[model_name] = (None, {}, "unreadable: " + str(exc))
            else:
                models[model_name] = (None, {}, "no legacy model; inspect Ogre hierarchy")
        model, parts, status = models[model_name]
        sys.path.insert(0,str(toolbox_root()))
        from battlezone.meshes.ogre_skeleton import read_skeleton
        skeleton_path=next((p for p in (assets.get(model_name+'.skeleton'),
            stock.parent/'BZ_ASSETS/common/models'/(model_name+'.skeleton')) if p and p.exists()),None)
        skeleton=read_skeleton(skeleton_path) if skeleton_path else None
        for slot in slots:
            matches = [p for p in parts.values() if slot["hardpoint"] and p.name.lower().endswith(slot["hardpoint"].lower())]
            slot["muzzle_nodes"] = [p.name for p in matches]
            slot["parents"] = [p.parent for p in matches]
            candidates = []
            for p in matches:
                parent = parts.get(p.parent.lower())
                # A dedicated barrel is a candidate; a hull/whole turret is never
                # automatically called a recoil barrel just because it owns GC1.
                if parent and re.search(r"bg[a-z0-9]$", parent.name, re.I):
                    track = model.track(parent.name)
                    moving = track and len({tuple(round(x, 5) for x in value) for _, value in track.positions}) > 1
                    estimate=None
                    geo_path=next((f for f in (assets.get(parent.name.lower()+'.geo'),stock/(parent.name.lower()+'.geo')) if f and f.exists()),None)
                    if geo_path:
                        geo=legacy.read_geo(geo_path)
                        if geo.positions: estimate=round(max(v[2] for v in geo.positions)-p.matrix[11],3)
                    candidates.append({"node": parent.name, "translation_animated": bool(moving),
                        "barrel_forward_tip_estimate":estimate})
            slot["recoil_candidates"] = candidates
            slot['cockpit_muzzle_nodes']=[p.name for p in model.band(4) if slot['hardpoint'] and p.name.lower().endswith(slot['hardpoint'].lower())] if model else []
            if not model and skeleton:
                slot['ogre_muzzle_bones']=[b.name for b in skeleton.bones if slot['hardpoint'] and b.name.lower().endswith(slot['hardpoint'].lower())]
            slot["plan"] = "dedicated barrel slide candidate" if candidates else "author additive recoil parent/clip; preserve aiming and locomotion"
        units.append({"odf": name, "name": game.get("unitname", ""), "class": game.get("classlabel", ""),
                      "scope": "CR" if name in cr_docs else "stock", "model": model_name, "model_status": status,
                      "role":"weapon supplier; not a firing unit" if game.get('classlabel')=='armory' else 'combat carrier',
                      "ogre_clips":[{'name':a.name,'seconds':a.length} for a in skeleton.animations] if skeleton else [], "slots": slots})
    return {"weapons": sorted(weapons, key=lambda w: w["odf"]), "units": sorted(units, key=lambda u: u["odf"])}


def report(data, output):
    output.mkdir(parents=True, exist_ok=True)
    choices=json.loads((ROOT/'References/WeaponPresentation/profiles.json').read_text())['weapons']
    for weapon in data['weapons']:
        choice=choices.get(weapon['odf'],{})
        weapon['flash_profile']=choice.get('profile') or ''
        weapon['flash_decision']=choice.get('decision','new definition; review required')
        weapon['casing_type']=choice.get('casing_type','none')
        weapon['casing_decision']=choice.get('casing_decision','new definition; review required')
    (output / "inventory.json").write_text(json.dumps(data, indent=2) + "\n")
    with (output / "weapons.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(data["weapons"][0]))
        writer.writeheader(); writer.writerows(data["weapons"])
    with (output / "recoil.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["unit", "name", "role", "model", "model_status", "slot", "weapon", "hardpoint", "muzzle_nodes", "cockpit_muzzle_nodes", "parents", "candidates", "ogre_clips", "plan"])
        for unit in data["units"]:
            for slot in unit["slots"]:
                writer.writerow([unit["odf"], unit["name"],unit['role'], unit["model"], unit["model_status"], slot["slot"], slot["weapon"], slot["hardpoint"],
                    ",".join(slot["muzzle_nodes"]), ','.join(slot['cockpit_muzzle_nodes']), ",".join(slot["parents"]), json.dumps(slot["recoil_candidates"]),
                    ','.join(a['name'] for a in unit['ogre_clips']), slot["plan"]])
    print("Inventory:", len(data["weapons"]), "weapons,", len(data["units"]), "armed ODFs; classes", dict(Counter(w["class"] for w in data["weapons"])))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stock", required=True, type=Path, help="extracted shipping StockODFFiles directory")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    report(inventory(args.stock), args.output)
