#!/usr/bin/env python3
"""bdmisn13 co-op map contract: the labels, paths and teams Scripts/bdmisn13cr.lua names exist in Missions/bdmisn13cr.bzn.

Skipped (exit 0, says so) when Missions/bdmisn13cr.bzn is not in the tree. The multiplayer listing
(Config/bdmisn13cr.ini), the campaign entry (Config/crbd.ini) and Missions/bdmisn13cr.vxt are checked only when present.
"""
from pathlib import Path
import math
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/bdmisn13cr.bzn"
if not bzn_path.is_file():
    print("bdmisn13 co-op contract SKIPPED: Missions/bdmisn13cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = bdmisn13\n" in text
assert "msn_filename = bdmisn13cr.bzn" in text
assert "name = MultSTMission" in text, "the map class restarts the cockpit timer upward: the CR layer counts the 45 minutes"

# ---------------------------------------------------------------- objects and teams
objects, starts, positions = {}, [], {}
for block in text.split("[GameObject]\n")[1:]:
    label = re.search(r"^label = (.*)$", block, re.M)
    odf = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)[1]
    team = int(re.search(r"^team \[1\] =\n(\d+)$", block, re.M)[1])
    perceived = int(re.search(r"^perceivedTeam \[1\] =\n(\d+)$", block, re.M)[1])
    pos = re.search(r"^pos \[1\] =\n  x \[1\] =\n(\S+)\n  y \[1\] =\n(\S+)\n  z \[1\] =\n(\S+)", block, re.M)
    if odf == "pspwn_1":
        starts.append(team)
        positions[label[1]] = (float(pos[1]), float(pos[3]))
        continue
    assert team in (0, 1, 5), "authored teams are neutral, the Black Dog side or the co-op enemy 5: %s team %d" % (odf, team)
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        objects.setdefault(label[1], (odf, team))
        positions.setdefault(label[1], (float(pos[1]), float(pos[3])))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert not any(team == 2 for _, team in objects.values()), "nothing is left on the script's enemy team 2"
assert objects["chin_recycler"] == ("cvrecy", 5), "the Chinese recycler is on the co-op enemy team"
assert objects["recycler"] == ("bvrecy", 1), "the Black Dog recycler is the shared base"
for i in range(1, 7):
    assert objects["chin_silo%d" % i] == ("cbsilo", 5), "silo %d is a Chinese silo on the co-op enemy team" % i
    assert objects["nav_chin_silo%d" % i] == ("apcamr", 1), "silo %d has its nav beacon" % i
assert any(odf == "bvcnst" and team == 1 for odf, team in objects.values()), "the Black Dog side has the construction rig that recycles"
paths, points = [], {}
for path in text.split("[AiPath]\n")[1:]:
    m = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if m:
        paths.append(m[1])
        found = re.findall(r"x \[1\] =\n(\S+)\n\s*z \[1\] =\n(\S+)", path.split("points [", 1)[1])
        points.setdefault(m[1], [(float(a), float(b)) for a, b in found])

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/bdmisn13cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--\[\[.*?\]\]", "", live, flags=re.S)
live = re.sub(r"(?m)^\s*--.*$", "", live)
cr_text = "".join(re.findall(region, lua_full))
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles == {"recycler", "chin_recycler"}, handles
assert 'GetHandle("chin_silo" .. i)' in live and 'GetHandle("nav_chin_silo" .. i)' in live
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
literals = set(re.findall(r'"(\w+)"', live))
used_body = literals & set(paths)
assert used_body == {"camera_intro", "spawn_attack_waves", "spawn_defend1", "spawn_defend6"}, used_body
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local NativeIsRecycledByTeam", 1)[0]
fallbacks = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1].replace('"', " ").replace(",", " ").split()
assert fallbacks and set(fallbacks) <= set(paths), "every fallback entry is a map path: " + str(fallbacks)
used = used_body | set(fallbacks)
# Nothing the body names lacks a map path.
for name in re.findall(r'CameraPath\("(\w+)"', live) + re.findall(r'BuildObject\([^\n]*"(\w+)"\)', live):
    assert name in paths, "path missing from the map: " + name

# ---------------------------------------------------------------- concealment: the entries are out of sight of every start
SAFE_RADIUS = 460
for name in sorted(used - {"camera_intro"}):
    assert len(points[name]) >= 1
    for spawn in ("coop_spawn1", "coop_spawn2", "coop_spawn3", "coop_spawn4"):
        sx, sz = positions[spawn]
        distance = math.hypot(points[name][0][0] - sx, points[name][0][1] - sz)
        assert distance > SAFE_RADIUS + 100, "%s is %.0f m from %s: not concealed at the start" % (name, distance, spawn)

