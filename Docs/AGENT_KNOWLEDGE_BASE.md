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
| Campaign missions, Lua consumers, assets, materials, packaging, Workshop publishing | **CR** (this repo) | Canonical checkout `%USERPROFILE%\Documents\GIT\Campaign-Reimagined` (stays on `main`) plus per-workstream worktrees (see below). The Google Drive tree is legacy; never edit or reverse-sync it. |
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
- **Worktree rule [owner].** The canonical checkout (`%USERPROFILE%\Documents\GIT\Campaign-Reimagined`)
  stays on `main` and is never used for feature work. Per-workstream worktrees are allowed: one per branch,
  at `%USERPROFILE%\Documents\GIT\Campaign-Reimagined-<topic>`, created from the canonical checkout with
  `git worktree add`. No other clones or copies.
- **Cleanup belongs to the creator.** The agent that creates a worktree removes it: once its PR is merged
  or closed, or the work is abandoned, run `git worktree remove` (from the canonical checkout) and
  `git worktree prune`, and delete the merged local branch. Never leave stray worktrees behind. Before
  ending a session, run `git worktree list` and remove your own finished ones.
- **Never touch another agent's active worktree.** A worktree is safe to prune only when its branch is
  merged into `origin/main`, it has no uncommitted or untracked changes, and no agent is still using it.
  The ignored `Local/Workshop` staging inside a worktree is regenerable, so it does not block removal.
- Audit recipe (read-only; the second command lists candidates, it removes nothing):
  `git worktree list; git branch --merged origin/main; git -C <worktree> status --short`
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
| Original guide / cut VO audit | `Docs/ORIGINAL_GUIDE_LORE_AND_CUT_CONTENT_20261016.md` | 1998 strategy-guide Cthonian/Tartarus/Titan lore, Achilles crystal-sabotage evidence, Titan-to-Achilles transition, unused-recordings restoration backlog. | Separate published guide narrative, recorded audio, archived source, CR implementation and inference. The owner's full guide OCR is **not** committed to this public repo. |
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
   (<= 300 bytes, CRLF, and it must be allowlisted in `.gitignore`), `Missions/misnNN.vxt`
   (approved roster: `Docs/COOP_STARTING_UNITS.md`),
   `Assets/Graphics/misnNN.bmp` (generic shared image), and the `[MISSIONk]` entry in
   `Config/crcampgn.ini` (3.7).
6. **Tests and lock.** Add the tests (section 5), update `Tools/Test-SetupMissionShell.py`'s campaign list,
   `crcampgn.des` range text, README scope lines and `CHANGELOG.md`, then bless the lock (3.8).
7. **Docs.** `Docs/MISNNN_COOP.md`: map, ownership, team table, owner decisions, restored content,
   inferences, and a live-harness checklist. Label unrun checks as unrun.
8. **Live check** with the harness (section 5.3) when the owner's session is available; update the doc.

Starting ships follow the player-controlled production menus, not the support team's factory.
The approved progression and the no-production mission exceptions are in
`Docs/COOP_STARTING_UNITS.md` [owner]. `baseName` selects assets, not ODF inheritance: inspect
the actual mission factory's `buildItem` entries (07 `avmu7`, 08 `avmu8`, 09+ `avmuf`).

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
- Parity-safe human triggers (misn18): when the faithful body is full of `Distance(M.player, ...)`, shadow
  `GetPlayerHandle` with a token and reassign the body's local `Distance` from a CR region; the wrapper answers
  the nearest human for approach triggers and the farthest for recycler gates, so no body line changes. Camera
  shots about the player's own ship ("left behind") stream only a height and each peer films its own ship.
  Check which of a mission's wavs ship in every Redux language archive before adding one to `Assets/Audio`
  (misn1817/1818 do, misn1803 does not). `Docs/MISN18_COOP.md` is the template for storm-style optional hooks.

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

Full detail: `Docs/WEATHER_ENVIRONMENT_OWNERSHIP.md`; full mission/stack audit and the 2026-10-15 owner
revision: `Docs/ATMOSPHERE_AUDIT_20261015.md`. Environment caps the final composed fog to TRN visibility,
including base/Clear/local overrides. It is the only atmosphere writer while loaded.

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
  into a weather-only commit. The owner explicitly authorized the final/base cap
  and subtle Moon/Venus integration on 2026-10-15; see `ATMOSPHERE_AUDIT_20261015.md`.
- **Shared weather sensors** [owner, 2026-10-15]: every weather-enabled campaign mission now applies
  sensor effects through Environment, including Moon dust/glow, Io, Europa, Titan and Mars 06.
  See `Docs/WEATHER_SENSOR_POLICY.md`; this supersedes the old visual-only mission exceptions.
  Directors stay render-only when used alone; missions bind activity to the sensor service.
  Damage/handling changes are separate; Venus lightning retains its approved knockback/scramble.
- **Seeded and peer-identical.** The leader decides; every peer renders from the same seed and shared
  events (`VenusFog`, `IoQuake`, `MoonGlow`, ...). Weather events must be routed to guests; a director
  that only runs on the host will desynchronize visuals.
