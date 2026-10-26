"""CRA light tank and CRA/CCA head-armored walker cockpits; native-rest fitting."""
import io
import numpy as np
import ogrelayout
import reddevilcockpit as shared
import combatcockpits as hw
import tankcockpits as tank
import cockpitsections as sections
import walkerpose
from bomberrocketcockpits import stable_caps
from lighttankmarkings import model_bytes
from bzmodellibs import legacy

CONFIG={
 'cvltnk':dict(faction='cra',shell='CNA21BDA',resource='cvltnk_cockpit',material='CRV/CVBomberCockpit',exterior='cvltnk',role='lighttank',width=.61,lip=-.34,front=.88,roof=.31,back=-.40),
 'cvwalk':dict(faction='cra',shell='cvw21hed',resource='cvwalk_c',material='CRV/CVBomberCockpit',exterior='cvwalk00',role='walker',width=.82,lip=-.43,front=1.08,roof=.48,back=-.60),
 'svwalk':dict(faction='cca',shell='svw21hed',resource='svwalk_c',material='CRV/CCAMechanicalCockpit',exterior='svwalk00',role='walker',width=.82,lip=-.43,front=1.08,roof=.48,back=-.60)}


def native_rig(skelpath,shellname,native):
    s,_,eye,shell=shared.rig(skelpath,shellname);mirror=np.diag([-1.,1.,1.]);records=legacy.read_vdf(native).parts
    rot={p.name:(mirror@np.array(p.matrix[:9]).reshape(3,3).T@mirror).tolist() for p in records if p.name.lower()!='null'}
    bind=walkerpose.world(s);posed=walkerpose.world(s,rot);world={h:(m[:3,3],m[:3,:3]) for h,m in posed.items()}
    return s,world,eye,shell,bind,posed,rot


def transform(data,T):
    d=data.copy();d[:,:3]=d[:,:3]@T[:3,:3].T+T[:3,3];d[:,3:6]=d[:,3:6]@T[:3,:3].T
    if d.shape[1]>8:d[:,8:11]=d[:,8:11]@T[:3,:3].T
    return d


def configs(base,origin,R):
    if base=='cvltnk':return [('bow',0,1291,[([0,0,1],2.2)]),('overheadCannon',0,0,[([0,0,1],1.12)])]
    def plane(n,v):
        n=R@np.array(n,float);return n.tolist(),float(origin@n+v)
    return [('chin',5,7192,[plane([0,0,1],1.05),plane([0,-1,0],.56)]),('brow',5,7192,[plane([0,0,1],.90),plane([0,1,0],.32)])]


