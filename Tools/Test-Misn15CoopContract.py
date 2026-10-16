"""Campaign binding, authored team isolation, rescue fixtures and MAT/HG2 water contract."""
from pathlib import Path
import importlib.util
import json
import re

ROOT=Path(__file__).resolve().parents[1]
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,ROOT/path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

raw=(ROOT/'Missions/misn15.bzn').read_bytes()
text=raw.decode('latin-1').replace('\r\n','\n')
assert b'\n' not in raw.replace(b'\r\n',b''), 'native BZN line endings'
assert 'TerrainName = misn15\n' in text and 'name = MultSTMission\n' in text
blocks=text.split('[GameObject]\n')[1:]
assert len(blocks)==60
labels={};starts=[]
for block in blocks:
    label=re.search(r'^label = (.*)$',block,re.M)[1]
    odf=re.search(r'^PrjID \[1\] =\n(.*)$',block,re.M)[1]
    team=int(re.search(r'^team \[1\] =\n(\d+)$',block,re.M)[1])
    if label.startswith('cr15_') or label.startswith('svtank') or label=='svapc0_apc':
        assert team==7 and 'perceivedTeam [1] =\n7\n' in block
    if odf=='pspwn_1':starts.append(team)
    else:assert team not in (2,3,4,5,6), 'guest and enemy slots stay clear'
    if not odf.startswith('sfield'):assert label not in labels, 'unique object identity: '+label
    labels[label]=odf
assert sorted(starts)==[1,2,3,4]
for label,odf in {'cr15_nw_scav':'avscav','cr15_nw_apc':'avapc','cr15_nw_turret':'avturr',
                  'cr15_ne_scav1':'avscav','cr15_ne_scav2':'avscav','cr15_ne_artillery':'avartl'}.items():
    assert labels[label]==odf
for ext in ('trn','hg2','mat','lgt'):
    runtime=(ROOT/'Missions'/f'misn15.{ext}').read_bytes()
    source=(ROOT/'Missions'/f'misn15b.{ext}').read_bytes()
    # TRN is text: Git normalizes the new runtime stem but retains CRLF in
    # the older source blob. Windows checkout conversion hid that difference.
    # Binary terrain companions must still be byte-identical on every OS.
    if ext == 'trn':
        runtime=runtime.replace(b'\r\n',b'\n')
        source=source.replace(b'\r\n',b'\n')
    assert runtime==source, 'misn15b terrain companion content: '+ext
for name in ('tank_path','alien_path','deny1','deny2','rescue_cam1','rescue_cam2'):
    assert f'label = {name}\n' in text
assert not re.search(r'^label = path_1$',text,re.M)
for path in text.split('[AiPath]\n')[1:]:
    size=int(re.search(r'^size \[1\] =\n(\d+)$',path,re.M)[1])
    name=re.search(r'^label = (.*)$',path,re.M)
    assert size==len(name[1].encode('latin-1')) if name else size==0, 'native path label allocation size'
assert '[MISSION14]' in (ROOT/'Config/crcampgn.ini').read_text()
assert 'voice = "misn1500.wav"' in (ROOT/'Config/crcampgn.ini').read_text()
assert len((ROOT/'misn15.des').read_bytes())<=300
assert (ROOT/'Assets/Graphics/misn15.bmp').read_bytes()[:2]==b'BM'
assert (ROOT/'Missions/misn15.vxt').read_bytes()==(ROOT/'Missions/misn14.vxt').read_bytes()

# Independent reconstruction from the shipping MAT and HG2, including inland
# plateaus and mixed shore tiles that must never become water.
sites=load('titan_sites','Tools/Build-TitanSites.py')
venus=load('venus_sites','Tools/Build-VenusSites.py')
surface=load('methane_surface','Tools/Build-MethaneSurface.py')
data=surface.read_sites(ROOT/'Scripts/CRTitanSites15.lua')
mask=set()
for row,runs in data['rowsData'].items():
    for start,length in runs:
        mask.update((row,col) for col in range(start,start+length))
_,hg2=sites.read_hg2((ROOT/'Missions/misn15.hg2').read_bytes())
lo,hi=sites.cell_extremes(hg2,256)
mat=venus.unzone((ROOT/'Missions/misn15.mat').read_bytes(),4,4)
assert len(mask)>2000
for row,col in mask:
    word=mat[row][col]
    assert (word>>12)==0 and ((word>>8)&15)==0, 'no rock/transition wet cells'
    assert lo[row][col]>=378 and hi[row][col]<=384, 'water uses the lower 38.1 m basin'
assert not any((row,col) in mask for row in range(256) for col in range(256) if lo[row][col]>=650), 'dry plateaus excluded'
assert 'CR/Titan/Methane15' in (ROOT/'Materials/cr_methane.material').read_text()
assert 'cr_titan15_wet.png' in (ROOT/'Materials/cr_methane.material').read_text()
assert 'CRTitanSites15' in (ROOT/'Scripts/CRMisn15.lua').read_text()
members={e['source'].replace('\\','/'):e['runtime'] for e in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
for path in ('Scripts/CRMisn15.lua','Scripts/CRTitanSites15.lua','Missions/misn15.bzn','Missions/misn15.trn',
             'Missions/misn15.hg2','Missions/misn15.mat','Missions/misn15.lgt','Missions/misn15.vxt',
             'Config/misn15.ini','misn15.des','Assets/Textures/cr_titan15_wet.png',
             'Assets/Audio/misn1506.wav','Assets/Audio/misn1508.wav','Assets/Audio/misn1512.wav',
             'Text/misn15l2.des','Text/misn15l3.des'):
    assert members.get(path)==Path(path).name, 'shipping membership: '+path
print('misn15 map, co-op teams, waiting rescues, campaign and MAT/HG2 methane contract passed')
