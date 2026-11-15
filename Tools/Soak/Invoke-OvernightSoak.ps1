<#
.SYNOPSIS
    Unattended overnight soak: loops CR missions for hours and keeps an evidence bundle per incident
    (crash, hang, GPU driver reset, GPU/main-loop stall, lighting jump) plus one morning summary.
.DESCRIPTION
    Debug tool; never ships (Tools\ is excluded from the Workshop payload). See Docs/OVERNIGHT_SOAK.md.
    Windows PowerShell 5.1. The player stays idle: nothing drives the player.
    Reuses Tools\ReleaseStress\ReleaseStress.Lib.ps1 (window ping, log reading, log copy, cdb stacks,
    Ogre.cfg editing) and the BZR-OpenShim harness (launch lock, safe-launch guard, CreateProcess with
    SW_SHOWNOACTIVATE, graceful Stop-BZRGame; the game is never force-killed).
.PARAMETER Hours             Wall-clock length of the soak (default 8).
.PARAMETER PlanPath          Mission list (default Tools\Soak\soak-plan.psd1).
.PARAMETER OutDir            Evidence folder (default Local\Soak\<timestamp>).
.PARAMETER Resolution        'native' (desktop resolution, windowed) or WxH.
.PARAMETER MinutesPerMission Run time per launch (default 15).
.PARAMETER DryRun            Print the plan and check prerequisites; launches nothing, changes nothing.
#>
[CmdletBinding()]
param(
    [double]$Hours = 8,
    [string]$PlanPath = '',
    [string]$OutDir = '',
    [string]$Resolution = 'native',
    [int]$MinutesPerMission = 15,
    [switch]$DryRun,
    [string]$GameDir = 'C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux',
    [string]$HarnessPath = '',
    [string]$CdbPath = 'C:\Program Files\WindowsApps\Microsoft.WinDbg_1.2606.22001.0_x64__8wekyb3d8bbwe\x86\cdb.exe',
    [int]$MaxLaunches = 200
)
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $PlanPath) { $PlanPath = Join-Path $PSScriptRoot 'soak-plan.psd1' }
if (-not $HarnessPath) { $HarnessPath = Join-Path $env:USERPROFILE 'Documents\GIT\BZR-OpenShim\reverse_engineering\BZRHarness.ps1' }
. (Join-Path $PSScriptRoot 'Soak.Lib.ps1')
. (Join-Path $RepoRoot 'Tools\ReleaseStress\ReleaseStress.Lib.ps1')   # RS.Native, Read-LogFrom, Copy-LogsSince, Save-Stacks, Set-OgreVideo, Get-Sha256

$Exe       = Join-Path $GameDir 'battlezone98redux.exe'
$LogsDir   = Join-Path $GameDir 'logs'
$ModDir    = Join-Path $GameDir 'mods\3686673790'
$DllPath   = Join-Path $GameDir 'plugins\openshim.dll'
$OgrePath  = Join-Path $GameDir 'Ogre.cfg'
$LockPath  = Join-Path $GameDir 'bzr_livetest.lock'
$OgreBackup = Join-Path $GameDir 'ogre.cfg.bzrharness-backup'   # the harness restores an orphan of this name on its next start
$RsPlan    = Import-PowerShellDataFile -LiteralPath (Join-Path $RepoRoot 'Tools\ReleaseStress\plan.psd1')
$HangSeconds = [double]$RsPlan.Budgets.HangSeconds     # same hang threshold as the release gate
$ReadyTimeoutS = 300
$SettleS = 20
$MaxBundlesPerKindPerRun = 3
$PollS = 2

# ------------------------------------------------------------------ resolve --
function Get-DesktopSize {
    Add-Type -AssemblyName System.Windows.Forms
    # RS.Native's static constructor calls SetProcessDPIAware, but only on first member access: touch it
    # first, or a scaled desktop (4K at 150%) reports 2560x1440 and the soak runs below native.
    [void][RS.Native]::Hung([IntPtr]::Zero)
    $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    @{ W = $b.Width; H = $b.Height }
}
if ($Resolution -ieq 'native') { $sz = Get-DesktopSize; $ResW = [string]$sz.W; $ResH = [string]$sz.H }
elseif ($Resolution -match '^(\d{3,5})x(\d{3,5})$') { $ResW = $Matches[1]; $ResH = $Matches[2] }
else { throw "-Resolution must be 'native' or WxH, got '$Resolution'" }

