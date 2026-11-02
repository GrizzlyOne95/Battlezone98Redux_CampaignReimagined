#!/usr/bin/env python3
"""bdmisn09 co-op map contract: the labels, paths and teams Scripts/bdmisn09cr.lua names exist in Missions/bdmisn09cr.bzn.

Skipped (exit 0, says so) when Missions/bdmisn09cr.bzn is not in the tree. The companion files (Missions/bdmisn09cr.vxt,
Config/bdmisn09cr.ini, the MISSION9 entry of Config/crbd.ini) are checked only when they are present.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/bdmisn09cr.bzn"
if not bzn_path.is_file():
    print("bdmisn09 co-op contract SKIPPED: Missions/bdmisn09cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = bdmisn09\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = bdmisn09cr.bzn" in text

# ---------------------------------------------------------------- objects and teams
objects, starts, perceived_of = {}, [], {}
for block in text.split("[GameObject]\n")[1:]:
    label = re.search(r"^label = (.*)$", block, re.M)
    odf = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)[1]
    team = int(re.search(r"^team \[1\] =\n(\d+)$", block, re.M)[1])
    perceived = int(re.search(r"^perceivedTeam \[1\] =\n(\d+)$", block, re.M)[1])
    if odf == "pspwn_1":
        starts.append(team)
        continue
    assert team in (0, 1, 5), "authored teams are neutral, Black Dog or the co-op enemy: %s team %d" % (odf, team)
    if label:
        objects.setdefault(label[1], (odf, team))
        perceived_of.setdefault(label[1], perceived)
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert not any(team == 2 for _, team in objects.values()), "nothing is left on the authored team 2"
for i in range(1, 6):
    assert objects["cvtnk%d" % i] == ("cvtnkb", 5) and perceived_of["cvtnk%d" % i] == 5, "the five tracked tanks are Chinese craft"
assert objects["portal"] == ("cbport", 5)
# the disguise: the authored player APC is a Chinese APC on team 1 perceived as the co-op enemy
assert objects["svapc2_apc"] == ("cvapc", 1) and perceived_of["svapc2_apc"] == 5
paths = {}
for path in text.split("[AiPath]\n")[1:]:
    m = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if m:
        paths[m[1]] = re.findall(r"x \[1\] =\n([-\d.e+]+)\n\s*z \[1\] =\n([-\d.e+]+)", path)

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/bdmisn09cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--[^\n]*", "", live)
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles == {"portal"} and 'GetHandle("cvtnk" .. i)' in live, handles
handles |= {"cvtnk%d" % i for i in range(1, 6)}
assert handles <= set(objects), "every GetHandle label is a map object"
used = set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live))
used |= set(re.findall(r'\{"\w+", "(spawn_deviate\d)"\}', live))
used |= set(re.findall(r'Goto\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'Distance\([^,]+, "(\w+)"\)', live))
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
assert {p for p in used if p.startswith("spawn_deviate")} == {"spawn_deviate%d" % i for i in range(1, 7)}
assert {"tank_path", "trigger_1", "last_one", "spawn_beacon1", "spawn_beacon2", "spawn_beacon3"} <= used

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local NativeIsOdf", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects, "the rally point is a map object that travels with the convoy"
fallback = re.findall(r'"(\w+)"', re.search(r"fallbackEntries = \{([^}]*)\}", config)[1])
assert sorted(fallback) == sorted("spawn_deviate%d" % i for i in range(1, 7)) and set(fallback) <= set(paths)
assert "enemyTeam = ENEMY_TEAM" in config and "local ENEMY_TEAM = 5" in cr_text and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'failDes = "bd09lose.des"' in config and "scrapPerGuest = 0" in config
assert 'module = "CRElysiumWeather"' in config and 'sites = "CRElysiumSitesBD09"' in config
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
body_odfs = set(re.findall(r'\{"(\w+)", "spawn_deviate\d"\}', live)) | set(re.findall(r'BuildObject\("(\w+)", 2,', live))
assert scaled == body_odfs, (scaled, body_odfs)
sites_path = ROOT / "Scripts/CRElysiumSitesBD09.lua"
sites = sites_path.read_text(encoding="utf-8")
assert 'mission = "bdmisn09"' in sites
for label in re.findall(r'label = "(\w+)"', sites):
    assert label in objects and objects[label][0] == "eggeizr1", "the site file's vent is a map geyser: " + label
assert (ROOT / "Scripts/CRElysiumWeather.lua").is_file()
assert "RESTORED_COMPLETED_OBJECTIVE" in cr_text

# ---------------------------------------------------------------- audio and objectives
wavs = set(re.findall(r'"(bd\d+\.wav)"', live))
assert wavs == {"bd0900%d.wav" % n for n in range(1, 9)}, wavs
for wav in sorted(wavs):
    assert (ROOT / "Text" / (wav[:-4] + ".txt")).is_file(), "no subtitle for " + wav
assert not [p for p in (ROOT / "Text").glob("bd09*.txt") if p.stem + ".wav" not in wavs], "every shipped bd09 line is used"
assert set(re.findall(r'"(bd09\w+\.des)"', live)) == {"bd09lose.des", "bd09lseb.des", "bd09win.des"}

# ---------------------------------------------------------------- companion files, only when present
vxt = ROOT / "Missions/bdmisn09cr.vxt"
if vxt.is_file():
    allowed = {line.split(",")[0].strip() for line in vxt.read_text(encoding="latin-1").splitlines() if line.strip()}
    assert allowed == {"cvapc"}, "every human starts in the stolen Chinese APC: " + str(allowed)
else:
    print("note: Missions/bdmisn09cr.vxt not present, vehicle list not checked")
ini = ROOT / "Config/bdmisn09cr.ini"
if ini.is_file():
    body = ini.read_text(encoding="utf-8")
    assert 'mapType = "multiplayer"' in body and 'gameType = "S"' in body and 'maxPlayers = "4"' in body
else:
    print("note: Config/bdmisn09cr.ini not present, multiplayer listing not checked")
crbd = ROOT / "Config/crbd.ini"
if crbd.is_file():
    assert re.search(r'\[MISSION9\][^\[]*missionBZN = "bdmisn09cr\.bzn"', crbd.read_text(encoding="utf-8")), "crbd.ini MISSION9 points at the co-op map"
else:
    print("note: Config/crbd.ini not present, campaign entry not checked")

# ---------------------------------------------------------------- the doc accounts for every map path and cut block
doc = (ROOT / "Docs/BDMISN09_COOP.md").read_text(encoding="utf-8")
unused = set(paths) - used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused == {"edge_path", "portal_in", "camera_portal_escape"}, unused
for word in ("SetPerceivedTeam(user, 2)", "GREEN", "RESTORED_COMPLETED_OBJECTIVE", "Stock bugs fixed in the CR layer", "Live checklist"):
    assert word in doc, "the doc accounts for " + word
print("bdmisn09 co-op contract passed: %d objects, %d paths, %d scripted path/label names, %d vents; %d paths unused (documented)"
      % (len(objects), len(paths), len(used) + len(handles), len(re.findall(r'label = "', sites)), len(unused)))
