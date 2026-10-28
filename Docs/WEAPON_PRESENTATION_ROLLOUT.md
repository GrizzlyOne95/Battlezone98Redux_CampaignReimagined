# Stock BZR / CR weapon presentation: first pass

2026-10-21, owner direction: work through stock and CR weapons with tailored
muzzle flashes; miniguns blue, chainguns orange-red. Inventory recoil options
across tanks, light tanks, bombers, walkers and other combat units.

## Inventory and delivered content

The casing follow-up assigns all 100 weapons an explicit `[WeaponClass]`
`casingType`: 11 small, four medium, ten large, and 75 none. Miniguns,
chainguns and the sniper get small brass; AT-Stabbers medium; SP/CP-Stabbers
and howitzers large. Plasma/arc/energy weapons, launchers, grenades, mines and
utilities eject none. These are initial cosmetic art choices for review.
Lengths are 0.12/0.24/0.40 using the native generated casing mesh scale.
The existing per-weapon casing mesh override remains available.

`Tools/Build-WeaponCasings.py` owns only its marked casing block. All 100
complete ODFs are checked against parsed gameplay baselines; 21 additional
stock overrides are listed in the shipping lock with no removals. Both
generators are independently repeatable. Inventory JSON/CSV includes casing
type and reason alongside the flash choice.

Requires companion OpenShim `agent/casing-flash-coexistence` and the existing
ShellCasings switch ON; defaults stay OFF. That change shares the native
accepted-shot dispatcher with flashes and reads casing types once at the
live ODF scope seam, without per-shot file reads. The authored casingType
scope is qualified statically only for exact GOG 2.2.301; other builds use
the native conservative stock allowlist. Flash activation still has its
existing single-player guard, so this does not claim CR co-op flash support.
Ejection uses each weapon's native mount matrix and estimated breech offset;
per-craft ejection-port fitting and live testing remain pending.

`ODF/gminigun.odf` documents the optional `casingMesh = "mymod_brass.mesh"`
override as commented lines inside the generated casing block. The generator
retains these notes from the manifest. A rigid unit-length Ogre mesh along local
+Z is uniformly scaled by casingType and uses its own material names. Ship the
case-sensitive mesh resource and dependencies with the mod. Missing/empty keys
retain the `<weapon>_casing.mesh` convention/default; an explicit missing or
invalid mesh suppresses the casing. It requires the companion exact-GOG scope.
The native generated brass finish now uses textured stock BZBase lighting,
machined rims, an inset primer and a dark hollow mouth. Live appearance remains
pending; an offline study is not a game screenshot.
For generated CR content, set a weapon's `casing_mesh` in
`References/WeaponPresentation/profiles.json` and run `Build-WeaponCasings.py`
to retain an active selection across regeneration.

The inventory covers all 73 weapon definitions in the installed GOG stock ODF
archive, overlaid with CR's current ODFs: **100 effective weapon definitions**.
The stock extracted directory was cross-checked against all 796 `bzone.zfs`
ODF members; all 73 WeaponClass definitions were present. This includes unused,
special and variant definitions, rather than assuming a weapon is unused because
its name does not begin with `g`. It is a definition inventory, not a proof of
mission reachability or arbitrary external mod coverage.

There are **174 weapon-equipped definitions / 61 models / 330 slots**: 159
combat carriers (including pilots and armed structures) and 15 armories that
supply weapons but do not fire them. `References/WeaponPresentation/inventory.json`,
`weapons.csv` and `recoil.csv` contain the complete inventory. Re-run with:

```powershell
python Tools/Inventory-WeaponPresentation.py --stock '<game>/StockODFFiles' --output '<report directory>'
```

**74 weapon ODFs now select authored flashes**, with 20 separate mesh/material
profiles. The other 26 definitions have an explicit reason for omission: supply
or mine deployment, countermeasures, cloak/radar/camera devices, paintball/debug,
ground-contact Thumper/anchor effects, or a utility projectile whose existing
effect is retained. A mine's trigger is not treated as a craft muzzle.

