#!/usr/bin/env python3
"""chmisn08 co-op map contract: the labels, paths and teams Scripts/chmisn08cr.lua names exist in Missions/chmisn08cr.bzn.

Skipped (exit 0, says so) when Missions/chmisn08cr.bzn is not in the tree. The vxt and the Config ini files are
checked only when present.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/chmisn08cr.bzn"
if not bzn_path.is_file():
    print("chmisn08 co-op contract SKIPPED: Missions/chmisn08cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = chmisn08\n" in text
assert "msn_filename = chmisn08cr.bzn" in text

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
    assert team in (0, 1, 5), "authored teams: neutral, the Chinese convoy side, the Soviets moved to 5: %s team %d" % (odf, team)
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        pos = [float(re.search(r"^  posit_%s \[1\] =\n(.*)$" % axis, block, re.M)[1]) for axis in "xyz"]
        objects.setdefault(label[1], (odf, team, pos))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert not any(team == 2 for _, team, _ in objects.values()), "nothing is left on the authored team 2"
assert objects["player"][0] == "cvtnk" and objects["player"][1] == 1, "the host starts in the convoy tank"
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
lua_full = (ROOT / "Scripts/chmisn08cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full).split("--[=[", 1)[0]  # the cut-content archive is a comment
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
# Four families are built from a loop with a concatenated label ("magpull_" .. (i + 1)), not a literal string.
expected_handles = {"west_1_1", "west_1_2", "west_1_3", "west_1_4", "east_1_1", "east_1_2", "east_1_3", "east_1_4",
                     "nav", "howitzer_nw", "howitzer_ne", "west_power", "east_power", "east_bolt", "west_bolt",
                     "walker_1", "west_comm", "east_comm"}
assert handles == expected_handles, handles ^ expected_handles
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
looped_handles = {"magpull_%d" % n for n in range(1, 7)}
looped_handles |= {"west_mag_%d" % n for n in range(1, 5)} | {"east_mag_%d" % n for n in range(1, 5)}
looped_handles |= {"sniper_%d" % n for n in range(1, 27)}
assert looped_handles <= set(objects), "every loop-concatenated label is a map object: " + str(looped_handles - set(objects))
all_handled = handles | looped_handles
quoted = set(re.findall(r'"(\w+)"', live))
used = quoted & set(paths)

# ---------------------------------------------------------------- the CR layer
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local NativeBuildObject", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally == "coop_spawn1" and rally in buoys, "rally point is the host's start buoy"
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'module = "CREuropaWeather"' in config and 'sites = "CRGanymedeSitesCH08"' in config
assert '"EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge"' in config, "the Europa wire ops are registered"
assert 'failDes = "ch08lsea.des"' in config and 'wonFlags = { "coopWon" }' in config
scaled = set(re.search(r"scaledOdfs = \{([^}]*)\}", config)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
enemy_odfs = set(re.findall(r'BuildObject\("(\w+)", 2,', live)) | set(re.findall(r'Wave\("(\w+)", "wave_\d"', live))
assert scaled <= enemy_odfs and scaled == {"svfigh", "svtank", "svwalk"}, scaled
# The convoy's five spawn/escort paths used by direct (unscaled) builds all exist on the map.
for name in ("apc_spawn", "apc_escort", "apc_path", "apc_nav", "military_spawn", "military_path"):
    assert name in paths, "direct-build path exists: " + name
# The six reinforcement-wave spawn/trigger paths (and their 'a' alternates) all exist on the map.
for name in ("spawn_1", "spawn_2", "spawn_2a", "spawn_3", "spawn_3a", "spawn_4", "spawn_5", "spawn_6",
             "wave_1", "wave_2", "wave_3", "wave_4", "wave_5", "wave_6"):
    assert name in paths, "reinforcement path exists: " + name

# ---------------------------------------------------------------- the weather's sites
sites = (ROOT / "Scripts/CRGanymedeSitesCH08.lua").read_text(encoding="utf-8")
assert 'mission = "chmisn08"' in sites, "generated Ganymede sites belong to chmisn08"
assert re.search(r"vents = \{.+?\}", sites, re.S) and not re.search(r"vents = \{\s*\}", sites), \
    "this Ganymede map has vents (unlike chmisn07's empty list)"
assert "if #europa.GetVentSites() > 0 then europa.TriggerPlume(1) end" in lua_full, "the plume beat is guarded"
assert (ROOT / "Scripts/CREuropaWeather.lua").is_file()

# ---------------------------------------------------------------- audio: every line has a subtitle text
wavs = sorted(set(re.findall(r'"(ch08\d+\.wav)"', live, re.I)), key=str.lower)
assert {w.lower() for w in wavs} == {"ch08%03d.wav" % n for n in range(1, 10)}, wavs
for wav in wavs:
    assert (ROOT / "Text" / (wav[:-4].lower() + ".txt")).is_file(), "no subtitle for " + wav
durations = (ROOT / "Config/durations.csv").read_text(encoding="utf-8")
shipped = set(re.findall(r"^(ch08\d+)\.wav,", durations, re.M))
assert shipped == {w[:-4] for w in wavs}, "no shipped ch08 voice line is left unplayed: " + str(shipped ^ {w[:-4] for w in wavs})

# ---------------------------------------------------------------- companions, checked only when present
ini = ROOT / "Config/chmisn08cr.ini"
if ini.is_file():
    ini_text = ini.read_text(encoding="utf-8")
    assert 'gameType = "S"' in ini_text and 'minPlayers = "2"' in ini_text and 'maxPlayers = "4"' in ini_text
    print("  Config/chmisn08cr.ini checked")
vxt = ROOT / "Missions/chmisn08cr.vxt"
if vxt.is_file():
    assert re.search(r"\bcvtnk\b", vxt.read_text(encoding="utf-8")), "the vehicle list offers the convoy tank"
    print("  Missions/chmisn08cr.vxt checked")

# ---------------------------------------------------------------- the doc accounts for every map path and loose object
doc = (ROOT / "Docs/CHMISN08_COOP.md").read_text(encoding="utf-8")
unused = set(paths) - used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused == {"east_scout", "west_scout", "east_sniper", "west_sniper", "guard_area", "edge_path"}, unused
scripted_prefixes = ("magpull_", "west_mag_", "east_mag_", "sniper_")
loose = {k for k in objects if k.startswith(scripted_prefixes)} - all_handled
for name in sorted(loose):
    assert "`" + name + "`" in doc, "undocumented unscripted unit: " + name
assert loose == set(), "every magpull/mag/sniper label is reached through the loop-concatenated handles: " + str(loose)
for section in ("## Layout", "## Teams and ownership", "## Scaling and concealed arrivals", "## Humans' result",
                "## Cinematics are shared", "## Restored content", "## Stock bugs and co-op fixes in the CR layer",
                "## Weather: Ganymede", "## Tests", "## Inferences and open questions", "## Live checklist"):
    assert section in doc, "doc section missing: " + section
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("chmisn08 co-op contract passed: %d objects, %d paths, %d scripted path names, Ganymede sites present; %d paths unused (documented)"
      % (len(objects), len(paths), len(used), len(unused)))
