"""Cockpit glass: adds a one-sided glass submesh to each craft's cockpit mesh (Campaign Reimagined).

Ported from the ISDF Chronicles tools/cockpitglass.py. CRWetGlass.lua draws windshield rain, dirt and
cracks on this submesh when EXU can move one sub-entity of the cockpit entity into its own render queue
group (exu.SetSubEntityRenderQueueGroup on exu.animation.TargetCockpit). The cockpit entity draws in
group 10, before terrain, and writes depth; the glass draws in group 90 with depth_check on and
depth_write off, so the frame, struts and dash hide it and it shows only through the window openings.
It is skinned to the cockpit, so it follows every cockpit bone.

Sources (CR overrides win, like the game's resource groups):
  meshes / skeletons  Assets/** (Assets/ModelFixes) over <game>/BZ_ASSETS/common/models/**
  craft ODFs          CR ODF/ over <game>/StockODFFiles (every ODF with a craft classLabel; mesh base =
                      baseName, else the ODF name)
  materials           CR Materials/ over <game>/BZ_ASSETS/pc/materials/** and BZ_ASSETS_CORE (used only to
                      recognise modelled glass submeshes)
Output: Assets/ModelFixes/<same leaf name as the source>. A unit the tool skips or fails gets no file.

How the glass is made (per mesh):
  1. The cockpit is what the first-person view draws, chosen as the engine does (0x0067F480): the fixed
     table below (avwalk -> avwalk_c ...); else <base>_cockpit.mesh; else the craft's own mesh when its
     skeleton has a '2' bone (bone name char[3] == '2'). In a craft's own mesh the cockpit is the
     triangles on '2' bones; a separate cockpit mesh is used whole if it has no '2' bones. The eye is the
     pov bone (name[5:8] == 'pov').
  2. Rays from the eye over a view-direction grid (yaw +-YAW, pitch PITCH0..PITCH1, FINE degrees) find the
     nearest FRONT-facing cockpit triangle (the fp view culls back faces, so a back face does not block
     the view). Directions with no hit within RMAX are window openings. Modelled glass submeshes (by
     material name or a translucent, depth_write-off material) never block.
  3. A depth field: MARGIN beyond the hit where the cockpit is, a Laplace fill of the rim depths across
     each opening (capped at CAP), so the glass spans every opening roughly in the plane of its frame and
     sits just OUTSIDE the frame.
  4. The glass is a COARSE-degree grid over the openings, dilated by one fine cell so its edge tucks
     behind the frame. UVs come from the view direction (u = 0.5 + yaw / U_SPAN, v = 0.5 - pitch / V_SPAN,
     degrees), so the rain and damage textures look the same whatever the glass depth.
  5. The submesh (material CRWX_CockpitGlass, a no-op that CRWetGlass.lua swaps on the cockpit entity
     only) is bound with weight 1 to one cockpit bone (a '2' shell parented to the eye, else the eye's
     nearest '2' ancestor, else *21coc / *21bda, else the '2' bone the eye sees most) and appended to the mesh; every other chunk is copied
     byte for byte (edge lists are dropped; Ogre rebuilds them on demand).

  python Tools/cockpitglass.py                      # every craft with a cockpit -> Assets/ModelFixes
  python Tools/cockpitglass.py avtank svfigh --render C:/.../renders/glass
  python Tools/cockpitglass.py --materials          # writes Materials/crwx_cockpitglass.material
  python Tools/cockpitglass.py --dry-run            # fit and report, write nothing
  python Tools/cockpitglass.py --game <BZR install> --out <dir> ...

Run again at any time: an existing CRWX_CockpitGlass submesh is replaced. A full run writes
Tools/cockpitglass_report.txt with the per-unit fit numbers.
"""
import argparse, os, re, struct, sys, time
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ogrebin

