#!/usr/bin/env python3
"""Audit BlackDog02 provenance, disabled code, state members and mission IDs.

Run: python3 Tools/Test-Bd02SourceParity.py
Complements Test-Bd02.lua; does not claim in-game qualification.
"""
from pathlib import Path
from collections import Counter
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]
raw = (ROOT / "References/BlackDog02Source/BlackDog02Mission.cpp").read_bytes()
blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
assert blob == "3d27e9760c7eb6d4a4f0adaf8c263552b66c3b23", f"source archive changed: {blob}"
source = raw.decode().replace("\r\n", "\n")
lua = (ROOT / "Scripts/bd02.lua").read_text()
gameplay = source.split("void BlackDog02Mission::AddObject(Handle h)", 1)[1]

def normalize(s):
    return re.sub(r"\s+", " ", s).strip()

for block in re.findall(r"/\*(.*?)\*/", gameplay, re.S):
    assert normalize(block) in normalize(lua), "cut-content block missing or changed"
without_blocks = re.sub(r"/\*.*?\*/", "", gameplay, flags=re.S)
for comment in re.findall(r"//([^\n]*)", without_blocks):
    assert normalize(comment) in normalize(lua), f"source line comment omitted: {comment}"

cpp_active = re.sub(r"//[^\n]*", "", without_blocks)
lua_active = re.sub(r"--[^\n]*", "", re.sub(r"--\[\[.*?\]\]", "", lua, flags=re.S))
source_ids = set(re.findall(r'"([^"\n]*)"', cpp_active))
lua_ids = set(re.findall(r'"([^"\n]*)"', lua_active))
assert source_ids <= lua_ids, f"source identifiers missing: {source_ids - lua_ids}"

# Wave/ambush composition must not silently change during translation.
cpp_spawns = Counter(re.findall(r'BuildObject\("([^"\n]*)",\s*(\d+),\s*"([^"\n]*)"\)', cpp_active))
lua_spawns = Counter(re.findall(r'BuildObject\("([^"\n]*)",\s*(\d+),\s*"([^"\n]*)"\)', lua_active))
assert cpp_spawns == lua_spawns, f"spawn definitions differ: {cpp_spawns - lua_spawns}; {lua_spawns - cpp_spawns}"
for name, number in re.findall(r"#define\s+(MS_\w+)\s+(\d+)", source):
    assert re.search(r"local\s+" + name + r"\s*=\s*" + number + r"\b", lua_active), f"state changed: {name}"
decls = source.split("IMPLEMENT_RTIME", 1)[0]
members = []
for typename, group in re.findall(r"\b(bool|float|int|Handle)\s+(.*?);", decls, re.S):
    if not any(x in group for x in ("b_last", "f_last", "i_last", "h_last")):
        continue
    group = re.sub(r"//[^\n]*", "", group)
    for member in re.findall(r"\b[A-Za-z_]\w*\b", group):
        if member.endswith("_last"):
            continue
        assert re.search(r"\b" + member + r"\s*=", lua_active), f"state member omitted: {member}"
        members.append(member)
assert len(members) == 33, f"unexpected member count: {members}"
for identifier in ("bvmuf", "path_bomber_attackpath", "bomber_scripted"):
    assert not re.search(r'\b' + identifier + r'\b', lua_active), f"disabled code activated: {identifier}"
assert not re.search(r"\b(Retreat|ObjectiveObjects|GameObjectHandle|SetAIControl)\s*\(", lua_active)
assert not re.search(r"\bgoto\b|::\w+::", lua_active), "Lua 5.2+ syntax used"
print(f"bd02 source parity: exact source blob, all gameplay comments, {len(source_ids)} active IDs, "
      f"{sum(cpp_spawns.values())} spawn definitions, {len(members)} state members")
