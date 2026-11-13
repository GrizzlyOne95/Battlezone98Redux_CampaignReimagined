"""Compatibility wrapper: rebuild Missions/misn06cr.bzn via Build-CoopMap.py."""

import runpy
import sys
from pathlib import Path

if __name__ == "__main__":
    sys.argv[1:1] = ["--mission", "misn06"]
    runpy.run_path(str(Path(__file__).with_name("Build-CoopMap.py")), run_name="__main__")
