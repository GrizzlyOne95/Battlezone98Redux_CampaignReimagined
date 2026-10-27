"""Offline contracts for the NSDF rocket cockpit; no game installation required."""
from pathlib import Path
import hashlib,json,sys,importlib.util
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
import avrcktcockpit as cp
import cockpitglass as cg
from bcdds import bc_dds_problem
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/AVRocketCockpit';count=0
def check(ok,message):
    global count
    assert ok,message
    count+=1
def sha(p):
    data=p.read_bytes()
    return hashlib.sha256(data.replace(b'\r\n',b'\n') if p.suffix=='.material' else data).hexdigest()
receipt=json.loads((REF/'build.json').read_text())
check(sha(REF/'atlas-master.png')==receipt['masterSha256'],'authored bitmap pinned')
for relative,digest in receipt['outputs'].items():check(sha(ROOT/relative)==digest,'compiled output pinned: '+relative)
check(sha(ROOT/'Assets/ModelFixes/avrckt.mesh')==receipt['sources']['exteriorSha256'],'exterior / fallback unchanged')
skelpath=ROOT/'Assets/Models/avrckt_cockpit.skeleton'
check(sha(skelpath)==receipt['sources']['skeletonSha256'],'all stock bones/hardpoints retained byte-for-byte')
s,world,eye,shell=cp.shared.rig(skelpath,'art21bda');origin,R=world[eye.handle]
check(eye.name=='art11pov' and shell.name=='art21bda' and shell.handle==11,'actual POV and stable shell')
check(np.allclose(origin,[0,2.1953830122947693,1.3317009508609772],atol=1e-8) and np.allclose(R,np.eye(3)),'exact stock eye transform')
mesh=cp.shared.read_mesh(ROOT/'Assets/Models/avrckt_cockpit.mesh')
check(mesh.skeleton_name=='avrckt_cockpit.skeleton','namespaced rig selector')
check([x.material_name for x in mesh.submesh_list]==[cp.MATERIAL,cp.FINS,'CRWX_CockpitGlass'],'only interior, bounded fins and weather glass')
opaque=[];fins_first=fins_last=0
for sub in mesh.submesh_list:
    vd=sub.vertex_data;p=cp.shared.values(vd,cp.shared.om.VES.POSITION);n=cp.shared.values(vd,cp.shared.om.VES.NORMAL);uv=cp.shared.values(vd,cp.shared.om.VES.TEXTURE_COORDINATES);t=cp.shared.values(vd,cp.shared.om.VES.TANGENT)
    check(np.isfinite(p).all() and np.isfinite(uv).all(),'finite geometry / UVs')
    check(np.allclose(np.linalg.norm(n,axis=1),1,atol=.003),'unit normals')
    check(np.allclose(np.linalg.norm(t,axis=1),1,atol=.003),'unit tangents')
    check(np.abs((n*t).sum(1)).max()<.003,'orthogonal tangent basis')
    weights=list(sub.bone_assignments())
    check(len(weights)==len(p) and all(a.bone_index==11 and a.weight==1 for a in weights),'every first-person vertex follows stable shell')
    tri=p[sub.index_array.reshape(-1,3)]
    check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),'no degenerate triangles')
    if sub.material_name!='CRWX_CockpitGlass':
        check(uv.min()>=0 and uv.max()<=1,'opaque UV range')
        if sub.material_name==cp.FINS:fins_first=sum(len(x) for x in opaque);fins_last=fins_first+len(tri)
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
check(receipt['alignment']['innerShell']['boundaryLoops']==1,'only intentional canopy boundary loop')
visible=[]
for sign in (-1,1):
    directions=np.concatenate([rays(sign*np.arange(5,48,1),pitch) for pitch in range(-31,1)])
    dist,hit=cg.cast(origin,directions,tri[:,0],tri[:,1],tri[:,2]);hits=np.isfinite(dist)&(hit>=fins_first)&(hit<fins_last)
    valid=np.flatnonzero(hits);normal=np.cross(tri[hit[valid],1]-tri[hit[valid],0],tri[hit[valid],2]-tri[hit[valid],0]);front=(normal*directions[valid]).sum(1)<0
    visible.append(int(front.sum()));check(front.any(),'front-facing source fin visible in forward FOV: '+str(sign))
