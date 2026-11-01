#!/usr/bin/env python3
"""Prove Scripts/misns6cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/misns6.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
faithful = (ROOT / "Scripts/misns6.lua").read_bytes()
coop_raw = (ROOT / "Scripts/misns6cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "co-op callback", "co-op scaling", "co-op callbacks"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "misns6cr.lua outside the CR regions is not the faithful misns6.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The only edits to the body are the two scaling calls and the callback hooks.
scaled = coop.count("-- CR co-op scaling >>")
assert scaled == 2, "BeginEvent marks: the miner raid and the silo counter-attack"
assert re.search(r"M\.counter1 = true\n-- CR co-op scaling >>\n[^\n]*BeginEvent\(\)[^\n]*\n-- CR co-op scaling <<\n\s*local a1 = BuildObject\(\"bvraz\", 2, \"counter1\"\)", coop)
assert re.search(r"-- CR co-op scaling <<\n\s*for _, odf in ipairs\(\{\"bvltnk\", \"bvltnk\", \"bvtank\", \"bvtank\", \"bvrckt\"\}\) do", coop)
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(timestep)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "local bodyAddObject = AddObject"):
    assert callback in coop, callback

# Every native the runtime shadows is one the faithful body really calls.
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and campaignRuntime\.\w+ or \1$", coop))
shadowed |= set(re.findall(r"(?m)^local (IsValid|GetDistance|GetTeamNum|IsAudioMessageDone) = \1$", coop))
body = re.sub(r"--\[=\[.*?\]=\]|--\[\[.*?\]\]|--[^\n]*", "", faithful_text, flags=re.S)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body))
natives = {"BuildObject", "IsAlive", "SetScrap", "SetAIP", "Goto", "Attack", "Defend", "AudioMessage", "ClearObjectives",
           "AddObjective", "SetObjectiveOn", "SucceedMission", "FailMission", "GetPlayerHandle", "GetTeamNum",
           "GetDistance", "IsAudioMessageDone"}
missing = {name for name in natives if name not in body_calls}
assert not missing, "shadowed but never called by the body: " + str(missing)
for name in natives:
    assert name in shadowed, "the body calls it, the layer must shadow it: " + name
for name in shadowed:
    assert name in natives or name == "IsValid", "unexpected shadow: " + name
assert "IsValid(" in body, "IsValid is shadowed for the PLAYERS token the body tests"
# Literal enemy team 2 in the body: every site is covered by the Spawn / GetTeamNum maps.
for site in re.findall(r"[^\n]*\b2\b[^\n]*", body):
    if re.search(r"BuildObject\(|GetTeamNum\(", site):
        continue
    assert not re.search(r"SetScrap\(2|AddScrap\(2|SetPerceivedTeam|SetTeamNum", site), "unmapped enemy team: " + site
print("misns6cr parity: %d CR regions (%d scaling marks) and %d shadowed natives; the rest is the faithful port"
      % (len(opened), scaled, len(shadowed)))
