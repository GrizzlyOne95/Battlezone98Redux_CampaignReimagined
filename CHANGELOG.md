# Changelog

## 2026-09-08

### OpenShim 1.0.0.22

**Fixed a crash when leaving Multiplayer for the main menu.** OpenShim adds a
Career page to the title screen, and kept re-applying that page's hidden state
to widgets the title screen had already destroyed. Going into Multiplayer and
coming back could then fault inside the stock shell. Repeated Multiplayer
visits in a single session are safe again.

**Battlezone Pro compatibility in the multiplayer waiting room.** Several
OpenShim additions were drawing over BZP/BZP-T's own lobby, or replacing its
data:

- The mod-scoped starting-vehicle reload now ships off. BZP's map vehicle list
  is faction-only, and the reload replaced it with stock ships. The map-list
  scroll wheel is unaffected and still works. Turn `VehicleListModScoping` back
  on for Workshop maps that need the vehicle list to follow the selected mod.
- The nickname field and route readout stay on -- they sit in the empty left
  column and do not cover BZP's faction picker. The Ban User button and the
  flag selector ship off, because those do sit on the faction/vehicle cluster.
  `/ban` still works.
- OpenShim no longer forces the reticle range back down in network games, so
  BZP's longer reticle is honored.

The crash fix is in the shim itself and reaches every install. The waiting-room
defaults above are settings, and an existing `openshim.ini` is never
overwritten, so an install created before this update keeps its current values
until they are changed by hand.

### OpenShim 1.0.0.21

- The disabled Multiplayer entry now explains whether platform sign-in,
  service transport, or authorization is blocking it instead of showing only
  the same bare `Not Ready` caption for every cause.
- A low-volume `[MPREADY]` log records readiness state changes without logging
  the player's name, giving support reports useful evidence immediately.
- GOG no longer runs the Steam-only multiplayer map-sort frame probe.

### OpenShim 1.0.0.20

**Steam installs were quietly missing several fixes.** Steam's copy-protection
layer rewrites part of the game a fraction of a second after launch. The
patcher looked for its patch sites too early, found nothing, and gave up for
the rest of the session -- so a number of fixes never applied at all on Steam
while the same build worked correctly on GOG. It now waits for the image to
settle and retries. On Steam that restores the pilot carrier crash guard, the
AI build-prerequisite fixes, and correct multi-producer build behaviour.

The log was also misreporting this: a patch whose signature failed to match was
announced as a missing config file, which pointed at redeploying something that
was already correct. Signature failures and missing entries now report
separately.

**Two crash fixes.** Moving between pilot and vehicle could crash -- the pilot
flashlight was destroyed while Ogre still held it in the current frame's light
list. And a mission whose pilot ODF declares its hardpoints under the wrong
section never allocates a weapon carrier, which the game then walked without
checking; that crashed on the first simulation frame. Found loading Hell Gate
II, and it affects any mission authored the same way.

**Less disk churn.** The shader microcode cache was rewritten every ten seconds
for the whole session even when nothing had changed -- an identical 164 KB
file, roughly 75 MB of pointless writes in a 90-minute session, and more
expensive on Linux where it crosses the Proton file layer. Ogre never clears
its own cache-dirty flag after a save, so the shim now clears it and writes
only on a real change.

Also in this build: turret tanks converge fixed weapons through the same path
as wingmen and walkers; radar size scaling with the projection re-anchored to
the backdrop; faction jet flames in blue, CCA orange and Black Dog red;
satellite zoom/pan limits and optional ordnance velocity inheritance as
single-player keys; and launching the bare executable no longer resumes the
rolling AutoSave recovery slot.

For mission authors: `.bzn` loads can be traced object by object with
structural checks on the file, off by default. World Builder source-folder
saving is present as a developer prototype, off by default and not yet
qualified.

Interactive ground fog wakes are in the build but not enabled and have no
in-game effect yet.
## 2026-09-07

### Mars weather: continuous transitions and a real-time clock

- Fog, ambient, sun diffuse and sun power no longer snap when the weather
  changes rung. The atmosphere contribution read only the *incoming* preset at
  weight `Blend`, and `SetPreset` restarts `Blend` at 0, so every change dropped
  the whole atmosphere back to the bare mission baseline for a frame and then
  ramped the new preset in over 18-30 seconds. `CRWeather` now keeps a weight per
  live preset and only ever moves ramp targets, which makes a change continuous
  by construction — including a change that interrupts a transition still in
  flight, which a single incoming/outgoing pair cannot express.
