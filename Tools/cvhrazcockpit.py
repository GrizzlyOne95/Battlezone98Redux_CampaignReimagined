"""CRA heavy-bomber cockpit: open panorama, low flight deck, selected pod caps."""
from collections import Counter
import math
import numpy as np
import reddevilcockpit as shared

MATERIAL='CRV/CVBomberCockpit';PODS='CRV/CVBomberShoulders'
CHARTS={'console':(.02,.02,.98,.32),'pilot':(.02,.36,.48,.64),
        'ordnance':(.52,.36,.98,.64),'frame':(.12,.73,.44,.91),
        'armor':(.55,.70,.95,.77),'trim':(.54,.86,.96,.96)}
POD_FIT=dict(inboard=.35,down=.85,forward=1.30)

def view_coverage(triangles,origin,R):
    """Same one-sided perspective screen sample for before/after, no weather."""
    import cockpitglass as cg
    v=math.tan(math.radians(32));x,y=np.meshgrid(np.linspace(-v*16/9,v*16/9,97),np.linspace(-v,v,55))
    directions=np.column_stack([x.ravel(),y.ravel(),np.ones(x.size)]);directions/=np.linalg.norm(directions,axis=1)[:,None];directions=directions@R.T
    distance,_=cg.cast(origin,directions,triangles[:,0],triangles[:,1],triangles[:,2])
    return float(np.isfinite(distance).mean())

