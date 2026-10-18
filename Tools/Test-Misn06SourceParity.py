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
# Presentation additions do not replace the source mission's audio/timer block.
for marker in ('launch film',):
    opening, closing = '-- CR ' + marker + ' >>', '-- CR ' + marker + ' <<'
    assert lua.splitlines().count(opening) == lua.splitlines().count(closing) > 0
    lua = re.sub(r'^' + re.escape(opening) + r'\n.*?^' + re.escape(closing) + r'\n', '', lua, flags=re.S | re.M)

# Campaign Reimagined restored-VO additions live between exact marker lines and keep
# every original statement in an else branch. Strip them (inclusive) so all checks
# below still prove the active DLL port is unchanged.
VO_OPEN, VO_CLOSE = "-- CR restored VO >>", "-- CR restored VO <<"
lua_lines = lua.split("\n")
assert lua_lines.count(VO_OPEN) == lua_lines.count(VO_CLOSE) > 0, "unbalanced restored-VO markers"
restored_vo = []
stripped_lines, inside = [], False
for line in lua_lines:
    if line == VO_OPEN:
        assert not inside, "nested restored-VO marker"
        inside = True
        restored_vo.append([])
    elif line == VO_CLOSE:
        assert inside, "restored-VO close without open"
        inside = False
    elif inside:
        restored_vo[-1].append(line)
    else:
        stripped_lines.append(line)
assert not inside, "unterminated restored-VO region"
cut_vo_text = "\n".join(l for region in restored_vo for l in region)
lua = "\n".join(stripped_lines)
for token in ("RESTORED_VO", "CUT_VO", "vob1", "vob3", "vob4", "vob5", "aud610", "aud636"):
    assert token not in lua, "restored-VO code outside marker regions: " + token
# Every restored wav needs its shipped subtitle text (never invent text).
cut_table = re.search(r"local CUT_VO = \{(.*?)\n\}", cut_vo_text, flags=re.S)
assert cut_table, "CUT_VO table missing from restored-VO region"
cut_wavs = sorted(set(re.findall(r'"(misn06\d\d)\.wav"', cut_table[1])))
assert cut_wavs, "CUT_VO lists no wavs"
missing_text = [w for w in cut_wavs if not (ROOT / "Text" / (w + ".txt")).is_file()]
assert not missing_text, "restored VO without Text subtitle: " + ", ".join(missing_text)
for wav in re.findall(r'"(misn06\d\d)\.wav"', cut_vo_text):
    assert wav in cut_wavs or wav in {"misn0636", "misn0614"}, "restored wav missing from CUT_VO: " + wav

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
      f"{len(re.findall(strings, cpp))} ordered string references, and source API call counts passed; "
      f"{len(restored_vo)} restored-VO regions stripped, {len(cut_wavs)} restored wavs have Text subtitles")