- The weather clock now comes from `GetTime()` instead of the caller's fixed
  `1.0 / M.TPS`. `Update` runs once per rendered frame, so that delta was a frame
  count: at 120 fps the weather ran six times real speed, rungs whose dwell is
  35-160 s re-rolled every 6-25 s, and gusts fired several times a second. This
  is what made the atmosphere snap repeatedly rather than occasionally.
- A preset displaced part way through a transition no longer strands its particle
  systems in the scene. The sweep only ever matched a single `Previous`, so those
  systems stayed for the rest of the mission at zero weight.
- `Tools/Test-CRMarsWeather.lua` asserts atmosphere continuity across a preset
  change and across an interrupted transition, and that no particle system
  outlives the preset that owns it.

### Mars weather for misn04

- Added `CRMarsWeather`, a Mars weather director layered on `CRWeather`. Weather
  now walks a five-rung ladder (calm, breezy, rising, storm, severe) one rung at
  a time, biased toward a target the mission sets. Integer crossings swap the
  preset; the fractional ladder position drives wind, sensors and visibility, so
  those slide through a transition instead of stepping when the preset changes.
- Wind is live rather than a preset constant: a prevailing bearing that wanders
  under a turn-rate cap, a base speed from the ladder, and discrete gusts with a
  rise/hold/fall envelope that also veer the bearing as they pass. `CRWeather`
  gained a wind override so the dust follows it -- steering emitter direction and
  scaling emitter velocity, because a gust that only changes particle *count*
  reads as a density flicker rather than as wind.
- Added dust devils: world-placed, spawned upwind of the player, drifting
  downwind and re-sampling terrain height, spinning up and down through their
  emission rate. They only form on the calmer half of the ladder, which is
  physical rather than a budget dodge.
- Added three Mars presets (`MarsHaze`, `MarsDustRising`, `MarsDustStormSevere`)
  and extended `MarsDustStorm` with a ground-hugging sheet-dust layer, a haze
  layer and a gust envelope. New particle templates: `CR/Weather/MarsHaze`,
  `DustSheet` and `DustDevil`.
- Weather now degrades sensors. Radar range, radar refresh and velocity jamming
  scale with storm severity through a **new gameplay-modifier hook** in
  `Environment`, so `ProcessObjectNightEffects` stays the single writer. A direct
  write would have been clobbered within the second, and worse, would have been
  captured as the craft's stock baseline and made the degradation permanent.
- Wind adds a small lateral component to gravity, so a gale is felt through the
  controls and unguided ordnance drifts downwind. Capped, opt-out, and restored
  on shutdown.
- Wired into misn04. Weather beats are recomputed from mission state each frame
  rather than latched, so a mid-mission save lands on the right weather; the one
  exception is the set piece, where the final CCA wave arrives inside a forced
  severe storm.
- Fixed a latent save-load bug in `CRWeather`: loading a save rebuilds the Ogre
  scene and destroys every particle system, but `LiveSystems` still named them,
  so the next preset application "retargeted" systems that no longer existed and
  the weather silently never rendered again. Added `CRWeather.ResetSystems()`,
  which the load path now calls.
- Fixed both `Environment` modifier loops iterating a list they mutate: a
  throwing modifier is unregistered from inside the loop, and `table.remove` on
  the live list shifted the next entry past the cursor and skipped it.

### Reactive presentation and dynamic weather (first pass)

- Added `CRWeather`, a proper atmospheric weather controller. Weather is now
  camera-centred Ogre particle systems plus fog, sky and lighting state, not
  scripted explosion effects. Six data-driven presets ship: MarsDustStorm,
  LunaLightSnow, EuropaBlizzard, VolcanicAsh, FurySporeStorm and
  AcidRainVisual, with crossfaded transitions, gust phases, a shared wind
  vector, and lightning as an illumination event rather than an object.
- Added `CRReactive`, a shared reactive-presentation layer. Impacts now produce
  weapon-specific particles at the contact point and a directional first-person
  reaction on the player's craft; craft progress through persistent damage
  bands with their own smoke, sparks and arcing; status lighting dims and
  flickers as damage rises; and weapon heat accumulates and decays per shot.
  None of it changes damage, balance or AI.
