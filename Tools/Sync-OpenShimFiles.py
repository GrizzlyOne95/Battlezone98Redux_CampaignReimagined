#!/usr/bin/env python3
"""Re-sync the OpenShim-owned files Campaign Reimagined commits and ships.

Copies from an OpenShim checkout (the same sources Manage-CampaignFiles.ps1
-> Update-OpenShimManifest and Sync-SupportWrapper use):

  resources/renderer/enhanced/*  -> openshim/renderer/enhanced/<name>.payload
  resources/ui/custom_widgets/*.png -> BZ_ASSETS_CORE/common/ui/CustomWidgets/
  upload/openshim_wrap.{ps1,bat,sh} -> openshim/support/
  (openshim/support/README.txt comes from Docs/openshim_support_README.txt)

then rewrites the renderer/customWidgets set hashes and assetFiles rows in
Scripts/OpenShimManifest.lua (binary rows are left alone) and records the
source commit in openshim/OPENSHIM_PIN.txt.

Usage: python Tools/Sync-OpenShimFiles.py <path-to-OpenShim-checkout>
"""
import hashlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RENDERER = ROOT / "openshim" / "renderer" / "enhanced"
SUPPORT = ROOT / "openshim" / "support"
WIDGETS = ROOT / "BZ_ASSETS_CORE" / "common" / "ui" / "CustomWidgets"
MANIFEST = ROOT / "Scripts" / "OpenShimManifest.lua"
PIN = ROOT / "openshim" / "OPENSHIM_PIN.txt"
WRAPPERS = ("openshim_wrap.ps1", "openshim_wrap.bat", "openshim_wrap.sh")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def set_hash(rows):
    """Mirror Get-OpenShimAssetSet: sorted '<lower path>|<sha>|<size>\n' lines."""
    text = "".join(f"{p.lower()}|{h}|{s}\n" for p, h, s in sorted(rows, key=lambda r: r[0].lower().encode()))
    return hashlib.sha256(text.encode("ascii")).hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    shim = Path(sys.argv[1]).resolve()
    renderer_src = shim / "resources" / "renderer" / "enhanced"
    widgets_src = shim / "resources" / "ui" / "custom_widgets"
    if not (renderer_src / "resources.version").is_file():
        print(f"not an OpenShim checkout: {shim}", file=sys.stderr)
        return 1
    commit = subprocess.run(["git", "-C", str(shim), "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()

    # Rebuild the renderer set so a file dropped from OpenShim does not linger.
    if RENDERER.exists():
        shutil.rmtree(RENDERER)
    RENDERER.mkdir(parents=True)
    for src in sorted(p for p in renderer_src.iterdir() if p.is_file()):
        shutil.copyfile(src, RENDERER / (src.name + ".payload"))
    SUPPORT.mkdir(parents=True, exist_ok=True)
    for name in WRAPPERS:
        shutil.copyfile(shim / "upload" / name, SUPPORT / name)
    shutil.copyfile(ROOT / "Docs" / "openshim_support_README.txt", SUPPORT / "README.txt")
    WIDGETS.mkdir(parents=True, exist_ok=True)
    widget_names = sorted(p.name for p in widgets_src.glob("*.png"))
    for name in widget_names:
        shutil.copyfile(widgets_src / name, WIDGETS / name)

    renderer_rows = [(p.name[:-len(".payload")], sha(p), p.stat().st_size) for p in RENDERER.iterdir()]
    widget_rows = [(n, sha(WIDGETS / n), (WIDGETS / n).stat().st_size) for n in widget_names]

    lua = MANIFEST.read_bytes().decode("utf-8")
    for key, rows in (("renderer", renderer_rows), ("customWidgets", widget_rows)):
        lua, n = re.subn(r'(\b%s = \{[^}]*?sha256 = ")\w+(", files = )\d+' % key,
                         lambda m: m.group(1) + set_hash(rows) + m.group(2) + str(len(rows)), lua)
        if n != 1:
            print(f"manifest row for {key} not found", file=sys.stderr)
            return 1
    lua = re.sub(r'^ *\{ set = "(?:renderer|customWidgets)".*\n', "", lua, flags=re.M)
    lines = [f'        {{ set = "{s}", path = "{p}", sha256 = "{h}", size = {z} }},\n'
             for s, rows in (("renderer", renderer_rows), ("customWidgets", widget_rows))
             for p, h, z in sorted(rows, key=lambda r: r[0].lower().encode())]
    lua, n = re.subn(r"(    assetFiles = \{\r?\n)", lambda m: m.group(1) + "".join(lines), lua)
    if n != 1:
        print("assetFiles block not found", file=sys.stderr)
        return 1
    MANIFEST.write_bytes(lua.encode("utf-8"))
    PIN.write_text(f"{commit}\n", encoding="ascii")
    print(f"synced {len(renderer_rows)} renderer, {len(widget_rows)} widget, {len(WRAPPERS)} wrapper files from OpenShim {commit}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
