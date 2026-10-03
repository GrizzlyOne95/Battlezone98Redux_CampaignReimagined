"""Archive integrity and asset/branch retention checks for BlackDog08."""
from hashlib import sha1
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
archive = root / 'References/BlackDog08Source/BlackDog08Mission.cpp'
raw = archive.read_bytes()
source = raw.decode('utf-8')
lua = (root / 'Scripts/bdmisn08.lua').read_text(encoding='utf-8')
checks = 0


def check(value, message):
    global checks
    assert value, message
    checks += 1


blob = sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
check(blob == 'f0fbb7371b4a584a4852889e1f33f741ad11695a', 'archive must exactly match upstream Git blob')
gameplay = source[source.index('void BlackDog08Mission::Setup()'):]
assets = set(re.findall(r'"([^"]+)"', gameplay)) - {'Failed to create APC'}
for asset in sorted(assets):
    check('"' + asset + '"' in lua, f'missing source content reference: {asset}')
for fragment in [
    'local TEST_PORTAL = false', 'TEST_PORTAL and 15.0 or 90.0',
    'TEST_PORTAL and 15.0 or 9 * 60.0', 'if not TEST_PORTAL and',
    '--StopAudioMessage(M.intro2Sound);', '--M.sound3Time = GetTime() + 5.0;',
    '--PilotGetOut(apc);', '--GetHealth(factory) <= 0.0f ||',
    'AiProcess::Attach(this, o)', 'o->curPilot = *(PrjID*)"cspilo"',
    'objective1Complete = false', 'objective2Complete = false',
    'objective3Complete = false', 'scheduleLose1 = false',
    'waveHandle', 'function Save()', 'function Load(state)',
]:
    check(fragment in lua, f'missing retained branch/comment/state: {fragment}')
for api in ['PortalOut', 'PortalIn', 'ActivatePortal', 'DeactivatePortal',
            'isPortalActive', 'BuildObjectAtPortal', 'IsTouching',
            'RemovePilot', 'GetIn', 'IsAliveAndPilot']:
    check(re.search(r'\b' + api + r'\(', lua), f'missing stock adaptation: {api}')
check(not re.search(r'\bactivatePortal\(', re.sub(r'--[^\n]*', '', lua)), 'native-only activatePortal leaked into Lua')
check('deactivatePortal(' not in lua, 'native-only deactivatePortal leaked into Lua')
check('GetTeam(' not in lua, 'native-only GetTeam leaked into Lua')
print(f'BlackDog08: {checks} source/archive parity checks passed.')
