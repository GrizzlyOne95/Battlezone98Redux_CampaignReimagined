"""CRA heavy-tank armored command cockpit, with native-coordinate hull/gun cues."""
import io
import numpy as np
import reddevilcockpit as shared
import combatcockpits as hardware
import tankcockpits as tank
import cockpitsections
from lighttankmarkings import model_bytes

MATERIAL='CRV/CVBomberCockpit';EXTERIOR='CRV/CVHeavyExterior';CAPS='CRV/CVHeavySectionBacks'
LAYOUT=dict(role='heavy',width=.80,lip=-.37,front=1.12,roof=.43,back=-.65)

def geometry(source,skelpath,game,root):
    s,w,eye,shell=shared.rig(skelpath,'CEM21BDA');tank.native_eye(w,eye,game,'cvhtnk',root);origin,R=w[eye.handle]
    h=hardware.Hardware(origin,R,hardware.CRA_CHARTS,hardware.ART_ASPECT['cra'])
    h.cassette([(-.63,-.39,1.09),(.63,-.39,1.09),(.56,-.69,.66),(-.56,-.69,.66)],'console',.040)
    for sign in (-1,1):
        h.cassette([(sign*.60,-.46,.70),(sign*.79,-.45,.14),(sign*.75,-.74,-.09),(sign*.54,-.75,.45)],'switch' if sign<0 else 'service',.035)
        h.cassette([(sign*.75,-.78,-.42),(sign*.72,-.78,.53),(sign*.51,-.94,.59),(sign*.51,-.94,-.42)],'armor',.016)
        h.beam((sign*.80,-.37,1.12),(sign*.864,-.37,-.65),.060,'armor')
        h.beam((sign*.80,-.37,1.12),(sign*.82,.10,.76),.052,'frame')
        h.beam((sign*.82,.10,.76),(sign*.504,.43,.336),.048,'armor')
        h.beam((sign*.504,.43,.336),(sign*.864,.43,-.65),.050,'frame')
        h.beam((sign*.864,-.37,-.65),(sign*.864,.43,-.65),.065,'armor')
        for z in (-.25,-.06,.13,.32):h.beam((sign*.55,-.90,z),(sign*.69,-.80,z),.018,'frame')
    h.beam((-.80,-.37,1.12),(.80,-.37,1.12),.065,'armor')
    h.beam((-.504,.43,.336),(.504,.43,.336),.055,'armor')
    h.cassette([(-.18,-.72,.60),(.18,-.72,.60),(.16,-.96,.17),(-.16,-.96,.17)],'service',.023)
    topology=h.enclosure(LAYOUT)
    # Rear armor ribs and a small access panel finish the cabin without forward clutter.
    for x in (-.60,-.24,.24,.60):h.beam((x,-.86,-.63),(x,.36,-.63),.032,'frame')
    h.cassette([(-.20,-.16,-.60),(.20,-.16,-.60),(.20,-.50,-.60),(-.20,-.50,-.60)],'switch',.018)
    body=shared.read_mesh(source).submesh_list[0];p=shared.values(body.vertex_data,shared.om.VES.POSITION);tri=body.index_array.reshape(-1,3);q=p[tri];weights={a.vertex_index:a.bone_index for a in body.bone_assignments()};valid=np.linalg.norm(np.cross(q[:,1]-q[:,0],q[:,2]-q[:,0]),axis=1)>1e-9
    configs=[('bow',0,[([0,0,1],1.95),([0,-1,0],-2.30)]),('portGunPod',1,[]),('starboardGunPod',3,[])];rows=[];backs=[];handles=[];cap_handles=[];sections=[]
    for name,bone,planes in configs:
        mask=valid&np.array([all(weights.get(int(v))==bone for v in t) for t in tri]);raw,ix,_=tank.source_part(body,mask);a,b,audit=cockpitsections.section(raw,ix,np.flatnonzero(mask),planes,hardware.CRA_CHARTS['trim']);driver=shell.handle if bone==0 else bone
        rows.append(a[0]);backs.append(b[0]);handles.extend([driver]*len(a[0]));cap_handles.extend([driver]*len(b[0]));sections.append(dict(name=name,sourceBone=bone,driver=driver,**audit))
    data=np.concatenate(rows);caps=np.concatenate(backs);parts={MATERIAL:h.part(),EXTERIOR:(data,np.arange(len(data),dtype='<u2')),CAPS:(caps,np.arange(len(caps),dtype='<u2'))}
    meta=dict(pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,layout=LAYOUT,panels=h.panels,innerShell=topology,sections=sections,exteriorTransform=np.eye(4).tolist(),exteriorHandles=handles,capHandles=cap_handles)
    return parts,s,w,eye,shell,meta

def compile_mesh(parts,s,w,eye,shell,meta):
    raw,glass=shared.mesh_bytes({MATERIAL:parts[MATERIAL]},s,w,eye,shell,skeleton_name='cvhtnk_cockpit.skeleton');mesh=shared.oms.MeshSerializer(io.BytesIO(raw)).read()
    for material,key in [(EXTERIOR,'exteriorHandles'),(CAPS,'capHandles')]:
        data,indices=parts[material];raw=model_bytes(mesh,data,indices,np.array(meta[key]),material);mesh=shared.oms.MeshSerializer(io.BytesIO(raw)).read()
    # The shared append writer leaves the previous AABB unchanged. Recompute it
    # for the appended native-coordinate bow and pod assemblies.
    points=np.concatenate([shared.values(sub.vertex_data,shared.om.VES.POSITION) for sub in mesh.submesh_list]);lo=points.min(0);hi=points.max(0);mesh.aabb=shared.om.AxisAlignedBoundingBox(*lo,*hi);mesh.bound_radius=float(np.linalg.norm(points,axis=1).max());out=io.BytesIO();shared.oms.MeshSerializer(out).write(mesh)
    return out.getvalue(),glass
