"""Add the docked CCA rocket to an already-converted Mission 06 ASCII BZN.

Preserves every authored block byte-for-byte. Also called by Build-CoopMap.py
so regenerating the shared mission cannot silently drop the cinematic prop.
"""
from pathlib import Path
import argparse
import re

ROOT = Path(__file__).resolve().parents[1]
# Stock Redux sblpad raised deck: Ogre bounds X -0.11085..38.92560,
# Z -59.09940..-25.97380 at Y 29.129. Ogre model X is mirrored relative
# to native BZ local X (also confirmed by sbl11bdc's SDF bounds).
# Keep the authored model's -48.5m nozzle plane; leave 25cm deck clearance.
DECK = (-19.407374, 29.129, -42.536600)
CENTRE = (DECK[0], DECK[1] + 48.5 + .25, DECK[2])

def add_rocket(text):
    parts = text.split('[GameObject]\n')
    index, pad = next((i,p) for i,p in enumerate(parts) if 'label = sblpad0_i76building\n' in p)
    def number(key):
        return float(re.search(r'^\s*'+key+r' \[1\] =\n([^\n]+)',pad,re.M)[1])
    origin = [number('posit_'+a) for a in 'xyz']
    centre = [origin[i]+sum(number(axis+'_'+a)*offset for axis,offset in zip(('right','up','front'),CENTRE))
              for i,a in enumerate('xyz')]
    def place(fixture):
        # Update existing fixtures too: regeneration must repair an old anchor.
        for a,v in zip('xyz',centre):
            fixture=re.sub(r'(^  posit_'+a+r' \[1\] =\n)[^\n]+',
                           lambda m:m[1]+f'{v:.9g}',fixture,flags=re.M)
        vector=''.join(f'  {a} [1] =\n{v:.9g}\n' for a,v in zip('xyz',centre))
        fixture=re.sub(r'(^pos \[1\] =\n)(?:  [xyz] \[1\] =\n[^\n]+\n){3}',
                       lambda m:m[1]+vector,fixture,flags=re.M)
        for key in ('v','omega','Accel'):
            fixture=re.sub(r'(^ '+key+r' \[1\] =\n)(?:  [xyz] \[1\] =\n[^\n]+\n){3}',
                lambda m:m[1]+''.join(f'  {a} [1] =\n0\n' for a in 'xyz'),fixture,flags=re.M)
        return fixture
    # The rebuilt dorsal housing faces the clear approach corridor. Its basis
    # matches the pad, replacing the old Resurgence model's 180-degree reversal.
    if 'label = cr06_rocket\n' in text:
        ri,fixture=next((i,p) for i,p in enumerate(parts) if 'label = cr06_rocket\n' in p)
        for axis in ('right','up','front'):
            for a in 'xyz':
                value=number(axis+'_'+a)
                fixture=re.sub(r'(^  '+axis+'_'+a+r' \[1\] =\n)[^\n]+',
                               lambda m:m[1]+f'{value:.9g}',fixture,count=1,flags=re.M)
        parts[ri]=place(fixture)
        return '[GameObject]\n'.join(parts)
    fixture = pad
    for key,value in [('PrjID','cr06rok'),('team','0'),('perceivedTeam','0'),('curHealth','0'),('maxHealth','0')]:
        fixture,n=re.subn(r'^'+key+r' \[1\] =\n[^\n]+',key+' [1] =\n'+value,fixture,count=1,flags=re.M)
        assert n==1,key
    fixture=fixture.replace('label = sblpad0_i76building\n','label = cr06_rocket\n',1)
    serial=int(re.search(r'^seq_count \[1\] =\n(\d+)',parts[0],re.M)[1])
    for key in ('seqno','seqNo'):
        fixture=re.sub(r'^'+key+r' \[1\] =\n\d+',key+' [1] =\n'+str(serial),fixture,count=1,flags=re.M)
    used={int(v,16) for v in re.findall(r'^obj_addr = ([0-9A-Fa-f]+)',text,re.M)}
    address=0x4006
    assert address not in used
    fixture=re.sub(r'^obj_addr = \w+',f'obj_addr = {address:08X}',fixture,count=1,flags=re.M)
    fixture=place(fixture)
    for key in ('v','omega','Accel'):
        fixture=re.sub(r'(^ '+key+r' \[1\] =\n)  x \[1\] =\n[^\n]+\n  y \[1\] =\n[^\n]+\n  z \[1\] =\n[^\n]+',
            lambda m:m[1]+'  x [1] =\n0\n  y [1] =\n0\n  z [1] =\n0',fixture,count=1,flags=re.M)
    parts.insert(index+1,fixture)
    parts[0]=re.sub(r'(^seq_count \[1\] =\n)\d+',lambda m:m[1]+str(serial+1),parts[0],count=1,flags=re.M)
    parts[0]=re.sub(r'(^size \[1\] =\n)(\d+)',lambda m:m[1]+str(int(m[2])+1),parts[0],count=1,flags=re.M)
    return '[GameObject]\n'.join(parts)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('map',nargs='?',type=Path,default=ROOT/'Missions/misn06.bzn')
    path=p.parse_args().map
    raw=path.read_bytes();text=raw.decode('latin1').replace('\r\n','\n')
    path.write_bytes(add_rocket(text).replace('\n','\r\n').encode('latin1'))
    print('Mission 06 docked rocket present; native CRLF retained')
