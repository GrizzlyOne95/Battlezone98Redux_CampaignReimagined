#!/usr/bin/env python3
"""chmisn06 co-op map contract: the labels, paths and teams Scripts/ch06cr.lua names exist in Missions/ch06cr.bzn.

The map, its .vxt and the Config ini are checked only when they are in the tree; the script, the sites, the
subtitles and the doc are always checked.
"""
from collections import Counter
from pathlib import Path
import math
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
lua_full = (ROOT / "Scripts/ch06cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--[^\n]*", "", live)
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local GetPlayerHandle", 1)[0]
doc = (ROOT / "Docs/CHMISN06_COOP.md").read_text(encoding="utf-8")

# ---------------------------------------------------------------- the script's own configuration
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRElysiumSitesCH06"' in config and 'module = "CRElysiumWeather"' in config
assert "ops =" not in config, "Elysium shares the Venus op names (the runtime default)"
assert 'failDes = "ch06lsea.des"' in config
scaled = set(re.findall(r"(\w+) = true", re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1]))
raiders = set(re.findall(r'"(\w+)"', re.search(r"local raidUnits = \{([^}]*)\}", live)[1]))
assert scaled == raiders == {"svfigh", "svltnk", "svtank", "svhraz"}, (scaled, raiders)
assert 'i <= 4 and "cvfigh" or (i <= 8 and "cvtnk" or "cvhraz")' in live, "the convoy is 4 fighters, 4 tanks, 4 bombers"
sites = ROOT / "Scripts/CRElysiumSitesCH06.lua"
assert sites.is_file() and 'mission = "chmisn06"' in sites.read_text(encoding="utf-8"), "generated Elysium sites belong to chmisn06"
for module in ("CRElysiumWeather", "CRVenusWeather", "CRCCARuntime"):
    assert (ROOT / ("Scripts/%s.lua" % module)).is_file(), module
# No Lua string literal may hold an engine basename longer than 8 characters (validator rule).
for literal in re.findall(r'"([^"\n]*)"', live + cr_text):
    m = re.fullmatch(r"([A-Za-z0-9_]+)\.(wav|otf|des|bzn|vxt|ini|odf|lua|aip)", literal)
    assert m is None or len(m[1]) <= 8, "engine basename over 8 characters: " + literal

# ---------------------------------------------------------------- audio: every line has a subtitle, none is left unused
body_wavs = sorted(set(re.findall(r'"(ch06\d+\.wav)"', live)))
assert body_wavs == ["ch06%03d.wav" % n for n in range(1, 7)], body_wavs
restored_wavs = sorted(set(re.findall(r'"(ch06\d+\.wav)"', cr_text)))
assert restored_wavs == ["ch06007.wav"], "the one unused line is slotted by the CR layer: " + str(restored_wavs)
for wav in body_wavs + restored_wavs:
    assert (ROOT / "Text" / (wav[:-4] + ".txt")).is_file(), "no subtitle for " + wav
assert not (ROOT / "Text/ch06008.txt").exists(), "the catalogue is ch06001..ch06007"
assert "ch06win.des" in live and "ch06lsea.des" in live and 'AddObjective("ch06001.otf"' in live
# The debriefs ch06win.des / ch06lsea.des and ch06001.otf ship with the game, not in this tree.

# ---------------------------------------------------------------- the doc
for section in ("## Layout", "## Teams and ownership", "## Scaling and concealed arrivals", "## Humans' result",
                "## Cinematics", "## Restored content", "## Stock bugs and co-op fixes in the CR layer",
                "## Weather: Elysium", "## Tests", "## Inferences and open questions", "## Live checklist"):
    assert section in doc, "doc section missing: " + section
for flag in re.findall(r"(?m)^local (RESTORED_\w+) =", cr_text):
    assert "`" + flag + "`" in doc, "undocumented restoration flag: " + flag
assert sorted(re.findall(r"(?m)^local (RESTORED_\w+) =", cr_text)) == ["RESTORED_DEBRIEF", "RESTORED_RECON_PATROLS", "RESTORED_REVEAL"]
assert "`ch06007`" in doc, "the slotted voice line is documented"
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()

