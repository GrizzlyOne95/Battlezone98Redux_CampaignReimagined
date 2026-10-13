"""Authored map objects that co-op presentation targets (markers, RemoveObject, camera
subjects/targets) travel to guests by BZN label, so every such label must exist in the
shipped BZN and be unique there. Every peer loads the same BZN, so GetHandle(label)
resolves the same object on every client."""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGETS = {
    "misn02b": ["apscrap-1_camerapod", "apbase-1_camerapod"],
    "misn03": ["launch_pad", "solar1", "solar2", "solar3", "solar4", "cam_geyser"],
    "misn04": ["avrecy-1_recycler"],
    "misn05": ["oblema110_i76building"],
    "misn06": ["eggeizr1-1_geyser", "obheph0_i76building", "sblpad0_i76building",
               "avtank13_wingman", "avtank11_wingman", "avtank12_wingman", "avfigh7_wingman",
               "avfigh10_wingman", "svu1", "svu2", "svu3", "svu4", "svfigh568_wingman",
               "svfigh566_wingman"],
    # misn07: the rendezvous nav, the radar array, the patrol fighters that run for the CCA
    # recycler (markers) and the parked turrets the alarm replaces (RemoveObject).
    "misn07": ["cam3", "radar_array", "svpatrol1_1", "svpatrol1_2", "svpatrol3_1", "svpatrol3_2",
               "pturret1", "pturret2"],
    "misn08": ["cam1", "cam2", "cam5", "hbcerb1_i76building"],
    # misn09: the six CCA artillery pieces (recon camera subjects), the Soviet-built CCA
    # muf (alarm trigger), the launch pad and geyser the camera shots frame, and the Venus
    # opening nav.
    "misn09": ["artil1", "artil2", "artil3", "artil4", "artil5", "artil6", "svmuf",
               "cut_off_geyser", "launchpad", "cam1"],
    # misn10: the Io opening navs, relic, both recyclers, the CCA muf (ODF-named) and
    # artillery, and the geysers the script frames or erupts.
    "misn10": ["relic", "cam1", "cam2", "cam3", "svrecycler", "avrecycler", "post1_geyser",
               "post3_geyser", "geyser1", "geyser2", "geyser3", "geyser4", "geyser5", "geyser6",
               "geyser7", "svartil1", "svartil2", "svmuf"],
}
# Labels that are also an authored PATH name in the BZN legitimately occur twice.
PATH_NAMES = {"launch_pad"}
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
        allowed = 2 if label in PATH_NAMES or label in ODF_NAMED else 1
        if label in ODF_NAMED and len(re.findall(rb"(?m)^label = " + re.escape(label.encode()) + rb"\s*$", data)) != 1:
            failures.append(f"{mission}: BZN label {label} is not declared exactly once")
        if n < 1 or n > allowed:
            failures.append(f"{mission}: BZN label {label} occurs {n} times (want {allowed if n else 1})")
        checked += 1
if failures:
    print("\n".join(failures)); sys.exit(1)
print(f"co-op authored target labels are present and unique in their BZNs: {checked} labels")
