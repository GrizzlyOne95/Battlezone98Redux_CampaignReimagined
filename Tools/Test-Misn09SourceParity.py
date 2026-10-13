#!/usr/bin/env python3
"""Check the DLL provenance, retained comments/state, and authored call order.

The co-op layer and the restored content (convoy scaling, Prescott's platoon, the cut radio
lines, the geyser-clear win, the replacement tug, the Venus weather, the team filter, the
rally point) live between exact marker lines. They are stripped (inclusive) so every check
below still proves the active DLL port is unchanged; each co-op substitution outside the
markers is an explicit API-count delta.
"""
import hashlib
import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = 0


def check(value, message):
    global checks
    assert value, message
    checks += 1


for name, expected in {
    "Misn09Mission.cpp": "888ee877b4b56348ddf3e9717f01aed95fc0f066",
    "Misn09Mission.h": "924152c5233b7933506d19c2417e7cbff84ea7a0",
}.items():
    data = (ROOT / "References/Misn09Source" / name).read_bytes()
    actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    check(actual == expected, "verbatim source blob changed: " + name)

source = (ROOT / "References/Misn09Source/Misn09Mission.cpp").read_text()
lua = (ROOT / "Scripts/misn09.lua").read_text().replace("\r\n", "\n")

REGIONS = ("CR Venus weather", "CR team filter", "CR convoy scaling", "CR Prescott platoon", "CR cut VO",
           "CR tug rebuild", "CR geyser-clear win", "CR rally")
opens = {f"-- {name} >>": name for name in REGIONS}
closes = {f"-- {name} <<": name for name in REGIONS}
lua_lines = lua.split("\n")
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
lua_full = lua
lua = "\n".join(stripped_lines)
for token in ("SpawnConvoyExtras", "FollowConvoyExtras", "ConvoyCombatUnits", "convoy_extra", "UpdatePrescott",
              "SpawnPrescott", "PRESCOTT_", "NoteBuiltUnit", "UpdateCutVo", "vo0917", "vo0910", "misn0917", "misn0910",
              "UpdateTugRebuild", "TUG_REBUILD", "tug_rebuilds", "tug_escort_due", "UpdateVenusBeats", "VenusSites",
              "CRVenusWeather", "UpdateRally", "rallyDropped", "AddObjectTeamAllowed", "CONVOY_EXTRA", "WALKER_FAR_M",
              "FACTORY_BUILD_RADIUS_M", "venusSeed"):
    check(token not in lua, "region code outside marker regions: " + token)
native_setup = source.split("void Misn09Mission::Setup(void)", 1)[1].split(
    "void Misn09Mission::AddObject(Handle h)", 1)[0]
native_update = source.split("void Misn09Mission::Execute(void)", 1)[1]
native_comments = re.findall(r"//[^\n]*|/\*[\s\S]*?\*/", native_setup + native_update)
for comment in native_comments:
    check(comment in lua, "original gameplay comment/cut code lost: " + comment[:100])

for kind, next_kind in [("bools", "floats"), ("floats", "handles"), ("handles", "integers"), ("integers", None)]:
    region = source.split("// " + kind, 1)[1]
    if next_kind:
        region = region.split("// " + next_kind, 1)[0]
    names = re.findall(r"\b\w+\b", region.split("struct {", 1)[1].split(";", 1)[0])[1:-1]
    for name in names:
        check(re.search(r"\bstate\." + name + r"\s*=", lua), "native state field lost: " + name)


def strip_cpp(text):
    return re.sub(r"//[^\n]*|/\*[\s\S]*?\*/", "", text)


def strip_lua(text):
    text = re.sub(r"--\[(=*)\[[\s\S]*?\]\1\]", "", text)
    return re.sub(r"--[^\n]*", "", text)


mapping = {"Get_Time": "GetTime", "GetDistance": "Distance", "SetName": "SetObjectiveName",
           "IsAudioMessageDone": "AudioDone", "StopAudioMessage": "StopAudio"}


def calls(text, native=False):
    # Compare authored API/local-wrapper call order. Native pointer casts and
    # object lookup for SetName/IsDeployed disappear in the stock Lua bindings.
    ignored = {"if", "and", "or", "not", "Factory", "GetObj", "NewState"}
    names = re.findall(r"\b([A-Za-z_]\w*)\s*\(", text)
    return [mapping.get(name, name) if native else name for name in names if name not in ignored]


active_lua = strip_lua(lua)
lua_setup = active_lua.split("local function Setup()", 1)[1].split("local trackedObjects", 1)[0]
check("-- Misn09Mission::Execute body" in lua, "Execute-body marker missing")
lua_update = strip_lua(lua.split("-- Misn09Mission::Execute body", 1)[1].split("function Save()", 1)[0])
check(calls(strip_cpp(native_setup), True) == calls(lua_setup), "Setup API call order differs from source")
# Documented co-op substitutions (each keeps its call position, so order is still compared):
#   Distance(user, x) tests -> AnyPlayerWithin x5 (the 70 m factory contact, the 100 m Nav 1 and two 400 m
#   fighter checks of misn0914, the 70 m Charon test) and NoPlayerWithin x1 (the 500 m convoy-spawn
#   hold-off). The remaining Distance calls measure objects against objects and are unchanged.
CO_OP_DISTANCE = {"AnyPlayerWithin": 5, "NoPlayerWithin": 1}
# The documented fix adds exactly the invocation missing in the convoy guard.
native_calls = calls(strip_cpp(native_update).replace("(CameraCancelled)", "(CameraCancelled())"), True)
lua_calls = calls(lua_update)
for name, expected in CO_OP_DISTANCE.items():
    check(lua_calls.count(name) == expected, f"{name} count changed: {lua_calls.count(name)} != {expected}")
