# N64 Pilot Mode in the US and Soviet campaigns

The N64 "Pilot" option (`g_800B93D5`, settings block `0x800B93A8 + 0x2D`)
turns off the player's unit commands and lets each mission script run your
side. All 25 US/Soviet campaign overlays (table 0–24) test the flag. This file lists, for each
one, what its Pilot Mode branch does, so Campaign Reimagined's
`PlayerPilotMode` can be tuned per mission instead of running generically.

Source: `mission_scripts/mNN_*.c`. The unclear parts were checked against the
overlay disassembly. The engine half of the option (the command lock, hidden
HUD counters, silenced voice reports) and the Black Dog missions are covered in
`redux_lua/README.md` ("Pilot Mode") and `redux_lua/bz64pilot.lua`.

Conventions:

- Positions are in Redux/BZN world coordinates. The overlays store them with
  96000 taken off z, and 96000 has been added back here.
- A number after an item is the scrap it waits for. "+ pilot" means it also
  needs `GetPilot(1) > 0`. "4 reserve" means the mission keeps 4 scrap spare,
  so a 6-scrap tower waits for 10.
- `label N` is BZN label N (`bzn64label_%04X`). `path N` is `bzn64path_%04X`.
  The ODF names are the staged Redux ones (`n64pNNN` for unnamed N64 variants,
  from `tools/bz64_odf_table.py`).
- "Objective A -> B" means Pilot Mode shows ROM text B where Commander mode
  shows A. The objective text is `en_objectives[id - 347]`, and the debrief
  text is `en_mission_text[id - 242]`.
- AiCommand numbers follow the BZR Lua Agent Reference order: `GO` = 3,
  `DROPOFF` = 8, `GET_REPAIR` = 10, `GET_RELOAD` = 11, `GO_TO_GEYSER` = 16,
  `RECYCLE` = 18.

## Shared building blocks

Every mission builds its Pilot Mode logic from a handful of patterns. They
line up closely with what `PlayerPilotMode` and `aiCore` already have.

