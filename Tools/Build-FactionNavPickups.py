"""Independent faction beacons and pickup models with re-UV'd casing panels.

Stock VDF/skeletons stay byte-identical. The shared Ogre codec clones render
streams and repartitions existing triangles; it never creates collision or
changes geometry. ImageGen masters are offline inputs, never build-time calls.
"""
from pathlib import Path
import copy,hashlib,importlib.util,io,json,re,shutil,sys
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh as om,ogremesh_serializer as oms
from bcdds import save_bc
from poduv import full_uv,remesh,atlas_image
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/TextureRevamp/nav-pickups';SRC=REF/'original'
PODREF=ROOT/'References/TextureRevamp/pod-palette-v4'
ARTREF=ROOT/'References/TextureRevamp/nav-weapons-v4'
FACTIONS={'ns':('NSDF','n'),'bd':('Black Dog','b'),'cc':('CCA','s'),'cr':('CRA','c')}
DECOR={'ns':(35,225,255),'bd':(255,20,28),'cc':(255,115,8),'cr':(150,255,12)}
WEAPON_CORE=[.725,.45,.80,.555]
# The four quadrant accents remain independent of faction paint.
FAMILIES={'apcamr':('crnv',None),'apammo':('cram',(0,0)),'aprepa':('crhp',(1,0)),
          'apcann':('crwc',(0,1)),'aprock':('crwr',(0,1)),'apmort':('crwm',(0,1)),'apspec':('crws',(0,1))}
spec=importlib.util.spec_from_file_location('building_contract',ROOT/'Tools/Build-BuildingTexturePatches.py')
contract=importlib.util.module_from_spec(spec);spec.loader.exec_module(contract)

def read(path):return oms.MeshSerializer(io.BytesIO(path.read_bytes())).read()
def values(vd,semantic):
    el=vd.vertex_declaration.find_by_semantic(semantic);vb=vd.get_vertex_buffer(el.source)
    return np.ndarray((vd.vertex_count,el.get_type_count()),'<f4',buffer=vb.buffer,offset=el.offset,strides=(vb.vertex_size,4))

def geometry(mesh):
    record=contract.triangle_contract(mesh)
    record.pop('skeleton') # Resource is deliberately namespaced; rig bytes pinned separately.
    return record

def emblem_fits(uv,triangles,radius=.32):
    """Conservative circular emblem footprint must lie inside drawn triangles."""
    samples=[np.array([.5,.5])]
    for r in (.10,.22,radius):
        samples.extend(np.array([.5+np.cos(a)*r,.5+np.sin(a)*r]) for a in np.linspace(0,2*np.pi,48,endpoint=False))
    tri=uv[triangles]
    cross=lambda a,b:a[:,0]*b[:,1]-a[:,1]*b[:,0]
    for p in samples:
        signs=[cross(tri[:,(i+1)%3]-tri[:,i],p-tri[:,i]) for i in range(3)]
        inside=(np.minimum.reduce(signs)>=-1e-6)|(np.maximum.reduce(signs)<=1e-6)
        if not inside.any():return False
    return True