- `Environment` gained a modifier hook so fog and sun state keep exactly one
  writer. Weather contributes into Environment's own per-frame targets instead
  of issuing competing renderer writes, which is what would otherwise show up
  as flicker during a storm.
- Both systems are bounded by design: precipitation is a camera-local volume,
  off-screen storms stop simulating, impact effects reuse a fixed pool, damage
  VFX are capped and distance-gated, and health polling walks a rotating slice
  so a large battle costs the same per frame as a small one.
- Both systems release everything on mission teardown -- particle systems,
  material overrides, emissive clones, the sky swap, and the ordnance callback
  chain -- so nothing carries into the next mission.
- Damage-state materials and cockpit animations are named but not yet authored.
  The systems check for them and skip what is missing, so everything else runs.
  `Docs/CR_REACTIVE_PRESENTATION.md` carries the wiring guide and asset list.

## 2026-09-05 (third update)

### OpenShim 1.0.0.17

**Several settings were quietly doing nothing.** On a default install, two
internal timers that most of OpenShim's per-frame and per-tick work hangs off
were switched off along with an unrelated chunk-rendering option. The headlight
controls were the most visible casualty: turning player or AI headlights on,
picking a colour, or choosing a beam shape had no effect at all, because the
code that applies them never ran. The radar layout fix, the multiplayer flag
fallback, the satellite fog-of-war sync and the periodic multiplayer safety
check were in the same boat. All of them work now. If you tried the headlight
settings before and concluded they were broken, they were -- try them again.

**New, off by default: a flashlight on your pilot.** When you are on foot your
pilot can now carry a spotlight that points where you look. Battlezone only
ever gave lights to vehicles, so this is a new one, built the same way the game
builds a vehicle headlight.

Turn it on with `[SinglePlayer] PilotFlashlight = 1`, or from the OpenShim
Settings page, which also has colour and beam-shape rows. The ini additionally
exposes `PilotFlashlightOffset`, `PilotFlashlightPitch` and
`PilotFlashlightBone` if you want to move the light off your eye line -- for
example to sit it low and to the right like a torch held in one hand.

It is single-player only and stands down for the duration of a network game.

## 2026-09-05 (second update)

### OpenShim 1.0.0.16

**Fixes a crash that could end your game mid-match.** Typing `/nickname` (or
its `/name` alias) during a multiplayer match could terminate Battlezone
outright. The lobby screen and its widgets are destroyed when a match starts,
but the display refresh that runs after every accepted rename was still
handing one of those destroyed widgets to the engine. It only checked that it
had a pointer, not that the pointer still pointed at anything.

This is worth spelling out because the obvious workaround did not work: the
refresh ran outside the live-nickname setting, so turning that setting off did
not protect you. If you have had an unexplained multiplayer crash shortly after
someone changed their name, this is a likely cause.

**Renaming now tells you the truth.** Changing your multiplayer name mid-session
used to report "applied live". It was not applied live -- no other player ever
saw the new name. The name is read only when a connection is authorised, so
changing it afterwards did nothing until you reconnected. It now says it has
been saved for the next connection, which is what actually happened.

**Optional, off by default: renaming without restarting.** Setting `[Network]
ReauthOnNicknameChange = 1` lets a rename made in a lounge or lobby re-authorise
your existing connection, so the new name appears to other players without
restarting the game. It is experimental and deliberately off. It does nothing
during a match, and it never reconnects you on its own. Leave it off unless you
are helping test it.

## 2026-09-05

### OpenShim 1.0.0.15

No change to how the game plays. This release adds an opt-in diagnostic and
refreshes the public roadmap; if you are not chasing a specific multiplayer
bug, there is nothing here you need to turn on.

**Multiplayer player-kill research trace.** Redux records a multiplayer death
against a *team* rather than against the object that fired, so killing another
player and killing that player's AI wingman look identical to the scoreboard.
A new `[Diagnostics] TracePlayerKills` setting writes one compact record per
authoritative death with the candidate ownership fields for both victim and
killer, plus how confidently the death can be tied back to the last damage
event. It is off by default and none of its hooks are installed unless it is
switched on. It changes no scoring and no career statistics, and what it
prints is a hypothesis being tested, not a verdict -- an object is never
called player-controlled merely because its team has a network player, since
wingmen share their owner's team.

