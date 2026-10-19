"""Author raw/processed crystal cargo and a refinery/converter receiving station.

Original geometry, with matching legacy collision and Ogre bind poses. The
station placements and playable substitution mechanic are CR reconstruction.
Run after Build-Misn17CoopMap and before Build-Misn17Jungle.
"""
from pathlib import Path
import argparse
import copy
import io
import math
import struct
import sys
import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parent))
ROOT=Path(__file__).resolve().parents[1]


def build(game,toolbox):
    sys.path.insert(0,str(toolbox))
    from battlezone.archives.zfs import ZFSArchive
    from battlezone.meshes.legacy import _SDF_RECORD,read_geo,read_sdf
    from bzmodellibs import geo,geo_serializer
    from battlezone.meshes.legacy_port import build_port,PortOptions
    from battlezone.meshes.ogre import write_mesh
    from battlezone.meshes.ogre_skeleton import write_skeleton
    from battlezone.bzn.bz1 import read_bzn,write_bzn
    from battlezone.terrain.hg2 import read_hg2
    arc=ZFSArchive(game/'bzone.zfs');template=arc.read('obdata.sdf');prefix=template[:template.index(b'SGEO')]
    out=ROOT/'Assets/Models';out.mkdir(exist_ok=True)
    def prism(vertices,faces,cx,cz,r,low,high,n=6,tip=None):
        start=len(vertices)
        vertices.extend([(cx+r*math.cos(a*math.tau/n),low,cz+r*math.sin(a*math.tau/n)) for a in range(n)])
        vertices.extend([(cx+r*.65*math.cos(a*math.tau/n),high,cz+r*.65*math.sin(a*math.tau/n)) for a in range(n)])
        faces.append([start+i for i in range(n-1,-1,-1)])
        for i in range(n):faces.append([start+i,start+(i+1)%n,start+n+(i+1)%n,start+n+i])
        if tip is None:faces.append([start+n+i for i in range(n)])
        else:
            vertices.append((cx,tip,cz));t=len(vertices)-1
            for i in range(n):faces.append([start+n+i,start+n+(i+1)%n,t])
    materials=[]
    for name in ('c17raw','c17proc','c17ref','c17slot'):
        v=[];f=[]
        if name=='c17raw':
            prism(v,f,0,0,.9,0,2.1,5,3.5);prism(v,f,1,.3,.6,0,1,5,2.1);prism(v,f,-.7,.65,.55,0,.8,5,1.8)
        elif name=='c17proc':prism(v,f,0,0,1.1,0,2.4,6,3.3)
        else:
            prism(v,f,0,0,5,0,1.2,8)
            for a in range(4):prism(v,f,3.5*math.cos(a*math.pi/2),3.5*math.sin(a*math.pi/2),.55,1.2,4,4)
            prism(v,f,0,0,2.2,1.2,1.7 if name=='c17slot' else 3.0,8)
        p=np.array(v,dtype=float);lo=p.min(0);hi=p.max(0);center=(lo+hi)/2;half=(hi-lo)/2
        g=geo.Geo();g.name=name;g.vert_count=len(v)
        g.vertex_pos_buffer=p.astype('<f4');g.vertex_normal_buffer=np.zeros_like(p,dtype='<f4')
        for i,face in enumerate(f):
            q=p[face];normal=np.cross(q[1]-q[0],q[2]-q[0]);normal/=np.linalg.norm(normal)
            # Native GEO uses inward plane normals, as the stock port codec expects.
            gf=g.create_face(i);gf.color=geo.Color3(255,255,255)
            gf.plane=geo.SurfacePlane(geo.Vector3(*(-normal)),float(normal@q[0]))
            gf.shade_type=gf.texture_type=0;gf.texture_name=name+'.map'
            for j in face:gf.create_face_node(j,j,geo.UV(float(p[j][0]*.2+.5),float(p[j][1]*.25)))
        raw=io.BytesIO();geo_serializer.GeoSerializer(raw).write(g);raw=raw.getvalue()
        (out/(name+'.geo')).write_bytes(raw);read_geo(raw)
        # TODO(toolkit gap): SDFSerializer.write always emits 3 EXIT chunks (this file has 2) and cannot omit them.
        rec=_SDF_RECORD.pack(name.encode(),1,0,0,0,1,0,0,0,1,0,0,0,b'WORLD',*center,float(np.linalg.norm(half)),*half,60,0,0,0,0,0,0)
        null=_SDF_RECORD.pack(b'NULL',*([0]*12),b'NULL',*([0]*7),0,0,0,0,0,0,0)
        body=struct.pack('<i',1)+rec+null*5
        sdf=prefix+struct.pack('<4si',b'SGEO',8+len(body))+body+struct.pack('<4si',b'EXIT',8)*2
        (out/(name+'.sdf')).write_bytes(sdf);read_sdf(sdf)
        result=build_port(sdf,'sdf',name,lambda n: (out/n).read_bytes(),PortOptions(normals='flat',texture_format='none'))
        for s in result.mesh.submeshes:s.material='CR17/'+name
        write_mesh(result.mesh,out/(name+'.mesh'));(out/(name+'.skeleton')).write_bytes(write_skeleton(result.skeleton))
        cargo=name in ('c17raw','c17proc')
        (ROOT/'ODF'/(name+'.odf')).write_text('[GameObjectClass]\nbaseName = "'+name+'"\nclassLabel = "'+('artifact' if cargo else 'i76building')+'"\nscrapCost = 0\nscrapValue = 0\nmaxHealth = '+('2500' if cargo else '10000')+'\nmaxAmmo = 0\nunitName = "'+{'c17raw':'Unprocessed Crystal','c17proc':'Processed Crystal','c17ref':'Crystal Refinery','c17slot':'Power Converter Feed'}[name]+'"\n')
        rgb='0.16 0.42 0.25' if name=='c17raw' else ('0.2 0.75 1' if name=='c17proc' else '0.14 0.2 0.18')
        materials.append('''material CR17/%s : BZBase
{
    set_texture_alias DiffuseMap white.png
    set_texture_alias NormalMap cr17_flat.dds
    set_texture_alias SpecularMap white.png
    set_texture_alias EmissiveMap white.png
    set $diffuse "%s"
    set $ambient "%s"
    set $specular "0.8 0.9 1"
    set $shininess "96"
    set $glow "%s"
}'''%(name,rgb,rgb,'0.01 0.08 0.12' if cargo else '0 0 0'))
    (ROOT/'Materials/cr17_crystal.material').write_text('import * from "BZBase.material"\n\n'+'\n\n'.join(materials)+'\n')
    b=read_bzn(ROOT/'Missions/misn17.bzn')
    b.objects=[o for o in b.objects if not o.label.startswith(('cr17_raw','cr17_processed','cr17_refinery','cr17_receiver','cr17_tug'))]
    _,heights=read_hg2(ROOT/'Missions/misn17.hg2')
    stock=read_bzn(arc.read('misn10.bzn'))
    artifact=next(o for o in stock.objects if o.prjid=='hvsrb')
    tug=next(o for o in read_bzn(arc.read('misn11.bzn')).objects if o.prjid=='avhaul')
    building=next(o for o in b.objects if o.prjid=='hbfact')
    seq=max(o.fields.get('seqno',o.fields.get('seqNo')).value for o in b.objects)+1
    paths={p['label'].value.decode():p['points'].value[0] for p in b.paths if 'label' in p}
    specs=[('c17raw',f'cr17_raw{i}',paths[f'rawcrys{i}spawn'][0]-180,paths[f'rawcrys{i}spawn'][1],0) for i in range(1,6)]
    specs += [('c17proc','cr17_processed',3501,101095,0),('c17ref','cr17_refinery',3501,101095,0),
              ('c17slot','cr17_receiver',3320,101380,6),('avhaul','cr17_tug',1840,99330,1)]
    for odf,label,x,z,team in specs:
        o=copy.deepcopy(tug if odf=='avhaul' else artifact if odf in ('c17raw','c17proc') else building)
        y=float(heights[round((z-97280)/5),round(x/5)])*.1+(3.1 if odf=='c17proc' else 0)
        for k,val in [('PrjID',odf.encode()),('label',label.encode()),('team',team),('perceivedTeam',team),
                      ('seqno',seq),('seqNo',seq),('obj_addr',0x50000+seq),('isUser',0),
                      ('curHealth',2500 if odf in ('c17raw','c17proc') else 10000),
                      ('maxHealth',2500 if odf in ('c17raw','c17proc') else 10000),('healthRatio',1.)]:
            if k in o.fields:o.fields[k].value=val
        o.fields['transform'].value=(1,0,0,0,1,0,0,0,1,x,y,z)
        for k in ('pos','pos2'):
            if k in o.fields:o.fields[k].value=[(x,y,z)]
        for k,field in o.fields.items():
            if k in ('v','omega','Accel'):field.value=[(0.,0.,0.)]
            if k in ('what','where','who','priority') or k.endswith(('.what','.where','.who','.priority')):
                field.value=bytes(4) if isinstance(field.value,bytes) else 0
        b.objects.append(o);seq+=1
    b.header['seq_count'].value=seq;b.header['#objects'].value=len(b.objects)
    (ROOT/'Missions/misn17.bzn').write_bytes(write_bzn(b,2016,binary=False,preserve_spelling=False))
    en=ZFSArchive(game/'bzone_en.zfs')
    for i in (2,5,6,7,8,9):
        name=f'misn17{i:02}.wav';(ROOT/'Assets/Audio'/name).write_bytes(en.read(name))
    print('Built four custom crystal/logistics models, nine map props and six stock VO files')


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--game',required=True,type=Path)
    ap.add_argument('--toolbox',type=Path,default=ROOT.parent/'Battlezone98_Modding_Toolbox')
    a=ap.parse_args();build(a.game,a.toolbox)
