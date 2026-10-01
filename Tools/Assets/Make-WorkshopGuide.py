"""Build the annotated "how to start" images for the Workshop description.

Takes 2560x1440 in-game screenshots and draws numbered highlight boxes on the
buttons a new player must press. Coordinates are in 2560x1440 pixels; retake
the screenshots at that size (any 16:9 size is rescaled first).

    python Tools/Assets/Make-WorkshopGuide.py --main-menu A.png --single-player B.png \
        --instant-action C.png --campaign D.png

Outputs Docs/workshop_guide/step*.png.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Docs" / "workshop_guide"
FONT = Path(r"C:\Windows\Fonts\bahnschrift.ttf")
BASE = (2560, 1440)
WIDTH = 1280
YELLOW = (255, 214, 0)

# (source key, output name, crop box, [(box, badge, label)], caption)
STEPS = [
    ("main_menu", "step1_single_player.png", (0, 0, 2560, 1440),
     [((545, 212, 1128, 450), "1", "Single Player")],
     "Step 1 - From the main menu, open SINGLE PLAYER"),
    ("single_player", "step2_instant_action.png", (0, 0, 2560, 1440),
     [((2105, 1352, 2465, 1428), "2", "Instant Action")],
     "Step 2 - First time only: open INSTANT ACTION (bottom right)"),
    ("instant_action", "step3_setup_mission.png", (0, 0, 2560, 1440),
     [((700, 340, 1418, 378), "3", "! SETUP / REPAIR"),
      ((2105, 0, 2465, 92), "4", "Launch")],
     "Step 3 - Select ! SETUP / REPAIR and press LAUNCH. "
     "If it says RESTART REQUIRED, fully exit and relaunch the game"),
    ("single_player", "step4_custom_campaign.png", (0, 0, 2560, 1440),
     [((2105, 0, 2465, 92), "5", "Custom Campaign")],
     "Step 4 - To play: SINGLE PLAYER > CUSTOM CAMPAIGN (top right)"),
    ("campaign", "step5_campaign.png", (0, 0, 2560, 1440),
     [((700, 368, 1418, 400), "6", "Campaign Reimagined"),
      ((2105, 0, 2465, 92), "7", "Launch")],
     "Step 5 - Select Campaign Reimagined and press LAUNCH"),
]


def font(size):
    return ImageFont.truetype(str(FONT), size)


def annotate(image, marks):
    draw = ImageDraw.Draw(image)
    badge_font = font(46)
    label_font = font(38)
    for (x0, y0, x1, y1), badge, label in marks:
        pad = 10
        draw.rounded_rectangle((x0 - pad, y0 - pad, x1 + pad, y1 + pad),
                               radius=14, outline=YELLOW, width=8)
        # Badge sits outside the box, toward the screen centre.
        r = 34
        cx = x0 - pad - r - 8 if x0 > BASE[0] / 2 else x1 + pad + r + 8
        cy = (y0 + y1) // 2 if y1 - y0 > 60 else max(y0, r + 6)
        cy = max(r + 6, min(BASE[1] - r - 6, cy))
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=YELLOW, outline=(0, 0, 0), width=4)
        draw.text((cx, cy), badge, font=badge_font, fill=(0, 0, 0), anchor="mm")
        # Label under the badge, or above it near the bottom edge.
        right_side = x0 > BASE[0] / 2
        lx = cx + r if right_side else cx - r
        if cy + r + 70 < BASE[1]:
            ly, anchor = cy + r + 12, "ra" if right_side else "la"
        else:
            ly, anchor = cy - r - 14, "rd" if right_side else "ld"
        box = draw.textbbox((lx, ly), label, font=label_font, anchor=anchor)
        draw.rectangle((box[0] - 10, box[1] - 6, box[2] + 10, box[3] + 8), fill=(0, 0, 0))
        draw.text((lx, ly), label, font=label_font, fill=YELLOW, anchor=anchor)


def caption_bar(image, text):
    bar_h = 64
    out = Image.new("RGB", (image.width, image.height + bar_h), (0, 0, 0))
    out.paste(image, (0, 0))
    draw = ImageDraw.Draw(out)
    size = 34
    while size > 18 and draw.textlength(text, font=font(size)) > image.width - 40:
        size -= 1
    draw.text((image.width // 2, image.height + bar_h // 2), text,
              font=font(size), fill=YELLOW, anchor="mm")
    return out


def main():
    parser = argparse.ArgumentParser()
    for key in ("main_menu", "single_player", "instant_action", "campaign"):
        parser.add_argument("--" + key.replace("_", "-"), required=True, type=Path)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    for key, name, crop, marks, caption in STEPS:
        shot = Image.open(getattr(args, key)).convert("RGB").resize(BASE, Image.LANCZOS)
        annotate(shot, marks)
        shot = shot.crop(crop)
        shot = shot.resize((WIDTH, round(shot.height * WIDTH / shot.width)), Image.LANCZOS)
        caption_bar(shot, caption).save(OUT / name, optimize=True)
        print("wrote", (OUT / name).relative_to(ROOT))


if __name__ == "__main__":
    main()
