# Native co-op progression. Assists act only on host-owned mission objects.
# Timer acceleration and kills qualify replication/gates, not combat balance.
param([ValidateSet('win','recycler-loss')][string]$Mode='win')
$H=0
$participants=@(Get-CRFlowClientIndices)
Invoke-CRFlowStep 'Mission 13 starts with all humans and protected Texas (ASSIST)' {
    Wait-CRFlow $H 'return M.start_done and IsAlive(M.nsdfrecycle)' -TimeoutSeconds 90 | Out-Null
    Invoke-CRFlow $H "every('protectTexas',0.5,function() heal(M.nsdfrecycle) end); return true" | Out-Null
    foreach($client in $participants) {
        Invoke-CRFlow $client "every('protectHuman',0.5,function() heal(me()) end); return true" | Out-Null
    }
}
if($Mode -eq 'recycler-loss') {
    Invoke-CRFlowStep 'Texas destruction fails every human (ASSIST: owner damage)' {
        Invoke-CRFlow $H "cancel('protectTexas'); return kill(M.nsdfrecycle)" | Out-Null
        foreach($client in $participants) { Wait-CRFlowOp $client FailMission 'misn13f1.des' -TimeoutSeconds 35 | Out-Null }
    }
    Test-CRFlowResultParity -Expect FailMission -Debrief 'misn13f1.des' -Clients $participants
    return
}
Invoke-CRFlowStep 'CCA AIP is active under native MultST (ASSIST: AIP deadline)' {
    Invoke-CRFlow $H "ff('^set_aip_time$'); return true" | Out-Null
    $plan=Wait-CRFlow $H 'local p=GetAIP(5);return p and p~="" and p~="nil" and p' -TimeoutSeconds 30
    Add-CRFlowCheck 'CCA native AIP assigned' ($plan -match 'misn13') $plan
}
Invoke-CRFlowStep 'Restored reinforcement waves scale to four humans (ASSIST: deadlines and wave cleanup)' {
    for($wave=1;$wave -le 3;$wave++) {
        Invoke-CRFlow $H 'for _,units in pairs(M.wave_units or {}) do for _,h in ipairs(units) do kill(h) end end; M.next_wave_time=GetTime()-1; return true' | Out-Null
        $row=Wait-CRFlow $H ('return M.wave_units['+$wave+'] and {count=#M.wave_units['+$wave+'], humans=CRCoop.ForEachHumanTeam(function() end)}') -TimeoutSeconds 35
        $expected=@(3,4,5)[$wave-1]+2*($participants.Count-1)
        Add-CRFlowCheck "wave $wave has $expected units for $($participants.Count) humans" ($row.count -eq $expected -and $row.humans -eq $participants.Count) $row
    }
}
Invoke-CRFlowStep 'Factory loss alone cannot win (ASSIST: owner damage)' {
    Invoke-CRFlow $H 'return kill(M.ccamuf)' | Out-Null
    Start-Sleep -Seconds 3
    $blocked=Invoke-CRFlow $H 'return not M.game_over and IsAlive(M.hangar)'
    Add-CRFlowCheck 'hangar and silos remain required' ([bool]$blocked) $blocked
}
Invoke-CRFlowStep 'Last silo blocks victory after factory and hangar fall (ASSIST: owner damage)' {
    Invoke-CRFlow $H 'return kill(M.hangar),kill(M.ccasilo1),kill(M.ccasilo2),kill(M.ccasilo3)' | Out-Null
    Start-Sleep -Seconds 3
    $blocked=Invoke-CRFlow $H 'return not M.game_over and IsAlive(M.ccasilo4)'
    Add-CRFlowCheck 'fourth silo is required' ([bool]$blocked) $blocked
}
Invoke-CRFlowStep 'All objectives destroyed; shared victory on every client (ASSIST: final silo)' {
    Invoke-CRFlow $H 'return kill(M.ccasilo4)' | Out-Null
    foreach($client in $participants) { Wait-CRFlowOp $client SucceedMission 'misn13w1.des' -TimeoutSeconds 35 | Out-Null }
}
Test-CRFlowResultParity -Expect SucceedMission -Debrief 'misn13w1.des' -Clients $participants