MOD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))     # the CR repository root
GAME = os.environ.get("BZR_GAME_DIR", r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux")
GLASS_MATERIAL = "CRWX_CockpitGlass"
CRAFT_CLASSES = {"wingman", "hover", "turrettank", "walker", "tug", "howitzer", "apc", "scavenger", "minelayer",
                 "recycler", "factory", "constructionrig", "sav", "turret"}
GLASS_NAME = re.compile(r"glass|canopy|window|windshield|windscreen|visor|cpglass", re.I)

# First-person meshes the engine picks from a fixed table before it looks for <base>_cockpit (0x008ED2E8).
FP_TABLE = {"avartl": "avartl_c", "bvartl": "bvartl_c", "svartl": "svartl_c", "avturr": "avturr_c",
            "svturr": "svturr_c", "bvturr": "bvturr_c", "avwalk": "avwalk_c", "svwalk": "svwalk_c",
            "cvwalk": "cvwalk_c", "bvwalk": "bvwalk_c", "aspilo": "aspilo_fp", "sspilo": "sspilo_fp",
            "bspilo": "bspilo_fp", "bsheav": "bsheav_fp", "cspilo": "cspilo_fp"}

YAW, PITCH0, PITCH1 = 120.0, -60.0, 84.0   # degrees around the eye's forward axis
FINE, COARSE = 2.0, 6.0                    # ray grid and glass grid steps (COARSE = k * FINE)
RMAX = 15.0                                 # metres; farther cockpit hits count as open
NEAR = 0.05                                 # metres; ignore hits closer than this
MARGIN = 0.04                               # glass sits this far beyond the cockpit surface
CAP, FLOOR = 3.0, 0.3                       # glass depth limits across openings
U_SPAN, V_SPAN = 96.0, 64.0                 # degrees per UV unit (16:9 at a 64 deg vertical FOV)


# ---------------------------------------------------------------- sources

class Sources:
    """Resolves meshes, skeletons, ODFs and material scripts: CR first, then the stock game."""

    def __init__(self, game=GAME, cr=MOD):
        self.game, self.cr = game, cr
        self.models = {}                      # lower leaf -> (path, "cr" | "stock")
        for root in (os.path.join(game, "BZ_ASSETS", "common", "models"), os.path.join(game, "BZ_ASSETS_CORE")):
            self._index(root, "stock")
        self._index(os.path.join(cr, "Assets"), "cr")
        self.odf_dirs = [os.path.join(cr, "ODF"), os.path.join(game, "StockODFFiles")]
        self.material_dirs = [os.path.join(game, "BZ_ASSETS", "pc", "materials"),
                              os.path.join(game, "BZ_ASSETS_CORE", "common", "BZ_MATERIALS"),
                              os.path.join(cr, "Materials")]            # later directories win

    def _index(self, root, tag):
        for dp, _dn, fn in os.walk(root):
            for f in fn:
                if f.lower().endswith((".mesh", ".skeleton")):
                    self.models[f.lower()] = (os.path.join(dp, f), tag)

    def model(self, name):
        """(path, origin) of a mesh or skeleton by leaf name, or (None, None)."""
        return self.models.get(name.lower(), (None, None))

    def odfs(self):
        """{odf name: path} with CR overriding stock."""
        out = {}
        for d in reversed(self.odf_dirs):
            if os.path.isdir(d):
                for f in os.listdir(d):
                    if f.lower().endswith(".odf"):
                        out[os.path.splitext(f)[0].lower()] = os.path.join(d, f)
        return out


def odf_units(src):
    """{mesh base: [odf names]} for craft ODFs (classLabel in CRAFT_CLASSES)."""
    units = {}
    for odf, path in sorted(src.odfs().items()):
        text = open(path, errors="replace").read()
        m = re.search(r'(?im)^\s*classLabel\s*=\s*"?([A-Za-z0-9_]+)', text)
        if not m or m.group(1).lower() not in CRAFT_CLASSES:
            continue
        b = re.search(r'(?im)^\s*baseName\s*=\s*"?([A-Za-z0-9_]+)', text)
        base = (b.group(1) if b else odf).lower()
        units.setdefault(base, []).append(odf)
    return units


def cockpit_mesh(src, base):
    """(mesh path, kind, origin) of the model the first-person view draws, or (None, reason, None).
    The engine tries its fixed table, then <base>_cockpit, then the craft's own mesh (0x0067F480)."""
    for name, kind in ((FP_TABLE.get(base), "table"), (base + "_cockpit", "separate")):
        if name:
            p, origin = src.model(name + ".mesh")
            if p:
                return p, kind, origin
    p, origin = src.model(base + ".mesh")
    if not p:
        return None, "no mesh in CR or stock", None
    return p, "in-mesh", origin


def is_cockpit_bone(name):
    return len(name) > 3 and name[3] == "2"


def is_pov_bone(name):
    n = name.lower()
    return n[5:8] == "pov" or n.endswith("pov")


# ---------------------------------------------------------------- materials

def material_scripts(src):
    """{material name lower: script text} for every material script (CR over stock)."""
    out = {}
    for d in src.material_dirs:
        for dp, _dn, fn in os.walk(d):
            for f in fn:
                if not f.lower().endswith(".material"):
                    continue
                try:
                    text = open(os.path.join(dp, f), errors="replace").read()
                except OSError:
                    continue
                for m in re.finditer(r"(?m)^\s*material\s+([^\s:{]+)", text):
                    start = m.end()
                    depth, i, opened = 0, start, False
                    while i < len(text):
                        if text[i] == "{":
                            depth += 1; opened = True
                        elif text[i] == "}":
                            depth -= 1
                            if opened and depth == 0:
                                break
                        i += 1
                    out[m.group(1).lower()] = text[start:i]
    return out


def is_glass_material(name, scripts):
    if name == GLASS_MATERIAL or name.startswith(GLASS_MATERIAL + "_"):
        return True
    if GLASS_NAME.search(name):
        return True
    body = scripts.get(name.lower(), "")
    return bool(re.search(r"scene_blend\s+(alpha_blend|add)", body) and re.search(r"depth_write\s+off", body))


# ---------------------------------------------------------------- ray casting

def ray_grid(step):
    yaws = np.arange(-YAW, YAW + 1e-6, step)
    pitches = np.arange(PITCH0, PITCH1 + 1e-6, step)
    Y, P = np.meshgrid(np.radians(yaws), np.radians(pitches))      # [pitch, yaw]
    D = np.stack([np.cos(P) * np.sin(Y), np.sin(P), np.cos(P) * np.cos(Y)], -1)
    return yaws, pitches, D


def cast(origin, dirs, v0, v1, v2, front_only=True, chunk=48):
    """Nearest hit distance per ray (inf = none) and the triangle index (-1)."""
    e1, e2 = (v1 - v0).astype(np.float32), (v2 - v0).astype(np.float32)
    s = (origin - v0).astype(np.float32)
    nrm = np.cross(e1, e2)
    flat = dirs.reshape(-1, 3).astype(np.float32)
    best = np.full(len(flat), np.inf, np.float32)
    which = np.full(len(flat), -1, np.int64)
    q = np.cross(s, e1)                                   # (M,3), ray independent
    for a in range(0, len(flat), chunk):
        d = flat[a:a + chunk]                             # (n,3)
        p = np.cross(d[:, None, :], e2[None, :, :])        # (n,M,3)
        det = np.einsum("nmk,mk->nm", p, e1)
        with np.errstate(divide="ignore", invalid="ignore"):
            inv = 1.0 / det
            u = np.einsum("nmk,mk->nm", p, s) * inv
            v = np.einsum("nk,mk->nm", d, q) * inv
            t = np.einsum("mk,mk->m", e2, q)[None, :] * inv
        with np.errstate(invalid="ignore"):
            ok = (np.abs(det) > 1e-9) & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > NEAR) & (t < RMAX)
        if front_only:
            ok &= (d @ nrm.T) < 0
        t = np.where(ok, t, np.inf)
        k = np.argmin(t, 1)
        tv = t[np.arange(len(d)), k]
        best[a:a + chunk] = tv
        which[a:a + chunk] = np.where(np.isfinite(tv), k, -1)
    return best.reshape(dirs.shape[:-1]), which.reshape(dirs.shape[:-1])


