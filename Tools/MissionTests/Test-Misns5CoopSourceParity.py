#!/usr/bin/env python3
"""Prove Scripts/misns5cr.lua minus its marked Campaign Reimagined regions is exactly Scripts/misns5.lua."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
faithful = (ROOT / "Scripts/misns5.lua").read_bytes()
coop_raw = (ROOT / "Scripts/misns5cr.lua").read_bytes()
assert (b"\r\n" in faithful) == (b"\r\n" in coop_raw), "line endings follow the faithful port"
faithful_text = faithful.decode("utf-8").replace("\r\n", "\n")
coop = coop_raw.decode("utf-8").replace("\r\n", "\n")

region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
opened = re.findall(r"(?m)^-- CR ([^\n]*) >>$", coop)
closed = re.findall(r"(?m)^-- CR ([^\n]*) <<$", coop)
assert opened == closed and opened, "every CR region opens and closes in order"
assert set(opened) == {"co-op layer", "co-op runtime", "restored content", "co-op callback",
                       "co-op scaling", "co-op callbacks", "early ladder"}, opened
assert "-- CR" not in re.sub(region, "", coop), "CR marker outside a region"
stripped = re.sub(region, "", coop)
assert stripped == faithful_text, "misns5cr.lua outside the CR regions is not the faithful misns5.lua"

for word in ("campaignRuntime", "CRCCARuntime", "Restored", "RESTORED"):
    assert word not in stripped, "CR code outside a region: " + word

# The only edits to the body are the three scaling calls and the callback hooks.
scaled = coop.count("-- CR co-op scaling >>")
assert scaled == 3, "BeginEvent marks: chaff fighter, APC strike, factory wave"
for needle in ('BuildObject("avfigh", 2, "spawn5")', 'M.h1 = BuildObject("avapc", 2, "spawn6")',
               "if M.wave_count ~= 1 then"):
    assert re.search(r"-- CR co-op scaling <<\n\s*" + re.escape(needle), coop), needle
for callback in ("campaignRuntime.Start()", "campaignRuntime.Update(dt)", "campaignRuntime.AfterUpdate()",
                 "campaignRuntime.Save()", "campaignRuntime.Load()", "campaignRuntime.AddObject(h)"):
    assert callback in coop, callback

# Every native the faithful body calls is either shadowed or deliberately left to the engine.
body = re.sub(r"(?ms)--\[=*\[.*?\]=*\]", "", stripped)
body = re.sub(r"(?m)--[^\n]*", "", body)
body_calls = set(re.findall(r"\b([A-Z]\w+)\(", body)) | set(re.findall(r"\bCommand\((\w+),", body))
shadowed = set(re.findall(r"(?m)^local (\w+) = campaignRuntime and ", coop))
natives = {"BuildObject", "IsValid", "IsAlive", "GetDistance", "GetTeamNum", "SetAIControl", "SetPilot", "AddScrap",
           "SetAIP", "Goto", "Attack", "Defend2", "AudioMessage", "StopAudioMessage", "CameraReady", "CameraPath",
           "CameraFinish", "CameraCancelled", "ClearObjectives", "AddObjective", "SetObjectiveOn",
           "SucceedMission", "FailMission"}
passthrough = {"NewState", "Valid", "Command", "Start", "AddObject", "Update", "Save", "Load", "GetHandle", "IsOdf",
               "IsAudioMessageDone", "GetTime"}
missing = {name for name in natives if name not in body_calls and name not in {"IsValid"}}
assert not missing, "shadowed but never called by the body: " + str(missing)
for name in natives:
    assert name in shadowed, "the body calls it, the CR layer must shadow it: " + name
unknown = body_calls - natives - passthrough - {"random", "command"}
assert not unknown, "natives the CR layer neither shadows nor passes through: " + str(unknown)

# No literal enemy team 2 may reach the engine: every call that names team 2 goes through a shadow.
for line in body.splitlines():
    if re.search(r"[,(]\s*2\s*[,)]|~= 2|== 2\b", line):
        assert re.search(r"BuildObject|SetPilot|AddScrap|SetAIControl|GetTeamNum", line), "unshadowed team 2: " + line.strip()
print("misns5cr parity: %d CR regions (%d scaling marks) and %d shadowed natives; the rest is the faithful port"
      % (len(opened), scaled, len(shadowed)))
