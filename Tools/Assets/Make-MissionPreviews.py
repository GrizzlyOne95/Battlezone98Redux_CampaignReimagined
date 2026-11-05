"""Build the per-mission previews shown beside the mission list.

Redux shows <mission>.bmp beside the list. Each preview is the map's own terrain
as a north-up relief with contours, titled from Config/<mission>.ini. Campaign
menu art (crcampgn, crcca, crch, crbd) and crsetup are not touched.

    python Tools/Assets/Make-MissionPreviews.py
"""
from pathlib import Path
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bzmodellibs import toolbox_root

sys.path.insert(0, str(toolbox_root()))
from battlezone.terrain.hg2 import read_hg2

ROOT = Path(__file__).resolve().parents[2]
MISSIONS = ROOT / "Missions"
OUTPUT = ROOT / "Assets" / "Graphics"
FONT = ROOT / "OverlayFont" / "BZONE.ttf"
GREEN = (40, 255, 40)
SIZE = 508
BAR = 92
CONTOURS = 14
LIGHT = np.array((-0.55, 0.55, 0.63))  # low sun from the north-west


def relief(heights):
    """Shade heights (row 0 south) into a square north-up RGB image."""
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

    value = (0.18 + 0.82 * shade) * (0.45 + 0.55 * level)
    rgb = np.dstack((value * 70, value * 235, value * 80))
    rgb[edge] = rgb[edge] * 0.55 + np.array(GREEN) * 0.25
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

    art = relief(heights).convert("RGBA")
    shade = Image.new("RGBA", art.size, (0, 0, 0, 0))
    ImageDraw.Draw(shade).rectangle((0, SIZE - BAR, SIZE, SIZE), fill=(0, 12, 0, 215))
    art = Image.alpha_composite(art, shade).convert("RGB")

    draw = ImageDraw.Draw(art)
    draw.rectangle((0, 0, SIZE - 1, SIZE - 1), outline=GREEN, width=3)
    draw.line((0, SIZE - BAR, SIZE, SIZE - BAR), fill=GREEN, width=3)
    tag, _, name = title(mission).partition(": ")
    margin = 18
    draw.text((margin, SIZE - BAR + 10), tag, font=ImageFont.truetype(str(FONT), 24), fill=(255, 220, 60))
    draw.text((margin, SIZE - BAR + 42), name, font=fit(draw, name, SIZE - 2 * margin, 32), fill=GREEN)
    art.save(OUTPUT / f"{mission}.bmp", format="BMP")


def main():
    stems = sorted(path.stem for path in MISSIONS.glob("*.vxt"))
    for mission in stems:
        build(mission)
    print(f"wrote {len(stems)} previews to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
