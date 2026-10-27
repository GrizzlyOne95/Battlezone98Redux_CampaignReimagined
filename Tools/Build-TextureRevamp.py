"""Compile reviewed TextureRevamp PNG masters to legacy BCn DDS with full mips.

No generative calls are made at build time. ImageGen supplies the colour/height
masters; this compiler performs format conversion and deterministic technical
map construction. Heights are authored approximations, not recovered geometry.
Model import and interior UV/material rebinding are separate from this tool.
"""
from pathlib import Path
import hashlib,json,re,sys
import numpy as np
from PIL import Image,ImageFilter,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bcdds import save_bc

ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'References/TextureRevamp'
TEX=ROOT/'Assets/Textures'
COLOURS={
 'bark1':('cr17_ftrunk1.dds',(1024,2048)),
 'bark2':('cr17_ftrunk2.dds',(512,2048)),
 'storage':('abstor_d.dds',(1256,1256)),
 'cockpit':('avapc_cockpit_D.dds',(1256,1256)),
 'repair':('crvpkup_d.dds',(1024,1024)),
 'salvage':('crvsalv_d.dds',(1024,1024)),
 'olwall':('crviolwall_d.dds',(1024,1024)),
 'olfloor':('crviolfloor_d.dds',(1024,1024)),
 'oltrim':('crvioltrim_d.dds',(1024,1024)),
 'olscreen':('crviolscreen_d.dds',(1536,512)),
}
HEIGHTS={
 'bark1_height':('cr17_ftrunk1_n.dds',(1024,2048),1.8),
 'bark2_height':('cr17_ftrunk2_n.dds',(512,2048),1.1),
 'olwall_height':('crviolwall_n.dds',(1024,1024),1.1),
 'olfloor_height':('crviolfloor_n.dds',(1024,1024),.7),
 'oltrim_height':('crvioltrim_n.dds',(1024,1024),1.1),
 **{f'cr16{x}_height':(f'cr16{x}_n.dds',(1024,1024),.65) for x in ('cmd','hng','pwr','tow')},
 **{f'{x}_height':(f'crv{x}_n.dds',(1024,1024),.8) for x in ('obdata00','oblemb00','obcycl00','obpowr00')},
}

def normal_from_height(image,strength):
    """DirectX RGB normal: negative image-U/V height gradients, positive Z.

    Smooth subpixel paint noise; cap slopes to keep the added relief shallow.
    Scaling by resolution keeps strength stable when shipping size changes.
    """
    h=np.asarray(image.convert('L').filter(ImageFilter.GaussianBlur(1.0)),dtype=np.float32)/255
    dx=(np.roll(h,-1,axis=1)-np.roll(h,1,axis=1))*.5*h.shape[1]/1024
    dy=(np.roll(h,-1,axis=0)-np.roll(h,1,axis=0))*.5*h.shape[0]/1024
    n=np.stack((-dx*strength,-dy*strength,np.ones_like(h)),axis=-1)
    n[:,:,:2]=np.clip(n[:,:,:2],-.35,.35)
    n/=np.linalg.norm(n,axis=-1,keepdims=True)
    return Image.fromarray(np.round((n*.5+.5)*255).astype('uint8'))

