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
import os
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


# Canopy parts are CLASS_ID_NONCOLLIDABLE (0x37, as stock wat11pn1). Otherwise
# every BuildObject welds the 1-2k-vertex canopy GEO into a polygon soup
# (O(n^2), ~15 ms per tree) and 3,000 streamed trees stall the opening minutes.
# The trunk parts keep their GEO collision.
CANOPY_PARTS={b'j1711lea',b'j1721lef'}


def noncollidable_canopy(sdf):
    data=bytearray(sdf);i=data.find(b'SGEO');count=int.from_bytes(data[i+8:i+12],'little')
    hit=0
    for k in range(count*6):
        rec=i+12+k*120
        if bytes(data[rec:rec+8]).rstrip(b'\0') in CANOPY_PARTS:
            data[rec+92:rec+96]=(0x37).to_bytes(4,'little');hit+=1
    assert hit,'no canopy part in the SDF'
    return bytes(data)


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
    # Ogre binds a unified program's default_params against delegates already
    # parsed, so each family's delegates must precede its unified block.
    order=sorted((n for n in needed if n in programs),
        key=lambda n:(re.sub(r'_(GLSL|HLSL4?)$','',n),'delegate' in programs[n],n))
    emit('Shaders','cr17_surface.program',rename('\n\n'.join(programs[n] for n in order)+'\n'))
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
material CR17/Streams : CR17/Water
{
    set_texture_alias DiffuseMap cr17_water.dds
    set $waterScroll "0 -0.22 0.02 -0.14"
    set $waterColour "0.26 0.42 0.34 0"
    set $waterSurface "0.6 0.95 0.04 0.4"
    set $skyColour "0.38 0.48 0.56 0.6"
}
material CR17/Pools : CR17/Water
{
    set_texture_alias DiffuseMap cr17_water.dds
    set $waterScroll "0.004 0.003 -0.003 0.002"
    set $waterColour "0.12 0.22 0.18 0"
    set $waterSurface "0.6 0.97 0.03 0"
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
            sdf=read(n+'.sdf');emit('Assets/Models',target+'.sdf',noncollidable_canopy(ns(sdf)))
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
    # Terrain water inside the play area. A priority flood finds closed basins
    # (standing pools); D8 flow on the filled surface traces streams down the
    # existing gradients until they join, reach a pool or meet the river.
    import heapq
    r0,r1,c0,c1=230,893,156,729
    sub=bed[r0:r1,c0:c1];R,C=sub.shape
    X=(np.arange(C)+c0)*5.;Z=(np.arange(R)+r0)*5.+97280;XX,ZZ=np.meshgrid(X,Z)
    guard=np.zeros(sub.shape,bool)
    for gx,gz in guards:guard|=(XX-gx)**2+(ZZ-gz)**2<20*20
    near_river=np.zeros(sub.shape,bool)
    for x,_,z in line:near_river|=(XX-x)**2+(ZZ-z)**2<22*22
    N8=[(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]
    def flood(h):
        fill=h.copy();seen=np.zeros(h.shape,bool);seen[[0,-1],:]=True;seen[:,[0,-1]]=True
        pq=[(fill[r,c],r,c) for r,c in zip(*np.nonzero(seen))];heapq.heapify(pq)
        while pq:
            v,r,c=heapq.heappop(pq)
            for dr,dc in N8:
                rr,cc=r+dr,c+dc
                if 0<=rr<R and 0<=cc<C and not seen[rr,cc]:
                    seen[rr,cc]=True;fill[rr,cc]=max(h[rr,cc],v+1e-3)
                    heapq.heappush(pq,(fill[rr,cc],rr,cc))
        return fill
    fill=flood(sub)
    # Streams route over a blurred surface: the 0.1 m height quantization
    # leaves flats on which D8 draws ruler-straight diagonals.
    k=np.exp(-.5*(np.arange(-9,10)/3.)**2);k/=k.sum()
    soft=np.pad(sub,9,mode='edge')
    soft=np.apply_along_axis(lambda v:np.convolve(v,k,'valid'),0,soft)
    soft=np.apply_along_axis(lambda v:np.convolve(v,k,'valid'),1,soft)
    flow=flood(soft)
    pool_cells=np.zeros(sub.shape,bool);pool_list=[];pool_label=np.full(sub.shape,-1)
    pool_view=([],0)  # largest pool, a camera target for native captures
    deep=(fill-sub>.6)&~near_river
    for r,c in zip(*np.nonzero(deep)):
        if pool_label[r,c]>=0:continue
        comp=[(r,c)];pool_label[r,c]=len(pool_list);k=0
        while k<len(comp):
            a,b=comp[k];k+=1
            for dr,dc in N8:
                rr,cc=a+dr,b+dc
                if 0<=rr<R and 0<=cc<C and deep[rr,cc] and pool_label[rr,cc]<0:
                    pool_label[rr,cc]=len(pool_list);comp.append((rr,cc))
        cells=tuple(np.array(comp).T)
        if len(comp)<8 or guard[cells].any():pool_list.append(None);continue
        level=min(float(fill[cells].max()),float(sub[cells].min())+2.)
        # Broad flat basins become a pond of at most ~1500 cells, not a lake.
        if len(comp)>1500:level=min(level,float(np.sort(sub[cells])[1499]))
        pool_list.append(level)
        if len(comp)>len(pool_view[0]):pool_view=(comp,level)
    def quad(vs,ix,a,b,c,d):
        # Faces up (+Y) whatever the corner order.
        p=[np.array(vs[i][:3]) for i in (a,b,c)]
        if np.cross(p[1]-p[0],p[2]-p[0])[1]<0:b,d=d,b
        ix.extend([a,b,c,a,c,d])
    pverts=[];pindices=[]
    for r in range(1,R-1):
        for c in range(1,C-1):
            lab=pool_label[r-1:r+2,c-1:c+2];levels=[pool_list[l] for l in lab.ravel() if l>=0 and pool_list[l] is not None]
            if not levels:continue
            level=max(levels)
            if sub[r,c]>level+.2:continue
            # Dilated by one cell so the surface tucks into the banks.
            pool_cells[r,c]=True;x,z=X[c],Z[r];base=len(pverts)
            for ox,oz in [(-2.5,-2.5),(2.5,-2.5),(2.5,2.5),(-2.5,2.5)]:
                pverts.append((x+ox-1500,level,-(z+oz-99600),0,1,0,(x+ox)/18,(z+oz)/18))
            quad(pverts,pindices,base,base+1,base+2,base+3)
    # D8 receivers and accumulation on the filled, blurred surface.
    recv=np.full(sub.shape+(2,),-1);drop=np.zeros(sub.shape)
    for dr,dc in N8:
        sh=np.full(sub.shape,np.inf)
        sh[max(0,-dr):R-max(0,dr),max(0,-dc):C-max(0,dc)]=flow[max(0,dr):R+min(0,dr),max(0,dc):C+min(0,dc)]
        g=(flow-sh)/math.hypot(dr,dc);better=g>drop
        drop[better]=g[better];recv[better]=(dr,dc)
    acc=np.ones(sub.shape)
    for i in np.argsort(-flow,axis=None):
        r,c=divmod(int(i),C)
        if drop[r,c]>0:acc[r+recv[r,c,0],c+recv[r,c,1]]+=acc[r,c]
    T=900;channel=acc>=T
    heads=[(r,c) for r,c in zip(*np.nonzero(channel)) if not any(
        0<=r-dr<R and 0<=c-dc<C and channel[r-dr,c-dc] and tuple(recv[r-dr,c-dc])==(dr,dc) and drop[r-dr,c-dc]>0 for dr,dc in N8)]
    heads.sort(key=lambda p:-flow[p])
    visited=np.zeros(sub.shape,bool);paths=[]
    def stop(r,c):return r in(0,R-1) or c in(0,C-1) or near_river[r,c]
    for r,c in heads:
        path=[]
        while True:
            if stop(r,c) or guard[r,c]:break
            if pool_cells[r,c]:
                # Pass under a pool and resume from its outlet.
                if len(path)>1:paths.append(path)
                path=[]
            else:
                path.append((r,c,acc[r,c]))
                if visited[r,c]:break
                visited[r,c]=True
            # Filled flats carry only the 1e-3 epsilon and draw ruler-straight lines.
            if drop[r,c]<.0004:break
            dr,dc=recv[r,c];r,c=r+dr,c+dc
        if len(path)>1:paths.append(path)
    sverts=[];sindices=[];stream_points=[];stream_view=(0,None)
    for path in paths:
        pts=np.array([(X[c],Z[r]) for r,c,_ in path])
        if np.sum(np.hypot(*np.diff(pts,axis=0).T))<120:continue
        if len(path)>stream_view[0]:
            r,c,_=path[len(path)//2];stream_view=(len(path),(float(X[c]),float(sub[r,c]),float(Z[r])))
        if len(pts)>2:pts[1:-1]=(pts[:-2]+pts[1:-1]*2+pts[2:])/4
        y=[];prev=math.inf
        for (x,z),(r,c,_) in zip(pts,path):prev=min(prev,float(sub[r,c])+.15);y.append(prev)
        half=[min(3.2,1.4+.9*math.sqrt(a/T)) for *_,a in path]
        base=len(sverts);length=0
        for i,((x,z),yy,w) in enumerate(zip(pts,y,half)):
            a=pts[max(0,i-1)];b=pts[min(len(pts)-1,i+1)]
            dx,dz=b-a;l=math.hypot(dx,dz) or 1;nx,nz=-dz/l,dx/l
            if i:length+=math.hypot(*(pts[i]-pts[i-1]))
            n=np.cross((dx,y[min(len(y)-1,i+1)]-y[max(0,i-1)],-dz),(nx,0,-nz))
            n=n/(np.linalg.norm(n) or 1)
            if n[1]<0:n=-n
            for sign,u in [(-1,0),(1,1)]:
                sverts.append((x+nx*w*sign-1500,yy,-(z+nz*w*sign-99600),*n,u,length/10))
            if i:quad(sverts,sindices,base+2*i-2,base+2*i-1,base+2*i+1,base+2*i)
            stream_points.append((x,yy,z,w))
            ext=w+3
            for iz in range(round((z-97280)/5)-2,round((z-97280)/5)+3):
                for ix in range(round(x/5)-2,round(x/5)+3):
                    xx,zz=ix*5,iz*5+97280;d=math.hypot(xx-x,zz-z)
                    if d<ext and not guard[iz-r0,ix-c0]:
                        weight=min(1,max(0,(ext-d)/2.5))
                        bed[iz,ix]=min(bed[iz,ix],bed[iz,ix]*(1-weight)+(yy-.6)*weight)
    wet=np.zeros(ground.shape,bool);wet[r0:r1,c0:c1]=pool_cells
    for x,_,z,w in stream_points:
        iz,ix=round((z-97280)/5),round(x/5);wet[iz-2:iz+3,ix-2:ix+3]=True
    if os.environ.get('CR17_WATER_PREVIEW'):
        # Top-down review image: shaded relief, pools cyan, streams blue, guards red.
        from PIL import Image
        g=np.gradient(sub);shade=np.clip(128+40*(g[1]-g[0]),0,255)
        img=np.stack([shade]*3,-1).astype(np.uint8)
        img[pool_cells]=(40,200,220);img[guard]=img[guard]//2+(100,0,0)
        for x,_,z,w in stream_points:img[round((z-97280)/5)-r0,round(x/5)-c0]=(20,60,255)
        for x,_,z in line:img[round((z-97280)/5)-r0,round(x/5)-c0]=(255,255,0)
        Image.fromarray(img[::-1]).resize((C*2,R*2),Image.NEAREST).save(os.environ['CR17_WATER_PREVIEW'])
    write_hg2(ROOT/'Missions/misn17.hg2',np.rint(bed*10).astype(np.uint16),header.zones_x,header.zones_z)
    # POSITION/NORMAL/TEXCOORD0 only, matching the surface shader inputs.
    import struct
    def water_mesh(file,material,verts,indices):
        geo=ogre.Geometry(vertex_count=len(verts),elements=[ogre.VertexElement(0,2,1,0,0),
            ogre.VertexElement(0,2,4,12,0),ogre.VertexElement(0,1,7,24,0)],
            buffers={0:ogre.VertexBuffer(0,32,b''.join(struct.pack('<8f',*v) for v in verts),0)})
        mesh=ogre.OgreMesh(version='[MeshSerializer_v1.100]',endian='<',
            submeshes=[ogre.SubMesh(material=material,uses_shared_vertices=False,indices=indices,
                                  use32bit=len(verts)>65535,operation=4,geometry=geo)])
        emit('Assets/Models',file,ogre.write_mesh(mesh))
    water_mesh('cr17_river.mesh','CR17/River',verts,indices)
    assert sverts and pverts,'terrain produced no streams or pools'
    water_mesh('cr17_streams.mesh','CR17/Streams',sverts,sindices)
    water_mesh('cr17_pools.mesh','CR17/Pools',pverts,pindices)
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
                if min(math.hypot(x-a,z1-b) for a,b in route)<24 or wet[iz,ix]:continue
                instances.append([round(x,2),round(y-.08,2),round(z1,2),round(float(rng.uniform(0,math.tau)),3),round(float(rng.uniform(*scale)),3)])
        if name in tree_assets:
            trees.extend((tree_assets[name],p) for p in instances)
        else:
            # Ground cover is visual only; large trees are solid native plants.
            # One layer per mesh per 384 m tile, aligned with the StaticGeometry
            # regions (192 m from origin 2048,99328). Row-order 256-instance
            # strips each crossed ~30 regions: ~3,700 region batches per frame.
            tiles={}
            for p in instances:tiles.setdefault((math.floor((p[0]-2048)/384),math.floor((p[2]-99328)/384)),[]).append(p)
            for k in sorted(tiles):layers.append({'mesh':'cr17_'+name+'.mesh','instances':tiles[k]})
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
    comp,level=pool_view
    data={'layers':layers,'water':{'mesh':'cr17_river.mesh','position':[1500,0,99600]},
          'streams':{'mesh':'cr17_streams.mesh','position':[1500,0,99600],
                     'view':[round(v,2) for v in stream_view[1]]},
          'pools':{'mesh':'cr17_pools.mesh','position':[1500,0,99600],
                   'view':[round(float(np.mean([X[c] for _,c in comp])),2),round(level,2),
                           round(float(np.mean([Z[r] for r,_ in comp])),2)]},
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
        'height_samples_changed':data['height_samples_changed'],'stream_paths':len(paths),
        'stream_points':len(stream_points),'pool_cells':int(pool_cells.sum())},indent=2)+'\n')
    print('Built jungle prototype:',len(layers),'batches,',sum(len(l['instances']) for l in layers),'plants;',data['height_samples_changed'],'channel samples;',
          len(paths),'stream paths,',len(stream_points),'stream points,',int(pool_cells.sum()),'pool cells,',
          sum(p is not None for p in pool_list),'pools')


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--isdfc',type=Path,required=True)
    ap.add_argument('--toolbox',type=Path,default=ROOT.parent/'Battlezone98_Modding_Toolbox')
    a=ap.parse_args();build(a.isdfc,a.toolbox)
