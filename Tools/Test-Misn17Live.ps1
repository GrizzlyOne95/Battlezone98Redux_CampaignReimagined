# Bounded native progression assists; does not qualify natural combat balance.
param([int]$HostClient=0,[switch]$Loss)
$H=$HostClient
Invoke-CRFlowStep 'Mission 17 starts with the complete Fury defenses on every peer' {
    foreach($c in @(Get-CRFlowClientIndices)) {
        Wait-CRFlow $c 'return M.coopMissionStarted == true' -TimeoutSeconds 90 | Out-Null
        Invoke-CRFlow $c "every('cr17Heal',0.5,function() heal(me()) end);return true" | Out-Null
        $layout=Invoke-CRFlow $c 'local n=0;for i=1,54 do if IsValid(GetHandle("cr17_mine"..i)) then n=n+1 end end;return {mines=n,tower=IsValid(GetHandle("cr17_tower7")),recycler=GetTeamNum(GetHandle("avrecy18_recycler")),factory=GetTeamNum(GetHandle("savfactory1"))}'
        Add-CRFlowCheck "c$c sees 54 mines, seven towers and isolated Fury ownership" ($layout.mines -eq 54 -and $layout.tower -and $layout.recycler -eq 1 -and $layout.factory -eq 6) $layout
    }
    Wait-CRFlow $H 'return M.openingcindone == true' -TimeoutSeconds 60 | Out-Null
}
if($Loss) {
    Invoke-CRFlowStep 'Shared recycler loss reaches every peer' {
        Invoke-CRFlow $H 'Damage(M.avrec,1e9);return true' | Out-Null
        foreach($c in @(Get-CRFlowClientIndices)) {Wait-CRFlowOp $c 'FailMission' -TimeoutSeconds 35 | Out-Null}
    }
    Test-CRFlowResultParity -Expect FailMission -Debrief 'misn17l1.des' -Clients @(Get-CRFlowClientIndices)
    return
}
Invoke-CRFlowStep 'A guest approach activates tower defenders through concealed entry' {
    $g=@(Get-CRFlowClientIndices | Where-Object {$_ -ne $H})[0]
    Invoke-CRFlow $g 'SetPosition(me(),GetPosition(GetHandle("cr17_tower1")));return true' | Out-Null
    $def=Wait-CRFlow $H 'return M.tower1spawn and IsValid(M.deftow1a) and IsValid(M.deftow1b) and {a=GetOdf(M.deftow1a),b=GetOdf(M.deftow1b),team=GetTeamNum(M.deftow1a)}' -TimeoutSeconds 25
    Add-CRFlowCheck 'guest-triggered defense includes restored fighters on Fury team' ($def.team -eq 6 -and ($def.a -match 'crfraz' -or $def.b -match 'crfraz')) $def
}
Invoke-CRFlowStep 'Seven tower losses collapse all 54 mines and share the breach radio' {
    Invoke-CRFlow $H 'for i=1,7 do Damage(M["tower"..i],1e9) end;return true' | Out-Null
    Wait-CRFlow $H 'return M.towersdestroyed and not M.minesdestroyed' -TimeoutSeconds 20 | Out-Null
    foreach($c in @(Get-CRFlowClientIndices)) {
        $clean=Wait-CRFlow $c 'local n=0;for i=1,54 do if IsAlive(GetHandle("cr17_mine"..i)) then n=n+1 end end;return n==0' -TimeoutSeconds 20
        Add-CRFlowCheck "c$c has no surviving field mine" $clean
    }
}
Invoke-CRFlowStep 'Three converter losses trigger the factory finale and one shared victory' {
    Invoke-CRFlow $H 'for i=1,3 do Damage(M["factorypart"..i],1e9) end;return true' | Out-Null
    foreach($c in @(Get-CRFlowClientIndices)) {Wait-CRFlowOp $c 'SucceedMission' -TimeoutSeconds 30 | Out-Null}
    $ending=Invoke-CRFlow $H 'return {won=M.missionwon,a=M.sf2gone,b=M.sf3gone,c=M.sf4gone}'
    Add-CRFlowCheck 'all visual factory shells detonate before result' ($ending.won -and $ending.a -and $ending.b -and $ending.c) $ending
}
Test-CRFlowResultParity -Expect SucceedMission -Debrief 'misn17w1.des' -Clients @(Get-CRFlowClientIndices)
