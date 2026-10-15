# World palettes and real SAV boarding prototype

This is an opt-in gameplay prototype and an initial conservative atmosphere pass.
The palettes have structural validation; their in-game appearance still needs review.
SAV boarding, deployment, hop-out and re-entry are not yet runtime-qualified.

## Palettes

`Assets/ACT` now covers all nine stock worlds. Existing `moon.act` and `mars.act`
are retained byte for byte, including Mars's established full-palette treatment.
The seven new files start from each world's embedded Toolbox stock ACT and edit
only the effective sky/fog entries. No shared object-color ramps are refitted.

| World | Sky RGB | Native fog RGB | Direction |
|---|---|---|---|
| Moon | 5, 5, 5 | 5, 5, 5 | Existing CR palette, preserved |
| Mars | 213, 160, 113 | 174, 112, 77 | Existing CR palette, preserved |
| Venus | 83, 66, 31 | 131, 106, 58 | Muted amber rather than saturated green-yellow |
| Io | 3, 1, 0 | 3, 1, 0 | Nearly black, with a very small warm bias |
| Europa | 1, 2, 3 | 1, 2, 3 | Nearly black, with a very small cool bias |
| Titan | 112, 65, 27 | 153, 90, 35 | Orange-brown haze |
| Achilles | 55, 66, 70 | 103, 113, 113 | Muted stock teal/gray identity |
| Ganymede | 2, 2, 2 | 2, 2, 2 | Nearly black, neutral |
| Elysium | 48, 44, 50 | 48, 44, 50 | Restrained violet-gray stock identity |

