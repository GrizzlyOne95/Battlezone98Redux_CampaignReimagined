# Campaign Reimagined (Canonical Source)

This is the authoritative Campaign Reimagined source tree for campaign content, Lua, materials/shaders, assets, packaging, and publishing.

## Authoritative Paths and Promotion
- Canonical source: `C:\Users\iestu\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\Open Patch - CampaignReimagined`.
- GOG test game: `C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux`; runtime mod: `...\mods\3686673790`.
- Steam subscribed payload: `C:\Program Files (x86)\Steam\steamapps\workshop\content\301650\3686673790`.
- Required promotion: **edit canonical source -> validate/build -> `Manage-CampaignFiles.ps1 -deploy` to GOG -> test GOG -> build/upload Workshop item `3686673790` -> let Steam download it -> final Steam test**.
- Steam/Workshop is never the development deploy target. Never copy source directly into Steam's Workshop cache or use it as a GOG fallback; final Steam evidence is valid only after upload/download.
- Use `Manage-CampaignFiles.ps1` for deploy/sync, Workshop staging, and publishing. `Local\Workshop` is generated staging, not a runtime. `BZR_CAMPAIGN_RUNTIME_DIR` may override the GOG runtime intentionally but must not point at a Steam Workshop cache.
- Preserve runtime-only files intentionally excluded by the manager; installed/deployed copies are not source and must not be committed.

## BZR Bundle
Local sibling/reference checkouts normally live under `%USERPROFILE%\Documents\GIT`; verify `origin` before editing because local folder names may be historical. The CR Git checkout there is useful for cross-reference, but the canonical edit/promotion paths above remain authoritative.

- **Campaign Reimagined / CR** — `GrizzlyOne95/Battlezone98Redux_CampaignReimagined` (this repo): addon content, Lua consumers, assets, packaging, integration/validation.
- **OpenShim** — `GrizzlyOne95/Battlezone98Redux_Shim`: low-level hooks, patches, RE, SDK/native engine integration.
- **EXU / ExtraUtilities** — `GrizzlyOne95/ExtraUtilities`: reusable native/Lua-facing runtime features. **EXU always means this repository.**
- **bzfile** — `GrizzlyOne95/bzfile`: Lua-accessible file I/O and update/deployment support.

Cross-repo reading is encouraged. Do not edit another repo merely because it was consulted; read that repo's `AGENTS.md` before coordinated changes.

Reference/tooling repos under `%USERPROFILE%\Documents\GIT` (reference, not default edit targets): `BZ98RBlenderToolKit`, `Battlezone98Redux_DedicatedServer`, `BZ1-GameWatcher`, `BZ1_Source`, `BZ2_Source`, `Battlezone_LobbyMonitor`, `BZNTools`, `Battlezone98Redux_AudioTool`, `Battlezone98Redux_WorldBuilder`, `Battlezone98Redux_ZFSSpecialist`. Rendering work may also consult local `ogre-1.10.0`.

## Git Workflow
- Before editing, inspect `git status -sb` and the relevant diff; preserve pre-existing user changes.
- Normal work goes on a task branch, usually `agent/<short-description>`, never directly on the default/protected branch.
- Agents may commit and push coherent task-owned checkpoints without repeatedly asking. Prefer validated build/validator/game-test milestones; a clearly labeled `WIP:` checkpoint may preserve valuable intermediate work but must stay out of the default branch and Workshop publication.
- Stage only task-owned files. Never blanket-stage, clean, restore, or otherwise absorb/destroy unrelated changes in a mixed worktree.
- Do not rewrite shared history or force-push unless explicitly requested.
- PR merges, releases/tags, Steam Workshop upload/publication, and other external publishing require explicit user instruction. GOG deployment is allowed when it is part of requested local validation.
- Do not commit secrets, machine credentials, transient output, runtime copies, generated Workshop staging payloads, crash dumps, or scratch artifacts the repo does not intentionally track.

## Ownership Routing
- Engine/native hooks, loader/save patches, low-level RE -> **OpenShim**.
- Reusable higher-level Lua/native runtime APIs -> **EXU**.
- File I/O and constrained update/deployment primitives -> **bzfile**.
- Campaign-specific Lua/content/assets/integration -> **this repo**.
- Consult sibling implementations before duplicating functionality, but keep changes in the repo that owns the behavior.
