"""Build world/cockpit gun helpers, closed cuts, EXU clips and outward ports."""
from pathlib import Path
import argparse, copy, dataclasses, hashlib, json, re, subprocess, sys
import numpy as np
import weaponrigs as wr
import cockpitglass as cg
import eyeoverrides
import hardpointbones as hpbones
import ogrelayout
from bzmodellibs import legacy

ROOT=wr.ROOT;REF=ROOT/'References/WeaponRigs';CONFIG=REF/'models.json'

def baseline(path,revision):
    if path.is_relative_to(ROOT):
        key=path.relative_to(ROOT).as_posix();revision=wr.stage_revision(key,revision)
        proc=subprocess.run(['git','show',revision+':'+key],capture_output=True)
        if proc.returncode==0:return proc.stdout
    return path.read_bytes()

def native_points(model,src):
    path=ROOT/'Assets/ModelFixes'/(model+'.vdf')
    if not path.exists():path=wr.GAME/'StockODFFiles'/(model+'.vdf')
    m=legacy.read_vdf(path);parts={p.name:p for p in m.band(0)};world={}
    def matrix(name):
        if name in world:return world[name]
        p=parts[name];a=np.eye(4);a[:3,:3]=np.asarray(p.matrix[:9]).reshape(3,3).T;a[:3,3]=p.matrix[9:12]
        w=matrix(p.parent)@a if p.parent in parts and p.parent!=name else a;world[name]=w;return w
    mirror=np.diag([-1,1,1,1])
    return {p.name:(mirror@matrix(p.name)@mirror) for p in parts.values()}

def repair_hierarchy(model,skel):
    if model=='svturr':
        for source,alias in [('STU11BGCA','STU11BGA'),('STU11BGCB','STU11BGB')]:
            child=skel.bone(source)
            if child is None or skel.bone(alias):continue
            helper=wr.Bone(alias,max(b.handle for b in skel.bones)+1,child.position,child.orientation,child.scale,child.parent)
            skel.bones.append(helper);child.parent=helper.handle;child.position=(0,0,0);child.orientation=(0,0,0,1);child.scale=None
    if model=='cblasr':
        from scipy.spatial.transform import Rotation
        source=legacy.read_vdf(wr.GAME/'StockODFFiles/cblasr.vdf');mirror=np.diag([-1.,1.,1.])
        for part in source.band(0):
            if skel.bone(part.name):continue
            parent=skel.bone(part.parent)
            if parent is None:continue
            rotation=mirror@np.asarray(part.matrix[:9]).reshape(3,3).T@mirror
            position=tuple(mirror@np.asarray(part.matrix[9:12]))
            skel.bones.append(wr.Bone(part.name,max(b.handle for b in skel.bones)+1,position,tuple(Rotation.from_matrix(rotation).as_quat()),parent=parent.handle))

def hardpoint_bones(model,mesh,skel):
    """Hang each References/Hardpoints receipt part's bone from its owner at the receipt pose
    (Tools/hardpointbones.py). A moved bone must be unanimated; vertices skinned to it (cvturr's
    stock hardpoint markers) move to its old parent, which carries them identically."""
    r=hpbones.receipt(model)
    if r is None:return {}
    def old(name):
        b=skel.bone(name);return None if b is None else tuple(b.orientation)
    done={}
    for name,owner,pos,quat,new in hpbones.poses(r,old,wr.GAME):
        o=skel.bone(owner);assert o is not None,(model,name,'no owner bone',owner)
        if new:
            skel.bones.append(wr.Bone(name,max(b.handle for b in skel.bones)+1,pos,quat,parent=o.handle))
        else:
            b=skel.bone(name);assert not any(t.bone==b.handle for a in skel.animations for t in a.tracks),(model,name,'animated')
            for sub in [mesh,*mesh.submeshes]:
                if sub.bone_assignments:sub.bone_assignments=[(i,b.parent if j==b.handle else j,w) for i,j,w in sub.bone_assignments]
            b.parent,b.position,b.orientation=o.handle,pos,quat
        done[name]={'parent':owner,'position':list(pos),'orientation':list(quat)}
    return done

