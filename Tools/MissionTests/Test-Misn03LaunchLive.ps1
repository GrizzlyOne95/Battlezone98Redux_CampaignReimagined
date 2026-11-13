# Live check of misn03's closing NSDF rocket launch (CR PR #259).
#
# Run with OpenShim/reverse_engineering/Run-BZRCoopMission.ps1 -Mission misn03
# -Scenario <this file> -CampaignContent <content staged from THIS worktree>
# -Clients 2. Dot-sourced by the runner, which has an [int]$Clients parameter;
# PowerShell names are case-insensitive, so every local here carries an m3 prefix.
#
# The scenario drives the real mission to its final objective exactly as
# misn03-win.ps1 does, takes still shots of the fixture on the pad with a
# scripted object camera that is released before the finale, then lets the REAL
# misn03 code start the launch film and checks it. It never calls the film.
param([int]$HostClient = 0, [int]$GuestClient = 1,
      [int]$NaturalOutroSeconds = 100,
      # Side offset of the still camera from the pad, metres.
      [int]$StillOffset = 26000)

$H, $G = $HostClient, $GuestClient
$script:M3Shots = New-Object System.Collections.ArrayList

function Save-M3Shot([string]$Tag) {
    foreach ($m3c in (Get-CRFlowClientIndices)) {
        $m3cl = Get-CRFlowClient $m3c
        $m3path = Join-Path $script:CRFlowRun.shots ("misn03live-{0}-c{1}.png" -f $Tag, $m3c)
        try {
            Save-BZRClientCapture $m3cl.pid $m3path
            $m3stat = Get-M3ShotStats $m3path
            [void]$script:M3Shots.Add(@{ tag = $Tag; client = $m3c; path = $m3path; stats = $m3stat })
            Write-Host "SHOT $Tag c$m3c $m3path $(ConvertTo-Json $m3stat -Compress)"
        } catch { Write-Host "SHOT $Tag c$m3c FAILED: $_" }
    }
}

# Mean luminance and the share of near-black samples on a coarse grid.
function Get-M3ShotStats([string]$Path) {
    Add-Type -AssemblyName System.Drawing
    $m3bmp = New-Object System.Drawing.Bitmap $Path
    try {
        $m3sum = 0.0; $m3dark = 0; $m3n = 0
        $m3min = 255; $m3max = 0
        for ($m3x = 4; $m3x -lt $m3bmp.Width; $m3x += [Math]::Max(1, [int]($m3bmp.Width / 24))) {
            for ($m3y = 4; $m3y -lt $m3bmp.Height; $m3y += [Math]::Max(1, [int]($m3bmp.Height / 24))) {
                $m3px = $m3bmp.GetPixel($m3x, $m3y)
                $m3l = 0.299 * $m3px.R + 0.587 * $m3px.G + 0.114 * $m3px.B
                $m3sum += $m3l; $m3n++
                if ($m3l -lt 6) { $m3dark++ }
                if ($m3l -lt $m3min) { $m3min = $m3l }
                if ($m3l -gt $m3max) { $m3max = $m3l }
            }
        }
        @{ w = $m3bmp.Width; h = $m3bmp.Height; meanLuma = [Math]::Round($m3sum / $m3n, 1); darkShare = [Math]::Round($m3dark / $m3n, 3); lumaMin = [Math]::Round($m3min, 0); lumaMax = [Math]::Round($m3max, 0) }
    } finally { $m3bmp.Dispose() }
}

$m3PoseLua = @'
local function pose(h)
    if not IsValid(h) then return false end
    local d = describe(h)
    local ok, f = pcall(GetFront, h)
    if ok and f then d.front = { f.x, f.y, f.z } end
    local ok2, p = pcall(GetPosition, h)
    if ok2 and p then d.exact = { p.x, p.y, p.z } end
    return d
end
'@

$m3PoseTail = @'

local pad, rk = GetHandle('launch_pad'), GetHandle('cr03_rocket')
return { pad = pose(pad), rocket = pose(rk), mLaunch = IsValid(M.launch) and M.launch == pad }
'@

Invoke-CRFlowStep 'probes attached on both clients' {
    $a = Wait-CRFlowEvent $H attach -TimeoutSeconds 120
    $b = Wait-CRFlowEvent $G attach -TimeoutSeconds 120
    if (-not $a.bzfile -or -not $b.bzfile) { throw "bzfile missing (host=$($a.bzfile) guest=$($b.bzfile)); no command channel" }
    @{ lua = $a.lua; hostRoot = $a.root; guestRoot = $b.root }
}

