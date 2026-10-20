"""Make an isolated player-only camera fixture; retain the map's terrain files."""
import argparse
from pathlib import Path
import sys

from bzmodellibs import toolbox_root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--base-type", type=int, help="Place the temporary camera vehicle on an existing solid base tile")
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
    if args.base_type is not None:
        import numpy as np
        from scipy.ndimage import distance_transform_edt
        from battlezone.terrain.hg2 import read_hg2
        from battlezone.terrain.mat import read_mat, write_mat, encode_entry
        from battlezone.terrain.trn import TRNDocument
        document = TRNDocument.read(args.source.with_suffix(".trn"))
        header, heights = read_hg2(args.source.with_suffix(".hg2"))
        cells = read_mat(args.source.with_suffix(".mat"), header.zones_x, header.zones_z)
        solids = ((cells >> 12) == args.base_type) & (((cells >> 8) & 15) == args.base_type)
        if not np.any(solids):
            if args.source.parent.resolve() == args.out.parent.resolve():
                raise ValueError("A base swatch must be written into a separate preview directory")
            start = player[0].fields["pos"].value[0]
            x = int(np.clip((start[0]-document.size.min_x)/20, 3, cells.shape[1]-4))
            z = int(np.clip((start[2]-document.size.min_z)/20, 3, cells.shape[0]-4))
            cells[z-2:z+3, x-2:x+3] = encode_entry(args.base_type, args.base_type)
            write_mat(args.out.with_suffix(".mat"), cells, header.zones_x, header.zones_z)
            solids = ((cells >> 12) == args.base_type) & (((cells >> 8) & 15) == args.base_type)
            print("Preview-only base swatch painted; source mission terrain is unchanged")
        z, x = np.unravel_index(np.argmax(distance_transform_edt(solids)), solids.shape)
        # Toolbox formats: 20m material cells, four 5m HG2 samples per cell,
        # heights in decimetres. This alters only the temporary camera object.
        position = [document.size.min_x + x*20+10, float(heights[z*4+2, x*4+2])/10+2,
                    document.size.min_z + z*20+10]
        player[0].fields["pos"] = Field("vec3", [tuple(position)])
        transform = list(player[0].fields["transform"].value)
        transform[9:12] = position
        player[0].fields["transform"] = Field("mat", tuple(transform))
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
