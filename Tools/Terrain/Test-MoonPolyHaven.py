"""Independent normal/height polarity, periodic scale and legacy material checks."""
import importlib.util
from pathlib import Path
import unittest
import numpy as np

spec = importlib.util.spec_from_file_location("polyhaven",Path(__file__).with_name("Build-MoonPolyHaven.py"))
art = importlib.util.module_from_spec(spec)
spec.loader.exec_module(art)


class PolyHavenArt(unittest.TestCase):
    def test_normal_sign_is_measured_from_height_for_each_axis(self):
        y,x = np.mgrid[:128,:128]
        height = np.sin(x*2*np.pi/128)+.7*np.cos(y*4*np.pi/128)
        dy,dx = np.gradient(height)
        for sign_x,sign_y in ((1,1),(1,-1),(-1,1),(-1,-1)):
            vectors = np.stack((-dx*sign_x,-dy*sign_y,np.ones_like(dx)),axis=2)
            vectors /= np.linalg.norm(vectors,axis=2,keepdims=True)
            slopes,audit = art.normal_audit(vectors,height)
            self.assertEqual(audit["channelSigns"],[sign_x,sign_y])
            self.assertTrue(all(c>.99 for c in audit["convertedCorrelation"]))
            np.testing.assert_allclose(slopes,np.stack((-dx,-dy),axis=2),atol=1e-12)

    def test_unrelated_normal_and_height_are_not_guessed(self):
        rng = np.random.default_rng(23)
        with self.assertRaises(ValueError):
            art.normal_audit(rng.random((128,128,3)),rng.random((128,128)))

    def test_resampling_preserves_integer_periods_without_aliasing(self):
        y,x = np.mgrid[:64,:64]
        source = np.cos(x*2*np.pi/64)+np.sin(y*2*np.pi/64)
        result = art.periodic_sample(source,96,6)
        np.testing.assert_allclose(result,np.roll(result,16,axis=0),atol=1e-12)
        np.testing.assert_allclose(result,np.roll(result,16,axis=1),atol=1e-12)
        with self.assertRaises(ValueError):art.periodic_sample(source,96,6.25)
        checkerboard = ((x+y)%2).astype(float)
        filtered = art.periodic_sample(checkerboard,32,6)
        self.assertLess(float(filtered.std()),.001)

    def test_rough_dust_stays_matte_and_nonemissive(self):
        roughness = np.array([[0.,.5,1.]])
        result = art.specular_from_roughness(roughness,{"specularMinimum":10,"specularRange":24})
        np.testing.assert_array_equal(result[0,:,0],[34,16,10])
        self.assertTrue((result[:,:,0]==result[:,:,2]).all())


if __name__ == "__main__":
    unittest.main()