def laplace_fill(field, known, iters=600):
    """Fill the unknown cells of a 2-D field by Jacobi relaxation (Neumann edges)."""
    f = field.copy()
    if known.any():
        f[~known] = np.median(field[known])
    else:
        f[:] = CAP * 0.6
        return f
    for _ in range(iters):
        p = np.pad(f, 1, mode="edge")
        avg = 0.25 * (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:])
        f = np.where(known, f, avg)
    return f


# ---------------------------------------------------------------- glass

class Fit:
    pass


def make_glass(mesh, skel, scripts, force_whole=False):
    """Build the glass for one cockpit mesh. Returns a Fit (positions, normals, uvs, tris,
    bone, stats) or raises ValueError with the reason."""
    pov = [h for h, n in skel.names.items() if is_pov_bone(n)]
    if not pov:
        raise ValueError("no pov bone")
    pov = min(pov, key=lambda h: (skel.names[h].lower()[5:8] != "pov", h))
    eye, R = skel.world[pov]

    cockpit_bones = {h for h, n in skel.names.items() if is_cockpit_bone(n)}
    tris, owners, glass_tris, glass_geo = [], [], [], []
    for si, sm in enumerate(mesh.submeshes):
        if sm["positions"] is None or len(sm["tris"]) == 0:
            continue
        P = sm["positions"]
        T = sm["tris"][(sm["tris"] < len(P)).all(1)]
        if is_glass_material(sm["material"], scripts):
            if sm["material"] != GLASS_MATERIAL:
                glass_tris.append((sm["material"], len(T)))
                dom = sm["bones"]
                if force_whole or not cockpit_bones:
                    gk = np.ones(len(T), bool)
                else:
                    gk = np.isin(dom[T], list(cockpit_bones)).all(1)
                if gk.any():
                    glass_geo.append(P[T[gk]])
            continue
        dom = sm["bones"]
        if force_whole or not cockpit_bones:
            keep = np.ones(len(T), bool)
        else:
            keep = np.isin(dom[T], list(cockpit_bones)).all(1)
        if keep.any():
            tris.append(P[T[keep]])
            owners.append(dom[T[keep]][:, 0])
    if not tris:
        raise ValueError("no cockpit triangles ('2' bones)")
    tri = np.concatenate(tris)
    own = np.concatenate(owners)

    # Keep what can matter: within RMAX of the eye.
    near = (np.linalg.norm(tri - eye, axis=2).min(1) < RMAX)
    tri, own = tri[near], own[near]
    yaws, pitches, D = ray_grid(FINE)
    Dm = D @ R.T                                           # eye frame -> mesh frame
    t, k = cast(eye, Dm, tri[:, 0], tri[:, 1], tri[:, 2])
    tb, _ = cast(eye, Dm, tri[:, 0], tri[:, 1], tri[:, 2], front_only=False)
    hit = np.isfinite(t)
    if not hit.any():
        raise ValueError("eye sees no front-facing cockpit surface")

    # Modelled glass (canopy) in an opening: put ours just inside it (never beyond CAP),
    # so a canopy that writes depth can never hide it and the layers sit on the real glass.
    on_glass = np.zeros_like(hit)
    tg = np.full(t.shape, np.inf)
    if glass_geo:
        g = np.concatenate(glass_geo)
        g = g[np.linalg.norm(g - eye, axis=2).min(1) < RMAX]
        if len(g):
            tg, _ = cast(eye, Dm, g[:, 0], g[:, 1], g[:, 2], front_only=False)
            on_glass = ~hit & np.isfinite(tg)

    # Depth field: just beyond the cockpit where it is, on the canopy where there is
    # one, filled across the rest of each opening.
    known = hit | on_glass
    field = np.where(hit, t + MARGIN, np.where(on_glass, np.clip(tg - 0.01, FLOOR, CAP), 0.0))
    filled = laplace_fill(field, known)
    filled = np.where(known, filled, np.clip(filled, FLOOR, CAP))
    # A glass vertex takes the deepest value around it (one coarse step each way), so
    # the flat glass between two vertices stays behind every cockpit surface it spans.
    step = int(round(COARSE / FINE))
    deep = filled.copy()
    pad = np.pad(filled, step, mode="edge")
    for dr in range(-step, step + 1):
        for dc in range(-step, step + 1):
            deep = np.maximum(deep, pad[step + dr:step + dr + filled.shape[0], step + dc:step + dc + filled.shape[1]])
    # ...but never behind a canopy that sits in front of it.
    deep = np.where(on_glass, np.minimum(deep, np.clip(tg - 0.01, FLOOR, CAP)), deep)

    # Glass cells: openings dilated by one fine cell.
    opening = ~hit
    dil = opening.copy()
    dil[1:, :] |= opening[:-1, :]; dil[:-1, :] |= opening[1:, :]
    dil[:, 1:] |= opening[:, :-1]; dil[:, :-1] |= opening[:, 1:]

    rows = np.arange(0, len(pitches), step)
    cols = np.arange(0, len(yaws), step)
    if rows[-1] != len(pitches) - 1:
        rows = np.append(rows, len(pitches) - 1)
    if cols[-1] != len(yaws) - 1:
        cols = np.append(cols, len(yaws) - 1)
    vid = {}
    pos, nrm, uv, faces = [], [], [], []

    def vertex(r, c):
        key = (r, c)
        if key not in vid:
            d = Dm[r, c]
            vid[key] = len(pos)
            pos.append(eye + d * deep[r, c])
            nrm.append(-d)
            uv.append((0.5 + yaws[c] / U_SPAN, 0.5 - pitches[r] / V_SPAN))
        return vid[key]

    for i in range(len(rows) - 1):
        for j in range(len(cols) - 1):
            r0, r1, c0, c1 = rows[i], rows[i + 1], cols[j], cols[j + 1]
            if not dil[r0:r1 + 1, c0:c1 + 1].any():
                continue
            a, b, c, d = vertex(r0, c0), vertex(r0, c1), vertex(r1, c1), vertex(r1, c0)
            # Facing the eye: counter-clockwise as the eye sees it (x right, y up).
            faces.append((a, c, b)); faces.append((a, d, c))
    if not faces:
        raise ValueError("no window openings")

    # The bone the glass follows: a '2' shell parented to the eye (svturr_c's 21tx1 and the
    # walkers' 21hed are locked to the view that way); else the eye's nearest '2' ancestor
    # (a turret's 21ty1: the glass turns with the dash and the eye); else the body-fixed
    # cockpit bone (*21coc, then *21bda: never a VDF-driven wing or foot); else the '2' bone
    # the eye sees most; else the pov's parent.
    bone = None
    shells = sorted(c for c in cockpit_bones if skel.parent.get(c) == pov)
    if len(shells) == 1:
        bone = int(shells[0])
    h = pov
    while bone is None and h in skel.parent:
        h = skel.parent[h]
        if h in cockpit_bones:
            bone = int(h)
            break
    if bone is None:
        for suffix in ("coc", "bda"):
            named = sorted(c for c in cockpit_bones if skel.names[c].lower()[5:8] == suffix)
            if named:
                bone = int(named[0])
                break
    if bone is None:
        seen = own[k[hit]]
        seen = seen[np.isin(seen, list(cockpit_bones))] if cockpit_bones else seen
        if len(seen):
            vals, cnt = np.unique(seen, return_counts=True)
            bone = int(vals[np.argmax(cnt)])
        else:
            bone = int(skel.parent.get(pov, pov))

    f = Fit()
    f.positions = np.array(pos); f.normals = np.array(nrm); f.uvs = np.array(uv)
    f.tris = np.array(faces, dtype=np.int64)
    f.bone, f.bone_name = bone, skel.names[bone]
    f.eye, f.R, f.pov = eye, R, skel.names[pov]
    f.cockpit = tri
    f.open_frac = float(opening.mean())
    f.back_only = float((np.isfinite(tb) & ~hit).mean())
    f.depth = (float(filled[opening].min()) if opening.any() else 0.0,
               float(filled[opening].max()) if opening.any() else 0.0)
    f.glass_materials = glass_tris
    f.hit_t, f.grid = t, (yaws, pitches)
    return f


