<#
.SYNOPSIS
    Release gate: drives ONE Battlezone 98 Redux launch through every menu and several missions and
    fails on any hang, slowdown, resource leak, crash or unexplained log warning.
.DESCRIPTION
    Non-interactive. See Docs/RELEASE_STRESS_TEST.md. Windows PowerShell 5.1.
    Drives the game through OpenShim's UiPerformanceLogging trigger harness (uiperf_trigger.txt), so no
    pixel clicks except the few list boxes the harness cannot address.
    openshim.ini and Ogre.cfg are backed up byte-exact and always restored + SHA-verified.
.PARAMETER Plan        Step file (default plan.psd1 beside this script).
.PARAMETER GameDir     Battlezone 98 Redux install (default: the GOG path).
.PARAMETER SkipCold    Skip the cold shader-cache start (debugging only; the run cannot qualify).
.PARAMETER OnlyPhases  Run only these plan phases (debugging only; the run cannot qualify).
.PARAMETER MissionSeconds  Override per-mission play time.
.PARAMETER Restore     Only restore settings left behind by an interrupted run, then exit.
#>
[CmdletBinding()]
param(
    [string]$Plan = '',
    [string]$GameDir = 'C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux',
    [string]$CdbPath = 'C:\Program Files\WindowsApps\Microsoft.WinDbg_1.2606.22001.0_x64__8wekyb3d8bbwe\x86\cdb.exe',
    [switch]$SkipCold,
    [string[]]$OnlyPhases,
    [int]$MissionSeconds = 0,
    [switch]$Restore
)
$ErrorActionPreference = 'Stop'
$OnlyPhases = @($OnlyPhases | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$CustomPlan = [bool]$Plan
if (-not $Plan) { $Plan = Join-Path $PSScriptRoot 'plan.psd1' }
. (Join-Path $PSScriptRoot 'ReleaseStress.Lib.ps1')

$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$LocalRoot  = Join-Path $RepoRoot 'Local\ReleaseStress'
$Exe        = Join-Path $GameDir 'battlezone98redux.exe'
$IniPath    = Join-Path $GameDir 'openshim.ini'
$OgrePath   = Join-Path $GameDir 'Ogre.cfg'
$LogsDir    = Join-Path $GameDir 'logs'
$TriggerFile = Join-Path $GameDir 'uiperf_trigger.txt'
$CacheDir   = Join-Path $GameDir 'shader_cache'
$PendingFile = Join-Path $LocalRoot 'pending-restore.json'
$ModDir     = Join-Path $GameDir 'mods\3686673790'

# ------------------------------------------------------------------ recovery --
function Restore-Settings([object]$P) {
    $ok = $true
    foreach ($f in $P.files) {
        if (-not (Test-Path -LiteralPath $f.backup)) { Write-Warning "backup missing: $($f.backup)"; $ok = $false; continue }
        Copy-Item -LiteralPath $f.backup -Destination $f.target -Force
        $now = Get-Sha256 $f.target
        if ($now -ne $f.sha256) { Write-Warning "RESTORE MISMATCH $($f.target): $now != $($f.sha256)"; $ok = $false }
    }
    if ($P.cacheAside -and (Test-Path -LiteralPath $P.cacheAside)) {
        # Keep the regenerated cache; drop the old one only if the new one exists.
        if ((Test-Path -LiteralPath $P.cacheDir) -and @(Get-ChildItem -LiteralPath $P.cacheDir -Recurse -File -ErrorAction SilentlyContinue).Count -gt 0) {
            Remove-Item -LiteralPath $P.cacheAside -Recurse -Force
        } else {
            if (Test-Path -LiteralPath $P.cacheDir) { Remove-Item -LiteralPath $P.cacheDir -Recurse -Force }
            Move-Item -LiteralPath $P.cacheAside -Destination $P.cacheDir
        }
    }
    $ok
}

if (Test-Path -LiteralPath $PendingFile) {
    Write-Warning 'A previous run did not restore settings; restoring now.'
    $p = Get-Content -LiteralPath $PendingFile -Raw | ConvertFrom-Json
    if (-not (Restore-Settings $p)) { throw 'Could not restore the previous run''s settings; fix by hand from the backup folder named in pending-restore.json.' }
    Remove-Item -LiteralPath $PendingFile -Force
}
if ($Restore) { Write-Host 'Restore complete.'; return }

# ----------------------------------------------------------------- preflight --
# Only a copy running from this install blocks the run; another install (e.g. Steam) may run alongside.
if (@(Get-Process -Name battlezone98redux -ErrorAction SilentlyContinue | Where-Object { $_.Path -and ($_.Path -ieq $Exe) }).Count) { throw "battlezone98redux.exe is already running from $GameDir; refusing to start." }
if (-not (Test-Path -LiteralPath $Exe)) { throw "Game not found: $Exe" }
$PlanData = Import-PowerShellDataFile -LiteralPath $Plan
$B = $PlanData.Budgets
$Stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$RunDir = Join-Path $LocalRoot $Stamp
$null = New-Item -ItemType Directory -Force -Path $RunDir, "$RunDir\backup", "$RunDir\logs", "$RunDir\stacks", "$RunDir\shots"
$RunStart = Get-Date
$RunStartUtc = $RunStart.ToUniversalTime()

# ------------------------------------------------------------------- state ---
$Steps = New-Object System.Collections.Generic.List[object]
$Anoms = New-Object System.Collections.Generic.List[object]
$script:Restores = 0
$Snaps = New-Object System.Collections.Generic.List[object]
$MonitorCsv = Join-Path $RunDir 'monitor.csv'
'ts,phase,step,alive,responding,ping_ms,private_mb,ws_mb,handles,gdi,user,threads,cpu_s' | Set-Content $MonitorCsv
$script:Proc = $null; $script:GamePid = 0; $script:Hwnd = [IntPtr]::Zero
$script:Phase = 'init'; $script:StepName = ''
$script:LastTick = [DateTime]::MinValue; $script:UnrespSince = $null; $script:MaxUnresp = 0.0; $script:MaxPing = 0
$script:LastSample = $null; $script:CpuHist = New-Object System.Collections.Generic.List[object]
$script:Offsets = @{}; $script:LaunchUtc = [DateTime]::MinValue
$script:Aborted = $false; $script:HangCount = 0
$script:LastSnapshot = $null; $script:ExitCode = $null
$Pending = [ordered]@{ files = @(); cacheAside = $null; cacheDir = $CacheDir }
$SavedEnv = @{}

function Add-Anom([string]$Kind, [string]$Text, [string]$Evidence = '') {
    $Anoms.Add([pscustomobject]@{ Kind = $Kind; Phase = $script:Phase; Step = $script:StepName; Text = $Text; Evidence = $Evidence })
    Write-Host "  ANOMALY [$Kind] $Text" -ForegroundColor Red
}
function Save-Shot([string]$Label) {
    try {
        if ($script:Hwnd -ne [IntPtr]::Zero) {
            $f = Join-Path "$RunDir\shots" ("{0}-{1}.png" -f (Get-Date).ToString('HHmmss'), ($Label -replace '[^\w\-]', '_'))
            [RS.Native]::Capture($script:Hwnd, $f); return $f
        }
    } catch {}
    ''
}

# -------------------------------------------------------------- game / logs --
function Get-NewLog([string]$Name) {
    # New text of logs\<Name> since the last call; ignores the file until the game has rewritten it this launch.
    $path = Join-Path $LogsDir $Name
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    if ((Get-Item -LiteralPath $path).LastWriteTimeUtc -lt $script:LaunchUtc) { return '' }
    $off = 0L; if ($script:Offsets.ContainsKey($Name)) { $off = $script:Offsets[$Name] }
    $r = Read-LogFrom $path $off
    $script:Offsets[$Name] = $r.Length
    $r.Text
}

function Tick([switch]$Force) {
    # Sampler + hang watchdog; called from every wait loop.
    if (-not $script:Proc) { return }
    $now = Get-Date
    if (-not $Force -and ($now - $script:LastTick).TotalSeconds -lt 1.5) { return }
    $script:LastTick = $now
    $p = Get-Process -Id $script:GamePid -ErrorAction SilentlyContinue
    if (-not $p) { "$($now.ToString('HH:mm:ss.fff')),$script:Phase,$script:StepName,0,,,,,,,," | Add-Content $MonitorCsv; return }
    if ($script:Hwnd -eq [IntPtr]::Zero) { $script:Hwnd = [RS.Native]::MainWindow([uint32]$script:GamePid) }
    if ([RS.Native]::RestoreIfMinimized($script:Hwnd)) {
        # Usually the desktop (another game, Win+D) minimized the test window; noted, not failed.
        $script:Restores++; Write-Host "  NOTE: game window was minimized during $script:StepName; restored without focus" -ForegroundColor Yellow
    }
    $ping = -1; $resp = 0
    if ($script:Hwnd -ne [IntPtr]::Zero) { $ping = [RS.Native]::Ping($script:Hwnd, 3000); $resp = [int]($ping -ge 0) }
    $p.Refresh()
    if ($resp -eq 0 -and $script:Hwnd -ne [IntPtr]::Zero) {
        if (-not $script:UnrespSince) { $script:UnrespSince = $now }
        $st = ($now - $script:UnrespSince).TotalSeconds
        if ($st -gt $script:MaxUnresp) { $script:MaxUnresp = $st }
    } else {
        $script:UnrespSince = $null
        if ($ping -gt $script:MaxPing) { $script:MaxPing = $ping }
    }
    $cpu = $p.TotalProcessorTime.TotalSeconds
    $script:CpuHist.Add([pscustomobject]@{ t = $now; cpu = $cpu })
    while ($script:CpuHist.Count -gt 0 -and ($now - $script:CpuHist[0].t).TotalSeconds -gt 40) { $script:CpuHist.RemoveAt(0) }
    $script:LastSample = [pscustomobject]@{
        ts = $now; private = [math]::Round($p.PrivateMemorySize64 / 1MB, 1); ws = [math]::Round($p.WorkingSet64 / 1MB, 1)
        handles = $p.HandleCount; gdi = [RS.Native]::Gui($script:GamePid, 0); user = [RS.Native]::Gui($script:GamePid, 1); threads = $p.Threads.Count
    }
    $s = $script:LastSample
    "{0},{1},{2},1,{3},{4},{5},{6},{7},{8},{9},{10},{11}" -f $now.ToString('HH:mm:ss.fff'), $script:Phase, $script:StepName, $resp, $ping, $s.private, $s.ws, $s.handles, $s.gdi, $s.user, $s.threads, [math]::Round($cpu, 1) | Add-Content $MonitorCsv
}

function Get-CpuIdleSeconds([double]$Window) {
    # Seconds of CPU used in the last $Window seconds (-1 = not enough history).
    $h = $script:CpuHist; if ($h.Count -lt 2) { return -1 }
    $last = $h[$h.Count - 1]; $first = $null
    foreach ($e in $h) { if (($last.t - $e.t).TotalSeconds -le $Window) { $first = $e; break } }
    if (-not $first -or ($last.t - $first.t).TotalSeconds -lt ($Window * 0.7)) { return -1 }
    $last.cpu - $first.cpu
}

function Invoke-Hang([string]$Why) {
    $script:HangCount++
    $stk = Join-Path "$RunDir\stacks" ("hang{0}-{1}-{2}.txt" -f $script:HangCount, $script:Phase, ($script:StepName -replace '[^\w\-]', '_'))
    $shot = Save-Shot "hang$script:HangCount"
    Add-Anom 'HANG' "$Why (pid $script:GamePid); stacks: $stk" $shot
    Save-Stacks $script:GamePid $stk $CdbPath
    Stop-Game -Kill
    $script:Aborted = $true
    throw "HANG: $Why"
}

function Start-Game {
    $script:Offsets = @{}; $script:CpuHist.Clear(); $script:UnrespSince = $null; $script:Hwnd = [IntPtr]::Zero
    if (Test-Path -LiteralPath $TriggerFile) { Remove-Item -LiteralPath $TriggerFile -Force }
    $script:LaunchUtc = (Get-Date).ToUniversalTime().AddSeconds(-1)
    $script:GamePid = [RS.Launcher]::Start($Exe, $GameDir)
    $script:Proc = [Diagnostics.Process]::GetProcessById($script:GamePid)
    [void]$script:Proc.Handle   # keep a handle so ExitCode survives exit
    Write-Host "Launched pid $script:GamePid"
}

function Stop-Game([switch]$Kill) {
    if (-not $script:Proc) { return }
    if (-not $script:Proc.HasExited) {
        try { $w = [RS.Native]::MainWindow([uint32]$script:GamePid); if ($w -ne [IntPtr]::Zero) { [RS.Native]::Close($w) } } catch {}
        $dl = (Get-Date).AddSeconds($(if ($Kill) { 8 } else { 30 }))
        while ((Get-Date) -lt $dl -and -not $script:Proc.HasExited) { Start-Sleep -Milliseconds 500 }
        if (-not $script:Proc.HasExited) { try { $script:Proc.Kill() } catch {}; [void]$script:Proc.WaitForExit(15000); Write-Host 'Game killed.' }
    }
    if ($script:Proc.HasExited) { try { $script:ExitCode = $script:Proc.ExitCode } catch {} }
}

# ------------------------------------------------------------ UI primitives --
function Send-Trigger([string]$Name) {
    # One trigger at a time: the harness deletes the file when it has consumed it.
    $dl = (Get-Date).AddSeconds(30)
    while (Test-Path -LiteralPath $TriggerFile) {
        if ((Get-Date) -gt $dl) { throw 'previous uiperf trigger was never consumed (main thread blocked?)' }
        Tick; Start-Sleep -Milliseconds 100
    }
    if ($script:Hwnd -ne [IntPtr]::Zero) { [RS.Native]::Activate($script:Hwnd) }
    [IO.File]::WriteAllText($TriggerFile, "$Name`r`n")
}

function Wait-Until([scriptblock]$Cond, [double]$TimeoutS, [string]$What) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutS) {
        Tick
        if ($script:Proc.HasExited) { throw "game exited while waiting for $What (exit code $($script:Proc.ExitCode))" }
        if (& $Cond) { return $sw.Elapsed.TotalSeconds }
        # Hang watchdog: stuck unresponsive window.
        if ($script:UnrespSince -and (((Get-Date) - $script:UnrespSince).TotalSeconds -gt $B.HangSeconds)) { Invoke-Hang "window not responding for >$($B.HangSeconds) s during $What" }
        Start-Sleep -Milliseconds 100
    }
    -1
}

