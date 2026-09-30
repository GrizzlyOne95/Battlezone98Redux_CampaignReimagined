# Operation Livewire — Shim + EXU showcase mission

Source-reviewed mission design • 30 September 2026

Build a living research outpost on Mars: a convoy arrives, the site wakes up, its equipment changes appearance, a dust front crosses the valley, automated combat trials run, and the player receives control of the proving ground. The opening is a **6 minute 30 second cinematic**. Every demonstration remains available afterward as a repeatable station with an operator-facing regression view.

This document is the design and implementation specification for Operation Livewire. Mission construction and in-game qualification are the next steps.

## Scope and confidence

**High confidence in the mission architecture and most API choices. Medium confidence in final camera timing, native visual outcomes, and multiplayer qualification until the authored map runs in Redux.** The reviewed sources support a substantial first version without new native APIs. Hull/ammo meter relocation and several renderer/music extensions require additional work and must remain optional extensions.

Use Campaign Reimagined (CR) as the content owner. Ship the showcase as a separate Instant Action entry, outside campaign progression, following the separation already used for `crsetup`. OpenShim owns engine behavior and regression documentation; EXU supplies reusable runtime operations and Lua bindings. Avoid creating another campaign checkout or a duplicate runtime implementation.

Pin the initial implementation to these reviewed default-branch snapshots, then recheck changed APIs when implementation begins:

| Repository | Reviewed commit |
| --- | --- |
| Battlezone98Redux_Shim | `fd328e0087e3ca90900024aea2719f88787d46ce` |
| Battlezone98Redux_CampaignReimagined | `91878ec9230ad2cb3b59caccfff21d3e1fab3b19` |
| ExtraUtilities | `68991210d613d76e20f5fc6bd1531c9012dfbcc2` |

These are code snapshots, not proof that an installed release has every feature. The mission must inspect its actual runtime.

## What the current code can demonstrate

| Feature | Verified interface or mechanism | Design consequence |
| --- | --- | --- |
| Cinematic cameras | Stock `CameraReady`, `CameraPath`, `CameraPathDir`, `CameraObject`, `CameraFinish`, `CameraCancelled`; CR already calls camera paths every update during films | Author real map paths and targets; drive shots through mission Lua. |
| Overlays | EXU overlay creation, Panel/TextArea elements, captions, layout, material and font controls | Provide titles, live telemetry and the regression dashboard. Use `CRBZoneOverlayFont` with the bundled font assets. |
| Object materials | `GetSubEntityCount`, `GetSubEntityMaterial`, `CloneMaterial`, `SetSubEntityMaterial`, `GetMaterialPassColors`, `SetMaterialPassColors` | Change one live vehicle without changing its control twin. Restore original assignments afterward. |
| Texture/material animation | `SetMaterialTexture`, texture scroll/rotate and their animation variants | Animate a cloned instrument or vehicle material. Preserve shared materials and shader compatibility. |
| Dynamic environment | EXU fog, sun, sky and particles; CR `Environment`, `CRWeather`, modifier registration, preset/intensity/wind controls | Use one environment writer and real weather resources. Fog, sun and particles visibly evolve over a fixed view. |
| AI tuning | `SetAiUnitTuning(handle, table)`, `GetAiUnitTuning`, clear operations; V1/V2/V3 native bridges | Demonstrate range floors, kiting and strafing on supported SP units. A successful setter or mirrored read-back alone does not prove behavior. |
| Destruction chunks | OpenShim chunk rendering plus a validated compatible mesh/resource pack | Kill real craft/buildings through engine damage. Test visible fragments manually; Lua has no verified chunk-count query. |
| Team filters | ODF `teamFilter`, `affectAllies`, `affectEnemies` for shield towers, magnet mines and proximity mines | Spawn preauthored variants with fresh objects. There is no verified generic Lua team-filter setter. |
| Radio policy | `Get/SetUnitVoMuted`, throttle, queue-depth and stale-time controls; alternate mappings | Compare real unit responses and restore captured policy. Mission narration is a separate audio channel. |
| Command hooks | `ReplaceStockCmd`, removal/query/manual trigger and update operations | Use selected-unit **Hunt** for the native demonstration. Other command names are not assumed to have automatic interception. |
| Radar | State, range/period and radar size-scale APIs | Show mode and scale changes with live contacts. Treat radar range/period as gameplay-affecting; keep those trials SP-only. |
| Existing native HUD controls | Scrap/pilot text anchors and colors; sprite geometry/visibility; HUD material textures | Reposition real scrap/pilot readouts, retain usable radar and live hull/ammo displays. Generic sprite records do not establish live meter placement controls. |
| Save/options | EXU native `SaveGame`; OpenShim autosave and settings UI | Offer a dedicated showcase save and a separate real autosave/options exercise. Never assume autosave is enabled. |
| Native music | `SetMusicTrack`, `StopMusic` through OpenShim | Use real OGG track changes if accepted. Pause/resume/read-back are currently fail-closed stubs; fades are not a verified API. |
| Renderer effects | Intent/status bridge for `ssao`, `depth_haze`, `soft_particles` | Status can report `not-implemented`. Do not advertise a visible effect from request acceptance. |

