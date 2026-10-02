"""Run from repository root: python Tools/Test-Misns6SourceParity.py."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]
expected = {
    "Misns6Mission.cpp": "d00a5728a0a925755807683d6d09a234d3afe593",
    "Misns6Mission.h": "2fd7c8a8ba44333518856982269ad9eac5a2fa77",
}
for name, sha in expected.items():
    data = (ROOT / "References/Misns6Source" / name).read_bytes()
    blob = b"blob " + str(len(data)).encode() + b"\0" + data
    assert hashlib.sha1(blob).hexdigest() == sha, name + ": archived source differs"

source = (ROOT / "References/Misns6Source/Misns6Mission.cpp").read_text()
lua = (ROOT / "Scripts/misns6.lua").read_text()
# The byte-identical archive above preserves ALL comments and conditional code.
# Strip comments from both languages before comparing active mission assets.
active_cpp = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
active_lua = re.sub(r'--\[=\[.*?\]=\]|--\[\[.*?\]\]|--[^\n]*', '', lua, flags=re.S)
for ext in ('wav', 'otf', 'aip', 'des'):
    assets = set(re.findall(r'"([^"\n]+\.' + ext + r')"', active_cpp))
    ported = set(re.findall(r'"([^"\n]+\.' + ext + r')"', active_lua))
    assert assets == ported, (ext, assets - ported, ported - assets)
for label in re.findall(r'GetHandle\("([^"]+)"\)', active_cpp):
    assert 'GetHandle("' + label + '")' in active_lua, label
for odf in set(re.findall(r'BuildObject\("([^"]+)"', active_cpp)):
    assert '"' + odf + '"' in active_lua, odf
assert 'BuildObject("svrecy"' not in active_lua, 'cut recycler spawn was activated'
# State member audit: source union declarations, including unused fields and
# all six miner slots, must survive. b/f/h/i_last are native layout sentinels.
declarations = re.search(r'// bools(.*?)void Misns6Mission::Setup', source, re.S)[1]
fields = []
for declaration in re.findall(r'\b(?:bool|float|Handle|int)\s+(.*?);', declarations, re.S):
    if '{' in declaration or '}' in declaration or '_array' in declaration:
        continue
    fields.extend(re.findall(r'\b[A-Za-z_]\w*\b', re.sub(r'\[\d+\]', '', declaration)))
for field in fields:
    if field in ('b_last', 'f_last', 'h_last', 'i_last'):
        continue
    assert re.search(r'\b' + field + r'\s*=', lua), field
assert 'for i = 1, 6 do' in lua
assert 'IsBusy(' not in active_lua
assert 'GetLastEnemyShot(h) > 0' in active_lua
print('misns6 source parity: exact C++/header blobs, assets, labels, ODFs and state verified')
