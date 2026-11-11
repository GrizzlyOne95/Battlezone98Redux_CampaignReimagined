"""'cdrv' atlas (CCA dropship svdrop). Colours, panel density, line weight and marking style measured from the stock
Redux DDS svrecy/svmuf/svtank/svfigh/sbspow (README, measure_stock.py) and from the Total Command Soviet dropship
used as a construction/texturing reference (rules only); generated fresh in code, nothing is copied.
The hull atlas is painted per mesh island by texgen_island.py: large cream paint fields, near-black armour on the nose
and undersides, panel outlines and relief on the real mesh edges, yellow/black hazard bands on chamfer strips, ramp edge
and leg bases, a dark colour band with a red line along the flanks, a red stripe fan on the nose slope, 1-5 height ticks on
the ramp, stencil blocks, vent hatches and a star + serial on each flank.
Needs `Local/dropships/tex/svdrop_islands.json` (blender -b -P build_svdrop.py -- --norender first).
Writes tex/cdrv*.png and out/cdrv*.dds.  Run: python texgen_svstock.py"""
import texgen_island as I

FAC = "cdrv"
PAL = dict(
    paints=[(1.0, (160, 154, 136))],
    tags=dict(base=(160, 154, 136), roof=(160, 154, 136), flank=(160, 154, 136), fan=(160, 154, 136),
              armor=(30, 30, 29), skirt=(30, 30, 29), door=(160, 154, 136), under=(24, 23, 21), bezel=(26, 25, 23), leg=(38, 38, 36), ramp=(150, 146, 130), bayfloor=(40, 39, 36), baywall=(58, 57, 53), bayceil=(66, 65, 60),
              rampdeck=(46, 45, 42)),
    dark=(30, 28, 25), floor=(36, 35, 32), line=(40, 36, 32), line_dark=(62, 62, 60), slot=(14, 13, 12),
    stencil=(120, 36, 30), mark=(160, 36, 32), star=(196, 36, 30), star_edge=None, ring=None, roundel=(70, 68, 62),
    hazard_a=(206, 168, 34), hazard_b=(24, 23, 21), stripe=(150, 38, 32), accent=(82, 84, 78), dash=(52, 52, 50),
    fan=(166, 40, 34), band=(88, 94, 92), band_line=(168, 40, 34), band_line2=(206, 168, 34), band_dash=(190, 186, 170), tick=(214, 176, 40),
    emb_bg=None, emb_ring=None, emb_star=(196, 36, 30), emb_star_edge=None, serial="3-A26", serial2="3-A27",
    serial_col=(130, 40, 34),
    light=(236, 160, 24), red=(225, 45, 35), lamp=(240, 170, 40), glow=(255, 150, 50), window=(58, 88, 100),
    glass_emit=0.2, greeble_tint=(0.9, 0.88, 0.82), chevron="bolt", patches=None)
STYLE = dict(
    ship="svdrop", tone=0.03, grid_m=5.0, patch_tags=(), patch_p=0.0, dark_tags=("armor", "skirt", "under", "bezel", "leg", "bayfloor", "baywall", "bayceil", "rampdeck"),
    band_tags=("flank",), band_th=0.42, ticks_tags=("ramp", "door"), logo_tags=("flank",), logo_min=4.5, serial_beside=False, lip_edge="bottom", bay_grid=3.0,
    density=0.07, max_details=14,
    spec=dict(armor=40, under=35, bezel=30, leg=45),
    kinds=dict(slab=.22, grille=.12, hatch=.14, plate=.10, rivets=.12, stencil=.14, stripe=.08, star=.02, bolt=.03),
    kinds_by_tag=dict(under=dict(hatch=.3, slab=.3, plate=.2, stencil=.2), armor=dict(slab=.4, rivets=.3, plate=.3), roof=dict(slab=.4, hatch=.3, grille=.2, rivets=.1)),
    # trim-sheet backdrop (texgen_fac.plating_cells)
    cells=True, minsz=130, depth=8, line=3, details=300)
WEAR = dict(drift=0.04, grain=0.04, blot=0.15, grime=0.9, rust=0.2, chip=0.4, scratch=200,
            dirt=(58, 50, 40), rustc=(96, 60, 40))

if __name__ == "__main__":
    I.build(FAC, PAL, STYLE, WEAR, 1140)
