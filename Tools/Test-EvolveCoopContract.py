#!/usr/bin/env python3
"""evolve co-op map contract: the spawn points Scripts/evolvecr.lua names exist in Missions/evolvecr.bzn.

Skipped (exit 0, says so) when Missions/evolvecr.bzn is not in the tree. Config/evolvecr.ini and the
evolvecr.mpdes lobby blurb are checked only when present.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/evolvecr.bzn"
if not bzn_path.is_file():
    print("evolve co-op contract SKIPPED: Missions/evolvecr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = sammy__1\n" in text, "the stock sammy__1 terrain, not a renamed copy"
assert "msn_filename = evolvecr.bzn" in text
assert "name = MultSTMission" in text and "name = EvolveMission" not in text

# ---------------------------------------------------------------- objects and teams
objects, starts = {}, []
for block in text.split("[GameObject]\n")[1:]:
    label = re.search(r"^label = (.*)$", block, re.M)
    odf = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)[1]
    team = int(re.search(r"^team \[1\] =\n(\d+)$", block, re.M)[1])
    if odf == "pspwn_1":
        starts.append(team)
        continue
    if label:
        objects.setdefault(label[1], (odf, team))
# Every human shares team 1 (owner decision): one shared arena, not one team-start buoy per human.
assert starts == [1, 1, 1, 1], "four team-1 start buoys (every human shares team 1): " + str(starts)
assert objects["asuser0_person"] == ("asusera", 1), "the stock player start is team 1 already"
assert not any(team == 2 for _, team in objects.values()), \
    "nothing is authored on team 2: every attacker is a runtime BuildObject in evolve.lua"

paths = []
for path in text.split("[AiPath]\n")[1:]:
    m = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if m:
        paths.append(m[1])

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/evolvecr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--\[\[.*?\]\]", "", live, flags=re.S)
live = re.sub(r"(?m)^\s*--.*$", "", live)
spawn_prefixes = {"pilot_%d", "sold_%d", "sniper_%d", "spawn_%d"}
assert set(re.findall(r'spawnPrefix="([a-z_%d]+)"', live)) == spawn_prefixes
numbered = {prefix.replace("%d", str(n)) for prefix in spawn_prefixes for n in (1, 2, 3)}
named = set(re.findall(r'spawnpoint="(\w+)"', live))
used = numbered | named
assert used <= set(paths), "a spawn point the Lua names is missing from the map: " + str(used - set(paths))
assert named == {"repair", "ammo", "apmini_1", "apmini_2", "apstab_1", "apstab_2", "apsstb_1", "apsstb_2",
                 "apflsh_1", "apflsh_2", "aptagg_1", "aptagg_2", "cover_1", "cover_2", "cover_3", "cover_4"}

unused = set(paths) - used
assert unused == {"edge_path"}, "undocumented unused map path: " + str(unused)

# ---------------------------------------------------------------- the CR layer
cr_text = "".join(re.findall(region, lua_full))
assert 'leaderTeam = 1, enemyTeam = 2, mapEnemyTeam = 2' in cr_text
assert "humanTeamMin = 1, humanTeamMax = 1" in cr_text, "every human shares team 1"
scaled = set(re.search(r"SCALED_ODFS = \{([^}]*)\}", cr_text, re.S)[1]
              .replace("=", " ").replace("true", " ").replace(",", " ").split())
assert scaled == {"cspilo", "cssolda", "cssold", "cvfigh", "cvltnk", "cvtnk", "cvhraz", "cvwalk", "cvhtnk"}, scaled
body_attackers = set(re.findall(r'attacker="(\w+)"', live))
assert scaled == body_attackers, "the scaled ODFs are exactly the body's wave attackers"
assert "csuserb" not in scaled, "the cover_1..4 items are a different odf and are never scaled"

# ---------------------------------------------------------------- the listing files, when present
ini = ROOT / "Config/evolvecr.ini"
if ini.is_file():
    ini_text = ini.read_text(encoding="utf-8")
    assert 'maxPlayers = "4"' in ini_text and 'gameType = "S"' in ini_text
    print("  Config/evolvecr.ini checked")
else:
    print("  Config/evolvecr.ini not present: skipped")
mpdes = ROOT / "evolvecr.mpdes"
if mpdes.is_file():
    assert mpdes.read_bytes().strip(), "the lobby blurb is not empty"
    print("  evolvecr.mpdes checked")
else:
    print("  evolvecr.mpdes not present: skipped")
for ext in ("trn", "mat", "lgt"):
    assert (ROOT / ("Missions/sammy__1." + ext)).is_file(), "sammy__1." + ext + " terrain companion missing"
hg2 = ROOT / "Missions/sammy__1.hg2"
if not hg2.is_file():
    print("  Missions/sammy__1.hg2 NOT present: the map cannot load in Redux until this is generated")

print("evolve co-op contract passed: %d objects, %d paths (%d used, %d documented unused)"
      % (len(objects), len(paths), len(used), len(unused)))
