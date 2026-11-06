"""Require complete native menu rows for the CCA, Black Dog and CRA co-op rosters.

Redux reads ODF, description token, animation token, and the remaining display
name. A two-token ``odf ,`` row can consume the following row as its missing
fields; a single-row pilot pool then has no selectable entry at all.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSIONS = ([f"misns{i}cr" for i in range(1, 9)]
            + [f"bd{i:02d}cr" for i in range(1, 16)]
            + [f"ch{i:02d}cr" for i in range(1, 9)])

for mission in MISSIONS:
    path = ROOT / "Missions" / f"{mission}.vxt"
    data = path.read_bytes()
    assert b"\n" not in data.replace(b"\r\n", b""), f"{path.name}: keep native CRLF lines"
    rows = [line.split(None, 3) for line in data.decode("ascii").splitlines() if line.strip()]
    assert rows, f"{path.name}: empty vehicle pool"
    assert len({row[0] for row in rows}) == len(rows), f"{path.name}: duplicate ODF"
    for row in rows:
        assert len(row) == 4, f"{path.name}: native parser needs four fields: {row!r}"
        assert all(token and token != "," for token in row), f"{path.name}: incomplete menu entry: {row!r}"
        assert len(row[0]) <= 8 and (ROOT / "ODF" / f"{row[0]}.odf").is_file(), f"{path.name}: unknown starting ODF {row[0]}"
    if mission in {"bd04cr", "ch01cr", "ch07cr"}:
        expected = {"bd04cr": "bsuser", "ch01cr": "csusera", "ch07cr": "ssuserb"}[mission]
        assert len(rows) == 1 and rows[0][0] == expected, f"{path.name}: preserve the on-foot mission start"

print(f"Native four-field vehicle lists passed for all {len(MISSIONS)} campaign co-op missions")
