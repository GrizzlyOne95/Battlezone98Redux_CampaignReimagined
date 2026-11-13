#!/usr/bin/env python3
"""chmisn07 co-op map contract: the labels, paths and teams Scripts/ch07cr.lua names exist in Missions/ch07cr.bzn.

Skipped (exit 0, says so) when Missions/ch07cr.bzn is not in the tree. The vxt and the Config ini files are
checked only when present.
"""
from pathlib import Path
import math
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
bzn_path = ROOT / "Missions/ch07cr.bzn"
if not bzn_path.is_file():
    print("chmisn07 co-op contract SKIPPED: Missions/ch07cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = chmisn07\n" in text
assert "msn_filename = ch07cr.bzn" in text

# ---------------------------------------------------------------- objects and teams
objects, starts, buoys = {}, [], set()
for block in text.split("[GameObject]\n")[1:]:
    label = re.search(r"^label = (.*)$", block, re.M)
    odf = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)[1]
    team = int(re.search(r"^team \[1\] =\n(\d+)$", block, re.M)[1])
    perceived = int(re.search(r"^perceivedTeam \[1\] =\n(\d+)$", block, re.M)[1])
    if odf == "pspwn_1":
        starts.append(team)
        if label:
            buoys.add(label[1])
        continue
    assert team in (0, 1, 5), "authored teams: neutral, the Chinese player side, the Soviets moved to 5: %s team %d" % (odf, team)
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        pos = [float(re.search(r"^  posit_%s \[1\] =\n(.*)$" % axis, block, re.M)[1]) for axis in "xyz"]
        objects.setdefault(label[1], (odf, team, pos))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert not any(team == 2 for _, team, _ in objects.values()), "nothing is left on the authored team 2"
