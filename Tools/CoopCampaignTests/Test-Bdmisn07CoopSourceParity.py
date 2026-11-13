#!/usr/bin/env python3
"""Prove Scripts/bd07cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bdmisn07.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
faithful = (ROOT / "Scripts/bdmisn07.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bd07cr.lua").read_bytes()
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
assert stripped == faithful_text, "bd07cr.lua outside the CR regions is not the faithful bdmisn07.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is edited only by the callback hooks and the restored-content step call; the raids are scaled by the
# BuildObject shadow in the runtime region (one scaling event per frame and entry path).
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()"):
    assert callback in coop, callback
assert "BeginEvent" in coop and "scaledOdfs = SCALED_ODFS" in coop

# Every native the runtime region shadows is one the faithful body really calls.
runtime_region = coop.split("-- CR co-op runtime >>", 1)[1].split("-- CR co-op runtime <<", 1)[0]
def shadows(name):
    return bool(re.search(r"(?m)^local %s = campaignRuntime and " % name, runtime_region)
                or re.search(r"(?m)^local (?:\w+, )*%s(?:, \w+)* = (?:\w+, )*%s" % (name, name), runtime_region)
                or re.search(r"(?m)^local %s = %s$" % (name, name), runtime_region))
body = re.sub(r"--\[==\[.*?\]==\]", "", faithful_text, flags=re.S)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
for name in ("GetPlayerHandle", "SetScrap", "SetAIP", "AudioMessage", "SetObjectiveName", "ClearObjectives",
             "AddObjective", "SucceedMission", "FailMission", "GetScrap", "SetPilot", "BuildObject", "IsValid",
             "IsAlive", "Goto", "Attack"):
    assert name in body_calls, "not a call of the body: " + name
    assert shadows(name), "the body calls it, the runtime region must shadow it: " + name
# Natives the runtime offers that this body does not call must not be wrapped.
for name in ("CameraReady", "CameraPath", "CameraFinish", "CameraCancelled", "StopAudioMessage", "Retreat", "Follow",
             "SetObjectiveOn", "RemoveObject", "GetDistance", "GetNearestEnemy", "SetPerceivedTeam", "GetTeamNum"):
    assert name not in body_calls, "the body now calls " + name + ": wrap it"
    assert not re.search(r"(?m)^local %s = " % name, coop), "wrapped but never called: " + name
# The enemy's literal team 2 only ever reaches the engine through the runtime (BuildObject, SetScrap, SetAIP) or
# the GetScrap shadow, and the body never reads a team number back from an object.
live = re.sub(r"--[^\n]*", "", body)
assert len(re.findall(r'BuildObject\("\w+", 2, ', live)) == len(re.findall(r"BuildObject\(", live)), "all body builds are on team 2"
assert "GetTeamNum(" not in body and "SetPerceivedTeam(" not in body, "the body names no other team"
print("bd07cr parity: %d CR regions; the rest is the faithful port" % len(opened))