**Roadmap corrections.** The Splinter multiplayer payload-duplication entry
carried a root cause that turns out to be contradicted: the deployed producer
clears its payload's send flag immediately after building it, and the send
path only handles a nonzero flag, so that payload is never transmitted and the
other peer is not receiving a duplicate of it. The bug report stays open, but
the explanation was wrong and the fix people kept proposing would not have
helped. The two Daywrecker entries are now marked as blocked on a two-peer
capture rather than on further static analysis.

**Platform support is now stated on the Workshop page.** Windows and Linux are
both supported, on Steam and on GOG; Linux and Steam Deck run the same 32-bit
Windows files through Proton rather than a separate build.

## 2026-09-03

### OpenShim 1.0.0.14

- Fixed Enhanced renderer resources being reported as unavailable when they
  were supplied by the active Campaign Reimagined Steam Workshop mod rather
  than copied beside the game executable. OpenShim now validates the same
  addon, mod, packaged-mod, and Workshop content roots that Redux loads.

## 2026-09-02

### OpenShim 1.0.0.13

Updated the bundled OpenShim DLL to 1.0.0.13.

**The Options page is reachable again on affected installs.** A previous release switched every OpenShim setting off by default, including the two keys that are not features but the way you reach every other feature. On an install that received those defaults the OpenShim Options page did not appear at all, so there was no way to turn anything back on without editing `openshim.ini` by hand. The shipped defaults were corrected the next day, but the config-migration version was never advanced, so existing installs kept the broken values and no later update could repair them. This release advances it and reopens both pages. A setting you deliberately changed yourself is left alone.

**Career statistics now work everywhere, with no scripting.** Kills, deaths and missions played are recorded across single player and multiplayer without any mission needing to implement tracking, written to a local `career_stats.cfg`. Nothing is uploaded anywhere. It is on by default and can be switched off, and there is a two-click Reset Career Stats row beside it that keeps a backup of the previous record. Previously only multiplayer was tracked natively and single player relied on campaign scripts.

**Stock Factions host rule.** New `[Network] StockFactionsOnly` (off by default) restores the restricted multiplayer starting-vehicle pool that Battlezone 1.5 offered when Any Nation was turned off. Redux merged the two 1.5 pools into one and removed the choice. This only ever removes factions from the list; it can never add a craft, and a map that supplies its own vehicle list still wins.

**Fixed a crash when quitting a mission.** The first-person pilot tracer could follow a scene manager that had already been destroyed and take the process down with it.

**The main menu now shows the OpenShim build version** next to the game version, so you can confirm which DLL is actually loaded.

Also included: a native event layer that these features are built on, and an opt-in walker cockpit diagnostic that is off unless you enable it.

## 2026-09-01

### Legacy terrain restored from the original Battlezone 1.5 heightmaps

- Added unsmoothed `.hg2` terrain for 36 stock campaign maps, converted directly
  from the Battlezone 1.5 `.hgt` originals. Redux normally cooks legacy `.hgt`
  at load time and finishes with a 3x3 box blur, which rounds off authored
  stair-steps, mesa rims and ridge lines. These files perform the same 2x
  piecewise-planar upsample the engine does and skip that blur, so every
  original 1.5 height sample is reproduced exactly and the geometry between
  samples is the surface the 1998 engine actually rendered.
- Redux loads `.hg2` in preference to `.hgt`, so no `.trn` or mission change is
  needed; the terrain is simply no longer smoothed.
- `misn02b` is a deliberate exception to "matches stock": Rebellion shipped
  hand-modified terrain there rather than a conversion of the 1.5 map, so this
  reverts that mission to the authentic 1.5 geometry.


## 2026-08-30

### OpenShim 1.0.0.9 and conservative player defaults

- Updated the bundled OpenShim DLL to 1.0.0.9. The native OpenShim Options and
  keybinding pages now render distinct value buttons and reliably receive row
  clicks. Raw Mouse Input is available directly on the Options page and remains
  off by default.
- Workshop installation now deliberately replaces `openshim.ini` with the
  complete conservative player preset, where OpenShim features and diagnostics
  are opt-in. The previous file is retained as `openshim.ini.pre-workshop.bak`.
- Added the OpenShim Enhanced renderer resources and the four native Options UI
  tiles to the Workshop package so the DLL cannot be paired with missing data.

## 2026-08-23

### Settings split: engine options moved to openshim.ini

The campaign's settings file is now strictly campaign settings. Options that
are implemented by the OpenShim patch itself -- and therefore work with or
without Extra Utilities, in the stock campaign, Instant Action and custom maps
alike -- have moved to `openshim.ini`, where they are documented in full.

