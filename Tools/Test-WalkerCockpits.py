"""Offline walker art contracts; does not qualify native arm visibility/animation."""
from pathlib import Path
import hashlib,json,sys
import numpy as np
import walkercockpits as cp
import walkerpose
import cockpitglass as cg

ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/WalkerCockpits';checks=0
members={x['source'].replace('\\','/'):x['runtime'] for x in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}

def check(ok,label):
    global checks
    assert ok,label
    checks+=1

def sha(path):
    b=path.read_bytes();return hashlib.sha256(b.replace(b'\r\n',b'\n') if path.suffix=='.material' else b).hexdigest()

def data(sub):
    return np.column_stack([cp.shared.values(sub.vertex_data,sem) for sem in (cp.shared.om.VES.POSITION,cp.shared.om.VES.NORMAL,cp.shared.om.VES.TEXTURE_COORDINATES,cp.shared.om.VES.TANGENT)])

def weights(sub):
    return [(a.vertex_index,a.bone_index,a.weight) for a in sub.bone_assignments()]

report={}
for base,cfg in cp.CONFIG.items():
    receipt=json.loads((REF/base/'build.json').read_text());meta=receipt['alignment'];rig=REF/base/'source-rig.skeleton'
    check(sha(rig)==receipt['sources']['cockpitRigSha256'],'byte-exact original cockpit rig fixture')
    check(sha(REF/base/'source-arms.npz')==receipt['sources']['armFixtureSha256'],'immutable pre-fit arm fixture')
    for path,digest in receipt['outputs'].items():
        check(sha(ROOT/path)==digest,'compiled resource hash '+path)
        check(members.get(path)==Path(path).name,'case-correct shipping member '+path)
    skeleton,world,eye,shell=cp.shared.rig(rig,cfg['shell']);origin=np.array(meta['povPosition']);R=np.array(meta['povBasis'])
    check(eye.name=='AGe11POV' and eye.handle==11 and eye.parent is None,'actual waist-height POV bone')
    check(np.allclose(origin,[.06509999930858612,9.199999809265137,-.2865999937057495],atol=1e-9),'unchanged actual eye position')
    check(np.allclose(R,np.eye(3),atol=1e-9),'native rest eye orientation, not bind approximation')
    check(len(list(skeleton.bones()))==26 and shell.handle==12 and shell.parent is None,'preserved 26-bone rig and independent shell')
    check(np.allclose(walkerpose.world(skeleton,meta['nativeBoneRotations'])[eye.handle][:3,:3],R),'native camera rotation agrees with pose utility')
    animations=list(skeleton.animations());check(len(animations)==1 and animations[0].name=='Take_001','original animation record retained')
    mesh=cp.shared.read_mesh(ROOT/'Assets/ModelFixes'/(base+'_c.mesh'))
    check(mesh.skeleton_name==base+'_c.skeleton','native fixed-table rig resource name')
    check([sub.material_name for sub in mesh.submesh_list]==[cfg['material'],'CRWX_CockpitGlass','CRV/'+base+'GunArms','CRV/'+base+'JointBacks'],'only deliberate interior, glass, source arms and socket backs')
    posed=[];tags=[]
    for sub in mesh.submesh_list:
        d=data(sub);p,n,uv,t=d[:,:3],d[:,3:6],d[:,6:8],d[:,8:11]
        check(np.isfinite(d).all(),'finite vertices')
        check(np.allclose(np.linalg.norm(n,axis=1),1,atol=.003),'unit normals')
        check(np.allclose(np.linalg.norm(t,axis=1),1,atol=.003) and abs((n*t).sum(1)).max()<.003,'orthonormal tangents')
        tri=p[sub.index_array.reshape(-1,3)];check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),'nondegenerate triangles')
        check(len(weights(sub))==len(p) and all(w==1 for i,b,w in weights(sub)),'one complete rigid driver per vertex')
        if not sub.material_name.endswith(('GunArms','JointBacks')):
            check(all(b==shell.handle for i,b,w in weights(sub)),'interior and weather glass follow stable shell')
        if sub.material_name==cfg['material']:check(uv.min()>=0 and uv.max()<=1,'authored atlas allocations stay inside sheet')
        pp,nn=walkerpose.deformed(sub,skeleton,meta['nativeBoneRotations'])
        plus,_=walkerpose.deformed(sub,skeleton,meta['nativeBoneRotations'],12);minus,_=walkerpose.deformed(sub,skeleton,meta['nativeBoneRotations'],-12)
        if sub.material_name.endswith('GunArms'):
            check(np.linalg.norm(plus-minus,axis=1).max()>.5,'forearms retain articulated joint drivers')
        else:check(np.array_equal(plus,minus),'forearm pitch does not move interior, glass or upper socket backs')
        if not sub.material_name.startswith('CRWX'):
            tris=pp[sub.index_array.reshape(-1,3)];posed.extend(tris);tags.extend([sub.material_name]*len(tris))
    arms=mesh.submesh_list[2];actual=data(arms);assign=weights(arms);fixture=np.load(REF/base/'source-arms.npz');source=fixture['data'];expected=source.copy()
    check(np.array_equal(np.array(assign),fixture['weights']),'source bone weights remapped by name, not rebound to shell')
    check(meta['armBones']=={name:skeleton.get_bone_by_name(name).handle for name in cp.ARM_NAMES},'correct separate shoulder/forearm handles')
    check(set(b for i,b,w in assign)=={2,3,5,6},'all four independent arm drivers retained')
    for b in meta['armBones'].values():
        ids=[i for i,handle,w in assign if handle==b];T=np.array(meta['armTransforms'][str(b)]);expected[ids,:3]=source[ids,:3]@T[:3,:3].T+T[:3,3]
        for channel in (slice(3,6),slice(8,11)):expected[ids,channel]=source[ids,channel]@T[:3,:3].T
        check(np.allclose(T[:3,:3].T@T[:3,:3],np.eye(3),atol=1e-7) and abs(np.linalg.det(T[:3,:3])-1)<1e-7,'rigid source shape fit, no scale or shear')
    check(np.allclose(actual,expected,atol=2e-6) and np.array_equal(actual[:,6:8],source[:,6:8]),'documented rigid fits only, exact source UVs')
    check(np.array_equal(arms.index_array,fixture['indices']) and len(arms.index_array)//3==2824,'complete source arm triangles, no marker cubes or whole body merge')
    check(meta['armFit']==cp.ARM_FIT and meta['armFit']['mode']=='native-firing-ray','native firing-ray constrained forward peek, not lateral gun drift')
    native_p,_=walkerpose.deformed(arms,skeleton,meta['nativeBoneRotations'])
    absolute={};mirror=np.diag([-1.,1.,1.])
    for part in meta['nativeFiringParts']:
        local=cp.legacy_port._local_matrix(part['matrix']);absolute[part['name']]=cp.legacy_port._mul(absolute[part['parent']],local) if part['parent'] in absolute else local
    for ray in meta['firingRays']:
        handle=meta['armBones'][ray['forearm']];ids={i for i,b,w in assign if b==handle};faces=arms.index_array.reshape(-1,3);faces=faces[np.array([all(int(v) in ids for v in face) for face in faces])]
        bore=next(poly for poly in cp.boundary_loops(native_p[faces]) if len(poly)==16);center=bore.mean(0);axis=np.array(ray['direction']);origin_hp=np.array(ray['origin']);delta=center-origin_hp
        check(np.linalg.norm(np.cross(delta,axis))<2e-5,'compiled main bore center lies on unchanged native projectile ray')
        check(abs(np.dot(delta,axis)-meta['armFit']['muzzleDistance'])<2e-5,'axial viewmodel placement recorded')
        _,_,axes=np.linalg.svd(bore-center);check(abs(np.dot(axes[-1],axis))>1-1e-6,'compiled bore axis matches native firing direction')
        native_hp=np.array(absolute[ray['hardpoint']]);check(np.allclose(origin_hp,mirror@native_hp[:3,3],atol=1e-9),'native projectile origin from complete VDF parent chain, not Ogre bind position')
        check(np.allclose(axis,mirror@native_hp[:3,2],atol=1e-6),'native shot direction from complete VDF chain')
        # The source is offscreen; a projectile travelling along this rest ray
        # enters the forward frustum AFTER the visible model's muzzle plane.
        local_origin=(origin_hp-origin)@R;local_axis=axis@R;side=np.sign(local_origin[0]);edge=np.tan(np.radians(32))*16/9
        entry=(side*local_origin[0]-edge*local_origin[2])/(edge*local_axis[2]-side*local_axis[0])
        check(entry>meta['armFit']['muzzleDistance'],'forward projectile path first becomes visible beyond the muzzle, not alongside housing')
    check(hashlib.sha256(json.dumps(assign,separators=(',',':')).encode()).hexdigest()==meta['armWeightsSha256'],'compiled source-arm skinning receipt')
    caps=mesh.submesh_list[3];check(len(caps.index_array)//3==20 and {b for i,b,w in weights(caps)}=={2,5},'tiny upper socket backs, not capped weapon muzzles')
    check(hashlib.sha256(json.dumps(weights(caps),separators=(',',':')).encode()).hexdigest()==meta['capWeightsSha256'],'socket-back skinning receipt')
    check(len(meta['jointBacks'])==2 and all(len(x['points'])==12 for x in meta['jointBacks']),'only two known source socket openings backed')
    check(meta['innerShell']['boundaryLoops']==1,'single intended canopy opening')
    check(receipt['glass']['bone']==shell.name and receipt['glass']['vertices']>0,'glass fitted to stable interior, not distant moving arms')
    tris=np.array(posed);tags=np.array(tags)
    def cast(yaw,pitch):
        y,p=np.radians(yaw),np.radians(pitch);d=np.column_stack([np.cos(p)*np.sin(y),np.sin(p),np.cos(p)*np.cos(y)])@R.T
        return cg.cast(origin,d,tris[:,0],tris[:,1],tris[:,2])[0]
    for pitch,label in [(-80,'floor'),(85,'roof'),(0,'rear')]:
        yaw=np.arange(-180,180,10) if label!='rear' else np.array([180]);check(np.isfinite(cast(yaw,np.full(len(yaw),pitch))).all(),'one-sided closed '+label)
    yaw,pitch=np.meshgrid(np.arange(-10,11,2),np.arange(0,11,2));check(np.isinf(cast(yaw.ravel(),pitch.ravel())).all(),'clear central aim corridor')
    xx,yy=np.meshgrid(np.linspace(-np.tan(np.radians(32))*16/9,np.tan(np.radians(32))*16/9,320),np.linspace(-np.tan(np.radians(32)),np.tan(np.radians(32)),180))
    rays=np.column_stack([xx.ravel(),yy.ravel(),np.ones(xx.size)]);rays/=np.linalg.norm(rays,axis=1)[:,None]
    distance,hit=cg.cast(origin,rays@R.T,tris[:,0],tris[:,1],tris[:,2]);gun=np.isfinite(distance)&np.char.endswith(tags[np.maximum(hit,0)],'GunArms');xs=np.tile(np.arange(320),180)[gun]
    check(.003<float(gun.mean())<.025,'cannons just barely visible forward, not filling screen')
    check((xs<160).any() and (xs>=160).any(),'both forward cannon edges visible')
    check(((xs<32)|(xs>=288)).all(),'forward cannon slivers confined to outer ten percent on each side')
    hp=data(mesh.submesh_list[0])[:,:3];huv=data(mesh.submesh_list[0])[:,6:8]
    for panel in meta['panels']:
        p=np.array(panel['instrumentPoints']);u=p[1]-p[0];v=p[3]-p[0]
        check(abs(np.dot(u,v))<1e-8 and np.allclose(p[2],p[1]+p[3]-p[0]),'rectangular inserts, no sheared dials')
        check(abs(np.linalg.norm(u)/np.linalg.norm(v)-panel['sourceAspect'])<1e-7,'artwork proportions retained')
        x0,y0,x1,y1=cp.scout.CHARTS[panel['chart']]
        if panel['section'] is not None:
            a,b=panel['section'];x0,x1=x0+(x1-x0)*a,x0+(x1-x0)*b
        for point,uv in zip(p@R.T+origin,[(x1,y0),(x0,y0),(x0,y1),(x1,y1)]):check(np.any((np.linalg.norm(hp-point,axis=1)<1e-5)&(np.linalg.norm(huv-uv,axis=1)<1e-6)),'compiled instrument UV corner')
    sources=cg.Sources(game=str(ROOT/'Local/no-game'),cr=str(ROOT));path,kind,_=cg.cockpit_mesh(sources,base)
    check(kind=='table' and Path(path).name==base+'_c.mesh','engine fixed-table resource takes priority')
    report[base]=dict(forwardCannonFraction=float(gun.mean()),cannonPixels=int(gun.sum()),sample=[320,180],verticalFov=64,sourceArmTriangles=2824,opaqueTriangles=len(tris))
if '--report' in sys.argv:
    Path(sys.argv[sys.argv.index('--report')+1]).write_text(json.dumps(report,indent=2)+'\n',newline='\n')
print('WALKER_COCKPITS_PASS',checks,json.dumps(report))
