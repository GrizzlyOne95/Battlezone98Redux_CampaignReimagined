#!/usr/bin/env python3
"""Audit DLL provenance, disabled code, state fields, and active source tokens."""
from collections import Counter
from hashlib import sha256
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
source_path = ROOT / "References/Misn18Source/Misn18Mission.cpp"
header_path = ROOT / "References/Misn18Source/Misn18Mission.h"
raw = source_path.read_bytes()
assert sha256(raw).hexdigest() == "19a999b8e06b445dcccf51ede5cb1312820daacb0dc457064feaee721baab538", "DLL source snapshot changed"
assert sha256(header_path.read_bytes()).hexdigest() == "ea2a4cbebe8853904bf463c41eb1c7f4b165084e74967026724cfd6cf5f0ba5c", "DLL header snapshot changed"
source = raw.decode("utf-8").replace("\r\n", "\n")
lua = (ROOT / "Scripts/misn18.lua").read_text(encoding="utf-8")
cpp_comment = r"//[^\n]*|/\*.*?\*/"
long_comment = r"--\[==\[(.*?)\]==\]"
setup = source.split("void Misn18Mission::Setup(void)", 1)[1].split("void Misn18Mission::Execute(void)", 1)[0]
execute = source.split("void Misn18Mission::Execute(void)", 1)[1].split("IMPLEMENT_RTIME", 1)[0]
comments = Counter(re.findall(cpp_comment, setup + execute, flags=re.S))
retained = "\n".join(re.findall(long_comment, lua, flags=re.S))
for comment, count in comments.items():
    assert retained.count(comment) >= count, "missing original comment: " + comment

live = re.sub(long_comment, "", lua, flags=re.S)
live = re.sub(r"--[^\n]*", "", live)
update = live.split("function Update(dt)", 1)[1].split("function Save()", 1)[0]
cpp = re.sub(cpp_comment, "", execute, flags=re.S)
# Native object-method calls become documented stock Lua wrappers. This checks
# every active token (conditions, numeric thresholds, commands, assignments and
# source order) after only those API/language adaptations, rather than testing
# a separately reimplemented mission state machine.
cpp = re.sub(r"GameObjectHandle\s*::\s*GetObj\((\w+)\)\s*->\s*(SetName|AddHealth)\s*\((.*?)\)",
             lambda m: ("SetObjectiveName" if m[2] == "SetName" else "AddHealth") +
             "(" + m[1] + "," + m[3] + ")", cpp)
cpp = re.sub(r"\bGetDistance\b", "Distance", cpp)
cpp = re.sub(r"\bWHITE\b", '"white"', cpp)
cpp = re.sub(r"\bGREEN\b", '"green"', cpp)
cpp = re.sub(r"(\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)f\b", r"\1", cpp)
cpp = cpp.replace("&&", " and ").replace("||", " or ")
cpp = re.sub(r"!(?!=)", " not ", cpp)
update = re.sub(r"\bM\.", "", update)
tokens = r'"(?:\\.|[^"\\])*"|[A-Za-z_]\w*|\d+(?:\.\d+)?|==|!=|<=|>=|[^\s]'
def active_tokens(text):
    return [token for token in re.findall(tokens, text) if token not in {"{", "}", ";", "then", "end"}]
def cpp_tokens(text):
    sequence = active_tokens(text)
    # Lua's `if condition then` replaces C++'s obligatory outer `if (condition)`.
    for index in range(len(sequence) - 1, -1, -1):
        if sequence[index] != "if":
            continue
        assert sequence[index + 1] == "("
        depth = 1
        closing = index + 2
        while depth:
            if sequence[closing] == "(": depth += 1
            elif sequence[closing] == ")": depth -= 1
            closing += 1
        del sequence[closing - 1]
        del sequence[index + 1]
    return sequence
assert cpp_tokens(cpp) == active_tokens(update), "active source logic/order changed"

declarations = re.sub(cpp_comment, "", source.split("void Misn18Mission::Setup", 1)[0], flags=re.S)
fields = []
for kind, sentinel in (("bool", "b"), ("float", "f"), ("Handle", "h"), ("int", "i")):
    section = re.search(r"\b" + kind + r"\s+([^;]*\b" + sentinel + r"_last)\s*;", declarations)[1]
    fields.extend(re.findall(r"\b\w+\b", section)[:-1])
for field in fields:
    assert re.search(r"\bstate\." + field + r"\s*=", lua), "source state omitted: " + field

# Setup assignments also retain their original order and values. Handle zero
# initializes to nil in Lua; the C++ loader's defaults are supplied by NewState.
cpp_setup = re.sub(cpp_comment, "", setup, flags=re.S)
cpp_setup = re.sub(r"(\d+(?:\.\d+)?)f\b", r"\1", cpp_setup)
lua_setup = live.split("function Start()", 1)[1].split("function Update(dt)", 1)[0]
lua_setup = re.sub(r"\bM = NewState\(\)", "", lua_setup)
lua_setup = re.sub(r"\bM\.", "", lua_setup).replace("nil", "0")
assert active_tokens(cpp_setup) == active_tokens(lua_setup), "Setup assignment sequence changed"

strings = r'"(?:\\.|[^"\\])*"'
print(f"Misn18 DLL parity: {sum(comments.values())} original mission comments, "
      f"{len(fields)} state fields, {len(re.findall(strings, cpp))} ordered string references, "
      f"and {len(cpp_tokens(cpp))} active logic tokens passed")