def panel_groups(sub,family):
    """Planar broad faces, not small fittings, warheads or underside triangles."""
    xyz=values(sub.vertex_data,om.VES.POSITION);indices=sub.index_array.reshape(-1,3)
    tri=xyz[indices];cross=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);length=np.linalg.norm(cross,axis=1)
    normal=cross/np.maximum(length[:,None],1e-12);area=length*.5
    supply=family in ('apammo','aprepa')
    mask=(area>area.max()*(.14 if supply else .18))
    if not supply:mask&=normal[:,1]>-.45
    if family=='apammo':mask&=tri[:,:,1].mean(1)<2.30 # Preserve the stock blue tip.
    if family=='aprepa':mask[[0,1,4,5]]=False # Keep the small top/bottom coupling caps.
    if family=='apspec':mask&=normal[:,1]>.2
    groups=[];tolerance=np.linalg.norm(xyz.max(0)-xyz.min(0))*.025
    for i in np.flatnonzero(mask):
        n=normal[i].astype(float);center=tri[i].mean(0)
        group=next((g for g in groups if np.dot(g['normal'],n)>.985 and abs(np.dot(g['normal'],center-g['center']))<tolerance),None)
        if group is None:
            group=dict(normal=n,center=center,triangles=[]);groups.append(group)
        group['triangles'].append(int(i))
    result=[]
    for group in groups:
        rows=group['triangles']
        if len(rows)<2 and family!='aprock' and not supply:continue
        n=group['normal'];n/=np.linalg.norm(n)
        up=np.array([0,1,0] if abs(n[1])<.9 else [0,0,-1],dtype=float)
        t=np.cross(up,n);t/=np.linalg.norm(t);b=np.cross(n,t)
        points=xyz[np.unique(indices[rows])]
        projected=np.column_stack((points@t,-points@b));lo=projected.min(0);hi=projected.max(0)
        if min(hi-lo)/max(hi-lo)<(.08 if supply else .36):continue
        result.append(dict(triangles=rows,t=t,b=b,lo=lo,hi=hi,normal=n,area=float(area[rows].sum())))
    assert result,'No broad, legible casing panels in '+family
    if family=='apspec':
        # The broad stock top is a ring with a central recess. A centered chart
        # hides its light in that recess; split only its UVs into four physical
        # rim sectors so the square optics are visible on existing hardware.
        sectors=[]
        center=(xyz.min(0)+xyz.max(0))*.5
        for group in result:
            rows=np.array(group['triangles']);mid=tri[rows].mean(1)-center
            keys=np.floor((np.arctan2(mid[:,2],mid[:,0])+np.pi)/(np.pi/2)).astype(int)%4
            for key in np.unique(keys):
                part=dict(group);part['triangles']=rows[keys==key].tolist()
                points=xyz[np.unique(indices[part['triangles']])]
                projected=np.column_stack((points@part['t'],-points@part['b']))
                part['lo']=projected.min(0);part['hi']=projected.max(0)
                part['area']=float(area[part['triangles']].sum());sectors.append(part)
        result=sectors
    # One complete, broad panel gets an emblem. Fins/bevels are plain metal,
    # not a tiled collection of clipped stars. The rocket's broad triangles
    # are fins: leave them deliberately unmarked.
    candidates=[]
    for i,g in enumerate(result):
        span=g['hi']-g['lo'];fill=g['area']/np.prod(span)
        facing=g['normal'][1] if family=='apspec' else g['normal'][2]
        center=(g['hi']+g['lo'])*.5
        projected=(np.column_stack((xyz@g['t'],-xyz@g['b']))-center)/max(span)*.92+.5
        if len(g['triangles'])>=2 and fill>.4 and emblem_fits(projected,indices[g['triangles']]):
            candidates.append((float(facing>.5)*100+g['area'],i))
    winner=max(candidates)[1] if candidates and family not in ('aprock','apspec') else None
    for i,group in enumerate(result):group['badge']=i==winner
    if family=='apcann':
        sides=[(g['area'],i) for i,g in enumerate(result) if not g['badge'] and g['normal'][0]>.5]
        if not sides:sides=[(g['area'],i) for i,g in enumerate(result) if not g['badge']]
        selected=max(sides)[1]
        for i,group in enumerate(result):group['hazard']=i==selected
    return result

