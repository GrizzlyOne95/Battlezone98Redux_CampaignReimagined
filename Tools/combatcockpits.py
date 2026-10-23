"""Five combat-only cockpit prototypes; shared codecs, faction art, fitted hardware."""
from collections import Counter
import math
import numpy as np
import reddevilcockpit as shared
import tankcockpits as tank
import scoutcockpits as scout
import cvhrazcockpit as bomber

CCA_CHARTS={'console':(.02,.02,.98,.30),'switch':(.02,.34,.48,.64),'service':(.52,.34,.98,.64),'armor':(.02,.68,.48,.98),'frame':(.52,.68,.98,.80),'trim':(.52,.84,.98,.98)}
CRA_CHARTS={**bomber.CHARTS,'switch':bomber.CHARTS['pilot'],'service':bomber.CHARTS['ordnance']}
# Ratios of the original bitmap crops, before atlas repacking. A square UV
# allocation need not contain square artwork: never fit dials to a trapezoid.
ART_ASPECT={
 'cca':{'console':1219/306,'switch':566/461,'service':618/461},
 'cra':{'console':.96/.30,'switch':.46/.28,'service':.46/.28},
 'nsdf':{'console':1218/296,'switch':595/385,'service':588/385},
 'bdog':{'console':1218/279,'switch':596/476,'service':588/476}}
CONFIG={
 'cvturr':dict(faction='cra',role='turret',shell='CAD21BDA',batch=1,material='CRV/CVBomberCockpit',charts=CRA_CHARTS,stock='cvturr01',exterior='cvturr',width=.86,lip=-.40,front=1.10,roof=.66,back=-.64),
 'svfigh':dict(faction='cca',role='fighter',shell='SFL21bda',batch=2,material='CRV/CCAMechanicalCockpit',charts=CCA_CHARTS,stock='svfigh01',exterior='svfigh00',width=.72,lip=-.38,front=1.07,roof=.54,back=-.54),
 'svltnk':dict(faction='cca',role='lighttank',shell='slt21ckp',batch=2,material='CRV/CCAMechanicalCockpit',charts=CCA_CHARTS,stock='svltnk01',exterior='svltnk00',width=.78,lip=-.44,front=1.34,roof=.59,back=-.60),
 'avhraz':dict(faction='nsdf',role='bomber',shell='ahr21bda',batch=2,material='CRV/NSDFScoutCockpit',charts=scout.CHARTS,stock='avhraz01',exterior='avhraz00',width=.98,lip=-.48,front=1.37,roof=.76,back=-.72),
 'bvhraz':dict(faction='bdog',role='bomber',shell='bhr21bda',batch=2,material='CRV/BDogScoutCockpit',charts=scout.CHARTS,stock='bvhraz01',exterior='bvhraz00',width=.98,lip=-.48,front=1.37,roof=.76,back=-.72)}

