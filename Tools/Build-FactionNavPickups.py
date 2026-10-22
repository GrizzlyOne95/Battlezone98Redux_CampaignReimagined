"""Independent faction beacons and pickup models with re-UV'd casing panels.

Stock VDF/skeletons stay byte-identical. The shared Ogre codec clones render
streams and repartitions existing triangles; it never creates collision or
changes geometry. ImageGen masters are offline inputs, never build-time calls.
"""
from pathlib import Path
import copy,hashlib,importlib.util,io,json,re,shutil,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh as om,ogremesh_serializer as oms
from bcdds import save_bc
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/TextureRevamp/nav-pickups';SRC=REF/'original'
FACTIONS={'ns':('NSDF','n'),'bd':('Black Dog','b'),'cc':('CCA','s'),'cr':('CRA','c')}
# The four quadrant accents remain independent of faction paint.
FAMILIES={'apcamr':('crnv',None),'apammo':('cram',(0,0)),'aprepa':('crhp',(1,0)),
          'apcann':('crwc',(0,1)),'aprock':('crwr',(0,1)),'apmort':('crwm',(1,1)),'apspec':('crws',(1,1))}
spec=importlib.util.spec_from_file_location('building_contract',ROOT/'Tools/Build-BuildingTexturePatches.py')
contract=importlib.util.module_from_spec(spec);spec.loader.exec_module(contract)

def read(path):return oms.MeshSerializer(io.BytesIO(path.read_bytes())).read()
def values(vd,semantic):
    el=vd.vertex_declaration.find_by_semantic(semantic);vb=vd.get_vertex_buffer(el.source)
    return np.ndarray((vd.vertex_count,el.get_type_count()),'<f4',buffer=vb.buffer,offset=el.offset,strides=(vb.vertex_size,4))

def geometry(mesh):
    record=contract.triangle_contract(mesh)
    record.pop('skeleton') # Resource is deliberately namespaced; rig bytes pinned separately.
    return record

def emblem_fits(uv,triangles,radius=.32):
    """Conservative circular emblem footprint must lie inside drawn triangles."""
    samples=[np.array([.5,.5])]
    for r in (.10,.22,radius):
        samples.extend(np.array([.5+np.cos(a)*r,.5+np.sin(a)*r]) for a in np.linspace(0,2*np.pi,48,endpoint=False))
    tri=uv[triangles]
    cross=lambda a,b:a[:,0]*b[:,1]-a[:,1]*b[:,0]
    for p in samples:
        signs=[cross(tri[:,(i+1)%3]-tri[:,i],p-tri[:,i]) for i in range(3)]
        inside=(np.minimum.reduce(signs)>=-1e-6)|(np.maximum.reduce(signs)<=1e-6)
        if not inside.any():return False
    return True

def panel_groups(sub,family):
    """Planar broad faces, not small fittings, warheads or underside triangles."""
    xyz=values(sub.vertex_data,om.VES.POSITION);indices=sub.index_array.reshape(-1,3)
    tri=xyz[indices];cross=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);length=np.linalg.norm(cross,axis=1)
    normal=cross/np.maximum(length[:,None],1e-12);area=length*.5
    supply=family in ('apammo','aprepa')
    mask=(area>area.max()*(.14 if supply else .18))
    if not supply:mask&=normal[:,1]>-.45
    if family=='apammo':mask&=tri[:,:,1].mean(1)<2.30 # Preserve the stock blue tip.
    if family=='aprepa':mask[[0,1,4,5]]=False # Keep the small top/bottom coupling caps.
    if family=='apspec':mask&=normal[:,1]>.2
    groups=[];tolerance=np.linalg.norm(xyz.max(0)-xyz.min(0))*.025
    for i in np.flatnonzero(mask):
        n=normal[i].astype(float);center=tri[i].mean(0)
        group=next((g for g in groups if np.dot(g['normal'],n)>.985 and abs(np.dot(g['normal'],center-g['center']))<tolerance),None)
        if group is None:
            group=dict(normal=n,center=center,triangles=[]);groups.append(group)
        group['triangles'].append(int(i))
    result=[]
    for group in groups:
        rows=group['triangles']
        if len(rows)<2 and family!='aprock' and not supply:continue
        n=group['normal'];n/=np.linalg.norm(n)
        up=np.array([0,1,0] if abs(n[1])<.9 else [0,0,-1],dtype=float)
        t=np.cross(up,n);t/=np.linalg.norm(t);b=np.cross(n,t)
        points=xyz[np.unique(indices[rows])]
        projected=np.column_stack((points@t,-points@b));lo=projected.min(0);hi=projected.max(0)
        if min(hi-lo)/max(hi-lo)<(.08 if supply else .36):continue
        result.append(dict(triangles=rows,t=t,b=b,lo=lo,hi=hi,normal=n,area=float(area[rows].sum())))
    assert result,'No broad, legible casing panels in '+family
    # One complete, broad panel gets an emblem. Fins/bevels are plain metal,
    # not a tiled collection of clipped stars. The rocket's broad triangles
    # are fins: leave them deliberately unmarked.
    candidates=[]
    for i,g in enumerate(result):
        span=g['hi']-g['lo'];fill=g['area']/np.prod(span)
        facing=g['normal'][1] if family=='apspec' else g['normal'][2]
        center=(g['hi']+g['lo'])*.5
        projected=(np.column_stack((xyz@g['t'],-xyz@g['b']))-center)/max(span)*.92+.5
        if len(g['triangles'])>=2 and fill>.4 and emblem_fits(projected,indices[g['triangles']]):
            candidates.append((float(facing>.5)*100+g['area'],i))
    winner=max(candidates)[1] if candidates and family!='aprock' else None
    for i,group in enumerate(result):group['badge']=i==winner
    return result

