#!/usr/bin/env python3
"""Rebuild the text-only Livewire map from the canonical setup world.

No terrain codec or binary assets are involved. Review the BZN diff after use.
The original tank becomes the authored user craft so the cockpit chapter has
real meters. The original pilot becomes an NPC; no scripted SetAsUser is used.
"""
import argparse
import re
from pathlib import Path

POINTS = {
    "control": (4138, 99142), "changed": (4138, 99166), "convoy": (4225, 99230),
    "weather_anchor": (4145, 98820), "ai_anchor": (4520, 98165),
    "break_anchor": (4510, 98600), "filter_anchor": (4200, 98295),
    "ai_stock": (4480, 98095), "ai_tuned": (4480, 98235),
    "ai_target_a": (4660, 98095), "ai_target_b": (4660, 98235),
    "break_craft": (4490, 98585), "break_building": (4540, 98620),
    "shield": (4115, 98235), "shield_power": (4080, 98235),
    "shield_ally": (4100, 98175), "shield_enemy": (4130, 98175),
    "magnet": (4290, 98235), "magnet_ally": (4265, 98175), "magnet_enemy": (4315, 98175),
    "prox_enemy": (4155, 98375), "pe_ally": (4142, 98325), "pe_enemy": (4168, 98325),
    "prox_ally": (4245, 98375), "pa_ally": (4258, 98325), "pa_enemy": (4232, 98325),
    "radio": (4195, 98920), "pe_ally_exit": (4142, 98425), "pa_enemy_exit": (4232, 98425),
}
ROUTES = {
    "arrive": [(4255, 99212), (4230, 99225), (4195, 99220), (4160, 99207), (4130, 99192)],
    "mat_a": [(4110, 99140), (4120, 99130), (4145, 99128), (4165, 99140), (4172, 99160)],
    "convoy_route": [(4225, 99230), (4190, 99205), (4158, 99195)],
    "weather": [(4210, 98890), (4190, 98850), (4170, 98820), (4120, 98790), (4090, 98820)],
    "break": [(4430, 98640), (4450, 98645), (4485, 98655), (4555, 98665), (4590, 98630)],
    "radio_cam": [(4150, 98965), (4170, 98970), (4210, 98965), (4245, 98940), (4240, 98900)],
    "radio_route": [(4195, 98920), (4225, 98900), (4240, 98885)],
    "radio_return": [(4240, 98885), (4225, 98900), (4195, 98920)],
    "shield_ally_run": [(4100, 98175), (4100, 98235), (4100, 98295)],
    "shield_enemy_run": [(4130, 98175), (4130, 98235), (4130, 98295)],
    "magnet_ally_run": [(4265, 98175), (4265, 98235), (4265, 98295)],
    "magnet_enemy_run": [(4315, 98175), (4315, 98235), (4315, 98295)],
    "pe_ally_run": [(4142, 98325), (4142, 98375), (4142, 98425)],
    "pe_enemy_run": [(4168, 98325), (4168, 98375), (4168, 98425)],
    "pa_ally_run": [(4258, 98325), (4258, 98375), (4258, 98425)],
    "pa_enemy_run": [(4232, 98325), (4232, 98375), (4232, 98425)],
}


def build(source):
    head, body = source.split("[GameObject]\n", 1)
    body, tail = body.split("\nname = LuaMission\n", 1)
    objects = body.split("[GameObject]\n")
    kept, removed = [], 0
    for obj in objects:
        if re.search(r"(?m)^team \[1\] =\n5$", obj):
            assert "PrjID [1] =\navtur2b\n" in obj, "source enemy set changed"
            removed += 1
            continue
        if "label = asuser0_person\n" in obj:
            obj = obj.replace("isUser [1] =\n1\n", "isUser [1] =\n0\n", 1)
        elif "label = fake_player\n" in obj:
            obj = obj.replace("isUser [1] =\n0\n", "isUser [1] =\n1\n", 1)
            obj = obj.replace("label = fake_player\n", "label = sx_player\n", 1)
        kept.append(obj.rstrip())
    assert removed == 7 and len(kept) == 32, "source object inventory changed"
    head = head.replace("msn_filename = crsetup.bzn", "msn_filename = sxshow.bzn")
    head = re.sub(r"size \[1\] =\n\d+", "size [1] =\n32", head, count=1)
    paths = {"sx_" + key: [point] for key, point in POINTS.items()}
    paths.update({"sx_" + key: route for key, route in ROUTES.items()})
    old_count = int(re.search(r"\[AiPaths\]\ncount \[1\] =\n(\d+)", tail).group(1))
    tail = re.sub(r"(\[AiPaths\]\ncount \[1\] =\n)\d+", lambda m: m.group(1) + str(old_count + len(paths)), tail, count=1)
    additions = []
    for index, (label, points) in enumerate(paths.items(), 0x100):
        block = f"[AiPath]\nold_ptr = {index:08X}\nsize [1] =\n{len(label)}\nlabel = {label}\npointCount [1] =\n{len(points)}\npoints [{len(points)}] =\n"
        for x, z in points:
            block += f"  x [1] =\n{x}\n  z [1] =\n{z}\n"
        additions.append(block + "pathType = 00000000")
    return head + "[GameObject]\n" + "\n[GameObject]\n".join(kept) + "\nname = LuaMission\n" + tail.rstrip() + "\n" + "\n".join(additions) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--reference-root", type=Path)
    args = parser.parse_args()
    source = (args.reference_root or args.root) / "Missions/crsetup.bzn"
    output = args.root / "Missions/sxshow.bzn"
    output.write_text(build(source.read_text(encoding="utf-8-sig")), encoding="utf-8", newline="\n")
    print(f"Wrote {output}: 32 objects, {14 + len(POINTS) + len(ROUTES)} paths; shared crsetup terrain.")
