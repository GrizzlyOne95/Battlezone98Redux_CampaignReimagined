"""Mission/aiCore ownership contracts: which brain runs each enemy team, and no global shadowing."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]


def active_lua(path):
    src = (root / path).read_text(encoding='utf-8', errors='replace')
    src = re.sub(r'--\[(=*)\[.*?\]\1\]', '', src, flags=re.S)
    return src, re.sub(r'--[^\n]*', '', src)


# aiCore must never define engine-visible globals that hide native functions.
core = (root / 'Scripts/aiCore.lua').read_text(encoding='utf-8')
for name in ('SetAIP', 'GetMass', 'SetMass'):
    assert not re.search(r'^function ' + name + r'\(', core, flags=re.M), 'aiCore must not define a global ' + name
    assert not re.search(r'^' + name + r'\s*=', core, flags=re.M)
assert 'function aiCore.SetStrategyFromAip(' in core and 'function aiCore.SetAIP(' not in core
assert 'exu.getmass' not in core and 'exu.setmass' not in core and 'exu.setunitturbo' not in core

# misn02b: native AIP brain. SetAIControl is a single chunk-root call; the native SetAIP runs only
# from Start/load functions (never at chunk load); aiCore base/factory/tactical management stays off.
raw, lua = active_lua('Scripts/misn02b.lua')
assert len(re.findall(r'SetAIControl\(', lua)) == 1 and re.search(r'^SetAIControl\(ENEMY_TEAM, true\)\r?$', raw, flags=re.M)
assert raw.index('SetAIControl(ENEMY_TEAM, true)') < raw.index('function Start()')
for m in re.finditer(r'^\s*SetAIP\(', lua, flags=re.M):
    line_start = lua.rfind('\nfunction ', 0, m.start()), lua.rfind('\nlocal function ', 0, m.start())
    assert max(line_start) != -1, 'native SetAIP must be inside a function, never at chunk load'
assert re.search(r'(?<![\w.])SetAIP\("misn02\.aip", ENEMY_TEAM\)', lua)
for flag in ('manageBase', 'manageFactories', 'manageTacticalOrders', 'autoBuild'):
    assert re.search(r'enemyTeam:SetConfig\("' + flag + r'", false\)', lua), 'misn02b enemy ' + flag + ' must stay off'

# misn05: aiCore Lua brain. No SetAIControl, no native SetAIP; the shim picks the strategy.
raw, lua = active_lua('Scripts/misn05.lua')
assert not re.search(r'SetAIControl\(', lua)
assert not re.search(r'(?<![\w.])SetAIP\(', lua)
assert 'aiCore.SetStrategyFromAip("misn05.aip", ENEMY_TEAM)' in lua

# misn04 pilot mode (single-player only) explicitly re-enables what human teams no longer get by default.
raw, lua = active_lua('Scripts/misn04.lua')
assert lua.count('manageBase = true,') >= 2 and lua.count('manageTacticalOrders = true,') >= 2

# Pilot Mode never runs in multiplayer.
ppm = (root / 'Scripts/PlayerPilotMode.lua').read_text(encoding='utf-8')
assert 'local function IsMultiplayer()' in ppm and ppm.count('IsMultiplayer()') >= 8
cfg = (root / 'Scripts/PersistentConfig.lua').read_text(encoding='utf-8')
assert 'Off (multiplayer)' in cfg and '_IsPilotModeLocked' in cfg

print('aiCore mission ownership contracts passed')
