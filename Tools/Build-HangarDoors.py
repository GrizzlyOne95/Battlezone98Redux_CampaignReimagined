"""Rebuild the NSDF (abhang) and Black Dog (bbhang) hangar door assets.

Stock defect: abhang.skeleton weights the door vertices to bones abh11dra7/abh11drb8 while
abhang.sdf drives GEOs abh11dra/abh11drb.  Redux binds an SDF GEO to the skeleton bone of the
same name, so the stock doors never move (and stock bbhang bakes its doors open).

Outputs (Assets/ModelFixes):
  abhang.skeleton  root + four door bones, bind pose = closed, hinge = SDF position key
  abhang.sdf       doors keyed on every frame, closed -> open (ease in/out, shortest-path quaternions)
  bbhang.mesh      abhang's closed-door geometry with the Black Dog material, exterior pad removed
  bbhang.skeleton  same bones as abhang (stock bbhang.sdf also names its GEOs abh11*)
  bbhang.sdf       abhang's SDF without the pad GEO; doors start OPEN and swing CLOSED over element 0
                   (2 s), ending on the closed bind pose so they hold closed

abhang.mesh is not touched.  Needs the bz98tools OgreXMLConverter (Blender add-on, MeshSerializer
v1.100) via OGRE_XML_CONVERTER or %APPDATA%\\Blender Foundation\\Blender\\*\\scripts\\addons\\bz98tools.
"""
import glob
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / 'Assets' / 'ModelFixes'

FRAMES = 121            # element 0: start 0, length 121 at speed 60 = 2.0 s (unchanged)
# SDF door GEO -> (skeleton bone id, SDF hinge position, closed yaw, open yaw), yaw in degrees
# about +Y.  The hinge is the old stock bone position (the SDF position key); the open yaw is
# the stock mesh's baked bind rotation, so the open pose equals the stock open doors.  Every
# yaw is unwrapped so the sweep is the short way round (drd: 180 -> 313.49, not 180 -> -46.51).
DOORS = {
    'dra': (1, (8.32074, 5.06648, 14.5155), 0.0, -136.93),
    'drd': (2, (-8.32075, 5.12826, 14.5155), 180.0, 313.49),
    'drc': (3, (-8.32074, 4.5104, -14.5155), 180.0, 45.36),
    'drb': (4, (8.32074, 4.9429, -14.5155), 0.0, 139.23),
}


def smooth(t):
    return t * t * (3.0 - 2.0 * t)


def yaw_key(deg):
    h = math.radians(deg) / 2.0
    return (math.cos(h), 0.0, math.sin(h), 0.0)   # SDF (w, x, y, z)


def converter():
    p = os.environ.get('OGRE_XML_CONVERTER')
    if p and os.path.exists(p):
        return p
    hits = sorted(glob.glob(os.path.join(os.environ.get('APPDATA', ''), 'Blender Foundation', 'Blender', '*',
                                         'scripts', 'addons', 'bz98tools', 'ogretools', 'OgreXMLConverter.exe')))
    if not hits:
        sys.exit('OgreXMLConverter (bz98tools) not found; set OGRE_XML_CONVERTER')
    return hits[-1]


def skeleton_xml(prefix):
    bones = [f'<bone id="0" name="{prefix}bbb"><position x="0" y="0" z="0" />'
             '<rotation angle="0"><axis x="1" y="0" z="0" /></rotation></bone>']
    for name, (bid, p, y0, _) in DOORS.items():
        ang = '0' if y0 == 0.0 else repr(math.pi)
        axis = '<axis x="1" y="0" z="0" />' if y0 == 0.0 else '<axis x="0" y="1" z="0" />'
        # Ogre skeleton space mirrors SDF X.
        bones.append(f'<bone id="{bid}" name="{prefix}{name}"><position x="{-p[0]}" y="{p[1]}" z="{p[2]}" />'
                     f'<rotation angle="{ang}">{axis}</rotation></bone>')
    parents = ''.join(f'<boneparent bone="{prefix}{n}" parent="{prefix}bbb" />' for n in DOORS)
    return ('<skeleton blendmode="average"><bones>' + ''.join(bones) + '</bones><bonehierarchy>' + parents +
            '</bonehierarchy><animations /></skeleton>')


