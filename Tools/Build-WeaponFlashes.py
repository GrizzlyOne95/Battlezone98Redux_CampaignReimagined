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
import os
import re
import struct
import sys
from bzmodellibs import toolbox_root

ROOT = Path(__file__).resolve().parents[1]
BEGIN, END = "// CR WEAPON FLASH BEGIN", "// CR WEAPON FLASH END"
CRAFT_BEGIN, CRAFT_END = "// CR CRAFT FLASH OFFSET BEGIN", "// CR CRAFT FLASH OFFSET END"
OFFSETS = ROOT / "References/WeaponPresentation/craft-flash-offsets.json"
GAME = Path(os.environ.get("BZR_GAME_DIR", r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux"))
# Tips closer than this (m) to the hardpoint get no per-craft key.
MIN_TIP = 0.1
# Front slab (m) of a barrel whose bounding-box centre is the aperture centre.
TIP_SLAB = 0.25


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


# ---------------------------------------------------------------------------
# Per-craft flash offsets (OpenShim `[CraftClass] flashOffset<N>`)
# ---------------------------------------------------------------------------
def odf_lines(text):
    """Return {section_lower: {key_lower: value}} for a CR ODF (comments dropped)."""
    section, out = "", {}
    for line in text.replace("\r\n", "\n").split("\n"):
        line = line.split("//", 1)[0].strip()
        if line.startswith("["):
            section = line.strip("[]").lower()
        elif "=" in line:
            key, value = line.split("=", 1)
            out.setdefault(section, {})[key.strip().lower()] = value.strip().split(";", 1)[0].strip().strip('"')
    return out


def flash_weapons(config):
    return {n.lower() for n, c in config["weapons"].items() if c["profile"]}


def craft_slots(odf_dir, weapons):
    """{craft: {"model": basename, "section": bool, "slots": {n: (weapon, hardpoint)}}}
    for every CR craft ODF whose slot selects a weapon that carries flashMesh."""
    crafts = {}
    for path in sorted(odf_dir.glob("*.odf")):
        data = odf_lines(path.read_text(errors="replace"))
        game = data.get("gameobjectclass")
        if not game:
            continue
        slots = {}
        for n in range(1, 6):
            weapon = game.get(f"weaponname{n}", "").lower()
            if weapon in weapons:
                slots[n] = (weapon, game.get(f"weaponhard{n}", ""))
        if slots:
            crafts[path.stem.lower()] = {"model": game.get("basename", path.stem).lower(),
                                         "section": "craftclass" in data, "slots": slots}
    return crafts


def _quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw*bx+ax*bw+ay*bz-az*by, aw*by-ax*bz+ay*bw+az*bx,
            aw*bz+ax*by-ay*bx+az*bw, aw*bw-ax*bx-ay*by-az*bz)


def _rotate(q, v):
    x, y, z, w = q
    # v' = v + 2w(q x v) + 2 q x (q x v)
    cx, cy, cz = y*v[2]-z*v[1], z*v[0]-x*v[2], x*v[1]-y*v[0]
    dx, dy, dz = y*cz-z*cy, z*cx-x*cz, x*cy-y*cx
    return (v[0]+2*(w*cx+dx), v[1]+2*(w*cy+dy), v[2]+2*(w*cz+dz))


def _conj(q):
    return (-q[0], -q[1], -q[2], q[3])


def bone_world(skeleton, index):
    """Bind-pose world (position, orientation) of a bone; scaled bones are rejected."""
    chain = []
    while index is not None:
        chain.append(skeleton.bones[index])
        index = chain[-1].parent
    pos, rot = (0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0)
    for bone in reversed(chain):
        if any(abs(s-1) > 1e-4 for s in (bone.scale or (1, 1, 1))):
            raise ValueError(f"bone {bone.name} is scaled")
        step = _rotate(rot, bone.position)
        pos = (pos[0]+step[0], pos[1]+step[1], pos[2]+step[2])
        rot = _quat_mul(rot, bone.orientation)
    return pos, rot


def game_models():
    """Index the installed game's Ogre meshes/skeletons (including the TRO subfolder) by name."""
    return {p.name.lower(): p for p in (GAME / "BZ_ASSETS/common/models").rglob("*")
            if p.suffix.lower() in (".mesh", ".skeleton")}


def model_files(name, assets, installed):
    """Return (mesh, skeleton) paths: shipped CR resource first, then the game install."""
    return [assets.get(name + ext) or installed.get(name + ext) for ext in (".mesh", ".skeleton")]


def shipped_assets():
    lock = json.loads((ROOT / "Shipping/shipping.lock.json").read_text())
    return {Path(e["runtime"]).name.lower(): ROOT / Path(e["source"].replace("\\", "/"))
            for e in lock["files"] if Path(e["runtime"]).suffix.lower() in (".mesh", ".skeleton")}


def barrel_vertices(mesh, bone_index):
    """Positions of every vertex mostly weighted to one bone (bind-pose model space)."""
    out = []
    for sub in mesh.submeshes:
        if sub.uses_shared_vertices or sub.geometry is None:
            continue
        geo = sub.geometry
        element = next(e for e in geo.elements if e.semantic == 1)
        buf = geo.buffers[element.source]
        ids = {a[0] for a in sub.bone_assignments if a[1] == bone_index and a[2] >= 0.5}
        for i in ids:
            out.append(struct.unpack_from("<3f", buf.data, i*buf.vertex_size + element.offset))
    return out


def measure_slot(mesh, skeleton, hardpoint):
    """Offset (right, up, forward) from a hardpoint bone to its barrel's aperture centre.

    Returns (offset, detail) or (None, reason). Forward is the barrel's furthest
    vertex along the barrel frame's +Z; right/up is the centre of the bounding box of
    the front TIP_SLAB metres of the barrel (verified against the live avtank fit
    0.20 0.10 2.41). Ogre bone space is already the mirrored X that "right" uses.
    """
    matches = [b for b in skeleton.bones if hardpoint and b.name.lower().endswith(hardpoint.lower())]
    if len(matches) != 1:
        return None, f"hardpoint {hardpoint!r} matches {len(matches)} skeleton bones"
    hp = matches[0]
    if hp.parent is None:
        return None, "hardpoint has no parent bone"
    barrel = skeleton.bones[hp.parent]
    if not re.search(r"bg[a-z0-9]$", barrel.name, re.I):
        return None, f"parent {barrel.name} is not a dedicated barrel node"
    # The sim hardpoint shares its barrel's frame (the legacy VDF matrices are identity);
    # an Ogre hardpoint bone may carry an exporter axis fix, so only its position is used.
    hp_pos, _ = bone_world(skeleton, hp.handle)
    _, frame = bone_world(skeleton, barrel.handle)
    verts = barrel_vertices(mesh, barrel.handle)
    if len(verts) < 8:
        return None, f"barrel {barrel.name} has only {len(verts)} weighted vertices"
    local = [_rotate(_conj(frame), (v[0]-hp_pos[0], v[1]-hp_pos[1], v[2]-hp_pos[2])) for v in verts]
    tip = max(p[2] for p in local)
    slab = [p for p in local if p[2] >= tip - TIP_SLAB]
    right = (min(p[0] for p in slab) + max(p[0] for p in slab)) / 2
    up = (min(p[1] for p in slab) + max(p[1] for p in slab)) / 2
    offset = [round(right, 2) + 0.0, round(up, 2) + 0.0, round(tip, 2) + 0.0]
    if tip < MIN_TIP:
        return None, f"visible tip is {tip:.2f} m from the hardpoint (under {MIN_TIP} m)"
    if any(abs(x) > 20 for x in offset):
        return None, f"offset {offset} outside OpenShim's +/-20 m bounds"
    return offset, {"hardpoint": hp.name, "barrel": barrel.name, "vertices": len(verts)}


def measure(odf_dir, config):
    """Measure every flash-carrying craft slot from the game's Ogre meshes/skeletons."""
    sys.path.insert(0, str(toolbox_root()))
    from battlezone.meshes import ogre as codec
    from battlezone.meshes.ogre_skeleton import read_skeleton
    assets, installed, cache, crafts = shipped_assets(), game_models(), {}, {}
    for craft, info in craft_slots(odf_dir, flash_weapons(config)).items():
        entry = {"model": info["model"], "slots": {}}
        crafts[craft] = entry
        if not info["section"]:
            for n, (weapon, hard) in info["slots"].items():
                entry["slots"][str(n)] = {"weapon": weapon, "skip": "no [CraftClass] section (OpenShim reads flashOffset<N> there only)"}
            continue
        model = info["model"]
        if model not in cache:
            mesh_path, skel_path = model_files(model, assets, installed)
            cache[model] = None if not (mesh_path and skel_path) else (
                codec.read_mesh(mesh_path.read_bytes()), read_skeleton(skel_path))
        for n, (weapon, hard) in info["slots"].items():
            row = {"weapon": weapon}
            entry["slots"][str(n)] = row
            if cache[model] is None:
                row["skip"] = f"no Ogre mesh/skeleton for model {model}"
                continue
            offset, detail = measure_slot(*cache[model], hard)
            if offset is None:
                row["skip"] = detail
            else:
                row.update(offset=offset, **detail)
    return {"method": "Tools/Build-WeaponFlashes.py --measure: forward = barrel tip along hardpoint +Z; "
                      f"right/up = centre of the front {TIP_SLAB} m of the barrel's weighted vertices", "crafts": crafts}


def authored_craft_odf(source, craft, entry):
    """Rewrite one craft ODF so its generated flashOffset<N> block matches the data."""
    text = source.replace("\r\n", "\n")
    if CRAFT_BEGIN in text:
        a = text.index(CRAFT_BEGIN)
        b = text.index(CRAFT_END, a) + len(CRAFT_END)
        if text[b:b+1] == "\n":
            b += 1
        text = text[:a] + text[b:]
    keys = [(int(n), row["offset"]) for n, row in sorted(entry["slots"].items()) if "offset" in row]
    if not keys:
        return text
    section = re.search(r"(?im)^[ \t]*\[CraftClass\][^\n]*\n", text)
    assert section, craft + ": missing CraftClass section"
    lines = [CRAFT_BEGIN, "// Visible barrel tip from the hardpoint (right up forward, metres); replaces the",
             "// weapon's flashOffset for this craft. Regenerate: Tools/Build-WeaponFlashes.py --measure"]
    lines += [f'flashOffset{n} = "{o[0]:.2f} {o[1]:.2f} {o[2]:.2f}"' for n, o in keys]
    lines.append(CRAFT_END)
    return text[:section.end()] + "\n".join(lines) + "\n" + text[section.end():]


def craft_outputs(config):
    """{path: bytes} for craft ODFs, after verifying the data covers every flash slot."""
    data = json.loads(OFFSETS.read_text())["crafts"]
    live = craft_slots(ROOT / "ODF", flash_weapons(config))
    outputs = {}
    for craft, info in live.items():
        entry = data.get(craft)
        assert entry, f"{craft}: flash-carrying craft missing from {OFFSETS.name}; run --measure"
        for n, (weapon, hard) in info["slots"].items():
            row = entry["slots"].get(str(n))
            assert row and row["weapon"] == weapon, f"{craft} slot {n}: weapon changed to {weapon}; run --measure"
    for craft, entry in data.items():
        assert craft in live, f"{craft}: no longer a flash-carrying craft; run --measure"
        target = ROOT / "ODF" / (craft + ".odf")
        outputs[target] = authored_craft_odf(target.read_text(), craft, entry).encode()
    # A stale generated block on an ODF that dropped out of the data would otherwise linger.
    for path in (ROOT / "ODF").glob("*.odf"):
        if path not in outputs and CRAFT_BEGIN in path.read_text(errors="replace"):
            outputs[path] = authored_craft_odf(path.read_text(), path.stem, {"slots": {}}).encode()
    return outputs


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
    outputs.update(craft_outputs(config))
    for path,data in outputs.items():
        if check:
            existing=path.read_bytes()
            if path.suffix in ('.odf','.material'): existing=existing.replace(b'\r\n',b'\n')
            assert existing==data, str(path.relative_to(ROOT))+' differs; regenerate'
        else:
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    craft_n=sum(1 for p in outputs if CRAFT_BEGIN in outputs[p].decode(errors="replace"))
    print(f"Weapon flashes: {len(profiles)} profiles, {len(outputs)-len(profiles)-1} ODFs ({craft_n} with craft flashOffset keys); mesh round trips pass")


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stock',type=Path,default=ROOT/'ODF',help='shipping StockODFFiles for initial creation; --check uses shipped overrides')
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--measure',action='store_true',help='re-measure craft barrel tips from the installed game meshes (BZR_GAME_DIR) and rewrite craft-flash-offsets.json')
    args=parser.parse_args()
    if args.measure:
        cfg=json.loads((ROOT/'References/WeaponPresentation/profiles.json').read_text())
        OFFSETS.write_text(json.dumps(measure(ROOT/'ODF',cfg),indent=2)+'\n')
    build(args.stock,args.check)
