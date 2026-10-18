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
        Invoke-CRFlow $c 'M.jungleCamera=false;CameraFinish();local s=require("CRJungle17Sites").cascade;SetPosition(me(),SetVector(s[1],s[2]+2,s[3]));CameraReady();M.jungleCamHeld=true;M.jungleRiverCamera=true;every("jungleRiverCamera",0.05,function() if M.jungleRiverCamera then CameraObject(me(),2500,1600,3200,me()) end end);return true' | Out-Null
    }
    Start-Sleep -Seconds 6
}
Invoke-CRFlowStep 'First tower loss brings a downpour on every peer' {
    # Release the test camera before any tower falls: the mission's mine cinematic
    # pops the camera stack itself, and a second pop raises a modal Fsm alert.
    foreach($c in @(Get-CRFlowClientIndices)) { Invoke-CRFlow $c 'M.jungleRiverCamera=false;if M.jungleCamHeld then M.jungleCamHeld=false;CameraFinish() end;return true' | Out-Null }
    foreach($c in @(Get-CRFlowClientIndices)) {
        $d=Wait-CRFlow $c 'local j=M.cr17Jungle;return j and j.level==1 and j' -TimeoutSeconds 20
        Add-CRFlowCheck "c$c opens in light rain with streams and pools" ($d.level -eq 1 -and $d.streams -and $d.pools -and $d.wind -gt 0) $d
    }
    Invoke-CRFlow $HostClient 'Damage(M.tower1,1e9);return true' | Out-Null
    foreach($c in @(Get-CRFlowClientIndices)) {
        $d=Wait-CRFlow $c 'local j=M.cr17Jungle;return j and j.level==2 and j' -TimeoutSeconds 30
        Add-CRFlowCheck "c$c follows the leader into downpour" ($d.level -eq 2) $d
    }
    Start-Sleep -Seconds 4
}
Invoke-CRFlowStep 'Tower collapse brings a shared lightning storm under a cloud deck' {
    Invoke-CRFlow $HostClient 'for i=2,7 do Damage(M["tower"..i],1e9) end;return true' | Out-Null
    foreach($c in @(Get-CRFlowClientIndices)) {
        $d=Wait-CRFlow $c 'local j=M.cr17Jungle;return j and j.level>=3 and (j.bolts or 0)>=1 and j' -TimeoutSeconds 45
        Add-CRFlowCheck "c$c storm with lightning" ($d.level -ge 3 -and $d.bolts -ge 1) $d
        Add-CRFlowCheck "c$c storm cloud deck" ($d.clouds -eq 'on') $d
    }
    Start-Sleep -Seconds 6
}
foreach($water in @('pools','streams')) {
    Invoke-CRFlowStep "Storm-lit $water hold water on the terrain" {
        foreach($c in @(Get-CRFlowClientIndices)) {
            # Cockpit view only: the mission's own cinematics pop the camera stack, and a
            # test push on top of them raises a modal "Camera Stack Overflow" alert.
            $v=Invoke-CRFlow $c "local v=require('CRJungle17Sites').$water.view;local x,z=v[1]+40,v[3]+40;local p=SetVector(x,GetTerrainHeightAndNormal(SetVector(x,0,z))+6,z);SetTransform(me(),BuildDirectionalMatrix(p,SetVector(v[1]-x,v[2]-p.y,v[3]-z)));return {x=v[1],y=v[2],z=v[3]}"
            Add-CRFlowCheck "c$c $water camera target" ($null -ne $v.x) $v
        }
        Start-Sleep -Seconds 5
    }
}
Invoke-CRFlowStep 'Native plant destruction replicates without affecting mission gates' {
    foreach($c in @(Get-CRFlowClientIndices)) { Invoke-CRFlow $c 'if exu.SetViewportOverlaysEnabled then exu.SetViewportOverlaysEnabled(true) end;return true' | Out-Null }
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
