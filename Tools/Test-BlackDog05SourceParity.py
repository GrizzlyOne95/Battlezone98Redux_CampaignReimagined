#!/usr/bin/env python3
"""Check the exact source archive and source-derived BlackDog05 port data."""
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
raw = (ROOT / "References/BlackDog05Source/BlackDog05Mission.cpp").read_bytes()
blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
assert blob == "4446a98596a903f1f7764a0a65ff909645913061", "native source archive changed"
source = raw.decode().replace("\r\n", "\n")
lua = (ROOT / "Scripts/bd05.lua").read_text()

# Both disabled blocks are present inside Lua long comments, not live code.
native_cut = re.findall(r"#if 0\n.*?#endif", source, re.S)
lua_comments = re.findall(r"--\[==\[(.*?)\]==\]", lua, re.S)
assert len(native_cut) == len(lua_comments) == 2
for original, retained in zip(native_cut, lua_comments):
    assert original.split() == retained.split(), "disabled source code lost or altered"
active = re.sub(r"--\[==\[.*?\]==\]", "", lua, flags=re.S)
active = re.sub(r"--[^\n]*", "", active)

# The SpawnUnit abstraction must preserve every original index, ODF, path,
# cloak call and command; ordered comparison catches reordered Execute blocks.
pattern = (r'units\[(\d+)\] = BuildObject\("([^"]+)", 2, "([^"]+)"\);\s*'
           r'SetCloaked\(units\[\1\]\);\s*'
           r'(Goto|Attack)\(units\[\1\], recycler, 1\);')
native_waves = re.findall(pattern, source)
lua_waves = re.findall(r'SpawnUnit\((\d+), "([^"]+)", "([^"]+)", (Goto|Attack)\)', active)
assert len(native_waves) == 31 and native_waves == lua_waves, "reinforcement parity failed"
assert sorted(int(w[0]) for w in lua_waves) == list(range(15, 46))

for field in ["waitTime[0]", "waitTime[1]", "waitTime[2]", "waitTime[3]", "waitTime[4]",
              "howitzerTime", "rearAttackTime1", "rearAttackTime2"]:
    native_time = re.search(re.escape(field) + r" = GetTime\(\) \+ ([\d.]+)", source)
    lua_time = re.search(r"M\." + re.escape(field) + r" = GetTime\(\) \+ ([\d.]+)", active)
    assert native_time and lua_time and float(native_time[1]) == float(lua_time[1]), field

native_quitters = re.findall(r'quitters\[(\d+)\] = BuildObject\("([^"]+)", 2, "quitters"\)', source)
lua_quitters = re.findall(r'M\.quitters\[(\d+)\] = BuildObject\("([^"]+)", 2, "quitters"\)', active)
assert len(native_quitters) == 6 and native_quitters == lua_quitters
native_labels = re.findall(r'units\[(\d+)\] = GetHandle\("unit_(\d+)"\)', source)
assert native_labels == [(str(i), str(i + 1)) for i in range(15)]
assert 'for i = 0, 14 do M.units[i] = GetHandle("unit_" .. (i + 1)) end' in active
assert "for i = 0, 45 do" in active and "for i = 0, 5 do" in active

# No voiced line, objective, success descriptor or camera parameter is lost.
for asset in set(re.findall(r'"([^"]+\.(?:wav|otf|des))"', source)):
    assert '"' + asset + '"' in lua, asset
for camera in re.findall(r'CameraPath\("([^"]+)", (\d+), (\d+), (\w+)\)', source):
    path, height, speed, target = camera
    assert f'CameraPath("{path}", {height}, {speed}, M.{target})' in active

# Retain every non-sentinel native field, including unused cut-content state.
members = ["startDone", "lost", "won", "objective1Complete", "objective2Complete",
           "cameraReady", "cameraComplete", "waitsInitialized", "waitOver",
           "quittersSpawned", "quitterMovieDone", "waitTime", "rearAttackTime1",
           "rearAttackTime2", "howitzerTime", "quitterDelay", "bomberTime",
           "portalTime", "quitterCamTime", "user", "recycler", "portal", "units",
           "quitters", "numBombers", "whichTimer", "portalStage", "quitterSound",
           "introSound", "sound6"]
for member in members:
    assert re.search(r"\b" + member + r"\b", active), member
assert "StartCockpitTimer(" not in active and "StopCockpitTimer(" not in active
assert "FailMission(" not in active, "source has no active scripted loss condition"
assert "PortalIn(M.portal)" in active and "IsTouching(h, M.portal)" in active
print("BlackDog05 source parity: exact archive, both cut blocks, waves, timers, assets, cameras and state passed")
