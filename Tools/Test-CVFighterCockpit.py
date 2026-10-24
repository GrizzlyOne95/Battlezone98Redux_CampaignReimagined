"""Targeted cvfigh cockpit contracts; no installed game or Blender required."""
from pathlib import Path
import hashlib,json,sys,importlib.util
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
import cvfighcockpit as cp
import cockpitglass as cg
from bcdds import bc_dds_problem
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/CVFighterCockpit';count=0
def check(ok,message):
    global count
    assert ok,message
    count+=1
def sha(p):
    data=p.read_bytes()
    return hashlib.sha256(data.replace(b'\r\n',b'\n') if p.suffix=='.material' else data).hexdigest()
receipt=json.loads((REF/'build.json').read_text());check(sha(REF/'atlas-master.png')==receipt['masterSha256'],'authored bitmap pinned')
for relative,digest in receipt['outputs'].items():check(sha(ROOT/relative)==digest,'compiled output pinned: '+relative)
check(sha(ROOT/'Assets/ModelFixes/cvfigh.mesh')==receipt['sources']['exteriorSha256'],'existing exterior / fallback unchanged')
skelpath=ROOT/'Assets/Models/cvfigh_cockpit.skeleton';check(sha(skelpath)==receipt['sources']['skeletonSha256'],'every stock bone, hardpoint and POV retained byte-for-byte')
s,world,eye,shell=cp.rig(skelpath);origin,R=world[eye.handle]
check(eye.name=='CFL11POV' and shell.name=='CFL21BDA' and shell.handle==10,'correct real POV and shell bone')
check(np.allclose(origin,receipt['alignment']['povPosition']) and np.allclose(R,receipt['alignment']['povBasis']),'exact source eye transform')
mesh=cp.shared.read_mesh(ROOT/'Assets/Models/cvfigh_cockpit.mesh');check(mesh.skeleton_name=='cvfigh_cockpit.skeleton','namespaced rig selector')
check([x.material_name for x in mesh.submesh_list]==[cp.MATERIAL,cp.GUNS,'CRWX_CockpitGlass'],'only authored interior, selected guns and weather glass')
opaque=[];gun_first=0;gun_last=0
for sub in mesh.submesh_list:
    vd=sub.vertex_data;p=cp.shared.values(vd,cp.shared.om.VES.POSITION);n=cp.shared.values(vd,cp.shared.om.VES.NORMAL);uv=cp.shared.values(vd,cp.shared.om.VES.TEXTURE_COORDINATES);t=cp.shared.values(vd,cp.shared.om.VES.TANGENT)
    check(np.isfinite(p).all() and np.isfinite(uv).all(),'finite geometry / UVs')
    check(np.allclose(np.linalg.norm(n,axis=1),1,atol=.003),'unit normals')
    check(np.allclose(np.linalg.norm(t,axis=1),1,atol=.003),'unit shader tangents')
    weights=list(sub.bone_assignments());check(len(weights)==len(p) and all(a.bone_index==10 and a.weight==1 for a in weights),'all first-person vertices follow stable shell')
    tri=p[sub.index_array.reshape(-1,3)];check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),'no degenerate triangles')
    if sub.material_name!='CRWX_CockpitGlass':
        check(uv.min()>=0 and uv.max()<=1,'opaque UV range')
        if sub.material_name==cp.GUNS:gun_first=sum(len(x) for x in opaque);gun_last=gun_first+len(tri)
        opaque.append(tri)
tri=np.concatenate(opaque)
def rays(yaws,pitch):
    y=np.radians(yaws);p=np.radians(pitch)
    return np.column_stack([np.cos(p)*np.sin(y),np.full(len(y),np.sin(p)),np.cos(p)*np.cos(y)])@R.T
for pitch in (0,5,10):
    distance,_=cg.cast(origin,rays(np.arange(-10,11,2),pitch),tri[:,0],tri[:,1],tri[:,2]);check(np.isinf(distance).all(),'clear central aiming corridor')
