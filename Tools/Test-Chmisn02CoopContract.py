#!/usr/bin/env python3
"""chmisn02 co-op map contract: the labels, paths and teams Scripts/ch02cr.lua names exist in Missions/ch02cr.bzn.

Skipped (exit 0, says so) when Missions/ch02cr.bzn is not in the tree. The vxt, the Config ini files and the
mpdes are checked only when present.
"""
from pathlib import Path
import math
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/ch02cr.bzn"
if not bzn_path.is_file():
    print("chmisn02 co-op contract SKIPPED: Missions/ch02cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = chmisn02\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = ch02cr.bzn" in text

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
    assert team in (0, 1, 5), "authored teams are neutral, the Chinese side or the moved Soviets: %s team %d" % (odf, team)
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        pos = [float(re.search(r"^  posit_%s \[1\] =\n(.*)$" % axis, block, re.M)[1]) for axis in "xyz"]
        objects.setdefault(label[1], (odf, team, pos))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert not any(team == 2 for _, team, _ in objects.values()), "nothing is left on the authored team 2"
soviets = {l for l, (odf, team, _) in objects.items() if team == 5}
assert {"attack_3_%d" % i for i in range(1, 6)} | {"attack_5_%d" % i for i in range(1, 6)} <= soviets, "the watched groups are enemies"
paths = {}
for path in text.split("[AiPath]\n")[1:]:
    m = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if m:
        body = path.split("pathType")[0]
        xs = [float(v) for v in re.findall(r"^  x \[1\] =\n(.*)$", body, re.M)]
        zs = [float(v) for v in re.findall(r"^  z \[1\] =\n(.*)$", body, re.M)]
        assert xs and len(xs) == len(zs)
        paths.setdefault(m[1], list(zip(xs, zs)))

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/ch02cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live_code = re.sub(r"--\[=\[.*?\]=\]", "", live, flags=re.S)
live_code = re.sub(r"--[^\n]*", "", live_code)
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live_code))
expected_handles = {"recycler", "hanger", "comm_tower", "armory"} | {"attack_3_%d" % i for i in range(1, 6)} | {"attack_5_%d" % i for i in range(1, 6)}
assert handles == expected_handles, handles
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
for label in ("attack_3_1", "attack_5_1"):
    assert objects[label][0] in ("svfigh", "svtank") and objects[label][1] == 5
assert objects["recycler"][0] == "cvrecy" and objects["hanger"][0] == "cbhanga"
used = set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live_code))
used |= set(re.findall(r'Goto\([^,]+, "(\w+)"', live_code))
used |= set(re.findall(r'Retreat\([^,]+, "(\w+)"', live_code))
used |= set(re.findall(r'CameraPath\("(\w+)"', live_code))
used |= set(re.findall(r'Distance\([^,]+, "(\w+)"\)', live_code))
used |= set(re.findall(r'ConvoyNear\("(\w+)"', live_code))
used |= set(re.findall(r'AtEndOfPath\([^,]+, "(\w+)"\)', live_code))
expected_used = {"annoy_1", "hanger_attack_2", "attack_6", "attack_6_path", "attack_7", "hanger_attack_3", "walker_spawn",
                 "walker_path", "walker_attack_2", "walker_attack_3", "hanger_attack_5", "attack_8", "convoy_units",
                 "convoy_path", "convoy_defend", "nav_convoy", "trigger_point_1", "trigger_point_2", "convoy_attack_10",
                 "attack_9", "attack_10", "hanger_attack_4", "camera_start", "hanger_attack_6", "attack_6_path"} \
    | {"convoy_attack_%d" % i for i in range(1, 10)}
assert used == expected_used, (used - expected_used, expected_used - used)
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local NativeBuildObject", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects and objects[rally][0] == "cvrecy", "rally point is the shared recycler"
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
fallback_paths = re.findall(r'"(\w+)"', fallback)
assert fallback_paths and len(set(fallback_paths)) == len(fallback_paths), "there are distinct alternative approaches"
for name in fallback_paths:
    assert name in paths, "fallback spawn entry exists: " + name
    assert name in expected_used, "a fallback entry is an approach the body already uses: " + name
