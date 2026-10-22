"""Canonical faction aliases, whole-ODF preservation and shipping coverage."""
from pathlib import Path
import hashlib,importlib.util,io,json,sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh_serializer as oms
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/TextureRevamp/integration'
spec=importlib.util.spec_from_file_location('integrate',ROOT/'Tools/Build-FactionPickupIntegration.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
manifest=json.loads((REF/'manifest.json').read_text());receipt=json.loads((REF/'build.json').read_text())
members={r['source'].replace('\\','/'):r['runtime'] for r in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']};count=0
def check(ok,why):
    global count
    assert ok,why
    count+=1
def read(path):return oms.MeshSerializer(io.BytesIO(path.read_bytes())).read()
check(len(manifest['aliases'])==receipt['models']==32,'seven pickups and one storage alias per faction')
check(len(manifest['odfs'])==receipt['odfs']==361,'all existing, namespaced and newly requested ODF routes')
for name,row in manifest['aliases'].items():
    source=ROOT/'Assets/Models'/(row['source']+'.mesh');target=ROOT/'Assets/Models'/(name+'.mesh')
    model=read(source);model.skeleton_name=name+'.skeleton';stream=io.BytesIO();oms.MeshSerializer(stream).write(model)
    check(target.read_bytes()==stream.getvalue(),'alias changes only skeleton resource name: '+name)
    for ext in row['extensions']:
        path=ROOT/'Assets/Models'/(name+'.'+ext)
        check(members.get(path.relative_to(ROOT).as_posix())==path.name,'alias resource ships: '+path.name)
        if ext!='mesh':check(path.read_bytes()==(ROOT/'Assets/Models'/(row['source']+'.'+ext)).read_bytes(),'native resource remains byte-identical: '+path.name)
for name,row in manifest['odfs'].items():
    baseline=REF/'original'/name;path=ROOT/'ODF'/name
    check(hashlib.sha256(baseline.read_bytes()).hexdigest()==row['sourceSha256'],'exact pre-integration ODF baseline: '+name)
    check(path.read_text()==build.replace(baseline.read_text(),row['model']),'every non-baseName byte/field retained: '+name)
    check(row['model'] in manifest['aliases'],'ODF selects a resolved canonical alias: '+name)
    check(members.get(path.relative_to(ROOT).as_posix())==path.name,'routed ODF ships: '+name)
for relative,digest in receipt['files'].items():
    path=ROOT/relative;payload=path.read_text().encode() if path.suffix=='.odf' else path.read_bytes()
    check(hashlib.sha256(payload).hexdigest()==digest,'integration receipt (normalized runtime ODF EOL): '+relative)
for name,model in {'spblst.odf':'spcann','spcamr.odf':'spcamr','bpcamr.odf':'bpcamr','sbstor.odf':'sbstor','cbstor.odf':'cbstor'}.items():
    check(manifest['odfs'][name]['model']==model,'explicit owner routing: '+name)
print(f'Faction pickup integration: {count} checks passed')
