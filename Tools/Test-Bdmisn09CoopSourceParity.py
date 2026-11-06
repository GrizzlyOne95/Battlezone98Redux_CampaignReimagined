#!/usr/bin/env python3
"""Prove Scripts/bd09cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bdmisn09.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/bdmisn09.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bd09cr.lua").read_bytes()
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
assert stripped == faithful_text, "bd09cr.lua outside the CR regions is not the faithful bdmisn09.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()"):
    assert callback in coop, callback
assert "BeginEvent" in coop and "scaledOdfs = SCALED_ODFS" in coop

cr_text = "".join(re.findall(region, coop))
body = re.sub(r"--[^\n]*", "", faithful_text)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))

# Every native the body calls and the runtime has a meaning for is shadowed in the runtime region.
must_shadow = {"BuildObject", "IsValid", "GetDistance", "Goto", "Attack", "AudioMessage", "IsAudioMessageDone",
               "SetObjectiveOn", "SetObjectiveOff", "ClearObjectives", "AddObjective", "SucceedMission", "FailMission",
               "SetScrap", "SetPilot", "GetPlayerHandle", "IsOdf", "SetPerceivedTeam", "IsTouching", "ActivatePortal"}
for name in sorted(must_shadow):
    assert name in body_calls, "not a call of the body: " + name
    assert re.search(r"(?m)^local [\w, ]*\b%s\b[\w, ]* =" % name, cr_text), "the body calls it, the runtime region must shadow it: " + name
# The body has no cameras and calls none of the other natives the runtime offers.
for name in ("CameraReady", "CameraPath", "CameraObject", "SetAIP", "Follow", "Defend", "Defend2", "Retreat",
             "SetIndependence", "StopAudioMessage", "GetNearestEnemy", "GetTeamNum", "RemoveObject", "SetObjectiveName"):
    assert name not in body_calls, name
    assert not re.search(r"(?m)^local [\w, ]*\b%s\b[\w, ]* =" % name, cr_text), "wrapped but never called: " + name
# The enemy's literal team 2 only reaches the engine through the runtime (BuildObject) or the SetPerceivedTeam shadow.
builds = re.findall(r"BuildObject\((\"\w+\"|unit\[1\]), (\d), ", body)
assert len(builds) == len(re.findall(r"BuildObject\(", body)), "every build names an odf and a literal team"
assert {team for odf, team in builds if odf != '"apcamr"'} == {"2"}, "all enemy builds are on team 2"
assert {(o, t) for o, t in builds if o == '"apcamr"'} == {('"apcamr"', "1")}, "the nav beacons are the team-1 builds"
assert "SetPerceivedTeam(M.user, team)" in body and "Perceived(2)" in body and "Perceived(1)" in body
assert "if team == 2 then team = ENEMY_TEAM end" in cr_text, "the shadow maps the DLL's team 2 to the co-op enemy"
print("bd09cr parity: %d CR regions; %d shadowed natives; the rest is the faithful port" % (len(opened), len(must_shadow)))