Moved out of `campaignReimagined_settings.cfg`:

| Was (campaign setting) | Now (openshim.ini) |
| --- | --- |
| `UnderAttackAlertMode` | `[Display] UnderAttackAlert` |
| `TargetReticlePopupMode` | `[Display] TargetPolicy` |
| `TurretAimPitchEnabled` | `[SinglePlayer] TurretAimPitch` |
| `AttackRevealEnabled` | `[SinglePlayer] AttackRevealPerceivedTeam` |
| `BomberAiRangeEnabled` | `[SinglePlayer] BomberAiRange` |
| `AiOdfGameplayTuningEnabled` | `[SinglePlayer] AiOdfGameplayTuning` |

The first four already existed in `openshim.ini`; the campaign was setting them
a second time through Extra Utilities and winning, so the setting you chose in
the OpenShim Options page was silently overridden while the campaign was
loaded. That no longer happens. `BomberAiRange` and `AiOdfGameplayTuning` are
new `openshim.ini` keys -- the features were always native, but until now the
only way to switch them on was the campaign.

The **Attack Beep** and **Hit Reticle** rows are gone from the campaign's PDA
settings page. Both live on the OpenShim page of the Options screen and in
`openshim.ini`.

Two settings were removed outright: `HowitzerVolleyEnabled` and
`WeaponMaskCarrierBiasEnabled`. Neither has done anything for some time -- the
patch reads neither value -- so they were dead switches on the menu.

Existing settings files need no migration: the removed keys are ignored on load
and dropped the next time settings are saved.

### Unchanged

Everything the campaign actually implements stays where it was -- lighting
modes, headlights, subtitles, the PDA overlay and its colours, radar scale,
team colours, auto-repair, pilot mode, scavenger assist and the Lua autosave.
Those depend on Extra Utilities and are campaign behaviour, not engine
behaviour.

## 2026-08-20 (experimental, visual validation pending)

### DX11 Enhanced dynamic-light audit

- Confirmed that Enhanced High already accepts up to 24 lights per renderable;
  Ogre's default value of eight acts as a sentinel and does not truncate this
  ordinary non-iterated pass path. No CR material or shader change was needed.
- The paired OpenShim experiment contribution-ranks the existing candidate list
  with deterministic tie-breaking and small cutoff hysteresis. Classic and DX9
  behavior remain unchanged.
- Native tests, all 208 DX11 SM4 shader permutations, and an unattended runtime
  probe pass. Interactive visual/frame-time acceptance is still required.

## 2026-08-17

Covers everything since the 2026-08-15 Workshop upload.

### AutoSave

- **AutoSave now actually runs.** OpenShim's own autosave has been present and
  fully wired for some time — settings, interval, mission detection, the lot —
  and had never executed once. The shim asks "is this a supported build?" before
  starting it, and the answer was hardcoded to no: the version check ran, passed,
  and then never recorded that it had passed. Any AutoSave you have been getting
  came from the campaign's bundled Lua script, not from the patch.
- With that fixed, AutoSave works in **any** single-player content — the stock
  campaign, rewritten missions, custom maps, Instant Action — with no dependency
  on Lua or Extra Utilities. It writes a rolling recovery slot roughly ten
  seconds into a mission and every two minutes after that, and never while you
  are paused, in a menu, or in edit mode.
- It also stays out of the way of the Lua autosave rather than fighting it: if
  something else updates the save, OpenShim notices and waits its turn.
- Turn it on or off and set the interval (1, 2, 3, 5 or 10 minutes) from the
  OpenShim page of the Options screen. Both apply immediately, no restart.
- AutoSave is a *recovery* slot, not a replacement for saving. It is one rolling
  file and it overwrites itself. Keep making your own saves.

### Single-player fixes

These shipped in the last build's source but were left out of its notes.

- **Smart reticle range no longer disturbs anything else.** The reticle's range
  was being written into a constant the compiler shares between many unrelated
  parts of the engine, so changing it altered that value everywhere it was used,
  not just for the reticle. The reticle now reads its range from a private
  location of OpenShim's own, and stands down and leaves the shared value alone
  if the code does not look the way it expects. This also makes reticle
  convergence aim where it should, since that range is what caps how far down
  the sight the aim point can land.
