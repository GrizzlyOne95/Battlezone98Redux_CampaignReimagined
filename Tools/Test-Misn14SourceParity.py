#!/usr/bin/env python3
"""Audit preserved source bytes, native state, comments, mission identifiers and the documented deltas.

Everything the campaign adds to misn14 (the co-op layer, the team map, the Titan weather hook, the NSDF
Fury squad, the Fury waves, the surrender additions, the rescue carrier/independence, the restored VO,
the Fury objective and the rally) lives between exact `-- CR <name> >>` / `-- CR <name> <<` marker lines.
They are stripped (inclusive) so the checks below prove what remains is the DLL port. The substitutions
outside the markers are intentional divergences (Docs/MISN14_COOP.md); each is asserted explicitly.
"""
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "References/Misn14Source"
checks = 0


def check(value, message):
    global checks
    assert value, message
    checks += 1


for name, sha in {
    "Misn14Mission.cpp": "77eeffab992d54a4c9a9d7825e1425d996a372db",
    "Misn14Mission.h": "08451d92c69746e6a6ba01fec0ea4efc9c58d791",
}.items():
    data = (ARCHIVE / name).read_bytes()
    blob_sha = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    check(blob_sha == sha, f"Original source bytes changed: {name}")

source = (ARCHIVE / "Misn14Mission.cpp").read_text(encoding="utf-8")
lua_full = (ROOT / "Scripts/misn14.lua").read_text(encoding="utf-8").replace("\r\n", "\n")

# ---- strip the CR regions ---------------------------------------------------------------------------
REGIONS = ("CR co-op layer", "CR team map", "CR Titan weather hook", "CR rescue", "CR fury squad",
           "CR fury waves", "CR surrender", "CR cut VO", "CR objectives", "CR rally")
opens = {f"-- {name} >>": name for name in REGIONS}
closes = {f"-- {name} <<": name for name in REGIONS}
lines = lua_full.split("\n")
for name in REGIONS:
    check(lines.count(f"-- {name} >>") == lines.count(f"-- {name} <<") > 0, "unbalanced/missing markers: " + name)
for line in lines:
    check(not re.match(r"\s*-- CR [\w ]+ (>>|<<)\s*$", line) or line in opens or line in closes,
          "marker must be an exact, unindented, known region line: " + line)
stack, kept = [], []
for line in lines:
    if line in opens:
        stack.append(opens[line])
    elif line in closes:
        check(stack and stack[-1] == closes[line], "region close without matching open: " + line)
        stack.pop()
    elif not stack:
        kept.append(line)
check(not stack, "unterminated region")
lua = "\n".join(kept)
lua_code = re.sub(r"--[^\n]*", "", re.sub(r"--\[(=*)\[.*?\]\1\]", "", lua, flags=re.S))
for token in ("UpdateFurySquad", "SpawnFuryWave", "TurnSquadRogue", "HoldSurvivor", "UpdateRescueNags",
              "UpdateObjectives", "UpdateRally", "TitanHook", "UpdatePresentationTransport", "SetIndependence",
              "misn1423", "misn1424", "misn1425", "misn1426", "misn1427", "misn1420", "avsav14", "hvsat",
              "SetAIControl", "pow1", "pow2"):
    check(token not in lua_code, "region code outside marker regions: " + token)

# ---- native state and comments ----------------------------------------------------------------------
execute = source.split("void Misn14Mission::Execute(void)", 1)[1].split("IMPLEMENT_RTIME", 1)[0]
state = lua.split("local function NewState()", 1)[1].split("local M = NewState()", 1)[0]
native_fields = set()
for fields in re.findall(r"struct\s*\{\s*(?:bool|float|Handle|int)\s+(.*?);", source, re.S):
    native_fields.update(re.findall(r"\b[a-zA-Z_]\w*\b", fields))
native_fields -= {"b_last", "f_last", "h_last", "i_last"}
lua_fields = set(re.findall(r"\b(\w+)\s*=", state))
check(native_fields == lua_fields, f"State mismatch: {native_fields ^ lua_fields}")

comments = re.findall(r"//([^\n]*)|/\*(.*?)\*/", execute, re.S)
normalize = lambda text: " ".join(text.split())
normalized_lua = normalize(lua)
for line, block in comments:
    text = normalize(line or block)
    check(text in normalized_lua, f"Missing original Execute comment/cut code: {text}")

identifiers = set(re.findall(r'"([^"\n]+)"', execute))
for identifier in identifiers:
    check(f'"{identifier}"' in lua, f"Missing source mission identifier: {identifier}")

active = re.sub(r"--\[(=*)\[.*?\]\1\]", "", lua, flags=re.S)
active = re.sub(r"--[^\n]*", "", active)

