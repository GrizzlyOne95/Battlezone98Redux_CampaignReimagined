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
assert mission_sections == [f"MISSION{i}" for i in range(1, 18)]
campaign_maps = [mod_parser[section]["missionBZN"].strip('"') for section in mission_sections]
assert campaign_maps == ["misn2bcr.bzn", "misn03cr.bzn", "misn04cr.bzn", "misn05cr.bzn", "misn06cr.bzn", "misn07cr.bzn", "misn08cr.bzn", "misn09cr.bzn", "misn10cr.bzn", "misn11cr.bzn", "misn12cr.bzn", "misn13cr.bzn", "misn14cr.bzn", "misn15.bzn", "misn16.bzn", "misn17cr.bzn", "misn18cr.bzn"]
for section, filename in zip(mission_sections, campaign_maps):
    assert mod_parser[section]["missionName"].strip('"')
    assert mod_parser[section]["planet"].strip('"') in {"moon", "mars", "venus", "io", "europa", "titan"}
    path = ROOT / "Missions" / filename
    assert path.is_file(), f"campaign must use a CR map: {filename}"
    mission_class = "MultSTMission"
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
template = (ROOT / "Missions" / "misn2bcr.bzn").read_text(encoding="utf-8")
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
# The co-op map gives the second turret a unique replication label. Setup
# retains its original offline map, which never uses that label for transport.
assert base.count("label = abtowe2_turret\n") == 1
base = base.replace("label = abtowe2_turret\n", "label = abtowe0_turret\n", 1)
assert bzn == base.replace("msn_filename = misn2bcr.bzn", "msn_filename = crsetup.bzn", 1).replace("TerrainName = misn02b", "TerrainName = crsetup", 1)
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

lock = json.loads(lock_path.read_text(encoding="utf-8-sig"))
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

# Soviet (CCA) campaign listing: a second campaign ini beside crcampgn.ini. The stem stays within
# the 16-character menu resource limit and the mission planets drive the weather director.
cca_ini_path = ROOT / "Config" / "crcca.ini"
cca_des_path = ROOT / "crcca.des"
cca_parser = configparser.ConfigParser()
cca_parser.optionxform = str
cca_parser.read(cca_ini_path, encoding="utf-8")
assert len(cca_ini_path.stem) <= 16 and len(cca_des_path.stem) <= 16
assert cca_parser["DESCRIPTION"]["missionName"] == '"CR Soviet"'
assert cca_parser["WORKSHOP"]["mapType"] == '"campaign"'
assert [s for s in cca_parser.sections() if s.startswith("MISSION")] == [f"MISSION{i}" for i in range(1, 9)]
cca_planets = ["venus", "venus", "io", "io", "titan", "titan", "titan", "titan"]
cca_maps = []
for index, planet in enumerate(cca_planets, start=1):
    section = cca_parser[f"MISSION{index}"]
    filename = section["missionBZN"].strip('"')
    assert filename == f"misns{index}cr.bzn"
    assert section["missionName"].strip('"')
    assert section["planet"].strip('"') == planet
    cca_maps.append(filename)
    stem = f"misns{index}cr"
    bzn_text = (ROOT / "Missions" / filename).read_text(encoding="utf-8")
    assert "name = MultSTMission\n" in bzn_text
    assert f"msn_filename = {filename}\n" in bzn_text
    # Terrain keeps the stock stem (misnsN), named by the BZN.
    assert f"TerrainName = misns{index}\n" in bzn_text
    for extension in ("trn", "hg2", "mat", "lgt"):
        assert (ROOT / "Missions" / f"misns{index}.{extension}").is_file(), f"misns{index} terrain {extension}"
    assert (ROOT / "Missions" / f"{stem}.vxt").read_text(encoding="ascii").strip()
    assert (ROOT / "Assets" / "Graphics" / f"{stem}.bmp").read_bytes()[:2] == b"BM"
    mp = configparser.ConfigParser()
    mp.optionxform = str
    mp.read(ROOT / "Config" / f"{stem}.ini", encoding="utf-8")
    assert mp["WORKSHOP"]["mapType"] == '"multiplayer"'
    assert (mp["MULTIPLAYER"]["minPlayers"], mp["MULTIPLAYER"]["maxPlayers"], mp["MULTIPLAYER"]["gameType"]) == ('"2"', '"4"', '"S"')
    blurb = (ROOT / f"{stem}.mpdes").read_bytes()
    assert len(blurb) <= 300 and b"\r\n" in blurb, f"{stem}.mpdes must be <= 300 bytes with CRLF"
    site_prefix = {"venus": "CRVenusSites", "io": "CRIoSites", "titan": "CRTitanSites"}[cca_planets[index - 1]]
    assert (ROOT / "Scripts" / f"{site_prefix}S{index}.lua").is_file(), f"weather sites for misns{index}"
