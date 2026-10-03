#!/usr/bin/env python3
"""Source provenance/content audit; complements Lua mock behavior tests."""
from collections import Counter
import hashlib
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
data = (root / 'References/BlackDog09Source/BlackDog09Mission.cpp').read_bytes()
digest = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
assert digest == '0f93213b17334acf7c0a408a44cdaf3791e1e644', digest
source = data.decode()
lua = (root / 'Scripts/bdmisn09.lua').read_text()
active = re.sub(r'--[^\n]*', '', lua)
execute = source.split('void BlackDog09Mission::Execute()', 1)[1]
cpp_active = re.sub(r'//[^\n]*', '', execute)
cpp_ids = set(re.findall(r'"([^"\n]*)"', cpp_active))
lua_ids = set(re.findall(r'"([^"\n]*)"', active))
# Source tank labels are loaded by the equivalent loop, not five literals.
lua_ids.update('cvtnk' + str(i) for i in range(1, 6))
assert cpp_ids <= lua_ids, f'missing active IDs: {cpp_ids - lua_ids}'

manifest = Counter(re.findall(r'BuildObject\("([^"\n]*)", 2, "(spawn_deviate\d+)"\)', cpp_active))
port_manifest = Counter(re.findall(r'\{"([^"\n]*)", "(spawn_deviate\d+)"\}', active))
assert manifest == port_manifest, (manifest, port_manifest)
assert sum(manifest.values()) == 11

disabled = re.findall(r'//((?:SetPerceivedTeam|AddObjective)\([^\n]*;)', execute)
assert len(disabled) == 2
for statement in disabled:
    assert statement in lua, f'disabled statement missing: {statement}'
assert not re.search(r'\bObjectiveObjects\s*\(', active)
assert 'activatePortal(' not in active and 'isTouching(' not in active
assert 'ActivatePortal(M.portal)' in active and 'IsTouching(M.user, M.portal)' in active

# Every source member name remains represented, including dormant/cut state.
decls = source.split('IMPLEMENT_RTIME', 1)[0]
members = []
for group in re.findall(r'(?:bool|float|Handle|int)\s+([^;]*\b[bfhi]_last);', decls, re.S):
    group = re.sub(r'//[^\n]*', '', group)
    for item in group.split(','):
        name = re.sub(r'\[.*?\]', '', item).strip()
        if name.endswith('_last'):
            continue
        assert re.search(r'\b' + re.escape(name) + r'\b', lua), f'missing member: {name}'
        members.append(name)
assert len(members) == 45, len(members)
print(f'BlackDog09 source audit passed: exact upstream blob, {len(members)} members, '
      f'{len(cpp_ids)} active IDs, 11 ambush units, 2 disabled statements.')
