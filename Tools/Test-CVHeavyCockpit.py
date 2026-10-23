"""Offline heavy-tank geometry, source sections, camera and UV contracts."""
from pathlib import Path
import hashlib,json,sys
import numpy as np
import cvheavycockpit as cp
import cockpitglass as cg
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/CVHeavyCockpit';checks=0

def check(ok,label):
    global checks
    assert ok,label
    checks+=1

def sha(path):
    b=path.read_bytes();return hashlib.sha256(b.replace(b'\r\n',b'\n') if path.suffix=='.material' else b).hexdigest()

def values(sub):
    return np.column_stack([cp.shared.values(sub.vertex_data,sem) for sem in (cp.shared.om.VES.POSITION,cp.shared.om.VES.NORMAL,cp.shared.om.VES.TEXTURE_COORDINATES,cp.shared.om.VES.TANGENT)])

receipt=json.loads((REF/'build.json').read_text());meta=receipt['alignment'];source=ROOT/'Assets/ModelFixes/cvhtnk.mesh';skel=ROOT/'Assets/Models/cvhtnk_cockpit.skeleton'
check(sha(source)==receipt['sources']['exteriorSha256'],'original exterior/fallback untouched')
check(sha(skel)==receipt['sources']['skeletonSha256'],'byte-exact stock hierarchy, POV and hardpoints')
members={x['source'].replace('\\','/'):x['runtime'] for x in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
for path,digest in receipt['outputs'].items():
    check(sha(ROOT/path)==digest,'compiled output pin '+path)
    check(members.get(path)==Path(path).name,'case-correct shipping member '+path)
s,w,eye,shell=cp.shared.rig(skel,'CEM21BDA');origin,R=w[eye.handle]
check(eye.name=='CEM11POV' and eye.handle==13 and shell.handle==16,'actual heavy-tank eye and shell')
check(np.allclose(origin,[0,2.7389559745788574,.09809499979019165],atol=1e-9) and np.allclose(R,np.eye(3)),'unchanged camera and rest basis')
check(np.allclose(meta['povPosition'],origin) and np.allclose(meta['povBasis'],R),'receipt camera agrees')
mesh=cp.shared.read_mesh(ROOT/'Assets/Models/cvhtnk_cockpit.mesh');check(mesh.skeleton_name=='cvhtnk_cockpit.skeleton','namespaced rig selector')
check([sub.material_name for sub in mesh.submesh_list]==[cp.MATERIAL,'CRWX_CockpitGlass',cp.EXTERIOR,cp.CAPS],'four deliberate material batches')
triangles=[];labels=[];exterior=None
for sub in mesh.submesh_list:
    d=values(sub);p,n,uv,t=d[:,:3],d[:,3:6],d[:,6:8],d[:,8:11];assign=list(sub.bone_assignments())
    check(np.isfinite(d).all(),'finite surface attributes')
    check(np.allclose(np.linalg.norm(n,axis=1),1,atol=.003),'unit normals')
    check(np.allclose(np.linalg.norm(t,axis=1),1,atol=.003) and abs((t*n).sum(1)).max()<.003,'orthonormal tangent bases')
    check(len(assign)==len(d) and all(a.weight==1 for a in assign),'one rigid driver per vertex')
    if sub.material_name in (cp.MATERIAL,'CRWX_CockpitGlass',cp.CAPS):check(all(a.bone_index==shell.handle for a in assign),'stable cockpit and bow backs')
    else:check({a.bone_index for a in assign}=={1,3,16},'independent native side-pod drivers')
    tri=p[sub.index_array.reshape(-1,3)];check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),'nondegenerate triangles '+sub.material_name)
    if sub.material_name==cp.MATERIAL:check(uv.min()>=0 and uv.max()<=1,'bounded authored UV allocations')
    if not sub.material_name.startswith('CRWX'):triangles.extend(tri);labels.extend([sub.material_name]*len(tri))
    if sub.material_name==cp.EXTERIOR:exterior=sub
    if sub.material_name in (cp.EXTERIOR,cp.CAPS):
        handles=[a.bone_index for a in assign];key='exteriorHandles' if sub.material_name==cp.EXTERIOR else 'capHandles';check(hashlib.sha256(json.dumps(handles,separators=(',',':')).encode()).hexdigest()==meta[key+'Sha256'],'compiled section driver receipt')
