# Native four-human checkpoint/uplink/extraction qualification.
# ASSIST: owner-local replicated svfi12 craft and SetAsUser replace physical
# sniping/boarding. Physical capture and natural stealth remain separate gates.
param()
$H=0
$participants=@(Get-CRFlowClientIndices)
$guests=@($participants | Where-Object {$_ -ne $H})
Invoke-CRFlowStep 'Mission 12 starts; humans protected during assisted progression' {
    Wait-CRFlow $H 'return M.start_done' -TimeoutSeconds 90 | Out-Null
    foreach($client in $participants) { Invoke-CRFlow $client "every('qualificationHeal',0.5,function() heal(me()) end); return true" | Out-Null }
}
Invoke-CRFlowStep 'Each human assumes an owner-local replicated key ship (ASSIST; physical boarding unverified)' {
    foreach($client in $participants) {
        $row=Invoke-CRFlow $client 'local exu=require("exu");local old=me();local h=exu.BuildSyncObject("svfi12",GetTeamNum(old),GetPosition(old));assert(IsValid(h),"replicated key ship failed");exu.SetAsUser(h);qualificationShip=h;return describe(GetPlayerHandle())'
        Add-CRFlowCheck "c$client controls an svfi12 key ship" ($row.odf -match '^svfi12') $row
    }
    Wait-CRFlow $H ('local n=0;CRCoop.ForEachPlayerHandle(function(h) if IsOdf(h,"svfi12") or IsOdf(h,"svfi12.odf") then n=n+1 end end);return n=='+$participants.Count) -TimeoutSeconds 25 | Out-Null
    Wait-CRFlow $H 'return M.camera_off' -TimeoutSeconds 85 | Out-Null
}
foreach($checkpoint in 2..4) {
    Invoke-CRFlowStep "Every human checks in at checkpoint $checkpoint (ASSIST: travel)" {
        $label=@{2='svguntower2';3='svmuf';4='svsilo1'}[$checkpoint]
        foreach($client in $participants) {
            Invoke-CRFlow $client ('return tp(GetHandle("'+$label+'"),'+(20+8*$client)+')') | Out-Null
        }
        $row=Wait-CRFlow $H ('local n=0;for id,p in pairs(CRCoop.GetPlayers()) do local s=M.hcur==id and M or M.hstore[id];if s and s.check'+$checkpoint+' then n=n+1 end end;return n=='+$participants.Count+' and {n=n,blown=M.game_blown}') -TimeoutSeconds 25
        Add-CRFlowCheck "checkpoint $checkpoint records each human without blowing cover" ($row.n -eq $participants.Count -and -not $row.blown) $row
        Start-Sleep -Seconds 7
    }
}
Invoke-CRFlowStep 'Guest uplink breaks outside 85 m (ASSIST: travel; native 45 s timer)' {
    Invoke-CRFlow 1 'return tp(GetHandle("svcom_tower"),35)' | Out-Null
    Wait-CRFlow $H 'local s=M.hstore[2];return s and s.interface_connect' -TimeoutSeconds 20 | Out-Null
    Invoke-CRFlow 1 'return tp(GetHandle("svcom_tower"),100)' | Out-Null
    Wait-CRFlow $H 'local s=M.hstore[2];return s and not s.interface_connect and not M.interface_complete' -TimeoutSeconds 15 | Out-Null
}
Invoke-CRFlowStep 'Guest holds a full uplink; shared escape objective reaches every peer' {
    Invoke-CRFlow 1 'return tp(GetHandle("svcom_tower"),35)' | Out-Null
    Wait-CRFlow $H 'return M.interface_complete and not M.game_blown' -TimeoutSeconds 75 | Out-Null
    foreach($client in $participants) { Wait-CRFlowOp $client AddObjective 'misn1205.otf' -TimeoutSeconds 15 | Out-Null }
}
Invoke-CRFlowStep 'One absent human blocks extraction; all humans then share victory (ASSIST: travel and win poll)' {
    foreach($client in @($participants | Select-Object -SkipLast 1)) {
        Invoke-CRFlow $client 'return tp(GetHandle("apcamr20_camerapod"),25)' | Out-Null
    }
    Invoke-CRFlow $H 'M.win_check_time=GetTime()-1;return true' | Out-Null
    Start-Sleep -Seconds 4
    $blocked=Invoke-CRFlow $H 'return not M.win'
    Add-CRFlowCheck 'extraction waits for fourth human' ([bool]$blocked) $blocked
    Invoke-CRFlow $participants[-1] 'return tp(GetHandle("apcamr20_camerapod"),25)' | Out-Null
    foreach($client in $participants) { Wait-CRFlowOp $client SucceedMission 'misn12w1.des' -TimeoutSeconds 25 | Out-Null }
}
Test-CRFlowResultParity -Expect SucceedMission -Debrief 'misn12w1.des' -Clients $participants
