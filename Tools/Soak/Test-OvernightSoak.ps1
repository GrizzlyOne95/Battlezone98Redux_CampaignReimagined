#requires -Version 5.1
# Unit tests for Soak.Lib.ps1 (synthetic text only; no game, no event log). Same style as Tools/Release/Test-*.ps1.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Soak.Lib.ps1')

$script:fail = 0
function Assert-Equal($Actual, $Expected, [string]$What) {
    if ("$Actual" -ne "$Expected") { Write-Host "FAIL $What : expected [$Expected] got [$Actual]" -ForegroundColor Red; $script:fail++ }
    else { Write-Host "ok   $What" }
}

# ---- telemetry line formats
$stall = ConvertFrom-SoakLine '[2026-11-14 02:11:03] [GPUWATCH] stall ms=8123 frame=45012 lastDone=Shadow.Cascade2 firstPending=Terrain.Draw pending=4 mission=misns1cr cam=(1204.5,88.0,-310.25)'
Assert-Equal $stall.Kind 'GpuStall' 'gpu stall kind'
Assert-Equal $stall.ms 8123 'gpu stall ms'
Assert-Equal $stall.firstPending 'Terrain.Draw' 'gpu stall firstPending'
Assert-Equal $stall.lastDone 'Shadow.Cascade2' 'gpu stall lastDone'
Assert-Equal $stall.pending 4 'gpu stall pending'
Assert-Equal $stall.mission 'misns1cr' 'gpu stall mission'
Assert-Equal $stall.cam '1204.5,88.0,-310.25' 'gpu stall cam'
Assert-Equal (ConvertFrom-SoakLine '[GPUWATCH] resumed after ms=8400').Kind 'GpuResumed' 'gpu resumed kind'
$hb = ConvertFrom-SoakLine '[SOAK] heartbeat frame=900 fps=61.5 run=RUN_STARTED mission=ch01cr'
Assert-Equal $hb.Kind 'Heartbeat' 'heartbeat kind'
Assert-Equal $hb.fps '61.5' 'heartbeat fps'
Assert-Equal $hb.run 'RUN_STARTED' 'heartbeat run'
Assert-Equal $hb.mission 'ch01cr' 'heartbeat mission'
$ls = ConvertFrom-SoakLine '[SOAK] main-loop stalled ms=15000 lastFrame=777'
Assert-Equal $ls.Kind 'LoopStall' 'loop stall kind'
Assert-Equal $ls.lastFrame 777 'loop stall lastFrame'
Assert-Equal (ConvertFrom-SoakLine '[SOAK] main-loop resumed after ms=15500').Kind 'LoopResumed' 'loop resumed kind'
$lt = ConvertFrom-SoakLine '[LIGHTING] change field=sunIntensity old=1.00 new=3.75 frame=1234 mission=bd01cr capture=C:\games\cap\f1234.png'
Assert-Equal $lt.Kind 'Lighting' 'lighting kind'
Assert-Equal $lt.field 'sunIntensity' 'lighting field'
Assert-Equal $lt.new '3.75' 'lighting new'
Assert-Equal $lt.capture 'C:\games\cap\f1234.png' 'lighting capture path'
Assert-Equal (ConvertFrom-SoakLine '[LIGHTING] change field=ambient old=a b new=c d frame=5 mission=m capture=unavailable').capture 'unavailable' 'lighting capture unavailable'
Assert-Equal (ConvertFrom-SoakLine '[LIGHTING] change field=ambient old=a b new=c d frame=5 mission=m capture=unavailable').old 'a b' 'lighting value with space'
Assert-Equal ($null -eq (ConvertFrom-SoakLine '[INFO] something else')) $true 'unrelated line is null'
Assert-Equal ($null -eq (ConvertFrom-SoakLine '[SOAK] heartbeat frame=x')) $true 'malformed heartbeat is null'

