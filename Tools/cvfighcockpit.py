"""Purpose-built CRA fighter interior; stock rig and selected gun geometry only."""
from pathlib import Path
from collections import Counter
import io,math
import numpy as np
import reddevilcockpit as shared

MATERIAL='CRV/CVFighterCockpit';GUNS='CRV/CVFighterGuns'
# Pixel-authored rectangles in the 1254-square generated master; inset gutters.
CHARTS={'console':(24,28,1230,397),'switch':(24,436,610,706),'engine':(644,436,1230,706),'armor':(24,743,609,1227),'frame':(720,775,1150,875),'trim':(644,954,1230,1227)}

def rig(path):
    s=shared.oss.SkeletonSerializer(io.BytesIO(Path(path).read_bytes())).read();world={}
    def visit(b):
        if b.handle in world:return world[b.handle]
        q=b.orientation;x,y,z,w=q.x,q.y,q.z,q.w
        r=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
        p=np.array([b.position.x,b.position.y,b.position.z])
        if b.parent is not None:pp,pr=visit(b.parent);p=pp+pr@p;r=pr@r
        world[b.handle]=(p,r);return p,r
    for b in s.bones():visit(b)
    eye=next(b for b in s.bones() if b.name=='CFL11POV');shell=next(b for b in s.bones() if b.name=='CFL21BDA')
    return s,world,eye,shell

