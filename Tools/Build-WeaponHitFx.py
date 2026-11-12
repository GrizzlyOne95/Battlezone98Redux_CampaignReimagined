"""Generate the unique per-weapon hit explosion ODFs (ODF/<stem>{g,v,b}.odf) and wire every
stock-weapon ordnance to them inside a "// CR HIT FX" marker block.

Deterministic and idempotent; run from anywhere:
    python Tools/Build-WeaponHitFx.py

Gameplay keys ([ExplosionClass] non-particle keys) are copied verbatim at run time from the
ORIGINAL slot explosion of each ordnance (ORIG below; CR ODF\\ first, then StockODFFiles).
Every particleClass ref points at the file's own sections (render refs are shared in BZ).

Surface language: ground = soil/dust (+ scorch decal for explosives/energy), vehicle = metal
sparks and hot flecks (never dirt textures), building = masonry chips and grey dust.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ODF = ROOT / "ODF"
STOCK = pathlib.Path(r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\StockODFFiles")
CRLF = "\r\n"
BEGIN = "// CR HIT FX begin"
END = "// CR HIT FX end"

ADD = "one one modulate"
ALPHA = "srcalpha invsrcalpha modulatealpha"

# ordnance -> original (ground, vehicle, building) explosion names (from the stock/CR ordnance ODFs).
ORIG = {
    "anchor": ("xbulgnd", "xbulcar", "xbulbld"),
    "blast": ("xlasgnd", "xlascar", "xlasbld"),
    "blastb": ("xlasgnd", "xlascar", "xlasbld"),
    "blastg": ("xlasgnd", "xlascar", "xlasbld"),
    "bolt": ("xlgtgnd", "xlgtcar", "xlgtbld"),
    "boltg": ("xlgtgndg", "xlgtcarg", "xlgtbldg"),
    "boltr": ("xlgtgndr", "xlgtcarr", "xlgtbldr"),
    "bouncebm": ("xgasgnd", "xgasxpl", "xgasxpl"),
    "bullet1": ("xbulgnd", "xbulcar", "xbulbld"),
    "bullet1a": ("xbulgnd", "xbulcar", "xbulbld"),
    "bullet1b": ("xbulgnd", "xbulcar", "xbulbld"),
    "bullet1g": ("xbulgnd", "xbulcar", "xbulbld"),
    "bullet2": ("xbulgnd", "xbulcar", "xbulbld"),
    "bullet5": ("xbulgnd", "xbulcar", "xbulbld"),
    "bullet6": ("xbulgnd", "xbulcar", "xbulbld"),
    "bullet6a": ("xbulgnd", "xbulcar", "xbulbld"),
    "charge6": ("xmslgnd", "xmslcar", "xmslbld"),
    "cvwo004": ("xgasxpl", "xgasxpl", "xgasxpl"),
    "dummy": ("xbulgnd", "xbulcar", "xbulbld"),
    "flash": ("xlasgnd", "xlascar", "xlasbld"),
    "flashb": ("xlasgnd", "xlascar", "xlasbld"),
    "flashch": ("xlasgnd", "xlascar2", "xlasbld"),
    "flashg": ("xlasgnd", "xlascar", "xlasbld"),
    "grenade": ("xgasgnd", "xgasxpl", "xgasxpl"),
    "heatmsl": ("xmslgnd", "xmslcar", "xmslbld"),
    "imagemsl": ("xmslgnd", "xmslcar", "xmslbld"),
    "mbolt": ("xlgtgnd", "xlgtcar", "xlgtbld"),
    "mboltg": ("xlgtgndg", "xlgtcarg", "xlgtbldg"),
    "mboltr": ("xlgtgndr", "xlgtcarr", "xlgtbldr"),
    "plasma": ("xgasxpl", "xgasxpl", "xgasxpl"),
    "popper": ("xmslgnd", "xmslcar", "xmslbld"),
    "rocket": ("xmslgnd", "xmslcar", "xmslbld"),
    "rocket2": ("xgasxpl", "xgasxpl", "xgasxpl"),
    "rocket3": ("xmslgnd", "xmslcar", "xmslbld"),
    "rocket3a": ("xpltrsi", "xpltrsg", "xpltrsh"),
    "rocket3b": ("xmslgnd", "xmslcar", "xmslbld"),
    "rocket3c": ("xmslgnd", "xmslcar", "xmslbld"),
    "rocket3d": ("xmslgnd", "xmslcar", "xmslbld"),
    "rocketa": ("xmslgnd", "xmslcar", "xmslbld"),
    "rocketb3": ("xmslgnd", "xmslcar", "xmslbld"),
    "shell": ("xgasgnd", "xgasxpl", "xgasxpl"),
    "shella": ("xgasxpl", "xgasxpl", "xgasxpl"),
    "snipe": ("xbulgnd", "xbulcar", "xbulbld"),
    "splintbg": ("xgasxpl", "xgasxpl", "xgasxpl"),
    "splintbm": ("xgasxpl", "xgasxpl", "xgasxpl"),
    "splintbr": ("xgasxpl", "xgasxpl", "xgasxpl"),
    "splntbma": ("xgasxpl", "xgasxpl", "xgasxpl"),
    "swarmer": ("xmslgnd", "xmslcar", "xmslbld"),
    "switch": ("xbulgnd", "xbulcar", "xbulbld"),
    "tracer": ("xbulgnd", "xbulcar", "xbulbld"),
}

# ---------------------------------------------------------------- palettes
# f flash, s sparks, c core/ring/glow, l light, sm smoke, pw dust; each is (start rgb, finish rgb).


def pal(f, s, c, sm=("90 85 80", "40 38 36"), pw=("190 180 165", "130 122 110"), l=None):
    return dict(f=f, s=s, c=c, l=l or c, sm=sm, pw=pw)


PAL = {
    "hot": pal(("255 240 200", "255 120 30"), ("255 250 215", "255 170 50"), ("255 190 100", "230 60 0")),
    "chain": pal(("255 190 110", "255 70 10"), ("255 200 120", "255 90 20"), ("255 150 60", "220 40 0")),
    "blue": pal(("215 232 255", "50 110 255"), ("200 230 255", "40 100 255"), ("150 200 255", "20 70 255"),
                sm=("70 80 110", "30 35 55")),
    "green": pal(("220 255 205", "60 220 50"), ("200 255 170", "40 200 30"), ("160 255 130", "20 170 10"),
                 sm=("60 85 55", "25 38 22")),
    "red": pal(("255 205 190", "255 50 30"), ("255 190 160", "230 30 10"), ("255 150 120", "200 20 0"),
               sm=("85 55 50", "35 22 20")),
    "plasma": pal(("200 255 235", "40 200 170"), ("180 255 225", "30 190 160"), ("120 255 210", "0 170 140"),
                  sm=("60 110 100", "25 50 45")),
    "purple": pal(("245 210 255", "150 40 255"), ("240 190 255", "130 30 255"), ("220 140 255", "110 0 220"),
                  sm=("90 60 110", "40 25 55")),
    "cold": pal(("240 248 255", "120 170 255"), ("230 240 255", "150 190 255"), ("200 225 255", "100 150 255"),
                sm=("150 160 175", "80 90 105")),
    "chem": pal(("225 255 170", "90 220 20"), ("200 255 120", "60 200 10"), ("170 255 90", "50 180 0"),
                sm=("100 125 85", "70 85 55")),
    "fire": pal(("255 225 150", "255 100 10"), ("255 210 120", "255 90 10"), ("255 170 70", "220 40 0"),
                sm=("50 42 36", "20 17 14")),
    "howz": pal(("255 240 200", "255 140 40"), ("255 235 170", "255 130 30"), ("255 200 120", "220 70 0"),
                sm=("84 74 64", "38 34 30"), pw=("150 125 100", "100 82 66")),
    "mort": pal(("255 215 140", "255 110 25"), ("255 200 110", "255 100 20"), ("255 180 90", "230 80 0"),
                sm=("170 145 105", "110 95 70"), pw=("200 172 125", "150 128 95")),
    "gold": pal(("255 255 225", "255 200 60"), ("255 245 170", "255 170 20"), ("255 240 160", "255 140 0")),
    "yellow": pal(("255 240 190", "255 160 20"), ("255 240 110", "255 170 0"), ("255 220 120", "255 120 0")),
    "paint": pal(("255 90 190", "220 20 140"), ("255 235 70", "255 160 20"), ("255 90 190", "220 20 140")),
    "sand": pal(("235 215 170", "190 165 120"), ("235 215 170", "190 165 120"), ("235 215 170", "190 165 120"),
                pw=("225 200 150", "185 165 125")),
    "emp": pal(("200 235 255", "40 120 255"), ("180 225 255", "30 110 255"), ("120 200 255", "20 80 255")),
    "bolt": pal(("200 235 255", "40 130 255"), ("190 235 255", "30 120 255"), ("125 225 255", "25 100 255")),
    "slug": pal(("255 250 235", "255 150 50"), ("255 235 190", "255 130 30"), ("255 210 150", "255 90 20")),
    "amber": pal(("255 235 190", "255 150 30"), ("255 230 170", "255 150 30"), ("255 200 110", "230 100 0")),
    "ice": pal(("225 255 255", "90 200 255"), ("220 255 255", "80 190 255"), ("170 245 255", "40 170 255"),
               sm=("100 125 135", "50 65 75")),
}

# ---------------------------------------------------------------- layer kinds
# sim, render, tex, blend, life, rot, (r0, r1), colour key, start alpha, veloc, bias
K = lambda **kw: kw
KINDS = {
    "flash": K(sim="sim_null", render="draw_sprite", tex="cr_xpl_flash.dds", blend=ADD, life=0.2, r=(0.3, 0.8), col="f"),
    "core": K(sim="sim_smoke", render="draw_twirl", tex="cr_xpl_core.dds", blend=ADD, life=0.5, rot=3.0, r=(1.0, 3.5), col="c"),
    "glint": K(sim="sim_null", render="draw_sprite", tex="cr_xpl_glint.dds", blend=ADD, life=0.25, r=(0.4, 1.2), col="f"),
    "ring": K(sim="sim_null", render="draw_planar", tex="cr_xpl_ring.dds", blend=ADD, life=0.6, r=(2.0, 18.0), col="c"),
    "ringv": K(sim="sim_null", render="draw_sprite", tex="cr_xpl_ring.dds", blend=ADD, life=0.4, r=(1.0, 8.0), col="c"),
    "smring": K(sim="sim_null", render="draw_planar", tex="cr_xpl_smoke.dds", blend=ALPHA, life=1.8, r=(2.0, 16.0), col="sm", a=140),
    "smringv": K(sim="sim_null", render="draw_sprite", tex="cr_xpl_ring.dds", blend=ALPHA, life=1.2, r=(1.0, 9.0), col="sm", a=150),
    "scorch": K(sim="sim_null", render="draw_planar", tex="cr_fx_scorch.dds", blend=ALPHA, life=8.0, r=(3.0, 3.0),
                col=("0 0 0 192", "0 0 0 0")),
    "glow": K(sim="sim_null", render="draw_planar", tex="cr_xpl_core2.dds", blend=ADD, life=2.5, r=(2.0, 3.5), col="c"),
    "spark": K(sim="sim_ember", render="draw_twirl", tex="cr_xpl_spark.dds", blend=ADD, life=0.3, rot=10.0, r=(0.12, 0.03),
               col="s", v=(8, 6, 8), b=(0, 1, 0)),
    "ember": K(sim="sim_ember", render="draw_twirl", tex="cr_xpl_spark.dds", blend=ADD, life=0.9, rot=8.0, r=(0.25, 0.08),
               col="s", v=(5, 4, 5), b=(0, 3, 0)),
    "clod": K(sim="sim_ember", render="draw_twirl", tex="cr_fx_dirt.dds", blend=ALPHA, life=1.4, rot=5.0, r=(0.15, 0.15),
              col=("64 64 64 255", "64 64 64 0"), v=(4, 4, 4), b=(0, 4, 0), terr=True),
    "chip": K(sim="sim_ember", render="draw_twirl", tex="cr_xpl_debris.dds", blend=ALPHA, life=1.0, rot=6.0, r=(0.08, 0.06),
              col=("150 150 145 255", "110 110 105 0"), v=(4, 4, 4), b=(0, 2, 0)),
    "fleck": K(sim="sim_ember", render="draw_twirl", tex="cr_xpl_debris.dds", blend=ALPHA, life=0.6, rot=8.0, r=(0.04, 0.03),
               col=("40 40 42 255", "30 30 32 0"), v=(3, 3, 3), b=(0, 1, 0)),
    "puff": K(sim="sim_smoke", render="draw_sprite", tex="cr_xpl_wisp.dds", blend=ALPHA, life=1.5, r=(0.3, 1.5), col="pw", a=110,
              b=(0, 0.5, 0), sc=1.0, terr=True),
    "dust": K(sim="sim_smoke", render="draw_twirl", tex="cr_xpl_wisp.dds", blend=ALPHA, life=1.8, rot=2.0, r=(0.5, 2.5), col="pw",
              a=120, b=(0, 0.5, 0)),
    "smoke": K(sim="sim_smoke", render="draw_twirl", tex="cr_xpl_smoke.dds", blend=ALPHA, life=2.0, rot=3.0, r=(0.8, 3.0), col="sm",
               a=200, v=(2, 1, 2), b=(0, 1, 0)),
    "wisp": K(sim="sim_smoke", render="draw_twirl", tex="cr_xpl_wisp.dds", blend=ALPHA, life=1.2, rot=2.0, r=(0.3, 1.2), col="sm",
              a=160, v=(1, 0.5, 1), b=(0, 0.5, 0)),
    "flame": K(sim="sim_smoke", render="draw_twirl", tex="cr_xpl_flame.dds", blend=ADD, life=0.6, rot=2.0, r=(1.0, 3.0), col="c",
               v=(0.5, 3, 0.5), b=(0, 3, 0)),
    "plasma": K(sim="sim_smoke", render="draw_twirl", tex="cr_fx_plasma.dds", blend=ADD, life=0.4, rot=4.0, r=(0.5, 1.8), col="c"),
    "arc": K(sim="sim_ember", render="draw_twirl", tex="cr_marc.dds", blend=ADD, life=0.15, rot=12.0, r=(0.7, 0.05), col="f",
             v=(1, 1, 1)),
    "pop": K(sim="sim_ember", render="draw_twirl", tex="cr_xpl_flash.dds", blend=ADD, life=0.15, rot=2.0, r=(0.4, 0.9), col="f",
             v=(3, 2, 3)),
    "blob": K(sim="sim_null", render="draw_sprite", tex="cr_xpl_wisp.dds", blend=ALPHA, life=0.5, r=(0.3, 1.2), col="f", a=230),
    "light": K(sim="sim_null", render="draw_light", life=0.3, r=(10.0, 4.0), col="l"),
}


def L(kind, n=1, **kw):
    return dict(kind=kind, n=n, **kw)


def vec(v):
    return " ".join(f"{x:.2f}" for x in v)


def colour(spec, p, a):
    if isinstance(spec, tuple):
        return spec
    c0, c1 = p[spec]
    return f"{c0} {a}", f"{c1} 0"


def section(name, spec, p):
    d = dict(KINDS[spec["kind"]])
    d.update({k: v for k, v in spec.items() if k not in ("kind", "n", "name")})
    life = d["life"]
    c0, c1 = colour(d["col"], p, d.get("a", 255))
    r0, r1 = d["r"]
    out = [f"[{name}]", f'simulateBase = "{d["sim"]}"', f"lifeTime = {life:.2f}", f'renderBase = "{d["render"]}"']
    if d["render"] == "draw_light":
        out += [f'startColor = "{c0}"', f'finishColor = "{c1}"', f"startRadius = {r0:.2f}", f"finishRadius = {r1:.2f}",
                f"animateTime = {life:.2f}", "attenuateConstant = 0.0", "attenuateLinear = 1.0", "attenuateQuadratic = 0.0"]
    else:
        if "sc" in d:
            out += ["spriteCenter.x = 0.0", f"spriteCenter.y = {d['sc']:.1f}"]
        out += [f'textureName = "{d["tex"]}"', f'textureBlend = "{d.get("blend2", d["blend"])}"',
                f'startColor = "{c0}"', f'finishColor = "{c1}"', f"startRadius = {r0:.2f}", f"finishRadius = {r1:.2f}",
                f"animateTime = {life:.2f}"]
        if "rot" in d:
            out.append(f"rotationRate = {d['rot']:.2f}")
        if d.get("terr"):
            out.append("useTerrainColor = true")
    return "\n".join(out) + "\n", d


# ---------------------------------------------------------------- styles
# Each style returns {"g": [...], "v": [...], "b": [...]} of L(...) layers; counts sum to the budget.

def s_mini(p):
    return dict(
        g=[L("glint", life=0.12, r=(0.1, 0.3)), L("clod", 2, life=0.7, r=(0.07, 0.07), v=(6, 5, 6), b=(0, 5, 0)),
           L("spark", life=0.18, r=(0.1, 0.02), v=(5, 4, 5), b=(0, 2, 0))],
        v=[L("flash", life=0.1, r=(0.15, 0.4), tex="cr_xpl_core.dds"),
           L("spark", 5, life=0.18, r=(0.1, 0.02), v=(12, 8, 12))],
        b=[L("flash", life=0.12, r=(0.15, 0.4)), L("chip", 2, life=0.8, r=(0.05, 0.04), v=(5, 5, 5)),
           L("spark", 3, life=0.25, r=(0.1, 0.02), v=(9, 6, 9), b=(0, 2, 0))])


def s_chan(p):
    return dict(
        g=[L("flash", life=0.25, r=(0.2, 0.6)), L("clod", 2, life=1.6, r=(0.22, 0.22), v=(5, 5, 5), b=(0, 6, 0)),
           L("puff", life=1.6, r=(0.5, 2.2)), L("ember", life=1.0, r=(0.2, 0.08), v=(4, 3, 4), b=(0, 4, 0))],
        v=[L("flash", life=0.2, r=(0.3, 0.8), tex="cr_xpl_core.dds"), L("spark", 3, life=0.3, r=(0.14, 0.04)),
           L("ember", life=0.9, r=(0.3, 0.1), v=(4, 3, 4), b=(0, 3, 0)), L("fleck", life=0.7, r=(0.06, 0.04)),
           L("wisp", life=1.0, r=(0.3, 0.9))],
        b=[L("flash", life=0.22, r=(0.3, 0.8)), L("chip", 3, life=1.1, r=(0.1, 0.07), v=(5, 5, 5), b=(0, 3, 0)),
           L("spark", 2, life=0.35, r=(0.15, 0.04), v=(7, 5, 7)), L("dust", life=1.4, r=(0.4, 1.8))])


def s_snipe(p):
    return dict(
        g=[L("glint", life=0.25, r=(0.3, 1.6)),
           L("spark", name="Streak", life=0.35, r=(0.5, 0.05), v=(0.5, 2, 0.5), b=(0, 22, 0), rot=0.0),
           L("puff", 2, life=1.2, r=(0.15, 0.7), v=(0.4, 2, 0.4), b=(0, 6, 0))],
        v=[L("glint", life=0.25, r=(0.3, 1.5)), L("spark", 4, life=0.35, r=(0.35, 0.05), v=(14, 10, 14), b=(0, 2, 0))],
        b=[L("glint", life=0.25, r=(0.3, 1.5)), L("chip", life=1.0, r=(0.1, 0.07), v=(5, 5, 5)),
           L("puff", life=1.4, r=(0.3, 1.4), v=(0.5, 1, 0.5)), L("spark", 2, life=0.35, r=(0.3, 0.05), v=(11, 8, 11))])


def s_plasma(p):
    sizz = ("120 255 210 150", "0 100 90 0")
    return dict(
        g=[L("plasma", life=0.35, r=(0.6, 2.0)), L("wisp", 2, life=1.4, r=(0.3, 1.0), col=sizz, b=(0, 1.5, 0)),
           L("scorch", life=4.0, r=(2.0, 2.0)), L("glint", life=0.2, r=(0.4, 1.2))],
        v=[L("plasma", life=0.3, r=(0.5, 1.6)), L("spark", 3, life=0.3, r=(0.14, 0.04), v=(8, 6, 8)),
           L("wisp", life=1.1, r=(0.3, 0.9), col=sizz), L("glint", life=0.2, r=(0.4, 1.2))],
        b=[L("plasma", life=0.3, r=(0.5, 1.6)), L("spark", 3, life=0.35, r=(0.14, 0.04), v=(7, 6, 7)),
           L("puff", life=1.3, r=(0.4, 1.6), terr=False), L("wisp", life=1.1, r=(0.3, 0.9), col=sizz)])


def s_paint(p):
    yel = ("255 235 70 255", "255 200 40 0")
    return dict(
        g=[L("scorch", name="Splat", life=4.0, r=(1.6, 1.6), col=("255 40 170 230", "255 40 170 0")),
           L("blob", life=0.5, r=(0.4, 1.3)),
           L("clod", life=1.2, r=(0.12, 0.12), col=("255 40 170 255", "255 40 170 0"), terr=False)],
        v=[L("blob", life=0.4, r=(0.3, 1.0)),
           L("chip", 2, life=0.9, r=(0.08, 0.05), col=("255 40 170 255", "255 40 170 0"), v=(3, 3, 3), b=(0, 1, 0))],
        b=[L("blob", life=0.4, r=(0.3, 1.0)),
           L("chip", name="Drops", life=1.0, r=(0.09, 0.06), col=yel, v=(3, 3, 3), b=(0, 2, 0)),
           L("chip", name="Spatter", life=1.0, r=(0.09, 0.06), col=("255 40 170 255", "255 40 170 0"), v=(3, 3, 3), b=(0, 2, 0))])


def s_sand(p):
    sand = ("215 190 140 255", "190 170 130 0")
    return dict(
        g=[L("puff", life=1.4, r=(0.4, 2.0), col=("215 190 140 160", "180 160 120 0"), terr=False),
           L("clod", 2, life=1.0, r=(0.1, 0.1), col=sand, terr=False, v=(3, 3, 3), b=(0, 3, 0))],
        v=[L("dust", 2, life=1.3, r=(0.4, 1.6), col=("215 190 140 150", "180 160 120 0")),
           L("fleck", life=0.7, r=(0.05, 0.04), col=sand)],
        b=[L("dust", life=1.4, r=(0.5, 1.8), col=("215 190 140 150", "180 160 120 0")),
           L("chip", 2, life=0.9, r=(0.06, 0.05), col=sand, v=(3, 3, 3), b=(0, 2, 0))])


def s_masg(p):
    return dict(
        g=[L("ring", life=0.5, r=(1.0, 14.0)), L("flash", life=0.15, r=(0.5, 1.8)),
           L("arc", 2, life=0.25, r=(0.9, 0.1), v=(2, 1, 2))],
        v=[L("ringv", life=0.4, r=(0.5, 5.0)), L("flash", life=0.15, r=(0.5, 1.6)),
           L("arc", 3, life=0.25, r=(0.9, 0.1), v=(3, 3, 3))],
        b=[L("ringv", life=0.45, r=(0.5, 6.0)), L("flash", life=0.15, r=(0.5, 1.6)),
           L("arc", 3, life=0.3, r=(1.0, 0.1), v=(4, 4, 4), b=(0, 1, 0))])


def s_blast(p):
    return dict(
        g=[L("flash", life=0.25, r=(0.5, 2.5)), L("ring", life=0.5, r=(2.0, 24.0)), L("scorch", r=(4.0, 4.0)),
           L("clod", 4, life=1.8, r=(0.25, 0.25), v=(1.5, 6, 1.5), b=(0, 12, 0)),
           L("puff", life=1.8, r=(0.8, 3.5)),
           L("clod", 2, name="Chunk", life=2.2, r=(0.4, 0.4), v=(3, 6, 3), b=(0, 14, 0))],
        v=[L("flash", life=0.2, r=(0.6, 2.0), tex="cr_xpl_core.dds"), L("ringv", life=0.4, r=(1.0, 9.0)),
           L("spark", 5, life=0.4, r=(0.15, 0.04), v=(9, 7, 9)),
           L("ember", 3, name="Spray", life=1.0, r=(0.3, 0.1), v=(6, 5, 6), b=(0, 3, 0)),
           L("smoke", life=1.5, r=(0.5, 2.0)), L("glint", life=0.2, r=(0.5, 1.6))],
        b=[L("flash", life=0.22, r=(0.6, 2.0)), L("ringv", life=0.4, r=(1.0, 9.0)),
           L("dust", 2, name="Crater", life=2.0, r=(1.0, 4.0), col=("160 158 150 130", "110 108 100 0")),
           L("chip", 5, life=1.3, r=(0.14, 0.1), v=(7, 7, 7), b=(0, 4, 0)),
           L("spark", 2, life=0.4, r=(0.15, 0.04), v=(8, 6, 8)), L("wisp", life=1.4, r=(0.5, 1.6))])


def s_flash(p):
    return dict(
        g=[L("flash", life=0.15, r=(0.8, 3.2)), L("ring", life=0.5, r=(1.0, 14.0)), L("glow"),
           L("arc", 3, life=0.18, r=(0.9, 0.1), v=(3, 1, 3)), L("glint", life=0.25, r=(0.6, 2.0)),
           L("spark", life=0.2, r=(0.1, 0.02), v=(5, 3, 5))],
        v=[L("flash", life=0.15, r=(0.9, 3.5), tex="cr_xpl_core.dds"), L("ringv", life=0.4, r=(0.8, 7.0)),
           L("arc", 4, life=0.18, r=(0.9, 0.1), v=(4, 3, 4)), L("glint", 2, life=0.25, r=(0.6, 1.8)),
           L("spark", 2, life=0.2, r=(0.1, 0.02), v=(6, 4, 6))],
        b=[L("flash", life=0.15, r=(0.9, 3.2)), L("ringv", life=0.4, r=(0.8, 7.0)),
           L("arc", 3, life=0.2, r=(1.0, 0.1), v=(4, 3, 4)), L("glint", life=0.25, r=(0.6, 1.8)),
           L("spark", 4, life=0.25, r=(0.12, 0.03), v=(7, 5, 7), b=(0, 2, 0))])


def s_bolt(p, big=False):
    k = 1.5 if big else 1.0
    t = lambda a, b: (round(a * k, 3), round(b * k, 3))
    lf = lambda x: round(x * k, 2)
    a = (1 if big else 0)
    return dict(
        g=[L("arc", 3 + a, life=lf(0.2), r=t(0.8, 0.1), v=(3, 2, 3)), L("spark", life=lf(0.25), r=t(0.12, 0.03)),
           L("flash", life=lf(0.12), r=t(0.2, 0.6), tex="cr_xpl_core.dds"),
           L("scorch", life=5.0, r=t(2.0, 2.0))],
        v=[L("arc", 4 + a, life=lf(0.2), r=t(0.8, 0.1), v=(3, 3, 3)), L("spark", 2, life=lf(0.25), r=t(0.12, 0.03)),
           L("flash", life=lf(0.12), r=t(0.2, 0.7), tex="cr_xpl_core.dds"), L("glint", life=lf(0.2), r=t(0.4, 1.0))],
        b=[L("arc", 3 + a, life=lf(0.2), r=t(0.8, 0.1), v=(3, 3, 3)), L("spark", 2, life=lf(0.3), r=t(0.12, 0.03)),
           L("flash", life=lf(0.12), r=t(0.2, 0.7), tex="cr_xpl_core.dds"),
           L("chip", life=1.0, r=(0.08, 0.06), v=(4, 4, 4)), L("puff", life=1.3, r=t(0.3, 1.2), terr=False)])


def s_atst(p):
    return dict(
        g=[L("flash", life=0.2, r=(0.6, 2.5)),
           L("flame", name="Jet", life=0.35, r=(0.5, 1.2), v=(0.2, 12, 0.2), b=(0, 10, 0)),
           L("core", life=0.5, r=(1.0, 3.0)), L("scorch", r=(3.5, 3.5)),
           L("clod", 3, life=1.6, r=(0.22, 0.22), v=(1.5, 7, 1.5), b=(0, 10, 0)), L("smoke", 2, life=2.0, r=(0.6, 2.4)),
           L("spark", 4, life=0.4, r=(0.14, 0.04), v=(3, 9, 3), b=(0, 6, 0)),
           L("light", life=0.35, r=(14.0, 8.0))],
        v=[L("flash", life=0.18, r=(0.6, 2.2), tex="cr_xpl_core.dds"), L("core", life=0.4, r=(0.8, 2.4)),
           L("flame", name="Jet", life=0.3, r=(0.4, 1.0), v=(0.2, 10, 0.2), b=(0, 8, 0)),
           L("spark", 6, life=0.4, r=(0.15, 0.04), v=(10, 8, 10)),
           L("ember", 4, name="Drip", life=1.4, r=(0.18, 0.05), v=(3, 3, 3), b=(0, 2, 0), col="c"),
           L("smoke", 2, life=1.8, r=(0.5, 2.0)), L("glint", life=0.2, r=(0.5, 1.6)),
           L("ringv", life=0.3, r=(0.6, 5.0)), L("light", life=0.3, r=(14.0, 8.0))],
        b=[L("flash", life=0.2, r=(0.6, 2.2)), L("core", life=0.4, r=(0.8, 2.4)),
           L("flame", name="Jet", life=0.3, r=(0.4, 1.0), v=(0.2, 10, 0.2), b=(0, 8, 0)),
           L("dust", 2, life=1.8, r=(0.8, 3.0)), L("chip", 5, life=1.3, r=(0.12, 0.09), v=(6, 6, 6), b=(0, 4, 0)),
           L("spark", 4, life=0.4, r=(0.15, 0.04), v=(8, 7, 8), col=("255 240 110 255", "255 170 0 0")),
           L("smoke", 2, life=1.8, r=(0.5, 2.0)), L("glint", life=0.2, r=(0.5, 1.4)),
           L("light", life=0.3, r=(14.0, 8.0))])


def s_spst(p):
    ring_dirt = ("150 120 90 200", "100 80 60 0")
    return dict(
        g=[L("flash", life=0.25, r=(0.8, 3.5)), L("core", tex="cr_xpl_core2.dds", life=0.6, r=(1.5, 6.0)),
           L("ring", name="DirtRing", blend2=ALPHA, col=ring_dirt, life=0.7, r=(2.0, 22.0)),
           L("scorch", life=10.0, r=(5.0, 5.0)), L("clod", 4, life=1.8, r=(0.28, 0.28), v=(5, 5, 5), b=(0, 7, 0)),
           L("flame", life=0.6, r=(1.5, 4.0)), L("smoke", 3, life=2.2, r=(0.8, 3.2)), L("light", life=0.4, r=(18.0, 10.0)),
           L("puff", life=1.8, r=(0.8, 3.5))],
        v=[L("flash", life=0.22, r=(0.8, 3.0), tex="cr_xpl_core.dds"), L("core", tex="cr_xpl_core2.dds", life=0.5, r=(1.2, 5.0)),
           L("ringv", life=0.4, r=(1.0, 10.0)), L("spark", 6, life=0.45, r=(0.16, 0.04), v=(9, 7, 9)),
           L("ember", 4, life=1.2, r=(0.28, 0.08), v=(6, 5, 6), b=(0, 3, 0)), L("smoke", 3, life=2.0, r=(0.6, 2.6)),
           L("flame", life=0.5, r=(1.2, 3.2)), L("light", life=0.35, r=(18.0, 10.0))],
        b=[L("flash", life=0.25, r=(0.8, 3.0)), L("core", tex="cr_xpl_core2.dds", life=0.5, r=(1.2, 5.0)),
           L("ringv", life=0.4, r=(1.0, 10.0)), L("chip", 6, life=1.4, r=(0.14, 0.1), v=(8, 7, 8), b=(0, 4, 0)),
           L("dust", 3, life=2.0, r=(1.0, 4.0)), L("spark", 3, life=0.4, r=(0.15, 0.04), v=(7, 6, 7)),
           L("smoke", 2, life=2.0, r=(0.6, 2.4)), L("light", life=0.35, r=(18.0, 10.0))])


def s_cpst(p):
    return dict(
        g=[L("flash", life=0.2, r=(0.8, 3.2)), L("core", life=0.5, r=(1.2, 4.5)),
           L("ring", life=0.5, r=(2.0, 20.0)), L("scorch", life=10.0, r=(4.0, 4.0)),
           L("spark", 4, life=0.45, r=(0.16, 0.04), v=(5, 8, 5), b=(0, 6, 0)),
           L("clod", 2, life=1.6, r=(0.24, 0.24), v=(4, 6, 4), b=(0, 8, 0)),
           L("flame", 2, life=0.55, r=(1.2, 3.6)), L("smoke", life=2.0, r=(0.8, 3.0)),
           L("light", life=0.4, r=(20.0, 10.0))],
        v=[L("flash", life=0.2, r=(0.8, 3.0), tex="cr_xpl_core.dds"), L("core", life=0.45, r=(1.0, 4.0)),
           L("ringv", life=0.35, r=(1.0, 9.0)), L("spark", 8, life=0.5, r=(0.16, 0.04), v=(11, 8, 11)),
           L("ember", 3, life=1.1, r=(0.26, 0.08), v=(5, 5, 5), b=(0, 3, 0)), L("flame", life=0.5, r=(1.2, 3.2)),
           L("glint", life=0.25, r=(0.6, 2.0)), L("smoke", life=1.8, r=(0.6, 2.2)), L("light", life=0.35, r=(20.0, 10.0))],
        b=[L("flash", life=0.2, r=(0.8, 3.0)), L("core", life=0.45, r=(1.0, 4.0)),
           L("ringv", life=0.35, r=(1.0, 9.0)), L("chip", 4, life=1.3, r=(0.13, 0.09), v=(7, 7, 7), b=(0, 4, 0)),
           L("spark", 6, life=0.45, r=(0.16, 0.04), v=(9, 8, 9)), L("dust", 2, life=1.8, r=(0.8, 3.0)),
           L("flame", life=0.5, r=(1.2, 3.2)), L("glint", life=0.25, r=(0.6, 1.8)), L("light", life=0.35, r=(20.0, 10.0))])


def s_horn(p):
    return dict(
        g=[L("flash", life=0.25, r=(0.8, 3.0)), L("core", life=0.6, r=(1.5, 5.0)), L("scorch", life=8.0, r=(3.5, 3.5)),
           L("smring", r=(2.0, 18.0)), L("clod", 2, life=1.6, r=(0.22, 0.22), v=(4, 5, 4), b=(0, 6, 0)),
           L("smoke", 3, life=2.4, r=(0.8, 3.2)), L("flame", life=0.6, r=(1.5, 4.0)),
           L("spark", life=0.4, r=(0.14, 0.04), v=(5, 7, 5), b=(0, 4, 0)), L("light", life=0.4, r=(16.0, 8.0))],
        v=[L("flash", life=0.22, r=(0.8, 2.8), tex="cr_xpl_core.dds"), L("core", life=0.5, r=(1.2, 4.0)),
           L("smringv", r=(1.0, 10.0)), L("spark", 4, life=0.4, r=(0.15, 0.04), v=(8, 7, 8)),
           L("ember", 2, life=1.0, r=(0.24, 0.07), v=(5, 4, 5), b=(0, 3, 0)), L("smoke", 3, life=2.2, r=(0.6, 2.6)),
           L("flame", life=0.5, r=(1.2, 3.4)), L("light", life=0.35, r=(16.0, 8.0))],
        b=[L("flash", life=0.22, r=(0.8, 2.8)), L("core", life=0.5, r=(1.2, 4.0)), L("smringv", r=(1.0, 10.0)),
           L("chip", 4, life=1.3, r=(0.13, 0.09), v=(6, 6, 6), b=(0, 4, 0)), L("dust", 2, life=1.8, r=(0.8, 3.0)),
           L("spark", 2, life=0.4, r=(0.15, 0.04), v=(7, 6, 7)), L("smoke", 2, life=2.2, r=(0.6, 2.4)),
           L("light", life=0.35, r=(16.0, 8.0))])


def s_shad(p):
    fast = dict(v=(5, 1, 5), life=1.0, r=(0.6, 2.5))
    return dict(
        g=[L("flash", life=0.15, r=(1.0, 4.0)), L("glint", life=0.3, r=(0.8, 2.4)), L("scorch", life=4.0, r=(2.5, 2.5)),
           L("smoke", 4, **fast), L("ring", life=0.45, r=(1.5, 16.0)),
           L("spark", 3, life=0.35, r=(0.14, 0.04), v=(6, 6, 6), b=(0, 4, 0)),
           L("clod", life=1.2, r=(0.2, 0.2), v=(3, 4, 3), b=(0, 5, 0))],
        v=[L("flash", life=0.15, r=(1.0, 3.6), tex="cr_xpl_core.dds"), L("glint", 2, life=0.3, r=(0.8, 2.2)),
           L("ringv", life=0.35, r=(1.0, 9.0)), L("smoke", 4, **fast),
           L("spark", 5, life=0.35, r=(0.14, 0.04), v=(10, 8, 10)), L("wisp", life=1.2, r=(0.4, 1.5))],
        b=[L("flash", life=0.15, r=(1.0, 3.4)), L("glint", life=0.3, r=(0.8, 2.0)), L("ringv", life=0.35, r=(1.0, 9.0)),
           L("smoke", 4, **fast), L("chip", 3, life=1.2, r=(0.12, 0.09), v=(6, 6, 6), b=(0, 3, 0)),
           L("spark", 3, life=0.35, r=(0.14, 0.04), v=(8, 7, 8)), L("dust", life=1.6, r=(0.6, 2.4))])


def s_tag(p):
    return dict(
        g=[L("pop", 5, life=0.15, r=(0.4, 1.0), v=(4, 2, 4), b=(0, 1, 0)),
           L("clod", 2, life=1.0, r=(0.12, 0.12), v=(4, 4, 4), b=(0, 4, 0)), L("puff", life=1.2, r=(0.4, 1.8)),
           L("scorch", life=6.0, r=(2.5, 2.5)), L("spark", life=0.25, r=(0.1, 0.03), v=(5, 5, 5))],
        v=[L("pop", 5, life=0.15, r=(0.4, 1.0), v=(4, 3, 4)), L("spark", 4, life=0.25, r=(0.12, 0.03), v=(8, 6, 8)),
           L("glint", life=0.2, r=(0.5, 1.4)), L("fleck", life=0.6, r=(0.05, 0.04)),
           L("wisp", life=1.1, r=(0.3, 1.0))],
        b=[L("pop", 5, life=0.15, r=(0.4, 1.0), v=(4, 3, 4)), L("chip", 3, life=1.0, r=(0.1, 0.07), v=(5, 5, 5), b=(0, 3, 0)),
           L("spark", 2, life=0.25, r=(0.12, 0.03), v=(7, 6, 7)), L("dust", life=1.3, r=(0.4, 1.6)),
           L("glint", life=0.2, r=(0.5, 1.4))])


def s_pop(p):
    pink = ("255 90 190 255", "255 90 190 0")
    yel = ("255 235 70 255", "255 235 70 0")
    cyan = ("70 230 255 255", "70 230 255 0")

    def conf(n):
        return [L("chip", n, name="ConfettiA", col=pink, life=1.5, r=(0.12, 0.12), v=(4, 4, 4), b=(0, 4, 0)),
                L("chip", n, name="ConfettiB", col=yel, life=1.5, r=(0.12, 0.12), v=(4, 4, 4), b=(0, 4, 0)),
                L("chip", n, name="ConfettiC", col=cyan, life=1.5, r=(0.12, 0.12), v=(4, 4, 4), b=(0, 4, 0))]
    return dict(
        g=[L("flash", life=0.12, r=(0.4, 1.4))] + conf(2) + [L("puff", life=1.2, r=(0.4, 1.6))],
        v=[L("flash", life=0.12, r=(0.4, 1.4)), L("spark", 2, life=0.25, r=(0.12, 0.03), v=(7, 6, 7)),
           L("glint", life=0.2, r=(0.4, 1.2))] + conf(2),
        b=[L("flash", life=0.12, r=(0.4, 1.4)), L("spark", 2, life=0.25, r=(0.12, 0.03), v=(7, 6, 7)),
           L("dust", life=1.2, r=(0.3, 1.3))] + conf(2))


def s_howz(p):
    brown = ("84 74 64 220", "38 34 30 0")
    return dict(
        g=[L("flash", life=0.15, r=(1.5, 6.0)), L("ring", name="Shock", life=0.35, r=(3.0, 60.0), col=("255 235 190 255", "200 150 90 0")),
           L("scorch", life=10.0, r=(9.0, 9.0)),
           L("smoke", 5, name="Column", life=3.0, r=(1.5, 5.5), col=brown, v=(0.8, 5, 0.8), b=(0, 14, 0)),
           L("clod", 5, name="DirtColumn", life=2.8, r=(0.3, 0.3), v=(1.2, 4, 1.2), b=(0, 16, 0)),
           L("clod", 3, name="Chunk", life=3.0, r=(0.6, 0.6), v=(2.5, 5, 2.5), b=(0, 22, 0)),
           L("flame", life=0.5, r=(1.0, 2.5), v=(0.2, 8, 0.2), b=(0, 8, 0)),
           L("wisp", 2, life=2.8, r=(1.0, 3.0), col=("70 62 54 150", "40 36 32 0"), v=(0.5, 3, 0.5), b=(0, 6, 0)),
           L("light", life=0.45, r=(22.0, 10.0))],
        v=[L("flash", life=0.15, r=(1.5, 5.0), tex="cr_xpl_core.dds"),
           L("ringv", name="Shock", life=0.3, r=(2.0, 22.0), col=("255 235 190 255", "200 150 90 0")),
           L("spark", 5, life=0.5, r=(0.2, 0.04), v=(14, 10, 14), b=(0, 3, 0)),
           L("smoke", 4, name="Column", life=2.8, r=(1.2, 4.5), col=brown, v=(0.8, 4, 0.8), b=(0, 12, 0)),
           L("ember", 3, name="HotChunk", life=2.0, r=(0.4, 0.12), v=(3, 4, 3), b=(0, 20, 0), col="c"),
           L("flame", life=0.45, r=(0.8, 2.2), v=(0.2, 6, 0.2), b=(0, 6, 0)), L("glint", life=0.25, r=(0.8, 2.6)),
           L("wisp", life=2.4, r=(0.8, 2.4), col=("70 62 54 150", "40 36 32 0")), L("light", life=0.4, r=(20.0, 10.0))],
        b=[L("flash", life=0.18, r=(1.5, 5.0)),
           L("ringv", name="Shock", life=0.3, r=(2.0, 22.0), col=("235 225 210 255", "160 150 130 0")),
           L("dust", 4, name="DustColumn", life=2.6, r=(1.2, 4.0), col=("150 148 140 160", "100 98 92 0"), v=(0.8, 4, 0.8), b=(0, 12, 0)),
           L("chip", 5, name="BigChip", life=2.4, r=(0.22, 0.16), v=(3, 5, 3), b=(0, 20, 0)),
           L("smoke", 4, name="Column", life=3.0, r=(1.2, 4.5), col=brown, v=(0.8, 5, 0.8), b=(0, 13, 0)),
           L("spark", 3, life=0.45, r=(0.2, 0.04), v=(10, 8, 10), b=(0, 3, 0)),
           L("flame", life=0.45, r=(0.8, 2.2), v=(0.2, 6, 0.2), b=(0, 6, 0)), L("light", life=0.4, r=(20.0, 10.0))])


def s_mort(p):
    tan = ("200 172 125 150", "150 128 95 0")
    return dict(
        g=[L("flash", life=0.12, r=(0.8, 2.6)), L("scorch", life=8.0, r=(5.0, 5.0)),
           L("clod", 8, name="Fountain", life=1.4, r=(0.13, 0.13), v=(6.5, 2.5, 6.5), b=(0, 4, 0)),
           L("puff", 4, name="Dust", life=1.6, r=(1.5, 6.0), col=tan, v=(3, 0.3, 3), terr=False),
           L("smoke", name="Low", life=2.0, r=(1.0, 4.0), col=("150 128 95 150", "110 95 70 0")),
           L("light", life=0.3, r=(14.0, 6.0))],
        v=[L("flash", life=0.12, r=(0.8, 2.4), tex="cr_xpl_core.dds"), L("spark", 4, life=0.3, r=(0.14, 0.04), v=(7, 5, 7)),
           L("ember", 3, name="Fleck", life=0.6, r=(0.14, 0.05), v=(5, 3, 5), b=(0, 2, 0)),
           L("dust", 2, life=1.5, r=(0.8, 3.0), col=tan), L("smoke", 2, life=1.8, r=(0.8, 3.0), col=("150 128 95 150", "110 95 70 0")),
           L("glint", life=0.2, r=(0.5, 1.6)), L("light", life=0.3, r=(14.0, 6.0))],
        b=[L("flash", life=0.12, r=(0.8, 2.4)), L("chip", 6, life=1.2, r=(0.07, 0.05), v=(6, 4, 6), b=(0, 3, 0)),
           L("dust", 4, life=1.7, r=(1.0, 4.0), col=tan), L("spark", 2, life=0.3, r=(0.14, 0.04), v=(6, 5, 6)),
           L("smoke", 2, life=1.8, r=(0.8, 3.0), col=("150 128 95 150", "110 95 70 0")), L("light", life=0.3, r=(14.0, 6.0))])


def s_mdm(p):
    haze = ("100 125 85 120", "70 85 55 0")
    wisp = ("150 230 90 150", "60 130 30 0")
    return dict(
        g=[L("flash", tex="cr_xpl_greenhit.dds", life=0.2, r=(0.8, 3.0)), L("plasma", life=0.5, r=(1.0, 5.0)),
           L("scorch", life=6.0, r=(4.0, 4.0), col=("25 45 12 190", "25 45 12 0")),
           L("spark", 5, name="Bounce", life=1.2, r=(0.16, 0.05), v=(4, 6, 4), b=(0, 8, 0)),
           L("smoke", 4, name="Haze", life=3.0, r=(1.5, 5.0), col=haze, v=(1.5, 0.3, 1.5), b=(0, 0.4, 0)),
           L("glint", life=0.3, r=(0.6, 2.0)), L("wisp", 2, life=2.0, r=(0.6, 2.0), col=wisp),
           L("light", life=0.4, r=(14.0, 6.0))],
        v=[L("flash", tex="cr_xpl_greenhit.dds", life=0.2, r=(0.8, 2.8)), L("plasma", life=0.45, r=(0.8, 4.0)),
           L("spark", 5, name="Bounce", life=1.2, r=(0.16, 0.05), v=(4, 6, 4), b=(0, 6, 0)),
           L("smoke", 3, name="Haze", life=3.0, r=(1.2, 4.0), col=haze, v=(1.5, 0.3, 1.5), b=(0, 0.4, 0)),
           L("wisp", life=2.0, r=(0.6, 1.8), col=wisp), L("glint", life=0.3, r=(0.6, 1.8)),
           L("ember", name="Drip", life=1.5, r=(0.2, 0.06), v=(2, 2, 2), b=(0, 1, 0), col="c"),
           L("light", life=0.35, r=(12.0, 6.0))],
        b=[L("flash", tex="cr_xpl_greenhit.dds", life=0.2, r=(0.8, 2.8)), L("plasma", life=0.45, r=(0.8, 4.0)),
           L("spark", 4, name="Bounce", life=1.2, r=(0.16, 0.05), v=(4, 6, 4), b=(0, 6, 0)),
           L("smoke", 4, name="Haze", life=3.0, r=(1.2, 4.5), col=haze, v=(1.5, 0.3, 1.5), b=(0, 0.4, 0)),
           L("chip", 2, col=("120 130 105 255", "90 100 80 0"), life=1.4, r=(0.1, 0.07), v=(4, 4, 4), b=(0, 3, 0)),
           L("wisp", 2, life=2.0, r=(0.6, 1.8), col=wisp),
           L("ember", name="Drip", life=1.5, r=(0.2, 0.06), v=(2, 2, 2), b=(0, 1, 0), col="c"),
           L("glint", life=0.3, r=(0.6, 1.8))])


def s_splint(p):
    return dict(
        g=[L("flash", life=0.12, r=(0.3, 1.2)),
           L("spark", 4, name="Shard", life=0.6, r=(0.35, 0.05), v=(14, 10, 14), b=(0, 3, 0)),
           L("clod", 2, life=1.0, r=(0.12, 0.12), v=(4, 4, 4), b=(0, 4, 0)), L("scorch", life=5.0, r=(2.5, 2.5))],
        v=[L("flash", life=0.12, r=(0.3, 1.2), tex="cr_xpl_core.dds"),
           L("spark", 6, name="Shard", life=0.6, r=(0.35, 0.05), v=(14, 10, 14), b=(0, 3, 0)),
           L("spark", 2, life=0.25, r=(0.12, 0.03)), L("glint", life=0.2, r=(0.4, 1.2))],
        b=[L("flash", life=0.12, r=(0.3, 1.2)), L("spark", 4, name="Shard", life=0.6, r=(0.35, 0.05), v=(13, 9, 13), b=(0, 3, 0)),
           L("chip", 3, life=1.0, r=(0.1, 0.07), v=(5, 5, 5), b=(0, 3, 0)), L("spark", life=0.25, r=(0.12, 0.03)),
           L("puff", life=1.3, r=(0.3, 1.3), terr=False)])


def s_rave(p):
    pink = ("255 90 200 255", "255 90 200 0")
    cyan = ("70 230 255 255", "70 230 255 0")
    yel = ("255 235 90 255", "255 235 90 0")
    wpu = ("150 80 220 150", "70 30 120 0")
    return dict(
        g=[L("flash", life=0.2, r=(0.6, 2.4)), L("plasma", name="PlasmaA", life=0.4, r=(0.8, 2.8)),
           L("plasma", name="PlasmaB", col=cyan, life=0.35, r=(0.6, 2.2)),
           L("glint", name="GlintA", col=pink, life=0.25, r=(0.5, 1.8)),
           L("glint", name="GlintB", col=cyan, life=0.25, r=(0.5, 1.8)),
           L("scorch", life=6.0, r=(3.0, 3.0), col=("60 20 90 190", "60 20 90 0")), L("wisp", 2, life=1.8, r=(0.5, 1.8), col=wpu)],
        v=[L("flash", life=0.2, r=(0.6, 2.2), tex="cr_xpl_core.dds"), L("plasma", name="PlasmaA", life=0.4, r=(0.8, 2.4)),
           L("plasma", name="PlasmaB", col=cyan, life=0.35, r=(0.6, 2.0)),
           L("spark", 3, col=("255 120 220 255", "200 40 160 0"), life=0.35, r=(0.14, 0.04), v=(8, 6, 8)),
           L("glint", name="GlintA", col=cyan, life=0.25, r=(0.5, 1.6)),
           L("glint", name="GlintB", col=yel, life=0.25, r=(0.5, 1.6)), L("wisp", 2, life=1.6, r=(0.4, 1.5), col=wpu)],
        b=[L("flash", life=0.2, r=(0.6, 2.2)), L("plasma", name="PlasmaA", life=0.4, r=(0.8, 2.4)),
           L("plasma", name="PlasmaB", col=cyan, life=0.35, r=(0.6, 2.0)),
           L("spark", 2, col=("255 120 220 255", "200 40 160 0"), life=0.35, r=(0.14, 0.04), v=(7, 6, 7)),
           L("glint", name="GlintA", col=pink, life=0.25, r=(0.5, 1.6)),
           L("glint", name="GlintB", col=yel, life=0.25, r=(0.5, 1.6)),
           L("chip", life=1.0, r=(0.1, 0.07), v=(5, 5, 5), b=(0, 3, 0)), L("dust", life=1.4, r=(0.4, 1.6)),
           L("wisp", life=1.5, r=(0.4, 1.5), col=wpu)])


def s_rkt(p):
    return dict(
        g=[L("flash", life=0.25, r=(1.0, 4.0)), L("core", 2, life=0.7, r=(2.0, 8.0)),
           L("flame", 2, life=0.7, r=(1.5, 4.5)), L("scorch", life=10.0, r=(6.0, 6.0)),
           L("clod", 3, life=2.0, r=(0.3, 0.3), v=(3, 7, 3), b=(0, 10, 0)), L("smoke", 4, life=2.8, r=(1.0, 4.5)),
           L("ring", life=0.5, r=(2.0, 28.0)), L("light", life=0.45, r=(20.0, 10.0)), L("puff", life=2.0, r=(1.0, 4.0))],
        v=[L("flash", life=0.25, r=(1.0, 3.6), tex="cr_xpl_core.dds"), L("core", 2, life=0.6, r=(1.5, 6.0)),
           L("flame", 2, life=0.6, r=(1.2, 4.0)), L("ringv", life=0.4, r=(1.0, 11.0)),
           L("spark", 4, life=0.45, r=(0.16, 0.04), v=(10, 8, 10)),
           L("ember", 2, life=1.2, r=(0.28, 0.08), v=(5, 5, 5), b=(0, 3, 0)), L("smoke", 3, life=2.6, r=(0.8, 3.6)),
           L("light", life=0.4, r=(20.0, 10.0))],
        b=[L("flash", life=0.25, r=(1.0, 3.6)), L("core", 2, life=0.6, r=(1.5, 6.0)), L("flame", life=0.6, r=(1.2, 4.0)),
           L("ringv", life=0.4, r=(1.0, 11.0)), L("chip", 4, life=1.4, r=(0.14, 0.1), v=(7, 7, 7), b=(0, 4, 0)),
           L("dust", 2, life=2.0, r=(1.0, 4.0)), L("smoke", 3, life=2.6, r=(0.8, 3.6)),
           L("spark", life=0.4, r=(0.15, 0.04), v=(8, 6, 8)), L("light", life=0.4, r=(20.0, 10.0))])


# ---------------------------------------------------------------- families
# stem, style, palette, (g, v, b) budget caps (DESIGN.md), ordnance, look text
def fam(stem, style, pname, caps, ords, look, **kw):
    return dict(stem=stem, style=style, pal=pname, caps=caps, ords=ords, look=look, kw=kw)


FAMILIES = [
    fam("hmini", s_mini, "hot", (4, 6, 6), ["bullet1", "bullet1a", "bullet5"], "minigun: tiny white-hot sparks, quick dirt spit"),
    fam("hminb", s_mini, "blue", (4, 6, 6), ["bullet1b"], "minigun, blue tint"),
    fam("hming", s_mini, "green", (4, 6, 6), ["bullet1g"], "minigun, green tint"),
    fam("hchan", s_chan, "chain", (5, 7, 7), ["bullet2", "bullet6", "bullet6a"], "chaingun: heavy orange flash, big clod, hot chunk"),
    fam("hsnip", s_snipe, "cold", (4, 5, 5), ["snipe"], "sniper: long white streak, glint, thin dust jet"),
    fam("hplas", s_plasma, "plasma", (5, 6, 6), ["tracer"], "plasma rifle: blue-green splash, sizzle wisps, small scorch"),
    fam("hpain", s_paint, "paint", (3, 3, 3), ["dummy"], "paintball: coloured splat, no sparks"),
    fam("hsand", s_sand, "sand", (3, 3, 3), ["anchor"], "sandbag: beige sand puff"),
    fam("hmasg", s_masg, "emp", (4, 5, 5), ["switch"], "MAS grenade: blue EMP ring and crackle"),
    fam("hblst", s_blast, "slug", (10, 12, 12), ["blast"], "blast cannon: shockwave ring, dirt cone, chunks"),
    fam("hblsb", s_blast, "blue", (10, 12, 12), ["blastb"], "blast cannon, blue"),
    fam("hblsg", s_blast, "green", (10, 12, 12), ["blastg"], "blast cannon, green"),
    fam("hflsh", s_flash, "cold", (8, 10, 10), ["flash", "flashch"], "flash cannon: white flash, glow ring, short arcs"),
    fam("hflsb", s_flash, "blue", (8, 10, 10), ["flashb"], "flash cannon, blue"),
    fam("hflsg", s_flash, "green", (8, 10, 10), ["flashg"], "flash cannon, green"),
    fam("hbolt", s_bolt, "bolt", (6, 8, 8), ["bolt"], "Bolt Buddy: arc crackle, small burst"),
    fam("hbolg", s_bolt, "green", (6, 8, 8), ["boltg"], "Bolt Buddy, green"),
    fam("hbolr", s_bolt, "red", (6, 8, 8), ["boltr"], "Bolt Buddy, red"),
    fam("hmblt", s_bolt, "bolt", (7, 9, 9), ["mbolt"], "Mega Bolt: larger, longer crackle", big=True),
    fam("hmblg", s_bolt, "green", (7, 9, 9), ["mboltg"], "Mega Bolt, green", big=True),
    fam("hmblr", s_bolt, "red", (7, 9, 9), ["mboltr"], "Mega Bolt, red", big=True),
    fam("hatst", s_atst, "yellow", (14, 18, 18), ["rocket", "rocketa", "charge6"], "AT-Stabber: tight jet, fireball, molten drips"),
    fam("hspst", s_spst, "amber", (14, 18, 18), ["rocket3", "rocket3b", "rocket3c", "rocket3d", "rocketb3"],
        "SP-Stabber: wide fireball, dirt ring, 10 s scorch"),
    fam("hcpst", s_cpst, "gold", (14, 18, 18), ["rocket3a"], "CP-Stabber: hotter gold fireball and sparks"),
    fam("hhorn", s_horn, "fire", (12, 14, 14), ["heatmsl"], "Hornet: orange fireball, smoke ring"),
    fam("hshad", s_shad, "cold", (12, 14, 14), ["imagemsl"], "Shadower: cold flash, fast smoke"),
    fam("htag", s_tag, "amber", (10, 12, 12), ["swarmer"], "TAG: cluster of small quick pops"),
    fam("hpop", s_pop, "hot", (8, 10, 10), ["popper"], "Pop Gun: small pop, confetti chunks"),
    fam("hhowz", s_howz, "howz", (20, 18, 20), ["shell", "shella", "cvwo004"],
        "howitzer: tall narrow dirt/smoke column, fast flat shock ring, big chunks thrown high"),
    fam("hmort", s_mort, "mort", (16, 14, 16), ["grenade"], "mortar: wide low dirt fountain, tan dust, short flash, no ring"),
    fam("hmdm", s_mdm, "chem", (16, 14, 16), ["bouncebm"], "MDM: green chemical burst, lingering haze, bouncy sparks"),
    fam("hspln", s_splint, "amber", (8, 10, 10), ["splintbm"], "splinter: flechette streaks, amber"),
    fam("hsplg", s_splint, "green", (8, 10, 10), ["splintbg"], "splinter, green"),
    fam("hsplr", s_splint, "red", (8, 10, 10), ["splintbr"], "splinter, red"),
    fam("hspla", s_splint, "ice", (8, 10, 10), ["splntbma"], "splinter, ice-blue (alt)"),
    fam("hrave", s_rave, "purple", (8, 10, 10), ["plasma"], "RAVE GUN: purple/rainbow plasma"),
    fam("hrkt", s_rkt, "fire", (16, 16, 16), ["rocket2"], "Rocket bomb: big fiery blast, smoke"),
]

SURF = {"g": "Ground", "v": "Vehicle", "b": "Building"}


# ---------------------------------------------------------------- gameplay copy
def resolve(name):
    for d in (ODF, STOCK):
        p = d / (name + ".odf")
        if p.exists():
            return p
    raise SystemExit(f"explosion {name}.odf not found in CR ODF or stock")


def explosion_body(name, depth=0):
    text = resolve(name).read_bytes().decode("latin-1").replace("\r\n", "\n")
    m = re.search(r"(?im)^\[ExplosionClass\][^\n]*\n", text)
    if not m:
        base = re.search(r'(?im)^\s*baseName\s*=\s*"([^"]+)"', text)
        assert base and depth < 5, f"{name}: no [ExplosionClass] and no baseName"
        return explosion_body(base.group(1), depth + 1)
    nxt = re.search(r"(?m)^\[", text[m.end():])
    return text[m.end(): m.end() + nxt.start() if nxt else len(text)]


def gameplay_lines(name):
    lines = [l.rstrip() for l in explosion_body(name).split("\n")
             if l.strip() and not l.strip().startswith("//") and not re.match(r"\s*particle", l, re.I)]
    assert lines, name
    return lines


def gp_key(lines):
    return sorted(re.sub(r"\s*//.*", "", l).strip().lower() for l in lines)


# ---------------------------------------------------------------- generation
def gen_file(f, surf):
    stem = f["stem"]
    name = stem + surf
    assert len(name) <= 8, name
    p = PAL[f["pal"]]
    layers = f["style"](p, **f["kw"])[surf]
    seen, secs, ex = {}, [], []
    total = 0
    lights = 0
    for i, spec in enumerate(layers, 1):
        base = spec.get("name") or spec["kind"].capitalize()
        seen[base] = seen.get(base, 0) + 1
        sname = base if seen[base] == 1 else f"{base}{seen[base]}"
        text, d = section(sname, spec, p)
        secs.append(text)
        n = spec["n"]
        total += n
        lights += d["render"] == "draw_light"
        ex.append((i, sname, n, d))
    assert lights <= 1, name
    # gameplay from the ORIGINAL slot of the first ordnance (all must agree)
    idx = "gvb".index(surf)
    gps = []
    for o in f["ords"]:
        gps.append((ORIG[o][idx], gameplay_lines(ORIG[o][idx])))
    for orig, lines in gps[1:]:
        if gp_key(lines) != gp_key(gps[0][1]):
            raise SystemExit(f"{name}: gameplay of {orig} differs from {gps[0][0]}; split family {stem}")
    head = [f"// {SURF[surf]} hit: {f['look']}. Particle budget {total} (cap {f['caps']['gvb'.index(surf)]}).",
            "// Generated by Tools/Build-WeaponHitFx.py; gameplay keys copied from "
            + "/".join(sorted({g[0] for g in gps})) + ".",
            "[ExplosionClass]"] + gps[0][1] + ["", f"particleTypes = {len(ex)}", ""]
    for i, sname, n, d in ex:
        head.append(f'particleClass{i} = "{name}.{sname}"')
        head.append(f"particleCount{i} = {n}")
        v = d.get("v", (0, 0, 0)) if d["render"] != "draw_light" else (0, 2, 0)
        head.append(f'particleVeloc{i} = "{vec(v)}"')
        b = d.get("b", (0, 0, 0)) if d["render"] != "draw_light" else (0, 5, 0)
        if any(b):
            head.append(f'particleBias{i} = "{vec(b)}"')
        head.append("")
    assert total <= f["caps"]["gvb".index(surf)], f"{name}: budget {total} > cap"
    return name, "\n".join(head) + "\n" + "\n".join(secs), total


def write(path, text):
    data = text.replace("\r\n", "\n").replace("\n", CRLF).encode("ascii")
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)


def wire(ordnance, names):
    """Replace the three xpl* lines in the ordnance ODF with a CR HIT FX marker block."""
    cr = ODF / (ordnance + ".odf")
    src = cr if cr.exists() else STOCK / (ordnance + ".odf")
    raw = src.read_bytes()
    text = raw.decode("latin-1")
    lines = text.splitlines(keepends=True)
    orig = ORIG[ordnance]
    eol_of = lambda l: "\r\n" if l.endswith("\r\n") else ("\n" if l.endswith("\n") else "")
    pat = re.compile(r"^\s*xpl(Ground|Vehicle|Building)\s*=", re.I)
    out, done = [], False
    i = 0
    while i < len(lines):
        l = lines[i]
        if l.strip() == BEGIN or l.strip().startswith(BEGIN):
            j = i
            while lines[j].strip() != END:
                j += 1
            e = eol_of(lines[i]) or eol_of(lines[j]) or "\r\n"
            block = [f"{BEGIN} (was {'/'.join(orig)}){e}",
                     f'xplGround = "{names[0]}"{e}', f'xplVehicle = "{names[1]}"{e}',
                     f'xplBuilding = "{names[2]}"{e}', f"{END}{eol_of(lines[j])}"]
            out += block
            i = j + 1
            done = True
            continue
        if pat.match(l):
            if not done:
                e = eol_of(l) or "\r\n"
                out += [f"{BEGIN} (was {'/'.join(orig)}){e}", f'xplGround = "{names[0]}"{e}',
                        f'xplVehicle = "{names[1]}"{e}', f'xplBuilding = "{names[2]}"{e}', f"{END}{e}"]
                done = True
            i += 1
            continue
        out.append(l)
        i += 1
    assert done, f"{ordnance}: no xpl lines"
    data = "".join(out).encode("latin-1")
    if not cr.exists() or cr.read_bytes() != data:
        cr.write_bytes(data)


def main():
    budgets = {}
    mapped = set()
    existing = {p.stem.lower() for p in ODF.glob("*.odf")}
    for f in FAMILIES:
        names = []
        for s in "gvb":
            name, text, total = gen_file(f, s)
            write(ODF / (name + ".odf"), text)
            names.append(name)
            budgets[name] = total
        for o in f["ords"]:
            assert o not in mapped, o
            mapped.add(o)
            wire(o, tuple(names))
    missing = set(ORIG) - mapped
    assert not missing, f"ordnance without a family: {sorted(missing)}"
    if "--budgets" in sys.argv:
        for f in FAMILIES:
            print(f["stem"], "/".join(str(budgets[f["stem"] + s]) for s in "gvb"))
    print(f"{len(FAMILIES) * 3} hit files, {len(mapped)} ordnance wired")


if __name__ == "__main__":
    main()
