"""Extract owned stock-map preview companions through the Toolbox ZFS reader."""
import argparse
from pathlib import Path
import sys
from bzmodellibs import toolbox_root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--mission", choices=("evolve_1", "evolve_3"), required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(toolbox_root()))
    from battlezone.archives.zfs import ZFSArchive
    archive = ZFSArchive(args.game / "bzone.zfs")
    args.out.mkdir(parents=True, exist_ok=True)
    for extension in ("bzn", "trn", "hg2", "mat", "lgt"):
        name = args.mission + "." + extension
        (args.out / name).write_bytes(archive.read(name))


if __name__ == "__main__":
    main()
