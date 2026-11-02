#!/usr/bin/env python3
"""chmisn03 co-op map contract: the labels, paths and teams Scripts/chmisn03cr.lua names exist in Missions/chmisn03cr.bzn.

Skipped (exit 0, says so) when Missions/chmisn03cr.bzn is not in the tree. The vxt and the Config ini files are checked
only when present.
"""
from pathlib import Path
import math
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/chmisn03cr.bzn"
if not bzn_path.is_file():
    print("chmisn03 co-op contract SKIPPED: Missions/chmisn03cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = chmisn03\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = chmisn03cr.bzn" in text

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
    assert team != 2 and perceived != 2, "nothing is left on the authored enemy team 2: " + odf
    assert team in (0, 1, 5), "authored teams are neutral, the Chinese side or the Soviets (5): %s team %d" % (odf, team)
    if team == 5:
        assert perceived == 5, "perceived team follows the move: " + odf
    if label:
        pos = [float(re.search(r"^  posit_%s \[1\] =\n(.*)$" % axis, block, re.M)[1]) for axis in "xyz"]
        objects.setdefault(label[1], (odf, team, pos, perceived))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
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
lua_full = (ROOT / "Scripts/chmisn03cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live_code = "\n".join(line for line in live.split("\n") if not line.lstrip().startswith("--"))
assert 'GetHandle("howitzer_" .. (i + 1))' in live and "for i = 0, 5 do M.howitzers[i]" in live
howitzers = ["howitzer_%d" % n for n in range(1, 7)]
for label in howitzers:
    assert label in objects, "every howitzer label is a map object: " + label
    odf, team, _, perceived = objects[label]
    assert odf == "cvartl" and team == 0 and perceived == 5, "howitzers are neutral artillery perceived as the Soviets: " + label
assert re.findall(r'GetHandle\("(\w+)"\)', live) == [], "the only labels the body resolves are the six howitzers"
assert objects["player_tank"][0] == "cvtnk" and objects["cvminea0_minelayer"][0] == "cvminea", "the briefing's minelayer is on the map"
assert objects["player_tank"][1] == 1 and objects["cvminea0_minelayer"][1] == 1

arrays = {}
for name in ("sounds", "back", "closeTo", "explosionSpot", "spawns", "apcFollow", "defends"):
    block = re.search(r"local %s = \{(.*?)\n?\}" % name, live, re.S)[1]
    arrays[name] = re.findall(r'"([\w.]+)"', block)
for name in ("back", "closeTo", "spawns", "apcFollow", "defends"):
    assert set(arrays[name]) <= set(paths), "array %s names real paths: %s" % (name, set(arrays[name]) - set(paths))
assert set(arrays["explosionSpot"]) <= set(paths) and len(arrays["explosionSpot"]) == 15
used = set(arrays["back"]) | set(arrays["closeTo"]) | set(arrays["explosionSpot"]) | set(arrays["spawns"]) | set(arrays["apcFollow"]) | set(arrays["defends"])
used |= set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live_code))
used |= set(re.findall(r'Goto\([^,]+, "(\w+)"', live_code))
used |= set(re.findall(r'Distance\([^,]+, "(\w+)"\)', live_code))
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
assert {"nav_base", "factory", "factory_path", "base_fail", "trigger_1", "won_mission", "apc_attack", "apc_attack_2",
        "factory_attack"} <= used, used

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local IsValid = campaignRuntime", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in paths and rally == "won_mission", "rally point is the starting base"
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
fallback_paths = re.findall(r'"(\w+)"', fallback)
assert fallback_paths and len(set(fallback_paths)) == len(fallback_paths), "there are distinct alternative approaches"
for name in fallback_paths:
    assert name in paths, "fallback spawn entry exists: " + name
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRGanymedeSitesCH03"' in config and 'module = "CREuropaWeather"' in config
assert '"EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge"' in config, "the Europa wire ops are registered"
assert 'failDes = "ch03lsea.des"' in config and "safeRadius = 250" in config
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
body_odfs = set(re.findall(r'BuildObject\("(\w+)", 2,', live_code))
assert scaled == body_odfs == {"svtank", "svhraz", "svfigh"}, (scaled, body_odfs)
assert re.findall(r'BuildObject\(M\.generalApc == i and "(\w+)" or "(\w+)", 2', live_code) == [("svapcq", "svapcr")], "the APCs are built directly"
for name in ("EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge"):
    assert name in config
# The escape check: the end of each APC route is the (unused in the source) fail point, within the CR radius.
escape = re.search(r"local ESCAPE = \{\[0\] = \"(\w+)\", \"(\w+)\", \"(\w+)\"\}", cr_text)
assert escape and list(escape.groups()) == ["east_fail", "north_fail", "west_fail"]
radius = float(re.search(r"ESCAPE\[math\.floor\(M\.generalApc / 2\)\]\) < ([\d.]+) then", cr_text)[1])
for route, fail in zip(("east_path", "north_path", "west_path"), escape.groups()):
    end = paths[route][-1]
    assert math.dist(end, paths[fail][0]) < radius, "%s ends at %s" % (route, fail)
# ...and well clear of the turn-around exits (the 40 m turn must always come first).
for exit_name, fail in zip(arrays["closeTo"], escape.groups()):
    assert math.dist(paths[exit_name][0], paths[fail][0]) > 150, "the turn-around exit is far from the edge"
