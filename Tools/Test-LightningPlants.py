#!/usr/bin/env python3
"""Static checks for the L-Power fin spin and lightning-bolts shader.

SDF (Assets/ModelFixes/ablpow.sdf and bblpow.sdf): ANIM element 4 exists (PowerPlant plays element 4), loops
forever, runs one revolution per 8 s, first and last pose match, and the two fins
(alt11tpb, alt11tpc) have a rotation key on every frame, turn exactly 360 degrees in even
steps about the vertical axis, and are the only parts whose rotation changes.

Material: every program the material names exists in cr_lightarc.program, every unified
default_params entry names a constant that every HLSL delegate keeps (fxc, skipped with a
note when no Windows SDK is present), and the bolts submesh material is named in both meshes.

  python Tools/Test-LightningPlants.py
"""
import glob
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bzmodellibs  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXES = os.path.join(ROOT, "Assets", "ModelFixes")
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print("FAIL " + msg)


# ------------------------------------------------------------------ SDF
def read_anim(path):
    """(sequences, parts, rotation keys) through the Modding Toolbox's legacy.read_sdf (read
    only; CI fetches the toolbox at a pinned commit, see campaign-validation.yml)."""
    model = bzmodellibs.legacy.read_sdf(path)
    seqs = [(q.index, q.start, q.length, q.loop, q.speed) for q in model.sequences]
    parts, rots = [], []
    for t in model.tracks:
        keys = sorted((fr, *q) for fr, q in t.rotations)
        parts.append((t.name, len(rots), len(keys), 0, len(t.positions)))
        rots += keys
    return seqs, parts, rots


def qdot(a, b):
    return sum(x * y for x, y in zip(a, b))


def qangle(a, b):
    """Rotation angle between two stored quaternions (sign-insensitive), radians. Uses the
    chord (acos is ill-conditioned near 1 for float32 keys)."""
    sign = 1.0 if qdot(a, b) >= 0 else -1.0
    chord = math.sqrt(sum((x - sign * y) ** 2 for x, y in zip(a, b)))
    return 4.0 * math.asin(min(1.0, chord / 2.0))


def test_sdf(name):
    seqs, parts, rots = read_anim(os.path.join(FIXES, name + ".sdf"))
    check(len(seqs) >= 5, "ANIM needs elements 0..4 (found %d)" % len(seqs))
    if len(seqs) < 5:
        return
    idx, start, length, loop, speed = seqs[4]
    check(idx == 4, "sequence array position 4 has index %d" % idx)
    check(loop < 1, "element 4 must loop forever (loop %d)" % loop)
    check(start == 0 and length > 1, "element 4 start/length %d/%d" % (start, length))
    frames = length - 1  # the engine wraps at start + length - 1
    check(abs(frames / speed - 8.0) < 1e-6, "element 4 period is %.3f s, not 8 s" % (frames / speed))
    by_name = {p[0]: p for p in parts}
    for fin in ("alt11tpb", "alt11tpc"):
        check(fin in by_name, fin + " has no ANIM record")
        if fin not in by_name:
            continue
        _, r0, rn, p0, pn = by_name[fin]
        keys = sorted(rots[r0:r0 + rn])
        check([k[0] for k in keys] == list(range(frames + 1)),
              "%s must key rotation on every frame 0..%d (has %d keys)" % (fin, frames, rn))
        quats = [k[1:] for k in keys]
        check(qangle(quats[0], quats[-1]) < 1e-4, fin + ": first and last pose differ")
        steps = [qangle(a, b) for a, b in zip(quats, quats[1:])]
        total = math.degrees(sum(steps))
        check(abs(total - 360.0) < 0.01, "%s turns %.4f degrees over the loop, not 360" % (fin, total))
        check(max(steps) - min(steps) < 1e-4, fin + ": uneven spin steps")
        # continuous half-angle path: consecutive keys must not flip sign (nlerp-safe)
        check(all(qdot(a, b) > 0 for a, b in zip(quats, quats[1:])), fin + ": key hemisphere flips")
        # axis: R_key(t) * R_key(0)^-1 must be a pure rotation about Y in the stored convention
        w0, x0, y0, z0 = quats[0]
        for q in quats[1::17]:
            # relative = q * conj(q0) (stored quaternions are conjugated Hamilton ones)
            w, x, y, z = q
            rw = w * w0 + x * x0 + y * y0 + z * z0
            rx = -w * x0 + x * w0 - y * z0 + z * y0
            ry = -w * y0 + y * w0 - z * x0 + x * z0
            rz = -w * z0 + z * w0 - x * y0 + y * x0
            check(abs(rx) < 1e-4 and abs(rz) < 1e-4, fin + ": spin is not about the vertical axis")
        check(pn >= 2, fin + " needs position keys like every stock moving part")
    for name, r0, rn, p0, pn in parts:
        if name in ("alt11tpb", "alt11tpc"):
            continue
        ks = rots[r0:r0 + rn]
        check(all(qangle(ks[0][1:], k[1:]) < 1e-4 for k in ks), name + " rotation must stay constant")


