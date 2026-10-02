#!/usr/bin/env python3
"""Audit authoritative source provenance, preserved comments, and mission IDs.

This complements the Lua host tests; it does not claim in-game qualification.
Run from any directory: python3 Tools/Test-Misn15SourceParity.py
"""
from collections import Counter
import hashlib
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "References" / "Misn15Source"
EXPECTED = {
    "Misn15Mission.cpp": "75974c4173246e540bf871eedc94cf09736989c8",
    "Misn15Mission.h": "055b9d92d1edf8c551fab6793bec6c94b88002a3",
}
for name, expected in EXPECTED.items():
    data = (ARCHIVE / name).read_bytes()
    actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    assert actual == expected, f"authoritative source changed: {name}: {actual}"

source = (ARCHIVE / "Misn15Mission.cpp").read_text()
lua = (ROOT / "Scripts" / "misn15.lua").read_text()
gameplay = source.split("void Misn15Mission::AddObject(Handle h)", 1)[1].split("IMPLEMENT_RTIME", 1)[0]

def normalized(text):
    return re.sub(r"\s+", " ", text).strip()

cpp_comments = Counter(normalized(body) for body in re.findall(r"/\*(.*?)\*/", gameplay, re.S))
lua_comments = Counter(normalized(body) for body in re.findall(r"--\[\[(.*?)\]\]", lua, re.S))
missing_comments = cpp_comments - lua_comments
assert not missing_comments, f"source block comments omitted or altered: {list(missing_comments)}"

cpp_without_blocks = re.sub(r"/\*.*?\*/", "", gameplay, flags=re.S)
for comment in re.findall(r"//([^\n]*)", cpp_without_blocks):
    assert normalized(comment) in normalized(lua), f"source line comment missing: {comment}"

def strip_cpp(text):
    return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", "", text, flags=re.S))

def strip_lua(text):
    return re.sub(r"--[^\n]*", "", re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S))

cpp_active = strip_cpp(gameplay)
lua_active = strip_lua(lua)
source_ids = set(re.findall(r'"([^"\n]*)"', cpp_active))
lua_ids = set(re.findall(r'"([^"\n]*)"', lua_active))
assert source_ids <= lua_ids, f"active source identifiers missing: {sorted(source_ids - lua_ids)}"

# Keep every initialized boolean, timer, and counter, including cut-content state.
decls = source.split("void Misn15Mission::Setup", 1)[0]
state_count = 0
for typename, group in re.findall(r"\b(bool|float|int)\s+(.*?);", decls, re.S):
    if "b_last" not in group and "f_last" not in group and "i_last" not in group:
        continue
    group = re.sub(r"//[^\n]*", "", group)
    for name in re.findall(r"\b[A-Za-z_]\w*\b", group):
        if name.endswith("_last"):
            continue
        assert re.search(r"\b" + re.escape(name) + r"\s*=", lua_active), f"mission state omitted: {name}"
        state_count += 1

assert not re.search(r"\bSetAIP\s*\(", lua_active), "disabled AIP was activated"
assert "rescue_cam2" not in lua_ids, "second rescue camera was activated"
assert "scav1here" not in lua_ids and "scav2here" not in lua_ids and "arthere" not in lua_ids, "second rescue spawns activated"
assert "waspmsl" not in lua_ids, "missile experiment activated"
assert "Get_Time(" not in lua_active, "native-only time spelling retained in Lua"
assert not re.search(r"\bObjectiveObjects\s*\(", lua_active), "broken stock iterator used"
assert not re.search(r"\bgoto\b|::[A-Za-z_]\w*::", lua_active), "Lua 5.2+ syntax used"

print(f"misn15 source parity: 2 exact source blobs, {sum(cpp_comments.values())} preserved block comments, "
      f"{len(source_ids)} active identifiers, {state_count} initialized state members")
