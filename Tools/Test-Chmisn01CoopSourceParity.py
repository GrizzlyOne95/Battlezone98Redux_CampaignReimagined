#!/usr/bin/env python3
"""Prove Scripts/ch01cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/ch01.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/ch01.lua").read_bytes()
coop_raw = (ROOT / "Scripts/ch01cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
# Intentional CR rename: the nav beacons match the player faction (Chinese: apcamr -> cpcamr).
faithful_text = faithful_text.replace('"apcamr"', '"cpcamr"')
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "co-op fixes", "restored content", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "ch01cr.lua outside the CR regions is not the faithful ch01.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED", "ENEMY_TEAM"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is never edited: every callback is wrapped at the end of the file, the waves are scaled by the BuildObject
# shadow in the runtime region (one scaling event per frame and entry path) and the restorations sit behind flags.
for needle in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
               "campaignRuntime.Save()", "campaignRuntime.Load()", "campaignRuntime.AddObject(h)",
               "Restored.Run()", "BeginEvent", "scaledOdfs = SCALED_ODFS",
               "local RESTORED_RECYCLER_OBJECTIVES = true", "local RESTORED_VOICE_LINES = true"):
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
natives = {"BuildObject", "IsValid", "GetPlayerHandle", "AudioMessage", "CameraReady", "CameraPath", "CameraFinish",
           "CameraCancelled", "ClearObjectives", "AddObjective", "SetObjectiveOn", "SetName", "SucceedMission",
           "FailMission", "SetScrap", "SetPilot", "Goto", "Attack", "Defend2", "SetIndependence", "GetTeamNum",
           "IsFollowing", "SetPerceivedTeam", "EnableAllCloaking", "IsInfo", "StartCockpitTimer", "HideCockpitTimer",
           "GetCockpitTimer", "ColorFade", "MakeExplosion"}
for name in natives:
    assert name in body_calls, "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
assert "IsAudioMessageDone(" in body and "local function IsAudioMessageDone" in coop, "nil-safe audio gate"
# Natives that touch only real objects or the clock stay unwrapped.
for name in ("GetTime", "IsDeployed", "GetCargo", "GetHealth", "GetDistance", "GetPosition", "GetHandle", "GetOdf",
             "AddScrap", "IsAlive", "SetAIP", "CameraObject", "Follow", "Retreat", "RemoveObject"):
    if name in ("SetAIP", "CameraObject", "Follow", "Retreat", "RemoveObject"):
        assert name not in body_calls and name not in shadowed, name
    else:
        assert name in body_calls and name not in shadowed, "stays native: " + name

# The enemy's literal team 2 only reaches the engine through the runtime (BuildObject / Spawn): every other team the
# body builds on is built directly by the shadow.
direct = re.findall(r'BuildObject\("(\w+)", (\d), ', body)
aerial = re.findall(r'Airborne\("(\w+)", (\d), ', body)
team2 = {odf for odf, team in direct + aerial if team == "2"}
other = {(odf, team) for odf, team in direct if team != "2"}
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", coop)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
assert scaled == {"svfigh", "svtank", "svltnk", "svhraz", "svturrb"}, scaled
assert scaled | {"svhaula", "sspilo", "sssold"} == team2, team2
assert other == {("cpcamr", "1"), ("cvslfb", "1"), ("cvrecyd", "1"), ("svfigh", "1"), ("cvhtnk", "1"), ("obdata", "0")}, other
assert "if team ~= 2 then return NativeBuildObject(odf, team, where) end" in coop, "teams other than 2 are built directly"
# The two map slips in the faithful port that the CR layer corrects.
assert 'BuildObject("cvrecyd", 1, "recycler")' in body and '"M.recycler"' not in body
assert '"spawn_explosion1"' in body and 'where = "relic_loc"' in body
# The body's literal enemy team 2 is only compared in the tug test; the shadow answers it.
assert re.findall(r"GetTeamNum\([^)]*\) == (\d)", body) == ["2"] and "if team == ENEMY_TEAM then return 2 end" in coop
assert "SetPerceivedTeam(M.user, 2)" in body and "if team == 2 then team = ENEMY_TEAM end" in coop
print("ch01cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