class Hardware:
    def __init__(self,origin,R,charts,aspects=None):self.origin=origin;self.R=R;self.charts=charts;self.aspects=aspects or {};self.rows=[];self.ix=[];self.panels=[]
    def face(self,points,chart='trim',hint=None,uvs=None):
        p=np.array(points,float);n=np.cross(p[1]-p[0],p[2]-p[0]);n/=np.linalg.norm(n);hint=-p.mean(0) if hint is None else np.array(hint)
        if np.dot(n,hint)<0:p=p[::-1];n=-n;uvs=None if uvs is None else list(reversed(uvs))
        x0,y0,x1,y1=self.charts[chart]
        if uvs is None:uvs=[(x1,y0),(x0,y0),(x0,y1),(x1,y1)] if len(p)==4 else [(x0+(x1-x0)*(.5+.5*math.cos(i*2*math.pi/len(p))),y0+(y1-y0)*(.5+.5*math.sin(i*2*math.pi/len(p)))) for i in range(len(p))]
        start=len(self.rows)
        for v,uv in zip(p,uvs):self.rows.append([*(self.origin+self.R@v),*(self.R@n),*uv])
        for i in range(1,len(p)-1):self.ix.extend([start,start+i,start+i+1])
    def beam(self,a,b,width=.032,chart='frame'):
        a=np.array(a,float);b=np.array(b,float);axis=b-a;axis/=np.linalg.norm(axis);u=np.cross(axis,[0,1,0] if abs(axis[1])<.9 else [1,0,0]);u/=np.linalg.norm(u);v=np.cross(axis,u)
        profile=[(-.3,-.5),(.3,-.5),(.5,-.3),(.5,.3),(.3,.5),(-.3,.5),(-.5,.3),(-.5,-.3)]
        rings=[[p+u*x*width+v*y*width for x,y in profile] for p in (a,b)];c=(a+b)/2
        for i in range(8):j=(i+1)%8;p=[rings[0][i],rings[1][i],rings[1][j],rings[0][j]];self.face(p,chart,np.mean(p,0)-c)
        self.face(rings[0],'trim',-axis);self.face(rings[1],'trim',axis)
    def cassette(self,p,chart='console',depth=.035,section=None):
        p=np.array(p,float);c=p.mean(0);_,_,axes=np.linalg.svd(p-c);n=axes[-1]
        # Project the authored corner profile to one physical mounting plane.
        # A warped rear quad can cut through its own recessed instrument face.
        p-=(p-c)@n[:,None]*n[None,:]
        if np.dot(n,-c)<0:n=-n
        # Closed wedge housing, recessed glass and a positive-thickness bezel.
        front=c+(p-c)*.94+n*depth;inside=front.mean(0)+(front-front.mean(0))*.92-n*.006
        for i in range(4):
            j=(i+1)%4;self.face([p[i],p[j],front[j],front[i]],'armor',hint=np.mean([p[i],front[j]],axis=0)-c);self.face([front[i],front[j],inside[j],inside[i]],'trim',hint=n)
            self.beam(front[i],front[j],.009,'frame')
        self.face(p,'trim',hint=-n)
        x0,y0,x1,y1=self.charts[chart]
        if section is not None:a,b=section;x0,x1=x0+(x1-x0)*a,x0+(x1-x0)*b
        aspect=self.aspects.get(chart,(x1-x0)/(y1-y0))*(1 if section is None else section[1]-section[0])
        # Largest centered rectangular insert within the convex housing. Keep
        # its physical axes orthogonal and its aspect equal to source artwork;
        # the surrounding tapered area is plain metal, not skewed instruments.
        center=inside.mean(0);u=inside[1]-inside[0];u/=np.linalg.norm(u)
        v=inside[3]-inside[0];v-=u*np.dot(u,v);v/=np.linalg.norm(v)
        corners=np.array([-u*aspect-v,u*aspect-v,u*aspect+v,-u*aspect+v])*.5
        scale=float('inf')
        for i in range(4):
            edge=inside[(i+1)%4]-inside[i];inward=np.cross(n,edge)
            if np.dot(inward,center-inside[i])<0:inward=-inward
            distance=np.dot(inward,center-inside[i]);limit=-(corners@inward).min()
            if limit>1e-12:scale=min(scale,distance/limit)
        instrument=center+corners*scale*.96
        for i in range(4):j=(i+1)%4;self.face([inside[i],inside[j],instrument[j],instrument[i]],'armor',hint=n)
        self.face(instrument,chart,uvs=[(x1,y0),(x0,y0),(x0,y1),(x1,y1)])
        # Tangible screw caps at the four corners (no embossed huge bolts).
        u=p[1]-p[0];u/=np.linalg.norm(u);v=np.cross(n,u)
        for corner in front:
            at=front.mean(0)+(corner-front.mean(0))*.96+n*.001;r=.004
            cap=[at+r*(math.cos(i*math.pi/4)*u+math.sin(i*math.pi/4)*v) for i in range(8)];self.face(cap,'frame',hint=n)
            for i in range(8):j=(i+1)%8;self.face([cap[i],cap[j],cap[j]-n*.003,cap[i]-n*.003],'trim',hint=cap[i]-at)
        self.panels.append(dict(chart=chart,points=p.tolist(),depth=depth,section=section,instrumentPoints=instrument.tolist(),sourceAspect=aspect))
    def fairing(self,a,b,width=.28,height=.15):
        rings=[]
        for c in (np.array(a),np.array(b)):rings.append([c+[x*width,y*height,0] for x,y in [(-.5,-.5),(.5,-.5),(.5,.5),(-.5,.5)]])
        c=np.mean(rings,axis=(0,1))
        for i in range(4):j=(i+1)%4;p=[rings[0][i],rings[1][i],rings[1][j],rings[0][j]];self.face(p,'armor' if i==2 else 'trim',hint=np.mean(p,0)-c)
        self.face(rings[0],hint=[0,0,-1]);self.face(rings[1],hint=[0,0,1])
    def enclosure(self,cfg):
        start=len(self.ix);w=cfg['width'];lip=cfg['lip'];front=cfg['front'];back=cfg['back'];roof=cfg['roof'];floor=-1.15 if cfg['role']=='bomber' else -.98
        rings=[]
        for z,width in [(back,w*1.08),(.15,w*1.03),(front,w)]:rings.append([(-width,lip,z),(-width*.98,floor*.72,z),(-width*.66,floor,z),(width*.66,floor,z),(width*.98,floor*.72,z),(width,lip,z)])
        length=np.r_[0,np.cumsum(np.linalg.norm(np.diff(np.array(rings[0]),axis=0),axis=1))];length/=length[-1];tx0,ty0,tx1,ty1=self.charts['trim']
        def uv(i,z):return (tx0+(tx1-tx0)*length[i],ty0+(ty1-ty0)*(z-back)/(front-back))
        for a,b in zip(rings,rings[1:]):
            for i in range(5):self.face([a[i],b[i],b[i+1],a[i+1]],uvs=[uv(i,a[i][2]),uv(i,b[i][2]),uv(i+1,b[i+1][2]),uv(i+1,a[i+1][2])])
        self.face(rings[0]);self.face(rings[-1]);self.face([rings[0][0],rings[0][-1],(w*1.08,roof,back),(-w*1.08,roof,back)])
        self.face([(-w*1.08,roof,back),(w*1.08,roof,back),(w*.63,roof,front*.30),(-w*.63,roof,front*.30)])
        # Prove this inner liner has only the single intended canopy opening.
        tris=np.array(self.rows)[:,:3][np.array(self.ix[start:]).reshape(-1,3)];edges=Counter()
        for tri in tris:
            keys=[tuple(np.round(p,6)) for p in tri]
            for i in range(3):edges[tuple(sorted((keys[i],keys[(i+1)%3])))]+=1
        boundary=[e for e,n in edges.items() if n==1];adj={}
        for a,b in boundary:adj.setdefault(a,set()).add(b);adj.setdefault(b,set()).add(a)
        assert max(edges.values())==2 and all(len(v)==2 for v in adj.values());seen=set();todo=[next(iter(adj))]
        while todo:
            p=todo.pop()
            if p not in seen:seen.add(p);todo.extend(adj[p]-seen)
        assert len(seen)==len(adj)
        return dict(triangles=len(tris),boundaryLoops=1,boundaryEdges=len(boundary))
    def part(self):return np.array(self.rows,dtype='<f4'),np.array(self.ix,dtype='<u2')

