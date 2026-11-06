#!/usr/bin/env python3
"""bdmisn01 co-op map contract: the labels, paths and teams Scripts/bd01cr.lua names exist in Missions/bd01cr.bzn.

Skipped (exit 0, says so) when Missions/bd01cr.bzn is not in the tree. The vxt, the Config ini files and the
mpdes are checked only when present.
"""
from pathlib import Path
import math
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/bd01cr.bzn"
if not bzn_path.is_file():
    print("bdmisn01 co-op contract SKIPPED: Missions/bd01cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = bdmisn01\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = bd01cr.bzn" in text

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
    assert team in (0, 1), "authored teams are neutral or the Black Dog side: %s team %d" % (odf, team)
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        pos = [float(re.search(r"^  posit_%s \[1\] =\n(.*)$" % axis, block, re.M)[1]) for axis in "xyz"]
        objects.setdefault(label[1], (odf, team, pos))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert not any(team == 2 for _, team, _ in objects.values()), "nothing is left on the authored team 2"
assert not any(o in ("cvfigh", "cvltnk") for o, _, _ in objects.values()), "the map has no authored enemies: Lua spawns them all"
paths = {}
for path in text.split("[AiPath]\n")[1:]:
    m = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if m:
        body = path.split("pathType")[0]
        xs = [float(v) for v in re.findall(r"^  x \[1\] =\n(.*)$", body, re.M)]
        zs = [float(v) for v in re.findall(r"^  z \[1\] =\n(.*)$", body, re.M)]
        assert xs and len(xs) == len(zs)
        paths[m[1]] = list(zip(xs, zs))

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/bd01cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles == {"recycler", "wingman1_bobcat", "wingman2_bobcat"}, handles
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
used = set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live))
used |= set(re.findall(r'Attacker\("\w+", "(\w+)"', live))
used |= set(re.findall(r'Goto\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'Retreat\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'Patrol\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'CameraPath\("(\w+)"', live))
used |= set(re.findall(r'GetNearestUnitOnTeam\("(\w+)"', live))
used |= set(re.findall(r'Distance\([^,]+, "(\w+)"\)', live))
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
assert {"spawn_nav_beacon", "spawn_attack_ambush", "ambush_patrol_path", "ambush_retreat_path", "spawn_attack_wave1",
        "spawn_attack_wave1a", "spawn_attack_wave2", "spawn_attack_wave2a", "camera_start_arc", "camera_attack_view",
        "start_path_recycler", "start_path_wingman1", "start_path_wingman2"} == used, used

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local NativeBuildObject", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects and objects[rally][0] == "bvrecye", "rally point is the shared recycler"
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
fallback_paths = re.findall(r'"(\w+)"', fallback)
assert fallback_paths and len(set(fallback_paths)) == len(fallback_paths), "there are distinct alternative approaches"
for name in fallback_paths:
    assert name in paths, "fallback spawn entry exists: " + name
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRGanymedeSitesBD01"' in config and 'module = "CREuropaWeather"' in config
assert '"EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge"' in config, "the Europa wire ops are registered"
assert 'failDes = "bd01lsea.des"' in config
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
body_odfs = set(re.findall(r'BuildObject\("(\w+)", 2,', live))
body_odfs |= set(re.findall(r'Attacker\("(\w+)", "', live))  # Attacker(odf, path, decloak) builds on team 2
assert scaled == body_odfs == {"cvfigh", "cvltnk"}, (scaled, body_odfs)
direct = set(re.search(r"DIRECT_PATHS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
assert direct == {"spawn_attack_ambush", "spawn_attack_wave1"} and direct <= used
# Only the cloaked ambush and the camera pair bypass the tickets; the second pair of wave 1 and wave 2 are scaled.
assert set(re.findall(r'Attacker\("\w+", "(\w+)"', live)) == {"spawn_attack_wave1", "spawn_attack_wave1a", "spawn_attack_wave2",
                                                               "spawn_attack_wave2a"}
assert 'BuildObject("cvfigh", 2, "spawn_attack_ambush")' in live

# The network shot fallback uses the flight time of each map path: length / (speed / 100) seconds.
eta = {k: float(v) for k, v in re.findall(r"(\w+) = ([\d.]+)", re.search(r"CAMERA_ETA = \{([^}]*)\}", cr_text)[1])}
shots = {path: speed for path, speed in re.findall(r'CameraPath\("(\w+)", \d+, (\d+),', live)}
assert set(eta) == set(shots) == {"camera_start_arc", "camera_attack_view"}, (eta, shots)
for path, seconds in eta.items():
    pts = paths[path]
    length = sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
    expected = length * 100 / int(shots[path])
    assert abs(seconds - expected) < 0.1, "CAMERA_ETA[%s] = %s, map says %.2f" % (path, seconds, expected)

# ---------------------------------------------------------------- the weather's vent and sites
sites_path = ROOT / "Scripts/CRGanymedeSitesBD01.lua"
sites = sites_path.read_text(encoding="utf-8")
assert 'mission = "bdmisn01"' in sites, "generated Ganymede sites belong to bdmisn01"
vents = re.findall(r'\{ x = ([\d.]+), y = [\d.]+, z = ([\d.]+), label = "(\w+)"', sites)
assert len(vents) == 1 and vents[0][2] == "eggeizr11_geyser", "one vent: the base geyser"
geyser = objects["eggeizr11_geyser"][2]
assert abs(float(vents[0][0]) - geyser[0]) < 0.1 and abs(float(vents[0][1]) - geyser[2]) < 1, "the vent sits on the geyser object"
assert "TriggerPlume(1)" in cr_text and "GetVentSites() > 0" in cr_text, "the plume beat is guarded and aims at the first vent"
assert (ROOT / "Scripts/CREuropaWeather.lua").is_file()

# ---------------------------------------------------------------- audio: every line has a subtitle text
wavs = sorted(set(re.findall(r'"(bd01\d+\.wav)"', live, re.I)), key=str.lower)
assert len(wavs) == 9, wavs  # bd01001..bd01009: the whole catalogue is in use
for wav in wavs:
    assert (ROOT / "Text" / (wav[:-4].lower() + ".txt")).is_file(), "no subtitle for " + wav
assert {w.lower() for w in wavs} == {"bd010%02d.wav" % n for n in range(1, 10)}, "no unused voice line is left"
# The debrief .des files (bd01win, bd01lsea, bd01lseb, bd01lsec) ship with the game, not in this tree.

# ---------------------------------------------------------------- companions, checked only when present
ini = ROOT / "Config/bd01cr.ini"
if ini.is_file():
    ini_text = ini.read_text(encoding="utf-8")
    assert 'gameType = "S"' in ini_text and 'minPlayers = "2"' in ini_text and 'maxPlayers = "4"' in ini_text
    print("  Config/bd01cr.ini checked")
crbd = ROOT / "Config/crbd.ini"
if crbd.is_file():
    assert re.search(r'\[MISSION1\][^\[]*missionBZN = "bd01cr\.bzn"', crbd.read_text(encoding="utf-8")), "campaign entry 1 is this map"
    print("  Config/crbd.ini checked")
vxt = ROOT / "Missions/bd01cr.vxt"
if vxt.is_file():
    assert re.search(r"\bbvtank\b", vxt.read_text(encoding="utf-8")), "the vehicle list offers the Grizzly"
    print("  Missions/bd01cr.vxt checked")
mpdes = ROOT / "bd01cr.mpdes"
if mpdes.is_file():
    assert "Close Target Wrecky" in mpdes.read_text(encoding="utf-8")
    print("  bd01cr.mpdes checked")

# ---------------------------------------------------------------- the doc accounts for every map path
doc = (ROOT / "Docs/BDMISN01_COOP.md").read_text(encoding="utf-8")
all_used = used | set(fallback_paths)
unused = set(paths) - all_used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused == {"edge_path", "outer_limits"}, unused
assert "`spawn_attack_wave1_1`" in doc, "the extra approach restored as a fallback is documented"
for section in ("## Layout", "## Teams and ownership", "## Scaling and concealed arrivals", "## Humans' result",
                "## Cinematics are shared", "## Restored content", "## Stock bugs and co-op fixes in the CR layer",
                "## Weather: Ganymede", "## Tests", "## Inferences and open questions", "## Live checklist"):
    assert section in doc, "doc section missing: " + section
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("bdmisn01 co-op contract passed: %d objects, %d paths, %d scripted path/label names, Ganymede sites present; %d paths unused (documented)"
      % (len(objects), len(paths), len(used) + len(handles), len(unused)))
