# Campaign atmosphere integration audit — 15 October 2026

Scope: every campaign mission Lua entry point, Environment, CRWeather and its
presets, all six planet directors, TRN sky/cloud/fog settings, RuntimeEnhancements,
save/load and co-op presentation wiring. Findings below are confirmed by source
inspection and host tests. Visual appearance and native networking remain unqualified.

## Changes resulting from the audit

| Finding | Resolution |
| --- | --- |
| Environment's base/keyframe fog could end beyond TRN visibility; weather alone had a cap. | Clamp authored keyframes and the final composed frame. This includes manual fog and every local modifier. An overlong ramp is scaled into the horizon, retaining an ordered start/end. No terrain draw-distance increase. |
| Io/Europa use the shared moon profile, whose long fog ramps exceeded their 250-unit terrain horizon. | The same final cap covers both, independently of weather severity. Their existing profile/tints and mission beats are retained. |
| Lua replaced native ACT/TRN fog color with a generic brown default. Explicit native sunlight RGB sections were not read. | Capture native fog RGB before script writes, retain compatible NormalView color overrides, and read Sun_Ambient/Sun_Diffuse/Sun_Specular Red/Green/Blue. |
| Moon 02b/03 had no time-varying lighting. Loading the default Environment profile would replace their fog and add a full night cycle. | Explicit subtle mode with a captured native light/sun baseline and authored 175–250 fog. A one-hour smooth lighting variation dims diffuse/specular by at most 6%, ambient by 3%, with a 4-degree azimuth excursion and small elevation drift. No night penalty. |
| Venus 07–09 used a rapid generic full day/night cycle under absolute weather lighting targets. | Subtle native-baseline mode: one-hour variation, at most 4% diffuse/specular dimming, 2% ambient dimming and 2-degree azimuth excursion. Weather retains its distinct gloom/lightning/banks; subtle TOD is applied after those modifiers. |
| Full-weight weather could replace nighttime light with its daytime preset. | Environment supplies a weather-light attenuation factor (1 at day, 0.2 at full night); CRWeather applies it to its ambient/diffuse targets. This leaves flashes and local emissive illumination available. |
| A manual fog transition could feed last frame's weather-composed fog into the base, then apply weather again. | Transition from the last unmodified base fog instead. |
| Public cycle inspection ignored LockDaylight. | Inspection and rendering now use the same cycle-state resolver. |
| Moon/Venus/Io/Europa Load callbacks could retain a started director and skip consuming saved weather state; renderer dirty caches also survived scene reconstruction. | Shut down those directors on Load and let the existing ready-session path consume saved scalars/rebuild particles. Invalidate Environment's renderer cache on load/reset so even an identical frame is reapplied. |
| Mission 06 had no Environment or weather integration. | Reuse CRMarsWeather Plains with story targets, below. Render on every peer, decide on host, route target and actual rung through the existing ordered/acknowledged event transport. Save/restore scalar weather state and rebuild particles. |
| Standalone CRWeather used initial fog end as the terrain limit, which is too short on Titan 14 (175 fog versus 250 visibility). | Prefer TRN VisibilityRange; fall back to captured fog end when TRN/API is unavailable. Cap the final standalone frame too. |

Subtle lighting is a bounded artistic progression over mission time, not a
simulation of a lunar or Venusian day. It uses GetTime rather than frame counts,
and does not repeatedly call the native, hour-quantized SetTimeOfDay function.
The sun sprite/sky artwork is retained. Shadow enablement and shadow range stay fixed.
Phase diagnostics remain in logs rather than being added to the player's HUD.

## Mission coverage after this change

