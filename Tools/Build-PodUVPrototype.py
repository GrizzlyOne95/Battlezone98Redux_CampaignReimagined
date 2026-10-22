"""Full, unique pod unwrap prototype; outputs stay outside shipping pending art review.

All source triangles get fresh UVs in one atlas/material. Continuous perimeter
bands replace per-facet panel stamping. Uses CR's shared native model codecs.
"""
from pathlib import Path
import argparse,copy,hashlib,importlib.util,io,json,sys
import numpy as np
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'Tools'))
spec=importlib.util.spec_from_file_location('pickups',ROOT/'Tools/Build-FactionNavPickups.py')
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
REF=ROOT/'References/TextureRevamp/pod-uv-v3'
SOURCES={'cramns3':'apammo','crhpns3':'aprepa'}

def key(xz):return tuple(np.round(xz,5))

def perimeter(xyz,triangles):
    """Unroll the actual concave cross-section by distance, not angle or tiles."""
    edges=set()
    for tri in triangles:
        points=sorted({key(xyz[i,[0,2]]) for i in tri})
        assert len(points)==2,('non-vertical side triangle',points)
        edges.add(tuple(points))
    graph={}
    for a,b in edges:graph.setdefault(a,[]).append(b);graph.setdefault(b,[]).append(a)
    assert all(len(v)==2 for v in graph.values()),('side section is not a cycle',{k:len(v) for k,v in graph.items()})
    start=min(graph,key=lambda q:(q[1],q[0]));order=[start];previous=None;current=start
    while True:
        choices=[q for q in graph[current] if q!=previous]
        following=choices[0] if previous is not None else max(choices,key=lambda q:q[0])
        if following==start:break
        assert following not in order,'cross-section loops before covering every edge'
        order.append(following);previous,current=current,following
    assert len(order)==len(graph),'multiple disconnected side profiles'
    lengths=[float(np.linalg.norm(np.array(order[(i+1)%len(order)])-a)) for i,a in enumerate(order)]
    total=sum(lengths);distance=np.r_[0,np.cumsum(lengths)]/total
    lookup=dict(zip(order,distance[:-1]))
    front=max(range(len(order)),key=lambda i:(order[i][1]+order[(i+1)%len(order)][1])*.5)
    front_u=(distance[front]+distance[front+1])*.5
    return lookup,total,float(front_u)

def full_uv(source,family):
    vd=source.vertex_data;xyz=p.values(vd,p.om.VES.POSITION);triangles=source.index_array.reshape(-1,3)
    tri=xyz[triangles];n=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);n/=np.linalg.norm(n,axis=1)[:,None]
    middle=tri.mean(1)
    if family=='apammo':
        labels=np.full(len(triangles),'side',dtype=object)
        labels[n[:,1]<-.2]='bottom'
        labels[(n[:,1]>.65)&(middle[:,1]<1.8)]='shoulder'
        labels[middle[:,1]>1.75]='cone'
        labels[n[:,1]>.95]='cap'
        boxes={'side':(.04,.04,.96,.30),'cone':(.06,.32,.94,.55),
               'shoulder':(.56,.59,.96,.99),'bottom':(.04,.59,.44,.99),'cap':(.48,.59,.52,.63)}
    else:
        labels=np.where(n[:,1]>.2,'top',np.where(n[:,1]<-.2,'bottom','side'))
        boxes={'top':(.03,.03,.68,.68),'bottom':(.72,.03,.97,.28),'side':(.03,.77,.97,.94)}
    side=triangles[labels=='side'];lookup,length,front=perimeter(xyz,side)
    # Equal U/V density on the vertical wrap: physical height / perimeter.
    a,b,c,_=boxes['side'];height=float(np.ptp(xyz[side][:,:,1]))
    boxes['side']=(a,b,c,b+(c-a)*height/length)
    uv=np.empty((len(triangles),3,2),float)
    metadata={'perimeter':length,'frontBandU':front,'charts':{}}
    for label,box in boxes.items():
        rows=np.flatnonzero(labels==label);points=tri[rows];low=points.min((0,1));high=points.max((0,1))
        if label=='side':
            projected=np.array([[[lookup[key(v[[0,2]])],(high[1]-v[1])/(high[1]-low[1])] for v in row] for row in points])
            for row in projected:
                if np.ptp(row[:,0])>.5:row[row[:,0]<.5,0]+=1
        elif label=='cone':
            projected=np.stack((np.arctan2(points[:,:,0],points[:,:,2])/(2*np.pi)+.5,
                                (high[1]-points[:,:,1])/(high[1]-low[1])),axis=-1)
            for row in projected:
                if np.ptp(row[:,0])>.5:row[row[:,0]<.5,0]+=1
            projected[:,:,0]=(projected[:,:,0]-projected[:,:,0].min())/np.ptp(projected[:,:,0])
        else:
            projected=np.stack(((points[:,:,0]-low[0])/(high[0]-low[0]),
                                (high[2]-points[:,:,2])/(high[2]-low[2])),axis=-1)
        uv[rows]=projected*np.subtract(box[2:],box[:2])+box[:2]
        metadata['charts'][label]={'box':list(box),'triangles':rows.tolist()}
    assert np.isfinite(uv).all() and uv.min()>.005 and uv.max()<.995,[(label,uv[labels==label].min((0,1)).tolist(),uv[labels==label].max((0,1)).tolist()) for label in boxes]
    return uv,metadata

