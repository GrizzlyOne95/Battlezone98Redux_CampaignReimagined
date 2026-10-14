#!/usr/bin/env python3
"""Check original DLL provenance, all comments/state, and ordered API references.

Everything the campaign adds (the co-op layer, CCA scaling, the team filters, the whole-base win, the
restored waves, the objectives, the unused misn1301 line, the escort/reserve roles, the rally and the
weather) lives between exact `-- CR <name> >>` / `-- CR <name> <<` marker lines. They are stripped
(inclusive) so the checks below prove the active DLL port is unchanged. The few substitutions outside the
markers are normalized back to the DLL spelling here, each asserted explicitly first.
"""
from collections import Counter
from hashlib import sha1
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "References/Misn13Source"
for name, expected in {
    "Misn13Mission.cpp": "9116778815ab02b25467a9427961ddb573cf626f",
    "Misn13Mission.h": "c51fcc6fc360ff0090613cdd0cb52cc307af5c53",
}.items():
    raw = (SNAPSHOT / name).read_bytes()
    actual = sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
    assert actual == expected, f"original Git blob changed: {name}"

source = (SNAPSHOT / "Misn13Mission.cpp").read_text(encoding="utf-8")
lua_full = (ROOT / "Scripts/misn13.lua").read_text(encoding="utf-8").replace("\r\n", "\n")

REGIONS = ("CR co-op layer", "CR CCA scaling", "CR team filter", "CR win", "CR objectives", "CR cut VO",
           "CR restored waves", "CR escort", "CR reserve", "CR GetWhoShotMe", "CR rally", "CR Europa weather")
opens = {f"-- {name} >>": name for name in REGIONS}
closes = {f"-- {name} <<": name for name in REGIONS}
stack, kept, region_lines = [], [], []
lines = lua_full.split("\n")
for name in REGIONS:
    assert lines.count(f"-- {name} >>") == lines.count(f"-- {name} <<"), "unbalanced markers: " + name
for line in lines:
    if line in opens:
        stack.append(opens[line])
    elif line in closes:
        assert stack and stack[-1] == closes[line], "region close without matching open"
        stack.pop()
    elif stack:
        region_lines.append(line)
    else:
        kept.append(line)
assert not stack, "unterminated region"
lua = "\n".join(kept)
region_all = "\n".join(region_lines)
for token in ("UpdateWaves", "SpawnWave", "UpdateEscorts", "UpdateReserve", "UpdateCollins", "UpdateObjectives",
              "UpdateRally", "UpdatePresentationTransport", "InitializeCoopState", "RESTORED_WAVES", "misn1301",
              "misn13_", "SetAIControl"):
    assert token not in lua, "region code outside marker regions: " + token

# ---- The substitutions outside the markers (each asserted, then normalized to the DLL spelling) --------
# 1. The CCA is team 5 in co-op: the DLL's literal team 2 is ENEMY_TEAM (SetAIP names the team).
active = re.sub(r"--\[=\[.*?\]=\]", "", lua, flags=re.S)
assert not re.search(r"\b(SetScrap|AddScrap|GetScrap|SetPilot)\(2[,)]|BuildObject\(\"\w+\", 2,", active), \
    "a DLL team-2 literal survived: the CCA is ENEMY_TEAM (team 5)"
for call in ("SetScrap", "GetScrap", "SetPilot", "AddScrap"):
    assert f"{call}(ENEMY_TEAM" in lua, call + " must use ENEMY_TEAM"
assert lua.count("ENEMY_TEAM") == 42, "unexpected ENEMY_TEAM uses outside the markers: " + str(lua.count("ENEMY_TEAM"))
lua = lua.replace("ENEMY_TEAM", "2")
for aip in ("misn13.aip", "misn13a.aip", "misn13c.aip"):
    assert f'SetAIP("{aip}", 2)' in lua, "SetAIP must name the CCA team"
    lua = lua.replace(f'SetAIP("{aip}", 2)', f'SetAIP("{aip}")')
# 2. The factory-safety count covers every human team and scales its threshold (the DLL counted team 1).
count_line = "M.check = HumanUnitsNear(M.ccamuf, 400.0) - (HumanCount() - 1)"
assert lua.count(count_line) == 1, "the human-team count substitution is missing"
lua = lua.replace(count_line, "M.check = CountUnitsNearObject(M.ccamuf, 400.0, 1, nil)")
# 3. The win needs the hangar and all four silos as well as the Unit Factory.
win_guard = " and CCABaseDestroyed() then"
assert lua.count(win_guard) == 1, "the whole-base win guard is missing"
assert "if (not IsAlive(M.ccamuf)) and (not M.game_over)" + win_guard in lua
lua = lua.replace(win_guard, " then")
cpp_comment = r"//[^\n]*|/\*.*?\*/"
comments = Counter(re.findall(cpp_comment, source, flags=re.S))
retained = "\n".join(re.findall(r"--\[=\[(.*?)\]=\]", lua, flags=re.S))
for comment, count in comments.items():
    assert retained.count(comment) >= count, "original comment omitted: " + comment

cpp = re.sub(cpp_comment, "", source, flags=re.S)
live = re.sub(r"--\[=\[.*?\]=\]", "", lua, flags=re.S)
live = re.sub(r"--[^\n]*", "", live)
fields = []
declarations = cpp.split("void Misn13Mission::Setup", 1)[0]
for kind, sentinel in (("bool", "b"), ("float", "f"), ("Handle", "h"), ("int", "i")):
    names = re.search(r"\b" + kind + r"\s+([^;]*\b" + sentinel + r"_last)\s*;", declarations)[1]
    fields.extend(re.findall(r"\w+", names)[:-1])
