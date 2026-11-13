#!/usr/bin/env python3
"""Prove Scripts/misns4cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/misns4.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
faithful = (ROOT / "Scripts/misns4.lua").read_bytes()
coop_raw = (ROOT / "Scripts/misns4cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
# Intentional CR rename: the enemy NSDF buildings are Black Dog (abtowe -> bbtowe, ablpow -> bblpow).
faithful_text = faithful_text.replace('"abtowe"', '"bbtowe"').replace('"ablpow"', '"bblpow"')
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "restored content", "co-op callback",
                       "co-op scaling", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
# A region at the very end of the file eats the trailing newline of the faithful text only when it is the last line.
assert stripped.rstrip("\n") == faithful_text.rstrip("\n"), "misns4cr.lua outside the CR regions is not the faithful misns4.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED", "CRIo"):
    assert word not in stripped, "CR code outside a region: " + word

# The only edits to the body are the four scaling calls and the callback hooks.
scaled = coop.count("-- CR co-op scaling >>")
assert scaled == 4, "BeginEvent marks: raiders, bridge guard, north force, counterattack"
for needle in ('M.t1 = BuildObject("avtank", 2, "sbridge")', 'BuildObject("avltnk", 2, "spawn3")',
               'M.counter1 = BuildObject("avrckt", 2, "counter")', 'BuildObject("avfigh", 2, "spawn4")'):
    assert re.search(r"-- CR co-op scaling <<\n[^\n]*\n?\s*" + re.escape(needle), coop) or \
        re.search(r"-- CR co-op scaling <<\n\s*" + re.escape(needle), coop), needle
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "Restored.Step()"):
    assert callback in coop, callback

# Every native the runtime shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and ", coop))
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", re.sub(r"--\[\[.*?\]\]", "", faithful_text, flags=re.S)))
natives = {"BuildObject", "IsAlive", "IsValid", "GetDistance", "GetPlayerHandle", "SetAIP", "Goto", "AudioMessage",
           "SetObjectiveName", "SetObjectiveOn", "ClearObjectives", "AddObjective", "SucceedMission", "FailMission",
           "StartCockpitTimer", "StopCockpitTimer", "HideCockpitTimer", "SetPilot", "AddScrap"}
missing = {name for name in natives if name not in body_calls}
assert not missing, "shadowed but never called by the body: " + str(missing)
for name in natives:
    assert name in shadowed, "the body calls it, the layer must shadow it: " + name
# No enemy-team literal is left unmapped: every team-2 use in the body goes through a shadowed call.
for match in re.finditer(r"(\w+)\(\s*(?:[^(),]*,\s*)?2\s*[,)]", re.sub(r"--\[\[.*?\]\]", "", faithful_text, flags=re.S)):
    assert match.group(1) in ("BuildObject", "SetPilot"), "unmapped team-2 literal: " + match.group(0)
print("misns4cr parity: %d CR regions (%d scaling marks) and %d shadowed natives; the rest is the faithful port"
      % (len(opened), scaled, len(shadowed)))