Important configuration detail: the reviewed `openshim.ini` has `AutoSave.Enabled = 0` and `ChunkMeshes = 0`, while the autosave document describes enabled defaults. Installed settings and actual resource availability govern the demonstration; do not infer readiness from prose or overwrite the user's configuration to make a shot pass.

## Player experience and visual language

Three modes share the same scene definitions and test fixtures:

1. **Cinematic tour:** the complete 6:30 sequence, captions and a clear skip route. It ends in free play rather than immediately showing a success screen.
2. **Free play:** drive or walk between bays, repeat trials, operate real command menus, and inspect the cockpit. No mandatory time limit.
3. **Regression operator:** run a selected bay or the suite, reveal detailed observations and export results when file support is available. Record exactly which profile and features were exercised.

The normal film shows only the chapter title, the active change and one useful live value. For example: “Material lab — service lights engaged”; “Combat trial — standoff range 100 m”; “Cockpit — live scrap readout moved.” Technical capability details belong in operator mode.

Use the same shot for a baseline and its changed state. Hold long enough to see the difference. Blue/white identifies allies, red/orange identifies enemies, and text labels repeat the distinction for players who cannot rely on color. Keep captions away from the reticle, stock meters and radar. Subtitle all mission narration. Avoid flashes, fast camera spins and letterboxing that conceals the stock HUD during the cockpit chapter.

If a bay is unavailable, provide a brief honest caption and continue. Operator mode reports the reason. A missing feature never produces a fake visual substitute labeled as a successful native demonstration.

## Map and camera authoring

Proposed SP basename: `sxshow`; optional network sibling: `sxcoop`. Keep mission-specific ODF tokens within eight characters. These filenames and paths are proposed new content, not existing repository files.

Author one connected outpost roughly 700–900 m across. Place a sheltered landing/control area at its center, material hangars to the west, a weather overlook to the north, parallel AI lanes to the east, and destruction/filter ranges to the south. Separate combat and mine bays by ridges and ample distance so stray shots, blast damage and aggro cannot contaminate another trial. Tune visibility and fog against the map's actual terrain horizon.

Author all paths and anchor objects in the BZN/editor. Use native supported authoring tools; do not manufacture unknown terrain binary formats. Camera anchors must be persistent, valid, inert mission fixtures. Targets remain alive until their last shot finishes. Each scene owns a clean fixture roster and a reset route.

| Path or anchor | Purpose | Shot requirement |
| --- | --- | --- |
| `sx_arrive` | Valley-to-outpost approach | Wide reveal; convoy and lit landing strip converge in frame. |
| `sx_mat_a`, `sx_mat_b` | Hangar glide and service-light detail | Frame both matching vehicles before changing one. |
| `sx_weather` | Slow ridge tracking path | Building, terrain horizon and a distant marker remain visible through the storm. |
| `sx_ai_wide`, `sx_ai_side` | Parallel-lane overview and side tracking | Display actual spacing and movement; keep both units visible. |
| `sx_break_a`, `sx_break_b` | Destruction side view and follow-through | Maintain a clear view from impact through fragment flight. |
| `sx_filter` | Shield/mine lane overview | Friendly and enemy effects are readable in the same composition. |
| `sx_control` | Control-tower/unit-command view | Establish the commandable unit and subsequent movement. |
| `sx_hud` | Return-to-craft approach | Finish the external shot before restoring the actual cockpit view. |
| `sx_end` | Final outpost flyby | Revisit the living site, then return control safely. |

Use native camera transitions and deliberate cuts. Do not assume an exposed spline/easing/FOV API that has not been verified. `CameraObject` offsets are centimeters; start framing at values such as 800 right / 350 up / -1200 forward and calibrate to the actual craft. Path height and speed require in-game calibration: CR's `CameraPath("movie_path", 175, 850, target)` is a reference call, not proof of suitable pacing for this map.

Use a 2-second settling allowance per shot, avoid terrain clipping, and test cockpit handover at multiple aspect ratios. Do not switch the player into a dummy camera craft with `SetAsUser`; native cinematic cameras preserve the real controlled object.

## Cinematic storyboard: 6:30

Times are editorial targets. Camera path completion, fixture readiness and bounded event waits decide actual transitions. A timeout reports an incomplete trial and advances cleanly.