| N64 pattern | what it does | CR counterpart |
|---|---|---|
| producer re-send | A recycler or factory that isn't deployed and whose current and pending command aren't `GO` / `GO_TO_GEYSER` for 60 frames is ordered again. Recyclers usually get `GO_TO_GEYSER`; some missions use `Goto` a named geyser. | the recycler/factory managers, or an adapter `update` |
| producer ready | `IsDeployed` and not building (object `+0x234`). | `IsDeployed(h) and not IsBusy(h)` |
| build queue | One `Build` per frame, first unmet item wins, each waiting for its scrap (and pilots). | `profile.autoBuild` plus a mission-specific queue in the adapter `update` |
| scav top-up | When one of the two scavengers is missing, the recycler builds one and the script **tops scrap up to 4 and pilots up to 1** so it can't stall. | same, in the adapter |
| placement | New turrets are sent (`GO`) to fixed spots, and constructors `Build` then `Dropoff` at fixed spots on the next update. | adapter `AddObject` hook; the reference's "Build then Dropoff next Update" rule |
| wingmen follow | Wingmen, tanks and fighters are told `Follow(player)` at creation, every 30 s, and whenever the player changes craft. | `profile.stickToPlayer`, or an objective action `{command = "follow", target = player}` |
| player supply | Player health or ammo below 0.75 with no pod of that kind standing makes the recycler build `aprepa` / `apammo` (Soviet `sprepa` / `spammo`). An armory instead launches up to two pods at the player (`GET_REPAIR` / `GET_RELOAD` path commands at the player's position), 3 s apart, ammo first. Needs scrap > 0. | adapter `update`; for an armory, `BuildAt(armory, "aprepa", GetPosition(player))` |
| cargo | A tug built or found is sent to pick up the mission object and bring it back. | `PlayerPilotMode.SetCargoJob` |
| user target | Each new nav beacon becomes the player's target (`SetUserTarget`). | mission script |
| text | Objectives, debriefs and voice messages switch to Pilot variants that drop "build X" instructions. | mission script |
| extra fails | Losing a unit the script depends on (factory, tug, constructor, howitzer, APC) fails the mission, sometimes only in Pilot Mode. | mission script |

The first four missions CR already has adapters for (misn02b, misn03,
misn04) line up with sections below. misn04's relic cargo job is the N64 tug
logic.

---

## US campaign

### misn02b (table 0)
- Voice 531 -> 540. Objective 354 -> 357, "Get inside a vehicle. Escort the
  scavenger." (the "use the recycler to build a scavenger" part is gone).
- The recycler builds an `avscav` at once.
- Win debrief 251 -> 423 (same text).

### misn03 (table 1)
- **Attacks come much sooner:** the wave timers are +20 / +60 / +180 s (with
  280 as the next step) instead of +200 / +310 / +430 s (530).
- Voice 538 -> 545. The "use the recycler to build turrets" objective
  (359/364) is never shown.
- Recycler (label 12, `avrec3`): `GO_TO_GEYSER` when the turret phase starts,
  with the 60-frame re-send. Once deployed it builds `avturr` (6) until four
  turrets stand within 200 m of the command tower.
- The first four turrets go to (1180, 101212), (1212, 101156), (1150, 101373)
  and (1190, 101294).
- Debriefs: win 259 -> 425, fail 253 -> 424.

### misn04 (table 2)
- Timers: the first wave is +10 s instead of +30 s; the relic alarm is +10 s
  instead of +60 s.
- Voice 530 -> 562 and 537 -> 563. Objectives: 367 -> 371 "Defend base from all
  Soviet attacks."; 369 -> 373 "Escort tug."; 372 "Return to unit factory for
  escort duty." while the tug is due.
- Start: the recycler (label 21, `avrec4`) goes to the geyser at label 9 and
  the factory (label 47, `avmuf4`) to the geyser at label 5, both with
  re-sends. Nav 35 is set as the objective.
- Queue, while both producers live:
  1. recycler `avscav` until two (4);
  2. factory `avltnk` (6) once both scavengers exist; it follows scavenger 1;
  3. repair/ammo pods for the player;
  4. recycler `avturr` until four (6), once the light tank exists;
  5. factory `avhaul` (6) when you return within 100 m of the factory; this
     also sets the escort objective and targets the new nav;
  6. factory `avtank` ×2 (8) while the tug lives; they follow the tug.
- Turrets 1–3 go to (1593, 100661), (1518, 100748) and (1620, 100532);
  turret 4 goes to path 57.
- The tug picks up the relic and, at the relic event, drives to the factory.
- Extra fails:
  - both scavengers lost (264);
  - tug lost after the pickup (266);
  - **factory lost (262, Pilot only)**.
- Debriefs 265 -> 426 and 267 -> 427.

### misn05 (table 3)
- Voice 530 -> 547 and 542 -> 548. The first nav (label 15) is the user target.
- Start: the armory (label 19, `avslf5`) goes to the geyser at label 3 and the
  recycler (label 10, `avrec5`) to the geyser at label 2, with re-sends.
- The armory supplies the player: up to two repair and two ammo pods.
- Wingmen follow the player (every 30 s and on a craft change).
- Recycler queue:
  1. `avscav` until two (4);
  2. `avfigh` ×2 (6) after the factory inspection;
  3. `avturr` until six (6).

### misn06 (table 4)
- The two tanks at labels 2 and 3 become escorts. At the convoy event they
  follow the recycler, and the recycler takes path 35.
- The recycler (label 9, `avrec6`) is ordered `GO_TO_GEYSER` when the platoon
  objective starts (re-sends).
- Queue:
  1. `avscav` ×1 (4);
  2. `apammo` ×2;
  3. `aprepa` ×2;
  4. `avturr` ×1 (6);
  5. `avfigh` ×8 (6 + pilot). Every new fighter follows the recycler.
- Once the launch pad is inspected and you're within 100 m, the recycler
  drives to path 38 (re-sent every 10 s). An earlier event sends it to path 36.
- New nav beacons become the user target.
- Objective 381 -> 387, "Protect recycler whilst platoon is built."
- Voice 571 -> 576, 564 -> 574, 543 -> 575 and 561 -> 573. Debriefs 280 -> 429
  and 279 -> 428.

### misn07 (table 5)
- Start:
  - the armory (label 74, `avsl7`) goes `GO_TO_GEYSER` (re-sends) and supplies
    the player;
  - the two turrets at labels 7/8 go to (2033, 97882) and (2015, 97837).
- Wingmen:
  - two `avtank` escorts follow you from nav 14;
  - once you're within 90 m of that nav they follow the armory.
- Every new nav camera becomes the user target.
- After the radar array (label 51) falls, the recycler "Utah" (`avrecn8`, path
  9) and a factory (`avmufn5`, path 12) arrive and are sent `GO_TO_GEYSER`
  (re-sends).
- Queue:
  1. recycler scavengers until two (top-up);
  2. `avturr` until four (6);
  3. factory `avartl` (8), which sets objective 392 "escort howitzers";
  4. a second `avartl` (8) after the power plant (label 44) is down;
  5. `avltnk` (6).
- Turrets 1–4 go to (2232, 100262), (2228, 100211), (2252, 100081) and (2306, 100083).
- Howitzers:
  - howitzer 1 goes to (2466, 99919) and, once deployed, attacks the power
    plant;
  - the light tank follows howitzer 2; howitzer 2 takes path 18 and
    howitzer 1 path 16;
  - once both are deployed after the plant falls, they attack the Soviet
    recycler (label 13).
- Extra fails: a howitzer lost (285), the factory lost (286).
- Voice 543 -> 549. Debriefs 284 -> 430 and 287 -> 431.

### misn08 (table 6)
- **The constructor (label 74) is removed at the start.** Objective 393 ->
  396, "Defend base while forces are constructed". Voice 530 -> 558 and
  540 -> 559, with extra clip 560 at the nav calls. The nav cameras are
  objectives, and label 25 is the user target.
- Recycler (label 45, `avrecn1`) and the factory it builds: `GO_TO_GEYSER`
  with re-sends.
- Queue:
  1. factory `n64p083` (10) if there is none;
  2. pods;
  3. scavengers until two (top-up);
  4. factory `avtank` ×2 (8 + pilot);
  5. factory `avartl` (8) once both Soviet walkers (labels 22/23) are dead;
  6. recycler `avturr` ×3 (6);
  7. `avfigh` ×8 (6 + pilot).
- Tanks and fighters follow the player (every 30 s and on a craft change).
- Turrets go to (2352, 101153), (2413, 101095) and (2293, 101204).
- The howitzer goes to (1869, 99301) and is set as an objective (objectives 396
  / 397 "escort howitzer" / 394, clip 562). Once deployed it shells the
  three power plants (labels 42/43/44) in turn, with clip 563 when all are down.
- Extra fail: the howitzer lost (291).

### misn09 (table 7)
- **Timers are longer to reach:** the waves and deadline are at 400 / 500 /
  600 / 660 s instead of 600 / 700 / 800 / 860 s.
- Voice 530 -> 549 and 534 -> 550. Objective 400 ("set up unit factory at nav
  3") is never shown. Nav 6 becomes the user target at the join-up.
- The armory (label 35) goes `GO_TO_GEYSER` (re-sends) and supplies the player.
- When the artillery is cleared:
  - the factory (label 44, `avmuf_n64_1`) takes path 16, then goes to the
    geyser at label 13 (re-sends);
  - the constructor (label 18) and the three scavengers (labels 19–21) follow
    the factory.
- Constructor: once the factory is deployed it builds `absilo` and drops it at
  (2836, 99811). When the silo exists, the rig is ordered to `RECYCLE` itself.
- Factory queue:
  1. `avtank` ×3 (8 + pilot), which follow the factory;
  2. `avhaul` (6 + pilot), which sets objectives 402 "protect tug" / 401;
  3. `avwalk` (12 + pilot), which follows the factory.
- Tug:
  - picks the relic up once the Soviet tug is dead, then follows the factory;
  - when the factory is within 300 m of the relic while an enemy tug holds it,
    the tanks and walker attack that tug, then escort the relic.
- Extra fails: the silo lost (301), the constructor lost before the silo (300),
  the tug lost (299).

### misn10 (table 8)
- Voice 530 -> 537 and 534 -> 538. The nav cameras at labels 2 and 32 are
  objectives from the start.
- Recycler (label 31, `avrecy_n64_2`) and its factory: `GO_TO_GEYSER`
  (re-sends).
- Queue:
  1. scavengers until two (top-up);
  2. factory `n64p085` (10);
  3. `avturr` ×2 (6 + pilot);
  4. factory `avhaul` (6 + pilot).
- The tug follows the player at the relic phase. Objectives 403 / 404
  "escort the tug to the relic" / 405 "escort the tug back to the recycler".
  Within 100 m of the relic (label 59) it picks it up.
- Extra fails: the factory lost (307), the tug lost (308).

### misn11 (table 9)
- Objective 406 -> 409, "Protect the three transports." (drops "Use your
  armoury for support").
- The wingmen at labels 18/19/20 follow the player (every 30 s and on a craft
  change).
- At the bridge, the armory (label 13) fires 3 ammo and 3 repair pods, one
  every 3 s, at the transports' crossing (2105, 99911).

### misn12 (table 10)
- Markers only. When the player gets within 100 m of the Soviet HQ (labels
  54 / 48) and its cameras switch to team 1, each camera becomes an objective.
  They switch off again past 300 m. No AI changes.

### misn13 (table 11)
- Objective 417 -> 418, "Defend your recycler." (no "destroy the Soviet unit
  factory"). The nav at label 16 is marked.
- The recycler (label 33, `avrecy_n64_3`) goes `GO_TO_GEYSER` at the start.
  Its factory `n64p086` goes to the geyser at label 9 when built, which also
  sets objectives 418 / 419 "defend your unit factory". Both have re-sends.
- Queue:
  1. scavengers until two (top-up);
  2. pods;
  3. factory `n64p086` (10);
  4. `avturr` ×4 (6 + pilot);
  5. factory `avtank` ×2 (8 + pilot), rebuilt when lost;
  6. `avfigh` ×6 (6 + pilot).
- Turret 1 goes to (3498, 97864) and the rest to (3472, 97953).
- Tanks and fighters follow the player.
- Extra fail: the factory lost (320).

### misn14 (table 12)
- Objective 421 -> 423, "Protect the recycler."
- The recycler (label 12, `avrecy_n64_9`) and its factory `n64p087` go
  `GO_TO_GEYSER` (re-sends).
- Queue:
  1. scavengers until two (top-up);
  2. pods;
  3. factory `n64p087` (10);
  4. `avturr` ×2 (6 + pilot), which go to (2489, 99475) and (2686, 99509);
  5. factory `avapc` whenever none is alive (6 + pilot);
  6. `avtank` ×2 (8 + pilot).
- The APC and tanks follow the player (every 30 s, on a craft change, and at
  each rescue-beacon event).
- Extra fails: the factory lost (323), the APC lost (324).

### misn15b (table 13)
- Objective 428 ("build scrap silos") is never shown. Voice 532 -> 548. Nav 18
  becomes the user target at the rescue.
- Start: the recycler (label 13) and constructor (label 30) follow the player.
- At the rescue:
  - the recycler goes to the geyser at label 11 (re-sends);
  - the tanks at labels 22/23 and the APC (label 24) follow the player;
  - each tank then guards a scavenger.
- The recycler tops up the scavengers and builds pods.
- Constructor: two `absilo` (4 each), dropped at (4066, 100266) and (4057, 100180).
- The APCs are ordered to `RECYCLE` themselves when they reach the recycler.
- Extra fails: the rig lost before both silos (331), a silo lost (330).

### misn16b (table 14)
- Start:
  - nav 17 is the user target;
  - the recycler (label 13) goes to the geyser at label 14 and the factory
    (label 12) to label 15 (re-sends);
  - **the armory (label 31) is removed.**
- Queue (4 reserve):
  - recycler: scavengers until two (top-up), then a constructor (`avcnst_n64_5`,
    8) whenever none is alive;
  - factory: `avtank` until four (8), all following the player.
- The constructor **rebuilds the base as it's destroyed**, one building at a
  time, at the original spots:

  | building | position | scrap |
  |---|---|---|
  | `abhang` | (3001, 99204) | 7 |
  | `absupp` | (2886, 99286) | 5 |
  | `abspow` | (2867, 99090) | 4 |
  | `abtowe` | (2903, 99059) | 6 |
  | `abtowe` | (2836, 99037) | 6 |
  | `abspow` | (2894, 99213) | 4 |
  | `abtowe` | (2962, 99211) | 6 |
  | `abtowe` | (2833, 99225) | 6 |
  | `abspow` | (2954, 99341) | 4 |
  | `abtowe` | (3000, 99330) | 6 |
  | `abtowe` | (2938, 99389) | 6 |

- Extra fail: the factory lost (335).

### misn17 (table 15)
- Start:
  - nav 18 is the user target;
  - the recycler (label 2) goes to the geyser at label 12 and the factory
    (label 10) to label 11 (re-sends);
  - the wingmen at labels 15/16/3/4 follow the player.
- Every 20 s the wingmen attack any enemy within 120 m of the player.
  Otherwise they attack the first standing Fury power tower (seven, in order).
- Queue (4 reserve):
  - recycler: scavengers until two (top-up), then a constructor (`n64p070`,
    8) whenever none is alive;
  - factory: `avtank` (8).
- The constructor builds the base where missing:

  | building | position | scrap |
  |---|---|---|
  | `abhang` | (1818, 99499) | 7 |
  | `absupp` | (1769, 99349) | 5 |
  | `abspow` | (1808, 99330) | 4 |
  | `abtowe` | (1836, 99288) | 6 |
  | `abtowe` | (1852, 99372) | 6 |
  | `abspow` | (1830, 99565) | 4 |
  | `abtowe` | (1766, 99539) | 6 |
  | `abtowe` | (1875, 99530) | 6 |

- Extra fail: the factory lost (338).

### misn18 (table 16)
- Objective 433 -> 436, "Protect recycler while forces are built." It goes
  green at eight fighters.
- Start: the tanks at labels 6/7 follow the player, and four free `avturr` are
  placed on paths 44–47.
- The armory (label 18) supplies the player.
- Recycler (label 4) queue:
  1. scavengers until two (top-up);
  2. `avfigh` ×8 (6 + pilot).
- The eighth fighter sends the whole group, with the tanks, after the player.
  From then on they attack the transport's four thrusters (labels 13–16) one
  at a time.

## Soviet campaign

### misns1 (table 17)
- Voice 530 -> 553. **The first attack timer is +30 s instead of +180 s.**
- Start: instead of 2 `svtank` + 1 `svfigh`, Pilot Mode builds 2 `svtank`
  (paths 19/20) and 6 `svfigh` (paths 21, 27–31). All follow the player.
- Recycler (label 18) queue:
  1. scavengers until two (top-up);
  2. `sprepa` / `spammo` for the player;
  3. `svfigh` (6) whenever one of the six is missing.
- Once the American recycler (label 4) is dead, an `svartl` is built on path 25
  and sent to path 26. It shells the towers at labels 23, then 26.
- Extra fail: the howitzer lost (395).
- Debriefs 396 -> 434 and 397 -> 435. The nav cameras along the recycler's
  route are marked and cleared as it passes.

### misns2 (table 18)
- The escort is split over the three transports (`svap2`, labels 23/24/25):
  - labels 5+2 guard transport 23;
  - labels 4+3 guard transport 24;
  - labels 18+6+7 guard transport 25.
- **The transports drive themselves** along the nav chain. When any one is
  within 70 m of the current nav (100 m for the last), all three are sent to
  the next. After the ambush, all three return to the first nav.

### misns3 (table 19)
- The four bombers (labels 18–21) follow the player (every 30 s and on a craft
  change). The navs at labels 17 and 34 become user targets.

### misns4 (table 20)
- Recycler (label 2) queue:
  1. armory `svslfn1` (7);
  2. scavenger (5);
  3. `svfigh` until four (7). The fighters follow the player.
- The armory goes `GO_TO_GEYSER` (re-sends) and fires ammo and repair pods at
  (2474, 99038) when the player is low.

### misns5 (table 21)
- At "secure the high ground, rebuild base defences":
  - the tanks at labels 27/13 follow the player;
  - the positions of the power plants (labels 20–22) and towers (labels 17–19)
    are recorded.
- The objective-510 event skips the normal team-AI economy settings.
- Recycler (label 5): scavengers (top-up), `spammo` when the player is low, and
  a constructor (`n64p377`, 8) whenever none is alive.
- Factory (label 23): `svtank` until two, more later (8). All follow the player.
- The constructor rebuilds each destroyed plant (`sbspow`, 4) or tower (`sbtowe`,
  6) at its recorded position.
- Extra fail: the constructor lost (410).

### misns6 (table 22)
- At the start the walkers (labels 29–31) follow the player. The recycler
  (label 7) and armory (label 33) go `GO_TO_GEYSER`.
- The armory supplies the player, and new pods are marked as objectives.
- At "destroy the field HQ" the walkers attack the HQ (label 32).

### misns7 (table 23)
- Voice 530 -> 558. The APC (label 34) follows the player from the start. The
  recycler (label 64) and factory (label 65) follow the player until their
  deploy event, then go `GO_TO_GEYSER` (re-sends).
- Queue: factory `svtank` (8 + pilot) and recycler `svfigh` (6 + pilot), all
  following the player.
- **Engineer pickup:** once the jail is down, the APC drives to each engineer
  in turn, then follows the player again. **Losing any engineer fails (418,
  Pilot only).**
- Later, the recycler drives to the Soviet hangar (label 15).

### misns8 (table 24)
- Start: the recycler (label 20) goes to the geyser at label 55 and the Fury
  factory (label 21, `savmf`) to label 54 (re-sends).
- Queue (4 reserve): scavengers until two (top-up), then a constructor
  (`n64p437`, 8) whenever none is alive.
- The constructor builds the base where missing:

  | building | position | scrap |
  |---|---|---|
  | `sbhang` | (1964, 100363) | 7 |
  | `sbsupp` | (1897, 100315) | 5 |
  | `sbspow` | (1829, 100314) | 4 |
  | `sbtowe` | (1836, 100351) | 6 |
  | `sbspow` | (1841, 100215) | 4 |
  | `sbtowe` | (1877, 100180) | 6 |
  | `sbspow` | (2025, 100356) | 4 |
  | `sbtowe` | (2063, 100349) | 6 |

- At the Fury event, one `svsav` is built for you at the geyser at label 9
  while the Fury factory stands.

---

## Pilot Mode text

| id | kind | text |
|---|---|---|
| 357 | objective | Get inside a vehicle. Escort the scavenger. |
| 371 | objective | Defend base from all soviet attacks. |
| 372 | objective | Return to unit factory for escort duty. |
| 373 | objective | Escort tug. |
| 387 | objective | Protect recycler whilst platoon is built. |
| 396 | objective | Defend base while forces are constructed |
| 397 | objective | Escort howitzer |
| 409 | objective | Protect the three transports. |
| 418 / 419 | objective | Defend your recycler. / Defend your unit factory |
| 423 | objective | Protect the recycler. |
| 436 | objective | Protect recycler while forces are built. |
| 424 | debrief | You did not protect the command tower. Be sure you watch this structure, it is the soviet's primary target. |
| 429 | debrief | You failed to protect your recycler. |
| 430 | debrief | You lost your recycler. Once the utah is dropped on venus, be sure to get to her and defend your base immediately. |
| 435 | debrief | You failed to protect your recycler. |

The other Pilot debriefs (423, 425, 426, 427, 428, 431, 434) are the
Commander texts, with minor wording changes. Get the exact strings with
`tools/bz64_text.py`. The voice IDs (540+) are unmapped clips; see
`BZR_PORT_NOTES.md` §6.

## Not covered

- Table 25–29 (misn01 and the training missions tran02/03/04/06) never read
  the flag.
- Some flags are set in one frame and read later. Where the pseudo-C was
  ambiguous, the branch was read from the disassembly, but the smaller items
  (marker toggles, message timing) were taken from the pseudo-C as is.
