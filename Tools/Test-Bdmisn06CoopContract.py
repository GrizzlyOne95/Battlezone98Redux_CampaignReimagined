#!/usr/bin/env python3
"""bdmisn06 co-op map contract: the labels, paths and teams Scripts/bdmisn06cr.lua names exist in Missions/bdmisn06cr.bzn.

Skipped (exit 0, says so) when Missions/bdmisn06cr.bzn is not in the tree. The multiplayer listing
(Config/bdmisn06cr.ini), the campaign entry (Config/crbd.ini) and Missions/bdmisn06cr.vxt are checked only when present.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/bdmisn06cr.bzn"
if not bzn_path.is_file():
    print("bdmisn06 co-op contract SKIPPED: Missions/bdmisn06cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = bdmisn06\n" in text
assert "msn_filename = bdmisn06cr.bzn" in text

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
lua_full = (ROOT / "Scripts/bdmisn06cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--\[==\[.*?\]==\]", "", live, flags=re.S)  # the DLL's disabled code stays disabled
live = re.sub(r"(?m)^\s*--.*$", "", live)
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
for i in range(10):
    handles |= {"silo_attack%d" % (i + 1), "bdtank_%d" % (i + 1)}  # built from "silo_attack" .. (i + 1)
handles |= {"2bdest_1", "2bdest_2", "2bdest_3", "2bdest_7", "2bdest_9", "2bdest_10"}  # the labels table
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
assert "portal" in handles
# portal is a labelled OBJECT, also named as a spawn location (BuildObject("bvapc", 1, "portal")), not a path
used = set(re.findall(r'Spawn\((?:"\w+"|odf), \d, "(\w+)"', live))
used |= set(re.findall(r'Goto, "(\w+)"', live)) | set(re.findall(r'Goto\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'CameraPath\("(\w+)"', live))
used |= set(re.findall(r'GetDistance\([^,]+, "(\w+)"\)', live))
used |= set(re.findall(r'"(fake_attack)"', live))
assert "portal" in used
used.discard("portal")
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
need = {"camera_start", "camera_go", "camera_end_scene", "apc_in", "apc_out", "attack_1", "attack_2", "attack_3",
        "attack_always", "dummy_1", "dummy_1_path", "backup_1", "backup_path", "recycler_spawn", "recycler_path",
        "portal_attack_1", "portal_attack_2", "fake_attack"}
assert need <= used, "missing: " + str(need - used)

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local IsValid", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in paths, "rally point is a map path"
fallback_paths = re.findall(r'"(\w+)"', re.search(r"fallbackEntries = \{([^}]*)\}", config)[1])
assert fallback_paths, "there are alternative enemy approaches"
for name in fallback_paths:
    assert name in paths, "fallback spawn entry exists: " + name
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRGanymedeSitesBD06"' in config and 'module = "CREuropaWeather"' in config
assert '"EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge"' in config
assert 'failDes = "bd06lsea.des"' in config and 'orders = { "Goto", "Attack", "Hunt" }' in config
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text)[1].replace("=", " ").replace("true", " ").replace(",", " ").split())
body_enemy_odfs = set(re.findall(r'"(cv\w+)"', live))
assert scaled <= body_enemy_odfs, scaled
assert scaled == {"cvfigh", "cvtnk", "cvrckt", "cvartl"}, scaled
assert "portal_spawn" in paths and 'PathExists("portal_spawn")' in cr_text, "portal extras use the authored portal exit"
sites = ROOT / "Scripts/CRGanymedeSitesBD06.lua"
sites_text = sites.read_text(encoding="utf-8")
assert 'mission = "bdmisn06"' in sites_text, "generated Ganymede sites belong to bdmisn06"
vent_labels = re.findall(r'label = "(\w+)"', sites_text.split("vents", 1)[1])
assert len(vent_labels) == 4 and set(vent_labels) <= set(objects), "every vent is a map geyser: " + str(vent_labels)
for label in re.findall(r'plume\("(\w+)"\)', cr_text):
    assert label in vent_labels, "a weather beat names a vent that exists: " + label
for module in ("CREuropaWeather", "CRCCARuntime"):
    assert (ROOT / ("Scripts/%s.lua" % module)).is_file(), module

# ---------------------------------------------------------------- audio: every shipped line is played (two restored)
wavs = set(re.findall(r'"(bd06\d+\.wav)"', lua_full))
for wav in sorted(wavs):
    assert (ROOT / "Text" / (wav[:-4] + ".txt")).is_file(), "no subtitle for " + wav
shipped = {p.stem + ".wav" for p in (ROOT / "Text").glob("bd06[0-9][0-9][0-9].txt")}
assert shipped == wavs, "every shipped bd06 voice line is played by the script: " + str(shipped ^ wavs)
body_wavs = set(re.findall(r'"(bd06\d+\.wav)"', live))
assert shipped - body_wavs == {"bd06005.wav", "bd06008.wav"}, "exactly two lines are restored: " + str(shipped - body_wavs)
# The debriefs bd06lsea/b/c and bd06wina ship with the game; bd06lsed does not (the CR layer maps it to bd06lsea).
assert "bd06lsed.des" in live and 'description == "bd06lsed.des"' in cr_text

# ---------------------------------------------------------------- the listing files, when present
ini = ROOT / "Config/bdmisn06cr.ini"
if ini.is_file():
    ini_text = ini.read_text(encoding="utf-8")
    assert 'minPlayers = "2"' in ini_text and 'maxPlayers = "4"' in ini_text
    print("  Config/bdmisn06cr.ini checked")
else:
    print("  Config/bdmisn06cr.ini not present: skipped")
campaign = ROOT / "Config/crbd.ini"
if campaign.is_file():
    assert 'missionBZN = "bdmisn06cr.bzn"' in campaign.read_text(encoding="utf-8")
    print("  Config/crbd.ini checked")
else:
    print("  Config/crbd.ini not present: skipped")
vxt = ROOT / "Missions/bdmisn06cr.vxt"
if vxt.is_file():
    assert vxt.read_bytes().strip(), "the vehicle list is not empty"
    print("  Missions/bdmisn06cr.vxt checked")
else:
    print("  Missions/bdmisn06cr.vxt not present: skipped")

# ---------------------------------------------------------------- the doc accounts for every map path and cut block
doc = (ROOT / "Docs/BDMISN06_COOP.md").read_text(encoding="utf-8")
extra_used = {"portal_spawn", "backup_1"}  # the CR layer (portal extras, rally)
unused = set(paths) - used - extra_used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
for cut in ("bd06lsed", "bd06008", "bd06005", "StartCockpitTimer", "bdtank", "Stock bugs fixed in the CR layer",
            "Live checklist", "RESTORED_VICTORY_LINES", "RESTORED_COCKPIT_TIMER"):
    assert cut in doc, "the doc must cover: " + cut
assert (ROOT / "Docs/CCA_COOP_RUNTIME.md").is_file()
print("bdmisn06 co-op contract passed: %d objects, %d paths, %d scripted path names, Ganymede sites present; %d paths unused (documented)"
      % (len(objects), len(paths), len(used), len(unused)))
