# Assisted core objective path; alarm/parachute and restored test-range branches
# require additional scenarios. Owner-local actions only, no guest state writes.
param()
$participants=@(Get-CRFlowClientIndices)
Invoke-CRFlowStep 'Mission 7 starts and all humans survive the test assists' {
    Wait-CRFlow 0 'return M.start_done' -TimeoutSeconds 90 | Out-Null
    foreach($client in $participants) { Invoke-CRFlow $client "every('qualificationHeal',0.5,function() heal(me()) end);return true" | Out-Null }
}
Invoke-CRFlowStep 'Guest meets the allied tanks (ASSIST: guest travel)' {
    $pos=Invoke-CRFlow 0 'return xyz(M.wingtank2)'
    Invoke-CRFlow 1 ('local p=SetVector('+($pos -join ',')+');p.x=p.x+25;p.y=p.y+3;SetPosition(me(),p);SetVelocity(me(),SetVector(0,0,0));return true') | Out-Null
    Wait-CRFlow 0 'return M.rendezvous' -TimeoutSeconds 35 | Out-Null
    foreach($client in $participants) { Wait-CRFlowOp $client AddObjective 'misn0701.otf' -TimeoutSeconds 20 | Out-Null }
}
Invoke-CRFlowStep 'Radar array falls; Utah convoy arrives (ASSIST: host damage and travel deadline)' {
    Invoke-CRFlow 0 'return kill(M.ccacomtower)' | Out-Null
    Wait-CRFlow 0 'return M.first_objective and M.next_mission and IsAlive(M.nsdfrecycle)' -TimeoutSeconds 35 | Out-Null
    Invoke-CRFlow 0 "every('protectUtah',0.5,function() heal(M.nsdfrecycle) end);return true" | Out-Null
    foreach($client in $participants) { Wait-CRFlowOp $client AddObjective 'misn0703.otf' -TimeoutSeconds 20 | Out-Null }
}
Invoke-CRFlowStep 'CCA recycler destruction completes shared victory (ASSIST: host damage)' {
    Invoke-CRFlow 0 'return kill(M.ccarecycle)' | Out-Null
    foreach($client in $participants) { Wait-CRFlowOp $client SucceedMission 'misn07w1.des' -TimeoutSeconds 35 | Out-Null }
}
Test-CRFlowResultParity -Expect SucceedMission -Debrief 'misn07w1.des' -Clients $participants
