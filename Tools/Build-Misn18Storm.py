"""Build the mission 18 storm site data and its generated textures.

Reads the stock misn18 terrain (.hgt height field, .mat tile painting) and the
stock .bzn (object and path positions) and writes

  Scripts/CRStorm18Sites.lua              dead-scrub ground cover in 384 m tile
                                          layers, plus the keep-clear circles the
                                          tornado must never enter
  Assets/Textures/cr18_foliage.dds        cr17_foliage.dds scorched (DXT5, mips)
  Assets/Textures/cr18_crack_a.png        glowing ground cracks (RGBA, white-hot
  Assets/Textures/cr18_crack_b.png        core to orange edge)
  References/Misn18Storm/source-assets.json  hashes of every input and output

Ground cover reuses the existing cr17_mire_* meshes (already baked for wind sway
by Tools/Bake-FoliageSway.py); only the atlas differs, through the
CR18/GroundWind material. Placement uses a fixed seed, so the same inputs
produce the same file.

Usage (the private Battlezone_Source and the toolbox are needed to build):

  python Tools/Build-Misn18Storm.py --stock <Battlezone_Source>/BZ1/1.5/Battlezone_Install/stock
  python -I Tools/Build-Misn18Storm.py --check     (CI: outputs match the manifest)
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
SITES = ROOT / "Scripts" / "CRStorm18Sites.lua"
MANIFEST = ROOT / "References" / "Misn18Storm" / "source-assets.json"
TEXTURES = ROOT / "Assets" / "Textures"
OUTPUTS = [SITES, TEXTURES / "cr18_foliage.dds", TEXTURES / "cr18_crack_a.png", TEXTURES / "cr18_crack_b.png"]

# The stock map: x 0..2560, z 97280..102400 (Battlezone_Source misn18.trn [Size]).
MIN_X, MIN_Z, WIDTH, DEPTH = 0, 97280, 2560, 5120
TILE = 384            # two 192 m StaticGeometry regions, as CRJungle17Sites
SEED = 18018

# (mesh, spacing m, scale range, keep probability). Meshes are the baked misn17
# ground cover; the dead-scrub look is the material's atlas, not new geometry.
LAYERS = [
    ("cr17_mire_ferna.mesh", 24, (0.55, 1.15), 0.80),
    ("cr17_mire_fernb.mesh", 28, (0.60, 1.20), 0.80),
    ("cr17_mire_frond.mesh", 26, (0.70, 1.50), 0.75),
    ("cr17_mire_reeds.mesh", 22, (0.60, 1.30), 0.85),
]
MAX_SLOPE = 0.55       # rise over run
GUARD_RADIUS = 28      # keep plants off every stock object

# Keep-clear circles for the tornado (x, z, radius, name). Everything the
# stock script builds, spawns or points a camera at is covered with margin: the
# player start and recycler, the stranded transport and its four thrusters, the
# discovery point, the wave spawns and the "dontgo" ambush column.
def keep_clear(objects, paths):
    zones = []
    def add(name, x, z, r):
        zones.append([round(x), round(z), r, name])
    def obj(label):
        return next(o for o in objects if o[0] == label)
    base = obj("avrecy2_recycler")
    add("base", base[1], base[2], 300)
    transport = obj("hbtran0038_i76building")
    add("transport", transport[1], transport[2], 300)
    found = paths["transfound"][0]
    add("transfound", found[0], found[1], 170)
    add("spawnreturn", *paths["spawnreturn"][0], 150)
    for n in ("spawn1a", "spawn1b", "spawnrand", "spawn2a", "spawn2b", "spawn3a", "spawn3b", "spawnrand2"):
        add(n, *paths[n][0], 140)
    for n in ("spawnalt1a", "spawnalt1b", "spawnalt2a", "spawnalt2b", "spawnalt3a", "spawnalt3b", "return1", "return2"):
        add(n, *paths[n][0], 110)
    # The ambush column the dontgo paths describe, as four overlapping circles.
    for z in (98990, 99280, 99560, 99830):
        add("dontgo", 945, z, 170)
    return zones


def sha(path):
    data = Path(path).read_bytes()
    if Path(path).suffix == ".lua":
        data = data.replace(b"\r\n", b"\n")  # a CRLF checkout must still match
    return hashlib.sha256(data).hexdigest()


def lua(v):
    if isinstance(v, dict):
        return "{" + ",".join(k + "=" + lua(x) for k, x in v.items()) + "}"
    if isinstance(v, (list, tuple)):
        return "{" + ",".join(lua(x) for x in v) + "}"
    return json.dumps(v)


def write_dds_dxt5(path, image):
    """DXT5 with a full mip chain, by compressing each level with Pillow. DXT5
    rather than DXT1: Pillow's DXT1 encoder mishandles the punch-through alpha
    blocks of a cutout atlas (red and black speckle)."""
    from PIL import Image
    import io
    levels = []
    level = image
    while True:
        buf = io.BytesIO()
        level.save(buf, format="DDS", pixel_format="DXT5")
        levels.append(buf.getvalue()[128:])
        if level.size[0] == 1 and level.size[1] == 1:
            break
        level = level.resize((max(1, level.size[0] // 2), max(1, level.size[1] // 2)), Image.LANCZOS)
    w, h = image.size
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000
    header = b"DDS " + struct.pack("<7I", 124, flags, h, w, max(16, ((w + 3) // 4) * 16 * ((h + 3) // 4)), 0, len(levels))
    header += b"\0" * 44
    header += struct.pack("<2I4s5I", 32, 0x4, b"DXT5", 0, 0, 0, 0, 0)
    header += struct.pack("<5I", 0x401008, 0, 0, 0, 0)
    assert len(header) == 128
    path.write_bytes(header + b"".join(levels))


def scorch_atlas():
    """Recolour the misn17 mire atlas: olive greens go dry brown, everything
    darker and ashier. Alpha (the cutout) is untouched."""
    from PIL import Image
    import numpy as np
    import colorsys
    src = Image.open(TEXTURES / "cr17_foliage.dds").convert("RGBA").resize((1024, 1024), Image.LANCZOS)
    a = np.asarray(src).astype(np.float32) / 255.0
    r, g, b, alpha = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    mx, mn = a[..., :3].max(-1), a[..., :3].min(-1)
    delta = mx - mn
    h = np.zeros_like(mx)
    d = np.where(delta == 0, 1, delta)
    h = np.where(mx == r, ((g - b) / d) % 6, h)
    h = np.where(mx == g, (b - r) / d + 2, h)
    h = np.where(mx == b, (r - g) / d + 4, h)
    h = (h / 6.0) % 1.0
    s = np.where(mx == 0, 0, delta / np.where(mx == 0, 1, mx))
    v = mx
    # Greens and yellow-greens (0.10 .. 0.42) pull toward a dry brown (0.07).
    green = np.clip((h - 0.09) / 0.05, 0, 1) * np.clip((0.45 - h) / 0.08, 0, 1)
    h = h * (1 - green) + 0.07 * green
    s = np.clip(s * (1 - 0.35 * green) * 0.85, 0, 1)
    v = np.clip(v * (0.78 - 0.12 * green), 0, 1)
    # Char: a faint cool grey toward the dark end.
    rgb = np.zeros_like(a[..., :3])
    flat_h, flat_s, flat_v = h.ravel(), s.ravel(), v.ravel()
    out = np.array([colorsys.hsv_to_rgb(*t) for t in zip(flat_h, flat_s, flat_v)], dtype=np.float32)
    rgb = out.reshape(h.shape + (3,))
    ash = np.clip(0.55 - v, 0, 1)[..., None] * 0.25
    rgb = rgb * (1 - ash) + np.array([0.20, 0.19, 0.19], dtype=np.float32) * ash
    rgb8 = (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)
    # Bleed colour into the transparent texels: the block compressor and the
    # mip filter would otherwise pull their garbage colour into the leaf edges.
    covered = alpha > 0.16
    filled = rgb8.astype(np.float32)
    for _ in range(8):
        total, weight = np.zeros_like(filled), np.zeros(alpha.shape, np.float32)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                m = np.roll(np.roll(covered, dx, 1), dy, 0)
                total += np.roll(np.roll(filled, dx, 1), dy, 0) * m[..., None]
                weight += m
        grow = (~covered) & (weight > 0)
        filled[grow] = (total / np.maximum(weight, 1)[..., None])[grow]
        covered = covered | grow
    rgb8 = np.where((alpha > 0.16)[..., None], rgb8, filled.astype(np.uint8))
    out = np.dstack([rgb8, (np.clip(alpha, 0, 1) * 255 + 0.5).astype(np.uint8)])
    return Image.fromarray(out, "RGBA")


def crack_image(variant):
    """One glowing crack decal: white-hot core, orange edge, soft alpha."""
    from PIL import Image, ImageDraw, ImageFilter
    import random
    rnd = random.Random(1800 + variant)
    size, ss = 256, 4
    canvas = size * ss
    mask_core = Image.new("L", (canvas, canvas), 0)
    mask_edge = Image.new("L", (canvas, canvas), 0)
    dc, de = ImageDraw.Draw(mask_core), ImageDraw.Draw(mask_edge)
    cx = cy = canvas / 2

    def branch(x, y, angle, length, width, depth):
        steps = max(4, int(length / (9 * ss)))
        for i in range(steps):
            angle += rnd.uniform(-0.35, 0.35)
            step = length / steps
            nx, ny = x + math.cos(angle) * step, y + math.sin(angle) * step
            w = max(1.0, width * (1 - i / steps * 0.8))
            de.line([(x, y), (nx, ny)], fill=255, width=int(w * 3.0))
            dc.line([(x, y), (nx, ny)], fill=255, width=max(1, int(w)))
            x, y = nx, ny
            if depth < 2 and i > 1 and rnd.random() < 0.28:
                branch(x, y, angle + rnd.choice((-1, 1)) * rnd.uniform(0.5, 1.1),
                       length * rnd.uniform(0.35, 0.6), width * 0.65, depth + 1)

    if variant == 0:
        arms = rnd.randint(5, 7)
        for k in range(arms):
            branch(cx, cy, k * math.tau / arms + rnd.uniform(-0.3, 0.3), canvas * rnd.uniform(0.30, 0.46), 5.5 * ss / 4, 0)
    else:
        a0 = rnd.uniform(0, math.pi)
        for sign in (0, 1):
            branch(cx, cy, a0 + sign * math.pi, canvas * 0.47, 6.5 * ss / 4, 0)
    core = mask_core.filter(ImageFilter.GaussianBlur(ss * 0.9)).resize((size, size), Image.LANCZOS)
    edge = mask_edge.filter(ImageFilter.GaussianBlur(ss * 3.2)).resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size))
    px_c, px_e, px = core.load(), edge.load(), out.load()
    for y in range(size):
        for x in range(size):
            c, e = px_c[x, y] / 255.0, px_e[x, y] / 255.0
            heat = min(1.0, c * 1.4)
            red, green, blue = 1.0, 0.25 + 0.65 * heat, 0.04 + 0.70 * heat ** 2
            alpha = min(1.0, e * 0.85 + c)
            # Fade to nothing at the card edge so the quad never shows its border.
            dx, dy = (x - size / 2) / (size / 2), (y - size / 2) / (size / 2)
            alpha *= max(0.0, min(1.0, (1.0 - math.hypot(dx, dy)) * 5.0))
            px[x, y] = (int(red * 255), int(green * 255), int(blue * 255), int(alpha * 255))
    return out


def build(stock, toolbox):
    import numpy as np
    sys.path.insert(0, str(toolbox))
    from battlezone.bzn.bz1 import read_bzn
    from battlezone.terrain.mat import read_mat
    stock = Path(stock)
    raw = np.fromfile(stock / "misn18.hgt", "<u2") & 0x0FFF
    height = np.zeros((512, 256))
    cursor = 0
    for zz in range(4):
        for zx in range(2):
            height[zz * 128:(zz + 1) * 128, zx * 128:(zx + 1) * 128] = raw[cursor:cursor + 16384].reshape(128, 128) * 0.1
            cursor += 16384
    mat = read_mat(stock / "misn18.mat", 2, 4)
    bzn = read_bzn(stock / "misn18.bzn", odf_dirs=[stock])
    objects = []
    for o in bzn.objects:
        t = o.fields["transform"].value
        objects.append((o.label, t[9], t[11], o.prjid))
    paths = {}
    for p in bzn.paths:
        paths[p["label"].value.rstrip(b"\0").decode()] = [(round(x), round(z)) for x, z in p["points"].value]
    zones = keep_clear(objects, paths)
    guards = np.array([(o[1], o[2]) for o in objects if o[3] != "sfield"] +
                      [(o[1], o[2]) for o in objects if o[3] == "sfield"])

    def ground(x, z):
        r, c = (z - MIN_Z) / 10.0, x / 10.0
        r0, c0 = int(min(510, max(0, r))), int(min(254, max(0, c)))
        fr, fc = r - r0, c - c0
        top = height[r0, c0] * (1 - fc) + height[r0, c0 + 1] * fc
        bot = height[r0 + 1, c0] * (1 - fc) + height[r0 + 1, c0 + 1] * fc
        return float(top * (1 - fr) + bot * fr)

    def slope(x, z):
        return math.hypot(ground(x + 6, z) - ground(x - 6, z), ground(x, z + 6) - ground(x, z - 6)) / 12.0

    def tile_type(x, z):
        return int(mat[int((z - MIN_Z) / 20), int(x / 20)]) >> 12

    rng = np.random.default_rng(SEED)
    layers, counts = [], {}
    for mesh, spacing, scale, keep in LAYERS:
        tiles = {}
        for z in np.arange(MIN_Z + 40, MIN_Z + DEPTH - 40, spacing):
            for x in np.arange(40, WIDTH - 40, spacing):
                px = float(x + rng.uniform(-spacing * 0.45, spacing * 0.45))
                pz = float(z + rng.uniform(-spacing * 0.45, spacing * 0.45))
                yaw, size, roll = float(rng.uniform(0, math.tau)), float(rng.uniform(*scale)), rng.random()
                if not (40 < px < WIDTH - 40 and MIN_Z + 40 < pz < MIN_Z + DEPTH - 40):
                    continue
                if tile_type(px, pz) not in (0, 1) or slope(px, pz) > MAX_SLOPE or roll > keep:
                    continue
                if np.any((guards[:, 0] - px) ** 2 + (guards[:, 1] - pz) ** 2 < GUARD_RADIUS ** 2):
                    continue
                key = (math.floor(px / TILE), math.floor((pz - MIN_Z) / TILE))
                tiles.setdefault(key, []).append([round(px, 2), round(ground(px, pz) - 0.08, 2), round(pz, 2), round(yaw, 3), round(size, 3)])
        for key in sorted(tiles):
            layers.append({"mesh": mesh, "cx": key[0] * TILE + TILE // 2, "cz": MIN_Z + key[1] * TILE + TILE // 2,
                           "instances": tiles[key]})
        counts[mesh] = sum(len(v) for v in tiles.values())
    data = {"seed": SEED, "tile": TILE, "bounds": [MIN_X, MIN_Z, MIN_X + WIDTH, MIN_Z + DEPTH],
            "origin": [MIN_X, 0, MIN_Z], "zones": zones, "layers": layers}
    SITES.write_text("-- Generated by Tools/Build-Misn18Storm.py\nreturn " + lua(data) + "\n", newline="\n")
    TEXTURES.mkdir(parents=True, exist_ok=True)
    write_dds_dxt5(TEXTURES / "cr18_foliage.dds", scorch_atlas())
    crack_image(0).save(TEXTURES / "cr18_crack_a.png", optimize=True)
    crack_image(1).save(TEXTURES / "cr18_crack_b.png", optimize=True)
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps({
        "source": "Battlezone_Source stock misn18 (.hgt .mat .bzn); cr17_foliage.dds",
        "inputs": {n: sha(stock / n) for n in ("misn18.hgt", "misn18.mat", "misn18.bzn")},
        "cr17_foliage.dds": sha(TEXTURES / "cr17_foliage.dds"),
        "outputs": {p.name: sha(p) for p in OUTPUTS},
        "layers": len(layers), "plants": sum(counts.values()), "perMesh": counts, "zones": len(zones),
    }, indent=2) + "\n", newline="\n")
    print("Built misn18 storm sites:", len(layers), "layers,", sum(counts.values()), "plants,", len(zones), "keep-clear circles")


def check():
    manifest = json.loads(MANIFEST.read_text())
    bad = [p.name for p in OUTPUTS if not p.exists() or sha(p) != manifest["outputs"].get(p.name)]
    if bad:
        raise SystemExit("Misn18 storm outputs differ from the manifest: " + ", ".join(bad))
    print("Misn18 storm outputs match the manifest.")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stock", type=Path)
    ap.add_argument("--toolbox", type=Path, default=ROOT.parent / "Battlezone98_Modding_Toolbox")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if a.check:
        check()
    elif a.stock:
        build(a.stock, a.toolbox)
    else:
        ap.error("--stock or --check required")