# ---------------------------------------------------------------- previews

def raster(tris, colors, w, h, project, alpha=None, zbuf=None, img=None, ztest_only=False):
    """Tiny z-buffer rasteriser: tris (N,3,3) in camera space (x right, y up, z forward)."""
    if img is None:
        img = np.zeros((h, w, 3), np.float32) + np.array([0.53, 0.62, 0.72], np.float32)
    if zbuf is None:
        zbuf = np.full((h, w), np.inf, np.float32)
    for n in range(len(tris)):
        p = tris[n]
        if (p[:, 2] < 0.02).any():
            continue
        xy = np.array([project(q) for q in p])
        x0, y0 = np.floor(xy.min(0)).astype(int)
        x1, y1 = np.ceil(xy.max(0)).astype(int)
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, w - 1), min(y1, h - 1)
        if x0 > x1 or y0 > y1:
            continue
        X, Y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, ay), (bx, by), (cx, cy) = xy
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        l0 = ((by - cy) * (X - cx) + (cx - bx) * (Y - cy)) / den
        l1 = ((cy - ay) * (X - cx) + (ax - cx) * (Y - cy)) / den
        l2 = 1 - l0 - l1
        inside = (l0 >= 0) & (l1 >= 0) & (l2 >= 0)
        if not inside.any():
            continue
        z = 1.0 / (l0 / p[0, 2] + l1 / p[1, 2] + l2 / p[2, 2])
        zb = zbuf[y0:y1 + 1, x0:x1 + 1]
        m = inside & (z < zb)
        if alpha is None:
            zb[m] = z[m]
            img[y0:y1 + 1, x0:x1 + 1][m] = colors[n]
        else:
            seg = img[y0:y1 + 1, x0:x1 + 1]
            seg[m] = seg[m] * (1 - alpha) + np.asarray(colors[n]) * alpha
    return img, zbuf


