"""Independent faction crate resolution, exact stock geometry and mip contracts."""
from pathlib import Path
import io,json,re,hashlib,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh_serializer as oms
from bcdds import bc_dds_problem
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/TextureRevamp/crates'
count=0
def check(ok,why):
    global count
    assert ok,why
    count+=1
def mesh(path):return oms.MeshSerializer(io.BytesIO(path.read_bytes())).read()
def weights(sub):return [(b.vertex_index,b.bone_index,b.weight) for b in sub.bone_assignments()]
receipt=json.loads((REF/'build.json').read_text())
members={x['source'].replace('\\','/'):x['runtime'] for x in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
original=mesh(REF/'abstor.mesh');textures=[]
for file,digest in receipt['stock'].items():check(hashlib.sha256((REF/file).read_bytes()).hexdigest()==digest,'crate source pin: '+file)
for file,digest in receipt['masters'].items():check(hashlib.sha256((REF/file).read_bytes()).hexdigest()==digest,'faction master receipt: '+file)
for name,faction in receipt['factions'].items():
    odf=ROOT/'ODF'/(name+'.odf');text=odf.read_text()
    check(f'baseName = "{name}"' in text and 'classLabel = "i76building"' in text,'independent native storage ODF: '+faction)
    check(f'unitName = "{faction} Storage"' in text,'faction-specific UI label: '+faction)
    for ext in ('sdf','skeleton'):
        path=ROOT/'Assets/Models'/(name+'.'+ext)
        check(path.read_bytes()==(REF/('abstor.'+ext)).read_bytes(),'stock native parts/collision and rig unchanged: '+name)
        check(members.get(path.relative_to(ROOT).as_posix())==path.name,'native resource shipped')
    path=ROOT/'Assets/Models'/(name+'.mesh');model=mesh(path)
    check(model.skeleton_name==name+'.skeleton','independent skeleton resource')
    check(len(model.submesh_list)==len(original.submesh_list),'stock submesh count')
    for src,dst in zip(original.submesh_list,model.submesh_list):
        check(dst.material_name==name,'unique active faction material')
        check(bytes(src.get_index_buffer())==bytes(dst.get_index_buffer()),'stock index order/winding')
        check(src.vertex_data.vertex_count==dst.vertex_data.vertex_count,'stock vertex count')
        check([vars(e) for e in src.vertex_data.vertex_declaration.vertex_element_list]==[vars(e) for e in dst.vertex_data.vertex_declaration.vertex_element_list],'stock vertex layout')
        check(all(bytes(vb.buffer)==bytes(dst.vertex_data.get_vertex_buffer(i).buffer) for i,vb in src.vertex_data.vertex_buffer_map.items()),'stock position/normal/UV/tangent bytes')
        check(weights(src)==weights(dst),'stock bone weights')
    check(vars(model.aabb)==vars(original.aabb) and model.bound_radius==original.bound_radius,'stock bounds')
    mat=ROOT/'Materials'/(name+'.material');text=mat.read_text()
    check(f'material {name} : CR_BZBase' in text,'owned enhanced/fallback material parent')
    for suffix in ('d','e'):
        filename=name+'_'+suffix+'.dds';p=ROOT/'Assets/Textures'/filename
        check(filename in text,'own map actually selected')
        check(hashlib.sha256(p.read_bytes()).hexdigest()==receipt['files'][filename]['sha256'],'crate map receipt')
        check(bc_dds_problem(p.read_bytes(),1280) is None,'crate full legacy-header mip chain')
        check(members.get(p.relative_to(ROOT).as_posix())==p.name,'crate map shipping membership')
    with Image.open(ROOT/'Assets/Textures'/(name+'_d.dds')) as im:
        textures.append(hashlib.sha256(im.tobytes()).hexdigest())
        # A generated UV atlas can silently shift the indicator even if its
        # silhouette looks plausible. Require a real red lamp at the stock UV.
        a=np.asarray(im.convert('RGB'),dtype=float)
        lamp=a[768:845,845:998]
        red=(lamp[:,:,0]>150)&(lamp[:,:,0]>lamp[:,:,1]*2)&(lamp[:,:,0]>lamp[:,:,2]*2)
        check(red.mean()>.15,'retained red status lamp occupies its original UV region: '+name)
    with Image.open(ROOT/'Assets/Textures'/(name+'_e.dds')) as im:
        a=np.asarray(im.convert('RGB'));outside=a.copy();outside[768:871,832:1012]=0
        check(a.max()>100 and outside.max()<20,'emission restricted to original status lamp, not painted emblems')
    for p in (odf,path,mat):check(members.get(p.relative_to(ROOT).as_posix())==p.name,'independent crate asset shipping membership')
check(len(set(textures))==4,'all four faction diffuse atlases are distinct')
for old,new in (('abstor','crstns'),('bbstor','crstbd')):
    text=(ROOT/'Materials'/(old+'.material')).read_text()
    check(new+'_d.dds' in text and new+'_e.dds' in text,'existing faction storage is branded too: '+old)
print(f'Faction storage: {count} checks passed')
