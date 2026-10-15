# Atmosphere ownership: Environment, CRWeather, and the terrain horizon

Three concerns, kept separate on purpose. They were drifting together — two
independent definitions of a dust storm, and weather fog that could outrun the
terrain — and this records where the lines are so they stay put.

```text
.trn
 └── authored FogEnd / VisibilityRange
       │
       └── Environment captures FogHorizon once, before anything mutates fog
              │
              ├── Environment.lua
              │    └── time of day and base atmosphere
              │
              └── CRWeather.lua
                   ├── weather particles
                   ├── weather lighting modifiers
                   └── weather fog, clamped to FogHorizon
```

## Environment.lua owns the base atmosphere

Time of day and everything that follows from it: `DayFog`, `SunriseFog`,
`SunsetFog`, `NightFog`, ambient, diffuse, specular, sun direction, the world
preset and palette. It is the single writer of renderer atmosphere state per
frame.

It does **not** own any weather phenomenon.

## CRWeather.lua owns every weather phenomenon

Dust storms, haze, rain, snow, mist, spore, ash, wind-driven particles, severe
variants, transitions between them, lightning, and the fog that belongs to a
weather state.

It does not write renderer state directly when Environment is present. It
registers through `Environment.RegisterEnvironmentModifier("CRWeather", fn)` and
mutates the frame Environment is about to apply. `CRWeather.OwnsEnvironment`
goes true only when there is no Environment.lua to contribute to, which is the
standalone path for missions that do not load it.

## The terrain horizon is shared metadata, owned by neither

`Environment.GetFogHorizon()` returns the distance past which the terrain
renderer stops drawing, read from the map's `.trn` (`VisibilityRange`, falling
back to `FogEnd`) during `Environment.Init` — before either system has touched
fog, so it is the authored value rather than whatever the current time of day
has produced.

It is not an atmosphere setting. It describes where geometry stops, which is a
property of the terrain, and both systems are consumers of it.

### The rule

```text
baseFogEnd = min(requestedBaseFogEnd, authoredTerrainHorizon)
weatherFogEnd = min(requestedWeatherFogEnd, authoredTerrainHorizon)
finalFogEnd = min(composedFogEnd, authoredTerrainHorizon)
```

The preset is capped before its blend and Environment caps the final composed
frame after all modifiers and manual transitions. Base keyframes are capped too.
At zero weight weather contributes nothing; the capped base remains. An overlong
base/final ramp scales into the horizon, so its start stays below its end.
This broad cap is the owner's explicit 2026-10-15 revision of the earlier
weather-only policy. See `ATMOSPHERE_AUDIT_20261015.md`.

### Why the rule exists

Stock `.trn` files set `VisibilityRange`, `FlatRange` and `FogEnd` to the same
number — misn04 is `250/250/250` — precisely so fog finishes where geometry
does. The weather presets are authored for more open ground: `MarsHaze` finishes
at 520, `MarsDustRising` 380, `MarsDustStorm` 320. On a 250-unit map none of
those reaches full density before the terrain is cut off, and the unfogged
remainder reads as a bright band along the horizon.

Measured on misn04, at the cut-off distance:

| preset | authored | density at 250 | clamped | density after |
| --- | --- | --- | --- | --- |
| `MarsHaze` | 90→520 | 37% | 90→250 | 100% |
| `MarsDustRising` | 45→380 | 61% | 45→250 | 100% |
| `MarsDustStorm` | 30→320 | 76% | 30→250 | 100% |
| `MarsDustStormSevere` | 12→130 | 100% | untouched | 100% |

The clamp costs density: fog is thicker at mid range than the preset asks for.
That is the honest price of a map that stops at 250, and no view distance is
actually lost, because there is nothing past 250 to see.

`CRWeather.Init{ fogHorizon = false }` disables its weather-request and standalone
cap; a number overrides those caps. Environment still enforces the TRN limit on
its final frame.

### Base fog is capped as well

Environment previously left its own long daytime fog outside the horizon.
That exception is retired: Clear, zero weather weight, time-of-day changes,
manual fog and local modifiers all obey the final visibility limit. Moon 02b/03
explicitly retain their native 175–250 fog while using subtle lighting mode.
Standalone CRWeather also caps its composed frame and reads TRN VisibilityRange
before falling back to captured fog end (these differ on Titan 14).

## Dust storms: one definition

