#!/usr/bin/env python3
"""Pin the DLL source and verify source fields, comments, and active assets."""
from collections import Counter
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "References/Misn16Source/Misn16Mission.cpp"
HEADER = ROOT / "References/Misn16Source/Misn16Mission.h"
PORT = ROOT / "Scripts/misn16.lua"
checks = 0


def check(condition, message):
    global checks
    checks += 1
    assert condition, message


def git_blob(data):
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


check(git_blob(SOURCE.read_bytes()) == "0b6305ff8ec4f218556c4fe1504e7329177e3e48",
      "DLL source snapshot differs from upstream blob")
check(git_blob(HEADER.read_bytes()) == "54fe03a6d9e7e8fb5178801a486512b52350d5e4",
      "DLL header snapshot differs from upstream blob")
source = SOURCE.read_text()
port = PORT.read_text()
comments = re.findall(r"/\*.*?\*/|//[^\n]*", source, re.S)
for index, comment in enumerate(comments, 1):
    check(comment in port, f"Missing or modified source comment {index}: {comment}")

cpp_live = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
lua_live = re.sub(r"--\[(=*)\[.*?\]\1\]", "", port, flags=re.S)
lua_live = re.sub(r"--[^\n]*", "", lua_live)
decl = cpp_live[cpp_live.index("private:"):cpp_live.index("void Misn16Mission::Setup")]
fields = []
for names in re.findall(r"struct\s*\{\s*(?:bool|float|Handle|int)\s+([^;]+);", decl):
    fields.extend(n.strip() for n in names.split(",") if not n.strip().endswith("_last"))
check(len(fields) == 38, f"Unexpected source field count: {len(fields)}")
for name in fields:
    check(re.search(r"\b" + re.escape(name) + r"\s*=", lua_live) is not None,
          f"Source state field omitted: {name}")

# Compare occurrence counts, not just membership: this catches missing duplicate
# type-5 radio, reinforcement locations, SAT routes, and counterattack spawns.
behavior = cpp_live[cpp_live.index("void Misn16Mission::Setup"):cpp_live.index("IMPLEMENT_RTIME")]
source_assets = Counter(re.findall(r'"([^"\n]+)"', behavior))
lua_assets = Counter(re.findall(r'"([^"\n]+)"', lua_live))
# WHITE is a native enum; the stock Lua objective API accepts its color name.
lua_assets["white"] -= 1
lua_assets += Counter()  # remove the resulting zero-count entry
check(lua_assets == source_assets,
      f"Active literal mismatch; missing={source_assets - lua_assets}, "
      f"extra={lua_assets - source_assets}")
check(len([c for c in comments if re.search(r"\b(BuildObject|Attack|AudioMessage)\(", c)]) == 7,
      "Unexpected disabled-content inventory")
for name in ("reinforce24", "reinforce14", "misn1614.wav"):
    check(name not in lua_live, f"Cut content accidentally activated: {name}")
check("ObjectiveObjects(" not in lua_live, "Uses broken stock objective iterator")
check("SetAIControl(" not in lua_live, "Introduces strategic-AI timing mutation")
check("math.randomseed(" not in lua_live, "Re-seeds the shared random generator")
check("goto " not in lua_live and "::" not in lua_live, "Contains Lua 5.2+ syntax")
print(f"misn16: {checks} source checks passed ({len(fields)} fields, {len(comments)} comments, "
      f"{sum(source_assets.values())} active literal references)")
