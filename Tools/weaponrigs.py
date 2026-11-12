"""Closed, independently weighted gun sections using the shared Ogre codecs.

Geometry operations live here; binary format I/O remains in bzmodellibs.
Original attributes, material names and original bone transforms are retained.
"""
from pathlib import Path
import copy, collections, importlib.util, json, math, struct, subprocess, sys
import numpy as np
from bzmodellibs import toolbox_root
sys.path.insert(0,str(toolbox_root()))
from battlezone.meshes import ogre
from battlezone.meshes.ogre_skeleton import Bone, Animation, Track, Keyframe, read_skeleton, write_skeleton
import cockpitsections

ROOT=Path(__file__).resolve().parents[1]
GAME=Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux')
spec=importlib.util.spec_from_file_location('flash_rig',ROOT/'Tools/Build-WeaponFlashes.py')
flash=importlib.util.module_from_spec(spec);spec.loader.exec_module(flash)

def stage_revision(key,default):
    """Pre-rig stage revision for one repo path: models.json source_revision unless
    stage_revisions pins a later authored pre-rig file (e.g. a rebuilt cockpit)."""
    config=ROOT/'References/WeaponRigs/models.json'
    return json.loads(config.read_text()).get('stage_revisions',{}).get(key,default) if config.exists() else default

def base_asset_path(path):
    """Pre-recoil stage input for the cockpit builders (Build-*.py).

    Builders rebuild from the pre-rig stage in git history. The Test-*.py suites
    check the shipped files directly and must not use this helper. Raises when the
    pinned stage revision is missing from history.
    """
    path=Path(path).resolve();receipt=ROOT/'References/WeaponRigs/build.json';config=ROOT/'References/WeaponRigs/models.json'
    if not receipt.exists() or not config.exists() or not path.is_relative_to(ROOT):return path
    key=path.relative_to(ROOT).as_posix();records=json.loads(receipt.read_text())
    if not any(key in r.get('outputs',{}) for r in records.values()):return path
    revision=stage_revision(key,json.loads(config.read_text())['source_revision'])
    proc=subprocess.run(['git','show',revision+':'+key],cwd=ROOT,capture_output=True)
    if proc.returncode:
        # Never fall back to the shipped (already rigged) file: a silent fallback hides an orphaned stage commit (e.g. after a squash merge).
        raise RuntimeError('pre-rig stage %s:%s is not in git history; update stage_revisions in References/WeaponRigs/models.json (%s)'%(revision,key,proc.stderr.decode(errors='replace').strip()))
    target=ROOT/'Local/WeaponRigBase'/revision/key;target.parent.mkdir(parents=True,exist_ok=True)
    if not target.exists() or target.read_bytes()!=proc.stdout:target.write_bytes(proc.stdout)
    return target

def is_rigged(path):
    """True when the shipped mesh at path carries the weapon-rig layer (it points at a <name>_recoil.skeleton)."""
    return ogre.read_mesh(Path(path).read_bytes()).skeleton.endswith('_recoil.skeleton')

def rig_helper_parents(mesh):
    """{handle: parent handle} of the crgun_* helper bones the weapon rig appended to the skeleton a shipped mesh points at."""
    if not mesh.skeleton_name.endswith('_recoil.skeleton'):return {}
    return {b.handle:b.parent for b in read_skeleton((ROOT/'Assets/Models'/mesh.skeleton_name).read_bytes()).bones if b.name.startswith('crgun_')}

def rig_helper_handles(mesh):
    """Bone handles of the crgun_* helpers the weapon rig appended to the skeleton a shipped mesh points at."""
    return set(rig_helper_parents(mesh))

def attributes(geo):
    columns=[];layout=[];at=0
    for e in sorted(geo.elements,key=lambda e:(e.semantic!=1,e.source,e.offset)):
        a=np.asarray(geo.attribute(e.semantic,e.index),dtype=float)
        if e.semantic==5 and e.type in (4,10,11):
            p=a[:,0].astype(np.uint32)
            shifts=(16,8,0,24) if e.type!=11 else (0,8,16,24)
            a=np.column_stack([(p>>s)&255 for s in shifts])/255.
        columns.append(a);layout.append((copy.copy(e),at,a.shape[1]));at+=a.shape[1]
    return np.column_stack(columns),layout

