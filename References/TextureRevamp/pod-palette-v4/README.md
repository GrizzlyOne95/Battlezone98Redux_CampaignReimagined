# Stock pods — actual-faction palette and unique-lamp pass

Owner direction supersedes the v3 pod colours, not its stock silhouettes or
complete UV unwrap. NSDF's olive shell did not match its vehicle/building art;
the repeated blue-ammo/green-repair luminous wraps also lacked faction identity.
This is still an **offline-only art checkpoint**, with no game deployment.
The pod pass leaves geometry, ODFs, native companions and gameplay unchanged.
The owner then requested this direction on navs/weapons as a **new pass**;
see `../nav-weapons-v4/README.md` for that explicitly authorized nav revision.

## Actual references and authoring choices

Four real building/vehicle diffuse atlases per faction are in the labelled
`*-actual-references.jpg` sheets. Their matching real E maps are separately
shown in `*-actual-emission.jpg`. `references.json` records the resolved active
materials, source names, paths and SHA-256 pins; these are not guessed legacy
texture names. Each pair includes two vehicles, a factory and a power building.
NSDF's fighter uses the current CR texture override; other selected diffuse
inputs are from the extracted GOG stock tree.

| Faction | Shell/markings anchored to references | Authored lamp identity |
|---|---|---|
| NSDF | Petrol blue-green, graphite and off-white tactical paint / white star | Thin paired ice-cyan rails; teal/cyan repair service rails |
| Black Dog | Dark blue-charcoal, crimson markings and dog badge | Amber-orange triple slashes for ammo; segmented ladder service lamps |
| CCA | Aged ivory, dark blue-grey insets and red tactical markings / star | Broad red-orange/amber-core ammo optics; paired golden-amber repair lamps |
| CRA | Weathered ochre-khaki/olive, warm charcoal and red tactical blocks / yellow star | Turquoise bracket/dot ammo optics; grouped raked lime service ticks |

These are deliberate new pod lamp arrangements informed by the references,
not a claim that each stock faction has only one exclusive light hue. For
example Black Dog buildings still select some shared NSDF E resources, despite
warmer-looking diffuse lamps. Stock references contain mixed status colours.
The new amber Black Dog pod identity is an authored distinction, not a recovered
engine requirement. Pickup shape and tool pictogram retain type readability.

## Runtime candidate / technical contracts

Built-in ImageGen edits the eight existing diffuse atlases using each faction's
actual reference sheet. `prompts.json` preserves every prompt/input role. New
`cram??4-master.png` / `crhp??4-master.png` preserve exact v3 island outlines and
locations; old v3 masters remain historical and byte-pinned. No new UV unwrap,
procedural paint, geometry, shader or native-light work is involved.

`Build-FactionNavPickups.py` resamples/extrudes gutters, extracts bright authored
lamp-glass colours within chart coverage and outside badge regions, then writes
the existing 1024px D/E resources with complete BC1 mip chains. It does not draw
the unique patterns or recolour them with a global material tint. Insignia and
broad shell paint stay nonemitting. Every pod keeps one material batch.
The later owner-requested hazard pass reuses the matching faction's authored
weapon warning pixels on ammo upper-shell trim and repair outer-rim trim.
Original pod masters stay unchanged; compiler strip reuse precedes gutter
extrusion. Ammo's complete front badge and all optical strips are spared.
Warning paint stays explicitly nonemitting; no extra atlas or batch is added.

The tests retain geometry/rig, original ODF/menu behavior, complete UV coverage,
accepted nav and historical master pins. Added E checks require faction-specific
colour families and different spatial light footprints, not a shared map tinted
four ways. Existing resource names and shipping membership do not change.

Offline review sheets are under `../review/faction-pods-palette-v4-*.jpg`, for
all four pairs in daylight/low light and from the opposite side. Both lighting
setups use the same material emission strength; only scene lighting is reduced
for the dark view. These are Blender inspections, not proof of engine bloom,
spinning parts, pickup collection/rejection, menus or performance. Native
Windows GOG/Steam and Proton/Wine checks remain unrun, as requested.
