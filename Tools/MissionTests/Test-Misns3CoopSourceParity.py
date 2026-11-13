#!/usr/bin/env python3
"""Prove Scripts/misns3cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/misns3.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
faithful = (ROOT / "Scripts/misns3.lua").read_bytes()
coop_raw = (ROOT / "Scripts/misns3cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "co-op callback", "co-op scaling", "co-op callbacks"}, set(opened)
stripped = re.sub(region, "", coop)
assert "-- CR" not in stripped, "CR marker outside a region"
assert stripped == faithful_text, "misns3cr.lua outside the CR regions is not the faithful misns3.lua"
for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The only edits to the body are the BeginEvent marks and the callback hooks.
scaled = opened.count("co-op scaling")
assert scaled == 3, "BeginEvent marks: every defender wave, the retreating lead tank, the retreating lead fighter"
for needle in ("local function SpawnDefenders()", 'M.bd50 = BuildObject("avtank", 2, "bdspawn1")',
               'M.bd60 = BuildObject("avfigh", 2, "bdspawn1")'):
    pattern = r"-- CR co-op scaling <<\n\s*" + re.escape(needle) if needle.startswith("M.") else \
        re.escape(needle) + r"\n-- CR co-op scaling >>"
    assert re.search(pattern, coop), needle
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()"):
    assert callback in coop, callback

# Every native the layer shadows is one the faithful body really calls, and every body native is shadowed.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and campaignRuntime\.\w+ or \1$", coop))
special = set(re.findall(r"(?m)^local IsValid, GetDistance, Attack, IsAudioMessageDone = ", coop) and
              ["IsValid", "GetDistance", "Attack", "IsAudioMessageDone"])
body = re.sub(r"--\[\[.*?\]\]", "", faithful_text, flags=re.S)
body = re.sub(r"--[^\n]*", "", body)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
natives = {"BuildObject", "IsAlive", "GetNearestEnemy", "GetPlayerHandle", "Goto", "Follow", "AudioMessage",
           "ClearObjectives", "AddObjective", "UpdateObjective", "SetObjectiveName", "SucceedMission", "FailMission",
           "SetIndependence", "Attack", "GetDistance", "IsAudioMessageDone"}
missing = {name for name in natives if name not in body_calls}
assert not missing, "shadowed but never called by the body: " + str(missing)
for name in natives | {"IsValid"}:
    assert name in shadowed | special, "the body calls it, the layer must shadow it: " + name
# Natives the body calls that the layer deliberately leaves alone.
untouched = {"GetHandle", "GetTime", "Valid", "Distance", "SafeAttack", "SpawnDefenders", "SpawnEscorts",
             "ShowObjectives", "NewState", "Start", "AddObject", "Update", "Save", "Load"}
assert body_calls - natives - untouched - {"IsValid"} == set(), body_calls - natives - untouched
print("misns3cr parity: %d CR regions (%d scaling marks) and %d shadowed natives; the rest is the faithful port"
      % (len(opened), scaled, len(shadowed | special)))