def convert(conv, src_xml, dst, work):
    src = work / Path(dst).name
    src_xml_path = work / (Path(dst).name + '.xml')
    src_xml_path.write_text(src_xml, encoding='utf-8')
    src.unlink(missing_ok=True)
    # The converter can fault after writing; judge it by the output file.
    subprocess.run([conv, '-q', str(src_xml_path), str(src)], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, cwd=work)
    if not src.exists() or src.stat().st_size == 0:
        sys.exit(f'OgreXMLConverter produced no {src.name}')
    shutil.copyfile(src, dst)


# ---- SDF rewrite (layout: SDFHeader 20, SDFC 78, SGEO 12 + 6*count*120, ANIM 72 + tables, EXIT) ----
def build_sdf(data, opening, drop_pad):
    """Return the SDF with every-frame door keys.

    opening=True: closed -> open (abhang). opening=False: open -> closed, ending on the closed
    bind pose (bbhang). drop_pad removes the abh11lot GEO (the exterior ground pad), which must be
    the last GEO and own the last position keys."""
    geo_at = 20 + 78
    sgeo = list(struct.unpack_from('<4sIi', data, geo_at))
    gc = sgeo[2]
    geos = [[data[geo_at + 12 + (b * gc + i) * 120:geo_at + 12 + (b * gc + i + 1) * 120] for i in range(gc)]
            for b in range(6)]
    a = geo_at + 12 + 6 * gc * 120
    hdr = list(struct.unpack_from('=4si16s5ii6i', data, a))
    n_el, n_or, n_rot, n_t2, n_pos = hdr[3:8]
    o = a + 72
    elements = data[o:o + n_el * 148]
    o += n_el * 148
    ors = [list(struct.unpack_from('=8si12f12f6i', data, o + i * 132)) for i in range(n_or)]
    o += n_or * 132
    rots = [struct.unpack_from('=i4f', data, o + i * 20) for i in range(n_rot)]
    o += n_rot * 20
    t2 = data[o:o + n_t2 * 16]
    o += n_t2 * 16
    poss = data[o:o + n_pos * 16]
    rest = data[o + n_pos * 16:]
    if drop_pad:
        assert ors[-1][0].rstrip(b'\0') == b'abh11lot' and geos[0][-1][:8].rstrip(b'\0') == b'abh11lot'
        lot = ors.pop()
        assert lot[30] + lot[31] == n_pos and lot[29] == 0
        poss = poss[:lot[30] * 16]
        n_pos = lot[30]
        for b in range(6):
            geos[b].pop()
        gc -= 1
        sgeo[2] = gc
        sgeo[1] = 12 + 6 * gc * 120
    n_or = len(ors)
    new_rots = []
    for r in ors:
        name = r[0].rstrip(b'\0').decode('ascii')
        old = rots[r[26]:r[26] + r[27]]
        short = name[-3:]
        if name.startswith('abh11') and short in DOORS and name[5:] == short:
            y0, y1 = DOORS[short][2], DOORS[short][3]
            if not opening:
                y0, y1 = y1, y0
            old = [(f,) + tuple(yaw_key(y0 + (y1 - y0) * smooth(f / (FRAMES - 1)))) for f in range(FRAMES)]
        r[26] = len(new_rots)
        r[27] = len(old)
        new_rots.extend(old)
    hdr[1] = 72 + n_el * 148 + n_or * 132 + len(new_rots) * 20 + n_t2 * 16 + n_pos * 16
    hdr[3:8] = [n_el, n_or, len(new_rots), n_t2, n_pos]
    out = bytearray(data[:geo_at])
    out += struct.pack('<4sIi', *sgeo)
    for b in range(6):
        out += b''.join(geos[b])
    out += struct.pack('=4si16s5ii6i', *hdr)
    out += elements
    for r in ors:
        out += struct.pack('=8si12f12f6i', *r)
    for k in new_rots:
        out += struct.pack('=i4f', *k)
    out += t2 + poss + rest
    return bytes(out)


