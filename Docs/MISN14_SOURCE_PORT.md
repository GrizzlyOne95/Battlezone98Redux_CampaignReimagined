# misn14 source port

`Scripts/misn14.lua` ports `BZ1/from_bz2_dll_src/Misn14Mission.cpp` from
[Battlezone_Source at e7c4105](https://github.com/GrizzlyOne95/Battlezone_Source/blob/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/from_bz2_dll_src/Misn14Mission.cpp)
to stock Battlezone 98 Redux Lua 5.1. It uses the API contracts in
`Docs/BZR_LUA_AGENT_REFERENCE.md`; no EXU, OpenShim, or project helper is required.
The complete original C++ and header are archived in `References/Misn14Source`.

## Preserved behavior

- Both opening camera shots (12 s and 15 s), the combined `misn1401.wav` briefing,
  four named camera pods, initial AIP/resources, and the single objective message.
  `Start` enables team-2 strategic AI once so LuaMission can run the CCA AIP
  supplied by native AiMission; no late `SetAIControl` calls are made.
- Three sequential NSDF rescues, each with three original pilot spawn paths,
  defense/walk commands, strict 100 m APC trigger, 25 s loading delay, cleanup,
  radio messages, and 10 s gaps. Only the first rescue has the source's short
  pickup/completion shots. The first-site APC reminder and all survivor-loss
  checks retain their source gates.
- 100,000 maximum barracks health and 5,000 health added once per elapsed second.
- First alien wave **720 s after the intro ends**, followed by 180 s intervals.
  The source's “six minutes” comment conflicts with its active twelve-minute
  value; the value is preserved. Each wave selects one of the three original
  three-unit spawn triplets.
- Third-wave surrender: all team-2 craft become neutral; only stock `svtank`,
  `svturr`, and `svfigh` retreat. The named barracks and four towers become team 1.
- Fourth-wave general message/camera gated on `rescue3`, with the source's 150 m
  nearby-enemy cutoff. Fifth-wave CCA evacuation instructions/objective, 200 m
  pickup, 15 s ready message, 300 m return radius, and original outcome files.
- Independent sequential `if` blocks, strict timer comparisons, and original
  same-frame camera-cancel behavior. Native `GetTime`/`Get_Time` both map to Lua
  `GetTime`; the source's modulo RNG maps to Lua 5.1 `math.random(0, 2)` choices.
- All 24 flags, 10 timers, 20 object/audio fields, and the wave counter, including
  unused camera flags and the enemy recycler. Supported userdata stays in the
  state table for engine save/load conversion.

The source treats NSDF survivors as rescued as soon as an APC arrives; its death
checks stop during the subsequent 25 s wait. It also allows a return-home victory
as soon as CCA pickup begins, before the 15 s ready message. These unusual gates
are retained rather than redesigned. APC choice before CCA pickup remains the
most recently reported friendly `avapc`, as in native `AddObject`.

## Cut content

Inline Lua comments preserve `GameObject *fcycler,*ecycler;`, `AddPilot(1,10);`,
the disabled first-shot `StopAudioMessage(audmsg);`, and the disabled
`audmsg=AudioMessage("misn1402.wav");`. None is enabled. Every original mission
comment is retained inline; native setup/serialization comments also remain in
the byte-identical archive. Unused second/third rescue-camera flags are retained
as state, but the source contains no code implementing those shots.

## Documented corrections

| Correction | Why | Effect on ordinary mission flow |
| --- | --- | --- |
| Hold the selected APC once CCA pickup begins | Native AddObject could transfer the scientists to a newly built APC, hiding loss of the real carrier or granting an empty-APC victory | The same carrier must return or die; single-APC play is unchanged |
| Missing-base failure at `GetTime() + 5`, and latch `lost` | Source `FailMission(5.0,...)` specifies absolute mission time long past by wave five and does not record failure | Preserves the intended five-second failure delay when the base is absent |
| Require no pending loss and live objects for victory | Source could succeed after a survivor/APC loss, or succeed and fail on a destroyed recycler in one update | Original successful return radius and delay are unchanged |
| Treat missing/dead distance endpoints as infinitely far | Lua nil can select an inappropriate overload or fail; a removed APC cannot perform a pickup | All live-object distances and thresholds remain unchanged |
| Guard missing camera targets; release interrupted APC/base shots | Native camera calls assume their target still exists | Intact-target shots keep their timing; rescue and wave timers continue |

`SetObjectiveName` supplies native camera-pod `SetName` behavior using the stock
alias available across Redux versions. `IsOdfBase` accepts bare and `.odf` names.
`AllCraft()` implements the source's `IsCraft`-filtered object-list conversion.

## Validation and in-game follow-up

From the repository root:

```sh
lua5.1 Tools/Test-Misn14.lua
python3 Tools/Test-Misn14SourceParity.py
```

The Lua host checks intro timing/cancellation, resources/names, all three rescue
sequences, every survivor-loss combination, wave variants/cadence, surrender,
general-camera gates, CCA loading/return, carrier replacement/destruction,
missing targets, recycler loss, base healing, and state round trips at multiple
mission stages. It rejects invalid object queries and camera targets.
The Python audit verifies original Git blob hashes, all native state fields,
all mission identifiers, every Execute comment, and continued disabling of cut
calls. These checks do not establish native game behavior.

In-game validation remains outstanding: use the original misn14 map/path labels,
stock ODF/AIP/voice/objective/debrief assets, and the LuaMission binding. Confirm
native AI, survivor movement, camera framing, and engine userdata save/load at
the intro, a rescue wait, surrender/general shot, and loaded scientist carrier.
This checkpoint adds the script and review/test evidence; it does not change
map/TRN bindings, bless shipping entries, deploy, or publish Workshop content.
