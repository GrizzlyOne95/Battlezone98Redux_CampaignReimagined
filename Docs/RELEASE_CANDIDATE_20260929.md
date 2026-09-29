# Campaign Reimagined release candidate — 2026-09-29

Status: prepared for review and package qualification. This is not a public
release or a completed Workshop publication. Candidate version: `2026.09.29-rc1`.

## Included work

The interrupted CodebaseAudit work is merged upstream: EXU #71/#72 and
OpenShim #374/#375/#365. This candidate adds the complete split native load
chain to campaign packaging and updates. OpenShim `1.0.0.34`, bzfile `1.1.0`
and EXU `1.3.0` are bundled. Setup installs game-root `winmm.dll` and
`bzloader.dll`, `plugins/openshim.dll`, `net.ini` and `scripts/patches.json`
as one verified transaction after exit. Player `openshim.ini` is preserved.

Review the companion source changes before merging:

- [OpenShim #382](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/pull/382)
- [bzfile #25](https://github.com/GrizzlyOne95/bzfile/pull/25)
- Campaign branch: `agent/cr-suite-release-20260929`.

The Setup map now uses the complete existing misn02b serialization with its
own terrain companions and script. The former minimal file failed to load.
Native BZN text must retain CRLF on every line; mixed header endings caused
a native reader failure in GOG. Git attributes and staging checks preserve
the format. Empty native fields intentionally retain their trailing space.

The primary OpenShim checkout's LensFlare shutdown prototype is preserved,
but excluded from this candidate. No shared history was rewritten.

## Validation completed

- OpenShim Win32 Release build, 64 Windows CTest checks, 56 Linux CTest
  checks, native loader lifecycle, uninstaller fixture, deployment verifier,
  INI policy and network baseline.
- bzfile native/API hardening and real Lua staging tests: fresh and existing
  installs of the exact candidate; legacy three-file replacement; complete
  five-file replacement; rollback with the final destination locked.
- Campaign Lua 5.1 tests and syntax, repository invariants, generated
  transcripts, setup map contract, program references, Enhanced shader
  checks and 232 DX11 shader compiles.
- Actual GOG `misn02b` campaign smoke, 40 seconds each with DX9 and DX11:
  native chain, EXU and bzfile loaded; terrain clutter created; clean exit;
  no Lua errors, new dumps or changed saved games.
- Actual GOG Setup smoke, 40 seconds with DX9: `update_staged` and
  `RESTART_REQUIRED`; after normal game exit the helper completed the entire
  five-file transaction and verified the installed hashes. Test settings,
  previous files and all 25 player saves were restored.

The local test evidence, including the failed Setup runs and subsequent
successful repair, is under
`../.research-archive/CR-release-20260929`. Private debugger output remains
local and is not part of the public source changes.

## Frozen packages and reproduction

The prepared package directory is
`../.research-archive/CR-release-20260929/Packages/2026.09.29-rc1`.
`candidate_receipt.json` records all four source commits, exact native hashes,
archive hashes and the content manifest identity. Workshop content and the
manual/ModDB archive contain the same 3,679 manifest-verified campaign files.
Native OpenShim, bzfile and EXU archives include matching symbols. The
directory also contains the change note and a snapshot of the canonical
Roadmap BBCode. Do not overwrite an existing frozen directory.

Run from the canonical campaign checkout with PowerShell 7:

```powershell
$env:BZR_OPENSHIM_REPO = "$env:USERPROFILE\Documents\GIT\BZR-OpenShim-cr-suite-release"
$env:BZR_BZFILE_REPO = "$env:USERPROFILE\Documents\GIT\bzfile-cr-suite-release"
$env:BZR_EXU_REPO = "$env:USERPROFILE\Documents\GIT\ExtraUtilities"
.\Manage-CampaignFiles.ps1 -workshop-build "Complete native suite, verified setup and rollback, EXU audit fixes, and DX11 compatibility updates."
.\Tools\Prepare-ReleaseCandidate.ps1 -OutputDir '<new output directory>' `
  -Version '2026.09.29-rc1' -ChangeNote '<reviewed change note>' `
  -OpenShimRepo $env:BZR_OPENSHIM_REPO -BzfileRepo $env:BZR_BZFILE_REPO `
  -ExuRepo $env:BZR_EXU_REPO
```

Commit tracked changes first. Staging refreshes Bin from the named sibling
builds; it must not fall back to the unrelated primary OpenShim prototype.
The candidate preparation checks all six runtime files against those builds,
checks suite ABI and source metadata, and verifies every file inside both
campaign ZIPs against the manifest.

## Remaining public release gates

1. Review and merge the three coherent source branches. Qualify and publish
   OpenShim's release before using its verified `OpenShim-Suite.zip` in a real
   Workshop upload. Candidate branch binaries are not a published release.
2. Record actual Windows/Steam, Steam/Proton and GOG/Wine runtime evidence.
   Linux host CTest is not a Proton or Wine gameplay test. This workstation
   does not have a Wine runtime available for those lanes.
3. Obtain explicit authorization for public tags/releases and Workshop
   publication. Use [the publication checklist](../docs/STEAM_PUBLISH_CHECKLIST.md),
   preserve the live item description unless replacement is deliberately
   requested, and use the reviewed change note.
4. After upload, synchronize the Steam Roadmap discussion with OpenShim's
   canonical BBCode, download the subscribed item and record the final Steam
   runtime result. An upload alone is not publication completion.

Do not describe this candidate as released, uploaded or fully qualified for
all supported platforms before those gates have evidence.
