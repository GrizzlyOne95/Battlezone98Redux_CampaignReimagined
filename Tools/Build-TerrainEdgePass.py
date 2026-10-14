"""Reproducible terrain prototype from the reviewed October 2026 map notes.

Works in a feature worktree. Baselines come from an immutable CR revision;
unported heightmaps come from CR's retained unsmoothed-heightmap revision.
Stock companion data is read from the owner's game archive, never downloaded.
Outputs standard HG2/MAT/LGT/BZN files; no runtime script dependencies.
"""
from __future__ import annotations
import argparse,copy,hashlib,json,os,subprocess,sys
from pathlib import Path
import numpy as np
from scipy import ndimage as ndi
from scipy.spatial import cKDTree

REPO=Path(__file__).resolve().parents[1]
MAPS=['misn02b','misn06','misn07','misn08','misn09','misn10','misn12','misn13','misn14','misn15b','misn16','misns4','misns5','misns6']
BASE='20692052db9b0a234604cfcad25272d0300d5987'
# Keep the accepted co-op mission's pads while retaining the original terrain.
MISSION_REFS={'misn14':'773564a9b60c79aa464e6ad2474d455869440752'}
AMPLITUDE={'misn02b':28,'misn06':25,'misn07':35,'misn08':35,'misn09':32,'misn10':30,'misn12':28,'misn13':28,'misn14':32,'misn15b':28,'misn16':22,'misns5':7,'misns6':35}

def git_bytes(ref,name):
 r=subprocess.run(['git','-C',str(REPO),'show',ref+':'+name],capture_output=True)
 return r.stdout if r.returncode==0 else None
def digest(data):return hashlib.sha256(data).hexdigest()
def smoothstep(x):
 x=np.clip(x,0,1);return x*x*(3-2*x)
def field_value(fields,key,default=None):return fields[key].value if key in fields else default
def label(path):return field_value(path,'label',b'').decode('latin1')
def points(path):return np.array(path['points'].value,dtype=float)
def path_update(path,pts):
 path['points']=Field('vec2',[tuple(map(float,p)) for p in pts]);path['pointCount']=Field('long',len(pts))
def distance_polyline(x,z,pts):
 dist=np.full(x.shape,np.inf)
 if len(pts)==1:return np.hypot(x-pts[0,0],z-pts[0,1])
 for a,b in zip(pts[:-1],pts[1:]):
  ab=b-a;t=np.clip(((x-a[0])*ab[0]+(z-a[1])*ab[1])/max(float(ab@ab),1e-8),0,1)
  dist=np.minimum(dist,np.hypot(x-a[0]-t*ab[0],z-a[1]-t*ab[1]))
 return dist
def load_baseline(name,ext,args):
 ref=MISSION_REFS.get(name,args.base) if ext=='.bzn' else args.base
 data=git_bytes(ref,'Missions/'+name+ext);provenance=ref+':Missions/'+name+ext
 if data is None and ext=='.hg2':
  data=git_bytes(args.height_ref,'Missions/'+name+ext);provenance=args.height_ref+':Missions/'+name+ext
 if data is None:data=ARCHIVE.read(name+ext);provenance='bzone.zfs::'+name+ext
 p=CACHE/(name+ext);p.write_bytes(data)
 SOURCES[name+ext]=dict(source=provenance,sha256=digest(data));return p
def local_objects(b,origin):
 result=[]
 for o in b.objects:
  p=np.array(o.fields['pos'].value[0]);result.append((o,p[0]-origin[0],p[2]-origin[1]))
 return result
def protect_masks(b,origin,x,z,exclude_paths=()):
 hard=np.zeros(x.shape,bool);weight=np.ones(x.shape)
 for o,ox,oz in local_objects(b,origin):
  if o.class_label in ('scrap','scrapfield'):radius=24
  elif o.class_label in ('geyser','camerapod','person'):radius=40
  elif o.class_label in ('wingman','walker','hover','turrettank','howitzer'):radius=55
  else:radius=85
  dist=np.hypot(x-ox,z-oz);hard|=dist<=radius
  weight=np.minimum(weight,smoothstep((dist-radius)/55))
 for p in b.paths:
  name=label(p).lower()
  if not name or name in exclude_paths or any(s in name for s in ('edge','bound','border')):continue
  pts=points(p)-origin
  radius=35 if any(s in name for s in ('cam','cin','zoom')) else 55
  dist=distance_polyline(x,z,pts);hard|=dist<=radius
  weight=np.minimum(weight,smoothstep((dist-radius)/45))
 return hard,weight
