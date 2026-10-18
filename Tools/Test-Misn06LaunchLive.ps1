# Run with OpenShim/reverse_engineering/Run-BZRCoopMission.ps1 -Mission misn06
# -Scenario <this file> -CampaignContent <manager-staged prototype> -Clients 2.
# Assists move only the original launch timer; the real mission starts the shot.
$C = @(Get-CRFlowClientIndices)
Invoke-CRFlowStep 'mission initialized; opening camera completes' {
    foreach ($c in $C) {
        Wait-CRFlowEvent $c attach -TimeoutSeconds 120 | Out-Null
        Wait-CRFlow $c 'return role().ready' -TimeoutSeconds 60 | Out-Null
        Invoke-CRFlow $c "every('protect', 0.5, function() heal(me()) end); return true" | Out-Null
    }
    Wait-CRFlow 0 'return M.missionstart == false and not M.opencamdone' -TimeoutSeconds 45 | Out-Null
    Invoke-CRFlow 0 "every('protect-rec', 0.5, function() heal(M.avrec) end); return true"
    foreach ($c in $C) {
        $r=Invoke-CRFlow $c "local h=GetHandle('cr06_rocket');return IsValid(h) and describe(h)"
        if (-not $r) { throw "c$c missing preplaced rocket" }
        Write-Host "DOCKED c$c $(ConvertTo-Json $r -Compress)"
    }
}
Invoke-CRFlowStep 'original VO cue starts rocket and object-camera insert' {
    Invoke-CRFlow 0 'M.transportarrive = GetTime() - 1; M.transarrive = true; return true' | Out-Null
    Wait-CRFlow 0 'return M.launchFilm and M.launchFilm.camera' -TimeoutSeconds 10 | Out-Null
    foreach ($c in $C) { Wait-CRFlow $c 'return L().localCameraActive' -TimeoutSeconds 8 | Out-Null }
    foreach ($c in $C) {
        Wait-CRFlowOp $c Play 'misn0614.wav' -TimeoutSeconds 10 | Out-Null
        $r = Invoke-CRFlow $c "local h=GetHandle('cr06_rocket');return IsValid(h) and describe(h)"
        Add-CRFlowCheck "c$c sees the actual CCA rocket" ([bool]$r) $r
        Write-Host "ROCKET c$c $(ConvertTo-Json $r -Compress)"
        $fx = Invoke-CRFlow $c "local r={}; for _,k in ipairs({'Core','Plume','Smoke','Dust'}) do r[k]=exu.HasParticleSystem('CR06/Launch/1/'..k) end; return r"
        if (-not $fx.Core -or -not $fx.Plume -or -not $fx.Smoke -or -not $fx.Dust) { throw "c$c missing rocket FX: $(ConvertTo-Json $fx -Compress)" }
    }
}
Invoke-CRFlowStep 'rocket climbs on both peers' {
    Wait-CRFlow 0 'return M.launchFilm and GetTime()-M.launchFilm.started >= 5' -TimeoutSeconds 8 | Out-Null
    foreach ($c in $C) {
        $r = Invoke-CRFlow $c "local h=GetHandle('cr06_rocket');return IsValid(h) and describe(h)"
        Add-CRFlowCheck "c$c rocket still exists during ascent" ([bool]$r) $r
        Write-Host "ASCENT c$c $(ConvertTo-Json $r -Compress)"
    }
}
Invoke-CRFlowStep 'film completes; original pad and timers survive' {
    Wait-CRFlow 0 'return M.launchFilm and M.launchFilm.viewDone' -TimeoutSeconds 15 | Out-Null
    foreach ($c in $C) { Wait-CRFlow $c 'return not L().localCameraActive' -TimeoutSeconds 8 | Out-Null }
    $r = Invoke-CRFlow 0 'return {pad=IsValid(M.launchpad), launched=M.touchdown, timer=M.transaway-GetTime(), result=M.coopResult==true}'
    if (-not $r.pad -or -not $r.launched -or $r.timer -lt 50 -or $r.result) { throw "launch changed mission contract: $(ConvertTo-Json $r -Compress)" }
    $r
}
Invoke-CRFlowStep 'rocket departs above horizon; particles drain on both peers' {
    Wait-CRFlow 0 'return M.launchFilmStarted and not M.launchFilm' -TimeoutSeconds 20 | Out-Null
    foreach ($c in $C) {
        Wait-CRFlow $c "return not exu.HasParticleSystem('CR06/Launch/1/Core') and not IsValid(GetHandle('cr06_rocket'))" -TimeoutSeconds 10 | Out-Null
    }
    'rocket removed and all effects destroyed'
}
