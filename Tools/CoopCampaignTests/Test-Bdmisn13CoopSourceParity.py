#!/usr/bin/env python3
"""Prove Scripts/bd13cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bdmisn13.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
faithful = (ROOT / "Scripts/bdmisn13.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bd13cr.lua").read_bytes()
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
assert stripped == faithful_text, "bd13cr.lua outside the CR regions is not the faithful bdmisn13.lua"

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
assert update.index("campaignRuntime.Update(dt)") < update.index("Restored.BeforeRun()") < update.index("M.lastUser = M.user")

# Every native the runtime region shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and (?:campaignRuntime\.[\w.]+(?:\([^)]*\))? or \1|function)", coop))
body = re.sub(r"--\[\[.*?\]\]", "", faithful_text, flags=re.S)
body = re.sub(r"(?m)--.*$", "", body)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
natives = {"BuildObject", "GetPlayerHandle", "GetDistance", "Goto", "Defend2", "SetScrap", "SetPilot", "IsValid",
           "IsRecycledByTeam", "IsAudioMessageDone", "AudioMessage", "StopAudioMessage", "CameraReady", "CameraPath",
           "CameraFinish", "CameraCancelled", "SetObjectiveName", "ClearObjectives", "AddObjective",
           "StartCockpitTimer", "HideCockpitTimer", "GetCockpitTimer", "SucceedMission", "FailMission"}
for name in natives:
    assert name in body_calls, "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
# The body's other engine calls stay native: health, scrap, time and the handle lookups are not co-op state.
for name in ("GetHealth", "GetHandle", "GetTime", "GetScrap", "SetObjectiveOn", "RemoveObject"):
    assert name not in shadowed, "must not be wrapped: " + name
# Hard-coded team numbers: the enemy's literal team 2 only reaches the engine through a mapped call (the spawn
# ticket, or a wrapper that maps it).
assert len(re.findall(r'BuildObject\([^\n]*, 2, ', body)) == 2, "the wave and guard build sites name the authored enemy team 2"
assert "SetPerceivedTeam" not in body and "BuildObjectAtPortal" not in body, "no portal or disguise in this mission"
assert "IsRecycledByTeam(h, 1)" in body, "the recycle query asks team 1 only"
print("bd13cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
