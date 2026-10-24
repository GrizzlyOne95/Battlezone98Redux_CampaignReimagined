"""Native-rest geometry and offline-art contracts; no installed game required."""
from pathlib import Path
import io,json,hashlib,sys
import numpy as np
import lightwalkercockpits as cp
import cockpitglass as cg
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/LightWalkerCockpits';checks=0;report=[]


def check(ok,label):
    global checks
    assert ok,label
    checks+=1


def sha(p):
    b=p.read_bytes();return hashlib.sha256(b.replace(b'\r\n',b'\n') if p.suffix=='.material' else b).hexdigest()


def values(sub):return np.column_stack([cp.shared.values(sub.vertex_data,sem) for sem in (cp.shared.om.VES.POSITION,cp.shared.om.VES.NORMAL,cp.shared.om.VES.TEXTURE_COORDINATES,cp.shared.om.VES.TANGENT)])


def posed_data(sub,s,rot):
    d=values(sub);bind=cp.walkerpose.world(s);posed=cp.walkerpose.world(s,rot);result=d.copy()
    for a in sub.bone_assignments():
        T=posed[a.bone_index]@np.linalg.inv(bind[a.bone_index]);result[a.vertex_index:a.vertex_index+1]=cp.transform(d[a.vertex_index:a.vertex_index+1],T)
    return result


