#!/usr/bin/env python3
"""bdmisn04 co-op map contract: the labels, paths and teams Scripts/bdmisn04cr.lua names exist in Missions/bdmisn04cr.bzn.

Skipped (exit 0, says so) when Missions/bdmisn04cr.bzn is not in the tree. The start file Missions/bdmisn04cr.vxt is
checked only when present (it ships with the map); so is the generated Ganymede site table's vent count.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/bdmisn04cr.bzn"
if not bzn_path.is_file():
    print("bdmisn04 co-op contract SKIPPED: Missions/bdmisn04cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = bdmisn04\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = bdmisn04cr.bzn" in text

# ---------------------------------------------------------------- objects and teams
objects, starts, user = {}, [], None
for block in text.split("[GameObject]\n")[1:]:
    label = re.search(r"^label = (.*)$", block, re.M)
    odf = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)[1]
    team = int(re.search(r"^team \[1\] =\n(\d+)$", block, re.M)[1])
    perceived = int(re.search(r"^perceivedTeam \[1\] =\n(\d+)$", block, re.M)[1])
    if odf == "pspwn_1":
        starts.append(team)
        continue
    if odf == "bsuser":
        user = (label and label[1], team)
    assert team in (0, 1, 5), "authored teams are neutral, the Black Dog side or the Chinese on team 5: %s team %d" % (odf, team)
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        objects.setdefault(label[1], []).append((odf, team))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert user == ("asuser1_person", 1), "the map start is the on-foot pilot on team 1: " + str(user)
assert not any(team == 2 for entries in objects.values() for _, team in entries), "nothing is left on the authored team 2"
assert any(team == 5 for entries in objects.values() for _, team in entries), "the Chinese base is on the co-op enemy team"
paths = []
for path in text.split("[AiPath]\n")[1:]:
    m = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if m:
        paths.append(m[1])

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/bdmisn04cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"(?m)--[^\n]*", "", live)  # the DLL's disabled lines stay disabled
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
handles |= {"turret_%d" % n for n in range(1, 10)} if '"turret_" ..' in live else set()
assert handles == {"silo", "portal", "scav_1", "scav_2", "scav_3", "fragment", "hauler_1"} | {"turret_%d" % n for n in range(1, 10)}, handles
for label in sorted(handles):
    assert len(objects.get(label, [])) == 1, "GetHandle label %s must be on exactly one map object (found %d)" % (label, len(objects.get(label, [])))
    assert objects[label][0][1] in (0, 5), "authored story object is neutral or Chinese: " + label
assert objects["portal"][0][0] == "cbport" and objects["fragment"][0][0] == "obdataa" and objects["hauler_1"][0][0] == "cvhaula"
assert {objects["scav_%d" % n][0][0] for n in (1, 2, 3)} == {"cvscava"}
USED = {"pilot", "pilot_path", "nav_1", "nav_2", "camera_start_up", "camera_portal", "unit_path", "trigger_1", "base_limit",
        "scav_path", "rv_scout", "escort_units", "bomber_wing_x5_spawn_point", "proposed_end_area",
        "chinese_scout_x6_spawn_point", "attack_1", "attack_2", "attack_3", "return_1", "return_2", "return_3", "return_4"}
for name in sorted(USED - {"return_%d" % n for n in range(1, 5)}):
    assert '"%s"' % name in live, "the body no longer names the path " + name
assert '"return_" ..' in live, "the four route ambushes are built from return_N"
assert USED <= set(paths), "every path the body names exists: " + str(USED - set(paths))
assert 'IsInsideArea("base_limit"' in live

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local NativeBuildObjectAtPortal", 1)[0]
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in paths or rally in objects, "rally point is a map path or object"
fallback = re.findall(r'"(\w+)"', re.search(r"fallbackEntries = \{([^}]*)\}", config)[1])
assert fallback, "there are alternative approaches"
for name in fallback:
    assert name in paths, "fallback spawn entry exists: " + name
    assert name not in ("pilot", "base_limit"), "a fallback is an enemy approach, not the start"
assert 'failDes = "bd04lose.des"' in config and 'wonFlags = { "won" }' in config
assert 'module = "CREuropaWeather"' in config and 'sites = "CRGanymedeSitesBD04"' in config
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
body_odfs = set(re.findall(r'BuildObject(?:AtPortal)?\("(\w+)", 2,', live))
assert scaled <= body_odfs and scaled == {"cvfigh", "cvfighg", "cvtnk"}, scaled
sites = ROOT / "Scripts/CRGanymedeSitesBD04.lua"
assert sites.is_file() and 'mission = "bdmisn04"' in sites.read_text(encoding="utf-8"), "generated Ganymede sites belong to bdmisn04"
for module in ("CREuropaWeather", "CRVenusMap"):
    assert (ROOT / ("Scripts/%s.lua" % module)).is_file(), module
vents = re.search(r"vents\s*=\s*\{(.*?)\n\s*\},", sites.read_text(encoding="utf-8"), re.S)
no_vents = vents is not None and not vents[1].strip()
assert '#europa.GetVentSites() > 0' in cr_text, "plumes are only triggered when the site table has vents"

# The start file: every co-op player starts as the on-foot pilot (the disguise mission); checked when present.
vxt = ROOT / "Missions/bdmisn04cr.vxt"
if vxt.is_file():
    assert vxt.read_bytes().decode("latin-1").strip() == "bsuser ,", "every co-op player starts as bsuser"
    vxt_note = "start file checked"
else:
    vxt_note = "start file absent, not checked"
mpdes = ROOT / "bdmisn04cr.mpdes"
if mpdes.is_file():
    assert "Wolf in Sheep" in mpdes.read_text(encoding="utf-8", errors="replace")

# ---------------------------------------------------------------- audio: every line has a subtitle, bd04009 is restored
for wav in sorted(set(re.findall(r'"(bd04\d+\.wav)"', lua_full))):
    assert (ROOT / "Text" / (wav[:-4] + ".txt")).is_file(), "no subtitle for " + wav
body_wavs = set(re.findall(r'"(bd04\d+\.wav)"', live))
shipped = {p.stem + ".wav" for p in (ROOT / "Text").glob("bd040??.txt")}
unused = shipped - body_wavs
assert unused == {"bd04009.wav"}, "the only shipped line the body never plays: " + str(unused)
assert '"bd04009.wav"' in cr_text and "RESTORED_VOICE_LINES" in cr_text

# ---------------------------------------------------------------- the doc accounts for every map path and cut label
doc = (ROOT / "Docs/BDMISN04_COOP.md").read_text(encoding="utf-8")
unused_paths = set(paths) - USED
for name in sorted(unused_paths):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused_paths == {"edge_path", "walker_path", "portal_units"}, unused_paths
for word in ("`silo`", "bd04009", "RESTORED_USER_TARGET", "RESTORED_VOICE_LINES", "Stock bugs fixed in the CR layer",
             "Live checklist", "GetCockpitTimer"):
    assert word in doc, "the doc must cover " + word
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("bdmisn04 co-op contract passed: %d labelled objects, %d paths, %d named by the body, %d unused (documented), "
      "%s vents in the Ganymede sites, %s"
      % (len(objects), len(paths), len(USED), len(unused_paths), "no" if no_vents else "some", vxt_note))