assert_fits_menu_box(cca_des_path)
assert (ROOT / "Assets" / "Graphics" / "crcca.bmp").read_bytes()[:2] == b"BM"

# Once the CCA co-op scripts exist, the shipped lock and the Workshop required-files list must
# carry the listing and every map and script (a stale lock fails Workshop staging).
if all((ROOT / "Scripts" / f"misns{i}cr.lua").is_file() for i in range(1, 9)):
    for filename in cca_maps:
        assert entries.get("Missions\\" + filename) == filename, f"lock missing {filename}"
        lua_name = str(Path(filename).with_suffix(".lua"))
        assert entries.get("Scripts\\" + lua_name) == lua_name, f"lock missing {lua_name}"
    assert entries.get(r"Config\crcca.ini") == "crcca.ini"
    assert entries.get("crcca.des") == "crcca.des"
    assert entries.get(r"Assets\Graphics\crcca.bmp") == "crcca.bmp"
    for runtime in ("crcca.ini", "crcca.des", "crcca.bmp"):
        assert f'"{runtime}"' in manager, f"Workshop required-files list missing {runtime!r}"

# Black Dog (Red Odyssey) campaign listing: the third campaign ini. Terrain keeps the bdmisnNN stem
# named by the BZN. Ganymede weather sites are authored per mission; Elysium weather is separate.
bd_ini_path = ROOT / "Config" / "crbd.ini"
bd_des_path = ROOT / "crbd.des"
bd_parser = configparser.ConfigParser()
bd_parser.optionxform = str
bd_parser.read(bd_ini_path, encoding="utf-8")
assert len(bd_ini_path.stem) <= 16 and len(bd_des_path.stem) <= 16
assert bd_parser["DESCRIPTION"]["missionName"] == '"CR Black Dog"'
assert bd_parser["WORKSHOP"]["mapType"] == '"campaign"'
assert [s for s in bd_parser.sections() if s.startswith("MISSION")] == [f"MISSION{i}" for i in range(1, 16)]
bd_maps = []
for index in range(1, 16):
    planet = "elysium" if index in (7, 9, 10, 11) else "ganymede"
    stem = f"bd{index:02d}cr"
    section = bd_parser[f"MISSION{index}"]
    filename = section["missionBZN"].strip('"')
    assert filename == f"{stem}.bzn"
    assert section["missionName"].strip('"')
    assert section["planet"].strip('"') == planet
    bd_maps.append(filename)
    bzn_text = (ROOT / "Missions" / filename).read_text(encoding="utf-8")
    assert "name = MultSTMission\n" in bzn_text
    assert f"msn_filename = {filename}\n" in bzn_text
    assert f"TerrainName = bdmisn{index:02d}\n" in bzn_text
    for extension in ("trn", "hg2", "mat", "lgt"):
        assert (ROOT / "Missions" / f"bdmisn{index:02d}.{extension}").is_file(), f"bdmisn{index:02d} terrain {extension}"
    vehicle_rows = [line.split(None, 3) for line in (ROOT / "Missions" / f"{stem}.vxt").read_text(encoding="ascii").splitlines() if line.strip()]
    assert vehicle_rows and all(len(row) == 4 for row in vehicle_rows), f"{stem}.vxt needs four native menu fields"
    vxt = [row[0] for row in vehicle_rows]
    # 04 starts on foot and 09 in a stolen Chinese APC: both are disguise missions.
    disguised = {4: "bsuser", 9: "cvapc"}
    if index in disguised:
        assert vxt == [disguised[index]], f"{stem}.vxt must start the disguise unit"
    else:
        assert vxt, f"{stem}.vxt must offer a craft"
    assert (ROOT / "Assets" / "Graphics" / f"{stem}.bmp").read_bytes()[:2] == b"BM"
    mp = configparser.ConfigParser()
    mp.optionxform = str
    mp.read(ROOT / "Config" / f"{stem}.ini", encoding="utf-8")
    assert mp["WORKSHOP"]["mapType"] == '"multiplayer"'
    assert (mp["MULTIPLAYER"]["minPlayers"], mp["MULTIPLAYER"]["maxPlayers"], mp["MULTIPLAYER"]["gameType"]) == ('"2"', '"4"', '"S"')
    blurb = (ROOT / f"{stem}.mpdes").read_bytes()
    assert len(blurb) <= 300 and b"\r\n" in blurb, f"{stem}.mpdes must be <= 300 bytes with CRLF"
    if planet == "ganymede" and index != 7:
        assert (ROOT / "Scripts" / f"CRGanymedeSitesBD{index:02d}.lua").is_file(), f"weather sites for {stem}"