members={r['source'].replace('\\','/'):r['runtime'] for r in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
for base,cfg in cp.CONFIG.items():
    ref=REF/base;receipt=json.loads((ref/'build.json').read_text());meta=receipt['alignment'];rigpath=ref/'source-rig.skeleton';s,_,eye,shell=cp.shared.rig(rigpath,cfg['shell']);rot=meta['nativeBoneRotations'];posed=cp.walkerpose.world(s,rot);bind=cp.walkerpose.world(s);origin=posed[eye.handle][:3,3];R=posed[eye.handle][:3,:3]
    check(sha(rigpath)==receipt['sources']['cockpitRigSha256'],'original cockpit rig fixture '+base)
    check(sha(ref/'source-full-rig.skeleton')==receipt['sources']['fullRigSha256'],'original full rig fixture '+base)
    check(sha(ref/'source-cockpit.mesh')==receipt['sources']['sourceCockpitSha256'],'immutable original cockpit snapshot '+base)
    check(sha(ref/'source-sections.npz')==receipt['sources']['sectionFixtureSha256'],'immutable original source section inputs '+base)
    if base=='cvltnk':
        check(sha(ROOT/'Assets/ModelFixes/cvltnk.mesh')==receipt['sources']['exteriorSha256'],'full light-tank body/fallback unchanged')
        check(sha(ROOT/'Assets/Models/cvltnk_cockpit.skeleton')==sha(rigpath),'byte-exact original light-tank rig')
    else:
        check(sha(ROOT/'Assets/ModelFixes'/(base+'_c.skeleton'))==sha(rigpath),'byte-exact fixed walker hierarchy, POV, drivers')
        native=(ROOT/'Assets/ModelFixes'/(base+'.vdf')).read_bytes();check(hashlib.sha256(native).hexdigest()==receipt['sources']['nativeVdfSha256'],'prior native animation fixes unchanged '+base)
        mirror=np.diag([-1.,1.,1.]);expected={p.name:(mirror@np.array(p.matrix[:9]).reshape(3,3).T@mirror).tolist() for p in cp.legacy.read_vdf(native).parts if p.name.lower()!='null'};check(rot==expected,'native GEO-local rest rotations independently reproduce '+base)
    for path,digest in receipt['outputs'].items():check(sha(ROOT/path)==digest,'compiled resource pin '+path);check(members.get(path)==Path(path).name,'case-correct shipping resource '+path)
    check(np.allclose(origin,meta['povPosition'],atol=1e-9) and np.allclose(R,meta['povBasis'],atol=1e-9),'full native-parent POV chain retained '+base)
    check(eye.name==('CNA11POV' if base=='cvltnk' else base[:2]+'w11POV') and shell.handle==meta['shellHandle'],'correct actual POV/shell '+base)
    modelpath=ROOT/('Assets/Models' if base=='cvltnk' else 'Assets/ModelFixes')/(cfg['resource']+'.mesh');mesh=cp.shared.read_mesh(modelpath)
    check(mesh.skeleton_name==cfg['resource']+'.skeleton','original runtime rig selection '+base)
    check([sub.material_name for sub in mesh.submesh_list]==[cfg['material'],'CRWX_CockpitGlass','CRV/'+base+'HeadHull','CRV/'+base+'SectionBacks'],'four deliberate batches '+base)
    triangles=[];labels=[];data={}
    for sub in mesh.submesh_list:
        d=values(sub);native=posed_data(sub,s,rot);data[sub.material_name]=native;assign=list(sub.bone_assignments());q=d[sub.index_array.reshape(-1,3),:3];p,n,uv,t=d[:,:3],d[:,3:6],d[:,6:8],d[:,8:11]
        check(np.isfinite(d).all() and np.isfinite(native).all(),'finite bind/native attributes '+base)
        check(np.allclose(np.linalg.norm(n,axis=1),1,atol=.004),'unit compiled normals '+base)
        check(np.allclose(np.linalg.norm(t,axis=1),1,atol=.004) and abs((n*t).sum(1)).max()<.004,'orthonormal compiled tangent basis '+base)
        check(len(assign)==len(d) and all(a.weight==1 for a in assign),'one rigid driver per vertex '+base)
        check((np.linalg.norm(np.cross(q[:,1]-q[:,0],q[:,2]-q[:,0]),axis=1)>1e-10).all(),'no degenerate compiled triangles '+base)
        if sub.material_name in (cfg['material'],'CRWX_CockpitGlass'):check(all(a.bone_index==shell.handle for a in assign),'interior/glass follows original cockpit shell '+base)
        else:
            key='exteriorHandles' if sub.material_name.endswith('HeadHull') else 'capHandles';handles=[a.bone_index for a in assign];check(hashlib.sha256(json.dumps(handles,separators=(',',':')).encode()).hexdigest()==meta[key+'Sha256'],'compiled source-piece driver pin '+base)
            check(set(handles)=={shell.handle if base=='cvltnk' else 4},'head pieces follow native head, not arms or legs '+base)
        if not sub.material_name.startswith('CRWX'):
            check(uv.min()>=0 and uv.max()<=1,'bounded compiled UVs '+base);triangles.extend(native[sub.index_array.reshape(-1,3),:3]);labels.extend([sub.material_name]*len(q))
    tr=np.array(triangles);labels=np.array(labels);interior=data[cfg['material']];charts=cp.hw.CRA_CHARTS if cfg['faction']=='cra' else cp.hw.CCA_CHARTS
    fs,*_=cp.shared.rig(ref/'source-full-rig.skeleton',cfg['shell']);fb=cp.walkerpose.world(fs);fp=cp.walkerpose.world(fs,rot);fixtures=np.load(ref/'source-sections.npz');rows=[];backs=[];face_labels=[]
    for record,(name,bone,seed,planes) in zip(meta['sections'],cp.configs(base,origin,R)):
        raw=fixtures[name+'Data'];indices=fixtures[name+'Indices'];ids=fixtures[name+'SourceIds'];T=fp[bone]@np.linalg.inv(fb[bone]);check(np.allclose(T,record['sourcePose'],atol=1e-9),'native source driver transform '+name)
        a,b,audit=cp.sections.section(cp.transform(raw,T),indices,ids,planes,record['capChart']);cap,collapsed,uv_slivers=cp.stable_caps(b[0],record['capChart']);rows.append(a[0]);backs.append(cap);face_labels.extend([name]*(len(a[1])//3))
        check(record['sourceTriangles']==audit['sourceTriangles'] and record['sourceFaceIds']==audit['sourceFaceIds'],'exact intended source faces, not arbitrary material hits '+name)
        check(record['cuts']==audit['cuts'] and all(c['loops']>0 and c['capTriangles']>0 for c in audit['cuts']),'new cut contours explicitly closed '+name)
        check(record['collapsedCapTriangles']==collapsed and record['remappedCapUVSlivers']==uv_slivers,'documented cap quantization '+name)
    check(np.allclose(data['CRV/'+base+'HeadHull'],np.concatenate(rows),atol=7e-6),'compiled native-rest source shape/UVs unchanged '+base)
    check(np.allclose(data['CRV/'+base+'SectionBacks'],np.concatenate(backs),atol=7e-6),'compiled explicit cut backs reproduce '+base)
    check(meta['innerShell']['boundaryLoops']==1 and meta['glassPolicy']=='cabin-only' and receipt['glass']['bone']==shell.name,'closed liner, only canopy open, cabin-only glass '+base)
    def cast(yaw,pitch):
        y,p=np.radians(yaw),np.radians(pitch);d=np.column_stack([np.cos(p)*np.sin(y),np.sin(p),np.cos(p)*np.cos(y)])@R.T;return cg.cast(origin,d,tr[:,0],tr[:,1],tr[:,2])
    for pitch,label in [(-80,'floor'),(85,'roof'),(0,'rear')]:
        yaw=np.array([180]) if label=='rear' else np.arange(-180,180,10);dist,_=cast(yaw,np.full(len(yaw),pitch));check(np.isfinite(dist).all(),'one-sided closed '+label+' '+base)
    yaw,pitch=np.meshgrid(np.arange(-10,11,2),np.arange(0,3));dist,_=cast(yaw.ravel(),pitch.ravel());check(np.isinf(dist).all(),'clear central forward aim corridor '+base)
    yaw,pitch=np.meshgrid(np.arange(-45,46),np.arange(-30,31));dist,hit=cast(yaw.ravel(),pitch.ravel());visible=np.isfinite(dist)&(labels[np.maximum(hit,0)]=='CRV/'+base+'HeadHull');check(visible.any(),'actual source surface visible, caps do not satisfy it '+base)
    face_names=np.array(face_labels);exterior_first=int(np.flatnonzero(labels=='CRV/'+base+'HeadHull')[0]);part_hits={name:int((visible&(face_names[np.clip(hit-exterior_first,0,len(face_names)-1)]==name)).sum()) for name in sorted(set(face_names))}
    for name,hits in part_hits.items():
        if name!='chin':check(hits>0,'intended original surface visible through complete cockpit '+base+' '+name)
    # At this eye the lower helmet is an inward-facing armor back, not proof
    # of visible original outer skin. Keep that cap claim separate and ensure
    # it never hides an instrument (checked independently below).
    if base!='cvltnk':check((np.isfinite(dist)&(labels[np.maximum(hit,0)]=='CRV/'+base+'SectionBacks')).any(),'closed inner head armor visible, not counted as source skin '+base)
    for panel in meta['panels']:
        p=np.array(panel['instrumentPoints']);u=p[1]-p[0];v=p[3]-p[0];check(abs(np.dot(u,v))<1e-8 and np.allclose(p[2],p[1]+p[3]-p[0]),'planar rectangular instrument insert '+base)
        check(abs(np.linalg.norm(u)/np.linalg.norm(v)-panel['sourceAspect'])<1e-7,'original artwork proportions '+base)
        x0,y0,x1,y1=charts[panel['chart']]
        if panel['section'] is not None:a,b=panel['section'];x0,x1=x0+(x1-x0)*a,x0+(x1-x0)*b
        for point,uv in zip(p@R.T+origin,[(x1,y0),(x0,y0),(x0,y1),(x1,y1)]):check(np.any((np.linalg.norm(interior[:,:3]-point,axis=1)<1e-5)&(np.linalg.norm(interior[:,6:8]-uv,axis=1)<1e-6)),'native-rest compiled chart corner '+base)
        if panel['chart'] in ('switch','service','console'):
            point=p.mean(0)@R.T+origin;delta=point-origin;distance=np.linalg.norm(delta);hitdist,_=cg.cast(origin,(delta/distance)[None,:],tr[:,0],tr[:,1],tr[:,2]);check(abs(hitdist[0]-distance)<.003,'instrument not hidden by new hull/cap '+base)
    if base!='cvltnk':
        # Omitting inverse bind compensation recreates the old tilted shell.
        wrong=cp.transform(interior,posed[shell.handle]@np.linalg.inv(bind[shell.handle]));check(np.abs(wrong[:,:3]-interior[:,:3]).max()>.10,'uncompensated-native-shell negative fixture '+base)
        # Head-pitch diagnostic: camera, visor and controls must move together.
        for angle in (-15,15):
            a=np.radians(angle);c,z=np.cos(a),np.sin(a);pitch=np.array([[1,0,0],[0,c,-z],[0,z,c]]);r2={**rot};head=base[:2]+'w11hed';r2[head]=(np.array(rot[head])@pitch).tolist();p2=cp.walkerpose.world(s,r2);o2=p2[eye.handle][:3,3];R2=p2[eye.handle][:3,:3]
            for sub in (mesh.submesh_list[0],mesh.submesh_list[2]):check(np.allclose((posed_data(sub,s,r2)[:,:3]-o2)@R2,(data[sub.material_name][:,:3]-origin)@R,atol=1e-5),'synthetic head pitch preserves cockpit/head relationship '+base)
    material=(ROOT/'Materials'/('CR_'+base+'_cockpit.material')).read_text().split('material CRV/'+base+'SectionBacks')[1];check('EmissiveMap capblack_E.dds' in material,'cut armor never emits '+base)
    src=cg.Sources(game=str(ROOT/'Local/no-game'),cr=str(ROOT));path,kind,_=cg.cockpit_mesh(src,base);check(Path(path).name==cfg['resource']+'.mesh' and kind==('separate' if base=='cvltnk' else 'table'),'actual fixed-table / namespaced routing '+base)
    report.append(dict(base=base,opaqueTriangles=len(tr),sourceCueSamples=part_hits,pov=eye.name,eye=origin.tolist()))
result=dict(checks=checks,units=report)
if '--report' in sys.argv:Path(sys.argv[sys.argv.index('--report')+1]).write_text(json.dumps(result,indent=2)+'\n',newline='\n')
print('LIGHT_WALKER_COCKPITS_PASS',json.dumps(result))