def shade(tris, light):
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
    k = 0.35 + 0.55 * np.abs(n @ light)
    return np.stack([k * 0.42, k * 0.40, k * 0.38], 1)


def render(fit, name, out_dir):
    from PIL import Image, ImageDraw
    os.makedirs(out_dir, exist_ok=True)
    W, H = 960, 600
    gt = fit.positions[fit.tris]
    # 1) eye view: cockpit (grey), glass where it is visible (cyan, hidden behind the frame)
    toE = lambda P: (P - fit.eye) @ fit.R
    ce, ge = toE(fit.cockpit), toE(gt)
    f = (W / 2) / np.tan(np.radians(55))
    proj = lambda q: (W / 2 + f * q[0] / q[2], H / 2 - f * q[1] / q[2])
    img, zb = raster(ce, shade(ce, np.array([0.3, 0.8, -0.5])), W, H, proj)
    gcol = np.tile([[0.2, 0.95, 1.0]], (len(ge), 1))
    img, _ = raster(ge, gcol, W, H, proj, alpha=0.45, zbuf=zb, img=img)
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    for tr in ge:
        if (tr[:, 2] > 0.02).all():
            pts = [proj(q) for q in tr]
            d.line(pts + [pts[0]], fill=(30, 120, 140), width=1)
    d.text((8, 8), f"{name}: eye view (110 deg h-fov) - glass cyan where visible", fill=(255, 255, 255))
    a = os.path.join(out_dir, f"{name}_eye.png"); im.save(a)
    # 2) outside 3/4 view: cockpit + glass (translucent), from front-right-above
    centre = fit.eye + fit.R @ np.array([0, 0, 1.0])
    span = np.percentile(np.linalg.norm(fit.cockpit.reshape(-1, 3) - centre, axis=1), 90) + 1.0
    fwd = fit.R @ np.array([-0.55, -0.45, -0.7]); fwd /= np.linalg.norm(fwd)
    up0 = fit.R @ np.array([0, 1.0, 0])
    right = np.cross(up0, fwd); right /= np.linalg.norm(right)
    up = np.cross(fwd, right)
    cam = centre - fwd * span * 2.6
    Rc = np.stack([right, up, fwd], 1)
    toC = lambda P: (P - cam) @ Rc
    cc, gc = toC(fit.cockpit), toC(gt)
    f2 = (W / 2) / np.tan(np.radians(24))
    proj2 = lambda q: (W / 2 + f2 * q[0] / q[2], H / 2 - f2 * q[1] / q[2])
    img, zb = raster(cc, shade(cc, fwd * -1 + up), W, H, proj2)
    img, _ = raster(gc, np.tile([[0.2, 0.9, 1.0]], (len(gc), 1)), W, H, proj2, alpha=0.5, zbuf=zb, img=img)
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    for tr in gc:
        pts = [proj2(q) for q in tr]
        d.line(pts + [pts[0]], fill=(20, 110, 130), width=1)
    e = proj2(toC(fit.eye[None])[0])
    d.ellipse([e[0] - 4, e[1] - 4, e[0] + 4, e[1] + 4], fill=(255, 60, 40))
    d.text((8, 8), f"{name}: outside view - cockpit grey, glass cyan, eye red", fill=(255, 255, 255))
    b = os.path.join(out_dir, f"{name}_outside.png"); im.save(b)
    return a, b