assert_fits_menu_box(bd_des_path)
assert (ROOT / "Assets" / "Graphics" / "crbd.bmp").read_bytes()[:2] == b"BM"

# Once the Black Dog co-op scripts exist, the lock and the Workshop list must carry the listing.
if all((ROOT / "Scripts" / f"bd{i:02d}cr.lua").is_file() for i in range(1, 16)):
    for filename in bd_maps:
        assert entries.get("Missions\\" + filename) == filename, f"lock missing {filename}"
        lua_name = str(Path(filename).with_suffix(".lua"))
        assert entries.get("Scripts\\" + lua_name) == lua_name, f"lock missing {lua_name}"
    assert entries.get(r"Config\crbd.ini") == "crbd.ini"
    assert entries.get("crbd.des") == "crbd.des"
    assert entries.get(r"Assets\Graphics\crbd.bmp") == "crbd.bmp"
    for runtime in ("crbd.ini", "crbd.des", "crbd.bmp"):
        assert f'"{runtime}"' in manager, f"Workshop required-files list missing {runtime!r}"

# CRA (Chinese) campaign listing: the fourth campaign ini. Terrain keeps the chmisnNN stem named by the BZN.
# Ganymede weather sites are authored per mission; chmisn05/06 (Elysium) and chmisn07 (Europa) use their own.
ch_ini_path = ROOT / "Config" / "crch.ini"
ch_des_path = ROOT / "crch.des"
ch_parser = configparser.ConfigParser()
ch_parser.optionxform = str
ch_parser.read(ch_ini_path, encoding="utf-8")
assert len(ch_ini_path.stem) <= 16 and len(ch_des_path.stem) <= 16
assert ch_parser["DESCRIPTION"]["missionName"] == '"CR Chinese"'
assert ch_parser["WORKSHOP"]["mapType"] == '"campaign"'
assert [s for s in ch_parser.sections() if s.startswith("MISSION")] == [f"MISSION{i}" for i in range(1, 9)]
ch_planets = {1: "ganymede", 2: "ganymede", 3: "ganymede", 4: "ganymede", 5: "elysium", 6: "elysium", 7: "europa", 8: "ganymede"}
ch_sites = {1: "CRGanymedeSitesCH01", 2: "CRGanymedeSitesCH02", 3: "CRGanymedeSitesCH03", 4: "CRGanymedeSitesCH04",
            5: "CRElysiumSitesCH05", 6: "CRElysiumSitesCH06", 7: "CREuropaSitesCH07", 8: "CRGanymedeSitesCH08"}
