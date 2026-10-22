"""Generate CR's authored muzzle geometry/materials and presentation-only ODF keys.

The shared toolbox writes meshes; no game model/art is copied. The EXU-derived
shader and original flame mask are pinned in the provenance manifest. Stock
ODFs are read only to preserve every gameplay field when adding new overrides.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import re
import struct
import sys
from bzmodellibs import toolbox_root

ROOT = Path(__file__).resolve().parents[1]
BEGIN, END = "// CR WEAPON FLASH BEGIN", "// CR WEAPON FLASH END"


def geometry(profile):
    length, radius, petals = (profile[k] for k in ("length", "radius", "petals"))
    shape = profile["shape"]
    widths = {"needle": [0.04,.16,.14,.05,0.005], "fork": [.05,.3,1,.32,.005],
              "jet": [.06,.35,.7,.35,.005], "crown": [.08,.9,1,.52,.005],
              "pulse": [.08,.65,1,.40,.005]}[shape]
    depths = [0,.12,.36,.65,1]
    layers = []
    for role in range(3):
        vertices, indices = [], []
        sheets = 3 if role == 0 else petals if role == 1 else 1
        for sheet in range(sheets):
            angle = math.pi * sheet / sheets
            start = len(vertices)
            for row in range(5):
                z = depths[row]
                for col in range(7):
                    a = col/3-1
                    heat = (1-z*.45) if role == 0 else max(0,1-z*.9-abs(a)*.35)
                    alpha = math.sin(math.pi*col/6)**1.3 * (1-z)**.7
                    if role == 2:
                        # Small frontal veil, never a large opaque halo.
                        theta = math.tau*col/6
                        radial = radius*row/4*.45
                        pos = [radial*math.cos(theta),radial*math.sin(theta),-length*.035]
                        alpha = (1-row/4)**2*.28
                    else:
                        radial = radius*widths[row]*a*(.24 if role == 0 else 1)
                        reach = 1 if role == 0 else .82+.18*math.sin(sheet*2.1+.8)**2
                        # The split forks have genuinely different geometry,
                        # not only a colour/scale change to one universal cone.
                        fork = .16*math.sin(z*math.pi)*math.cos(sheet*math.pi) if shape == "fork" and role == 1 else 0
                        pos = [(radial+fork*radius)*math.cos(angle),(radial+fork*radius)*math.sin(angle),-length*z*reach]
                    rgba = [1,.20+.77*heat,.035+.93*heat,alpha*(.8 if role==0 else .5)]
                    vertices.append((pos,rgba,[col/6+role*2,z]))
            for row in range(4):
                for col in range(6):
                    a=start+row*7+col
                    for tri in [(a,a+1,a+7),(a+1,a+8,a+7)]:
                        p,q,r=[vertices[i][0] for i in tri]
                        u,v=[q[i]-p[i] for i in range(3)],[r[i]-p[i] for i in range(3)]
                        cross=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
                        if sum(x*x for x in cross)>1e-15: indices.extend(tri)
        layers.append((vertices,indices))
    return layers


def mesh_bytes(profile, material):
    sys.path.insert(0,str(toolbox_root()))
    from battlezone.meshes import ogre as codec
    mesh = codec.OgreMesh("[MeshSerializer_v1.100]", "<")
    for role,(vertices,indices) in enumerate(geometry(profile)):
        raw=bytearray()
        for pos,colour,uv in vertices:
            assert all(math.isfinite(x) for x in (*pos,*colour,*uv))
            r,g,b,a=[round(max(0,min(1,x))*255) for x in colour]
            raw.extend(struct.pack("<3fI2f",*pos,(a<<24)|(r<<16)|(g<<8)|b,*uv))
        geom=codec.Geometry(len(vertices),[codec.VertexElement(0,2,1,0,0),codec.VertexElement(0,10,5,12,0),
            codec.VertexElement(0,1,7,16,0)],{0:codec.VertexBuffer(0,24,bytes(raw),0)})
        mesh.submeshes.append(codec.SubMesh(material,False,indices,False,geometry=geom,name=["Core","Plume","Bloom"][role]))
    data=codec.write_mesh(mesh)
    assert codec.write_mesh(codec.read_mesh(data))==data
    return data


def authored_odf(source, name, choice, profiles):
    # Generated blocks are the only changed portion of a complete source ODF.
    text=source.replace("\r\n","\n")
    if BEGIN in text:
        a=text.index(BEGIN);b=text.index(END,a)+len(END)
        if text[b:b+1]=="\n": b+=1
        text=text[:a]+text[b:]
    if not choice["profile"]: return text
    key=choice["profile"];p=profiles[key]
    section=re.search(r"(?im)^[ \t]*\[WeaponClass\][^\n]*\n",text)
    assert section, name+": missing WeaponClass section"
    at=section.end()
    # Natural hardpoint origin. Never use the avtank-specific offset on every
    # carrier; the inventory identifies models needing individual tip fitting.
    block=f'''{BEGIN}
// Authored {key}: shape/colour/timing in References/WeaponPresentation/profiles.json.
// Requires Muzzle Flashes ON and matching EXU; native SP/build guards remain.
flashMesh = "crmf_{key}.mesh"
flashMaterial = "CR/Muzzle/{key}"
flashDuration = {p['duration']}
flashScale = 1
flashEndScale = 0.65
flashOffset = "0 0 0"
{END}
'''
    return text[:at]+block+text[at:]


def material(profiles):
    # Named technique/pass overrides match the checked EXU shader contract.
    text='// Generated by Tools/Build-WeaponFlashes.py\nabstract material CR/Muzzle/Base\n{\n'
    for backend,suffix in (("DX11",""),("DX9","9")):
        text+=f'''    technique {backend}
    {{
        pass Emission
        {{
            lighting off
            scene_blend one one
            depth_write off
            depth_check on
            cull_hardware none
            cull_software none
            fog_override true
            texture_unit Flame
            {{
                texture crmf_flame.png
                tex_address_mode clamp
                filtering bilinear
            }}
            vertex_program_ref CR_Muzzle_v1_VS{suffix} {{ }}
            fragment_program_ref CR_Muzzle_v1_PS{suffix} {{ }}
        }}
    }}
'''
    text+='}\n'
    for name,p in profiles.items():
        text+=f'material CR/Muzzle/{name} : CR/Muzzle/Base\n{{\n'
        for backend,suffix in (("DX11",""),("DX9","9")):
            anim=' '.join(str(x) for x in p['animation'])
            text+=f'''    technique {backend}
    {{
        pass Emission
        {{
            vertex_program_ref CR_Muzzle_v1_VS{suffix}
            {{
                param_named flashAnimation float4 {anim}
            }}
            fragment_program_ref CR_Muzzle_v1_PS{suffix}
            {{
                param_named flashCoolColour float3 {' '.join(str(x) for x in p['cool'])}
                param_named flashHotColour float3 {' '.join(str(x) for x in p['hot'])}
                param_named flashAnimation float4 {anim}
            }}
        }}
    }}
'''
        text+='}\n'
    return text


def build(stock, check):
    config=json.loads((ROOT/'References/WeaponPresentation/profiles.json').read_text())
    profiles=config['profiles'];outputs={}
    for name,p in profiles.items():
        outputs[ROOT/f'Assets/Models/crmf_{name}.mesh']=mesh_bytes(p,'CR/Muzzle/'+name)
    outputs[ROOT/'Materials/cr_muzzle.material']=material(profiles).encode()
    for name,choice in config['weapons'].items():
        if not choice['profile']: continue
        target=ROOT/'ODF'/(name+'.odf')
        source=target if target.exists() else stock/(name+'.odf')
        outputs[target]=authored_odf(source.read_text(),name,choice,profiles).encode()
    for path,data in outputs.items():
        if check:
            existing=path.read_bytes()
            if path.suffix in ('.odf','.material'): existing=existing.replace(b'\r\n',b'\n')
            assert existing==data, str(path.relative_to(ROOT))+' differs; regenerate'
        else:
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    print(f"Weapon flashes: {len(profiles)} profiles, {len(outputs)-len(profiles)-1} ODFs; mesh round trips pass")


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stock',type=Path,default=ROOT/'ODF',help='shipping StockODFFiles for initial creation; --check uses shipped overrides')
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args();build(args.stock,args.check)