| Time | Chapter and camera | Visible action | Lua/native driver |
| --- | --- | --- | --- |
| 0:00–0:25 | Arrival; `sx_arrive` | Convoy approaches; outpost powers up; title appears; live tour progress starts | Stock camera path; EXU overlays; optional accepted native music track. |
| 0:25–1:05 | Material lab; paired hangar shots | Twin craft begin identical. One acquires a new livery, emissive service lights and an animated instrument texture. The twin stays unchanged. | Clone and bind per-subentity materials; pass colors and texture animation. |
| 1:05–2:05 | Atmosphere; ridge shot held on landmarks | Clear daylight transitions to warm dusk, visible windblown dust, then clears. Headlights and emissive markings become easy to see. | CR environment modifier and weather preset/intensity/wind controls. Neutralize unrelated gameplay modifiers. |
| 2:05–3:10 | AI arena; overview then side tracking | Matching craft engage comparable targets. The tuned trial maintains standoff and, when V3 is accepted, strafes. Range telemetry reflects their real positions. | Native attack behavior; SP per-unit tuning; position sampling and event conditions. |
| 3:10–3:50 | Destruction yard; low side shot | Tank/fighter and a selected structure die in separate beats. Real fragments cross a clean background, then settle/expire. | Actual weapon damage or SP `Damage`; asset-backed OpenShim chunks; optional reactive particles. |
| 3:50–4:35 | Team-filter lanes; fixed overview | Allied/enemy shots cross shield lanes; magnet lane pulls the intended craft; proximity lane allows an ally, then triggers for an enemy. | Authored ODF variants and alliance state; native ordnance/craft/mine simulation. |
| 4:35–5:20 | Control tower; unit selection and movement | Introduce radio policy; a selected unit's Hunt slot reads “Run trial.” The registered callback starts a route and updates live status. | Hunt replacement and command maintenance. Film may use manual trigger; native interception is checked interactively. |
| 5:20–6:10 | Actual cockpit | Stock radar changes mode/size. Real scrap and pilot numbers move into authored slots. Hull/ammo visibly respond to controlled damage and firing; live custom numeric readouts accompany them. | EXU radar, text anchors/colors, HUD material swap; stock health/ammo changes in SP. |
| 6:10–6:30 | Handover | Brief outpost reveal; cockpit/control returns; station objectives and test controls appear. Save/options station is introduced. | `CameraFinish`, baseline restoration, mission state transitions; optional dedicated checkpoint from live gameplay. |

The radio scene must exercise actual native unit responses to count as a radio-policy demonstration. A mission `AudioMessage` is narration and does not prove the unit-VO hooks. If script-issued orders do not emit native acknowledgements in the tested build, keep the film introduction and perform the auditory comparison through the player's real unit command menu in free play. Mark that check pending until observed.

## Exhibit and regression contracts

### Material lab

Snapshot every affected subentity material. Clone a small fixed set of materials into a `SX/` namespace and reuse those names across resets, because no general material-destruction API was verified. Do not create new clone names every replay or change shared base materials globally.

Swap one fixture while retaining a control twin. Read back subentity assignments; verify the twin still uses its originals. Animate only clone-owned textures/pass colors. Confirm visually that livery, emissive detail, alpha/glow behavior and shadows still work on the active renderer. Reverse the operation and compare with the captured assignments. Resolve handles again after destruction/load; never operate on stale handles.

### Environment overlook

Reuse `Environment` and `CRWeather`. `Environment` is the sole writer of fog/sun, with the showcase's art direction registered through `RegisterEnvironmentModifier`. `CRWeather.Init` contributes its own modifier. Drive `CRWeather.SetPreset("MarsDustStorm", 12.0)`, intensity and wind explicitly, then `SetPreset(nil, 10.0)` to clear.

Do not run an independent loop that also calls `exu.SetFog` or sun setters while those controllers own the scene. For a small independent EXU-only fixture, use one writer with `GetFog`/`SetFog` and the sun getters/setters instead.

The chapter's visual modifier blends ambient/diffuse/specular/sun-power fields along its scene-local timeline. Avoid changing `Environment.DebugScale` mid-scene: its clock uses `GetTime() * scale`, which can jump the phase. Set night radar/period/jamming modifiers to neutral for this showcase controller and make radar behavior a deliberate SP trial later. Bound fog by the authored horizon; keep stable shadow configuration. Show clear → dust → clear without hiding all landmarks.

Regression: read back selected environment values, observe transitions and horizon stability, check weather system inventory/emission state, and confirm reset removes showcase contributions. Particles must follow the cinematic camera where appropriate and remain bounded by quality/quota controls. Test camera changes, pause and replay for stranded emitters or duplicated systems.

### AI arena

Use the smallest suitable craft fixtures with isolated opponents, fixed equipment, identical terrain and controlled health. Keep broad `aiCore` mission simulation out of this first prototype. Native AI owns movement; do not manually move the tuned craft to manufacture a result.

Initial V3 request for calibration:

