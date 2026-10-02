#!/usr/bin/env python3
"""Verify early-mission source provenance, disabled comments and phase inventory.

The ports intentionally change QOL, difficulty and co-op behavior. These checks
protect reconstruction evidence and named phase coverage, not strict call-order
or gameplay equivalence. Test-EarlyMissionFlow.lua covers the corrected blocks.
"""
import hashlib
import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "References/EarlyMissionSources"
checks = 0


def check(value, message):
    global checks
    assert value, message
    checks += 1


# Skip quoted C++ strings/chars when identifying comments.
CPP_TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*[\s\S]*?\*/')


def comments(text):
    return [m for m in CPP_TOKEN.finditer(text) if m[0].startswith(("//", "/*"))]


def active_cpp(text):
    for m in reversed(comments(text)):
        text = text[:m.start()] + "\n" * m[0].count("\n") + text[m.end():]
    return text


def active_lua(text):
    text = re.sub(r"--\[(=*)\[[\s\S]*?\]\1\]", "", text)
    return re.sub(r"--[^\n]*", "", text)


for name, expected in {
    "Tran05Mission.cpp": "f318d388fb7976a40652c88b0fb375dcc18fc93a",
    "Tran05Mission.h": "8b479b59bcdb5fe02e64a11a2270f29b69575968",
    "Misn02Mission.cpp": "7afb97a4628dfcd9634626ca1a43e5e00e2e75f1",
    "Misn03Mission.cpp": "9aa778f241bfd2fa6d4939d7db4da1bdba3821e5",
    "Misn03Mission.h": "2c5d98f54585a63d6fcd9b1a18083cc0a4b625b0",
    "Misn04Mission.cpp": "9cbc6c519f8cdec0759f07de348cd47de20947c5",
    "Misn05Mission.cpp": "e2c612866d09c144356a20cf6c96a7ecf8c1d81f",
    "Misn05Mission.h": "53477ae443c46897ef0754c45b48763b5d3bfeed",
}.items():
    data = (ARCHIVE / name).read_bytes()
    actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    check(actual == expected, "verbatim source blob changed: " + name)

check("uses Tran05Mission.cpp" in (ARCHIVE / "Misn02Mission.cpp").read_text(),
      "misn02b provenance must follow the original source dispatch")

MAPPING = {"misn02b": "Tran05Mission", "misn03": "Misn03Mission",
           "misn04": "Misn04Mission", "misn05": "Misn05Mission"}
COMMENT_COUNTS = {"misn02b": 42, "misn03": 87, "misn04": 84, "misn05": 64}
# Named source phases are present despite intentional timing/unit variations.
PHASES = {
    "misn02b": ["camera1", "camera3", "patrol1", "message1", "message2", "message3",
                "message4", "message5", "last_wave_time", "NextSecond", "mission_lost", "mission_won"],
    "misn03": ["first_wave_done", "start_retreat", "turrets_set", "second_wave_done", "third_wave_done",
               "fourth_wave_done", "scavhunt", "scavhunt2", "help_spawn", "second_objective",
               "start_movie", "movie_over", "trans_underway", "turret_move_done", "ambush_message",
               "third_objective", "second_warning", "last_warning", "final_objective",
               "startfinishingmovie", "show_tank_attack", "tower_dead", "climax1", "climax2",
               "last_blown", "end_shot", "dead1", "dead2", "dead3"],
    "misn04": ["missionstart", "relic", "fetch", "surveysent", "discoverrelic", "relicseen", "reconsent",
               "relicsecure", "ccatugsent", "ccahasrelic", "missionfail2", "warn", "cin1done",
               "wavenumber", "wave1", "wave2", "wave3", "wave4", "wave5", "wave1arrive",
               "wave2arrive", "wave3arrive", "wave4arrive", "wave5arrive", "possiblewin", "basesecure",
               "secureloopbreak", "retreat", "missionwon", "missionfail"],
    "misn05": ["game_start", "randomwave", "needtospawn", "reconfactory", "notfound", "shuffle",
               "sent1Done", "sent2Done", "sent3Done", "sent4Done", "check1", "check2", "check3", "check4",
               "reconed", "neworders", "basewave", "attacktimeset", "platoonhere", "attackcmd",
               "attackstatement", "aw1sent", "aw2sent", "aw3sent", "aw4sent", "possiblewin",
               "missionwon", "missionfail"],
}

