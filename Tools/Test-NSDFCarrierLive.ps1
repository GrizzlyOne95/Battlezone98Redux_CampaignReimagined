# Isolated preview map produced by Build-CarrierPreviewMap.py. Never inserts a
# carrier into a campaign mission or issues unit AI commands to this fixture.
$carrierPeers = @(Get-CRFlowClientIndices)
Invoke-CRFlowStep 'opening camera ends; preplaced carrier exists on both peers' {
    foreach ($carrierPeer in $carrierPeers) {
        Wait-CRFlowEvent $carrierPeer attach -TimeoutSeconds 120 | Out-Null
        Wait-CRFlow $carrierPeer 'return role().ready' -TimeoutSeconds 60 | Out-Null
        Invoke-CRFlow $carrierPeer "every('protect-preview',0.5,function() heal(me()) end);return true" | Out-Null
    }
    Wait-CRFlow 0 'return M.missionstart == false and not M.opencamdone and GetTime()>=45' -TimeoutSeconds 60 | Out-Null
    foreach ($carrierPeer in $carrierPeers) {
        $carrierInfo=Invoke-CRFlow $carrierPeer 'carrier=GetHandle("cr_carrier_preview");return IsValid(carrier) and {obj=describe(carrier),material=exu.GetMaterialName(carrier),hp=GetMaxHealth(carrier)}'
        if (-not $carrierInfo -or $carrierInfo.obj.odf -ne 'crncarr' -or $carrierInfo.hp -ne 0) { throw "Carrier fixture invalid on c$carrierPeer" }
        Add-CRFlowCheck "c$carrierPeer loads carrier mesh/material" ([bool]$carrierInfo.material) $carrierInfo
        Invoke-CRFlow $carrierPeer 'local p=require("PersistentConfig");p.Settings.WeaponStatsHud=false;p._DestroyAllPdaOverlays();if exu.SetViewportOverlaysEnabled then exu.SetViewportOverlaysEnabled(false) end;if exu.GetCameraClipDistances then carrierClip={exu.GetCameraClipDistances()} end;native.CameraReady();carrierView={20000,0,0};every("carrier-view",0,function() exu.SetFog(.03,.04,.06,4000,5000);native.CameraObject(carrier,carrierView[1],carrierView[2],carrierView[3],carrier);if exu.SetCameraClipDistances then exu.SetCameraClipDistances(.1,5000) end end);return true' | Out-Null
    }
}
Invoke-CRFlowStep 'concept side profile and emissive windows' {
    foreach ($carrierPeer in $carrierPeers) {
        Invoke-CRFlow $carrierPeer 'carrierView={20000,0,0};return true' | Out-Null
        Wait-CRFlow $carrierPeer 'return GetTime()>48' -TimeoutSeconds 8 | Out-Null
    }
}
Invoke-CRFlowStep 'bow three-quarter view' {
    foreach ($carrierPeer in $carrierPeers) {
        Invoke-CRFlow $carrierPeer 'carrierView={15000,6000,-19000};return true' | Out-Null
    }
}
Invoke-CRFlowStep 'aft three-quarter and engine bank' {
    foreach ($carrierPeer in $carrierPeers) {
        Invoke-CRFlow $carrierPeer 'carrierView={15000,6000,19000};return true' | Out-Null
    }
}
Invoke-CRFlowStep 'bounded owner-local flyby' {
    foreach ($carrierPeer in $carrierPeers) {
        Invoke-CRFlow $carrierPeer 'carrierPose=GetTransform(carrier);carrierStarted=GetTime();carrierView={15000,6000,-19000};every("carrier-flight",0,function() carrierPose.posit_z=100900-6*(GetTime()-carrierStarted);SetTransform(carrier,carrierPose) end);return true' | Out-Null
    }
    foreach ($carrierPeer in $carrierPeers) {
        Wait-CRFlow $carrierPeer 'return GetTime()-carrierStarted>=4' -TimeoutSeconds 10 | Out-Null
        $carrierMoved=Invoke-CRFlow $carrierPeer 'local p=GetTransform(carrier);return {z=p.posit_z,valid=IsValid(carrier)}'
        Add-CRFlowCheck "c$carrierPeer can move its cinematic fixture" ($carrierMoved.valid -and $carrierMoved.z -lt 100880) $carrierMoved
    }
}
Invoke-CRFlowStep 'release only owned camera and tasks' {
    foreach ($carrierPeer in $carrierPeers) {
        Invoke-CRFlow $carrierPeer 'cancel("carrier-view");cancel("carrier-flight");native.CameraFinish();if carrierClip and type(carrierClip[1])=="number" and type(carrierClip[2])=="number" then exu.SetCameraClipDistances(carrierClip[1],carrierClip[2]) end;return IsValid(carrier)' | Out-Null
    }
}