```lua
local accepted = exu.SetAiUnitTuning(tunedCraft, {
    engageRange = 180.0,
    weaponRangeMin = 120.0,
    retargetPeriod = 0.75,
    kiteEnterRange = 70.0,
    kiteDesiredRange = 100.0,
    kiteExitRange = 130.0,
    kitePreserveLos = true,
    kiteStrafe = 0.35,
    kiteSwitchPeriod = 1.2,
})
```

These are proposed fixture values, not validated balance settings. Range/retarget fields act as floors; they do not change the weapon's physical projectile properties. Kiting requires `enter < desired < exit`. Test the full request, fall back to V2 without strafe fields if refused, then range-only if appropriate; label the accepted subset. Do not claim V3 after falling back.

`GetAiUnitTuning` is an EXU-side mirror, not a native behavior probe. Sample target distance, motion and AI process/task information and compare broad calibrated bounds over a sustained observation window. The control lane is a visual reference, not a frame-exact deterministic assertion. A shot blocked by terrain is inconclusive. Clear per-unit tuning on reset and demonstrate that a fresh unit does not inherit it. Disable the tuning chapter in network play unless separately qualified.

### Destruction yard

Choose three models with verified compatible chunk resources: a tank, fighter, and structure. Preserve their normal ODF destruction definitions. Damage actual objects; `MakeExplosion` artwork alone does not test death chunks. Use an engine weapon hit where practical and SP `Damage` for a bounded scripted kill fallback, recording the trigger used.

Hold on visible fragment motion for several seconds. Observe correct model/material selection, internal caps, shadows where supported, expiration and the absence of ghost fragments after reset. Stage one destruction event at a time for readability, followed by an optional operator stress burst with explicit limits.

A compatible asset pack and enabled setting are required. Configuration alone does not prove effective chunk rendering. Without a verified Lua chunk-capability query, operator preflight uses the installed manifest/native startup diagnostics and visual observation. No fragment-count claim is generated from an invented API. Missing assets are a blocked visual test, while a repeatable no-crash baseline remains separately reportable.

### Team-filter range

Author distinct stock-derived ODF variants for `teamFilter = "all"`, `"allies"`, `"enemies"`, and `"none"`. Include an unmodified stock control. Use complete inherited ODF definitions; the filter line alone is not a valid complete object definition. Spawn fresh fixtures rather than editing cached ODF files during play.

The shield lane tests projectile **owners**, not projectile color. Use valid friendly/enemy shooters and controlled comparable weapons. The magnet lane measures displacement of friendly/enemy craft inside an authored effective radius. The proximity lane waits for normal arming, crosses with an ally, resets, then crosses with an enemy. Keep bystanders outside the blast radius: trigger filtering does not establish immunity to the resulting stock explosion damage.

Record alliance setup, actual team, fixture position, weapon, arming delay and trial variant. Set alliances in a valid update phase; the shared reference warns that `LockAllies` has no effect from Redux `Start`. Keep perception/reveal experiments separate from these trials. Never assert “team filtering works” from spawn success. Verify each object class's actual behavior. Ship these as SP regression bays first; enable their network counterparts only after authority/ownership-specific qualification.

### Radio and command station

Capture mute, throttle, depth and stale-time values; display Normal / rate-limited / Muted comparisons and restore the captured values. Keep narration/subtitles independent. Exercise queued native unit messages with real selected-unit orders, including a short burst and a stale backlog. Check by listening and native diagnostics; setter read-back alone does not verify audio suppression. Alternate mappings are optional and only use bundled known files with a captured mapping to restore.

Register a Hunt replacement on one mission-owned wingman:

```lua
exu.ReplaceStockCmd(wingman, "Hunt", "Run trial",
    function(unit, stockCommand, replacementLabel, origin)
        -- Validate the handle and mission mode here.
        -- Increment a mission-owned counter and start the authored route.
        Goto(unit, "sx_cmd_route", 1)
        return true
    end)
```

This is an illustrative callback, not the complete station implementation. Return true to consume the replacement. Call `UpdateCommandReplacements` once per frame through one owner; `RuntimeEnhancements.Update` already calls it when that module is the owner.

For the film, `TriggerStockCmdReplacement(wingman, "Hunt")` may stage the visible action. Record this as the manual/script path. In operator mode, choose Hunt through the actual command UI and record callback `origin`: `native_set_active_mode` demonstrates the native hook; `stock_command_poll` demonstrates its polling fallback. Neither is inferred from the manual trigger. Test selecting another unit, removal, default Hunt restoration, repeated presses, unit deletion and load/rebuild.

### Cockpit/radar/HUD station

Use the actual cockpit and native live engine bars. Switch minimap/radar state and show moderate radar scales such as 1.0 → 0.75 → 1.15 → baseline. Check backdrop/contact alignment at each size. Recalculate layout when resolution/UI scale changes; the game's HUD scaling option can overwrite radar scale.

