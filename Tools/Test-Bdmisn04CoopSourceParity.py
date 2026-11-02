#!/usr/bin/env python3
"""Prove Scripts/bdmisn04cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bd04.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/bd04.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bdmisn04cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "restored content", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "bdmisn04cr.lua outside the CR regions is not the faithful bd04.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is never edited: every callback is wrapped at the end of the file, and the waves are scaled by the
# BuildObject shadow in the runtime region (one scaling event per frame and entry path).
for needle in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
               "campaignRuntime.Save()", "campaignRuntime.Load()", "campaignRuntime.AddObject(h)",
               "Restored.Run()", "BeginEvent", "scaledOdfs = SCALED_ODFS"):
    assert needle in coop, needle
callbacks = coop.split("-- CR co-op callbacks >>", 1)[1]
for name in ("Start", "AddObject", "Update", "Save", "Load", "CreatePlayer", "AddPlayer", "DeletePlayer", "Receive"):
    assert re.search(r"(?m)^function %s\(" % name, callbacks), "wrapped callback: " + name

# Every native the runtime region shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and (?:campaignRuntime\.\w+ or \1|function)", coop))
body = re.sub(r"(?m)--[^\n]*", "", faithful_text)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
natives = {"BuildObject", "BuildObjectAtPortal", "IsValid", "GetPlayerHandle", "Attack", "Hide", "UnHide", "SetPerceivedTeam",
           "PortalOut", "DeactivatePortal", "SetUserTarget", "IsInfo", "StartCockpitTimer", "StopCockpitTimer",
           "HideCockpitTimer", "GetCockpitTimer", "SetScrap", "SetPilot", "AudioMessage", "StopAudioMessage",
           "CameraReady", "CameraPath", "CameraFinish", "CameraCancelled", "SetObjectiveName", "SetObjectiveOn",
           "SetObjectiveOff", "ClearObjectives", "AddObjective", "RemoveObject", "SucceedMission", "FailMission"}
for name in natives:
    assert name in body_calls, "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
# Natives that touch only authored objects or real units stay unwrapped; the body never sets an AIP, uses an object
# camera, or issues a follow/defend/retreat order.
for name in ("SetAIP", "CameraObject", "Defend", "Defend2", "Follow", "SetIndependence", "Retreat", "GetNearestEnemy", "IsAlive"):
    assert name not in body_calls and name not in shadowed, name
for name in ("Goto", "GetDistance", "IsInsideArea", "GetTug", "GetHealth", "GetHandle", "IsAudioMessageDone"):
    assert name in body_calls and name not in shadowed, "stays native: " + name
# The enemy's literal team 2 only reaches the engine through the runtime (BuildObject) or the portal shadow.
builds = re.findall(r'BuildObject\("(\w+)", (\d), ', body)
assert {odf for odf, team in builds if team == "2"} == {"cvfighg", "cvfigh", "cvtnk"}, builds
assert {odf for odf, team in builds if team == "1"} == {"aspilo", "bvfigh", "bvtank", "bvhraza", "apcamr"}, builds
assert re.findall(r'BuildObjectAtPortal\("(\w+)", (\d), ', body) == [("cvfigh", "2")], "one portal build, on the enemy team"
assert re.findall(r"SetPerceivedTeam\((\w+\.\w+), (\d)\)", body) == [("M.user", "2")], "the disguise is the DLL's team 2 on the player"
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", coop)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
assert scaled == {"cvfigh", "cvfighg", "cvtnk"}, scaled
print("bdmisn04cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
