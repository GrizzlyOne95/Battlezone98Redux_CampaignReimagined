"""POV-fitted NSDF rocket-tank interior and a bounded selection of nose fins."""
from collections import Counter
import math
import numpy as np
import reddevilcockpit as shared

MATERIAL='CRV/AVRocketCockpit';FINS='CRV/AVRocketNoseFins'
# Normalized rectangles: independent optical panels and quiet structural charts.
CHARTS={'flight':(.02,.02,.48,.34),'rocket':(.52,.02,.98,.34),
        'switch':(.02,.38,.48,.61),'engine':(.52,.38,.98,.61),
        'armor':(.02,.65,.48,.98),'frame':(.60,.66,.94,.73),
        'trim':(.52,.83,.98,.98),'back':(.10,.70,.44,.93)}
FIN_PLACEMENT=dict(up=.28,outward=0.,forward=.40,pitchDegrees=-12.,pivotModel=[0.,1.1,3.3])

def geometry(source,skeleton_path):
    skeleton,world,eye,shell=shared.rig(skeleton_path,'art21bda');origin,R=world[eye.handle]
    rows=[];indices=[]
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
    def beam(a,b,width=.035,depth=.045):
        a=np.asarray(a,float);b=np.asarray(b,float);axis=b-a;axis/=np.linalg.norm(axis)
        across=np.cross(axis,[0,1,0] if abs(axis[1])<.92 else [1,0,0]);across/=np.linalg.norm(across);up=np.cross(axis,across)
        profile=[(-.3,-.5),(.3,-.5),(.5,-.3),(.5,.3),(.3,.5),(-.3,.5),(-.5,.3),(-.5,-.3)]
        rings=[[v+across*x*width+up*y*depth for x,y in profile] for v in (a,b)];c=(a+b)/2
        for i in range(8):j=(i+1)%8;p=[rings[0][i],rings[1][i],rings[1][j],rings[0][j]];face(p,'frame',np.mean(p,0)-c)
        face(rings[0],hint=-axis);face(rings[1],hint=axis)
    # Broad hexagonal observation windscreen, unlike the tall APC cage. Thin
    # diagonal cheeks and a high brow keep the centre sightline uninterrupted.
    rim=[(-.91,-.48,1.28),(0,-.48,1.48),(.91,-.48,1.28),
         (.87,.28,1.02),(.57,.66,.66),(-.57,.66,.66),(-.87,.28,1.02)]
    for i in range(len(rim)):beam(rim[i],rim[(i+1)%len(rim)],.033,.045)
    for sign in (-1,1):
        beam((sign*.87,.28,1.02),(sign*.97,.30,-.66),.034,.046)
        beam((sign*.57,.66,.66),(sign*.66,.70,-.66),.028,.042)
        beam((sign*.91,-.48,1.28),(sign*.97,-.42,-.66),.042,.052)
        # Outboard shoulders, inward-raked side panels, low padded arm rails.
        face([(sign*.89,-.48,1.25),(sign*.96,-.43,-.59),(sign*1.01,-.80,-.50),(sign*.93,-.82,1.10)],'armor')
        face([(sign*.68,-.56,.96),(sign*.89,-.52,.12),(sign*.86,-.79,-.04),(sign*.64,-.82,.75)],'switch' if sign<0 else 'engine')
        beam((sign*.71,-.55,.99),(sign*.91,-.51,.12),.025,.028)
    # Split angled instrument wings, with a low central armored bridge.
    # +X is screen-left when looking along the Ogre POV +Z.
    for sign,chart in [(1,'flight'),(-1,'rocket')]:
        dash=[(sign*.06,-.55,1.22),(sign*.70,-.50,1.14),(sign*.65,-.84,.84),(sign*.06,-.88,.94)]
        x0,y0,x1,y1=CHARTS[chart]
        face(dash,chart,uvs=[(x1,y0),(x0,y0),(x0,y1),(x1,y1)] if sign==1 else [(x0,y0),(x1,y0),(x1,y1),(x0,y1)])
        for i in range(4):beam(dash[i],dash[(i+1)%4],.018,.025)
    face([(-.065,-.55,1.22),(.065,-.55,1.22),(.065,-.88,.94),(-.065,-.88,.94)],'armor')
    # A shallow uninterrupted coaming lies behind the selected nose-fin roots.
    face([(-.90,-.48,1.28),(0,-.48,1.48),(.90,-.48,1.28),(.70,-.50,1.14),(.06,-.55,1.22),(-.06,-.55,1.22),(-.70,-.50,1.14)],'armor',hint=[0,1,0])
    # Closed coaming-to-nose bridge: the exterior crop's underside must not
    # expose an unattached ribbon of sky between apron and windscreen sill.
    deck=[(-.90,-.48,1.28),(.90,-.48,1.28),(.95,-.58,2.20),(-.95,-.58,2.20)]
    bottom=[(x,y-.08,z) for x,y,z in deck];c=np.mean(deck+bottom,axis=0)
    face(deck,'armor',hint=[0,1,0]);face(bottom,'back',hint=[0,-1,0])
    for i in range(4):j=(i+1)%4;p=[deck[i],deck[j],bottom[j],bottom[i]];face(p,'frame',hint=np.mean(p,0)-c)
    # Closed cheek boots connect the art-fitted source fin roots to the sill.
    for sign in (-1,1):
        rings=[]
        for c,w,h in [(np.array([sign*.83,-.65,1.30]),.30,.20),(np.array([sign*1.23,-.80,1.85]),.40,.26)]:
            rings.append([c+np.array([dx*w,dy*h,0]) for dx,dy in [(-.5,-.5),(.5,-.5),(.5,.5),(-.5,.5)]])
        c=np.mean(rings,axis=(0,1))
        for i in range(4):j=(i+1)%4;p=[rings[0][i],rings[1][i],rings[1][j],rings[0][j]];face(p,'armor' if i==2 else 'trim',hint=np.mean(p,0)-c)
        face(rings[0],hint=[0,0,-1]);face(rings[1],hint=[0,0,1])
    # One connected inner enclosure: continuous tub UVs and one deliberate
    # wraparound canopy boundary, not isolated panels hiding open gaps.
    shell_start=len(indices);rings=[]
    for z,w,lip in [(-.66,.97,-.42),(.20,.95,-.45),(1.28,.91,-.48)]:
        rings.append([(-w,lip,z),(-w*.98,-.85,z),(-w*.66,-1.17,z),(w*.66,-1.17,z),(w*.98,-.85,z),(w,lip,z)])
    length=np.r_[0,np.cumsum(np.linalg.norm(np.diff(np.array(rings[0]),axis=0),axis=1))];length/=length[-1]
    tx0,ty0,tx1,ty1=CHARTS['trim']
    def tub_uv(i,z):return (tx0+(tx1-tx0)*length[i],ty0+(ty1-ty0)*(1-(z+.66)/1.94))
    for a,b in zip(rings,rings[1:]):
        for i in range(5):face([a[i],b[i],b[i+1],a[i+1]],uvs=[tub_uv(i,a[i][2]),tub_uv(i,b[i][2]),tub_uv(i+1,b[i+1][2]),tub_uv(i+1,a[i+1][2])])
    face(rings[0],'back');face(rings[-1]+[(0,-.48,1.48)],'back')
    face([rings[0][0],rings[0][-1],(.97,.30,-.66),(.66,.70,-.66),(-.66,.70,-.66),(-.97,.30,-.66)],'back')
    face([(-.66,.70,-.66),(.66,.70,-.66),(.57,.66,.66),(-.57,.66,.66)],'back')
    triangles=np.array(rows)[:,:3][np.array(indices[shell_start:]).reshape(-1,3)];edges=Counter()
    for tri in triangles:
        keys=[tuple(np.round(p,6)) for p in tri]
        for i in range(3):edges[tuple(sorted((keys[i],keys[(i+1)%3])))]+=1
    boundary=[e for e,n in edges.items() if n==1];adj={}
    for a,b in boundary:adj.setdefault(a,set()).add(b);adj.setdefault(b,set()).add(a)
    assert max(edges.values())==2 and all(len(v)==2 for v in adj.values())
    seen=set();todo=[next(iter(adj))]
    while todo:
        p=todo.pop()
        if p not in seen:seen.add(p);todo.extend(adj[p]-seen)
    assert len(seen)==len(adj),'unintended disconnected enclosure opening'
    parts={MATERIAL:(np.array(rows,dtype='<f4'),np.array(indices,dtype='<u2'))}
    # Keep the lower forward nose apron AND fin wedges as one rigid piece.
    # Selecting disconnected sides alone leaves missing connecting surfaces.
    # Exclude the launcher, upper hull, lights, rear nozzles and APC cockpit.
    body=shared.read_mesh(source).submesh_list[0];vd=body.vertex_data
    p=shared.values(vd,shared.om.VES.POSITION);n=shared.values(vd,shared.om.VES.NORMAL);uv=shared.values(vd,shared.om.VES.TEXTURE_COORDINATES);tri=body.index_array.reshape(-1,3);q=p[tri]
    weights=np.zeros(len(p))
    for a in body.bone_assignments():
        if a.bone_index==0:weights[a.vertex_index]+=a.weight
    keep=(weights[tri]>.99).all(1)&(q[:,:,2].min(1)>1.8)&(q[:,:,2].max(1)>2.9)&(q[:,:,1].max(1)<1.8)
    selected=tri[keep];used,remap=np.unique(selected,return_inverse=True);positions=p[used].copy();local=(positions-origin)@R
    theta=math.radians(FIN_PLACEMENT['pitchDegrees']);c,s=math.cos(theta),math.sin(theta);rot=np.array([[1.,0,0],[0,c,-s],[0,s,c]])
    pivot=(np.array(FIN_PLACEMENT['pivotModel'])-origin)@R;local=(local-pivot)@rot.T+pivot
    local[:,0]+=np.sign(local[:,0])*FIN_PLACEMENT['outward'];local[:,1]+=FIN_PLACEMENT['up'];local[:,2]+=FIN_PLACEMENT['forward']
    positions=origin+local@R.T;normal=(n[used]@R)@rot.T@R.T;data=np.column_stack([positions,normal,uv[used]]).astype('<f4')
    t=shared.values(vd,shared.om.VES.TANGENT)[used,:3]@R@rot.T@R.T;t-=normal*(t*normal).sum(1)[:,None]
    for i in np.flatnonzero(np.linalg.norm(t,axis=1)<1e-8):t[i]=np.cross(np.eye(3)[np.argmin(np.abs(normal[i]))],normal[i])
    t/=np.linalg.norm(t,axis=1)[:,None];parts[FINS]=(np.column_stack([data,t]).astype('<f4'),remap.astype('<u2').reshape(-1))
    assert len(selected)>0
    meta=dict(pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,finTriangles=len(selected),finSourceIndices=np.flatnonzero(keep).tolist(),finPlacement=FIN_PLACEMENT,rim=np.array(rim).tolist(),innerShell=dict(triangles=len(triangles),boundaryEdges=len(boundary),boundaryLoops=1))
    return parts,skeleton,world,eye,shell,meta
