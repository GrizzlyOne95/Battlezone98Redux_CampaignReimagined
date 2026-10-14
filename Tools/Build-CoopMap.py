"""Build Missions/<mission>.bzn (co-op) from the Battlezone 1.5 original.

Shared by misn06 through misn12 (Build-Misn06CoopMap.py is a thin wrapper); the
notes below use misn06 as the example.

The 1.5 map is a binary version-1032 BZN whose mission class is the C++
Misn06Mission. CR ships an ASCII Redux (2016) BZN that runs the shared
offline/co-op Lua under MultSTMission:

  * re-save at 2016 through the Modding Toolbox converter (no data loss
    beyond the 1.5-only collision-damage fields it reports);
  * TerrainName names the terrain stem (the converter keeps "misn06.bzn");
  * mission class MultSTMission, so the same BZN also hosts co-op;
  * CCA (authored team 2) moves to team 5, freeing teams 2-4 for guests;
  * four pspwn_1 team-start buoys for teams 1-4, 25 m apart along the
    player's left, at the authored start with zero motion (copied motion
    pushed misn05's team 3/4 starts far away).

Usage:
  python Tools/Build-CoopMap.py --mission misn06|...|misn12 [--source FILE] [--toolbox DIR]
"""

from __future__ import annotations

import argparse
from collections import Counter
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
STOCK_DIR = Path(r"C:\Program Files (x86)\Battlezone\stockfiles2")
DEFAULT_TOOLBOX = Path(os.environ.get("BZ_MODDING_TOOLBOX", REPO.parent / "Battlezone98_Modding_Toolbox"))

ENEMY_TEAM = 5
AUTHORED_ENEMY_TEAM = 2
# Authored objects dropped from a map; the mission Lua spawns replacements instead.
# misn07: the DLL parks two disguised NSDF tanks (avtank2/avtank3) on authored team 3,
# which co-op gives to a guest. misn07.lua spawns support-team (7) tanks off the
# west edge and drives them to these authored positions (CONVOY_DEST in the Lua):
#   avtank2 (1426.3, 22.9489, 99546.5)   avtank3 (1442.5, 21.613, 99570.4)
REMOVE_LABELS = {"misn07": ("avtank2", "avtank3")}
# Authored objects that move to another team: label -> (team, perceivedTeam).
# misn08: the Colorado (avrecy, authored team 3) is a map object the script kills by
# Damage; team 3 is a guest team in co-op, so it goes to the support team (7) but
# stays perceived as team 1 (the host's side).
RETEAM_LABELS = {
    "misn08": {"colorado": (7, 1)},
    # misn12: six authored nav-camera pods (apcamr5-10_camerapod) sit on authored team 3 (the
    # DLL's hidden camera team). Team 3 is a guest slot in co-op, so they move to the support team
    # (7): not a guest, not allied with the humans, so they stay hidden. The Lua reveals a pod by
    # switching it to team 1 and re-hides it on 7. perceivedTeam follows the team (7), because the
    # hidden state is exactly "a non-allied team's object", unlike the Colorado which must look
    # friendly from the start.
    "misn12": {f"apcamr{n}_camerapod": (7, 7) for n in range(5, 11)},
}
BUOY_SPACING = 25.0
BUOY_ADDR_BASE = 0x3001

