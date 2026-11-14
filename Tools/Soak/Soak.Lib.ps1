# Soak.Lib.ps1 -- pure helpers for Invoke-OvernightSoak.ps1 (dot-sourced) and Test-OvernightSoak.ps1.
# No game access and no Add-Type here, so the tests run on any PowerShell 5.1 / 7 host.
# Debug tooling only: Tools\ is never part of the Workshop payload (Manage-CampaignFiles.ps1 SourceExcludedDirs).

# ----------------------------------------------------------- telemetry lines --
# List-returning helpers emit plain pipeline output (no ', @()' wrapper): callers wrap them in @(),
# and in PS 5.1 @() around a comma-wrapped result is ONE element holding the whole array.
# Formats are the OpenShim SoakTelemetry contract (see Docs/OVERNIGHT_SOAK.md). All optional: a build
# without the feature simply produces no matches.
$script:TelemetryRules = @(
    @{ Kind = 'GpuStall';     Re = '\[GPUWATCH\] stall ms=(?<ms>\d+) frame=(?<frame>\d+) lastDone=(?<lastDone>.*?) firstPending=(?<firstPending>.*?) pending=(?<pending>\d+) mission=(?<mission>.*?) cam=\((?<cam>[^)]*)\)' }
    @{ Kind = 'GpuResumed';   Re = '\[GPUWATCH\] resumed after ms=(?<ms>\d+)' }
    @{ Kind = 'Heartbeat';    Re = '\[SOAK\] heartbeat frame=(?<frame>\d+) fps=(?<fps>[\d.]+) run=(?<run>\S+) mission=(?<mission>.*?)\s*$' }
    @{ Kind = 'LoopStall';    Re = '\[SOAK\] main-loop stalled ms=(?<ms>\d+) lastFrame=(?<lastFrame>\d+)' }
    @{ Kind = 'LoopResumed';  Re = '\[SOAK\] main-loop resumed after ms=(?<ms>\d+)' }
    @{ Kind = 'Lighting';     Re = '\[LIGHTING\] change field=(?<field>.+?) old=(?<old>.*?) new=(?<new>.*?) frame=(?<frame>\d+) mission=(?<mission>.*?) capture=(?<capture>.*?)\s*$' }
) | ForEach-Object { @{ Kind = $_.Kind; Re = [regex]::new($_.Re) } }

function ConvertFrom-SoakLine([string]$Line) {
    # Returns $null for a non-telemetry line, else [pscustomobject]@{ Kind; Line; <named groups> }.
    if (-not $Line -or ($Line.IndexOf('[GPUWATCH]') -lt 0 -and $Line.IndexOf('[SOAK]') -lt 0 -and $Line.IndexOf('[LIGHTING]') -lt 0)) { return $null }
    foreach ($r in $script:TelemetryRules) {
        $m = $r.Re.Match($Line)
        if (-not $m.Success) { continue }
        $o = [ordered]@{ Kind = $r.Kind; Line = $Line.Trim() }
        foreach ($g in $r.Re.GetGroupNames()) { if ($g -notmatch '^\d+$') { $o[$g] = $m.Groups[$g].Value } }
        return [pscustomobject]$o
    }
    $null
}

function Get-SoakTelemetry([string]$Text) {
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($l in ($Text -split "`r?`n")) { $e = ConvertFrom-SoakLine $l; if ($e) { $out.Add($e) } }
    $out.ToArray()
}

# ------------------------------------------------------- DX11 recreation count --
# Startup creates several devices; only recreations after the mission is up count as incidents.
function Get-DxRecreations([string]$Text) {
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($m in [regex]::Matches($Text, '\[DX11 Recovery\] device recreation #(?<n>\d+)(?<rest>[^\r\n]*)')) {
        $out.Add([pscustomobject]@{ Number = [int]$m.Groups['n'].Value; Offset = $m.Index; Line = $m.Value.Trim() })
    }
    $out.ToArray()
}

function Get-DxRecreationsAfter([string]$Text, [int]$Offset) {
    # Recreations whose line starts at or after $Offset (the log length when the mission reached Post Load).
    $all = Get-DxRecreations $Text
    @($all | Where-Object { $_.Offset -ge $Offset })
}

# ---------------------------------------------------------------- heartbeats --
function Get-HeartbeatStats([object[]]$Events) {
    # All heartbeats regardless of phase; the summary uses Get-HeartbeatPhases.
    $inv = [Globalization.CultureInfo]::InvariantCulture
    Get-FpsStats @($Events | Where-Object { $_.Kind -eq 'Heartbeat' } | ForEach-Object { [double]::Parse($_.fps, $inv) })
}

