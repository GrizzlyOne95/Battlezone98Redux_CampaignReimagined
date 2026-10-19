"""tex/*.png -> out/*.dds (DXT1, full Lanczos mip chain) via the modding toolbox's bcpack."""
import glob, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.expanduser("~/Documents/GIT/Battlezone98_Modding_Toolbox"))
from bztoolbox.modules.textures import bcpack

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for p in sorted(glob.glob(os.path.join(ROOT, "tex", "*.png"))):
    a = np.asarray(Image.open(p).convert("RGBA"))
    h, w = a.shape[:2]
    chain, _ = bcpack.build_chain([a], w, h)
    out = os.path.join(ROOT, "out", os.path.basename(p)[:-4] + ".dds")
    bcpack.write_dds(out, w, h, [bcpack.encode_level(lv, "DXT1") for lv in chain], "DXT1")
    print(os.path.basename(out), w, len(chain))
