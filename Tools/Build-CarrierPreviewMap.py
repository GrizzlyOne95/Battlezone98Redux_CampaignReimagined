"""Create an isolated misn06 preview map; never alter the campaign map.

python Tools/Build-CarrierPreviewMap.py <override-folder>
"""
from pathlib import Path
import argparse
import re

ROOT=Path(__file__).resolve().parents[1]

def build(output):
    source=ROOT/'Missions/misn06.bzn'
    target=output/'misn06.bzn'
    assert target.resolve()!=source.resolve(),'preview must stay outside the campaign map'
    text=source.read_bytes().decode('latin1').replace('\r\n','\n')
    blocks=text.split('[GameObject]\n')
    index,fixture=next((i,b) for i,b in enumerate(blocks) if 'label = sblpad0_i76building\n' in b)
    serial=int(re.search(r'^seq_count \[1\] =\n(\d+)',blocks[0],re.M)[1])
    for key,value in [('PrjID','crncarr'),('team','0'),('perceivedTeam','0'),('curHealth','0'),('maxHealth','0'),('seqno',str(serial)),('seqNo',str(serial))]:
        fixture,n=re.subn(r'^'+key+r' \[1\] =\n[^\n]+',key+' [1] =\n'+value,fixture,count=1,flags=re.M)
        assert n==1,key
    fixture=fixture.replace('label = sblpad0_i76building\n','label = cr_carrier_preview\n',1)
    used={int(v,16) for v in re.findall(r'^obj_addr = ([0-9A-Fa-f]+)',text,re.M)}
    address=0x4CA1
    while address in used:address+=1
    fixture=re.sub(r'^obj_addr = \w+',f'obj_addr = {address:08X}',fixture,count=1,flags=re.M)
    position=(1700,650,100900)
    for i,axis in enumerate(('right','up','front')):
        for j,c in enumerate('xyz'):
            fixture=re.sub(r'(^  '+axis+'_'+c+r' \[1\] =\n)[^\n]+',lambda m:m[1]+str(int(i==j)),fixture,count=1,flags=re.M)
    for c,value in zip('xyz',position):
        fixture=re.sub(r'(^  posit_'+c+r' \[1\] =\n)[^\n]+',lambda m:m[1]+str(value),fixture,count=1,flags=re.M)
    vector=''.join(f'  {c} [1] =\n{v}\n' for c,v in zip('xyz',position))
    fixture=re.sub(r'(^pos \[1\] =\n)(?:  [xyz] \[1\] =\n[^\n]+\n){3}',lambda m:m[1]+vector,fixture,flags=re.M)
    for key in ('v','omega','Accel'):
        fixture=re.sub(r'(^ '+key+r' \[1\] =\n)(?:  [xyz] \[1\] =\n[^\n]+\n){3}',
            lambda m:m[1]+''.join(f'  {c} [1] =\n0\n' for c in 'xyz'),fixture,count=1,flags=re.M)
    blocks.insert(index+1,fixture)
    for key,value in [('seq_count',serial+1),('size',len(blocks)-1)]:
        blocks[0]=re.sub(r'(^'+key+r' \[1\] =\n)\d+',lambda m:m[1]+str(value),blocks[0],count=1,flags=re.M)
    output.mkdir(parents=True,exist_ok=True)
    target.write_bytes('[GameObject]\n'.join(blocks).replace('\n','\r\n').encode('latin1'))
    print('Preview-only carrier preplaced at',position,'in',target)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path)
    build(p.parse_args().output)
