"""Stock-layout tank cockpit detailing, using shared codecs and existing atlases."""
from collections import Counter
import io, math
import numpy as np
import reddevilcockpit as shared
import cvhrazcockpit, tankpanelatlas
from bzmodellibs import legacy, legacy_port

CONFIG={
 'nsdf':dict(base='avtank',shell='agr21bda',batch=2,body=0,bodyBone=2,gun=[18],material='CRV/avtankTankPanels',atlas='crvatkp',stock='avtank01',exterior='avtank00',charts=tankpanelatlas.CHARTS,width=.98,lip=-.49,front=.91,roof=.62,cut=2.02),
 'bdog':dict(base='bvtank',shell='bgr21bda',batch=0,body=1,bodyBone=2,gun=[1],material='CRV/bvtankTankPanels',atlas='crvbtkp',stock='bvtank01',exterior='bvtank00',charts=tankpanelatlas.CHARTS,width=.98,lip=-.35,front=.80,roof=.85,cut=2.02),
 'cca':dict(base='svtank',shell='scz21bda',batch=2,body=0,bodyBone=1,gun=[2,3],gunSource={26:3},material='svtank01',stock='svtank01',exterior='svtank00',charts={'console':(.370,.158,.553,.297),'switch':(.207,.006,.350,.298),'service':(.770,.008,.986,.190),'armor':(.635,.06,.739,.23),'frame':(.635,.06,.739,.23),'trim':(.745,.35,.757,.56),'plate':(.640,.585,.770,.705)},hood=dict(tex='crcca_svhood',x=(-1.9,1.9),z=(3.29,4.82)),width=.76,lip=-.44,front=1.10,roof=.62,cut=1.62),
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

def raw_world(world):
    """shared.rig reads skeletons through the toolkit serializer, which negates X; mesh data keeps raw Ogre X.
    Without this an off-centre eye (CZar, raw x=+0.276) builds the whole cabin mirrored onto the other side."""
    M=np.diag([-1.,1.,1.]);return {h:(M@p,M@r@M) for h,(p,r) in world.items()}

# Grizzly lower-half stock triangles rebuilt as metric panels (same positions):
# the outer lower walls and the two sloped sill quads. The stock floor and its
# spine strut stay: a generated tread plate read flatter than the original.
GRIZZLY_WALLS=[0,1,17,18,35,36,60,61];GRIZZLY_SILLS=[[26,27],[66,67]]

def clip(poly,k,c,sign):
    """Sutherland-Hodgman: keep the part of a 2D polygon with sign*(x[k]-c)>=0."""
    out=[]
    for i in range(len(poly)):
        a,b=poly[i],poly[(i+1)%len(poly)];da,db=sign*(a[k]-c),sign*(b[k]-c)
        if da>=0:out.append(a)
        if da*db<0:out.append(a+(b-a)*da/(da-db))
    out=[q for i,q in enumerate(out) if np.linalg.norm(q-out[i-1])>1e-7]
    out=[q for i,q in enumerate(out) if abs((out[i-1][0]-q[0])*(out[(i+1)%len(out)][1]-q[1])-(out[i-1][1]-q[1])*(out[(i+1)%len(out)][0]-q[0]))>1e-10]
    return np.array(out) if len(out)>=3 else np.zeros((0,2))

def source_part(sub,mask=None):
    vd=sub.vertex_data;p=shared.values(vd,shared.om.VES.POSITION);n=shared.values(vd,shared.om.VES.NORMAL);uv=shared.values(vd,shared.om.VES.TEXTURE_COORDINATES)
    t=shared.values(vd,shared.om.VES.TANGENT)[:,:3] if vd.vertex_declaration.find_by_semantic(shared.om.VES.TANGENT) else np.zeros_like(n)
    tri=sub.index_array.reshape(-1,3);tri=tri if mask is None else tri[mask];used,remap=np.unique(tri,return_inverse=True)
    n=n[used];n/=np.maximum(np.linalg.norm(n,axis=1)[:,None],1e-9);t=t[used];t-=n*(t*n).sum(1)[:,None]
    for i in np.flatnonzero(np.linalg.norm(t,axis=1)<1e-8):t[i]=np.cross(np.eye(3)[np.argmin(abs(n[i]))],n[i])
    t/=np.linalg.norm(t,axis=1)[:,None]
    return np.column_stack([p[used],n,uv[used],t]).astype('<f4'),remap.astype('<u2').reshape(-1),used

def geometry(source,skelpath,faction,game,root):
    cfg=CONFIG[faction];s,w,eye,shell=shared.rig(skelpath,cfg['shell']);native=native_eye(w,eye,game,cfg['base'],root);w=raw_world(w);origin,R=w[eye.handle]
    mesh=shared.read_mesh(source);rows=[];ix=[];parts={};panels=[]
    def face(points,chart='trim',hint=None,rect=None,uvs=None):
        p=np.array(points,float);n=np.cross(p[1]-p[0],p[2]-p[0]);n/=np.linalg.norm(n);hint=-p.mean(0) if hint is None else np.array(hint)
        if np.dot(n,hint)<0:p=p[::-1];n=-n;uvs=None if uvs is None else uvs[::-1]
        x0,y0,x1,y1=cfg['charts'][chart] if rect is None else rect
        uv=uvs if uvs is not None else ([(x1,y0),(x0,y0),(x0,y1),(x1,y1)] if len(p)==4 else [(x0+(x1-x0)*(.5+.5*math.cos(i*2*math.pi/len(p))),y0+(y1-y0)*(.5+.5*math.sin(i*2*math.pi/len(p)))) for i in range(len(p))])
        start=len(rows)
        for v,t in zip(p,uv):rows.append([*(origin+R@v),*(R@n),*t])
        for i in range(1,len(p)-1):ix.extend([start,start+i,start+i+1])
    def tiled(points,chart,hint=None,u=None,anchor=None):
        """Clip a planar polygon into metric atlas cells in its own face frame
        (u along `u` projected onto the face), so seams follow the mesh."""
        p=np.array(points,float);n=np.cross(p[1]-p[0],p[2]-p[0]);n/=np.linalg.norm(n);hint=-p.mean(0) if hint is None else np.array(hint,float)
        if np.dot(n,hint)<0:p=p[::-1];n=-n
        u=np.array([0,0,1.]) if u is None else np.array(u,float);u=u-n*np.dot(u,n)
        if np.linalg.norm(u)<1e-6:u=np.array([1.,0,0])-n*n[0]
        u/=np.linalg.norm(u);v=np.cross(n,u);a=np.zeros(3) if anchor is None else np.array(anchor,float);a=a+n*np.dot(p[0]-a,n)
        st=np.column_stack([(p-a)@u,(p-a)@v]);cu,cv=tankpanelatlas.CELL[chart];x0,y0,x1,y1=cfg['charts'][chart]
        for i in range(math.floor(st[:,0].min()/cu+1e-9),math.ceil(st[:,0].max()/cu-1e-9)):
            for j in range(math.floor(st[:,1].min()/cv+1e-9),math.ceil(st[:,1].max()/cv-1e-9)):
                poly=st
                for k,c,sg in ((0,i*cu,1),(0,(i+1)*cu,-1),(1,j*cv,1),(1,(j+1)*cv,-1)):
                    poly=clip(poly,k,c,sg)
                    if not len(poly):break
                if not len(poly):continue
                face([a+q[0]*u+q[1]*v for q in poly],chart,hint=n,uvs=[(x0+(x1-x0)*(q[0]/cu-i),y0+(y1-y0)*(q[1]/cv-j)) for q in poly])
    def beam(a,b,width=.025,chart='frame'):
        a=np.array(a,float);b=np.array(b,float);axis=b-a;axis/=np.linalg.norm(axis);u=np.cross(axis,[0,1,0] if abs(axis[1])<.9 else [1,0,0]);u/=np.linalg.norm(u);v=np.cross(axis,u)
        section=[(-.3,-.5),(.3,-.5),(.5,-.3),(.5,.3),(.3,.5),(-.3,.5),(-.5,.3),(-.5,-.3)]
        ring=[[p+u*x*width+v*y*width for x,y in section] for p in (a,b)];c=(a+b)/2
        for i in range(8):j=(i+1)%8;q=[ring[0][i],ring[1][i],ring[1][j],ring[0][j]];face(q,chart,np.mean(q,0)-c)
        face(ring[0],'trim',-axis);face(ring[1],'trim',axis)
    def sweep(points,width=.05,chart='frame'):
        """One continuous octagonal frame member along a polyline. Interior
        corners are mitred (rings on the bisector plane, frame carried by minimal
        rotation), so joints are closed with no crossing end caps."""
        P=[np.array(q,float) for q in points];axes=[(b-a)/np.linalg.norm(b-a) for a,b in zip(P,P[1:])]
        section=[(-.3,-.5),(.3,-.5),(.5,-.3),(.5,.3),(.3,.5),(-.3,.5),(-.5,.3),(-.5,-.3)]
        a=axes[0];u=np.cross(a,[0,1,0] if abs(a[1])<.9 else [1,0,0]);u/=np.linalg.norm(u);v=np.cross(a,u)
        rings=[[P[0]+u*x*width+v*y*width for x,y in section]]
        for k in range(1,len(P)):
            a=axes[k-1];m=a if k==len(P)-1 else a+axes[k];m/=np.linalg.norm(m)
            rings.append([q+a*np.dot(P[k]-q,m)/np.dot(a,m) for q in (P[k]+u*x*width+v*y*width for x,y in section)])
            if k<len(P)-1:
                b=axes[k];c=np.cross(a,b);sn=np.linalg.norm(c);cs=np.dot(a,b)
                if sn>1e-9:
                    c/=sn;rot=lambda w:w*cs+np.cross(c,w)*sn+c*np.dot(c,w)*(1-cs);u,v=rot(u),rot(v)
        for k in range(len(P)-1):
            mid=(np.mean(rings[k],0)+np.mean(rings[k+1],0))/2
            for i in range(8):j=(i+1)%8;q=[rings[k][i],rings[k+1][i],rings[k+1][j],rings[k][j]];face(q,chart,np.mean(q,0)-mid)
        face(rings[0],'trim',-axes[0]);face(rings[-1],'trim',axes[-1])
    def panel(p,chart='switch',rect=None,depth=.012,hole=None):
        p=np.array(p,float);c=p.mean(0);n=np.cross(p[1]-p[0],p[2]-p[0]);n/=np.linalg.norm(n)
        if np.dot(n,-c)<0:n=-n
        back=p+n*.003;front=c+(p-c)*.92+n*depth
        if hole is None:face(front,chart,rect=rect)
        else:
            # Recessed scope: the face is four strips round a real opening and
            # trim walls step back to the screen; no decal floating on the plate.
            x0,y0,x1,y1=cfg['charts'][chart] if rect is None else rect;X0,_,X1,_=cfg['charts'][chart]
            def at(s,t):return (1-t)*((1-s)*front[1]+s*front[0])+t*((1-s)*front[2]+s*front[3])
            def strip(s0,t0,s1,t1):
                st=((s1,t0),(s0,t0),(s0,t1),(s1,t1));face([at(*q) for q in st],chart,hint=n,uvs=[(x0+(x1-x0)*a,y0+(y1-y0)*b) for a,b in st])
            sa,sb=sorted((X0+h*(X1-X0)-x0)/(x1-x0) for h in (hole[0],hole[2]));ta,tb=hole[1],hole[3]
            strip(0,0,sa,1);strip(sb,0,1,1);strip(sa,0,sb,ta);strip(sa,tb,sb,1)
            rim=[at(sb,ta),at(sa,ta),at(sa,tb),at(sb,tb)];pit=[q-n*.006 for q in rim];mid=np.mean(pit,0)
            for i in range(4):j=(i+1)%4;face([rim[i],rim[j],pit[j],pit[i]],'trim',hint=mid-(rim[i]+rim[j])/2)
            sx0,sy0,sx1,sy1=cfg['charts']['scope'];face(pit,'scope',hint=n,uvs=[(sx1,sy0),(sx0,sy0),(sx0,sy1),(sx1,sy1)])
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
        # Lower walls keep their exact positions but are re-emitted as armour
        # panels cut on face-local metric cells.
        for k in GRIZZLY_WALLS:
            q=points[tri[k]];tiled(q,'plate',hint=np.cross(q[1]-q[0],q[2]-q[0]))
        for pair,chart in [([4,5],'console'),([28,29],'console'),([26,27],'service'),([66,67],'switch')]:
            q=np.unique(points[tri[pair]].reshape(-1,3),axis=0);c=q.mean(0);n=np.cross(q[1]-q[0],q[2]-q[0]);n/=np.linalg.norm(n);u=q[0]-c;u/=np.linalg.norm(u);v=np.cross(n,u);order=np.argsort(np.arctan2((q-c)@v,(q-c)@u));q=q[order]
            if pair in GRIZZLY_SILLS:
                # Faction hazard band along each sill's inner (pod-side) edge, armour
                # plate behind it, and a narrower cassette on the remaining slope.
                inner=np.argsort(abs(q[:,0]))[:2];A,B=q[inner[0]],q[inner[1]];up=n*np.sign(np.dot(n,-c))
                axis=(B-A)/np.linalg.norm(B-A);side=np.cross(up,axis);st=np.column_stack([(q-A)@axis,(q-A)@side])
                if st[:,1].sum()<0:side=-side;st[:,1]*=-1
                band,rest=clip(st,1,.06,-1),clip(st,1,.06,1)
                lift=lambda poly:[A+x*axis+y*side for x,y in poly]
                tiled(lift(band),'hazard',hint=up,u=axis,anchor=A);tiled(lift(rest),'plate',hint=up,u=axis,anchor=A)
                q=np.array(lift(rest));assert len(q)==4,'sill remainder is a quad'
                c=q.mean(0);q=q[np.argsort(np.arctan2((q-c)@v,(q-c)@u))]
            rect=None
            if chart=='console':
                # Pod fronts keep the stock-grounded button blocks from either end of the console chart.
                x0,y0,x1,y1=cfg['charts'][chart];rect=(x0,y0,x0+(x1-x0)*.29,y1) if pair[0]==4 else (x0+(x1-x0)*.72,y0,x1,y1)
            panel(q,chart,rect)
        # The characteristic raised left/right instrument pods and central
        # bridge retain their exact stock positions and warning horns. One
        # recessed scope per pod replaces the old uniform lamp grid.
        delta=np.array([0.,0.,0.]) if faction=='nsdf' else np.array([0.,-.633138,-.112862])
        for sign in (-1,1):
            q=np.array([(sign*.12,.959,1.893),(sign*.172,1.030,2.014),(sign*.478,1.030,2.014),(sign*.478,.959,1.893)])+delta-origin
            x0,y0,x1,y1=cfg['charts']['pod'];panel(q,'pod',(x1,y0,x0,y1) if sign>0 else None,depth=.009,hole=(.10,.08,.40,.92))
        # Central tactile switch unit follows the stepped stock bridge.
        panel([(-.115,-.47 if faction=='nsdf' else -.30,.66 if faction=='nsdf' else .55),(.115,-.47 if faction=='nsdf' else -.30,.66 if faction=='nsdf' else .55),(.115,-.57 if faction=='nsdf' else -.40,.625 if faction=='nsdf' else .515),(-.115,-.57 if faction=='nsdf' else -.40,.625 if faction=='nsdf' else .515)],'switch')
        replaced=sorted(GRIZZLY_WALLS+sum(GRIZZLY_SILLS,[]));keep=np.ones(len(tri),bool);keep[replaced]=False
        parts[cfg['stock']]=source_part(stock,keep)[:2]
    elif faction=='cra':
        # Keep original tiny split-console pit, ceiling and yellow braces.
        # Small replacement cassettes fit the original banks; the center stays open.
        for sign in (-1,1):
            panel([(sign*.065,-.229,.365),(sign*.172,-.176,.356),(sign*.264,-.264,.206),(sign*.103,-.347,.222)],'service' if sign>0 else 'switch',depth=.006)
            beam((sign*.30,-.10,.06),(sign*.32,-.33,.66),.012)
    # CCA builds its deck hatch after the real deck crop exists (below).
    # CCA's hatch cupola is closed on its own (above); the others keep the tub and deck slab.
    topology=None;width=cfg['width'];lip=cfg['lip'];front=cfg['front'];roof=cfg['roof']
    if faction!='cca':
        # Continuous inner tub behind instruments, with a rear bulkhead and roof.
        # This patch has exactly ONE intentional window boundary, never little holes.
        shellstart=len(ix);floor=-1.18 if faction!='cra' else -.47;back=-.62 if faction!='cra' else -.22
        rings=[]
        for z in (back,front*.30,front):rings.append([(-width,lip,z),(-width*.98,floor*.70,z),(-width*.65,floor,z),(width*.65,floor,z),(width*.98,floor*.70,z),(width,lip,z)])
        length=np.r_[0,np.cumsum(np.linalg.norm(np.diff(np.array(rings[0]),axis=0),axis=1))];length/=length[-1];tx0,ty0,tx1,ty1=cfg['charts']['trim']
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
        (tiled(deck,'plate',hint=[0,1,0]) if faction in ('nsdf','bdog') else face(deck,'armor',hint=[0,1,0]));bottom=np.array(deck)-[0,.07,0];face(bottom,hint=[0,-1,0])
        for i in range(4):j=(i+1)%4;face([deck[i],deck[j],bottom[j],bottom[i]],'frame')
    parts[cfg['material']]=(np.array(rows,dtype='<f4'),np.array(ix,dtype='<u2'))
    body=mesh.submesh_list[cfg['body']];p=shared.values(body.vertex_data,shared.om.VES.POSITION);n=shared.values(body.vertex_data,shared.om.VES.NORMAL);tri=body.index_array.reshape(-1,3)
    weight=np.zeros(len(p))
    for a in body.bone_assignments():
        if cfg.get('gunSource',{}).get(a.bone_index,a.bone_index) in cfg['gun']:weight[a.vertex_index]+=a.weight
    gun=(weight[tri]>.99).all(1);gunpart,gunix,used=source_part(body,gun);gunweights=[];remap={int(old):i for i,old in enumerate(used)}
    for a in body.bone_assignments():
        if a.vertex_index in remap:gunweights.append((remap[a.vertex_index],cfg.get('gunSource',{}).get(a.bone_index,a.bone_index),a.weight))
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
    # Owner review: both noses read as ramps climbing toward the aim point. Each plate
    # sits lower with less nose-up pitch (negative lifts the nose), so its far edge drops
    # further below the eye line (see README) while enough real hull stays visible;
    # full nose-down pitch hides it behind the console.
    pitch=(-3. if faction=='nsdf' else -15.) if grizzly else 0.;angle=math.radians(pitch);c,ss=math.cos(angle),math.sin(angle);rotation=np.array([[1.,0,0],[0,c,-ss],[0,ss,c]])
    # NSDF review: the nose read as a narrow wedge, so only its breadth grows.
    spread=1.35 if faction=='nsdf' else 1.;rotation=rotation@np.diag([spread,1.,1.])
    pivot_model=np.array([0.,1.25,1.10]) if grizzly else np.zeros(3);pivot=(pivot_model-origin)@R
    local=((apron[:,:3]-origin)@R-pivot)@rotation.T+pivot
    top=(-.54 if faction=='nsdf' else -.44) if grizzly else lip-.09
    near=1.10 if grizzly else front+.04
    # CCA shows the real front deck exactly where the exterior has it, around the cupola.
    offset=np.zeros(3) if faction=='cca' else np.array([0.,top-local[:,1].max(),max(near-local[:,2].min(),0.)]);transform=np.eye(4);transform[:3,:3]=R@rotation@R.T;transform[:3,3]=pivot_model-transform[:3,:3]@pivot_model+R@offset
    apron[:,:3]=apron[:,:3]@transform[:3,:3].T+transform[:3,3]
    normal=np.linalg.inv(transform[:3,:3]).T if spread!=1 else transform[:3,:3];apron[:,3:6]=apron[:,3:6]@normal.T;apron[:,8:11]=apron[:,8:11]@transform[:3,:3].T
    if spread!=1:
        for k in (3,8):apron[:,k:k+3]/=np.linalg.norm(apron[:,k:k+3],axis=1)[:,None]
    parts['CRV/'+cfg['base']+'TankHull']=(apron,apronix)
    if faction=='cca':
        # Owner review (Total Command layout idea, no assets): the pilot's head sits in a small
        # hatch on the deck nose just behind the muzzle, ~15 cm above the deck. The real deck
        # nose fills the bottom of the view and the real barrel runs overhead. The opening is
        # clipped out of the real deck crop; a sunk tub holds one console, a thin coaming hides
        # the cut, and an open hatch lid behind the head closes the rear and roof out of view.
        x0,x1,z0,z1,bottom,rise,coam=-.28,.28,-.30,.32,-.60,.30,.04
        hloc=(apron[:,:3]-origin)@R;ht=apronix.reshape(-1,3);T=hloc[ht]
        def deck(x,z):
            d=__import__('cockpitglass').cast(np.array([x,.28,z]),np.array([[0,-1.,0]]),T[:,0],T[:,1],T[:,2],front_only=False)[0][0]
            assert np.isfinite(d),'real deck under the hatch';return .28-d
        cut_rows=[];cut_ix=[]
        for t in ht:
            poly=np.column_stack([hloc[t][:,0],hloc[t][:,2],apron[t]])  # x,z then the full vertex row
            if poly[:,0].max()<=x0 or poly[:,0].min()>=x1 or poly[:,1].max()<=z0 or poly[:,1].min()>=z1:pieces=[poly]
            else:
                mid=clip(clip(poly,0,x0,1),0,x1,-1);pieces=[clip(poly,0,x0,-1),clip(poly,0,x1,1)]
                if len(mid):pieces+=[clip(mid,1,z0,-1),clip(mid,1,z1,1)]
            for q in pieces:
                if len(q)<3:continue
                start=len(cut_rows);cut_rows.extend(q[:,2:])
                for i in range(1,len(q)-1):cut_ix.extend([start,start+i,start+i+1])
        apron=np.array(cut_rows,dtype=float);apron[:,3:6]/=np.linalg.norm(apron[:,3:6],axis=1)[:,None]
        apron[:,8:11]-=apron[:,3:6]*(apron[:,8:11]*apron[:,3:6]).sum(1)[:,None];apron[:,8:11]/=np.linalg.norm(apron[:,8:11],axis=1)[:,None]
        if 'hood' in cfg:
            # Owner review: the deck nose was blurry at the exterior livery's ~140 px/m. Its own
            # hood texture is mapped top-down in vehicle space: image top = nose, the cream
            # star rows just ahead of the hatch; x spans the full deck (1.24x wider than tall).
            # Tangent = dP/du = -x and cross(n,t) = -dP/dv, the stock hull's convention.
            (hx0,hx1),(hz0,hz1)=cfg['hood']['x'],cfg['hood']['z']
            apron[:,6]=(hx1-apron[:,0])/(hx1-hx0);apron[:,7]=np.minimum((hz1-apron[:,2])/(hz1-hz0),1)
            apron[:,8:11]=[-1,0,0];apron[:,8:11]-=apron[:,3:6]*(apron[:,8:11]*apron[:,3:6]).sum(1)[:,None]
            apron[:,8:11]/=np.linalg.norm(apron[:,8:11],axis=1)[:,None]
        apron=apron.astype('<f4');apronix=np.array(cut_ix,dtype='<u2');parts['CRV/'+cfg['base']+'TankHull']=(apron,apronix)
        # Opening perimeter (front-right, front-left, rear-left, rear-right), sampled so the
        # coaming follows the real deck; one continuous trim strip runs round it (no repeats).
        corners=[(x1,z1),(x0,z1),(x0,z0),(x1,z0)];K=6;loop=[];assert K%2==0,'mosaic cells split walls at s=.5'
        for i in range(4):
            (ax,az),(bx,bz)=corners[i],corners[(i+1)%4]
            for k in range(K):f=k/K;loop.append((ax+(bx-ax)*f,az+(bz-az)*f))
        def out(x,z):return (x+(coam if x>=x1-1e-9 else -coam if x<=x0+1e-9 else 0),z+(coam if z>=z1-1e-9 else -coam if z<=z0+1e-9 else 0))
        lipy=[deck(x,z)+.03 for x,z in loop];base=[min(deck(x,z),deck(*out(x,z)))-.02 for x,z in loop]
        tx0,ty0,tx1,ty1=cfg['charts']['trim'];n=len(loop)
        for i in range(n):
            j=(i+1)%n;(ax,az),(bx,bz)=loop[i],loop[j];(oax,oaz),(obx,obz)=out(ax,az),out(bx,bz)
            va,vb=ty0+(ty1-ty0)*i/n,ty0+(ty1-ty0)*(i+1)/n;mid=np.array([(ax+bx)/2,0,(az+bz)/2])
            face([(oax,base[i],oaz),(obx,base[j],obz),(obx,lipy[j],obz),(oax,lipy[i],oaz)],'trim',hint=mid*[1,0,1],uvs=[(tx0,va),(tx0,vb),(tx0+(tx1-tx0)*.4,vb),(tx0+(tx1-tx0)*.4,va)])
            face([(oax,lipy[i],oaz),(obx,lipy[j],obz),(bx,lipy[j],bz),(ax,lipy[i],az)],'trim',hint=[0,1,0],uvs=[(tx0+(tx1-tx0)*.4,va),(tx0+(tx1-tx0)*.4,vb),(tx1,vb),(tx1,va)])
        # Tub walls: a mosaic of distinct bordered modules from the 1024 atlas, each module on its
        # own cell at ~450-650 px/m (one module stretched over a whole wall was ~300 px/m and
        # read as blurry); no module repeats. Cells are (s0,s1,t0,t1) along the wall / down it,
        # rects in atlas pixels. The console leans back toward the pilot; the rear is behind the head.
        inset=.10
        def lower(x,z):return (x,bottom,z-inset*(z-z0)/(z1-z0))  # front leans back; side walls follow linearly
        MOSAIC=(
            [((0,.5,0,.5),(378,2,566,152)),((.5,1,0,.5),(379,162,566,305)),((0,.5,.5,1),(378,312,566,436)),((.5,1,.5,1),(378,440,566,652))],
            [((0,.5,0,1),(210,4,362,306)),((.5,1,0,1),(210,318,366,704))],
            [((0,1,0,1),tuple(c*1024 for c in cfg['charts']['plate']))],
            [((0,.5,0,1),(210,708,366,1016)),((.5,1,0,1),(778,640,928,1016))])
        for side,cells in enumerate(MOSAIC):
            idx=[side*K+k for k in range(K+1)]
            for k in range(K):
                i,j=idx[k],idx[k+1]%n;(ax,az),(bx,bz)=loop[i],loop[j];la,lb=np.array(lower(ax,az)),np.array(lower(bx,bz))
                ta,tb=np.array([ax,lipy[i],az]),np.array([bx,lipy[j],bz]);sa,sb=k/K,(k+1)/K
                for (c0,c1,r0,r1),(px0,py0,px1,py1) in cells:
                    if sb<=c0+1e-9 or sa>=c1-1e-9:continue
                    def at(s,t):f=(s-sa)/(sb-sa);top=ta+(tb-ta)*f;return top+((la+(lb-la)*f)-top)*t
                    def uv(s,t):return ((px0+(px1-px0)*(s-c0)/(c1-c0))/1024,(py0+(py1-py0)*(t-r0)/(r1-r0))/1024)
                    q=[(sa,r0),(sb,r0),(sb,r1),(sa,r1)]
                    face([at(*p) for p in q],'plate',hint=[-(ax+bx)/2,0,-(az+bz)/2],uvs=[uv(*p) for p in q])
        face([lower(*c) for c in corners],'plate',hint=[0,1,0])
        # Open hatch lid hinged on the rear coaming: its rear plate is the bulkhead behind the
        # head and its top leaf the roof, front edge ~75 deg up (outside the forward view).
        def box(a,b,chart):
            (ax,ay,az),(bx,by,bz)=a,b;c=np.array([(ax+bx)/2,(ay+by)/2,(az+bz)/2])
            for q in ([(ax,ay,az),(bx,ay,az),(bx,by,az),(ax,by,az)],[(ax,ay,bz),(bx,ay,bz),(bx,by,bz),(ax,by,bz)],[(ax,ay,az),(bx,ay,az),(bx,ay,bz),(ax,ay,bz)],[(ax,by,az),(bx,by,az),(bx,by,bz),(ax,by,bz)],[(ax,ay,az),(ax,by,az),(ax,by,bz),(ax,ay,bz)],[(bx,ay,az),(bx,by,az),(bx,by,bz),(bx,ay,bz)]):
                face(q,chart,hint=np.mean(q,0)-c)
        zr=z0-coam;yb=min(lipy[2*K:3*K+1])-.01
        box((x0-coam,yb,zr),(x1+coam,rise+.03,zr+.03),'armor');box((x0-coam,rise,zr+.03),(x1+coam,rise+.03,.08),'armor')
        parts[cfg['material']]=(np.array(rows,dtype='<f4'),np.array(ix,dtype='<u2'))
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
    meta=dict(faction=faction,base=cfg['base'],pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,panels=panels,stockCockpitRetained=faction!='cca',stockReplacedTriangles=replaced if faction in ('nsdf','bdog') else [],stockTriangles=len(stockix)//3,gunWeights=gunweights,gunBones=cfg['gun'],gunOffset=gunoffset.tolist(),apronSourceIndices=np.flatnonzero(mask).tolist(),apronOffset=offset.tolist(),apronTriangles=len(apronix)//3,innerShell=topology,window=dict(width=width,lip=lip,front=front,roof=roof),nativeVdfSha256=__import__('hashlib').sha256(native).hexdigest())
    if grizzly:meta.update(apronTransform=transform.tolist(),apronPitchDegrees=pitch,apronPivotModel=pivot_model.tolist(),**(dict(apronSpreadX=spread) if spread!=1 else {}))
    return parts,s,w,eye,shell,meta

def compile_mesh(parts,s,w,eye,shell,base,meta):
    # CCA shows the real exterior gun running out to the muzzle (where shots
    # spawn); fit the weather glass to the cabin alone so it is not stretched.
    key='CRV/'+base+'TankGuns'
    glass_parts={k:v for k,v in parts.items() if k!=key} if meta['faction']=='cca' else None
    raw,glass=shared.mesh_bytes(parts,s,w,eye,shell,skeleton_name=base+'_cockpit.skeleton',glass_parts=glass_parts)
    mesh=shared.oms.MeshSerializer(io.BytesIO(raw)).read()
    guns=next(sub for sub in mesh.submesh_list if sub.material_name=='CRV/'+base+'TankGuns');guns.clear_bone_assignments()
    for v,b,weight in meta['gunWeights']:guns.create_bone_assignment(v,b,weight)
    out=io.BytesIO();shared.oms.MeshSerializer(out).write(mesh)
    return out.getvalue(),glass
