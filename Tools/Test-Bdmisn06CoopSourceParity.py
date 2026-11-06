#!/usr/bin/env python3
"""Prove Scripts/bd06cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bd06.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/bd06.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bd06cr.lua").read_bytes()
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
assert stripped == faithful_text, "bd06cr.lua outside the CR regions is not the faithful bd06.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is never edited: the callbacks are wrapped in the final region, the waves are scaled by the BuildObject
# shadow (one scaling event per frame and entry path), the portal waves by the BuildObjectAtPortal shadow.
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()", "BodyStart()", "BodyUpdate(dt)"):
    assert callback in coop, callback
assert "BeginEvent" in coop and "scaledOdfs = SCALED_ODFS" in coop

# Every native the runtime region shadows is one the faithful body really uses (called or passed as a value).
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and ", coop))
body = re.sub(r"--\[==\[.*?\]==\]", "", faithful_text, flags=re.S)
body = re.sub(r"--[^\n]*", "", body)
for name in sorted(shadowed):
    assert re.search(r"\b%s\b" % name, body), "shadowed but never used by the body: " + name
natives = {"BuildObject", "BuildObjectAtPortal", "PortalOut", "ActivatePortal", "DeactivatePortal", "IsValid", "IsAlive",
           "Goto", "Attack", "Hunt", "GetPlayerHandle", "SetScrap", "SetPilot", "AudioMessage", "CameraReady",
           "CameraPath", "CameraFinish", "CameraCancelled", "ClearObjectives", "AddObjective", "RemoveObject",
           "SucceedMission", "FailMission"}
for name in natives:
    assert name in shadowed, "the body uses it, the runtime region must shadow it: " + name
# IsAudioMessageDone is shadowed by a local function pair (nativeAudioDone), checked separately.
assert "local IsAudioMessageDone = campaignRuntime and" in coop
# Natives that must stay native (the body passes real handles or paths only) are not wrapped.
for name in ("SetAIP", "CameraObject", "Follow", "Defend", "Defend2", "SetIndependence", "GetDistance",
             "GetNearestEnemy", "SetObjectiveName", "SetObjectiveOn", "StopAudioMessage"):
    assert name not in shadowed, "must not be wrapped: " + name
# The enemy's literal team 2 only ever reaches the engine through the runtime; the body never reads a team back.
live = body
assert len(re.findall(r'(?:Spawn|BuildObjectAtPortal)\((?:"\w+"|odf), 2,', live)) + len(re.findall(r'BuildObjectAtPortal\(odf, 2,', live)) > 0
assert "GetTeamNum(" not in body and "SetPerceivedTeam(" not in body, "the body names no other team"
print("bd06cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
