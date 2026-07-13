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

Steam passwords are never read from the JSON configuration. SteamCMD may ask
for a password and Steam Guard code during the authentication bootstrap, then
reuse its locally cached login for subsequent uploads. Generated content,
hash manifests, VDF files, receipts, and SteamCMD logs remain under the ignored
`Local/Workshop` directory.
