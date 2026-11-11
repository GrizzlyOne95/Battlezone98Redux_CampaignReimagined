#!/usr/bin/env python3
"""misns8 co-op map contract: the labels, paths and teams Scripts/misns8cr.lua names exist in Missions/misns8cr.bzn.

Skipped (exit 0, says so) when Missions/misns8cr.bzn is not in the tree.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/misns8cr.bzn"
if not bzn_path.is_file():
    print("misns8 co-op contract SKIPPED: Missions/misns8cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = misns8\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = misns8cr.bzn" in text

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
    assert team in (0, 1, 5), "authored teams are neutral, the CCA on 1 or the Black Dogs on 5: %s team %d" % (odf, team)
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        objects.setdefault(label[1], (odf, team))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
paths = []
for path in text.split("[AiPath]\n")[1:]:
    found = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if found:  # a few authored paths carry no label
        paths.append(found[1])

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/misns8cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--\[=\[.*?\]=\]", "", live, flags=re.S)
live = re.sub(r"(?m)--[^\n]*", "", live)
handles = set(re.findall(r'GetHandle\s*\("(\w+)"\)', live))
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
used = set(re.findall(r'BuildObject\s*\("\w+", \d, "(\w+)"\)', live))
used |= set(re.findall(r'(?:Goto|Dropoff)\([^,()]+, "(\w+)"', live))
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
# the CR layer's own names
layer = "".join(re.findall(region, lua_full))
layer_paths = set(re.findall(r'(?:PathExists|BuildObject\("spcamr", 1,)\s*\(?"(\w+)"', layer))
layer_paths |= set(re.findall(r'"(\w+_?\w*post\w*|american_spawn|last_nav_spawn)"', layer))
assert layer_paths <= set(paths), "every path the CR layer names exists: " + str(layer_paths - set(paths))
layer_objects = set(re.findall(r'rallyPoints = \{ \[0\] = "(\w+)" \}', layer))
assert layer_objects <= set(objects), "rally point is a map object"
assert objects["avrecycle"] == ("bvrec8", 5) and objects["avmuf"] == ("bvmuf", 5)
assert objects["svrecycle"] == ("svrecy8", 1) and objects["svmuf"] == ("savmf", 1)
for label in ("powerplant1", "powerplant2", "basetower1", "basetower2"):
    assert objects[label][1] == 5, "the Black Dog base is on team 5: " + label
assert objects["cam"][1] == 1 and objects["basecam"][1] == 1, "nav beacons belong to the humans' side"
for label in ("dis_geyser1", "dis_geyser2", "center_geyser", "first_geyser", "last_geyser", "sv_geyser", "av_geyser",
              "temp_geyser", "turret_geyser", "avmuf_geyser"):
    assert objects[label][0] == "eggeizr1", "geyser " + label
assert not any(team == 2 for _, team in objects.values()), "nothing is left on the authored team 2"
assert not any(odf == "savtnk" for odf, _ in objects.values()), "the SAVs are never authored: the humans build them"

# ---------------------------------------------------------------- the runtime configuration
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local RESTORED =", 1)[0]
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
for name in re.findall(r'"(\w+)"', fallback):
    assert name in paths, "fallback spawn entry exists: " + name
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRTitanSitesS8"' in config and 'module = "CRTitanWeather"' in config
assert '"TitanState", "TitanRoll"' in config, "the Titan wire ops are whitelisted"
sites = ROOT / "Scripts/CRTitanSitesS8.lua"
assert sites.is_file() and 'mission = "misns8"' in sites.read_text(encoding="utf-8"), "generated Titan sites belong to misns8"
weather = (ROOT / "Scripts/CRTitanWeather.lua").read_text(encoding="utf-8")
for api in ("SetTargetLevel", "Roll", "SkyState", "Init", "Update", "AnnounceState", "ApplyNetEvent", "Save", "Load", "Shutdown",
            "OnObjectCreated"):
    assert re.search(r"function V\.%s\(" % api, weather), "CRTitanWeather exports " + api
for beat in ("convoy_start", "recycle_pack", "sav_attack", "sav_payback", "general_scream", "game_over"):
    assert "M." + beat + " = " in (ROOT / "Scripts/misns8.lua").read_text(encoding="utf-8"), "beat state field exists: " + beat
unused = [p for p in paths if p not in used and p not in layer_paths]
doc = (ROOT / "Docs/MISNS8_COOP.md").read_text(encoding="utf-8")
for name in unused:
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
for name in ("a_post1", "t2post", "t3post", "last_nav_spawn"):
    assert "`" + name + "`" in doc
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("misns8 co-op contract passed: %d objects, %d paths, %d scripted path/label names, %d unused paths documented"
      % (len(objects), len(paths), len(used) + len(handles), len(unused)))
