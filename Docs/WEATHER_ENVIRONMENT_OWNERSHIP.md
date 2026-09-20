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
weatherFogEnd = min(requestedWeatherFogEnd, authoredTerrainHorizon)
```

Applied to the preset's requested value **before** the blend, never to the
composed frame afterwards. At zero weight a weather layer therefore contributes
nothing at all, and a mission with weather disabled or standing clear keeps
exactly the base fog Environment asked for.

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

`Init{ fogHorizon = false }` opts out entirely; a number overrides.

### What is deliberately *not* clamped

Environment's own `DayFog` finishes at 700 on that same 250-unit map, so the
identical argument applies to it. It is left alone anyway.

Clamping it would change the established appearance of **every** mission that
loads Environment, weather or no weather. Whether 700 is architecturally wrong
is a fair question, but answering it is not required to fix the weather defect,
and it deserves its own change tested across maps with different `FogEnd` and
`VisibilityRange` values. Do not fold it into a weather commit.

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

The weather suites had never been wired into CI. They are now, in
`campaign-validation.yml` — a weather regression could previously reach a
release with CI green.

## Still outstanding

`Scripts/Weather.lua` is a 973-line predecessor of CRWeather with no requirer
anywhere in the repository. It is a third dust-storm definition
(`BuildDustStormPreset`) that nothing can reach. Left in place here because
deleting it is not this change's business, but it should go.