def spectrum_from_source(h,seed):
 """Phase-randomized source spectrum preserves each map's scale/direction.

 It is sampled from the existing height field, not a generic noise preset.
 The 150 m high-pass keeps the new ridges subordinate to authored landmarks.
 """
 residual=h-ndi.gaussian_filter(h,30)
 amplitude=np.abs(np.fft.rfft2(residual))
 rng=np.random.default_rng(seed);random=np.fft.rfft2(rng.normal(size=h.shape))
 signal=np.fft.irfft2(amplitude*random/np.maximum(np.abs(random),1e-12),s=h.shape).real
 signal=ndi.gaussian_filter(signal,4)
 lo,hi=np.percentile(signal,[3,97]);return np.clip((signal-lo)/max(hi-lo,1e-5),0,1)
def flat_regions(h):
 relief=ndi.maximum_filter(h,13)-ndi.minimum_filter(h,13)
 flat=relief<=1.;labels,n=ndi.label(flat)
 counts=np.bincount(labels.ravel());counts[0]=0
 return np.isin(labels,np.where(counts>=400)[0]),relief
def select_extent(name,x,z,bounds,envelope):
 x0,z0,x1,z1=bounds
 outside=np.hypot(np.maximum.reduce([x0-x,x-x1,np.zeros_like(x)]),np.maximum.reduce([z0-z,z-z1,np.zeros_like(z)]))
 edge=np.minimum.reduce([x-x0,x1-x,z-z0,z1-z])
 # Broad source-derived variations avoid a rectangular paint perimeter.
 near=outside<=(300+650*envelope)
 if name=='misn02b':return near&((x<1300)|(z<2000))
 if name=='misn06':return (x<1650)&(x>350)&(z>1950)&(z<3600)
 if name in ('misn12','misn13','misn14','misns5'):return near
 return near&(edge<(250+350*envelope))
def terrain_extension(name,h,b,origin,x,z,bounds):
 shape=spectrum_from_source(h,int.from_bytes(name.encode()[:4],'little')+sum(name.encode()))
 envelope=ndi.gaussian_filter(shape,45);lo,hi=np.percentile(envelope,[5,95]);envelope=np.clip((envelope-lo)/max(hi-lo,1e-6),0,1)
 flat,relief=flat_regions(h);selected=select_extent(name,x,z,bounds,envelope)&flat
 # "world" is misn14's closed area-of-interest outline, not a road.
 hard,protection=protect_masks(b,origin,x,z,exclude_paths=('world',) if name=='misn14' else ())
 # Start inside level areas and leave a C1-continuous join to authored relief.
 blend=smoothstep(ndi.distance_transform_edt(selected)*5/160)*protection
 amplitude=AMPLITUDE[name]
 delta=(shape**1.35*amplitude+4.0)*blend
 if name=='misns5':
  # Travel remains easy: long undulations, <= approximately 10 degree grade.
  shape=ndi.gaussian_filter(shape,18);shape=(shape-shape.min())/max(float(np.ptp(shape)),1e-6)
  delta=(shape*7+1)*blend
 return h+delta,hard,blend
def transform_south(z,x=None):
 # Stretch the actual 100 m metal bridge, rather than the northern landmass.
 bridge=np.where(z<1400,z-450,np.where(z<1500,950+(z-1400)*550/100,z))
 if x is None:return bridge
 return np.where((x>=2380)&(x<=2480),bridge,np.where(z<1500,z-450,z))

def bridge_source_z(z):
 return np.where(z<950,z+450,np.where(z<1500,1400+(z-950)*100/550,z))
