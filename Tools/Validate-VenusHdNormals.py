"""Validate Venus source-normal conventions, authored height slopes and runtime DDS."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

from bzmodellibs import toolbox_root

spec = importlib.util.spec_from_file_location("normal_audit", Path(__file__).with_name("Validate-MoonHdNormals.py"))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-build", type=Path, required=True)
    parser.add_argument("--images", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(toolbox_root()))
    from battlezone.images.dds import read_dds
    from battlezone.terrain.hd_tiles import check_bundle, inspect_dds
    from battlezone.images.bc1 import decode_bc1
    catalogue = {row["id"]: row for row in json.loads((args.source_build / "all_diffuse_candidates.json").read_text())}
    metadata = json.loads((args.images / "source_tiles.json").read_text())
    if metadata.get("world") != "venus" or metadata.get("normalCorrections") or metadata.get("atlasPixelsRead") is not False:
        raise ValueError("Expected independent Venus sources without empirical XY reversal")
    sources = []
    height_aliases = {"0b3bb7fc9238": "ve00sa0", "23e1e3c33291": "ve33sa0"}
    for uid in ("0b3bb7fc9238", "23e1e3c33291", "cc1e7aac9914", "cc26094103ba", "cc347a1d61cd"):
        source = catalogue[uid]
        raw, normal_hash = audit.read_channel(source, "N")
        vector = raw / 127.5 - 1
        slopes = vector[:, :, :2] / np.maximum(vector[:, :, 2:3], .25)
        slopes = gaussian_filter(slopes, (2, 2, 0), mode="wrap")
        mixed = audit.correlation(np.gradient(slopes[:, :, 0], axis=0), np.gradient(slopes[:, :, 1], axis=1))
        if mixed > -.60:
            raise ValueError(f"{source['name']}: supplied normal no longer supports opposite-Y convention")
        row = {"sourceId": uid, "name": source["name"], "normalSha256": normal_hash,
               "mixedDerivativeCorrelationBeforeGreenConversion": mixed, "engineConversion": "flip_green"}
        if uid in height_aliases:
            alias = height_aliases[uid]
            height, height_hash = audit.read_channel(source, "H")
            dy, dx = np.gradient(gaussian_filter(height, 1., mode="wrap"))
            exported = np.asarray(Image.open(args.images / f"{alias}_n.png"), np.float32) / 127.5 - 1
            scores = [audit.correlation(exported[:, :, 0], -dx), audit.correlation(exported[:, :, 1], -dy)]
            if min(scores) < .60:
                raise ValueError(f"{alias}: normals invert/mismatch authored height slopes: {scores}")
            row.update({"heightSha256": height_hash, "alias": alias.upper() + ".MAP",
                        "exportNxVersusNegativeHeightDx": scores[0], "exportNyVersusNegativeHeightDy": scores[1],
                        "absoluteReliefPolarity": "agrees with independently supplied height"})
        else:
            row["absoluteReliefPolarity"] = "unverified: no independently supplied height map"
        sources.append(row)
    count, minimum, maximum, nonpositive = 0, 2., 0., {}
    for path in (args.bundle / "resources").glob("*_n.dds"):
        levels, _ = read_dds(str(path))
        for level in levels:
            vector = level[:, :, :3].astype(np.float32) / 127.5 - 1
            lengths = np.linalg.norm(vector, axis=2)
            minimum, maximum = min(minimum, float(lengths.min())), max(maximum, float(lengths.max()))
            below = int(np.count_nonzero(vector[:, :, 2] <= 0))
            if below:
                nonpositive[path.name] = nonpositive.get(path.name, 0) + below
            count += 1
    if count != 143 or minimum < .985 or maximum > 1.015:
        raise ValueError(f"Invalid Venus normal mip vectors: count={count} length={minimum}..{maximum}")
    for path in (args.bundle / "resources").glob("*_e.dds"):
        info, payload = inspect_dds(path), path.read_bytes()
        for mip, (offset, size) in enumerate(zip(info["offsets"], info["sizes"])):
            edge = max(1, info["width"] >> mip)
            decoded = decode_bc1(payload[offset:offset+size], max(4, edge), max(4, edge))[:edge, :edge]
            base_tiles = ("ve22sa0", "ve22sb0", "ve02ca0", "ve02cb0", "ve02da0")
            if not any(alias in path.stem for alias in base_tiles) and np.any(decoded[:, :, :3]):
                raise ValueError("Only base surfaces may emit in the Venus recipe")
            if decoded.max() > 40:
                raise ValueError("Venus base emissives exceed their subtle authored range")
    report = {"schema": "cr-venus-hd-normal-validation-v1", "sources": sources,
              "normalMips": {"count": count, "minimumLength": minimum, "maximumLength": maximum,
                             "nonPositiveZTexels": nonpositive},
              "projectedBasis": audit.projected_shader_basis(), "rotations": audit.rotation_checks(args.source_build),
              "bundle": check_bundle(args.bundle), "emissive": "Sparse base accents only; natural ground/liquid/vent tiles remain black",
              "limitations": ["Three BZCC source normals have no independent height reference for absolute relief polarity.",
                              "Source/basis validation is separate from live GPU resource/draw qualification."]}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: two height pairs, five source Y conventions, {count} normal mips, subtle base-only emissive")


if __name__ == "__main__":
    main()
