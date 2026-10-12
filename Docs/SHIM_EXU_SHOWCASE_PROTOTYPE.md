# Operation Livewire: full OpenShim + EXU showcase

This expands the [showcase design](SHIM_EXU_SHOWCASE_DESIGN.md) into an eleven-chapter,
7:33 single-player film and a repeatable regression range. Launch `sxshow.bzn`
after blessing and deploying the sources. This checkpoint passes host checks.
One native GOG/DX11 run (2026-10-07, test client) played the whole tour to `tour PASS`
with no render or camera-stack errors; framing, audio and physics are not yet judged.
The filename of these build notes is retained from the first prototype.

The [8 October native follow-up](LIVEWIRE_VALIDATION_20261008.md) records the
destruction heap-crash fix, the current 6:40 tour, successful Enhanced runs and
remaining trailer acceptance checks.

**12 October trailer pass.** The tour is now 405 s (6:45). The material lab parks
the scouts side by side under a close object camera and cuts the near hull through
six authored liveries (`Materials/sxtint.material`: the tint lives in the emissive
map, which is the only channel the Enhanced/CR object shaders show at lunar night;
pass colors and texture-unit UV transforms never reached the screen), then pulses its
glow. The weather bay runs the CRStormFX particle weather ported from ISDF Chronicles
([port notes](CR_STORMFX_PORT.md)): rain with splashes, a storm with four ground
strikes, snow, a dust storm and clearing, framed on the outpost, under an overcast
dome that takes the fog colour so open space no longer shows above coloured fog.
Host regression 119 checks, asset validator 358 checks.

**12 October second pass.** The tour is now 453 s (7:33) in eleven chapters, with
short trailer captions. New: a render-profile chapter that flips Retro, Redux and
Enhanced on held shots under the map's own lighting (needs the OpenShim live-apply fix;
before it, requests reported effective but the frame never changed), and a pilot
chapter for OpenShim skinned gibs (people spawn neutral, since the stock pilot AI
runs off on a player team). Destruction is four clusters on the flat plateau, each
under its own fixed camera: six vehicles, five walkers/APCs, three comm towers and
a five-building base, 19 kills, all in frame. The AI duel is now fighter against
a fixed turret (only AttackTask users kite) and needs the OpenShim kite-position fix, without
which kiting never engaged. Music cues are gone. Host regression 145 checks, asset
validator 420 checks.

## Film and feature coverage

The runtime tracks **15 feature groups**. The design's earlier count of 13 grouped
autosave and options together; the implementation records them separately. Music
was dropped from the film; lighting and gibs were added.

| Film time | Chapter | Visible or audible showcase |
| --- | --- | --- |
| 0:00–0:25 | Arrival | Moving scout convoy, native camera path, custom title/caption overlay |
| 0:25–1:05 | Materials | Identical scouts side by side: the near hull cuts through six authored liveries, holds with a script-driven glow pulse, then returns to its original assignment; the control twin never changes |
| 1:05–1:41 | Lighting | Outpost and parked scout on held shots under the map's own lighting; `exu.RequestRenderProfile` flips Retro, Redux and Enhanced, then hands back the user's profile |
| 1:41–2:41 | Environment | CRStormFX particle weather over the outpost: rain and splashes, storm with lightning strikes, snow, dust storm on live wind, clearing; overcast dome while weather is up |
| 2:41–3:41 | AI arena | Two avfigh against fixed svturr turrets; stock beside V3 standoff/kiting/strafe, with V2/V1 fallback; live range readout on screen |
| 3:41–4:29 | Destruction | Four framed clusters: vehicles, walkers/APCs, comm towers, a base; 19 kills, all in shot |
| 4:29–4:53 | Pilots | Four stock pilots, then three running soldiers, die in close-up; OpenShim skinned gibs |
| 4:53–5:48 | Team filters | Allied/enemy crossings of an enemy-only shield and magnet, then protected/triggering waves through enemy-only and ally-only proximity mines |
| 5:48–6:18 | Control tower | Normal, muted and throttled unit radio policy; Hunt replacement callback |
| 6:18–7:03 | Cockpit | Real player cockpit, map/scan radar, radar size/range/period, moved/recolored stock scrap/pilot text, live hull/ammo change, baseline return |
| 7:03–7:33 | Handover | Animated “Autosaving...” overlay preview, invitation to use real Options/OpenShim pages, then free play |

