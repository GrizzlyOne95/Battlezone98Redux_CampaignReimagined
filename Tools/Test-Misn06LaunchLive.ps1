# Run with OpenShim/reverse_engineering/Run-BZRCoopMission.ps1 -Mission misn06
# -Scenario <this file> -CampaignContent <manager-staged prototype> -Clients 2.
# Assists move only the original launch timer; the real mission starts the shot.
# Dot-sourced by a runner with an [int]$Clients parameter; PowerShell names
# are case-insensitive, so keep this array outside that parameter's name.
$rocketClients = @(Get-CRFlowClientIndices)
Invoke-CRFlowStep 'mission initialized; opening camera completes' {
    foreach ($rocketClient in $rocketClients) {
        Wait-CRFlowEvent $rocketClient attach -TimeoutSeconds 120 | Out-Null
        Wait-CRFlow $rocketClient 'return role().ready' -TimeoutSeconds 60 | Out-Null
        Invoke-CRFlow $rocketClient "every('protect', 0.5, function() heal(me()) end); return true" | Out-Null
    }
    Wait-CRFlow 0 'return M.missionstart == false and not M.opencamdone' -TimeoutSeconds 45 | Out-Null
    # Let the opening battle's stock kill-feed messages expire before capturing.
    Wait-CRFlow 0 'return GetTime() >= 45' -TimeoutSeconds 25 | Out-Null
    Invoke-CRFlow 0 "every('protect-rec', 0.5, function() heal(M.avrec) end); return true"
    foreach ($rocketClient in $rocketClients) {
        $r=Invoke-CRFlow $rocketClient "local h=GetHandle('cr06_rocket');return IsValid(h) and describe(h)"
        if (-not $r) { throw "c$rocketClient missing preplaced rocket" }
        Write-Host "DOCKED c$rocketClient $(ConvertTo-Json $r -Compress)"
        Invoke-CRFlow $rocketClient 'local p=require("PersistentConfig");p.Settings.WeaponStatsHud=false;p._DestroyAllPdaOverlays();if exu.SetViewportOverlaysEnabled then exu.SetViewportOverlaysEnabled(false) end;return true' | Out-Null
    }
}
Invoke-CRFlowStep 'original VO cue starts rocket and object-camera insert' {
    Invoke-CRFlow 0 'M.transportarrive = GetTime() - 1; M.transarrive = true; return true' | Out-Null
    Wait-CRFlow 0 'return M.launchFilm and M.launchFilm.camera' -TimeoutSeconds 10 | Out-Null
    foreach ($rocketClient in $rocketClients) { Wait-CRFlow $rocketClient 'return L().localCameraActive' -TimeoutSeconds 8 | Out-Null }
    foreach ($rocketClient in $rocketClients) {
        Wait-CRFlowOp $rocketClient Play 'misn0614.wav' -TimeoutSeconds 10 | Out-Null
        $r = Invoke-CRFlow $rocketClient "local h=GetHandle('cr06_rocket');return IsValid(h) and describe(h)"
        Add-CRFlowCheck "c$rocketClient sees the actual CCA rocket" ([bool]$r) $r
        Write-Host "ROCKET c$rocketClient $(ConvertTo-Json $r -Compress)"
        $fx = Invoke-CRFlow $rocketClient "local r={}; for _,k in ipairs({'Core','Plume','Smoke','Dust'}) do r[k]=exu.HasParticleSystem('CR06/Launch/1/'..k) end; for _,k in ipairs({'Core','Plume'}) do local n='CR06/Launch/1/'..k;r[k..'Emitters']=exu.GetParticleSystemEmitterCount(n);local lit=0;for i=0,7 do if (exu.GetParticleEmitterEmissionRate(n,i) or 0)>0 then lit=lit+1 end end;r[k..'Lit']=lit end;if exu.HasPointLight then r.Light=exu.HasPointLight('CR06/Launch/1/Light') else r.Light='unavailable' end;return r"
        if (-not $fx.Core -or -not $fx.Plume -or -not $fx.Smoke -or -not $fx.Dust) { throw "c$rocketClient missing rocket FX: $(ConvertTo-Json $fx -Compress)" }
        Add-CRFlowCheck "c$rocketClient renders all four rocket FX layers" $true $fx
        if ($fx.CoreEmitters -ne 8 -or $fx.PlumeEmitters -ne 8 -or $fx.CoreLit -ne 8 -or $fx.PlumeLit -ne 8) { throw "c$rocketClient has inactive or missing bell emitters: $(ConvertTo-Json $fx -Compress)" }
        Add-CRFlowCheck "c$rocketClient fires every bell in the eight-engine cluster" $true $fx
        if ($fx.Light -eq $false) { throw "c$rocketClient failed to create the supported engine light" }
        Add-CRFlowCheck "c$rocketClient physical engine light capability" ($fx.Light -eq $true) $fx.Light
    }
}
Invoke-CRFlowStep 'rocket climbs on both peers' {
    Wait-CRFlow 0 'return M.launchFilm and GetTime()-M.launchFilm.started >= 5' -TimeoutSeconds 8 | Out-Null
    foreach ($rocketClient in $rocketClients) {
        $r = Invoke-CRFlow $rocketClient "local h=GetHandle('cr06_rocket');return IsValid(h) and describe(h)"
        Add-CRFlowCheck "c$rocketClient rocket still exists during ascent" ([bool]$r) $r
        if (-not $r -or $r.pos[1] -lt 110) { throw "c$rocketClient rocket failed to climb: $(ConvertTo-Json $r -Compress)" }
        Write-Host "ASCENT c$rocketClient $(ConvertTo-Json $r -Compress)"
    }
}
Invoke-CRFlowStep 'film completes; original pad and timers survive' {
    Wait-CRFlow 0 'return M.launchFilm and M.launchFilm.viewDone' -TimeoutSeconds 15 | Out-Null
    foreach ($rocketClient in $rocketClients) { Wait-CRFlow $rocketClient 'return not L().localCameraActive' -TimeoutSeconds 8 | Out-Null }
    $r = Invoke-CRFlow 0 'return {pad=IsValid(M.launchpad), launched=M.touchdown, timer=M.transaway-GetTime(), result=M.coopResult==true}'
    if (-not $r.pad -or -not $r.launched -or $r.timer -lt 50 -or $r.result) { throw "launch changed mission contract: $(ConvertTo-Json $r -Compress)" }
    $r
}
Invoke-CRFlowStep 'rocket departs above horizon; particles drain on both peers' {
    Wait-CRFlow 0 'return M.launchFilmStarted and not M.launchFilm' -TimeoutSeconds 20 | Out-Null
    foreach ($rocketClient in $rocketClients) {
        Wait-CRFlow $rocketClient "return not exu.HasParticleSystem('CR06/Launch/1/Core') and not IsValid(GetHandle('cr06_rocket')) and (not exu.HasPointLight or not exu.HasPointLight('CR06/Launch/1/Light'))" -TimeoutSeconds 10 | Out-Null
    }
    'rocket removed and all effects destroyed'
}
