# Run with OpenShim/reverse_engineering/Run-BZRCoopMission.ps1 -Mission misn06
# -Scenario <this file> -CampaignContent <manager-staged prototype> -Clients 2.
# Pulls the original launch and Mayday timers forward; the restored vob4 cue
# starts the orbit film on the authority. Shots are taken at the end of each step.
$orbitClients = @(Get-CRFlowClientIndices)
Invoke-CRFlowStep 'mission initialized; opening camera completes' {
    foreach ($orbitClient in $orbitClients) {
        Wait-CRFlowEvent $orbitClient attach -TimeoutSeconds 120 | Out-Null
        Wait-CRFlow $orbitClient 'return role().ready' -TimeoutSeconds 60 | Out-Null
        Invoke-CRFlow $orbitClient "every('protect', 0.5, function() heal(me()) end); return true" | Out-Null
        Invoke-CRFlow $orbitClient 'local p=require("PersistentConfig");p.Settings.WeaponStatsHud=false;p._DestroyAllPdaOverlays();if exu.SetViewportOverlaysEnabled then exu.SetViewportOverlaysEnabled(false) end;return true' | Out-Null
    }
    Wait-CRFlow 0 'return M.missionstart == false and not M.opencamdone' -TimeoutSeconds 45 | Out-Null
    Invoke-CRFlow 0 "every('protect-rec', 0.5, function() heal(M.avrec) end); return true" | Out-Null
}
Invoke-CRFlowStep 'launch film runs and drains' {
    Invoke-CRFlow 0 'M.transportarrive = GetTime() - 1; M.transarrive = true; return true' | Out-Null
    Wait-CRFlow 0 'return M.launchFilmStarted and not M.launchFilm' -TimeoutSeconds 45 | Out-Null
    foreach ($orbitClient in $orbitClients) { Wait-CRFlow $orbitClient 'return not L().localCameraActive' -TimeoutSeconds 8 | Out-Null }
    Invoke-CRFlow 0 'return {recon=M.launchpadreconed, bugout=M.bugout, clip={exu.GetCameraClipDistances()}}'
}
Invoke-CRFlowStep 'vob3 and vob4 cues fire; orbit film begins' {
    Invoke-CRFlow 0 'M.oneminstrans = GetTime() - 1; M.transaway = GetTime() - 1; return true' | Out-Null
    Wait-CRFlow 0 'return M.vob3 == true' -TimeoutSeconds 5 | Out-Null
    Wait-CRFlow 0 'return M.orbitFilm ~= nil' -TimeoutSeconds 40 | Out-Null
    $r = Invoke-CRFlow 0 "local s=M.orbitFilm;return {t=GetTime()-s.started, lin=IsValid(s.lincoln), d1=IsValid(s.d1), d2=IsValid(s.d2), rok=IsValid(s.transport), sky=#(s.retextured or {}), clip={exu.GetCameraClipDistances()}, dome={exu.GetSkyDome and exu.GetSkyDome()}}"
    Write-Host "ORBIT $(ConvertTo-Json $r -Compress)"
    if (-not $r.lin -or -not $r.d1 -or -not $r.d2) { throw "orbit actors missing: $(ConvertTo-Json $r -Compress)" }
    $r
}
foreach ($mark in 3, 7, 11, 15, 17) {
    Invoke-CRFlowStep "orbit film t=$mark" -Soft {
        Wait-CRFlow 0 "return not M.orbitFilm or GetTime()-M.orbitFilm.started >= $mark" -TimeoutSeconds 25 | Out-Null
        Invoke-CRFlow 0 "local s=M.orbitFilm;if not s then return {done=M.orbitFilmDone} end;local p=GetPosition(s.lincoln);return {t=GetTime()-s.started, lincoln={p.x,p.y,p.z}, camera=s.camera, clip={exu.GetCameraClipDistances()}}"
    }.GetNewClosure()
}
Invoke-CRFlowStep 'film ends; scene restored on the authority' {
    Wait-CRFlow 0 'return M.orbitFilmDone == true and M.orbitFilm == nil' -TimeoutSeconds 30 | Out-Null
    foreach ($orbitClient in $orbitClients) { Wait-CRFlow $orbitClient 'return not L().localCameraActive' -TimeoutSeconds 8 | Out-Null }
    $r = Invoke-CRFlow 0 'local n=0;for h in AllObjects() do local o=GetOdf(h) or "";if o:find("cr06lin",1,true) or o:find("cr06dst",1,true) then n=n+1 end end;return {left=n, clip={exu.GetCameraClipDistances()}, light=exu.HasPointLight and exu.HasPointLight("CR06/Orbit/Flash")}'
    if ($r.left -gt 0 -or $r.light) { throw "orbit cleanup incomplete: $(ConvertTo-Json $r -Compress)" }
    $r
}
