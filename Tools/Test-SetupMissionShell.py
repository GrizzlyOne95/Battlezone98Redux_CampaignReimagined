from __future__ import annotations

import configparser
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ini_path = ROOT / "Config" / "crsetup.ini"
des_path = ROOT / "crsetup.des"
bzn_path = ROOT / "Missions" / "crsetup.bzn"
lua_path = ROOT / "Scripts" / "crsetup.lua"
mod_ini_path = ROOT / "Config" / "campaignReimagined.ini"
mod_des_path = ROOT / "campaignReimagined.des"
lock_path = ROOT / "Shipping" / "shipping.lock.json"
manager_path = ROOT / "Manage-CampaignFiles.ps1"

result_des_paths = [
    ROOT / "crsetok.des",
    ROOT / "crsetrr.des",
    ROOT / "crsetfl.des",
]

for path in (ini_path, des_path, bzn_path, lua_path, mod_ini_path, mod_des_path, lock_path, manager_path, *result_des_paths):
    assert path.is_file(), f"missing setup artifact: {path.relative_to(ROOT)}"

parser = configparser.ConfigParser()
parser.optionxform = str
parser.read(ini_path, encoding="utf-8")
setup_name = parser["DESCRIPTION"]["missionName"]
assert setup_name == '"! SETUP / REPAIR - Open Community Patch"'
assert setup_name.startswith('"!'), "setup entry must retain the first-sort ! prefix"
assert parser["WORKSHOP"]["mapType"] == '"instant_action"'

mod_parser = configparser.ConfigParser()
mod_parser.optionxform = str
mod_parser.read(mod_ini_path, encoding="utf-8")
assert mod_parser["DESCRIPTION"]["missionName"] == '"Open Community Patch + Campaign Reimagined"'
assert mod_parser["WORKSHOP"]["mapType"] == '"mod"'

mod_description = mod_des_path.read_text(encoding="utf-8")
assert "! SETUP / REPAIR - Open Community Patch" in mod_description
assert "go to INSTANT ACTION" in mod_description
assert "completely exit Battlezone" in mod_description
assert "logs\\openpatch_setup.log" in mod_description

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
assert 'Installer.Apply(before)' in lua
assert 'Installer.WriteDiagnosticLog(report)' in lua
assert 'Installer.EnsureOnce' not in lua
assert 'StageOpenShimSuiteUpdate' not in lua
assert 'SucceedMission' in lua
assert 'FailMission' in lua
assert '"crsetok.des"' in lua
assert '"crsetrr.des"' in lua
assert '"crsetfl.des"' in lua

description = des_path.read_text(encoding="utf-8")
assert "logs\\openpatch_setup.log" in description
assert "automatically installs or updates OpenShim" in description
assert "never downgrades" in description

lock = json.loads(lock_path.read_text(encoding="utf-8"))
entries = {entry["source"]: entry["runtime"] for entry in lock["files"]}
expected = {
    r"Config\campaignReimagined.ini": "campaignReimagined.ini",
    "campaignReimagined.des": "campaignReimagined.des",
    r"Config\crsetup.ini": "crsetup.ini",
    "crsetup.des": "crsetup.des",
    "crsetok.des": "crsetok.des",
    "crsetrr.des": "crsetrr.des",
    "crsetfl.des": "crsetfl.des",
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