def geometry(source,skeleton_path):
    skeleton,world,eye,shell=rig(skeleton_path);origin,R=world[eye.handle];rows=[];indices=[]
    def face(points,chart='trim',hint=None,uvs=None):
        p=np.array(points,float);normal=np.cross(p[1]-p[0],p[2]-p[0]);normal/=np.linalg.norm(normal)
        hint=-p.mean(0) if hint is None else np.array(hint)
        if np.dot(normal,hint)<0:p=p[::-1];normal=-normal;uvs=None if uvs is None else list(reversed(uvs))
        if uvs is None:
            x0,y0,x1,y1=np.array(CHARTS[chart])/1254
            uvs=[(x0,y1),(x1,y1),(x1,y0),(x0,y0)] if len(p)==4 else [(x0+(x1-x0)*(.5+.5*math.cos(2*math.pi*i/len(p))),y0+(y1-y0)*(.5+.5*math.sin(2*math.pi*i/len(p)))) for i in range(len(p))]
        start=len(rows)
        for v,uv in zip(p,uvs):rows.append([*(origin+R@v),*(R@normal),*uv])
        for i in range(1,len(p)-1):indices.extend([start,start+i,start+i+1])
    def beam(a,b,width=.032,depth=.045):
        a=np.array(a,float);b=np.array(b,float);axis=b-a;axis/=np.linalg.norm(axis);across=np.cross(axis,[0,1,0] if abs(axis[1])<.92 else [1,0,0]);across/=np.linalg.norm(across);up=np.cross(axis,across)
        ring=[(-.3,-.5),(.3,-.5),(.5,-.3),(.5,.3),(.3,.5),(-.3,.5),(-.5,.3),(-.5,-.3)]
        rings=[[v+across*x*width+up*y*depth for x,y in ring] for v in (a,b)];center=(a+b)/2
        for i in range(8):j=(i+1)%8;p=[rings[0][i],rings[1][i],rings[1][j],rings[0][j]];face(p,'frame',np.mean(p,0)-center)
        face(rings[0],'trim',-axis);face(rings[1],'trim',axis)
    # A low, broad, raked canopy: no central upright or tall generic cage.
    rim=[(-.76,-.33,1.02),(0,-.38,1.28),(.76,-.33,1.02),(.86,.10,.70),(.60,.43,.30),(0,.47,.40),(-.60,.43,.30),(-.86,.10,.70)]
    for i in range(len(rim)):beam(rim[i],rim[(i+1)%len(rim)],.030,.043)
    for sign in (-1,1):
        beam((sign*.86,.10,.70),(sign*.88,.16,-.55),.033,.049)
        beam((sign*.60,.43,.30),(sign*.64,.49,-.55),.029,.041)
        # Deep sill and angled gun-control wing, below the forward aim corridor.
        face([(sign*.74,-.34,1.02),(sign*.88,-.34,-.40),(sign*.94,-.72,-.35),(sign*.78,-.72,.91)],'armor')
        face([(sign*.61,-.43,.73),(sign*.84,-.43,.17),(sign*.82,-.68,-.17),(sign*.58,-.68,.39)],'switch' if sign<0 else 'engine')
        beam((sign*.63,-.42,.72),(sign*.85,-.42,.17),.026,.031)
    dash=[(-.61,-.37,1.03),(.61,-.37,1.03),(.56,-.67,.67),(-.56,-.67,.67)]
    x0,y0,x1,y1=np.array(CHARTS['console'])/1254
    face(dash,'console',uvs=[(x1,y0),(x0,y0),(x0,y1),(x1,y1)])
    for i in range(4):beam(dash[i],dash[(i+1)%4],.022,.030)
    # Restrained split-nose apron joins the sill, not a full exterior hull merge.
    face([(-.75,-.36,1.04),(0,-.38,1.28),(.75,-.36,1.04),(.56,-.49,1.52),(0,-.53,1.64),(-.56,-.49,1.52)],'armor',hint=[0,1,0])
    # Closed swept mounting shoulders hide the gun backs and join them to the
    # sill. Only their forward upper barrel sections should peek into view.
    for sign in (-1,1):
        a=np.array([sign*.78,-.48,1.08]);b=np.array([sign*1.48,-.69,2.20]);rings_mount=[]
        for c,w,h in [(a,.22,.15),(b,.28,.20)]:rings_mount.append([c+np.array([dx*w,dy*h,0]) for dx,dy in [(-.5,-.5),(.5,-.5),(.5,.5),(-.5,.5)]])
        c=(a+b)/2
        for i in range(4):j=(i+1)%4;p=[rings_mount[0][i],rings_mount[1][i],rings_mount[1][j],rings_mount[0][j]];face(p,'armor' if i==2 else 'trim',hint=np.mean(p,0)-c)
        face(rings_mount[0],'trim',hint=[0,0,-1]);face(rings_mount[1],'trim',hint=[0,0,1])
    shell_start=len(indices);rings=[]
    for z,w,lip in [(-.55,.88,-.34),(.17,.85,-.34),(1.02,.76,-.33)]:
        rings.append([(-w,lip,z),(-w*.97,-.72,z),(-w*.66,-1.04,z),(w*.66,-1.04,z),(w*.97,-.72,z),(w,lip,z)])
    # One continuous unwrap across the entire lower tub, not a repeated full
    # panel stamp on every small facet. Shared seam coordinates remain exact.
    profile=np.array(rings[0]);length=np.r_[0,np.cumsum(np.linalg.norm(np.diff(profile,axis=0),axis=1))];length/=length[-1]
    tx0,ty0,tx1,ty1=np.array(CHARTS['trim'])/1254
    def tub_uv(i,z):return (tx0+(tx1-tx0)*length[i],ty0+(ty1-ty0)*(1-(z+.55)/1.57))
    for a,b in zip(rings,rings[1:]):
        for i in range(5):face([a[i],b[i],b[i+1],a[i+1]],'trim',uvs=[tub_uv(i,a[i][2]),tub_uv(i,b[i][2]),tub_uv(i+1,b[i+1][2]),tub_uv(i+1,a[i+1][2])])
    face(rings[0],'trim');face(rings[-1]+[(0,-.38,1.28)],'trim')
    face([rings[0][0],rings[0][-1],(.88,.16,-.55),(.64,.49,-.55),(-.64,.49,-.55),(-.88,.16,-.55)],'trim')
    face([(-.64,.49,-.55),(.64,.49,-.55),(.60,.43,.30),(0,.47,.40),(-.60,.43,.30)],'trim')
    # A single connected inner tub with exactly one intentional canopy loop.
    shell_tri=np.array(rows)[:,:3][np.array(indices[shell_start:]).reshape(-1,3)];edges=Counter()
    for tri in shell_tri:
        keys=[tuple(np.round(p,6)) for p in tri]
        for i in range(3):edges[tuple(sorted((keys[i],keys[(i+1)%3])))]+=1
    boundary=[e for e,n in edges.items() if n==1];adj={}
    for a,b in boundary:adj.setdefault(a,set()).add(b);adj.setdefault(b,set()).add(a)
    assert max(edges.values())==2 and all(len(v)==2 for v in adj.values())
    seen=set();todo=[next(iter(adj))]
    while todo:
        p=todo.pop()
        if p not in seen:seen.add(p);todo.extend(adj[p]-seen)
    assert len(seen)==len(adj),'unintended separate tub opening'
    parts={MATERIAL:(np.array(rows,dtype='<f4'),np.array(indices,dtype='<u2'))}
    # Actual visible gun-tip surface triangles, not the tiny GC hardpoint cubes.
    body=shared.read_mesh(source).submesh_list[0];vd=body.vertex_data;p=shared.values(vd,shared.om.VES.POSITION);n=shared.values(vd,shared.om.VES.NORMAL);uv=shared.values(vd,shared.om.VES.TEXTURE_COORDINATES);t=shared.values(vd,shared.om.VES.TANGENT);tri=body.index_array.reshape(-1,3);q=p[tri]
    weights=np.zeros(len(p))
    for a in body.bone_assignments():
        if a.bone_index==0:weights[a.vertex_index]+=a.weight
    keep=(weights[tri]>.99).all(1)&(np.abs(q[:,:,0]).min(1)>1.7)&(np.abs(q[:,:,0]).max(1)<2.3)&(q[:,:,1].max(1)<.35)&(q[:,:,2].min(1)>2.0)
    selected=tri[keep];used,remap=np.unique(selected,return_inverse=True);positions=p[used].copy();local=(positions-origin)@R
    # Art-directed first-person fitting: no rotation/rescaling or UV changes.
    local[:,0]-=np.sign(local[:,0])*.55;local[:,1]+=.45;local[:,2]+=.65;positions=origin+local@R.T
    data=np.column_stack([positions,n[used],uv[used]]).astype('<f4')
    if t is not None:
        tangent=t[used,:3].copy();normal=n[used];tangent-=normal*(tangent*normal).sum(1)[:,None];length=np.linalg.norm(tangent,axis=1);bad=length<1e-8
        for i in np.flatnonzero(bad):
            axis=np.eye(3)[np.argmin(np.abs(normal[i]))];tangent[i]=np.cross(axis,normal[i])
        tangent/=np.linalg.norm(tangent,axis=1)[:,None];data=np.column_stack([data,tangent]).astype('<f4')
    parts[GUNS]=(data,remap.astype('<u2').reshape(-1));assert len(selected)>100
    return parts,skeleton,world,eye,shell,dict(pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,gunTriangles=len(selected),gunSourceIndices=np.flatnonzero(keep).tolist(),gunPlacement=dict(inboard=.55,up=.45,forward=.65),rim=np.array(rim).tolist(),innerShell=dict(triangles=len(shell_tri),boundaryEdges=len(boundary),boundaryLoops=1))
