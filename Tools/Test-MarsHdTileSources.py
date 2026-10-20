"""Small offline checks for the source-tile adapter and native capture binding."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location("mars_tiles", Path(__file__).with_name("Build-MarsHdTileSources.py"))
tiles = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tiles)


class SourceTiles(unittest.TestCase):
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
    print("PASS: 18 complete 1024 D/N/S/E tile sets, valid DDS formats and full mip payloads")


if __name__ == "__main__":
    import sys
    if len(sys.argv) == 3 and sys.argv[1] == "--export":
        verify_export(Path(sys.argv[2]))
    else:
        unittest.main()