for pitch,label in [(-70,'floor/side seams'),(85,'roof seams')]:
    distance,_=cg.cast(origin,rays(np.arange(-180,180,10),pitch),tri[:,0],tri[:,1],tri[:,2]);check(np.isfinite(distance).all(),'closed '+label)
distance,_=cg.cast(origin,rays(np.array([180]),0),tri[:,0],tri[:,1],tri[:,2]);check(np.isfinite(distance).all(),'closed rear bulkhead')
check(receipt['alignment']['innerShell']['boundaryLoops']==1,'only intended canopy boundary loop')
visible=[]
for sign in (-1,1):
    directions=np.concatenate([rays(sign*np.arange(15,48,1),pitch) for pitch in range(-31,1)])
    dist,hit=cg.cast(origin,directions,tri[:,0],tri[:,1],tri[:,2]);hits=np.isfinite(dist)&(hit>=gun_first)&(hit<gun_last);visible.append(int(hits.sum()));check(hits.any(),'source wing/gun assembly present inside forward angular sample: '+str(sign))
parts,*_=cp.geometry(ROOT/'Assets/ModelFixes/cvfigh.mesh',skelpath);compiled=mesh.submesh_list[1]
check(np.array_equal(cp.shared.values(compiled.vertex_data,cp.shared.om.VES.TEXTURE_COORDINATES),parts[cp.GUNS][0][:,6:8]),'source gun UVs preserved')
check(receipt['alignment']['gunTriangles']==3992 and len(mesh.submesh_list[1].index_array)//3==3992,'bounded wing-and-gun sections, not full hull or hardpoint cubes')
check(receipt['alignment']['gunPlacement']==dict(inboard=0,up=0,forward=0),'native wing/gun relationship, no sideways muzzle drift')
check(receipt['alignment']['wingCapTriangles']==110 and len(receipt['alignment']['wingSections'])==2,'both rear wing sections explicitly capped')
for sem,column in [(cp.shared.om.VES.POSITION,slice(0,3)),(cp.shared.om.VES.NORMAL,slice(3,6)),(cp.shared.om.VES.TANGENT,slice(8,11))]:
    check(np.array_equal(cp.shared.values(compiled.vertex_data,sem),parts[cp.GUNS][0][:,column]),'compiled source section attributes reproduce')
check(len(parts[cp.MATERIAL][1])//3==720,'lowered side sills with capped front join posts and source-section backs')
check(receipt['alignment']['sillFit']==cp.SILL_FIT,'intentional lowered outer-sill profile recorded')
# Classify actual low barrel source faces, NOT every triangle in the combined
# wing/gun material batch. A visible wing must not satisfy the barrel test.
body=cp.shared.read_mesh(ROOT/'Assets/ModelFixes/cvfigh.mesh').submesh_list[0];source_p=cp.shared.values(body.vertex_data,cp.shared.om.VES.POSITION);source_tri=body.index_array.reshape(-1,3);q=source_p[source_tri]
barrel_source=(np.abs(q[:,:,0]).min(1)>1.7)&(np.abs(q[:,:,0]).max(1)<2.3)&(q[:,:,1].max(1)<.35)&(q[:,:,2].min(1)>2.0)
source_ids=np.concatenate([section['sourceFaceIds'] for section in receipt['alignment']['wingSections']]);barrel=np.zeros(len(tri),bool);barrel[gun_first:gun_last]=barrel_source[source_ids]
v=np.tan(np.radians(32));x,y=np.meshgrid(np.linspace(-v*16/9,v*16/9,160),np.linspace(-v,v,90));directions=np.column_stack([x.ravel(),y.ravel(),np.ones(x.size)]);directions/=np.linalg.norm(directions,axis=1)[:,None];distance,hit=cg.cast(origin,directions@R.T,tri[:,0],tri[:,1],tri[:,2]);pixels=np.isfinite(distance)&barrel[np.maximum(hit,0)];cols=np.tile(np.arange(160),90);pixel_counts=[]
for side in (cols<80,cols>=80):
    n=int((pixels&side).sum());pixel_counts.append(n);check(n>=20,'actual barrel surface visibly clears complete forward cockpit, on both sides')
check(.002<pixels.mean()<.025,'small forward barrel peek, not oversized guns in aiming view')
check(((cols[pixels]<20)|(cols[pixels]>=140)).all(),'barrel peeks confined to outer screen corners')
for sign in (-1,1):
    muzzle=np.array([sign*1.98511195,.219458,2.95545602]);direction=muzzle-origin;direction/=np.linalg.norm(direction);distance,hit=cg.cast(origin,direction[None,:],tri[:,0],tri[:,1],tri[:,2]);check(np.isfinite(distance[0]) and barrel[hit[0]],'muzzle sightline first hits barrel, not cockpit sill')
# Restore the two exact old armor faces as a negative fixture. The same screen
# rays must expose the old failure instead of passing on visible wing triangles.
old_sills=[]
for sign in (-1,1):
    p=np.array([(sign*.74,-.34,1.02),(sign*.88,-.34,-.40),(sign*.94,-.72,-.35),(sign*.78,-.72,.91)])
    if np.dot(np.cross(p[1]-p[0],p[2]-p[0]),-p.mean(0))<0:p=p[::-1]
    p=origin+p@R.T;old_sills.extend([p[[0,1,2]],p[[0,2,3]]])
bad_tri=np.concatenate([tri,np.array(old_sills)]);bad_barrel=np.concatenate([barrel,np.zeros(len(old_sills),bool)]);distance,hit=cg.cast(origin,directions@R.T,bad_tri[:,0],bad_tri[:,1],bad_tri[:,2]);old_pixels=np.isfinite(distance)&bad_barrel[np.maximum(hit,0)];check(old_pixels.sum()<pixels.sum()*.25,'old-sill negative fixture rejects barrel occlusion regression')
check(receipt['glass']['bone']=='CFL21BDA' and receipt['glass']['vertices']>0,'weather glass refit onto new window')
check(receipt['alignment']['glassPolicy']=='cabin-only','distant wing/pod surfaces do not drive weather-glass fitting')
src=cg.Sources(game=str(ROOT/'Local/no-game'),cr=str(ROOT));path,kind,_=cg.cockpit_mesh(src,'cvfigh');check(kind=='separate' and Path(path).name=='cvfigh_cockpit.mesh','separate first-person resource selected for all cvfigh ODF aliases')
spec=importlib.util.spec_from_file_location('build_cv',ROOT/'Tools/Build-CVFighterCockpit.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build);d,e,mask=build.textures()
check(np.array_equal(np.array(mask),np.array(Image.open(REF/'optical-mask.png'))),'physical optical mask reproduces')
for channel,expected in [('d',d),('e',e)]:
    p=ROOT/'Assets/Textures'/('crvcfcp_'+channel+'.dds');check(bc_dds_problem(p.read_bytes(),1024,1024) is None,'legacy BC1 / complete mip chain')
    a=np.array(Image.open(p).convert('RGB'));check(np.abs(a.astype(float)-np.array(expected).astype(float)).mean()<5,'DDS matches authored chart / emission mask')
    if channel=='e':
        for key in ('armor','frame','trim'):
            x0,y0,x1,y1=np.array(cp.CHARTS[key])*1024/1254;check(a[int(y0)+3:int(y1)-3,int(x0)+3:int(x1)-3].max()<12,'paint/structure never emit: '+key)
bad=origin+R@np.array([0,-.5,0]);distance,_=cg.cast(bad,rays(np.array([0]),0),tri[:,0],tri[:,1],tri[:,2]);check(np.isfinite(distance).all(),'misaligned-eye negative fixture is rejected by obstruction')
members={r['source'].replace('\\','/'):r['runtime'] for r in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
for relative in receipt['outputs']:check(members.get(relative)==Path(relative).name,'case-correct shipping resource: '+relative)
print('CV fighter cockpit:',count,'checks passed; visible wing/gun angular samples L/R',visible,'actual barrel forward pixels L/R',pixel_counts)
