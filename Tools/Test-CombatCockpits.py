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
        if base=='cvturr' or (base=='svltnk' and piece['bones']==[2]):check(np.allclose(T,np.eye(4),atol=1e-8),'gun assemblies retain actual position relative to POV')
        if base=='svltnk' and piece['bones']==[2]:
            from collections import Counter
            edges=Counter()
            def count_edges(face):
                keys=[tuple(np.rint(point*10000).astype(np.int64)) for point in face]
                for i in range(len(keys)):edges[tuple(sorted((keys[i],keys[(i+1)%len(keys)])))]+=1
            for face in data[ix.reshape(-1,3),:3]:count_edges(face)
            for cap in piece['rearCaps']:count_edges(np.array(cap)@R.T+origin)
            check(len(piece['rearCaps'])>0 and all(count==2 for count in edges.values()),'all source cannon mounting openings explicitly capped')
            hardware=m.submesh_list[0];hp=cp.shared.values(hardware.vertex_data,cp.shared.om.VES.POSITION);hn=cp.shared.values(hardware.vertex_data,cp.shared.om.VES.NORMAL)
            for cap in piece['rearCaps']:
                for point in np.array(cap)@R.T+origin:check(np.any((np.linalg.norm(hp-point,axis=1)<1e-5)&(hn[:,2]<-.99)),'rear cap emitted with outward normal')
    check(offset==len(extdata),'every exterior vertex accounted for')
    hits=[0,0];lo,hi=ranges[ext.material_name]
    for pitch in range(-31,1):
        yaw=np.arange(-45,46);dist,hit=cast(yaw,pitch);visible=(hit>=lo)&(hit<hi)&np.isfinite(dist);hits[0]+=int((visible&(yaw<0)).sum());hits[1]+=int((visible&(yaw>0)).sum())
    if base=='cvturr':
        # Native gun pods flank the pilot; do not require them to sit artificially
        # on the bottom of a forward render. Both high/low pairs must be visible
        # through side looks, with their original high/low geometry.
        side_hits=[0,0];high_low=[0,0]
        for pitch in range(-25,26):
            yaw=np.r_[np.arange(-85,-44),np.arange(45,86)];dist,hit=cast(yaw,pitch);visible=(hit>=lo)&(hit<hi)&np.isfinite(dist)
            side_hits[0]+=int((visible&(yaw<0)).sum());side_hits[1]+=int((visible&(yaw>0)).sum());high_low[int(pitch>0)]+=int(visible.sum())
        check(min(side_hits)>15 and min(high_low)>15,'both native gun pods visible above/below eye in peripheral views')
        for piece in meta['exteriorPieces']:
            mask=np.zeros(len(body.index_array)//3,bool);mask[piece['sourceIndices']]=True;weights=np.zeros(len(cp.shared.values(body.vertex_data,cp.shared.om.VES.POSITION)))
            for a in body.bone_assignments():
                if a.bone_index in piece['bones']:weights[a.vertex_index]+=a.weight
            t=cp.shared.values(body.vertex_data,cp.shared.om.VES.POSITION)[body.index_array.reshape(-1,3)];valid=(weights[body.index_array.reshape(-1,3)]>.99).all(1)&(np.linalg.norm(np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]),axis=1)>1e-9)
            check(np.array_equal(mask,valid),'whole original gun pod retained, no floating front crop')
        report['turretPeripheralVisibility']=side_hits
    else:check(sum(hits)>20,'real exterior pieces visibly connect the view '+base+' '+str(hits))
    if cfg['role']=='bomber':check(min(hits)>10,'bow visible on both sides')
    src=cg.Sources(game=str(ROOT/'Local/no-game'),cr=str(ROOT));path,kind,_=cg.cockpit_mesh(src,base);check(kind=='separate' and Path(path).name==base+'_cockpit.mesh','first-person resource lookup')
    check(len(meta['panels'])>=3,'role-specific fitted instrument banks')
    for panel in meta['panels']:
        corners=np.array(panel['points']);normal=np.cross(corners[1]-corners[0],corners[2]-corners[0]);normal/=np.linalg.norm(normal)
        check(abs((corners-corners[0])@normal).max()<1e-8,'each cassette mounting face is planar, preventing self-intersection')
        insert=np.array(panel['instrumentPoints']);u=insert[1]-insert[0];v=insert[3]-insert[0]
        check(abs(np.dot(u,v))<1e-8 and np.allclose(insert[2],insert[1]+insert[3]-insert[0]),'instrument insert is rectangular, never a skewed or tapered UV quad')
        check(abs(np.linalg.norm(u)/np.linalg.norm(v)-panel['sourceAspect'])<1e-7,'instruments preserve original pre-repack artwork proportions')
        hardware=m.submesh_list[0];hp=cp.shared.values(hardware.vertex_data,cp.shared.om.VES.POSITION);huv=cp.shared.values(hardware.vertex_data,cp.shared.om.VES.TEXTURE_COORDINATES)
        x0,y0,x1,y1=cfg['charts'][panel['chart']]
        if panel['section'] is not None:a,b=panel['section'];x0,x1=x0+(x1-x0)*a,x0+(x1-x0)*b
        for point,uv in zip(insert@R.T+origin,[(x1,y0),(x0,y0),(x0,y1),(x1,y1)]):check(np.any((np.linalg.norm(hp-point,axis=1)<1e-5)&(np.linalg.norm(huv-uv,axis=1)<1e-6)),'compiled instrument UV corner matches aspect-correct insert')
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