def bridge_pass(h,mat,b,origin,x,z):
 oldz=bridge_source_z(z)
 hnew=ndi.map_coordinates(h,[oldz/5,x/5],order=1,mode='nearest')
 mz,mx=np.indices(mat.shape);old_mz=bridge_source_z(mz*20)
 newmat=ndi.map_coordinates(mat,[old_mz/20,mx],order=0,mode='nearest').astype(np.uint16)
 # Only the bridge is stretched. Southern side islands move intact; the
 # newly opened gap is lava, not tall strips of resampled shoreline.
 side=(x<2380)|(x>2480)
 southern=ndi.map_coordinates(h,[(z+450)/5,x/5],order=1,mode='nearest')
 hnew[side&(z<1050)]=southern[side&(z<1050)]
 hnew[(z>=1050)&(z<1500)]=5
 side_m=(mx*20<2380)|(mx*20>2480)
 southern_m=ndi.map_coordinates(mat,[mz+450/20,mx],order=0,mode='nearest').astype(np.uint16)
 newmat[side_m&(mz*20<1050)]=southern_m[side_m&(mz*20<1050)]
 newmat[(mz*20>=1050)&(mz*20<1500)]=0
 moved=[]
 for o,ox,oz in local_objects(b,origin):
  nz=float(transform_south(np.array(oz),np.array(ox)));dz=nz-oz
  if abs(dz)<1e-4:continue
  for key in ('pos','pos2'):
   if key in o.fields:
    v=[list(p) for p in o.fields[key].value]
    for p in v:p[2]+=dz
    o.fields[key]=Field('vec3',[tuple(p) for p in v])
  if 'transform' in o.fields:
   v=list(o.fields['transform'].value);v[11]+=dz;o.fields['transform']=Field('mat',tuple(v))
  moved.append(dict(label=o.label,shift_z_m=dz))
 for p in b.paths:
  pts=points(p);pts[:,1]=transform_south(pts[:,1]-origin[1],pts[:,0]-origin[0])+origin[1];path_update(p,pts)
 # A level 80 m deck with smooth approaches; its shoulders remain steep banks.
 across=1-smoothstep((np.abs(x-2430)-40)/30)
 along=smoothstep((z-850)/50)*(1-smoothstep((z-1560)/70))
 deck=across*along;hnew=hnew*(1-deck)+30*deck
 flat,relief=flat_regions(hnew)
 background=np.isin(newmat>>12,[0,1])
 lava=flat&(hnew<=5.4)&ndi.zoom(background,4,order=0)
 blend=smoothstep(ndi.distance_transform_edt(lava)*5/70)
 waves=.7+.45*np.sin(x/55+np.sin(z/160))+.2*np.sin(z/32+x/150)
 hnew+=waves*blend
 hard,_=protect_masks(b,origin,x,z)
 return hnew,newmat,hard,moved

def bridge_paint(mat,h):
 """Use the authored Io atlas's pool and metal families explicitly.

 Type 0 is the cracked red lava crust. Type 1 is the visible molten pool;
 type 5 is the manufactured deck. Neither can be inferred from slope alone.
 """
 result=mat.copy();mz,mx=np.indices(mat.shape);x,z=mx*20,mz*20
 result[np.isin(mat>>12,[0,1])]=0x1100
 # Hardened lava on the actual shoulders, never painted over the pool.
 apron=(x>=2360)&(x<=2500)&(z>=900)&(z<=1560)&(h[::4,::4]>10)
 result[apron]=0x4400
 metal=(x>=2400)&(x<=2440)&(z>=940)&(z<=1500)
 # Keep one consistent orientation on the metal panels.
 result[metal]=0x5500
 return result