$Plan = Import-PowerShellDataFile -LiteralPath $PlanPath
$Missions = @($Plan.Missions)
if ($Missions.Count -eq 0) { throw "plan has no missions: $PlanPath" }
foreach ($m in $Missions) {
    if (-not $m.Name -or @('ini', 'direct') -notcontains $m.Route) { throw "bad plan entry (need Name and Route ini|direct): $($m | ConvertTo-Json -Compress)" }
    if ($m.Route -eq 'ini' -and $m.Name.Length -gt 8) { throw "plan entry '$($m.Name)': route 'ini' needs a stem of 8 characters or fewer" }
}

# ------------------------------------------------------------ prerequisites --
function Test-Prerequisites {
    $r = New-Object System.Collections.Generic.List[object]
    function Add-Check([string]$What, [bool]$Ok, [string]$Detail = '', [bool]$Blocking = $true) { $r.Add([pscustomobject]@{ What = $What; Ok = $Ok; Detail = $Detail; Blocking = $Blocking }) }
    Add-Check 'game exe' (Test-Path -LiteralPath $Exe) $Exe
    Add-Check 'openshim.dll' (Test-Path -LiteralPath $DllPath) "$DllPath sha256 $(Get-Sha256 $DllPath)"
    if (Test-Path -LiteralPath $DllPath) {
        $bytes = [IO.File]::ReadAllBytes($DllPath)
        $hay = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
        Add-Check 'SoakTelemetry in this openshim.dll' ($hay.Contains('OPENSHIM_SOAK_TELEMETRY')) 'optional: without it only crash/hang/driver-reset/recreation detection works' $false
    }
    Add-Check 'Ogre.cfg' (Test-Path -LiteralPath $OgrePath) $OgrePath
    Add-Check 'no stale bzr_livetest.lock' (-not (Test-Path -LiteralPath $LockPath)) $(if (Test-Path -LiteralPath $LockPath) { "held by: $("$(Get-Content -LiteralPath $LockPath -Raw -ErrorAction SilentlyContinue)".Trim())" } else { '' })
    $running = @(Get-Process -Name battlezone98redux -ErrorAction SilentlyContinue | Where-Object { $_.Path -and ($_.Path -ieq $Exe) })
    Add-Check 'game not already running from this install' ($running.Count -eq 0) "$($running.Count) running"
    Add-Check 'BZRHarness.ps1' (Test-Path -LiteralPath $HarnessPath) $HarnessPath
    if (Test-Path -LiteralPath $HarnessPath) {
        $errs = $null; [void][Management.Automation.Language.Parser]::ParseFile($HarnessPath, [ref]$null, [ref]$errs)
        Add-Check 'BZRHarness.ps1 parses' (-not $errs -or $errs.Count -eq 0) ''
    }
    Add-Check 'cdb (hang stacks)' (Test-Path -LiteralPath $CdbPath) $CdbPath $false
    foreach ($m in $Missions) {
        $bzn = Join-Path $ModDir "$($m.Name).bzn"; $ini = Join-Path $ModDir "$($m.Name).ini"
        Add-Check "mission $($m.Name) ($($m.Route)) files" ((Test-Path -LiteralPath $bzn) -and ($m.Route -ne 'ini' -or (Test-Path -LiteralPath $ini))) "$bzn$(if ($m.Route -eq 'ini') { ' + .ini' })"
        if ($m.Route -eq 'ini' -and (Test-Path -LiteralPath $ini)) {
            $txt = $script:Latin1.GetString([IO.File]::ReadAllBytes($ini))
            Add-Check "mission $($m.Name) ini has a quoted mapType" ($txt -match '(?im)^\s*mapType\s*=\s*"[^"]*"') ''
        }
        Add-Check "mission $($m.Name) no stale .soakbak" (-not (Test-Path -LiteralPath "$ini.soakbak")) "$ini.soakbak"
    }
    $r
}

