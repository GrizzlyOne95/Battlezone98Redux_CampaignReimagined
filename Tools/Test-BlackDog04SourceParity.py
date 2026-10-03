"""Source coverage checks; run from repository root with Python 3."""
from pathlib import Path
import hashlib
import re

root = Path(__file__).resolve().parents[1]
source = (root / "References/BlackDog04Source/BlackDog04Mission.cpp").read_text()
port = (root / "Scripts/bd04.lua").read_text()
native_bytes = source.replace("\n", "\r\n").encode()
blob = b"blob " + str(len(native_bytes)).encode() + b"\0" + native_bytes
assert hashlib.sha1(blob).hexdigest() == "d3d0ee442c4140050186402965d851e19a5ea7a1", "Archived source changed"
execute = source.split("void BlackDog04Mission::Execute()", 1)[1]

# Compare every asset referenced by native execution, including audio/objectives
# that can be missed when inspecting only the main success path.
assets = set(re.findall(r'"([^"\n]+\.(?:wav|otf|des))"', execute))
assert len(assets) == 15, assets
for asset in assets:
    assert f'"{asset}"' in port, f"Missing mission asset: {asset}"

odfs = set(re.findall(r'(?:BuildObject(?:AtPortal)?|IsInfo)\("([^"\n]+)"', execute))
for odf in odfs:
    assert f'"{odf}"' in port, f"Missing ODF/info test: {odf}"

# Source path strings must remain present, allowing exactly the two numbered
# families assembled by the port. No path geometry is simulated by this audit.
paths = set(re.findall(r'"([^"\n]+)"', execute)) - assets - odfs
paths -= {"Scavenger", "Drop Zone"}
paths = {p for p in paths if not p.startswith(("Failed to", "bomber not"))}
for path in paths:
    if re.fullmatch(r"return_[1-4]", path):
        assert '"return_" .. (i + 1)' in port
    else:
        assert f'"{path}"' in port, f"Missing mission path: {path}"

handles = set(re.findall(r'GetHandle\("([^"\n]+)"', source))
for label in handles:
    if re.fullmatch(r"turret_[1-9]", label):
        assert 'for i = 0, 8 do M.turret[i] = GetHandle("turret_" .. (i + 1)) end' in port
    else:
        assert f'GetHandle("{label}")' in port, f"Missing setup label: {label}"

disabled = re.findall(r"^\s*//\s*((?:doAttack|SetUserTarget).*;)", execute, re.M)
assert disabled == ["doAttack = FALSE;", "SetUserTarget(navBeacon);", "SetUserTarget(navBeacon);"]
for line in set(disabled):
    assert port.count("--" + line) == disabled.count(line), f"Lost disabled code: {line}"

# Keep source members including unused fields and zero-based array sizes.
for name in ("silo", "fightersSpawned", "cameraReady", "cameraComplete",
             "returnAttack", "portalUnitTime", "portalUnit", "turret",
             "lastUser", "sound4Time", "portalSoundTime"):
    assert re.search(r"\b" + name + r"\b", port), f"Lost source state: {name}"
assert 'IsInsideArea("base_limit", M.user)' in port
assert 'PortalOut(M.portal)' in port and 'DeactivatePortal(M.portal)' in port
assert 'BuildObjectAtPortal("cvfigh", 2, M.portal)' in port
assert 'IsIn(' not in port, "Area membership must not call portal IsIn"
assert 'SucceedMission(GetTime() + 0.1, "bd04win.des")' in port
print(f"BlackDog04 source coverage passed: {len(assets)} mission assets, "
      f"{len(odfs)} ODF/info names, {len(handles)} map labels, 3 disabled lines")
