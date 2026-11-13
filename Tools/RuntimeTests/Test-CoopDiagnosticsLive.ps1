# Real clients/native local server on misn03cr; no simulated transport metrics.
# The scoped outbound Lua filter below is explicit application-message loss;
# it does not block engine packets or alter native ping/loss measurements.
param([int]$HostClient=0,[int]$GuestClient=1)
$script:CRFlowSkipParity=$true
Invoke-CRFlowStep 'fresh peer heartbeats and native samples agree on every client' {
 foreach($c in Get-CRFlowClientIndices) {
  Invoke-CRFlow $c 'pc=require("PersistentConfig");every("diag-heal",0.25,function()if IsValid(me())then SetCurHealth(me(),GetMaxHealth(me()))end;if IsHosting()then for h in AllObjects()do if IsValid(h)and IsLocal(h)and GetTeamNum(h)==1 then SetCurHealth(h,GetMaxHealth(h))end end end end);return true' | Out-Null
  Wait-CRFlow $c @'
local s=CRCoop.GetNetworkDiagnostics()
if not s.ready then return false end
for id,p in pairs(s.players)do
 local n=exu.GetPlayerNetworkStats(id)
 if not n or n.id~=id or n.team~=p.team then return false end
 if not p.localPlayer and (p.status~="Synced" or not p.heartbeatAge or p.heartbeatAge>=3 or not n.pingSamples or n.pingSamples<1)then return false end
end
return true
'@ -TimeoutSeconds 25 | Out-Null
 }
}
Invoke-CRFlowStep 'physical PDA navigation opens Coop Diagnostics as page two' {
 foreach($c in Get-CRFlowClientIndices) {
  Invoke-CRFlow $c 'pc._SettingsActions.SetWeaponStatsHudEnabled(false);return true' | Out-Null
  Send-CRFlowKey $c 0x58 -Focused -HoldMs 200
  Wait-CRFlow $c 'return pc.Settings.WeaponStatsHud==true and pc.P.BuildWeaponStatsText(me(),0):find("==COOP==",1,true)~=nil' -TimeoutSeconds 5 | Out-Null
  Send-CRFlowKey $c 0xDD -Focused -HoldMs 200
  Wait-CRFlow $c 'local s=pc.P.BuildWeaponStatsText(me(),0);return s:find("Coop Diagnostics",1,true)~=nil and s:find("2/10",1,true)~=nil and s:find("loss",1,true)~=nil' -TimeoutSeconds 5 | Out-Null
  Send-CRFlowKey $c 0x28 -Focused -HoldMs 200
  Invoke-CRFlow $c 'local s=pc.P.BuildWeaponStatsText(me(),0);assert(s:find("Coop Diagnostics",1,true) and s:find("Control Tx/Rx",1,true));return CRCoop.GetNetworkDiagnostics()'
 }
}
Invoke-CRFlowStep 'missing application traffic stops claiming synced despite native ping samples' {
 Invoke-CRFlow $HostClient 'diagRealSend=_G.Send;diagDropped=0;_G.Send=function(to,kind,...)if kind=="H"or kind=="P"or kind=="J"then diagDropped=diagDropped+1;return end;return diagRealSend(to,kind,...)end;return true' | Out-Null
 try {
  Wait-CRFlow $HostClient 'return diagDropped>0' -TimeoutSeconds 3 | Out-Null
  Wait-CRFlow $GuestClient 'for _,p in pairs(CRCoop.GetNetworkDiagnostics().players)do if p.host and not p.localPlayer then return p.status=="No recent traffic"end end;return false' -TimeoutSeconds 8 | Out-Null
  Wait-CRFlow $GuestClient 'for _,p in pairs(CRCoop.GetNetworkDiagnostics().players)do if p.host and not p.localPlayer then local n=exu.GetPlayerNetworkStats(p.id);return p.status=="Traffic stalled"and n and n.pingSamples>0 end end;return false' -TimeoutSeconds 15 | Out-Null
  # Background D3D clients can keep their last presented frame. A harmless
  # modifier press gives the receiver foreground time for a fresh capture.
  Send-CRFlowKey $GuestClient 0x10 -Focused -HoldMs 600
  Invoke-CRFlow $GuestClient 'local s=pc.P.BuildWeaponStatsText(me(),0);assert(s:find("Traffic stalled",1,true));return CRCoop.GetNetworkDiagnostics()'
 } finally {
  Invoke-CRFlow $HostClient 'if diagRealSend then _G.Send=diagRealSend;diagRealSend=nil end;return true' | Out-Null
 }
}
Invoke-CRFlowStep 'fresh traffic recovers diagnostics without reopening the PDA' {
 foreach($c in Get-CRFlowClientIndices) {
  Wait-CRFlow $c 'for _,p in pairs(CRCoop.GetNetworkDiagnostics().players)do if not p.localPlayer and p.status~="Synced"then return false end end;return pc.P.BuildWeaponStatsText(me(),0):find("Coop Diagnostics",1,true)~=nil' -TimeoutSeconds 8 | Out-Null
  Invoke-CRFlow $c 'assert(not exu.GetShowScoreboard());return true' | Out-Null
  Send-CRFlowKey $c 0x10 -Focused -HoldMs 600
 }
}
