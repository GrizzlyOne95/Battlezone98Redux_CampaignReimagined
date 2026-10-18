"""Build an Achilles jungle prototype from CR terrain and ISDFC surface assets.

Never writes to ISDFC. Meshes, materials, programs and texture references get
CR17 names. Placement uses the original tree painting, protected mission sites
and a fixed seed. The new western cascade is a CR addition, not recovered content.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
import numpy as np

ROOT=Path(__file__).resolve().parents[1]


def blocks(text,keyword):
    out={}
    for m in re.finditer(r'(?m)^'+keyword+r'\s+(\S+)[^\n{]*\s*\{',text):
        depth=1;i=m.end()
        while depth:
            depth+=(text[i]=='{')-(text[i]=='}');i+=1
        out[m[1]]=text[m.start():i]
    return out


def build(src,toolbox):
    sys.path.insert(0,str(toolbox))
    from battlezone.meshes import ogre
    from battlezone.bzn.bz1 import read_bzn,write_bzn
    from battlezone.meshes.legacy import read_sdf
    from battlezone.terrain.hg2 import read_hg2,write_hg2
    from battlezone.terrain.mat import read_mat
    consumed={}
    def read(name):
        p=src/name;key=name
        if not p.exists() and name.lower() in ('flat_n.dds','black.dds'):
            p=src.parent.parent/'BZ_ASSETS/pc/textures/DIFF'/name.lower();key='stock/'+name.lower()
        data=p.read_bytes();consumed[key]=hashlib.sha256(data).hexdigest();return data
    def text(name):return read(name).decode('utf-8-sig').replace('\r\n','\n')
    def emit(folder,name,data):
        p=ROOT/folder/name;p.parent.mkdir(parents=True,exist_ok=True)
        if isinstance(data,str):p.write_text(data,newline='\n')
        else:p.write_bytes(data)
    def rename(s):
        return s.replace('ISDFC','CR17').replace('isdfc_surface','cr17_surface').replace(
            'FoliageAtlas_Mire.dds','cr17_foliage.dds').replace('FoliageAtlas_Mire','Foliage').replace(
            'flat_N.dds','cr17_flat.dds').replace('black.dds','cr17_black.dds')
    materials=blocks(text('isdfc_surface.material'),'material')
    chosen=['ISDFC/NoShadowCaster','ISDFC/Water','ISDFC/CutoutCaster/FoliageAtlas_Mire','ISDFC/Cutout']
    mat='\n\n'.join(materials[n] for n in chosen)+'\n'
    programs={}
    ptext=text('isdfc_surface.program')
    for k in ('vertex_program','fragment_program'):programs.update(blocks(ptext,k))
    needed=set(re.findall(r'(?:vertex|fragment)_program_ref\s+(\S+)',mat))
    while True:
        more={d for n in needed if n in programs for d in re.findall(r'\bdelegate\s+(\S+)',programs[n])}
        if more<=needed:break
        needed|=more
    emit('Materials','cr17_surface.material',rename(mat))
    emit('Shaders','cr17_surface.program',rename('\n\n'.join(programs[n] for n in sorted(needed) if n in programs)+'\n'))
    for n in ('isdfc_surface.hlsl','isdfc_surface-vertex.glsl','isdfc_surface-fragment.glsl'):
        emit('Shaders',n.replace('isdfc','cr17'),rename(text(n)))
    for old,new in [('FoliageAtlas_Mire.dds','cr17_foliage.dds'),('flat_N.dds','cr17_flat.dds'),
                    ('black.dds','cr17_black.dds'),('water256.dds','cr17_water.dds'),
                    ('motrnk01.dds','cr17_bark.dds'),('motrnk01_n.dds','cr17_bark_n.dds'),
                    ('motrnk01_s.dds','cr17_bark_s.dds')]:emit('Assets/Textures',new,read(old))
    children='''import * from "cr17_surface.material"
import * from "BZBase.material"
material CR17/Leaves : CR17/Cutout
{
    set_texture_alias DiffuseMap cr17_foliage.dds
    set_texture_alias NormalMap cr17_flat.dds
    set_texture_alias SpecularMap cr17_black.dds
    set_texture_alias EmissiveMap cr17_black.dds
    set $cutoutParams "0.45 0.5 0.6 2048"
    set $specular "0.1 0.1 0.1"
    set $shininess "16"
    set $caster "CR17/CutoutCaster/Foliage"
}
material CR17/Bark : BZBase
{
    set_texture_alias DiffuseMap cr17_bark.dds
    set_texture_alias NormalMap cr17_bark_n.dds
    set_texture_alias SpecularMap cr17_bark_s.dds
    set_texture_alias EmissiveMap cr17_black.dds
    set $specular "0.12 0.12 0.12"
    set $shininess "16"
}
material CR17/River : CR17/Water
{
    set_texture_alias DiffuseMap cr17_water.dds
    set $waterScroll "0 -0.13 0.014 -0.08"
    set $waterColour "0.24 0.42 0.36 0"
    set $waterSurface "0.65 0.96 0.04 0.3"
    set $skyColour "0.38 0.48 0.56 0.6"
}
'''
    emit('Materials','cr17_jungle.material',children)
    mesh_names=['miretre1','miretre2','mire_ferna','mire_fernb','mire_frond','mire_reeds']
    tree_assets={}
    for n in mesh_names:
        m=ogre.read_mesh(read(n+'.mesh'))
        for s in m.submeshes:s.material='CR17/Bark' if 'motrnk' in s.material else 'CR17/Leaves'
        target='cr17_'+n
        if n.startswith('miretre'):
            target='c17tree'+n[-1]
            oldprefix='tr111' if n.endswith('1') else 'tr311'
            newprefix='j1711' if n.endswith('1') else 'j1721'
            def ns(data):return data.replace(oldprefix.encode(),newprefix.encode())
            sdf=read(n+'.sdf');emit('Assets/Models',target+'.sdf',ns(sdf))
            for part in read_sdf(sdf).parts:
                if part.band==0 and part.name!='NULL':
                    emit('Assets/Models',part.name.replace(oldprefix,newprefix)+'.geo',ns(read(part.name+'.geo')))
            # Native solid building + EXU PlantClass is the working Redux plant
            # contract used by ISDFC. Keep the original GEO collision surfaces.
            emit('ODF',target+'.odf','''[GameObjectClass]
baseName = "%s"
classLabel = "i76building2"
scrapCost = 0
scrapValue = 0
maxHealth = 2500
maxAmmo = 0
unitName = "Jungle Tree"
collisionRadius = 5
explosionName = "xplnxpl"
[PlantClass]
isPlant = 1
dropScrap = 0
'''%target)
            tree_assets[n]=target
        if m.skeleton:
            old=m.skeleton;m.skeleton=target+'.skeleton'
            data=read(old)
            if n.startswith('miretre'):data=ns(data)
            emit('Assets/Models',m.skeleton,data)
        emit('Assets/Models',target+'.mesh',ogre.write_mesh(m))
    # Fresh original heightmap makes rebuilding idempotent.
    original=subprocess.check_output(['git','show','ce18e89:Missions/misn17.hg2'],cwd=ROOT)
    emit('Missions','misn17.hg2',original)
    header,h=read_hg2(ROOT/'Missions/misn17.hg2');ground=h.astype(float)*.1
    mat=read_mat(ROOT/'Missions/misn17.mat',4,4)
    bzn=read_bzn(ROOT/'Missions/misn17.bzn')
    bzn.objects=[o for o in bzn.objects if not o.label.startswith('cr17_tree')]
    guards=np.array([o.fields['transform'].value[9::2] for o in bzn.objects if o.prjid!='sfield'])
    def height(x,z):return float(ground[round((z-97280)/5),round(x/5)])
    def protected(x,z,r=30):return np.any((guards[:,0]-x)**2+(guards[:,1]-z)**2<r*r)
    route=[(1440,99480),(1450,99520),(1470,99570),(1490,99620),(1500,99660),(1525,99720),(1550,99780)]
    # Dense samples along an existing descending ravine; the water surface
    # follows its gradient and the bed is cut one metre below it.
    line=[];length=0
    for i,(a,b) in enumerate(zip(route,route[1:])):
        n=math.ceil(math.dist(a,b)/5)
        for j in range(n):
            t=j/n;x=a[0]+(b[0]-a[0])*t;z=a[1]+(b[1]-a[1])*t
            line.append((x,height(x,z)+.15,z))
    line.append((route[-1][0],height(*route[-1])+.15,route[-1][1]))
    bed=ground.copy();verts=[];indices=[]
    for i,(x,y,z) in enumerate(line):
        a=line[max(0,i-1)];b=line[min(len(line)-1,i+1)]
        dx,dz=b[0]-a[0],b[2]-a[2];l=math.hypot(dx,dz);nx,nz=-dz/l,dx/l
        if i:length+=math.dist(line[i-1],line[i])
        normal=np.cross((dx,b[1]-a[1],-dz),(nx,0,-nz))
        if normal[1]<0:normal=-normal
        normal=normal/np.linalg.norm(normal)
        for sign,u in [(-1,0),(1,1)]:
            verts.append((x+nx*7*sign-1500,y,-(z+nz*7*sign-99600),*normal,u,length/18))
        if i:indices.extend([2*i-2,2*i,2*i-1,2*i-1,2*i,2*i+1])
        for iz in range(round((z-97280)/5)-5,round((z-97280)/5)+6):
            for ix in range(round(x/5)-5,round(x/5)+6):
                xx,zz=ix*5,iz*5+97280;d=math.hypot(xx-x,zz-z)
                if d<15 and not protected(xx,zz):
                    target=y-1.1;weight=min(1,max(0,(15-d)/8))
                    bed[iz,ix]=min(bed[iz,ix],ground[iz,ix]*(1-weight)+target*weight)
    write_hg2(ROOT/'Missions/misn17.hg2',np.rint(bed*10).astype(np.uint16),header.zones_x,header.zones_z)
    # POSITION/NORMAL/TEXCOORD0 only, matching the surface shader inputs.
    import struct
    geo=ogre.Geometry(vertex_count=len(verts),elements=[ogre.VertexElement(0,2,1,0,0),
        ogre.VertexElement(0,2,4,12,0),ogre.VertexElement(0,1,7,24,0)],
        buffers={0:ogre.VertexBuffer(0,32,b''.join(struct.pack('<8f',*v) for v in verts),0)})
    mesh=ogre.OgreMesh(version='[MeshSerializer_v1.100]',endian='<',
        submeshes=[ogre.SubMesh(material='CR17/River',uses_shared_vertices=False,indices=indices,
                              use32bit=False,operation=4,geometry=geo)])
    emit('Assets/Models','cr17_river.mesh',ogre.write_mesh(mesh))
    rng=np.random.default_rng(17017);layers=[];trees=[]
    for name,spacing,scale in [('miretre1',34,(.65,1.15)),('miretre2',39,(.8,1.3)),
                               ('mire_ferna',13,(.7,1.4)),('mire_fernb',15,(.8,1.4)),('mire_frond',14,(.9,1.8))]:
        instances=[]
        for z in np.arange(98430,101740,spacing):
            for x in np.arange(780,3640,spacing):
                x=float(x+rng.uniform(-spacing*.4,spacing*.4));z1=float(z+rng.uniform(-spacing*.4,spacing*.4))
                tile=int(mat[int((z1-97280)/20),int(x/20)]);typ=tile>>12
                y=height(x,z1);ix,iz=round(x/5),round((z1-97280)/5)
                slope=math.hypot(ground[iz,ix+1]-ground[iz,ix-1],ground[iz+1,ix]-ground[iz-1,ix])/10
                if typ!=1 or slope>.5 or protected(x,z1,45) or rng.random()<.2:continue
                if min(math.hypot(x-a,z1-b) for a,b in route)<24:continue
                instances.append([round(x,2),round(y-.08,2),round(z1,2),round(float(rng.uniform(0,math.tau)),3),round(float(rng.uniform(*scale)),3)])
        if name in tree_assets:
            trees.extend((tree_assets[name],p) for p in instances)
        else:
            # Ground cover is visual only; large trees are solid native plants.
            for i in range(0,len(instances),256):layers.append({'mesh':'cr17_'+name+'.mesh','instances':instances[i:i+256]})
    original_trees=read_bzn(src/'isdfms10.bzn',odf_dirs=[src])
    tree_template=next(o for o in original_trees.objects if o.prjid=='miretre1')
    consumed['isdfms10.bzn']=hashlib.sha256((src/'isdfms10.bzn').read_bytes()).hexdigest()
    # Keep native loading below the lobby keepalive budget. Initial sightlines
    # get authored plants; the host streams the remaining solid plants only
    # beyond every player's fog horizon and outside shared cameras.
    chosen=set(sorted(range(len(trees)),key=lambda i:math.hypot(trees[i][1][0]-1813,trees[i][1][2]-99354))[:64])
    for tx,tz in [(1378,100523),(2020,100536),(932,100020),(1976,100608),(3462,100070),(3148,98653),(3047,99488),(1490,99620)]:
        chosen.update(sorted(range(len(trees)),key=lambda i:math.hypot(trees[i][1][0]-tx,trees[i][1][2]-tz))[:8])
    seq=max(o.fields.get('seqno',o.fields.get('seqNo')).value for o in bzn.objects)+1
    for i,(odf,p) in enumerate(trees,1):
        if i-1 not in chosen:continue
        o=copy.deepcopy(tree_template);x,y,z,yaw,_=p;c,s=math.cos(yaw),math.sin(yaw)
        for k,v in [('PrjID',odf.encode()),('label',f'cr17_tree{i}'.encode()),('team',0),('perceivedTeam',0),
                    ('seqno',seq),('seqNo',seq),('obj_addr',0x20000+seq),('isUser',0),
                    ('curHealth',2500),('maxHealth',2500),('healthRatio',1.)]:
            if k in o.fields:o.fields[k].value=v
        o.fields['transform'].value=(c,0,-s,0,1,0,s,0,c,x,y,z)
        for k in ('pos','pos2'):
            if k in o.fields:o.fields[k].value=[(x,y,z)]
        bzn.objects.append(o);seq+=1
    bzn.header['seq_count'].value=seq;bzn.header['#objects'].value=len(bzn.objects)
    emit('Missions','misn17.bzn',write_bzn(bzn,2016,binary=False,preserve_spelling=False))
    data={'layers':layers,'water':{'mesh':'cr17_river.mesh','position':[1500,0,99600]},
          'trees':[{'odf':odf,'position':p[:3],'label':f'cr17_tree{i+1}','preplaced':int(i in chosen)} for i,(odf,p) in enumerate(trees)],
          'cascade':list(line[len(line)//3]),'river':route,'height_samples_changed':int(np.count_nonzero(h!=np.rint(bed*10)))}
    # JSON's arrays are rendered as Lua tables; no parser dependency in game.
    def lua(v):
        if isinstance(v,dict):return '{'+','.join(k+'='+lua(x) for k,x in v.items())+'}'
        if isinstance(v,(list,tuple)):return '{'+','.join(lua(x) for x in v)+'}'
        return json.dumps(v)
    emit('Scripts','CRJungle17Sites.lua','-- Generated by Build-Misn17Jungle.py\nreturn '+lua(data)+'\n')
    emit('References/Misn17Jungle','source-assets.json',json.dumps({'source':'ISDF_Chronicles',
        'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=src,text=True).strip(),
        'sha256':consumed,'layers':len(layers),'plants':sum(len(l['instances']) for l in layers),'solid_trees':len(trees),'preplaced_trees':len(chosen),
        'height_samples_changed':data['height_samples_changed']},indent=2)+'\n')
    print('Built jungle prototype:',len(layers),'batches,',sum(len(l['instances']) for l in layers),'plants;',data['height_samples_changed'],'channel samples')


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--isdfc',type=Path,required=True)
    ap.add_argument('--toolbox',type=Path,default=ROOT.parent/'Battlezone98_Modding_Toolbox')
    a=ap.parse_args();build(a.isdfc,a.toolbox)
