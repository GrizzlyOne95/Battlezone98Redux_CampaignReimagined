#!/usr/bin/env python3
"""bdmisn02 co-op map contract: the labels, paths and teams Scripts/bdmisn02cr.lua names exist in Missions/bdmisn02cr.bzn.

Skipped (exit 0, says so) when Missions/bdmisn02cr.bzn is not in the tree. The companion files (Missions/bdmisn02cr.vxt,
Config/bdmisn02cr.ini, the MISSION2 entry of Config/crbd.ini) are checked only when they are present.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/bdmisn02cr.bzn"
if not bzn_path.is_file():
    print("bdmisn02 co-op contract SKIPPED: Missions/bdmisn02cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = bdmisn02\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = bdmisn02cr.bzn" in text

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
    assert team in (0, 1, 5), "authored teams are neutral, Black Dog or the co-op enemy: %s team %d" % (odf, team)
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        objects.setdefault(label[1], (odf, team))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert not any(team == 2 for _, team in objects.values()), "nothing is left on the authored team 2"
turrets = {k: v for k, v in objects.items() if k.startswith("enemy_turret")}
assert sorted(turrets) == ["enemy_turret1", "enemy_turret2", "enemy_turret3", "enemy_turret4"]
assert all(team == 5 and odf.startswith("cv") for odf, team in turrets.values()), "the four cloaked turrets are Chinese craft on team 5"
assert objects["recycler"] == ("bvrecye", 1) and objects["player_grizzly"][1] == 1
paths = []
for path in text.split("[AiPath]\n")[1:]:
    m = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if m:
        paths.append(m[1])
# The map-native AOI still names team 2 (the generator moved the units, not the area of interest): it is inert for
# this mission and documented.
assert re.search(r"\[AOI\]\nundefptr = \w+\nteam \[1\] =\n2\n", text), "the AOI team is documented below if it changes"

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/bdmisn02cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--\[\[.*?\]\]", "", live, flags=re.S)  # the DLL's disabled code stays disabled
live = re.sub(r"--[^\n]*", "", live)
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
assert handles == {"recycler", "enemy_turret1", "enemy_turret2", "enemy_turret3", "enemy_turret4"}, handles
used = set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live))
used |= set(re.findall(r'Goto\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'CameraPath(?:Dir)?\("(\w+)"', live))
used |= set(re.findall(r'Distance\([^,]+, "(\w+)"\)', live))
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
# the spawn paths the body names are exactly the ones the stage list and the scaling rules reason about
spawns = {p for p in used if p.startswith("spawn_") or p == "fighter_1"}
assert len(spawns) == 21, spawns

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local NativeBuildObject", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects and objects[rally][1] == 1, "rally point is the shared recycler"
fallback_paths = re.findall(r'"(\w+)"', re.search(r"fallbackEntries = \{([^}]*)\}", config)[1])
assert fallback_paths, "there are alternative staging points"
for name in fallback_paths:
    assert name in paths and name.startswith("spawn_"), "fallback spawn entry exists: " + name
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRGanymedeSitesBD02"' in config and 'module = "CREuropaWeather"' in config
assert 'failDes = "bd02lose.des"' in config
stage = set(re.findall(r"(\w+) = true", re.search(r"STAGE_PATHS = \{([^}]*)\}", cr_text)[1]))
assert stage <= set(paths) and stage <= spawns and len(stage) == 9, stage
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
body_odfs = set(re.findall(r'BuildObject\("(\w+)", 2,', live))
assert scaled <= body_odfs and scaled == {"cvfigh", "cvltnk", "cvtnk"} and "cvhraz" in body_odfs - scaled, scaled
# the camera subjects are stage props (a ticket cannot be a camera target)
for subject in ("spawn_wave1_scout1", "spawn_enemy_tank"):
    assert subject in stage, subject
sites_path = ROOT / "Scripts/CRGanymedeSitesBD02.lua"
sites = sites_path.read_text(encoding="utf-8")
assert sites_path.is_file() and 'mission = "bdmisn02"' in sites, "generated Ganymede sites belong to bdmisn02"
vents = re.findall(r'label = "(\w+)"', sites)
assert vents == ["eggeizr10_geyser", "eggeizr11_geyser"], vents
for label in vents:
    assert label in objects and objects[label][0] == "eggeizr1", "the site file's vent is a map geyser: " + label
    assert '"%s"' % label in cr_text, "the weather beats name the vent: " + label
assert (ROOT / "Scripts/CREuropaWeather.lua").is_file()
assert 'ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" }' in config

# ---------------------------------------------------------------- restorations are gated on what the map carries
route_paths = set(re.findall(r'"(path_bomber_\d_attackpath)"', cr_text))
assert route_paths == {"path_bomber_1_attackpath", "path_bomber_2_attackpath"} and route_paths <= set(paths)
assert "RESTORED_BOMBER_ROUTES" in cr_text and "PathExists" in cr_text
# Audio: every line the body names has a subtitle text, and every shipped bd02 line is used.
wavs = set(re.findall(r'"(bd\d+\.wav)"', live))
assert wavs == {"bd0200%d.wav" % n for n in range(1, 10)}, wavs
for wav in sorted(wavs):
    assert (ROOT / "Text" / (wav[:-4] + ".txt")).is_file(), "no subtitle for " + wav
# The debriefs (bd02lose.des, bd02win.des) ship with the game, not in this tree; bd02lsea.des ships nowhere.
assert "bd02lsea.des" in live and 'description == "bd02lsea.des"' in cr_text, "the missing debrief is substituted in the CR layer"

# ---------------------------------------------------------------- companion files, only when present
vxt = ROOT / "Missions/bdmisn02cr.vxt"
if vxt.is_file():
    allowed = {line.split()[0] for line in vxt.read_text(encoding="latin-1").splitlines() if line.strip()}
    assert allowed and allowed <= {"bvtank", "bvltnk"}, "the vehicle list names Black Dog craft: " + str(allowed)
else:
    print("note: Missions/bdmisn02cr.vxt not present, vehicle list not checked")
ini = ROOT / "Config/bdmisn02cr.ini"
if ini.is_file():
    body = ini.read_text(encoding="utf-8")
    assert 'mapType = "multiplayer"' in body and 'gameType = "S"' in body and 'maxPlayers = "4"' in body
else:
    print("note: Config/bdmisn02cr.ini not present, multiplayer listing not checked")
crbd = ROOT / "Config/crbd.ini"
if crbd.is_file():
    assert re.search(r'\[MISSION2\][^\[]*missionBZN = "bdmisn02cr\.bzn"', crbd.read_text(encoding="utf-8")), "crbd.ini MISSION2 points at the co-op map"
else:
    print("note: Config/crbd.ini not present, campaign entry not checked")

# ---------------------------------------------------------------- the doc accounts for every map path and cut block
doc = (ROOT / "Docs/BDMISN02_COOP.md").read_text(encoding="utf-8")
all_used = used | route_paths
unused = set(paths) - all_used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused == {"edge_path", "outer_limits"}, unused
for word in ("MS_WAITFORFACTORY", "Explode", "bd02lsea.des", "AOI", "RESTORED_BOMBER_ROUTES"):
    assert word in doc, "the doc accounts for " + word
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("bdmisn02 co-op contract passed: %d objects, %d paths, %d scripted path/label names, Ganymede sites present with %d vents; %d paths unused (documented)"
      % (len(objects), len(paths), len(used) + len(handles), len(vents), len(unused)))
