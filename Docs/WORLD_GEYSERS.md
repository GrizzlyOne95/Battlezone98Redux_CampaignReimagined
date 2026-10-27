# Per-world scrap geyser effects

`Scripts/CRGeysers.lua` draws a cosmetic effect on the free stock scrap geysers of
each campaign world and removes it while a building is deployed on the geyser. It is
visual only: no damage, no physics, no sim object, no network traffic, no random
numbers.

## What a geyser is

- ODF `eggeizr1` (stock; the spelling is the game's), class label `geyser`
  (`GeizerClass`, a `BuildingClass` descendant), so `IsBuilding` is true. The mesh sits
  below ground. BZN labels look like `eggeizr19_geyser`, `geyser3`, `center_geyser`.
- Recycler, Factory and Armory (and the Construction Rig) deploy onto one. Nothing in
  the Lua API says "taken".
- `aiCore.IsGeyserObject` / `IsGeyserOpen` are the AI's version of the same test.

## Occupancy

A geyser is occupied when a live object within `OccupyRadius` (11 m, the reach
`aiCore.IsGeyserOpen` uses) is

- a craft that reports `IsDeployed`, or
- a non-craft of class `recycler`, `factory`, `armory` or `constructionrig`.

Scrap, powerups, nav pods (`camerapod`), `i76sign`, other geysers and the co-op
`crping` marker never count; a Recycler still driving over the pad does not count
until it deploys. Reads are cached for one second per geyser (`OccupancyTtl`) and
made only for geysers near the local player, so there is no per-frame scan.
A destroyed or undeployed building frees the geyser at the next pass (about a second).

## Lifecycle: no per-mission edits

`CRWeather.Init / Update / Shutdown / ResetSystems / OnObjectCreated` call into
`CRGeysers` (`GeyserHook` in `CRWeather.lua`). Every weather-enabled mission therefore
gets it. A fault in `CRGeysers` is printed once and latched off; weather carries on.
The world comes from `CRWeather.ArtWorld` (the terrain atlas prefix).

- Geysers are found by `AllObjects()` at Init and every 20 s, and at once by
  `OnObjectCreated` (misn17 builds geysers when towers fall).
- Streaming copies the weather modules: nearest free geysers within `StreamIn`
  (900 m) up to `MaxLive` (8), dropped past `StreamOut` (1100 m); a clearly nearer
  geyser replaces the farthest one drawn.
- Quality (`CRWeather.Quality`): live count is `MaxLive x min(q, 1)`, emission and
  quota scale with `q`; 0 draws nothing. `MaxSystems` (24) is a hard ceiling.
- Every peer draws its own copy. The spurt rhythm of a geyser (period and phase) is a
  hash of its map position, so peers agree without messages.

## Looks

| World (missions) | Look |
| --- | --- |
| achilles (17, 18) | dirt and dust: grey-brown column, brown dust skirt, thrown dark clods |
| mars (4, 5, 6) | rust dust: red-brown column and skirt, thrown rust grit |
| titan (14, 15, 16) | tan haze: a slow orange-tan billow in dense air, nothing thrown far |
| moon (2b, 3) | ballistic grit on long low arcs, a faint grey dust skirt (no air) |
| europa (12, 13) | `CREuropaWeather` already draws vapour plumes; gated by occupancy |
| io (10, 11) | `CRIoWeather` already draws smoke and eruptions; gated by occupancy |
| venus (7, 8, 9) | `CRVenusWeather` draws sulphur plumes; **not yet gated** (see below) |
| ganymede, elysium | no campaign mission; stock |

Europa and Io: `StreamSites` in each director takes a `blocked(site)` predicate
(`VentOccupied` -> `CRGeysers.IsOccupiedAt`). An occupied vent is not streamed in,
a live one is torn down, and `BeginPlume` / `BeginEruption` return false for it, so the
host announces nothing for it and guests stay consistent.

**Venus** is the same two-line change in `CRVenusWeather.lua`, deliberately left
out here because that file belongs to the open Venus sky stack (PRs #330-#337). After
it merges: copy `VentOccupied` and the `blocked` argument from `CREuropaWeather.lua`.

## Art

`Materials/cr_geyser.particle.payload` has three neutral templates, `CR/Geyser/Plume`,
`Dust` and `Grit` (emitter 0 = steady jet, emitter 1 = spurt). `CRGeysers.Looks`
re-tints and re-shapes them per world at run time. They use the `CR18/Puff`, `CR18/Dust`
and `CR18/Chunk` materials from `cr18_storm.material`, which inherit
`CRWX_FX/ParticleAlphaBlend` (RGBA order kept). Do not switch to `CR_FX/*`: those
go through the BGRA sprite swizzle and draw red and blue swapped on DX11.

## Unverified

Host tests only (`Tools/Test-CRGeysers.lua`, plus occupancy scenarios in
`Test-CREuropaWeather.lua` and `Test-CRIoWeather.lua`). Not yet seen in game:

- the look values (sizes, speeds, colours, rates) are first guesses and need a tuning pass;
- that the `CR18/*` materials resolve outside mission 18;
- the 11 m occupancy reach against a real deployed Recycler, and whether the engine
  reports a deployed Recycler as a craft or a building (both are handled);
- `lcbench` smoke for the new payload (templates load, setters take, `BZOgreLogfile.log` clean).
