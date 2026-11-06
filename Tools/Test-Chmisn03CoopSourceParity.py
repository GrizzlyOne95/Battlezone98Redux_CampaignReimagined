#!/usr/bin/env python3
"""Prove Scripts/ch03cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/ch03.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/ch03.lua").read_bytes()
coop_raw = (ROOT / "Scripts/ch03cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
if b"\r\n" in coop_raw:
    assert coop_raw.count(b"\n") == coop_raw.count(b"\r\n"), "consistent CRLF line endings"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "restored content", "co-op user", "co-op callback", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "ch03cr.lua outside the CR regions is not the faithful ch03.lua"

# (the body's own `howitzerAiRestored` flag is not CR code)
for word in ("campaignRuntime", "CRCCARuntime", "Restored.", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is edited only by the callback hooks, the per-howitzer seat and the restored-content step call; the
# convoys are scaled by the BuildObject shadow in the runtime region (one scaling event per frame and entry path).
for needle in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
               "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()", "Restored.Scan()", "Restored.Seat(i)",
               "BeginEvent", "scaledOdfs = SCALED_ODFS"):
    assert needle in coop, needle
assert coop.count("if campaignRuntime then Restored.Seat(i) end") == 3, "one seat per howitzer loop and one in RestoreHowitzerAI"
callbacks = coop.split("-- CR co-op callbacks >>", 1)[1]
for name in ("AddObject", "CreatePlayer", "AddPlayer", "DeletePlayer", "Receive"):
    assert re.search(r"(?m)^function %s\(" % name, callbacks), "wrapped callback: " + name

# Every native the runtime region shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and (?:campaignRuntime\.\w+ or \1|function)", coop))
body = faithful_text
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
natives = {"BuildObject", "IsValid", "Attack", "Defend2", "SetScrap", "SetPilot", "SetPerceivedTeam", "GetTeamNum",
           "GetPlayerHandle", "MakeExplosion", "AudioMessage", "ClearObjectives", "AddObjective", "SetObjectiveOn",
           "SetObjectiveOff", "SetObjectiveName", "StartCockpitTimer", "StopCockpitTimer", "HideCockpitTimer",
           "GetCockpitTimer", "SucceedMission", "FailMission"}
for name in natives:
    assert name in body_calls, "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
# Natives that touch only real units or authored objects stay unwrapped; the body has no cameras and sets no AIP.
for name in ("SetAIP", "CameraReady", "CameraPath", "RemoveObject", "StopAudioMessage", "Follow"):
    assert name not in body_calls and name not in shadowed, name
for name in ("Goto", "AddScrap", "SetPilotClass", "Stop", "GetHandle", "GetCurHealth", "GetCurAmmo", "IsAliveAndPilot"):
    assert name in body_calls and name not in shadowed, "stays native: " + name
# The enemy's literal team 2 only reaches the engine through the runtime (BuildObject) or the SetPerceivedTeam shadow.
live_body = "\n".join(line for line in body.split("\n") if not line.lstrip().startswith("--"))
builds = re.findall(r'BuildObject\(([^,]+), (\d), ', live_body)
assert {team for odf, team in builds if "apcamr" not in odf and "cvmufa" not in odf and "cvslfa" not in odf} == {"2"}, builds
# (the four commented cvscav builds are the cut content the CR layer restores)
assert {odf for odf, team in builds if team == "1"} == {'"apcamr"', '"cvmufa"', '"cvslfa"'}, "team-1 builds are the base beacon, factory and armory"
assert len(re.findall(r"SetPerceivedTeam\([^,]+, 2\)", live_body)) >= 2, "the howitzers are perceived as team 2 (remapped to 5 by the shadow)"
print("ch03cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