Move native scrap/pilot text into readable authored slots using the individual top-left APIs and restore the original anchors/colors. Use overlay TextAreas for sampled live health/ammo values, clearly labeled as custom readouts. A scripted SP health decrease and actual firing make the stock hull/ammo bars visibly update. Restore controlled fixture values before handover; avoid repairing or modifying other network players.

`Get/SetHudSpriteRect` controls live sprite records and dimensions, with special visibility treatment for scrap/pilot panels. It is not evidence of a relocatable live hull/ammo-meter layout API. Keep those native meters in their existing usable positions in v1. Reserve a capability adapter for a later verified meter-placement API; when it arrives, repeat the same health/ammo trial after moving the real bars into authored instrument slots. No proposed native function name is presented as already supported.

If swapping `HUDcombi` textures, use authored compatible atlas dimensions/layout and restore the known original texture. The inspected API lacks a general texture read-back, so only touch a mission-owned, known-baseline HUD asset or defer that comparison. Keep radar, reticle and other stock elements visible.

### Save/options station

At the end of the film, restore camera control and transient presentation overrides before saving. Expose an explicit “Save showcase checkpoint” action using `exu.SaveGame("Save\\sxshow.sav", 0, "Operation Livewire checkpoint")`. This uses a dedicated file and never masquerades as the engine autosave timer.

For the real autosave regression, let the operator open OpenShim Settings and choose AutoSave/interval. Wait according to the actual configuration; confirm `auto.sav` through native diagnostics/file evidence and then load it through the injected load button. Repeat with pause/options open over a deadline and in MP. Do not run CR `AutoSave.lua` alongside the engine timer in this mission; test their coexistence separately if desired.

Serialize mission primitives, the scene/variant, fired-cue state, results, relevant game handles, and weather's serializable state. Persist through stock `Save`/`Load`, rebuild overlays/material assignments/command callbacks and reacquire the current player after load. Never serialize functions, Ogre pointers, Lua registry references, live emitters or UI objects. Prefer explicit game handles in the mission's established save contract rather than assuming arbitrary tables of native state are safe.

An autosave can still occur during a film under the user's timer. On load, cleanly finish camera mode and restore to a safe scene checkpoint or free-play handover; never replay a destructive cue or duplicate objects unintentionally. Preserve enough cue/fixture state to make that policy consistent.

Test radar/UI scale or other documented live settings through the actual options page. Re-query/rebuild layout on return. Changing an option must visibly affect the scene and must not start a second environment writer.

### Music and future renderer extensions

Use known available tracks, initially the 7/12 fixture exercised by OpenShim's existing music test, with graceful refusal if unavailable. Add an operator check for same-track idempotence, unavailable-track refusal preserving current playback, stop twice, and subsequent restart. Auditory/native-engine evidence is required; `GetMusicTrack` currently returns nil because its provider is a stub.

Exact restoration of a preexisting music playback position is unavailable. Keep the film's authored track policy explicit and transition to its free-play track on handover. Do not promise pause/resume or fades.

Renderer effects may be listed in operator preflight with `requested`, `supported`, `effective`, and `reason`. The reviewed bridge documents no implemented effect. Use the status contract to skip unsupported requests and reset mission intent; no cinematic chapter depends on SSAO, depth haze or soft-particle depth fading. Enhanced material/profile comparisons can be an optional extra bay, with effective-profile read-back and visual evidence.

## Lua architecture and lifecycle

Proposed CR files: `Scripts/sxshow.lua`, a small `SXDirector.lua`, `SXCapabilities.lua`, `SXResults.lua`, `SXStations.lua`, and declarative `SXScenes.lua`; `Config/sxshow.ini`; `Missions/sxshow.*`; prefixed ODF/material/overlay assets; and a mission guide. An optional `sxcoop` entry shares the station definitions. Validate the actual packaging conventions before generating the final map wrapper and content lock.

Each scene declares requirements, fixtures, shots, timed cues, observations, reset, and cleanup. Keep scene IDs stable so saved state and result exports survive editorial timing changes. Modules and helpers proposed here belong to the mission; they are not new EXU APIs.

Run a nonblocking state machine: preflight → scene setup → camera/action → observation → cleanup → next scene → free play. Native camera advancement runs every update; cues run once when elapsed simulation time crosses their threshold. Avoid equality-time checks, blocking waits and a chain of one-shot camera calls. Readiness and timeout conditions allow slower machines to progress safely.

Illustrative native camera pattern:

```lua
-- Call CameraReady once when entering this shot.
-- target is a validated authored anchor; elapsed is scene-local simulation time.
local function UpdateArrivalShot(target, elapsed)
    if CameraCancelled() then
        CameraFinish()
        return "cancelled"
    end
    CameraPath("sx_arrive", 175, 850, target)
    if elapsed >= 25.0 then
        CameraFinish()
        return "complete"
    end
    return "running"
end
```

