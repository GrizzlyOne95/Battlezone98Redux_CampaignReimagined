"""Check the emit-based weapon trails (draw_twirl_trail sections in ordnance ODFs).
Cost, against the frozen pre-change values in Tools/Weapons/TrailDensity.baseline.json (so CI needs no stock files):
- standing sprites (emitLife / emitDelay) per section <= 150 and per ordnance <= 200;
- per ordnance standing <= max(1.5 x baseline, 60);
- overdraw proxy (sum of standing * ((startRadius + finishRadius) / 2)^2) <= 1.25 x baseline;
- per section emitLife and both radii >= 0.6 x baseline, emitDelay >= 0.004.
Smoothness (shotSpeed * emitDelay / startRadius, goal <= 0.6) is printed as info and never fails.
draw_bolt, draw_tracer and plain draw_trail ribbons (segmentTime, no emitter) are ignored.
Stdlib only: python Tools/Weapons/Test-TrailDensity.py"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
ODF = ROOT / "ODF"
SPACING_GOAL = 0.6
MAX_SECTION = 150
MAX_ORDNANCE = 200
GROWTH_STANDING = 1.5
STANDING_FLOOR = 60
MAX_OVERDRAW_GROWTH = 1.25
KEEP = 0.6
MIN_DELAY = 0.004
EPS = 1e-6
ROUND = 0.0011  # ODF values are written with 3 decimals


def parse_trails(text):
    """Return (shotSpeed, [section dict]) for an ordnance ODF; sections are the draw_twirl_trail emitters."""
    secs, cur = {}, None
    order = []
    for raw in text.splitlines():
        line = re.sub(r"//.*", "", raw).strip()
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            cur = m.group(1).strip().lower()
            secs[cur] = {}
            order.append(cur)
            continue
        m = re.match(r"^(\w+)\s*=\s*(.+)$", line)
        if m and cur is not None:
            secs[cur][m.group(1).lower()] = m.group(2).strip().strip('"')
    if "ordnanceclass" not in secs:
        return None, []
    speed = float(secs["ordnanceclass"].get("shotspeed", "0"))
    out = []
    for name in order:
        s = secs[name]
        if s.get("renderbase", "").lower() == "draw_twirl_trail" and "emitdelay" in s:
            out.append({"name": name, "r0": float(s["startradius"]), "r1": float(s["finishradius"]),
                        "delay": float(s["emitdelay"]), "life": float(s["emitlife"])})
    return speed, out


def measure(speed, secs):
    """Return (total standing sprites, overdraw proxy)."""
    standing = sum(s["life"] / s["delay"] for s in secs)
    overdraw = sum(s["life"] / s["delay"] * ((s["r0"] + s["r1"]) / 2) ** 2 for s in secs)
    return standing, overdraw


def main():
    base = json.loads((ROOT / "Tools" / "Weapons" / "TrailDensity.baseline.json").read_text(encoding="utf-8"))["ordnance"]
    failures = []
    seen = 0
    for path in sorted(ODF.glob("*.odf")):
        speed, secs = parse_trails(path.read_text(encoding="utf-8", errors="replace"))
        if not secs:
            continue
        seen += 1
        stem = path.stem
        b = base.get(stem)
        if b is None:
            failures.append(f"{stem}: no entry in Tools/Weapons/TrailDensity.baseline.json")
            continue
        for s in secs:
            n = f"{stem}.{s['name']}"
            standing = s["life"] / s["delay"]
            if standing > MAX_SECTION + EPS:
                failures.append(f"{n}: {standing:.1f} standing sprites > {MAX_SECTION}")
            if s["delay"] < MIN_DELAY - EPS:
                failures.append(f"{n}: emitDelay {s['delay']} < {MIN_DELAY}")
            bs = b["sections"].get(s["name"])
            if bs is None:
                failures.append(f"{n}: section not in baseline")
                continue
            for key, bkey in (("life", "life"), ("r0", "r0"), ("r1", "r1")):
                if s[key] < KEEP * bs[bkey] - ROUND:
                    failures.append(f"{n}: {key} {s[key]} < {KEEP} x baseline {bs[bkey]}")
        total, overdraw = measure(speed, secs)
        cap = min(MAX_ORDNANCE, max(GROWTH_STANDING * b["standing"], STANDING_FLOOR))
        if total > cap + EPS:
            failures.append(f"{stem}: {total:.1f} standing sprites > {cap:.1f}")
        if overdraw > MAX_OVERDRAW_GROWTH * b["overdraw"] + EPS:
            failures.append(f"{stem}: overdraw {overdraw:.2f} > {MAX_OVERDRAW_GROWTH} x baseline {b['overdraw']:.2f}")
        ratios = ", ".join(f"{s['name']} {speed * s['delay'] / s['r0']:.2f}" for s in secs)
        print(f"info {stem}: standing {b['standing']:.0f} -> {total:.0f}, spacing/startRadius {ratios} (goal <= {SPACING_GOAL})")
    for stem in base:
        if not (ODF / f"{stem}.odf").exists():
            failures.append(f"baseline ordnance {stem} has no ODF")
    if failures:
        for f in failures:
            print("FAIL " + f)
        return 1
    print(f"trail density: ok ({seen} ordnance)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
