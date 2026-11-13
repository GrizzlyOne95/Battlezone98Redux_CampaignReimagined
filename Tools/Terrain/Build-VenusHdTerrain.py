"""Build CR's Venus pack with the shared terrain bundle workflow."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("hd_terrain_bundle", Path(__file__).with_name("Build-HdTerrainBundle.py"))
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)

if __name__ == "__main__":
    bundle.main("venus")
