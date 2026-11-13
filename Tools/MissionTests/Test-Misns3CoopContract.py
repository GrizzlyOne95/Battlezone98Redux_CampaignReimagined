#!/usr/bin/env python3
"""misns3 co-op map contract: the labels, paths and teams Scripts/misns3cr.lua names exist in Missions/misns3cr.bzn.

Skipped (exit 0, says so) when Missions/misns3cr.bzn is not in the tree.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
bzn_path = ROOT / "Missions/misns3cr.bzn"
if not bzn_path.is_file():
    print("misns3 co-op contract SKIPPED: Missions/misns3cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = misns3\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = misns3cr.bzn" in text

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
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        objects.setdefault(label[1], (odf, team))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
paths = []
for path in text.split("[AiPath]\n")[1:]:
    paths.append(re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)[1])

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/misns3cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--\[\[.*?\]\]", "", live, flags=re.S)
live = re.sub(r"--[^\n]*", "", live)
handles = set(re.findall(r'GetHandle\("([\w-]+)"\)', live))
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
used = set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live))
used |= set(re.findall(r'(?:Goto)\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'Distance\([^,]+, "([^"]+)"\)', live))
used |= {"path_%d" % i for i in range(1, 35)}  # the minefields: "path_" .. index, 1..34
assert 'BuildObject("proxmine", 2, "path_" .. index)' in live
for lo, hi in re.findall(r"for index = (\d+), (\d+) do BuildObject", live):
    assert 1 <= int(lo) <= int(hi) <= 34
# minetrig1b/2b/3b are optional: the shipped map does not carry them and the layer treats them as infinitely far.
optional = set(re.findall(r"minetrig\db", live))
assert optional == {"minetrig1b", "minetrig2b", "minetrig3b"}, optional
assert not (optional & set(paths)), "the optional triggers are still absent; update the layer notes if they were added"
assert used - optional <= set(paths), "every path the body names exists: " + str(used - optional - set(paths))
assert re.search(r"OPTIONAL_PATHS = \{ minetrig1b = true, minetrig2b = true, minetrig3b = true \}", lua_full)
assert objects["avrecy1_recycler"] == ("bvrecy", 5)
assert objects["basenav"][0] == "spcamr" and objects["avrecy"][0] == "spcamr"
for label in ("bomb1", "bomb2", "bomb3", "bomb4"):
    assert objects[label] == ("svhraz", 1), "the wing bombers are on the Soviet side: " + label
assert not any(team == 2 for _, team in objects.values()), "nothing is left on the authored team 2"
# Spawns the layer scales are enemy-side ODFs the body builds with the authored team 2 (mapped to 5).
spawned = set(re.findall(r'BuildObject\("(\w+)", 2,', live)) | {"avtank", "avfigh"}
assert spawned == {"avtank", "avfigh", "bvraz", "proxmine"}, spawned

# ---------------------------------------------------------------- the runtime configuration only names real content
config = lua_full.split("require(\"CRCCARuntime\").Create", 1)[1].split("local RESTORED =", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects, "rally point is a map object"
for name in re.findall(r'farthestTargets = \{ ([^}]*)\}', config)[0].replace('"', "").split(","):
    assert name.strip() in paths, "reach-gate target is a map path: " + name
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert "scaledOdfs = { avtank = true, avfigh = true, bvraz = true }" in config
assert 'sites = "CRIoSitesS3"' in config and 'module = "CRIoWeather"' in config
sites_path = ROOT / "Scripts/CRIoSitesS3.lua"
assert sites_path.is_file() and (ROOT / "Scripts/CRIoWeather.lua").is_file(), "the Io weather and its misns3 sites exist"
sites = sites_path.read_text(encoding="utf-8")
assert 'mission = "misns3"' in sites, "generated Io sites belong to misns3"
pools = re.search(r"pools = \{\n(.*?)\n        \},", sites, re.S)[1].count("cluster =")
assert pools == 341, "341 lava pools, got %d" % pools
vents = re.findall(r'label = "(\w+)"', sites.split("vents = {", 1)[1])
for label in vents:
    assert label in objects, "every Io vent sits on a map geyser: " + label
for src in ("Docs/CCA_COOP_RUNTIME.md", "Docs/MISNS3_COOP.md"):
    assert (ROOT / src).is_file(), src

# ---------------------------------------------------------------- the doc accounts for the map
doc = (ROOT / "Docs/MISNS3_COOP.md").read_text(encoding="utf-8")
for name in sorted(optional):
    assert "`" + name + "`" in doc, "the doc accounts for the absent optional trigger " + name
unused = set(paths) - used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
print("misns3 co-op contract passed: %d objects, %d paths, %d scripted path/label names, %d lava pools, %d vents; %d optional triggers absent"
      % (len(objects), len(paths), len(used) + len(handles), pools, len(vents), len(optional)))
