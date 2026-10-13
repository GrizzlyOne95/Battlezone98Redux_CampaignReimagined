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
# The co-op preamble precedes this marker; the Execute body (DLL order) follows it.
assert "-- Misn06Mission::Execute body" in lua, "Execute-body marker missing"
live = re.sub(r"--\[=\[.*?\]=\]", "", lua.split("-- Misn06Mission::Execute body", 1)[1], flags=re.S)
live = re.sub(r"--[^\n]*", "", live)
cpp = re.sub(r"\bWHITE\b", '"white"', cpp)
cpp = re.sub(r"\bGREEN\b", '"green"', cpp)
strings = r'"(?:\\.|[^"\\])*"'
assert re.findall(strings, cpp) == re.findall(strings, live), "active source asset/label sequence changed"

# Calls retain their count; three impossible handle/number comparisons become
# EnemyWithin, with the original thresholds checked by Lua scenario tests.
cpp_calls = Counter(re.findall(r"\b([A-Z]\w*)\s*\(", cpp))
lua_calls = Counter(re.findall(r"\b([A-Z]\w*)\s*\(", live))
# A dialogue block plays its first line and queues the rest (subtitles append).
lua_calls["Play"] += lua_calls.pop("Queue", 0)
mapping = {"GetDistance": "MissionDistance", "IsAudioMessageDone": "AudioDone",
           "StopAudioMessage": "StopAudio", "GetNearestEnemy": "NearestEnemy",
           "AudioMessage": "Play"}  # AudioMessage -> subtit.Play/Queue (shared audio+subtitle presentation)
# Documented co-op substitutions, as (Lua name -> delta against the mapped DLL count).
# Each replaces one player-handle test in the DLL body with a helper over every human:
#   MissionDistance(player,x)<d -> AnyPlayerWithin x5 (Hephestus x2, blockade, starport, svrec),
#   MissionDistance(player,launchpad)>d -> NoPlayerWithin, bogey distance -> NoPlayerEnemyWithin,
#   Attack(wAu, player) -> Attack(wAu, NearestPlayer(wAu)) x2, extraction player test -> AllPlayersWithin.
# That removes 8 MissionDistance calls (5 any-player, launchpad, bogey, extraction) and the
# 2 Attack(..., player) targets gain a NearestPlayer call. IsInfo, SetScrap and the
# camera/cockpit/object-removal calls are lexical co-op wrappers of the same name.
COOP_DELTAS = {"MissionDistance": -8, "AnyPlayerWithin": 5, "NoPlayerWithin": 1,
               "NoPlayerEnemyWithin": 1, "NearestPlayer": 2, "AllPlayersWithin": 1}
expected = Counter()
for function, count in cpp_calls.items():
    if function == "GetNearestEnemy":
        assert lua_calls["NearestEnemy"] + lua_calls["EnemyWithin"] == count
    else:
        expected[mapping.get(function, function)] += count
for name, delta in COOP_DELTAS.items():
    expected[name] += delta
for name in expected:
    assert lua_calls[name] == expected[name], f"{name} call count changed: {lua_calls[name]} != {expected[name]}"

# Unused source state stays available alongside the cut blocks.
declarations = re.sub(cpp_comment, "", source.split("void Misn06Mission::Setup", 1)[0], flags=re.S)
fields = []
for kind, sentinel in (("bool", "b"), ("float", "f"), ("Handle", "h"), ("int", "i")):
    section = re.search(r"\b" + kind + r"\s+([^;]*\b" + sentinel + r"_last)\s*;", declarations)[1]
    fields.extend(re.findall(r"\b\w+\b", section)[:-1])
for field in fields:
    key = "endtime" if field == "end" else field
    assert re.search(r"\bM\." + key + r"\s*=", lua), "source state omitted: " + field

assert not re.search(r'BuildObject\("\w+", [23],', live), "CCA/platoon spawns must use ENEMY_TEAM/SUPPORT_TEAM"
assert "GetPosition(M.haephestus)" not in live, "Redux-only collision adjustment reintroduced"
assert "IsOdf(" not in live, "Redux-only death check reintroduced"
print(f"Misn06 DLL parity: {sum(comments.values())} comments, {len(fields)} state fields, "
      f"{len(re.findall(strings, cpp))} ordered string references, and source API call counts passed")
