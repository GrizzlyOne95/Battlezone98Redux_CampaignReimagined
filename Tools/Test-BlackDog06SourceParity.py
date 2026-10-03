#!/usr/bin/env python3
"""Source-derived completeness checks for the BlackDog06 Lua port."""
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
raw = (ROOT / 'References/BlackDog06Source/blackdog06mission.cpp').read_bytes()
assert hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest() == \
    '4103fbfa8032b89fc3592c46f2366e4f0f115839', 'native source/comments changed'
source = raw.decode().replace('\r\n', '\n')
lua = (ROOT / 'Scripts/bd06.lua').read_text()
active = re.sub(r'--\[==\[.*?\]==\]', '', lua, flags=re.S)
active = re.sub(r'--[^\n]*', '', active)

# Native state values must remain explicit, including inert cut states.
states = dict(re.findall(r'#define\s+(MS_\w+)\s+(\d+)', source))
assigned = {}
for names, values in re.findall(r'local (MS_[^\n=]+) = ([\d, ]+)', active):
    assigned.update(zip([x.strip() for x in names.split(',')],
                        [x.strip() for x in values.split(',')]))
assert len(states) == 25 and states == assigned, 'mission state numbers changed'

# Both substantial disabled gameplay blocks are inert and text-complete.
cut = re.findall(r'/\*(.*?)\*/', source, re.S)[1:]
comments = re.findall(r'--\[==\[(.*?)\]==\]', lua, re.S)
for block in cut:
    words = block.split()
    assert any(' '.join(words) in ' '.join(c.split()) for c in comments), 'cut block lost'
assert 'GetCurHealth(M.bdtank' not in active, 'cut friendly-damage gate enabled'
assert 'StartCockpitTimer(' not in active and 'HideCockpitTimer(' not in active
assert 'bd06008.wav' not in active and 'bd06005.wav' not in active

# Every referenced asset (including disabled audio) is preserved in the port.
for asset in set(re.findall(r'"([^"]+\.(?:wav|otf|des))"', source)):
    assert f'"{asset}"' in lua, f'asset missing: {asset}'
for asset in ('bd06001.wav', 'bd06002.wav', 'bd06003.wav', 'bd06004.wav',
              'bd06006.wav', 'bd06007.wav', 'bd06009.wav'):
    assert f'"{asset}"' in active, f'active audio missing: {asset}'

# Spawn calls collapsed into loops must retain each source group count and order.
groups = [(2, 'cvtnk', 2, 'attack_1', 'Attack', 'M.user'),
          (3, 'cvtnk', 2, 'attack_2', 'Attack', 'M.user'),
          (2, 'bvrdeva', 1, 'recycler_spawn', 'Follow', 'M.recycler'),
          (5, 'cvtnk', 2, 'attack_3', 'Hunt', None),
          (3, 'cvartl', 2, 'portal_attack_1', 'Attack', 'M.portal'),
          (7, 'cvtnk', 2, 'dummy_1', 'Goto', '"dummy_1_path"'),
          (7, 'cvfigh', 2, 'portal_attack_2', 'Attack', 'M.portal')]
for n, odf, team, path, command, target in groups:
    pattern = r'BuildObject\("' + odf + r'", ' + str(team) + r', "' + path + r'"\)'
    native_calls = len(re.findall(pattern, source))
    if path in ('dummy_1', 'portal_attack_2'):
        assert native_calls == 1 and re.search(
            r'for\(i = 0; i < ' + str(n) + r'; i\+\+\)\s*\{\s*temp = ' + pattern,
            source), (path, n)
    else:
        assert native_calls == n, (path, n)
    call = f'Spawn("{odf}", {team}, "{path}", {command}'
    if target is not None:
        call += ', ' + target
    call += ')'
    assert f'for i = 0, {n - 1} do ' in active and call in active, (path, n)
assert 'Spawn("bvrecy", 1, "recycler_spawn", Goto, "recycler_path")' in active
assert 'Spawn("bvapc", 1, "portal", Goto, "apc_out")' in active
assert 'for i = 0, 9 do' in active and 'for i = 0, 5 do' in active
for label in re.findall(r'h2bdest\[\d\] = GetHandle\("([^"]+)"\)', source):
    assert f'"{label}"' in active
for path, height, speed in re.findall(r'CameraPath\("([^"]+)", (\d+), (\d+)', source):
    assert f'CameraPath("{path}", {height}, {speed},' in active
assert 'GetDistance(apc, "apc_in") < 100' in active
assert 'IsOdf(apc, "bvapc")' in active and 'for apc in AllObjects()' in active
assert 'Deploy(M.recycler)' in active and 'AiCommand.NONE' in active
assert all(f'"{odf}"' in active for odf in ('cvfigh', 'cvtnk', 'cvrckt'))
assert 'r < 0.33' in active and 'r < 0.66' in active and 'math.random() < 0.5' in active
assert 'function Save() return M end' in active and 'function Load(state)' in active
print('BlackDog06 source parity: exact archive, 25 states, cut blocks, assets, waves and API mappings passed')
