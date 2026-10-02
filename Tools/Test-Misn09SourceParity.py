#!/usr/bin/env python3
"""Check the DLL provenance, retained comments/state, and authored call order."""
import hashlib
import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = 0


def check(value, message):
    global checks
    assert value, message
    checks += 1


for name, expected in {
    "Misn09Mission.cpp": "888ee877b4b56348ddf3e9717f01aed95fc0f066",
    "Misn09Mission.h": "924152c5233b7933506d19c2417e7cbff84ea7a0",
}.items():
    data = (ROOT / "References/Misn09Source" / name).read_bytes()
    actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    check(actual == expected, "verbatim source blob changed: " + name)

source = (ROOT / "References/Misn09Source/Misn09Mission.cpp").read_text()
lua = (ROOT / "Scripts/misn09.lua").read_text()
native_setup = source.split("void Misn09Mission::Setup(void)", 1)[1].split(
    "void Misn09Mission::AddObject(Handle h)", 1)[0]
native_update = source.split("void Misn09Mission::Execute(void)", 1)[1]
native_comments = re.findall(r"//[^\n]*|/\*[\s\S]*?\*/", native_setup + native_update)
for comment in native_comments:
    check(comment in lua, "original gameplay comment/cut code lost: " + comment[:100])

for kind, next_kind in [("bools", "floats"), ("floats", "handles"), ("handles", "integers"), ("integers", None)]:
    region = source.split("// " + kind, 1)[1]
    if next_kind:
        region = region.split("// " + next_kind, 1)[0]
    names = re.findall(r"\b\w+\b", region.split("struct {", 1)[1].split(";", 1)[0])[1:-1]
    for name in names:
        check(re.search(r"\bstate\." + name + r"\s*=", lua), "native state field lost: " + name)


def strip_cpp(text):
    return re.sub(r"//[^\n]*|/\*[\s\S]*?\*/", "", text)


def strip_lua(text):
    text = re.sub(r"--\[(=*)\[[\s\S]*?\]\1\]", "", text)
    return re.sub(r"--[^\n]*", "", text)


mapping = {"Get_Time": "GetTime", "GetDistance": "Distance", "SetName": "SetObjectiveName",
           "IsAudioMessageDone": "AudioDone", "StopAudioMessage": "StopAudio"}


def calls(text, native=False):
    # Compare authored API/local-wrapper call order. Native pointer casts and
    # object lookup for SetName/IsDeployed disappear in the stock Lua bindings.
    ignored = {"if", "and", "or", "not", "Factory", "GetObj", "NewState"}
    names = re.findall(r"\b([A-Za-z_]\w*)\s*\(", text)
    return [mapping.get(name, name) if native else name for name in names if name not in ignored]


active_lua = strip_lua(lua)
lua_setup = active_lua.split("function Start()", 1)[1].split("local trackedObjects", 1)[0]
lua_update = active_lua.split("function Update(dt)", 1)[1].split("function Save()", 1)[0]
check(calls(strip_cpp(native_setup), True) == calls(lua_setup), "Setup API call order differs from source")
# The documented fix adds exactly the invocation missing in the convoy guard.
native_calls = calls(strip_cpp(native_update).replace("(CameraCancelled)", "(CameraCancelled())"), True)
check(native_calls == calls(lua_update), "Execute API call order differs beyond the documented camera fix")

native_add = source.split("void Misn09Mission::AddObject(Handle h)", 1)[1].split(
    "void Misn09Mission::Execute(void)", 1)[0]
native_slots = re.findall(r'if\s*\(\((\w+)\s*==\s*NULL\)\s*&&\s*\(IsOdf\(h,"(\w+)"\)\)\)', native_add)
lua_slots = re.findall(r'\{"(\w+)",\s*"(\w+)"\}', lua.split("local trackedObjects =", 1)[1].split("function AddObject", 1)[0])
check(native_slots == lua_slots and len(lua_slots) == 16, "AddObject first-empty slot order differs")
check("SetAIControl" not in active_lua and "ObjectiveObjects" not in active_lua, "unsafe/unsupported API introduced")
check(len(re.findall(r"-- PORT FIX:", lua)) == 3, "expected three documented source fixes")

# The campaign validator must ignore preserved C++ in every Lua long-comment
# delimiter while still rejecting actual Lua 5.2 control flow after the comment.
spec = importlib.util.spec_from_file_location("campaign_validator", ROOT / "Tools/Validate-CampaignRepository.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
for equals in ["", "=", "=="]:
    text = "--[" + equals + "[\ngoto cut_content;\n]" + equals + "]\nGoto(unit, path)\ngoto live_label"
    code = validator.strip_lua_comments(text)
    check("cut_content" not in code and "Goto(unit, path)" in code and "goto live_label" in code,
          "validator misclassifies inactive C++ or loses live Lua syntax")
print(f"misn09: {checks} source preservation/parity checks passed")