def reuv_body(mesh,family,material,quadrant):
    assert len(mesh.submesh_list)==1 and not mesh.shared_vertex_data
    assert not mesh.edge_lists,'precomputed shadow topology needs an upstream rebuild'
    source=mesh.submesh_list[0];vd=source.vertex_data;indices=source.index_array.reshape(-1,3)
    groups=panel_groups(source,family);claimed=np.zeros(len(indices),dtype=bool)
    # Compact duplicated corners allow independent face UVs in one extra batch,
    # without overwriting shared vertices on other planes or detail surfaces.
    body=om.SubMesh(mesh,1);body.material_name=material;body.operation_type=source.operation_type
    body.vertex_data=om.VertexData(0);body.vertex_data.vertex_declaration=copy.deepcopy(vd.vertex_declaration)
    buffers={i:bytearray() for i in vd.vertex_buffer_map};out_indices=[];plain_indices=[];new_uv=[];origins=[]
    whole_xyz=values(vd,om.VES.POSITION);whole_center=(whole_xyz.min(0)+whole_xyz.max(0))*.5;whole_span=max(whole_xyz.max(0)-whole_xyz.min(0))
    for group in groups:
        selected=group['triangles'];assert not claimed[selected].any();claimed[selected]=True
        ids=np.unique(indices[selected]);mapping={int(old):len(origins)+i for i,old in enumerate(ids)}
        points=values(vd,om.VES.POSITION)[ids]
        uv=np.column_stack((points@group['t'],-points@group['b']))
        center=(group['hi']+group['lo'])*.5;scale=max(group['hi']-group['lo'])
        uv=(uv-center)/scale*.92+.5
        if family=='apspec':
            box=weapon_lamp_box('apspec','ns');lo=np.array(box[:2]);hi=np.array(box[2:])
            projected=np.column_stack((points@group['t'],-points@group['b']))
            span=group['hi']-group['lo'];projected-=center
            if span[0]>span[1]:projected=projected[:,::-1];span=span[::-1]
            scale=float(np.min((hi-lo)/np.maximum(span,1e-10)))*.94
            uv=projected*scale+(lo+hi)*.5
        elif family=='apcann' and not group['badge']:
            if group.get('hazard'):
                # Stock cannon does not sample a warning island at all. Its
                # existing side casing gets one complete type-0 warning band.
                lo=np.array([.835,.04]);hi=np.array([.99,.21])
                uv=(uv-.5)/.92*(hi-lo)+(lo+hi)*.5
            else:
                # Same shared detail material: quiet metal inside the hatch,
                # away from bolts, emblems, lamps and all warning swatches.
                centered=points-whole_center
                uv=np.column_stack((centered@group['t'],-centered@group['b']))/whole_span*.64
                uv=uv*np.array([.26,.13])+np.array([.225,.53])
        elif not group['badge'] and family not in ('apammo','aprepa'):
            # Object-scale plain metal has no frame, stripe or emblem to chop.
            # It no longer magnifies a tiny corner of the artwork.
            centered=points-whole_center
            uv=np.column_stack((centered@group['t'],-centered@group['b']))/whole_span*.64+.5
        # Each type is unpacked into its OWN DDS before mip generation. UVs
        # never reach another atlas cell, including at coarse mip levels.
        assert uv.min()>=0 and uv.max()<=1,'Unwrap would leave its isolated panel texture'
        new_uv.extend(uv.tolist());origins.extend(ids.tolist())
        for slot,vb in vd.vertex_buffer_map.items():
            for old in ids:
                start=int(old)*vb.vertex_size;buffers[slot].extend(vb.buffer[start:start+vb.vertex_size])
        destination=out_indices if group['badge'] else plain_indices
        destination.extend(mapping[int(old)] for old in indices[selected].reshape(-1))
    body.vertex_data.vertex_count=len(origins)
    for slot,raw in buffers.items():
        vb=vd.vertex_buffer_map[slot]
        body.vertex_data.create_vertex_buffer(bytes(raw),slot,vb.vertex_size)
    el=body.vertex_data.vertex_declaration.find_by_semantic(om.VES.TEXTURE_COORDINATES)
    vb=body.vertex_data.get_vertex_buffer(el.source);raw=bytearray(vb.buffer)
    uv=np.ndarray((len(origins),el.get_type_count()),'<f4',buffer=raw,offset=el.offset,strides=(vb.vertex_size,4))
    uv[:,:2]=new_uv;vb.set_buffer(raw)
    weights={}
    for bone in source.bone_assignments():weights.setdefault(bone.vertex_index,[]).append(bone)
    for new,old in enumerate(origins):
        for bone in weights.get(old,[]):body.create_bone_assignment(new,bone.bone_index,bone.weight)
    body.indices_32_bit=len(origins)>=65536;body.index_count=len(out_indices)
    body.set_index_buffer(np.asarray(out_indices,dtype='<u4' if body.indices_32_bit else '<u2').tobytes())
    plain=copy.copy(body);plain.material_name=material+('/rim' if family=='apspec' else '/plain');plain.index_count=len(plain_indices)
    plain.set_index_buffer(np.asarray(plain_indices,dtype='<u4' if plain.indices_32_bit else '<u2').tobytes())
    remainder=copy.copy(source);remainder.index_count=int((~claimed).sum())*3
    remainder.set_index_buffer(indices[~claimed].tobytes())
    mesh.submesh_list=[remainder]+([body] if body.index_count else [])+([plain] if plain.index_count else [])
    for i,sub in enumerate(mesh.submesh_list):sub.parent=mesh;sub.submesh_index=i
    mesh.name_table={i:sub.material_name for i,sub in enumerate(mesh.submesh_list)}
    return dict(triangles=int(claimed.sum()),totalTriangles=len(indices),faceGroups=len(groups),badgePanels=sum(g['badge'] for g in groups),quadrant=list(quadrant),casingHazardTriangles=sum(len(g['triangles']) for g in groups if g.get('hazard')))


def weapon_lamp_box(family,code):
    """Distinct authored optics per weapon type within the ONE faction atlas."""
    if family=='apcann':
        return {'ns':[.02,.29,.16,.36], 'bd':[.14,.075,.26,.23],
                'cc':[.16,.275,.32,.37], 'cr':[.16,.275,.32,.37]}[code]
    return {'aprock':[.06,.81,.315,.91], # paired vertical machinery lamps
            'apmort':[.775,.35,.82,.435], # paired small status dots
            'apspec':[.065,.785,.165,.935]}[family] # single framed rim-service port