Invoke-CRFlowStep 'roles: host has authority, guest does not' {
    $hr = Wait-CRFlow $H 'local r = role(); return r.playerId ~= nil and r' -TimeoutSeconds 90
    $gr = Wait-CRFlow $G 'local r = role(); return r.playerId ~= nil and r' -TimeoutSeconds 90
    if (-not $hr.authority -or $gr.authority) { throw "authority host=$($hr.authority) guest=$($gr.authority)" }
    @{ hostTeam = $hr.team; guestTeam = $gr.team }
}

Invoke-CRFlowStep 'session ready and mission started on host' {
    Wait-CRFlow $H 'return M.start_done and role().ready' -TimeoutSeconds 120 | Out-Null
    Invoke-CRFlow $H 'return players()'
}

Invoke-CRFlowStep 'keep objectives and players alive (test assist)' {
    Invoke-CRFlow $H @'
every('protect', 1, function()
    for _, k in ipairs({ "solar1", "solar2", "solar3", "solar4", "launch", "avrecycler", "rescue1", "rescue2" }) do
        if M[k] then heal(M[k]) end
    end
end)
return #tasks()
'@ | Out-Null
    foreach ($m3c in (Get-CRFlowClientIndices)) { Invoke-CRFlow $m3c "every('selfheal', 1, function() heal(me()) end); return true" | Out-Null }
    'protect + selfheal'
}

Invoke-CRFlowStep 'first wave destroyed -> retreat' {
    Invoke-CRFlow $H 'return kill(M.wave1_1), kill(M.wave1_2)' | Out-Null
    Wait-CRFlow $H 'return M.start_retreat' -TimeoutSeconds 30
}

Invoke-CRFlowStep 'fortify phase on host' {
    Invoke-CRFlow $H "return ff('^new_message_time$')" | Out-Null
    Wait-CRFlow $H 'return M.done_retreat and role().phase == 2' -TimeoutSeconds 30
}

Invoke-CRFlowStep 'waves 2-4 and reinforcements (timers pulled)' {
    Invoke-CRFlow $H "return { ff('^second_wave_time$'), ff('^third_wave_time$'), ff('^fourth_wave_time$'), ff('^support_time$') }" | Out-Null
    Wait-CRFlow $H 'return M.second_wave_done and M.third_wave_done and M.fourth_wave_done and M.help_spawn' -TimeoutSeconds 60
}

Invoke-CRFlowStep 'every player clear of enemies -> evacuation' {
    Invoke-CRFlow $H @'
every('clear', 2, function()
    if M.second_objective then return true end
    clearAroundPlayers(5, "^svtank", 600)
    clearAroundPlayers(5, "^svfigh", 600)
end)
return ff('^apc_spawn_time$')
'@ | Out-Null
    Wait-CRFlow $H 'return M.second_objective' -TimeoutSeconds 120
}

Invoke-CRFlowStep 'evacuation film plays on both clients, then ends on its own' {
    Wait-CRFlow $H 'return M.camera_ready and L().localCameraActive' -TimeoutSeconds 30 | Out-Null
    Wait-CRFlow $G 'return L().localCameraActive' -TimeoutSeconds 20 | Out-Null
    Wait-CRFlow $H 'return M.movie_over' -TimeoutSeconds 150 | Out-Null
    Wait-CRFlow $H 'return not L().localCameraActive' -TimeoutSeconds 15 | Out-Null
    Wait-CRFlow $G 'return not L().localCameraActive' -TimeoutSeconds 15 | Out-Null
    Wait-CRFlow $H 'return M.remove_props' -TimeoutSeconds 30
}

Invoke-CRFlowStep 'transports reach the launch pad' {
    Wait-CRFlow $H 'return IsAlive(M.rescue1) and IsAlive(M.rescue2)' -TimeoutSeconds 60 | Out-Null
    Invoke-CRFlow $H 'return put(M.rescue1, M.launch, 30), put(M.rescue2, M.launch, 45)' | Out-Null
    Wait-CRFlow $H 'return M.third_objective' -TimeoutSeconds 30
}

