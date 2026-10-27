"""Prepare a scale-aware Poly Haven Moon trial through the existing HD builder.

Source downloads are opt-in, hash-pinned CC0 assets. Resulting binaries stay in
Local. The original HD candidate, source cache and shipping config are preserved.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import urllib.request

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates

ROOT = Path(__file__).resolve().parent.parent


def periodic_sample(values, size, repeats):
    """Filter before resampling; integer repeats keep the tile periodic."""
    if repeats < 1 or int(repeats) != repeats:
        raise ValueError("Use positive integer repeats for seamless tiles")
    width = values.shape[0]
    if values.shape[1] != width:
        raise ValueError("Expected square source maps")
    sigma = max(0., (width*repeats/size-1)*.5)
    blur = gaussian_filter(values, (sigma,sigma,0) if values.ndim == 3 else sigma, mode="wrap")
    uv = ((np.arange(size)+.5)*width*repeats/size-.5) % width
    yy,xx = np.meshgrid(uv,uv,indexing="ij")
    if values.ndim == 2:
        return map_coordinates(blur,[yy,xx],order=1,mode="grid-wrap")
    return np.stack([map_coordinates(blur[:,:,c],[yy,xx],order=1,mode="grid-wrap")
                     for c in range(values.shape[2])],axis=2)


def encode_slopes(slopes):
    vectors = np.concatenate((slopes,np.ones((*slopes.shape[:2],1),np.float32)),axis=2)
    vectors /= np.linalg.norm(vectors,axis=2,keepdims=True)
    return np.uint8(np.clip(np.rint((vectors+1)*127.5),0,255))


def normal_audit(normal, height):
    """Determine polarity from independently supplied displacement, never D."""
    slopes = normal[:,:,:2]/np.maximum(normal[:,:,2:],.01)
    dy,dx = np.gradient(gaussian_filter(height,2,mode="wrap"))
    correlations = [float(np.corrcoef(gaussian_filter(slopes[:,:,i],2,mode="wrap")[6:-6,6:-6].ravel(),
                                     -d[6:-6,6:-6].ravel())[0,1]) for i,d in enumerate((dx,dy))]
    if not all(np.isfinite(c) and abs(c) > .6 for c in correlations):
        raise ValueError(f"Normal/height convention is inconclusive: {correlations}")
    signs = np.sign(correlations)
    return slopes*signs, {"sourceCorrelationToNegativeHeightGradient":correlations,
                          "channelSigns":signs.astype(int).tolist(),
                          "convertedCorrelation":[abs(c) for c in correlations]}


def specular_from_roughness(roughness, settings):
    # Legacy specular weakly influences Enhanced roughness; this is a matte
    # dielectric approximation, not lossless metallic/roughness conversion.
    value = settings["specularMinimum"] + settings["specularRange"]*(1-np.clip(roughness,0,1))**2
    return np.repeat(np.uint8(np.rint(value))[:,:,None],3,axis=2)


def read_source(folder, asset):
    images = {}
    for channel in ("diff","disp","nor_dx","rough"):
        with Image.open(folder/f"{asset}_{channel}_2k.png") as image:
            if channel in ("diff","nor_dx"):
                images[channel] = np.asarray(image.convert("RGB"),np.float32)
            else:
                raw = np.asarray(image)
                if raw.ndim != 2 or raw.dtype != np.uint16:
                    raise ValueError("Expected original 16-bit displacement/roughness PNG")
                images[channel] = raw.astype(np.float32)/65535
    return images


def material(source, settings, config, size=1024):
    normal = source["nor_dx"]/127.5-1
    slopes,audit = normal_audit(normal,source["disp"])
    repeats = config["repeats"]
    diffuse = periodic_sample(source["diff"],size,repeats)
    # Retain photographed variation with the candidate's cool-neutral palette.
    diffuse *= np.asarray(config["targetMean"])/np.maximum(diffuse.mean(axis=(0,1)),1)
    images = {"D":np.uint8(np.clip(np.rint(diffuse),0,255)),
              "N":encode_slopes(periodic_sample(slopes,size,repeats)*config["normalStrength"]/2.1),
              "S":specular_from_roughness(periodic_sample(source["rough"],size,repeats),settings),
              "E":np.zeros((size,size,3),np.uint8)}
    audit.update({"repeats":repeats,"sourceWidthMeters":config["sourceWidthMeters"],
                  "effectiveWidthMeters":20/repeats,"normalSharpenCompensation":2.1})
    return images,audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources",type=Path,default=ROOT/"Local/TerrainHD/PolyHavenSources")
    parser.add_argument("--settings",type=Path,default=ROOT/"Tools/TerrainHD/Moon/polyhaven.json")
    parser.add_argument("--download",action="store_true",help="Download missing pinned CC0 source images")
    parser.add_argument("--source-build",type=Path,required=True)
    parser.add_argument("--toolbox",type=Path,required=True)
    parser.add_argument("--openshim",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    args = parser.parse_args()
    settings = json.loads(args.settings.read_text())
    if settings["schema"] != "cr-moon-polyhaven-v1":
        raise ValueError("Unsupported Poly Haven recipe")
    output = args.output.resolve()
    if output.exists():
        raise ValueError("Choose a fresh output folder to preserve earlier artwork")
    args.sources.mkdir(parents=True,exist_ok=True)
    for entry in settings["assets"]:
        path = args.sources/entry["file"]
        if not path.exists() and args.download:
            with urllib.request.urlopen(entry["url"],timeout=90) as response:
                payload = response.read()
            if hashlib.sha256(payload).hexdigest() != entry["sha256"]:
                raise ValueError(f"Source download hash changed: {entry['file']}")
            path.write_bytes(payload)
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            raise ValueError(f"Missing or changed source {path}; use --download for missing files")
    output.mkdir(parents=True)
    sources = {asset:read_source(args.sources,asset) for asset in {settings[k]["asset"] for k in ("ground","dust","detail")}}
    audits = {}
    for kind in ("ground","dust"):
        directory = output/kind
        directory.mkdir()
        images,audits[kind] = material(sources[settings[kind]["asset"]],settings,settings[kind])
        for channel,pixels in images.items():
            Image.fromarray(pixels).save(directory/f"{channel}.png")
    # Dust detail uses displacement, not shaded albedo. The 8x layer covers
    # 2.5 m; six 0.4 m repeats retain approximately physical grain scale.
    detail = periodic_sample(sources[settings["detail"]["asset"]]["disp"],2048,settings["detail"]["repeats"])
    detail = (detail-detail.mean())/max(float(detail.std()),1e-8)
    detail = np.uint8(np.clip(np.rint((.5+detail*settings["detail"]["heightContrast"])*255),0,255))
    detail_png = output/"detail.png"
    Image.fromarray(np.repeat(detail[:,:,None],3,axis=2)).save(detail_png)
    sys.path.insert(0,str(args.toolbox.resolve()))
    from battlezone.terrain import hd_tiles
    detail_dds = output/"detail.dds"
    hd_tiles._convert(detail_png,detail_dds,"D",2048,"directx")
    spec = importlib.util.spec_from_file_location("moon_regolith",ROOT/"Tools/Build-MoonRegolith.py")
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    builder.main(["--source-build",str(args.source_build),"--toolbox",str(args.toolbox),
                  "--openshim",str(args.openshim),"--output",str(output/"terrain"),
                  "--ground-material",str(output/"ground"),"--dust-material",str(output/"dust"),
                  "--detail-source",str(detail_dds)])
    report = {"schema":"cr-moon-polyhaven-report-v1","recipe":settings,"normalAudits":audits,
              "detail":builder.audit_detail(Image.open(detail_png)),
              "detailPhysicalWidthMetersAt8x":2.5/settings["detail"]["repeats"],
              "geometry":"Existing varied authored craters; Poly Haven height validates fine normals and supplies detail only",
              "roughnessPolicy":"Matte legacy specular approximation; no new shader or texture slot",
              "bundle":str(output/"terrain/bundle")}
    (output/"polyhaven_report.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps({k:v for k,v in report.items() if k != "recipe"},indent=2))


if __name__ == "__main__":
    main()