# ---------------------------------------------------------------- materials file

LAYER_TEX = {"wrap": "crwx_wetbeads.png", "clamp": "crwx_windcrack.png"}
MAX_WRAP, MAX_CLAMP = 7, 4


def material_text():
    """crwx_cockpitglass.material: the no-op default plus CRWX_CockpitGlass_W<a>C<b>, a
    pass per layer (a wrap passes, then b clamp passes) for CRWetGlass.lua to fill."""
    def pass_block(mode, sm4):
        prog = ("\t\t\tvertex_program_ref CRWX_FF_Lit1_vertex\n\t\t\t{\n\t\t\t}\n"
                "\t\t\tfragment_program_ref CRWX_FF_Mod_NoFog_fragment\n\t\t\t{\n\t\t\t}\n") if sm4 else ""
        return ("\t\tpass\n\t\t{\n" + prog +
                "\t\t\tlighting on\n\t\t\tambient 1 1 1\n\t\t\tdiffuse 0.45 0.45 0.45 0\n"
                "\t\t\tspecular 0 0 0 1\n\t\t\temissive 0.06 0.06 0.06\n"
                "\t\t\tscene_blend alpha_blend\n\t\t\tdepth_check on\n\t\t\tdepth_write off\n"
                "\t\t\tcull_hardware none\n\t\t\tcull_software none\n\t\t\tfog_override true\n"
                "\t\t\ttexture_unit\n\t\t\t{\n"
                f"\t\t\t\ttexture {LAYER_TEX[mode]}\n\t\t\t\ttex_address_mode {mode}\n"
                "\t\t\t\tfiltering trilinear\n\t\t\t}\n\t\t}\n")

    def noop(scheme, sm4):
        prog = ("\t\t\tvertex_program_ref CRWX_FF_Unlit1_vertex\n\t\t\t{\n\t\t\t}\n"
                "\t\t\tfragment_program_ref CRWX_FF_Mod_NoFog_fragment\n\t\t\t{\n\t\t\t}\n") if sm4 else ""
        return ("\ttechnique\n\t{\n" + (f"\t\tscheme {scheme}\n" if scheme else "") +
                "\t\tpass\n\t\t{\n" + prog +
                "\t\t\tlighting off\n\t\t\tcolour_write off\n\t\t\tdepth_check off\n\t\t\tdepth_write off\n"
                "\t\t\tfog_override true\n\t\t\ttexture_unit\n\t\t\t{\n"
                "\t\t\t\ttexture crwx_windcrack.png\n\t\t\t}\n\t\t}\n\t}\n")

    out = ["// Generated by Tools/cockpitglass.py --materials -- edit the generator, not this file.",
           "// Cockpit glass submesh materials (see Tools/cockpitglass.py and CRWetGlass.lua).",
           "// CRWX_CockpitGlass is what every glass submesh ships with: it draws nothing, so the",
           "// glass costs nothing in third person or without EXU. On the player's cockpit entity",
           "// CRWetGlass.lua swaps in CRWX_CockpitGlass_W<a>C<b> (a wrap layers then b clamp layers,",
           "// one pass each), points each pass at a layer texture and window, and fades it with the",
           "// pass diffuse alpha. Technique 0 = DX11 (CRWX_FF_* stand-ins), 1 = fixed function.",
           "// The glow scheme draws nothing, so rain never blooms.", ""]
    out.append(f"material {GLASS_MATERIAL}\n{{\n\treceive_shadows off\n" + noop(None, True) + noop(None, False)
               + noop("glow", True) + noop("glow", False) + "}\n")
    for a in range(MAX_WRAP + 1):
        for b in range(MAX_CLAMP + 1):
            if a + b == 0:
                continue
            modes = ["wrap"] * a + ["clamp"] * b
            body = f"material {GLASS_MATERIAL}_W{a}C{b}\n{{\n\treceive_shadows off\n"
            for sm4 in (True, False):
                body += "\ttechnique\n\t{\n" + "".join(pass_block(m, sm4) for m in modes) + "\t}\n"
            body += noop("glow", True) + noop("glow", False) + "}\n"
            out.append(body)
    return "\n".join(out)


