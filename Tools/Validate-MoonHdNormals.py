"""Independently check Moon source-height polarity, shader basis, rotations and DDS.

Source N/H pairs provide polarity evidence; diffuse brightness is never treated
as height. BZCC paving has no supplied height, so its absolute relief polarity
is explicitly unverified, even when its handedness passes integrability.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import io
import json
from pathlib import Path
import sys
import zipfile

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter


def normalized(vector):
    return vector / np.maximum(np.linalg.norm(vector, axis=-1, keepdims=True), 1e-9)


def correlation(a, b):
    return float(np.corrcoef(a[8:-8, 8:-8].ravel(), b[8:-8, 8:-8].ravel())[0, 1])


def projected_shader_basis():
    """Differentiate a projected plane, then evaluate the shader's actual crosses.

    Uses Ogre's GPU-program RH projection (clip w=-view z), screen y down,
    three oblique cameras, all quarter turns and mirrored UVs. Height geometry
    computes the independent expected normal; it does not reuse TBN math.
    """
    results = []
    for eye in (np.array([2., 3., 4.]), np.array([-3., 4., 2.]), np.array([4., 2., -3.])):
        back = normalized(eye)
        right = normalized(np.cross([0, 1, 0], back))
        up = np.cross(back, right)
        view = np.stack([right, up, back])
        origin = view @ -eye
        # Analytic screen-position derivatives of (vx/-vz, -vy/-vz).
        derivatives = view[:, [0, 2]]
        z = origin[2]
        screen = np.stack([(-derivatives[0] * z + origin[0] * derivatives[2]) / z**2,
                           (derivatives[1] * z - origin[1] * derivatives[2]) / z**2])
        inverse = np.linalg.inv(screen)
        dp1, dp2 = (derivatives @ inverse).T
        normal = view @ np.array([0., 1., 0.])
        for turn in range(4):
            angle = turn * np.pi / 2
            rotation = np.array([[np.cos(angle), -np.sin(angle)], [np.sin(angle), np.cos(angle)]])
            for mirrored in (False, True):
                uv = (np.diag([-1., 1.]) if mirrored else np.eye(2)) @ rotation
                duv1, duv2 = (uv @ inverse).T
                t = np.cross(normal, dp2) * duv1[0] + np.cross(dp1, normal) * duv2[0]
                b = np.cross(normal, dp2) * duv1[1] + np.cross(dp1, normal) * duv2[1]
                scale = 1 / np.sqrt(max(t @ t, b @ b))
                basis = np.stack([t * scale, b * scale, normal])
                slopes = np.array([.23, -.37])
                mapped = normalized(np.array([-slopes[0], -slopes[1], 1.]) @ basis)
                gradient = uv.T @ slopes
                geometry = normalized(view @ np.array([-gradient[0], 1., -gradient[1]]))
                cosine = float(mapped @ geometry)
                if cosine < .999999:
                    raise ValueError("Projected shader normal disagrees with independently displaced geometry")
                results.append(cosine)
    return {"cases": len(results), "minimumCosineToHeightGeometry": min(results),
            "projectionContract": "Ogre GPU-program RH: clip w=-view z; Direct3D screen y down",
            "upstreamProjectionSource": "https://github.com/OGRECave/ogre/blob/v1-9-0/RenderSystems/Direct3D11/src/OgreD3D11RenderSystem.cpp#L1473-L1523",
            "runtimeCameraQualification": "Requires live draw-level validation; analytical projection tests alone are not a game capture"}


def read_channel(source, key):
    name = source["channels"][key]
    if source.get("member"):
        with zipfile.ZipFile(source["path"]) as archive:
            if source.get("nested"):
                with zipfile.ZipFile(io.BytesIO(archive.read(source["nested"]))) as nested:
                    data = nested.read(name)
            else:
                data = archive.read(name)
    else:
        data = (Path(name) if Path(name).is_absolute() else Path(source["path"]).parent / name).read_bytes()
    with Image.open(io.BytesIO(data)) as image:
        array = np.asarray(image.convert("F" if key == "H" else "RGB").resize((1024, 1024), Image.Resampling.LANCZOS), np.float32)
    return array, hashlib.sha256(data).hexdigest()


def source_checks(source_build, images):
    catalogue = {r["id"]: r for r in json.loads((source_build / "all_diffuse_candidates.json").read_text())}
    results = []
    for uid, alias in (("92a81dc059aa", "mn00sa0"), ("97a97e4e6580", "mn33sa0")):
        source = catalogue[uid]
        height, height_hash = read_channel(source, "H")
        raw, normal_hash = read_channel(source, "N")
        exported = np.asarray(Image.open(images / f"{alias}_n.png"), np.float32) / 127.5 - 1
        dy, dx = np.gradient(gaussian_filter(height, 1., mode="wrap"))
        scores = [correlation(exported[:, :, 0], -dx), correlation(exported[:, :, 1], -dy)]
        if min(scores) < .60:
            raise ValueError(f"{alias}: exported normals invert/mismatch authored height slopes: {scores}")
        if np.any(exported[:, :, 2] <= 0):
            raise ValueError(f"{alias}: normal Z must face out of the surface")
        results.append({"sourceId": uid, "name": source["name"], "alias": alias.upper() + ".MAP",
                        "normalSha256": normal_hash, "heightSha256": height_hash,
                        "sourceNxVersusHeightDx": correlation(raw[:, :, 0], dx),
                        "sourceNyVersusHeightDy": correlation(raw[:, :, 1], dy),
                        "exportNxVersusNegativeHeightDx": scores[0], "exportNyVersusNegativeHeightDy": scores[1],
                        "decision": "Flip source green once; omit empirical XY reversal"})
    source = catalogue["ccf846357bf1"]
    normal, digest = read_channel(source, "N")
    n = normal / 127.5 - 1
    slopes = n[:, :, :2] / np.maximum(n[:, :, 2:3], .25)
    slopes = gaussian_filter(slopes, (2, 2, 0), mode="wrap")
    mixed = correlation(np.gradient(slopes[:, :, 0], axis=0), np.gradient(slopes[:, :, 1], axis=1))
    if mixed > -.60:
        raise ValueError("BZCC paving source no longer supports the audited opposite-Y convention")
    results.append({"sourceId": source["id"], "name": source["name"], "normalSha256": digest,
                    "mixedDerivativeCorrelationBeforeGreenConversion": mixed,
                    "decision": "Flip source green once; retain paving polarity",
                    "absoluteReliefPolarity": "unverified: source supplies no independent height map"})
    return results


def rotation_checks(source_build):
    tree = ast.parse((source_build / "build_stock_atlases.py").read_text())
    functions = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in ("renorm", "rot")]
    scope = {"np": np}
    exec(compile(ast.fix_missing_locations(ast.Module(body=functions, type_ignores=[])), "trusted-source-rotation", "exec"), scope)
    y, x = np.mgrid[0:256, 0:256] / 256
    height = np.sin(2*np.pi*(3*x+4*y)) + .4*np.sin(2*np.pi*(7*x-y))
    dy, dx = np.gradient(height)
    authored = np.uint8(np.clip((normalized(np.stack([-dx*5, -dy*5, np.ones_like(height)], 2)) + 1) * 127.5, 0, 255))
    results = []
    for turn in range(4):
        output = normalized(scope["rot"](authored, turn, "N").astype(np.float32) / 127.5 - 1)
        dy, dx = np.gradient(np.rot90(height, turn))
        expected = normalized(np.stack([-dx*5, -dy*5, np.ones_like(height)], 2))
        angles = np.degrees(np.arccos(np.clip(np.sum(output * expected, axis=2), -1, 1)))
        p95 = float(np.percentile(angles[4:-4, 4:-4], 95))
        if p95 > 1.5:
            raise ValueError(f"{turn*90}-degree source normal rotation disagrees with rotated height")
        results.append({"degrees": turn*90, "p95AngleToRotatedHeightNormal": p95})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-build", type=Path, required=True)
    parser.add_argument("--images", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--openshim", type=Path, required=True)
    parser.add_argument("--toolbox", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.toolbox))
    from battlezone.images.dds import read_dds
    from battlezone.terrain.hd_tiles import check_bundle
    shader = args.openshim / "resources/renderer/enhanced/openshim_enhanced_terrain-sm4.hlsl"
    text = shader.read_text()
    for contract in ("cross(N, dp2)", "cross(dp1, N)", "mul(shapedNormalTex, tbn)", "packedNormal.rgb * 2.0 - 1.0"):
        if contract not in text:
            raise ValueError("Shader contract changed; requalify the normal audit")
    specialize = args.openshim / "include/terrain_hd_material.h"
    if "cotangent_frame(geometryNormal, vViewPosition.xyz, openShimHdUV)" not in specialize.read_text():
        raise ValueError("HD channel basis must use the same local UV as normal sampling")
    report = {"schema": "cr-moon-hd-normal-validation-v1", "shaderSha256": hashlib.sha256(shader.read_bytes()).hexdigest(),
              "hdSpecializationSha256": hashlib.sha256(specialize.read_bytes()).hexdigest(),
              "projectedBasis": projected_shader_basis(), "sources": source_checks(args.source_build, args.images),
              "rotations": rotation_checks(args.source_build), "bundle": check_bundle(args.bundle)}
    minimum, maximum, mips = 2., 0., 0
    for path in (args.bundle / "resources").glob("*_n.dds"):
        levels, _ = read_dds(str(path))
        for level in levels:
            vectors = level[:, :, :3].astype(np.float32) / 127.5 - 1
            lengths = np.linalg.norm(vectors, axis=2)
            minimum, maximum = min(minimum, float(lengths.min())), max(maximum, float(lengths.max()))
            if np.any(vectors[:, :, 2] <= 0):
                raise ValueError(f"Normal points below the surface: {path.name}")
            mips += 1
    if minimum < .985 or maximum > 1.015:
        raise ValueError(f"Normals are not unit vectors within RGB8 quantization: {minimum}..{maximum}")
    report["normalMips"] = {"count": mips, "minimumLength": minimum, "maximumLength": maximum, "positiveZ": True}
    report["liveGameLighting"] = "unverified by this offline checker; see separate native run evidence"
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: source-height polarity, {report['projectedBasis']['cases']} projected basis cases, four rotations, {mips} normal mips")
    print("BZCC paving polarity has no independent source-height proof; native lighting remains a separate check.")


if __name__ == "__main__":
    main()
