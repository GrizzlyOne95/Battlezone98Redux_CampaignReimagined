"""Promote the accepted nine-world bundles byte-for-byte into CR source.

This imports reviewed artifacts, not new art. It never deploys or publishes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

from bzmodellibs import toolbox_root
from terrain_art_tuning import validate_runtime

sys.path.insert(0, str(toolbox_root()))
from battlezone.terrain.hd_tiles import check_bundle, inspect_dds

ROOT = Path(__file__).resolve().parent.parent
WORLDS = ("moon", "mars", "venus", "io", "europa", "titan", "ganymede", "achilles", "elysium")


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate-root", type=Path, required=True)
    args = parser.parse_args()
    config_path = ROOT / "Config/cr_terrain_hd.json"
    config = read(config_path)
    plans = []
    # Validate every input before changing any canonical file.
    for world in WORLDS:
        bundle = args.candidate_root / f"{world.title()}Hd1024"
        report = check_bundle(bundle)
        recipe = read(bundle / "authoring.json")
        material = recipe["material"]
        incoming = read(bundle / "terrain_hd_tiles.json")["materials"][material]
        previous = config["materials"][material]
        for key in ("diffuseResource", "sliceCount", "tileRects"):
            if incoming[key] != previous[key]:
                raise ValueError(f"Changed native identity/layout: {world} {key}")
        for key in ("normal", "specular", "emissive"):
            if incoming[key]["sourceResource"] != previous[key]["sourceResource"]:
                raise ValueError(f"Changed native source guard: {world} {key}")
        files = dict(report["sha256"])
        if world == "moon":
            height = bundle / incoming["heightTexture"]
            if height.name != "crhd_moon_regolith_h.dds" or incoming["heightEncoding"] != "signed-unit-r32":
                raise ValueError("Unexpected Moon height contract")
            detail = bundle / "resources/crhd_moon_regolith_detail.dds"
            info = inspect_dds(detail)
            if (info["width"], info["height"], info["format"], info["mips"]) != (2048, 2048, "DXT1", 12):
                raise ValueError("Unexpected accepted Moon detail")
            files.update({height.name: sha(height), detail.name: sha(detail)})
            incoming["heightTexture"] = height.name
        for name, digest in files.items():
            if Path(name).name != name or sha(bundle / "resources" / name) != digest:
                raise ValueError(f"Invalid resource/hash: {name}")
        incoming.update(validate_runtime(previous))
        if "surfaceBlend" in previous:
            incoming["surfaceBlend"] = previous["surfaceBlend"]
        plans.append((world, bundle, recipe, incoming, report, files))

    promotion = {"schema": "cr-world-art-promotion-v1", "accepted": "2026-10-21",
                 "pullRequests": [273, 274, 275, 276, 277], "worlds": {}}
    for world, bundle, recipe, binding, report, files in plans:
        folder = ROOT / "Tools/TerrainHD" / world.title()
        for name in files:
            shutil.copyfile(bundle / "resources" / name, ROOT / "Assets/Textures" / name)
        for alias, channels in recipe["tiles"].items():
            for channel in channels:
                name = f"{recipe['prefix']}_{Path(alias).stem.lower()}_{channel.lower()}.dds"
                channels[channel] = f"../../../Assets/Textures/{name}"
        write(folder / "authoring.json", recipe)
        shutil.copyfile(bundle / "layout.csv", folder / "layout.csv")
        validation = read(folder / "pack_validation.json")
        baseline = validation.get("baselineEvidence", {k: v for k, v in validation.items()
            if k not in ("schema", "world", "bundle", "acceptedArt")})
        write(folder / "pack_validation.json", {
            "schema": "cr-hd-pack-validation-v1", "world": world,
            "acceptedArt": "2026-10-21; see Docs/WORLD_ART_PROMOTION.md",
            "bundle": report,
            "baselineEvidenceNote": "Historical pre-promotion source audits, not replacement-art measurements",
            "baselineEvidence": baseline})
        provenance = read(folder / "provenance.json")
        if world == "moon":
            provenance["acceptedArt"] = {"recipe": "Tools/TerrainHD/Moon/polyhaven.json",
                "craters": "Tools/TerrainHD/Moon/regolith.json", "license": "CC0-1.0"}
        else:
            source = read(args.candidate_root / f"{world.title()}Sources/source_tiles.json")
            provenance["worldSurfaceArt"] = source["worldSurfaceArt"]
        write(folder / "provenance.json", provenance)
        config["materials"][recipe["material"]] = binding
        promotion["worlds"][world] = {"material": recipe["material"], "sha256": files}
    write(config_path, config)
    material = ROOT / "Materials/mn_detail_atlas.material"
    text = material.read_text()
    text = text.replace("set_texture_alias DetailMap mn_detail.dds",
                        "set_texture_alias DetailMap crhd_moon_regolith_detail.dds")
    material.write_text(text)
    write(ROOT / "Tools/TerrainHD/accepted_world_art.json", promotion)
    print(f"Promoted {len(plans)} worlds / {sum(len(p[-1]) for p in plans)} DDS resources; no deployment performed")


if __name__ == "__main__":
    main()
