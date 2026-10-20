"""World-specific tuning, authored overlay isolation and portable pack behavior."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image
import terrain_art_tuning as art


class TerrainArt(unittest.TestCase):
    def test_all_nine_worlds_are_explicit_and_mars_is_unchanged(self):
        for world in ("moon","mars","venus","io","europa","titan","achilles","ganymede","elysium"):
            binding = art.binding_for(world)
            self.assertTrue(set(art.RUNTIME_DEFAULTS) <= binding.keys())
            self.assertEqual(art.validate_runtime(binding),dict(art.RUNTIME_DEFAULTS,
                microReliefScale=2.5 if world=="moon" else 1.0))
            self.assertEqual(art.surface_coverage(binding),1.0 if world=="moon" else 0.)

    def test_invalid_fields_are_rejected(self):
        for key in art.RUNTIME_DEFAULTS:
            for bad in (-1,float("nan"),float("inf"),True,"1",art.RUNTIME_LIMITS[key]+.01):
                with self.subTest(key=key,bad=bad), self.assertRaises(ValueError):
                    art.validate_runtime({key:bad})
        with self.assertRaises(ValueError):
            art.surface_coverage({"surfaceBlend":{"coverage":1.01}})

    def test_rebuild_preserves_each_world_tuning_and_authored_surface(self):
        spec = importlib.util.spec_from_file_location("bundle",Path(__file__).with_name("Build-HdTerrainBundle.py"))
        bundle = importlib.util.module_from_spec(spec); spec.loader.exec_module(bundle)
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/"pack.json"
            old={"schema":"v2","materials":{"MN":dict(art.RUNTIME_DEFAULTS,detailNormalStrength=.7,
                 surfaceBlend={"coverage":.5}),"MA":dict(art.RUNTIME_DEFAULTS)}}
            path.write_text(json.dumps(old))
            bundle.merge_manifest(path,{"schema":"v2","materials":{"MN":{"sliceCount":11}}})
            current=json.loads(path.read_text())
            self.assertEqual(current["materials"]["MA"],old["materials"]["MA"])
            self.assertEqual(current["materials"]["MN"]["detailNormalStrength"],.7)
            self.assertEqual(current["materials"]["MN"]["surfaceBlend"],{"coverage":.5})

    def test_authored_mask_blends_all_channels_before_transitions(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); (root/"Config").mkdir()
            mask=np.zeros((8,8),np.uint8); mask[2:6,2:6]=255
            Image.fromarray(mask).save(root/"Config/mask.png")
            for channel in "DNSE":
                image=np.full((8,8,3),[128,128,255] if channel=="N" else [180,180,180],np.uint8)
                Image.fromarray(image).save(root/f"Config/{channel}.png")
            binding={"surfaceBlend":{"coverage":.5,"sourceType":0,"mask":"mask.png",
                      "channels":{c:f"{c}.png" for c in "DNSE"}}}
            with patch.object(art,"ROOT",root),patch.object(art,"binding_for",return_value=binding):
                signature=art.surface_signature("venus")
                for channel in "DNSE":
                    source=np.full((8,8,3),[128,128,255] if channel=="N" else [80,80,80],np.uint8)
                    bases={"ground":source.copy(),"base":source.copy()}
                    art.apply_authored_surface("venus",channel,{0:"ground"},bases,{})
                    np.testing.assert_array_equal(bases["ground"][mask==0],source[mask==0])
                    np.testing.assert_array_equal(bases["base"],source)
                    if channel!="N": self.assertEqual(int(bases["ground"][3,3,0]),130)
                Image.fromarray(np.full((8,8),128,np.uint8)).save(root/"Config/mask.png")
                self.assertNotEqual(signature,art.surface_signature("venus"))
                binding["surfaceBlend"]["coverage"]=0
                self.assertIsNone(art.surface_signature("venus"))

    def test_enable_without_authored_assets_fails_clearly(self):
        with patch.object(art,"binding_for",return_value={"surfaceBlend":{"coverage":1,"channels":{}}}):
            with self.assertRaises(ValueError): art.surface_signature("venus")

    def test_zero_coverage_does_not_load_or_change_material(self):
        original=np.full((4,4,3),[80,120,230],np.uint8)
        bases={"ground":original.copy()}
        with patch.object(art,"binding_for",return_value={"surfaceBlend":{"coverage":0}}):
            art.apply_authored_surface("mars","N",{0:"ground"},bases,{})
        np.testing.assert_array_equal(bases["ground"],original)


if __name__=="__main__": unittest.main()
