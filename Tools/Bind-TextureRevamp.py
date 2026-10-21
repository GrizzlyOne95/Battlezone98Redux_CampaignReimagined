"""Bind the reviewed textures and existing imported interior surfaces.

Only interior render UVs, their tangent basis and material names change.
Native GEO/SDF, collision, transforms, skinning, indices, normals and vertex
positions stay byte-identical.
"""
from pathlib import Path
import io,json,re,hashlib,sys
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh as om,ogremesh_serializer as oms

ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'References/TextureRevamp'
MAPPING={
 'osp_bronze':'Floor','osp_dark':'Wall','osp_tech':'Trim',
 'lme_bronze':'Floor','lme_dark':'Wall','lme_edge':'Trim',
 **{prefix+suffix:kind for prefix in ('ovheph_','oth_') for suffix,kind in [('metal','Floor'),('dark','Wall'),('edge','Trim'),('screen','Screen')]},
}
SELECTORS={
 'abstor':{'NormalMap':'crvstor_n.dds'},
 **{key:{'DiffuseMap':'crvpkup_d.dds','NormalMap':'crvpkup_n.dds'} for key in ('apammo','aprepa','aprock')},
 'apwrck':{'DiffuseMap':'crvsalv_d.dds','NormalMap':'crvpkup_n.dds'},
 **{key:{'NormalMap':f'crv{stem}_n.dds'} for key,stem in [('obdata','obdata00'),('obcycl','obcycl00'),('oblemb','oblemb00'),('oblemd','oblemb00')]},
 **{key:{'NormalMap':'crvobpowr00_n.dds'} for key in ('obcurt','obhavc','obmits','obmagc','obrfld','obtags')},
 **{f'cr16{x}':{'NormalMap':f'cr16{x}_n.dds','SpecularMap':f'cr16{x}_s.dds','EmissiveMap':f'cr16{x}_e.dds'} for x in ('cmd','hng','pwr','tow')},
 'ubtart':{'DiffuseMap':'trld_d.dds','NormalMap':'flat_N.dds','SpecularMap':'black.dds','EmissiveMap':'black.dds'},
 'trld':{'DiffuseMap':'trld_d.dds','NormalMap':'flat_N.dds','SpecularMap':'black.dds','EmissiveMap':'black.dds'},
}

def bone_digest(rows):
    rows=[list(row) for row in rows]
    return dict(count=len(rows),sha256=hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest())

def invariant(mesh):
    """Fingerprint all mesh data except permitted UV/material changes."""
    out=[]
    for sub in mesh.submesh_list:
        vd=mesh.shared_vertex_data if sub.use_shared_vertices else sub.vertex_data
        buffers=[]
        for source,vb in vd.vertex_buffer_map.items():
            raw=bytearray(vb.buffer)
            for el in vd.vertex_declaration.vertex_element_list:
                interior=sub.material_name in MAPPING or sub.material_name.startswith('CRV/Interior')
                if el.source==source and (el.semantic==om.VES.TEXTURE_COORDINATES or
                        (interior and el.semantic in (om.VES.TANGENT,om.VES.BINORMAL))):
                    for i in range(vd.vertex_count):
                        start=i*vb.vertex_size+el.offset
                        raw[start:start+el.get_type_size()]=bytes(el.get_type_size())
            buffers.append([source,vb.vertex_size,hashlib.sha256(raw).hexdigest()])
        out.append(dict(vertices=vd.vertex_count,indices=hashlib.sha256(sub.get_index_buffer()).hexdigest(),buffers=buffers,
                        layout=[vars(e) for e in vd.vertex_declaration.vertex_element_list],
                        bones=bone_digest(sorted((b.vertex_index,b.bone_index,b.weight) for b in sub.bone_assignments()))))
    return dict(skeleton=mesh.skeleton_name,submeshes=out,
                sharedBones=bone_digest(sorted((b.vertex_index,b.bone_index,b.weight) for b in mesh.bone_assignments())))

def stream(vd,semantic,buffers):
    el=vd.vertex_declaration.find_by_semantic(semantic)
    if el is None:return None
    vb=vd.get_vertex_buffer(el.source)
    data=buffers.setdefault(el.source,bytearray(vb.buffer))
    return np.ndarray((vd.vertex_count,el.get_type_count()),dtype='<f4',buffer=data,offset=el.offset,strides=(vb.vertex_size,4))