| Report key | Feature and boundary |
| --- | --- |
| `overlay` | Resolution-aware titles, status, telemetry, instrument labels and animated notification using `CRBZoneOverlayFont` |
| `materials` | Clone-owned per-subentity material swap; shared sources and control twin remain original |
| `lighting` | OpenShim render profile requested per shot with effective-profile readback; scene lighting untouched |
| `animation` | Clone texture-unit scrolling plus emissive pulse; untextured passes may refuse scrolling |
| `environment` | Campaign `CRWeather`: fog, ambient/sun light, dust particles and wind; one environment writer |
| `ai` | Real stock attacks and gated EXU tuning; a tuning mirror alone does not prove movement behavior |
| `chunks` | Real craft/building death; no verified Lua chunk-count/config query |
| `gibs` | Native person deaths; the gib split is logged by OpenShim (`[SKINNEDGIBS]`), not read back in Lua |
| `filters` | Authored native ODF team filters on shieldtower, magnet and proximity classes |
| `radio` | Actual unit-VO mute, throttle, queue depth and stale policy; listen to native acknowledgements |
| `command` | Real selected-unit Hunt slot replacement; film dispatch and player interception are reported separately |
| `radar` | Native map/scan, size scale, player radar range and scan period; SP only |
| `hud` | Real scrap/pilot anchors/colors and native hull/ammo response; hull/ammo bars keep their native positions |
| `autosave` | Automatic notification preview; optional explicit native checkpoint command |
| `options` | Real menu exercise, overlay suppression/reflow and live resolution/UI-scale/music-option readback |

This is a lunar training range on the existing `crsetup` terrain. The dust preset
is an authored demonstration there, not a claim that the map is Mars. No binary
terrain copy is added. The text BZN removes seven hostile setup turrets and keeps
32 original objects. The original tank becomes the authored user craft, and the
original pilot becomes an NPC; the script never calls `SetAsUser`. Every other
non-hostile object field and all 14 original paths are preserved. Eighty-one
showcase paths are appended, for 95 total.

Eight stable owned fixtures remain for free play: the comparison scouts, convoy,
four camera/navigation stations and radio tank. AI, destruction, pilot and filter actors
are built for their chapter and removed afterwards. The peak authored population
is eight stable plus 23 temporary destruction actors, apart from native effects
and debris. Reset removes only mission-owned fixtures and preserves the user craft.

## Autosaving and save handover

The handover chapter automatically displays an animated spinner and
**Autosaving...** for four simulation seconds, with a small **Notification preview**
label. `sx autosave` previews it again. These previews write no save file and need
no loading transition, so a continuous mission recording can show the message.

Optional `sx save` first stops the film and restores temporary overrides, then
queues one `exu.SaveGame("Save\\sxshow.sav", 0, "Operation Livewire checkpoint")`
request for the next safe gameplay interval. An open native UI suspends that
request. The pending job is cleared before native serialization and is never
saved or replayed. The dedicated path may replace an earlier Livewire checkpoint;
the notification changes to saved/unavailable according to the native result.
No automatic save is issued by the film.

There is no scripted load invocation. The existing mission `Load(...)` callback
supports manual/native checkpoint restoration: end cameras, rebind handles,
restore captured material/native baselines, briefly retry render readiness and
return to free play. Camera, destruction and save cues never resume. Save data
contains serializable values/game handles and diagnostic scene state, not callback
closures or timer jobs. Old prototype save data is also accepted. Actual loading
is not part of this video's acceptance path.

## Controls and honest results

Enter these in the stock game console:

| Command | Action |
| --- | --- |
| `sx tour` | Replay all eleven chapters |
| `sx arrival/materials/lighting/environment/ai/chunks/pilots/filters/control/cockpit/handover` | Use one chapter name after `sx` to replay only that chapter |
| `sx skip` or native camera cancel | End the film and restore temporary baselines |
| `sx service` / `sx baseline` | Apply the cyan comparison in free play / restore originals |
| `sx autosave` | Show the notification preview, without writing a save |
| `sx save` | Write the optional dedicated native checkpoint after cleanup |
| `sx options` | Return to gameplay and prompt for the real Esc/options pages |
| `sx confirm <feature> pass` / `fail` | Record an actual visual/auditory observation using the keys above |
| `sx report` | Print sorted feature/API/cleanup results and separate operator observations |
| `sx caps` | Read requested/supported/effective/reason for renderer effects; does not request unavailable effects |
| `sx reset` | Restore, rebuild only owned fixtures, then replay |
| `sx list` | Display controls |

A report `PASS` means the stated API readback or witness matched, not that the
whole effect looked correct. `visual/<feature>` remains `PENDING` until an operator
confirms it. A replay or load invalidates observations. Blocked features cannot
be confirmed as passing. Cleanup failures stop the film before the next chapter, and camera/cue/setup
errors report tour `FAIL`. `sx baseline` retries restoration before replay.
Tour `PASS` means the authored sequence completed with successful cleanup;
individual features may still be blocked, fail, or need observation.

The proximity witness checks protected craft reaching their lane exits unharmed
while both mines remain alive, followed by configured-team damage and mine
disappearance. Shield and magnet behavior still require direct observation.
Manual command dispatch does not pass the real Hunt-interception check. Scripted
movement might not emit a unit acknowledgement on every native build: during the
control chapter, issue real commands to the selected radio tank and listen. Open
`Esc` during handover and use the real settings pages for the options check.

