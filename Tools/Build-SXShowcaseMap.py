#!/usr/bin/env python3
"""Rebuild the text-only Livewire map from the canonical setup world.

No terrain codec or binary assets are involved. Review the BZN diff after use.
The original tank becomes the authored user craft so the cockpit chapter has
real meters. The original pilot becomes an NPC; no scripted SetAsUser is used.
"""
import argparse
import re
from pathlib import Path

# Staging was re-laid from an in-game terrain survey (GetTerrainHeightAndNormal on a
# 20 m grid). The AI arena sits on the flat 117 m bench east of the central cliff, so
# both lanes and their targets share level ground; the destruction yard is the flat
# 131 m plateau. Camera routes ride 2.5-4 m above terrain and stay off cliff lips.
POINTS = {
    "control": (4138, 99142), "changed": (4138, 99166), "convoy": (4225, 99230),
    "weather_anchor": (4145, 98820), "ai_anchor": (4700, 98720),
    "break_anchor": (4510, 98600), "filter_anchor": (4200, 98295),
    "ai_stock": (4630, 98760), "ai_tuned": (4675, 98760),
    "ai_target_a": (4630, 98960), "ai_target_b": (4675, 98960),
    # Ten craft from all three factions, then three barracks, in kill order.
    **{f"break_{i + 1}": (4470, 98470 + 20 * i) for i in range(10)},
    "break_b1": (4482, 98690), "break_b2": (4482, 98725), "break_b3": (4482, 98760),
    "break_look": (4475, 98880),  # fixed aim point past the line; the pan stays smooth
    "shield": (4115, 98235), "shield_power": (4080, 98235),
    "shield_ally": (4127, 98165), "shield_enemy": (4127, 98135),
    "magnet": (4290, 98235), "magnet_ally": (4298, 98165), "magnet_enemy": (4298, 98135),
    "prox_enemy": (4155, 98375), "pe_ally": (4142, 98325), "pe_enemy": (4168, 98325),
    "prox_ally": (4245, 98375), "pa_ally": (4258, 98325), "pa_enemy": (4232, 98325),
    "radio": (4195, 98920), "pe_ally_exit": (4142, 98425), "pa_enemy_exit": (4232, 98425),
}
ROUTES = {
    "arrive": [(4160, 99258), (4140, 99250), (4115, 99232), (4105, 99205), (4112, 99180)],
    "mat_a": [(4156, 99134), (4152, 99146), (4152, 99162), (4156, 99178)],
    "convoy_route": [(4225, 99230), (4190, 99205), (4158, 99195)],
    "weather": [(4210, 98890), (4190, 98850), (4170, 98820), (4120, 98790), (4090, 98820)],
    "break": [(4445, 98400), (4445, 98600), (4445, 98790)],
    "ai_chase": [(4652, 98712), (4652, 98790)],
    "ai_front": [(4685, 98915), (4615, 98915)],
    "ai_side": [(4606, 98800), (4606, 98900)],
    "fil_shield": [(4150, 98205), (4152, 98245)],
    "fil_magnet": [(4268, 98200), (4266, 98240)],
    "fil_prox": [(4200, 98300), (4200, 98345)],
    "radio_cam": [(4165, 98945), (4195, 98950), (4214, 98925), (4214, 98895)],
    "radio_route": [(4195, 98920), (4225, 98900), (4240, 98885)],
    "radio_return": [(4240, 98885), (4225, 98900), (4195, 98920)],
    # Shield and magnet are pursuits: the friendly escapes down one lane and an
    # enemy chases it into the enemy-only field.
    "shield_ally_run": [(4127, 98165), (4127, 98235), (4127, 98320)],
    "shield_enemy_run": [(4127, 98135), (4127, 98235), (4127, 98320)],
    "magnet_ally_run": [(4298, 98165), (4298, 98235), (4298, 98320)],
    "magnet_enemy_run": [(4298, 98135), (4298, 98235), (4298, 98320)],
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
    # CRLF, as .gitattributes checks BZNs out: the Redux text BZN reader rejects an
    # LF-only file ("Quiting Game because failed to load game files", no other error).
    output.write_text(build(source.read_text(encoding="utf-8-sig")), encoding="utf-8", newline="\r\n")
    print(f"Wrote {output}: 32 objects, {14 + len(POINTS) + len(ROUTES)} paths; shared crsetup terrain.")