def encode(rows,layout):
    decl=[];offset=0
    for e,start,n in layout:
        e=copy.copy(e);e.source=0;e.offset=offset
        decl.append(e);offset+=e.size
    raw=bytearray(offset*len(rows))
    for (e,start,n),dst in zip(layout,decl):
        a=rows[:,start:start+n]
        if e.semantic==9:
            a=a.copy()
            normal_start=next(s for el,s,_ in layout if el.semantic==4)
            normals=rows[:,normal_start:normal_start+3].copy();normals/=np.maximum(np.linalg.norm(normals,axis=1)[:,None],1e-12)
            a[:,:3]-=normals*np.einsum('ij,ij->i',a[:,:3],normals)[:,None]
            bad=np.linalg.norm(a[:,:3],axis=1)<1e-10
            for i in np.flatnonzero(bad):a[i,:3]=np.cross(normals[i],np.eye(3)[np.argmin(abs(normals[i]))])
            if n==4:a[:,3]=np.where(a[:,3]>=0,1,-1)
        if e.semantic in (4,9) and n>=3:
            a=a.copy();length=np.linalg.norm(a[:,:3],axis=1);good=length>1e-12;a[good,:3]/=length[good,None]
        if e.semantic==5 and e.type in (4,10,11):
            c=np.rint(np.clip(a,0,1)*255).astype(np.uint32)
            shifts=(16,8,0,24) if e.type!=11 else (0,8,16,24)
            data=sum(c[:,i]<<s for i,s in enumerate(shifts))
            for i,v in enumerate(data):struct.pack_into('<I',raw,i*offset+dst.offset,int(v))
        else:
            code,count,_=ogre.TYPES[e.type];fmt='<'+str(count)+code
            for i,v in enumerate(a):struct.pack_into(fmt,raw,i*offset+dst.offset,*v)
    return ogre.Geometry(len(rows),decl,{0:ogre.VertexBuffer(0,offset,bytes(raw),0)})

def split_faces(faces,normal,distance):
    """Partition triangles with attribute interpolation; no faces are discarded."""
    inside=[];outside=[]
    for tri in faces:
        d=tri[:,:3]@normal-distance
        if d.min()>=-1e-9:inside.append(tri);continue
        if d.max()<=1e-9:outside.append(tri);continue
        for sign,out in [(1,inside),(-1,outside)]:
            poly=[]
            for j,a in enumerate(tri):
                b=tri[(j+1)%3];da=d[j]*sign;db=d[(j+1)%3]*sign
                if da>=-1e-9:poly.append(a)
                if da*db<0:poly.append(a+(b-a)*(da/(da-db)))
            for j in range(1,len(poly)-1):
                f=np.asarray([poly[0],poly[j],poly[j+1]])
                if np.linalg.norm(np.cross(f[1,:3]-f[0,:3],f[2,:3]-f[0,:3]))>1e-10:out.append(f)
    return inside,outside

def surface_clearance(point,tri):
    """Nearest triangle-surface distance, including face interiors and edges."""
    a=tri[:,0];ab=tri[:,1]-a;ac=tri[:,2]-a;n=np.cross(ab,ac);length=np.linalg.norm(n,axis=1)
    unit=n/np.maximum(length[:,None],1e-20);signed=np.einsum('ij,ij->i',point-a,unit)
    projected=point-signed[:,None]*unit;ap=projected-a
    d00=np.einsum('ij,ij->i',ab,ab);d01=np.einsum('ij,ij->i',ab,ac);d11=np.einsum('ij,ij->i',ac,ac)
    d20=np.einsum('ij,ij->i',ap,ab);d21=np.einsum('ij,ij->i',ap,ac);den=d00*d11-d01*d01
    safe=np.where(abs(den)>1e-20,den,1);u=(d11*d20-d01*d21)/safe;v=(d00*d21-d01*d20)/safe
    distance=np.where((length>1e-12)&(u>=0)&(v>=0)&(u+v<=1),abs(signed),np.inf)
    for j in range(3):
        a=tri[:,j];edge=tri[:,(j+1)%3]-a;t=np.clip(np.einsum('ij,ij->i',point-a,edge)/np.maximum(np.einsum('ij,ij->i',edge,edge),1e-20),0,1)
        distance=np.minimum(distance,np.linalg.norm(point-a-edge*t[:,None],axis=1))
    return float(distance.min())

