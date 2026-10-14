# Campaign Reimagined agent knowledge base

Durable, repo-level knowledge for any coding agent (Claude, Codex, others) that builds or maintains
Campaign Reimagined (CR). It distills lessons, recipes, tooling and pitfalls that were each learned the
hard way at least once. It is a **map and a rulebook**, not a replacement for the detailed documents it
links: when a linked doc and this file disagree, the linked doc and the code win, and this file should be
fixed in the same PR.

Last consolidated: 2026-10-14. Statements about "current" PRs and branches go stale quickly; verify with
`gh pr list --state open` and `git log --all --since="3 weeks ago" -- <files>` before relying on them.

Conventions in this file: **[owner]** marks a decision made by the repository owner (do not re-litigate
it without asking); **[inferred]** marks an inference that has not been proven in the game; **[private]**
marks a source that exists only on the maintainer's machine and must never be committed here.

## Contents

1. [How to use this document and where work belongs](#1-how-to-use-this-document-and-where-work-belongs)
2. [Source-of-truth map](#2-source-of-truth-map)
3. [Co-op mission recipe](#3-co-op-mission-recipe)
4. [Weather and environment architecture](#4-weather-and-environment-architecture)
5. [Testing and validation](#5-testing-and-validation)
6. [Using Codex and other delegated agents](#6-using-codex-and-other-delegated-agents)
7. [Hard rules (never do)](#7-hard-rules-never-do)
8. [Lessons and pitfalls](#8-lessons-and-pitfalls)
9. [Decision log pointers and active work](#9-decision-log-pointers-and-active-work)
10. [Keeping this document current](#10-keeping-this-document-current)

---

## 1. How to use this document and where work belongs

Read `AGENTS.md` first (short, auto-loaded by most agents), then this file for the task you are about to
do. Sections 3-5 are the working recipes; section 7 is the list of things that have broken the project
before; section 8 is the pitfall index.

### Repository routing

| Work | Repository | Notes |
| --- | --- | --- |
| Campaign missions, Lua consumers, assets, materials, packaging, Workshop publishing | **CR** (this repo) | Only editable checkout: `%USERPROFILE%\Documents\GIT\Campaign-Reimagined` plus owner-directed per-workstream worktrees (see below). The Google Drive tree is legacy; never edit or reverse-sync it. |
| Native hooks, engine bug fixes, patch policy, renderer shaders (DX11 Enhanced base/terrain), live-test harness | **BZR-OpenShim** (`GrizzlyOne95/Battlezone98Redux_Shim`) | Patch entries live in `scripts/patches.json`; read its `AGENTS.md`, `Docs/AGENT_PATCH_WORKFLOW.md`, `AGENT_TOOLING.md`. |
| Reusable Lua/native runtime APIs (particles, camera, materials, `BuildSyncObject`, ...) | **EXU** (`ExtraUtilities`) | Prefers reusable C++ with thin Lua bindings; no campaign content. |
| Lua file I/O and constrained update primitives | **bzfile** | Mutating paths are security-sensitive; see its `AGENTS.md`. |
| Terrain format codecs (`.trn`/`.hg2`/`.mat`/`.lgt`) | **Battlezone98Redux_WorldBuilder** | `docs/MAT_FORMAT_VALIDATION.md`, `mat_codec.py`, `hg2_codec.py`. Read before inferring byte layout from a hex dump. It may not be checked out locally; check `origin` before use. |
| BZN/ODF/archive conversion tooling | **Battlezone98_Modding_Toolbox** | `python -m battlezone.bzn.version_convert`, `battlezone.archives.zfs.ZFSArchive`. |

Rule of thumb: if the fix would be needed by *any* mod, it is not CR's. A CR workaround for an engine bug
is acceptable as a stopgap, but name the owning repo and open or link the upstream issue/PR.

Verify `origin` and branch of any sibling checkout before treating it as evidence; sibling builds can be
from a different branch than you assume. Read a sibling's `AGENTS.md` before editing it.

### Branches and worktrees

- One `agent/<short-description>` branch per workstream, from current `origin/main`, unless you are
  deliberately stacking (then say which base you chose and why).
- `origin/main` often lags open PRs and other agents' branches. Before cutting a branch or designing a
  feature, run `gh pr list --state open` and `git log --all --since="3 weeks ago" -- <files>`.
- `AGENTS.md` says CR has a single canonical checkout and to serialize writes. In practice the owner runs
  parallel agents in per-workstream sibling worktrees named `Documents\GIT\Campaign-Reimagined-<topic>`
  (for example `-misn13`, `-moonwx`). Use a worktree only when the owner or the orchestrating agent
  assigned one, never touch another agent's worktree, and prune your worktree after the PR merges.
- Never leave pushed work invisible: end every workstream with a PR (draft is fine) or name the branch and
  why it has no PR.
- CR's GitHub slug is `GrizzlyOne95/Battlezone98Redux_CampaignReimagined`. From a directory that is not a
  CR checkout, pass `-R GrizzlyOne95/Battlezone98Redux_CampaignReimagined` to `gh`.

---

## 2. Source-of-truth map

Know which source answers which question. Several sources are **wrong in specific, known ways**.

### 2.1 Private, local-only sources (never commit, never paste into the repo)

This repository is **public**. The following exist only on the maintainer's machine. Describe what you
learned from them in prose; do not copy decompiler output, PDB-derived names/offsets, or game binaries
into any tracked file.

| Source [private] | Location (maintainer machine) | Good for | Caveats |
| --- | --- | --- | --- |
| `Battlezone_Source` repo | `%USERPROFILE%\Documents\GIT\Battlezone_Source` | One corpus for BZ1 and BZ2 research. Its own `AGENTS.md` demands PROVEN / STRONG INFERENCE / UNKNOWN labels; follow them. | Reference corpus, not an implementation repo. |
| BZ 1.5 decompile (`BZ1/1.5/`) | inside `Battlezone_Source` | What the **shipped** 1.5 `bzone.exe` actually does (function-per-file C-like export with symbols applied). | Reference-grade Ghidra output, not buildable source; 25 functions failed to decompile. |
| BZ 1.5 stock install tree | `Battlezone_Source\BZ1\1.5\Battlezone_Install` and the loose originals under `Program Files (x86)\Battlezone\stockfiles*` | Original `misnNN.bzn` (binary v1032), `.hgt`, `.mat`, ODFs, bitmaps. This is the **map source for ports** (see section 3.1). | CR wants the 1.5 *unsmoothed* terrain, not Redux's smoothed one. |
| BZ2 DLL mission sources | `BZ1/from_bz2_dll_src` and `BZ2/` in `Battlezone_Source` | The C++ `MisnNNMission` sources the Lua ports were transcribed from; many CR `References/*Source` folders derive from them. | **The shipped 1.5 exe can differ from the BZ2 DLL source.** Always check the 1.5 decompile for what actually ran (see 8.3). |
| Redux executable decompile corpus | `BZ1/Redux/openshim_re_corpus` in `Battlezone_Source`; restore into OpenShim with `reverse_engineering/Restore-ReCorpus.ps1` | Engine behaviour of the GOG Redux exe (the real runtime). | Git-ignored in OpenShim; never commit. |
| Leaked Redux PDB (`bzrpdb.zip`) | `BZ1/Redux` in `Battlezone_Source` | Naming hints only. | **Advisory only**: it is a different build from the shipping exe. Matching RVAs prove nothing. Confirm every address against the shipping GOG exe. |
| Z64Tools (RotBD N64 reference) | `%USERPROFILE%\Documents\GIT\Z64Tools`, branch `origin/agent/bd-lua-port` (not on `main`) | Decompiled N64 mission overlays for every US/Soviet mission and Black Dog; design source for per-mission Pilot Mode. | Search the N64 Pilot flag in `mission_scripts/mNN_*.c`. |
| Concept art (moon, Venus, Titan) | owner Drive / session scratch | Weather art direction. | Not in repo; ask the owner for the current copy. |

For Battlezone native RE start from the corpus and `BZR-OpenShim/AGENT_TOOLING.md` before raw
disassembly, then confirm addresses in the **GOG** exe. The GOG exe is unpacked (valid for static RE);
the Steam exe is SteamStub-packed, so let runtime bytes settle before comparing.

### 2.2 Public, in-repo sources

| Source | Path | Use it for | Caveats |
| --- | --- | --- | --- |
| Mission source references | `References/<Name>Source/`, `Docs/MissionSources/` | The C++ the port was derived from, kept for parity tests. | Parity tests (`Test-MisnNNSourceParity.py`) strip CR-marked regions and compare the rest. |
| Per-mission docs | `Docs/MISNNN_SOURCE_PORT.md`, `Docs/MISNNN_COOP.md`, `Docs/*_LUA_PORT.md` | Why each divergence from the original exists, owner decisions, live-check lists. | Co-op docs end with *inferences* and an unrun live checklist; read both. |
| Early mission audit | `Docs/EARLY_MISSION_SOURCE_AUDIT.md` | Native vs port phase coverage for misn02b-05. | Differences alone are not omissions (QOL changes are intentional). |
| Transcripts | `Tools/TranscriptSources/GoombaBZ/campaigns.csv` (778 lines), `units.csv`, README | Mission titles, VO line text, which wavs exist. `Tools/Import-GoombaTranscripts.py --check` is a CI step. | Annotations are upstream data kept verbatim and **often wrong** ("Unused voiceover" on lines that do play, e.g. `misn1303`). Verify against the source and the Lua. |
| Terrain codecs | WorldBuilder repo (see 1) | `.mat`, `.hg2`, `.trn` structure. | `.mat` is zone-major with Base in the high bits; use the codecs, not hex guesses. |
| Pilot Mode notes | `Docs/PILOT_MODE_CAMPAIGN.md` | Per-mission N64 Pilot branches, to tune `PlayerPilotMode`. | Offline only. |
| Lua API ground truth | `Docs/BZR_LUA_AGENT_REFERENCE.md` | Lua-facing engine APIs. | Hash-pinned across four repos; do not edit (section 7). |
| Platform policy | `Docs/BZR_PLATFORM_COMPATIBILITY.md` | Windows/GOG, Windows/Steam, Proton, Wine matrix. | Same pin. |

### 2.3 Which runtime is the truth

- `logs\openshim.log` (not `Ogre.cfg`, not a settings screen) states which renderer actually ran. Check the
  `configured renderer=` line before diffing logs; a play session may leave `Ogre.cfg` on Direct3D9.
- OpenShim redirects logs into `logs\`; the copies in the game root are stale. Exception: on Steam,
  `BZLogger.txt` and `BZOgreLogfile.log` stay in the game root (SteamStub defeats the early patch).
- Lua `print()` reaches `logs\BZLogger.txt`. Ogre does not log per-instance particle creation.
- Never use Steam's Workshop cache as a development target; `Local\Workshop` and installed copies are
  generated output, not source.

---

## 3. Co-op mission recipe

Goal [owner]: the **full CR campaign trees**, each mission playable as a shared offline mission *and* as
2-4 player co-op. As of 2026-10-14 misn02b-misn13 have co-op layers; misn14 and later are in progress or
pending. One `.bzn` and one `.lua` serve both modes. Use the newest finished mission doc
(`Docs/MISN13_COOP.md`, `Docs/MISN12_COOP.md`) as the structural template.

### 3.1 Per-mission checklist

1. **Scope first.** Read the existing faithful port (`Scripts/misnNN.lua`, `Docs/MISNNN_SOURCE_PORT.md`,
   `References/*Source`) and the 1.5 decompile for what shipped. List: unused VO (diff stock
   `misnNN*.wav` against Lua refs and the transcript CSV), disabled/cut branches, single-player hazards
   (3.4), and unused BZN paths. Present decisions to the owner before building anything non-obvious.
2. **Map.** Source is the BZ 1.5 original `.bzn`/`.hgt`/`.mat`, not Redux's. `Tools/Build-CoopMap.py
   --mission misnNN` is the maintained builder (older `Build-Misn06CoopMap.py` is its ancestor). It converts
   with the Toolbox (`version_convert --to redux`), sets class `MultSTMission`, moves the enemy from team 2
   to team 5 (and `perceivedTeam`), removes or reteams authored team 3/4 objects, strips mid-play snapshot
   state (runtime `[AiPath]` blocks, issued commands, velocity, duplicate labels), and adds four
   `pspwn_1` start buoys (teams 1-4, 25 m apart, **zero** velocity/omega/acceleration). Per-mission
   `REMOVE_LABELS` / `RETEAM_LABELS` live in the builder.
3. **Companions.** Ship Redux's own `.trn/.mat/.lgt` (extract with Toolbox `ZFSArchive` from `bzone.zfs`);
   the Workshop uploader needs them and same-name files override stock. The heightmap is the 1.5
   unsmoothed one. Unsmoothed `.hg2` for 36 stock maps exists in history (commit `ce18e89`, later deleted
   by `086ba03`): `git show ce18e89:Missions/misnNN.hg2`.
4. **Lua co-op layer** (section 3.2-3.6), marked with `-- CR ... >>` / `<<` regions so the source-parity
   test can strip them and prove the DLL port underneath is unchanged.
5. **Listing.** `Config/misnNN.ini` (mapType multiplayer, gameType S, 2-4 players), root `misnNN.des`
   (<= 300 bytes, CRLF, and it must be allowlisted in `.gitignore`), `Missions/misnNN.vxt` (avtank/avfimp),
   `Assets/Graphics/misnNN.bmp` (generic shared image), and the `[MISSIONk]` entry in
   `Config/crcampgn.ini` (3.7).
6. **Tests and lock.** Add the tests (section 5), update `Tools/Test-SetupMissionShell.py`'s campaign list,
   `crcampgn.des` range text, README scope lines and `CHANGELOG.md`, then bless the lock (3.8).
7. **Docs.** `Docs/MISNNN_COOP.md`: map, ownership, team table, owner decisions, restored content,
   inferences, and a live-harness checklist. Label unrun checks as unrun.
8. **Live check** with the harness (section 5.3) when the owner's session is available; update the doc.

### 3.2 Team and ownership model

| Team | Use |
| --- | --- |
| 1-4 | Human players (host on 1, guests on 2-4). Guest slots are **human-only**. |
| 5 | CCA / the primary enemy (the authored team 2 enemy is moved here). |
| 6 | Furies / aliens / mines / second hostile faction (misn02b's enemy is already 6; check the doc). |
| 7 | Support, survivors, allied NPCs and any authored team-3 allies (they would otherwise occupy a guest slot). |

- **Host-owned spawning.** Only the campaign leader (`CRCoop.IsAuthority()` / `IsCampaignLeader()`) builds
  enemies, issues orders, runs timers and decides win/loss. Plain `BuildObject` from a guest is local-only;
  guests that must spawn replicated units use `exu.BuildSyncObject` on the owning client and route orders
  to that owner.
- The authored Recycler/base is shared and host-run (`SetScrap(1, ...)`, `SetPilot(1, ...)` leader-only;
  the starting recycler of each human team is disabled in recycler-centred missions).
- Authored team-3/4 allies in later missions [owner]: remove them from the map, spawn them off-map on
  team 7, drive them to the rendezvous, then switch to team 1 there.
- Scale difficulty per extra human (typical: +1 hunter/fighter/tank per extra human, cap at 4 players,
  scrap bonuses), always with a documented cap.
- Pilot Mode (`PlayerPilotMode.lua`) **never** activates in MP/co-op [owner]; `aiCore` never manages human
  teams (wingman support only, opt-in).

### 3.3 `CRCoop` helpers and shared presentation

`Scripts/CRCoop.lua` is the co-op core (`Initialize`, `Update`, `Receive`, session readiness, leader
authority). Frequently needed helpers: `IsAuthority`, `IsCampaignLeader`, `IsHumanTeam`,
`ForEachHumanTeam`, `ForEachPlayerHandle`, `AnyPlayerSatisfies(pred)`, `AllPlayersSatisfy(pred)`,
`AllPlayersNear(target, distance)`, `GetPlayers`. Companion modules: `CRCoopComms`, `CRCoopPda`,
`CRCoopPingHud`, `CRCoopRespawn` (see `Docs/COOP_COMMS_PINGS.md`, `Docs/COOP_RESPAWN.md`).

- **Triggers:** proximity triggers become `AnyPlayerSatisfies`. Extraction and "the player must reach X"
  gates need **all** players (`AllPlayersNear`) [owner]. Route new any/all-player helpers through the
  mission's own `MissionDistance` guard (`CRCoop.AllPlayersNear` calls raw `GetDistance`).
- **Cutscenes, audio, objectives, markers** are replicated through the ordered, acknowledged E/A stream
  and the C (camera) channel via the presentation adapter (copy it from misn05; misn03 has `CameraPath`
  replication; misn04 has the `AudioDone`/`StopAudio` pattern). Shared cutscenes are leader-triggered and
  play on every peer; objectives are **per player** where the original was keyed on the player (stealth,
  per-player gates) and shared otherwise.
- **Markers** use the wire form `@handle@label`; guests resolve by label first (`GetHandle(label)`), then
  fall back to the replicated handle; ttl is relative to the guest clock (PR #186 pattern). Map objects
  that were never `SetLocal`'d arrive as nil handles in `Send`, so **labels are the only stable cross-peer
  key** for authored objects. (OpenShim hooks pack/unpack to synthesize ids from labels for unique-label
  map objects; verify your build includes that fix before depending on it.)
- **Local-only UI:** `IsInfo` (scanner info) is local, so guests relay to the host. Native `AudioMessage`
  **queues**; `subtit.Play` clears the subtitle sequence, so use `Play` for a block's first line and
  `subtit.Queue` for the rest (both return the native handle).
- Admission: early Q/K/P handshakes before `CRCoop.Initialize()` are consumed without acknowledgement
  (`Docs/COOP_ADMISSION_INITIALIZATION_20261009.md`).
- Guest-built objects are **not** listed in the host's Lua `AllCraft`; do not assume the host can see
  them.

### 3.4 Single-player hazards checklist

Grep every ported mission for these before trusting it in MP:

- `GetPlayerHandle()` used as "the" player (stored as `M.user`, used in triggers, `GetTeamNum(...) == 1`).
- Unfiltered `AllCraft()` / `AllObjects()` scans that retask, reteam or "clean up" every craft of a class
  (they hit guest craft and cameras; for example a surrender step that flips team 2 to 0).
- Hardcoded team numbers (enemy 2, allies 3, `SetAIP(..., 2)`), including `SetScrap/SetPilot` on team 1 only.
- Local-only UI/state: `IsInfo`, `SetUserTarget`, cockpit timers, local `AudioMessage`/subtitle state,
  camera calls, `GetCameraPosition`-style reads, anything keyed on "the local player".
- Single global flags keyed on `user` (alarm, out-of-car, vehicle stolen, uplink progress).
- `CountUnitsNearObject` thresholds that assume one human (use 1 + humans, or sum over human teams).
- Snapshot leftovers in the BZN (runtime paths, mid-drive velocities, pre-issued commands).
- Never blanket-apply unit AI commands to camera pods or static fixtures (`Docs/LIVEWIRE_VALIDATION_20261008.md`:
  `pcall` does not protect native heap writes).

### 3.5 AI: AIP vs aiCore

- **AIPs work under `MultSTMission`** (runtime-proven on misn09, 2026-10-13) with conditions: call
  `SetAIControl(team, true)` **once, at chunk root** (calling it inside `Start()` runs after the engine's
  AI init and null-derefs, killing the host); call `SetAIP(name, team)` only in `Start`/`Update` (never at
  chunk load); the team needs a recycler/factory and scrap; the BZN must keep its `[AiMission]` block; AIP
  unit ODFs must exist (unresolved ones are silently skipped). The stock `.aip` files and many `b_misnNN.odf`
  live in Redux's `bzone.zfs`, so they are **not** copied into the mod (the manager has no `.aip`
  classifier).
- `Scripts/aiCore.lua` (SP-era Lua brain, host-only) **redefines the global `SetAIP`**. In missions that
  load aiCore, the native AIP is never loaded; pick one brain per mission [owner decisions: misn02b native
  AIP, misn05 aiCore, misn13 AIP only because aiCore would fight the fixed-outpost win].
- A craft ODF without `aiName`/`aiName2` builds and looks healthy but has **no AI process**: `CanCommand`
  is false forever and hooks inside the process never run.
- A missing enemy recycler/factory/scrap means an AIP cannot build (misn02b); script-built forces (Lua
  `BuildObject` with caps and timers) are the alternative and are fully acceptable [owner].
- Orders: `Formation(unit, leader, prio)` is broken in stock Lua (a handle in arg 2 errors). Use
  `SetCommand(unit, AiCommand.FORMATION, prio, leader)` or `Follow`/`Defend2`. An OpenShim rebind exists,
  but CR keeps the `SetCommand` form.
- **Any Lua runtime error in an MP session can close the host** (the error alert hits a render exception).
  Treat Lua errors as fatal in co-op; guard with `pcall` only where the callee is pure Lua.
- Restored waves/reinforcements must obey the **no pop-in rule** [owner]: nothing is built within 400 m of
  any human (fog is typically 250 m). Fall back to another spawn, else retry later.
- Stock engine bug (fixed in OpenShim): a guest-owned scavenger on a host AIP team corrupted the host heap.
  If you see co-op host `0xC0000374`, check that OpenShim's scavenger guard is present.

### 3.6 Designing the co-op deltas

- Keep the DLL-faithful port intact and express co-op as marked deltas. Parity tests require explicit,
  documented co-op deltas, not loosened assertions.
- Prefer shared, host-decided randomness (seeded, peer-identical) for anything visual that must match.
- Decide and document what is inferred versus confirmed; put open questions in the mission doc.
- Cut content is restorable, but ask: restore cut VO with a trigger the story supports, behind a flag
  (`RESTORED_*`), with a CR marker region so parity strips it.
- Restored VO wavs ship as `Assets/Audio/*.wav` byte-exact from `bzone_en.zfs` (marked binary in
  `.gitattributes`; the manager has a `.wav` map) because Redux's de/es/fr/it archives lack many cut
  wavs (subtitle but silence). `Tools/Test-ShippedCutVo.py` guards this.

### 3.7 `crcampgn.ini` conventions

Each `[MISSIONk]` entry has the mission, `planet`, and a `voice=` that is the **Grizzly One retrospective**
(typically `misnNN00.wav` or the mission's last line such as `misn0518`), **not** the in-mission briefing.
Pick the unused retrospective line; for example misn13 uses `misn1305`, misn12 `misn1227`, misn14
`misn1422` [owner]. Planet drives Environment/weather hints. Mission titles come from
`campaigns.csv`. Campaign `mapType` is `campaign` (see 5.4 for what that does to command-line launches).

### 3.8 Shipping lock rules

`Shipping/shipping.lock.json` decides what lands in players' installs.

- New shipped files need `Manage-CampaignFiles.ps1 -bless`; **read the printed list and review the lock
  diff**. A stale lock fails Workshop staging as "missing required file", not as "lock is stale".
- Bless under **pwsh 7** (Windows PowerShell 5.1 writes a BOM that breaks `Test-SetupMissionShell`). Keep
  the lock **LF**. Bless writes CRLF and may re-sort: fix to LF in place.
- **Never re-sort the lock.** It is not globally sorted. To add entries without blessing, insert them in
  place beside their neighbours and bump the count; `Validate-CampaignRepository.py` confirms.
- Bless scans the **working tree including gitignored files**: move stray files (`luac.out`,
  `.claude/handoffs`, other branches' artifacts) aside first, then restore.
- Merge conflicts in the lock: resolve by 3-way membership union (theirs in order, plus our additions
  inserted after their predecessor), then run Validate; do not re-bless to resolve.
- Renderer payloads ship as `.payload` files (OpenShim 1.0.0.51+ reads them). Chunk meshes ship from
  `Assets/chunkMeshes_capped`; `Assets/chunkMeshes` still supplies 21 companion files the lock ships, so
  deleting that directory makes `-verify` report `LOCKED BUT ABSENT`.
- If a bless was done with zero-byte stand-in files, delete them afterwards (`find BZ_ASSETS_CORE openshim
  -size 0`); they are gitignored so `git status` looks clean while Validate reports hash mismatches.

---

## 4. Weather and environment architecture

Full detail: `Docs/WEATHER_ENVIRONMENT_OWNERSHIP.md`. The split is deliberate; do not blur it.

```text
.trn (FogEnd / VisibilityRange)
  -> Environment captures FogHorizon once, before anything mutates fog
       |- Environment.lua : time of day, base atmosphere, the single writer of renderer atmosphere state
       '- CRWeather.lua   : every weather phenomenon; registers Environment.RegisterEnvironmentModifier
                            (weather fog is clamped to the terrain horizon)
Per-planet directors sit on top: choose CRWeather presets + register modifiers; never write renderer state.
```

| Layer | Files | Owns |
| --- | --- | --- |
| Environment | `Scripts/Environment.lua` | Base fog, ambient/diffuse/specular, sun, world preset. Sensor scrambles via `SetObjectScramble` (only sensor writer). |
| Weather engine | `Scripts/CRWeather.lua`, `CRWeatherPresets.lua`, `CRParticleTemplates.lua`, `Materials/cr_weather.particle` | Particles, lighting modifiers, weather fog, transitions. Data-driven presets. |
| Planet directors | `CRMarsWeather` (`Docs/CR_MARS_WEATHER.md`), `CRVenusWeather` (`Docs/VENUS_WEATHER.md`, `VENUS_DENSE_ATMOSPHERE.md`), `CRIoWeather` (`Docs/IO_WEATHER.md`), `CREuropaWeather` (`Docs/EUROPA_WEATHER.md`), `CRMoonWeather` (`Docs/MOON_WEATHER.md`), `CRTitanWeather` (`Docs/TITAN_WEATHER.md`) | Per-planet ladders and events. |
| Site data | `CRVenusSites07-09`, `CRIoSites10-11`, `CREuropaSites12-13` generated by `Tools/Build-VenusSites.py`, `Build-IoSites.py`, `Build-EuropaSites.py` | Terrain-scan placements (pools, vents, anchors) derived from `.mat` painting. |

Rules:

- **Environment owns fog.** Weather requests are `min(requested, authored terrain horizon)`, applied before
  blending; at zero weight a layer contributes nothing. Do not fold changes to Environment's own `DayFog`
  into a weather commit.
- **Visual only by default** [owner]. Gameplay effects need an explicit owner decision (Venus lightning
  knockback/radar scramble is the approved exception; acid rain is visual only because chip damage annoyed
  players; Europa touches no sensor/gameplay/perception state at all, which keeps stealth missions safe).
- **Seeded and peer-identical.** The leader decides; every peer renders from the same seed and shared
  events (`VenusFog`, `IoQuake`, `MoonGlow`, ...). Weather events must be routed to guests; a director
  that only runs on the host will desynchronize visuals.
- **DX11 Enhanced caveat:** fog range scales terrain diffuse IBL. Raising global fog greys the sky and
  terrain. Where the owner wants subtle effects (Moon), keep global fog near off and use particle ground
  mist instead. Do not "fix" mood with global fog.
- **Missions that do not load Environment** (the moon missions) must not have a director that assumes it:
  loading Environment would add day/night and fog 420-1120.
- **CR owns weather content**; do not migrate or "unify" it into EXU [owner]. EXU provides mechanics.
  Redux ships no `.particle` scripts; assets ship flat in `mods/<id>/` (`.particle`, `.material`, `.png`
  at the root) and Ogre parses any registered resource location.
- Inherit `BZSprite/AlphaBlend` / `BZSprite/Additive` for billboards rather than declaring passes; textures
  should be white with shaped alpha so emitter `colour_range` tints correctly. A material **scheme miss**
  renders black, not absent.
- **Shaders:** DX11 Enhanced base and terrain shaders live in OpenShim (`openshim_enhanced_*`). CR owns the
  selecting materials, texture aliases, static-IBL wrappers and the other `CR_*` shader families. Before
  editing `Materials/CR_BZBase.material`, `Materials/CR_BZTerrainBase.material` or
  `Shaders/CR_static_ibl.program`, read `Docs/ENHANCED_SHADER_OWNERSHIP.md` and run
  `Tools/Test-ProgramReferences.ps1`. On a CR install, grep the deployed `.material` for the program names
  to find which family is actually bound before editing; `OSE_*` edits are inert when CR binds `CR_*`.
- **Ogre materials outlive the mission Lua state.** On mission 2+ of one process, "does the resource
  already exist" early returns skip the side effect the fresh Lua state needs (filling caches). Fill
  caches before the exists-check and log a named skip reason.
- **lcbench smoke before release.** Ogre silently skips a malformed `.particle` script (only symptom:
  `exu.CreateParticleSystem` returns false). Host CI cannot see this. Any new template or runtime
  parameter name needs an in-game smoke: templates load, spawn each, setters work, intensity to zero and
  back, `BZOgreLogfile.log` clean. Ogre ignores wrong parameter names and out-of-range affector indices
  silently; `CRWeather.DescribeSystem(name)` prints what the running build registers. Silence in the
  weather scripts is the healthy result (they only print on failure).
- Atmosphere screenshots need windowed mode, a deployed build, DPI-aware capture and 1920x1080 or larger
  (`exu.CAMERA.NO_HUD` removes the HUD). Tuning passes therefore need the owner's session (5.3).

---

## 5. Testing and validation

### 5.1 Host-side tests

| What | How |
| --- | --- |
| Lua 5.1 runner | `%LOCALAPPDATA%\Programs\Lua51\bin\lua5.1.exe` on the maintainer machine; CI uses apt `lua5.1`. Missions must compile under **stock Lua 5.1** (60-upvalue limit; newly touched files are strictly checked in CI). |
| Python validators | Set `PYTHONUTF8=1` (parity tests fail on cp1252 otherwise). |
| Whole-repo invariants | `python Tools/Validate-CampaignRepository.py` (lock, shared-doc hashes, manifests). |
| Weather | `lua5.1 Tools/Test-CR<Planet>Weather.lua`, `Test-CRWeatherFogHorizon.lua`, `Test-CRWeatherParameters.lua`. |
| Shaders | `Tools/Test-ProgramReferences.ps1`, `Tools/Validate-DX11Shaders.ps1`, `Tools/Test-DX11ShaderValidator.ps1`. |
| Transcripts | `python Tools/Import-GoombaTranscripts.py --check`. |

Per-mission test naming (`Tools/`), run after every change to that mission:

| File | Purpose |
| --- | --- |
| `Test-MisnNN.lua` | The faithful single-player port runs through its phases with a mocked engine. |
| `Test-MisnNNCoop.lua` | Co-op layer: ownership, scaling, triggers, win/loss, peer behaviour. |
| `Test-MisnNNPresentation.lua` | Host vs guest presentation parity (dialogue, markers, objectives, cutscenes). |
| `Test-MisnNNSourceParity.py` | Strips `-- CR ... >>/<<` regions and proves the port equals the DLL source; co-op substitutions are asserted explicitly. |
| `Test-MisnNNCoopContract.py` | Map/listing contract: teams, spawn buoys, labels, `.ini/.des/.vxt`, crcampgn entry. |
| `Test-CoopAuthoredLabels.py`, `Test-SetupMissionShell.py`, `Test-ShippedCutVo.py` | Cross-mission contracts. |

When adding a mission's tests, **wire them into `.github/workflows/campaign-validation.yml`**. Several
suites (misn06-08 at one point, weather suites for a long time) existed but were never run by CI, so a
regression reached `main` green. Test mocks use `x/y/z` position keys (helper `nearTo(h, label, dx, dz)`
in the misn13 suite). A test that never failed is not proof: verify it fails when the fix is disabled.

CI (`campaign-validation.yml`) runs on PRs and pushes to `main`: Validate, port suites, co-op suites,
weather, aiCore, transcripts, strict Lua 5.1 compile of changed files. Branch protection requires an
up-to-date head: merge `origin/main` into the branch, push, wait for CI, then merge.

### 5.2 What host tests cannot see

Native Lua mocks cannot prove: Ogre accepting a script/material, AIPs actually building, replication of
authored objects, `Formation`-style binding quirks, lava damage, DX11 behaviour, and anything involving
the real engine's order of initialization. Mark these as unrun in the mission doc until a live run exists.

### 5.3 Live harness (OpenShim repo)

Owned by OpenShim: dot-source `reverse_engineering/BZRHarness.ps1` (serializes launches machine-wide,
`Stop-BZRGame`). Co-op runners: `reverse_engineering/Run-BZRCoopFour.ps1`, `Run-BZRCoopSuite.ps1`,
`Run-BZRCoopMission.ps1`, per-mission steps in `BZRCoopMission.ps1`, scenarios under
`reverse_engineering/coopflow/` (misn06-09+ cases are in OpenShim PR #465 if not yet merged; check).
Runtime directory is `C:\BZRCoop`. Test instances need `PreLobby=0`; a lobby row map (`KnownMapRows`) must
list the mission.

Operating rules that each cost a run once:

- The owner's **RDP session must be Active** (`query user`). A disconnected or locked session kills the DX11
  device about 100 s in ("hardware adapter did not settle"). `query session` still says `Active` when
  locked; capture one frame and *look at it* before trusting a series. Do not unlock or take over the
  workstation; ask.
- **Drive the game by Lua or logs, not `SendInput`/focus calls.** Default to zero focus steals; any focus or
  scancode input is opt-in and only when the owner says the PC is free. Computer-use approval dialogs
  stall sessions when the owner is away.
- Launch via the harness (WMI, outside the agent's job object). **Never force-kill**
  `battlezone98redux`; stop with `Stop-BZRGame` (prefer `-Id`). A force-kill with a fullscreen D3D device
  can hard-lock the workstation. Use `BZR_FORCE_WINDOWED=1` except for timing comparisons.
- The exe **re-execs**: poll by process *name*, not the launch pid. Mission arg is at most 15 characters and
  must include `.bzn` (`misn13.bzn`).
- `/edit` does not suspend the simulation; an edit-mode launch is a valid smoke.
- Hash-verify deployed binaries before and after a run (another agent may deploy mid-run).
- A run that does not reach its final marker is not a result; re-run it. Suspect an unattended/disconnected
  session first. Launching Windows PowerShell 5.1 from pwsh pollutes `PSModulePath`; run via Bash with the
  variable reset. About 1 in 4 launches once crashed at startup in OpenShim's activation sweep (since
  fixed); retry wrapper before concluding.
- Crash dumps: WER writes full dumps to `C:\BZDumps` with a small rotation; copy gameplay dumps to
  `C:\BZDumps\keep\` immediately. Page heap is unusable on this 32-bit game.
- Give timed runs generous slack; the simulation can stall on focus loss without a crash.
- Steam live runs need `steam_appid.txt` (301650) next to the exe, deleted afterwards. GOG needs nothing.

### 5.4 Smoke-test gotchas specific to CR

- **Command-line launch of a campaign mission runs without CR.** Since `crcampgn.ini` became
  `mapType = "campaign"`, CR is only active when the campaign is picked from the menu. A CLI launch of
  `misn02b.bzn` shows no `mods\3686673790` line, no CR Lua, no `exu.dll`. For a CR runtime smoke use
  `-Mission crsetup.bzn` (instant action, activates CR) or `-MenuStart` (requires a click). Co-op
  `strategy` listings (`mapType multiplayer`) are what the co-op harness launches.
- Loose files dropped into `mods\<name>\` break mission loading (the folder is an asset root); put test
  assets in `addon\<mission>\`. Disabling a mod means moving it out of `mods\`, not renaming.
- `mods\<id>` Lua modules **shadow** `addon\` modules of the same basename (the `mods\` copy always wins);
  a definitions file named `ExtraUtils.lua` once disabled all of ISDF Chronicles' EXU integration. CR's
  LuaLS definitions live in `Docs/lua-definitions/` (authoring only, not shipped). Workshop `require`
  names are limited (sourceless, 11-character truncation).
- `exu` is not a global in mission scope: `local exu = require("exu")`.

---

## 6. Using Codex and other delegated agents

- Use the **Codex CLI**; the Codex MCP connection is flaky.
  ```text
  codex exec -C <worktree> -s workspace-write --add-dir <dir> -o <report> - < prompt.txt
  ```
- Codex's sandbox cannot write a shared worktree's git `index.lock`, so it cannot commit. The
  orchestrating agent reviews the diff and commits.
- Codex sessions can **exit after pushing, before opening the PR**. Read branches and `gh pr list`, not
  the final message.
- Codex has done good native RE (root-causing the co-op scavenger heap bug, a chunk-bridge probe AV).
  Brief it like a peer: goal, ruled-out hypotheses, files, validation commands, evidence labels
  (PROVEN / STRONG INFERENCE / UNKNOWN), and where to write the report. Don't hand it your hypothesis as a
  finding.
- Give every delegated agent the hard rules in section 7 verbatim. Delegated agents stay inside their own
  worktree and own files; the orchestrator owns scope, architecture, final diff review and test runs.
- Heredocs containing apostrophes can break some agent shells: write files with a file-write tool instead.
  Windows PowerShell 5.1 vs pwsh 7 differences matter (BOM, `System.Drawing`, `-replace` is
  case-insensitive, variable names are case-insensitive); prefer pwsh 7 for repo tooling.

---

## 7. Hard rules (never do)

1. **Never edit `Docs/BZR_LUA_AGENT_REFERENCE.md` or `Docs/BZR_PLATFORM_COMPATIBILITY.md`** in CR alone.
   They are byte-identical across CR, OpenShim, EXU and bzfile and hash-pinned (`SHARED_BZR_DOCS` in
   `Tools/Validate-CampaignRepository.py`; each sibling pins them too). Changing one requires changing all
   four plus every pin in one workstream.
2. **Never run `Manage-CampaignFiles.ps1 -deploy`** (or `-fromsource`/`-release`/no-arg) unless the
   owner asks in-session, and never touch `Bin/`. `-deploy` overwrites repo `Bin/` natives from whichever
   branch each sibling build output is on, self-elevates and returns no stdout/exit code. If the owner asks
   for a deploy: point `BZR_OPENSHIM_REPO`/`BZR_EXU_REPO`/`BZR_BZFILE_REPO` at the intended builds, then
   always follow with `-verify` (pipe its long MISSING list through `Select-Object -First 12`).
   `Bin/` is a cache of sibling build outputs, not a source.
3. **Never re-sort `Shipping/shipping.lock.json`**; keep it LF; see 3.8.
4. **No merges, releases/tags, Workshop uploads or other public publication without explicit owner
   instruction** (a per-batch "merge as you go" granted in the current session counts, and only for that
   scope). When merging: CI green, mergeable, `gh pr merge --merge`.
5. **Workshop publishing is a local maintainer operation** through `Manage-CampaignFiles.ps1`
   (`-workshop-init`, `-workshop-auth`, `-workshop-build "<note>"` dry run, `-workshop-upload "<note>"`),
   not CI; follow `Docs/STEAM_PUBLISH_CHECKLIST.md` and its OpenShim Roadmap sync. Publishing stages the
   **working tree**, not HEAD, so a dirty tree is a blocker. Publishing silently reverts the Steam
   description unless `workshop.config.json` is set to leave it alone (`PublishDescription` stays false;
   the description is hand-edited and capped at 8000 characters). Exit code 0 is not proof of an upload;
   confirm the "Uploading app 301650 item ..." line. Never hand-copy files into `Local\Workshop\content`;
   `Scripts/OpenShimManifest.lua` hashes must come from staging. Publication needs a tagged OpenShim
   release, never a branch.
6. **Never copy source into Steam's Workshop cache** or treat `Local\Workshop`/installed copies as source.
7. **Never commit** secrets, crash dumps, logs, scratch RE artifacts, decompiler output, PDB-derived data,
   game binaries, player saves, or anything from the private sources in 2.1.
8. Never blanket-stage, clean, restore or overwrite unrelated work; stage only task-owned files. No
   force-push or history rewrite unless explicitly requested (a force-push does not purge GitHub's cached
   blobs anyway).
9. Don't touch another agent's branch/worktree/files. Concurrent workstreams are the norm.
10. **Never force-kill the game**, never steal focus by default, never unlock or take over the owner's
    workstation (5.3).
11. Never revive deleted designs flagged as such (for example OpenShim's old clean-room map filter port).
12. **Co-op invariants:** Pilot Mode off in MP; `aiCore` never on human teams; no unfiltered team-wide
    sweeps; no pop-in within 400 m; `SetAIControl` only at chunk root.

---

## 8. Lessons and pitfalls

Each bullet: the pitfall, the one-line why, and where to read more.

### 8.1 Build, lock and publishing

- Staging includes whatever is in the working tree. *Why:* an upload once shipped in-flight shaders. See
  `Docs/STEAM_PUBLISH_CHECKLIST.md`.
- A file missing from the lock is silently excluded and surfaces as "missing required file". *Why:* the
  validator's required list is independent of the lock. Fix with `-bless`, never by hand-editing.
- The manager's dispatch falls through to an interactive menu for unrecognized args, so a typo once exited
  0 with nothing uploaded (now exits 2 and lists received args). Check output, not exit codes.
- Publishing the description reverts hand edits made on Steam; SteamCMD's VDF cannot hold a literal double
  quote (the publisher rewrites `"` to `'`). Snapshot the live text first
  (`Docs/workshop_description.published-*.bbcode`).
- `Docs/STEAM_WORKSHOP_RUNNER.md` describes a two-runner design that has never run; the README and
  checklist are the current path (`Docs/LEVEL1_RELEASE_PIPELINE.md` for release packaging).
- Zero-byte or stand-in files used to unblock a bless must be removed again (3.8).
- Always run `-verify` after any asset deletion or deploy; its four count lines are the check.

### 8.2 Engine and Lua behaviour

- `SetAIControl` inside `Start()` crashes the host; chunk root only (3.5).
- `Formation(unit, leader)` errors in stock Lua; use `SetCommand(..., AiCommand.FORMATION, ...)`.
- A Lua error in MP can close the host; every error is fatal in co-op.
- The Lua state is rebuilt each mission, but Ogre materials and the process are not (section 4).
- Native `AudioMessage` queues; `subtit.Play` clears subtitles; `Play` first then `Queue` (3.3).
- `CRCoop`-style admission handshakes can race `Initialize` (see the 2026-10-09 doc).
- `SetPerceivedTeam` works in MP [owner-confirmed]. `EjectPilot` returns nothing: capture the pilot via
  `AddObject`/`ObjectsInRange`. `SetAIP` needs the team argument.
- `Formation`, `AllCraft` and handle semantics: when a Lua API surprises you, read
  `Docs/BZR_LUA_AGENT_REFERENCE.md` and the 1.5 decompile before guessing.
- Lava damage is real in Redux (`Lava=1` in `[NormalView]` of the `.trn`, TextureType based): about
  159 hp/s on molten tiles. The stock misn11 `.trn` had no lava key; a 2-tile crust moat is needed because
  sulphur is the walkable continent.
- `GetCameraPosition`-style and `IsInfo` calls are local; don't branch gameplay on them.

### 8.3 Source fidelity

- The BZ2 DLL source is a good *structure* reference but the shipped 1.5 exe may differ (misn14 misses
  pow1/pow55 team flips, `SetIndependence(guy, 0)` on pilots and `SetAIP(..., 2)` unless you check the
  decompile). Check both.
- GoombaBZ "Unused voiceover" labels are often wrong (`misn1303` plays on victory). Trace each wav through
  the script before restoring it.
- The 1.5 BZN is sometimes a **mid-play snapshot** (misn13: 133 unnamed runtime paths, pre-issued
  commands, duplicate labels); strip it. `edge_path` is the play boundary, not cut content.
- Don't trust 1.5 exe string scans (they omit most real ODF keys); the decompile and the data files are
  the ground truth. Leaked-PDB names are hints, never proof.
- Redux has no ODF class inheritance (parent is a descriptor; basename is the mesh), and renamed ODF
  sections can crash (null payload faults on frame 1). Custom ODFs need `aiName`.
- Hardpoints live in the skeleton, not the ODF; cockpit is a sibling node; pilot aim lives in the node.

### 8.4 Rendering and weather

- Edit the shader family the material actually binds (`CR_*` vs `OSE_*`); presence in the microcode cache
  proves nothing.
- Hash generated shader program names or Ogre's microcode cache serves stale code.
- Particle and material problems fail silently in Ogre (section 4); the lcbench smoke is the gate.
- Black pools on terrain came from N.V-gated diffuse in CR's PBR; view-gain swim was not the cause.
- DX11 context vtable reverts mid-frame, so per-frame checks lose draws; and an exit crash came from an
  unpinned `d3d11` module. These are OpenShim-owned; report rather than patch in CR.
- Redux's HUD is authored for a 1440x1080 design space; small overlays may draw nothing; plates eat clicks.
- Terrain `.trn` map names are atlas keys: absent keys draw the default. Some keys are parsed but dead
  (`Backdrop*`).
- A TextureType label is not a place. Titan's `TextureType0 // Methane Ocean` covers 95 % of misn14; the
  liquid is type 0 **on the flat sea floor** (height 5.0), found by combining `.mat` and `.hg2`
  (`Tools/Build-TitanSites.py`). Check the type's coverage before keying an effect to it.
- Environment used to send every Titan map down the `earth` preset (only moon hints existed). Detection
  now checks palette / atlas / sky; `Environment.LockDaylight` holds a world at day (Titan sets it).
- Terrain roughness is floored at 0.56 in the Enhanced terrain shader (OpenShim), so no CR material or
  spec-map change can make a reflective liquid; that needs an OpenShim shader term (`Docs/TITAN_WEATHER.md`).

### 8.5 Live testing

- Disconnected/locked session kills the device; locked captures return the lock screen but logs still
  look healthy; do not draw rendering or FPS conclusions from them.
- A test that never engaged looks like a null result: count what each arm suppressed before concluding.
- A fixture ODF without `aiName`, a game launched inside the agent's job object, a loose `mods\` folder, a
  stale `patches.json` copy, or a renamed-parked mod each produces "nothing happened". Check the install
  state (BZLogger "MOD FOUND" lines) before debugging code.
- Keep the GOG install current after test runs; the real `patches.json` must go back.
- Dot-sourcing `BZRHarness.ps1` already takes the machine-wide launch lock, so a runner can sit silent for
  many minutes behind another agent's run: that is queueing, not a hang. Launch Windows PowerShell 5.1
  from Git Bash with `< /dev/null` (it otherwise stalls on stdin) and `env -u PSModulePath`.
- To capture a stock campaign map with CR active, use a scratch instance (`C:\BZRCoop\<name>`, the
  `New-BZRCoopInstance` layout) with a temporary `instant_action` listing that copies the stock `.bzn` and
  terrain under a short new basename; never add such files to the GOG install. Convert the `.bzn` to text and set
  both `msn_filename` and `[AiMission] name = LuaMission`: with the stock `MisnNNMission` name the native
  mission logic runs and the Lua never does. Goldberg instances find the mod only through
  `steam_settings\mods\<id>` (a junction to the instance mod folder).
- `GetPosition` returns a `VECTOR_3D` userdata. A `type(p) == "table"` check silently discards every position
  (it hid all position-driven Titan effects until the first live run); mock positions as userdata in tests.
- A match on bytes proves an address, not identity: byte match plus semantic corroboration, always.

### 8.6 Process

- Label confidence: "confirmed", "inferred", "unknown". Don't assert a hypothesis as a finding.
- Lead reports with the outcome, then the evidence.
- Read the ground-truth docs before experimenting; diff against the working sibling path first (one grep
  beat nine launches).
- Run the narrowest checks while iterating; broad validation at a stable checkpoint; the release checklist
  only for a release candidate.
- Exploratory visual work: build the smallest deployable prototype and wait for the owner's acceptance
  before production hardening.

---

## 9. Decision log pointers and active work

Per-mission owner decisions live in the mission docs (read their "owner decision" sections before
changing behaviour). Highlights:

| Mission | Where | Owner decisions in brief |
| --- | --- | --- |
| misn07 "Behind Enemy Lines" | `Docs/MISN07_COOP.md` | Alarm is per-player (any trip alarms all); full test-range arc restored behind a flag; rendezvous allies spawned on team 7 then switched to team 1; Razor One glides over the outpost wall, steals a Soviet vehicle, and has leader-only regeneration. |
| misn08 "A Nasty Surprise" | `Docs/MISN08_COOP.md` | Colorado starts allied (team 7) with a Lua-built base; the massacre is witnessable; CCA builds walkers until its base dies; heal sentinel bug fixed. |
| misn09 "Wrangling the Fleeing Herd" | `Docs/MISN09_COOP.md` | Host-only base; convoy scales per human; Prescott platoon (5 avtank) arrives behind the convoy and can win; the launch pad must never be attacked (standoff 150 m); geyser-clear win dropped. |
| misn10 "The Race is On" | `Docs/MISN10_COOP.md` | Scrap and hunter scaling per extra human; tug rebuild 30 s x2; plan-B AIP; quake on first relic pickup; no intro. |
| misn11 "Bring it Home" | `Docs/MISN11_COOP.md` | Idle units become hostile ambushes; betrayal backup squad; lava tiles fill the central area (`Tools/Build-Misn11Lava.py`, escort loop is the only dry route east). |
| misn12 "Flying Solo" | `Docs/MISN12_COOP.md` | **Stealth**: cover blown by anyone fails everyone; one key ship per human; cockpit timer and nav cams synced; win = all humans at nav1; Razor One appears only when hunters catch up (separate PR). |
| misn13 "Total Destruction" | `Docs/MISN13_COOP.md` | Win = factory + hangar + all 4 silos; waves 2-4 restored with no pop-in; AIP only (no aiCore); shared Europa director. |
| misn14 "The Three Beacons" | branch `agent/misn14-fury-rework` | **Concept C**: players control the Furies, lose control, rogue Furies hit NSDF and CCA; surrender is the consequence. Restore the pow1/pow55 flip and `SetIndependence(guy, 0)`; shared host-triggered activation scene (1402/1423-1425, 1426/1427/1420); recycler named "Texas"; teams CCA 5 / Furies 6 / survivors+base 7; +1 Fury per extra human, cap 12; `hvsat` from wave 4; `crcampgn` `[MISSION13]` voice `misn1422.wav`, planet titan; `hvsav` is not commandable, `hvsat` is. |
| Early missions (02b-05) | `Docs/MISN02B_COOP.md` ... `MISN05_COOP.md`, `Docs/EARLY_MISSION_SOURCE_AUDIT.md` | aiCore audit decisions: misn02b native AIP, misn05 aiCore Lua brain, aiCore never manages humans, DepotManager kept (it services all units in range at once). |

Where active work lives (stale quickly; refresh with `gh pr list --state open` and
`git branch -r --sort=-committerdate`): as of 2026-10-14 open or recent branches include
`agent/misn12-razor-chase`, `agent/misn14-fury-rework`, `agent/venus-fogbank`, `agent/moon-weather`,
`agent/titan-weather`, and the livewire trailer pass `agent/livewire-trailer-shots`. The Moon and Titan
directors have no doc on `main` yet; their design notes arrive with their PRs. Do not touch those
branches' files from an unrelated workstream.

Open decisions/ideas recorded elsewhere: NSDF Pilot Mode should follow the Z64Tools per-mission Pilot
branches (offline only); the one-shot "Unable to set D3D11 vertex declaration" exceptions are uninvestigated;
`Scripts/Weather.lua` is a dead predecessor of CRWeather with no requirer (candidate for deletion in its
own change).

---

## 10. Keeping this document current

- Append lessons **in the same PR as the change that taught them**. A lesson that lives only in a chat or
  a private note is lost when the session ends.
- Put per-mission detail in the mission doc, subsystem detail in its own doc, and link it from here; this
  file indexes, it does not duplicate.
- When a pitfall is fixed upstream (OpenShim/EXU), edit its bullet to say so rather than deleting the
  history; the symptom signature is the valuable part.
- Mark facts as confirmed, inferred or unknown; date anything that can go stale.
- If you change a hash-pinned shared doc (you shouldn't, section 7) update all four repos' pins instead.
- Keep it skimmable: tables for maps, one-line bullets for pitfalls, no code dumps, no decompiler or
  PDB-derived content, no secrets, no machine-specific credentials.
- Add a pointer here from any new doc that agents must read before touching a subsystem.
