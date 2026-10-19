# Total Command mission ideas for Campaign Reimagined

Status: idea list only. No code, assets, text or audio from Total Command (TC) are used or reproduced here.
Survey date: 2026-10-19. Branch: `agent/tc-mission-ideas`.

## 1. Scope, licence, confidence

- **Source studied.** TC's reimagined NSDF campaign ("Stars and Stripes", scripts `bztcss01`..`ss17`) and, as a secondary pass, its Black Dog campaign (`bztcbd01`..`bd10`), read from the BZCC Steam Workshop cache (read-only). Compared with CR's `misn01`..`misn18` (incl. `misn02b`) and `bd01`..`bd06`, `bdmisn07`..`bdmisn15`.
- **Licence.** Coxxon permits TC to be linked only as assets from BZCC config mods, with credit. This document therefore records *ideas and patterns in our own words*. Anything built from it must be written from scratch against BZR/EXU APIs, with CR's own ODFs, audio and text. TC's own text, audio, ODFs, models and scripts must not be copied, ported or "translated" line by line.
- **Credit.** Where an idea is clearly TC's, name it as an idea in release notes ("inspired by Total Command by Coxxon"), but do not describe it as shipped TC content.
- **Confidence.**
  - TC side: read from scripts and `.des` briefing files. TC's `tcss*.txt` "subtitle" files are only objective cards; spoken lines exist as wav names only, so there is no dialogue to compare. Speaker identities come from script comments.
  - CR side: scripts were grepped and skimmed, plus the per-mission docs. A "none found" means a search found nothing, not that it is proven absent. Premises for several BD missions are inferred from script logic.
  - API availability: checked against `Docs/BZR_LUA_AGENT_REFERENCE.md` ("REF") and `Docs/lua-definitions/ExtraUtils.lua` ("EXU-DEF"), plus a grep of `Scripts/`. **"Not documented" is not "does not exist in the engine"**: it means no ground truth exists in this repo, so a one-off native probe is needed before depending on it (see §3).

## 2. Mission pairing

TC's NSDF arc is a chapter-for-chapter reimagining of the same stock arc CR rewrites, so the pairing is one-to-one with an offset. `misn01` (flight training) has no TC counterpart.

| TC | Title (TC) | CR | World |
|---|---|---|---|
| ss01 | Red Arrival | misn02b | Moon |
| ss02 | Eagle's Nest 1 | misn03 | Moon |
| ss03 | The Relic Discovered | misn04 | Mars |
| ss04 | An Unexpected Connection | misn05 | Mars |
| ss05 | Escape from Mars | misn06 | Mars |
| ss06 | Behind Enemy Lines | misn07 | Venus |
| ss07 | A Nasty Surprise | misn08 | Venus |
| ss08 | Wrangling the Fleeing Herd | misn09 | Venus |
| ss09 | The Race is On | misn10 | Io |
| ss10 | Bring it Home | misn11 | Io |
| ss11 | Flying Solo | misn12 | Europa |
| ss12 | Total Destruction | misn13 | Europa |
| ss13 | The Three Beacons | misn14 | Titan |
| ss14 | United We Fight, United We Die | misn15 | Titan |
| ss15 | Strike at the Heart | misn16 | Titan |
| ss16 | Tapping the Core | misn17 | Achilles |
| ss17 | The Ultimate Quake | misn18 | Achilles |

## 3. API readiness (read this before any idea)

Result of checking every TC call that an idea below would need.

**Documented in REF (safe to plan on):** `SetPerceivedTeam`, camera family (`CameraReady/Path/Object/Finish/Cancelled`), `AddObjective/UpdateObjective/ClearObjectives`, `SetObjectiveOn/Off/SetObjectiveName`, `AudioMessage/IsAudioMessageDone`, `StartCockpitTimer*`, `Goto/Attack/Follow/Retreat/Defend2/Patrol/Mine/Pickup/Dropoff/Stop/Formation/Hunt`, `SetCommand` + AiCommand names (incl. build and dropoff), `GetTug/HasCargo`, `IsInfo`, `SetTeamNum`, `Ally/UnAlly`, `SetTeamColor`, `GiveWeapon`, `SetCurAmmo`, `SetVelocity`, `BuildObjectAtPortal`, `Damage/SetCurHealth/SetMaxHealth/AddHealth`, `GetODFInt/GetODFString`, `IsInsideArea`, `GetPositionNear`, `GetNearestEnemy`, `KillPilot/EjectPilot/RemovePilot`, scrap/pilot setters, `ColorFade(...)`, `StartEarthquake/UpdateEarthQuake/StopEarthquake` (note the mixed-case spelling), `MakeExplosion`, `Hide/UnHide`. Difficulty is not a stock call: CR reads `exu.GetDifficulty()` (EXU-DEF:1284) via `DiffUtils`.

