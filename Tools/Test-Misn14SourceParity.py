#!/usr/bin/env python3
"""Audit preserved source bytes, native state, comments, and mission identifiers."""
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "References/Misn14Source"
checks = 0


def check(value, message):
    global checks
    assert value, message
    checks += 1


for name, sha in {
    "Misn14Mission.cpp": "77eeffab992d54a4c9a9d7825e1425d996a372db",
    "Misn14Mission.h": "08451d92c69746e6a6ba01fec0ea4efc9c58d791",
}.items():
    data = (ARCHIVE / name).read_bytes()
    blob_sha = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    check(blob_sha == sha, f"Original source bytes changed: {name}")

source = (ARCHIVE / "Misn14Mission.cpp").read_text()
lua = (ROOT / "Scripts/misn14.lua").read_text()
execute = source.split("void Misn14Mission::Execute(void)", 1)[1].split("IMPLEMENT_RTIME", 1)[0]
state = lua.split("local function NewState()", 1)[1].split("local M = NewState()", 1)[0]
native_fields = set()
for fields in re.findall(r"struct\s*\{\s*(?:bool|float|Handle|int)\s+(.*?);", source, re.S):
    native_fields.update(re.findall(r"\b[a-zA-Z_]\w*\b", fields))
native_fields -= {"b_last", "f_last", "h_last", "i_last"}
lua_fields = set(re.findall(r"\b(\w+)\s*=", state))
check(native_fields == lua_fields, f"State mismatch: {native_fields ^ lua_fields}")

# Execute has no strings containing comment delimiters, so this deliberately
# small scanner is sufficient for this pinned file rather than a general parser.
comments = re.findall(r"//([^\n]*)|/\*(.*?)\*/", execute, re.S)
normalize = lambda text: " ".join(text.split())
normalized_lua = normalize(lua)
for line, block in comments:
    text = normalize(line or block)
    check(text in normalized_lua, f"Missing original Execute comment/cut code: {text}")

identifiers = set(re.findall(r'"([^"\n]+)"', execute))
for identifier in identifiers:
    check(f'"{identifier}"' in lua, f"Missing source mission identifier: {identifier}")

active = re.sub(r"--\[(=*)\[.*?\]\1\]", "", lua, flags=re.S)
active = re.sub(r"--[^\n]*", "", active)
check('"misn1402.wav"' not in active, "Combined-briefing cut audio was enabled")
check(not re.search(r"AddPilot\s*\(\s*1\s*,\s*10\s*\)", active), "Cut pilot grant was enabled")
check("Get_Time" not in active and "GameObjectHandle" not in active, "Native-only API left active")
check("ObjectiveObjects" not in active, "Broken stock objective iterator used")
check(not re.search(r"\b(?:require|io|os|debug)\b", active), "External runtime dependency")
check(not re.search(r"\bgoto\b|::", active), "Lua 5.2+ syntax")
# Guard against accidentally using similarly named BZ2/project-only APIs.
reference = (ROOT / "Docs/BZR_LUA_AGENT_REFERENCE.md").read_text()
helpers = set(re.findall(r"local function\s+(\w+)", active))
callbacks = {"Start", "AddObject", "Update", "Save", "Load"}
for function in set(re.findall(r"\b([A-Z]\w*)\s*\(", active)) - helpers - callbacks:
    check(re.search(r"\b" + function + r"\s*\(", reference), f"API absent from stock BZR reference: {function}")
print(f"misn14 source parity: {checks} checks passed")
