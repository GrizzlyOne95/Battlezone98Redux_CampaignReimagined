#!/usr/bin/env python3
"""CPU reference and deterministic packing tests for Enhanced Material V2."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import math
import tempfile
import unittest
from pathlib import Path

from PIL import Image


TOOLS = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "enhanced_material_map", TOOLS / "Build-EnhancedMaterialMap.py"
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Build-EnhancedMaterialMap.py")
PACKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKER)

PI = math.pi
MIN_ROUGHNESS = 0.12
MAX_ROUGHNESS = 0.92
MAX_IBL_MIP = 7.0

REFERENCE_MATERIALS = {
    "matte dielectric paint": ((0.04, 0.04, 0.04), 0.80),
    "smooth painted surface": ((0.04, 0.04, 0.04), 0.25),
    "rough exposed metal-like": ((0.55, 0.48, 0.38), 0.68),
    "smooth reflective metal-like": ((0.78, 0.64, 0.45), 0.18),
    "rubber/plastic": ((0.025, 0.025, 0.025), 0.88),
    "ice/glass-like": ((0.08, 0.10, 0.12), 0.20),
}


def clamp(value: float, low: float, high: float) -> float:
    return min(max(value, low), high)


def material_v2_input(f0: tuple[float, float, float], roughness: float):
    return tuple(clamp(value, 0.0, 1.0) for value in f0), clamp(
        roughness, MIN_ROUGHNESS, MAX_ROUGHNESS
    )


def distribution_ggx(ndoth: float, roughness: float) -> float:
    a = max(roughness * roughness, 1.0e-4)
    a2 = a * a
    denom = ndoth * ndoth * (a2 - 1.0) + 1.0
    return a2 / max(PI * denom * denom, 1.0e-6)


def geometry_schlick_ggx(ndotx: float, roughness: float) -> float:
    k = (roughness + 1.0) ** 2 * 0.125
    return ndotx / max(ndotx * (1.0 - k) + k, 1.0e-6)


def fresnel_schlick(costheta: float, f0: tuple[float, float, float]):
    m5 = clamp(1.0 - costheta, 0.0, 1.0) ** 5
    return tuple(value + (1.0 - value) * m5 for value in f0)


def specular_brdf(
    ndotv: float,
    ndotl: float,
    ndoth: float,
    vdoth: float,
    f0: tuple[float, float, float],
    roughness: float,
):
    d = distribution_ggx(ndoth, roughness)
    g = geometry_schlick_ggx(ndotv, roughness) * geometry_schlick_ggx(ndotl, roughness)
    f = fresnel_schlick(vdoth, f0)
    denominator = max(4.0 * ndotv * ndotl, 1.0e-5)
    return tuple(d * g * channel / denominator for channel in f)


def legacy_specular_to_f0(specular: tuple[float, float, float]):
    values = tuple(clamp(value, 0.0, 1.0) for value in specular)
    peak = max(values)
    tint = tuple(value / peak for value in values) if peak > 1.0e-4 else (1.0, 1.0, 1.0)
    strength = 0.04 + (0.45 - 0.04) * peak**1.35
    blend = clamp(peak * 0.90, 0.0, 1.0)
    return tuple(clamp(0.04 + (tint[i] * strength - 0.04) * blend, 0.0, 1.0) for i in range(3))


def legacy_roughness(shininess: float, specular_mask: float) -> float:
    roughness = math.sqrt(2.0 / (max(shininess, 0.0) + 2.0))
    roughness = clamp(roughness, MIN_ROUGHNESS, MAX_ROUGHNESS)
    smoothness_bias = (specular_mask - 0.5) * 2.0
    return clamp(roughness * (1.0 - smoothness_bias * 0.10), MIN_ROUGHNESS, MAX_ROUGHNESS)


class MaterialMathTests(unittest.TestCase):
    def test_synthetic_reference_materials_are_bounded_and_finite(self):
        for name, (f0, roughness) in REFERENCE_MATERIALS.items():
            with self.subTest(name=name):
                mapped_f0, mapped_roughness = material_v2_input(f0, roughness)
                self.assertTrue(all(0.0 <= value <= 1.0 for value in mapped_f0))
                self.assertGreaterEqual(mapped_roughness, MIN_ROUGHNESS)
                self.assertLessEqual(mapped_roughness, MAX_ROUGHNESS)
                result = specular_brdf(0.8, 0.75, 0.94, 0.91, mapped_f0, mapped_roughness)
                self.assertTrue(all(math.isfinite(value) and value >= 0.0 for value in result))

    def test_invalid_texture_values_clamp_safely(self):
        f0, roughness = material_v2_input((-4.0, 0.5, 8.0), float("inf"))
        self.assertEqual(f0, (0.0, 0.5, 1.0))
        self.assertEqual(roughness, MAX_ROUGHNESS)
        f0, roughness = material_v2_input((0.2, 0.3, 0.4), -2.0)
        self.assertEqual(roughness, MIN_ROUGHNESS)

    def test_roughness_reduces_peak_and_broadens_lobe(self):
        smooth = 0.18
        rough = 0.68
        self.assertGreater(distribution_ggx(1.0, smooth), distribution_ggx(1.0, rough))
        smooth_relative_off_axis = distribution_ggx(0.90, smooth) / distribution_ggx(1.0, smooth)
        rough_relative_off_axis = distribution_ggx(0.90, rough) / distribution_ggx(1.0, rough)
        self.assertGreater(rough_relative_off_axis, smooth_relative_off_axis)

    def test_increasing_f0_increases_reflected_energy(self):
        low = specular_brdf(0.8, 0.8, 0.95, 0.9, (0.04, 0.04, 0.04), 0.35)
        high = specular_brdf(0.8, 0.8, 0.95, 0.9, (0.45, 0.45, 0.45), 0.35)
        self.assertTrue(all(high[i] > low[i] for i in range(3)))

    def test_ibl_mip_is_monotonic_with_roughness(self):
        mips = [clamp(value, MIN_ROUGHNESS, MAX_ROUGHNESS) * MAX_IBL_MIP for value in (0.0, 0.2, 0.5, 1.0)]
        self.assertEqual(mips, sorted(mips))
        self.assertGreater(len(set(mips)), 1)

    def test_grazing_fresnel_is_bounded_and_rises(self):
        f0 = (0.04, 0.08, 0.12)
        normal = fresnel_schlick(1.0, f0)
        grazing = fresnel_schlick(0.0, f0)
        self.assertEqual(normal, f0)
        self.assertTrue(all(abs(value - 1.0) < 1.0e-12 for value in grazing))

    def test_legacy_mapping_reference_values_are_stable(self):
        # These snapshots protect the CPU expression used in audits/tools; the
        # stronger acceptance gate is byte-identical fxc output from the legacy
        # shader permutations (Compare-DX11ShaderBinaries.ps1).
        expected_f0 = (0.2584177030, 0.1348088515, 0.0730044258)
        actual_f0 = legacy_specular_to_f0((0.8, 0.4, 0.2))
        for actual, expected in zip(actual_f0, expected_f0):
            self.assertAlmostEqual(actual, expected, places=8)
        self.assertAlmostEqual(legacy_roughness(32.0, 0.5), 0.2425356250, places=8)


class PackingTests(unittest.TestCase):
    def test_constant_pack_is_exact_and_deterministic(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = PACKER.build_material_image(None, None, (0.04, 0.50, 1.0), 0.25, (2, 1))
            first = root / "first.dds"
            second = root / "second.dds"
            PACKER.write_dds(first, image)
            PACKER.write_dds(second, image)
            self.assertEqual(hashlib.sha256(first.read_bytes()).digest(), hashlib.sha256(second.read_bytes()).digest())
            payload = first.read_bytes()[128:]
            # DDS masks specify BGRA byte order: B, G, R, A.
            self.assertEqual(payload, bytes((255, 128, 10, 64)) * 2)

    def test_image_channels_round_trip_without_resizing_or_gamma(self):
        specular = Image.new("RGB", (2, 1))
        specular.putdata([(1, 2, 3), (253, 254, 255)])
        roughness = Image.new("L", (2, 1))
        roughness.putdata([4, 252])
        packed = PACKER.build_material_image(specular, roughness, None, None, None)
        self.assertEqual(list(packed.getdata()), [(1, 2, 3, 4), (253, 254, 255, 252)])

    def test_dimension_mismatch_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "dimensions do not match"):
            PACKER.build_material_image(Image.new("RGB", (2, 2)), Image.new("L", (1, 2)), None, None, None)

    def test_out_of_range_constants_are_rejected(self):
        with self.assertRaises(argparse.ArgumentTypeError):
            PACKER.normalized_triplet("0.04,1.2,0.04")
        with self.assertRaises(argparse.ArgumentTypeError):
            PACKER.normalized_scalar("-0.1")


if __name__ == "__main__":
    unittest.main(verbosity=2)
