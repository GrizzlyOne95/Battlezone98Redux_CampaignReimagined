"""Checks the surface's normal convention and avoids duplicate macro relief."""
import importlib.util
import json
from pathlib import Path
import unittest

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("regolith", ROOT/"Tools/Build-MoonRegolith.py")
art = importlib.util.module_from_spec(spec)
spec.loader.exec_module(art)


class Regolith(unittest.TestCase):
    def test_normals_follow_negative_uv_height_gradient(self):
        y, x = np.mgrid[0:32, 0:32]
        normal = art.encode_normal(.1*x+.2*y, 1, 2.1)[16,16]/127.5-1
        # Undo the runtime's z/2.1 sharpening in slope space.
        np.testing.assert_allclose(normal[:2]/normal[2]*2.1, [-.1,-.2], atol=.012)
        self.assertGreater(normal[2], .99)

    def test_macro_craters_not_baked_into_micro_normal(self):
        settings = json.loads((ROOT/"Tools/TerrainHD/Moon/regolith.json").read_text())
        settings["tileSize"] = 256
        settings["dustHeightMeters"] = 0
        height, images = art.surface(settings)
        self.assertLess(float(height.min()), -.95)
        self.assertGreater(float(height.max()), .10)
        self.assertTrue(np.all(images["N"] == [128,128,255]))
        self.assertTrue(np.all(height[:9] == 0))
        self.assertTrue(np.all(height[:,:9] == 0))
        self.assertGreater(float((height == 0).mean()), .7)
        self.assertTrue((images["E"] == 0).all())

    def test_detail_flat_field_has_neutral_modulation_and_no_normal(self):
        result = art.audit_detail(Image.fromarray(np.full((32,32,3),128,np.uint8)))
        self.assertEqual(result["std"], 0)
        self.assertEqual(result["detailNormalDegreesMax"], 0)
        self.assertAlmostEqual(result["mean"], 128/255, places=6)

    def test_seed_reproduces_periodic_dust(self):
        first = art.noise(128, 43, 2)
        np.testing.assert_array_equal(first, art.noise(128,43,2))
        self.assertFalse(np.array_equal(first,art.noise(128,44,2)))
        self.assertLess(abs(float(first.mean())), 1e-6)
        self.assertAlmostEqual(float(first.std()), 1, places=6)

    def test_hd_art_is_preserved_outside_local_dust_coverage(self):
        settings = json.loads((ROOT/"Tools/TerrainHD/Moon/regolith.json").read_text())
        settings["tileSize"] = 256
        height, images = art.surface(settings)
        mask = art.dust_mask(height, settings)
        self.assertGreater(float((mask == 0).mean()), .80)
        self.assertLess(float(mask.mean()), .10)
        self.assertGreater(float(mask.max()), .7)
        original = np.random.default_rng(34).integers(0,256,(256,256,3),dtype=np.uint8)
        for channel in ("D", "N", "S", "E"):
            result = art.blend_surface(original, images[channel], mask, channel)
            np.testing.assert_array_equal(result[mask == 0],original[mask == 0])

    def test_full_dust_normal_blend_remains_unit_length(self):
        source = np.full((2,2,3),[200,100,230],np.uint8)
        dust = np.full((2,2,3),[128,128,255],np.uint8)
        result = art.blend_surface(source,dust,np.ones((2,2),np.float32),"N")
        np.testing.assert_array_equal(result,dust)

    def test_ground_variants_have_different_shapes_not_just_a_rotation(self):
        settings=json.loads((ROOT/"Tools/TerrainHD/Moon/regolith.json").read_text())
        settings["tileSize"]=256
        first,_=art.surface(settings)
        second,_=art.surface(dict(settings,**settings["variants"]["MN00SC0.MAP"]))
        self.assertGreater(float(np.std(first-second)),.10)
        for turn in range(4):
            self.assertFalse(np.allclose(first,np.rot90(second,turn)))
        self.assertTrue((second[:9]==0).all())
        self.assertGreater(float(first.max()),.3)

    def test_rim_readability_preserves_hd_outside_local_crater_masks(self):
        settings=json.loads((ROOT/"Tools/TerrainHD/Moon/regolith.json").read_text())
        settings["tileSize"]=256
        height,images=art.surface(settings)
        mask=art.dust_mask(height,settings)
        untouched=(mask==0)&(height<=0)
        self.assertGreater(float(untouched.mean()),.70)
        original=np.full((256,256,3),[100,160,240],np.uint8)
        for channel in "DNSE":
            result=art.local_material(original,images[channel],mask,channel,height,settings)
            np.testing.assert_array_equal(result[untouched],original[untouched])
        settings["surfaceCoverage"]=0
        for channel in "DNSE":
            result=art.local_material(original,images[channel],art.dust_mask(height,settings),channel,height,settings)
            np.testing.assert_array_equal(result,original)


if __name__ == "__main__":
    unittest.main()
