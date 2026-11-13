#!/usr/bin/env python3
"""bdmisn08 co-op map contract: the labels, paths and teams Scripts/bd08cr.lua names exist in Missions/bd08cr.bzn.

Skipped (exit 0, says so) when Missions/bd08cr.bzn is not in the tree. The multiplayer listing
(Config/bd08cr.ini), the campaign entry (Config/crbd.ini) and Missions/bd08cr.vxt are checked only when present.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
bzn_path = ROOT / "Missions/bd08cr.bzn"
if not bzn_path.is_file():
    print("bdmisn08 co-op contract SKIPPED: Missions/bd08cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = bdmisn08\n" in text
assert "msn_filename = bd08cr.bzn" in text

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
assert objects["portal"] == ("cbport", 5), "the Chinese portal is on the co-op enemy team"
paths = []
for path in text.split("[AiPath]\n")[1:]:
    m = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if m:
        paths.append(m[1])

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/bd08cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--\[\[.*?\]\]", "", live, flags=re.S)
live = re.sub(r"(?m)^\s*--.*$", "", live)
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
assert {"recycler", "portal", "command", "factory", "nav_portal", "nav_base"} <= handles
literals = set(re.findall(r'"(\w+)"', live))
used = literals & set(paths)
assert {"path_camera_intro", "path_portalcam", "attack_path1", "attack_path2", "portal_in", "portal_out", "spawn_pilot"} <= used, used
for name in ("path_camera_intro", "path_portalcam", "attack_path1", "attack_path2", "portal_in", "portal_out", "spawn_pilot"):
    assert re.search(r'"%s"' % name, live), name
# Nothing in the body names a path the map lacks: every quoted token used as a path argument exists.
for name in re.findall(r'(?:CameraPath|Goto|Retreat)\([^,]+, ?"(\w+)"', live) + re.findall(r'BuildObject\([^\n]*"(\w+)"\)', live):
    if name.startswith(("path_", "attack_", "portal_", "spawn_")):
        assert name in paths, "path missing from the map: " + name

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local NativeIsValid", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects, "rally point is a map object"
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRGanymedeSitesBD08"' in config and 'module = "CREuropaWeather"' in config
assert '"EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge"' in config
assert 'failDes = "bd08lose.des"' in config
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
assert scaled == {"cvtnk", "cvltnk", "cvfigh", "cvrckt", "cvhraz"}, scaled
body_attackers = set(re.search(r"local attackers = \{(.*?)\}", live, re.S)[1].replace('"', " ").replace(",", " ").split())
assert scaled == body_attackers, "the scaled ODFs are the body's attackers"
assert "cvapc" not in scaled and "cspilo" not in scaled, "the APC and the pilots are never scaled"
sites = ROOT / "Scripts/CRGanymedeSitesBD08.lua"
sites_text = sites.read_text(encoding="utf-8")
assert sites.is_file() and 'mission = "bdmisn08"' in sites_text, "generated Ganymede sites belong to bdmisn08"
vent_labels = re.findall(r'label = "(\w+)"', sites_text.split("vents", 1)[1])
assert len(vent_labels) == 3 and set(vent_labels) <= set(objects), "every vent is a map geyser: " + str(vent_labels)
for module in ("CREuropaWeather", "CRCCARuntime"):
    assert (ROOT / ("Scripts/%s.lua" % module)).is_file(), module

# ---------------------------------------------------------------- audio: every line has a subtitle, none is left unused
wavs = set(re.findall(r'"(bd08\d+\.wav)"', live))
restored_wavs = set(re.findall(r'"(bd08\d+\.wav)"', cr_text)) - wavs
assert restored_wavs == {"bd08005.wav"}, "the CR layer plays exactly the one line the DLL never plays: " + str(restored_wavs)
for wav in sorted(wavs | restored_wavs):
    assert (ROOT / "Text" / (wav[:-4] + ".txt")).is_file(), "no subtitle for " + wav
shipped = {p.stem + ".wav" for p in (ROOT / "Text").glob("bd08[0-9][0-9][0-9].txt")}
assert shipped == wavs | restored_wavs, "every shipped bd08 voice line is played: " + str(shipped ^ (wavs | restored_wavs))
# The debrief .des files (bd08win, bd08lsea..c, bd08lose) ship with the game, not in this tree.

# ---------------------------------------------------------------- the listing files, when present
ini = ROOT / "Config/bd08cr.ini"
if ini.is_file():
    ini_text = ini.read_text(encoding="utf-8")
    assert 'minPlayers = "2"' in ini_text and 'maxPlayers = "4"' in ini_text
    print("  Config/bd08cr.ini checked")
else:
    print("  Config/bd08cr.ini not present: skipped")
campaign = ROOT / "Config/crbd.ini"
if campaign.is_file():
    assert 'missionBZN = "bd08cr.bzn"' in campaign.read_text(encoding="utf-8")
    print("  Config/crbd.ini checked")
else:
    print("  Config/crbd.ini not present: skipped")
vxt = ROOT / "Missions/bd08cr.vxt"
if vxt.is_file():
    assert vxt.read_bytes().strip(), "the vehicle list is not empty"
    print("  Missions/bd08cr.vxt checked")
else:
    print("  Missions/bd08cr.vxt not present: skipped")

# ---------------------------------------------------------------- the doc accounts for every map path and cut block
doc = (ROOT / "Docs/BDMISN08_COOP.md").read_text(encoding="utf-8")
unused = set(paths) - used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert unused == {"spawn1", "edge_path"}, unused
for cut in ("bd08005", "factory", "TEST_PORTAL", "Stock bugs fixed in the CR layer", "Live checklist", "RESTORED_APC_LOSS_VOICE"):
    assert cut in doc, "the doc must cover: " + cut
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("bdmisn08 co-op contract passed: %d objects, %d paths, %d scripted path/label names, Ganymede sites present; %d paths unused (documented)"
      % (len(objects), len(paths), len(used) + len(handles), len(unused)))