def load(path,src,revision):
    raw=baseline(path,revision);mesh=wr.ogre.read_mesh(raw)
    sp=Path(src.model(mesh.skeleton)[0]);sraw=baseline(sp,revision)
    skel=wr.read_skeleton(eyeoverrides.patch_skeleton(sp.stem.split('_')[0],sraw))
    evidence={'mesh':hashlib.sha256(raw).hexdigest(),'skeleton':hashlib.sha256(sraw).hexdigest(),
        'bind_poses':{b.name:wr.flash.bone_world(skel,b.handle) for b in skel.bones},
        'animations':{a.name:hashlib.sha256(json.dumps(dataclasses.asdict(a),sort_keys=True).encode()).hexdigest() for a in skel.animations}}
    return mesh,skel,evidence

def cockpit_overrides(model,channels,src,revision):
    cp,_,_=cg.cockpit_mesh(src,model)
    if not cp:return
    mesh,skel,_=load(Path(cp),src,revision)
    if model in ('svtank','cvtnk'):
        material='CRV/'+model+'TankGuns'
        sub=next(s for s in mesh.submeshes if s.material==material)
        points=np.asarray(sub.geometry.attribute(1));lo=points.min(0)-.001;hi=points.max(0)+.001
        for i,ch in enumerate(channels):
            ch['cockpit_materials']=[material] if i==0 else []
            if i==0:
                ch['cockpit_lo']=lo.tolist();ch['cockpit_hi']=hi.tolist();ch['cockpit_pivot']=points.mean(0).tolist()
    if model=='svfigh':
        data=json.loads((ROOT/'References/CombatCockpits/svfigh/build.json').read_text())
        T=np.asarray(data['alignment']['exteriorPieces'][0]['transform'])
        for ch in channels:
            corners=np.asarray([[x,y,z] for x in (ch['lo'][0],ch['hi'][0]) for y in (ch['lo'][1],ch['hi'][1]) for z in (ch['lo'][2],ch['hi'][2])])
            points=corners@T[:3,:3].T+T[:3,3]
            ch['cockpit_lo']=points.min(0).tolist();ch['cockpit_hi']=points.max(0).tolist()
            ch['cockpit_pivot']=(T[:3,:3]@ch['pivot']+T[:3,3]).tolist();ch['cockpit_axis']=(T[:3,:3]@np.array([0,0,1])).tolist()
    if model=='svartl':
        for ch in channels:ch['allow_stock_cockpit']=True

