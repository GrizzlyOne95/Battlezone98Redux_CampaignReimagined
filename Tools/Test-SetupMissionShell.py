from __future__ import annotations

import configparser
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ini_path = ROOT / "Config" / "crsetup.ini"
des_path = ROOT / "crsetup.des"
bzn_path = ROOT / "Missions" / "crsetup.bzn"
lua_path = ROOT / "Scripts" / "crsetup.lua"
lock_path = ROOT / "Shipping" / "shipping.lock.json"
manager_path = ROOT / "Manage-CampaignFiles.ps1"

for path in (ini_path, des_path, bzn_path, lua_path, lock_path, manager_path):
    assert path.is_file(), f"missing setup artifact: {path.relative_to(ROOT)}"

parser = configparser.ConfigParser()
parser.optionxform = str
parser.read(ini_path, encoding="utf-8")
assert parser["DESCRIPTION"]["missionName"] == '"[SETUP] Open Community Patch"'
assert parser["WORKSHOP"]["mapType"] == '"instant_action"'

bzn = bzn_path.read_text(encoding="utf-8")
for required in (
    "msn_filename = crsetup.bzn",
    "missionSave [1] =\nfalse",
    "TerrainName = misn02b",
    "size [1] =\n1",
    "name = LuaMission",
):
    assert required in bzn, f"setup BZN invariant missing: {required!r}"

assert bzn.count("[GameObject]") == 1, "setup BZN must stay a one-object shell"

lua = lua_path.read_text(encoding="utf-8")
assert 'Installer.Inspect()' in lua
assert 'Installer.WriteDiagnosticLog(report)' in lua
assert 'Installer.EnsureOnce' not in lua
assert 'StageOpenShimSuiteUpdate' not in lua
assert 'SucceedMission' not in lua
assert 'FailMission' not in lua

description = des_path.read_text(encoding="utf-8")
assert "logs\\openpatch_setup.log" in description
assert "diagnostic-only" in description.lower()

lock = json.loads(lock_path.read_text(encoding="utf-8"))
entries = {entry["source"]: entry["runtime"] for entry in lock["files"]}
expected = {
    r"Config\crsetup.ini": "crsetup.ini",
    "crsetup.des": "crsetup.des",
    r"Missions\crsetup.bzn": "crsetup.bzn",
    r"Scripts\crsetup.lua": "crsetup.lua",
}
for source, runtime in expected.items():
    assert entries.get(source) == runtime, (
        f"shipping lock missing setup mapping {source!r} -> {runtime!r}"
    )

manager = manager_path.read_text(encoding="utf-8")
for runtime in expected.values():
    assert f'"{runtime}"' in manager, (
        f"Workshop required-files list missing {runtime!r}"
    )

print("Setup mission shell tests passed")
