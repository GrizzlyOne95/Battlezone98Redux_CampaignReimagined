# Steam Workshop publish checklist

This checklist defines when a Campaign Reimagined Workshop publication is complete.
It applies to real uploads of Workshop item `3686673790`. Dry runs do not require
public Steam edits.

## Canonical public-text sources

Keep the different Steam surfaces separate:

| Surface | Canonical source |
|---|---|
| Workshop item description | `docs/workshop_description.bbcode` in Campaign Reimagined |
| Workshop update/change note | `change_note` supplied to the publish workflow |
| Project changelog | `CHANGELOG.md` in Campaign Reimagined |
| Roadmap discussion | `Docs/STEAM_ROADMAP_BBCODE.txt` in `GrizzlyOne95/Battlezone98Redux_Shim` |
| Stock bug fixes discussion | `Docs/STEAM_STOCK_FIXES_BBCODE.txt` in `GrizzlyOne95/Battlezone98Redux_Shim` |

Roadmap discussion:

`https://steamcommunity.com/workshop/filedetails/discussion/3686673790/216888303627073611/`

Stock bug fixes discussion:

`https://steamcommunity.com/workshop/filedetails/discussion/3686673790/564797239535461771/`

The OpenShim BBCode files are the canonical editable sources for those
discussions. Do not maintain second independent copies in Campaign Reimagined.

## How a publish actually runs

Publishing is a **local** run of `Manage-CampaignFiles.ps1` on the maintainer's
PC. It is not the GitHub Actions workflow: `Publish Steam Workshop` has never
run and no self-hosted `steam-workshop` runner exists, so that job would queue
forever. `Docs/STEAM_WORKSHOP_RUNNER.md` is a design document, not the process.

Run the actions non-interactively -- the bare script drops into a `Read-Host`
menu that cannot be driven headlessly:

```powershell
# once per machine: workshop.config.json is per-machine and gitignored,
# so a fresh clone never has one
.\Manage-CampaignFiles.ps1 -workshop-init

.\Manage-CampaignFiles.ps1 -workshop-build "<note>"    # dry run: stage + validate + upload plan, no Steam
.\Manage-CampaignFiles.ps1 -workshop-upload "<note>"   # real upload through the running Steam client
```

`-workshop-build` is a genuine dry run: it stages, validates, writes the
manifest and resolves the upload (helper, `steam_api.dll`, Steam sign-in)
without contacting Steam. Always run it first.

### The upload goes through the running Steam client, not SteamCMD

`-workshop-upload` and `-publish` upload through the desktop Steam client that
is already signed in, using the Battlezone98_Modding_Toolbox helper
`bztoolbox/modules/publishing/steamworks_helper.ps1`. That helper drives the
game's 32-bit `steam_api.dll` under 32-bit Windows PowerShell, so there is no
second login, password or Steam Guard prompt. Requirements:

- Steam is running and signed in with the account that owns item `3686673790`.
  The manager refuses to start otherwise.
- The toolbox is checked out at `Documents\GIT\Battlezone98_Modding_Toolbox`,
  or `BZR_TOOLBOX_REPO` points to it.
- A Battlezone 98 Redux `steam_api.dll` exists: the Steam or GOG game folder
  (`BZR_GAME_DIR`), the official uploader tool, or `BZ_STEAM_API_DIR`.

