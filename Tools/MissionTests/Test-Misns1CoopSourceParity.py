#!/usr/bin/env python3
"""Prove Scripts/misns1cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/misns1.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
faithful = (ROOT / "Scripts/misns1.lua").read_bytes()
coop_raw = (ROOT / "Scripts/misns1cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
# Intentional CR rename: player-placed navs use the player faction camera (stock apcamr -> spcamr).
faithful_text = faithful_text.replace('"apcamr"', '"spcamr"')
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "restored content", "co-op callback",
                       "co-op scaling", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "misns1cr.lua outside the CR regions is not the faithful misns1.lua"

outside = stripped
for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in outside, "CR code outside a region: " + word

# The only edits to the body are the four scaling calls and the callback hooks.
scaled = coop.count("-- CR co-op scaling >>")
assert scaled == 4, "BeginEvent marks: first cavalry craft + first unit of each of the three factory waves"
for needle in ('BuildAtFactory("avtank", 2, M.muf)\n        M.aw1amade = true',
               'BuildAtFactory("avtank", 2, M.muf)\n        M.aw2amade = true',
               'BuildAtFactory("avtank", 2, M.muf)\n        M.aw3amade = true',
               'M.cav1 = BuildObject("avfigh", 2, "cavspawn")'):
    assert re.search(r"-- CR co-op scaling <<\n[^\n]*\n?\s*" + re.escape(needle.split("\n")[0].strip()), coop), needle
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Step(dt)"):
    assert callback in coop, callback

# Every native the runtime shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and campaignRuntime\.\w+ or \1$", coop))
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", re.sub(r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?", "",
                                                         re.sub(r"--\[=\[.*?\]=\]", "", faithful_text, flags=re.S))))
natives = {"BuildObject", "IsAlive", "SetScrap", "SetAIP", "Goto", "Follow", "Attack", "SetIndependence", "AudioMessage",
           "CameraReady", "CameraObject", "SetObjectiveName", "SetObjectiveOn", "ClearObjectives", "AddObjective",
           "RemoveObject", "SucceedMission", "FailMission", "GetNearestEnemy"}
missing = {name for name in natives if name not in body_calls}
assert not missing, "shadowed but never called by the body: " + str(missing)
for name in natives:
    assert name in shadowed, "the body calls it, the runtime must shadow it: " + name
print("misns1cr parity: %d CR regions (%d scaling marks) and %d shadowed natives; the rest is the faithful port"
      % (len(opened), scaled, len(shadowed)))
