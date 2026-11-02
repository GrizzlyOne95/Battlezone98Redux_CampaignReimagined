#!/usr/bin/env python3
"""Prove Scripts/chmisn02cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/ch02.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/ch02.lua").read_bytes()
coop_raw = (ROOT / "Scripts/chmisn02cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
assert coop_raw.count(b"\n") == coop_raw.count(b"\r\n"), "no bare LF in a CRLF file"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert opened == ["co-op layer", "co-op runtime", "co-op fixes", "co-op callbacks"], opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "chmisn02cr.lua outside the CR regions is not the faithful ch02.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED", "ENEMY_TEAM"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is not edited at all: every callback is wrapped at the end of the file.
for needle in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
               "campaignRuntime.Save()", "campaignRuntime.Load()", "campaignRuntime.AddObject(h)", "Restored.Run()",
               "BeginEvent", "scaledOdfs = SCALED_ODFS"):
    assert needle in coop, needle
callbacks = coop.split("-- CR co-op callbacks >>", 1)[1]
for name in ("Start", "AddObject", "Update", "Save", "Load", "CreatePlayer", "AddPlayer", "DeletePlayer", "Receive"):
    assert re.search(r"(?m)^function %s\(" % name, callbacks), "wrapped callback: " + name

# Every native the runtime region shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and (?:campaignRuntime\.\w+ or \1|function)", coop))
shadowed.add("IsAudioMessageDone")  # a plain local function, not a campaignRuntime branch
body = re.sub(r"--\[=\[.*?\]=\]", "", faithful_text, flags=re.S)  # the disabled block is a comment, not a call
body = re.sub(r"--[^\n]*", "", body)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
natives = {"BuildObject", "Goto", "Attack", "Hunt", "SetScrap", "SetPilot", "AudioMessage", "StopAudioMessage",
           "IsAudioMessageDone", "ClearObjectives", "AddObjective", "SetObjectiveOn", "SetName", "SucceedMission",
           "FailMission", "GetPlayerHandle", "CameraReady", "CameraPath", "CameraFinish", "CameraCancelled",
           "StartCockpitTimer"}
for name in natives:
    assert name in body_calls, "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
# Natives that touch only real units or the engine itself stay unwrapped (the body never holds a ticket in M).
for name in ("Retreat", "Defend2", "SetPerceivedTeam", "SetTeamNum", "SetCommand", "GetHandle",
             "GetDistance", "GetHealth", "IsValid", "IsAlive", "GetPathPointCount", "GetTime"):
    assert name not in shadowed, "stays native: " + name
for name in ("SetAIP", "SetAIControl", "GetTeamNum", "SetCloaked", "CameraObject", "Follow", "Patrol"):
    assert name not in body_calls, "the body never calls " + name

# The enemy's literal team 2 only reaches the engine through the runtime (BuildObject); the convoy, the nav and the
# defecting walker are the only builds on other teams.
builds = re.findall(r'BuildObject\("(\w+)", (\d), "(\w+)"\)', body)
assert len(builds) == len(re.findall(r"BuildObject\(", body)), "every build names a literal team and path"
enemy = {odf for odf, team, _ in builds if team == "2"}
assert enemy == {"svfigh", "svtank", "svwalk", "svhraz", "svartl", "svltnk", "svrckt"}, enemy
others = {(odf, team) for odf, team, _ in builds if team != "2"}
assert others == {("svwalk", "0"), ("cvapcb", "1"), ("cvfighc", "1"), ("cpcamr", "1")}, others
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", coop)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
assert scaled == enemy, (scaled, enemy)
assert "team == 2" in coop and "NativeBuildObject(odf, team, where)" in coop, "only team 2 builds become tickets"
print("chmisn02cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
