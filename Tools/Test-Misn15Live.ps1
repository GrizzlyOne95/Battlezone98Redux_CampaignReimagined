# Scenario for OpenShim Run-BZRCoopMission.ps1, using configured native clients.
# Test assists move owner-local craft/host-owned NPCs and set the host reserve.
# They establish progression/replication, not natural collection or difficulty.
param([int]$HostClient=0,[int]$GuestClient=1)
$H=$HostClient; $G=$GuestClient
Invoke-CRFlowStep 'Mission 15 and its own methane surface initialize on every peer' {
    Wait-CRFlow $H 'return M.start_done and M.cr15 ~= nil' -TimeoutSeconds 90 | Out-Null
    foreach($c in @(Get-CRFlowClientIndices)) {
        $state=Wait-CRFlow $c 'local t=require("CRTitanWeather"); return t.GetSurface().up and {surface=t.GetSurface(), sea=t.Sites.sea.level, map=t.Sites.mission}' -TimeoutSeconds 60
        Add-CRFlowCheck "c$c methane uses misn15 MAT/HG2 sites and its own material" ($state.map -eq 'misn15' -and $state.sea -eq 38.1 -and $state.surface.material -eq 'CR/Titan/Methane15') $state
    }
}
Invoke-CRFlowStep 'CCA convoy reaches rendezvous' {
    Invoke-CRFlow $H 'put(GetHandle("svtank0_wingman"),"apcamr5_camerapod",20); return true' | Out-Null
    Wait-CRFlow $H 'return M.cr15.cca' -TimeoutSeconds 25
}
Invoke-CRFlowStep 'Guest recovers both waiting rescue groups' {
    Invoke-CRFlow $G 'return tp("apcamr1_camerapod",15)' | Out-Null
    Wait-CRFlow $H 'return M.cr15.nw' -TimeoutSeconds 25 | Out-Null
    Invoke-CRFlow $G 'return tp("apcamr2_camerapod",15)' | Out-Null
    Wait-CRFlow $H 'return M.cr15.ne' -TimeoutSeconds 25 | Out-Null
    foreach($c in @(Get-CRFlowClientIndices)) {
        $state=Wait-CRFlow $c 'local nw=GetTeamNum(GetHandle("cr15_nw_scav")); local ne=GetTeamNum(GetHandle("cr15_ne_artillery"));return nw==1 and ne==1 and {nw=nw, ne=ne}' -TimeoutSeconds 25
        Add-CRFlowCheck "c$c observes the same recovered units on team 1" ($state.nw -eq 1 -and $state.ne -eq 1) $state
    }
}
Invoke-CRFlowStep 'Tartarus warning and deliberate disturbance provoke one bounded response' {
    Invoke-CRFlow $G 'return tp("ubtart0_i76building",120)' | Out-Null
    Wait-CRFlow $H 'return M.cr15.tartarusWarning ~= nil' -TimeoutSeconds 20 | Out-Null
    $quiet=Invoke-CRFlow $H 'return M.cr15.tartarusAlert ~= true'
    Add-CRFlowCheck 'warning radius alone has no punitive response' ([bool]$quiet) $quiet
    # Explicit host-owned damage assist; does not pretend to be physical firing.
    Invoke-CRFlow $H 'local h=GetHandle("ubtart0_i76building"); Damage(h,1); return true' | Out-Null
    Wait-CRFlow $H 'return M.cr15.tartarusResponseSpawned == true' -TimeoutSeconds 35
}
Invoke-CRFlowStep 'Persistent intrusion deploys the same bolt-mine grid on both peers' {
    # Explicit survivability assist while inspecting the hostile grid.
    Invoke-CRFlow $G 'SetMaxHealth(me(),1000000); SetCurHealth(me(),1000000); return tp("ubtart0_i76building",60)' | Out-Null
    Wait-CRFlow $H 'return M.cr15.tartarusMinesPending ~= nil' -TimeoutSeconds 25 | Out-Null
    Invoke-CRFlow $G 'return tp("ubtart0_i76building",220)' | Out-Null
    Wait-CRFlow $H 'return M.cr15.tartarusMinesComplete == true' -TimeoutSeconds 30 | Out-Null
    foreach($c in @(Get-CRFlowClientIndices)) {
        $count=Wait-CRFlow $c 'local n=0;for h in ObjectsInRange(120,GetPosition(GetHandle("ubtart0_i76building"))) do if IsValid(h) and (IsOdf(h,"boltmine") or IsOdf(h,"boltmine.odf")) and GetTeamNum(h)==6 then n=n+1 end end;return n>=40 and n' -TimeoutSeconds 25
        Add-CRFlowCheck "c$c observes forty native Fury arc mines" ($count -eq 40) $count
    }
}
Invoke-CRFlowStep 'Banked reserve starts withdrawal; missing guest blocks victory' {
    # Capacity must exist before setting a reserve; native SetScrap clamps it.
    Invoke-CRFlow $H 'for i=1,3 do BuildObject("absilo",1,GetPositionNear(GetPosition(M.recy),80+i*25,90+i*25)) end; SetScrap(1,50); return {scrap=GetScrap(1),cap=GetMaxScrap(1)}' | Out-Null
    Wait-CRFlow $H 'return M.cr15.withdraw == true' -TimeoutSeconds 20 | Out-Null
    Invoke-CRFlow $H 'SetScrap(1,75); put(M.recy,"apcamr4_camerapod",40); tp("apcamr4_camerapod",30); return {scrap=GetScrap(1),cap=GetMaxScrap(1)}' | Out-Null
    Start-Sleep -Seconds 3
    $blocked=Invoke-CRFlow $H 'return M.won ~= true'
    Add-CRFlowCheck '75 scrap and Texas alone cannot finish without guest' ([bool]$blocked) $blocked
}
Invoke-CRFlowStep 'All humans return and share the victory' {
    Invoke-CRFlow $G 'return tp("apcamr4_camerapod",30)' | Out-Null
    foreach($c in @(Get-CRFlowClientIndices)) { Wait-CRFlowOp $c 'SucceedMission' -TimeoutSeconds 45 | Out-Null }
    return $true
}
