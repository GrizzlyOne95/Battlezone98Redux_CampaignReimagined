"""Native-loader contracts for the three CCA capital ships (no stock duplicates)."""
import hashlib
import io
import json
import math
from pathlib import Path
import struct
import sys

ROOT=Path(__file__).resolve().parents[1]
ASSETS=('crccarr','crcred1','crcred2')


sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import bwd2_serializer,geo_serializer,ogremesh_serializer


for asset in ASSETS:
    source=ROOT/'References/CCAFleet'/asset
    info=json.loads((source/'build.json').read_text())
    assert info['asset']==asset and info['scale_metres_per_pixel']==.25
    assert info['quality_pass'].startswith('Redux CCA')
    # Art quality and integrated surface treatment require visual review, not an
    # arbitrary number of greebles. Structural checks below cover the exports.
    assert info['normal_mapping'].startswith('DirectX (-Y)')
    assert 'all five bottom-right' in info['excluded']
    for path,digest in info['sha256'].items():
        assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,path+' stale build'
    mesh=ogremesh_serializer.MeshSerializer(io.BytesIO((ROOT/'Assets/ModelFixes'/(asset+'.mesh')).read_bytes())).read()
    assert mesh.skeleton_name is None
    bounds=(mesh.aabb.min_x,mesh.aabb.min_y,mesh.aabb.min_z,mesh.aabb.max_x,mesh.aabb.max_y,mesh.aabb.max_z,mesh.bound_radius)
    subs=0
    for sub in mesh.submesh_list:
        subs+=1;assert sub.material_name==asset+'00'
        count=sub.index_count
        assert not sub.use_shared_vertices and count%3==0
        indices=sub.get_index_array().tolist()
        nv=sub.vertex_data.vertex_count
        buffer=sub.vertex_data.get_vertex_buffer(0)
        assert buffer.bind_index==0 and buffer.vertex_size==44,'explicit PNUV+tangent buffer'
        vertices=list(struct.iter_unpack('<11f',bytes(buffer.buffer)))
        assert len(vertices)==nv and max(indices)<nv
        assert count//3==info['triangles'] and 0<count//3<75000 and nv<160000
        assert all(math.isfinite(x) for v in vertices for x in v)
        assert all(abs(sum(x*x for x in v[3:6])-1)<.006 for v in vertices)
        assert all(abs(sum(x*x for x in v[8:11])-1)<.006 for v in vertices),'unit tangents'
        assert all(abs(sum(v[3+i]*v[8+i] for i in range(3)))<.006 for v in vertices),'orthogonal tangent basis'
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
    assert 0<=bounds[5]-bounds[2]-expected<4,'reference length plus inferred engine extension'
    geo=geo_serializer.GeoSerializer(io.BytesIO((ROOT/'Assets/ModelFixes'/(asset+'.geo')).read_bytes())).read()
    assert geo.name==asset
    assert 0<geo.vert_count<4096 and 0<len(geo.face_list)<4096
    sdf=bwd2_serializer.SDFSerializer(io.BytesIO((ROOT/'Assets/ModelFixes'/(asset+'.sdf')).read_bytes())).read()
    obj=sdf.get_object(0,0,0)
    assert obj.name==asset and obj.parent=='WORLD'
    center=(obj.center_pos.x,obj.center_pos.y,obj.center_pos.z);half=(obj.half_size.x,obj.half_size.y,obj.half_size.z)
    for i in range(3):
        assert abs(center[i]-half[i]-bounds[i])<.01
        assert abs(center[i]+half[i]-bounds[3+i])<.01
    for suffix,size in info['atlas_sizes'].items():
        d=(ROOT/'Assets/Textures'/(asset+'_'+suffix+'.dds')).read_bytes()
        assert d[:4]==b'DDS ' and struct.unpack_from('<II',d,12)==(size,size)
        assert struct.unpack_from('<I',d,80)[0]==0x41 and struct.unpack_from('<I',d,88)[0]==32
        if suffix=='n':
            assert size==2048,'real bevel/paint tangent-normal atlas'
            samples={struct.unpack_from('<I',d,128+4*i)[0] for i in range(0,size*size,size*size//8192)}
            assert len(samples)>32,'normal map must contain surface detail, not a flat placeholder'
    mat=(ROOT/'Materials'/(asset+'.material')).read_text()
    for suffix in 'dens':assert asset+'_'+suffix+'.dds' in mat
    odf=(ROOT/'ODF'/(asset+'.odf')).read_text()
    assert 'classLabel = "i76building"' in odf and 'maxHealth = 0' in odf
    assert len(info['engine_exits']) in (2,4)
    assert (source/(asset+'.blend')).stat().st_size>100000
    print(asset,': mesh/material, authored scale, normals, native budgets/bounds, atlases and build hashes passed')
assert len(list((ROOT/'References/CCAFleet').glob('*/geometry.json')))==3,'stock comparisons must not become new fleet assets'
