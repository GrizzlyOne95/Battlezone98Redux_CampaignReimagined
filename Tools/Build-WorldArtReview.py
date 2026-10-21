"""Compare original palettes, previous independent HD tiles and new candidates."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
# Representative changed surfaces; these are palette references, not art inputs.
SURFACES = (("mars", 1), ("venus", 3), ("io", 3), ("europa", 0),
            ("titan", 3), ("ganymede", 1), ("achilles", 0), ("elysium", 0))
STEMS = dict(mars="ma", venus="ve", io="io", europa="eu", titan="ti",
             ganymede="ga", achilles="ac", elysium="el")


def load(path, size):
    with Image.open(path) as source:
        return source.convert("RGB").resize(size, Image.Resampling.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-build", type=Path, required=True)
    parser.add_argument("--candidate-root", type=Path, required=True)
    args = parser.parse_args()
    font = ImageFont.load_default(size=16)
    sheet = Image.new("RGB", (780, 32 + 205 * len(SURFACES)), (25, 28, 29))
    draw = ImageDraw.Draw(sheet)
    for column, label in enumerate(("Original stock", "Previous HD", "New candidate")):
        draw.text((5 + column * 260, 5), label, font=font)
    for row, (world, type_id) in enumerate(SURFACES):
        alias = f"{STEMS[world]}{type_id}{type_id}sa0".upper() + ".MAP"
        previous_recipe_path = ROOT / f"Tools/TerrainHD/{world.title()}/authoring.json"
        candidate_recipe_path = args.candidate_root / f"{world.title()}Sources/authoring.json"
        previous = json.loads(previous_recipe_path.read_text())["tiles"][alias]["D"]
        candidate = json.loads(candidate_recipe_path.read_text())["tiles"][alias]["D"]
        paths = (args.source_build / f"stock/{world}_type{type_id}_SolidA0.jpg",
                 previous_recipe_path.parent / previous,
                 candidate_recipe_path.parent / candidate)
        for column, path in enumerate(paths):
            x, y = 5 + column * 260, 32 + row * 205
            draw.text((x, y), f"{world.title()} type {type_id}", font=font)
            sheet.paste(load(path, (245, 170)), (x, y + 25))
    palette_path = args.candidate_root / "palette_comparison.png"
    sheet.save(palette_path)
    print(palette_path)

    # Add real rendered evidence when available, without implying that worlds
    # with no capture have been reviewed or that different maps isolate RAM cost.
    index = args.candidate_root / "live_review.json"
    if index.exists():
        captures = json.loads(index.read_text(encoding="utf-8-sig"))
        if not captures:
            return
        gallery = Image.new("RGB", (960, 320 * ((len(captures) + 1) // 2)), (25, 28, 29))
        draw = ImageDraw.Draw(gallery)
        for i, entry in enumerate(captures):
            x, y = (i % 2) * 480, (i // 2) * 320
            evidence = Path(entry["path"])
            draw.text((x + 5, y + 4), f"{entry['world'].title()} / {evidence.name}", font=font)
            if entry.get("skyReview"):
                draw.text((x + 5, y + 24), entry["skyReview"], font=font)
            gallery.paste(load(evidence / "trial.png", (480, 270)), (x, y + 47))
        gallery_path = args.candidate_root / "live_comparison.png"
        gallery.save(gallery_path)
        print(gallery_path)


if __name__ == "__main__":
    main()
