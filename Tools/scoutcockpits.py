"""Stock-grounded Razor scout cockpits with faction art and original nose pieces."""
from collections import Counter
import math
import numpy as np
import reddevilcockpit as shared

CHARTS={'console':(.02,.02,.98,.34),'switch':(.02,.38,.48,.64),
        'service':(.52,.38,.98,.64),'armor':(.02,.68,.48,.98),
        'frame':(.52,.68,.98,.80),'trim':(.52,.84,.98,.98)}
CONFIG={
    'nsdf':dict(base='avfigh',shell='ara21bda',material='CRV/NSDFScoutCockpit',nose='CRV/NSDFScoutNose',stem='crvascp',noseBone=2,cockpitBatch=2,eye=[-.004399999976158142,1.467507004737854,.7488619983196259]),
    'bdog':dict(base='bvraz',shell='bra21bda',material='CRV/BDogScoutCockpit',nose='CRV/BDogScoutNose',stem='crvbscp',noseBone=1,cockpitBatch=1,eye=[-.004399999976158142,1.467507004737854,.8566620051860809])}
NOSE_FIT=dict(up=.10,forward=.15,pitchDegrees=-14.,pivotModel=[0.,.70,2.30])

def geometry(source,skeleton_path,faction):
    cfg=CONFIG[faction];skeleton,world,eye,shell=shared.rig(skeleton_path,cfg['shell']);origin,R=world[eye.handle];rows=[];indices=[]
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
    rim=[(-.65,-.40,1.03),(0,-.45,1.25),(.65,-.40,1.03),
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
    # Low squat mechanical console, not a glass instrument wall. Lower
    # center spine echoes the stock Razor's controls without blocking aim.
    dash=[(-.51,-.43,1.02),(.51,-.43,1.02),(.46,-.71,.87),(-.46,-.71,.87)]
    x0,y0,x1,y1=CHARTS['console'];face(dash,'console',uvs=[(x1,y0),(x0,y0),(x0,y1),(x1,y1)])
    for i in range(4):beam(dash[i],dash[(i+1)%4],.025,.034)
    keel=[(-.14,-.72,.86),(.14,-.72,.86),(.12,-1.01,.12),(-.12,-1.01,.12)]
    x0,y0,x1,y1=CHARTS['service'];face(keel,'service',uvs=[(x0,y0),(x0,y1),(x1,y1),(x1,y0)])
    for i in (1,3):beam(keel[i],keel[(i+1)%4],.025,.030)
    # Closed low coaming reaches the original nose root. The actual exterior
    # nose is a separate bounded, preserved-UV piece, not the complete hull.
    deck=[(-.64,-.41,1.03),(0,-.45,1.25),(.64,-.41,1.03),(.58,-.49,1.49),(-.58,-.49,1.49)]
    bottom=[(x,y-.09,z) for x,y,z in deck];c=np.mean(deck+bottom,axis=0)
    face(deck,'armor',hint=[0,1,0]);face(bottom,hint=[0,-1,0])
    for i in range(5):j=(i+1)%5;p=[deck[i],deck[j],bottom[j],bottom[i]];face(p,'frame',hint=np.mean(p,0)-c)
    # One closed, continuously unwrapped tub with a single intentional window.
    shell_start=len(indices);rings=[]
    for z,w,lip in [(-.57,.78,-.36),(.17,.73,-.38),(1.03,.65,-.40)]:
        rings.append([(-w,lip,z),(-w*.97,-.80,z),(-w*.65,-1.11,z),(w*.65,-1.11,z),(w*.97,-.80,z),(w,lip,z)])
    length=np.r_[0,np.cumsum(np.linalg.norm(np.diff(np.array(rings[0]),axis=0),axis=1))];length/=length[-1];tx0,ty0,tx1,ty1=CHARTS['trim']
    def tuv(i,z):return (tx0+(tx1-tx0)*length[i],ty0+(ty1-ty0)*(1-(z+.57)/1.60))
    for a,b in zip(rings,rings[1:]):
        for i in range(5):face([a[i],b[i],b[i+1],a[i+1]],uvs=[tuv(i,a[i][2]),tuv(i,b[i][2]),tuv(i+1,b[i+1][2]),tuv(i+1,a[i+1][2])])
    face(rings[0]);face(rings[-1]+[(0,-.45,1.25)])
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
    parts={cfg['material']:(np.array(rows,dtype='<f4'),np.array(indices,dtype='<u2'))}
    # The entire original ROF nose piece, not a hardpoint cube or a fragile
    # side-only crop. Preserve source UVs, normals and triangle shape.
    body=shared.read_mesh(source).submesh_list[0];vd=body.vertex_data;p=shared.values(vd,shared.om.VES.POSITION);n=shared.values(vd,shared.om.VES.NORMAL);uv=shared.values(vd,shared.om.VES.TEXTURE_COORDINATES);tri=body.index_array.reshape(-1,3);weight=np.zeros(len(p))
    for a in body.bone_assignments():
        if a.bone_index==cfg['noseBone']:weight[a.vertex_index]+=a.weight
    keep=(weight[tri]>.99).all(1);selected=tri[keep];used,remap=np.unique(selected,return_inverse=True);positions=p[used].copy();local=(positions-origin)@R
    theta=math.radians(NOSE_FIT['pitchDegrees']);c,s=math.cos(theta),math.sin(theta);rot=np.array([[1.,0,0],[0,c,-s],[0,s,c]])
    pivot=(np.array(NOSE_FIT['pivotModel'])-origin)@R;local=(local-pivot)@rot.T+pivot
    local[:,1]+=NOSE_FIT['up'];local[:,2]+=NOSE_FIT['forward'];positions=origin+local@R.T
    normal=n[used]@R@rot.T@R.T;t=shared.values(vd,shared.om.VES.TANGENT)[used,:3]@R@rot.T@R.T;t-=normal*(t*normal).sum(1)[:,None]
    for i in np.flatnonzero(np.linalg.norm(t,axis=1)<1e-8):t[i]=np.cross(np.eye(3)[np.argmin(np.abs(normal[i]))],normal[i])
    t/=np.linalg.norm(t,axis=1)[:,None];parts[cfg['nose']]=(np.column_stack([positions,normal,uv[used],t]).astype('<f4'),remap.astype('<u2').reshape(-1));assert len(selected)>100
    meta=dict(faction=faction,base=cfg['base'],pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,noseTriangles=len(selected),noseBone=cfg['noseBone'],noseSourceIndices=np.flatnonzero(keep).tolist(),nosePlacement=NOSE_FIT,rim=np.array(rim).tolist(),innerShell=dict(triangles=len(tris),boundaryEdges=len(boundary),boundaryLoops=1))
    return parts,skeleton,world,eye,shell,meta