Only the content folder and the change note are sent. Title, description,
tags, preview and visibility are never passed, so Steam keeps its copies, and
the hand-edited description cannot be overwritten by a content push. The run
prints upload progress; a failed submit prints the decoded EResult (from the
toolbox's `steam_errors.py`) and exits 1. Logs go to
`Local\Workshop\steamclient_upload_*.log`, and a success writes
`Local\Workshop\last_upload.json`.

**Do not use SteamCMD on the maintainer's PC.** SteamCMD logs in as a second
session of the same account, and Steam signs the desktop client out ("Session
Replaced"); the 1.0.0.57 publish kicked the owner out of a running game. The
old SteamCMD path remains only as an explicit opt-in for a machine with no
desktop client: add `-steamcmd` to `-workshop-build` / `-workshop-upload`
(it needs `SteamUser` in `workshop.config.json` and a one-time
`-workshop-auth`). Only that path writes a VDF or honours `PublishDescription`.

### Call the manager directly, and prefer `-workshop-upload`

`-publish` and `-workshop-upload` dispatch to the same `Publish-All`, but
`-workshop-upload` is the safer thing to type. `publish` is an unambiguous
*prefix* of a PowerShell parameter name, so any wrapper or helper that declares
a parameter beginning with `Publish` binds `-publish "<change note>"` to that
parameter instead of forwarding it. `Docs\Invoke-WorkshopPublisher.ps1` did
exactly that: the manager received only the change note, matched no action, fell
through to the interactive menu, and exited 0. Nothing was staged and nothing
was uploaded, but the call looked like a success.

That wrapper is no longer part of the repository -- the manager excludes
repository-only material from staging by itself. If a copy is still sitting in
your working tree from an older checkout, delete it rather than running it, and
invoke `Manage-CampaignFiles.ps1` directly.

The manager no longer covers for a mistake like this: an action it does not
recognize prints every argument it received, lists the supported actions, and
exits 2. Only a genuinely argument-less run opens the menu.

### Confirming that an upload actually happened

Do not judge a publish by its exit code alone. Check what the run printed:

| Output | Meaning |
|---|---|
| `Uploading app 301650 item 3686673790 to Steam Workshop through the running Steam client...` | The real upload path ran. |
| `Workshop upload succeeded for item 3686673790 (EResult 1).` | Steam accepted the update. |
| `Workshop upload FAILED. Nothing was published.` | Steam rejected it; the decoded reason follows. Exit 1. |
| `Campaign Reimagined - Mod Manager` banner | The run fell into the interactive menu. **Nothing was staged and nothing was uploaded.** |
| `Unrecognized action: ...` | The action never reached the manager. Nothing ran. |

A publish that never printed the `Workshop upload succeeded for item 3686673790`
line is not a publish. Re-run it before reporting the publication as complete.

### The shipping lock will stop you

Staging only ships files listed in `Shipping/shipping.lock.json`. A file added
to the repo since the last bless is silently excluded -- and because the
staging validator separately *requires* certain files, the run then fails with
`Workshop staging is missing required file '...'` rather than naming the lock
as the cause. The fix is `-bless`, which rebuilds the lock and prints every
file it admits:

```powershell
.\Manage-CampaignFiles.ps1 -bless
```

`-bless` decides what lands in players' installs, so read the list before
committing `Shipping/shipping.lock.json`. Treat a required file appearing in
the unlocked list as a stale lock rather than a reason to hand-edit either one.

### Prerequisite: a qualified OpenShim release

The bundled OpenShim comes from a published release of
`Battlezone98Redux_Shim`, verified by SHA-256 against
`OpenShim-Suite.zip.sha256`. Tag and release OpenShim first (pushing a `v*`
tag runs its `Build and Release` workflow); a branch or an untagged build
cannot be published.

The first OpenShim release that contains the updater trust chain
(Battlezone98Redux_Shim #254) must ship in a publish whose manifest carries
the `helper` entry for `bzfile_replace_helper.exe` (this repository's #106).
A #254 shim refuses any package without that entry, so never publish one
without the other.

## Before a real Workshop upload

1. Confirm the candidate has completed the normal GOG deploy/test path.
2. Update `CHANGELOG.md` for player-facing changes included in the candidate.
3. Review `docs/workshop_description.bbcode` against the live Steam
   description. The default upload never sends the description: it is edited
   by hand on Steam between releases, and a content push must not revert those
   edits. Change it on Steam directly. (Only the `-steamcmd` path can replace
   it, and only with `PublishDescription: true`; re-snapshot the live text
   first, see `docs/workshop_description.published-*.bbcode`. Steam rejects a
   description over 8000 characters.)
4. Review all OpenShim, EXU, bzfile, and CR changes entering the upload against
   `Battlezone98Redux_Shim/Docs/STEAM_ROADMAP_BBCODE.txt`.
5. Update the roadmap BBCode so completed work, changed implementation status,
   newly discovered constraints, and newly relevant roadmap items accurately
   reflect the build being published.
6. Review the OpenShim changes entering the upload for fixes to confirmed stock
   defects (new `[Fixes]` settings in `openshim.ini`, crash fixes, stock Lua
   binding repairs) and add each one to
   `Battlezone98Redux_Shim/Docs/STEAM_STOCK_FIXES_BBCODE.txt` under its
   section. Mark fixes that switch off in network games `[i](SP)[/i]`. List
   only fixes that ship in the build being published.
7. Supply a concise `change_note` describing the actual Workshop update.

A real publish should not knowingly ship roadmap-relevant changes or new stock
fixes while leaving `STEAM_ROADMAP_BBCODE.txt` or `STEAM_STOCK_FIXES_BBCODE.txt`
stale.

## After the Workshop upload succeeds

1. Open the Steam Roadmap discussion:
   `https://steamcommunity.com/workshop/filedetails/discussion/3686673790/216888303627073611/`
2. Edit the discussion post.
3. Replace its body with the complete current contents of
   `Battlezone98Redux_Shim/Docs/STEAM_ROADMAP_BBCODE.txt`.
4. Save the Steam post and verify the rendered discussion matches the canonical
   BBCode source closely enough that no section was truncated, reverted, or
   accidentally reformatted.
5. Do the same for the stock bug fixes discussion
   (`https://steamcommunity.com/workshop/filedetails/discussion/3686673790/564797239535461771/`)
   with the complete current contents of
   `Battlezone98Redux_Shim/Docs/STEAM_STOCK_FIXES_BBCODE.txt`.
6. Let Steam download Workshop item `3686673790` and perform the normal final
   Steam runtime verification.

**The Workshop publication is not considered complete until the Roadmap and
 stock bug fixes discussions have been synchronized.**

Even when an upload does not materially change roadmap status or add a stock
fix, perform the synchronization check. The live Steam posts should never be
allowed to drift from their canonical `STEAM_ROADMAP_BBCODE.txt` and
`STEAM_STOCK_FIXES_BBCODE.txt` sources.

## Publication completion record

When reporting that a Workshop publish is complete, include all of the
following:

- Workshop upload succeeded (the run printed `Uploading app 301650 item
  3686673790 to Steam Workshop...`);
- Workshop change note used;
- Roadmap BBCode reviewed/updated;
- Steam Roadmap discussion synchronized;
- stock fixes BBCode reviewed/updated, and the stock bug fixes discussion
  synchronized;
- subscribed Workshop item downloaded for final verification;
- final Steam test result.

If the upload succeeds but either discussion cannot be updated, report the
publication as **uploaded but not fully synchronized**, with each missing
discussion update left as an explicit outstanding action.
