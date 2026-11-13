#!/usr/bin/env python3
"""Prove Scripts/bd02cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bd02.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
faithful = (ROOT / "Scripts/bd02.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bd02cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
# Intentional CR rename: the nav beacons match the player faction (Black Dog: apcamr -> bpcamr).
faithful_text = faithful_text.replace('"apcamr"', '"bpcamr"')
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "restored content", "co-op callback", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "bd02cr.lua outside the CR regions is not the faithful bd02.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is edited only by the callback hooks and the restored-content step call; the waves are scaled by the
# BuildObject shadow in the runtime region (one scaling event per frame), not by marks in the body.
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()"):
    assert callback in coop, callback
assert "BeginEvent" in coop and "scaledOdfs = SCALED_ODFS" in coop

cr_text = "".join(re.findall(region, coop))
body = re.sub(r"--\[\[.*?\]\]", "", faithful_text, flags=re.S)
body = re.sub(r"--[^\n]*", "", body)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))

# Every native the body calls and the runtime has a meaning for is shadowed in the runtime region, and every
# shadow is a native the body really calls (so a stale shadow cannot hide).
must_shadow = {"BuildObject", "IsValid", "IsAlive", "GetDistance", "Goto", "Attack", "AudioMessage", "IsAudioMessageDone",
               "CameraReady", "CameraPath", "CameraPathDir", "CameraFinish", "CameraCancelled", "SetObjectiveName",
               "StopAudioMessage", "ClearObjectives", "AddObjective", "RemoveObject", "SucceedMission", "FailMission", "SetScrap", "SetPilot",
               "GetPlayerHandle"}
for name in sorted(must_shadow):
    assert name in body_calls, "not a call of the body: " + name
    assert re.search(r"(?m)^local [\w, ]*\b%s\b[\w, ]* =" % name, cr_text), "the body calls it, the runtime region must shadow it: " + name
# Natives the runtime offers that this body does not call must not be wrapped.
for name in ("SetAIP", "CameraObject", "Follow", "Defend", "Defend2", "Retreat", "SetIndependence",
             "SetPerceivedTeam", "GetNearestEnemy", "GetTeamNum"):
    assert name not in body_calls, name
    assert not re.search(r"(?m)^local [\w, ]*\b%s\b[\w, ]* =" % name, cr_text), "wrapped but never called: " + name
# The enemy's literal team 2 only ever reaches the engine through the runtime (BuildObject) or a stage-prop build.
builds = re.findall(r"BuildObject\(\"(\w+)\", (\d), \"(\w+)\"\)", body)
assert len(builds) == len(re.findall(r"BuildObject\(", body)), "every build names a literal odf, team and path"
assert {team for odf, team, where in builds if odf != "bpcamr"} == {"2"}, "all enemy builds are on team 2"
assert [(o, t) for o, t, w in builds if o == "bpcamr"] == [("bpcamr", "1")], "nav alpha is the one team-1 build"
assert "SetPerceivedTeam" not in body and "GetTeamNum" not in body, "no other hard-coded team reaches the engine"
print("bd02cr parity: %d CR regions; %d shadowed natives; the rest is the faithful port" % (len(opened), len(must_shadow)))
