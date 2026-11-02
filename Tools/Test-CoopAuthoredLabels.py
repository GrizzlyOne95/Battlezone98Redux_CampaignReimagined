"""Authored map objects that co-op presentation targets (markers, RemoveObject, camera
subjects/targets) travel to guests by BZN label, so every such label must exist in the
shipped BZN and be unique there. Every peer loads the same BZN, so GetHandle(label)
resolves the same object on every client."""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGETS = {
    "misn2bcr": ["apscrap-1_camerapod", "apbase-1_camerapod"],
    "misn03cr": ["launch_pad", "solar1", "solar2", "solar3", "solar4", "cam_geyser"],
    "misn04cr": ["avrecy-1_recycler"],
    "misn05cr": ["oblema110_i76building"],
    "misn06cr": ["eggeizr1-1_geyser", "obheph0_i76building", "sblpad0_i76building", "cr06_rocket",
               "avtank13_wingman", "avtank11_wingman", "avtank12_wingman", "avfigh7_wingman",
               "avfigh10_wingman", "svu1", "svu2", "svu3", "svu4", "svfigh568_wingman",
               "svfigh566_wingman"],
    # misn07: the rendezvous nav, the radar array, the patrol fighters that run for the CCA
    # recycler (markers) and the parked turrets the alarm replaces (RemoveObject).
    "misn07cr": ["cam3", "radar_array", "svpatrol1_1", "svpatrol1_2", "svpatrol3_1", "svpatrol3_2",
               "pturret1", "pturret2"],
    "misn08cr": ["cam1", "cam2", "cam5", "hbcerb1_i76building"],
    # misn09: the six CCA artillery pieces (recon camera subjects), the Soviet-built CCA
    # muf (alarm trigger), the launch pad and geyser the camera shots frame, and the Venus
    # opening nav.
    "misn09cr": ["artil1", "artil2", "artil3", "artil4", "artil5", "artil6", "svmuf",
               "cut_off_geyser", "launchpad", "cam1"],
    # misn10: the Io opening navs, relic, both recyclers, the CCA muf (ODF-named) and
    # artillery, and the geysers the script frames or erupts.
    "misn10cr": ["relic", "cam1", "cam2", "cam3", "svrecycler", "avrecycler", "post1_geyser",
               "post3_geyser", "geyser1", "geyser2", "geyser3", "geyser4", "geyser5", "geyser6",
               "geyser7", "svartil1", "svartil2", "svmuf"],
    # misn11: the three transports, the three waypoint navs, both launch pads (all markers) and the
    # CCA picket/walker/artillery the ambush drives (never presented, but resolved by label).
    "misn11cr": ["avhaul0_tug", "avhaul1_tug", "avhaul2_tug", "apcamr3_camerapod", "apcamr4_camerapod",
               "apcamr5_camerapod", "launch_pad", "launch_pad2", "svturr0_turrettank", "svturr1_turrettank",
               "svturr2_turrettank", "svturr3_turrettank", "second_blockade", "svwalk0_walker",
               "svartl0_howitzer", "svartl0(1)_howitzer"],
    # misn12: the checkpoint buildings (checktower1 = sbhqt1, center = sbhqt2), the CCA muf/silos/
    # comm tower the uplink and cameras frame, the six geysers the key ship and guards spawn at,
    # the Drop Zone nav, the parked/guard units and the patrol fighters the script retargets.
    "misn12cr": ["checktower1", "svguntower2", "svmuf", "svsilo1", "svsilo2", "svsilo3", "svsilo4",
               "center", "svcom_tower", "spawn_geyser", "spawn_geyser1", "spawn_geyser2",
               "choke_geyser", "check2_geyser", "center_geyser", "apcamr20_camerapod",
               "pfighter1", "pfighter2", "ptank1", "ptank2", "turret1", "turret2", "turret3",
               "turret4", "turret5", "turret6", "gtank1", "gtank2",
               "svfigh1_1", "svfigh1_2", "svfigh2_1", "svfigh2_2", "svfigh3_1", "svfigh3_2",
               "svfigh4_1", "svfigh4_2", "artil1", "artil2", "artil3", "artil4"],
    # misn13: the Drop Zone nav (marker), the CCA base objects the win and objectives watch (factory, hangar,
    # four silos), the east tower the waves aim at, the spawn/key geysers the restored waves use, the five
    # relabelled wingmen (artillery escorts and the factory reserve) and the artillery.
    "misn13cr": ["apcamr20_camerapod", "avrecycle", "svmuf", "svguntower1", "svguntower2", "svsilo1", "svsilo2",
               "svsilo3", "svsilo4", "spawn_geyser1", "spawn_geyser2", "artil1", "artil2", "artil3", "artil4",
               "artil_escort1", "artil_escort2", "artil_escort3", "cca_reserve1", "cca_reserve2"],
    # misn14: the four nav pods (named markers), the Texas (camera target, rally, win), the scientists'
    # barracks (Rescue CCA marker, 1406 camera target), the CCA recycler/factory whose fall forces the
    # surrender, and the towers and power plants that surrender to team 7.
    "misn14cr": ["apcamr0_camerapod", "apcamr1_camerapod", "apcamr2_camerapod", "apcamr3_camerapod",
               "avrecy-1_recycler", "sbbarr0_i76building", "svrecy-1_recycler", "svmuf0_factory",
               "sbtowe0_turret", "sbtowe1_turret", "sbtowe55_turret", "sbtowe56_turret",
               "sblpow1_powerplant", "sblpow55_powerplant"],
    # misn18: the opening camera targets (removed afterwards), the Fury transport and its four thrusters
    # (markers, camera target), the Home Base nav and the Texas (rally, win/loss).
    "misn18cr": ["scrapcam", "scrapcam2", "hbtran0038_i76building", "hbtrn20049_i76building",
               "hbtrn20050_i76building", "hbtrn20051_i76building", "hbtrn20052_i76building",
               "basenav", "avrecy2_recycler"],
    # bdmisn04: the portal every peer opens and closes by label (BD4Portal) and the scav to commandeer
    # (the HUD target every human gets by label, BD4Target).
    "bdmisn04cr": ["portal", "scav_3"],
    # bdmisn05/06/08/09/12: the portal every peer animates through a presentation op.
    "bdmisn05cr": ["portal"],
    "bdmisn06cr": ["portal"],
    "bdmisn08cr": ["portal"],
    "bdmisn09cr": ["portal"],
    "bdmisn12cr": ["portal"],
}
# Labels that are also an authored PATH name in the BZN legitimately occur twice (a (mission, label)
# pair allows it on one map only).
PATH_NAMES = {"launch_pad", ("bdmisn05cr", "portal")}
# A label that is also its own ODF class name appears once as PrjID and once as the label;
# exactly one of the two may be a `label =` line.
ODF_NAMED = {"svmuf"}

