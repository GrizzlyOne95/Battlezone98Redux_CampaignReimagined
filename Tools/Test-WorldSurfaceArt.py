"""Protect recognizable palettes, source normals and natural/base emissives."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch
import numpy as np
from world_surface_art import apply,normal,slopes

ROOT=Path(__file__).resolve().parent.parent
POLICY=json.loads((ROOT/"Tools/TerrainHD/world_surface_art.json").read_text())


class WorldArt(unittest.TestCase):
    def test_all_worlds_are_explicit_and_colour_edits_are_bounded(self):
        self.assertEqual(len(POLICY["worlds"]),9)
        for world,entry in POLICY["worlds"].items():
            for spec in entry["types"].values():
                self.assertLessEqual(spec.get("neutralMix",0),.15)
                self.assertTrue(.9<=spec.get("brightness",1)<=1.1)
                self.assertTrue(.9<=spec.get("contrast",1)<=1.1)

    def test_ganymede_borrows_ice_structure_without_importing_blue_palette(self):
        uid="ground";old=np.full((128,128,3),[110,70,45],np.uint8)
        # Only light terrain is selected; untouched materials remain identical.
        policy={"schema":POLICY["schema"],"worlds":{"ganymede":{"types":{"1":POLICY["worlds"]["ganymede"]["types"]["1"]}}}}
        bases={uid:old.copy(),"base":old.copy()}
        # Europa's DDS reference tiles were retired for paint; stand in a textured reference.
        reference=np.random.default_rng(7).integers(60,200,(128,128,3),dtype=np.uint8)
        with patch("world_surface_art.reference",return_value=(reference,{})):
            apply("ganymede","D",{1:uid},bases,{},policy)
        np.testing.assert_allclose(bases[uid].mean(axis=(0,1)),np.array([110,70,45])*1.06,atol=1.2)
        np.testing.assert_array_equal(bases["base"],old)
        self.assertGreater(float(bases[uid].std()),1)

    def test_source_emissive_is_preserved_for_every_world(self):
        for world,entry in POLICY["worlds"].items():
            mapping={int(key):key for key in entry["types"]}
            bases={uid:np.full((32,32,3),[10,60,200],np.uint8) for uid in mapping.values()}
            before={key:value.copy() for key,value in bases.items()}
            apply(world,"E",mapping,bases,{},POLICY)
            for uid in bases:np.testing.assert_array_equal(before[uid],bases[uid])

    def test_normal_strength_changes_slope_without_reversing_relief(self):
        source=normal(np.full((16,16,2),[.2,-.1],np.float32))
        bases={"ground":source.copy()}
        apply("europa","N",{0:"ground"},bases,{}, {"schema":"test","worlds":{"europa":{"types":{"0":{"normalStrength":.5}}}}})
        np.testing.assert_allclose(slopes(bases["ground"]),slopes(source)*.5,atol=.008)


if __name__=="__main__":unittest.main()
