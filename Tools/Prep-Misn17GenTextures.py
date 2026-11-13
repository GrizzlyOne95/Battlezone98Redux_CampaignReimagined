"""Turn the owner's generated misn17 rock and water images into TextureRevamp masters.

    python Tools/Prep-Misn17GenTextures.py

Inputs (References/TextureRevamp/raw):
  cr17_frock_gen.jpg      owner-generated mossy granite, 1125^2 (2026-11-13)
  cr17_water_gen.jpg      owner-generated dark river surface, 2000^2, lit top-to-bottom
  cr17_frock_pack.png     the forest pack's baked rock atlas (cr17_frock.dds before this pass)
  cr17_frock_pack_n.png   its DirectX normal map (cr17_frock_n.dds before this pass)
  cr17_fbranch1_gen.jpg   owner-generated spruce sprigs on white, 1500^2
  cr17_fbranch2_gen.jpg   owner-generated autumn birch sprigs on white, 2000^2
  cr17_fbranch?_pack.png  the pack's 512^2 branch-card atlases (the card layout)
  Assets/Models/cr17_frock*.mesh (9 rocks), read through the toolkit serializer (unchanged)

Outputs (References/TextureRevamp), compiled by Tools/Build-TextureRevamp.py:
  frock.png         2048^2 rock atlas
  frock_normal.png  2048^2 DirectX normal: pack normal + new surface detail
  frock_spec.png    2048^2 grey specular: dull stone, moss duller
  water.png         1024^2 grey ripple map, seamless, for the CR17 water shader
  fbranch1.png, fbranch2.png  2048^2 RGBA branch-card atlases (sprigs refit to the pack layout)

Rock: cr17_frock is an atlas of baked rock islands (one set per mesh; a few
rocks share some texels), not a tiling texture. The new image is made
seamless, then projected onto each shipped rock in object space (triplanar,
one tile per TILE_M metres, weights from the vertex normals) and written into
that rock's own UV islands, so the meshes are unchanged and nothing seams at
UV chart edges. The pack atlas's blurred luminance is kept as shading, so the
baked high-poly form survives; its normal map gets the new detail added
(UDN blend). Height for the detail is luminance (crevices dark, faces light).

Water: the shader tints the diffuse with $waterColour and derives its bump from
the luminance, so the master is grey. The source's lighting gradient is removed
and the result matched to the old water256 level (mean 123, contrast a little
above its std 11) so the tints stay as tuned. It is a plain tile.

Seamless: crossfade tiling. The last 12% of each axis fades into the first,
so the tile wraps cleanly (the source's spare pixels fund the overlap).
"""
from pathlib import Path
import importlib.util
import io
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Tools'))
from bzmodellibs import ogremesh as om, ogremesh_serializer as oms  # noqa: E402

REF = ROOT / 'References/TextureRevamp'
RAW = REF / 'raw'
ATLAS = 2048
TILE_M = 1.5          # metres of rock surface per tile repeat
ROCKS = sorted(p.name for p in (ROOT / 'Assets/Models').glob('cr17_frock*.mesh'))  # all CR17/ForestRock meshes


def seamless(a, band=0.12):
    """Crossfade tile: the last `band` of each axis fades into the first, so
    the result (smaller by the band) wraps with no seam. a is (H, W, C) float."""
    for axis in (1, 0):
        n = a.shape[axis]
        b = int(band * n)
        keep = n - b
        t = np.linspace(0, 1, b, dtype=np.float32)
        t = t * t * (3 - 2 * t)
        shape = [1, 1, 1]
        shape[axis] = b
        t = t.reshape(shape)
        head = np.take(a, range(b), axis=axis)
        tail = np.take(a, range(keep, n), axis=axis)
        a = np.take(a, range(keep), axis=axis).copy()
        idx = [slice(None)] * 3
        idx[axis] = slice(0, b)
        a[tuple(idx)] = tail * (1 - t) + head * t
    return a


def values(vd, semantic):
    el = vd.vertex_declaration.find_by_semantic(semantic)
    vb = vd.get_vertex_buffer(el.source)
    return np.ndarray((vd.vertex_count, el.get_type_count()), '<f4', buffer=vb.buffer, offset=el.offset,
                      strides=(vb.vertex_size, 4)).astype(np.float64)


def load(name):
    """(pos, nrm, uv, tris) per submesh of a shipped mesh, via the toolkit."""
    mesh = oms.MeshSerializer(io.BytesIO((ROOT / 'Assets/Models' / name).read_bytes())).read()
    out = []
    for sub in mesh.submesh_list:
        vd = sub.vertex_data if sub.vertex_data is not None else mesh.shared_vertex_data
        out.append((values(vd, om.VES.POSITION)[:, :3], values(vd, om.VES.NORMAL)[:, :3],
                    values(vd, om.VES.TEXTURE_COORDINATES)[:, :2],
                    np.asarray(sub.get_index_array()).astype(np.int64).reshape(-1, 3)))
    return out


