"""POV-relative Red Devil cockpit geometry through the shared Ogre codecs."""
from pathlib import Path
import io,math,sys
from types import SimpleNamespace
import numpy as np
from bzmodellibs import ogremesh as om,ogremesh_serializer as oms,ogreskeleton_serializer as oss

CHARTS={'frame':(240,66,770,144),'console':(16,216,632,632),'switch':(664,216,1008,632),'armor':(16,664,632,1008),'trim':(664,664,1008,1008)}
MATERIAL='CRV/RedDevilCockpit';BOW='CRV/RedDevilForedeck'

def values(vd,semantic):
    e=vd.vertex_declaration.find_by_semantic(semantic);v=vd.get_vertex_buffer(e.source)
    return np.ndarray((vd.vertex_count,e.get_type_count()),'<f4',buffer=v.buffer,offset=e.offset,strides=(v.vertex_size,4)).copy()

def read_mesh(path):return oms.MeshSerializer(io.BytesIO(path.read_bytes())).read()

def rig(path):
    skeleton=oss.SkeletonSerializer(io.BytesIO(path.read_bytes())).read();world={}
    def transform(b):
        if b.handle in world:return world[b.handle]
        q=b.orientation;x,y,z,w=q.x,q.y,q.z,q.w
        r=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
        p=np.array([b.position.x,b.position.y,b.position.z])
        if b.parent is not None:
            pp,pr=transform(b.parent);p=pp+pr@p;r=pr@r
        world[b.handle]=(p,r);return p,r
    for b in skeleton.bones():transform(b)
    eye=next(b for b in skeleton.bones() if b.name.lower().endswith('pov'))
    shell=next(b for b in skeleton.bones() if b.name.lower()=='brd21bda')
    return skeleton,world,eye,shell

