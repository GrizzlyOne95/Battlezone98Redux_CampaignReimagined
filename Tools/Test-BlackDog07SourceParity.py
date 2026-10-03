#!/usr/bin/env python3
"""Verify the complete source archive and mission's source-authored content."""
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
archive = ROOT / "References/BlackDog07Source/BlackDog07Mission.cpp"
raw = archive.read_bytes()
blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
assert blob == "35e2f6e94e88cd33a2c00e544da5600f46b7cc53", (
    "The original source, including all comments/cut content, must remain verbatim"
)
cpp = raw.decode()
lua = (ROOT / "Scripts/bdmisn07.lua").read_text()
active = re.sub(r"--[^\n]*", "", lua)
checks = 1

# Compare content-bearing literals (map labels, paths, assets, display names).
# Header includes and the native RTTI name have no Lua gameplay counterpart.
source_gameplay = cpp[cpp.index("void BlackDog07Mission::Setup()"):]
cpp_strings = set(re.findall(r'"([^"\r\n]*)"', source_gameplay))
lua_strings = set(re.findall(r'"([^"\r\n]*)"', active))
assert cpp_strings <= lua_strings, "Missing source literals: " + str(cpp_strings - lua_strings)
checks += len(cpp_strings)

# Explicit indices are intentional: nil slots must never truncate a list.
for array, total in [("mustSave", 3), ("mustDestroy", 11), ("waveUnits1", 3), ("waveUnits2", 8)]:
    expected = re.findall(rf'{array}\[(\d+)\] = GetHandle\("([^"]+)"\)', source_gameplay)
    actual = re.findall(rf'M\.{array}\[(\d+)\] = GetHandle\("([^"]+)"\)', active)
    assert len(expected) == total and actual == expected, f"{array} mapping differs"
    checks += total

# Every native persistent field is retained, including unused flags, audio
# userdata, and zero-based arrays. Native sentinel members are not game state.
for field in [
    "startDone", "objective1Complete", "objective2Complete", "objective3Complete",
    "wavesSpawned", "lost", "won", "sound1Time", "sound2Time", "sound3Time",
    "waveDelay", "annoyTime", "user", "mustDestroy", "mustSave", "waveUnits1",
    "waveUnits2", "sound1", "sound2", "sound3",
]:
    assert re.search(rf"\b{field}\b", lua), f"Missing persistent field {field}"
    checks += 1

# Every native Execute call remains active (SetName only occurs in Setup and
# becomes its documented stock alias). This is a complement to runtime tests,
# not a substitute for timer, resource, and objective-order checks.
execute = cpp[cpp.index("void BlackDog07Mission::Execute()"):].split("{", 1)[1]
functions = set(re.findall(r"\b([A-Z]\w*)\(", execute))
for function in functions - {"IsAlive", "GetHealth"}:
    assert re.search(rf"\b{function}\(", active), f"Missing source API {function}"
    checks += 1
assert "IsAlive(h)" in active and "GetHealth(h)" in active
assert "waveDelay[0] = now +" not in active, "Do not invent opening wave timing"
checks += 3
print(f"BlackDog07: {checks} source/archive parity checks passed.")
