# Campaign Reimagined

Campaign Reimagined is an experimental, unofficial overhaul and community patch for Battlezone 98 Redux. It is more than a mission pack: the Workshop payload combines rewritten campaign logic, shared Lua gameplay systems, replacement maps and assets, renderer content, and native engine extensions in one integrated distribution.

The project aims to preserve the identity and progression of the original campaign while making its missions more reliable, reactive, configurable, and maintainable. It also serves as the live integration environment for OpenShim, Extra Utilities, and bzfile features used by the campaign.

This project is not affiliated with or supported by Rebellion.

Windows/GOG, Windows/Steam, Linux/Steam via Proton, and Linux/GOG through a
compatible Wine/Proton prefix are maintained together. See the shared
[`BZR platform and distribution compatibility policy`](Docs/BZR_PLATFORM_COMPATIBILITY.md).

## Current scope

- The main rewrite and testing focus is currently `misn02b`, `misn03`, and `misn04`.
- Lua mission ports are present for `misn01` through `misn05`; custom map packages are included for `misn02b` through `misn05`.
- Missions outside the active focus may be playable but should not be assumed to have the same level of testing or completion.
- Native components currently target the 32-bit Windows build of Battlezone 98 Redux 2.2.301.
- The project remains experimental: native hooks, broad asset overrides, and evolving mission scripts can introduce incompatibilities or regressions.

## What it changes

- **Campaign scripting** — Lua ports and rewrites of early NSDF missions, repaired objective flow, safer save/load restoration, difficulty-aware encounters, and mission-specific stability fixes.
- **AI and combat behavior** — shared team AI, construction and economy management, command-safe wingman behavior, howitzer range assistance, targeting controls, stuck recovery, and configurable unit tuning.
- **PDA and mission UI** — a persistent multi-page PDA for combat, target, career, logistics, loadout, settings, and system information, with scalable Ogre overlays and mission-aware controls.
- **Persistent player systems** — autosaves, career statistics, per-unit loadout presets, interface preferences, lighting options, audio/alert settings, and gameplay-assistance toggles.
- **Subtitles and radio** — script-driven subtitle overlays, audio-duration data, pause-aware presentation, and improved handling of queued, repetitive, or stale unit dialogue.
- **Rendering and atmosphere** — enhanced and retro lighting modes, custom shaders and materials, terrain and sky controls, weather support, emissive vehicle states, star effects, and high-resolution HUD adjustments.
- **Native engine fixes** — OpenShim and Extra Utilities integrations for loader behavior, multiplayer stability, shader caching, native autosaves, HUD placement, radar scaling, reticle and weapon convergence, turbo, headlights, and restored legacy behaviors.
- **Content restoration and replacement** — repaired or replacement meshes, ODFs, textures, materials, flags, localized text, loading screens, and physical destruction chunks used by the integrated runtime.
- **Diagnostics and maintenance** — manifest-verified native payloads, safer patch validation, crash and replacement logs, local deployment tooling, Workshop staging checks, and reproducible publishing automation.

## How the package fits together

| Layer | Role |
|---|---|
| `Scripts/` and `Missions/` | Mission rewrites, shared AI, PDA, autosave, subtitles, persistence, weather, and runtime orchestration |
| `Bin/` | Bundled OpenShim (`winmm.dll`), Extra Utilities (`exu.dll`), bzfile, symbols, and replacement helper |
| `Assets/`, `ODF/`, `Materials/`, `Shaders/`, `Textures/`, `Text/` | Models, gameplay definitions, rendering resources, UI content, and localization overrides |
| `Config/` and `InstallerPayload/` | Mod metadata, shader settings, generated OpenShim configuration inputs, and installation payloads |
| `Manage-CampaignFiles.ps1` | Canonical source synchronization, GOG development deployment, Workshop staging, validation, and upload control |

OpenShim owns low-level loading and engine patches. Extra Utilities exposes native engine and Ogre functionality to Lua. bzfile supplies file access used by persistent campaign systems. Campaign Reimagined ties those layers to its missions and content; installing only the Lua files does not reproduce the complete experience.

## Installation

Subscribe to [Campaign Reimagined on Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3686673790), then launch one of its missions. The package installs or updates OpenShim by placing `winmm.dll` beside `battlezone98redux.exe`; restart the game when prompted because the loaded DLL cannot be replaced in place.

If automatic installation fails, check `winmm_replace.log` in the game directory. Other native DLL modifications should be removed before troubleshooting compatibility. To remove the native patch, delete the Campaign Reimagined `winmm.dll` from the Battlezone 98 Redux installation directory.

## Repository workflow

This repository is the canonical source tree. Development follows this promotion path:

1. Make and validate changes here.
2. Deploy to the GOG working runtime with `Manage-CampaignFiles.ps1 -deploy`.
3. Test against the GOG game installation.
4. Build and upload the validated Workshop payload.
5. Let Steam download item `3686673790`, then perform final Steam verification.

Do not deploy development files directly into Steam's Workshop download cache. `Local/Workshop` is generated staging, not a playable development runtime.

Useful references:

- [`CHANGELOG.md`](CHANGELOG.md) — recent player-facing and technical changes
- [`docs/workshop_description.bbcode`](docs/workshop_description.bbcode) — canonical public Workshop description
- [`docs/STEAM_WORKSHOP_RUNNER.md`](docs/STEAM_WORKSHOP_RUNNER.md) — publishing architecture and runner setup
- [`AGENTS.md`](AGENTS.md) — authoritative local paths and promotion rules

## Publishing

The manual **Publish Steam Workshop** GitHub Actions workflow builds OpenShim, stages the campaign, validates the content manifest, and hands the immutable payload to a dedicated Steam-authenticated runner. It is restricted to `main` and supports a dry-run mode.

Local builds and uploads use `docs/Invoke-WorkshopPublisher.ps1`, which wraps `Manage-CampaignFiles.ps1` so repository-only files are excluded from the flattened Workshop payload. Copy `workshop.config.example.json` to the ignored `workshop.config.json` before local publishing.

## Reporting problems

Include the mission or game mode, reproduction steps, expected and observed behavior, and any relevant screenshots, logs, or save files. Also identify other installed native modifications. Reports with a reproducible sequence are substantially easier to diagnose.

## Credits and rights

- **GrizzlyOne95** — current campaign maintenance, integration, mission work, and workspace stewardship.
- **VTrider** — Extra Utilities groundwork used throughout the addon stack.
- OpenShim, Extra Utilities, bzfile, and earlier Battlezone community contributors whose work supports the integrated runtime.

This is a mixed-rights addon repository. The MIT terms in [`LICENSE.md`](LICENSE.md) apply only to clearly original project work; bundled binaries, third-party files, and stock-derived game content retain their original rights as described in [`NOTICE.md`](NOTICE.md).