$TransRe = [regex]'\[UIPERF\] transition end\s+(\S+)\s+elapsed=([\d.]+)ms'
function Invoke-UiStep($S) {
    # trigger -> wait for the shell to report the screen transition(s) it ran. Returns result object.
    $name = if ($S.Do -eq 'back' -and -not $S.T) { '__BACK__' } else { $S.T }
    $budget = [double]$S.BudgetS
    [void](Get-NewLog 'openshim.log'); [void](Get-NewLog 'BZLogger.txt')
    $buf = ''; $bz = ''
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Send-Trigger $name
    $firstT = $null; $lastT = $null; $trans = @(); $engineMs = 0.0; $delivered = $false; $err = ''
    $expectNone = ($S.Expect -eq 'none')
    $settle = if ($S.SettleS) { [double]$S.SettleS } else { 0.8 }
    $limit = $budget * 2 + 10   # hard stop: grace to let a slow step finish so state stays known
    while ($true) {
        Tick
        if ($script:Proc.HasExited) { $err = "game exited (code $($script:Proc.ExitCode))"; break }
        $buf += (Get-NewLog 'openshim.log'); $bz += (Get-NewLog 'BZLogger.txt')
        if (-not $delivered -and $buf -match [regex]::Escape("trigger=$name detected")) { $delivered = $true }
        if ($buf -match "button=$([regex]::Escape($name)) not found") { $err = "button '$name' not found on the active screen"; break }
        if ($buf -match '__BACK__ ignored') { $err = '__BACK__ ignored (ShellBack hook missing)'; break }
        $m = $TransRe.Matches($buf)
        if ($m.Count -gt $trans.Count) { $trans = @($m); if (-not $firstT) { $firstT = $sw.Elapsed.TotalSeconds }; $lastT = $sw.Elapsed.TotalSeconds }
        if ($expectNone -and $delivered -and $sw.Elapsed.TotalSeconds -gt $settle) { break }
        if (-not $expectNone -and $lastT -and ($sw.Elapsed.TotalSeconds - $lastT) -gt $settle) { break }
        if ($sw.Elapsed.TotalSeconds -gt $limit) { $err = "no transition within $limit s"; break }
        if ($script:UnrespSince -and (((Get-Date) - $script:UnrespSince).TotalSeconds -gt $B.HangSeconds)) { Invoke-Hang "window not responding >$($B.HangSeconds) s in step $($S.Name)" }
        if ($sw.Elapsed.TotalSeconds -gt $budget -and $sw.Elapsed.TotalSeconds -lt ($budget + 1.0)) {
            # budget blown: if the process is dead-idle or wedged, that is a hang, not a slow step
            $idle = Get-CpuIdleSeconds 20
            if ($script:UnrespSince -and $idle -ge 0 -and $idle -lt 0.5 -and $sw.Elapsed.TotalSeconds -gt 25) { Invoke-Hang "no progress, idle CPU, window unresponsive in step $($S.Name)" }
        }
        Start-Sleep -Milliseconds 80
    }
    foreach ($t in $trans) { $engineMs += [double]::Parse($t.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture) }
    $screens = ([regex]::Matches($bz, 'Creating screen of type (\d+)') | ForEach-Object { $_.Groups[1].Value }) -join '>'
    $elapsed = if ($expectNone) { $sw.Elapsed.TotalSeconds } elseif ($lastT) { $lastT } else { $sw.Elapsed.TotalSeconds }
    [pscustomobject]@{ Elapsed = [math]::Round($elapsed, 2); EngineMs = [math]::Round($engineMs, 0); Transitions = $trans.Count; Screens = $screens; Err = $err; Buf = $buf; Bz = $bz }
}

