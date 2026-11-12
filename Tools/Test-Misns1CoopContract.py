#!/usr/bin/env python3
"""misns1 co-op map contract: the labels, paths and teams Scripts/misns1cr.lua names exist in Missions/misns1cr.bzn.

Skipped (exit 0, says so) when Missions/misns1cr.bzn is not in the tree yet.
"""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
bzn_path = ROOT / "Missions/misns1cr.bzn"
if not bzn_path.is_file():
    print("misns1 co-op contract SKIPPED: Missions/misns1cr.bzn is not present yet")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = misns1\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = misns1cr.bzn" in text

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
    assert team in (0, 1, 5), "authored teams are neutral, the Soviet side or the CCA on 5: %s team %d" % (odf, team)
    assert perceived == team, "perceived team follows the move: " + str(label and label[1])
    if label:
        objects.setdefault(label[1], (odf, team))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
paths = []
for path in text.split("[AiPath]\n")[1:]:
    paths.append(re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)[1])

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/misns1cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
live = re.sub(region, "", lua_full)
live = re.sub(r"--\[=\[.*?\]=\]", "", live, flags=re.S)
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
used = set(re.findall(r'BuildObject\("\w+", \d, "(\w+)"\)', live))
used |= set(re.findall(r'(?:Goto|MissionGoto)\([^,]+, "(\w+)"', live))
used |= set(re.findall(r'MissionDistance\([^,]+, "(\w+)"\)', live))
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
assert objects["avrecy1_recycler"] == ("bvrecy", 5) and objects["svrecy2_recycler"] == ("svrecy", 1)
assert objects["avmuf1_factory"] == ("bvmuf", 5) and objects["absilo1_i76building"] == ("bbsilo", 5)
for label in ("avfigh3_wingman", "avfigh4_wingman", "avfigh5_wingman", "avtank5_wingman", "avtank6_wingman",
              "avtank7_wingman", "avtank8_wingman"):
    assert objects[label][1] == 5 and objects[label][0] in ("bvraz", "bvtank"), "escorts are CCA team 5: " + label
assert not any(team == 2 for _, team in objects.values()), "nothing is left on the authored team 2"

