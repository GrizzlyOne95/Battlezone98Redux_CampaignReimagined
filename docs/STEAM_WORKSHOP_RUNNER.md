# Steam Workshop publishing runner

Campaign Reimagined publishes Workshop item `3686673790` through the
`Publish Steam Workshop` GitHub Actions workflow.

## Promotion boundary

Before publishing, deploy and validate the candidate in the GOG working copy:

```text
C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux
C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\mods\3686673790
```

After the upload succeeds, let Steam download the subscribed item and perform
final verification with:

```text
C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux
C:\Program Files (x86)\Steam\steamapps\workshop\content\301650\3686673790
```

Do not copy development files directly into the Steam Workshop content folder.
It is a downloaded final-test artifact, not a working deploy directory.

The workflow deliberately splits publishing into two trust zones:

1. A GitHub-hosted Windows runner checks out Campaign Reimagined, checks out and
   builds OpenShim, stages the exact Workshop payload, validates it, writes a
   SHA-256 manifest, and uploads the validated bundle as a workflow artifact.
2. A dedicated self-hosted Windows runner downloads only that validated bundle,
   verifies every file against the manifest, generates the Steam VDF, and calls
   SteamCMD.

The Steam-authenticated runner does **not** check out or compile repository code.
This keeps the machine holding the cached Steam login as small and isolated as
possible.

## Recommended runner

Use a small dedicated Windows VM. It can be any of the following:

- a local Hyper-V or VMware VM that is powered on only when publishing;
- a small Azure/AWS/other Windows VM that is normally deallocated;
- a dedicated always-on Windows VPS if unattended publishing is important.

A local VM is the simplest zero-recurring-cost option. A cloud VM is useful if
Workshop publishing must work while the development PC is off.

Suggested minimums are 2 vCPU, 4 GB RAM, roughly 20 GB free disk space, and
outbound HTTPS access. The runner does not need Visual Studio or the Battlezone
installation. Compilation happens on GitHub's hosted runner.

Because this repository is public, do not use a normal workstation as the
self-hosted runner and do not put unrelated credentials on the runner VM.
GitHub recommends avoiding persistent self-hosted runners for public repositories;
this workflow reduces that exposure by using `workflow_dispatch` only, restricting
publishes to `main`, and never checking repository code out on the credentialed
runner.

## 1. Create a dedicated Windows account

Create a local account such as `SteamWorkshopRunner` on the VM. Use that same
Windows account for both the GitHub Actions runner service and the SteamCMD
login cache.

SteamCMD authentication is cached per Windows profile. If SteamCMD is
bootstrapped under one user while the Actions service runs under another, the
workflow may be asked to authenticate again.

## 2. Install SteamCMD

Install SteamCMD at:

```text
C:\steamcmd\steamcmd.exe
```

The workflow also checks several other common locations and `PATH`, but
`C:\steamcmd` is the recommended layout.

## 3. Register the GitHub Actions runner

In the repository, open:

```text
Settings -> Actions -> Runners -> New self-hosted runner
```

Choose Windows x64 and follow GitHub's generated installation commands. A
conventional location is:

```text
C:\actions-runner
```

Register the runner to this repository and add this custom label:

```text
steam-workshop
```

The workflow targets all four labels:

```text
self-hosted, windows, x64, steam-workshop
```

If the runner is installed as a Windows service, make sure the service's **Log
On** account is the same dedicated Windows account that will bootstrap
SteamCMD. The runner may also be run interactively for initial testing.

## 4. Bootstrap SteamCMD authentication once

Sign into Windows as the same account used by the runner service and run:

```powershell
C:\steamcmd\steamcmd.exe +login YOUR_STEAM_USERNAME +quit
```

Enter the password and Steam Guard code interactively when Steam requests them.
Do not put the password or Steam Guard secret in GitHub.

After a successful login, verify the cached session by running the same command
again. It should complete without requiring normal credentials.

Steam may eventually invalidate the cached machine session. If a Workshop job
starts failing at `+login`, sign into the runner account and repeat this
bootstrap step.

## 5. Configure the GitHub repository variable

Create a repository Actions variable:

```text
Settings -> Secrets and variables -> Actions -> Variables
```

Name:

```text
STEAM_USERNAME
```

Value: the Steam account name that owns or can update Workshop item
`3686673790`.

This is intentionally a GitHub **variable**, not a password secret. No Steam
password is required by the workflow.

## 6. Configure the publishing environment

Create the GitHub environment:

```text
steam-workshop
```

under:

```text
Settings -> Environments
```

For additional protection, configure a required reviewer for that environment.
The build/validation job can finish without approval, but the Steam upload job
will not start until the environment is approved.

## Publishing

Open:

```text
Actions -> Publish Steam Workshop -> Run workflow
```

Run it from `main` and enter:

- `change_note`: text shown in the Workshop update history;
- `openshim_ref`: normally `main`, but a specific OpenShim tag/SHA may be used;
- `dry_run`: when enabled, build and validate the complete payload without
  contacting Steam or requiring the self-hosted runner.

A normal publish performs this chain:

```text
Campaign main
  -> GitHub-hosted Windows build
  -> OpenShim Release build
  -> Workshop staging + validation
  -> SHA-256 manifest
  -> immutable workflow artifact
  -> steam-workshop self-hosted runner
  -> manifest revalidation
  -> SteamCMD
  -> Workshop item 3686673790
```

The `concurrency` lock prevents two Workshop publishes from running at the same
time.

## Runner availability

The self-hosted runner does not have to be online continuously. If using a
local or normally-deallocated VM, power it on before starting a real publish.
Dry runs do not use the self-hosted runner at all.

If the publish job is queued with a message that it is waiting for a runner,
check that the VM is online and the runner shows as **Idle** under:

```text
Settings -> Actions -> Runners
```

## What remains on the runner

The workflow deletes the downloaded Workshop payload and generated VDF after
an attempted publish. The only state intentionally retained between runs is the
GitHub runner installation and SteamCMD's local authentication/cache data.
