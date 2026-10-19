"""Validate the rebuilt rocket's binary geometry, atlas, native bounds and jets."""
from pathlib import Path
import json
import math
import re
import struct

ROOT=Path(__file__).resolve().parents[1]


def chunks(data,start,end):
    while start<end:
        kind,size=struct.unpack_from('<HI',data,start)
        assert size>=6 and start+size<=end,'truncated Ogre chunk'
        yield kind,start+6,start+size
        start+=size
    assert start==end


data=(ROOT/'Assets/ModelFixes/cr06rok.mesh').read_bytes()
head=data.index(b'\n')+1
kind,root_start,root_end=next(chunks(data,head,len(data)))
assert kind==0x3000 and data[root_start]==0,'static Ogre mesh'
submeshes=[]
for kind,start,end in chunks(data,root_start+1,root_end):
    if kind==0x9000:bounds=struct.unpack_from('<7f',data,start)
    if kind!=0x4000:continue
    name_end=data.index(b'\n',start)
    assert data[start:name_end]==b'cr06rok00'
    shared,count,wide=struct.unpack_from('<?I?',data,name_end+1)
    assert not shared and count%3==0
    p=name_end+7
    indices=struct.unpack_from('<%d%s'%(count,'I' if wide else 'H'),data,p)
    p+=count*(4 if wide else 2)
    for ck,gs,ge in chunks(data,p,end):
        if ck!=0x5000:continue
        nv=struct.unpack_from('<I',data,gs)[0]
        for gk,vs,ve in chunks(data,gs+4,ge):
            if gk!=0x5200:continue
            binding,stride=struct.unpack_from('<HH',data,vs)
            assert binding==0 and stride==32
            bk,bs,be=next(chunks(data,vs+4,ve))
            assert bk==0x5210 and be-bs==nv*stride
            vertices=list(struct.iter_unpack('<8f',data[bs:be]))
    assert max(indices)<len(vertices)
    assert all(math.isfinite(x) for v in vertices for x in v)
    assert all(abs(sum(x*x for x in v[3:6])-1)<.005 for v in vertices),'unit normals'
    aligned=degenerate=0
    for i in range(0,count,3):
        a,b,c=[vertices[indices[i+j]] for j in range(3)]
        u=[b[j]-a[j] for j in range(3)];v=[c[j]-a[j] for j in range(3)]
        n=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
        if sum(x*x for x in n)<1e-12:degenerate+=1;continue
        mean=[a[3+j]+b[3+j]+c[3+j] for j in range(3)]
        aligned+=sum(x*y for x,y in zip(n,mean))>0
    assert aligned>=.995*(count/3-degenerate),'normals must agree with triangle winding'
    assert degenerate<count/300,'few degenerate triangles'
    submeshes.append(count//3)
assert len(submeshes)==1 and 10000<sum(submeshes)<25000,'bounded authored mesh budget'
assert abs(bounds[1]+48.5)<.001 and abs(bounds[4]-48.5)<.001,'stable nozzle plane and height'
assert bounds[0]>=-14.2 and bounds[3]<=14.2 and bounds[5]<17,'fits the launch fixture'

geo=(ROOT/'Assets/ModelFixes/cr06rok.geo').read_bytes()
magic,_,name,nv,nf,_=struct.unpack_from('<4si16siii',geo)
assert magic==b'OEG.' and name.rstrip(b'\0')==b'cr06rok'
assert nv<4096 and nf<4096,'light native geometry'
sdf=(ROOT/'Assets/ModelFixes/cr06rok.sdf').read_bytes()
start=sdf.index(b'SGEO')+12
record=struct.unpack_from('<8s12f8s7fiii4f',sdf,start)
assert record[0].rstrip(b'\0')==b'cr06rok' and record[13].rstrip(b'\0')==b'WORLD'
half=record[18:21]
assert half[1]>=48.5 and half[0]>=13.39 and half[2]>14,'updated native bounds'

for suffix,size in [('d',2048),('e',1024),('s',512),('n',16)]:
    dds=(ROOT/'Assets/Textures'/('cr06rok_'+suffix+'.dds')).read_bytes()
    assert dds[:4]==b'DDS ' and struct.unpack_from('<II',dds,12)==(size,size)
    assert struct.unpack_from('<I',dds,80)[0]==0x41 and struct.unpack_from('<I',dds,88)[0]==32,'RGBA8 texture'

layout=(ROOT/'Scripts/CR06RocketLayout.lua').read_text()
jets=[tuple(map(float,m)) for m in re.findall(r'\{(-?[\d.]+),\s*(-?[\d.]+)\}',layout)]
assert len(jets)==8 and len(set(jets))==8
assert all(abs(x*x+z*z-64)<.00001 for x,z in jets),'eight bell exits on the 8m ring'
template=(ROOT/'Materials/cr06_launch.particle.payload').read_text()
core,plume,smoke,dust=template.split('particle_system CR/M06/')[1:]
assert core.startswith('Core') and core.count('emitter Point')==8
assert plume.startswith('Plume') and plume.count('emitter Point')==8
assert sum(map(int,re.findall(r'\bquota\s+(\d+)',template)))==1006,'shared bounded particle quotas'
print('Misn06 rebuilt rocket: geometry, normals, native bounds, RGBA8 atlases and eight nozzle anchors passed')
