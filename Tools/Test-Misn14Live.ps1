# Native mission progression with explicit owner-local assists. No guest M writes.
param([ValidateSet('win','recycler-loss')][string]$Mode='win')
$H=0
$participants=@(Get-CRFlowClientIndices)
Invoke-CRFlowStep 'Mission 14 starts; protect Texas, survivors and humans (ASSIST)' {
    Wait-CRFlow $H 'return M.start_done and M.fury_built' -TimeoutSeconds 90 | Out-Null
    Invoke-CRFlow $H "every('protectMission',0.5,function() heal(M.recy); for _,k in ipairs({'guy1','guy2','guy3','apc'}) do if IsAlive(M[k]) then heal(M[k]) end end end); return true" | Out-Null
    foreach($client in $participants) { Invoke-CRFlow $client "every('protectHuman',0.5,function() heal(me()) end); return true" | Out-Null }
    foreach($client in $participants) {
        $state=Wait-CRFlow $client 'local teams={0,0,0,0};local n=0;for h in AllCraft() do if IsAlive(h) and (IsOdf(h,"avsav14") or IsOdf(h,"avsav14.odf")) then local t=GetTeamNum(h);if t>=1 and t<=4 then teams[t]=teams[t]+1;n=n+1 end end end;return n>=2*CRCoop.ForEachHumanTeam(function() end) and {n=n,teams=teams}' -TimeoutSeconds 30
        Add-CRFlowCheck "c$client sees two dormant Furies per human" ($state.n -eq 2*$participants.Count) $state
    }
}
if($Mode -eq 'recycler-loss') {
    Invoke-CRFlowStep 'Texas loss fails every peer (ASSIST: owner damage)' {
        Invoke-CRFlow $H "cancel('protectMission'); return kill(M.recy)" | Out-Null
        foreach($client in $participants) { Wait-CRFlowOp $client FailMission 'misn14l1.des' -TimeoutSeconds 30 | Out-Null }
    }
    Test-CRFlowResultParity -Expect FailMission -Debrief 'misn14l1.des' -Clients $participants
    return
}
Invoke-CRFlowStep 'Shared intro ends; activation hands each human a Fury pair (ASSIST: activation deadline)' {
    Wait-CRFlow $H 'return M.fury_phase=="waiting"' -TimeoutSeconds 70 | Out-Null
    Invoke-CRFlow $H 'M.fury_time=GetTime()-1;return true' | Out-Null
    Wait-CRFlow $H 'return M.fury_phase=="control"' -TimeoutSeconds 40 | Out-Null
    foreach($client in $participants) {
        $row=Invoke-CRFlow $client 'local n=0;local commandable=0;local t=GetTeamNum(me());for h in AllCraft() do if IsAlive(h) and GetTeamNum(h)==t and (IsOdf(h,"avsav14") or IsOdf(h,"avsav14.odf")) then n=n+1;if CanCommand(h) then commandable=commandable+1 end end end;return {n=n,commandable=commandable}'
        Add-CRFlowCheck "c$client can command its two Furies" ($row.n -eq 2 -and $row.commandable -eq 2) $row
    }
}
Invoke-CRFlowStep 'Loss of control re-teams every Fury to team 6 on every peer (ASSIST: deadline)' {
    Invoke-CRFlow $H 'M.fury_time=GetTime()-1;return true' | Out-Null
    Wait-CRFlow $H 'return M.fury_phase=="rogue"' -TimeoutSeconds 25 | Out-Null
    foreach($client in $participants) {
        $n=Wait-CRFlow $client 'local n=0;for h in AllCraft() do if IsAlive(h) and GetTeamNum(h)==6 and (IsOdf(h,"avsav14") or IsOdf(h,"avsav14.odf")) then n=n+1 end end;return n>=2*CRCoop.ForEachHumanTeam(function() end) and n' -TimeoutSeconds 20
        Add-CRFlowCheck "c$client observes all rogue Furies" ($n -eq 2*$participants.Count) $n
    }
    # Clear the tested rogue squad so later rescue checks isolate rescue logic.
    Invoke-CRFlow $H 'for _,e in ipairs(M.fury_squad or {}) do kill(e.unit) end;return true' | Out-Null
}
for($beacon=1;$beacon -le 3;$beacon++) {
    Invoke-CRFlowStep "Rescue beacon $beacon completes (ASSIST: host APC, travel and deadline)" {
        if($beacon -eq 1) {
            Invoke-CRFlow $H 'qualificationApc=BuildObject("avapc",1,GetPositionNear(GetPosition(M.recy),50,70));M.beacon_time1=GetTime()-1;return true' | Out-Null
        } else {
            Invoke-CRFlow $H ('M.beacon_time'+$beacon+'=GetTime()-1;return true') | Out-Null
        }
        Wait-CRFlow $H ('return IsAlive(M.beacon'+$beacon+')') -TimeoutSeconds 20 | Out-Null
        Invoke-CRFlow $H ('return put(qualificationApc,M.beacon'+$beacon+',20)') | Out-Null
        Wait-CRFlow $H ('return M.rescue'+$beacon) -TimeoutSeconds 20 | Out-Null
        Invoke-CRFlow $H ('M.rescue_finish'+$beacon+'=GetTime()-1;return true') | Out-Null
        Start-Sleep -Seconds 4
    }
}
Invoke-CRFlowStep 'Five Fury waves and CCA surrender (ASSIST: wave deadlines and cleanup)' {
    for($wave=1;$wave -le 5;$wave++) {
        Invoke-CRFlow $H 'for _,h in ipairs(M.fury_wave_units or {}) do kill(h) end; M.alien_time=GetTime()-1; return true' | Out-Null
        Wait-CRFlow $H ('return M.wave_count>='+$wave) -TimeoutSeconds 25 | Out-Null
    }
    Wait-CRFlow $H 'return M.cca_surrender and M.rescue_start' -TimeoutSeconds 45 | Out-Null
    foreach($client in $participants) {
        $row=Wait-CRFlow $client 'local b=GetHandle("sbbarr0_i76building");local p=GetHandle("sblpow1_powerplant");return IsValid(b) and IsValid(p) and GetTeamNum(b)==7 and GetTeamNum(p)==7 and true' -TimeoutSeconds 20
        Add-CRFlowCheck "c$client sees surrendered scientists and power plant on team 7" ([bool]$row) $row
    }
}
Invoke-CRFlowStep 'Scientists board APC; carrier returns to Texas and all humans win (ASSIST: host travel)' {
    Invoke-CRFlow $H 'return put(qualificationApc,M.base,40)' | Out-Null
    Wait-CRFlow $H 'return M.pick_up' -TimeoutSeconds 20 | Out-Null
    Invoke-CRFlow $H 'return put(qualificationApc,M.recy,80)' | Out-Null
    foreach($client in $participants) { Wait-CRFlowOp $client SucceedMission 'misn14w1.des' -TimeoutSeconds 30 | Out-Null }
}
Test-CRFlowResultParity -Expect SucceedMission -Debrief 'misn14w1.des' -Clients $participants
