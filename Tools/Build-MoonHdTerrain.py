"""Build CR's Moon tiles with the shared Toolbox, then optionally install source assets.

The saved local recipe supplies independent PNGs only. The Toolbox owns DDS,
mipmaps, runtime mapping, validation and portable authoring bundle generation.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-build", type=Path, required=True, help="Trusted saved HD source recipe/cache")
    parser.add_argument("--toolbox", type=Path, default=os.environ.get("BZ_TOOLBOX_DIR"),
                        help="Toolbox checkout containing terrain hd-tiles (PR #36)")
    parser.add_argument("--output", type=Path, default=ROOT / "Local/TerrainHD/MoonBundle1024")
    parser.add_argument("--sources", type=Path, default=ROOT / "Local/TerrainHD/MoonHeightMatched1024")
    parser.add_argument("--install-source-assets", action="store_true", help="Copy reviewed runtime output into CR source; never deploys game files")
    args = parser.parse_args()
    toolbox = args.toolbox or ROOT.parent / "Battlezone98_Modding_Toolbox"
    if not (toolbox / "battlezone/terrain/hd_tiles.py").is_file():
        parser.error("Select Toolbox with HD bundle tooling via --toolbox or BZ_TOOLBOX_DIR")
    environment = dict(os.environ, PYTHONPATH=str(toolbox.resolve()), PYTHONUTF8="1")
    sources, output = args.sources.resolve(), args.output.resolve()
    if not sources.exists():
        subprocess.run([sys.executable, str(ROOT / "Tools/Build-MarsHdTileSources.py"),
                        "--world", "moon", "--images-only", "--height-matched-normals",
                        "--source-build", str(args.source_build.resolve()), "--output", str(sources),
                        "--tile-size", "1024"], env=environment, check=True)
    metadata = json.loads((sources / "source_tiles.json").read_text())
    if (metadata.get("world") != "moon" or metadata.get("normalPolarity") != "source-height-matched"
            or metadata.get("tileSize") != 1024 or metadata.get("atlasPixelsRead") is not False):
        raise ValueError("Expected 1024px independent Moon images with source-height-matched normals")
    recipe = sources / "authoring.json"
    if not recipe.exists():
        subprocess.run([sys.executable, "-m", "bztoolbox", "terrain", "hd-tiles", "init", str(sources),
                        "--layout", str(sources / "native_layout.csv"), "--material", "MN_DETAIL_ATLAS",
                        "--diffuse-resource", "moon_atlas_d.dds", "--normal-resource", "moon_atlas_n.dds",
                        "--specular-resource", "moon_atlas_s.dds", "--default-alias", metadata["defaultAlias"],
                        "--prefix", "crhd_moon", "--tile-size", "1024", "--normal-space", "directx",
                        "--out", str(recipe)], env=environment, check=True)
    if not output.exists():
        subprocess.run([sys.executable, "-m", "bztoolbox", "terrain", "hd-tiles", "build", str(recipe),
                        "--out", str(output)], env=environment, check=True)
    subprocess.run([sys.executable, "-m", "bztoolbox", "terrain", "hd-tiles", "check", str(output)],
                   env=environment, check=True)
    if args.install_source_assets:
        for path in (output / "resources").glob("*.dds"):
            shutil.copyfile(path, ROOT / "Assets/Textures" / path.name)
        shutil.copyfile(output / "terrain_hd_tiles.json", ROOT / "Config/cr_terrain_hd.json")
        shutil.copyfile(output / "layout.csv", ROOT / "Config/mn_detail_atlas.csv")
        # Canonical runtime DDS double as lossless/reusable bundle input. Keep
        # larger PNG masters in the ignored portable bundle instead of shipping.
        authoring = json.loads((output / "authoring.json").read_text())
        for alias, channels in authoring["tiles"].items():
            for channel in channels:
                name = f"crhd_moon_{Path(alias).stem.lower()}_{channel.lower()}.dds"
                channels[channel] = f"../../../Assets/Textures/{name}"
        folder = ROOT / "Tools/TerrainHD/Moon"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "authoring.json").write_text(json.dumps(authoring, indent=2) + "\n")
        shutil.copyfile(output / "layout.csv", folder / "layout.csv")
        provenance = {key: metadata[key] for key in ("schema", "world", "tileSize", "normalPolarity",
                      "sourceRecipeSha256", "normalEngineConversion", "normalCorrections", "normalRotation", "atlasPixelsRead")}
        provenance["sources"] = [{"id": item["id"], "name": item["name"], "library": item["library"],
                                  "inputHashes": {key: value["sha256"] for key, value in item["input_sources"].items()}}
                                 for item in metadata["sources"]]
        (folder / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"Moon authoring bundle: {output}")


if __name__ == "__main__":
    main()