$tel = Get-SoakTelemetry ("noise`r`n[SOAK] heartbeat frame=1 fps=60 run=A mission=m`r`n[SOAK] heartbeat frame=2 fps=30 run=A mission=m`r`n[SOAK] heartbeat frame=3 fps=45 run=A mission=m`r`n")
Assert-Equal $tel.Count 3 'telemetry count'
$st = Get-HeartbeatStats $tel
Assert-Equal $st.MinFps 30 'fps min'
Assert-Equal $st.MedianFps 45 'fps median odd'
Assert-Equal (Get-HeartbeatStats (Get-SoakTelemetry "[SOAK] heartbeat frame=1 fps=10 run=A mission=m`n[SOAK] heartbeat frame=2 fps=20 run=A mission=m")).MedianFps 15 'fps median even'
Assert-Equal (Get-HeartbeatStats @()).Count 0 'fps stats empty'

# phases: load (run 5 but fps ~0), mission, a slow stretch with a lighting change beside it, then the
# throttled end screen (run 0). Shape taken from the 2026-11-14 ch01cr smoke run.
function HB([int]$s, [double]$fps, [string]$run) { "[2026-11-14T13:40:{0:D2}.000Z] [pid:1 tid:2] [INFO] [soak] [SOAK] heartbeat frame={0} fps={1} run={2} mission=ch01cr" -f $s, $fps.ToString([Globalization.CultureInfo]::InvariantCulture), $run }
$phLog = @(
    (HB 0 0 '5'), (HB 5 1 '5'),                                   # loading
    (HB 10 210 '5'), (HB 15 215 '5'), (HB 20 40 '5'),
    '[2026-11-14T13:40:21.000Z] [pid:1 tid:2] [INFO] [soak] [LIGHTING] change field=ambient old=0.3,0.3,0.3 new=0,0,0 frame=9 mission=ch01cr capture=unavailable',
    (HB 25 212 '5'), (HB 30 209 '5'),
    (HB 35 19 '0'), (HB 40 19 '0'), (HB 45 18.7 '0')              # end screen
) -join "`n"
$ph = Get-HeartbeatPhases @(Get-SoakTelemetry $phLog)
Assert-Equal $ph.LoadSeconds 10 'phase: load ends at the first heartbeat with frames flowing'
Assert-Equal $ph.Mission.Count 5 'phase: in-mission heartbeats'
Assert-Equal $ph.Mission.MedianFps 210 'phase: median excludes load and end screen'
Assert-Equal $ph.Mission.MinFps 40 'phase: min excludes load zeros'
Assert-Equal $ph.After.MedianFps 19 'phase: after-mission fps'
Assert-Equal $ph.AfterSeconds 10 'phase: after-mission seconds'
Assert-Equal ($null -ne $ph.MissionStopped) $true 'phase: mission stop time recorded'
Assert-Equal $ph.SlowTotal 1 'phase: one slow stretch'
Assert-Equal @($ph.Slow[0].context).Count 1 'phase: slow stretch carries the lighting line'
Assert-Equal ($ph.Slow[0].context[0] -like 'Lighting: *field=ambient*') $true 'phase: context is labelled by kind'
# the load's last freeze after a beat that already shows frames (2026-11-14 misns1cr live run)
$phLate = Get-HeartbeatPhases @(Get-SoakTelemetry (@(
    (HB 0 0 '5'), (HB 5 1 '5'), (HB 10 6 '5'),
    '[2026-11-14T13:40:10.500Z] [pid:1 tid:2] [WARN] [soak] [SOAK] main-loop stalled ms=2016 lastFrame=36',
    '[2026-11-14T13:40:12.700Z] [pid:1 tid:2] [INFO] [soak] [SOAK] main-loop resumed after ms=4219',
    (HB 15 230 '5'), (HB 20 222 '5'), (HB 25 227 '5'), (HB 30 163 '5')
) -join "`n"))
Assert-Equal $phLate.LoadSeconds 15 'phase: a beat followed by a load freeze stays in the load'
Assert-Equal $phLate.Mission.MinFps 163 'phase: load freeze beat not in mission min'
Assert-Equal $phLate.SlowTotal 0 'phase: load freeze beat is not a slow stretch'
$phHitch = Get-HeartbeatPhases @(Get-SoakTelemetry (@(
    (HB 0 0 '5'), (HB 5 230 '5'),
    '[2026-11-14T13:40:06.000Z] [pid:1 tid:2] [WARN] [soak] [SOAK] main-loop stalled ms=2016 lastFrame=900',
    (HB 10 225 '5'), (HB 15 228 '5')
) -join "`n"))
Assert-Equal $phHitch.LoadSeconds 5 'phase: a healthy beat before an in-mission hitch stays in the mission'
$phNone = Get-HeartbeatPhases @()
Assert-Equal $phNone.Mission.Count 0 'phase: no heartbeats'
Assert-Equal $phNone.SlowTotal 0 'phase: no heartbeats, no slow stretches'
$md = ConvertTo-SummaryMarkdown (New-SoakSummary (Get-Date) (Get-Date) @([pscustomobject]@{ start = 's'; mission = 'ch01cr'; outcome = 'ok'; loadS = 10; missionS = 20; minFps = 40; medianFps = 210; missionStopped = 'x'; afterMissionS = 10; afterMissionFps = 19; slow = $ph.Slow; slowTotal = 1 }) @())
Assert-Equal ($md -match 'Slow stretches') $true 'summary: slow stretch section'
Assert-Equal ($md -match '10 @ 19') $true 'summary: after-mission cell'

