"""Build all nine planet packs with the shared Toolbox; preserve original atlases."""
import argparse
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-build", type=Path, required=True)
    parser.add_argument("--toolbox", type=Path)
    parser.add_argument("--install-source-assets", action="store_true")
    parser.add_argument("--worlds", nargs="+", default=["moon", "mars", "venus", "io", "europa", "titan", "achilles", "ganymede", "elysium"])
    args = parser.parse_args()
    for world in args.worlds:
        command = [sys.executable, str(Path(__file__).with_name("Build-HdTerrainBundle.py")),
                   "--world", world, "--source-build", str(args.source_build)]
        if args.toolbox:
            command += ["--toolbox", str(args.toolbox)]
        if args.install_source_assets:
            command.append("--install-source-assets")
        subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