These RGB values are artistic choices, not calibrated measurements. The warm
direction for Titan and Venus is informed by [NASA's Titan atmosphere description](https://science.nasa.gov/saturn/moons/titan/facts/)
and [the atmospheric color correction of Venera imagery](https://ntrs.nasa.gov/citations/19870039592).
Achilles and Elysium retain the game's art direction without a scientific claim.

Redux uses ACT entry 223 for default sky, and the palette index in LUM byte 223
for default fog. Stock Moon/Io/Europa/Ganymede/Elysium select entry 223 for both;
Mars/Venus/Titan/Achilles select 209 for fog. Moon's existing ACT entry 209 is
26,26,26, but that is not the native default with the stock Moon LUM.
`FogDirection=0` selects entry 0 instead; explicit TRN `FogColor`/`SkyColor`
overrides take precedence. These palettes use the existing stock LUM mappings.

Regenerate the missing palettes with Toolbox:

```console
bztoolbox textures act tune-all Assets/ACT --keep-existing
```

Individual editing is in Textures > LUM Table & Atmosphere: load the world's
ACT/LUM pair, apply the tuned preset, adjust ACT colors, and save. The reusable
presets live in Toolbox's `battlezone/terrain/atmosphere_presets.py`.

Environment.lua remains the base-atmosphere writer where loaded; the directors
continue to layer their weather on it. They can override the native ACT baseline
after initialization. This change does not alter weather, lighting, fog distances,
sensor/gameplay settings, or DDS terrain color grading.

## Fury assets

`avsav.mesh` is the stock Fury body's mesh, with its material and skeleton links
retargeted to `avsav00` and `avsav.skeleton`. All binary string replacements are
equal-length, leaving geometry, bone weights, bounds and other chunks intact.
`avsav.skeleton` and `avsav.vdf` are the matching stock Hadean Fury files; the
VDF is required for the body's geometry hierarchy, hardpoints and native motion.
The cut stock American SAV VDF alone has only a placeholder body and no Redux
mesh, so it is not the source for this complete visual body.

The material uses CR's existing `avsav_d.dds` NSDF skin, the stock Fury specular
and emissive maps copied as `avsav_s.dds` / `avsav_e.dds`, and the existing flat
normal map. No new texture painting or imported third-party model is involved.
`avsav2_d.dds` is an alternate existing skin and is not selected.

## Boardable real SAV

`ODF/avpsav.odf` uses `baseName=avsav`, **classLabel=sav**, `pilotCost=1`,
`pilotClass=aspilo`, and `userClass=asuser`. The existing Fury weapons and CR
HoverCraft tuning are retained, including the real SAV flight-altitude setting.
Its AI names are empty because this fixture needs to be boardable and does not
claim to implement a friendly SAV controller. Stock SAVFriend is not a working
registered controller in the checked Redux build.

No production mission loads the fixture automatically. In a disposable offline
mission that has CR mounted, call this from mission Lua or a Lua test harness:

```lua
local fury, reason = require("CRSAVTest").Spawn()
if not fury then print(reason) end
```

This spawns one empty Fury 20 meters beside the player and marks it. Hop out of
your current vehicle and walk into it normally; the fixture deliberately does
not force player control. Test ground driving, flight deployment, landing,
hop-out, re-entry, ejection/destruction and save/reload. Airborne exit and flight
camera behavior also need review. The fixture refuses multiplayer.

The existing `avsav` ODF and mission 14 `avsav14` wingman controller are unchanged.
The newly complete `avsav` presentation assets also satisfy their existing model
references. Native friendly AI is a separate feature.

## Friendly pickup experiment

The empty boarding fixture cannot answer **Pick me up**: native commandability
requires an AI controller and ordinary player-command priority. Confirmed native
behavior also shows that the real SAV controller inherits the generic rescue
path. Rescue normally approaches the on-foot player, waits nearby and asks the
AI pilot to abandon the vehicle; it is not a passenger-seat transfer.
An ODF that names `SAVFriend` cannot establish that controller in the checked
Redux build because that AI name is not registered there.

`ODF/avrsav.odf` is a second, occupied real `sav` fixture with the same visual
assets, pilot settings and movement tuning. It uses the registered `SAVEnemy`
controller on the player's team. This is an experimental controller reuse,
not a new `SAVFriend` implementation. Friendly combat initiative, flight/landing
interaction, pilot release and subsequent boarding remain **unknown in-game**.
Use a disposable offline mission away from the map edge and enemy units.

```lua
local test = require("CRSAVTest")
local fury, reason = test.SpawnPickup()
if not fury then print(reason) end
-- Keep this handle. Hop out normally, then try the Fury's Pick me up menu.
-- If the menu does not expose it, issue the native order separately:
local issued, why = test.RequestPickup(fury)
if not issued then print(why) end
```

Run the request only after the player is on foot. The helper accepts only a
commandable `avrsav` on the player's own team and passes `AiCommand.RESCUE` at
priority 0 so normal menu command access remains available. A true return means
the order was issued, not that rescue succeeded. No teleport, forced player
transfer or scripted pilot removal completes the pickup. Compare whether the
menu appears, the order is accepted, the Fury approaches/lands, the pilot exits,
and normal boarding followed by hop-out/re-entry works.

## Local content deployment

New content is explicitly added to the shipping lock. The manager's
`-deploy-files <source-relative path> [more paths]` action deploys and verifies
only selected, blessed content files. It does not refresh native binaries,
rewrite the native manifest or remove other runtime files, making it suitable
for this prototype while other game instances are open. Reload the mission
before inspecting changed assets.

No Workshop upload, release or automatic mission integration is part of this pass.

## Validation and installed prototype

Toolbox's focused texture/world/terrain/CLI run passed 280 tests (one skipped),
including the nine preset mappings, preservation of non-atmosphere ACT bytes,
ACT footers, LUM round trips and the keep-existing batch workflow. CR's new ODF
has no Toolbox validation findings; its material program references resolve.
The fixture compiles under Lua 5.1 and its offline/invalid-player/empty-spawn,
occupied-spawn and guarded priority-0 rescue contracts pass. These are mocked
API checks, not native gameplay qualification. The selected deployment command passes its temporary-runtime
tests, including rejection of native binaries, unlisted paths and partial writes.

The seven new ACTs, complete Fury presentation assets, test ODF and optional Lua
fixture were copied to the GOG development mod with `-deploy-files`; every copied
file was checked against its source hash. The existing NSDF diffuse texture was
also verified/deployed as a dependency. Moon and Mars matched their preserved
source hashes and were not overwritten. Reload a mission before trying the unit.
The occupied pickup ODF and updated fixture were subsequently deployed through
the same selected-content action and verified against their source hashes.

The full repository validator reports eight pre-existing OpenShim renderer-payload
hash/size mismatches. The untouched canonical CR checkout reports the same eight
errors. This prototype does not regenerate that unrelated native manifest.
Two Battlezone processes were already running, so no new gameplay session was
launched and boarding/flight/hop-out behavior remains unqualified.
