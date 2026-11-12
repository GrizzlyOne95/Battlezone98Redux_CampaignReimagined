"""Island painter for the faction dropships (svdrop = CCA, cvdrop = CRA).

dropkit.finish_uv packs every hull face group (a coplanar group of faces, in a frame aligned to its longest edge) into
one atlas and writes `<ship>_islands.json` with each island's rectangle, polygons and boundary edges in atlas pixels.
This module paints that atlas so the texture follows the mesh: base paint by the island's tag, border relief and
darkening along the real mesh edges, an inset panel outline (a fixed fraction of the island size from the border,
parallel to its edges), an inner grid at a fixed fraction of the island width that stops at the outline, and the tag's
markings (hazard bands on chamfer strips, ramp and leg bases, colour bands, a red stripe fan, height ticks, stencil text,
vent hatches, one insignia per large flat face). Everything is generated in code; nothing is copied from any texture,
concept image or reference model. Weathering reuses texgen_fac.weather on the whole atlas.
Trim sheet: texgen_fac.trim_sheet (lamps, glass window cell, nozzle strip and throat dish cell, hold strip).
"""
import glob
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths as P
import texgen as T
import texgen_fac as F
from texgen_fac import Canvas, digits, bolt_pts, star_pts, weather

c = T.col
BAY = ("bayfloor", "baywall", "bayceil", "rampdeck")
LOGOS = []          # world positions of the insignia, written for the close-up cameras


# ---------------------------------------------------------------- local helpers (island-sized arrays only)
def lmask(w, h, fn):
    m = Image.new("L", (w, h), 0)
    fn(ImageDraw.Draw(m))
    return np.asarray(m, np.float32) / 255.0


def ldecal(rgb, paint, m, color, alpha=0.92):
    a = (m * alpha)[..., None]
    rgb[:] = rgb * (1 - a) + c(color) * a
    paint[:] = np.maximum(paint, m)