Calibrate path completion and camera return semantics in-game, then use completion with a maximum duration. Cancellation immediately stops the camera, restores the active scene's settings, stops owned narration, preserves required fixtures and enters free play. Do not execute all remaining cues when skipping. A single scene failure also runs its cleanup and proceeds to the next chapter.

Use `Start`, `Update(dt)`, `Save`, `Load`, object/player callbacks, `GameKey`, `Command` and `Receive` as the actual supported mission surface. Route unrelated commands and network packets onward. Provide operator commands such as `sx scene materials`, `sx runall`, `sx reset`, and `sx report` through the mission's `Command` handler, plus physical station objectives and a chosen nonconflicting input for normal users. These command strings are proposed mission controls.

No verified universal Lua shutdown callback is assumed. Invoke cleanup on controlled transitions, cancellation, replay and success; verify native Lua-state/mission cleanup on restart, quit and next-map load. `CRWeather.Shutdown` and `CRReactive.Shutdown` exist. Remove per-unit command replacements and tuning, detach/destroy owned particles, restore material assignments and captured HUD/radio/camera values, and unregister the showcase environment modifier. Use `ResetMissionHookOverrides` only at the deliberate mission boundary: it also resets render-profile/effect and other mission overrides. Do not use it mid-scene as a narrow undo function.

Keep handles in a bounded roster and invalidate them on deletion. Guard AddObject/DeleteObject work so setup and cleanup do not recursively spawn fixtures. Reuse stable overlay/system names. Hide the custom dashboard while pause/options/save/load or mission-result UI is open using verified UI state APIs; do not obscure or fight the native menus.

## Capability and result model

Detect native EXU with protected `require` after the established RequireFix initialization; reject `exu.isStub`. Check required functions and asset availability. Call setters only during a reversible trial with captured state, interpreting each function's actual contract. Some setters return nothing on success, some return booleans, and some getters return nil when unsupported. A generic “pcall succeeded” test is insufficient.

Use explicit result states:

| State | Meaning |
| --- | --- |
| PASS | Stated behavioral/read-back assertion passed, or a visual/audio observer explicitly confirmed it. |
| FAIL | Supported, prepared trial produced a measured wrong result or an unexpected error. |
| PENDING | A request was accepted but the required behavior/visual/audio observation is incomplete. |
| BLOCKED | Required build, asset, setting or fixture readiness is absent. |
| SKIP | Trial was intentionally excluded by mode/policy, such as SP tuning in MP. |

Record evidence kind separately: `api`, `behavior`, `visual`, `audio`, `native-log`. Automated API acceptance and visual/manual acceptance never share an unlabeled pass counter. Ordinary presentation shows a concise status; operator mode reveals request/result/error, observation, timeout and effective subset.

Export a compact ordered text/CSV-style report using the existing bzfile/LogPaths workflow only when available. Fall back to stock print/display messages. Include mission version, repository/build identifiers available at runtime, SP/MP role, renderer requested/effective profile, capabilities, asset/settings preflight, scene/variant/cue, assertion type, result, measurements and observation source. Do not log player identities unless necessary for network authority diagnosis.

## Multiplayer companion

Make multiplayer an explicitly smaller presentation/test mode. Use a companion entry built from the same geography; start in free play, with the camera tour optional per player. CRCoop's contract assigns human teams 1–4 and enemies 5+. Team 1 remains campaign authority; a migrated network host does not silently inherit authority. If the leader departs, stop new trial mutations and release local cameras safely.

| Behavior | Initial network policy |
| --- | --- |
| Captions, numeric overlays, camera, radar mode/size, native HUD text layout | Local per client; capture and restore each player's own state. |
| Material and weather appearance | Replicated scene intent; each client applies presentation locally. Check assets/capabilities on every peer. |
| Mission fixtures, AI commands, damage and removals | Only the authoritative owner mutates shared objects, after ownership validation. |
| SP AI overrides, radar range/period trials, gravity/ballistic changes, team-filter regression bays | Skipped in v1 MP; separate qualification required. |
| Radio policy and music | Local opt-in; do not change another player's audio preference. |
| Autosave and explicit EXU save action | Disabled in MP. Verify engine autosave produces no writes. |
| Destruction | Native authoritative death; each peer renders its supported chunks. Compare model/cleanup, not identical random fragment trajectories. |
| Objectives and names | Explicitly synchronized; the shared reference says these do not replicate automatically. |

Extend the established CRCoop adapter for this content rather than copying the older generic sync example verbatim. That example uses a numeric packet type; the current shared reference and CRCoop use string types, with only the first character significant and approximately 244 bytes of payload.

Reserve a distinct one-character showcase type, provisionally `X`, without colliding with CRCoop's `H/Q/K/P`. Use compact primitive payloads carrying protocol version, session epoch, sequence, opcode, scene/variant and elapsed state. Keep each serialized packet comfortably below the actual transport limit, measured in tests. `Receive` must authenticate the known campaign authority for state updates, bound values, ignore old/duplicate sequences and rate-limit client requests. Do not send Lua tables, registry references, Ogre pointers or local ordnance handles.

