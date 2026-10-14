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
    "control": (4146, 99160), "changed": (4136, 99160), "mat_look": (4141, 99130), "storm_look": (4030, 99175), "convoy": (4225, 99230),
    "weather_anchor": (4145, 98820), "ai_anchor": (4620, 98900),
    "break_anchor": (4510, 98600), "filter_anchor": (4200, 98295),
    # Fighter duels 80 m apart on the wide north end of the AI bench (stock west,
    # tuned east); each fixed target turret stands 120 m north of its fighter.
    "ai_look": (4620, 98990), "ai_stock": (4580, 98900), "ai_tuned": (4660, 98900),
    "ai_target_a": (4580, 99020), "ai_target_b": (4660, 99020),
    # Destruction plateau (x 4380-4620, z 98450-98800 is level to 0.6 m): four
    # clusters, each with a camera anchor at its centre.
    "brk_armor": (4440, 98520), "brk_avtank": (4430, 98522), "brk_svtank": (4446, 98516),
    "brk_cvtank": (4458, 98526), "brk_avrckt": (4424, 98536), "brk_svltnk": (4440, 98538), "brk_cvfigh": (4455, 98542),
    "brk_walk": (4540, 98540), "brk_avapc": (4533, 98528), "brk_avwalk": (4524, 98548),
    "brk_svapc": (4550, 98530), "brk_svwalk": (4541, 98556), "brk_cvwalk": (4558, 98548),
    "brk_comm": (4470, 98700), "brk_abcomm": (4425, 98706), "brk_sbcomm": (4470, 98714), "brk_cbcomm": (4515, 98706),
    "brk_base": (4560, 98640), "brk_abtowe": (4542, 98618), "brk_sbtowe": (4560, 98612), "brk_cbtowe": (4578, 98618),
    "brk_abspow": (4548, 98648), "brk_abhqcp": (4578, 98656),
    # Pilot deaths on the plateau's north end: four standing pilots, three soldiers
    # who run east across the frame and fall at their marks.
    "gib_look": (4420, 98900), "gib_aspilo": (4415, 98903), "gib_bspilo": (4418, 98904),
    "gib_cspilo": (4422, 98904), "gib_sspilo": (4425, 98903),
    "gib_assold": (4400, 98898), "gib_sssold": (4396, 98901), "gib_cssold": (4392, 98904),
    "gib_mark_1": (4414, 98898), "gib_mark_2": (4421, 98901), "gib_mark_3": (4428, 98904),
    "shield": (4115, 98235), "shield_power": (4080, 98235),
    "shield_ally": (4127, 98165), "shield_enemy": (4127, 98135),
    "magnet": (4290, 98235), "magnet_ally": (4298, 98165), "magnet_enemy": (4298, 98135),
    "prox_enemy": (4155, 98375), "prox_look": (4155, 98370), "pe_ally": (4142, 98325), "pe_enemy": (4168, 98325),
    "prox_ally": (4245, 98375), "pa_ally": (4258, 98325), "pa_enemy": (4232, 98325),
    "radio": (4195, 98920), "pe_ally_exit": (4142, 98425), "pa_enemy_exit": (4232, 98425),
}
ROUTES = {
    "arrive": [(4160, 99258), (4140, 99250), (4115, 99232), (4105, 99205), (4112, 99180)],
    "convoy_route": [(4225, 99230), (4190, 99205), (4158, 99195)],
    "gib_run_1": [(4400, 98898), (4446, 98898)],
    "gib_run_2": [(4396, 98901), (4446, 98901)],
    "gib_run_3": [(4392, 98904), (4446, 98904)],
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