# ------------------------------------------------------------- driver resets --
# System log: nvlddmkm 153 / 13 / 14 and Display 4101.
function Test-DriverResetEvent($E) {
    if (-not $E) { return $false }
    ($E.ProviderName -ieq 'nvlddmkm' -and @(153, 13, 14) -contains [int]$E.Id) -or
    ($E.ProviderName -ieq 'Display' -and [int]$E.Id -eq 4101)
}

function Select-DriverResetEvents([object[]]$Events, [datetime]$From, [datetime]$To) {
    @($Events | Where-Object { (Test-DriverResetEvent $_) -and $_.TimeCreated -ge $From -and $_.TimeCreated -le $To })
}

function Get-DriverResetEvents([datetime]$From, [datetime]$To) {
    # Live System-log query. No matching events is not an error.
    try {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = @('nvlddmkm', 'Display'); StartTime = $From; EndTime = $To } -ErrorAction Stop)
    } catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return }
        Write-Warning "event log query failed: $($_.Exception.Message)"; return
    }
    Select-DriverResetEvents $ev $From $To
}

function ConvertTo-EventText([object[]]$Events) {
    ($Events | ForEach-Object {
        $msg = if ($_.Message) { ($_.Message -replace '\s+', ' ').Trim() } else { '' }
        '{0:yyyy-MM-dd HH:mm:ss} {1} id={2} {3}' -f $_.TimeCreated, $_.ProviderName, $_.Id, $msg
    }) -join "`r`n"
}

# ----------------------------------------------------------------- incidents --
function New-IncidentRecord([string]$Kind, [string]$Mission, [datetime]$Time, [string]$DllHash, [string[]]$Evidence, [string]$Bundle = '') {
    [ordered]@{
        kind = $Kind; mission = $Mission; time = $Time.ToString('s'); dllHash = $DllHash
        evidence = @($Evidence | Where-Object { $_ }); bundle = $Bundle
    }
}

function Get-IncidentKeyLine($Incident) {
    # The one line a reader needs: the GPUWATCH stage for a stall, else the first evidence line.
    $ev = @($Incident.evidence)
    foreach ($l in $ev) {
        $t = ConvertFrom-SoakLine $l
        if ($t -and $t.Kind -eq 'GpuStall') { return ('GPUWATCH stall {0} ms, firstPending={1}, lastDone={2}' -f $t.ms, $t.firstPending, $t.lastDone) }
        if ($t -and $t.Kind -eq 'Lighting') { return ('{0}: {1} -> {2}' -f $t.field, $t.old, $t.new) }
        if ($t -and $t.Kind -eq 'LoopStall') { return ('main loop stalled {0} ms after frame {1}' -f $t.ms, $t.lastFrame) }
    }
    if ($ev.Count) { $s = [string]$ev[0]; if ($s.Length -gt 160) { $s = $s.Substring(0, 160) + '...' }; return $s }
    ''
}

# ------------------------------------------------------------ failure policy --
function Get-SoakPolicy([hashtable]$ConsecutiveByMission, [int]$FailedLaunches, [string]$Mission, [bool]$Failed,
                        [int]$MaxConsecutive = 3, [int]$MaxFailedLaunches = 10) {
    # Updates the per-mission consecutive-failure counter and says what to do next.
    # Returns Skip ($Mission is dropped from the loop) and Abort (stop the whole soak).
    if ($Failed) { $ConsecutiveByMission[$Mission] = 1 + [int]$ConsecutiveByMission[$Mission]; $FailedLaunches++ }
    else { $ConsecutiveByMission[$Mission] = 0 }
    [pscustomobject]@{
        FailedLaunches = $FailedLaunches
        Skip  = ([int]$ConsecutiveByMission[$Mission] -ge $MaxConsecutive)
        Abort = ($FailedLaunches -ge $MaxFailedLaunches)
    }
}

# Run state 5 is "mission running" (OpenShim kBzrRunStateStarted). Heartbeats before the first 5 are the
# load; any other state after it is the end / death / fail screen, which the engine draws throttled (seen
# flat ~19 fps in the background). Mixing those into the fps numbers hides real in-mission slowdowns.
$script:RunStateMission = '5'
$script:LoadEndFps = 5          # first in-mission heartbeat at or above this ends the load
$script:HeartbeatS = 5          # OpenShim heartbeat period (heartbeatMs=5000)
$script:LoadHoldFps = 20        # only a beat below this, followed by a main-loop stall, stays in the load
$script:SlowFraction = 0.5      # a heartbeat below half the in-mission median is "slow"
$script:SlowContextS = 10       # telemetry this many seconds either side of a slow stretch is its context
$script:MaxSlowStretches = 10

function Get-SoakLineTime([string]$Line) {
    # openshim.log lines start "[2026-11-14T13:40:07.822Z]"; returns local time, or $null.
    if ($Line -match '^\[(?<t>\d{4}-\d\d-\d\dT[\d:.]+Z)\]') {
        return [datetime]::Parse($Matches.t, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal).ToLocalTime()
    }
    $null
}

