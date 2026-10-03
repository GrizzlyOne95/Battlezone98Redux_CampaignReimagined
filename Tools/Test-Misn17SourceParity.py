#!/usr/bin/env python3
"""Check archived source bytes and gameplay coverage independently of the porter."""
from collections import Counter
from hashlib import sha1
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "References/Misn17Source"
CPP = (SOURCE / "Misn17Mission.cpp").read_text()
LUA = (ROOT / "Scripts/misn17.lua").read_text()
checks = 0


def check(value, message):
    global checks
    assert value, message
    checks += 1


CPP_TOKEN = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[A-Za-z_]\w*|\d+(?:\.\d+)?f?|[^\s]', re.S)
LUA_TOKEN = re.compile(r'--\[==\[.*?\]==\]|--[^\n]*|"(?:\\.|[^"\\])*"|[A-Za-z_]\w*|\d+(?:\.\d+)?|[^\s]', re.S)


def cpp_body(signature):
    text = CPP[CPP.index(signature) + len(signature):]
    tokens = CPP_TOKEN.findall(text)
    depth = 0
    for index, token in enumerate(tokens):
        depth += (token == "{") - (token == "}")
        if token == "}" and depth == 0:
            return tokens[:index + 1]
    raise AssertionError("unterminated C++ method")


def calls(tokens):
    return Counter(token for token, following in zip(tokens, tokens[1:])
                   if following == "(" and re.fullmatch(r"[A-Za-z_]\w*", token))


for name, expected in {
    "Misn17Mission.cpp": "8a3dd976203e79ebae70d30329d4b737fa074764",
    "Misn17Mission.h": "3a567da6ed4802c11dd16caec001362e87956e9e",
}.items():
    content = (SOURCE / name).read_bytes()
    digest = sha1(b"blob " + str(len(content)).encode() + b"\0" + content).hexdigest()
    check(digest == expected, name + " archive must be byte-identical to GitHub")

cpp_bodies = [cpp_body(signature) for signature in (
    "void Misn17Mission::Setup(void)", "void Misn17Mission::AddObject(Handle h)",
    "void Misn17Mission::Execute(void)")]
for body in cpp_bodies:
    for token in body:
        if token.startswith(("//", "/*")):
            check("--[==[" + token + "]==]" in LUA, "source comment/disabled code missing inline")

# Default state includes every native member, even currently unused cut-content
# variables. MINE expands from native storage into a serializable Lua table.
group_sizes = []
members = []
for kind, first, last in (("bool", "missionstart", "b_last"), ("float", "discheck", "f_last"),
                          ("Handle", "savfactory1", "h_last"), ("int", "hint", "i_last")):
    group = re.search(r"\b" + kind + r"\s+(" + first + r"\b.*?)\b" + last, CPP, re.S)[1]
    names = re.findall(r"[A-Za-z_]\w*", group)
    group_sizes.append(len(names) + (52 if "MINE" in names else 0))
    members.extend(names)
    for name in names:
        check(re.search(r"\bstate\." + name + r"\s*=", LUA) is not None, "missing source state " + name)
check(group_sizes == [64, 34, 141, 3], "native state declaration counts")

cpp_tokens = [t for body in cpp_bodies[1:] for t in body if not t.startswith(("//", "/*"))]
lua_tokens = [t for t in LUA_TOKEN.findall(LUA[LUA.index("function AddObject(h)"):LUA.index("function Save()")])
              if not t.startswith("--")]

# Every native gameplay call and every string argument must remain present, with
# only the documented BZR adapters/typo corrections normalized for comparison.
native_calls = calls(cpp_tokens)
lua_calls = calls(lua_tokens)
mapping = {"BuildObject": "Spawn", "GetDistance": "Distance", "GetNearestEnemy": "NearestEnemy",
           "CameraPath": "TargetCameraPath", "CameraObject": "TargetCameraObject",
           "Damage": "DamageValid", "SetName": "NameValid", "SetObjectiveName": "NameValid",
           "SetObjectiveOn": "MarkObjective", "Defend2": "DefendValid", "Attack": "AttackValid",
           "GetWhoTheHellShotMe": "GetWhoShotMe"}
expected_calls = Counter()
for name, count in native_calls.items():
    if name not in {"if", "GetObj"}:
        expected_calls[mapping.get(name, name)] += count
for name, count in expected_calls.items():
    check(lua_calls[name] == count, "gameplay call coverage mismatch: " + name)

source_strings = Counter('"mine10"' if t == '" mine10"' else '"eggeizr1"' if t == '"eggiezr1"' else t
                         for t in cpp_tokens if t.startswith('"'))
for t in cpp_tokens:
    if t in {"WHITE", "GREEN"}:
        source_strings['"' + t.lower() + '"'] += 1
lua_strings = Counter(t for t in lua_tokens if t.startswith('"'))
check(source_strings == lua_strings, "gameplay assets, labels, path strings or objective colors omitted/added")

# Calls with hundreds of repeated mine literals can conceal a missing endpoint.
# Both source paths must explicitly retain the full ordered 1..53 field.
mine_spawns = re.findall(r'M\.MINE\[(\d+)\] = Spawn\("boltmine2", 2, "mine(\d+)"\)', LUA)
check(mine_spawns == [(str(i), str(i)) for _ in range(2) for i in range(1, 54)], "both minefield branches cover 1..53 in order")
check('AttackValid(M.deftow7a, M.badman13, 1)' in LUA, "retaliation fix")
check('M.minecount = 0' in LUA and 'M.minecount > 53' in LUA, "source mine destruction cadence")
check('M.minecount >= 1 and M.minecount <= 53' in LUA, "mine array bounds correction")
check('M.spawntime1 = GetTime() + 400.0' in LUA and 'M.sf4blow = GetTime() + 2.5' in LUA, "source timer constants")
check('return M' in LUA and 'M = state' in LUA, "persistent mission state")
check('/*if\n\t\t(cineractive1 == false)' in LUA, "cut alternate cinematic remains commented")
print(f"misn17 source parity: {checks} checks passed")
