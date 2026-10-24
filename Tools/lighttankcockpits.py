"""Open Wolverine cockpits; retain the exact stock-painted exterior framing."""
import hashlib
import numpy as np
import combatcockpits as hardware
import reddevilcockpit as shared
import scoutcockpits as scout
import tankcockpits as tank
import lighttankmarkings as markings

CONFIG={
 'avltnk':dict(faction='nsdf',shell='aln21bdb',bodyBone=1,material='CRV/NSDFScoutCockpit',stock='avltnk00'),
 'bvltnk':dict(faction='bdog',shell='bln21bdb',bodyBone=3,material='CRV/BDogScoutCockpit',stock='bvltnk00')}
LAYOUT=dict(role='lighttank',width=.70,lip=-.37,front=.86,roof=.57,back=-.65)

def geometry(source,skelpath,base,game,root):
    cfg=CONFIG[base];s,w,eye,shell=shared.rig(skelpath,cfg['shell']);native=tank.native_eye(w,eye,game,base,root);origin,R=w[eye.handle]
    h=hardware.Hardware(origin,R,scout.CHARTS,hardware.ART_ASPECT[cfg['faction']])
    # Relocate the old tall side-wall equipment to a low, squat central bank.
    # No new A-pillars: the original painted exterior already frames the view.
    h.cassette([(-.50,-.28,.94),(.50,-.28,.94),(.44,-.54,.63),(-.44,-.54,.63)],'console',.032)
    for sign in (-1,1):
        h.cassette([(sign*.48,-.45,.58),(sign*.67,-.43,-.10),(sign*.62,-.72,-.31),(sign*.42,-.74,.36)],'switch' if sign>0 else 'service',.025)
        h.cassette([(sign*.66,-.75,-.52),(sign*.63,-.75,.65),(sign*.47,-.92,.65),(sign*.50,-.92,-.52)],'armor',.012)
        h.cassette([(sign*.10,-.96,-.20),(sign*.39,-.96,-.20),(sign*.39,-.86,.57),(sign*.10,-.86,.57)],'armor',.012)
        for z in (.01,.17,.33,.49):
            y=-.96+(z+.20)*(.10/.77)+.025
            h.beam((sign*.13,y,z),(sign*.36,y,z),.017,'trim')
        h.beam((sign*.70,-.37,.86),(sign*.756,-.37,-.65),.033)
        h.beam((sign*.756,-.37,-.65),(sign*.756,.57,-.65),.033)
        h.beam((sign*.441,.57,.258),(sign*.756,.57,-.65),.025)
    h.cassette([(-.16,-.74,.49),(.16,-.74,.49),(.14,-.94,-.04),(-.14,-.94,-.04)],'service',.020)
    topology=h.enclosure(LAYOUT)
    # Only the original shell-weighted exterior rail/overhead group. Neither
    # its position nor its paint/UVs are modified, and no whole body is added.
    body=shared.read_mesh(source).submesh_list[0];p=shared.values(body.vertex_data,shared.om.VES.POSITION);tri=body.index_array.reshape(-1,3);weight=np.zeros(len(p))
    for a in body.bone_assignments():
        if a.bone_index==shell.handle:weight[a.vertex_index]+=a.weight
    q=p[tri];area2=np.linalg.norm(np.cross(q[:,1]-q[:,0],q[:,2]-q[:,0]),axis=1);keep=(weight[tri]>.99).all(1)&(area2>1e-9)
    framing,indices,_=tank.source_part(body,keep)
    parts={cfg['material']:h.part(),'CRV/'+base+'OriginalFrame':(framing,indices)}
    paint,paint_indices,_,paint_source=markings.geometry(body,origin,[shell.handle],cfg['faction']);parts['CRV/'+base+'HullPaint']=(paint,paint_indices)
    meta=dict(base=base,faction=cfg['faction'],pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,layout=LAYOUT,panels=h.panels,innerShell=topology,exteriorSourceIndices=np.flatnonzero(keep).tolist(),exteriorTransform=np.eye(4).tolist(),nativeVdfSha256=hashlib.sha256(native).hexdigest())
    meta['paintTriangles']=paint_source
    return parts,s,w,eye,shell,meta
