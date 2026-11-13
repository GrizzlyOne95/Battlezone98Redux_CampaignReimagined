#!/usr/bin/env python3
"""misns2 co-op map contract: the labels, paths and teams Scripts/misns2cr.lua names exist in Missions/misns2cr.bzn.

Skipped (exit 0, says so) when Missions/misns2cr.bzn is not in the tree.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
bzn_path = ROOT / "Missions/misns2cr.bzn"
if not bzn_path.is_file():
    print("misns2 co-op contract SKIPPED: Missions/misns2cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = misns2\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = misns2cr.bzn" in text

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
    assert team in (0, 1), "authored teams are neutral or the Soviet side: %s team %d" % (odf, team)
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        objects.setdefault(label[1], (odf, team))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert not any(team == 2 for _, team in objects.values()), "nothing is left on the authored team 2"
assert not any(o in ("bvtank", "bvraz", "bvartl") for o, _ in objects.values()), "the map has no authored enemies: Lua spawns them all"
paths = []
for path in text.split("[AiPath]\n")[1:]:
    m = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if m:
        paths.append(m[1])

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/misns2cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--\[==\[.*?\]==\]", "", live, flags=re.S)  # the DLL's disabled code stays disabled
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert "navmine" not in handles, "the cut navmine lookup stays a comment"
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
used = set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live))
used |= set(re.findall(r'(?:Goto)\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'Retreat\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'CameraPath\("(\w+)"', live))
used |= set(re.findall(r'GetNearestVehicle\("(\w+)", 1\)', live))
used |= set(re.findall(r'Distance\([^,]+, "(\w+)"\)', live))
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
assert {"bdsp1", "bdsp2", "bdsp3", "bdsp4", "bdsp5", "bdspmain", "bdnet4", "bdnet9", "bdnet12", "nav1", "nav3",
        "platooncam", "cinpath1"} <= used
assert {str(n) for n in range(100, 111)} <= used and {"mine%d" % n for n in range(1, 20)} <= used
assert {"bdnet%d" % n for n in range(7, 15)} <= used

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local NativeBuildObject", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects, "rally point is a map object"
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
fallback_paths = re.findall(r'"(\w+)"', fallback)
assert fallback_paths, "there are alternative staging points"
for name in fallback_paths:
    assert name in paths, "fallback spawn entry exists: " + name
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRVenusSitesS2"' in config and 'module = "CRVenusWeather"' in config
assert 'failDes = "misns2l1.des"' in config
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
body_odfs = set(re.findall(r'BuildObject\("(\w+)", 2,', live))
assert scaled <= body_odfs and scaled == {"bvtank", "bvraz", "bvartl"}, scaled
sites = ROOT / "Scripts/CRVenusSitesS2.lua"
assert sites.is_file() and 'mission = "misns2"' in sites.read_text(encoding="utf-8"), "generated Venus sites belong to misns2"
for module in ("CRVenusWeather", "CRVenusMap"):
    assert (ROOT / ("Scripts/%s.lua" % module)).is_file(), module

# ---------------------------------------------------------------- restorations are gated on what the map carries
restored_paths = set(re.findall(r'"(cinpath\d|nav\d|bdsp\d)"', cr_text)) | {"bdnet%d" % i for i in range(1, 7)}
assert restored_paths <= set(paths), "restored content only names map paths: " + str(restored_paths - set(paths))
for label in ("apcamr5_camerapod", "sblpad59_i76building", "cam1"):
    assert label in objects
assert "nav1route" in live and "apcamr5_camerapod" in live  # the restored film's second shot targets this pod
# Audio: every line the body or the CR layer names has a subtitle text.
for wav in sorted(set(re.findall(r'"(misns\d+\.wav)"', lua_full))):
    assert (ROOT / "Text" / (wav[:-4] + ".txt")).is_file(), "no subtitle for " + wav
# The debrief .des files (misns2w1.des, misns2l1.des) ship with the game, not in this tree.

# ---------------------------------------------------------------- the doc accounts for every map path and cut label
doc = (ROOT / "Docs/MISNS2_COOP.md").read_text(encoding="utf-8")
all_used = used | restored_paths
unused = set(paths) - all_used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert "`navmine`" in doc and "navmine" not in objects, "the absent navmine label is documented"
assert unused == {"nav2", "nav4", "nav6", "nav7", "nav8", "tursp1", "tursp2", "cinpath3", "edge_path", "alt_trigger_wave1",
                  "alt_spawn_wave1", "alt_trigger_artillery&mines"}, unused
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("misns2 co-op contract passed: %d objects, %d paths, %d scripted path/label names, Venus sites present; %d paths unused (documented)"
      % (len(objects), len(paths), len(used) + len(handles), len(unused)))
