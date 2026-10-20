"""Audit all Toolbox packs, source conventions, normal mips and base emissives."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
from bzmodellibs import toolbox_root


def module(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-build", type=Path, required=True)
    parser.add_argument("--worlds", nargs="+", default=list(module("Build-HdTerrainBundle.py").WORLDS))
    args = parser.parse_args()
    sys.path.insert(0, str(toolbox_root()))
    from battlezone.images.dds import read_dds
    from battlezone.terrain.hd_tiles import check_bundle, inspect_dds
    from battlezone.images.bc1 import decode_bc1
    audit = module("Validate-MoonHdNormals.py")
    root = Path(__file__).resolve().parent.parent
    catalogue = {row["id"]: row for row in json.loads((args.source_build / "all_diffuse_candidates.json").read_text())}
    for world in args.worlds:
        bundle = root / f"Local/TerrainHD/{world.title()}Hd1024"
        images = root / f"Local/TerrainHD/{world.title()}HdSources1024"
        metadata = json.loads((images / "source_tiles.json").read_text())
        report = {"schema": "cr-hd-pack-validation-v1", "world": world, "bundle": check_bundle(bundle),
                  "baseEmissives": metadata["baseEmissives"], "sources": [], "normalMips": 0,
                  "nonPositiveZTexels": {}, "emissiveTiles": {}}
        if metadata["atlasPixelsRead"] or metadata["normalCorrections"]:
            raise ValueError("Expected independent sources without empirical XY reversals")
        for source in metadata["sources"]:
            uid = source["id"]
            row = {"id": uid, "name": source["name"], "engineConversion": metadata["normalEngineConversion"][uid]}
            original = catalogue[uid]
            if "H" in original.get("channels", {}):
                height, digest = audit.read_channel(original, "H")
                normal = np.asarray(Image.open(args.source_build / "material_cache" / uid / "N.png").convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS), np.float32) / 127.5 - 1
                if row["engineConversion"] == "flip_green":
                    normal[:, :, 1] *= -1
                if metadata.get("sourceHeightCorrections", {}).get(uid) == "invert_xy":
                    normal[:, :, :2] *= -1
                    row["sourceHeightCorrection"] = "invert_xy"
                dy, dx = np.gradient(gaussian_filter(height, 1., mode="wrap"))
                row["sourceHeightSha256"] = digest
                gradients = (-dx, -dy)
                scores = [audit.correlation(normal[:, :, i], gradient)
                          if np.std(gradient[8:-8, 8:-8]) > 1e-9 and np.std(normal[8:-8, 8:-8, i]) > 1e-9 else None
                          for i, gradient in enumerate(gradients)]
                row["convertedSourceSlopeCorrelations"] = scores
                row["heightQualification"] = "source pair only; recipe scale/compositing and final GPU shading are separate"
                if any(value is None for value in scores):
                    row["heightQualification"] = "unverified absolute polarity: supplied height/normal has no measurable slope variation"
                if all(value is not None for value in scores) and max(scores) < -.2:
                    raise ValueError(f"{world}: {uid} slopes oppose authored height")
                if uid == "2fb5706a9216":
                    levels, _ = read_dds(str(bundle / "resources/crhd_europa_eu22sa0_n.dds"))
                    emitted = levels[0][:, :, :3].astype(np.float32) / 127.5 - 1
                    scores = [audit.correlation(emitted[:, :, 0], -dx), audit.correlation(emitted[:, :, 1], -dy)]
                    if min(scores) < .30:
                        raise ValueError("Europa snowy-rock emitted normals still oppose source height")
                    row["emittedSolidSlopeCorrelations"] = scores
            else:
                row["heightQualification"] = "unverified absolute polarity: no independent source height"
            report["sources"].append(row)
        for path in sorted((bundle / "resources").glob("*_n.dds")):
            levels, _ = read_dds(str(path))
            for level in levels:
                vector = level[:, :, :3].astype(np.float32) / 127.5 - 1
                length = np.linalg.norm(vector, axis=2)
                if length.min() < .985 or length.max() > 1.015:
                    raise ValueError(f"Non-unit normal vector: {path.name}")
                count = int(np.count_nonzero(vector[:, :, 2] <= 0))
                if count:
                    report["nonPositiveZTexels"][path.name] = report["nonPositiveZTexels"].get(path.name, 0) + count
                report["normalMips"] += 1
        for path in sorted((bundle / "resources").glob("*_e.dds")):
            info = inspect_dds(path)
            payload = path.read_bytes()
            rgb = decode_bc1(payload[info["offsets"][0]:info["offsets"][0]+info["sizes"][0]], 1024, 1024)
            report["emissiveTiles"][path.name] = {"maximum": int(rgb.max()), "litFraction": float(np.any(rgb, axis=2).mean())}
        report["projectedBasis"] = audit.projected_shader_basis()
        report["limitations"] = ["Source height and analytical basis checks do not substitute for native GPU draw evidence.",
                                  "Nonpositive Z samples are inventoried; native source maps are not silently reauthored."]
        out = root / f"Tools/TerrainHD/{world.title()}/pack_validation.json"
        out.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
        print(f"PASS {world}: {report['bundle']['slices']} slices, {report['normalMips']} normal mips")


if __name__ == "__main__":
    main()
