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
assert mod_parser["DESCRIPTION"]["missionName"] == '"Campaign Reimagined"'
assert mod_parser["WORKSHOP"]["mapType"] == '"campaign"'

# Campaign progression must use the shipped LuaMission rewrites, with setup
# remaining independently discoverable in Instant Action. Stock training has
# a Lua port but no CR BZN yet, so it must not masquerade as a playable rewrite.
mission_sections = [section for section in mod_parser.sections() if section.startswith("MISSION")]
assert mission_sections == [f"MISSION{i}" for i in range(1, 5)]
campaign_maps = [mod_parser[section]["missionBZN"].strip('"') for section in mission_sections]
assert campaign_maps == ["misn02b.bzn", "misn03.bzn", "misn04.bzn", "misn05.bzn"]
for section, filename in zip(mission_sections, campaign_maps):
    assert mod_parser[section]["missionName"].strip('"')
    assert mod_parser[section]["planet"].strip('"') in {"moon", "mars"}
    path = ROOT / "Missions" / filename
    assert path.is_file(), f"campaign must use a CR map: {filename}"
    assert "name = LuaMission" in path.read_text(encoding="utf-8")
    assert (ROOT / "Scripts" / Path(filename).with_suffix(".lua")).is_file()

# Redux's custom-campaign menu uses a BMP preview; retain the JPG for Workshop.
thumbnail = ROOT / "Assets" / "Graphics" / "campaignReimagined.bmp"
assert thumbnail.read_bytes()[:2] == b"BM"

mod_description = mod_des_path.read_text(encoding="utf-8")
assert "! SETUP / REPAIR - Open Community Patch" in mod_description
assert "SINGLE PLAYER > INSTANT ACTION" in mod_description
assert "SINGLE PLAYER > CUSTOM CAMPAIGN > Campaign Reimagined" in mod_description
assert "does not need to be activated in Mods" in mod_description
assert "completely exit Battlezone" in mod_description
assert "logs\\openpatch_setup.log" in mod_description

bzn = bzn_path.read_text(encoding="utf-8")
raw_bzn = bzn_path.read_bytes()
assert b"\n" not in raw_bzn.replace(b"\r\n", b""), "native BZN must use CRLF on every line"
for required in (
    "msn_filename = crsetup.bzn",
    "missionSave [1] =\ntrue",
    "TerrainName = crsetup",
    "size [1] =\n39",
    "name = LuaMission",
):
    assert required in bzn, f"setup BZN invariant missing: {required!r}"

# The former one-object hand-written file did not load in-game. Reuse the complete, tested mission map
# serialization while selecting the independent setup script.
template = (ROOT / "Missions" / "misn02b.bzn").read_text(encoding="utf-8")
assert bzn == template.replace("msn_filename = misn02b.bzn", "msn_filename = crsetup.bzn", 1).replace("TerrainName = misn02b", "TerrainName = crsetup", 1)
for extension in ("trn", "hg2", "mat", "lgt"):
    assert (ROOT / "Missions" / ("crsetup." + extension)).is_file(), "setup terrain must be self-contained"

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

gameplay_config = (ROOT / "Scripts" / "PersistentConfig.lua").read_text(encoding="utf-8")
assert "OpenShimInstaller.CheckOnce(ShowFeedback)" in gameplay_config
assert "OpenShimInstaller.Apply(" not in gameplay_config
assert "OpenShimInstaller.EnsureOnce(" not in gameplay_config

description = des_path.read_text(encoding="utf-8")
assert "logs\\openpatch_setup.log" in description
assert "automatically installs or updates OpenShim" in description
assert "never downgrades" in description

lock = json.loads(lock_path.read_text(encoding="utf-8"))
entries = {entry["source"]: entry["runtime"] for entry in lock["files"]}
expected = {
    r"Config\campaignReimagined.ini": "campaignReimagined.ini",
    "campaignReimagined.des": "campaignReimagined.des",
    r"Assets\Graphics\campaignReimagined.bmp": "campaignReimagined.bmp",
    r"Config\crsetup.ini": "crsetup.ini",
    "crsetup.des": "crsetup.des",
    "crsetok.des": "crsetok.des",
    "crsetrr.des": "crsetrr.des",
    "crsetfl.des": "crsetfl.des",
    r"Missions\crsetup.bzn": "crsetup.bzn",
    r"Missions\crsetup.trn": "crsetup.trn",
    r"Missions\crsetup.hg2": "crsetup.hg2",
    r"Missions\crsetup.mat": "crsetup.mat",
    r"Missions\crsetup.lgt": "crsetup.lgt",
    r"Scripts\crsetup.lua": "crsetup.lua",
}
for source, runtime in expected.items():
    assert entries.get(source) == runtime, (
        f"shipping lock missing setup mapping {source!r} -> {runtime!r}"
    )

for filename in campaign_maps:
    assert entries.get("Missions\\" + filename) == filename
    lua_name = str(Path(filename).with_suffix(".lua"))
    assert entries.get("Scripts\\" + lua_name) == lua_name

manager = manager_path.read_text(encoding="utf-8")
for runtime in expected.values():
    assert f'"{runtime}"' in manager, (
        f"Workshop required-files list missing {runtime!r}"
    )

print("Setup mission shell tests passed")