def project_interior(vd,kind):
    """Meter-scale local planar UVs with a matching orthonormal tangent basis.

    Hard surface normals choose a stable projection plane. Existing vertices,
    normals and indices remain untouched; only UV/T/B render streams change.
    The display atlas keeps its original normalized layout and flat normal.
    """
    if kind=='Screen':return
    buffers={}
    xyz=stream(vd,om.VES.POSITION,buffers)
    normal=stream(vd,om.VES.NORMAL,buffers).copy()
    normal/=np.maximum(np.linalg.norm(normal,axis=1,keepdims=True),1e-8)
    uv=stream(vd,om.VES.TEXTURE_COORDINATES,buffers)
    tangent=stream(vd,om.VES.TANGENT,buffers)
    assert tangent is not None,'interior needs an existing tangent stream'
    axis=np.zeros_like(normal);axis[:,0]=1
    vertical=abs(normal[:,0])>.8;axis[vertical]=[0,0,1]
    t=axis-normal*np.sum(axis*normal,axis=1,keepdims=True)
    t/=np.maximum(np.linalg.norm(t,axis=1,keepdims=True),1e-8)
    b=np.cross(normal,t)
    metres=2.0 if kind=='Trim' else 4.0
    uv[:,0]=np.sum(xyz*t,axis=1)/metres
    uv[:,1]=np.sum(xyz*b,axis=1)/metres
    tangent[:,:3]=t
    if tangent.shape[1]==4:tangent[:,3]=1
    binormal=stream(vd,om.VES.BINORMAL,buffers)
    if binormal is not None:binormal[:,:3]=b
    for source,data in buffers.items():vd.get_vertex_buffer(source).set_buffer(data)

def bind():
    imports=json.loads((REF/'local-model-import.json').read_text())
    textures=json.loads((REF/'imported-textures.json').read_text())
    aliases={alias:entry['file'] for entry in textures for alias in entry['aliases']}
    for item in imports['files']:
        if not item['path'].endswith('.material'):continue
        path=ROOT/item['path'];text=path.read_text()
        text=text.replace('"BZBase.material"','"CR_BZBase.material"')
        text=re.sub(r': BZBaseCockpit\b',': CR_BZBaseCockpit',text)
        text=re.sub(r': BZBase\b',': CR_BZBase',text)
        for old,new in aliases.items():
            text=re.sub(r'(?<![\w.])'+re.escape(old)+r'(?![\w.])',new,text)
        path.write_text(text,newline='\n')
    for name,bindings in SELECTORS.items():
        path=ROOT/'Materials'/(name+'.material');text=path.read_text()
        for alias,resource in bindings.items():
            text,n=re.subn(r'(set_texture_alias\s+'+alias+r'\s+)\S+',lambda m:m[1]+resource,text)
            assert n==1,(name,alias,n)
        path.write_text(text,newline='\n')
    receipt=REF/'mesh-invariants.json'
    baseline=json.loads(receipt.read_text()) if receipt.exists() else {}
    for record in baseline.values():
        if isinstance(record['sharedBones'],list):record['sharedBones']=bone_digest(record['sharedBones'])
        for sub in record['submeshes']:
            if isinstance(sub['bones'],list):sub['bones']=bone_digest(sub['bones'])
    bound={}
    for model in imports['models']:
        name=model['stock'];path=ROOT/'Assets/Models'/(name+'.mesh')
        mesh=oms.MeshSerializer(io.BytesIO(path.read_bytes())).read()
        before=invariant(mesh)
        if name in baseline:assert before==baseline[name],f'Unexpected geometry edit in {name}'
        else:baseline[name]=before
        changes=0
        for sub in mesh.submesh_list:
            kind=MAPPING.get(sub.material_name)
            if sub.material_name.startswith('CRV/Interior'):kind=sub.material_name[len('CRV/Interior'):]
            if kind is None:continue
            assert not sub.use_shared_vertices,'unexpected shared interior UV layout'
            project_interior(sub.vertex_data,kind)
            sub.material_name='CRV/Interior'+kind;changes+=1
        after=invariant(mesh);assert after==before,f'Geometry/rig changed in {name}'
        if changes:
            stream=io.BytesIO();oms.MeshSerializer(stream).write(mesh)
            path.write_bytes(stream.getvalue())
            assert invariant(oms.MeshSerializer(io.BytesIO(path.read_bytes())).read())==before
        bound[name]=[s.material_name for s in mesh.submesh_list]
    receipt.write_text(json.dumps(baseline,indent=2)+'\n')
    (REF/'material-bindings.json').write_text(json.dumps(dict(models=bound,selectors=SELECTORS),indent=2)+'\n')
    # Exclude redundant imported copies from the runtime set, recoverably.
    unused=ROOT/'Local/TextureRevamp/duplicate-imports';unused.mkdir(parents=True,exist_ok=True)
    for old,new in aliases.items():
        path=ROOT/'Assets/Textures'/old
        if old!=new and path.exists():
            import shutil
            shutil.move(str(path),str(unused/old))
    print('Bound interior textures and selectors; model geometry/rig/collision unchanged.')

if __name__=='__main__':bind()