def weapon_lamp_uv(sub,family,code):
    """Replace magnified stock light-swatches with physical planar lamp charts.

    These existing faces used a ~50x40px blob for entire tips/casing wedges.
    Map their planar groups to separate authored type-specific optics instead;
    no bitmap repaint, geometry change, new material or extra draw batch.
    """
    ids=sub.index_array.reshape(-1,3)
    xyz=values(sub.vertex_data,om.VES.POSITION)[ids]
    uv=values(sub.vertex_data,om.VES.TEXTURE_COORDINATES)[ids].copy()
    wrapped=uv-np.floor(uv.mean(1))[:,None,:]
    selected=((wrapped>=[.49,.84])&(wrapped<=[.70,.92])).all((1,2))
    cross=np.cross(xyz[:,1]-xyz[:,0],xyz[:,2]-xyz[:,0])
    normal=cross/np.maximum(np.linalg.norm(cross,axis=1)[:,None],1e-12)
    tolerance=np.linalg.norm(xyz.max((0,1))-xyz.min((0,1)))*.002
    groups=[]
    for row in np.flatnonzero(selected):
        n=normal[row];center=xyz[row].mean(0)
        group=next((g for g in groups if np.dot(g['normal'],n)>.999 and abs(np.dot(n,center-g['center']))<tolerance),None)
        if group is None:
            group=dict(normal=n,center=center,rows=[]);groups.append(group)
        group['rows'].append(int(row))
    box=weapon_lamp_box(family,code)
    # One existing physical lamp group is the common weapon core. Remaining
    # optics retain their per-type silhouettes and faction decorative colour.
    core_group=max(groups,key=lambda g:sum(np.linalg.norm(cross[r]) for r in g['rows']))
    for group in groups:
        bounds=WEAPON_CORE if group is core_group else box
        lo=np.array(bounds[:2]);hi=np.array(bounds[2:]);extent=hi-lo
        n=group['normal'];up=np.array([0,1,0] if abs(n[1])<.9 else [1,0,0],dtype=float)
        t=np.cross(up,n);t/=np.linalg.norm(t);b=np.cross(n,t)
        rows=group['rows'];p=xyz[rows]
        projected=np.stack((p@t,p@b),axis=2)
        lower=projected.min((0,1));upper=projected.max((0,1));span=upper-lower
        # The longer physical direction follows the longer atlas dimension.
        if span[1]>span[0]:projected=projected[:,:,::-1];span=span[::-1];lower=lower[::-1];upper=upper[::-1]
        if extent[1]>extent[0]:projected=projected[:,:,::-1];span=span[::-1];lower=lower[::-1];upper=upper[::-1]
        scale=float(np.min(extent/np.maximum(span,1e-10)))*.94
        uv[rows]=(projected-(lower+upper)*.5)*scale+(lo+hi)*.5
    assert np.isfinite(uv).all()
    return uv,selected,dict(lampUvTriangles=int(selected.sum()),lampUvGroups=len(groups),lampUvBounds=box,coreUvRows=core_group['rows'],coreUvBounds=WEAPON_CORE)


def reuv_weapon_lamps(mesh,name,family,code):
    sub=mesh.submesh_list[0];uv,selected,metadata=weapon_lamp_uv(sub,family,code)
    xyz=values(sub.vertex_data,om.VES.POSITION)[sub.index_array].reshape(-1,3,3)
    uv,hazard,hazard_metadata,warning=weapon_hazard_uv(uv,family,xyz)
    metadata.update(hazard_metadata)
    temporary=copy.copy(mesh);temporary.submesh_list=[sub]
    remesh(temporary,uv,name+'/detail')
    mesh.submesh_list[0]=temporary.submesh_list[0]
    for i,part in enumerate(mesh.submesh_list):part.parent=mesh;part.submesh_index=i
    mesh.name_table={i:part.material_name for i,part in enumerate(mesh.submesh_list)}
    return metadata