# ---- recreation counting: startup devices do not count, later ones do
$os = "[INFO] [DX11 Recovery] device recreation #1: hardware adapter settled after 0 ms (1 probes)`r`n" +
      "[INFO] [DX11 Recovery] device recreation #2: hardware adapter settled after 0 ms (1 probes)`r`n"
$ready = $os.Length
$os += "[INFO] misc line`r`n[WARN] [DX11 Recovery] device recreation #3: hardware adapter settled after 1800 ms (4 probes)`r`n" +
       "[ERROR] [DX11 Recovery] device recreation #4 failed hr=0x887A0005`r`n"
Assert-Equal (Get-DxRecreations $os).Count 4 'recreations total'
$late = Get-DxRecreationsAfter $os $ready
Assert-Equal $late.Count 2 'recreations after ready'
Assert-Equal $late[0].Number 3 'first late recreation number'
Assert-Equal (Get-DxRecreationsAfter $os $os.Length).Count 0 'none after end'

# ---- event log -> incident
function E($p, $id, $t) { [pscustomobject]@{ ProviderName = $p; Id = $id; TimeCreated = [datetime]$t; Message = "msg $id`r`nline2" } }
$ev = @(
    (E 'nvlddmkm' 153 '2026-11-14 03:00:10'), (E 'nvlddmkm' 13 '2026-11-14 03:00:11'), (E 'nvlddmkm' 14 '2026-11-14 03:00:12'),
    (E 'Display' 4101 '2026-11-14 03:00:13'),
    (E 'nvlddmkm' 999 '2026-11-14 03:00:14'),     # wrong id
    (E 'Display' 153 '2026-11-14 03:00:15'),      # wrong provider/id pair
    (E 'nvlddmkm' 153 '2026-11-14 01:00:00'))     # outside the window
$sel = Select-DriverResetEvents $ev ([datetime]'2026-11-14 02:59:00') ([datetime]'2026-11-14 03:10:00')
Assert-Equal $sel.Count 4 'driver reset events selected'
Assert-Equal (ConvertTo-EventText $sel).Split("`n").Count 4 'event text lines'
Assert-Equal ((ConvertTo-EventText $sel) -match 'nvlddmkm id=153 msg 153 line2') $true 'event text format'
Assert-Equal (Select-DriverResetEvents @() ([datetime]'2026-01-01') ([datetime]'2026-12-31')).Count 0 'no events'
# The runner wraps every call in @(); a comma-wrapped return made that one element (a false DRIVER_RESET per launch).
Assert-Equal @(Select-DriverResetEvents @() ([datetime]'2026-01-01') ([datetime]'2026-12-31')).Count 0 'no events through @()'
Assert-Equal @(Get-SoakTelemetry "[SOAK] heartbeat frame=1 fps=1 run=A mission=m`n[SOAK] heartbeat frame=2 fps=2 run=A mission=m").Count 2 'telemetry through @()'
Assert-Equal @(Get-SoakTelemetry 'noise').Count 0 'no telemetry through @()'

