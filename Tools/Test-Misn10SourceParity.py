#!/usr/bin/env python3
"""Verify source provenance, complete cut-code retention, state, and asset names.

The co-op layer and the restored content (CCA scaling and hunters, tug rebuild, plan B, the Io
weather and pickup quake, the team filter, the rally point) live between exact marker lines. They
are stripped (inclusive) so every check below still proves the active DLL port is unchanged; each
co-op substitution outside the markers is asserted explicitly at the end.
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
    "Misn10Mission.cpp": "1e000fdc8e95fa7c58009b249031bb420c789980",
    "Misn10Mission.h": "794f56e6cb3b85c0d7877d42bebfd9c98293124b",
}.items():
    raw = (ROOT / "References/Misn10Source" / name).read_bytes()
    blob = b"blob " + str(len(raw)).encode() + b"\0" + raw
    check(hashlib.sha1(blob).hexdigest() == expected, f"verbatim source changed: {name}")

source = (ROOT / "References/Misn10Source/Misn10Mission.cpp").read_text()
lua_full = (ROOT / "Scripts/misn10cr.lua").read_text().replace("\r\n", "\n")

REGIONS = ("CR PDA", "CR co-op layer", "CR Io weather", "CR CCA scaling", "CR tug rebuild", "CR plan B",
           "CR team filter", "CR rally")
opens = {f"-- {name} >>": name for name in REGIONS}
closes = {f"-- {name} <<": name for name in REGIONS}
lua_lines = lua_full.split("\n")
for name in REGIONS:
    check(lua_lines.count(f"-- {name} >>") == lua_lines.count(f"-- {name} <<") > 0, "unbalanced markers: " + name)
region_text = {name: [] for name in REGIONS}
stripped_lines, inside = [], None
for line in lua_lines:
    if line in opens:
        assert inside is None, "nested region marker"
        inside = opens[line]
        region_text[inside].append([])
    elif line in closes:
        assert inside == closes[line], "region close without matching open"
        inside = None
    elif inside:
        region_text[inside][-1].append(line)
    else:
        stripped_lines.append(line)
assert inside is None, "unterminated region"
lua = "\n".join(stripped_lines)
region_all = "\n".join(l for lines in region_text.values() for region in lines for l in region)
for token in ("SpawnHunters", "SendHunters", "HUNTER_", "CCAExtraCount", "UpdateTugRebuild", "TUG_REBUILD",
              "tug_rebuilds", "UpdatePlanB", "PLAN_B_AIP", "UpdatePickupQuake", "PICKUP_QUAKE", "CRIoWeather",
              "IoSites", "UpdateIoBeats", "UpdateRally", "rallyDropped", "AddObjectTeamAllowed",
              "CCA_START_SCRAP", "CCA_SCRAP_PER_EXTRA", "ioStarted", "ioSeed"):
    check(token not in lua, "region code outside marker regions: " + token)
gameplay = source[source.index("void Misn10Mission::Setup(void)"):]

# Comments may contain nested // lines, so tokenize in lexical order.
tokens = re.findall(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*', gameplay, re.S)
blocks = [token for token in tokens if token.startswith("/*")]
disabled_lines = [token for token in tokens if token.startswith("//")
                  and re.search(r";|\bif\s*\(|^//\s*[{}]", token)]
for comment in blocks + disabled_lines:
    check(comment in lua, "missing verbatim gameplay comment: " + comment[:80])

state_fields = []
for kind, first, last, expected_count in [
    ("bool", "start_done", "b_last", 66),
    ("float", "gech_warning_message", "f_last", 13),
    ("Handle", "user", "h_last", 31),
    ("int", "audmsg", "i_last", 1),
]:
    declaration = re.search(r"\b" + kind + r"\s+" + first + r"\b(.*?)\b" + last, source, re.S)[1]
    declaration = first + re.sub(r"//[^\n]*|/\*.*?\*/", "", declaration, flags=re.S)
    names = re.findall(r"\b\w+\b", declaration)
    check(len(names) == expected_count, "source state count: " + kind)
    state_fields.extend(names)
lua_fields = re.findall(r"\bstate\.(\w+)\s*=", lua)
check(Counter(lua_fields) == Counter(state_fields), "all 111 native state fields must be retained exactly once")


def cpp_active(text):
    return re.sub(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*',
                  lambda m: m[0] if m[0].startswith('"') else "", text, flags=re.S)


def lua_active(text):
    # Preserve string literals when stripping either form of Lua comment.
    return re.sub(r'"(?:\\.|[^"\\])*"|--\[(=*)\[.*?\]\1\]|--[^\n]*',
                  lambda m: m[0] if m[0].startswith('"') else "", text, flags=re.S)


native_literals = Counter(re.findall(r'"((?:\\.|[^"\\])*)"', cpp_active(gameplay)))
lua_literals = Counter(re.findall(r'"((?:\\.|[^"\\])*)"', lua_active(lua)))
check(not (native_literals - lua_literals), "active native labels, paths, names, and files must all survive")
check(not re.search(r"\b(Get_Time|GameObjectHandle|NULL|WHITE)\b", lua_active(lua)), "native-only syntax in Lua")

# ---- the explicit co-op substitutions outside the markers -----------------------------------------
active = lua_active(lua)
update = active.split("function Update(dt)", 1)[1].split("function Save()", 1)[0]
start_fn = active.split("function Start()", 1)[1].split("function AddObject", 1)[0]
check("local LEADER_TEAM, ENEMY_TEAM, SUPPORT_TEAM = 1, 5, 7" in active, "team constants")
# Native AiMission enabled the CCA's strategic AI; the chunk root does the same on the remapped team
# (Start is too late: the engine has already run DR_AI_Init).
check(active.count("SetAIControl(") == 1 and re.search(r"^SetAIControl\(ENEMY_TEAM, true\)$", active, flags=re.M) is not None
      and "SetAIControl" not in start_fn + update,
      "SetAIControl belongs at chunk load only, once, on the CCA team")
check(re.search(r"\b(SetScrap|SetPilot|GetScrap)\s*\(\s*[234]\s*[,)]", active) is None
      and re.search(r'BuildObject\s*\(\s*"\w+",\s*[234]\s*,', active) is None,
      "CCA spawns and resources must use ENEMY_TEAM, never the DLL's team 2 or a guest team")
check("SetScrap(ENEMY_TEAM, 40)" in update and "SetPilot(ENEMY_TEAM, 40)" in update
      and 'SetAIP("misn10.aip", ENEMY_TEAM)' in update and 'SetAIP("misn10a.aip", ENEMY_TEAM)' in update
      and "GetScrap(ENEMY_TEAM) > 15.0" in update, "CCA resources and AIPs on the CCA team")
check("SetScrap(1, 30)" in update and "SetPilot(1, 10)" in update and "local function SetScrap" not in active
      and 'Present("Resources"' not in active, "the shared base keeps the DLL's team-1 resources (only the host builds)")
check("GetTeamNum(M.tugger) ~= ENEMY_TEAM" in update and "GetTeamNum(M.tugger) == 1" not in active,
      "any non-CCA tug secures the relic")
check("CRCoop.IsHumanTeam(GetTeamNum(M.tugger))" in update, "any human team's tug is chased")
check(not re.search(r"Distance\s*\(\s*M\.user", update) and "GetDistance(M.user" not in update,
      "player-handle distance test left in the mission body")
check(update.count("AnyPlayerWithin(M.sav, 100.0)") == 1 and update.count("NearestPlayer(M.geys1)") == 1,
      "relic marker and artillery use the any/nearest-player helpers")
check("Attack(M.svartil1, nearest)" in update and "Attack(M.svartil2, nearest)" in update,
      "artillery targets the nearest player")
check(re.search(r"\bStartEarthquake\s*\(|\bStopEarthquake\s*\(", lua_active(lua_full)) is None,
      "the mission never calls the stock earthquake natives; the weather director does the shake")
# Restored content.
check("TUG_REBUILD_DELAY_S, TUG_REBUILD_MAX = 30.0, 2" in region_all
      and 'BuildObject("svhaul", ENEMY_TEAM, factory)' in region_all, "tug rebuild: 30 s, max 2, CCA team")
check('PLAN_B_AIP = "misn10b.aip"' in region_all and "SetAIP(PLAN_B_AIP, ENEMY_TEAM)" in region_all
      and "SetScrap(ENEMY_TEAM, CCA_START_SCRAP + CCA_SCRAP_PER_EXTRA * CCAExtraCount())" in region_all,
      "plan B AIP on the CCA team")
check("PICKUP_QUAKE_STRENGTH, PICKUP_QUAKE_SECONDS = 0.85, 6.0" in region_all
      and "CRIoWeather.Quake(PICKUP_QUAKE_STRENGTH, PICKUP_QUAKE_SECONDS)" in region_all, "pickup quake wired to the director")
check("CCA_START_SCRAP, CCA_SCRAP_PER_EXTRA, CCA_EXTRA_MAX = 40, 10, 3" in region_all, "CCA scaling constants")
check('require("CRIoSites10")' in region_all and "sites = IoSites" in region_all, "Io map data wired")
check("misn1007" not in lua_full, "misn1007 is the campaign epilogue voice, not an in-mission line")
check('rallyPoints = { [0] = "avrecycler" }' in lua_full, "respawns rally at Utah")
print(f"misn10 source parity: {checks} checks passed; {len(blocks)} block comments and "
      f"{len(disabled_lines)} disabled lines retained; 111 state fields")
