#!/usr/bin/env python3
"""misns6 co-op map contract: the labels, paths and teams Scripts/misns6cr.lua names exist in Missions/misns6cr.bzn.

Skipped (exit 0, says so) when Missions/misns6cr.bzn is not in the tree.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/misns6cr.bzn"
if not bzn_path.is_file():
    print("misns6 co-op contract SKIPPED: Missions/misns6cr.bzn is not present yet")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = misns6\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = misns6cr.bzn" in text

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
    assert team in (0, 1, 5), "authored teams are neutral, the Soviet side or the Black Dogs on 5: %s team %d" % (odf, team)
    if label and label[1] == "abcafe8_i76building":
        # The command centre is a Black Dog building (team 5) that keeps its team-1 disguise on purpose.
        assert (team, perceived) == (5, 1), "the disguised command centre keeps team 5 / perceived team 1"
    else:
        assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        objects.setdefault(label[1], (odf, team))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
paths, unlabeled = [], 0
for path in text.split("[AiPath]\n")[1:]:
    label = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if label:
        paths.append(label[1])
    else:
        unlabeled += 1

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/misns6cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--\[=\[.*?\]=\]|--\[\[.*?\]\]", "", live, flags=re.S)
live = re.sub(r"--[^\n]*", "", live)
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
used = set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live))
used |= set(re.findall(r'(?:Goto|Mine)\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'Distance\(\w+, "(\w+)"', live))
used |= set(re.findall(r'mine_paths = \{([^}]*)\}', live)[0].replace('"', "").replace(" ", "").split(","))
used -= {"m", "s"}  # the "m" .. i / "s" .. i concatenations
used |= {"s1", "s2", "s3", "m1", "m2", "m3"}
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
for label in ("svrecy0_recycler", "absilo0_scrapsilo", "avartl3_howitzer", "avartl4_howitzer", "abcafe8_i76building"):
    assert label in objects, label
assert objects["svrecy0_recycler"] == ("svrecy", 1) and objects["absilo0_scrapsilo"] == ("absilo", 5)
for label in ("avturr0_turrettank", "avturr1_turrettank", "defender1", "defender2", "avartl3_howitzer", "avartl4_howitzer"):
    assert objects[label][1] == 5, "the defended guns are Black Dogs on team 5: " + label
assert not any(team == 2 for _, team in objects.values()), "nothing is left on the authored team 2"

# ---------------------------------------------------------------- the runtime configuration only names real content
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local BuildObject =", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects, "rally point is a map object"
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
for name in re.findall(r'"(\w+)"', fallback):
    assert name in paths, "fallback spawn entry exists: " + name
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRTitanSitesS6"' in config and 'module = "CRTitanWeather"' in config
sites = ROOT / "Scripts/CRTitanSitesS6.lua"
assert sites.is_file(), "the generated Titan sites for this map exist"
assert 'mission = "misns6"' in sites.read_text(encoding="utf-8"), "generated Titan sites belong to misns6"
assert (ROOT / "Scripts/CRTitanWeather.lua").is_file()
scaled = set(re.findall(r"(\w+) = true", re.search(r"scaledOdfs = \{([^}]*)\}", config)[1]))
spawned = set(re.findall(r'"(\w+)"', live))  # BuildObject literals and the counter-attack odf list
assert scaled <= spawned and "avmine" not in scaled, "scaled ODFs are enemy raiders the body builds; the mines are not scaled"

# ---------------------------------------------------------------- the AIP substitution
assert 'local AIP = { ["misns6.aip"] = "crns6.aip" }' in lua_full, "stock svturr AIP is mapped to crns6.aip"
aip = (ROOT / "ODF/crns6.aip").read_text(encoding="utf-8", errors="replace")
items = re.findall(r'(?m)^\s*\d+,\s*"(\w+)"', aip)
assert items and all(i.startswith("av") for i in items), "every build item of crns6.aip is American: " + str(items)

# ---------------------------------------------------------------- the doc accounts for every authored path
doc = (ROOT / "Docs/MISNS6_COOP.md").read_text(encoding="utf-8")
unused = set(paths) - used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
for name in ("check1", "check2", "check3", "check4", "counter2", "counter3", "counter4", "counter5", "spawn1"):
    assert name in paths and ("`" + name + "`") in doc, "cut-content path accounted for: " + name
assert unlabeled == 3, "three unlabeled sowing routes ship in the map (documented as unlabeled)"
assert "unlabeled" in doc
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("misns6 co-op contract passed: %d objects, %d labeled paths (+%d unlabeled), %d scripted path/label names, Titan sites present"
      % (len(objects), len(paths), unlabeled, len(used) + len(handles)))
