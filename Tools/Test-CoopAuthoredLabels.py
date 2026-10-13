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
}
# Labels that are also an authored PATH name in the BZN legitimately occur twice.
PATH_NAMES = {"launch_pad"}

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
        allowed = 2 if label in PATH_NAMES else 1
        if n < 1 or n > allowed:
            failures.append(f"{mission}: BZN label {label} occurs {n} times (want {allowed if n else 1})")
        checked += 1
if failures:
    print("\n".join(failures)); sys.exit(1)
print(f"co-op authored target labels are present and unique in their BZNs: {checked} labels")