if ($DryRun) {
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    Write-Host "DRY RUN: nothing is launched, locked or written."
    Write-Host ("Hours={0}  MinutesPerMission={1}  Resolution={2}x{3} (windowed)  GameDir={4}" -f $Hours, $MinutesPerMission, $ResW, $ResH, $GameDir)
    Write-Host ("OutDir would be: {0}" -f $(if ($OutDir) { $OutDir } else { Join-Path $RepoRoot "Local\Soak\$stamp" }))
    Write-Host "Plan ($PlanPath), looped until time runs out:"
    $i = 0; foreach ($m in $Missions) { $i++; Write-Host ("  {0}. {1,-10} route={2,-6} minutes={3}" -f $i, $m.Name, $m.Route, $(if ($m.Minutes) { $m.Minutes } else { $MinutesPerMission })) }
    $perLoop = ($Missions | ForEach-Object { if ($_.Minutes) { [double]$_.Minutes } else { $MinutesPerMission } } | Measure-Object -Sum).Sum
    Write-Host ("One pass = {0} min; about {1:N1} passes in {2} h (plus startup/settle time)." -f $perLoop, ($Hours * 60 / $perLoop), $Hours)
    Write-Host 'Env per launch: OPENSHIM_SOAK_TELEMETRY=1 OPENSHIM_NEVER_ACTIVATE=1 OPENSHIM_NEVER_CAPTURE_MOUSE=1'
    Write-Host 'Prerequisites:'
    $bad = 0
    foreach ($c in (Test-Prerequisites)) {
        $tag = if ($c.Ok) { 'ok  ' } elseif ($c.Blocking) { 'FAIL' } else { 'warn' }
        if (-not $c.Ok -and $c.Blocking) { $bad++ }
        Write-Host ("  [{0}] {1}{2}" -f $tag, $c.What, $(if ($c.Detail) { " -- $($c.Detail)" } else { '' }))
    }
    if ($bad) { Write-Host "$bad blocking prerequisite(s) failed; a real run would refuse to start." -ForegroundColor Yellow; exit 2 }
    Write-Host 'All blocking prerequisites pass.'
    return
}

# ================================================================ real run ====
$blocking = @(Test-Prerequisites | Where-Object { -not $_.Ok -and $_.Blocking })
if ($blocking.Count) { throw ("prerequisites failed: " + (($blocking | ForEach-Object { "$($_.What) ($($_.Detail))" }) -join '; ')) }