assert "enemyTeam = ENEMY_TEAM" in config and "ENEMY_TEAM = 5" in cr_text and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRGanymedeSitesCH02"' in config and 'module = "CREuropaWeather"' in config
assert '"EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge"' in config, "the Europa wire ops are registered"
assert 'failDes = "ch02lsea.des"' in config and 'wonFlags = { "won" }' in config and 'endedFlags = { "lost", "won" }' in config
assert 'orders = { "Goto", "Attack", "Hunt" }' in config, "every order the body gives a ticketed raider is replayed"
safe = int(re.search(r"safeRadius = (\d+)", config)[1])
# hanger_attack_5/6 are the nearest scripted spawns to the base (320-340 m from the hangar): they must not be blocked by
# a human who stands at the base; the fallback is for a watched spawn only.
hangar = objects["hanger"][2]
near = {n: math.dist(paths[n][0], (hangar[0], hangar[2])) for n in ("hanger_attack_5", "hanger_attack_6")}
assert all(300 < d < 460 for d in near.values()) and safe == 300, (near, safe)
orders = set(re.findall(r'(Goto|Attack|Hunt)\(', re.sub(r"--[^\n]*", "", live_code)))
assert orders == {"Goto", "Attack", "Hunt"}, orders
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
body_odfs = set(re.findall(r'BuildObject\("(\w+)", 2,', live_code))
assert scaled == body_odfs, (scaled, body_odfs)

# The restorations name real map content.
for needle in ('"walker_attack_1"', '"walker_attack_3"', '"attack_9_path"'):
    assert needle in cr_text, needle
for name in ("walker_attack_1", "walker_attack_3", "attack_9_path"):
    assert name in paths, name
assert "walker_attack_1" not in live_code and "attack_9_path" not in live_code, "the cut paths are named only in the CR layer"
assert 'BuildObject("svfigh", 2, "walker_attack_1")' in lua_full.split("--[=[", 1)[1].split("]=]", 1)[0], "the disabled block is the source of the ambush"
assert "svhraz" in lua_full and '-- h = BuildObject("svhraz", 2, "walker_attack_3")' in lua_full, "the commented razors are the source of the restored pair"

# The network shot fallback uses the flight time of each map path: length / (speed / 100) seconds.
eta = {k: float(v) for k, v in re.findall(r"(\w+) = ([\d.]+)", re.search(r"CAMERA_ETA = \{([^}]*)\}", cr_text)[1])}
shots = {path: speed for path, speed in re.findall(r'CameraPath\("(\w+)", \d+, (\d+),', live_code)}
assert set(eta) == set(shots) == {"camera_start"}, (eta, shots)
for path, seconds in eta.items():
    pts = paths[path]
    length = sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
    expected = length * 100 / int(shots[path])
    assert abs(seconds - expected) < 0.1, "CAMERA_ETA[%s] = %s, map says %.2f" % (path, seconds, expected)

# ---------------------------------------------------------------- the weather's vent and sites
sites = (ROOT / "Scripts/CRGanymedeSitesCH02.lua").read_text(encoding="utf-8")
assert 'mission = "chmisn02"' in sites, "generated Ganymede sites belong to chmisn02"
vents = re.findall(r'\{ x = ([\d.]+), y = [\d.]+, z = ([\d.]+), label = "(\w+)"', sites)
assert len(vents) >= 5, "the beats use vent indexes 1, 2 and 5"
first = objects["eggeizr12_geyser"][2]
assert abs(float(vents[0][0]) - first[0]) < 0.1 and abs(float(vents[0][1]) - first[2]) < 1, "vent 1 is the geyser beside the armoury"
for index in re.findall(r"plume\((\d+)\)", cr_text):
    assert int(index) <= len(vents), "the plume beat names a vent that exists: " + index
