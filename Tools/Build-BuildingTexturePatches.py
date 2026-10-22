"""Give selected close-up building surfaces dedicated texture space.

Repartition existing triangles without changing positions, winding, weights or
native GEO/SDF/skeleton files. UV crops are positive affine transforms, leaving
the original tangent directions intact. Uses the shared Ogre codec, never a
private format parser. These CCA/Black Dog pad pilots are pending native review.
"""
from pathlib import Path
import copy,hashlib,io,json,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh as om,ogremesh_serializer as oms
from bcdds import save_bc

ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'References/TextureRevamp'

def read_mesh(path):
    return oms.MeshSerializer(io.BytesIO(path.read_bytes())).read()

def values(vd,semantic):
    el=vd.vertex_declaration.find_by_semantic(semantic)
    vb=vd.get_vertex_buffer(el.source)
    return np.ndarray((vd.vertex_count,el.get_type_count()),'<f4',buffer=vb.buffer,offset=el.offset,strides=(vb.vertex_size,4))

def triangle_contract(mesh,include_uv=False,source_only=None):
    """Order-independent oriented triangle/corner attributes, including skinning.

    Repartitioning can duplicate buffers but must preserve every drawn triangle
    exactly once. UVs are optionally included for the untouched stock remainder.
    """
    triangles=[]
    for sub in mesh.submesh_list:
        if source_only and sub.material_name!=source_only:continue
        vd=mesh.shared_vertex_data if sub.use_shared_vertices else sub.vertex_data
        corners=[]
        bones={}
        for bone in list(mesh.bone_assignments())+list(sub.bone_assignments()):
            bones.setdefault(bone.vertex_index,[]).append([bone.bone_index,bone.weight])
        for i in range(vd.vertex_count):
            blob=bytearray()
            for el in vd.vertex_declaration.vertex_element_list:
                if not include_uv and el.semantic==om.VES.TEXTURE_COORDINATES:continue
                vb=vd.get_vertex_buffer(el.source);start=i*vb.vertex_size+el.offset
                blob.extend(vb.buffer[start:start+el.get_type_size()])
            blob.extend(json.dumps(sorted(bones.get(i,[])),separators=(',',':')).encode())
            corners.append(hashlib.sha256(blob).hexdigest())
        for indices in sub.index_array.reshape(-1,3):
            # Keep winding and original corner order; only triangle order changes.
            triangles.append(tuple(corners[int(i)] for i in indices))
    return dict(skeleton=mesh.skeleton_name,bounds=vars(mesh.aabb),
                radius=mesh.bound_radius,count=len(triangles),sha256=hashlib.sha256(json.dumps(sorted(triangles),separators=(',',':')).encode()).hexdigest())

def patch_mask(uv,indices,box,atlas):
    coords=uv[indices]*np.array(atlas)
    return np.all((coords>=np.array(box[:2])-.25)&(coords<=np.array(box[2:])+.25),axis=(1,2))

