# Release stress test (the release gate)

A player who plays many modes in one game launch must hit no bug, hang, slowdown or leak.
`Tools\ReleaseStress\Invoke-ReleaseStress.ps1` checks that on the installed candidate. **Every new
Workshop release needs a passing run on the exact candidate** (same commit, same `Bin\` hashes).
`Manage-CampaignFiles.ps1 -workshop-upload` refuses without one. Only a hotfix may skip it, with a
recorded reason.

## What it covers

One command, non-interactive, Windows PowerShell 5.1, roughly 25 minutes. It drives the game through
OpenShim's UI trigger harness (`[Diagnostics] UiPerformanceLogging=true`: it polls
`<gamedir>\uiperf_trigger.txt`, finds the named button on the active screen and invokes it), not pixel
clicks. The only pixel clicks are the campaign/map list boxes and the game-name field, which the
harness cannot address.

1. **Preflight.** Refuses if the game is running. Backs up `openshim.ini` and `Ogre.cfg` byte-exact,
   applies temporary settings (UiPerformanceLogging, windowed 1280x720 for the active render system,
   RunInBackground, RawMouseInput=0, NoAuthLan) and records versions, hashes, CR HEAD and
   `OPENSHIM_PIN`. The installed natives and mod must equal this checkout's `Bin\` and the shipping lock
   (`Manage-CampaignFiles.ps1 -verify`): the install has to *be* the candidate.
2. **Cold start.** Moves `shader_cache` aside, launches, requires a usable main menu within the budget
   (a cold-cache startup deadlock shipped once), quits. The regenerated cache is kept.
3. **Main run, ONE launch.** Every Options page and every OpenShim options category, Main-menu pages,
   Multiplayer (LAN host, lobby, staging, ready toggle, stop host), every Single Player submenu, the
   Custom Campaign list and Campaign Reimagined enter/back-out, then five back-to-back missions
   (stock campaign, two CR missions, a CR Black Dog co-op-capable mission, Instant Action), each
   ~60 s, aborted through ESC > Abort Mission, and a clean menu quit (exit code 0).
4. **Throughout.** A sampler writes private bytes, working set, handles, GDI, USER, threads, CPU and
   window responsiveness every ~1.5 s (`monitor.csv`). A snapshot is taken at every main-menu return.
5. **Post run.** Scans every log, checks for new crashes/dumps, re-hashes the installed DLLs, restores
   and SHA-verifies the settings.

Multiplayer limit: the stock lobby refuses to launch with fewer than 2 players
("Need 2 players to launch"), so a solo run ends at the staging screen. A true MP launch needs a second
client (the `C:\BZRCoop` rig); this harness does not drive one.

## Running it

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\ReleaseStress\Invoke-ReleaseStress.ps1
```

The tree must have no uncommitted tracked changes for a PASS to qualify (`last-pass.json` is not written
otherwise). Debug switches (`-SkipCold`, `-OnlyPhases a,b`, `-MissionSeconds N`) mark the run PARTIAL and
it can never qualify. If a run was killed hard, the next run (or `-Restore`) first restores the settings
from `Local\ReleaseStress\pending-restore.json`. Do not touch the game or move the mouse while it runs;
it never takes focus (`OPENSHIM_NEVER_ACTIVATE`, `NEVER_CAPTURE_MOUSE`).

## Reading the result

`Local\ReleaseStress\<timestamp>\report.md` starts with PASS or FAIL, then candidate identity, anomalies
(kind, step, detail, screenshot), the per-step table (budget, actual wall seconds, engine ms from the
`[UIPERF] transition end` line, max unresponsive stretch), resources at each menu return, and per-log
anomaly counts. Also: `steps.csv`, `monitor.csv`, `snapshots.csv`, `logs\<phase>\` (a copy of every
scanned log), `stacks\` (cdb all-thread stacks of any hang), `shots\`, `install-verify.txt`.

A PASS writes `Local\ReleaseStress\last-pass.json` (`cr_head`, `openshim_pin`, `bin_hashes`,
installed hashes, timestamp, report). `Local\` is gitignored.

Failure kinds: `HANG` (window unresponsive longer than `HangSeconds`, or no progress with idle CPU: stacks
captured, process killed), `SLOW` (step over budget), `UNRESPONSIVE` (single stretch over
`UnresponsiveSeconds`), `LEAK` (growth over the limit and monotonic across mission returns: private
+250 MB, handles +200, GDI/USER +50, threads +20, first mission return is the warm-up), `LOG`
(unexplained log line), `CRASH` (new `openshim_crash_*` or dump), `QUIT` (no clean exit/code 0),
`CANDIDATE` (installed bits are not this checkout), `DLLCHANGED`, `SETTINGS`, `STEP`/`STUCK`/`STATE`
(UI did not do what the plan expects), `FPS` (min FPS line under `MinFps`).

## Log scan

Every `*.log` / `*.txt` (and dumps) under the game dir, `logs\`, `exu\`, `openshim\` and the mod folder
modified since the run started is discovered by timestamp, so a new log cannot slip past, copied into
the run folder and scanned. That covers `BZLogger.txt`, `BZOgreLogfile.log`, `openshim.log`, `exu.log`,
`openshim_update.log`, `openshim_crash_*.log` and CR Lua output. A line is an anomaly when it matches
error / exception / fail / assert / warning / `[SKIP]` / not found / cannot / could not / timeout / crash
/ leak / missing / invalid / unsupported and similar (see `$AnomRe`), `Frame Rate Dropped Lower Than`,
plus per-log extras: Ogre (`OGRE EXCEPTION`, missing materials/textures/meshes, shader compile errors)
and BZLogger (Lua errors, stack tracebacks). Unexplained signatures (numbers and hex normalised) fail the
run, with the count per log in the report.

## Editing the plan, budgets and baseline

* **Steps:** `Tools\ReleaseStress\plan.psd1`, plain data. Find a button name by writing `__ENUMERATE__` to
  `uiperf_trigger.txt` with `UiPerformanceLogging=true` and reading the `ui depth=` lines in
  `logs\openshim.log`. Add a hashtable with `Group`, `Name`, `Do` (`click`, `back`, `clickxy`, `text`, `key`,
  `wait`, `snapshot`, `mission`) and its keys. Each group must start and end on the main menu.
* **Budgets and growth limits:** the `Budgets` table in the same file. Do not loosen a budget to make a
  run pass: a breach is a finding.
* **Known warnings:** `Tools\ReleaseStress\known-warnings.txt`, one entry per line:
  `<log glob> ::: <regex> ::: <one-line reason>`. Keep entries narrow. A baseline entry is for something
  understood and accepted, never for an unfixed defect.

## Hotfix exception

A hotfix may skip the gate:

```powershell
.\Manage-CampaignFiles.ps1 -workshop-upload "<change note>" -hotfix "<why the stress test is skipped>"
```

The reason is printed, appended to the change note and written to
`Local\Workshop\release_gate_override.json`. `-workshop-build` (dry run) prints the gate status but never
fails on it.