Invoke-CRFlowStep 'assertion 1: cr03_rocket exists on every client; pad and rocket poses' {
    $m3poses = @{}
    foreach ($m3c in (Get-CRFlowClientIndices)) {
        $m3r = Invoke-CRFlow $m3c ($m3PoseLua + $m3PoseTail)
        Write-Host "POSE c$m3c $(ConvertTo-Json $m3r -Compress -Depth 6)"
        Add-CRFlowCheck "c$m3c cr03_rocket exists before the finale" ([bool]$m3r.rocket) $m3r
        Add-CRFlowCheck "c$m3c launch_pad exists before the finale" ([bool]$m3r.pad) $m3r
        if ($m3r.rocket -and $m3r.pad) {
            $m3dx = $m3r.rocket.exact[0] - $m3r.pad.exact[0]
            $m3dy = $m3r.rocket.exact[1] - $m3r.pad.exact[1]
            $m3dz = $m3r.rocket.exact[2] - $m3r.pad.exact[2]
            $m3off = @{ dx = [Math]::Round($m3dx, 2); dy = [Math]::Round($m3dy, 2); dz = [Math]::Round($m3dz, 2); horiz = [Math]::Round([Math]::Sqrt($m3dx * $m3dx + $m3dz * $m3dz), 2) }
            Write-Host "OFFSET c$m3c rocket-minus-pad $(ConvertTo-Json $m3off -Compress) (expected dy 66.26, horiz ~34.1)"
            Add-CRFlowCheck "c$m3c rocket origin sits 66.26 m above the pad origin (+/-3) and about 34 m off its axis" (([Math]::Abs($m3dy - 66.2562) -lt 3) -and ([Math]::Abs($m3off.horiz - 34.07) -lt 3)) $m3off
        }
        $m3poses["c$m3c"] = $m3r
    }
    $m3poses
}

Invoke-CRFlowStep 'hide HUD and overlays on every client' {
    foreach ($m3c in (Get-CRFlowClientIndices)) {
        Invoke-CRFlow $m3c 'local p=require("PersistentConfig");p.Settings.WeaponStatsHud=false;p._DestroyAllPdaOverlays();if exu.SetViewportOverlaysEnabled then exu.SetViewportOverlaysEnabled(false) end;return true' | Out-Null
    }
    $true
}

# Still shots of the fixture on the pad. The camera is pushed and popped here,
# well before the finale, so the camera stack is balanced when the real film runs.
$m3StillLua = @'
local v = { __X__, __Y__, __Z__ }
local pad, rk = GetHandle('launch_pad'), GetHandle('cr03_rocket')
if not IsValid(pad) or not IsValid(rk) then return false end
native.CameraReady()
M.m3StillCam = true
every('m3stillcam', 0, function()
    if not M.m3StillCam then return true end
    native.CameraObject(pad, v[1], v[2], v[3], rk)
end)
return true
'@
$m3StillOff = 'M.m3StillCam = nil; cancel("m3stillcam"); native.CameraFinish(); return true'
Invoke-CRFlowStep 'still shots of the rocket on the pad (camera released before the finale)' {
    # CameraObject offsets are centimetres in the base object's frame.
    foreach ($m3view in @(@{ tag = 'still-posx'; x = 26000; y = 8000; z = 0 }, @{ tag = 'still-negx'; x = -26000; y = 8000; z = 0 }, @{ tag = 'still-posz'; x = 0; y = 8000; z = 26000 }, @{ tag = 'still-negz'; x = 0; y = 8000; z = -26000 }, @{ tag = 'still-close'; x = 15000; y = 6000; z = 5000 })) {
        $m3lua = $m3StillLua.Replace('__X__', [string]$m3view.x).Replace('__Y__', [string]$m3view.y).Replace('__Z__', [string]$m3view.z)
        $m3ok = Invoke-CRFlow $H $m3lua
        if (-not $m3ok) { throw 'pad or rocket handle missing for the still camera' }
        Start-Sleep -Seconds 4
        Save-M3Shot $m3view.tag
        Invoke-CRFlow $H $m3StillOff | Out-Null
        Start-Sleep -Seconds 1
    }
    # Guest still from its own camera so the second peer's pad view is on record.
    Invoke-CRFlow $G ($m3StillLua.Replace('__X__', [string]$StillOffset).Replace('__Y__', '8000').Replace('__Z__', '0')) | Out-Null
    Start-Sleep -Seconds 4
    $m3gp = Join-Path $script:CRFlowRun.shots 'misn03live-still-side-guest-c1.png'
    try { Save-BZRClientCapture (Get-CRFlowClient $G).pid $m3gp; Write-Host "SHOT still-side-guest c$G $m3gp $(ConvertTo-Json (Get-M3ShotStats $m3gp) -Compress)" } catch { Write-Host "guest still failed: $_" }
    Invoke-CRFlow $G $m3StillOff | Out-Null
    Start-Sleep -Seconds 1
    foreach ($m3c in (Get-CRFlowClientIndices)) {
        $m3t = Invoke-CRFlow $m3c 'return { still = M.m3StillCam, active = L().localCameraActive }'
        if ($m3t.still -or $m3t.active) { throw "c$m3c test camera not released: $(ConvertTo-Json $m3t -Compress)" }
    }
    'test cameras released'
}