# ---------------------------------------------------------------- main

def process(src, out, base, scripts, render_dir=None, dry=False):
    path, kind, origin = cockpit_mesh(src, base)
    if path is None:
        return {"base": base, "status": "skip", "why": kind}
    leaf = os.path.basename(path)
    try:
        mesh = ogrebin.Mesh(path)
    except (ValueError, OSError) as e:
        return {"base": base, "status": "fail", "why": str(e), "mesh": leaf}
    if not mesh.skeleton:
        return {"base": base, "status": "skip", "why": "mesh has no skeleton", "mesh": leaf}
    skel_path, _ = src.model(os.path.basename(mesh.skeleton))
    if not skel_path:
        return {"base": base, "status": "fail", "why": "skeleton %s missing" % mesh.skeleton, "mesh": leaf}
    try:
        skel = ogrebin.Skeleton(skel_path)
    except (ValueError, OSError, struct.error) as e:
        return {"base": base, "status": "fail", "why": "skeleton unreadable: %s" % e, "mesh": leaf}
    has2 = any(is_cockpit_bone(n) for n in skel.names.values())
    if kind == "in-mesh" and not has2:
        return {"base": base, "status": "skip", "why": "no cockpit ('2' bones, no _c/_cockpit mesh)", "mesh": leaf}
    try:
        fit = make_glass(mesh, skel, scripts, force_whole=(kind != "in-mesh" and not has2))
    except ValueError as e:
        return {"base": base, "status": "fail", "why": str(e), "mesh": leaf}
    res = {"base": base, "status": "ok", "mesh": leaf, "kind": kind, "origin": origin, "pov": fit.pov,
           "bone": fit.bone_name, "verts": len(fit.positions), "tris": len(fit.tris),
           "open": fit.open_frac, "depth": fit.depth, "glass_materials": fit.glass_materials,
           "backface_only": fit.back_only}
    if not dry:
        dst = os.path.join(out, leaf)
        try:
            res["submesh"] = mesh.write_with_submesh(dst, GLASS_MATERIAL, fit.positions, fit.normals, fit.uvs,
                                                     fit.tris, fit.bone, drop_material=GLASS_MATERIAL)
        except ValueError as e:
            return {"base": base, "status": "fail", "why": str(e), "mesh": leaf}
    if render_dir:
        res["renders"] = render(fit, base, render_dir)
    return res


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("units", nargs="*", help="mesh base names (default: every craft ODF's baseName)")
    ap.add_argument("--game", default=GAME, help="Battlezone 98 Redux install (BZ_ASSETS, StockODFFiles)")
    ap.add_argument("--out", default=os.path.join(MOD, "Assets", "ModelFixes"), help="where rebuilt meshes go")
    ap.add_argument("--render", help="write eye/outside preview PNGs here")
    ap.add_argument("--dry-run", action="store_true", help="fit and report, write nothing")
    ap.add_argument("--materials", action="store_true", help="write Materials/crwx_cockpitglass.material and exit")
    ap.add_argument("--report", default=os.path.join(MOD, "Tools", "cockpitglass_report.txt"))
    a = ap.parse_args()
    if a.materials:
        p = os.path.join(MOD, "Materials", "crwx_cockpitglass.material")
        open(p, "w", newline="\n").write(material_text())
        print("wrote", p)
        return
    src = Sources(a.game, MOD)
    out = a.out
    os.makedirs(out, exist_ok=True)
    units = odf_units(src)
    bases = [u.lower() for u in a.units] if a.units else sorted(units)
    scripts = material_scripts(src)
    results, t0 = [], time.time()
    done = set()
    for base in bases:
        path, _, _ = cockpit_mesh(src, base)
        key = os.path.basename(path).lower() if path else base
        if key in done:
            continue
        done.add(key)
        r = process(src, out, base, scripts, a.render, a.dry_run)
        r["odfs"] = units.get(base, [])
        results.append(r)
        if r["status"] == "ok":
            print("ok   %-10s %-22s %-8s %-5s bone %-9s %4d v %4d t  open %3.0f%%  glass %.2f-%.2f m%s" % (
                base, r["mesh"], r["kind"], r["origin"], r["bone"], r["verts"], r["tris"], 100 * r["open"], *r["depth"],
                ("  modelled glass: " + ", ".join(m for m, _ in r["glass_materials"])) if r["glass_materials"] else ""))
        else:
            print("%-4s %-10s %s" % (r["status"], base, r["why"]))
    ok = [r for r in results if r["status"] == "ok"]
    fail = [r for r in results if r["status"] == "fail"]
    skip = [r for r in results if r["status"] == "skip"]
    lines = ["cockpitglass.py report %s (game %s)" % (time.strftime("%Y-%m-%d %H:%M"), a.game),
             "glass added: %d, failed: %d, skipped (no cockpit): %d" % (len(ok), len(fail), len(skip)), ""]
    for r in results:
        if r["status"] == "ok":
            lines.append("ok   %s (%s, %s, from %s) odfs=%s pov=%s bone=%s verts=%d tris=%d open=%.0f%% depth=%.2f-%.2f%s" % (
                r["base"], r["mesh"], r["kind"], r["origin"], ",".join(r["odfs"]), r["pov"], r["bone"], r["verts"],
                r["tris"], 100 * r["open"], r["depth"][0], r["depth"][1],
                (" modelled-glass=" + ",".join(m for m, _ in r["glass_materials"])) if r["glass_materials"] else ""))
        else:
            lines.append("%s %s (%s) odfs=%s: %s" % (r["status"], r["base"], r.get("mesh", "-"), ",".join(r["odfs"]),
                                                     r["why"]))
    if not a.dry_run and not a.units:
        open(a.report, "w", newline="\n").write("\n".join(lines) + "\n")
    print("\n%d glass, %d failed, %d skipped in %.0f s" % (len(ok), len(fail), len(skip), time.time() - t0))


if __name__ == "__main__":
    main()