original=cp.shared.read_mesh(source).submesh_list[0];p=cp.shared.values(original.vertex_data,cp.shared.om.VES.POSITION);tri=original.index_array.reshape(-1,3);q=p[tri];weights={a.vertex_index:a.bone_index for a in original.bone_assignments()};valid=np.linalg.norm(np.cross(q[:,1]-q[:,0],q[:,2]-q[:,0]),axis=1)>1e-9
expected=[];backs=[];expected_handles=[]
configs=[('bow',0,[([0,0,1],1.95),([0,-1,0],-2.30)]),('portGunPod',1,[]),('starboardGunPod',3,[])]
for section,(name,bone,planes) in zip(meta['sections'],configs):
    mask=valid&np.array([all(weights.get(int(v))==bone for v in face) for face in tri]);raw,ix,_=cp.tank.source_part(original,mask);a,b,audit=cp.cockpitsections.section(raw,ix,np.flatnonzero(mask),planes,cp.hardware.CRA_CHARTS['trim'])
    check(section['sourceTriangles']==audit['sourceTriangles'] and section['sourceFaceIds']==audit['sourceFaceIds'],'exact source triangle provenance '+name)
    check(section['cuts']==audit['cuts'],'documented cut planes and closed contours '+name)
    check(section['sourceBone']==bone and section['driver']==(shell.handle if bone==0 else bone),'source-specific skinning')
    if bone!=0:check(len(a[1])//3==1735 and len(b[1])==0,'complete side housing/barrels, no arbitrary crop')
    expected.append(a[0]);backs.append(b[0]);expected_handles.extend([section['driver']]*len(a[0]))
check(np.array_equal(values(exterior),np.concatenate(expected)),'source positions/UVs reproduced at unit scale')
check(np.array_equal(values(mesh.submesh_list[3]),np.concatenate(backs)),'all generated bow backs reproduce')
check(np.array_equal(meta['exteriorTransform'],np.eye(4)),'no invented exterior fit')
check([a.bone_index for a in exterior.bone_assignments()]==expected_handles,'compiled native pod drivers')
check(meta['innerShell']['boundaryLoops']==1 and receipt['glass']['bone']==shell.name,'single canopy, glass fitted only to interior')
tr=np.array(triangles);labels=np.array(labels)
def cast(yaw,pitch):
    y,p=np.radians(yaw),np.radians(pitch);d=np.column_stack([np.cos(p)*np.sin(y),np.sin(p),np.cos(p)*np.cos(y)])@R.T
    return cg.cast(origin,d,tr[:,0],tr[:,1],tr[:,2])
for pitch,label in [(-80,'floor'),(85,'roof'),(0,'rear')]:
    yaw=np.arange(-180,180,10) if label!='rear' else np.array([180]);distance,_=cast(yaw,np.full(len(yaw),pitch));check(np.isfinite(distance).all(),'one-sided closed '+label)
yaw,pitch=np.meshgrid(np.arange(-10,11,2),np.arange(0,11,2));distance,_=cast(yaw.ravel(),pitch.ravel());check(np.isinf(distance).all(),'open central aim corridor')
hits=[]
for sign in (-1,1):
    yaw,pitch=np.meshgrid(sign*np.arange(35,101,2),np.arange(-28,3,2));dist,hit=cast(yaw.ravel(),pitch.ravel());visible=np.isfinite(dist)&(labels[np.maximum(hit,0)]==cp.EXTERIOR);check(visible.any(),'real side pod visible through complete cockpit');hits.append(int(visible.sum()))
yaw,pitch=np.meshgrid(np.arange(-15,16),np.arange(-28,-2));dist,hit=cast(yaw.ravel(),pitch.ravel());bow=int((np.isfinite(dist)&(labels[np.maximum(hit,0)]==cp.EXTERIOR)).sum());check(bow>0,'real bow visible above lower sill')
hp=values(mesh.submesh_list[0])[:,:3];huv=values(mesh.submesh_list[0])[:,6:8]
for panel in meta['panels']:
    p=np.array(panel['instrumentPoints']);u=p[1]-p[0];v=p[3]-p[0];check(abs(np.dot(u,v))<1e-8 and np.allclose(p[2],p[1]+p[3]-p[0]),'rectangular inserts, no sheared dials')
    check(abs(np.linalg.norm(u)/np.linalg.norm(v)-panel['sourceAspect'])<1e-7,'artwork aspect retained')
    x0,y0,x1,y1=cp.hardware.CRA_CHARTS[panel['chart']]
    for point,uv in zip(p@R.T+origin,[(x1,y0),(x0,y0),(x0,y1),(x1,y1)]):check(np.any((np.linalg.norm(hp-point,axis=1)<1e-5)&(np.linalg.norm(huv-uv,axis=1)<1e-6)),'compiled chart corner')
src=cg.Sources(game=str(ROOT/'Local/no-game'),cr=str(ROOT));path,kind,_=cg.cockpit_mesh(src,'cvhtnk');check(kind=='separate' and Path(path).name=='cvhtnk_cockpit.mesh','native first-person resource routing')
report=dict(checks=checks,sidePodSamples=hits,bowSamples=bow,opaqueTriangles=len(tr))
if '--report' in sys.argv:Path(sys.argv[sys.argv.index('--report')+1]).write_text(json.dumps(report,indent=2)+'\n',newline='\n')
print('CV_HEAVY_COCKPIT_PASS',json.dumps(report))
