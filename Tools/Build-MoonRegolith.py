"""Build a matched Moon dust/crater candidate with the shared Toolbox packer.

Preserve the authored HD rocky surface and detail texture. Procedural crater
geometry and localized dust share placement masks; only crater floors and sparse
patches soften the source material. No normal is inferred from albedo.
"""
import argparse
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
from terrain_art_tuning import binding_for, validate_runtime, surface_coverage

ROOT = Path(__file__).resolve().parent.parent


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


def noise(size, seed, sigma):
    field = gaussian_filter(np.random.default_rng(seed).standard_normal((size, size)), sigma, mode="wrap")
    return ((field-field.mean())/max(float(field.std()), 1e-8)).astype(np.float32)


def encode_normal(height, spacing, compensation=1):
    dv, du = np.gradient(height, spacing)
    vectors = np.stack((-du/compensation, -dv/compensation, np.ones_like(du)), axis=2)
    vectors /= np.linalg.norm(vectors, axis=2, keepdims=True)
    return np.uint8(np.clip(np.rint((vectors+1)*127.5), 0, 255))


def surface(settings):
    size = settings["tileSize"]
    crater = module("moon_craters", ROOT/"Tools/Build-MoonCraterDisplacement.py")
    heights = crater.crater_tile(size, settings)
    # Match the existing 1024px height atlas's hard guard, then ease into dust.
    guard = (int(np.ceil(settings["heightAtlasSize"]/160))+2)*size/(settings["heightAtlasSize"]//4)
    distance = np.minimum(np.arange(size), np.arange(size)[::-1])
    edge = crater.fade((distance-guard)/(settings["edgeMeters"]/settings["tileMeters"]*size))
    envelope = edge[:, None]*edge[None, :]
    heights *= envelope
    dust = noise(size, settings["seed"], 1.8) * settings["dustHeightMeters"]
    dust *= envelope
    broad = noise(size, settings["seed"]+1, size/30)
    # These are material differences, not a baked directional light or shadow.
    floor = np.clip(-heights, 0, 1)
    rim = np.clip(heights/settings["rimHeight"], 0, 1)
    colour = np.array(settings["albedo"], np.float32) + (
        settings["albedoVariation"]*broad + 1.5*dust/max(settings["dustHeightMeters"], 1e-8)
        + 3*floor + 5*rim)[:, :, None]
    images = {
        "D": np.uint8(np.clip(colour, 0, 255)),
        "N": encode_normal(dust, settings["tileMeters"]/size, settings["normalSharpenCompensation"]),
        "S": np.full((size, size, 3), 18, np.uint8),
        "E": np.zeros((size, size, 3), np.uint8),
    }
    return heights, images


def dust_mask(height, settings):
    """Local coverage only: outside crater floors/sparse patches keep the HD art."""
    crater = module("moon_craters_mask", ROOT/"Tools/Build-MoonCraterDisplacement.py")
    floors = crater.fade((-height-settings["floorDustStart"])/
                         (settings["floorDustFull"]-settings["floorDustStart"]))
    patches = crater.fade((noise(height.shape[0], settings["seed"]+9,
                                height.shape[0]/24)-settings["patchThreshold"])/.7)
    return (np.maximum(floors*settings["floorDustStrength"],
                       patches*settings["patchDustStrength"])*settings.get("surfaceCoverage",1.)).astype(np.float32)


def blend_surface(source, dust, coverage, channel):
    """Preserve original bytes at zero coverage, including authored normal XY."""
    weight = coverage[:, :, None]
    if channel == "N":
        a, b = source.astype(np.float32)/127.5-1, dust.astype(np.float32)/127.5-1
        slopes = (a[:, :, :2]/np.maximum(a[:, :, 2:3], .01)*(1-weight)
                  + b[:, :, :2]/np.maximum(b[:, :, 2:3], .01)*weight)
        vectors = np.concatenate((slopes, np.ones((*slopes.shape[:2], 1), np.float32)), axis=2)
        vectors /= np.linalg.norm(vectors, axis=2, keepdims=True)
        result = np.uint8(np.clip(np.rint((vectors+1)*127.5), 0, 255))
    else:
        result = np.uint8(np.clip(np.rint(source.astype(np.float32)*(1-weight)+dust*weight), 0, 255))
    result[coverage == 0] = source[coverage == 0]
    return result


def alias_heights(height, recipe):
    """Use the same material placement masks and solid rotations as the exporter."""
    size = height.shape[0]
    result = {"MN00SA0.MAP": height, "MN00SC0.MAP": np.rot90(height, 2),
              "MN33SA0.MAP": np.zeros_like(height)}
    for name, kind, seed in (("MN03CA0.MAP", "C", 30), ("MN03DA0.MAP", "D", 31),
                             ("MN04CA0.MAP", "C", 40), ("MN04DA0.MAP", "D", 41)):
        if "04" in name:
            mask = recipe.paving_transition(size, name, kind, seed)
        else:
            mask = recipe.masks.cap_mask(size, seed) if kind == "C" else recipe.masks.diagonal_mask(size, seed)
        result[name] = height*(1-mask)
    for name in ("MN44SA0.MAP", "MN44SB0.MAP", "MN55SA0.MAP", "MN66SA0.MAP"):
        result[name] = height*(1-recipe.paving_master(size, name))
    return result


def audit_detail(image):
    raw = np.asarray(image.convert("RGB"), np.float32)/255
    luminance = raw @ np.array([.299, .587, .114], np.float32)
    # Exact shader central differences, including wrap at the texture edges.
    dx = (np.roll(luminance, 1, 1)-np.roll(luminance, -1, 1))*2.2
    dy = (np.roll(luminance, 1, 0)-np.roll(luminance, -1, 0))*2.2
    angle = np.degrees(np.arctan(np.hypot(dx, dy)))
    return {"size": list(image.size), "mean": float(luminance.mean()), "std": float(luminance.std()),
            "detailNormalDegreesP95": float(np.percentile(angle, 95)),
            "detailNormalDegreesMax": float(angle.max())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-build", type=Path, required=True, help="Trusted saved independent material cache/recipe")
    parser.add_argument("--toolbox", type=Path, required=True)
    parser.add_argument("--openshim", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--settings", type=Path, help="Override Config surfaceBlend.recipe")
    parser.add_argument("--compare-detail", type=Path)
    parser.add_argument("--detail-source", type=Path, help="Preserve the authored HD detail DDS; defaults to the saved Moon HD detail")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        raise ValueError("Choose a new output folder; existing artwork is preserved")
    world_binding = binding_for("moon")
    settings_path = args.settings or ROOT/world_binding.get("surfaceBlend", {}).get("recipe", "Tools/TerrainHD/Moon/regolith.json")
    settings = json.loads(settings_path.read_text())
    runtime_tuning = validate_runtime(world_binding)
    settings["depthMeters"] = min(1., .25*runtime_tuning["microReliefScale"])
    settings["surfaceCoverage"] = surface_coverage(world_binding)
    if (settings["schema"] != "cr-moon-regolith-v1" or settings["tileSize"] != 1024
            or settings["detailSize"] != 2048 or settings["heightAtlasSize"] != 1024):
        raise ValueError("This candidate retains the qualified tile/height/detail sizes")
    source = args.source_build.resolve()
    sys.path[:0] = [str(args.toolbox.resolve()), str(source), str(source/".deps")]
    from battlezone.terrain import hd_tiles
    recipe = module("saved_moon_source", source/"build_stock_atlases.py")
    recipe.BUNDLE = output/"recipe_work"
    recipe.BUNDLE.mkdir(parents=True)
    recipe.FORCE = True
    recipe.NORMAL_ONLY = recipe.DIFFUSE_ONLY = recipe.PREFERRED = False
    recipe.material = lambda uid: json.loads((source/"material_cache"/uid/"material.json").read_text())
    height, images = surface(settings)
    coverage = dust_mask(height, settings)
    Image.fromarray(np.uint8(np.rint(coverage*255))).save(output/"dust_coverage.png")
    source_hashes = {}
    original = recipe.apply_art6
    def authored(world, channel, by_type, bases, report, rotate):
        original(world, channel, by_type, bases, report, rotate)
        ground = bases[by_type[0]]
        # The source exporter normalizes RGB normals even for a zero-turn
        # solid. Retain that same baseline, not pre-export quantized vectors.
        reference = rotate(ground, 0, channel)
        Image.fromarray(reference).save(output/f"original_hd_ground_{channel.lower()}.png")
        source_hashes[channel] = hashlib.sha256(reference.tobytes()).hexdigest()
        bases[by_type[0]] = blend_surface(ground, images[channel], coverage, channel)
        report["groundOverride"] = "HD source retained; dust coverage restricted to crater floors and sparse patches"
    recipe.apply_art6 = authored
    sources = output/"masters"
    sources.mkdir()
    def sink(world, channel, tiles, report):
        for alias, pixels in tiles.items():
            Image.fromarray(pixels).save(sources/(alias.lower().replace('.map', '')+f"_{channel.lower()}.png"))
    exporter = module("moon_source_exporter", ROOT/"Tools/Build-MarsHdTileSources.py")
    build = exporter.source_function(recipe, sink, 1024, True, True)
    build(next(world for world in recipe.PLAN["worlds"] if world["world"] == "moon"))
    project = hd_tiles.new_project(sources, ROOT/"Config/mn_detail_atlas.csv", material="MN_DETAIL_ATLAS",
        diffuse_resource="moon_atlas_d.dds", normal_resource="moon_atlas_n.dds", specular_resource="moon_atlas_s.dds",
        emissive_resource="black.dds", default_alias="MN00SA0.MAP", tile_size=1024, prefix="crhd_moon", normal_space="directx")
    bundle = output/"bundle"
    hd_tiles.build_bundle(project, bundle, progress=print)
    pack_path = bundle/"terrain_hd_tiles.json"
    pack = json.loads(pack_path.read_text())
    binding = pack["materials"]["MN_DETAIL_ATLAS"]
    binding.update(runtime_tuning)
    writer = module("terrain_height_writer", args.openshim/"scripts/Build-TerrainSurfacePack.py")
    heights = alias_heights(height, recipe)
    atlas_size = settings["heightAtlasSize"]
    atlas = np.zeros((atlas_size, atlas_size), np.float32)
    for row in csv.reader((bundle/"layout.csv").read_text().splitlines()):
        if not row[0]:
            continue
        x, y, w, h = [round(float(value)*atlas_size) for value in row[1:]]
        atlas[y:y+h, x:x+w] = np.asarray(Image.fromarray(heights[row[0].upper()]).resize((w,h), Image.Resampling.BILINEAR))
    height_path = bundle/"resources/crhd_moon_regolith_h.dds"
    height_path.write_bytes(writer.height_dds_bytes(atlas_size, atlas.ravel().tolist()))
    Image.fromarray(np.uint16(np.rint((atlas+1)*32767.5))).save(output/"height_atlas.png")
    Image.fromarray(encode_normal(height*settings["depthMeters"], settings["tileMeters"]/1024)).save(output/"crater_geometry_normal_reference.png")
    binding["heightTexture"] = "resources/"+height_path.name
    binding["heightEncoding"] = "signed-unit-r32"
    pack_path.write_text(json.dumps(pack, indent=2)+"\n")
    detail_source = args.detail_source or source/"staged_atlases/moon/ST_MOON_DETAIL.dds"
    detail_info = hd_tiles.inspect_dds(detail_source)
    if (detail_info["width"] != 2048 or detail_info["height"] != 2048 or detail_info["format"] != "DXT1"):
        raise ValueError("Preserve the authored 2048px BC1 Moon HD detail")
    detail_path = bundle/"resources/crhd_moon_regolith_detail.dds"
    shutil.copyfile(detail_source, detail_path)
    with Image.open(detail_path) as detail_image:
        detail_audit = audit_detail(detail_image)
        detail_image.save(output/"regolith_detail.png")
    bundle_audit = hd_tiles.check_bundle(bundle)
    report = {"settings": settings, "detail": detail_audit, "heightRange": [float(atlas.min()),float(atlas.max())],
              "heightSha256": hashlib.sha256(height_path.read_bytes()).hexdigest(),
              "sourceRecipeSha256": hashlib.sha256((source/"build_stock_atlases.py").read_bytes()).hexdigest(),
              "sourceGroundPixelSha256": source_hashes,
              "dustCoverage": {"unchangedFraction": float((coverage == 0).mean()),
                               "mean": float(coverage.mean()), "maximum": float(coverage.max())},
              "detailSourceSha256": hashlib.sha256(detail_source.read_bytes()).hexdigest(),
              "detailOutputSha256": hashlib.sha256(detail_path.read_bytes()).hexdigest(),
              "bundle": bundle_audit,
              "normalPolicy": "HD source RGB XYZ normals retained; dust microheight softens only covered areas. DS supplies macro crater normal, not duplicated in pixel normal.",
              "detailPolicy": "Original authored HD detail preserved byte-for-byte, including mips. Shader generates -dH/dU,-dH/dV normal at 8x/32x; no extra slot.",
              "sizesUnchanged": True, "additionalTextureSlots": 0}
    if args.compare_detail:
        with Image.open(args.compare_detail) as image:
            report["previousDetail"] = audit_detail(image)
    (output/"regolith_report.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps(report, indent=2))
    print(f"Preview bundle: {bundle}\nDetail override: {detail_path}")


if __name__ == "__main__":
    main()
