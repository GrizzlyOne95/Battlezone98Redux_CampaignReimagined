#!/usr/bin/env python3
"""chmisn05 co-op map contract: the labels, paths and teams Scripts/chmisn05cr.lua names exist in Missions/chmisn05cr.bzn.

Skipped (exit 0, says so) when Missions/chmisn05cr.bzn is not in the tree. The companion files (Missions/chmisn05cr.vxt,
Config/chmisn05cr.ini, the MISSION5 entry of Config/crch.ini) are checked only when they are present.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/chmisn05cr.bzn"
if not bzn_path.is_file():
    print("chmisn05 co-op contract SKIPPED: Missions/chmisn05cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = chmisn05\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = chmisn05cr.bzn" in text

# ---------------------------------------------------------------- objects and teams
objects, starts = {}, []
for block in text.split("[GameObject]\n")[1:]:
    label = re.search(r"^label = (.*)$", block, re.M)
    odf = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)[1]
    team = int(re.search(r"^team \[1\] =\n(\d+)$", block, re.M)[1])
    if odf == "pspwn_1":
        starts.append(team)
        continue
    assert team in (0, 1, 5), "authored teams are neutral, Chinese or the co-op enemy: %s team %d" % (odf, team)
    if label:
        objects.setdefault(label[1], (odf, team))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert not any(team == 2 for _, team in objects.values()), "nothing is left on the authored team 2"
assert objects["player"] == ("cvscav", 1), "the host starts in a scavenger"
assert objects["recycler"] == ("cvrecy", 1) and objects["silo"] == ("cbsilo", 1)
assert all(objects[k][1] == 5 for k in objects if objects[k][0] in ("sbtowe", "sbspow", "svturr", "proxminc")), "the Soviet base is the co-op enemy"
paths = {}
unnamed = 0
for path in text.split("[AiPath]\n")[1:]:
    m = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if m:
        paths[m[1]] = re.findall(r"x \[1\] =\n([-\d.e+]+)\n\s*z \[1\] =\n([-\d.e+]+)", path)
    else:
        unnamed += 1

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/chmisn05cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--\[(=*)\[.*?\]\1\]", "", live, flags=re.S)
live = re.sub(r"--[^\n]*", "", live)
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles == {"silo", "recycler"}, handles
assert handles <= set(objects), "every GetHandle label is a map object"
used = set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live))
used |= set(re.findall(r'(?:Goto|CameraPath|GetPosition)\([^,)]*?"(\w+)"', live))
used |= set(re.findall(r'GetDistance\([^,]+, "(\w+)"\)', live))
used |= set(re.findall(r'Goto\([^,]+, "(\w+)"', live))
used |= {"annoy_path_1", "annoy_path_2"}  # chosen from a literal list
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
assert {"scout_path", "convoy_path", "haul_path", "haul_cam", "trigger_1", "trigger_2", "nav_1", "base_1", "aerial_1"} <= used
assert {"wave_%d" % i for i in range(1, 8)} <= used and {"wave_%d_path" % i for i in (1, 2, 4, 5, 6, 7)} <= used
assert {"day_%d" % i for i in range(1, 9)} <= used

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local NativeBuildObject", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects, "the rally point is the map's recycler, which travels with the convoy"
fallback = re.findall(r'"(\w+)"', re.search(r"fallbackEntries = \{([^}]*)\}", config)[1])
assert set(fallback) <= set(paths) and set(fallback) == {"wave_7", "annoy_1", "wave_6", "wave_1", "wave_5", "wave_4", "wave_2"}
scaled_paths = set(re.findall(r"(\w+) = true", re.search(r"SCALED_PATHS = \{([^}]*)\}", cr_text)[1]))
assert scaled_paths <= set(paths) and scaled_paths <= set(fallback) | {"annoy_1"}
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'failDes = "ch05lsec.des"' in config and "scrapPerGuest = 0" in config
assert 'module = "CRElysiumWeather"' in config and 'sites = "CRElysiumSitesCH05"' in config
sites = (ROOT / "Scripts/CRElysiumSitesCH05.lua").read_text(encoding="utf-8")
assert 'mission = "chmisn05"' in sites
for label in re.findall(r'label = "(\w+)"', sites):
    assert label in objects and objects[label][0] == "eggeizr1", "the site file's vent is a map geyser: " + label
assert (ROOT / "Scripts/CRElysiumWeather.lua").is_file()
for beat_path in re.findall(r'strikeAt\("(\w+)"\)', config):
    assert beat_path in paths, "the weather strikes a real path: " + beat_path
for flag in ("RESTORED_SILO_TARGET", "RESTORED_VOICE_LINES"):
    assert flag in cr_text

# ---------------------------------------------------------------- audio and objectives
wavs = set(re.findall(r'"([a-z]+\d*\.wav)"', live))
assert wavs == {"ch0500%d.wav" % n for n in range(1, 8)} | {"abetty6.wav", "abetty14.wav"}, wavs
for wav in sorted(w for w in wavs if w.startswith("ch")):
    assert (ROOT / "Text" / (wav[:-4] + ".txt")).is_file(), "no subtitle for " + wav
unused = [p for p in (ROOT / "Text").glob("ch05*.txt") if p.stem + ".wav" not in wavs]
assert [p.stem for p in unused] == ["ch05008"], "the one unused shipped ch05 line is the victory line: " + str(unused)
assert '"ch05008.wav"' in cr_text, "the CR layer slots it in"
durations = dict(line.split(",") for line in (ROOT / "Config/durations.csv").read_text(encoding="utf-8").split() if line.startswith("ch05008"))
win_seconds = float(re.search(r"WIN_LINE_SECONDS = ([\d.]+)", cr_text)[1])
assert float(durations["ch05008.wav"]) == win_seconds, "the victory wait is the line's shipped duration"
assert set(re.findall(r'"(ch05\w+\.des)"', live)) == {"ch05lsea.des", "ch05lseb.des", "ch05lsec.des", "ch05lsed.des", "ch05win.des"}
assert set(re.findall(r'"(ch05\w+\.otf)"', live)) == {"ch05001.otf", "ch05002.otf", "ch05003.otf", "ch05004.otf"}

# ---------------------------------------------------------------- companion files, only when present
vxt = ROOT / "Missions/chmisn05cr.vxt"
if vxt.is_file():
    allowed = [line.split(",")[0].strip() for line in vxt.read_text(encoding="latin-1").splitlines() if line.strip()]
    assert allowed == ["cvscav", "cvtnk"], "every human starts in a scavenger or a tank: " + str(allowed)
else:
    print("note: Missions/chmisn05cr.vxt not present, vehicle list not checked")
ini = ROOT / "Config/chmisn05cr.ini"
if ini.is_file():
    body = ini.read_text(encoding="utf-8")
    assert 'mapType = "multiplayer"' in body and 'gameType = "S"' in body and 'maxPlayers = "4"' in body
else:
    print("note: Config/chmisn05cr.ini not present, multiplayer listing not checked")
crch = ROOT / "Config/crch.ini"
if crch.is_file():
    assert re.search(r'\[MISSION5\][^\[]*missionBZN = "chmisn05cr\.bzn"', crch.read_text(encoding="utf-8")), "crch.ini MISSION5 points at the co-op map"
else:
    print("note: Config/crch.ini not present, campaign entry not checked")

# ---------------------------------------------------------------- the doc accounts for every map path and cut block
doc = (ROOT / "Docs/CHMISN05_COOP.md").read_text(encoding="utf-8")
unused_paths = set(paths) - used - {"scout_1", "scout_2", "convoy", "haul_scout", "enemy_haul", "haul_defend", "artl_1",
                                    "artl_2", "artl_defend"}
for name in sorted(unused_paths):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused_paths == {"edge_path", "outer_limits"}, unused_paths
assert unnamed == 1 and "unnamed" in doc, "the unnamed two-point path is documented"
for word in ("GetHealth(silo)", "RESTORED_SILO_TARGET", "RESTORED_VOICE_LINES", "ch05008", "Stock bugs fixed in the CR layer",
             "Live checklist", "cut/debug block", "smokingUnit"):
    assert word in doc, "the doc accounts for " + word
print("chmisn05 co-op contract passed: %d objects, %d paths, %d scripted path/label names, %d vents; %d paths unused (documented)"
      % (len(objects), len(paths), len(used) + len(handles), len(re.findall(r'label = "', sites)), len(unused_paths)))
