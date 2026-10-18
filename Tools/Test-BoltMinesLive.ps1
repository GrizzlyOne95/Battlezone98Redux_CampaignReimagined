# Native mine art/ordnance fixture. No unit AI setters are used on mines.
Invoke-CRFlowStep 'Load private mine fixture' {
    foreach($c in @(Get-CRFlowClientIndices)) {
        Wait-CRFlow $c 'return M.coopMissionStarted == true' -TimeoutSeconds 90 | Out-Null
        Invoke-CRFlow $c 'every("minePlayerHeal",0.5,function() heal(me()) end);return true' | Out-Null
    }
    Invoke-CRFlow 0 'every("mineBaseGuard",0.2,function() M.cr16.nextSav=1e9;M.cr16.nextSat=1e9;heal(M.recy);heal(M.muf) end);return true' | Out-Null
    Wait-CRFlow 0 'return M.start_done and not M.cr16.introUntil' -TimeoutSeconds 35 | Out-Null
}
$rates=@{}
foreach($mineOdf in @('cromine','crfmine')) {
    Invoke-CRFlowStep "$mineOdf hull and firing effects" {
        $spawn=Invoke-CRFlow 0 "local p=SetVector(3900,7,100000);M.mine=BuildObject('$mineOdf',6,p);M.mineTarget=BuildObject('avtank',1,SetVector(3900,7,100035));SetIndependence(M.mineTarget,0);Stop(M.mineTarget,0);GiveWeapon(M.mineTarget,'',0);GiveWeapon(M.mineTarget,'',1);SetMaxHealth(M.mineTarget,100000);SetCurHealth(M.mineTarget,100000);CameraReady();CameraObject(M.mine,1000,600,-1300,M.mineTarget);every('mineArt',0.02,function() local pda=require('PersistentConfig');pda._HidePdaOverlay('stats');pda._HidePdaOverlay('feedback') end);return {mine=IsAlive(M.mine),target=IsAlive(M.mineTarget)}"
        Add-CRFlowCheck "$mineOdf and inert test target loaded" ($spawn.mine -and $spawn.target) $spawn
        foreach($c in @(Get-CRFlowClientIndices)) {
            Wait-CRFlow $c "for h in AllObjects() do if IsAlive(h) and (IsOdf(h,'$mineOdf') or IsOdf(h,'$mineOdf.odf')) then M.observedMine=h;return true end end;return false" -TimeoutSeconds 15 | Out-Null
        }
        Start-Sleep -Seconds 5
        $sample=Invoke-CRFlow 0 'M.mineSample={time=GetTime(),health=GetCurHealth(M.mineTarget)};return true'
        Start-Sleep -Seconds 3
        $damage=Invoke-CRFlow 0 'return {damage=M.mineSample.health-GetCurHealth(M.mineTarget),seconds=GetTime()-M.mineSample.time,mine=IsAlive(M.mine),distance=GetDistance(M.mine,M.mineTarget)}'
        Add-CRFlowCheck "$mineOdf inflicts native arc damage" ($damage.damage -gt 0 -and $damage.mine) $damage
        $rates[$mineOdf]=$damage.damage/[Math]::Max(0.01,$damage.seconds)
        Write-Host ('MINE-DAMAGE '+$mineOdf+' '+($damage|ConvertTo-Json -Compress))
    }
    Invoke-CRFlowStep "$mineOdf destruction is clearable" {
        Invoke-CRFlow 0 'CameraFinish();every("mineArt",1,function() end);RemoveObject(M.mineTarget);Damage(M.mine,1e9);return true' | Out-Null
        Start-Sleep -Seconds 3
        foreach($c in @(Get-CRFlowClientIndices)) {
            Add-CRFlowCheck "c$c sees $mineOdf destroyed" (Invoke-CRFlow $c 'return not IsAlive(M.observedMine)')
        }
    }
}
Add-CRFlowCheck 'Fury mine is materially more damaging than Olympian mine' ($rates['crfmine'] -gt 1.5*$rates['cromine']) $rates
