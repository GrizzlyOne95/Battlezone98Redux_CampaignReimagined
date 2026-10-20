"""CR art controls; runtime detail tuning is consumed by OpenShim's HD pack."""
import json
import math
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNTIME_DEFAULTS = {"microReliefScale": 1.0, "detailContrast": .55,
                    "detailNormalStrength": 2.2, "detailNormalNearScale": .55}
RUNTIME_LIMITS = {"microReliefScale": 4., "detailContrast": 1.,
                  "detailNormalStrength": 4., "detailNormalNearScale": 1.}


def validate_runtime(binding):
    result = {}
    for key, default in RUNTIME_DEFAULTS.items():
        value = binding.get(key, default)
        if type(value) not in (int, float) or not math.isfinite(value) or not 0 <= value <= RUNTIME_LIMITS[key]:
            raise ValueError(f"{key} must be finite within 0..{RUNTIME_LIMITS[key]}")
        result[key] = value
    return result


def binding_for(world, path=None):
    stems = {"moon": "MN", "mars": "MA", "venus": "VE", "io": "IO", "europa": "EU",
             "titan": "TI", "achilles": "AC", "ganymede": "GA", "elysium": "EL"}
    return json.loads((path or ROOT/"Config/cr_terrain_hd.json").read_text())["materials"][stems[world]+"_DETAIL_ATLAS"]


def surface_coverage(binding):
    value = binding.get("surfaceBlend", {}).get("coverage", 0.)
    if type(value) not in (int,float) or not math.isfinite(value) or not 0 <= value <= 1:
        raise ValueError("surfaceBlend.coverage must be finite within 0..1")
    return value


def surface_signature(world):
    binding = binding_for(world)
    spec = binding.get("surfaceBlend", {})
    if not surface_coverage(binding):
        return None
    if spec.get("recipe"):
        recipe = (ROOT/spec["recipe"]).resolve()
        if world != "moon" or not recipe.is_relative_to(ROOT) or not recipe.is_file():
            raise ValueError("Only the Moon custom generator supports surfaceBlend.recipe; other worlds need authored maps")
        return None  # Moon's explicit custom build owns its source/cache
    if not spec.get("mask") or set(spec.get("channels", {})) != set("DNSE"):
        raise ValueError("Enabled surfaceBlend needs independent mask/D/N/S/E images")
    files = {}
    for key, relative in {"mask":spec["mask"], **spec["channels"]}.items():
        path = (ROOT/"Config"/relative).resolve()
        if not path.is_relative_to(ROOT):
            raise ValueError("Surface authoring path must stay inside the CR checkout")
        files[key] = hashlib.sha256(path.read_bytes()).hexdigest()
    return {"settings": spec, "inputSha256": files}


def blend_channel(original, overlay, mask, channel):
    """Blend independent authored maps; leave unmasked HD pixels identical."""
    import numpy as np
    weight = mask[:, :, None]
    if channel == "N":
        a, b = original.astype(np.float32)/127.5-1, overlay.astype(np.float32)/127.5-1
        slopes = a[:, :, :2]/np.maximum(a[:, :, 2:3], .01)*(1-weight) + b[:, :, :2]/np.maximum(b[:, :, 2:3], .01)*weight
        normals = np.concatenate((slopes, np.ones((*mask.shape,1),np.float32)), axis=2)
        normals /= np.linalg.norm(normals,axis=2,keepdims=True)
        result = np.uint8(np.clip(np.rint((normals+1)*127.5),0,255))
    else:
        result = np.uint8(np.clip(np.rint(original.astype(np.float32)*(1-weight)+overlay*weight),0,255))
    result[mask == 0] = original[mask == 0]
    return result


def apply_authored_surface(world, channel, source_by_type, bases, report):
    """Optional independent mask/DNSE paths in Config/cr_terrain_hd.json.

    Moon's procedural recipe is consumed by Build-MoonRegolith instead. A
    nonzero coverage alone never fabricates an overlay for any world's surface.
    """
    binding = binding_for(world)
    spec = binding.get("surfaceBlend", {})
    coverage = surface_coverage(binding)
    if not coverage:
        return
    surface_signature(world)
    if spec.get("recipe"):
        return
    import numpy as np
    from PIL import Image
    kind = spec.get("sourceType", 0)
    if type(kind) is not int or kind not in source_by_type:
        raise ValueError("surfaceBlend needs a valid sourceType and independent mask/D/N/S/E images")
    source = bases[source_by_type[kind]]
    def load(relative, mode):
        path = (ROOT/"Config"/relative).resolve()
        if not path.is_relative_to(ROOT):
            raise ValueError("Surface authoring path must stay inside the CR checkout")
        with Image.open(path) as image:
            if image.size != (source.shape[1],source.shape[0]):
                raise ValueError("Surface blend images must match independent source tile dimensions")
            return np.array(image.convert(mode))
    mask = load(spec["mask"], "L").astype(np.float32)/255*coverage
    overlay = load(spec["channels"][channel], "RGB")
    bases[source_by_type[kind]] = blend_channel(source, overlay, mask, channel)
    report["surface_blend"] = spec
