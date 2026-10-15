# Run against the assistance scenario's retained native local-server session.
# Aim the host reticle at open ground before attaching; no synthetic hit is used.
param([int]$HostClient=0,[int]$GuestClient=1)
$H,$G=$HostClient,$GuestClient
$script:CRFlowSkipParity=$true
Invoke-CRFlowStep 'physical X opens and closes the current PDA' {
 foreach($c in @($H,$G)) {
  Invoke-CRFlow $c 'ct=CRCoop.GetComms();pc=require("PersistentConfig");pc._SettingsActions.SetWeaponStatsHudEnabled(false);return true' | Out-Null
  Send-CRFlowKey $c 0x58 -Focused -HoldMs 200
  Wait-CRFlow $c 'return pc.Settings.WeaponStatsHud==true' -TimeoutSeconds 5 | Out-Null
  Send-CRFlowKey $c 0x58 -Focused -HoldMs 200
  Wait-CRFlow $c 'return pc.Settings.WeaponStatsHud==false' -TimeoutSeconds 5 | Out-Null
 }
}
Invoke-CRFlowStep 'physical J uses the native terrain reticle and sends a ping' {
 Wait-CRFlow $H 'local kind,h,p=exu.GetReticleHit();return kind=="terrain" and p~=nil' -TimeoutSeconds 5 | Out-Null
 Send-CRFlowKey $H 0x4A -Focused -HoldMs 200
 Wait-CRFlow $G 'for _,p in pairs(ct.GetPings()) do if p.kind=="terrain" then return true end end' -TimeoutSeconds 5 | Out-Null
}
Invoke-CRFlowStep 'physical V calls for help and Backspace cancels the selected row' {
 Invoke-CRFlow $G 'ct.CancelRescue();return true' | Out-Null
 Start-Sleep -Seconds 21
 Send-CRFlowKey $G 0x56 -Focused -HoldMs 200
 Wait-CRFlow $H 'for _,r in pairs(ct.GetRequests()) do return r.kind==1 end' -TimeoutSeconds 5 | Out-Null
 Send-CRFlowKey $G 0x58 -Focused -HoldMs 200
 Wait-CRFlow $G 'return pc.Settings.WeaponStatsHud==true' -TimeoutSeconds 5 | Out-Null
 Invoke-CRFlow $G 'pc.CoopPda.selected="help";return true' | Out-Null
 Send-CRFlowKey $G 0x08 -Focused -HoldMs 200
 Wait-CRFlow $H 'return next(ct.GetRequests())==nil' -TimeoutSeconds 5 | Out-Null
}
Invoke-CRFlowStep 'stock chat suppresses physical co-op action keys' {
 Invoke-CRFlow $G 'pc._SettingsActions.SetWeaponStatsHudEnabled(false);return true' | Out-Null
 Start-Sleep -Seconds 11
 Send-CRFlowKey $G 0x0D -Focused -HoldMs 200
 Wait-CRFlow $G 'return exu.IsTextEntryActive()==true' -TimeoutSeconds 5 | Out-Null
 foreach($key in 0x58,0x4A,0x56,0x5A,0x08) {Send-CRFlowKey $G $key -Focused -HoldMs 200}
 Wait-CRFlow $G 'return exu.IsTextEntryActive() and not pc.Settings.WeaponStatsHud and next(ct.GetRequests())==nil and next(ct.GetPings())==nil' -TimeoutSeconds 5 | Out-Null
 Send-CRFlowKey $G 0x1B -Focused -HoldMs 200
 Wait-CRFlow $G 'return not exu.IsTextEntryActive() and not pc.Settings.WeaponStatsHud' -TimeoutSeconds 5 | Out-Null
}