def reuv_body(mesh,family,material,quadrant):
    assert len(mesh.submesh_list)==1 and not mesh.shared_vertex_data
    assert not mesh.edge_lists,'precomputed shadow topology needs an upstream rebuild'
    source=mesh.submesh_list[0];vd=source.vertex_data;indices=source.index_array.reshape(-1,3)
    groups=panel_groups(source,family);claimed=np.zeros(len(indices),dtype=bool)
    # Compact duplicated corners allow independent face UVs in one extra batch,
    # without overwriting shared vertices on other planes or detail surfaces.
    body=om.SubMesh(mesh,1);body.material_name=material;body.operation_type=source.operation_type
    body.vertex_data=om.VertexData(0);body.vertex_data.vertex_declaration=copy.deepcopy(vd.vertex_declaration)
    buffers={i:bytearray() for i in vd.vertex_buffer_map};out_indices=[];plain_indices=[];new_uv=[];origins=[]
    whole_xyz=values(vd,om.VES.POSITION);whole_center=(whole_xyz.min(0)+whole_xyz.max(0))*.5;whole_span=max(whole_xyz.max(0)-whole_xyz.min(0))
    for group in groups:
        selected=group['triangles'];assert not claimed[selected].any();claimed[selected]=True
        ids=np.unique(indices[selected]);mapping={int(old):len(origins)+i for i,old in enumerate(ids)}
        points=values(vd,om.VES.POSITION)[ids]
        uv=np.column_stack((points@group['t'],-points@group['b']))
        center=(group['hi']+group['lo'])*.5;scale=max(group['hi']-group['lo'])
        uv=(uv-center)/scale*.92+.5
        if not group['badge'] and family not in ('apammo','aprepa'):
            # Object-scale plain metal has no frame, stripe or emblem to chop.
            # It no longer magnifies a tiny corner of the artwork.
            centered=points-whole_center
            uv=np.column_stack((centered@group['t'],-centered@group['b']))/whole_span*.64+.5
        # Each type is unpacked into its OWN DDS before mip generation. UVs
        # never reach another atlas cell, including at coarse mip levels.
        assert uv.min()>=0 and uv.max()<=1,'Unwrap would leave its isolated panel texture'
        new_uv.extend(uv.tolist());origins.extend(ids.tolist())
        for slot,vb in vd.vertex_buffer_map.items():
            for old in ids:
                start=int(old)*vb.vertex_size;buffers[slot].extend(vb.buffer[start:start+vb.vertex_size])
        destination=out_indices if group['badge'] else plain_indices
        destination.extend(mapping[int(old)] for old in indices[selected].reshape(-1))
    body.vertex_data.vertex_count=len(origins)
    for slot,raw in buffers.items():
        vb=vd.vertex_buffer_map[slot]
        body.vertex_data.create_vertex_buffer(bytes(raw),slot,vb.vertex_size)
    el=body.vertex_data.vertex_declaration.find_by_semantic(om.VES.TEXTURE_COORDINATES)
    vb=body.vertex_data.get_vertex_buffer(el.source);raw=bytearray(vb.buffer)
    uv=np.ndarray((len(origins),el.get_type_count()),'<f4',buffer=raw,offset=el.offset,strides=(vb.vertex_size,4))
    uv[:,:2]=new_uv;vb.set_buffer(raw)
    weights={}
    for bone in source.bone_assignments():weights.setdefault(bone.vertex_index,[]).append(bone)
    for new,old in enumerate(origins):
        for bone in weights.get(old,[]):body.create_bone_assignment(new,bone.bone_index,bone.weight)
    body.indices_32_bit=len(origins)>=65536;body.index_count=len(out_indices)
    body.set_index_buffer(np.asarray(out_indices,dtype='<u4' if body.indices_32_bit else '<u2').tobytes())
    plain=copy.copy(body);plain.material_name=material+'/plain';plain.index_count=len(plain_indices)
    plain.set_index_buffer(np.asarray(plain_indices,dtype='<u4' if plain.indices_32_bit else '<u2').tobytes())
    remainder=copy.copy(source);remainder.index_count=int((~claimed).sum())*3
    remainder.set_index_buffer(indices[~claimed].tobytes())
    mesh.submesh_list=[remainder]+([body] if body.index_count else [])+([plain] if plain.index_count else [])
    for i,sub in enumerate(mesh.submesh_list):sub.parent=mesh;sub.submesh_index=i
    mesh.name_table={i:sub.material_name for i,sub in enumerate(mesh.submesh_list)}
    return dict(triangles=int(claimed.sum()),totalTriangles=len(indices),faceGroups=len(groups),badgePanels=sum(g['badge'] for g in groups),quadrant=list(quadrant))

