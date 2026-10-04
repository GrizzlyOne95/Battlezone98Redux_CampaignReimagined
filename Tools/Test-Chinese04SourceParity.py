"""Run from repository root; no external dependencies."""
import hashlib
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source_path = root / 'References/Chinese04Source/Chinese04Mission.cpp'
raw = source_path.read_bytes()
blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
assert blob == '11fb5b1a3203fd8a5e864ee30578624eb7788827', 'source snapshot changed'
source = raw.decode()
lua = (root / 'Scripts/ch04.lua').read_text()
# Exclude cut blocks from active source asset comparisons, but keep them in the
# hash-protected archive. Dynamic path loops are checked by the decision test.
active = re.sub(r'/\*.*?\*/|//[^\r\n]*', '', source, flags=re.S)
for name in set(re.findall(r'"([^"\r\n]+\.(?:wav|otf|des))"', active)):
    assert '"' + name + '"' in lua, name
for odf in set(re.findall(r'BuildObject\("([^"]+)"', active)):
    assert '"' + odf + '"' in lua, odf
for path in ('camera_start', 'camera_alarm', 'trigger_1', 'fighter_1',
             'fighter_2', 'figh1_path', 'figh2_path', 'chase_1', 'chase_2',
             'chase_3', 'portal_units', 'nav_base', 'auto_end'):
    assert '"' + path + '"' in lua, path
assert 'goto ' not in re.sub(r'--[^\n]*', '', lua), 'Lua 5.2 goto syntax'
print('Chinese04: exact source blob, active asset names and paths passed')
