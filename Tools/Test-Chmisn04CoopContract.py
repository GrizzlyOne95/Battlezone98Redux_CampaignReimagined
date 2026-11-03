#!/usr/bin/env python3
"""chmisn04 co-op map contract: the labels, paths and teams Scripts/chmisn04cr.lua names exist in Missions/chmisn04cr.bzn.

Skipped (exit 0, says so) when Missions/chmisn04cr.bzn is not in the tree. The start file, the Config ini files and the
mpdes are checked only when present.
"""
from pathlib import Path
import math
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/chmisn04cr.bzn"
if not bzn_path.is_file():
    print("chmisn04 co-op contract SKIPPED: Missions/chmisn04cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = chmisn04\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = chmisn04cr.bzn" in text

# ---------------------------------------------------------------- objects and teams
objects, starts, user = {}, [], None
for block in text.split("[GameObject]\n")[1:]:
    label = re.search(r"^label = (.*)$", block, re.M)
    odf = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)[1]
    team = int(re.search(r"^team \[1\] =\n(\d+)$", block, re.M)[1])
    perceived = int(re.search(r"^perceivedTeam \[1\] =\n(\d+)$", block, re.M)[1])
    if odf == "pspwn_1":
        starts.append(team)
        continue
    if odf == "cvfighe":
        user = (label and label[1], team)
    assert team in (0, 1, 5), "authored teams are neutral, the Chinese side or the Soviets on team 5: %s team %d" % (odf, team)
    if label:
        # The Chinese factory and portal stand on team 1 disguised as Soviet buildings (perceived team 5).
        if label[1] in ("factory", "portal"):
            assert (team, perceived) == (1, 5), "the disguised Chinese buildings: " + label[1]
        else:
            assert perceived == team, "perceived team follows the move: " + label[1]
        pos = [float(re.search(r"^  posit_%s \[1\] =\n(.*)$" % axis, block, re.M)[1]) for axis in "xyz"]
        objects.setdefault(label[1], []).append((odf, team, pos))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert user == ("player", 1), "the map start is the upgraded fighter on team 1: " + str(user)
