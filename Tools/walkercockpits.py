"""Grounded NSDF/Black Dog walker cockpits with independently skinned gun arms."""
from pathlib import Path
from collections import Counter
import io,hashlib
import numpy as np
import combatcockpits as hardware
import reddevilcockpit as shared
import scoutcockpits as scout
import tankcockpits as tank
import walkerpose
from bzmodellibs import legacy,legacy_port

CONFIG={
 'avwalk':dict(faction='nsdf',shell='age21hed',material='CRV/NSDFScoutCockpit',exterior='avwalk00'),
 'bvwalk':dict(faction='bdog',shell='age21hed',material='CRV/BDogScoutCockpit',exterior='bvwalk_00')}
ARM_NAMES=('age11lsh','age11rsh','age11tx1','age11tx2')
LAYOUT=dict(role='walker',width=1.05,lip=-.48,front=1.22,roof=.80,back=-.80)
ARM_FIT=dict(mode='native-firing-ray',muzzleDistance=1.60)

def boundary_loops(faces):
    edges=Counter();points={}
    for face in faces:
        keys=[tuple(np.rint(v*10000).astype(np.int64)) for v in face];points.update(zip(keys,face))
        for i in range(3):edges[tuple(sorted((keys[i],keys[(i+1)%3])))]+=1
    border={edge for edge,count in edges.items() if count==1};adj={}
    for a,b in border:adj.setdefault(a,set()).add(b);adj.setdefault(b,set()).add(a)
    assert all(len(v)==2 for v in adj.values())
    result=[]
    while border:
        a,b=min(border);loop=[a];previous=a;current=b;border.remove(tuple(sorted((a,b))))
        while current!=loop[0]:
            loop.append(current);nxt=next(v for v in adj[current] if v!=previous);border.remove(tuple(sorted((current,nxt))));previous,current=current,nxt
        result.append(np.array([points[v] for v in loop]))
    return result

def ray_frame(axis):
    z=np.array(axis)/np.linalg.norm(axis);x=np.cross([0.,1.,0.],z);x/=np.linalg.norm(x);return np.column_stack([x,np.cross(z,x),z])

