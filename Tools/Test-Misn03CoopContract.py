from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
bzn = (root / "Missions" / "misn03.bzn").read_text(encoding="utf-8")
lua = (root / "Scripts" / "misn03.lua").read_text(encoding="utf-8")

# Teams 1-4 are reserved for human players in the co-op contract. Mission 03
# must not ship preplaced Team-2 enemies that can collide with Player 2.
assert "team [1] =\n2" not in bzn, "misn03.bzn still contains Team-2 mission state"
assert "perceivedTeam [1] =\n2" not in bzn, "misn03.bzn still contains perceived Team-2 enemies"

blocks = bzn.split("[GameObject]")[1:]
enemy_blocks = []
for block in blocks:
    team = re.search(r"team \[1\] =\s*\n(\d+)", block)
    if team and team.group(1) == "5":
        enemy_blocks.append(block)
        perceived = re.search(r"perceivedTeam \[1\] =\s*\n(\d+)", block)
        assert perceived and perceived.group(1) == "5", "Team-5 object has mismatched perceivedTeam"

assert len(enemy_blocks) >= 7, "expected preplaced mission enemies on Team 5"

assert "local ENEMY_TEAM = 5" in lua, "misn03.lua enemy-team contract changed"
assert "local LEADER_TEAM = 1" in lua, "misn03.lua leader-team contract changed"

for pattern, message in [
    (r"BuildObject\([^\n]*,\s*2\s*,", "dynamic enemy spawn still uses Team 2"),
    (r"CountUnitsNearObject\([^\n]*,\s*2\s*,\s*\"sv", "enemy count still queries Team 2"),
    (r"GetTeamNum\([^\n]*\)\s*==\s*2\b", "enemy classification still uses Team 2"),
    (r"SetScrap\(\s*2\s*,", "enemy resources still use Team 2"),
]:
    assert not re.search(pattern, lua), message

print(f"misn03 co-op team contract passed ({len(enemy_blocks)} preplaced Team-5 enemies)")


# Early presentation phases must remain explicit leader-published transitions.
assert "local PHASE_DEFENSE = 1" in lua, "misn03 defense phase contract changed"
assert "local PHASE_FORTIFY = 2" in lua, "misn03 fortify phase contract changed"
assert "CRCoop.SetMissionPhase(PHASE_DEFENSE)" in lua, "initial defense phase is not published"
assert "CRCoop.SetMissionPhase(PHASE_FORTIFY)" in lua, "fortify phase is not published"
assert "local function PresentMissionPhase()" in lua, "client phase presentation handler missing"