def fit_effects(model,mesh,skel,channels,proof,ports_only=()):
    names={b.handle:b.name for b in skel.bones};triangles=[];byhelper={}
    def world_bone(handle):
        b=skel.bones[handle]
        while b is not None:
            if len(b.name)>3 and b.name[3]=='2':return False
            b=skel.bones[b.parent] if b.parent is not None else None
        return True
    for sub in mesh.submeshes:
        g=mesh.shared_geometry if sub.uses_shared_vertices else sub.geometry
        p=np.asarray(g.attribute(1));assign=mesh.bone_assignments if sub.uses_shared_vertices else sub.bone_assignments
        own={i:b for i,b,w in assign if w>.99}
        for i,b in own.items():byhelper.setdefault(names[b],[]).append(p[i])
        for f in sub.triangles():
            if all(i in own and world_bone(own[i]) for i in f):triangles.append(p[list(f)])
    tri=np.asarray(triangles);e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0]
    def last_hit(origin,direction):
        h=np.cross(np.broadcast_to(direction,e2.shape),e2);det=np.einsum('ij,ij->i',e1,h);mask=abs(det)>1e-9
        inv=np.zeros(len(det));inv[mask]=1/det[mask];s=origin-tri[:,0];u=np.einsum('ij,ij->i',s,h)*inv
        q=np.cross(s,e1);v=q@direction*inv;t=np.einsum('ij,ij->i',e2,q)*inv
        hit=mask&(u>=-1e-7)&(v>=-1e-7)&(u+v<=1+1e-7)&(t>0)
        return float(t[hit].max()) if hit.any() else 0.
    result={}
    native_path=ROOT/'Assets/ModelFixes'/(model+'.vdf')
    if not native_path.exists():native_path=wr.GAME/'StockODFFiles'/(model+'.vdf')
    native=legacy.read_vdf(native_path)
    work=list(zip(channels,proof))
    for hard in ports_only:
        hp=next(b for b in skel.bones if b.name.upper().endswith(hard) and (len(b.name)<4 or b.name[3]!='2'))
        work.append((dict(hardpoints=[hard],pivot=wr.flash.bone_world(skel,hp.handle)[0],port_only=True),None))
    for ch,record in work:
        if record:
            p=np.asarray([v for h in record['helpers'] for v in byhelper[h['bone']]])
            tip=p[:,2].max();front=p[p[:,2]>tip-.04];point=np.r_[(front[:,:2].min(0)+front[:,:2].max(0))/2,tip]
        else:point=np.asarray(ch['pivot'])
        side=1 if point[0]>=0 else -1
        direction=np.asarray([side,.35,-.15]);direction/=np.linalg.norm(direction)
        breech=np.asarray(ch['pivot'])+np.asarray([0,.02,-.2]);travel=last_hit(breech,direction)
        port=breech+direction*(travel+.26)
        cone=[direction+np.asarray([x,y,z])*.2 for x in (-1,1) for y in (-1,1) for z in (-1,1)]
        for attempt in range(50):
            clearance=wr.surface_clearance(port,tri)
            if clearance>=.25 and all(last_hit(port,d)<1e-5 for d in cone):break
            port+=direction*.10
        else:raise AssertionError((model,'cannot fit a hull-clear outward ejection port'))
        assert last_hit(port,direction)<1e-5,(model,'ejection ray still enters the hull')
        for hard in ch['hardpoints']:
            hp=next((b for b in skel.bones if b.name.upper().endswith(hard) and (len(b.name)<4 or b.name[3]!='2')),None)
            n=next(x for x in native.band(0) if x.name.upper().endswith(hard))
            if hp is not None:
                hp_pos=np.asarray(wr.flash.bone_world(skel,hp.handle)[0]);parent=skel.bones[hp.parent]
            else:
                parent=skel.bone(n.parent) or skel.bone(ch['parent']);pos,rot=wr.flash.bone_world(skel,parent.handle)
                hp_pos=np.asarray(pos)+np.asarray(wr.flash._rotate(rot,np.asarray(n.matrix[9:12])*[-1,1,1]))
            _,rot=wr.flash.bone_world(skel,parent.handle)
            local=lambda x:[round(float(v),4) for v in wr.flash._rotate(wr.flash._conj(rot),x)]
            result[hard]={'animation':ch.get('clip',''),'node':'','spin':ch.get('spin',False),'distance':ch.get('distance',0),'return':2.0,
                'kick_without_weapon':.25 if model in ('avfigh','bvraz','svfigh','cvfigh') else 1.,
                'flash_offset':local(point-hp_pos),'casing_offset':local(port-hp_pos),'casing_direction':local(direction),
                'casing_outward_side':side,'casing_clearance':round(clearance,4),'casing_jitter_rays_clear':True,
                'port_world':port.tolist(),'direction_world':direction.tolist(),'tip_world':point.tolist(),'cockpit':True}
            if ch.get('port_only'):
                result[hard]['presentation_only']=True
                del result[hard]['flash_offset'] # No visible barrel: retain the separately measured emitter fit.
    return result

