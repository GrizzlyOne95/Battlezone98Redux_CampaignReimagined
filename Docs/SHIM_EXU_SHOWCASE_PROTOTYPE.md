# Operation Livewire: full OpenShim + EXU showcase

This expands the [showcase design](SHIM_EXU_SHOWCASE_DESIGN.md) into a nine-chapter,
6:30 single-player film and a repeatable regression range. Launch `sxshow.bzn`
after blessing and deploying the sources. This checkpoint passes host checks.
One native GOG/DX11 run (2026-10-07, test client) played the whole tour to `tour PASS`
with no render or camera-stack errors; framing, audio and physics are not yet judged.
The filename of these build notes is retained from the first prototype.

## Film and feature coverage

The runtime tracks **14 feature groups**. The design's earlier count of 13 grouped
autosave and options together; the implementation records them separately.

| Film time | Chapter | Visible or audible showcase |
| --- | --- | --- |
| 0:00–0:25 | Arrival | Moving scout convoy, native camera path, custom title/status/telemetry overlay, native soundtrack |
| 0:25–1:05 | Materials | Identical scouts: original control beside a cyan material clone, emissive pulse, texture UV scroll, then original assignments |
| 1:05–2:00 | Environment | Clear baseline, warm light/haze, moving dust front and wind, clearing transition; live fog/particle/wind telemetry |
| 2:00–3:00 | AI arena | Two tanks attack separate durable targets; stock control beside V3 standoff/kiting/strafe, with V2/V1 fallback and actual range telemetry |
| 3:00–3:35 | Destruction | Native damage kills a scout and a barracks; watch vehicle and building chunks with OpenShim chunks enabled |
| 3:35–4:30 | Team filters | Allied/enemy crossings of an enemy-only shield and magnet, then protected/triggering waves through enemy-only and ally-only proximity mines |
| 4:30–5:15 | Control tower | Normal, muted and throttled unit radio policy; Hunt replacement callback; native music pause, resume, fade/change and stop |
| 5:15–6:00 | Cockpit | Real player cockpit, map/scan radar, radar size/range/period, moved/recolored stock scrap/pilot text, live hull/ammo change, baseline return |
| 6:00–6:30 | Handover | Soundtrack restart, animated “Autosaving...” overlay preview, invitation to use real Options/OpenShim pages, then free play |

| Report key | Feature and boundary |
| --- | --- |
| `overlay` | Resolution-aware titles, status, telemetry, instrument labels and animated notification using `CRBZoneOverlayFont` |
| `materials` | Clone-owned per-subentity material swap; shared sources and control twin remain original |
| `animation` | Clone texture-unit scrolling plus emissive pulse; untextured passes may refuse scrolling |
| `environment` | Campaign `CRWeather`: fog, ambient/sun light, dust particles and wind; one environment writer |
| `ai` | Real stock attacks and gated EXU tuning; a tuning mirror alone does not prove movement behavior |
| `chunks` | Real craft/building death; no verified Lua chunk-count/config query |
| `filters` | Authored native ODF team filters on shieldtower, magnet and proximity classes |
| `radio` | Actual unit-VO mute, throttle, queue depth and stale policy; listen to native acknowledgements |
| `command` | Real selected-unit Hunt slot replacement; film dispatch and player interception are reported separately |
| `radar` | Native map/scan, size scale, player radar range and scan period; SP only |
| `hud` | Real scrap/pilot anchors/colors and native hull/ammo response; hull/ammo bars keep their native positions |
| `autosave` | Automatic notification preview; optional explicit native checkpoint command |
| `options` | Real menu exercise, overlay suppression/reflow and live resolution/UI-scale/music-option readback |
| `music` | Native track selection, pause/resume, sequential fade/change and stop; playback flags do not prove audibility |

This is a lunar training range on the existing `crsetup` terrain. The dust preset
is an authored demonstration there, not a claim that the map is Mars. No binary
terrain copy is added. The text BZN removes seven hostile setup turrets and keeps
32 original objects. The original tank becomes the authored user craft, and the
original pilot becomes an NPC; the script never calls `SetAsUser`. Every other
non-hostile object field and all 14 original paths are preserved. Forty-five
showcase paths are appended, for 59 total.

Eight stable owned fixtures remain for free play: the comparison scouts, convoy,
four camera/navigation stations and radio tank. AI, destruction and filter actors
are built for their chapter and removed afterwards. The peak authored population
is eight stable plus thirteen temporary filter actors, apart from native effects
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
| `sx tour` | Replay all nine chapters |
| `sx arrival/materials/environment/ai/chunks/filters/control/cockpit/handover` | Use one chapter name after `sx` to replay only that chapter |
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
Weather shuts down its particles and restores captured fog/light. Music restores
the original selected track and playing/paused policy, with readback; exact audio
stream position is unavailable. An unselected native track (`-1`) is left intact
and blocks the music exhibit because EXU cannot restore that selection. Saved
volume/options are not overwritten.
Failed cleanup is reported, retains retry state, and blocks destructive reset or
replay until restoration succeeds. Material clone names are bounded and reused.

Missing EXU, its stub, absent APIs and native failures produce blocked results.
The stock camera/death/attack demonstrations can still run with native exhibits
blocked. Network detection permits only a local overlay and returns before any
scripted world, camera, tuning, music or save mutation. This SP map is **not** an
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
weather/music/radio/HUD/AI cleanup, save-job gating, safe load handover, repeated
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
