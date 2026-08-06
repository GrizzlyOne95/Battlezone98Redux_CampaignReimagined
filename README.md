## Credits

- `GrizzlyOne95` for current addon maintenance, integration, and workspace stewardship.
- `VTrider` for EXU-side groundwork that this addon stack builds on.

## Steam Workshop publishing

The publisher is locked to Battlezone 98 Redux app `301650` and Workshop item
`3686673790`. It builds a clean payload under `Local/Workshop/content`; it never
uploads the live game directory and does not commit or push Git changes.

1. Copy `workshop.config.example.json` to the ignored
   `workshop.config.json`.
2. Set `SteamUser`, or define the `STEAM_USERNAME` environment variable.
3. Bootstrap SteamCMD authentication once:

   ```powershell
   .\Manage-CampaignFiles.ps1 -workshop-auth
   ```

4. Build and validate without uploading:

   ```powershell
   .\Manage-CampaignFiles.ps1 -workshop-build "Release candidate"
   ```

   The build refreshes `Bin/winmm.dll` from
   `Documents/GIT/BZR-OpenShim/bin/Release/winmm.dll` before generating the
   OpenShim manifest. Set `BZR_OPENSHIM_REPO` to override that repository path.

   For a local Steam test without uploading, deploy directly to the installed
   Workshop item:

   ```powershell
   .\Manage-CampaignFiles.ps1 -deploy
   ```

5. Upload the validated payload:

   ```powershell
   .\Manage-CampaignFiles.ps1 -workshop-upload "Describe the update"
   ```

### Description and visibility

Two SteamCMD behaviours are worth knowing, because both fail silently:

- `workshop_build_item` only understands an **inline** `description` key. A
  `descriptionfile` path is not a real key; SteamCMD discards it, reports
  `Committing update...Success.`, updates the content and leaves the published
  description untouched. `DescriptionFile` in `workshop.config.json` is now read
  by the publisher and inlined for you, so keep the canonical text in
  `Local/workshop_description.bbcode`. That path is excluded from staging, so it
  is not shipped inside the payload.
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
`Local/Workshop` directory.
