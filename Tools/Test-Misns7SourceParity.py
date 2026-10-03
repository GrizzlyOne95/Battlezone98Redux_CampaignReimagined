#!/usr/bin/env python3
"""Check source provenance, all comments/state, and ordered active statements."""
from collections import Counter
import hashlib
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "References/Misns7Source"
for name, expected in {
    "Misns7Mission.cpp": "5d930f36abba9a078ed16b09690553c6b02faa82",
    "Misns7Mission.h": "f5606b6c56a8bca4c07b6f30d9906b85e1b4af82",
}.items():
    data = (ARCHIVE / name).read_bytes()
    actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    assert actual == expected, (name, actual)

source = (ARCHIVE / "Misns7Mission.cpp").read_text()
lua = (ROOT / "Scripts/misns7.lua").read_text()
gameplay = source.split("void Misns7Mission::Setup(void)", 1)[1].split("IMPLEMENT_RTIME", 1)[0]
normalize = lambda s: " ".join(s.split())
blocks = Counter(normalize(s) for s in re.findall(r"/\*(.*?)\*/", gameplay, re.S))
lua_blocks = Counter(normalize(s) for s in re.findall(r"--\[\[(.*?)\]\]", lua, re.S))
assert not blocks - lua_blocks, f"missing block comments: {blocks - lua_blocks}"
cpp_no_blocks = re.sub(r"/\*.*?\*/", "", gameplay, flags=re.S)
comments = re.findall(r"//([^\n]*)", cpp_no_blocks)
for comment in comments:
    assert normalize(comment) in normalize(lua), f"missing source line comment: {comment}"

def strip_cpp(s):
    return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", "", s, flags=re.S))

def strip_lua(s):
    return re.sub(r"--[^\n]*", "", re.sub(r"--\[(=*)\[.*?\]\1\]", "", s, flags=re.S))

active = strip_lua(lua)
state = active.split("local function NewState()", 1)[1].split("local M = NewState()", 1)[0]
fields = set()
for group in re.findall(r"struct\s*\{\s*(?:bool|float|Handle|int)\s+(.*?);", source, re.S):
    fields.update(re.findall(r"\b\w+\b", group))
fields -= {"b_last", "f_last", "h_last", "i_last"}
assert fields == set(re.findall(r"\b(\w+)\s*=", state)), "missing or invented native state"

# Audit EVERY active assignment/call, in order per native gameplay method.
# Conditions are covered by mission scenarios, with two deliberate guard fixes.
def canonical(s):
    s = s.replace("M.", "").replace("Get_Time", "GetTime").replace("GetDistance", "Distance")
    s = re.sub(r"\bNULL\b", "nil", s)
    s = re.sub(r"\b(\d+(?:\.\d+)?)f\b", r"\1", s)
    s = s.replace("WHITE", '"white"').replace("GREEN", '"green"')
    s = s.replace("camera_off_supply = nil", "camera_off_supply = false")
    return re.sub(r"\s+", "", s).rstrip(";")

statement_count = 0
for cpp_method, lua_method, following in [
    ("Setup(void)", "local function Setup()", "function Start()"),
    ("AddObject(Handle h)", "function AddObject(h)", "function Update(dt)"),
    ("Execute(void)", "function Update(dt)", "function Save()"),
]:
    cpp = source.split("void Misns7Mission::" + cpp_method, 1)[1].split("\n}", 1)[0]
    # Execute contains column-zero inner blocks. Delimit by next method instead.
    if cpp_method == "Execute(void)":
        cpp = source.split("void Misns7Mission::Execute(void)", 1)[1].split("IMPLEMENT_RTIME", 1)[0]
    native = [canonical(s) for s in re.findall(r"^\s*(\w+\s*=\s*[^;]+;|[A-Z]\w*\s*\([^;]*\);)", strip_cpp(cpp), re.M)]
    port = active.split(lua_method, 1)[1].split(following, 1)[0]
    translated = [canonical(s) for s in re.findall(r"^\s*(M\.\w+\s*=\s*[^\n]+|[A-Z]\w*\s*\([^\n]*\))", port, re.M)]
    assert native == translated, f"active statements differ in {cpp_method}: " + str([(a,b) for a,b in zip(native,translated) if a != b][:5])
    statement_count += len(native)

assert "GameObjectHandle" not in active and "Get_Time" not in active
assert not re.search(r"\bObjectiveObjects\s*\(|\bgoto\b|::|\brequire\b", active)
assert '"power2_spot"' not in active and '"tower3_spot"' not in active, "cut base expansion activated"
assert '"geyser3"' in active and not re.search(r"Goto\s*\(M\.avmuf\s*,\s*M\.geyser3", active), "cut factory retreat activated"
reference = (ROOT / "Docs/BZR_LUA_AGENT_REFERENCE.md").read_text()
helpers = set(re.findall(r"local function\s+(\w+)", active))
for api in set(re.findall(r"\b([A-Z]\w*)\s*\(", active)) - helpers - {"Start", "AddObject", "Update", "Save", "Load"}:
    assert re.search(r"\b" + api + r"\s*\(", reference), f"non-stock API: {api}"
print(f"misns7 source parity: 2 exact blobs, {len(fields)} state fields, "
      f"{len(comments)} line comments, {sum(blocks.values())} block comments, "
      f"{statement_count} ordered active statements")
