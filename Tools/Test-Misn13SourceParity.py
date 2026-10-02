#!/usr/bin/env python3
"""Check original DLL provenance, all comments/state, and ordered API references."""
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
lua = (ROOT / "Scripts/misn13.lua").read_text(encoding="utf-8")
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
assert "M.bomber_reload = true" not in live, "cut bomber reload was enabled"
assert 'BuildObject("avhraz"' not in live, "cut bomber replacement was enabled"
print(f"Misn13 DLL parity: {sum(comments.values())} original comments, {len(fields)} state fields, "
      f"{total_strings} string references, {total_conditions} predicates, {total_assignments} assignments, "
      "exact source blobs, and API counts passed")