# ---------------------------------------------------------------- the runtime configuration only names real content
config = lua_full.split("require(\"CRCCARuntime\").Create", 1)[1].split("local RESTORED =", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects, "rally point is a map object"
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
for name in re.findall(r'"(\w+)"', fallback):
    assert name in paths, "fallback spawn entry exists: " + name
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert 'sites = "CRVenusSitesS1"' in config and 'module = "CRVenusWeather"' in config
sites = ROOT / "Scripts/CRVenusSitesS1.lua"
if sites.is_file():
    assert 'mission = "misns1"' in sites.read_text(encoding="utf-8"), "generated Venus sites belong to misns1"
    sites_note = "Venus sites present"
else:
    sites_note = "Venus sites absent (weather runs disabled)"

# ---------------------------------------------------------------- restorations are gated on what the map carries
# The cinematic paths and extra walker pods the DLL cut are NOT in this map; the doc says so and the Lua gates on them.
cut_paths = {"cinpath3", "cinpath4", "geyserpath", "approach", "cinpath1", "walkcam2", "walkcam3", "walkstart3", "spawnwalker3"}
absent = cut_paths - set(paths)
doc = (ROOT / "Docs/MISNS1_COOP.md").read_text(encoding="utf-8")
for name in sorted(cut_paths):
    assert ("`" + name + "`") in doc, "the doc accounts for the cut path " + name
for name in sorted(absent):
    assert ("`" + name + "` (absent)") in doc or ("`" + name + "`") in doc
assert "spawnwalker2" in paths and "`spawnwalker2`" in doc, "present-but-unused extra walker path is documented"
unused = set(paths) - used - cut_paths
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
assert "geyser2" not in objects, "geyser2 does not exist in this map (the lookup is restored but stays nil)"
# The stock body loads Soviet plans for an American base; the CR layer swaps in American copies.
coop = (ROOT / "Scripts/misns1cr.lua").read_text(encoding="utf-8")
for stock, plan in (("misn09.aip", "crns1a.aip"), ("misn14.aip", "crns1b.aip")):
    assert '["%s"] = "%s"' % (stock, plan) in coop, "misns1cr maps %s to %s" % (stock, plan)
    builds = re.findall(r'(?m)^\s*\d+,\s*"(\w+)"', (ROOT / "ODF" / plan).read_text(encoding="ascii"))
    assert builds and all(b.startswith("bv") for b in builds), plan + " builds only Black Dog units: " + str(builds)
    assert "`%s`" % plan in doc, "the doc names " + plan
# ---------------------------------------------------------------- the dropship opening (Scripts/CRDropIn.lua)
drop = (ROOT / "Scripts/CRDropIn.lua").read_text(encoding="utf-8")
drop_code = re.sub(r"--[^\r\n]*", "", drop)
assert 'pcall(require, "CRDropIn")' in coop and not re.search(r'[^p]require\("CRDropIn"\)', coop), "CRDropIn loads through pcall"
assert "if okDropIn then DropIn = module else" in coop, "a failed load leaves DropIn nil: the stock start"
mission_ops = set(re.findall(r'"(Drop\w+)"', re.search(r"for _, op in ipairs\(\{([^}]*)\}\) do\s+dropOps", coop)[1]))
module_ops = set(re.findall(r"(\w+) = true", re.search(r"Drop\.OPS = \{([^}]*)\}", drop_code)[1]))
sent_ops = set(re.findall(r'call\("present", "(\w+)"', drop_code))
assert mission_ops == module_ops == sent_ops == {"DropShip", "DropCrew", "DropGo"}, (mission_ops, module_ops, sent_ops)
assert "presentationOps = dropOps," in coop, "the drop ops ride the runtime's ordered stream (guests acknowledge them)"
assert 'profile = "svdrop"' in coop and "svdrop = {" in drop, "the CCA ship profile"
# the hold gate sits right after the runtime update and returns before the whole stock body
gate = re.search(r"-- CR co-op callback >>\n    if campaignRuntime then\n(.*?)-- CR co-op callback <<\n", coop, re.S)
assert gate and "DropStandby(campaignRuntime); return end" in gate[1] and "if M.dropHold then return end" in gate[1], "hold gate"
assert coop.index("if M.dropHold then return end") < coop.index("if (M.missionstart == false) then"), "the gate is before the stock body"
# the cargo and the stock player spot are real map objects on the Soviet side
for label, odf in (("svrecy2_recycler", "svrecy"), ("svtank0_wingman", "svtank")):
    assert objects.get(label) == (odf, 1), label + " is the stock start: " + str(objects.get(label))
assert 'GetHandle("svrecy2_recycler")' in coop and 'GetHandle("svtank0_wingman")' in coop
lock = {e["source"] for e in json.loads((ROOT / "Shipping/shipping.lock.json").read_text(encoding="utf-8-sig"))["files"]}
for suffix in "cox":
    for folder, ext in (("ODF", "odf"), ("Materials", "material"), ("Assets\\ModelFixes", "mesh"),
                        ("Assets\\ModelFixes", "sdf"), ("Assets\\ModelFixes", "skeleton")):
        rel = "%s\\svdrop%s.%s" % (folder, suffix, ext)
        assert rel in lock and (ROOT / rel.replace("\\", "/")).is_file(), "the svdrop art ships: " + rel
for src in ("Docs/CCA_COOP_RUNTIME.md",):
    assert (ROOT / src).is_file(), src
print("misns1 co-op contract passed: %d objects, %d paths, %d scripted path/label names, %s; %d cut paths absent"
      % (len(objects), len(paths), len(used) + len(handles), sites_note, len(absent)))
