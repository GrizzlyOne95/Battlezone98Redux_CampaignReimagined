#!/usr/bin/env python3
"""Check exact DLL source, preserved disabled code/comments, and mission IDs."""
from collections import Counter
import hashlib
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "References/Misns5Source"
for name, expected in {
    "Misns5Mission.cpp": "27a86be1800531bf576a211acb4fdd356458260e",
    "Misns5Mission.h": "314b3e0c57b6e561a4d512b3225fffb86b3b6d59",
}.items():
    data = (ARCHIVE / name).read_bytes()
    actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    assert actual == expected, (name, actual)

source = (ARCHIVE / "Misns5Mission.cpp").read_text()
lua = (ROOT / "Scripts/misns5.lua").read_text()
gameplay = source.split("void Misns5Mission::AddObject(Handle h)", 1)[1].split("IMPLEMENT_RTIME", 1)[0]

def normalized(text):
    return re.sub(r"\s+", " ", text).strip()

cpp_comments = Counter(normalized(x) for x in re.findall(r"/\*(.*?)\*/", gameplay, re.S))
lua_comments = Counter(normalized(x) for x in re.findall(r"--\[\[(.*?)\]\]", lua, re.S))
assert not cpp_comments - lua_comments, cpp_comments - lua_comments
cpp_no_blocks = re.sub(r"/\*.*?\*/", "", gameplay, flags=re.S)
for comment in re.findall(r"//([^\n]*)", cpp_no_blocks):
    assert normalized(comment) in normalized(lua), comment
cpp_active = re.sub(r"//[^\n]*", "", cpp_no_blocks)
lua_active = re.sub(r"--[^\n]*", "", re.sub(r"--\[\[.*?\]\]", "", lua, flags=re.S))
source_ids = set(re.findall(r'"([^"\n]*)"', cpp_active))
lua_ids = set(re.findall(r'"([^"\n]*)"', lua_active))
assert source_ids <= lua_ids, source_ids - lua_ids
for typename, group in re.findall(r"\b(bool|float|int)\s+(.*?);", source.split("void Misns5Mission::Setup", 1)[0], re.S):
    if not re.search(r"[bfi]_last", group):
        continue
    for name in re.findall(r"\b[A-Za-z_]\w*\b", group):
        if not name.endswith("_last"):
            assert re.search(r"\b" + name + r"\s*=", lua_active), name
assert '"avtank"' not in lua_ids, "cut defender activated"
assert lua_active.count('BuildObject("avrecy"') == 1, "cut second recycler activated"
assert not re.search(r"\bgoto\b|::\w+::|\bObjectiveObjects\s*\(", lua_active)
print(f"misns5 source parity: 2 exact blobs, {sum(cpp_comments.values())} block comments, {len(source_ids)} active IDs")
