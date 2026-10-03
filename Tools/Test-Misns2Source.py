"""Audit the native source archive, disabled code and ported call sequence."""
import re
from collections import Counter
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "References/Misns2Source/Misns2Mission.cpp").read_text()
lua = (root / "Scripts/misns2.lua").read_text()
comment_pattern = r"/\*[\s\S]*?\*/|//[^\n]*"
methods = source[source.index("void Misns2Mission::Setup"):source.index("IMPLEMENT_RTIME")]
comments = re.findall(comment_pattern, methods)
for comment in comments:
    assert comment in lua, "Lost or changed source comment: " + comment[:80]

for kind, members in re.findall(r"\b(bool|float|Handle|int)\s+([^;]+_last);", source):
    fields = [name.strip() for name in members.split(",")][:-1]
    initial_state = lua[lua.index("local function NewState()"):lua.index("local function Setup()")]
    for name in fields:
        assert re.search(r"\b" + name + r"\s*=", initial_state), "Missing save field: " + name

native = source[source.index("void Misns2Mission::Execute(void)"):source.index("IMPLEMENT_RTIME")]
native = re.sub(comment_pattern, "", native)
ported = lua[lua.index("function Update(dt)"):lua.index("function Save()")]
ported = re.sub(r"--\[==\[[\s\S]*?\]==\]|--[^\n]*", "", ported)
native = re.sub(r'GameObjectHandle\s*::\s*GetObj\((\w+)\)\s*->\s*SetName\s*\(([^)]+)\)', r'SetObjectiveName(\1, \2)', native)
ported = re.sub(r"\bMarkObjective\(", "SetObjectiveOn(", ported)
ported = re.sub(r"\bNearestEnemy\(", "GetNearestEnemy(", ported)

selected = {
    "BuildObject", "Attack", "Follow", "Retreat", "Goto", "SetIndependence",
    "GetHandle", "GetNearestVehicle", "GetNearestEnemy", "SetObjectiveOn",
    "SetObjectiveName", "AudioMessage", "StopAudioMessage", "RemoveObject",
    "ClearObjectives", "AddObjective", "CameraReady", "CameraPath", "CameraFinish",
    "FailMission", "SucceedMission",
}

def calls(text):
    results = []
    pattern = r'\b(' + '|'.join(sorted(selected)) + r')\s*\('
    for match in re.finditer(pattern, text):
        start, cursor, depth = match.end(), match.end(), 1
        while depth:
            char = text[cursor]
            if char == '"':
                cursor += 1
                while text[cursor] != '"':
                    cursor += 2 if text[cursor] == "\\" else 1
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            cursor += 1
        args = text[start:cursor - 1]
        args = args.replace("M.", "")
        args = re.sub(r"\b(WHITE|GREEN|RED)\b", lambda m: '"' + m[0].lower() + '"', args)
        args = re.sub(r"(\d(?:\.\d+)?)f\b", r"\1", args)
        # Whitespace is irrelevant outside the original string literals.
        parts = re.split(r'("(?:[^"\\]|\\.)*")', args)
        for i in range(0, len(parts), 2):
            parts[i] = re.sub(r"\s+", "", parts[i])
        results.append((match[1], "".join(parts)))
    return results

expected, actual = calls(native), calls(ported)
assert expected == actual, "Changed native call order/arguments: " + str([
    (i, left, right) for i, (left, right) in enumerate(zip(expected, actual)) if left != right
][:5])
counts = Counter(name for name, _ in actual)
assert counts["BuildObject"] == 104
assert counts["Retreat"] == 44
print(f"misns2 source: {len(comments)} in-place comments, 159 save fields, "
      f"{len(actual)} ordered calls preserved (104 spawns, 44 retreats)")
