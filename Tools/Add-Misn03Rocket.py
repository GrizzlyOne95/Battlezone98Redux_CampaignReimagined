"""Place the NSDF launch rocket on Mission 03's `launch_pad` in Missions/misn03cr.bzn.

The fixture is a clone of the pad's own block (team 0, health 0, PrjID cr03rok,
label cr03_rocket), the same trick Add-Misn06Rocket.py uses. Re-running repairs
an existing fixture in place, so the step is idempotent. Misn03's BZN is not
produced by Build-CoopMap.py, so this edits the committed file directly:

  python Tools/Add-Misn03Rocket.py [Missions/misn03cr.bzn]

Placement. The art's own pad (abtrans) is the stock ablpad rotated 180 degrees
about Y, and the rocket stands on it. In the stock pad's Ogre mesh frame the
rocket axis is therefore at (-24.745, ., +23.415). Native BZ local X is mirrored
relative to the Ogre mesh (stock ablpad's SDF centre x = +6.2092 for an Ogre mesh
centre x = -6.2092, measured on the N64 pad), exactly as for misn06's deck anchor,
so the native pad-local offset is (+24.745, mid-height, +23.415). The fixture's
basis is the pad's rotated 180 degrees about Y (right and front negated). The
world transform comes from the pad's basis, never from raw axis offsets. The
fixture origin is the mid-height of the rocket (cr06rok's convention), so the
nozzle plane sits 20.2515 above the pad origin.
"""
from pathlib import Path
import argparse
import json
import re

ROOT = Path(__file__).resolve().parents[1]
LABEL, PAD_LABEL, ODF = 'cr03_rocket', 'launch_pad', 'cr03rok'
OBJ_ADDR = 0x4003
# Rocket axis in the stock pad's native local frame (see module docstring).
AXIS_RIGHT, AXIS_FRONT = 24.745, 23.415
BUILD = ROOT / 'References/Misn03Rocket/build.json'


def mid_height():
    return float(json.loads(BUILD.read_text())['mid_height_in_abtrans_frame'])


def add_rocket(text):
    parts = text.split('[GameObject]\n')
    index, pad = next((i, p) for i, p in enumerate(parts) if f'label = {PAD_LABEL}\n' in p)

    def number(block, key):
        return float(re.search(r'^\s*' + key + r' \[1\] =\n([^\n]+)', block, re.M)[1])

    origin = [number(pad, 'posit_' + a) for a in 'xyz']
    # Pad basis columns (right, up, front) in world axes.
    basis = {axis: [number(pad, axis + '_' + a) for a in 'xyz'] for axis in ('right', 'up', 'front')}
    offset = {'right': AXIS_RIGHT, 'up': mid_height(), 'front': AXIS_FRONT}
    centre = [origin[i] + sum(basis[axis][i] * offset[axis] for axis in offset) for i in range(3)]
    # Rotate the fixture 180 degrees about the pad's up axis.
    heading = {'right': [-v for v in basis['right']], 'up': basis['up'],
               'front': [-v for v in basis['front']]}

    def set_vec3(block, key, indent, values):
        pattern = r'(^' + re.escape(key) + r' \[1\] =\n)(?:' + indent + r'[xyz] \[1\] =\n[^\n]+\n){3}'
        vector = ''.join(f'{indent}{a} [1] =\n{v}\n' for a, v in zip('xyz', values))
        return re.sub(pattern, lambda m: m[1] + vector, block, flags=re.M)

    def place(fixture):
        for a, v in zip('xyz', centre):
            fixture = re.sub(r'(^  posit_' + a + r' \[1\] =\n)[^\n]+',
                             lambda m: m[1] + f'{v:.9g}', fixture, count=1, flags=re.M)
        for axis in heading:
            for a, v in zip('xyz', heading[axis]):
                fixture = re.sub(r'(^  ' + axis + '_' + a + r' \[1\] =\n)[^\n]+',
                                 lambda m: m[1] + f'{v:.9g}', fixture, count=1, flags=re.M)
        fixture = set_vec3(fixture, 'pos', '  ', [f'{v:.9g}' for v in centre])
        for key in ('v', 'omega', 'Accel'):
            fixture = re.sub(r'(^ ' + key + r' \[1\] =\n)(?:  [xyz] \[1\] =\n[^\n]+\n){3}',
                             lambda m: m[1] + ''.join(f'  {a} [1] =\n0\n' for a in 'xyz'),
                             fixture, count=1, flags=re.M)
        return fixture

    if f'label = {LABEL}\n' in text:
        ri, fixture = next((i, p) for i, p in enumerate(parts) if f'label = {LABEL}\n' in p)
        parts[ri] = place(fixture)
        return '[GameObject]\n'.join(parts)
    fixture = pad
    for key, value in [('PrjID', ODF), ('team', '0'), ('perceivedTeam', '0'), ('curHealth', '0'), ('maxHealth', '0')]:
        fixture, n = re.subn(r'^' + key + r' \[1\] =\n[^\n]+', key + ' [1] =\n' + value, fixture, count=1, flags=re.M)
        assert n == 1, key
    fixture = fixture.replace(f'label = {PAD_LABEL}\n', f'label = {LABEL}\n', 1)
    serial = int(re.search(r'^seq_count \[1\] =\n(\d+)', parts[0], re.M)[1])
    for key in ('seqno', 'seqNo'):
        fixture, n = re.subn(r'^' + key + r' \[1\] =\n\d+', key + ' [1] =\n' + str(serial), fixture, count=1, flags=re.M)
        assert n == 1, key
    used = {int(v, 16) for v in re.findall(r'^obj_addr = ([0-9A-Fa-f]+)', text, re.M)}
    assert OBJ_ADDR not in used
    fixture = re.sub(r'^obj_addr = \w+', f'obj_addr = {OBJ_ADDR:08X}', fixture, count=1, flags=re.M)
    fixture = place(fixture)
    parts.insert(index + 1, fixture)
    parts[0] = re.sub(r'(^seq_count \[1\] =\n)\d+', lambda m: m[1] + str(serial + 1), parts[0], count=1, flags=re.M)
    parts[0] = re.sub(r'(^size \[1\] =\n)(\d+)', lambda m: m[1] + str(int(m[2]) + 1), parts[0], count=1, flags=re.M)
    return '[GameObject]\n'.join(parts)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('map', nargs='?', type=Path, default=ROOT / 'Missions/misn03cr.bzn')
    path = p.parse_args().map
    raw = path.read_bytes()
    text = raw.decode('latin1').replace('\r\n', '\n')
    path.write_bytes(add_rocket(text).replace('\n', '\r\n').encode('latin1'))
    print('Mission 03 NSDF launch rocket present; native CRLF retained')
