#!/usr/bin/env python3
"""Audit the pinned native source, all state/comments, IDs, and stock Lua APIs."""
import hashlib
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "References/Misns3Source"
checks = 0


def check(value, message):
    global checks
    assert value, message
    checks += 1


for name, expected in {
    "Misns3Mission.cpp": "2805325b14fcd9273f0bd03eb36f0be17b755527",
    "Misns3Mission.h": "394be44569d47ed3b5a4333d87ce6d18d912564a",
}.items():
    data = (ARCHIVE / name).read_bytes()
    actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    check(actual == expected, f"Source bytes changed: {name}")

source = (ARCHIVE / "Misns3Mission.cpp").read_text()
lua = (ROOT / "Scripts/misns3.lua").read_text()
gameplay = source.split("void Misns3Mission::Setup", 1)[1].split("IMPLEMENT_RTIME", 1)[0]
active = re.sub(r"--\[(=*)\[.*?\]\1\]", "", lua, flags=re.S)
active = re.sub(r"--[^\n]*", "", active)
state = active.split("local function NewState()", 1)[1].split("local M = NewState()", 1)[0]
native_fields = set()
for group in re.findall(r"struct\s*\{\s*(?:bool|float|Handle|int)\s+(.*?);", source, re.S):
    native_fields.update(re.findall(r"\b[A-Za-z_]\w*\b", group))
native_fields -= {"b_last", "f_last", "h_last", "i_last"}
lua_fields = set(re.findall(r"\b(\w+)\s*=", state)) - {"state"}
check(native_fields == lua_fields, f"State mismatch: {native_fields ^ lua_fields}")

normalized_lua = " ".join(lua.split())
for comment in re.findall(r"/\*(.*?)\*/", source.split("IMPLEMENT_RTIME", 1)[0], re.S):
    check(" ".join(comment.split()) in normalized_lua, f"Missing source block comment: {comment}")
for comment in re.findall(r"//([^\n]*)", gameplay):
    check(" ".join(comment.split()) in normalized_lua, f"Missing gameplay line comment: {comment}")

# Mine paths are compacted into three exact numeric loops. Check their expanded
# identifiers and order separately rather than requiring 34 duplicated literals.
source_ids = set(re.findall(r'"([^"\n]+)"', gameplay))
lua_ids = set(re.findall(r'"([^"\n]+)"', active))
mine_ranges = [(int(a), int(b)) for a, b in re.findall(
    r'for index = (\d+), (\d+) do BuildObject\("proxmine", 2, "path_" \.\. index\) end', active)]
check(mine_ranges == [(1, 11), (12, 22), (23, 34)], "Mine ranges/order changed")
lua_ids.update(f"path_{i}" for a, b in mine_ranges for i in range(a, b + 1))
check(source_ids <= lua_ids, f"Missing active identifiers: {sorted(source_ids - lua_ids)}")

reference = (ROOT / "Docs/BZR_LUA_AGENT_REFERENCE.md").read_text()
helpers = set(re.findall(r"local function\s+(\w+)", active))
callbacks = {"Start", "AddObject", "Update", "Save", "Load"}
for name in sorted(set(re.findall(r"\b([A-Z]\w*)\s*\(", active)) - helpers - callbacks):
    check(re.search(r"\b" + name + r"\s*\(", reference), f"API absent from BZR stock reference: {name}")
check(not re.search(r"\bgoto\b|::", active), "Lua 5.2/native syntax")
check(not re.search(r"\b(?:require|io|os|debug|ObjectiveObjects)\b", active), "External dependency or broken iterator")
for timer, offset in (("Checkdist", 5), ("Checkdist2", 5), ("Checkalive", 15),
                      ("Checkdist", 3), ("Checkdist2", 3), ("Checkalive", 8)):
    check(f"M.{timer} = math.floor(GetTime() + {offset}.0)" in active, "Lost integer deadline truncation")
print(f"misns3 source parity: {checks} checks passed; {len(native_fields)} native fields; "
      f"{len(source_ids)} active identifiers; exact original source blobs")
