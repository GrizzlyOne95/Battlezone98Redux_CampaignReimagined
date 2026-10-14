"""Render before/after terrain changes using the Toolbox atlas definitions."""
from pathlib import Path
import argparse,importlib.util,json,sys
import numpy as np
from scipy import ndimage as ndi
from PIL import Image
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import LightSource
from matplotlib.patches import Rectangle

REPO=Path(__file__).resolve().parents[1]
def render(args):
 sys.path.insert(0,str(args.toolbox))
 from battlezone.terrain.trn import TRNDocument
 from battlezone.terrain.mat import decode_entry
 from battlezone.terrain.atlas import read_atlas_csv,read_atlas_default,read_materials
 files={p.name.lower():p for root in [args.game_root/'BZ_ASSETS_CORE',args.game_root/'BZ_ASSETS',REPO/'Assets',REPO/'Materials'] for p in root.rglob('*') if p.is_file()}
 local=REPO/'Local/terrain-edge-pass';out=local/'review';out.mkdir(exist_ok=True)
 titles={'misns4':"Io's Bridge",'misns5':'Controlling the High Ground','misns6':'Clear the Path','misn02b':'Red Arrival','misn06':'Escape from Mars','misn07':'Behind Enemy Lines','misn08':'A Nasty Surprise','misn09':'Wrangling the Fleeing Herd','misn10':'The Race is On','misn12':'Flying Solo','misn13':'Total Destruction','misn14':'The Three Beacons','misn15b':'United We Fight - United We Die','misn16':'Strike at the Heart'}
 def paint(mat,doc):
  name=doc.material_name;csv=files[name.lower()+'.csv'];cells=read_atlas_csv(csv);fallback=read_atlas_default(csv);material=read_materials(REPO/'Materials')[name.lower()];image=Image.open(files[material.diffuse.lower()]).convert('RGB');width,height=image.size;scale=4;arr=np.zeros((mat.shape[0]*scale,mat.shape[1]*scale,3),np.uint8)
  for value in np.unique(mat):
   e=decode_entry(int(value));sec=doc.texture_types().get(e.base);alias=None
   if sec:
    for i in range(e.variant&3,-1,-1):
     key=f'Solid{"ABCD"[i]}0' if e.base==e.next else f'{"DiagonalTo" if e.cap else "CapTo"}{e.next}_{"ABCD"[i]}0';alias=sec.get(key)
     if alias:break
   cell=cells.get(alias.upper()) if alias else None;cell=cell or fallback;tile=np.flipud(np.asarray(image.crop(cell.box(width,height)).resize((scale,scale),Image.Resampling.BILINEAR)))
   if e.flip:tile=np.fliplr(tile)
   tile=np.rot90(tile,e.rotation)
   zz,xx=np.where(mat==value)
   for z,x in zip(zz,xx):arr[z*scale:(z+1)*scale,x*scale:(x+1)*scale]=tile
  return arr
 rows=[]
 for p in sorted(local.glob('*.npz')):
  name=p.stem
  if args.maps and name not in args.maps:continue
  data=np.load(p);terrain='misn16b' if name=='misn16' else name;doc=TRNDocument.read(REPO/'Missions'/(terrain+'.trn'));w,d=doc.size.width,doc.size.depth;extent=[0,w,0,d]
  fig,axs=plt.subplots(1,3,figsize=(17,6.3),layout='constrained',facecolor='#101820')
  panels=[]
  for key,mkey in [('before','mat_before'),('after','mat_after')]:
   h=data[key];rgb=paint(data[mkey],doc);shade=LightSource(315,45).hillshade(h,vert_exag=2,dx=5,dy=5);rgb=np.clip(rgb*(.55+.6*shade[...,None]),0,255).astype('uint8');panels.append(rgb)
  axs[0].imshow(panels[0],origin='lower',extent=extent);axs[1].imshow(panels[1],origin='lower',extent=extent)
  delta=data['after']-data['before'];im=axs[2].imshow(delta,origin='lower',extent=extent,cmap='RdBu_r',vmin=-max(10,abs(delta).max()),vmax=max(10,abs(delta).max()));fig.colorbar(im,ax=axs[2],label='Height delta (m)',shrink=.6)
  for i,ax in enumerate(axs):
   bounds=data['bounds_before'] if i==0 else data['bounds_after'];x0,z0,x1,z1=bounds;ax.add_patch(Rectangle((x0,z0),x1-x0,z1-z0,fill=False,color='#00e8ff',lw=1.4));ax.set_xlabel('Local X (m)',color='white');ax.set_ylabel('Local Z (m)',color='white');ax.tick_params(colors='#acbdcc',labelsize=8);ax.set_aspect('equal')
  for ax,title in zip(axs,['Baseline HG2 + MAT','Revised HG2 + MAT','Changed terrain / preserved pads']):ax.set_title(title,color='white')
  fig.suptitle(f'{name} · {titles.get(name,name)}\nCyan: playable bounds | 2× relief shading',color='white',fontsize=15);fig.savefig(out/(name+'.png'),dpi=135,facecolor=fig.get_facecolor());plt.close(fig)
  Image.fromarray(np.flipud(panels[1])).save(out/(name+'_after.png'))
  rows.append((name,panels,data['bounds_after'].copy(),extent))
  print('Rendered',name,flush=True)
 if len(rows)>1:
  fig,axs=plt.subplots(int(np.ceil(len(rows)/3)),3,figsize=(15,int(np.ceil(len(rows)/3))*5),layout='constrained',facecolor='#101820',squeeze=False)
  for ax in axs.flat:ax.set_visible(False)
  for ax,(name,panels,bounds,extent) in zip(axs.flat,rows):
   ax.set_visible(True);ax.imshow(panels[1],origin='lower',extent=extent);x0,z0,x1,z1=bounds;ax.add_patch(Rectangle((x0,z0),x1-x0,z1-z0,fill=False,color='#00e8ff'));ax.set_title(name+' · '+titles.get(name,name),color='white');ax.set_xticks([]);ax.set_yticks([])
  fig.suptitle('Terrain edge pass — revised terrain and paints',color='white',fontsize=18);fig.savefig(out/'all_maps.png',dpi=125,facecolor=fig.get_facecolor());plt.close(fig)
 html='<!doctype html><meta charset="utf-8"><title>Terrain implementation review</title><style>body{background:#101820;color:white;font:16px system-ui;margin:35px}img{width:100%}h2{margin-top:40px}a{color:cyan}</style><h1>Terrain implementation review</h1><p>Before / after / height delta. Asset render only; in-game driving and AI checks remain required.</p>'
 html+='<p>Review corrections: misn14 has no flat road along its square world outline. misns4 has a 550 m level metal bridge, intact southern islands, and molten lava paint with small height waves.</p>'
 deployment=local/'deployment.json'
 if deployment.exists():
  status=json.loads(deployment.read_text())
  if status.get('status')=='verified':html+=f'<p>Deployed to the GOG CR development mod: {status["expected_files"]:,} shipping files verified; zero missing, differing or unexpected files. Workshop publication has not been performed.</p>'
 for name,_,_,_ in rows:html+=f'<h2>{name} — {titles.get(name,name)}</h2><a href="{name}.png"><img src="{name}.png"></a>'
 (out/'index.html').write_text(html,encoding='utf-8')
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--game-root',type=Path,required=True);p.add_argument('--toolbox',type=Path,default=REPO.parent/'Battlezone98_Modding_Toolbox');p.add_argument('--maps',nargs='*');render(p.parse_args())