- **DX11 Enhanced caveat:** fog range scales terrain diffuse IBL. Raising global fog greys the sky and
  terrain. Where the owner wants subtle effects (Moon), keep global fog near off and use particle ground
  mist instead. Do not "fix" mood with global fog.
- **Moon 02b/03 now explicitly load Environment in subtle/native-baseline mode** [owner, 2026-10-15]:
  retain their 175-250 black fog and use bounded lighting variation, with no full night or sensor penalty.
  Do not replace this with the default full-cycle moon profile. Titan 14 now loads Environment with
  its native baseline and daylight lock; CRWeather contributes through the shared writer.
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
- `BZLogger.txt` flushes late: a capture triggered by a log line can catch the next camera. Hold each fixture
  view about 6 s after its `SHOT` line before moving the camera.
- Steam live runs need `steam_appid.txt` (301650) next to the exe, deleted afterwards. GOG needs nothing.

The full local-server and 2-4 client recipe is in 5.5.

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

### 5.5 Local server and multi-player co-op testing

Everything here was read from the sources named in each item (checked 2026-10-14 against OpenShim
`origin/main` 9133a9c2f and DedicatedServer `origin/main` c996e21). Claims I could not confirm are marked
**[inferred]** or **[unverified]**. No live run was made while writing this section. Co-op cannot be tested
by a command-line mission launch: it needs a lobby server, so every recipe below runs a server.

#### Server options

| Option | What it is | Where it is documented |
|---|---|---|
| **Private loopback server (the default for agents)** | `Battlezone98Redux_DedicatedServer` (Python, `server.py`) started by the harness bound to `127.0.0.1`: TCP 1337 lobby, UDP 1338 handshake, UDP 1339 relay, TCP 8080 health. State goes to the run folder. Nothing leaves the PC. | OpenShim `reverse_engineering/Run-BZRCoopMission.ps1` (server args near the "Starts a private ... server" step), `coopflow/README.md` |
| **Manual local/LAN server** | `python server.py --state-file C:\BZRCoop\server\state.json`, or `ServerGUI.bat` (`server_gui.py`). Listens on every interface; 8080 stays loopback-only. Players point at it with the launch option `/bzrserver=ws://<lan-ip>:1337/` or OpenShim `net.ini` `[OpenShimSocket] MatchmakingRedirectAddress=<lan-ip>` (IP only). Needs the Private network profile and an inbound firewall rule for TCP 1337 and UDP 1338-1339. Tailscale is the documented no-port-forward option for remote players. | DedicatedServer `docs/LAN_COOP.md`, `README.md` (access modes, Docker/Compose) |
| **Remote box** | I found no remote machine documented as a co-op test server. The remote host in the private notes is the BZ1 Game Watcher production host (reachable over the tailnet and WinRM); it runs Game Watcher, not a BZRNet test lobby. Internet/WAN co-op is "untested" in `LAN_COOP.md`, and real multi-PC sessions are listed as unqualified in OpenShim's `Docs/ROADMAP_CODE_VALIDATION_20261007.md` (row 125). Credentials, host names and the DPAPI store: **see the private memory/secret store**, never this repo. | private memory (`stuartserver-is-reachable-over-winrm`, `bz1-gamewatcher-production-operations`) |
| **Official Rebellion lobby** | Never for CR co-op tests. The session script refuses it unless `-Matchmaking official -AllowOfficialServer` are both passed, because test identities would reach the public lobby. | `BZRCoopSession.ps1` header comments and `Start-BZRCoopClients` |

Server prerequisites for 3-4 clients: `--relay-pair-ports` (a distinct loopback UDP port per peer pair; the
runner adds it automatically when `-Clients` is greater than 2) and a DedicatedServer checkout that contains
`native_network_health.py`. A second harness, a leftover server, or another process on ports 1337-1339 or
8080 makes the runner refuse to start (it checks the ports first).

#### Launching 2-4 clients on one machine

Use the OpenShim harness, from the OpenShim repo root in **Windows PowerShell 5.1** (from Git Bash use
`env -u PSModulePath`; see 5.3). Runtime root is `C:\BZRCoop`.

- **One command.** `reverse_engineering\Run-BZRCoopMission.ps1 -Mission misn03 -Scenario win [-Clients 2|3|4]
  [-CampaignContent <staged CR content>] [-ContentOverride <folder>] [-KeepRunning]`. It stages CR into
  `C:\BZRCoop\stage\3686673790`, starts the loopback server, prepares instances, launches the clients,
  walks the lobby, runs the scenario, checks logs, writes `flow-summary.md`, and stops everything. Exit code
  0 is PASS. Evidence: `C:\BZRCoop\runs\<run>\`.
- **Manual lifecycle.** `reverse_engineering\BZRCoopSession.ps1 -Action Prepare|Launch|Stop|Status -Clients N
  -CampaignStage <dir>` does just the instances. `Launch` first checks `http://127.0.0.1:8080/health`, so the
  server must already be running. It starts clients one at a time (`-LaunchDelaySeconds`, default 30) and
  holds the launch lock for as long as it runs.
