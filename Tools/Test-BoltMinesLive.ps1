# Native mine art/ordnance fixture. No unit AI setters are used on mines.
Invoke-CRFlowStep 'Load private mine fixture' {
    foreach($c in @(Get-CRFlowClientIndices)) {
        Wait-CRFlow $c 'return M.coopMissionStarted == true' -TimeoutSeconds 90 | Out-Null
        Invoke-CRFlow $c 'local p=require("PersistentConfig");M.mineHudWasEnabled=p.Settings.WeaponStatsHud;p.Settings.WeaponStatsHud=false;p._HidePdaOverlay("stats");p._HidePdaOverlay("feedback");every("minePlayerHeal",0.5,function() heal(me()) end);return true' | Out-Null
    }
    Invoke-CRFlow 0 'every("mineBaseGuard",0.2,function() M.cr16.nextSav=1e9;M.cr16.nextSat=1e9;heal(M.recy);heal(M.muf) end);return true' | Out-Null
    Wait-CRFlow 0 'return M.start_done and not M.cr16.introUntil' -TimeoutSeconds 35 | Out-Null
    # Isolated art fixture: clear initial hostile craft so their hits cannot flash the camera.
    Invoke-CRFlow 0 'for h in AllCraft() do local t=GetTeamNum(h);if t==5 or t==6 then RemoveObject(h) end end;return true' | Out-Null
}
$rates=@{}
foreach($mineOdf in @('cromine','crfmine')) {
    Invoke-CRFlowStep "$mineOdf hull texture closeup" {
        $spawn=Invoke-CRFlow 0 "local y=GetTerrainHeightAndNormal(SetVector(3200,0,99550));M.mine=BuildObject('$mineOdf',6,SetVector(3200,y+1,99550));CameraReady();CameraObject(M.mine,250,160,-330,M.mine);every('mineArt',0.02,function() local pda=require('PersistentConfig');pda._HidePdaOverlay('stats');pda._HidePdaOverlay('feedback') end);return {mine=IsAlive(M.mine),height=y}"
        Add-CRFlowCheck "$mineOdf loaded in the open test field" $spawn.mine $spawn
        foreach($c in @(Get-CRFlowClientIndices)) {
            Wait-CRFlow $c "for h in AllObjects() do if IsAlive(h) and (IsOdf(h,'$mineOdf') or IsOdf(h,'$mineOdf.odf')) and GetDistance(h,SetVector(3200,5,99550))<10 then M.observedMine=h;return true end end;return false" -TimeoutSeconds 15 | Out-Null
        }
        Start-Sleep -Seconds 5
    }
    Invoke-CRFlowStep "$mineOdf firing effects and native damage" {
        Invoke-CRFlow 0 'CameraFinish();local y=GetTerrainHeightAndNormal(SetVector(3235,0,99550));M.mineTarget=BuildObject("avtank",1,SetVector(3235,y+1,99550));SetIndependence(M.mineTarget,0);Stop(M.mineTarget,0);GiveWeapon(M.mineTarget,"",0);GiveWeapon(M.mineTarget,"",1);SetMaxHealth(M.mineTarget,100000);SetCurHealth(M.mineTarget,100000);M.mineView=BuildObject("apcamr",1,SetVector(3217.5,5,99540));exu.SetEntityVisible(M.mineView,false);CameraReady();CameraObject(M.mineView,0,3000,-4000,M.mineView);return {target=IsAlive(M.mineTarget),weapon=GetWeaponClass(M.mine,0)}' | Out-Null
        Start-Sleep -Seconds 4
        $sample=Invoke-CRFlow 0 'M.mineSample={time=GetTime(),health=GetCurHealth(M.mineTarget)};return true'
        Start-Sleep -Seconds 3
        $damage=Invoke-CRFlow 0 'return {damage=M.mineSample.health-GetCurHealth(M.mineTarget),seconds=GetTime()-M.mineSample.time,mine=IsAlive(M.mine),distance=GetDistance(M.mine,M.mineTarget)}'
        Add-CRFlowCheck "$mineOdf inflicts native arc damage" ($damage.damage -gt 0 -and $damage.mine) $damage
        $rates[$mineOdf]=$damage.damage/[Math]::Max(0.01,$damage.seconds)
        Write-Host ('MINE-DAMAGE '+$mineOdf+' '+($damage|ConvertTo-Json -Compress))
    }
    Invoke-CRFlowStep "$mineOdf destruction is clearable" {
        Invoke-CRFlow 0 'CameraFinish();every("mineArt",1,function() end);RemoveObject(M.mineTarget);RemoveObject(M.mineView);Damage(M.mine,1e9);return true' | Out-Null
        Start-Sleep -Seconds 3
        foreach($c in @(Get-CRFlowClientIndices)) {
            Add-CRFlowCheck "c$c sees $mineOdf destroyed" (Invoke-CRFlow $c 'return not IsAlive(M.observedMine)')
        }
    }
}
Add-CRFlowCheck 'Fury mine is materially more damaging than Olympian mine' ($rates['crfmine'] -gt 1.5*$rates['cromine']) $rates

Invoke-CRFlowStep 'Restore private mine fixture HUD' {
    foreach($c in @(Get-CRFlowClientIndices)) {
        Invoke-CRFlow $c 'local p=require("PersistentConfig");p.Settings.WeaponStatsHud=M.mineHudWasEnabled;return true' | Out-Null
    }
}
