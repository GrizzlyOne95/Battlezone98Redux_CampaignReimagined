"""Small offline checks for the source-tile adapter and native capture binding."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("mars_tiles", Path(__file__).with_name("Build-MarsHdTileSources.py"))
tiles = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tiles)


class SourceTiles(unittest.TestCase):
    def test_height_check_accepts_outward_relief_and_rejects_reversed_slopes(self):
        import numpy as np
        validation_spec = importlib.util.spec_from_file_location("mars_normals", Path(__file__).with_name("Validate-MarsHdNormals.py"))
        validation = importlib.util.module_from_spec(validation_spec)
        validation_spec.loader.exec_module(validation)
        y, x = np.mgrid[0:128, 0:128] / 128
        height = np.sin(2*np.pi*(3*x+2*y)) + .3*np.sin(2*np.pi*(x-5*y))
        dy, dx = np.gradient(height)
        normal = validation.audit.normalized(np.stack([-dx, -dy, np.ones_like(height)], 2))
        validation.require_matching_slopes(validation.slope_scores(normal, height), .95, "synthetic")
        normal[:, :, :2] *= -1
        with self.assertRaisesRegex(ValueError, "invert/mismatch"):
            validation.require_matching_slopes(validation.slope_scores(normal, height), .95, "synthetic")

    def test_stale_pack_rejected_before_rebinding_without_touching_art(self):
        import sys
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            metadata = output / "source_tiles.json"
            metadata.write_text(json.dumps({"tileSize": 1024}))
            art = output / "custom_n.dds"
            art.write_bytes(b"custom artist data")
            with patch.object(sys, "argv", ["export", "--bind-existing", "--output", str(output)]):
                with self.assertRaisesRegex(ValueError, "new --output directory"):
                    tiles.main()
            self.assertEqual(art.read_bytes(), b"custom artist data")
            self.assertFalse((output / "cr_mars_hd.json").exists())
        tiles.require_mars_normal_policy({"world": "mars", "normalPolarity": "source-height-matched",
                                          "normalCorrections": {}})
        with self.assertRaises(ValueError):
            tiles.require_mars_normal_policy({"normalPolarity": "source-height-matched",
                                              "normalCorrections": {"a8264dc12988": {"invert_xy": True}}})

    def test_pack_binds_without_a_capture_and_rejects_ambiguous_layout(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            csv = output / 'native_layout.csv'
            csv.write_text('B.MAP,0.5,0,0.5,1\nA.MAP,0,0,0.5,1\n,0,0,1,1\n')
            aliases = {name: {'slice': index, **{ch: f'{name}_{ch}.dds' for ch in 'DNS'}}
                       for index, name in enumerate(('A.MAP', 'B.MAP'))}
            tiles.write_manifest(output, None, csv, aliases, 'A.MAP')
            manifest = json.loads((output / 'cr_mars_hd.json').read_text())
            binding = manifest['materials']['CRHD_MARS_EXAMPLE']
            self.assertNotIn('sliceRemap', binding)
            self.assertEqual(binding['tileRects'], [
                {'rect': [.5, 0, .5, 1], 'slice': 1},
                {'rect': [0, 0, .5, 1], 'slice': 0},
                {'rect': [0, 0, 1, 1], 'slice': 0}])
            self.assertTrue(binding['releaseSourceTextures'])
            self.assertEqual(binding['normal']['sourceResource'], 'mars_atlas_n.dds')
            self.assertEqual(binding['specular']['sourceResource'], 'mars_atlas_s.dds')
            csv.write_text(csv.read_text() + 'B.MAP,0,0,0.5,1\n')
            with self.assertRaisesRegex(ValueError, 'Ambiguous layout rectangle'):
                tiles.write_manifest(output, None, csv, aliases, 'A.MAP')

    def test_capture_uses_rectangles_not_csv_order(self):
        with tempfile.TemporaryDirectory() as directory:
            csv = Path(directory) / "tiles.csv"
            csv.write_text("B.MAP,0.5,0,0.5,1\nA.MAP,0,0,0.5,1\n")
            capture = {"schema": "bzr-openshim-terrain-atlas-v1", "usedIndices": [37, 91],
                       "tiles": {"37": [0, 0, .5, 1], "91": [.5, 0, .5, 1]}}
            aliases = {"A.MAP": {"slice": 0}, "B.MAP": {"slice": 1}}
            result = tiles.bind_capture(capture, csv, aliases)
            self.assertEqual(len(result), 256)
            self.assertEqual((result[37], result[91]), (0, 1))
            capture["usedIndices"].append(99)
            with self.assertRaisesRegex(ValueError, "Used native tile 99"):
                tiles.bind_capture(capture, csv, aliases)
            csv.write_text(csv.read_text() + ",0,0,1,1\n")
            capture["tiles"]["99"] = [0, 0, 1, 1]
            with self.assertRaisesRegex(ValueError, "Used native tile 99"):
                tiles.bind_capture(capture, csv, aliases)
            self.assertEqual(tiles.bind_capture(capture, csv, aliases, "A.MAP")[99], 0)

    def test_source_generation_stops_before_packing(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "recipe.py"
            source.write_text("""def build(world):
 report = {}
 for ch in 'DNSE':
  channel_cell = 1
  tile_cache = {'A.MAP': channel_cell}
  if ch == 'E' and all(tile_cache.values()):
   raise AssertionError('packing must never execute')
  raise AssertionError('atlas encoding must never execute')
 raise AssertionError('atlas file writes must never execute')
""")
            seen = []
            module = SimpleNamespace(__file__=str(source), cell=1344)
            function = tiles.source_function(module, lambda w, ch, cache, report: seen.append((ch, cache)))
            self.assertEqual(function("mars"), {})
            self.assertEqual([ch for ch, cache in seen], list("DNSE"))
            self.assertTrue(all(cache == {"A.MAP": 1344} for ch, cache in seen))
            seen.clear()
            tiles.source_function(module, lambda w, ch, cache, report: seen.append(cache), 2048)("mars")
            self.assertTrue(all(cache == {"A.MAP": 2048} for cache in seen))
            source.write_text("def build(world):\n return {}\n")
            with self.assertRaisesRegex(ValueError, "one material-channel loop"):
                tiles.source_function(module, None)


def verify_export(folder):
    """Optional check of real generated DDS headers and every full mip payload."""
    manifest = json.loads((folder / "source_tiles.json").read_text())
    assert manifest["atlasPixelsRead"] is False
    assert len(manifest["aliases"]) == 18
    size = manifest["tileSize"]
    for entry in manifest["aliases"].values():
        for channel in "DNSE":
            payload = (folder / entry[channel]).read_bytes()
            assert payload[:4] == b"DDS "
            height, width = struct.unpack_from("<II", payload, 12)
            mips = struct.unpack_from("<I", payload, 28)[0]
            assert (width, height, mips) == (size, size, size.bit_length())
            dimensions = [max(1, size >> i) for i in range(mips)]
            expected = sum(n*n*3 if channel == "N" else max(1, (n+3)//4)**2*8 for n in dimensions)
            assert len(payload) == 128 + expected, (entry[channel], len(payload), expected)
            assert payload[84:88] == (b"\x00"*4 if channel == "N" else b"DXT1")
    assert manifest.get("sourceGenerationPixels", size) == size
    print(f"PASS: 18 complete {size} D/N/S/E tile sets, valid DDS formats and full mip payloads")


if __name__ == "__main__":
    import sys
    if len(sys.argv) == 3 and sys.argv[1] == "--export":
        verify_export(Path(sys.argv[2]))
    else:
        unittest.main()