**Not documented in REF or EXU-DEF and not called by any CR script (zero hits):** `SetCanSnipe`, `IFace_*` (`IFace_GetInteger/SetInteger/ConsoleCmd`, used by TC for difficulty, FOV, music volume and sky colours), `SetControls`, `SetAnimation`, `StartEmitter/StopEmitter/MaskEmitter`, `StartSoundEffect`, `SetColorFade` (CR's equivalent is `ColorFade`), `SetSkill`, `SetEjectRatio`, `SetAutoGroupUnits`, `PreloadODF`, `IsCraftButNotPerson`, `IsAround`, `HasPilot`, `LookAt`, `SetGroup`, `SetAsUser`, `GetPower/IsPowered`, `AddPilotByHandle`, `GetNetworkListItem`, `Service`, `TeamHQ`, `SetPlan`, `IsEnemy`, `LaunchObject`, `Apply/ForceReplace`. Several are BZCC additions or BZ2-lineage names. None of them should appear in a plan until a probe proves it in Redux.

**Equivalents CR already has** for the capabilities those missing calls provide:

| TC capability (BZCC call) | CR route |
|---|---|
| Freeze the player during a dropship cold open (`SetControls`) | `exu.SetPlayerControlMask/ClearPlayerControlMask` as used in `CR04Drop.lua` (used but undocumented in EXU-DEF; stands down in MP) |
| Dropship doors/takeoff animation (`SetAnimation`, emitters) | model swap `avdropc` → `avdropo` → `avdropx` as in `CR04Drop`/`CRDrop18`; EXU entity animation (`SetEntityAnimationEnabled/Loop/Time`, EXU-DEF:873-904) |
| Screen flash/fade (`SetColorFade`) | `ColorFade` (REF:1130) |
| Un-snipeable VIP (`SetCanSnipe(h,0)`) | none documented. Options: keep the VIP in a vehicle with no pilot-eject exposure, make it neutral to AI via team choice, or pin health; probe `SetEjectRatio`-like behaviour only if needed |
| Enemy skill (`SetSkill`) | `DiffUtils` scale tables, `aiCore` difficulty level, ODF variants; TC itself only uses skill as a flat pass-through, so little is lost |
| Difficulty read (`IFace_GetInteger`) | `exu.GetDifficulty()` (0..4; locked Very Hard in MP) |
| Music duck / sky colour drift (`IFace_ConsoleCmd`) | `exu.SetFog/SetAmbientLight/SetSunDiffuse/SetTimeOfDay` (EXU-DEF:273-486) for sky; **no documented music-volume control** (open question) |
| Subtitles | `ScriptSubtitles.lua` |
| Spawn-freeze "holder" objects, jammer objects | TC-specific ODF tricks; not needed if control mask + `Stop` suffice |
| Power checks (`GetPower`) | none; avoid |

**Co-op constraints on every idea** (from `AGENT_KNOWLEDGE_BASE.md` and REF): guest `BuildObject` stays local (use `exu.BuildSyncObject` from the owner); `MakeExplosion` is local-only; `SetObjectiveName`/marker changes are not auto-synced; `SetVelocity` does sync; camera shots go through CR's ordered C-channel; `Send` strings over 127 bytes crash peers (`CRWire`). Any idea marked "co-op: needs design" below must be routed through `CRMisnNN` events, not fire-and-forget locals. Mission scripts in misn06..18 and `bd*` have no difficulty scaling at all today, and `bd*` have no co-op layer.

## 4. Executive summary: the ideas worth doing, ranked

Ranked by value to CR players against implementation risk. "New" means CR has nothing comparable.

| # | Idea (TC origin) | Where it fits | API need | Risk |
|---|---|---|---|---|
| 1 | **Live relic theft loop.** An enemy tug actively fetches an unguarded relic, shadows the friendly tug, and an assassin squad hunts the carrier (ss03, ss08, ss09) | misn04, misn09, misn10 | `Pickup/Dropoff/GetTug/HasCargo/Follow/Attack` (all REF) | Low; misn10 already has the chase |
| 2 | **Reusable wave director ("WARCODE")**: 3-4 lanes by target, staging point, 80%-casualty gate, cooldown growing, wave 5 loops to wave 2, abort timer, retarget chain (ss06..ss17, bd05, bd10) | New helper module for CR missions that currently have no or sparse waves (misn07-09, 13, 15, bdmisn07/12/14) | stock orders + `BuildObject` + `GetNearestEnemy` | Medium (balance, MP spawn rules) |
| 3 | **Daywrecker strike** with a difficulty-scaled warning reveal range (ss09, ss12, ss15) | misn10 act 2, misn13, misn16 | `SetCommand` build/dropoff by AiCommand *name*, ordnance catch via `AddObject`, `SetObjectiveOn` | Medium; ODF must exist; verify AI armory obeys |
| 4 | **Dropship extraction/cold open reuse**: `CRDrop18` for misn06 dust-off and misn14 evacuation; `CR04Drop` for a Venus/Io cold open (ss03, ss05, ss06, ss09, ss13) | misn06, 07, 10, 14 | existing `CRDrop18`, `CR04Drop` | Low-Med; SP-only today for CR04Drop |
| 5 | **Orders with teeth**: "go inspect X" with a warn line then a dated fail, plus per-cause fail debriefs (ss03-05, ss08) | misn04-06, 09 | timers, `IsInfo`, `FailMission` | Low |
| 6 | **Graceful cover-blown escalation** and ordered checkpoints with diegetic intel (scan-unlocked nav cams) instead of hard stealth fails (ss11) | misn12, misn07, bdmisn09 | `SetPerceivedTeam`, `IsInfo`, `GetNearestEnemy`, `IsInsideArea` | Low; CR already has half |
| 7 | **Counter-strike on breach**: punish a flank (two towers on one side die → rocket strike), warning zone then punishment, artillery-hunter squad that reacts to player artillery near the enemy recycler (ss04, ss06, ss14, ss15) | misn05, 13, 15, 16 | `GetNearestEnemy`, orders, `AllCraft` iteration | Low |
| 8 | **Optional discovery rewards**: scan a hidden object with the info key to flip it to the player (free artillery, power, bio-metal pool; consequence-free ruin as a bonus) (ss07, bd05, bd07) | misn08, 13, 16 | `IsInfo`, `SetTeamNum` | Low |
| 9 | **Hidden clock / surprise reveal**: real deadline hidden, a visible timer only when the player dawdles (ss05) | misn06 | cockpit timer family | Low |
| 10 | **Mid-mission "twist" act** that turns a won objective into a defence (ss09: relic secured, then the base is attacked) | misn10 | whole-mission design | Medium; changes pacing, owner decision |
| 11 | **Quota-banking economy** with milestone lines (ss14) | misn15 | `GetScrap/SetScrap` | Low |
| 12 | **Epilogue machinima** of the dying moon from orbit (ss17) | misn18 ending | camera + a prop; assets | Medium-High (assets; unskippable) |

Treat all ranks as proposals: CR's current policy for misn06-18 and `bd*` is source faithfulness, so every idea that changes gameplay should be an opt-in, a difficulty-gated option, or an explicit owner decision.

## 5. Cross-cutting patterns

These recur across TC missions; describing them once lets the per-mission sections stay short.

### 5.1 Script shape (not a thing to copy, but explains how TC works)
Each TC script is one table of state plus a linear integer "spine" stage counter, with independent timer blocks for AI, cameras and fail checks; timers use a far-future sentinel to mean "disarmed"; a one-shot "mission critical asset" block handles failure. A terminal stage number freezes everything after win/loss. Take-away for CR: the *separation of a linear story line from independent timer-driven systems* maps onto `MissionLifecycle` and the `CRMisnNN` runtime pattern; nothing to adopt.

### 5.2 Wave director ("WARCODE")
- **What it is.** Several parallel lanes, each aimed at a different target class (player recycler, factory, armory, "whatever base building is next" priority list, player as a last resort). Per lane: choose wave number and size → spawn at the enemy factory/recycler with scatter → send to one of two alternating staging points → wait until any unit reaches staging → attack the lane's target with a fallback chain → when about 80% are dead or captured, schedule the next wave after a cooldown (longer after wave 5, "ease up") → loop wave 5 back to wave 2, never replaying the gentlest wave.
- **Pacing knobs.** Lane starts are staggered about a minute apart, abort timers reset a lane stuck on terrain (6-7 minutes), sizes ramp 2→8 (ss12) to 4→12 (ss15), higher waves swap in upgraded weapons by wave number, every third unit gets +1 skill, spawns are suppressed when the player is within ~300-400 m, lanes stop when the enemy factory is gone.
- **Companion systems** TC pairs with it: capped-life turret slots, scout patrol slots, two scavengers whose scrap is clamped so they keep working but don't bank, an "artillery assassin" squad, a factory rebuild only when the player is far away.
- **CR fit.** CR missions that are source ports (misn06-09, 13, 15, bdmisn07/12/14) rely on stock AIPs or sparse hand-spawned waves; a small CR-owned director module could give optional pressure. `aiCore` exists, but docs note it is not loaded by misn10-18 and that scripted AI builds nothing without prerequisites/scope, so a director built on plain stock orders is the lower-risk route. Needs: `BuildObject`, orders, `GetNearestEnemy`, handle bookkeeping. Co-op: spawns must come from the host (`BuildSyncObject`), cap live units (CR already caps at 12-16), and follow the 400 m no-pop-in rule.
- **Hazard.** TC's own AI keeps the enemy alive with scrap clamps and "never bank" hacks; these are balance workarounds for a missing AIP. CR does not need to replicate them.

### 5.3 Daywrecker strike
Conditions: enemy has tech centre + armory and at least 80 scrap. The armory is ordered with the raw AiCommand build, then a dropoff at the chosen target (factory 4/12, recycler 3/12, service bay 3/12, player 2/12). The launched bomb is caught on creation, flipped to a trackable team once within 400/300/200 m (easy/medium/hard) so the player gets a window to shoot it down or flee, with an alert pulse; rearm after 5-9 minutes. API: `SetCommand` with AiCommand *names* (REF:447-480, 957), not TC's raw numeric ids, which are BZCC enum values and must not be assumed. Needs a CR ODF for the bomb and a probe that the AI armory honours the order. Co-op: bomb marker changes are not auto-synced (REF:747); route through an event.

### 5.4 Dropship cold open
Player starts inside a landing craft: input frozen, rising quake, doors, units walk out, ship leaves. CR already has this for misn04 (`CR04Drop`, SP only, uses the EXU control mask) and for misn18's extraction (`CRDrop18`, replicated, pure function of plan and clock). Idea is to extend reuse rather than invent: misn06 dust-off, misn14 scientist evacuation, a Venus or Io arrival. Constraint: `CR04Drop` is SP-only because the mask stands down in MP; any reuse must follow the `CRDrop18` replicated model.

### 5.5 Orders with teeth
Pattern: an order ("investigate X", "scan Y") starts a warning ladder, e.g. a reminder voice line at ~20-90 s, then a short fail timer, with tongue-in-cheek debrief copy. A distinct fail debrief per cause (TC has 4-7 per mission) turns failure into coaching. CR already has six loss debriefs in misn06; copy the *structure* to misn04/05/09. API: timers, `IsInfo`, `FailMission` with per-cause text.

### 5.6 Hidden countdown with a surprise (ss05)
The true deadline is started but not shown; a voice reminder cadence at fixed remaining times; if the player is slow and far from the objective, a set-piece (the friendly platoon's last stand) fires and a *visible* timer starts. Frustration cushion, tension preserved. Maps to misn06's 540/362/180 timers.

### 5.7 Cover and stealth ladder (ss11, bd03, bd04)
Ordered checkpoints (visiting out of order warns twice, third time blows cover), a boundary path that blows cover on crossing, scan-unlocked "intel camera" markers that show the next stop through terrain, a cover-blown state that changes the objective rather than ending the mission (patrols hunt, a hunter squad spawns, comm tower interception continues), and a punishment ladder (warn → 10 s grace → 3-unit hunters → reset after they die). CR's misn12 already has per-human stealth state, challenge timers and a death squad; the new parts are the diegetic intel markers, boundary paths and the "degrade, don't fail" rule.

### 5.8 Voice and objective sequencing
TC queues one voice line, then swaps the objective card only after it ends (`IsAudioMessageDone`), so cards never outrun speech. CR's `ScriptSubtitles.Queue` plus the CR presentation adapter already cover this; verify that the objective swap in each CR mission waits on the queue, not on a fixed delay.

### 5.9 Difficulty and pacing
TC difficulty is thin: skill pass-through on every enemy, +1 skill on every third wave unit, a few timer or count tables (free scavengers on higher difficulty in ss02, wave size and daywrecker warning range in ss15, relic delay 90/75/60 s in ss03), and extra friendly wingmen on higher difficulty in the Black Dog arc. Several intended tables never apply because of misspelled variables (ss01 respawn timers; ss04 strike size). Mission length grows ss01 (minutes) → ss14-17 (30-60 min). Anti-frustration measures worth keeping in mind: no spawns near the player, heal/pin player health during cutscenes, reinforcement narration, nag lines every ~10 minutes, deliberately thinning an enemy turret ring ("too difficult").
**CR fit:** misn06-18 and `bd*` have no difficulty scaling; `DiffUtils` is ready. The cheap, useful TC lessons are the *per-difficulty warning reveal range*, *relic/clock delays*, and *free-support gifts*, not skill pass-through.

## 6. Mission-by-mission

For each pair: what TC adds that CR lacks, pacing and difficulty notes, and fit with the API it needs.

### 6.1 ss01 Red Arrival ↔ misn02b
- **TC adds.** Economy tutorial built around a quota story (build a scavenger, escort it, collect) with an anti-cheese scrap wipe on first contact; HUD role names on enemies ("Unknown Contact", "Scav Killer", "Assassin"); a lone assassin that re-sends its attack order every ~10 s so it follows when the player swaps vehicle; a second scavenger rescue whose spawn point deliberately overlaps its path; four distinct loss debriefs.
- **Pacing/difficulty.** Very short, seven voice lines. Intended respawn tables (fighters 18/15/12 s, assassin 30/25/20 s) never apply because of the variable bug; only skill and the rescue start delay scale.
- **CR status.** Has a richer three-stage intro, scripted waves with `DiffUtils`, restored alternate VO, co-op, weather.
- **Fit.** Low. Worth borrowing: HUD role names on key enemies (`SetObjectiveName`, documented REF:735-747, not MP-synced) and a short "assassin that follows you between vehicles" patrol. No new API.

### 6.2 ss02 Eagle's Nest ↔ misn03
- **TC adds.** A recycler gift for defence with extra free scavengers on medium/hard; reinforcements arriving as a neutral column that flips to the player on proximity, with a 40 s fail timer; a raid on that recycler by a team-6 squad; a CCA arrival cutscene staged with props; transport escort where hunters target *each* transport and one transport may be lost but not two; a 60 s deadline to reach the pad; a "win by escaping, base lost" ending in which scripted tanks raze friendly buildings in order, with buildings pre-damaged for visuals.
- **Pacing.** Four phases (hold, meet allies, escort, escape). Wave count not difficulty-scaled.
- **CR status.** Waves, escort, CCA base film, demolition outro, difficulty via `DiffUtils`, thorough co-op doc. The demolition outro already covers the bittersweet ending.
- **Fit.** Medium. New to CR: the *meet-the-column with timer and team flip on proximity* beat, and the "tolerate one loss" rule for escorts. API: `SetTeamNum`, `IsWithin`, timers, `Hunt/Attack`. Co-op: proximity must consider every human (CR has `AllPlayersNear`).

### 6.3 ss03 The Relic Discovered ↔ misn04
- **TC adds.** Relic site chosen by which deploy position the player used (three variants); neutral relic that flips ally when found; relic guards respawning; **live theft race**: an enemy tug fetches the relic and carries it home, follows the friendly tug if it holds it, guards re-aim at the friendly tug; a tether rule that keeps the relic within 64 m of the recycler; a recon-order ladder (warn at 90 s, fail ~90 s later); a "don't attack the CCA base" proximity warning loop; six waves of 2/4/8/12/16/20 with a rear spawn on wave 4+; wave announcements vary; if the enemy recycler dies a parked enemy dropship appears for plausibility.
- **Pacing/difficulty.** The relic appears 90/75/60 s after wave 3 is cleared; tug and assassin respawn faster in harder relic placements. 38 voice lines.
- **CR status.** Single-player dropship landing, relic discovery film with four camera variants, theft *cinematic*, five scripted waves, co-op, weather escalation. The theft is scripted, not simulated.
- **Fit.** High for the live tug race (idea #1). API: `Pickup`, `Dropoff` (needs a path different from the one walked), `GetTug`, `HasCargo`, `Follow`, `Attack`, `SetObjectiveOn` (all REF). Co-op: any friendly tug returns the relic (CR rule); a live enemy tug needs host authority and a deterministic target choice.

### 6.4 ss04 An Unexpected Connection ↔ misn05
- **TC adds.** Info-key inspection gate for the objective; the structure then flips to player so enemy AI targets it (a hold phase); a "bombers" strike that is actually a ground rocket group with a difficulty-scaled size; the richest set of small AI groups in the early chapters: turret ring respawning every ~2 minutes, pool patrols, a recycler-killer squad rebuilt periodically so stale squads do not linger, a factory/armory killer picking targets in order, a guard group in three waves rallying at paths, an artillery counter-squad that reacts when player artillery comes within 600 m of the enemy recycler; killing the enemy recycler early skips to the hold phase; a free alien scavenger to find and inspect; passive hazards removed at the right time.
- **Pacing.** 18 voice lines; ~10 minute relief timer before friendly reinforcement arrives.
- **CR status.** Discovery film, four shuffled deployment waves, razor assault, 23 persistent mines, supplemental waves, victory fleet cinematic, strong `DiffUtils` use (about 27 references).
- **Fit.** Medium. Candidates: the artillery-hunter anti-cheese squad and the "kill the recycler early to skip ahead" shortcut. API: `GetNearestEnemy`, iteration over craft by ODF, orders. No new API. Co-op: counter-squad should evaluate every human's artillery.

### 6.5 ss05 Escape from Mars ↔ misn06
- **TC adds.** Hidden deadline with surprise last-stand (idea #9); intro skirmish between scripted friends and enemies; a rising crane camera (height creeping up each frame); orbit camera on a huge alien craft; three starport buildings scanned in any order; a launch-pad rocket protected until scanned (destroying it first fails); rocket launch with quake and chase camera; final phase: build base, hold until a dropship ("Big Betty") arrives after about six minutes and lands; four fail variants share one timer through a failstate array; seven fail debriefs.
- **Pacing.** 58 voice lines, five camera set pieces. Time limits fixed regardless of difficulty.
- **CR status.** Opening camera, Hephaestus scan, three info types, three waves, 540/362/180 timers, 5th Platoon film, rocket launch film with tracked camera and FX, orbital film, restored VO, six loss debriefs, no difficulty scaling.
- **Fit.** Medium-high. Best new idea is the **dust-off as a real dropship landing** using `CRDrop18` choreography, and the protect-the-pad-until-scanned rule if not already present. API: `CRDrop18`, `IsInfo`, cockpit timer. Co-op: `CRDrop18` is already replicated.

### 6.6 ss06 Behind Enemy Lines ↔ misn07
- **TC adds.** Dropship cold open; jetpack hand-off (control the pilot via weapon mask + a velocity vector, with a hard reset on death); a runner/alarm system (fleeing scouts that trip an alarm if they reach the gatekeeper, a four-tank response, voice differs by who tripped it); a **cheater punishment** if the player enters through the front gate without bailing out (hostile guards, buildings made tanky, objective rewritten, helper removed); comm-tower damage spawns pilot defenders; the first appearance of the wave director after the recycler deploys; an artillery hunter; factory rebuild only when the player is away; scout patrol interval lengthening because "the OA has a time limit".
- **Pacing.** Two distinct acts (stealth then base-kill), 20 voice lines, call queue gating objective swaps.
- **CR status.** Alarm/stealth rules, runner pursuit, Razor One glide/theft/regen, restored test-range arc, prototype tank production, no timed waves (stock AIP on team 5), no difficulty scaling, per-player alarm table for co-op.
- **Fit.** Medium. Candidates: cheater punishment (a graceful sequence-break response) and, after deploy, an optional director (§5.2). `SetWeaponMask`, `FireAt`, `SetVelocity` are documented, so the jetpack hack is portable in principle but CR already has its own solution.

### 6.7 ss07 A Nasty Surprise ↔ misn08
- **TC adds.** Walkers hit the allied base first; the first walker's side is chosen by player position (west/east), named "Unknown Alpha/Beta" on the HUD; hidden artillery pickups and a hidden relic site flip to buildable friendly versions when scanned; a Cthonian ruin to find as a bonus and a win gate (find ruins before the win line plays); lanes of the director staggered 60/120/180/240 s; allied base pre-weakened so the massacre reads quickly with killers' health pinned.
- **CR status.** Colorado massacre, walker production, relic recon, AIP composition change at 420 s, Venus storm beat, no difficulty scaling, no film.
- **Fit.** Medium. New to CR: scan-to-unlock optional rewards (idea #8) and the named-threat HUD markers. API: `IsInfo`, `SetTeamNum`, `SetObjectiveName/On`. Co-op: rewards must be granted to the team, not whoever scanned.

### 6.8 ss08 Wrangling the Fleeing Herd ↔ misn09
- **TC adds.** Six artillery on plateaus pre-framed by a camera pass of 3 s each; anti-cheese: a factory built too early near the deploy nav before the artillery are dead is damaged to death; "Charon" unknown object that demands an ID scan within 30 s or fails the mission as disobedience; announcement ladder ("15 min out", "5 min out"); an enemy tug loop (fetch relic, follow friendly tug, rebuild); the convoy turns toward the player factory; **recurring convoy rebuilds**, shrinking; kill-the-factory squads growing 2/4/6/8 every 80 s; **assassin squad that hunts the friendly tug carrying the relic**, order re-sent every 7 s, rebuilt after both die; six fail variants including "too many critical assets lost".
- **CR status.** One convoy after ~1300 s, six artillery with camera, Charon recon, Prescott's platoon, relic tug, restored radio lines, no recurring waves, no difficulty scaling.
- **Fit.** Medium-high. Candidate set: the carrier-hunter assassin, countdown announcements, and a shrinking recurring convoy (tune carefully so the player is not overwhelmed). API: all REF.

### 6.9 ss09 The Race is On ↔ misn10
- **TC adds.** Dropship cold open; relic starts neutral and flips ally when first seen; enemy tug escorts with limited lives; a field HQ "jammer" advisory when near the player; **the twist**: the moment the relic is secured, the mission announces trouble and turns into a base defence with the full wave director, artillery, scavs, a daywrecker timer, and a second win condition (kill enemy recycler and factory, then keep the relic within 80-100 m of the recycler for ~10 s).
- **Pacing.** Tension in act 1 is the race; act 2 is a hold-and-hunt with a staggered director. 13 voice lines.
- **CR status.** Relic race (seven variants), enemy tug chase, artillery shelling, Plan B AIP, Io weather, quake on pickup, co-op unverified live. Skips a temporary-relic mechanic from the source on purpose.
- **Fit.** Medium; idea #10 is a structural change, so make it an owner decision or an optional "extended" mode. The daywrecker and director (idea #2, #3) are cleaner contributions.

### 6.10 ss10 Bring it Home ↔ misn11
- **TC adds.** Almost the same story as CR: three tugs, a defecting tug, blockade, pad destroyed, second pad built. Extras: a bleed on the pad (small damage per tick so it dies slowly if not defended), backup squads if half the escorts die, a "last chance" trickle of scouts until the player reaches pad B, a warning when the player gets near the defector's base, two lines per fail.
- **Pacing.** About 10 minutes, three pressure spikes, no base building.
- **CR status.** Defector unkillable by +300 hp/update, scripted strike waves, ambush table, backup squad, lava repainted so the dry route matters, pad destruction with a 40 s escape delay, last-camera finale, co-op not live-verified.
- **Fit.** Low; mostly parity. The *pad bleed* is a cheap tension device for the existing pad loss beat.

### 6.11 ss11 Flying Solo ↔ misn12
- **TC adds.** See §5.7. Plus: opening orbit over the comm tower for ~17 s, a mine squad laid on the exit route after the data is taken, a 600 s timer, ordered checkpoints with a checklist objective whose lines change colour as items complete.
- **Pacing.** Roughly 10 minutes, heavily scripted, 30 voice lines. No difficulty-driven numbers beyond the pass-through.
- **CR status.** Richest cinematic content (~215 camera hits), per-human stealth, challenge timers, uplink 45 s within 60 m, 20-minute cockpit timer, SetPerceivedTeam(5) on the stolen ship (needs live run), howitzers shell only exposed humans.
- **Fit.** High for intel markers via scan, boundary paths, graceful cover-blown handling, colour-coded checklist. API: `IsInfo`, `AddObjective` colour tags, `SetObjectiveOn`, `SetPerceivedTeam`. Co-op: markers and checklist must be per-human or team-shared by design.

### 6.12 ss12 Total Destruction ↔ misn13
- **TC adds.** An artillery strike on the player recycler around the 10-minute mark (two guns spawned at an alt point, walked to a plateau, announcer line depends on whether the recycler is on the plateau), a **special package**: after silos fall, a pilotless hover tank appears marked for the player to claim by walking up to it, with the objective naming the real unit; an **ice-slide cinematic** (mountain prop animates, quake ramps to 80, new ruin revealed, mission completion requires the cinematic to have played); a 30-minute failsafe that triggers the cinematic if the base is destroyed fast; minelayer squads; daywrecker after the player's first factory.
- **Pacing.** Sandbox of 30+ minutes, waves 2→8 per lane.
- **CR status.** Opening rush, howitzer march, silo scrap clamp, restored reinforcement waves (300/600/900 s), idle wingmen given roles, ice quake on factory fall, bomber retreat intentionally disabled by the owner.
- **Fit.** Medium. Candidates: special package reward, artillery strike, daywrecker. The landslide scene needs an animation hook: `SetAnimation` is not documented; EXU entity animation or a model swap could replace it. API: `KillPilot`, `GetODFString`, `exu.SetEntityAnimation*`.

### 6.13 ss13 The Three Beacons ↔ misn14
- **TC adds.** Dropship cold open; an **ambush ladder**: each rescued trio of pilots spawns a hunter squad aimed at the APC, first two dressed as CCA (separate teams allied to CCA, with distinct colours) and the third Fury, each followed by a survivor monologue that hints at the truth; a mid-mission **alliance flip** (Ally/UnAlly toggles; CCA turrets and patrols stand down, the CCA lab becomes the rescue objective); scientists evac with a dropship that lands at <500 m, opens at <180 m, and a Fury rocket every 30 s at the APC; four fail variants including "survivor died at a beacon".
- **CR status.** Concept C rewrite: activated Fury squad, loss of control, rogue waves every 180 s, CCA surrender, rescue 3, scientists, APC to Texas, cameras (~168 hits), `CRFuryRoster`, co-op offline-verified only.
- **Fit.** Medium. Candidates: ambush ladder per rescue and dropship evacuation via `CRDrop18` choreography. Disguised enemy squads work because SetPerceivedTeam is documented, but TC uses plain team alliances; either is fine.

### 6.14 ss14 United We Fight ↔ misn15
- **TC adds.** Quota banking: scrap converted to "units" in fixed steps with milestone lines; scattered friendly squads discovered on a 300 s cadence rotating spots, neutral until the player is within 100 m; the Tartarus restricted zone (350 m warning, 90 s grace, then Fury hunters; destroying it triggers a staggered 8-rocket stream); a hidden three-extractor objective whose fail text exists but is never triggered (dead content, a clean idea if built properly).
- **Pacing.** Slow economy puzzle, first real wave at 5 minutes, waves 2→10.
- **CR status.** Convoy, NW rescue, optional NE group restored, 75 scrap, Tartarus guard with 150 m/80 m rule and bolt-mine grid, hunters 1/2/3 by humans, Titan weather, native acceptance outstanding.
- **Fit.** Medium-low. Candidates: milestone reporting at fixed steps (CR already reports at 40/65) and the cadence-based friendly discovery loop. No new API.

### 6.15 ss15 Strike at the Heart ↔ misn16
- **TC adds.** Allied reinforcements picked from six manifest types at one of four spawn paths with distinct radio lines and an optional reinforce camera only if no enemy is within 250 m; **counter-strike on breach**: two gun towers on one side destroyed → the Fury sends a rocket strike every ~5 minutes; daywrecker (§5.3); a Fury artillery-hunter; bolt-mine field and turrets regrow only when the player is >300 m away; a victory tour of three chained voice lines; nags every 10 minutes after 20 minutes; a 30-minute soft-limit message.
- **CR status.** Nine CCA reinforcement groups (seven manifests), Fury SAV pressure from 60 s (gap shrinks 150→60 s), SAT pairs, transport-escape finale with native two- and four-client passes, retextured Fury-corrupted structures, restored VO.
- **Fit.** Medium. Candidates: counter-strike on breach and the daywrecker; the rest overlaps CR.

### 6.16 ss16 Tapping the Core ↔ misn17
- **TC adds.** Dropship cold open and a fly-over camera that visits each of seven power gens in sequence; **chain-detonation of the whole mine field** one mine per frame via `Damage` after the last gen falls; a second phase where four factories are kept at full health until four geothermal generators die (health refill), then a scripted collapse of all four factories 2 s apart with gun towers killed; allied reinforcements from five factions chosen at random, group size by difficulty, each aimed at the nearest tower; Fury tower defenders switch `Defend2`→`Defend` when their tower falls; seven of 24 gun towers deliberately removed.
- **CR status.** Opening cinematic (cineractive 1-7), seven towers with two hvsat each on proximity, 54-mine field, minecin cutscene, three-part factory win with explosions, optional crystal route, jungle weather, co-op simulation-tested.
- **Fit.** Medium. Candidates: the second-phase "shield" objective (invulnerable-until-X), allied reinforcement pools by difficulty. The mine chain detonation is probably already what the CR `minecin` cutscene does.

### 6.17 ss17 The Ultimate Quake ↔ misn18
- **TC adds.** A **60-minute global clock** plus a 390 s "find the ship" timer, a 120 s extension when found, a 3 min evac timer; thruster progress voice lines and a spawn of two Fury rockets at both entry points when each pod falls; the ship held at full health until the fourth pod; the last pod gets a health snapshot/restore if the player drifts away; quake restarted and ramped every 90 s up to a cap; "boom" scenery popping at random points with an interval that shortens every 10 minutes; environment drift over six 60 s steps toward red; and the **ending machinima**: the moon is a scenery prop that is blown up, asteroids spawned and sent away with `Retreat`, a camera path per asteroid at 9 s each (about 45 s), lighting preset swapped to a space look, the score's volume ducked, no skip.
- **Pacing.** Long and timer-heavy; mission length is the player's choice up to the hour.
- **CR status.** Best-documented CR mission: shared cockpit timer, 180 s countdown, `CRStorm18` suite, up to five NSDF dropships loading humans and base, unskippable shared shots, Fury scaling, live results 2026-10-19.
- **Fit.** Mixed. The environment drift and boom scenery are covered by `CRStorm18` (cracks, landslides, vehicle debris) and documented EXU sky/fog calls. The epilogue is the new thing: a short orbital view of the break-up after the extraction. Needs a body prop with an explosion, invisible camera targets, `CameraPath` per shot (documented, but the camera stack must stay balanced, REF:270), and an unskippable replicated shot following `CRMisn18`'s C-channel pattern. The music duck depends on `IFace_ConsoleCmd`, which is not documented; skip it. Asset dependency: the planet/moon prop.

## 7. Secondary pass: TC Black Dogs bd01-bd10 vs CR bd01-06, bdmisn07-15

TC rewrote the Black Dog arc (new story: rogue NSDF faction, Crimson Bears in place of stock CCA), so titles and order do not match CR's stock-faithful ports. The table pairs them by gameplay theme only.

| TC | Theme | Nearest CR mission(s) | Note |
|---|---|---|---|
| bd01 Grab the Scientists | Scan a tower, kill generators in sequence, scientists flee when you approach | bd01 Close Target Wrecky (cloaked ambush) | different shape |
| bd02 Preparations | Ordered build tutorial that fails on wrong order, call-center objective list | bd01/bd02 | no CR counterpart |
| bd03 Exploratory | Foot recon, steal a tug, perceived-team disguise, escape clock | bd04 Wolf in Sheep's Clothing, bdmisn09 | good match |
| bd04 The Mammoth Project | Decoy plus trap, steal the real prototype | none (closest: bdmisn10) | |
| bd05 The Last Stand | Defend with wave director, jammed tower | bdmisn12 Meanwhile, Back at the Ranch | loose |
| bd06 Evacuate Venus | Escort two APCs, optional defector pickup | bd03 Spilt Milk, bdmisn09 | loose |
| bd07 Retrieve Relics | Dropship intro, tug escort, fake distress trap | none | |
| bd08 The Silencers | Timed sabotage, hold position to transmit, extraction | bdmisn13 Knavish Tricks (timer, deny) | loose |
| bd09 Capture the Armory | Timed vault run, chambers, collapse | none | |
| bd10 Prepare to Evacuate | Build a rocket under siege, VIP APCs, launch | bdmisn15 The Best Laid Plans | finale parallels |

**CR status of the BD set.** All 15 scripts are single-player stock-API ports with no `ScriptSubtitles`, no `aiCore`, no co-op layer, no difficulty scaling, and mission maps not in the repo. Subtitle data is ready: `Config/durations.csv` has per-wav durations for all BD narration (126 rows) and `Tools/TranscriptSources/GoombaBZ/campaigns.csv` holds transcripts. Wiring subtitles is a documented, low-risk task independent of TC.

**Ideas to take from TC's BD arc**
- **Ordered-build tutorial with a call-center objective list** (bd02): green line per completed step, sound cue per rewrite, fail on out-of-order build with a dedicated debrief. Works for CR's early BD missions that teach building. API: `AddObject` callback by ODF, `AddObjective`.
- **ODF-driven numbers** (bd10): read build cost and build time from the ODF (`GetODFInt`, REF) so briefing text and timers follow balance changes. Cheap, documented, and makes CR's own tuning self-consistent.
- **Boss-on-a-timer sortie** (bd10): an enemy commander who sorties every few minutes and retreats at low health; tied to the pad appearing to raise stakes.
- **Harassing the builder** (bd10): assassin squads that go for the constructor and then the pad.
- **Hold-position transmission** (bd08): stay near a dish for N seconds with an uplink-lost reset; CR's misn12 uses the same device.
- **Penalty ladder instead of instant fail** (bd03): used above in §5.7.
- **Casualty-gated rescue artifact** (bd05, bd07): a bonus unit appears only if the player has lost wingmen; a quiet difficulty assist.
- **Cutscene safety** (bd04, bd09): re-apply player and wingman health during a camera shot so nothing dies on camera; already used by CR in places.
- **Scaling by wingmen** (bd01, bd09): higher difficulty gives more allies because enemies are placed in the editor. Counterintuitive but trivial with `DiffUtils` if CR wants any BD scaling.
- **Dropship extraction cadence** (bd03, bd06, bd08): land animation at ~470 m, open at ~160 m, win at 64 m, spawned late, cleared hostiles told to retreat on win. Fits `CRDrop18`.

## 8. Things not to import

- **Hard-coded BZCC enum numbers** (raw command ids for build and dropoff): use AiCommand names.
- **Frame-by-frame health pinning to fake invulnerability** is fine for cutscenes, but note `pcall` does not protect against native heap writes (AGENTS.md, Livewire note); never blanket-apply commands to static fixtures.
- **Dead content and bugs observed in TC** (do not reproduce): difficulty-scaled respawn tables that never apply (ss01), strike size variable mismatch (ss04), a turret respawn block that cannot run (ss06), a `GetTime` compared without being called (bd06 "leave no man behind"), an unused "failed to deploy extractors" fail text (ss14).
- **Hostile punishments for sequence breaks** are fun in TC but conflict with CR's source-faithful posture; offer only where the stock mission already has a hard rule.
- **Skill pass-through** (`SetSkill`) is not documented; do not plan on it.
- **Non-skippable machinima** is fine only in single-player shots; CR's rule is per-player local skip, unskippable only for shared shots.

## 9. Suggested sequencing and open questions

**Sequencing (suggested, each its own PR):**
1. Probe pass: one native test mission that exercises the "not documented" calls actually needed by chosen ideas (a build/dropoff `SetCommand` by name for the armory; an EXU entity animation for a map prop; the control mask in a replicated start). No design work depends on `SetCanSnipe`, `SetControls`, `SetAnimation` or `IFace_*` existing.
2. Cheap, documented, single-mission changes: orders-with-teeth ladders, fail debriefs, hidden clock, scan-unlocked rewards, `CRDrop18` reuse in misn06/misn14.
3. Relic theft loop (misn04, misn09, misn10).
4. Shared wave director module plus counter-strike and daywrecker, opt-in per mission.
5. BD subtitle wiring (data ready) before any BD design changes.
6. Epilogue machinima, only if art for the body prop is ready.

**Open questions for the owner**
- Is CR content change on source-faithful missions allowed, or should every idea above be a toggle/"extended" variant?
- Is a second act on misn10 acceptable, given the faithful relic race?
- Is there any music-volume control available to scripts (needed only for the ending duck)?
- Does the mission set want any difficulty scaling beyond what misn01-05 have today?
- Co-op posture for BD: stay single-player or invest in a `CRCoop` layer first?

## 10. Source references

- TC mission list: `BZTC_Core/missions.odf` (read-only, Steam Workshop 2344006579), scripts `BZTC_SCRIPT/bztcss01..17.lua`, `bztcbd01..10.lua`, text `BZTC_CAMP_TEXT/`.
- CR: `Scripts/misn*.lua`, `Scripts/bd*.lua`, `Docs/MISN*_*.md`, `Docs/BD05/06_LUA_PORT.md`, `Docs/BLACKDOG09/12/14_LUA_PORT.md`, `Docs/BZR_LUA_AGENT_REFERENCE.md`, `Docs/lua-definitions/ExtraUtils.lua`, `Docs/AGENT_KNOWLEDGE_BASE.md`.
- Working notes behind this doc: shared notes folder `side-session-notes/local_30dd5b58-c364-4e6e-8526-7d9b65b84fdd/tc-ideas/` (outside the repository).