def seg_distance(h, w, segs):
    """Distance (px) from every pixel centre to the nearest boundary segment."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    xx += 0.5
    yy += 0.5
    dist = np.full((h, w), 1e9, np.float32)
    for ax, ay, bx, by in segs:
        abx, aby = bx - ax, by - ay
        L2 = abx * abx + aby * aby
        if L2 < 1e-6:
            continue
        t = np.clip(((xx - ax) * abx + (yy - ay) * aby) / L2, 0, 1)
        dx = xx - (ax + t * abx)
        dy = yy - (ay + t * aby)
        np.minimum(dist, np.sqrt(dx * dx + dy * dy), out=dist)
    return dist


# ---------------------------------------------------------------- one island
def paint_island(cv, I, pal, st, r):
    x0, y0, w, h = I["rect"]
    pad, dd, tag = I["pad"], I["dd"], I["tag"]
    W, H = I["W"], I["H"]
    n = I["n"]
    sl = (slice(y0, y0 + h), slice(x0, x0 + w))
    rgb, paint, height = cv.rgb[sl], cv.paint[sl], cv.height[sl]
    m = Image.new("L", (w, h), 0)
    d_ = ImageDraw.Draw(m)
    for poly in I["faces"]:
        pts = [(x - x0, y - y0) for x, y in poly]
        d_.polygon(pts, fill=255)
        d_.line(pts + [pts[0]], fill=255, width=1)
    mask = np.asarray(m, np.float32) / 255.0
    inner = mask > 0.5
    segs = [(a - x0, b - y0, c_ - x0, d - y0) for a, b, c_, d in I["edges"]]
    dist = seg_distance(h, w, segs[:120] if len(segs) > 120 else segs)
    short = min(W, H)
    area = float(inner.sum()) / (dd * dd)
    dark = tag in st["dark_tags"]
    # base paint: one value per island (+-3 %), a faint fall-off toward the bottom edge
    col = c(pal["tags"].get(tag, pal["tags"]["base"])) * (1 + r.uniform(-st["tone"], st["tone"]))
    grad = np.linspace(1.025, 0.975, h, dtype=np.float32)[:, None, None]
    rgb[:] = col * grad
    height[:] = 0.6
    cv.spec[sl] = st["spec"].get(tag, 55)
    lw = max(1.5, 0.06 * dd)
    inset_m = float(np.clip(0.075 * short, 0.16, 0.5))
    inset = inset_m * dd
    line_col = c(pal["line_dark"] if dark else pal["line"])
    flat = tag == "bezel"
    isbay = tag in BAY
    bx0, by0, bx1, by1 = pad, pad, pad + W * dd, pad + H * dd

    # patches (CRA): the inner grid cells take a paint from the patch list, so patch borders are panel lines
    gm = st.get("bay_grid", st["grid_m"]) if isbay else st["grid_m"]
    nu = max(1, int(round((W - 2 * inset_m) / gm)))
    nv = max(1, int(round((H - 2 * inset_m) / gm)))
    xs = [bx0 + inset + i * (bx1 - bx0 - 2 * inset) / nu for i in range(nu + 1)]
    ys = [by0 + inset + j * (by1 - by0 - 2 * inset) / nv for j in range(nv + 1)]
    if pal.get("patches") and tag in st["patch_tags"] and short > 2.4:
        for j in range(nv):
            for i in range(nu):
                if r.random() < st["patch_p"]:
                    pc = c(pal["patches"][int(r.integers(len(pal["patches"])))]) * (1 + r.uniform(-.04, .04))
                    ia, ib, ja, jb = int(xs[i]), int(xs[i + 1]), int(ys[j]), int(ys[j + 1])
                    rgb[ja:jb, ia:ib] = pc * grad[ja:jb]
    # border relief: darkening along the real mesh edge, a thin highlight just inside it, edge wear source
    ao = np.exp(-dist / (0.22 * dd)) * mask
    rgb *= (1 - 0.30 * ao)[..., None]
    rgb[(dist > 1.2) & (dist < 2.6) & inner] *= 1.14
    height[inner & (dist < 0.12 * dd)] = 0.42
    cv.seam[sl] = np.maximum(cv.seam[sl], ((dist < 2.0) & inner).astype(np.float32))
    cv.dirt[sl] = np.maximum(cv.dirt[sl], np.where((dist < 2.5) & inner, 0.35, 0).astype(np.float32))
    if not flat and short > 0.45:
        ol = (np.abs(dist - inset) < lw * 0.5) & inner
        rgb[ol] = line_col
        height[ol] = 0.2
        lit = (dist > inset + lw * 0.5) & (dist < inset + lw * 1.6) & inner
        rgb[lit] *= 1.10
        cv.seam[sl][ol] = 1
        # inner grid, parallel to the island axes, ending at the outline
        gl = np.zeros((h, w), bool)
        for xg in xs[1:-1]:
            gl[:, int(xg):int(xg) + max(1, int(lw * 0.8))] = True
        for yg in ys[1:-1]:
            gl[int(yg):int(yg) + max(1, int(lw * 0.8)), :] = True
        gl &= inner & (dist > inset + lw)
        rgb[gl] = line_col * 1.1
        height[gl] = 0.25
        cv.seam[sl][gl] = 1
        cv.dirt[sl] = np.maximum(cv.dirt[sl], np.where(gl, 0.2, 0).astype(np.float32))

    # ---- markings
    occ = np.zeros((h // 6 + 2, w // 6 + 2), bool)
    clear = lambda px, py, pw, ph, mg=0.0: (
        min(dist[min(h - 1, py), min(w - 1, px)], dist[min(h - 1, py + ph), min(w - 1, px)],
            dist[min(h - 1, py), min(w - 1, px + pw)], dist[min(h - 1, py + ph), min(w - 1, px + pw)],
            dist[min(h - 1, py + ph // 2), min(w - 1, px + pw // 2)]) > inset + lw * 2 + mg * dd
        and mask[min(h - 1, py + ph // 2), min(w - 1, px + pw // 2)] > 0.5)

    def reserve(px, py, pw, ph):
        occ[py // 6:(py + ph) // 6 + 1, px // 6:(px + pw) // 6 + 1] = True

    def place(wm, hm, mg=0.12, tries=40):
        pw, ph = max(3, int(wm * dd)), max(3, int(hm * dd))
        lo_x, hi_x = int(bx0 + inset), int(bx1 - inset - pw)
        lo_y, hi_y = int(by0 + inset), int(by1 - inset - ph)
        if hi_x <= lo_x or hi_y <= lo_y:
            return None
        for _ in range(tries):
            px, py = int(r.integers(lo_x, hi_x)), int(r.integers(lo_y, hi_y))
            if occ[py // 6:(py + ph) // 6 + 1, px // 6:(px + pw) // 6 + 1].any():
                continue
            if not clear(px, py, pw, ph, mg):
                continue
            reserve(px - 2, py - 2, pw + 4, ph + 4)
            return px, py, pw, ph
        return None

    strip = short <= 4.6 and max(W, H) >= 3.0 * short and area >= 1.0
    horiz = W >= H
    L_axis, S_axis = (W, H) if horiz else (H, W)

    def hazard_band(ax, ay, bw_, bh_, pitch):
        """Diagonal two-colour band in the local rect [ax, ax+bw_) x [ay, ay+bh_), clipped to the island."""
        ax, ay = max(0, ax), max(0, ay)
        bw_, bh_ = min(w - ax, bw_), min(h - ay, bh_)
        if bw_ < 2 or bh_ < 2:
            return
        yy, xx = np.mgrid[ay:ay + bh_, ax:ax + bw_]
        band = (((xx + yy) // max(3, pitch)) % 2 == 0)
        sub_in = inner[ay:ay + bh_, ax:ax + bw_] & (dist[ay:ay + bh_, ax:ax + bw_] > inset * 0.6)
        tgt = rgb[ay:ay + bh_, ax:ax + bw_]
        newc = np.where(band[..., None], c(pal["hazard_a"]), c(pal["hazard_b"]))
        tgt[sub_in] = newc[sub_in]
        paint[ay:ay + bh_, ax:ax + bw_][sub_in] = 1
        height[ay:ay + bh_, ax:ax + bw_][sub_in] = 0.7

    if strip and tag not in ("under", "bezel") and short > 0.3:
        hazardous = tag in ("leg", "ramp") or n[2] < -0.2
        bwm = float(np.clip(0.14 * short, 0.16, 0.45))
        if hazardous:
            if horiz:
                hazard_band(int(bx0 + inset), int(by0 + (H - bwm) * 0.5 * dd), int((W - 2 * inset_m) * dd), int(bwm * dd),
                            int(bwm * dd))
            else:
                hazard_band(int(bx0 + (W - bwm) * 0.5 * dd), int(by0 + inset), int(bwm * dd), int((H - 2 * inset_m) * dd),
                            int(bwm * dd))
        else:      # dark panel insert along the chamfer with fine vent ribs (not a row of windows)
            bt = 0.42 * short
            if horiz:
                ra, rb = int(by0 + (H - bt) * 0.5 * dd), int(by0 + (H + bt) * 0.5 * dd)
                ca, cb = int(bx0 + inset * 1.6), int(bx1 - inset * 1.6)
            else:
                ca, cb = int(bx0 + (W - bt) * 0.5 * dd), int(bx0 + (W + bt) * 0.5 * dd)
                ra, rb = int(by0 + inset * 1.6), int(by1 - inset * 1.6)
            sel = np.zeros((h, w), bool)
            sel[ra:rb, ca:cb] = True
            sel &= inner & (dist > inset * 0.8)
            rgb[sel] = c(pal["dash"])
            rib = np.zeros((h, w), bool)
            pitch = max(4, int(0.16 * dd))
            if horiz:
                rib[:, ::pitch] = True
            else:
                rib[::pitch, :] = True
            rgb[sel & rib] *= 1.35
            height[sel] = 0.35
            paint[sel] = 1
    elif tag in ("leg", "ramp") and not flat and short > 0.3:
        # base band at the bottom of the face: a fixed 0.9 m on legs, 5 % of the face height on the ramp
        bh = 0.9 if tag == "leg" else max(0.5, 0.06 * H)
        if H > bh * 2.2 and n[2] > -0.9:
            hazard_band(int(bx0 + inset), int(by1 - inset - bh * dd), int((W - 2 * inset_m) * dd), int(bh * dd),
                        int(bh * dd))
            reserve(int(bx0), int(by1 - inset - bh * dd) - 3, w, int(bh * dd) + 6)

    big = area >= 6.0 and short >= 1.6 and not strip and not flat and not isbay
    if big and tag in st.get("spine_tags", ()) and max(W, H) >= 8.0:
        bwm = int(1.3 * dd)
        sel = np.zeros((h, w), bool)
        if H >= W:
            xa = int(bx0 + (bx1 - bx0 - bwm) / 2)
            sel[:, xa:xa + bwm] = True
            reserve(xa - 3, 0, bwm + 6, h)
        else:
            ya = int(by0 + (by1 - by0 - bwm) / 2)
            sel[ya:ya + bwm, :] = True
            reserve(0, ya - 3, w, bwm + 6)
        sel &= inner & (dist > inset * 1.3)
        rgb[sel] = c(pal["spine"]) * (1 + r.uniform(-.03, .03))
        edge = sel & ~np.roll(np.roll(sel, 2, 0), 2, 1) | sel & ~np.roll(np.roll(sel, -2, 0), -2, 1)
        rgb[edge] = line_col
        paint[sel] = 1
    if big and tag == "fan" and area >= 5:
        ax, ay = int((bx0 + bx1) / 2), int(by1 - inset * 1.5)
        R = (H + W) * dd
        stripes = lmask(w, h, lambda d: [d.polygon([
            (ax, ay), (ax + R * math.sin(a - dl), ay - R * math.cos(a - dl)),
            (ax + R * math.sin(a + dl), ay - R * math.cos(a + dl))], fill=255)
            for a, dl in ((math.radians(g), math.radians(3.2 + 0.05 * abs(g))) for g in range(-48, 49, 16))])
        okm = (dist > inset * 1.6) & inner
        ldecal(rgb, paint, stripes * okm, pal["fan"], 0.95)
        reserve(0, 0, w, h)
    if big and tag in st["band_tags"] and H >= 3.4 and W >= 5.5:
        yb = int(by1 - inset - 0.14 * H * dd)
        th = max(3, int(st.get("band_th", 0.26) * dd))
        lt = max(2, th // 4)
        rows = [(0, "band", th), (th + 2, "band_line", lt)]
        if pal.get("band_line2"):
            rows.append((th + lt + 4, "band_line2", max(2, lt // 2 + 1)))
        for dy, key, tt in rows:
            sel = np.zeros((h, w), bool)
            sel[yb + dy:yb + dy + tt, :] = True
            sel &= inner & (dist > inset * 1.1)
            rgb[sel] = c(pal[key])
            paint[sel] = 1
        reserve(0, yb - 4, w, rows[-1][0] + rows[-1][2] + 10)
        # strip marking: short dashes on the band
        dm = lmask(w, h, lambda d: [d.rectangle((bx0 + inset * 2 + k * 1.1 * dd, yb + 1, bx0 + inset * 2 + k * 1.1 * dd + 0.5 * dd,
                                                 yb + th - 1), fill=255) for k in range(int((W - 2) / 1.1))])
        ldecal(rgb, paint, dm * (dist > inset * 1.6) * inner, pal["band_dash"], 0.6)
    if big and tag in st["ticks_tags"] and H >= 3.0 and W >= 4.0:
        tx, ty = int(bx0 + inset * 1.8), int(by0 + inset * 1.8)
        th_ = int((H - 3.6 * inset_m) * dd)
        step = th_ // 5

        def tick_fn(d):
            d.rectangle((tx, ty, tx + 2, ty + th_), fill=255)
            for k in range(6):
                yk = ty + th_ - k * step
                d.rectangle((tx, yk - 1, tx + int((0.25 + 0.05 * k) * dd), yk + 1), fill=255)
                if 0 < k:
                    digits(d, str(k), tx + int(0.7 * dd), yk - int(0.2 * dd), int(0.22 * dd), int(0.42 * dd), max(2, int(0.07 * dd)), 0.4)
        ldecal(rgb, paint, lmask(w, h, tick_fn) * inner, pal["tick"], 0.9)
        reserve(tx - 3, ty - 3, int(1.8 * dd), th_ + 8)
    if big and tag in st["logo_tags"] and short >= st["logo_min"] and area >= st.get("logo_area", 0):
        side = 1 if n[0] > 0 else -1
        # centre of the widest clear area of this face: the insignia never touches an edge or a bevel
        dsm = dist * mask
        dsm[:int(by0 + inset)] = 0
        dsm[int(by1 - inset - 0.3 * H * dd * (1 if tag in st["band_tags"] else 0)):] = 0
        iy, ix = np.unravel_index(int(np.argmax(dsm)), dsm.shape)
        free = float(dsm[iy, ix]) - (inset + 0.3 * dd)
        R = min(free, 0.24 * short * dd, math.sqrt(0.25 * area / math.pi) * dd)
        if R > 0.55 * dd:
            emblem(rgb, paint, w, h, ix, iy, R, pal, tag, side, dd, st)
            fr = I.get("frame")
            if fr:
                pu, pv = fr[6] + (ix - pad) / dd, fr[7] - (iy - pad) / dd
                pos = [fr[0] * pu + fr[3] * pv + n[0] * fr[8], fr[1] * pu + fr[4] * pv + n[1] * fr[8],
                       fr[2] * pu + fr[5] * pv + n[2] * fr[8]]
                LOGOS.append(dict(tag=tag, side=side, pos=[round(v, 2) for v in pos], n=n))
            reserve(int(ix - R * 1.2), int(iy - R * 1.2), int(R * 2.4 + (4.2 * R if st.get("serial_beside") else 0)), int(R * 2.4))
    if big:
        nd = int(min(st["max_details"], area * st["density"]))
        kinds = st["kinds_by_tag"].get(tag, st["kinds"])
        names = list(kinds)
        wts = np.array([kinds[k] for k in names], np.float64)
        wts /= wts.sum()
        for _ in range(nd):
            k = names[int(r.choice(len(names), p=wts))]
            detail(cv, sl, rgb, paint, w, h, place, k, pal, r, dd, x0, y0, st)

    if isbay and short > 0.6:
        paint_bay(cv, sl, I, rgb, paint, height, w, h, dist, inner, dd, inset, lw, (bx0, by0, bx1, by1), xs, ys,
                  pal, st, r, place, reserve, hazard_band, x0, y0)
    if tag == "armor" and area > 4:
        # tarmac panel: faint lighter stipple so the dark slab reads as worn armour, not a hole
        rgb[inner] *= (1 + 0.10 * (np.random.default_rng(int(x0 + y0)).random((h, w), dtype=np.float32)[inner] - 0.5))[..., None]


def paint_bay(cv, sl, I, rgb, paint, height, w, h, dist, inner, dd, inset, lw, box, xs, ys, pal, st, r, place, reserve,
              hazard_band, x0, y0):
    """Hold interior: floor/ramp grating and plating seams, wall and ceiling ribs on the face grid, tie-down rings,
    hazard edging at the ramp lip, small stencils, light panels (painted, and dim emissive via cv.emit)."""
    tag, W, H = I["tag"], I["W"], I["H"]
    bx0, by0, bx1, by1 = box
    emit = cv.emit[sl]
    yy, xx = np.mgrid[0:h, 0:w]
    ok = inner & (dist > inset + lw)
    if tag in ("bayfloor", "rampdeck"):
        p = max(5, int(0.26 * dd))
        cx = xx % p
        cy = (yy + ((xx // p) % 2) * (p // 2)) % p
        slot = (cx < p - 2) & (cy < max(2, p // 3)) & ok
        rgb[slot] *= 0.55
        height[slot] = 0.3
        ridge = (cy == p // 2) & ok & ~slot
        rgb[ridge] *= 1.12
        # lip edging: the stern (bottom) edge of a floor, the free (top) edge of a ramp deck; 0.5 m diagonal hazard
        bh = max(4, int(0.5 * dd))
        top = tag == "rampdeck" or st.get("lip_edge") == "top"
        ya = int(by0 + inset) if top else int(by1 - inset - bh)
        hazard_band(int(bx0 + inset), ya, int((bx1 - bx0) - 2 * inset), bh, bh)
        reserve(int(bx0), ya - 3, w, bh + 6)
        # tie-down rings along both long margins
        rr = max(3, int(0.2 * dd))
        step = int(6.0 * dd)
        rings = Image.new("L", (w, h), 0)
        d_ = ImageDraw.Draw(rings)
        for xm in (bx0 + inset + 0.9 * dd, bx1 - inset - 0.9 * dd):
            yk = by0 + inset + 2.0 * dd
            while yk < by1 - inset - 2.0 * dd:
                iy, ix = int(min(h - 1, yk)), int(min(w - 1, xm))
                if inner[iy, ix] and dist[iy, ix] > inset + 1.2 * dd:
                    d_.ellipse((xm - rr, yk - rr, xm + rr, yk + rr), outline=255, width=2)
                    d_.ellipse((xm - 1, yk - 1, xm + 1, yk + 1), fill=255)
                    reserve(int(xm - rr - 2), int(yk - rr - 2), 2 * rr + 4, 2 * rr + 4)
                yk += step
        ldecal(rgb, paint, np.asarray(rings, np.float32) / 255.0, pal["tick"], 0.85)
    elif tag == "baywall":
        # vertical frame ribs every grid column: lighter raised strip with dark edges, plus a rail near the floor
        for xg in xs[1:-1]:
            a = int(xg) - max(2, int(0.14 * dd))
            b = int(xg) + max(2, int(0.14 * dd))
            sel = np.zeros((h, w), bool)
            sel[:, a:b] = True
            sel &= ok
            rgb[sel] *= 1.22
            height[sel] = 0.75
            e = sel & ~np.roll(sel, 1, 1)
            rgb[e] *= 0.5
        yr = int(by1 - inset - 1.0 * dd)
        sel = np.zeros((h, w), bool)
        sel[yr:yr + max(3, int(0.22 * dd)), :] = True
        sel &= ok
        rgb[sel] = c(pal["band"]) if pal.get("band") is not None else rgb[sel]
        paint[sel] = 1
        # wall light strips, dim
        for xg in xs[:-1]:
            lx0, lx1 = int(xg + 0.7 * dd), int(xg + 2.2 * dd)
            ly0, ly1 = int(by0 + inset + 1.2 * dd), int(by0 + inset + 1.5 * dd)
            if lx1 < bx1 - inset and ly1 < by1 - inset:
                sel = np.zeros((h, w), bool)
                sel[ly0:ly1, lx0:lx1] = True
                sel &= ok
                if sel.any():
                    rgb[sel] = (205, 205, 190)
                    emit[sel] = (120, 118, 100)
    elif tag == "bayceil":
        for yg in ys[1:-1]:
            a = int(yg) - max(2, int(0.13 * dd))
            b = int(yg) + max(2, int(0.13 * dd))
            sel = np.zeros((h, w), bool)
            sel[a:b, :] = True
            sel &= ok
            rgb[sel] *= 1.2
            height[sel] = 0.75
            e = sel & ~np.roll(sel, 1, 0)
            rgb[e] *= 0.5
        for fx in (0.25, 0.75):          # conduit runs along the bay
            xc = int(bx0 + (bx1 - bx0) * fx)
            sel = np.zeros((h, w), bool)
            sel[:, xc:xc + max(3, int(0.12 * dd))] = True
            sel &= ok
            rgb[sel] = c(pal["band"])
            height[sel] = 0.7
        # light panels in the centre line, every second grid row
        xc = int((bx0 + bx1) / 2)
        for j in range(len(ys) - 1):
            if j % 2:
                continue
            ya, yb = int(ys[j] + 0.5 * dd), int(ys[j] + 2.2 * dd)
            sel = np.zeros((h, w), bool)
            sel[ya:yb, xc - int(0.7 * dd):xc + int(0.7 * dd)] = True
            sel &= ok
            if sel.any():
                rgb[sel] = (210, 210, 196)
                emit[sel] = (130, 128, 112)
                e = sel & ~np.roll(sel, 2, 1)
                rgb[e] *= 0.6
    # a few small labels, generated from segments
    for _ in range(2 if min(W, H) > 3 else 0):
        p = place(r.uniform(1.0, 1.8), 0.3, mg=0.2)
        if p:
            txt = "".join(str(int(r.integers(0, 10))) if r.random() < 0.75 else "-" for _ in range(int(r.integers(4, 7))))
            ch = p[3]
            m = lmask(w, h, lambda d: digits(d, txt, p[0], p[1], max(2, int(ch * 0.62)), ch, max(1, ch // 5), 0.5))
            ldecal(rgb, paint, m, pal["stencil"], 0.7)


def emblem(rgb, paint, w, h, cx, cy, R, pal, tag, side, dd, st):
    """One insignia + serial, centred at (cx, cy), radius R (px). Per-side variants are authored, not mirrored."""
    R = int(R)
    rot = -math.pi / 2 + (0.0 if side > 0 else math.radians(18))
    disc = lmask(w, h, lambda d: d.ellipse((cx - R, cy - R, cx + R, cy + R), fill=255))
    if pal.get("emb_bg"):
        ldecal(rgb, paint, disc, pal["emb_bg"], 0.95)
    if pal.get("emb_ring"):
        ring = lmask(w, h, lambda d: d.ellipse((cx - R, cy - R, cx + R, cy + R), outline=255, width=max(2, R // 9)))
        ldecal(rgb, paint, ring, pal["emb_ring"], 0.95)
    k = 0.72 if pal.get("emb_bg") else 1.0
    if pal.get("emb_star_edge"):
        ldecal(rgb, paint, lmask(w, h, lambda d: d.polygon(star_pts(cx, cy, R * k * 1.12, rot), fill=255)), pal["emb_star_edge"], 0.95)
    ldecal(rgb, paint, lmask(w, h, lambda d: d.polygon(star_pts(cx, cy, R * k, rot), fill=255)), pal["emb_star"], 0.95)
    txt = pal["serial"] if side > 0 else pal["serial2"]
    ch = max(5, int(R * 0.42))
    tw = int(len(txt) * ch * 0.62 * 1.5)
    if st.get("serial_beside"):
        sx = cx + R + int(R * 0.35) if side > 0 else cx - R - int(R * 0.35) - tw
        sy = cy - ch // 2
    else:
        sx, sy = cx - tw // 2, cy + R + int(R * 0.25)
    ldecal(rgb, paint, lmask(w, h, lambda d: digits(d, txt, sx, sy, int(ch * 0.62), ch, max(2, ch // 5), 0.5)), pal["serial_col"], 0.88)


def detail(cv, sl, rgb, paint, w, h, place, k, pal, r, dd, x0, y0, st):
    """A small detail at a free spot (atlas coordinates for the canvas helpers, local for decals)."""
    if k == "slab":
        p = place(r.uniform(1.6, 4.2), r.uniform(0.45, 1.0))
        if p:
            cv.slab(x0 + p[0], y0 + p[1], x0 + p[0] + p[2], y0 + p[1] + p[3], ribs=r.random() < 0.7)
    elif k == "grille":
        p = place(r.uniform(0.9, 1.8), r.uniform(0.5, 0.9))
        if p:
            cv.grille(x0 + p[0], y0 + p[1], x0 + p[0] + p[2], y0 + p[1] + p[3], pitch=int(r.choice((5, 7))))
    elif k == "hatch":
        s = r.uniform(1.3, 2.2)
        p = place(s, s * r.uniform(0.7, 1.0))
        if p:
            a, b, pw, ph = x0 + p[0], y0 + p[1], p[2], p[3]
            cv.recess(a, b, a + pw, b + ph, 0.80)
            cv.plate(a + 4, b + 4, a + pw - 4, b + ph - 4, 1.0)
            cv.recess(a + pw // 2 - 9, b + ph // 2 - 3, a + pw // 2 + 9, b + ph // 2 + 3, 0.5)
    elif k == "plate":
        p = place(r.uniform(1.0, 2.4), r.uniform(0.7, 1.4))
        if p:
            a, b, pw, ph = x0 + p[0], y0 + p[1], p[2], p[3]
            cv.plate(a, b, a + pw, b + ph, r.uniform(0.96, 1.1))
            for qx, qy in ((a + 4, b + 4), (a + pw - 7, b + 4), (a + 4, b + ph - 7), (a + pw - 7, b + ph - 7)):
                cv.rivets(qx, qy, 1, 1)
    elif k == "rivets":
        p = place(r.uniform(1.0, 2.4), 0.12)
        if p:
            cv.rivets(x0 + p[0], y0 + p[1], max(3, int(p[2] / max(7, 0.22 * dd))), max(7, int(0.22 * dd)))
    elif k == "stencil":
        p = place(r.uniform(1.4, 2.6), 0.34)
        if p:
            txt = "".join(str(int(r.integers(0, 10))) if r.random() < 0.8 else "-" for _ in range(int(r.integers(4, 7))))
            ch = p[3]
            m = lmask(w, h, lambda d: digits(d, txt, p[0], p[1], int(ch * 0.62), ch, max(2, ch // 5), 0.5))
            ldecal(rgb, paint, m, pal["stencil"], 0.75)
    elif k == "stripe":
        p = place(r.uniform(2.0, 5.0), 0.16)
        if p:
            rgb[p[1]:p[1] + p[3], p[0]:p[0] + p[2]] = c(pal["stripe"])
            paint[p[1]:p[1] + p[3], p[0]:p[0] + p[2]] = 1
    elif k == "star":
        p = place(0.6, 0.6)
        if p:
            R = p[2] // 2
            ldecal(rgb, paint, lmask(w, h, lambda d: d.polygon(star_pts(p[0] + R, p[1] + R, R), fill=255)), pal["star"])
    elif k == "bolt":
        p = place(0.8, 1.1)
        if p:
            ldecal(rgb, paint, lmask(w, h, lambda d: d.polygon(bolt_pts(p[0], p[1], p[2], p[3]), fill=255)), pal["mark"])


# ---------------------------------------------------------------- atlas
def build(fac, pal, st, wp, seed):
    os.makedirs(T.OUT, exist_ok=True)
    p = os.path.join(T.OUT, fac)
    jp = os.path.join(P.TEX, st["ship"] + "_islands.json")
    if not os.path.exists(jp):
        sys.exit(f"missing {jp}: run build_{st['ship']}.py -- --norender first (it writes the island layout)")
    with open(jp) as fh:
        lay = json.load(fh)
    A = lay["atlas"]
    cv = Canvas(pal, A, A)
    cv.emit = np.zeros((A, A, 3), np.uint8)
    cv.rgb[:] = c(pal["dark"])
    r = np.random.default_rng(seed)
    for isl in lay["islands"]:
        paint_island(cv, isl, pal, st, r)
    print("painted", len(lay["islands"]), "islands on", A, "px atlas")
    weather(cv, seed + 100, wp)
    T.finish_maps(cv.rgb, cv.height, cv.spec, None, p + "hull")
    Image.fromarray(cv.emit).save(p + "hull_E.png")        # per-ship emissive: dim hold light panels, same UVs as hull_D
    with open(os.path.join(P.TEX, st["ship"] + "_logos.json"), "w") as fh:
        json.dump(LOGOS, fh)
    del cv
    F.trim_sheet(pal, st, wp, seed + 240, p + "trim")
    for stale in glob.glob(p + "hullw*") + glob.glob(os.path.join(P.OUT, fac + "hullw*")):
        os.remove(stale)
    F.to_dds(sorted(glob.glob(p + "hull*.png") + glob.glob(p + "trim*.png")))
