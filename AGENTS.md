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
- Do not commit or push unless the user explicitly requests it.

## Cross-Repo Pointers

- Native shim, loader, save, patch, and reverse-engineering work: `C:\Users\iestu\Documents\GIT\BZR-OpenShim`
- Lua file I/O support: `C:\Users\iestu\Documents\GIT\bzfile`
- Ogre rendering reference: `C:\Users\iestu\Documents\GIT\ogre-1.10.0`
- Discover any other Battlezone repo beneath `C:\Users\iestu\Documents\GIT`; verify that it exists before relying on it.

Open `C:\Users\iestu\Documents\GIT\BZR-Workspace\Battlezone98.code-workspace` when a task spans repos.