def geometry(source,fullrig,rigpath,base,native):
    cfg=CONFIG[base];s,w,eye,shell,bind,posed,rot=native_rig(rigpath,cfg['shell'],native);origin,R=w[eye.handle]
    charts=hw.CRA_CHARTS if cfg['faction']=='cra' else hw.CCA_CHARTS;h=hw.Hardware(origin,R,charts,hw.ART_ASPECT[cfg['faction']]);width=cfg['width'];lip=cfg['lip'];front=cfg['front'];roof=cfg['roof'];back=cfg['back']
    if base=='cvltnk':
        rim=[(-.61,-.34,.88),(0,-.37,1.03),(.61,-.34,.88),(.65,.07,.60),(.38,.31,.264),(-.38,.31,.264),(-.65,.07,.60)]
        for sign in (-1,1):
            h.cassette([(sign*.07,-.37,.85),(sign*.50,-.36,.81),(sign*.46,-.61,.53),(sign*.07,-.62,.57)],'switch' if sign<0 else 'service',.024)
            h.cassette([(sign*.46,-.46,.49),(sign*.57,-.44,-.06),(sign*.51,-.73,-.18),(sign*.39,-.74,.34)],'service' if sign<0 else 'switch',.020)
        # A closed low bridge supports the real sloped bow without a full hull.
        h.fairing((0,-.48,.93),(0,-.79,1.70),1.12,.12)
        h.fairing((0,.42,.22),(0,.39,.68),.52,.32)
    else:
        # Visor-like head opening, not an NSDF waist-height command cab. The
        # actual brow and chin supply the distinctive Golem family silhouette.
        rim=[(-.82,-.43,1.08),(.82,-.43,1.08),(.88,.04,.78),(.52,.48,.324),(-.52,.48,.324),(-.88,.04,.78)]
        for sign in (-1,1):
            h.cassette([(sign*.11,-.46,1.01),(sign*.68,-.43,.96),(sign*.63,-.73,.59),(sign*.10,-.74,.67)],'switch' if sign>0 else 'service',.030)
            h.cassette([(sign*.66,-.54,.56),(sign*.78,-.50,-.18),(sign*.72,-.81,-.34),(sign*.55,-.84,.36)],'service' if sign>0 else 'switch',.025)
            h.fairing((sign*.69,-.48,.96),(sign*.89,-.55,1.24),.24,.12)
            h.beam((sign*.84,.43,.96),(sign*.88,.04,.78),.042,'frame')
        # Closed visor bridge ties the source brow into the cabin roof. A
        # detached source slice is not a convincing head enclosure.
        h.fairing((0,.51,.30),(0,.51,1.02),1.65,.16)
        h.cassette([(-.13,-.77,.64),(.13,-.77,.64),(.13,-.94,.24),(-.13,-.94,.24)],'service',.022,section=(.04,.47))
    for i in range(len(rim)):h.beam(rim[i],rim[(i+1)%len(rim)],.026 if base=='cvltnk' else .036,'frame')
    for sign in (-1,1):
        h.beam((sign*width,lip,front),(sign*width*1.08,lip,back),.038,'armor')
        h.beam((sign*width*.63,roof,front*.30),(sign*width*1.08,roof,back),.030,'frame')
        h.beam((sign*width*1.08,lip,back),(sign*width*1.08,roof,back),.037,'armor')
        h.cassette([(sign*width*.96,-.76,back+.05),(sign*width*.88,-.76,.45),(sign*width*.66,-.91,.45),(sign*width*.66,-.91,back+.05)],'armor',.012)
        for z in (-.18,-.02,.14,.30):h.beam((sign*.14,-.94,z),(sign*width*.61,-.94,z),.014,'frame')
    topology=h.enclosure(cfg)
    for x in (-width*.70,0,width*.70):h.beam((x,-.86,back+.018),(x,roof-.04,back+.018),.020,'frame')
    h.cassette([(-.14,-.22,back+.035),(.14,-.22,back+.035),(.14,-.47,back+.035),(-.14,-.47,back+.035)],'armor',.012)
    parts={cfg['material']:h.part()};cabin_count=len(parts[cfg['material']][1])//3
    fs,fw,fe,fsh,fb,fp,_=native_rig(fullrig,cfg['shell'],native);source_names={b.handle:b.name for b in fs.bones()};targets={b.name:b.handle for b in s.bones()}
    body=shared.read_mesh(source).submesh_list[0];p=shared.values(body.vertex_data,shared.om.VES.POSITION);ix=body.index_array.reshape(-1,3);weights={a.vertex_index:a.bone_index for a in body.bone_assignments()};q=p[ix];valid=np.linalg.norm(np.cross(q[:,1]-q[:,0],q[:,2]-q[:,0]),axis=1)>1e-9
    rows=[];backs=[];drivers=[];back_drivers=[];audit=[];fixtures={}
    for name,bone,seed,planes in configs(base,origin,R):
        eligible=valid&np.array([all(weights.get(int(v))==bone for v in f) for f in ix]);mask=hw.source_island(p,ix,eligible,p[ix[seed]][0]);raw,indices,_=tank.source_part(body,mask);fixtures[name+'Data']=raw.copy();fixtures[name+'Indices']=indices.copy();fixtures[name+'SourceIds']=np.flatnonzero(mask);source_pose=fp[bone]@np.linalg.inv(fb[bone]);raw=transform(raw,source_pose)
        cap_chart=charts['trim' if name=='overheadCannon' else 'frame'];a,b,record=sections.section(raw,indices,np.flatnonzero(mask),planes,cap_chart);driver=shell.handle if base=='cvltnk' else targets[source_names[bone]]
        cap,collapsed,uv_slivers=stable_caps(b[0],cap_chart);rows.append(a[0]);backs.append(cap);drivers.extend([driver]*len(a[0]));back_drivers.extend([driver]*len(cap));audit.append(dict(name=name,sourceBone=bone,driver=driver,islandSeedFace=seed,sourcePose=source_pose.tolist(),capChart=cap_chart,collapsedCapTriangles=collapsed,remappedCapUVSlivers=uv_slivers,**record))
    exterior=np.concatenate(rows);capdata=np.concatenate(backs);parts['CRV/'+base+'HeadHull']=(exterior,np.arange(len(exterior),dtype='<u2'));parts['CRV/'+base+'SectionBacks']=(capdata,np.arange(len(capdata),dtype='<u2'))
    meta=dict(pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,layout={k:cfg[k] for k in ('width','lip','front','roof','back','role')},panels=h.panels,innerShell=topology,cabinTriangles=cabin_count,sections=audit,exteriorHandles=drivers,capHandles=back_drivers,nativeBoneRotations=rot,glassPolicy='cabin-only',fitPolicy='source native-rest positions; inverse target bind compensation only',sourceFixtures=fixtures)
    return parts,s,w,eye,shell,bind,posed,meta


def compile_mesh(parts,s,w,eye,shell,bind,posed,meta,base):
    cfg=CONFIG[base];interior={cfg['material']:parts[cfg['material']]};raw,glass=shared.mesh_bytes(interior,s,w,eye,shell,skeleton_name=cfg['resource']+'.skeleton');mesh=shared.oms.MeshSerializer(io.BytesIO(raw)).read()
    for material,key in [('CRV/'+base+'HeadHull','exteriorHandles'),('CRV/'+base+'SectionBacks','capHandles')]:
        d,ix=parts[material];raw=model_bytes(mesh,d,ix,np.array(meta[key]),material);mesh=shared.oms.MeshSerializer(io.BytesIO(raw)).read()
    # Authored and glass vertices are in native rest. Encode original bind
    # coordinates per driver so native GEO rotations do not tilt them twice.
    for sub in mesh.submesh_list:
        vd=sub.vertex_data;d=np.column_stack([shared.values(vd,sem) for sem in (shared.om.VES.POSITION,shared.om.VES.NORMAL,shared.om.VES.TEXTURE_COORDINATES,shared.om.VES.TANGENT)]);handles=np.array([a.bone_index for a in sub.bone_assignments()]);original=d.copy()
        for handle in set(handles):
            ids=handles==handle;T=bind[handle]@np.linalg.inv(posed[handle]);d[ids]=transform(original[ids],T)
        ogrelayout.set_rows(vd,d)
    points=np.concatenate([shared.values(sub.vertex_data,shared.om.VES.POSITION) for sub in mesh.submesh_list]);lo=points.min(0);hi=points.max(0);mesh.aabb=shared.om.AxisAlignedBoundingBox(*lo,*hi);mesh.bound_radius=float(np.linalg.norm(points,axis=1).max());out=io.BytesIO();shared.oms.MeshSerializer(out).write(mesh)
    return out.getvalue(),glass