- **Jump-snipe crouch restored for real.** The player-object lookup it depends on
  was only ever set up inside a diagnostic probe that is off unless a developer
  environment variable is set, so it silently did nothing in normal play.

### Multiplayer netcode

- The shim now applies the full network tuning block itself. It previously set
  only the four auto-kick values and left the send-rate governor and the
  bandwidth floor/ceiling to `net.ini` — and `net.ini` does not reliably reach
  the game, because Battlezone only parses that file for the session's active
  mod. A match on 2026-08-12 was measured collapsing to 4,000 bytes/sec, the
  stock floor, while `net.ini` asked for 16,000. All ten values are now written
  directly, so the tuning actually takes effect.
- The practical effect: the send rate no longer collapses to a trickle after a
  bad stretch and then take minutes to recover. The floor is four times higher,
  the ceiling no longer throttles a healthy connection, and recovery now runs
  twice as fast as back-off instead of five times slower.
- Fixed a bug that could jump your send rate tenfold in the middle of a match.
  The shim watches for the value the game writes at match start and raises it;
  it was also matching that same value when the rate simply fell that far during
  a bad patch, and treating it as a new match. Those two cases are now told
  apart, and both are logged so the difference is visible.
- Every network address the shim writes is now checked before it is written. If
  a game update moves one, that value is skipped and reported rather than
  written blind.
- The shim now measures its own outbound traffic — peak packets per second and
  how long it spends bursting. This is what separates a normal session from one
  where a connection is flooding, and until now nothing recorded it.

Thanks to the PiercingXX Battlezone netcode-patch project, whose field testing
established most of the above.

### Diagnostics

- Relay and lobby-server logging is now a single switch: `RelayLogging` in the
  `[Diagnostics]` section of `openshim.ini`. It captures the lobby connection,
  the peer-routing negotiation, and the underlying traffic together, and now
  says in the log whether it started — previously "logging was off" and "logging
  was on but caught nothing" looked identical in a report.
- Two further switches for deeper work: `RelayLogAllControl` records the whole
  lobby conversation rather than just the routing messages, and
  `RelayLogDatagrams` records every packet on the relay ports unsampled.
- Map-list and jump-snipe tracing are now normal INI settings instead of
  environment variables only.
- `net.ini` is rewritten to document every setting it accepts, what each one
  does, and the evidence behind the chosen value. `openshim.ini` documents the
  new diagnostics.

Privacy note: relay logs record public addresses, account identity and lobby
metadata for everyone in the session, not just you. They are off by default.
Read one before sharing it.

## 2026-08-15

Covers everything since the 2026-08-06 Workshop upload.

### Destruction Chunks
- Buildings and vehicles now break apart into their real modelled pieces in many
  places that previously threw generic rock debris. The number of visible pieces
  falling back to a generic placeholder dropped from 177 to 62.
- Fixed the Hadean relic buildings, whose models name their pieces after
  modelling-tool nodes rather than the names the game asks for. The correct
  mapping was recovered by matching each Redux piece against the original
  Battlezone geometry of the same building.
- Fixed the NSDF hangar, which shipped every piece under a duplicate bone name
  and so exploded entirely into placeholders.
- Added the missing Black Dog storage bay and second barracks pieces, and the
  NSDF/Black Dog landing pad piece whose model bone carries a stray underscore.
- Black Dog buildings now use their own textures when they shatter instead of
  borrowing the NSDF equivalents.
- Chunk pieces keep the shading the artists authored. A toolchain change had
  started rebuilding normals from scratch, which shades blocky debris as though
  it were smooth.
- Interior caps are generated for the new pieces, so freshly broken chunks read
  as solid rather than hollow shells.

### AutoSave
- The AutoSave button on the load screen now names the mission it will restore
  instead of just reading "AutoSave". This works without EXU installed.
- Career statistics no longer file every autosave-resumed session under a single
  bogus mission.

### Rendering (DX11 Enhanced)
- Static image-based lighting across base and terrain shaders, with a neutral
  reference asset set.
- Legacy-PBR lighting for base and terrain, with terrain tuning that preserves
  emissive surfaces across level-of-detail changes.
- Atmospheric rendering pass, and an experimental linear-light colour path.
- PDA and EXU overlays render correctly on DX11: programmable overlay and font
  materials, a tint shader, and a corrected panel vertex input layout.
- Added a DX11 shader validator and wired it into CI, plus a colour-space audit
  and runtime probe.

