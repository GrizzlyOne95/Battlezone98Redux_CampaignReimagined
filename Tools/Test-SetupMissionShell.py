from __future__ import annotations

import configparser
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ini_path = ROOT / "Config" / "crsetup.ini"
des_path = ROOT / "crsetup.des"
bzn_path = ROOT / "Missions" / "crsetup.bzn"
lua_path = ROOT / "Scripts" / "crsetup.lua"
# Redux truncates menu resource names to 16 characters ("campaignReimagined.des"
# was looked up as "campaignreimagin"), so the campaign ini stem stays short.
mod_ini_path = ROOT / "Config" / "crcampgn.ini"
mod_des_path = ROOT / "crcampgn.des"
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

# Campaign progression must use the shipped Lua-backed rewrites, with setup
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
    mission_class = "MultSTMission" if filename in {"misn02b.bzn", "misn03.bzn", "misn04.bzn"} else "LuaMission"
    assert f"name = {mission_class}\n" in path.read_text(encoding="utf-8")
    assert (ROOT / "Scripts" / Path(filename).with_suffix(".lua")).is_file()

# Redux's custom-campaign menu uses a BMP preview; retain the JPG for Workshop.
for stem in ("crcampgn", "crsetup"):
    thumbnail = ROOT / "Assets" / "Graphics" / (stem + ".bmp")
    assert len(thumbnail.name) <= 16, thumbnail.name
    assert thumbnail.read_bytes()[:2] == b"BM", thumbnail.name

# The menu description boxes show about six wrapped lines; longer text is cut.
def assert_fits_menu_box(path):
    text = path.read_text(encoding="utf-8").strip()
    assert len(text) <= 300 and "\n" not in text, (
        f"{path.name} is {len(text)} chars; the menu box fits about 300")
    return text

mod_description = assert_fits_menu_box(mod_des_path)
assert "! SETUP / REPAIR - Open Community Patch" in mod_description
assert "SINGLE PLAYER > INSTANT ACTION" in mod_description
assert "not need to be activated in Mods" in mod_description
assert "completely exit Battlezone" in mod_description

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
# misn02b now carries MP spawn buoys/team reservations. Setup retains its
# original offline serialization; compare the authored objects after undoing
# only those mission-specific co-op changes.
import re
parts = template.split("[GameObject]")
kept = []
for block in parts[1:]:
    if "label = coop_spawn" in block:
        # The last buoy also contains the mission footer and path tables.
        if "name = MultSTMission\n" in block:
            kept[-1] += block[block.index("name = MultSTMission\n"):]
        continue
    block = re.sub(r"((?:team|perceivedTeam) \[1\] =\n)7\n", r"\g<1>5\n", block)
    if "label = fake_player\n" in block:
        block = re.sub(r"((?:team|perceivedTeam) \[1\] =\n)5\n", r"\g<1>1\n", block)
    kept.append(block)
base = parts[0].replace("seq_count [1] =\n532", "seq_count [1] =\n528", 1).replace("size [1] =\n43", "size [1] =\n39", 1)
base += "".join("[GameObject]" + block for block in kept)
base = base.replace("name = MultSTMission", "name = LuaMission", 1)
base = re.sub(r"(\[AOI\].*?team \[1\] =\n)6\n", r"\g<1>2\n", base, flags=re.S)
assert bzn == base.replace("msn_filename = misn02b.bzn", "msn_filename = crsetup.bzn", 1).replace("TerrainName = misn02b", "TerrainName = crsetup", 1)
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

description = assert_fits_menu_box(des_path)
assert "logs\\openpatch_setup.log" in description
assert "updates OpenShim automatically" in description
assert "never downgrades" in description

lock = json.loads(lock_path.read_text(encoding="utf-8"))
entries = {entry["source"]: entry["runtime"] for entry in lock["files"]}
expected = {
    r"Config\crcampgn.ini": "crcampgn.ini",
    "crcampgn.des": "crcampgn.des",
    r"Assets\Graphics\crcampgn.bmp": "crcampgn.bmp",
    r"Assets\Graphics\crsetup.bmp": "crsetup.bmp",
    r"InstallerPayload\OpenShimAssets.ini.payload": "OpenShimAssets.ini.payload",
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
