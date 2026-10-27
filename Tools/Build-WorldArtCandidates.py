"""Build palette-preserving world candidates without replacing shipping art."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-build",type=Path,required=True)
    parser.add_argument("--toolbox",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--moon-bundle",type=Path,required=True)
    parser.add_argument("--jobs",type=int,choices=(1,2),default=2)
    parser.add_argument("--worlds",nargs="+",default=["mars","venus","io","europa","titan","ganymede","achilles","elysium"])
    args = parser.parse_args()
    if args.output.exists(): raise ValueError("Use a fresh output directory; earlier candidates are preserved")
    args.output.mkdir(parents=True)
    shutil.copytree(args.moon_bundle,args.output/"MoonHd1024")
    def build(world):
        if world not in ("mars","venus","io","europa","titan","ganymede","achilles","elysium"):
            raise ValueError("Unknown world")
        command = [sys.executable,str(ROOT/"Tools/Build-HdTerrainBundle.py"),"--world",world,
                   "--source-build",str(args.source_build),"--toolbox",str(args.toolbox),
                   "--art-direction",str(ROOT/"Tools/TerrainHD/world_surface_art.json"),
                   "--sources",str(args.output/f"{world.title()}Sources"),
                   "--output",str(args.output/f"{world.title()}Hd1024")]
        subprocess.run(command,check=True)
        return world
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        worlds = list(pool.map(build,args.worlds))
    (args.output/"world_candidates.json").write_text(json.dumps({"worlds":["moon"]+worlds,"shippingPromoted":False},indent=2)+"\n")


if __name__ == "__main__":main()