# The authored ambush sits outside the CR safe radius from the trigger, so a human at the trigger does not divert it.
for ambush in ("apc_attack", "factory_attack"):
    assert 250 < math.dist(paths["trigger_1"][0], paths[ambush][0]) < 460, ambush
# The seats: five-element route pairs follow the map's howitzer pairs (route i guns are howitzers 2i and 2i+1).
for route, (a, b) in enumerate((("howitzer_1", "howitzer_2"), ("howitzer_3", "howitzer_4"), ("howitzer_5", "howitzer_6"))):
    ex = paths[arrays["closeTo"][route]][0]
    for h in (a, b):
        near = min(range(3), key=lambda k: math.dist((objects[h][2][0], objects[h][2][2]), paths[arrays["closeTo"][k]][0]))
        assert near == route, "%s covers the %s exit" % (h, arrays["closeTo"][route])

# ---------------------------------------------------------------- the weather's vents and sites
sites_path = ROOT / "Scripts/CRGanymedeSitesCH03.lua"
sites = sites_path.read_text(encoding="utf-8")
assert 'mission = "chmisn03"' in sites, "generated Ganymede sites belong to chmisn03"
vents = re.findall(r'\{ x = ([\d.]+), y = [\d.]+, z = ([\d.]+), label = "(\w+)"', sites)
assert len(vents) == 4 and vents[0][2] == "eggeizr17_geyser", "four vents around the start"
for x, z, label in vents:
    assert label in objects, label
    assert abs(float(x) - objects[label][2][0]) < 0.1 and abs(float(z) - objects[label][2][2]) < 1, "the vent sits on the geyser object"
assert "TriggerPlume(1)" in cr_text and "TriggerPlume(2)" in cr_text and "GetVentSites() > 0" in cr_text and "GetVentSites() > 1" in cr_text
assert (ROOT / "Scripts/CREuropaWeather.lua").is_file()

# ---------------------------------------------------------------- audio, objectives and debriefs
wavs = set(w.lower() for w in re.findall(r'"(ch03\d+\.wav)"', live_code, re.I))
restored_wavs = set(w.lower() for w in re.findall(r'"(ch03\d+\.wav)"', cr_text, re.I))
assert wavs == {"ch03%03d.wav" % n for n in (1, 2, 3, 4, 5, 6, 8, 9)}, wavs
assert restored_wavs == {"ch03007.wav"}, restored_wavs
for wav in sorted(wavs | restored_wavs):
    assert (ROOT / "Text" / (wav[:-4] + ".txt")).is_file(), "no subtitle for " + wav
assert wavs | restored_wavs == {"ch03%03d.wav" % n for n in range(1, 10)}, "no unused voice line is left"
assert set(re.findall(r'"(ch03\w+\.des)"', live_code)) == {"ch03lsea.des", "ch03lsec.des", "ch03lsed.des", "ch03lsee.des", "ch03win.des"}
assert set(re.findall(r'"(ch03\w+\.des)"', cr_text)) == {"ch03lseb.des", "ch03lsea.des"}, "the restored escape debrief"
assert set(re.findall(r'"(ch03\d+\.otf)"', live_code)) == {"ch03001.otf", "ch03002.otf", "ch03003.otf"}
# The debrief .des and objective .otf files ship with the game, not in this tree.

# ---------------------------------------------------------------- companions, checked only when present
ini = ROOT / "Config/chmisn03cr.ini"
if ini.is_file():
    ini_text = ini.read_text(encoding="utf-8")
    assert 'gameType = "S"' in ini_text and 'minPlayers = "2"' in ini_text and 'maxPlayers = "4"' in ini_text
    print("  Config/chmisn03cr.ini checked")
crch = ROOT / "Config/crch.ini"
if crch.is_file():
    assert re.search(r'\[MISSION3\][^\[]*missionBZN = "chmisn03cr\.bzn"', crch.read_text(encoding="utf-8")), "campaign entry 3 is this map"
    print("  Config/crch.ini checked")
vxt = ROOT / "Missions/chmisn03cr.vxt"
if vxt.is_file():
    vxt_text = vxt.read_text(encoding="utf-8")
    assert re.search(r"\bcvtnk\b", vxt_text) and re.search(r"\bcvminea\b", vxt_text), "the vehicle list offers the Tank and the Minelayer"
    print("  Missions/chmisn03cr.vxt checked")

# ---------------------------------------------------------------- the doc accounts for every map path
doc = (ROOT / "Docs/CHMISN03_COOP.md").read_text(encoding="utf-8")
all_used = used | set(fallback_paths) | {rally} | set(escape.groups())
unused = set(paths) - all_used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused == {"edge_path", "patrol_path_1", "patrol_path_2", "patrol_path_3", "apc_attack_2_path", "mine_path"}, unused
for name in ("east_fail", "north_fail", "west_fail", "ch03007", "ch03lseb", "cvscav"):
    assert name in doc, "the restored content is documented: " + name
for section in ("## Layout", "## Teams and ownership", "## Scaling and concealed arrivals", "## Humans' result",
                "## Cinematics", "## Restored content", "## Stock bugs and co-op fixes in the CR layer",
                "## Weather: Ganymede", "## Tests", "## Inferences and open questions", "## Live checklist"):
    assert section in doc, "doc section missing: " + section
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("chmisn03 co-op contract passed: %d objects, %d paths, %d scripted path/label names, Ganymede sites present; %d paths unused (documented)"
      % (len(objects), len(paths), len(used) + len(howitzers), len(unused)))