def make_config():
    assert not CONFIG.exists(), 'Authoring configuration already exists; edit its reviewed regions instead of repinning generated assets'
    src=cg.Sources(str(wr.GAME),str(ROOT));models={}
    targets='avfigh avltnk avrckt avtest avwalk bvltnk bvraz bvrckt bvrdev bvwalk cblasr cvartl cvfigh cvhraz cvhtnk cvltnk cvrckt cvtnk cvturr svartl svfigh svhraz svltnk svrckt svtank svturr svwalk'.split()
    revision=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
    for model in targets:
        mp=Path(src.model(model+'.mesh')[0]);mesh,skel,_=load(mp,src,revision)
        bones={b.name:b for b in skel.bones};native=native_points(model,src)
        hard={b.name[-3:].upper():b for b in skel.bones if len(b.name)>3 and b.name[3]!='2' and re.search(r'(GC[1-4]|GR[1-3]|GM[1-4])$',b.name,re.I)}
        points=[]
        for sub in mesh.submeshes:
            g=mesh.shared_geometry if sub.uses_shared_vertices else sub.geometry
            points.extend(g.attribute(1))
        p=np.asarray(points)
        keys=['GC1','GC2']
        if model in ('avrckt','bvrckt','svrckt','cvhraz','cvrckt','svhraz'):keys=['GR1','GR2']
        if model in ('avltnk','bvltnk'):keys=['GC1','GR1']
        if model=='bvrdev':keys=['GC1','GR1']
        if model in ('cvltnk','svltnk','cblasr'):keys=['GC1']
        if model=='cvartl':keys=['GM1','GM2','GM3','GM4']
        if model=='svartl':keys=['GM1']
        if model=='cvturr':keys=['GC1','GC2','GC3','GC4']
        channels=[]
        for i,key in enumerate(keys):
            hp=hard.get(key);nat=next((v for n,v in native.items() if n.upper().endswith(key)),None)
            if hp:
                anchor=np.asarray(wr.flash.bone_world(skel,hp.handle)[0]);parent=bones.get(skel.bones[hp.parent].name)
            else:
                assert nat is not None,(model,key,'hardpoint missing')
                anchor=nat[:3,3];parent=next((b for b in skel.bones if b.name.lower().endswith('bdb')),skel.bones[0])
            radius=.20;depth=.55;distance=.06
            if model in ('avfigh','bvraz','svfigh'):radius=.15;depth=.4;distance=.025
            if model=='cvfigh':radius=.24;depth=.65;distance=0
            if model in ('avltnk','bvltnk'):radius=.145 if key=='GC1' else .27;depth=.7 if key=='GC1' else .4
            if model in ('avwalk','bvwalk'):radius=.6;depth=1.0;distance=.18
            if model in ('svwalk','cvwalk'):radius=.30;depth=.65;distance=.12
            if model in ('cvartl','svartl'):radius=.24;depth=.85;distance=.18
            if model=='cvturr':radius=.14;depth=.5;distance=.06
            if model in ('cvhraz','svhraz','cvrckt','avrckt','bvrckt','svrckt'):radius=.30;depth=.45;distance=.05
            if model=='cvhtnk':radius=.27;depth=1.05;distance=.14
            if model=='cblasr':radius=.4;depth=.5;distance=.07
            if model=='svtank' and key=='GC1':radius=.35;depth=1.1;distance=.2
            if model=='svtank' and key=='GC2':radius=.16;depth=.5;distance=.03
            if model=='svltnk':radius=.28;depth=.55;distance=.07
            eligible=[parent.name]
            if model in ('avltnk','bvltnk'):
                prefix='aln' if model=='avltnk' else 'bln'
                eligible=[prefix+'11bdc' if key=='GC1' else prefix+'11bdb']
                parent=bones[eligible[0]]
            if model=='cvhtnk':
                eligible=['CEM11WGL0' if key=='GC1' else 'CEM11WGR1'];parent=bones[eligible[0]]
            if model=='cblasr':eligible=['clz11bdb']
            if model=='bvrdev' and key=='GR1':eligible=['brd11tur'];parent=bones[eligible[0]]
            if model=='cvhraz':eligible=['CPX11NRl' if key=='GR1' else 'CPX11NRR'];parent=bones[eligible[0]]
            if model=='svturr':
                parent=bones['STU11BGC' if key=='GC1' else 'STU11BGCB'];eligible=[parent.name]
                owned=[]
                for sub in mesh.submeshes:
                    owned.extend(wr.flash.barrel_vertices(mesh,parent.handle));break
                bnd=np.asarray(owned);anchor=bnd.max(0);anchor[:2]=(bnd.min(0)[:2]+bnd.max(0)[:2])/2
                radius=.24;depth=.7
            eligible_vertices=[]
            for b in skel.bones:
                if b.name in eligible:eligible_vertices.extend(wr.flash.barrel_vertices(mesh,b.handle))
            q=np.asarray(eligible_vertices)
            near=[]
            ids={b.handle for b in skel.bones if b.name in eligible}
            for sub in mesh.submeshes:
                g=mesh.shared_geometry if sub.uses_shared_vertices else sub.geometry
                verts=np.asarray(g.attribute(1));weights=mesh.bone_assignments if sub.uses_shared_vertices else sub.bone_assignments
                owners={v:b for v,b,w in weights if w>.99}
                for tri in sub.triangles():
                    if not all(owners.get(v) in ids for v in tri):continue
                    t=verts[list(tri)]
                    a,b=wr.partition([t],anchor-[radius,radius,.2],anchor+[radius,radius,3.6]);near.extend(a)
            tip=max(v[2] for face in near for v in face) if len(near) else anchor[2]
            lo=(anchor-[radius,radius,0]);hi=(anchor+[radius,radius,0]);lo[2]=tip-depth;hi[2]=tip+.02
            if model=='avtest':
                lo=q.min(0)-.001;hi=q.max(0)+.001;distance=.06
            aliases=[key]
            if model in ('avtest',):aliases.append('GM'+key[-1])
            if model in ('cvltnk','svltnk'):aliases.append('GR1')
            if model=='bvrdev' and key=='GR1':aliases.append('GM1')
            channels.append({'hardpoints':aliases,'parent':parent.name,'bones':eligible,'pivot':anchor.tolist(),
                             'lo':lo.tolist(),'hi':hi.tolist(),'distance':distance,'duration':.18 if distance>.1 else .12,
                             'spin':model=='cvfigh','clip':'cr_fire_'+str(i+1)})
            if model=='cblasr':channels[-1]['motion_parent']='clz11bdd'
        cockpit_overrides(model,channels,src,revision)
        models[model]={'channels':channels}
    REF.mkdir(parents=True,exist_ok=True)
    stages=json.loads(CONFIG.read_text()).get('stage_revisions',{}) if CONFIG.exists() else {}
    CONFIG.write_text(json.dumps({'source_revision':revision,**({'stage_revisions':stages} if stages else {}),'models':models,'excluded':'svsav; svmine has only utility deployment, no firearm barrel'},indent=2)+'\n')

