#!/usr/bin/env python3
"""Prove Scripts/bdmisn03cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bd03.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/bd03.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bdmisn03cr.lua").read_bytes()
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
assert stripped == faithful_text, "bdmisn03cr.lua outside the CR regions is not the faithful bd03.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is edited only by the callback hooks and the restored-content step call; the raids are scaled by the
# BuildObject shadow in the runtime region (one scaling event per frame), not by marks in the body.
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()"):
    assert callback in coop, callback
assert "BeginEvent" in coop and "scaledOdfs = SCALED_ODFS" in coop
# Start runs the runtime before Setup, so Setup's SetObjectiveName is published after the presentation reset.
start = coop.split("function Start()", 1)[1].split("\nend\n", 1)[0]
assert start.index("campaignRuntime.Start()") < start.index("Setup()"), "runtime Start precedes Setup"

# Every native the runtime region shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and (?:campaignRuntime\.\w+ or \1|function)", coop))
body = re.sub(r"--\[\[.*?\]\]", "", faithful_text, flags=re.S)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
natives = {"BuildObject", "GetPlayerHandle", "Goto", "Follow", "Attack", "Defend2", "Hunt", "SetCloaked", "SetScrap",
           "AudioMessage", "StopAudioMessage", "CameraReady", "CameraPath", "CameraFinish", "CameraCancelled",
           "SetObjectiveName", "SetObjectiveOn", "ClearObjectives", "AddObjective", "RemoveObject",
           "SucceedMission", "FailMission"}
for name in natives:
    assert name in body_calls, "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
# GetDistance keeps its third (path point) argument, which the runtime's two-argument version would drop; no
# enemy unit is ever measured, so tickets never reach it. The same holds for IsValid/IsAlive.
for name in ("GetDistance", "IsValid", "IsAlive", "GetNearestEnemy", "CameraObject", "Defend", "SetIndependence", "Retreat"):
    assert name not in shadowed, "must not be wrapped: " + name
# The enemy's literal team 2 only ever reaches the engine through the runtime (BuildObject); team 1 builds are friendly.
enemy = re.findall(r'BuildObject\(.*, 2, "\w+"\)', body)
friendly = re.findall(r'BuildObject\(.*, 1, "\w+"\)', body)
assert len(enemy) + len(friendly) == len(re.findall(r"BuildObject\(", body)), "every body build is on team 1 or team 2"
assert enemy and friendly
assert "SetPerceivedTeam" not in body and "GetTeamNum" not in body, "no hard-coded team test in the body"
print("bdmisn03cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
