# campaignReimagined

This repo is part of the shared Battlezone workspace described in `C:\Users\iestu\Documents\GIT\BZR-Workspace\AGENTS.md`.

## Local Role
- Primary addon repo for Lua mission scripts, gameplay content, packaged assets, and installed runtime files.

## Local Workflow
- Make campaign content changes in the repo root first; that is the live working/runtime directory.
- Before committing or pushing, sync the root changes into `_Source` so git reflects the verified organized copy.
- Use `Manage-CampaignFiles.ps1` in the repo root when you need to sync root <-> `_Source`, build `_Release`, or publish.
- Treat `_Release` as build output for workshop packaging, not the primary editing location.

## Cross-Repo Pointers
- Native save behavior, hooks, and reverse-engineering notes live in `C:\Users\iestu\Documents\GIT\BZR-OpenShim`.
- Subtitle support lives in `C:\Users\iestu\Documents\GIT\BZR-Subtitles`.
- File I/O helpers live in `C:\Users\iestu\Documents\GIT\bzfile`.
- Script extender support lives in `C:\Users\iestu\Documents\ExtraUtilities`.
- Shader/material work lives in `C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\addon\shadersEnhanced`.

Open the shared workspace file `C:\Users\iestu\Documents\GIT\BZR-Workspace\Battlezone98.code-workspace` when a task may span repos.