function Send-Click([int]$X, [int]$Y) {
    Add-Type -Name W -Namespace RS2 -ErrorAction SilentlyContinue -MemberDefinition '[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);'
    [RS.Native]::Activate($script:Hwnd)
    $lp = [IntPtr](($Y -shl 16) -bor ($X -band 0xFFFF))
    [void][RS2.W]::PostMessage($script:Hwnd, 0x200, [IntPtr]::Zero, $lp); Start-Sleep -Milliseconds 150
    [void][RS2.W]::PostMessage($script:Hwnd, 0x200, [IntPtr]::Zero, $lp)
    [void][RS2.W]::PostMessage($script:Hwnd, 0x201, [IntPtr]1, $lp); Start-Sleep -Milliseconds 120
    [void][RS2.W]::PostMessage($script:Hwnd, 0x202, [IntPtr]::Zero, $lp)
}
function Send-Text([string]$Text) {
    Add-Type -Name W3 -Namespace RS3 -ErrorAction SilentlyContinue -MemberDefinition '[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);'
    foreach ($c in $Text.ToCharArray()) { [void][RS3.W3]::PostMessage($script:Hwnd, 0x102, [IntPtr][int]$c, [IntPtr]1); Start-Sleep -Milliseconds 40 }
}
function Sleep-Ticking([double]$Seconds) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
        Tick
        if ($script:Proc.HasExited) { throw "game exited during wait (code $($script:Proc.ExitCode))" }
        if ($script:UnrespSince -and (((Get-Date) - $script:UnrespSince).TotalSeconds -gt $B.HangSeconds)) { Invoke-Hang "window not responding >$($B.HangSeconds) s" }
        Start-Sleep -Milliseconds 200
    }
}

# ------------------------------------------------------------ main-menu gate --
function Get-ScreenType {
    # last "Creating screen of type N" in BZLogger of this launch
    $path = Join-Path $LogsDir 'BZLogger.txt'
    $r = Read-LogFrom $path 0
    $m = [regex]::Matches($r.Text, 'Creating screen of type (\d+)')
    if ($m.Count) { [int]$m[$m.Count - 1].Groups[1].Value } else { -1 }
}

function Wait-MenuReady([double]$BudgetS) {
    $script:MenuShownS = -1
    # The main menu ignores input for a while after it first appears (intro). A harmless Options round trip proves readiness.
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $BudgetS) {
        Tick
        if ($script:Proc.HasExited) { throw "game exited before the main menu (code $($script:Proc.ExitCode))" }
        if ($script:Hwnd -ne [IntPtr]::Zero -and (Get-ScreenType) -eq 1) {
            if ($script:MenuShownS -lt 0) { $script:MenuShownS = $sw.Elapsed.TotalSeconds }
            $r = Invoke-UiStep @{ Name = 'ready_probe'; Do = 'click'; T = 'Options_MainScreen'; BudgetS = 4 }
            if ($r.Screens -match "(^|>)3(>|$)" -and -not $r.Err) {
                $null = Invoke-UiStep @{ Name = 'ready_probe_back'; Do = "click"; T = "Back"; BudgetS = 4 }
                return $sw.Elapsed.TotalSeconds
            }
        }
        if ($script:UnrespSince -and (((Get-Date) - $script:UnrespSince).TotalSeconds -gt $B.HangSeconds)) { Invoke-Hang "no response while waiting for the main menu" }
        Sleep-Ticking 3
    }
    -1
}

function Add-Snapshot([string]$Label) {
    Tick -Force
    $s = $script:LastSample
    if ($s) { $Snaps.Add([pscustomobject]@{ Label = $Label; Time = (Get-Date).ToString('HH:mm:ss'); Private = $s.private; WS = $s.ws; Handles = $s.handles; Gdi = $s.gdi; User = $s.user; Threads = $s.threads }) }
}

function Add-Step([string]$Name, [string]$Do, [string]$Target, [double]$Budget, [double]$Actual, [double]$EngineMs, [string]$Result, [string]$Note, [string]$Screens = '') {
    $Steps.Add([pscustomobject]@{
        Phase = $script:Phase; Step = $Name; Do = $Do; Target = $Target; BudgetS = $Budget; ActualS = $Actual
        EngineMs = $EngineMs; MaxUnrespS = [math]::Round($script:MaxUnresp, 1); MaxPingMs = $script:MaxPing; Result = $Result; Note = $Note; Screens = $Screens })
    $c = if ($Result -eq 'PASS') { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1,-28} {2,7:N2}s (budget {3}) {4}" -f $Result, $Name, $Actual, $Budget, $Note) -ForegroundColor $c
}

