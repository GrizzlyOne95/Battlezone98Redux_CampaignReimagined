#!/usr/bin/env python3
"""Verify misn12 source provenance, state, asset names and every co-op substitution.

The co-op layer and the restored/added content (Europa weather, the artillery, scaling, Razor One)
live between exact marker lines. They are stripped (inclusive) so the checks below prove the active
DLL port is unchanged; each substitution outside the markers is asserted explicitly at the end.
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
    "Misn12Mission.cpp": "547a9e0849cd16070060e31f26cf6aa8c4d14b61",
    "Misn12Mission.h": "65abfbd4adddbe22af8dbe589f11bd0d3c36d6da",
}.items():
    raw = (ROOT / "References/Misn12Source" / name).read_bytes()
    blob = b"blob " + str(len(raw)).encode() + b"\0" + raw
    check(hashlib.sha1(blob).hexdigest() == expected, f"verbatim source changed: {name}")

source = (ROOT / "References/Misn12Source/Misn12Mission.cpp").read_text(encoding="utf-8", errors="replace")
lua_full = (ROOT / "Scripts/misn12cr.lua").read_text().replace("\r\n", "\n")

REGIONS = ("CR PDA", "CR co-op layer", "CR Europa weather", "CR scaling", "CR artillery", "CR Razor One")
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
for token in ("ExtraHumans", "BuildExtraPatrols", "BuildHunters", "UpdateArtillery", "ART_RANGE_M",
              "CREuropaWeather", "EuropaSites", "UpdateEuropaWeather", "UpdateEuropaBeats", "UpdateRazor",
              "InitializeRazorState", "KEY_STAGGER_S", "Present(", "focusTeam"):
    check(token not in lua, "region code outside marker regions: " + token)
gameplay = source[source.index("void Misn12Mission::Setup(void)"):]

# ---- state: every native member is a NewState key, exactly once -----------------------------------
state_names = []
for kind, first, last in [("bool", "start_done", "b_last"), ("float", "countdown_time", "f_last"),
                          ("Handle", "user", "h_last"), ("int", "audmsg", "i_last")]:
    declaration = re.search(r"\b" + kind + r"\s+" + first + r"\b(.*?)\b" + last, source, re.S)[1]
    declaration = first + re.sub(r"//[^\n]*|/\*.*?\*/", "", declaration, flags=re.S)
    state_names.extend(re.findall(r"\b\w+\b", declaration))
newstate = lua_full.split("local function NewState()", 1)[1].split("\nend", 1)[0]
newstate = re.sub(r"--[^\n]*", "", newstate)
lua_state = re.findall(r"\bstate\.([A-Za-z_]\w*)\s*=", newstate)
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

# The 180 DLL conditionals survive in the active port (the co-op wrappers add none outside the markers
# except the explicit deltas below).
native_ifs = len(re.findall(r"\bif\s*\(", cpp_active(gameplay)))
lua_ifs = len(re.findall(r"\bif\b", lua_active(lua)))
check(lua_ifs >= native_ifs - 40 and lua_ifs <= native_ifs + 40,
      f"conditional count drifted: native {native_ifs}, lua {lua_ifs}")

# ---- the explicit co-op substitutions outside the markers -----------------------------------------
active = lua_active(lua)
all_active = lua_active(lua_full)
check("local LEADER_TEAM, ENEMY_TEAM, HIDDEN_TEAM = 1, 5, 7" in all_active, "team constants")
check(re.search(r"\bSetAIControl\s*\(|\bSetAIP\s*\(|\bGetAIP\s*\(", all_active) is None,
      "misn12 has no AIP: the CCA is script-driven")
check(re.search(r'BuildObject\s*\(\s*"\w+",\s*[2-4]\s*,', all_active) is None
      and re.search(r"\b(SetScrap|SetPilot)\s*\(\s*[234]\s*[,)]", all_active) is None,
      "CCA spawns must use ENEMY_TEAM and pods HIDDEN_TEAM, never the DLL's team 2/3 or a guest team")
check(active.count('"apcamr", HIDDEN_TEAM,') == 6, "the six camera pods hide on the support team")
check(active.count("SetTeamNum(M.start_cam, HIDDEN_TEAM)") == 1 and active.count(", HIDDEN_TEAM)") >= 6,
      "camera pods return to the hidden team, not guest team 3")
check('BuildObject("svfi12", ENEMY_TEAM, M.spawn_geyser)' in active, "the key ship is a CCA craft")
check(active.count('BuildObject("svfigh", ENEMY_TEAM, M.spawn_geyser)') == 2
      and active.count('BuildObject("svltnk", ENEMY_TEAM, M.spawn_geyser)') == 2, "death squad on the CCA team")
check(active.count('BuildObject("svtank", ENEMY_TEAM,') == 8, "discovery guards on the CCA team")
check('BuildObject("svfigh", ENEMY_TEAM, "3spawn")' in active and 'BuildObject("svfigh", ENEMY_TEAM, "4spawn")' in active,
      "warning escorts on the CCA team")
check("GetPlayerHandle" not in active.split("function Update(")[1].split("UpdateStart()")[0].replace(
    "M.user = GetPlayerHandle()", ""), "the leader's handle is only M.user's anchor")
# Per human: the DLL's progress fields move with the human being processed.
check("ForEachHuman(UpdateProgress)" in active and "ForEachHuman(UpdateCapture)" in active
      and "ForEachHuman(UpdateBlownTank)" in active and "ForEachHuman(UpdateBlownTankNearCheckpoint)" in active,
      "checkpoint, capture and tank gates run once per human")
check("ForEachSlot(UpdateKeyCycle)" in active and "ForEachSlot(UpdateBlownKeyShip)" in active,
      "the key-ship cycle runs once per ship")
check(active.count("(not M.slot_captured)") == 4 and "(not M.key_captured) and (not M.checked_in)" not in active,
      "the key ship leaves the cycle when taken (per ship)")
check("if (M.captured_any) and (M.camera_time < GetTime())" in active, "the capture tour is shared")
check("AllHumansArrived(M.nav1, 75.0)" in active and "Distance(M.user, M.nav1)" not in active,
      "the win needs every human at the drop zone")
check("(AllHumansBeyond(M.center, 300.0))" in active and "(AllHumansBeyond(M.checkpoint1, 300.0))" in active,
      "a nav-console reveal ends only when every human is far")
check(len(re.findall(r"Attack\(M\.death_squad\d, TargetFor\(", active)) == 4, "the death squad hunts the nearest human")
check("TopUpAmmo(entry)" in all_active and "Disguise(entry)" in all_active, "capture tops up and disguises per human")
check("if M.strict and M.real_bad and not M.interface_complete then CoverBlown() end" in all_active
      and 'CoverBlown("misn1213.wav")' in all_active,
      "several humans: exposure or a wrong vehicle blows cover for everyone")
check("Broadcast(function()" in all_active, "the uplink result reaches every panel")
check(len(re.findall(r"local shot = CheckpointShotReady\(\)", all_active)) == 6, "six checkpoint shots go through the camera arbiter")
check(len(re.findall(r"BuildExtraPatrols\(\)|BuildHunters\(\)", all_active)) == 4, "scaling hooks")
# Region facts.
check("CRCoop.ApplyCoopAlliances(ENEMY_TEAM)" in region_all, "co-op alliances target the CCA team")
check('rallyPoints = { [0] = "apcamr20_camerapod" }' in region_all, "respawns rally at the drop zone nav")
check('require("CREuropaSites12")' in region_all and "sites = EuropaSites" in region_all, "Europa map data wired")
check("startLevel = 1" in region_all and "targetLevel = 1" in region_all, "calm at the start")
check("MAX_PLAYERS = 4" in region_all and "KEY_STAGGER_S" in region_all, "up to four key ships, staggered")
check('"sbhqt1", "sbhqt2"' in region_all, "the nav-console IsInfo prefixes are relayed")
check('"misn1224.wav"' in region_all, "the cut Razor One line is wired")
check(re.search(r"\bStartEarthquake\s*\(|\bStopEarthquake\s*\(", all_active) is None,
      "the mission never calls the stock earthquake natives; the weather director does the shake")
for cut in ("misn1225", "misn1226", "misn1231", "misn1232"):
    check(cut not in lua_full, cut + " stays cut")
check("misn1227" not in lua_full, "misn1227 is the campaign retrospective voice, not an in-mission line")
check("edge_path" not in lua_full, "edge_path is the play boundary, never a route")
print(f"misn12 source parity: {checks} checks passed; {len(state_names)} state fields")