failures = []
checked = 0
for mission, labels in TARGETS.items():
    data = (ROOT / "Missions" / f"{mission}.bzn").read_bytes()
    script = (ROOT / "Scripts" / f"{mission}.lua").read_text(encoding="utf-8", errors="replace")
    for label in labels:
        if f'"{label}"' not in script:
            failures.append(f"{mission}: script no longer references {label}")
        pattern = rb"(?<![A-Za-z0-9_\-])" + re.escape(label.encode()) + rb"(?![A-Za-z0-9_\-])"
        n = len(re.findall(pattern, data))
        allowed = 2 if label in PATH_NAMES or (mission, label) in PATH_NAMES or label in ODF_NAMED else 1
        if label in ODF_NAMED and len(re.findall(rb"(?m)^label = " + re.escape(label.encode()) + rb"\s*$", data)) != 1:
            failures.append(f"{mission}: BZN label {label} is not declared exactly once")
        if n < 1 or n > allowed:
            failures.append(f"{mission}: BZN label {label} occurs {n} times (want {allowed if n else 1})")
        checked += 1
if failures:
    print("\n".join(failures)); sys.exit(1)
print(f"co-op authored target labels are present and unique in their BZNs: {checked} labels")

# Campaign BZN consistency, CCA (Soviet) misns1..misns8 and CRA (Chinese) chmisn01..chmisn07. The faithful
# scripts look objects up by label (GetHandle), including inside the disabled "cut" blocks that are to be
# restored, so every looked-up label must be declared exactly once on a map object (path labels do not count)
# in the co-op BZN. The CCA lookups below are absent from the stock 1.5 BZN (cut content, nothing to find):
CCA_CUT_MISSING = {"misns1": {"geyser2"}, "misns2": {"navmine"}}
# GetHandle("prefix" .. n) loops in the CRA scripts: script stem -> prefix -> (first, last) index looked up.
CH_PREFIXES = {
    "ch03": {"howitzer_": (1, 6)},
    "ch04": {"empty_": (1, 25), "turret_": (1, 4)},
    "ch06": {"psu_": (1, 4)},
    "ch08": {"magpull_": (1, 6), "west_mag_": (1, 4), "east_mag_": (1, 4), "sniper_": (1, 26)},
}
# CRA lookups absent from the stock chmisn BZN (cut content or runtime-spawned), with the reason.
CH_CUT_MISSING = {}


