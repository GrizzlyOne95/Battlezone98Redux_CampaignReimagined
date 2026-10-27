"""Stock-layout tank cockpit detailing, using shared codecs and existing atlases."""
from collections import Counter
import io, math
import numpy as np
import reddevilcockpit as shared
import scoutcockpits, cvhrazcockpit
from bzmodellibs import legacy, legacy_port

CONFIG={
 'nsdf':dict(base='avtank',shell='agr21bda',batch=2,body=0,bodyBone=2,gun=[18],material='CRV/NSDFScoutCockpit',stock='avtank01',exterior='avtank00',charts=scoutcockpits.CHARTS,width=.98,lip=-.49,front=.91,roof=.62,cut=2.02),
 'bdog':dict(base='bvtank',shell='bgr21bda',batch=0,body=1,bodyBone=2,gun=[1],material='CRV/BDogScoutCockpit',stock='bvtank01',exterior='bvtank00',charts=scoutcockpits.CHARTS,width=.98,lip=-.35,front=.80,roof=.85,cut=2.02),
 'cca':dict(base='svtank',shell='scz21bda',batch=2,body=0,bodyBone=1,gun=[18,19],material='svtank01',stock='svtank01',exterior='svtank00',charts={'console':(.370,.158,.553,.297),'switch':(.207,.006,.350,.298),'service':(.770,.008,.986,.190),'armor':(.635,.06,.739,.23),'frame':(.635,.06,.739,.23),'trim':(.745,.35,.757,.56)},width=.76,lip=-.44,front=1.10,roof=.62,cut=3.9),
 'cra':dict(base='cvtnk',shell='CYE21BDA',batch=1,body=0,bodyBone=0,gun=[11],material='CRV/CVBomberCockpit',stock='cvtnk01',exterior='cvtnk',charts={**cvhrazcockpit.CHARTS,'switch':cvhrazcockpit.CHARTS['pilot'],'service':cvhrazcockpit.CHARTS['ordnance']},width=.34,lip=-.43,front=.69,roof=.30,cut=4.39)}

def native_eye(world,eye,game,base,root):
    """Native local GEO rotation is authoritative; bind translations stay intact."""
    source=legacy_port.AssetSource(folders=[root/'Assets/ModelFixes',root/'Assets/Models'],archives=[game/'bzone.zfs',game/'tro_cam.zfs'])
    raw=source(base+'.vdf');assert raw,'native POV reference required'
    record=next(p for p in legacy.read_vdf(raw).parts if p.name==eye.name)
    mirror=np.diag([-1.,1.,1.]);local=mirror@np.array(record.matrix[:9]).reshape(3,3).T@mirror
    parent_r=world[eye.parent.handle][1] if eye.parent is not None else np.eye(3)
    world[eye.handle]=(world[eye.handle][0],parent_r@local)
    return raw

def source_part(sub,mask=None):
    vd=sub.vertex_data;p=shared.values(vd,shared.om.VES.POSITION);n=shared.values(vd,shared.om.VES.NORMAL);uv=shared.values(vd,shared.om.VES.TEXTURE_COORDINATES)
    t=shared.values(vd,shared.om.VES.TANGENT)[:,:3] if vd.vertex_declaration.find_by_semantic(shared.om.VES.TANGENT) else np.zeros_like(n)
    tri=sub.index_array.reshape(-1,3);tri=tri if mask is None else tri[mask];used,remap=np.unique(tri,return_inverse=True)
    n=n[used];n/=np.maximum(np.linalg.norm(n,axis=1)[:,None],1e-9);t=t[used];t-=n*(t*n).sum(1)[:,None]
    for i in np.flatnonzero(np.linalg.norm(t,axis=1)<1e-8):t[i]=np.cross(np.eye(3)[np.argmin(abs(n[i]))],n[i])
    t/=np.linalg.norm(t,axis=1)[:,None]
    return np.column_stack([p[used],n,uv[used],t]).astype('<f4'),remap.astype('<u2').reshape(-1),used

