"""Validate the rebuilt rocket's binary geometry, atlas, native bounds and jets."""
from pathlib import Path
import io
import json
import math
import re
import struct
import sys

ROOT=Path(__file__).resolve().parents[1]
atlas=(ROOT/'Assets/Textures/cr06rok_d.dds').read_bytes()
atlas_height,atlas_width=struct.unpack_from('<II',atlas,12)

def atlas_rgb(px,py):
    # Decode one mip-0 texel of the BC1 atlas.
    offset=128+8*((py>>2)*(atlas_width>>2)+(px>>2))
    c0,c1,bits=struct.unpack_from('<HHI',atlas,offset)
    def rgb(c):return ((c>>11)*255//31,((c>>5)&63)*255//63,(c&31)*255//31)
    a,b=rgb(c0),rgb(c1)
    palette=[a,b,tuple((2*x+y)//3 for x,y in zip(a,b)),tuple((x+2*y)//3 for x,y in zip(a,b))] if c0>c1 else [a,b,tuple((x+y)//2 for x,y in zip(a,b)),(0,0,0)]
    return palette[(bits>>(2*(4*(py&3)+(px&3))))&3]


sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import bwd2_serializer,geo_serializer,ogremesh_serializer
from bcdds import bc_dds_problem

mesh=ogremesh_serializer.MeshSerializer(io.BytesIO((ROOT/'Assets/ModelFixes/cr06rok.mesh').read_bytes())).read()
assert mesh.skeleton_name is None,'static Ogre mesh'
bounds=(mesh.aabb.min_x,mesh.aabb.min_y,mesh.aabb.min_z,mesh.aabb.max_x,mesh.aabb.max_y,mesh.aabb.max_z,mesh.bound_radius)
submeshes=[]
for sub in mesh.submesh_list:
    assert sub.material_name=='cr06rok00'
    count=sub.index_count
    assert not sub.use_shared_vertices and count%3==0
    indices=sub.get_index_array().tolist()
    nv=sub.vertex_data.vertex_count
    buffer=sub.vertex_data.get_vertex_buffer(0)
    assert buffer.bind_index==0 and buffer.vertex_size==32
    assert buffer.buffer.nbytes==nv*buffer.vertex_size
    vertices=list(struct.iter_unpack('<8f',bytes(buffer.buffer)))
    assert max(indices)<len(vertices)
    assert all(math.isfinite(x) for v in vertices for x in v)
    assert all(abs(sum(x*x for x in v[3:6])-1)<.005 for v in vertices),'unit normals'
    aligned=degenerate=red_paint=0
    for i in range(0,count,3):
        a,b,c=[vertices[indices[i+j]] for j in range(3)]
        u=[b[j]-a[j] for j in range(3)];v=[c[j]-a[j] for j in range(3)]
        n=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
        if sum(x*x for x in n)<1e-12:degenerate+=1;continue
        mean=[a[3+j]+b[3+j]+c[3+j] for j in range(3)]
        aligned+=sum(x*y for x,y in zip(n,mean))>0
        uv=[sum(v[j] for v in (a,b,c))/3 for j in (6,7)]
        px=min(atlas_width-1,max(0,int(uv[0]*atlas_width)))
        py=min(atlas_height-1,max(0,int(uv[1]*atlas_height)))
        red,green,blue=atlas_rgb(px,py)
        if red>60 and red>2*green and red>2*blue:
            red_paint+=1
            center=[sum(v[j] for v in (a,b,c))/3 for j in range(3)]
            assert center[0]*mean[0]+center[2]*mean[2]>-.1,'Paint cards must face outwards, not vanish under native culling'
    assert aligned>=.995*(count/3-degenerate),'normals must agree with triangle winding'
    assert degenerate<count/300,'few degenerate triangles'
    assert red_paint>30,'visible red paint is present'
    submeshes.append(count//3)
assert len(submeshes)==1 and 10000<sum(submeshes)<25000,'bounded authored mesh budget'
assert abs(bounds[1]+48.5)<.001 and abs(bounds[4]-48.5)<.001,'stable nozzle plane and height'
assert bounds[0]>=-15.2 and bounds[3]<=15.2 and bounds[5]<15.2,'fits the stock raised launch deck'

geo=geo_serializer.GeoSerializer(io.BytesIO((ROOT/'Assets/ModelFixes/cr06rok.geo').read_bytes())).read()
assert geo.name=='cr06rok'
assert geo.vert_count<4096 and len(geo.face_list)<4096,'light native geometry'
sdf=bwd2_serializer.SDFSerializer(io.BytesIO((ROOT/'Assets/ModelFixes/cr06rok.sdf').read_bytes())).read()
obj=sdf.get_object(0,0,0)
assert obj.name=='cr06rok' and obj.parent=='WORLD'
half=(obj.half_size.x,obj.half_size.y,obj.half_size.z)
assert half[1]>=48.5 and half[0]>=15.0 and half[2]>=15.0,'updated native bounds'

for suffix,size in [('d',2048),('e',1024),('s',512),('n',16)]:
    dds=(ROOT/'Assets/Textures'/('cr06rok_'+suffix+'.dds')).read_bytes()
    if suffix=='n':  # flat 16x16 normal stays RGBA8
        assert dds[:4]==b'DDS ' and struct.unpack_from('<II',dds,12)==(size,size)
        assert struct.unpack_from('<I',dds,80)[0]==0x41 and struct.unpack_from('<I',dds,88)[0]==32,'RGBA8 texture'
    else:
        assert not bc_dds_problem(dds,size),bc_dds_problem(dds,size)

layout=(ROOT/'Scripts/CR06RocketLayout.lua').read_text()
jets=[tuple(map(float,m)) for m in re.findall(r'\{(-?[\d.]+),\s*(-?[\d.]+)\}',layout)]
assert len(jets)==8 and len(set(jets))==8
radius=7*97/77.58216095
assert all(abs(x*x+z*z-radius*radius)<.00001 for x,z in jets),'scaled TC eight-bell arrangement'
template=(ROOT/'Materials/cr06_launch.particle.payload').read_text()
core,plume,smoke,dust=template.split('particle_system CR/M06/')[1:]
assert core.startswith('Core') and core.count('emitter Point')==8
assert plume.startswith('Plume') and plume.count('emitter Point')==8
assert sum(map(int,re.findall(r'\bquota\s+(\d+)',template)))==1006,'shared bounded particle quotas'
print('Misn06 rebuilt rocket: geometry, normals, native bounds, BC1 mipped atlases and eight nozzle anchors passed')
