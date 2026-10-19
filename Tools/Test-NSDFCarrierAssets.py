"""Native-loader invariants for the standalone cinematic NSDF carrier."""
import io
import json
import math
from pathlib import Path
import struct
import sys

ROOT=Path(__file__).resolve().parents[1]

sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import bwd2_serializer,geo_serializer,ogremesh_serializer

mesh=ogremesh_serializer.MeshSerializer(io.BytesIO((ROOT/'Assets/ModelFixes/crncarr.mesh').read_bytes())).read()
assert mesh.skeleton_name is None
bounds=(mesh.aabb.min_x,mesh.aabb.min_y,mesh.aabb.min_z,mesh.aabb.max_x,mesh.aabb.max_y,mesh.aabb.max_z,mesh.bound_radius)
submeshes=0
for sub in mesh.submesh_list:
    submeshes+=1
    assert sub.material_name=='crncarr00'
    count=sub.index_count
    assert not sub.use_shared_vertices and count%3==0
    indices=sub.get_index_array().tolist()
    nv=sub.vertex_data.vertex_count
    buffer=sub.vertex_data.get_vertex_buffer(0)
    assert buffer.bind_index==0 and buffer.vertex_size==32
    vertices=list(struct.iter_unpack('<8f',bytes(buffer.buffer)))
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

geo=geo_serializer.GeoSerializer(io.BytesIO((ROOT/'Assets/ModelFixes/crncarr.geo').read_bytes())).read()
assert geo.name=='crncarr'
assert 0<geo.vert_count<4096 and 0<len(geo.face_list)<4096,'native geometry table limits'
sdf=bwd2_serializer.SDFSerializer(io.BytesIO((ROOT/'Assets/ModelFixes/crncarr.sdf').read_bytes())).read()
obj=sdf.get_object(0,0,0)
assert obj.name=='crncarr' and obj.parent=='WORLD'
center=(obj.center_pos.x,obj.center_pos.y,obj.center_pos.z);half=(obj.half_size.x,obj.half_size.y,obj.half_size.z)
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
