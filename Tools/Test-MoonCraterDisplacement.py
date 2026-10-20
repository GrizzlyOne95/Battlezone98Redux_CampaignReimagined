"""Crater morphology, signed height limits and flat tile/paving boundaries."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("craters", ROOT/"Tools/Build-MoonCraterDisplacement.py")
craters = importlib.util.module_from_spec(spec)
spec.loader.exec_module(craters)


class CraterArt(unittest.TestCase):
    def setUp(self):
        self.settings = json.loads((ROOT/"Tools/TerrainHD/Moon/craters.json").read_text())
        self.layout = ROOT/"Config/mn_detail_atlas.csv"

    def test_bowls_rims_and_flat_ground(self):
        tile = craters.crater_tile(256, self.settings)
        self.assertLess(float(tile[87,87]), -.95)
        self.assertGreater(float(tile.max()), .15)
        self.assertEqual(float(tile[4,4]), 0)
        self.assertGreater(float((tile == 0).mean()), .6)
        self.assertTrue(np.isfinite(tile).all())
        self.assertGreaterEqual(float(tile.min()), -1)
        self.assertLessEqual(float(tile.max()), 1)

    def test_flat_borders_and_paving(self):
        height = craters.build(self.settings, self.layout)
        size = height.shape[0]//4
        for y in range(0, height.shape[0], size):
            for x in range(0, height.shape[1], size):
                tile = height[y:y+size,x:x+size]
                self.assertTrue((tile[:10] == 0).all())
                self.assertTrue((tile[-10:] == 0).all())
                self.assertTrue((tile[:,:10] == 0).all())
                self.assertTrue((tile[:,-10:] == 0).all())
        # Solid paving and both paving transitions have no crater displacement.
        for x, y in ((3,0),(1,1),(3,1),(0,2)):
            self.assertTrue((height[y*size:(y+1)*size,x*size:(x+1)*size] == 0).all())

    def test_edited_texture_can_add_relief_on_previously_flat_ground(self):
        edited = np.full((1024,1024), -.5, np.float32)
        height = craters.build(self.settings, self.layout, edited)
        self.assertEqual(float(height[128,128]), -.5)
        self.assertEqual(float(height[384,896]), 0)  # paving remains flat
        self.assertEqual(float(height[0,128]), 0)  # tile guard remains flat

    def test_invalid_art_settings_rejected(self):
        for key, value in (("size", 1000),("rimWidth", 0),("tileMeters", 0)):
            settings = copy.deepcopy(self.settings)
            settings[key] = value
            with self.assertRaises(ValueError):
                craters.build(settings, self.layout)

    def test_edit_roundtrip_does_not_apply_rock_gain_twice(self):
        original = craters.build(self.settings, self.layout)
        edited = craters.build(self.settings, self.layout, original)
        np.testing.assert_allclose(original, edited, atol=1e-6)


if __name__ == "__main__":
    unittest.main()