def geometry(source,skeleton_path):
    skeleton,world,eye,shell=rig(skeleton_path);origin,R=world[eye.handle]
    rows=[];indices=[];parts={}
    def face(points,chart='trim',hint=None,uvs=None):
        p=np.array(points,float);normal=np.cross(p[1]-p[0],p[2]-p[0]);normal/=np.linalg.norm(normal)
        hint=-p.mean(0) if hint is None else np.array(hint)
        if np.dot(normal,hint)<0:p=p[::-1];normal=-normal;uvs=None if uvs is None else list(reversed(uvs))
        if uvs is None:
            # Rectangular charts stay inside their padded allocation.
            x0,y0,x1,y1=np.array(CHARTS[chart])/1024
            if len(p)==4:uvs=[(x0,y1),(x1,y1),(x1,y0),(x0,y0)]
            else:uvs=[(x0+(x1-x0)*(.5+.5*math.cos(2*math.pi*i/len(p))),y0+(y1-y0)*(.5+.5*math.sin(2*math.pi*i/len(p)))) for i in range(len(p))]
        start=len(rows)
        for v,uv in zip(p,uvs):rows.append([*(origin+R@v),*(R@normal),*uv])
        for i in range(1,len(p)-1):indices.extend([start,start+i,start+i+1])
    def beam(a,b,width=.035,depth=.045):
        a=np.array(a,float);b=np.array(b,float);axis=b-a;axis/=np.linalg.norm(axis)
        across=np.cross(axis,[0,1,0] if abs(axis[1])<.92 else [1,0,0]);across/=np.linalg.norm(across);up=np.cross(axis,across)
        c=.22;section=[(-.5+c,-.5),(.5-c,-.5),(.5,-.5+c),(.5,.5-c),(.5-c,.5),(-.5+c,.5),(-.5,.5-c),(-.5,-.5+c)]
        rings=[[v+across*x*width+up*y*depth for x,y in section] for v in (a,b)]
        center=(a+b)*.5
        for i in range(8):
            j=(i+1)%8;p=[rings[0][i],rings[1][i],rings[1][j],rings[0][j]];face(p,'frame',np.mean(p,0)-center)
        face(rings[0],'trim',-axis);face(rings[1],'trim',axis)
    # Raked, faceted windscreen: low pointed sill and wraparound side posts.
    rim=[(-.58,-.30,.83),(0,-.34,1.05),(.58,-.30,.83),(.65,.10,.62),(.40,.46,.28),(0,.50,.38),(-.40,.46,.28),(-.65,.10,.62)]
    for i in range(len(rim)):beam(rim[i],rim[(i+1)%len(rim)],.027,.037)
    # Upper/side longerons follow the compact pointed canopy rather than an APC box.
    for sign in (-1,1):
        beam((sign*.65,.10,.62),(sign*.70,.18,-.48),.038,.052)
        beam((sign*.40,.46,.28),(sign*.48,.53,-.48),.031,.043)
        beam((sign*.58,-.30,.83),(sign*.70,-.30,-.48),.045,.052)
        face([(sign*.59,-.32,.82),(sign*.68,-.41,-.27),(sign*.75,-.72,-.25),(sign*.69,-.70,.70)],'armor')
        # Side console faces angle inward and remain below the horizon.
        face([(sign*.49,-.38,.75),(sign*.65,-.39,.17),(sign*.63,-.65,.10),(sign*.46,-.65,.66)],'switch')
        beam((sign*.50,-.38,.75),(sign*.65,-.39,.17),.024,.024)
    # Low center console: no tall center pillar in the aiming corridor.
    dash=[(-.46,-.35,.84),(.46,-.35,.84),(.39,-.69,.51),(-.39,-.69,.51)]
    # Explicit texture orientation: atlas top is dashboard top.
    x0,y0,x1,y1=np.array(CHARTS['console'])/1024
    # Looking along the Ogre POV's +Z makes model +X screen-left.
    face(dash,'console',uvs=[(x1,y0),(x0,y0),(x0,y1),(x1,y1)])
    for i in range(4):beam(dash[i],dash[(i+1)%4],.022,.032)
    face([(-.48,-.36,.87),(0,-.34,1.05),(.48,-.36,.87),(.46,-.35,.84),(-.46,-.35,.84)],'armor')
    # One connected inner tub, rear bulkhead and roof. Instrument panels are
    # overlays, never substitutes for a shell: seams cannot expose empty space.
    shell_start=len(indices)
    rings=[]
    for z,w,lip in [(-.48,.70,-.30),(.17,.67,-.31),(.83,.58,-.30)]:
        rings.append([(-w,lip,z),(-w*.95,-.66,z),(-w*.65,-.90,z),(w*.65,-.90,z),(w*.95,-.66,z),(w,lip,z)])
    for a,b in zip(rings,rings[1:]):
        for i in range(5):face([a[i],b[i],b[i+1],a[i+1]],'trim')
    face(rings[0],'trim')
    face(rings[-1]+[(0,-.34,1.05)],'trim')
    face([rings[0][0],rings[0][-1],(.70,.18,-.48),(.48,.53,-.48),(-.48,.53,-.48),(-.70,.18,-.48)],'trim')
    face([(-.48,.53,-.48),(.48,.53,-.48),(.40,.46,.28),(0,.50,.38),(-.40,.46,.28)],'trim')
    # Quantized position topology: all unmatched edges must belong to the single
    # intentional wraparound canopy opening, with no other disconnected holes.
    from collections import Counter
    shell_tri=np.array(rows)[:,:3][np.array(indices[shell_start:]).reshape(-1,3)]
    edges=Counter()
    for tri in shell_tri:
        keys=[tuple(np.round(p,6)) for p in tri]
        for i in range(3):edges[tuple(sorted((keys[i],keys[(i+1)%3])))]+=1
    boundary=[e for e,n in edges.items() if n==1];adj={}
    for a,b in boundary:adj.setdefault(a,set()).add(b);adj.setdefault(b,set()).add(a)
    assert edges and max(edges.values())==2 and all(len(v)==2 for v in adj.values()),'inner shell must be manifold except a window loop'
    seen=set();todo=[next(iter(adj))]
    while todo:
        p=todo.pop()
        if p in seen:continue
        seen.add(p);todo.extend(adj[p]-seen)
    assert len(seen)==len(adj),'unexpected disconnected shell opening'
    shell_topology=dict(triangles=len(shell_tri),boundaryEdges=len(boundary),boundaryLoops=1,role='single intentional wraparound canopy opening')
    parts[MATERIAL]=(np.array(rows,dtype='<f4'),np.array(indices,dtype='<u2'))
    # Retain the real external nose's geometry/UVs for the view over the sill.
    body=read_mesh(source).submesh_list[0];p=values(body.vertex_data,om.VES.POSITION);n=values(body.vertex_data,om.VES.NORMAL);uv=values(body.vertex_data,om.VES.TEXTURE_COORDINATES);tri=body.index_array.reshape(-1,3)
    local=(p-origin)@R;coords=local[tri];normal=n[tri].mean(1)@R
    keep=(coords[:,:,2].min(1)>.48)&(coords[:,:,1].max(1)<-.20)&(abs(coords[:,:,0]).max(1)<1.30)&(normal[:,1]>.15)
    selected=tri[keep];used,remap=np.unique(selected,return_inverse=True)
    parts[BOW]=(np.column_stack([p[used],n[used],uv[used]]).astype('<f4'),remap.astype('<u2').reshape(-1))
    tangent=body.vertex_data.vertex_declaration.find_by_semantic(om.VES.TANGENT)
    if tangent is not None:parts[BOW]=(np.column_stack([parts[BOW][0],values(body.vertex_data,om.VES.TANGENT)[used,:3]]).astype('<f4'),parts[BOW][1])
    assert len(selected)>0,'actual pointed foredeck must be selected'
    return parts,skeleton,world,eye,shell,dict(pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,foredeckTriangles=len(selected),rim=pub(rim),innerShell=shell_topology)

