"""'crdv' atlas (CRA dropship cvdrop). Palette, patch scale, wear and marking style measured from the stock Redux DDS
cvrecy/cvmuf/cvtnk/cvfigh/cvhraz (README, measure_stock.py), with the Total Command Chinese-palette dropship used only as a
colour/marking reference (rules, not pixels): olive and ochre hull, maroon roof and spine, red-star roundels with a yellow
ring and a serial, chipped olive/khaki/charcoal patches, yellow/black hazard on chamfer strips and ramp and leg bases.
The hull atlas is painted per mesh island by texgen_island.py (panel outline and relief on the real mesh edges, one
insignia per large flat face, authored separately for each side); generated fresh in code, nothing is copied.
Needs `Local/dropships/tex/cvdrop_islands.json` (blender -b -P build_cvdrop.py -- --norender first).
Writes tex/crdv*.png and out/crdv*.dds.  Run: python texgen_cvstock.py"""
import texgen_island as I

FAC = "crdv"
PAL = dict(
    paints=[(0.38, (82, 78, 44)), (0.14, (58, 60, 34)), (0.10, (112, 98, 52)), (0.28, (56, 56, 53))],
    tags=dict(base=(82, 78, 44), roof=(80, 28, 24), flank=(118, 102, 50), wing=(110, 98, 52), pod=(60, 62, 36),
              armor=(66, 68, 38), rear=(112, 98, 50), under=(34, 34, 31), bezel=(24, 24, 22), leg=(56, 56, 52),
              ramp=(58, 58, 54), bayfloor=(38, 38, 33), baywall=(54, 54, 44), bayceil=(58, 58, 50),
              rampdeck=(44, 44, 38)),
    patches=[(82, 78, 44), (90, 84, 46), (76, 72, 42)],
    dark=(32, 32, 30), floor=(34, 34, 31), line=(30, 30, 24), line_dark=(78, 78, 70), slot=(16, 16, 15),
    stencil=(190, 156, 48), mark=(150, 124, 40), star=(200, 160, 44), star_edge=(110, 26, 18), ring=(215, 210, 195),
    roundel=(90, 28, 20), hazard_a=(176, 144, 40), hazard_b=(24, 24, 22), stripe=(120, 104, 46), accent=(96, 32, 22),
    dash=(34, 34, 28), fan=(150, 32, 26), band=(88, 30, 26), band_line=(194, 154, 40), band_dash=(150, 130, 50),
    tick=(204, 164, 44), spine=(62, 22, 18),
    emb_bg=(176, 162, 118), emb_ring=(190, 150, 36), emb_star=(190, 36, 28), emb_star_edge=None,
    serial="4-17", serial2="4-18", serial_col=(212, 180, 56),
    light=(60, 210, 245), red=(225, 45, 35), lamp=(50, 210, 245), glow=(255, 140, 40), window=(36, 72, 84),
    glass_emit=0.3, greeble_tint=(0.9, 0.95, 0.85), chevron="slash")
STYLE = dict(
    ship="cvdrop", tone=0.03, grid_m=6.0, patch_tags=("base", "wing", "pod", "rear"), patch_p=0.4,
    dark_tags=("under", "bezel", "leg", "ramp", "bayfloor", "baywall", "bayceil", "rampdeck"), band_tags=("flank",), band_th=0.36, ticks_tags=("ramp",),
    logo_tags=("flank", "rear"), logo_min=4.0, logo_area=90, lip_edge="top", bay_grid=3.0, serial_beside=True, spine_tags=("roof",),
    density=0.05, max_details=10,
    spec=dict(under=35, bezel=30, leg=45, armor=50),
    kinds=dict(slab=.10, recess=.0, plate=.18, rivets=.12, grille=.10, stencil=.10, stripe=.10, hazard=.0, hatch=.12,
               star=.0),
    kinds_by_tag=dict(roof=dict(slab=.3, grille=.3, hatch=.2, rivets=.2)),
    # trim-sheet backdrop (texgen_fac.plating)
    minsz=330, depth=5, line=2, details=340)
WEAR = dict(drift=0.12, grain=0.06, blot=0.25, grime=0.8, rust=0.4, chip=0.5, scratch=700,
            bare=(54, 50, 42), scratch_col=(26, 24, 20), scratch_a=0.5,
            dirt=(36, 34, 28), rustc=(104, 60, 30))

if __name__ == "__main__":
    I.build(FAC, PAL, STYLE, WEAR, 2140)
