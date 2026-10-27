# Native leaf-visibility diagnostic: material bindings on a solid tree, then
# the same shot with the leaf submesh forced to the (visible) bark material.
param([int]$HostClient = 0)
$camera='local p=require("PersistentConfig");p.Settings.WeaponStatsHud=false;p._DestroyAllPdaOverlays();if exu.SetViewportOverlaysEnabled then exu.SetViewportOverlaysEnabled(false) end;CameraReady();every("leafCamera",0.05,function() local h=GetHandle(M.leafTree);if IsValid(h) then CameraObject(h,9000,3500,9000,h) end end);return true'
Invoke-CRFlowStep 'Leaf material bindings on a solid tree' {
    Wait-CRFlow $HostClient 'return M.coopMissionStarted and M.openingcindone' -TimeoutSeconds 100 | Out-Null
    Invoke-CRFlow $HostClient "every('leafHeal',0.5,function() heal(me()) end);return true" | Out-Null
    $d=Invoke-CRFlow $HostClient 'local h;for _,p in ipairs(require("CRJungle17Sites").trees) do if p.preplaced==1 then M.leafTree=p.label;h=GetHandle(p.label);break end end;local r={odf=GetOdf(h),subs=exu.GetNumSubEntities and exu.GetNumSubEntities(h),entity=exu.GetMaterialName and exu.GetMaterialName(h),leavesExists=exu.MaterialExists("CR17/Leaves"),cutoutExists=exu.MaterialExists("CR17/Cutout"),barkExists=exu.MaterialExists("CR17/Bark"),sub={}};for i=0,(r.subs or 0)-1 do r.sub[#r.sub+1]=tostring(exu.GetSubEntityMaterial(h,i)) end;return r'
    Add-CRFlowCheck 'leaf material diagnostic' $true $d
    Invoke-CRFlow $HostClient $camera | Out-Null
    Start-Sleep -Seconds 4
}
# Bisect: bark (stock BZBase, known visible), untextured cutout (nothing to
# clip), then the CR17 water kind (no clip, different fragment program).
function Set-LeafMaterial([string]$Material) {
    $d=Invoke-CRFlow $HostClient ('local h=GetHandle(M.leafTree);exu.SetSubEntityMaterial(h,1,"{0}");return {{now=exu.GetSubEntityMaterial(h,1)}}' -f $Material)
    Add-CRFlowCheck "leaf submesh now $Material" ($d.now -eq $Material) $d
    Start-Sleep -Seconds 4
}
Invoke-CRFlowStep 'Leaf submesh forced to CR17/Bark' { Set-LeafMaterial 'CR17/Bark' }
Invoke-CRFlowStep 'Leaf submesh forced to CR17/Cutout' { Set-LeafMaterial 'CR17/Cutout' }
Invoke-CRFlowStep 'Leaf submesh forced to CR17/River' { Set-LeafMaterial 'CR17/River' }
