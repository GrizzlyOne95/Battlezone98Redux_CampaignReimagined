"""Extract Resurgence's docked CCA rocket for the local Mars film prototype.

Usage: python Tools/Build-Misn06Rocket.py <Resurgence addon directory>
Retains the rocket's UVs, normals and triangles. Removes the pad and bones,
centres the model on the rocket, and namespaces every installed resource.
No Blender or native library is required. Art comes from GrizzlyOne95's
Battlezone: Resurgence asset pack; see Docs/MISN06_ROCKET_FILM.md for credits
and the author's reuse statement.
"""
from pathlib import Path
import argparse, hashlib, json, shutil, struct

ROOT = Path(__file__).resolve().parents[1]

def chunk(kind, body):
    return struct.pack('<HI', kind, len(body) + 6) + body

def chunks(data, start, stop):
    while start < stop:
        kind, size = struct.unpack_from('<HI', data, start)
        assert size >= 6 and start + size <= stop
        yield kind, start, start + size
        start += size

def build(source):
    name = 'cr06rok'
    mesh = (source / 'sblpada.mesh').read_bytes()
    header_end = mesh.index(b'\n') + 1
    assert mesh[2:header_end] == b'[MeshSerializer_v1.100]\n'
    body = bytearray(b'\x00')  # static, no skeleton
    centre = (-20.546749114990234, 77.06172180175781, 43.21162986755371)
    nsub = 0
    for kind, start, stop in chunks(mesh, header_end + 7, len(mesh)):
        if kind != 0x4000:
            continue
        eol = mesh.index(b'\n', start + 6)
        material = mesh[start + 6:eol]
        if not material.endswith(b'_sbtrans'):
            continue
        nsub += 1
        p = eol + 1
        shared, count, wide = struct.unpack_from('<?I?', mesh, p)
        assert not shared
        p += 6 + count * (4 if wide else 2)
        sub = bytearray(b'cr06rok00\n' + mesh[eol + 1:p])
        for cid, cs, ce in chunks(mesh, p, stop):
            if cid == 0x4100:  # strip bone assignments
                continue
            if cid != 0x5000:
                sub += mesh[cs:ce]
                continue
            geom = bytearray(mesh[cs + 6:cs + 10])
            vertices = struct.unpack_from('<I', mesh, cs + 6)[0]
            position_source, position_offset = None, None
            for gid, gs, ge in chunks(mesh, cs + 10, ce):
                if gid == 0x5100:
                    for _, es, ee in chunks(mesh, gs + 6, ge):
                        source_id, vtype, semantic, offset, index = struct.unpack_from('<5H', mesh, es + 6)
                        if semantic == 1:
                            assert vtype == 2
                            position_source, position_offset = source_id, offset
            assert position_source is not None
            for gid, gs, ge in chunks(mesh, cs + 10, ce):
                if gid != 0x5200:
                    geom += mesh[gs:ge]
                    continue
                bind, stride = struct.unpack_from('<HH', mesh, gs + 6)
                if bind != position_source:
                    geom += mesh[gs:ge]
                    continue
                assert stride >= 12
                vb = bytearray(mesh[gs + 6:gs + 10])
                for did, ds, de in chunks(mesh, gs + 10, ge):
                    assert did == 0x5210
                    raw = bytearray(mesh[ds + 6:de])
                    assert len(raw) == vertices * stride
                    for i in range(vertices):
                        xyz = struct.unpack_from('<3f', raw, i * stride + position_offset)
                        struct.pack_into('<3f', raw, i * stride + position_offset, *(a-b for a,b in zip(xyz,centre)))
                    vb += chunk(did, raw)
                geom += chunk(gid, vb)
            sub += chunk(cid, geom)
        body += chunk(kind, sub)
    assert nsub == 1
    bounds = (-14.136, -48.515, -14.996, 14.136, 48.515, 14.996, 53.0)
    body += chunk(0x9000, struct.pack('<7f', *bounds))
    target = ROOT / 'Assets/ModelFixes'
    (target / (name + '.mesh')).write_bytes(mesh[:header_end] + chunk(0x3000, body))
    sdf = bytearray((source / 'sblpada.sdf').read_bytes())
    sgeo = sdf.index(b'SGEO')
    native = bytearray(sdf[sgeo + 12 + 120:sgeo + 12 + 240])
    native[:8] = name.encode().ljust(8, b'\0')
    struct.pack_into('<12f', native, 8, 1,0,0,0,1,0,0,0,1,0,0,0)
    native[56:64] = b'WORLD\0\0\0'
    sdf[28:44] = name.encode().ljust(16, b'\0')
    struct.pack_into('<5f', sdf, 48, 2000, 1e20, 1e20, 1e20, 1e20)
    struct.pack_into('<i', sdf, sgeo + 8, 1)
    null = bytearray(120); null[:8] = b'NULL\0\0\0\0'
    sdf[sgeo + 12:sgeo + 1452] = native + null * 11
    (target / (name + '.sdf')).write_bytes(sdf)
    shutil.copyfile(source / 'str11rok.geo', target / (name + '.geo'))
    textures = ['BaseMap', 'Normal', 'Specular', 'Emissive']
    for suffix, short in zip(textures, ['d', 'n', 's', 'e']):
        shutil.copyfile(source / ('svtrans_DefaultMaterial_' + suffix + '.dds'),
                        ROOT / 'Assets/Textures' / (name + '_' + short + '.dds'))
    paths = ['sblpada.mesh', 'sblpada.sdf', 'str11rok.geo'] + [
        'svtrans_DefaultMaterial_' + t + '.dds' for t in textures]
    print(json.dumps({'source': 'Resurgence installed addon', 'rocket_triangles': count // 3,
        'pad_local_centre': centre, 'sha256': {p: hashlib.sha256((source/p).read_bytes()).hexdigest() for p in paths}}, indent=2))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    build(parser.parse_args().source)
