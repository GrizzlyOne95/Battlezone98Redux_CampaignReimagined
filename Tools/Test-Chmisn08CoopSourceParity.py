#!/usr/bin/env python3
"""Prove Scripts/chmisn08cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/ch08.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/ch08.lua").read_bytes()
coop_raw = (ROOT / "Scripts/chmisn08cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert opened == ["co-op layer", "co-op runtime", "co-op fixes", "co-op callbacks"], opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "chmisn08cr.lua outside the CR regions is not the faithful ch08.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED", "MissionEnv", "setfenv"):
    assert word not in stripped, "CR code outside a region: " + word

# The body is not edited at all: every callback is wrapped at the end of the file, and the runtime sandbox
# (setfenv/RealEnv, see "CR co-op runtime") restores the real global table before the entry points below are
# (re)defined, so the host engine's lua_getglobal still finds them.
for needle in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
               "campaignRuntime.Save()", "campaignRuntime.Load()", "campaignRuntime.AddObject(h)",
               "local RealEnv = getfenv(1)", "setfenv(1, MissionEnv)", "setfenv(1, RealEnv)",
               "scaledOdfs = { svfigh = true, svtank = true, svwalk = true }", "CH8Cloak", "CH8Decloak",
               "CH8EnableCloak", "CH8Perceived", "CH8Boom"):
    assert needle in coop, needle
callbacks = coop.split("-- CR co-op callbacks >>", 1)[1]
for name in ("Start", "AddObject", "Update", "Save", "Load", "CreatePlayer", "AddPlayer", "DeletePlayer", "Receive"):
    assert re.search(r"(?m)^function %s\(" % name, callbacks), "wrapped callback: " + name
# The sandbox restore happens before the callbacks are (re)defined, never after.
assert callbacks.index("setfenv(1, RealEnv)") < callbacks.index("function Start()"), \
    "RealEnv must be restored before the engine-visible entry points are defined"

body = faithful_text
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
runtime_region = coop.split("-- CR co-op runtime >>", 1)[1].split("-- CR co-op runtime <<", 1)[0]
# chmisn08cr.lua shadows natives as chunk GLOBALS (not locals): Update() alone needs 37 MS_* constants plus M
# as upvalues, leaving no room under Lua 5.1's 60-upvalue limit for ~25 shadowed natives too (see the runtime
# region's own comment). Two styles appear: `Name = campaignRuntime and ... or Name` and a plain `function
# Name(...)` redefinition (SetPilot, IsAudioMessageDone) that branches on `campaignRuntime` internally.
assign_shadows = set(re.findall(r"(?m)^(\w+) = campaignRuntime and", runtime_region))
func_shadows = set(re.findall(r"(?m)^function (\w+)\(", runtime_region))
shadowed = assign_shadows | func_shadows
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
# Natives that carry the player, an enemy build, a camera, a message or a result must be shadowed.
required = {"GetPlayerHandle", "Attack", "BuildObject", "GetNearestUnitOnTeam", "SetScrap", "SetAIP",
            "AudioMessage", "IsAudioMessageDone", "RemoveObject", "ClearObjectives", "AddObjective", "SetName",
            "SetObjectiveOn", "SetObjectiveOff", "CameraReady", "CameraPath", "CameraFinish", "CameraCancelled",
            "SucceedMission", "FailMission", "Cloak", "Decloak", "EnableCloaking", "SetPerceivedTeam",
            "MakeExplosion", "SetPilot"}
assert shadowed == required, shadowed ^ required
# Stay native: map-authored objects and real units only (the convoy's five APCs and their escorts are direct
# builds that need an immediately-valid handle; Goto/Defend2 are never shadowed).
for name in ("Goto", "Defend2", "GetHandle", "GetTime", "SetUserTarget", "GetHealth", "IsValid", "IsAlive"):
    assert name in body_calls and name not in shadowed, "stays native: " + name

# The enemy's literal team 2 only reaches the engine through BuildObject's shadow (remapped to team 5): the
# convoy's APCs and direct escorts (literal odf), plus the reinforcement waves (odf is a Wave() parameter).
builds = re.findall(r'BuildObject\("(\w+)", (\d), ', body)
teams = {}
for odf, team in builds:
    teams.setdefault(team, set()).add(odf)
assert teams["2"] == {"svapc", "svfigh"}, teams
assert teams["1"] == {"apcamr", "cvrecy", "cvmuf", "cvslf"}, teams
wave_builds = set(re.findall(r'Wave\("(\w+)", "wave_\d"', body))
assert wave_builds == {"svfigh", "svtank", "svwalk"}, wave_builds
# svfigh is shared between a scaled wave and the two direct, unscaled apc_escort builds, so SCALED_PATHS gates
# by spawn path, not by odf (a scaledOdfs-by-odf gate alone cannot tell them apart, see the runtime comment).
scaled_odfs = set(re.search(r"scaledOdfs = \{([^}]*)\}", runtime_region)[1]
                   .replace("=", " ").replace("true", " ").replace(",", " ").split())
assert scaled_odfs == wave_builds == {"svfigh", "svtank", "svwalk"}, scaled_odfs
scaled_paths = set(re.search(r"SCALED_PATHS = \{([^}]*)\}", runtime_region)[1]
                    .replace("=", " ").replace("true", " ").replace(",", " ").split())
assert scaled_paths == {"wave_1", "wave_2", "wave_3", "wave_4", "wave_5", "wave_6"}, scaled_paths

print("chmisn08cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port"
      % (len(opened), len(shadowed)))
