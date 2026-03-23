# campaignReimagined

This repo is part of the local Battlezone workspace opened via
`%USERPROFILE%\Documents\GIT\BZR-Workspace\Battlezone98.code-workspace`.

## Canonical Paths
- Workspace File: `%USERPROFILE%\Documents\GIT\BZR-Workspace\Battlezone98.code-workspace`
- Destination/Runtime Mod Folder: `C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\packaged_mods\3686673790`
- Source Repo for Git and edits: `%USERPROFILE%\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\Open Patch - CampaignReimagined`

## Workspace Layout
- Sibling repos may live under `%USERPROFILE%\Documents\GIT\...`, but this repo's canonical local source path is `%USERPROFILE%\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\Open Patch - CampaignReimagined`.
- The primary local runtime target for this repo is `C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\packaged_mods\3686673790`.
- Prefer these canonical paths for this machine over older `Documents\Battlezone 98 Redux` or `addon\campaignReimagined` assumptions.

## Local Role
- Primary addon source repo for Lua mission scripts, gameplay content, and packaged assets.

## Local Workflow
- Make campaign content changes directly in this repo root; `%USERPROFILE%\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\Open Patch - CampaignReimagined` is the canonical tracked source tree on this machine.
- Use `Manage-CampaignFiles.ps1` in the repo root when you need to sync from the packaged mod runtime, deploy to the packaged mod runtime, or publish.
- Treat `C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\packaged_mods\3686673790` as the primary runtime target for local verification.
- Do not treat the game install's `addon\campaignReimagined` path as a second git checkout or source workspace.

## Cross-Repo Pointers
- Native save behavior, hooks, and reverse-engineering notes live in `%USERPROFILE%\Documents\GIT\BZR-OpenShim`.
- Subtitle support lives in `%USERPROFILE%\Documents\GIT\BZR-Subtitles`.
- File I/O helpers live in `%USERPROFILE%\Documents\GIT\bzfile`.
- Script extender support lives in `%USERPROFILE%\Documents\ExtraUtilities`.
- Shader/material work for this campaign now lives directly in `C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\packaged_mods\3686673790`; use `%USERPROFILE%\Documents\GIT\ogre-1.10.0` only when engine-side rendering behavior needs inspection.

Open `%USERPROFILE%\Documents\GIT\BZR-Workspace\Battlezone98.code-workspace` when a task may span repos.