def check_campaign(title, missions, script_for, cut_missing, prefixes):
    failures = []
    checked = 0
    for mission in missions:
        text = (ROOT / "Missions" / f"{mission}cr.bzn").read_text(encoding="latin-1").replace("\r\n", "\n")
        header, *blocks = text.split("[GameObject]\n")
        blocks[-1] = re.split(r"(?m)^(?=name = MultSTMission$)", blocks[-1], maxsplit=1)[0]
        objects = "\n".join(blocks)
        if f"msn_filename = {mission}cr.bzn\n" not in header:
            failures.append(f"{mission}: msn_filename is not {mission}cr.bzn")
        if "name = MultSTMission\n" not in text:
            failures.append(f"{mission}: mission class is not MultSTMission")
        # Guest teams 2-4 hold only the four start buoys; the enemy is team 5.
        for team in "1234":
            if len(re.findall(rf"(?m)^label = coop_spawn{team}$", objects)) != 1:
                failures.append(f"{mission}: team {team} start buoy missing or duplicated")
        for block in blocks:
            if "label = coop_spawn" in block:
                continue
            if re.search(r"(?m)^team \[1\] =\n[234]$", block):
                found = re.search(r"(?m)^label = (.*)$", block)
                failures.append(f"{mission}: authored object left on a guest team: {found.group(1) if found else '?'}")
        script_stem = script_for(mission)
        script = (ROOT / "Scripts" / f"{script_stem}.lua").read_text(encoding="utf-8", errors="replace")
        labels = set()
        for literal, concat in re.findall(r'GetHandle\s*\(\s*"([^"]+)"(\s*\.\.)?', script):
            if concat:
                first, last = prefixes[script_stem][literal]  # KeyError: a new dynamic lookup to describe
                labels.update(f"{literal}{i}" for i in range(first, last + 1))
            else:
                labels.add(literal)
        for label in sorted(labels):
            count = len(re.findall(rf"(?m)^label = {re.escape(label)}$", objects))
            checked += 1
            if label in cut_missing.get(mission, ()):
                if count != 0:
                    failures.append(f"{mission}: {label} is now in the BZN; drop it from the cut-missing list")
            elif count != 1:
                failures.append(f"{mission}: GetHandle label {label} occurs {count} times on map objects")
    if failures:
        print("\n".join(failures)); sys.exit(1)
    print(f"{title} co-op BZN labels, teams and spawn buoys are consistent: {checked} labels in {len(missions)} maps")


check_campaign("CCA", [f"misns{n}" for n in range(1, 9)], lambda m: m, CCA_CUT_MISSING, {})
check_campaign("CRA", [f"chmisn{n:02d}" for n in range(1, 9)], lambda m: "ch" + m[6:], CH_CUT_MISSING, CH_PREFIXES)