parts,*_=cp.geometry(ROOT/'Assets/ModelFixes/avrckt.mesh',skelpath);compiled=mesh.submesh_list[1]
check(np.array_equal(cp.shared.values(compiled.vertex_data,cp.shared.om.VES.TEXTURE_COORDINATES),parts[cp.FINS][0][:,6:8]),'source fin UVs preserved')
check(receipt['alignment']['finTriangles']==393 and len(compiled.index_array)//3==393,'only selected lower nose/fin apron, not full hull')
# Independent source contract: retain the contiguous centre nose apron (not
# a split absolute-X translation) and keep the rigid fit's edge lengths.
raw=cp.shared.read_mesh(ROOT/'Assets/ModelFixes/avrckt.mesh').submesh_list[0];rawp=cp.shared.values(raw.vertex_data,cp.shared.om.VES.POSITION);rawtri=raw.index_array.reshape(-1,3)[receipt['alignment']['finSourceIndices']];q=rawp[rawtri]
check((q[:,:,2].min(1)>1.8).all() and (q[:,:,2].max(1)>2.9).all() and (q[:,:,1].max(1)<1.8).all(),'bounded lower front source selection')
check(receipt['alignment']['finPlacement']['outward']==0,'contiguous nose is never split or translated by X sign')
fitted=parts[cp.FINS][0][:,:3][parts[cp.FINS][1].reshape(-1,3)]
check(np.allclose(np.linalg.norm(np.roll(q,-1,axis=1)-q,axis=2),np.linalg.norm(np.roll(fitted,-1,axis=1)-fitted,axis=2),atol=1e-6),'rigid fin fit preserves shape and scale')
check(receipt['glass']['bone']=='art21bda' and receipt['glass']['vertices']>0,'weather glass refit onto new opening')
src=cg.Sources(game=str(ROOT/'Local/no-game'),cr=str(ROOT));path,kind,_=cg.cockpit_mesh(src,'avrckt')
check(kind=='separate' and Path(path).name=='avrckt_cockpit.mesh','separate first-person resource selected')
spec=importlib.util.spec_from_file_location('build_av',ROOT/'Tools/Build-AVRocketCockpit.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build);d,e,mask=build.textures()
check(np.array_equal(np.array(mask),np.array(Image.open(REF/'optical-mask.png'))),'physical optical mask reproduces')
for channel,expected in [('d',d),('e',e)]:
    p=ROOT/'Assets/Textures'/('crvarcp_'+channel+'.dds');check(bc_dds_problem(p.read_bytes(),1024,1024) is None,'legacy BC1 / complete mip chain')
    a=np.array(Image.open(p).convert('RGB'));check(np.abs(a.astype(float)-np.array(expected).astype(float)).mean()<5,'DDS matches saved bitmap / emission mask')
    if channel=='e':
        for key in ('armor','frame','trim','back'):
            x0,y0,x1,y1=np.array(cp.CHARTS[key])*1024;check(a[int(y0)+3:int(y1)-3,int(x0)+3:int(x1)-3].max()<12,'nonemitting structure: '+key)
        check(((a[:,:,1]>a[:,:,0]*1.25)&(a[:,:,2]>a[:,:,0]*1.2)&(a[:,:,1]>100)).sum()>100,'cyan instruments present')
        check(((a[:,:,0]>150)&(a[:,:,1]>80)&(a[:,:,2]<110)).sum()>100,'amber launcher lamps present')
bad=origin+R@np.array([0,-.7,0]);distance,_=cg.cast(bad,rays(np.array([0]),0),tri[:,0],tri[:,1],tri[:,2]);check(np.isfinite(distance).all(),'moved-eye negative fixture hits dashboard')
members={r['source'].replace('\\','/'):r['runtime'] for r in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
for relative in receipt['outputs']:check(members.get(relative)==Path(relative).name,'case-correct shipping resource: '+relative)
print('AV rocket cockpit:',count,'checks passed; front-facing fin samples L/R',visible)