assert "#europa.GetVentSites() >= index" in cr_text, "the plume beats are guarded"
assert (ROOT / "Scripts/CREuropaWeather.lua").is_file()

# ---------------------------------------------------------------- audio: every line has a subtitle text
wavs = sorted(set(re.findall(r'"(ch0\d\d+\.wav)"', live_code, re.I)), key=str.lower)
assert {w.lower() for w in wavs} == {"ch0200%d.wav" % n for n in range(1, 9)}, "the body plays the whole ch02 catalogue: " + str(wavs)
restored = sorted(set(re.findall(r'"(ch0\d\d+\.wav)"', cr_text, re.I)))
assert restored == ["ch03007.wav", "ch04005.wav"], restored
catalogue = (ROOT / "Tools/TranscriptSources/GoombaBZ/campaigns.csv").read_text(encoding="utf-8")
for wav in wavs + restored:
    assert (ROOT / "Text" / (wav[:-4].lower() + ".txt")).is_file(), "no subtitle for " + wav
    assert re.search(r"(?m)^%s," % re.escape(wav.lower()), catalogue, re.I), "not in the voice catalogue: " + wav
# The debrief .des files (ch02win, ch02lsea, ch02lseb, ch02lsec) ship with the game, not in this tree.
for des in ("ch02win.des", "ch02lsea.des", "ch02lseb.des", "ch02lsec.des"):
    assert des in lua_full, des

# ---------------------------------------------------------------- companions, checked only when present
ini = ROOT / "Config/ch02cr.ini"
if ini.is_file():
    ini_text = ini.read_text(encoding="utf-8")
    assert 'gameType = "S"' in ini_text and 'minPlayers = "2"' in ini_text and 'maxPlayers = "4"' in ini_text
    print("  Config/ch02cr.ini checked")
crch = ROOT / "Config/crch.ini"
if crch.is_file():
    assert re.search(r'\[MISSION2\][^\[]*missionBZN = "ch02cr\.bzn"', crch.read_text(encoding="utf-8")), "campaign entry 2 is this map"
    print("  Config/crch.ini checked")
vxt = ROOT / "Missions/ch02cr.vxt"
if vxt.is_file():
    vxt_text = vxt.read_text(encoding="utf-8")
    assert re.search(r"\bcvtnk\b", vxt_text) and re.search(r"\bcvfigh\b", vxt_text), "the vehicle list offers the Tank and the Fighter"
    print("  Missions/ch02cr.vxt checked")
mpdes = ROOT / "Missions/Descriptions/ch02cr.mpdes"
if mpdes.is_file():
    assert "Protection" in mpdes.read_text(encoding="utf-8")
    print("  ch02cr.mpdes checked")

# ---------------------------------------------------------------- the doc accounts for every map path
doc = (ROOT / "Docs/CHMISN02_COOP.md").read_text(encoding="utf-8")
all_used = used | set(fallback_paths) | {"walker_attack_1", "attack_9_path"}
unused = set(paths) - all_used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused == {"edge_path", "outer_limits", "attack_path_1", "attack_path_2", "attack_path_3", "attack_path_4",
                  "attack_path_5"}, unused
for flag in ("RESTORED_WALKER_AMBUSH", "RESTORED_WALKER_RAZORS", "RESTORED_ATTACK_9_PATH", "RESTORED_VOICE_LINES"):
    assert flag in cr_text and flag in doc, flag
for section in ("## Layout", "## Teams and ownership", "## Scaling and concealed arrivals", "## Humans' result",
                "## Cinematics are shared", "## Restored content", "## Stock bugs and co-op fixes in the CR layer",
                "## Weather: Ganymede", "## Tests", "## Inferences and open questions", "## Live checklist"):
    assert section in doc, "doc section missing: " + section
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("chmisn02 co-op contract passed: %d objects, %d paths, %d scripted path/label names, Ganymede sites present; %d paths unused (documented)"
      % (len(objects), len(paths), len(used) + len(handles), len(unused)))