# ------------------------------------------------------------------ shader / material
def blocks(text, kind):
    text = re.sub(r"//[^\n]*", "", text)
    out = {}
    for m in re.finditer(r"(?m)^%s\s+(\S+)([^\n{]*)\s*\{" % kind, text):
        depth, j = 0, m.end() - 1
        while j < len(text):
            depth += text[j] == "{"
            depth -= text[j] == "}"
            if depth == 0:
                break
            j += 1
        out[m.group(1)] = (m.group(2).strip(), text[m.end():j])
    return out


def field(body, key):
    m = re.search(r"(?m)^\s*%s\s+(\S+)" % key, body)
    return m.group(1) if m else None


def find_fxc():
    hit = shutil.which("fxc.exe") or shutil.which("fxc")
    if hit:
        return hit
    kits = os.path.join(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"), "Windows Kits", "10", "bin")
    hits = sorted(glob.glob(os.path.join(kits, "*", "x64", "fxc.exe")))
    return hits[-1] if hits else None


def test_shader():
    prog_text = open(os.path.join(ROOT, "Shaders", "cr_lightarc.program")).read()
    mat_text = open(os.path.join(ROOT, "Materials", "cr_lightarc.material")).read()
    programs = {}
    for kind in ("vertex_program", "fragment_program"):
        for name, (lang, body) in blocks(prog_text, kind).items():
            programs[name] = (kind, lang, body)
    # program names referenced by the material and by unified delegates all exist
    for ref in re.findall(r"(?:vertex|fragment)_program_ref\s+(\S+)", mat_text):
        if ref.startswith("CR_LightArc"):
            check(ref in programs, "material names missing program " + ref)
    for name, (kind, lang, body) in programs.items():
        for d in re.findall(r"(?m)^\s*delegate\s+(\S+)", body):
            check(d in programs, "%s delegates to missing %s" % (name, d))
        src = field(body, "source")
        if src:
            check(os.path.exists(os.path.join(ROOT, "Shaders", src)), "%s source %s missing" % (name, src))
    check("scheme glow" in mat_text, "material needs a glow-scheme technique that draws nothing")
    check(len(re.findall(r"(?m)^\s*technique", mat_text)) >= 3, "material needs bolts, glow and null techniques")
    # the shipped program name is versioned (microcode cache serves stale code by name)
    check(re.search(r"CR_LightArc_v\d+_", prog_text) is not None, "program names must carry a version suffix")

    # meshes carry the bolts material as a second submesh
    for mesh, mat in (("ablpow.mesh", b"CR_LightArc_NSDF"), ("bblpow.mesh", b"CR_LightArc_BDog")):
        data = open(os.path.join(FIXES, mesh), "rb").read()
        check(mat in data, "%s does not use %s" % (mesh, mat.decode()))
        check(mat.decode() in mat_text, "%s not defined in cr_lightarc.material" % mat.decode())

    fxc = find_fxc()
    if not fxc:
        print("note: fxc not found, skipping the compile and constant checks")
        return
    work = tempfile.mkdtemp(prefix="cr_lightarc_")
    kept = {}
    try:
        for name, (kind, lang, body) in programs.items():
            if lang != "hlsl":
                continue
            target, entry = field(body, "target"), field(body, "entry_point")
            defs = field(body, "preprocessor_defines")
            lst = os.path.join(work, name + ".asm")
            cmd = [fxc, "/nologo", "/WX", "/T", target, "/E", entry, "/Fc", lst, "/Fo", os.path.join(work, name + ".o")]
            if defs:
                for d in defs.split(","):
                    cmd += ["/D", d]
            cmd.append(os.path.join(ROOT, "Shaders", field(body, "source")))
            r = subprocess.run(cmd, capture_output=True, text=True)
            check(r.returncode == 0, "%s does not compile for %s:\n%s%s" % (name, target, r.stdout, r.stderr))
            if r.returncode:
                continue
            asm = open(lst).read()
            names = set()
            if target.endswith("_4_0"):
                for m in re.finditer(r"(?m)^//\s+(?:float|float[234]|float4x4|int)\s+(\w+)(?:\[\d+\])?;.*$", asm):
                    if "[unused]" not in m.group(0):
                        names.add(m.group(1))
            else:
                for m in re.finditer(r"(?m)^//\s+(\w+)\s+[cs]\d+\s+\d+\s*$", asm):
                    names.add(m.group(1))
            kept[name] = names
            print("compiled %-34s %s (%d constants)" % (name, target, len(names)))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    for name, (kind, lang, body) in programs.items():
        if "unified" not in lang:
            continue
        params = re.findall(r"(?m)^\s*param_named(?:_auto)?\s+(\w+)", body)
        for d in re.findall(r"(?m)^\s*delegate\s+(\S+)", body):
            if d in kept:
                for p in params:
                    check(p in kept[d], "%s param %s is not kept by %s (Ogre would drop the technique)" % (name, p, d))


if __name__ == "__main__":
    if not bzmodellibs.require_or_skip("Test-LightningPlants"):
        sys.exit(0)
    test_sdf("ablpow")
    test_sdf("bblpow")
    test_shader()
    if failures:
        print("\n%d failure(s)" % len(failures))
        sys.exit(1)
    print("Lightning plant checks passed.")
