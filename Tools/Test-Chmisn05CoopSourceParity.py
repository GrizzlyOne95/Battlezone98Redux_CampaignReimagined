#!/usr/bin/env python3
"""Prove Scripts/ch05cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/ch05.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/ch05.lua").read_bytes()
coop_raw = (ROOT / "Scripts/ch05cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
# Intentional CR rename: the nav beacons match the player faction (Chinese: apcamr -> cpcamr).
faithful_text = faithful_text.replace('"apcamr"', '"cpcamr"')
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "restored content", "co-op victory", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "ch05cr.lua outside the CR regions is not the faithful ch05.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()", "Restored.Wave7Alive()"):
    assert callback in coop, callback
assert "BeginEvent" in coop and "scaledOdfs = SCALED_ODFS" in coop

cr_text = "".join(re.findall(region, coop))
body = re.sub(r"--\[(=*)\[.*?\]\1\]", "", faithful_text, flags=re.S)  # the archived C++ and the cut/debug block
body = re.sub(r"--[^\n]*", "", body)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))

# Every native the body calls and the runtime has a meaning for is shadowed in the runtime region.
must_shadow = {"BuildObject", "GetDistance", "Goto", "Attack", "AudioMessage", "IsAudioMessageDone", "IsAlive",
               "SetObjectiveOn", "SetObjectiveOff", "ClearObjectives", "AddObjective", "SucceedMission", "FailMission",
               "SetScrap", "GetScrap", "SetPilot", "GetPlayerHandle", "SetPerceivedTeam", "SetUserTarget", "GetTug",
               "CameraReady", "CameraPath", "CameraFinish", "CameraCancelled", "SetName"}
for name in sorted(must_shadow):
    assert name in body_calls, "not a call of the body: " + name
    assert re.search(r"(?m)^local [\w, ]*\b%s\b[\w, ]* =" % name, cr_text), "the body calls it, the runtime region must shadow it: " + name
# Natives the body calls that stay native: removals travel with the engine, orders on real units, one-off effects.
for name in ("RemoveObject", "Defend2", "Follow", "Stop", "Pickup", "RemovePilot", "SetCommand", "GetPosition", "GetHandle",
             "SetVector", "GetClassSig", "GetClassLabel", "AllObjects", "GetTime"):
    assert name in body_calls, "not a call of the body: " + name
    assert not re.search(r"(?m)^local [\w, ]*\b%s\b[\w, ]* =" % name, cr_text), "shadowed without need: " + name
# The body has no weather/AIP calls the runtime would need to wrap.
for name in ("SetAIP", "Retreat", "SetIndependence", "StopAudioMessage", "GetNearestEnemy", "GetTeamNum", "CameraObject",
             "StartCockpitTimer", "SetObjectiveName"):
    assert name not in body_calls, name
    assert not re.search(r"(?m)^local [\w, ]*\b%s\b[\w, ]* =" % name, cr_text), "wrapped but never called: " + name

# The enemy's literal team 2 only reaches the engine through the BuildObject / SetPerceivedTeam shadows.
builds = re.findall(r'BuildObject\("(\w+)", (\d), ("\w+"|SetVector\([^\n]*\)|\w+)\)', body)
assert len(builds) == len(re.findall(r"BuildObject\(", body)), "every build names an odf, a literal team and a place"
teams = {}
for odf, team, where in builds:
    teams.setdefault(team, set()).add(odf)
assert set(teams) == {"0", "1", "2"}, teams
assert teams["0"] == {"cvfigh", "apwrck"} and teams["1"] == {"cvfighh", "cpcamr", "cvfigh", "cvmuf", "cvcnst"}, teams
assert all(odf.startswith(("s", "a")) for odf in teams["2"]) and "cpcamr" not in teams["2"], "all enemy builds are Soviet on team 2"
assert 'team == 2 and 5 or team' in cr_text and "if team == 2 then team = 5 end" in cr_text
# Scaling: exactly the combat craft built at the six wave entries and the raid, never the escorts or the guns.
scaled = {}
for odf, team, where in builds:
    if team == "2":
        scaled.setdefault(where.strip('"'), set()).add(odf)
declared_paths = set(re.findall(r"(\w+) = true", re.search(r"SCALED_PATHS = \{([^}]*)\}", cr_text)[1]))
declared_odfs = set(re.findall(r"(\w+) = true", re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1]))
assert declared_paths == {"wave_1", "wave_2", "wave_4", "wave_5", "wave_6", "wave_7", "annoy_1"}, declared_paths
assert declared_odfs == set().union(*(scaled[p] for p in declared_paths)), (declared_odfs, scaled)
for direct in ("enemy_haul", "haul_defend", "artl_1", "artl_2", "artl_defend", "wave_3"):
    assert direct in scaled and direct not in declared_paths, "built directly: " + direct
assert "SetPerceivedTeam(S.user, 2)" in body and "SetPerceivedTeam(S.user, 1)" in body
print("ch05cr parity: %d CR regions; %d shadowed natives; the rest is the faithful port" % (len(opened), len(must_shadow)))