def weapon_hazard_uv(uv,family,xyz=None):
    """One authored stripe swatch per type inside the shared faction atlas."""
    uv=uv.copy();wrapped=uv-np.floor(uv.mean(1))[:,None,:]
    selected=((wrapped>=[.82,0])&(wrapped<=[1.001,1.001])).all((1,2))
    band=('apcann','aprock','apmort','apspec').index(family)
    p=wrapped[selected]
    u=np.clip((p[:,:,0]-.82)/.18,0,1);v=(p[:,:,1]%.5)/.5
    # The stock rocket's stripe U runs along its shaft. Turn the chart so CCA
    # crossbars stay transverse warning rungs, not long solid vertical stripes.
    if family=='aprock':u,v=v,u
    p[:,:,0]=.835+u*.155
    p[:,:,1]=band/4+.015+v*.22
    uv[selected]=p
    warning=selected.copy();quiet=np.zeros(len(uv),bool);panels=0
    if family=='apspec':
        assert xyz is not None
        # Stock strips use unrelated UV scales/directions on neighboring faces.
        # Keep warnings on the four straight exterior panels; bevel end caps
        # are deliberately quiet metal, not stretched fragments of that band.
        for box in ([.635,.365,.715,.635],[.315,.80,.495,1.001]):
            selected|=((wrapped>=box[:2])&(wrapped<=box[2:])).all((1,2))
        outer=(xyz[:,:,1].min(1)>1.06)&(np.linalg.norm(xyz[:,:,[0,2]],axis=2).min(1)>1.08)
        assert int(outer.sum())==8,'Special outer shell topology changed'
        quiet=selected&~outer
        whole=max(xyz.max((0,1))-xyz.min((0,1)))
        center=(xyz.max((0,1))+xyz.min((0,1)))*.5
        for row in np.flatnonzero(quiet):
            normal=np.cross(xyz[row,1]-xyz[row,0],xyz[row,2]-xyz[row,0])
            axes=[i for i in range(3) if i!=int(abs(normal).argmax())]
            projected=(xyz[row,:,axes].T-center[axes])/whole
            uv[row]=projected*np.array([.18,.09])+np.array([.225,.53])
        keys=(xyz.mean(1)[:,0]>0).astype(int)+2*(xyz.mean(1)[:,2]>0).astype(int)
        groups=[]
        for key in np.unique(keys[outer]):
            rows=np.flatnonzero(outer&(keys==key));points=xyz[rows]
            radial=points.mean((0,1))*np.array([1,0,1]);radial/=np.linalg.norm(radial)
            tangent=np.array([-radial[2],0,radial[0]])
            projected=points@tangent
            groups.append((rows,projected,float(projected.min()),float(projected.max())))
        width=max(high-low for _,_,low,high in groups)
        low_y=float(xyz[outer,:,1].min());height=float(np.ptp(xyz[outer,:,1]))
        for rows,projected,low,high in groups:
            uv[rows,:,0]=.835+((projected-(low+high)*.5)/width+.5)*.155
            uv[rows,:,1]=.765+(xyz[rows,:,1]-low_y)/height*.22
        warning=outer;selected|=outer;panels=len(groups)
    return uv,selected,dict(hazardUvTriangles=int(warning.sum()),hazardUvBand=[band/4,(band+1)/4],quietUvTriangles=int(quiet.sum()),alignedWarningPanels=panels),warning


def lamp_mask(a,code,repair=False):
    """Select authored saturated lamp glass; never invent/recolour a motif."""
    rgb=a.astype(float)
    r,g,b=[rgb[:,:,i] for i in range(3)]
    if code=='ns':mask=(b>135)&(b>r*1.4)&(g>r*1.25)
    elif code=='bd':mask=(r>145)&(r>g*1.7)&(r>b*1.7)
    elif code=='cc':mask=(r>165)&(g>60)&(g>r*.23)&(g<r*.92)&(b<g*.65)
    elif code=='cr':mask=(g>140)&(r>g*.30)&(r<g*.96)&(b<r*.70)
    else:raise ValueError('Unknown faction: '+code)
    return mask


def emission_image(image,mask,colour=None):
    a=np.array(image.convert('RGB'));e=np.zeros_like(a)
    if colour is None:e[mask]=np.clip(a[mask].astype(float)*1.4,0,255).astype('uint8')
    else:
        # Technical E-channel calibration: authored glass footprint/luminance,
        # one agreed hue per faction, no emissive contamination from paint.
        brightness=np.clip(a.max(2).astype(float)*1.4/255,0,1)
        e[mask]=(brightness[mask,None]*np.array(colour)).astype('uint8')
    return Image.fromarray(e)


def glass_guard(kind,code,size):
    """Retain the pre-edit physical lamp footprint, especially for red factions.

    Hue alone cannot distinguish a red emitter from Black Dog painted armour.
    NSDF's explicitly accepted cyan rails remain untouched except core inserts.
    """
    if code=='ns':return np.ones((size[1],size[0]),bool)
    stem=f'{kind}_{code}_master' if kind in ('weapon','badge') else f'{"cram" if kind=="ammo" else "crhp"}{code}4-master'
    with Image.open(ARTREF/'glow-masks'/(stem+'.png')) as image:
        return np.array(image.convert('L').resize(size,Image.Resampling.NEAREST))>0


