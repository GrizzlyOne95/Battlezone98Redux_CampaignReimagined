"""Write block-compressed DDS files with a full offline mip chain via texconv.

The native DX11 renderer cannot generate mips for compressed textures, so a BCn
DDS without mips samples uninitialised levels and renders black. texconv
(DirectXTex) writes legacy DXT1/DXT5 headers and the whole chain.
Set CR_TEXCONV to texconv.exe, or install XnViewMP in its default location.
"""
import os
from pathlib import Path
import subprocess
import tempfile

_DEFAULT = Path(r'C:\Program Files\XnViewMP\plugins\texconv.exe')


def texconv_path():
    path = Path(os.environ.get('CR_TEXCONV') or _DEFAULT)
    if not path.is_file():
        raise SystemExit(f'texconv not found at {path}; set CR_TEXCONV to texconv.exe (DirectXTex).')
    return path


def save_bc(image, dest, fmt='BC1_UNORM'):
    """Save a Pillow image as `dest` in fmt (BC1_UNORM, or BC3_UNORM for real alpha) with full mips."""
    dest = Path(dest)
    texconv = texconv_path()
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / dest.name
        image.convert('RGBA').save(src)
        out = Path(tmp) / 'out'
        out.mkdir()
        subprocess.run([str(texconv), '-nologo', '-f', fmt, '-m', '0', '-y', '-o', str(out), str(src)],
                       check=True, stdout=subprocess.DEVNULL)
        dest.write_bytes((out / dest.name).read_bytes())


def bc_dds_problem(raw, width, height=None, fourcc=b'DXT1'):
    """Return why `raw` is not a legacy-header BCn DDS with a full mip chain, or None if it is."""
    import struct
    height = height or width
    if raw[:4] != b'DDS ':
        return 'not a DDS'
    h, w, _, _, mips = struct.unpack_from('<5I', raw, 12)
    if (w, h) != (width, height):
        return f'size {w}x{h}, expected {width}x{height}'
    if struct.unpack_from('<I', raw, 80)[0] & 4 == 0 or raw[84:88] != fourcc:
        return f'FourCC {raw[84:88]!r}, expected {fourcc!r}'
    full = max(width, height).bit_length()
    if mips != full:
        return f'{mips} mips, expected the full chain of {full}'
    block = 8 if fourcc == b'DXT1' else 16
    expected = 128 + sum(block * max(1, (width >> i) + 3 >> 2) * max(1, (height >> i) + 3 >> 2) for i in range(full))
    if len(raw) != expected:
        return f'{len(raw)} bytes, expected {expected}'
    return None
