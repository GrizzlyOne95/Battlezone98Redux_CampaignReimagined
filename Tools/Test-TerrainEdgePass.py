"""Asset and navigation-proxy checks for the terrain prototype.

Navigation uses a 20 m grid with a 35 degree slope ceiling; this is an offline
screen, not a claim about hover physics or the engine's AI path planner.
"""
from pathlib import Path
import argparse,importlib.util,json,sys
import numpy as np
from scipy import ndimage as ndi
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra

REPO=Path(__file__).resolve().parents[1]
def shortest(h,bounds,start,goal):
 coarse=h[::4,::4];z,x=np.indices(coarse.shape);x=x*20;z=z*20
 valid=(x>=bounds[0])&(x<=bounds[2])&(z>=bounds[1])&(z<=bounds[3]);indices=np.arange(coarse.size).reshape(coarse.shape)
 rows=[];cols=[];weights=[]
 for dz,dx in [(0,1),(1,0),(1,1),(1,-1)]:
  zz,xx=np.indices(coarse.shape);tz,tx=zz+dz,xx+dx;ok=(tz>=0)&(tz<coarse.shape[0])&(tx>=0)&(tx<coarse.shape[1]);sz,sx=zz[ok],xx[ok];tz,tx=tz[ok],tx[ok];step=20*np.hypot(dz,dx);dh=abs(coarse[sz,sx]-coarse[tz,tx]);allowed=valid[sz,sx]&valid[tz,tx]&(dh<=step*np.tan(np.radians(35)))
  i,j=indices[sz[allowed],sx[allowed]],indices[tz[allowed],tx[allowed]];distance=np.sqrt(step**2+dh[allowed]**2);rows.extend([i,j]);cols.extend([j,i]);weights.extend([distance,distance])
 graph=coo_matrix((np.concatenate(weights),(np.concatenate(rows),np.concatenate(cols))),shape=(coarse.size,coarse.size)).tocsr()
 start_index=int(round(start[1]/20))*coarse.shape[1]+int(round(start[0]/20));goal_index=int(round(goal[1]/20))*coarse.shape[1]+int(round(goal[0]/20))
 distances,predecessors=dijkstra(graph,indices=start_index,return_predecessors=True);length=float(distances[goal_index]);path=[]
 if np.isfinite(length):
  node=goal_index
  while node!=start_index:
   path.append([int(node%coarse.shape[1]*20),int(node//coarse.shape[1]*20)]);node=int(predecessors[node]);assert node>=0
  path.append(list(start));path.reverse()
 return length,path

def run(args):
 sys.path.insert(0,str(args.toolbox));spec=importlib.util.spec_from_file_location('edge_build',REPO/'Tools/Build-TerrainEdgePass.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 from battlezone.bzn.bz1 import read_bzn,Field,compare_bzn
 from battlezone.terrain.hg2 import read_hg2
 from battlezone.terrain.mat import read_mat
 from battlezone.terrain.trn import TRNDocument
 from battlezone.terrain.lgt import read_lgt
 module.decode_entry=__import__('battlezone.terrain.mat',fromlist=['decode_entry']).decode_entry
 local=REPO/'Local/terrain-edge-pass';build=json.loads((local/'build.json').read_text());checks=[]
 for row in build['maps']:
  name,terrain=row['name'],row['terrain'];data=np.load(local/(name+'.npz'));old,new=data['before'],data['after'];head,hg=read_hg2(REPO/'Missions'/(terrain+'.hg2'));doc=TRNDocument.read(REPO/'Missions'/(terrain+'.trn'));mat=read_mat(REPO/'Missions'/(terrain+'.mat'),head.zones_x,head.zones_z);lm,*_=read_lgt(REPO/'Missions'/(terrain+'.lgt'),head.zones_x,head.zones_z)
  assert np.array_equal(hg,np.rint(new*10).astype(np.uint16));assert new.min()>=0 and new.max()<=409.5
  assert doc.size.width==head.zones_x*1280 and doc.size.depth==head.zones_z*1280
  changed=mat!=data['mat_before'];bad=[int(v) for v in np.unique(mat[changed]) if module.slot(doc,v) is None];assert not bad,(name,bad)
  if name!='misns4':assert np.array_equal(new[data['hard']],old[data['hard']])
  base=read_bzn(local/'baseline'/(name+'.bzn'));out=REPO/'Missions'/(name+('cr' if name in ('misn12','misn13') else '')+'.bzn');revised=read_bzn(out) if out.exists() else base
  assert len(base.objects)==len(revised.objects);assert [o.label for o in base.objects]==[o.label for o in revised.objects]
  if name!='misns4':
   for a,b in zip(base.objects,revised.objects):
    for key,value in a.fields.items():assert value.value==b.fields[key].value,(name,a.label,key)
  if name in ('misn12','misn13'):
   oldarea=np.prod(data['bounds_before'][2:]-data['bounds_before'][:2]);area=np.prod(data['bounds_after'][2:]-data['bounds_after'][:2]);assert area<oldarea
   x0,z0,x1,z1=data['bounds_after']
   for o in revised.objects:
    ox,_,oz=o.fields['pos'].value[0];ox-=doc.size.min_x;oz-=doc.size.min_z;assert x0<=ox<=x1 and z0<=oz<=z1,(name,o.label)
  if name=='misns4':
   for a,b in zip(base.objects,revised.objects):
    p,q=np.array(a.fields['pos'].value[0]),np.array(b.fields['pos'].value[0]);assert p[0]==q[0] and p[1]==q[1]
    assert abs(float(module.transform_south(np.array(p[2]-doc.size.min_z),np.array(p[0]-doc.size.min_x)))+doc.size.min_z-q[2])<.02
   p=np.array([o.fields['pos'].value[0] for o in base.objects]);q=np.array([o.fields['pos'].value[0] for o in revised.objects]);oldground=ndi.map_coordinates(old,[(p[:,2]-doc.size.min_z)/5,(p[:,0]-doc.size.min_x)/5],order=1);newground=ndi.map_coordinates(new,[(q[:,2]-doc.size.min_z)/5,(q[:,0]-doc.size.min_x)/5],order=1);offset_delta=float(np.max(abs(oldground-newground)));assert offset_delta<6,offset_delta
  record=dict(name=name,dimensions='pass',changed_paint_slots='pass',objects='pass',protected_pads='pass' if name!='misns4' else 'coordinated 450m Z warp')
  if name=='misn14':
   world=next(p for p in base.paths if module.label(p)=='world');pts=module.points(world)-[doc.size.min_x,doc.size.min_z]
   zz,xx=np.indices(new.shape);lane=(module.distance_polyline(xx*5,zz*5,pts)<30)&(old==5)&~data['hard']
   coverage=float(np.mean((new-old)[lane]>1));assert coverage>.8,('Artificial world-outline corridor',coverage)
   record['world_outline_relief_coverage']=coverage
  if name=='misns4':
   # Independently specified visible/gameplay contract: 550 m level crossing,
   # uninterrupted metal deck, molten pool across the surrounding sea.
   assert np.all(new[190:301,480:493]==30),'Bridge deck must be level at 30 m'
   assert np.all(mat[48:75,120:123]>>12==5),'Metal deck has gaps'
   assert not np.any(mat>>12==0),'Cracked red crust remains in the lava sea'
   assert np.all(mat[:,:80]>>12==1),'Outer sea must use the molten-pool texture'
   assert np.ptp(new[20:180,20:180])>=1,'Lava waves are absent'
   # Escort waypoints and the interpolated crossing stay on the metal deck.
   escort=next(p for p in revised.paths if module.label(p)=='escort');pts=module.points(escort)-[doc.size.min_x,doc.size.min_z]
   dense=np.vstack([np.linspace(a,b,101) for a,b in zip(pts[:-1],pts[1:])]);cross=dense[(dense[:,1]>=950)&(dense[:,1]<=1500)]
   ground=ndi.map_coordinates(new,[cross[:,1]/5,cross[:,0]/5],order=1)
   assert len(cross)>0 and np.all(abs(ground-30)<.11),'Escort route leaves the level deck'
   record.update(bridge_length_m=550,bridge_deck_height_range_m=[30,30],metal_deck='pass',lava_pool='pass',escort_crossing='pass')
  if name=='misns5':
   gz,gx=np.gradient(new-old,5);grade=np.degrees(np.arctan(np.hypot(gx,gz)));record['max_added_slope_deg']=float(grade.max());assert grade.max()<15
  if name=='misns6':
   start=np.array(next(o.fields['pos'].value[0] for o in revised.objects if o.label=='svrecy0_recycler'))[[0,2]]-[doc.size.min_x,doc.size.min_z];goal=np.array(next(o.fields['pos'].value[0] for o in revised.objects if o.label=='abcafe8_i76building'))[[0,2]]-[doc.size.min_x,doc.size.min_z]
   length,path=shortest(new,data['bounds_after'],start,goal);before,_=shortest(old,data['bounds_before'],start,goal);direct=float(np.linalg.norm(goal-start))
   record.update(route_length_m=length,baseline_route_length_m=before,direct_m=direct,detour_ratio=length/direct);(local/'canyon_navigation.json').write_text(json.dumps(dict(**record,path=path),indent=2))
   assert np.isfinite(length),'Canyon has no navigable proxy route';assert length/direct>1.35,('Canyon still permits a short rush',length,direct)
  checks.append(record);print(json.dumps(record),flush=True)
 (local/'validation.json').write_text(json.dumps(dict(status='pass',maps=checks,navigation_limit='20m grid, <=35 degree slope; runtime hover/AI untested'),indent=2))
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--toolbox',type=Path,default=REPO.parent/'Battlezone98_Modding_Toolbox');run(p.parse_args())
