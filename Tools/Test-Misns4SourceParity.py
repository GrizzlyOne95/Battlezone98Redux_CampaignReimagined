"""Run from repository root: python Tools/Test-Misns4SourceParity.py."""
from pathlib import Path
import hashlib
import re

root = Path(__file__).resolve().parents[1]
source_dir = root / 'References/Misns4Source'
checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1


for filename, expected in (
    ('Misns4Mission.cpp', 'efc5de9d0b4cd4fcfd0165c04319725417f87ae7'),
    ('Misns4Mission.h', '2fd7c8a8ba44333518856982269ad9eac5a2fa77'),
):
    data = (source_dir / filename).read_bytes()
    actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    check(actual == expected, f'{filename}: archive differs from pinned native source')

source = (source_dir / 'Misns4Mission.cpp').read_text()
lua = (root / 'Scripts/misns4.lua').read_text()
# Every string argument in Execute/AddObject, including disabled code, must
# remain present. The archive separately retains native include/save strings.
mission = source[source.index('void Misns4Mission::AddObject(Handle h)'):
                 source.index('IMPLEMENT_RTIME')]
for text in sorted(set(re.findall(r'"([^"\n]*)"', mission))):
    check(f'"{text}"' in lua, f'source mission string missing: {text}')

cut_lines = re.findall(r'^\s*//\s*((?:BuildObject|b2=BuildObject).*?;)', source, re.M)
check(len(cut_lines) == 3, 'unexpected native cut-spawn inventory')
for line in cut_lines:
    check('-- ' + line in lua, f'disabled source line missing: {line}')

for note in ('Notes', 'At some point later', 'Now load an AIP.',
             'Another one bites the dust', 'AudioMessage("transport dead..")',
             "That's it", 'AudioMessage()', 'Cineractive', 'neareset guy',
             'a little reminder', 'wrong message..', 'counter attack in 2 1/2 minutes'):
    check(note in lua, f'native comment/note missing: {note}')

# Ensure dead-data placeholders have not become active new mission content.
active = re.sub(r'--\[\[.*?\]\]', '', lua, flags=re.S)
active = re.sub(r'--[^\n]*', '', active)
for line in cut_lines:
    check(line not in active, f'cut code unexpectedly active: {line}')
print(f'misns4 source parity: {checks} checks passed')
