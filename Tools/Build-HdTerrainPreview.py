"""Make an isolated player-only camera fixture; retain the map's terrain files."""
import argparse
from pathlib import Path
import sys

from bzmodellibs import toolbox_root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(toolbox_root()))
    from battlezone.bzn.bz1 import Field, read_bzn
    mission = read_bzn(args.source, odf_dirs=[Path(__file__).resolve().parent.parent / "ODF"])
    player = [obj for obj in mission.objects if obj.prjid == "player"]
    if len(player) != 1:
        raise ValueError("Preview requires exactly one authored player")
    mission.objects = player
    mission.paths, mission.aois = [], []
    mission.mission["name"] = Field("chars", b"LuaMission")
    mission.mission["sObject"] = Field("ptr", player[0].fields["obj_addr"].value)
    payload = mission.write(binary=False)
    # Validate the serialized fixture before touching its caller-owned target.
    reloaded = read_bzn(payload)
    if (len(reloaded.objects) != 1 or reloaded.terrain_name != mission.terrain_name
            or reloaded.mission_name != "LuaMission"
            or reloaded.mission["sObject"].value != reloaded.objects[0].fields["obj_addr"].value):
        raise ValueError("Preview fixture changed its terrain identity")
    args.out.write_bytes(payload)


if __name__ == "__main__":
    main()
