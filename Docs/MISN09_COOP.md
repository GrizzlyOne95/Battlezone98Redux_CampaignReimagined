# Mission 09 offline and co-op

Wrangling the Fleeing Herd shares `misn09.bzn` / `misn09.lua` between the campaign
mission (`crcampgn.ini`) and the strategy listing `CR: Wrangling the Fleeing Herd Coop`.
Use matching CR, EXU and OpenShim builds. Host on team 1, with guests on distinct teams 2-4;
select an NSDF tank or scout and start together. Late join/rejoin requires a restart. Host
departure ends the mission.

## Map

`Tools/Build-CoopMap.py --mission misn09` rebuilt `Missions/misn09.bzn` from the Battlezone 1.5
original (class `Misn09Mission`) as for misn06-08: class `MultSTMission`, the 13 authored CCA
objects (six `svartl` artillery, two `sbtowe`, two `sblpow`, the `sblpad` launch pad, `svrecy`
and `svmuf`) moved from team 2 to team 5 (`perceivedTeam 5`), four zero-motion `pspwn_1` team
starts (`coop_spawn1`-`4`) a short step apart at the authored start, no authored object on
teams 2-4. `misn09.trn` has the stock lightning removed (the Venus director replaces it, see
below).

## Mission ownership

The Unit Factory (`avmuf`), the rig, the three scavengers, the Self-Loader and Nav 1 stay on
team 1 (the host). The DLL's CCA is team 2, which is a guest slot: every runtime CCA spawn (the convoy
tug and ten escorts, the replacement tug, the extra escort) is team 5, and `SetAIControl(5, true)`,
`SetAIP("misn09*.aip", 5)`, `SetScrap(5, 40)` and `SetPilot(5, 40)` target it. The AIPs are
the stock files from `bzone.zfs` and name no team. Prescott's platoon is the support team (7),
allied with every human and hostile to the CCA, perceived as NSDF. The Alien Relic
(`obdata`), which the DLL builds on team 3 (a guest slot), is built on **team 0**: neutral
keeps it off every human team and off the CCA's target lists, and a tug carries cargo of any
team (`GetTug` and the seized/secured test read the *tug's* team, not the relic's).

Only the campaign leader runs AI, spawns, orders, timers and the win/loss gates; the co-op
preamble returns for guests before the mission body. Objectives, markers, dialogue, camera
shots, removals and results go to every peer through the ordered, acknowledged E/A event
stream, and the opening shot, the artillery shot and the convoy shot are the usual C
camera snapshots. Map-object markers and camera targets travel by map label (`key_scrap`,
`artil6`, `cam1`); a runtime object such as the tug or the relic gets a `crco_N` label
that the leader announces first, and each guest's wait for a late replica is bounded on its
own clock (the #186 pattern; the adapter is a self-contained block shared with misn08 so a
newer version drops in). Skipping a film is local to the player who skipped it.

