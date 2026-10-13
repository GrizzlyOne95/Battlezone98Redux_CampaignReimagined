# Mission 10 offline and co-op

The Race is On shares `misn10.bzn` / `misn10.lua` between the campaign mission (`crcampgn.ini`
MISSION9, Io, epilogue `misn1007.wav`) and the strategy listing `CR: The Race is On Coop`. Use
matching CR, EXU and OpenShim builds. Host on team 1, guests on distinct teams 2-4; select an NSDF
tank or scout and start together. Late join/rejoin requires a restart. Host departure ends the
mission. There is no intro cutscene (the original has none).

## Map

`Tools/Build-CoopMap.py --mission misn10` rebuilt `Missions/misn10.bzn` from the Battlezone 1.5
original: class `MultSTMission`, the eight authored CCA objects (`svrecy`, `svmuf`, two `sbbarr`,
`svcnst`, `sbsilo`, two `svartl`) moved from team 2 to team 5, four zero-motion `pspwn_1` team
starts (`coop_spawn1`-`4`), no authored object on teams 2-4, the `[AiMission]` block kept. Utah
(`avrecycler`) and the nav beacons stay team 1. The relic (`hvsrb`, label `relic`) is authored on
**team 0** (neutral), so no human team owns it; a tug carries cargo of any team. The terrain
companions are Redux's own; the stock trn has no lightning section, so it is unchanged.

## Ownership and rules

Only the campaign leader runs AI, spawns, orders, timers and the win/loss gates. Objectives,
markers, dialogue, removals and results reach every peer through the ordered, acknowledged E/A
stream (label-aware markers, bounded guest waits: the #186 pattern). `SetAIControl(5, true)` is a
single chunk-root call (Start runs after the engine's AI init and would crash the host);
`SetAIP(..., 5)` lives in Update. The base is host-only: team-1 `SetScrap(1, 30)` / `SetPilot(1, 10)`
stay leader-only and respawns rally at Utah while it lives.

| DLL | Co-op |
|---|---|
| CCA team 2 | team 5 (scrap/pilots/AIPs/spawns) |
| Player within 100 m of the relic shows its marker | any player |
| Artillery shells the player within 200 m of geyser 1 | the player nearest that geyser |
| Relic secured when the tug is team 1 | when the tug is not CCA (any human team) |
| CCA chases the team-1 tug | chases any human team's tug |
| `AddObject` with no team test | CCA ODFs must be team 5; hunters never take a slot |

## The map artillery is `ccaartil1`/`ccaartil2`

The DLL never builds an `svartl`: the only two are the map's `svartil1`/`svartil2`, and the engine's
post-Setup `AddObject` pass claims them as the first two artillery slots. Start recovers that pass
(`AllObjects`), so they get the `artil1_path`/`artil2_path` posting orders and, as both slots and
`svartil` names, the chase `Attack` is issued to each twice with identical arguments. That is the
DLL's own behavior (kept, not "fixed"); the repeat order is idempotent.

## Restored and scaled (marked `-- CR ...` regions)

* **CCA scaling.** Each extra human (cap 4 players) gives the CCA +10 starting scrap and one
  relic-carrier hunter (`svfigh`, base-defending until a human team's tug has the relic, then
  ordered onto it with the rest of the chase).
* **Tug rebuild.** After a CCA tug dies, a replacement `svhaul` is built at the CCA recycler 30 s
  later, at most twice, only while the relic exists, and not if the AIP already replaced it.
* **Plan B.** With the tug and both tanks alive the CCA is restocked (40 + scaling) and loads
  `misn10b.aip` once. The AIP builds from the CCA recycler/factory; it does nothing if they are dead.
* **Pickup quake.** The first relic pickup by anyone calls `CRIoWeather.Quake(0.85, 6)`; the
  director performs the engine shake and replicates it. The mission never calls the stock quake
  natives itself.
* **Skipped:** the abstor temporary relic; `misn1007` is the campaign epilogue, not an in-mission line.

## Io weather

`CRIoWeather` with `CRIoSites10` (see `IO_WEATHER.md`): every peer inits and updates it, the leader
decides, and `IoState` / `IoErupt` / `IoQuake` ride the ordered stream like misn09's Venus ops.
Beats (leader only, each once): calm at the start; level 2 when the CCA tug exists; level 3 when it
comes within 400 m of the relic or anyone first picks the relic up; a 60 s level-5 burst when the
carrier is within 500 m of its destination; calm on the win.

## Focused checks

```sh
lua5.1 Tools/Test-Misn10.lua
lua5.1 Tools/Test-Misn10Coop.lua
lua5.1 Tools/Test-Misn10Presentation.lua
lua5.1 Tools/Test-CRIoWeather.lua Scripts
python Tools/Test-Misn10SourceParity.py
python Tools/Test-Misn10CoopContract.py
python Tools/Test-CoopAuthoredLabels.py
python Tools/Test-SetupMissionShell.py
python Tools/Validate-CampaignRepository.py
```

## Not yet verified

No live run (two- and four-client co-op, campaign progression). Specifically unproven:
`SetAIControl(5, true)` plus `misn10*.aip` actually running for team 5 under `MultSTMission`;
whether the AIPs find a CCA factory to build from (they use the authored recycler and `svmuf`);
that a neutral (team 0) relic is picked up by both a CCA and a player tug and `GetTug` reports a
guest's tug; `CountUnits`-style calls are not used, but `AddObject` for the authored `svartl`/`svmuf`
after Start (the recovery loop) is untested live; the `planet = "io"` campaign key; the
quake feel and Io sky live; hunter behaviour and difficulty at four players.
