"""Shipped Moon pack, shared Toolbox rebuild and independently tested normal basis."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image

from bzmodellibs import toolbox_root
from terrain_art_tuning import binding_for, paint_problems

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(toolbox_root()))
try:
    from battlezone.terrain.hd_tiles import read_layout
except ImportError as exc:
    raise RuntimeError("Set BZ_TOOLBOX_DIR to Toolbox with HD terrain authoring (PR #36 / ec0fce2)") from exc


def module(filename):
    spec = importlib.util.spec_from_file_location(filename, ROOT / "Tools" / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class MoonHdTerrain(unittest.TestCase):
    def test_native_material_identity_and_moon_missions(self):
        manifest = json.loads((ROOT / "Config/cr_terrain_hd.json").read_text())
        self.assertIn("MN_DETAIL_ATLAS", manifest["materials"])
        binding = manifest["materials"]["MN_DETAIL_ATLAS"]
        self.assertEqual(binding["sliceCount"], 9)
        self.assertEqual(paint_problems("moon"), [])
        self.assertEqual(read_layout(ROOT / "Config/mn_detail_atlas.csv", "MN00SA0.MAP"),
                         read_layout(ROOT / "Tools/TerrainHD/Moon/layout.csv", "MN00SA0.MAP"))
        material = (ROOT / "Materials/mn_detail_atlas.material").read_text()
        self.assertIn(f"set_texture_alias DiffuseMap {binding['diffuseResource']}", material)
        for mission in ("misn02b", "misn03"):
            self.assertRegex((ROOT / f"Missions/{mission}.trn").read_text(), r"MaterialName\s*=\s*mn_detail_atlas")

    def test_painted_moon_cannot_be_overwritten_by_a_dds_rebuild(self):
        # The DDS pack was retired for OpenShim paint; rebuilding it would clobber the paint binding.
        builder = module("Build-HdTerrainBundle.py")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "terrain.json"
            path.write_text(json.dumps({"schema": "v2", "materials": {"MN_DETAIL_ATLAS": binding_for("moon")}}))
            before = path.read_bytes()
            with self.assertRaisesRegex(ValueError, "paint world"):
                builder.merge_manifest(path, {"schema": "v2", "materials": {"MN_DETAIL_ATLAS": {"sliceCount": 11}}})
            self.assertEqual(path.read_bytes(), before)

    def test_height_evidence_and_shader_basis_are_not_empirical_polarity_guesses(self):
        audit = module("Validate-MoonHdNormals.py")
        self.assertEqual(audit.projected_shader_basis()["cases"], 24)
        report = json.loads((ROOT / "Tools/TerrainHD/Moon/normal_validation.json").read_text())
        for source in report["sources"][:2]:
            self.assertGreater(source["exportNxVersusNegativeHeightDx"], .60)
            self.assertGreater(source["exportNyVersusNegativeHeightDy"], .60)
        self.assertIn("unverified", report["sources"][2]["absoluteReliefPolarity"])
        self.assertEqual(report["normalMips"]["count"], 121)
        self.assertTrue(report["normalMips"]["positiveZ"])
        provenance = json.loads((ROOT / "Tools/TerrainHD/Moon/provenance.json").read_text())
        self.assertEqual(provenance["normalPolarity"], "source-height-matched")
        self.assertEqual(provenance["normalCorrections"], {})
        self.assertFalse(provenance["atlasPixelsRead"])

    def test_height_matching_omits_only_empirical_relief_override(self):
        adapter = module("Build-MarsHdTileSources.py")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "recipe.py"
            path.write_text("""def build(world):
 report = {}
 for ch in 'DNSE':
  channel_cell = 1
  relief = {'ground': {'invert_xy': True}}
  tile_cache = {'A.MAP': bool(relief)}
  if ch == 'E' and all(tile_cache.values()):
   raise AssertionError('packing must not run')
 return report
""")
            seen = []
            recipe = SimpleNamespace(__file__=str(path), cell=1344)
            adapter.source_function(recipe, lambda w, c, t, r: seen.append(t),
                                    1024, height_matched_normals=True)("moon")
            self.assertEqual(seen, [{"A.MAP": False}] * 4)

    def test_height_audit_rejects_the_opposite_relief_direction(self):
        audit = module("Validate-MoonHdNormals.py")
        y, x = np.mgrid[0:64, 0:64] / 64
        height = np.sin(2*np.pi*(3*x+2*y)) + .3*np.sin(2*np.pi*(x-5*y))
        dy, dx = np.gradient(height)
        raw = (audit.normalized(np.stack([-dx, dy, np.ones_like(height)], 2)) + 1) * 127.5
        converted = np.uint8(raw)
        converted[:, :, 1] = 255 - converted[:, :, 1]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rows = [{"id": uid, "name": uid} for uid in ("92a81dc059aa", "97a97e4e6580", "ccf846357bf1")]
            (root / "all_diffuse_candidates.json").write_text(json.dumps(rows))
            def read_channel(source, key):
                return (height if key == "H" else raw), "test-hash"
            for alias in ("mn00sa0", "mn33sa0"):
                Image.fromarray(converted).save(root / f"{alias}_n.png")
            with patch.object(audit, "read_channel", side_effect=read_channel):
                self.assertEqual(len(audit.source_checks(root, root)), 3)
                reversed_normal = converted.copy()
                reversed_normal[:, :, :2] = 255 - reversed_normal[:, :, :2]
                Image.fromarray(reversed_normal).save(root / "mn00sa0_n.png")
                with self.assertRaisesRegex(ValueError, "invert/mismatch"):
                    audit.source_checks(root, root)

    def test_camera_fixture_retains_terrain_and_points_to_its_player(self):
        from battlezone.bzn.bz1 import read_bzn
        fixture = module("Build-HdTerrainPreview.py")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "preview.bzn"
            with patch.object(sys, "argv", ["preview", "--source", str(ROOT / "Missions/misn03cr.bzn"), "--out", str(output)]):
                fixture.main()
            mission = read_bzn(output)
            self.assertEqual(mission.terrain_name, "misn03")
            self.assertEqual(mission.mission_name, "LuaMission")
            self.assertEqual(len(mission.objects), 1)
            self.assertEqual(mission.mission["sObject"].value, mission.objects[0].fields["obj_addr"].value)

    def test_shipping_lock_contains_runtime_assets_and_excludes_authoring_masters(self):
        lock = json.loads((ROOT / "Shipping/shipping.lock.json").read_text(encoding="utf-8-sig"))
        files = {entry["source"].replace("\\", "/") for entry in lock["files"]}
        self.assertIn("Config/cr_terrain_hd.json", files)
        self.assertIn("Config/mn_detail_atlas.csv", files)
        for texture in (ROOT / "Assets/Textures").glob("crhd_moon_*.dds"):
            self.assertIn(texture.relative_to(ROOT).as_posix(), files)
        self.assertFalse(any(name.startswith(("Tools/TerrainHD/", "Local/")) for name in files))


if __name__ == "__main__":
    unittest.main()
