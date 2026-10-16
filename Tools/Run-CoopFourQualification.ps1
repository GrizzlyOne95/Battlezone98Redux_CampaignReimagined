# Bounded local native qualification. Content is a frozen, privately staged
# Workshop layout. The harness owns launches, probes, captures and graceful stop.
param(
    [Parameter(Mandatory)][string]$HarnessRepo,
    [Parameter(Mandatory)][string]$CampaignContent,
    [Parameter(Mandatory)][string]$BZRCoopRoot,
    [string[]]$Missions=@('misn15','misn13','misn14','misn12','misn02b','misn03','misn04','misn07','misn08'),
    [switch]$StopOnFailure
)
$ErrorActionPreference='Stop'
$env:PSModulePath=$null
$env:BZR_FORCE_WINDOWED='1'
$env:BZR_QUALIFICATION_HARNESS=$HarnessRepo
$exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$suite=Join-Path $BZRCoopRoot ('suite-'+$stamp)
New-Item -ItemType Directory -Path $suite -Force | Out-Null
$rows=New-Object Collections.ArrayList
$nativeFiles=@('winmm.dll','bzloader.dll','plugins\openshim.dll')
$expectedNative=@{}
foreach($file in $nativeFiles) {$expectedNative[$file]=(Get-FileHash -LiteralPath (Join-Path "$HarnessRepo\bin\Release" $file)).Hash}
foreach($mission in $Missions) {
    if(Get-Process battlezone98redux -ErrorAction SilentlyContinue) { throw 'An existing game blocks qualification; no game was closed.' }
    $scenario=Join-Path $PSScriptRoot ('Test-'+$mission.Replace('misn','Misn')+'Live.ps1')
    if(-not(Test-Path -LiteralPath $scenario)) { throw "Missing progression scenario: $scenario" }
    $runName="$mission-four-progression-$stamp"
    @{started=$stamp;current=$mission;run=$runName;planned=$Missions;completed=@($rows);suite=$suite;state='running'} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $BZRCoopRoot 'qualification-status.json')
    foreach($client in 0..3) {
        foreach($file in $nativeFiles) {
            $actual=(Get-FileHash -LiteralPath (Join-Path "$BZRCoopRoot\instances\Instance$client\Battlezone 98 Redux" $file)).Hash
            if($actual -ne $expectedNative[$file]) {throw "c$client native $file differs from the selected build; no run launched"}
        }
    }
    $log=Join-Path $suite ($runName+'.log')
    $listing=Join-Path $BZRCoopRoot ('listings\'+$mission)
    $params=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',"$HarnessRepo\reverse_engineering\Run-BZRCoopMission.ps1",'-Mission',$mission,'-Scenario',$scenario,'-Clients','4','-CampaignContent',$CampaignContent,'-BZRCoopRoot',$BZRCoopRoot,'-ContentOverride',$listing,'-MapListY','99','-MapListScroll','0','-SkipPrepare','-MaxNetworkLogging','-MuteClients','-RunName',$runName,'-HardTimeoutSeconds','900','-FailureGraceSeconds','60')
    $child=Start-Process -FilePath $exe -ArgumentList $params -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log+'.err')
    $null=$child.Handle
    $child.WaitForExit()
    # Run-BZRCoopMission's out-of-process watchdog finishes after its runner.
    # Do not reuse session.json or start the next case until that specific
    # watchdog is gone, or it could inspect the next run's live session.
    $watchdogDeadline=(Get-Date).AddSeconds(60)
    do {
        $oldWatchdogs=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'Watch-BZRCoopRun' -and $_.CommandLine -match ('-ParentPid '+$child.Id+'(?: |$)') })
        if(-not $oldWatchdogs.Count){break}
        if((Get-Date) -gt $watchdogDeadline){throw 'The previous run watchdog has not finished; queue stopped.'}
        Start-Sleep -Seconds 2
    } while($true)
    $summaryPath=Join-Path $BZRCoopRoot ("runs\$runName\flow-summary.json")
    $result=if(Test-Path -LiteralPath $summaryPath) {Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json} else {$null}
    $verdict=if($result){$result.verdict}else{'INCOMPLETE'}
    [void]$rows.Add([pscustomobject]@{mission=$mission;clients=4;verdict=$verdict;exit=$child.ExitCode;run=$runName;summary=$summaryPath})
    $rows | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $suite 'suite.json')
    $rows | Format-Table -AutoSize | Out-String | Set-Content (Join-Path $suite 'suite.txt')
    Write-Output "$mission $verdict ($summaryPath)"
    if(Get-Process battlezone98redux -ErrorAction SilentlyContinue) { throw 'A client survived graceful teardown; suite stopped.' }
    foreach($client in 0..3) {
        foreach($file in $nativeFiles) {
            $actual=(Get-FileHash -LiteralPath (Join-Path "$BZRCoopRoot\instances\Instance$client\Battlezone 98 Redux" $file)).Hash
            if($actual -ne $expectedNative[$file]) {throw "c$client native $file changed during the run; suite stopped"}
        }
    }
    if(-not $result -or ($StopOnFailure -and $verdict -ne 'PASS')) {break}
}
$state=if(@($rows | Where-Object verdict -eq 'INCOMPLETE').Count){'stopped-incomplete'}else{'finished'}
@{started=$stamp;planned=$Missions;completed=@($rows);suite=$suite;state=$state} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $BZRCoopRoot 'qualification-status.json')
if(@($rows | Where-Object verdict -ne 'PASS').Count){exit 1}
