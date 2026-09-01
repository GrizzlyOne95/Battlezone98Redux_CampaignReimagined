# Level 1 Campaign Release Pipeline

This pipeline prepares one immutable Campaign Reimagined payload and uses it for both Steam Workshop publishing and a ModDB-ready manual release. Level 1 intentionally does **not** submit the final ModDB web form.

## Workflow

Run **Publish Campaign Release** from GitHub Actions on `main` and provide:

- `version` — release identifier such as `1.4.0`.
- `change_note` — player-facing release notes used by Steam and the ModDB package.
- `openshim_ref` — OpenShim branch, tag, or SHA to build.
- `moddb_release_type` — `Full Version` or `Patch` for the ModDB submission metadata.
- `archive_drive` — when enabled, copy the prepared release into the configured synchronized Drive directory after Steam succeeds.
- `dry_run` — build and validate everything without publishing Steam or writing to the external archive.

The workflow remains restricted to `main`.

## Outputs

Every run builds and uploads a GitHub Actions artifact named like:

`campaign-release-1.4.0-<run-id>`

It contains the immutable Steam payload plus `level1_release/` with:

- `CampaignReimagined-<version>-ModDB.zip` — manual/ModDB installation archive.
- `CampaignReimagined-<version>-ModDB.zip.sha256` — checksum for the archive.
- `moddb_description.txt` — ready-to-paste ModDB description/change notes.
- `moddb_submission.json` — release type, suggested title, version, file hash/size, source commits, Steam IDs, and Drive target.
- `release_receipt.json` — machine-readable cross-channel release identity.
- `Open-ModDbHandoff.cmd` — validates the ZIP, copies the submission text, selects the archive in Explorer, and opens the trusted Mod DB page in Opera.

The ModDB ZIP is laid out so it can be extracted directly into the Battlezone 98 Redux installation directory. Its payload lands under `mods\3686673790`.

## Steam

When `dry_run=false`, the validated bundle is downloaded by the existing Steam-authenticated self-hosted runner pattern and uploaded to Workshop item `3686673790`. The job emits a separate Steam publication receipt.

The legacy **Publish Steam Workshop** workflow is deliberately left intact as a fallback. Future coordinated releases should use **Publish Campaign Release** so Steam and the ModDB-ready package are guaranteed to originate from the same validated content.

## Google Drive archive

The intended archive destination is the shared Drive folder:

`Open Patch - CampaignReimagined`

Folder ID:

`1vORbih4z8QKXTdwwzHfS_-81-izYW0uv`

GitHub Actions cannot use the ChatGPT Google Drive connector. Instead, the self-hosted Windows publishing runner copies the `level1_release` directory into a local Google Drive for Desktop synchronized path.

Configure the repository variable:

`CAMPAIGN_RELEASE_ARCHIVE_DIR`

Example only:

`G:\My Drive\Open Patch - CampaignReimagined\Releases`

Use the actual synchronized path on the Steam publishing runner. Each release is written to a new version subdirectory. Existing version directories are never overwritten.

If the variable is not configured, Steam publishing still succeeds and the complete release remains available as a GitHub Actions artifact; the archive job emits a warning and skips the Drive copy.

## ModDB submission

After the workflow succeeds:

1. Open the `level1_release` folder from the GitHub artifact or Drive archive.
2. Double-click `Open-ModDbHandoff.cmd`. It verifies the ZIP against `moddb_submission.json`, copies the ready-to-paste submission text to the clipboard, selects the ZIP in Explorer, and opens `https://www.moddb.com/members/grizzlyone95/downloads` in Opera. If Opera is unavailable, it uses the default browser.
3. On Mod DB, choose **Add file** and upload the already selected `CampaignReimagined-<version>-ModDB.zip`.
4. Paste/adapt the clipboard text into the title, version, classification, description, and change-log fields. The original field-by-field sources remain in `moddb_submission.json` and `moddb_description.txt`.
5. Review every field and complete the final ModDB submission manually.

For a command-line integrity check that does not open windows or change the clipboard:

```powershell
.\Invoke-ModDbHandoff.ps1 -ValidateOnly
```

The helper does not log in, upload, fill a web form, or click the final submit button. No ModDB credentials, cookies, CSRF values, or undocumented endpoints are stored in the repository or GitHub Actions.

## Release integrity

The workflow keeps the existing `content_manifest.sha256` validation and re-verifies that manifest before creating the ModDB ZIP. The release metadata records both the Campaign Reimagined commit and the exact OpenShim commit. This makes Steam, the manual ModDB package, and the archived release traceable to the same source payload.
