"""Venus pack rebuild, identity guards, multi-world installation and preview checks."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from bzmodellibs import toolbox_root
from terrain_art_tuning import RUNTIME_DEFAULTS, binding_for, paint_problems

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(toolbox_root()))
from battlezone.terrain.hd_tiles import read_layout


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "Tools" / name)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class VenusHdTerrain(unittest.TestCase):
    def test_painted_venus_cannot_be_overwritten_by_a_dds_rebuild(self):
        builder = module("Build-HdTerrainBundle.py")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "terrain.json"
            path.write_text(json.dumps({"schema": "v2", "materials": {"VE_DETAIL_ATLAS": binding_for("venus")}}))
            before = path.read_bytes()
            with self.assertRaisesRegex(ValueError, "paint world"):
                builder.merge_manifest(path, {"schema": "v2", "materials": {"VE_DETAIL_ATLAS": {"sliceCount": 13}}})
            self.assertEqual(path.read_bytes(), before)

    def test_material_guards_mission_selection_and_layout(self):
        materials = json.loads((ROOT / "Config/cr_terrain_hd.json").read_text())["materials"]
        self.assertIn("MN_DETAIL_ATLAS", materials)
        binding = materials["VE_DETAIL_ATLAS"]
        self.assertEqual(binding["sliceCount"], 9)
        self.assertEqual(paint_problems("venus"), [])
        material = (ROOT / "Materials/ve_detail_atlas.material").read_text()
        self.assertIn(f"set_texture_alias DiffuseMap {binding['diffuseResource']}", material)
        self.assertEqual(read_layout(ROOT / "Config/ve_detail_atlas.csv", "VE00SA0.MAP"),
                         read_layout(ROOT / "Tools/TerrainHD/Venus/layout.csv", "VE00SA0.MAP"))
        for mission in ("misn07", "misn08", "misn09"):
            self.assertRegex((ROOT / f"Missions/{mission}.trn").read_text(), r"MaterialName\s*=\s*ve_detail_atlas")

    def test_installing_one_world_preserves_the_other_and_rejects_wrong_schema(self):
        builder = module("Build-HdTerrainBundle.py")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "terrain.json"
            moon = {"schema": "v2", "materials": {"MOON": {"tiles": "authored moon"}}}
            venus = {"schema": "v2", "materials": {"VENUS": {"tiles": "authored venus"}}}
            builder.merge_manifest(path, moon)
            builder.merge_manifest(path, venus)
            builder.merge_manifest(path, moon)
            self.assertEqual(json.loads(path.read_text())["materials"], {
                key: dict(RUNTIME_DEFAULTS, **value)
                for key, value in {**moon["materials"], **venus["materials"]}.items()})
            before = path.read_bytes()
            with self.assertRaisesRegex(ValueError, "another schema"):
                builder.merge_manifest(path, {"schema": "v1", "materials": {}})
            self.assertEqual(path.read_bytes(), before)

    def test_source_height_evidence_retains_unverified_bzcc_limit(self):
        evidence = json.loads((ROOT / "Tools/TerrainHD/Venus/normal_validation.json").read_text())
        for source in evidence["sources"][:2]:
            self.assertGreater(source["exportNxVersusNegativeHeightDx"], .60)
            self.assertGreater(source["exportNyVersusNegativeHeightDy"], .60)
        self.assertTrue(all("unverified" in row["absoluteReliefPolarity"] for row in evidence["sources"][2:]))
        self.assertEqual(evidence["normalMips"]["count"], 143)
        provenance = json.loads((ROOT / "Tools/TerrainHD/Venus/provenance.json").read_text())
        self.assertFalse(provenance["atlasPixelsRead"])
        self.assertEqual(provenance["normalCorrections"], {})

    def test_venus_camera_fixture_keeps_native_terrain(self):
        from battlezone.bzn.bz1 import read_bzn
        preview = module("Build-HdTerrainPreview.py")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "preview.bzn"
            with patch.object(sys, "argv", ["preview", "--source", str(ROOT / "Missions/misn08cr.bzn"), "--out", str(output)]):
                preview.main()
            mission = read_bzn(output)
            self.assertEqual(mission.terrain_name, "misn08")
            self.assertEqual(len(mission.objects), 1)
            self.assertEqual(mission.mission_name, "LuaMission")

    def test_shipping_membership(self):
        lock = json.loads((ROOT / "Shipping/shipping.lock.json").read_text(encoding="utf-8-sig"))
        files = {entry["source"].replace("\\", "/") for entry in lock["files"]}
        self.assertIn("Config/ve_detail_atlas.csv", files)
        self.assertEqual(list((ROOT / "Assets/Textures").glob("crhd_venus_*.dds")), [])


if __name__ == "__main__":
    unittest.main()