`Environment.DustStormFog` and the per-frame override that applied it are
retired. They were a second definition of a dust storm, with their own fog and
their own gravity wobble competing with `CRMarsWeather`'s wind push — which
still carries a guard written against exactly that collision.

The legacy entry points stay recognised so missions that already call them keep
working:

| legacy call | now does |
| --- | --- |
| `Environment.TriggerDustStorm(duration)` | `CRWeather.SetPreset("MarsDustStorm")`, and warns if CRWeather is absent |
| `Environment.SetFogState("dust")` | resolves to base day fog; CRWeather supplies the storm on top |

`duration` is accepted and ignored. A storm that expires on a wall-clock timer
was never reconcilable with a severity ladder that raises and lowers over a
mission; stand one down with `CRWeather.SetPreset("Clear")`.

New code should not call either. Use `CRWeather.SetPreset`, or drive the ladder
in `CRMarsWeather`.

## Tests

`Tools/Test-CRWeatherFogHorizon.lua` covers the clamp and, just as importantly,
the regression running the other way: that base Environment fog survives
untouched with no weather active and at zero weight. Verified to fail when the
clamp is disabled, so it is not passing vacuously.

`Tools/Test-AtmosphereIntegration.lua` additionally executes the real Environment
and CRWeather together, including the final cap, subtle TOD and single-writer
contract. The weather suites had originally not been wired into CI. They are now, in
`campaign-validation.yml` — a weather regression could previously reach a
release with CI green.

## Still outstanding

`Scripts/Weather.lua` is a 973-line predecessor of CRWeather with no requirer
anywhere in the repository. It is a third dust-storm definition
(`BuildDustStormPreset`) that nothing can reach. Left in place here because
deleting it is not this change's business, but it should go.

## Per-craft sensor scrambles

The gameplay modifiers (`RegisterGameplayModifier`) are global: one set of radar and
jamming scales for every craft. A brief, local upset -- a Venus lightning strike scrambling
the radar of the units beside it -- needs a scale for one craft that lapses by itself.

`Environment.SetObjectScramble(h, seconds, { radarRange, radarPeriod, velocJam })` is that.
It is multiplied into the same scales `ProcessObjectNightEffects` already applies, so
Environment stays the only sensor writer: an outside `exu.SetRadarRange` would be
overwritten by the next sync pass and, worse, captured as the craft's "original" value.
The entry expires on its own (`Environment.Update` notices and rewrites the craft), a
second call never shortens an existing one, and replicas are skipped by the existing
`IsLocal` guard. See `VENUS_WEATHER.md`.


## Per-planet directors

The planet directors (`CRMarsWeather`, `CRVenusWeather`, `CRIoWeather`, `CREuropaWeather`) all sit on top
of this split: they pick a CRWeather preset and register an Environment modifier, and never write renderer state.
`CREuropaWeather` additionally touches no sensor, gameplay modifier or perception state at all (see
`EUROPA_WEATHER.md`), which makes it safe for stealth missions.

`CRTitanWeather` (`TITAN_WEATHER.md`) registers no Environment modifier at all: it only chooses CRWeather
presets and draws particles, so it runs the same on CRWeather's standalone path (misn14 does not load
Environment). Environment has a `titan` world preset of its own (detected from `TITAN.ACT`, the `ti_` atlas
or the `titan` sky) that holds the cycle at day through `Environment.LockDaylight`; any mission may set that
field, and `TitanAllowNight = true` before `Init` keeps the cycle on a Titan map.

## Subtle Moon and Venus lighting (2026-10-15)

Moon 02b/03 and Venus 07–09 call `Environment.Init` with `lightingMode="subtle"`
and `nativeBaseline=true`. This captures the authored light, sun and fog before
scripts modify them. A one-hour bounded lighting variation replaces the full
night cycle in those missions: at most 6% dimming / 4-degree azimuth excursion
on Moon and 4% / 2 degrees on Venus, with a small smooth elevation drift.
Subtle light modulation runs after weather, so full weather weight cannot erase
it. It does not add fog, clouds or night sensor penalties. Moon glow now lends
its small existing ambient contribution through Environment.

Other cycle-mode missions pass a day/night light scale to CRWeather so its
absolute daylight ambient/diffuse targets cannot relight the night. Manual fog
transitions start from unmodified base fog, not last frame's composed weather.
Mission 06 uses the Plains director and the full visual cycle, with both weather
sensor/wind effects and Environment night gameplay disabled. Full coverage,
remaining visual checks and inactive legacy modules are recorded in the audit.