def geometry(fullpath,fullskel,skelpath,base,game,root):
    cfg=CONFIG[base];s,w,eye,shell=shared.rig(skelpath,cfg['shell']);native=tank.native_eye(w,eye,game,base,root);origin,R=w[eye.handle]
    h=hardware.Hardware(origin,R,scout.CHARTS,hardware.ART_ASPECT[cfg['faction']])
    # A broad industrial command station, not a scout canopy: split low banks
    # leave the central sightline and waist-height gun-arm side windows open.
    for sign in (-1,1):
        h.cassette([(sign*.18,-.49,1.16),(sign*.86,-.47,1.10),(sign*.80,-.78,.65),(sign*.15,-.80,.72)],'console',.036,section=(0,.33) if sign>0 else (.68,1))
        h.cassette([(sign*.85,-.55,.65),(sign*1.01,-.55,-.32),(sign*.92,-.85,-.48),(sign*.72,-.86,.42)],'switch' if sign>0 else 'service',.026)
        h.cassette([(sign*.98,-.79,-.66),(sign*.94,-.79,.83),(sign*.68,-.96,.83),(sign*.71,-.96,-.66)],'armor',.012)
        h.cassette([(sign*.20,-.96,-.24),(sign*.58,-.96,-.24),(sign*.58,-.84,.62),(sign*.20,-.84,.62)],'armor',.012)
        for z in (-.02,.16,.34,.52):
            y=-.96+(z+.24)*(.12/.86)+.025;h.beam((sign*.24,y,z),(sign*.54,y,z),.018,'trim')
        h.beam((sign*1.05,-.48,1.22),(sign*1.134,-.48,-.80),.040)
        h.beam((sign*1.134,-.48,-.80),(sign*1.134,.80,-.80),.038)
        h.beam((sign*.662,.80,.366),(sign*1.134,.80,-.80),.028)
        h.beam((sign*1.05,-.48,1.22),(sign*1.16,.35,.80),.028)
        h.beam((sign*1.16,.35,.80),(sign*.662,.80,.366),.028)
    h.cassette([(-.15,-.79,.74),(.15,-.79,.74),(.13,-.98,.20),(-.13,-.98,.20)],'service',.022)
    topology=h.enclosure(LAYOUT)
    # Select real complete arm components, excluding hardpoint marker cubes.
    body=shared.read_mesh(fullpath).submesh_list[0];p=shared.values(body.vertex_data,shared.om.VES.POSITION);tri=body.index_array.reshape(-1,3)
    fs,fw,fe,fsh=shared.rig(fullskel,cfg['shell']);source_names={b.handle:b.name for b in fs.bones()};target={b.name:b.handle for b in s.bones()};weight=np.zeros(len(p))
    for a in body.bone_assignments():
        if source_names.get(a.bone_index) in ARM_NAMES:weight[a.vertex_index]+=a.weight
    q=p[tri];keep=(weight[tri]>.99).all(1)&(np.linalg.norm(np.cross(q[:,1]-q[:,0],q[:,2]-q[:,0]),axis=1)>1e-9);arms,ix,used=tank.source_part(body,keep);remap={int(v):i for i,v in enumerate(used)};weights=[]
    for a in body.bone_assignments():
        if a.vertex_index in remap:weights.append((remap[a.vertex_index],target[source_names[a.bone_index]],a.weight))
    records=legacy.read_vdf(native).parts;mirror=np.diag([-1.,1.,1.]);native_rotations={record.name:(mirror@np.array(record.matrix[:9]).reshape(3,3).T@mirror).tolist() for record in records if record.name in target}
    # Native legacy firing transforms, including translation, are authoritative.
    # Stock Ogre bind positions are NOT a substitute for these hardpoints.
    absolute={}
    for record in records:
        if record.band!=0:continue
        local=legacy_port._local_matrix(record.matrix);absolute[record.name]=legacy_port._mul(absolute[record.parent],local) if record.parent in absolute else local
    bind=walkerpose.world(s);posed=walkerpose.world(s,native_rotations);deltas={h:posed[h]@np.linalg.inv(bind[h]) for h in bind}
    source_arms=arms.copy();transforms={};firing=[]
    for upper,fore,hp in [('age11lsh','age11tx2','AGe11GC1'),('age11rsh','age11tx1','AGe11GC2')]:
        handle=target[fore];ids=np.array([i for i,b,weight in weights if b==handle]);ids_set=set(ids);faces=ix.reshape(-1,3);faces=faces[np.array([all(int(v) in ids_set for v in t) for t in faces])]
        raw_loops=boundary_loops(source_arms[:,:3][faces]);bore=next(p for p in raw_loops if len(p)==16);delta=deltas[handle];bore=bore@delta[:3,:3].T+delta[:3,3];center=bore.mean(0);_,_,axes=np.linalg.svd(bore-center);axis=axes[-1]
        if axis[2]<0:axis=-axis
        native_hp=np.array(absolute[hp]);shot=mirror@native_hp[:3,3];direction=mirror@native_hp[:3,2];direction/=np.linalg.norm(direction)
        turn=ray_frame(direction)@ray_frame(axis).T;opening=shot+direction*ARM_FIT['muzzleDistance'];fit=np.eye(4);fit[:3,:3]=turn;fit[:3,3]=opening-turn@center
        for name in (upper,fore):
            hnd=target[name];T=np.linalg.inv(deltas[hnd])@fit@deltas[hnd];transforms[hnd]=T
            selected=[i for i,b,wgt in weights if b==hnd];arms[selected,:3]=source_arms[selected,:3]@T[:3,:3].T+T[:3,3]
            for channel in (slice(3,6),slice(8,11)):arms[selected,channel]=source_arms[selected,channel]@T[:3,:3].T
        firing.append(dict(hardpoint=hp,forearm=fore,upper=upper,origin=shot.tolist(),direction=direction.tolist(),sourceBore=bore.tolist(),opening=opening.tolist(),poseFit=fit.tolist()))
    # Back only the small upper-arm socket openings; the forearm's three front
    # barrel bores per side are intentional weapon cavities, not missing armor.
    caps=hardware.Hardware(origin,R,scout.CHARTS);capweights=[];capmeta=[]
    for name in ('age11lsh','age11rsh'):
        source_bone=fs.get_bone_by_name(name).handle;verts={a.vertex_index for a in body.bone_assignments() if a.bone_index==source_bone and a.weight>.99};mask=np.array([all(int(v) in verts for v in t) for t in tri]);faces=q[mask]
        for source_polygon in boundary_loops(faces):
            T=transforms[target[name]];polygon=source_polygon@T[:3,:3].T+T[:3,3];c=polygon.mean(0);_,sv,axes=np.linalg.svd(polygon-c);normal=axes[-1]
            if normal[1]>0:normal=-normal
            assert sv[-1]<.001 and len(polygon)==12,'only expected tiny socket is backed'
            start=len(caps.rows);caps.face((polygon-origin)@R,'trim',hint=normal@R);capweights.extend((i,target[name],1.) for i in range(start,len(caps.rows)));capmeta.append(dict(bone=target[name],name=name,points=polygon.tolist()))
    parts={cfg['material']:h.part(),'CRV/'+base+'GunArms':(arms,ix),'CRV/'+base+'JointBacks':caps.part()}
    chain_names={'age11bda','age11ty1','age11lsh','age11rsh','age11tx1','age11tx2','AGe11GC1','AGe11GC2'}
    chain=[dict(name=p.name,parent=p.parent,matrix=list(p.matrix)) for p in records if p.band==0 and p.name in chain_names]
    meta=dict(base=base,faction=cfg['faction'],pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,layout=LAYOUT,panels=h.panels,innerShell=topology,sourceArmTriangles=np.flatnonzero(keep).tolist(),armBones={name:target[name] for name in ARM_NAMES},armFit=ARM_FIT,armTransforms={str(k):v.tolist() for k,v in transforms.items()},firingRays=firing,nativeFiringParts=chain,armWeights=weights,capWeights=capweights,jointBacks=capmeta,nativeBoneRotations=native_rotations,nativeVdfSha256=hashlib.sha256(native).hexdigest(),sourceArmFixture=dict(data=source_arms,indices=ix,weights=np.array(weights,float)))
    return parts,s,w,eye,shell,meta