def boundary(faces):
    edges=collections.Counter();positions={};attrs={};directed={}
    for f in faces:
        keys=[tuple(np.rint(p[:3]*100000).astype(int)) for p in f]
        for k,p in zip(keys,f):positions[k]=p[:3];attrs[k]=p
        for j,a in enumerate(keys):
            b=keys[(j+1)%3]
            if a==b:continue
            edge=tuple(sorted((a,b)));edges[edge]+=1;directed[edge]=(a,b)
    # Normalize collinear T-junctions left by the stock triangulation or a cap:
    # a long edge and two shorter edges describe a sealed geometric seam.
    border=[e for e,c in edges.items() if c==1]
    keys=sorted({k for edge in border for k in edge})
    if keys:
        q=np.asarray(keys,dtype=float)
        for a,b in border:
            A=np.asarray(a,dtype=float);B=np.asarray(b,dtype=float);delta=B-A;norm=delta@delta
            if norm<=0:continue
            t=((q-A)@delta)/norm
            distance=np.linalg.norm((q-A)-t[:,None]*delta,axis=1)
            mask=(t>1e-8)&(t<1-1e-8)&(distance<.05)
            mid=sorted([(float(t[i]),keys[i]) for i in np.flatnonzero(mask)])
            if not mid:continue
            edges[(a,b)]-=1;chain=[a]+[k for _,k in mid]+[b]
            for x,y in zip(chain,chain[1:]):
                edge=tuple(sorted((x,y)));edges[edge]+=1
                directed.setdefault(edge,(x,y) if directed[(a,b)]==(a,b) else (y,x))
    return {e for e,c in edges.items() if c==1},positions,attrs,directed

def cap_faces(faces,layout):
    """Close every boundary of the moving section with real single-sided faces."""
    if not faces:return [],[]
    edges,points,attrs,directed=boundary(faces);todo=set(edges);adj=collections.defaultdict(set)
    for a,b in edges:adj[a].add(b);adj[b].add(a)
    assert all(len(v)%2==0 for v in adj.values()), 'gun section has an open boundary; revise its selection'
    caps=[];contours=[]
    while todo:
        a,b=min(todo);walk=[a];cur=b;todo.remove(tuple(sorted((a,b))))
        while cur not in walk:
            walk.append(cur)
            nxt=next(v for v in sorted(adj[cur]) if tuple(sorted((cur,v))) in todo)
            todo.remove(tuple(sorted((cur,nxt))));cur=nxt
        start=walk.index(cur);loop=walk[start:]
        # Touching rear contours can share a vertex. Close each simple cycle
        # separately, returning any leading path to the pending edge set.
        for x,y in zip(walk[:start],walk[1:start+1]):todo.add(tuple(sorted((x,y))))
        # Reverse the incident surface edge so the cap winds outward.
        if directed[tuple(sorted((loop[0],loop[1])))]==(loop[0],loop[1]):loop.reverse()
        p=np.asarray([points[k] for k in loop]);center=p.mean(0)
        n=np.zeros(3)
        for i in range(len(p)):n+=np.cross(p[i]-center,p[(i+1)%len(p)]-center)
        length=np.linalg.norm(n)
        if length<1e-10:continue
        n/=length
        # Planar boundaries use the existing ear-clipping tessellator.
        try:indices=cockpitsections.triangulate(p,n)
        except AssertionError:
            # Minimum-area triangulation of a nonplanar section boundary.
            # Unlike a center fan this respects the ordered perimeter even
            # when the surface cannot be flattened into a simple projection.
            count=len(p);cost=np.full((count,count),np.inf);split={}
            for i in range(count-1):cost[i,i+1]=0
            for gap in range(2,count):
                for i in range(count-gap):
                    j=i+gap
                    for k in range(i+1,j):
                        area=np.linalg.norm(np.cross(p[k]-p[i],p[j]-p[i]))
                        score=cost[i,k]+cost[k,j]+area
                        if area>1e-10 and score<cost[i,j]:cost[i,j]=score;split[i,j]=k
            assert np.isfinite(cost[0,count-1]),'degenerate cap boundary'
            indices=[]
            def emit(i,j):
                if j-i<2:return
                k=split[i,j];indices.append([i,k,j]);emit(i,k);emit(k,j)
            emit(0,count-1);indices=np.asarray(indices)
        avg=np.mean([attrs[k] for k in loop],axis=0);rows=np.tile(avg,(len(p),1));rows[:,:3]=p
        for e,start,count in layout:
            if e.semantic==4:rows[:,start:start+3]=n
            if e.semantic==9:
                tangent=np.cross(n,np.eye(3)[np.argmin(abs(n))]);tangent/=np.linalg.norm(tangent);rows[:,start:start+3]=tangent
        cap=rows[indices]
        for f in cap:
            face_normal=np.cross(f[1,:3]-f[0,:3],f[2,:3]-f[0,:3]);face_normal/=np.linalg.norm(face_normal)
            for e,start,count in layout:
                if e.semantic==4:f[:,start:start+3]=face_normal
        caps.extend(cap);contours.append({'points':p.tolist(),'edges':[list(map(list,e)) for e in edges if e[0] in loop and e[1] in loop]})
    remaining=boundary([*faces,*caps])[0]
    assert not remaining, f'moving gun still has uncovered faces: {len(remaining)} {list(remaining)[:8]}'
    return caps,contours