def uv_area(parts):
    total = 0.0
    for _, _, uv, tris in parts:
        a, b, c = uv[tris[:, 0]], uv[tris[:, 1]], uv[tris[:, 2]]
        total += np.abs((b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (c[:, 0] - a[:, 0]) * (b[:, 1] - a[:, 1])).sum() / 2
    return total


def rasterize(names):
    """Object-space position and normal for every atlas texel a rock covers.

    Where rocks share texels (rock 4 reuses part of rock 2), the rock with the
    larger UV area is written last and keeps them, so only the small rock
    shows a mismatched patch."""
    meshes = sorted((load(name) for name in names), key=uv_area)
    pos_map = np.zeros((ATLAS, ATLAS, 3))
    nrm_map = np.zeros((ATLAS, ATLAS, 3))
    cover = np.zeros((ATLAS, ATLAS), bool)
    for parts in meshes:
        for pos, nrm, uv, tris in parts:
            uv = uv * ATLAS - 0.5   # texel-centre space
            for tri in tris:
                a, b, c = uv[tri]
                x0, y0 = np.floor(np.minimum(np.minimum(a, b), c)).astype(int) - 1
                x1, y1 = np.ceil(np.maximum(np.maximum(a, b), c)).astype(int) + 1
                x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, ATLAS - 1), min(y1, ATLAS - 1)
                gy, gx = np.mgrid[y0:y1 + 1, x0:x1 + 1]
                den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
                if abs(den) < 1e-12:
                    continue
                w0 = ((b[1] - c[1]) * (gx - c[0]) + (c[0] - b[0]) * (gy - c[1])) / den
                w1 = ((c[1] - a[1]) * (gx - c[0]) + (a[0] - c[0]) * (gy - c[1])) / den
                w2 = 1 - w0 - w1
                inside = (w0 >= -1e-3) & (w1 >= -1e-3) & (w2 >= -1e-3)
                if not inside.any():
                    continue
                bary = np.stack([w0[inside], w1[inside], w2[inside]], -1)
                yy, xx = gy[inside], gx[inside]
                pos_map[yy, xx] = bary @ pos[tri]
                # Half face normal: smooth vertex normals alone pick an edge-on
                # projection plane on big flat facets and the texture streaks.
                face = np.cross(pos[tri[1]] - pos[tri[0]], pos[tri[2]] - pos[tri[0]])
                vn = bary @ nrm[tri]
                if face @ vn.mean(0) < 0:
                    face = -face
                face /= max(np.linalg.norm(face), 1e-12)
                vn /= np.maximum(np.linalg.norm(vn, axis=-1, keepdims=True), 1e-12)
                nrm_map[yy, xx] = vn + face
                cover[yy, xx] = True
    nrm_map /= np.maximum(np.linalg.norm(nrm_map, axis=-1, keepdims=True), 1e-9)
    return pos_map, nrm_map, cover


def sample(img, u, v):
    """Bilinear sample of a tiling (H, W, C) image at pixel coordinates (wrap)."""
    h, w = img.shape[:2]
    u0 = np.floor(u).astype(int)
    v0 = np.floor(v).astype(int)
    fu = (u - u0)[:, None]
    fv = (v - v0)[:, None]
    u0 %= w
    v0 %= h
    u1 = (u0 + 1) % w
    v1 = (v0 + 1) % h
    return ((img[v0, u0] * (1 - fu) + img[v0, u1] * fu) * (1 - fv)
            + (img[v1, u0] * (1 - fu) + img[v1, u1] * fu) * fv)


def triplanar(img, p, n):
    k = img.shape[0] / TILE_M
    w = np.abs(n) ** 4
    w /= w.sum(-1, keepdims=True)
    return (sample(img, p[:, 1] * k, p[:, 2] * k) * w[:, :1]
            + sample(img, p[:, 0] * k, p[:, 2] * k) * w[:, 1:2]
            + sample(img, p[:, 0] * k, p[:, 1] * k) * w[:, 2:3])


def dilate(img, cover):
    """Fill texels no rock uses with the nearest used texel (mip padding)."""
    _, (iy, ix) = ndimage.distance_transform_edt(~cover, return_indices=True)
    return img[iy, ix]


