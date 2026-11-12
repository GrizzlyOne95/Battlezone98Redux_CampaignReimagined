"""Generate the per-faction craft death explosion ODFs (xd<fac><stage>) and wire
xplSnipe/xplSecondary/xplDetonate/explosionName into faction craft ODFs.

Deterministic and idempotent; run from the repo root:
    python Tools/Build-FactionDeathExplosions.py

Gameplay fields ([ExplosionClass] radius/sound/damage) are copied at run time from the
stock explosion each file replaces, so only the particle layers differ.
Every render ref points at the file's own sections (render refs are shared in BZ).
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
ODF = ROOT / "ODF"
CRLF = "\r\n"

# stage -> (label, engine key, stock explosion it replaces, extra particle allowance)
STAGES = {
    "i": ("INITIAL", "explosionName", "xcarxpla", 0),
    "s": ("SECONDARY", "xplSecondary", "xsecxpla", 0),
    "d": ("DETONATE", "xplDetonate", "xcarxplb", 0),
    "p": ("SNIPE", "xplSnipe", "xsecxpla", 2),
}
ADD = "one one modulate"
ALPHA = "srcalpha invsrcalpha modulatealpha"

# Palette per faction; colours are "r g b" and get an alpha appended per layer.
FACTIONS = {
    "nsdf": dict(
        title="NSDF", scale=1.0,
        look="cool white-blue flash, cyan-white electrical sparks, grey coolant vapour",
        flash=("235 245 255", "90 170 255"), core=("205 235 255", "40 120 255"),
        spark=("cr_xpl_spark.dds", "200 245 255", "30 140 255"),
        smoke=("cr_xpl_wisp.dds", "175 180 190", "90 92 100", 200),
        debris=("200 210 225", "100 110 125"), light=("210 240 255", "90 160 255")),
    "cca": dict(
        title="CCA", scale=1.3,
        look="big orange fireball, fat brown-black diesel soot, chunky orange embers",
        flash=("255 235 175", "255 120 20"), core=("255 195 95", "230 60 0"),
        spark=("cr_xpl_spark.dds", "255 195 75", "220 70 0"),
        smoke=("cr_xpl_smoke.dds", "70 56 40", "30 25 18", 225),
        debris=("230 190 150", "110 90 70"), light=("255 170 90", "255 90 15")),
    "bdog": dict(
        title="Black Dog", scale=0.8,
        look="tight hot flash, crimson embers, fast near-black column",
        flash=("255 200 180", "200 20 20"), core=("255 130 110", "140 0 0"),
        spark=("cr_xpl_spark.dds", "255 100 90", "160 0 0"),
        smoke=("cr_xpl_smoke.dds", "32 28 30", "10 8 8", 230),
        debris=("120 110 115", "50 45 48"), light=("255 110 90", "255 60 40")),
    "cra": dict(
        title="CRA", scale=1.0,
        look="yellow-green chemical flash, lime glints, olive soot",
        flash=("240 255 175", "120 200 0"), core=("215 255 125", "90 170 0"),
        spark=("cr_xpl_glint.dds", "200 255 110", "60 170 0"),
        smoke=("cr_xpl_smoke.dds", "66 74 46", "28 34 18", 215),
        debris=("190 200 150", "90 100 60"), light=("200 255 150", "110 190 30")),
}


def write(path, text):
    path.write_bytes(text.replace("\r\n", "\n").replace("\n", CRLF).encode("ascii"))


def stock_text(stock):
    return (ODF / (stock + ".odf")).read_bytes().decode("latin-1").replace("\r\n", "\n")


def stock_gameplay(stock):
    """Non-particle lines of the stock [ExplosionClass] section, verbatim."""
    text = stock_text(stock)
    m = re.search(r"(?im)^\[ExplosionClass\][^\n]*\n", text)
    nxt = re.search(r"(?m)^\[", text[m.end():])
    body = text[m.end(): m.end() + nxt.start() if nxt else len(text)]
    lines = [l for l in body.split("\n") if l.strip() and not re.match(r"\s*particle", l, re.I)]
    assert lines, stock
    return lines


def layer(name, sim, render, tex, blend, life, c0, c1, r0, r1, rot=None):
    if render == "draw_light":
        lines = [f"[{name}]", f'simulateBase = "{sim}"', f"lifeTime = {life}", 'renderBase = "draw_light"',
                 f'startColor = "{c0}"', f'finishColor = "{c1}"', f"startRadius = {r0:.2f}",
                 f"finishRadius = {r1:.2f}", f"animateTime = {life}", "attenuateConstant = 0.0",
                 "attenuateLinear = 1.0", "attenuateQuadratic = 0.0"]
    else:
        lines = [f"[{name}]", f'simulateBase = "{sim}"', f"lifeTime = {life:.2f}", f'renderBase = "{render}"',
                 f'textureName = "{tex}"', f'textureBlend = "{blend}"', f'startColor = "{c0}"',
                 f'finishColor = "{c1}"', f"startRadius = {r0:.2f}", f"finishRadius = {r1:.2f}",
                 f"animateTime = {life:.2f}"]
        if rot is not None:
            lines.append(f"rotationRate = {rot:.2f}")
    return "\n".join(lines) + "\n"


def build(key, stage):
    f = FACTIONS[key]
    k = f["scale"]
    root = f"xd{key}{stage}"
    assert len(root) <= 8, root
    s = lambda v: round(v * k, 2)
    sparktex, sc0, sc1 = f["spark"]
    smtex, sm0, sm1, sma = f["smoke"]
    d0, d1 = f["debris"]

    def flash(r0, r1, life):
        return layer("Flash", "sim_null", "draw_sprite", "cr_xpl_flash.dds", ADD, life,
                     f"{f['flash'][0]} 255", f"{f['flash'][1]} 0", r0, r1)

    def core(tex, r0, r1, life):
        return layer("Core", "sim_smoke", "draw_twirl", tex, ADD, life,
                     f"{f['core'][0]} 255", f"{f['core'][1]} 0", r0, r1, 3.0)

    def ember(r0, r1, life):
        return layer("Ember", "sim_ember", "draw_twirl", sparktex, ADD, life, f"{sc0} 255", f"{sc1} 0", r0, r1, 8.0)

    def smoke(r0, r1, life):
        return layer("Smoke", "sim_smoke", "draw_twirl", smtex, ALPHA, life, f"{sm0} {sma}", f"{sm1} 0", r0, r1, 3.0)

    def debris(r, life):
        return layer("Debris", "sim_ember", "draw_twirl", "cr_xpl_debris.dds", ALPHA, life,
                     f"{d0} 255", f"{d1} 0", r, r, 6.0)

    def lite(r, life):
        return layer("Light", "sim_smoke", "draw_light", None, None, life,
                     f"{f['light'][0]} 255", f"{f['light'][1]} 0", r, r)

    # (section text, count, veloc, bias)
    if stage == "i":
        L = [(flash(s(7), s(14), 0.25), 1, "0.00 0.00 0.00", None),
             (core("cr_xpl_core.dds", s(3.5), s(11), 1.0), 1, "0.00 1.00 0.00", "0.00 2.00 0.00"),
             (ember(0.4, 0.2, 1.6), 4, "5.00 4.00 5.00", "0.00 2.00 0.00"),
             (smoke(s(2.5), s(7), 3.5), 2, "2.00 1.00 2.00", "0.00 1.00 0.00"),
             (lite(20.0, 0.6), 1, "0.00 2.00 0.00", "0.00 5.00 0.00")]
    elif stage == "d":
        L = [(flash(s(8), s(16), 0.3), 1, "0.00 0.00 0.00", None),
             (core("cr_xpl_core.dds", s(4), s(13), 1.1), 1, "0.00 1.00 0.00", "0.00 2.00 0.00"),
             (debris(0.8, 3.0), 2, "6.00 6.00 6.00", "0.00 3.00 0.00"),
             (ember(0.4, 0.2, 1.6), 2, "5.00 4.00 5.00", "0.00 2.00 0.00"),
             (smoke(s(3), s(8), 3.5), 2, "2.00 1.00 2.00", "0.00 1.00 0.00"),
             (lite(24.0, 0.7), 1, "0.00 2.00 0.00", "0.00 5.00 0.00")]
    elif stage == "s":
        L = [(debris(0.5, 2.0), 2, "3.00 3.00 3.00", "0.00 1.00 0.00"),
             (smoke(s(0.8), s(2.2), 1.6), 1, "1.00 0.60 1.00", "0.00 0.50 0.00"),
             (flash(s(1.6), s(3.2), 0.18), 1, "0.00 0.00 0.00", None)]
    else:  # snipe: no fireball
        shard = layer("Shard", "sim_ember", "draw_twirl", "cr_xpl_glint.dds", ADD, 0.8,
                      "215 235 255 255", "120 160 255 0", 0.25, 0.10, 10.0)
        mist = layer("Mist", "sim_smoke", "draw_twirl", "cr_xpl_smoke.dds", ALPHA, 1.2,
                     "110 10 10 190", "60 5 5 0", 0.6, 1.6, 2.0)
        spark = layer("Spark", "sim_ember", "draw_twirl", sparktex, ADD, 0.6,
                      f"{sc0} 255", f"{sc1} 0", 0.15, 0.06, 8.0)
        L = [(shard, 4, "4.00 3.50 4.00", "0.00 1.50 0.00"),
             (mist, 1, "0.60 0.50 0.60", "0.00 0.40 0.00"),
             (spark, 1, "1.50 1.20 1.50", "0.00 0.60 0.00")]

    names = [re.match(r"\[(\w+)\]", t).group(1) for t, *_ in L]
    total = sum(c for _, c, *_ in L)
    lights = sum(1 for n in names if n == "Light")
    assert lights <= (1 if stage in "id" else 0), root
    _, _, stock, extra = STAGES[stage]
    stock_total = sum(int(x) for x in re.findall(r"(?im)^\s*particleCount\d+\s*=\s*(\d+)", stock_text(stock)))
    assert total <= stock_total + extra, (root, total, stock_total)

    out = [f"// {'=' * 60}", f"// CR {f['title']} death explosion, {STAGES[stage][0]} stage ({root})",
           f"// Look: {f['look']}.",
           f"// Budget: {total} particles (stock {stock} is {stock_total}"
           + (f" + {extra} allowed" if extra else "") + ")"
           + (", one light" if lights else "") + f". Gameplay fields copied from {stock}.",
           f"// {'=' * 60}", "", "[ExplosionClass]"]
    out += stock_gameplay(stock)
    out += ["", f"particleTypes = {len(L)}"]
    for i, (text, count, veloc, bias) in enumerate(L, 1):
        out += ["", f'particleClass{i} = "{root}.{names[i - 1]}"', f"particleCount{i} = {count}",
                f'particleVeloc{i} = "{veloc}"']
        if bias:
            out.append(f'particleBias{i} = "{bias}"')
    out.append("")
    body = "\n".join(out) + "\n" + "\n".join(t for t, *_ in L)
    write(ODF / f"{root}.odf", body)
    return root, total, stock_total


# ----------------------------------------------------------- craft wiring
PREFIX = {"av": "nsdf", "sv": "cca", "bv": "bdog", "cv": "cra"}
BEGIN, END = "// CR DEATH FX BEGIN", "// CR DEATH FX END"


def section_span(text, name):
    m = re.search(r"(?im)^[ \t]*\[" + name + r"\][^\n]*\n", text)
    if not m:
        return None
    nxt = re.search(r"(?m)^[ \t]*\[", text[m.end():])
    return m.end(), m.end() + nxt.start() if nxt else len(text)


def insert_block(text, section, keys, comment):
    """Append a marker block at the end of [section]; returns (text, skipped_keys)."""
    start, end = section_span(text, section)
    body = text[start:end]
    skipped = [k for k, _ in keys if re.search(r"(?im)^[ \t]*" + k + r"[ \t]*=", body)]
    keys = [(k, v) for k, v in keys if k not in skipped]
    if not keys:
        return text, skipped
    stripped = body.rstrip("\n")
    trail = body[len(stripped):] or "\n"
    block = "\n".join([BEGIN, comment] + [f'{k} = "{v}"' for k, v in keys] + [END])
    return text[:start] + stripped + ("\n" if stripped else "") + block + trail + text[end:], skipped


def strip_blocks(text):
    while BEGIN in text:
        a = text.index(BEGIN)
        b = text.index(END, a) + len(END) + 1
        text = text[:a] + text[b:]
    return text


def wire_crafts():
    done, notes = [], []
    for path in sorted(ODF.glob("*.odf")):
        key = PREFIX.get(path.name[:2].lower())
        if not key:
            continue
        raw = path.read_bytes().decode("latin-1")
        nl = "\r\n" if "\r\n" in raw else "\n"
        text = raw.replace("\r\n", "\n")
        if not re.search(r"(?im)^[ \t]*\[CraftClass\][^\n]*\n", text):
            continue
        text = strip_blocks(text)
        title = FACTIONS[key]["title"]
        text, sk = insert_block(
            text, "CraftClass",
            [("xplSnipe", f"xd{key}p"), ("xplSecondary", f"xd{key}s"), ("xplDetonate", f"xd{key}d")],
            f"// {title} death explosions (ODF/xd{key}s, xd{key}d, xd{key}p)")
        notes += [f"{path.name}: skipped existing {k}" for k in sk]
        if section_span(text, "GameObjectClass"):
            text, sk = insert_block(text, "GameObjectClass", [("explosionName", f"xd{key}i")],
                                    f"// {title} initial death blast (ODF/xd{key}i)")
            notes += [f"{path.name}: skipped existing {k}" for k in sk]
        else:
            notes.append(f"{path.name}: no [GameObjectClass], explosionName not set")
        path.write_bytes(text.replace("\n", nl).encode("latin-1"))
        done.append(path.name)
    return done, notes


if __name__ == "__main__":
    for fac in FACTIONS:
        print(fac, " ".join(f"{st}={t}/{b}" for st in STAGES for _, t, b in [build(fac, st)]))
    crafts, notes = wire_crafts()
    print(len(crafts), "craft ODFs wired")
    for p, fac in PREFIX.items():
        print(fac, sum(1 for c in crafts if c.lower().startswith(p)))
    for n in notes:
        print("NOTE", n)