# ---------------------------------------------------------------- the CR layer
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects, "rally point is a map object"
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRGanymedeSitesBD13"' in config and 'module = "CREuropaWeather"' in config
assert '"EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge"' in config
assert "failDes" not in re.sub(r"(?m)^\s*--.*$", "", config), "the game ships no bd13 generic loss debrief"
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
body_odfs = set(re.findall(r'"(cv\w+)"', live))
assert scaled == body_odfs == {"cvfigh", "cvltnk", "cvtnk", "cvrckt", "cvhraz", "cvhtnk"}, (scaled, body_odfs)
sites = ROOT / "Scripts/CRGanymedeSitesBD13.lua"
sites_text = sites.read_text(encoding="utf-8")
assert sites.is_file() and 'mission = "bdmisn13"' in sites_text, "generated Ganymede sites belong to bdmisn13"
vent_labels = re.findall(r'label = "(\w+)"', sites_text.split("vents", 1)[1])
assert len(vent_labels) == 15 and set(vent_labels) <= set(objects), "every vent is a map geyser: " + str(vent_labels)
beat_vents = set(re.findall(r'plume\("(\w+)"\)', cr_text))
assert beat_vents == {"eggeizr10_geyser", "eggeizr11_geyser", "eggeizr1146_geyser", "eggeizr1147_geyser", "eggeizr1148_geyser"}, beat_vents
assert beat_vents <= set(vent_labels), "every weather beat names a real vent"
for module in ("CREuropaWeather", "CRCCARuntime"):
    assert (ROOT / ("Scripts/%s.lua" % module)).is_file(), module

# ---------------------------------------------------------------- audio: every line has a subtitle, none is left unused
wavs = set(re.findall(r'"(bd13\d+\.wav)"', live))
restored_wavs = set(re.findall(r'"(bd13\d+\.wav)"', cr_text)) - wavs
assert wavs == {"bd13001.wav", "bd13002.wav", "bd13003.wav", "bd13004.wav", "bd13005.wav"}, wavs
assert restored_wavs == {"bd13006.wav", "bd13007.wav"}, "the CR layer plays exactly the two lines the DLL never plays: " + str(restored_wavs)
for wav in sorted(wavs | restored_wavs):
    assert (ROOT / "Text" / (wav[:-4] + ".txt")).is_file(), "no subtitle for " + wav
shipped = {p.stem + ".wav" for p in (ROOT / "Text").glob("bd13[0-9][0-9][0-9].txt")}
assert shipped == wavs | restored_wavs, "every shipped bd13 voice line is played: " + str(shipped ^ (wavs | restored_wavs))
# The debrief .des files (bd13win, bd13lsea..d) and the objective .otf files ship with the game, not in this tree.
des = set(re.findall(r'"(bd13\w+\.des)"', live))
assert des == {"bd13win.des", "bd13lsea.des", "bd13lseb.des", "bd13lsec.des", "bd13lsed.des"}, des

# ---------------------------------------------------------------- the listing files, when present
ini = ROOT / "Config/bdmisn13cr.ini"
if ini.is_file():
    ini_text = ini.read_text(encoding="utf-8")
    assert 'minPlayers = "2"' in ini_text and 'maxPlayers = "4"' in ini_text
    print("  Config/bdmisn13cr.ini checked")
else:
    print("  Config/bdmisn13cr.ini not present: skipped")
campaign = ROOT / "Config/crbd.ini"
if campaign.is_file():
    assert 'missionBZN = "bdmisn13cr.bzn"' in campaign.read_text(encoding="utf-8")
    print("  Config/crbd.ini checked")
else:
    print("  Config/crbd.ini not present: skipped")
vxt = ROOT / "Missions/bdmisn13cr.vxt"
if vxt.is_file():
    assert vxt.read_bytes().strip(), "the vehicle list is not empty"
    print("  Missions/bdmisn13cr.vxt checked")
else:
    print("  Missions/bdmisn13cr.vxt not present: skipped")

# ---------------------------------------------------------------- the doc accounts for every map path and cut block
doc = (ROOT / "Docs/BDMISN13_COOP.md").read_text(encoding="utf-8")
unused = set(paths) - used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused == {"edge_path", "spawn_defend4", "spawn_defend9"}, unused
for cut in ("bd13006", "bd13007", "MultSTMission", "Stock bugs fixed in the CR layer", "Live checklist",
            "RESTORED_SILO_LOSS_VOICE", "RESTORED_EARLY_STRIKE_VOICE", "IsRecycledByTeam"):
    assert cut in doc, "the doc must cover: " + cut
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("bdmisn13 co-op contract passed: %d objects, %d paths, %d scripted path/label names, Ganymede sites present; %d paths unused (documented)"
      % (len(objects), len(paths), len(used) + len(handles), len(unused)))
