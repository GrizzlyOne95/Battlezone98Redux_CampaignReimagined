"""Shared locations for the dropship tooling. Generated output goes to <repo>/Local/dropships (git-ignored).

Override with environment variables:
  BZ_DROPSHIPS_LOCAL   output root (default <repo>/Local/dropships; holds out/ and tex/)
  BZ_STOCK_MODELS      folder of stock Redux .mesh files (only used for the cargo-fit proxies in the .blend)
  BZ_TOOLBOX           Battlezone98_Modding_Toolbox checkout (DDS encoder for texgen_avstock.py)
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
LOCAL = os.environ.get("BZ_DROPSHIPS_LOCAL", os.path.join(REPO, "Local", "dropships"))
OUT = os.path.join(LOCAL, "out")
TEX = os.path.join(LOCAL, "tex")
LAYOUT = os.path.join(HERE, "trim_layout.json")   # tracked: strip/cell layout shared by texgen and shipkit
STOCK = os.environ.get("BZ_STOCK_MODELS",
                       r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\BZ_ASSETS\common\models")
TOOLBOX = os.environ.get("BZ_TOOLBOX", os.path.expanduser("~/Documents/GIT/Battlezone98_Modding_Toolbox"))
