#!/usr/bin/env python3
"""Validate the Livewire text map and its campaign dependencies without a game.

Run from the repository root: python Tools/Test-SXShowcaseAssets.py
--reference-root permits checking a task-owned patch against read-only sources.
Native loading, terrain clearance, and camera framing still need the game.
"""

import argparse
import configparser
import json
import math
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--reference-root", type=Path)
    args = parser.parse_args()
    root = args.root
    reference = args.reference_root or root
    checks = 0

    def check(value, message):
        nonlocal checks
        if not value:
            raise ValueError(message)
        checks += 1

    def read(base, name):
        return (base / name).read_text(encoding="utf-8-sig")

    def field(text, name):
        match = re.search(r"(?m)^" + re.escape(name) + r" \[1\] =\n([^\n]+)", text)
        if not match:
            raise ValueError("missing native field: " + name)
        return match.group(1).strip()

    def objects(text):
        head, body = text.split("[GameObject]\n", 1)
        body, tail = body.split("\nname = LuaMission\n", 1)
        return head, [part.strip() for part in body.split("[GameObject]\n")], tail

    def paths(text):
        body = text.split("[AiPaths]\n", 1)[1]
        head, *blocks = body.split("[AiPath]\n")
        check(int(field(head, "count")) == len(blocks), "AiPaths count differs from serialized paths")
        return [block.strip() for block in blocks]

    bzn = read(root, "Missions/sxshow.bzn")
    source = read(reference, "Missions/crsetup.bzn")
    head, objs, tail = objects(bzn)
    source_head, source_objs, source_tail = objects(source)
    check("msn_filename = sxshow.bzn\n" in head, "mission filename must bind sxshow.lua")
    check("TerrainName = crsetup\n" in head, "prototype must reuse the setup terrain")
    check(int(field(head, "size")) == len(objs) == 32, "BZN object count must be 32")
    removed = [obj for obj in source_objs if field(obj, "team") == "5"]
    check(len(removed) == 7 and all(field(obj, "PrjID") == "avtur2b" for obj in removed),
          "source hostile fixture set changed; review map derivation")
    check(objs == [obj for obj in source_objs if field(obj, "team") != "5"],
          "prototype must preserve every non-hostile setup object")
    check(all(field(obj, "team") in {"0", "1"} for obj in objs), "unexpected hostile team")
    addresses = [re.search(r"(?m)^obj_addr = ([0-9A-Fa-f]+)$", obj).group(1) for obj in objs]
    check(len(set(addresses)) == len(addresses), "duplicate object serialization address")
    check(field(head, "seq_count") == field(source_head, "seq_count"), "sequence ceiling changed")
    check(tail.split("[AiPaths]\n", 1)[0] == source_tail.split("[AiPaths]\n", 1)[0],
          "LuaMission/AOI metadata changed unexpectedly")

    blocks, source_blocks = paths(bzn), paths(source)
    check(blocks[:len(source_blocks)] == source_blocks, "original setup paths changed")
    check(len(blocks) == len(source_blocks) + 6 == 20, "prototype must append six paths")
    terrain = configparser.ConfigParser()
    terrain.read_string(read(reference, "Missions/crsetup.trn"))
    size = terrain["Size"]
    min_x, min_z = float(size["MinX"]), float(size["MinZ"])
    max_x, max_z = min_x + float(size["Width"]), min_z + float(size["Depth"])
    labels, ids = [], []
    for block in blocks:
        label_field = re.search(r"(?m)^label = ([^\n]*)$", block)
        label = label_field.group(1) if label_field else ""
        labels.append(label)
        ids.append(re.search(r"(?m)^old_ptr = ([0-9A-Fa-f]+)$", block).group(1))
        check(int(field(block, "size")) == len(label), "native label size mismatch: " + label)
        count = int(field(block, "pointCount"))
        point_decl = re.search(r"(?m)^points \[(\d+)\] =", block)
        coords = re.findall(r"  x \[1\] =\n([^\n]+)\n  z \[1\] =\n([^\n]+)", block)
        check(point_decl and int(point_decl.group(1)) == count == len(coords) and count > 0,
              "path point count mismatch: " + label)
        if label.startswith("sx_"):
            for x, z in coords:
                x, z = float(x), float(z)
                check(math.isfinite(x) and math.isfinite(z) and min_x <= x <= max_x and min_z <= z <= max_z,
                      "showcase path outside the terrain extent: " + label)
    named_labels = [label for label in labels if label]
    check(len(set(named_labels)) == len(named_labels), "duplicate path label")
    check(len(set(ids)) == len(ids), "duplicate path serialization address")
    check(not set(ids).intersection(addresses), "path/object serialization address collision")

    mission = read(root, "Scripts/sxshow.lua")
    bindings = set(re.findall(r'\bpath = "([^"]+)"', mission))
    bindings.update(re.findall(r'Build\("[^"]+", "[^"]+", "([^"]+)"\)', mission))
    bindings.update(re.findall(r'Goto\(convoy, "([^"]+)"', mission))
    check(bindings == {label for label in labels if label.startswith("sx_")},
          "Lua path bindings differ from authored showcase paths")
    config = configparser.ConfigParser()
    config.read_string(read(root, "Config/sxshow.ini"))
    check(config["WORKSHOP"]["mapType"].strip('"') == "instant_action", "incorrect mission listing type")

    entries = json.loads(read(reference, "Shipping/shipping.lock.json"))["files"]
    norm = lambda name: name.replace("\\", "/").casefold()
    sources = {norm(entry["source"]) for entry in entries}
    for dependency in ("Missions/crsetup.trn", "Missions/crsetup.hg2", "Missions/crsetup.mat",
                       "Missions/crsetup.lgt", "ODF/avfigh.odf", "Scripts/RequireFix.lua"):
        check(norm(dependency) in sources, "dependency absent from existing shipping lock: " + dependency)
    runtime = {norm(entry["runtime"]): norm(entry["source"]) for entry in entries}
    additions = ["Config/sxshow.ini", "Missions/sxshow.bzn", "Scripts/sxshow.lua",
                 "Scripts/SXDirector.lua", "Scripts/SXMaterials.lua", "Scripts/SXOverlay.lua"]
    for name in additions:
        check((root / name).is_file(), "missing runtime source: " + name)
        existing = runtime.get(norm(Path(name).name))
        check(existing is None or existing == norm(name), "flattened runtime-name collision: " + name)
    check(len({norm(Path(name).name) for name in additions}) == len(additions), "new runtime names collide")
    print(f"SXShowcase assets: {checks} checks passed (text/schema/dependencies; native loading unverified)")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, AttributeError) as error:
        raise SystemExit("SXShowcase assets FAILED: " + str(error))
