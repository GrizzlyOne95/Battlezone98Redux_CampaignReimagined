"""Low CCA bomber and split-nose CRA rocket cockpits; shared art and codecs."""
import numpy as np
import reddevilcockpit as shared
import combatcockpits as hardware
import tankcockpits as tank
import cockpitsections

CONFIG={
 'svhraz':dict(faction='cca',shell='shb21bdb',material='CRV/CCAMechanicalCockpit',exterior='svhraz00',width=.62,lip=-.39,front=.96,roof=.32,back=-.55,role='lowbomber'),
 'cvrckt':dict(faction='cra',shell='CDR21BDA',material='CRV/CVBomberCockpit',exterior='cvrckt',width=.79,lip=-.46,front=1.22,roof=.46,back=-.62,role='rocket')}
SV_STRUCTURE='CRV/svhrazStructure'
# Quiet worn red allocations from THIS bomber's exterior atlas. No repaint or
# diffuse tint on the analog faces, and no new texture sheet.
SV_RED={'armor':(.33,.442,.49,.48),'frame':(.04,.366,.54,.402)}


class BomberHardware(hardware.Hardware):
    def __init__(self,*args):super().__init__(*args);self.structure=[]
    def cassette(self,p,chart='console',depth=.035,section=None):
        old=self.charts
        if chart in SV_RED:self.charts={**old,**SV_RED}
        super().cassette(p,chart,depth,section)
        self.charts=old
    def face(self,points,chart='trim',hint=None,uvs=None):
        first=len(self.ix);old=self.charts
        if chart in SV_RED:self.charts={**old,**SV_RED}
        super().face(points,chart,hint,uvs)
        if chart in SV_RED:self.structure.extend(range(first,len(self.ix)))
        self.charts=old
    def split(self):
        d,ix=self.part();mask=np.zeros(len(ix),bool);mask[self.structure]=True
        def part(indices):
            used,remap=np.unique(indices,return_inverse=True)
            return d[used],remap.astype('<u2')
        return part(ix[~mask]),part(ix[mask])


def stable_caps(data,chart):
    """Drop collapsed float32 faces; give UV-precision slivers valid UV axes."""
    tri=data.reshape(-1,3,11);area=np.linalg.norm(np.cross(tri[:,1,:3]-tri[:,0,:3],tri[:,2,:3]-tri[:,0,:3]),axis=1);keep=area>1e-10
    tri=tri[keep].copy();a=tri[:,1,6:8]-tri[:,0,6:8];b=tri[:,2,6:8]-tri[:,0,6:8];bad=np.abs(a[:,0]*b[:,1]-a[:,1]*b[:,0])<=1e-12;x0,y0,x1,y1=chart
    tri[bad,:,6:8]=[(x0,y0),(x1,y0),(x0,y1)]
    return tri.reshape(-1,11),int((~keep).sum()),int(bad.sum())


def cut_configs(base):
    # All planes are in unchanged source-model coordinates, not a gun art fit.
    if base=='svhraz':return [('pilotPodNose',2,[([0,0,1],1.52)])]
    return [('prong'+str(sign),0,[([0,0,1],.55),([sign,0,0],.95),([0,-1,0],-1.93)]) for sign in (-1,1)]