def remesh(mesh,uv,name):
    original=mesh.submesh_list[0];vd=original.vertex_data;ids=original.index_array
    out=copy.copy(original);out.material_name=name;out.vertex_data=p.om.VertexData(len(ids))
    out.vertex_data.vertex_declaration=copy.deepcopy(vd.vertex_declaration)
    for slot,vb in vd.vertex_buffer_map.items():
        raw=b''.join(vb.buffer[int(i)*vb.vertex_size:(int(i)+1)*vb.vertex_size] for i in ids)
        out.vertex_data.create_vertex_buffer(raw,slot,vb.vertex_size)
    el=out.vertex_data.vertex_declaration.find_by_semantic(p.om.VES.TEXTURE_COORDINATES)
    vb=out.vertex_data.get_vertex_buffer(el.source);raw=bytearray(vb.buffer)
    mapped=np.ndarray((len(ids),el.get_type_count()),'<f4',buffer=raw,offset=el.offset,strides=(vb.vertex_size,4))
    mapped[:,:2]=uv.reshape(-1,2);vb.set_buffer(raw)
    # copy.copy shares the bone dictionary: replace it via the codec's fresh SubMesh.
    fresh=p.om.SubMesh(mesh,0)
    fresh.material_name=out.material_name;fresh.vertex_data=out.vertex_data;fresh.operation_type=original.operation_type
    weights={}
    for bone in original.bone_assignments():weights.setdefault(bone.vertex_index,[]).append(bone)
    for new,old in enumerate(ids):
        for bone in weights.get(int(old),[]):fresh.create_bone_assignment(new,bone.bone_index,bone.weight)
    fresh.indices_32_bit=False;fresh.index_count=len(ids);fresh.set_index_buffer(np.arange(len(ids),dtype='<u2').tobytes())
    mesh.submesh_list=[fresh];mesh.name_table={0:name}

def guide(name,uv,metadata):
    # Technical UV diagram only, never used as final artwork.
    size=1254;im=Image.new('RGB',(size,size),(35,38,43));draw=ImageDraw.Draw(im)
    colours=[(110,135,155),(170,155,120),(110,155,135),(145,120,150),(155,150,110)]
    for (label,record),colour in zip(metadata['charts'].items(),colours):
        for row in uv[record['triangles']]:draw.polygon([tuple(q*size) for q in row],fill=colour)
        for row in uv[record['triangles']]:draw.line([tuple(q*size) for q in np.r_[row,row[:1]]],fill=(190,200,205),width=1)
        a,b,c,d=record['box'];draw.text((a*size+4,b*size+4),label.upper(),fill='white')
    im.save(REF/(name+'-uv-guide.png'))

def build():
    parser=argparse.ArgumentParser();parser.add_argument('--textures',action='store_true');args=parser.parse_args()
    REF.mkdir(parents=True,exist_ok=True);receipt={}
    for name,family in SOURCES.items():
        mesh=p.read(p.SRC/(family+'.mesh'));before=p.geometry(mesh);source=mesh.submesh_list[0]
        uv,metadata=full_uv(source,family);remesh(mesh,uv,name)
        assert p.geometry(mesh)==before,'Full unwrap altered drawn geometry or skin'
        stream=io.BytesIO();p.oms.MeshSerializer(stream).write(mesh);(REF/(name+'.mesh')).write_bytes(stream.getvalue())
        assert p.geometry(p.read(REF/(name+'.mesh')))==before,'Shared-codec roundtrip altered geometry'
        guide(name,uv,metadata)
        record={'source':family,'sourceMeshSha256':hashlib.sha256((p.SRC/(family+'.mesh')).read_bytes()).hexdigest(),
                'triangles':len(uv),'geometry':before,'uv':uv.tolist(),**metadata}
        if args.textures:
            from bcdds import save_bc
            from scipy.ndimage import distance_transform_edt
            master=REF/(name+'-master.png')
            with Image.open(master) as image:im=image.convert('RGB').resize((1024,1024),Image.Resampling.LANCZOS)
            # Technical gutter extrusion only. No painted pixels are invented.
            mask=Image.new('1',im.size);d=ImageDraw.Draw(mask)
            for row in uv:d.polygon([tuple(v*1023) for v in row],fill=1)
            unused=~np.array(mask);nearest=distance_transform_edt(unused,return_distances=False,return_indices=True)
            pixels=np.array(im);pixels[unused]=pixels[tuple(nearest[:,unused])]
            save_bc(Image.fromarray(pixels),REF/(name+'_d.dds'))
            record['masterSha256']=hashlib.sha256(master.read_bytes()).hexdigest()
            material='\n'.join(['import * from "CR_BZBase.material"',f'material {name} : CR_BZBase','{',
                f'    set_texture_alias DiffuseMap {name}_d.dds','    set_texture_alias NormalMap flat_N.dds',
                '    set_texture_alias SpecularMap crvcca_patch_s.dds','    set_texture_alias EmissiveMap black.dds',
                '    set $diffuse "1 1 1"','    set $ambient "1 1 1"','    set $specular ".15 .15 .15"','    set $shininess "32"','}',''])
            (REF/(name+'.material')).write_text(material,newline='\n')
        receipt[name]=record
        print(name,'fully unwrapped:',len(uv),'triangles in',len(metadata['charts']),'charts, one material; perimeter',round(metadata['perimeter'],3),'front U',round(metadata['frontBandU'],3))
    (REF/'build.json').write_text(json.dumps(receipt,indent=2)+'\n')

if __name__=='__main__':build()