def geometry(source,skelpath,faction,game,root):
    cfg=CONFIG[faction];s,w,eye,shell=shared.rig(skelpath,cfg['shell']);native=native_eye(w,eye,game,cfg['base'],root);origin,R=w[eye.handle]
    mesh=shared.read_mesh(source);rows=[];ix=[];liner=[];parts={};panels=[]
    def face(points,chart='trim',hint=None,rect=None,uvs=None):
        p=np.array(points,float);n=np.cross(p[1]-p[0],p[2]-p[0]);n/=np.linalg.norm(n);hint=-p.mean(0) if hint is None else np.array(hint)
        if np.dot(n,hint)<0:p=p[::-1];n=-n;uvs=None if uvs is None else uvs[::-1]
        if faction=='cca' and chart=='trim':rect=scoutcockpits.CHARTS['trim']
        x0,y0,x1,y1=cfg['charts'][chart] if rect is None else rect
        uv=uvs if uvs is not None else ([(x1,y0),(x0,y0),(x0,y1),(x1,y1)] if len(p)==4 else [(x0+(x1-x0)*(.5+.5*math.cos(i*2*math.pi/len(p))),y0+(y1-y0)*(.5+.5*math.sin(i*2*math.pi/len(p)))) for i in range(len(p))])
        start=len(rows)
        for v,t in zip(p,uv):rows.append([*(origin+R@v),*(R@n),*t])
        for i in range(1,len(p)-1):ix.extend([start,start+i,start+i+1]);liner.append(faction=='cca' and chart=='trim')
    def beam(a,b,width=.025,chart='frame'):
        a=np.array(a,float);b=np.array(b,float);axis=b-a;axis/=np.linalg.norm(axis);u=np.cross(axis,[0,1,0] if abs(axis[1])<.9 else [1,0,0]);u/=np.linalg.norm(u);v=np.cross(axis,u)
        section=[(-.3,-.5),(.3,-.5),(.5,-.3),(.5,.3),(.3,.5),(-.3,.5),(-.5,.3),(-.5,-.3)]
        ring=[[p+u*x*width+v*y*width for x,y in section] for p in (a,b)];c=(a+b)/2
        for i in range(8):j=(i+1)%8;q=[ring[0][i],ring[1][i],ring[1][j],ring[0][j]];face(q,chart,np.mean(q,0)-c)
        face(ring[0],'trim',-axis);face(ring[1],'trim',axis)
    def panel(p,chart='switch',rect=None,depth=.012):
        p=np.array(p,float);c=p.mean(0);n=np.cross(p[1]-p[0],p[2]-p[0]);n/=np.linalg.norm(n)
        if np.dot(n,-c)<0:n=-n
        back=p+n*.003;front=c+(p-c)*.92+n*depth
        face(front,chart,rect=rect)
        for i in range(4):j=(i+1)%4;face([back[i],back[j],front[j],front[i]],'trim',hint=n)
        for i in range(4):beam(front[i],front[(i+1)%4],depth*.65,'frame')
        # Real eight-sided, capped fasteners and inset screw slots, not decals
        # floating in the view. These live only on pilot-visible cassettes.
        for corner in front:
            fc=front.mean(0);at=fc+(corner-fc)*.89+n*.001;u=front[1]-front[0];u/=np.linalg.norm(u);v=np.cross(n,u);radius=depth*.25
            ring=[at+radius*(math.cos(i*math.pi/4)*u+math.sin(i*math.pi/4)*v) for i in range(8)]
            face(ring,'frame',hint=n)
            for i in range(8):j=(i+1)%8;face([ring[i],ring[j],ring[j]-n*.002,ring[i]-n*.002],'trim',hint=ring[i]-at)
            face([at-u*radius*.7-v*radius*.12+n*.0002,at+u*radius*.7-v*radius*.12+n*.0002,at+u*radius*.7+v*radius*.12+n*.0002,at-u*radius*.7+v*radius*.12+n*.0002],'trim',hint=n)
        panels.append(dict(points=p.tolist(),chart=chart,depth=depth))
    stock=mesh.submesh_list[cfg['batch']];stockdata,stockix,_=source_part(stock)
    if faction!='cca':parts[cfg['stock']]=(stockdata,stockix)
    if faction in ('nsdf','bdog'):
        # Copy source control quads exactly, including each faction's different
        # eye-relative placement. No imposed scout canopy or raised Black Dog eye.
        points=(stockdata[:,:3]-origin)@R;tri=stockix.reshape(-1,3)
        for pair,chart in [([4,5],'console'),([28,29],'console'),([26,27],'service'),([66,67],'switch')]:
            q=np.unique(points[tri[pair]].reshape(-1,3),axis=0);c=q.mean(0);n=np.cross(q[1]-q[0],q[2]-q[0]);n/=np.linalg.norm(n);u=q[0]-c;u/=np.linalg.norm(u);v=np.cross(n,u);order=np.argsort(np.arctan2((q-c)@v,(q-c)@u));q=q[order]
            rect=None
            if chart=='console':
                x0,y0,x1,y1=cfg['charts'][chart];rect=(x0,y0,x0+(x1-x0)*.29,y1) if pair[0]==4 else (x0+(x1-x0)*.72,y0,x1,y1)
            panel(q,chart,rect)
        # The characteristic raised left/right instrument pods and central
        # bridge retain their exact stock positions and warning horns.
        delta=np.array([0.,0.,0.]) if faction=='nsdf' else np.array([0.,-.633138,-.112862])
        for sign in (-1,1):
            q=np.array([(sign*.12,.959,1.893),(sign*.172,1.030,2.014),(sign*.478,1.030,2.014),(sign*.478,.959,1.893)])+delta-origin
            # Both pods show the full button block; the right one mirrors the left
            # (the other chart strip cut its top row and read as sheared).
            x0,y0,x1,y1=cfg['charts']['console'];rect=(x1,y0,x0+(x1-x0)*.72,y1) if sign>0 else (x0+(x1-x0)*.72,y0,x1,y1)
            panel(q,'console',rect,depth=.009)
        # Central tactile switch unit follows the stepped stock bridge.
        panel([(-.115,-.47 if faction=='nsdf' else -.30,.66 if faction=='nsdf' else .55),(.115,-.47 if faction=='nsdf' else -.30,.66 if faction=='nsdf' else .55),(.115,-.57 if faction=='nsdf' else -.40,.625 if faction=='nsdf' else .515),(-.115,-.57 if faction=='nsdf' else -.40,.625 if faction=='nsdf' else .515)],'switch')
    elif faction=='cra':
        # Keep original tiny split-console pit, ceiling and yellow braces.
        # Small replacement cassettes fit the original banks; the center stays open.
        for sign in (-1,1):
            panel([(sign*.065,-.229,.365),(sign*.172,-.176,.356),(sign*.264,-.264,.206),(sign*.103,-.347,.222)],'service' if sign>0 else 'switch',depth=.006)
            beam((sign*.30,-.10,.06),(sign*.32,-.33,.66),.012)
    else:
        # CCA keeps its stock white-enamel, black equipment and red seams. The
        # thin off-centre legacy shell is rebuilt as substantial low control boxes.
        for sign in (-1,1):
            panel([(sign*.12,-.35,1.05),(sign*.61,-.30,1.03),(sign*.59,-.60,.79),(sign*.12,-.61,.79)],'console',depth=.019)
            panel([(sign*.58,-.38,.83),(sign*.71,-.25,.55),(sign*.71,-.55,.20),(sign*.56,-.66,.48)],'switch',depth=.016)
            beam((sign*.73,-.29,.93),(sign*.73,.29,.62),.050)
            beam((sign*.73,.29,.62),(sign*.48,.57,.37),.050)
            beam((sign*.48,.57,.37),(sign*.73,.60,-.40),.044)
            beam((sign*.73,-.29,.93),(sign*.77,-.30,-.40),.045)
        beam((-.48,.57,.37),(.48,.57,.37),.052)
        panel([(-.105,-.40,1.01),(.105,-.40,1.01),(.105,-.59,.81),(-.105,-.59,.81)],'switch',depth=.018)
    # Continuous inner tub behind instruments, with a rear bulkhead and roof.
    # This patch has exactly ONE intentional window boundary, never little holes.
    shellstart=len(ix);width=cfg['width'];lip=cfg['lip'];front=cfg['front'];roof=cfg['roof'];floor=-1.18 if faction!='cra' else -.47;back=-.62 if faction!='cra' else -.22
    rings=[]
    for z in (back,front*.30,front):rings.append([(-width,lip,z),(-width*.98,floor*.70,z),(-width*.65,floor,z),(width*.65,floor,z),(width*.98,floor*.70,z),(width,lip,z)])
    length=np.r_[0,np.cumsum(np.linalg.norm(np.diff(np.array(rings[0]),axis=0),axis=1))];length/=length[-1];tx0,ty0,tx1,ty1=scoutcockpits.CHARTS['trim'] if faction=='cca' else cfg['charts']['trim']
    def tubuv(i,z):return (tx0+(tx1-tx0)*length[i],ty0+(ty1-ty0)*(z-back)/(front-back))
    for a,b in zip(rings,rings[1:]):
        for i in range(5):face([a[i],b[i],b[i+1],a[i+1]],uvs=[tubuv(i,a[i][2]),tubuv(i,b[i][2]),tubuv(i+1,b[i+1][2]),tubuv(i+1,a[i+1][2])])
    face(rings[-1]);face(rings[0])
    face([rings[0][0],rings[0][-1],(width,roof,back),(-width,roof,back)])
    face([(-width,roof,back),(width,roof,back),(width*.68,roof,front*.38),(-width*.68,roof,front*.38)])
    shellend=len(ix)
    edges=Counter()
    for tri in np.array(rows)[:,:3][np.array(ix[shellstart:shellend]).reshape(-1,3)]:
        keys=[tuple(np.round(p,6)) for p in tri]
        for i in range(3):edges[tuple(sorted((keys[i],keys[(i+1)%3])))]+=1
    boundary=[e for e,n in edges.items() if n==1];adj={}
    for a,b in boundary:adj.setdefault(a,set()).add(b);adj.setdefault(b,set()).add(a)
    assert max(edges.values())==2 and all(len(v)==2 for v in adj.values())
    seen=set();todo=[next(iter(adj))]
    while todo:
        p=todo.pop()
        if p not in seen:seen.add(p);todo.extend(adj[p]-seen)
    assert len(seen)==len(adj),'only one intentional window boundary'
    topology=dict(triangles=(shellend-shellstart)//3,boundaryEdges=len(boundary),boundaryLoops=1)
    # A bounded solid coaming joins the lower window to the visible hull apron.
    # Grizzly's broader nose needs a continuous lower fairing behind the cut
    # source group; otherwise sky shows through the rear crop beside the horns.
    if faction in ('nsdf','bdog'):
        # NSDF drops further so the slab stays under the widened hull shoulders.
        drop=.30 if faction=='nsdf' else .20
        rear,taper=(2.55,.72) if faction=='nsdf' else (1.85,1.)
        deck=[(-width,lip,front),(width,lip,front),(width*taper,lip-drop*(rear-front)/(1.85-front),rear),(-width*taper,lip-drop*(rear-front)/(1.85-front),rear)]
    else:deck=[(-width,lip,front),(width,lip,front),(width*.90,lip-.075,front+.35),(-width*.90,lip-.075,front+.35)]
    face(deck,'armor',hint=[0,1,0]);bottom=np.array(deck)-[0,.07,0];face(bottom,hint=[0,-1,0])
    for i in range(4):j=(i+1)%4;face([deck[i],deck[j],bottom[j],bottom[i]],'frame')
    if faction=='cca':
        for material,mask in [(cfg['material'],~np.array(liner)),('CRV/SharedCockpitLiner',np.array(liner))]:
            used,remap=np.unique(np.array(ix).reshape(-1,3)[mask],return_inverse=True)
            parts[material]=(np.array(rows,dtype='<f4')[used],remap.astype('<u2').reshape(-1))
    else:parts[cfg['material']]=(np.array(rows,dtype='<f4'),np.array(ix,dtype='<u2'))
    body=mesh.submesh_list[cfg['body']];p=shared.values(body.vertex_data,shared.om.VES.POSITION);n=shared.values(body.vertex_data,shared.om.VES.NORMAL);tri=body.index_array.reshape(-1,3)
    weight=np.zeros(len(p))
    for a in body.bone_assignments():
        if a.bone_index in cfg['gun']:weight[a.vertex_index]+=a.weight
    gun=(weight[tri]>.99).all(1);gunpart,gunix,used=source_part(body,gun);gunweights=[];remap={int(old):i for i,old in enumerate(used)}
    for a in body.bone_assignments():
        if a.vertex_index in remap:gunweights.append((remap[a.vertex_index],a.bone_index,a.weight))
    # The stock CRA first-person barrel sits behind CYE11POV. Bring that same
    # complete part forward as one rigid piece: just its distal underside peeks
    # below the roof, without touching the aiming corridor or replacing the rig.
    gunoffset=np.array([0.,.02,4.30]) if faction=='cra' else np.zeros(3)
    gunpart[:,:3]+=(R@gunoffset).astype('<f4')
    parts['CRV/'+cfg['base']+'TankGuns']=(gunpart,gunix)
    # Original-painted front glacis, not the whole exterior. Keep triangle
    # shapes and UVs; one rigid fit gives the low view an actual vehicle surface.
    bodyweight=np.zeros(len(p))
    for a in body.bone_assignments():
        if a.bone_index==cfg['bodyBone']:bodyweight[a.vertex_index]+=a.weight
    grizzly=faction in ('nsdf','bdog')
    # A recognizable Grizzly needs the complete front deck/shoulder group,
    # not just the last upward-facing strip at the tip. Keep its original
    # sloping plate, vents, lamp recesses and bevels as one rigid source piece.
    cut=1.0 if grizzly else cfg['cut'];normal_floor=-1.1 if grizzly else .25
    q=p[tri];mask=(q[:,:,2].min(1)>cut)&(abs(q[:,:,0]).max(1)<2.05)&(n[tri].mean(1)[:,1]>normal_floor)&(bodyweight[tri]>.99).all(1)&~gun
    apron,apronix,used=source_part(body,mask);assert len(apronix)>0,'front hull crop must exist'
    pitch=(-5. if faction=='nsdf' else -22.) if grizzly else 0.;angle=math.radians(pitch);c,ss=math.cos(angle),math.sin(angle);rotation=np.array([[1.,0,0],[0,c,-ss],[0,ss,c]])
    # NSDF review: the nose read as a narrow wedge, so only its breadth grows.
    spread=1.35 if faction=='nsdf' else 1.;rotation=rotation@np.diag([spread,1.,1.])
    pivot_model=np.array([0.,1.25,1.10]) if grizzly else np.zeros(3);pivot=(pivot_model-origin)@R
    local=((apron[:,:3]-origin)@R-pivot)@rotation.T+pivot
    top=(-.48 if faction=='nsdf' else -.32) if grizzly else lip-.09
    near=1.10 if grizzly else front+.04
    offset=np.array([0.,top-local[:,1].max(),max(near-local[:,2].min(),0.)]);transform=np.eye(4);transform[:3,:3]=R@rotation@R.T;transform[:3,3]=pivot_model-transform[:3,:3]@pivot_model+R@offset
    apron[:,:3]=apron[:,:3]@transform[:3,:3].T+transform[:3,3]
    normal=np.linalg.inv(transform[:3,:3]).T if spread!=1 else transform[:3,:3];apron[:,3:6]=apron[:,3:6]@normal.T;apron[:,8:11]=apron[:,8:11]@transform[:3,:3].T
    if spread!=1:
        for k in (3,8):apron[:,k:k+3]/=np.linalg.norm(apron[:,k:k+3],axis=1)[:,None]
    parts['CRV/'+cfg['base']+'TankHull']=(apron,apronix)
    if faction=='nsdf':
        # The level hull leaves a slit over the coaming; a bulkhead leaning in
        # under the plate's open near edge stops see-through rays.
        hull=((apron[:,:3]-origin)@R)[apronix.reshape(-1,3)];zw,zt=near+.04,near+.10;xs=[];tops=[]
        for x in np.linspace(-2.6,2.6,53):
            dist,_=__import__('cockpitglass').cast(np.array([x,2.,zt]),np.array([[0,-1.,0]]),hull[:,0],hull[:,1],hull[:,2])
            if np.isfinite(dist[0]):xs.append(x);tops.append(2-dist[0]-.003)
        floor_y=lip-drop*(zw-front)/(1.85-front)-.03
        for a in range(len(xs)-1):face([(xs[a],floor_y,zw),(xs[a+1],floor_y,zw),(xs[a+1],tops[a+1],zt),(xs[a],tops[a],zt)],'frame',hint=[0,0,-1])
        parts[cfg['material']]=(np.array(rows,dtype='<f4'),np.array(ix,dtype='<u2'))
    meta=dict(faction=faction,base=cfg['base'],pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,panels=panels,stockCockpitRetained=faction!='cca',stockTriangles=len(stockix)//3,gunWeights=gunweights,gunBones=cfg['gun'],gunOffset=gunoffset.tolist(),apronSourceIndices=np.flatnonzero(mask).tolist(),apronOffset=offset.tolist(),apronTriangles=len(apronix)//3,innerShell=topology,window=dict(width=width,lip=lip,front=front,roof=roof),nativeVdfSha256=__import__('hashlib').sha256(native).hexdigest())
    if grizzly:meta.update(apronTransform=transform.tolist(),apronPitchDegrees=pitch,apronPivotModel=pivot_model.tolist(),**(dict(apronSpreadX=spread) if spread!=1 else {}))
    return parts,s,w,eye,shell,meta

def compile_mesh(parts,s,w,eye,shell,base,meta):
    raw,glass=shared.mesh_bytes(parts,s,w,eye,shell,skeleton_name=base+'_cockpit.skeleton')
    mesh=shared.oms.MeshSerializer(io.BytesIO(raw)).read()
    guns=next(sub for sub in mesh.submesh_list if sub.material_name=='CRV/'+base+'TankGuns');guns.clear_bone_assignments()
    for v,b,weight in meta['gunWeights']:guns.create_bone_assignment(v,b,weight)
    out=io.BytesIO();shared.oms.MeshSerializer(out).write(mesh)
    return out.getvalue(),glass
