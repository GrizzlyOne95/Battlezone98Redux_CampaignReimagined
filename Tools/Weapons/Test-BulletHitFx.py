"""Check the bullet hit effect ODFs (xbulgnd, xbulbld, xbulcar).
Gameplay fields must match the old/stock files, particle budgets hold, and each file
references only its own sections. Stdlib only: python Tools/Weapons/Test-BulletHitFx.py"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
# name -> (max particles, max section lifetime)
FILES = {"xbulgnd": (5, 1.5), "xbulbld": (9, 2.0), "xbulcar": (9, 2.0)}
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def parse(text):
    sections, cur = {}, None
    for line in text.splitlines():
        line = line.split("//")[0].strip()
        m = re.match(r"\[(\w+)\]", line)
        if m:
            cur = sections.setdefault(m.group(1).lower(), {})
        elif cur is not None and "=" in line:
            k, v = line.split("=", 1)
            cur[k.strip().lower()] = v.strip().strip('"')
    return sections


def pinned(label, sound):
    # Gameplay fields of the pre-CR-FX files (stock xbulcar; xbulgnd/xbulbld before this change).
    return {"classlabel": label, "explsound": sound, "damageradius": "0.0", "damageballistic": "0",
            "damageconcussion": "0", "damageflame": "0", "damageimpact": "0"}


BASELINE = {"xbulgnd": pinned("groundblast", "wmgr2.wav"),
            "xbulbld": pinned("explosion", "wmgr1.wav"),
            "xbulcar": pinned("explosion", "wmgr1.wav")}


def gameplay(sec):
    return {k: v for k, v in sec["explosionclass"].items() if not k.startswith("particle")}


for name, (budget, maxlife) in FILES.items():
    path = ROOT / "ODF" / (name + ".odf")
    if not path.exists():
        check(False, name + ": missing")
        continue
    sec = parse(path.read_bytes().decode("latin-1"))
    ex = sec["explosionclass"]
    check(gameplay(sec) == BASELINE[name], f"{name}: gameplay fields changed: {gameplay(sec)}")
    total = sum(int(v) for k, v in ex.items() if re.fullmatch(r"particlecount\d+", k))
    check(total <= budget, f"{name}: {total} particles > {budget}")
    for i in range(1, int(ex["particletypes"]) + 1):
        owner, _, section = ex.get(f"particleclass{i}", "").partition(".")
        check(owner.lower() == name, f"{name}: particleClass{i} not its own section")
        check(section.lower() in sec, f"{name}: section {section!r} missing")
    for sname, s in sec.items():
        if sname == "explosionclass":
            continue
        check(s.get("renderbase") != "draw_light", f"{name}.{sname}: light layer")
        tex = s.get("texturename", "")
        check(bool(tex) and (ROOT / "Assets" / "Textures" / tex).exists(), f"{name}.{sname}: texture {tex!r} missing")
        check(float(s["lifetime"]) <= maxlife, f"{name}.{sname}: lifetime too long")
    if name == "xbulcar":
        check(not any("dirt" in s.get("texturename", "") for s in sec.values()), "xbulcar: dirt texture")

for f in failures:
    print("FAIL", f)
print("bullet hit fx:", "FAIL" if failures else "ok")
sys.exit(1 if failures else 0)