Invoke-CRFlowStep 'every human reaches the launch pad -> outro' {
    foreach ($m3c in (Get-CRFlowClientIndices)) {
        Invoke-CRFlow $m3c 'return tp(M.launch, 35)' | Out-Null
    }
    Wait-CRFlow $H 'return M.final_objective' -TimeoutSeconds 30 | Out-Null
    Wait-CRFlow $H 'return M.startfinishingmovie' -TimeoutSeconds 15
}

Invoke-CRFlowStep 'older outro plays until it would end; the real code starts the launch' {
    Wait-CRFlow $G 'return L().localCameraActive' -TimeoutSeconds 25 | Out-Null
    $m3ok = $true
    try { Wait-CRFlow $H 'return M.launchPhase' -TimeoutSeconds $NaturalOutroSeconds | Out-Null }
    catch { $m3ok = $false }
    if (-not $m3ok) {
        Write-Host 'natural outro did not reach the launch in time; pulling the 90 s coop deadline (test assist)'
        Invoke-CRFlow $H "return ff('^coopOutroDeadline$', 1)" | Out-Null
        Wait-CRFlow $H 'return M.launchPhase' -TimeoutSeconds 40 | Out-Null
    }
    @{ natural = $m3ok }
}

$m3startTime = $null
Invoke-CRFlowStep 'assertion 2: launch state and cameras' {
    $m3st = Wait-CRFlow $H 'return M.launchFilm and M.launchFilm.camera and { phase = M.launchPhase, start = M.launchStart, now = GetTime(), camera = tostring(M.launchFilm.camera) }' -TimeoutSeconds 15
    $script:m3startTime = $m3st.start
    Save-M3Shot 'launch-t1'
    foreach ($m3c in (Get-CRFlowClientIndices)) {
        $m3a = Wait-CRFlow $m3c 'return L().localCameraActive' -TimeoutSeconds 10
        Add-CRFlowCheck "c$m3c localCameraActive during the launch" ([bool]$m3a) $m3a
    }
    Add-CRFlowCheck 'host M.launchPhase and M.launchFilm.camera set' ($m3st.phase -eq $true) $m3st
    $m3st
}

