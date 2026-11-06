#!/usr/bin/env python3
"""Prove Scripts/bd12cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bdmisn12.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/bdmisn12.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bd12cr.lua").read_bytes()
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
assert stripped == faithful_text, "bd12cr.lua outside the CR regions is not the faithful bdmisn12.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is edited only by the callback hooks and the restored-content step call; the raids are scaled by the
# BuildObject shadow in the runtime region (one scaling event per frame and entry path).
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
natives = {"BuildObject", "IsValid", "Goto", "Attack", "Defend2", "SetScrap", "SetPilot", "SetCloaked", "PortalOut",
           "ActivatePortal", "DeactivatePortal", "AudioMessage", "StopAudioMessage", "CameraReady", "CameraPath",
           "CameraFinish", "CameraCancelled", "ClearObjectives", "AddObjective", "SucceedMission", "FailMission"}
for name in natives:
    assert name in body_calls, "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
# IsAudioMessageDone is wrapped by hand: a nil or 0 handle counts as finished.
assert "IsAudioMessageDone" in body_calls and "local function IsAudioMessageDone(message)" in coop
# Natives the runtime offers that this body does not call must not be wrapped.
for name in ("SetAIP", "CameraObject", "Follow", "Defend", "SetIndependence", "Retreat", "GetDistance",
             "GetNearestEnemy", "SetObjectiveName", "SetObjectiveOn", "RemoveObject", "UpdateObjective"):
    assert name not in body_calls and name not in shadowed, name
# The enemy's literal team 2 only ever reaches the engine through the runtime (BuildObject); TRO 1.3 spawns no scrap,
# the portal reinforcements are the Black Dog team 1, and the body never reads a team number back.
live = re.sub(r"--[^\n]*", "", body)
builds = re.findall(r'BuildObject\(("\w+"), (\d), ', live)
assert builds and {team for _, team in builds} == {"2"}, "all body builds are on team 2 (TRO 1.3 has no scrap spawns)"
assert re.findall(r'BuildAtPortal\("\w+", (\d), ', live) == ["1", "1", "1", "1"], "reinforcements are team 1"
assert "GetTeamNum(" not in body and "SetPerceivedTeam(" not in body, "the body names no other team"
print("bd12cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