def pod_hazard_image(image,family,code):
    """Reuse authored warning pixels on pod trim, not another texture sheet.

    A warning band intentionally repeats; no emblem, casing chart or lamp is
    tiled. The front ammo plaque and every original luminous region are spared.
    """
    image=image.copy();size=image.width
    with Image.open(ARTREF/f'weapon_{code}_master.png') as source:
        w,h=source.size;row=0 if family=='apammo' else 2
        tile=source.crop((round(w*.835),round(h*(row/4+.015)),round(w*.99),round(h*((row+1)/4-.015)))).convert('RGB')
    tile=tile.transpose(Image.Transpose.ROTATE_90 if family=='apammo' else Image.Transpose.ROTATE_270)
    bounds=(.04,.115,.96,.145) if family=='apammo' else (.03,.772,.97,.790)
    x0,y0,x1,y1=[round(v*size) for v in bounds];height=y1-y0
    tile=tile.resize((max(1,round(height*tile.width/tile.height)),height),Image.Resampling.LANCZOS)
    band=Image.new('RGB',(x1-x0,height))
    for x in range(0,band.width,tile.width):band.paste(tile,(x,0))
    if family=='apammo':
        # Preserve the complete existing centered faction badge.
        badge=image.crop((round(.49*size),y0,round(.60*size),y1))
    image.paste(band,(x0,y0))
    if family=='apammo':image.paste(badge,(round(.49*size),y0))
    return image


def pod_emission(atlas,family,uv,code):
    """Extract authored lamps with chart/region guards, excluding the badge."""
    a=np.array(atlas.convert('RGB'));mask=lamp_mask(a,code,family=='aprepa')
    mask&=glass_guard('ammo' if family=='apammo' else 'repair',code,atlas.size)
    y,x=np.meshgrid(np.linspace(0,1,a.shape[0]),np.linspace(0,1,a.shape[1]),indexing='ij')
    if family=='apammo':
        regions=((y>.155)&(y<.23))|((y>.315)&(y<.39))|(y>.58)
        mask&=regions
    else:
        center=(abs(x-.355)<.075)&(abs(y-.355)<.075)
        top=(x>.025)&(x<.685)&(y>.025)&(y<.685)
        rails=(abs(x-.355)<.045)|(abs(y-.355)<.045)
        sides=(y>.77)&(y<.94)
        warning=(y>=.77)&(y<=.793)
        mask&=((top&rails)|sides)&~center&~warning
    coverage=Image.new('L',atlas.size);draw=ImageDraw.Draw(coverage)
    for row in uv:draw.polygon([tuple(v*(a.shape[0]-1)) for v in row],fill=255)
    drawn=np.array(coverage.filter(ImageFilter.MaxFilter(17)))>0
    mask&=drawn
    result=np.array(emission_image(atlas,mask,DECOR[code]))
    r,g,b=a.astype(float).transpose(2,0,1)
    if family=='apammo':
        region=((x>.478)&(x<.523)&(y>.587)&(y<.635))|((x>.035)&(x<.45)&(y>.69)&(y<.90))
        functional=region&(b>120)&(b>r*1.35)&(b>g*1.15)
        colour=(20,100,255)
    else:
        region=((x>.305)&(x<.405)&(y>.075)&(y<.16))|((x>.80)&(x<.89)&(y>.10)&(y<.21))
        functional=region&(g>130)&(g>r*1.4)&(g>b*1.4)
        colour=(30,255,12)
    functional&=drawn
    core=np.array(emission_image(atlas,functional,colour));result[functional]=core[functional]
    return Image.fromarray(result)

