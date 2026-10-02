#!/usr/bin/env python3
"""Verify source provenance, complete cut-code retention, state, and asset names."""
import hashlib
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = 0


def check(value, message):
    global checks
    assert value, message
    checks += 1


for name, expected in {
    "Misn10Mission.cpp": "1e000fdc8e95fa7c58009b249031bb420c789980",
    "Misn10Mission.h": "794f56e6cb3b85c0d7877d42bebfd9c98293124b",
}.items():
    raw = (ROOT / "References/Misn10Source" / name).read_bytes()
    blob = b"blob " + str(len(raw)).encode() + b"\0" + raw
    check(hashlib.sha1(blob).hexdigest() == expected, f"verbatim source changed: {name}")

source = (ROOT / "References/Misn10Source/Misn10Mission.cpp").read_text()
lua = (ROOT / "Scripts/misn10.lua").read_text()
gameplay = source[source.index("void Misn10Mission::Setup(void)"):]

# Comments may contain nested // lines, so tokenize in lexical order.
tokens = re.findall(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*', gameplay, re.S)
blocks = [token for token in tokens if token.startswith("/*")]
disabled_lines = [token for token in tokens if token.startswith("//")
                  and re.search(r";|\bif\s*\(|^//\s*[{}]", token)]
for comment in blocks + disabled_lines:
    check(comment in lua, "missing verbatim gameplay comment: " + comment[:80])

state_fields = []
for kind, first, last, expected_count in [
    ("bool", "start_done", "b_last", 66),
    ("float", "gech_warning_message", "f_last", 13),
    ("Handle", "user", "h_last", 31),
    ("int", "audmsg", "i_last", 1),
]:
    declaration = re.search(r"\b" + kind + r"\s+" + first + r"\b(.*?)\b" + last, source, re.S)[1]
    declaration = first + re.sub(r"//[^\n]*|/\*.*?\*/", "", declaration, flags=re.S)
    names = re.findall(r"\b\w+\b", declaration)
    check(len(names) == expected_count, "source state count: " + kind)
    state_fields.extend(names)
lua_fields = re.findall(r"\bstate\.(\w+)\s*=", lua)
check(Counter(lua_fields) == Counter(state_fields), "all 111 native state fields must be retained exactly once")


def cpp_active(text):
    return re.sub(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*',
                  lambda m: m[0] if m[0].startswith('"') else "", text, flags=re.S)


def lua_active(text):
    # Preserve string literals when stripping either form of Lua comment.
    return re.sub(r'"(?:\\.|[^"\\])*"|--\[(=*)\[.*?\]\1\]|--[^\n]*',
                  lambda m: m[0] if m[0].startswith('"') else "", text, flags=re.S)


native_literals = Counter(re.findall(r'"((?:\\.|[^"\\])*)"', cpp_active(gameplay)))
lua_literals = Counter(re.findall(r'"((?:\\.|[^"\\])*)"', lua_active(lua)))
check(not (native_literals - lua_literals), "active native labels, paths, names, and files must all survive")
check(not re.search(r"\b(Get_Time|GameObjectHandle|NULL|WHITE)\b", lua_active(lua)), "native-only syntax in Lua")
print(f"misn10 source parity: {checks} checks passed; {len(blocks)} block comments and "
      f"{len(disabled_lines)} disabled lines retained; 111 state fields")
