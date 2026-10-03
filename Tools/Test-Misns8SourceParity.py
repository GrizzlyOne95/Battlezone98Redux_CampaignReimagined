#!/usr/bin/env python3
"""Audit source preservation and active call/asset coverage independently of Lua mocks."""
from collections import Counter
import hashlib
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "References/Misns8Source/Misns8Mission.cpp"
HEADER = ROOT / "References/Misns8Source/Misns8Mission.h"
PORT = ROOT / "Scripts/misns8.lua"


def strip_cpp(text):
    # Like C++, a block comment ends at the FIRST */; nested /* is inert text.
    # Strings are tokens too, so // inside a quoted literal is never a comment.
    return re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',
                  lambda m: "" if m[0].startswith(("//", "/*")) else m[0],
                  text, flags=re.S)


def strip_lua(text):
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", "", text, flags=re.S)
    return re.sub(r'"(?:\\.|[^"\\])*"|--[^\n]*',
                  lambda m: "" if m[0].startswith("--") else m[0], text)


def calls(text):
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    return Counter(re.findall(r"\b([A-Za-z_]\w*)\s*\(", text))


def literals(text):
    return Counter(re.findall(r'"((?:\\.|[^"\\])*)"', text))


def run():
    for file, expected in [(SOURCE, "9d5dfd561387e867bcbfc973573087616bca2cbe"),
                           (HEADER, "7d8863fc2abc6bc4176fb64d526eeb01dd13baa7")]:
        data = file.read_bytes()
        actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        assert actual == expected, (file, "archived source blob changed", actual)
    source, port = SOURCE.read_text(), PORT.read_text()
    execute_raw = source.split("void Misns8Mission::Execute(void)", 1)[1]
    execute = strip_cpp(execute_raw)
    update = strip_lua(port.split("function Update(dt)", 1)[1].split("function Save()", 1)[0])
    # All active mission asset names and paths must appear actively, with the
    # same count. Merely archiving an omitted mission branch cannot pass this.
    native_literals, lua_literals = literals(execute), literals(update)
    assert lua_literals.pop("white", 0) == len(re.findall(r"\bWHITE\b", execute)), "objective colors differ"
    assert native_literals == lua_literals, "active Update literal coverage differs"
    source_calls, port_calls = calls(execute), calls(update)
    mapping = {"Get_Time": "GetTime", "GetDistance": "Distance",
               "SetName": "SetObjectiveName", "GetWhoTheHellShotMe": "GetWhoShotMe"}
    for old, new in mapping.items():
        source_calls[new] += source_calls.pop(old, 0)
    for internal in ("if", "GetObj"):
        source_calls.pop(internal, None)
    for internal in ("if", "Update", "floor", "and", "or", "not"):
        port_calls.pop(internal, None)
    assert source_calls == port_calls, ("active Update call coverage differs", source_calls - port_calls, port_calls - source_calls)
    # Compare the ordered active state writes. Known bug fixes change tests,
    # not assignment order or mission actions.
    writes = re.findall(r"\b(\w+)\s*=(?!=)", execute)
    port_writes = re.findall(r"\bM\.(\w+)\s*=(?!=)", update)
    writes = [name for name in writes if name not in ("test", "shot_by")]
    assert writes == port_writes, "active state writes were dropped or reordered"
    # Every C block in Execute, including inline disabled condition fragments,
    # remains verbatim in a Lua long comment. Line comments remain in order.
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', execute_raw, re.S)
    comments = [token for token in tokens if token.startswith(("/*", "//"))]
    cursor = 0
    for comment in comments:
        retained = comment if comment.startswith("/*") else "--" + comment[2:]
        position = port.find(retained, cursor)
        assert position >= 0, ("missing/reordered source comment", comment[:100])
        cursor = position + len(retained)
    # Check the order of all ODF registration slots, which drives construction.
    add_source = strip_cpp(source.split("void Misns8Mission::AddObject(Handle h)", 1)[1].split("void Misns8Mission::Execute", 1)[0])
    add_port = strip_lua(port.split("function AddObject(h)", 1)[1].split("function Update", 1)[0])
    native_slots = re.findall(r'\((\w+) == NULL\)\s*&&\s*\(IsOdf\(h,"([^"]+)"\)', add_source)
    lua_slots = re.findall(r'M\.(\w+) == nil and IsOdf\(h, "([^"]+)"\)', add_port)
    assert native_slots == lua_slots and len(lua_slots) == 34, "AddObject slot priority differs"
    print("PASS: exact source blobs, active literals/calls/state-write order, all Execute comments, 34 object slots")


if __name__ == "__main__":
    run()
