"""Stock-grounded Razor scout cockpits with faction art and original nose pieces."""
from collections import Counter
import math
import numpy as np
import reddevilcockpit as shared

CHARTS={'console':(.02,.02,.98,.34),'switch':(.02,.38,.48,.64),
        'service':(.52,.38,.98,.64),'armor':(.02,.68,.48,.98),
        'frame':(.52,.68,.98,.80),'trim':(.52,.84,.98,.98)}
CONFIG={
    'nsdf':dict(base='avfigh',shell='ara21bda',material='CRV/NSDFScoutCockpit',nose='CRV/NSDFScoutNose',stem='crvascp',noseBone=2,cockpitBatch=2,front=1.03,eye=[-.004399999976158142,1.467507004737854,.7488619983196259]),
    'bdog':dict(base='bvraz',shell='bra21bda',material='CRV/BDogScoutCockpit',nose='CRV/BDogScoutNose',stem='crvbscp',noseBone=1,cockpitBatch=1,front=.91,eye=[-.004399999976158142,1.467507004737854,.8566620051860809])}

# Largest nose roll: full strafe with rollStrafRotator[1]=0.4 (all_decompiled.c:195005),
# x3 per HoverCraft::UpdateGimbals (:193638). When the engine picks index 1 is UNVERIFIED.
ROLL_DEG=23.6


def roll_matrix(axis,angle):
    k=np.array([[0,-axis[2],axis[1]],[axis[2],0,-axis[0]],[-axis[1],axis[0],0]])
    return np.eye(3)+np.sin(angle)*k+(1-np.cos(angle))*k@k


def convex_hull(points):
    """Counter-clockwise 2-D hull (monotone chain)."""
    pts=sorted(set(map(tuple,np.round(points,6))))
    def half(seq):
        out=[]
        for q in seq:
            while len(out)>1 and (out[-1][0]-out[-2][0])*(q[1]-out[-2][1])-(out[-1][1]-out[-2][1])*(q[0]-out[-2][0])<=0:out.pop()
            out.append(q)
        return out[:-1]
    return np.array(half(pts)+half(pts[::-1]))

def bones(parts,cfg,shell,meta):
    """Per-vertex bones: shell for the interior and hull bulkhead, rof bone for the nose."""
    return {cfg['material']:np.full(len(parts[cfg['material']][0]),shell.handle),cfg['nose']:np.full(len(parts[cfg['nose']][0]),cfg['noseBone'])}

