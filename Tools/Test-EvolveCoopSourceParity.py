#!/usr/bin/env python3
"""Prove Scripts/evolvecr.lua minus its marked Campaign Reimagined regions is exactly Scripts/evolve.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/evolve.lua").read_bytes()
coop_raw = (ROOT / "Scripts/evolvecr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "co-op callback", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "evolvecr.lua outside the CR regions is not the faithful evolve.lua"

for word in ("campaignRuntime", "CRCCARuntime", "SCALED_ODFS", "lastHumanHandle"):
    assert word not in stripped, "CR code outside a region: " + word

for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()"):
    assert callback in coop, callback
update = coop.split("function Update(dt)", 1)[1]
assert update.index("campaignRuntime.Update(dt)") < update.index("M.user=GetPlayerHandle()"), \
    "runtime Update precedes the body"

# Start()/Save()/Load()/AddObject() are one-line globals in the faithful body (no "M = NewState()" line to
# inject into like the other CR missions do): the CR layer captures the originals and reassigns the globals
# afterward instead of editing those lines.
for native_name in ("NativeStart", "NativeSave", "NativeLoad"):
    assert native_name in coop, native_name

# Every native the runtime region shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and (?:campaignRuntime\.\w+ or \1|function)", coop))
body = re.sub(r"--\[\[.*?\]\]", "", faithful_text, flags=re.S)
body = re.sub(r"(?m)--.*$", "", body)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
for name in sorted(shadowed):
    assert name in body_calls, "shadowed but never called by the body: " + name
natives = {"GetPlayerHandle", "RemoveObject", "SetScrap", "ClearObjectives", "AddObjective", "SucceedMission",
           "StartCockpitTimerUp", "IsValid", "IsAlive", "Attack", "BuildObject"}
for name in natives:
    assert name in body_calls, "not a call of the body: " + name
    assert name in shadowed, "the body calls it, the runtime region must shadow it: " + name
# SetMaxScrap/SetPilot/GetCockpitTimer are team/HUD stats the engine already replicates; never wrapped.
for name in ("SetMaxScrap", "SetPilot", "GetCockpitTimer", "GetTime", "AllObjects", "GetOdf"):
    assert name not in shadowed, "must not be wrapped: " + name

print("evolvecr parity: %d CR regions and %d shadowed natives; the rest is the faithful port"
      % (len(opened), len(shadowed)))