for mission, stem in MAPPING.items():
    source = (ARCHIVE / (stem + ".cpp")).read_text()
    lua = (ROOT / "Scripts" / (mission + ".lua")).read_text()
    ledger = lua.split("-- Original DLL comments and cut-content ledger.", 1)[1]
    check(ledger.count("--[==[") == 1 and ledger.endswith("]==]\n"), "cut ledger must remain inactive: " + mission)
    tokens = comments(source)
    check(len(tokens) == COMMENT_COUNTS[mission], "original comment inventory changed: " + mission)
    for m in tokens:
        line = source[:m.start()].count("\n") + 1
        check(stem + ".cpp:" + str(line) + "\n" + m[0] in ledger,
              f"original comment/cut code missing: {stem}.cpp:{line}")
    code = active_lua(lua)
    for phase in PHASES[mission]:
        check(re.search(r"\b" + phase + r"\b", active_cpp(source)) and re.search(r"\bM\." + phase + r"\b", code),
              "native phase/state absent from active port: " + mission + ":" + phase)
    # Preserve native active audio/objective/debrief/AIP names, allowing the
    # already-existing misn02b intro audio replacement explicitly.
    files = set(re.findall(r'"([^"\n]+\.(?:wav|otf|des|aip))"', active_cpp(source)))
    for file in sorted(files):
        if mission == "misn02b" and file == "misn0224.wav":
            check('"misn0201.wav"' in code and '"misn0224.wav"' in lua,
                  "intentional intro replacement and reconstruction reference lost")
        else:
            check('"' + file + '"' in code, "native active asset reference lost: " + mission + ":" + file)

# Archive + inactive ledger also protects details not represented by a named
# phase: reduced/cut units, alternate camera paths, audio, timer edits and the
# mine-system implementation replaced by the intentional static field in Lua.
five = active_lua((ROOT / "Scripts/misn05.lua").read_text())
check('"path_" .. i' in five and re.search(r"for i = 1, 23 do", five), "all 23 intentional static mine locations remain")
check('SetLabel(M.cam1, "Volcano")' not in five and five.count('SetObjectiveName(M.cam1, "Volcano")') == 2,
      "camera display name must not replace its map lookup label")

three_source = (ARCHIVE / "Misn03Mission.cpp").read_text()
three_lua = (ROOT / "Scripts/misn03.lua").read_text()
i = three_source.index("if ((!help_spawn) && (support_time < Get_Time()))")
j = three_source.index("//  Time to evacuate the base", i)
check(three_source[i:j].rstrip() in three_lua, "replaced native escort/arrival block must remain reconstructable")
check("Follow(M.help1, M.rescue1, 0)" in active_lua(three_lua) and "Follow(M.help2, M.rescue2, 0)" in active_lua(three_lua),
      "current QOL transport-escort orders must remain")

spec = importlib.util.spec_from_file_location("validator", ROOT / "Tools/Validate-CampaignRepository.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
for equals in ["", "=", "=="]:
    text = "--[" + equals + "[\ngoto cut;\n]" + equals + "]\nGoto(unit, path)\ngoto live_label"
    code = validator.strip_lua_comments(text)
    check("cut" not in code and "Goto(unit, path)" in code and "goto live_label" in code,
          "validator must distinguish disabled C++ from actual Lua 5.2 syntax")

print(f"early missions: {checks} source preservation/coverage checks passed")
