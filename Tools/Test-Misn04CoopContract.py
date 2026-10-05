from pathlib import Path
import configparser
import json
import re
import struct

root = Path(__file__).resolve().parents[1]
bzn = (root / "Missions" / "misn04.bzn").read_text(encoding="utf-8")
lua = (root / "Scripts" / "misn04.lua").read_text(encoding="utf-8")
# The source audit retains inactive C++ with original Team-2 orders. Check
# active Lua only, including equals-delimited long comments, so reconstruction
# evidence cannot be mistaken for a live co-op team-contract regression.
lua = re.sub(r"--\[(=*)\[.*?\]\1\]", "", lua, flags=re.DOTALL)
lua = re.sub(r"--[^\r\n]*", "", lua)

# Teams 1-4 are reserved for human players in the co-op contract. Mission 04
# must not ship preplaced Team-2 enemies that can collide with Player 2.
assert "name = MultSTMission\n" in bzn, "offline/online map must use MultSTMission"
assert b"\r\n" in (root / "Missions" / "misn04.bzn").read_bytes(), "native BZN needs CRLF"

assert bzn.index("name = MultSTMission") > bzn.rindex("[GameObject]"), "native footer must follow all objects"
assert bzn.index("name = MultSTMission") < bzn.index("[AiMission]")
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
    if team and team.group(1) == "5":
        enemy_blocks.append(block)
        perceived = re.search(r"perceivedTeam \[1\] =\s*\n(\d+)", block)
        assert perceived and perceived.group(1) == "5", "Team-5 object has mismatched perceivedTeam"

assert len(enemy_blocks) == 3, "expected preplaced mission enemies on Team 5"
assert sorted(spawn_teams) == [1, 2, 3, 4], "native Init requires one spawn per human team"
header_size = int(re.search(r"size \[1\] =\n(\d+)\n\[GameObject\]", bzn).group(1))
assert header_size == len(blocks), "native object count does not match serialized objects"
seq_count = int(re.search(r"seq_count \[1\] =\n(\d+)", bzn).group(1))
assert seq_count > max(int(re.search(r"seqno \[1\] =\n(\d+)", b).group(1)) for b in blocks)

assert "local ENEMY_TEAM = 5" in lua, "misn04.lua enemy-team contract changed"
assert "local LEADER_TEAM = 1" in lua, "misn04.lua leader-team contract changed"

for pattern, message in [
    (r"BuildObject\([^\n]*,\s*2\s*,", "dynamic enemy spawn still uses Team 2"),
    (r"CountUnitsNearObject\([^\n]*,\s*2\s*,\s*\"sv", "enemy count still queries Team 2"),
    (r"GetTeamNum\([^\n]*\)\s*==\s*2\b", "enemy classification still uses Team 2"),
    (r"SetScrap\(\s*2\s*,", "enemy resources still use Team 2"),
]:
    assert not re.search(pattern, lua), message

print(f"misn04 co-op team contract passed ({len(enemy_blocks)} preplaced Team-5 enemies)")


# Separate native mode INIs must resolve the one shared BZN/script by stem.
mp = configparser.ConfigParser()
mp.read(root / "Config" / "misn04.ini", encoding="utf-8")
assert mp["DESCRIPTION"]["missionName"] == '"CR: The Relic Discovered Coop"'
assert mp["WORKSHOP"]["mapType"] == '"multiplayer"'
assert dict(mp["MULTIPLAYER"]) == {
    "minplayers": '"2"', "maxplayers": '"4"', "gametype": '"S"',
}
campaign = configparser.ConfigParser()
campaign.read(root / "Config" / "crcampgn.ini", encoding="utf-8")
assert campaign["MISSION3"]["missionBZN"] == '"misn04.bzn"'
assert campaign["WORKSHOP"]["mapType"] == '"campaign"'

vehicles = [line.split(",")[0].strip() for line in
            (root / "Missions" / "misn04.vxt").read_text().splitlines() if line.strip()]
assert vehicles == ["avtank", "avfimp"], "MP selection must be tank or scout only"
for odf in vehicles:
    assert (root / "ODF" / (odf + ".odf")).is_file()

description = (root / "misn04.des").read_text().strip()
assert len(description) <= 300 and "\n" not in description
assert "team 1" in description and "teams 2-4" in description
bitmap = (root / "Assets" / "Graphics" / "misn04.bmp").read_bytes()
assert bitmap[:2] == b"BM" and struct.unpack_from("<I", bitmap, 14)[0] == 40
width, height, planes, depth, compression = struct.unpack_from("<iiHHI", bitmap, 18)
assert width > 0 and height > 0 and planes == 1 and depth == 24 and compression == 0
assert struct.unpack_from("<I", bitmap, 2)[0] == len(bitmap)

lock = json.loads((root / "Shipping" / "shipping.lock.json").read_text())
entries = {entry["source"]: entry["runtime"] for entry in lock["files"]}
assert lock["count"] == len(lock["files"])
manager = (root / "Manage-CampaignFiles.ps1").read_text(encoding="utf-8-sig")
for source in (r"Config\misn04.ini", r"Assets\Graphics\misn04.bmp",
               "misn04.des", r"Missions\misn04.vxt",
               r"Missions\misn04.bzn", r"Scripts\misn04.lua"):
    runtime = source.split("\\")[-1]
    assert entries.get(source) == runtime, f"missing shipping entry: {source}"
    assert f'"{runtime}"' in manager, f"missing staging requirement: {runtime}"
    assert len(runtime) <= 16

print("misn04 campaign/MP scaffold and shipping checks passed")
