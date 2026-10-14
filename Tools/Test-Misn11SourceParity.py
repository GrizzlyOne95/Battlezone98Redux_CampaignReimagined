#!/usr/bin/env python3
"""Verify misn11 source provenance, state, asset names and every co-op substitution.

The co-op layer and the restored/added content (Io weather, CCA scaling, the ambush, the reworked
betrayal, the respawn rally) live between exact marker lines. They are stripped (inclusive) so the
checks below prove the active DLL port is unchanged; each substitution outside the markers is
asserted explicitly at the end.
"""
import hashlib
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = 0


def check(value, message):
    global checks
    assert value, message
    checks += 1


for name, expected in {
    "Misn11Mission.cpp": "127e2f66fe3de1c79434a4c1a7b284601909ee7c",
    "Misn11Mission.h": "273252ed1e663e3c6fb9eaaf007ffef44a3a07c6",
}.items():
    raw = (ROOT / "References/Misn11Source" / name).read_bytes()
    blob = b"blob " + str(len(raw)).encode() + b"\0" + raw
    check(hashlib.sha1(blob).hexdigest() == expected, f"verbatim source changed: {name}")

source = (ROOT / "References/Misn11Source/Misn11Mission.cpp").read_text(encoding="utf-8", errors="replace")
lua_full = (ROOT / "Scripts/misn11.lua").read_text().replace("\r\n", "\n")

REGIONS = ("CR co-op layer", "CR Io weather", "CR CCA scaling", "CR ambush", "CR betrayal", "CR rally")
opens = {f"-- {name} >>": name for name in REGIONS}
closes = {f"-- {name} <<": name for name in REGIONS}
lua_lines = lua_full.split("\n")
for name in REGIONS:
    check(lua_lines.count(f"-- {name} >>") == lua_lines.count(f"-- {name} <<") > 0, "unbalanced markers: " + name)
region_text = {name: [] for name in REGIONS}
stack, stripped_lines = [], []
for line in lua_lines:
    if line in opens:
        stack.append(opens[line])
        region_text[stack[-1]].append([])
    elif line in closes:
        assert stack and stack[-1] == closes[line], "region close without matching open"
        stack.pop()
    elif stack:
        for name in stack:
            region_text[name][-1].append(line)
    else:
        stripped_lines.append(line)
assert not stack, "unterminated region"
lua = "\n".join(stripped_lines)
region_all = "\n".join(l for lines in region_text.values() for region in lines for l in region)
for token in ("ExtraHumans", "BuildExtras", "UpdateAmbush", "UpdateBackup", "CallBackup", "PICKET_", "ART_RANGE_M",
              "BACKUP_", "CHASE_M", "UpdateIoBeats", "UpdateIoWeather", "CRIoWeather", "IoSites", "UpdateRally",
              "rallyDropped", "ioStarted"):
    check(token not in lua, "region code outside marker regions: " + token)
gameplay = source[source.index("void Misn11Mission::Setup(void)"):]

# ---- state: every native member is a NewState key, exactly once -----------------------------------
state_names = []
for kind, first, last in [("bool", "won", "b_last"), ("float", "escape_time", "f_last"),
                          ("Handle", "player", "h_last"), ("int", "audmsg", "i_last")]:
    declaration = re.search(r"\b" + kind + r"\s+" + first + r"\b(.*?)\b" + last, source, re.S)[1]
    declaration = first + re.sub(r"//[^\n]*|/\*.*?\*/", "", declaration, flags=re.S)
    state_names.extend(re.findall(r"\b\w+\b", declaration))
newstate = lua_full.split("local function NewState()", 1)[1].split("\nend", 1)[0]
newstate = re.sub(r"--[^\n]*", "", newstate)
lua_state = re.findall(r"\b([A-Za-z_]\w*)\s*=", newstate)
check(Counter(lua_state) == Counter(state_names) and len(state_names) == len(set(state_names)),
      "all native state fields must be retained exactly once in NewState")


def cpp_active(text):
    return re.sub(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*',
                  lambda m: m[0] if m[0].startswith('"') else "", text, flags=re.S)


def lua_active(text):
    return re.sub(r'"(?:\\.|[^"\\])*"|--\[(=*)\[.*?\]\1\]|--[^\n]*',
                  lambda m: m[0] if m[0].startswith('"') else "", text, flags=re.S)


native_literals = Counter(re.findall(r'"((?:\\.|[^"\\])*)"', cpp_active(gameplay)))
lua_literals = Counter(re.findall(r'"((?:\\.|[^"\\])*)"', lua_active(lua)))
for serializer in ("b_array", "f_array", "h_array", "i_array"):
    native_literals.pop(serializer, None)       # native Save/Load field names, replaced by Save()/Load()
check(not (native_literals - lua_literals), "active native labels, paths, names, and files must all survive: "
      + str(native_literals - lua_literals))
check(not re.search(r"\b(Get_Time|GameObjectHandle|NULL|WHITE)\b", lua_active(lua)), "native-only syntax in Lua")

