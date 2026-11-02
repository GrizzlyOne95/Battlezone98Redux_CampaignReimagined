#!/usr/bin/env python3
"""evolve co-op map contract: the spawn points Scripts/evolvecr.lua names exist in Missions/evolvecr.bzn.

Skipped (exit 0, says so) when Missions/evolvecr.bzn is not in the tree. Config/evolvecr.ini and the
evolvecr.mpdes lobby blurb are checked only when present.
"""
from pathlib import Path
import array
import re
import struct
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
objects, starts, start_xz = {}, [], []
for block in text.split("[GameObject]\n")[1:]:
    label = re.search(r"^label = (.*)$", block, re.M)
    odf = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)[1]
    team = int(re.search(r"^team \[1\] =\n(\d+)$", block, re.M)[1])
    if odf == "pspwn_1":
        starts.append(team)
        start_xz.append(tuple(float(v) for v in re.findall(r"^  posit_[xz] \[1\] =\n(.*)$", block, re.M)))
        continue
    if label:
        objects.setdefault(label[1], (odf, team))
# Standard CR co-op layout: one team-start buoy per human team 1-4.
assert starts == [1, 2, 3, 4], "one start buoy per human team 1-4: " + str(starts)
assert objects["asuser0_person"] == ("asusera", 1), "the stock player start is team 1 already"
assert not any(team == 2 for _, team in objects.values()), \
    "nothing is authored on team 2: every attacker is a runtime BuildObject in evolve.lua"

paths, path_xz = [], {}
for path in text.split("[AiPath]\n")[1:]:
    m = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if m:
        paths.append(m[1])
        path_xz[m[1]] = list(zip(*(map(float, re.findall(r"^  %s \[1\] =\n(.*)$" % a, path, re.M))
                                   for a in "xz")))

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
assert 'leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2' in cr_text
assert "humanTeamMin" not in cr_text and "humanTeamMax" not in cr_text, "humans use the default teams 1-4"
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
# ---------------------------------------------------------------- the terrain (converted from TRO's sammy__1.hgt)
# HG2: 12-byte header (u16 version 1, zone bits 8, zones x, zones z; u32 map version), then 256x256 u16 per
# zone, zone-major then row-major, 5 m per sample, 0.1 m per unit (Modding Toolbox LEGACY_HGT_TO_HG2.md).
hg2 = ROOT / "Missions/sammy__1.hg2"
raw = hg2.read_bytes()
version, bits, zx, zz, map_version = struct.unpack_from("<4HI", raw)
assert (version, bits, zx, zz) == (1, 8, 4, 4) and map_version >= 10, "sammy__1.hg2 header"
assert len(raw) == 12 + zx * zz * 0x20000, "sammy__1.hg2 payload matches its 4x4 zones"
heights = array.array("H", raw[12:])
trn = (ROOT / "Missions/sammy__1.trn").read_text(encoding="latin-1")
min_x, min_z = (float(re.search(r"^%s=(.*)$" % k, trn, re.M)[1]) for k in ("MinX", "MinZ"))

def terrain(x, z):
    col, row = round((x - min_x) / 5), round((z - min_z) / 5)
    return heights[(row >> 8) * zx * 0x10000 + (col >> 8) * 0x10000 + (row & 255) * 256 + (col & 255)] / 10

floor = terrain(*start_xz[0])
assert floor == 165.0, "team 1 starts on the 165 m floor the stock objects were authored at: %s" % floor
assert all(len(xz) == 2 for xz in start_xz), "each start buoy has one posit_x and one posit_z"
for i, (x, z) in enumerate(start_xz):
    assert terrain(x, z) == floor, "co-op start %d is on the floor, not in a wall: %s" % (i + 1, terrain(x, z))
    if i:  # the generated starts, not the stock one (which has a wall 5 m off)
        around = max(terrain(x + dx, z + dz) for dx in (-5, 0, 5) for dz in (-5, 0, 5))
        assert around == floor, "co-op start %d has a wall within 5 m: %s" % (i + 1, around)
for label in used:
    for xz in path_xz[label]:
        assert terrain(*xz) <= floor, "spawn point %s is on the arena floor: %s" % (label, terrain(*xz))
print("  Missions/sammy__1.hg2 checked: starts on the arena floor, used spawn points at or below it")

print("evolve co-op contract passed: %d objects, %d paths (%d used, %d documented unused)"
      % (len(objects), len(paths), len(used), len(unused)))
