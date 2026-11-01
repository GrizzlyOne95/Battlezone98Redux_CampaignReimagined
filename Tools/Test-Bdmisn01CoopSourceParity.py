#!/usr/bin/env python3
"""Prove Scripts/bdmisn01cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bd01.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/bd01.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bdmisn01cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "co-op fixes", "co-op victory", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "bdmisn01cr.lua outside the CR regions is not the faithful bd01.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is edited only by the extras check before the victory test; every callback is wrapped at the end of the
# file (the body returns early on most frames, so AfterUpdate cannot sit inside Update), and the waves are scaled
# by the BuildObject shadow in the runtime region (one scaling event per frame and entry path).
for needle in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
               "campaignRuntime.Save()", "campaignRuntime.Load()", "campaignRuntime.AddObject(h)",
               "Restored.ExtrasAlive()", "BeginEvent", "scaledOdfs = SCALED_ODFS"):
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
natives = {"BuildObject", "IsValid", "IsAlive", "GetDistance", "GetPlayerHandle", "GetNearestUnitOnTeam", "Attack",
           "SetCloaked", "Decloak", "SetScrap", "AudioMessage", "StopAudioMessage", "CameraReady", "CameraPath",
           "CameraFinish", "CameraCancelled", "SetObjectiveName", "SetUserTarget", "ClearObjectives", "AddObjective",
           "SucceedMission", "FailMission"}
for name in natives:
    assert name in body_calls or name in ("IsValid", "IsAlive"), "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
assert "IsValid(" in body and "IsAlive(" in body
# Natives that touch only authored objects or real units stay unwrapped; the body never sets an AIP or builds a
# non-enemy scaled unit.
for name in ("SetAIP", "CameraObject", "Defend", "Defend2", "Follow", "SetIndependence", "RemoveObject"):
    assert name not in body_calls and name not in shadowed, name
for name in ("Goto", "Retreat", "Patrol", "Cloak", "SetPilotClass", "IsCloaked"):
    assert name in body_calls and name not in shadowed, "stays native: " + name
# The enemy's literal team 2 only reaches the engine through the runtime (BuildObject) or the direct-path bypass.
builds = re.findall(r'BuildObject\("(\w+)", (\d), ', body)
assert {team for odf, team in builds if odf != "apcamr"} == {"2"}, "all enemy builds are on team 2"
assert [(o, t) for o, t in builds if o == "apcamr"] == [("apcamr", "1")], "the nav beacon is the one team-1 build"
assert "SetPerceivedTeam" not in body and "team = 2" not in body
print("bdmisn01cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
