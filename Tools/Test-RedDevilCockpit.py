"""POV, cockpit selection, skinning, sightline, atlas/glow and shipping checks."""
from pathlib import Path
import hashlib,importlib.util,io,json,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
import reddevilcockpit as cp
import cockpitglass as cg
from bcdds import bc_dds_problem
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/RedDevilLegacy';count=0

def check(ok,message):
    global count
    assert ok,message
    count+=1

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
recipe=json.loads((REF/'cockpit.json').read_text());receipt=json.loads((REF/'cockpit-build.json').read_text())
for name,digest in receipt['masters'].items():check(sha(REF/name)==digest,'authored cockpit master pinned')
for name,digest in receipt['outputs'].items():
    p=ROOT/name;actual=hashlib.sha256(p.read_text().encode()).hexdigest() if p.suffix=='.material' else sha(p)
    check(actual==digest,'compiled resource hash: '+name)
check((ROOT/'Assets/Models/bvrdev_cockpit.skeleton').read_bytes()==(REF/'original/bvrdev.skeleton').read_bytes(),'POV and every original bone/hardpoint unchanged')
check((ROOT/'Assets/ModelFixes/bvrdev.mesh').read_bytes()==(REF/'original/bvrdev.mesh').read_bytes(),'exterior and old fallback mesh untouched')
skeleton,world,eye,shell=cp.rig(REF/'original/bvrdev.skeleton');origin,R=world[eye.handle]
check(eye.name==receipt['alignment']['pov']=='brd11POV','real POV bone authority')
check(np.allclose(origin,receipt['alignment']['povPosition'],atol=1e-8),'exact eye-frame origin, not bounding-box centering')
check(np.allclose(R,receipt['alignment']['povBasis'],atol=1e-8),'POV orientation retained')
check(shell.handle==receipt['alignment']['shellHandle']==14 and shell.name=='brd21BDA','stable cockpit shell binding')
mesh=cp.read_mesh(ROOT/'Assets/Models/bvrdev_cockpit.mesh')
check(mesh.skeleton_name=='bvrdev_cockpit.skeleton','dedicated first-person rig resource')
check([s.material_name for s in mesh.submesh_list]==[cp.MATERIAL,cp.BOW,'CRWX_CockpitGlass'],'cockpit / real foredeck / fitted weather glass')
opaque=[]
for sub in mesh.submesh_list:
    d=sub.vertex_data;p=cp.values(d,cp.om.VES.POSITION);n=cp.values(d,cp.om.VES.NORMAL);uv=cp.values(d,cp.om.VES.TEXTURE_COORDINATES);t=cp.values(d,cp.om.VES.TANGENT)
    check(np.isfinite(p).all() and np.isfinite(uv).all(),'finite positions and UVs')
    check(np.allclose(np.linalg.norm(n,axis=1),1,atol=.002),'unit authored normals')
    check(np.isfinite(t).all() and np.allclose(np.linalg.norm(t,axis=1),1,atol=.003),'finite unit tangents for DX11 input')
    assignments=list(sub.bone_assignments())
    check(len(assignments)==len(p) and all(a.bone_index==14 and a.weight==1 for a in assignments),'every drawn vertex follows correct cockpit shell')
    tri=p[sub.index_array.reshape(-1,3)]
    check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),'no degenerate triangles')
    if sub.material_name!='CRWX_CockpitGlass':
        check(uv.min()>=0 and uv.max()<=1,'opaque UVs remain inside their source atlas')
        opaque.append(tri)
tri=np.concatenate(opaque)
dirs=np.array([[np.sin(np.radians(yaw)),np.sin(np.radians(pitch)),np.cos(np.radians(yaw))] for yaw in (-5,0,5) for pitch in (0,5)])@R.T
distance,_=cg.cast(origin,dirs,tri[:,0],tri[:,1],tri[:,2])
check(np.isinf(distance).all(),'clear central aiming corridor at actual POV')
shell_receipt=receipt['alignment']['innerShell']
check(shell_receipt['boundaryLoops']==1 and shell_receipt['triangles']>30,'connected manifold inner shell with only intended canopy opening')
for pitch,label in [(-60,'floor / lower side seams'),(85,'roof seams')]:
    yaws=np.radians(np.arange(-180,180,10));p=np.radians(pitch)
    rays=np.column_stack([np.cos(p)*np.sin(yaws),np.full(len(yaws),np.sin(p)),np.cos(p)*np.cos(yaws)])@R.T
    distances,_=cg.cast(origin,rays,tri[:,0],tri[:,1],tri[:,2])
    check(np.isfinite(distances).all(),'no unintended see-through gaps: '+label)
distances,_=cg.cast(origin,np.array([[0,0,-1.]])@R.T,tri[:,0],tri[:,1],tri[:,2])
check(np.isfinite(distances).all(),'rear bulkhead closes cockpit behind POV')
check(receipt['alignment']['foredeckTriangles']==252,'actual pointed Red Devil nose selected, not an invented hood')
check(receipt['glass']['bone']=='brd21BDA' and receipt['glass']['vertices']>0,'weather glass refit to new shell')
src=cg.Sources(game=str(ROOT/'Local/nonexistent-game'),cr=str(ROOT));selected,kind,_=cg.cockpit_mesh(src,'bvrdev')
check(kind=='separate' and Path(selected).name=='bvrdev_cockpit.mesh','documented engine lookup selects the separate cockpit before stock fallback')
spec=importlib.util.spec_from_file_location('build_cockpit',ROOT/'Tools/Build-RedDevilCockpit.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
d,e,mask=build.textures(recipe)
check(sha(REF/'cockpit-glass-mask.png')==receipt['glassMaskSha256'],'physical optical mask pinned')
check(np.array_equal(np.array(mask),np.array(Image.open(REF/'cockpit-glass-mask.png'))),'saved mask reproduces')
for channel,expected in [('d',d),('e',e)]:
    p=ROOT/'Assets/Textures'/('crvrdcp_'+channel+'.dds')
    check(bc_dds_problem(p.read_bytes(),1024,1024) is None,'legacy BC1 header / complete mips')
    with Image.open(p) as im:actual=np.array(im.convert('RGB')).astype(float)
    check(np.abs(actual-np.array(expected)).mean()<4,'compiled atlas matches authored source / glass mask')
    if channel=='e':
        for name in ('frame','armor','trim'):
            x0,y0,x1,y1=recipe['charts'][name]['target'];check(actual[y0:y1,x0:x1].max()<10,'frame/armor/trim remain non-emissive')
material=(ROOT/'Materials/CR_reddevil_cockpit.material').read_text()
check('CRV/RedDevilCockpit : CR_BZBaseCockpit' in material and 'CRV/RedDevilForedeck : CR_BZBaseCockpit' in material,'correct first-person material parent for both opaque batches')
members={r['source'].replace('\\','/'):r['runtime'] for r in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
for path in receipt['outputs']:check(members.get(path)==Path(path).name,'case-correct unique shipping resource: '+path)
# Negative fixture: an eye moved far below the cockpit intersects the dash.
bad=origin+R@np.array([0,-.5,0]);distance,_=cg.cast(bad,np.array([[0,0,1.]])@R.T,tri[:,0],tri[:,1],tri[:,2])
check(np.isfinite(distance).all(),'misaligned-eye negative fixture hits cockpit instead of clear view')
print(f'Red Devil cockpit: {count} checks passed')
