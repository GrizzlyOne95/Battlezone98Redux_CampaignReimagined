#!/usr/bin/env python3
"""bdmisn03 co-op map contract: the labels, paths and teams Scripts/bdmisn03cr.lua names exist in Missions/bdmisn03cr.bzn.

Skipped (exit 0, says so) when Missions/bdmisn03cr.bzn is not in the tree. The multiplayer listing
(Config/bdmisn03cr.ini), the campaign entry (Config/crbd.ini) and Missions/bdmisn03cr.vxt are checked only when present.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/bdmisn03cr.bzn"
if not bzn_path.is_file():
    print("bdmisn03 co-op contract SKIPPED: Missions/bdmisn03cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = bdmisn03\n" in text
assert "msn_filename = bdmisn03cr.bzn" in text

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
    assert team in (0, 1, 5), "authored teams are neutral, the Black Dog side or the co-op enemy 5: %s team %d" % (odf, team)
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        objects.setdefault(label[1], (odf, team))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert not any(team == 2 for _, team in objects.values()), "nothing is left on the script's enemy team 2"
paths = []
for path in text.split("[AiPath]\n")[1:]:
    m = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if m:
        paths.append(m[1])

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/bdmisn03cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--\[\[.*?\]\]", "", live, flags=re.S)  # the DLL's disabled code stays disabled
live = re.sub(r"(?m)^\s*--.*$", "", live)
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
assert {"recycler", "nav_delta", "geyser1", "bobcat_kill_me_now", "scout_kill_me_now", "evil_tank1"} <= handles
for label in ("evil_scout1", "evil_scout2", "evil_scout3", "evil_scout4", "evil_scout5"):
    assert label in objects, label
used = set(re.findall(r'BuildObject\([^\n]*, \d, "(\w+)"\)', live))
used |= set(re.findall(r'(?:Goto)\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'CameraPath\("(\w+)"', live))
used |= set(re.findall(r'Distance\([^,]+, "(\w+)"\)', live))
used |= set(re.findall(r'GetPathPointCount\((\w+)\)', live)) - {"path"}
used |= {"path_recycler_travel"}  # AtEndOfPath(M.recycler, "path_recycler_travel")
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
assert {"camera_intro", "camera_recycler", "path_recycler_travel", "path_recycler_attack", "spawn_apc", "path_apc_travel",
        "spawn_attack_apc", "trigger_ambush", "spawn_recycler_attack"} <= used
assert {"spawn_random_%d" % n for n in range(1, 5)} | {"spawn_turret_1", "spawn_turret_2", "spawn_turret_guard1",
                                                       "spawn_turret_guard2"} <= used

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local GetPlayerHandle", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects, "rally point is a map object"
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
fallback_paths = re.findall(r'"(\w+)"', fallback)
assert fallback_paths, "there are alternative enemy approaches"
for name in fallback_paths:
    assert name in paths, "fallback spawn entry exists: " + name
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRGanymedeSitesBD03"' in config and 'module = "CREuropaWeather"' in config
assert '"EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge"' in config
assert 'failDes = "bd03lose.des"' in config
assert 'orders = {' in config and '"Hunt"' in config and '"SetCloaked"' in config, "the body's Hunt and SetCloaked reach tickets"
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
body_enemy_odfs = set(re.findall(r'BuildObject\("(\w+)", 2,', live))
body_enemy_odfs |= set(re.findall(r'"(cv\w+)"', live))  # randomUnits and the ambush choices are picked by index
assert scaled <= body_enemy_odfs, scaled
assert scaled == {"cvfigh", "cvfighf", "cvltnk", "cvtnk"}, scaled
assert "cvturr" not in scaled, "static turrets are never scaled"
sites = ROOT / "Scripts/CRGanymedeSitesBD03.lua"
sites_text = sites.read_text(encoding="utf-8")
assert sites.is_file() and 'mission = "bdmisn03"' in sites_text, "generated Ganymede sites belong to bdmisn03"
vent_labels = re.findall(r'label = "(\w+)"', sites_text.split("vents", 1)[1])
assert "geyser1" in vent_labels and set(vent_labels) <= set(objects), "every vent is a map geyser: " + str(vent_labels)
assert 'site.label == "geyser1"' in cr_text, "the deploy beat names the recycler's geyser"
for module in ("CREuropaWeather", "CRCCARuntime"):
    assert (ROOT / ("Scripts/%s.lua" % module)).is_file(), module

# ---------------------------------------------------------------- restorations are gated on what the map carries
for name in re.findall(r'PathExists\("(\w+)"\)', cr_text):
    assert name in paths, "restored content only names map paths: " + name
assert {"spawn_scav", "spawn_turret"} <= set(re.findall(r'PathExists\("(\w+)"\)', cr_text))

# ---------------------------------------------------------------- audio: every line has a subtitle, none is left unused
wavs = set(re.findall(r'"(bd03\d+\.wav)"', lua_full))
for wav in sorted(wavs):
    assert (ROOT / "Text" / (wav[:-4] + ".txt")).is_file(), "no subtitle for " + wav
shipped = {p.stem + ".wav" for p in (ROOT / "Text").glob("bd03[0-9][0-9][0-9].txt")}
assert shipped == wavs, "every shipped bd03 voice line is played by the script: " + str(shipped ^ wavs)
# The debrief .des files (bd03win, bd03lsea, bd03lseb, bd03lose) ship with the game, not in this tree.

# ---------------------------------------------------------------- the listing files, when present
ini = ROOT / "Config/bdmisn03cr.ini"
if ini.is_file():
    ini_text = ini.read_text(encoding="utf-8")
    assert 'minPlayers = "2"' in ini_text and 'maxPlayers = "4"' in ini_text
    print("  Config/bdmisn03cr.ini checked")
else:
    print("  Config/bdmisn03cr.ini not present: skipped")
campaign = ROOT / "Config/crbd.ini"
if campaign.is_file():
    assert 'missionBZN = "bdmisn03cr.bzn"' in campaign.read_text(encoding="utf-8")
    print("  Config/crbd.ini checked")
else:
    print("  Config/crbd.ini not present: skipped")
vxt = ROOT / "Missions/bdmisn03cr.vxt"
if vxt.is_file():
    assert vxt.read_bytes().strip(), "the vehicle list is not empty"
    print("  Missions/bdmisn03cr.vxt checked")
else:
    print("  Missions/bdmisn03cr.vxt not present: skipped")

# ---------------------------------------------------------------- the doc accounts for every map path and cut block
doc = (ROOT / "Docs/BDMISN03_COOP.md").read_text(encoding="utf-8")
restored_paths = {"spawn_scav", "spawn_turret"}
unused = set(paths) - used - restored_paths
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused == {"edge_path"}, unused
for cut in ("evil_scout4", "bd03wina", "bd03winb", "Stock bugs fixed in the CR layer", "Live checklist"):
    assert cut in doc, "the doc must cover: " + cut
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("bdmisn03 co-op contract passed: %d objects, %d paths, %d scripted path/label names, Ganymede sites present; %d path unused (documented)"
      % (len(objects), len(paths), len(used) + len(handles), len(unused)))