ch_maps = []
for index in range(1, 9):
    stem = f"ch{index:02d}cr"
    section = ch_parser[f"MISSION{index}"]
    filename = section["missionBZN"].strip('"')
    assert filename == f"{stem}.bzn"
    assert section["missionName"].strip('"')
    assert section["planet"].strip('"') == ch_planets[index]
    ch_maps.append(filename)
    bzn_text = (ROOT / "Missions" / filename).read_text(encoding="utf-8")
    assert "name = MultSTMission\n" in bzn_text
    assert f"msn_filename = {filename}\n" in bzn_text
    assert f"TerrainName = chmisn{index:02d}\n" in bzn_text
    for extension in ("trn", "hg2", "mat", "lgt"):
        assert (ROOT / "Missions" / f"chmisn{index:02d}.{extension}").is_file(), f"chmisn{index:02d} terrain {extension}"
    vehicle_rows = [line.split(None, 3) for line in (ROOT / "Missions" / f"{stem}.vxt").read_text(encoding="ascii").splitlines() if line.strip()]
    assert vehicle_rows and all(len(row) == 4 for row in vehicle_rows), f"{stem}.vxt needs four native menu fields"
    vxt = [row[0] for row in vehicle_rows]
    # 01 starts on foot and 07 on foot disguised as the enemy: both keep their map pilot.
    pilots = {1: "csusera", 7: "ssuserb"}
    if index in pilots:
        assert vxt == [pilots[index]], f"{stem}.vxt must start the on-foot pilot"
    else:
        assert all(odf.startswith("cv") for odf in vxt), f"{stem}.vxt must list cv* units"
    assert (ROOT / "Assets" / "Graphics" / f"{stem}.bmp").read_bytes()[:2] == b"BM"
    mp = configparser.ConfigParser()
    mp.optionxform = str
    mp.read(ROOT / "Config" / f"{stem}.ini", encoding="utf-8")
    assert mp["WORKSHOP"]["mapType"] == '"multiplayer"'
    assert (mp["MULTIPLAYER"]["minPlayers"], mp["MULTIPLAYER"]["maxPlayers"], mp["MULTIPLAYER"]["gameType"]) == ('"2"', '"4"', '"S"')
    blurb = (ROOT / f"{stem}.mpdes").read_bytes()
    assert len(blurb) <= 300 and b"\r\n" in blurb, f"{stem}.mpdes must be <= 300 bytes with CRLF"
    assert (ROOT / "Scripts" / f"{ch_sites[index]}.lua").is_file(), f"weather sites for {stem}"
assert_fits_menu_box(ch_des_path)
assert (ROOT / "Assets" / "Graphics" / "crch.bmp").read_bytes()[:2] == b"BM"

# Once the CRA co-op scripts exist, the lock and the Workshop list must carry the listing.
if all((ROOT / "Scripts" / f"ch{i:02d}cr.lua").is_file() for i in range(1, 9)):
    for filename in ch_maps:
        assert entries.get("Missions\\" + filename) == filename, f"lock missing {filename}"
        lua_name = str(Path(filename).with_suffix(".lua"))
        assert entries.get("Scripts\\" + lua_name) == lua_name, f"lock missing {lua_name}"
    assert entries.get(r"Config\crch.ini") == "crch.ini"
    assert entries.get("crch.des") == "crch.des"
    assert entries.get(r"Assets\Graphics\crch.bmp") == "crch.bmp"
    for runtime in ("crch.ini", "crch.des", "crch.bmp"):
        assert f'"{runtime}"' in manager, f"Workshop required-files list missing {runtime!r}"

print("Setup mission shell tests passed")