function Get-FpsStats([double[]]$Values) {
    $f = @($Values | Sort-Object)
    if ($f.Count -eq 0) { return [pscustomobject]@{ Count = 0; MinFps = $null; MedianFps = $null } }
    $mid = [int][math]::Floor($f.Count / 2)
    $med = if ($f.Count % 2) { $f[$mid] } else { ($f[$mid - 1] + $f[$mid]) / 2 }
    [pscustomobject]@{ Count = $f.Count; MinFps = $f[0]; MedianFps = [math]::Round($med, 1) }
}

function Get-HeartbeatPhases([object[]]$Events) {
    # Splits heartbeats into load / mission / after-mission and finds slow stretches inside the mission,
    # each with the telemetry around it, so the summary explains its own numbers.
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $hb = @($Events | Where-Object { $_.Kind -eq 'Heartbeat' } | ForEach-Object {
        [pscustomobject]@{ Time = (Get-SoakLineTime $_.Line); Fps = [double]::Parse($_.fps, $inv); Run = $_.run }
    })
    # The load's last freeze can follow a heartbeat that already shows a few frames (misns1cr 2026-11-14:
    # "fps=6.0", then "main-loop stalled" 0.5 s later), so a beat with a main-loop stall starting within one
    # heartbeat period after it still belongs to the load.
    $stalls = @($Events | Where-Object { $_.Kind -eq 'LoopStall' } | ForEach-Object { Get-SoakLineTime $_.Line } | Where-Object { $_ })
    $load = @(); $mission = @(); $after = @(); $seen = $false
    foreach ($h in $hb) {
        # The run state is already 5 while the world loads (fps 0-1, frame 0): the load lasts until frames flow.
        $starts = $seen -or ($h.Fps -ge $script:LoadEndFps -and -not ($h.Fps -lt $script:LoadHoldFps -and $h.Time -and @($stalls | Where-Object { $_ -gt $h.Time -and $_ -le $h.Time.AddSeconds($script:HeartbeatS) }).Count))
        if ($h.Run -eq $script:RunStateMission -and $starts) { $seen = $true; $mission += $h }
        elseif ($seen) { $after += $h } else { $load += $h }
    }
    $ms = Get-FpsStats @($mission | ForEach-Object { $_.Fps })
    $as = Get-FpsStats @($after | ForEach-Object { $_.Fps })
    $slow = @()
    if ($ms.Count -ge 3 -and $ms.MedianFps -gt 0) {
        $limit = $ms.MedianFps * $script:SlowFraction
        $ctx = @($Events | Where-Object { $_.Kind -ne 'Heartbeat' })
        $cur = $null
        foreach ($h in ($mission + @($null))) {
            if ($h -and $h.Fps -lt $limit) {
                if (-not $cur) { $cur = @{ Start = $h.Time; End = $h.Time; MinFps = $h.Fps; Beats = 0 } }
                $cur.End = $h.Time; $cur.Beats++; if ($h.Fps -lt $cur.MinFps) { $cur.MinFps = $h.Fps }
                continue
            }
            if ($cur) {
                $near = @()
                if ($cur.Start) {
                    $lo = $cur.Start.AddSeconds(-$script:SlowContextS); $hi = $cur.End.AddSeconds($script:SlowContextS)
                    $near = @($ctx | Where-Object { $t = Get-SoakLineTime $_.Line; $t -and $t -ge $lo -and $t -le $hi } | ForEach-Object { '{0}: {1}' -f $_.Kind, ($_.Line -replace '^(\[[^\]]*\]\s*){4}', '') })
                }
                $slow += [pscustomobject]@{
                    start = $(if ($cur.Start) { $cur.Start.ToString('s') }); end = $(if ($cur.End) { $cur.End.ToString('s') })
                    heartbeats = $cur.Beats; minFps = $cur.MinFps; missionMedianFps = $ms.MedianFps
                    context = @($near | Select-Object -First 5)
                }
                $cur = $null
            }
        }
    }
    [pscustomobject]@{
        LoadSeconds = $(if ($load.Count -and $mission.Count -and $load[0].Time -and $mission[0].Time) { [math]::Round(($mission[0].Time - $load[0].Time).TotalSeconds) } else { $null })
        Mission = $ms
        MissionSeconds = $(if ($mission.Count -ge 2 -and $mission[0].Time -and $mission[-1].Time) { [math]::Round(($mission[-1].Time - $mission[0].Time).TotalSeconds) } else { $null })
        MissionStopped = $(if ($after.Count -and $after[0].Time) { $after[0].Time.ToString('s') } else { $null })
        After = $as
        AfterSeconds = $(if ($after.Count -ge 2 -and $after[0].Time -and $after[-1].Time) { [math]::Round(($after[-1].Time - $after[0].Time).TotalSeconds) } else { $null })
        Slow = @($slow | Select-Object -First $script:MaxSlowStretches)
        SlowTotal = $slow.Count
    }
}