### Missions
- Scripted enemies in missions 02B, 03, 04 and 05 are kept out of the general AI
  pool, including across save and load.
- Restored Mission 04's fallback defender position and fixed an overlay call left
  behind by an ownership refactor.

### Multiplayer and Engine
- Lobby name panel: clicks register, long names truncate correctly, and renaming
  applies at connect time.
- Ogre runtime resolver and an animation/render overhead profiler for diagnosing
  performance.
- HD terrain path and semantic terrain streaming, opt-in.
- `openshim.ini` is now an exhaustive configuration reference and runtime feature
  gates are driven from it rather than environment variables.
- Observational network instrumentation for diagnosing multiplayer issues; it
  records nothing without being explicitly enabled and redacts identities.

### Housekeeping
- Retired legacy scripts, hardened the campaign runtime, and defined the
  project's actual scope in the README.
- Workshop publishing is automated and the capped chunk-mesh tree is routed
  through deploy correctly.

## 2026-07-16

### PDA Navigation and Readability
- Reorganized the PDA into `COMBAT`, `RECORDS`, `LOGISTICS`, and `SYSTEM` groups with short contextual sub-tabs.
- Reordered pages around player workflow while retaining all seven views and their existing controls.
- Streamlined the unit, target, career, command, queue, and loadout readouts; weapon details now use an Up/Down inspection cursor instead of expanding every hardpoint at once.
- Split Settings into focused `Interface`, `Lighting`, `Audio & Alerts`, `Assistance`, `Saves`, and `System` categories while preserving continuous Up/Down navigation through every option.

### AutoSave Notice
- Extended the `Autosaving...` notice to five seconds and moved its dedicated EXU overlay to the bottom center of the screen.

## 2026-07-13

### Neutral Hit Reticle
- Restored the persistent PDA `NEUTRAL ONLY` hit-reticle option now that OpenShim reads the Redux GameObject team through the correct `+0x18` interface subobject.
- Saved mode `2` values are preserved and applied again instead of being migrated back to `DEFAULT`.

## 2026-07-12

### Empty Craft Running Lights
- Added a persistent `Empty Craft Lights` PDA setting. By default, valid craft without a pilot now use an Ogre material variant with emissive lighting disabled; enabling the setting restores normal emissive running lights on empty craft.
- The runtime visual pass uses `IsAliveAndPilot()` and reapplies the occupied emissive variant when a pilot enters the craft.
- Added an optional persistent `Light Pulse` PDA setting. In enhanced lighting mode, occupied/emissive material variants now use a slow 2.4-second shader intensity pulse while empty variants remain black.
- Added a persistent `Star Twinkle` PDA setting. The dedicated `STARS.MAP` pass now uses the campaign Ogre sky shader and gives star cells independent, time-driven brightness variation without per-frame Lua updates.

## 2026-03-24

### Mission Startup Hang Fix
- Fixed a mission-start hang that reproduced on `misn02b.bzn /edit` after `Game Simulation Initialized` completed.
- Root cause: startup still had two blocking `bzfile` read paths. `PersistentConfig` could scan the live `bzlogger.txt` stream while the game was still writing it, and `CareerStats` could open a missing `career_stats.cfg` as a zombie handle and then hang on the first read.
- `PersistentConfig` now relies on `exu.GetSteam64()` for Steam identification and keeps the `bzlogger.txt` fallback disabled until a non-blocking reader exists.
- `CareerStats` now checks file existence before opening `career_stats.cfg`, which avoids the zombie-handle read hang while preserving normal stats loads when the file is present.

## 2026-03-16

### Subtitle Overlay Migration
- Ported mission subtitles from the legacy subtitle DLL path to the built-in EXU/Ogre overlay runtime, while keeping the old DLL submission path as a fallback.
- Reworked subtitle rendering to use PDA-style overlay panels/materials instead of the previous shell-style subtitle window.
- Wired subtitle pause/suspension, opacity, and font scaling to the same persistent PDA settings used by the rest of the HUD.

### Target Page and Weapon Selection
- Updated the PDA `TARGET` page to use `exu.GetSelectedWeaponMask()` so it shows the player's currently selected weapons instead of collapsing to the top weapon slot.
- Added per-weapon in-range markers against the current target using the selected-weapon mask path.

