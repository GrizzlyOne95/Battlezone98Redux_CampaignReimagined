"""Route existing faction ODFs through canonical faction render basenames.

Only baseName changes. Explicit source snapshots preserve every gameplay field;
canonical mesh/native aliases reuse the reviewed faction models and textures.
Run after Build-FactionNavPickups.py and Build-FactionStorage.py.
"""
from pathlib import Path
import argparse,hashlib,io,json,re,shutil,sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh_serializer as oms
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/TextureRevamp/integration'
NAV=ROOT/'References/TextureRevamp/nav-pickups'
FACTIONS={'ns':('a','abstor','crstns'),'bd':('b','bbstor','crstbd'),
          'cc':('s','sbstor','crstcc'),'cr':('c','cbstor','crstcr')}
FAMILIES={'apcamr':'crnv','apammo':'cram','aprepa':'crhp','apcann':'crwc','aprock':'crwr','apmort':'crwm','apspec':'crws'}
BASE=re.compile(r'(?mi)^(\s*baseName\s*=\s*)"([^"]+)"')
def canonical(family,code):return FACTIONS[code][0]+family[1:]
def replace(text,model):
    if BASE.search(text):return BASE.sub(lambda m:m[1]+'"'+model+'"',text,count=1)
    return re.sub(r'(?mi)^(\[GameObjectClass\]\s*)$',lambda m:m[1]+'\nbaseName = "'+model+'"',text,count=1)
def capture():
    assert not (REF/'manifest.json').exists(),'Integration baseline already captured'
    REF.mkdir(parents=True,exist_ok=True);(REF/'original').mkdir(exist_ok=True)
    aliases={};targets={};nav=json.loads((NAV/'build.json').read_text())
    for code,(prefix,storage,crate) in FACTIONS.items():
        for family,stem in FAMILIES.items():aliases[canonical(family,code)]=dict(source=stem+code,kind='pickup',faction=code,extensions=['mesh','vdf','skeleton'])
        aliases[storage]=dict(source=crate,kind='storage',faction=code,extensions=['mesh','sdf','skeleton'])
    for alias,record in aliases.items():
        for ext in record['extensions']:
            assert not (ROOT/'Assets/Models'/(alias+'.'+ext)).exists(),'Existing model alias requires review: '+alias+'.'+ext
    def add(path,code,family=None,storage=False,new_template=None):
        text=(ROOT/new_template).read_text() if new_template else path.read_text()
        model=FACTIONS[code][1] if storage else canonical(family,code)
        snapshot=REF/'original'/path.name;snapshot.write_text(text,newline='\n')
        targets[path.name]=dict(model=model,faction=code,sourceSha256=hashlib.sha256(snapshot.read_bytes()).hexdigest(),created=bool(new_template),template=new_template)
    by_prefix={record[0]:code for code,record in FACTIONS.items()}
    for path in sorted((ROOT/'ODF').glob('*.odf')):
        if not re.match(r'^[absc]p',path.stem):continue
        text=path.read_text();match=BASE.search(text)
        if match and match[2] in FAMILIES:add(path,by_prefix[path.stem[0]],match[2])
    for name,record in nav['odfs'].items():
        code=next(code for code,value in {'ns':'NSDF','bd':'Black Dog','cc':'CCA','cr':'CRA'}.items() if value==record['faction'])
        family=nav['models'][record['model']]['source'];add(ROOT/'ODF'/(name+'.odf'),code,family)
    for code,(_,name,crate) in FACTIONS.items():
        path=ROOT/'ODF'/(name+'.odf')
        add(path,code,storage=True,new_template=None if path.exists() else 'ODF/'+crate+'.odf')
    if not (ROOT/'ODF/bpcamr.odf').exists():add(ROOT/'ODF/bpcamr.odf','bd','apcamr',new_template='ODF/bapcamr.odf')
    (REF/'manifest.json').write_text(json.dumps(dict(schema=1,aliases=aliases,odfs=targets),indent=2)+'\n',newline='\n')
    print(f'Captured {len(targets)} exact ODF baselines and {len(aliases)} canonical model aliases.')
def build():
    manifest=json.loads((REF/'manifest.json').read_text());files={}
    for name,record in manifest['aliases'].items():
        source=record['source'];model=oms.MeshSerializer(io.BytesIO((ROOT/'Assets/Models'/(source+'.mesh')).read_bytes())).read()
        model.skeleton_name=name+'.skeleton'
        stream=io.BytesIO();oms.MeshSerializer(stream).write(model)
        path=ROOT/'Assets/Models'/(name+'.mesh');path.write_bytes(stream.getvalue())
        for ext in record['extensions']:
            target=ROOT/'Assets/Models'/(name+'.'+ext)
            if ext!='mesh':shutil.copyfile(ROOT/'Assets/Models'/(source+'.'+ext),target)
            files[target.relative_to(ROOT).as_posix()]=hashlib.sha256(target.read_bytes()).hexdigest()
    for name,record in manifest['odfs'].items():
        snapshot=REF/'original'/name
        assert hashlib.sha256(snapshot.read_bytes()).hexdigest()==record['sourceSha256'],'ODF baseline modified: '+name
        original=snapshot.read_text();expected=replace(original,record['model'])
        path=ROOT/'ODF'/name
        if path.exists():assert path.read_text() in (original,expected),'Unrelated ODF edit: '+name
        path.write_text(expected,newline='\n')
        # Runtime ODF checkout EOL varies by host; pin normalized text, while
        # source snapshots above and binary models retain exact byte hashes.
        files[path.relative_to(ROOT).as_posix()]=hashlib.sha256(expected.encode()).hexdigest()
    (REF/'build.json').write_text(json.dumps(dict(schema=1,files=files,models=len(manifest['aliases']),odfs=len(manifest['odfs'])),indent=2)+'\n',newline='\n')
    print(f'Integrated {len(manifest["aliases"])} canonical faction models and {len(manifest["odfs"])} existing/new ODFs; all non-baseName settings retained.')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--capture',action='store_true');args=parser.parse_args()
    if args.capture:capture()
    build()
