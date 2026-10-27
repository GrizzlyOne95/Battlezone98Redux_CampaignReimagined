# Real GOG clients, native local server. Attach after -Scenario play on misn03.
param([int]$HostClient=0,[int]$GuestClient=1)
$script:CRFlowSkipParity=$true
Invoke-CRFlowStep 'co-op starts with stock scoreboard and kill notices hidden' {
 foreach($c in Get-CRFlowClientIndices) {
  Wait-CRFlow $c 'return CRCoop.IsSessionReady() and exu.GetShowScoreboard()==false and exu.GetShowKillMessages()==false' -TimeoutSeconds 15 | Out-Null
  Invoke-CRFlow $c 'every("hud-keepalive",0.25,function() if IsValid(me()) then SetCurHealth(me(),GetMaxHealth(me())) end; if IsHosting() then for h in AllObjects() do if IsValid(h) and IsLocal(h) and GetTeamNum(h)==1 then SetCurHealth(h,GetMaxHealth(h)) end end end end);return true' | Out-Null
 }
}
Invoke-CRFlowStep 'read-only stats describe each real peer while the scoreboard stays hidden' {
 foreach($c in Get-CRFlowClientIndices) {
  Invoke-CRFlow $c @'
local rows={}
for id,p in pairs(CRCoop.GetPlayers()) do
 local s=exu.GetPlayerNetworkStats(id)
 assert(s and s.id==id and s.team==p.team and s.name==p.name,"native row identity mismatch")
 assert(type(s.kills)=="number" and type(s.deaths)=="number" and type(s.lives)=="number","native score slots absent")
 if id==CRCoop.GetLocalPlayerId() then assert(s.pingMs==nil and s.lossPercent==nil)
 else assert(type(s.pingMs)=="number" and s.pingMs>=0 and s.lossPercent>=0 and s.lossPercent<=100) end
 rows[#rows+1]=s
end
assert(exu.GetPlayerNetworkStats(65534)==nil,"missing peer returned a row")
assert(exu.GetShowScoreboard()==false,"stats query revealed scoreboard")
return rows
'@
 }
}
Invoke-CRFlowStep 'physical M reveals the stock scoreboard and remains user controlled' {
 foreach($c in Get-CRFlowClientIndices) {
  Send-CRFlowKey $c 0x4D -Focused -HoldMs 200
  Wait-CRFlow $c 'return exu.GetShowScoreboard()==true' -TimeoutSeconds 5 | Out-Null
  Start-Sleep -Seconds 2
  Wait-CRFlow $c 'return exu.GetShowScoreboard()==true' -TimeoutSeconds 5 | Out-Null
  Send-CRFlowKey $c 0x4D -Focused -HoldMs 200
  Wait-CRFlow $c 'return exu.GetShowScoreboard()==false' -TimeoutSeconds 5 | Out-Null
 }
}
Invoke-CRFlowStep 'presentation switch is reversible without changing native stats' {
 foreach($c in Get-CRFlowClientIndices) {
  Invoke-CRFlow $c 'local id=CRCoop.GetLocalPlayerId();local a=exu.GetPlayerNetworkStats(id);assert(exu.SetShowKillMessages(true));assert(exu.GetShowKillMessages());assert(exu.SetShowKillMessages(false));assert(not exu.GetShowKillMessages());local b=exu.GetPlayerNetworkStats(id);assert(a.kills==b.kills and a.deaths==b.deaths and a.lives==b.lives);return true' | Out-Null
 }
}

Invoke-CRFlowStep 'native death statistics still advance while notices and scoreboard are hidden' {
 Invoke-CRFlow $GuestClient 'if not IsPerson(me()) then HopOut(me()) end;return true' | Out-Null
 Wait-CRFlow $GuestClient 'return IsPerson(me())' -TimeoutSeconds 10 | Out-Null
 Invoke-CRFlow $GuestClient 'hudStatsId=CRCoop.GetLocalPlayerId();hudBefore=exu.GetPlayerNetworkStats(hudStatsId);hudOldPilot=me();cancel("hud-keepalive");Damage(me(),1000000);return true' | Out-Null
 Wait-CRFlow $GuestClient 'local s=exu.GetPlayerNetworkStats(hudStatsId);return s and s.deaths>hudBefore.deaths and IsValid(me()) and me()~=hudOldPilot' -TimeoutSeconds 20 | Out-Null
 $guestId=Invoke-CRFlow $GuestClient 'return hudStatsId'
 Wait-CRFlow $HostClient "local s=exu.GetPlayerNetworkStats($guestId);return s and s.deaths>0" -TimeoutSeconds 10 | Out-Null
 foreach($c in Get-CRFlowClientIndices) {
  Invoke-CRFlow $c 'assert(not exu.GetShowKillMessages() and not exu.GetShowScoreboard());local rows={};for id in pairs(CRCoop.GetPlayers())do rows[#rows+1]=exu.GetPlayerNetworkStats(id)end;return rows'
 }
}
