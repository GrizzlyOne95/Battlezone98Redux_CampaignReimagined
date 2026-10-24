"""Source-frame identity, native camera, visibility and UV contracts."""
from pathlib import Path
import hashlib,json,sys
import numpy as np
from PIL import Image
import lighttankcockpits as cp
import cockpitglass as cg
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/LightTankCockpits';checks=0
members={x['source'].replace('\\','/'):x['runtime'] for x in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}

def check(ok,label):
    global checks
    assert ok,label
    checks+=1

def sha(path):
    data=path.read_bytes()
    return hashlib.sha256(data.replace(b'\r\n',b'\n') if path.suffix=='.material' else data).hexdigest()

def shell_triangles(mesh,handle):
    result=[]
    for sub in mesh.submesh_list:
        if sub.material_name.startswith('CRWX'):continue
        p=cp.shared.values(sub.vertex_data,cp.shared.om.VES.POSITION);tri=sub.index_array.reshape(-1,3);weights=np.zeros(len(p))
        for a in sub.bone_assignments():
            if a.bone_index==handle:weights[a.vertex_index]+=a.weight
        result.append(p[tri[(weights[tri]>.99).all(1)]])
    return np.concatenate(result)

report={}
for base,cfg in cp.CONFIG.items():
    receipt=json.loads((REF/base/'build.json').read_text());meta=receipt['alignment'];skel=ROOT/'Assets/Models'/(base+'_cockpit.skeleton');source=ROOT/receipt['sources']['baseline'];original=cp.shared.read_mesh(source)
    check(sha(source)==receipt['sources']['exteriorSha256'],'original source/fallback preserved')
    check(sha(skel)==receipt['sources']['skeletonSha256'],'full stock rig bytes preserved')
    for path,digest in receipt['outputs'].items():
        check(sha(ROOT/path)==digest,'pinned compiled output '+path)
        check(members.get(path)==Path(path).name,'case-correct shipping resource '+path)
    s,w,eye,shell=cp.shared.rig(skel,cfg['shell']);origin,R=w[eye.handle]
    check(np.allclose(origin,[.0997999981045723,1.46069997549057,.1421000063419342],atol=1e-9),'actual unchanged POV position')
    check(np.allclose(R,np.eye(3),atol=1e-8) and np.allclose(meta['povBasis'],R),'native/rest eye basis fixture')
    check(meta['shell']==shell.name and meta['shellHandle']==shell.handle,'right stable shell for this faction')
    mesh=cp.shared.read_mesh(ROOT/'Assets/Models'/(base+'_cockpit.mesh'))
    check(mesh.skeleton_name==base+'_cockpit.skeleton','namespaced rig resource')
    check([sub.material_name for sub in mesh.submesh_list]==[cfg['material'],'CRV/'+base+'OriginalFrame','CRV/'+base+'HullPaint','CRWX_CockpitGlass'],'only intended four batches')
    for sub in mesh.submesh_list:
        p,n,uv,t=[cp.shared.values(sub.vertex_data,sem) for sem in (cp.shared.om.VES.POSITION,cp.shared.om.VES.NORMAL,cp.shared.om.VES.TEXTURE_COORDINATES,cp.shared.om.VES.TANGENT)]
        check(np.isfinite(np.column_stack([p,n,uv,t])).all(),'finite compiled vertices')
        check(np.allclose(np.linalg.norm(n,axis=1),1,atol=.003),'unit surface normals')
        check(np.allclose(np.linalg.norm(t,axis=1),1,atol=.003) and abs((n*t).sum(1)).max()<.003,'unit orthogonal tangents')
        weights=list(sub.bone_assignments());check(len(weights)==len(p) and all(a.weight==1 and a.bone_index==shell.handle for a in weights),'stable-shell skinning')
        tri=p[sub.index_array.reshape(-1,3)];check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),'nondegenerate triangles')
        if sub.material_name==cfg['material']:check(uv.min()>=0 and uv.max()<=1,'bounded authored UV allocations; original frame tiling is preserved separately')
    body=original.submesh_list[0];p=cp.shared.values(body.vertex_data,cp.shared.om.VES.POSITION);tri=body.index_array.reshape(-1,3);weights=np.zeros(len(p))
    for a in body.bone_assignments():
        if a.bone_index==shell.handle:weights[a.vertex_index]+=a.weight
    q=p[tri];keep=(weights[tri]>.99).all(1)&(np.linalg.norm(np.cross(q[:,1]-q[:,0],q[:,2]-q[:,0]),axis=1)>1e-9)
    check(np.array_equal(np.flatnonzero(keep),meta['exteriorSourceIndices']) and keep.sum()==316,'complete original exterior framing, not a body merge or crop')
    raw,indices,_=cp.tank.source_part(body,keep);frame=mesh.submesh_list[1];data=np.column_stack([cp.shared.values(frame.vertex_data,sem) for sem in (cp.shared.om.VES.POSITION,cp.shared.om.VES.NORMAL,cp.shared.om.VES.TEXTURE_COORDINATES,cp.shared.om.VES.TANGENT)])
    check(np.array_equal(frame.index_array,indices),'original framing connectivity unchanged')
    check(np.array_equal(data[:,:3],raw[:,:3]),'original exterior framing at exact native positions')
    check(np.array_equal(data[:,6:8],raw[:,6:8]),'original faction framing UVs unchanged')
    check(np.allclose(data[:,3:6],raw[:,3:6],atol=1e-7),'original framing normals unchanged')
    check(np.array_equal(meta['exteriorTransform'],np.eye(4)),'no framing fit, rotation or scale')
    full=cp.shared.read_mesh(ROOT/'Assets/ModelFixes'/(base+'.mesh'));check(full.skeleton_name==original.skeleton_name and len(full.submesh_list)==len(original.submesh_list)+1,'full vehicle adds only a paint batch, keeps native rig reference')
    for a,b in zip(original.submesh_list,full.submesh_list):
        check(a.material_name==b.material_name and np.array_equal(a.index_array,b.index_array),'full vehicle original material and connectivity preserved')
        for sem in (cp.shared.om.VES.POSITION,cp.shared.om.VES.NORMAL,cp.shared.om.VES.TEXTURE_COORDINATES,cp.shared.om.VES.TANGENT):
            first=a.vertex_data.vertex_declaration.find_by_semantic(sem);second=b.vertex_data.vertex_declaration.find_by_semantic(sem)
            check((first is None and second is None) or (first is not None and second is not None and np.array_equal(cp.shared.values(a.vertex_data,sem),cp.shared.values(b.vertex_data,sem))),'full vehicle original surface attributes byte-exact, including absent channels')
        check([(x.vertex_index,x.bone_index,x.weight) for x in a.bone_assignments()]==[(x.vertex_index,x.bone_index,x.weight) for x in b.bone_assignments()],'full vehicle original skinning preserved')
    for model,bones in [(mesh,[shell.handle]),(full,[cfg['bodyBone'],shell.handle])]:
        expected,paint_indices,handles,provenance=cp.markings.geometry(body,origin,bones,cfg['faction']);paint=next(sub for sub in model.submesh_list if sub.material_name=='CRV/'+base+'HullPaint');actual=np.column_stack([cp.shared.values(paint.vertex_data,sem) for sem in (cp.shared.om.VES.POSITION,cp.shared.om.VES.NORMAL,cp.shared.om.VES.TEXTURE_COORDINATES,cp.shared.om.VES.TANGENT)])
        check(np.array_equal(actual,expected) and np.array_equal(paint.index_array,paint_indices),'1P/3P stripes are surface-conforming source clips, not free-floating quads')
        assignments=list(paint.bone_assignments());check(all(a.bone_index==handles[a.vertex_index] and a.weight==1 for a in assignments),'paint follows the original source surface bone')
        check(len(provenance)>0 and {'dark','accent'}=={p['layer'] for p in provenance},'both paint layers exist')
        stem=cp.scout.CONFIG[cfg['faction']]['stem'];emission=np.array(Image.open(ROOT/'Assets/Textures'/(stem+'_e.dds')).convert('RGB'));diffuse=np.array(Image.open(ROOT/'Assets/Textures'/(stem+'_d.dds')).convert('RGB'));uv=actual[:,6:8];xy=np.clip(np.rint(uv*1023).astype(int),0,1023);colors=diffuse[xy[:,1],xy[:,0]];accent=uv[:,1]<.82
        check(emission[xy[:,1],xy[:,0]].max()<12,'hull paint uses quiet nonemissive charts')
        rgb=colors[accent].mean(0);check((rgb[0]>rgb[1]*1.5 and rgb[0]>80) if cfg['faction']=='bdog' else (rgb[1]>rgb[0] and rgb[2]>rgb[0]),'actual faction paint palette, red Black Dog / petrol NSDF')
    check(meta['innerShell']['boundaryLoops']==1,'liner only has intended canopy opening')
    check(receipt['glass']['vertices']>0 and receipt['glass']['bone']==shell.name,'weather glass fit to this shell')
    before=shell_triangles(original,shell.handle);after=shell_triangles(mesh,shell.handle)
    def cast(tris,yaws,pitches):
        y,p=np.radians(yaws),np.radians(pitches);d=np.column_stack([np.cos(p)*np.sin(y),np.sin(p),np.cos(p)*np.cos(y)])@R.T
        return cg.cast(origin,d,tris[:,0],tris[:,1],tris[:,2])[0]
    for pitch,label in [(-80,'floor'),(85,'roof'),(0,'rear')]:
        yaw=np.arange(-180,180,10) if label!='rear' else np.array([180]);check(np.isfinite(cast(after,yaw,np.full(len(yaw),pitch))).all(),'closed '+label)
    yaw,pitch=np.meshgrid(np.arange(-10,11,2),np.arange(0,11,2));check(np.isinf(cast(after,yaw.ravel(),pitch.ravel())).all(),'clear central aim corridor')
    yaw,pitch=np.meshgrid(np.r_[np.arange(-85,-24),np.arange(25,86)],np.arange(-12,13));yaw,pitch=yaw.ravel(),pitch.ravel()
    old_open=np.isinf(cast(before,yaw,pitch));new_open=np.isinf(cast(after,yaw,pitch));metrics={}
    for side,mask in [('modelNegativeX',yaw<0),('modelPositiveX',yaw>0),('both',np.ones(len(yaw),bool))]:
        old=float(old_open[mask].mean());new=float(new_open[mask].mean());metrics[side]=dict(beforeOpen=old,afterOpen=new)
        check(new>=old-.005,'no peripheral visibility regression '+side)
    check(metrics['both']['afterOpen']>metrics['both']['beforeOpen']+.12,'meaningful measured peripheral opening, same eye and rays')
    hp=cp.shared.values(mesh.submesh_list[0].vertex_data,cp.shared.om.VES.POSITION);huv=cp.shared.values(mesh.submesh_list[0].vertex_data,cp.shared.om.VES.TEXTURE_COORDINATES)
    for panel in meta['panels']:
        p=np.array(panel['instrumentPoints']);u=p[1]-p[0];v=p[3]-p[0]
        check(abs(np.dot(u,v))<1e-8 and np.allclose(p[2],p[1]+p[3]-p[0]),'orthogonal rectangular insert, no dial shear')
        check(abs(np.linalg.norm(u)/np.linalg.norm(v)-panel['sourceAspect'])<1e-7,'original pre-repack artwork proportions')
        x0,y0,x1,y1=cp.scout.CHARTS[panel['chart']]
        for point,uv in zip(p@R.T+origin,[(x1,y0),(x0,y0),(x0,y1),(x1,y1)]):check(np.any((np.linalg.norm(hp-point,axis=1)<1e-5)&(np.linalg.norm(huv-uv,axis=1)<1e-6)),'compiled UV corner matches intended insert')
    sources=cg.Sources(game=str(ROOT/'Local/no-game'),cr=str(ROOT));path,kind,_=cg.cockpit_mesh(sources,base);check(kind=='separate' and Path(path).name==base+'_cockpit.mesh','native first-person resource naming')
    report[base]=dict(opaqueTriangles=len(after),peripheral=metrics)
if '--report' in sys.argv:
    path=Path(sys.argv[sys.argv.index('--report')+1]);path.write_text(json.dumps(report,indent=2)+'\n',newline='\n')
print('LIGHT_TANK_COCKPITS_PASS',checks,json.dumps(report))