BUOY_TEMPLATE = """[GameObject]
PrjID [1] =
pspwn_1
seqno [1] =
{seq}
pos [1] =
  x [1] =
{x}
  y [1] =
{y}
  z [1] =
{z}
team [1] =
{team}
label = coop_spawn{team}
isUser [1] =
0
obj_addr = {addr:08X}
transform [1] =
  right_x [1] =
{rx}
  right_y [1] =
{ry}
  right_z [1] =
{rz}
  up_x [1] =
{ux}
  up_y [1] =
{uy}
  up_z [1] =
{uz}
  front_x [1] =
{fx}
  front_y [1] =
{fy}
  front_z [1] =
{fz}
  posit_x [1] =
{x}
  posit_y [1] =
{y}
  posit_z [1] =
{z}
illumination [1] =
1
pos [1] =
  x [1] =
{x}
  y [1] =
{y}
  z [1] =
{z}
euler =
 mass [1] =
0
 mass_inv [1] =
1e+030
 v_mag [1] =
0
 v_mag_inv [1] =
1e+030
 I [1] =
1
 k_i [1] =
0
 v [1] =
  x [1] =
0
  y [1] =
0
  z [1] =
0
 omega [1] =
  x [1] =
0
  y [1] =
0
  z [1] =
0
 Accel [1] =
  x [1] =
0
  y [1] =
0
  z [1] =
0
seqNo [1] =
{seq}
name =
isCritical [1] =
false
isObjective [1] =
false
isSelected [1] =
false
isVisible [1] =
ffffffff
seen [1] =
2
healthRatio [1] =
0
curHealth [1] =
0
maxHealth [1] =
0
ammoRatio [1] =
0
curAmmo [1] =
0
maxAmmo [1] =
0
priority [1] =
0
what = 00000000
who [1] =
0
where = 00000000
param [1] =

aiProcess [1] =
false
isCargo [1] =
false
independence [1] =
1
curPilot [1] =

perceivedTeam [1] =
{team}
"""


def fmt(value: float) -> str:
    return f"{value:.6g}"


def field(block: str, name: str) -> float:
    match = re.search(rf"^\s*{name} \[1\] =\n(\S+)$", block, re.M)
    if not match:
        raise SystemExit(f"field {name} missing from player object")
    return float(match.group(1))


def convert(source: Path, toolbox: Path) -> str:
    sys.path.insert(0, str(toolbox))
    from battlezone.bzn.version_convert import convert_bzn  # noqa: E402

    result = convert_bzn(str(source), "redux")
    return result.data.decode("latin-1").replace("\r\n", "\n")


