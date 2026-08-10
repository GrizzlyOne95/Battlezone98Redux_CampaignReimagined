## Credits

- `GrizzlyOne95` for current addon maintenance, integration, and workspace stewardship.
- `VTrider` for EXU-side groundwork that this addon stack builds on.

## Steam Workshop publishing

The publisher is locked to Battlezone 98 Redux app `301650` and Workshop item
`3686673790`. It builds a clean payload under `Local/Workshop/content`; it never
uploads the live game directory and does not commit or push Git changes.

The required promotion order is canonical source -> GOG working test copy ->
Workshop upload -> Steam final verification. Development deploys target
`C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\mods\3686673790`.
The subscribed Steam Workshop folder is never a direct deploy target; Steam
testing begins only after the validated upload has been downloaded by Steam.

### GitHub Actions publishing

The repository includes a manual `Publish Steam Workshop` workflow. Publishing
is intentionally split between two machines:

1. A GitHub-hosted Windows runner checks out Campaign Reimagined, checks out and
   builds the selected OpenShim revision, creates the Workshop payload, validates
   required/forbidden files, and writes the SHA-256 content manifest.
2. A dedicated self-hosted Windows runner with cached SteamCMD authentication
   downloads only that validated artifact, verifies its manifest again, and
   uploads it to Steam.

The Steam-authenticated runner does not check out or compile repository code.
The workflow only runs through `workflow_dispatch`, refuses to publish anything
other than `main`, and uses a concurrency lock so two uploads cannot collide.

Setup instructions are in `docs/STEAM_WORKSHOP_RUNNER.md`. After the runner is
configured, publishing is:

```text
Actions -> Publish Steam Workshop -> Run workflow
```

Enter the Workshop change note, normally leave `openshim_ref` at `main`, and
choose whether the run is a dry run. Dry runs build and validate the complete
payload without contacting Steam and do not require the self-hosted runner.

The canonical Workshop description is tracked at
`docs/workshop_description.bbcode`. It is included in the upload metadata but
excluded from the Workshop content payload itself.

### Local publishing

Local publishing remains supported. When publishing from a Git checkout, use
`docs/Invoke-WorkshopPublisher.ps1` as the entrypoint. The legacy manager
recursively scans the repository, so the wrapper temporarily moves `.github/`
outside the source tree while it runs and restores it afterward. This prevents
GitHub workflow YAML from being flattened into the mod payload.

1. Copy `workshop.config.example.json` to the ignored
   `workshop.config.json`.
2. Set `SteamUser`, or define the `STEAM_USERNAME` environment variable.
3. Bootstrap SteamCMD authentication once:

   ```powershell
   .\docs\Invoke-WorkshopPublisher.ps1 -workshop-auth
   ```

4. Build and validate without uploading:

   ```powershell
   .\docs\Invoke-WorkshopPublisher.ps1 -workshop-build "Release candidate"
   ```

   The build refreshes `Bin/winmm.dll` from
   `Documents/GIT/BZR-OpenShim/bin/Release/winmm.dll` before generating the
   OpenShim manifest. Set `BZR_OPENSHIM_REPO` to override that repository path.

   Deploy the candidate to the GOG working test copy:

   ```powershell
   .\Manage-CampaignFiles.ps1 -deploy
   ```

   Validate the candidate in
   `C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux`. The manager
   must not fall back to a Steam install or subscribed Workshop cache.

5. Upload the GOG-validated payload:

   ```powershell
   .\docs\Invoke-WorkshopPublisher.ps1 -workshop-upload "Describe the update"
   ```

6. Let Steam download Workshop item `3686673790`, then perform final testing
   with `C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux` and
   its subscribed payload under
   `C:\Program Files (x86)\Steam\steamapps\workshop\content\301650\3686673790`.

### Description and visibility

Two SteamCMD behaviours are worth knowing, because both fail silently:

- `workshop_build_item` only understands an **inline** `description` key. A
  `descriptionfile` path is not a real key; SteamCMD discards it, reports
  `Committing update...Success.`, updates the content and leaves the published
  description untouched. `DescriptionFile` in `workshop.config.json` is read by
  the publisher and inlined for you from `docs/workshop_description.bbcode`.
- SteamCMD's KeyValues parser does **not** process escape sequences. Newlines
  are fine inside the quoted value, but a literal double quote ends it early and
  the upload dies with `got } in key in file workshopitem`. The publisher
  converts double quotes to apostrophes and tells you when it does.
- An upload that does not state a `visibility` leaves the item **hidden**, and a
  hidden item rejects the *next* upload at the commit step with nothing but
  `Failed to update workshop item (Access Denied)`. `Visibility` therefore
  defaults to `0` (public) so every publish reasserts it. If you ever do hit
  that error, set the item back to Public in the Steam client once and re-run
  the upload.

Steam passwords are never read from the JSON configuration. SteamCMD may ask
for a password and Steam Guard code during the authentication bootstrap, then
reuse its locally cached login for subsequent uploads. Generated content,
hash manifests, VDF files, receipts, and SteamCMD logs remain under the ignored
`Local/Workshop` directory during local publishing.
