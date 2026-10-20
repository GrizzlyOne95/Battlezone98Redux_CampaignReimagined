"""Compare exported Mars normal slopes with independently authored source height.

Optionally compare an older export: only gravel-containing normals may change;
diffuse, specular, emissive and unaffected normals must remain byte-identical.
No atlas pixels or diffuse-derived height are used.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

import numpy as np
from scipy.ndimage import gaussian_filter

from bzmodellibs import toolbox_root

spec = importlib.util.spec_from_file_location("moon_normal_checks", Path(__file__).with_name("Validate-MoonHdNormals.py"))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

SOURCES = (
    ("8d3ed1bbb4f9", "MA00SA0.MAP", .30),
    ("a8264dc12988", "MA11SA0.MAP", .60),
    ("6902a3b5990f", "MA33SA0.MAP", .80),
)
GRAVEL_ALIASES = {"MA11SA0.MAP", "MA11SB0.MAP", "MA11SC0.MAP",
                  "MA01CA0.MAP", "MA01DA0.MAP", "MA13CA0.MAP", "MA13DA0.MAP"}


def slope_scores(normal, height):
    dy, dx = np.gradient(gaussian_filter(height, 1., mode="wrap"))
    return [audit.correlation(normal[:, :, 0], -dx), audit.correlation(normal[:, :, 1], -dy)]


def require_matching_slopes(scores, minimum, alias):
    if not all(np.isfinite(score) and score > minimum for score in scores):
        raise ValueError(f"{alias}: normals invert/mismatch authored height slopes: {scores}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-build", type=Path, required=True)
    parser.add_argument("--export", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(toolbox_root()))
    from battlezone.images.dds import read_dds

    metadata = json.loads((args.export / "source_tiles.json").read_text())
    if (metadata.get("normalPolarity") != "source-height-matched"
            or metadata.get("normalCorrections") or metadata.get("atlasPixelsRead") is not False):
        raise ValueError("Expected source-height-matched independent Mars export")
    if args.baseline:
        baseline = json.loads((args.baseline / "source_tiles.json").read_text())
        for key in ("tileSize", "sourceGenerationPixels", "sourceRecipeSha256"):
            if metadata.get(key) != baseline.get(key):
                raise ValueError(f"Baseline must use the same source recipe and generation size: {key}")
    catalogue = {row["id"]: row for row in json.loads((args.source_build / "all_diffuse_candidates.json").read_text())}
    sources = []
    for uid, alias, minimum in SOURCES:
        height, height_hash = audit.read_channel(catalogue[uid], "H")
        _, source_normal_hash = audit.read_channel(catalogue[uid], "N")
        normal_path = args.export / metadata["aliases"][alias]["N"]
        levels, _ = read_dds(str(normal_path))
        # The source reader samples at 1K; evaluate a matching 1K mip for 2K packs.
        normal = next((level for level in levels if level.shape[:2] == height.shape), None)
        if normal is None:
            raise ValueError("Height audit requires a 1K or 2K pack")
        normal = normal[:, :, :3].astype(np.float32) / 127.5 - 1
        scores = slope_scores(normal, height)
        require_matching_slopes(scores, minimum, alias)
        row = {"sourceId": uid, "alias": alias, "name": catalogue[uid]["name"],
               "sourceNormalSha256": source_normal_hash, "sourceHeightSha256": height_hash,
               "exportNxVersusNegativeHeightDx": scores[0], "exportNyVersusNegativeHeightDy": scores[1]}
        if args.baseline:
            before, _ = read_dds(str(args.baseline / normal_path.name))
            matching = next(level for level in before if level.shape[:2] == height.shape)
            row["baselineSlopeCorrelations"] = slope_scores(matching[:, :, :3].astype(np.float32) / 127.5 - 1, height)
        sources.append(row)

    hashes, changed, mip_count, nonpositive_z = {}, [], 0, {}
    for alias, channels in metadata["aliases"].items():
        for channel in "DNSE":
            path = args.export / channels[channel]
            hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
            if args.baseline and path.read_bytes() != (args.baseline / path.name).read_bytes():
                if channel != "N" or alias not in GRAVEL_ALIASES:
                    raise ValueError(f"Unexpected change outside gravel normals: {path.name}")
                changed.append(path.name)
            if channel == "N":
                levels, _ = read_dds(str(path))
                for level in levels:
                    normal = level[:, :, :3].astype(np.float32) / 127.5 - 1
                    lengths = np.linalg.norm(normal, axis=2)
                    if lengths.min() < .985 or lengths.max() > 1.015:
                        raise ValueError(f"Invalid normal vector/mip: {path.name}")
                    count = int(np.count_nonzero(normal[:, :, 2] <= 0))
                    if count and alias in GRAVEL_ALIASES:
                        raise ValueError(f"Corrected gravel normal points below surface: {path.name}")
                    if count:
                        nonpositive_z[path.name] = nonpositive_z.get(path.name, 0) + count
                    mip_count += 1
    if args.baseline and len(changed) != len(GRAVEL_ALIASES):
        raise ValueError(f"Expected all seven gravel solids/transitions to change: {changed}")
    report = {"schema": "cr-mars-hd-normal-validation-v1", "tileSize": metadata["tileSize"],
              "sourceRecipeSha256": metadata["sourceRecipeSha256"], "baselineCompared": bool(args.baseline),
              "sources": sources, "normalMips": mip_count, "changedNormalFiles": sorted(changed),
              "unaffectedNonPositiveZTexels": nonpositive_z,
              "sha256": hashes, "projectedBasis": audit.projected_shader_basis(),
              "limitations": ["Base metal and vent sources have no independent source-height polarity proof.",
                              "Offline source/basis validation is separate from live GPU lighting qualification."]}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: three source-height pairs, {mip_count} normal mips, {len(changed)} corrected gravel normals")


if __name__ == "__main__":
    main()
