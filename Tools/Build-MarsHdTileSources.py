"""Export the saved Stock World Terrain HD source recipe BEFORE atlas packing.

The trusted local source build is supplied explicitly. No atlas pixels are read.
The source recipe's material/normal corrections and shared transition masks are
reused; this adapter replaces only its final packing loop with a tile sink.
"""
import argparse
import ast
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
from terrain_hd_base_emissives import apply_base_emissives, apply_source_height_corrections
from terrain_art_tuning import apply_authored_surface, surface_signature

WORLD_STEMS = {"moon": "mn", "mars": "ma", "venus": "ve", "io": "io", "europa": "eu",
               "titan": "ti", "achilles": "ac", "ganymede": "ga", "elysium": "el"}


def source_function(module, sink, tile_size=None, height_matched_normals=False, base_emissives=False, art_direction=None):
    path = Path(module.__file__)
    tree = ast.parse(path.read_text(encoding="utf-8-sig"))
    function = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "build")
    loops = [(i, n) for i, n in enumerate(function.body) if isinstance(n, ast.For)
             and isinstance(n.target, ast.Name) and n.target.id == "ch"]
    if len(loops) != 1:
        raise ValueError("Unsupported saved recipe: expected one material-channel loop")
    index, loop = loops[0]
    if height_matched_normals:
        # Source-height validation owns the Moon/Mars pack polarity. Preserve
        # audited green conversion, but omit the later empirical XY reversal.
        relief_assignments = [n for n in ast.walk(loop) if isinstance(n, ast.Assign)
                              and any(isinstance(t, ast.Name) and t.id == "relief" for t in n.targets)]
        if len(relief_assignments) != 1:
            raise ValueError("Unsupported saved recipe: relief override boundary missing")
        relief_assignments[0].value = ast.Dict(keys=[], values=[])
    if base_emissives:
        normal_boundaries = [i for i, n in enumerate(loop.body) if isinstance(n, ast.Expr)
                             and isinstance(n.value, ast.Call) and isinstance(n.value.func, ast.Name)
                             and n.value.func.id == "apply_art5"]
        if len(normal_boundaries) != 1:
            raise ValueError("Unsupported saved recipe: source normal authoring boundary missing")
        loop.body[normal_boundaries[0]:normal_boundaries[0]] = ast.parse("_hd_source_height_corrections(world, ch, bases, report)").body
        boundaries = [i for i, n in enumerate(loop.body) if isinstance(n, ast.Expr)
                      and isinstance(n.value, ast.Call) and isinstance(n.value.func, ast.Name)
                      and n.value.func.id == "apply_art6"]
        if len(boundaries) != 1:
            raise ValueError("Unsupported saved recipe: base emissive authoring boundary missing")
        loop.body[boundaries[0]+1:boundaries[0]+1] = ast.parse("_hd_base_emissives(world, ch, source_by_type, bases, report)").body
        # Blend independent authored maps before rotations/transitions; native
        # arrays still consume the same dimensions/channels and no new slot.
        loop.body[boundaries[0]+1:boundaries[0]+1] = ast.parse("_hd_surface_blend(world, ch, source_by_type, bases, report)").body
        if art_direction:
            loop.body[boundaries[0]+1:boundaries[0]+1] = ast.parse("_hd_world_surface(world, ch, source_by_type, bases, report)").body
    cut = next((i for i, n in enumerate(loop.body) if isinstance(n, ast.If)
                and "tile_cache.values()" in ast.unparse(n.test) and "'E'" in ast.unparse(n.test)), None)
    if cut is None:
        raise ValueError("Unsupported saved recipe: tile generation/packing boundary missing")
    # Independent tiles have no packing gutters or atlas allocation ceiling.
    # Generate at the requested resolution directly from the material cache.
    for n in loop.body:
        if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "channel_cell" for t in n.targets):
            n.value = ast.Constant(tile_size) if tile_size else ast.Name(id="cell", ctx=ast.Load())
    loop.body = loop.body[:cut] + ast.parse("_hd_tile_sink(world, ch, tile_cache, report)\ncontinue").body
    prelude = function.body[:index]
    if tile_size:
        prelude += ast.parse(f"base_gutter = 0\nmaster_interior = {tile_size}").body
    function.body = prelude + [loop, ast.Return(value=ast.Name(id="report", ctx=ast.Load()))]
    scope = dict(vars(module)); scope["_hd_tile_sink"] = sink
    scope["_hd_base_emissives"] = apply_base_emissives
    scope["_hd_source_height_corrections"] = apply_source_height_corrections
    scope["_hd_surface_blend"] = apply_authored_surface
    if art_direction:
        from world_surface_art import apply
        scope["_hd_world_surface"] = lambda world,ch,types,bases,report: apply(world,ch,types,bases,report,art_direction)
    exec(compile(ast.fix_missing_locations(ast.Module(body=[function], type_ignores=[])), str(path), "exec"), scope)
    return scope["build"]


