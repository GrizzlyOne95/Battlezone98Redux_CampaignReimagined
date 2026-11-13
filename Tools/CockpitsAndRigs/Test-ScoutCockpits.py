"""Razor scout pair: offline rig, shape, closure, faction art and lookup checks."""
# The shipped meshes carry the weapon-rig layer (Build-WeaponRigs.py), which retargets each mesh at <name>_recoil.skeleton; skeleton selectors are compared with that suffix removed.
import sys as _sys; from pathlib import Path as _Path
_sys.path.insert(0, str(_Path(__file__).resolve().parent))
from pathlib import Path
import hashlib,json,sys,importlib.util,re
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent.parent))
import scoutcockpits as cp
import combatcockpits as combat
import cockpitglass as cg
import weaponrigs
from bcdds import bc_dds_problem
ROOT=Path(__file__).resolve().parents[2];REF=ROOT/'References/ScoutCockpits';count=0
def check(ok,message):
    global count
    assert ok,message
    count+=1
def sha(p):
    data=(p).read_bytes()
    return hashlib.sha256(data.replace(b'\r\n',b'\n') if p.suffix=='.material' else data).hexdigest()
spec=importlib.util.spec_from_file_location('build_scouts',ROOT/'Tools/CockpitsAndRigs/Build-ScoutCockpits.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
members={r['source'].replace('\\','/'):r['runtime'] for r in json.loads((ROOT/'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'))['files']};nose_visible={};emission={};diffuse={};authored={}
for faction,cfg in cp.CONFIG.items():
    base=cfg['base'];ref=REF/faction;receipt=json.loads((ref/'build.json').read_text())
    check(sha(ref/'atlas-master.png')==receipt['masterSha256'],'master pinned: '+faction)
    source=ROOT/'Assets/ModelFixes'/(base+'.mesh')
    STAGE=not weaponrigs.is_rigged(source)  # Source-reproduction checks need the pre-rig stage; they only run for units the weapon rig left untouched.
    skelpath=ROOT/'Assets/Models'/(base+'_cockpit.skeleton')
    s,world,eye,shell=cp.shared.rig(skelpath,cfg['shell']);origin,R=world[eye.handle]
    check(np.allclose(origin,cfg['eye'],atol=1e-8) and np.allclose(R,np.eye(3)),'actual faction POV, including Black Dog forward offset')
    check(shell.name.lower()==cfg['shell'],'correct stable faction shell')
    mesh=cp.shared.read_mesh((ROOT/'Assets/Models'/(base+'_cockpit.mesh')))
    check(mesh.skeleton_name.replace('_recoil.skeleton','.skeleton')==base+'_cockpit.skeleton','namespaced skeleton selector')
    check([x.material_name for x in mesh.submesh_list]==[cfg['material'],cfg['nose'],'CRWX_CockpitGlass'],'authored interior, stock nose, weather glass only')
    opaque=[];nose_first=nose_last=0
    for sub in mesh.submesh_list:
        vd=sub.vertex_data;p=cp.shared.values(vd,cp.shared.om.VES.POSITION);n=cp.shared.values(vd,cp.shared.om.VES.NORMAL);uv=cp.shared.values(vd,cp.shared.om.VES.TEXTURE_COORDINATES);t=cp.shared.values(vd,cp.shared.om.VES.TANGENT)
        check(np.isfinite(p).all() and np.isfinite(uv).all(),'finite geometry and UVs')
        check(np.allclose(np.linalg.norm(n,axis=1),1,atol=.003),'unit normals')
        check(np.allclose(np.linalg.norm(t,axis=1),1,atol=.003),'unit tangents')
        check(np.abs((n*t).sum(1)).max()<.003,'orthogonal tangent basis')
        bone=np.full(len(p),cfg['noseBone'] if sub.material_name==cfg['nose'] else shell.handle)
        weights=list(sub.bone_assignments());check(len(weights)==len(p) and all(a.bone_index==bone[a.vertex_index] and a.weight==1 for a in weights),'interior/glass/hull bulkhead on stable shell; nose whole on the moving rof bone')
        tri=p[sub.index_array.reshape(-1,3)];check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),'no degenerate triangles')
        if sub.material_name!='CRWX_CockpitGlass':
            check(uv.min()>=0 and uv.max()<=1,'opaque UV range')
            if sub.material_name==cfg['nose']:nose_first=sum(len(x) for x in opaque);nose_last=nose_first+len(tri)
            opaque.append(tri)
    tri=np.concatenate(opaque)
    def rays(yaws,pitch):
        y=np.radians(yaws);p=np.radians(pitch)
        return np.column_stack([np.cos(p)*np.sin(y),np.full(len(y),np.sin(p)),np.cos(p)*np.cos(y)])@R.T
    for pitch in (0,5,10):
        distance,_=cg.cast(origin,rays(np.arange(-10,11,2),pitch),tri[:,0],tri[:,1],tri[:,2]);check(np.isinf(distance).all(),'clear central aiming corridor')
    for pitch,label in [(-70,'floor/side seams'),(85,'roof seams')]:
        distance,_=cg.cast(origin,rays(np.arange(-180,180,10),pitch),tri[:,0],tri[:,1],tri[:,2]);check(np.isfinite(distance).all(),'closed '+label)
    distance,_=cg.cast(origin,rays(np.array([180]),0),tri[:,0],tri[:,1],tri[:,2]);check(np.isfinite(distance).all(),'closed rear')
    check(receipt['alignment']['innerShell']['boundaryLoops']==1,'only deliberate canopy opening')
    # In game the camera is the CR-raised POV (eyeoverrides), 0.35 m above the stock eye the tub is fitted to.
    import eyeoverrides;bone,pos=eyeoverrides.EYES[base];stock=__import__('weaponrigs').read_skeleton(skelpath.read_bytes()).bone(bone).position;game=origin+R@(np.array(pos)-np.array(stock))
    check(bone==eye.name and np.allclose(R.T@(game-origin),[0,.35,0],atol=1e-4),'in-game POV raised 0.35 m straight up')
    directions=np.concatenate([rays(np.arange(-35,35.5,.5),pitch) for pitch in np.arange(-31,0,.5)])
    dist,hit=cg.cast(game,directions,tri[:,0],tri[:,1],tri[:,2]);hits=np.isfinite(dist)&(hit>=nose_first)&(hit<nose_last);nose_visible[faction]=int(hits.sum());check(hits.sum()>=25,'nose crescent visible over the hull bulkhead from the in-game eye: %d samples'%hits.sum())
    local={x.material_name:(cp.shared.values(x.vertex_data,cp.shared.om.VES.POSITION)-origin)@R for x in mesh.submesh_list};cap=receipt['alignment']['noseCap'];tub=np.delete(local[cfg['material']],np.s_[cap['firstVertex']:cap['firstVertex']+cap['vertices']],0)
    check(local[cfg['nose']][:,2].min()>tub[:,2].max(),'nose entirely ahead of the built tub')
    # Open nose rear closed: the cap lies behind the nose and spans its whole rear
    # rim, and every eye ray through the cap's area stops at the cap or the tub.
    capv=local[cfg['material']][cap['firstVertex']:cap['firstVertex']+cap['vertices']];nose=local[cfg['nose']];rear=nose[nose[:,2]<nose[:,2].min()+.03]
    check(capv[:,2].max()<nose[:,2].min(),'nose cap just behind the nose')
    inside=lambda q:all((b[0]-a[0])*(q[1]-a[1])-(b[1]-a[1])*(q[0]-a[0])>=-1e-6 for a,b in zip(capv[:,:2],np.roll(capv[:,:2],-1,0)))
    # The engine rolls the nose about its bone z (all_decompiled.c:193638-193641) up to
    # cp.ROLL_DEG; the static cap must cover the rim at every roll, not just at rest.
    bone_origin,bone_basis=world[cfg['noseBone']];pivot=(bone_origin-origin)@R;axis=R.T@bone_basis[:,2]
    check(np.allclose(axis,[0,0,1],atol=1e-4),'nose rolls about the cockpit forward axis')
    rolled=[(rear-pivot)@cp.roll_matrix(axis,a).T+pivot for a in np.radians(np.linspace(-cp.ROLL_DEG,cp.ROLL_DEG,49))]
    check(cp.ROLL_DEG>=5.74 and all(inside(q) for r in rolled for q in r[:,:2]),'nose cap covers the rear rim at every roll to +-%.1f deg'%cp.ROLL_DEG)
    # The static weather glass must keep NOSE_CLEARANCE from the nose at every roll.
    subs={x.material_name:x for x in mesh.submesh_list};tris=lambda name:local[name][subs[name].index_array.reshape(-1,3)]
    gap=combat.rotor_sweep(tris(cfg['nose']),tris('CRWX_CockpitGlass'),pivot,axis,np.linspace(-cp.ROLL_DEG,cp.ROLL_DEG,13),cp.NOSE_CLEARANCE)
    check((gap>=cp.NOSE_CLEARANCE-1e-4).all(),'weather glass clears the rolling nose by %.3f m to +-%.1f deg: %d glass triangles closer'%(cp.NOSE_CLEARANCE,cp.ROLL_DEG,(gap<cp.NOSE_CLEARANCE-1e-4).sum()))
    cap_last=len(mesh.submesh_list[0].index_array)//3;cap_first=cap_last-cap['triangles'];u,v=np.meshgrid(np.linspace(.05,.95,12),np.linspace(.05,.95,12));grid=capv[:,:2].min(0)+np.column_stack([u.ravel(),v.ravel()])*(capv[:,:2].max(0)-capv[:,:2].min(0))
    # From the stock eye the tub was fitted to, and the raised in-game eye, the tub sill
    # hides most of the bulkhead. Neither eye may ever see into the open nose.
    pts=np.array([[x,y,capv[0,2]] for x,y in grid if inside((x,y))])
    for name,eyepos in (('stock',origin),('in-game',game)):
        targets=pts-R.T@(eyepos-origin);dirs=targets/np.linalg.norm(targets,axis=1)[:,None];dist,hit=cg.cast(eyepos,dirs@R.T,tri[:,0],tri[:,1],tri[:,2])
        nose_hits=((hit>=nose_first)&(hit<nose_last)).sum();cap_hits=((hit>=cap_first)&(hit<cap_last)).sum()
        check(len(targets)>40 and np.isfinite(dist).all() and nose_hits==0 and cap_hits>0,'open nose rear never visible from the %s eye: %d nose, %d/%d cap'%(name,nose_hits,cap_hits,len(targets)))
    parts,*_=cp.geometry((source),skelpath,faction);authored[faction]=parts[cfg['material']][0]
    if STAGE:
        check(np.array_equal(cp.shared.values(mesh.submesh_list[1].vertex_data,cp.shared.om.VES.TEXTURE_COORDINATES),parts[cfg['nose']][0][:,6:8]),'stock nose UVs retained')
    check(receipt['alignment']['noseTriangles']==738 and len(mesh.submesh_list[1].index_array)//3==738,'only complete original nose, not whole hull/hardpoint cubes')
    if STAGE:
        raw=cp.shared.read_mesh((source)).submesh_list[0];rawp=cp.shared.values(raw.vertex_data,cp.shared.om.VES.POSITION);q=rawp[raw.index_array.reshape(-1,3)[receipt['alignment']['noseSourceIndices']]];fitted=parts[cfg['nose']][0][:,:3][parts[cfg['nose']][1].reshape(-1,3)]
        check(np.allclose(np.linalg.norm(np.roll(q,-1,axis=1)-q,axis=2),np.linalg.norm(np.roll(fitted,-1,axis=1)-fitted,axis=2),atol=1e-6),'nose shape/scale preserved')
        check(np.allclose(np.unique(q.reshape(-1,3),axis=0),np.unique(fitted.reshape(-1,3),axis=0),atol=1e-6),'nose at native exterior position (engine-posed rof, no art fit)')
    check(receipt['glass']['bone'].lower()==cfg['shell'] and receipt['glass']['vertices']>0,'weather glass refitted')
    src=cg.Sources(game=str(ROOT/'Local/no-game'),cr=str(ROOT));path,kind,_=cg.cockpit_mesh(src,base);check(kind=='separate' and Path(path).name==base+'_cockpit.mesh','first-person resource selected')
    d,e,mask=build.textures(faction);check(np.array_equal(np.array(mask),np.array(Image.open(ref/'optical-mask.png'))),'physical source mask reproduces')
    source_mask=np.array(mask)
    for key in ('armor','frame','trim'):
        x0,y0,x1,y1=build.SOURCE_CHARTS[faction][key];check(source_mask[y0:y1,x0:x1].max()==0,'source paint/quiet chart excluded from optical mask')
    check(source_mask[350:700,650:935].max()==0,'source service-bay cables remain nonemissive')
    for channel,expected in [('d',d),('e',e)]:
        path=ROOT/'Assets/Textures'/(cfg['stem']+'_'+channel+'.dds');check(bc_dds_problem(path.read_bytes(),1024,1024) is None,'legacy BC1 / complete mip chain')
        a=np.array(Image.open(path).convert('RGB'));check(np.abs(a.astype(float)-np.array(expected).astype(float)).mean()<5,'DDS matches repacked authoring charts')
        if channel=='e':
            emission[faction]=a
            for key in ('armor','frame','trim'):
                x0,y0,x1,y1=np.array(cp.CHARTS[key])*1024;check(a[int(y0)+3:int(y1)-3,int(x0)+3:int(x1)-3].max()<12,'paint/structure never emit: '+key)
            if faction=='nsdf':check(((a[:,:,1]>95)&(a[:,:,2]>95)&(a[:,:,1]>a[:,:,0]*1.35)&(a[:,:,2]>a[:,:,0]*1.35)).sum()>100,'NSDF cyan lamps present')
            else:check(((a[:,:,0]>110)&(a[:,:,0]>a[:,:,1]*1.8)&(a[:,:,0]>a[:,:,2]*1.8)).sum()>100,'Black Dog red lamps present')
        else:diffuse[faction]=a
    bad=origin+R@np.array([0,-.65,0]);distance,_=cg.cast(bad,rays(np.array([0]),0),tri[:,0],tri[:,1],tri[:,2]);check(np.isfinite(distance).all(),'lowered-eye negative fixture hits console')
    for relative in receipt['outputs']:check(members.get(relative)==Path(relative).name,'case-correct shipping member: '+relative)
check(re.search(r'(?im)^baseName\s*=\s*"bvraz"',(ROOT/'ODF/bvfigh.odf').read_text()) is not None,'bvfigh routes to bvraz cockpit without gameplay edit')
check(not np.array_equal(emission['nsdf'],emission['bdog']),'separate faction emission maps and footprints')
check(not np.array_equal(diffuse['nsdf'],diffuse['bdog']),'separate faction paint, not a shared atlas alias')
for faction in cp.CONFIG:
    x0,y0,x1,y1=np.array(cp.CHARTS['armor'])*1024;region=diffuse[faction][int(y0)+5:int(y1)-5,int(x0)+5:int(x1)-5].mean((0,1))
    check(region[1]>region[0]*1.08 and region[2]>region[0]*1.08 if faction=='nsdf' else region.max()-region.min()<22,'stock-grounded faction structural palette: '+faction)
origins={f:np.array(c['eye']) for f,c in cp.CONFIG.items()}
check(np.allclose(authored['nsdf'][:,:2]-origins['nsdf'][:2],authored['bdog'][:,:2]-origins['bdog'][:2],atol=2e-7),'common Razor shell fitted to each faction eye (depth fitted to its nose root)')
print('Scout cockpit pair:',count,'checks passed; source-nose samples',nose_visible)
