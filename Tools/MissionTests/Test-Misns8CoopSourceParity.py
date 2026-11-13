#!/usr/bin/env python3
"""Prove Scripts/misns8cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/misns8.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
faithful = (ROOT / "Scripts/misns8.lua").read_bytes()
coop_raw = (ROOT / "Scripts/misns8cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
# Intentional CR renames: enemy NSDF buildings became Black Dog ("ab*" -> "bb*"), the nav camera follows
# the player faction (apcamr -> spcamr), and the stock "bvtavk" typo is fixed to "bvtank".
faithful_text = re.sub(r'"ab(\w+)"', lambda m: '"bb' + m.group(1) + '"', faithful_text)
faithful_text = faithful_text.replace('"apcamr"', '"spcamr"').replace('"bvtavk"', '"bvtank"')
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "restored content", "co-op callback",
                       "co-op scaling", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "misns8cr.lua outside the CR regions is not the faithful misns8.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The only edits to the body are the one scaling call and the callback hooks.
assert coop.count("-- CR co-op scaling >>") == 1, "BeginEvent marks: the retaliation squad (the first tank of the pair)"
assert re.search(r'-- CR co-op scaling <<\n\s*M\.screwu1 = BuildObject\("bvtank", 2, "t1post"\)', coop), "BeginEvent precedes the first tank"
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "campaignRuntime.AddObject(h)", "Restored.Step(dt)"):
    assert callback in coop, callback

# Every native the runtime shadows is one the faithful body really calls; every call it makes is shadowed.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and campaignRuntime\.\w+ or \1$", coop))
shadowed |= set(re.findall(r"(?m)^local (SetScrap) = campaignRuntime and function", coop))
shadowed |= set(re.findall(r"(?m)^    (\w+) = function\(", coop.split("-- CR co-op runtime >>", 1)[1].split("-- CR co-op runtime <<", 1)[0]))
body = re.sub(r"--\[=\[.*?\]=\]", "", faithful_text, flags=re.S)
body = re.sub(r"(?m)--[^\n]*", "", body)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
natives = {"BuildObject", "IsAlive", "IsValid", "GetDistance", "SetScrap", "SetAIP", "Goto", "Follow", "Attack", "Defend",
           "SetIndependence", "AudioMessage", "SetObjectiveName", "SetObjectiveOn", "ClearObjectives", "AddObjective",
           "RemoveObject", "SucceedMission", "GetScrap", "AddScrap", "SetPilot", "CountUnitsNearObject",
           "SetPerceivedTeam", "GetWhoShotMe", "GetPlayerHandle"}
missing = {name for name in natives if name not in body_calls}
assert not missing, "shadowed but never called by the body: " + str(missing)
for name in natives:
    assert name in shadowed, "the body calls it, the CR layer must shadow it: " + name
# Calls the body makes that the layer deliberately leaves native (real handles only, no team argument).
native_ok = {"Build", "Dropoff", "Pickup", "IsDeployed", "IsOdf", "GetHandle", "GetTime", "AddHealth", "GetHealth",
             "Damage", "SetPerceivedTeam", "FailMission"}
unshadowed = {c for c in body_calls if c not in shadowed and c not in native_ok}
unshadowed -= {"NewState", "Valid", "Distance", "Start", "Update", "Save", "Load", "AddObject"}
unshadowed -= {c for c in unshadowed if c in ("floor",)}
assert not unshadowed, "unreviewed native calls in the body: " + str(sorted(unshadowed))
# No literal enemy team 2 survives unmapped: every team-2 argument goes through a mapped wrapper.
for pattern in (r"SetScrap\(2", r"GetScrap\(2", r"AddScrap\(2", r"SetPilot\(2", r"BuildObject\([^)]*, 2,",
                r"SetPerceivedTeam\([^)]*, 2\)", r"CountUnitsNearObject\([^)]*, 2,"):
    assert re.search(pattern, body), "the body still names team 2 here (wrapper needed): " + pattern
print("misns8cr parity: %d CR regions and %d shadowed natives; the rest is the faithful port" % (len(opened), len(shadowed)))