Late join uses a compact authoritative snapshot and applies the current scene state rather than replaying destruction/spawn cues. Cache intent until fixture handles become valid. Use a scene/epoch clock derived from received elapsed state; do not compare unrelated peers' absolute `GetTime` values or broadcast every render frame. Visual differences from unsupported local capabilities are reported separately from simulation divergence.

`MakeExplosion` is local-only in project testing, so it is not a replicated destruction primitive. Do not call `SetLocal` as a synchronization shortcut. Validate paired host/client runs before listing this mode as multiplayer-safe.

## Implementation sequence and acceptance

1. **Small vertical slice:** author the outpost's safe center, one hangar and arrival/material camera paths. Build the director, real overlays, per-object material comparison, cancellation and free-play handover. Run in the GOG development install with the documented serialized/windowed harness.
2. **Visible chapters:** add environment, native AI, destruction and filters as separate fixtures. Calibrate shot lengths and observation thresholds. Add cockpit layout/radio/command interactions. Reuse verified CR assets and modules.
3. **State and regression:** add reset/replay, capability/result contracts, bounded logs, save/load recovery and the actual autosave/options exercise. Validate mission packaging and content-lock changes in the canonical CR checkout.
4. **Network subset:** add CRCoop authority/session handling, local presentation, scene snapshots and late join. Keep excluded gameplay trials visibly skipped until qualified.
5. **Polish and qualification:** subtitles and accessible captions, camera/framing refinement, resolution/backend checks, repeatable evidence and release documentation. Publishing remains a separate action.

The first useful milestone is a short playable arrival/material prototype, not the entire production matrix. Continue chapters only after its camera and interaction direction is accepted or a broader implementation is explicitly requested.

Minimum runtime acceptance:

- Complete the film, cancel it in each chapter, replay each bay three times and return to free play with valid control/HUD/radar.
- Validate actual material assignments and unchanged control twins; observe correct glow/shadows and baseline restoration.
- Observe clear/dust/clear on a stable horizon, without duplicate weather systems or competing environment writers.
- Observe real AI movement at supported tuning levels, clearing overrides and recreating fixtures correctly.
- Observe asset-backed chunks for selected models, settling/expiry, repeated destruction and next-map cleanup.
- Exercise all four filter variants and stock control for each chosen object class, including valid projectile owners and proximity arming.
- Exercise native command interception, manual trigger, polling fallback if available, removal/default Hunt and unit lifecycle; listen to real radio comparisons.
- Test cockpit/native text/radar layout at 1280×720, 1920×1080, a higher UI scale and ultrawide. Change resolution/scale mid-mission and recheck after load.
- Load the dedicated save and an actual engine autosave; test save during a film, pause/options deadlines, restart and unrelated next mission for leaked state.
- Run missing-EXU/stub, no-Shim, disabled/missing chunk resources and unsupported effect/profile cases: continue safely and report honest blocked/skipped results.
- For the MP subset, run host plus client, local camera cancellation, late join, duplicate/out-of-order state, ownership constraints and leader departure; confirm no save writes or forbidden SP tuning calls.
- Before shipping, cover Windows/GOG and Steam, then the repository's supported Proton/Wine routes; qualify Redux and supported Enhanced backends separately. A passing host Lua test or build is not runtime visual evidence.

Host-side tests, when implemented, should cover the director's cue crossing/cancel/reset/save behavior, request-versus-effective result classification, missing APIs, and compact network authority/sequence handling. Use narrow fixtures; do not mirror every authored value in trivial tests.

## Source references

All links below are pinned to the reviewed snapshots. Current source implementations take precedence over older plans or editor stubs.