# ------------------------------------------------------------- mission step --
function Invoke-Mission($S) {
    $name = $S.Name
    $play = if ($MissionSeconds -gt 0) { $MissionSeconds } elseif ($S.PlayS) { [double]$S.PlayS } else { [double]$B.MissionPlaySeconds }
    $loadBudget = if ($S.LoadBudgetS) { [double]$S.LoadBudgetS } else { [double]$B.MissionLoad }
    $note = @(); $fail = $false
    [void](Get-NewLog 'openshim.log'); [void](Get-NewLog 'BZLogger.txt')
    $script:MaxUnresp = 0.0; $script:MaxPing = 0
    $before = Get-ScreenType
    $t0 = Get-Date
    Send-Trigger ($(if ($S.T) { $S.T } else { 'Launch' }))
    $script:bzAll = ''; $script:osAll = ''; $script:b4 = ''
    $w = Wait-Until { $script:bzAll += (Get-NewLog 'BZLogger.txt'); $script:osAll += (Get-NewLog 'openshim.log'); $script:bzAll -match 'Sim Startup: Post Load after' } ($loadBudget * 2) "$name load finished"
    # 'Post Load' is the end of the loading screen; 'Starting Game Simulator' / 'Mission Load after' come
    # before terrain and object loading (88 s apart on a cold planet), and the trigger harness answers
    # during the loading screen, so neither marks "in game".
    if ($w -lt 0) { Add-Anom 'TIMEOUT' "${name}: mission load never finished"; Add-Step $name 'mission' '' $loadBudget -1 0 'FAIL' 'load never finished'; return $false }
    # Liveness probe: the trigger is delivered by the main loop, so delivery = first frame after load.
    Send-Trigger '__ENUMERATE__'
    $w2 = Wait-Until { $script:osAll += (Get-NewLog 'openshim.log'); $script:bzAll += (Get-NewLog 'BZLogger.txt'); $script:osAll -match 'trigger=__ENUMERATE__ detected' } ($loadBudget * 2) "$name main loop after load"
    $loadS = ((Get-Date) - $t0).TotalSeconds
    $loadUnresp = $script:MaxUnresp
    $loadMs = if ($script:bzAll -match 'Post Load after (\d+) ms') { [int]$Matches[1] } else { -1 }
    if ($w2 -lt 0) { Add-Anom 'TIMEOUT' "${name}: main loop never resumed after load"; Add-Step $name 'mission' '' $loadBudget -1 0 'FAIL' 'load never finished'; return $false }
    if ($loadS -gt $loadBudget) { $fail = $true; $note += ("load {0:N1}s > budget {1}s" -f $loadS, $loadBudget) }
    Add-Step "$name.load" 'mission-load' '' $loadBudget ([math]::Round($loadS, 2)) $loadMs $(if ($loadS -gt $loadBudget) { 'FAIL' } else { 'PASS' }) ("sim 'Post Load after' {0} ms; max unresponsive {1:N1}s" -f $loadMs, $loadUnresp)
    # Play
    $script:MaxUnresp = 0.0; $script:MaxPing = 0
    $pc0 = $script:LastSample
    Sleep-Ticking $play
    $playUnresp = $script:MaxUnresp
    $shot = Save-Shot "$name-play"
    Tick -Force
    $fps = [regex]::Matches($script:bzAll + (Get-NewLog 'BZLogger.txt'), 'Max FPS ([\d.]+), Min FPS ([\d.]+)')
    $unrespBad = $playUnresp -gt [double]$B.UnresponsiveSeconds
    Add-Step "$name.play" 'mission-play' '' $play $play 0 $(if ($unrespBad) { 'FAIL' } else { 'PASS' }) ("max unresponsive {0:N1}s; ping max {1} ms; private {2} MB" -f $playUnresp, $script:MaxPing, $script:LastSample.private)
    if ($unrespBad) { Add-Anom 'UNRESPONSIVE' "$name play: window unresponsive $([math]::Round($playUnresp,1)) s" $shot; $fail = $true }
    # Leave: ESC -> pause screen -> Abort
    $ok = $false
    for ($try = 1; $try -le 3 -and -not $ok; $try++) {
        [void](Get-NewLog 'openshim.log')
        $sw = [Diagnostics.Stopwatch]::StartNew(); $script:escBuf = ''
        [RS.Native]::Key($script:Hwnd, 27, 60)
        $w3 = Wait-Until { $script:escBuf += (Get-NewLog 'openshim.log'); $TransRe.IsMatch($script:escBuf) } 8 "$name esc menu"
        if ($w3 -ge 0) { $ok = $true; Add-Step "$name.esc" 'mission-esc' '' $B.Transition ([math]::Round($sw.Elapsed.TotalSeconds, 2)) 0 PASS '' }
    }
    if (-not $ok) { Add-Anom 'STUCK' "${name}: ESC never opened the pause screen" (Save-Shot "$name-noesc"); Add-Step "$name.esc" 'mission-esc' '' $B.Transition -1 0 FAIL 'no pause screen'; return $false }
    $unload = Invoke-UiStep @{ Name = "$name.abort"; Do = 'click'; T = 'Abort'; BudgetS = $B.MissionExit }
    # Abort ends the mission and returns to the main menu (screen type 1): wait for it.
    $script:b4 = $unload.Bz
    $w4 = Wait-Until { $script:b4 += (Get-NewLog 'BZLogger.txt'); $script:b4 -match 'Creating screen of type 1\b' } ($B.MissionExit * 2) "$name return to menu"
    $unloadS = $unload.Elapsed
    if ($w4 -ge 0) { $unloadS = [math]::Max($unloadS, ((Get-Date) - $t0).TotalSeconds - $loadS - $play) }
    $res = if ($w4 -lt 0 -or $unloadS -gt $B.MissionExit) { 'FAIL' } else { 'PASS' }
    if ($res -eq 'FAIL') { $fail = $true; Add-Anom 'SLOW' "${name}: mission exit took $([math]::Round($unloadS,1)) s (budget $($B.MissionExit))" '' }
    Add-Step "$name.exit" 'mission-exit' '' $B.MissionExit ([math]::Round($unloadS, 2)) $unload.EngineMs $res ("max unresponsive {0:N1}s" -f $script:MaxUnresp)
    if ($w4 -lt 0) { Add-Anom 'STUCK' "${name}: did not return to the main menu" (Save-Shot "$name-nomenu"); return $false }
    Sleep-Ticking 2
    Add-Snapshot "after $name"
    $fps | ForEach-Object { if ([double]$_.Groups[2].Value -lt [double]$B.MinFps) { Add-Anom 'FPS' "${name}: $($_.Value)" '' } }
    -not $fail
}

