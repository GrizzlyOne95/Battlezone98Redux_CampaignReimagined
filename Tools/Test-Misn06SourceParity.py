#!/usr/bin/env python3
"""Verify DLL provenance, inactive-code retention, and ordered asset references."""
from collections import Counter
from hashlib import sha256
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
source_path = ROOT / "Docs/MissionSources/Misn06Mission.cpp"
lua_path = ROOT / "Scripts/misn06.lua"
raw = source_path.read_bytes()
assert sha256(raw).hexdigest() == "5a66c54a9d6c7f17ebb293434e645d317a50f7bb8e5518ff08fb705bfc27507a", "DLL source snapshot changed"
source = raw.decode("utf-8").replace("\r\n", "\n")
lua = lua_path.read_text(encoding="utf-8")

cpp_comment = r"//[^\n]*|/\*.*?\*/"
comments = Counter(m[0] for m in re.finditer(cpp_comment, source, flags=re.S))
lua_comments = re.findall(r"--\[=\[(.*?)\]=\]", lua, flags=re.S)
retained = "\n".join(lua_comments)
for comment, count in comments.items():
    assert retained.count(comment) >= count, "missing original comment: " + comment

cpp = re.sub(cpp_comment, "", source, flags=re.S)
cpp = cpp.split("void Misn06Mission::Execute(void)", 1)[1].split("Misn06Mission::Misn06Mission", 1)[0]
live = re.sub(r"--\[=\[.*?\]=\]", "", lua, flags=re.S)
live = re.sub(r"--[^\n]*", "", live)
live = live.split("function Update(dt)", 1)[1]
cpp = re.sub(r"\bWHITE\b", '"white"', cpp)
cpp = re.sub(r"\bGREEN\b", '"green"', cpp)
strings = r'"(?:\\.|[^"\\])*"'
assert re.findall(strings, cpp) == re.findall(strings, live), "active source asset/label sequence changed"

# Calls retain their count; three impossible handle/number comparisons become
# EnemyWithin, with the original thresholds checked by Lua scenario tests.
cpp_calls = Counter(re.findall(r"\b([A-Z]\w*)\s*\(", cpp))
lua_calls = Counter(re.findall(r"\b([A-Z]\w*)\s*\(", live))
mapping = {"GetDistance": "MissionDistance", "IsAudioMessageDone": "AudioDone",
           "StopAudioMessage": "StopAudio", "GetNearestEnemy": "NearestEnemy"}
for function, count in cpp_calls.items():
    if function == "GetNearestEnemy":
        assert lua_calls["NearestEnemy"] + lua_calls["EnemyWithin"] == count
    else:
        assert lua_calls[mapping.get(function, function)] == count, function + " call count changed"

# Unused source state stays available alongside the cut blocks.
declarations = re.sub(cpp_comment, "", source.split("void Misn06Mission::Setup", 1)[0], flags=re.S)
fields = []
for kind, sentinel in (("bool", "b"), ("float", "f"), ("Handle", "h"), ("int", "i")):
    section = re.search(r"\b" + kind + r"\s+([^;]*\b" + sentinel + r"_last)\s*;", declarations)[1]
    fields.extend(re.findall(r"\b\w+\b", section)[:-1])
for field in fields:
    key = "endtime" if field == "end" else field
    assert re.search(r"\bM\." + key + r"\s*=", lua), "source state omitted: " + field

assert "GetPosition(M.haephestus)" not in live, "Redux-only collision adjustment reintroduced"
assert "IsOdf(" not in live, "Redux-only death check reintroduced"
print(f"Misn06 DLL parity: {sum(comments.values())} comments, {len(fields)} state fields, "
      f"{len(re.findall(strings, cpp))} ordered string references, and source API call counts passed")