**Shared base.** Only the host manages building. `SetScrap(1, 20)` and `SetPilot(1, 7)`
(the Unit Factory's report) stay as the DLL wrote them, on team 1, and run on the leader
only; no guest gets scrap or pilots, and the "scavengers dead and scrap < 10" loss reads team 1.
Guests have no factory to spend them with. The Unit Factory is the **respawn rally point**
(`rallyPoints = { [0] = "avmuf" }`) while it lives; when it dies (which fails the mission) the rally
point is dropped and respawns fall back to the native MultST team start (the player start buoys
are consumed by MultST during initialization). Exhausting the five-life respawn service
(`COOP_RESPAWN.md`) fails everyone.

## Co-op rule table

| DLL test | Co-op rule |
|---|---|
| Player within 70 m of `avmuf` releases the units, plays 0905 | any player |
| 0914 base warning: player within 100 m of Nav 1 or 400 m of the first two CCA fighters | any player |
| Convoy spawns once the player is more than 500 m from `convoy_geyser` | no player within 500 m (the DLL's eleven-second retry) |
| Charon found (< 70 m) | any player |
| `IsInfo("hbchar")` | selection is local UI state: guests relay the prefix (`I`) and the leader honours a report for 1 s |
| Tug team 1 secures the relic | any tug not on the CCA team secures it, so a guest's tug counts |
| `AddObject` (no team filter) | marked filter: `svturr`/`svfigh`/`svtank`/`svscav`/`svhaul` must be team 5; the player's `avwalk`/`absilo` any human team |
| `CountUnitsNearObject(..., team 2, ...)` | team 5 |
| Back-to-back `AudioMessage` | not present in the DLL flow; the first line of a block plays through the shared `Play` |
| Factory (`avmuf`) lost, launch pad destroyed, relic lost, tug at the pad | the DLL fails everyone, as before |

## Restored and changed behavior

All of it sits between `-- CR ... >>` / `<<` marker lines; the source parity test strips them
and proves the DLL body is otherwise unchanged. The remaining co-op substitutions are the
five `Distance(user, x)` tests that became `AnyPlayerWithin` and the one that became
`NoPlayerWithin` (listed as API-count deltas), the team constants, `GetTeamNum(M.tugger)
~= ENEMY_TEAM`, and the `AudioMessage` / camera / objective calls that resolve to the
presentation adapter's lexical wrappers, so the DLL body keeps its own spelling.

* **Convoy scaling** (`CR convoy scaling`). The DLL's convoy (four `svfigh`, four `svtank`,
  two `svapc` and the tug) is sized for one player. Each extra human team adds one `svtank`
  and one `svfigh` (spawned on the same spawn paths, ordered to `Defend`, then `Follow` the tug
  like the rest), capped at +3 (four players). Humans are counted as misn07/misn08 do
  (`ForEachHumanTeam`): 1 player is the DLL's convoy exactly.
* **Prescott's platoon** (`CR Prescott platoon`). The VO has Commander Prescott flush the
  convoy out (0901) and seal its retreat (0903). Once the convoy has started and its lead (the
  tug, else the first living escort) comes within **350 m** of `cut_off_geyser` (the soviet path
  passes 125 m from it), the players get a **45 s** head start. Then the leader spawns an allied
  `avtank` platoon on team 7 **`PRESCOTT_BEHIND_M` = 250 m behind the convoy's rearmost living
  unit** (the one farthest from the cutoff geyser; any tug, escort, APC or extra counts): the
  `soviet_path` points are walked backwards from the point nearest that unit, spread 20 m
  sideways, `y` from the terrain. If the path cannot be read it uses the rear unit's position
  minus its facing times 250 m, and if no convoy unit is alive nothing spawns (and no arrival
  burst). It used to spawn on `spawn1`-`4`, the convoy's origin 1.17 km back, which could be
  after the convoy had already passed the cutoff. It is perceived as NSDF, on orders only (`SetIndependence 0`). It is **3** tanks, +1 per
  extra human, max **5** (3/4/5/5 for 1-4 players). Every 4 s each tank is ordered to attack
  the nearest living convoy *combat* unit (the four fighters, four tanks and the scaling
  extras) and is re-ordered only when its target changes or dies. The tug (which may carry
  the relic), the APCs and the launch pad are never named in an order, so the platoon cannot
  deliberately fire at them; once no combat unit is left each tank stops and holds. Leader
  only; the handles live in the saved state. 0903 stays at the DLL's time (seven seconds
  after the convoy starts, tied to the convoy shot); the platoon usually spawns well after
  it, which the line ("is sealing their retreat path") tolerates, so the VO timing is stock.
* **Restored radio** (`CR cut VO`). `misn0917` (Collins: "why are you wasting time and
  resources building units now?") plays once when a human combat unit (`avtank`, `avltnk`,
  `avrckt`, `avhraz`, `avartl`, `avfigh`, `avwalk`) appears within 120 m of the Unit Factory
  before the six artillery are dead. `misn0910` (Sasquatch: too slow to reach the cutoff
  position) plays once when a walker (`avwalk`) is built more than **600 m** from
  `cut_off_geyser`; the factory starts 1.28 km from it, so a walker built at the start
  position qualifies, and one built after moving the factory up to Nav 1 does not.
  `avwalk` is buildable from `avmuf` (`buildItem9`; the briefing calls it the new Walker
  technology). When both are due they play one after the other, Collins first. `misn0912` is a
  duplicate briefing and stays cut. The wavs are in `Assets/Audio` (byte-exact from the Redux
  `bzone_en.zfs`; the 1.5 `stockfiles2` copies are identical) and the subtitles are in `Text/`;
  see "Shipped voice lines" in `MISN07_COOP.md` for the method.
* **Geyser-clear win** (`CR geyser-clear win`). The DLL plays 0908 ("Venus is secure") when
  `CountUnitsNearObject(convoy_geyser, 5000, team 2)` is zero, with its `SucceedMission`
  commented out. It is enabled: with the convoy started, clearing every CCA (team 5) unit
  within 5 km of the geyser wins with `misn09w1.des`. The check runs every 10 s and does not fire
  once an outcome is set, so the relic win (0909) and the failures keep their DLL precedence.
* **Replacement tug** (`CR tug rebuild`). The DLL's cut block rebuilt the tug at the CCA
  recycler. Restored with the dead `build_new_tug` / `build_tug_time` / `tug_done` state: if the
  CCA tug dies after the convoy started while the relic exists, the CCA factory (`svmuf`) builds
  a replacement `svhaul` (team 5) 90 s later, at most **2** times, only while `svmuf` lives (if it dies during the
  wait, the rebuild is cancelled). The existing tug logic (`Pickup`, then `Dropoff` on
  `soviet_path`) resumes the seizure, and the surviving escort is told to `Follow` the new
  tug once it holds the relic again. Leader only.
* **Team filter** (`CR team filter`). See the table. `AddObject` keeps the DLL's
  first-empty-slot order and ODF-only matching; the filter only decides which objects reach it.
* **Venus weather** (`CR Venus weather`). See below.

## Venus weather

