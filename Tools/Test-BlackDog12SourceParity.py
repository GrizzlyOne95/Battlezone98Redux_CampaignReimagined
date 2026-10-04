"""Run from any directory: python Tools/Test-BlackDog12SourceParity.py.

Structural checks complement Test-BlackDog12.lua; this is not a BZR runtime test.
"""
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "References/BlackDog12Source/BlackDog12Mission.cpp"
LUA = ROOT / "Scripts/bdmisn12.lua"
raw = SOURCE.read_bytes()
blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
assert blob == "584450878d2ed983c75195f10d8ccaeb6abcaedc", "source archive changed"
source = raw.decode().split("void BlackDog12Mission::Execute()", 1)[1]
lua = LUA.read_text().split("function Update(dt)", 1)[1].split("function Save()", 1)[0]
source = re.sub(r"//[^\n]*", "", source)
lua = re.sub(r"--[^\n]*", "", lua)

# Compare ordered gameplay side effects, including every explicit spawn,
# cloak, target, escort assignment, priority, objective, voice and ending.
aliases = {
    "CloakUnit": "SetCloaked", "AttackUnit": "Attack",
    "DefendUnit": "Defend2", "GotoUnit": "Goto",
    "BuildAtPortal": "BuildObjectAtPortal",
    "AudioDone": "IsAudioMessageDone",
}
names = {
    "SetScrap", "SetPilot", "BuildObject", "BuildObjectAtPortal", "SetCloaked",
    "Attack", "Defend2", "Goto", "AudioMessage", "StopAudioMessage",
    "ClearObjectives", "AddObjective", "SucceedMission", "FailMission",
}


def canonical(call):
    call = call.replace("M.", "")
    call = re.sub(r"(\d+\.\d+)f\b", r"\1", call)
    call = re.sub(r"\bWHITE\b", '"white"', call)
    call = re.sub(r"\bGREEN\b", '"green"', call)
    return re.sub(r"\s+", "", call)


def effects(code):
    result = []
    for line in code.splitlines():
        for name in names | aliases.keys():
            match = re.search(r"\b" + name + r"\((.*)\)\s*;?\s*$", line)
            if match:
                result.append(canonical(aliases.get(name, name) + "(" + match[1] + ")"))
                break
    return result


native, port = effects(source), effects(lua)
assert native == port, "\n".join(
    f"{i}: native={a} port={b}" for i, (a, b) in enumerate(zip(native, port)) if a != b
) or f"side-effect counts differ: {len(native)} != {len(port)}"

# Timer expressions are compared in source order, not just numeric totals.
timer = re.compile(
    r"(?:M\.)?(delays\[\d+\]|camera1SoundDelay|scrapDelay|portalOnTime|portalOffTime)"
    r"\s*=\s*([^;\n]+)"
)
assert [canonical(a + "=" + b) for a, b in timer.findall(source)] == [
    canonical(a + "=" + b) for a, b in timer.findall(lua)
], "timer expression/order changed"
assert "activatePortal(portal, false)" in source
assert "ActivateOutwardPortal()" in lua
assert "deactivatePortal(portal)" in source and "ClosePortal()" in lua
assert "for i = 0, 3 do" in lua and "healthLow[4+i]" in lua
assert not re.search(r"\b(TRUE|FALSE|NULL)\b", lua), "untranslated C++ constants"
print(f"BlackDog12: exact source blob, {len(native)} ordered side effects and timers match")