$inc = New-IncidentRecord 'DRIVER_RESET' 'ch01cr' ([datetime]'2026-11-14 03:00:10') 'ABC' @((ConvertTo-EventText $sel).Split("`n")[0], $stall.Line) 'b1'
Assert-Equal $inc.kind 'DRIVER_RESET' 'incident kind'
Assert-Equal $inc.time '2026-11-14T03:00:10' 'incident time'
Assert-Equal $inc.evidence.Count 2 'incident evidence'
$gi = New-IncidentRecord 'GPU_STALL' 'misns1cr' ([datetime]'2026-11-14 02:11:03') 'ABC' @($stall.Line)
Assert-Equal (Get-IncidentKeyLine $gi) 'GPUWATCH stall 8123 ms, firstPending=Terrain.Draw, lastDone=Shadow.Cascade2' 'key line gpu stall'
$di = New-IncidentRecord 'DRIVER_RESET' 'ch01cr' ([datetime]'2026-11-14 03:00:10') 'ABC' @((ConvertTo-EventText $sel).Split("`n")[0])
Assert-Equal (Get-IncidentKeyLine $di).StartsWith('2026-11-14 03:00:10 nvlddmkm') $true 'key line falls back to first evidence'

# ---- failure policy
$c = @{}; $failed = 0
$p = Get-SoakPolicy $c $failed 'a' $true; $failed = $p.FailedLaunches
Assert-Equal $p.Skip $false 'one failure does not skip'
$p = Get-SoakPolicy $c $failed 'a' $false; $failed = $p.FailedLaunches
Assert-Equal $c['a'] 0 'success resets consecutive'
1..3 | ForEach-Object { $p = Get-SoakPolicy $c $failed 'a' $true; $failed = $p.FailedLaunches }
Assert-Equal $p.Skip $true 'three in a row skips'
Assert-Equal $p.Abort $false 'four failed launches do not abort'
foreach ($i in 1..6) { $p = Get-SoakPolicy $c $failed "m$i" $true; $failed = $p.FailedLaunches }
Assert-Equal $p.Abort $true 'ten failed launches abort'

# ---- summary
$runs = @(
    [ordered]@{ mission = 'ch01cr'; start = '2026-11-14T02:00:00'; minFps = 30; medianFps = 58 },
    [ordered]@{ mission = 'misns1cr'; start = '2026-11-14T02:20:00'; minFps = $null; medianFps = $null })
$sum = New-SoakSummary ([datetime]'2026-11-14 02:00:00') ([datetime]'2026-11-14 10:00:00') $runs @($inc, $gi)
Assert-Equal $sum.hours 8 'summary hours'
Assert-Equal $sum.launches 2 'summary launches'
Assert-Equal $sum.countsByKind['DRIVER_RESET'] 1 'summary count driver'
$md = ConvertTo-SummaryMarkdown $sum
Assert-Equal ($md -match '\| 2026-11-14T02:11:03 \| misns1cr \| GPU_STALL \| GPUWATCH stall 8123 ms, firstPending=Terrain.Draw') $true 'summary table row'
Assert-Equal ($md -match '- DRIVER_RESET: 1') $true 'summary counts'
Assert-Equal ((ConvertTo-SummaryMarkdown (New-SoakSummary ([datetime]'2026-11-14 02:00:00') ([datetime]'2026-11-14 03:00:00') @() @())) -match 'No incidents recorded') $true 'summary with no incidents'

# ---- mission ini flip
$ini = "[WORKSHOP]`r`nmapType = `"multiplayer`"`r`ncustomtags = `"Coop`"`r`n"
$flip = Set-MapTypeText $ini 'instant_action'
Assert-Equal ($flip -match 'mapType = "instant_action"') $true 'maptype flipped'
Assert-Equal ($flip -match 'customtags = "Coop"') $true 'other lines kept'
$threw = $false; try { Set-MapTypeText "[x]`r`na=1" 'instant_action' | Out-Null } catch { $threw = $true }
Assert-Equal $threw $true 'missing mapType throws'

# ---- shipped plan parses and is sane
$plan = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'soak-plan.psd1')
Assert-Equal (@($plan.Missions).Count -gt 0) $true 'plan has missions'
foreach ($m in $plan.Missions) {
    Assert-Equal (@('ini', 'direct') -contains $m.Route) $true "plan route valid: $($m.Name)"
    if ($m.Route -eq 'ini') { Assert-Equal ($m.Name.Length -le 8) $true "plan ini stem <= 8 chars: $($m.Name)" }
}

if ($script:fail) { Write-Host "$script:fail assertion(s) failed." -ForegroundColor Red; exit 1 }
Write-Host 'Overnight soak tests passed.'
