"""Build CR's independent terrain tiles with the shared Modding Toolbox.

The saved local recipe supplies independent PNGs only. The Toolbox owns DDS,
mipmaps, runtime mapping, validation and portable authoring bundle generation.
"""
from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
from terrain_hd_base_emissives import SOURCE_HEIGHT_CORRECTIONS

ROOT = Path(__file__).resolve().parent.parent
WORLDS = {"moon": "mn", "mars": "ma", "venus": "ve", "io": "io", "europa": "eu",
          "titan": "ti", "achilles": "ac", "ganymede": "ga", "elysium": "el"}


def world_material(world):
    stem = WORLDS[world]
    text = (ROOT / f"Materials/{stem}_detail_atlas.material").read_text()
    material = re.search(r"(?m)^material\s+(\w+)\s*:", text).group(1)
    resources = dict(re.findall(r"set_texture_alias\s+(DiffuseMap|NormalMap|SpecularMap|EmissiveMap)\s+(\S+)", text))
    return material, stem, resources


def merge_manifest(path, incoming):
    """Update one pack without discarding other authored worlds."""
    current = json.loads(path.read_text()) if path.exists() else {"schema": incoming["schema"], "materials": {}}
    if current.get("schema") != incoming["schema"]:
        raise ValueError("Existing terrain manifest uses another schema")
    current["materials"].update(incoming["materials"])
    path.write_text(json.dumps(current, indent=2) + "\n")


def main(world=None):
    parser = argparse.ArgumentParser(description=__doc__)
    if world is None:
        parser.add_argument("--world", choices=WORLDS, required=True)
    parser.add_argument("--source-build", type=Path, required=True, help="Trusted saved HD source recipe/cache")
    parser.add_argument("--toolbox", type=Path, default=os.environ.get("BZ_TOOLBOX_DIR"),
                        help="Toolbox checkout containing terrain hd-tiles (PR #36)")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--sources", type=Path)
    parser.add_argument("--install-source-assets", action="store_true", help="Copy reviewed runtime output into CR source; never deploys game files")
    args = parser.parse_args()
    world = world or args.world
    material, stem, resources = world_material(world)
    title = world.title()
    toolbox = args.toolbox or ROOT.parent / "Battlezone98_Modding_Toolbox"
    if not (toolbox / "battlezone/terrain/hd_tiles.py").is_file():
        parser.error("Select Toolbox with HD bundle tooling via --toolbox or BZ_TOOLBOX_DIR")
    environment = dict(os.environ, PYTHONPATH=str(toolbox.resolve()), PYTHONUTF8="1")
    sources = (args.sources or ROOT / f"Local/TerrainHD/{title}HdSources1024").resolve()
    output = (args.output or ROOT / f"Local/TerrainHD/{title}Hd1024").resolve()
    if not sources.exists():
        subprocess.run([sys.executable, str(ROOT / "Tools/Build-MarsHdTileSources.py"),
                        "--world", world, "--images-only", "--height-matched-normals", "--base-emissives",
                        "--source-build", str(args.source_build.resolve()), "--output", str(sources),
                        "--tile-size", "1024"], env=environment, check=True)
    metadata = json.loads((sources / "source_tiles.json").read_text())
    if (metadata.get("world") != world or metadata.get("normalPolarity") != "source-height-matched"
            or metadata.get("tileSize") != 1024 or metadata.get("atlasPixelsRead") is not False
            or not metadata.get("baseEmissives")):
        raise ValueError(f"Expected 1024px independent {title} images with source-height-matched normals")
    settings = json.loads((ROOT / "Tools/TerrainHD/base_emissives.json").read_text())
    authored = metadata["baseEmissives"]
    if (authored["settings"] != settings["worlds"][world] or authored["maximum"] != settings["maximum"]
            or authored["sourceGain"] != settings["sourceGain"]
            or metadata.get("sourceHeightCorrections", {}) != SOURCE_HEIGHT_CORRECTIONS.get(world, {})):
        raise ValueError("Existing source images use an older normal/emissive recipe; select new --sources and --output folders")
    recipe = sources / "authoring.json"
    if not recipe.exists():
        command = [sys.executable, "-m", "bztoolbox", "terrain", "hd-tiles", "init", str(sources),
                   "--layout", str(sources / "native_layout.csv"), "--material", material,
                   "--diffuse-resource", resources["DiffuseMap"], "--normal-resource", resources["NormalMap"],
                   "--specular-resource", resources["SpecularMap"], "--default-alias", metadata["defaultAlias"],
                   "--prefix", f"crhd_{world}", "--tile-size", "1024", "--normal-space", "directx",
                   "--emissive-resource", resources["EmissiveMap"], "--out", str(recipe)]
        subprocess.run(command, env=environment, check=True)
    if not output.exists():
        subprocess.run([sys.executable, "-m", "bztoolbox", "terrain", "hd-tiles", "build", str(recipe),
                        "--out", str(output)], env=environment, check=True)
    else:
        current = json.loads(recipe.read_text())
        bundled = json.loads((output / "authoring.json").read_text())
        for alias, channels in current["tiles"].items():
            for channel, path in channels.items():
                original = (recipe.parent / path).resolve()
                retained = (output / bundled["tiles"][alias][channel]).resolve()
                if original.read_bytes() != retained.read_bytes():
                    raise ValueError("Source art changed after this bundle was built; select a new --output folder")
    subprocess.run([sys.executable, "-m", "bztoolbox", "terrain", "hd-tiles", "check", str(output)],
                   env=environment, check=True)
    if args.install_source_assets:
        for path in (output / "resources").glob("*.dds"):
            shutil.copyfile(path, ROOT / "Assets/Textures" / path.name)
        merge_manifest(ROOT / "Config/cr_terrain_hd.json", json.loads((output / "terrain_hd_tiles.json").read_text()))
        shutil.copyfile(output / "layout.csv", ROOT / f"Config/{stem}_detail_atlas.csv")
        # Canonical runtime DDS double as lossless/reusable bundle input. Keep
        # larger PNG masters in the ignored portable bundle instead of shipping.
        authoring = json.loads((output / "authoring.json").read_text())
        for alias, channels in authoring["tiles"].items():
            for channel in channels:
                name = f"crhd_{world}_{Path(alias).stem.lower()}_{channel.lower()}.dds"
                channels[channel] = f"../../../Assets/Textures/{name}"
        folder = ROOT / f"Tools/TerrainHD/{title}"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "authoring.json").write_text(json.dumps(authoring, indent=2) + "\n")
        shutil.copyfile(output / "layout.csv", folder / "layout.csv")
        provenance = {key: metadata[key] for key in ("schema", "world", "tileSize", "normalPolarity",
                      "sourceRecipeSha256", "normalEngineConversion", "normalCorrections", "normalRotation", "atlasPixelsRead", "baseEmissives")}
        provenance["sourceHeightCorrections"] = metadata.get("sourceHeightCorrections", {})
        provenance["sources"] = [{"id": item["id"], "name": item["name"], "library": item["library"],
                                  "inputHashes": {key: value["sha256"] for key, value in item["input_sources"].items()}}
                                 for item in metadata["sources"]]
        (folder / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"{title} authoring bundle: {output}")


if __name__ == "__main__":
    main()