# ---------------------------------------------------------------- the map
bzn_path = ROOT / "Missions/ch06cr.bzn"
if not bzn_path.is_file():
    print("chmisn06 co-op contract: map checks SKIPPED, Missions/ch06cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = chmisn06\n" in text and "msn_filename = ch06cr.bzn" in text

objects, starts, labels, disguised, craft = {}, [], Counter(), [], {}
for block in text.split("[GameObject]\n")[1:]:
    label = re.search(r"^label = (.*)$", block, re.M)
    odf = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)[1]
    team = int(re.search(r"^team \[1\] =\n(\d+)$", block, re.M)[1])
    perceived = int(re.search(r"^perceivedTeam \[1\] =\n(\d+)$", block, re.M)[1])
    pos = [float(re.search(r"^  posit_%s \[1\] =\n(.*)$" % axis, block, re.M)[1]) for axis in "xyz"]
    if odf == "pspwn_1":
        starts.append((team, pos))
        continue
    assert team in (0, 1, 5), "authored teams are neutral, Chinese or the co-op enemy 5: %s team %d" % (odf, team)
    if perceived != team:
        disguised.append((label and label[1], odf, team, perceived))
    if label:
        labels[label[1]] += 1
        objects.setdefault(label[1], (odf, team, pos))
        craft.setdefault(label[1], []).append((odf, team))
assert sorted(t for t, _ in starts) == [1, 2, 3, 4], "one start buoy per human team"
assert not any(team == 2 for _, team, _ in objects.values()), "nothing is left on the authored team 2"
# The Soviet base wears a Chinese disguise in exactly three places: the stolen factory and the two long-range plants.
assert sorted(d[0] for d in disguised) == ["ld_power", "ld_power", "stolen"], disguised
assert all(d[2] == 5 and d[3] == 1 for d in disguised), disguised
paths = {}
for path in text.split("[AiPath]\n")[1:]:
    m = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if m:
        body = path.split("pathType")[0]
        xs = [float(v) for v in re.findall(r"^  x \[1\] =\n(.*)$", body, re.M)]
        zs = [float(v) for v in re.findall(r"^  z \[1\] =\n(.*)$", body, re.M)]
        assert xs and len(xs) == len(zs)
        paths[m[1]] = list(zip(xs, zs))

# Every handle the body asks for is a map object, on the right side.
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
handles |= {"psu_%d" % n for n in range(1, 5)}
assert re.search(r'GetHandle\("psu_" \.\. i\)', live), "the four PSU towers are looked up in a loop"
handles |= set(re.findall(r'GetHandle\("(\w+)"\)', cr_text))
assert handles == {"avrecy2_recycler", "avmuf2_factory", "avslf2_armory", "absilo2_scrapsilo", "absilo3_scrapsilo",
                   "psu_1", "psu_2", "psu_3", "psu_4", "stolen"}, handles
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
for label in handles:
    odf, team, _ = objects[label]
    assert labels[label] == 1, "a looked-up label is unique: " + label
    if label.startswith("av") or label.startswith("ab"):
        assert team == 1, "Chinese side (shared, host-run): " + label
    else:
        assert team == 5, "Soviet side (co-op enemy team): " + label
assert objects["avrecy2_recycler"][0] == "cvrecya" and objects["avmuf2_factory"][0] == "cvmufc"
assert objects["stolen"][0] == "cvmuf", "the stolen factory is a Chinese Muf"
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects and objects[rally][0] == "cvrecya", "rally point is the shared recycler"
# Labels the map gives to several objects: the patrols (six recon fighters) and the long-range plants.
# (The geysers, turrets and a turret tank repeat ODF-style labels that nothing looks up.)
duplicated = ["ld_power", "nw_patrol", "sw_patrol"]
assert set(duplicated) <= {l for l, n in labels.items() if n > 1}
assert not ({l for l, n in labels.items() if n > 1} & handles), "no looked-up label is duplicated"
assert labels["sw_patrol"] == 3 and labels["nw_patrol"] == 3 and labels["ld_power"] == 2
assert set(craft["sw_patrol"]) == set(craft["nw_patrol"]) == {("cvfigh", 1)}, "the recon fighters are Chinese fighters"
for name in duplicated:
    assert "`" + name + "`" in doc, "undocumented duplicate label: " + name

