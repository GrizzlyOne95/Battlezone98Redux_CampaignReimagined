# Enhanced Shaders

Material, shader, and rendering-profile addon content for Battlezone 98 Redux.

Workflow on this machine:
- source repo for git: `C:\Users\iestu\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\Open Patch - CampaignReimagined`
- edit the organized source tree in this repo root
- deploy a flattened runtime build to `C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\packaged_mods\3686673790`
- destination/runtime mod folder: `C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\packaged_mods\3686673790`
- use `Manage-CampaignFiles.ps1` for sync/deploy/publish so local testing matches a packaged mod install as closely as possible

Current shader pass:
- conservative stock-derived `CR_*` material/shader fork
- shared DX9, DX11, and GL safety hardening
- terrain atlas texel-center and packed-normal fixes aimed at stock terrain deformation issues
- optional OG retro-lighting compatibility through the `og-*` material schemes used by the addon stack

See [`ISSUE_TRIAGE.md`](ISSUE_TRIAGE.md) for the current rationale and issue-by-issue status for this pass.

## Credits

- `GrizzlyOne95` for current addon maintenance, integration, and workspace stewardship.
- `VTrider` for EXU-side groundwork that this addon stack builds on.