| Family | Art direction |
| --- | --- |
| Minigun, variants, turret minigun | Short narrow blue jet, pale blue-white core, 45 ms |
| Chaingun, variants, turret chaingun | Wider split orange-red plume, warm core, 55 ms |
| AT-Stabber | Amber directional gas jet, 85 ms |
| SP/CP-Stabber | Larger crown with a hotter pale core, 95 ms |
| CCA Pulse Stabber | Compact orange pulse, 60 ms |
| Blast cannon variants | Broad crown; green, blue or red presets, 90 ms |
| Bolt/arc/flash families | Thin forked blue, green or red discharge, 55 ms |
| Rockets and guided launchers | Longer warm launch jet, 100 ms |
| Mortars/howitzers/splinter | Broad short pressure crown, 120 ms |
| Infantry plasma / Fury pulse | Compact faction-coloured pulse, 60 ms |
| MAG, sniper, popper, Olympian arc | Separate violet pulse, narrow blue needle, warm crown and gold arc profiles |

The colour choices beyond the owner's minigun/chaingun direction are initial
art choices for review, not recovered stock muzzle colours. Profiles differ in
geometry, radial shape, petal count, duration and gas animation; this is more
than tinting/scaling one universal mesh. A shared original EXU flame mask and
LGPL shader provide hot-core/gas breakup, per-shot variation and pause-aware
phase. Provenance, original prompt, source revision and input hashes are in
`References/WeaponPresentation/provenance.json`. No new third-party game model
or texture was imported. Each profile has its own CR resource names.

`Build-WeaponFlashes.py` writes meshes using the shared Toolbox codec and adds
only marked presentation fields to complete ODF overrides. Gameplay baselines
pin every original field, including ammo, delay, ordnance, sounds, damage-related
references and inheritance. Existing projectiles/effects remain. No ship loadout
or recoil configuration was changed. Existing example comments remain comments.

## Runtime coverage and fitting limits

The companion OpenShim change adds the separately qualified MachineGun accepted
shot call to the existing factory bridge. It preserves the original factory
return, owner/matrix arguments and lifecycle/ODF gates. No extra unit scan or
Lua per-shot callback is introduced. Existing cannon handling also covers the
Mortar and SniperGun simulation implementations that use the same stock path.

| Selected flash ODFs | Runtime state |
| --- | --- |
| 30 cannon + 10 mortar + 1 sniper | Existing accepted-shot path; these new assets and individual weapons still need live fitting/visual tests |
| 15 machinegun | New accepted-shot producer compiled and host-tested; live activation/visual test pending |
| 9 beam + 2 thermal + 2 targeting + radar + image + charge + detonator + popper (18 total) | Art/ODFs prepared; separate accepted-fire producers not added in this pass |

Current native scope stays exact-GOG 2.2.301 **single-player**. OpenShim Video >
Muzzle Flashes must be enabled and the matching EXU loaded; the setting still
defaults OFF and requires restart. This does not enable flashes in CR co-op.
Steam/Proton/Wine execution, other weapon producers and multiplayer remain
separate runtime qualification work. DX9/DX11 shader compilation is not proof
of those game/runtime lanes.

Shared weapons use **zero extra muzzle offset** (`flashOffset = "0 0 0"`). The
stock tank's `0.20 0.10 2.41` trial correction is never applied to every carrier
of gatstab; some models place firing hardpoints behind their visible tips.

### Per-craft flash offsets (offset policy)

Craft ODFs carry the correction instead, using OpenShim's
`[CraftClass] flashOffset<N> = "right up forward"` (N = weapon slot 1..5, metres,
|v| <= 20), which replaces the weapon's offset for that craft's slot only.
`References/WeaponPresentation/craft-flash-offsets.json` records, for every CR
craft slot whose `weaponName<N>` selects a weapon with `flashMesh`, either a
measured offset or the reason it has none. `Tools/Build-WeaponFlashes.py` writes
the keys inside a `// CR CRAFT FLASH OFFSET BEGIN/END` block directly under
`[CraftClass]`; `--check` (also run by `Tools/Test-WeaponPresentation.py` and CI)
fails if a craft or slot is missing from the data, a weapon selection changed
without re-measuring, or the ODF block differs.

