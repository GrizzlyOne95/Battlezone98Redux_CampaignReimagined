"""Build the per-mission previews shown beside the mission list.

Redux shows <mission>.bmp beside the list. Each preview is the map's own terrain
in true colour (MAT cells -> TRN tile names -> atlas colours) as a north-up relief with contours, titled from Config/<mission>.ini. Campaign
menu art (crcampgn, crcca, crch, crbd) and crsetup are not touched.

    python Tools/Assets/Make-MissionPreviews.py
"""
from pathlib import Path
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bzmodellibs import toolbox_root

sys.path.insert(0, str(toolbox_root()))
from battlezone.meshes.legacy_port import AssetSource
from battlezone.terrain.atlas import read_atlas_csv, read_atlas_default, read_materials
from battlezone.terrain.hg2 import read_hg2
from battlezone.terrain.mat import decode_entry, unpack_mat_zones
from battlezone.terrain.trn import TRNDocument

ROOT = Path(__file__).resolve().parents[2]
MISSIONS = ROOT / "Missions"
OUTPUT = ROOT / "Assets" / "Graphics"
FONT = ROOT / "OverlayFont" / "BZONE.ttf"
ACCENT = (36, 40, 36)  # neutral dark UI line so the map art reads as true colour
GAME_ROOT = Path(os.environ.get("BZR_GAME_ROOT", r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux"))
SIZE = 508
BAR = 92
CONTOURS = 14
AMBIENT, DIFFUSE = 0.45, 0.85
LIGHT = np.array((-0.55, 0.55, 0.63))  # low sun from the north-west


_FILES = {}


def game_file(name):
    """Find a texture or atlas CSV by name in the repo, then the Redux install."""
    if not _FILES:
        for root in (GAME_ROOT / "BZ_ASSETS", GAME_ROOT / "BZ_ASSETS_CORE", ROOT / "Assets", ROOT / "Materials", ROOT / "Config"):
            for path in root.rglob("*"):
                if path.is_file():
                    _FILES.setdefault(path.name.lower(), path)
    return _FILES[name.lower()]


def terrain_colour(terrain):
    """Mean atlas colour per MAT cell (row 0 south), or None if the map has no MAT."""
    stock = AssetSource(archives=[GAME_ROOT / "bzone.zfs", GAME_ROOT / "tro_cam.zfs"])
    local = MISSIONS / f"{terrain}.trn"
    # Stock campaign terrains ship their TRN/MAT in the Redux archives, not in this repo.
    trn = local.read_bytes() if local.exists() else stock(f"{terrain}.trn")
    mat_bytes = (MISSIONS / f"{terrain}.mat").read_bytes() if local.exists() else stock(f"{terrain}.mat")
    if trn is None or mat_bytes is None:
        return None
    doc = TRNDocument.parse(trn.decode("cp1252"))
    zones_x, zones_z = doc.zone_counts()
    mat = unpack_mat_zones(mat_bytes, zones_x, zones_z)
    name = doc.material_name.lower()
    csv = game_file(f"{name}.csv")
    cells, fallback = read_atlas_csv(csv), read_atlas_default(csv)
    diffuse = read_materials(ROOT / "Materials")[name].diffuse
    atlas = Image.open(game_file(diffuse)).convert("RGB")
    width, height = atlas.size
    types = doc.texture_types()
    lookup = {}
    for value in np.unique(mat):
        entry = decode_entry(int(value))
        alias = None
        if entry.base in types:
            for variant in range(entry.variant & 3, -1, -1):
                letter = "ABCD"[variant]
                key = f"Solid{letter}0" if entry.base == entry.next else f"{'DiagonalTo' if entry.cap else 'CapTo'}{entry.next}_{letter}0"
                alias = types[entry.base].get(key)
                if alias:
                    break
        cell = (cells.get(alias.upper()) if alias else None) or fallback
        lookup[int(value)] = np.asarray(atlas.crop(cell.box(width, height)).resize((1, 1), Image.BOX), np.float32).reshape(3)
    out = np.zeros(mat.shape + (3,), np.float32)
    for value, colour in lookup.items():
        out[mat == value] = colour
    return out


def relief(heights, colour):
    """Shade true-colour terrain by heights (row 0 south) into a square north-up RGB image."""
    rows, columns = heights.shape
    z = np.flipud(heights.astype(np.float32))
    span = max(float(z.max() - z.min()), 1.0)
    level = (z - z.min()) / span

    # Exaggerate by span so flat and mountainous maps both show their shape.
    slope_z, slope_x = np.gradient(level * max(rows, columns) * 0.12)
    normal = np.dstack((-slope_x, slope_z, np.ones_like(z)))
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    shade = np.clip(normal @ LIGHT, 0.0, 1.0)

    band = np.floor(level * CONTOURS)
    edge = (band != np.roll(band, 1, 0)) | (band != np.roll(band, 1, 1))
    edge[0, :] = edge[:, 0] = False

    base = np.asarray(Image.fromarray(np.flipud(colour).astype(np.uint8)).resize((columns, rows), Image.BILINEAR), np.float32)
    rgb = base * (AMBIENT + DIFFUSE * shade)[..., None]
    rgb[edge] *= 0.8
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).resize((SIZE, SIZE), Image.LANCZOS)


def fit(draw, text, width, start):
    for size in range(start, 11, -1):
        font = ImageFont.truetype(str(FONT), size)
        if draw.textlength(text, font=font) <= width:
            return font
    raise ValueError(f"title does not fit: {text}")


def title(mission):
    text = (ROOT / "Config" / f"{mission}.ini").read_text(encoding="utf-8", errors="replace")
    name = re.search(r'missionName\s*=\s*"([^"]+)"', text).group(1)
    return re.sub(r"\s+Coop$", "", name)


def build(mission):
    bzn = (MISSIONS / f"{mission}.bzn").read_text(encoding="latin-1")
    terrain = re.search(r"TerrainName = (\S+)", bzn).group(1)
    _, heights = read_hg2(MISSIONS / f"{terrain}.hg2")

    colour = terrain_colour(terrain)
    if colour is None:
        raise SystemExit(f"{mission}: {terrain}.mat missing, no true colour source")
    art = relief(heights, colour).convert("RGBA")
    shade = Image.new("RGBA", art.size, (0, 0, 0, 0))
    ImageDraw.Draw(shade).rectangle((0, SIZE - BAR, SIZE, SIZE), fill=(0, 0, 0, 215))
    art = Image.alpha_composite(art, shade).convert("RGB")

    draw = ImageDraw.Draw(art)
    draw.rectangle((0, 0, SIZE - 1, SIZE - 1), outline=ACCENT, width=3)
    draw.line((0, SIZE - BAR, SIZE, SIZE - BAR), fill=ACCENT, width=3)
    tag, _, name = title(mission).partition(": ")
    margin = 18
    draw.text((margin, SIZE - BAR + 10), tag, font=ImageFont.truetype(str(FONT), 24), fill=(255, 220, 60))
    draw.text((margin, SIZE - BAR + 42), name, font=fit(draw, name, SIZE - 2 * margin, 32), fill=(235, 235, 235))
    art.save(OUTPUT / f"{mission}.bmp", format="BMP")


def main():
    if not (GAME_ROOT / "bzone.zfs").is_file():
        raise SystemExit(f"Redux install not found at {GAME_ROOT}; set BZR_GAME_ROOT")
    stems = sorted(path.stem for path in MISSIONS.glob("*.vxt"))
    for mission in stems:
        build(mission)
    print(f"wrote {len(stems)} previews to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
