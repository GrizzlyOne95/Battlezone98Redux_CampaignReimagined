#!/usr/bin/env python3
"""Prove Scripts/bd05cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/bd05.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/bd05.lua").read_bytes()
coop_raw = (ROOT / "Scripts/bd05cr.lua").read_bytes()
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
assert stripped == faithful_text, "bd05cr.lua outside the CR regions is not the faithful bd05.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is edited only by the callback hooks, the restored-content step call and the one enemy-count gate; the
# waves are scaled by the BuildObject shadow in the runtime region (one scaling event per frame and entry path).
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()", "Restored.EnemiesLeft()"):
    assert callback in coop, callback
assert "BeginEvent" in coop and "scaledOdfs = SCALED_ODFS" in coop

# Every native the runtime region shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and (?:campaignRuntime\.\w+ or \1|function)", coop))
body = re.sub(r"--\[==\[.*?\]==\]", "", faithful_text, flags=re.S)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
# Goto and Attack reach the body as values (SpawnUnit(..., Goto)), not as calls.
body_calls |= {name for name in ("Goto", "Attack") if re.search(r"\b%s\)" % name, body)}
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
natives = {"BuildObject", "IsValid", "IsAlive", "Goto", "Attack", "Retreat", "SetScrap", "SetPilot", "SetCloaked",
           "PortalIn", "AudioMessage", "StopAudioMessage", "CameraReady", "CameraPath", "CameraFinish",
           "CameraCancelled", "ClearObjectives", "AddObjective", "RemoveObject", "SucceedMission"}
for name in natives:
    assert name in body_calls or name == "IsValid", "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
# Natives the runtime offers that this body does not call must not be wrapped.
for name in ("SetAIP", "CameraObject", "Follow", "Defend", "Defend2", "SetIndependence", "FailMission", "GetDistance",
             "GetNearestEnemy", "SetObjectiveName", "SetObjectiveOn"):
    assert name not in body_calls and name not in shadowed, name
# The enemy's literal team 2 only ever reaches the engine through the runtime (BuildObject) or the quitters bypass,
# and the body never reads a team number back.
live = re.sub(r"--[^\n]*", "", body)  # the commented portal build stays a comment
assert len(re.findall(r'BuildObject\((?:"\w+"|odf), 2, ', live)) == len(re.findall(r"BuildObject\(", live)), "all body builds are on team 2"
assert "GetTeamNum(" not in body and "SetPerceivedTeam(" not in body, "the body names no other team"
print("bd05cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
