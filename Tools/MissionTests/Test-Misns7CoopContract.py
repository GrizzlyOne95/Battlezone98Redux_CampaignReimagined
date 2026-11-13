#!/usr/bin/env python3
"""misns7 co-op map contract: the labels, paths and teams Scripts/misns7cr.lua names exist in Missions/misns7cr.bzn.

Skipped (exit 0, says so) when Missions/misns7cr.bzn is not in the tree.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
bzn_path = ROOT / "Missions/misns7cr.bzn"
if not bzn_path.is_file():
    print("misns7 co-op contract SKIPPED: Missions/misns7cr.bzn is not present")
    sys.exit(0)

text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
assert "TerrainName = misns7\n" in text and "name = MultSTMission\n" in text
assert "msn_filename = misns7cr.bzn" in text

# ---------------------------------------------------------------- objects and teams
objects, starts, disguised = {}, [], {}
for block in text.split("[GameObject]\n")[1:]:
    label = re.search(r"^label = (.*)$", block, re.M)
    odf = re.search(r"^PrjID \[1\] =\n(.*)$", block, re.M)[1]
    team = int(re.search(r"^team \[1\] =\n(\d+)$", block, re.M)[1])
    perceived = int(re.search(r"^perceivedTeam \[1\] =\n(\d+)$", block, re.M)[1])
    if odf == "pspwn_1":
        starts.append(team)
        continue
    assert team in (0, 1, 5), "authored teams are neutral, the Soviet side or the NSDF on 5: %s team %d" % (odf, team)
    if perceived != team:
        assert perceived == 5, "the only disguise is the NSDF's team 5: " + str(label and label[1])
        disguised[label[1] if label else odf] = (odf, team)
    if label:
        objects.setdefault(label[1], (odf, team))
assert sorted(starts) == [1, 2, 3, 4], "one start buoy per human team"
assert sorted(disguised) == ["guntower1", "guntower2", "stuff1", "stuff2", "svrecycle"], \
    "the five Soviet objects the DLL disguises as team 2 are perceived as team 5: " + str(sorted(disguised))
assert not any(team == 2 for _, team in objects.values()), "nothing is left on the authored team 2"
paths = []
for path in text.split("[AiPath]\n")[1:]:
    label = re.search(r"^label = (.*)$", path.split("pointCount", 1)[0], re.M)
    if label:
        paths.append(label[1])

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / "Scripts/misns7cr.lua").read_text(encoding="utf-8")
region = r"(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?"
cr_text = "\n".join(re.findall(region, lua_full))
live = re.sub(region, "", lua_full)
live = re.sub(r"(?ms)--\[\[.*?\]\]", "", live)
live = re.sub(r"(?m)--[^\n]*", "", live)
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles <= set(objects), "every GetHandle label is a map object: " + str(handles - set(objects))
used = set(re.findall(r'BuildObject\("\w+",\s*\d,\s*"(\w+)"\)', live))
used |= set(re.findall(r'(?:Goto|Retreat|Dropoff)\([^,]+,\s*"(\w+)"', live))
cr_used = set(re.findall(r'(?:Dropoff)\([^,]+,\s*"(\w+)"', cr_text))
assert used <= set(paths), "every path the body names exists: " + str(used - set(paths))
assert cr_used <= set(paths), "every path the CR layer names exists: " + str(cr_used - set(paths))
assert {"power2_spot", "tower3_spot"} <= cr_used, "the expansion restoration names its two shipped paths"
assert objects["avrecycle"] == ("bvrecy", 5) and objects["jail"] == ("bbbar7", 5) and objects["svapc"] == ("svap7", 1)
assert objects["svmuf"][0] == "svmuf" and objects["svrecycle"][0] == "svrecy" and objects["rig"] == ("bvcnst", 5)
assert objects["avsilo"] == ("bbsilo", 5) and objects["geyser3"][0] == "eggeizr1", "restored retreat target exists"

# ---------------------------------------------------------------- the runtime configuration only names real content
config = lua_full.split('require("CRCCARuntime").Create', 1)[1].split("local RESTORED =", 1)[0]
rally = re.search(r'rallyPoints = \{ \[0\] = "(\w+)" \}', config)[1]
assert rally in objects or rally in paths, "rally point is a map object or path"
fallback = re.search(r"fallbackEntries = \{([^}]*)\}", config)[1]
for name in re.findall(r'"(\w+)"', fallback):
    assert name in paths, "fallback spawn entry exists: " + name
used |= set(re.findall(r'"(\w+)"', fallback))
assert "enemyTeam = 5" in config and "mapEnemyTeam = 2" in config and "leaderTeam = 1" in config
assert "scaledOdfs = { bvraz = true }" in config
assert 'sites = "CRTitanSitesS7"' in config and 'module = "CRTitanWeather"' in config
assert 'ops = { "TitanState", "TitanRoll" }' in config and "environment = false" in config
titan = (ROOT / "Scripts/CRTitanWeather.lua").read_text(encoding="utf-8")
assert 'op ~= "TitanState" and op ~= "TitanRoll"' in titan, "the weather ops in the config are the module's wire ops"
for call in ("SetTargetLevel", "Roll"):
    assert re.search(r"function V\.%s\(" % call, titan), "the beats only use real module functions: " + call
sites = ROOT / "Scripts/CRTitanSitesS7.lua"
assert sites.is_file() and 'mission = "misns7"' in sites.read_text(encoding="utf-8"), "generated Titan sites belong to misns7"
assert re.search(r"pools = \{\s*\}", sites.read_text(encoding="utf-8")), "the sites tables are empty: weather must run without them"

# ---------------------------------------------------------------- every ODF the script builds ships in ODF/
odfs = set(re.findall(r'BuildObject\("(\w+)"', live)) | set(re.findall(r'Build\([^,]+,\s*"(\w+)"\)', live + cr_text))
odfs |= set(re.findall(r'IsOdfBase\(h,\s*"(\w+)"\)', live))
for odf in sorted(odfs):
    assert (ROOT / "ODF" / (odf + ".odf")).is_file(), "ODF ships: " + odf

# ---------------------------------------------------------------- audio and text the layer plays
wavs = set(re.findall(r'AudioMessage\("(misns7\d+)\.wav"\)', lua_full))
for name in sorted(wavs):
    assert (ROOT / "Text" / (name + ".txt")).is_file(), "subtitle for " + name
assert "misns700" in wavs

# ---------------------------------------------------------------- the doc accounts for every unused path and cut block
doc = (ROOT / "Docs/MISNS7_COOP.md").read_text(encoding="utf-8") if (ROOT / "Docs/MISNS7_COOP.md").is_file() else ""
unused = set(paths) - used - cr_used
for name in sorted(unused):
    assert "`" + name + "`" in doc, "undocumented unused map path: " + name
for name in ("plan_d", "muf_redirect", "power2_spot", "tower3_spot", "RESTORED_PLAN_D", "RESTORED_MUF_RETREAT",
             "RESTORED_EXPANSION", "misns7f1.des", "SetAIControl", "AddObject"):
    assert name in doc, "the doc covers " + name
for src in ("Docs/CCA_COOP_RUNTIME.md", "Docs/MISNS7_SOURCE_PORT.md"):
    assert (ROOT / src).is_file(), src
print("misns7 co-op contract passed: %d objects, %d paths, %d scripted path/label names, %d wavs, Titan sites present"
      % (len(objects), len(paths), len(used | cr_used) + len(handles), len(wavs)))