def build():
    files={};models={};odfs={};pod_masters={}
    routes=json.loads((REF/'routes.json').read_text())
    def put(file,image):
        path=ROOT/'Assets/Textures'/file;save_bc(image,path)
        files[file]=dict(size=list(image.size),sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    for code,(faction,prefix) in FACTIONS.items():
        with Image.open(ARTREF/'plain_v4.png') as image:
            qx,qy={'ns':(0,0),'bd':(1,0),'cc':(0,1),'cr':(1,1)}[code];w,h=image.size
            cell=image.crop((round(qx*w/2),round(qy*h/2),round((qx+1)*w/2),round((qy+1)*h/2)))
            put(f'crpk{code}_plain.dds',cell.convert('RGB').resize((512,512),Image.Resampling.LANCZOS))
        with Image.open(ARTREF/('nav_'+code+'_v4.png')) as image:nav=image.convert('RGB').resize((1024,1024),Image.Resampling.LANCZOS)
        put('crnv'+code+'_d.dds',nav)
        # Restrict emission to the two stock lower lamps. Painted emblems and
        # faction red markings must not glow. No diffuse-derived normal map.
        a=np.array(nav);x,y=np.meshgrid(np.linspace(0,1,1024),np.linspace(0,1,1024))
        mask=(((x-.084)**2/(.043**2)+(y-.915)**2/(.046**2)<1)|((x-.205)**2/(.043**2)+(y-.915)**2/(.046**2)<1))
        glass=lamp_mask(a,code)
        if code=='cr':glass|=lamp_mask(a,code,True)
        mask&=glass
        put('crnv'+code+'_e.dds',emission_image(nav,mask,DECOR[code]))
        with Image.open(ARTREF/('badge_'+code+'_master.png')) as image:
            # All weapon types share ONE compact badge/lamp panel.
            cell=image.convert('RGB').resize((512,512),Image.Resampling.LANCZOS)
            put(f'crpk{code}2_d.dds',cell)
            a=np.array(cell);y,x=np.meshgrid(np.linspace(0,1,512),np.linspace(0,1,512),indexing='ij')
            band=(x<.23)|(x>.77)|(y>.77)
            mask=lamp_mask(a,code)&band&glass_guard('badge',code,cell.size)
            if code=='cr':mask|=lamp_mask(a,code,True)&band
            put(f'crpk{code}2_e.dds',emission_image(cell,mask,DECOR[code]))
        # The weapon families use the same stock UV coordinates for machinery,
        # lamps and hazard regions. Share the cannon-layout cell across all four
        # instead of shipping near-identical repaints per model. Faction paint
        # remains unique, and the compiler does not downsize the surviving map.
        with Image.open(ARTREF/('weapon_'+code+'_master.png')) as image:
            cell=image.convert('RGB').resize((1024,1024),Image.Resampling.LANCZOS)
            put(f'crwp{code}_d.dds',cell)
            a=np.array(cell);mask=lamp_mask(a,code)
            if code=='cr':
                mask|=lamp_mask(a,code,True)
            # Warning paint is never an emitter, even if a worn yellow/cyan
            # pixel happens to pass a hue threshold.
            y,x=np.meshgrid(np.linspace(0,1,1024),np.linspace(0,1,1024),indexing='ij')
            paint=(x>=.82)|((x>.635)&(x<.715)&(y>.365)&(y<.635))|((x>.315)&(x<.495)&(y>.80))
            mask&=~paint&glass_guard('weapon',code,cell.size)
            result=np.array(emission_image(cell,mask,DECOR[code]))
            r,g,b=a.astype(float).transpose(2,0,1)
            core=(x>WEAPON_CORE[0])&(y>WEAPON_CORE[1])&(x<WEAPON_CORE[2])&(y<WEAPON_CORE[3])&(r>150)&(g>80)&(g<r*.96)&(b<g*.7)
            common=np.array(emission_image(cell,core,(255,185,12)));result[core]=common[core]
            put(f'crwp{code}_e.dds',Image.fromarray(result))
        # Owner retained the stock/full-v3 unwrap but requested actual faction
        # building/vehicle palettes and unique lamp patterns in the v4 masters.
        for family,type_id in (('apammo',0),('aprepa',1)):
            stem=FAMILIES[family][0];uv,_=full_uv(read(SRC/(family+'.mesh')).submesh_list[0],family)
            master=PODREF/(stem+code+'4-master.png')
            with Image.open(master) as image:paint=pod_hazard_image(image.convert('RGB').resize((1024,1024),Image.Resampling.LANCZOS),family,code)
            atlas=atlas_image(paint,uv)
            put(f'crpk{code}{type_id}_d.dds',atlas)
            put(f'crpk{code}{type_id}_e.dds',pod_emission(atlas,family,uv,code))
            pod_masters[master.relative_to(ROOT).as_posix()]=hashlib.sha256(master.read_bytes()).hexdigest()
        materials=['import * from "CR_BZBase.material"','']
        for family,(stem,quad) in FAMILIES.items():
            name=stem+code;mesh=read(SRC/(family+'.mesh'));before=geometry(mesh)
            mesh.skeleton_name=name+'.skeleton'
            if family=='apcamr':
                for sub in mesh.submesh_list:sub.material_name=name
                coverage=dict(triangles=mesh.submesh_list[0].index_count//3,totalTriangles=mesh.submesh_list[0].index_count//3)
            elif family in ('apammo','aprepa'):
                uv,metadata=full_uv(mesh.submesh_list[0],family);remesh(mesh,uv,name)
                coverage=dict(triangles=len(uv),totalTriangles=len(uv),fullUnwrap=True,charts=metadata['charts'])
            else:
                coverage=reuv_body(mesh,family,name,quad)
                coverage.update(reuv_weapon_lamps(mesh,name,family,code))
            assert geometry(mesh)==before,'Geometry/skin changed: '+name
            stream=io.BytesIO();oms.MeshSerializer(stream).write(mesh)
            path=ROOT/'Assets/Models'/(name+'.mesh');path.write_bytes(stream.getvalue())
            assert geometry(read(path))==before,'Roundtrip geometry changed: '+name
            for ext in ('vdf','skeleton'):shutil.copyfile(SRC/(family+'.'+ext),ROOT/'Assets/Models'/(name+'.'+ext))
            models[name]=dict(source=family,coverage=coverage,geometry=before,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
            type_id=None if quad is None else quad[0]+quad[1]*2
            diffuse='crnv'+code+'_d.dds' if quad is None else f'crpk{code}{type_id}_d.dds'
            emission='crnv'+code+'_e.dds' if family=='apcamr' else f'crpk{code}{type_id}_e.dds'
            materials.extend([f'material {name} : CR_BZBase','{',f'    set_texture_alias DiffuseMap {diffuse}',
              '    set_texture_alias NormalMap flat_N.dds','    set_texture_alias SpecularMap crvcca_patch_s.dds',
              f'    set_texture_alias EmissiveMap {emission}','    set $diffuse "1 1 1"','    set $ambient "1 1 1"',
              '    set $specular ".15 .15 .15"' if family in ('apammo','aprepa') else '    set $specular ".25 .25 .25"',
              '    set $shininess "32"' if family in ('apammo','aprepa') else '    set $shininess "48"','}',''])
            if quad is not None and family not in ('apammo','aprepa'):
                materials.extend([f'material {name}/detail : {name}','{',f'    set_texture_alias DiffuseMap crwp{code}_d.dds',f'    set_texture_alias EmissiveMap crwp{code}_e.dds','}',''])
                finish=f'crwp{code}_d.dds' if family in ('apcann','apspec') else f'crpk{code}_plain.dds'
                glow=f'crwp{code}_e.dds' if family=='apspec' else 'black.dds'
                child='/rim' if family=='apspec' else '/plain'
                materials.extend([f'material {name}{child} : {name}','{',f'    set_texture_alias DiffuseMap {finish}',f'    set_texture_alias EmissiveMap {glow}','    set $diffuse "1 1 1"','    set $ambient "1 1 1"','}',''])
        (ROOT/'Materials'/('CR_pickups_'+code+'.material')).write_text('\n'.join(materials),newline='\n')
        # Retain source identity in the output name: e.g. sapmini != sspmini.
        # Soviet minigun/ammo values differ from NSDF and must not be conflated.
        sources={p.stem for p in SRC.glob('ap*.odf')}
        for route in routes:
            if route['faction']==code:sources.update(route['sources'])
        translated={}
        for stem in sorted(sources):
            source=SRC/(stem+'.odf')
            text=source.read_text();match=re.search(r'baseName\s*=\s*"([^"]+)"',text)
            assert match and match[1] in FAMILIES,(source.name,match)
            destination=prefix+source.stem
            if len(destination)>8:destination=prefix+source.stem[:4]+hashlib.sha256(source.name.encode()).hexdigest()[:3]
            assert destination not in odfs,'ODF namespace collision: '+destination
            new_model=FAMILIES[match[1]][0]+code
            output=re.sub(r'(baseName\s*=\s*)"[^"]+"',lambda m:m[1]+'"'+new_model+'"',text,count=1)
            # Keep weapon-name/null UI resolution and all gameplay values intact.
            (ROOT/'ODF'/(destination+'.odf')).write_text(output.rstrip()+'\n',newline='\n')
            odfs[destination]=dict(source=source.name,model=new_model,faction=faction)
            translated[source.stem]=destination
        for route in routes:
            if route['faction']!=code:continue
            path=ROOT/route['path'];baseline=REF/'menus'/path.name
            text=baseline.read_text();current=path.read_text()
            def substitute(match):
                old=match[2]
                return match[1]+translated.get(old,old)+match[3]
            pattern=r'(?mi)^((?:buildItem|cannonItem|rocketItem|mortarItem|specialItem)\d+\s*=\s*")([^"]+)(")'
            output=re.sub(pattern,substitute,text)
            assert current in (text,output),'Unrelated menu edit: '+str(path)
            path.write_text(output,newline='\n')
    retired=sorted([f'crw{kind}{code}_{channel}.dds' for code in FACTIONS for kind in ('c','r','m','s') for channel in ('d','e')]+
        [f'crpk{code}3_{channel}.dds' for code in FACTIONS for channel in ('d','e')]+
        [f'crpk{code}{kind}_surf.dds' for code in FACTIONS for kind in (0,1)])
    optimization=dict(previousDraftMaps=84,previousDraftBytes=44052064,currentMaps=len(files),
        currentBytes=sum((ROOT/'Assets/Textures'/name).stat().st_size for name in files),
        retiredFiles=retired,sharedWeaponDetail={code:f'crwp{code}' for code in FACTIONS})
    receipt=dict(schema=4,files=files,models=models,odfs=odfs,menuRoutes=len(routes),masters={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in REF.glob('*.png')},podMasters=pod_masters,navWeaponMasters={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in ARTREF.glob('*.png')},atlasOptimization=optimization)
    (REF/'build.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(f'Built {len(models)} faction models, {len(odfs)} independent ODFs and {len(files)} mipped DDS maps; native geometry/rig bytes retained.')

if __name__=='__main__':build()