# The pad is the flat slab in front of the hangar (stock bone/GEO "lot"): y 0.006..0.308,
# z 15.05..32.03, |x| <= 8.27.  Every vertex of its faces lies in this box.
PAD_MIN = (-8.28, 0.0, 15.04)
PAD_MAX = (8.28, 0.32, 32.04)
PAD_FACES, PAD_VERTS = 178, 534      # asserted so a changed mesh fails loudly


def drop_pad_from_mesh_xml(xml):
    """Remove the pad faces and the vertices only they use from a one-submesh mesh XML."""
    import xml.etree.ElementTree as ET
    root = ET.fromstring(xml)
    sub = root.find('submeshes')[0]
    vb = sub.find('geometry/vertexbuffer')
    verts = vb.findall('vertex')
    pos = [tuple(float(v.find('position').get(c)) for c in 'xyz') for v in verts]
    in_box = [all(PAD_MIN[i] <= p[i] <= PAD_MAX[i] for i in range(3)) for p in pos]
    faces = sub.find('faces')
    all_faces = faces.findall('face')
    kept = []
    for f in all_faces:
        if not all(in_box[int(f.get(k))] for k in ('v1', 'v2', 'v3')):
            kept.append(f)
    removed = len(all_faces) - len(kept)
    for f in all_faces:
        if f not in kept:
            faces.remove(f)
    faces.set('count', str(len(kept)))
    used = sorted({int(f.get(k)) for f in kept for k in ('v1', 'v2', 'v3')})
    remap = {old: new for new, old in enumerate(used)}
    for buf in sub.findall('geometry/vertexbuffer'):      # positions and normals may sit in separate buffers
        bverts = buf.findall('vertex')
        assert len(bverts) == len(verts)
        for i, v in enumerate(bverts):
            if i not in remap:
                buf.remove(v)
    for f in kept:
        for k in ('v1', 'v2', 'v3'):
            f.set(k, str(remap[int(f.get(k))]))
    ba = sub.find('boneassignments')
    for b in list(ba):
        vi = int(b.get('vertexindex'))
        if vi in remap:
            b.set('vertexindex', str(remap[vi]))
        else:
            ba.remove(b)
    sub.find('geometry').set('vertexcount', str(len(used)))
    dropped = len(verts) - len(used)
    assert (removed, dropped) == (PAD_FACES, PAD_VERTS), (removed, dropped)
    return ET.tostring(root, encoding='unicode')


def main():
    conv = converter()
    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        # Both hangars use abh11* bone/GEO names: stock bbhang.sdf also names its GEOs abh11*, so
        # the existing abh11*.geo collision files apply and no new GEO files are needed.
        convert(conv, skeleton_xml('abh11'), FIX / 'abhang.skeleton', work)
        convert(conv, skeleton_xml('abh11'), FIX / 'bbhang.skeleton', work)
        # bbhang.mesh: abhang's closed-door mesh without the pad, Black Dog material and skeleton.
        shutil.copyfile(FIX / 'abhang.mesh', work / 'abhang.mesh')
        shutil.copyfile(FIX / 'abhang.skeleton', work / 'abhang.skeleton')
        subprocess.run([conv, '-q', str(work / 'abhang.mesh'), str(work / 'abhang.mesh.xml')],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=work)
        xml = (work / 'abhang.mesh.xml').read_text(encoding='utf-8')
        assert 'material="abhang00"' in xml and '<skeletonlink name="abhang.skeleton" />' in xml
        xml = xml.replace('material="abhang00"', 'material="bbhang"')
        xml = xml.replace('<skeletonlink name="abhang.skeleton" />', '<skeletonlink name="bbhang.skeleton" />')
        xml = drop_pad_from_mesh_xml(xml)
        shutil.copyfile(FIX / 'bbhang.skeleton', work / 'bbhang.skeleton')
        convert(conv, xml, FIX / 'bbhang.mesh', work)
    # abhang: doors open on creation (closed -> open), pad kept.
    abh = build_sdf((FIX / 'abhang.sdf').read_bytes(), True, False)
    (FIX / 'abhang.sdf').write_bytes(abh)
    # bbhang: same SDF without the pad GEO; doors start open and swing closed, holding closed.
    (FIX / 'bbhang.sdf').write_bytes(build_sdf(abh, False, True))
    print('hangar assets rebuilt')


if __name__ == '__main__':
    main()