### AutoSave HUD
- Moved the `Autosaving...` notification to a compact bottom-left overlay layout.
- Added an immediate mission-start autosave trigger when autosave is enabled so the overlay can be verified without waiting for the interval timer.

### HUD Settings
- Added a persistent `Radar Size` PDA setting backed by `exu.GetRadarSizeScale()` / `exu.SetRadarSizeScale()`.
- Reapply the saved radar size automatically if the stock HUD scaling menu overwrites the live radar layout scale.

### Verification
- `luac -p _Source/Scripts/ScriptSubtitles.lua`
- `luac -p _Source/Scripts/PersistentConfig.lua`
- `luac -p _Source/Scripts/AutoSave.lua`

## 2026-03-09

### PDA / Weapon HUD Expansion
- Reworked the weapon HUD into a multi-page PDA with `STATS`, `TARGET`, `SETTINGS`, and `PRESETS` pages.
- Moved the PDA panel to the left-middle of the screen and scaled it from EXU HUD/UI scale, screen aspect, and user size presets.
- Added PDA settings for text size, window size, and HUD color presets (`dark green`, `green`, `blue`, `white`).
- Added page navigation on `[` and `]`, plus arrow-key editing for `SETTINGS` and `PRESETS`.
- Added stock menu sound effects for PDA page changes and interactive settings changes.
- Updated the in-game help text to document the new PDA controls.

### Targeting and Weapon Data
- Added reticle-aware aim fallback so the PDA updates immediately from `GetReticleObject()` or `GetReticlePos()` when there is no explicit target lock.
- Added a dedicated `TARGET` page with unit name, target distance, closure/ETA, speed, ammo, hull, and hardpoint summaries.
- Improved weapon stat extraction to read `CannonClass` timing/range fields and ordnance damage correctly for cases like `gtminis2.odf`.
- Added cached ODF-driven weapon stats for range, damage, DPS, shot delay, shot speed, and ballistic detection.
- Added elevation-adjusted ballistic range estimation so mortar-style weapons show a more realistic effective range versus uphill or downhill targets.

### Unit Presets
- Added a `PRESETS` PDA page that inspects live recycler/factory build lists and armory upgrade pools.
- Added persistent per-unit, per-slot loadout presets sourced from actual armory powerups and mapped back to weapon ODFs.
- New player-built units now receive preset weapons on creation and charge a positive-only scrap surcharge when the preset is applied.
- Preset application is now gated by nearby production structure proximity so mission-spawned allied units are far less likely to be modified accidentally.
- Added `Armory not available` handling when no valid armory exists.

### Subtitle Runtime
- Bundled an updated `subtitles.dll` with channelized subtitle layout support used by the PDA window.

### Verification
- `luac -p _Source/Scripts/PersistentConfig.lua`

## 2026-03-08

### AI and Mission Fixes
- Fixed `aiCore` enemy-team selection so neutral `team 0` is no longer chosen as a primary enemy target set.
- Stopped misn04 CCA AI from fixating on neutral geysers during base assault behavior.
- Updated scripted mission control flow so player-team (`team 1`) command wrappers default to priority `0` and no longer steal unit control.
- Fixed misn04 player wingman scripted patrol and retreat orders to use commandable priorities.
- Fixed wingman auto-repair command restore priority so restored orders do not come back as uncommandable for player-owned units.

### Player Howitzer Improvements
- Added player howitzer range-assist behavior: attack orders issued against out-of-range targets now move the unit into firing position and resume attack automatically.
- Reworked the howitzer assist to use the currently equipped weapon and live weapon mask instead of a fixed hardcoded range.
- Added ODF-driven range probing for active weapons with fallbacks for direct range fields, projectile travel distance, and ballistic estimation.
- Fixed the helper ordering bug that caused `aiCore.lua` to error when loading before the `aiCore` table was initialized.

### PDA / Weapon HUD
- Moved the weapon details HUD into a right-side, vertically centered PDA-style panel.
- Added screen/aspect-aware panel sizing using EXU resolution helpers when available.
- Added player speed readout in meters per second.
- Added target closure rate and ETA when a valid hostile target is selected.
- Rebound the PDA / weapon HUD toggle from `Ctrl+S` to `Y`.
- Updated the in-game help overlay to match the new `Y` binding.

### Verification
- `luac -p _Source/Scripts/aiCore.lua`
- `luac -p _Source/Scripts/misn04.lua`
- `luac -p _Source/Scripts/PersistentConfig.lua`