- **Instances.** Each client is `C:\BZRCoop\instances\Instance<N>\Battlezone 98 Redux`: a copy of the GOG
  install's exe, DLLs and small configs, junctions to the large read-only asset trees, its own `logs\`,
  `save\`, `mods\`, a Goldberg `steam_api.dll` with a per-instance name (`BZRCoop1`..) and Steam id, and an
  `openshim.ini` with `RawMouseInput = 0`. Instances are disposable; regenerate them instead of editing them.
  The harness needs Goldberg's DLL at `C:\BZRCoop\tools\NucleusCoop\utils\GoldbergEmu\steam_api.dll` and
  `C:\BZRCoop\tools\steam_interfaces.txt` (present on the maintainer's machine; **[unverified]** for any
  other machine).
- **Matchmaking redirect.** The coordinator sets `OPENSHIM_MATCHMAKING_ADDRESS=127.0.0.1`, launches with
  `CreateProcess` (environment inherited), and then checks every client's log: a redirect other than
  `127.0.0.1`, an official-server contact, or no redirect line within 15 s stops that client and fails the
  run. For any other launcher, put the redirect in each instance's **`net.ini`**, not the environment (see
  gotchas).
- **Ports.** Loopback only: 1337/tcp, 1338/udp, 1339/udp, 8080/tcp, plus ephemeral per-pair UDP relay
  ports for 3-4 clients. These do not qualify any firewall or WAN setup.
- **Windowed, quiet, serialized.** `BZR_FORCE_WINDOWED=1` is set for every launch (never fullscreen: a
  force-killed fullscreen D3D device can lock the workstation). `BZRHarness.ps1` defaults
  `OPENSHIM_NEVER_ACTIVATE=1` and `OPENSHIM_NEVER_CAPTURE_MOUSE=1`, takes the machine-wide launch mutex
  (`Local\BZROpenShimGameLaunch`), and refuses to launch when a game is already running. Do not dot-source
  `BZRHarness.ps1` from a scenario: the coordinator already holds the lock and the scenario would block.
- **Stopping.** `Stop-BZRGame -Id <pid> -NoForce` (WM_CLOSE). Never force-kill.
- **Several machines.** The harness is single-PC and loopback-only. A second physical PC is the manual LAN
  recipe in `LAN_COOP.md`: the same CR build in `mods\3686673790` on every PC, every PC pointed at the
  server's LAN address. **[inferred]** An agent can drive the first PC with the harness only if the others
  are driven by hand; no multi-PC automation exists.

#### Loading a CR co-op listing

A CR co-op mission is a `strategy` listing (`Config/misnNN.ini`, `mapType = "multiplayer"`, `gameType = "S"`,
2-4 players) shipped in the CR mod folder. The harness copies the staged CR into each instance's
`mods\3686673790`, so the listing appears in Multiplayer > Internet > Create Game on the host. Then
`BZRCoopLobby.ps1` has the host create the game, click the map row, raise the native Player Limit to the
client count (the shell keeps 2 otherwise), enable Sync Join, join each guest, and launch.

- Staged content comes from `-CampaignContent`. Its default (`...\GIT\CR-release\Local\Workshop\content`)
  does not exist on this machine; pass a staged tree explicitly, for example the canonical checkout's
  `Local\Workshop\content` **[inferred]**, or build an override of uncommitted work with
  `New-CRFlowOverride.ps1` and pass it as `-ContentOverride`.
- The host's map row is a pixel position in the 1280x720 shell. `Run-BZRCoopMission.ps1` knows
  `misn05=128, misn03=147, misn02b=159, misn04=171` (`$KnownMapRows`); any other mission, such as the misn06
  to misn13 listings, needs `-MapListY <row>` (the lobby script also scans rows 88-230 and confirms the pick
  through the server's `gameSettings`). Test instances need `PreLobby=0`.
- Hash-check the staged `mods\3686673790` and the deployed OpenShim/EXU DLLs before and after (see 5.3).

#### Driving the clients by Lua

Never by focus or `SendInput` unless the owner says the PC is free. The scenario runner and
`BZRCoopPlay.ps1` talk to `CRFlowProbe.lua`, which the harness installs into each client's mission.

- Hands-on: `Run-BZRCoopMission.ps1 -Mission <m> -Scenario play` loads the mission and leaves it running;
  then, one action per call, `BZRCoopPlay.ps1 -Lua '<chunk>' [-Client 0|1|both]`, `-State`, `-Events`,
  `-Shot`, `-Key`, `-Click`, `-Status`, and finally `-Stop`. `-Mission <m> -Scenario <s> -Attach` runs a
  scenario against that live session. Attach right after load: an idle misn03 is lost at about 77 s.
- Scenarios live in `reverse_engineering/coopflow/scenarios/` (`<mission>-<name>.ps1`, else `<name>.ps1`);
  step helpers are `Invoke-CRFlowStep`, `Invoke-CRFlow`, `Wait-CRFlow`, `Wait-CRFlowOp`, `Wait-CRFlowEvent`.
  Probe helpers in Lua include `role()`, `players()`, `tp`, `put`, `kill`, `killTeam`, `heal`, `ff`.
  CR ships its own scenario, `Tools/Test-CoopCommsLive.ps1` (use it with `-ContentOverride` and a fresh
  `exu.dll`).
- Client 0 is the host (player 1, team 1, authority); the others are guests. A client may only move, damage
  or remove objects it owns; the host owns mission AI. Never write the guest's `M` state: the guest must
  reach it through CR's replication. A guest's plain `BuildObject` stays local; use `exu.BuildSyncObject` on
  the owner for multi-owner tests. Keep `Send()` strings under 128 bytes.
- `BZRCoopPlay.ps1` addresses clients 0 and 1 only (`-Client 0|1|both`); **[inferred]** for clients 2 and 3
  use a scenario (`Invoke-CRFlow <client> '<lua>'`) as the four-client scenarios do.

#### What to assert

- **No Lua error alert on any client.** A Lua error in a network game can close the host (3.4). The
  PR #465 live check of misn03 showed the alert as `Lua script Update error:` in the host's `BZLogger.txt`.
  Assert: no such line on any client, no `Ogre Rendering Exception Seen` line, every client process still
  alive afterwards, and no kick or `ping failure` lines on the host. The runner's end-of-run Lua-error scan
  covers the first part.
- **Host departure.** The `host-leaves` scenario closes the host with WM_CLOSE: each guest must see
  `role().leaderDeparted`, call `FailMission` exactly once, and stay running. Register the pid in
  `$script:CRFlowExpectedExit` before closing a client on purpose.
- **Peer-identical weather.** The harness has no generic weather-parity check **[inferred from a search of
  the scenarios]**. The misn05 win scenario waits for the shared severe-weather cue and queries
  `require("CRMarsWeather").GetTargetLevel() >= 4` on every guest. For other missions, read the same
  weather module's state through `-Lua` on every client and compare it with the host's, and confirm the
  event reached the guests (weather events must be routed to them, 3.6).
- **Guest objectives and results.** Use `Wait-CRFlowOp <guest> AddObjective '<file>.otf'` (and the other
  replicated presentation ops) and `Test-CRFlowResultParity`. The runner adds presentation-stream parity
  between the host and every guest, requires exactly one result per client, and fails on a duplicate result,
  script error, wrong directional alliance or wrong craft owner. Four-client runs also gate on
  `native-network-health.json` (a diagnostic heuristic, not measured zero loss).

#### Known gotchas

- **RDP must be Active and unlocked** (`query user`); `query session` says Active even when locked.
  Capture one frame and look at it. A disconnected session kills the DX11 device about 100 s in and can
  stop a client's shell rendering. Do not unlock or take over the workstation; ask.
- **WMI launches lose the redirect.** A game started with `Win32_Process.Create` does not inherit
  `OPENSHIM_MATCHMAKING_ADDRESS`, so Goldberg test clients reach the official lobby (this happened on
  2026-10-10). The shipped session script is safe because it uses `CreateProcess` plus the log guard. Any
  hand-rolled WMI launcher must write `MatchmakingRedirectAddress = 127.0.0.1` under `[OpenShimSocket]` in
  each instance's `net.ini` (the same key in `openshim.ini` is ignored), read it back, and stop the client
  at once if the first `relay_logging: ... matchmakingRedirect=` line in `openshim.log` shows anything else.
- **Focus.** A minimized Redux still owns the foreground, and test clients once stole the mouse. Keep to
  posted messages (`WM_ACTIVATE` is sent before clicks); `-Focused` input is opt-in. PR #423
  (`UnfocusedMouseRelease`) treats a minimized or background Redux as unfocused. The simulation can also
  stall on focus loss with no crash; a run that never reaches its final marker is not a result.
- **MP-gated OpenShim fixes.** Five `[Fixes]` stand down in a network game (ApcAlliedTargetDeploy,
  SplinterUndead, HowitzerUndeployedRetaliation, TugCargoPostLoad, ConstructorRemoteBuild). A co-op run
  therefore does not exercise them, and their absence there is expected. Test those in single-player.
- **Audio.** Clients need an audio endpoint, or voice-overs complete instantly and films gated on audio end
  on frame 1 (the run summary warns "audio available"). `-MuteClients` keeps tests quiet.
- **Key delivery.** In network games the mission `GameKey` callback sees only some keys; the raw key state
  sees all of them.
- **Co-op map rule.** Never name a path `player_path` in a co-op map (online it spawns a team-0 ship).
- **Shared-machine hazards.** Another agent may hold the launch lock, the ports or `C:\BZRCoop`; an
  independent game once ran under `C:\BZRCoop\sx` and blocked a suite. Wait; do not kill other games.
- A stale `patches.json` copy or a DLL deployed by another agent mid-run produces "nothing happened".
  Hash-verify.

#### Cleanup checklist

1. Stop each client with `Stop-BZRGame -Id <pid> -NoForce`, or `BZRCoopPlay.ps1 -Stop` for a play session,
   or `BZRCoopSession.ps1 -Action Stop`. Confirm `Get-Process battlezone98redux` is empty.
2. Stop the loopback server (the runner does it unless `-KeepRunning`); confirm 1337/1338/1339/8080 are free.
3. Confirm the launch lock is released and `C:\BZRCoop\session.json` / `play.json` describe no live pids.
4. Copy anything worth keeping out of `C:\BZRCoop\runs\<run>` and `C:\BZDumps` (to `C:\BZDumps\keep\`),
   and record the run name in the PR or doc. Never commit run output, dumps or screenshots.
5. Leave the GOG install current: restore any file you swapped (the real `patches.json` must go back) and
   delete a `steam_appid.txt` you added for Steam runs.
6. Remove disposable overrides and instances you no longer need; never leave loose test files in `mods\`.
7. Remove your own worktree and branch once the PR merges (section 1, "Branches and worktrees").

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

- **Confirmed 2026-10-15:** Ogre Panel/BorderPanel geometry supplies POSITION and TEXCOORD0,
  not COLOR0. Binding `CR_UI_vertexHLSL4` caused the repeated co-op DX11 vertex-declaration
  exceptions; `CR_UI` now selects the dedicated panel shader on DX11 and keeps its older
  backend fallback. `Tools/Test-OverlayPanelInputs.ps1 -VerifyRegression` reflects the
  actual material-selected shader and rejects the old COLOR0 input requirement.
- A subtitle BorderPanel always queues its border. Missions without `PersistentConfig`
  cannot resolve a palette material, so leaving its border unbound draws Ogre's shaderless
  default on DX11. `ScriptSubtitles` binds `CR_UI` as the explicit fallback before showing
  it; `Test-SubtitleReplacement.lua` covers this standalone path. A responsive Lua probe
  does not prove the renderer is presenting frames.
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
  spec-map change can make terrain itself reflective. A flat liquid can still be done in CR: a render-only
  sheet through `exu.CreateStaticGeometry` with a CR shader (Titan's methane, `Docs/TITAN_WEATHER.md`
  section 5). Sloped or multi-level wetness still needs the OpenShim terrain term.
- **Porting an ISDFC surface kind into CR** (2026-10-14, methane from `isdfc_surface.hlsl` WATER): give the
  program and material CR names and a mod-unique file name (assets ship flat); keep POSITION/NORMAL/TEXCOORD0
  inputs; add a `scheme glow` technique that draws nothing (otherwise the default technique feeds the glow
  pass) and a last technique that draws nothing for backends without a delegate (an unsupported material
  falls back to the default white material [inferred, not seen live]); compile every delegate with fxc
  and check params against the kept constants (`Tools/Test-MethaneShader.ps1`); gate creation on
  `exu.MaterialExists`.
- Pass colours make cheap Lua-driven shader controls (`exu.SetMaterialPassColors` -> `surface_diffuse_colour`
  / `surface_specular_colour`), but Ogre's `derived_light_*_colour` autos multiply by them: read
  `light_*_colour_power_scaled_array` instead (a control vector of `0 1 1` turned a glint pure red live).
- `Tools/Validate-DX11Shaders.ps1` confines radial-fog symbols to the two Enhanced world shaders, comments
  included; other CR shaders use the stock clip-depth fog.
- misn14 (no Environment) lights from the stock sun, almost overhead (`GetSunDirection` -0.17 -0.98 0);
  `exu.GetSunDirection` / Environment's `DaySunDirection` are Ogre space, z mirrored from the sim.
- EXU StaticGeometry positions are sim space (EXU converts); a unit mesh scaled per instance keeps its UVs,
  and render z is mirrored, so mesh `v` runs south. A sheet over a "flat" floor must clear the floor's
  relief (misn14's wet cells vary by up to 0.3; at +0.06 the floor poked through in patches).
- Vehicle wakes are one shared module (`Scripts/CRWake.lua`, `Docs/VEHICLE_WAKES.md`): directors call
  `Init` / `Update` / `Stop`; a particle system per tracked craft is budgeted globally (default 4, max 6),
  scanned at 4 Hz, near-viewer only. Do not add per-director hover/wake loops, and do not give a director
  its own copy of the craft scan. Its second `EnsureExtra("cr_wake")` overwrites the "last payload
  requested" in director test stubs: call `Wake.Init` before the director's own `EnsureExtra`.

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

**Original 1998 guide / cut campaign VO (2026-10-16):** `Docs/ORIGINAL_GUIDE_LORE_AND_CUT_CONTENT_20261016.md` records the owner-provided Shane Mooney guide findings, the Tartarus/Titan warning (not a proven boss), the potential Mission 17 processed/unprocessed crystal mechanic, and other cut-dialogue leads. **[owner goal]** restore the Achilles crystal idea after map/1.5-source verification; keep faithful Lua behavior distinguished from newly authored CR extensions. Mission 4-7/12/13/15 cut VO already restored must not be added a second time. This is a research/backlog checkpoint, not approval of a specific gameplay design.

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

### Mars rocket presentation (18 October 2026)

`misn06` now follows the Mission 16 pattern for moving static cinematic fixtures:
preplace the labelled actor, relay one acknowledged visual event, and apply its
translation on each peer. Do not assume host `SetTransform` on a static building
will replicate like a craft. Custom presentation operations must also be admitted
by `ReceivePresentation`; otherwise they stall the ordered event stream even if
the local host effect works. The four-peer presentation test covers this case.
Art, native validation status and resume steps: `Docs/MISN06_ROCKET_FILM.md`.

For stock launch-pad docking, do not transfer Ogre mesh X directly into a BZN
local offset. Redux's `sblpad.mesh` raised deck has positive model X; its native
SDF `sbl11bdc` bounds have negative X. The validated native deck centre is
(-19.407374,29.129,-42.536600). A wrong sign displaced the rocket by about 40 m.
EXU point-light colour arguments need named `{r=...,g=...,b=...}` fields; an
array silently failed inside the effect's pcall until the mock asserted the
actual native shape. Rebuild 4 proves the corrected pad and light on both peers.

Native scenarios are dot-sourced into `Run-BZRCoopMission.ps1`. Avoid names from
its parameters: `$clients` aliases its `[int]$Clients` parameter because
PowerShell is case-insensitive. Assigning a peer-index array then fails before
the first scenario step. Use a scoped name such as `$rocketClients`; also avoid
using `$c` for an array and `$C` for its loop element.

## 10. Keeping this document current

Cut Fury fighter (2026-10-16): the owner-selected standalone `hvraz` port is
`Battlezone Files/Mods and Custom Files/Fury Fighter` in Drive, not ISDFC's
ODF/red texture. CR's `crfraz` copies its model/native data and namespaces every
GEO companion; ship those companions even with a Redux mesh. Destruction passed
in the private current-bundle baseline; the historical crash cause remains
unknown. See `Docs/FURY_FIGHTER.md` for the source hashes, initial weapon balance,
Mission 14-18 roster changes and exact native evidence/limits.

### Mission 16 map selection and cut-content evidence (2026-10-16)

The installed stock campaign selects `misn16b.bzn` for Strike at the Heart.
Both `misn16` maps use the same mission class; the suffix does not establish a
second story phase. The selected `b` layout includes six spawn paths required
by the active port but absent from the alternate map. Its unnamed paths and
saved SAT/camera motion need deliberate handling during conversion. See
`Docs/MISN16_PLANNING.md` for the asset inventory and proposal.

Six available Mission 16 radio files have no active call in the audited source;
only one is explicitly commented out there. Distinguish available unused
dialogue, disabled code, shipped quirks and a proposed new set piece. In
particular, the transport-escape VO and debrief support the story, but the
inspected mission/map do not establish a recovered transport sequence.

### Terrain source and boundary preservation (2026-10-14)

For the terrain prototype, see `Docs/TERRAIN_EDGE_PASS.md` and
`Tools/Build-TerrainEdgePass.py`. Use the canonical unsmoothed CR heights;
retained later-mission heights are available at `ce18e89`. `misn16.bzn` resolves
`misn16b` terrain. Redux uses the min/max X/Z of `edge_path`; `path_edge` does
not substitute for it, and a polygon-shaped path still gives rectangular
limits. A southern-terrain move must transform BZN objects, physics positions
and mission paths together. Preserve mission pads and validate the navigation
consequences separately from the asset render. Offline slope-grid navigation
is a screening tool, not live AI qualification.

The misn14 `world` path is a closed area outline, not a travel corridor. Do not
protect a flat road along it. On Io, type 0's cracked red crust and type 1's
molten pool have different appearances despite the former's "Lava" TRN label;
use type 5 explicitly for a manufactured bridge. Stretch only the crossing,
translate adjoining land intact, and check the escort's interpolated route as
well as its waypoints against the level deck.

Both binary and text BZNs start with `version [1]`; distinguish them using the
`binarySave` header before applying text CRLF checks. Binary payload 0x0A bytes
are data. Deployment must use build roots matching the bundled suite: the
default sibling checkout can be older than CR's committed binaries.

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

### Co-op quick-action polling (2026-10-15)

The network GameKey wrapper discards every key owned by the raw-key poller.
Its closed-PDA gate must allow J, V and Z, since all three consumers run every
frame. Restricting that gate to J silently disables closed-PDA help and give.
Keep navigation gated, and update down-edge state during text entry so held chat
keys cannot replay on exit. `Tools/Test-CoopNetworkInput.lua` executes the actual
polling block; `Tools/Test-CoopInputLive.ps1` exercises native input separately.

### Co-op HUD defaults and native stats (2026-10-15)

Apply the native scoreboard default once after a local network player is ready;
reasserting it in every Update defeats the stock M toggle. Retry late EXU loading
and reset defaults on Initialize. The optional EXU kill-notice switch suppresses
presentation only; stock scores and mission text remain active. Confirmed by
`Tools/Test-CoopHudLive.ps1` on two native GOG clients, including a controlled
death. GetPlayerNetworkStats takes a network id, not a team. Local ping/loss are
absent and native lives differ from CR's respawn budget; see
`Docs/COOP_DX11_RECOVERY_20261015.md` for evidence and platform limits.

### Coop Diagnostics freshness (2026-10-15)

The second co-op PDA page uses mission-scoped CR control/receipt observations;
polling native scoreboard data does not establish fresh traffic. Native
pingSamples is retained history size, not a last-packet timestamp. Status must
expire and recover from actual received messages, distinguish a delayed heartbeat
from other live CR traffic, and clear on Initialize/DeletePlayer. Application
receipt timeouts are not measured UDP loss. Legacy heartbeat metadata stays
unknown. See `Docs/COOP_DIAGNOSTICS_20261015.md`; regression fixtures cover these
boundaries and the native three-client run demonstrates stalled/recovered traffic.

Transport totals come from optional EXU GetNetworkTrafficStats/OpenShim snapshots:
two-second wall-clock UDP rates and observed routes, not per-player delivery.
Tx includes accepted pending submissions; Rx uses observed completions. Keep
unavailable providers and unknown/idle route states explicit. Never infer the
route from a configured preference or count a truncated trace prefix as the
datagram's actual byte length.

### Mission 15 map and methane classification (2026-10-15)

Mission 15 campaign play uses the shipped `misn15b` layout under the `misn15`
runtime stem (`Docs/MISN15_COOP.md`). The alternate map is not interchangeable:
it lacks the active patrol label, sixth camera and Tartarus. Prepare close
rescue groups before discovery; their authored spawn sites are inside the
discovery radius. Mission 15 authors them with stable labels on team 7.
The global pure-MAT-0 height mode is a dry exterior plateau at 102.2 m here;
use the explicit 38.1 m lower-basin classification for this map's water data,
not Mission 14's mask or the generic mode. Validate both MAT nibbles and the
height range. When changing parsed BZN Fields, write with
`preserve_spelling=False` and reparse; source text spellings can hide mutations.
Changing an AiPath label also requires updating its `label.size` field to the
encoded byte length. The native loader allocates from that count; a successful
Toolbox reparse does not check their agreement. Mission 15's map contract checks
every path's allocation length after renaming the duplicate editor labels.

### Four-client evidence and cold startup (2026-10-16)

Per-mission "not yet verified" sections can lag the native reports. Check the
saved `flow-summary.json` participant array, scenario and actual result checks;
a four-player filename or a short startup pass is not a complete story pass.
The focused queue and coverage boundaries are in
`Docs/FOUR_PLAYER_QUALIFICATION_20261016.md`. Require all four results and move
all humans through extraction, not just the host and the original second-client
fixture. Hash the selected native build before and after each run.

A fourth cold client exposed a shader-resource hook installed only after CR's
first Modable parse. OpenShim owns the correction: arm the identity-checked
import hook before the expensive patch sweep, while keeping actual Ogre
registration on its caller thread. Do not hide caught rendering errors or
switch renderer to obtain a green campaign result. An assisted key-ship swap
in the Mission 12 scenario does not qualify physical sniping or boarding.

Newly assigned label announcements, including custom mission names and `crco_`
names, must carry the native handle itself until
Send serializes it. A printable `@handle@label` string is not a native network
identity and cannot bootstrap a label the guest has not received. Keep authored
map labels unique as well. Host-owned static objects can need explicit peer
presentation of surrender `SetTeamNum`; check the actual buildings on every
guest rather than only the authority's mission flag. Dynamic craft ownership
continues through native replication.

Per-human objective panels intentionally differ. Compare each peer's native
operations with the authority's recipient-specific dispatch plan, and retain a
negative regression for a missing fourth-player operation. Native object deletion
can arrive before a presentation RemoveObject event, so verify the previously
observed guest objects are gone. Travel helpers that take object handles must not
receive position vectors: use owner-local SetPosition for a vector assist.

Compile the complete mission plus appended harness probe under Lua 5.1 before
launching. A separately valid probe can exceed the mission chunk's 200-local
limit; keep extra wrapper captures inside nested functions. A sampled event
delivery check must allow bounded time to reach the authority's sampled
watermark. Equality between two independent instantaneous reads can reject an
in-flight event or a guest that has already received newer events. Keep actual
undelivered watermarks and final presentation mismatches as failures.

### Mission 16 captured CCA assets and escape reference (2026-10-16)

Owner-approved art: copy the stock SDF/VDF and mesh, rebind a new material and
texture; preserve geometry, rig and native hardpoints. Use `cr16cmd`, `cr16hng`,
`cr16pwr`, `cr16tow` for every hostile CCA base instance in Mission 16. Allies
keep normal CCA assets. Both tower hardpoints use a mission-local 200 m Bolt
Buddy (ordnance lifetime must change as well as scan range). Keep CR's amended
`misn16b` terrain. Mission 18 already provides the Fury transport: `hbtran00`
hull and `hbtrn200` thrusters. Mission 16's unused boarding VO supports a new
evacuation scene using those models; this is not proof of recovered takeoff
logic or a working boarding animation. See `Docs/MISN16_PLANNING.md`.

Mission 16 evacuation prototype now uses a preplaced stock Mission 18 assembly
and two SATs beyond edge_path, on a local type-1 Titan pad. Static hull/engine
movement is a visual translation per peer after an acknowledged scene event;
never issue craft AI commands to it. Publish scene identities before boarding
removals so a late initial Label cannot block the ordered stream. Register new
scene opcodes in both ApplyPresentation and ReceivePresentation's allowlist.
See `Docs/MISN16_COOP.md` for validation boundaries.

The native SAV class is the flying Fury and can ignore a cinematic Goto in
favor of its attack behavior. Use the ground SAT for evacuation actors and
script their route velocity, keeping the two lanes separated; the native AIP
can supersede ordinary enemy movement orders. Keep boarding pockets outside
engine collision shapes and stop accepting boarders before launch. The pad
film also needs a camera high enough to clear the southern foreground ridge.

### Fury fighter and faction mine asset checks (2026-10-17)

`crfraz` uses the owner's standalone Drive Fury Fighter port, not ISDFC gameplay
or its red atlas. Mars volcano mines use `cromine`; later Fury fields use
`crfmine`. See `Docs/FURY_FIGHTER.md` and `Docs/BOLT_MINE_VARIANTS.md` for scope,
source hashes and native evidence. The historical original VDF destruction crash
was not reproduced with either replacement or native debris; its cause remains
unknown, so do not describe the asset copy as a proven crash fix.

Verify mesh -> material -> texture in the live renderer, then inspect an actual
frame. A loaded texture and a correct material readback did not prove the first
BC3 conversions displayed: these mine atlases appeared gray until the same pixels
were tested as PNG/RGBA8 DDS. The builders now use RGBA8 DDS. Native `draw_bolt`
and `draw_twirl` texture names also need an Ogre sprite material; copying a new
image alone is insufficient. Hidden camera pods retain collision: keep fixture
anchors away from the mine-to-target firing line, and apply no craft AI setters
to the mines or pods. Private art/damage fixtures do not qualify mission combat.

Mission 16 transport exhaust is peer-local `CRMisn16LaunchFX`, started by the
existing `EvacLaunch` event. Attach at the `hbtrn200` mesh's lower end, local Y=12;
its object origin is below the actual nozzle. Keep spent exhaust in world space
and pad dust grounded. `MakeExplosion` light particles are local-only, so each
peer emits its own bounded zero-damage ignition pulses. Stop effects on departure,
result and restart; do not replay ground wash when resuming an airborne launch.

The SM4 and GLSL `CR_Effect` sprite vertex programs swizzle stock vertex color
BGRA, while SM3 HLSL does not. For Mission 16 Ogre exhaust, use neutral emitter
RGB with the Fury blue hue in `CR16/FuryExhaust` material diffuse/glow constants
(after that swizzle). Do not fix one Ogre effect by recoloring shared stock shaders.

Concept fleet assets: the owner identified the five small bottom-right objects
in private `CCAfleet3.webp` as stock comparison units, not additional capital ship
designs. Its svapc silhouette and the installed 14.6186 m mesh inform an approximate
0.25 m/pixel survey. See `Docs/CONCEPT_FLEET_ASSETS.md`; never invent classes for
those comparison units. Curved-hull surface cards need subdivisions to stay on
the hull, and coarse closed structural solids should feed the native GEO/SDF;
copying every visual window/panel can exceed native geometry table limits.

Create an explicit `BZR_CAMPAIGN_RUNTIME_DIR` **before** invoking the manager and
check the actual deployment footer. A nonexistent override currently falls back
to the ordinary GOG development mod. In the carrier prototype this refreshed 13
existing managed files and added nine resources there; the handoff records the
exact affected files rather than pretending the deployment was isolated.
Native fleet preview motion remains unqualified: guest static-fixture transform
readback lagged behind continuous movement, then failed to converge even after
holding a fixed endpoint. Network ownership/interpolation is suspected, not
proven. `Test-ConceptFleetLive.ps1 -ExerciseMovement` retains the strict failing
diagnostic; its default validates stationary model rendering. Do not present a
passing asset smoke test as proof of precise co-op cinematic motion.

CCA fleet art review: inspect stock CCA meshes with their UV textures, not only
texture atlases. The owner rejected regular raised armour tiles. Preserve broad
faceted skin and use restrained flush seams. Corner-only paint projection can
cut through bevels; intersect paint polygons with actual structural triangles.
The fleet tangent normal bake uses DirectX -Y to match cross(tangent,normal).
See `Docs/CCA_REDUX_ART_PASS.md` for the revision and qualification state.