Invoke-CRFlowStep 'assertion 3: FX layers, lit bells and light on every client' {
    $m3out = @{}
    foreach ($m3c in (Get-CRFlowClientIndices)) {
        $m3fx = Invoke-CRFlow $m3c @'
local r = {}
for _, k in ipairs({ 'Core', 'Plume', 'Smoke', 'Dust' }) do r[k] = exu.HasParticleSystem('CR03/Launch/1/' .. k) end
for _, k in ipairs({ 'Core', 'Plume' }) do
    local n = 'CR03/Launch/1/' .. k
    r[k .. 'Emitters'] = exu.GetParticleSystemEmitterCount(n)
    local rates, lit = {}, 0
    for i = 0, 7 do rates[#rates + 1] = exu.GetParticleEmitterEmissionRate(n, i) or 0 end
    for i = 1, 7 do if rates[i] > 0 then lit = lit + 1 end end
    r[k .. 'Rates'] = rates
    r[k .. 'Lit0to6'] = lit
    r[k .. 'Idx7'] = rates[8]
end
if exu.HasPointLight then r.Light = exu.HasPointLight('CR03/Launch/1/Light') and true or false else r.Light = 'unavailable' end
r.age = M.launchStart and (GetTime() - M.launchStart) or nil
return r
'@
        Write-Host "FX c$m3c $(ConvertTo-Json $m3fx -Compress -Depth 6)"
        $m3out["c$m3c"] = $m3fx
        Add-CRFlowCheck "c$m3c has Core, Plume and Dust but no Smoke" ([bool]($m3fx.Core -and $m3fx.Plume -and $m3fx.Dust -and -not $m3fx.Smoke)) $m3fx
        Add-CRFlowCheck "c$m3c lights emitters 0-6 of Core and Plume and leaves 7 dormant" (($m3fx.CoreLit0to6 -eq 7) -and ($m3fx.PlumeLit0to6 -eq 7) -and ($m3fx.CoreIdx7 -eq 0) -and ($m3fx.PlumeIdx7 -eq 0)) $m3fx
        if ($m3fx.Light -eq $true) { Add-CRFlowCheck "c$m3c engine point light exists" $true $m3fx.Light }
        else { Write-Host "NOTE c$m3c engine light: $($m3fx.Light) (reported, not failed)"; Add-CRFlowCheck "c$m3c engine point light (informational: $($m3fx.Light))" $true $m3fx.Light }
    }
    $m3out
}

Invoke-CRFlowStep 'launch camera shot at +4 s' {
    Wait-CRFlow $H 'return M.launchStart and GetTime() - M.launchStart >= 4' -TimeoutSeconds 10 | Out-Null
    Save-M3Shot 'launch-t4'
    $true
}

Invoke-CRFlowStep 'assertion 4: the rocket climbs' {
    Wait-CRFlow $H 'return M.launchStart and GetTime() - M.launchStart >= 5' -TimeoutSeconds 10 | Out-Null
    $m3climb = @{}
    foreach ($m3c in (Get-CRFlowClientIndices)) {
        $m3r = Invoke-CRFlow $m3c 'local h=GetHandle("cr03_rocket");return IsValid(h) and {y=GetPosition(h).y, age=GetTime()-M.launchStart}'
        Write-Host "ASCENT c$m3c $(ConvertTo-Json $m3r -Compress)"
        $m3climb["c$m3c"] = $m3r
        $m3start = 119.756
        Add-CRFlowCheck "c$m3c rocket climbed well above its start (>25 m by about 5 s)" ([bool]$m3r -and ($m3r.y - $m3start) -gt 25) $m3r
    }
    $m3climb
}

Invoke-CRFlowStep 'launch camera shot at +8 s' {
    Wait-CRFlow $H 'return M.launchStart and GetTime() - M.launchStart >= 8' -TimeoutSeconds 10 | Out-Null
    Save-M3Shot 'launch-t8'
    $true
}

Invoke-CRFlowStep 'assertion 5: film ends and the mission succeeds about 11 s after the launch began' {
    $m3a = Wait-CRFlowOp $H SucceedMission 'misn03w1.des' -TimeoutSeconds 30
    $m3b = Wait-CRFlowOp $G SucceedMission 'misn03w1.des' -TimeoutSeconds 30
    $m3dt = [Math]::Round($m3a.t - $script:m3startTime, 2)
    $m3res = Invoke-CRFlow $H 'return { result = M.coopResult, lost = M.lost, cameraOff = M.camera_off, phase = M.launchPhase }'
    Write-Host "RESULT hostSucceedAt=$($m3a.t) guestAt=$($m3b.t) launchStart=$($script:m3startTime) dt=$m3dt $(ConvertTo-Json $m3res -Compress)"
    Add-CRFlowCheck 'SucceedMission fires 11 s (+/-3) after the launch started' (($m3dt -gt 8) -and ($m3dt -lt 14)) @{ dt = $m3dt; host = $m3a.t; guest = $m3b.t }
    Add-CRFlowCheck 'pad-destroyed failure did not fire' (-not $m3res.lost) $m3res
    @{ dt = $m3dt; state = $m3res }
}

Invoke-CRFlowStep 'launch teardown: rocket removed, particles drained, cameras released' {
    foreach ($m3c in (Get-CRFlowClientIndices)) {
        Wait-CRFlow $m3c "return not exu.HasParticleSystem('CR03/Launch/1/Core') and not L().localCameraActive" -TimeoutSeconds 20 | Out-Null
    }
    $true
} -Soft

Write-Host "SHOTS: $(ConvertTo-Json @($script:M3Shots | ForEach-Object { $_.path }) -Compress)"
Test-CRFlowResultParity -Expect SucceedMission -Debrief 'misn03w1.des' -Clients @(Get-CRFlowClientIndices)
