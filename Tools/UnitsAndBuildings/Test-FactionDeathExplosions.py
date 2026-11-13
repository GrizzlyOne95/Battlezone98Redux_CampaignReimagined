"""Check the per-faction death explosion ODFs (xd<fac><stage>) and their craft wiring.
Stdlib only; run from anywhere: python Tools/UnitsAndBuildings/Test-FactionDeathExplosions.py"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
ODF = ROOT / "ODF"
FACS = ("nsdf", "cca", "bdog", "cra")
# stage -> (stock source, allowed extra particles, engine key)
STAGES = {"i": ("xcarxpla", 0, "explosionname"), "s": ("xsecxpla", 0, "xplsecondary"),
          "d": ("xcarxplb", 0, "xpldetonate"), "p": ("xsecxpla", 2, "xplsnipe")}
PREFIX = {"av": "nsdf", "sv": "cca", "bv": "bdog", "cv": "cra"}
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def parse(path):
    sections, cur = {}, None
    for line in path.read_bytes().decode("latin-1").splitlines():
        line = line.split("//")[0].strip()
        m = re.match(r"\[(\w+)\]", line)
        if m:
            cur = sections.setdefault(m.group(1).lower(), {})
        elif cur is not None and "=" in line:
            k, v = line.split("=", 1)
            cur[k.strip().lower()] = v.strip().strip('"')
    return sections


def gameplay(sections):
    return {k: v for k, v in sections["explosionclass"].items() if not k.startswith("particle")}


def total(sections):
    return sum(int(v) for k, v in sections["explosionclass"].items() if re.fullmatch(r"particlecount\d+", k))


for fac in FACS:
    for stage, (stock, extra, _) in STAGES.items():
        name = f"xd{fac}{stage}"
        path = ODF / (name + ".odf")
        check(len(name) <= 8, name + ": name > 8 chars")
        if not path.exists():
            check(False, name + ": missing")
            continue
        sec = parse(path)
        ref = parse(ODF / (stock + ".odf"))
        check(gameplay(sec) == gameplay(ref), f"{name}: gameplay fields differ from {stock}")
        check(total(sec) <= total(ref) + extra, f"{name}: {total(sec)} particles > {total(ref) + extra}")
        ex = sec["explosionclass"]
        n = int(ex["particletypes"])
        lights = 0
        for i in range(1, n + 1):
            cls = ex.get(f"particleclass{i}", "")
            owner, _, section = cls.partition(".")
            check(owner.lower() == name, f"{name}: particleClass{i} references {cls!r}, not its own section")
            check(section.lower() in sec, f"{name}: section {section!r} missing")
            lights += sec.get(section.lower(), {}).get("renderbase") == "draw_light"
        check(lights <= (1 if stage in "id" else 0), f"{name}: {lights} light layers")
        if stage == "p":
            check(lights == 0 and "flash" not in sec and "core" not in sec, name + ": snipe has a fireball")

wired = 0
for path in sorted(ODF.glob("*.odf")):
    fac = PREFIX.get(path.name[:2].lower())
    sec = parse(path) if fac else None
    if not fac or "craftclass" not in sec:
        continue
    wired += 1
    for stage, (_, _, key) in STAGES.items():
        section = "gameobjectclass" if stage == "i" else "craftclass"
        value = sec.get(section, {}).get(key)
        if value is None:
            check(stage == "i" and section not in sec, f"{path.name}: {key} not set")
            continue
        check(value == f"xd{fac}{stage}", f"{path.name}: {key} = {value!r}, expected xd{fac}{stage}")
        check((ODF / (value + ".odf")).exists(), f"{path.name}: {value}.odf missing")
check(wired > 0, "no faction craft found")

print(f"{wired} craft ODFs checked")
for f in failures:
    print("FAIL", f)
sys.exit(1 if failures else 0)