assert objects["player"][0] == "ssuserb" and objects["player"][1] == 1, "the host starts as the on-foot sniper"
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
lua_full = (ROOT / "Scripts/ch07cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full).split("--[=[", 1)[0]  # the cut-content archive is a comment
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
expected_handles = {"commtower", "ammo_1", "ammo_2", "repair_1", "repair_2", "bomb_north", "bomb_east"}
expected_handles |= {"foot_%d_%d" % (a, b) for a, b in ((1, 1), (1, 2), (1, 3), (2, 1), (2, 2), (2, 3))}
expected_handles |= {"figh_1_1", "figh_1_2", "figh_1_3", "figh_2_1", "figh_2_2", "figh_3_1", "figh_3_2"}
assert handles == expected_handles, handles ^ expected_handles
quoted = set(re.findall(r'"(\w+)"', live))
used = quoted & set(paths)
for name in re.findall(r'"(\w+_spn)"', live):
    assert name in paths, name
for name in re.findall(r'"(\w+_trig)"', live):
    assert name in paths, name
assert {"cin_start", "cin_burglar", "cin_north", "cin_east", "fake_spn", "fake_vanish", "burglar_exit", "nav_north",
        "nav_east", "nav_end", "north_path", "east_path", "north_trig", "east_trig", "north_wav", "east_wav",
        "north_fail", "east_fail", "expl_north_spn", "expl_east_spn"} <= used

# ---------------------------------------------------------------- the CR layer
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local NativeBuildObject", 1)[0]
cr_text = "".join(re.findall(region, lua_full))
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally == "coop_spawn1" and rally in buoys, "rally point is the host's start buoy"
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
fallback_paths = re.findall(r'"(\w+)"', fallback)
assert fallback_paths and len(set(fallback_paths)) == len(fallback_paths), "there are distinct alternative approaches"
for name in fallback_paths:
    assert name in paths, "fallback spawn entry exists: " + name
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CREuropaSitesCH07"' in config and 'module = "CREuropaWeather"' in config
assert '"EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge"' in config, "the Europa wire ops are registered"
assert 'failDes = "ch07lose.des"' in config and 'wonFlags = { "won" }' in config
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
enemy_odfs = set(re.findall(r'BuildObject\("(\w+)", 2,', live))
assert scaled <= enemy_odfs and scaled == {"ssusera", "sssold", "sspilo"}, scaled
# The disguise: the body names the Soviet side as team 2; the CR layer maps it to the co-op enemy team 5 for every human.
assert 'campaignRuntime.Present("CH7Disguise", team == 2 and 5 or team)' in cr_text
assert "NativeSetPerceivedTeam(h, team == 1 and GetTeamNum(h) or team)" in cr_text

# The network shot fallback uses the flight time of each map path: length / (speed / 100) seconds.
eta = {k: float(v) for k, v in re.findall(r"(\w+) = ([\d.]+)", re.search(r"CAMERA_ETA = \{([^}]*)\}", cr_text)[1])}
shots = {path: speed for path, speed in re.findall(r'CameraPath\("(\w+)", \d+, (\d+),', live)}
assert set(eta) == {"cin_start", "cin_north", "cin_east"} and set(eta) <= set(shots), (eta, shots)
for path, seconds in eta.items():
    pts = paths[path]
    length = sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
    expected = length * 100 / int(shots[path])
    assert abs(seconds - expected) < 0.1, "CAMERA_ETA[%s] = %s, map says %.2f" % (path, seconds, expected)
# the stand-in's walk is short; the watchdog is only a never-hang guard
walk = math.dist(paths["fake_spn"][0], paths["fake_vanish"][0])
assert walk < 40 and "BURGLAR_LIMIT = 25.0" in cr_text

# ---------------------------------------------------------------- the weather's sites
sites = (ROOT / "Scripts/CREuropaSitesCH07.lua").read_text(encoding="utf-8")
assert 'mission = "chmisn07"' in sites, "generated Europa sites belong to chmisn07"
assert re.search(r"vents = \{\s*\}", sites), "this Europa map has no vents"
assert "if #europa.GetVentSites() > 0 then europa.TriggerPlume(1) end" in cr_text, "the plume beat is guarded"
assert (ROOT / "Scripts/CREuropaWeather.lua").is_file()

# ---------------------------------------------------------------- audio: every line has a subtitle text
wavs = sorted(set(re.findall(r'"(ch07\d+\.wav)"', live, re.I)), key=str.lower)
assert {w.lower() for w in wavs} == {"ch07%03d.wav" % n for n in range(1, 10)}, wavs
for wav in wavs:
    assert (ROOT / "Text" / (wav[:-4].lower() + ".txt")).is_file(), "no subtitle for " + wav
durations = (ROOT / "Config/durations.csv").read_text(encoding="utf-8")
shipped = set(re.findall(r"^(ch07\d+)\.wav,", durations, re.M))
assert shipped == {w[:-4] for w in wavs}, "no shipped ch07 voice line is left unplayed: " + str(shipped ^ {w[:-4] for w in wavs})

# ---------------------------------------------------------------- companions, checked only when present
ini = ROOT / "Config/ch07cr.ini"
if ini.is_file():
    ini_text = ini.read_text(encoding="utf-8")
    assert 'gameType = "S"' in ini_text and 'minPlayers = "2"' in ini_text and 'maxPlayers = "4"' in ini_text
    print("  Config/ch07cr.ini checked")
vxt = ROOT / "Missions/ch07cr.vxt"
if vxt.is_file():
    assert re.search(r"\bssuserb\b", vxt.read_text(encoding="utf-8")), "the vehicle list offers the on-foot sniper"
    print("  Missions/ch07cr.vxt checked")

# ---------------------------------------------------------------- the doc accounts for every map path and loose object
doc = (ROOT / "Docs/CHMISN07_COOP.md").read_text(encoding="utf-8")
all_used = used | set(fallback_paths)
unused = set(paths) - all_used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused == {"edge_path", "foot_1_path", "foot_2_path", "foot_3_path", "foot_4_path", "figh_1_path",
                  "figh_2_path", "figh_3_path"}, unused
scripted_prefixes = ("figh_", "foot_", "pilot_")
loose = {k for k in objects if k.startswith(scripted_prefixes)} - handles
for name in sorted(loose):
    assert "`" + name + "`" in doc, "undocumented unscripted unit: " + name
assert loose == {"pilot_%d" % i for i in range(1, 7)} | {"figh_2_3"}, loose
for section in ("## Layout", "## Teams and ownership", "## Scaling and concealed arrivals", "## Humans' result",
                "## Cinematics are shared", "## Restored content", "## Stock bugs and co-op fixes in the CR layer",
                "## Weather: Europa", "## Tests", "## Inferences and open questions", "## Live checklist"):
    assert section in doc, "doc section missing: " + section
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("chmisn07 co-op contract passed: %d objects, %d paths, %d scripted path names, Europa sites present; %d paths unused (documented)"
      % (len(objects), len(paths), len(used), len(unused)))
