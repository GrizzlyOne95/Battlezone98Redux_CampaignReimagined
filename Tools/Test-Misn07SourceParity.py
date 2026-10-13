#!/usr/bin/env python3
"""Verify DLL provenance, inactive-code retention, and ordered asset references for misn07.

The co-op layer, the restored test-range arc, the rendezvous convoy and Razor One's
infiltration live between exact marker lines. They are stripped (inclusive) so every
check below still proves the active DLL port is unchanged; each co-op substitution
outside the markers is an explicit API-count delta.
"""
from collections import Counter
from hashlib import sha256
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
source_path = ROOT / "References/Misn07Source/Misn07Mission.cpp"
lua_path = ROOT / "Scripts/misn07.lua"
raw = source_path.read_bytes()
# Pinned on LF-normalized bytes so the check is independent of checkout line endings.
assert sha256(raw.replace(b"\r\n", b"\n")).hexdigest() == "2179500357224761cd5588025e0aa26ca1fdb8e715c0b6a8fde8999dabe21846", "DLL source snapshot changed"
source = raw.decode("utf-8").replace("\r\n", "\n")
lua = lua_path.read_text(encoding="utf-8").replace("\r\n", "\n")

REGIONS = ("CR restored VO", "CR Razor One infiltration", "CR rendezvous convoy")
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
for token in ("RESTORED_VO", "CUT_VO", "RENDEZVOUS_CONVOY", "RAZOR_ONE", "SpawnConvoy", "UpdateConvoy",
              "UpdateRazorOne", "RazorOne", "RestoredTestRange", "RestoredMineField", "RestoredMagCannon",
              "utah_nag", "mine_ok", "cine_player", "M.rk", "M.convoy", "PROTO_", "Prototype", "M.proto", "TestRangeOpen", "BeginTestRangeTrip", "razor_unit"):
    assert token not in lua, "region code outside marker regions: " + token

# Restored voice lines need their shipped subtitle text (never invent text); 0711 and 0717 stay cut.
restored = "\n".join(l for region in region_text["CR restored VO"] for l in region)
cut_table = re.search(r"local CUT_VO = \{(.*?)\n\}", restored, flags=re.S)
assert cut_table, "CUT_VO table missing from restored region"
cut_wavs = sorted(set(re.findall(r'"(misn07\d\d)\.wav"', cut_table[1])))
assert cut_wavs == ["misn0703", "misn0704", "misn0719"], cut_wavs
missing_text = [w for w in cut_wavs if not (ROOT / "Text" / (w + ".txt")).is_file()]
assert not missing_text, "restored VO without Text subtitle: " + ", ".join(missing_text)
for wav in re.findall(r'"(misn07\d\d)\.wav"', restored):
    assert wav in cut_wavs, "restored wav missing from CUT_VO: " + wav
assert "misn0711" not in restored and "misn0717" not in restored, "dev joke / duplicate line restored"

# Disabled C++ blocks stay in Lua comments; // comments are kept as -- comments.
cpp_comment = r"//[^\n]*|/\*.*?\*/"
# Declaration and serialization comments stay in References/Misn07Source; the Lua keeps
# every comment from the gameplay routines (Setup, AddObject, Execute).
gameplay = "void Misn07Mission::Setup(void)" + source.split("void Misn07Mission::Setup(void)", 1)[1]
comments = Counter(m[0] for m in re.finditer(cpp_comment, gameplay, flags=re.S))
lua_block_comments = "\n".join(re.findall(r"--\[=*\[(.*?)\]=*\]", lua, flags=re.S))
lua_plain = re.sub(r"\s+", " ", re.sub(r"--\[=*\[.*?\]=*\]", " ", lua, flags=re.S))
def squash(text):
    return re.sub(r"\s+", " ", text).strip()
missing = []
for comment, count in comments.items():
    if comment.startswith("/*"):
        if lua_block_comments.count(comment) < count and squash(comment) not in squash(lua_block_comments):
            missing.append(comment)
    else:
        body = squash(comment[2:])
        if body and body not in lua_plain and body not in squash(lua_block_comments):
            missing.append(comment)
assert not missing, "missing original comments: " + repr(missing[:5])

