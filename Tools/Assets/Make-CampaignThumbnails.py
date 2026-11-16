"""Build the four Campaign Reimagined custom-campaign list thumbnails.

Redux shows <campaign ini name>.bmp (508x508, 24-bit) beside the custom
campaign list, so each file is named after its INI: crcampgn, crbd, crch,
crcca. Each uses the campaign's own loading-screen world as the backdrop with
a title plate in the CR menu green.

    python Tools/Assets/Make-CampaignThumbnails.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
GRAPHICS = ROOT / "Assets" / "Graphics"
LOADING = ROOT / "Assets" / "LoadingScreens"
FONT = ROOT / "OverlayFont" / "BZONE.ttf"
GREEN = (40, 255, 40)
GOLD = (255, 220, 60)
SIZE = 508

# stem: (backdrop, title lines, subtitle)
CAMPAIGNS = {
    "crcampgn": ("emload.png", ["NSDF"], "17 missions"),
    "crbd": ("ganyload.png", ["BLACK DOG"], "15 missions"),
    "crch": ("elysload.png", ["CHINESE", "(CRA)"], "8 missions"),
    "crcca": ("vload.png", ["SOVIET", "(CCA)"], "8 missions"),
}


def centered(draw, y, text, font, fill):
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text(((SIZE - (right - left)) // 2 - left, y - top), text, font=font, fill=fill)
    return y + (bottom - top)


def build(stem, backdrop, lines, subtitle):
    art = Image.open(LOADING / backdrop).convert("RGB")
    side = int(min(art.size) * 0.86)  # drop the loading screen's own frame
    left = (art.width - side) // 2
    top = (art.height - side) // 2
    art = art.crop((left, top, left + side, top + side)).resize((SIZE, SIZE), Image.LANCZOS)

    plate_top = 300 if len(lines) == 1 else 248
    box = (24, plate_top, SIZE - 24, SIZE - 24)
    shade = Image.new("RGBA", art.size, (0, 0, 0, 0))
    ImageDraw.Draw(shade).rounded_rectangle(box, radius=12, fill=(0, 12, 0, 190),
                                            outline=GREEN + (255,), width=3)
    art = Image.alpha_composite(art.convert("RGBA"), shade).convert("RGB")

    draw = ImageDraw.Draw(art)
    small = ImageFont.truetype(str(FONT), 25)
    big = ImageFont.truetype(str(FONT), 64 if max(map(len, lines)) <= 7 else 54)
    y = centered(draw, plate_top + 16, "CAMPAIGN REIMAGINED", small, GOLD) + 16
    for line in lines:
        y = centered(draw, y, line, big, GREEN) + 12
    centered(draw, y + 6, subtitle, small, GREEN)

    out = GRAPHICS / f"{stem}.bmp"
    art.save(out, format="BMP")
    print(f"wrote {out.relative_to(ROOT)} {art.size}")


def main():
    for stem, (backdrop, lines, subtitle) in CAMPAIGNS.items():
        build(stem, backdrop, lines, subtitle)


if __name__ == "__main__":
    main()
