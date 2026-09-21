# Campaign Reimagined (canonical source)

This is the authoritative Campaign Reimagined source tree for campaign content, Lua, materials, assets, packaging, and publishing. Keep this root file short; load the linked task-specific references only when their trigger applies.

## Authority and ownership

- The only editable CR checkout is `C:\Users\iestu\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\Open Patch - CampaignReimagined`. Treat duplicate or nested CR trees as stale until their provenance is verified. Do not create a second CR checkout or worktree.
- Because CR has one canonical checkout, serialize tasks that write to it. Read-only cross-repository inspection can run concurrently.
- Campaign content, Lua consumers, assets, materials, packaging, and integration belong here. Route low-level hooks to **OpenShim**, reusable Lua/native runtime APIs to **EXU**, and file/update primitives to **bzfile**.
- Sibling repositories normally live under `%USERPROFILE%\Documents\GIT`. Verify `origin` and branch before treating a sibling as evidence, and read its `AGENTS.md` before editing it.

The DX11 Enhanced base and terrain shaders are the exception to CR ownership: they live in OpenShim as `resources/renderer/enhanced/openshim_enhanced_*`. CR owns the selecting materials, texture aliases, static-IBL wrappers, and other shaders. Before editing `Materials/CR_BZBase.material`, `Materials/CR_BZTerrainBase.material`, or `Shaders/CR_static_ibl.program`, read `Docs/ENHANCED_SHADER_OWNERSHIP.md` and then run `Tools/Test-ProgramReferences.ps1`.

## Load only when relevant

- Lua behavior or Lua-facing native APIs: read `Docs/BZR_LUA_AGENT_REFERENCE.md` first.
- Loading, paths, filesystem/process behavior, discovery, installers, deployment, packaging, or updates: read `Docs/BZR_PLATFORM_COMPATIBILITY.md` first and account for Windows/GOG, Windows/Steam, Linux/Steam via Proton, and Linux/GOG via Wine/Proton.
- GOG deployment, Workshop staging, or publication: read `docs/STEAM_PUBLISH_CHECKLIST.md` before acting.
- The two shared BZR documents above must remain byte-identical across CR, OpenShim, EXU, and bzfile; update all four in one workstream if either changes.

## Working style

- Inspect `git status -sb` and the relevant diff before editing. Preserve unrelated changes.
- Use one `agent/<short-description>` branch per workstream, normally from current `origin/main`. Do not reuse merged/closed branches or accumulate unrelated follow-ups. Salvage only task-owned commits from stale branches.
- For exploratory visual or gameplay work, build the smallest deployable prototype and use targeted validation first. Wait for user acceptance before broad production hardening, release documentation, or a full qualification matrix unless those were explicitly requested.
- During iteration, run the narrowest meaningful checks. Run broader validation at a stable checkpoint and the release checklist only for a release candidate.
- Stage only task-owned files. Never blanket-stage, clean, restore, or overwrite unrelated work. Do not force-push or rewrite shared history unless explicitly requested.
- Agents may commit and push coherent task-owned checkpoints. PR merges, releases/tags, Workshop uploads, and other public publication require explicit user instruction.

## Deployment guardrails

- Use `Manage-CampaignFiles.ps1` non-interactively. The GOG mod at `C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\mods\3686673790` is the development target; never copy source into Steam's Workshop cache. Final Steam evidence comes only after an upload/download.
- New shipped files require `-bless`; review the lock diff. Use `-allow-removals` only when removing shipping entries intentionally. Deploy verifies against the lock by default.
- Preserve runtime-only files excluded by the manager. Installed copies and `Local\Workshop` are generated output, not source.
- `Bin\` is a cache refreshed from sibling build outputs, not an independent source. Override those repositories only with the documented `BZR_OPENSHIM_REPO`, `BZR_EXU_REPO`, and `BZR_BZFILE_REPO` variables.
- Real Workshop publication is incomplete until OpenShim's `Docs/STEAM_ROADMAP_BBCODE.txt` is synchronized to the Steam Roadmap discussion. Follow the checklist; dry runs do not require public edits.
