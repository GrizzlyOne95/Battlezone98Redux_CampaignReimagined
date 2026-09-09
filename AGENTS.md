# Campaign Reimagined (Canonical Source)

This is the authoritative Campaign Reimagined source tree for campaign content, Lua, materials/shaders, assets, packaging, and publishing.

## Authoritative Paths and Promotion
- Canonical Git working tree: `C:\Users\iestu\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\Open Patch - CampaignReimagined`. **This Google Drive directory is the canonical Git checkout and edit source.** Do not create or use a second Campaign Reimagined checkout elsewhere (including under `docs/`, `Docs/`, or `%USERPROFILE%\Documents\GIT`) as an alternate edit source. If a duplicate/nested CR checkout is discovered, treat it as scratch/stale until its provenance is verified against this worktree and `origin`.
- GOG test game: `C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux`; runtime mod: `...\mods\3686673790`.
- Steam subscribed payload: `C:\Program Files (x86)\Steam\steamapps\workshop\content\301650\3686673790`.
- Required promotion: **edit canonical source -> validate/build -> `Manage-CampaignFiles.ps1 -deploy` to GOG -> test GOG -> build/upload Workshop item `3686673790` -> synchronize the Steam Roadmap discussion -> let Steam download it -> final Steam test**.
- A real Workshop publication is not complete until the Roadmap discussion at `https://steamcommunity.com/workshop/filedetails/discussion/3686673790/216888303627073611/` has been synchronized from OpenShim's canonical `Docs/STEAM_ROADMAP_BBCODE.txt`. Follow `docs/STEAM_PUBLISH_CHECKLIST.md`. Dry runs are exempt from public Steam edits.
- Steam/Workshop is never the development deploy target. Never copy source directly into Steam's Workshop cache or use it as a GOG fallback; final Steam evidence is valid only after upload/download.
- Use `Manage-CampaignFiles.ps1` for deploy/sync, Workshop staging, and publishing. Publishing is a **local** run of that script, not the `Publish Steam Workshop` GitHub workflow -- that workflow has never run and its self-hosted runner does not exist, so it would queue forever. Drive it non-interactively (`-workshop-init`, `-workshop-auth`, `-workshop-build` for a dry run, `-publish "<note>"`); the bare script opens a `Read-Host` menu that cannot be used headlessly. `workshop.config.json` is per-machine and gitignored, so a fresh clone has none. A new file in the repo is excluded from staging until `-bless` adds it to `Shipping/shipping.lock.json`, which surfaces confusingly as "missing required file". Publishing also needs a tagged OpenShim release, not a branch. Full sequence in `docs/STEAM_PUBLISH_CHECKLIST.md`. `Local\Workshop` is generated staging, not a runtime. `BZR_CAMPAIGN_RUNTIME_DIR` may override the GOG runtime intentionally but must not point at a Steam Workshop cache.
- Preserve runtime-only files intentionally excluded by the manager; installed/deployed copies are not source and must not be committed.
- `Bin\` is a cache of sibling build outputs, not an independent source. Every deploy and Workshop staging refreshes all four shipping binaries (`winmm.dll`, `exu.dll`, `bzfile.dll`, `bzfile_replace_helper.exe`) and their `.pdb` pairs from the repositories that build them, then fails the staging if a staged binary does not hash-match its build output. Override the source repositories with `BZR_OPENSHIM_REPO`, `BZR_EXU_REPO`, and `BZR_BZFILE_REPO`; they default to `%USERPROFILE%\Documents\GIT\{BZR-OpenShim,ExtraUtilities,bzfile}`.

## BZR Bundle
Sibling/reference repositories normally live under `%USERPROFILE%\Documents\GIT`; verify `origin` before editing because local folder names may be historical. **Campaign Reimagined is the exception:** its canonical Git worktree is the Google Drive path above. Do not maintain or consult a second CR checkout under `%USERPROFILE%\Documents\GIT` as a competing source tree.

- **Campaign Reimagined / CR** — `GrizzlyOne95/Battlezone98Redux_CampaignReimagined` (this repo): addon content, Lua consumers, assets, packaging, integration/validation.
- **OpenShim** — `GrizzlyOne95/Battlezone98Redux_Shim`: low-level hooks, patches, RE, SDK/native engine integration.
- **EXU / ExtraUtilities** — `GrizzlyOne95/ExtraUtilities`: reusable native/Lua-facing runtime features. **EXU always means this repository.**
- **bzfile** — `GrizzlyOne95/bzfile`: Lua-accessible file I/O and update/deployment support.

Cross-repo reading is encouraged. Do not edit another repo merely because it was consulted; read that repo's `AGENTS.md` before coordinated changes.

## Shared BZR Lua Reference
Before writing, reviewing, or changing BZR Lua behavior—or adding Lua-facing native APIs—read `Docs/BZR_LUA_AGENT_REFERENCE.md`. This document is mirrored across the four core BZR repos and should remain byte-identical. Repo-specific `AGENTS.md`/architecture docs still govern implementation ownership. When the shared reference changes, mirror the same content to OpenShim, EXU, Campaign Reimagined, and bzfile in the same workstream.

## Platform and Distribution Compatibility
- Treat Windows/GOG, Windows/Steam, Linux/Steam via Proton, and Linux/GOG via a compatible Wine/Proton prefix as the supported runtime matrix. Read `Docs/BZR_PLATFORM_COMPATIBILITY.md` before changing native loading, paths, filesystem behavior, process launch, module/resource discovery, installers, deployment, packaging, or update behavior.
- Compatibility is a standing review requirement. Do not infer Steam behavior from GOG alone or Proton/Wine behavior from native Windows alone; run the affected validation lanes, or explicitly record a lane as unverified and obtain tester validation before release.
- `Docs/BZR_PLATFORM_COMPATIBILITY.md` is mirrored across OpenShim, EXU, Campaign Reimagined, and bzfile and should remain byte-identical. Update all four copies in the same workstream.

Reference/tooling repos under `%USERPROFILE%\Documents\GIT` (reference, not default edit targets): `BZ98RBlenderToolKit`, `Battlezone98Redux_DedicatedServer`, `BZ1-GameWatcher`, `BZ1_Source`, `BZ2_Source`, `Battlezone_LobbyMonitor`, `BZNTools`, `Battlezone98Redux_AudioTool`, `Battlezone98Redux_WorldBuilder`, `Battlezone98Redux_ZFSSpecialist`. Rendering work may also consult local `ogre-1.10.0`.

## Git Workflow
- Before editing, inspect `git status -sb` and the relevant diff; preserve pre-existing user changes.
- Normal work goes on a task branch, usually `agent/<short-description>`, never directly on the default/protected branch.
- One logical task/workstream belongs to one branch and one PR. Name the branch for its actual scope; do not accumulate unrelated follow-up work merely because a checkout already exists.
- A task branch is single-use. Once its PR is merged or closed, do not add new work to that branch or reopen it as the base for a different PR. Start the next task from current `origin/main` on a new branch.
- Stacked PRs are temporary. A child may target an unmerged parent branch when there is a real dependency, but after the parent lands, reconstruct the child on updated `main` (prefer a fresh branch plus selective cherry-picks/reapplication) rather than carrying stale parent ancestry forward.
- If an old branch has diverged far from `main`, do not open or preserve a giant mixed-history PR. Identify the task-owned commits/files, salvage only that coherent work onto a fresh branch from current `main`, then retire the stale branch.
- After a PR is merged or intentionally abandoned and any unique work worth preserving has been rescued, delete the corresponding local and remote task branch. Closed PRs remain the historical record; task branches are not permanent archives.
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