# ---- the explicit co-op substitutions outside the markers -----------------------------------------
active = lua_active(lua)
start_fn = active.split("function Start()", 1)[1].split("function Update(", 1)[0]
update = active.split("function Update(timestep)", 1)[1].split("function Save()", 1)[0]
all_active = lua_active(lua_full)
check("local LEADER_TEAM, ENEMY_TEAM = 1, 5" in all_active, "team constants")
# The CCA is script-driven: no strategic AI anywhere, no AIP.
check(re.search(r"\bSetAIControl\s*\(|\bSetAIP\s*\(|\bGetAIP\s*\(", all_active) is None,
      "misn11 has no AIP and no SetAIControl: the CCA is script-driven")
check(re.search(r'BuildObject\s*\(\s*"\w+",\s*[2-4]\s*,', all_active) is None
      and re.search(r"\b(SetScrap|SetPilot)\s*\(\s*[234]\s*[,)]", all_active) is None,
      "CCA spawns must use ENEMY_TEAM, never the DLL's team 2 or a guest team")
check("SetTeamNum(M.openh, ENEMY_TEAM)" in update and "SetTeamNum(M.openh, 2)" not in update,
      "the defecting tug joins the CCA team")
check('BuildObject("svfigh", ENEMY_TEAM, "strike1")' in update and 'BuildObject("svfigh", ENEMY_TEAM, "strike2")' in update
      and 'BuildObject("svtank", ENEMY_TEAM, "launch_attack")' in update
      and 'BuildObject("svfigh", ENEMY_TEAM, M.launch2)' in update, "stock spawns on the CCA team")
check(update.count("GetTeamNum(h) == ENEMY_TEAM and not IsBackupUnit(h)") == 3,
      "every svfigh scan is CCA-only and never takes the backup squad")
check(not re.search(r'IsOdfBase\(h, "svfigh"\) then', update), "no unfiltered svfigh scan survives")
check("SetScrap(1, 50)" in update and "SetPilot" not in active, "the shared base keeps the DLL's team-1 scrap")
body = update
check(not re.search(r"M\.player\b", re.sub(r"\bplayer\b", "", body)) , "the mission body no longer reads M.player")
check(not re.search(r"Distance\s*\(\s*[^)]*M\.player", body), "player-handle distance test left in the mission body")
check("GetPlayerHandle" not in body, "the mission body does not read the local player handle")
check("AnyPlayerWithin(M.cam1, 50.0)" in body and "AnyPlayerWithin(M.launch, 450.0)" in body,
      "check1 and the pad ambush trigger on any player")
check("CRCoop.AnyPlayerSatisfies(function(h) return Distance(M.turr1, h) ~= 0 end)" in body,
      "the source's always-true pursuit warning is kept (any player)")
check("AllPlayersArrived(M.launch2, 200.0)" in body and "Distance(M.tug1, M.launch2) < 200.0" in body
      and "Distance(M.tug2, M.launch2) < 200.0" in body,
      "the win needs every human at launch2 plus both required tugs")
check("not IsAlive(M.turr2) and not IsAlive(M.walker)" in body, "the convoy restarts only when the blockade AND the walker are dead")
check("local victim = NearestPlayer(M.launch2)" in body and "Attack(last_guy, victim)" in body,
      "the last fighter hunts the nearest player")
check("CRCoop.SetMissionPhase(1)" in region_all, "convoy departure advances the respawn rally phase")
check('rallyPoints = { [0] = "base1", [1] = "avhaul0_tug" }' in region_all, "respawns rally at the start, then the lead tug")
check("CRCoop.ApplyCoopAlliances(ENEMY_TEAM)" in region_all, "co-op alliances target the CCA team")
check('require("CRIoSites11")' in region_all and "sites = IoSites" in region_all, "Io map data wired")
check("startLevel = 1" in region_all and "targetLevel = 1" in region_all, "calm at the start")
check("SetTargetLevel(2)" in region_all and "SetTargetLevel(3)" in region_all and "SetTargetLevel(4)" in region_all
      and "CRIoWeather.ForceLevel(5, 60.0, 10.0)" in region_all
      and "CRIoWeather.Quake(PAD_QUAKE_STRENGTH, PAD_QUAKE_SECONDS)" in region_all, "weather beats")
check(re.search(r"\bStartEarthquake\s*\(|\bStopEarthquake\s*\(", all_active) is None,
      "the mission never calls the stock earthquake natives; the weather director does the shake")
check('"misn1114.wav"' in region_all and '"misn1115.wav"' in region_all, "the unused Collins/Corbett lines are wired")
check("misn1100" not in lua_full, "misn1100 is the campaign retrospective voice, not an in-mission line")
check('BACKUP_SPAWN_X, BACKUP_SPAWN_Z, BACKUP_SPREAD_M = 906.0, 98614.0, 24.0' in region_all
      and 'local odfs = { "svtank", "svtank", "svfigh" }' in region_all, "backup squad composition and entry point")
check("SetCommand(unit, AiCommand.FORMATION, 1, M.openh)" in region_all and "Attack(unit, chaser, 1)" in region_all,
      "the squad forms up on the defector and engages chasers")
check("edge_path" not in lua_full, "edge_path is the play boundary, never a route")
print(f"misn11 source parity: {checks} checks passed; {len(state_names)} state fields")
