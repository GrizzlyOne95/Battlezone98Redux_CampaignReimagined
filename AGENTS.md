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
