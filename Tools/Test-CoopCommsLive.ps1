# Dot-source through OpenShim's Run-BZRCoopMission.ps1 -Mission misn03 -Scenario
# <this file>. Uses two disposable clients, the local server and CRFlowProbe.
# -ContentOverride must contain the changed Lua modules and freshly built EXU.
param([int]$HostClient = 0, [int]$GuestClient = 1)
$H, $G = $HostClient, $GuestClient
# This scenario deliberately targets a ping only on the host; ordinary mission
# presentation parity does not apply to the explicitly local target selection.
$script:CRFlowSkipParity = $true
function Assert-Live($Value, [string]$Message) { if (-not (Test-CRFlowTruthy $Value)) { throw $Message } }
Invoke-CRFlowStep 'co-op communications initialized on both real clients' {
    Wait-CRFlowEvent $H attach -TimeoutSeconds 120 | Out-Null
    Wait-CRFlowEvent $G attach -TimeoutSeconds 120 | Out-Null
    foreach ($client in @($H, $G)) {
        Wait-CRFlow $client 'return CRCoop.IsSessionReady() and CRCoop.GetComms() and CRCoop.GetComms().IsActive()' -TimeoutSeconds 90 | Out-Null
        Invoke-CRFlow $client 'commsTest = require("CRCoop").GetComms(); pdaTest = require("PersistentConfig"); return { role = role(), hit = type(exu.GetReticleHit), page = pdaTest.CoopPda.PageNumber(9) }'
    }
}
Invoke-CRFlowStep 'terrain ping crosses the native Send / Receive path' {
    $session = Get-CRFlowSession
    foreach ($client in @($H, $G)) {
        $window = Get-BZRClientWindow $session.clients[$client].pid
        [BZRWin.Native]::SetWindowPos($window, [IntPtr]::Zero, 40, 40, 1296, 759, 0x14) | Out-Null
    }
    Assert-Live (Invoke-CRFlow $H 'return commsTest.SendPing("terrain", nil, GetPosition(me()))') 'Host terrain ping failed'
    Wait-CRFlow $G 'for _, p in pairs(commsTest.GetPings()) do if p.kind == "terrain" then return p end end' -TimeoutSeconds 8
}
Invoke-CRFlowStep 'guest object ping and explicit local target selection' {
    Start-Sleep -Seconds 2
    Assert-Live (Invoke-CRFlow $G 'return commsTest.SendPing("object", me())') 'Guest object ping failed'
    Wait-CRFlow $H 'for id, p in pairs(commsTest.GetPings()) do if p.kind == "object" then coopPingId = id; return IsValid(p.handle) end end' -TimeoutSeconds 8 | Out-Null
    Assert-Live (Invoke-CRFlow $H 'return commsTest.TargetPing(coopPingId)') 'Explicit object target failed'
    Invoke-CRFlow $H 'return { ping = commsTest.GetPings()[coopPingId].kind, targetValid = IsValid(GetUserTarget()) }'
}
Invoke-CRFlowStep 'PDA co-op page and keyboard action' {
    foreach ($client in @($H, $G)) {
        Assert-Live (Invoke-CRFlow $client 'pdaTest._SettingsActions.SetWeaponStatsHudEnabled(false); pdaTest._SettingsActions.SetWeaponStatsHudEnabled(true); local text = pdaTest.P.BuildWeaponStatsText(me(), 0); return text:find("CO%-OP") and text:find("J Action") and true') 'PDA did not open the co-op page'
    }
    Invoke-CRFlow $H 'return { text = pdaTest.P.BuildWeaponStatsText(me(), 0), camera = exu.GetCameraView(), hit = exu.GetReticleHit() }'
    Start-Sleep -Seconds 2
}
Invoke-CRFlowStep 'quick ping key and native terrain-hit snapshot' {
    Invoke-CRFlow $H 'pdaTest._SettingsActions.SetWeaponStatsHudEnabled(false); return true' | Out-Null
    Start-Sleep -Seconds 2
    Assert-Live (Invoke-CRFlow $H 'local kind, h, pos = exu.GetReticleHit(); assert(kind == "terrain" and pos); GameKey("J"); return true') 'Reticle terrain snapshot unavailable'
    Wait-CRFlow $G 'local p = commsTest.GetPings()[1]; return p and p.seq >= 2' -TimeoutSeconds 8
}
Invoke-CRFlowStep 'reticle no-hit never reuses old terrain coordinates' {
    Invoke-CRFlow $H 'local kind, h, pos = exu.GetReticleHit(); return { kind = kind, hValid = h and IsValid(h), pos = pos, legacy = exu.GetReticlePos() }'
}
Invoke-CRFlowStep 'ping markers expire on both clients' {
    Start-Sleep -Seconds 11
    foreach ($client in @($H, $G)) {
        Assert-Live (Invoke-CRFlow $client 'return next(commsTest.GetPings()) == nil') 'Ping did not expire'
    }
    $true
}
Invoke-CRFlowStep 'guest pilot rescue request and host acknowledgements' {
    # Exercise the stock player transition on the guest's own craft.
    Assert-Live (Invoke-CRFlow $G 'HopOut(GetPlayerHandle()); return true') 'Guest could not hop out'
    Wait-CRFlow $G 'return IsPerson(GetPlayerHandle())' -TimeoutSeconds 10 | Out-Null
    Wait-CRFlow $H 'for _, p in pairs(CRCoop.GetPlayers()) do if p.team == 2 then return p.handle and IsPerson(p.handle) end end' -TimeoutSeconds 10 | Out-Null
    Assert-Live (Invoke-CRFlow $G 'return commsTest.RequestRescue()') 'Pilot request failed'
    Wait-CRFlow $H 'for id, r in pairs(commsTest.GetRequests()) do coopRequestId = id; return r end' -TimeoutSeconds 8 | Out-Null
    Assert-Live (Invoke-CRFlow $H 'return commsTest.Respond(coopRequestId, 1)') 'Host Coming reply failed'
    Wait-CRFlow $G 'local r = commsTest.GetRequests()[CRCoop.GetLocalPlayerId()]; return r and r.status == "Help on the way"' -TimeoutSeconds 8 | Out-Null
    Assert-Live (Invoke-CRFlow $H 'return commsTest.Respond(coopRequestId, 2)') 'Host no-craft reply failed'
    Wait-CRFlow $G 'local r = commsTest.GetRequests()[CRCoop.GetLocalPlayerId()]; return r and r.status == "No craft available"' -TimeoutSeconds 8 | Out-Null
    Assert-Live (Invoke-CRFlow $G 'return commsTest.CancelRescue()') 'Guest cancellation failed'
    Wait-CRFlow $H 'return next(commsTest.GetRequests()) == nil' -TimeoutSeconds 8
}