def geometry(source,skelpath,base,game,root):
    cfg=CONFIG[base];s,w,eye,shell=shared.rig(skelpath,cfg['shell']);native=tank.native_eye(w,eye,game,base,root);origin,R=w[eye.handle];h=Hardware(origin,R,cfg['charts'],ART_ASPECT[cfg['faction']]);role=cfg['role'];width=cfg['width'];front=cfg['front'];lip=cfg['lip'];roof=cfg['roof']
    # Different structural silhouettes, not a generic shared canopy.
    if role=='turret':
        rim=[(-.86,-.40,1.10),(.86,-.40,1.10),(.93,.34,.62),(.57,.65,.39),(-.57,.65,.39),(-.93,.34,.62)]
        # Two low independent fire-control stations and a dropped selector bank.
        for sign in (-1,1):
            h.cassette([(sign*.13,-.42,1.04),(sign*.73,-.39,.98),(sign*.71,-.67,.61),(sign*.16,-.69,.66)],'switch' if sign>0 else 'service',.04)
            h.beam((sign*.91,.32,.63),(sign*1.00,.38,-.64),.038)
        h.cassette([(-.15,-.71,.64),(.15,-.71,.64),(.13,-.88,.15),(-.13,-.88,.15)],'service',.028)
    elif role=='fighter':
        rim=[(-.72,-.38,1.07),(0,-.41,1.36),(.72,-.38,1.07),(.81,.16,.66),(.44,.53,.30),(-.44,.53,.30),(-.81,.16,.66)]
        h.cassette([(-.55,-.40,1.04),(.55,-.40,1.04),(.49,-.68,.72),(-.49,-.68,.72)],'console',.032)
        for sign in (-1,1):
            h.cassette([(sign*.54,-.48,.72),(sign*.70,-.46,.12),(sign*.65,-.72,-.09),(sign*.47,-.72,.48)],'switch' if sign>0 else 'service',.022)
            h.fairing((sign*.65,-.47,1.04),(sign*1.04,-.54,1.53),.22,.18)
            h.beam((sign*.81,.16,.66),(sign*.82,.24,-.54),.030)
    elif role=='lighttank':
        rim=[(-.78,-.44,1.34),(0,-.47,1.50),(.78,-.44,1.34),(.89,.29,.78),(.48,.58,.48),(-.48,.58,.48),(-.89,.29,.78)]
        # Characteristic armored asymmetric work stations, no giant X over aim.
        h.cassette([(-.60,-.47,1.29),(.18,-.47,1.29),(.17,-.70,.91),(-.56,-.70,.91)],'console',.045,section=(0,.64))
        h.cassette([(.24,-.48,1.27),(.66,-.43,1.16),(.63,-.76,.78),(.25,-.76,.91)],'switch',.045)
        for sign in (-1,1):
            h.cassette([(sign*.62,-.52,.87),(sign*.79,-.47,.15),(sign*.76,-.77,-.10),(sign*.54,-.79,.60)],'service' if sign>0 else 'switch',.025)
            h.beam((sign*.89,.29,.78),(sign*.88,.35,-.60),.038)
        h.fairing((-.85,-.58,.40),(-1.36,-.47,.90),.78,.26)
    else:
        # Thunderbolt: a tall tapered bomber screen and split side desks keep
        # its angular, open bomb-aiming pit; the scout canopy is not reused.
        rim=[(-.98,-.48,1.37),(0,-.45,1.64),(.98,-.48,1.37),(1.03,.20,.94),(.48,.75,.58),(-.48,.75,.58),(-1.03,.20,.94)]
        for sign in (-1,1):
            h.cassette([(sign*.19,-.49,1.35),(sign*.81,-.47,1.18),(sign*.77,-.79,.73),(sign*.17,-.80,.91)],'console',.035,section=(0,.33) if sign>0 else (.70,1.))
            h.cassette([(sign*.77,-.54,.75),(sign*.94,-.49,-.04),(sign*.88,-.88,-.28),(sign*.64,-.91,.52)],'switch' if sign>0 else 'service',.03)
            h.beam((sign*1.03,.20,.94),(sign*1.06,.31,-.72),.036)
            h.beam((sign*.48,.75,.58),(sign*.60,.82,-.72),.029)
            h.fairing((sign*.85,-.55,1.27),(sign*1.36,-.66,1.87),.30,.18)
        h.cassette([(-.17,-.84,.90),(.17,-.84,.90),(.14,-1.03,.10),(-.14,-1.03,.10)],'service',.025)
    for i in range(len(rim)):h.beam(rim[i],rim[(i+1)%len(rim)],.031 if role!='lighttank' else .041)
    for sign in (-1,1):
        h.beam((sign*width,lip,front),(sign*width*1.08,lip,cfg['back']),.043)
        h.beam((sign*width*.63,roof,front*.30),(sign*width*1.08,roof,cfg['back']),.031)
    topology=h.enclosure(cfg)
    # Closed bridge behind the selected exterior cut. No sky crack behind nose.
    h.fairing((0,lip-.055,front),(0,lip-.18,front+.72),width*2,.12)
    parts={cfg['material']:h.part()}
    # Small warning strips reuse the stock cockpit paint, without duplicating
    # its instruments or stretching a single stripe over a whole pillar.
    hazard=(.166,.20,.313,.94) if cfg['faction'] in ('nsdf','bdog') else ((.008,.025,.180,.96) if cfg['faction']=='cca' else (.006,.01,.130,.96))
    legacy=Hardware(origin,R,{'trim':hazard})
    for sign in (-1,1):
        if role=='bomber':points=[(sign*.963,-.47,1.358),(sign*1.002,-.47,1.358),(sign*1.023,-.16,1.145),(sign*.984,-.16,1.145)]
        else:points=[(sign*(width-.12),lip-.018,front+.04),(sign*(width-.055),lip-.018,front+.04),(sign*(width-.055),lip-.080,front+.26),(sign*(width-.12),lip-.080,front+.26)]
        legacy.face(points)
    parts[cfg['stock']]=legacy.part()
    body=shared.read_mesh(source).submesh_list[0];p=shared.values(body.vertex_data,shared.om.VES.POSITION);tri=body.index_array.reshape(-1,3);q=p[tri];pieces=[];exterior=[];indices=[];weights=list(body.bone_assignments())
    def piece(label,bones,mask,pitch=0,target_top=None,near=None,inboard=0,cap_rear=False):
        boneweight=np.zeros(len(p))
        for a in weights:
            if a.bone_index in bones:boneweight[a.vertex_index]+=a.weight
        area2=np.linalg.norm(np.cross(q[:,1]-q[:,0],q[:,2]-q[:,0]),axis=1)
        keep=(boneweight[tri]>.99).all(1)&mask&(area2>1e-9);data,ix,used=tank.source_part(body,keep);assert len(ix)>0,label
        angle=math.radians(pitch);c,ss=math.cos(angle),math.sin(angle);rot=np.array([[1,0,0],[0,c,-ss],[0,ss,c]],float);local=(data[:,:3]-origin)@R;center=np.array([0.,0.,local[:,2].min()]);local=(local-center)@rot.T+center
        delta=np.array([-np.sign(local[:,0].mean())*inboard,0 if target_top is None else target_top-local[:,1].max(),0 if near is None else near-local[:,2].min()]);T=np.eye(4);T[:3,:3]=R@rot@R.T;T[:3,3]=origin+R@(center-rot@center+delta)-T[:3,:3]@origin
        data[:,:3]=data[:,:3]@T[:3,:3].T+T[:3,3];data[:,3:6]=data[:,3:6]@T[:3,:3].T;data[:,8:11]=data[:,8:11]@T[:3,:3].T
        caps=[]
        if cap_rear:
            # Source cannon is open on its normally buried rear mounting plane.
            # Close each real boundary loop, rather than hiding it two-sided.
            edge_counts=Counter();points={}
            for face in data[ix.reshape(-1,3),:3]:
                keys=[tuple(np.rint(v*10000).astype(np.int64)) for v in face]
                points.update(zip(keys,face))
                for i in range(3):edge_counts[tuple(sorted((keys[i],keys[(i+1)%3])))]+=1
            edges={edge for edge,count in edge_counts.items() if count==1};adj={}
            for a,b in edges:adj.setdefault(a,set()).add(b);adj.setdefault(b,set()).add(a)
            assert all(len(neighbors)==2 for neighbors in adj.values()),'rear cap must have simple closed boundary loops'
            while edges:
                a,b=next(iter(edges));loop=[a];previous=a;current=b;edges.remove(tuple(sorted((a,b))))
                while current!=loop[0]:
                    loop.append(current);nxt=next(x for x in adj[current] if x!=previous);edges.remove(tuple(sorted((current,nxt))));previous,current=current,nxt
                polygon=np.array([points[key] for key in loop]);localpoly=(polygon-origin)@R
                assert np.ptp(localpoly[:,2])<1e-4,'only planar rear mount openings are capped'
                h.face(localpoly,'armor',hint=[0,0,-1]);caps.append(localpoly.tolist())
        indices.extend((ix+sum(len(x) for x in exterior)).tolist());exterior.append(data);pieces.append(dict(label=label,bones=bones,sourceIndices=np.flatnonzero(keep).tolist(),transform=T.tolist(),triangles=len(ix)//3,rearCaps=caps))
    if role=='turret':
        # Four guns flank the eye: one high and one low on each side. Keep
        # the complete pod geometry at native coordinates, not on the sill.
        for sign,bone in [(1,4),(-1,7)]:piece('native '+str(sign)+' high/low gun pod',[bone],np.ones(len(tri),bool))
    elif role=='fighter':piece('Flanker gun/fuselage nose',[4],q[:,:,2].min(1)>1.50,-10,-.47,1.18)
    elif role=='lighttank':
        piece('Stoli front glacis',[1],q[:,:,2].min(1)>2.50,-8,-.56,1.55)
        piece('Stoli side cannon, native position',[2],np.ones(len(tri),bool),cap_rear=True)
    else:piece('Thunderbolt sloped bow',[1],q[:,:,2].min(1)>3.25,-16,-.36,1.62)
    parts['CRV/'+base+'CombatExterior']=(np.concatenate(exterior),np.array(indices,dtype='<u2'))
    parts[cfg['material']]=h.part()
    meta=dict(base=base,role=role,pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,innerShell=topology,rim=rim,panels=h.panels,exteriorPieces=pieces,nativeVdfSha256=__import__('hashlib').sha256(native).hexdigest())
    return parts,s,w,eye,shell,meta
