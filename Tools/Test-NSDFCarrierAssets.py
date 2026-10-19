"""Native-loader invariants for the standalone cinematic NSDF carrier."""
import json
import math
from pathlib import Path
import struct

ROOT=Path(__file__).resolve().parents[1]

def chunks(data,start,end):
    while start<end:
        kind,size=struct.unpack_from('<HI',data,start)
        assert size>=6 and start+size<=end,'truncated Ogre chunk'
        yield kind,start+6,start+size
        start+=size
    assert start==end

data=(ROOT/'Assets/ModelFixes/crncarr.mesh').read_bytes()
head=data.index(b'\n')+1
assert data[2:head]==b'[MeshSerializer_v1.100]\n'
kind,start,end=next(chunks(data,head,len(data)));assert kind==0x3000 and data[start]==0
submeshes=0
for kind,ss,se in chunks(data,start+1,end):
    if kind==0x9000:bounds=struct.unpack_from('<7f',data,ss)
    if kind!=0x4000:continue
    submeshes+=1;ne=data.index(b'\n',ss)
    assert data[ss:ne]==b'crncarr00'
    shared,count,wide=struct.unpack_from('<?I?',data,ne+1)
    assert not shared and count%3==0
    pos=ne+7;indices=struct.unpack_from('<%d%s'%(count,'I' if wide else 'H'),data,pos)
    pos+=count*(4 if wide else 2)
    for k,gs,ge in chunks(data,pos,se):
        if k!=0x5000:continue
        nv=struct.unpack_from('<I',data,gs)[0]
        for kk,vs,ve in chunks(data,gs+4,ge):
            if kk!=0x5200:continue
            binding,stride=struct.unpack_from('<HH',data,vs)
            assert binding==0 and stride==32
            _,bs,be=next(chunks(data,vs+4,ve))
            vertices=list(struct.iter_unpack('<8f',data[bs:be]))
    assert max(indices)<len(vertices) and len(vertices)==nv
    assert 10000<count//3<35000 and nv<65536,'bounded static cinematic mesh'
    assert all(math.isfinite(x) for v in vertices for x in v)
    assert all(abs(sum(x*x for x in v[3:6])-1)<.006 for v in vertices),'unit normals'
    wrong=valid=0
    for i in range(0,count,3):
        a,b,c=[vertices[indices[i+j]] for j in range(3)]
        u=[b[j]-a[j] for j in range(3)];v=[c[j]-a[j] for j in range(3)]
        normal=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
        if sum(x*x for x in normal)<1e-10:continue
        valid+=1
        wrong+=sum(normal[j]*(a[3+j]+b[3+j]+c[3+j]) for j in range(3))<=0
    assert wrong<valid*.005,'native backface winding must match normals'
assert submeshes==1
assert 240<bounds[5]-bounds[2]<248 and 56<bounds[3]-bounds[0]<62
assert bounds[1]<-30 and bounds[4]>38,'bridge/radome/underbody are inside culling bounds'

geo=(ROOT/'Assets/ModelFixes/crncarr.geo').read_bytes()
magic,_,name,nv,nf,_=struct.unpack_from('<4si16siii',geo)
assert magic==b'OEG.' and name.rstrip(b'\0')==b'crncarr'
assert 0<nv<4096 and 0<nf<4096,'native geometry table limits'
sdf=(ROOT/'Assets/ModelFixes/crncarr.sdf').read_bytes();offset=sdf.index(b'SGEO')+12
rec=struct.unpack_from('<8s12f8s7fiii4f',sdf,offset)
assert rec[0].rstrip(b'\0')==b'crncarr' and rec[13].rstrip(b'\0')==b'WORLD'
center=rec[14:17];half=rec[18:21]
for i in range(3):
    assert abs(center[i]-half[i]-bounds[i])<.01 and abs(center[i]+half[i]-bounds[3+i])<.01

for suffix,size in [('d',2048),('e',2048),('s',512),('n',16)]:
    d=(ROOT/'Assets/Textures'/('crncarr_'+suffix+'.dds')).read_bytes()
    assert d[:4]==b'DDS ' and struct.unpack_from('<II',d,12)==(size,size)
    assert struct.unpack_from('<I',d,80)[0]==0x41 and struct.unpack_from('<I',d,88)[0]==32,'RGBA8 avoids the old BC3 colour path'
    if suffix=='n':assert d[128:132]==bytes((255,128,128,255)),'neutral BGRA tangent normal'

odf=(ROOT/'ODF/crncarr.odf').read_text()
assert 'classLabel = "i76building"' in odf and 'maxHealth = 0' in odf
mat=(ROOT/'Materials/crncarr.material').read_text()
for suffix in 'dens':assert 'crncarr_'+suffix+'.dds' in mat
manifest=json.loads((ROOT/'References/NSDFCarrier/geometry.json').read_text())
assert len(manifest['engine_exits'])==8 and len({tuple(p) for p in manifest['engine_exits']})==8
assert all(abs(p[2]-122.8)<.001 for p in manifest['engine_exits'])
assert (ROOT/'References/NSDFCarrier/NSDF-Carrier.blend').stat().st_size>100000
print('NSDF carrier: static mesh, normals, native bounds/budgets, atlases, fixture and eight engines passed')
