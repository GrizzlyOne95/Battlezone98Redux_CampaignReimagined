"""Build the Instant Action preview for the Setup / Repair mission.

Redux shows <mission>.bmp beside the Instant Action list. This reuses the
campaign art's logo and cockpit backdrop and replaces the campaign title with
the setup label, so the two menu entries read as one product.

    python Tools/Assets/Make-SetupThumbnail.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Assets" / "Graphics" / "campaignReimagined.jpg"
OUTPUT = ROOT / "Assets" / "Graphics" / "crsetup.bmp"
FONT = ROOT / "OverlayFont" / "BZONE.ttf"
GREEN = (40, 255, 40)
SIZE = 508


def centered(draw, y, text, font, fill=GREEN):
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text(((SIZE - (right - left)) // 2 - left, y), text, font=font, fill=fill)
    return y + (bottom - top)


def main():
    art = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE))

    # Blur the old campaign title away, keeping the backdrop's colours.
    title_box = (40, 275, SIZE - 40, 478)
    art.paste(art.crop(title_box).filter(ImageFilter.GaussianBlur(14)), title_box[:2])
    shade = Image.new("RGBA", art.size, (0, 0, 0, 0))
    ImageDraw.Draw(shade).rounded_rectangle(title_box, radius=12, fill=(0, 12, 0, 185),
                                            outline=GREEN + (255,), width=3)
    art = Image.alpha_composite(art.convert("RGBA"), shade).convert("RGB")

    draw = ImageDraw.Draw(art)
    big = ImageFont.truetype(str(FONT), 58)
    small = ImageFont.truetype(str(FONT), 27)
    y = centered(draw, 292, "SETUP", big) + 14
    y = centered(draw, y, "& REPAIR", big) + 24
    y = centered(draw, y, "Open Community Patch", small) + 10
    centered(draw, y, "Run me first", small, fill=(255, 220, 60))

    art.save(OUTPUT, format="BMP")
    print(f"wrote {OUTPUT.relative_to(ROOT)} {art.size}")


if __name__ == "__main__":
    main()
