"""Build svtank's first-person hood texture (crcca_svhood_d/n/s/e.dds).

The cockpit's deck nose (CRV/svtankTankHull) used to sample the exterior svtank_d
livery at ~140 px/m and read blurry from the hatch. It now has its own owner-generated
livery (red nose, blue band with yellow pinstripes, cream plates with a red star nearest
the pilot) mapped top-down by Tools/CockpitsAndRigs/tankcockpits.py (CONFIG['cca']['hood']), image top =
nose. Normals come from a height built from the painted features (seam grooves, rivet
domes, shallow detail), not paint brightness; specular from the diffuse; emissive black.

python Tools/CockpitsAndRigs/Build-CCAHoodTexture.py
Source and provenance: References/TankCockpits/cca/hood-src/.
"""
from pathlib import Path
import importlib.util, json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'References/TankCockpits/cca/hood-src'
OUT = ROOT / 'Assets/Textures'
SIZE = (2048, 1024)

spec = importlib.util.spec_from_file_location('ccaatlas', ROOT / 'Tools/CockpitsAndRigs/Build-CCACockpitAtlas.py')
atlas = importlib.util.module_from_spec(spec); spec.loader.exec_module(atlas)


WORLD = (3.8, 1.53)  # hood extent (m) the image spans: CONFIG['cca']['hood'] in Tools/CockpitsAndRigs/tankcockpits.py


def relief(d):
    """Height (m) from the painted features, not paint brightness: welded plate seams
    (long dark lines) are grooves, rivets are domes, hatch outlines/handles/chips are
    shallow detail. Returns tangent-space normals in atlas.derive's encoding."""
    from scipy import ndimage as nd
    lum = d @ np.float32([.299, .587, .114])
    dark = nd.grey_closing(lum, size=9) - lum                  # thin dark features
    def lines(n):  # dark lines at least n px long (horizontal or vertical)
        l = np.maximum(nd.grey_opening(dark, size=(1, n)), nd.grey_opening(dark, size=(n, 1)))
        return nd.gaussian_filter(np.clip((l - .03) / .08, 0, 1), 1.2)
    seam = lines(121)   # welded plate seams; shorter runs are mostly drips and paint edges
    # Rivets: isotropic blobs ~10 px across (both Hessian eigenvalues large, same sign).
    s = 3.0
    hxx = nd.gaussian_filter(lum, s, order=(0, 2)); hyy = nd.gaussian_filter(lum, s, order=(2, 0))
    hxy = nd.gaussian_filter(lum, s, order=(1, 1))
    tr, det = hxx + hyy, hxx * hyy - hxy * hxy
    blob = np.where(det > .6 * (tr / 2) ** 2, np.abs(tr) * s * s, 0)
    # Rivet rows run beside the welded seams; mid-plate blobs are grime, chips or paint.
    near = nd.distance_transform_edt(lines(61) < .5) < 28
    peaks = (blob == nd.maximum_filter(blob, 13)) & (blob > .08) & (lines(61) < .5) & near
    yy, xx = np.mgrid[-6:7, -6:7]
    dome = np.sqrt(np.clip(1 - (xx * xx + yy * yy) / 30.0, 0, 1))
    rivets = np.clip(nd.convolve(peaks.astype(np.float32), dome, mode='constant'), 0, 1)
    detail = nd.gaussian_filter(lum, 1.0) - nd.gaussian_filter(lum, 6.0)
    h = -.003 * seam + .0025 * rivets + .0012 * np.tanh(detail / .08)
    ppm_x, ppm_y = h.shape[1] / WORLD[0], h.shape[0] / WORLD[1]
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * .5 * ppm_x   # dh/dx in m/m
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * .5 * ppm_y   # along image rows
    n = np.dstack([-gx, -gy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * .5 + .5, seam, peaks.sum()


def main():
    src = SRC / json.loads((SRC / 'provenance.json').read_text())['file']
    d = np.asarray(Image.open(src).convert('RGB').resize(SIZE, Image.LANCZOS), np.float32) / 255
    none = np.zeros(d.shape[:2], bool)
    _, spec_, _ = atlas.derive(d, none, np.zeros(d.shape[:2], np.float32))
    normal, seam, nriv = relief(d)
    print('rivets', nriv, 'seam px', int((seam > .5).sum()))
    spec_ *= (1 - .7 * seam)[..., None]   # dull the weld grooves
    maps = {'d': atlas.img(d), 'n': atlas.img(normal), 's': atlas.img(spec_), 'e': Image.new('RGB', (64, 32))}
    for k, v in maps.items():
        (OUT / f'crcca_svhood_{k}.dds').write_bytes(atlas.dxt1_dds(v))
        print('wrote', OUT / f'crcca_svhood_{k}.dds', v.size)


if __name__ == '__main__':
    main()
