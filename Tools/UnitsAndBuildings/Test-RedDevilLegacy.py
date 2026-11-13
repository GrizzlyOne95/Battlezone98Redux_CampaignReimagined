"""Texture-only Red Devil art, source, rig and package regression contracts."""
from pathlib import Path
import hashlib,io,json,re,sys,importlib.util
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent.parent))
from bcdds import bc_dds_problem
from bzmodellibs import ogremesh_serializer as oms
ROOT=Path(__file__).resolve().parents[2];REF=ROOT/'References/RedDevilLegacy';count=0
spec=importlib.util.spec_from_file_location('combat',ROOT/'Tools/Weapons/Build-CombatPresentation.py');combat=importlib.util.module_from_spec(spec);spec.loader.exec_module(combat)
# The hardpoint mount kit appends one bvrdev_hpmount submesh and material block; everything else stays byte-identical.
spec=importlib.util.spec_from_file_location('mounts',ROOT/'Tools/CockpitsAndRigs/Build-HardpointMounts.py');mounts=importlib.util.module_from_spec(spec);spec.loader.exec_module(mounts)

def check(ok,message):
    global count
    assert ok,message
    count+=1

def sha(path):return hashlib.sha256((path).read_bytes()).hexdigest()

sources=json.loads((REF/'sources.json').read_text())
for name,record in sources.items():
    path=REF/name
    if record.get('normalizedText'):
        baseline=json.loads(path.read_text())['text']
        check(hashlib.sha256(baseline.encode()).hexdigest()==record['sha256'],'normalized original text: '+name)
        current=(ROOT/record['source']).read_text()
        if record['source'].endswith('.odf'):
            check(combat.gameplay_digest(combat.builder.odf_lines(current))==combat.gameplay_digest(combat.builder.odf_lines(baseline)),'retained gameplay definition: '+record['source'])
        else:
            check(re.sub(r'(?m)^[ \t]*set_texture_alias ACTMap \S+\n','',mounts.without_mount_material(current,'bvrdev'))==baseline,'retained material definition: '+record['source'])
    else:
        check(sha(path)==record['sha256'],'captured source: '+name)
        if record['source'].startswith('Assets/ModelFixes/'):
            # The shipped mesh also carries the weapon-rig layer (re-cut, re-ordered gun vertices), so it is compared by submesh/material list; a byte-exact comparison needs the pre-rig stage.
            shipped=[s.material_name for s in oms.MeshSerializer(io.BytesIO((ROOT/record['source']).read_bytes())).read().submesh_list if s.material_name!='bvrdev_hpmount']
            check(shipped==[s.material_name for s in oms.MeshSerializer(io.BytesIO(path.read_bytes())).read().submesh_list],'cockpit-glass mesh keeps every original submesh/material, plus only the hardpoint mount')
recipe=json.loads((REF/'recipe.json').read_text());receipt=json.loads((REF/'build.json').read_text())
master=REF/recipe['master'];target=ROOT/recipe['output']
check(sha(master)==receipt['masterSha256'],'selected built-in ImageGen master pinned')
check(recipe['output']==receipt['output'],'exact existing diffuse resource reused')
check(target.stat().st_size==receipt['bytes'],'texture size receipt')
check(bc_dds_problem((target).read_bytes(),*recipe['size']) is None,'BC1 legacy header and complete offline mip chain')
with Image.open(master) as im:
    check(list(im.size)==receipt['authoredSize'],'real authored source dimensions, not alleged upscale detail')
    check(max(recipe['size'][i]/im.size[i] for i in (0,1))<1.15,'near-authored shipping size')
    expected=np.array(im.convert('RGB').resize(tuple(recipe['size']),Image.Resampling.LANCZOS)).astype(float)
with Image.open(target) as im:
    check(list(im.size)==recipe['size'],'runtime dimensions')
    actual=np.array(im.convert('RGB')).astype(float)
check(np.abs(actual-expected).mean()<4,'compiled diffuse stays within BC1 error')
mesh=oms.MeshSerializer(io.BytesIO(((ROOT/recipe['mesh'])).read_bytes())).read()
check([s.material_name for s in mesh.submesh_list]==['bvrdev','bvrdev01','CRWX_CockpitGlass','bvrdev_hpmount'],'existing exterior/cockpit/weather-glass submesh bindings, then the hardpoint mount')
check(mesh.skeleton_name.replace('_recoil.skeleton','.skeleton')=='bvrdev.skeleton','stock skeleton resource identity')
lock=json.loads((ROOT/'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'));members=[r for r in lock['files'] if r['source'].replace('\\','/')==recipe['output']]
check(len(members)==1 and members[0]['runtime']==target.name,'existing diffuse ships once, no duplicate atlas alias')
material=(ROOT/recipe['material']).read_text()
check('DiffuseMap bvrdev_D.dds' in material and 'EmissiveMap bvrdev_E.dds' in material,'existing diffuse/emissive aliases retained')
check('NormalMap bvrdev_N.dds' in material and 'SpecularMap bvrdev_S.dds' in material,'existing N/S retained, no diffuse-derived relief')
check(not (ROOT/'Assets/Textures/crvrdev_e.dds').exists(),'no redundant emissive atlas')
print(f'Red Devil legacy pass: {count} checks passed')
