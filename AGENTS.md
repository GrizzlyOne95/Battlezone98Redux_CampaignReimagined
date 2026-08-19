# Campaign Reimagined (Canonical Source)

This is the canonical Campaign Reimagined source tree. Make campaign content, Lua, material, shader, packaging, and publishing changes here.

## Authoritative Paths

- Workspace: `C:\Users\iestu\Documents\GIT\BZR-Workspace\Battlezone98.code-workspace`
- Canonical source: `C:\Users\iestu\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\Open Patch - CampaignReimagined`
- Working game/test copy: `C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux`
- Working runtime mod: `C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\mods\3686673790`
- Other Battlezone Git repos: `C:\Users\iestu\Documents\GIT`
- Steam final-test game: `C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux`
- Steam post-upload Workshop payload: `C:\Program Files (x86)\Steam\steamapps\workshop\content\301650\3686673790`

## Required Promotion Order

1. Edit this canonical source tree.
2. Run validators/builds here.
3. Deploy to the GOG working runtime with `Manage-CampaignFiles.ps1 -deploy`.
4. Validate the change in the GOG game copy.
5. Build and upload the validated payload to Steam Workshop item `3686673790`.
6. Allow Steam to download the subscribed item, then perform final Steam testing.

Steam is not the development deploy target. Never copy source files directly into the Steam Workshop content directory, and never use that directory as a fallback when GOG is absent. Final Steam evidence is valid only after the corresponding payload has been uploaded and downloaded.

## Local Workflow

- Prefer source edits here over edits in either installed runtime.
- Use `Manage-CampaignFiles.ps1` for GOG deploy/sync, Workshop staging, and publishing.
- `BZR_CAMPAIGN_RUNTIME_DIR` may explicitly override the working runtime when necessary. Do not point it at a Steam Workshop download cache.
- Use `Local\Workshop` only as generated upload staging; it is not a game runtime.
- Preserve runtime-only files that the manager intentionally excludes from source synchronization.

## BZR Bundle Repository Map
- Treat the following four repositories as the core **BZR bundle**. They are separate repositories with separate ownership boundaries, but they are expected to be available together for cross-reference during Battlezone 98 Redux work.
- On the primary development PC, look for local sibling checkouts under `%USERPROFILE%\Documents\GIT` before searching GitHub. Prefer local source for fast code/reference lookup when the checkout is present and current; fall back to GitHub when a sibling repo is unavailable locally or when remote state must be verified.
- Do not assume the folder name from memory. Verify the checkout and its remote before editing; some repositories may use historical local directory names. The Campaign Reimagined Git checkout under `Documents\GIT` is useful for cross-repo reference, but the authoritative edit/promotion paths for Campaign Reimagined remain the ones declared above.
- **Campaign Reimagined / CR** = `GrizzlyOne95/Battlezone98Redux_CampaignReimagined` (this repo): campaign/addon content, Lua consumers, materials/shaders, packaging, integration examples, and end-user validation.
- **OpenShim** = `GrizzlyOne95/Battlezone98Redux_Shim`: native `winmm.dll` shim, engine hooks/patches, reverse engineering, SDK/native integration, and low-level Redux behavior.
- **EXU / ExtraUtilities** = `GrizzlyOne95/ExtraUtilities`: script extender and native utility library, especially reusable Lua-facing APIs and higher-level runtime features. When a task or document says **EXU**, it means this repository; do not rediscover or invent a separate EXU project.
- **bzfile** = `GrizzlyOne95/bzfile`: Lua-accessible file I/O support used by Battlezone scripts and addon-side systems.
- Cross-repo reading is encouraged when it avoids duplicating an API, misunderstanding ownership, or re-reverse-engineering something already solved elsewhere. Cross-repo editing is not automatic: modify another bundle repo only when the task actually requires a coordinated change and after reading that repo's own `AGENTS.md`.

### BZR Reference and Tooling Repositories
These repositories are especially useful for research and implementation reference, but are **not default edit targets** for new OpenShim/EXU/CR features. When working locally, first look for them under `%USERPROFILE%\Documents\GIT\<repository-name>` and verify the checkout/remote before relying on it.

