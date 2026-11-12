#!/usr/bin/env python3
"""Prove Scripts/bd10cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bdmisn10.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/bdmisn10.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bd10cr.lua").read_bytes()
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
assert stripped == faithful_text, "bd10cr.lua outside the CR regions is not the faithful bdmisn10.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED", "crFinale"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is edited only by the callback hooks and the restored-content step call.
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()"):
    assert callback in coop, callback
assert "BeginEvent" in coop and "scaledOdfs = SCALED_ODFS" in coop

# Every native the runtime region shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and (?:campaignRuntime\.\w+ or \1|function)", coop))
shadowed.add("IsAudioMessageDone")  # a plain local function, not a campaignRuntime branch
body = re.sub(r"--[^\n]*", "", faithful_text)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
natives = {"BuildObject", "Hunt", "SetScrap", "SetPilot", "AudioMessage", "StopAudioMessage", "IsAudioMessageDone",
           "CameraReady", "CameraPath", "CameraFinish", "CameraCancelled", "ClearObjectives", "AddObjective",
           "SucceedMission", "GetNearestUnitOnTeam"}
for name in natives:
    assert name in body_calls, "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
# Natives the runtime offers that this body does not call must not be wrapped.
for name in ("SetAIP", "CameraObject", "IsValid", "IsAlive", "GetDistance", "Attack", "Retreat", "FailMission",
             "GetPlayerHandle"):
    assert name not in shadowed, name
# The enemy's literal team 2 only ever reaches the engine through the runtime (BuildObject, SetScrap); the body
# never reads a team number back.
live = body
assert len(re.findall(r"BuildObject\(units\[i\], 2, ", live)) == 1
assert "GetTeamNum(" not in body and "SetPerceivedTeam(" not in body, "the body names no other team"
print("bd10cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
