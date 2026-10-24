"""Install OpenShim terrain paint packs into Config/cr_terrain_hd.json.

Each pack is a <world>-auto folder built by OpenShim's
scripts/terrain-packs/build-world-packs.sh against the staged CR maps. The
pack's material replaces that world's DDS tile binding, its runtime PNGs are
copied flat into Assets/Textures, and with --remove-dds the world's crhd tile
DDS files are deleted so the payload never ships both forms.
"""
import argparse
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "Config/cr_terrain_hd.json"
TEXTURES = ROOT / "Assets/Textures"
WORLDS = {
    "moon": "MN_DETAIL_ATLAS", "venus": "VE_DETAIL_ATLAS", "io": "IO_DETAIL_ATLAS",
    "europa": "EU_DETAIL_ATLAS", "titan": "TI_DETAIL_ATLAS", "achilles": "AC_DETAIL_ATLAS",
}
# Used outside the HD binding (Materials/mn_detail_atlas.material), so it stays.
KEEP = {"crhd_moon_regolith_detail.dds"}


def runtime_files(binding):
    """Every resource the runtime loads for a paint binding."""
    names = set(binding["tiles"].values()) | {binding["fallback"]}
    for entry in binding["paint"]["maps"]:
        names.update(entry[key] for key in ("control", "control2") if entry.get(key))
    return sorted(names)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packs", type=Path, required=True, help="Folder holding <world>-auto pack folders")
    parser.add_argument("--worlds", nargs="+", choices=WORLDS, default=list(WORLDS))
    parser.add_argument("--remove-dds", action="store_true", help="Delete the painted worlds' crhd tile DDS files")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    for world in args.worlds:
        pack = args.packs / f"{world}-auto"
        materials = json.loads((pack / f"openshim_{world}_auto.json").read_text())["materials"]
        binding = materials[WORLDS[world]]
        if set(materials) != {WORLDS[world]} or "paint" not in binding:
            raise ValueError(f"{pack} is not a single {WORLDS[world]} paint pack")
        for name in runtime_files(binding):
            shutil.copyfile(pack / name, TEXTURES / name)
        # Drop this world's previous paint PNGs that the new pack no longer uses.
        used = set(runtime_files(binding))
        for stale in TEXTURES.glob(f"openshim_{world}_auto_*.png"):
            if stale.name not in used:
                stale.unlink()
        manifest["materials"][WORLDS[world]] = binding
        removed = 0
        if args.remove_dds:
            for dds in TEXTURES.glob(f"crhd_{world}_*.dds"):
                if dds.name not in KEEP:
                    dds.unlink()
                    removed += 1
        print(f"{world}: {len(used)} runtime files, {len(binding['paint']['maps'])} maps, {removed} DDS removed")
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
