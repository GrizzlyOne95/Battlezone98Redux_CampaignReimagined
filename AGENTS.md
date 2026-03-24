# campaignReimagined (Legacy Mirror)

This repo is a legacy local mirror/reference tree for campaignReimagined and is
part of the Battlezone workspace opened via
`C:\Users\iestu\Documents\GIT\BZR-Workspace\Battlezone98.code-workspace`.

## Canonical Paths
- Workspace File: `C:\Users\iestu\Documents\GIT\BZR-Workspace\Battlezone98.code-workspace`
- Canonical Source Repo for edits: `C:\Users\iestu\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\Open Patch - CampaignReimagined`
- Destination/Runtime Mod Folder: `C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\packaged_mods\3686673790`

## Workspace Layout
- This repo still exists for legacy sync, publishing, and historical `_Source`/`_Release` workflows, but the only active campaign paths right now are the Google Drive source repo and the packaged mod runtime folder.
- The canonical local source path for campaign content on this machine is `C:\Users\iestu\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\Open Patch - CampaignReimagined`.
- The primary local runtime target is `C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\packaged_mods\3686673790`.
- Prefer these canonical paths over older `Documents\Battlezone 98 Redux` or `addon\campaignReimagined` assumptions.

## Local Role
- Legacy mirror/reference repo for campaign content and sync tooling.

## Local Workflow
- Prefer making campaign content changes in `C:\Users\iestu\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\Open Patch - CampaignReimagined`, not in this legacy mirror, unless the task explicitly targets this tree or its sync scripts.
- If work must happen in this repo, `_Source` is the mirrored source subtree and not the primary source of truth on this machine.
- Use `Manage-CampaignFiles.ps1` in the repo root when you need to sync from runtime, build `_Release`, deploy runtime content, or publish.
- Treat `C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\packaged_mods\3686673790` as the runtime target for local verification.
- Do not treat the game install's `addon\campaignReimagined` path as a second git checkout or source workspace.

## Cross-Repo Pointers
- Native save behavior, hooks, and reverse-engineering notes live in `C:\Users\iestu\Documents\GIT\BZR-OpenShim`.
- Subtitle support lives in `C:\Users\iestu\Documents\GIT\BZR-Subtitles`.
- File I/O helpers live in `C:\Users\iestu\Documents\GIT\bzfile`.
- Script extender support lives in `C:\Users\iestu\Documents\ExtraUtilities`.
- Shader/material work for this campaign now lives directly in `C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\packaged_mods\3686673790`; use `C:\Users\iestu\Documents\GIT\ogre-1.10.0` only when engine-side rendering behavior needs inspection.

Open `C:\Users\iestu\Documents\GIT\BZR-Workspace\Battlezone98.code-workspace` when a task may span repos.
