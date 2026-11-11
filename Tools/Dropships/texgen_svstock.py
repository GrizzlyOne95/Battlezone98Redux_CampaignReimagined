"""'cdrv' atlas (CCA dropship svdrop): cream-grey painted plate on a charcoal chassis, black ribbed slabs,
red-brown stencils, red stars and lightning bolts, black/white hazard strips, amber lamps, soft heavy grime.
Palette and wear measured from the stock Redux DDS svrecy/svmuf/svtank/svfigh/sbspow (README, measure_stock.py);
generated fresh in code, nothing is copied from those textures. Writes tex/cdrv*.png and out/cdrv*.dds.
Run: python texgen_svstock.py"""
import texgen_fac as F

FAC = "cdrv"
PAL = dict(
    paints=[(1.0, (160, 154, 136))],      # one cream paint field; per-cell value variation is +-3 % (STYLE["tone"])
    dark=(30, 28, 25), dark_paint=(24, 23, 21), floor=(36, 35, 32), line=(26, 24, 22), slot=(14, 13, 12),
    stencil=(120, 36, 30), mark=(160, 36, 32), star=(196, 36, 30), star_edge=None, ring=None, roundel=(70, 68, 62),
    hazard_a=(200, 196, 184), hazard_b=(24, 23, 21), stripe=(150, 38, 32), accent=(82, 84, 78),
    light=(236, 160, 24), red=(225, 45, 35), lamp=(240, 170, 40), glow=(255, 150, 50), window=(58, 88, 100),
    glass_emit=0.2, serial="3-A26", serial_col=(130, 40, 34), greeble_tint=(0.9, 0.88, 0.82), chevron="bolt")
# cells: 4 x 4 cells of 512 px, a panel line on each cell's left/bottom edge (lines follow the facet edges because
# facets are UV'd from a cell origin); 3 to 5 sparse details per cell; underside/frame islands use the dark patch
STYLE = dict(cells=True, tone=0.03, minsz=130, depth=8, line=3, details=300,
             kinds=dict(slab=.26, grille=.12, hatch=.10, plate=.10, rivets=.12, stencil=.10, stripe=.08, hazard=.05,
                        star=.03, bolt=.04))
WEAR = dict(drift=0.04, grain=0.04, blot=0.15, grime=0.9, rust=0.2, chip=0.4, scratch=200,
            dirt=(58, 50, 40), rustc=(96, 60, 40))

if __name__ == "__main__":
    F.build(FAC, PAL, STYLE, WEAR, 1140)