def compile_mesh(parts,s,w,eye,shell,base,meta):
    # Glass fits the stable interior only. Distant moving arms must not inflate
    # the canopy fitter or be rebound wholesale to the stationary shell.
    interior={name:part for name,part in parts.items() if name==CONFIG[base]['material']};raw,glass=shared.mesh_bytes(interior,s,w,eye,shell,skeleton_name=base+'_c.skeleton');model=shared.oms.MeshSerializer(io.BytesIO(raw)).read()
    # Reuse the shared append writer; it retains per-vertex bone handles.
    from lighttankmarkings import model_bytes
    for suffix,key in [('GunArms','armWeights'),('JointBacks','capWeights')]:
        data,indices=parts['CRV/'+base+suffix]
        if data.shape[1]==8:
            # Use the established authoring compiler for mapped tangents.
            temp,_=shared.mesh_bytes({'joint':(data,indices)},s,w,eye,shell);sub=shared.oms.MeshSerializer(io.BytesIO(temp)).read().submesh_list[0]
            data=np.column_stack([shared.values(sub.vertex_data,sem) for sem in (shared.om.VES.POSITION,shared.om.VES.NORMAL,shared.om.VES.TEXTURE_COORDINATES,shared.om.VES.TANGENT)])
        handles=np.full(len(data),-1)
        for i,b,weight in meta[key]:assert weight==1;handles[i]=b
        assert (handles>=0).all();raw=model_bytes(model,data,indices,handles,'CRV/'+base+suffix);model=shared.oms.MeshSerializer(io.BytesIO(raw)).read()
    return raw,glass
