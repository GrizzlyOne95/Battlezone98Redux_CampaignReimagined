# Preparing a small update without an agent

Run from the canonical Campaign Reimagined checkout in PowerShell 7.

```powershell
# Build the three native projects, run local checks, deploy/test GOG and bundle.
.\Manage-CampaignFiles.ps1 -prepare-update "Fix <the player-visible problem>"

# A Lua/content-only fix: reuse the already built native DLLs.
.\Manage-CampaignFiles.ps1 -prepare-update "Fix <mission bug>" -reuse-native
```

The command runs incremental Win32 Release builds for OpenShim, bzfile/helper
and EXU; checks the complete three-DLL load chain; runs native regression,
installer/rollback, Lua 5.1, repository, material and DX11 shader checks;
deploys the full native chain and campaign to GOG; then runs bounded DX9,
DX11 and Setup smokes. It preserves player saves/settings and stops at a
failed step with a log path. Close the game normally before starting.

Outputs are under `Local/Releases/<timestamp-version>/`. `Packages/` contains
the frozen Workshop content/VDF, Workshop ZIP, manual/ModDB ZIP, OpenShim,
bzfile and EXU ZIPs, native/source identities and SHA-256 sidecars. Both
campaign ZIPs are checked file-by-file against the shipping manifest.
`Logs/`, `Runtime/` and `preparation_receipt.json` record what actually ran.
Existing runs are never overwritten. Failed runs remain available for diagnosis.

## One-time configuration

```powershell
.\Manage-CampaignFiles.ps1 -release-init
```

Edit the generated, gitignored `Local/release.config.json` to select native
checkouts. Blank paths use sibling `BZR-OpenShim`, `bzfile` and
`ExtraUtilities`. Explicit config fields take precedence for this preparation
command; blank fields use `BZR_OPENSHIM_REPO`, `BZR_BZFILE_REPO` and
`BZR_EXU_REPO` before the sibling defaults. This prevents an inherited
prototype path from displacing your release configuration. Other manager
actions keep their existing environment override behavior. `BZR_RELEASE_CONFIG`
can select a different config file. Origins and branches are printed in the
plan and receipt.
For the September 29 suite work, use `BZR-OpenShim-cr-suite-release` and
`bzfile-cr-suite-release` rather than the unrelated primary OpenShim prototype.

Required tools: PowerShell 7, Git, Python, CMake/CTest, Visual Studio 2022
with x86 C++ tools and Windows SDK. EXU needs MSVC 14.44 or later; the newest
installed compatible version is selected unless `ExuVCToolsVersion` is set.
Lua checks require **Lua 5.1**. Configure Windows `LuaExe`/`LuacExe`, or use
`lua5.1` in the default WSL distro. Lua 5.4 is rejected as a substitute.

The Workshop staging config is scaffolded if missing; a dry run does not
need Steam authentication. The usual shipping lock still applies. For new
shipped files, run `-bless` and review its diff first. No preparation command
silently approves removals or adds files to the lock.

## Useful switches

| Switch | Effect |
|---|---|
| `-version 2026.09.29-hotfix1` | Select the package label instead of a timestamp |
| `-output 'D:\Releases\hotfix1'` | Select a new run directory |
| `-reuse-native` | Skip rebuilding shipping DLLs; retain checks and fixtures |
| `-no-deploy` | Checks/bundles only; skips deployment and runtime smokes |
| `-no-smoke` | Build/check/deploy/bundle; record runtime validation as skipped |
| `-plan` | Show selected repositories and operations without building or writing |

Example:

```powershell
.\Manage-CampaignFiles.ps1 -prepare-update "Fix subtitle timing" `
  -reuse-native -version 2026.09.29-hotfix1 -plan
```

The interactive manager has the same action as menu option **7**. Use the
command line for an unattended preparation run.

Keep the selected checkouts unchanged while a preparation run is in progress.

## Before publication

Preparation accepts an explicitly marked working-tree candidate so a small
uncommitted fix can be built/tested. It records dirty source/cache files and
exact payload hashes. All five ZIPs are checked against their file manifests,
and the extracted OpenShim archive passes the native chain/ABI identity gate.
Review, commit and push coherent changes afterward;
the receipt's commit IDs alone do not reproduce dirty working changes.

This action does not commit, merge, tag, create a release or upload to Steam.
It records GOG evidence; Steam/Proton/Wine qualification and a verified,
qualified published OpenShim release remain separate gates. A direct Steam
CLI launch can start the stock mission unless the intended mod is actually
activated; require campaign-native module paths when counting a Steam pass.

Follow [the Workshop publication checklist](STEAM_PUBLISH_CHECKLIST.md) for
the real upload. Preserve the live item description by default, synchronize
the Roadmap discussion afterward, download the subscribed item and test the
Steam copy. A local preparation receipt is not a completed publication.
