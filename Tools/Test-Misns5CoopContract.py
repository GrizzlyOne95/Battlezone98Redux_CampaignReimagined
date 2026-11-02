#!/usr/bin/env python3
"""misns5 co-op map contract: the labels, paths and teams Scripts/misns5cr.lua names exist in Missions/misns5cr.bzn.

Skipped (exit 0, says so) when Missions/misns5cr.bzn is not in the tree.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/misns5cr.bzn"
if not bzn_path.is_file():
    print("misns5 co-op contract SKIPPED: Missions/misns5cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = misns5\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = misns5cr.bzn" in text

# ---------------------------------------------------------------- objects and teams
objects, starts = {}, []
for block in text.split("[GameObject]\n")[1:]:
    label = re.search(r"^label = (.*)$", block, re.M)
    odf = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)[1]
    team = int(re.search(r"^team \[1\] =\n(\d+)$", block, re.M)[1])
    perceived = int(re.search(r"^perceivedTeam \[1\] =\n(\d+)$", block, re.M)[1])
    if odf == "pspwn_1":
        starts.append(team)
        continue
    assert team in (0, 1, 5), "authored teams are neutral, the Soviets (1) or the Americans on 5: %s team %d" % (odf, team)
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        objects.setdefault(label[1], (odf, team))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
paths = []
for path in text.split("[AiPath]\n")[1:]:
    paths.append(re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)[1])

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/misns5cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"(?ms)--\[=*\[.*?\]=*\]", "", live)
live = re.sub(r"(?m)--[^\n]*", "", live)
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
used = set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live))
used |= set(re.findall(r'CameraPath\("(\w+)"', live))
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
# the player side is Soviet team 1; the single authored enemy craft is on 5
assert objects["svrecy0_recycler"] == ("svrecy", 1) and objects["svmuf0_factory"] == ("svmuf", 1)
assert objects["sbhang0_repairdepot"][1] == 1
for label in ("sblpow2_powerplant", "sblpow3_powerplant", "sblpow4_powerplant"):
    assert objects[label] == ("sblpow", 1), label
assert objects["eggeizr11_geyser"][0] == "eggeizr1" and objects["eggeizr12_geyser"][0] == "eggeizr1"
assert objects["avturr0_turrettank"] == ("avturr", 5), "the authored enemy is the CCA on team 5"
assert not any(team == 2 for _, team in objects.values()), "nothing is left on the authored team 2"
assert "avtank" not in {odf for odf, _ in objects.values()}

# ---------------------------------------------------------------- the runtime configuration only names real content
config = lua_full.split("require(\"CRCCARuntime\").Create", 1)[1].split("local RESTORED =", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects, "rally point is a map object"
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
names = re.findall(r'"(\w+)"', fallback)
assert names, "fallback entries are declared"
for name in names:
    assert name in paths, "fallback spawn entry exists: " + name
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRTitanSitesS5"' in config and 'module = "CRTitanWeather"' in config
assert '"TitanState"' in config and '"TitanRoll"' in config, "the Titan weather channels are declared"
scaled = set(re.findall(r"(\w+) = true", re.search(r"scaledOdfs = \{([^}]*)\}", config)[1]))
built = set(re.findall(r'BuildObject\("(\w+)", \d,', live))
assert scaled <= built, "every scaled ODF is one the body builds: " + str(scaled - built)
sites_path = ROOT / "Scripts/CRTitanSitesS5.lua"
assert sites_path.is_file(), "generated Titan sites are present"
sites = sites_path.read_text(encoding="utf-8")
assert 'mission = "misns5"' in sites, "generated Titan sites belong to misns5"
assert (ROOT / "Scripts/CRTitanWeather.lua").is_file()
anchors = len(re.findall(r"^\s*\{ x = [\d.-]+, z = [\d.-]+, weight", sites, re.M))
assert anchors == 25, "25 pool anchors, got %d" % anchors
bounds = re.search(r"bounds\s*=\s*\{ minX = ([\d.]+), maxX = ([\d.]+), minZ = ([\d.]+), maxZ = ([\d.]+)", sites)
minx, maxx, minz, maxz = (float(g) for g in bounds.groups())
edge = re.findall(r"x \[1\] =\n(\S+)\n\s*z \[1\] =\n(\S+)", text.split("label = edge_path", 1)[1].split("[AiPath]", 1)[0])
assert [(float(a), float(b)) for a, b in edge][0] == (minx, maxz) and [(float(a), float(b)) for a, b in edge][-1] == (maxx, minz), \
    "edge_path spans the playable bounds the weather uses"

# ---------------------------------------------------------------- everything unused is documented
doc = (ROOT / "Docs/MISNS5_COOP.md").read_text(encoding="utf-8")
unused_paths = set(paths) - used - set(names)
for name in sorted(unused_paths):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
unused_objects = {label for label in objects if not label.startswith("sscr_")} - handles
for name in sorted(unused_objects):
    assert "`" + name + "`" in doc, "undocumented unused map object: " + name
coop = (ROOT / "Scripts/misns5cr.lua").read_text(encoding="utf-8")
assert '["misns5.aip"] = "crns5.aip"' in coop, "misns5cr maps misns5.aip to crns5.aip"
builds = re.findall(r'(?m)^\s*\d+,\s*"(\w+)"', (ROOT / "ODF/crns5.aip").read_text(encoding="ascii"))
assert builds and all(b.startswith("bv") for b in builds), "crns5.aip builds only Black Dog units: " + str(builds)
assert "`crns5.aip`" in doc, "the doc names crns5.aip"
for src in ("Docs/CCA_COOP_RUNTIME.md",):
    assert (ROOT / src).is_file(), src
print("misns5 co-op contract passed: %d objects, %d paths, %d scripted path/label names, 25 Titan anchors; %d unused paths and %d unused objects documented"
      % (len(objects), len(paths), len(used) + len(handles), len(unused_paths), len(unused_objects)))