def build(text: str, mission: str) -> str:
    mission_class = mission[0].upper() + mission[1:] + "Mission"
    header, *objects_and_tail = text.split("[GameObject]\n")
    count = len(objects_and_tail)
    size_match = re.search(r"^size \[1\] =\n(\d+)$", header, re.M)
    if not size_match or int(size_match.group(1)) != count:
        raise SystemExit(f"header size does not match {count} stock objects")
    tail_split = re.split(rf"(?m)^(?=name = {mission_class}$)", objects_and_tail[-1], maxsplit=1)
    if len(tail_split) != 2:
        raise SystemExit(f"mission class {mission_class} not found")
    objects = objects_and_tail[:-1] + [tail_split[0]]
    tail = tail_split[1].replace(f"name = {mission_class}", "name = MultSTMission", 1)

    header = header.replace(f"TerrainName = {mission}.bzn\n", f"TerrainName = {mission}\n")
    if f"TerrainName = {mission}\n" not in header:
        raise SystemExit("TerrainName not rewritten")

    removed = 0
    for label in REMOVE_LABELS.get(mission, ()):
        keep = [b for b in objects if not re.search(rf"^label = {re.escape(label)}$", b, re.M)]
        if len(keep) != len(objects) - 1:
            raise SystemExit(f"object {label} not found exactly once")
        gone = next(b for b in objects if b not in keep)
        print(f"removed {label}:", tuple(field(gone, f"posit_{a}") for a in "xyz"))
        objects = keep
        removed += 1
    count = len(objects)

    for label, (new_team, new_perceived) in RETEAM_LABELS.get(mission, {}).items():
        hits = [i for i, b in enumerate(objects) if re.search(rf"^label = {re.escape(label)}$", b, re.M)]
        if len(hits) != 1:
            raise SystemExit(f"object {label} not found exactly once")
        b = objects[hits[0]]
        b, n1 = re.subn(r"^team \[1\] =\n\d+$", f"team [1] =\n{new_team}", b, count=1, flags=re.M)
        b, n2 = re.subn(r"^perceivedTeam \[1\] =\n\d+$", f"perceivedTeam [1] =\n{new_perceived}", b, count=1, flags=re.M)
        if n1 != 1 or n2 != 1:
            raise SystemExit(f"object {label} team fields not rewritten")
        objects[hits[0]] = b
        print(f"reteamed {label}: team {new_team}, perceivedTeam {new_perceived}")

    moved = 0
    for i, block in enumerate(objects):
        team = re.search(r"^team \[1\] =\n(\d+)$", block, re.M)
        if team and int(team.group(1)) == AUTHORED_ENEMY_TEAM:
            block = re.sub(r"^team \[1\] =\n2$", f"team [1] =\n{ENEMY_TEAM}", block, count=1, flags=re.M)
            block, n = re.subn(r"^perceivedTeam \[1\] =\n2$", f"perceivedTeam [1] =\n{ENEMY_TEAM}",
                               block, count=1, flags=re.M)
            if n != 1:
                raise SystemExit(f"object {i} has no perceivedTeam 2")
            objects[i] = block
            moved += 1

    player = next(b for b in objects if re.search(r"^isUser \[1\] =\n1$", b, re.M))
    px, py, pz = (field(player, f"posit_{a}") for a in "xyz")
    print("player start:", re.search(r"^label = (.*)$", player, re.M).group(1), (px, py, pz))
    right = [field(player, f"right_{a}") for a in "xyz"]
    up = [field(player, f"up_{a}") for a in "xyz"]
    front = [field(player, f"front_{a}") for a in "xyz"]

    seq_match = re.search(r"^seq_count \[1\] =\n(\d+)$", header, re.M)
    seq = int(seq_match.group(1))
    used_addrs = {int(a, 16) for a in re.findall(r"^obj_addr = ([0-9A-Fa-f]+)$", "\n".join(objects), re.M)}

    buoys = []
    for team in range(1, 5):
        # The player's left is -right; keep y at the authored start height.
        offset = BUOY_SPACING * (team - 1)
        x = px - right[0] * offset
        z = pz - right[2] * offset
        addr = BUOY_ADDR_BASE + team - 1
        if addr in used_addrs:
            raise SystemExit(f"buoy obj_addr {addr:08X} collides")
        buoys.append(BUOY_TEMPLATE.format(
            seq=seq + team - 1, team=team, addr=addr, x=fmt(x), y=fmt(py), z=fmt(z),
            rx=fmt(right[0]), ry=fmt(right[1]), rz=fmt(right[2]),
            ux=fmt(up[0]), uy=fmt(up[1]), uz=fmt(up[2]),
            fx=fmt(front[0]), fy=fmt(front[1]), fz=fmt(front[2])))

    header = re.sub(r"^seq_count \[1\] =\n\d+$", f"seq_count [1] =\n{seq + 4}", header, count=1, flags=re.M)
    header = re.sub(r"^size \[1\] =\n\d+$", f"size [1] =\n{count + 4}", header, count=1, flags=re.M)
    teams = Counter(re.findall(r"^team \[1\] =\n(\d+)$", "\n".join(objects), re.M))
    print("object counts per team (after move):", dict(sorted(teams.items())))
    for team in (2, 3, 4):
        if teams.get(str(team)):
            print(f"warning: {teams[str(team)]} authored objects remain on guest team {team}")
    print(f"removed {removed} objects; moved {moved} CCA objects to team {ENEMY_TEAM}; added 4 team-start buoys")
    body = "".join("[GameObject]\n" + b for b in objects + [s.split("[GameObject]\n", 1)[1] for s in buoys])
    return header + body + tail


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--mission", default="misn06", help="mission stem: misn06 .. misn12")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--toolbox", type=Path, default=DEFAULT_TOOLBOX)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    source = args.source or STOCK_DIR / f"{args.mission}.bzn"
    output = args.output or REPO / "Missions" / f"{args.mission}.bzn"
    text = build(convert(source, args.toolbox), args.mission)
    output.write_bytes(text.replace("\n", "\r\n").encode("latin-1"))
    print(f"wrote {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
