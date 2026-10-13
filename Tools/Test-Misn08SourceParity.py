#!/usr/bin/env python3
"""Verify DLL provenance, inactive-code retention, and ordered asset references for misn08.

The co-op layer and the restored content (the Colorado base and witnessable massacre, walker 3's
advance, the CCA walker production, the Venus weather, the 0816 close-range warning, the relic heal fix, the failure line, the AddObject
team filter) live between exact marker lines. They are stripped (inclusive) so every
check below still proves the active DLL port is unchanged; each co-op substitution
outside the markers is an explicit API-count delta.
"""
from collections import Counter
from hashlib import sha256
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
source_path = ROOT / "References/Misn08Source/Misn08Mission.cpp"
lua_path = ROOT / "Scripts/misn08.lua"
raw = source_path.read_bytes()
# Pinned on LF-normalized bytes so the check is independent of checkout line endings.
assert sha256(raw.replace(b"\r\n", b"\n")).hexdigest() == "d243e4829850eee64f151c6962d7f734f05c79acf9f2f240327c5cf1a0522de5", "DLL source snapshot changed"
source = raw.decode("utf-8").replace("\r\n", "\n")
lua = lua_path.read_text(encoding="utf-8").replace("\r\n", "\n")

REGIONS = ("CR Colorado massacre", "CR restored walker content", "CR relic heal fix", "CR failure VO", "CR team filter",
           "CR Colorado base", "CR CCA walkers", "CR Venus weather")
opens = {f"-- {name} >>": name for name in REGIONS}
closes = {f"-- {name} <<": name for name in REGIONS}
lua_lines = lua.split("\n")
for name in REGIONS:
    assert lua_lines.count(f"-- {name} >>") == lua_lines.count(f"-- {name} <<") > 0, "unbalanced markers: " + name
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
for token in ("UpdateColoradoMassacre", "ColoradoMassacreDone", "ColoradoStrikeUnits", "COLORADO_", "M.strike",
              "colorado_warned", "colorado_deadline", "RestoredWalkerAdvance", "RestoredCloseWarning", "GECH3_FALLBACK_S",
              "gech3_fallback", "VO_SUBSTITUTE", "misn0823", "misn0824", "AddObjectTeamAllowed", "next_second = 0",
              "next_second2 = 0", "UpdateColoradoBase", "UpdateCcaWalkers", "ColoradoForce", "ColoradoTarget",
              "ColoradoExtraStrike", "COLORADO_ESCORT", "COLORADO_BUILDS", "WALKER_", "cbase", "M.cw", "colorado_cleanup",
              "colorado_cleaned", "CRVenusWeather", "UpdateVenusBeats", "VenusSites", "venusSeed"):
    assert token not in lua, "region code outside marker regions: " + token

# Restored/substituted voice lines need their shipped subtitle text (never invent text); 0825 stays unused.
region_all = "\n".join(l for lines in region_text.values() for region in lines for l in region)
wavs = sorted(set(re.findall(r'"(misn08\d\d)\.wav"', region_all)))
assert set(wavs) == {"misn0816", "misn0823", "misn0824"} | ({"misn0421"} & set(wavs)), wavs
for wav in wavs:
    if wav.startswith("misn08"):
        assert (ROOT / "Text" / (wav + ".txt")).is_file(), "region VO without Text subtitle: " + wav
assert (ROOT / "Text/misn0421.txt").is_file()
assert "misn0825" not in region_all and "misn0825" not in lua, "0825 must stay unused"

# Disabled C++ blocks stay in Lua comments; // comments are kept as -- comments.
cpp_comment = r"//[^\n]*|/\*.*?\*/"
# Declaration and serialization comments stay in References/Misn08Source; the Lua keeps
# every comment from the gameplay routines (Setup, AddObject, Execute).
gameplay = "void Misn08Mission::Setup(void)" + source.split("void Misn08Mission::Setup(void)", 1)[1]
gameplay = gameplay.split("Misn08Mission::Misn08Mission(void)", 1)[0]
comments = Counter(m[0] for m in re.finditer(cpp_comment, gameplay, flags=re.S))
# The misn08 port translated comments in place (C++ delimiters dropped, `M.` prefixes and
# semicolons adjusted), so compare them with that punctuation normalized away.
def norm(text):
    text = re.sub(r"/\*|\*/|//|--|;|M\.", "", text)
    return re.sub(r"\s+", "", text).lower()
haystack = norm(lua)
# Commented-out C++ statements were re-expressed in Lua syntax; their prose comments are checked
# verbatim and the disabled blocks / statements are asserted explicitly below.
missing = [c for c in comments if norm(c) and not re.search(r"[(=]", c) and norm(c) not in haystack]
block_comments = "\n".join(re.findall(r"--\[=*\[(.*?)\]=*\]", lua, flags=re.S))
for needle in ("M.gech3_move = true", "M.gech3_there_time = GetTime() + 97.0", 'AudioMessage("misn0816.wav")'):
    assert needle in block_comments, "disabled block missing from its Lua comment: " + needle
for needle in ('-- M.drop = GetHandle("dropoff57_dropoff")', "-- SetPilot(1, 30)", "-- RemoveObject (M.colorado)", "-- RemoveObject (M.drop)"):
    assert needle in lua, "disabled statement missing: " + needle