# --------------------------------------------------------- plan interpreter --
function Invoke-PlanStep($S) {
    $name = $S.Name
    $script:StepName = $name
    $script:MaxUnresp = 0.0; $script:MaxPing = 0
    $bud = if ($S.Budget) { [double]$B[$S.Budget] } else { [double]$B.Transition }
    $S.BudgetS = $bud
    switch ($S.Do) {
        'click' { }
        'back'  { if (-not $S.Budget) { $S.BudgetS = [double]$B.BackOut } }
    }
    switch ($S.Do) {
        { $_ -in 'click', 'back' } {
            $r = Invoke-UiStep $S
            $res = 'PASS'; $notes = @()
            if ($r.Err) { $res = 'FAIL'; $notes += $r.Err; Add-Anom 'STEP' "$name`: $($r.Err)" (Save-Shot $name) }
            elseif ($S.Expect -ne 'none' -and $r.Transitions -eq 0) { $res = 'FAIL'; $notes += 'no screen transition' }
            if ($r.Elapsed -gt $S.BudgetS) { $res = 'FAIL'; $notes += ("{0:N2}s over budget {1}s" -f $r.Elapsed, $S.BudgetS); Add-Anom 'SLOW' "$name took $($r.Elapsed) s (budget $($S.BudgetS) s); engine $($r.EngineMs) ms" (Save-Shot $name) }
            $unLimit = if ($S.UnrespS) { [double]$S.UnrespS } else { [double]$B.UnresponsiveSeconds }
            if ($script:MaxUnresp -gt $unLimit) { $res = 'FAIL'; $notes += "unresponsive $([math]::Round($script:MaxUnresp,1)) s"; Add-Anom 'UNRESPONSIVE' "$name`: window unresponsive $([math]::Round($script:MaxUnresp,1)) s" (Save-Shot $name) }
            if ($S.ExpectScreen) { $cur = Get-ScreenType; if ($cur -ne [int]$S.ExpectScreen) { $res = 'FAIL'; $notes += "screen type $cur, expected $($S.ExpectScreen)"; Add-Anom 'STATE' "$name`: on screen type $cur, expected $($S.ExpectScreen)" (Save-Shot $name) } }
            Add-Step $name $S.Do $S.T $S.BudgetS $r.Elapsed $r.EngineMs $res ($notes -join '; ') $r.Screens
            if ($res -eq 'FAIL' -and $r.Err) { return $false }
            return $true
        }
        'clickxy' { Send-Click ([int]$S.X) ([int]$S.Y); Sleep-Ticking $(if ($S.SettleS) { [double]$S.SettleS } else { 1.0 }); Add-Step $name 'clickxy' "$($S.X),$($S.Y)" 0 0 0 PASS ''; return $true }
        'text'    { Send-Text $S.Text; Sleep-Ticking 0.5; Add-Step $name 'text' $S.Text 0 0 0 PASS ''; return $true }
        'key'     { [RS.Native]::Key($script:Hwnd, [int]$S.VK, 60); Sleep-Ticking $(if ($S.SettleS) { [double]$S.SettleS } else { 1.0 }); Add-Step $name 'key' "$($S.VK)" 0 0 0 PASS ''; return $true }
        'wait'    { Sleep-Ticking ([double]$S.Seconds); Add-Step $name 'wait' "$($S.Seconds)" 0 $S.Seconds 0 PASS ''; return $true }
        'snapshot' { Add-Snapshot $S.Label; Add-Step $name 'snapshot' $S.Label 0 0 0 PASS ''; return $true }
        'mission' { return (Invoke-Mission $S) }
        'quit' { return $true }  # handled by the caller
        default { throw "unknown step kind '$($S.Do)' in plan ($name)" }
    }
}

function Get-ScreenButtons {
    # Enumerates the active screen through the harness; returns the names of its clickable controls ($null = no answer).
    [void](Get-NewLog 'openshim.log')
    Send-Trigger '__ENUMERATE__'
    $script:enumBuf = ''
    $w = Wait-Until { $script:enumBuf += (Get-NewLog 'openshim.log'); $script:enumBuf -match 'enumerating active screen' } 20 'screen enumeration'
    if ($w -lt 0) { return $null }
    Start-Sleep -Milliseconds 900; $script:enumBuf += (Get-NewLog 'openshim.log')
    $txt = $script:enumBuf.Substring($script:enumBuf.LastIndexOf('enumerating active screen'))
    $names = @()
    foreach ($m in [regex]::Matches($txt, 'ui depth=\d+ name=(.+?) ptr=0x[0-9A-Fa-f]+ vt=0x[0-9A-Fa-f]+ onclick=0x([0-9A-Fa-f]+)')) {
        if ($m.Groups[2].Value.Trim('0')) { $names += $m.Groups[1].Value }
    }
    , $names
}

function Test-AtMainMenu { $n = Get-ScreenButtons; [bool]($n -and ($n -contains 'ExitGame_MainScreen')) }

function Invoke-Recover {
    # Back out of whatever is up until the main menu shows. Never fires the shell back at the main menu
    # (that crashes: 'Top Screen' already exists), so it enumerates first and clicks a real Back control.
    for ($i = 0; $i -lt 12; $i++) {
        try {
            $n = Get-ScreenButtons
            if ($n -and ($n -contains 'ExitGame_MainScreen')) { return $true }
            $target = $null
            if ($n -contains 'Abort') { $target = 'Abort' }
            else { $target = $n | Where-Object { $_ -match '^(Back|Back_\w+|\w+_Back|OpenShim\w*Back\w*)$' } | Select-Object -First 1 }
            if ($target) { [void](Invoke-UiStep @{ Name = 'recover_back'; Do = 'click'; T = $target; BudgetS = 20 }) }
            elseif (-not $n -or $n.Count -eq 0) { [RS.Native]::Key($script:Hwnd, 27, 60); Sleep-Ticking 4 }   # in a mission without a screen: ESC
            else { Sleep-Ticking 3 }
        } catch { if ($script:Aborted) { throw }; return $false }
    }
    $false
}

function Invoke-Quit([string]$Tag) {
    $script:StepName = "quit_$Tag"; $script:MaxUnresp = 0.0
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Send-Trigger 'ExitGame_MainScreen'
    $w = -1; $swq = [Diagnostics.Stopwatch]::StartNew()
    while ($swq.Elapsed.TotalSeconds -lt $B.Quit) { Tick; if ($script:Proc.HasExited) { $w = $swq.Elapsed.TotalSeconds; break }; Start-Sleep -Milliseconds 200 }
    if ($w -lt 0) { Add-Anom 'QUIT' "game did not exit within $($B.Quit) s of the Exit Game button" (Save-Shot "quit_$Tag"); Stop-Game }
    $script:ExitCode = $null; try { $script:ExitCode = $script:Proc.ExitCode } catch {}
    $res = if ($w -ge 0 -and $script:ExitCode -eq 0) { 'PASS' } else { 'FAIL' }
    if ($w -ge 0 -and $script:ExitCode -ne 0) { Add-Anom 'QUIT' "exit code $($script:ExitCode) (expected 0)" '' }
    Add-Step "quit_$Tag" 'quit' 'ExitGame_MainScreen' $B.Quit ([math]::Round($sw.Elapsed.TotalSeconds, 2)) 0 $res "exit code $($script:ExitCode)"
}

# ------------------------------------------------------------------- logs ----
function Copy-RunLogs([string]$Tag) {
    $dest = Join-Path "$RunDir\logs" $Tag
    Copy-LogsSince $GameDir @($GameDir, $LogsDir, (Join-Path $GameDir 'exu'), (Join-Path $GameDir 'openshim'), $ModDir) $RunStartUtc $dest
}

$KnownRules = @()
$KnownPath = Join-Path $PSScriptRoot 'known-warnings.txt'
if (Test-Path -LiteralPath $KnownPath) {
    foreach ($l in (Get-Content -LiteralPath $KnownPath)) {
        if ($l -match '^\s*(#|$)') { continue }
        $parts = $l -split ' ::: '
        if ($parts.Count -lt 3) { throw "known-warnings.txt: bad line (need 'logglob ::: regex ::: reason'): $l" }
        $KnownRules += [pscustomobject]@{ Glob = $parts[0].Trim(); Re = [regex]::new($parts[1].Trim(), 'IgnoreCase'); Reason = $parts[2].Trim(); Hits = 0 }
    }
}
$AnomRe = [regex]::new('(?i)\b(error|errors|exception|fail|failed|failure|failing|assert\w*|warn|warning|not found|cannot|could not|can''t|couldn''t|timed? ?out|timeout|crash\w*|leak\w*|unresolved|missing|denied|invalid|corrupt\w*|abort\w*|fatal|unsupported|overflow|underflow)\b|Dropped Lower Than|\[SKIP\]')
$ExtraRe = @{
    'bzlogger' = [regex]::new('(?i)\blua\b.*(error|fail)|stack traceback|attempt to (call|index|compare|perform|concatenate)|\[string "|\.lua:\d+:')
    'ogre'     = [regex]::new('(?i)OGRE EXCEPTION|Can''t find|Unable to|shader.*(error|compile)|compile.*(error|failed)|texture.*(not found|missing)|mesh.*(not found|missing)|material.*(not found|missing)|Cannot find')
}
# Logs with a [LEVEL] token (openshim.log, exu.log): INFO/DEBUG lines are not anomalies unless they say something strong.
$LevelRe = [regex]::new('\[(INFO|DEBUG|TRACE|WARN|WARNING|ERROR|FATAL)\]')
$StrongRe = [regex]::new('(?i)unhandled|access violation|fatal|deadlock|not responding|stack overflow|std::terminate')
function Get-LogKind([string]$n) { if ($n -match 'BZLogger') { 'bzlogger' } elseif ($n -match 'Ogre') { 'ogre' } else { 'other' } }
function Get-Sig([string]$line) {
    $s = $line -replace '^\[?\d{4}-\d\d-\d\d[T ][\d:.]+Z?\]?\s*', '' -replace '\[pid:\d+ tid:\d+\]', '' -replace '0x[0-9A-Fa-f]+', '0x#' -replace '\d+(\.\d+)?', '#'
    $s = $s.Trim(); if ($s.Length -gt 220) { $s = $s.Substring(0, 220) }
    $s
}

