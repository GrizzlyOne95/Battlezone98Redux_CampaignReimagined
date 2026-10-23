"""Offline five-cockpit geometry, rig, atlas and first-person lookup contracts."""
from pathlib import Path
import hashlib,importlib.util,json,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
import combatcockpits as cp
import cockpitglass as cg
from bcdds import bc_dds_problem
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/CombatCockpits';checks=0
def check(ok,message):
    global checks
    assert ok,message
    checks+=1
def sha(p):
    b=p.read_bytes();return hashlib.sha256(b.replace(b'\r\n',b'\n') if p.suffix=='.material' else b).hexdigest()
spec=importlib.util.spec_from_file_location('build_combat',ROOT/'Tools/Build-CombatCockpits.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
members={x['source'].replace('\\','/'):x['runtime'] for x in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
eyes={'cvturr':[0,3.620931014418602,1.0216540098190308],'svfigh':[0,1.492648959159851,.9383049756288528],'svltnk':[.002672000089660287,2.4873430132865906,-.7983300685882568],'avhraz':[.0007450000266544521,2.3997009992599487,2.301424026489258],'bvhraz':[.0007450000266544521,2.3997009992599487,2.301424026489258]};report={}
for base,cfg in cp.CONFIG.items():
    receipt=json.loads((REF/base/'build.json').read_text());meta=receipt['alignment'];source=ROOT/'Assets/ModelFixes'/(base+'.mesh');skel=ROOT/'Assets/Models'/(base+'_cockpit.skeleton')
    check(sha(source)==receipt['sources']['exteriorSha256'],'exterior/fallback byte-exact')
    check(sha(skel)==receipt['sources']['skeletonSha256'],'stock rig byte-exact')
    for relative,digest in receipt['outputs'].items():
        check(sha(ROOT/relative)==digest,'pinned compiled resource '+relative)
        check(members.get(relative)==Path(relative).name,'shipping member '+relative)
    s,w,eye,shell=cp.shared.rig(skel,cfg['shell']);origin,R=w[eye.handle]
    check(np.allclose(origin,eyes[base],atol=1e-8),'exact actual eye position')
    check(np.allclose(R,np.eye(3),atol=2e-5) and np.allclose(meta['povBasis'],R),'native/rest camera fixture')
    check(shell.handle==meta['shellHandle'] and shell.name==meta['shell'],'correct stable shell')
    m=cp.shared.read_mesh(ROOT/'Assets/Models'/(base+'_cockpit.mesh'));check(m.skeleton_name==base+'_cockpit.skeleton','separate namespaced rig')
    check([sub.material_name for sub in m.submesh_list]==[cfg['material'],cfg['stock'],'CRV/'+base+'CombatExterior','CRWX_CockpitGlass'],'four deliberate batches including glass')
    opaque=[];ranges={};cursor=0
    for sub in m.submesh_list:
        vd=sub.vertex_data;p=cp.shared.values(vd,cp.shared.om.VES.POSITION);n=cp.shared.values(vd,cp.shared.om.VES.NORMAL);uv=cp.shared.values(vd,cp.shared.om.VES.TEXTURE_COORDINATES);t=cp.shared.values(vd,cp.shared.om.VES.TANGENT)
        check(np.isfinite(np.column_stack([p,n,uv,t])).all(),'finite vertex data')
        check(np.allclose(np.linalg.norm(n,axis=1),1,atol=.003),'unit normals')
        check(np.allclose(np.linalg.norm(t,axis=1),1,atol=.003) and abs((n*t).sum(1)).max()<.003,'orthonormal tangent basis')
        weights=list(sub.bone_assignments());check(len(weights)==len(p) and all(a.bone_index==shell.handle and a.weight==1 for a in weights),'single stable-shell skinning')
        tri=p[sub.index_array.reshape(-1,3)];check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),'nondegenerate triangles '+base+' / '+sub.material_name)
        if sub.material_name!='CRWX_CockpitGlass':
            ranges[sub.material_name]=(cursor,cursor+len(tri));cursor+=len(tri);opaque.append(tri)
            if sub.material_name==cfg['material']:check(uv.min()>=0 and uv.max()<=1,'authored atlas UV bounds')
    tri=np.concatenate(opaque)
    def cast(yaws,pitch):
        y=np.radians(yaws);p=np.radians(pitch);d=np.column_stack([np.cos(p)*np.sin(y),np.full(len(y),np.sin(p)),np.cos(p)*np.cos(y)])@R.T
        return cg.cast(origin,d,tri[:,0],tri[:,1],tri[:,2])
    for pitch in (0,5,10):check(np.isinf(cast(np.arange(-10,11,2),pitch)[0]).all(),'unobstructed aim corridor')
    for pitch,label in [(-80,'floor'),(85,'roof')]:check(np.isfinite(cast(np.arange(-180,180,10),pitch)[0]).all(),'closed '+label)
    check(np.isfinite(cast([180],0)[0]).all(),'closed rear')
    check(meta['innerShell']['boundaryLoops']==1,'only one intentional inner-shell opening')
    check(receipt['glass']['vertices']>0 and receipt['glass']['bone'].lower()==cfg['shell'].lower(),'weather glass refitted')
    # Reconstruct selected native pieces from the immutable source, proving
    # actual vehicle identity, original UVs, rigid scale and transformed normals.
    body=cp.shared.read_mesh(source).submesh_list[0];ext=m.submesh_list[2];extdata=np.column_stack([cp.shared.values(ext.vertex_data,sem) for sem in (cp.shared.om.VES.POSITION,cp.shared.om.VES.NORMAL,cp.shared.om.VES.TEXTURE_COORDINATES,cp.shared.om.VES.TANGENT)]);offset=0
    for piece in meta['exteriorPieces']:
        mask=np.zeros(len(body.index_array)//3,bool);mask[piece['sourceIndices']]=True;raw,ix,_=cp.tank.source_part(body,mask);T=np.array(piece['transform']);data=extdata[offset:offset+len(raw)];offset+=len(raw)
        check(np.allclose(T[:3,:3].T@T[:3,:3],np.eye(3),atol=1e-7) and abs(np.linalg.det(T[:3,:3])-1)<1e-7,'no scale/shear/mirroring of exterior piece')
        check(np.allclose(data[:,:3],raw[:,:3]@T[:3,:3].T+T[:3,3],atol=1e-6),'actual vehicle surface positions, rigid fit only')
        check(np.array_equal(data[:,6:8],raw[:,6:8]),'original exterior UVs')
        check(np.allclose(data[:,3:6],raw[:,3:6]@T[:3,:3].T,atol=1e-6),'normals follow piece rotation')
        check(0<len(ix)//3<3000,'bounded exterior group, not whole exterior')
    check(offset==len(extdata),'every exterior vertex accounted for')
    hits=[0,0];lo,hi=ranges[ext.material_name]
    for pitch in range(-31,1):
        yaw=np.arange(-45,46);dist,hit=cast(yaw,pitch);visible=(hit>=lo)&(hit<hi)&np.isfinite(dist);hits[0]+=int((visible&(yaw<0)).sum());hits[1]+=int((visible&(yaw>0)).sum())
    check(sum(hits)>20,'real exterior pieces visibly connect the view '+base+' '+str(hits))
    if base=='cvturr':check(min(hits)>15,'both original gun pods visible')
    if cfg['role']=='bomber':check(min(hits)>10,'bow visible on both sides')
    src=cg.Sources(game=str(ROOT/'Local/no-game'),cr=str(ROOT));path,kind,_=cg.cockpit_mesh(src,base);check(kind=='separate' and Path(path).name==base+'_cockpit.mesh','first-person resource lookup')
    check(len(meta['panels'])>=3,'role-specific fitted instrument banks')
    for panel in meta['panels']:
        corners=np.array(panel['points']);normal=np.cross(corners[1]-corners[0],corners[2]-corners[0]);normal/=np.linalg.norm(normal)
        check(abs((corners-corners[0])@normal).max()<1e-8,'each cassette mounting face is planar, preventing self-intersection')
    report[base]=dict(opaqueTriangles=len(tri),exteriorVisibility=hits,materials=len(m.submesh_list))

receipt=json.loads((REF/'cca/build.json').read_text());check(sha(REF/'cca/atlas-master.png')==receipt['masterSha256'],'CCA master pin')
for relative,digest in receipt['outputs'].items():
    check(sha(ROOT/relative)==digest,'CCA compiled resource pin');check(members.get(relative)==Path(relative).name,'CCA shipping member')
d,e,mask=build.textures();check(np.array_equal(np.array(mask),np.array(Image.open(REF/'cca/optical-mask.png'))),'physical lens mask reproduces')
check(np.count_nonzero(mask)>500,'meaningful optical mask coverage')
for channel,expected in [('d',d),('e',e)]:
    path=ROOT/'Assets/Textures'/('crvsmcp_'+channel+'.dds');check(bc_dds_problem(path.read_bytes(),1024,1024) is None,'BC1 / full mip chain');a=np.array(Image.open(path).convert('RGB'));check(np.abs(a.astype(float)-np.array(expected)).mean()<5,'DDS matches chart repack')
    if channel=='e':
        for key in ('armor','frame','trim'):
            x0,y0,x1,y1=[round(v*1024) for v in cp.CCA_CHARTS[key]];check(a[y0+3:y1-3,x0+3:x1-3].max()<12,'paint/structure not emissive')
        check(((a[:,:,0]>150)&(a[:,:,1]>65)&(a[:,:,1]<a[:,:,0]*.85)).sum()>500,'orange CCA optics')
source_mask=np.array(mask);check(source_mask[340:830,620:920].max()==0,'red service cables never emit');check(source_mask[840:].max()==0,'quiet source swatches never emit')
check(cp.CONFIG['avhraz']['charts']==cp.CONFIG['bvhraz']['charts'] and cp.CONFIG['avhraz']['material']!=cp.CONFIG['bvhraz']['material'],'bomber siblings share design, not faction materials')
print('COMBAT_COCKPITS_PASS',checks,json.dumps(report))
