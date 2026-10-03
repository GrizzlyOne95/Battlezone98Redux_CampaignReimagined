#!/usr/bin/env python3
"""Check pinned DLL provenance, comments, state, conditions and API coverage."""
from collections import Counter
from hashlib import sha1
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "References/Misns1Source"
PINS = {
    "Misns1Mission.cpp": "2777814cd482d24d7d9aed0ee4b76bb5c937f241",
    "Misns1Mission.h": "43fb73ea0d7172dc74442979ffba85203f772c4e",
}
for filename, expected in PINS.items():
    raw = (ARCHIVE / filename).read_bytes()
    actual = sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
    assert actual == expected, "verbatim DLL source changed: " + filename

source = (ARCHIVE / "Misns1Mission.cpp").read_text(encoding="utf-8")
lua = (ROOT / "Scripts/misns1.lua").read_text(encoding="utf-8")
COMMENT = r"//[^\n]*|/\*.*?\*/"
setup = source.split("void Misns1Mission::Setup(void)", 1)[1].split("void Misns1Mission::AddObject(Handle h)", 1)[0]
execute = source.split("void Misns1Mission::Execute(void)", 1)[1].split("IMPLEMENT_RTIME", 1)[0]
comments = Counter(re.findall(COMMENT, setup + execute, flags=re.S))
retained = "\n".join(re.findall(r"--\[=\[(.*?)\]=\]", lua, flags=re.S))
for comment, count in comments.items():
    assert retained.count(comment) >= count, "original gameplay comment missing: " + comment

cpp = re.sub(COMMENT, "", execute, flags=re.S)
live = re.sub(r"--\[=\[.*?\]=\]", "", lua, flags=re.S)
live = re.sub(r"--[^\n]*", "", live).split("function Update(dt)", 1)[1]
for color in ("WHITE", "GREEN", "RED"):
    cpp = re.sub(r"\b" + color + r"\b", '"' + color.lower() + '"', cpp)
STRING = r'"(?:\\.|[^"\\])*"'
expected_strings = re.findall(STRING, cpp)
expected_strings = ['"misns103.otf"' if s == '"misn103.otf"' else s for s in expected_strings]
assert expected_strings == re.findall(STRING, live), "active label/asset order changed"

mapping = {
    "GetDistance": "MissionDistance", "GetNearestEnemy": "NearestEnemy",
    "Goto": "MissionGoto", "Follow": "MissionFollow", "Attack": "MissionAttack",
    "SetIndependence": "Independence", "SetObjectiveOn": "ObjectiveOn",
    "RemoveObject": "MissionRemove", "IsAudioMessageDone": "AudioDone",
    "SetName": "ObjectiveName",
}
cpp_calls = Counter(re.findall(r"\b([A-Z]\w*)\s*\(", cpp))
lua_calls = Counter(re.findall(r"\b([A-Z]\w*)\s*\(", live))
for function, count in cpp_calls.items():
    if function == "GetObj":
        continue  # Six native GetObj(...)->SetName calls become ObjectiveName.
    if function == "BuildObject":
        assert lua_calls["BuildObject"] + lua_calls["BuildAtFactory"] == count
    else:
        assert lua_calls[mapping.get(function, function)] == count, "API call coverage changed: " + function
assert cpp_calls["GetObj"] == lua_calls["ObjectiveName"] == 6

# Compare every original if predicate in order, excluding only the documented
# camera-validity and one-shot-outcome guards introduced by the port.
conditions = []
for match in re.finditer(r"\bif\s*\(", cpp):
    start = cpp.index("(", match.start())
    depth = 1
    end = start + 1
    while depth:
        depth += (cpp[end] == "(") - (cpp[end] == ")")
        end += 1
    conditions.append(cpp[start:end])
lua_conditions = re.findall(r"^\s*if (.*?) then\s*$", live, flags=re.M)
lua_conditions = [c for c in lua_conditions if c not in (
    "M.path == 0", "M.cav == 0",  # switch opening cases
    "not M.success_called", "not M.escape_failure_called",
    "not M.recycler_failure_called", "Valid(anchor) and Valid(M.colorado)",
)]
def canonical(condition, is_lua=False):
    if is_lua:
        condition = re.sub(r"\bM\.", "", condition)
        condition = re.sub(r"\band\b", "&&", condition)
        condition = re.sub(r"\bor\b", "||", condition)
        condition = re.sub(r"\bnot\s*", "!", condition)
        for original, translated in mapping.items():
            condition = re.sub(r"\b" + translated + r"\b", original, condition)
    condition = re.sub(r"(\d)f\b", r"\1", condition)
    return re.sub(r"\s+", "", condition)
assert [canonical(c) for c in conditions] == [canonical(c, True) for c in lua_conditions], "source predicate order or content changed"

decl = re.sub(COMMENT, "", source.split("void Misns1Mission::Setup", 1)[0], flags=re.S)
fields = {}
for kind, sentinel, default in (("bool", "b", "false"), ("float", "f", "99999.0"), ("Handle", "h", "nil"), ("int", "i", "0")):
    section = re.search(r"\b" + kind + r"\s+([^;]*\b" + sentinel + r"_last)\s*;", decl)[1]
    for field in re.findall(r"\b\w+\b", section)[:-1]:
        fields[field] = (kind, default)
for field, value in re.findall(r"\b(\w+)\s*=\s*([^;]+);", re.sub(COMMENT, "", setup, flags=re.S)):
    kind, _ = fields[field]
    value = re.sub(r"(\d)f\b", r"\1", value.strip())
    fields[field] = (kind, "nil" if kind == "Handle" and value == "0" else value)
for field, (_, value) in fields.items():
    match = re.search(r"\bstate\." + field + r"\s*=\s*([^\n]+)", lua)
    assert match and match[1].strip() == value, "source initial state changed: " + field
assert len(fields) == 143
assert "math.random(0, 2)" in live and "math.random(0, 3)" in live
assert "Goto(h, where, priority)" in lua and "MissionGoto(M.ef1, M.muf, 1000)" in live
print(f"misns1 DLL parity: 2 exact source blobs, {sum(comments.values())} gameplay comments, "
      f"{len(fields)} state fields, {len(conditions)} ordered predicates, "
      f"{len(expected_strings)} ordered strings, and API call coverage passed")
