# Native geometry/weather smoke and visual captures, followed by stock victory.
param([int]$HostClient = 0)
Invoke-CRFlowStep 'Jungle rain, river and foliage initialize on every native peer' {
    foreach($c in @(Get-CRFlowClientIndices)) {
        # The mission body runs only on the authority, so only it sets openingcindone.
        $ready=if($c -eq $HostClient){'return M.coopMissionStarted and M.openingcindone'}else{'return M.coopMissionStarted == true'}
        Wait-CRFlow $c $ready -TimeoutSeconds 100 | Out-Null
        Invoke-CRFlow $c "every('jungleHeal',0.5,function() heal(me()) end);return true" | Out-Null
        try {
            $d=Wait-CRFlow $c 'local j=M.cr17Jungle;return j and j.river and j.mist and j.batches==j.totalBatches and j' -TimeoutSeconds 80
        } catch {
            $diagnostic=Invoke-CRFlow $c 'return M.cr17Jungle'
            Add-CRFlowCheck "c$c jungle initialization diagnostic" $false $diagnostic
            throw
        }
        Add-CRFlowCheck "c$c finishes bounded foliage batches and river/mist" (-not $d.error -and $d.batches -gt 0) $d
        $plant=Invoke-CRFlow $c 'local h;for _,p in ipairs(require("CRJungle17Sites").trees) do if p.preplaced==1 then M.jungleTree=p.label;h=GetHandle(p.label);break end end;return {valid=IsValid(h),plant=exu.IsPlant and IsValid(h) and exu.IsPlant(GetOdf(h)),odf=GetOdf(h),health=GetCurHealth(h)}'
        Add-CRFlowCheck "c$c sees a solid native plant" ($plant.valid -and $plant.plant -and $plant.health -gt 0) $plant
        Invoke-CRFlow $c 'local p=require("PersistentConfig");p.Settings.WeaponStatsHud=false;p._DestroyAllPdaOverlays();if exu.SetViewportOverlaysEnabled then exu.SetViewportOverlaysEnabled(false) end;M.jungleCamera=true;CameraReady();every("jungleCamera",0.05,function() if M.jungleCamera then local h=GetHandle(M.jungleTree);CameraObject(h,3000,1800,5000,h) end end);return true' | Out-Null
    }
    Start-Sleep -Seconds 4
}
Invoke-CRFlowStep 'Waterfall and stream flow through the western ravine' {
    foreach($c in @(Get-CRFlowClientIndices)) {
        Invoke-CRFlow $c 'M.jungleCamera=false;CameraFinish();local s=require("CRJungle17Sites").cascade;SetPosition(me(),SetVector(s[1],s[2]+2,s[3]));CameraReady();M.jungleRiverCamera=true;every("jungleRiverCamera",0.05,function() if M.jungleRiverCamera then CameraObject(me(),2500,1600,3200,me()) end end);return true' | Out-Null
    }
    Start-Sleep -Seconds 6
}
Invoke-CRFlowStep 'Rain escalates into a shared storm on every peer' {
    foreach($c in @(Get-CRFlowClientIndices)) {
        $d=Wait-CRFlow $c 'return M.cr17Jungle and M.cr17Jungle.phase==3 and M.cr17Jungle' -TimeoutSeconds 100
        Add-CRFlowCheck "c$c reaches heavy jungle rain" ($d.phase -eq 3) $d
        Invoke-CRFlow $c 'M.jungleRiverCamera=false;CameraFinish();if exu.SetViewportOverlaysEnabled then exu.SetViewportOverlaysEnabled(true) end;return true' | Out-Null
    }
}
Invoke-CRFlowStep 'Native plant destruction replicates without affecting mission gates' {
    Invoke-CRFlow 0 'Damage(GetHandle(M.jungleTree),1e9);return true' | Out-Null
    foreach($c in @(Get-CRFlowClientIndices)) {
        $gone=Wait-CRFlow $c 'return not IsAlive(GetHandle(M.jungleTree))' -TimeoutSeconds 15
        Add-CRFlowCheck "c$c sees destroyed plant" $gone
    }
}
Invoke-CRFlowStep 'Stock converter route remains available with the jungle active' {
    Invoke-CRFlow 0 'for i=1,3 do Damage(M["factorypart"..i],1e9) end;return true' | Out-Null
    foreach($c in @(Get-CRFlowClientIndices)) { Wait-CRFlowOp $c 'SucceedMission' -TimeoutSeconds 30 | Out-Null }
}
Test-CRFlowResultParity -Expect SucceedMission -Debrief 'misn17w1.des' -Clients @(Get-CRFlowClientIndices)
