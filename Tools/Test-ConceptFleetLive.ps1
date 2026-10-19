# Isolated four-ship preview. Feed Build-CarrierPreviewMap.py --fleet output to
# Run-BZRCoopMission.ps1 -ContentOverride; never place these in shipping misn06.
$fleetPeers = @(Get-CRFlowClientIndices)
Invoke-CRFlowStep 'mission opening completes; four preplaced neutral fixtures load' {
    foreach ($fleetPeer in $fleetPeers) {
        Wait-CRFlowEvent $fleetPeer attach -TimeoutSeconds 120 | Out-Null
        Wait-CRFlow $fleetPeer 'return role().ready' -TimeoutSeconds 60 | Out-Null
        Invoke-CRFlow $fleetPeer "every('protect-preview',.5,function() heal(me());if IsValid(M.avrec) then heal(M.avrec) end end);return true" | Out-Null
    }
    Wait-CRFlow 0 'return M.missionstart==false and not M.opencamdone and GetTime()>=45' -TimeoutSeconds 70 | Out-Null
    foreach ($fleetPeer in $fleetPeers) {
        Invoke-CRFlow $fleetPeer 'local p=require("PersistentConfig");p.Settings.WeaponStatsHud=false;p._DestroyAllPdaOverlays();if exu.SetViewportOverlaysEnabled then exu.SetViewportOverlaysEnabled(false) end;fleetClip={exu.GetCameraClipDistances()};return true' | Out-Null
        foreach ($fleetAsset in @('crncarr','crccarr','crcred1','crcred2')) {
            $fleetLabel = if ($fleetAsset -eq 'crncarr') { 'cr_carrier_preview' } else { 'cr_fleet_'+$fleetAsset }
            $fleetInfo=Invoke-CRFlow $fleetPeer "local h=GetHandle('$fleetLabel');return IsValid(h) and {odf=GetOdf(h),hp=GetMaxHealth(h),material=exu.GetMaterialName(h)}"
            Add-CRFlowCheck "c$fleetPeer loads $fleetAsset static mesh and material" ([bool]$fleetInfo -and $fleetInfo.odf -eq $fleetAsset -and $fleetInfo.hp -eq 0 -and $fleetInfo.material -eq ($fleetAsset+'00')) $fleetInfo
        }
    }
}
foreach ($fleetAsset in @('crncarr','crccarr','crcred1','crcred2')) {
    $fleetLabel = if ($fleetAsset -eq 'crncarr') { 'cr_carrier_preview' } else { 'cr_fleet_'+$fleetAsset }
    $fleetRange = if ($fleetAsset -in @('crncarr','crccarr')) { 20000 } else { 12000 }
    Invoke-CRFlowStep "$fleetAsset concept side" {
        foreach ($fleetPeer in $fleetPeers) {
            Invoke-CRFlow $fleetPeer "fleetShip=GetHandle('$fleetLabel');fleetView={$fleetRange,0,0};native.CameraReady();every('fleet-view',0,function() exu.SetFog(.03,.04,.06,4000,5000);native.CameraObject(fleetShip,fleetView[1],fleetView[2],fleetView[3],fleetShip);exu.SetCameraClipDistances(.1,5000) end);return true" | Out-Null
            Wait-CRFlow $fleetPeer 'local c=exu.GetCameraTransformMatrix();return c and c.posit_y>500' -TimeoutSeconds 8 | Out-Null
        }
    }
    Invoke-CRFlowStep "$fleetAsset bow three-quarter" {
        foreach ($fleetPeer in $fleetPeers) {
            Invoke-CRFlow $fleetPeer "fleetView={$([int]($fleetRange*.75)),$([int]($fleetRange*.3)),-$fleetRange};fleetViewAt=GetTime();return true" | Out-Null
            Wait-CRFlow $fleetPeer 'return GetTime()-fleetViewAt>.6' -TimeoutSeconds 4 | Out-Null
        }
    }
    Invoke-CRFlowStep "$fleetAsset aft engines" {
        foreach ($fleetPeer in $fleetPeers) {
            Invoke-CRFlow $fleetPeer "fleetView={$([int]($fleetRange*.75)),$([int]($fleetRange*.3)),$fleetRange};fleetViewAt=GetTime();return true" | Out-Null
            Wait-CRFlow $fleetPeer 'return GetTime()-fleetViewAt>.6' -TimeoutSeconds 4 | Out-Null
        }
    }
    Invoke-CRFlowStep "$fleetAsset bounded peer-local flyby; release camera" {
        foreach ($fleetPeer in $fleetPeers) {
            Invoke-CRFlow $fleetPeer 'fleetPose=GetTransform(fleetShip);fleetZ=fleetPose.posit_z;fleetStarted=GetTime();every("fleet-flight",0,function() local t=math.min(4,math.max(0,GetTime()-fleetStarted));fleetPose.posit_z=fleetZ-6*t;SetTransform(fleetShip,fleetPose) end);return true' | Out-Null
        }
        foreach ($fleetPeer in $fleetPeers) {
            # A remote static actor's transform readback is interpolated. Hold
            # the actual bounded endpoint until BOTH clients reach it; do not
            # infer distance from either clock or keep moving the finish line.
            Wait-CRFlow $fleetPeer 'local p=GetTransform(fleetShip);return GetTime()-fleetStarted>=4 and math.abs(fleetZ-p.posit_z-24)<.15' -TimeoutSeconds 12 | Out-Null
            $fleetMoved=Invoke-CRFlow $fleetPeer 'local p=GetTransform(fleetShip);return {valid=IsValid(fleetShip),distance=fleetZ-p.posit_z,elapsed=GetTime()-fleetStarted}'
            Add-CRFlowCheck "c$fleetPeer reaches $fleetAsset 24m flyby endpoint" ($fleetMoved.valid -and [math]::Abs($fleetMoved.distance-24) -lt .15) $fleetMoved
            Invoke-CRFlow $fleetPeer 'cancel("fleet-view");cancel("fleet-flight");native.CameraFinish();return true' | Out-Null
        }
    }
}
Invoke-CRFlowStep 'restore preview clip distances and leave fixtures valid' {
    foreach ($fleetPeer in $fleetPeers) {
        Invoke-CRFlow $fleetPeer 'if type(fleetClip[1])=="number" and type(fleetClip[2])=="number" then exu.SetCameraClipDistances(fleetClip[1],fleetClip[2]) end;cancel("protect-preview");return true' | Out-Null
    }
}