Measurement (`python Tools/Build-WeaponFlashes.py --measure`, needs the installed
game's Ogre meshes and skeletons via `BZR_GAME_DIR`; shipped `Assets/ModelFixes`
meshes win): the hardpoint's parent must be a dedicated barrel node (`*BG?`);
the barrel is every vertex weighted at least 0.5 to that bone. The sim hardpoint
shares its barrel's frame, so vertices are expressed in the barrel frame relative
to the hardpoint position. Forward is the furthest barrel vertex; right/up is the
centre of the bounding box of the front 0.25 m (the aperture), rounded to
0.01 m. This reproduces the live avtank fit exactly (`0.20 0.10 2.41`) and is
consistent with the legacy-GEO estimates in the inventory (the inventory's value
is a forward distance from the older collision GEO; the Ogre mesh is what is
drawn, so it is used for lateral and vertical too).

A hardpoint whose parent is a hull, turret, arm or pod rather than a dedicated
barrel gets `0.00 0.00 0.00`, so the flash draws at the hardpoint, where the shot
spawns (OpenShim draws no vehicle flash at all without a key). That is only
right at the muzzle face (`avfigh`/`svfigh` GC1/GC2 are 3-7 cm behind the front
geometry), so the parent's geometry within 0.25 m right/up of the hardpoint, in
the parent's frame, must end between 0.1 m behind and 0.3 m ahead of it. 74
slots pass (mostly fighters, Chinese and Soviet tanks, turrets). The rest are
skipped with the reason: buried (39, e.g. `avlamp` 2.66 m, the `avsav` family
2.27 m, `svtank` slot 2 1.46 m), floating ahead of the hull (10, e.g. `svsav`
17.3 m, `svrckt` slot 3 0.74 m), or no parent geometry near the hardpoint (47).
The JSON row says `anchor` instead of `barrel`; the per-family fitting pass
below can replace it.

Not emitted (listed in the JSON with the reason): pilots (32 slots, no
`[CraftClass]`; they use the weapon's own `flashOffset`), hardpoint bones not present in the
Ogre skeleton (10), hardpoints already at the tip (under 0.1 m: Soviet howitzers
`svartl`/`svarmp`/`svartla`, and `bvhraz` slot 1 whose barrel mesh ends behind
its hardpoint), and the skipped hull hardpoints above.
Re-run `--measure` after changing a craft's weapons, hardpoints or model.
Offsets are fitted from geometry, not yet confirmed live except avtank.

## Recoil opt-in: craft node, weapon kick

OpenShim recoil is opt-in on both sides, so a slot never recoils by accident:

- The **craft** supplies the node, distance and return: `recoilName<N>`,
  `recoilDistance<N>`, `recoilReturn<N>` in `[CraftClass]`. These are enabled on
  avtank, avtamp, avdemo, bvtank, bvtanka, svtank, svtanka, svtas8, svtk13 and
  svtnk7 (slot 1 cannon barrel).
- The **weapon** supplies the kick: `[WeaponClass] recoilKick` (float 0..4, absent
  means 0 and no recoil). The node slides `recoilDistance<N>` x kick metres.
- `recoilKick<N>` in the craft's `[CraftClass]` overrides the weapon's kick for
  that slot, for example a scout's miniguns at 0.15 (see the commented example in
  `avtank.odf`).

CR gives `recoilKick = 1.0` to every cannon-category weapon (`wpnCategory = "CANN"`)
whose `classLabel` is not `machinegun`: the slot-1 defaults gatstab, gspstab,
gsatstab and ga7stab plus every other CANN weapon the armory could swap into those
slots (stabber variants, blast, bolt, flash, MAG, sniper, plasma rifles and the
Fury/Olympian arcs). Machineguns and miniguns get no kick. The block is generated
between `// CR WEAPON RECOIL BEGIN` and `// CR WEAPON RECOIL END` by
`Tools/Build-WeaponFlashes.py`; `--check` and `Tools/Test-WeaponPresentation.py`
fail on drift, on a recoil slot whose default weapon has no kick, and on any
machinegun with a kick. Muzzle flashes are separate: a craft shows a mesh flash
only for slots with a `flashOffset<N>` key (see the flash offsets section).

## Recoil setup inventory