- `GrizzlyOne95/BZ98RBlenderToolKit` — Redux asset, mesh/skeleton, animation, and Blender pipeline reference.
- `GrizzlyOne95/Battlezone98Redux_DedicatedServer` — dedicated-server behavior and multiplayer/server reference.
- `GrizzlyOne95/BZ1-GameWatcher` — Battlezone 1 game/server watching and related integration reference.
- `GrizzlyOne95/BZ1_Source` — Battlezone 1 source reference for legacy engine/game behavior.
- `GrizzlyOne95/BZ2_Source` — Battlezone II source reference for related engine/game concepts.
- `GrizzlyOne95/Battlezone_LobbyMonitor` — lobby/network monitoring reference.
- `GrizzlyOne95/BZNTools` — BZN/map tooling and format reference.
- `GrizzlyOne95/Battlezone98Redux_AudioTool` — Redux audio tooling/format reference.
- `GrizzlyOne95/Battlezone98Redux_WorldBuilder` — world/map-building tooling reference.
- `GrizzlyOne95/Battlezone98Redux_ZFSSpecialist` — ZFS/archive/content-format reference.
- Use these repos to answer questions, compare implementations, recover formats/behavior, and avoid duplicated investigation. Do not include them in a feature's change set merely because they were consulted.

## Git Checkpoint and Publishing Workflow

- At the start of any task that may modify the repo, inspect `git status -sb` and the relevant diff before editing. Treat pre-existing local changes as user-owned unless they are clearly part of the active task.
- Do not work directly on `main`, `master`, or another protected/default branch for normal feature, fix, content, validation, or documentation work. Create or use a task branch, normally named `agent/<short-description>`.
- Agents are pre-authorized to create coherent checkpoint commits and push task-owned changes to the current task branch without asking for permission after every checkpoint.
- Create checkpoints at meaningful engineering boundaries: after a coherent implementation/content slice, an important investigation result, a known-good build/validator/game-test state, or before beginning a riskier follow-on change. Do not create a commit for every trivial edit.
- Prefer checkpoints that pass the most relevant available validation. If valuable work must be preserved before validation, a clearly labeled `WIP:` commit is acceptable on a task branch; keep unvalidated WIP out of the default branch and out of Workshop publication.
- Push the task branch after meaningful checkpoints and before ending a substantial work session so the remote branch serves as a durable recovery point.
- Stage only task-owned files. On a mixed or pre-dirty worktree, do not use `git add -A`, `git add .`, blanket restore/clean commands, or other operations that can silently absorb or destroy unrelated workstation changes.
- If task changes overlap pre-existing user changes, preserve both where safely possible. Ask for direction only when the overlap cannot be isolated without risking user work.
- Use concise, descriptive commit subjects. For Lua/gameplay behavior, asset/material/shader changes, packaging behavior, compatibility assumptions, or in-game fixes, prefer a commit body that records the important rationale and validation performed.
- Documentation, roadmap, changelog, or release-note updates that are part of the same logical task should normally travel with the implementation/content checkpoints rather than being left only in the workstation tree.
- Do not amend, rebase, reset, rewrite, delete, or force-push shared history unless explicitly requested. Never use a force push as routine checkpoint behavior.
- Do not merge pull requests, push task work directly to the protected/default branch, create release tags/releases, upload or publish Steam Workshop content, or perform other external release/deployment actions unless the user explicitly requests that action.
- GOG runtime deployment for local validation may follow the Required Promotion Order when it is part of the requested task, but deployment copies are not source and must not be committed.
- Do not commit secrets, machine-specific credentials, transient build output, runtime deployment copies, generated Workshop staging payloads, crash dumps, scratch artifacts, or generated files that the repository does not intentionally track.

## Cross-Repo Pointers

- Native shim, loader, save, patch, and reverse-engineering work: `C:\Users\iestu\Documents\GIT\BZR-OpenShim`
- Lua file I/O support: `C:\Users\iestu\Documents\GIT\bzfile`
- Ogre rendering reference: `C:\Users\iestu\Documents\GIT\ogre-1.10.0`
- Discover any other Battlezone repo beneath `C:\Users\iestu\Documents\GIT`; verify that it exists before relying on it.

Open `C:\Users\iestu\Documents\GIT\BZR-Workspace\Battlezone98.code-workspace` when a task spans repos.