def panel_height(size,kind):
    """Conservative authored structural fields, never diffuse-as-height.

    Only broad, known original atlas panel outlines get shallow relief. Lamps,
    stripes, symbols and random scratches do not become raised geometry.
    """
    image=Image.new('L',size,128);d=ImageDraw.Draw(image)
    rects=([( .012,.012,.510,.552),(.519,.010,.990,.552),(.015,.688,.635,.835),(.015,.885,.728,.975)]
           if kind=='storage' else [(.004,.003,.268,.213),(.007,.365,.300,.720),(.510,.020,.677,.245),(.530,.370,.700,.692),(.012,.792,.310,.990)])
    for x0,y0,x1,y1 in rects:
        box=tuple(round(v*size[i%2]) for i,v in enumerate((x0,y0,x1,y1)))
        d.rectangle(box,fill=131,outline=120,width=max(1,size[0]//512))
    return image.filter(ImageFilter.GaussianBlur(1.2))

def build(foliage_only=False):
    written={}
    def put(name,image,fmt='BC1_UNORM'):
        save_bc(image,TEX/name,fmt)
        written[name]=dict(size=list(image.size),format=fmt,sha256=hashlib.sha256((TEX/name).read_bytes()).hexdigest())
    for key,(name,size) in COLOURS.items():
        if foliage_only and key not in ('bark1','bark2'):continue
        with Image.open(REF/(key+'.png')) as image:
            put(name,image.convert('RGB').resize(size,Image.Resampling.LANCZOS))
    for key,(name,size,strength) in HEIGHTS.items():
        if foliage_only and key not in ('bark1_height','bark2_height'):continue
        with Image.open(REF/(key+'.png')) as image:
            put(name,normal_from_height(image.resize(size,Image.Resampling.LANCZOS),strength))
    for key in ('bark1','bark2'):
        name,size=COLOURS[key]
        put(name.replace('.dds','_s.dds'),Image.new('RGB',(4,4),(22,22,22)))
    if foliage_only:return written
    for name,size,kind in [('crvstor_n.dds',(1024,1024),'storage'),('crvpkup_n.dds',(1024,1024),'pickup')]:
        put(name,normal_from_height(panel_height(size,kind),.9))
    for key in ('olwall','olfloor','oltrim'):
        name,size=COLOURS[key]
        put(name.replace('_d.dds','_s.dds'),Image.new('RGB',(4,4),(42,42,42)))
    with Image.open(REF/'olscreen.png') as image:
        put('crviolscreen_e.dds',image.convert('RGB').resize((1536,512),Image.Resampling.LANCZOS))
    # Keep approved captured-base diffuse artwork byte-for-byte. New auxiliary
    # maps select its actual cyan nodes, never stock human lamp locations.
    for suffix in ('cmd','hng','pwr','tow'):
        key='cr16'+suffix
        with Image.open(TEX/(key+'_d.dds')) as image:
            rgb=np.asarray(image.convert('RGB'),dtype=np.float32)/255
        r,g,b=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
        glow=np.clip((np.minimum(g,b)-r-.035)*5,0,1)*np.clip((np.minimum(g,b)-.15)*4,0,1)
        emission=np.round(rgb*glow[:,:,None]*255).astype('uint8')
        spec=np.round((.14+.12*(1-glow))*255).astype('uint8')
        put(key+'_e.dds',Image.fromarray(emission))
        put(key+'_s.dds',Image.fromarray(np.repeat(spec[:,:,None],3,axis=2)))
    # Import texture aliases share a single resource per byte-identical source.
    # Preserve the original Tartarus DDS bytes and its original eye pixels.
    for entry in json.loads((REF/'imported-textures.json').read_text()):
        if entry.get('preserveBytes'):
            path=TEX/entry['file']
            assert hashlib.sha256(path.read_bytes()).hexdigest()==entry['sourceSha256'],'Original Tartarus artwork changed'
            continue
        with Image.open(REF/entry['master']) as image:
            rgba=image.convert('RGBA')
            if all(lo==hi for lo,hi in rgba.getextrema()):rgba=rgba.resize((4,4))
            put(entry['file'],rgba,entry['format'])
    (REF/'build.json').write_text(json.dumps(dict(schema=1,files=written),indent=2)+'\n')
    forest=ROOT/'References/Misn17Forest/source-assets.json'
    if forest.exists():
        data=json.loads(forest.read_text())
        for name,record in written.items():
            if name.startswith('cr17_ftrunk'):data['textures'][name]=record['sha256']
        data['trunk_art']='TextureRevamp: generated colour/height masters; original tree geometry and attribution retained.'
        forest.write_text(json.dumps(data,indent=2)+'\n')
    print(f'Compiled {len(written)} DDS resources with full offline mip chains.')

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--foliage-only',action='store_true',help='Compile only the six bark maps for the forest builder')
    build(foliage_only=parser.parse_args().foliage_only)