`Scripts/CRVenusWeather.lua` (see `VENUS_WEATHER.md`) gives the mission its sulphurous
overcast, altitude-pooled fog, lightning storms, sulfur pools, geyser plumes and acid rain;
`Missions/misn09.trn` no longer carries the stock `[LightningBolt]` section. misn09 uses the
same wiring as misn07/08: `InitVenusWeather` on every peer with `CRVenusSites09` (generated by
`Tools/Build-VenusSites.py misn09 --types 1`: 179 Liquid Sulphur cells in one pool, six
geysers - four unnamed plus `cut_off_geyser` and `convoy_geyser` - and the playable box from
`edge_path`; the stock map has no Lightning Power generators and no `volcano*` vents),
authority = offline or the leader, the three Venus ops riding the ordered presentation
stream, `Update` on every peer, `AnnounceState` once when the session is ready, `AddObject`
forwarding and the director's state saved with the mission. The director keeps updating through the
result window so the win's calm is visible.

Beats (leader/offline only, each once; guests follow `VenusState`):

1. Opening and the artillery fight: calm, target level 2.
2. Level 3 when the convoy launches (the CCA tug has the relic) or the cutoff warning (0903)
   fires.
3. `ForceLevel(5, 60, 10)` when Prescott's platoon arrives or the tug makes its final run
   (within 500 m of the launch pad).
4. Target level 1 (clear) on the win.

The director never damages anything, so the fight is unaffected beyond knockback and brief
radar scrambles near strikes.

## Focused checks

```sh
lua5.1 Tools/Test-Misn09.lua
lua5.1 Tools/Test-Misn09Coop.lua
lua5.1 Tools/Test-Misn09Presentation.lua
lua5.1 Tools/Test-CRVenusWeather.lua Scripts
python Tools/Test-Misn09SourceParity.py
python Tools/Test-Misn09CoopContract.py
python Tools/Test-ShippedCutVo.py
python Tools/Test-SetupMissionShell.py
python Tools/Validate-CampaignRepository.py
```

`Test-Misn09.lua` (126) is the offline host flow over the real CRCoop with one player:
the DLL's own timers, strict boundaries, slot order and outcome precedence, plus the team-5
remaps, the neutral relic, the replacement tug's delay and the geyser-clear win.
`Test-Misn09Coop.lua` (1077) runs the whole script in four peers plus an offline peer
over the E/A/C transport: startup, ownership and rally, label-aware nav names and opening
shot, every any-player trigger at its strict boundary, the IsInfo relay, the convoy at
1-4 players (extras and their orders), a guest-held relic, the platoon (trigger at 351 and 349
m, the 45 s delay, 3/4/5/5 tanks spawned 250 m behind the rear unit along the route (facing fallback, no spawn when the convoy is dead), orders that only name escort combat units,
tug, relic, APC and pad untouched through a full fight, retargeting, holding when none are
left), both cut lines (and the cases that must not fire), the replacement tug (delay, team,
placement, limits, factory loss, relic loss), the geyser-clear win and the lock-step result on every
peer, the factory loss and rally, and the Venus wiring and beats. `Test-Misn09Presentation.lua`
(98) covers the adapter. The parity test pins `References/Misn09Source` and lists each
co-op substitution as an API-count delta.
These mocks do not qualify native wire serialization, AI navigation, weapon
damage or voice queuing.

## Not yet verified

No live run: Windows GOG two- and four-client co-op and the campaign progression.
Specifically unproven:

* `SetAIControl(5, true)` at startup enabling the CCA strategic AI the way the DLL's
  `AiMission` did for team 2, and whether `misn09.aip` / `misn09a.aip` / `misn09b.aip`
  actually execute for team 5 under `MultSTMission` (no evidence in this repository either way;
  the stock route is kept).
* Whether `SetIndependence(unit, 0)` stops Prescott's tanks from opening fire on their own at
  something near them (the tug carrying the relic, the launch pad); the script only guarantees
  that no *order* names those. If the live platoon shoots the tug the exclusion needs a
  geometric guard (hold fire inside a radius), not a different target list.
* Whether `CountUnitsNearObject` counts buildings: if it does, the CCA launch pad and base
  keep the geyser-clear win from ever firing, and the DLL's cut block would have had the same
  problem. The mock counts units only.
* Whether a neutral (team 0) relic is picked up by both the CCA and a player tug exactly as the
  team-3 one was, and whether a tug's `GetTug` reports a guest's tug.
* The platoon's travel time from the convoy's origin to the fight (about 1.2 km at tank speed)
  against the 45 s delay, the effect of the new escort on the fight, and that the mission is
  still winnable with four players and the extra fighters.
* Which of `avtank` / `avwalk` units built from the Unit Factory reach `AddObject` on the host in a live
  session (the cut radio keys on that callback).
* The `IsInfo` relay, label markers and film snapshots in a live four-client session, and the
  Venus sky, fog pooling, bolt look and storm pacing on this terrain (see `VENUS_WEATHER.md`).
  Steam and Wine/Proton are unverified.
