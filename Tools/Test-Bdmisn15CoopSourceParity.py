#!/usr/bin/env python3
"""Prove Scripts/bdmisn15cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bdmisn15.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/bdmisn15.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bdmisn15cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "restored content", "co-op callback", "co-op gate",
                       "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "bdmisn15cr.lua outside the CR regions is not the faithful bdmisn15.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED", "ABSENT_AUDIO", "PLAYERS"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is edited only by the callback hooks, the restored-content step call and the one enemy-count gate; the
# waves are scaled by the BuildObject shadow in the runtime region (one scaling event per frame and spawn path).
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()", "Restored.EnemiesLeft()"):
    assert callback in coop, callback
assert "BeginEvent" in coop and "scaledOdfs = SCALED_ODFS" in coop

# Every native the runtime region shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and (?:campaignRuntime\.\w+ or \1|function)", coop))
shadowed.add("IsAudioMessageDone")  # a plain local function, not a campaignRuntime branch
shadowed.add("GetDistance")  # campaignRuntime.WrapDistance(campaignRuntime.GetDistance)
body = re.sub(r"--[^\n]*", "", faithful_text)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
natives = {"BuildObject", "Goto", "SetScrap", "SetPilot", "AudioMessage", "IsAudioMessageDone", "IsValid", "IsAlive",
           "GetDistance", "GetPlayerHandle", "CameraReady", "CameraPath", "ClearObjectives", "AddObjective",
           "SetObjectiveOn", "SucceedMission", "FailMission", "StartCockpitTimer", "GetCockpitTimer",
           "HideCockpitTimer", "ColorFade", "MakeExplosion"}
for name in natives:
    assert name in body_calls, "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
# Natives the runtime offers that this body does not call must not be wrapped.
for name in ("SetAIP", "CameraObject", "CameraFinish", "CameraCancelled", "StopAudioMessage", "Attack", "Retreat",
             "Follow", "Hunt", "RemoveObject", "SetObjectiveName", "GetNearestEnemy", "SetPerceivedTeam"):
    assert name not in shadowed, name
# The enemy's literal team 2 only ever reaches the engine through the runtime (BuildObject); the body never reads
# a team number back.
assert len(re.findall(r"BuildObject\(odf, 2, ", body)) == 1
assert "GetTeamNum(" not in body and "SetPerceivedTeam(" not in body, "the body names no other team"
print("bdmisn15cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