def build(selected):
    cfg=json.loads(CONFIG.read_text());src=cg.Sources(str(wr.GAME),str(ROOT))
    receipt_path=REF/'build.json';receipts=json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
    for model,entry in cfg['models'].items():
        if selected and model not in selected:continue
        mp=Path(src.model(model+'.mesh')[0]);mesh,skel,source=load(mp,src,cfg['source_revision'])
        repair_hierarchy(model,skel);hardpoints=hardpoint_bones(model,mesh,skel)
        channels=copy.deepcopy(entry['channels']);proof=wr.channels_mesh(mesh,skel,channels)
        assert all(p['triangles'] for p in proof),(model,'empty world gun selection',proof)
        sp=ROOT/'Assets/Models'/(model+'_recoil.skeleton');target=ROOT/'Assets/ModelFixes'/(model+'.mesh')
        outputs={};mesh.skeleton=sp.name;target.write_bytes(ogrelayout.convert(wr.ogre.write_mesh(mesh))[0]);sp.write_bytes(wr.write_skeleton(skel))
        for path in (sp,target):outputs[path.relative_to(ROOT).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
        cp,kind,_=cg.cockpit_mesh(src,model);cp_proof=[];cp_hardpoints={}
        if cp and Path(cp)!=mp:
            cpm,cps,csource=load(Path(cp),src,cfg['source_revision']);cpchannels=copy.deepcopy(entry['channels'])
            # Opt-in per model (models.json "cockpit_hardpoints": true): moved
            # hardpoints take the same receipt poses in the cockpit skeleton so
            # first-person muzzles match the world rig. Only valid where the
            # cockpit skeleton's owner bones match the exterior's world pose;
            # other cockpits (e.g. svturr_c) lack the owner bones entirely.
            if entry.get('cockpit_hardpoints'):cp_hardpoints=hardpoint_bones(model,cpm,cps)
            cp_proof=wr.channels_mesh(cpm,cps,cpchannels,True)
            cpsp=ROOT/'Assets/Models'/(model+'_cockpit_recoil.skeleton')
            cpp=Path(cp) if Path(cp).is_relative_to(ROOT) else ROOT/'Assets/Models'/Path(cp).name
            cpm.skeleton=cpsp.name;cpp.write_bytes(ogrelayout.convert(wr.ogre.write_mesh(cpm))[0]);cpsp.write_bytes(wr.write_skeleton(cps))
            for path in (cpp,cpsp):outputs[path.relative_to(ROOT).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
        fit=fit_effects(model,mesh,skel,channels,proof,entry.get('ports_only',()))
        receipts[model]={'source':source,'world':proof,'cockpit':cp_proof,'cockpit_source':csource if cp_proof else None,
                         'cockpit_kind':kind,'bindings':fit,'outputs':outputs,**({'hardpoints':hardpoints} if hardpoints else {}),**({'cockpit_hardpoints':cp_hardpoints} if cp_hardpoints else {})}
        receipt_path.write_text(json.dumps(receipts,indent=2)+'\n')
        print(model,[(p['triangles'],p['cap_triangles']) for p in proof],'cockpit',[(p['triangles'],p['cap_triangles']) for p in cp_proof],flush=True)
    (REF/'build.json').write_text(json.dumps(receipts,indent=2)+'\n')

def sync_policy():
    cfg=json.loads(CONFIG.read_text());receipts=json.loads((REF/'build.json').read_text())
    target=ROOT/'References/WeaponPresentation/combat-models.json';policy=json.loads(target.read_text())
    for model in cfg['models']:
        record=receipts[model];assert record.get('bindings'),(model,'build its final rig first')
        policy['models'][model]['bindings']=record['bindings']
        policy['models'][model]['category']='Authored closed gun rigs'
        visible=sum(bool(p['triangles']) for p in record['cockpit'])
        policy['models'][model]['action']=f"Closed gun sections and EXU world/cockpit clips authored; {visible} channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending."
    policy['casing_port_status']='Per-slot fitted offsets/directions authored for the weapon-rig models; companion OpenShim runtime required.'
    target.write_text(json.dumps(policy,indent=2)+'\n')


def report():
    cfg=json.loads(CONFIG.read_text());records=json.loads((REF/'build.json').read_text())
    review=REF/'review';review.mkdir(exist_ok=True)
    gallery=[]
    for model in cfg['models']:
        images=''.join(f'<a href="{model}-{k}.jpg"><img src="{model}-{k}.jpg" alt="{model} {k}"></a>' for k in ('rest','firing','rear','cockpit','cockpit-down') if (review/f'{model}-{k}.jpg').exists())
        gallery.append(f'<section><h2>{model}</h2>{images}</section>')
    (review/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>CR weapon rigs: offline review</title><style>body{font:16px system-ui;background:#1b1e23;color:#eee;max-width:1500px;margin:32px auto}img{width:32%;margin:.5%}h2{margin-top:40px}a{color:#78c9ff}</style><h1>CR weapon rigs: exported asset review</h1><p>Offline Blender diagnostics. Grey hardware stays fixed; cyan, blue, orange and purple identify independent firing channels. World views: rest, fired, rear/underside. Cockpit: actual eye/native VDF basis, 64 degree vertical FOV, then 25 degrees down. Materials are diagnostic, with backface culling. These are not native gameplay captures.</p>'+''.join(gallery),encoding='utf-8')
    descriptions={
        'avfigh':'Paired visible side-rail gun tips; fixed nose armor, hull and mounts.',
        'avltnk':'Small upper gun plus launcher bell; retain the separate aiming drivers.',
        'avrckt':'Paired forward launcher outlet sections; fixed launcher housings.',
        'avtest':'Two existing gun assemblies receive separate helper clips.',
        'avwalk':'Left and right forward gun sections; retain arm and aiming motion.',
        'bvltnk':'Small upper gun plus launcher bell, using the Black Dog source geometry.',
        'bvraz':'Paired visible side-rail gun tips; mirrored outward casing paths.',
        'bvrckt':'Paired launcher outlet sections; cockpit cabin stays fixed.',
        'bvrdev':'Forward gun tip and secondary launcher outlet; preserve the existing atlas.',
        'bvwalk':'Independent left/right gun sections beneath their original arm drivers.',
        'cblasr':'Emitter tip split from tower; restore missing native aiming hierarchy in the rendered rig.',
        'cvartl':'Four forward tube sections with separate clips; existing single equipped hardpoint selects its own channel.',
        'cvfigh':'Spin the full exposed minigun barrel clusters and retaining rings about each bore; rear receivers, mounts and wings stay fixed.',
        'cvhraz':'Paired forward launcher aperture sections; launcher bodies stay fixed.',
        'cvhtnk':'Independent paired cannon sections; corresponding cockpit gun copies use the same clip names.',
        'cvltnk':'Forward cannon section, shared by cannon/launcher hardpoint aliases.',
        'cvrckt':'Paired forward launcher sections and the visible cockpit copies.',
        'cvtnk':'Primary cannon and secondary gun tip; the art-fitted cockpit primary gun has its own matching helper.',
        'cvturr':'Four separate barrels, four clips, four equipped slots; all four cockpit copies are rigged.',
        'svartl':'The equipped GM1 tube recoils independently; the other visible tubes remain fixed.',
        'svfigh':'Paired forward gun aperture sections; apply the recorded cockpit fitting transform to the copied gun regions.',
        'svhraz':'Two large round forward apertures, selected by disconnected source component before cutting; fixed housing.',
        'svltnk':'Forward cannon section with the cannon/launcher alias bound to the same clip.',
        'svrckt':'Paired forward launcher outlet sections; cockpit cabin stays fixed.',
        'svtank':'Primary cannon and secondary tip; preserve the art-fitted cockpit primary gun and source UVs.',
        'svturr':'Three gun sections (GC1-GC3); restore native alias parents while preserving existing world bind poses.',
        'svwalk':'Paired groups of small forward head-aperture sections; retain the original head driver.'}
    lines=['# Requested CR weapon model edits', '',
        'Authored source and exported assets, 2026-11-04. **27 model families; not deployed or qualified in native gameplay.**', '',
        '[Exported model gallery](../References/WeaponRigs/review/index.html) · [Full ODF/slot coverage](COMBAT_WEAPON_EFFECTS.md) · [Companion native PR 698](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/pull/698)', '',
        '## Implemented model edits', '',
        'Gun regions retain source surfaces, materials and UVs. New moving boundaries are capped, with reverse caps closing the fixed receiver cuts. Helpers remain children of each original geometry driver, preserving aiming, arm, deployment and visibility relationships. Only helpers receive new tracks; existing bind poses and animation tracks are retained.', '',
        '| Model | Model edit | Rigged cockpit channels |', '|---|---|---|']
    for model in cfg['models']:
        r=records[model];visible=sum(bool(p['triangles']) for p in r['cockpit'])
        cp=str(visible)+' / '+str(len(r['cockpit'])) if r['cockpit'] else 'In-mesh cabin / no separate gun copy'
        if model=='avtest':cp='No cockpit gun copy'
        if model=='cblasr':cp='Building; no cockpit gun copy'
        lines.append(f'| `{model}` | {descriptions[model]} | {cp} |')
    lines += ['', 'A zero cockpit count means that resource contains no selected gun surface; the cabin, nose or frame is not moved just to create recoil. In-mesh rocket/artillery cockpits contain cabin/glass surfaces rather than duplicate guns. Guns outside the forward cockpit FOV still receive tracks when they are present in the resource.', '',
        '`svsav` is excluded. `svmine` deploys utility ordnance and has no firearm barrel to split. ODF aliases sharing these models receive their actual equipped-hardpoint bindings without changing their loadouts.', '',
        '## Remaining mesh additions proposed', '',
        'The following secondary mounts have no independently selected visible barrel in this pass. They are not counted as working recoil. The full slot report also distinguishes utility weapons and unsupported native firing producers.', '',
        '| ODF / mount | Remaining model proposal |', '|---|---|',
        '| `avwamp` / GM1 Splinter | Add a closed short mortar insert at the top/head mount; retain native aiming and include it in the cockpit only if actually visible. |',
        '| `svfi12`, `svdemo` / GR1 centerline | Add a closed centerline emitter/barrel insert between the existing scout guns. The ballistic variant already has a fitted outward casing port; the existing side guns are not moved on its behalf. |',
        '| `svhrmp` / GC1 tagger | Add a small closed auxiliary emitter at the existing marker, separate from the two bomber nose apertures. |',
        '| `cvrckt` / GM1 MDM | Separate the lower launcher outlet from the upper rocket outlet, with closed receiver and moving caps. Native detonator producer support remains pending. |',
        '| `svrckt` / GM1 MDM | Add a closed mortar outlet at the raised centerline mount; do not recoil the whole launcher body. Native detonator producer support remains pending. |',
        '| Scout GR1 guided-rocket variants | A centerline launcher insert is needed where there is no visible tube; qualify the guided firing producer before calling this working recoil. |', '',
        'Mine, popper, flare, camera and field-device mounts have no firearm barrel to move. Their lack of a recoil binding is intentional. Their per-weapon effect/producer decisions remain in the slot report.', '',
        '## Flash and casing placement', '',
        'Flash offsets are fitted to the exported moving-piece fronts in the native hardpoint-parent frame. Ballistic slots receive fitted local casing offsets and directions. Each port is outside the full world hull with at least 0.25 m surface clearance; the outward ray and eight jitter-cone corner rays clear the hull in the authored rest pose. Paired scout ports point away from the centerline in opposite directions. Energy, rocket and utility weapons retain their no-brass decisions.', '',
        'All ballistic slots on the requested model families have fitted casing offsets/directions, including the centerline `svfi12` variant that has no visible recoil barrel. Offsets are a static geometry fit. Aiming, recoil, vehicle motion, casing collision and cockpit emission still require native acceptance. The new spin/port keys require OpenShim PR 698, which `Bin/openshim.dll` now includes.', '',
        '## Evidence and remaining work', '',
        '- `Test-WeaponRigs.py`: six final-asset contracts pass for requested coverage, exported hashes, finite geometry, rigid helper ownership, closed moving surfaces, original bind poses/clips, four-barrel/spin counterparts, port clearance and the reviewed actual gun regions.',
        '- Weapon/flash/casing and combat-presentation suites: fifteen tests pass; all 132 armed ODF gameplay baselines remain unchanged.',
        '- Original cockpit/art suites validate their pinned pre-rig stage through `weaponrigs.base_asset_path`; final runtime files are checked separately by `Test-WeaponRigs.py`. Twelve related art suites pass. The existing `Test-TankCockpits.py` fails on the unchanged `avtank_cockpit.mesh` receipt: current/base SHA-256 `29e82cd602926a10af03c4844bf91d5d697a8afb4d917283104dc91f8977ffc9`, receipt expects `9868c0b465eda741fd5d0061823c4e90e680201441ed98aae7ff00b319035205`.',
        '- Repository invariants pass. Shipping membership adds 49 helper skeletons, with no removals. Preview gallery covers all 27 exported world models and 22 separate cockpit resources, including fired rear/underside views with backface culling. Grey is fixed hardware; colors identify firing channels. These are diagnostic Blender renders, not textured native captures.',
        '- Companion OpenShim builds in Release, passes 172 host tests, and passes the exact executable static hook qualification. Neither that binary nor the content has been deployed or live tested.',
        '- Shared-codec gap: the original `bvwalk.mesh` has a precomputed Ogre edge-list chunk. The shared writer omits it after topology changes, avoiding stale indices. Before accepting native shadows, rebuild that derived data with supported Ogre tooling or establish that the native renderer regenerates it. The other edited source meshes have no omitted top-level derived chunks.',
        '- Native acceptance must check firing/recovery and sustained spin; all four turret barrels; turret pitch/deploy and arm motion; cockpit copies; flash at rest/kick; outboard brass under vehicle motion; repeated/simultaneous shots, swaps and reloads. Other firing producer gaps remain listed in the full slot report.',
        '- The broader CR report still lists model families outside this requested edit set. `avartla` references the missing weapon `gpopguna`; no gameplay substitution was made.', '',
        '## Rebuild', '',
        'The immutable source revision is recorded in `References/WeaponRigs/models.json`. Builders read pre-rig tracked inputs from that Git revision; keep repository history available. Stock fallbacks require the local retail assets. Region bounds and cockpit fitting overrides are authoring data, not runtime heuristics.', '',
        '```powershell', 'python Tools/Build-WeaponRigs.py', 'python Tools/Build-WeaponRigs.py --sync', 'python Tools/Build-WeaponFlashes.py --measure', 'python Tools/Build-CombatPresentation.py', 'python Tools/Test-WeaponRigs.py', '```', '',
        '`--init` is one-time configuration creation and refuses to overwrite reviewed regions. For previews, run `Tools/Render-WeaponRigs.py` through background Blender. The renderer preserves eye position and uses the native VDF local POV basis, a 64 degree vertical FOV and 16:9 aspect; the down view pitches 25 degrees from that basis.', '']
    (ROOT/'Docs/WEAPON_RIGS.md').write_text('\n'.join(lines),encoding='utf-8',newline='\n')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--init',action='store_true');p.add_argument('--sync',action='store_true');p.add_argument('--report',action='store_true');p.add_argument('--models',nargs='*');args=p.parse_args()
    if args.init:make_config()
    elif args.sync:sync_policy()
    elif args.report:report()
    else:build(args.models)
