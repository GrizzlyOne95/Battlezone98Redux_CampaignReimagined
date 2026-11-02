"""Run from repository root; no external dependencies."""
import hashlib
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source_path = root / 'References/Chinese08Source/Chinese08Mission.cpp'
raw = source_path.read_bytes()
blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
assert blob == '319372874b7b9379401b4199562d1fd5c16dbe21', 'source snapshot changed'
source = raw.decode()
lua = (root / 'Scripts/ch08.lua').read_text()
# Exclude cut blocks (comments and #if 0) from the active source comparison but
# keep them in the hash-protected archive.
active = re.sub(r'/\*.*?\*/|//[^\r\n]*', '', source, flags=re.S)
active = re.sub(r'#if 0.*?#endif', '', active, flags=re.S)
lua_code = re.sub(r'--[^\n]*', '', lua)

for name in set(re.findall(r'"([^"\r\n]+\.(?:wav|otf|des|aip))"', active)):
    assert '"' + name + '"' in lua_code, name
for odf in set(re.findall(r'BuildObject\("([^"]+)"', active)):
    assert '"' + odf + '"' in lua_code, odf
for effect in set(re.findall(r'MakeExplosion\([^,]+,\s*"([^"]+)"\)', active)):
    if effect != 'xpltrss':  # legacy-renderer branch; Redux takes xpltrsr
        assert '"' + effect + '"' in lua_code, effect
# Every map path and label the active native code names must be in the Lua.
paths = set(re.findall(r'(?:GetDistance|GetNearestUnitOnTeam|BuildObject|Goto|CameraPath)\([^;]*?"([a-z_0-9]+)"', active))
paths |= set(re.findall(r'MakeExplosion\("([a-z_0-9]+)"', active))
paths |= set(re.findall(r'GetHandle\("([a-z_0-9]+)"\)', active))
for path in sorted(paths):
    if path.startswith(('ch0', 'xplt', 'sv', 'cv', 'apcamr')) or path in ('Base', 'apc_1'):
        continue
    assert '"' + path + '"' in lua_code, path
# Mission states: names and numbers must match the native #defines.
defines = dict(re.findall(r'#define\s+(MS_\w+)\s+(\d+)', source))
assert len(defines) == 37, len(defines)
for name, number in defines.items():
    assert re.search(r'\b%s\b' % name, lua_code), name
# Resolve the packed `local A, B = 1, 2` declarations to compare numerically.
resolved = {}
for line in lua_code.splitlines():
    m = re.match(r'local (MS_[\w, ]+?)\s*=\s*([\d, ]+)$', line)
    if m:
        for n, v in zip([x.strip() for x in m.group(1).split(',')],
                        [x.strip() for x in m.group(2).split(',')]):
            resolved[n] = v
assert resolved == defines, set(resolved.items()) ^ set(defines.items())
# Timing constants of the scripted sequence.
for expr in ('GetTime() + 22', 'GetTime() + 30', 'GetTime() + 25', 'GetTime() + 40',
             'GetTime() + (5 * 60)', 'StartCockpitTimer(60 * 4.5)'):
    assert expr in lua_code, expr
# Cut and unreachable content must stay out of active Lua.
for cut in ('ch08003.otf', 'walker_path', 'walker_return', '"scavs"', 'xpltrss'):
    assert cut not in lua_code, cut
assert 'goto ' not in lua_code, 'Lua 5.2 goto syntax'
print('Chinese08: exact source blob, assets, paths, MS_ states and timers passed')