if (-not $OutDir) { $OutDir = Join-Path $RepoRoot ("Local\Soak\" + (Get-Date).ToString('yyyyMMdd-HHmmss')) }
$null = New-Item -ItemType Directory -Force -Path $OutDir
$SoakStart = Get-Date
$Runs = New-Object System.Collections.Generic.List[object]
$Incidents = New-Object System.Collections.Generic.List[object]
$script:GamePid = 0
$script:LockTaken = $false
$script:OgreChanged = $false
$script:IniSwapped = @()
$script:KeepLock = $false   # set when the game would not close: it still owns the folder
$script:FirstDllHash = $null; $script:DllSwapWarned = $false; $script:DllSwapNote = $null   # CR updater swap detection
$script:BundleSeq = 0
$PreForceWindowed = $env:BZR_FORCE_WINDOWED
$PreLockHeld = $env:BZR_LAUNCH_LOCK_HELD
$SavedEnv = @{}
$Note = ''

function Write-Summary([string]$Why = '') {
    $s = New-SoakSummary $SoakStart (Get-Date) $Runs $Incidents $Why
    ($s | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $OutDir 'summary.json') -Encoding UTF8
    (ConvertTo-SummaryMarkdown $s) | Set-Content -LiteralPath (Join-Path $OutDir 'summary.md') -Encoding UTF8
}

function Restore-Ini {
    # Entries that fail stay listed, so the outer finally keeps the lock instead of hiding a .soakbak.
    $left = @()
    foreach ($e in @($script:IniSwapped)) {
        try {
            if (Test-Path -LiteralPath $e.Bak) {
                if (Test-Path -LiteralPath $e.Path) { Remove-Item -LiteralPath $e.Path -Force }
                Move-Item -LiteralPath $e.Bak -Destination $e.Path
            }
        } catch { Write-Warning "COULD NOT RESTORE $($e.Path): original is at $($e.Bak)"; $left += $e }
    }
    $script:IniSwapped = $left
}

function Set-SoakEnv([hashtable]$Vars) {
    foreach ($k in $Vars.Keys) { if (-not $SavedEnv.ContainsKey($k)) { $SavedEnv[$k] = [Environment]::GetEnvironmentVariable($k) }; [Environment]::SetEnvironmentVariable($k, $Vars[$k]) }
}
function Restore-SoakEnv { foreach ($k in @($SavedEnv.Keys)) { [Environment]::SetEnvironmentVariable($k, $SavedEnv[$k]) }; $SavedEnv.Clear() }

try {
    # ---- 1. our lock first (exclusive create), then the harness, whose dot-source takes the machine-wide launch mutex
    try {
        $fs = [IO.File]::Open($LockPath, 'CreateNew', 'Write', 'Read')
    } catch [IO.IOException] {
        throw "bzr_livetest.lock exists: $("$(Get-Content -LiteralPath $LockPath -Raw -ErrorAction SilentlyContinue)".Trim()). Not touching the game."
    }
    $script:LockTaken = $true   # the file is ours from CreateNew on, even if the write below fails
    try {
        $b = [Text.Encoding]::UTF8.GetBytes("Invoke-OvernightSoak.ps1 pid $PID started $($SoakStart.ToString('s')) out=$OutDir`r`n")
        $fs.Write($b, 0, $b.Length)
    } finally { $fs.Dispose() }
    $GameRoot = $GameDir   # read by the harness at dot-source (orphaned Ogre.cfg recovery)
    # The harness's own BZR_FORCE_WINDOWED path would take the Ogre.cfg backup first and ours would
    # then overwrite it with the windowed copy, losing the original. We set the mode ourselves.
    $env:BZR_FORCE_WINDOWED = $null
    Set-SoakEnv @{ OPENSHIM_NEVER_ACTIVATE = '1'; OPENSHIM_NEVER_CAPTURE_MOUSE = '1' }
    . $HarnessPath
    Assert-BZRSafeToLaunch

    # ---- 2. snapshot logs and saves before the first launch
    $snap = Join-Path $OutDir 'snapshot'
    foreach ($n in 'logs', 'Save') { $src = Join-Path $GameDir $n; if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $snap $n) -Recurse -Force -ErrorAction Continue } }
    Write-Host "Snapshot of logs\ and Save\ in $snap"

    # ---- 3. windowed Ogre.cfg at the chosen resolution (byte-exact backup under the harness's orphan name)
    # The harness restored any orphan at dot-source, so a backup here means something else holds it.
    if (Test-Path -LiteralPath $OgreBackup) { throw "$OgreBackup already exists; refusing to overwrite the only copy of the original Ogre.cfg" }
    Copy-Item -LiteralPath $OgrePath -Destination $OgreBackup
    $ogreOrig = [IO.File]::ReadAllText($OgrePath, $script:Latin1)
    $script:OgreChanged = $true   # before the write: an interrupt mid-write must still restore
    [IO.File]::WriteAllText($OgrePath, (Set-OgreVideo $ogreOrig $ResW $ResH), $script:Latin1)

    $launches = 0; $failedLaunches = 0; $consec = @{}; $skipped = @{}
    $endAt = $SoakStart.AddHours($Hours)
    $abort = $false

    :soak while ((Get-Date) -lt $endAt -and -not $abort) {
        $anyRan = $false
        foreach ($m in $Missions) {
            if ((Get-Date) -ge $endAt.AddMinutes(-1)) { break soak }
            if ($skipped[$m.Name]) { continue }
            if ($launches -ge $MaxLaunches) { $Note = "stopped at the MaxLaunches cap ($MaxLaunches)"; $abort = $true; break soak }
            $anyRan = $true; $launches++
            $minutes = if ($m.Minutes) { [double]$m.Minutes } else { [double]$MinutesPerMission }
            $runEnd = [datetime]::MinValue
            $dllHash = Get-Sha256 $DllPath
            if (-not $script:FirstDllHash) { $script:FirstDllHash = $dllHash }
            elseif ($dllHash -ne $script:FirstDllHash -and -not $script:DllSwapWarned) {
                # CR's updater re-stages its bundled suite on exit when plugins\openshim.dll differs from it.
                $script:DllSwapWarned = $true
                $script:DllSwapNote = "plugins\openshim.dll changed between launches ($($script:FirstDllHash.Substring(0,8)) -> $($dllHash.Substring(0,8))): CR's updater replaced a hand-deployed DLL. Later runs may lack SoakTelemetry; deploy test DLLs through CR's bundle."
                Write-Warning $script:DllSwapNote
            }
            $runStart = Get-Date; $launchUtc = $runStart.ToUniversalTime().AddSeconds(-1)
            $mission = $m.Name
            $runRec = [ordered]@{ mission = $mission; start = $runStart.ToString('s'); dllHash = $dllHash; outcome = 'ok'; minFps = $null; medianFps = $null; loadS = $null; missionS = $null; missionStopped = $null; afterMissionS = $null; afterMissionFps = $null; slow = @(); slowTotal = 0; telemetryLines = 0; suppressed = 0 }
            $kindCount = @{}
            $failed = $false; $stopped = $false; $needSettle = $false
            $script:Proc = $null; $ready = $false; $osAll = ''; $bzAll = ''; $readyOsOffset = 0
            $offsets = @{}; $pending = @{}; $seenRecr = @{}
            Write-Host ("[{0}] launch #{1}: {2} ({3}), {4} min" -f (Get-Date).ToString('HH:mm:ss'), $launches, $mission, $m.Route, $minutes)

            function Get-NewText([string]$Name, [switch]$Flush) {
                # Returns only complete lines; an unterminated tail waits for the next poll ($Flush returns it).
                $path = Join-Path $LogsDir $Name
                $carry = ''; if ($pending.ContainsKey($Name)) { $carry = $pending[$Name] }
                $text = ''
                if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).LastWriteTimeUtc -ge $launchUtc) {
                    $off = 0L; if ($offsets.ContainsKey($Name)) { $off = $offsets[$Name] }
                    $r = Read-LogFrom $path $off; $offsets[$Name] = $r.Length; $text = $r.Text
                }
                $text = $carry + $text
                if ($Flush) { $pending[$Name] = ''; return $text }
                $cut = $text.LastIndexOf("`n")
                $pending[$Name] = $text.Substring($cut + 1)
                if ($cut -lt 0) { return '' }
                $text.Substring(0, $cut + 1)
            }
            function Add-Incident([string]$Kind, [string[]]$Evidence, [bool]$Shot = $false, [datetime[]]$EventWindow = $null) {
                $kindCount[$Kind] = 1 + [int]$kindCount[$Kind]
                if ($kindCount[$Kind] -gt $MaxBundlesPerKindPerRun) { $runRec.suppressed++; return }
                $now = Get-Date
                $script:BundleSeq++
                $dir = Join-Path $OutDir ("{0}_{1:D3}_{2}_{3}" -f $now.ToString('yyyyMMdd-HHmmss'), $script:BundleSeq, (Get-SafeName $mission), $Kind)
                $null = New-Item -ItemType Directory -Force -Path $dir
                Copy-LogsSince $GameDir @($GameDir, $LogsDir, (Join-Path $GameDir 'exu'), (Join-Path $GameDir 'openshim')) $launchUtc (Join-Path $dir 'logs')
                $evs = @(Get-DriverResetEvents $runStart $now.AddMinutes(1))
                ConvertTo-EventText $evs | Set-Content -LiteralPath (Join-Path $dir 'events.txt') -Encoding UTF8
                foreach ($l in $Evidence) {
                    $t = ConvertFrom-SoakLine $l
                    if ($t -and $t.Kind -eq 'Lighting' -and $t.capture -and $t.capture -ne 'unavailable' -and (Test-Path -LiteralPath $t.capture)) {
                        $null = New-Item -ItemType Directory -Force -Path (Join-Path $dir 'captures')
                        Copy-Item -LiteralPath $t.capture -Destination (Join-Path $dir 'captures') -Force -ErrorAction SilentlyContinue
                    }
                }
                # PrintWindow sends WM_PRINT synchronously: on a hung window it can block the runner all night.
                if ($Shot -and $script:Hwnd -and $script:Hwnd -ne [IntPtr]::Zero -and [RS.Native]::Ping($script:Hwnd, 1000) -ge 0) { try { [RS.Native]::Capture($script:Hwnd, (Join-Path $dir 'screenshot.png')) } catch {} }
                $rec = New-IncidentRecord $Kind $mission $now $dllHash $Evidence $dir
                ($rec | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $dir 'incident.json') -Encoding UTF8
                $Incidents.Add([pscustomobject]$rec)
                Write-Host ("  INCIDENT {0}: {1}" -f $Kind, (Get-IncidentKeyLine ([pscustomobject]$rec))) -ForegroundColor Red
                Write-Summary
            }

            try {
                # ---- launch
                if ($m.Route -eq 'ini') {
                    $ini = Join-Path $ModDir "$mission.ini"
                    # Rename aside and write a new file: the slot may be a hard link into a repo checkout.
                    $orig = $script:Latin1.GetString([IO.File]::ReadAllBytes($ini))
                    $script:IniSwapped += @{ Path = $ini; Bak = "$ini.soakbak" }   # before the move: Restore-Ini skips a missing .soakbak
                    Move-Item -LiteralPath $ini -Destination "$ini.soakbak"
                    [IO.File]::WriteAllText($ini, (Set-MapTypeText $orig 'instant_action'), $script:Latin1)
                }
                Set-SoakEnv @{ OPENSHIM_SOAK_TELEMETRY = '1'; OPENSHIM_NEVER_ACTIVATE = '1'; OPENSHIM_NEVER_CAPTURE_MOUSE = '1' }
                Assert-BZRSafeToLaunch
                $p = Start-BZRGameProcess -FilePath $Exe -ArgumentList @("$mission.bzn", '/nointro', '/renderer:dx11') -WorkingDirectory $GameDir -PassThru
                $script:GamePid = $p.Id; $script:Proc = $p; [void]$p.Handle
                $script:Hwnd = [IntPtr]::Zero
                $unrespSince = $null
                $deadline = $runStart.AddMinutes($minutes)
                if ($deadline -gt $endAt) { $deadline = $endAt }
                $lastEvtCheck = Get-Date
                $driverSeen = $false

                # ---- poll
                while ($true) {
                    Start-Sleep -Seconds $PollS
                    $now = Get-Date
                    if ($script:Proc.HasExited -and -not $stopped) {
                        $code = $null; try { $code = $script:Proc.ExitCode } catch {}
                        $lastOs = Get-NewText 'openshim.log' -Flush; $osAll += $lastOs; $bzAll += Get-NewText 'BZLogger.txt' -Flush
                        foreach ($t in @(Get-SoakTelemetry $lastOs)) {   # stall/lighting lines written just before the crash
                            switch ($t.Kind) { 'GpuStall' { Add-Incident 'GPU_STALL' @($t.Line) } 'LoopStall' { Add-Incident 'LOOP_STALL' @($t.Line) } 'Lighting' { Add-Incident 'LIGHTING' @($t.Line) } }
                        }
                        $ev = @("process exited without being stopped (exit code $code) after $([math]::Round(($now - $runStart).TotalSeconds)) s")
                        $crashFiles = @(foreach ($d in @($GameDir, $LogsDir)) { Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue | Where-Object { ($_.Name -like 'openshim_crash_*' -or $_.Extension -eq '.dmp') -and $_.LastWriteTimeUtc -ge $launchUtc } })
                        foreach ($f in $crashFiles) { $ev += "crash artifact: $($f.FullName)" }
                        $tail = @(($osAll -split "`r?`n") | Where-Object { $_ } | Select-Object -Last 5); $ev += $tail
                        Add-Incident 'CRASH' $ev
                        $runRec.outcome = 'crash'; $failed = $true; $stopped = $true; break
                    }
                    if ($script:Hwnd -eq [IntPtr]::Zero) { $script:Hwnd = [RS.Native]::MainWindow([uint32]$script:GamePid) }
                    if ([RS.Native]::RestoreIfMinimized($script:Hwnd)) { }   # the desktop minimized it; the sim stops while minimized
                    # hang: window not answering for HangSeconds (same threshold as the release gate)
                    if ($script:Hwnd -ne [IntPtr]::Zero) {
                        if ([RS.Native]::Ping($script:Hwnd, 1500) -lt 0) { if (-not $unrespSince) { $unrespSince = $now } } else { $unrespSince = $null }
                        if ($unrespSince -and ($now - $unrespSince).TotalSeconds -gt $HangSeconds) {
                            $stk = Join-Path $OutDir ("hang_{0}_{1}.txt" -f $now.ToString('HHmmss'), (Get-SafeName $mission))
                            Save-Stacks $script:GamePid $stk $CdbPath
                            Add-Incident 'HANG' @("window not responding for > $HangSeconds s (pid $($script:GamePid)); stacks: $stk") $true
                            $runRec.outcome = 'hang'; $failed = $true; $needSettle = $true; break
                        }
                    }
                    # logs and telemetry
                    $newOs = Get-NewText 'openshim.log'; $newBz = Get-NewText 'BZLogger.txt'
                    $osAll += $newOs; $bzAll += $newBz
                    if (-not $ready -and $bzAll -match 'Sim Startup: Post Load after') { $ready = $true; $readyOsOffset = $osAll.Length }
                    if ($newOs) {
                        foreach ($t in @(Get-SoakTelemetry $newOs)) {
                            switch ($t.Kind) {
                                'GpuStall'   { Add-Incident 'GPU_STALL' @($t.Line) }
                                'LoopStall'  { Add-Incident 'LOOP_STALL' @($t.Line) }
                                'Lighting'   { Add-Incident 'LIGHTING' @($t.Line) }
                            }
                        }
                    }
                    if ($ready) {
                        foreach ($r in @(Get-DxRecreationsAfter $osAll $readyOsOffset)) {
                            if ($seenRecr.ContainsKey($r.Number)) { continue }
                            $seenRecr[$r.Number] = 1
                            Add-Incident 'DX11_RECREATION' @($r.Line)
                            $needSettle = $true
                        }
                    } elseif (($now - $runStart).TotalSeconds -gt $ReadyTimeoutS) {
                        Add-Incident 'STARTUP_FAIL' @("mission never reached 'Post Load' within $ReadyTimeoutS s") $true
                        $runRec.outcome = 'startup-fail'; $failed = $true; break
                    }
                    # driver resets from the System log (cheap query every ~10 s)
                    if (($now - $lastEvtCheck).TotalSeconds -ge 10) {
                        $lastEvtCheck = $now
                        $drv = @(Get-DriverResetEvents $launchUtc.ToLocalTime() $now.AddMinutes(1))
                        if ($drv.Count -gt 0 -and -not $driverSeen) {
                            $driverSeen = $true
                            Add-Incident 'DRIVER_RESET' @((ConvertTo-EventText $drv).Split("`n") | ForEach-Object { $_.Trim() }) $true
                            $runRec.outcome = 'driver-reset'; $failed = $true; $needSettle = $true; break
                        }
                    }
                    if ($now -ge $deadline) {
                        if (-not $ready) {   # MinutesPerMission shorter than ReadyTimeoutS: still a startup failure
                            Add-Incident 'STARTUP_FAIL' @("mission never reached 'Post Load' before its $minutes min ran out") $true
                            $runRec.outcome = 'startup-fail'; $failed = $true
                        }
                        break
                    }
                }
            } catch {
                Write-Warning "run error ($mission): $($_.Exception.Message)"
                $runRec.outcome = 'error'; $failed = $true; $runRec.error = $_.Exception.Message
            } finally {
                # ---- stop only through the harness (graceful; never a force-kill), then verify it is gone
                if ($script:GamePid -ne 0) {
                    $alive = Get-Process -Id $script:GamePid -ErrorAction SilentlyContinue
                    if ($alive -and -not $alive.HasExited) {
                        try { Stop-BZRGame -Id $script:GamePid -ErrorAction Continue } catch { Write-Warning "Stop-BZRGame: $_" }
                    }
                    if (Get-Process -Id $script:GamePid -ErrorAction SilentlyContinue) {
                        $abort = $true; $failed = $true; $runRec.outcome = 'game-would-not-close'; $script:KeepLock = $true
                        $Note = "game pid $($script:GamePid) ignored WM_CLOSE and was left running (never force-killed); soak aborted. bzr_livetest.lock and the game's Ogre.cfg/ini changes are KEPT: close the game, then run the soak's -DryRun to see what to restore"
                        Write-Warning $Note
                    } else { $script:GamePid = 0 }
                }
                # final log pass: late telemetry, low-FPS stats, post-hoc driver events
                try {
                    $osAll += Get-NewText 'openshim.log' -Flush
                    $all = @(Get-SoakTelemetry $osAll)
                    $ph = Get-HeartbeatPhases $all
                    $runRec.minFps = $ph.Mission.MinFps; $runRec.medianFps = $ph.Mission.MedianFps; $runRec.telemetryLines = $all.Count
                    $runRec.loadS = $ph.LoadSeconds; $runRec.missionS = $ph.MissionSeconds; $runRec.missionStopped = $ph.MissionStopped
                    $runRec.afterMissionS = $ph.AfterSeconds; $runRec.afterMissionFps = $ph.After.MedianFps
                    $runRec.slow = $ph.Slow; $runRec.slowTotal = $ph.SlowTotal
                    if (-not $driverSeen) {
                        $drv = @(Get-DriverResetEvents $launchUtc.ToLocalTime() (Get-Date).AddMinutes(1))
                        if ($drv.Count -gt 0) { $driverSeen = $true; if ($runRec.outcome -eq 'ok') { $runRec.outcome = 'driver-reset' }; $failed = $true; $needSettle = $true
                            Add-Incident 'DRIVER_RESET' @((ConvertTo-EventText $drv).Split("`n") | ForEach-Object { $_.Trim() }) }
                    }
                } catch { Write-Warning "final scan: $_" }
                $runRec.end = (Get-Date).ToString('s')
                $Runs.Add([pscustomobject]$runRec)
                if (-not $script:KeepLock) { Restore-Ini }
                Restore-SoakEnv
                Set-SoakEnv @{ OPENSHIM_NEVER_ACTIVATE = '1'; OPENSHIM_NEVER_CAPTURE_MOUSE = '1' }
                Write-Summary
            }

            $pol = Get-SoakPolicy $consec $failedLaunches $mission $failed
            $failedLaunches = $pol.FailedLaunches
            if ($pol.Skip) { $skipped[$mission] = $true; Write-Host "  $mission failed 3 launches in a row: skipped for the rest of the soak" -ForegroundColor Yellow }
            if ($pol.Abort) { $Note = "aborted: $failedLaunches failed launches"; $abort = $true; break soak }
            if ($abort) { break soak }
            Start-Sleep -Seconds $(if ($needSettle) { $SettleS } else { 5 })
        }
        if (-not $anyRan) { $Note = 'every mission was skipped after repeated failures'; break }
    }
    Write-Summary ((@($Note, $script:DllSwapNote) | Where-Object { $_ }) -join '; ')
    Write-Host "Done. Summary: $(Join-Path $OutDir 'summary.md')"
}
finally {
    # Safe even after an abort: stop our own game gracefully, restore every file we touched, drop the lock last.
    if ($script:GamePid -ne 0 -and -not $script:KeepLock -and (Get-Command Stop-BZRGame -ErrorAction SilentlyContinue)) { try { Stop-BZRGame -Id $script:GamePid -ErrorAction Continue } catch {} }
    if ($script:GamePid -ne 0 -and (Get-Process -Id $script:GamePid -ErrorAction SilentlyContinue)) { $script:KeepLock = $true }
    if (-not $script:KeepLock) {
        Restore-Ini
        if (@($script:IniSwapped).Count) { $script:KeepLock = $true; Write-Warning "Left bzr_livetest.lock: restore the *.ini.soakbak above, then delete the lock." }
        if ($script:OgreChanged -and (Test-Path -LiteralPath $OgreBackup)) {
            try {
                Copy-Item -LiteralPath $OgreBackup -Destination $OgrePath -Force
                Remove-Item -LiteralPath $OgreBackup -Force
            } catch { $script:KeepLock = $true; Write-Warning "COULD NOT RESTORE Ogre.cfg ($_): the original is $OgreBackup. Left bzr_livetest.lock." }
        }
    } else {
        Write-Warning "Game still running: left bzr_livetest.lock, $OgreBackup and any *.ini.soakbak in place. Close the game, restore them, then delete the lock."
    }
    Restore-SoakEnv
    $env:BZR_FORCE_WINDOWED = $PreForceWindowed
    if (Get-Command Exit-BZRLaunchLock -ErrorAction SilentlyContinue) { if ($global:BZRAutoLock) { Exit-BZRLaunchLock $global:BZRAutoLock } }
    $env:BZR_LAUNCH_LOCK_HELD = $PreLockHeld
    if ($script:LockTaken -and -not $script:KeepLock -and (Test-Path -LiteralPath $LockPath)) { Remove-Item -LiteralPath $LockPath -Force }
}