| Entry points | Atmosphere owner | Weather and progression |
| --- | --- | --- |
| misn02b, misn03 | Environment, subtle mode | CRMoonWeather: particle mist, impact/hover dust and small glow contribution; no global fog or cloud creation. |
| misn04, misn05 | Environment, existing full cycle | CRMarsWeather Plains/Volcano: existing story targets and co-op authority retained. |
| misn06 | Environment, full visual cycle | CRMarsWeather Plains: reconnaissance 1; Hephaestus scan 2; starport recon 3; blockade/timed launch-pad assault 4; launch-pad recon/extraction 2. Targets move the ladder, without abrupt forced cuts. |
| misn07–09 | Environment, subtle mode | CRVenusWeather: existing story beats, clouds, local pools/banks and lightning. |
| misn10–11 | Environment, existing full cycle | CRIoWeather: existing volcanic weather and scripted beats. |
| misn12–13 | Environment, existing full cycle | CREuropaWeather: existing snow, vents, haze and mission beats. |
| misn14 | Standalone CRWeather | CRTitanWeather, existing story ladder; no Environment auto-loading. |
| misn01, misn15–18, misns1–8, bdmisn07–15 | Native terrain/engine | No Environment/weather import found. Their TRN baseline remains native; no blanket integration added. |
| crsetup | Native terrain/engine | Installer utility; no weather needed. |
| sxshow / SXExhibits | Exhibition-specific CRStormFX | Separate exhibit with explicit baseline restoration; not a campaign weather caller. |

New mission-06 weather does not change gravity/vehicle handling or weather
sensor scales. Its Environment instance also sets nightGameplay=false so adding
visual night does not introduce new radar penalties. Existing approved gameplay
effects in other missions are retained. The leader periodically publishes its
actual rung; clients do not run independent automatic ladders. Procedural gusts
and dust-devil placement remain cosmetic client-side behavior, as in 04/05.

## Fog, sky and particle ownership

There is one renderer fog state, written by Environment after weather and local
modifiers have contributed. CRWeather writes directly only in its standalone
lane (currently Titan 14). Weather presets interpolate that same state; they do
not instantiate another global fog renderer. Final fogEnd never exceeds a known
TRN visibility limit, even when weather is Clear, at zero weight, during a
transition, or after a local override.

Environment creates no clouds, precipitation, skydomes or particle systems.
Native sky textures are backdrops, rather than a second procedural weather
system. None of the audited campaign callers supplies CRWeather's optional
baseSky descriptor, so its runtime sky-swap lane stays off. Moon, Venus, Io and
Europa mission TRNs contain no authored Clouds block. Mars 04/06 have eight
native clouds and Titan 14 has six; these are retained as their sky cloud layer.
The Plains weather particles are dust, and Titan's moving sheets are haze; no
additional cloud deck was introduced on those maps.

Venus's director owns its two counter-moving cloud layers; its presets supply
atmospheric haze/grit and its terrain systems provide local ground pools/vent
effects. Moon's basin pools and local ground mist remain intentional spatial
effects. These can still look too dense together and require visual judgment,
but they are distinct effects, not competing global atmosphere writers.

CRWeather keys particles by system name. A shared system is retargeted when a
preset changes, rather than allocated twice. Outgoing systems fade and are
destroyed when their layer retires. Rapid transitions/reversal/Clear are covered
by the integration regression. No new particle templates or cloud assets ship.

Weather.lua is an unused older implementation: no campaign or shared-module
require reaches it. It does not stack with CRWeather. It remains for compatibility;
CRStormFX is only used by the separate exhibition. Neither is newly activated.

## Validation and limits

Tools/Test-AtmosphereIntegration.lua executes the real Environment and CRWeather
against a mocked renderer: native baseline, RGB imports, bounded sun/light motion,
frame-rate independence/time rewind, full weather weight, cycle lock, manual fog,
100/130/250/700 horizons, standalone TRN limit, sensor opt-out and particle reuse.
The Moon complete-mission suites assert Environment wiring. Mission 06's host
suite covers story targets and save/load; its four-peer presentation suite drives
the real weather helper and transport, including rejection of guest authority.
Existing director and affected mission suites are retained. All changed runtime
Lua must compile under stock Lua 5.1; integration regression is wired into CI.
The integration regression also checks identical-time renderer reconstruction;
Moon mission suites explicitly check that saved director state is consumed on load.

This is platform-neutral Lua using existing EXU capabilities and existing flat
resource names. No native ABI, DLL, shader, terrain geometry or shipping membership
changes. Steam/Proton/Wine native rendering is not qualified by host mocks.
Three game processes were already active during implementation; no game was
launched, restarted or focused. Remaining visual review: shadow drift, Moon glow
strength, fog/terrain join at the cutoff, Venus lightning/bank brightness, and
mission-06 story pacing with the new weather. No new global cloud layer needs
qualification, but the existing native clouds plus moving dust/haze should be
reviewed together in those scenes.
