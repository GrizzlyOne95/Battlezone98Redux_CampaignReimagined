"""Offline contracts for the bomber/rocket pair; no Blender or game required."""
from pathlib import Path
import hashlib,json,sys
import numpy as np
import bomberrocketcockpits as cp
import cockpitglass as cg
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/BomberRocketCockpits';checks=0;report=[]


def check(ok,label):
    global checks
    assert ok,label
    checks+=1


def sha(path):
    b=path.read_bytes();return hashlib.sha256(b.replace(b'\r\n',b'\n') if path.suffix=='.material' else b).hexdigest()


def values(sub):return np.column_stack([cp.shared.values(sub.vertex_data,sem) for sem in (cp.shared.om.VES.POSITION,cp.shared.om.VES.NORMAL,cp.shared.om.VES.TEXTURE_COORDINATES,cp.shared.om.VES.TANGENT)])


members={r['source'].replace('\\','/'):r['runtime'] for r in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
for base,cfg in cp.CONFIG.items():
    receipt=json.loads((REF/base/'build.json').read_text());meta=receipt['alignment'];source=ROOT/'Assets/ModelFixes'/(base+'.mesh');skel=ROOT/'Assets/Models'/(base+'_cockpit.skeleton');mesh=cp.shared.read_mesh(ROOT/'Assets/Models'/(base+'_cockpit.mesh'))
    check(sha(source)==receipt['sources']['exteriorSha256'],'original full hull / fallback preserved '+base)
    check(sha(skel)==receipt['sources']['skeletonSha256'],'byte-exact original rig and every hardpoint '+base)
    for path,digest in receipt['outputs'].items():
        check(sha(ROOT/path)==digest,'output hash '+path);check(members.get(path)==Path(path).name,'case-correct shipping member '+path)
    s,w,eye,shell=cp.shared.rig(skel,cfg['shell']);origin,R=w[eye.handle]
    expected=[2.5341849327087402,1.170401031151414,.48031704127788544] if base=='svhraz' else [0,2.611823081970215,-.9334869980812073]
    check(np.allclose(origin,expected,atol=1e-9) and np.allclose(R,np.eye(3)),'unchanged actual eye and basis '+base)
    check(np.allclose(origin,meta['povPosition']) and np.allclose(R,meta['povBasis']),'receipt camera '+base)
    check(eye.name==('Shb11POV' if base=='svhraz' else 'CDR11POV') and shell.handle==meta['shellHandle'],'source-specific POV/shell '+base)
    check(mesh.skeleton_name==base+'_cockpit.skeleton','namespaced rig resource '+base)
    check([sub.material_name for sub in mesh.submesh_list]==[cfg['material']]+([cp.SV_STRUCTURE] if base=='svhraz' else [])+['CRV/'+base+'Exterior','CRWX_CockpitGlass'],'deliberate faction batches '+base)
    triangles=[];labels=[]
    for sub in mesh.submesh_list:
        d=values(sub);p,n,uv,t=d[:,:3],d[:,3:6],d[:,6:8],d[:,8:11];assign=list(sub.bone_assignments());tri=p[sub.index_array.reshape(-1,3)]
        check(np.isfinite(d).all(),'finite compiled attributes '+base)
        check(np.allclose(np.linalg.norm(n,axis=1),1,atol=.003),'unit normals '+base)
        check(np.allclose(np.linalg.norm(t,axis=1),1,atol=.003) and np.abs((n*t).sum(1)).max()<.003,'orthonormal shader tangents '+base)
        check(len(assign)==len(d) and all(a.bone_index==shell.handle and a.weight==1 for a in assign),'stable shell skinning '+base)
        check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),'no zero-area faces '+base)
        if not sub.material_name.startswith('CRWX'):check(uv.min()>=0 and uv.max()<=1,'bounded compiled UVs '+base)
        if not sub.material_name.startswith('CRWX'):triangles.extend(tri);labels.extend([sub.material_name]*len(tri))
    tr=np.array(triangles);labels=np.array(labels);batches={sub.material_name:values(sub) for sub in mesh.submesh_list};interior=np.concatenate([batches[name] for name in meta['cabinTriangleCounts']]);exterior=batches['CRV/'+base+'Exterior']
    body=cp.shared.read_mesh(source).submesh_list[0];p=cp.shared.values(body.vertex_data,cp.shared.om.VES.POSITION);tri=body.index_array.reshape(-1,3);weights={a.vertex_index:a.bone_index for a in body.bone_assignments()};valid=np.linalg.norm(np.cross(p[tri[:,1]]-p[tri[:,0]],p[tri[:,2]]-p[tri[:,0]]),axis=1)>1e-9
    charts=cp.hardware.CCA_CHARTS if cfg['faction']=='cca' else cp.hardware.CRA_CHARTS;rows=[];backs=[]
    for recorded,(name,bone,planes) in zip(meta['sections'],cp.cut_configs(base)):
        mask=valid&np.array([all(weights.get(int(v))==bone for v in face) for face in tri]);raw,ix,_=cp.tank.source_part(body,mask);a,b,audit=cp.cockpitsections.section(raw,ix,np.flatnonzero(mask),planes,meta['capChart']);rows.append(a[0]);backs.append(b[0])
        check(recorded['sourceTriangles']==audit['sourceTriangles'] and recorded['sourceFaceIds']==audit['sourceFaceIds'],'exact source-face provenance '+name)
        check(recorded['cuts']==audit['cuts'] and all(c['loops']>0 and c['capTriangles']>0 for c in audit['cuts']),'every exposed cut explicitly capped '+name)
        check(recorded['sourceBone']==bone and recorded['driver']==shell.handle,'bounded shell-driven hull selection '+name)
    fit=np.eye(4)
    if base=='svhraz':fit[1,3]=-.30
    expected_rows=np.concatenate(rows);expected_rows[:,:3]+=fit[:3,3];expected_caps,collapsed,remapped=cp.stable_caps(np.concatenate(backs),meta['capChart']);expected_caps[:,:3]+=fit[:3,3]
    check(np.array_equal(exterior,expected_rows),'recorded source positions, normals, UVs and tangents '+base)
    check(np.array_equal(batches[meta['capMaterial']][-len(expected_caps):,:8],expected_caps[:,:8]),'compiled cap attributes '+base)
    check(meta['collapsedCapTriangles']==collapsed and meta['remappedCapUVSlivers']==remapped,'recorded float32 cap handling '+base)
    check(meta['exteriorTransform']==fit.tolist(),'rocket native fit / explicit lower bomber nose cue '+base)
    check(meta['innerShell']['boundaryLoops']==1 and meta['glassPolicy']=='cabin-only' and receipt['glass']['bone']==shell.name,'one canopy boundary and cabin-only weather fit '+base)
    def cast(yaw,pitch):
        y,p=np.radians(yaw),np.radians(pitch);d=np.column_stack([np.cos(p)*np.sin(y),np.sin(p),np.cos(p)*np.cos(y)])@R.T
        return cg.cast(origin,d,tr[:,0],tr[:,1],tr[:,2])
    for pitch,label in [(-80,'floor'),(85,'roof'),(0,'rear')]:
        yaw=np.array([180]) if label=='rear' else np.arange(-180,180,10);dist,_=cast(yaw,np.full(len(yaw),pitch));check(np.isfinite(dist).all(),'one-sided closed '+base+' '+label)
    yaw,pitch=np.meshgrid(np.arange(-10,11,2),np.arange(0,11,2));dist,_=cast(yaw.ravel(),pitch.ravel());check(np.isinf(dist).all(),'clear center aim corridor '+base)
    yaw,pitch=np.meshgrid(np.arange(-48,49,2),np.arange(-30,1,2));dist,hit=cast(yaw.ravel(),pitch.ravel());visible=np.isfinite(dist)&(labels[np.maximum(hit,0)]=='CRV/'+base+'Exterior');check(visible.any(),'actual source hull visible through complete cockpit '+base)
    if base=='cvrckt':
        for side in (yaw.ravel()<0,yaw.ravel()>0):check((visible&side).any(),'both actual prongs visible, not just a fabricated fairing')
    if base=='svhraz':
        material=(ROOT/'Materials/CR_svhraz_cockpit.material').read_text();structure=material.split('material '+cp.SV_STRUCTURE)[1]
        check('DiffuseMap svhraz_d.dds' in structure and 'EmissiveMap capblack_E.dds' in structure,'actual bomber red armor, explicitly nonemissive structure')
        check(len(batches[cp.SV_STRUCTURE])>0 and len(batches[cfg['material']])>0,'separate red structure and untouched cream instruments')
    for panel in meta['panels']:
        p=np.array(panel['instrumentPoints']);u=p[1]-p[0];v=p[3]-p[0];check(abs(np.dot(u,v))<1e-8 and np.allclose(p[2],p[1]+p[3]-p[0]),'rectangular unsheared instrument inset '+base)
        check(abs(np.linalg.norm(u)/np.linalg.norm(v)-panel['sourceAspect'])<1e-7,'original artwork aspect '+base)
        chart=cp.SV_RED[panel['chart']] if base=='svhraz' and panel['chart'] in cp.SV_RED else charts[panel['chart']];x0,y0,x1,y1=chart
        if panel['section'] is not None:a,b=panel['section'];x0,x1=x0+(x1-x0)*a,x0+(x1-x0)*b
        for point,uv in zip(p@R.T+origin,[(x1,y0),(x0,y0),(x0,y1),(x1,y1)]):check(np.any((np.linalg.norm(interior[:,:3]-point,axis=1)<1e-5)&(np.linalg.norm(interior[:,6:8]-uv,axis=1)<1e-6)),'compiled instrument UV corner '+base)
    # Eye-down regression must not be accepted as an unobstructed forward view.
    bad_eye=origin+R@np.array([0,-.75,0]);d=R[:,2][None,:];dist,_=cg.cast(bad_eye,d,tr[:,0],tr[:,1],tr[:,2]);check(np.isfinite(dist).all(),'misaligned-eye negative fixture '+base)
    src=cg.Sources(game=str(ROOT/'Local/no-game'),cr=str(ROOT));path,kind,_=cg.cockpit_mesh(src,base);check(kind=='separate' and Path(path).name==base+'_cockpit.mesh','existing aliases select first-person replacement '+base)
    report.append(dict(base=base,opaqueTriangles=len(tr),sourceHullSamples=int(visible.sum()),pov=eye.name,eye=origin.tolist()))
# Quantization fixtures: a cap may be geometrically valid while its tiny UV
# determinant vanishes in float32. Remap that isolated face, never a whole atlas.
fixture=np.zeros((6,11),'<f4');fixture[:3,:3]=[(0,0,0),(1,0,0),(0,1,0)];fixture[:,3:6]=[0,0,1];fixture[:,8:11]=[1,0,0]
fixed,collapsed,remapped=cp.stable_caps(fixture,(.1,.2,.3,.4))
check(len(fixed)==3 and collapsed==1 and remapped==1,'collapsed position / collapsed UV negative fixtures')
check(np.array_equal(fixed[:,:3],fixture[:3,:3]) and np.allclose(fixed[:,6:8],[(.1,.2),(.3,.2),(.1,.4)]),'UV repair preserves valid cap positions and allocation')
result=dict(checks=checks,units=report)
if '--report' in sys.argv:Path(sys.argv[sys.argv.index('--report')+1]).write_text(json.dumps(result,indent=2)+'\n',newline='\n')
print('BOMBER_ROCKET_COCKPITS_PASS',json.dumps(result))
