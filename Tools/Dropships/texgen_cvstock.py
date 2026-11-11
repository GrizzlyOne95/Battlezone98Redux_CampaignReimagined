"""'crdv' atlas (CRA dropship cvdrop): camouflage patchwork of olive, mustard and brick-red paint panels on
a dark charcoal chassis, large panels, yellow stars with a red edge, cyan lamps, heavy chipping and fine
scratches. Palette and wear measured from the stock Redux DDS cvrecy/cvmuf/cvtnk/cvfigh/cvhraz (README,
measure_stock.py); generated fresh in code, nothing is copied from those textures.
Writes tex/crdv*.png and out/crdv*.dds.  Run: python texgen_cvstock.py"""
import texgen_fac as F

FAC = "crdv"
PAL = dict(
    paints=[(0.46, (82, 78, 44)), (0.16, (58, 60, 34)), (0.10, (112, 98, 52)), (0.28, (56, 56, 53))],
    dark=(32, 32, 30), dark_paint=(24, 24, 22), floor=(34, 34, 31), line=(14, 14, 12), slot=(16, 16, 15),
    stencil=(150, 130, 50), mark=(150, 124, 40), star=(200, 160, 44), star_edge=(110, 26, 18), ring=(215, 210, 195),
    roundel=(90, 28, 20), hazard_a=(150, 124, 40), hazard_b=(24, 24, 22), stripe=(120, 104, 46), accent=(96, 32, 22),
    light=(60, 210, 245), red=(225, 45, 35), lamp=(50, 210, 245), glow=(255, 140, 40), window=(36, 72, 84),
    glass_emit=0.3, serial="4-17", serial_col=(170, 140, 44), greeble_tint=(0.9, 0.95, 0.85), chevron="slash")
# paint: olive dominant, khaki (the old mustard) pulled toward the cvrecy/cvtnk plate medians (74-90 grey-olive);
# red only in the trim accent band, the roundel and the star edge. Patch size about 3x the previous frequency.
STYLE = dict(minsz=330, depth=5, line=2, details=340,
             kinds=dict(slab=.10, recess=.14, plate=.16, rivets=.10, grille=.08, pipe=.02, stencil=.08, slash=.05,
                        star=.03, stripe=.10, hazard=.06, hatch=.08))
WEAR = dict(drift=0.12, grain=0.06, blot=0.25, grime=0.8, rust=0.5, chip=0.7, scratch=2200,
            dirt=(36, 34, 28), rustc=(104, 60, 30))

if __name__ == "__main__":
    F.build(FAC, PAL, STYLE, WEAR, 2140)
