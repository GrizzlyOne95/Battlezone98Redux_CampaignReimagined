# Run via OpenShim Run-BZRCoopMission.ps1 -Mission misn03 -Scenario <this file>.
# Calls the real services and native transport. Setup movement is a test assist;
# physical keys, reticle aiming and visual layout need separate acceptance.
param([int]$HostClient = 0, [int]$GuestClient = 1)
$H, $G = $HostClient, $GuestClient
$script:CRFlowSkipParity = $true # Local ping markers deliberately differ.
function Assert-Assist($Value, [string]$Message) {
    if (-not (Test-CRFlowTruthy $Value)) { throw $Message }
}
Invoke-CRFlowStep 'current assistance services initialize on every peer' {
    foreach ($client in Get-CRFlowClientIndices) {
        Wait-CRFlowEvent $client attach -TimeoutSeconds 120 | Out-Null
        Wait-CRFlow $client 'return CRCoop.IsSessionReady() and CRCoop.GetComms().IsActive()' -TimeoutSeconds 90 | Out-Null
        Assert-Assist (Invoke-CRFlow $client @'
ct=CRCoop.GetComms(); pc=require("PersistentConfig")
-- Keep the story objective alive during interaction-only acceptance.
if IsHosting() then every("assist-objectives",0.25,function()
 for h in AllObjects() do if IsValid(h) and IsLocal(h) and GetTeamNum(h)==1 then SetCurHealth(h,GetMaxHealth(h)) end end
end) end
if ct.GetRequests()[CRCoop.GetLocalPlayerId()] then ct.CancelRescue() end
every("assist-heal",0.25,function() if IsValid(me()) then heal(me()) end end)
assert(type(exu.AdoptObject)=="function" and type(exu.IsObjectiveOn)=="function")
assert(type(exu.GetReticleHit)=="function" and type(exu.IsTextEntryActive)=="function")
pc._SettingsActions.SetWeaponStatsHudEnabled(true)
local text=pc.P.BuildWeaponStatsText(me(),0)
assert(text:find("==COOP==",1,true) and text:find("Bksp do",1,true))
assert(not ct.MarkersOn())
pc._SettingsActions.SetWeaponStatsHudEnabled(false)
return true
'@) 'Current PDA/dependencies unavailable'
    }
}
Invoke-CRFlowStep 'terrain ping has a local stock objective marker on every peer' {
    Assert-Assist (Invoke-CRFlow $H 'return ct.SendPing("terrain",nil,GetPosition(me()))==true') 'Terrain ping failed'
    foreach ($client in Get-CRFlowClientIndices) {
        Wait-CRFlow $client @'
for h in AllObjects() do
 if IsValid(h) and GetOdf(h):lower():gsub("%.odf$","")=="crping" then
  terrainMark=h
  return exu.IsObjectiveOn(h) and GetObjectiveName(h):find(": TERRAIN PING",1,true)~=nil
 end
end
'@ -TimeoutSeconds 8 | Out-Null
    }
}
Invoke-CRFlowStep 'ping expiry preserves an existing objective' {
    # Redux clears/renames the local player marker independently. A normal
    # owned NPC is the stable fixture for preserving a mission objective.
    Start-Sleep -Seconds 2
    Assert-Assist (Invoke-CRFlow $H 'existingMark=BuildObject("avturr",1,GetPosition(me())); SetObjectiveOn(existingMark); priorName=GetObjectiveName(existingMark); return ct.SendPing("object",existingMark)==true') 'Object ping failed'
    Wait-CRFlow $H 'return GetObjectiveName(existingMark):find(": TARGET PING",1,true)~=nil' -TimeoutSeconds 8 | Out-Null
    Start-Sleep -Seconds 12
    foreach ($client in Get-CRFlowClientIndices) {
        Assert-Assist (Invoke-CRFlow $client 'return next(ct.GetPings())==nil and not IsValid(terrainMark)') 'Ping/terrain marker did not expire'
    }
    Assert-Assist (Invoke-CRFlow $H 'return exu.IsObjectiveOn(existingMark) and GetObjectiveName(existingMark)==priorName') 'Existing objective was damaged'
}
Invoke-CRFlowStep 'guest help call and host response use native Send/Receive' {
    Assert-Assist (Invoke-CRFlow $G 'return ct.CallForHelp()==true') 'Help call failed'
    Wait-CRFlow $H 'for id,r in pairs(ct.GetRequests()) do requestId=id; return r.kind==1 or r.kind==2 end' -TimeoutSeconds 8 | Out-Null
    Assert-Assist (Invoke-CRFlow $H 'return ct.Respond(requestId,1)==true') 'Host response failed'
    Wait-CRFlow $G 'local r=ct.GetRequests()[CRCoop.GetLocalPlayerId()]; return r and r.status=="Help on the way"' -TimeoutSeconds 8 | Out-Null
    Assert-Assist (Invoke-CRFlow $G 'return ct.CancelRescue()==true') 'Cancellation failed'
    Wait-CRFlow $H 'return next(ct.GetRequests())==nil' -TimeoutSeconds 8 | Out-Null
}
Invoke-CRFlowStep 'real unit hand-off preserves identity and accepts guest orders' {
    Wait-CRFlow $H 'for id,p in pairs(CRCoop.GetPlayers()) do if p.team==2 then guestId=id; return true end end' -TimeoutSeconds 8 | Out-Null
    Assert-Assist (Invoke-CRFlow $H 'giveUnit=BuildObject("avtank",1,GetPosition(me())); Stop(giveUnit,0); return ct.SendPing("object",giveUnit)==true') 'Transfer fixture failed'
    Wait-CRFlow $G 'for _,p in pairs(ct.GetPings()) do if p.kind=="object" then receivedUnit=p.handle; return IsValid(receivedUnit) end end' -TimeoutSeconds 8 | Out-Null
    foreach ($client in Get-CRFlowClientIndices) {
        if ($client -eq $H -or $client -eq $G) { continue }
        Wait-CRFlow $client 'for _,p in pairs(ct.GetPings()) do if p.kind=="object" then witnessUnit=p.handle; return IsValid(witnessUnit) and GetTeamNum(witnessUnit)==1 end end' -TimeoutSeconds 8 | Out-Null
    }
    Assert-Assist (Invoke-CRFlow $H 'return ct.Give(giveUnit,guestId)==true') 'Give request failed'
    Wait-CRFlow $G 'return IsValid(receivedUnit) and IsLocal(receivedUnit) and GetTeamNum(receivedUnit)==2 and CanCommand(receivedUnit)' -TimeoutSeconds 8 | Out-Null
    Wait-CRFlow $H 'return IsValid(giveUnit) and not IsLocal(giveUnit) and GetTeamNum(giveUnit)==2' -TimeoutSeconds 8 | Out-Null
    foreach ($client in Get-CRFlowClientIndices) {
        if ($client -eq $H -or $client -eq $G) { continue }
        Wait-CRFlow $client 'return IsValid(witnessUnit) and GetTeamNum(witnessUnit)==2 and not IsLocal(witnessUnit)' -TimeoutSeconds 8 | Out-Null
    }
    Invoke-CRFlow $G 'giveStart=GetPosition(receivedUnit); Goto(receivedUnit,SetVector(giveStart.x+60,giveStart.y,giveStart.z),0); return true' | Out-Null
    Wait-CRFlow $G 'return GetDistance(receivedUnit,giveStart)>15' -TimeoutSeconds 15 | Out-Null
}
Invoke-CRFlowStep 'recall executes on each guest owner' {
    Assert-Assist (Invoke-CRFlow $H 'return ct.Recall()==true') 'Recall failed'
    foreach ($client in Get-CRFlowClientIndices) {
        if ($client -eq $H) { continue }
        Wait-CRFlow $client 'for _,p in pairs(CRCoop.GetPlayers()) do if p.team==1 then return GetDistance(me(),p.handle)<40 end end' -TimeoutSeconds 8 | Out-Null
    }
}

Invoke-CRFlowStep 'native rescue dispatch targets the remote guest pilot' {
    Invoke-CRFlow $G 'if not IsPerson(me()) then HopOut(me()) end; return true' | Out-Null
    Wait-CRFlow $G 'return IsPerson(me())' -TimeoutSeconds 10 | Out-Null
    Wait-CRFlow $H 'for id,p in pairs(CRCoop.GetPlayers()) do if p.team==2 and IsValid(p.handle) and IsPerson(p.handle) then guestId=id; return true end end' -TimeoutSeconds 10 | Out-Null
    Wait-CRFlow $G 'return ct.RequestRescue()==true' -TimeoutSeconds 25 | Out-Null
    Assert-Assist (Invoke-CRFlow $H @'
local p=GetPosition(CRCoop.GetPlayers()[guestId].handle)
ride=BuildObject("avfigh",1,SetVector(p.x+60,p.y+5,p.z))
return ct.Dispatch(ride,guestId)==true
'@) 'Native dispatch failed'
    Wait-CRFlow $H 'return IsValid(ride) and GetCurrentCommand(ride)==AiCommand["RESCUE"] and IsAliveAndPilot(ride)' -TimeoutSeconds 8 | Out-Null
    Wait-CRFlow $H 'local p=CRCoop.GetPlayers()[guestId]; return IsValid(ride) and GetDistance(ride,p.handle)<35 and GetCurrentCommand(ride)~=AiCommand["RESCUE"] and not IsAliveAndPilot(ride)' -TimeoutSeconds 40 | Out-Null
}
# Rescue acceptance ends when the craft arrives and its AI pilot hops out.
# Player boarding is the stock walk-into-craft transition, not the H key.