def partition(faces,lo,hi):
    moving=list(faces);fixed=[]
    for axis in range(3):
        n=np.eye(3)[axis]
        moving,out=split_faces(moving,n,lo[axis]);fixed.extend(out)
        moving,out=split_faces(moving,-n,-hi[axis]);fixed.extend(out)
        if not moving:break
    return moving,fixed

def channels_mesh(mesh,skel,channels,cockpit=False):
    """Keep each selected surface beneath its original live driver in both views."""
    byid={b.handle:b for b in skel.bones};proof=[];helpers={};next_handle=max(byid)+1
    component_bounds={}
    if not cockpit and any(ch.get('component_regions') for ch in channels):
        # Reviewed disconnected tubes can overlap armor in an axis-aligned view.
        # Restrict those selections to actual source components before cutting.
        parents={};positions={}
        def root(k):
            parents.setdefault(k,k)
            while parents[k]!=k:
                parents[k]=parents[parents[k]];k=parents[k]
            return k
        def key(owner,p):return (owner,*np.rint(np.asarray(p)*1e5).astype(int))
        for sub in mesh.submeshes:
            g=mesh.shared_geometry if sub.uses_shared_vertices else sub.geometry
            a=mesh.bone_assignments if sub.uses_shared_vertices else sub.bone_assignments;own={i:b for i,b,w in a if w>.99};p=np.asarray(g.attribute(1))
            for face in sub.triangles():
                owner=own.get(face[0])
                if owner is None or not all(own.get(i)==owner for i in face):continue
                ks=[key(owner,p[i]) for i in face]
                for k,i in zip(ks,face):positions[k]=p[i]
                for k in ks[1:]:parents[root(k)]=root(ks[0])
        bounds={}
        for k,p in positions.items():
            r=root(k)
            if r not in bounds:bounds[r]=[p.copy(),p.copy()]
            else:bounds[r]=[np.minimum(bounds[r][0],p),np.maximum(bounds[r][1],p)]
        component_bounds={k:bounds[root(k)] for k in positions}
    for ch in channels:proof.append({'hardpoints':ch['hardpoints'],'triangles':0,'cap_triangles':0,'cockpit':cockpit,'helpers':[]})
    def helper(j,driver):
        nonlocal next_handle
        key=(j,driver)
        if key in helpers:return helpers[key]
        ch=channels[j];parent=byid[driver]
        if not cockpit and ch.get('motion_parent'):
            parent=next(b for b in skel.bones if b.name==ch['motion_parent'])
        pos,rot=flash.bone_world(skel,parent.handle)
        pivot=np.asarray(ch.get('cockpit_pivot',ch['pivot']) if cockpit else ch['pivot'])
        local=flash._rotate(flash._conj(rot),pivot-np.asarray(pos))
        bone=Bone(f'crgun_{j+1}_{driver}',next_handle,tuple(local),parent=parent.handle);next_handle+=1;skel.bones.append(bone)
        helpers[key]=(bone,rot);proof[j]['helpers'].append({'bone':bone.name,'parent':parent.name})
        return bone,rot
    for sub in mesh.submeshes:
        if cockpit and 'glass' in sub.material.lower():continue
        geo=mesh.shared_geometry if sub.uses_shared_vertices else sub.geometry
        if geo is None:continue
        rows,layout=attributes(geo);assignments=mesh.bone_assignments if sub.uses_shared_vertices else sub.bone_assignments
        owners=np.full(len(rows),-1,dtype=int)
        for i,b,w in assignments:
            assert w==1.0,'gun builder requires rigid source weights'
            owners[i]=b
        faces=np.asarray(sub.triangles(),dtype=int)
        if not len(faces):continue
        rows=np.column_stack([rows,owners])
        fragments=[(rows[f],int(owners[f[0]]) if len(set(owners[f]))==1 else -2) for f in faces];new=[]
        touched=False
        for j,ch in enumerate(channels):
            if cockpit and ch.get('cockpit_materials') is not None and sub.material not in ch['cockpit_materials']:continue
            if cockpit and ch.get('cockpit_materials') is None and not any(word in sub.material.lower() for word in ('gun','nose','exterior','headhull','sectionbacks','originalframe','foredeck')) and ch.get('allow_stock_cockpit') is not True:continue
            lo=np.asarray(ch.get('cockpit_lo',ch['lo']) if cockpit else ch['lo']);hi=np.asarray(ch.get('cockpit_hi',ch['hi']) if cockpit else ch['hi'])
            eligible=set(ch.get('bones',[]));eligible_ids={b.handle for b in skel.bones if b.name in eligible}
            extracted={};keep=[];fixed_parts=[]
            for f,owner in fragments:
                if (not cockpit and owner not in eligible_ids) or owner<0:keep.append((f,owner));continue
                if not cockpit and ch.get('component_regions'):
                    bounds=component_bounds.get(key(owner,f[0,:3]))
                    if bounds is None or not any(np.all(bounds[0]>=np.asarray(r['lo'])-1e-4) and np.all(bounds[1]<=np.asarray(r['hi'])+1e-4) for r in ch['component_regions']):
                        keep.append((f,owner));continue
                a,b=partition([f],lo,hi)
                if ch.get('cylinder_radius'):
                    # A spinning cluster needs a round rear interface; an AABB
                    # would also rotate square receiver corners into the mount.
                    center=np.asarray(ch.get('cockpit_pivot',ch['pivot']) if cockpit else ch['pivot'])
                    for k in range(16):
                        angle=math.tau*k/16;normal=np.asarray([math.cos(angle),math.sin(angle),0])
                        a,outside=split_faces(a,normal,float(center@normal)-ch['cylinder_radius']);b.extend(outside)
                if a:extracted.setdefault(owner,[]).extend(a)
                fixed_parts.extend((v,owner) for v in b)
            if not extracted:continue
            touched=True
            for driver,pieces in extracted.items():
                bone,_=helper(j,driver);caps,contours=cap_faces(pieces,layout)
                cut_edges=boundary(pieces)[0] & boundary([f for f,b in fixed_parts if b==driver])[0]
                if cut_edges:
                    for f in caps:
                        back=f[::-1].copy()
                        for e,start,count in layout:
                            if e.semantic==4:back[:,start:start+3]*=-1
                        fixed_parts.append((back,driver))
                new.extend((f,bone.handle) for f in [*pieces,*caps])
                proof[j]['triangles']+=len(pieces);proof[j]['cap_triangles']+=len(caps)
            fragments=keep+fixed_parts
        if not touched:continue
        fragments+=new
        data=np.concatenate([f for f,_ in fragments]);own=np.concatenate([np.full(3,b) if b!=-2 else np.rint(f[:,-1]).astype(int) for f,b in fragments])
        data[:,-1]=own
        unique,remap=np.unique(data.astype('<f4'),axis=0,return_inverse=True)
        own=unique[:,-1].astype(int)
        sub.geometry=encode(unique,layout);sub.uses_shared_vertices=False
        sub.indices=remap.tolist();sub.use32bit=len(unique)>65535
        sub.bone_assignments=[(i,int(b),1.0) for i,b in enumerate(own) if b>=0]
    for j,ch in enumerate(channels):
        tracks=[]
        for (channel,driver),(bone,rot) in helpers.items():
            if channel!=j:continue
            world_axis=ch.get('cockpit_axis',[0,0,1]) if cockpit else [0,0,1]
            axis=np.asarray(flash._rotate(flash._conj(rot),world_axis));axis/=np.linalg.norm(axis)
            if ch.get('spin'):
                keys=[];duration=.1
                for k in range(5):
                    angle=math.pi*k/2;quat=tuple(axis*math.sin(angle/2))+(math.cos(angle/2),);keys.append(Keyframe(k*duration/4,quat))
            else:
                duration=ch.get('duration',.15);kick=-axis*ch.get('distance',.1)
                keys=[Keyframe(0,translation=tuple(kick)),Keyframe(duration*.2,translation=tuple(kick*.8)),Keyframe(duration)]
            tracks.append(Track(bone.handle,keys))
        # Empty cockpit tracks mean the gun is absent from this cockpit resource.
        skel.animations.append(Animation(ch['clip'],.1 if ch.get('spin') else ch.get('duration',.15),tracks))
    return proof
