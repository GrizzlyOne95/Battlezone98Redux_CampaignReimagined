#!/usr/bin/env python3
"""chmisn01 co-op map contract: the labels, paths and teams Scripts/chmisn01cr.lua names exist in Missions/chmisn01cr.bzn.

Skipped (exit 0, says so) when Missions/chmisn01cr.bzn is not in the tree. The vxt, the Config ini files and the
mpdes are checked only when present.
"""
from pathlib import Path
import math
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/chmisn01cr.bzn"
if not bzn_path.is_file():
    print("chmisn01 co-op contract SKIPPED: Missions/chmisn01cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = chmisn01\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = chmisn01cr.bzn" in text

# ---------------------------------------------------------------- objects and teams
objects, starts, enemy_odfs, start_pos = {}, [], set(), {}
for block in text.split("[GameObject]\n")[1:]:
    label = re.search(r"^label = (.*)$", block, re.M)
    odf = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)[1]
    team = int(re.search(r"^team \[1\] =\n(\d+)$", block, re.M)[1])
    perceived = int(re.search(r"^perceivedTeam \[1\] =\n(\d+)$", block, re.M)[1])
    if odf == "pspwn_1":
        starts.append(team)
        start_pos[team] = [float(re.search(r"^  posit_%s \[1\] =\n(.*)$" % axis, block, re.M)[1]) for axis in "xyz"]
        continue
    assert team in (0, 1, 5), "authored teams are neutral, the Chinese player or the moved CCA enemy: %s team %d" % (odf, team)
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if team == 5:
        enemy_odfs.add(odf)
    if label:
        pos = [float(re.search(r"^  posit_%s \[1\] =\n(.*)$" % axis, block, re.M)[1]) for axis in "xyz"]
        objects.setdefault(label[1], (odf, team, pos))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert not any(team == 2 for _, team, _ in objects.values()), "nothing is left on the authored team 2"
