"""Offline geometry/art/visibility contracts; no Blender or game required."""
from pathlib import Path
import hashlib,json,sys,importlib.util
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
import cvhrazcockpit as cp
import cockpitglass as cg
from bcdds import bc_dds_problem
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/CVBomberCockpit';count=0
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
source=ROOT/'Assets/ModelFixes/cvhraz.mesh';check(sha(source)==receipt['sources']['exteriorSha256'],'existing exterior / fallback unchanged')
skelpath=ROOT/'Assets/Models/cvhraz_cockpit.skeleton';check(sha(skelpath)==receipt['sources']['skeletonSha256'],'every stock bone/hardpoint retained byte-for-byte')
s,world,eye,shell=cp.shared.rig(skelpath,'CPX21BDA');origin,R=world[eye.handle]
check(eye.name=='CPX11POV' and shell.name=='CPX21BDA' and shell.handle==11,'actual POV and stable shell')
check(np.allclose(origin,[0,1.5885809659957886,1.1832480430603027],atol=1e-8) and np.allclose(R,np.eye(3)),'exact stock eye transform')
mesh=cp.shared.read_mesh(ROOT/'Assets/Models/cvhraz_cockpit.mesh')
check(mesh.skeleton_name=='cvhraz_cockpit.skeleton','namespaced skeleton selector')
check([x.material_name for x in mesh.submesh_list]==[cp.MATERIAL,cp.PODS,'CRWX_CockpitGlass'],'interior, bounded pod caps and weather glass only')
opaque=[];pods_first=pods_last=0
for sub in mesh.submesh_list:
    vd=sub.vertex_data;p=cp.shared.values(vd,cp.shared.om.VES.POSITION);n=cp.shared.values(vd,cp.shared.om.VES.NORMAL);uv=cp.shared.values(vd,cp.shared.om.VES.TEXTURE_COORDINATES);t=cp.shared.values(vd,cp.shared.om.VES.TANGENT)
    check(np.isfinite(p).all() and np.isfinite(uv).all(),'finite geometry / UVs')
    check(np.allclose(np.linalg.norm(n,axis=1),1,atol=.003),'unit normals')
    check(np.allclose(np.linalg.norm(t,axis=1),1,atol=.003),'unit tangents')
    check(np.abs((n*t).sum(1)).max()<.003,'orthogonal tangent basis')
    weights=list(sub.bone_assignments());check(len(weights)==len(p) and all(a.bone_index==11 and a.weight==1 for a in weights),'all first-person vertices follow shell 11')
    tri=p[sub.index_array.reshape(-1,3)];check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),'no degenerate triangles')
    if sub.material_name!='CRWX_CockpitGlass':
        check(uv.min()>=0 and uv.max()<=1,'opaque UV range')
        if sub.material_name==cp.PODS:pods_first=sum(len(x) for x in opaque);pods_last=pods_first+len(tri)
        opaque.append(tri)
tri=np.concatenate(opaque)
def rays(yaws,pitch):
    y=np.radians(yaws);p=np.radians(pitch)
    return np.column_stack([np.cos(p)*np.sin(y),np.full(len(y),np.sin(p)),np.cos(p)*np.cos(y)])@R.T
for pitch in (-10,0,10,20):
    distance,_=cg.cast(origin,rays(np.arange(-20,21,2),pitch),tri[:,0],tri[:,1],tri[:,2]);check(np.isinf(distance).all(),'clear broad central sight corridor')
for pitch,label in [(-70,'floor/side seams'),(85,'roof seams')]:
    distance,_=cg.cast(origin,rays(np.arange(-180,180,10),pitch),tri[:,0],tri[:,1],tri[:,2]);check(np.isfinite(distance).all(),'closed '+label)
distance,_=cg.cast(origin,rays(np.array([180]),0),tri[:,0],tri[:,1],tri[:,2]);check(np.isfinite(distance).all(),'closed rear bulkhead')
check(receipt['alignment']['innerShell']['boundaryLoops']==1,'only intentional wraparound window boundary')
visible=[]
for sign in (-1,1):
    directions=np.concatenate([rays(sign*np.arange(25,49,1),pitch) for pitch in range(-31,1)])
    dist,hit=cg.cast(origin,directions,tri[:,0],tri[:,1],tri[:,2]);hits=np.isfinite(dist)&(hit>=pods_first)&(hit<pods_last);visible.append(int(hits.sum()));check(hits.any(),'source pod cap visible at lower periphery: '+str(sign))