def canyon_pass(h,b,origin,x,z,bounds):
 """An eroded upland cut by a continuous S-shaped canyon blocks the rush.

 Preserve all pads. Carve a connected passage through the older relief, and
 route the mission's counterattack through that same canyon in reverse.
 """
 route=np.array([[2440,1320],[2430,1750],[2100,2120],[1640,2430],[1580,2750],[1950,3000],[2430,3100],[2940,3260],[3090,3530],[3080,3800],[2850,4050],[2600,4270],[2714,4395]],float)
 d=distance_polyline(x,z,route)
 hard,protect=protect_masks(b,origin,x,z,exclude_paths=('counter_attack_path','path_2','path6','protectme'))
 # Reuse the map's relief spectrum for eroded canyon walls and uplands.
 motif=spectrum_from_source(h,8646)
 interior=np.minimum.reduce([x-(1050+120*np.sin(z/320)),(4100+140*np.sin(z/450))-x,z-(1820+180*np.sin(x/500)),(4400+120*np.sin(x/400))-z])
 extent=smoothstep(interior/65)
 # The outer cliff must also rise above the source's existing high ground;
 # otherwise a vehicle can enter via that high ground and cross the upland.
 crest=225+motif*35
 result=h+(np.maximum(h,crest)-h)*extent*protect
 # Lower the route to a smooth canyon floor; keep hard pads and ramp into them.
 floor=35+4*np.sin(z/900)+2*ndi.gaussian_filter(motif,20)
 carve=(1-smoothstep((d-70)/40))*protect
 result=result*(1-carve)+floor*carve
 # Safe connections to authored object pads within 350 m of the main lane.
 # Counterattack path is explicit rather than crossing the blocking ridges.
 for o,ox,oz in local_objects(b,origin):
  if o.class_label in ('scrap','scrapfield','camerapod'):continue
  dense=np.vstack([np.linspace(a,b,max(2,int(np.linalg.norm(b-a)/20))) for a,b in zip(route[:-1],route[1:])])
  idx=np.argmin(np.sum((dense-[ox,oz])**2,axis=1));end=dense[idx]
  if np.linalg.norm(end-[ox,oz])>900:continue
  spur=distance_polyline(x,z,np.array([[ox,oz],end]))
  weight=(1-smoothstep((spur-45)/45))*protect
  ix=int(np.clip(round(ox/5),0,h.shape[1]-1));iz=int(np.clip(round(oz/5),0,h.shape[0]-1))
  t=np.clip(np.hypot(x-ox,z-oz)/max(float(np.linalg.norm(end-[ox,oz])),1),0,1)
  target=h[iz,ix]*(1-t)+floor*t
  result=result*(1-weight)+target*weight
 for p in b.paths:
  if label(p)=='counter_attack_path':path_update(p,route[::-1]+origin)
 return result,hard,route

def set_edge(b,bounds):
 edge=next((p for p in b.paths if label(p).lower()=='edge_path'),None)
 if edge is None:
  template=copy.deepcopy(b.paths[0]);template['label']=Field('chars',b'edge_path');template['label.size']=Field('ulong',9)
  if 'old_ptr' in template:template['old_ptr']=Field(template['old_ptr'].kind,0 if template['old_ptr'].kind!='void' else b'\0'*4)
  edge=template;b.paths.append(edge)
 path_update(edge,[[bounds[0],bounds[1]],[bounds[2],bounds[3]]])

def slot(doc,value):
 e=decode_entry(int(value));sec=doc.texture_types().get(e.base)
 if sec is None:return None
 for i in range(e.variant&3,-1,-1):
  key=f'Solid{"ABCD"[i]}0' if e.base==e.next else f'{"DiagonalTo" if e.cap else "CapTo"}{e.next}_{"ABCD"[i]}0'
  if sec.get(key):return sec.get(key)
 return None
def coarse_metrics(h):
 gz,gx=np.gradient(ndi.gaussian_filter(h,1),5)
 slope=np.hypot(gx,gz)
 return h[::4,::4],slope[::4,::4]
def repaint(name,oldh,newh,mat,doc,change):
 old_e,old_s=coarse_metrics(oldh);new_e,new_s=coarse_metrics(newh)
 valid=np.array([slot(doc,v) is not None for v in mat.ravel()]).reshape(mat.shape)
 base=(mat>>12).astype(np.uint8);nxt=((mat>>8)&15).astype(np.uint8)
 train=valid&(base==nxt)
 solid_types=[t for t in doc.texture_types() if slot(doc,(t<<12)|(t<<8)) is not None]
 floor=float(np.median(oldh));scale=max(float(np.percentile(oldh,95)-np.percentile(oldh,5)),20)
 features=np.c_[((old_e-floor)/scale)[train],(old_s*2)[train]]
 tree=cKDTree(features);ids=np.flatnonzero(train)
 _,nearest=tree.query(np.c_[((new_e-floor)/scale).ravel(),(new_s*2).ravel()])
 labels=base.ravel()[ids[nearest]].reshape(mat.shape).copy()
 if name in ('misn10','misn15b','misns4'):
  land=(new_e-old_e>4)&np.isin(labels,[0,1]);labels[land]=np.where(new_s[land]>.35,4,3)
 if name=='misns4':labels[(new_e<3)&(old_e<3)]=0
 # Keep corner labels outside the repaint patch sourced from the original MAT.
 changed=ndi.maximum_filter(change.astype(np.uint8),9)[::4,::4]>0
 labels[~changed]=base[~changed]
 result=mat.copy();rng=MSVCRand(1014)
 for z,x in zip(*np.where(changed)):
  zs=min(z+1,mat.shape[0]-1);xs=min(x+1,mat.shape[1]-1)
  corners=[labels[z,x],labels[z,xs],labels[zs,xs],labels[zs,x]]
  value,_=encode_make_trn_tile(corners,rng)
  if slot(doc,value) is None:
   counts=np.bincount(corners,minlength=16);choice=int(np.argmax(counts));value=(choice<<12)|(choice<<8)
  if slot(doc,value) is None:value=(solid_types[0]<<12)|(solid_types[0]<<8)
  result[z,x]=value
 return result,changed