assert [k for k, v in objects.items() if v[1] == 1 and v[0] != "pspwn_1"] == ["player"], "the only authored human object is the on-foot player"
assert objects["player"][0] == "csusera", "the host starts on foot (the vxt offers csusera)"
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
lua_full = (ROOT / "Scripts/chmisn01cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles == {"target_1", "target_2", "bb_tower", "sp_turret_1", "sp_turret_2", "sp_turret_3"} | {"sp_tower_%d" % i for i in range(1, 8)}, handles
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
assert objects["target_1"][0] == "sbhanga", "the hangar the guests inspect"
used = set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live))
used |= set(re.findall(r'BuildObject\("\w+", \d, "([\w.]+)"\)', live))
used |= set(re.findall(r'Airborne\("\w+", \d, "(\w+)", \d+\)', live))
used |= set(re.findall(r'Goto\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'CameraPath\("(\w+)"', live))
used |= set(re.findall(r'Distance\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'MakeExplosion\("\w+", "(\w+)"\)', live))
# A slip of the faithful port names a place the map lacks; the shared body substitutes a real one.
SLIPS = {"spawn_explosion1": "relic_loc"}
assert set(SLIPS) <= used and not (set(SLIPS) & set(paths)), "the slipped names are not map paths"
used -= set(SLIPS)
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
assert set(SLIPS.values()) <= set(paths)
assert {"wave_1", "wave_2", "wave_3", "wave_4", "wave_5", "follow_1", "follow_2", "follow_3", "follow_4", "follow_5",
        "aerial_1", "aerial_2", "aerial_3", "aerial_4", "armoury", "nav_start", "nav_tug", "nav_end",
        "relic_tug", "tug_path", "tug_defend", "tug_fail", "fighters", "fighters_to", "relic_loc", "decoy_units", "recycler",
        "cut_end"} == used, used
for name, expect in (("wave_1", 1), ("wave_5", 1)):
    assert len(paths[name]) == expect, name

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local NativeBuildObject", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in paths, "rally point is the Chinese beachhead path"
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
fallback_paths = re.findall(r'"(\w+)"', fallback)
assert fallback_paths and len(set(fallback_paths)) == len(fallback_paths), "there are distinct alternative approaches"
for name in fallback_paths:
    assert name in paths and name.startswith("wave_"), "fallback spawn entry is a CCA wave path: " + name
assert set(fallback_paths) == {"wave_%d" % i for i in range(1, 6)}
assert "enemyTeam = ENEMY_TEAM" in config and "local ENEMY_TEAM = 5" in cr_text
assert "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRGanymedeSitesCH01"' in config and 'module = "CREuropaWeather"' in config
assert '"EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge"' in config, "the Europa wire ops are registered"
assert 'failDes = "ch01lsea.des"' in config and 'wonFlags = { "won" }' in config and 'endedFlags = { "won", "lost" }' in config
assert "scrapPerGuest = 0" in config, "the mission starts with no scrap on purpose"
for op in ("CH1Cloak", "CH1Disguise", "CH1Fade", "CH1Blast"):
    assert op in config, op
info = set(re.search(r"INFO_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
assert info == {objects["target_1"][0]}, info

# Concealed arrivals: no wave path is near a start buoy, and the safe run is longer than the blast radius margin.
spawns = [start_pos[i] for i in range(1, 5)]
for name in sorted(set(fallback_paths) | {"relic_tug", "tug_defend"}):
    for sx, _, sz in spawns:
        d = math.dist((sx, sz), paths[name][0])
        assert d > 460, "%s is %.0f m from a start buoy (460 m rule)" % (name, d)
hangar = objects["target_1"][2]
nav_end = paths["nav_end"][0]
assert math.dist((hangar[0], hangar[2]), nav_end) - 50 > 1000, "the safe distance is a real run"
assert math.dist((hangar[0], hangar[2]), paths["relic_loc"][0]) < 100, "the restored blast site is at the hangar"
tug_fail = paths["tug_fail"][0]
assert math.dist((hangar[0], hangar[2]), tug_fail) < 100, "tug_fail is the hangar"

# ---------------------------------------------------------------- the weather's vents and sites
sites_path = ROOT / "Scripts/CRGanymedeSitesCH01.lua"
sites = sites_path.read_text(encoding="utf-8")
assert 'mission = "chmisn01"' in sites, "generated Ganymede sites belong to chmisn01"
vents = re.findall(r'\{ x = ([\d.]+), y = [\d.]+, z = ([\d.]+), label = "(\w+)"', sites)
assert len(vents) == 7, vents
for x, z, label in vents:
    geyser = objects[label][2]
    assert abs(float(x) - geyser[0]) < 0.1 and abs(float(z) - geyser[2]) < 1, "the vent sits on the geyser object " + label
assert "TriggerPlume(5)" in cr_text and "TriggerPlume(1)" in cr_text and "#europa.GetVentSites() >= 5" in cr_text
beach = vents[4]
assert math.dist((float(beach[0]), float(beach[1])), paths["recycler"][0]) < 150, "vent 5 is the beachhead geyser beside the Recycler path"
base = vents[0]
assert math.dist((float(base[0]), float(base[1])), (hangar[0], hangar[2])) < 400, "vent 1 is in the CCA base"
assert (ROOT / "Scripts/CREuropaWeather.lua").is_file()

# ---------------------------------------------------------------- audio: every line has a subtitle text
wavs = sorted(set(re.findall(r'"(ch01\d+\.wav)"', live, re.I)), key=str.lower)
restored = sorted(set(re.findall(r'"(ch01\d+\.wav)"', cr_text, re.I)), key=str.lower)
assert restored == ["ch01010.wav"], restored
# TRO 1.3 plays ch01010 in the body too (timer <= 5 s, FUN_005ae660); the co-op layer still restores it earlier.
assert len(wavs) == 11, wavs
for wav in wavs + restored:
    assert (ROOT / "Text" / (wav[:-4].lower() + ".txt")).is_file(), "no subtitle for " + wav
assert {w.lower() for w in wavs + restored} == {"ch01%03d.wav" % n for n in range(1, 12)}, "no unused voice line is left"
otfs = set(re.findall(r'"(ch01\d+\.otf)"', live)) | set(re.findall(r'"(ch01\d+\.otf)"', cr_text))
assert otfs == {"ch01%03d.otf" % n for n in range(1, 8)}, otfs
# The debrief .des files (ch01win, ch01lsea..ch01lsee) ship with the game, not in this tree.

# ---------------------------------------------------------------- companions, checked only when present
ini = ROOT / "Config/chmisn01cr.ini"
if ini.is_file():
    ini_text = ini.read_text(encoding="utf-8")
    assert 'gameType = "S"' in ini_text and 'minPlayers = "2"' in ini_text and 'maxPlayers = "4"' in ini_text
    print("  Config/chmisn01cr.ini checked")
crch = ROOT / "Config/crch.ini"
if crch.is_file():
    assert re.search(r'\[MISSION1\][^\[]*missionBZN = "chmisn01cr\.bzn"', crch.read_text(encoding="utf-8")), "campaign entry 1 is this map"
    print("  Config/crch.ini checked")
vxt = ROOT / "Missions/chmisn01cr.vxt"
if vxt.is_file():
    assert re.search(r"\bcsusera\b", vxt.read_text(encoding="utf-8")), "the vehicle list offers the on-foot Chinese pilot"
    print("  Missions/chmisn01cr.vxt checked")
mpdes = ROOT / "chmisn01cr.mpdes"
if mpdes.is_file():
    assert "New Kids on the Block" in mpdes.read_text(encoding="utf-8")
    print("  chmisn01cr.mpdes checked")

# ---------------------------------------------------------------- the doc accounts for every map path
doc = (ROOT / "Docs/CHMISN01_COOP.md").read_text(encoding="utf-8")
all_used = used | set(fallback_paths) | {rally}
unused = set(paths) - all_used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused == {"edge_path", "camera_end", "mobile_patrol_1", "confine_1", "confine_2"} | {"patrol_path_%d" % i for i in range(1, 15)}, unused
for name in SLIPS:
    assert "`" + name + "`" in doc, "undocumented slipped path: " + name
for section in ("## Layout", "## Teams and ownership", "## Scaling and concealed arrivals", "## The disguise",
                "## Humans' result", "## Cinematics are shared", "## Restored content",
                "## Stock bugs and co-op fixes in the CR layer", "## Weather: Ganymede", "## Tests",
                "## Inferences and open questions", "## Live checklist"):
    assert section in doc, "doc section missing: " + section
for flag in ("RESTORED_RECYCLER_OBJECTIVES", "RESTORED_VOICE_LINES", "ch01010", "ch01006", "ch01007"):
    assert flag in doc, "restoration not documented: " + flag
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("chmisn01 co-op contract passed: %d objects, %d paths, %d scripted path/label names, Ganymede sites present; %d paths unused (documented)"
      % (len(objects), len(paths), len(used) + len(handles), len(unused)))
