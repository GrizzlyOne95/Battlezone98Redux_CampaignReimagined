#!/usr/bin/env python3
"""Prove Scripts/bdmisn11cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bdmisn11.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/bdmisn11.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bdmisn11cr.lua").read_bytes()
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
assert stripped == faithful_text, "bdmisn11cr.lua outside the CR regions is not the faithful bdmisn11.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is edited only by the callback hooks and the restored-content step call; the waves are scaled by the
# BuildObject shadow in the runtime region (one scaling event per frame and entry path).
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()"):
    assert callback in coop, callback
assert "BeginEvent" in coop and "scaledOdfs = SCALED_ODFS" in coop

# Every native the runtime region shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and (?:campaignRuntime\.\w+ or \1|function)", coop))
body = re.sub(r"--\[==\[.*?\]==\]", "", faithful_text, flags=re.S)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
natives = {"BuildObject", "IsValid", "Attack", "Defend2", "SetScrap", "SetPilot", "SetCloaked", "SetPerceivedTeam",
           "AudioMessage", "StopAudioMessage", "CameraReady", "CameraPath", "CameraFinish", "CameraCancelled",
           "ClearObjectives", "AddObjective", "SetObjectiveName", "SetObjectiveOn", "RemoveObject",
           "SucceedMission", "FailMission", "StartCockpitTimer", "GetCockpitTimer", "HideCockpitTimer",
           "ColorFade", "MakeExplosion"}
assert shadowed == natives, (sorted(shadowed - natives), sorted(natives - shadowed))
for name in sorted(natives):
    assert name in body_calls, "shadowed but never called by the body: " + name
# Natives the runtime offers that this body does not call, or calls on real handles only, must not be wrapped.
for name in ("SetAIP", "CameraObject", "Follow", "Defend", "SetIndependence", "GetDistance", "GetNearestEnemy",
             "Goto", "Retreat", "IsAlive", "Stop"):
    assert name not in shadowed, name
# IsAudioMessageDone is wrapped as a local function (nil / 0 count as finished), the body's `~= nil` gates stay.
assert "local function IsAudioMessageDone(message)" in coop and "if handle == nil then return 0 end" in coop

# The enemy's literal team 2 only ever reaches the engine through the runtime (BuildObject): every body build is
# on team 2 except the player-side ones, and the only other place a team number is named is the dead test block.
live = re.sub(r"--[^\n]*", "", body)
builds = re.findall(r'BuildObject\(("\w+"), (\d), ', live)
assert {team for odf, team in builds if odf in ('"aspilo"', '"apcamr"')} == {"1"}, "the player-side builds are team 1"
assert all(team == "2" for odf, team in builds if odf not in ('"aspilo"', '"apcamr"')), "all other builds are the enemy"
assert "local TEST_EXPLOSION = false" in faithful_text, "the Chinese-user test block is disabled in the DLL"
assert "GetTeamNum(" not in body, "the body reads no team number back"
print("bdmisn11cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
