"""Palette-preserving, explicit source-material edits before variants/blends."""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

ROOT = Path(__file__).resolve().parent.parent


def signature(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def slopes(pixels):
    n = pixels.astype(np.float32)/127.5-1
    return n[:,:,:2]/np.maximum(n[:,:,2:],.02)


def normal(slopes):
    n = np.concatenate((slopes,np.ones((*slopes.shape[:2],1),np.float32)),axis=2)
    n /= np.linalg.norm(n,axis=2,keepdims=True)
    return np.uint8(np.clip(np.rint((n+1)*127.5),0,255))


def reference(spec, channel, size):
    path = ROOT/f"Tools/TerrainHD/{spec['world']}/authoring.json"
    recipe = json.loads(path.read_text())
    source = (path.parent/recipe["tiles"][spec["alias"]][channel]).resolve()
    with Image.open(source) as image:
        pixels = np.asarray(image.convert("RGB").resize((size,size),Image.Resampling.LANCZOS)).copy()
    repeat = spec.get("repeats",1)
    if repeat != 1:
        # Existing qualified independent tiles, not an atlas crop. Filter once
        # to the repeated cell before wrapping, preserving the normal basis.
        cell = max(1,size//repeat)
        image = Image.fromarray(pixels).resize((cell,cell),Image.Resampling.LANCZOS)
        pixels = np.tile(np.asarray(image),(repeat+1,repeat+1,1))[:size,:size].copy()
    return pixels, {"file":source.name,"sha256":signature(source)}


def apply(world, channel, by_type, bases, report, policy):
    settings = policy["worlds"][world]
    applied = report.setdefault("world_surface_art",{"schema":policy["schema"],"settings":settings,"references":{}})
    for type_id, spec in settings.get("types",{}).items():
        uid = by_type[int(type_id)]
        old = bases[uid]
        result = old.astype(np.float32)
        replacement = spec.get("replacement")
        if replacement and channel != "E":
            other, provenance = reference(replacement,channel,old.shape[0])
            applied["references"][f"{type_id}:{channel}"] = provenance
            weight = replacement["weight"]
            if channel == "D":
                # Keep the world's original RGB balance/mean; borrow physical
                # structure rather than importing another world's palette.
                other = other.astype(np.float32)*old.mean(axis=(0,1))/np.maximum(other.mean(axis=(0,1)),1)
            if channel == "N":
                result = normal(slopes(old)*(1-weight)+slopes(other)*weight).astype(np.float32)
            else:
                result = result*(1-weight)+other*weight
        if channel == "D":
            mean = result.mean(axis=(0,1),keepdims=True)
            result = mean+(result-mean)*spec.get("contrast",1.)
            neutral = result.mean(axis=2,keepdims=True)
            result = result*(1-spec.get("neutralMix",0.))+neutral*spec.get("neutralMix",0.)
            result *= spec.get("brightness",1.)
            # Deposited frost is explicit and local to Io's sulphur material;
            # it is a broad coverage field, never an albedo-derived height.
            if "frost" in spec:
                frost = spec["frost"]
                field = gaussian_filter(np.random.default_rng(frost["seed"]).normal(size=old.shape[:2]),old.shape[0]/24,mode="wrap")
                field /= max(float(field.std()),1e-8)
                mask = np.clip((field-frost["threshold"])/1.5,0,1)*frost["strength"]
                result = result*(1-mask[:,:,None])+np.asarray(frost["colour"])*mask[:,:,None]
        elif channel == "N" and spec.get("normalStrength",1.) != 1.:
            result = normal(slopes(np.uint8(np.clip(result,0,255)))*spec["normalStrength"])
        elif channel == "S" and "specularMaximum" in spec:
            result = np.minimum(result,spec["specularMaximum"])
        # Preserve all source E, including lava and the following base accents.
        if channel != "E":
            bases[uid] = np.uint8(np.clip(np.rint(result),0,255))
