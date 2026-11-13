#!/usr/bin/env python3
"""Prove Scripts/ch06cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/ch06.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
faithful = (ROOT / "Scripts/ch06.lua").read_bytes()
coop_raw = (ROOT / "Scripts/ch06cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
assert b"\n" not in faithful.replace(b"\r\n", b"") and b"\n" not in coop_raw.replace(b"\r\n", b""), "no bare LF"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
# Intentional CR rename: the nav beacons match the player faction (Chinese: apcamr -> cpcamr).
faithful_text = faithful_text.replace('"apcamr"', '"cpcamr"')
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "restored content", "co-op victory", "co-op callback",
                       "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "ch06cr.lua outside the CR regions is not the faithful ch06.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is edited only by the callback hooks, the restored-content step and the victory guard; the Soviet
# craft are scaled by the BuildObject shadow in the runtime region (one scaling event per frame and entry path).
for needle in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
               "campaignRuntime.Save()", "campaignRuntime.Load()", "campaignRuntime.AddObject(h)",
               "Restored.Run()", "Restored.Pending()", "BeginEvent", "scaledOdfs = SCALED_ODFS"):
    assert needle in coop, needle
callbacks = coop.split("-- CR co-op callbacks >>", 1)[1]
for name in ("AddObject", "CreatePlayer", "AddPlayer", "DeletePlayer", "Receive"):
    assert re.search(r"(?m)^function %s\(" % name, callbacks), "wrapped callback: " + name
# Start, Update, Save and Load keep the body's own function and carry a callback region inside it.
for name, needle in (("Start", "campaignRuntime.Start()"), ("Update", "campaignRuntime.Update(dt)"),
                     ("Save", "campaignRuntime.Save()"), ("Load", "campaignRuntime.Load()")):
    m = re.search(r"(?ms)^function %s\(.*?^end$" % name, coop)
    assert m and needle in m[0], name + " carries its callback"

runtime_region = coop.split("-- CR co-op runtime >>", 1)[1].split("-- CR co-op runtime <<", 1)[0]
def shadows(name):
    return bool(re.search(r"(?m)^local %s = campaignRuntime and " % name, runtime_region)
                or re.search(r"(?m)^local function %s\(" % name, runtime_region)
                or re.search(r"(?m)^local (?:\w+, )*%s(?:, \w+)* = (?:\w+, )*%s" % (name, name), runtime_region))
body = faithful_text
live = re.sub(r"--[^\n]*", "", body)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", live))
# Every native the runtime region shadows is one the faithful body really calls.
for name in ("GetPlayerHandle", "SetAIP", "SetScrap", "AddScrap", "SetPilot", "AudioMessage", "IsAudioMessageDone",
             "SetObjectiveName", "ClearObjectives", "AddObjective", "SucceedMission", "FailMission", "SetTeamNum",
             "SetPerceivedTeam", "GetTeamNum", "Goto", "Attack", "IsValid", "IsAlive", "GetHealth", "BuildObject"):
    assert name in body_calls, "not a call of the body: " + name
    assert shadows(name), "the body calls it, the runtime region must shadow it: " + name
# Natives the body calls on real objects only stay native; natives it never calls must not be wrapped.
for name in ("SetPilotClass", "GetDistance", "AllObjects", "GetTime", "GetHandle"):
    assert name in body_calls, "not a call of the body: " + name
    assert not re.search(r"(?m)^local %s = " % name, runtime_region), "stays native: " + name
for name in ("CameraReady", "CameraPath", "CameraFinish", "CameraCancelled", "StopAudioMessage", "Retreat", "Follow",
             "Patrol", "SetObjectiveOn", "RemoveObject", "GetNearestEnemy", "GetScrap", "GetNearestUnitOnTeam"):
    assert name not in body_calls, "the body now calls " + name + ": wrap it"
    assert not re.search(r"(?m)^local %s = " % name, coop), "wrapped but never called: " + name
# The Soviets' literal team 2 only reaches the engine through the runtime (BuildObject, SetScrap, SetAIP) or the
# team shadows; the body's team-1 builds are the Chinese convoy and the nav beacon.
builds = re.findall(r'BuildObject\(([^,]+), (\d), ', live)
enemy = {odf for odf, team in builds if team == "2"}
assert enemy == {'"svfigh"', '"svtank"', "raidUnits[math.random(4)]"}, enemy
assert sorted(odf for odf, team in builds if team == "1") == ['"cpcamr"', "odf"], builds
raid = set(re.findall(r'"(\w+)"', re.search(r"local raidUnits = \{([^}]*)\}", live)[1]))
scaled = set(re.findall(r"(\w+) = true", re.search(r"SCALED_ODFS = \{([^}]*)\}", runtime_region)[1]))
assert scaled == raid == {"svfigh", "svltnk", "svtank", "svhraz"}, (scaled, raid)
assert "SetTeamNum(h, 2)" in live and "SetPerceivedTeam(h, 2)" in live and "GetTeamNum(h) == 2" in live
assert "SetPilot(1, 10)" in live and "SetScrap(2, 0)" in live and "AddScrap(2, 50)" in live
print("ch06cr parity: %d CR regions and 21 shadowed natives; the rest is the faithful port" % len(opened))
