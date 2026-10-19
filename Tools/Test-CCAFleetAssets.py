"""Native-loader contracts for the three CCA capital ships (no stock duplicates)."""
import hashlib
import json
import math
from pathlib import Path
import struct

ROOT=Path(__file__).resolve().parents[1]
ASSETS=('crccarr','crcred1','crcred2')


def chunks(data,start,end):
    while start<end:
        cid,size=struct.unpack_from('<HI',data,start)
        assert size>=6 and start+size<=end,'truncated Ogre chunk'
        yield cid,start+6,start+size
        start+=size
    assert start==end


for asset in ASSETS:
    source=ROOT/'References/CCAFleet'/asset
    info=json.loads((source/'build.json').read_text())
    assert info['asset']==asset and info['scale_metres_per_pixel']==.25
    assert 'all five bottom-right' in info['excluded']
    for path,digest in info['sha256'].items():
        assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,path+' stale build'
    data=(ROOT/'Assets/ModelFixes'/(asset+'.mesh')).read_bytes()
    head=data.index(b'\n')+1;assert data[2:head]==b'[MeshSerializer_v1.100]\n'
    cid,start,end=next(chunks(data,head,len(data)));assert cid==0x3000 and data[start]==0
    subs=0
    for cid,ss,se in chunks(data,start+1,end):
        if cid==0x9000:bounds=struct.unpack_from('<7f',data,ss)
        if cid!=0x4000:continue
        subs+=1;ne=data.index(b'\n',ss);assert data[ss:ne]==(asset+'00').encode()
        shared,count,wide=struct.unpack_from('<?I?',data,ne+1)
        assert not shared and count%3==0
        p=ne+7;indices=struct.unpack_from('<%d%s'%(count,'I' if wide else 'H'),data,p)
        for ck,gs,ge in chunks(data,p+count*(4 if wide else 2),se):
            if ck!=0x5000:continue
            nv=struct.unpack_from('<I',data,gs)[0]
            for vk,vs,ve in chunks(data,gs+4,ge):
                if vk!=0x5200:continue
                binding,stride=struct.unpack_from('<HH',data,vs);assert binding==0 and stride==32
                _,bs,be=next(chunks(data,vs+4,ve));vertices=list(struct.iter_unpack('<8f',data[bs:be]))
        assert len(vertices)==nv and max(indices)<nv
        assert count//3==info['triangles'] and count//3<10000 and nv<65536
        assert all(math.isfinite(x) for v in vertices for x in v)
        assert all(abs(sum(x*x for x in v[3:6])-1)<.006 for v in vertices)
        for i in range(0,count,3):
            a,b,c=[vertices[indices[i+j]] for j in range(3)]
            u=[b[j]-a[j] for j in range(3)];v=[c[j]-a[j] for j in range(3)]
            n=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
            if sum(x*x for x in n)<1e-10:continue
            assert sum(n[j]*(a[3+j]+b[3+j]+c[3+j]) for j in range(3))>0,'backface winding'
    assert subs==1
    for i in range(3):
        assert abs(bounds[i]-info['bounds_min'][i])<.001
        assert abs(bounds[3+i]-info['bounds_max'][i])<.001
    expected=(info['source_span'][1]-info['source_span'][0])*.25
    assert abs(bounds[5]-bounds[2]-expected)<1,'reference length at APC-informed scale'
    geo=(ROOT/'Assets/ModelFixes'/(asset+'.geo')).read_bytes()
    magic,_,name,nv,nf,_=struct.unpack_from('<4si16siii',geo)
    assert magic==b'OEG.' and name.rstrip(b'\0')==asset.encode()
    assert 0<nv<4096 and 0<nf<4096
    sdf=(ROOT/'Assets/ModelFixes'/(asset+'.sdf')).read_bytes()
    rec=struct.unpack_from('<8s12f8s7fiii4f',sdf,sdf.index(b'SGEO')+12)
    assert rec[0].rstrip(b'\0')==asset.encode() and rec[13].rstrip(b'\0')==b'WORLD'
    for i in range(3):
        assert abs(rec[14+i]-rec[18+i]-bounds[i])<.01
        assert abs(rec[14+i]+rec[18+i]-bounds[3+i])<.01
    for suffix,size in info['atlas_sizes'].items():
        d=(ROOT/'Assets/Textures'/(asset+'_'+suffix+'.dds')).read_bytes()
        assert d[:4]==b'DDS ' and struct.unpack_from('<II',d,12)==(size,size)
        assert struct.unpack_from('<I',d,80)[0]==0x41 and struct.unpack_from('<I',d,88)[0]==32
        if suffix=='n':assert d[128:132]==bytes((255,128,128,255))
    mat=(ROOT/'Materials'/(asset+'.material')).read_text()
    for suffix in 'dens':assert asset+'_'+suffix+'.dds' in mat
    odf=(ROOT/'ODF'/(asset+'.odf')).read_text()
    assert 'classLabel = "i76building"' in odf and 'maxHealth = 0' in odf
    assert len(info['engine_exits']) in (2,4)
    assert (source/(asset+'.blend')).stat().st_size>100000
    print(asset,': mesh/material, authored scale, normals, native budgets/bounds, atlases and build hashes passed')
assert len(list((ROOT/'References/CCAFleet').glob('*/geometry.json')))==3,'stock comparisons must not become new fleet assets'
