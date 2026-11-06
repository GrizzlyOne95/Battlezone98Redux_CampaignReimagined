#!/usr/bin/env python3
"""Prove Scripts/ch04cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/ch04.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/ch04.lua").read_bytes()
coop_raw = (ROOT / "Scripts/ch04cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "co-op fixes", "restored content", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "ch04cr.lua outside the CR regions is not the faithful ch04.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is not edited at all: every callback is wrapped at the end of the file, the pursuit is scaled by the
# BuildObject shadow in the runtime region (one scaling event per frame and entry path).
for needle in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
               "campaignRuntime.Save()", "campaignRuntime.Load()", "campaignRuntime.AddObject(h)",
               "BeginEvent", "scaledOdfs = SCALED_ODFS", "Restored.Run()"):
    assert needle in coop, needle
callbacks = coop.split("-- CR co-op callbacks >>", 1)[1]
for name in ("Start", "AddObject", "Update", "Save", "Load", "CreatePlayer", "AddPlayer", "DeletePlayer", "Receive"):
    assert re.search(r"(?m)^function %s\(" % name, callbacks), "wrapped callback: " + name

# Every native the runtime region shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and (?:campaignRuntime\.\w+ or \1|function)", coop))
body = faithful_text
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
natives = {"IsValid", "IsAlive", "GetDistance", "GetPlayerHandle", "AudioMessage", "StopAudioMessage", "CameraReady",
           "CameraFinish", "CameraCancelled", "CameraPath", "CameraPathDir", "ClearObjectives", "AddObjective",
           "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff", "RemoveObject", "SetScrap", "SetPilot", "Goto",
           "BuildObject", "Attack", "IsCloaked", "Decloak", "EnableCloaking", "GetCurHealth", "GetMaxHealth", "AddHealth",
           "Hide", "SetPerceivedTeam", "PortalIn", "DeactivatePortal", "SetUserTarget", "IsInfo", "StartCockpitTimer",
           "HideCockpitTimer", "GetCockpitTimer", "SucceedMission", "FailMission"}
for name in natives:
    assert name in body_calls, "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
assert shadowed == natives, "shadowed but not listed: " + str(shadowed - natives)
# Natives that touch only real units or authored objects stay unwrapped; the body never sets an AIP.
for name in ("SetAIP", "CameraObject", "Defend", "Defend2", "Follow", "SetIndependence"):
    assert name not in body_calls and name not in shadowed, name
for name in ("Retreat", "GetHandle", "GetOdf", "GetTime", "IsAudioMessageDone"):
    assert name in body_calls and name not in shadowed, "stays native: " + name
# The enemy's literal team 2 only reaches the engine through the runtime (BuildObject) or the direct-path bypass.
builds = re.findall(r'BuildObject\("(\w+)", (\d), ', body)
assert {team for odf, team in builds if odf != "apcamr"} == {"2"}, "all enemy builds are on team 2"
assert {team for odf, team in builds if odf == "apcamr"} == {"1"}, "the nav beacons are on team 1"
assert "team = 2" not in body
print("ch04cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