# ------------------------------------------------------------------- summary --
function New-SoakSummary([datetime]$Start, [datetime]$End, [object[]]$Runs, [object[]]$Incidents, [string]$Note = '') {
    $by = [ordered]@{}
    foreach ($i in $Incidents) { $by[$i.kind] = 1 + [int]$by[$i.kind] }
    [ordered]@{
        start = $Start.ToString('s'); end = $End.ToString('s')
        hours = [math]::Round(($End - $Start).TotalHours, 2)
        launches = @($Runs).Count
        missionsRun = @($Runs | ForEach-Object { $_.mission } | Sort-Object -Unique).Count
        countsByKind = $by
        runs = @($Runs)
        incidents = @($Incidents)
        note = $Note
    }
}

function ConvertTo-SummaryMarkdown($S) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Overnight soak summary')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine(('Ran {0} h ({1} to {2}); {3} launches over {4} distinct missions.' -f $S.hours, $S.start, $S.end, $S.launches, $S.missionsRun))
    if ($S.note) { [void]$sb.AppendLine(); [void]$sb.AppendLine("Note: $($S.note)") }
    [void]$sb.AppendLine()
    $inc = @($S.incidents)
    if ($inc.Count -eq 0) {
        [void]$sb.AppendLine('No incidents recorded.')
    } else {
        [void]$sb.AppendLine('## Incidents')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('| Time | Mission | Kind | Key line |')
        [void]$sb.AppendLine('|---|---|---|---|')
        foreach ($i in $inc) {
            $key = (Get-IncidentKeyLine $i) -replace '\|', '/'
            [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} |' -f $i.time, $i.mission, $i.kind, $key))
        }
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('## Counts by kind')
        [void]$sb.AppendLine()
        foreach ($k in $S.countsByKind.Keys) { [void]$sb.AppendLine(('- {0}: {1}' -f $k, $S.countsByKind[$k])) }
    }
    $runs = @($S.runs | Where-Object { $null -ne $_.minFps -or $null -ne $_.afterMissionFps })
    if ($runs.Count) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('## FPS per run (heartbeats, every 5 s)')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('Min and median count only heartbeats while the mission runs (run state 5). Loading, and the')
        [void]$sb.AppendLine('end / death / fail screen after the mission stops (which the engine throttles), are timed separately.')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('| Start | Mission | Outcome | Load s | In-mission s | Min | Median | Mission stopped | After-mission s @ fps |')
        [void]$sb.AppendLine('|---|---|---|---|---|---|---|---|---|')
        foreach ($r in $runs) {
            $afterCell = if ($r.missionStopped) { '{0} @ {1}' -f $r.afterMissionS, $r.afterMissionFps } else { '-' }
            $stopCell = if ($r.missionStopped) { $r.missionStopped } else { 'no (still running at stop)' }
            [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} |' -f $r.start, $r.mission, $r.outcome, $r.loadS, $r.missionS, $r.minFps, $r.medianFps, $stopCell, $afterCell))
        }
        $slowRuns = @($runs | Where-Object { @($_.slow).Count })
        if ($slowRuns.Count) {
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('## Slow stretches inside missions (below half the in-mission median)')
            [void]$sb.AppendLine()
            foreach ($r in $slowRuns) {
                foreach ($w in @($r.slow)) {
                    [void]$sb.AppendLine(('- **{0}** {1} to {2}: min {3} fps vs median {4} ({5} heartbeats)' -f $r.mission, $w.start, $w.end, $w.minFps, $w.missionMedianFps, $w.heartbeats))
                    if (@($w.context).Count) { foreach ($c in @($w.context)) { [void]$sb.AppendLine(('  - nearby: `{0}`' -f ($c -replace '`', "'"))) } }
                    else { [void]$sb.AppendLine('  - nearby: no telemetry within 10 s (not a stall or lighting change)') }
                }
                if ($r.slowTotal -gt @($r.slow).Count) { [void]$sb.AppendLine(('  - ...and {0} more in this run (summary.json caps the list)' -f ($r.slowTotal - @($r.slow).Count))) }
            }
        }
    }
    $sb.ToString()
}

# ---------------------------------------------------------------------- misc --
function Set-MapTypeText([string]$Text, [string]$To) {
    # Rewrites mapType = "<x>" in a mission ini. Throws when the line is absent (the flip would do nothing).
    $re = [regex]'(?im)^(\s*mapType\s*=\s*")[^"]*(")'
    if (-not $re.IsMatch($Text)) { throw 'ini has no mapType line' }
    $re.Replace($Text, ('${1}' + $To + '${2}'), 1)
}

function Get-SafeName([string]$s) { ($s -replace '[^\w\-]', '_') }
