# Native local-server test. Full shim chain and fresh EXU must be staged.
param([int]$HostClient=0,[int]$GuestClient=1)
$script:CRFlowSkipParity=$true
. (Join-Path $PSScriptRoot 'Test-CoopDiagnosticsLive.ps1') -HostClient $HostClient -GuestClient $GuestClient
Invoke-CRFlowStep 'native UDP rates and relay evidence advance on every real client' {
 foreach($c in Get-CRFlowClientIndices) {
  Wait-CRFlow $c 'local s=exu.GetNetworkTrafficStats();return s and s.windowMs==2000 and s.txBytesPerSecond>0 and s.rxBytesPerSecond>0 and s.txPacketsPerSecond>0 and s.rxPacketsPerSecond>0 and s.route=="relay" and s.receiveAgeMs<3000' -TimeoutSeconds 20 | Out-Null
  Invoke-CRFlow $c 'transportBefore=exu.GetNetworkTrafficStats();assert(transportBefore.txBytes>transportBefore.txPackets*18 and transportBefore.rxBytes>transportBefore.rxPackets*18);return transportBefore'
 }
 Start-Sleep -Seconds 3
 foreach($c in Get-CRFlowClientIndices) {
  Invoke-CRFlow $c 'local s=exu.GetNetworkTrafficStats();assert(s.txBytes>transportBefore.txBytes and s.rxBytes>transportBefore.rxBytes and s.sampledAtMs>transportBefore.sampledAtMs);local text=pc.P.BuildWeaponStatsText(me(),0);assert(text:find("UDP B/s Tx",1,true)and text:find("UDP pkt/s Tx",1,true)and text:find("Route relay",1,true));assert(not exu.GetShowScoreboard());return {native=s,text=text}'
  Send-CRFlowKey $c 0x10 -Focused -HoldMs 700
 }
}