check(native_calls.count("Distance") - sum(CO_OP_DISTANCE.values()) == lua_calls.count("Distance"),
      "object-to-object Distance calls changed")
normalized = ["Distance" if name in CO_OP_DISTANCE else name for name in lua_calls]
check(native_calls == normalized, "Execute API call order differs beyond the documented camera fix and co-op distance helpers")
check(not re.search(r"Distance\s*\(\s*M\.user", lua_update), "player-handle distance test left in the mission body")

native_add = source.split("void Misn09Mission::AddObject(Handle h)", 1)[1].split(
    "void Misn09Mission::Execute(void)", 1)[0]
native_slots = re.findall(r'if\s*\(\((\w+)\s*==\s*NULL\)\s*&&\s*\(IsOdf\(h,"(\w+)"\)\)\)', native_add)
lua_slots = re.findall(r'\{"(\w+)",\s*"(\w+)"\}', lua.split("local trackedObjects =", 1)[1].split("function AddObject", 1)[0])
check(native_slots == lua_slots and len(lua_slots) == 16, "AddObject first-empty slot order differs")
check("ObjectiveObjects" not in active_lua, "unsupported API introduced")
# Native AiMission enabled the CCA's strategic AI; Start does the same on the remapped team, outside Setup/Update.
check(active_lua.count("SetAIControl(ENEMY_TEAM, true)") == 1 and "SetAIControl" not in lua_setup + lua_update,
      "SetAIControl belongs in Start only, on the CCA team")
check("local LEADER_TEAM, ENEMY_TEAM, SUPPORT_TEAM = 1, 5, 7" in active_lua, "team constants")
check(re.search(r'BuildObject\s*\(\s*"\w+",\s*[234]\s*,', lua_setup + lua_update) is None
      and re.search(r"\b(SetScrap|SetPilot)\s*\(\s*[234]\s*,", lua_setup + lua_update) is None,
      "CCA spawns and resources must use ENEMY_TEAM, never the DLL's team 2 or a guest team")
check(len(re.findall(r'BuildObject\("\w+",\s*ENEMY_TEAM,', lua_update)) == 11, "tug plus ten escorts on the CCA team")
check(len(re.findall(r'SetAIP\("misn09\w?\.aip",\s*ENEMY_TEAM\)', lua_update)) == 3, "AIPs run on the CCA team")
check('BuildObject("obdata", RELIC_TEAM, M.convoy_geyser)' in lua_update and "local RELIC_TEAM = 0" in active_lua,
      "the relic is neutral, not the DLL's guest team 3")
check("GetTeamNum(M.tugger) ~= ENEMY_TEAM" in lua_update, "any non-CCA tug secures the relic")
check("CountUnitsNearObject(M.convoy_geyser, 5000.0, ENEMY_TEAM, nil)" in lua_update, "enemy-cleared query counts the CCA team")
check("SetScrap(1, 20)" in lua_update and "SetPilot(1, 7)" in lua_update and "local function SetScrap" not in active_lua,
      "the shared base keeps the DLL's team-1 resources (only the host builds)")
check(len(re.findall(r"-- PORT FIX:", lua)) == 3, "expected three documented source fixes")

# Restored radio lines: only 0917 and 0910 (0912 is a duplicate briefing and stays in its cut comment), each with
# its subtitle text and shipped wav; the geyser-clear win is the DLL's own cut SucceedMission, re-enabled.
region_all = "\n".join(l for lines in region_text.values() for region in lines for l in region)
wavs = sorted(set(re.findall(r'"(misn09\d\d)\.wav"', region_all)))
check(wavs == ["misn0910", "misn0917"], "restored voice lines: " + repr(wavs))
for wav in wavs:
    check((ROOT / "Text" / (wav + ".txt")).is_file(), "region VO without Text subtitle: " + wav)
    check((ROOT / "Assets/Audio" / (wav + ".wav")).is_file(), "region VO without shipped wav: " + wav)
check("misn0912" not in active_lua and "misn0912" not in region_all, "0912 must stay cut")
check('AudioMessage("misn0912.wav")' in lua, "the cut 0912 block stays in its comment")
geyser = "\n".join("\n".join(region) for region in region_text["CR geyser-clear win"])
check('SucceedMission(GetTime() + 15.0, "misn09w1.des")' in geyser, "geyser-clear win re-enabled in its region")
check('SucceedMission(Get_Time() + 15.0f, "misn09w1.des");' in lua, "the cut SucceedMission stays in its comment")
check('BuildObject("avtank", SUPPORT_TEAM, path)' in region_all, "Prescott's platoon spawns on the support team")
check('BuildObject("svhaul", ENEMY_TEAM, M.ccamuf)' in region_all, "the replacement tug is built at the CCA factory")

# The campaign validator must ignore preserved C++ in every Lua long-comment
# delimiter while still rejecting actual Lua 5.2 control flow after the comment.
spec = importlib.util.spec_from_file_location("campaign_validator", ROOT / "Tools/Validate-CampaignRepository.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
for equals in ["", "=", "=="]:
    text = "--[" + equals + "[\ngoto cut_content;\n]" + equals + "]\nGoto(unit, path)\ngoto live_label"
    code = validator.strip_lua_comments(text)
    check("cut_content" not in code and "Goto(unit, path)" in code and "goto live_label" in code,
          "validator misclassifies inactive C++ or loses live Lua syntax")
print(f"misn09: {checks} source preservation/parity checks passed")