def geometry(source,skeleton_path,faction):
    cfg=CONFIG[faction];skeleton,world,eye,shell=shared.rig(skeleton_path,cfg['shell']);origin,R=world[eye.handle];rows=[];indices=[]
    # The tub front sits just behind this faction's native nose root (Black Dog's
    # starts 0.12 m nearer the eye), so the forward half is scaled in depth to it.
    k=(cfg['front']-.17)/(1.03-.17)
    def face(points,chart='trim',hint=None,uvs=None):
        p=np.array(points,float);p[:,2]=np.where(p[:,2]>.17,.17+(p[:,2]-.17)*k,p[:,2]);normal=np.cross(p[1]-p[0],p[2]-p[0]);normal/=np.linalg.norm(normal)
        hint=-p.mean(0) if hint is None else np.asarray(hint,float)
        if np.dot(normal,hint)<0:p=p[::-1];normal=-normal;uvs=None if uvs is None else list(reversed(uvs))
        if uvs is None:
            x0,y0,x1,y1=CHARTS[chart]
            uvs=[(x0,y1),(x1,y1),(x1,y0),(x0,y0)] if len(p)==4 else [(x0+(x1-x0)*(.5+.5*math.cos(2*math.pi*i/len(p))),y0+(y1-y0)*(.5+.5*math.sin(2*math.pi*i/len(p)))) for i in range(len(p))]
        start=len(rows)
        for v,uv in zip(p,uvs):rows.append([*(origin+R@v),*(R@normal),*uv])
        for i in range(1,len(p)-1):indices.extend([start,start+i,start+i+1])
    def beam(a,b,width=.038,depth=.050):
        a=np.asarray(a,float);b=np.asarray(b,float);axis=b-a;axis/=np.linalg.norm(axis)
        across=np.cross(axis,[0,1,0] if abs(axis[1])<.92 else [1,0,0]);across/=np.linalg.norm(across);up=np.cross(axis,across)
        section=[(-.3,-.5),(.3,-.5),(.5,-.3),(.5,.3),(.3,.5),(-.3,.5),(-.5,.3),(-.5,-.3)]
        rings=[[v+across*x*width+up*y*depth for x,y in section] for v in (a,b)];c=(a+b)/2
        for i in range(8):j=(i+1)%8;p=[rings[0][i],rings[1][i],rings[1][j],rings[0][j]];face(p,'frame' if i in (0,4) else 'armor',np.mean(p,0)-c)
        face(rings[0],hint=-axis);face(rings[1],hint=axis)
    # Compact Razor canopy: a low pointed windscreen and rearward-swept cheek
    # posts follow the ship, retaining thick mechanical seals rather than a
    # generic panoramic glass bubble or floating HUD.
    # The windscreen sill is notched down over the nose so the real ROF nose
    # (native position, ~18-24 degrees below the horizon) reads past it.
    notch=[(-.40,-.60,1.03),(.40,-.60,1.03)]
    rim=[(-.65,-.40,1.03),*notch,(.65,-.40,1.03),
         (.70,.12,.71),(.43,.52,.30),(0,.57,.38),(-.43,.52,.30),(-.70,.12,.71)]
    for i in range(len(rim)):beam(rim[i],rim[(i+1)%len(rim)],.038,.050)
    # Narrow inner charcoal gasket remains a visible mechanical seam.
    for sign in (-1,1):
        beam((sign*.70,.12,.71),(sign*.78,.20,-.57),.044,.058)
        beam((sign*.43,.52,.30),(sign*.52,.59,-.57),.032,.047)
        beam((sign*.65,-.40,1.03),(sign*.78,-.36,-.57),.050,.060)
        face([(sign*.65,-.42,1.02),(sign*.76,-.38,-.49),(sign*.81,-.77,-.43),(sign*.71,-.77,.96)],'armor')
        face([(sign*.48,-.53,.87),(sign*.70,-.49,.17),(sign*.68,-.77,-.03),(sign*.44,-.82,.66)],'switch' if sign>0 else 'service')
        beam((sign*.51,-.51,.89),(sign*.73,-.47,.18),.026,.032)
    # Low squat mechanical console, not a glass instrument wall, kept under the
    # sill notch. Lower center spine echoes the stock Razor's controls.
    dash=[(-.51,-.62,1.00),(.51,-.62,1.00),(.46,-.84,.80),(-.46,-.84,.80)]
    x0,y0,x1,y1=CHARTS['console'];face(dash,'console',uvs=[(x1,y0),(x0,y0),(x0,y1),(x1,y1)])
    for i in range(4):beam(dash[i],dash[(i+1)%4],.025,.034)
    keel=[(-.14,-.85,.79),(.14,-.85,.79),(.12,-1.01,.12),(-.12,-1.01,.12)]
    x0,y0,x1,y1=CHARTS['service'];face(keel,'service',uvs=[(x0,y0),(x0,y1),(x1,y1),(x1,y0)])
    for i in (1,3):beam(keel[i],keel[(i+1)%4],.025,.030)
    # One closed, continuously unwrapped tub with a single intentional window.
    shell_start=len(indices);rings=[]
    for z,w,lip in [(-.57,.78,-.36),(.17,.73,-.38),(1.03,.65,-.40)]:
        rings.append([(-w,lip,z),(-w*.97,-.80,z),(-w*.65,-1.11,z),(w*.65,-1.11,z),(w*.97,-.80,z),(w,lip,z)])
    length=np.r_[0,np.cumsum(np.linalg.norm(np.diff(np.array(rings[0]),axis=0),axis=1))];length/=length[-1];tx0,ty0,tx1,ty1=CHARTS['trim']
    def tuv(i,z):return (tx0+(tx1-tx0)*length[i],ty0+(ty1-ty0)*(1-(z+.57)/1.60))
    for a,b in zip(rings,rings[1:]):
        for i in range(5):face([a[i],b[i],b[i+1],a[i+1]],uvs=[tuv(i,a[i][2]),tuv(i,b[i][2]),tuv(i+1,b[i+1][2]),tuv(i+1,a[i+1][2])])
    face(rings[0]);r=rings[-1]
    # Front wall closes up to the notched sill in three convex pieces.
    face([r[0],r[1],r[2],notch[0]]);face([notch[0],r[2],r[3],notch[1]]);face([notch[1],r[3],r[4],r[5]])
    face([rings[0][0],rings[0][-1],(.78,.20,-.57),(.52,.59,-.57),(-.52,.59,-.57),(-.78,.20,-.57)])
    face([(-.52,.59,-.57),(.52,.59,-.57),(.43,.52,.30),(0,.57,.38),(-.43,.52,.30)])
    tris=np.array(rows)[:,:3][np.array(indices[shell_start:]).reshape(-1,3)];edges=Counter()
    for tri in tris:
        keys=[tuple(np.round(p,6)) for p in tri]
        for i in range(3):edges[tuple(sorted((keys[i],keys[(i+1)%3])))]+=1
    boundary=[e for e,n in edges.items() if n==1];adj={}
    for a,b in boundary:adj.setdefault(a,set()).add(b);adj.setdefault(b,set()).add(a)
    assert max(edges.values())==2 and all(len(v)==2 for v in adj.values());seen=set();todo=[next(iter(adj))]
    while todo:
        p=todo.pop()
        if p not in seen:seen.add(p);todo.extend(adj[p]-seen)
    assert len(seen)==len(adj),'unintended separate shell opening'
    parts={}
    # The entire original ROF nose piece (VDF class 66, rolled by the engine
    # every frame) at its native position, skinned whole to its own bone so
    # it moves as the exterior does. Preserve source UVs, normals and shape.
    body=shared.read_mesh(source).submesh_list[0];vd=body.vertex_data;p=shared.values(vd,shared.om.VES.POSITION);n=shared.values(vd,shared.om.VES.NORMAL);uv=shared.values(vd,shared.om.VES.TEXTURE_COORDINATES);tri=body.index_array.reshape(-1,3);weight=np.zeros(len(p))
    for a in body.bone_assignments():
        if a.bone_index==cfg['noseBone']:weight[a.vertex_index]+=a.weight
    keep=(weight[tri]>.99).all(1);selected=tri[keep];used,remap=np.unique(selected,return_inverse=True);positions=p[used]
    normal=n[used];t=shared.values(vd,shared.om.VES.TANGENT)[used,:3].copy();t-=normal*(t*normal).sum(1)[:,None]
    for i in np.flatnonzero(np.linalg.norm(t,axis=1)<1e-8):t[i]=np.cross(np.eye(3)[np.argmin(np.abs(normal[i]))],normal[i])
    t/=np.linalg.norm(t,axis=1)[:,None];parts[cfg['nose']]=(np.column_stack([positions,normal,uv[used],t]).astype('<f4'),remap.astype('<u2').reshape(-1));assert len(selected)>100
    # On the exterior the nose's open rear is buried in the hull; from the eye it
    # would read as hollow. Close it with the static hull bulkhead the nose rolls
    # against (as Total Command's scout does), its armour lip proud of the rim so
    # the tub reads as continuing into the main hull.
    # The engine rolls the nose about its bone z (all_decompiled.c:193638-193641), up to
    # ROLL_DEG at full strafe, so the bulkhead covers the rim swept through that roll.
    local=(positions-origin)@R;zmin=local[:,2].min();rear=local[local[:,2]<zmin+.03]
    bone_origin,bone_basis=world[cfg['noseBone']];pivot=(bone_origin-origin)@R;axis=R.T@bone_basis[:,2];axis/=np.linalg.norm(axis)
    swept=np.concatenate([(rear-pivot)@roll_matrix(axis,a).T+pivot for a in np.radians(np.linspace(-ROLL_DEG,ROLL_DEG,25))])
    hull=convex_hull(swept[:,:2]);hull=hull.mean(0)+(hull-hull.mean(0))*1.01;lo,hi=hull.min(0),hull.max(0)
    cap_start=len(rows);x0,y0,x1,y1=CHARTS['armor']
    for x,y in hull:rows.append([*(origin+R@np.array([x,y,zmin-.008])),*(R@np.array([0.,0,-1])),x0+(x1-x0)*(x-lo[0])/(hi[0]-lo[0]),y0+(y1-y0)*(y-lo[1])/(hi[1]-lo[1])])
    for i in range(1,len(hull)-1):indices.extend([cap_start,cap_start+i+1,cap_start+i])
    parts={cfg['material']:(np.array(rows,dtype='<f4'),np.array(indices,dtype='<u2')),cfg['nose']:parts[cfg['nose']]}
    meta=dict(faction=faction,base=cfg['base'],pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,noseTriangles=len(selected),noseBone=cfg['noseBone'],noseSourceIndices=np.flatnonzero(keep).tolist(),nosePlacement='native',noseSkin=cfg['noseBone'],tubFront=cfg['front'],noseCap=dict(firstVertex=cap_start,vertices=len(hull),triangles=len(hull)-2),rim=np.array(rim).tolist(),innerShell=dict(triangles=len(tris),boundaryEdges=len(boundary),boundaryLoops=1))
    return parts,skeleton,world,eye,shell,meta
