# Native model/weapon prototype, deliberately separate from mission balance tests.
# Explicit known-craft AI commands only. All progression assists are recorded.
Invoke-CRFlowStep 'Load the fighter fixture on every native peer' {
    foreach($c in @(Get-CRFlowClientIndices)) {
        Wait-CRFlow $c 'return M.coopMissionStarted == true' -TimeoutSeconds 90 | Out-Null
        Invoke-CRFlow $c 'every("fighterHeal",0.5,function() heal(me()) end);return true' | Out-Null
    }
    Invoke-CRFlow 0 'every("blockFuryWaves",0.1,function() M.cr16.nextSav=1e9;M.cr16.nextSat=1e9;heal(M.recy);heal(M.muf) end);return true' | Out-Null
    Wait-CRFlow 0 'return M.start_done and not M.cr16.introUntil' -TimeoutSeconds 35 | Out-Null
}
Invoke-CRFlowStep 'Original geometry and new material are visible' {
    $model=Invoke-CRFlow 0 'local p=GetPosition(me());p.x=p.x+70;p.z=p.z+50;M.fighter=BuildObject("crfraz",6,p);SetLabel(M.fighter,"fighterTest");SetIndependence(M.fighter,0);Stop(M.fighter,0);CameraReady();CameraObject(M.fighter,1200,600,-1700,M.fighter);every("artPda",0.02,function() local pda=require("PersistentConfig");pda._HidePdaOverlay("stats");pda._HidePdaOverlay("feedback") end);return {valid=IsAlive(M.fighter),left=GetWeaponClass(M.fighter,0),right=GetWeaponClass(M.fighter,1),max=GetMaxHealth(M.fighter)}'
    Add-CRFlowCheck 'Both custom Fury weapons installed' ($model.valid -and $model.left -match 'crfpuls' -and $model.right -match 'crfarc' -and $model.max -eq 2400) $model
    foreach($c in @(Get-CRFlowClientIndices)) {
        Wait-CRFlow $c 'for h in AllCraft() do if IsAlive(h) and (IsOdf(h,"crfraz") or IsOdf(h,"crfraz.odf")) then M.remoteFighter=h;return true end end;return false' -TimeoutSeconds 12 | Out-Null
    }
    Start-Sleep -Seconds 5
}
Invoke-CRFlowStep 'Both guns cause native damage with their own effects' {
    Invoke-CRFlow 0 'CameraFinish();every("artPda",1,function() end);local p=GetPosition(M.fighter);p.z=p.z+30;M.fighterTarget=BuildObject("avtank",1,p);SetIndependence(M.fighterTarget,0);Stop(M.fighterTarget,0);GiveWeapon(M.fighterTarget,"",0);GiveWeapon(M.fighterTarget,"",1);SetMaxHealth(M.fighterTarget,20000);SetCurHealth(M.fighterTarget,20000);Attack(M.fighter,M.fighterTarget,1);return true' | Out-Null
    foreach($mask in @(1,2)) {
        Invoke-CRFlow 0 "M.fighterBefore=GetCurHealth(M.fighterTarget);SetWeaponMask(M.fighter,$mask);every('testFire',0.1,function() if IsAlive(M.fighter) and IsAlive(M.fighterTarget) then SetWeaponMask(M.fighter,$mask);FireAt(M.fighter,M.fighterTarget) end end);return true" | Out-Null
        Start-Sleep -Seconds 7
        $damage=Invoke-CRFlow 0 'local d=M.fighterBefore-GetCurHealth(M.fighterTarget);return {damage=d,alive=IsAlive(M.fighter),ammo=GetCurAmmo(M.fighter),distance=GetDistance(M.fighter,M.fighterTarget)}'
        Write-Host ('FURY-WEAPON '+($damage|ConvertTo-Json -Compress))
        Add-CRFlowCheck "Gun mask $mask damages the stationary test target" ($damage.damage -gt 0 -and $damage.alive) $damage
    }
    Invoke-CRFlow 0 'every("testFire",1,function() end);RemoveObject(M.fighterTarget);Damage(M.fighter,1e9);return true' | Out-Null
    Start-Sleep -Seconds 4
}
foreach($i in 1..8) {
    Invoke-CRFlowStep "Gradual damage, movement and destruction cycle $i" {
        Invoke-CRFlow 0 'local p=GetPosition(me());p.x=p.x+90;p.z=p.z+70;M.fighter=BuildObject("crfraz",6,p);SetLabel(M.fighter,"fighterTest");SetIndependence(M.fighter,0);Goto(M.fighter,me(),1);return true' | Out-Null
        foreach($c in @(Get-CRFlowClientIndices)) {
            Wait-CRFlow $c 'for h in AllCraft() do if IsAlive(h) and (IsOdf(h,"crfraz") or IsOdf(h,"crfraz.odf")) then M.remoteFighter=h;return true end end;return false' -TimeoutSeconds 12 | Out-Null
        }
        Start-Sleep -Seconds 2
        Invoke-CRFlow 0 'Damage(M.fighter,600);return true' | Out-Null
        Start-Sleep -Seconds 2
        Invoke-CRFlow 0 'Damage(M.fighter,1200);return true' | Out-Null
        Start-Sleep -Seconds 2
        Invoke-CRFlow 0 'Damage(M.fighter,1e9);return true' | Out-Null
        Start-Sleep -Seconds 3
        foreach($c in @(Get-CRFlowClientIndices)) {
            $dead=Invoke-CRFlow $c 'return M.remoteFighter~=nil and not IsAlive(M.remoteFighter)'
            Add-CRFlowCheck "c$c observes destruction and keeps simulating" $dead
        }
    }
}