# Every path the body or the CR layer names exists.
used = set(re.findall(r'"(ran_\d(?:_path|_trigger)?|annoy_1(?:_path)?|activate_\d|nav_1)"', live))
used |= {"ran_%d%s" % (n, suffix) for n in (1, 2, 3) for suffix in ("", "_path", "_trigger")}
used |= set(re.findall(r'"(ran_\d)"', live))
used |= {"%s_path" % g for g in ("sw", "nw")} if "_path" in cr_text and '"sw", "nw"' in cr_text else set()
used |= set(re.findall(r'(?:Goto|GetDistance)\([^"\n]*"(\w+)"', cr_text))
assert used == {"ran_1", "ran_2", "ran_3", "ran_1_path", "ran_2_path", "ran_3_path", "ran_1_trigger", "ran_2_trigger",
                "ran_3_trigger", "annoy_1", "annoy_1_path", "activate_1", "activate_2", "nav_1", "sw_path", "nw_path"}, used
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
fallback_paths = re.findall(r'"(\w+)"', fallback)
assert fallback_paths == ["ran_1", "ran_2", "ran_3"], fallback_paths
# Concealed entries: none of the four start positions is within the 460 m safe radius of an entry, so nothing
# arrives in view at the start of the mission.
for entry in ("ran_1", "ran_2", "ran_3", "annoy_1"):
    for team, pos in starts:
        d = math.dist((paths[entry][0][0], paths[entry][0][1]), (pos[0], pos[2]))
        assert d > 460, "%s is %.0f m from the start of team %d" % (entry, d, team)
# The raid route ends at the Chinese base; a raid that falls back to a far edge drives to activate_2, the base.
route = paths["annoy_1_path"]
base = objects["avrecy2_recycler"][2]
assert math.dist(route[-1], (base[0], base[2])) < 100, "annoy_1_path ends at the Chinese base"
assert math.dist(paths["activate_2"][0], (base[0], base[2])) < 100, "activate_2 is the Chinese base"
# The convoy routes end at the base, and each trigger is a point at the base side (75 m gate).
for n in (1, 2, 3):
    assert math.dist(paths["ran_%d_path" % n][-1], (base[0], base[2])) < 100, n
    assert math.dist(paths["ran_%d_trigger" % n][0], (base[0], base[2])) < 200, n
# The restored recon routes end at the base too.
for group in ("sw", "nw"):
    assert math.dist(paths[group + "_path"][-1], (base[0], base[2])) < 200, group

# The surrounding companions of a mission entry (checked when present).
vxt = ROOT / "Missions/ch06cr.vxt"
ini = ROOT / "Config/ch06cr.ini"
crch = ROOT / "Config/crch.ini"
if vxt.is_file():
    vxt_bytes = vxt.read_bytes()
    assert b"cvtnk" in vxt_bytes and b"cvfigh" in vxt_bytes, "the vehicle list offers the tank and the fighter"
if ini.is_file():
    ini_text = ini.read_text(encoding="utf-8")
    assert 'gameType = "S"' in ini_text and 'minPlayers = "2"' in ini_text and 'maxPlayers = "4"' in ini_text
if crch.is_file():
    assert re.search(r'\[MISSION6\][^\[]*missionBZN = "ch06cr\.bzn"', crch.read_text(encoding="utf-8")), "campaign entry 6 is this map"

# ---------------------------------------------------------------- the doc accounts for every map path
unused = sorted(set(paths) - used)
for name in unused:
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused == ["alien_1", "edge_path", "nw_trigger", "sw_trigger"], unused
print("chmisn06 co-op contract passed: %d labels, %d paths, %d scripted path/label names, Elysium sites present; %d paths unused (documented)"
      % (len(objects), len(paths), len(used) + len(handles), len(unused)))