def geometry(source,skelpath,base,game,root):
    cfg=CONFIG[base];s,w,eye,shell=shared.rig(skelpath,cfg['shell']);native=tank.native_eye(w,eye,game,base,root);origin,R=w[eye.handle]
    charts=hardware.CCA_CHARTS if cfg['faction']=='cca' else hardware.CRA_CHARTS
    h=(BomberHardware if base=='svhraz' else hardware.Hardware)(origin,R,charts,hardware.ART_ASPECT[cfg['faction']])
    if base=='svhraz':
        # The offset low pilot pod calls for short armored glazing, not a tall
        # Thunderbolt canopy. Keep the mechanical CCA controls below the eye.
        rim=[(-.62,-.39,.96),(0,-.42,1.10),(.62,-.39,.96),(.65,.10,.68),(.39,.32,.29),(-.39,.32,.29),(-.65,.10,.68)]
        h.cassette([(-.47,-.42,.92),(.47,-.42,.92),(.42,-.65,.65),(-.42,-.65,.65)],'console',.027)
        for sign in (-1,1):
            h.cassette([(sign*.45,-.49,.61),(sign*.58,-.48,-.05),(sign*.54,-.73,-.20),(sign*.38,-.75,.43)],'switch' if sign<0 else 'service',.024)
        h.cassette([(-.13,-.73,.58),(.13,-.73,.58),(.13,-.89,.31),(-.13,-.89,.31)],'switch',.018,section=(.04,.50))
        # Low coaming supports the pilot-pod nose cue. Unlike weapons this
        # nonfunctional first-person hood may sit lower to preserve visibility.
        h.fairing((.42,-.47,.93),(.50,-.46,1.04),.32,.10)
    else:
        # Related to the stock twin red guard rails, but not the full tall hull
        # shoulders in the pilot's face. Split desks frame a low arming keel.
        rim=[(-.79,-.46,1.22),(0,-.50,1.39),(.79,-.46,1.22),(.90,.08,.82),(.50,.46,.37),(-.50,.46,.37),(-.90,.08,.82)]
        for sign in (-1,1):
            h.cassette([(sign*.16,-.48,1.18),(sign*.65,-.48,1.18),(sign*.60,-.72,.83),(sign*.16,-.72,.83)],'switch' if sign<0 else 'service',.032)
            h.cassette([(sign*.61,-.54,.78),(sign*.75,-.53,.02),(sign*.69,-.80,-.17),(sign*.52,-.83,.54)],'service' if sign<0 else 'switch',.027)
            # Broad closed roots under both original forward prongs, below the
            # sill and never nudging the launchers off their source positions.
            h.fairing((sign*.72,-.57,1.12),(sign*1.03,-.61,1.53),.30,.15)
        h.cassette([(-.15,-.75,.79),(.15,-.75,.79),(.15,-.94,.27),(-.15,-.94,.27)],'service',.025,section=(.03,.47))
    width=cfg['width'];front=cfg['front'];lip=cfg['lip'];roof=cfg['roof'];back=cfg['back']
    for i in range(len(rim)):h.beam(rim[i],rim[(i+1)%len(rim)],.034 if base=='svhraz' else .030,'frame')
    for sign in (-1,1):
        h.beam((sign*width,lip,front),(sign*width*1.08,lip,back),.047,'armor')
        h.beam((sign*width*.63,roof,front*.30),(sign*width*1.08,roof,back),.034,'frame')
        h.beam((sign*width*1.08,lip,back),(sign*width*1.08,roof,back),.043,'armor')
        # Worn knee plates, foot trays and small ribs replace empty black walls.
        h.cassette([(sign*width*.94,-.76,back+.06),(sign*width*.88,-.76,.55),(sign*width*.66,-.91,.55),(sign*width*.66,-.91,back+.06)],'armor',.012)
        for z in (-.22,-.06,.10,.26):h.beam((sign*.20,-.94,z),(sign*width*.62,-.94,z),.015,'frame')
    topology=h.enclosure(cfg)
    for x in (-width*.70,0,width*.70):h.beam((x,-.87,back+.015),(x,roof-.04,back+.015),.022,'frame')
    h.cassette([(-.18,-.19,back+.045),(.18,-.19,back+.045),(.18,-.51,back+.045),(-.18,-.51,back+.045)],'armor',.015)
    parts={cfg['material']:h.part()}
    if base=='svhraz':parts[cfg['material']],parts[SV_STRUCTURE]=h.split()
    cabin_counts={key:len(ix)//3 for key,(d,ix) in parts.items()};cap_material=SV_STRUCTURE if base=='svhraz' else cfg['material'];cap_chart=SV_RED['armor'] if base=='svhraz' else charts['armor']
    body=shared.read_mesh(source).submesh_list[0];p=shared.values(body.vertex_data,shared.om.VES.POSITION);tri=body.index_array.reshape(-1,3);weights={a.vertex_index:a.bone_index for a in body.bone_assignments()};valid=np.linalg.norm(np.cross(p[tri[:,1]]-p[tri[:,0]],p[tri[:,2]]-p[tri[:,0]]),axis=1)>1e-9
    rows=[];backs=[];sections=[]
    for name,bone,planes in cut_configs(base):
        mask=valid&np.array([all(weights.get(int(v))==bone for v in face) for face in tri]);raw,ix,_=tank.source_part(body,mask);a,b,audit=cockpitsections.section(raw,ix,np.flatnonzero(mask),planes,cap_chart);rows.append(a[0]);backs.append(b[0]);sections.append(dict(name=name,sourceBone=bone,driver=shell.handle,**audit))
    data=np.concatenate(rows);capdata,collapsed,uv_slivers=stable_caps(np.concatenate(backs),cap_chart);capdata=capdata[:,:8];fit=np.eye(4)
    if base=='svhraz':fit[1,3]=-.30
    data[:,:3]+=fit[:3,3];capdata[:,:3]+=fit[:3,3]
    interior,ix=parts[cap_material];parts[cap_material]=(np.concatenate([interior,capdata]),np.r_[ix,np.arange(len(capdata))+len(interior)].astype('<u2'));parts['CRV/'+base+'Exterior']=(data,np.arange(len(data),dtype='<u2'))
    meta=dict(pov=eye.name,povPosition=origin.tolist(),povBasis=R.tolist(),shell=shell.name,shellHandle=shell.handle,layout={k:cfg[k] for k in ('width','lip','front','roof','back','role')},panels=h.panels,innerShell=topology,sections=sections,cabinTriangleCounts=cabin_counts,capMaterial=cap_material,capChart=cap_chart,capTriangles=len(capdata)//3,collapsedCapTriangles=collapsed,remappedCapUVSlivers=uv_slivers,exteriorTransform=fit.tolist(),glassPolicy='cabin-only')
    return parts,s,w,eye,shell,meta,native


def compile_mesh(parts,s,w,eye,shell,meta,base):
    cabin={material:(parts[material][0],parts[material][1][:count*3]) for material,count in meta['cabinTriangleCounts'].items()}
    return shared.mesh_bytes(parts,s,w,eye,shell,skeleton_name=base+'_cockpit.skeleton',glass_parts=cabin)
