# Core objective path: base destruction cannot finish without a relic discovery.
# Colorado/walker story branches and natural combat remain separate checks.
param()
$participants=@(Get-CRFlowClientIndices)
Invoke-CRFlowStep 'Mission 8 starts; protect Utah and every human (ASSIST)' {
    Wait-CRFlow 0 'return M.start_done and IsAlive(M.nsdfrecycle)' -TimeoutSeconds 90 | Out-Null
    Invoke-CRFlow 0 "every('protectUtah',0.5,function() heal(M.nsdfrecycle) end);return true" | Out-Null
    foreach($client in $participants) { Invoke-CRFlow $client "every('qualificationHeal',0.5,function() heal(me()) end);return true" | Out-Null }
}
Invoke-CRFlowStep 'CCA base destroyed; missing relic prevents victory (ASSIST: host damage)' {
    Invoke-CRFlow 0 'return kill(M.ccarecycle),kill(M.ccamuf)' | Out-Null
    Wait-CRFlow 0 'return M.base_dead' -TimeoutSeconds 25 | Out-Null
    foreach($client in $participants) { Wait-CRFlowOp $client AddObjective 'misn0802.otf' -TimeoutSeconds 20 | Out-Null }
    $pending=Invoke-CRFlow 0 'return not M.cerb_found and not M.coopResult'
    Add-CRFlowCheck 'base loss alone does not win' ([bool]$pending) $pending
}
Invoke-CRFlowStep 'Fourth human discovers the relic; every peer wins (ASSIST: owner-local travel)' {
    $pos=Invoke-CRFlow 0 'return xyz(M.main_relic)'
    Invoke-CRFlow $participants[-1] ('return tp(SetVector('+($pos -join ',')+'),35)') | Out-Null
    foreach($client in $participants) { Wait-CRFlowOp $client SucceedMission 'misn08w1.des' -TimeoutSeconds 35 | Out-Null }
}
Test-CRFlowResultParity -Expect SucceedMission -Debrief 'misn08w1.des' -Clients $participants
