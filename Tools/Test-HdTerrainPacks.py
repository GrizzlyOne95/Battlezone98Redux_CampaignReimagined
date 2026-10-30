"""Rebuild every shipped HD pack and verify sparse base-only authoring semantics."""
import importlib.util
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

import numpy as np
from bzmodellibs import toolbox_root
from terrain_hd_base_emissives import apply_base_emissives, apply_source_height_corrections
from terrain_art_tuning import RUNTIME_DEFAULTS, KEEP_DDS, binding_for, paint_problems

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(toolbox_root()))
from battlezone.terrain.hd_tiles import build_bundle, load_project


class HdPacks(unittest.TestCase):
    def test_pack_rebuild_preserves_world_relief_tuning(self):
        spec = importlib.util.spec_from_file_location("bundle", ROOT / "Tools/Build-HdTerrainBundle.py")
        bundle = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bundle)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "terrain.json"
            path.write_text(json.dumps({"schema": "v2", "materials": {
                "MN": {"microReliefScale": 2.5, "old": True},
                "MA": {"microReliefScale": 0.0}}}))
            bundle.merge_manifest(path, {"schema": "v2", "materials": {"MN": {"new": True}, "VE": {}}})
            self.assertEqual(json.loads(path.read_text())["materials"], {
                "MN": dict(RUNTIME_DEFAULTS, microReliefScale=2.5, new=True),
                "MA": {"microReliefScale": 0.0}, "VE": dict(RUNTIME_DEFAULTS)})

    def test_pack_rebuild_refuses_to_overwrite_a_paint_world(self):
        spec = importlib.util.spec_from_file_location("bundle", ROOT / "Tools/Build-HdTerrainBundle.py")
        bundle = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bundle)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "terrain.json"
            path.write_text(json.dumps({"schema": "v2", "materials": {"IO": {"paint": {}, "tiles": {}}}}))
            before = path.read_bytes()
            with self.assertRaisesRegex(ValueError, "paint world"):
                bundle.merge_manifest(path, {"schema": "v2", "materials": {"IO": {"sliceCount": 4}}})
            self.assertEqual(path.read_bytes(), before)

    def test_base_preview_swatch_preserves_source_terrain(self):
        from unittest.mock import patch
        from battlezone.terrain.hg2 import read_hg2
        from battlezone.terrain.mat import read_mat
        spec = importlib.util.spec_from_file_location("preview", ROOT / "Tools/Build-HdTerrainPreview.py")
        preview = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(preview)
        # CR renamed the BZN to misn08cr but terrain keeps the stock misn08 stem;
        # the preview reads terrain beside the source, so stage them together.
        terrain = ROOT / "Missions/misn08.mat"
        before = terrain.read_bytes()
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source/misn08.bzn"
            source.parent.mkdir()
            shutil.copyfile(ROOT / "Missions/misn08cr.bzn", source)
            for suffix in (".trn", ".hg2", ".mat"):
                shutil.copyfile(terrain.with_suffix(suffix), source.with_suffix(suffix))
            out = Path(temporary) / "fixture.bzn"
            with patch.object(sys, "argv", ["preview", "--source", str(source), "--out", str(out), "--base-type", "2"]):
                preview.main()
            header, _ = read_hg2(source.with_suffix(".hg2"))
            cells = read_mat(out.with_suffix(".mat"), header.zones_x, header.zones_z)
            self.assertEqual(np.count_nonzero((cells >> 12 == 2) & (((cells >> 8) & 15) == 2)), 25)
            self.assertEqual(source.with_suffix(".mat").read_bytes(), before)
        self.assertEqual(terrain.read_bytes(), before)

    def test_europa_height_correction_changes_only_the_target_normal_slopes(self):
        original = np.full((4, 4, 3), [80, 180, 240], np.uint8)
        bases = {"2fb5706a9216": original.copy(), "other": original.copy()}
        apply_source_height_corrections("europa", "D", bases, {})
        np.testing.assert_array_equal(bases["2fb5706a9216"], original)
        apply_source_height_corrections("europa", "N", bases, {})
        np.testing.assert_array_equal(bases["2fb5706a9216"][:, :, :2], 255-original[:, :, :2])
        np.testing.assert_array_equal(bases["2fb5706a9216"][:, :, 2], original[:, :, 2])
        np.testing.assert_array_equal(bases["other"], original)

    def test_every_world_rebuilds_and_preserves_other_world_materials(self):
        combined = json.loads((ROOT / "Config/cr_terrain_hd.json").read_text())["materials"]
        lock = json.loads((ROOT / "Shipping/shipping.lock.json").read_text(encoding="utf-8-sig"))
        shipped = {r["source"].replace("\\", "/") for r in lock["files"]}
        worlds = json.loads((ROOT / "Tools/TerrainHD/base_emissives.json").read_text())["worlds"]
        self.assertEqual(len(worlds), 9)
        for world in worlds:
            with self.subTest(world=world), tempfile.TemporaryDirectory() as temporary:
                if "paint" in binding_for(world):
                    self.assertEqual(paint_problems(world), [])
                    continue
                folder = ROOT / "Tools/TerrainHD" / world.title()
                project = load_project(folder / "authoring.json")
                out = Path(temporary) / "bundle"
                report = build_bundle(project, out)
                self.assertEqual(report["conversion"], {"preserved": report["resourceCount"], "converted": 0})
                evidence = json.loads((folder / "pack_validation.json").read_text())
                self.assertEqual(report["sha256"], evidence["bundle"]["sha256"])
                material = project["material"]
                expected = dict(combined[material])
                scale = expected.pop("microReliefScale")
                for key in ("detailContrast", "detailNormalStrength", "detailNormalNearScale", "surfaceBlend"):
                    expected.pop(key)
                if world == "moon":
                    self.assertEqual(expected.pop("heightTexture"), "crhd_moon_regolith_h.dds")
                    self.assertEqual(expected.pop("heightEncoding"), "signed-unit-r32")
                self.assertEqual(scale, 2.5 if world == "moon" else 1.0)
                self.assertEqual(json.loads((out / "terrain_hd_tiles.json").read_text())["materials"][material], expected)
                for channels in project["tiles"].values():
                    for source in channels.values():
                        self.assertIn(Path(source).relative_to(ROOT).as_posix(), shipped)
                self.assertIn(f"Config/{Path(project['layout']).name.replace('layout', material.lower())}", shipped)
                provenance = json.loads((folder / "provenance.json").read_text())
                self.assertFalse(provenance["atlasPixelsRead"])
                self.assertEqual(provenance["normalCorrections"], {})
                self.assertEqual(provenance["baseEmissives"]["schema"], "cr-base-emissive-accents-v1")

    def test_accepted_art_hashes_and_runtime_membership(self):
        acceptance = json.loads((ROOT / "Tools/TerrainHD/accepted_world_art.json").read_text())
        lock = json.loads((ROOT / "Shipping/shipping.lock.json").read_text(encoding="utf-8-sig"))
        shipped = {r["source"].replace("\\", "/") for r in lock["files"]}
        self.assertEqual(len(acceptance["worlds"]), 9)
        self.assertEqual(sum(len(w["sha256"]) for w in acceptance["worlds"].values()), 606)
        for key, world in acceptance["worlds"].items():
            painted = "paint" in binding_for(key)
            for name, digest in world["sha256"].items():
                if painted and name not in KEEP_DDS:
                    continue  # retired DDS tiles; paint_problems covers the replacement files
                relative = "Assets/Textures/" + name
                self.assertEqual(hashlib.sha256((ROOT / relative).read_bytes()).hexdigest(), digest)
                self.assertIn(relative, shipped)
        self.assertIn("set_texture_alias DetailMap crhd_moon_regolith_detail.dds",
                      (ROOT / "Materials/mn_detail_atlas.material").read_text())

    def test_base_accents_are_sparse_bounded_and_do_not_touch_other_materials(self):
        worlds = json.loads((ROOT / "Tools/TerrainHD/base_emissives.json").read_text())["worlds"]
        for world, settings in worlds.items():
            with self.subTest(world=world):
                base = np.zeros((512, 512, 3), np.uint8)
                soil = np.full_like(base, 123)
                bases = {"base": base.copy(), "soil": soil.copy()}
                for channel in "DNS":
                    apply_base_emissives(world, channel, {settings["type"]: "base"}, bases, {})
                    np.testing.assert_array_equal(bases["base"], base)
                report = {}
                apply_base_emissives(world, "E", {settings["type"]: "base"}, bases, report)
                lit = np.any(bases["base"], axis=2).mean()
                self.assertGreater(lit, 0)
                self.assertLess(lit, .005)
                self.assertLessEqual(int(bases["base"].max()), 32)
                np.testing.assert_array_equal(bases["soil"], soil)

    def test_emissives_are_inserted_before_variant_and_blend_generation(self):
        spec = importlib.util.spec_from_file_location("adapter", ROOT / "Tools/Build-MarsHdTileSources.py")
        adapter = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(adapter)
        from types import SimpleNamespace
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "recipe.py"
            path.write_text("""def build(world):
 report = {}
 for ch in 'E':
  channel_cell = 1
  source_by_type = {4: 'base'}
  bases = {'base': np.zeros((512,512,3),np.uint8)}
  apply_art5(world,ch,source_by_type,bases,report,None)
  apply_art6(world,ch,source_by_type,bases,report,None)
  tile_cache = {'A.MAP': bases['base'].copy()}
  if ch == 'E' and all(tile_cache.values()):
   raise AssertionError('must stop before packing')
 return report
""")
            seen = []
            recipe = SimpleNamespace(__file__=str(path), cell=512, np=np, apply_art6=lambda *args: None, apply_art5=lambda *args: None)
            adapter.source_function(recipe, lambda w,c,t,r: seen.append(t["A.MAP"]), base_emissives=True)("moon")
            self.assertGreater(int(seen[0].max()), 0)


if __name__ == "__main__":
    unittest.main()
