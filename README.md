# Campaign Reimagined

Campaign Reimagined is an experimental, unofficial campaign overhaul and community patch for **Battlezone 98 Redux**. It combines Lua mission rewrites, replacement maps and assets, shared gameplay systems, and native engine extensions. Its goal is to preserve the original campaign's identity while improving reliability, presentation, AI, and player options.

The integrated runtime uses [OpenShim](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim) for low-level engine fixes, [Extra Utilities](https://github.com/GrizzlyOne95/ExtraUtilities) for native Lua/Ogre features, and bzfile for file and persistence services. Installing the Lua scripts alone does not provide the full experience.

This project is **not affiliated with or supported by Rebellion**.

## Status and compatibility

- The **source tree** contains 17 NSDF campaign entries, from `misn02b` (Red Arrival) through `misn18` (The Ultimate Quake), plus other mission ports and supporting systems. These are not all at the same level of completion or testing.
- Later missions include experimental implementations: `misn16` and `misn17` remain prototypes, and `misn18` has limited DX11 one-/two-client live test coverage. Its offline, four-player, and DX9 paths are not fully qualified.
- **Source-tree content is not necessarily in the current Steam Workshop download.** Consult the [Workshop item](https://steamcommunity.com/sharedfiles/filedetails/?id=3686673790) and its change notes for the last published build.
- Native components target the 32-bit Windows executable of Battlezone 98 Redux **2.2.301**. Windows Steam/GOG and Linux Steam/GOG via Proton or compatible Wine are the maintained compatibility targets, not a guarantee that every experimental feature has passed all four configurations. See the [platform policy](Docs/BZR_PLATFORM_COMPATIBILITY.md).

This is a native patch with broad asset overrides and evolving mission code. Expect regressions, and report reproducible problems.

## Features

- **Campaign rewrites:** Lua-based mission flow, difficulty-aware encounters, objective and save/load repairs, co-op work, and restored or expanded mission presentation.
- **AI and combat:** Shared team AI, wingman command handling, economy/construction logic, targeting assistance, stuck recovery, and configurable tuning.
- **PDA and player systems:** Multi-page combat, target, career, logistics, loadout, and settings interfaces; autosaves, statistics, loadout presets, and persistent preferences.
- **Radio and subtitles:** Subtitle overlays, timing data, pause handling, and controls for stale or repetitive dialogue.
- **Visuals and atmosphere:** Renderer profiles, shaders/materials, weather, sky and terrain enhancements, emissive states, HUD scaling, and repaired models and textures.
- **Engine improvements:** Integrated OpenShim/Extra Utilities features for stability, networking, native autosaves, HUD/radar behavior, weapon convergence, headlights, turbo, shader caching, and classic destruction effects. OpenShim's engine-level changes also apply outside this campaign.
- **Maintenance:** Native-payload verification, diagnostics, repeatable builds, and checked Workshop staging.

Optional [HD terrain packs](Docs/HD_TERRAIN_PACKS.md) are **development/experimental content**, requiring a matching OpenShim HD build and DX11 Enhanced. Do not assume they are available in the published Workshop version.

## Installation and play

### Steam Workshop

1. [Subscribe to Campaign Reimagined](https://steamcommunity.com/sharedfiles/filedetails/?id=3686673790) and let Steam download it. Do **not** enable the item globally in the Mods menu.
2. Install the native patch using either the [OpenShimSetup.exe release installer](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/releases/latest/download/OpenShimSetup.exe) on Windows **or** **Single Player > Instant Action > ! SETUP / REPAIR - Open Community Patch** in-game.
3. **Exit Battlezone completely** after in-game setup so the verified native replacement can finish. Relaunch the game.
4. Open **Single Player > Custom Campaign > Campaign Reimagined** and select an entry included in your installed Workshop version.

The native suite installs game-root `winmm.dll` and `bzloader.dll`, `plugins/openshim.dll`, and matching configuration, patches, and resources. Existing player `openshim.ini` settings are preserved. Copying `winmm.dll` alone is **not** a complete installation. The setup mission can be rerun for verification or repair.

For setup failures, inspect `logs/openpatch_setup.log`, `logs/openshim_update.log` (normally under the game directory), and `openshim_update.status` in the game directory. Include these with a bug report. Refer to OpenShim's instructions for native patch removal.

### GOG and manual installations

The Steam subscription instructions do not install campaign assets for GOG. GOG/manual users need a compatible separately packaged campaign payload and the complete OpenShim native suite. This repository's `Manage-CampaignFiles.ps1 -deploy` command is a **maintainer development deployment**, not a general-purpose end-user installer. Follow the instructions accompanying a qualified manual distribution; do not copy individual DLLs from this repository as an installation shortcut.

## Repository layout

| Path | Purpose |
|---|---|
| `Scripts/`, `Missions/` | Mission ports, shared Lua systems, and map packages |
| `Bin/` | Bundled OpenShim, EXU, bzfile, loader/helper binaries, and symbols |
| `Assets/` (including `Assets/Textures/`), `ODF/`, `Materials/`, `Shaders/`, `Text/` | Gameplay assets, definitions, rendering content, and localization |
| `Config/`, `InstallerPayload/` | Campaign metadata, renderer configuration, and native install inputs |
| `Manage-CampaignFiles.ps1` | Maintainer deployment, validation, staging, and publishing |

## Development and publishing

This repository is the canonical campaign source. The maintained workflow is to validate here, deploy and test in the GOG development runtime, stage the verified Workshop payload, upload locally, then test the downloaded Steam copy. Never deploy development files into Steam's subscribed Workshop cache.

For a prepared update, use PowerShell 7:

```powershell
pwsh -File .\Manage-CampaignFiles.ps1 -prepare-update "Describe the fix"
```

Use `-reuse-native` for content-only changes when the existing qualified native builds are appropriate. Preparation does **not** publish anything. Workshop publication is a separate local maintainer action, not the GitHub Actions release-artifact workflow.

- [Update preparation](Docs/UPDATE_PREPARATION.md) and [Workshop publication checklist](docs/STEAM_PUBLISH_CHECKLIST.md)
- [Changelog](CHANGELOG.md) and [Workshop description source](docs/workshop_description.bbcode)
- [Agent knowledge base](Docs/AGENT_KNOWLEDGE_BASE.md) and [repository working rules](AGENTS.md)

## Reporting problems

Include the mission or game mode, expected versus observed behavior, reproduction steps, installed native modifications, and any relevant screenshots, logs, or save files. A reproducible sequence is especially valuable.

## Credits and rights

- **GrizzlyOne95:** Campaign maintenance, integration, and mission work.
- **VTrider:** Extra Utilities groundwork used throughout the addon stack.
- **OpenShim, Extra Utilities, bzfile, and Battlezone community contributors:** Supporting work across the integrated runtime.
- **NASA/JPL-Caltech:** Uranus image (Voyager 2, PIA18182); [sky art credits](Docs/SKY_ART_CREDITS.md).
- **99.Miles:** "Low Poly Forest Tree Pack" (Sketchfab), CC BY 4.0; [foliage art credits](Docs/FOLIAGE_ART_CREDITS.md).

This is a mixed-rights addon repository. The MIT terms in [LICENSE.md](LICENSE.md) apply only to clearly original project work; stock-derived assets, third-party content, and bundled binaries retain their respective rights. Consult the applicable asset credits and upstream projects before reusing those materials.

### AI-assisted development

AI coding tools help with drafting, analysis, testing, and documentation. Their output is not authoritative reverse-engineering evidence: native behavior and compatibility claims are checked against game binaries, runtime observations, and reproducible tests. Changes remain maintainer-directed and reviewed.