Legacy topology inspection found **56 slot candidates on 17 distinct dedicated
barrel nodes**. These are candidates, not 56 proven runtime bindings. It rejects
whole hulls/turrets/locomotion nodes as automatic recoil choices. Existing position
tracks are checked for changing translation; aiming rotations must stay live.
All 61 models resolve through the shipping lock's resource mapping (including
Assets/ModelFixes), then stock fallbacks. Cockpit hardpoints and actual Ogre
clips are recorded separately. A stock `Take_001` clip is not assumed
to be an authored firing recoil clip.

| Unit family | Concrete setup / remaining work |
| --- | --- |
| NSDF tank, Black Dog tank variants | `AGR11BGA` / `bGR11BGA` are separate barrel candidates. Existing avtank node trial: 0.30 m kick / 2.5 m/s return. Revalidate every model/slot; inspect cockpit separately. |
| CCA tank variants | `SCZ11BGB` is the barrel candidate. Slots can share this barrel; avoid conflicting settings and don't mistake Thumper for a firearm. Shorter initial kick than the NSDF cannon is appropriate for the rapid pulse cycle. |
| Turrets / assault units | Several separate `BGA/BGB/BGC` assemblies appear in the CSV. Bind only the actual fired slot's barrel and retain its aim axes. |
| NSDF light tank / Black Dog equivalent | GC1 belongs to the hull, not a dedicated barrel. The side gun and launcher need deliberate mesh-weight/bone grouping and an additive helper/clip. Never slide the entire hull. |
| CCA / CRA light tanks | GC1 is on a turret or integrated hull/head. Author a recoil parent for the actual gun or a restrained firing clip after mesh inspection. |
| NSDF / Black Dog walkers | GC1 and GC2 are on separate aimed arm assemblies (`age11tx2/tx1` or equivalents). Author separate left/right recoil helpers/clips, preserving shoulder aim and the walking rig. Don't restart one shared clip that recoils both arms for either shot. |
| CCA / CRA walkers | Both GC muzzles can be on the same head. Separate weighted gun helpers are needed to avoid jerking the whole head/legs. Existing animated translation makes blind node sliding unsuitable. |
| NSDF / CCA bombers | Current weapons use rocket hardpoints, often on integrated roof/hull structure. Prefer short nozzle/launcher compression or launch effects; a cannon-style sliding hull would be incorrect. |
| Howitzers | Separate cannon assemblies are candidates where present. Coordinate deployed/aiming pose and long shell cycle; packed/unpacked model changes require lifecycle testing. |
| Fighters, scouts, missile tanks, Fury units | Follow the exact hardpoint parent in the CSV. Integrated pods require a deliberate helper/clip or no physical slide; beams/launchers also need their own accepted-fire observation. |
| Pilots | Existing `fireRecoilSniper` and movement clips are recorded. Preserve the person/FPS animation controller; do not treat a pilot as a vehicle node-slide target. |
| Armories and utility slots | Supplier/utility records stay in the inventory but do not receive firearm recoil. |

## Checks and next work

- All 20 generated meshes round-trip byte-for-byte through the shared codec.
- All four shader stages compile: DX11 vs/ps 4.0 and DX9 vs/ps 3.0.
- Content checks cover all 100 decisions, required minigun/chaingun colours,
  resource links, correct ODF sections and unchanged gameplay baselines for all
  74 edited/added weapon definitions. The generator's `--check` passes.
- Repository invariants pass. CI runs the content checks. Shipping adds only
  new weapon overrides and their resources; the bless refused 50 missing generated
  UI files, so new membership was inserted in place per knowledge-base section 3.8.
- Companion native Release Win32 build and all 136 Windows CTests pass; static
  qualification checks 15 sites, four call targets and five instruction steals.
  Observer tests cover the added machinegun caller and fail-closed capture.

**Live testing pending.** No active game, installed config, release payload or
Workshop publication was changed. This is a first authored content/inventory
checkpoint, not completed visual qualification for every weapon. Next: fit and
review minigun/chaingun/AT-Stabber on representative craft; establish machinegun
live proof; add the other accepted-fire producers; visually confirm the per-craft
flash offsets live (needs the OpenShim `flashOffset<N>` build) and fit the unmeasured
hull-mounted hardpoints; then author and test recoil rigs family by family. Keep
the current setting/build/network guards until the relevant evidence exists.
