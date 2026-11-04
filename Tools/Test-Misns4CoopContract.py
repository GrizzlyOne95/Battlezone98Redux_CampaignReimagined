#!/usr/bin/env python3
"""misns4 co-op map contract: the labels, paths and teams Scripts/misns4cr.lua names exist in Missions/misns4cr.bzn.

Skipped (exit 0, says so) when Missions/misns4cr.bzn is not in the tree.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/misns4cr.bzn"
if not bzn_path.is_file():
    print("misns4 co-op contract SKIPPED: Missions/misns4cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = misns4\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = misns4cr.bzn" in text

# ---------------------------------------------------------------- objects and teams
objects, starts = {}, []
for block in text.split("[GameObject]\n")[1:]:
    label = re.search(r"^label = (.*)$", block, re.M)
    odf = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)[1]
    team = int(re.search(r"^team \[1\] =\n(\d+)$", block, re.M)[1])
    perceived = re.search(r"^perceivedTeam \[1\] =\n(-?\d+)$", block, re.M)
    assert perceived and 0 <= int(perceived[1]) <= 15, "native visibility requires a real perceived team: " + str(label and label[1])
    if odf == "pspwn_1":
        starts.append(team)
        continue
    assert team in (0, 1, 5), "authored teams are neutral, the Soviet side or the CCA on 5: %s team %d" % (odf, team)
    assert int(perceived[1]) == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        objects.setdefault(label[1], (odf, team))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
paths = []
for path in text.split("[AiPath]\n")[1:]:
    head = path.split("pointCount", 1)[0]
    label = re.search(r"^label = (.*)$", head, re.M)
    if label:
        paths.append(label[1])
assert not any(team == 2 for _, team in objects.values()), "nothing is left on the authored team 2"
assert not any(o == "svhaul" for o, _ in objects.values()), "the convoy is scripted, never authored (AddObject must not pre-register)"
assert objects["svrecy0_recycler"] == ("svrecy", 1)
assert objects["avartl0_howitzer"] == ("avartl", 5), "the authored howitzer is CCA team 5"

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/misns4cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"(?s)--\[\[.*?\]\]", "", live)
live = "\n".join(line for line in live.split("\n") if not line.lstrip().startswith("--"))
used = set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live))
used |= set(re.findall(r'Goto\([^,]+, "(\w+)"\)', live))
used |= set(re.findall(r'Distance\([^,]+, "(\w+)"\)', live))
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
assert {"spawn1", "spawn2", "spawn3", "spawn4", "sbridge", "goal", "camerapt", "warn1", "escort", "wakeup", "counter",
        "tower1", "tower2", "power1", "power2", "svcnst"} <= used, "the contract covers every path the mission uses"
restored_paths = set(re.findall(r'PathExists\("(\w+)"\)', lua_full))
assert restored_paths == {"spawn4", "sbridge", "spawn3"} and restored_paths <= set(paths), "restorations are gated on real paths"

# ---------------------------------------------------------------- the runtime configuration only names real content
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local BuildObject =", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects, "rally point is a map object"
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
for name in re.findall(r'"(\w+)"', fallback):
    assert name in paths, "fallback spawn entry exists: " + name
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'failDes = "misns4l1.des"' in config
scaled = set(re.findall(r"(\w+) = true", re.search(r"scaledOdfs = \{([^}]*)\}", config)[1]))
cr_code = "\n".join(line for block in re.findall(region, lua_full) for line in block.split("\n") if not line.lstrip().startswith("--"))
cr_built = set(re.findall(r'BuildObject\("(\w+)"', cr_code))
assert cr_built == {"avltnk", "avhraz", "avtank"}, "the CR regions build exactly the restorations: " + str(cr_built)
built_enemy = set(re.findall(r'BuildObject\("(\w+)", 2,', live)) | cr_built
assert {"avfigh", "avtank", "avltnk", "avrckt", "avturr", "avscav", "avrecy"} == scaled, scaled
assert scaled <= built_enemy, "every scaled ODF is one the mission builds on the enemy team"

# ---------------------------------------------------------------- stock AIP bug
assert 'local AIP = { ["misns4.aip"] = "crns4.aip" }' in lua_full, "the AIP substitution is present"
aip = (ROOT / "ODF/crns4.aip").read_text(encoding="utf-8", errors="replace")
items = re.findall(r'(?m)^\s*\d+,\s*"(\w+)"', aip)
assert items and all(i.startswith("av") for i in items), "crns4.aip builds only American items: " + str([i for i in items if not i.startswith("av")])

# ---------------------------------------------------------------- weather sites belong to this map
assert 'sites = "CRIoSitesS4"' in config and 'module = "CRIoWeather"' in config
sites = ROOT / "Scripts/CRIoSitesS4.lua"
assert sites.is_file(), "generated Io sites are shipped"
site_text = sites.read_text(encoding="utf-8")
assert 'mission = "misns4"' in site_text, "generated Io sites belong to misns4"
pools = len(re.findall(r"\{ x = [\d.-]+, z = [\d.-]+, weight", site_text))
assert pools >= 300, "lava pools present: %d" % pools
vent_labels = re.findall(r'label = "(eggeizr\d+_geyser)"', site_text)
assert vent_labels and all(label in objects for label in vent_labels), "every vent site is a geyser object in the map"

# ---------------------------------------------------------------- the doc accounts for what it restores and skips
doc = (ROOT / "Docs/MISNS4_COOP.md").read_text(encoding="utf-8")
for needle in ('-- BuildObject("avltnk",2,"spawn4");', '-- b2=BuildObject("avhraz",2,"sbridge");',
               '-- BuildObject("avtank",2,"spawn3");', "RESTORED_RAIDER_LTNK", "RESTORED_BRIDGE_HRAZ",
               "RESTORED_NORTH_TANK", "misns405", "Live checklist"):
    assert needle in doc, "the doc covers: " + needle
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("misns4 co-op contract passed: %d objects, %d paths, %d scripted path names, %d Io pools, %d vents"
      % (len(objects), len(paths), len(used), pools, len(vent_labels)))