1. [OpenShim repository rules](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/fd328e0087e3ca90900024aea2719f88787d46ce/AGENTS.md), [CR repository rules](https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined/blob/91878ec9230ad2cb3b59caccfff21d3e1fab3b19/AGENTS.md), [EXU repository rules](https://github.com/GrizzlyOne95/ExtraUtilities/blob/68991210d613d76e20f5fc6bd1531c9012dfbcc2/AGENTS.md): ownership, canonical checkout and validation boundaries.
2. [Shared Lua reference](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/fd328e0087e3ca90900024aea2719f88787d46ce/Docs/BZR_LUA_AGENT_REFERENCE.md): mission callbacks, cameras, save types, multiplayer locality and packet limits.
3. [EXU definitions](https://github.com/GrizzlyOne95/ExtraUtilities/blob/68991210d613d76e20f5fc6bd1531c9012dfbcc2/Definitions/ExtraUtils.lua) and [runtime registration](https://github.com/GrizzlyOne95/ExtraUtilities/blob/68991210d613d76e20f5fc6bd1531c9012dfbcc2/src/luaexport.cpp): exposed API inventory.
4. [AI/HUD bridge implementation](https://github.com/GrizzlyOne95/ExtraUtilities/blob/68991210d613d76e20f5fc6bd1531c9012dfbcc2/src/Patches/AiHudBridges.cpp) and [native mission overrides](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/fd328e0087e3ca90900024aea2719f88787d46ce/src/patches/mission_hook_bridges.cpp): tuning subsets, mirrored read-back, mission reset effects.
5. [HUD sprite implementation](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/fd328e0087e3ca90900024aea2719f88787d46ce/src/patches/hud_sprite_rects.cpp), [EXU HUD bindings](https://github.com/GrizzlyOne95/ExtraUtilities/blob/68991210d613d76e20f5fc6bd1531c9012dfbcc2/src/UI/ControlPanel.cpp), [EXU radar](https://github.com/GrizzlyOne95/ExtraUtilities/blob/68991210d613d76e20f5fc6bd1531c9012dfbcc2/src/UI/Radar.cpp): supported existing layout operations.
6. [Command implementation](https://github.com/GrizzlyOne95/ExtraUtilities/blob/68991210d613d76e20f5fc6bd1531c9012dfbcc2/src/Game/CommandReplacement.cpp) and [unit VO policy](https://github.com/GrizzlyOne95/ExtraUtilities/blob/68991210d613d76e20f5fc6bd1531c9012dfbcc2/src/Patches/UnitVo.cpp): native Hunt origin, polling fallback and actual queue hooks.
7. [Team-filter implementation](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/fd328e0087e3ca90900024aea2719f88787d46ce/src/patches/team_filter_mines.cpp): ODF parsing, shield/magnet classification and stock proximity detonation.
8. [Chunk rendering and asset requirements](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/fd328e0087e3ca90900024aea2719f88787d46ce/CHUNK_RENDERING_EXPLAINED.md): compatible resources and DLL-only limits.
9. [Environment](https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined/blob/91878ec9230ad2cb3b59caccfff21d3e1fab3b19/Scripts/Environment.lua), [CRWeather](https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined/blob/91878ec9230ad2cb3b59caccfff21d3e1fab3b19/Scripts/CRWeather.lua), [reactive presentation](https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined/blob/91878ec9230ad2cb3b59caccfff21d3e1fab3b19/Docs/CR_REACTIVE_PRESENTATION.md): one writer, storm controls, lifecycle and particles.
10. [RuntimeEnhancements](https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined/blob/91878ec9230ad2cb3b59caccfff21d3e1fab3b19/Scripts/RuntimeEnhancements.lua): per-handle materials, emissive effects and command-update ownership.
11. [CRCoop](https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined/blob/91878ec9230ad2cb3b59caccfff21d3e1fab3b19/Scripts/CRCoop.lua): team-1 authority, humans/enemies, handshake and phase handling.
12. [CR camera use](https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined/blob/91878ec9230ad2cb3b59caccfff21d3e1fab3b19/Scripts/misn03.lua), [separate setup entry](https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined/blob/91878ec9230ad2cb3b59caccfff21d3e1fab3b19/Config/crsetup.ini), [campaign progression config](https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined/blob/91878ec9230ad2cb3b59caccfff21d3e1fab3b19/Config/campaignReimagined.ini): camera precedent and bonus-entry separation.
13. [Autosave behavior](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/fd328e0087e3ca90900024aea2719f88787d46ce/Docs/autosave.md) and [reviewed configuration](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/fd328e0087e3ca90900024aea2719f88787d46ce/openshim.ini): native timer, menu/network gates, user options and configuration differences.
14. [Native SDK/music status](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/fd328e0087e3ca90900024aea2719f88787d46ce/Docs/OPENSHIM_SDK_V2.md), [actual music provider](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/fd328e0087e3ca90900024aea2719f88787d46ce/src/patches/openshim_sdk_provider.cpp), [existing music fixture](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/fd328e0087e3ca90900024aea2719f88787d46ce/reverse_engineering/test_missions/lcbench_music/music.lua): implemented change/stop and fail-closed stubs.
15. [Render-effect status bridge](https://github.com/GrizzlyOne95/ExtraUtilities/blob/68991210d613d76e20f5fc6bd1531c9012dfbcc2/Docs/OPENSHIM_RENDER_EFFECT_BRIDGE.md) and [native effect intent](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/fd328e0087e3ca90900024aea2719f88787d46ce/src/engine/render_effect_intent.cpp): request/support/effective distinction.
16. [Platform compatibility](https://github.com/GrizzlyOne95/ExtraUtilities/blob/68991210d613d76e20f5fc6bd1531c9012dfbcc2/Docs/BZR_PLATFORM_COMPATIBILITY.md) and [CR LogPaths](https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined/blob/91878ec9230ad2cb3b59caccfff21d3e1fab3b19/Scripts/LogPaths.lua): test/deployment matrix and diagnostics routing.