# Active code: Setup + AddObject + Execute against Start + Execute body.
cpp = re.sub(cpp_comment, "", source, flags=re.S)
cpp = cpp.split("void Misn07Mission::Setup(void)", 1)[1]
cpp = re.sub(r"\bvoid Misn07Mission::\w+\([^)]*\)", "", cpp)
assert "-- Misn07Mission::Execute body" in lua, "Execute-body marker missing"
start = lua.split("function Start()", 1)[1].split("function AddObject", 1)[0]
execute = lua.split("-- Misn07Mission::Execute body", 1)[1].split("function Save()", 1)[0]
live = re.sub(r"--\[=*\[.*?\]=*\]", "", start + "\n" + execute, flags=re.S)
live = re.sub(r"--[^\n]*", "", live)
strings = r'"(?:\\.|[^"\\])*"'
cpp_strings = re.findall(strings, cpp)
cpp_text = re.sub(r"\bWHITE\b", '"white"', re.sub(r"\bGREEN\b", '"green"', cpp))
cpp_text = re.sub(r"\bRED\b", '"red"', cpp_text)
cpp_strings = [s.replace("%0.3d", "%03d") for s in re.findall(strings, cpp_text)]  # C printf -> Lua format
lua_strings = re.findall(strings, live)
# Native path lookups (AiPath::Find) and the format-string loop keep the same names.
assert cpp_strings == [s for s in lua_strings], "active source asset/label sequence changed"

live_calls = re.sub(r"\bfunction\s+\w*\s*\([^)]*\)", "", live)
cpp_calls = Counter(re.findall(r"\b([A-Z]\w*)\s*\(", cpp))
lua_calls = Counter(re.findall(r"\b([A-Z]\w*)\s*\(", live_calls))
# A dialogue block plays its first line and queues the rest; misn07 has only single lines.
lua_calls["Play"] += lua_calls.pop("Queue", 0)
mapping = {"Get_Time": "GetTime", "GetDistance": "Distance", "AudioMessage": "Play",
           "SetName": "SetObjectiveName", "IsOdf": "IsOdfBase"}
# C++-only constructs with no Lua call: native object lookups, AiPath::Find, and the
# AliveButDamaged helper (defined above Start in Lua, so its body is outside the compared text).
cpp_only = {"GetObj": 8, "Find": 2}
# One GetHealth and the AliveButDamaged definition sit in the helper, which Lua keeps above Start.
cpp_calls["GetHealth"] -= 1
cpp_calls["AliveButDamaged"] -= 1
# Documented co-op substitutions as (Lua name -> delta against the mapped DLL count):
#   Distance(user, x) < d -> AnyPlayerWithin x9 (wingtank2/3, nav1, rookie, comtower, 4 runners)
#   and NoPlayerWithin x1 (jump geyser), i.e. -10 Distance; the tank tripwire and camera-geyser
#   infiltration keep their Distance call inside a per-player closure (PlayerKey x3 with the
#   stolen latch; ForEachPlayerHandle x3 = infiltration, stolen latch, units sum; AnyPlayerSatisfies x1
#   = the tripwire; AllInfiltratorsStolen x1 replaces vehicle_stolen's latch);
#   Attack(x, user) -> Attack(x, NearestPlayer(x)) x7; parkturret ~= user -> IsAnyPlayer x2;
#   IsOdf(user, ...) x3 and CountUnitsNearObject x1 keep their calls inside per-player closures.
COOP_DELTAS = {
    "Distance": -10, "AnyPlayerWithin": 9, "NoPlayerWithin": 1, "NearestPlayer": 7, "IsAnyPlayer": 2,
    "PlayerKey": 3, "AllInfiltratorsStolen": 1, "ForEachPlayerHandle": 3, "AnyPlayerSatisfies": 1,
    # Start scaffolding: shared co-op initialization and the native NewState reset.
    "InitializeCoop": 1, "NewState": 1, "Initialize": 1,
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
declarations = re.sub(cpp_comment, "", source.split("Misn07Mission::Misn07Mission", 1)[0], flags=re.S)
fields = []
for kind, sentinel in (("bool", "b"), ("float", "f"), ("Handle", "h"), ("int", "i")):
    section = re.search(r"\b" + kind + r"\s+([^;]*\b" + sentinel + r"_last)\s*;", declarations)
    if section is None:
        section = re.search(r"\b" + kind + r"\s*\n?\s*([^;]*\b" + sentinel + r"_last)\s*;", declarations)
    fields.extend(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", section[1])[:-1])  # identifiers only
for field in fields:
    key = "endtime" if field == "end" else field
    assert re.search(r"\bstate\." + key + r"\s*=", lua) or re.search(r"\bM\." + key + r"\s*=", lua), \
        "source state omitted: " + field

assert not re.search(r'BuildObject\("\w+",\s*[23],', live), "CCA/platoon spawns must use ENEMY_TEAM/SUPPORT_TEAM"
assert "M.user" not in live.replace("M.user=GetPlayerHandle()", ""), "player-handle test left in the mission body"
print(f"Misn07 DLL parity: {sum(comments.values())} comments, {len(fields)} state fields, "
      f"{len(cpp_strings)} ordered string references, and source API call counts passed; "
      f"{sum(len(v) for v in region_text.values())} co-op regions stripped, {len(cut_wavs)} restored wavs have Text subtitles")