def pub(x):return np.array(x).tolist()

def mesh_bytes(parts,skeleton,world,eye,shell,skeleton_name='bvrdev_cockpit.skeleton'):
    mesh=om.Mesh();mesh.skeleton_name=skeleton_name
    def add(name,data,index):
        if data.shape[1]==8:
            # Positive/negative UV axes both get a matching orthogonal tangent.
            t=np.zeros((len(data),3))
            for tri in index.reshape(-1,3):
                p=data[tri,:3];uv=data[tri,6:8];a,b=uv[1]-uv[0],uv[2]-uv[0];det=a[0]*b[1]-b[0]*a[1]
                if abs(det)>1e-12:
                    v=((p[1]-p[0])*b[1]-(p[2]-p[0])*a[1])/det
                    for i in tri:t[i]+=v
            n=data[:,3:6];t-=n*(t*n).sum(1)[:,None];length=np.linalg.norm(t,axis=1)
            assert (length>1e-9).all(),'all mapped cockpit vertices need a tangent'
            data=np.column_stack([data,t/length[:,None]]).astype('<f4')
        sub=mesh.create_submesh();sub.material_name=name;sub.index_count=len(index);sub.indices_32_bit=False;sub.set_index_buffer(index.astype('<u2').tobytes());vd=sub.create_vertex_data(len(data))
        for typ,sem,offset in [(om.VET.FLOAT3,om.VES.POSITION,0),(om.VET.FLOAT3,om.VES.NORMAL,12),(om.VET.FLOAT2,om.VES.TEXTURE_COORDINATES,24),(om.VET.FLOAT3,om.VES.TANGENT,32)]:vd.vertex_declaration.create_vertex_element(0,typ,sem,offset,0)
        vd.create_vertex_buffer(np.asarray(data,dtype='<f4').tobytes(),0,44)
        for i in range(len(data)):sub.create_bone_assignment(i,shell.handle,1.)
        return sub
    for name,(data,index) in parts.items():add(name,data,index)
    # Reuse the established bounded ray-grid fit, not its legacy file parser.
    # All on-disk model I/O in this builder uses bzmodellibs exclusively.
    import cockpitglass as cg
    adapter=SimpleNamespace(submeshes=[dict(positions=d[:,:3],tris=i.reshape(-1,3),bones=np.full(len(d),shell.handle),material=name) for name,(d,i) in parts.items()])
    skel=SimpleNamespace(names={b.handle:b.name for b in skeleton.bones()},world=world,parent={b.handle:b.parent.handle for b in skeleton.bones() if b.parent is not None})
    fit=cg.make_glass(adapter,skel,{})
    glass=np.column_stack([fit.positions,fit.normals,fit.uvs]).astype('<f4');add('CRWX_CockpitGlass',glass,fit.tris.reshape(-1))
    points=np.concatenate([d[:,:3] for d,i in parts.values()]+[fit.positions]);lo=points.min(0);hi=points.max(0)
    mesh.aabb=om.AxisAlignedBoundingBox(*lo,*hi);mesh.bound_radius=float(np.linalg.norm(points,axis=1).max())
    out=io.BytesIO();oms.MeshSerializer(out).write(mesh)
    return out.getvalue(),dict(openFraction=fit.open_frac,depth=list(fit.depth),bone=fit.bone_name,vertices=len(glass),triangles=len(fit.tris))