def geometry(source,skeleton_path):
    skeleton,world,eye,shell=shared.rig(skeleton_path,'CPX21BDA');origin,R=world[eye.handle];rows=[];indices=[]
    def face(points,chart='trim',hint=None,uvs=None):
        p=np.asarray(points,float);normal=np.cross(p[1]-p[0],p[2]-p[0]);normal/=np.linalg.norm(normal)
        hint=-p.mean(0) if hint is None else np.asarray(hint,float)
        if np.dot(normal,hint)<0:p=p[::-1];normal=-normal;uvs=None if uvs is None else list(reversed(uvs))
        if uvs is None:
            x0,y0,x1,y1=CHARTS[chart]
            uvs=[(x0,y1),(x1,y1),(x1,y0),(x0,y0)] if len(p)==4 else [(x0+(x1-x0)*(.5+.5*math.cos(2*math.pi*i/len(p))),y0+(y1-y0)*(.5+.5*math.sin(2*math.pi*i/len(p)))) for i in range(len(p))]
        start=len(rows)
        for v,uv in zip(p,uvs):rows.append([*(origin+R@v),*(R@normal),*uv])
        for i in range(1,len(p)-1):indices.extend([start,start+i,start+i+1])
    def beam(a,b,width=.032,depth=.043):
        a=np.asarray(a,float);b=np.asarray(b,float);axis=b-a;axis/=np.linalg.norm(axis)
        across=np.cross(axis,[0,1,0] if abs(axis[1])<.92 else [1,0,0]);across/=np.linalg.norm(across);up=np.cross(axis,across)
        profile=[(-.3,-.5),(.3,-.5),(.5,-.3),(.5,.3),(.3,.5),(-.3,.5),(-.5,.3),(-.5,-.3)]
        rings=[[v+across*x*width+up*y*depth for x,y in profile] for v in (a,b)];c=(a+b)/2
        for i in range(8):j=(i+1)%8;p=[rings[0][i],rings[1][i],rings[1][j],rings[0][j]];face(p,'frame',np.mean(p,0)-c)
        face(rings[0],hint=-axis);face(rings[1],hint=axis)
    # A wide, near-vertical faceted screen: no overhead console wedges, deep
    # central V, centre upright or tall forward keel in the aiming corridor.
    rim=[(-.84,-.48,1.18),(0,-.51,1.50),(.84,-.48,1.18),
         (.96,.42,.98),(.70,.70,.73),(-.70,.70,.73),(-.96,.42,.98)]
    for i in range(len(rim)):beam(rim[i],rim[(i+1)%len(rim)],.030,.041)
    for sign in (-1,1):
        beam((sign*.96,.42,.98),(sign*1.02,.46,-.70),.032,.044)
        beam((sign*.70,.70,.73),(sign*.76,.75,-.70),.027,.039)
        beam((sign*.84,-.48,1.18),(sign*1.02,-.44,-.70),.040,.052)
        # Ochre cheeks carry the outboard pod-root silhouette, below eye level.
        face([(sign*.83,-.49,1.16),(sign*1.00,-.45,-.62),(sign*1.05,-.91,-.48),(sign*.88,-.90,1.08)],'armor')
        face([(sign*.67,-.60,.97),(sign*.91,-.58,.16),(sign*.86,-.92,-.02),(sign*.61,-.93,.77)],'pilot' if sign>0 else 'ordnance')
        beam((sign*.70,-.59,1.00),(sign*.94,-.57,.17),.024,.029)
        # Closed, tapered fairing supports selected outboard shell caps.
        rings=[]
        for c,w,h in [(np.array([sign*.85,-.64,1.12]),.26,.18),(np.array([sign*1.48,-.65,1.63]),.44,.30)]:
            rings.append([c+np.array([dx*w,dy*h,0]) for dx,dy in [(-.5,-.5),(.5,-.5),(.5,.5),(-.5,.5)]])
        c=np.mean(rings,axis=(0,1))
        for i in range(4):j=(i+1)%4;p=[rings[0][i],rings[1][i],rings[1][j],rings[0][j]];face(p,'armor' if i==2 else 'frame',hint=np.mean(p,0)-c)
        face(rings[0],hint=[0,0,-1]);face(rings[1],hint=[0,0,1])
    # One low panoramic flight deck, with a dropped bombardier/arming keel.
    dash=[(-.68,-.50,1.20),(.68,-.50,1.20),(.60,-.88,.80),(-.60,-.88,.80)]
    x0,y0,x1,y1=CHARTS['console'];face(dash,'console',uvs=[(x1,y0),(x0,y0),(x0,y1),(x1,y1)])
    for i in range(4):beam(dash[i],dash[(i+1)%4],.020,.027)
    keel=[(-.23,-.88,.80),(.23,-.88,.80),(.19,-1.12,.06),(-.19,-1.12,.06)]
    # Turn the landscape auxiliary chart into the long keel's portrait axis;
    # keeping its old orientation stretched circular lamps into tall ovals.
    x0,y0,x1,y1=CHARTS['ordnance'];face(keel,'ordnance',uvs=[(x0,y0),(x0,y1),(x1,y1),(x1,y0)])
    for i in (1,3):beam(keel[i],keel[(i+1)%4],.024,.032)
    for sign in (-1,1):face([(sign*.23,-.88,.80),(sign*.19,-1.12,.06),(sign*.25,-1.21,.05),(sign*.30,-1.07,.77)],'frame')
    face([(-.83,-.49,1.18),(0,-.51,1.50),(.83,-.49,1.18),(.68,-.50,1.20),(-.68,-.50,1.20)],'armor',hint=[0,1,0])
    # Connected tub, roof and bulkhead. One intentional wraparound window.
    shell_start=len(indices);rings=[]
    for z,w,lip in [(-.70,1.02,-.44),(.18,.96,-.46),(1.18,.84,-.48)]:
        rings.append([(-w,lip,z),(-w*.98,-.94,z),(-w*.66,-1.28,z),(w*.66,-1.28,z),(w*.98,-.94,z),(w,lip,z)])
    length=np.r_[0,np.cumsum(np.linalg.norm(np.diff(np.array(rings[0]),axis=0),axis=1))];length/=length[-1]
    tx0,ty0,tx1,ty1=CHARTS['trim']
    def tub_uv(i,z):return (tx0+(tx1-tx0)*length[i],ty0+(ty1-ty0)*(1-(z+.70)/1.88))
    for a,b in zip(rings,rings[1:]):
        for i in range(5):face([a[i],b[i],b[i+1],a[i+1]],uvs=[tub_uv(i,a[i][2]),tub_uv(i,b[i][2]),tub_uv(i+1,b[i+1][2]),tub_uv(i+1,a[i+1][2])])
    face(rings[0]);face(rings[-1]+[(0,-.51,1.50)])
    face([rings[0][0],rings[0][-1],(1.02,.46,-.70),(.76,.75,-.70),(-.76,.75,-.70),(-1.02,.46,-.70)])
    face([(-.76,.75,-.70),(.76,.75,-.70),(.70,.70,.73),(-.70,.70,.73)])
    triangles=np.array(rows)[:,:3][np.array(indices[shell_start:]).reshape(-1,3)];edges=Counter()
    for tri in triangles:
        keys=[tuple(np.round(p,6)) for p in tri]
        for i in range(3):edges[tuple(sorted((keys[i],keys[(i+1)%3])))]+=1
    boundary=[e for e,n in edges.items() if n==1];adj={}
    for a,b in boundary:adj.setdefault(a,set()).add(b);adj.setdefault(b,set()).add(a)
    assert max(edges.values())==2 and all(len(v)==2 for v in adj.values());seen=set();todo=[next(iter(adj))]
    while todo:
        p=todo.pop()
        if p not in seen:seen.add(p);todo.extend(adj[p]-seen)
    assert len(seen)==len(adj),'unintended separate enclosure opening'
    parts={MATERIAL:(np.array(rows,dtype='<f4'),np.array(indices,dtype='<u2'))}
    # Whole front/inner pod-cap triangles, not the GR hardpoint marker cubes.
    body=shared.read_mesh(source).submesh_list[0];vd=body.vertex_data;p=shared.values(vd,shared.om.VES.POSITION);n=shared.values(vd,shared.om.VES.NORMAL);uv=shared.values(vd,shared.om.VES.TEXTURE_COORDINATES);tri=body.index_array.reshape(-1,3);q=p[tri]
    weight=np.zeros(len(p))
    for a in body.bone_assignments():
        if a.bone_index in (1,2):weight[a.vertex_index]+=a.weight
    keep=(weight[tri]>.99).all(1)&(np.abs(q[:,:,0]).min(1)>1.55)&(np.abs(q[:,:,0]).min(1)<2.2)&(q[:,:,2].min(1)>-.15)&(q[:,:,2].max(1)>.60)&(q[:,:,1].min(1)>1.30)
    selected=tri[keep];used,remap=np.unique(selected,return_inverse=True);positions=p[used].copy();local=(positions-origin)@R
    local[:,0]-=np.sign(local[:,0])*POD_FIT['inboard'];local[:,1]-=POD_FIT['down'];local[:,2]+=POD_FIT['forward'];positions=origin+local@R.T
    normal=n[used];t=shared.values(vd,shared.om.VES.TANGENT)[used,:3];t-=normal*(t*normal).sum(1)[:,None]
    for i in np.flatnonzero(np.linalg.norm(t,axis=1)<1e-8):t[i]=np.cross(np.eye(3)[np.argmin(np.abs(normal[i]))],normal[i])
    t/=np.linalg.norm(t,axis=1)[:,None];parts[PODS]=(np.column_stack([positions,normal,uv[used],t]).astype('<f4'),remap.astype('<u2').reshape(-1));assert len(selected)>0
    meta=dict(pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,podTriangles=len(selected),podSourceIndices=np.flatnonzero(keep).tolist(),podPlacement=POD_FIT,rim=np.array(rim).tolist(),innerShell=dict(triangles=len(triangles),boundaryEdges=len(boundary),boundaryLoops=1))
    return parts,skeleton,world,eye,shell,meta
