# Targeted native scene test. Host damage/healing are explicit progression assists.
param([int]$HostClient=0,[int]$GuestClient=1)
$H=$HostClient;$G=$GuestClient
Invoke-CRFlowStep 'Mission 16 scene loads on all native peers' {
    foreach($c in @(Get-CRFlowClientIndices)) {
        Wait-CRFlow $c 'return M.coopMissionStarted == true' -TimeoutSeconds 90 | Out-Null
        Invoke-CRFlow $c "every('sceneHeal',0.5,function() heal(me()) end); return true" | Out-Null
        $layout=Invoke-CRFlow $c 'local h=GetHandle("cr16_transport");local p=GetPosition(h);return {x=p.x,y=p.y,z=p.z,parts=IsValid(GetHandle("cr16_engine4"))}'
        Add-CRFlowCheck "c$c sees preplaced transport beyond edge" ($layout.x -gt 3414 -and $layout.parts) $layout
    }
    $preflight=Invoke-CRFlow $H 'local rows={};for h in AllCraft() do if GetTeamNum(h)==6 then local p=GetPosition(h);rows[#rows+1]={label=GetLabel(h),odf=GetOdf(h),x=p.x,y=p.y,z=p.z} end end;return {savedOne=IsValid(M.cr16.evac[1]),labelOne=IsValid(GetHandle("cr16_evac1")),furies=rows}'
    Write-Host ('EVAC-PREFLIGHT '+($preflight | ConvertTo-Json -Depth 5 -Compress))
    Wait-CRFlow $H 'return M.start_done and GetTime() > M.cr16.started+21' -TimeoutSeconds 45 | Out-Null
}
Invoke-CRFlowStep 'First facility loss starts physical evacuation' {
    Invoke-CRFlow $H 'Damage(M.base1,1e9);return true' | Out-Null
    Wait-CRFlow $H 'return M.cr16.evacuating == true' -TimeoutSeconds 10 | Out-Null
    Start-Sleep -Seconds 12
    $approach=Invoke-CRFlow $H 'local h=GetHandle("cr16_evac1");local p=IsValid(h) and GetPosition(h);return {boarded=M.cr16.boarded,x=p and p.x,y=p and p.y,z=p and p.z}'
    Write-Host ('EVAC-APPROACH '+($approach | ConvertTo-Json -Compress))

}
Invoke-CRFlowStep 'Final facility loss shows boarding scene and VO' {
    # Explicit combat-clear assist permits the safe optional cinematic to play.
    Invoke-CRFlow $H 'for h in AllCraft() do local l=GetLabel(h);if GetTeamNum(h)==6 and l~="cr16_evac1" and l~="cr16_evac2" and (IsOdf(h,"hvsav") or IsOdf(h,"hvsav.odf") or IsOdf(h,"hvsat") or IsOdf(h,"hvsat.odf")) then RemoveObject(h) end end;Damage(M.base2,1e9);return true' | Out-Null
    Wait-CRFlow $H 'return M.cr16.finale == "boarding"' -TimeoutSeconds 15 | Out-Null
    Wait-CRFlow $H 'return M.cr16.sceneCamera == true' -TimeoutSeconds 15 | Out-Null
    Start-Sleep -Seconds 6
}
Invoke-CRFlowStep 'Hull and engines lift together on each native peer' {
    Wait-CRFlow $H 'return M.cr16.boarded == 2 and M.cr16.finale == "boarding"' -TimeoutSeconds 55 | Out-Null
    Wait-CRFlow $H 'return M.cr16.finale == "launch"' -TimeoutSeconds 80 | Out-Null
    foreach($c in @(Get-CRFlowClientIndices)) {
        $lift=Wait-CRFlow $c 'local a=GetPosition(GetHandle("cr16_transport"));local b=GetPosition(GetHandle("cr16_engine1"));return a.y>20 and {hull=a.y,engine=b.y}' -TimeoutSeconds 20
        Add-CRFlowCheck "c$c hull and engine stay attached" ([Math]::Abs($lift.hull-$lift.engine) -lt 1.0) $lift
    }
}
Invoke-CRFlowStep 'Departure produces one shared victory' {
    foreach($c in @(Get-CRFlowClientIndices)) {Wait-CRFlowOp $c 'SucceedMission' -TimeoutSeconds 50 | Out-Null}
}
Test-CRFlowResultParity -Expect SucceedMission -Debrief 'misn16w1.des' -Clients @(Get-CRFlowClientIndices)