# ---- the intentional divergences outside the markers (each asserted) -----------------------------------
# 1. Teams: CCA 2 -> ENEMY_TEAM (5), Furies 3 -> FURY_TEAM (6), survivors and the surrendered base -> 7.
check(not re.search(r"\b(SetScrap|AddPilot|SetAIP|GetTeamNum)\([^)]*\b[23]\)", active)
      and not re.search(r"BuildObject\(\"\w+\", [23],", active)
      and not re.search(r"SetTeamNum\([^,]+, [123]\)", active)
      and not re.search(r"GetTeamNum\(h\) == [23]", active), "a DLL team-2/3 literal survived")
check('SetAIP("misn14.aip", ENEMY_TEAM)' in active, "SetAIP names the CCA team (shipped 1.5)")
check(active.count("AddPilot(ENEMY_TEAM, 30)") == 1 and active.count("SetScrap(ENEMY_TEAM, 45)") == 1
      and active.count("SetScrap(ENEMY_TEAM, 0)") == 2, "CCA pilots/scrap on ENEMY_TEAM")
check(active.count('BuildObject("hvsav", FURY_TEAM, "alien') == 9, "the DLL's waves (kept behind FURY_WAVES) use team 6")
check(active.count('BuildObject("aspilo", SURVIVOR_TEAM, "help') == 9, "survivors on team 7")
check(active.count('BuildObject("apcamr", 1, "rescue') == 3, "beacons stay on the shared team 1")
check("if GetTeamNum(h) == ENEMY_TEAM then" in active, "the surrender loop flips the CCA team only")
check(active.count(", SURVIVOR_TEAM) end") == 5, "the base and four towers surrender to team 7 (was team 1)")
# 2. Single-player handles -> any-human checks.
check("AnyPlayerWithin(M.beacon1, 200.0)" in active, "the beacon reminder fires for any human")
check(active.count("HasCarrier() and not M.rescue") == 3 and active.count("CarrierNear(M.beacon") == 3,
      "rescues accept any carrier (tracked APC or a human piloting an avapc)")
check("CarrierNear(M.base, 200.0)" in active, "the pickup accepts any carrier")
check("IsHumanTeamNumber(GetTeamNum(h))" in active, "AddObject tracks any human team's APC")
# 3. Shipped 1.5: Defend(guy, 1).
check(active.count("Defend(M.guy") == 9 and active.count(", 1)\n") >= 9, "Defend priority 1 as in the shipped exe")
check(not re.search(r"Defend\(M\.guy\d\)\n", active), "every Defend names priority 1")
# 4. Cut content that stays cut / restored only inside regions.
check('"misn1402.wav"' not in active, "1402 plays only from the CR Fury scene, never the DLL intro")
check(not re.search(r"AddPilot\s*\(\s*1\s*,\s*10\s*\)", active), "Cut pilot grant was enabled")
check("M.alien_time = GetTime() + 720.0" in active and "M.alien_time = GetTime() + 180.0" in active,
      "the DLL's 720/180 s schedule is kept verbatim (FURY_WAVES replaces it inside the regions)")
check("(M.wave_count > 2 or CcaBroken()) and not M.cca_surrender" in active,
      "the surrender also follows the Fury onslaught (CcaBroken)")
check('FailMission(GetTime() + 5.0, "misn14l.des")' in active, "the DLL's missing-base guard is kept")

check("Get_Time" not in active and "GameObjectHandle" not in active, "Native-only API left active")
check("ObjectiveObjects" not in active, "Broken stock objective iterator used")

# ---- whole file: Lua 5.1, no host-only modules, stock BZR APIs only --------------------------------------
whole = re.sub(r"--\[(=*)\[.*?\]\1\]", "", lua_full, flags=re.S)
whole = re.sub(r"--[^\n]*", "", whole)
check(not re.search(r"\b(?:io|os|debug)\.", whole), "host-only Lua library used")
check(not re.search(r"\bgoto\b|::", whole), "Lua 5.2+ syntax")
check(whole.count("SetAIControl(") == 1 and re.search(r"^SetAIControl\(ENEMY_TEAM, true\)$", whole, re.M),
      "SetAIControl is a single chunk-root call")
check(re.findall(r"SetIndependence\((\w+)", whole) == ["guy"], "SetIndependence only through the aspilo allowlist")
reference = (ROOT / "Docs/BZR_LUA_AGENT_REFERENCE.md").read_text(encoding="utf-8")
helpers = set(re.findall(r"local function\s+(\w+)", whole)) | set(re.findall(r"local (\w+)\s*=", whole))
callbacks = {"Start", "AddObject", "Update", "Save", "Load", "CreatePlayer", "AddPlayer", "DeletePlayer", "Receive"}
for function in set(re.findall(r"(?<![.:\w])([A-Z]\w*)\s*\(", whole)) - helpers - callbacks:
    check(re.search(r"\b" + function + r"\s*\(", reference), f"API absent from stock BZR reference: {function}")
print(f"misn14 source parity: {checks} checks passed")
