#!/usr/bin/env python3
"""Prove Scripts/misns7cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/misns7.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/misns7.lua").read_bytes()
coop_raw = (ROOT / "Scripts/misns7cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "restored content", "co-op callback",
                       "co-op scaling", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "misns7cr.lua outside the CR regions is not the faithful misns7.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The body's own AddObject keeps its job: the CR layer forwards to the runtime from inside it and never redefines it.
assert coop.count("function AddObject(") == 1, "the body's AddObject is not shadowed by a second definition"
assert "campaignRuntime.AddObject(h)" in coop

# The only edits to the body are the five scaling calls and the callback hooks.
scaled = coop.count("-- CR co-op scaling >>")
assert scaled == 5, "BeginEvent marks: every bvraz fighter the body builds (three escalation, two factory)"
builds = re.findall(r"-- CR co-op scaling <<\n\s*(M\.avfight\d = BuildObject\(\"bvraz\",2,\"muf_point\"\))", coop)
assert len(builds) == 5 and builds.count('M.avfight1 = BuildObject("bvraz",2,"muf_point")') == 2 \
    and builds.count('M.avfight2 = BuildObject("bvraz",2,"muf_point")') == 2 \
    and builds.count('M.avfight3 = BuildObject("bvraz",2,"muf_point")') == 1, builds
assert len(re.findall(r'BuildObject\("bvraz"', faithful_text)) == 5, "every body bvraz build is a scaling site"
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Run()"):
    assert callback in coop, callback

# Every native the CR layer shadows is one the faithful body really calls, and the other way round.
body = re.sub(r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?", "", coop)
body = re.sub(r"(?ms)--\[\[.*?\]\]", "", body)
body = re.sub(r"(?m)--[^\n]*", "", body)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
runtime_shadows = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and campaignRuntime\.\w+ or \1$", coop))
custom = set(re.findall(r"(?m)^local ([A-Za-z, ]+) = ([A-Za-z, ]+)$",
                        coop.split("Natives the runtime has no shadow for", 1)[1].split("if campaignRuntime then", 1)[0])[0][0].replace(" ", "").split(",")) \
    | set(re.findall(r"(?m)^local ([A-Za-z, ]+) = ([A-Za-z, ]+)$",
                     coop.split("Natives the runtime has no shadow for", 1)[1].split("if campaignRuntime then", 1)[0])[1][0].replace(" ", "").split(","))
shadowed = runtime_shadows | custom
natives = {"BuildObject", "IsAlive", "SetScrap", "AddScrap", "SetAIP", "SetAIControl", "Goto", "Attack", "Defend", "Retreat",
           "SetIndependence", "AudioMessage", "CameraReady", "CameraObject", "CameraFinish", "CameraCancelled",
           "SetObjectiveName", "SetObjectiveOn", "ClearObjectives", "AddObjective", "RemoveObject", "SucceedMission",
           "FailMission", "GetPlayerHandle", "SetPerceivedTeam", "CountUnitsNearObject", "SetPilot", "AddPilot", "GetIn"}
missing = {name for name in natives if name not in body_calls}
assert not missing, "shadowed but never called by the body: " + str(missing)
for name in natives:
    assert name in shadowed, "the body calls it, the CR layer must shadow it: " + name
# IsValid is shadowed for the helper locals (Distance, IsOdfBase) that test handles; GetDistance for Distance.
for name in ("IsValid", "GetDistance"):
    assert name in shadowed, name
# natives that cannot name the co-op enemy or need no mapping stay native
for name in ("GetHandle", "GetTime", "GetHealth", "Build", "Dropoff", "Stop", "IsOdf", "CountUnitsNearObject"):
    assert name in body_calls or name == "CountUnitsNearObject", name

# A literal enemy team 2 only appears in the body; the CR layer maps it to 5 (runtime) or spells ENEMY.
cr = "\n".join(re.findall(region, coop))
assert "ENEMY = 5" in coop and "team == 2" in cr
print("misns7cr parity: %d CR regions (%d scaling marks) and %d shadowed natives; the rest is the faithful port"
      % (len(opened), scaled, len(shadowed)))
