"""Check the unique per-weapon hit explosion ODFs (ODF/<stem>{g,v,b}.odf) and their ordnance wiring.
Gameplay keys must equal the original slot explosions, budgets and lifetimes stay within the DESIGN
caps, every file references only its own sections and only textures that have a material.
Stdlib only: python Tools/Test-WeaponHitFx.py"""
import importlib.util
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ODF = ROOT / "ODF"
failures = []

# The original (pre-change) slot explosions and their gameplay keys are frozen in the baseline,
# so CI does not need the stock game files. The generator's table must still agree with it.
BASE = json.loads((ROOT / "Tools" / "WeaponHitFx.baseline.json").read_text(encoding="utf-8"))
ORIG = {o: tuple(t) for o, t in BASE["ordnance"].items()}
spec = importlib.util.spec_from_file_location("buildhit", ROOT / "Tools" / "Build-WeaponHitFx.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
if {o: tuple(t) for o, t in build.ORIG.items()} != ORIG:
    failures.append("generator ORIG table differs from Tools/WeaponHitFx.baseline.json")

# stem -> (caps g/v/b, ordnance); caps from DESIGN.md.
FAMS = {
    "hmini": ((4, 6, 6), ["bullet1", "bullet1a", "bullet5"]), "hminb": ((4, 6, 6), ["bullet1b"]),
    "hming": ((4, 6, 6), ["bullet1g"]), "hchan": ((5, 7, 7), ["bullet2", "bullet6", "bullet6a"]),
    "hsnip": ((4, 5, 5), ["snipe"]), "hplas": ((5, 6, 6), ["tracer"]), "hpain": ((3, 3, 3), ["dummy"]),
    "hsand": ((3, 3, 3), ["anchor"]), "hmasg": ((4, 5, 5), ["switch"]), "hblst": ((10, 12, 12), ["blast"]),
    "hblsb": ((10, 12, 12), ["blastb"]), "hblsg": ((10, 12, 12), ["blastg"]),
    "hflsh": ((8, 10, 10), ["flash", "flashch"]), "hflsb": ((8, 10, 10), ["flashb"]), "hflsg": ((8, 10, 10), ["flashg"]),
    "hbolt": ((6, 8, 8), ["bolt"]), "hbolg": ((6, 8, 8), ["boltg"]), "hbolr": ((6, 8, 8), ["boltr"]),
    "hmblt": ((7, 9, 9), ["mbolt"]), "hmblg": ((7, 9, 9), ["mboltg"]), "hmblr": ((7, 9, 9), ["mboltr"]),
    "hatst": ((14, 18, 18), ["rocket", "rocketa", "charge6"]),
    "hspst": ((14, 18, 18), ["rocket3", "rocket3b", "rocket3c", "rocket3d", "rocketb3"]),
    "hcpst": ((14, 18, 18), ["rocket3a"]), "hhorn": ((12, 14, 14), ["heatmsl"]), "hshad": ((12, 14, 14), ["imagemsl"]),
    "htag": ((10, 12, 12), ["swarmer"]), "hpop": ((8, 10, 10), ["popper"]),
    "hhowz": ((20, 18, 20), ["shell", "shella", "cvwo004"]), "hmort": ((16, 14, 16), ["grenade"]),
    "hmdm": ((16, 14, 16), ["bouncebm"]), "hspln": ((8, 10, 10), ["splintbm"]), "hsplg": ((8, 10, 10), ["splintbg"]),
    "hsplr": ((8, 10, 10), ["splintbr"]), "hspla": ((8, 10, 10), ["splntbma"]), "hrave": ((8, 10, 10), ["plasma"]),
    "hrkt": ((16, 16, 16), ["rocket2"]),
}
TINT_PAIRS = [("hmini", "hminb"), ("hmini", "hming"), ("hminb", "hming"), ("hblst", "hblsb"), ("hblst", "hblsg"),
              ("hblsb", "hblsg"), ("hflsh", "hflsb"), ("hflsh", "hflsg"), ("hflsb", "hflsg"), ("hbolt", "hbolg"),
              ("hbolt", "hbolr"), ("hbolg", "hbolr"), ("hmblt", "hmblg"), ("hmblt", "hmblr"), ("hmblg", "hmblr"),
              ("hspln", "hsplg"), ("hspln", "hsplr"), ("hspln", "hspla"), ("hsplg", "hsplr"), ("hsplg", "hspla"),
              ("hsplr", "hspla")]
MAX_LIFE, MAX_DECAL_LIFE, MAX_PLANAR_RADIUS, MAX_LIGHT_RADIUS, MAX_LIGHT_ALPHA = 3.0, 10.0, 100.0, 24.0, 255
DIRT = ("dirt",)


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


def gameplay(sec):
    return {k: v for k, v in sec["explosionclass"].items() if not k.startswith("particle")}


def original_gameplay(name):
    return BASE["explosions"].get(name)


materials = set()
for m in (ROOT / "Materials").glob("*.material"):
    materials.update(x.lower() for x in re.findall(r"(?m)^\s*material\s+(\S+)", m.read_text(errors="replace")))
textures = {p.name.lower() for p in (ROOT / "Assets" / "Textures").glob("*")}

files = {}
for stem, (caps, ords) in FAMS.items():
    for i, s in enumerate("gvb"):
        name = stem + s
        check(len(name) <= 8 and name == name.lower(), name + ": bad file name")
        path = ODF / (name + ".odf")
        if not path.exists():
            check(False, name + ": missing")
            continue
        text = path.read_bytes().decode("latin-1")
        sec = parse(text)
        files[name] = (sec, text)
        ex = sec["explosionclass"]
        total = sum(int(v) for k, v in ex.items() if re.fullmatch(r"particlecount\d+", k))
        check(total <= caps[i], f"{name}: {total} particles > cap {caps[i]}")
        lights = 0
        for n in range(1, int(ex["particletypes"]) + 1):
            owner, _, section = ex.get(f"particleclass{n}", "").partition(".")
            check(owner.lower() == name, f"{name}: particleClass{n} not its own section")
            check(section.lower() in sec, f"{name}: section {section!r} missing")
        check(not any(k.startswith("rendername") for s2 in sec.values() for k in s2), name + ": renderName ref")
        for sname, sc in sec.items():
            if sname == "explosionclass":
                continue
            rb = sc.get("renderbase", "")
            life = float(sc["lifetime"])
            r1 = max(float(sc.get("startradius", 0)), float(sc.get("finishradius", 0)))
            if rb == "draw_light":
                lights += 1
                check(r1 <= MAX_LIGHT_RADIUS, f"{name}.{sname}: light radius {r1}")
                check(int(sc["startcolor"].split()[3]) <= MAX_LIGHT_ALPHA, f"{name}.{sname}: light intensity")
                check(life <= MAX_LIFE, f"{name}.{sname}: light lifetime")
                continue
            tex = sc.get("texturename", "")
            check(tex.lower() in textures, f"{name}.{sname}: texture {tex!r} not in Assets/Textures")
            check(tex.lower() in materials, f"{name}.{sname}: texture {tex!r} has no material")
            decal = rb == "draw_planar" and tex == "cr_fx_scorch.dds"
            check(life <= (MAX_DECAL_LIFE if decal else MAX_LIFE), f"{name}.{sname}: lifetime {life}")
            if rb == "draw_planar":
                check(r1 <= MAX_PLANAR_RADIUS, f"{name}.{sname}: planar radius {r1}")
            if s == "v":
                check(not any(d in tex for d in DIRT) and sc.get("useterraincolor") != "true", f"{name}.{sname}: dirt on vehicle")
        check(lights <= 1, f"{name}: {lights} lights")

# ordnance wiring + gameplay copy
stem_of = {o: stem for stem, (_, ords) in FAMS.items() for o in ords}
check(set(stem_of) == set(ORIG), "family table does not cover exactly the stock ordnance: "
      + str(sorted(set(stem_of) ^ set(ORIG))))
for o, stem in stem_of.items():
    path = ODF / (o + ".odf")
    if not path.exists():
        check(False, o + ": no CR ordnance ODF")
        continue
    text = path.read_bytes().decode("latin-1")
    check("// CR HIT FX begin" in text and "// CR HIT FX end" in text, o + ": no marker block")
    check(f"// CR HIT FX begin (was {'/'.join(ORIG[o])})" in text, f"{o}: marker does not record baseline slots {ORIG[o]}")
    sec = parse(text)["ordnanceclass"]
    got = [sec.get("xplground"), sec.get("xplvehicle"), sec.get("xplbuilding")]
    check(got == [stem + "g", stem + "v", stem + "b"] and len(set(got)) == 3, f"{o}: slots {got}")
    for i, s in enumerate("gvb"):
        name = stem + s
        if name in files:
            ref = original_gameplay(ORIG[o][i])
            check(ref is not None and gameplay(files[name][0]) == ref, f"{name}: gameplay differs from {ORIG[o][i]} ({o})")
check(not (ODF / "seismic.odf").exists(), "seismic must keep no hit explosions")

# tinted variants differ in colour; families differ in look
colours = lambda name: sorted(re.findall(r'(?:start|finish)Color = "([^"]+)"', files[name][1]))
for a, b in TINT_PAIRS:
    for s in "gvb":
        if a + s in files and b + s in files:
            check(colours(a + s) != colours(b + s), f"{a}{s} and {b}{s}: same colours")
body = lambda name: re.sub(r"(?m)^//.*\n", "", files[name][1].replace(name, "@"))
for s in "gvb":
    names = [st + s for st in FAMS if st + s in files]
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            check(body(a) != body(b), f"{a} and {b}: identical look")

# howitzer / mortar / MDM must read differently, not only in size
def layers(name):
    sec = files[name][0]
    ex = sec["explosionclass"]
    out = []
    for n in range(1, int(ex["particletypes"]) + 1):
        sname = ex[f"particleclass{n}"].partition(".")[2].lower()
        vel = [float(x) for x in ex.get(f"particleveloc{n}", "0 0 0").split()]
        bias = [float(x) for x in ex.get(f"particlebias{n}", "0 0 0").split()]
        out.append((sec[sname], vel, bias))
    return out


if all(n in files for n in ("hhowzg", "hmortg", "hmdmg")):
    howz, mort, mdm = layers("hhowzg"), layers("hmortg"), layers("hmdmg")
    check(any(s.get("renderbase") == "draw_planar" and "ring" in s.get("texturename", "") and float(s["lifetime"]) <= 0.5
              for s, _, _ in howz), "hhowzg: no fast flat shockwave ring")
    check(any(s.get("texturename") == "cr_xpl_smoke.dds" and v[0] <= 1.0 and b[1] >= 12 for s, v, b in howz),
          "hhowzg: no tall narrow smoke column")
    check(any(s.get("texturename") == "cr_fx_dirt.dds" and b[1] >= 20 for s, v, b in howz), "hhowzg: no high chunks")
    check(not any("ring" in s.get("texturename", "") for s, _, _ in mort), "hmortg: has a ring")
    check(sum(1 for s, v, b in mort if s.get("texturename") == "cr_fx_dirt.dds" and v[0] >= 6 and b[1] <= 5) >= 1
          and sum(int(files["hmortg"][0]["explosionclass"][f"particlecount{i + 1}"]) for i, (s, v, b) in enumerate(mort)
                  if s.get("texturename") == "cr_fx_dirt.dds") >= 6, "hmortg: no wide low dirt fountain")
    check(any(s.get("texturename") == "cr_fx_plasma.dds" for s, _, _ in mdm) and
          any(s.get("lifetime") == "3.00" and "smoke" in s.get("texturename", "") for s, _, _ in mdm),
          "hmdmg: no chemical burst + lingering haze")
    tex = lambda L: {s.get("texturename") for s, _, _ in L}
    check(tex(howz) != tex(mort) and tex(mort) != tex(mdm) and tex(howz) != tex(mdm), "howz/mort/mdm share textures")

for f in failures:
    print("FAIL", f)
print("weapon hit fx:", "FAIL" if failures else "ok")
sys.exit(1 if failures else 0)