$LogStats = New-Object System.Collections.Generic.List[object]
$LogUnknown = New-Object System.Collections.Generic.List[object]
function Invoke-LogScan([string]$Tag) {
    $dir = Join-Path "$RunDir\logs" $Tag
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -match '\.prev\.' -or $f.Extension -eq '.dmp') { continue }
        $kind = Get-LogKind $f.Name
        $total = 0; $known = 0; $groups = @{}
        $lines = $script:Latin1.GetString([IO.File]::ReadAllBytes($f.FullName)) -split "`r?`n"
        $n = 0
        foreach ($line in $lines) {
            $n++
            if ($line.Length -eq 0 -or $line.Contains('ui depth=')) { continue }
            if ($line.Contains('[UIPERF][HARNESS]') -and $line -notmatch 'not found|ignored') { continue }
            $lvl = $LevelRe.Match($line)
            if ($lvl.Success -and $lvl.Groups[1].Value -in 'INFO', 'DEBUG', 'TRACE') { if (-not $StrongRe.IsMatch($line)) { continue } }
            $hit = $AnomRe.IsMatch($line)
            if (-not $hit -and $ExtraRe.ContainsKey($kind)) { $hit = $ExtraRe[$kind].IsMatch($line) }
            if (-not $hit) { continue }
            $total++
            $isKnown = $false
            foreach ($k in $KnownRules) { if ($f.Name -like $k.Glob -and $k.Re.IsMatch($line)) { $k.Hits++; $isKnown = $true; break } }
            if ($isKnown) { $known++; continue }
            $sig = Get-Sig $line
            if ($groups.ContainsKey($sig)) { $groups[$sig].Count++ } else { $groups[$sig] = [pscustomobject]@{ Log = $f.Name; Tag = $Tag; Sig = $sig; Count = 1; Line = $n; Sample = $line.Substring(0, [math]::Min(300, $line.Length)) } }
        }
        $LogStats.Add([pscustomobject]@{ Tag = $Tag; Log = $f.Name; Lines = $lines.Count; Matches = $total; Known = $known; Unknown = ($total - $known); Signatures = $groups.Count })
        foreach ($g in $groups.Values) { $LogUnknown.Add($g) }
    }
}