def build(name,args):
 bpath=load_baseline(name,'.bzn',args);b=read_bzn(bpath)
 original_b=copy.deepcopy(b);terrain=Path(b.terrain_name).stem.lower()
 hp=load_baseline(terrain,'.hg2',args);head,raw=read_hg2(hp);h=raw.astype(float)/10
 mp=load_baseline(terrain,'.mat',args);mat=read_mat(mp,head.zones_x,head.zones_z)
 trnp=load_baseline(terrain,'.trn',args);doc=TRNDocument.read(trnp);origin=np.array([doc.size.min_x,doc.size.min_z]);z,x=np.indices(h.shape,dtype=float);x*=5;z*=5
 edge=next((p for p in b.paths if label(p).lower()=='edge_path'),None)
 pts=points(edge)-origin if edge else np.array([[30,30],[doc.size.width-30,doc.size.depth-30]])
 bounds=np.r_[pts.min(axis=0),pts.max(axis=0)];oldbounds=bounds.copy();moved=[];route=None
 if name=='misns4':new,newmat,hard,moved=bridge_pass(h,mat,b,origin,x,z);bounds[1]=float(transform_south(np.array(bounds[1])));set_edge(b,bounds+np.tile(origin,2))
 elif name=='misns6':new,hard,route=canyon_pass(h,b,origin,x,z,bounds);newmat=mat
 else:new,hard,blend=terrain_extension(name,h,b,origin,x,z,bounds);newmat=mat
 if name in ('misn12','misn13'):
  # Bound the rectangular canyon complex, retaining all starts, objectives and
  # authored mission paths; the engine does not implement polygon edge paths.
  active=[]
  for o,ox,oz in local_objects(b,origin):
   if not o.prjid.startswith(('fake','pspwn')):active.append([ox,oz])
  for p in b.paths:
   if label(p) and not any(k in label(p).lower() for k in ('edge','bound','border','camera','cam','cin')):active.extend(points(p)-origin)
  p=np.array(active);bounds=np.r_[np.maximum(p.min(axis=0)-110,oldbounds[:2]),np.minimum(p.max(axis=0)+110,oldbounds[2:])]
  set_edge(b,bounds+np.tile(origin,2))
 new=np.round(np.clip(new,0,409.5)*10)/10
 changed=np.abs(new-h)>=.049
 if name!='misns4':assert np.array_equal(new[hard],h[hard]),'Protected pad changed'
 painted,paintmask=repaint(name,h,new,newmat,doc,changed)
 if name=='misns4':painted=bridge_paint(newmat,new)
 out=REPO/'Missions';out.mkdir(exist_ok=True)
 write_hg2(out/(terrain+'.hg2'),new*10,head.zones_x,head.zones_z)
 write_mat(out/(terrain+'.mat'),painted,head.zones_x,head.zones_z)
 # Every newly restored map has its own TRN and LGT companions.
 if not (out/(terrain+'.trn')).exists():(out/(terrain+'.trn')).write_bytes(trnp.read_bytes())
 lp=load_baseline(terrain,'.lgt',args);lighting_rebuilt=False
 try:lm,_,_,ls=read_lgt(lp,head.zones_x,head.zones_z)
 except ValueError:
  # Several stock LGTs have fewer chunks than their current HG2/TRN extents.
  # Do not reinterpret them at a guessed layout. Bake a complete soft map.
  level=int(np.percentile(np.frombuffer(lp.read_bytes(),np.uint8),80))
  lm=np.full(h.shape,level,np.uint8);lighting_rebuilt=True
 lchange=ndi.zoom(changed.astype(float),(lm.shape[0]/changed.shape[0],lm.shape[1]/changed.shape[1]),order=0)>0
 if lighting_rebuilt or name=='misns4':lchange[:]=True
 # Remove obsolete baked shadows only on modified land; use soft local light.
 gz,gx=np.gradient(ndi.gaussian_filter(new,2),5);normal=np.dstack([-gx,-gz,np.ones_like(new)]);normal/=np.linalg.norm(normal,axis=2,keepdims=True)
 shade=np.clip(normal@np.array([-.4,.3,.866]),.2,1)
 shade=ndi.zoom(shade,(lm.shape[0]/h.shape[0],lm.shape[1]/h.shape[1]),order=1)
 relit=lm.copy();level=float(np.percentile(lm,80));relit[lchange]=np.clip(level*(.65+.35*shade[lchange]),0,255)
 write_lgt(out/(terrain+'.lgt'),relit,head.zones_x,head.zones_z,border=int(lp.read_bytes()[0]))
 if name in ('misn12','misn13','misns4','misns6'):
  (out/(name+'.bzn')).write_bytes(b.write())
  reread=read_bzn(out/(name+'.bzn'));assert len(reread.objects)==len(b.objects)
  assert [o.label for o in reread.objects]==[o.label for o in original_b.objects]
 if name=='misns4':
  # Interior mission data use the same Z warp as terrain and path coordinates.
  assert moved
 np.savez_compressed(LOCAL/(name+'.npz'),before=h,after=new,mat_before=mat,mat_after=painted,changed=changed,hard=hard,bounds_before=oldbounds,bounds_after=bounds)
 metrics=dict(name=name,terrain=terrain,modified_km2=float(changed.sum()*25/1e6),changed_height_samples=int(changed.sum()),max_height_delta_m=float(np.max(abs(new-h))),changed_paint_cells=int(np.sum(painted!=mat)),protected_samples=int(hard.sum()),lighting_rebuilt=lighting_rebuilt,bounds_before=oldbounds.tolist(),bounds_after=bounds.tolist(),moved_objects=moved,route=route.tolist() if route is not None else None)
 print(json.dumps(metrics),flush=True);return metrics