for field in fields:
    assert re.search(r"\bstate\." + field + r"\s*=", live), "state field omitted: " + field

def native_section(name, following):
    return cpp.split(name, 1)[1].split(following, 1)[0]

def lua_section(name, following):
    return live.split(name, 1)[1].split(following, 1)[0]

sections = (
    (native_section("void Misn13Mission::Setup(void)", "void Misn13Mission::AddObject(Handle h)"),
     lua_section("function Start()", "function AddObject(h)"), "Setup"),
    (native_section("void Misn13Mission::AddObject(Handle h)", "void Misn13Mission::Execute(void)"),
     lua_section("local function RegisterObject(h)", "function Start()"), "AddObject"),
    (native_section("void Misn13Mission::Execute(void)", "IMPLEMENT_RTIME"),
     lua_section("function Update(dt)", "function Save()"), "Execute"),
)
strings = r'"(?:\\.|[^"\\])*"'
total_strings = 0
total_conditions = 0
total_assignments = 0

def normalize(expression):
    expression = expression.replace("M.", "").replace("Get_Time", "GetTime")
    expression = expression.replace("GetDistance", "MissionDistance").replace("IsOdf(", "IsOdfBase(")
    expression = expression.replace("NULL", "nil").replace("&&", "and").replace("||", "or")
    expression = expression.replace("!=", "~=")
    expression = re.sub(r"!(?!=)", "not", expression)
    expression = re.sub(r"(\d+\.\d+)f\b", r"\1", expression)
    return re.sub(r"[\s()]", "", expression)

def native_conditions(code):
    result = []
    for match in re.finditer(r"\bif\s*\(", code):
        start = match.end()
        end, depth = start, 1
        while depth:
            if code[end] == "(": depth += 1
            if code[end] == ")": depth -= 1
            end += 1
        result.append(code[start:end-1])
    return result

for native, port, name in sections:
    native = re.sub(r"GameObjectHandle::GetObj\((\w+)\)->GetHealth\(\)", r"GetHealth(\1)", native)
    native = re.sub(r"GameObjectHandle::GetObj\((\w+)\)->GetWhoTheHellShotMe\(\)", r"GetWhoShotMe(\1)", native)
    native = re.sub(r"\bWHITE\b", '"white"', native)
    references = re.findall(strings, native)
    assert references == re.findall(strings, port), f"ordered asset/label references changed: {name}"
    total_strings += len(references)
    expected = Counter(re.findall(r"\b([A-Z]\w*)\s*\(", native))
    calls = Counter(re.findall(r"\b([A-Z]\w*)\s*\(", port))
    for old, new in {"Get_Time": "GetTime", "GetDistance": "MissionDistance",
                     "IsOdf": "IsOdfBase", "SetName": "SetObjectiveName"}.items():
        if old in expected:
            expected[new] += expected.pop(old)
    if name == "Setup":
        expected.update({"NewState": 1, "RegisterObject": 1})
    elif name == "AddObject":
        expected.update({"IsValid": 1})
    else:
        # The discarded timer comparison is omitted. Only the five destroyed-
        # object guards are new predicates; commands/asset references stay ordered.
        expected["GetTime"] -= 1
        expected["GetObj"] -= 1  # native camera-name access becomes stock Lua call
        expected["IsAlive"] += 5
    expected += Counter()  # discard zero entries
    assert calls == expected, f"API count mismatch in {name}: expected {expected}, got {calls}"

    native_tests = [normalize(c) for c in native_conditions(native)]
    lua_tests = [normalize(c) for c in re.findall(r"\b(?:if|elseif)\s+(.*?)\s+then", port, flags=re.S)]
    if name == "AddObject":
        lua_tests = lua_tests[1:]  # invalid-callback guard
    if name == "Execute":
        native_tests = [
            "shot_by~=niland" + c if c == "shot_by~=0" else
            re.sub(r"svscav([1-4])~=nil", r"IsAlivesvscav\1", c)
            for c in native_tests
        ]
        native_tests = [c + "andIsAliveccamuf" if c.startswith("notgame_overandmuf_attacked") else c
                        for c in native_tests]
    assert native_tests == lua_tests, f"ordered predicates changed: {name}"
    total_conditions += len(native_tests)

    native_assign = [(field, normalize(value)) for field, value in
                     re.findall(r"\b(\w+)\s*=(?!=)\s*([^;]+);", native)]
    lua_assign = [(field, normalize(value)) for field, value in
                  re.findall(r"\bM\.(\w+)\s*=(?!=)\s*([^\n]+)", port)]
    assert native_assign == lua_assign, f"ordered state assignments changed: {name}"
    total_assignments += len(native_assign)

assert "M.safe_time_check = GetTime() + 60" not in live, "factory polling cadence changed"
assert 'AudioMessage("misn1303.wav")' in live and 'SucceedMission(GetTime() + 15.0, "misn13w1.des")' in live,     "the victory line and result are the DLL's"
assert "misn1300.otf" in live, "the DLL objective stays (the CR objectives replace it after it runs)"
assert "M.bomber_reload = true" not in live, "cut bomber reload was enabled"
assert 'BuildObject("avhraz"' not in live, "cut bomber replacement was enabled"
print(f"Misn13 DLL parity: {sum(comments.values())} original comments, {len(fields)} state fields, "
      f"{total_strings} string references, {total_conditions} predicates, {total_assignments} assignments, "
      "exact source blobs, and API counts passed")