function Test-Crashes {
    foreach ($d in @($GameDir, $LogsDir)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue | Where-Object { ($_.Name -like 'openshim_crash_*' -or $_.Extension -eq '.dmp') -and $_.LastWriteTimeUtc -ge $RunStartUtc })) {
            Add-Anom 'CRASH' "new crash artifact: $($f.FullName)" ''
            if ($f.Extension -ne '.dmp') { Copy-Item -LiteralPath $f.FullName -Destination "$RunDir\logs\" -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Test-Growth {
    $m = @($Snaps | Where-Object { $_.Label -like 'after *' })
    $out = [ordered]@{ Evaluated = $false; Failures = @(); Note = '' }
    if ($m.Count -lt 3) { $out.Note = "only $($m.Count) mission returns; need >= 3 to judge growth"; return $out }
    $out.Evaluated = $true
    $first = $m[0]; $last = $m[$m.Count - 1]   # first return is the warm-up (shader/asset caches fill once)
    foreach ($metric in @(@('Private', $B.GrowthPrivateMB), @('Handles', $B.GrowthHandles), @('Gdi', $B.GrowthGdi), @('User', $B.GrowthUser), @('Threads', $B.GrowthThreads))) {
        $name = $metric[0]; $lim = [double]$metric[1]
        $delta = [double]$last.$name - [double]$first.$name
        $mono = $true; for ($i = 1; $i -lt $m.Count; $i++) { if ([double]$m[$i].$name -lt [double]$m[$i - 1].$name - ($lim * 0.1)) { $mono = $false } }
        if ($delta -gt $lim -and $mono) { $out.Failures += "$name grew $([math]::Round($delta,1)) (limit $lim) monotonically across $($m.Count) mission returns" }
    }
    $out
}

function Get-PinText { $p = Join-Path $RepoRoot 'openshim\OPENSHIM_PIN.txt'; if (Test-Path $p) { (Get-Content $p -Raw).Trim() } else { 'n/a' } }
function Get-FileVer([string]$p) { if (Test-Path -LiteralPath $p) { (Get-Item -LiteralPath $p).VersionInfo.FileVersion } else { 'n/a' } }

# ---------------------------------------------------------------- main run ---
$DllSet = [ordered]@{
    'winmm.dll'             = Join-Path $GameDir 'winmm.dll'
    'bzloader.dll'          = Join-Path $GameDir 'bzloader.dll'
    'plugins\openshim.dll'  = Join-Path $GameDir 'plugins\openshim.dll'
    'mods\...\exu.dll'      = Join-Path $ModDir 'exu.dll'
    'mods\...\bzfile.dll'   = Join-Path $ModDir 'bzfile.dll'
    'mods\...\openshim.dll' = Join-Path $ModDir 'openshim.dll'
    'mods\...\winmm.dll'    = Join-Path $ModDir 'winmm.dll'
    'mods\...\bzloader.dll' = Join-Path $ModDir 'bzloader.dll'
}
$DllBefore = [ordered]@{}; foreach ($k in $DllSet.Keys) { $DllBefore[$k] = Get-Sha256 $DllSet[$k] }
$BinHashes = [ordered]@{}; foreach ($f in @(Get-ChildItem (Join-Path $RepoRoot 'Bin') -File -Filter *.dll)) { $BinHashes[$f.Name] = Get-Sha256 $f.FullName }
$Identity = [ordered]@{
    'CR HEAD'            = (git -C $RepoRoot rev-parse HEAD).Trim()
    'CR branch'          = (git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
    'CR tracked changes' = (@(git -C $RepoRoot status --porcelain --untracked-files=no)).Count
    'OPENSHIM_PIN'       = Get-PinText
    'OpenShim version'   = Get-FileVer (Join-Path $GameDir 'plugins\openshim.dll')
    'EXU version'        = Get-FileVer (Join-Path $ModDir 'exu.dll')
    'Game exe'           = Get-FileVer $Exe
}
$FatalError = ''
$ProcessWasKilled = $false
$SettingsOk = $false
try {
    # ---- back up + apply temporary settings (recorded BEFORE anything is changed)
    foreach ($pair in @(@($IniPath, 'openshim.ini'), @($OgrePath, 'Ogre.cfg'))) {
        $bk = Join-Path "$RunDir\backup" $pair[1]
        Copy-Item -LiteralPath $pair[0] -Destination $bk -Force
        $sha = Get-Sha256 $pair[0]
        if ((Get-Sha256 $bk) -ne $sha) { throw "backup of $($pair[1]) is not byte-identical" }
        $Pending.files += [ordered]@{ target = $pair[0]; backup = $bk; sha256 = $sha }
    }
    $Pending | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $PendingFile
    $ini = $script:Latin1.GetString([IO.File]::ReadAllBytes($IniPath))
    $ini = Set-IniValue $ini 'Diagnostics' 'UiPerformanceLogging' '1'
    $ini = Set-IniValue $ini 'General' 'RawMouseInput' '0'
    $ini = Set-IniValue $ini 'Testing' 'RunInBackground' '1'
    $ini = Set-IniValue $ini 'Network' 'NoAuthLan' '1'
    [IO.File]::WriteAllBytes($IniPath, $script:Latin1.GetBytes($ini))
    $ogre = $script:Latin1.GetString([IO.File]::ReadAllBytes($OgrePath))
    [IO.File]::WriteAllBytes($OgrePath, $script:Latin1.GetBytes((Set-OgreVideo $ogre $PlanData.Settings.Width $PlanData.Settings.Height)))
    foreach ($e in @{ OPENSHIM_NEVER_ACTIVATE = '1'; OPENSHIM_NEVER_CAPTURE_MOUSE = '1'; OPENSHIM_DISABLE_RAW_MOUSE_INPUT = '1' }.GetEnumerator()) {
        $SavedEnv[$e.Key] = [Environment]::GetEnvironmentVariable($e.Key, 'Process'); [Environment]::SetEnvironmentVariable($e.Key, $e.Value, 'Process')
    }

    # A new run supersedes any earlier pass: only a PASS from this run may re-create it.
    Remove-Item -LiteralPath (Join-Path $LocalRoot 'last-pass.json') -ErrorAction SilentlyContinue

    # ---- preflight: the install must BE the candidate
    $script:Phase = 'preflight'; $script:StepName = 'candidate'
    foreach ($n in $BinHashes.Keys) {
        $k = "mods\...\$n"
        if ($DllSet.Contains($k) -and $DllBefore[$k] -ne $BinHashes[$n]) { Add-Anom 'CANDIDATE' "installed $k differs from this checkout's Bin\$n (installed $($DllBefore[$k].Substring(0,12)), Bin $($BinHashes[$n].Substring(0,12)))" }
    }
    if ($DllBefore['plugins\openshim.dll'] -ne $BinHashes['openshim.dll']) { Add-Anom 'CANDIDATE' 'plugins\openshim.dll differs from Bin\openshim.dll' }
    $ver = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'Manage-CampaignFiles.ps1') -verify 2>&1 | Out-String
    $verOk = ($LASTEXITCODE -eq 0)
    Set-Content -LiteralPath (Join-Path $RunDir 'install-verify.txt') -Value $ver
    if (-not $verOk) { Add-Anom 'CANDIDATE' 'Manage-CampaignFiles.ps1 -verify: installed mod does not match the shipping lock (see install-verify.txt)' }
    Write-Host "Install verify: $(if ($verOk) { 'matches shipping lock' } else { 'MISMATCH' })"

    # ---- phase 0: cold shader cache
    if (-not $SkipCold) {
        $script:Phase = 'cold-start'
        if (Test-Path -LiteralPath $CacheDir) {
            $aside = "$CacheDir.stress-aside-$Stamp"; Move-Item -LiteralPath $CacheDir -Destination $aside
            $Pending.cacheAside = $aside; $Pending | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $PendingFile
        }
        Start-Game
        $script:StepName = 'cold_menu_ready'
        $t = Wait-MenuReady ([double]$B.MenuReadyCold)
        if ($t -lt 0) { Add-Anom 'COLDSTART' "no usable main menu within $($B.MenuReadyCold) s on a cold shader cache" (Save-Shot 'cold-nomenu'); Invoke-Hang 'cold-cache startup never reached the main menu' }
        Add-Step 'cold_menu_shown' 'startup' '' $B.MenuShownCold ([math]::Round($script:MenuShownS, 2)) 0 $(if ($script:MenuShownS -gt $B.MenuShownCold) { 'FAIL' } else { 'PASS' }) 'first main menu on a cold shader cache (intro movie plays after it)'
        Add-Step 'cold_menu_ready' 'startup' '' $B.MenuReadyCold ([math]::Round($t, 2)) 0 PASS 'cold shader cache'
        Add-Snapshot 'cold menu'
        Invoke-Quit 'cold'
        Copy-RunLogs 'cold'; Invoke-LogScan 'cold'
    }

    # ---- main run: ONE launch, whole plan
    $script:Phase = 'warm-start'
    Start-Game
    $script:StepName = 'menu_ready'
    $t = Wait-MenuReady ([double]$B.MenuReadyWarm)
    if ($t -lt 0) { Add-Anom 'STARTUP' "no usable main menu within $($B.MenuReadyWarm) s" (Save-Shot 'warm-nomenu'); Invoke-Hang 'warm start never reached the main menu' }
    Add-Step 'menu_shown' 'startup' '' $B.MenuShownWarm ([math]::Round($script:MenuShownS, 2)) 0 $(if ($script:MenuShownS -gt $B.MenuShownWarm) { 'FAIL' } else { 'PASS' }) 'first main menu on a warm start'
    Add-Step 'menu_ready' 'startup' '' $B.MenuReadyWarm ([math]::Round($t, 2)) 0 PASS 'warm start'
    Add-Snapshot 'warm menu'

    $groups = [ordered]@{}
    foreach ($s in $PlanData.Steps) { if (-not $groups.Contains($s.Group)) { $groups[$s.Group] = @() }; $groups[$s.Group] += , $s }
    foreach ($g in $groups.Keys) {
        if ($OnlyPhases.Count -and ($OnlyPhases -notcontains $g)) { continue }
        Write-Host "== group $g" -ForegroundColor Cyan
        $failed = $false
        foreach ($s in $groups[$g]) {
            $script:Phase = $g
            if ($failed) { Add-Step $s.Name $s.Do $s.T 0 0 0 'SKIP' 'skipped: earlier step in this group failed'; continue }
            $ok = $false
            try { $ok = Invoke-PlanStep $s } catch { if ($script:Aborted) { throw }; Add-Anom 'STEP' "$($s.Name): $($_.Exception.Message)" (Save-Shot $s.Name); $ok = $false }
            if (-not $ok) {
                $failed = $true
                Write-Host '  recovering to the main menu...' -ForegroundColor Yellow
                if (-not (Invoke-Recover)) { Add-Anom 'STUCK' "could not get back to the main menu after $($s.Name)" (Save-Shot 'stuck'); throw "stuck after $($s.Name)" }
            }
        }
        # every group must end on the main menu
        $script:Phase = $g; $script:StepName = "$g-end"
        if (-not (Test-AtMainMenu)) { Add-Anom 'STATE' "group $g did not end on the main menu"; if (-not (Invoke-Recover)) { throw "group $g left the game off the main menu" } }
        Add-Snapshot "end $g"
    }
    $script:Phase = 'quit'
    Invoke-Quit 'main'
    Copy-RunLogs 'main'; Invoke-LogScan 'main'
}
catch {
    $FatalError = $_.Exception.Message
    Write-Host "RUN ABORTED: $FatalError" -ForegroundColor Red
}
finally {
    # ---- ALWAYS: stop the game, restore settings, verify
    try { if ($script:Proc -and -not $script:Proc.HasExited) { $ProcessWasKilled = $true; Stop-Game -Kill } } catch {}
    try { if (-not (Test-Path (Join-Path "$RunDir\logs" 'main')) -or $ProcessWasKilled) { Copy-RunLogs 'final'; Invoke-LogScan 'final' } } catch { Write-Warning "log copy: $_" }
    if (Test-Path -LiteralPath $TriggerFile) { Remove-Item -LiteralPath $TriggerFile -Force -ErrorAction SilentlyContinue }
    foreach ($k in $SavedEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $SavedEnv[$k], 'Process') }
    try {
        $SettingsOk = Restore-Settings ([pscustomobject]$Pending)
        if ($SettingsOk -and (Test-Path -LiteralPath $PendingFile)) { Remove-Item -LiteralPath $PendingFile -Force }
    } catch { Write-Warning "RESTORE FAILED: $_"; $SettingsOk = $false }
    Write-Host ("Settings restored and SHA-verified: {0}" -f $SettingsOk) -ForegroundColor $(if ($SettingsOk) { 'Green' } else { 'Red' })
}

