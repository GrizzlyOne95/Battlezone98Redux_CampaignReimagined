#!/usr/bin/env python3
"""Prove Scripts/misns2cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/misns2.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/misns2.lua").read_bytes()
coop_raw = (ROOT / "Scripts/misns2cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "restored content", "co-op callback", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "misns2cr.lua outside the CR regions is not the faithful misns2.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is edited only by the callback hooks and the restored-content step call; the waves are scaled by the
# BuildObject shadow in the runtime region (one scaling event per frame and entry path), not by marks in the body.
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()"):
    assert callback in coop, callback
assert "BeginEvent" in coop and "scaledOdfs = SCALED_ODFS" in coop

# Every native the runtime region shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and (?:campaignRuntime\.\w+ or \1|function)", coop))
body = re.sub(r"--\[==\[.*?\]==\]", "", faithful_text, flags=re.S)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
natives = {"BuildObject", "IsValid", "IsAlive", "GetDistance", "GetNearestEnemy", "GetHandle", "GetTeamNum", "Goto", "Follow",
           "Attack", "SetIndependence", "Retreat", "AudioMessage", "StopAudioMessage", "CameraReady", "CameraPath",
           "CameraFinish", "CameraCancelled", "SetObjectiveName", "SetObjectiveOn", "ClearObjectives", "AddObjective",
           "RemoveObject", "SucceedMission", "FailMission"}
for name in natives:
    assert name in body_calls or name == "IsValid", "not a call of the body: " + name
    assert name in shadowed or name == "IsValid" and "IsValid" in shadowed, "the body calls it, the runtime region must shadow it: " + name
# Natives the runtime offers that this body does not call must not be wrapped (no SetScrap/SetAIP/CameraObject here).
for name in ("SetScrap", "SetAIP", "CameraObject", "Defend", "Defend2"):
    assert name not in body_calls and name not in shadowed, name
# The enemy's literal team 2 only ever reaches the engine through the runtime (BuildObject) or the platoon bypass.
assert len(re.findall(r'BuildObject\("\w+", 2, ', body)) == len(re.findall(r'BuildObject\(', body)), "all body builds are on team 2"
assert len(re.findall(r"GetTeamNum\(", body)) == len(re.findall(r"GetTeamNum\([^)]*\) == 1", body)) > 0, "the body only tests for team 1"
print("misns2cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
