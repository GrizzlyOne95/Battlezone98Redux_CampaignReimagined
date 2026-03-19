# campaignReimagined

This repo is part of the local Battlezone workspace opened via
`%USERPROFILE%\Documents\Battlezone98Redux_Shim.code-workspace`.

## Workspace Layout
- Sibling repos normally live under `%USERPROFILE%\Documents\GIT\...`.
- The primary local game install is typically `%USERPROFILE%\Documents\Battlezone 98 Redux`.
- Prefer the workspace file and these conventions over hardcoded profile-specific paths.

## Local Role
- Primary addon source repo for Lua mission scripts, gameplay content, and packaged assets.

## Local Workflow
- Make campaign content changes in `_Source`; that is the canonical tracked source tree on this machine.
- Use `Manage-CampaignFiles.ps1` in the repo root when you need to sync from a deployed addon install, build `_Release`, deploy `_Source`, or publish.
- Treat the deployed game addon folder as a runtime target, not a second git checkout.
- Treat `_Release` as build output for workshop packaging, not the primary editing location.

## Cross-Repo Pointers
- Native save behavior, hooks, and reverse-engineering notes live in `%USERPROFILE%\Documents\GIT\Battlezone98Redux_Shim`.
- Subtitle support lives in `%USERPROFILE%\Documents\GIT\BZR-Subtitles`.
- File I/O helpers live in `%USERPROFILE%\Documents\GIT\bzfile`.
- Script extender support lives in `%USERPROFILE%\Documents\GIT\ExtraUtilities-G1`.
- Shader/material work lives in `%USERPROFILE%\Documents\GIT\Battlezone98Redux_EnhancedShaders` and the deployed workspace game install.

Open `%USERPROFILE%\Documents\Battlezone98Redux_Shim.code-workspace` when a task may span repos.
