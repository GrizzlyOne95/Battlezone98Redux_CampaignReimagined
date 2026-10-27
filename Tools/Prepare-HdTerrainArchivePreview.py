"""Extract owned stock-map preview companions through the Toolbox ZFS reader."""
import argparse
from pathlib import Path
import re
import sys
from bzmodellibs import toolbox_root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--mission", choices=("evolve_1", "evolve_3"), required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--preview-name", help="Unique local map stem to avoid native stock-map selection")
    args = parser.parse_args()
    sys.path.insert(0, str(toolbox_root()))
    from battlezone.archives.zfs import ZFSArchive
    from battlezone.bzn.bz1 import Field, read_bzn
    stem = args.preview_name or args.mission
    if not re.fullmatch(r"[a-z0-9_]{1,11}", stem):
        raise ValueError("Preview name must fit a native mission filename")
    archive = ZFSArchive(args.game / "bzone.zfs")
    args.out.mkdir(parents=True, exist_ok=True)
    for extension in ("bzn", "trn", "hg2", "mat", "lgt"):
        name = args.mission + "." + extension
        (args.out / (stem + "." + extension)).write_bytes(archive.read(name))
    if args.preview_name:
        path = args.out / (stem + ".bzn")
        mission = read_bzn(path)
        mission.header["msn_filename"] = Field("chars", (stem + ".bzn").encode("ascii"))
        mission.header["TerrainName"] = Field("chars", stem.encode("ascii"))
        path.write_bytes(mission.write(binary=False))
        if read_bzn(path).terrain_name != stem:
            raise ValueError("Preview terrain rename did not round-trip")


if __name__ == "__main__":
    main()