# ------------------------------------------------------------------ verdict --
$script:Phase = 'postrun'; $script:StepName = 'verdict'
Test-Crashes
$DllAfter = [ordered]@{}; foreach ($k in $DllSet.Keys) { $DllAfter[$k] = Get-Sha256 $DllSet[$k] }
$DllChanged = @($DllSet.Keys | Where-Object { $DllBefore[$_] -ne $DllAfter[$_] })
if ($DllChanged.Count) { Add-Anom 'DLLCHANGED' "installed DLL hashes changed during the run: $($DllChanged -join ', ')" }
if (-not $SettingsOk) { Add-Anom 'SETTINGS' 'openshim.ini / Ogre.cfg were NOT restored byte-exact' }
if ($FatalError) { Add-Anom 'ABORT' $FatalError }
if ($CustomPlan -or $PSBoundParameters.ContainsKey('GameDir')) { Add-Anom 'PARTIAL' 'custom -Plan or -GameDir: this run cannot qualify a release' }
if ($SkipCold -or $OnlyPhases.Count -or $MissionSeconds -gt 0) { Add-Anom 'PARTIAL' 'debug switches used (-SkipCold / -OnlyPhases / -MissionSeconds): this run cannot qualify a release' }
foreach ($u in $LogUnknown) { Add-Anom 'LOG' ("{0}: {1} x {2}" -f $u.Log, $u.Count, $u.Sample.Substring(0, [math]::Min(200, $u.Sample.Length))) '' }
$growth = Test-Growth
foreach ($f in $growth.Failures) { Add-Anom 'LEAK' $f '' }
$stepFails = @($Steps | Where-Object { $_.Result -eq 'FAIL' })
$verdict = if ($Anoms.Count -eq 0 -and $stepFails.Count -eq 0) { 'PASS' } else { 'FAIL' }
$Steps | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $RunDir 'steps.csv')
$Snaps | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $RunDir 'snapshots.csv')

# ------------------------------------------------------------------- report --
$sb = New-Object System.Text.StringBuilder
function W([string]$t = '') { [void]$sb.AppendLine($t) }
W "# Release stress test: **$verdict**"
W
W "Run $Stamp, $([math]::Round(((Get-Date) - $RunStart).TotalMinutes,1)) min. $($Steps.Count) steps, $($stepFails.Count) failed, $($Anoms.Count) anomalies."
if ($FatalError) { W; W "**Run aborted:** $FatalError" }
W; W '## Candidate'; W
foreach ($k in $Identity.Keys) { W "- $k`: $($Identity[$k])" }
W "- Settings restored byte-exact: $SettingsOk"; W "- Game exit code (main run): $script:ExitCode"
W "- Game window found minimized and restored (not a failure): $script:Restores time(s)"
W; W '| Installed binary | sha256 (12) | Bin\ in checkout |'; W '|---|---|---|'
foreach ($k in $DllSet.Keys) { $leaf = Split-Path $DllSet[$k] -Leaf; $bn = if ($BinHashes.Contains($leaf)) { $BinHashes[$leaf].Substring(0, 12) } else { '' }; W "| $k | $($DllAfter[$k].Substring(0,[math]::Min(12,$DllAfter[$k].Length))) | $bn |" }
W; W '## Anomalies'; W
if ($Anoms.Count -eq 0) { W 'None.' } else { W '| Kind | Phase | Step | Detail | Evidence |'; W '|---|---|---|---|---|'; foreach ($a in $Anoms) { W ("| {0} | {1} | {2} | {3} | {4} |" -f $a.Kind, $a.Phase, $a.Step, ($a.Text -replace '\|', '/'), $a.Evidence) } }
W; W '## Steps'; W; W '| Phase | Step | Do | Target | Budget s | Actual s | Engine ms | Max unresp s | Result | Note |'; W '|---|---|---|---|---|---|---|---|---|---|'
foreach ($s in $Steps) { W ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f $s.Phase, $s.Step, $s.Do, $s.Target, $s.BudgetS, $s.ActualS, $s.EngineMs, $s.MaxUnrespS, $s.Result, ($s.Note -replace '\|', '/')) }
W; W '## Resources at each main-menu return'; W; W '| Label | Private MB | WS MB | Handles | GDI | USER | Threads |'; W '|---|---|---|---|---|---|---|'
foreach ($s in $Snaps) { W "| $($s.Label) | $($s.Private) | $($s.WS) | $($s.Handles) | $($s.Gdi) | $($s.User) | $($s.Threads) |" }
W; W "Growth check (first mission return = warm-up, vs last): $(if ($growth.Evaluated) { if ($growth.Failures.Count) { 'FAIL' } else { 'ok' } } else { $growth.Note })"
W "Limits: private +$($B.GrowthPrivateMB) MB, handles +$($B.GrowthHandles), GDI +$($B.GrowthGdi), USER +$($B.GrowthUser), threads +$($B.GrowthThreads); fails only when growth exceeds the limit AND is monotonic."
W; W '## Log scan (every *.log/*.txt modified during the run)'; W; W '| Phase | Log | Lines | Matches | Baselined | Unexplained | Signatures |'; W '|---|---|---|---|---|---|---|'
foreach ($l in $LogStats) { W "| $($l.Tag) | $($l.Log) | $($l.Lines) | $($l.Matches) | $($l.Known) | $($l.Unknown) | $($l.Signatures) |" }
W; W '### Baseline hits'; W
foreach ($k in $KnownRules) { W "- ($($k.Hits)) $($k.Glob) ::: $($k.Re) -- $($k.Reason)" }
W; W 'Artifacts: monitor.csv, steps.csv, snapshots.csv, logs\<phase>\ (every scanned log), stacks\, shots\, install-verify.txt.'
Set-Content -LiteralPath (Join-Path $RunDir 'report.md') -Value $sb.ToString() -Encoding UTF8

if ($verdict -eq 'PASS') {
    if ([int]$Identity['CR tracked changes'] -eq 0) {
        [ordered]@{
            cr_head = $Identity['CR HEAD']; openshim_pin = $Identity['OPENSHIM_PIN']; bin_hashes = $BinHashes; installed_hashes = $DllAfter
            timestamp = (Get-Date).ToString('o'); report = (Join-Path $RunDir 'report.md')
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $LocalRoot 'last-pass.json') -Encoding UTF8
        Write-Host 'last-pass.json written.' -ForegroundColor Green
    } else { Write-Warning 'PASS, but the checkout has tracked changes: last-pass.json NOT written (commit first, then re-run).' }
}
Write-Host "`nVERDICT: $verdict   report: $(Join-Path $RunDir 'report.md')" -ForegroundColor $(if ($verdict -eq 'PASS') { 'Green' } else { 'Red' })
exit $(if ($verdict -eq 'PASS') { 0 } else { 1 })