Menus hide the custom overlay and freeze the scene clock. Resolution changes
reflow the overlay. Temporary camera/radar/HUD/radio overrides are captured and
restored; later external setting changes take precedence where supported.
Weather shuts down its particles and restores captured fog/light. The lighting
chapter requests `inherit` on exit, so the user's own render profile returns. Saved volume/options are not
overwritten.
Failed cleanup is reported, retains retry state, and blocks destructive reset or
replay until restoration succeeds. Material clone names are bounded and reused.

Missing EXU, its stub, absent APIs and native failures produce blocked results.
The stock camera/death/attack demonstrations can still run with native exhibits
blocked. Network detection permits only a local overlay and returns before any
scripted world, camera, tuning, render-profile or save mutation. This SP map is **not** an
authored multiplayer companion or a multiplayer qualification result.

## Build and verification

Use the canonical `%USERPROFILE%\Documents\GIT\Campaign-Reimagined` checkout on
`agent/shim-exu-showcase`, preserving unrelated changes. The shipping lock remains
unchanged because this checkpoint was authored without that Windows checkout.
The files will not be installed by lock-based deployment until blessed there.
Do not bless a partial source tree or hand-edit the lock.

```powershell
python Tools/Build-SXShowcaseMap.py
lua Tools/Test-SXShowcase.lua Scripts
python Tools/Test-SXShowcaseAssets.py
.\Manage-CampaignFiles.ps1 -bless
git diff -- Shipping/shipping.lock.json
python Tools/Validate-CampaignRepository.py
.\Manage-CampaignFiles.ps1 -deploy
```

Use Lua 5.1 for the host command when available. Bless should add these fourteen
runtime sources with no removals/unrelated membership changes (each ships to its
leaf filename):

- `Config/sxshow.ini`, `Missions/sxshow.bzn`
- `Scripts/sxshow.lua`, `Scripts/SXDirector.lua`, `Scripts/SXMaterials.lua`, `Scripts/SXOverlay.lua`
- `Scripts/SXState.lua`, `Scripts/SXScenes.lua`, `Scripts/SXExhibits.lua`
- `ODF/sxanchor.odf`, `ODF/sxshield.odf`, `ODF/sxmag.odf`, `ODF/sxproxe.odf`, `ODF/sxproxa.odf`

Review and commit the generated lock diff before deployment. Existing campaign
terrain, models, font and particle payload plus the native sibling components
must be installed. The magnet/proximity visual base and blast use the stock game
`proxmine`/`xminxpl` resources. The filter fixtures explicitly declare their native
classes; the campaign's decorative `abshld` model alone is not a shieldtower.
Use the GOG development target from [AGENTS.md](../AGENTS.md). `Docs` and `Tools`
are authoring files, not runtime payload.

For serialized game launches, follow the current OpenShim
`reverse_engineering/BZRHarness.ps1` guidance, use its launch mutex and windowed
mode, and stop only the launched process through `Stop-BZRGame -Id`. Enable the
supported chunk renderer and compatible assets before judging the destruction
shots. No unavailable postprocessing bridge is advertised as working.

Source contracts inspected for this checkpoint:

- Campaign showcase parent: `54b727eaee710b179bcb868b547d7f6ddb02fde3`
- EXU main: `75863c5005b96d09855b140bb4b32907e87fba75`
- OpenShim main: `4d610647556a22d58273694c2a9ce6c68b246ed1`

The host regression passes **97 checks** for cue/hitch/cancel handling, independent
chapter replay, material rollback/UV cleanup, native readbacks, external settings,
weather/lighting/radio/HUD/AI cleanup, save-job gating, safe load handover, repeated
whole tours, failed-reset protection, chapter-boundary cleanup failures, early
startup cancellation, callback error reporting, a balanced native camera stack and
the network guard. These use fakes,
including idealized proximity motion, and do not qualify native physics.
The asset validator passes **295 checks** for map counts/IDs, preserved source
objects/paths, exact generator output, terrain bounds, Lua bindings, ODF classes
and filters, existing shipped dependencies and runtime-name collisions.
Both host checks pass under Lua 5.1.5.

The first native run found two defects, now fixed. Closing a camera that was never
opened (`CameraFinish` before the tour's first `CameraReady`) raised the engine's
"Fsm error: Camera Stack 0verfow". Overlay text kept the image font's internal
fixed-function material, so D3D11 threw on every frame and never presented the
scene; text areas now use the shader-backed `CR_OverlayFont`, as subtitles do.

The next acceptance pass is an in-game recording: watch the full film, replay and
cancel individual chapters, inspect each transition, use the real Hunt slot and
radio commands, open options/resize, confirm observed features, and repeat/reset
the range. Adjust camera framing, terrain clearance, shader visibility, AI timing
and filter routes from that evidence. Native loading, real handle remapping,
repeated mission entry and the Windows/GOG, Windows/Steam, Proton and Wine lanes
remain unverified. No release or Workshop qualification is claimed.
