"""Razor scout pair: offline rig, shape, closure, faction art and lookup checks."""
from pathlib import Path
import hashlib,json,sys,importlib.util,re
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
import scoutcockpits as cp
import cockpitglass as cg
from bcdds import bc_dds_problem
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/ScoutCockpits';count=0
def check(ok,message):
    global count
    assert ok,message
    count+=1
def sha(p):
    data=p.read_bytes()
    return hashlib.sha256(data.replace(b'\r\n',b'\n') if p.suffix=='.material' else data).hexdigest()
spec=importlib.util.spec_from_file_location('build_scouts',ROOT/'Tools/Build-ScoutCockpits.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
members={r['source'].replace('\\','/'):r['runtime'] for r in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']};nose_visible={};emission={};diffuse={};authored={}
for faction,cfg in cp.CONFIG.items():
    base=cfg['base'];ref=REF/faction;receipt=json.loads((ref/'build.json').read_text())
    check(sha(ref/'atlas-master.png')==receipt['masterSha256'],'master pinned: '+faction)
    for relative,digest in receipt['outputs'].items():check(sha(ROOT/relative)==digest,'compiled output pinned: '+relative)
    source=ROOT/'Assets/ModelFixes'/(base+'.mesh');check(sha(source)==receipt['sources']['exteriorSha256'],'existing exterior/fallback unchanged')
    skelpath=ROOT/'Assets/Models'/(base+'_cockpit.skeleton');check(sha(skelpath)==receipt['sources']['skeletonSha256'],'stock skeleton byte-exact')
    s,world,eye,shell=cp.shared.rig(skelpath,cfg['shell']);origin,R=world[eye.handle]
    check(np.allclose(origin,cfg['eye'],atol=1e-8) and np.allclose(R,np.eye(3)),'actual faction POV, including Black Dog forward offset')
    check(shell.name.lower()==cfg['shell'],'correct stable faction shell')
    mesh=cp.shared.read_mesh(ROOT/'Assets/Models'/(base+'_cockpit.mesh'))
    check(mesh.skeleton_name==base+'_cockpit.skeleton','namespaced skeleton selector')
    check([x.material_name for x in mesh.submesh_list]==[cfg['material'],cfg['nose'],'CRWX_CockpitGlass'],'authored interior, stock nose, weather glass only')
    opaque=[];nose_first=nose_last=0
    for sub in mesh.submesh_list:
        vd=sub.vertex_data;p=cp.shared.values(vd,cp.shared.om.VES.POSITION);n=cp.shared.values(vd,cp.shared.om.VES.NORMAL);uv=cp.shared.values(vd,cp.shared.om.VES.TEXTURE_COORDINATES);t=cp.shared.values(vd,cp.shared.om.VES.TANGENT)
        check(np.isfinite(p).all() and np.isfinite(uv).all(),'finite geometry and UVs')
        check(np.allclose(np.linalg.norm(n,axis=1),1,atol=.003),'unit normals')
        check(np.allclose(np.linalg.norm(t,axis=1),1,atol=.003),'unit tangents')
        check(np.abs((n*t).sum(1)).max()<.003,'orthogonal tangent basis')
        weights=list(sub.bone_assignments());check(len(weights)==len(p) and all(a.bone_index==shell.handle and a.weight==1 for a in weights),'every vertex skinned to stable shell')
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
    directions=np.concatenate([rays(np.arange(-35,36,1),pitch) for pitch in range(-31,0)])
    dist,hit=cg.cast(origin,directions,tri[:,0],tri[:,1],tri[:,2]);hits=np.isfinite(dist)&(hit>=nose_first)&(hit<nose_last);nose_visible[faction]=int(hits.sum());check(hits.any(),'original nose visible in actual forward FOV')
    parts,*_=cp.geometry(source,skelpath,faction);authored[faction]=parts[cfg['material']][0]
    check(np.array_equal(cp.shared.values(mesh.submesh_list[1].vertex_data,cp.shared.om.VES.TEXTURE_COORDINATES),parts[cfg['nose']][0][:,6:8]),'stock nose UVs retained')
    check(receipt['alignment']['noseTriangles']==738 and len(mesh.submesh_list[1].index_array)//3==738,'only complete original nose, not whole hull/hardpoint cubes')
    raw=cp.shared.read_mesh(source).submesh_list[0];rawp=cp.shared.values(raw.vertex_data,cp.shared.om.VES.POSITION);q=rawp[raw.index_array.reshape(-1,3)[receipt['alignment']['noseSourceIndices']]];fitted=parts[cfg['nose']][0][:,:3][parts[cfg['nose']][1].reshape(-1,3)]
    check(np.allclose(np.linalg.norm(np.roll(q,-1,axis=1)-q,axis=2),np.linalg.norm(np.roll(fitted,-1,axis=1)-fitted,axis=2),atol=1e-6),'nose shape/scale preserved')
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
check(np.allclose(authored['nsdf'][:,:3]-origins['nsdf'],authored['bdog'][:,:3]-origins['bdog'],atol=2e-7),'common Razor shell fitted independently to each faction eye')
print('Scout cockpit pair:',count,'checks passed; source-nose samples',nose_visible)
