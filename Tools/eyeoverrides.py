"""Cockpit eyes CR moves away from stock. Only the skeleton POV bone moves; no other part does.

Redux takes the cockpit camera from the skeleton POV bone, verified live 2026-11-09: swapping
only the VDF eyepoint left the view identical to stock, swapping only the skeletons moved it.
(1.5 reads the VDF eyepoint instead: Battlezone_Source BZ1/1.5/all_decompiled.c:152449.)
The VDF eyepoint stays stock, so anything else that still reads it is unchanged; which Redux
code that is (sniper zoom, AI sight) is UNVERIFIED. Every skeleton builder that reads a stock
rig (Build-WeaponRigs.py, Build-CombatCockpits.py) applies the move via patch_skeleton().
"""
import weaponrigs as wr

# model -> (POV bone, new local position under its stock parent)
EYES = {
    # Back to the sloped canopy windows on the spine: 0.22 m lower, 1.5 m back from stock.
    'svfigh': ('SFL11POV', (0.0, 0.61, -0.35)),
    # Scouts: 0.35 m up, so the rolling ROF nose reads over its hull bulkhead.
    'avfigh': ('ARA11POV', (0.0044, 1.15, 0.5)),
    'bvraz': ('bRA11POV', (0.0044, 1.15, 0.6078)),
    # CZar (owner review, Total Command layout idea): the pilot's head is in a small hatch on
    # the deck nose just behind the muzzle, ~0.15 m above the real deck (vehicle 0.12, 1.62, 3.10).
    # The real barrel stays where shots leave it (VDF hardpoint) and runs overhead; the deck
    # nose frames the bottom of the view.
    'svtank': ('SCZ11POV', (0.1360, 0.291, 2.472)),
}


def patch_skeleton(model, raw):
    """Stock skeleton bytes with the model's POV bone moved; unchanged bytes if no override."""
    if model not in EYES:
        return raw
    name, pos = EYES[model]
    skel = wr.read_skeleton(raw)
    bone = skel.bone(name)
    assert bone is not None, (model, name)
    assert not [b for b in skel.bones if b.parent == bone.handle], (model, name, 'POV has children')
    assert not [t for a in skel.animations for t in a.tracks if t.bone == bone.handle], (model, name, 'POV is animated')
    bone.position = tuple(pos)
    return wr.write_skeleton(skel)