def bind_capture(capture, csv_path, resources, default_alias=None):
    if capture.get("schema") != "bzr-openshim-terrain-atlas-v1":
        raise ValueError("A live native terrain capture is required; CSV rows are not tile IDs")
    aliases = {}
    with Path(csv_path).open(encoding="utf-8-sig", newline="") as f:
        for row in csv.reader(f):
            if len(row) != 5:
                raise ValueError("Expected name,u,v,width,height CSV")
            rect = tuple(round(float(v), 6) for v in row[1:])
            aliases.setdefault(rect, []).append(row[0].strip().upper())
    remap = []
    used = set(capture["usedIndices"])
    for index in range(256):
        rect = capture["tiles"].get(str(index))
        names = aliases.get(tuple(round(float(v), 6) for v in rect), []) if rect else []
        name = next((n for n in names if n in resources), None)
        if name is None and "" in names and default_alias in resources:
            name = default_alias
        if name is None and index in used:
            raise ValueError(f"Used native tile {index} has no generated source alias: {names}")
        remap.append(resources[name or next(iter(resources))]["slice"])
    return remap


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-build", type=Path)
    p.add_argument("--world", choices=WORLD_STEMS, default="mars")
    p.add_argument("--base-emissives", action="store_true", help="Add small UV-authored base accents before source rotations/transitions")
    p.add_argument("--art-direction",type=Path,help="Explicit palette-preserving world surface recipe")
    p.add_argument("--images-only", action="store_true", help="Export independent PNG masters for Toolbox hd-tiles init/build")
    p.add_argument("--height-matched-normals", action="store_true", help="Keep source-height polarity after green conversion; omit empirical XY reversal")
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--tile-size", type=int, choices=[512, 1024, 2048], default=1024)
    p.add_argument("--capture", type=Path)
    p.add_argument("--atlas-csv", type=Path)
    p.add_argument("--bind-existing", action="store_true", help="Rebuild the runtime manifest for existing source tiles")
    args = p.parse_args()
    # Mars' saved recipe reverses ChunkyMartianGravel after converting green.
    # Independent source height proves that extra reversal is inverted relief.
    height_matched_normals = args.world == "mars" or args.height_matched_normals
    if args.world != "mars" and not args.images_only:
        p.error("Other worlds use --images-only and the shared Toolbox bundle builder")
    if args.images_only and (args.bind_existing or args.capture):
        p.error("--images-only cannot bind an existing DDS pack/capture")
    output = args.output.resolve()
    if args.capture and not args.atlas_csv:
        raise ValueError("--capture requires --atlas-csv")
    if args.bind_existing:
        result = json.loads((output / "source_tiles.json").read_text())
        require_mars_normal_policy(result)
        write_manifest(output, args.capture, args.atlas_csv or output / "native_layout.csv",
                       result["aliases"], result.get("defaultAlias"))
        return
    if not args.source_build:
        raise ValueError("--source-build is required for source export")
    root = args.source_build.resolve()
    if output.exists():
        raise ValueError("Output must be a new directory")
    if root == output or root in output.parents:
        raise ValueError("Keep generated example separate from the original source build")
    sys.path[:0] = [str(root), str(root / ".deps")]
    spec = importlib.util.spec_from_file_location("saved_terrain_recipe", root / "build_stock_atlases.py")
    recipe = importlib.util.module_from_spec(spec); spec.loader.exec_module(recipe)
    import numpy as np
    from PIL import Image, ImageDraw
    output.mkdir(parents=True)
    atlas = WORLD_STEMS[args.world] + "_detail_atlas.csv"
    shutil.copyfile(root / "stock" / atlas, output / "native_layout.csv")
    recipe.BUNDLE = output / "recipe_work"
    recipe.BUNDLE.mkdir()
    recipe.FORCE = True; recipe.NORMAL_ONLY = recipe.DIFFUSE_ONLY = recipe.PREFERRED = False
    # Refuse rebuilding or downloading source materials. Read the matching
    # source cache and provenance only; the original addon/build stay untouched.
    def cached_material(uid):
        folder = root / "material_cache" / uid
        if not all((folder / (ch + ".png")).is_file() for ch in "DNSE"):
            raise ValueError(f"Incomplete source cache: {uid}")
        return json.loads((folder / "material.json").read_text())
    recipe.material = cached_material
    aliases, channels = {}, {}
    def sink(world, channel, tiles, report):
        print(f"Export {world} source {channel}: {len(tiles)} tiles", flush=True)
        resources = {}
        previews = []
        for name, pixels in tiles.items():
            slug = name.lower().removesuffix(".map") or "default"
            filename = f"{slug}_{channel.lower()}.png" if args.images_only else f"crhd_mars_{slug}_{channel.lower()}.dds"
            if pixels.shape[:2] != (args.tile_size, args.tile_size):
                raise ValueError("Source recipe did not generate full-resolution independent tiles")
            image = recipe.resize(pixels, args.tile_size, channel)
            if args.images_only:
                Image.fromarray(image).save(output / filename)
                resources[name] = filename
                aliases.setdefault(name, {})[channel] = filename
                if channel == "D": previews.append((name, Image.fromarray(image).resize((160, 160))))
                continue
            levels = []; size = args.tile_size
            while True:
                mip = image if size == args.tile_size else recipe.resize(image, size, channel)
                if channel == "N": levels.append(mip[:, :, ::-1].tobytes())
                else:
                    if size < 4: mip = np.pad(mip, ((0, 4-size), (0, 4-size), (0, 0)), mode="edge")
                    levels.append(recipe.bc1.encode_bc1(mip, max_blocks=16384))
                if size == 1: break
                size //= 2
            writer = recipe.write_rgb24 if channel == "N" else recipe.write_dxt1
            writer(output / filename, args.tile_size, args.tile_size, levels)
            resources[name] = filename
            aliases.setdefault(name, {})[channel] = filename
            if channel == "D": previews.append((name, Image.fromarray(image).resize((160, 160))))
        channels[channel] = resources
        if previews:
            sheet = Image.new("RGB", (800, ((len(previews)+4)//5)*184), "#202020")
            draw = ImageDraw.Draw(sheet)
            for i, (name, image) in enumerate(previews):
                x, y = i % 5 * 160, i // 5 * 184
                sheet.paste(image, (x, y)); draw.text((x+3, y+163), name, fill="white")
            sheet.save(output / f"{args.world}_tiles.jpg")
    direction = json.loads(args.art_direction.read_text()) if args.art_direction else None
    if direction and not args.base_emissives:
        raise ValueError("World surface art requires the qualified source/emissive pipeline")
    build = source_function(recipe, sink, args.tile_size, height_matched_normals, args.base_emissives,direction)
    world = next(w for w in recipe.PLAN["worlds"] if w["world"] == args.world)
    report = build(world)
    for i, (name, entry) in enumerate(aliases.items()): entry["slice"] = i
    result = {"schema": "cr-hd-source-images-v1" if args.images_only else "cr-mars-hd-source-tiles-v1",
              "world": args.world, "tileSize": args.tile_size,
              "normalPolarity": "source-height-matched" if height_matched_normals else "saved-recipe",
              "sourceGenerationPixels": args.tile_size,
              "exporterSha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "sourceRecipeSha256": hashlib.sha256((root / "build_stock_atlases.py").read_bytes()).hexdigest(),
              "sources": report["sources"], "normalCorrections": report.get("normal_relief_overrides", {}),
              "normalEngineConversion": report.get("normal_engine_conversion", {}),
              "normalRotation": report.get("normal_rotation"),
              "baseEmissives": report.get("base_emissives"),
              "sourceHeightCorrections": report.get("source_height_corrections", {}),
              "surfaceBlend": surface_signature(args.world),
              "worldSurfaceArt": report.get("world_surface_art"),
              "transitions": report.get("transitions", []),
              "recipeInputs": {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                               for path in sorted(root.glob("*.py")) + sorted(root.glob("*.json"))},
              "aliases": aliases, "atlasPixelsRead": False}
    result["defaultAlias"] = report.get("default_alias_shared") or None
    if not args.images_only:
        write_manifest(output, args.capture, args.atlas_csv or output / "native_layout.csv", aliases, result["defaultAlias"])
    (output / "source_tiles.json").write_text(json.dumps(result, indent=2)+"\n")
    print(f"Exported {len(aliases)} full D/N/S/E tile sets to {output}", flush=True)


def require_mars_normal_policy(metadata):
    if (metadata.get("world", "mars") != "mars"
            or metadata.get("normalPolarity") != "source-height-matched"
            or metadata.get("normalCorrections")):
        raise ValueError("Existing Mars pack predates the source-height normal correction. "
                         "Generate into a new --output directory; existing artwork is preserved.")


def write_manifest(output, capture_path, csv_path, aliases, default_alias=None):
    capture = json.loads(capture_path.read_text(encoding="utf-8-sig")) if capture_path else {
        "material": "CRHD_MARS_EXAMPLE", "diffuseResource": "mars_atlas_d.dds",
        "channelResources": {"normal": "mars_atlas_n.dds", "specular": "mars_atlas_s.dds"}}
    first = next(iter(aliases.values()))
    binding = {"sliceCount": len(aliases), "releaseSourceTextures": True,
               "diffuseResource": capture["diffuseResource"], "fallback": first["D"],
               "tiles": {str(a["slice"]): a["D"] for a in aliases.values()}}
    if capture_path:
        binding["sliceRemap"] = bind_capture(capture, csv_path, aliases, default_alias)
    else:
        rects = {}
        with csv_path.open(encoding="utf-8-sig", newline="") as source:
            for row in csv.reader(source):
                if len(row) != 5: raise ValueError("Expected name,u,v,width,height CSV")
                name = row[0].strip().upper() or default_alias
                if name not in aliases: raise ValueError(f"Missing source tile alias: {name}")
                rect = tuple(float(value) for value in row[1:])
                slice_id = aliases[name]["slice"]
                if rect in rects and rects[rect] != slice_id:
                    raise ValueError("Ambiguous layout rectangle")
                rects[rect] = slice_id
        binding["tileRects"] = [{"rect": rect, "slice": slice_id} for rect, slice_id in rects.items()]
    for ch, key in [("N", "normal"), ("S", "specular")]:
        source = capture.get("channelResources", {}).get(key)
        if not source:
            raise ValueError(f"Native capture is missing the {key} resource identity")
        binding[key] = {"sourceResource": source, "fallback": first[ch],
                        "tiles": {str(a["slice"]): a[ch] for a in aliases.values()}}
        if ch == "N": binding[key]["encoding"] = "rgb-xyz-linear"
    manifest = {"schema": "bzr-openshim-terrain-hd-v2", "materials": {capture["material"]: binding}}
    (output / "cr_mars_hd.json").write_text(json.dumps(manifest, indent=2)+"\n")
    print(f"Prepared {len(aliases)} source tiles for {capture['material']} in {output}", flush=True)


if __name__ == "__main__": main()
