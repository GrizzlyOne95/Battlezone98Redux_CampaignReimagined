"""Every repo file a shipped material, program or shader needs must ship too.

Ogre resolves `source`, `texture` and `#include` names by bare file name at
runtime (as are material `import ... from` files). A file that is tracked here but missing from Shipping/shipping.lock.json
works in a dev deploy of a working tree only by luck and is silently left out of
Workshop staging (CR_cockpit_damage-sm4.hlsl did exactly that). This walks every
shipped .program, .material and .hlsl and fails on any name that matches a
tracked repository file which the lock does not ship. Names no tracked file has
(stock engine assets, OpenShim payload) are not ours to resolve and are skipped.

Usage, from the repository root:   python Tools/Test-LockedReferences.py
"""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Never shipped; a same-named fixture there must not count as "the repo has it".
NON_SHIPPING = ("tools/", "docs/", ".github/", "local/", "shipping/")
REFERENCE = re.compile(
    r'^\s*(?:source|texture|anim_texture)\s+"?([^\s"]+\.[A-Za-z0-9]+)"?'
    r'|^\s*cubic_texture\s+([^\r\n]+)'            # one combined file or six faces
    r'|^\s*#\s*include\s+"([^"]+)"'
    r'|^\s*import\s+\S+\s+from\s+"([^"]+)"',
    re.MULTILINE,
)
FILE_NAME = re.compile(r'[^\s"]+\.[A-Za-z0-9]+')
BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
SCRIPT_EXT = (".program", ".material", ".hlsl", ".glsl")


def main():
    lock = json.loads((ROOT / "Shipping" / "shipping.lock.json").read_text(encoding="utf-8"))["files"]
    shipped = {pathlib.PureWindowsPath(f["runtime"]).name.lower() for f in lock}

    tracked = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    repo_names = {}
    for path in tracked.decode("utf-8").split("\0"):
        if path and not path.lower().startswith(NON_SHIPPING):
            repo_names.setdefault(pathlib.PurePosixPath(path).name.lower(), path)

    problems, scanned = [], 0
    for entry in lock:
        source = entry["source"].replace("\\", "/")
        if not source.lower().endswith(SCRIPT_EXT):
            continue
        path = ROOT / source
        if not path.is_file():
            continue
        scanned += 1
        text = path.read_text(encoding="utf-8", errors="replace")
        # blank block comments but keep their newlines so line numbers hold
        text = BLOCK_COMMENT.sub(lambda c: "\n" * c.group(0).count("\n"), text)
        for m in REFERENCE.finditer(text):
            names = FILE_NAME.findall(m.group(2)) if m.group(2) else [m.group(1) or m.group(3) or m.group(4)]
            for ref in names:
                name = pathlib.PurePosixPath(ref.replace("\\", "/")).name.lower()
                if name in repo_names and name not in shipped:
                    line = text.count("\n", 0, m.start()) + 1
                    problems.append(f"{source}:{line} needs {repo_names[name]}, which is tracked but not in the shipping lock")

    print(f"scanned {scanned} shipped script(s) against {len(shipped)} locked file(s)")
    if problems:
        for p in sorted(set(problems)):
            print("UNSHIPPED: " + p)
        print("Fix: Manage-CampaignFiles.ps1 -bless, then review the lock diff.")
        return 1
    print("every repo file a shipped script references is in the shipping lock")
    return 0


if __name__ == "__main__":
    sys.exit(main())
