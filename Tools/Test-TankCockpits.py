"""Offline tank cockpit contracts; no retail game installation required."""
from pathlib import Path
import hashlib,json,sys
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
import tankcockpits as cp
import cockpitglass as cg
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/TankCockpits';checks=0
def check(ok,message):
    global checks
    assert ok,message
    checks+=1
def sha(p):
    b=p.read_bytes();return hashlib.sha256(b.replace(b'\r\n',b'\n') if p.suffix=='.material' else b).hexdigest()
members={x['source'].replace('\\','/'):x['runtime'] for x in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
eyes={'nsdf':[0,1.4254159927368164,1.229254961013794],'bdog':[0,.6254140138626099,1.2293000221252441],'cca':[-.27610001154243946,1.9194999933242798,.3680000305175781],'cra':[0,1.7300000190734863,3.5074000358581543]}
report={}
for faction,cfg in cp.CONFIG.items():
    base=cfg['base'];receipt=json.loads((REF/faction/'build.json').read_text());meta=receipt['alignment'];source=ROOT/'Assets/ModelFixes'/(base+'.mesh');skel=ROOT/'Assets/Models'/(base+'_cockpit.skeleton')
    for relative,digest in receipt['outputs'].items():
        check(sha(ROOT/relative)==digest,'pinned output '+relative)
        check(members.get(relative)==Path(relative).name,'shipping member '+relative)
    check(sha(source)==receipt['sources']['exteriorSha256'],'exterior/fallback unchanged')
    check(sha(skel)==receipt['sources']['skeletonSha256'],'stock skeleton bytes retained')
    s,w,eye,shell=cp.shared.rig(skel,cfg['shell']);origin,bindR=w[eye.handle];R=np.array(meta['povBasis'])
    check(np.allclose(origin,eyes[faction],atol=1e-8),'exact individual eye position')
    check(np.allclose(R,np.eye(3),atol=2e-5),'native VDF rest POV basis')
    if faction=='cca':check(not np.allclose(bindR,R),'CCA native versus bind orientation fixture is meaningful')
    mesh=cp.shared.read_mesh(ROOT/'Assets/Models'/(base+'_cockpit.mesh'));check(mesh.skeleton_name==base+'_cockpit.skeleton','namespaced rig reference')
    check(len(mesh.submesh_list)==5,'bounded material batch count')
    opaque=[];ranges={};cursor=0
    for sub in mesh.submesh_list:
        vd=sub.vertex_data;p=cp.shared.values(vd,cp.shared.om.VES.POSITION);n=cp.shared.values(vd,cp.shared.om.VES.NORMAL);uv=cp.shared.values(vd,cp.shared.om.VES.TEXTURE_COORDINATES);t=cp.shared.values(vd,cp.shared.om.VES.TANGENT)
        check(np.isfinite(np.column_stack([p,n,uv,t])).all(),'finite vertex data')
        check(np.allclose(np.linalg.norm(n,axis=1),1,atol=.003),'unit normals')
        check(np.allclose(np.linalg.norm(t,axis=1),1,atol=.003),'unit tangents')
        check(abs((n*t).sum(1)).max()<.003,'orthogonal tangent basis')
        tri=p[sub.index_array.reshape(-1,3)];check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),'nondegenerate triangles')
        weights=list(sub.bone_assignments());check(len(weights)==len(p) and all(a.weight==1 for a in weights),'one normalized skin weight per vertex')
        if sub.material_name.endswith('TankGuns'):
            check({a.bone_index for a in weights}==set(cfg['gun']),'retain original gun bones, not frozen to shell')
            triples=[(a.vertex_index,a.bone_index,a.weight) for a in weights]
            check(hashlib.sha256(json.dumps(triples,separators=(',',':')).encode()).hexdigest()==meta['gunWeightSha256'],'source gun skin weights pinned')
        else:check(all(a.bone_index==shell.handle for a in weights),'stable cockpit shell weights')
        if sub.material_name!='CRWX_CockpitGlass':ranges[sub.material_name]=(cursor,cursor+len(tri));cursor+=len(tri);opaque.append(tri)
    tri=np.concatenate(opaque)
    def cast(yaws,pitch):
        y=np.radians(yaws);p=np.radians(pitch);dirs=np.column_stack([np.cos(p)*np.sin(y),np.full(len(y),np.sin(p)),np.cos(p)*np.cos(y)])@R.T
        return cg.cast(origin,dirs,tri[:,0],tri[:,1],tri[:,2])
    for pitch in (0,5,10):check(np.isinf(cast(np.arange(-10,11,2),pitch)[0]).all(),'clear aiming corridor')
    for pitch,label in [(-80,'floor'),(85,'roof')]:check(np.isfinite(cast(np.arange(-180,180,10),pitch)[0]).all(),'closed '+label)
    check(np.isfinite(cast([180],0)[0]).all(),'closed rear bulkhead')
    check(meta['innerShell']['boundaryLoops']==1,'one connected intentional window boundary')
    check(receipt['glass']['bone'].lower()==cfg['shell'].lower() and receipt['glass']['vertices']>0,'refitted weather glass')
    src=cg.Sources(game=str(ROOT/'Local/no-game'),cr=str(ROOT));path,kind,_=cg.cockpit_mesh(src,base);check(kind=='separate' and Path(path).name==base+'_cockpit.mesh','separate first-person resource discovery')
    raw=cp.shared.read_mesh(source)
    if faction!='cca':
        stock=raw.submesh_list[cfg['batch']];new=mesh.submesh_list[0]
        for sem in (cp.shared.om.VES.POSITION,cp.shared.om.VES.TEXTURE_COORDINATES):check(np.array_equal(cp.shared.values(stock.vertex_data,sem),cp.shared.values(new.vertex_data,sem)),'stock layout and UV identity')
        check(np.array_equal(stock.index_array,new.index_array),'stock shell triangles retained exactly')
    gunsub=next(x for x in mesh.submesh_list if x.material_name.endswith('TankGuns'));body=raw.submesh_list[cfg['body']];weights=np.zeros(body.vertex_data.vertex_count)
    for a in body.bone_assignments():
        if a.bone_index in cfg['gun']:weights[a.vertex_index]+=a.weight
    mask=(weights[body.index_array.reshape(-1,3)]>.99).all(1);d,i,used=cp.source_part(body,mask);fitted=cp.shared.values(gunsub.vertex_data,cp.shared.om.VES.POSITION)
    remap={int(old):i for i,old in enumerate(used)};original=[(remap[a.vertex_index],a.bone_index,a.weight) for a in body.bone_assignments() if a.vertex_index in remap]
    check(hashlib.sha256(json.dumps(original,separators=(',',':')).encode()).hexdigest()==meta['gunWeightSha256'],'individual original gun skin weights retained')
    check(np.allclose(fitted,d[:,:3]+R@np.array(meta['gunOffset']),atol=1e-6),'complete original barrel geometry, rigid fit only')
    check(np.array_equal(cp.shared.values(gunsub.vertex_data,cp.shared.om.VES.TEXTURE_COORDINATES),d[:,6:8]),'original barrel UVs')
    hull=next(x for x in mesh.submesh_list if x.material_name.endswith('TankHull'));mask=np.zeros(len(body.index_array)//3,bool);mask[meta['apronSourceIndices']]=True;d,i,_=cp.source_part(body,mask)
    check(np.allclose(cp.shared.values(hull.vertex_data,cp.shared.om.VES.POSITION),d[:,:3]+R@np.array(meta['apronOffset']),atol=1e-6),'bounded original hull geometry, rigid fit only')
    check(0<len(i)//3<100,'not a whole exterior merge')
    gunhits=0;lo,hi=ranges[gunsub.material_name]
    for pitch in np.arange(-31,32,1):
        dist,hit=cast(np.arange(-45,46,1),pitch);gunhits+=int(((hit>=lo)&(hit<hi)&np.isfinite(dist)).sum())
    if faction=='cra':check(0<gunhits<120,'CRA barrel barely peeks into the upper view')
    report[faction]=dict(opaqueTriangles=len(tri),gunScreenSamples=gunhits,materials=len(mesh.submesh_list))
print('TANK_COCKPITS_PASS',checks,json.dumps(report))
