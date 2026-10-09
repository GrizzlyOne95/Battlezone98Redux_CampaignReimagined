from pathlib import Path
import configparser
import json
import re
import struct

root = Path(__file__).resolve().parents[1]
bzn = (root / "Missions" / "misn02b.bzn").read_text(encoding="utf-8")
lua = (root / "Scripts" / "misn02b.lua").read_text(encoding="utf-8")
# The source audit retains inactive C++ with original Team-2 orders. Check
# active Lua only, including equals-delimited long comments, so reconstruction
# evidence cannot be mistaken for a live co-op team-contract regression.
lua = re.sub(r"--\[(=*)\[.*?\]\1\]", "", lua, flags=re.DOTALL)
lua = re.sub(r"--[^\r\n]*", "", lua)

# Teams 1-4 are reserved for human players in the co-op contract. Mission 02B
# must not ship preplaced Team-2 enemies that can collide with Player 2.
assert "name = MultSTMission\n" in bzn, "offline/online map must use MultSTMission"
assert b"\r\n" in (root / "Missions" / "misn02b.bzn").read_bytes(), "native BZN needs CRLF"

blocks = bzn.split("[GameObject]")[1:]
enemy_blocks = []
spawn_teams = []
for block in blocks:
    team = re.search(r"team \[1\] =\s*\n(\d+)", block)
    odf = re.search(r"PrjID \[1\] =\s*\n([^\n]+)", block).group(1)
    if odf == "pspwn_1":
        spawn_teams.append(int(team.group(1)))
    elif team:
        assert team.group(1) not in ("2", "3", "4"), "mission object occupies a guest team"
    if team and team.group(1) == "6":
        enemy_blocks.append(block)
        perceived = re.search(r"perceivedTeam \[1\] =\s*\n(\d+)", block)
        assert perceived and perceived.group(1) == "6", "Team-6 object has mismatched perceivedTeam"

# Enemies begin as neutral staged fighters and become team 6 in Lua.
# Preplaced defensive turrets and the authored dummy belong to friendly team 7.
friendly = [block for block in blocks if re.search(r"team \[1\] =\s*\n7\b", block)]
assert len(friendly) == 8
for block in friendly:
    assert re.search(r"perceivedTeam \[1\] =\s*\n7\b", block)
assert sorted(spawn_teams) == [1, 2, 3, 4], "native Init requires one spawn per human team"
header_size = int(re.search(r"size \[1\] =\n(\d+)\n\[GameObject\]", bzn).group(1))
assert header_size == len(blocks), "native object count does not match serialized objects"
seq_count = int(re.search(r"seq_count \[1\] =\n(\d+)", bzn).group(1))
assert seq_count > max(int(re.search(r"seqno \[1\] =\n(\d+)", b).group(1)) for b in blocks)

assert "local ENEMY_TEAM = 6" in lua, "misn02b.lua enemy-team contract changed"
assert "local LEADER_TEAM = 1" in lua, "misn02b.lua leader-team contract changed"

for pattern, message in [
    (r"BuildObject\([^\n]*,\s*2\s*,", "dynamic enemy spawn still uses Team 2"),
    (r"CountUnitsNearObject\([^\n]*,\s*2\s*,\s*\"sv", "enemy count still queries Team 2"),
    (r"GetTeamNum\([^\n]*\)\s*==\s*2\b", "enemy classification still uses Team 2"),
    (r"SetScrap\(\s*2\s*,", "enemy resources still use Team 2"),
]:
    assert not re.search(pattern, lua), message

print(f"misn02b co-op team contract passed ({len(enemy_blocks)} preplaced Team-6 enemies)")


assert "local FRIENDLY_TEAM = 7" in lua
assert "exu.DisableStartingRecycler()" in lua
assert "IsLocal(h) and not CRCoop.IsHumanCraft(h)" in lua
assert 'SetAIP("misn02.aip", ENEMY_TEAM)' in lua

# Separate native mode INIs must resolve the one shared BZN/script by stem.
mp = configparser.ConfigParser()
mp.read(root / "Config" / "misn02b.ini", encoding="utf-8")
assert mp["DESCRIPTION"]["missionName"] == '"CR: Red Arrival Coop"'
assert mp["WORKSHOP"]["mapType"] == '"multiplayer"'
assert dict(mp["MULTIPLAYER"]) == {
    "minplayers": '"2"', "maxplayers": '"4"', "gametype": '"S"',
}
campaign = configparser.ConfigParser()
campaign.read(root / "Config" / "crcampgn.ini", encoding="utf-8")
assert campaign["MISSION1"]["missionBZN"] == '"misn02b.bzn"'
assert campaign["WORKSHOP"]["mapType"] == '"campaign"'

# Matches the offline start: everyone begins on foot beside the empty craft.
# Stock vxt form "odf des<TAB>movie name"; the short "asuser ," form leaves
# staging at "Vehicle not selected".
vxt = [line for line in (root / "Missions" / "misn02b.vxt").read_text().splitlines() if line.strip()]
assert len(vxt) == 1 and vxt[0].split()[0] == "asuser", "MP start must be the pilot only"
assert vxt[0].split()[1] == "aspilo.des" and "\t" in vxt[0], "pilot line must use the stock vxt form"

description = (root / "misn02b.des").read_text().strip()
assert len(description) <= 300 and "\n" not in description
assert "team 1" in description and "teams 2-4" in description
bitmap = (root / "Assets" / "Graphics" / "misn02b.bmp").read_bytes()
assert bitmap[:2] == b"BM" and struct.unpack_from("<I", bitmap, 14)[0] == 40
width, height, planes, depth, compression = struct.unpack_from("<iiHHI", bitmap, 18)
assert width > 0 and height > 0 and planes == 1 and depth == 24 and compression == 0
assert struct.unpack_from("<I", bitmap, 2)[0] == len(bitmap)

lock = json.loads((root / "Shipping" / "shipping.lock.json").read_text())
entries = {entry["source"]: entry["runtime"] for entry in lock["files"]}
assert lock["count"] == len(lock["files"])
manager = (root / "Manage-CampaignFiles.ps1").read_text(encoding="utf-8-sig")
for source in (r"Config\misn02b.ini", r"Assets\Graphics\misn02b.bmp",
               "misn02b.des", r"Missions\misn02b.vxt",
               r"Missions\misn02b.bzn", r"Scripts\misn02b.lua"):
    runtime = source.split("\\")[-1]
    assert entries.get(source) == runtime, f"missing shipping entry: {source}"
    assert f'"{runtime}"' in manager, f"missing staging requirement: {runtime}"
    assert len(runtime) <= 16

print("misn02b campaign/MP scaffold and shipping checks passed")
