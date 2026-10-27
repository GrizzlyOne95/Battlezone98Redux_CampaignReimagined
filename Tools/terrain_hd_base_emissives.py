"""Small UV-authored base status lights; no diffuse-derived emissive masks."""
import json
from pathlib import Path

SOURCE_HEIGHT_CORRECTIONS = {"europa": {"2fb5706a9216": "invert_xy"}}


def apply_source_height_corrections(world, channel, bases, report):
    if channel != "N":
        return
    corrections = SOURCE_HEIGHT_CORRECTIONS.get(world, {})
    for uid, operation in corrections.items():
        if operation != "invert_xy" or uid not in bases:
            raise ValueError("Source-height normal correction no longer matches the saved recipe")
        bases[uid][:, :, :2] = 255 - bases[uid][:, :, :2]
    report["source_height_corrections"] = corrections


def apply_base_emissives(world, channel, source_by_type, bases, report):
    if channel != "E":
        return
    import numpy as np
    recipe = json.loads((Path(__file__).parent / "TerrainHD/base_emissives.json").read_text())
    settings = recipe["worlds"][world]
    uid = source_by_type[settings["type"]]
    original = bases[uid]
    n = original.shape[0]
    y, x = (np.mgrid[0:n, 0:n].astype(np.float32) + .5) / n
    mask = np.zeros((n, n), np.float32)
    for u, v, width, height in settings["rectangles"]:
        distance = np.maximum(np.abs(x-u-width/2)-width/2, np.abs(y-v-height/2)-height/2)
        mask = np.maximum(mask, np.clip(.5-distance*n, 0, 1))
    # Source-authored E remains independent from albedo. Keep its locations,
    # reduce its intensity, then add these sparse authored UV status strips.
    retained = np.minimum(original.astype(np.float32) * recipe["sourceGain"], recipe["maximum"])
    accents = mask[:, :, None] * np.array(settings["color"], np.float32)
    bases[uid] = np.uint8(np.clip(np.maximum(retained, accents), 0, recipe["maximum"]))
    report["base_emissives"] = {"schema": recipe["schema"], "sourceId": uid,
                                 "maximum": recipe["maximum"], "sourceGain": recipe["sourceGain"],
                                 "settings": settings,
                                 "policy": "Independent source E plus sparse UV-authored status accents before variants/blends"}
