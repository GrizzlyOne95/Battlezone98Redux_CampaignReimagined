"""Build the shared Mission 16 map and off-boundary Fury evacuation pad.

Inputs are CR's amended misn16b terrain and copied-building art baseline.
The original amended companions stay untouched; only the runtime misn16
terrain gets the small pad edit. Model templates come from stock Mission 18.
"""
from pathlib import Path
import argparse
import copy
import importlib.util
import json
import re
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
PAD = (3900.0, 100000.0)


def build(game, toolbox):
    sys.path.insert(0, str(toolbox))
    from battlezone.archives.zfs import ZFSArchive
    from battlezone.bzn.bz1 import read_bzn, write_bzn
    from battlezone.terrain.hg2 import read_hg2, write_hg2
    from battlezone.terrain.mat import read_mat, write_mat, encode_entry
    spec = importlib.util.spec_from_file_location('coopmap', ROOT/'Tools/Build-CoopMap.py')
    base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
    base.ENEMY_TEAM = 6
    base.CLEAR_COMMANDS.add('misn16')
    base.STRIP_UNNAMED_PATHS.add('misn16')
    source = (ROOT/'Missions/misn16b.bzn').read_text(encoding='latin-1')
    source = source.replace('msn_filename = misn16b.bzn', 'msn_filename = misn16.bzn')
    source = source.replace('TerrainName = misn16b.bzn', 'TerrainName = misn16.bzn')
    blocks=source.split('[GameObject]\n')
    for i in range(1,len(blocks)):
        if re.search(r'(?m)^team \[1\] =\n2$',blocks[i]):
            blocks[i]=blocks[i].replace('perceivedTeam [1] =\n-1\n','perceivedTeam [1] =\n2\n',1)
    source='[GameObject]\n'.join(blocks)
    result = read_bzn(base.build(source, 'misn16').encode('latin-1'), odf_dirs=[ROOT/'ODF'])
    arc = ZFSArchive(game/'bzone.zfs')
    original18 = read_bzn(arc.read('misn18.bzn'))
    hull = next(o for o in original18.objects if o.prjid == 'hbtran00')
    engines = [o for o in original18.objects if o.prjid == 'hbtrn200']
    templates = {o.prjid: o for o in result.objects}
    serial = result.header['seq_count'].value
    pad_x, pad_z = PAD
    header, height = read_hg2(ROOT/'Missions/misn16b.hg2')
    original_height = height.copy()
    # 5 m HG2 samples; flatten a 120 m square with a 20 m blended shoulder.
    zz, xx = np.indices(height.shape)
    distance = np.maximum(abs(xx*5-pad_x), abs(zz*5+97280-pad_z))
    weight = np.clip((80-distance)/20, 0, 1)
    height = np.rint(height*(1-weight)+50*weight).astype(np.uint16)
    write_hg2(ROOT/'Missions/misn16.hg2', height, header.zones_x, header.zones_z)
    materials = read_mat(ROOT/'Missions/misn16b.mat',4,4)
    original_mat = materials.copy()
    for z in range(materials.shape[0]):
        for x in range(materials.shape[1]):
            wx, wz = x*20+10, z*20+97290
            pad = abs(wx-pad_x)<=60 and abs(wz-pad_z)<=60
            apron = 3660<=wx<3840 and abs(wz-pad_z)<=20
            if pad or apron:
                materials[z,x] = encode_entry(1,1,variant=(x+z)%2)
    write_mat(ROOT/'Missions/misn16.mat',materials,4,4)
    trn = (ROOT/'Missions/misn16b.trn').read_bytes()
    trn += b'\r\n; CR evacuation pad: stock Titan base tiles, A/B atlas variants.\r\n[TextureType1]\r\nSolidA0=ti11sa0.map\r\nSolidB0=ti11sb0.map\r\n'
    (ROOT/'Missions/misn16.trn').write_bytes(trn)
    (ROOT/'Missions/misn16.lgt').write_bytes((ROOT/'Missions/misn16b.lgt').read_bytes())

    def ground(x,z):
        return float(height[round((z-97280)/5),round(x/5)])*.1

    def add(template, label, x,y,z, team=6, rotation=None):
        nonlocal serial
        obj = copy.deepcopy(template)
        for key,val in [('seqno',serial),('seqNo',serial),('obj_addr',0x5000+serial),
                        ('label',label.encode()),('team',team),('perceivedTeam',team),('isUser',0)]:
            if key in obj.fields: obj.fields[key].value=val
        transform = list(obj.fields['transform'].value)
        if rotation is not None: transform[:9]=rotation
        transform[9:]=[x,y,z]; obj.fields['transform'].value=tuple(transform)
        for key in ('pos','pos2'):
            if key in obj.fields: obj.fields[key].value=[(x,y,z)]
        for key,f in obj.fields.items():
            if key in ('v','omega','Accel'): f.value=[(0.,0.,0.)]
            if key.endswith(('.what','.who','.where','.priority')) or key in ('what','where','who','priority'):
                f.value=bytes(4) if isinstance(f.value,bytes) else 0
        result.objects.append(obj);serial+=1
        return obj

    # Retain Mission 18's proven relative engine arrangement and rotations.
    origin=hull.fields['transform'].value[9:]
    add(hull,'cr16_transport',pad_x,5.0,pad_z)
    for i,engine in enumerate(engines,1):
        t=engine.fields['transform'].value
        add(engine,'cr16_engine'+str(i),pad_x+t[9]-origin[0],5.0,pad_z+t[11]-origin[2])
    # Boarding target stays concealed inside the grounded hull; removed at launch.
    identity=(1.,0.,0.,0.,1.,0.,0.,0.,1.)
    add(templates['apcamr'],'cr16_pad_look',pad_x,35.,pad_z,0,identity)
    for i,(x,z) in enumerate(((3650.,100020.),(3680.,99980.)),1):
        add(templates['hvsat'],'cr16_evac'+str(i),x,ground(x,z)+1,z,6,identity)

    routes={
        'cr16_evac_route':[(3740,100050),(3820,100050),(3860,100050)],
        'cr16_board':[(3900,100060)],
        'cr16_evac_cam':[(3900,99900),(3900,99905),(3900,99910),(3900,99915)],
        'cr16_launch_cam':[(4000,99940),(4020,99980),(4010,100030)],
        'cr16_ally_a':[(1200,99460)],'cr16_ally_b':[(3700,100300)],
        'cr16_enemy_a':[(3650,98600)],'cr16_enemy_b':[(1250,100550)],
    }
    path_template=result.paths[0]
    for i,(label,points) in enumerate(routes.items(),1):
        path=copy.deepcopy(path_template)
        for key,val in [('label',label.encode()),('label.size',len(label)),
                        ('pointCount',len(points)),('points',points),('pathType',bytes(4)),('old_ptr',0x7000+i)]:
            if key in path: path[key].value=val
        result.paths.append(path)
    result.header['seq_count'].value=serial
    result.header['#objects'].value=len(result.objects)
    data=write_bzn(result,2016,binary=False,preserve_spelling=False)
    checked=read_bzn(data,odf_dirs=[ROOT/'ODF'])
    assert len(checked.objects)==145
    assert all(o.fields['team'].value not in (2,3,4) or o.prjid=='pspwn_1' for o in checked.objects)
    assert all(p['label.size'].value==len(p['label'].value) for p in checked.paths if 'label' in p)
    (ROOT/'Missions/misn16.bzn').write_bytes(data)
    summary={'pad':{'x':pad_x,'z':pad_z,'height':5,'width':120,'material':'Titan TI11SA0/TI11SB0'},
             'height_samples_changed':int(np.count_nonzero(height!=original_height)),
             'material_tiles_changed':int(np.count_nonzero(materials!=original_mat)),
             'objects':len(checked.objects),'paths':len(checked.paths),
             'outside_edge_x':3413.330078125,'scene_paths':routes}
    (ROOT/'References/Misn16Fury/scene-layout.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game',required=True,type=Path)
    parser.add_argument('--toolbox',type=Path,default=ROOT.parent/'Battlezone98_Modding_Toolbox')
    a=parser.parse_args();build(a.game,a.toolbox)
