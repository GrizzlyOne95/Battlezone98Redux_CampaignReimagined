#!/usr/bin/env python3
"""Prove Scripts/ch07cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/ch07.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
faithful = (ROOT / "Scripts/ch07.lua").read_bytes()
coop_raw = (ROOT / "Scripts/ch07cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
# Intentional CR rename: the nav beacons match the player faction (Chinese: apcamr -> cpcamr).
faithful_text = faithful_text.replace('"apcamr"', '"cpcamr"')
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert opened == ["co-op layer", "co-op runtime", "co-op fixes", "co-op callbacks"], opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "ch07cr.lua outside the CR regions is not the faithful ch07.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is not edited at all: every callback is wrapped at the end of the file and every native is shadowed by the
# runtime region.
for needle in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
               "campaignRuntime.Save()", "campaignRuntime.Load()", "campaignRuntime.AddObject(h)",
               "BeginEvent", "scaledOdfs = SCALED_ODFS", "Restored.HoldExtraction()", "CH7Disguise"):
    assert needle in coop, needle
callbacks = coop.split("-- CR co-op callbacks >>", 1)[1]
for name in ("Start", "AddObject", "Update", "Save", "Load", "CreatePlayer", "AddPlayer", "DeletePlayer", "Receive"):
    assert re.search(r"(?m)^function %s\(" % name, callbacks), "wrapped callback: " + name

body = faithful_text
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
runtime_region = coop.split("-- CR co-op runtime >>", 1)[1].split("-- CR co-op runtime <<", 1)[0]
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and ", runtime_region))
shadowed -= {"PLAYERS", "campaignRuntime"}
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
# Natives that carry the player, an enemy build, a camera, a message or a result must be shadowed.
required = {"GetPlayerHandle", "GetDistance", "IsAlive", "AudioMessage", "StopAudioMessage", "CameraReady", "CameraFinish",
            "CameraCancelled", "CameraPath", "ClearObjectives", "AddObjective", "SetName", "RemoveObject",
            "SucceedMission", "FailMission", "SetScrap", "SetPilot", "BuildObject", "Attack", "Hide", "UnHide",
            "SetPerceivedTeam", "SetPosition", "MakeExplosion", "ColorFade", "StartSound", "GetCurHealth",
            "GetMaxHealth", "SetCurHealth", "GetCurAmmo", "GetMaxAmmo", "SetCurAmmo"}
for name in sorted(required):
    assert name in body_calls, "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
# Stay native: map-authored objects and real units only (the convoy and its escorts are direct builds).
for name in ("Goto", "Defend2", "SetPilotClass", "IsAudioMessageDone"):
    assert name in body_calls and name not in shadowed - {"IsAudioMessageDone"}, "stays native: " + name
# The disguise values the body names are the ones the CR layer maps: 2 -> 5, 1 -> the human's own team.
live_body = body.split("--[=[", 1)[0]
assert set(re.findall(r"(?m)^\s*SetPerceivedTeam\(M\.user, (\d)\)", live_body)) == {"1", "2"}
assert "team == 2 and 5 or team" in runtime_region and "team == 1 and GetTeamNum(h) or team" in coop
# The enemy's literal team 2 only reaches the engine through the runtime (BuildObject wrapper).
builds = re.findall(r'BuildObject\("(\w+)", (\d), ', body)
teams = {}
for odf, team in builds:
    teams.setdefault(team, set()).add(odf)
assert teams["0"] == {"sspilo"} and teams["1"] == {"cpcamr", "cspilo"}, teams
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", runtime_region)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
assert scaled == {"ssusera", "sssold", "sspilo"}, scaled
print("ch07cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