def rock():
    build = importlib.util.spec_from_file_location('texture_build', ROOT / 'Tools/Build-TextureRevamp.py')
    build_mod = importlib.util.module_from_spec(build)
    build.loader.exec_module(build_mod)

    tile = seamless(np.asarray(Image.open(RAW / 'cr17_frock_gen.jpg').convert('RGB'), np.float32))
    lum = tile @ np.array([.299, .587, .114], np.float32)
    green = tile[..., 1] - (tile[..., 0] + tile[..., 2]) / 2      # moss
    spec = np.clip(6 + lum * .06 - np.clip(green, 0, None) * .4, 2, 40)
    height = ndimage.gaussian_filter(lum, 1.5, mode='wrap')
    layers = np.concatenate([tile, height[..., None], spec[..., None]], -1)

    pos, nrm, cover = rasterize(ROCKS)
    baked = np.zeros((ATLAS, ATLAS, 5), np.float32)
    baked[cover] = triplanar(layers, pos[cover], nrm[cover])
    baked = dilate(baked, cover)

    # Keep the pack's baked form: its blurred luminance as a shading ratio.
    pack = np.asarray(Image.open(RAW / 'cr17_frock_pack.png').convert('L').resize((ATLAS, ATLAS), Image.Resampling.BILINEAR), np.float32)
    pack = ndimage.gaussian_filter(pack, 6)
    shade = np.clip((pack / pack[cover].mean()) ** 0.8, 0.45, 1.5)[..., None]
    colour = np.clip(baked[..., :3] * shade, 0, 255)
    Image.fromarray(colour.round().astype(np.uint8)).save(REF / 'frock.png')
    Image.fromarray(np.clip(baked[..., 4], 0, 255).round().astype(np.uint8)).save(REF / 'frock_spec.png')

    detail = np.asarray(build_mod.normal_from_height(Image.fromarray(np.clip(baked[..., 3], 0, 255).astype(np.uint8)), 1.2),
                        np.float32) / 127.5 - 1
    base = np.asarray(Image.open(RAW / 'cr17_frock_pack_n.png').convert('RGB').resize((ATLAS, ATLAS), Image.Resampling.BILINEAR),
                      np.float32) / 127.5 - 1
    n = np.concatenate([base[..., :2] + detail[..., :2], np.maximum(base[..., 2:], .2)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    xy = np.linalg.norm(n[..., :2], axis=-1, keepdims=True)    # cap the tilt: z >= 0.6
    n[..., :2] *= np.minimum(1, .8 / np.maximum(xy, 1e-9))
    n[..., 2] = np.sqrt(np.clip(1 - (n[..., :2] ** 2).sum(-1), 0, 1))
    Image.fromarray(np.round((n * .5 + .5) * 255).astype(np.uint8)).save(REF / 'frock_normal.png')
    return int(cover.sum())


def water():
    w = np.asarray(Image.open(RAW / 'cr17_water_gen.jpg').convert('L'), np.float32)
    w = w - ndimage.gaussian_filter(w, 60, mode='reflect')     # remove the lighting gradient
    w = w / np.maximum(ndimage.gaussian_filter(np.abs(w), 60, mode='reflect'), 1)  # even contrast
    w = seamless(w[..., None])[..., 0]
    w = (w - w.mean()) / w.std() * 14 + 122.7
    Image.fromarray(np.clip(w, 0, 255).round().astype(np.uint8)).resize((1024, 1024), Image.Resampling.LANCZOS).save(REF / 'water.png')


def sprigs(path):
    """Key the white background off a generated sprig sheet: a list of
    (RGBA float array, base (x, y)) per sprig, stem base at the lowest pixel."""
    rgb = np.asarray(Image.open(path).convert('RGB'), np.float32)
    alpha = np.clip((255 - rgb.min(-1) - 30) / 45, 0, 1)
    # Rim pixels take the colour of the nearest solid pixel: no white fringe.
    _, (iy, ix) = ndimage.distance_transform_edt(alpha < 0.95, return_indices=True)
    colour = rgb[iy, ix]
    rgba = np.concatenate([np.clip(colour, 0, 255), alpha[..., None] * 255], -1)
    lab, n = ndimage.label(ndimage.binary_closing(alpha > 0.3, iterations=3))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        piece = rgba[sl].copy()
        piece[..., 3] *= lab[sl] == i
        if (piece[..., 3] > 128).sum() < 2000:
            continue
        ys, xs = np.nonzero(piece[..., 3] > 128)
        bottom = ys.max()
        out.append((piece, (xs[ys >= bottom - 3].mean(), float(bottom))))
    return out


def place(canvas, piece, base, at, angle, length):
    """Alpha-over a sprig onto canvas: its base at `at`, its stem pointing along
    `angle` (radians, image space, 0 = up), scaled so it is `length` px long."""
    h = piece.shape[0]
    scale = length / h
    img = Image.fromarray(piece.astype(np.uint8), 'RGBA')
    img = img.resize((max(1, round(piece.shape[1] * scale)), max(1, round(h * scale))), Image.Resampling.LANCZOS)
    bx, by = base[0] * scale, base[1] * scale
    pad = int(np.hypot(*img.size)) + 2
    big = Image.new('RGBA', (2 * pad, 2 * pad))
    big.paste(img, (int(pad - bx), int(pad - by)))
    big = big.rotate(-np.degrees(angle), Image.Resampling.BICUBIC, center=(pad, pad))
    layer = Image.new('RGBA', canvas.size)
    layer.paste(big, (int(at[0] - pad), int(at[1] - pad)))
    canvas.alpha_composite(layer)
    return np.asarray(big.getchannel('A'))


BRANCH_SIZE = 2048
KEEP = {1: [(160, 275, 248, 475)]}   # 512-scale boxes: fbranch1's bare twig card


def branch(k, seed):
    """Refit the generated sprigs onto the pack's branch atlas cr17_fbranch<k>.

    The tree meshes' cards point at fixed card silhouettes, so the old atlas
    alpha is the layout: it stays as a darkened under-layer (interior shade,
    full UV coverage), and sprigs are scattered over it, each sized to the
    local card thickness and pointing out from the card's spine, then clipped
    to the card silhouette (slightly dilated) so no neighbour card is touched."""
    rng = np.random.default_rng(seed)
    S = BRANCH_SIZE
    old = Image.open(RAW / f'cr17_fbranch{k}_pack.png').convert('RGBA')
    old = np.asarray(old.resize((S, S), Image.Resampling.LANCZOS), np.float32)
    mask = ndimage.gaussian_filter(old[..., 3], 2) > 110
    twig = np.zeros((S, S), bool)            # bare-twig cards keep the pack art
    for x0, y0, x1, y1 in KEEP.get(k, ()):
        twig[y0 * S // 512:y1 * S // 512, x0 * S // 512:x1 * S // 512] = True
    twig &= old[..., 3] > 0
    mask &= ~twig
    old_lum = (old[..., :3][mask] @ np.array([.299, .587, .114])).mean()
    pieces = sprigs(RAW / f'cr17_fbranch{k}_gen.jpg')
    gain = min(1.0, old_lum * 1.55 / np.mean([(p[..., :3][p[..., 3] > 128] @ np.array([.299, .587, .114])).mean() for p, _ in pieces]))
    pieces = [(np.concatenate([p[..., :3] * gain, p[..., 3:]], -1), b) for p, b in pieces]

    under = old.copy()
    under[..., :3] *= 0.45
    under[..., 3] = np.where(mask, 255, 0)
    canvas = Image.fromarray(under.astype(np.uint8), 'RGBA')

    edt = ndimage.distance_transform_edt(mask)
    thick = ndimage.maximum_filter(edt, size=S // 12)
    smooth = ndimage.gaussian_filter(edt, S / 128)
    gy, gx = np.gradient(smooth)
    covered = np.zeros((S, S), bool)
    target = mask.sum()
    for _ in range(4000):
        if (covered & mask).sum() > 0.93 * target:
            break
        free = np.flatnonzero((mask & ~covered).ravel())
        y, x = divmod(int(free[rng.integers(free.size)]), S)
        g = np.array([gx[y, x], gy[y, x]])
        out = -g / np.linalg.norm(g) if np.linalg.norm(g) > 1e-3 else rng.normal(size=2)   # toward the card edge
        angle = np.arctan2(out[0], -out[1]) + rng.normal(0, .35)
        length = float(np.clip(3.4 * thick[y, x], S * .07, S * .28)) * rng.uniform(.85, 1.1)
        at = (x - np.sin(angle) * length * .35, y + np.cos(angle) * length * .35)
        piece, base = pieces[rng.integers(len(pieces))]
        if rng.random() < .5:   # mirror for variety
            piece = piece[:, ::-1]
            base = (piece.shape[1] - 1 - base[0], base[1])
        a = place(canvas, piece, base, at, angle, length)
        pad = a.shape[0] // 2
        y0, x0 = int(at[1] - pad), int(at[0] - pad)
        ys, xs = np.nonzero(a > 128)
        ys, xs = ys + y0, xs + x0
        keep = (ys >= 0) & (ys < S) & (xs >= 0) & (xs < S)
        covered[ys[keep], xs[keep]] = True

    result = np.asarray(canvas, np.float32).copy()
    clip = ndimage.gaussian_filter(ndimage.binary_dilation(mask, iterations=S // 160).astype(np.float32), 1.5)
    result[..., 3] *= clip
    result[twig] = old[twig]
    Image.fromarray(np.clip(result, 0, 255).round().astype(np.uint8), 'RGBA').save(REF / f'fbranch{k}.png')
    return (covered & mask).sum() / target


def main():
    texels = rock()
    water()
    cover = [branch(k, 17 + k) for k in (1, 2)]
    print(f'wrote frock.png, frock_normal.png, frock_spec.png ({texels} rock texels), water.png, '
          f'fbranch1/2.png (sprig cover {cover[0]:.0%}, {cover[1]:.0%})')


if __name__ == '__main__':
    main()
