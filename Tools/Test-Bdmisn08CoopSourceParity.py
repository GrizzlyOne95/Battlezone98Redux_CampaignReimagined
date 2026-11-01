#!/usr/bin/env python3
"""Prove Scripts/bdmisn08cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bdmisn08.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/bdmisn08.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bdmisn08cr.lua").read_bytes()
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
assert stripped == faithful_text, "bdmisn08cr.lua outside the CR regions is not the faithful bdmisn08.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is edited only by the callback hooks and the restored-content step call; every other change is a lexical
# shadow of a native in the runtime region.
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()", "Restored.BeforeRun()"):
    assert callback in coop, callback
start = coop.split("function Start()", 1)[1].split("\nend\n", 1)[0]
assert start.index("campaignRuntime.Start()") < start.index('GetHandle("recycler")'), "runtime Start precedes the body's handles"
update = coop.split("function Update(dt)", 1)[1]
assert update.index("campaignRuntime.Update(dt)") < update.index("Restored.BeforeRun()") < update.index("M.user = GetPlayerHandle()")

# Every native the runtime region shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and (?:campaignRuntime\.\w+ or \1|function)", coop))
body = re.sub(r"--\[\[.*?\]\]", "", faithful_text, flags=re.S)
body = re.sub(r"(?m)--.*$", "", body)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
natives = {"BuildObject", "BuildObjectAtPortal", "GetPlayerHandle", "Goto", "Retreat", "Attack", "SetScrap", "SetPerceivedTeam",
           "AudioMessage", "StopAudioMessage", "CameraReady", "CameraPath", "CameraFinish", "CameraCancelled",
           "SetObjectiveName", "SetObjectiveOn", "ClearObjectives", "AddObjective", "RemoveObject",
           "SucceedMission", "FailMission", "IsValid", "GetHealth", "GetTeamNum"}
for name in natives:
    assert name in body_calls, "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
# Calls with arguments the runtime would drop stay native: the body's Stop/IsTouching/GetIn/RemovePilot etc. are not orders
# the runtime knows, and IsAudioMessageDone must see the audio handles unchanged.
for name in ("Stop", "GetIn", "RemovePilot", "IsTouching", "IsAudioMessageDone", "PortalIn", "PortalOut", "ActivatePortal",
             "DeactivatePortal", "isPortalActive", "GetPilotClass", "IsAliveAndPilot", "SetPilot"):
    assert name not in shadowed, "must not be wrapped: " + name
# Hard-coded team numbers: the enemy's literal team 2 only reaches the engine through a mapped call.
assert re.findall(r'BuildObjectAtPortal\(.*, 2, M\.portal\)', body) and re.findall(r'BuildObject\("cspilo", 2,', body)
assert "SetPerceivedTeam(M.apc, 0)" in body and "SetPerceivedTeam(M.apc, 2)" in body
assert "GetTeamNum(h)" in body and "== 1" in body
print("bdmisn08cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
