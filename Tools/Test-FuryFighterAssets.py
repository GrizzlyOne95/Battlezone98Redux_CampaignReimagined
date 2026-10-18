"""Guard the restored fighter's native asset contract, balance and shipping."""
from pathlib import Path
from hashlib import sha256
import json,re,struct
ROOT=Path(__file__).resolve().parents[1]
ORIGINAL=ROOT/'References/FuryFighter/original'
ASSETS=ROOT/'Assets/ModelFixes'
checks=0
def check(ok,why):
    global checks
    assert ok,why
    checks+=1
def namespaced(data):return re.sub(b'hra11',b'cfr11',data,flags=re.I)
files={p.name.lower():p for p in ORIGINAL.iterdir()}
manifest=json.loads((ORIGINAL.parent/'provenance.json').read_text())
for name,digest in manifest['original_sha256'].items():
    check(sha256(files[name.lower()].read_bytes()).hexdigest()==digest,'source asset provenance '+name)
check('ISDF' not in manifest['source_folder'],'owner-selected standalone source')
for old,new in [('hvraz.vdf','crfraz.vdf'),('hvraz.skeleton','crfraz.skeleton')]:
    check(namespaced(files[old].read_bytes())==(ASSETS/new).read_bytes(),'native collision/animation bytes unchanged except part namespace')
for key,path in files.items():
    if key.endswith('.geo'):
        check(namespaced(path.read_bytes())==(ASSETS/('cfr11'+key[5:])).read_bytes(),'every legacy GEO companion is present and geometry unchanged: '+key)
vdf=(ASSETS/'crfraz.vdf').read_bytes()
check(vdf[:4]==b'BWD2' and struct.unpack_from('<I',vdf,104)[0]==12,'complete 12-part VDF')
for hp in (b'cfr11GC1',b'cfr11GC2'):
    check(hp in vdf,'original weapon hardpoint survives: '+str(hp))
def mesh_children(data):
    p=data.index(b'\n')+1
    check(struct.unpack_from('<H',data,p)[0]==0x3000,'Ogre root chunk')
    end=p+struct.unpack_from('<I',data,p+2)[0]
    flag=data[p+6:p+7];p+=7;out=[]
    while p<end:
        kind,length=struct.unpack_from('<HI',data,p)
        check(length>=6 and p+length<=end,'valid complete Ogre chunk')
        out.append((kind,data[p+6:p+length]));p+=length
    check(p==end,'mesh length covers all chunks')
    return flag,out,data[end:]
a,old,oldtail=mesh_children(files['hvraz.mesh'].read_bytes())
b,new,newtail=mesh_children((ASSETS/'crfraz.mesh').read_bytes())
check(a==b and oldtail==newtail and len(old)==len(new),'skeletal flag, chunk count and tail preserved')
for (kind,src),(kind2,dst) in zip(old,new):
    check(kind==kind2,'chunk identity retained')
    if kind in (0x4000,0x6000):
        srcname,srcbody=src.split(b'\n',1);dstname,dstbody=dst.split(b'\n',1)
        check(dstname==(b'crfraz' if kind==0x4000 else b'crfraz.skeleton'),'only intended material/skeleton resource is selected')
        check(namespaced(srcbody)==dstbody,'vertex/index/UV/normal/weight data are byte-identical')
    else:check(namespaced(src)==dst,'bounds and remaining mesh metadata are unchanged')
def odf(name):
    text=(ROOT/'ODF'/f'{name}.odf').read_text()
    return {m[1].lower():m[2].strip().strip('"') for m in re.finditer(r'(?m)^(\w+)\s*=\s*([^/\n]*)',text)}
craft=odf('crfraz');pulse=odf('crfp0');arc=odf('crfa0')
check(craft['basename']=='crfraz' and craft['classlabel']=='wingman','uses its own model and commandable hover process')
check(craft['pilotname']=='' and int(craft['pilotcost'])==0,'no human pilot ejects from alien hull')
check(int(craft['maxhealth'])==2400 and float(craft['velocforward'])==35,'lighter/faster balance baseline')
check(craft['weaponname1']=='crfpuls' and craft['weaponname2']=='crfarc' and craft['weaponmask']=='00011','both custom cannons enabled')
dps=float(pulse['damageballistic'])/float(odf('crfpuls')['shotdelay'])+float(arc['damageballistic'])/float(odf('crfarc')['shotdelay'])
check(abs(dps-210)<0.001,'combined sustained damage below stock 250 DPS Bolt Buddy')
check(float(pulse['shotSpeed'.lower()])*float(pulse['lifespan'])==180,'pulse maximum range 180 m')
check(float(arc['shotspeed'])*float(arc['lifespan'])==160,'arc maximum range 160 m')
dds=(ROOT/'Assets/Textures/crfraz_d.dds').read_bytes()
check(dds[:4]==b'DDS ' and struct.unpack_from('<II',dds,12)==(1024,1024) and struct.unpack_from('<I',dds,80)[0]==0x41 and struct.unpack_from('<I',dds,88)[0]==32,'shipped RGBA8 atlas with engine-generated mipmaps')
lock=json.loads((ROOT/'Shipping/shipping.lock.json').read_text())
members={x['source'].replace('\\','/'):x['runtime'] for x in lock['files']}
shipped=[p for p in ASSETS.iterdir() if p.name.startswith(('crfraz.','cfr11'))]
shipped+=[ROOT/'Assets/Textures/crfraz_d.dds',ROOT/'Materials/crfraz.material',ROOT/'Scripts/CRFuryRoster.lua']
shipped+=[ROOT/'ODF'/f'{n}.odf' for n in ('crfraz','crfpuls','crfp0','crfarc','crfa0')]
for p in shipped:check(members.get(p.relative_to(ROOT).as_posix())==p.name,'shipping admission: '+p.name)
print(f'Fury fighter assets: {checks} checks passed')