assert not missing, "missing original comments: " + repr(missing[:5])

# Active code: Setup + AddObject + Execute against the Lua Setup + AddObject + Execute body.
cpp = re.sub(cpp_comment, "", gameplay, flags=re.S)
cpp = re.sub(r"\bvoid Misn08Mission::\w+\([^)]*\)", "", cpp)
assert "-- Misn08Mission::Execute body" in lua, "Execute-body marker missing"
setup_add = lua.split("local function Setup()", 1)[1].split("local function InitializeCoop()", 1)[0]
execute = lua.split("-- Misn08Mission::Execute body", 1)[1].split("function Save()", 1)[0]
live = re.sub(r"--\[=*\[.*?\]=*\]", "", setup_add + "\n" + execute, flags=re.S)
live = re.sub(r"--[^\n]*", "", live)
strings = r'"(?:\\.|[^"\\])*"'
cpp_text = re.sub(r"\bWHITE\b", '"white"', re.sub(r"\bGREEN\b", '"green"', cpp))
cpp_strings = re.findall(strings, cpp_text)
lua_strings = re.findall(strings, live)
import difflib
if cpp_strings != lua_strings:
    for line in list(difflib.unified_diff(cpp_strings, lua_strings, lineterm="", n=1))[:30]: print(line)
assert cpp_strings == lua_strings, "active source asset/label sequence changed"

live_calls = re.sub(r"\bfunction\s+\w*\s*\([^)]*\)", "", live)
cpp_calls = Counter(re.findall(r"\b([A-Z]\w*)\s*\(", cpp))
lua_calls = Counter(re.findall(r"\b([A-Z]\w*)\s*\(", live_calls))
# A dialogue block plays its first line and queues the rest.
lua_calls["Play"] += lua_calls.pop("Queue", 0)
mapping = {"Get_Time": "GetTime", "GetDistance": "Distance", "AudioMessage": "Play", "SetName": "SetObjectiveName"}
# C++-only constructs with no Lua call: native object lookups on the setup path.
cpp_only = {"GetObj": cpp_calls["GetObj"], "AddObject": cpp_calls["AddObject"], "Setup": cpp_calls["Setup"],
            "Execute": cpp_calls["Execute"], "IMPLEMENT_RTIME": cpp_calls["IMPLEMENT_RTIME"]}
# Documented co-op substitutions as (Lua name -> delta against the mapped DLL count):
#   Distance(user, x) tests -> AnyPlayerWithin x8 (two 400 m discoveries, four 100 m stumbles, the
#   700 m nosey test, the 70 m relic test) and NoPlayerWithin x1 (the 400 m Colorado hold-off);
#   Attack(x, user) -> Attack(x, NearestPlayer(x)) x3;
#   CountUnitsNearObject x2 -> CountHumanUnits x2 (summed over every human team);
#   the native AddObject scan and AiMission startup are Start scaffolding outside the compared text.
COOP_DELTAS = {
    "Distance": -9, "AnyPlayerWithin": 8, "NoPlayerWithin": 1, "NearestPlayer": 3,
    "CountUnitsNearObject": -2, "CountHumanUnits": 2,
}
expected = Counter()
for function, count in cpp_calls.items():
    if function in cpp_only:
        continue
    expected[mapping.get(function, function)] += count
for name, delta in COOP_DELTAS.items():
    expected[name] += delta
mismatch = {name: (lua_calls[name], expected[name]) for name in set(expected) | set(lua_calls)
            if lua_calls[name] != expected[name]}
assert not mismatch, f"call counts changed (lua, expected): {mismatch}"

# Unused source state stays available alongside the cut blocks.
declarations = re.sub(cpp_comment, "", source.split("Misn08Mission::Misn08Mission", 1)[0], flags=re.S)
fields = []
for kind, sentinel in (("bool", "b"), ("float", "f"), ("Handle", "h"), ("int", "i")):
    section = re.search(r"\b" + kind + r"\s+([^;]*\b" + sentinel + r"_last)\s*;", declarations)
    if section is None:
        section = re.search(r"\b" + kind + r"\s*\n?\s*([^;]*\b" + sentinel + r"_last)\s*;", declarations)
    fields.extend(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", section[1])[:-1])  # identifiers only
for field in fields:
    assert re.search(r"^\s+" + field + r"\s*=", lua, flags=re.M) or re.search(r"\bM\." + field + r"\s*=", lua), \
        "source state omitted: " + field

assert not re.search(r'BuildObject\s*\("\w+",\s*2,', live), "CCA spawns must use ENEMY_TEAM"
assert "SetAIControl(ENEMY_TEAM, true)" in lua and "SetAIP(" in live and 'ENEMY_TEAM)' in live
assert "M.user" not in live.replace("M.user = GetPlayerHandle()", ""), "player-handle test left in the mission body"
print(f"Misn08 DLL parity: {sum(comments.values())} comments, {len(fields)} state fields, "
      f"{len(cpp_strings)} ordered string references, and source API call counts passed; "
      f"{sum(len(v) for v in region_text.values())} co-op regions stripped, {len(wavs)} region wavs have Text subtitles")