assert not any(team == 2 for entries in objects.values() for _, team, _ in entries), "nothing is left on the authored team 2"
assert any(team == 5 for entries in objects.values() for _, team, _ in entries), "the Soviet base is on the co-op enemy team"
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
lua_full = (ROOT / "Scripts/chmisn04cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"(?m)--[^\n]*", "", live)  # the DLL's disabled lines stay disabled
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert '"empty_" ..' in live and '"turret_" ..' in live
handles |= {"empty_%d" % n for n in range(1, 26)} | {"turret_%d" % n for n in range(1, 5)}
assert handles == {"target_silo", "nav_1", "cca_factory", "factory", "portal"} | {"empty_%d" % n for n in range(1, 26)} \
    | {"turret_%d" % n for n in range(1, 5)}, handles
for label in sorted(handles):
    assert len(objects.get(label, [])) == 1, "GetHandle label %s must be on exactly one map object (found %d)" % (label, len(objects.get(label, [])))
    assert objects[label][0][1] in (0, 1, 5), "authored story object is Chinese or Soviet: " + label
assert objects["portal"][0][0] == "cbport" and objects["factory"][0][0] == "cvmuf" and objects["target_silo"][0][0] == "sbsiloa"
assert objects["cca_factory"][0][0] == "svmuf"
assert all(objects["empty_%d" % n][0][0] in ("svfigha", "svtanka") for n in range(1, 26))
# IsInfo relays by the silo's ODF name (INFO_PREFIXES); the body asks IsInfo(GetOdf(target_silo)).
assert 'IsInfo(GetOdf(M.target_silo))' in live and "INFO_PREFIXES = { sbsiloa = true }" in lua_full

used = set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live))
used |= set(re.findall(r'Goto\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'CameraPath(?:Dir)?\("(\w+)"', live))
used |= set(re.findall(r'Distance\([^,]+, "(\w+)"\)', live))
used |= set(re.findall(r'BuildObject\("sspilo", 2, "pilot_" \.\. n\)', live) and {"pilot_%d" % n for n in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17, 25)})
used |= {"nav_%d" % n for n in range(2, 7)} if '"nav_" .. (M.uptonavpoint + 1)' in live else set()
for n in (1, 2, 3, 4, 5, 6, 11, 14, 17, 25, 7, 8, 9, 10, 12, 13):
    assert "pilot_%d" % n in paths, "pilot path " + str(n)
assert re.search(r"SpawnPilots\(\{1, 2, 3, 4, 5, 6, 11, 14, 17, 25\}\)", live) and re.search(r"SpawnPilots\(\{7, 8, 9, 10, 12, 13\}\)", live)
assert "nav_base" in used and used >= {"camera_start", "camera_alarm", "auto_end", "trigger_1", "fighter_1", "fighter_2",
                                         "figh1_path", "figh2_path", "chase_1", "chase_2", "chase_3", "portal_units"}, used
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local NativeIsValid", 1)[0]
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects and objects[rally][0][0] == "cvmuf", "rally point is the Chinese factory, the shared base"
fallback = re.findall(r'"(\w+)"', re.search(r"fallbackEntries = \{([^}]*)\}", config)[1])
assert fallback and len(set(fallback)) == len(fallback), "there are distinct alternative approaches"
for name in fallback:
    assert name in paths, "fallback spawn entry exists: " + name
    assert name in ("chase_1", "chase_2", "chase_3", "portal_units"), "a fallback is a hidden Soviet approach: " + name
assert 'failDes = "ch04lose.des"' in config and 'wonFlags = { "won" }' in config and 'endedFlags = { "won", "lost" }' in config
assert 'farthestTargets = { "portal" }' in config and "scrapPerGuest = 0" in config
assert 'module = "CREuropaWeather"' in config and 'sites = "CRGanymedeSitesCH04"' in config
assert '"EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge"' in config, "the Europa wire ops are registered"
for op in ("CH4Hide", "CH4Disguise", "CH4Portal", "CH4Shot"):
    assert op in config and 'Present("%s"' % op in cr_text, "presentation op " + op
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
body_odfs = set(re.findall(r'BuildObject\("(\w+)", 2,', live)) | {"svfigh"}  # the portal guards and the fighters
assert scaled == {"svfigh", "svfigha", "svtanka"} and scaled <= body_odfs | {"svfigha", "svtanka"}, scaled
direct = set(re.search(r"DIRECT_PATHS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
assert direct == {"fighter_1", "fighter_2"} and direct <= used, "the two scramble fighters are built directly"
sites = ROOT / "Scripts/CRGanymedeSitesCH04.lua"
assert sites.is_file() and 'mission = "chmisn04"' in sites.read_text(encoding="utf-8"), "generated Ganymede sites belong to chmisn04"
vents = re.findall(r'\{ x = ([\d.]+), y = [\d.]+, z = ([\d.]+), label = "(\w+)"', sites.read_text(encoding="utf-8"))
assert [v[2] for v in vents] == ["eggeizr19_geyser", "eggeizr17_geyser"], "two vents: the base geyser and the Soviet geyser"
for x, z, label in vents:
    geyser = objects[label][0][2]
    assert abs(float(x) - geyser[0]) < 0.1 and abs(float(z) - geyser[2]) < 1, "the vent sits on the geyser object: " + label
assert "TriggerPlume(1)" in cr_text and "GetVentSites() > 0" in cr_text, "the plume beat is guarded and aims at the first vent"
for module in ("CREuropaWeather", "CRCCARuntime"):
    assert (ROOT / ("Scripts/%s.lua" % module)).is_file(), module

# The network shot fallback uses the flight time of each map path: length / (speed / 100) seconds.
eta = {k: float(v) for k, v in re.findall(r"(\w+) = ([\d.]+)", re.search(r"CAMERA_ETA = \{([^}]*)\}", cr_text)[1])}
shots = {}
for path, speed in re.findall(r'CameraPath(?:Dir)?\("(\w+)", \d+, (\d+)', live):
    shots.setdefault(path, speed)  # the first call of a path is the flight; auto_end is called again at speed 0 to hold
assert set(eta) == {"camera_start", "auto_end"} and shots["camera_start"] == "1200" and shots["auto_end"] == "4500", (eta, shots)
for path, seconds in eta.items():
    pts = paths[path]
    length = sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
    expected = length * 100 / int(shots[path])
    assert abs(seconds - expected) < 0.1, "CAMERA_ETA[%s] = %s, map says %.2f" % (path, seconds, expected)

# The cut content the CR layer restores names real map content.
assert '"nav_silo"' in cr_text and "nav_silo" in paths and '"nav_base"' in live
assert "auto_end" in paths and '"trigger_1"' in cr_text
for flag in ("RESTORED_UNCLOAKED_DETECTION", "RESTORED_SILO_BEACON", "RESTORED_ALARM_PILOTS", "RESTORED_FAKE_CRAFT",
             "RESTORED_VOICE_LINES"):
    assert re.search(r"(?m)^local %s = true" % flag, cr_text), flag
nine = [int(n) for n in re.search(r"local NINE = \{([^}]*)\}", cr_text)[1].replace(" ", "").split(",")]
assert nine == [15, 16, 18, 19, 20, 21, 22, 23, 24], nine
assert not (set(nine) & {1, 2, 3, 4, 5, 6, 11, 14, 17, 25, 7, 8, 9, 10, 12, 13}), "the nine are the craft the body gives no pilot"

# ---------------------------------------------------------------- audio: every line has a subtitle, the unused two are restored
for wav in sorted(set(re.findall(r'"(ch04\d+\.wav)"', lua_full))):
    assert (ROOT / "Text" / (wav[:-4] + ".txt")).is_file(), "no subtitle for " + wav
body_wavs = set(re.findall(r'"(ch04\d+\.wav)"', live))
shipped = {p.stem + ".wav" for p in (ROOT / "Text").glob("ch040??.txt")}
assert shipped == {"ch0400%d.wav" % n for n in range(1, 9)}, shipped
unused = shipped - body_wavs
assert unused == {"ch04004.wav", "ch04005.wav"}, "the only shipped lines the body never plays: " + str(unused)
assert '"ch04004.wav"' in cr_text and '"ch04005.wav"' in cr_text
# The debriefs ship with the game: ch04lsea, ch04lseb, ch04win in the body, ch04lose for the runtime's out-of-lives.
for des in ("ch04lsea.des", "ch04lseb.des", "ch04win.des"):
    assert '"%s"' % des in live, des

# ---------------------------------------------------------------- companions, checked only when present
vxt = ROOT / "Missions/chmisn04cr.vxt"
if vxt.is_file():
    assert [l.strip() for l in vxt.read_bytes().decode("latin-1").strip().splitlines()] == ["cvfighe ,", "cvtnk ,"], "the start file offers the fighter and the tank"
    print("  Missions/chmisn04cr.vxt checked")
ini = ROOT / "Config/chmisn04cr.ini"
if ini.is_file():
    ini_text = ini.read_text(encoding="utf-8")
    assert 'gameType = "S"' in ini_text and 'minPlayers = "2"' in ini_text and 'maxPlayers = "4"' in ini_text
    print("  Config/chmisn04cr.ini checked")
crch = ROOT / "Config/crch.ini"
if crch.is_file():
    assert re.search(r'\[MISSION4\][^\[]*missionBZN = "chmisn04cr\.bzn"', crch.read_text(encoding="utf-8")), "campaign entry 4 is this map"
    print("  Config/crch.ini checked")
mpdes = ROOT / "chmisn04cr.mpdes"
if mpdes.is_file():
    assert "From Out There Somewhere" in mpdes.read_text(encoding="utf-8")

# ---------------------------------------------------------------- the doc accounts for every map path and cut label
doc = (ROOT / "Docs/CHMISN04_COOP.md").read_text(encoding="utf-8")
all_used = used | set(fallback) | {"nav_silo"}
unused_paths = set(paths) - all_used
for name in sorted(unused_paths):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused_paths == {"edge_path", "outer_limits", "camera_end", "path_3"}, unused_paths
for section in ("## Layout", "## Teams and ownership", "## Humans as the player", "## Scaling and concealed arrivals",
                "## Results", "## Cinematics are shared", "## Restored content", "## Stock bugs fixed in the CR layer",
                "## Weather: Ganymede", "## Tests", "## Inferences and open questions", "## Live checklist"):
    assert section in doc, "doc section missing: " + section
for word in ("RESTORED_UNCLOAKED_DETECTION", "RESTORED_SILO_BEACON", "RESTORED_ALARM_PILOTS", "RESTORED_FAKE_CRAFT",
             "RESTORED_VOICE_LINES", "ch04004.wav", "ch04005.wav", "ch04004.otf", "GetCockpitTimer", "ch04lose.des"):
    assert word in doc, "the doc must cover " + word
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("chmisn04 co-op contract passed: %d labelled objects, %d paths, %d named by the body, %d unused (documented), %d vents in the Ganymede sites"
      % (len(objects), len(paths), len(used), len(unused_paths), len(vents)))