def build():
    files={};models={};odfs={}
    routes=json.loads((REF/'routes.json').read_text())
    def put(file,image):
        path=ROOT/'Assets/Textures'/file;save_bc(image,path)
        files[file]=dict(size=list(image.size),sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    for code,(faction,prefix) in FACTIONS.items():
        with Image.open(REF/'plain-finishes.png') as image:
            qx,qy={'ns':(0,0),'bd':(1,0),'cc':(0,1),'cr':(1,1)}[code];w,h=image.size
            cell=image.crop((round(qx*w/2),round(qy*h/2),round((qx+1)*w/2),round((qy+1)*h/2)))
            put(f'crpk{code}_plain.dds',cell.convert('RGB').resize((512,512),Image.Resampling.LANCZOS))
        with Image.open(REF/('nav_'+code+'_v2.png')) as image:nav=image.convert('RGB').resize((1024,1024),Image.Resampling.LANCZOS)
        put('crnv'+code+'_d.dds',nav)
        # Restrict emission to the two stock lower lamps. Painted emblems and
        # faction red markings must not glow. No diffuse-derived normal map.
        a=np.array(nav);x,y=np.meshgrid(np.linspace(0,1,1024),np.linspace(0,1,1024))
        mask=(((x-.084)**2/(.043**2)+(y-.915)**2/(.046**2)<1)|((x-.205)**2/(.043**2)+(y-.915)**2/(.046**2)<1))
        mask&=a.min(2)>70;e=np.zeros_like(a);e[mask]=a[mask]
        put('crnv'+code+'_e.dds',Image.fromarray(e))
        with Image.open(REF/('panels_'+code+'.png')) as image:
            atlas=image.convert('RGB');w,h=atlas.size
            for type_id,(qx,qy) in enumerate(((0,0),(1,0),(0,1),(1,1))):
                cell=atlas.crop((round(qx*w/2),round(qy*h/2),round((qx+1)*w/2),round((qy+1)*h/2)))
                put(f'crpk{code}{type_id}_d.dds',cell.resize((512,512),Image.Resampling.LANCZOS))
        # Dedicated supply art replaces plain-metal casings and oversized stock
        # stripe panels, without altering weapon art or its source snapshots.
        with Image.open(REF/('supply_'+code+'_v2.png')) as image:
            atlas=image.convert('RGB');w,h=atlas.size
            for type_id,qy in ((0,0),(1,1)):
                for qx,ending in ((0,'_d.dds'),(1,'_surf.dds')):
                    cell=atlas.crop((round(qx*w/2),round(qy*h/2),round((qx+1)*w/2),round((qy+1)*h/2)))
                    put(f'crpk{code}{type_id}'+ending,cell.resize((512,512),Image.Resampling.LANCZOS))
        materials=['import * from "CR_BZBase.material"','']
        for family,(stem,quad) in FAMILIES.items():
            name=stem+code;mesh=read(SRC/(family+'.mesh'));before=geometry(mesh)
            mesh.skeleton_name=name+'.skeleton'
            if family=='apcamr':
                for sub in mesh.submesh_list:sub.material_name=name
                coverage=dict(triangles=mesh.submesh_list[0].index_count//3,totalTriangles=mesh.submesh_list[0].index_count//3)
            else:coverage=reuv_body(mesh,family,name,quad)
            assert geometry(mesh)==before,'Geometry/skin changed: '+name
            stream=io.BytesIO();oms.MeshSerializer(stream).write(mesh)
            path=ROOT/'Assets/Models'/(name+'.mesh');path.write_bytes(stream.getvalue())
            assert geometry(read(path))==before,'Roundtrip geometry changed: '+name
            for ext in ('vdf','skeleton'):shutil.copyfile(SRC/(family+'.'+ext),ROOT/'Assets/Models'/(name+'.'+ext))
            models[name]=dict(source=family,coverage=coverage,geometry=before,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
            type_id=None if quad is None else quad[0]+quad[1]*2
            diffuse='crnv'+code+'_d.dds' if quad is None else f'crpk{code}{type_id}_d.dds'
            emission='crnv'+code+'_e.dds' if family=='apcamr' else 'black.dds'
            materials.extend([f'material {name} : CR_BZBase','{',f'    set_texture_alias DiffuseMap {diffuse}',
              '    set_texture_alias NormalMap flat_N.dds','    set_texture_alias SpecularMap crvcca_patch_s.dds',
              f'    set_texture_alias EmissiveMap {emission}','    set $diffuse "1 1 1"','    set $ambient "1 1 1"',
              '    set $specular ".25 .25 .25"','    set $shininess "48"','}',''])
            if quad is not None:
                finish=f'crpk{code}{type_id}_surf.dds' if family in ('apammo','aprepa') else f'crpk{code}_plain.dds'
                materials.extend([f'material {name}/plain : {name}','{',f'    set_texture_alias DiffuseMap {finish}','    set $diffuse "1 1 1"','    set $ambient "1 1 1"','}',''])
        (ROOT/'Materials'/('CR_pickups_'+code+'.material')).write_text('\n'.join(materials),newline='\n')
        # Retain source identity in the output name: e.g. sapmini != sspmini.
        # Soviet minigun/ammo values differ from NSDF and must not be conflated.
        sources={p.stem for p in SRC.glob('ap*.odf')}
        for route in routes:
            if route['faction']==code:sources.update(route['sources'])
        translated={}
        for stem in sorted(sources):
            source=SRC/(stem+'.odf')
            text=source.read_text();match=re.search(r'baseName\s*=\s*"([^"]+)"',text)
            assert match and match[1] in FAMILIES,(source.name,match)
            destination=prefix+source.stem
            if len(destination)>8:destination=prefix+source.stem[:4]+hashlib.sha256(source.name.encode()).hexdigest()[:3]
            assert destination not in odfs,'ODF namespace collision: '+destination
            new_model=FAMILIES[match[1]][0]+code
            output=re.sub(r'(baseName\s*=\s*)"[^"]+"',lambda m:m[1]+'"'+new_model+'"',text,count=1)
            # Keep weapon-name/null UI resolution and all gameplay values intact.
            (ROOT/'ODF'/(destination+'.odf')).write_text(output.rstrip()+'\n',newline='\n')
            odfs[destination]=dict(source=source.name,model=new_model,faction=faction)
            translated[source.stem]=destination
        for route in routes:
            if route['faction']!=code:continue
            path=ROOT/route['path'];baseline=REF/'menus'/path.name
            text=baseline.read_text();current=path.read_text()
            def substitute(match):
                old=match[2]
                return match[1]+translated.get(old,old)+match[3]
            pattern=r'(?mi)^((?:buildItem|cannonItem|rocketItem|mortarItem|specialItem)\d+\s*=\s*")([^"]+)(")'
            output=re.sub(pattern,substitute,text)
            assert current in (text,output),'Unrelated menu edit: '+str(path)
            path.write_text(output,newline='\n')
    receipt=dict(schema=1,files=files,models=models,odfs=odfs,menuRoutes=len(routes),masters={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in REF.glob('*.png')})
    (REF/'build.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(f'Built {len(models)} faction models, {len(odfs)} independent ODFs and {len(files)} mipped DDS maps; native geometry/rig bytes retained.')

if __name__=='__main__':build()