def build_one(recipe_file):
    recipe=json.loads((REF/recipe_file).read_text())
    name=recipe['model'];source=REF/'building-sources'/(name+'.mesh')
    mesh=read_mesh(source)
    assert len(mesh.submesh_list)==1 and not mesh.submesh_list[0].use_shared_vertices
    sub=mesh.submesh_list[0];assert sub.material_name==recipe['sourceMaterial']
    before=triangle_contract(mesh)
    original_uv=values(sub.vertex_data,om.VES.TEXTURE_COORDINATES).copy()
    indices=sub.index_array.reshape(-1,3).copy();claimed=np.zeros(len(indices),dtype=bool)
    parts=[];files={};coverage={}
    def put(file,image):
        path=ROOT/'Assets/Textures'/file;save_bc(image,path)
        files[file]=dict(size=list(image.size),format='BC1_UNORM',sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    material=[f'import * from "{recipe["sourceMaterial"]}.material"','']
    for patch in recipe['patches']:
        key=patch['id'];box=patch['bounds'];size=tuple(patch['size'])
        selected=patch_mask(original_uv,indices,box,recipe['atlasSize'])
        assert not np.any(claimed&selected),'overlapping patch selections'
        assert int(selected.sum())==patch['expectedTriangles'],(key,int(selected.sum()))
        claimed|=selected
        part=copy.copy(sub);part.vertex_data=read_mesh(source).submesh_list[0].vertex_data
        part.material_name='CRV/Building/'+key;part.texture_alias_map={}
        part.index_count=int(selected.sum())*3;part.set_index_buffer(indices[selected].tobytes())
        el=part.vertex_data.vertex_declaration.get_texcoord_vertex_element();vb=part.vertex_data.get_vertex_buffer(el.source)
        data=bytearray(vb.buffer)
        uv=np.ndarray((part.vertex_data.vertex_count,2),'<f4',buffer=data,offset=el.offset,strides=(vb.vertex_size,4))
        uv[:]=(original_uv*np.array(recipe['atlasSize'])-np.array(box[:2]))/np.array([box[2]-box[0],box[3]-box[1]])
        vb.set_buffer(data);parts.append(part)
        coverage[key]=int(selected.sum())
        with Image.open(REF/(key+'.png')) as im:image=im.convert('RGB').resize(size,Image.Resampling.LANCZOS)
        stem='crv'+key
        put(stem+'_d.dds',image)
        # Matched lamp extraction, never diffuse-as-height. Only the authored
        # four green central lamps and two red upper bars can emit.
        emission=np.zeros((size[1],size[0],3),dtype=np.uint8)
        if key=='cca_door':
            a=np.array(image);r,g,b=[a[:,:,i].astype(float) for i in range(3)]
            x,y=np.meshgrid(np.linspace(0,1,size[0]),np.linspace(0,1,size[1]))
            green=(g>100)&(g>r*1.8)&(g>b*1.8)&(abs(x-.5)<.04)
            red=(r>85)&(r>g*2.2)&(r>b*2.2)&(y>.14)&(y<.20)&(((x>.25)&(x<.40))|((x>.60)&(x<.75)))
            emission[green|red]=a[green|red]
            put(stem+'_e.dds',Image.fromarray(emission))
        emissive=stem+'_e.dds' if key=='cca_door' else 'black.dds'
        material.extend([f'material {part.material_name} : {recipe["sourceMaterial"]}','{',
          f'    set_texture_alias DiffuseMap {stem}_d.dds','    set_texture_alias NormalMap flat_N.dds',
          '    set_texture_alias SpecularMap crvcca_patch_s.dds',f'    set_texture_alias EmissiveMap {emissive}','}',''])
    put('crvcca_patch_s.dds',Image.new('RGB',(4,4),(30,30,30)))
    remainder=copy.copy(sub);remainder.index_count=int((~claimed).sum())*3;remainder.set_index_buffer(indices[~claimed].tobytes())
    mesh.submesh_list=[remainder]+parts
    for i,part in enumerate(mesh.submesh_list):part.parent=mesh;part.submesh_index=i
    # Keep the original remainder's name; assign unique names to new batches.
    assert all(i==0 for i in mesh.name_table),'unexpected source submesh names'
    for i,patch in enumerate(recipe['patches'],1):mesh.name_table[i]=patch['id']
    # Stock CCA pad has no precomputed edge list. Fail instead of retaining a
    # stale list or silently dropping shadow topology on a different source.
    assert not mesh.edge_lists,'source edge topology needs upstream rebuild support'
    assert triangle_contract(mesh)==before,'render geometry or rig changed'
    path=ROOT/'Assets/Models'/(name+'.mesh');stream=io.BytesIO();oms.MeshSerializer(stream).write(mesh);path.write_bytes(stream.getvalue())
    assert triangle_contract(read_mesh(path))==before,'roundtrip geometry changed'
    (ROOT/'Materials'/recipe.get('materialFile','CR_building_patches.material')).write_text('\n'.join(material),newline='\n')
    receipt=dict(schema=1,sourceSha256=hashlib.sha256(source.read_bytes()).hexdigest(),modelSha256=hashlib.sha256(path.read_bytes()).hexdigest(),geometry=before,coverage=coverage,files=files)
    (REF/recipe.get('receipt','building-build.json')).write_text(json.dumps(receipt,indent=2)+'\n')
    print(name+': dedicated texture space for',coverage,'with exact triangle/rig preservation')

def build():
    for recipe in ('building-patches.json','bdog-pad-patch.json'):build_one(recipe)

if __name__=='__main__':build()
