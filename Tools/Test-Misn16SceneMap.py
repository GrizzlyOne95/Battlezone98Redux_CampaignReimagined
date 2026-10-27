"""Check scene placement, localized terrain edits and packaged native assets."""
from pathlib import Path
import json
import re
import struct
ROOT=Path(__file__).resolve().parents[1]
layout=json.loads((ROOT/'References/Misn16Fury/scene-layout.json').read_text())
assert layout['pad']['x']-60>layout['outside_edge_x']
raw=(ROOT/'Missions/misn16.bzn').read_bytes()
assert b'\n' not in raw.replace(b'\r\n',b'')
text=raw.decode('latin-1').replace('\r\n','\n')
assert 'name = MultSTMission\n' in text and 'TerrainName = misn16\n' in text
objects=text.split('[GameObject]\n')[1:]
assert len(objects)==145
for name,count in [('cr16cmd',1),('cr16hng',1),('cr16pwr',4),('cr16tow',4),('hbtran00',1),('hbtrn200',4),('crfmine',6)]:
    assert len(re.findall(r'(?m)^PrjID \[1\] =\n'+name+'$',text))==count
for label in ['cr16_transport','cr16_pad_look','cr16_evac1','cr16_evac2']:
    assert len(re.findall(r'(?m)^label = '+label+'$',text))==1
for label in layout['scene_paths']:
    assert 'label = '+label+'\n' in text
for block in objects:
    team=int(re.search(r'(?m)^team \[1\] =\n(\d+)$',block)[1])
    if team in (2,3,4): assert 'PrjID [1] =\npspwn_1\n' in block

def diff_points(old,new,offset,size,cell):
    a,b=old.read_bytes(),new.read_bytes()
    assert a[:offset]==b[:offset] and len(a)==len(b)
    changed=[]
    for i,(x,y) in enumerate(zip(struct.iter_unpack('<H',a[offset:]),struct.iter_unpack('<H',b[offset:]))):
        if x!=y:
            zone,local=divmod(i,size*size);zz,zx=divmod(zone,4);z,x=divmod(local,size)
            changed.append(((zx*size+x)*cell,97280+(zz*size+z)*cell))
    assert all(3820<=x<=3980 and 99920<=z<=100080 for x,z in changed) if size==256 else all(3660<=x<=3960 and 99940<=z<=100060 for x,z in changed)
    return len(changed)
assert diff_points(ROOT/'Missions/misn16b.hg2',ROOT/'Missions/misn16.hg2',12,256,5)==24
assert diff_points(ROOT/'Missions/misn16b.mat',ROOT/'Missions/misn16.mat',0,64,20)==54
assert (ROOT/'Missions/misn16.lgt').read_bytes()==(ROOT/'Missions/misn16b.lgt').read_bytes()
assert (ROOT/'Missions/misn16.trn').read_bytes().startswith((ROOT/'Missions/misn16b.trn').read_bytes())
lock={r['source'].replace('\\','/') for r in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
for n in (9,10,11,14,15,16):
    p='Assets/Audio/misn16'+str(n).zfill(2)+'.wav'
    assert p in lock and (ROOT/p).read_bytes()[:4]==b'RIFF'
for stem in ('cr16cmd','cr16hng','cr16pwr','cr16tow'):
    assert 'Materials/'+stem+'.material' in lock
    assert 'Assets/Textures/'+stem+'_d.dds' in lock
print('misn16 scene map: placements, 145 objects, localized pad edits and shipping assets pass')