def main():
 global ARCHIVE,CACHE,LOCAL,SOURCES,read_bzn,Field,read_hg2,write_hg2,read_mat,write_mat,decode_entry,TRNDocument,MSVCRand,encode_make_trn_tile,read_lgt,write_lgt
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--game-root',type=Path,required=True);parser.add_argument('--toolbox',type=Path,default=REPO.parent/'Battlezone98_Modding_Toolbox');parser.add_argument('--base',default=BASE);parser.add_argument('--height-ref',default='ce18e89');parser.add_argument('--maps',nargs='+',default=MAPS,choices=MAPS);args=parser.parse_args()
 sys.path.insert(0,str(args.toolbox))
 from battlezone.archives.zfs import ZFSArchive
 from battlezone.bzn.bz1 import read_bzn,Field
 from battlezone.terrain.hg2 import read_hg2,write_hg2
 from battlezone.terrain.mat import read_mat,write_mat,decode_entry
 from battlezone.terrain.trn import TRNDocument
 from battlezone.terrain.lgt import read_lgt,write_lgt
 from bztoolbox.modules.world.mat_codec import MSVCRand,encode_make_trn_tile
 ARCHIVE=ZFSArchive(args.game_root/'bzone.zfs');LOCAL=REPO/'Local/terrain-edge-pass';LOCAL.mkdir(parents=True,exist_ok=True);CACHE=LOCAL/'baseline';CACHE.mkdir(exist_ok=True);SOURCES={}
 previous=json.loads((LOCAL/'build.json').read_text()) if (LOCAL/'build.json').exists() else dict(maps=[],sources={})
 results=[build(name,args) for name in args.maps]
 byname={r['name']:r for r in previous['maps']};byname.update({r['name']:r for r in results});sources=previous['sources'];sources.update(SOURCES)
 (LOCAL/'build.json').write_text(json.dumps(dict(base=args.base,height_ref=args.height_ref,maps=[byname[n] for n in MAPS if n in byname],sources=sources),indent=2))
if __name__=='__main__':main()