parts,*_=cp.geometry(source,skelpath);compiled=mesh.submesh_list[1]
authored=parts[cp.MATERIAL][0];local=(authored[:,:3]-origin)@R;uv=authored[:,6:8];top=np.isclose(local[:,1],-.88)&np.isclose(local[:,2],.80)&np.isclose(np.abs(local[:,0]),.23)&(uv[:,1]>=.36)&(uv[:,1]<=.64)
check(top.sum()==2 and np.allclose(uv[top,0],.52),'portrait keel maps the landscape chart across its short axis')
check(np.array_equal(cp.shared.values(mesh.submesh_list[0].vertex_data,cp.shared.om.VES.TEXTURE_COORDINATES),authored[:,6:8]),'authored UVs compile without reinterpretation')
check(np.array_equal(cp.shared.values(compiled.vertex_data,cp.shared.om.VES.TEXTURE_COORDINATES),parts[cp.PODS][0][:,6:8]),'source pod UVs retained')
check(receipt['alignment']['podTriangles']==586 and len(compiled.index_array)//3==586,'only selected pod caps, not full hull or hardpoint cubes')
raw=cp.shared.read_mesh(source);body=raw.submesh_list[0];p=cp.shared.values(body.vertex_data,cp.shared.om.VES.POSITION);q=p[body.index_array.reshape(-1,3)[receipt['alignment']['podSourceIndices']]]
fitted=parts[cp.PODS][0][:,:3][parts[cp.PODS][1].reshape(-1,3)]
check(np.allclose(np.linalg.norm(np.roll(q,-1,axis=1)-q,axis=2),np.linalg.norm(np.roll(fitted,-1,axis=1)-fitted,axis=2),atol=1e-6),'pod fit keeps triangle shape and scale')
old=raw.submesh_list[1];p=cp.shared.values(old.vertex_data,cp.shared.om.VES.POSITION);old_tri=p[old.index_array.reshape(-1,3)]
before=cp.view_coverage(old_tri,origin,R);after=cp.view_coverage(tri,origin,R)
check(abs(before-receipt['screenObstruction']['before'])<1e-6 and abs(after-receipt['screenObstruction']['after'])<1e-6,'same-camera coverage receipt reproduces')
check(after<before-.10,'at least ten screen-percentage-points less obstruction')
check(cp.view_coverage(old_tri,origin,R)>after,'stock-cage negative fixture rejects visibility regression')
check(receipt['glass']['bone']=='CPX21BDA' and receipt['glass']['vertices']>0,'weather glass refit')
src=cg.Sources(game=str(ROOT/'Local/no-game'),cr=str(ROOT));path,kind,_=cg.cockpit_mesh(src,'cvhraz');check(kind=='separate' and Path(path).name=='cvhraz_cockpit.mesh','separate first-person lookup selected')
spec=importlib.util.spec_from_file_location('build_cvh',ROOT/'Tools/Build-CVBomberCockpit.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build);d,e,mask=build.textures()
check(np.array_equal(np.array(mask),np.array(Image.open(REF/'optical-mask.png'))),'physical optical mask reproduces')
for channel,expected in [('d',d),('e',e)]:
    p=ROOT/'Assets/Textures'/('crvchcp_'+channel+'.dds');check(bc_dds_problem(p.read_bytes(),1024,1024) is None,'legacy BC1 / full mips')
    a=np.array(Image.open(p).convert('RGB'));check(np.abs(a.astype(float)-np.array(expected).astype(float)).mean()<5,'DDS matches atlas / physical emission mask')
    if channel=='e':
        for key in ('armor','frame','trim'):
            x0,y0,x1,y1=np.array(cp.CHARTS[key])*1024;check(a[int(y0)+3:int(y1)-3,int(x0)+3:int(x1)-3].max()<12,'structure and paint stay nonemissive: '+key)
        check(((a[:,:,1]>a[:,:,0]*1.1)&(a[:,:,1]>a[:,:,2]*1.5)&(a[:,:,1]>85)).sum()>100,'lime optical traces present')
        check(((a[:,:,0]>150)&(a[:,:,1]>80)&(a[:,:,2]<110)).sum()>100,'amber status lamps present')
bad=origin+R@np.array([0,-.7,0]);distance,_=cg.cast(bad,rays(np.array([0]),0),tri[:,0],tri[:,1],tri[:,2]);check(np.isfinite(distance).all(),'moved-eye negative fixture hits dashboard')
members={r['source'].replace('\\','/'):r['runtime'] for r in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
for relative in receipt['outputs']:check(members.get(relative)==Path(relative).name,'case-correct shipping resource: '+relative)
print('CV bomber cockpit:',count,'checks passed; pod samples L/R',visible,'screen obstruction',round(before*100,1),'->',round(after*100,1),'percent')
