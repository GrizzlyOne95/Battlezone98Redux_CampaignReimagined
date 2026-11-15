# Overnight soak runner

A debug tool for the "crash, sudden lighting change or freeze (NVIDIA driver reset)" hunt. It loops CR
missions for hours, leaves one evidence bundle per incident and one summary for the morning. It is not a
release gate and never ships (`Tools\` is excluded from the Workshop payload).

## Start it

Close everything that uses the GPU first, then from the repo root in Windows PowerShell 5.1:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\Soak\Invoke-OvernightSoak.ps1 -Hours 8
```

Check first without launching anything (creates and changes nothing):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\Soak\Invoke-OvernightSoak.ps1 -DryRun
```

Parameters: `-Hours` (8), `-PlanPath` (`Tools\Soak\soak-plan.psd1`), `-OutDir` (`Local\Soak\<timestamp>`),
`-Resolution` (`native` = desktop resolution, windowed, or `WxH`), `-MinutesPerMission` (15), `-DryRun`,
`-GameDir` (GOG install), `-MaxLaunches` (200).

## What it does

- Takes `bzr_livetest.lock` in the game folder (stops if it exists; the file names the holder), then the
  BZR-OpenShim harness (`BZRHarness.ps1`: machine-wide launch mutex, `Assert-BZRSafeToLaunch`,
  `OPENSHIM_NEVER_ACTIVATE=1` so it never takes focus). The harness repo must be at
  `%USERPROFILE%\Documents\GIT\BZR-OpenShim` or passed as `-HarnessPath`.
- Snapshots `logs\` and `Save\` into `<OutDir>\snapshot` before the first launch.
- Sets `Ogre.cfg` to windowed at the chosen resolution (backed up byte-exact; restored at the end, or by the
  harness on its next start if the run is killed).
- For each mission in the plan, in a loop: launches `<stem>.bzn /nointro /renderer:dx11` with
  `OPENSHIM_SOAK_TELEMETRY=1`, records the SHA-256 of `plugins\openshim.dll`, polls every 2 s, stops the game
  after `-MinutesPerMission` through `Stop-BZRGame` (graceful, never a force-kill), then starts the next.
  A route-`ini` mission has `mapType` flipped to `instant_action` for the run (original renamed aside and
  restored), so the mission's own Lua and the CR runtime run.
- Detects: crash (exit not caused by the soak, `openshim_crash_*`, dumps), hang (window not answering for
  the release gate's `HangSeconds`, plus `cdb` stacks), driver reset (System log `nvlddmkm` 153/13/14 and
  `Display` 4101), DX11 device recreations after the mission reached `Post Load` (startup ones are ignored),
  and the OpenShim telemetry lines `[GPUWATCH] stall`, `[SOAK] main-loop stalled`, `[LIGHTING] change`.
  Min and median FPS per run come from `[SOAK] heartbeat` lines.
- After a driver reset or hang it stops the game, waits 20 s for the GPU and moves on. Three failed
  launches in a row on one mission skip that mission; ten failed launches in total abort the soak.
  If the game ignores the close request it is left running and the soak aborts (nothing is force-killed).

## Morning

In `<OutDir>`:

- `summary.md` / `summary.json`: hours, launches, distinct missions, an incident table (time, mission, kind,
  the key line, for example the GPUWATCH `firstPending` stage), counts by kind, FPS per run.
- The FPS table splits each run into phases, so its numbers explain themselves: load seconds (run state 5 but
  no frames yet), in-mission seconds with min and median fps (only these count), when the mission stopped
  running (death, failure or end) and the seconds and fps of the end screen after it (the engine throttles
  that screen; about 19 fps in the background). "Slow stretches" lists every in-mission dip below half the
  run's median, with the stall and lighting lines within 10 s of it, or says there were none.
- One folder per incident, `<time>_<mission>_<kind>\`: `logs\` (openshim.log, BZLogger.txt,
  BZOgreLogfile.log, exu.log, crash logs and dumps changed since launch), `events.txt` (matching System-log
  entries), `captures\` (files named by `[LIGHTING] ... capture=`), `screenshot.png` when one could be taken,
  `incident.json` (kind, mission, time, dllHash, evidence lines). At most 3 bundles per kind per launch; the
  rest are counted as `suppressed` in `summary.json`.

## Limits

- The player is idle. Nothing drives the player, so only missions that start combat on their own exercise
  the renderer. Which plan entries do so is unverified (see `soak-plan.psd1`).
- The telemetry lines need an OpenShim build with SoakTelemetry. Without it only the crash, hang,
  driver-reset and DX11-recreation detectors work (`-DryRun` reports whether the installed DLL contains the
  switch).
- A hand-copied test `openshim.dll` lasts one launch: on exit CR's updater puts its bundled DLL back when the
  bytes differ. Ship the test build through CR's bundle for a full night. The runner warns, and notes it in
  `summary.md`, when the DLL hash changes between launches.
- Never run it while you play: it owns the game folder, the GOG mod's mission `.ini` files and the GPU.
- Screenshots use the same `PrintWindow` path as the release stress test and can be black while the desktop
  is locked or disconnected; the `[LIGHTING]` capture files are the reliable image.
- Only the `ini` route (stems of 8 characters or fewer) is implemented, not the `crsetup` slot swap.
- A native-resolution window may be clamped by Windows to the usable desktop area (untested).
- Tests for the parsers: `pwsh Tools\Soak\Test-OvernightSoak.ps1` (also run by `campaign-validation.yml`).
