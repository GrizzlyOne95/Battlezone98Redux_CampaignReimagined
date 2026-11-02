"""Build Missions/evolvecr.bzn from the stock BZ1 1.5 "sammy" map.

Unlike misn06..misn18/misns1..misns8 (terrain stem == mission stem == C++ mission class, handled by
Build-CoopMap.py) this mission's three names disagree: the stock terrain is `sammy__1` (its own `.bzn/.lgt/.mat/.trn`,
archived in the Redux `tro_cam.zfs` alongside the Black Dog/Chinese maps, no `.hg2`), its C++ mission class is
`EvolveMission` (`BZ1/from_bz2_dll_src/evolvemission.cpp`, `Docs/EVOLVE_LUA_PORT.md`), and CR's own script/mission
stem is `evolve` (`Scripts/evolvecr.lua`, `Missions/evolvecr.bzn`). This script borrows Build-CoopMap.py's proven
primitives (the toolbox converter, the buoy template, the stock-object field reader) rather than forcing a second
mission naming scheme into the shared one.

The stock map has no authored enemy (every attacker is a runtime BuildObject in evolve.lua): there is nothing to
reteam, remove or relabel. Its sole authored human start (`asuser0_person`) is already team 1, matching the CR
decision that every co-op human shares team 1 (a shared arena/shared-lives survival mission, not one team slot per
human). The four co-op start buoys are therefore all team 1, not one per team 1-4 as Build-CoopMap.py's generic
buoy loop does; each needs a distinct label (`coop_spawn1_1`..`coop_spawn1_4`) since BUOY_TEMPLATE's default label
is keyed by team number alone and would collide across four same-team buoys.

Usage:
  python Tools/Build-EvolveCoopMap.py [--toolbox DIR] [--output FILE]
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

MISSION_CLASS = "EvolveMission"
STOCK_STEM = "sammy__1"


def _load_build_coop_map():
    spec = importlib.util.spec_from_file_location("buildcoopmap", str(Path(__file__).with_name("Build-CoopMap.py")))
    module = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("buildcoopmap", module)
    spec.loader.exec_module(module)
    return module


def read_source(toolbox: Path) -> bytes:
    sys.path.insert(0, str(toolbox))
    from battlezone.archives.zfs import ZFSArchive  # noqa: E402

    bc = _load_build_coop_map()
    return ZFSArchive(str(bc.TRO_CAM)).read(f"{STOCK_STEM}.bzn")


def build(text: str, bc) -> str:
    header, *objects_and_tail = text.split("[GameObject]\n")
    count = len(objects_and_tail)
    size_match = re.search(r"^size \[1\] =\n(\d+)$", header, re.M)
    if not size_match or int(size_match.group(1)) != count:
        raise SystemExit(f"header size does not match {count} stock objects")
    tail_split = re.split(rf"(?m)^(?=name = {MISSION_CLASS}$)", objects_and_tail[-1], maxsplit=1)
    if len(tail_split) != 2:
        raise SystemExit(f"mission class {MISSION_CLASS} not found")
    objects = objects_and_tail[:-1] + [tail_split[0]]
    tail = tail_split[1].replace(f"name = {MISSION_CLASS}", "name = MultSTMission", 1)

    header = header.replace(f"TerrainName = {STOCK_STEM}.bzn\n", f"TerrainName = {STOCK_STEM}\n")
    if f"TerrainName = {STOCK_STEM}\n" not in header:
        raise SystemExit("TerrainName not rewritten")
    header = header.replace(f"msn_filename = {STOCK_STEM}.bzn\n", "msn_filename = evolvecr.bzn\n")
    if "msn_filename = evolvecr.bzn\n" not in header:
        raise SystemExit("msn_filename not rewritten")

    player = next(b for b in objects if re.search(r"^isUser \[1\] =\n1$", b, re.M))
    px, py, pz = (bc.field(player, f"posit_{a}") for a in "xyz")
    print("player start:", re.search(r"^label = (.*)$", player, re.M).group(1), (px, py, pz))
    right = [bc.field(player, f"right_{a}") for a in "xyz"]
    up = [bc.field(player, f"up_{a}") for a in "xyz"]
    front = [bc.field(player, f"front_{a}") for a in "xyz"]

    seq = int(re.search(r"^seq_count \[1\] =\n(\d+)$", header, re.M).group(1))
    used_addrs = {int(a, 16) for a in re.findall(r"^obj_addr = ([0-9A-Fa-f]+)$", "\n".join(objects), re.M)}

    buoys = []
    for slot in range(4):
        offset = bc.BUOY_SPACING * slot
        x = px - right[0] * offset
        z = pz - right[2] * offset
        addr = bc.BUOY_ADDR_BASE + slot
        if addr in used_addrs:
            raise SystemExit(f"buoy obj_addr {addr:08X} collides")
        block = bc.BUOY_TEMPLATE.format(
            seq=seq + slot, team=1, addr=addr, x=bc.fmt(x), y=bc.fmt(py), z=bc.fmt(z),
            rx=bc.fmt(right[0]), ry=bc.fmt(right[1]), rz=bc.fmt(right[2]),
            ux=bc.fmt(up[0]), uy=bc.fmt(up[1]), uz=bc.fmt(up[2]),
            fx=bc.fmt(front[0]), fy=bc.fmt(front[1]), fz=bc.fmt(front[2]))
        # Every human shares team 1 (shared arena, shared score/lives); the template's default
        # label is keyed by team number alone, which would collide across four same-team buoys.
        block, n = re.subn(r"^label = coop_spawn1$", f"label = coop_spawn1_{slot + 1}", block, count=1, flags=re.M)
        if n != 1:
            raise SystemExit("buoy label not rewritten")
        buoys.append(block)

    header = re.sub(r"^seq_count \[1\] =\n\d+$", f"seq_count [1] =\n{seq + 4}", header, count=1, flags=re.M)
    header = re.sub(r"^size \[1\] =\n\d+$", f"size [1] =\n{count + 4}", header, count=1, flags=re.M)
    print(f"added 4 team-1 co-op start buoys ({count} stock objects -> {count + 4})")
    body = "".join("[GameObject]\n" + b for b in objects + [s.split("[GameObject]\n", 1)[1] for s in buoys])
    return header + body + tail


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--toolbox", type=Path)
    parser.add_argument("--output", type=Path, default=REPO / "Missions" / "evolvecr.bzn")
    args = parser.parse_args()
    bc = _load_build_coop_map()
    toolbox = args.toolbox or bc.DEFAULT_TOOLBOX
    text = build(bc.convert(read_source(toolbox), toolbox), bc)
    args.output.write_bytes(text.replace("\n", "\r\n").encode("latin-1"))
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
