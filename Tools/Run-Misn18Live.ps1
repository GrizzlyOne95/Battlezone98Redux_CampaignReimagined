# Runs Tools\Test-Misn18Live.ps1 cases through the OpenShim co-op harness and gathers the evidence.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File Tools\Run-Misn18Live.ps1 -Cases smoke,storm -Clients 2
#
# * Content: this checkout's Local\Workshop\content (build it first with
#   Manage-CampaignFiles.ps1 -workshop-build "<note>"; its final manifest check can fail on
#   an unrelated OpenShim asset after the content is already complete).
# * Lobby: the harness picks the first row of the host's map list, so a one-file listing
#   override renames mission 18 to "! CR: Misn18 live" (sorts first) and sets the player minimum.
# * One client needs a harness runner that accepts a single peer (Run-BZRCoopMission.ps1 itself
#   requires two to four): pass -HarnessRunner.
# * The harness refuses while any battlezone98redux runs. This script waits for the machine to be
#   idle (bounded) and never closes a game it did not start.
# * Evidence is copied to <EvidenceRoot>\misn18-<date>\<run>\ (flow summary, steps, shots, logs).
# Windows PowerShell 5.1.
param(
    [Parameter(Mandatory)][ValidateSet('smoke', 'storm', 'win', 'loss', 'wakes')][string[]]$Cases,
    [ValidateRange(1, 4)][int]$Clients = 2,
    [string]$HarnessRepo = (Join-Path $env:USERPROFILE 'Documents\GIT\BZR-OpenShim'),
    [string]$HarnessRunner = '',
    [string]$CampaignContent = '',
    [string]$BZRCoopRoot = 'C:\BZRCoop',
    [string]$EvidenceRoot = 'C:\BZRCoop',
    [string]$Tag = '',
    [int]$IdleWaitMinutes = 45,
    [int]$HardTimeoutSeconds = 1500,
    # The coordinator aborts the run when an audio endpoint appears mid-run (RDP audio) with no muted game session.
    # Off by default: a game that started with no device stays silent.
    [switch]$MuteClients,
    [switch]$SkipPrepare
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $CampaignContent) { $CampaignContent = Join-Path (Split-Path $here -Parent) 'Local\Workshop\content' }
$env:PSModulePath = $null
$env:BZR_FORCE_WINDOWED = '1'
$env:BZR_NO_FOREGROUND_WATCHDOG = '1'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$runner = if ($HarnessRunner) { $HarnessRunner } else { Join-Path $HarnessRepo 'reverse_engineering\Run-BZRCoopMission.ps1' }
if ($Clients -lt 2 -and -not $HarnessRunner) { throw 'One client needs -HarnessRunner (a runner that accepts a single peer).' }
if (-not (Test-Path -LiteralPath (Join-Path $CampaignContent 'misn18.lua'))) { throw "No misn18.lua in $CampaignContent; build the Workshop staging first." }
$date = Get-Date -Format 'yyyyMMdd'
$evidence = New-Item -ItemType Directory -Force -Path (Join-Path $EvidenceRoot "misn18-$date")
$stamp = Get-Date -Format 'HHmmss'
$results = @()

foreach ($case in $Cases) {
    # Wait for an idle machine without touching anyone's game.
    $deadline = (Get-Date).AddMinutes($IdleWaitMinutes)
    while (Get-Process battlezone98redux -ErrorAction SilentlyContinue) {
        if ((Get-Date) -gt $deadline) { throw "A game is still running after ${IdleWaitMinutes} min; nothing was started." }
        Start-Sleep -Seconds 5
    }
    $min = if ($Clients -eq 1) { 1 } else { 2 }
    $listing = Join-Path $evidence "listing-$Clients"
    New-Item -ItemType Directory -Force -Path $listing | Out-Null
    @"
[DESCRIPTION]
missionName = "! CR: Misn18 live"

[WORKSHOP]
mapType = "multiplayer"
customtags = "Coop, Campaign Reimagined"

[MULTIPLAYER]
minPlayers = "$min"
maxPlayers = "4"
gameType = "S"
"@ | Set-Content -LiteralPath (Join-Path $listing 'misn18.ini') -Encoding ASCII
    # misn18.lua keeps CRCoop and the native table inside its campaign runtime; the harness probe stub is appended
    # at the end of the mission chunk and looks for them as file-level locals (misn17 has them). The override adds
    # them after the last line of a copy of the staged mission script, in test instances only.
    $latin1 = [Text.Encoding]::GetEncoding(28591)
    $mission = [IO.File]::ReadAllText((Join-Path $CampaignContent 'misn18.lua'), $latin1)
    $probeLocals = "`r`n-- [misn18 live] expose the runtime locals to the harness probe stub (test instances only)`r`nlocal CRCoop = campaignRuntime and campaignRuntime.Coop`r`nlocal native = campaignRuntime and campaignRuntime.Native`r`n"
    [IO.File]::WriteAllText((Join-Path $listing 'misn18.lua'), $mission.TrimEnd() + $probeLocals, $latin1)
    $runName = "misn18-$case-${Clients}p-$Tag$date-$stamp"
    $log = Join-Path $evidence "$runName.log"
    Write-Host "[run] $runName"
    # -ScenarioArgs is a hashtable parameter: pass it through a command string instead of -File.
    $audioArgs = if ($MuteClients) { '-MaxNetworkLogging -MuteClients -AllowNoAudioEndpoint' } else { '' }
    $cmd = "& '$runner' -Mission misn18 -Scenario '$(Join-Path $here 'Test-Misn18Live.ps1')' -ScenarioArgs @{Case='$case'} -Clients $Clients " +
        "-CampaignContent '$CampaignContent' -BZRCoopRoot '$BZRCoopRoot' -ContentOverride '$listing' -MapListY 99 -MapListScroll 0 " +
        "$audioArgs -RunName '$runName' -HardTimeoutSeconds $HardTimeoutSeconds -FailureGraceSeconds 120" +
        $(if ($SkipPrepare) { ' -SkipPrepare' } else { '' }) + '; exit $LASTEXITCODE'
    $p = Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $cmd) `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log + '.err')
    $null = $p.Handle
    if (-not $p.WaitForExit(($HardTimeoutSeconds + 600) * 1000)) {
        Write-Warning "$runName exceeded its wall limit; the harness watchdog owns the teardown. Not killing anything."
        $results += [pscustomobject]@{ case = $case; clients = $Clients; run = $runName; verdict = 'TIMEOUT'; exit = $null }
        break
    }
    $summary = Join-Path $BZRCoopRoot "runs\$runName\flow-summary.json"
    $verdict = if (Test-Path -LiteralPath $summary) { (Get-Content -LiteralPath $summary -Raw | ConvertFrom-Json).verdict } else { 'INCOMPLETE' }
    $dest = Join-Path $evidence $runName
    if (Test-Path -LiteralPath (Join-Path $BZRCoopRoot "runs\$runName")) {
        robocopy (Join-Path $BZRCoopRoot "runs\$runName") $dest /E /NFL /NDL /NJH /NJS /NP | Out-Null
    }
    $results += [pscustomobject]@{ case = $case; clients = $Clients; run = $runName; verdict = $verdict; exit = $p.ExitCode }
    Write-Host "[run] $runName -> $verdict (exit $($p.ExitCode))"
    if (-not (Test-Path -LiteralPath $summary)) { break }
}
$results | Format-Table -AutoSize | Out-String | Write-Host
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence "results-$stamp.json")
if (@($results | Where-Object verdict -ne 'PASS').Count) { exit 1 }
